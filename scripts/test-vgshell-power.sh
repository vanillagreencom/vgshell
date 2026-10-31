#!/usr/bin/env bash
# Controls for `vgshell power`, bin/vgshell-power: the ask on vgs.jarvis's
# `power` handler of the shell the instance lock names, and the systemctl
# call that follows unless the answer is `held`. A stub qs, first on the
# suite's PATH, records the argv of its call and answers STUB_REPLY with
# STUB_STATUS; STUB_CLIENT_FAILURE answers that line and exit 0, as
# Quickshell 0.3.1's client answers a failure of its own, such as a
# disabled vgs.jarvis. A stub systemctl, first on PATH too, records its
# argv and restarts nothing; the suite refuses to run any row while
# systemctl resolves anywhere else. The instance lock names this suite's
# own pid, a live process that is no shell.
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
chmod 755 "$tmp/loginctl"
resolved="$("${base_env[@]}" bash -c 'command -v systemctl')"
if [[ $resolved != "$tmp/systemctl" ]]; then
  echo "test-vgshell-power: refused: systemctl=$resolved want=$tmp/systemctl"
  exit 1
fi

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
power_row "another verb is refused" 2 "vgshell: refused: power=halt" "" halt
power_row "no verb is refused" 2 "vgshell: refused: power=missing" ""
power_row "a second argument is refused" 2 "vgshell: refused: argument=now" "" reboot now

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

rows_done test-vgshell-power
