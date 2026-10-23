# Sourced by scripts/sandbox-shots.sh, scripts/smoke/harness.sh and
# scripts/test-smoke-display-record.sh; defines display_record_program, the
# display recorder the harness runs.
set -euo pipefail

# The harness runs this program as one of its owned process groups. Linux
# notifications wake readers of owned original logs. It never writes
# producer logs. The record limit is a storage policy, not a measured budget.
display_record_program() {
  cat <<'PY'
import collections
import array
import contextlib
import ctypes
import fcntl
import json
import math
import os
import pathlib
import re
import resource
import selectors
import signal
import shutil
import socket
import stat
import struct
import subprocess
import sys
import termios
import time

CAP_EVENTS = 65536
CAP_BYTES = 67108864
CAP_LINE = 1048576
CAP_STREAMS = 128
PREFIX = b"VGS_DISPLAY_EVENT "
IN_MODIFY = 0x00000002
IN_ATTRIB = 0x00000004
IN_CLOSE_WRITE = 0x00000008
IN_MOVE_SELF = 0x00000800
IN_DELETE_SELF = 0x00000400
IN_UNMOUNT = 0x00002000
IN_Q_OVERFLOW = 0x00004000
IN_IGNORED = 0x00008000
# Public Linux inotify API, verified against the Linux man-pages project:
# https://man7.org/linux/man-pages/man7/inotify.7.html
# Events coalesce and identify neither the writer nor its clock. Watches
# only wake an offset reader; they are never write counts or PID evidence.
LIBC = ctypes.CDLL(None, use_errno=True)
LIBC.inotify_init1.argtypes = [ctypes.c_int]
LIBC.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
LIBC.inotify_rm_watch.argtypes = [ctypes.c_int, ctypes.c_int]

def checked(value):
    if value < 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))
    return value

def finite_number(value):
    return type(value) in (int, float) and (type(value) is int or math.isfinite(value))

def probe_float(text):
    value = float(text)
    if not math.isfinite(value):
        raise ValueError("non-finite Probe number")
    return value

def probe_constant(text):
    raise ValueError("non-JSON Probe constant: " + text)

def process_completion(value):
    return (isinstance(value, dict) and type(value.get("code")) is int
            and type(value.get("status")) is int)

def process_binding(pid):
    # Identity snapshots, never event history. Linux starttime is field22
    # in boot-relative ticks; stdout is fd1. Read around the descriptor
    # snapshot to refuse a changed process. These are not helper identities.
    # https://man7.org/linux/man-pages/man5/proc_pid_stat.5.html
    # https://man7.org/linux/man-pages/man5/proc_pid_fd.5.html
    if not re.fullmatch(r"[1-9][0-9]*", pid):
        raise ValueError("owner-pid-invalid")
    path = pathlib.Path("/proc") / pid
    try:
        before = (path / "stat").read_text().rsplit(")", 1)[1].split()
        if before[0] in ("Z", "X", "x"):
            return dict(status="ended", startTicks=before[19])
        stdout = (path / "fd/1").stat()
        after = (path / "stat").read_text().rsplit(")", 1)[1].split()
        if before[19] != after[19]:
            return dict(status="changed")
        return dict(status="live", startTicks=after[19], stdout=[stdout.st_dev, stdout.st_ino])
    except FileNotFoundError:
        return dict(status="gone") if not path.exists() else dict(status="unavailable", error="identity-component-missing")
    except (OSError, IndexError, ValueError) as error:
        return dict(status="unavailable", error=str(error))

@contextlib.contextmanager
def socket_name(path):
    # sun_path holds 108 bytes (unix(7)), and the record directory under a
    # long checkout path exceeds it. The directory's /proc/self/fd link names
    # the same directory in a few bytes (proc_pid_fd(5)).
    path = pathlib.Path(path)
    directory = os.open(path.parent, os.O_PATH | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        yield f"/proc/self/fd/{directory}/{path.name}"
    finally:
        os.close(directory)

def request(path, command, *args):
    with socket.socket(socket.AF_UNIX, socket.SOCK_SEQPACKET) as client:
        with socket_name(path) as name:
            client.connect(name)
        client.sendall(json.dumps([command, *args]).encode())
        reply = json.loads(client.recv(CAP_LINE))
        if not reply["ok"]:
            raise RuntimeError(reply["error"])
        return reply.get("value", "ok")

def read_record(path):
    # A killed writer can leave no terminal or an incomplete final JSON
    # line. Retention and downstream readers must never promote either.
    try:
        with open(path, "rb") as file:
            data = file.read(CAP_BYTES + CAP_LINE + 1)
        if len(data) > CAP_BYTES + CAP_LINE:
            return dict(localRecord="incomplete", problems=["record:overflow"])
        if not data.endswith(b"\n"):
            return dict(localRecord="incomplete", problems=["record:partial-final-record"])
        events = [json.loads(line) for line in data.splitlines()]
        if not events or events[-1].get("kind") != "terminal":
            return dict(localRecord="incomplete", problems=["record:terminal-missing"])
        return events[-1]["data"]
    except (OSError, ValueError, KeyError, TypeError) as error:
        return dict(localRecord="incomplete", problems=["record:unreadable"], error=str(error))

def retain_record(directory, sandbox, runtime, home):
    destination = pathlib.Path(directory)
    roots = ((pathlib.Path(sandbox), "logs/sandbox", "*.log"),
             (pathlib.Path(runtime) / "hypr", "logs/hypr", "*"),
             (pathlib.Path(runtime) / "quickshell", "logs/quickshell", "*"),
             (pathlib.Path(home) / ".config", "configuration", "*"),
             (pathlib.Path(home) / ".local/state/vgshell/hypr", "layer", "*"),
             (pathlib.Path(home) / ".local/state/vgshell/display-trials", "display-trials", "*"))
    problems = []
    for root, target, pattern in roots:
        for path in root.rglob(pattern):
            # Runtime directories also contain sockets and symlinks to the
            # same log. Copy owned regular files only, after producers end.
            if path.is_symlink() or not path.is_file():
                continue
            output = destination / target / path.relative_to(root)
            try:
                output.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, output)
            except OSError as error:
                problems.append(dict(path=str(path), error=str(error)))
    (destination / "retention.json").write_text(json.dumps(dict(
        state="incomplete" if problems else "complete", problems=problems)) + "\n")

