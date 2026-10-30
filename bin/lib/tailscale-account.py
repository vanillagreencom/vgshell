"""Tailscale system transactions, called only by vgshell-system under its lock.

The caller owns consent and the TUI sudo session. This unprivileged owner keeps
that session through login, child reaping, verification and recovery. It opens
the browser as the desktop user; no authentication address enters a transcript.
"""

import json
import os
import re
import selectors
import shlex
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import urlsplit


PREFIX = ""
COMMAND_TIMEOUT = 15
LOGIN_TIMEOUT = 300
ADDRESS_TIMEOUT = 30
NAME = re.compile(r"[a-z_][a-z0-9_-]*\$?", re.ASCII)
PROFILE = re.compile(r"[0-9a-f]+", re.ASCII)


class Refused(Exception):
    pass


def program(name):
    path = shutil.which(name)
    if not path or not path.startswith("/"):
        raise Refused("command-missing")
    return path


class Transaction:
    def __init__(self):
        self.uid = os.getuid()
        self.user = subprocess.check_output([program("id"), "-un"], text=True).strip()
        if self.uid == 0 or not NAME.fullmatch(self.user):
            raise Refused("user-unsupported")
        self.sudo = program("sudo")
        self.tailscale = program("tailscale")
        self.directory = Path(PREFIX + "/var/lib/vgshell/system")
        self.cancelled = False
        self.recovering = False
        for signum in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
            signal.signal(signum, self.cancel)
        # Root commands never inherit the desktop bus or a user-selected PATH.
        self.root_env = {"PATH": os.environ["PATH"], "LC_ALL": "C"}

    def cancel(self, signum, frame):
        self.cancelled = True

    def check_cancel(self):
        if self.cancelled and not self.recovering:
            raise Refused("cancelled")

    def run(self, argv, *, root=True, data=None, timeout=COMMAND_TIMEOUT):
        self.check_cancel()
        if root:
            argv = [self.sudo, "--", *argv]
            print(shlex.join(argv), flush=True)
        try:
            with subprocess.Popen(argv, stdin=subprocess.PIPE if data is not None else subprocess.DEVNULL,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  env=self.root_env if root else self.browser_env()) as child:
                try:
                    deadline = time.monotonic() + timeout
                    first = True
                    while True:
                        self.check_cancel()
                        remaining = deadline - time.monotonic()
                        if remaining <= 0:
                            raise Refused("command-timeout")
                        try:
                            out, _ = child.communicate(data if first else None, timeout=min(0.1, remaining))
                            break
                        except subprocess.TimeoutExpired:
                            first = False
                except Refused:
                    child.terminate()
                    try:
                        child.communicate(timeout=2)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        child.communicate()
                    raise
                if child.returncode:
                    raise Refused("command-failed")
        except OSError:
            raise Refused("command-start") from None
        self.check_cancel()
        return out.decode("utf-8")

    def ts(self, *args):
        return self.run([self.tailscale, *args])

    def json_ts(self, *args):
        try:
            return json.loads(self.ts(*args))
        except (ValueError, UnicodeError):
            raise Refused("daemon-report") from None

    def profile(self):
        # v1.104.1 cli/switch.go's listProfilesJSON emits a list, including []
        # when there are no saved profiles. A selected empty profile is not in
        # that list. Confirm signed-out daemon state before treating a report
        # with no selection as no previous profile, even when other saves exist.
        rows = self.json_ts("switch", "--list", "--json")
        if not isinstance(rows, list):
            raise Refused("profile-report")
        ids = set()
        selected = []
        for row in rows:
            if (not isinstance(row, dict) or not isinstance(row.get("id"), str)
                    or not PROFILE.fullmatch(row["id"]) or row["id"] in ids
                    or type(row.get("selected")) is not bool):
                raise Refused("profile-report")
            ids.add(row["id"])
            if row["selected"]:
                selected.append(row["id"])
        if len(selected) > 1:
            raise Refused("profile-selection")
        if not selected:
            status = self.json_ts("status", "--json")
            if not isinstance(status, dict) or status.get("BackendState") not in ("NeedsLogin", "NoState"):
                raise Refused("profile-selection")
        return selected[0] if selected else ""

    def preferences(self):
        # `status --json` does not expose WantRunning. The CLI's debug prefs
        # calls LocalClient.GetPrefs and emits its JSON (v1.104.1 debug.go,
        # runPrefs). Read only connection intent, never print the report or
        # read tailscaled's private state. A changed format refuses preflight.
        prefs = self.json_ts("debug", "prefs")
        if not isinstance(prefs, dict) or type(prefs.get("WantRunning")) is not bool:
            raise Refused("preferences-report")
        return prefs["WantRunning"]

    def operator(self):
        operator = self.ts("get", "operator").strip()
        if operator and not NAME.fullmatch(operator):
            raise Refused("operator-report")
        return operator

    def trusted(self, path):
        if path.is_symlink():
            raise Refused("record-untrusted")
        try:
            owner, mode = subprocess.check_output(
                [program("stat"), "-c", "%u %a", "--", str(path)], text=True).split()
        except (OSError, subprocess.CalledProcessError, ValueError):
            raise Refused("record-unreadable") from None
        if owner != "0" or int(mode, 8) & 0o022:
            raise Refused("record-untrusted")

    def read_record(self, name):
        self.trusted(self.directory)
        path = self.directory / name
        if not path.exists() and not path.is_symlink():
            return None
        self.trusted(path)
        if not path.is_file():
            raise Refused("record-untrusted")
        text = path.read_text()
        if name == "tailscale-operator" and not text.startswith("{"):
            # D107: no historical profile identity can be reconstructed from
            # uid/operator/previous. Retain that grant as unbound; it never
            # authorizes undo on whichever account happens to be selected.
            legacy = {}
            for line in text.splitlines():
                key, sep, value = line.partition("=")
                if not sep or key in legacy:
                    raise Refused("record-malformed")
                legacy[key] = value
            if (set(legacy) != {"uid", "operator", "previous"}
                    or not legacy["uid"].isdigit()
                    or not NAME.fullmatch(legacy["operator"])
                    or (legacy["previous"] and not NAME.fullmatch(legacy["previous"]))):
                raise Refused("record-malformed")
            record = {"version": 2, "uid": int(legacy["uid"]), "profiles": {},
                      "unbound": {"operator": legacy["operator"], "previous": legacy["previous"]}}
            self.validate_record(name, record)
            self.write_record(name, record)
            return record
        try:
            record = json.loads(text)
        except ValueError:
            raise Refused("record-malformed") from None
        self.validate_record(name, record)
        return record

    def validate_record(self, name, record):
        if not isinstance(record, dict) or record.get("version") != 2 or type(record.get("uid")) is not int:
            raise Refused("record-malformed")
        if record["uid"] != self.uid:
            raise Refused("record-other-uid")
        if name == "tailscale-account-add":
            if (set(record) != {"version", "uid", "profile", "running", "operator"}
                    or not isinstance(record["profile"], str)
                    or (record["profile"] and not PROFILE.fullmatch(record["profile"]))
                    or type(record["running"]) is not bool
                    or not isinstance(record["operator"], str)
                    or (record["operator"] and not NAME.fullmatch(record["operator"]))):
                raise Refused("record-malformed")
            return
        if set(record) - {"version", "uid", "profiles", "unbound"} or not isinstance(record.get("profiles"), dict):
            raise Refused("record-malformed")
        entries = list(record["profiles"].values())
        if "unbound" in record:
            entries.append(record["unbound"])
        for profile in record["profiles"]:
            if not PROFILE.fullmatch(profile):
                raise Refused("record-malformed")
        for entry in entries:
            if (not isinstance(entry, dict) or set(entry) != {"operator", "previous"}
                    or not isinstance(entry["operator"], str) or not NAME.fullmatch(entry["operator"])
                    or not isinstance(entry["previous"], str)
                    or (entry["previous"] and not NAME.fullmatch(entry["previous"]))):
                raise Refused("record-malformed")

    def write_record(self, name, record):
        self.validate_record(name, record)
        destination = self.directory / name
        temporary = self.directory / ("." + name)
        for path in (destination, temporary):
            if path.exists() or path.is_symlink():
                self.trusted(path)
        self.run([program("tee"), "--", str(temporary)], data=(json.dumps(record) + "\n").encode())
        self.run([program("mv"), "-fT", "--", str(temporary), str(destination)])

    def drop_record(self, name):
        self.run([program("rm"), "-f", "--", str(self.directory / name)])

    def grants(self):
        return self.read_record("tailscale-operator") or {"version": 2, "uid": self.uid, "profiles": {}}

    def grant(self, profile, previous):
        if not profile:
            raise Refused("profile-missing")
        record = self.grants()
        if profile not in record["profiles"]:
            record["profiles"][profile] = {"operator": self.user, "previous": previous}
        self.write_record("tailscale-operator", record)

    def browser_env(self):
        # The helper never elevates itself. Select the desktop inputs instead
        # of forwarding terminal/session credentials and arbitrary overrides.
        keys = ("HOME", "USER", "LOGNAME", "LANG", "XDG_RUNTIME_DIR", "WAYLAND_DISPLAY",
                "DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "XDG_CURRENT_DESKTOP", "XDG_SESSION_TYPE",
                "XDG_CONFIG_HOME", "XDG_DATA_HOME")
        return {"PATH": os.environ["PATH"], **{key: os.environ[key] for key in keys if key in os.environ}}

    def login(self):
        self.check_cancel()
        # v1.104.1 newUpFlagSet registers --json for up only. Login's private
        # text is drained, never interpreted or logged; the same bounded wait
        # reads public Status.AuthURL/HaveNodeKey instead (ipnstate.Status).
        argv = [self.sudo, "--", self.tailscale, "login", "--operator=" + self.user, "--timeout", "0"]
        print(shlex.join(argv), flush=True)
        try:
            child = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, env=self.root_env)
        except OSError:
            raise Refused("login-start") from None
        opened = False
        began = False
        next_status = 0
        start = time.monotonic()
        try:
            with selectors.DefaultSelector() as reader:
                reader.register(child.stdout, selectors.EVENT_READ)
                while True:
                    self.check_cancel()
                    now = time.monotonic()
                    if now - start >= LOGIN_TIMEOUT:
                        raise Refused("login-timeout")
                    for key, _ in reader.select(0.1):
                        block = os.read(key.fd, 4096)
                        if not block:
                            reader.unregister(child.stdout)
                        else:
                            # login.go switches to its empty profile before
                            # runUp can print. Do not open a prior AuthURL before
                            # this owned CLI has reached that transaction phase.
                            began = True
                    if began and now >= next_status:
                        report = self.json_ts("status", "--json")
                        if (not isinstance(report, dict) or not isinstance(report.get("AuthURL"), str)
                                or not isinstance(report.get("BackendState"), str)):
                            raise Refused("daemon-report")
                        next_status = time.monotonic() + 0.5
                        url = report["AuthURL"]
                        if url and not opened:
                            if any(ord(char) <= 32 or ord(char) == 127 for char in url):
                                raise Refused("login-address-invalid")
                            parsed = urlsplit(url)
                            if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
                                raise Refused("login-address-invalid")
                            try:
                                self.run([program("xdg-open"), url], root=False)
                            except Refused:
                                self.check_cancel()
                                raise Refused("browser-open") from None
                            opened = True
                            print("Complete sign-in in your browser. Press Ctrl-C here to cancel.", flush=True)
                        if report["BackendState"] == "NeedsMachineAuth" and report.get("HaveNodeKey") is True:
                            return
                    result = child.poll()
                    if result is not None and not reader.get_map():
                        if result:
                            raise Refused("login-refused")
                        if not opened:
                            raise Refused("login-address-missing")
                        return
                    if not opened and time.monotonic() - start >= ADDRESS_TIMEOUT:
                        raise Refused("login-address-missing")
        finally:
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    child.kill()
            child.wait()
            child.stdout.close()

    def recover(self, saved):
        self.recovering = True
        try:
            if saved["profile"]:
                # switch can return failure for an intentionally stopped
                # profile. Selection and intent readback are authoritative.
                try:
                    self.ts("switch", saved["profile"])
                except Refused:
                    if self.profile() != saved["profile"]:
                        raise
                if self.profile() != saved["profile"]:
                    raise Refused("recovery-selection")
                if self.preferences() != saved["running"]:
                    self.ts("up" if saved["running"] else "down")
                if self.preferences() != saved["running"] or self.operator() != saved["operator"]:
                    raise Refused("recovery-access")
                status = self.json_ts("status", "--json")
                if not isinstance(status, dict) or (saved["running"] and status.get("BackendState") != "Running"):
                    raise Refused("recovery-connection")
                state = "recovered"
            else:
                self.ts("logout")
                status = self.json_ts("status", "--json")
                if self.profile() or not isinstance(status, dict) or status.get("BackendState") not in ("NeedsLogin", "NoState"):
                    raise Refused("recovery-signed-out")
                state = "signed-out"
            self.drop_record("tailscale-account-add")
            return state
        finally:
            self.recovering = False

    def add(self):
        pending = self.read_record("tailscale-account-add")
        if pending:
            try:
                state = self.recover(pending)
            except Refused:
                raise Refused("recovery-failed") from None
            print("vgs-system: account-add state=" + state + " reason=recovery-retry", flush=True)
            return 1
        previous = self.profile()
        running = self.preferences()
        operator = self.operator()
        if operator and operator != self.user:
            raise Refused("operator-other")
        self.grants()  # Migrate before any profile change.
        saved = {"version": 2, "uid": self.uid, "profile": previous, "running": running, "operator": operator}
        self.write_record("tailscale-account-add", saved)
        try:
            self.login()
            current = self.profile()
            status = self.json_ts("status", "--json")
            if not current or current == previous or self.operator() != self.user:
                raise Refused("login-verification")
            # local.go's updateStatusLocked fills Self.ID only with a netmap.
            # Device approval can precede that map; HaveNodeKey is the daemon's
            # independent credential reading, and no network-ready claim follows.
            if (not isinstance(status, dict) or status.get("BackendState") not in ("Running", "NeedsMachineAuth")
                    or status.get("HaveNodeKey") is not True):
                raise Refused("login-verification")
            self.grant(current, "")
            self.drop_record("tailscale-account-add")
        except (Refused, OSError, ValueError) as error:
            reason = str(error) if isinstance(error, Refused) else "transaction-io"
            try:
                state = self.recover(saved)
            except (Refused, OSError, ValueError):
                raise Refused("recovery-failed") from None
            print("vgs-system: account-add state=" + state + " reason=" + reason, flush=True)
            return 130 if reason == "cancelled" else 1
        if status["BackendState"] == "NeedsMachineAuth":
            print("vgs-system: account-add state=needs-approval reason=device-approval", flush=True)
            print("The account was added. Its administrator must approve this device before it can connect.", flush=True)
        else:
            print("ok system=tailscale-account-add state=ready", flush=True)
        return 0

    def operator_step(self, undo):
        profile = self.profile()
        operator = self.operator()
        record = self.grants()
        if undo:
            entry = record["profiles"].get(profile)
            if entry is None:
                if "unbound" in record:
                    raise Refused("record-profile-unbound")
                print("ok system=tailscale-operator state=untouched", flush=True)
                return 0
            if operator == entry["operator"]:
                self.ts("set", "--operator=" + entry["previous"])
                if self.operator() != entry["previous"]:
                    raise Refused("operator-verification")
            del record["profiles"][profile]
            self.write_record("tailscale-operator", record)
            print("ok system=tailscale-operator state=undone", flush=True)
        else:
            if operator and operator != self.user:
                raise Refused("operator-other")
            self.grant(profile, operator)
            self.ts("set", "--operator=" + self.user)
            if self.profile() != profile or self.operator() != self.user:
                raise Refused("operator-verification")
            print("ok system=tailscale-operator state=ready", flush=True)
        return 0


def main():
    try:
        transaction = Transaction()
        if sys.argv[1:] == ["add"]:
            return transaction.add()
        if sys.argv[1:] in (["operator"], ["undo-operator"]):
            return transaction.operator_step(sys.argv[1] == "undo-operator")
        raise Refused("invocation")
    except (Refused, OSError, ValueError, UnicodeError) as error:
        reason = str(error) if isinstance(error, Refused) else "transaction-io"
        print("vgs-system: refused: account=" + reason, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
