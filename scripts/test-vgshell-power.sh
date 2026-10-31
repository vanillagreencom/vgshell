#!/usr/bin/env bash
# Controls for `vgshell power`, bin/vgshell-power: the ask on vgs.jarvis's
# `power` handler of the shell the instance lock names, and the systemctl
# call that follows unless the answer is `held`; suspend and hibernate,
# which run systemctl with no ask; logout through loginctl; switch-user,
# which locks through the `vgshell lock` beside the route and then asks
# LightDM's seat over gdbus. A stub qs, first on the suite's PATH, records
# the argv of its call and answers STUB_REPLY with STUB_STATUS;
# STUB_CLIENT_FAILURE answers that line and exit 0, as Quickshell 0.3.1's
# client answers a failure of its own, such as a disabled vgs.jarvis. Stub
# systemctl, loginctl and gdbus, first on PATH too, record their argv and
# act on nothing; the suite refuses to run any row while one of them
# resolves anywhere else. The switch-user rows run a copy of the route
# beside a stand-in `vgshell` that records its argv and locks nothing. The
# instance lock names this suite's own pid, a live process that is no shell.
set -euo pipefail

# shellcheck source=scripts/vgshell-rows.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"

cat >"$tmp/qs" <<'SH'
#!/usr/bin/env bash
if [[ -n ${STUB_CLIENT_FAILURE:-} ]]; then printf '%s\n' "$STUB_CLIENT_FAILURE"; exit 0; fi
printf '%s\n' "$*" >"$STUB_ARGS"
printf '%s\n' "${STUB_REPLY:-ok}"
exit "${STUB_STATUS:-0}"
SH
cat >"$tmp/systemctl" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>$(printf %q "$tmp/systemctl.calls")
exit "\${STUB_SYSTEMCTL_STATUS:-0}"
SH
chmod 755 "$tmp/qs" "$tmp/systemctl"
cat >"$tmp/loginctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOGIN_CALLS"
case "$1" in
  show-user) printf '%s\n' "${STUB_DISPLAY-1}"; exit "${STUB_DISPLAY_STATUS:-0}" ;;
  terminate-session) exit "${STUB_TERMINATE_STATUS:-0}" ;;
  *) exit 99 ;;
esac
SH
# gdbus and the switch-user tree's stand-in `vgshell` record each argv
# word through %q into STUB_CALLS, one call a line, so word boundaries and
# call order both show; each prints what the real one prints on success,
# which the route must not pass on.
cat >"$tmp/gdbus" <<'SH'
#!/usr/bin/env bash
{ printf gdbus; printf ' %q' "$@"; echo; } >>"$STUB_CALLS"
if [[ ${STUB_GDBUS_STATUS:-0} != 0 ]]; then echo "Error: GDBus.Error:org.freedesktop.DBus.Error.Failed: stand-in" >&2; exit "$STUB_GDBUS_STATUS"; fi
echo '()'
SH
chmod 755 "$tmp/loginctl" "$tmp/gdbus"
for tool in systemctl loginctl gdbus; do
  resolved="$("${base_env[@]}" bash -c "command -v $tool")" || resolved=missing
  if [[ $resolved != "$tmp/$tool" ]]; then
    echo "test-vgshell-power: refused: $tool=$resolved want=$tmp/$tool"
    exit 1
  fi
done

rt="$tmp/rt-power"
mkdir -p "$rt"
printf '%s\n' "$$" >"$rt/vgshell.lock"
cfg="$tmp/cfg-power"

# The systemctl argv lines the last row recorded, one per line.
calls() { if [[ -f $tmp/systemctl.calls ]]; then cat -- "$tmp/systemctl.calls"; fi; }

