#!/usr/bin/env bash
# Prove that scripts/smoke/gpu-fence.sh ends every process a smoke sandbox
# starts and removes the directories its harness names, on every way a run
# can end.
#
# Usage: scripts/test-smoke-owner.sh
#        scripts/test-smoke-owner.sh --live
#
# Each case runs in a PID namespace of its own that util-linux unshare
# makes, whose end ends whatever a defect leaves. Its PID 1, case.sh, runs
# the fence over a stand-in harness. The stand-in sources
# scripts/smoke/teardown.sh as the harness does, makes a sandbox and a
# runtime dir and names them in the fence's ledger as the harness does, and
# starts the process shapes a sandbox holds: two daemons in sessions of
# their own, recorded as spawn records them (the D-Bus daemons and the
# compositor), a runner whose child it waits on (`vgshell run` and qs), a
# process in a session no group record holds (a shell the compositor
# relaunched) and a stopped one. It takes the write bits off a folder in
# the sandbox, as the TUI fixtures are. Then it exits, fails under set -e,
# or waits for the case's signal. Once the fence returns, the case reads
# that no process but case.sh is left in its namespace, and whether each
# directory is gone. The controls plant one defect per rule in a copy of
# the fence and require the case that rule owns to go red.
#
# --live runs scripts/qml-smoke.sh --rows bar twice, in a namespace of the
# suite's own, and interrupts the harness, with INT and then with SIGKILL.
# It reads that the sandbox's qs, nested Hyprland and both D-Bus daemons
# ran before the signal, and that no process naming the sandbox and no
# sandbox directory is left after. It needs the nested sandbox's
# environment: WAYLAND_DISPLAY, XDG_RUNTIME_DIR and the fleet slot.
#
# Exit 0 when every case and control holds, 1 otherwise, 77 when unshare
# or bubblewrap cannot make a namespace here.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
fence="$repo/scripts/smoke/gpu-fence.sh"
teardown="$repo/scripts/smoke/teardown.sh"

