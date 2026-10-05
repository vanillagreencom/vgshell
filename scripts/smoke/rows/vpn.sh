# The VPN section, vgs.vpn, over the device fakes' stand-ins
# (docs/architecture/validation-smoke-devices.md). No call reaches the
# host's tailscale, tailscaled, browser or sudo: `tailscale` and `xdg-open`
# are the recorded stand-ins in the shell's PATH directory, which answer
# `status --json` from the shapes in scripts/fixtures/vpn/, and the core's
# step probe reads the same `tailscale` through a link the row adds to the
# fakes' system tree and removes. The row stands over the tailscale
# stand-in with a wrapper that records each call through it and then, on
# the row's markers alone, holds one poll open, answers as a daemon that
# is off, refuses one `set` or one sign-in with the CLI's access-denied
# text, or prints a sign-in address and waits.
#
# Rows: the service publishes the fixture's state to the widget, the
# flyout and the pane; an unset operator offers Allow, which the keyboard
# presses and which hands the terminal `vgshell system apply
# tailscale-operator`; keys alone then toggle the connection, `down` and
# `up`, and choose an exit node, `set --exit-node=<dns name>`, with no peer
# id in any argv; a change that ends with a plain exit 1, a change the CLI
# denies and a sign-in it denies each leave a problem, the denied ones
# another than the plain one; the poll interval is 3 s while a view is open and the
# setting's 30 s while none is; every `status --json` call the stand-in
# records is one the service started; a held poll is killed 10 s after its
# start while a refresh arrives every second; sign-in hands the printed
# address to the xdg-open stand-in; a daemon that is off offers Enable.
# Controls, a copy of the plugin whose widget polls on its own, whose
# refresh restarts the watchdog and which does not know the access-denied
# text: the stand-in records a call the service did not start, the held
# poll outlives 20 s of refreshes, and the denied change leaves the plain
# one's problem.
#
# The held poll's wait is the service's own 10 s watchdog, read on the
# wall clock with a refresh every second; the row accepts 9 s to 20 s,
# since a refresh that moved the deadline would hold it past any bound.
# Every other reading is expect_poll's: 25 reads 0.2 s apart.
# inputs: shell/plugins/vgs.vpn/* shell/plugins/vgs.system/* scripts/fixtures/vpn/* scripts/smoke/fixtures/devices/* shell/Ui/layout/DeviceList.qml shell/Core/SystemSteps.qml shell/Core/PluginStatus.qml shell/Core/Capabilities.qml shell/Core/PluginLogic.js shell/Hosts/PaneHost.qml bin/vgshell-system bin/vgshell-tui scripts/smoke/rows/device-fakes.sh scripts/smoke/rows/start-order.sh
set -euo pipefail
devices_ready vpn || return 0
vpn_saved="$sandbox/vpn-shell-before.json"
cp -- "$home/.config/vgshell/shell.json" "$vpn_saved"
vpn_dir="$sandbox/vpn"
vpn_fixtures="$repo/scripts/fixtures/vpn"
vpn_login_url="https://login.fixture.example/a/smoke0123456789"
vpn_system_link="$devices_system_root/usr/bin/tailscale"
mkdir -p -- "$vpn_dir"
cp -- "$vpn_fixtures/service-off.txt" "$vpn_dir/service-off.text"
cp -- "$vpn_fixtures/access-denied.txt" "$vpn_dir/access-denied.text"
{
  printf '#!/usr/bin/env bash\ndir=%q saved=%q url=%q\n' "$vpn_dir" "$(sentinel_saved "$shim/tailscale")" "$vpn_login_url"
  cat <<'EOF'
if [[ "$*" == "status --json" ]]; then
  if mv -- "$dir/hang" "$dir/hang.taken" 2>/dev/null; then
    "$saved" "$@" >/dev/null 2>&1 || true
    echo $$ >"$dir/hang.pid.next" && mv -f -- "$dir/hang.pid.next" "$dir/hang.pid"
    exec sleep 60
  fi
  if [[ -e $dir/service-off ]]; then
    "$saved" "$@" >/dev/null 2>&1 || true
    cat -- "$dir/service-off.text" >&2
    exit 1
  fi
elif [[ "$*" == "login --timeout 0" ]]; then
  "$saved" "$@" >/dev/null 2>&1 || true
  if mv -- "$dir/login-denied" "$dir/login-denied.taken" 2>/dev/null; then
    cat -- "$dir/access-denied.text" >&2
    exit 1
  fi
  printf 'To authenticate, visit:\n\n\t%s\n\n' "$url" >&2
  for _ in $(seq 1 300); do
    if [[ -e $dir/login-release ]]; then exit 0; fi
    sleep 0.1
  done
  exit 1
elif [[ ${1:-} == set ]] && mv -- "$dir/denied" "$dir/denied.taken" 2>/dev/null; then
  "$saved" "$@" >/dev/null 2>&1 || true
  cat -- "$dir/access-denied.text" >&2
  exit 1
fi
exec "$saved" "$@"
EOF
} | sentinel_stand_over "$shim/tailscale"

