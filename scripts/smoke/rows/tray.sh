# The tray over two stand-in tray apps, scripts/smoke/fixtures/tray/mock-sni.py,
# which run on the sandbox's private session bus alone: their starter takes
# an environment of its own, the sandbox bus its only D-Bus address, and
# refuses any other address, the owner's bus among them, and an empty one,
# which its control reads with a stand-in spawn that starts nothing. With
# vgs.tray enabled and placed, the row reads both apps' icons in the drawer
# and the `items` choices the service publishes; the drawer opening while
# the pointer rests on the arrow and closing once it leaves, from the drawn
# clip's width and the reveal at 1 and at 0; the arrow staying put on the
# screen while the drawer opens, and a click on it then holding the drawer
# open and activating no app; a left click reaching the app as Activate; a
# right click opening the app's menu, a double click on Accounts opening
# its submenu, with a Back entry named after the app, and reaching nothing
# with its second click, sent once Sign in is drawn under a motion scale
# that stretches the menu's guard to 1000 ms, Back and Accounts again, and
# Sign in reaching the app as its menu event once; Pin in the drawn Manage tray icons popover,
# opened from the frame menu on the arrow, moving the app to the pinned
# row, into the user file, and keeping it there after a shell restart,
# which the apps follow by registering again; and Hide taking the other
# app off the bar. Each click is a real one on the drawn item through the
# pointer helper. Controls, each a copy of vgs.tray installed as a user
# plugin of its own id with one edit: an arrow at the widget's left edge,
# left of the drawer, which moves as the drawer opens; a menu without the
# guard after a level change, whose double click on Accounts sends Sign
# in; a menu without the drill-down, whose Accounts triggers instead, so
# Sign in is never drawn; a service that drops the manage write, which
# logs each drop, so the restart reads the app unpinned; a reveal held at
# 0, so the clip stays shut under the hover; and a left click that calls
# the secondary action, so the app records no Activate. The row stops the
# apps, restores the user file and the theme file, reads the tray's
# settings back, removes its copies and puts the pointer back.
# This row has no latency ceiling; every reading polls through expect_poll.
# inputs: shell/plugins/vgs.tray/* shell/plugins/vgs.bar/Bar.qml scripts/smoke/fixtures/tray/* scripts/smoke/fixtures/ai-usage/edit.py shell/Ui/BarWidget.qml shell/Ui/controls/BarItem.qml shell/Ui/controls/Button.qml shell/Ui/controls/ToggleButton.qml shell/Ui/overlay/* shell/Ui/layout/SectionHeader.qml shell/Ui/foundation/Divider.qml shell/Core/PluginLogic.js shell/Core/PluginStatus.qml shell/Core/Plugins.qml shell/Core/Config.qml shell/Core/Capabilities.qml shell/Core/IpcRegistry.qml shell/Commons/Theme.qml shell/Commons/ThemeLogic.js shell/Commons/AnchorTracker.qml
set -euo pipefail
tray_file="$home/.config/vgshell/shell.json"
tray_saved="$sandbox/shell-before-tray.json"
tray_pointer="$pointer_at"
tray_record="$sandbox/tray-record"
tray_bus="unix:path=$rt_dir/bus"
tray_mock_pid=""
tray_id=vgs.tray
cp -- "$tray_file" "$tray_saved"

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
# it left LOG absent. Inside it a stand-in spawn only creates LOG, so a
# starter whose refusal broke reads `log=present` and connects nothing.
tray_mock_refused() { local said; said="$(spawn() { : >"$1"; }; tray_mock_start "$1" "$2")" || true; if [[ -e $2 ]]; then echo "$said log=present"; else echo "$said log=absent"; fi; }

