#!/usr/bin/env bash
# Exercise fatal-row recovery through the real entry, world and smoke_row.
# A disposable runtime tree uses neutral core rows, two fatal forms and a
# consumer of a provider's function/private variable. Each attempt starts
# real nested Hyprland and VGS; no host session is used. The mutant disables
# only driver resumption and must lose the following row.
# --case resume runs that existing recovery case alone; --case cancellation
# sends INT, TERM and HUP to the public PID in initial and resumed worlds.
# --case producer checks the controller's recorded bare executable form.
# --case completion checks acknowledged lifecycle boundaries without QML.
# --case late-exit stops real initial and resumed worlds during EXIT.
# Each cancellation case has the private PID namespace and 60 s readiness /
# 30 s stop bounds of test-smoke-owner.sh --live. Its end contains defects.
set -euo pipefail
selected_case=all
if [[ ${1-} == --case && $# == 2 ]]; then
  selected_case=$2
  case "$selected_case" in resume|cancellation|producer|completion|late-exit) ;; *) echo 'test-qml-smoke: refused: case' >&2; exit 2 ;; esac
elif (($#)); then
  echo 'test-qml-smoke: refused: arguments' >&2
  exit 2
fi
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)" || { echo 'test-qml-smoke: scratch=mktemp-failed' >&2; exit 1; }
[[ -d $TMP_ROOT && ! -L $TMP_ROOT ]] || { echo 'test-qml-smoke: scratch=not-a-directory' >&2; exit 1; }
TMP_ROOT="$(cd -- "$TMP_ROOT" && pwd -P)" || { echo 'test-qml-smoke: scratch=resolve-failed' >&2; exit 1; }
trap 'rm -rf -- "${TMP_ROOT:?}"' EXIT
mkdir -- "$TMP_ROOT/tree"
source "$repo/scripts/smoke/tree.sh"
tree_harness_copy "$repo" "$TMP_ROOT/tree" "$repo"
tree="$TMP_ROOT/tree"
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
import hashlib, json, os, pathlib, re, signal, subprocess, sys, time
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
    ('  if ((qml_smoke_run_stop != 0)); then\n', 'after-run-seal'),
]:
    call = f'  completion_barrier {phase}\n'
    driver = change(driver, old, old + call if phase in ('pending-reader', 'early-reader', 'after-attempt-seal') else call + old)
driver = change(driver, 'exec env --default-signal=INT,QUIT tee "$qml_smoke_attempt/run.log"',
                'env --default-signal=INT,QUIT tee "$qml_smoke_attempt/run.log"; completion_barrier reader-only "$qml_smoke_attempt"')
harness = (repo / 'scripts/smoke/harness.sh').read_text()
functions = []
for name in ('spawn', 'display_record_call', 'display_record_close', 'display_record_finish', 'display_record_arm'):
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
leak_seq=0
ok() { :; }
compositor_logs_on() { :; }
smoke_row() { source "$repo/scripts/smoke/rows/$1.sh" >"$sandbox/rows/$1.out" 2>&1; }
smoke_finish() { exit "$failures"; }
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
                    while not accepted.exists() and child.poll() is None and time.monotonic() < deadline:
                        time.sleep(0.01)
                    assert accepted.read_text().splitlines() == ['143'], 'first-stop-not-acknowledged'
                    # A different repeated signal cannot replace the first.
                    os.kill(child.pid, signal.SIGHUP)
                    while len(accepted.read_text().splitlines()) < 2 and child.poll() is None and time.monotonic() < deadline:
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

run_case() {
  local label="$1" destination="${2:-$TMP_ROOT/$1}" status=0
  [[ $selected_case == all || $selected_case == "$label" ]] || return 0
  mkdir -- "$TMP_ROOT/$label"
  "$tree/scripts/qml-smoke.sh" --log-dir "$destination" >"$TMP_ROOT/$label/log" 2>&1 || status=$?
  python3 - "$TMP_ROOT/$label" "$status" "$label" <<'PY'
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
assert status == {'good': 0, 'not-measured': 77}.get(label, 1), (status, log)
assert len(results) == len(by_row), results
if label not in ('no-resume', 'output-refused'):
    targets = (root.parent / 'tree/scripts/smoke/rows.list').read_text().splitlines()
    assert set(by_row) == set(targets), (by_row, targets)
if label == 'resume':
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
    assert 'following' not in by_row, by_row
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
elif label == 'finish-operation':
    assert all(state == 'ok' for state, _ in by_row.values()), by_row
    assert re.search(r'^qml-smoke: failed=1$', log, re.M), log
    assert len(attempts) == 1, log
    assert (attempts[0].parent / 'outside-failures').read_bytes() == b'1\0', log
elif label == 'output-refused':
    assert not by_row, by_row
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
kind, phase, stop_phase = sys.argv[3:]
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
    deadline = time.monotonic() + 60
    while child.poll() is None and time.monotonic() < deadline:
        log = log_path.read_text(errors='replace')
        ready = re.search(r'^cancel-ready root=(\S+) sandbox=(\S+) attempt=(\S+) record=(\S+)$', log, re.M)
        if ready:
            break
        time.sleep(0.1)
    problems = []
    roots = []
    before = []
    if ready is None:
        problems.append('prerequisite:cancel-row-not-ready')
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
                while child.poll() is None and not accepted.exists() and time.monotonic() < deadline:
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
    print(json.dumps({'case': 'cancel-' + phase + '-' + kind, 'public_pid': child.pid, 'exit': child.returncode, 'expected_exit': expected, 'world_roots': list(map(str, roots)), 'before_producers': before, 'problems': problems}), flush=True)
    for line in log_path.read_text(errors='replace').splitlines():
        print('  CONTROL  ' + line)
    sys.exit(bool(problems))
PY
  if [[ $selected_case == all || $selected_case == producer ]]; then
    python3 "$TMP_ROOT/cancel-case.py" --test-producers
  fi
  [[ $selected_case != producer ]] || exit 0
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
      if timeout -k 2 100 unshare --user --map-current-user --pid --fork --kill-child --mount-proc \
        python3 "$TMP_ROOT/cancel-case.py" "$tree" "$case_dir" "$signal" "$phase" "$stop_phase"; then
        printf '  ok    cancel-%s-%s\n' "$phase" "$signal"
      else
        cancellation_failures=$((cancellation_failures + 1))
        printf '  FAIL  cancel-%s-%s\n' "$phase" "$signal"
      fi
    done
  done
  ((cancellation_failures == 0)) || exit 1
  printf '%s\n' "${core[@]}" provider ordinary fatal-unbound fatal-arithmetic dependent following >"$tree/scripts/smoke/rows.list"
fi
[[ $selected_case != resume && $selected_case != cancellation && $selected_case != late-exit ]] || exit 0
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
if [[ $selected_case == all ]]; then "$BASH" "$repo/scripts/test-qml-smoke.sh" --case late-exit; fi
