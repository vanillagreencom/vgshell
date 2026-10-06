# The login screen, vgs.greeter (D101, docs/decisions/D101-greeter-host-and-greeter-system-step.md).
#
# Its service in the running shell: the harness starts it disabled, and the
# row enables it over the device fakes' system tree, where
# rows/system-steps.sh's stand-in systemctl answers greetd.service's load
# state, so the core's step probe reaches no host unit. The row reads the
# lending record name vgs.greeter the one holder of `system` and lend it
# the greeter step alone, and the `greeter` status its service publishes
# from that reading, then plants a masked greetd, rescans, and reads both
# follow it, its control: the status is the step's reading, not a constant.
# Disabling the plugin drops its status record and its hold.
#
# The core's greeter host: the row starts a second qs on shell/greeter.qml
# with VGS_GREETER_VIEW naming the plugin's view, XDG_DATA_DIRS naming two
# fixture directories under scripts/smoke/fixtures/greeter, a theme
# directory holding the fixture theme copy, `theme.json` and a
# `background` image, as the service writes it, an empty state directory,
# and no greetd socket. It reads the host's view line, greetd unavailable,
# the theme and the background the view loaded from the copy, the three
# sessions the view lists of the eight fixture files (a Hidden file
# deleting the later directory's file of the same name, a NoDisplay entry,
# a TryExec not found and a file with no Exec left out, the last refused by
# path), the X entry available only while startx is on the sandbox's PATH,
# the uwsm-managed Hyprland session preselected on first use, and its
# surface on the overlay layer, each from the lines the host and the view
# print for the journal. It then starts the host again over a state
# directory whose `greeter.json` names the caller as the last user and the
# plain Hyprland entry as their session, as the view writes it before a
# launch, and reads that entry preselected: the next boot's choice. That
# start's GREETD_SOCK names fixtures/greeter/greetd.py, a stand-in greetd
# started before it, which answers greetd's protocol with one password and
# logs each request. The row types a wrong password and reads greetd's
# auth_error as an auth failure and the client's cancel; presses Enter
# with the field empty, which starts a login that waits at the hidden
# prompt, and Escape, which cancels it; then types the right password and
# reads the chosen session's command and environment reach start_session
# and the host end on its own, exit 0, with no surface left. The control
# starts the host again with a view reached through `..` outside the
# plugin tree: it prints the refusal, builds no surface and exits 1. No
# greetd, PAM or sudo is reached; rows/auth-sentinel.sh reads the log
# empty. The host's reads wait up to 20 s, 100 reads 0.2 s apart, for a qs
# start with no compiled QML cache; every other reading is expect_poll's:
# 25 reads 0.2 s apart.
# inputs: shell/plugins/vgs.greeter/* shell/greeter.qml shell/Core/SystemSteps.qml bin/vgshell-system config/system/greeter/* scripts/smoke/fixtures/greeter/* scripts/smoke/rows/system-steps.sh scripts/smoke/fixtures/devices/* scripts/smoke/rows/device-fakes.sh
set -euo pipefail
greeter_status() { ipc smoke statusValues vgs.greeter | py_reply 'import json,sys; v=json.load(sys.stdin).get("greeter"); print(json.dumps(v if v is None else [v["tone"], v["text"], v.get("action")]))'; }
greeter_lent() { ipc smoke readInstance service vgs.greeter steps | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin), sort_keys=True))'; }
greeter_holders() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["holders"].get("system", [])))'; }
greeter_record() { ipc shell lent | py_reply 'import json,sys; r=json.load(sys.stdin)["status"].get("vgs.greeter"); print(json.dumps(r if r is None else sorted(r["keys"])))'; }

