#!/usr/bin/env bash
# Drive display_record_arm in scripts/smoke/harness.sh, the wait for the
# display recorder's ready line, with the function text taken from the
# harness itself. Each case runs a driver bash that holds the harness's
# spawn, display_record_call and display_record_arm and arms one recorder:
# a stub that exits before it writes, a stub whose healthy start takes two
# seconds, and the real recorder from scripts/smoke/host-window.sh in a
# directory whose control socket path is longer than the 108 bytes of
# sun_path. Each case pins the driver's exit status and its keyed line.
#
# The controls at the end run the pre-fix wait, a harness copy that keeps
# its own write end of the ready pipe, and a recorder copy that binds the
# long path as given, and require each to go red the way its defect does.
#
# Every driver runs with an explicit environment, under a parent deadline,
# and touches no display. A driver ends the process groups of its jobs
# still running on exit; the suite signals nothing else.
#
# Exit 0 when every case and control holds, 1 otherwise.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
harness="$repo/scripts/smoke/harness.sh"

tmp="$(mktemp -d)" || { echo "test-smoke-display-record: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $tmp && ! -L $tmp ]] || { echo "test-smoke-display-record: scratch=not-a-directory value=[$tmp]" >&2; exit 1; }
tmp="$(cd -- "$tmp" && pwd -P)"
trap 'rm -rf -- "${tmp:?}"' EXIT
failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

source "$repo/scripts/smoke/host-window.sh"
display_record_program >"$tmp/recorder.py"

# extract SOURCE OUT: the harness functions the driver runs, each from its
# `name() {` line to the first `}` line after it.
extract() {
  local name text
  : >"$2"
  for name in spawn display_record_call display_record_arm; do
    if ! text="$(sed -n "/^$name() {/,/^}/p" "$1")" || [[ $text != "$name() {"*$'\n}' ]]; then
      echo "test-smoke-display-record: extract=failed function=$name" >&2
      return 1
    fi
    printf '%s\n' "$text" >>"$2"
  done
}
extract "$harness" "$tmp/functions.sh"

# mutate SOURCE OLD NEW OUT: OUT is SOURCE with its one OLD replaced.
mutate() {
  python3 - "$@" <<'PY'
import pathlib, sys
source, old, new, out = sys.argv[1:]
text = pathlib.Path(source).read_text()
assert text.count(old) == 1, "mutation-source: " + old
pathlib.Path(out).write_text(text.replace(old, new))
PY
}

# The driver: FUNCTIONS MODE DIR CMD... MODE arm arms CMD and prints
# `armed`; serve also closes and stops the armed recorder through the
# harness's own client and prints its exit; old runs the pre-fix wait.
cat >"$tmp/driver.sh" <<'SH'
set -euo pipefail
source "$1"
mode="$2" dir="$3"
shift 3
pgids=()
# Each spawned job leads its own process group. Only a job still running
# is signalled, so no reaped pid is reused as a target.
trap 'for pid in $(jobs -pr); do kill -KILL -- "-$pid" 2>/dev/null || true; done' EXIT
display_record_dir="$dir"
case $mode in
  arm)
    display_record_arm "$dir" "$@"
    echo armed ;;
  serve)
    display_record_arm "$dir" "$@"
    display_record_call close 1 cleanup >/dev/null
    display_record_call stop normal >/dev/null
    status=0
    wait "$display_record_pid" || status=$?
    echo "stopped status=$status" ;;
  old)
    mkfifo -m 600 "$dir/ready"
    spawn "$dir/recorder.log" "$@"
    IFS= read -r answer <"$dir/ready"
    echo "answered [$answer]" ;;
esac
SH

printf '%s\n' 'exit 3' >"$tmp/stub-exits.sh"
printf '%s\n' 'sleep 2' 'printf "ready\n" >"$2/ready"' 'exec sleep 60' >"$tmp/stub-slow.sh"