def complete_record(directory, finalizer_errors):
    root = pathlib.Path(directory)
    summary = read_record(root / "events.jsonl")
    problems = list(summary.get("problems", []))
    if finalizer_errors != "0":
        problems.append("finalizer:failed")
    if (root / "request-failed").exists():
        problems.append("control:client-request-failed")
    try:
        retention = json.loads((root / "retention.json").read_text())
        if retention["state"] != "complete":
            problems.append("retention:incomplete")
    except (OSError, ValueError, KeyError, TypeError):
        problems.append("retention:unavailable")
    summary["problems"] = problems
    if problems:
        summary["localRecord"] = "incomplete"
    (root / "completeness.json").write_text(json.dumps(summary) + "\n")
    (root / "finalization.json").write_text(json.dumps(dict(
        state="failed" if finalizer_errors != "0" else "finished", errors=finalizer_errors)) + "\n")

class Record:
    def __init__(self, directory):
        self.directory = pathlib.Path(directory)
        self.output = (self.directory / "events.jsonl").open("xb", buffering=0)
        self.selector = selectors.DefaultSelector()
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_SEQPACKET)
        with socket_name(self.directory / "control") as name:
            self.server.bind(name)
        self.server.listen()
        self.selector.register(self.server, selectors.EVENT_READ, ("control", None))
        self.sequences = collections.Counter()
        self.receipts = 0
        self.bytes = 0
        self.events = 0
        self.problems = set()
        self.streams = {}
        self.next_stream = 0
        self.log_watches = {}
        self.log_history = {}
        self.registrations = {}
        self.launches = []
        self.owner_contexts = {}
        self.shell_owners = {}
        self.layer_stops = {}
        self.layer_signature = None
        self.layer_bound = None
        self.next_context = 0
        self.scope = None
        self.display_registration = None
        self.read_bytes = collections.Counter()
        self.notify_fd = None
        try:
            self.notify_fd = checked(LIBC.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC))
            self.selector.register(self.notify_fd, selectors.EVENT_READ, ("notify", None))
        except OSError as error:
            self.problems.add("notification:unavailable:" + str(error))
        self.probe_states = {}
        self.probe_sequences = {}
        self.shell_pids = {}
        self.observations = set()
        self.fact_counts = collections.Counter()
        self.request_counts = collections.Counter()
        self.monitor_counts = collections.Counter()
        self.bound = False
        self.configure_seen = False
        self.stopping = False
        self.closed = False
        self.stop_reason = "interrupted"
        self.input_span = None
        self.emit("recorder", "arm", {
            "schema": "vgs.display-record.v1", "run": self.directory.name,
            "capacityEvents": CAP_EVENTS, "capacityBytes": CAP_BYTES,
            "capacityLineBytes": CAP_LINE, "capacityStreams": CAP_STREAMS,
            "terminalReserve": "one terminal outside ordinary event/byte caps; bounded by CAP_LINE reader allowance",
            "probeLimits": {"eventsIncludingTerminal": 4096, "aggregateJsonUtf16Chars": 16777216, "terminalReserveJsonChars": 4096},
            "clocks": {"receiptRealtimeNs": "time.time_ns CLOCK_REALTIME",
                       "receiptMonotonicNs": "time.monotonic_ns CLOCK_MONOTONIC",
                       "probeRealtimeMs": "Date.now from Probe; wall clock can change",
                       "wayland": "raw libwayland diagnostic timestamp; consulted formatter uses wrapping realtime microseconds; no conversion or clock calibration"},
            "order": "receipt sequence orders reader delivery only; sourceSequence preserves each input stream; no cross-stream causal order",
            "limits": "socket2 has no producer timestamp, replay, arm acknowledgement or terminal marker; upstream loss is unobservable; inotify coalesces and has no writer PID or write timestamp; independent writers and seek/overwrite history cannot be proved absent; notification and buffering delay receipt; collection consumes CPU and disk bandwidth",
            "logHistory": "single acquired original regular-log writer inherited by actual launch; byte offsets preserve local order; reuse requires prior local owner end and new empty acquisition; unexpected truncate, replacement or notification overflow make history incomplete; close-write is context only; ordinary readers do not end observation",
            "diagnosticBinding": "owned nested launch original regular log with WAYLAND_DEBUG=client; diagnostic text has no connection identity; inherited child diagnostic output is not independently attributed",
            "validity": "collector terminal describes local receipt only; completeness.json also requires successful finalization and retention",
            "helperLaunchIdentity": "unresolved separate input"})
        with (self.directory / "ready").open("w") as ready:
            ready.write("ready\n")

    def emit(self, source, kind, data, terminal=False):
        self.sequences[source] += 1
        self.receipts += 1
        event = dict(receiptSequence=self.receipts, source=source,
                     sourceSequence=self.sequences[source], kind=kind,
                     receiptRealtimeNs=time.time_ns(), receiptMonotonicNs=time.monotonic_ns(), data=data)
        if self.input_span is not None and source == self.input_span["source"]:
            event["inputFileBytes"] = self.input_span
        text = (json.dumps(event, separators=(",", ":")) + "\n").encode()
        if terminal and len(text) > CAP_LINE:
            # A terminal has a finite reserved allowance. Lost summary
            # detail cannot become a complete record.
            event["data"] = dict(localRecord="incomplete", problems=["terminal:overflow"],
                                 observationCost=data.get("observationCost"),
                                 detail="terminal summary exceeded reserved line capacity")
            text = (json.dumps(event, separators=(",", ":")) + "\n").encode()
        if not terminal and (self.events >= CAP_EVENTS or self.bytes + len(text) > CAP_BYTES):
            self.problems.add("overflow")
            return
        self.output.write(text)
        self.bytes += len(text)
        self.events += 1

    def subscribe(self, source, path):
        if len(self.streams) >= CAP_STREAMS:
            raise ValueError("capacity-streams")
        sock = socket.socket(socket.AF_UNIX)
        try:
            sock.connect(path)
        except OSError as error:
            sock.close()
            self.problems.add(source + ":missing")
            self.emit(source, "missing", {"path": path, "error": str(error)})
            return
        sock.setblocking(False)
        self.streams[sock] = dict(source=source, buffer=b"", kind="ipc", log=None, clipped=False, ended=False)
        self.selector.register(sock, selectors.EVENT_READ, ("stream", sock))
        self.emit(source, "connected", {"socket": path, "subscriptionAcknowledgement": "unavailable"})

    def watch_log(self, kind, path, acquired):
        if self.notify_fd is None:
            raise ValueError("notification-unavailable")
        if len(self.streams) >= CAP_STREAMS:
            raise ValueError("capacity-streams")
        if self.next_stream >= CAP_EVENTS:
            raise ValueError("capacity-registrations")
        if not re.fullmatch(r"/proc/[0-9]+/fd/[0-9]+", acquired):
            raise ValueError("log-acquisition-unbound")
        fd = os.open(acquired, os.O_RDONLY | os.O_CLOEXEC)
        try:
            info = os.fstat(fd)
            named = os.stat(path, follow_symlinks=False)
            identity = (info.st_dev, info.st_ino)
            reused = identity in self.log_history
            if not stat.S_ISREG(info.st_mode) or identity != (named.st_dev, named.st_ino):
                raise ValueError("log-identity-ambiguous")
            if identity in self.log_history and not self.log_history[identity]:
                raise ValueError("log-inode-overlap-or-unproved-reuse")
            if info.st_size != 0:
                raise ValueError("log-initial-history-missing")
            wd = checked(LIBC.inotify_add_watch(self.notify_fd, os.fsencode("/proc/self/fd/" + str(fd)),
                         IN_MODIFY | IN_ATTRIB | IN_CLOSE_WRITE | IN_MOVE_SELF | IN_DELETE_SELF))
            if wd in self.log_watches:
                raise ValueError("log-watch-ambiguous")
            self.next_stream += 1
            source = kind + ":log-" + str(self.next_stream)
            registration = dict(key=source, state="pending", fd=fd, kind=kind,
                                path=path, identity=identity, launch=None, required=False)
            self.registrations[source] = registration
            self.streams[fd] = dict(source=source, kind=kind, buffer=b"", clipped=False, ended=False,
                                    path=path, identity=identity, wd=wd, offset=0, valid=True,
                                    registration=registration, log=None)
            self.log_watches[wd] = fd
            self.log_history[identity] = False
            self.emit("harness", "log-binding", dict(source=source, path=path, acquiredWriter=acquired,
                      device=info.st_dev, inode=info.st_ino, offset=0, generation=self.next_stream,
                      reuseBoundary="prior-local-owner-end" if reused else "new-empty-acquisition"))
            return source
        except BaseException:
            os.close(fd)
            raise

    def launched(self, kind, key, pid, path):
        if len(self.launches) >= CAP_EVENTS:
            raise ValueError("capacity-launches")
        registration = None
        tag = "expected-refused"
        if key != "refused":
            registration = self.registrations.get(key)
            if registration is None or registration["state"] != "pending":
                raise ValueError("launch-registration-missing-or-used")
            if registration["kind"] != kind or registration["path"] != path:
                raise ValueError("launch-registration-mismatch")
            tag = "registered"
        else:
            self.problems.add("launch:expected-registration-refused")
        launch = dict(key="launch-" + str(len(self.launches) + 1), tag=tag,
                      pid=pid, kind=kind, registration=key if registration else None,
                      path=path, identity=process_binding(pid), ended=False)
        self.launches.append(launch)
        if registration is not None:
            registration["state"] = "bound"
            registration["launch"] = launch
        self.emit("harness", "actual-launch", launch)

    def resolve_owner(self, pid):
        snapshot = process_binding(pid)
        candidates = [launch for launch in self.launches if launch["pid"] == pid
                      and launch["kind"] == "probe" and not launch["ended"]]
        matched = []
        for launch in candidates:
            original = launch["identity"]
            if snapshot["status"] == "gone":
                matched.append(launch)
            elif snapshot["status"] in ("live", "ended") and original.get("startTicks") == snapshot.get("startTicks"):
                if launch["tag"] == "expected-refused" or snapshot["status"] == "ended":
                    matched.append(launch)
                elif tuple(snapshot["stdout"]) == self.registrations[launch["registration"]]["identity"]:
                    matched.append(launch)
        if len(matched) > 1:
            raise ValueError("owner-generation-ambiguous")
        if matched:
            launch = matched[0]
            return dict(tag=launch["tag"], pid=pid, launch=launch["key"],
                        registration=launch["registration"], snapshot=snapshot)
        if candidates and (snapshot["status"] in ("unavailable", "changed") or
                           any("startTicks" not in launch["identity"] for launch in candidates)):
            self.problems.add("owner:expected-binding-unavailable")
            return dict(tag="expected-unverified", pid=pid, snapshot=snapshot)
        return dict(tag="unobserved-adoption", pid=pid, snapshot=snapshot,
                    reason="no issued Probe registration proves this current runner; snapshots are context only")

    def owner_context(self, pid):
        if self.next_context >= CAP_EVENTS:
            raise ValueError("capacity-owner-contexts")
        context = self.resolve_owner(pid)
        self.next_context += 1
        key = "owner-" + str(self.next_context)
        self.owner_contexts[key] = context
        self.emit("harness", "owner-context", dict(key=key, **context))
        return key

    def end_owner(self, key, pid):
        context = self.owner_contexts.get(key)
        if context is None:
            raise ValueError("owner-context-missing-or-ended")
        if context["pid"] != pid:
            raise ValueError("owner-end-wrong-pid")
        if "stopShell" in context:
            self.shell_owners[context["stopShell"]]["stop"] = key
            context["layerStop"] = self.layers_report(self.layers_query(), context["stopShell"])
            context["layerStop"].update(stop=key, instance=context["stopInstance"])
            context["layerStop"].pop("raw", None)
            context["layerStop"]["layers"] = [l for l in context["layerStop"]["layers"] if str(l["pid"]) == context["stopShell"]]
            for layer in context["layerStop"]["layers"]:
                if len(self.layer_stops) < CAP_EVENTS:
                    self.layer_stops[layer["address"]] = dict(layer, stop=key, instance=context["stopInstance"])
                else:
                    self.problems.add("layers:capacity")
            context["layerStop"]["stillListed"] = (any(str(l["pid"]) == context["stopShell"] for l in context["layerStop"]["layers"])
                                                    if context["layerStop"]["status"] == "read" else "unreadable")
        if context["tag"] == "registered":
            registration = self.registrations[context["registration"]]
            launch = registration["launch"]
            if registration["state"] != "bound" or launch["key"] != context["launch"] or launch["pid"] != pid:
                raise ValueError("owner-end-wrong-generation")
            after = process_binding(pid)
            if after["status"] not in ("gone", "ended"):
                raise ValueError("owner-end-not-ended-or-unavailable")
            if after["status"] == "ended" and after.get("startTicks") != context["snapshot"].get("startTicks"):
                raise ValueError("owner-end-generation-changed")
            fd = registration["fd"]
            self.read_file(fd)
            registration["state"] = "local-ended"
            launch["ended"] = True
            self.emit(registration["key"], "local-owner-end", dict(namespaceRunner=pid,
                      launch=launch["key"], registration=registration["key"],
                      action="stop_shell instance-lock wait and runner wait/reap",
                      limit="local observation end; not proof that every inherited writer exited",
                      layerStop=context.get("layerStop", {"status": "unobserved"}),
                      offset=self.streams[fd]["offset"]))
            if not registration["required"]:
                self.retire_log(fd, "local-owner-end")
        elif context["tag"] == "unobserved-adoption":
            self.emit("harness", "unobserved-adoption-end", context)
        elif context["tag"] in ("expected-refused", "expected-unverified"):
            self.problems.add("owner:expected-observation-unavailable")
            self.emit("harness", "expected-observation-unavailable", context)
            if context["tag"] == "expected-refused":
                for launch in self.launches:
                    if launch["key"] == context["launch"]:
                        launch["ended"] = True
        else:
            raise ValueError("owner-context-invalid-state")
        del self.owner_contexts[key]

    def layers_query(self):
        # Advisory native query by this observer. Its serial wait and child
        # cost are outside terminal observationCost's collector-only claim.
        if self.layer_signature is None or self.layer_bound is None:
            return "unreadable:unbound-compositor"
        try:
            result = subprocess.run(["hyprctl", "-i", self.layer_signature, "-j", "layers"],
                env={k: os.environ[k] for k in ("PATH", "XDG_RUNTIME_DIR") if k in os.environ},
                capture_output=True, timeout=self.layer_bound, check=False)
            return result.stdout.decode() if result.returncode == 0 else "unreadable:hyprctl-exit=" + str(result.returncode)
        except (OSError, ValueError, TypeError, subprocess.TimeoutExpired) as error:
            return "unreadable:" + str(error)

    def layers_report(self, raw, current, probe="[]"):
        report = dict(status="read", layers=[], raw=raw)
        try:
            hosts = json.loads(probe)
            host_keys = {(h["screen"], h["namespace"]) for h in hosts}
        except (ValueError, KeyError, TypeError, AttributeError):
            host_keys = set()
            report["probeStatus"] = "unreadable"
        try:
            for screen, monitor in json.loads(raw).items():
                for level in monitor["levels"].values():
                    for layer in level:
                        if layer["pid"] == -1:
                            continue
                        pid, address = str(layer["pid"]), layer["address"]
                        snapshot = process_binding(pid)
                        owner = self.shell_owners.get(pid, {"status": "unobserved"})
                        stopped = self.layer_stops.get(address, {})
                        if str(stopped.get("pid")) != pid:
                            stopped = {}
                        original = stopped.get("instance", {}).get("snapshot", {})
                        if snapshot.get("startTicks") and original.get("startTicks") and snapshot["startTicks"] != original["startTicks"]:
                            stopped = {}
                        identity = owner.get("identity", {})
                        reused = snapshot.get("startTicks") is not None and identity.get("startTicks") is not None and snapshot["startTicks"] != identity["startTicks"]
                        if reused:
                            owner = dict(status="pid-reused", pid=pid, previous=owner)
                        report["layers"].append(dict(address=address, namespace=layer["namespace"], screen=screen, pid=layer["pid"],
                            liveness=snapshot, instance=stopped.get("instance", owner), stop=stopped.get("stop", owner.get("stop", "none")),
                            identityMatch="changed" if reused else "unavailable" if not identity else "matched-or-ended",
                            hostOwner=pid == current and (screen, layer["namespace"]) in host_keys,
                            ownershipMismatch=pid != current and (screen, layer["namespace"]) in host_keys))
        except (ValueError, KeyError, TypeError, AttributeError) as error:
            report.update(status="unreadable", error=type(error).__name__)
        return report

    def layer_close(self, line):
        # https://wiki.hypr.land/IPC/: layer events name only a namespace.
        # This snapshot proves later address absence, not a causal close.
        namespace = line.split(b">>", 1)[1].decode(errors="replace")
        pending = [l for l in self.layer_stops.values() if l["namespace"] == namespace]
        if not pending:
            return
        close_receipt = self.receipts
        report = self.layers_report(self.layers_query(), "")
        self.emit("nested-ipc", "layer-close-snapshot", dict(closeReceipt=close_receipt, **report))
        snapshot_receipt = self.receipts
        if report["status"] != "read":
            return
        present = {l["address"] for l in report["layers"]}
        for layer in report["layers"]:
            prior = self.layer_stops.get(layer["address"])
            if prior and (layer["pid"] != prior["pid"] or layer["stop"] != prior["stop"] or layer["identityMatch"] == "changed"):
                self.emit("nested-ipc", "layer-generation-changed", dict(previous=prior, current=layer))
                del self.layer_stops[layer["address"]]
        gone = [l for l in pending if l["address"] not in present]
        for layer in gone:
            self.emit("nested-ipc", "layer-close-join", dict(layer, closeEvent=line.decode(errors="replace"),
                closeReceipt=close_receipt, snapshotReceipt=snapshot_receipt,
                closeAttribution="ambiguous" if len(gone) > 1 else "address-absent-after-namespace-close",
                limit="subsequent snapshot absence; no address-bearing close or client-exit proof; unseen close/reopen unresolved"))
            del self.layer_stops[layer["address"]]

    def require_display(self, pid, qs_pid):
        if self.scope is None or not self.scope["displayRequired"]:
            raise ValueError("display-scope-unbound")
        context = self.resolve_owner(pid)
        if context["tag"] != "registered" or self.shell_pids.get(qs_pid) != context["registration"]:
            raise ValueError("display-registration-missing")
        key = context["registration"]
        if self.display_registration is not None and self.display_registration != key:
            raise ValueError("display-registration-ambiguous")
        self.display_registration = key
        self.registrations[key]["required"] = True
        self.emit("harness", "required-display-registration", dict(registration=key, runner=pid, qs=qs_pid))

    def set_scope(self, role, caller, argc, *words):
        if self.scope is not None:
            raise ValueError("scope-repeated")
        if role not in ("display-smoke", "smoke-context", "first-bar-context", "shader-context", "screenshot-context"):
            raise ValueError("scope-unknown")
        argc = int(argc)
        if argc < 0 or argc > len(words):
            raise ValueError("scope-argv-invalid")
        rows = list(words[argc:])
        expected = role == "display-smoke"
        if expected != ("displays-modes" in rows):
            raise ValueError("scope-selection-mismatch")
        self.scope = dict(role=role, caller=caller, argv=list(words[:argc]), selectedRows=rows,
                          displayRequired=expected,
                          factsNotRequested=[] if expected else ["trial-acceptance", "phase-token-deadline", "queue-completion", "layer-reload"],
                          scopeSource="declared caller and canonical row selection, before producer launch")
        self.emit("harness", "declared-scope", self.scope)

    def close_window(self, status, origin):
        if self.closed:
            self.emit("harness", "window-already-closed", dict(originalStatus=status, origin=origin))
            return
        self.drain()
        for state in self.streams.values():
            if state["buffer"] or state["clipped"]:
                self.problems.add(state["source"] + ":partial-at-window-end")
        self.emit("harness", "window-end", dict(originalStatus=status, origin=origin))
        self.closed = True

    def retire_log(self, fd, reason):
        state = self.streams.pop(fd)
        registration = state["registration"]
        self.emit(state["source"], "local-stream-end", dict(reason=reason, offset=state["offset"],
                  partialBytes=len(state["buffer"]), required=registration["required"]))
        if state["buffer"] or state["clipped"]:
            self.problems.add(state["source"] + ":partial-final-record")
        self.log_history[state["identity"]] = registration["state"] == "local-ended" and state["valid"]
        registration["state"] = "final-ended" if reason == "final-producer-group-teardown" else "local-ended"
        registration["fd"] = None
        self.log_watches.pop(state["wd"], None)
        LIBC.inotify_rm_watch(self.notify_fd, state["wd"])
        os.close(fd)
        self.sequences.pop(state["source"], None)

    def notifications(self, limit=65536):
        try:
            packet = os.read(self.notify_fd, limit)
        except BlockingIOError:
            return 0
        self.read_bytes["notifications"] += len(packet)
        at = 0
        while at < len(packet):
            wd, mask, cookie, length = struct.unpack_from("iIII", packet, at)
            at += 16 + length
            self.notification(wd, mask, cookie)
        return len(packet)

    def notification(self, wd, mask, cookie):
        if mask & IN_Q_OVERFLOW:
            self.problems.add("notification:overflow")
            self.emit("recorder", "notification-overflow", {"history": "lost; no reconstruction"})
        fd = self.log_watches.get(wd)
        if fd is None:
            return
        state = self.streams[fd]
        if mask & (IN_MOVE_SELF | IN_DELETE_SELF | IN_UNMOUNT | IN_IGNORED):
            state["valid"] = False
            self.problems.add(state["source"] + ":replacement-or-watch-lost")
        if mask & IN_CLOSE_WRITE:
            self.emit(state["source"], "close-write-notification", {
                "writerIdentity": "unavailable; does not end local observation"})
        self.read_file(fd)

    def read_file(self, fd):
        state = self.streams[fd]
        info = os.fstat(fd)
        try:
            named = os.stat(state["path"], follow_symlinks=False)
            if (named.st_dev, named.st_ino) != state["identity"]:
                raise ValueError("replaced")
        except (OSError, ValueError):
            state["valid"] = False
            self.problems.add(state["source"] + ":replacement-or-watch-lost")
        if info.st_size < state["offset"]:
            state["valid"] = False
            self.problems.add(state["source"] + ":truncated-history")
        # Snapshot once. A continuously writing producer cannot extend
        # this read. File EOF is temporary, never a completion event.
        remaining = info.st_size - state["offset"]
        while state["valid"] and remaining > 0:
            data = os.read(fd, min(remaining, 65536))
            if not data:
                state["valid"] = False
                self.problems.add(state["source"] + ":truncated-history")
                break
            state["offset"] += len(data)
            remaining -= len(data)
            self.read_bytes["files"] += len(data)
            self.consume(state, data)

    def control(self):
        client, _ = self.server.accept()
        with client:
            try:
                packet, _, flags, _ = client.recvmsg(CAP_LINE)
                if flags & socket.MSG_TRUNC:
                    raise ValueError("control-truncated")
                command, *args = json.loads(packet)
                value = "ok"
                if command == "log":
                    value = self.watch_log(*args)
                elif command == "launched":
                    self.launched(*args)
                elif command == "owner-context":
                    value = self.owner_context(*args)
                elif command == "owner-end":
                    self.end_owner(*args)
                elif command == "require-display":
                    self.require_display(*args)
                elif command == "scope":
                    self.set_scope(*args)
                elif command == "read":
                    self.drain()
                    value = dict(activeStreams=len(self.streams), registrations=self.next_stream,
                                 streams=[dict(source=s["source"], path=s.get("path"), offset=s.get("offset"),
                                               registration=s["registration"]["key"] if "registration" in s else None,
                                               state=s["registration"]["state"] if "registration" in s else "ipc",
                                               required=s["registration"]["required"] if "registration" in s else False)
                                          for s in self.streams.values()],
                                 problems=sorted(self.problems))
                elif command == "bind":
                    signature, path, pid, wayland = args
                    if self.bound:
                        raise ValueError("ambiguous-nested-binding")
                    self.bound = True
                    self.layer_signature = signature
                    self.emit("harness", "nested-binding", dict(signature=signature, socket=path,
                              namespacePid=pid, waylandSocket=wayland))
                    self.subscribe("nested-ipc", path)
                elif command == "mark":
                    if args[0] in ("display-request", "display-reply"):
                        self.request_counts[args[0]] += 1
                    if args[0] == "shell-identity":
                        if len(self.shell_owners) >= CAP_EVENTS:
                            raise ValueError("layers:owner-capacity")
                        self.shell_owners[args[2]] = dict(runner=args[1], pid=args[2], tree=args[3], log=args[4], identity=process_binding(args[2]))
                        context = self.resolve_owner(args[1])
                        if context["tag"] == "registered":
                            self.shell_pids[args[2]] = context["registration"]
                        self.emit("harness", "shell-observation-context", context)
                    if args[0] == "stop-shell" and args[1] in self.owner_contexts and args[2]:
                        context = self.owner_contexts[args[1]]
                        owner = self.shell_owners.get(args[2], {})
                        snapshot = process_binding(args[2])
                        known = owner.get("runner") == context["pid"] and owner.get("identity", {}).get("startTicks") is not None
                        known = known and (snapshot["status"] == "gone" or owner["identity"]["startTicks"] == snapshot.get("startTicks"))
                        context.update(stopShell=args[2], stopInstance=dict(owner if known else {},
                            pid=args[2], instanceLog=args[3] if known and args[3] else None,
                            instanceLogStatus="bound" if known and args[3] else "unavailable",
                            instanceLogReason=None if known and args[3] else "no recorded shell generation binds the supplied instance log",
                            binding=context["tag"], snapshot=snapshot))
                        self.shell_owners[args[2]] = context["stopInstance"]
                        self.layer_bound = float(args[4]) if args[4] else None
                    if args[0] == "display-request":
                        self.emit("harness", "outgoing-display-request", dict(operation=args[1], argument=args[2]))
                    elif args[0] == "display-reply":
                        self.emit("harness", "display-request-reply", dict(operation=args[1], clientExit=args[2], reply=args[3]))
                    else:
                        self.emit("harness", "boundary", args)
                elif command == "probe-state":
                    self.emit("harness", "probe-state", json.loads(args[0]))
                elif command == "layer-reading":
                    directory, current = args
                    root = pathlib.Path(directory)
                    raw = (root / "layers.raw").read_text()
                    report = self.layers_report(raw, current, (root / "layers.probe").read_text())
                    self.emit("harness", "layer-reading", dict(directory=directory, **report))
                    value = json.dumps(report)
                elif command == "close":
                    self.close_window(*args)
                elif command == "stop":
                    self.stop_reason = args[0]
                    self.stopping = True
                else:
                    raise ValueError("unknown-command")
                client.sendall(json.dumps(dict(ok=True, value=value)).encode())
            except (OSError, ValueError, TypeError) as error:
                self.problems.add("control:" + str(error))
                client.sendall(json.dumps(dict(ok=False, error=str(error))).encode())

    def line(self, state, line):
        self.input_span = dict(source=state["source"], start=state["line_start"],
                               end=state["byte_cursor"]) if "path" in state else None
        try:
            self.parse_line(state, line)
        finally:
            self.input_span = None

    def parse_line(self, state, line):
        if self.closed:
            return
        source = state["source"]
        kind = state["kind"]
        if kind == "probe":
            at = line.find(PREFIX)
            if at < 0:
                return
            try:
                # Probe's encoder emits every JSON data type. Envelope
                # metadata is separate from event-specific fact fields.
                # https://docs.python.org/3.14/library/json.html#json.loads
                value = json.loads(line[at + len(PREFIX):], parse_float=probe_float,
                                   parse_constant=probe_constant)
                if (not isinstance(value, dict) or value["schema"] != "VGS-1714.display-event.v1"
                        or not isinstance(value["instance"], str) or not value["instance"]
                        or type(value["sequence"]) is not int or value["sequence"] < 1
                        or not finite_number(value["realtimeMs"])
                        or not isinstance(value["producer"], str) or not value["producer"]
                        or not isinstance(value["kind"], str) or not value["kind"] or "data" not in value):
                    raise ValueError("invalid Probe envelope")
            except (KeyError, TypeError, ValueError, RecursionError):
                self.problems.add(source + ":probe-unparsed")
                self.emit(source, "unparsed", line.decode(errors="replace"))
                return
            instance = value["instance"]
            if instance not in self.probe_states and len(self.probe_states) >= CAP_STREAMS:
                self.problems.add("probe:capacity-instances")
                return
            if value["sequence"] != self.probe_sequences.get(instance, 0) + 1:
                self.problems.add("probe:sequence-gap:" + instance)
            self.probe_sequences[instance] = value["sequence"]
            registration = state["registration"]["key"]
            prior = self.probe_states.get(instance)
            if prior is not None and prior["kind"] in ("stopped", "missing", "interrupted", "overflow"):
                self.problems.add("probe:event-after-terminal:" + instance)
            if prior is not None and prior["registration"] != registration:
                self.problems.add("probe:instance-generation-ambiguous:" + instance)
            self.probe_states[instance] = dict(kind=value["kind"], registration=registration)
            self.observations.add((registration, instance, value["producer"], value["kind"]))
            self.fact_counts[(registration, value["producer"], value["kind"])] += 1
            data = value["data"]
            target = (value["producer"], value["kind"])
            valid_fact = True
            if target == ("MonitorState", "trialStateChanged"):
                valid_fact = (isinstance(data, dict) and isinstance(data.get("phase"), str)
                              and isinstance(data.get("token"), str) and finite_number(data.get("deadline"))
                              and isinstance(data.get("failure"), str))
                if valid_fact:
                    self.fact_counts[(registration, "fact", "trial-state-publication")] += 1
                    if data["phase"] == "arming":
                        self.fact_counts[(registration, "fact", "accepted-state-publication")] += 1
            elif target == ("Compositor", "completionChanged"):
                valid_fact = (isinstance(data, dict) and "completion" in data
                              and (data["completion"] is None or process_completion(data["completion"])))
                if valid_fact and data["completion"] is not None:
                    self.fact_counts[(registration, "fact", "queue-process-completion")] += 1
            elif target == ("HyprlandLayer.reloader", "exited"):
                valid_fact = process_completion(data)
                if valid_fact:
                    self.fact_counts[(registration, "fact", "reloader-exit")] += 1
            if not valid_fact:
                self.problems.add(source + ":probe-fact-payload-invalid:" + ":".join(target))
            self.emit(source, "probe-observation", value)
        elif kind == "wayland":
            # Preserve the actual diagnostic text and direction. Requests
            # prove only a client request, never acceptance or presentation.
            if not re.search(rb"(?:xdg_(?:wm_base|toplevel|surface)|wl_(?:compositor|surface|output)).*(?:configure|ack_configure|get_xdg_surface|get_toplevel|create_surface|enter\(|leave\(|destroy\()", line):
                return
            if b"xdg_toplevel" in line and b".configure(" in line and b" -> " not in line:
                self.configure_seen = True
            self.emit(source, "outgoing-request" if b" -> " in line else "incoming-observation",
                      line.decode(errors="replace"))
        else:
            name = line.split(b">>", 1)[0]
            relevant = (name.startswith((b"monitor", b"openwindow", b"closewindow", b"movewindow"))
                        or name in (b"configreloaded", b"focusedmon", b"moveworkspace", b"moveworkspacev2", b"openlayer", b"closelayer"))
            if relevant:
                if name.startswith(b"monitor"):
                    self.monitor_counts[source] += 1
                self.emit(source, "ipc-observation", line.decode(errors="replace"))
                if name == b"closelayer":
                    self.layer_close(line)

    def read(self, stream, limit=65536):
        state = self.streams[stream]
        if state["ended"]:
            return False
        try:
            data = os.read(stream if isinstance(stream, int) else stream.fileno(), limit)
        except BlockingIOError:
            return False
        if not data:
            if not self.closed:
                self.problems.add(state["source"] + ":unexpected-eof")
                self.emit(state["source"], "unexpected-eof", {"partialBytes": len(state["buffer"])})
            if state["buffer"] or state["clipped"]:
                self.problems.add(state["source"] + ":partial-final-record")
            self.emit(state["source"], "local-stream-end", dict(reason="socket-eof", windowClosed=self.closed))
            self.selector.unregister(stream)
            del self.streams[stream]
            stream.close()
            return False
        self.consume(state, data)
        self.read_bytes["sockets"] += len(data)
        return len(data)

    def consume(self, state, data):
        if self.closed:
            # Keep the acquired reader through group teardown. Later bytes
            # are read volume only, outside the recorded observation window.
            return
        # Long original log lines stay intact in their original file.
        # No clipped value becomes an observation.
        for part in data.splitlines(keepends=True):
            if not state["buffer"] and not state["clipped"]:
                state["line_start"] = state.get("byte_cursor", 0)
            state["byte_cursor"] = state.get("byte_cursor", 0) + len(part)
            if state["clipped"]:
                if part.endswith(b"\n"):
                    state["clipped"] = False
                continue
            if len(state["buffer"]) + len(part) > CAP_LINE:
                self.problems.add(state["source"] + ":truncated")
                state["buffer"] = b""
                state["clipped"] = not part.endswith(b"\n")
                continue
            state["buffer"] += part
            if part.endswith(b"\n"):
                self.line(state, state["buffer"].rstrip(b"\r\n"))
                state["buffer"] = b""

    def drain(self):
        if self.notify_fd is not None:
            queued = array.array("i", [0])
            fcntl.ioctl(self.notify_fd, termios.FIONREAD, queued, True)
            remaining = queued[0]
            while remaining > 0:
                consumed = self.notifications(min(remaining, 65536))
                if not consumed:
                    break
                remaining -= consumed
        for stream, state in list(self.streams.items()):
            if "path" in state:
                self.read_file(stream)
                continue
            if state["ended"]:
                continue
            # Snapshot the kernel's queued byte count. A busy socket
            # cannot extend this drain with later arrivals. FIONREAD is a
            # Linux pipe/socket read, inside the existing Linux sandbox.
            queued = array.array("i", [0])
            try:
                fd = stream if isinstance(stream, int) else stream.fileno()
                fcntl.ioctl(fd, termios.FIONREAD, queued, True)
                remaining = queued[0]
                while remaining > 0:
                    consumed = self.read(stream, min(remaining, 65536))
                    if not consumed:
                        break
                    remaining -= consumed
            except OSError as error:
                self.problems.add(state["source"] + ":drain-unavailable")
                self.emit(state["source"], "drain-unavailable", str(error))

    def run(self):
        signal.signal(signal.SIGTERM, lambda *_: self.interrupt("signal-TERM"))
        signal.signal(signal.SIGINT, lambda *_: self.interrupt("signal-INT"))
        signal.signal(signal.SIGHUP, lambda *_: self.interrupt("signal-HUP"))
        try:
            while not self.stopping:
                for key, _ in self.selector.select():
                    kind, stream = key.data
                    if kind == "control":
                        self.control()
                    elif kind == "notify":
                        self.notifications()
                    else:
                        self.read(stream)
            # Drain only bytes already available at stop. socket2 supplies
            # no flush acknowledgement, so later delivery remains unknown.
            self.drain()
        finally:
            if self.stop_reason != "normal":
                self.problems.add("interrupted:" + self.stop_reason)
            if not self.closed:
                self.problems.add("window-end:missing")
            if not self.bound:
                self.problems.add("nested-binding:missing")
            if not any(registration["kind"] == "wayland" and registration["launch"] is not None
                       for registration in self.registrations.values()):
                self.problems.add("wayland-producer:missing")
            if self.scope is None:
                self.problems.add("scope:missing")
            expected = self.scope is not None and self.scope["displayRequired"]
            required_instances = []
            if expected:
                if self.display_registration is None:
                    self.problems.add("display-registration:missing")
                for instance, state in self.probe_states.items():
                    if state["registration"] == self.display_registration:
                        required_instances.append(instance)
                if not required_instances:
                    self.problems.add("probe:missing")
                for instance in required_instances:
                    registration = self.probe_states[instance]["registration"]
                    seen = {(producer, kind) for key, identity, producer, kind in self.observations
                            if key == registration and identity == instance}
                    if ("Probe", "arm") not in seen:
                        self.problems.add("probe:arm-missing:" + instance)
                    for producer in ("MonitorState", "Compositor", "HyprlandLayer", "HyprlandLayer.reloader", "Quickshell/Hyprland"):
                        if (producer, "initial-sample") not in seen:
                            self.problems.add("probe:producer-missing:" + producer)
                    if self.probe_states[instance]["kind"] != "stopped":
                        self.problems.add("probe:interrupted:" + instance)
                    if self.shell_pids.get(instance.split("/", 1)[0]) != registration:
                        self.problems.add("probe:launch-unbound:" + instance)
            # Occurrence is not collection integrity. Public producers can
            # report zero changes after a refusal or an unchanged input.
            facts = {}
            for label, producer, kind in (("phase-token-deadline", "fact", "trial-state-publication"),
                                           ("trial-acceptance-publication", "fact", "accepted-state-publication"),
                                           ("queue-completion", "fact", "queue-process-completion"),
                                           ("actual-layer-reload", "fact", "reloader-exit")):
                observed = self.fact_counts[(self.display_registration, producer, kind)]
                facts[label] = dict(status="scope-unavailable" if self.scope is None else "not-requested" if not expected else "observed" if observed else "not-observed",
                                    observationCount=observed,
                                    limit="initial samples are not historical events; zero observations prove no product success; reloader exit is command exit, not successful configuration application")
            facts["outgoing-display-requests-and-replies"] = dict(
                status="scope-unavailable" if self.scope is None else "not-requested" if not expected else "observed" if self.request_counts["display-request"] and self.request_counts["display-reply"] else "not-observed",
                counts=dict(self.request_counts), limit="outgoing requests/replies are not incoming acceptance or completion")
            facts["public-wayland-configure"] = dict(status="observed" if self.configure_seen else "not-observed",
                limit="owned launch diagnostic output only; protocol connection identity unresolved")
            facts["nested-monitor-ipc"] = dict(status="observed" if self.monitor_counts["nested-ipc"] else "not-observed",
                observationCount=self.monitor_counts["nested-ipc"], limit="public socket2 receipt only; no upstream delivery acknowledgement")
            for registration in self.registrations.values():
                if registration["state"] == "pending":
                    self.problems.add("registration:launch-missing:" + registration["key"])
            for stream, state in list(self.streams.items()):
                if state["buffer"] or state["clipped"]:
                    self.problems.add(state["source"] + ":partial-final-record")
                if "path" in state:
                    self.retire_log(stream, "final-producer-group-teardown")
                else:
                    stream.close()
            # Prefix counters and RUSAGE_SELF are sampled here, before
            # terminal serialization/write. Linux ru_maxrss is peak KiB.
            # https://docs.python.org/3/library/resource.html
            # https://man7.org/linux/man-pages/man2/getrusage.2.html
            usage = resource.getrusage(resource.RUSAGE_SELF)
            cost = dict(samplePoint="after final drains and stream-end records, before terminal serialization",
                        prefixRecordEvents=self.events, prefixRecordBytes=self.bytes,
                        readBytes=dict(self.read_bytes), userCpuSeconds=usage.ru_utime,
                        systemCpuSeconds=usage.ru_stime, peakResidentKiB=usage.ru_maxrss,
                        scope="collector process threads only; excludes children, terminal serialization/write, exit and retention",
                        productLatencyAndObserverEffect="unmeasured")
            self.emit("recorder", "terminal", dict(localRecord="complete" if not self.problems else "incomplete",
                      problems=sorted(self.problems), stopReason=self.stop_reason,
                      declaredScope=self.scope, requiredDisplayRegistration=self.display_registration,
                      factAvailability=facts,
                      displayOutcome="scope-unavailable" if self.scope is None else "not-requested" if not expected else "facts-observed" if not self.problems and all(f["status"] == "observed" for f in facts.values()) else "not-established",
                      observationCost=cost,
                      upstreamDelivery="unknown: no socket2 acknowledgement or terminal marker",
                      configureAttribution="owned launch output stream only; protocol connection identity unresolved",
                      productResult="separate original smoke verdict"), terminal=True)
            self.output.close()
            self.server.close()
            self.selector.close()
            if self.notify_fd is not None:
                os.close(self.notify_fd)

    def interrupt(self, reason):
        self.stop_reason = reason
        self.stopping = True
        raise SystemExit(1)

if __name__ == "__main__":
    if sys.argv[1] == "serve":
        Record(sys.argv[2]).run()
    elif sys.argv[1] == "read":
        print(json.dumps(read_record(sys.argv[2])))
    elif sys.argv[1] == "retain":
        retain_record(*sys.argv[2:])
    elif sys.argv[1] == "complete":
        complete_record(*sys.argv[2:])
    else:
        try:
            print(request(sys.argv[2], *sys.argv[3:]))
        except (OSError, ValueError, RuntimeError) as error:
            print("display-record: unavailable=" + str(error), file=sys.stderr)
            sys.exit(1)
PY
}