TMP_ROOT="$(mktemp -d)" || { echo "test-smoke-owner: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $TMP_ROOT && ! -L $TMP_ROOT ]] || { echo "test-smoke-owner: scratch=not-a-directory value=[$TMP_ROOT]" >&2; exit 1; }
TMP_ROOT="$(cd -- "$TMP_ROOT" && pwd -P)" || { echo "test-smoke-owner: scratch=resolve-failed" >&2; exit 1; }
# A case a control turned red can leave a folder without write bits.
trap 'chmod -R u+rwX -- "${TMP_ROOT:?}" 2>/dev/null || true; rm -rf -- "${TMP_ROOT:?}"' EXIT
failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

# contain: a namespace of the suite's own. unshare blocks TERM and INT
# while it waits, so a time limit over it ends it with KILL after its grace.
contain=(unshare --user --map-current-user --pid --fork --kill-child --mount-proc)
if ! "${contain[@]}" true 2>/dev/null || ! bwrap --dev-bind / / --unshare-pid --proc /proc true 2>/dev/null; then
  echo "test-smoke-owner: status=not-measured missing=namespace"
  exit 77
fi

# left_naming TEXT: one line per process whose argv holds TEXT, as its pid
# and argv. It only reads.
left_naming() {
  python3 -c 'import os, sys
for pid in filter(str.isdigit, os.listdir("/proc")):
    try:
        argv = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        continue
    if sys.argv[1] in argv and pid != str(os.getpid()):
        print(pid, argv)' "$1"
}

if [[ ${1-} == --live ]]; then
  for need in WAYLAND_DISPLAY XDG_RUNTIME_DIR; do
    [[ -n ${!need:-} ]] || { echo "test-smoke-owner: status=not-measured missing=$need"; exit 77; }
  done
  # shell_runs TEXT: TEXT, the processes naming the sandbox, holds its qs,
  # its nested Hyprland and both D-Bus daemons.
  shell_runs() {
    grep -Eq '[ /]qs .*-p ' <<<"$1" && grep -q 'Hyprland --config' <<<"$1" &&
      [[ $(grep -c 'dbus-daemon --nofork' <<<"$1") -eq 2 ]]
  }
  # live SIGNAL: one smoke run, its harness sent SIGNAL once its shell runs.
  live() {
    local signal="$1" out="$TMP_ROOT/live-$1.out" runner fence="" monitor="" binit="" harness="" sandbox="" before="" status=0 _
    "${contain[@]}" env --default-signal=INT "$repo/scripts/qml-smoke.sh" --rows bar >"$out" 2>&1 &
    runner=$!
    for _ in $(seq 1 600); do
      kill -0 "$runner" 2>/dev/null || break
      sandbox="$(sed -n 's/^qml-smoke: sandbox //p' "$out")"
      if [[ -n $sandbox ]] && before="$(left_naming "$sandbox")" && shell_runs "$before"; then break; fi
      sleep 0.1
    done
    # unshare -> its PID 1, the fence -> bubblewrap's monitor -> its init
    # -> the harness. A children file ends with no newline, so read
    # answers 1 while it fills its variables.
    read -r fence _ <"/proc/$runner/task/$runner/children" || true
    [[ -z $fence ]] || read -r monitor _ <"/proc/$fence/task/$fence/children" || true
    [[ -z $monitor ]] || read -r binit _ <"/proc/$monitor/task/$monitor/children" || true
    [[ -z $binit ]] || read -r harness _ <"/proc/$binit/task/$binit/children" || true
    # The control: before the signal, the read finds what it must not find
    # after it.
    if [[ -z $sandbox || -z $harness ]] || ! shell_runs "$before" || [[ ! -d $sandbox ]]; then
      fail "control: live $signal: the read never found the sandbox's shell running (sandbox=[$sandbox] harness=[$harness]):"
      printf '        %s\n' "$before"
      sed 's/^/        /' -- "$out"
      if [[ -n $harness ]]; then kill -TERM -- "$harness" 2>/dev/null || true; else kill -KILL -- "$runner" 2>/dev/null || true; fi
      wait "$runner" 2>/dev/null || true
      return
    fi
    ok "control: live $signal: before the signal the read finds qs, Hyprland, both D-Bus daemons and the sandbox"
    kill -s "$signal" -- "$harness"
    for _ in $(seq 1 300); do kill -0 "$runner" 2>/dev/null || break; sleep 0.1; done
    if kill -0 "$runner" 2>/dev/null; then
      fail "live $signal: the run did not end within 30 s"
      kill -KILL "$runner" 2>/dev/null || true
    fi
    wait "$runner" 2>/dev/null || status=$?
    local after
    after="$(left_naming "$sandbox")" || after="unreadable"
    if [[ -z $after && ! -e $sandbox ]]; then
      ok "live $signal: no process naming the sandbox and no sandbox directory is left (exit $status)"
    else
      fail "live $signal: left after the run (sandbox exists: $([[ -e $sandbox ]] && echo yes || echo no)):"; printf '        %s\n' "$after"
    fi
  }
  live INT
  live KILL
  if [[ $failures -gt 0 ]]; then echo "test-smoke-owner: failed=$failures"; exit 1; fi
  echo "test-smoke-owner: ok"
  exit 0
fi

# Trees with no DRM node: the fence makes its namespace and changes nothing
# under /dev.
mkdir -p "$TMP_ROOT/sys/class/drm" "$TMP_ROOT/dev" "$TMP_ROOT/bin"
for tool in bash bwrap chmod mkdir mktemp readlink realpath rm sed seq setsid sh sleep stat true; do
  tool_path="$(type -P "$tool")" || { echo "test-smoke-owner: missing=$tool" >&2; exit 1; }
  ln -s -- "$tool_path" "$TMP_ROOT/bin/$tool"
done

# The stand-in harness: TEARDOWN MODE CASE_DIR. MODE pass exits 0, fail
# fails under set -e, wait idles until a signal; keep is wait under --keep.
# It idles in the wait builtin: bash acts on an INT that comes while a
# foreground child runs only once that child has ended of it too.
cat >"$TMP_ROOT/harness.sh" <<'SH'
set -euo pipefail
teardown="$1" mode="$2" case_dir="$3"
sandbox="" rt_dir="" pgids=() keep=false
[[ $mode != keep ]] || keep=true
source "$teardown"
sandbox="$(mktemp -d "$TMPDIR/vgshell-smoke.XXXXXX")"
[[ $keep == true ]] || printf '%s\n' "$sandbox" >>"$VGSHELL_FENCE_LEDGER"
rt_dir="$(mktemp -d "$TMPDIR/vs.XXXXXX")"
[[ $keep == true ]] || printf '%s\n' "$rt_dir" >>"$VGSHELL_FENCE_LEDGER"
printf '%s\n%s\n' "$sandbox" "$rt_dir" >"$case_dir/dirs"
for _ in session system compositor; do setsid sleep 300 & pgids+=("$!"); done
setsid sh -c 'sleep 301 & wait' & pgids+=("$!")
setsid sh -c 'setsid sleep 302 & wait' &
sleep 303 &
kill -STOP $!
mkdir -p -- "$sandbox/tui-fixtures/a/tui"
chmod a-w -- "$sandbox/tui-fixtures/a/tui" "$sandbox/tui-fixtures/a"
: >"$case_dir/ready"
case $mode in
  pass) exit 0 ;;
  fail) false ;;
  wait|keep) while :; do sleep 0.1 & wait $!; done ;;
