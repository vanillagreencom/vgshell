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
# status or runs in a command substitution. Only qs is a transport stub;
# the call, page loop, poll and row verdict run their production code.
with tempfile.TemporaryDirectory(prefix="smoke-ipc-") as scratch:
    root = Path(scratch)
    production = root / "production.sh"
    names = ("ipc_call_last", "ipc_failed", "ipc_page", "ipc_via", "ipc",
             "ipc_at", "ipc_timeout_check", "ipc_oversize_check", "smoke_row",
             "reader_stderr", "expect_poll")
    production.write_text("".join(function(name) for name in names))
    stub = root / "qs"
    stub.write_text('''#!/usr/bin/env bash
set -euo pipefail
shift 4
printf '%s|%s\\n' "$1" "$2" >>"$CASE_DIR/calls"
[[ "$1 $2" != "${CASE_BLOCK:-}" ]] || exec sleep infinity
case "$1 $2" in
  'shell ping') echo ok; exit ;;
  'shell listPlugins') echo paged=7; exit ;;
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
source "$4"
block=""
[[ $want_timeout != yes ]] || block="$6 $7"
shell_env=(env -i PATH="$root:$PATH" HOME="$sandbox" XDG_RUNTIME_DIR="$sandbox" CASE_DIR="$sandbox" CASE_BLOCK="$block" VGS_TEST_RUN=1)
printf '%s\\n' "$BASHPID" >"$sandbox/vgshell.lock"
# The short bound tests timer wiring, independently of the measured default.
ipc_call_bound_s=0.1
ipc_last_reply="" ipc_reply_chars=32768 ipc_oversize_log="$sandbox/oversize"
ipc_timeout_log="$sandbox/ipc-timeout.log"
smoke_row_drain_s=5
leak_starts=()
devices_check() { return 0; }
rest_pointer() { return 0; }
leak_row_start() { leak_starts+=(active); }
leak_row_end() { leak_starts=(); }
shell_crash_check() { return 0; }
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
        ("reply", 'got="$(ipc smoke reply)"; [[ $got == answer ]]', "smoke", "reply", "no"),
        ("status", 'status=0; got="$(ipc smoke failure)" || status=$?; [[ $status == 17 && $got == refused ]]', "smoke", "failure", "no"),
    )

    def ipc_case(helpers, case):
        name, command, target, method, want_timeout = case
        folder = Path(tempfile.mkdtemp(prefix=name + "-", dir=root))
        (folder / "example.sh").write_text(command + "\n")
        result = subprocess.run(
            ["timeout", "--signal=KILL", "3", BASH, str(child),
             str(HARNESS.parents[2]), str(folder), str(root), str(helpers), want_timeout, target, method],
            env=ENV, stdin=subprocess.DEVNULL, capture_output=True, text=True)
        assert result.returncode == 0, (name, result.returncode, result.stdout, result.stderr, str(folder))
        # smoke_row consumes this machine-read record to fail the row.
        records = (folder / "rows/example.ipc-timeout.log").read_text().splitlines()
        expected = "ipc-timeout: target=%s function=%s bound_s=0.1" % (target, method)
        assert records == ([expected] if want_timeout == "yes" else []), (name, records)
        calls = (folder / "calls").read_text().splitlines()
        assert calls.count(target + "|" + method) == 1, (name, calls)

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