vpn_use() { device_reply tailscale 0 "$(<"$vpn_fixtures/$1")" status --json; }
vpn_value() { ipc smoke statusValues vgs.vpn | py_reply 'import json,sys; v=json.load(sys.stdin).get("vpn"); print("unpublished" if v is None else json.dumps(v[sys.argv[1]]))' "$1"; }
vpn_setup() { ipc smoke statusValues vgs.vpn | py_reply 'import json,sys; v=json.load(sys.stdin).get("setup"); print("unpublished" if v is None else v.get("action", "none"))'; }
vpn_step() { ipc shell lent | py_reply 'import json,sys; s=json.load(sys.stdin)["system"]["steps"][sys.argv[1]]; print(s["state"] + " " + s["reason"])' "$1"; }
vpn_shown() { [[ $(ipc smoke instanceGeometry "$1" vgs.vpn) != absent ]] && echo shown || echo hidden; }
vpn_body() { ipc smoke readDescendant "$1" vgs.vpn VpnBody "$2"; }
vpn_body_state() { vpn_body "$1" vpn | py_reply 'import json,sys; print(json.load(sys.stdin)["state"])'; }
vpn_exit_rows() { vpn_body window exitRows | py_reply 'import json,sys; print(json.dumps([[r["text"], r["badge"]] for r in json.load(sys.stdin)]))'; }
vpn_placed() { bar_widget_ids | py_reply 'import json,sys; print(any("vgs.vpn" in ids for ids in json.load(sys.stdin)))'; }
vpn_interval() { ipc smoke readInstance service vgs.vpn pollInterval; }
vpn_polls() { ipc smoke readInstance service vgs.vpn pollsStarted; }
vpn_status_calls() { device_calls tailscale | py_reply 'import json,sys; print(sum(1 for c in json.load(sys.stdin) if c == ["status", "--json"]))'; }
vpn_call_count() { device_calls "$1" | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
# The commands that change Tailscale, from call N of the stand-in's record.
vpn_changes() { device_calls tailscale | py_reply 'import json,sys; print(json.dumps([c for c in json.load(sys.stdin)[int(sys.argv[1]):] if c[:1] not in (["status"], ["get"]) and c != ["switch", "--list"]]))' "$1"; }
vpn_argv_ids() { device_calls tailscale | py_reply 'import json,sys; print(sum(1 for c in json.load(sys.stdin)[int(sys.argv[1]):] for word in c if "nFIXTURE" in word))' "$1"; }
# The `status --json` calls the stand-in recorded since BEFORE against the
# polls the service started: `none` while the service is the only caller,
# `extra` for a call it did not start, `short` while a poll it started has
# not reached the stand-in.
vpn_surplus() { # BEFORE
  local polls calls
  polls="$(vpn_polls)" || return 1
  calls="$(vpn_status_calls)" || return 1
  if ((calls - $1 == polls)); then echo none; elif ((calls - $1 > polls)); then echo extra; else echo short; fi
}
vpn_account_ids() { ipc smoke statusValues vgs.vpn | py_reply 'import json,sys; print(json.dumps([a["id"] for a in json.load(sys.stdin)["vpn"]["accounts"]]))'; }
vpn_opens() { device_calls xdg-open | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)[int(sys.argv[1]):]))' "$1"; }
vpn_record() { ipc shell lent | py_reply 'import json,sys; print("held" if "vgs.vpn" in json.load(sys.stdin)["status"] else "absent")'; }
vpn_refresh() { ipc vgs.vpn invoke refresh ""; }
vpn_act() { ipc vgs.vpn invoke action "{\"kind\":\"$1\",\"id\":\"${2:-}\"}"; }
# Sends the action KIND and prints the problem its run left once FIELD
# reads IDLE again, `""` for none: `refused` for an action the service
# does not take, `unended` when the run has not ended after 10 s.
vpn_problem_after() { # KIND FIELD IDLE
  local now
  [[ $(vpn_act "$1") == ok ]] || { echo refused; return 0; }
  for _ in $(seq 1 50); do
    now="$(vpn_value "$2")" || return 1
    if [[ $now == "$3" ]]; then vpn_value problem; return; fi
    sleep 0.2
  done
  echo unended
}
# Fails one change with a plain exit 1, one change with the CLI's
# access-denied text and one sign-in with that text: `told-apart` when
# each change leaves a problem, the two differ and the sign-in leaves the
# denied change's; `same` when the two changes leave one problem.
vpn_failures() {
  local plain denied login
  plain="$(vpn_problem_after exit-node action '""')" || return 1
  : >"$vpn_dir/denied"
  denied="$(vpn_problem_after exit-node action '""')" || return 1
  : >"$vpn_dir/login-denied"
  login="$(vpn_problem_after login login '"idle"')" || return 1
  if [[ $plain != \"?*\" || $denied != \"?*\" ]]; then echo "unset plain=$plain denied=$denied"
  elif [[ $plain == "$denied" ]]; then echo same
  elif [[ $login != "$denied" ]]; then echo "login=$login denied=$denied"
  else echo told-apart
  fi
}
# `grew` once the service has started two more polls, within 10 s.
vpn_polls_grow() {
  local first now
  first="$(vpn_polls)" || return 1
  for _ in $(seq 1 50); do
    now="$(vpn_polls)" || return 1
    if ((now >= first + 2)); then echo grew; return 0; fi
    sleep 0.2
  done
  echo "polls=$((now - first))"
}
# `still` when the service starts no poll over 4 s.
vpn_polls_still() {
  local first now
  first="$(vpn_polls)" || return 1
  sleep 4
  now="$(vpn_polls)" || return 1
  if ((now == first)); then echo still; else echo "polls=$((now - first))"; fi
}
# Holds the next poll open and asks for a refresh every second until the
# held process is gone: `killed` when that takes 9 s to 20 s, with the
# time in $vpn_dir/hang.ms, `killed ms=<n>` outside it, `postponed` when
# the process outlives 20 s, `unheld` when no poll took the marker.
vpn_hang() {
  local pid start elapsed
  rm -f -- "${vpn_dir:?}/hang.pid" "${vpn_dir:?}/hang.taken"
  : >"$vpn_dir/hang"
  [[ $(vpn_refresh) == ok ]] || { echo refresh-refused; return 0; }
  for _ in $(seq 1 100); do
    if [[ -e $vpn_dir/hang.pid ]]; then break; fi
    sleep 0.1
  done
  [[ -e $vpn_dir/hang.pid ]] || { rm -f -- "${vpn_dir:?}/hang"; echo unheld; return 0; }
  pid="$(<"$vpn_dir/hang.pid")"
  start="$(now_ms)"
  while kill -0 "$pid" 2>/dev/null; do
    elapsed=$(($(now_ms) - start))
    if ((elapsed >= 20000)); then echo postponed; return 0; fi
    [[ $(vpn_refresh) == ok ]] || { echo refresh-refused; return 0; }
    sleep 1
  done
  elapsed=$(($(now_ms) - start))
  printf '%s\n' "$elapsed" >"$vpn_dir/hang.ms"
  if ((elapsed >= 9000)); then echo killed; else echo "killed ms=$elapsed"; fi
}
vpn_enter_pane() { # LABEL
  rest_pointer || fail "$1: moving the pointer off System failed"
  type_keys -M logo -k comma -m logo
  expect_poll "$1: the System shortcut opens the VPN section" shown vpn_shown window
  expect_poll "$1: System opens in its search field" '["TextField",""]' ipc smoke activeFocusItem window vgs.system
  type_keys VPN
  expect_poll "$1: the search names VPN" '"VPN"' ipc smoke readDescendant window vgs.system Sidebar query
  type_keys -k Return
  expect_poll "$1: Enter moves the keys into the VPN section" true ipc smoke activeFocusWithin window vgs.vpn VpnBody
}
vpn_leave_pane() { # LABEL
  type_keys -k Escape
  type_keys -k Escape
  type_keys -k Escape
  expect_poll "$1: Escape closes System" hidden vpn_shown window
}

# The world: a running tailnet with Mullvad nodes, two accounts, a running
# daemon and no operator, so the operator step reads needed.
vpn_use mullvad.json
device_reply tailscale 0 "$(<"$vpn_fixtures/accounts.txt")" switch --list
device_reply tailscale 0 "" get operator
device_reply tailscale 0 "" down
device_reply tailscale 0 "" up
device_reply tailscale 0 "" set --exit-node=gateway.tail-fixture.ts.net
device_reply tailscale 1 "" set --exit-node=
device_reply systemctl 0 "" is-active --quiet tailscaled.service
device_reply xdg-open 0 "" "$vpn_login_url"
expect "the core's system steps resolve in the fakes' tree" prefixed devices_system_tree
ln -sfn -- "$shim/tailscale" "$vpn_system_link"
expect "the shell resolves tailscale to the stand-in" "$shim/tailscale" shell_resolves tailscale
expect "the shell resolves xdg-open to the stand-in" "$shim/xdg-open" shell_resolves xdg-open
expected_errors+=('vpn: poll killed after 10000 ms' 'vpn: (exit-node|login) failed kind=(access-denied|other) ')
# The default set starts the plugin; the row counts one service's polls
# from its first, so it starts from a disabled plugin.
expect "VPN disables before its row" ok ipc shell setPluginEnabled vgs.vpn false
expect_poll "no VPN service is built before the row" False record_exists vgs.vpn
vpn_status_before="$(vpn_status_calls)" || { fail "vpn: the tailscale stand-in's calls are unreadable"; return 0; }
vpn_calls_before="$(vpn_call_count tailscale)" || { fail "vpn: the tailscale stand-in's calls are unreadable"; return 0; }
vpn_opens_before="$(vpn_call_count xdg-open)" || { fail "vpn: the xdg-open stand-in's calls are unreadable"; return 0; }

expect "VPN enables over the stand-ins" ok ipc shell setPluginEnabled vgs.vpn true
expect_poll "VPN's service is built" True record_exists vgs.vpn
rescan "a scan probes the system steps over the linked stand-in"
expect_poll "the service publishes the running tailnet" '"running"' vpn_value state
expect "the service publishes this device" '{"name": "desk", "address": "100.64.0.1"}' vpn_value device
expect "the service publishes the exit node in use" '{"id": "nFIXTURE0013CNTRL", "name": "Zurich, Switzerland"}' vpn_value exit
expect_poll "the service publishes both accounts" '["f1a0", "f1a1"]' vpn_account_ids
expect_poll "VPN's widget is placed" True vpn_placed
expect_poll "the widget draws the exit node from the shared record" '"globe-lock"' ipc smoke readDescendant "$(bar_key)" vgs.vpn BarItem iconName
expect "the poll waits the setting's 30 s while no view is open" 30000 vpn_interval

# Access denied: no operator, so the step reads needed and Allow is offered.
expect_poll "the core reads the operator step needed" "needed operator-unset" vpn_step tailscale-operator
expect_poll "an unset operator offers Allow" allow vpn_setup
expect "changes wait for Allow" false vpn_value writable
expect "System enables for the VPN section" ok ipc shell setPluginEnabled vgs.system true
expect "the VPN section opens in System" ok ipc shell summon window vgs.system '{"pane":"vgs.vpn","source":"smoke"}'
expect_poll "VPN's pane is mounted" shown vpn_shown window
expect "the pane receives its payload" '{"source":"smoke"}' ipc smoke readInstance window vgs.vpn payload
expect_poll "the pane reads the shared record" running vpn_body_state window
expect_poll "the pane draws the core's offered step" '{"label":"Allow"}' vpn_body window setupAction
expect_poll "an open pane makes the poll fast" 3000 vpn_interval
expect "System closes before the keyboard path" ok ipc shell hide window vgs.system
expect_poll "the closed pane is gone" hidden vpn_shown window
expect_poll "a closed pane gives the poll its 30 s back" 30000 vpn_interval

hypr_lua_save vpn
printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = true } })' >>"$home/.config/hypr/hyprland.lua"
expect "the nested keyboard uses symbol bindings" ok hypr reload config-only
terminal_stand_in
terminal_ready "vpn"
vpn_enter_pane "Allow"
expect "the section opens on its body while the switch waits for Allow" '["VpnBody",null]' ipc smoke activeFocusItem window vgs.vpn
type_keys -k Tab
expect_poll "Tab reaches Allow" '["Button","Allow"]' ipc smoke activeFocusItem window vgs.vpn
forget_record
type_keys -k Return
expect_poll "Allow hands the terminal vgshell system apply tailscale-operator" \
  "$(core_words core/system "System setup" org.vgs.tui system apply tailscale-operator)" recorded