esac
SH

# case.sh FENCE TEARDOWN MODE CASE_DIR ROOT TARGET SIGNAL: PID 1 of the
# case's namespace. It runs FENCE over the stand-in and, once the stand-in
# is ready, sends SIGNAL to TARGET, `harness` or `fence`. It writes to
# CASE_DIR/verdict the fence's exit status, or `running` when the fence
# has not returned within 10 s, and how many processes but its own are
# left, once none is or after 5 s more. A zombie has ended.
cat >"$TMP_ROOT/case.sh" <<'SH'
fence="$1" teardown="$2" mode="$3" case_dir="$4" root="$5" target="$6" signal="$7"
env -i --default-signal=INT PATH="$root/bin" HOME="$root" TMPDIR="$case_dir" \
  "$root/bin/bash" "$fence" --sys "$root/sys" --dev "$root/dev" \
  "$root/bin/bash" "$root/harness.sh" "$teardown" "$mode" "$case_dir" >"$case_dir/out" 2>"$case_dir/err" &
pid=$!
if [[ -n $signal ]]; then
  for _ in $(seq 1 200); do [[ -e $case_dir/ready ]] && break; sleep 0.05; done
  victim="$pid"
  if [[ $target == harness ]]; then
    # The fence -> bubblewrap's monitor -> its init -> the harness.
    read -r monitor _ <"/proc/$pid/task/$pid/children"
    read -r init _ <"/proc/$monitor/task/$monitor/children"
    read -r victim _ <"/proc/$init/task/$init/children"
  fi
  kill -s "$signal" -- "$victim"