# One row: `vgshell power ARGS` with NAME=VALUE words over the stubs'
# answers, then its exit, stderr's first line and systemctl's argv.
# power_row NAME WANT_EXIT WANT_STDERR WANT_SYSTEMCTL ARGS... [-- NAME=VALUE...]
power_row() {
  local name="$1" want_exit="$2" want_err="$3" want_calls="$4" args=()
  shift 4
  while [[ $# -gt 0 && $1 != -- ]]; do args+=("$1"); shift; done
  [[ $# -eq 0 ]] || shift
  rm -f -- "${tmp:?}/systemctl.calls" "${tmp:?}/args"
  inst_env=("$@")
  inst "$name" "$cfg" "${RT:-$rt}" "$want_exit" "" "$want_err" power "${args[@]}"
  inst_env=()
  check "$name: systemctl [$want_calls]" test "$(calls)" == "$want_calls"
}

power_row "held runs nothing" 0 "" "" reboot -- STUB_REPLY=held
check "the ask reaches vgs.jarvis's power handler in the shell the instance lock names" test "$(<"$tmp/args")" == "ipc --pid $$ call vgs.jarvis invoke power reboot"
power_row "proceed reboots" 0 "" reboot reboot -- STUB_REPLY=proceed
power_row "proceed shuts down" 0 "" poweroff poweroff -- STUB_REPLY=proceed
power_row "a refusal reboots" 0 "" reboot reboot -- STUB_REPLY="refused: power=reboot"
RT="$tmp/rt-none" power_row "no shell reboots" 0 "" reboot reboot
power_row "a disabled vgs.jarvis reboots" 0 "" reboot reboot -- STUB_CLIENT_FAILURE="Target not found."
power_row "a failed reboot reports systemctl's status" 5 "" reboot reboot -- STUB_REPLY=proceed STUB_SYSTEMCTL_STATUS=5
power_row "a failed shutdown reports systemctl's status" 5 "" poweroff poweroff -- STUB_REPLY=proceed STUB_SYSTEMCTL_STATUS=5
power_row "another verb is refused" 2 "vgshell: refused: power=halt" "" halt
power_row "no verb is refused" 2 "vgshell: refused: power=missing" ""
power_row "a second argument is refused" 2 "vgshell: refused: argument=now" "" reboot now
power_row "a second argument after suspend is refused" 2 "vgshell: refused: argument=now" "" suspend now
power_row "a second argument after switch-user is refused" 2 "vgshell: refused: argument=now" "" switch-user now -- XDG_SEAT_PATH=/org/freedesktop/DisplayManager/Seat0

# Suspend and hibernate run systemctl with no ask, even while a shell runs:
# the stub qs leaves no args file when nothing called it.
for verb in suspend hibernate; do
  power_row "$verb runs systemctl" 0 "" "$verb" "$verb" -- STUB_REPLY=held
  check "$verb asks no one" test ! -e "$tmp/args"
  power_row "a failed $verb reports systemctl's status" 6 "" "$verb" "$verb" -- STUB_SYSTEMCTL_STATUS=6
done

# switch-user: a copy of the route beside a stand-in `vgshell`, the route's
# `"$vgshell" lock`, which records its argv and answers STUB_LOCK_STATUS
# with the lock's keyed refusal line, as bin/vgshell-lock does.
switch_stand_in() { # DIR
  mkdir -p "$1"
  cat >"$1/vgshell" <<'SH'
#!/usr/bin/env bash
{ printf vgshell; printf ' %q' "$@"; echo; } >>"$STUB_CALLS"
if [[ ${STUB_LOCK_STATUS:-0} != 0 ]]; then echo "vgshell: refused: lock=unconfirmed" >&2; exit "$STUB_LOCK_STATUS"; fi
echo ok
SH
  chmod 755 "$1/vgshell"
}
switch_tree="$tmp/switch-tree/bin"
switch_stand_in "$switch_tree"
cp -- "$repo/bin/vgshell-power" "$switch_tree/vgshell-power"
seat=/org/freedesktop/DisplayManager/Seat0
greeter="gdbus call --system --dest org.freedesktop.DisplayManager --object-path $seat --method org.freedesktop.DisplayManager.Seat.SwitchToGreeter"
# switch_case POWER SEAT LOCK_STATUS GDBUS_STATUS WANT_STATUS WANT_ERR WANT_CALLS
# SEAT is UNSET, EMPTY or a path; WANT_CALLS joins calls with `;`, GREETER
# standing for the SwitchToGreeter call on $seat. True when the exit, the
# first stderr line, an empty stdout and the calls in order all match; the
# exit lands in switch_status.
switch_case() {
  local power="$1" seat_value="$2" lock_status="$3" gdbus_status="$4" want_status="$5" want_err="$6" want_calls="$7" err="" seat_env=()
  case $seat_value in
    UNSET) ;;
    EMPTY) seat_env=(XDG_SEAT_PATH=) ;;
    *) seat_env=(XDG_SEAT_PATH="$seat_value") ;;
  esac
  want_calls="${want_calls//GREETER/$greeter}"
  want_calls="${want_calls//;/$'\n'}"
  : >"$tmp/switch.calls"
  switch_status=0
  "${base_env[@]}" "${seat_env[@]}" STUB_CALLS="$tmp/switch.calls" STUB_LOCK_STATUS="$lock_status" STUB_GDBUS_STATUS="$gdbus_status" "$power" switch-user </dev/null >"$tmp/switch.out" 2>"$tmp/switch.err" || switch_status=$?
  [[ -s $tmp/switch.err ]] && IFS= read -r err <"$tmp/switch.err"
  [[ $switch_status == "$want_status" && $err == "$want_err" && ! -s $tmp/switch.out && $(<"$tmp/switch.calls") == "$want_calls" ]]
}
while IFS='|' read -r name seat_value lock_status gdbus_status want_status want_err want_calls; do
  [[ $seat_value == SEAT ]] && seat_value="$seat"
  if switch_case "$switch_tree/vgshell-power" "$seat_value" "$lock_status" "$gdbus_status" "$want_status" "$want_err" "$want_calls"; then ok "switch-user: $name"; else fail "switch-user: $name: exit=$switch_status calls=[$(<"$tmp/switch.calls")] stderr=[$(head -n1 "$tmp/switch.err")]"; fi
done <<'SWITCH_CASES'
locks, then shows the greeter on the session's seat|SEAT|0|0|0||vgshell lock;GREETER
no seat refuses and runs nothing|UNSET|0|0|1|vgshell: refused: power-seat=missing|
an empty seat refuses and runs nothing|EMPTY|0|0|1|vgshell: refused: power-seat=missing|
a failed lock reports its status and switches nothing|SEAT|69|0|69|vgshell: refused: lock=unconfirmed|vgshell lock
a failed switch reports gdbus's status after the lock|SEAT|0|4|4|Error: GDBus.Error:org.freedesktop.DBus.Error.Failed: stand-in|vgshell lock;GREETER
SWITCH_CASES

# Execute the shipped menu argv against an isolated logind command stand-in.
# Its Display is independent of this suite's absent login-session membership.
logout_case() {
  local menu="$1" display="$2" read_status="$3" terminate_status="$4" want_status="$5" want_calls="$6" actual=0 argv_text
  argv_text="$(node -e 'const m=require(process.argv[1]); for (const word of m.items["system.logout"].run) console.log(word)' "$menu")" || return
  local argv=()
  mapfile -t argv <<<"$argv_text"
  : >"$tmp/loginctl.calls"
  "${base_env[@]}" PATH="$tmp:$repo/bin:$base_path" STUB_DISPLAY="$display" STUB_DISPLAY_STATUS="$read_status" STUB_TERMINATE_STATUS="$terminate_status" STUB_LOGIN_CALLS="$tmp/loginctl.calls" "${argv[@]}" >"$tmp/logout.out" 2>"$tmp/logout.err" || actual=$?
  [[ $actual == "$want_status" && $(cat "$tmp/loginctl.calls") == "$want_calls" ]]
}
while IFS='|' read -r name display read_status terminate_status want_status suffix; do
  wanted="show-user $UID --property=Display --value"
  [[ -z $suffix ]] || wanted+=$'\n'"$suffix"
  if logout_case "$repo/shell/plugins/vgs.launcher/menu.json" "$display" "$read_status" "$terminate_status" "$want_status" "$wanted"; then ok "logout: $name"; else fail "logout: $name"; fi
done <<'LOGOUT_CASES'
graphical session ends|1|0|0|0|terminate-session 1
no graphical session refuses||0|0|1|
session lookup failure propagates||7|0|7|
termination failure propagates|1|0|9|9|terminate-session 1
LOGOUT_CASES
mkdir -p "$tmp/control-menu"
python3 - "$repo/shell/plugins/vgs.launcher/menu.json" "$tmp/control-menu/menu.json" <<'PY'
import json,sys
menu = json.load(open(sys.argv[1]))
menu["items"]["system.logout"]["run"] = ["sh", "-c", "exec loginctl terminate-session ''"]
with open(sys.argv[2], "w") as target:
    json.dump(menu, target)
PY
if logout_case "$tmp/control-menu/menu.json" 1 0 0 0 "show-user $UID --property=Display --value"$'\n'"terminate-session 1"; then
  fail "control: today's empty-session menu passed explicit graphical-session logout"
else
  ok "control: today's empty-session menu fails explicit graphical-session logout"
fi

# Must-fail control on a copy of bin/: a copy whose ask ends the script on a
# failed call runs no systemctl when no shell answers.
tree_copy="$tmp/control-unanswered"
mkdir -p "$tree_copy"
cp -R -- "$repo/bin" "$tree_copy/"
copy_with unanswered "$repo/bin/vgshell-power" ' 2>/dev/null)" || true' ' 2>/dev/null)"'
cp -- "$copy" "$tree_copy/bin/vgshell-power"
rm -f -- "${tmp:?}/systemctl.calls"
status=0
"${base_env[@]}" XDG_CONFIG_HOME="$cfg" XDG_RUNTIME_DIR="$tmp/rt-none" "$tree_copy/bin/vgshell" power reboot </dev/null >/dev/null 2>&1 || status=$?
if [[ $status != 0 || $(calls) != reboot ]]; then ok "control: a copy that stops on a failed ask restarts nothing with no shell"; else fail "control: the unanswered copy passed the no-shell row"; fi

# Must-fail control on a copy of bin/: a copy whose suspend falls through to
# the Jarvis ask asks the running shell.
tree_copy="$tmp/control-suspend-ask"
mkdir -p "$tree_copy"
cp -R -- "$repo/bin" "$tree_copy/"
copy_with suspend-ask "$repo/bin/vgshell-power" '  suspend|hibernate)' '  suspend-unmatched|hibernate-unmatched)'
cp -- "$copy" "$tree_copy/bin/vgshell-power"
rm -f -- "${tmp:?}/args" "${tmp:?}/systemctl.calls"
"${base_env[@]}" XDG_CONFIG_HOME="$cfg" XDG_RUNTIME_DIR="$rt" STUB_ARGS="$tmp/args" "$tree_copy/bin/vgshell" power suspend </dev/null >/dev/null 2>&1 || true
if [[ -e $tmp/args ]]; then ok "control: a copy whose suspend asks Jarvis fails the asks-no-one row"; else fail "control: the asking copy passed the suspend asks-no-one row"; fi

# Must-fail control on a copy of the route: a copy that switches without
# locking fails both the lock-then-greeter row and the failed-lock row.
control_tree="$tmp/control-unlocked/bin"
switch_stand_in "$control_tree"
copy_with unlocked "$repo/bin/vgshell-power" '"$vgshell" lock >/dev/null || exit "$?"' 'true || exit "$?"'
cp -- "$copy" "$control_tree/vgshell-power"
chmod 755 "$control_tree/vgshell-power"
if switch_case "$control_tree/vgshell-power" "$seat" 0 0 0 "" "vgshell lock;GREETER" \
  || switch_case "$control_tree/vgshell-power" "$seat" 69 0 69 "vgshell: refused: lock=unconfirmed" "vgshell lock"; then
  fail "control: a copy that switches without locking passed a lock-before-switch row"
else
  ok "control: a copy that switches without locking fails the lock-before-switch rows"
fi

rows_done test-vgshell-power