device_reply tailscale 0 "$(id -un)" get operator
expect_run_end "the Allow core/system run ends" core/system
forget_record
rescan "a scan probes the operator again"
expect_poll "the core reads the operator step ready" "ready granted" vpn_step tailscale-operator
expect_poll "a granted operator offers no step" none vpn_setup
expect_poll "changes are open once the operator is granted" true vpn_value writable
# The setup run's window took the keys, so System closes by its IPC here.
expect "System closes after Allow" ok ipc shell hide window vgs.system
expect_poll "System is closed after Allow" hidden vpn_shown window

# Keys alone: the switch runs down and up, the list sets the exit node.
vpn_enter_pane "keys"
expect_poll "the section opens on its connection switch" '["Switch",""]' ipc smoke activeFocusItem window vgs.vpn
type_keys -k space
expect_poll "Space on the switch runs down" '[["down"]]' vpn_changes "$vpn_calls_before"
vpn_use stopped.json
expect_poll "the pane reads the stopped tailnet" stopped vpn_body_state window
expect_poll "the widget draws the stopped tailnet" '"shield-off"' ipc smoke readDescendant "$(bar_key)" vgs.vpn BarItem iconName
expect_poll "the switch keeps the keys" '["Switch",""]' ipc smoke activeFocusItem window vgs.vpn
type_keys -k space
expect_poll "Space on the switch runs up" '[["down"], ["up"]]' vpn_changes "$vpn_calls_before"
vpn_use mullvad.json
expect_poll "the pane reads the running tailnet again" running vpn_body_state window
expect_poll "the exit nodes list the tailnet's node, then one Mullvad node a city" \
  '[["None", ""], ["gateway", ""], ["Stockholm, Sweden", ""], ["Zurich, Switzerland", "In use"]]' vpn_exit_rows
