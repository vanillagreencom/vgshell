#!/usr/bin/env bash
# Controls for `vgshell lock`, bin/vgshell-lock: the call it makes on vgs.lock's
# IPC target of the shell the instance lock names, its answer taken from
# qs's last stdout line, the wait for the compositor's answer in the
# plugin's status reply, and each refusal. A stub qs, first on the suite's
# PATH, records the argv of its lock call and answers it from STUB_REPLY
# and STUB_STATUS after STUB_NOISE; it answers the first status call from
# STUB_BEFORE and every later one from STUB_AFTER. STUB_CLIENT_FAILURE
# answers every call with that line and exit 0, as Quickshell 0.3.1's
# client answers a failure of its own. The instance lock names
# this suite's own pid, a live process that is no shell. Expected values
# are the ones each row planted. Startup fixtures advance on acknowledged
# target calls; the sleep stand-in records requested delays without waiting.
set -euo pipefail

# shellcheck source=scripts/vgshell-rows.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"

cat >"$tmp/qs" <<'SH'
#!/usr/bin/env bash
[[ -z ${STUB_NOISE:-} ]] || printf '%s\n' "$STUB_NOISE"
if [[ ${5:-} == shell ]]; then
  [[ ${STUB_SHELL_STATUS:-0} == 0 ]] || exit "$STUB_SHELL_STATUS"
  if [[ ${6:-} == listPlugins ]]; then
    listing='{"scanned":true,"config":{"ready":true},"plugins":[{"id":"vgs.lock","enabled":true}]}'
    if [[ ${STUB_PAGED:-0} == 1 ]]; then printf '%s\n' 'paged=7'
    else printf '%s\n' "${STUB_LISTING:-$listing}"; fi
  elif [[ ${6:-} == page ]]; then
    printf '1 %s\n' '{"scanned":true,"config":{"ready":true},"plugins":[{"id":"vgs.lock","enabled":true}]}'
  else
    count=0; [[ ! -e $STUB_ARGS.loading ]] || read -r count <"$STUB_ARGS.loading"
    if ((count < ${STUB_LOADING:-20})); then printf '%s\n' '{"service":[]}'
    else printf '%s\n' '{"service":[{"id":"vgs.lock"}]}'; fi
  fi
  exit 0
fi
if [[ -n ${STUB_STARTUP:-} && ( $STUB_STARTUP != lock || ${7:-} == lock ) ]]; then
  count=0; [[ ! -e $STUB_ARGS.loading ]] || read -r count <"$STUB_ARGS.loading"
  if ((count < ${STUB_LOADING:-20})); then
    printf '%s\n' "$((count + 1))" >"$STUB_ARGS.loading"
    case $STUB_STARTUP in
      target) printf '%s\n' 'Target not found.' ;;
      stderr) printf '%s\n' 'Target not found.' >&2 ;;
      *) printf 'unknown: %s\n' "${7:-}" ;;
    esac
    exit 0
  fi
fi
if [[ -n ${STUB_CLIENT_FAILURE:-} ]]; then printf '%s\n' "$STUB_CLIENT_FAILURE" >&2; exit 0; fi
if [[ ${7:-} == status ]]; then
  [[ ${STUB_STATUS:-0} == 0 ]] || exit "$STUB_STATUS"
  before='{"secure":false,"refusals":0}' after='{"secure":true,"refusals":0}'
  [[ -z ${STUB_BEFORE:-} ]] || before="$STUB_BEFORE"
  [[ -z ${STUB_AFTER:-} ]] || after="$STUB_AFTER"
  if [[ -e ${STUB_ARGS:?}.status ]]; then printf '%s\n' "$after"; else : >"$STUB_ARGS.status"; printf '%s\n' "$before"; fi
  exit 0
