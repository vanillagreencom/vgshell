#!/usr/bin/env bash
# Drive scripts/smoke/teardown.sh, the smoke sandbox's teardown, through the
# exits a run of the read-only prefix row can take. Each case starts a child
# bash in its own process group that sources the teardown the way harness.sh
# does, makes a sandbox, a runtime dir and an export under this suite's
# scratch directory, builds a nested prefix tree, records one process group
# as spawn does, and takes the write bits off the tree as
# scripts/smoke/rows/read-only-prefix.sh does. The child then fails under
# set -e, or waits for the signals the case sends to its process group. Each
# case pins the exit status, whether the sandbox and the runtime dir are gone
# or kept, that the export and the recorded process group are gone, and that
# stderr is empty. The controls at the end plant one defect per rule in a
# copy of the teardown and require the case that rule owns to go red. The
# sink cases run the teardown with harness.sh's own sink_alive over a
# stand-in sink and pin the line it prints for a sink that exited.
#
# The child gets an explicit environment. Its sandbox and runtime dir are
# never under the host's XDG_RUNTIME_DIR. The suite signals only the process
# groups it started and those its children recorded.
#
# Exit 0 when every case and control holds, 1 otherwise.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
teardown="$repo/scripts/smoke/teardown.sh"
source_tree_only=false
if [[ ${1:-} == --source-tree-cases && $# -le 2 ]]; then
  source_tree_only=true
  teardown="${2:-$teardown}"
elif [[ $# -gt 0 ]]; then
  echo 'test-smoke-teardown: refused: arguments' >&2
  exit 2
fi

# The EXIT trap is armed only on the directory mktemp made: an empty or
# non-directory answer never reaches rm -rf.
mkdir -p -- "$repo/tmp"
tmp="$(mktemp -d "$repo/tmp/test-smoke-teardown.XXXXXX")" || { echo "test-smoke-teardown: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $tmp && ! -L $tmp ]] || { echo "test-smoke-teardown: scratch=not-a-directory value=[$tmp]" >&2; exit 1; }
tmp="$(cd -- "$tmp" && pwd -P)"
# Process groups this suite started or its children recorded. A control's
# case leaves a non-writable tree, so the owner bits come back before rm.
groups=()
finish() {
  local pg
  for pg in "${groups[@]}"; do kill -KILL -- "-$pg" 2>/dev/null || true; done
  chmod -R u+rwX -- "${tmp:?}" 2>/dev/null || true
  rm -rf -- "${tmp:?}"
}
trap finish EXIT
failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

# Only disposable git repositories are passed to the teardown, including
# the control against the previous teardown that would delete a checkout.
cat >"$tmp/source-child.sh" <<'SH'
set -euo pipefail
sandbox="" rt_dir="" pgids=() keep=false
source_tree="$2" VGSHELL_FENCE_LEDGER="$3"
source "$1"
exit 0
SH
source_case() { # TEARDOWN KIND
  local file="$1" kind="$2" dir target status=0 diagnostic recorded
  source_case_deleted=false
  dir="$(mktemp -d "$tmp/source-case.XXXXXX")" || return 1
  mkdir -- "$dir/repository"
  git -C "$dir/repository" init -q || return 1
  printf 'retained\n' >"$dir/repository/marker"
  git -C "$dir/repository" add marker || return 1
  git -C "$dir/repository" -c user.name=Test -c user.email=test@example.invalid commit -qm fixture || return 1
  case "$kind" in
    repository) target="$dir/repository" ;;
    worktree)
      target="$dir/worktree"
      git -C "$dir/repository" worktree add -q --detach "$target" HEAD || return 1
      ;;
    export|unrecorded|prefix|removed)
      target="$dir/export"
      mkdir -- "$target"
      git -C "$dir/repository" archive HEAD | tar -x -C "$target" || return 1
      ;;
    symlink)
      target="$dir/export"
      ln -s -- "$dir/repository" "$target" || return 1
      ;;
    *) return 1 ;;
  esac
  recorded="$target"
  case "$kind" in
    unrecorded) recorded="$dir/other-export" ;;
    prefix) recorded="$target-neighbour" ;;
    removed) rm -rf -- "${target:?}" || return 1 ;;
  esac
  printf '%s\n' "$recorded" >"$dir/ledger"
  timeout -k 2 10 env -i PATH="$PATH" HOME="$tmp/home" LC_ALL=C VGS_TEST_RUN=1 \
    "$BASH" "$tmp/source-child.sh" "$file" "$target" "$dir/ledger" >"$dir/out" 2>"$dir/err" || status=$?
  diagnostic="$(<"$dir/err")" || return 1
  if [[ $status == 0 && ! -e $target ]]; then source_case_deleted=true; fi
  case "$kind" in
    export|removed)
      [[ $status == 0 && ! -e $target && -z $diagnostic ]]
      ;;
    *)
      # The issue archive reads this stable refusal record. Every refusal
      # must preserve the directory and the fixture content it held.
      [[ $status == 1 && $diagnostic == "teardown: source-tree-refused path=$target cause="?* && -d $target && $(<"$target/marker") == retained ]]
      ;;
  esac
}
source_cases=(repository worktree export unrecorded prefix symlink removed)
for kind in "${source_cases[@]}"; do
  if source_case "$teardown" "$kind"; then ok "source tree: $kind"; else fail "source tree: $kind"; fi