if devices_ready greeter; then
  device_reply systemctl 0 not-found show --property=LoadState --value greetd.service
  expect "the greeter plugin starts disabled in the sandbox" False plugin_enabled vgs.greeter
  expect "enabling the greeter plugin is allowed" ok ipc shell setPluginEnabled vgs.greeter true
  expect_poll "the greeter service is built" True record_exists vgs.greeter
  expect_poll "vgs.greeter holds the system capability" '["vgs.greeter"]' greeter_holders
  expect_poll "the capability lends the greeter step alone" '{"greeter": {"reason": "greetd-missing", "state": "absent"}}' greeter_lent
  expect_poll "the service publishes the step's reading" '["info", "Needs greetd", false]' greeter_status
  expect_poll "the lending record holds the plugin's status keys" '["greeter", "theme"]' greeter_record
  # Control: the status follows the step's reading.
  device_reply systemctl 0 masked show --property=LoadState --value greetd.service
  rescan "a rescan with greetd masked answers ok"
  expect_poll "a masked greetd reads denied in the lending record" '{"greeter": {"reason": "unit-masked", "state": "denied"}}' greeter_lent
  expect_poll "the service publishes the masked reading" '["danger", "greetd is turned off by the system", false]' greeter_status
  expect "disabling the greeter plugin is allowed" ok ipc shell setPluginEnabled vgs.greeter false
  expect_poll "no plugin holds system once the greeter is disabled" '[]' greeter_holders
  expect_poll "disable dropped the greeter's status record" null greeter_record
  device_reply_clear systemctl
fi

# The host. greeter_lines TEXT LOG: how many lines of LOG end with TEXT;
# greeter_count TEXT LOG: how many hold it.
greeter_lines() { awk -v t="$1" 'length($0) >= length(t) && substr($0, length($0) - length(t) + 1) == t { n++ } END { print n + 0 }' "$2"; } # TEXT LOG
greeter_count() { # TEXT LOG
  local count status=0
  count="$(grep -c -F -e "$1" -- "$2")" || status=$?
  ((status <= 1)) || return 1
  printf '%s\n' "$count"
}
greeter_fixtures="$repo/scripts/smoke/fixtures/greeter"
greeter_view="$repo/shell/plugins/vgs.greeter/Greeter.qml"
greeter_log="$sandbox/greeter-host.log"
mkdir -p -- "$sandbox/greeter-theme/vgshell" "$sandbox/greeter-state/vgshell"
cp -- "$greeter_fixtures/theme/vgshell/theme.json" "$greeter_fixtures/theme/vgshell/background" "$sandbox/greeter-theme/vgshell/"
greeter_env=("${shell_env[@]}" XDG_DATA_DIRS="$greeter_fixtures/share-a:$greeter_fixtures/share-b"
  XDG_CONFIG_HOME="$sandbox/greeter-theme" XDG_STATE_HOME="$sandbox/greeter-state")