# Readers of the widget of plugin tray_id on the first bar.
tray_read() { ipc smoke readInstance "$(bar_key)" "$tray_id" "$1"; }
# The ids in bucket NAME (pinned, drawer, hidden, listed), sorted.
tray_bucket() { tray_read buckets | py_reply 'import json,sys; print(json.dumps(sorted(r["id"] for r in json.load(sys.stdin)[sys.argv[1]])))' "$1"; }
# Whether the widget draws a shown icon named LABEL: drawn or absent.
tray_icon() { ipc smoke labelledGeometry "$(bar_key)" "$tray_id" TrayButton "$1" | py_reply 'import sys; print("absent" if sys.stdin.read().strip() == "absent" else "drawn")'; }
# Whether the stand-in apps recorded LINE, and how many times.
tray_recorded() { if [[ -f $tray_record ]] && grep -qFx -- "$1" "$tray_record"; then echo True; else echo False; fi; }
tray_count() { if [[ -f $tray_record ]]; then grep -cFx -- "$1" "$tray_record" || true; else echo 0; fi; }
# Whether the running shell's log holds LINE's text.
tray_logged() { if grep -qF -- "$1" "$instance_log"; then echo True; else echo False; fi; }
# The open popup's control TYPE reading TEXT: drawn or absent.
tray_popup() { ipc smoke popupItemGeometry "$(bar_key)" "$tray_id" "" "" "$1" "$2" | py_reply 'import sys; print("absent" if sys.stdin.read().strip() == "absent" else "drawn")'; }
# The pinned ids of plugin tray_id's layout entry in the user file.
tray_file_pinned() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); l=d.get("bar", {}).get("layout", {}); e=[e for s in ("left", "center", "right") for e in l.get(s, []) if e["id"] == sys.argv[2]]; print(json.dumps([i["item"] for i in e[0].get("pinned", [])]) if e else "unplaced")' "$tray_file" "$tray_id"; }
# The drawn drawer clip: `full` while its box is as wide as the drawer,
# `shut` while it has no width, else its width. The clip is the item
# holding the Row of the drawer's icons, read from the probe's boxes of
# every item under the widget; a pinned icon's Row sits on the widget.
tray_clip_state() {
  local extent
  extent="$(tray_read drawerExtent)" || return 1
  ipc smoke descendantGeometry "$(bar_key)" "$tray_id" | py_reply 'import json,sys
items = json.load(sys.stdin)
extent = float(sys.argv[1])
clips = {items[items[i]["parent"]]["parent"] for i, c in enumerate(items) if c["type"] == "TrayButton" and items[c["parent"]]["parent"] != 0}
if len(clips) != 1:
    print("clips=%d" % len(clips))
else:
    width = items[clips.pop()]["box"][2]
    print("full" if extent > 0 and abs(width - extent) < 0.5 else "shut" if width == 0 else "width=%s extent=%s" % (width, extent))' "$extent"
}
# tray_clip_opens_within MS: `opened` once tray_clip_state reads full,
# `never` when it has not after MS milliseconds, read every 100 ms.
tray_clip_opens_within() { # MS
  local state
  for _ in $(seq 1 $(($1 / 100))); do
    state="$(tray_clip_state)" || return 1
    [[ $state == full ]] && { echo opened; return; }
    sleep 0.1
  done
  echo never
}
# The arrow's box on the screen, and its centre.
tray_arrow_box() { ipc smoke labelledGeometry "$(bar_key)" "$tray_id" BarItem "Tray icons"; }
tray_arrow_centre() { python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(int(x+w/2), int(y+h/2))' "$(tray_arrow_box)"; }
# tray_arrow_moved X: `still` while the arrow's left edge is within one
# pixel of X, else `moved=<dx>`.
tray_arrow_moved() { tray_arrow_box | py_reply 'import json,sys; dx = json.load(sys.stdin)[0] - float(sys.argv[1]); print("still" if abs(dx) <= 1 else "moved=%s" % dx)' "$1"; }
tray_arrow_slid() { local said; said="$(tray_arrow_moved "$1")" || return 1; if [[ $said == moved=* ]]; then echo moved; else echo "$said"; fi; }
tray_arrow_x() { tray_arrow_box | py_reply 'import json,sys; print(json.load(sys.stdin)[0])'; }
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
  local x y
  read -r x y < <(tray_arrow_centre) || return 1
  hover "$((x - 1))" "$y" && hover "$x" "$y"
}
# The drawer opened under the pointer.
tray_open_drawer() {
  tray_hover_arrow || fail "$1: hovering the arrow failed"
  expect_poll "$1: the drawer opens under the pointer" 1 tray_read revealProgress
}
# The Manage tray icons popover, opened from the frame menu on the arrow.
tray_manage() {
  local x y
  read -r x y < <(tray_arrow_centre) || return 1
  hover "$((x - 1))" "$y" && right_click "$x" "$y" || return 1
  click_item "popup:$(bar_key)" "$tray_id" "" "" MenuItem "Manage tray icons"
}
tray_toggle() { click_item "popup:$(bar_key)" "$tray_id" ManageRow "$1" ToggleButton "$2"; }
# A click on the open menu's entry TEXT. A level change ignores the
# rows' clicks for motion.duration.slow, which tray_slow_guard stretches
# to 1000 ms; the click waits 1.2 s first, past the guard of the change
# before it.
tray_menu_click() { sleep 1.2; click_item "popup:$(bar_key)" "$tray_id" "" "" MenuItem "$1"; }
# tray_menu_double TEXT NEXT: a click on the open menu's entry TEXT, then a
# second click on the same point as soon as the level it opens draws its
# entry NEXT, read at most 20 times, so the second click lands on NEXT's
# row inside the guard.
tray_menu_double() { # TEXT NEXT
  local at x y
  at="$(point_item "popup:$(bar_key)" "$tray_id" "" "" MenuItem "$1")" || return 1
  read -r x y <<<"$at" || return 1
  click "$x" "$y" || return 1
  for _ in $(seq 1 20); do [[ $(tray_popup MenuItem "$2") == drawn ]] && break; done
  click "$x" "$y"
}
# tray_slow_guard on|off: the theme's motion scale at 4, which makes
# motion.duration.slow, the menu's guard, 1000 ms, so a second click read
# after the submenu draws lands inside it; off puts the theme file back.
tray_theme="$home/.config/vgshell/theme.json"
tray_slow_guard() { # on|off
  if [[ $1 == on ]]; then
    if [[ -e $tray_theme ]]; then cp -- "$tray_theme" "$sandbox/theme-before-tray.json"; else rm -f -- "${sandbox:?}/theme-before-tray.json"; fi
    printf '%s\n' '{ "schemaVersion": 1, "name": "slowtray", "tokens": { "motion": { "scale": 4 } } }' >"$tray_theme.tmp" && mv -T -- "$tray_theme.tmp" "$tray_theme"
    expect_poll "the slowed motion scale stretches the menu's guard" 1000 ipc smoke themeValue motion.duration.slow
  else
    if [[ -e $sandbox/theme-before-tray.json ]]; then cp -- "$sandbox/theme-before-tray.json" "$tray_theme.tmp" && mv -T -- "$tray_theme.tmp" "$tray_theme"; else rm -f -- "${tray_theme:?}"; fi
    expect_poll "the theme's motion scale is back" 250 ipc smoke themeValue motion.duration.slow
  fi
}
# The settings the running tray reads, against the saved user file:
# `restored` while vgs.tray is disabled there and in the shell, or its
# pinned and hidden ids are the saved entry's, else what differs.
tray_restored() {
  local enabled pinned hidden
  enabled="$(plugin_enabled vgs.tray)" || return 1
  if [[ $enabled == True ]]; then
    pinned="$(tray_read pinnedIds)" || return 1
    hidden="$(tray_read hiddenIds)" || return 1
  fi
  python3 -c 'import json,sys
d = json.load(open(sys.argv[1]))
disabled = "vgs.tray" in d.get("disabledPlugins", [])
entries = [e for s in ("left", "center", "right") for e in d.get("bar", {}).get("layout", {}).get(s, []) if e["id"] == "vgs.tray"]
saved = [[i["item"] for i in (entries[0].get(k, []) if entries else [])] for k in ("pinned", "hidden")]
if disabled:
    print("restored" if sys.argv[2] == "False" else "enabled=%s" % sys.argv[2])
elif sys.argv[2] != "True":
    print("enabled=%s" % sys.argv[2])
else:
    got = [json.loads(sys.argv[3]), json.loads(sys.argv[4])]
    print("restored" if got == saved else "settings=%s saved=%s" % (got, saved))' "$tray_saved" "$enabled" "${pinned:-[]}" "${hidden:-[]}"
}

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
# it leaves, read from the drawn clip.
expect "the drawn drawer starts shut" shut tray_clip_state
tray_open_drawer "the hover"
expect "the open drawer's drawn clip is as wide as the drawer" full tray_clip_state
rest_pointer || fail "moving the pointer off the tray failed"
expect_poll "the drawer shuts once the pointer leaves" 0 tray_read revealProgress
expect "the shut drawer's drawn clip has no width" shut tray_clip_state

