#!/usr/bin/env python3
"""Exercise the production copier and the world cleanup owner without a display."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

REPO = Path(__file__).resolve().parent.parent
BASH = shutil.which("bash")
ENV = {"PATH": os.environ["PATH"], "LC_ALL": "C.UTF-8", "VGS_TEST_RUN": "1",
       "TMPDIR": os.environ["TMPDIR"], "VGSHELL_WORLD_ROOT": os.environ["VGSHELL_WORLD_ROOT"]}
NODE = subprocess.check_output(["node", "-e", "process.stdout.write(process.execPath)"], text=True)
ENV["PATH"] = str(Path(NODE).parent) + ":" + ENV["PATH"]
BOUND = 8 * 1024 * 1024


def fixture(root, failed=True, oversized=False, row="example"):
    sandbox = root / "sandbox"
    runtime = root / "runtime"
    output = root / "logs"
    for path in (sandbox / "evidence/failed", sandbox / ("rows/" + row + ".dumps/nested"), sandbox / "leaks/1-1",
                 runtime / "quickshell/by-id/example", runtime / "hypr/example", output):
        path.mkdir(parents=True)
    instance = runtime / "quickshell/by-id/example/log.log"
    instance.write_bytes(b"instance\n")
    (runtime / "hypr/example/hyprland.log").write_bytes(b"compositor\n")
    (sandbox / "sink.log").write_bytes(b"sink\n")
    (sandbox / ("rows/" + row + ".out")).write_bytes(b"probe dump\n")
    (sandbox / ("rows/" + row + ".dumps/nested/reading.json")).write_bytes(b'{"frame":7}\n')
    (sandbox / "leaks/1-1/layers").write_bytes(b'{"geometry":[0,0,10,10]}\n')
    (sandbox / "evidence/destination").write_text(str(output) + "\n")
    (sandbox / "evidence/runtime").write_text(str(runtime) + "\n")
    (sandbox / "evidence/runtime-backing").write_text(str(runtime) + "\n")
    if failed:
        (sandbox / "evidence/active").write_text(row + "\n" + str(instance) + "\n1-1\n")
    if oversized:
        for index in range(12):
            (sandbox / ("rows/example.%02d" % index)).write_bytes(b"x" * (2 * 1024 * 1024))
    return sandbox, runtime, output


def snapshot(output, row="example"):
    folders = list(output.glob("smoke-evidence-*/" + row))
    assert len(folders) == 1, folders
    folder = folders[0]
    assert (folder / "instance-example.log").read_bytes() == b"instance\n"
    assert (folder / "compositor-example.log").read_bytes() == b"compositor\n"
    assert (folder / "sink.log").read_bytes() == b"sink\n"
    assert (folder / ("row/" + row + ".out")).read_bytes() == b"probe dump\n"
    assert (folder / ("row/" + row + ".dumps/nested/reading.json")).read_bytes() == b'{"frame":7}\n'
    assert (folder / "probes/1-1/layers").read_bytes() == b'{"geometry":[0,0,10,10]}\n'
    return sum(p.stat().st_size for p in folder.rglob("*") if p.is_file())


with tempfile.TemporaryDirectory(prefix="smoke-evidence-") as scratch:
    root = Path(scratch)
    child = root / "child.sh"
    child.write_text('''set -euo pipefail
source_repo="$1" sandbox="$2" rt_dir="$3" mode="$4"
pgids=() keep=false
[[ $mode != keep ]] || keep=true
source "$source_repo/scripts/smoke/teardown.sh"
if [[ $mode == producer ]]; then
  source "$5"
  notes() { printf '%s\\n' '{"rows":[]}'; }
  producer_status=0
  fade_inventory || producer_status=$?
  [[ $producer_status == 1 ]] || exit 95
  exit 19
fi
case $mode in
  pass) exit 0 ;;
  fail|keep|copy-error|restart) exit 19 ;;
  TERM) kill -TERM "$BASHPID" ;;
  KILL) kill -KILL "$BASHPID" ;;
esac
''')
    bootstrap = root / "bootstrap.sh"
    bootstrap.write_text("""set -euo pipefail
