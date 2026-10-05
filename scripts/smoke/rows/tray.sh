# The tray over two stand-in tray apps, scripts/smoke/fixtures/tray/mock-sni.py,
# which run on the sandbox's private session bus alone: their starter takes
# an environment of its own, the sandbox bus its only D-Bus address, and
# refuses any other address, the owner's bus among them, and an empty one,
# which its control reads with nothing started. With vgs.tray enabled and
# placed, the row reads both apps' icons in the drawer and the `items`
# choices the service publishes; the drawer opening while the pointer
# rests on the arrow and closing once it leaves, from the clip's width
# and the reveal at 1 and at 0; a left click reaching the app as
# Activate; a right click opening the app's menu, Accounts opening its
# submenu with a Back entry named after the app, Back and Accounts again,
# and Sign in reaching the app as its menu event; Pin in the drawn Manage
# tray icons popover, opened from the frame menu on the arrow, moving the
# app to the pinned row, into the user file, and keeping it there after a
# shell restart, which the apps follow by registering again; and Hide
# taking the other app off the bar. Each click is a real one on the drawn
# item through the pointer helper. Controls, each a copy of vgs.tray
# installed as a user plugin of its own id with one edit: a menu without
# the drill-down, whose Accounts triggers instead, so Sign in never
# reaches the app; a service that drops the manage write, so the restart
# reads the app unpinned; a reveal held at 0, so the clip stays shut
# under the hover; and a left click that calls the secondary action, so
# the app records no Activate. The row stops the apps, restores the user
# file, removes its copies and puts the pointer back.
# This row has no latency ceiling; every reading polls through expect_poll.
# inputs: shell/plugins/vgs.tray/* scripts/smoke/fixtures/tray/* scripts/smoke/fixtures/ai-usage/edit.py shell/Ui/BarWidget.qml shell/Ui/controls/BarItem.qml shell/Ui/controls/Button.qml shell/Ui/controls/ToggleButton.qml shell/Ui/overlay/* shell/Ui/layout/SectionHeader.qml shell/Ui/foundation/Divider.qml shell/Core/PluginLogic.js shell/Core/PluginStatus.qml shell/Core/Plugins.qml shell/Core/Config.qml shell/Core/Capabilities.qml shell/Core/IpcRegistry.qml
set -euo pipefail
tray_file="$home/.config/vgshell/shell.json"
tray_saved="$sandbox/shell-before-tray.json"
tray_pointer="$pointer_at"
tray_record="$sandbox/tray-record"
tray_bus="unix:path=$rt_dir/bus"
tray_mock_pid=""
tray_id=vgs.tray
cp -- "$tray_file" "$tray_saved"
tray_enabled_before="$(plugin_enabled vgs.tray)"

# tray_mock_start BUS LOG: the stand-in tray apps started on the session
# bus BUS, their output in LOG, with no environment but PATH, HOME and that
# bus, recording into tray_record; prints `started`. Any BUS but the
# sandbox's own session bus is refused, `refused: bus=<bus> reason=empty`
# or `reason=not-sandbox`, and nothing starts.
tray_mock_start() { # BUS LOG
  if [[ -z $1 ]]; then echo "refused: bus= reason=empty"; return 1; fi
  if [[ $1 != "$tray_bus" ]]; then echo "refused: bus=$1 reason=not-sandbox"; return 1; fi
  spawn "$2" env -i PATH="$PATH" HOME="$home" DBUS_SESSION_BUS_ADDRESS="$1" python3 "$source_repo/scripts/smoke/fixtures/tray/mock-sni.py" "$tray_record"
  tray_mock_pid="$spawn_pid"
  echo started
}
# tray_mock_refused BUS LOG: tray_mock_start's answer for BUS, and whether
# it left LOG, which a start creates, absent.
tray_mock_refused() { local said; said="$(tray_mock_start "$1" "$2")" || true; if [[ -e $2 ]]; then echo "$said log=present"; else echo "$said log=absent"; fi; }