done
# The control runs only the new contract, with the original deletion
# reachable and every candidate still confined to the scratch directory.
if [[ $source_tree_only == false ]]; then
  if ! python3 - "$teardown" "$tmp/source-unguarded.sh" <<'PY_CONTROL'
import pathlib, sys
source, target = map(pathlib.Path, sys.argv[1:])
text = source.read_text()
old = '  teardown_source_tree_check || source_tree_status=$?'
assert text.count(old) == 1
changed = text.replace(old, '  :')
assert changed != text
target.write_text(changed)
PY_CONTROL
  then fail 'control: source tree refusal mutation'
  elif source_case "$tmp/source-unguarded.sh" worktree; then
    fail 'control: an unguarded source tree deletion left the worktree case green'
  elif [[ $source_case_deleted != true ]]; then
    fail 'control: the worktree case failed without deleting its throwaway worktree'
  else
    ok 'control: an unguarded source tree deletion'
  fi
fi
if [[ $source_tree_only == true ]]; then
  if [[ $failures -gt 0 ]]; then echo "test-smoke-teardown: failed=$failures"; exit 1; fi
  echo 'test-smoke-teardown: ok'
  exit 0
fi

# The process group the child records. TERM from the teardown writes the
# marker the second-signal cases wait for.
cat >"$tmp/group.sh" <<'SH'
# Delay trap installation so the signal cases require the ready handshake.
sleep 0.1
trap ': >"$1"; exit 0' TERM
printf 'ready\n' >"$2"
while :; do sleep 0.1; done
SH
cat >"$tmp/recorder.sh" <<'SH'
trap ': >"$1/recorder-termed"; exit 0' TERM
printf 'ready\n' >"$1/recorder-ready"
while :; do sleep 0.1; done
SH