# The arrow stays put on the screen while the drawer opens, so a click on
# it after the reveal holds the drawer open and activates no app.
: >"$tray_record"
tray_arrow_before="$(tray_arrow_x)" || fail "the arrow's box is unreadable"
tray_open_drawer "the arrow"
expect "the arrow stays put while the drawer opens" still tray_arrow_moved "$tray_arrow_before"
read -r tray_ax tray_ay < <(tray_arrow_centre) || fail "the arrow's box after the reveal is unreadable"
click "$tray_ax" "$tray_ay" || fail "the click on the arrow failed"
expect_poll "a click on the arrow holds the drawer open" true tray_read held
rest_pointer || fail "moving the pointer off the held tray failed"
expect_poll "the held drawer stays open once the pointer leaves" true tray_read expanded
expect "the held drawer's drawn clip stays open" full tray_clip_state
tray_hover_arrow || fail "hovering the arrow to release it failed"
click "$tray_ax" "$tray_ay" || fail "the click releasing the arrow failed"
expect_poll "a second click on the arrow releases the drawer" false tray_read held
rest_pointer || fail "moving the pointer off the released tray failed"
expect_poll "the released drawer shuts" 0 tray_read revealProgress

# (e) A left click activates the app; the arrow's clicks before it
# activated neither app, which the Activate of this click, recorded after
# theirs, proves.
tray_open_drawer "the left click"
tray_click "Smoke Tray A" left || fail "the left click on Smoke Tray A's icon failed"
expect_poll "a left click reaches the app as Activate" True tray_recorded "Activate vgs-smoke-tray-a"
expect "the left click activates its app once" 1 tray_count "Activate vgs-smoke-tray-a"
expect "the arrow's clicks activated no app" False tray_recorded "Activate vgs-smoke-tray-b"