# run MODE DIR_NAME FUNCTIONS RECORDER CMD...: run the driver in a fresh
# directory, with RECORDER copied in as recorder.py when it is not `-`,
# under a deadline of `deadline` seconds. Leaves the exit status in
# `status` and the first qml-smoke line in `keyed`, or the driver's last
# line when it printed none.
status=0 keyed="" deadline=20
run() {
  local mode="$1" dir="$tmp/$2" functions="$3" recorder="$4" out
  shift 4
  mkdir -- "$dir"
  [[ $recorder == - ]] || cp -- "$recorder" "$dir/recorder.py"
  status=0
  out="$(timeout -k 2 "$deadline" env -i PATH="$PATH" HOME="$tmp" TMPDIR="$tmp" LC_ALL=C VGS_TEST_RUN=1 \
    bash "$tmp/driver.sh" "$functions" "$mode" "$dir" "${@//DIR/$dir}" 2>"$dir.err")" || status=$?
  if ! keyed="$(grep -m1 '^qml-smoke: ' <<<"$out")"; then keyed="${out##*$'\n'}"; fi
}

# A directory name that puts DIR/control past the 108 bytes of sun_path.
long="$(printf 'd%.0s' {1..120})"
exits="sh $tmp/stub-exits.sh serve DIR"
real="python3 -u DIR/recorder.py serve DIR"
recorder_exited="qml-smoke: display-record=arm-failed cause=recorder-exited"

# Cases: name | mode | directory | recorder program | recorder command (DIR
# is the directory) | exit | keyed line.
cases=(
  "recorder exits before ready|arm|exits|-|$exits|77|$recorder_exited status=3 log=DIR/recorder.log"
  "a slow healthy start arms|arm|slow|-|sh $tmp/stub-slow.sh serve DIR|0|armed"
  "the recorder arms past the sun_path length|serve|long-$long|$tmp/recorder.py|$real|0|stopped status=0"
)
check() { # LABEL DIR_NAME WANT_STATUS WANT_KEYED
  local want="${4//DIR/$tmp/$2}"
  if [[ $status == "$3" && $keyed == "$want" ]]; then
    ok "$1"
  else
    fail "$1: status=$status keyed=[$keyed] want status=$3 keyed=[$want]; stderr: $(tail -n 3 "$tmp/$2.err" 2>/dev/null)"
  fi
}
for row in "${cases[@]}"; do
  IFS='|' read -r label mode dir_name recorder command want_status want_keyed <<<"$row"
  read -ra argv <<<"$command"
  run "$mode" "$dir_name" "$tmp/functions.sh" "$recorder" "${argv[@]}"
  check "$label" "$dir_name" "$want_status" "$want_keyed"
done

# Controls. The pre-fix wait opened the pipe by name, which never returns
# once the recorder is gone: it must outlast the deadline (timeout's 124).
# The stub exits at once, so a short deadline suffices.
deadline=3
read -ra argv <<<"$exits"
run old control-old "$tmp/functions.sh" - "${argv[@]}"
check "control: the pre-fix wait hangs on a recorder that exits before ready" control-old 124 ""

# A harness that keeps its own write end never reads end of file.
mutate "$harness" 'exec {ready_w}>&-' ':' "$tmp/harness-holds-writer.sh"
extract "$tmp/harness-holds-writer.sh" "$tmp/functions-holds-writer.sh"
run arm control-writer "$tmp/functions-holds-writer.sh" - "${argv[@]}"
check "control: a harness that keeps the write end hangs" control-writer 124 ""

# A recorder that binds the long path as given exits before ready.
deadline=20
mutate "$tmp/recorder.py" 'yield f"/proc/self/fd/{directory}/{path.name}"' 'yield str(path)' "$tmp/recorder-long-path.py"
read -ra argv <<<"$real"
run serve "control-$long" "$tmp/functions.sh" "$tmp/recorder-long-path.py" "${argv[@]}"
check "control: a recorder that binds the long path does not arm" "control-$long" 77 "$recorder_exited status=1 log=DIR/recorder.log"

if [[ $failures -gt 0 ]]; then
  echo "test-smoke-display-record: failed=$failures"
  exit 1
fi
echo "test-smoke-display-record: ok"