if "${shell_env[@]}" bash -c 'command -v startx' >/dev/null 2>&1; then xfce_state=available; else xfce_state=unavailable; fi
# greeter_wait TEXT LOG PID: whether one line of LOG ends with TEXT within
# 20 s, while PID runs.
greeter_wait() {
  local got=0
  for _ in $(seq 1 100); do
    got="$(greeter_lines "$1" "$2")" || got=unreadable
    [[ $got == 1 ]] && return 0
    kill -0 "$3" 2>/dev/null || break
    sleep 0.2
  done
  return 1
}
# greeter_ended PID: whether PID ends within 20 s.
greeter_ended() {
  for _ in $(seq 1 100); do
    kill -0 "$1" 2>/dev/null || return 0
    sleep 0.2
  done
  return 1
}
# greeter_stop PID: ends that host and reads its surfaces gone.
greeter_stop() {
  kill -TERM "$1" 2>/dev/null || fail "stopping the greeter host pid $1 failed"
  wait "$1" 2>/dev/null || true
  expect_poll "the stopped host leaves no surface" 0 layer_count vgs:greeter
}
spawn "$greeter_log" "${greeter_env[@]}" VGS_GREETER_VIEW="$greeter_view" qs -p "$repo/shell/greeter.qml"
greeter_pid="$spawn_pid"
if greeter_wait "greeter: sessions=3 preselected=wayland-sessions/hyprland-uwsm.desktop" "$greeter_log" "$greeter_pid"; then ok "the greeter host lists the sessions and preselects the uwsm-managed Hyprland session"; else fail "the greeter host's preselection line, log: $(tail -n 20 -- "$greeter_log")"; fi
expect "the host accepts the plugin's view" 1 greeter_count "/shell/plugins/vgs.greeter/Greeter.qml screens=" "$greeter_log"
greeter_screens="$(sed -n 's|.*/shell/plugins/vgs\.greeter/Greeter\.qml screens=\([0-9][0-9]*\)$|\1|p' -- "$greeter_log")" || greeter_screens=unreadable
expect "the view finds no greetd socket" 1 greeter_lines "greeter: greetd=unavailable" "$greeter_log"
expect_poll "the view loads the theme copy" 1 greeter_lines "greeter: theme=greeter-smoke file=loaded" "$greeter_log"
expect_poll "the view loads the background copy" 1 greeter_lines "greeter: background=ready path=$sandbox/greeter-theme/vgshell/background" "$greeter_log"
expect "the view lists the uwsm-managed Hyprland entry" 1 greeter_lines "greeter: session id=wayland-sessions/hyprland-uwsm.desktop type=wayland state=available name=Hyprland (uwsm-managed)" "$greeter_log"
expect "the view lists the plain Hyprland entry" 1 greeter_lines "greeter: session id=wayland-sessions/hyprland.desktop type=wayland state=available name=Hyprland" "$greeter_log"
expect "the view lists the X entry, available only with startx" 1 greeter_lines "greeter: session id=xsessions/xfce.desktop type=x11 state=$xfce_state name=Xfce Session" "$greeter_log"
expect "the view lists no other session" 3 greeter_count "greeter: session id=" "$greeter_log"
expect "the view refuses the file with no Exec by its path" 1 greeter_lines "greeter: refused: session=$greeter_fixtures/share-b/wayland-sessions/broken.desktop reason=exec-missing" "$greeter_log"
expect_poll "the host builds one surface per screen" "$greeter_screens" layer_count vgs:greeter
greeter_stop "$greeter_pid"