# Readers of the widget of plugin tray_id on the first bar.
tray_read() { ipc smoke readInstance "$(bar_key)" "$tray_id" "$1"; }
# The ids in bucket NAME (pinned, drawer, hidden, listed), sorted.
tray_bucket() { tray_read buckets | py_reply 'import json,sys; print(json.dumps(sorted(r["id"] for r in json.load(sys.stdin)[sys.argv[1]])))' "$1"; }
# Whether the widget draws a shown icon named LABEL: drawn or absent.
tray_icon() { ipc smoke labelledGeometry "$(bar_key)" "$tray_id" TrayButton "$1" | py_reply 'import sys; print("absent" if sys.stdin.read().strip() == "absent" else "drawn")'; }
# Whether the stand-in apps recorded LINE.
tray_recorded() { if [[ -f $tray_record ]] && grep -qFx -- "$1" "$tray_record"; then echo True; else echo False; fi; }
# The open popup's control TYPE reading TEXT: drawn or absent.
tray_popup() { ipc smoke popupItemGeometry "$(bar_key)" "$tray_id" "" "" "$1" "$2" | py_reply 'import sys; print("absent" if sys.stdin.read().strip() == "absent" else "drawn")'; }
# The pinned ids of plugin tray_id's layout entry in the user file.
tray_file_pinned() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); l=d.get("bar", {}).get("layout", {}); e=[e for s in ("left", "center", "right") for e in l.get(s, []) if e["id"] == sys.argv[2]]; print(json.dumps([i["item"] for i in e[0].get("pinned", [])]) if e else "unplaced")' "$tray_file" "$tray_id"; }
# A real click of BUTTON (left or right) on the centre of the widget's
# drawn icon named LABEL.
tray_click() { # LABEL left|right
  local box x y
  box="$(ipc smoke labelledGeometry "$(bar_key)" "$tray_id" TrayButton "$1")" || return 1
  [[ $box == \[* ]] || return 1
  read -r x y < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(int(x+w/2), int(y+h/2))' "$box") || return 1
  hover "$((x - 1))" "$y" || return 1
  if [[ $2 == right ]]; then right_click "$x" "$y"; else click "$x" "$y"; fi
}
# The pointer resting on the widget's arrow, which opens the drawer.
tray_hover_arrow() {
  local box x y
  box="$(ipc smoke labelledGeometry "$(bar_key)" "$tray_id" BarItem "Tray icons")" || return 1
  [[ $box == \[* ]] || return 1
  read -r x y < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(int(x+w/2), int(y+h/2))' "$box") || return 1
  hover "$((x - 1))" "$y" && hover "$x" "$y"
}
# The drawer opened under the pointer, its clip as wide as the drawer.
tray_open_drawer() {
  tray_hover_arrow || fail "$1: hovering the arrow failed"
  expect_poll "$1: the drawer opens under the pointer" 1 tray_read revealProgress
}
tray_clip_full() { python3 -c 'import sys; e, r = float(sys.argv[1]), float(sys.argv[2]); print("full" if e > 0 and r == e else "extent=%s reveal=%s" % (e, r))' "$(tray_read drawerExtent)" "$(tray_read revealExtent)"; }
# The Manage tray icons popover, opened from the frame menu on the arrow.
tray_manage() {
  local box x y
  box="$(ipc smoke labelledGeometry "$(bar_key)" "$tray_id" BarItem "Tray icons")" || return 1
  read -r x y < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(int(x+w/2), int(y+h/2))' "$box") || return 1
  hover "$((x - 1))" "$y" && right_click "$x" "$y" || return 1
  click_item "popup:$(bar_key)" "$tray_id" "" "" MenuItem "Manage tray icons"
}
tray_toggle() { click_item "popup:$(bar_key)" "$tray_id" ManageRow "$1" ToggleButton "$2"; }
tray_menu_click() { click_item "popup:$(bar_key)" "$tray_id" "" "" MenuItem "$1"; }

expect "enabling the tray is allowed" ok ipc shell setPluginEnabled vgs.tray true
expect "placing the tray is allowed" ok ipc shell setPluginPlaced vgs.tray true
expect_poll "the tray's widget and service are built" True record_exists vgs.tray

# The starter's refusals start nothing, so no stand-in reaches a bus but
# the sandbox's.
expect "control: the stand-in tray apps refuse the owner's bus" "refused: bus=unix:path=$XDG_RUNTIME_DIR/bus reason=not-sandbox log=absent" tray_mock_refused "unix:path=$XDG_RUNTIME_DIR/bus" "$sandbox/tray-mock-owner.log"
expect "control: the stand-in tray apps refuse the owner's bus by its fixed path" "refused: bus=unix:path=/run/user/$(id -u)/bus reason=not-sandbox log=absent" tray_mock_refused "unix:path=/run/user/$(id -u)/bus" "$sandbox/tray-mock-fixed.log"
expect "control: the stand-in tray apps refuse an empty address" "refused: bus= reason=empty log=absent" tray_mock_refused "" "$sandbox/tray-mock-empty.log"
tray_mock_start "$tray_bus" "$sandbox/tray-mock.log" >/dev/null || fail "the stand-in tray apps did not start"

# (a) Both apps' icons sit in the drawer, and the service offers both.
expect_poll "both apps' icons sit in the drawer" '["vgs-smoke-tray-a", "vgs-smoke-tray-b"]' tray_bucket drawer
expect "no icon is pinned" '[]' tray_bucket pinned
expect "the drawer draws Smoke Tray A's icon" drawn tray_icon "Smoke Tray A"
tray_offers() { ipc smoke statusValues vgs.tray | py_reply 'import json,sys; print(json.dumps(sorted([c["label"], c["value"]] for c in json.load(sys.stdin).get("items", []))))'; }
expect_poll "the service offers both apps to the Settings page" '[["Smoke Tray A", "vgs-smoke-tray-a"], ["Smoke Tray B", "vgs-smoke-tray-b"]]' tray_offers

# (d) The drawer opens while the pointer rests on the arrow and shuts once
# it leaves.
expect "the drawer starts shut" 0 tray_read revealExtent
tray_open_drawer "the hover"
expect "the open drawer's clip is as wide as the drawer" full tray_clip_full
rest_pointer || fail "moving the pointer off the tray failed"
expect_poll "the drawer shuts once the pointer leaves" 0 tray_read revealProgress
expect "the shut drawer's clip has no width" 0 tray_read revealExtent

# (e) A left click activates the app.
: >"$tray_record"
tray_open_drawer "the left click"
tray_click "Smoke Tray A" left || fail "the left click on Smoke Tray A's icon failed"
expect_poll "a left click reaches the app as Activate" True tray_recorded "Activate vgs-smoke-tray-a"

# (f) A right click opens the app's menu; Accounts opens its submenu in
# place, Back returns, and Sign in reaches the app.
tray_click "Smoke Tray A" right || fail "the right click on Smoke Tray A's icon failed"
expect_poll "a right click opens the app's menu" drawn tray_popup MenuItem Open
expect "the menu lists Accounts" drawn tray_popup MenuItem Accounts
expect "the menu draws no frame menu entry" absent tray_popup MenuItem Hide
tray_menu_click Accounts || fail "the click on Accounts failed"
expect_poll "Accounts opens its submenu" drawn tray_popup MenuItem "Sign in"
expect "the submenu starts with Back, named after the app" drawn tray_popup MenuItem "Smoke Tray A"
expect "the submenu replaces the root's entries" absent tray_popup MenuItem Open
tray_menu_click "Smoke Tray A" || fail "the click on Back failed"
expect_poll "Back returns to the root" drawn tray_popup MenuItem Open
tray_menu_click Accounts || fail "the second click on Accounts failed"
expect_poll "Accounts opens its submenu again" drawn tray_popup MenuItem "Sign in"
tray_menu_click "Sign in" || fail "the click on Sign in failed"
expect_poll "Sign in reaches the app as its menu event" True tray_recorded "Event 4 clicked"
expect_poll "Sign in closes the menu" absent tray_popup MenuItem "Sign in"
expect "Accounts sent the app no event" False tray_recorded "Event 3 clicked"
rest_pointer || fail "moving the pointer off the tray failed"

# (b) Pin in the drawn Manage tray icons popover pins the app, into the
# user file and through a restart.
tray_manage || fail "opening Manage tray icons failed"
expect_poll "Manage tray icons opens the popover" drawn tray_popup ToggleButton Pin
tray_toggle "Smoke Tray A" Pin || fail "the click on Smoke Tray A's Pin failed"
expect_poll "Pin moves the app to the pinned row" '["vgs-smoke-tray-a"]' tray_bucket pinned
expect "Pin takes the app out of the drawer" '["vgs-smoke-tray-b"]' tray_bucket drawer
expect_poll "the user file holds the pin" '["vgs-smoke-tray-a"]' tray_file_pinned
type_keys -k Escape || fail "Escape on the popover failed"
expect_poll "Escape closes the popover" absent tray_popup ToggleButton Pin
stop_shell
start_shell "$repo" "$sandbox/tray-restart.log" || fail "the shell starts again for the pinned app"
expect_poll "after a restart the apps' icons are back" '["vgs-smoke-tray-a", "vgs-smoke-tray-b"]' tray_bucket listed
expect "after a restart the app stays pinned" '["vgs-smoke-tray-a"]' tray_bucket pinned
expect "after a restart the pinned row draws its icon" drawn tray_icon "Smoke Tray A"

# (c) Hide takes the other app off the bar and out of the drawer.
tray_manage || fail "opening Manage tray icons after the restart failed"
expect_poll "Manage tray icons opens the popover after the restart" drawn tray_popup ToggleButton Hide
tray_toggle "Smoke Tray B" Hide || fail "the click on Smoke Tray B's Hide failed"
expect_poll "Hide takes the app out of the drawer" '[]' tray_bucket drawer
expect "Hide keeps the pinned app" '["vgs-smoke-tray-a"]' tray_bucket pinned
expect_poll "the bar draws no icon of the hidden app" absent tray_icon "Smoke Tray B"
type_keys -k Escape || fail "Escape on the popover failed"
expect_poll "Escape closes the popover after Hide" absent tray_popup ToggleButton Hide

# The controls: copies of vgs.tray, each with one edit, installed under
# their own ids, read from a user file with no other copy.
cp -- "$tray_file" "$sandbox/shell-tray-controls.json"
tray_edit() { python3 "$source_repo/scripts/smoke/fixtures/ai-usage/edit.py" "$@"; }
# tray_copy NAME FILE OLD NEW: vgs.tray installed as acme.tray-NAME with
# OLD in FILE replaced by NEW, then found by a rescan, placed and enabled;
# tray_id names it.
tray_copy() { # NAME FILE OLD NEW
  local dir="$home/.config/vgshell/plugins/acme.tray-$1"
  rm -rf -- "${dir:?}"
  cp -R -- "$repo/shell/plugins/vgs.tray" "$dir"
  tray_edit "$dir/manifest.json" '"id": "vgs.tray"' "\"id\": \"acme.tray-$1\"" && tray_edit "$dir/$2" "$3" "$4" || { fail "control $1: the copy's edit failed"; return 1; }
  tray_id="acme.tray-$1"
  rescan "control $1: rescan after installing the copy answers ok"
  expect_poll "control $1: the copy's widget and service are built" True record_exists "$tray_id"
  expect_poll "control $1: the copy draws both apps' icons" '["vgs-smoke-tray-a", "vgs-smoke-tray-b"]' tray_bucket listed
  : >"$tray_record"
}
tray_copy_drop() { # NAME
  rest_pointer || fail "control $1: moving the pointer off the tray failed"
  cp -- "$sandbox/shell-tray-controls.json" "$tray_file.tmp" && mv -T -- "$tray_file.tmp" "$tray_file"
  rm -rf -- "${home:?}/.config/vgshell/plugins/acme.tray-$1"
  rescan "control $1: rescan after removing the copy answers ok"
  expect_poll "control $1: the copy is gone" absent plugin_enabled "acme.tray-$1"
  tray_id=vgs.tray
}

if tray_copy drill TrayMenu.qml 'if (modelData.hasChildren) root.enter(modelData, modelData.text);' 'if (false) root.enter(modelData, modelData.text);'; then
  tray_open_drawer "control drill"
  tray_click "Smoke Tray A" right || fail "control drill: the right click failed"
  expect_poll "control drill: the copy's menu opens" drawn tray_popup MenuItem Accounts
  tray_menu_click Accounts || fail "control drill: the click on Accounts failed"
  expect_poll "control drill: Accounts reaches the app as its own event" True tray_recorded "Event 3 clicked"
  sleep 1
  expect "control drill: with no drill-down Sign in is never drawn" absent tray_popup MenuItem "Sign in"
  expect "control drill: with no drill-down Sign in never reaches the app" False tray_recorded "Event 4 clicked"
  type_keys -k Escape || fail "control drill: Escape on the menu failed"
  expect_poll "control drill: Escape closes the menu" absent tray_popup MenuItem Accounts
  tray_copy_drop drill
fi

if tray_copy nowrite Service.qml 'const reply = shell.configure.set(key, next[key]);' 'const reply = "ok";'; then
  tray_manage || fail "control nowrite: opening Manage tray icons failed"
  expect_poll "control nowrite: the popover lists Smoke Tray A" drawn tray_popup ToggleButton Pin
  tray_toggle "Smoke Tray A" Pin || fail "control nowrite: the click on Pin failed"
  type_keys -k Escape || fail "control nowrite: Escape on the popover failed"
  expect_poll "control nowrite: Escape closes the popover" absent tray_popup ToggleButton Pin
  stop_shell
  start_shell "$repo" "$sandbox/tray-nowrite-restart.log" || fail "control nowrite: the shell starts again"
  expect_poll "control nowrite: after a restart the apps' icons are back" '["vgs-smoke-tray-a", "vgs-smoke-tray-b"]' tray_bucket listed
  expect "control nowrite: a dropped write leaves the app unpinned after the restart" '[]' tray_bucket pinned
  expect "control nowrite: the user file holds no pin" '[]' tray_file_pinned
  tray_copy_drop nowrite
fi

if tray_copy shut Widget.qml 'property real revealProgress: expanded && buckets.drawer.length > 0 ? 1 : 0' 'property real revealProgress: 0'; then
  tray_hover_arrow || fail "control shut: hovering the arrow failed"
  expect_poll "control shut: the hover reaches the copy" true tray_read expanded
  sleep 1
  expect "control shut: a reveal held at 0 keeps the clip shut under the hover" 0 tray_read revealExtent
  tray_copy_drop shut
fi

if tray_copy secondary TrayButton.qml 'else trayItem.activate();' 'else trayItem.secondaryActivate();'; then
  tray_open_drawer "control secondary"
  tray_click "Smoke Tray A" left || fail "control secondary: the left click failed"
  expect_poll "control secondary: the click reaches the app as its secondary action" True tray_recorded "SecondaryActivate vgs-smoke-tray-a"
  expect "control secondary: the app records no Activate" False tray_recorded "Activate vgs-smoke-tray-a"
  tray_copy_drop secondary
fi

# The restore: the stand-in apps stopped, the user file as the row found it.
if [[ -n $tray_mock_pid ]]; then
  kill -TERM "$tray_mock_pid" 2>/dev/null || true
  wait "$tray_mock_pid" 2>/dev/null || true
fi
expect_poll "the tray lists no app once the stand-ins stop" '[]' tray_bucket listed
cp -- "$tray_saved" "$tray_file.tmp" && mv -T -- "$tray_file.tmp" "$tray_file"
expect_poll "the restore leaves the tray enabled as the row found it" "$tray_enabled_before" plugin_enabled vgs.tray
if [[ -n $tray_pointer ]]; then
  read -r tray_x tray_y <<<"$tray_pointer"
  hover "$tray_x" "$tray_y" || fail "putting the pointer back failed"
else
  rest_pointer || fail "resting the pointer failed"
fi