fi
printf '%s\n' "$*" >"$STUB_ARGS"
printf '%s\n' "${STUB_REPLY:-ok}"
exit "${STUB_STATUS:-0}"
SH
chmod 755 "$tmp/qs"
cat >"$tmp/sleep" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"${STUB_ARGS:?}.sleep"
SH
chmod 755 "$tmp/sleep"

rt="$tmp/rt-lock"
mkdir -p "$rt"
printf '%s\n' "$$" >"$rt/vgshell.lock"
cfg="$tmp/cfg-lock"

# lock_row NAME WANT_EXIT WANT_STDOUT WANT_STDERR [NAME=VALUE...]
lock_row() {
  local name="$1" want_exit="$2" want_out="$3" want_err="$4"
  shift 4
  rm -f -- "${tmp:?}/args.status" "$tmp/args.loading" "$tmp/args.sleep"
  inst_env=("$@")
  inst "$name" "$cfg" "${RT:-$rt}" "$want_exit" "$want_out" "$want_err" lock
  inst_env=()
}

rm -f -- "${tmp:?}/args"
lock_row "the plugin's ok is the answer" 0 ok ""
check "the call reaches vgs.lock's lock function in the shell the instance lock names" test "$(<"$tmp/args")" == "ipc --pid $$ call vgs.lock invoke lock "
lock_row "qs's log lines ahead of the reply are skipped" 0 ok "" STUB_NOISE="INFO: log line"
lock_row "a plugin refusal is the command's" 1 "" "vgshell: refused: lock=not-ready" STUB_REPLY="refused: lock=not-ready"
lock_row "a core refusal keeps its key" 1 "" "vgshell: refused: lock-content=not-a-component" STUB_REPLY="refused: lock-content=not-a-component"
lock_row "a failed qs call is no answer" 1 "" "vgshell: refused: lock=no-answer pid=$$" STUB_STATUS=1
for startup in target stderr status lock; do
  lock_row "a loading $startup registers then locks" 0 ok "" STUB_STARTUP="$startup" STUB_LOADING=2
done
lock_row "a built service retries immediately" 0 ok "" STUB_STARTUP=target STUB_LOADING=1
check "a built service takes no startup delay" test ! -e "$tmp/args.sleep"
lock_row "a paged registry reply still permits startup" 0 ok "" STUB_STARTUP=target STUB_LOADING=2 STUB_PAGED=1
lock_row "a missing target after the wait is starting" 1 "" "vgshell: refused: lock=starting pid=$$" STUB_STARTUP=target
readarray -t delays <"$tmp/args.sleep"
check "startup delays are bounded" test "${#delays[@]}" -le 20
lock_row "a disabled lock plugin refuses" 1 "" "vgshell: refused: lock=disabled pid=$$" STUB_STARTUP=target STUB_LISTING='{"scanned":true,"config":{"ready":true},"plugins":[{"id":"vgs.lock","enabled":false}]}'
check "a disabled lock plugin takes no startup delay" test ! -e "$tmp/args.sleep"
lock_row "an unfinished scan still waits" 1 "" "vgshell: refused: lock=starting pid=$$" STUB_STARTUP=target STUB_LISTING='{"scanned":false,"config":{"ready":false},"plugins":[]}'
lock_row "a failed readiness call is no answer" 1 "" "vgshell: refused: lock=no-answer pid=$$" STUB_STARTUP=target STUB_SHELL_STATUS=1
lock_row "a coloured client error is no answer" 1 "" "vgshell: refused: lock=no-answer pid=$$" STUB_CLIENT_FAILURE=$'\e[31mERROR quickshell.ipc: no instance\e[0m'
lock_row "a lock the compositor refused is refused" 1 "" "vgshell: refused: lock=refused-by-compositor" STUB_AFTER='{"secure":false,"refusals":1}'
lock_row "a lock never confirmed is refused" 1 "" "vgshell: refused: lock=unconfirmed" STUB_AFTER='{"secure":false,"refusals":0}'
lock_row "a lock already confirmed is ok" 0 ok "" STUB_BEFORE='{"secure":true,"refusals":2}' STUB_AFTER='{"secure":true,"refusals":2}'
RT="$tmp/rt-none" lock_row "no shell is exit 69" 69 "" "vgshell: refused: shell=not-running lock=$tmp/rt-none/vgshell.lock"
inst "an argument is a bad invocation" "$cfg" "$rt" 2 "" "vgshell: refused: argument=--now" lock --now

