#!/usr/bin/env python3
"""Drive real recorder events and smoke_row boundaries with owned fixtures."""
import contextlib
import json
import os
from pathlib import Path
import re
import select
import shutil
import signal
import socket
import stat
import subprocess
import tempfile
import threading
import types

REPO = Path(__file__).resolve().parent.parent
BASH = shutil.which("bash")
PYTHON = shutil.which("python3")
ENV = {key: os.environ[key] for key in ("PATH", "TMPDIR", "VGSHELL_WORLD_ROOT") if key in os.environ}
ENV.update(LC_ALL="C.UTF-8", VGS_TEST_RUN="1")
source = (REPO / "scripts/smoke/harness.sh").read_text()
recorder = subprocess.check_output([BASH, "-c", 'source "$1"; display_record_program', "_",
                                    str(REPO / "scripts/smoke/display-record.sh")], env=ENV, text=True)


def function(name):
    found = re.search(r"(?ms)^" + name + r"\(\).*?^}\n", source)
    assert found, name
    return found.group()


class OwnedDialog:
    """A detached fixture stays bound to its acquired pidfd and stdout pipe."""
    def __init__(self, launcher):
        self.launcher = launcher
        ready = launcher.stdout.readline().split()
        assert len(ready) == 2 and ready[0] == "ready", ready
        self.pid = int(ready[1])
        self.fd = os.pidfd_open(self.pid)
        try:
            assert launcher.wait(timeout=3) == 0
            expected = os.fstat(launcher.stdout.fileno())
            actual = (Path("/proc") / str(self.pid) / "fd/1").stat()
            assert (actual.st_dev, actual.st_ino) == (expected.st_dev, expected.st_ino)
        except BaseException:
            os.close(self.fd)
            raise

    def alive(self):
        return not select.select([self.fd], [], [], 0)[0]

    def terminate(self):
        try:
            signal.pidfd_send_signal(self.fd, signal.SIGTERM)
        except ProcessLookupError:
            pass

    def wait_ended(self, timeout=3):
        assert select.select([self.fd], [], [], timeout)[0], "owned dialog did not end"

    def close(self):
        if self.alive():
            self.terminate()
        self.wait_ended()
        os.close(self.fd)
        self.launcher.stdout.close()
        self.launcher.stderr.close()