type_keys -k Tab
expect_poll "Tab reaches the exit nodes" true ipc smoke activeFocusWithin window vgs.vpn DeviceList
type_keys -k Down
type_keys -k Return
expect_poll "Enter on a node sets it by its DNS name" \
  '[["down"], ["up"], ["set", "--exit-node=gateway.tail-fixture.ts.net"]]' vpn_changes "$vpn_calls_before"
expect "no peer id reached a tailscale argv" 0 vpn_argv_ids "$vpn_calls_before"
expect_poll "the change ends" '""' vpn_value action
expect "a denied change and a denied sign-in leave another problem than a plain failure" told-apart vpn_failures
vpn_leave_pane "keys"
hypr_lua_restore vpn

# The flyout, and the poll interval behind it.
expect_poll "the poll is slow again with System closed" 30000 vpn_interval
expect "the closed poll starts nothing for 4 s" still vpn_polls_still
expect "the flyout opens" ok ipc shell summon panel vgs.vpn '{"source":"smoke"}'
expect_poll "VPN's flyout is shown" shown vpn_shown panel
expect "the flyout receives its payload" '{"source":"smoke"}' ipc smoke readInstance panel vgs.vpn payload
expect_poll "the flyout reads the shared record" running vpn_body_state panel
expect_poll "an open flyout makes the poll fast" 3000 vpn_interval
expect "the open poll starts two polls within 10 s" grew vpn_polls_grow
expect "the flyout closes" ok ipc shell hide panel vgs.vpn
expect_poll "the closed flyout is gone" hidden vpn_shown panel
expect_poll "the closed flyout gives the poll its 30 s back" 30000 vpn_interval
expect_poll "every status call the stand-in recorded is the service's" none vpn_surplus "$vpn_status_before"

