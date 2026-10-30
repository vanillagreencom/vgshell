#!/usr/bin/env python3
"""Drive real recorder events and smoke_row boundaries with owned fixtures."""
import json
import os
from pathlib import Path
import re
import select
import shutil
import signal
import socket
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
    helpers.write_text("".join(function(name) for name in ("py_dumps", "py_reply", "anr_row_boundary", "smoke_row", "now_ms", "cpu_some_us", "cpu_some_pct", "load_average", "smoke_row_secs")))
    driver = root / "driver.sh"
    driver.write_text('''set -euo pipefail
repo="$1" sandbox="$2" display_record_dir="$3"
source "$repo/scripts/smoke/verdict.sh"
source "$repo/scripts/smoke/leaks.sh"
source "$4"
display_record_call() { python3 "$display_record_dir/recorder.py" request "$display_record_dir/control" "$@"; }
ipc() { if [[ "$*" == 'shell ping' ]]; then echo ok; else echo '[]'; fi; }
# This recorder-only fixture starts no registry or bus. Stable neutral
# sensors keep the successor assertion about ANR cleanup.
leak_plugins() { echo '{"scanned":true,"plugins":[{"id":"vgs.bar","enabled":true}]}'; }
leak_bus_names() { echo 'org.freedesktop.DBus run:fixture'; }
hypr() {
  case "$*" in
    '-j clients') cat "$sandbox/clients.json" ;;
    '-j descriptions') echo '[{"name":"general:border_size"}]' ;;
    '-j layers') echo '{}' ;;
    '--batch j/getoption general:border_size') echo '{"int":1}' ;;
    *) return 1 ;;
  esac
}
active_window() { python3 -c 'import json,sys; cs=json.load(open(sys.argv[1])); ds=[c for c in cs if c["class"]=="hyprland-dialog"]; print(json.dumps([ds[0]["class"],ds[0]["title"]] if ds else []))' "$sandbox/clients.json"; }
key_submap() { echo default; }
devices_guard() { echo stable; }
devices_check() { return 0; }
rest_pointer() { :; }
shell_crash_check() { return 0; }
sink_check() { :; }
ipc_oversize_check() { :; }
ipc_timeout_check() { return 0; }
ok() { :; }
shim="$sandbox/shim"; mkdir "$shim"
shell_start_path="$PATH" shell_start_words=() shell_env=()
shell_qs_pid="" timeout_s=1 smoke_row_drain_s=5
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

    def case(name, program=recorder, transient=False, ownership=True, candidates=1, abandoned=False, reuse=False):
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
            row += f'python3 "{client}" "{directory / "fixture"}" start\n'
            if transient:
                row += f'python3 "{client}" "{directory / "fixture"}" close\n'
            (sandbox / "planted.sh").write_text(row)
            (sandbox / "successor.sh").write_text('''python3 -c 'import json,sys; cs=json.load(open(sys.argv[1])); assert all(c["class"]!="hyprland-dialog" for c in cs)' "$sandbox/clients.json"
printf 'successor-ran\\n'
''')
            result = subprocess.run([BASH, str(driver), str(REPO), str(sandbox), str(recording), str(helpers)],
                                    env=ENV, capture_output=True, text=True, timeout=15)
            assert not errors, errors
            incidents = list((sandbox / "rows/planted.anr").glob("*/incident.json"))
            assert len(incidents) == 1, (incidents, result.stdout, result.stderr)
            incident = json.loads(incidents[0].read_text())
            assert result.stdout.count("FAIL  anr-dialog:") == 1, result.stdout
            assert ordinary.poll() is None and unrelated.poll() is None
            if ownership:
                assert "successor-ran" in result.stdout, result.stdout
                assert result.returncode == 0, (result.stdout, result.stderr)
                assert incident["cleanup"] in ("removed", "already-closed"), incident
                if reuse:
                    assert incident["cleanup"] == "already-closed", incident
                    assert "continuation before=2 after=2" in result.stdout, result.stdout
                held_dialogs[-1].wait_ended()
            else:
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
                          ("ordinary-address-reuse", {"transient": True, "reuse": True})):
        case(name, **options)
        print("smoke-anr: path=" + name + " continuation=pass")
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

    # Keep the behaviour under test while removing one protection in each
    # disposable source copy. Only an assertion failure kills a mutant.
    for name, old, new, options in (
        ("cleanup", "signal.pidfd_send_signal(fd, signal.SIGTERM)", "pass", {}),
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
