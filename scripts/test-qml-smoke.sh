#!/usr/bin/env bash
# Exercise fatal-row recovery through the real entry, world and smoke_row.
# A disposable runtime tree uses neutral core rows, two fatal forms and a
# consumer of a provider's function/private variable. Each attempt starts
# real nested Hyprland and VGS; no host session is used. The mutant disables
# only driver resumption, so the rows after the fatal one have no result:
# its summary must name each unreached and count it as failed.
# --case resume runs that existing recovery case alone; --case cancellation
# sends INT, TERM and HUP to the public PID in initial and resumed worlds.
# --case producer checks the controller's recorded bare executable form.
# --case popup-readiness checks the required native helper's failed return
# through bt_main and its row cleanup, without a compositor or device.
# --case completion checks acknowledged lifecycle boundaries without QML,
# and that a unit's stop mid-row leaves the attempt's closing reading.
# --case unmeasured checks unreached rows before and after world setup.
# --case late-exit stops real initial and resumed worlds during EXIT.
# --case hold runs two real worlds against harness.sh's quiet-host hold:
# after a run killed while it holds the hold, one world's timed window
# waits for the other world's current row to end, and that world reaches
# its next row boundary while the hold is waited for but starts the row
# only after the hold ends. Its control takes the hold shared, not
# exclusively, and its window must overlap the other world's row.
# The full run also plants a row that goes silent, with TERM ignored, after
# a row that prints slowly past the bound: the driver's no-progress stop
# goes unanswered, so the driver ends the world through its namespace init
# one bound later, the fence keeps the hung row's evidence, and the run
# ends within two bounds of the stop naming the silent row, never the slow
# one.
# Each cancellation case has the private PID namespace and 60 s readiness /
# 30 s stop bounds of test-smoke-owner.sh --live. A world still starting at
# the readiness bound is not measured when the case's window's CPU pressure,
# read from the run's own cgroup as harness.sh's cpu_some_us reads it, is
# above harness.sh's latency_pressure_limit: the run then ends 77 with the
# reading, unless a case failed. Its end contains defects.
set -euo pipefail
selected_case=all
unmeasured_cases=()
end_run() {
  ((${#unmeasured_cases[@]} == 0)) || { printf 'test-qml-smoke: status=not-measured cases=%s\n' "${unmeasured_cases[*]}"; exit 77; }
  exit 0
}
if [[ ${1-} == --case && $# == 2 ]]; then
  selected_case=$2
  case "$selected_case" in resume|cancellation|producer|completion|late-exit|popup-readiness|unmeasured|hold) ;; *) echo 'test-qml-smoke: refused: case' >&2; exit 2 ;; esac
elif (($#)); then
  echo 'test-qml-smoke: refused: arguments' >&2
  exit 2
fi
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)" || { echo 'test-qml-smoke: scratch=mktemp-failed' >&2; exit 1; }
[[ -d $TMP_ROOT && ! -L $TMP_ROOT ]] || { echo 'test-qml-smoke: scratch=not-a-directory' >&2; exit 1; }
TMP_ROOT="$(cd -- "$TMP_ROOT" && pwd -P)" || { echo 'test-qml-smoke: scratch=resolve-failed' >&2; exit 1; }
trap 'rm -rf -- "${TMP_ROOT:?}"' EXIT
if [[ $selected_case == popup-readiness || $selected_case == all ]]; then
  # Keep the actual bt_main and row cleanup. The native prerequisite can
  # return before any assertion calls fail (open_other's unmapped client).
  python3 - "$repo" "$TMP_ROOT" "$BASH" <<'PY'
import os, pathlib, re, subprocess, sys
repo, root = map(pathlib.Path, sys.argv[1:3])
bash = sys.argv[3]
source = (repo / "scripts/smoke/rows/bluetooth.sh").read_text()
anchor = '\nbt_was_system=""\n'
assert source.count(anchor) == 1
stubs = r'''
devices_ready() { :; }
devices_system_tree() { printf '%s\n' "$sandbox"; }
device_reply() { :; }
bluez() { :; }
bluez_follow() { [[ $1 != off ]] || cleaned_follow=true; }
plugin_enabled() { echo True; }
bt_powered_sets() { echo 0; }
expect() { :; }
expect_poll() { :; }
bt_popup_native() { readiness_failed=true; return 1; }
bt_count() { : >"$sandbox/dependent"; echo 0; }
device_reply_clear() { cleaned_reply=true; }
check_unexpected_log() { cleaned_log=true; }
'''
source = source.replace(anchor, '\n' + stubs + anchor)
fixture = r'''set -euo pipefail
sandbox="$1" repo="$2"
devices_dir="$sandbox" instance_log="$sandbox/instance.log"
readiness_failed=false
cleaned_follow=false cleaned_reply=false cleaned_log=false
touch "$instance_log" "$sandbox/bt-display-seen" "$sandbox/bt-pin-typed"
source "$repo/scripts/smoke/verdict.sh"
row_class=geometry
source "$sandbox/bluetooth.sh"
[[ $readiness_failed == true && ! -e $sandbox/dependent ]]
[[ $cleaned_follow == true && $cleaned_reply == true && $cleaned_log == true ]]
[[ ! -e $sandbox/bt-display-seen && ! -e $sandbox/bt-pin-typed ]]
printf 'readiness-failed=%s cleanup=complete failures=%s behaviour=%s\n' "$readiness_failed" "$failures" "$behaviour_failures"
smoke_verdict "$failures" "$behaviour_failures" /dev/null
'''
env = {key: os.environ[key] for key in ("PATH", "TMPDIR", "VGSHELL_WORLD_ROOT")}
env.update(LC_ALL="C.UTF-8", VGS_TEST_RUN="1")
def run(name, text):
    folder = root / name
    folder.mkdir()
    (folder / "bluetooth.sh").write_text(text)
    return subprocess.run([bash, "-c", fixture, "_", str(folder), str(repo)],
                          env=env, capture_output=True, text=True, timeout=10)
def check(result):
    assert result.returncode == 1, (result.returncode, result.stdout, result.stderr)
    assert "readiness-failed=true cleanup=complete failures=1 behaviour=1\n" in result.stdout, result.stdout
    assert re.findall(r"status=([0-9]+)", result.stdout) == ["1"], result.stdout
result = run("popup-readiness", source)
check(result)
print("test-qml-smoke: case=popup-readiness row_exit=1 cause_status=1 cleanup=complete failures=1 behaviour=1")
needle = 'row_class=operation fail "bluetooth: native popup proof failed status=$?"'
assert source.count(needle) == 1
mutant = source.replace(needle, ":")
assert mutant != source
control = run("popup-readiness-control", mutant)
assert control.returncode == 0, (control.returncode, control.stdout, control.stderr)
assert "readiness-failed=true cleanup=complete failures=0 behaviour=0\n" in control.stdout, control.stdout
try:
    check(control)
except AssertionError:
    print("test-qml-smoke: case=popup-readiness control_exit=0 cleanup=complete failures=0 behaviour=0 control=rejected")
else:
    raise AssertionError("failed readiness left the row green")
PY
  [[ $selected_case != popup-readiness ]] || end_run
fi
mkdir -- "$TMP_ROOT/tree"
source "$repo/scripts/smoke/tree.sh"
tree_harness_copy "$repo" "$TMP_ROOT/tree" "$repo"
tree="$TMP_ROOT/tree"
# The driver creates the quiet-host hold's lock files in the checkout's
# common git directory.
git -C "$tree" init -q
# The fixture checkout lives below masked /tmp. Declare it read-only at
# each world entry, just as --tree preserves an exported runtime input.
preserve_checkout() {
  python3 - "$tree/scripts/qml-smoke.sh" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
old = 'world_args=(--out "$repo/tmp/display-record")'
assert text.count(old) == 1
changed = text.replace(old, 'world_args=(--input "$repo" --out "$repo/tmp/display-record")')
assert changed != text
path.write_text(changed)
PY
}
preserve_checkout
core=(bar hyprland-consent session start-order auth-sentinel)
for row in "${core[@]}"; do
  printf '# inputs: scripts/smoke/harness.sh\n:\n' >"$tree/scripts/smoke/rows/$row.sh"
done
cat >"$tree/scripts/smoke/rows/provider.sh" <<'ROW'
# inputs: scripts/smoke/harness.sh
provider_private=restored
provider_read() { printf '%s\n' "$provider_private"; }
ok provider-ready
ROW
cat >"$tree/scripts/smoke/rows/fatal-unbound.sh" <<'ROW'
# inputs: scripts/smoke/harness.sh
fail real-before-fatal-one
fail real-before-fatal-two
not_measured "$smoke_row_name" planted-unavailable
(
  failures=0 behaviour_failures=0 not_measured_rows=()
  fail expected-private-failure
  not_measured "$smoke_row_name" expected-private-unavailable
) >"$sandbox/expected-reset.log"
control_output "$sandbox/expected-reset.log"
printf '%s\n' "$qml_smoke_missing_variable"
ROW
cat >"$tree/scripts/smoke/rows/fatal-arithmetic.sh" <<'ROW'
# inputs: scripts/smoke/harness.sh
qml_smoke_bad_number=not_a_number
printf '%s\n' "$((qml_smoke_bad_number + 1))"
ROW
cat >"$tree/scripts/smoke/rows/following.sh" <<'ROW'
# inputs: scripts/smoke/rows/provider.sh
[[ $(provider_read) == restored ]] || fail following-provider-state
ok following-ran
ROW
cat >"$tree/scripts/smoke/rows/dependent.sh" <<'ROW'
# inputs: scripts/smoke/rows/fatal-unbound.sh
fail dependent-must-not-run
ROW
cat >"$tree/scripts/smoke/rows/ordinary.sh" <<'ROW'
# inputs: scripts/smoke/harness.sh
fail planted-assertion-one
fail planted-assertion-two
not_measured ordinary planted-unavailable
false
fail past-failed-command
ROW
printf '%s\n' "${core[@]}" provider ordinary fatal-unbound fatal-arithmetic dependent following >"$tree/scripts/smoke/rows.list"

if [[ $selected_case == completion || $selected_case == all ]]; then
  # These cases run the production driver, namespace, teardown, finalizer
  # and recorder with neutral row bodies. Barriers exist only in copies.
  cp -- "$tree/scripts/smoke/rows/following.sh" "$TMP_ROOT/following.before"
  cat >"$TMP_ROOT/completion-case.py" <<'PY'
import errno, hashlib, json, os, pathlib, re, signal, subprocess, sys, time
repo, tree, scratch = map(pathlib.Path, sys.argv[1:])
def change(text, old, new):
    assert text.count(old) == 1, (old, text.count(old))
    result = text.replace(old, new)
    assert result != text
    return result
barrier = r'''
completion_barrier() {
  local selected where="${2:-${qml_smoke_attempt:-${qml_smoke_driver:-}}}" attempt="${3:-${qml_smoke_attempt:-}}" released
  read -r selected <"${source_repo:-$repo}/completion-phase"
  [[ $selected == "$1" ]] || return 0
  mkfifo "$where/release"
  printf '%s\0' "$1" "$where" "$attempt" >"$where/phase-ready.new"
  mv -- "$where/phase-ready.new" "$where/phase-ready"
  printf 'completion-ready phase=%s path=%s\n' "$1" "$where"
  IFS= read -r released <"$where/release"
}
'''
driver = (tree / 'scripts/qml-smoke.sh').read_text()
driver = change(driver, '  qml_smoke_pending=()\n', barrier + '  qml_smoke_pending=()\n')
driver = change(driver, '    ((qml_smoke_cancel_status != 0 || (qml_smoke_cancel_status=$2)))\n',
                '    ((qml_smoke_cancel_status != 0 || (qml_smoke_cancel_status=$2)))\n'
                '    printf "%s\\n" "$qml_smoke_cancel_status" >>"$qml_smoke_driver/accepted"\n')
for old, phase in [
    ("  while ((${#qml_smoke_pending[@]})); do\n", 'pre-handles'),
    ('    qml_smoke_log_pid=pending\n', 'pending-reader'),
    ('    qml_smoke_log_pid=$!\n', 'early-reader'),
    ('    qml_smoke_attempt_stop=$qml_smoke_cancel_status qml_smoke_phase=between\n', 'before-attempt-seal'),
    ('    qml_smoke_completions+=("$qml_smoke_completion")\n', 'after-attempt-seal'),
    ('      continue\n    fi\n    if [[ $qml_smoke_attempt_status != 0 ]]; then', 'between-attempts'),
    ("  # Final run seal: later stop signals cannot alter this record or exit.\n", 'before-run-seal'),
    ('  if ((qml_smoke_run_stop == 1)); then\n', 'after-run-seal'),
]:
    call = f'  completion_barrier {phase}\n'
    driver = change(driver, old, old + call if phase in ('pending-reader', 'early-reader', 'after-attempt-seal') else call + old)
driver = change(driver, 'exec env --default-signal=INT,QUIT tee "$qml_smoke_attempt/run.log"',
                'env --default-signal=INT,QUIT tee "$qml_smoke_attempt/run.log"; completion_barrier reader-only "$qml_smoke_attempt"')
harness = (repo / 'scripts/smoke/harness.sh').read_text()
functions = []
for name in ('spawn', 'display_record_call', 'display_record_close', 'display_record_finish', 'display_record_arm', 'sink_alive'):
    match = re.search(r'^' + name + r'\(\) \{.*?^}\n', harness, re.M | re.S)
    assert match, name
    functions.append(match.group())
mini = '''set -euo pipefail
source_repo="$repo"
source "$repo/scripts/smoke/verdict.sh"
source "$repo/scripts/smoke/display-record.sh"
pgids=()
source "$repo/scripts/smoke/teardown.sh"
sandbox="$(mktemp -d "$TMPDIR/vgshell-smoke.XXXXXX")"
rt_dir="$(mktemp -d "$XDG_RUNTIME_DIR/owned/vs.XXXXXX")"
home="$sandbox/home"
mkdir -p "$home" "$sandbox/evidence/failed" "$sandbox/rows"
printf '%s\\n' "$rt_dir" >"$sandbox/evidence/runtime"
printf '%s\\n' "$VGSHELL_WORLD_ROOT/runtime/${rt_dir##*/}" >"$sandbox/evidence/runtime-backing"
printf '%s\\n' "$smoke_log_dir" >"$sandbox/evidence/destination"
printf 'qml-smoke: sandbox %s\\n' "$sandbox"
'''+barrier+'\n'.join(functions)+'''
display_record_dir="$(mktemp -d "$source_repo/tmp/display-record/run.XXXXXX")"
printf '%s\\0' "$VGSHELL_WORLD_ROOT" "$sandbox" "$display_record_dir" "$qml_smoke_completion" >"$qml_smoke_attempt/world"
display_record_program >"$display_record_dir/recorder.py"
display_record_arm "$display_record_dir" env -i PATH="$PATH" python3 -u "$display_record_dir/recorder.py" serve "$display_record_dir" "$qml_smoke_completion"
spawn "$sandbox/producer.log" sleep 300
# A stand-in sink: a world process a unit's stop also ends, whose exit the
# teardown reports on its output before the closing reading.
spawn "$sandbox/sink.log" sleep 300
sink_pid="$spawn_pid" sink_exit=""
leak_seq=0
ok() { :; }
compositor_logs_on() { :; }
smoke_row() { source "$repo/scripts/smoke/rows/$1.sh" >"$sandbox/rows/$1.out" 2>&1; }
smoke_finish() { exit "$failures"; }
smoke_judge_reading() { printf '0 0 intact\\n'; }
'''
for old, phase in [
    ('  for group in "${pgids[@]}"; do\n', 'producer-joins'),
    ('  if ! display_record_call stop "$reason" >/dev/null; then\n', 'recorder-stop'),
    ('  python3 "$display_record_dir/recorder.py" retain "$display_record_dir" "$sandbox" "$rt_dir" "$home" || finalizer_errors=1\n', 'recorder-retain'),
]:
    mini = change(mini, old, f'  completion_barrier {phase}\n' + old)
teardown = (repo / 'scripts/smoke/teardown.sh').read_text()
teardown = change(teardown, "  trap '' TERM INT HUP\n", "  trap '' TERM INT HUP\n  completion_barrier producer-close\n")
fence = (repo / 'scripts/smoke/gpu-fence.sh').read_text()
fence = change(fence, '# inside ABSENT... -- PRESENT... -- CMD...', barrier + '\n# inside ABSENT... -- PRESENT... -- CMD...')
fence = change(fence, '  for path in "$fence_dir"/tmp/vgshell-smoke.*/evidence/destination; do\n',
               '  repo="$checkout"; completion_barrier namespace-release "${outputs[-1]}" "${outputs[-1]}"\n'
               '  for path in "$fence_dir"/tmp/vgshell-smoke.*/evidence/destination; do\n')
recorder = (repo / 'scripts/smoke/display-record.sh').read_text()
needle = '            self.emit("recorder", "terminal", dict(localRecord='
recorder = change(recorder, needle, '''            phase_file = pathlib.Path(__file__).parents[3] / "completion-phase"
            if phase_file.read_text().strip() == "recorder-terminal":
                where = pathlib.Path(self.outcome_authority).parent
                os.mkfifo(where / "release")
                (where / "phase-ready.new").write_bytes(b"recorder-terminal\\0" + os.fsencode(where) + b"\\0" + os.fsencode(where) + b"\\0")
                os.replace(where / "phase-ready.new", where / "phase-ready")
                print("completion-ready phase=recorder-terminal path=" + str(where), flush=True)
                with (where / "release").open() as release:
                    release.readline()
'''+needle)
core = ['bar', 'hyprland-consent', 'session', 'start-order', 'auth-sentinel']
for name in core + ['following']:
    (tree / f'scripts/smoke/rows/{name}.sh').write_text('# inputs: scripts/smoke/harness.sh\n:\n')
(tree / 'scripts/smoke/rows/fatal.sh').write_text('# inputs: scripts/smoke/harness.sh\nprintf "%s\\n" "$completion_missing"\n')
(tree / 'scripts/smoke/harness.sh').write_text(mini)
(tree / 'scripts/smoke/teardown.sh').write_text(teardown)
(tree / 'scripts/smoke/gpu-fence.sh').write_text(fence)
(tree / 'scripts/smoke/display-record.sh').write_text(recorder)
# phase, stop applies to attempt, number of worlds, native run status
cases = [
    ('pre-handles', False, 0, 0), ('pending-reader', False, 0, 0), ('early-reader', False, 0, 0),
    ('producer-close', True, 1, 0), ('producer-joins', True, 1, 0),
    ('recorder-stop', True, 1, 0), ('recorder-terminal', True, 1, 0),
    ('recorder-retain', True, 1, 0), ('namespace-release', True, 1, 0),
    ('reader-only', True, 1, 0), ('before-attempt-seal', True, 1, 0),
    ('after-attempt-seal', False, 1, 0), ('between-attempts', False, 1, 1),
    ('before-run-seal', False, 1, 0), ('after-run-seal', False, 1, 0),
    ('input-failed', False, 1, 1), ('publication-failed', False, 1, 1),
    ('run-publication-failed', False, 1, 1),
    ('stale-snapshot', True, 1, 0),
]
for phase, attempt_stop, worlds, native in cases:
    output = scratch / ('completion-' + phase)
    output.mkdir()
    selected = 'before-attempt-seal' if phase == 'stale-snapshot' else phase
    (tree / 'completion-phase').write_text(selected + '\n')
    names = core + (['fatal', 'following'] if phase == 'between-attempts' else ['following'])
    (tree / 'scripts/smoke/rows.list').write_text('\n'.join(names) + '\n')
    source = driver
    if phase == 'input-failed':
        source = change(source, '    if ! qml_smoke_prepare_completion attempt ',
                        '    rm -- "$qml_smoke_attempt/world"\n    if ! qml_smoke_prepare_completion attempt ')
    if phase == 'publication-failed':
        source = change(source, '    if ! mv -- "$qml_smoke_attempt/.completion-$qml_smoke_attempt_stop" "$qml_smoke_completion"; then',
                        '    if ! mv -- "$qml_smoke_attempt/.completion-$qml_smoke_attempt_stop" "$qml_smoke_completion/missing"; then')
    if phase == 'run-publication-failed':
        source = change(source, '  if ! mv -- "$qml_smoke_driver/.completion-$qml_smoke_run_stop" "$qml_smoke_driver/completion.json"; then',
                        '  if ! mv -- "$qml_smoke_driver/.completion-$qml_smoke_run_stop" "$qml_smoke_driver/completion.json/missing"; then')
    if phase == 'stale-snapshot':
        source = change(source, '  completion_barrier before-attempt-seal\n',
                        '  qml_smoke_pre_stop_status=$qml_smoke_cancel_status\n  completion_barrier before-attempt-seal\n')
        source = change(source, 'qml_smoke_attempt_stop=$qml_smoke_cancel_status qml_smoke_phase=between',
                        'qml_smoke_attempt_stop=$qml_smoke_pre_stop_status qml_smoke_phase=between')
    (tree / 'scripts/qml-smoke.sh').write_text(source)
    log_path = output / 'log'
    expected = 1 if phase.endswith('-failed') else 0 if phase == 'after-run-seal' else 143
    with log_path.open('wb') as stream:
        child = subprocess.Popen(['env', '--default-signal=INT,QUIT', str(tree / 'scripts/qml-smoke.sh'), '--log-dir', str(output / 'evidence')], stdout=stream, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 60
            ready = None
            if not phase.endswith('-failed'):
                while child.poll() is None and time.monotonic() < deadline:
                    text = log_path.read_text()
                    run_path = re.search(r'^qml-smoke: completion=(\S+)$', text, re.M)
                    if run_path:
                        directory = pathlib.Path(run_path[1]).parent
                        announced = re.findall(r'^qml-smoke: attempt=(\S+) targets=', text, re.M)
                        current_attempt = pathlib.Path(announced[-1]) if announced else directory
                        channel = current_attempt / 'phase-ready'
                        if channel.exists():
                            fields = channel.read_bytes().split(b'\0')
                            expected_attempt = announced[-1] if announced else ''
                            expected_ready = [os.fsencode(selected), os.fsencode(current_attempt), os.fsencode(expected_attempt), b'']
                            assert fields == expected_ready, ('readiness-binding', fields, expected_ready)
                            ready = dict(phase=selected, path=str(current_attempt), attempt=expected_attempt or None)
                            break
                    time.sleep(0.01)
                assert ready and ready['phase'] == selected, ('barrier-not-ready', phase)
                directory = pathlib.Path(re.search(r'^qml-smoke: completion=(\S+)$', text, re.M)[1]).parent
                closed = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in directory.glob('*/completion.json')}
                if phase == 'after-run-seal':
                    closed[directory / 'completion.json'] = hashlib.sha256((directory / 'completion.json').read_bytes()).hexdigest()
                os.kill(child.pid, signal.SIGTERM)
                if phase != 'after-run-seal':
                    accepted = directory / 'accepted'
                    # The driver's >> creates the file before printf writes
                    # its line, so wait for a whole line, not the file.
                    while not (accepted.exists() and accepted.read_text().endswith('\n')) and child.poll() is None and time.monotonic() < deadline:
                        time.sleep(0.01)
                    assert accepted.read_text().splitlines() == ['143'], 'first-stop-not-acknowledged'
                    # A different repeated signal cannot replace the first.
                    os.kill(child.pid, signal.SIGHUP)
                    while accepted.read_text().count('\n') < 2 and child.poll() is None and time.monotonic() < deadline:
                        time.sleep(0.01)
                    assert accepted.read_text().splitlines() == ['143', '143'], 'mixed-stop-replaced-first'
                with (pathlib.Path(ready['path']) / 'release').open('w') as release:
                    release.write('release\n')
            child.wait(timeout=30)
            text = log_path.read_text()
            assert child.returncode == expected, ('public-exit', child.returncode, expected)
            directory = pathlib.Path(re.search(r'^qml-smoke: completion=(\S+)$', text, re.M)[1]).parent
            if phase == 'run-publication-failed':
                assert not (directory / 'completion.json').exists(), 'failed-run-publication-was-usable'
                assert len(list(directory.glob('*/completion.json'))) == 1, 'sealed-world-lost'
                print(json.dumps(dict(case=phase, exit=child.returncode, expected=expected, result='pass')), flush=True)
                for line in text.splitlines():
                    print('  CONTROL  ' + line)
                continue
            run = json.loads((directory / 'completion.json').read_text())
            assert run['exit'] == expected, ('run-exit', run)
            attempts = [json.loads(pathlib.Path(p).read_text()) for p in run['attempts']]
            assert len(re.findall(r'^qml-smoke: sandbox ', text, re.M)) == worlds, 'world-count'
            if not phase.endswith('-failed'):
                assert len(attempts) == worlds, 'attempt-count'
                for path, digest in closed.items():
                    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, 'sealed-record-changed'
                if attempts:
                    current = attempts[-1]
                    wanted = 143 if attempt_stop else native
                    correct = current['exit'] == wanted and current['reason'] == ('interrupted:143' if attempt_stop else 'failed' if native else 'passed')
                    if phase == 'stale-snapshot':
                        assert not correct and current['exit'] == 0, 'control-did-not-reject-stale-normal'
                    else:
                        assert correct, ('attempt-exit', current, wanted)
                    assert current['joins'] == dict(fence=True, reader=True), 'joins'
                    assert not pathlib.Path(current['world']['root']).exists(), 'world-left-after-return'
                    record = pathlib.Path(current['world']['recorder'])
                    terminal = [json.loads(line) for line in (record / 'events.jsonl').read_text().splitlines() if json.loads(line)['kind'] == 'terminal']
                    assert terminal[0]['data']['productResult']['authority'] == current['authority'], 'recorder-authority'
            else:
                assert not list(directory.glob('*/completion.json')), 'failed-required-record-published'
            print(json.dumps(dict(case=phase, exit=child.returncode, expected=expected, completion=str(directory / 'completion.json'), readiness=ready, result='pass')), flush=True)
        except BaseException:
            print(log_path.read_text(), file=sys.stderr)
            raise
        finally:
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
    for line in log_path.read_text().splitlines():
        print('  CONTROL  ' + line)
# A unit's stop: TERM to the driver and every process under it at once, as
# systemd stops a unit (systemd.kill(5), KillMode=control-group), the way
# dev-validate-run's unit ends a run at its bound. The attempt waits inside
# a row whose output runs through a filter the stop also ends, as
# harness.sh's smoke_row does; the row has lost its sink, as the stop ends
# it, so the teardown writes the sink's exit to that dead filter before its
# closing reading. The teardown must still take the reading. Each control
# restores one half of the old stop order, bubblewrap's monitor dying of
# the TERM or the teardown dying of its write, and must lose the reading.
# The held case forces the order a busy host can give that stop: the world
# shell has entered its teardown on the unit's TERM, short of the point
# where the old teardown ignored stops, before the fence's copy of the stop
# reaches it. The world's copy of the teardown reports teardown-entered and
# waits; the fence's copy of its forward reports forward-held and waits,
# then reports forwarded once its kill has returned. Each opens its release
# fifo read-write before it reports, so the fifo has a reader from the
# report on, and one with none is one whose holder has ended. The teardown
# must take the reading and the recorder write its teardown record; its
# control, the teardown with no trap for the stops, must lose both.
stop_harness = change(mini, 'smoke_row() { source "$repo/scripts/smoke/rows/$1.sh" >"$sandbox/rows/$1.out" 2>&1; }',
                      'smoke_row() { source "$repo/scripts/smoke/rows/$1.sh" > >(exec cat >"$sandbox/rows/$1.out") 2>&1; }')
def tree_of(pid):
    found, queue = [], [pid]
    while queue:
        current = queue.pop()
        found.append(current)
        for task in pathlib.Path(f'/proc/{current}/task').glob('*'):
            try:
                queue += [int(word) for word in (task / 'children').read_text().split()]
            except OSError:
                pass
    return found
def hold(fifo, report):
    return (f'mkfifo "{fifo}"; exec {{held_fd}}<>"{fifo}"; : >"{report}"; '
            'IFS= read -r -u "$held_fd" _; exec {held_fd}<&-\n')
def release(fifo):
    # True once the release is in the fifo of a live holder, False when
    # the holder has ended.
    try:
        descriptor = os.open(fifo, os.O_WRONLY | os.O_NONBLOCK)
    except OSError as error:
        assert error.errno == errno.ENXIO, (fifo.name, error)
        return False
    try:
        os.write(descriptor, b'release\n')
    except BrokenPipeError:
        return False
    finally:
        os.close(descriptor)
    return True
forward_kill = '    [[ -z $child ]] || stop_session "$1" "$child"\n'
held_fence = change(fence, forward_kill,
                    '    ' + hold('${outputs[-1]}/forward-release', '${outputs[-1]}/forward-held')
                    + forward_kill + '    : >"${outputs[-1]}/forwarded"\n')
teardown_ignore = "  trap '' TERM INT HUP\n  completion_barrier producer-close\n"
held_teardown = change(teardown, teardown_ignore,
                       '  ' + hold('$qml_smoke_attempt/teardown-release', '$qml_smoke_attempt/teardown-entered')
                       + teardown_ignore)
stop_traps = ''.join(f"trap 'trap \"\" TERM INT HUP; trap - EXIT; cleanup {status}; exit {status}' {name}\n" for name, status in (('TERM', 143), ('INT', 130), ('HUP', 129)))
def unit_stop(label, fence_source, teardown_source, want_close, held=False):
    output = scratch / ('unit-stop-' + label)
    output.mkdir()
    (tree / 'completion-phase').write_text('mid-row\n')
    (tree / 'scripts/smoke/rows/stop-here.sh').write_text('# inputs: scripts/smoke/harness.sh\nkill "$sink_pid"\nwait "$sink_pid" || :\ncompletion_barrier mid-row\n')
    (tree / 'scripts/smoke/rows.list').write_text('\n'.join(core + ['stop-here']) + '\n')
    (tree / 'scripts/qml-smoke.sh').write_text(driver)
    (tree / 'scripts/smoke/harness.sh').write_text(stop_harness)
    (tree / 'scripts/smoke/gpu-fence.sh').write_text(fence_source)
    (tree / 'scripts/smoke/teardown.sh').write_text(teardown_source)
    log_path = output / 'log'
    with log_path.open('wb') as stream:
        child = subprocess.Popen(['env', '--default-signal=INT,QUIT', str(tree / 'scripts/qml-smoke.sh'), '--log-dir', str(output / 'evidence')], stdout=stream, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 60
            attempt = None
            while child.poll() is None and time.monotonic() < deadline:
                announced = re.findall(r'^qml-smoke: attempt=(\S+) targets=', log_path.read_text(), re.M)
                if announced and (pathlib.Path(announced[-1]) / 'phase-ready').exists():
                    attempt = pathlib.Path(announced[-1])
                    break
                time.sleep(0.01)
            assert attempt, ('mid-row-not-ready', label)
            for pid in tree_of(child.pid):
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
            if held:
                entered, holding = attempt / 'teardown-entered', attempt / 'forward-held'
                while not (entered.exists() and holding.exists()) and child.poll() is None and time.monotonic() < deadline:
                    time.sleep(0.01)
                assert entered.exists() and holding.exists(), ('stop-not-held', label, entered.exists(), holding.exists())
                assert release(attempt / 'forward-release'), ('fence-ended-held', label)
                forwarded = attempt / 'forwarded'
                while not forwarded.exists() and child.poll() is None and time.monotonic() < deadline:
                    time.sleep(0.01)
                assert forwarded.exists(), ('copy-not-forwarded', label)
                # The fence wrote forwarded after its kill returned, so the
                # copy is pending on the world shell or already handled. The
                # kernel runs a pending handler on the shell's next return to
                # user mode, before its next command, so this release cannot
                # let a teardown that has not yet ignored the stops reach its
                # ignore first. A shell the copy ended has no reader.
                release(attempt / 'teardown-release')
            child.wait(timeout=30)
            readings = (attempt / 'judge-readings').read_text().splitlines()
            assert readings[:len(core) * 2] == [f'{row} {edge} 0 0 intact' for row in core for edge in ('start', 'end')], readings
            assert readings[len(core) * 2] == 'stop-here start 0 0 intact', readings
            closed = readings[len(core) * 2 + 1:] == ['- close 0 0 intact']
            assert closed == want_close, ('closing-reading', label, readings)
            if held:
                world = (attempt / 'world').read_bytes().split(b'\0')
                record = pathlib.Path(os.fsdecode(world[2])) / 'teardown'
                if want_close:
                    fields = dict(line.split('=', 1) for line in record.read_text().splitlines())
                    assert fields['world_exit'] == '143' and fields['completion'] == str(attempt / 'completion.json'), ('teardown-record', fields)
                else:
                    assert not record.exists(), ('control-kept-teardown-record', label)
            if label == 'shipped':
                # The stop also ended the attempt's log reader. The driver
                # traps the stop and writes its summary to this log, not
                # through that reader: the rows the attempt ended keep their
                # results, and only the open row stop-here, with no record,
                # is unreached and counted.
                text = log_path.read_text()
                assert re.search(r'^qml-smoke: failed-operation=run-log ', text, re.M), 'log-reader-survived-stop'
                results = dict(re.findall(r'^qml-smoke: row-result row=(\S+) status=(\S+.*)$', text, re.M))
                assert all(results.get(row, 'unreached') != 'unreached' for row in core), ('ended-row-unreached', results)
                assert results.get('stop-here') == 'unreached', ('open-row', results)
                assert re.search(r'^qml-smoke: failed=1$', text, re.M), 'failed-count'
        except BaseException:
            print(log_path.read_text(), file=sys.stderr)
            raise
        finally:
            if child.poll() is None:
                for pid in tree_of(child.pid):
                    try:
                        os.kill(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                child.wait()
    print(json.dumps(dict(case='unit-stop-' + label, closed=closed, result='pass')), flush=True)
unit_stop('shipped', fence, teardown, True)
unit_stop('control-monitor-dies', change(fence, 'fence=(env --ignore-signal=TERM,INT,HUP bwrap', 'fence=(bwrap'), teardown, False)
unit_stop('control-teardown-write-ends-it', fence, change(teardown, "  trap '' PIPE\n  set +e\n", ''), False)
unit_stop('held', held_fence, held_teardown, True, held=True)
unit_stop('control-held-repeat-ends-it', held_fence, change(held_teardown, stop_traps, ''), False, held=True)
(tree / 'scripts/smoke/rows/stop-here.sh').unlink()
PY
  timeout -k 2 1500 unshare --user --map-current-user --pid --fork --kill-child --mount-proc \
    python3 "$TMP_ROOT/completion-case.py" "$repo" "$tree" "$TMP_ROOT"
  [[ $selected_case != completion ]] || exit 0
  cp -- "$repo/scripts/qml-smoke.sh" "$tree/scripts/qml-smoke.sh"
  cp -- "$repo/scripts/smoke/harness.sh" "$tree/scripts/smoke/harness.sh"
  cp -- "$repo/scripts/smoke/teardown.sh" "$tree/scripts/smoke/teardown.sh"
  cp -- "$repo/scripts/smoke/gpu-fence.sh" "$tree/scripts/smoke/gpu-fence.sh"
  cp -- "$repo/scripts/smoke/display-record.sh" "$tree/scripts/smoke/display-record.sh"
  cp -- "$TMP_ROOT/following.before" "$tree/scripts/smoke/rows/following.sh"
  preserve_checkout
  printf '%s\n' "${core[@]}" provider ordinary fatal-unbound fatal-arithmetic dependent following >"$tree/scripts/smoke/rows.list"
fi

if [[ $selected_case == all || $selected_case == hold ]]; then
  # The rows append to one events file in the log directory both worlds
  # share, so its line order is the order of their steps. Each wait polls
  # that file for the line it waits on.
  hold_reader='hold_events="$smoke_log_dir/hold-events"
hold_seen() { [[ -f $hold_events ]] && grep -qxF -- "$1" "$hold_events"; }'
  cat >"$tree/scripts/smoke/rows/hold-forever.sh" <<'ROW'
# inputs: scripts/smoke/harness.sh
hold_forever() { printf 'K held\n' >>"$smoke_log_dir/hold-events"; sleep 300; }
smoke_hold hold-forever window hold_forever
ROW
  # The window starts while the other world is in tick-1, and looks for
  # tick-2 starting while it holds.
  cat >"$tree/scripts/smoke/rows/hold-window.sh" <<ROW
# inputs: scripts/smoke/harness.sh
$hold_reader
for _ in \$(seq 1 1200); do hold_seen 'B start 1' && break; sleep 0.1; done
printf 'A requested\n' >>"\$hold_events"
hold_window() {
  printf 'A held\n' >>"\$hold_events"
  for _ in \$(seq 1 20); do hold_seen 'B start 2' && break; sleep 0.1; done
  printf 'A release\n' >>"\$hold_events"
}
smoke_hold hold-window window hold_window
ROW
  # tick-1 stays open until the hold is requested, then looks for the
  # window starting before the row ends.
  cat >"$tree/scripts/smoke/rows/tick-1.sh" <<ROW
# inputs: scripts/smoke/harness.sh
$hold_reader
printf 'B start 1\n' >>"\$hold_events"
for _ in \$(seq 1 1200); do hold_seen 'A requested' && break; sleep 0.1; done
for _ in \$(seq 1 30); do hold_seen 'A held' && break; sleep 0.1; done
printf 'B end 1\n' >>"\$hold_events"
ROW
  for tick in 2 3 4; do
    printf '# inputs: scripts/smoke/harness.sh\nprintf '\''B start %s\\nB end %s\\n'\'' >>"$smoke_log_dir/hold-events"\n' "$tick" "$tick" >"$tree/scripts/smoke/rows/tick-$tick.sh"
  done
  printf '%s\n' "${core[@]}" hold-forever hold-window tick-1 tick-2 tick-3 tick-4 >"$tree/scripts/smoke/rows.list"
  cat >"$TMP_ROOT/hold-case.py" <<'PY'
import json, pathlib, re, signal, subprocess, sys, time
tree, output, mode = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
output.mkdir()
def start(name, rows, logs):
    log = output / (name + '.log')
    with log.open('wb') as stream:
        child = subprocess.Popen(['env', '--default-signal=INT,QUIT', str(tree / 'scripts/qml-smoke.sh'), '--rows', rows, '--log-dir', str(logs)],
                                 stdout=stream, stderr=subprocess.STDOUT)
    return child, log
def finish(child, log, bound):
    try:
        child.wait(timeout=bound)
    except subprocess.TimeoutExpired:
        print(log.read_text(errors='replace'), file=sys.stderr)
        raise AssertionError(('run-did-not-end', log.name, bound))
def events(logs):
    path = logs / 'hold-events'
    return path.read_text().splitlines() if path.exists() else []
if mode == 'shipped':
    # A world killed while it holds the hold: the driver's USR2 kills the
    # world's namespace init, as its no-progress stop does.
    logs = output / 'killed'
    child, log = start('killed', 'hold-forever', logs)
    deadline = time.monotonic() + 300
    while events(logs) != ['K held'] and child.poll() is None and time.monotonic() < deadline:
        time.sleep(0.1)
    assert events(logs) == ['K held'], ('killed-run-not-holding', events(logs), log.read_text(errors='replace'))
    child.send_signal(signal.SIGUSR2)
    finish(child, log, 60)
    assert re.search(r'^qml-smoke: no-progress stop=unanswered world=ended ', log.read_text(errors='replace'), re.M), log.read_text(errors='replace')
logs = output / 'pair'
window = start('window', 'hold-window', logs)
ticks = start('ticks', 'tick-1,tick-2,tick-3,tick-4', logs)
finish(*window, 600)
finish(*ticks, 600)
for child, log in (window, ticks):
    assert child.returncode == 0, (log.name, child.returncode, log.read_text(errors='replace'))
text = window[1].read_text(errors='replace')
assert re.search(r'^  smoke_hold row=hold-window window=window hold=held wait_ms=[0-9]+ held_ms=[0-9]+$', text, re.M), text
# The window waits for tick-1 to end; tick-2 reaches its start while the
# hold is waited for and starts only after the window ends.
want = ['B start 1', 'A requested', 'B end 1', 'A held', 'A release'] + [f'B {edge} {n}' for n in (2, 3, 4) for edge in ('start', 'end')]
got = events(logs)
if mode == 'shipped':
    assert got == want, ('order', got)
    print(json.dumps(dict(case='hold', events=got, result='pass')), flush=True)
else:
    assert got != want, ('control-window-did-not-overlap', got)
    print(json.dumps(dict(case='hold-control-shared', events=got, result='rejected')), flush=True)
PY
  timeout -k 2 1500 unshare --user --map-current-user --pid --fork --kill-child --mount-proc \
    python3 "$TMP_ROOT/hold-case.py" "$tree" "$TMP_ROOT/hold-shipped" shipped
  python3 - "$tree/scripts/smoke/harness.sh" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
old = '    if smoke_lock_take -x hold; then\n'
assert text.count(old) == 1
changed = text.replace(old, '    if smoke_lock_take -s hold; then\n')
assert changed != text
path.write_text(changed)
PY
  timeout -k 2 1500 unshare --user --map-current-user --pid --fork --kill-child --mount-proc \
    python3 "$TMP_ROOT/hold-case.py" "$tree" "$TMP_ROOT/hold-control" control
  cp -- "$repo/scripts/smoke/harness.sh" "$tree/scripts/smoke/harness.sh"
  printf '%s\n' "${core[@]}" provider ordinary fatal-unbound fatal-arithmetic dependent following >"$tree/scripts/smoke/rows.list"
fi
[[ $selected_case != hold ]] || end_run

run_case() {
  local label="$1" destination="${2:-$TMP_ROOT/$1}" completed="${3-}" status=0
  [[ $selected_case == all || $selected_case == "$label" ||
    ( $selected_case == unmeasured && ( $label == pre-world || $label == stopped-unmeasured ) ) ]] || return 0
  mkdir -- "$TMP_ROOT/$label"
  "$tree/scripts/qml-smoke.sh" --log-dir "$destination" >"$TMP_ROOT/$label/log" 2>&1 || status=$?
  python3 - "$TMP_ROOT/$label" "$status" "$label" "$completed" <<'PY'
from pathlib import Path
import json, re, sys
root, status, label = Path(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
log = (root / 'log').read_text()
def report_error(kind, value, traceback):
    print(log, file=sys.stderr)
    sys.__excepthook__(kind, value, traceback)
sys.excepthook = report_error
results = re.findall(r'^qml-smoke: row-result row=(\S+) status=(\S+)(.*)$', log, re.M)
by_row = {name: (state, detail) for name, state, detail in results}
attempts = [Path(path) / 'run.log' for path in re.findall(r'^qml-smoke: attempt=(.*?) targets=', log, re.M)]
assert status == {'good': 0, 'not-measured': 77, 'pre-world': 77, 'stopped-unmeasured': 77}.get(label, 1), (status, log)
assert len(results) == len(by_row), results
targets = (root.parent / 'tree/scripts/smoke/rows.list').read_text().splitlines()
assert set(by_row) == set(targets), (by_row, targets)
unreached = ('unreached', '')
if label in ('pre-world', 'stopped-unmeasured'):
    completed = sys.argv[4].split()
    assert set(completed) <= set(targets), (completed, targets)
    remaining = [name for name in targets if name not in completed]
    for name in completed:
        assert by_row[name] == ('ok', ''), by_row
    for name in remaining:
        assert by_row[name] == unreached, by_row
    expected = 'qml-smoke: status=not-measured rows=' + ','.join(name + ':unreached' for name in remaining)
    assert re.findall(r'^qml-smoke: status=not-measured rows=.*$', log, re.M) == [expected], log
    assert not re.search(r'^qml-smoke: failed=', log, re.M), log
    assert len(attempts) == 1, log
elif label == 'resume':
    for name in ('fatal-unbound', 'fatal-arithmetic'):
        assert by_row[name][0] == 'failed', by_row
    source = (root.parent / 'tree/scripts/smoke/rows/fatal-unbound.sh').read_text().splitlines()
    fatal_lines = [number for number, line in enumerate(source, 1) if '"$qml_smoke_missing_variable"' in line]
    assert len(fatal_lines) == 1, fatal_lines
    assert re.search(rf'/fatal-unbound.sh: line {fatal_lines[0]}: qml_smoke_missing_variable: unbound variable', log), log
    assert re.search(r'/fatal-arithmetic.sh: line 3: not_a_number: unbound variable', log), log
    assert by_row['dependent'] == ('blocked', ' producer=fatal-unbound'), by_row
    assert by_row['following'][0] == 'ok', by_row
    assert by_row['provider'][0] == 'ok', by_row
    assert by_row['ordinary'][0] == 'failed', by_row
    assert 'past-failed-command' not in log, log
    # Real assertions before the fatal survive; the nested reset's expected
    # failure and unavailable note never overwrite the containing outcome.
    assert re.search(r'^qml-smoke: failed=8$', log, re.M), log
    assert len(attempts) == 3, attempts
    partial = (attempts[0].parent / 'partial/fatal-unbound').read_bytes().split(b'\0')
    assert partial == [b'2', b'fatal-unbound:planted-unavailable', b''], partial
    for attempt in attempts:
        text = attempt.read_text()
        completion = json.loads((attempt.parent / 'completion.json').read_text())
        assert completion['exit'] in (0, 1) and completion['recorderExit'] == 0, completion
        assert completion['joins'] == {'fence': True, 'reader': True}, completion
    assert '  ok    following-ran' in attempts[-1].read_text(), log
elif label == 'no-resume':
    # The mutant ends the loop before the blocking pass: dependent has no
    # result, so it is unreached rather than blocked.
    for name in ('following', 'dependent', 'fatal-arithmetic'):
        assert by_row[name] == unreached, by_row
    # fatal-unbound's fatal 1 and partial record 2, ordinary 3, unreached 3.
    assert re.search(r'^qml-smoke: failed=9$', log, re.M), log
    assert '  ok    following-ran' not in log, log
    assert len(attempts) == 1, log
elif label == 'fatal-core':
    assert by_row['bar'][0] == 'failed', by_row
    assert by_row['following'] == ('blocked', ' producer=bar'), by_row
    assert all(state == 'blocked' for name, (state, _) in by_row.items() if name != 'bar'), by_row
    assert len(attempts) == 1, log
elif label in ('good', 'not-measured'):
    assert by_row['following'][0] == 'ok', by_row
    assert by_row['note'][0] == ('ok' if label == 'good' else 'not-measured'), by_row
    assert len(attempts) == 1, log
    if label == 'not-measured':
        assert re.search(r'^qml-smoke: status=not-measured rows=note:planted-unavailable$', log, re.M), log
    else:
        completion = json.loads((attempts[0].parent.parent / 'completion.json').read_text())
        assert completion['exit'] == 0 and completion['attempts'] == [str(attempts[0].parent / 'completion.json')], completion
elif label == 'early-zero':
    for name in ('early-zero', 'following'):
        assert by_row[name] == ('failed', ' cause=incomplete-attempt'), by_row
    assert '  ok    following-ran' not in log, log
    assert len(attempts) == 1, log
elif label == 'stopped':
    # An attempt that exits 1 with no fatal Bash error leaves its open row,
    # which wrote no record, and every later row with no result.
    for name in ('stopped', 'following', 'ordinary'):
        assert by_row[name] == unreached, by_row
    assert by_row['provider'][0] == 'ok', by_row
    assert '  ok    following-ran' not in log, log
    assert re.search(r'^qml-smoke: failed=3$', log, re.M), log
    assert len(attempts) == 1, log
elif label == 'no-progress':
    # The killed world leaves its attempt unsealed, so the driver reads no
    # row record from it: every row but the hung one is unreached.
    assert by_row['hang'] == ('failed', ' cause=no-progress'), by_row
    assert all(value == unreached for name, value in by_row.items() if name != 'hang'), by_row
    assert len(attempts) == 1, log
    ended = re.findall(r'^qml-smoke: no-progress stop=unanswered world=ended after-secs=15 root=(\S+) evidence=(\S+)$', log, re.M)
    assert len(ended) == 1 and 'fence=killed' not in log, log
    evidence = Path(ended[0][1])
    assert evidence.parent.parent == root and evidence.name == 'hang' and (evidence / 'row/hang.out').is_file(), (ended, log)
    assert not Path(ended[0][0]).exists(), ended
    assert re.search(r'^qml-smoke: no-progress row=hang idle-secs=[0-9]+ bound-secs=15 note=', log, re.M), log
    stopped = attempts[0].parent / 'no-progress'
    record = attempts[0].parent.parent / 'completion.json'
    assert not (attempts[0].parent / 'completion.json').exists(), log
    completion = json.loads(record.read_text())
    assert completion['exit'] == 1 and completion['reason'] == 'no-progress' and completion['requestedStop'] == 1, completion
    assert completion['noProgress']['row'] == 'hang' and completion['noProgress']['boundSecs'] == 15, completion
    assert record.stat().st_mtime - stopped.stat().st_mtime <= 2 * 15, (record.stat().st_mtime, stopped.stat().st_mtime)
elif label == 'finish-operation':
    assert all(state == 'ok' for state, _ in by_row.values()), by_row
    assert re.search(r'^qml-smoke: failed=1$', log, re.M), log
    assert len(attempts) == 1, log
    assert (attempts[0].parent / 'outside-failures').read_bytes() == b'1\0', log
elif label == 'output-refused':
    # No world started, so no row has a result.
    assert all(value == unreached for value in by_row.values()), by_row
    assert re.search(rf'^qml-smoke: failed={len(targets)}$', log, re.M), log
    assert re.search(r'^gpu-fence: refused: output=.* protected=', log, re.M), log
    assert len(attempts) == 1, log
else:
    raise AssertionError(label)
print('  ok    ' + label)
PY
}
run_case resume
if [[ $selected_case == all || $selected_case == cancellation || $selected_case == producer || $selected_case == late-exit ]]; then
  cat >"$tree/scripts/smoke/rows/cancel-fatal.sh" <<'ROW'
# inputs: scripts/smoke/harness.sh
printf '%s\n' "$qml_smoke_cancel_missing"
ROW
  cat >"$tree/scripts/smoke/rows/cancel-wait.sh" <<'ROW'
# inputs: scripts/smoke/harness.sh
printf 'cancel-ready root=%s sandbox=%s attempt=%s record=%s\n' "$VGSHELL_WORLD_ROOT" "$sandbox" "$qml_smoke_attempt" "$display_record_dir"
sleep 300 &
wait $!
ROW
  cat >"$tree/scripts/smoke/rows/cancel-forbidden.sh" <<'ROW'
# inputs: scripts/smoke/harness.sh
fail cancel-forbidden-ran
ROW
  if [[ $selected_case == late-exit ]]; then
    printf '# inputs: scripts/smoke/harness.sh\n:\n' >"$tree/scripts/smoke/rows/cancel-wait.sh"
    python3 - "$tree" <<'PY'
from pathlib import Path
import sys
tree = Path(sys.argv[1])
path = tree / 'scripts/smoke/teardown.sh'
text = path.read_text()
old = "  trap '' TERM INT HUP\n"
assert text.count(old) == 1
barrier = '''  if [[ $original_status == 0 ]]; then
  mkfifo "$qml_smoke_attempt/release"
  printf 'cancel-ready root=%s sandbox=%s attempt=%s record=%s\\n' "$VGSHELL_WORLD_ROOT" "$sandbox" "$qml_smoke_attempt" "$display_record_dir"
  IFS= read -r released <"$qml_smoke_attempt/release"
  fi
'''
path.write_text(text.replace(old, old + barrier))
path = tree / 'scripts/qml-smoke.sh'
text = path.read_text()
old = '    ((qml_smoke_cancel_status != 0 || (qml_smoke_cancel_status=$2)))\n'
assert text.count(old) == 1
path.write_text(text.replace(old, old + '    printf "%s\\n" "$qml_smoke_cancel_status" >"$qml_smoke_driver/accepted"\n'))
PY
  fi
  cat >"$TMP_ROOT/cancel-case.py" <<'PY'
import json, os, pathlib, re, signal, subprocess, sys, time
def real_producers(argv):
    return bool(re.search(r'(?:^|[ /])qs .*-p ', argv, re.M) and 'Hyprland --config' in argv and argv.count('dbus-daemon --nofork') == 2)
if sys.argv[1:] == ['--test-producers']:
    bare = 'qs -p /owned/shell\nHyprland --config /owned/hyprland.lua\ndbus-daemon --nofork --config-file=/owned/session.xml\ndbus-daemon --nofork --config-file=/owned/system.xml'
    assert real_producers(bare)
    print('  ok    producers-bare-argv')
    sys.exit(0)
tree, output = map(pathlib.Path, sys.argv[1:3])
kind, phase, stop_phase, ready_bound = sys.argv[3:]
expected = {'INT': 130, 'TERM': 143, 'HUP': 129}[kind]
log_path = output / 'log'
def processes(text):
    found = []
    for path in pathlib.Path('/proc').iterdir():
        if not path.name.isdecimal() or int(path.name) == os.getpid():
            continue
        try:
            argv = (path / 'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
        except OSError:
            continue
        if text in argv:
            found.append((int(path.name), argv))
    return found
with log_path.open('wb') as stream:
    child = subprocess.Popen(['env', '--default-signal=INT,QUIT', str(tree / 'scripts/qml-smoke.sh'), '--log-dir', str(output / 'evidence')], stdout=stream, stderr=subprocess.STDOUT)
    ready = None
    deadline = time.monotonic() + float(ready_bound)
    while child.poll() is None and time.monotonic() < deadline:
        log = log_path.read_text(errors='replace')
        ready = re.search(r'^cancel-ready root=(\S+) sandbox=(\S+) attempt=(\S+) record=(\S+)$', log, re.M)
        if ready:
            break
        time.sleep(0.1)
    problems = []
    roots = []
    before = []
    # A world still starting at the bound may only be slow; one whose entry
    # ended without the ready line is a defect at any load.
    not_ready = ready is None and child.poll() is None
    if not_ready:
        problems.append('prerequisite:cancel-row-not-ready')
    elif ready is None:
        problems.append('prerequisite:public-entry-ended-before-ready')
    else:
        root, sandbox, attempt, record = map(pathlib.Path, ready.groups())
        before = processes(str(sandbox))
        argv = '\n'.join(text for _, text in before)
        if not real_producers(argv):
            problems.append('prerequisite:real-producers-not-observed')
        roots = [pathlib.Path(value).parents[1] for value in re.findall(r'^qml-smoke: sandbox (\S+)$', log, re.M)]
        count = 1 if phase == 'initial' else 2
        if len(roots) != count or roots[-1] != root:
            problems.append('world-count-before-stop')
        attempts = re.findall(r'^qml-smoke: attempt=(\S+) targets=', log, re.M)
        if len(attempts) != count or pathlib.Path(attempts[-1]) != attempt or attempt.name != str(count):
            problems.append('current-attempt-before-stop')
        before_stop = len(log)
        for previous in roots[:-1]:
            if previous.exists() or processes(str(previous)):
                problems.append('world-overlap-before-resume')
        if phase == 'resumed' and not re.search(r'world_exit=1 recorder_exit=0 completion=', log):
            problems.append('fatal-world-drain-before-resume')
        if child.poll() is None:
            # This handle is the public entry we started, never its worker.
            os.kill(child.pid, getattr(signal, 'SIG' + kind))
            if stop_phase == 'late-exit':
                accepted = attempt.parent / 'accepted'
                # As in the completion cases, the driver's >> creates the
                # file before its line lands: wait for the whole line.
                while child.poll() is None and not (accepted.exists() and accepted.read_text().endswith('\n')) and time.monotonic() < deadline:
                    time.sleep(0.01)
                if not accepted.exists() or accepted.read_text().strip() != str(expected):
                    problems.append('stop-not-acknowledged')
                else:
                    with (attempt / 'release').open('w') as release:
                        release.write('release\n')
        else:
            problems.append('prerequisite:public-entry-ended-before-stop')
        deadline = time.monotonic() + 30
        while child.poll() is None and time.monotonic() < deadline:
            time.sleep(0.1)
        if child.poll() is None:
            problems.append('cancellation-not-complete')
        elif child.returncode != expected:
            problems.append(f'public-exit:{child.returncode}:expected:{expected}')
        log = log_path.read_text(errors='replace')
        for owned_root in roots:
            if owned_root.exists() or processes(str(owned_root)):
                problems.append('world-left-after-public-return')
        if len(re.findall(r'^qml-smoke: attempt=', log, re.M)) != count:
            problems.append('extra-attempt-after-cancellation')
        finalizer = re.search(rf'^qml-smoke: display-record-retained={re.escape(str(record))} world_exit=\d+ recorder_exit=0 completion={re.escape(str(attempt / "completion.json"))}$', log, re.M)
        cancelled = f'qml-smoke: cancelled signal={kind} status={expected}'
        if finalizer is None or finalizer.start() < before_stop or log.find(cancelled) < finalizer.end():
            problems.append('cancelled-world-log-not-drained')
        attempt_log = (attempt / 'run.log').read_text(errors='replace')
        if finalizer is None or finalizer.group() not in attempt_log or str(sandbox) not in attempt_log:
            problems.append('current-attempt-finalizer-missing')
        teardown = (record / 'teardown').read_text().splitlines()
        if any(line.startswith('original_exit=') for line in teardown) or f'completion={attempt / "completion.json"}' not in teardown:
            problems.append('current-world-authority')
        completion = json.loads((attempt / 'completion.json').read_text())
        if (completion['exit'] != expected or completion['reason'] != f'interrupted:{expected}'
                or completion['world'] != dict(root=str(root), sandbox=str(sandbox), recorder=str(record))
                or completion['joins'] != dict(fence=True, reader=True)):
            problems.append('current-attempt-completion')
        if stop_phase == 'late-exit' and completion['worldExit'] != 0:
            problems.append('prerequisite:late-cleanup-was-not-normal')
        run = json.loads((attempt.parent / 'completion.json').read_text())
        if run['exit'] != expected or run['reason'] != f'interrupted:{expected}' or run['attempts'][-1] != str(attempt / 'completion.json'):
            problems.append('run-completion')
        terminal = [json.loads(line) for line in (record / 'events.jsonl').read_text().splitlines()]
        if any(event['kind'] == 'boundary' and event['data'][0] == 'original-result' for event in terminal):
            problems.append('duplicate-managed-result')
        terminal = [event for event in terminal if event['kind'] == 'terminal']
        if len(terminal) != 1 or terminal[0]['data']['productResult']['authority'] != str(attempt / 'completion.json') or not terminal[0]['data']['stopReason'].startswith('world-exit:'):
            problems.append('current-world-local-facts')
        if cancelled not in log:
            problems.append('cancellation-not-reported')
        if 'cancel-forbidden-ran' in log:
            problems.append('row-ran-after-cancellation')
        # The row the stop held open, which wrote no record, and the row
        # after it have no result; the rows the attempts ended keep theirs.
        if stop_phase == 'row':
            row_results = dict(re.findall(r'^qml-smoke: row-result row=(\S+) status=(\S+.*)$', log, re.M))
            if any(row_results.get(name) != 'unreached' for name in ('cancel-wait', 'cancel-forbidden')):
                problems.append('unreached-not-named')
            ended = [name for name in (tree / 'scripts/smoke/rows.list').read_text().splitlines() if not name.startswith('cancel-')]
            if not ended or any(row_results.get(name, 'unreached') == 'unreached' for name in ended):
                problems.append('ended-row-unreached')
            if phase == 'resumed' and row_results.get('cancel-fatal') != 'failed cause=fatal-bash':
                problems.append('fatal-row-result')
    print(json.dumps({'case': 'cancel-' + phase + '-' + kind, 'public_pid': child.pid, 'exit': child.returncode, 'expected_exit': expected, 'world_roots': list(map(str, roots)), 'before_producers': before, 'problems': problems}), flush=True)
    for line in log_path.read_text(errors='replace').splitlines():
        print('  CONTROL  ' + line)
    # 77 hands the pressure judgement to cancel_case.
    sys.exit(77 if not_ready else bool(problems))
PY
  if [[ $selected_case == all || $selected_case == producer ]]; then
    python3 "$TMP_ROOT/cancel-case.py" --test-producers
  fi
  [[ $selected_case != producer ]] || exit 0
  # The latency rows' pressure reader and busy judge. Sourcing harness.sh
  # starts a world, so only these definitions are taken from it.
  python3 - "$repo/scripts/smoke/harness.sh" >"$TMP_ROOT/contention.sh" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
for name in ('now_ms', 'world_pressure_path', 'pressure_some_us', 'cpu_some_us', 'host_cpu_some_us',
             'cpu_some_pct', 'load_average', 'load_per_core', 'latency_pressure_verdict'):
    found = (re.findall(r'(?m)^' + name + r'\(\) \{.*\}\n', text)
             or re.findall(r'(?ms)^' + name + r'\(\) \{[^\n]*\n.*?^\}\n', text))
    assert len(found) == 1, (name, len(found))
    sys.stdout.write(found[0])
for name in ('world_pressure_file', 'host_pressure_file', 'latency_pressure_limit', 'latency_cores'):
    found = re.findall(r'(?m)^' + name + r'=.*\n', text)
    assert len(found) == 1, (name, len(found))
    sys.stdout.write(found[0])
PY
  source "$TMP_ROOT/contention.sh"
  # cancel_case NAME READY_BOUND_SECS ARG...: one cancel-case.py run in its
  # private PID namespace; returns 0, 1 or 77, judged as the header says
  # over the window of the case. An unreadable reading fails.
  cancel_case() {
    local name="$1" bound="$2" start_ms start_us host_start_us status=0 load per_core pressure host_pressure
    shift 2
    start_ms="$(now_ms)"
    start_us="$(cpu_some_us)"
    host_start_us="$(host_cpu_some_us)"
    timeout -k 2 100 unshare --user --map-current-user --pid --fork --kill-child --mount-proc \
      python3 "$TMP_ROOT/cancel-case.py" "$@" "$bound" || status=$?
    case $status in
      0) printf '  ok    %s\n' "$name"; return 0 ;;
      77) ;;
      *) printf '  FAIL  %s\n' "$name"; return 1 ;;
    esac
    load="$(load_average)"
    per_core="$(load_per_core "$load")"
    pressure="$(cpu_some_pct "$start_us" "$(cpu_some_us)" $(( $(now_ms) - start_ms )))"
    host_pressure="$(cpu_some_pct "$host_start_us" "$(host_cpu_some_us)" $(( $(now_ms) - start_ms )))"
    printf '  ready=late bound_s=%s cpu_some_pct=%s host_cpu_some_pct=%s load=%s load_per_core=%s\n' "$bound" "$pressure" "$host_pressure" "${load:-unmeasured}" "$per_core"
    if [[ $(latency_pressure_verdict 0 "$pressure" 0) == unmeasured ]]; then
      printf '  not-measured %s ready-at-cpu_some_pct=%s-above-%s\n' "$name" "$pressure" "$latency_pressure_limit"
      return 77
    fi
    printf '  FAIL  %s\n' "$name"
    return 1
  }
  if [[ $selected_case != late-exit ]]; then
    # Controls of that verdict at planted pressures, on a stand-in entry:
    # one still starting at the bound while the run's own processes wait,
    # the same while only the host is busy, and one that ended without the
    # ready line, a defect at any pressure. A busy stall total grows with
    # the clock, every microsecond stalled; a quiet one never moves.
    mkdir -- "$TMP_ROOT/starting" "$TMP_ROOT/starting/scripts" "$TMP_ROOT/ended" "$TMP_ROOT/ended/scripts"
    printf '#!/bin/sh\nexec sleep 300\n' >"$TMP_ROOT/starting/scripts/qml-smoke.sh"
    printf '#!/bin/sh\nexit 0\n' >"$TMP_ROOT/ended/scripts/qml-smoke.sh"
    chmod +x "$TMP_ROOT/starting/scripts/qml-smoke.sh" "$TMP_ROOT/ended/scripts/qml-smoke.sh"
    planted_stall() { if [[ $1 == busy ]]; then echo "$(( $(date +%s%N) / 1000 ))"; else echo 0; fi; }
    # entry | world | host | ready bound | status | reading line (extended regex)
    controls=(
      'starting|busy|quiet|0|77|^  ready=late bound_s=0 cpu_some_pct=[1-9][0-9]+\.[0-9] host_cpu_some_pct=0\.0 load='
      'starting|quiet|busy|0|1|^  ready=late bound_s=0 cpu_some_pct=0\.0 host_cpu_some_pct=[1-9][0-9]+\.[0-9] load='
      'ended|busy|busy|60|1|'
    )
    for control in "${controls[@]}"; do
      IFS='|' read -r entry planted_world planted_host bound want reading <<<"$control"
      name="control-$entry-world-$planted_world-host-$planted_host"
      mkdir -- "$TMP_ROOT/$name"
      status=0
      output="$(
        cpu_some_us() { planted_stall "$planted_world"; }
        host_cpu_some_us() { planted_stall "$planted_host"; }
        cancel_case "$name" "$bound" "$TMP_ROOT/$entry" "$TMP_ROOT/$name" TERM initial row
      )" || status=$?
      if [[ $status != "$want" ]] || { [[ -n $reading ]] && ! grep -q -E -- "$reading" <<<"$output"; } ||
        { [[ -z $reading ]] && grep -q '^  ready=' <<<"$output"; }; then
        printf '%s\n' "$output"
        printf '  FAIL  %s status=%s want=%s\n' "$name" "$status" "$want"
        exit 1
      fi
      printf '  ok    %s status=%s\n' "$name" "$status"
    done
  fi
  cancellation_failures=0
  signals=(INT TERM HUP)
  forbidden=(cancel-forbidden)
  stop_phase=row
  if [[ $selected_case == late-exit ]]; then signals=(TERM); forbidden=(); stop_phase=late-exit; fi
  for phase in initial resumed; do
    if [[ $phase == initial ]]; then
      printf '%s\n' "${core[@]}" cancel-wait "${forbidden[@]}" >"$tree/scripts/smoke/rows.list"
    else
      printf '%s\n' "${core[@]}" cancel-fatal cancel-wait "${forbidden[@]}" >"$tree/scripts/smoke/rows.list"
    fi
    for signal in "${signals[@]}"; do
      case_dir="$TMP_ROOT/cancel-$phase-$signal"
      mkdir -- "$case_dir"
      status=0
      cancel_case "cancel-$phase-$signal" 60 "$tree" "$case_dir" "$signal" "$phase" "$stop_phase" || status=$?
      case $status in
        0) ;;
        77) unmeasured_cases+=("cancel-$phase-$signal") ;;
        *) cancellation_failures=$((cancellation_failures + 1)) ;;
      esac
    done
  done
  ((cancellation_failures == 0)) || exit 1
  printf '%s\n' "${core[@]}" provider ordinary fatal-unbound fatal-arithmetic dependent following >"$tree/scripts/smoke/rows.list"
fi
[[ $selected_case != resume && $selected_case != cancellation && $selected_case != late-exit ]] || end_run
python3 - "$tree/scripts/qml-smoke.sh" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
old = '      continue\n    fi\n    if [[ $qml_smoke_attempt_status != 0 ]]; then'
assert text.count(old) == 1
changed = text.replace(old, '      break\n    fi\n    if [[ $qml_smoke_attempt_status != 0 ]]; then')
assert changed != text
path.write_text(changed)
PY
run_case no-resume
cp -- "$repo/scripts/qml-smoke.sh" "$tree/scripts/qml-smoke.sh"
preserve_checkout
cp -- "$tree/scripts/smoke/rows/fatal-unbound.sh" "$tree/scripts/smoke/rows/bar.sh"
run_case fatal-core
printf '# inputs: scripts/smoke/harness.sh\n:\n' >"$tree/scripts/smoke/rows/bar.sh"
printf '# inputs: scripts/smoke/harness.sh\nnot_measured note planted-unavailable\n' >"$tree/scripts/smoke/rows/note.sh"
printf '%s\n' "${core[@]}" provider note following >"$tree/scripts/smoke/rows.list"
run_case not-measured
printf '# inputs: scripts/smoke/harness.sh\n:\n' >"$tree/scripts/smoke/rows/note.sh"
run_case good
printf '# inputs: scripts/smoke/harness.sh\nexit 0\n' >"$tree/scripts/smoke/rows/early-zero.sh"
printf '%s\n' "${core[@]}" provider early-zero following >"$tree/scripts/smoke/rows.list"
run_case early-zero
printf '# inputs: scripts/smoke/harness.sh\nexit 1\n' >"$tree/scripts/smoke/rows/stopped.sh"
printf '%s\n' "${core[@]}" provider stopped following ordinary >"$tree/scripts/smoke/rows.list"
run_case stopped
# The slow row prints a line every 2 s for 18 s, past the 15 s bound; the
# hang row then prints one line and goes silent with TERM ignored, as a
# teardown that hangs on a stop does.
printf '# inputs: scripts/smoke/harness.sh\nfor i in 1 2 3 4 5 6 7 8 9; do sleep 2; ok "slow line $i"; done\n' >"$tree/scripts/smoke/rows/slow.sh"
printf '# inputs: scripts/smoke/harness.sh\nok "hang starts"\ntrap "" TERM\nsleep 600\n' >"$tree/scripts/smoke/rows/hang.sh"
printf '%s\n' "${core[@]}" provider slow hang following >"$tree/scripts/smoke/rows.list"
(export VGS_SMOKE_IDLE_SECS=15; run_case no-progress)
printf '%s\n' "${core[@]}" provider stopped following ordinary >"$tree/scripts/smoke/rows.list"
# label | rows completed before the attempt exits 77
unreached_cases=(
  'pre-world|'
  "stopped-unmeasured|${core[*]} provider"
)
printf '# inputs: scripts/smoke/harness.sh\nexit 77\n' >"$tree/scripts/smoke/rows/stopped.sh"
for unreached_case in "${unreached_cases[@]}"; do
  IFS='|' read -r label completed <<<"$unreached_case"
  if [[ $label == pre-world ]]; then
    printf 'exit 77\n' >"$tree/scripts/smoke/harness.sh"
  else
    cp -- "$repo/scripts/smoke/harness.sh" "$tree/scripts/smoke/harness.sh"
  fi
  run_case "$label" "$TMP_ROOT/$label" "$completed"
done
cp -- "$repo/scripts/smoke/harness.sh" "$tree/scripts/smoke/harness.sh"
[[ $selected_case != unmeasured ]] || end_run
cat >"$tree/scripts/smoke/rows/finish-operation.sh" <<'ROW'
# inputs: scripts/smoke/harness.sh
sink_check() { [[ -n ${smoke_row_name:-} ]] || fail planted-final-operation; }
ROW
printf '%s\n' "${core[@]}" provider following finish-operation >"$tree/scripts/smoke/rows.list"
run_case finish-operation
python3 - "$tree" "$TMP_ROOT/refused-before" <<'PY'
from pathlib import Path
import json, sys
tree, snapshot = map(Path, sys.argv[1:])
assert (tree / 'scripts/qml-smoke.sh').is_file()
snapshot.write_text(json.dumps(sorted(str(path.relative_to(tree)) for path in tree.rglob('*'))))
PY
run_case output-refused "$tree"
python3 - "$tree" "$TMP_ROOT/refused-before" <<'PY'
from pathlib import Path
import json, sys
tree, snapshot = map(Path, sys.argv[1:])
assert json.loads(snapshot.read_text()) == sorted(str(path.relative_to(tree)) for path in tree.rglob('*'))
PY
late_exit_status=0
if [[ $selected_case == all ]]; then "$BASH" "$repo/scripts/test-qml-smoke.sh" --case late-exit || late_exit_status=$?; fi
case $late_exit_status in
  0) ;;
  77) unmeasured_cases+=(late-exit) ;;
  *) exit "$late_exit_status" ;;
esac
end_run