# A held poll: killed at the watchdog while a refresh arrives every second.
expect "a held poll is killed by the 10 s watchdog under refreshes" killed vpn_hang
if [[ -e $vpn_dir/hang.ms ]]; then printf '        the held poll ended %s ms after its start\n' "$(<"$vpn_dir/hang.ms")"; fi
expect "the service counts one killed poll" 1 ipc smoke readInstance service vgs.vpn pollsKilled
expect_poll "the refresh that waited reads the tailnet again" '"running"' vpn_value state

# Sign-in: the printed address goes to the xdg-open stand-in.
vpn_use logged-out.json
expect "a refresh reads the signed-out daemon" ok vpn_refresh
expect_poll "the service publishes signed out" '"signed-out"' vpn_value state
rm -f -- "${vpn_dir:?}/login-release"
expect "sign-in starts" ok vpn_act login
expect_poll "the sign-in address reaches the xdg-open stand-in alone" "[[\"$vpn_login_url\"]]" vpn_opens "$vpn_opens_before"
expect_poll "the service waits for the browser" '"opened"' vpn_value login
: >"$vpn_dir/login-release"
expect_poll "the finished sign-in ends the wait" '"idle"' vpn_value login
expect "the finished sign-in leaves no problem" '""' vpn_value problem

# A daemon that is off: the service step reads needed and Enable is offered.
: >"$vpn_dir/service-off"
device_reply systemctl 3 "" is-active --quiet tailscaled.service
device_reply systemctl 0 loaded show --property=LoadState --value tailscaled.service
rescan "a scan probes the stopped service"
expect_poll "the core reads the service step needed" "needed inactive" vpn_step service-tailscaled
expect "a refresh reads the stopped daemon" ok vpn_refresh
expect_poll "the service publishes the daemon off" '"service-off"' vpn_value state
expect_poll "a stopped daemon offers Enable" enable vpn_setup
rm -f -- "${vpn_dir:?}/service-off"
device_reply systemctl 0 "" is-active --quiet tailscaled.service
vpn_use mullvad.json