script="$1" source_repo="$2" old_sandbox="$3" old_runtime="$4" mode="$5"
shift 5
sandbox="$(mktemp -d "$TMPDIR/vgshell-smoke.XXXXXX")"
runtime="$(mktemp -d "$XDG_RUNTIME_DIR/owned/vs.XXXXXX")"
cp -a -- "$old_sandbox/." "$sandbox/"
cp -a -- "$old_runtime/." "$runtime/"
python3 - "$sandbox" "$old_runtime" "$runtime" <<'PYBOOT'
from pathlib import Path
import sys
sandbox, old, new = sys.argv[1:]
for file in Path(sandbox, 'evidence').rglob('*'):
    if file.is_file(): file.write_text(file.read_text().replace(old, new))
PYBOOT
printf '%s\\n' "$VGSHELL_WORLD_ROOT/runtime/${runtime##*/}" >"$sandbox/evidence/runtime-backing"
printf '%s\\n%s\\n' "$sandbox" "$VGSHELL_WORLD_ROOT/runtime/${runtime##*/}" >"${old_sandbox%/*}/actual"
exec "$BASH" "$script" "$source_repo" "$sandbox" "$runtime" "$mode" "$@"
""")

    def world(script, sandbox, runtime, mode, env, extra=()):
        env["HOME"] = str(root / "caller-home")
        declarations = ["--fresh", "--out", str(sandbox.parent)]
        if mode == "keep": declarations.append("--keep")
        result = subprocess.run([BASH, str(REPO / "scripts/smoke/gpu-fence.sh"), *declarations,
                                 BASH, str(bootstrap), str(script), str(REPO), str(sandbox), str(runtime), mode, *map(str, extra)],
                                env=env, capture_output=True, text=True, timeout=30)
        actual = (sandbox.parent / "actual").read_text().splitlines()
        return result, Path(actual[0]), Path(actual[1])

    for mode, status in (("pass", 0), ("fail", 19), ("TERM", 143), ("KILL", 137),
                         ("keep", 19), ("copy-error", 19), ("restart", 19)):
        case = root / mode
        sandbox, runtime, output = fixture(case, failed=mode != "pass")
        if mode == "restart":
            for index in range(10):
                folder = runtime / ("quickshell/by-id/z-older-%02d" % index)
                folder.mkdir()
                (folder / "log.log").write_bytes(b"x" * 1024 * 1024)
            latest = runtime / "quickshell/by-id/a-newest/log.log"
            latest.parent.mkdir()
            latest.write_bytes(b"restarted instance\n")
            # The newest instance's id sorts before the old ones. Both the
            # starting log and this log must survive when older logs fill cap.
            timestamp = max(p.stat().st_mtime_ns for p in runtime.rglob("log.log")) + 1000000
            os.utime(latest, ns=(timestamp, timestamp))
        if mode == "copy-error":
            # A real write refusal must preserve the original failing exit.
            output.rmdir()
            output.write_text("not a directory")
        env = dict(ENV, HOME=str(case), TMPDIR=str(case))
        result, sandbox, runtime = world(child, sandbox, runtime, mode, env)
        assert result.returncode == status, (mode, result.returncode, result.stdout, result.stderr)
        assert sandbox.exists() == (mode == "keep"), (mode, sandbox)
        assert runtime.exists() == (mode == "keep"), (mode, runtime)
        if mode == "pass":
            assert not list(output.iterdir())
        elif mode != "copy-error":
            size = snapshot(output)
            assert 0 < size < BOUND, size
            if mode == "restart":
                newest = next(output.glob("smoke-evidence-*/example/instance-a-newest.log"))
                assert newest.read_bytes() == b"restarted instance\n"
        print("smoke-evidence: exit-path=%s preserved-exit=%d" % (mode, status))

    # Read the actual failure-dump producer and its reply reader. The only
    # stand-in is panel-state's valid response with insufficient fixtures.
    producer_source = (REPO / "scripts/smoke/rows/notifications.sh").read_text()
    reader_source = (REPO / "scripts/smoke/harness.sh").read_text()
    extracted = []
    functions = [(reader_source, "py_reply")]
    functions.extend((producer_source, name) for name in (
        "fade_inventory", "fade_probe_file", "fade_read_probe", "fade_read_geometry",
        "fade_read_context", "fade_capture_geometry_same", "fade_capture_layout"))
    for source, name in functions:
        match = re.search(r"(?ms)^" + name + r"\(\).*?^}\n", source)
        assert match, name
        extracted.append(match.group())
    producer = root / "producer.sh"
    producer.write_text("".join(extracted))

    def producer_case(name, source):
        case = root / name
        sandbox, runtime, output = fixture(case, row="notifications")
        result, sandbox, runtime = world(child, sandbox, runtime, "producer", dict(ENV, HOME=str(case), TMPDIR=str(case)), (source,))
        assert result.returncode == 19, (result.returncode, result.stdout, result.stderr)
        assert not sandbox.exists() and not runtime.exists()
        snapshot(output, "notifications")
        dumped = next(output.glob("smoke-evidence-*/notifications/row/notifications.fade-inventory-failure.json"), None)
        assert dumped is not None, "producer-dump-missing"
        assert dumped.read_bytes() == b'{"rows":[]}\n'

    producer_case("producer", producer)
    print("smoke-evidence: actual-fade-inventory=retained-through-cleanup")
    needle = '$sandbox/rows/notifications.fade-inventory-failure.json'
    text = producer.read_text()
    assert text.count(needle) == 1
    old_producer = root / "old-producer.sh"
    changed = text.replace(needle, '$sandbox/fade-inventory-failure.json')
    assert changed != text
    old_producer.write_text(changed)
    try:
        producer_case("producer-control", old_producer)
    except AssertionError as error:
        assert str(error) == "producer-dump-missing", error
        print("smoke-evidence: control=old-producer-dump-rejected")
    else:
        raise AssertionError("legacy producer dump path survived")

    # Exercise the shared raw writer, the real layout reader/copy and context
    # writer. Only the IPC/frame/environment responses are stand-ins.
    geometry_child = root / "geometry-child.sh"
    geometry_child.write_text('''set -euo pipefail
source_repo="$1" sandbox="$2" rt_dir="$3" scenario="$4"
pgids=() keep=false
source "$source_repo/scripts/smoke/teardown.sh"
source "$5"
geometry_reads=0
ipc() {
  geometry_reads=$((geometry_reads+1))
  case "$scenario:$geometry_reads" in
    previous-invalid:1|current-invalid:2) printf 'invalid-geometry\\n'; return ;;
    previous-interrupted:1|current-interrupted:2)
      printf 'partial-geometry'; kill -KILL "$BASHPID" ;;
  esac
  if [[ $geometry_reads == 1 ]]; then printf '[{"frame":1}]\\n'
  else printf '[{"frame":2}]\\n'; fi
}
fade_current_view() {
  if [[ $scenario == context-view-invalid ]]; then printf 'invalid-view\\n'; return; fi
  printf '{"box":[0,0,10,10]}\\n'
}
surface_box() {
  if [[ $scenario == context-surface-interrupted ]]; then
    printf 'partial-surface'; kill -KILL "$BASHPID"
  fi
  printf '[0,0,10,10]\\n'
}
look_at() {
  if [[ $scenario == context-ink-invalid ]]; then printf 'invalid-ink\\n'; return; fi
  printf '"#ffffff"\\n'
}
smoke_poll_tries() { smoke_poll_n=3; }
fade_panel_frames_read() { printf '0\\n'; }
fade_wait_panel_frame_after() { fade_panel_frame_count=1; }
actual=0
if [[ $scenario == context* ]]; then
  fade_read_context panel-sheet-dark-rest || actual=$?
else
  fade_capture_layout panel-sheet-dark-rest-items.json || actual=$?
fi
case "$scenario" in
  layout|context) [[ $actual == 0 ]] || exit 95 ;;
  *) [[ $actual == 1 ]] || exit 95 ;;
esac
exit 19
''')
    items = "panel-sheet-dark-rest-items.json"
    previous = items + "-previous.json"
    frame1, frame2 = b'[{"frame":1}]\n', b'[{"frame":2}]\n'
    context = {items: frame1, "panel-sheet-dark-rest-view.json": b'{"box":[0,0,10,10]}\n',
               "panel-sheet-dark-rest-surface.json": b'[0,0,10,10]\n',
               "panel-sheet-dark-rest-ink.json": b'"#ffffff"\n'}
    geometry_cases = (
        ("layout", 19, {items: frame2, previous: frame2}),
        ("previous-invalid", 19, {previous: b"invalid-geometry\n"}),
        ("current-invalid", 19, {previous: frame1, items: b"invalid-geometry\n"}),
        ("previous-interrupted", 137, {previous: b"partial-geometry"}),
        ("current-interrupted", 137, {previous: frame1, items: b"partial-geometry"}),
        ("context", 19, context),
        ("context-view-invalid", 19,
         {items: frame1, "panel-sheet-dark-rest-view.json": b"invalid-view\n"}),
        ("context-surface-interrupted", 137,
         {items: frame1, "panel-sheet-dark-rest-view.json": context["panel-sheet-dark-rest-view.json"],
          "panel-sheet-dark-rest-surface.json": b"partial-surface"}),
        ("context-ink-invalid", 19, dict(context, **{"panel-sheet-dark-rest-ink.json": b"invalid-ink\n"})),
    )

    def geometry_case(name, scenario, status, expected, source):
        case = root / name
        sandbox, runtime, output = fixture(case, row="notifications")
        # These real sandbox categories must remain outside diagnostic retention.
        (sandbox / "panel-sheet-dark-rest.png").write_bytes(b"capture")
        (sandbox / "notifications-background-state").mkdir()
        (sandbox / "notifications-background-state/theme.json").write_bytes(b"setup")
        result, sandbox, runtime = world(geometry_child, sandbox, runtime, scenario, dict(ENV, HOME=str(case), TMPDIR=str(case)), (source,))
        assert result.returncode == status, (scenario, result.returncode, result.stdout, result.stderr)
        assert not sandbox.exists() and not runtime.exists()
        snapshot(output, "notifications")
        retained = next(output.glob("smoke-evidence-*/notifications"))
        probes = retained / "row/notifications.probes"
        assert probes.is_dir(), "probe-dump-missing"
        assert {path.name: path.read_bytes() for path in probes.iterdir()} == expected, scenario
        assert not list(retained.rglob("*.png"))
        assert not list(retained.rglob("theme.json"))
        assert sum(path.stat().st_size for path in retained.rglob("*") if path.is_file()) < BOUND

    for scenario, status, expected in geometry_cases:
        geometry_case("geometry-" + scenario, scenario, status, expected, producer)
        print("smoke-evidence: shared-probe=%s preserved-exit=%s" % (scenario, status))
    needle = "printf '%s/rows/notifications.probes/%s"
    text = producer.read_text()
    assert text.count(needle) == 1
    changed = text.replace(needle, "printf '%s/%s")
    assert changed != text
    old_geometry = root / "old-geometry-owner.sh"
    old_geometry.write_text(changed)
    try:
        geometry_case("geometry-control", "current-interrupted", 137,
                      {previous: frame1, items: b"partial-geometry"}, old_geometry)
    except AssertionError as error:
        assert str(error) == "probe-dump-missing", error
        print("smoke-evidence: control=old-geometry-owner-rejected")
    else:
        raise AssertionError("old raw-probe owner survived")

    case = root / "bound"
    sandbox, runtime, output = fixture(case, oversized=True)
    result = subprocess.run(["python3", str(REPO / "scripts/smoke/evidence.py"), str(case), str(sandbox), str(output)],
                            env=ENV, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stderr
    retained = next(output.glob("smoke-evidence-*/example"))
    total = sum(p.stat().st_size for p in retained.rglob("*") if p.is_file())
    assert 7 * 1024 * 1024 < total <= BOUND, total
    assert all(p.stat().st_size <= 1024 * 1024 for p in retained.rglob("*") if p.is_file())
    print("smoke-evidence: bound retained-bytes=%d bound-bytes=%d" % (total, BOUND))

    # Keep inputs intact but remove the copy. The same snapshot assertions
    # must reject that disposable production implementation.
    copier = REPO / "scripts/smoke/evidence.py"
    source = copier.read_text()
    def incident_snapshot(name, program):
        sandbox, runtime, output = fixture(root / name, oversized=True)
        incident = sandbox / "rows/example.anr/1"
        incident.mkdir(parents=True)
        (incident / "incident.json").write_text('{"receiptMonotonicNs":123,"spans":[{"start":0,"end":18}]}\n')
        frozen = b"appearance-marker\n" + b"before\n" * 100000
        (incident / "compositor.log").write_bytes(frozen)
        # Later output replaces the generic retained tail, not the frozen
        # incident. Oversized ordinary row dumps compete for the same cap.
        with (runtime / "hypr/example/hyprland.log").open("ab") as stream:
            stream.write(b"later\n" * 200000)
        result = subprocess.run(["python3", str(program), str(sandbox.parent), str(sandbox), str(output)],
                                env=ENV, capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, result.stderr
        retained = next(output.glob("smoke-evidence-*/example"))
        saved = retained / "row/example.anr/1/compositor.log"
        assert saved.is_file() and saved.read_bytes() == frozen, "appearance span lost"
        assert (retained / "row/example.anr/1/incident.json").read_bytes() == (incident / "incident.json").read_bytes()
        files = [p for p in retained.rglob("*") if p.is_file()]
        assert sum(p.stat().st_size for p in files) <= BOUND
        assert all(p.stat().st_size <= 1024 * 1024 for p in files)

    incident_snapshot("anr", copier)
    print("smoke-evidence: anr-appearance=retained later-output=excluded cap=held")
    first = source.index('        incident_root = sandbox / "rows" / (row + ".anr")\n')
    last = source.index('        instances = ', first)
    changed = source[:first] + source[last:]
    assert changed != source
    late = root / "late-anr.py"
    late.write_text(changed)
    try:
        incident_snapshot("anr-control", late)
    except AssertionError:
        print("smoke-evidence: control=late-anr-span-rejected")
    else:
        raise AssertionError("unprioritized ANR span passed")

    needle = 'entry.rglob("*")'
    assert source.count(needle) == 1
    changed = source.replace(needle, 'entry.glob("*")')
    assert changed != source
    mutant = root / "no-directory-copy.py"
    mutant.write_text(changed)
    sandbox, runtime, output = fixture(root / "directory-control")
    result = subprocess.run(["python3", str(mutant), str(sandbox.parent), str(sandbox), str(output)], env=ENV,
                            capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stderr
    try:
        snapshot(output)
    except FileNotFoundError as error:
        assert str(error.filename).endswith("/row/example.dumps/nested/reading.json"), error
        print("smoke-evidence: control=directory-omission-rejected")
    else:
        raise AssertionError("nonrecursive copier passed")

    needle = "        retain(Path(sys.argv[1]), Path(sys.argv[2]), [Path(path) for path in sys.argv[3:]])"
    assert source.count(needle) == 1
    changed = source.replace(needle, "        pass")
    assert changed != source
    mutant = root / "no-copy.py"
    mutant.write_text(changed)
    sandbox, runtime, output = fixture(root / "control")
    result = subprocess.run(["python3", str(mutant), str(sandbox.parent), str(sandbox), str(output)], env=ENV,
                            capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stderr
    try:
        snapshot(output)
    except AssertionError:
        print("smoke-evidence: control=missing-copy-rejected")
    else:
        raise AssertionError("disabled copier passed")