# (f) A right click opens the app's menu. A double click on Accounts
# opens its submenu in place and its second click reaches nothing; Back
# returns, and Sign in reaches the app once.
tray_slow_guard on
tray_click "Smoke Tray A" right || fail "the right click on Smoke Tray A's icon failed"
expect_poll "a right click opens the app's menu" drawn tray_popup MenuItem Open
expect "the menu lists Accounts" drawn tray_popup MenuItem Accounts
expect "the menu draws no frame menu entry" absent tray_popup MenuItem Hide
tray_menu_double Accounts "Sign in" || fail "the double click on Accounts failed"
expect_poll "Accounts opens its submenu" drawn tray_popup MenuItem "Sign in"
expect "the submenu starts with Back, named after the app" drawn tray_popup MenuItem "Smoke Tray A"
expect "the submenu replaces the root's entries" absent tray_popup MenuItem Open
tray_menu_click "Smoke Tray A" || fail "the click on Back failed"
expect_poll "Back returns to the root" drawn tray_popup MenuItem Open
tray_menu_click Accounts || fail "the second click on Accounts failed"
expect_poll "Accounts opens its submenu again" drawn tray_popup MenuItem "Sign in"
tray_menu_click "Sign in" || fail "the click on Sign in failed"
expect_poll "Sign in reaches the app as its menu event" True tray_recorded "Event 4 clicked"
expect "the double click's second click sent Sign in nothing" 1 tray_count "Event 4 clicked"
expect_poll "Sign in closes the menu" absent tray_popup MenuItem "Sign in"
tray_slow_guard off
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
  expect_poll "control $1: the copy's drawer holds both apps' icons" '["vgs-smoke-tray-a", "vgs-smoke-tray-b"]' tray_bucket drawer
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

if tray_copy slide Widget.qml 'x: drawerClip.width' 'x: 0'; then
  tray_arrow_before="$(tray_arrow_x)" || fail "control slide: the arrow's box is unreadable"
  tray_open_drawer "control slide"
  expect "control slide: an arrow left of the drawer moves as it opens" moved tray_arrow_slid "$tray_arrow_before"
  tray_copy_drop slide
fi

if tray_copy guard TrayMenu.qml 'readonly property bool settling: settleTimer.running' 'readonly property bool settling: false'; then
  tray_slow_guard on
  tray_open_drawer "control guard"
  tray_click "Smoke Tray A" right || fail "control guard: the right click failed"
  expect_poll "control guard: the copy's menu opens" drawn tray_popup MenuItem Accounts
  tray_menu_double Accounts "Sign in" || fail "control guard: the double click on Accounts failed"
  expect_poll "control guard: with no guard the second click sends Sign in" True tray_recorded "Event 4 clicked"
  expect_poll "control guard: Sign in closes the copy's menu" absent tray_popup MenuItem "Sign in"
  tray_slow_guard off
  tray_copy_drop guard