# The child: TEARDOWN MODE CASE_DIR GROUP_SCRIPT. MODE abort fails under
# set -e after the chmod, keep does the same with keep=true, wait idles
# until a signal ends it.
cat >"$tmp/child.sh" <<'SH'
set -euo pipefail
teardown="$1" mode="$2" case_dir="$3" group_script="$4"
sandbox="" rt_dir="" pgids=() keep=false
[[ $mode != keep ]] || keep=true
source_tree="$case_dir/export"
mkdir -- "$source_tree"
VGSHELL_FENCE_LEDGER="$case_dir/ledger"
printf '%s\n' "$source_tree" >"$VGSHELL_FENCE_LEDGER"
[[ $mode != refused ]] || : >"$VGSHELL_FENCE_LEDGER"
source "$teardown"
sandbox="$case_dir/sandbox"
mkdir -- "$sandbox"
rt_dir="$case_dir/runtime"
mkdir -- "$rt_dir"
readonly_dest="$sandbox/read-only-prefix"
mkdir -p -- "$readonly_dest/usr/bin" "$readonly_dest/usr/share/vgshell/shell/Core" "$readonly_dest/usr/share/vgshell/themes/targets/kitty"
printf '#!/bin/sh\n' >"$readonly_dest/usr/bin/vgshell"
chmod 755 -- "$readonly_dest/usr/bin/vgshell"
echo 'Item {}' >"$readonly_dest/usr/share/vgshell/shell/Core/Config.qml"
echo '{}' >"$readonly_dest/usr/share/vgshell/themes/targets/kitty/target.json"
group_ready="$case_dir/group-ready"
mkfifo "$group_ready"
setsid bash "$group_script" "$case_dir/group-termed" "$group_ready" &
pgids+=("$!")
printf '%s\n' "$!" >"$case_dir/group"
IFS= read -r ready <"$group_ready"
chmod -R a-w -- "$readonly_dest/usr"
if [[ $mode == recorder* ]]; then
  mkfifo "$case_dir/recorder-ready"
  setsid "$BASH" "$case_dir/../recorder.sh" "$case_dir" &
  display_record_pid=$!
  pgids+=("$display_record_pid")
  printf '%s\n' "$display_record_pid" >"$case_dir/recorder"
  IFS= read -r ready <"$case_dir/recorder-ready"
  display_record_dir="$case_dir"
  display_record_close() {
    local original_status="$1"
    if [[ $original_status != 1 || -e $case_dir/group-termed || -e $case_dir/recorder-termed ]]; then
      printf 'wrong-order\n' >"$case_dir/close-receipt"
      return 1
    fi
    if [[ $mode == recorder-close-failed ]]; then
      printf 'failed\n' >"$case_dir/close-receipt"
      return 1
    fi
    printf 'closed-before-TERM\n' >"$case_dir/close-receipt"
  }
  display_record_finish() {
    local original_status="$1" producer
    producer="$(<"$case_dir/group")" || return 1
    wait "$producer" 2>/dev/null || true
    if [[ $original_status != 1 || ! -d $sandbox || ! -d $rt_dir || -e $case_dir/recorder-termed || ! -e $case_dir/group-termed ]]; then
      printf 'incomplete\n' >"$case_dir/recorder-receipt"
      kill -TERM -- "-$display_record_pid" 2>/dev/null || true
      wait "$display_record_pid" || true
      return 1
    fi
    kill -TERM -- "-$display_record_pid"
    wait "$display_record_pid" || true
    if [[ $mode == recorder-failed || $mode == recorder-close-failed ]]; then
      printf 'incomplete\n' >"$case_dir/recorder-receipt"
      return 1
    fi
    printf 'finished original_status=%s\n' "$original_status" >"$case_dir/recorder-receipt"
  }
fi
case $mode in
  abort|keep|refused|recorder|recorder-failed|recorder-close-failed) false ;;
  wait) : >"$case_dir/ready"; while :; do sleep 0.1; done ;;
esac
SH

# wait_for PATH: true once PATH exists. A real wait: the child makes it
# asynchronously; 10 s is far past the milliseconds it takes.
wait_for() {
  local _
  for _ in $(seq 1 500); do [[ -e $1 ]] && return 0; sleep 0.02; done
  return 1
}

# gone PID_OR_GROUP TRIES: true once kill -0 finds nothing, polled every
# 20 ms. A real wait: the teardown takes half a second, and a killed process
# lingers until its parent or the reaper collects it.
gone() {
  local _
  for _ in $(seq 1 "$2"); do kill -0 -- "$1" 2>/dev/null || return 0; sleep 0.02; done
  return 1
}

