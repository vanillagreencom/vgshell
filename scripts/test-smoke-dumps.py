#!/usr/bin/env python3
"""Exercise harness transports, their limits and their must-fail controls."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

HARNESS = Path(__file__).resolve().parent / "smoke/harness.sh"
BASH = shutil.which("bash")
ENV = {"PATH": os.environ.get("PATH", ""), "LC_ALL": "C.UTF-8",
       "VGS_TEST_RUN": "1"}
source = HARNESS.read_text()


def function(name):
    one_line = re.search(r"(?m)^" + name + r"\(\).*}\n", source)
    if one_line:
        return one_line.group()
    found = re.search(r"(?ms)^" + name + r"\(\).*?^}\n", source)
    assert found, name
    return found.group()


with tempfile.TemporaryDirectory(prefix="smoke-dumps-") as scratch:
    root = Path(scratch)
    helper = root / "helpers.sh"
    helper.write_text(function("py_dumps") + function("py_reply"))
    values = [{"kind": kind, "text": 'é\n"\\' * 40000}
              for kind in ("page", "window", "surface", "card", "items")]
    dumps = [json.dumps(value, ensure_ascii=False, indent=2) for value in values]
    assert all(len(value.encode()) > 128 * 1024 for value in dumps)
    fixture = root / "dumps"
    fixture.write_bytes(b"\0".join(value.encode() for value in dumps) + b"\0")
    runner = '''set -euo pipefail
source "$1"
mapfile -d '' -t dumps < "$2"
py_dumps "${dumps[@]}" <<'PY'
import json,sys
print(json.dumps([json.loads(value) for value in sys.argv[1:]]))
PY
'''

    def run(path):
        return subprocess.run([BASH, "-c", runner, "_", str(path), str(fixture)],
                              env=ENV, capture_output=True, text=True, timeout=30)

    result = run(helper)
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout) == values
    print("smoke-dumps: oversized=read dumps=%d bytes=%d" %
          (len(dumps), len(fixture.read_bytes())))

    # The old exec boundary must fail on the same complete inputs.
    mutant = root / "argv.sh"
    mutant.write_text('py_dumps() { python3 - "$@"; }\n')
    control = run(mutant)
    assert control.returncode == 126, (control.returncode, control.stderr)
    assert not control.stdout
    print("smoke-dumps: control=argv-rejected exit=126")

    result = subprocess.run([BASH, "-c", '''set -euo pipefail
source "$1"
py_dumps '' 'a\nb' <<'PY'
import json,sys
print(json.dumps(sys.argv[1:]))
PY
''', "_", str(helper)], env=ENV, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout) == ["", "a\nb"]

    invalid = root / "invalid.json"
    invalid.write_text("[" + "x" * 200000)
    result = subprocess.run([BASH, "-c", '''set -euo pipefail
source "$1"
py_reply 'import sys; sys.exit(23)' < "$2"
''', "_", str(helper), str(invalid)], env=ENV, capture_output=True,
                            text=True, timeout=30)
    assert result.returncode == 23, (result.returncode, result.stderr)
    assert result.stderr and len(result.stderr) < 2000
    print("smoke-dumps: empty-and-multiline=kept diagnostic-exit=23")


# The real smoke_row must reject a timeout even when a reader catches its
# status or runs in a command substitution. The call, page loop, poll,
# leak reading and row verdict run their production code against stand-ins.
with tempfile.TemporaryDirectory(prefix="smoke-ipc-") as scratch:
    root = Path(scratch)
    production = root / "production.sh"
    names = ("ipc_call_last", "ipc_failed", "ipc_page", "ipc_via", "ipc",
             "ipc_at", "ipc_timeout_check", "ipc_oversize_check", "smoke_row",
             "reader_stderr", "expect_poll", "now_ms")
    production.write_text("".join(function(name) for name in names))
    stub = root / "qs"
    stub.write_text('''#!/usr/bin/env bash
set -euo pipefail
shift 4
printf '%s|%s\\n' "$1" "$2" >>"$CASE_DIR/calls"
if [[ "$1 $2" == "${CASE_BLOCK:-}" ]]; then
  if [[ ${CASE_DEFER:-no} != yes || -e $CASE_DIR/block ]]; then
    rm -f -- "$CASE_DIR/block"
    exec sleep infinity
  fi
fi
case "$1 $2" in
  'shell ping') echo ok; exit ;;
  'shell guarded') echo true; exit ;;
  'shell listPlugins') echo paged=7; exit ;;
  'smoke perScreenLayers') echo '[]'; exit ;;
  'smoke reply') printf 'noise\\nanswer\\n'; exit ;;
  'smoke failure') echo refused; exit 17 ;;
esac
exec sleep infinity
''')
    stub.chmod(0o755)
    child = root / "child.sh"
    child.write_text('''set -euo pipefail
unset WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE
repo="$1" sandbox="$2" root="$3" want_timeout="$5"
source "$repo/bin/lib/ipc-reply.sh"
source "$repo/scripts/smoke/verdict.sh"
source "$repo/scripts/smoke/leaks.sh"
source "$4"
block=""
[[ $want_timeout != yes ]] || block="$6 $7"
shell_env=(env -i PATH="$root:$PATH" HOME="$sandbox" XDG_RUNTIME_DIR="$sandbox" CASE_DIR="$sandbox" CASE_BLOCK="$block" CASE_DEFER="$8" VGS_TEST_RUN=1)
printf '%s\\n' "$BASHPID" >"$sandbox/vgshell.lock"
# The short bound tests timer wiring, independently of the measured default.
ipc_call_bound_s=0.1
ipc_last_reply="" ipc_reply_chars=32768 ipc_oversize_log="$sandbox/oversize"
ipc_timeout_log="$sandbox/ipc-timeout.log"
smoke_row_drain_s=5
shell_qs_pid="$BASHPID" timeout_s=1
shell_start_path="$PATH" shell_start_words=()
shim="$sandbox/shim"
mkdir "$shim"
hypr() {
  case "$*" in
    '-j clients') echo '[]' ;;
    '-j descriptions') echo '[{"name":"general:border_size"}]' ;;
    '-j layers') echo '{}' ;;
    '--batch j/getoption general:border_size') echo '{"int":1}' ;;
    *) return 1 ;;
  esac
}
active_window() { echo '[]'; }
key_submap() { echo default; }
devices_guard() { echo stable; }
devices_check() { return 0; }
rest_pointer() { return 0; }
shell_crash_check() { return 0; }
sink_check() { :; }
anr_row_boundary() { :; }
smoke_poll_tries() { smoke_poll_n=50; }
ok() { :; }
smoke_row example "$sandbox"
printf 'result failures=%s behaviour=%s\\n' "$failures" "$behaviour_failures"
if [[ $want_timeout == yes ]]; then
  ((failures > 0 && behaviour_failures > 0))
else
  ((failures == 0 && behaviour_failures == 0))
fi
''')
    cases = (
        ("plain", "ipc smoke descendantGeometry window vgs.settings || true", "smoke", "descendantGeometry", "yes"),
        ("substitution", 'got="$(ipc smoke descendantGeometry window vgs.settings || true)"', "smoke", "descendantGeometry", "yes"),
        ("poll", "reader() { ipc smoke descendantGeometry window vgs.settings || true; echo ok; }; expect_poll example ok reader", "smoke", "descendantGeometry", "yes"),
        ("instance", 'ipc_at "$BASHPID" smoke descendantGeometry window vgs.settings || true', "smoke", "descendantGeometry", "yes"),
        ("page", 'got="$(ipc shell listPlugins)" || true', "shell", "page", "yes"),
        ("geometry", "row_class=geometry; ipc smoke descendantGeometry window vgs.settings || true", "smoke", "descendantGeometry", "yes"),
        ("preflight", ":", "shell", "ping", "yes"),
        ("cleanup", 'touch "$sandbox/block"', "smoke", "perScreenLayers", "yes"),
        ("cleanup-reply", ":", "smoke", "perScreenLayers", "no"),
        ("reply", 'got="$(ipc smoke reply)"; [[ $got == answer ]]', "smoke", "reply", "no"),
        ("status", 'status=0; got="$(ipc smoke failure)" || status=$?; [[ $status == 17 && $got == refused ]]', "smoke", "failure", "no"),
    )

    def ipc_case(helpers, case):
        name, command, target, method, want_timeout = case
        folder = Path(tempfile.mkdtemp(prefix=name + "-", dir=root))
        (folder / "example.sh").write_text(command + "\n")
        result = subprocess.run(
            ["timeout", "--signal=KILL", "3", BASH, str(child),
             str(HARNESS.parents[2]), str(folder), str(root), str(helpers), want_timeout, target, method,
             "yes" if name == "cleanup" else "no"],
            env=ENV, stdin=subprocess.DEVNULL, capture_output=True, text=True)
        assert result.returncode == 0, (name, result.returncode, result.stdout, result.stderr, str(folder))
        # smoke_row consumes this machine-read record to fail the row.
        records = (folder / "rows/example.ipc-timeout.log").read_text().splitlines()
        expected = "ipc-timeout: target=%s function=%s bound_s=0.1" % (target, method)
        assert records == ([expected] if want_timeout == "yes" else []), (name, records)
        calls = (folder / "calls").read_text().splitlines()
        assert calls.count(target + "|" + method) == (2 if method == "perScreenLayers" else 1), (name, calls)
        if name == "cleanup":
            assert "result failures=1 behaviour=1" in result.stdout, result.stdout

    for case in cases:
        ipc_case(production, case)
        print("smoke-ipc: bounded-row=" + case[0])

    # Keep the call intact while removing its deadline. The same row test
    # must reject that disposable implementation at its parent deadline.
    text = production.read_text()
    needle = 'timeout --signal=KILL "$ipc_call_bound_s"'
    assert text.count(needle) == 1
    mutant = root / "unbounded.sh"
    changed = text.replace(needle, "")
    assert changed != text
    mutant.write_text(changed)
    try:
        ipc_case(mutant, cases[0])
    except AssertionError as failure:
        detail = failure.args[0]
        assert len(detail) == 5 and detail[1] in (-9, 137), detail
        calls = (Path(detail[4]) / "calls").read_text().splitlines()
        assert "smoke|descendantGeometry" in calls, calls
        print("smoke-ipc: control=unbounded-rejected")
    else:
        raise AssertionError("unbounded production copy passed")

    # Keep timeout handling intact but restore its premature placement.
    needle = '  ipc_timeout_check "$smoke_row_name" || true\n'
    assert text.count(needle) == 1
    before_cleanup = text.replace(needle, "")
    needle = '  leak_row_end "$smoke_row_name" "$smoke_row_dir"\n'
    assert before_cleanup.count(needle) == 1
    before_cleanup = before_cleanup.replace(needle, '  ipc_timeout_check "$smoke_row_name" || true\n' + needle)
    assert before_cleanup != text
    mutant = root / "premature.sh"
    mutant.write_text(before_cleanup)
    cleanup_case = next(case for case in cases if case[0] == "cleanup")
    try:
        ipc_case(mutant, cleanup_case)
    except AssertionError as failure:
        detail = failure.args[0]
        assert len(detail) == 5 and detail[1] == 1, detail
        assert "result failures=0 behaviour=0" in detail[2], detail
        print("smoke-ipc: control=premature-check-rejected")
    else:
        raise AssertionError("premature timeout check passed")

    # Exercise start-order's snapshot, teardown and holdUntil boundary with
    # the real row runner. Stand-ins own the shell and compositor effects.
    row_source = (HARNESS.parent / "rows/start-order.sh").read_text()
    prefix, _ = row_source.split("# restart_over TREE", 1)
    plant = re.search(r"(?ms)^plant\(\).*?^}\n", row_source)
    assert plant
    restore_helpers = root / "restore-helpers.sh"
    restore_helpers.write_text(production.read_text() + function("expect"))
    observer = root / "world.py"
    observer.write_text('''import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
def state(path):
    if path.is_symlink(): return ["link", str(path.readlink())]
    if path.is_dir(): return ["dir", {p.name: state(p) for p in sorted(path.iterdir())}]
    if path.exists(): return ["file", path.read_text(), path.stat().st_mode & 0o777]
    return ["absent"]
paths = json.loads((root / "paths.json").read_text())
print(json.dumps([state(root / path) for path in paths]))
''')
    restore_child = root / "restore-child.sh"
    setup = '''home="$sandbox/home" dev_state="$sandbox/dev-state" rt_dir="$sandbox"
record_exists() { echo True; }
holder_state() { echo running; }
stop_holder_bound_s=1
stop_shell() {
  if [[ ${start_order_restore_started:-false} == true && $restore_fault == stop ]]; then return 73; fi
  echo stopped >"$sandbox/shell.state"
  rm -f -- "$sandbox/block"
}
start_shell() {
  if [[ ${start_order_restore_started:-false} == true && $restore_fault == start ]]; then return 74; fi
  cat -- "$home/.config/vgshell/shell.json" >"$sandbox/shell.state"
  ipc shell ping >/dev/null
}
default_set_prepare() {
  local path
  for path in "${start_order_paths[@]}"; do
    rm -rf -- "$path"
    echo default >"$path"
  done
}
restore_fault="${9:-none}"
smoke_row start-order "$sandbox"
smoke_row successor "$sandbox"
printf 'restored failures=%s\n' "$failures"
'''
    original_child = child.read_text()
    marker = 'smoke_row example "$sandbox"'
    assert original_child.count(marker) == 1
    restore_child.write_text(original_child.split(marker, 1)[0].replace('mkdir "$shim"', 'mkdir -p "$shim"') + setup)

    def restore_case(row_prefix, fault="none"):
        folder = Path(tempfile.mkdtemp(prefix="restore-", dir=root))
        paths = ["home/.config/vgshell/shell.json",
                 "home/.config/vgshell/plugins/acme.locker",
                 "home/.config/vgshell/plugins/acme.contention",
                 "shim/mise", "shim/docker", "shim/podman", "shim/pacman",
                 "dev-state", "home/.local/state/vgshell/updates/status.json",
                 "shell.state"]
        (folder / "paths.json").write_text(json.dumps(paths))
        for path in paths:
            (folder / path).parent.mkdir(parents=True, exist_ok=True)
        for path in (paths[0], paths[6], paths[8], paths[9]):
            (folder / path).write_text("incoming\n")
        for path in (paths[1], paths[7]):
            (folder / path).mkdir()
            (folder / path / "fixture").write_text("incoming\n")
        (folder / paths[3]).symlink_to("pacman")
        before = subprocess.check_output([shutil.which("python3"), str(observer), str(folder)], env=ENV)
        (folder / "start-order.sh").write_text(row_prefix + plant.group() + '''
stop_shell
default_set_prepare
start_shell "$repo" "$sandbox/default.log"
touch "$sandbox/block"
ipc shell ping || true
plant restart
echo unreachable >"$sandbox/after-plant"
''')
        (folder / "successor.sh").write_text('python3 "$root/world.py" "$sandbox" >"$sandbox/successor.world"\n')
        result = subprocess.run(
            ["timeout", "--signal=KILL", "10", BASH, str(restore_child),
             str(HARNESS.parents[2]), str(folder), str(root), str(restore_helpers),
             "yes", "shell", "ping", "yes", fault],
            env=ENV, stdin=subprocess.DEVNULL, capture_output=True, text=True)
        assert (folder / "rows/start-order.ipc-timeout.log").exists(), (result.returncode, result.stdout, result.stderr)
        assert not (folder / "after-plant").exists(), result.stdout
        records = (folder / "rows/start-order.ipc-timeout.log").read_text().splitlines()
        assert records == ["ipc-timeout: target=shell function=ping bound_s=0.1"], records
        assert "ipc-timeout-latched: target=smoke function=holdUntil" in result.stdout, result.stdout
        assert "status=124," in result.stdout, result.stdout
        if fault != "none":
            assert result.returncode == 124, (result.returncode, result.stdout, result.stderr)
            assert not (folder / "successor.world").exists(), result.stdout
        else:
            assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
            assert (folder / "successor.world").read_bytes() == before, "successor inherited changed world"
            assert "restored failures=0" not in result.stdout, result.stdout
        print("smoke-ipc: restore-case=%s\n%s" % (fault, result.stdout))
        return result

    restore_case(prefix)
    for fault in ("stop", "start"):
        restore_case(prefix, fault)
    print("smoke-ipc: restoration=incoming-world failure=124 failed-restore=ends-run")

    needle = 'smoke_row_abandon=(start_order_restore)\n'
    assert prefix.count(needle) == 1
    pre_fix = prefix.replace(needle, "")
    assert pre_fix != prefix
    try:
        restore_case(pre_fix)
    except AssertionError as failure:
        assert failure.args == ("successor inherited changed world",), failure
        print("smoke-ipc: control=missing-restoration-rejected successor=leaked-world")
    else:
        raise AssertionError("missing start-order restoration passed")