# Must-fail controls, one per rule, each on a copy of bin/: the copy's row
# fails the expectation the real script meets.
control() { # NAME NEEDLE REPLACEMENT
  local tree_copy="$tmp/control-$1"
  mkdir -p "$tree_copy"
  cp -R -- "$repo/bin" "$tree_copy/"
  copy_with "$1" "$repo/bin/vgshell-lock" "$2" "$3"
  cp -- "$copy" "$tree_copy/bin/vgshell-lock"
  control_bin="$tree_copy/bin/vgshell"
}
# control_row NAME WANT_EXIT WANT_STDERR_FIRST [NAME=VALUE...]: passes when
# the copy misses the exit or the first stderr line.
control_row() {
  local name="$1" want_exit="$2" want_err="$3" status=0 err=""
  shift 3
  rm -f -- "${tmp:?}/args.status" "$tmp/args.loading" "$tmp/args.sleep"
  "${base_env[@]}" XDG_CONFIG_HOME="$cfg" XDG_RUNTIME_DIR="$rt" STUB_ARGS="$tmp/args" "$@" "$control_bin" lock </dev/null >/dev/null 2>"$tmp/control.err" || status=$?
  [[ -s $tmp/control.err ]] && IFS= read -r err <"$tmp/control.err"
  if [[ $status != "$want_exit" || $err != "$want_err" ]]; then ok "control: $name"; else fail "control: $name passed the row"; fi
}
control reply-ignored 'case "$reply" in' 'case ok in'
control_row "a copy that ignores the plugin's answer" 1 "vgshell: refused: lock=not-ready" STUB_REPLY="refused: lock=not-ready"
control no-answer-unkeyed 'no_answer() { refuse 1 "lock=no-answer pid=$pid"' 'no_answer() { : "lock=no-answer pid=$pid"'
control_row "a copy that reads a failed call as an empty answer" 1 "vgshell: refused: lock=no-answer pid=$$" STUB_STATUS=1
control no-wait '  if [[ $now == *'"'"'"secure":true'"'"'* ]]; then echo ok; exit 0; fi' '  echo ok; exit 0'
control_row "a copy that answers before the compositor does" 1 "vgshell: refused: lock=refused-by-compositor" STUB_AFTER='{"secure":false,"refusals":1}'
control refusal-ignored '    refuse 1 "lock=refused-by-compositor"' '    : "lock=refused-by-compositor"'
control_row "a copy that waits out a refusal" 1 "vgshell: refused: lock=refused-by-compositor" STUB_AFTER='{"secure":false,"refusals":1}'
control client-failure-unjudged '  [[ $status != 0 ]] || return 1' '  :'
control_row "a copy that reads a client failure as the plugin's answer" 1 "vgshell: refused: lock=no-answer pid=$$" STUB_CLIENT_FAILURE='ERROR quickshell.ipc: no instance'
control startup-ignored '    [[ $status == 0 || $status == 75 ]] || unanswered "$status"' '    [[ $status == 0 ]] || unanswered "$status"'
control_row "a copy that refuses the loading target" 0 "" STUB_STARTUP=target STUB_LOADING=2
control whole-output '  printf '"'"'%s\n'"'"' "$vgs_ipc_last_line"' '  printf '"'"'%s\n'"'"' "$out"'
control_row "a copy that reads qs's log as the answer" 0 "" STUB_NOISE="INFO: log line"

rows_done test-vgshell-lock