# run_case FILE ROW: true when the teardown FILE holds the row. What broke
# is in `problems`, the case's directory in `case_dir`, and the first
# teardown failure line the child printed on stderr in `keyed_err`. Bash's
# own job notices, such as `Terminated`, may share stderr.
cases=0
problems=()
case_dir=""
keyed_err=""
run_case() {
  local file="$1" label mode signals want_status want_sandbox pid status=0 sig first=true recorded
  IFS='|' read -r label mode signals want_status want_sandbox <<<"$2"
  cases=$((cases + 1))
  case_dir="$tmp/case-$cases"
  mkdir -- "$case_dir"
  problems=()
  # env restores SIGINT, which bash ignores in a background command.
  setsid env -i --default-signal=INT PATH="$PATH" HOME="$tmp/home" TMPDIR="$tmp" LC_ALL=C \
    bash "$tmp/child.sh" "$file" "$mode" "$case_dir" "$tmp/group.sh" >"$case_dir/out" 2>"$case_dir/err" &
  pid=$!
  groups+=("$pid")
  if [[ -n $signals ]]; then
    if ! wait_for "$case_dir/ready"; then
      problems+=("ready=missing")
    else
      for sig in $signals; do
        # A later signal lands while the teardown waits after the TERM it
        # sent the recorded group, before it removes anything.
        if [[ $first == false ]] && ! wait_for "$case_dir/group-termed"; then
          problems+=("group-termed=missing")
          break
        fi
        kill -"$sig" -- "-$pid"
        first=false
      done
    fi
  fi
  if ! gone "$pid" 500; then
    problems+=("child=still-running")
    kill -KILL -- "-$pid" 2>/dev/null || true
  fi
  # Bash prints its own notice when the job died of a signal, such as
  # `Hangup`; the status below carries that signal.
  { wait "$pid"; } 2>/dev/null || status=$?
  keyed_err=""
  if [[ ! -r $case_dir/err ]]; then
    problems+=("stderr=unreadable")
  elif ! keyed_err="$(grep -m 1 '^qml-smoke: cleanup=' -- "$case_dir/err")"; then
    keyed_err=""
  fi
  [[ $status -eq $want_status ]] || problems+=("exit=$status want=$want_status")
  if recorded="$(<"$case_dir/group")" 2>/dev/null && [[ -n $recorded ]]; then
    groups+=("$recorded")
    gone "-$recorded" 100 || problems+=("recorded-group=alive")
  else
    problems+=("recorded-group=unrecorded")
  fi
  if [[ $mode == refused ]]; then
    [[ -d $case_dir/export ]] || problems+=("refused-export=removed")
    grep -Fx -- "teardown: source-tree-refused path=$case_dir/export cause=unrecorded-export" "$case_dir/err" >/dev/null || problems+=("source-refusal=missing")
  else
    [[ ! -e $case_dir/export ]] || problems+=("export=left")
  fi
  if [[ -f $case_dir/recorder ]]; then
    recorded="$(<"$case_dir/recorder")"
    groups+=("$recorded")
    if ! gone "-$recorded" 100; then
      problems+=("recorder-group=alive")
      kill -KILL -- "-$recorded" 2>/dev/null || true
    fi
  fi
  if [[ $mode == recorder ]]; then
    [[ -f $case_dir/recorder-receipt && $(<"$case_dir/recorder-receipt") == 'finished original_status=1' ]] || problems+=("recorder-evidence=missing")
    [[ -e $case_dir/recorder-termed ]] || problems+=("recorder-cleanup=missing")
    [[ -f $case_dir/close-receipt && $(<"$case_dir/close-receipt") == closed-before-TERM ]] || problems+=("recorder-close-order=wrong")
  elif [[ $mode == recorder-failed ]]; then
    [[ -f $case_dir/recorder-receipt && $(<"$case_dir/recorder-receipt") == incomplete ]] || problems+=("recorder-error=missing")
    [[ $keyed_err == "qml-smoke: cleanup=recorder-finalization-failed path=$case_dir" ]] || problems+=("recorder-diagnostic=missing")
    keyed_err=""
  elif [[ $mode == recorder-close-failed ]]; then
    [[ -f $case_dir/recorder-receipt && $(<"$case_dir/recorder-receipt") == incomplete ]] || problems+=("recorder-error=missing")
    [[ $keyed_err == "qml-smoke: cleanup=recorder-close-failed path=$case_dir" ]] || problems+=("recorder-close-diagnostic=missing")
    keyed_err=""
  fi
  case $want_sandbox in
    gone)
      [[ ! -e $case_dir/sandbox ]] || problems+=("sandbox=left")
      [[ ! -e $case_dir/runtime ]] || problems+=("runtime=left")
      [[ -z $keyed_err ]] || problems+=("teardown=failed")
      ;;
    kept)
      [[ -d $case_dir/sandbox && -d $case_dir/runtime ]] || problems+=("sandbox=not-kept")
      rm -rf -- "$case_dir/sandbox" 2>/dev/null || problems+=("kept-sandbox=not-removable")
      [[ ! -e $case_dir/sandbox ]] || problems+=("kept-sandbox=left-after-rm")
      ;;
    *) problems+=("row=unknown-sandbox-expectation:$want_sandbox") ;;
  esac
  [[ ${#problems[@]} -eq 0 ]]
}

# Rows: label | child mode | signals sent to its process group, in order |
# exit status | sandbox and runtime dir gone or kept.
cases_table=(
  "a set -e failure after the chmod removes the sandbox|abort||1|gone"
  "one TERM removes the sandbox|wait|TERM|143|gone"
  "one HUP removes the sandbox|wait|HUP|129|gone"
  "one INT removes the sandbox|wait|INT|130|gone"
  "a second TERM during the teardown does not cut it|wait|TERM TERM|143|gone"
  "a HUP after a TERM does not cut the teardown|wait|TERM HUP|143|gone"
  "a kept sandbox is removable with plain rm -rf|keep||1|kept"
  "a refused source tree still releases owned sandbox and process groups|refused||1|gone"
  "recorder finalization follows producers and retains evidence before removal|recorder||1|gone"
  "recorder failure retains incomplete evidence without changing original exit|recorder-failed||1|gone"
  "failed close retains an explicit error and original exit|recorder-close-failed||1|gone"
)
for row in "${cases_table[@]}"; do
  if run_case "$teardown" "$row"; then ok "${row%%|*}"; else fail "${row%%|*}: ${problems[*]}"; fi
done

# mutate OLD NEW OUT: a copy of the teardown with OLD, which must occur
# once, replaced by NEW.
mutate() {
  local text rest count
  text="$(<"$teardown")"
  rest="${text//"$1"/}"
  count=$(( (${#text} - ${#rest}) / ${#1} ))
  if [[ $count -ne 1 ]]; then
    printf '        mutation matched %s times: %s\n' "$count" "$1"
    return 1
  fi
  printf '%s\n' "${text/"$1"/"$2"}" >"$3"
  cmp -s -- "$teardown" "$3" && { printf '        mutation left the file unchanged: %s\n' "$1"; return 1; }
  return 0
}

# Rows: label | text | replacement | the case label that must go red | the
# problem that case must report | the teardown failure line it must print,
# CASE standing for its directory, or empty for any. A field holds no `|`,
# the separator.
controls=(
  "the owner bits are not restored|chmod -R u+rwX -- \"\$sandbox\"|true|a set -e failure after the chmod removes the sandbox|sandbox=left|qml-smoke: cleanup=rm-failed path=CASE/sandbox"
  "the signals are not ignored|trap '' TERM INT HUP|:|a second TERM during the teardown does not cut it|sandbox=left|"
  "the recorder finalizer is skipped|if ! display_record_finish \"\$original_status\"; then|if ! true; then|recorder finalization follows producers and retains evidence before removal|recorder-evidence=missing|"
  "the recorder closes after producer TERM|if ! display_record_close \"\$original_status\" cleanup; then|if ! true; then|recorder finalization follows producers and retains evidence before removal|recorder-close-order=wrong|"
)
for i in "${!controls[@]}"; do
  IFS='|' read -r label old new target want want_err <<<"${controls[i]}"
  mutant="$tmp/mutant-$i.sh"
  if ! mutate "$old" "$new" "$mutant"; then fail "control: $label"; continue; fi
  row=""
  for candidate in "${cases_table[@]}"; do [[ ${candidate%%|*} == "$target" ]] && row="$candidate"; done
  if [[ -z $row ]]; then fail "control: $label names no case: $target"; continue; fi
  if run_case "$mutant" "$row"; then
    fail "control: $label left '$target' green"
  elif [[ " ${problems[*]} " != *" $want "* ]]; then
    fail "control: $label went red without $want: ${problems[*]}"
  elif [[ -n $want_err && $keyed_err != "${want_err//CASE/$case_dir}" ]]; then
    fail "control: $label printed [$keyed_err] as its teardown failure"
  else
    ok "control: $label"
  fi
done

# A sink that exited before the teardown: a child sources the teardown
# and harness.sh's own sink_alive, starts a stand-in sink that exits 7 or
# keeps running, and exits; its teardown prints the sink's exit with its
# status once, and nothing for a sink that still runs. The control drops
# the teardown's sink line.
if ! sink_alive_text="$(sed -n '/^sink_alive() {/,/^}/p' "$repo/scripts/smoke/harness.sh")" || [[ $sink_alive_text != "sink_alive() {"*$'\n}' ]]; then
  fail "sink exit: sink_alive is not extracted from harness.sh"
else
  printf '%s\n' "$sink_alive_text" >"$tmp/sink-alive.sh"
  cat >"$tmp/sink-child.sh" <<'SH'
set -euo pipefail
teardown="$1" functions="$2" case_dir="$3" mode="$4"
sandbox="" rt_dir="" pgids=() keep=false
source "$teardown"
source "$functions"
sandbox="$case_dir/sandbox" rt_dir="$case_dir/runtime"
mkdir -- "$sandbox" "$rt_dir"
echo "sink: listening" >"$sandbox/sink.log"
# Each stand-in leads its own process group, as spawn's setsid gives the
# real sink, so the teardown's group signals reach it; the running one
# says it is ready once its trap is set, and marks the TERM it gets.
if [[ $mode == exited ]]; then
  setsid sh -c 'echo "sink: refused: stand-in" >>"$1"; exit 7' _ "$sandbox/sink.log" >/dev/null 2>&1 &
else
  setsid sh -c 'trap "echo termed >\"\$1\"; exit 0" TERM; : >"$1.ready"; while :; do sleep 0.1; done' _ "$case_dir/termed" >/dev/null 2>&1 &
fi
sink_pid=$! sink_exit=""
pgids+=("$sink_pid")
if [[ $mode == exited ]]; then
  while kill -0 "$sink_pid" 2>/dev/null; do sleep 0.05; done
else
  while [[ ! -e $case_dir/termed.ready ]]; do sleep 0.05; done
fi
exit 0
SH
  # sink_case TEARDOWN MODE: the child's stdout; sink_dir is the case's
  # directory, made before the call.
  sink_case() {
    timeout -k 2 20 env -i PATH="$PATH" "$BASH" "$tmp/sink-child.sh" "$1" "$tmp/sink-alive.sh" "$sink_dir" "$2" 2>/dev/null
  }
  want_sink='qml-smoke: sink=exited status=7 last=[sink: refused: stand-in]'
  sink_dir="$(mktemp -d "$tmp/sink-case.XXXXXX")"
  got="$(sink_case "$teardown" exited)" || got="exit=$?"
  if [[ $got == "$want_sink" ]]; then ok "the teardown prints a sink that exited with its status"; else fail "the teardown prints a sink that exited with its status: got [$got]"; fi
  sink_dir="$(mktemp -d "$tmp/sink-case.XXXXXX")"
  started=$EPOCHREALTIME
  got="$(sink_case "$teardown" running)" || got="exit=$?"
  elapsed_ms=$(( (${EPOCHREALTIME/./} - ${started/./}) / 1000 ))
  if [[ -z $got ]]; then ok "the teardown prints nothing for a sink that runs"; else fail "the teardown prints nothing for a sink that runs: got [$got]"; fi
  # The stand-in took the teardown's TERM and the child's stdout closed
  # with it, well inside the stand-in's own life.
  if [[ -e $sink_dir/termed && $elapsed_ms -lt 10000 ]]; then
    ok "the teardown's group signal ends a running sink"
  else
    fail "the teardown's group signal ends a running sink: termed=$([[ -e $sink_dir/termed ]] && echo yes || echo no) elapsed_ms=$elapsed_ms"
  fi
  sink_line="$(grep -F 'qml-smoke: %s' -- "$teardown")" || sink_line=""
  if [[ -n $sink_line ]] && mutate "$sink_line" '    :' "$tmp/mutant-sink.sh"; then
    sink_dir="$(mktemp -d "$tmp/sink-case.XXXXXX")"
    got="$(sink_case "$tmp/mutant-sink.sh" exited)" || got="exit=$?"
    if [[ $got == "$want_sink" ]]; then fail "control: a teardown without the sink line left the sink case green"; else ok "control: a teardown without the sink line"; fi
  else
    fail "control: a teardown without the sink line"
  fi
fi

if [[ $failures -gt 0 ]]; then
  echo "test-smoke-teardown: failed=$failures"
  exit 1
fi
echo "test-smoke-teardown: ok"
