# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034,SC2016
# `vgshell start` launches the runner through nested Hyprland, not through
# the row's process tree, waits for the guarded shell, writes run.log and
# shows the first-start welcome. A second start sees the guarded shell and
# dispatches nothing. Controls use copies of the tree: one runs the runner
# in the foreground and does not return inside the ceiling; one skips the
# running-shell check and does not answer `ok running` on the second start.
# inputs: bin/vgshell shell/Core/Notices.qml shell/Core/PluginLogic.js
set -euo pipefail

# Ceiling on latency_start_ms, the wall time from `vgshell start` to its
# `ok pid=<pid>` reply, read once per start with no polling of its own;
# start itself polls the lock file and the shell every 100 ms, so the
# reading carries at most 100 ms of polling. Twice the highest of six
# readings, two per run of `scripts/qml-smoke.sh --rows start` on host
# cachy on 2026-10-06 at load average 16 to 17: 273 to 353 ms.
start_budget_ms=706

start_log="$home/.local/state/vgshell/run.log"
welcome_seen="$home/.local/state/vgshell/welcome-seen"
start_env=("${sandbox_env[@]}" "${shell_start_words[@]}" WAYLAND_DISPLAY="$nested_socket"
  DBUS_SESSION_BUS_ADDRESS="unix:path=$rt_dir/bus" DBUS_SYSTEM_BUS_ADDRESS="unix:path=$rt_dir/system-bus")
parent_of() { awk '$1 == "PPid:" { print $2 }' "/proc/$1/status"; } # PID
start_reply=""
start_status=0
start_err="$sandbox/start.err"

vgshell_start_no_signature() { # TREE
  set +e
  start_reply="$("${start_env[@]}" "$1/bin/vgshell" start 2>"$start_err")"
  start_status=$?
  set -e
  printf '%s\n' "$start_reply"
}
start_ok() { # TREE
  local out
  out="$(vgshell_start_no_signature "$1")"
  [[ $start_status == 0 && $out =~ ^ok\ pid=[0-9]+$ ]] && echo ok || echo "exit=$start_status out=$out err=$(cat "$start_err" 2>/dev/null || :)"
}
start_and_check() { # LABEL TREE
  local label="$1" tree="$2" started elapsed
  started="$(now_ms)"
  vgshell_start_no_signature "$tree" >/dev/null
  elapsed=$(( $(now_ms) - started ))
  if [[ $start_status == 0 && $start_reply =~ ^ok\ pid=[0-9]+$ && $elapsed -le $start_budget_ms ]]; then
    printf '  latency_start_ms=%d ceiling_ms=%d\n' "$elapsed" "$start_budget_ms"
    ok "$label"
  else
    printf '  latency_start_ms=%s ceiling_ms=%d\n' "$elapsed" "$start_budget_ms"
    fail "$label: exit=$start_status reply=$start_reply err=$(cat "$start_err" 2>/dev/null || :)"
  fi
}
running_start() { # TREE
  local out
  out="$(vgshell_start_no_signature "$1")"
  [[ $start_status == 0 ]] && printf '%s\n' "$out" || printf 'exit=%s out=%s err=%s\n' "$start_status" "$out" "$(cat "$start_err" 2>/dev/null || :)"
}
runner_count() {
  python3 - "$compositor_pid" "$repo/bin/vgshell" <<'PY'
import os, sys
parent, exe = sys.argv[1:]
count = 0
for pid in filter(str.isdigit, os.listdir("/proc")):
    try:
        stat = open(f"/proc/{pid}/stat").read()
        ppid = stat[stat.rindex(")") + 2:].split()[1]
        cmd = open(f"/proc/{pid}/cmdline", "rb").read().split(b"\0")
    except OSError:
        continue
    words = [part.decode(errors="ignore") for part in cmd if part]
    if ppid == parent and exe in words and "run" in words:
        count += 1
print(count)
PY
}
welcome_record() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["notices"]["welcome"], sort_keys=True))'; }
welcome_state() { welcome_record | py_reply 'import json,sys; print(json.load(sys.stdin)["state"])'; }
consent_title() { ipc shell lent | py_reply 'import json,sys; c=json.load(sys.stdin)["notices"]["consent"]; print(None if c is None else c["title"])'; }
file_exists() { [[ -f $1 ]] && echo true || echo false; }

welcome_found=absent
[[ -e $welcome_seen ]] && welcome_found=present
notice_found="$(consent_title)"
stop_shell || :
rm -f -- "${welcome_seen:?}" "$start_log"
start_and_check "start returns after the guarded shell answers" "$repo"
if [[ $start_reply =~ ^ok\ pid=([0-9]+)$ ]]; then
  shell_qs_pid="${BASH_REMATCH[1]}"
  shell_pid="$(parent_of "$shell_qs_pid")"
  shell_tree="$repo"
  shell_log="$start_log"
  shell_answers "$repo" "$start_log" || :
  expect "the runner is the shell's parent" "$shell_pid" parent_of "$shell_qs_pid"
  expect "the runner is Hyprland's child" "$compositor_pid" parent_of "$shell_pid"
fi
expect "start writes the run log" true file_exists "$start_log"
expect_poll "start shows the welcome state as unseen" unseen welcome_state
expect_poll "start shows the welcome consent title" "Welcome to VGS" consent_title
expect "one runner belongs to Hyprland after start" 1 runner_count
second="$(running_start "$repo")"
if [[ $second == "ok running pid=$shell_qs_pid" ]]; then ok "a second start returns the running shell"; else fail "a second start answered $second"; fi
expect "the second start dispatches no second runner" 1 runner_count

if copy_tree foreground && edit_tree foreground bin/vgshell \
    'dispatch_reply="$(hyprctl dispatch "$request" 2>&1)"' \
    'dispatch_reply="$("$self" run 2>&1)"'; then
  stop_shell || :
  set +e
  control_out="$(timeout "$(( (start_budget_ms + 999) / 1000 ))" "${start_env[@]}" "$sandbox/tree-foreground/bin/vgshell" start 2>&1)"
  control_status=$?
  set -e
  if [[ $control_status == 124 ]]; then ok "control: a foreground start misses the return ceiling"; else fail "control: foreground start returned exit=$control_status out=$control_out"; fi
fi

if copy_tree skip-running && edit_tree skip-running bin/vgshell \
    'if pid="$(shell_pid 2>/dev/null)"; then' \
    'if false && pid="$(shell_pid 2>/dev/null)"; then'; then
  stop_shell || :
  start_and_check "control setup starts the skip-running copy" "$sandbox/tree-skip-running"
  if [[ $start_reply =~ ^ok\ pid=([0-9]+)$ ]]; then
    shell_qs_pid="${BASH_REMATCH[1]}"
    shell_pid="$(parent_of "$shell_qs_pid")"
    shell_tree="$sandbox/tree-skip-running"
    shell_log="$home/.local/state/vgshell/run.log"
    shell_answers "$sandbox/tree-skip-running" "$shell_log" || :
  fi
  skipped="$(running_start "$sandbox/tree-skip-running")"
  if [[ $skipped != ok\ running* ]]; then ok "control: skipping the running check does not answer ok running"; else fail "control: skipping the running check answered $skipped"; fi
fi

# The welcome-seen marker as the row found it, so the next row meets the
# same notice.
rm -f -- "${welcome_seen:?}"
[[ $welcome_found == absent ]] || : >"$welcome_seen"
stop_shell || :
start_shell "$repo" "$sandbox/start-qs.log" || fail "the start row leaves a harness-tracked shell"
expect_poll "the restored shell shows the notice the row found" "$notice_found" consent_title