fi
ended() { local line; read -r line 2>/dev/null <"/proc/$1/stat" || return 0; line="${line##*) }"; [[ ${line%% *} == Z ]]; }
for _ in $(seq 1 200); do ended "$pid" && break; sleep 0.05; done
status=running
if ended "$pid"; then status=0; wait "$pid" || status=$?; fi
for _ in $(seq 1 100); do
  left=0
  for entry in /proc/[0-9]*; do
    [[ ${entry#/proc/} != 1 ]] || continue
    read -r line 2>/dev/null <"$entry/stat" || continue
    rest="${line##*) }"
    [[ ${rest%% *} == Z ]] || left=$((left + 1))
  done
  ((left == 0)) && break
  sleep 0.05
done
echo "status=$status left=$left" >"$case_dir/verdict"
SH

# run_case FENCE ROW: true when the case holds. What broke is in
# `problems`, the case's directory in `case_dir`.
cases=0
problems=()
case_dir=""
run_case() {
  local file="$1" label mode target signal want_status want_dirs fence_status="" left="" dir status=0
  IFS='|' read -r label mode target signal want_status want_dirs <<<"$2"
  cases=$((cases + 1))
  case_dir="$TMP_ROOT/case-$cases"
  mkdir -- "$case_dir"
  problems=()
  # The shell reports on stderr a job a signal ended; the status says it.
  { timeout -k 2 30 "${contain[@]}" bash "$TMP_ROOT/case.sh" "$file" "$teardown" "$mode" "$case_dir" "$TMP_ROOT" "$target" "$signal" \
    >"$case_dir/case.out" 2>&1 || status=$?; } 2>/dev/null
  [[ $status -eq 0 ]] || problems+=("case-exit=$status")
  [[ ! -r $case_dir/verdict ]] || read -r fence_status left <"$case_dir/verdict" || true
  [[ ${fence_status-} == "status=$want_status" ]] || problems+=("fence-${fence_status:-status=none} want=$want_status")
  [[ ${left-} == left=0 ]] || problems+=("processes-${left:-left=none}")
  if [[ ! -r $case_dir/dirs ]]; then
    problems+=("dirs=unrecorded")
  else
    while IFS= read -r dir; do
      case $want_dirs in
        gone) [[ ! -e $dir ]] || problems+=("left=${dir##*/}") ;;
        kept) [[ -d $dir ]] || problems+=("not-kept=${dir##*/}") ;;
        *) problems+=("row=unknown-dirs-expectation:$want_dirs") ;;
      esac
    done <"$case_dir/dirs"
  fi
  if grep -q '^gpu-fence: cleanup=' -- "$case_dir/err"; then problems+=("$(grep -m 1 '^gpu-fence: cleanup=' -- "$case_dir/err")"); fi
  [[ ${#problems[@]} -eq 0 ]]
}

# Rows: label | stand-in mode | signal target | signal | the fence's exit
# status | the directories gone or kept. A SIGKILL of the fence itself
# leaves the directories, which the fence can no longer remove; its row
# reads only that no process is left.
cases_table=(
  "a run that passes leaves no process and no directory|pass|||0|gone"
  "a run that fails under set -e leaves no process and no directory|fail|||1|gone"
  "INT to the harness leaves no process and no directory|wait|harness|INT|130|gone"
  "TERM to the harness leaves no process and no directory|wait|harness|TERM|143|gone"
  "HUP to the harness leaves no process and no directory|wait|harness|HUP|129|gone"
  "a SIGKILL of the harness leaves no process and no directory|wait|harness|KILL|137|gone"
  "a kept sandbox stays, with no process left|keep|harness|TERM|143|kept"
  "a SIGKILL of the fence leaves no process|wait|fence|KILL|137|kept"
)
for row in "${cases_table[@]}"; do
  if run_case "$fence" "$row"; then ok "${row%%|*}"; else fail "${row%%|*}: ${problems[*]}"; fi
done

# mutate OLD NEW OUT: a copy of the fence with OLD, which must occur once,
# replaced by NEW.
mutate() {
  local text rest count
  text="$(<"$fence")"
  rest="${text//"$1"/}"
  count=$(( (${#text} - ${#rest}) / ${#1} ))
  if [[ $count -ne 1 ]]; then
    printf '        mutation matched %s times: %s\n' "$count" "$1"
    return 1
  fi
  printf '%s\n' "${text/"$1"/"$2"}" >"$3"
  ! cmp -s -- "$fence" "$3" || { printf '        mutation left the file unchanged: %s\n' "$1"; return 1; }
}

# Rows: label | text | replacement | the case that must go red | the
# problem it must report. A field holds no `|`.
controls=(
  "the namespace is no PID namespace| --unshare-pid --proc /proc||a SIGKILL of the harness leaves no process and no directory|processes-left=[1-9]"
  "bubblewrap outlives the fence|--proc /proc --die-with-parent --new-session|--proc /proc --new-session|a SIGKILL of the fence leaves no process|processes-left=[1-9]"
  "the ledger is not read|done <\"\$fence_dir/ledger\"|done </dev/null|a SIGKILL of the harness leaves no process and no directory|left=vgshell-smoke."
  "the owner bits are not given back|chmod -R u+rwX -- \"\$path\" 2>/dev/null|true|a SIGKILL of the harness leaves no process and no directory|gpu-fence: cleanup=rm-failed path="
)
for i in "${!controls[@]}"; do
  IFS='|' read -r label old new target want <<<"${controls[i]}"
  mutant="$TMP_ROOT/mutant-$i.sh"
  if ! mutate "$old" "$new" "$mutant"; then fail "control: $label"; continue; fi
  row=""
  for candidate in "${cases_table[@]}"; do [[ ${candidate%%|*} == "$target" ]] && row="$candidate"; done
  if [[ -z $row ]]; then fail "control: $label names no case: $target"; continue; fi
  if run_case "$mutant" "$row"; then
    fail "control: $label left '$target' green"
  elif [[ " ${problems[*]} " != *" "$want* ]]; then
    fail "control: $label went red without $want: ${problems[*]}"
  else
    ok "control: $label"
  fi
done

if [[ $failures -gt 0 ]]; then
  echo "test-smoke-owner: failed=$failures"
  exit 1
fi
echo "test-smoke-owner: ok"