with tempfile.TemporaryDirectory(prefix="smoke-anr-") as scratch:
    root = Path(scratch)
    namespace = {"__name__": "fixture"}
    exec(compile(recorder, "display-recorder", "exec"), namespace)
    request = namespace["request"]
    # Synthetic process bindings test the identity decision, not liveness
    # of invented PIDs. End-to-end cases below hold real fixture pidfds.
    state_subject = namespace["Record"].__new__(namespace["Record"])
    incident = dict(address="0xd", dialog=dict(pid=17), identity=dict(startTicks="123"))
    mapped = dict(address="0xd", pid=17, **{"class": "hyprland-dialog"})
    lifecycle = (
        ("mapped", incident, [mapped], dict(status="live", startTicks="123"), "same"),
        ("closed", incident, [], dict(status="gone"), "absent"),
        ("ordinary-address-reuse", incident, [dict(mapped, **{"class": "org.fixture"})], dict(status="live", startTicks="123"), "absent"),
        ("new-dialog-pid", incident, [dict(mapped, pid=18)], dict(status="live", startTicks="123"), "absent"),
        ("reused-pid-generation", incident, [mapped], dict(status="live", startTicks="124"), "replaced"),
        ("gone-with-stale-client", incident, [mapped], dict(status="gone"), "ended"),
        ("zombie-with-stale-client", incident, [mapped], dict(status="ended", startTicks="123"), "ended"),
        ("unreadable-process", incident, [mapped], dict(status="unavailable"), "unavailable"),
        ("unknown-generation", dict(incident, identity={}), [mapped], dict(status="live", startTicks="123"), "unavailable"),
        ("unknown-dialog", dict(incident, dialog={}), [mapped], dict(status="live", startTicks="123"), "unavailable"),
    )
    binding = namespace["process_binding"]
    try:
        for name, observed, clients, current, expected in lifecycle:
            namespace["process_binding"] = lambda _pid, current=current: current
            assert state_subject.anr_client_state(observed, clients) == expected, name
    finally:
        namespace["process_binding"] = binding
    print("smoke-anr: lifecycle-table=pass")
    transport = namespace["subprocess"]
    state_subject.anr_bound = 0.2
    state_subject.layer_signature = "fixture"
    replies = (
        ("empty", [], 0, True),
        ("complete", [dict(mapped, title="")], 0, True),
        ("not-list", {}, 0, False),
        ("incomplete-row", [{}], 0, False),
        ("unreadable-pid", [dict(mapped, title="", pid=None)], 0, False),
        ("native-failure", [], 23, False),
    )
    try:
        for name, payload, status, readable in replies:
            response = subprocess.CompletedProcess([], status, stdout=json.dumps(payload).encode())
            namespace["subprocess"] = types.SimpleNamespace(run=lambda *_, response=response, **__: response)
            try:
                value = state_subject.anr_clients(0.2)
            except ValueError:
                assert not readable, name
            else:
                assert readable and value == payload, name
    finally:
        namespace["subprocess"] = transport
    print("smoke-anr: required-client-evidence=checked empty-input=allowed")
    helpers = root / "functions.sh"
    helpers.write_text("".join(function(name) for name in ("py_dumps", "py_reply", "shell_crash_check", "shell_crash_new", "shell_crash_reports", "anr_row_boundary", "smoke_row", "now_ms", "cpu_some_us", "cpu_some_pct", "load_average", "smoke_row_secs")))
    driver = root / "driver.sh"
    driver.write_text('''set -euo pipefail
repo="$1" sandbox="$2" display_record_dir="$3"
source "$repo/scripts/smoke/verdict.sh"
source "${7:-$repo/scripts/smoke/leaks.sh}"
source "$4"
display_record_call() { python3 "$display_record_dir/recorder.py" request "$display_record_dir/control" "$@"; }
ipc() { if [[ "$*" == 'shell ping' ]]; then echo ok; else echo '[]'; fi; }
# This recorder-only fixture starts no registry or bus. Stable neutral
# sensors keep the successor assertion about ANR cleanup.
leak_plugins() { echo '{"scanned":true,"plugins":[{"id":"vgs.bar","enabled":true},{"id":"acme.enabled","enabled":true}]}'; }
leak_bus_names() { echo 'org.freedesktop.DBus none'; }
# No theme writer runs in this recorder fixture. Its queue is already idle.
theme_idle() { echo idle; }
hypr() {
  case "$*" in
    '-j clients') cat "$sandbox/clients.json" ;;
    '-j descriptions') echo '[{"name":"general:border_size"}]' ;;
    '-j layers') echo '{}' ;;
    '--batch j/getoption general:border_size') echo '{"int":1}' ;;
    'reload config-only') echo ok ;;
    *) return 1 ;;
  esac
}
active_window() { python3 -c 'import json,sys; cs=json.load(open(sys.argv[1])); ds=[c for c in cs if c["class"]=="hyprland-dialog"]; print(json.dumps([ds[0]["class"],ds[0]["title"]] if ds else []))' "$sandbox/clients.json"; }
key_submap() { echo default; }
devices_guard() { echo stable; }
devices_check() { return 0; }
rest_pointer() { :; }
if [[ ${6:-} != crash ]]; then shell_crash_check() { return 0; }; fi
stop_shell() { :; }
shell_stop() { local -n shell_stop_outcome="$1"; shell_stop_outcome=stopped; }
start_shell() { :; }
sink_check() { :; }
row_log_check() { :; }
row_log_tail() { :; }
ipc_oversize_check() { :; }
ipc_timeout_check() { return 0; }
ok() { :; }
shim="$sandbox/shim"; mkdir "$shim"
shell_start_path="$PATH" shell_start_words=() shell_env=()
if [[ ${5:-} == launch-variables ]]; then
  unset shell_start_path
  shell_start_words=([2]=$'one\ntwo' [7]='')
  shell_env=(env 'VGS_FIXTURE_EMPTY=' $'VGS_FIXTURE_LINES=one\ntwo')
fi
shell_qs_pid="" shell_pid="" timeout_s=1 smoke_row_drain_s=5
shell_class=org.vgs.shell shell_reporter_class=org.quickshell
home="$sandbox/home" rt_dir="$sandbox/run"
mkdir -p "$home/.config/hypr" "$rt_dir"
printf 'fixture\n' >"$home/.config/hypr/hyprland.lua"
ipc() {
 case "$*" in
  'shell ping') echo ok ;;
  'shell listPlugins') leak_plugins ;;
  *) echo '[]' ;;
 esac
}
smoke_row planted "$sandbox"
before=$failures
smoke_row successor "$sandbox"
printf 'continuation before=%s after=%s\\n' "$before" "$failures"
[[ $before == "$failures" ]]
''')
    client = root / "event.py"
    client.write_text('''import os,pathlib,socket,sys
with socket.socket(socket.AF_UNIX,socket.SOCK_SEQPACKET) as s:
 p=pathlib.Path(sys.argv[1]); fd=os.open(p.parent,os.O_PATH|os.O_DIRECTORY)
 try: s.connect(f"/proc/self/fd/{fd}/{p.name}")
 finally: os.close(fd)
 s.sendall(sys.argv[2].encode()); reply=s.recv(1024)
 if reply != b"ok": raise RuntimeError(reply)
''')
    dialog = root / "dialog.py"
    dialog.write_text('''import json,os,pathlib,signal,sys
path=pathlib.Path(sys.argv[1])
def end(*_):
 data=[c for c in json.loads(path.read_text()) if c["pid"] != os.getpid()]
 path.write_text(json.dumps(data))
 raise SystemExit(0)
if os.fork(): os._exit(0)
signal.signal(signal.SIGTERM,end)
print("ready",os.getpid(),flush=True)
while True: signal.pause()
''')

    def case(name, program=recorder, transient=False, ownership=True, candidates=1, abandoned=False, reuse=False, entry=False, mutation=None, crash=False, helper_path=None, leaks_path=None):
        directory = Path(tempfile.mkdtemp(prefix=name + "-", dir=root))
        sandbox, runtime, recording = (directory / part for part in ("sandbox", "runtime", "record"))
        for folder in (sandbox, runtime / "hypr/test", recording):
            folder.mkdir(parents=True)
        log = runtime / "hypr/test/hyprland.log"
        log.write_bytes(b"before\nappearance-marker\n")
        (sandbox / "hyprland.log").write_bytes(b"launch-appearance\n")
        ordinary = subprocess.Popen(["sleep", "60"], env=ENV)
        unrelated = subprocess.Popen(["sleep", "60"], env=ENV)
        clients = [dict(address="0x1", pid=ordinary.pid, title="Plugins", **{"class": "org.vgs.shell"}, mapped=True)]
        if candidates == 2:
            clients.append(dict(clients[0], address="0x2", pid=unrelated.pid))
        path = sandbox / "clients.json"
        path.write_text(json.dumps(clients))
        nested = socket.socket(socket.AF_UNIX)
        # The parent holds this directory across subscription. A child
        # addresses that parent's fd, so no case label enters sun_path.
        socket_directory = os.open(runtime / "hypr/test", os.O_PATH | os.O_DIRECTORY)
        nested_name = f"/proc/{os.getpid()}/fd/{socket_directory}/.socket2.sock"
        nested.bind(nested_name)
        nested.listen()
        nested.settimeout(3)
        # Only the native clients transport is a fixture. Observation,
        # attribution, pidfd ownership, capture and cleanup run production.
        marker = 'if __name__ == "__main__":'
        assert program.count(marker) == 1
        code = program.replace(marker, '''if __name__ == "__main__" and sys.argv[1] == "serve":
    Record.anr_clients = lambda self, _bound: json.loads(pathlib.Path(sys.argv[3]).read_text())
    # No compositor transport exists in this recorder-only fixture.
    # ANR cleanup and the boundary's literal snapshot comparison stay real.
    Record.row_close_added = lambda self, *_args: None
''' + marker)
        script = recording / "recorder.py"
        script.write_text(code)
        serve = subprocess.Popen([PYTHON, str(script), "serve", str(recording), str(path)], env=ENV,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        held_dialogs = []
        errors = []
        stream = None
        stop = threading.Event()
        fixture = socket.socket(socket.AF_UNIX, socket.SOCK_SEQPACKET)
        with namespace["socket_name"](directory / "fixture") as name:
            fixture.bind(name)
        fixture.listen()
        fixture.settimeout(0.1)

        def fixture_loop():
            try:
                while not stop.is_set():
                    try:
                        call, _ = fixture.accept()
                    except TimeoutError:
                        continue
                    with call:
                        action = call.recv(1024)
                        if action == b"start":
                            description = "An application Plugins - org.vgs.shell is not responding." if candidates else "unknown"
                            launcher = subprocess.Popen([PYTHON, str(dialog), str(path), "--text", description],
                                env=ENV, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                            process = OwnedDialog(launcher)
                            held_dialogs.append(process)
                            parent = int((Path("/proc") / str(process.pid) / "stat").read_text().rsplit(")", 1)[1].split()[1])
                            assert parent != os.getpid(), "fixture did not detach"
                            path.write_text(json.dumps(clients + [dict(address="0xd", pid=process.pid,
                                title="", **{"class": "hyprland-dialog"}, mapped=True)]))
                            stream.sendall(b"openwindow>>d,1,hyprland-dialog,\n")
                        elif action == b"close":
                            process = held_dialogs[-1]
                            process.terminate()
                            process.wait_ended()
                            if reuse:
                                path.write_text(json.dumps(clients + [dict(address="0xd", pid=unrelated.pid,
                                    title="Other", **{"class": "org.fixture"}, mapped=True)]))
                            stream.sendall(b"closewindow>>d\n")
                        else:
                            raise AssertionError(action)
                        call.sendall(b"ok")
            except BaseException as error:
                errors.append(error)

        thread = threading.Thread(target=fixture_loop)
        try:
            # Ready is a reported state; the parent bounds the whole case.
            import time
            deadline = time.monotonic() + 5
            while not (recording / "ready").exists():
                assert serve.poll() is None, serve.stderr.read().decode()
                assert time.monotonic() < deadline, "recorder readiness"
                time.sleep(0.01)
            compositor_pid = os.getpid() if ownership else unrelated.pid
            request(recording / "control", "bind", "test", nested_name, str(compositor_pid), "wayland-test")
            assert not request(recording / "control", "read")["problems"]
            stream, _ = nested.accept()
            request(recording / "control", "anr-arm", str(sandbox), str(runtime), "0.2")
            thread.start()
            row = '(smoke_row abandoned "$sandbox")\n' if abandoned else ""
            (sandbox / "abandoned.sh").write_text("exit 0\n")
            if mutation == "managed-refusal":
                row += 'ipc() { return 1; }\n'
            elif mutation == "missing-enabled-id":
                row += "ipc() { echo '{\"scanned\":true,\"plugins\":[{\"id\":\"vgs.bar\",\"enabled\":true}]}'; }\n"
            elif entry:
                subprocess.run([PYTHON, str(client), str(directory / "fixture"), "start"], env=ENV, check=True, timeout=3)
            else:
                row += f'python3 "{client}" "{directory / "fixture"}" start\n'
            if mutation == "launch-variables":
                row += "shell_start_path=broken; shell_start_words=([7]=changed); shell_env=broken\n"
            elif mutation == "shim":
                row += 'printf "#!/bin/sh\\nexit 0\\n" >"$shim/planted"; chmod 755 "$shim/planted"\n'
            elif mutation == "shim-read-error":
                row += 'find() { if [[ ! -e $sandbox/shim-read.seen ]]; then touch "$sandbox/shim-read.seen"; return 1; fi; command find "$@"; }\n'
            if transient:
                row += f'python3 "{client}" "{directory / "fixture"}" close\n'
            if mutation == "end-unreadable-once":
                row += "leak_plugins() { if [[ ! -e $sandbox/end-read.seen ]]; then touch \"$sandbox/end-read.seen\"; echo '{\"scanned\":false,\"plugins\":[]}'; else echo '{\"scanned\":true,\"plugins\":[{\"id\":\"vgs.bar\",\"enabled\":true},{\"id\":\"acme.enabled\",\"enabled\":true}]}'; fi; }\n"
            elif mutation == "end-unreadable-permanent":
                row += "leak_plugins() { echo '{\"scanned\":false,\"plugins\":[]}'; }\n"
            if crash:
                row += 'mkdir -p "$home/.cache/quickshell/crashes/fixture"\n'
                row += 'printf "===== Stacktrace =====\\n#0 fixture\\n===== End =====\\n" >"$home/.cache/quickshell/crashes/fixture/report.txt"\n'
                row += 'shell_crash_check "$sandbox/detected.crashes" || true\n'
            (sandbox / "planted.sh").write_text(row)
            (sandbox / "successor.sh").write_text('''python3 -c 'import json,sys; cs=json.load(open(sys.argv[1])); assert all(c["class"]!="hyprland-dialog" for c in cs)' "$sandbox/clients.json"
printf 'successor-ran\\n'
''')
            result = subprocess.run([BASH, str(driver), str(REPO), str(sandbox), str(recording), str(helper_path or helpers), mutation or "", "crash" if crash else "", str(leaks_path or REPO / "scripts/smoke/leaks.sh")],
                                    env=ENV, capture_output=True, text=True, timeout=15)
            assert not errors, errors
            incidents = list((sandbox / "rows/planted.anr").glob("*/incident.json"))
            if mutation in ("managed-refusal", "missing-enabled-id"):
                # A refused restore step fails its row; the post reading,
                # equal to the start here, ends nothing.
                assert not incidents, incidents
                assert "successor-ran" in result.stdout, (result.stdout, result.stderr)
                assert "scope=managed original-status=0" in result.stdout, result.stdout
                assert "  FAIL  planted: restoration step=plugins cause=refused" in result.stdout, result.stdout
                assert "restoration=terminal" not in result.stdout, result.stdout
                return None, result
            assert len(incidents) == 1, (incidents, result.stdout, result.stderr)
            incident = json.loads(incidents[0].read_text())
            assert result.stdout.count("FAIL  anr-dialog:") == 1, result.stdout
            if mutation == "shim-read-error":
                assert result.returncode == 1 and "successor-ran" not in result.stdout, "shim-read-error-continued:" + result.stdout
                assert "reading=unreadable class=shim at=end" in result.stdout, result.stdout
                assert "restoration=terminal row=planted original-status=1" in result.stdout, result.stdout
            if crash:
                assert "leaves clients:" in result.stdout, "raw-client-evidence-missing:" + result.stdout
                assert "the shell crashed: crash=fixture" in result.stdout, result.stdout
                assert result.stdout.index("leaves clients:") < result.stdout.index("restore=begin"), result.stdout
            assert ordinary.poll() is None and unrelated.poll() is None
            if ownership and not reuse and not entry and mutation not in ("shim", "shim-read-error", "end-unreadable-permanent"):
                assert "successor-ran" in result.stdout, result.stdout
                assert result.returncode == 0, (result.stdout, result.stderr)
                assert incident["cleanup"] in ("removed", "already-closed"), incident
                held_dialogs[-1].wait_ended()
            elif mutation == "end-unreadable-permanent":
                # Every restore phase runs, the dialog's cleanup among them;
                # the post reading, still unreadable, then ends the run.
                assert "successor-ran" not in result.stdout and result.returncode == 1, result.stdout
                assert "reading=unreadable class=plugins at=end" in result.stdout, result.stdout
                assert "restoration=terminal row=planted original-status=1" in result.stdout, result.stdout
                assert incident["cleanup"] in ("removed", "already-closed"), incident
                held_dialogs[-1].wait_ended()
            elif ownership:
                assert "successor-ran" not in result.stdout, result.stdout
                assert result.returncode != 0, (result.stdout, result.stderr)
                assert incident["cleanup"] in ("removed", "already-closed"), incident
                held_dialogs[-1].wait_ended()
                if entry:
                    assert incident["appearance"] == "between-rows", incident
                    starts = sorted((sandbox / "leaks").glob("*/clients"))
                    assert any(c["class"] == "hyprland-dialog" for c in json.loads(starts[0].read_text()))
            else:
                assert "successor-ran" not in result.stdout, result.stdout
                assert result.returncode != 0, (result.stdout, result.stderr)
                assert incident["cleanup"] == "ownership-unproved", incident
                assert held_dialogs[-1].alive()
            assert incident["receiptRealtimeNs"] > 0 and incident["receiptMonotonicNs"] > 0
            assert incident["signature"] == "test"
            if not transient and ownership:
                assert incident["dialog"]["pid"] == held_dialogs[-1].pid
                pipe = os.fstat(held_dialogs[-1].launcher.stdout.fileno())
                assert incident["identity"]["dialogPipe"] == dict(device=pipe.st_dev, inode=pipe.st_ino,
                    compositorFd=held_dialogs[-1].launcher.stdout.fileno()), incident
                assert incident["target"]["attribution"] == ("inferred" if candidates == 1 else "unavailable"), incident
                assert incident["target"]["candidates"] == (clients if candidates else []), incident
            saved = incidents[0].parent / "compositor.log"
            assert b"appearance-marker" in saved.read_bytes()
            with log.open("ab") as output:
                output.write(b"later\n" * 200000)
            assert b"appearance-marker" in saved.read_bytes(), "incident replaced by later output"
            return incident, result
        finally:
            stop.set()
            if thread.is_alive():
                thread.join(timeout=3)
            for process in held_dialogs:
                process.close()
            for process in [ordinary, unrelated]:
                if process.poll() is None:
                    process.terminate()
                process.wait(timeout=5)
            if serve.poll() is None:
                try:
                    request(recording / "control", "stop", "normal")
                except (OSError, RuntimeError):
                    serve.terminate()
            serve.communicate(timeout=5)
            fixture.close()
            if stream is not None:
                stream.close()
            nested.close()
            os.close(socket_directory)

    for name, options in (("mapped", {}), ("transient", {"transient": True}),
                          ("unavailable", {"candidates": 0}), ("ambiguous", {"candidates": 2}),
                          ("abandoned-inner-row", {"abandoned": True}),
                          ("ordinary-address-reuse", {"transient": True, "reuse": True}),
                          ("entry-dialog", {"entry": True}),
                          ("typed-launch-variables", {"mutation": "launch-variables"}),
                          ("terminal-shim", {"mutation": "shim"}),
                          ("terminal-shim-read-error", {"mutation": "shim-read-error"}),
                          ("managed-refusal-status", {"mutation": "managed-refusal"}),
                          ("missing-enabled-id", {"mutation": "missing-enabled-id"}),
                          ("end-read-recovers", {"mutation": "end-unreadable-once"}),
                          ("post-read-still-unreadable", {"mutation": "end-unreadable-permanent"})):
        case(name, **options)
        print("smoke-anr: path=" + name + " boundary=pass")
    leaks = (REPO / "scripts/smoke/leaks.sh").read_text()
    needle = "$class == shim && ( $verdict == leaves || $verdict == unreadable )"
    assert leaks.count(needle) == 1
    readable_only = root / "readable-shim-only.sh"
    readable_only.write_text(leaks.replace(needle, "$class == shim && $verdict == leaves"))
    try:
        case("control-readable-shim-only", mutation="shim-read-error", leaks_path=readable_only)
    except AssertionError as error:
        assert str(error).startswith("shim-read-error-continued:"), str(error)
        print("smoke-anr: control=unreadable-shim-continuation rejected")
    else:
        raise AssertionError("unreadable shim continued")
    case("foreign", ownership=False)
    print("smoke-anr: ownership=refused unrelated-processes=kept")
    case("long-socket-path-" + "x" * 110)
    print("smoke-anr: socket-path=parent-fd long-directory=pass")

    capture_dir = root / "capture"
    capture_dir.mkdir()
    capture = namespace["Record"](capture_dir)
    capture.anr_sources = (capture_dir.resolve(),)
    try:
        missing, data = capture.anr_span(capture_dir / "missing")
        assert missing["status"] == "unavailable" and not data
        foreign = root / "foreign-log"
        foreign.write_bytes(b"must-not-copy")
        refused, data = capture.anr_span(foreign)
        assert refused["status"] == "unavailable" and not data
        path = capture_dir / "large"
        path.write_bytes(b"x" * (1024 * 1024) + b"appearance\n")
        clipped, data = capture.anr_span(path)
        assert clipped["status"] == "captured" and clipped["clipped"]
        assert clipped["start"] > 0 and clipped["end"] == path.stat().st_size
        assert len(data) == 1024 * 1024 and data.endswith(b"appearance\n")
        capture.anr_bytes = namespace["CAP_BYTES"]
        full, data = capture.anr_span(path)
        assert full["status"] == "empty-or-capacity" and not data
    finally:
        capture.output.close()
        capture.server.close()
        capture.selector.close()
        if capture.notify_fd is not None:
            os.close(capture.notify_fd)
    print("smoke-anr: capture=bounded missing-and-clipped=explicit")

    # The same recorder owns bounded stopping. A TERM-resistant real child
    # exercises the exit observation before reap; its pidfd stays held by
    # this test even if the cleanup helper fails.
    def stopping(program):
        subject_module = {"__name__": "fixture"}
        exec(compile(program, "display-recorder-stop", "exec"), subject_module)
        subject = subject_module["Record"].__new__(subject_module["Record"])
        process = subprocess.Popen([PYTHON, "-c", 'import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); print("ready",flush=True); time.sleep(60)'],
                                   env=ENV, stdout=subprocess.PIPE)
        handle = os.pidfd_open(process.pid)
        try:
            assert select.select([process.stdout], [], [], 3)[0], "stop fixture readiness"
            assert process.stdout.readline() == b"ready\n"
            try:
                subject.bounded_cleanup("stop_process", (str(process.pid), str(os.getpid())), "7")
            except ValueError as error:
                raise AssertionError("bounded stop failed: " + str(error)) from error
            assert select.select([handle], [], [], 0)[0], "owned generation remains after successful stop"
            process.wait(timeout=1)
        finally:
            if not select.select([handle], [], [], 0)[0]:
                signal.pidfd_send_signal(handle, signal.SIGKILL)
            process.wait(timeout=2)
            os.close(handle)
            process.stdout.close()

    stopping(recorder)
    print("smoke-anr: owned-stop=bounded term-resistant-child=reaped")
    # The forced path's escalation, apart from the orderly stop's deeper one.
    needle = "\n                        signal.pidfd_send_signal(fd, signal.SIGKILL)"
    assert recorder.count(needle) == 1
    try:
        stopping(recorder.replace(needle, "\n                        pass"))
    except AssertionError:
        print("smoke-anr: control=missing-escalation rejected")
    else:
        raise AssertionError("missing escalation passed")

    # An orderly stop leaves a child's TERM to its root's own cleanup. The
    # child reads the sender of its TERM; the forced stop is the control.
    def orderly_sender(orderly):
        subject_module = {"__name__": "fixture"}
        exec(compile(recorder, "display-recorder-orderly", "exec"), subject_module)
        subject = subject_module["Record"].__new__(subject_module["Record"])
        sender = root / f"orderly-sender-{orderly}"
        process = subprocess.Popen([PYTHON, "-c", '''import os,signal,sys,time
signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGTERM})
child = os.fork()
if child == 0:
    info = signal.sigwaitinfo({signal.SIGTERM})
    open(sys.argv[1], "w").write(str(info.si_pid))
    os._exit(0)
def cleanup(signum, frame):
    # The forced control's own TERM reaches the child first.
    time.sleep(0.5)
    os.kill(child, signal.SIGTERM)
    os.waitpid(child, 0)
    os._exit(0)
signal.signal(signal.SIGTERM, cleanup)
print("ready", flush=True)
signal.pthread_sigmask(signal.SIG_UNBLOCK, {signal.SIGTERM})
while True:
    signal.pause()
''', str(sender)], env=ENV, stdout=subprocess.PIPE)
        handle = os.pidfd_open(process.pid)
        try:
            assert select.select([process.stdout], [], [], 3)[0], "orderly fixture readiness"
            assert process.stdout.readline() == b"ready\n"
            result = subject.bounded_cleanup("stop_process", (str(process.pid), str(os.getpid()), None, False, 5 if orderly else None), "7")
            assert select.select([handle], [], [], 0)[0], "orderly root remains after its stop"
            process.wait(timeout=1)
            return sender.read_text() == str(process.pid), result
        finally:
            if not select.select([handle], [], [], 0)[0]:
                signal.pidfd_send_signal(handle, signal.SIGKILL)
            process.wait(timeout=2)
            os.close(handle)
            process.stdout.close()

    sent, result = orderly_sender(True)
    assert sent, "an orderly stop signalled the child itself"
    assert result is None, "an orderly stop that ended in time reported " + str(result)
    print("smoke-anr: orderly-stop=root-cleanup-signals-child")
    sent, _ = orderly_sender(False)
    assert not sent, "control: the forced stop left the child's TERM to its root"
    print("smoke-anr: control=forced-stop-signals-child rejected")

    # A root that outlives the orderly wait is forced, and the stop says so.
    def forced_result(program):
        subject_module = {"__name__": "fixture"}
        exec(compile(program, "display-recorder-forced", "exec"), subject_module)
        subject = subject_module["Record"].__new__(subject_module["Record"])
        process = subprocess.Popen([PYTHON, "-c", 'import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); print("ready",flush=True); time.sleep(60)'],
                                   env=ENV, stdout=subprocess.PIPE)
        handle = os.pidfd_open(process.pid)
        try:
            assert select.select([process.stdout], [], [], 3)[0], "forced fixture readiness"
            assert process.stdout.readline() == b"ready\n"
            result = subject.bounded_cleanup("stop_process", (str(process.pid), str(os.getpid()), None, False, 2), "4")
            assert select.select([handle], [], [], 0)[0], "forced root remains after its stop"
            process.wait(timeout=1)
            return result
        finally:
            if not select.select([handle], [], [], 0)[0]:
                signal.pidfd_send_signal(handle, signal.SIGKILL)
            process.wait(timeout=2)
            os.close(handle)
            process.stdout.close()

    assert forced_result(recorder) == "forced", "a forced orderly stop reported no force"
    print("smoke-anr: orderly-stop=forced-reported")
    needle = '            return "forced" if orderly is not None else None\n'
    assert recorder.count(needle) == 1
    assert forced_result(recorder.replace(needle, "            return None\n")) is None
    print("smoke-anr: control=unreported-force rejected")

    # The shared ss reader, over lines `ss -xpnH` and `ss -xlpnH` printed on
    # the development host on 2026-10-31, the session bus's path standing
    # in for a server's: a client end two processes hold, a client end ss
    # names no holder of, a listener and another server's connection; and
    # a probe's listener holding the server's side of a connection whose
    # client end has closed, which reads peer 0. The same text without the
    # unnamed end's own line is an end that closed after ss read the
    # server's side.
    socket_ends_parse = namespace["socket_ends_parse"]
    recorded = """u_str LISTEN 0      4096                    /run/user/1000/bus 44537      * 0 users:(("dbus-broker",pid=3252,fd=6),("dbus-broker-lau",pid=3251,fd=3))
u_str ESTAB 0      0                       /run/user/1000/bus 813531862  * 813467542  users:(("dbus-broker",pid=3252,fd=15))
u_str ESTAB 0      0                       /run/user/1000/bus 636757598  * 636765959  users:(("dbus-broker",pid=3252,fd=35))
u_str ESTAB 0      0                                        * 636765959  * 636757598
u_str ESTAB 0      0                                        * 813467542  * 813531862  users:(("qs",pid=2973242,fd=12),("sleep",pid=472058,fd=3))
u_str ESTAB 0      0             /run/dbus/system_bus_socket 35110      * 35111      users:(("dbus-broker",pid=1200,fd=9))
u_str ESTAB 0      0                                        * 35111      * 35110      users:(("qs",pid=2973242,fd=14))
u_str ESTAB 0      0                       /run/user/1000/bus 14016517   * 0        users:(("python3",pid=3783770,fd=6))
"""
    unnamed_line = "u_str ESTAB 0      0                                        * 636765959  * 636757598\n"
    assert recorded.count(unnamed_line) == 1
    for text, servers, want in (
        (recorded, {"dbus": "/run/user/1000/bus"}, {813467542: ("dbus", [472058, 2973242]), 636765959: ("dbus", None)}),
        (recorded.replace(unnamed_line, ""), {"dbus": "/run/user/1000/bus"}, {813467542: ("dbus", [472058, 2973242]), 636765959: ("dbus", [])}),
        (recorded, {"system-bus": "/run/dbus/system_bus_socket"}, {35111: ("system-bus", [2973242])}),
        (recorded, {"wayland": "/run/user/1000/wayland-1"}, {}),
        ("", {"dbus": "/run/user/1000/bus"}, {}),
    ):
        assert socket_ends_parse(text, servers) == want, (servers, want)
    print("smoke-anr: socket-ends=client-ends-by-server-path")

    # The shell stop's survivor check (stop_shell_owner) over real owned
    # processes. A python runner starts the shell: a launcher that connects
    # to a listening socket standing in for the nested compositor and execs
    # a copy of sleep named qs, which the stop takes as the shell. A planted
    # launcher first hands that end to a sleeper it detaches with setsid,
    # whose parent exits, as a fork of qs that never reached exec holds it.
    # An in-flight launcher first sends that end in a message to a courier
    # socket the test accepts and never reads, so once qs ends the end is
    # open in no process's descriptor table and ss names no holder of it.
    # On TERM the runner ends its child and exits.
    shell_executable = root / "qs"
    shutil.copy(shutil.which("sleep"), shell_executable)
    no_ss = root / "no-ss"
    no_ss.mkdir()
    (no_ss / "ss").write_text("#!/bin/sh\nexit 3\n")
    (no_ss / "ss").chmod(0o755)
    # sun_path holds 108 bytes and the scratch root can be longer, so both
    # ends name the socket through a /proc/self/fd directory link, as the
    # recorder's own control socket does; ss names the listener by the
    # name it bound, which is the server path the stop is given.
    compositor = root / "wayland-1"
    courier_path = root / "courier"
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    with namespace["socket_name"](compositor) as name:
        listener.bind(name)
    compositor_name = listener.getsockname()
    listener.listen(8)
    courier = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    with namespace["socket_name"](courier_path) as name:
        courier.bind(name)
    courier.listen(8)
    accepted = []
    def accept(server):
        while True:
            try:
                accepted.append(server.accept()[0])
            except OSError:
                return
    for server in (listener, courier):
        threading.Thread(target=accept, args=(server,), daemon=True).start()
    shell_runner = """import signal, subprocess, sys
shell = subprocess.Popen(sys.argv[1:])
def stop(signum, frame):
    shell.terminate()
    shell.wait()
    sys.exit(0)
signal.signal(signal.SIGTERM, stop)
print(shell.pid, flush=True)
while True:
    signal.pause()
"""
    shell_launch = """import array, os, socket, sys
server, plant, record, shell = sys.argv[1:]
def connect(path):
    directory = os.open(os.path.dirname(path), os.O_PATH | os.O_DIRECTORY)
    end = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    end.connect(f"/proc/self/fd/{directory}/{os.path.basename(path)}")
    os.close(directory)
    return end
end = connect(server)
os.set_inheritable(end.fileno(), True)
if plant == "sleeper":
    child = os.fork()
    if child == 0:
        os.setsid()
        sleeper = os.fork()
        if sleeper == 0:
            os.execvp("sleep", ["sleep", "60"])
        with open(record, "w") as out:
            out.write(str(sleeper))
        os._exit(0)
    os.waitpid(child, 0)
elif plant != "-":
    courier = connect(plant)
    courier.sendmsg([b"end"], [(socket.SOL_SOCKET, socket.SCM_RIGHTS, array.array("i", [end.fileno()]))])
    courier.close()
    with open(record, "w") as out:
        out.write(str(os.fstat(end.fileno()).st_ino))
os.execv(shell, ["qs", "60"])
"""

    def sockets_of(pid):
        found = set()
        for entry in (Path("/proc") / str(pid) / "fd").iterdir():
            with contextlib.suppress(FileNotFoundError):
                if stat.S_ISSOCK(entry.stat().st_mode):
                    found.add(entry.stat().st_ino)
        return found

    def shell_stop_case(name, shell, program=recorder, path=None, runner_gone=False, orderly=2.0, bound=4):
        subject_module = {"__name__": "fixture"}
        exec(compile(program, "display-recorder-survivor", "exec"), subject_module)
        subject = subject_module["Record"].__new__(subject_module["Record"])
        subject.nested_wayland = compositor_name
        subject.anr_runtime = root / "runtime"
        record = root / ("survivor-" + name)
        argv = dict(planted=[PYTHON, "-c", shell_launch, str(compositor), "sleeper", str(record), str(shell_executable)],
                    inflight=[PYTHON, "-c", shell_launch, str(compositor), str(courier_path), str(record), str(shell_executable)],
                    clean=[PYTHON, "-c", shell_launch, str(compositor), "-", "-", str(shell_executable)],
                    sleep=[shutil.which("sleep"), "60"])[shell]
        runner = subprocess.Popen([PYTHON, "-c", shell_runner, *argv], env=ENV, stdout=subprocess.PIPE)
        handles = [os.pidfd_open(runner.pid)]
        result = dict(sleeper=None, holds=None)
        try:
            assert select.select([runner.stdout], [], [], 3)[0], "survivor runner readiness"
            shell_pid = runner.stdout.readline().decode().strip()
            for _ in range(300):
                if shell == "sleep" or os.readlink(f"/proc/{shell_pid}/exe") == str(shell_executable):
                    break
                select.select([], [], [], 0.01)
            else:
                raise AssertionError("survivor shell never ran qs")
            if shell == "planted":
                result["sleeper"] = int(record.read_text())
                handles.append(os.pidfd_open(result["sleeper"]))
                result["holds"] = sockets_of(result["sleeper"])
            if shell == "inflight":
                result["end"] = int(record.read_text())
            binding = subject_module["process_binding"]
            subject.shell_owners = {shell_pid: dict(runner=str(runner.pid), pid=shell_pid, identity=binding(shell_pid),
                                                    runnerIdentity=binding(str(runner.pid)))}
            if runner_gone:
                # Ended but unreaped, so its pid names no other process.
                signal.pidfd_send_signal(handles[0], signal.SIGTERM)
                assert select.select([handles[0]], [], [], 3)[0], "survivor runner did not end"
            saved = os.environ["PATH"]
            if path:
                os.environ["PATH"] = path
            try:
                result["answer"] = subject.bounded_cleanup("stop_shell_owner", (str(runner.pid), str(os.getpid()), orderly), bound)
            except ValueError as error:
                result["answer"] = "refused " + str(error)
            finally:
                os.environ["PATH"] = saved
            # A stop that answers before its runner's TERM ran still sent it.
            result["runner"] = "ended" if select.select([handles[0]], [], [], 3)[0] else "running"
            if len(handles) > 1:
                result["sleeper-state"] = "ended" if select.select([handles[1]], [], [], 0)[0] else "running"
            return result
        finally:
            for handle in handles:
                if not select.select([handle], [], [], 0)[0]:
                    signal.pidfd_send_signal(handle, signal.SIGKILL)
                    select.select([handle], [], [], 2)
                os.close(handle)
            runner.wait(timeout=2)
            runner.stdout.close()

    try:
        survived = shell_stop_case("survived", "planted")
        lines = survived["answer"].split("\n")
        assert lines[0] == "survived" and len(lines) == 2, survived
        fields = dict(word.split("=", 1) for word in lines[1].split(" argv=")[0].split()[1:])
        assert fields["pid"] == str(survived["sleeper"]) and lines[1].startswith("survivor "), survived
        assert {int(inode) for inode in fields["holds"].split(",")} == survived["holds"], survived
        assert {"ppid", "pgrp", "sid", "threads", "start", "state", "wchan", "sigblk", "sigpnd", "shdpnd", "coredumping", "fd0"} <= fields.keys()
        assert lines[1].endswith(" argv=[sleep 60]") and survived["sleeper-state"] == "ended" and survived["runner"] == "ended", survived
        print("smoke-anr: shell-stop=survivor-named-and-ended")
        for name, shell, options, want in (
            ("stopped", "clean", {}, "stopped"),
            ("no-shell", "sleep", {}, "stopped\nsurvivor-check=not-run reason=no-shell"),
            ("runner-gone", "clean", {"runner_gone": True}, "stopped\nsurvivor-check=not-run reason=runner-gone"),
            ("unproved", "clean", {"path": f"{no_ss}:{ENV['PATH']}"},
             "refused row-cleanup=stop_shell_owner result=ValueError:row-shell-ends-unreadable:ss-exit-3"),
            # leak-check's force overrun: the table read finds its deadline
            # spent, and the runner still gets its TERM first.
            ("deadline-spent", "clean", {"orderly": 0.0, "bound": 0},
             "refused row-cleanup=stop_shell_owner result=ValueError:row-owner-acquisition-timeout"),
        ):
            got = shell_stop_case(name, shell, **options)
            assert got["answer"] == want and got["runner"] == "ended", (name, got)
            print("smoke-anr: shell-stop=" + name)
        # An end of the stopped shell that is still open with no holder ss
        # can name is no proved close.
        inflight = shell_stop_case("in-flight", "inflight")
        want = f"refused row-cleanup=stop_shell_owner result=ValueError:row-shell-end-open:wayland:{inflight['end']}:holders=unnamed"
        assert inflight["answer"] == want and inflight["runner"] == "ended", inflight
        print("smoke-anr: shell-stop=unnamed-end-unproved")
        # Without the survivor check the planted sleeper outlives the stop.
        needle = "            survivors = self.stop_survivors(ends)\n"
        assert recorder.count(needle) == 1
        unchecked = shell_stop_case("unchecked", "planted", program=recorder.replace(needle, "            survivors = []\n"))
        assert unchecked["answer"] == "stopped" and unchecked["sleeper-state"] == "running", unchecked
        print("smoke-anr: control=no-survivor-check rejected")
    finally:
        listener.close()
        courier.close()
        for connection in accepted:
            connection.close()

    case("crash-original-end", crash=True)
    print("smoke-anr: crash-report=original-client-evidence-before-restoration")
    crash_helpers = helpers.read_text()
    needle = '  smoke_row_crashed_report="$1"\n'
    assert crash_helpers.count(needle) == 1
    premature = root / "premature-crash-cleanup.sh"
    premature.write_text(crash_helpers.replace(needle, needle + '  display_record_call read >/dev/null\n  display_record_call anr-cleanup "$smoke_row_name" >/dev/null\n'))
    try:
        case("control-pre-snapshot-cleanup", crash=True, helper_path=premature)
    except AssertionError as error:
        assert str(error).startswith("raw-client-evidence-missing:"), str(error)
        print("smoke-anr: control=pre-snapshot-crash-cleanup rejected")
    else:
        raise AssertionError("pre-snapshot crash cleanup hid no raw evidence")

    # Keep the behaviour under test while removing one protection in each
    # disposable source copy. Only an assertion failure kills a mutant.
    for name, old, new, options in (
        ("cleanup", "                        signal.pidfd_send_signal(fd, signal.SIGTERM)", "                        pass", {}),
        ("transient", "self.anr_observe(fields[0])", "pass", {"transient": True}),
        ("ownership", "fd, identity = self.anr_owned_handle(pid)",
         "fd, identity = os.pidfd_open(pid), process_binding(str(pid))", {"ownership": False}),
        ("ancestry", "if (peer is None or original.get(\"status\") != \"live\"",
         "if (peer is None or int((pathlib.Path(\"/proc\") / str(pid) / \"stat\").read_text().rsplit(\")\", 1)[1].split()[1]) != self.anr_compositor[\"pid\"] or original.get(\"status\") != \"live\"", {}),
        ("address-only", '''matched = any(c.get("class") == "hyprland-dialog" and c.get("address") == incident["address"]
                      and (expected is None or c.get("pid") == expected) for c in clients)''',
         '''matched = any(c.get("address") == incident["address"] for c in clients)''', {"transient": True, "reuse": True}),
    ):
        assert recorder.count(old) == 1
        mutant = recorder.replace(old, new)
        assert mutant != recorder
        try:
            case("control-" + name, program=mutant, **options)
        except AssertionError:
            print("smoke-anr: control=" + name + " rejected")
        else:
            raise AssertionError("surviving control: " + name)