# The next boot: the memory the view writes before a launch.
greeter_user="$(id -un)"
printf '{"lastUser":"%s","sessions":{"%s":"wayland-sessions/hyprland.desktop"}}\n' "$greeter_user" "$greeter_user" >"$sandbox/greeter-state/vgshell/greeter.json"
greeter_again_log="$sandbox/greeter-host-again.log"
greetd_sock="$rt_dir/greetd.sock"
greetd_log="$sandbox/greetd.log"
spawn "$sandbox/greetd-stand-in.log" "${shell_env[@]}" python3 "$greeter_fixtures/greetd.py" "$greetd_sock" smoke-right "$greetd_log"
greetd_pid="$spawn_pid"
for _ in $(seq 1 50); do [[ -S $greetd_sock ]] && break; sleep 0.1; done
[[ -S $greetd_sock ]] || fail "the stand-in greetd's socket, log: $(tail -n 20 -- "$sandbox/greetd-stand-in.log")"
spawn "$greeter_again_log" "${greeter_env[@]}" GREETD_SOCK="$greetd_sock" VGS_GREETER_VIEW="$greeter_view" qs -p "$repo/shell/greeter.qml"
greeter_pid="$spawn_pid"
if greeter_wait "greeter: sessions=3 preselected=wayland-sessions/hyprland.desktop" "$greeter_again_log" "$greeter_pid"; then ok "the next start preselects the session the last user chose"; else fail "the greeter host's remembered preselection, log: $(tail -n 20 -- "$greeter_again_log")"; fi
expect "the view finds the stand-in greetd" 1 greeter_lines "greeter: greetd=available" "$greeter_again_log"
expect_poll "the next start builds one surface per screen" "$greeter_screens" layer_count vgs:greeter
# A wrong password: greetd's auth_error, then the client's own cancel.
type_keys smoke-wrong
type_keys -k Return
expect_poll "the wrong password reaches greetd" 1 greeter_lines "response=wrong" "$greetd_log"
expect_poll "the view reads greetd's auth_error as an auth failure" 1 greeter_lines "greeter: auth=failed" "$greeter_again_log"
# greetd answers each cancel with success, which the inactive client logs
# as unexpected; a success read after the next create_session would pass
# as that session's authentication, so each try waits for that line.
expect_poll "the client reads greetd's answer to its own cancel" 1 greeter_count "Received unexpected greetd response" "$greeter_again_log"
# Enter with the field empty starts a login that holds the hidden prompt
# for the person; Escape cancels it.
type_keys -k Return
expect_poll "an empty field starts a login" 2 greeter_lines "create_session username=$greeter_user" "$greetd_log"
type_keys -k Escape
expect_poll "Escape cancels the login, after the client's cancel on the failure" 2 greeter_lines "cancel_session" "$greetd_log"
expect_poll "the client reads greetd's answer to the Escape cancel" 2 greeter_count "Received unexpected greetd response" "$greeter_again_log"
expect "control: the empty field answered no prompt" 1 greeter_count "response=" "$greetd_log"
expect "control: a cancel is no auth failure" 1 greeter_lines "greeter: auth=failed" "$greeter_again_log"
# The right password, after both: the chosen session's command, then the
# host ends on its own, as Greetd.launch quits once greetd answers.
type_keys smoke-right
type_keys -k Return
expect_poll "the right password reaches greetd" 1 greeter_lines "response=right" "$greetd_log"
expect_poll "the view starts the chosen session" 1 greeter_lines 'start_session cmd=["/usr/bin/start-hyprland"] env=["XDG_SESSION_TYPE=wayland","XDG_SESSION_DESKTOP=Hyprland","XDG_CURRENT_DESKTOP=Hyprland"]' "$greetd_log"
expect "each try created one session" 3 greeter_lines "create_session username=$greeter_user" "$greetd_log"
greeter_exit=0
if greeter_ended "$greeter_pid"; then
  wait "$greeter_pid" 2>/dev/null || greeter_exit=$?
  if [[ $greeter_exit == 0 ]]; then ok "the host ends with exit 0 once the session starts"; else fail "the launched host exited $greeter_exit"; fi
  expect_poll "the launched host leaves no surface" 0 layer_count vgs:greeter
else
  fail "the greeter host still runs 20 s after the session started, log: $(tail -n 20 -- "$greeter_again_log")"
  greeter_stop "$greeter_pid"
fi
expect "control: the right password is no auth failure" 1 greeter_lines "greeter: auth=failed" "$greeter_again_log"
expect "control: the stand-in greetd refused no request" 0 greeter_count "refused" "$greetd_log"
kill -TERM "$greetd_pid" 2>/dev/null || fail "stopping the stand-in greetd pid $greetd_pid failed"
wait "$greetd_pid" 2>/dev/null || true

# Control: a view outside the plugin tree, reached through `..`.
outside="$repo/shell/plugins/../../scripts/smoke/fixtures/greeter/Outside.qml"
spawn "$sandbox/greeter-outside.log" "${greeter_env[@]}" VGS_GREETER_VIEW="$outside" qs -p "$repo/shell/greeter.qml"
outside_pid="$spawn_pid"
outside_exit=0
if ! greeter_ended "$outside_pid"; then
  fail "control: the greeter host with an outside view still runs after 20 s"
  kill -TERM "$outside_pid" 2>/dev/null || true
fi
wait "$outside_pid" 2>/dev/null || outside_exit=$?
expect "control: a view outside the plugin tree is refused" 1 greeter_lines "greeter: refused: view=outside path=$outside" "$sandbox/greeter-outside.log"
if [[ $outside_exit == 1 ]]; then ok "control: the refused host exits 1"; else fail "control: the refused host exited $outside_exit"; fi
expect "control: the refused host built no surface" 0 layer_count vgs:greeter
expect "control: the refused host listed no session" 0 greeter_count "greeter: sessions=" "$sandbox/greeter-outside.log"