fi

if tray_copy drill TrayMenu.qml 'if (modelData.hasChildren) root.enter(modelData, modelData.text);' 'if (false) root.enter(modelData, modelData.text);'; then
  tray_open_drawer "control drill"
  tray_click "Smoke Tray A" right || fail "control drill: the right click failed"
  expect_poll "control drill: the copy's menu opens" drawn tray_popup MenuItem Accounts
  tray_menu_click Accounts || fail "control drill: the click on Accounts failed"
  expect_poll "control drill: Accounts reaches the app as its own event" True tray_recorded "Event 3 clicked"
  expect "control drill: with no drill-down Sign in is never drawn" absent tray_popup MenuItem "Sign in"
  type_keys -k Escape || fail "control drill: Escape on the menu failed"
  expect_poll "control drill: Escape closes the menu" absent tray_popup MenuItem Accounts
  tray_copy_drop drill
fi

if tray_copy nowrite Service.qml 'const reply = shell.configure.set(key, next[key]);' 'const reply = (console.info("tray-nowrite: dropped " + key), "ok");'; then
  tray_manage || fail "control nowrite: opening Manage tray icons failed"
  expect_poll "control nowrite: the popover lists Smoke Tray A" drawn tray_popup ToggleButton Pin
  tray_toggle "Smoke Tray A" Pin || fail "control nowrite: the click on Pin failed"
  expect_poll "control nowrite: the Pin click reaches the copy's service, which drops its write" True tray_logged "tray-nowrite: dropped pinned"
  type_keys -k Escape || fail "control nowrite: Escape on the popover failed"
  expect_poll "control nowrite: Escape closes the popover" absent tray_popup ToggleButton Pin
  stop_shell
  start_shell "$repo" "$sandbox/tray-nowrite-restart.log" || fail "control nowrite: the shell starts again"
  expect_poll "control nowrite: after a restart the apps' icons are back" '["vgs-smoke-tray-a", "vgs-smoke-tray-b"]' tray_bucket listed
  expect "control nowrite: a dropped write leaves the app unpinned after the restart" '[]' tray_bucket pinned
  expect "control nowrite: the user file holds no pin" '[]' tray_file_pinned
  tray_copy_drop nowrite
fi

# The reveal takes motion.duration.slow, 250 ms; the shut control gives it
# 2 s, eight times that, to open the drawn clip.
if tray_copy shut Widget.qml 'property real revealProgress: expanded && buckets.drawer.length > 0 ? 1 : 0' 'property real revealProgress: 0'; then
  tray_hover_arrow || fail "control shut: hovering the arrow failed"
  expect_poll "control shut: the hover reaches the copy" true tray_read expanded
  expect "control shut: a reveal held at 0 keeps the drawn clip shut under the hover" never tray_clip_opens_within 2000
  tray_copy_drop shut
fi

if tray_copy secondary TrayButton.qml 'else trayItem.activate();' 'else trayItem.secondaryActivate();'; then
  tray_open_drawer "control secondary"
  tray_click "Smoke Tray A" left || fail "control secondary: the left click failed"
  expect_poll "control secondary: the click reaches the app as its secondary action" True tray_recorded "SecondaryActivate vgs-smoke-tray-a"
  expect "control secondary: the app records no Activate" False tray_recorded "Activate vgs-smoke-tray-a"
  tray_copy_drop secondary
fi

# The restore: the stand-in apps stopped, the user file as the row found
# it, and the running tray reading the saved settings again.
if [[ -n $tray_mock_pid ]]; then
  kill -TERM "$tray_mock_pid" 2>/dev/null || true
  wait "$tray_mock_pid" 2>/dev/null || true
fi
expect_poll "the tray lists no app once the stand-ins stop" '[]' tray_bucket listed
cp -- "$tray_saved" "$tray_file.tmp" && mv -T -- "$tray_file.tmp" "$tray_file"
expect_poll "the restore gives the tray the saved settings again" restored tray_restored
if [[ -n $tray_pointer ]]; then
  read -r tray_x tray_y <<<"$tray_pointer"
  hover "$tray_x" "$tray_y" || fail "putting the pointer back failed"
else
  rest_pointer || fail "resting the pointer failed"
fi