# Controls, on a copy: a widget that polls on its own, a refresh that
# restarts the watchdog, and a failure table without the access-denied text.
expect "VPN disables before its control copy" ok ipc shell setPluginEnabled vgs.vpn false
expect_poll "the disabled service's build record is gone" False record_exists vgs.vpn
expect_poll "the disabled plugin holds no status record" absent vpn_record
vpn_copy="$home/.config/vgshell/plugins/vgs.vpn"
mkdir -p -- "$vpn_copy"
cp -R -- "$repo/shell/plugins/vgs.vpn/." "$vpn_copy/"
python3 - "$vpn_copy/Widget.qml" "$vpn_copy/Service.qml" "$vpn_copy/VpnLogic.js" <<'PYCONTROL'
import pathlib, sys
widget, service, logic = map(pathlib.Path, sys.argv[1:])
text = widget.read_text()
for old, new in (("import QtQuick\n", "import QtQuick\nimport Quickshell.Io\n"),
                 ("    BarItem {\n", "    Process { command: [\"tailscale\", \"status\", \"--json\"]; running: true }\n\n    BarItem {\n")):
    assert text.count(old) == 1, old
    text = text.replace(old, new)
widget.write_text(text)
text = service.read_text()
old = "        runPoll(\"refresh\");\n        readAccounts();\n"
assert text.count(old) == 1, old
service.write_text(text.replace(old, "        if (watchdog.running) watchdog.restart();\n" + old))
text = logic.read_text()
old = "pattern: /access denied/i"
assert text.count(old) == 1, old
logic.write_text(text.replace(old, "pattern: /prefs refused/i"))
PYCONTROL
rescan "the control copy is discovered"
vpn_control_before="$(vpn_status_calls)" || { fail "vpn: the tailscale stand-in's calls are unreadable"; return 0; }
expect "the control copy enables" ok ipc shell setPluginEnabled vgs.vpn true
expect_poll "the control's service is built" True record_exists vgs.vpn
expect_poll "the control's service reads the tailnet" '"running"' vpn_value state
expect_poll "control: a widget that polls on its own is a call the service did not start" extra vpn_surplus "$vpn_control_before"
expect "control: a service that does not know the access-denied text leaves the plain failure's problem" same vpn_failures
expect "control: a refresh that restarts the watchdog holds the poll past 20 s" postponed vpn_hang
expect "the control copy disables" ok ipc shell setPluginEnabled vgs.vpn false
expect_poll "the control's service is gone" False record_exists vgs.vpn
rm -rf -- "${vpn_copy:?}"
rescan "the shipped plugin is restored"
cp -- "$vpn_saved" "$home/.config/vgshell/shell.json"
expect "the row restores the configuration" ok ipc shell reloadConfig
rm -f -- "$vpn_system_link"
device_reply_clear tailscale
device_reply_clear systemctl
device_reply_clear xdg-open
sentinel_restore "$shim/tailscale"
