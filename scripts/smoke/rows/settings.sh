# Settings edits and the dispatch queue. The Settings window opens from a
# real click on the gear, so the compositor gives its window the keyboard,
# and a click on a text field gives that field keyboard focus. A write is
# published once: its own file notification is read and found identical.
# An unrelated change keeps an edit in progress: the same drawn field, its
# focus, its text and its cursor. The plug leaves the bar again at the
# end, as the harness started it. A plugin's page opens on Settings, and its tab strip shows
# Details and returns by the pointer and by the keyboard; a copy that opens
# on Details is the control. A summonable plugin's page draws Open, which
# opens the plugin's window or panel through the manager. A mouse drag leaves a page where it was, while a wheel notch and
# Tab scroll it, and a two-finger swipe moves it as far as GTK moves a list. The
# Setup section draws the screen an offered step opens as that step, first
# and primary, and a screen that lacks a command it needs disabled with a
# reason naming it. Dispatches asked for back to back run in order behind one
# process, the queue has a bound, and a process that cannot start does not
# stop the queue.
# A setting description's link opens its address through the desktop open
# route, by the pointer and by Return, into a stand-in that records it.
# inputs: shell/Core/PluginLogic.js shell/plugins/vgs.settings/* shell/Ui/layout/ScrollArea.qml shell/Ui/layout/TouchpadScroll.qml shell/Ui/layout/TouchpadScrollLogic.js shell/Commons/Reply.js shell/plugins/vgs.notifications/* scripts/smoke/fixtures/plugins/acme.status/* scripts/smoke/fixtures/plugins/acme.probe/* scripts/smoke/fixtures/plugins/acme.bare/* shell/Core/Dispatch.js shell/Core/Compositor.qml shell/Core/Config.qml shell/Core/PluginStatus.qml bin/vgshell-scan shell/Core/TuiRunner.qml shell/Commons/SettingValues.js shell/Core/Capabilities.qml shell/Core/Registry.qml shell/Core/Plugins.qml shell/Hosts/SummonHost.qml shell/Hosts/SummonLayer.qml shell/Hosts/AppWindow.qml shell/plugins/vgs.bar/manifest.json shell/plugins/vgs.jarvis/manifest.json shell/plugins/vgs.gallery/manifest.json shell/plugins/vgs.themes/manifest.json shell/plugins/vgs.devtools/manifest.json shell/Core/Notices.qml bin/lib/qml-library.js scripts/smoke/rows/manager.sh scripts/smoke/rows/status.sh scripts/smoke/rows/capabilities.sh scripts/smoke/rows/plugins.sh bin/vgshell-tui shell/Ui/layout/TabPages.qml shell/Ui/layout/Tabs.qml shell/Ui/foundation/KeyNav.qml shell/Ui/controls/RowAction.qml shell/Ui/controls/Field.qml shell/Ui/feedback/LinkText.qml shell/Commons/DesktopLaunch.js
set -euo pipefail
click_centre "$(bar_key)" vgs.settings || fail "the click on the gear failed"
expect_poll "the gear's click opens the Settings window" open settings_open
expect "the window opens the fixture's page" ok ipc smoke invokeInstance window vgs.settings openPlugin acme.probe
expect_poll "the page draws the fixture's fields again" '[9, 0]' page_fields

# A setting description's link opens its address through the desktop open
# route by the pointer and by Return. The row stands a `gio` that records
# its argv in the shell's stand-in directory, so no browser starts and
# nothing leaves the sandbox. The fixture's Compact description is its
# link's words alone, so a click at its centre lands on the link. Two Tabs
# from the Gap field's editor pass the Compact switch to the link.
link_argv="$sandbox/gio-argv"
cat >"$shim/gio" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>$(printf %q "$link_argv")
EOF
chmod 755 "$shim/gio"
link_opens() { if [[ -f $link_argv ]]; then python3 -c 'import json,sys; print(json.dumps(open(sys.argv[1]).read().splitlines()))' "$link_argv"; else echo '[]'; fi; }
link_focus() { page_focus | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)[:2]))'; }
link_click() {
  local rect x y
  rect="$(ipc smoke windowGeometry window vgs.settings "$1" "$2")" || return 1
  [[ $rect == \[* ]] || { echo "link_click: no $1 $2: $rect" >&2; return 1; }
  read -r x y < <(at_centre window:Plugins "$rect") || return 1
  hover "$((x + 1))" "$y" || return 1
  click "$x" "$y"
}
link_click LinkText "Compact guide" || fail "the click on the Compact guide link failed"
expect_poll "a click on a description link opens its address" '["open https://example.invalid/compact"]' link_opens
link_click TextField 4 || fail "the click on the Gap field failed"
type_keys -k Tab -k Tab || fail "tabbing from the Gap field to the Compact guide link failed"
expect_poll "the Compact guide link is the Tab stop after the Compact switch" '["LinkText", "Compact guide"]' link_focus
type_keys -k Return || fail "pressing Return on the Compact guide link failed"
expect_poll "Return on a description link opens its address" '["open https://example.invalid/compact", "open https://example.invalid/compact"]' link_opens
rm -f -- "${shim:?}/gio" "${link_argv:?}"

# The plugin page's two pages (TabPages): an opened page shows Settings and
# draws nothing of Details. A click on the Details tab shows Details alone
# and a click on the Settings tab returns. On the keyboard Ctrl+Tab steps
# the page from the back button, which keeps the keyboard, and the strip is
# the Tab stop after the title: Right and Left on it change the page, Tab
# from it enters the shown page, and Ctrl+Tab from a control there steps the
# page and hands the strip the keyboard with its ring, so no hidden control
# keeps the keys. A change of the manager's rows keeps the page, another
# plugin's page opens on Settings, where a plugin with nothing below its
# switches says so in one line and, disabled, draws no hint to turn it on,
# and a page change returns the body to
# its top. A disposable fixture supplies both pages' content, independent
# of requirements or accounts on the host. The disabled Jarvis page is
# only the Enabled hint reader's control.
# The control, at the row's end, is a copy of the page that opens on
# Details, keeps its place and forwards no key to its pages, read by the
# same readers.
# page_shown: the page's index, then whether it draws the Enabled switch of
# Settings and the Source line of Details, the installed fixture's.
page_shown() {
  local index enabled listing
  index="$(settings_tab)" || return
  enabled="$(ipc smoke scopedWindowGeometry window vgs.settings Field Enabled Switch "")" || return
  [[ $enabled == \[* ]] && enabled=drawn
  listing="$(settings_label Installed)" || return
  printf '%s %s %s\n' "$index" "$enabled" "$listing"
}
page_focus() { ipc smoke focused window vgs.settings; }
focus_type() { page_focus | py_reply 'import json,sys; print(json.load(sys.stdin)[0])'; }
strip_focused='["Tabs","",true,true,true]'
page_top() { scroll_value contentY; }
# enabled_hint NAME: whether the page draws the Enabled switch's hint to
# turn plugin NAME on.
enabled_hint() { settings_label "Turn on $1 to change its settings and shortcuts."; }
# page_scrolled Y: reject insufficient fixture content as a setup error
# before judging scroll return. Probe.scrollTo reports the clamped position
# and both heights from the same scroll operation.
page_scrolled() {
  ipc smoke scrollTo window vgs.settings "$1" | py_reply '
import json,sys
d=json.load(sys.stdin)
wanted=int(sys.argv[1])
if not isinstance(d,list) or len(d)!=3:
    print(json.dumps({"setupError":"scroll-unavailable","reading":d}))
    sys.exit(2)
y,content,view=d
print("settings-scroll: requested=%s contentHeight=%s height=%s contentY=%s" % (wanted,content,view,y), file=sys.stderr)
if content-view < wanted:
    print(json.dumps({"setupError":"short-page","requested":wanted,"contentHeight":content,"height":view,"contentY":y}))
    sys.exit(2)
print(y)' "$1"
}
# Tab and plugin changes publish their index before Qt positions a Column's
# children. Wait on the fixture's measured range before its scroll assertion.
page_scroll_ready() {
  scroll_value contentHeight height | py_reply 'import json,sys; d=json.load(sys.stdin); print(d[0]-d[1] >= int(sys.argv[1]))' "$1"
}
# The short-page control consumes the setup category and its nonzero status.
page_scroll_short_control() {
  local got status=0
  got="$(page_scrolled 300)" || status=$?
  if [[ $status -ne 2 ]]; then printf 'unexpected-status=%s reading=%s\n' "$status" "$got"; return; fi
  printf '%s\n' "$got" | py_reply 'import json,sys; print(json.load(sys.stdin).get("setupError", "missing-category"))'
}
expect_poll "an opened page shows Settings and nothing of Details" "0 drawn absent" page_shown
expect "a plugin with settings draws no line that it has none" absent settings_label "This plugin has no other settings."
settings_details
expect_poll "a click on the Details tab shows Details and nothing of Settings" "1 absent drawn" page_shown
settings_tab_click Settings || fail "the click on the Settings tab failed"
expect_poll "a click on the Settings tab returns to Settings" "0 drawn absent" page_shown
expect "the window opens the fixture's page as a key opens it" ok ipc smoke invokeInstance window vgs.settings openPlugin acme.probe
expect_poll "a page a key opens holds the keyboard on its back button" IconButton focus_type
type_keys -M ctrl -k Tab -m ctrl || fail "sending Ctrl+Tab to the back button failed"
expect_poll "Ctrl+Tab from the back button shows Details" "1 absent drawn" page_shown
expect "the back button keeps the keyboard across the page change" IconButton focus_type
type_keys -M ctrl -k Tab -m ctrl || fail "sending a second Ctrl+Tab to the back button failed"
expect_poll "Ctrl+Tab from the back button steps round to Settings" "0 drawn absent" page_shown
type_keys -k Tab -k Tab || fail "tabbing from the back button to the strip failed"
expect_poll "the strip is the Tab stop after the title, with its ring" "$strip_focused" page_focus
type_keys -k Right || fail "sending Right to the strip failed"
expect_poll "Right on the strip shows Details" "1 absent drawn" page_shown
type_keys -k Left || fail "sending Left to the strip failed"
expect_poll "Left on the strip returns to Settings" "0 drawn absent" page_shown
type_keys -k Tab || fail "tabbing from the strip into the page failed"
expect_poll "Tab from the strip enters the shown page at its Enabled switch" Switch focus_type
type_keys -M ctrl -k Tab -m ctrl || fail "sending Ctrl+Tab to the page failed"
expect_poll "Ctrl+Tab from a control of the page shows Details" "1 absent drawn" page_shown
expect_poll "the strip takes the keyboard from the page that hid, with its ring" "$strip_focused" page_focus
expect "the window toggles the bare fixture off under Details" ok ipc smoke invokeInstance window vgs.settings toggle acme.bare
expect_poll "the window's rows show the bare fixture disabled" '{"acme.bare": false, "acme.probe": true, "vgs.bar": true}' manager_rows
expect "a change of the rows that keeps the plugin keeps its Details page" "1 absent drawn" page_shown
expect "the window toggles the bare fixture back on under Details" ok ipc smoke invokeInstance window vgs.settings toggle acme.bare
expect_poll "the window's rows show the bare fixture enabled again" '{"acme.bare": true, "acme.probe": true, "vgs.bar": true}' manager_rows
expect "the window opens the bare fixture's page from Details" ok ipc smoke invokeInstance window vgs.settings openPlugin acme.bare
expect_poll "another plugin's page opens on Settings" 0 settings_tab
expect_poll "a plugin with nothing below its switches says so on Settings" drawn settings_label "This plugin has no other settings."
expect "the window toggles the bare fixture off on its own page" ok ipc smoke invokeInstance window vgs.settings toggle acme.bare
expect_poll "the window's rows show the bare fixture disabled on its page" '{"acme.bare": false, "acme.probe": true, "vgs.bar": true}' manager_rows
expect "the disabled bare fixture's page still says it has no other settings" drawn settings_label "This plugin has no other settings."
expect "a disabled plugin with nothing to change draws no hint to turn it on" absent enabled_hint Bare
expect "the window toggles the bare fixture back on from its page" ok ipc smoke invokeInstance window vgs.settings toggle acme.bare
expect_poll "the window's rows show the bare fixture enabled after its page's readings" '{"acme.bare": true, "acme.probe": true, "vgs.bar": true}' manager_rows
expect "the window opens the Jarvis page" ok ipc smoke invokeInstance window vgs.settings openPlugin vgs.jarvis
expect_poll "the Jarvis page opens on Settings" 0 settings_tab
expect_poll "control: the disabled Jarvis page, with settings to change, draws the hint to turn it on" drawn enabled_hint Jarvis
# The short fixture reaches the same scroll reader, which must refuse it
# as setup rather than report a product failure or accept a clamped zero.
expect "the window opens the short page control" ok ipc smoke invokeInstance window vgs.settings openPlugin acme.bare
expect_poll "the short page control opens on Settings" 0 settings_tab
expect_poll "the short page control has insufficient scroll range" False page_scroll_ready 300
expect "control: insufficient page content is a setup error" short-page page_scroll_short_control

# Both pages get their length from this row's own manifest content. The
# service copy has no capabilities or host-dependent data.
scroll_fixture="$home/.config/vgshell/plugins/acme.settings-scroll"
mkdir -- "$scroll_fixture"
cp -- "$repo/scripts/smoke/fixtures/plugins/acme.bare/Service.qml" "$scroll_fixture/Service.qml"
python3 - "$repo/scripts/smoke/fixtures/plugins/acme.bare/manifest.json" "$scroll_fixture/manifest.json" <<'PYSCROLL'
import json,sys
from pathlib import Path
manifest=json.loads(Path(sys.argv[1]).read_text())
manifest.update(id="acme.settings-scroll",name="Scroll fixture",
    description="\n".join("Details fixture line %s" % n for n in range(40)),
    requirements=[],settings={"field%s" % n:False for n in range(40)},
    schema={"field%s" % n:{"type":"boolean","label":"Fixture field %s" % n} for n in range(40)})
with Path(sys.argv[2]).open("x") as file:
    json.dump(manifest,file)
PYSCROLL
rescan "a rescan picks the row-owned scroll fixture"
expect "the window opens the scroll fixture" ok ipc smoke invokeInstance window vgs.settings openPlugin acme.settings-scroll
expect_poll "the scroll fixture opens on Settings" 0 settings_tab
type_keys -k Tab -k Tab || fail "tabbing to the scroll fixture's strip failed"
expect_poll "the scroll fixture's strip holds the keyboard" "$strip_focused" page_focus
expect_poll "the fixture's Settings take the row's scroll: fixture content is ready" True page_scroll_ready 300
expect "the fixture's Settings take the row's scroll" 300 page_scrolled 300
type_keys -k Right || fail "sending Right to the scrolled page's strip failed"
expect_poll "Right shows the fixture's Details" 1 settings_tab
expect_poll "a page change returns the body to its top" '[0]' page_top
expect_poll "the fixture's Details take the row's scroll: fixture content is ready" True page_scroll_ready 300
expect "the fixture's Details take the row's scroll" 300 page_scrolled 300
type_keys -k Left || fail "sending Left to the scrolled page's strip failed"
expect_poll "Left shows the fixture's Settings" 0 settings_tab
expect_poll "the page change back returns the body to its top" '[0]' page_top

open_rows() { settings_rows | py_reply 'import json,sys; ids=("acme.probe","vgs.gallery","vgs.devtools","vgs.themes"); print(json.dumps({r["id"]: r["opens"] for r in json.load(sys.stdin) if r["id"] in ids}, sort_keys=True))'; }
open_button() { ipc smoke windowGeometry window vgs.settings Button Open | py_reply 'import sys; print("absent" if sys.stdin.read().strip() == "absent" else "drawn")'; }
shown_open_button() { ipc smoke shownWindowGeometry window vgs.settings Button Open | py_reply 'import sys; print("absent" if sys.stdin.read().strip() == "absent" else "drawn")'; }
themes_panel_open() {
  local geometry
  geometry="$(ipc smoke instanceGeometry panel vgs.themes)" || return
  [[ $geometry != absent ]] && echo open || echo closed
}
# open_click: a real click on the shown page's Open in the header, which no
# scroll reaches, the pointer moved there a pixel off first.
open_click() {
  local rect x y
  rect="$(ipc smoke windowGeometry window vgs.settings Button Open)" || return 1
  [[ $rect == \[* ]] || { echo "open_click: no Open: $rect" >&2; return 1; }
  read -r x y < <(at_centre window:Plugins "$rect") || return 1
  hover "$((x + 1))" "$y" || return 1
  click "$x" "$y"
}
# Open by keyboard first, while Settings holds the keyboard the strip rows
# left it; the pointer needs no keyboard, so no focus dispatch is sent.
expect "manager rows name each plugin's summonable surface" '{"acme.probe": "", "vgs.devtools": "window", "vgs.gallery": "window", "vgs.themes": "panel"}' open_rows
expect "the window opens the fixture's page for the Open control" ok ipc smoke invokeInstance window vgs.settings openPlugin acme.probe
expect "control: the fixture page without a window or panel draws no Open" absent open_button
expect "the window opens the bare fixture's page for the Open control" ok ipc smoke invokeInstance window vgs.settings openPlugin acme.bare
expect_poll "control: the bare fixture page draws no Open" absent open_button
expect "the window opens the Gallery page as a key opens it for Open" ok ipc smoke invokeInstance window vgs.settings openPlugin vgs.gallery
expect_poll "the Gallery page draws Open" drawn open_button
expect_poll "the Gallery page's back button holds the keyboard before Open" IconButton focus_type
type_keys -k Tab -k Tab || fail "tabbing to Gallery Open failed"
expect_poll "Open is the Tab stop after the title" Button focus_type
type_keys -k Return || fail "pressing Gallery Open with Return failed"
expect_poll "Open maps the Gallery window by keyboard" 1 window_count "VGS Components"
expect "hiding the Gallery window after the keyboard Open is allowed" ok ipc shell hide window vgs.gallery
expect_poll "the Gallery window is gone after the keyboard Open" 0 window_count "VGS Components"
open_click || fail "the click on Gallery Open failed"
expect_poll "Open maps the Gallery window by pointer" 1 window_count "VGS Components"
expect "hiding the Gallery window after the pointer Open is allowed" ok ipc shell hide window vgs.gallery
expect_poll "the Gallery window is gone after the pointer Open" 0 window_count "VGS Components"
expect "the window opens the Themes page for the Open control" ok ipc smoke invokeInstance window vgs.settings openPlugin vgs.themes
expect_poll "the Themes page draws Open" drawn open_button
open_click || fail "the click on Themes Open failed"
expect_poll "Open maps the Themes panel" open themes_panel_open
expect "hiding the Themes panel after Open is allowed" ok ipc shell hide panel vgs.themes
expect_poll "the Themes panel is gone after Open" closed themes_panel_open
expect "the window opens the Dev Tools page for the Open control" ok ipc smoke invokeInstance window vgs.settings openPlugin vgs.devtools
expect_poll "the Dev Tools page draws Open" drawn shown_open_button
expect "the disabled Dev Tools Open takes no press" absent open_button
expect "the window opens the fixture's page again for the edit rows" ok ipc smoke invokeInstance window vgs.settings openPlugin acme.probe
expect_poll "the fixture's page opens on Settings for the edit rows" "0 drawn absent" page_shown
held_rect="$(ipc smoke invokeInstance window vgs.settings holdField '{"id":"acme.probe","key":"label","text":"draft"}')" || fail "holdField failed"
if [[ $held_rect == \[* ]]; then ok "an edit begins in the fixture's label field"; else fail "an edit begins in the fixture's label field: got $held_rect"; fi
read -r field_cx field_cy < <(at_centre window:Plugins "$held_rect")
click "$field_cx" "$field_cy" || fail "the click on the held field failed"
held_state() { ipc smoke invokeInstance window vgs.settings heldFieldState ''; }
# The click also puts the cursor where it landed; the state read after it
# is what the unrelated changes must preserve.
held_focused() { held_state | py_reply 'import json,sys; d=json.load(sys.stdin); print(d["same"] and d["focus"] and d["activeFocus"] and d["text"] == "draft")'; }
expect_poll "the clicked field holds keyboard focus with its draft" True held_focused
held_before="$(held_state)" || fail "held field state unreadable"
expect "the window toggles the bare fixture off around the edit" ok ipc smoke invokeInstance window vgs.settings toggle acme.bare
expect_poll "the window shows the bare fixture disabled" '{"acme.bare": false, "acme.probe": true, "vgs.bar": true}' manager_rows
expect "the edit in progress survives the unrelated change" "$held_before" held_state
expect "the window toggles the bare fixture back on" ok ipc smoke invokeInstance window vgs.settings toggle acme.bare
expect_poll "the window shows the bare fixture enabled" '{"acme.bare": true, "acme.probe": true, "vgs.bar": true}' manager_rows
expect "the edit in progress survives the second unrelated change" "$held_before" held_state

config_changes() { ipc smoke configChanges; }
user_loads() { ipc smoke configUserLoads; }
user_label() { python3 -c 'import json,sys; print([e.get("label") for e in json.load(open(sys.argv[1])).get("plugins", []) if e["id"]=="acme.probe"][0])' "$home/.config/vgshell/shell.json"; }
if changes_before="$(config_changes)" && loads_before="$(user_loads)"; then
  expect "the window writes the fixture's setting" ok ipc smoke invokeInstance window vgs.settings applySetting '{"id":"acme.probe","key":"label","value":"published-once"}'
  expect_poll "the write's own file notification was read" "$((loads_before + 1))" user_loads
  expect "the user file holds the written setting" published-once user_label
  expect "one write is published once" "$((changes_before + 1))" config_changes
  expect_poll "the running service received the written setting" '"published-once"' read_service label
else
  fail "configuration counters unreadable before the write rows"
fi
# Two writes back to back: each lands before it answers, and the later one wins.
if changes_before="$(config_changes)"; then
  expect "the first of two rapid writes is accepted" ok ipc smoke invokeInstance window vgs.settings applySetting '{"id":"acme.probe","key":"label","value":"rapid-first"}'
  expect "the second of two rapid writes is accepted" ok ipc smoke invokeInstance window vgs.settings applySetting '{"id":"acme.probe","key":"label","value":"rapid-second"}'
  expect_poll "the user file holds the later of two rapid writes" rapid-second user_label
  expect "each rapid write is published once" "$((changes_before + 2))" config_changes
  expect "the running service holds the later rapid write" '"rapid-second"' read_service label
else
  fail "configuration counters unreadable before the rapid write rows"
fi
# Status rows, D037: a page draws each status entry its manifest does not
# keep from Settings, read-only, with its label, its value in the tone of
# its type and its hint, the entries without a group first; `data` and
# hidden entries are not drawn, an entry nothing published says so, and a
# disabled plugin's rows all say so. An entry draws its action button only
# while its step applies: the present token draws none, the absent one draws
# Set up token, and a disabled plugin's row none. The status fixture,
# which rows/status.sh left disabled, publishes; the notifications, which
# the harness starts disabled, have published nothing.
# The drawn texts of the Token row, the Sync group's first.
token_drawn() { drawn_status | py_reply 'import json,sys; r=[r for r in json.load(sys.stdin) if r and r[0] == "Token"]; print(json.dumps(r[0] if len(r) == 1 else "rows=%d" % len(r)))'; }
status_of() { settings_rows | py_reply 'import json,sys; r=[p for p in json.load(sys.stdin) if p["id"] == sys.argv[1]][0]["status"]; print(json.dumps([[s["label"], s["report"], s["value"], s["tone"]] for s in r]))' "$1"; }
drawn_status() { ipc smoke itemTexts window vgs.settings StatusRow | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)))'; }
page_fields_of() { ipc smoke drawnFields window vgs.settings | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps([d[sys.argv[1]], sum(v for k, v in d.items() if k != sys.argv[1])]))' "$1"; }
# The drawn rows with the `Last check` value replaced by `time` when it
# draws the fixture's moment as a local date and time: it names that
# moment's hour and minute, in the 24-hour or the 12-hour form, and not the
# raw milliseconds. A row then compares the rows whatever the locale's date
# order, and a page that draws the number itself fails.
fixture_time=1790650695194
drawn_status_timeless() { drawn_status | py_reply '
import datetime, json, sys
moment = datetime.datetime.fromtimestamp(int(sys.argv[1]) / 1000)
clocks = ("%02d:%02d" % (moment.hour, moment.minute), "%d:%02d" % ((moment.hour - 1) % 12 + 1, moment.minute))
def shown(t): return "time" if sys.argv[1][:10] not in t and any(c in t for c in clocks) else t
print(json.dumps([[shown(t) for t in r] if r[0] == "Last check" else r for r in json.load(sys.stdin)]))' "$fixture_time"; }
expect "enabling the status fixture for its Status rows is allowed" ok ipc shell setPluginEnabled acme.status true
expect_poll "the status fixture's service published its first value" '"ok"' ipc smoke readInstance service acme.status startReply
expect "the fixture publishes a state" ok ipc acme.status invoke set 'check={"tone":"warning","text":"Two sources failed"}'
expect "the fixture publishes a count" ok ipc acme.status invoke set 'pending=3'
expect "the fixture publishes a time" ok ipc acme.status invoke set "lastCheck=$fixture_time"
expect "the fixture publishes data" ok ipc acme.status invoke detail ''
expect "the window opens the status fixture's page" ok ipc smoke invokeInstance window vgs.settings openPlugin acme.status
expect_poll "the status fixture's Settings page heads its one settings section" '["Settings"]' section_names
settings_details
expect_poll "the manager row lists each drawn entry in manifest order, with its value and tone" "$(python3 -c 'import json,sys; print(json.dumps([["Token", "reported", "present", "success"], ["Check", "reported", {"tone": "warning", "text": "Two sources failed"}, "warning"], ["Pending", "reported", 3, ""], ["Last check", "reported", int(sys.argv[1]), ""], ["Note", "unreported", None, ""]]))' "$fixture_time")" status_of acme.status
expect_poll "the page draws the ungrouped entries, then each group's, read-only, and no command for the present token" '[["Check", "Two sources failed"], ["Last check", "time"], ["Note", "Not reported"], ["Token", "Present", "Needed for the fixture'"'"'s sync"], ["Pending", "3"]]' drawn_status_timeless
expect_poll "Details head the status sections, then Requirements" '["Status", "Sync", "Requirements"]' section_names
expect "no Status row takes an edit" '[[],[],[],[],[]]' ipc smoke statusRowInputs window vgs.settings
expect "the page draws the choices setting only" '[1, 0]' page_fields_of acme.status

# Status actions, D061: an entry's action is offered while its published
# value calls for it, a presence while absent and a state while it says so,
# and its button runs the step through the manager: the fixture's own TUI
# in a floating terminal, or the requirement notice for its own command.
# The control comes first: a value that does not call for the action draws
# no button, and the manager refuses the act and starts nothing. The
# presses after it succeed, which clears each refusal from its line.
expected_errors+=('settings: acme\.status/(token|check) refused: action=(token|check) reason=not-offered')
terminal_stand_in
terminal_ready "the status actions"
expect_poll "values that do not call for them offer no action" '[["token", "Set up token", false], ["check", "Install the tool", false]]' offered_actions acme.status
expect_poll "the Token row draws no button and no command" '["Token", "Present", "Needed for the fixture'"'"'s sync"]' token_drawn
forget_record
expect "the manager refuses an act the token does not call for" "refused: action=token reason=not-offered" settings_act acme.status token
expect "the manager refuses an act the check does not call for" "refused: action=check reason=not-offered" settings_act acme.status check
expect "the refused acts started no terminal" absent recorded
expect "the refused acts raised no notice" null notice_shown
expect_poll "the refusal reads under the Token line" '["Token", "Present", "This setup step is not needed now."]' token_drawn
expect "the fixture publishes its token absent" ok ipc acme.status invoke set 'token="absent"'
expect_poll "an absent token offers Set up token and the check offers nothing" '[["token", "Set up token", true], ["check", "Install the tool", false]]' offered_actions acme.status
expect_poll "the Token row draws its Set up token action" '["Token", "Absent", "Set up token", "This setup step is not needed now."]' token_drawn
settings_press --type RowAction "Set up token" || fail "the click on Set up token failed"
expect_poll "Set up token hands the terminal the fixture's setup TUI" "$(words acme.status/setup tui/setup.sh)" recorded_tail
expect_poll "the step that ran clears the Token line's refusal" '["Token", "Absent", "Set up token", "Needed for the fixture'"'"'s sync"]' token_drawn
expect_run_end "the setup TUI's run ends" acme.status/setup
expect_poll "the setup TUI's terminal closes" 0 tui_windows
expect "the check publishes that its tool is missing" ok ipc acme.status invoke set 'check={"tone":"warning","text":"Tool missing","action":true}'
expect_poll "the check offers Install the tool" '[["token", "Set up token", true], ["check", "Install the tool", true]]' offered_actions acme.status
# The press scans before it raises: the last scan found the command, from a
# stand-in since removed with no rescan, so only a scan the press starts
# finds it missing, as the plugin's value says. A notice raised from the
# last scan would answer satisfied and show nothing.
fixture_requirement() { ipc smoke readInstance window vgs.settings plugins | py_reply 'import json,sys; r=[q["state"] for p in json.load(sys.stdin) if p["id"] == "acme.status" for q in p["requirements"] if q["name"] == "vgs-smoke-absent"]; print(r[0] if r else "unlisted")'; }
printf '#!/bin/sh\nexit 0\n' >"$shim/vgs-smoke-absent"
chmod 755 "$shim/vgs-smoke-absent"
rescan "a rescan with the fixture's command stood in starts"
expect_poll "the scan finds the fixture's command present" present fixture_requirement
rm -f -- "${shim:?}/vgs-smoke-absent"
expect "with the stand-in gone and no rescan the last scan still reads it present" present fixture_requirement
settings_press --type RowAction "Install the tool" || fail "the click on Install the tool failed"
expect_poll "Install the tool shows the requirement notice for its own command" '["acme.status", ["vgs-smoke-absent"], ["vgs-smoke-absent"], false]' notice_shown
expect "Install the tool leaves the Settings window open under the notice" 1 window_count Plugins
expect_poll "the action's notice holds the keyboard" true ipc smoke noticeFocused
type_keys -k Escape || fail "sending Escape to the action's notice failed"
expect_poll "Escape closes the action's notice" null notice_shown


# The same offered status step must use the requirement notice at the run
# boundary when its declared command is required and absent. The copy also
# lists the setup script, so the page draws its Setup button for the read
# after the controls.
status_manifest="$status_dir/manifest.json"
cp -- "$status_manifest" "$sandbox/status-action-manifest"
python3 - "$status_manifest" <<'PYTHON'
from pathlib import Path
import json, sys
path=Path(sys.argv[1])
assert not path.is_symlink()
manifest=json.loads(path.read_text())
requirement=next(row for row in manifest["requirements"] if row["command"]=="vgs-smoke-absent")
assert requirement["optional"] is True
requirement["optional"]=False
setup=manifest["tui"]["setup"]
assert "entry" not in setup
setup["entry"]={"label":"Token setup","icon":"key-round","group":"Smoke"}
path.write_text(json.dumps(manifest))
PYTHON
rescan "the fixture now declares its missing command required"
expect "the fixture republishes an absent token" ok ipc acme.status invoke set 'token="absent"'
expect_poll "Settings replaces the unavailable setup step with install" '[["token", "Install requirements", true], ["check", "Install the tool", false]]' offered_actions acme.status
forget_record
settings_press --type RowAction "Install requirements" || fail "the click on Install requirements failed"
expect_poll "the withheld TUI opens the existing requirement notice" '["acme.status", ["vgs-smoke-absent"], ["vgs-smoke-absent"], false]' notice_shown
expect "a missing requirement starts no setup terminal" absent recorded
# No install button is pressed. Escape dismisses the requirement notice.
expect_poll "the required action's notice holds the keyboard" true ipc smoke noticeFocused
type_keys -k Escape || fail "sending Escape to the required action's notice failed"
expect_poll "Escape closes the required action's notice" null notice_shown

# Jarvis's full required list exceeds the explicit-choice notice bound.
# Prefix the fixture's commands so host programs cannot satisfy them.
large_notice="$(node - "$status_manifest" "$repo/shell/plugins/vgs.jarvis/manifest.json" "$repo" <<'JS' | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)))'
const fs = require("fs");
const path = require("path");
const [fixture, jarvisFile, repo] = process.argv.slice(2);
const logic = require(path.join(repo, "bin/lib/qml-library.js")).load(path.join(repo, "shell/Core/PluginLogic.js"));
if (fs.lstatSync(fixture).isSymbolicLink()) throw new Error("fixture manifest is a symlink");
const manifest = JSON.parse(fs.readFileSync(fixture, "utf8"));
const jarvis = logic.validateManifest(JSON.parse(fs.readFileSync(jarvisFile, "utf8")), path.dirname(jarvisFile));
if (!jarvis.ok) throw new Error(jarvis.error);
const required = jarvis.manifest.requirements.filter(row => !row.optional);
if (required.length <= logic.NOTICE_OFFER_MAX) throw new Error("Jarvis list does not reach the notice subset bound");
manifest.requirements.push(...required.map(row => ({ command: "vgs-smoke-required-" + row.name, packages: row.packages, optional: row.optional, purpose: row.purpose })));
const judged = logic.validateManifest(manifest, path.dirname(fixture));
if (!judged.ok) throw new Error(judged.error);
fs.writeFileSync(fixture, JSON.stringify(manifest));
const missing = manifest.requirements.map(row => row.command || row.dbus.name);
process.stdout.write(JSON.stringify([manifest.id, missing, missing, false]));
JS
)" || fail "the full-required-list fixture could not be prepared"
large_commands="$(printf '%s\n' "$large_notice" | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)[1]))')" || fail "the full-required-list commands could not be read"
rescan "the status fixture carries Jarvis's full required list as absent stand-ins"
expect "the large-list fixture republishes an absent token" ok ipc acme.status invoke set 'token="absent"'
expect_poll "the large-list fixture offers install instead of setup" '[["token", "Install requirements", true], ["check", "Install the tool", false]]' offered_actions acme.status
forget_record
settings_press --type RowAction "Install requirements" || fail "the large-list install action could not be pressed"
expect_poll "the setup action opens the notice for the full missing list" "$large_notice" notice_shown
expect "the full missing list starts no setup terminal" absent recorded
expect_poll "the full-list notice holds the keyboard" true ipc smoke noticeFocused
type_keys -k Escape || fail "closing the large-list notice failed"
expect_poll "the full-list notice closes" null notice_shown

# Run copies of the real TUI owner against the same registered fixture.
# The control sends the full list through the bounded explicit choice.
python3 - "$repo/shell/Core" <<'PYTHON'
from pathlib import Path
import sys
root = Path(sys.argv[1])
source = (root / "TuiRunner.qml").read_text()
imports = 'import "PluginLogic.js" as Logic'
assert source.count(imports) == 1
source = source.replace(imports, 'import "../PluginLogic.js" as Logic\nimport qs.Core')
anchor = '    id: root\n'
assert source.count(anchor) == 1
source = source.replace(anchor, anchor + '''
    property string smokeAnswer: ""
    property var smokeMissing: []
    function smokeRun() {
        smokeMissing = Notices.missingOf("acme.status");
        smokeAnswer = runFor("acme.status", "setup");
    }
''')
needle = 'return Notices.requested(id, name);'
assert source.count(needle) == 1
mutant = source.replace(needle, 'return Notices.chosen(id, Notices.missingOf(id));')
assert mutant != source
controls = root / "TuiInstallControls"
controls.mkdir()
for name, text in [("TuiInstallGood", source), ("TuiInstallChosen", mutant)]:
    with (controls / (name + ".qml")).open("x") as file:
        file.write(text)
PYTHON
for control in TuiInstallGood TuiInstallChosen; do
  expect "the probe builds $control" ok ipc smoke popupLoad "$control" "$repo/shell/Core/TuiInstallControls/$control.qml" window vgs.settings '{}'
done
expect "the unchanged TUI owner runs the full-list request" ok ipc smoke popupCall TuiInstallGood smokeRun
expect "the unchanged owner accepts the full-list installation notice" '"ok"' ipc smoke popupRead TuiInstallGood smokeAnswer
expect_poll "the unchanged owner opens the full-list notice" "$large_notice" notice_shown
expect "the unchanged owner starts no terminal" absent recorded
expect_poll "the unchanged owner's notice holds the keyboard" true ipc smoke noticeFocused
type_keys -k Escape || fail "closing the unchanged owner's notice failed"
expect_poll "the unchanged owner's notice closes" null notice_shown
install_control_missing() { ipc smoke popupRead TuiInstallChosen smokeMissing | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)))'; }
expect "the explicit-choice control reaches the same request" ok ipc smoke popupCall TuiInstallChosen smokeRun
expect "control: the explicit choice receives the full declared missing array" "$large_commands" install_control_missing
expect "control: the explicit-choice route rejects the full list" '"refused: requirements=malformed"' ipc smoke popupRead TuiInstallChosen smokeAnswer
expect "control: the rejected route opens no installation notice" null notice_shown
expect "control: the rejected route starts no terminal" absent recorded
for control in TuiInstallGood TuiInstallChosen; do
  expect "the probe drops $control" ok ipc smoke popupDrop "$control"
  rm -- "$repo/shell/Core/TuiInstallControls/$control.qml" || fail "removing the $control source copy failed"
done
rmdir -- "$repo/shell/Core/TuiInstallControls" || fail "removing the TUI install control directory failed"
# The Setup section draws the token's offered step on its screen's action:
# with the token absent and the required list missing, Token setup draws
# as Install requirements, first and active, and its press, the
# manager's openTui, opens the notice and no terminal. With no step
# offered, the same screen draws disabled with a reason naming the missing
# command, since its press could only open that notice; the two readings
# are each other's control. The same button of a plugin missing nothing
# starts its terminal in rows/tui.sh.
# setup_buttons NAME: the Setup section's actions as [text, tone,
# enabled, whether its tooltip names NAME].
setup_buttons() { ipc smoke setupSection window vgs.settings | py_reply 'import json,sys; print(json.dumps([[b[0], b[1], b[2], sys.argv[1] in b[3]] for b in json.load(sys.stdin)["buttons"]]))' "$1"; }
settings_tab_click Settings || fail "the click back to the status fixture's Settings failed"
expect_poll "the status fixture's page shows Settings for its Setup button" 0 settings_tab
expect_poll "the offered step draws Token setup's screen as Install requirements, active" '[["Install requirements", "accent", true, false]]' setup_buttons vgs-smoke-absent
forget_record
settings_press --type RowAction "Install requirements" || fail "the click on the Setup section's Install requirements failed"
expect_poll "the Setup step of a plugin missing required commands opens the requirement notice" "$large_notice" notice_shown
expect "the Setup step starts no setup terminal" absent recorded
expect_poll "the Setup step's notice holds the keyboard" true ipc smoke noticeFocused
type_keys -k Escape || fail "closing the Setup step's notice failed"
expect_poll "the Setup step's notice closes" null notice_shown
expect "the fixture republishes a present token, which offers no step" ok ipc acme.status invoke set 'token="present"'
expect_poll "with no step offered, Token setup draws disabled with a reason naming the missing command" '[["Token setup", "accent", false, true]]' setup_buttons vgs-smoke-absent
expect "the fixture republishes the absent token" ok ipc acme.status invoke set 'token="absent"'
cp -- "$sandbox/status-action-manifest" "$status_manifest"
rescan "the fixture restores its optional requirement"


# The editor reads the service's choices, writes stable values rather than
# labels, and never writes on a status refresh. A missing configured value
# remains visible and stored. Node judge controls pin the shape, distinct
# ids, list and text bounds, empty-string reservation and retained values.
expect_poll "the status fixture's page shows Settings for its editor" 0 settings_tab
device_field() { ipc smoke invokeInstance window vgs.settings fieldChoice '{"id":"acme.status","key":"device"}'; }
device_state() { device_field | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps([d["index"],d["text"],d["value"],d["enabled"]]))'; }
device_model() { device_field | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["model"]))'; }
choose_device() { ipc smoke invokeInstance window vgs.settings chooseField "{\"id\":\"acme.status\",\"key\":\"device\",\"index\":$1}"; }
user_device() { python3 -c 'import json,sys; print(json.dumps(next(r["device"] for r in json.load(open(sys.argv[1]))["plugins"] if r["id"]=="acme.status")))' "$home/.config/vgshell/shell.json"; }
expect_poll "unreported choices draw an empty Select" '[-1, "", "", true]' device_state
expect "the fixture offers labeled device ids" ok ipc acme.status invoke set 'devices=[{"label":"Alpha","value":"a"},{"label":"Beta","value":"b"}]'
expect_poll "the Select draws the status labels and keeps automatic empty string" '[0, "First offered: Alpha", "", true]' device_state
expect "the Select contains the offered ids" '[{"label": "First offered: Alpha", "value": ""}, {"label": "Alpha", "value": "a"}, {"label": "Beta", "value": "b"}]' device_model
expect "choosing the second offered device is allowed" chosen choose_device 2
expect_poll "the file stores the stable id, not its label" '"b"' user_device
expect_poll "the service receives the chosen id" '"b"' ipc smoke readInstance service acme.status configuredDevice
choices_changes="$(config_changes)" || fail "configuration counter unreadable before choices refresh"
expect "the fixture removes the chosen id" ok ipc acme.status invoke set 'devices=[{"label":"Alpha","value":"a"}]'
expect_poll "the removed id remains selected and marked unavailable" '[2, "b (unavailable)", "b", true]' device_state
expect "the removed id stays in the user file" '"b"' user_device
expect "removing a choice writes no configuration" "$choices_changes" config_changes
expect "the fixture offers the configured id again, with a new label and order" ok ipc acme.status invoke set 'devices=[{"label":"Beta renamed","value":"b"},{"label":"Alpha","value":"a"}]'
expect_poll "the existing value follows its id rather than its old index" '[1, "Beta renamed", "b", true]' device_state
expect "a label and order refresh writes no configuration" "$choices_changes" config_changes
expect "the fixture publishes an empty choices list" ok ipc acme.status invoke set 'devices=[]'
expect_poll "an empty list keeps the configured id alone" '[0, "b (unavailable)", "b", true]' device_state
expect "an empty list writes no configuration" "$choices_changes" config_changes
expect "the fixture offers a device again" ok ipc acme.status invoke set 'devices=[{"label":"Beta renamed","value":"b"}]'
expect_poll "an offered device brings back the automatic entry" '[1, "Beta renamed", "b", true]' device_state
expect "the user can return to automatic selection" chosen choose_device 0
expect_poll "automatic selection stores empty string, not the first id" '""' user_device
expect "the fixture offers a new first device" ok ipc acme.status invoke set 'devices=[{"label":"Alpha","value":"a"}]'
expect_poll "automatic selection displays the new first offer without storing it" '[0, "First offered: Alpha", "", true]' device_state
expect "the empty string stays in the file" '""' user_device

# Preset fields: the Bar clock format is a datetime preset Select with a
# trailing Custom… entry. Presets write their stable format string. Custom…
# opens the custom row without writing, invalid datetime formats show the
# shared problem text and do not write, and a valid custom format writes
# once Enter is pressed in its field.
clock_field() { ipc smoke invokeInstance window vgs.settings fieldChoice '{"id":"vgs.bar","key":"clockFormat"}'; }
clock_state() { clock_field | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps([len(d["model"]), d["model"][-1]["label"], d["enabled"]]))'; }
clock_model() { clock_field | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["model"]))'; }
clock_model_edges() { clock_model | py_reply 'import json,sys; m=json.load(sys.stdin); print(json.dumps([m[0]["value"], m[-1]["label"]]))'; }
clock_previews() { ipc smoke invokeInstance window vgs.settings fieldPresetPreviews '{"id":"vgs.bar","key":"clockFormat"}'; }
clock_custom() { ipc smoke invokeInstance window vgs.settings fieldCustom '{"id":"vgs.bar","key":"clockFormat"}'; }
clock_custom_state() { clock_custom | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps([d["visible"], d["text"], d["error"], d["preview"] == d["formatted"], d["previewBox"][2] > 0]))'; }
choose_clock() { ipc smoke invokeInstance window vgs.settings chooseField "{\"id\":\"vgs.bar\",\"key\":\"clockFormat\",\"index\":$1}"; }
edit_clock_custom() { ipc smoke invokeInstance window vgs.settings editFieldCustom "$(python3 -c 'import json,sys; print(json.dumps({"id":"vgs.bar","key":"clockFormat","text":sys.argv[1]}))' "$1")"; }
user_clock() { python3 -c 'import json,sys; print(json.dumps(next(r["clockFormat"] for r in json.load(open(sys.argv[1])).get("plugins", []) if r["id"]=="vgs.bar")))' "$home/.config/vgshell/shell.json"; }
bar_reply() { ipc smoke readInstance window vgs.settings replies | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin).get("vgs.bar", "")))'; }
expect "the window opens the Bar page for preset field checks" ok ipc smoke invokeInstance window vgs.settings openPlugin vgs.bar
expect_poll "the clock format Select has every preset and Custom last" '[9, "Custom\u2026", true]' clock_state
expect "the clock preset model carries the current default first and Custom last" '["ddd d MMM  HH:mm", "Custom\u2026"]' clock_model_edges
expect_poll "every clock preset previews with Qt.formatDateTime" '[]' clock_previews
expect "choosing a clock preset is accepted" chosen choose_clock 4
expect_poll "the chosen clock preset writes its format" '"HH:mm"' user_clock
clock_changes="$(config_changes)" || fail "configuration counter unreadable before clock Custom"
expect "choosing Custom opens the row" chosen choose_clock 8
expect "choosing Custom writes no configuration" "$clock_changes" config_changes
expect_poll "the Custom row opens with the configured format and a drawn preview" '[true, "HH:mm", "", true, true]' clock_custom_state
expect "an invalid custom clock edit is typed into the editor" edited edit_clock_custom "'abc"
type_keys -k Return || fail "sending Return to the invalid custom clock format failed"
expect_poll "the invalid custom clock format shows the shared problem" '[true, "'\''abc", "Close the quoted text.", true, false]' clock_custom_state
expect "the invalid custom clock format writes nothing" "$clock_changes" config_changes
expect "the invalid custom clock format raises no manager refusal" '""' bar_reply
expect "a valid custom clock edit is typed into the editor" edited edit_clock_custom "yyyy-MM-dd HH:mm:ss"
expect "a typed custom clock format is not written before Enter" "$clock_changes" config_changes
type_keys -k Return || fail "sending Return to the valid custom clock format failed"
expect_poll "the valid custom clock format writes" '"yyyy-MM-dd HH:mm:ss"' user_clock

# A disposable SettingField keeps the same editor and observes apply.
# Each mutation keeps the code it tests and removes one guarantee.
choice_controls="$repo/shell/plugins/vgs.settings"
choice_source_revision() {
  "$repo/bin/vgshell-scan" --require-base "$repo/shell/plugins" |
    py_reply 'import json,sys; print(next(entry["revision"] for entry in json.load(sys.stdin) if entry["dir"] == sys.argv[1]))' "$choice_controls"
}
choice_revision_before="$(choice_source_revision)" || fail "the Settings source revision is unreadable before the controls"
python3 - "$choice_controls" <<'PYEDIT'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
source = (root / "SettingField.qml").read_text()
controls = [
    ("ChoicesGood", None, None),
    ("ChoicesNoModel", "model: dynamic ? root.choices : root.spec.options", "model: dynamic ? [] : root.spec.options"),
    ("ChoicesWriteLabel", "root.choices[index].value", "root.choices[index].label"),
    ("ChoicesNoBinding", "currentIndex = Qt.binding(() => configuredIndex);", "if (false) currentIndex = Qt.binding(() => configuredIndex);"),
]
for name, needle, replacement in controls:
    text = source
    if needle is not None:
        assert text.count(needle) == 1, (name, needle)
        text = text.replace(needle, replacement)
        assert text != source, name
    anchor = "    property var choices: []"
    assert text.count(anchor) == 1
    text = text.replace(anchor, anchor + """
    property var smokeApplied: null
    onApply: v => smokeApplied = v
    readonly property int smokeCount: loader.item === null ? -1 : loader.item.count
    readonly property int smokeIndex: loader.item === null ? -1 : loader.item.currentIndex
    function smokeChoose() { loader.item.choose(1); }
""")
    (root / (name + ".qml")).write_text(text)
PYEDIT
choice_props='{"spec":{"type":"string","label":"Device","optionsFrom":"devices"},"value":"","choices":[{"label":"First offered: Alpha","value":""},{"label":"Alpha","value":"a"}]}'
for control in ChoicesGood ChoicesNoModel ChoicesWriteLabel ChoicesNoBinding; do
  expect "the probe builds $control" ok ipc smoke popupLoad "$control" "$choice_controls/$control.qml" window vgs.settings "$choice_props"
done
expect "the unchanged field copy draws the model" 2 ipc smoke popupRead ChoicesGood smokeCount
expect "the control without the status model draws no choices" 0 ipc smoke popupRead ChoicesNoModel smokeCount
expect "the unchanged copy chooses an offered item" ok ipc smoke popupCall ChoicesGood smokeChoose
expect "the unchanged copy applies the stable value" '"a"' ipc smoke popupRead ChoicesGood smokeApplied
expect "the unchanged copy restores the configured index after an unsaved choice" 0 ipc smoke popupRead ChoicesGood smokeIndex
expect "the label-writing control chooses the same item" ok ipc smoke popupCall ChoicesWriteLabel smokeChoose
expect "the label-writing control breaks stable-value readback" '"Alpha"' ipc smoke popupRead ChoicesWriteLabel smokeApplied
expect "the no-binding control chooses the same item" ok ipc smoke popupCall ChoicesNoBinding smokeChoose
expect "the no-binding control leaves an unsaved index selected" 1 ipc smoke popupRead ChoicesNoBinding smokeIndex
choice_revision_with_controls="$(choice_source_revision)" || fail "the Settings source revision is unreadable with the controls"
if [[ $choice_revision_with_controls != "$choice_revision_before" ]]; then
  ok "control: leaving generated copies changes the Settings source revision"
else
  fail "control: generated copies did not change the Settings source revision"
fi
for control in ChoicesGood ChoicesNoModel ChoicesWriteLabel ChoicesNoBinding; do
  expect "the probe drops $control" ok ipc smoke popupDrop "$control"
  rm -- "$choice_controls/$control.qml" || fail "removing the $control source copy failed"
done
expect "dropping the controls restores the Settings source revision" "$choice_revision_before" choice_source_revision
expect "the window opens the status fixture's page again" ok ipc smoke invokeInstance window vgs.settings openPlugin acme.status
expect "disabling the status fixture from its page is allowed" ok ipc smoke invokeInstance window vgs.settings toggle acme.status
expect_poll "a disabled plugin's dynamic Select is read-only and has no offered choices" '[-1, "", "", false]' device_state
settings_details
expect_poll "a disabled plugin's rows all read not reported" '[["Check", "Not reported"], ["Last check", "Not reported"], ["Note", "Not reported"], ["Token", "Not reported", "Needed for the fixture'"'"'s sync"], ["Pending", "Not reported"]]' drawn_status
expect "the window opens the notifications' page" ok ipc smoke invokeInstance window vgs.settings openPlugin vgs.notifications
settings_details
slack_tokens_hint="Connect each workspace to show sender photos."
# The Slack token connection remains available when photos are off.
# A disabled plugin reports no account state and offers no token edit.
expect_poll "with Slack photos off the disabled notifications list the Slack tokens row unreported" '[["Slack tokens", "unreported", null, ""]]' status_of vgs.notifications
expect_poll "the page draws the Slack tokens row with its hint while photos are off" "$(python3 -c 'import json,sys; print(json.dumps([["Slack tokens", "Not reported", sys.argv[1]]]))' "$slack_tokens_hint")" drawn_status
# Changing the photos setting keeps the same supported connection path.
set_slack_photos on
expect_poll "the disabled notifications list the Slack tokens row unreported" '[["Slack tokens", "unreported", null, ""]]' status_of vgs.notifications
expect_poll "the page draws the Slack tokens row with its hint and no line per account" "$(python3 -c 'import json,sys; print(json.dumps([["Slack tokens", "Not reported", sys.argv[1]]]))' "$slack_tokens_hint")" drawn_status
expect "no Slack tokens row takes an edit" '[[]]' ipc smoke statusRowInputs window vgs.settings
set_slack_photos absent
expect_poll "turning photos off again keeps the Slack tokens row unreported" '[["Slack tokens", "unreported", null, ""]]' status_of vgs.notifications

# Pointer scrolling (docs/architecture/design-system.md § Pointer): a mouse drag on the page
# leaves it where it was, a wheel notch scrolls it, and Tab still scrolls
# each focused
# row into view. The control gives the same page Qt's left-button drag back
# through the probe, and the same drag then scrolls it.
settings_view() { ipc smoke viewHolding window vgs.settings Layout; }
settings_view_y() { settings_view | py_reply 'import json,sys; print(json.load(sys.stdin)["contentY"])'; }
settings_view_kind() { settings_view | py_reply 'import json,sys; v=json.load(sys.stdin); print(json.dumps([v["type"], v["acceptedButtons"]]))'; }
expect "the window opens the fixture's page for the scroll rows" ok ipc smoke invokeInstance window vgs.settings openPlugin acme.probe
expect_poll "the page draws the fixture's fields for the scroll rows" '[9, 0]' page_fields
expect "the page scrolls in a ScrollArea that takes no mouse button" '["ScrollArea", 0]' settings_view_kind
expect "a mouse drag on the page leaves it where it was" still view_pointer window:Plugins window vgs.settings Layout drag
expect "a wheel notch on the page scrolls it" moved view_pointer window:Plugins window vgs.settings Layout wheel
expect "control: the probe gives the page Qt's left-button drag" 0 ipc smoke setViewButtons window vgs.settings Layout 1
expect "control: the same drag then scrolls the page" moved view_pointer window:Plugins window vgs.settings Layout drag
expect "the page takes no mouse button again" 1 ipc smoke setViewButtons window vgs.settings Layout 0
# Touchpad scrolling (docs/architecture/design-system.md § Pointer): a two-finger swipe of
# 40 px of axis length moves the page as far as GTK moves a list, and a
# wheel notch still
# moves it Qt's own step, 72 px. The control turns the page's touchpad
# scroll off through the probe, and the same swipe then moves the page Qt's
# one pixel per pixel. Each starts from the page's top, which a long swipe
# up reaches. They run on the row's scroll fixture, whose forty fields
# leave the swipe the room view_swipe asks for, seven times its length, at
# the window's height (size.window.tallHeightShare); the probe fixture's
# page is shorter than that past the window. The Tab row after them reads
# the probe fixture's page again.
swipe_text="Fixture field 0"
expect "the window opens the scroll fixture for the touchpad rows" ok ipc smoke invokeInstance window vgs.settings openPlugin acme.settings-scroll
swipe_view_kind() { ipc smoke viewHolding window vgs.settings "$swipe_text" | py_reply 'import json,sys; print(json.load(sys.stdin)["type"])'; }
expect_poll "the scroll fixture's first field lies in the page's ScrollArea for the touchpad rows" ScrollArea swipe_view_kind
settings_travel() {
  view_travel window:Plugins window vgs.settings "$swipe_text" swipe -2000 0 >/dev/null || return 1
  "$@"
}
settings_swipe() { settings_travel view_swipe window:Plugins window vgs.settings "$swipe_text" 40; }
expect "a two-finger swipe moves the page as far as it moves a GTK list" as-gtk settings_swipe
expect "control: the probe turns the page's touchpad scroll off" true ipc smoke setViewTouchpad window vgs.settings "$swipe_text" false
expect "control: the same swipe then moves the page one pixel per pixel" as-qt settings_swipe
expect "the page's touchpad scroll is on again" false ipc smoke setViewTouchpad window vgs.settings "$swipe_text" true
expect "a wheel notch moves the page Qt's step" 72 settings_travel view_travel window:Plugins window vgs.settings "$swipe_text" wheel 1 80
expect "the window opens the fixture's page again for the Tab row" ok ipc smoke invokeInstance window vgs.settings openPlugin acme.probe
expect_poll "the page draws the fixture's fields again for the Tab row" '[9, 0]' page_fields
# Tab until the page scrolls, each focused item read in view. The control's
# drag can leave a flick running, so the page first holds one position for
# two readings 0.1 s apart, for up to 3 s.
settings_tab_reveal() {
  local before last focus now
  before="$(settings_view_y)" || return 1
  for _ in $(seq 1 30); do
    sleep 0.1
    last="$before"
    before="$(settings_view_y)" || return 1
    [[ $before == "$last" ]] && break
  done
  [[ $before == "$last" ]] || { printf 'unsettled contentY=%s\n' "$before"; return 0; }
  for _ in $(seq 1 40); do
    type_keys -k Tab || return 1
    focus="$(ipc smoke focused window vgs.settings)" || return 1
    python3 -c 'import json,sys; r=json.loads(sys.argv[1]); sys.exit(0 if isinstance(r, list) and len(r) == 5 and r[4] else 1)' "$focus" 2>/dev/null || { printf 'out-of-view=%s\n' "$focus"; return 0; }
    now="$(settings_view_y)" || return 1
    if [[ $now != "$before" ]]; then printf 'ok\n'; return 0; fi
  done
  printf 'not-scrolled contentY=%s\n' "$before"
}
expect "Tab scrolls the page to bring each focused row into view" ok settings_tab_reveal
rest_pointer || fail "moving the pointer off the Settings window failed"

expect "the gear closes the Settings window after the edit rows" ok ipc smoke invokeInstance "$(bar_key)" vgs.settings toggle ''
expect_poll "the Settings window is gone after the edit rows" 0 window_count Plugins
expect "taking the Settings plug off the bar after the edit rows is allowed" ok ipc shell setPluginPlaced vgs.settings false
expect_poll "the Settings plug left every bar" True gear_gone

# Control of the page rows: a copy of the Settings plugin whose page opens
# on Details, drops the return to the top and forwards no key to its
# pages. The same readers read the fixture's page open on Details, Ctrl+Tab
# from the back button leave the scroll fixture where it was, and that page
# keep the scroll the row gave it across a page change.
expected_errors+=('plugins: hidden by a higher-precedence plugin with the same id: vgs\.settings')
page_copy="$home/.config/vgshell/plugins/vgs.settings"
rm -rf -- "${page_copy:?}"
mkdir -p -- "$(dirname -- "$page_copy")"
cp -R -- "$repo/shell/plugins/vgs.settings" "$page_copy"
if python3 - "$page_copy/PluginPage.qml" <<'PYCOPY'
import sys
path = sys.argv[1]
text = open(path).read()
for old, new in (("        tabs.currentIndex = 0;\n", "        tabs.currentIndex = 1;\n"),
                 ("                        layout.scrollArea.contentY = 0;\n", ""),
                 ("    Keys.forwardTo: [tabs]\n", "")):
    if text.count(old) != 1:
        sys.exit("%r occurs %d times" % (old, text.count(old)))
    text = text.replace(old, new)
open(path, "w").write(text)
PYCOPY
then ok "the page control opens on Details, drops the return to the top and forwards no key"; else fail "the page control could not be written"; fi
rescan "a rescan picks the page control"
settings_page_open acme.probe
expect_poll "control: a page copy that opens on Details reads Details" "1 absent drawn" page_shown
expect "control: the copy opens the scroll fixture" ok ipc smoke invokeInstance window vgs.settings openPlugin acme.settings-scroll
expect_poll "control: the copy's scroll fixture opens on Details too" 1 settings_tab
type_keys -M ctrl -k Tab -m ctrl || fail "control: sending Ctrl+Tab to the copy's back button failed"
type_keys -k Tab -k Tab || fail "control: tabbing to the copy's strip failed"
expect_poll "control: the copy's strip holds the keyboard" "$strip_focused" page_focus
expect "control: a page that forwards no key leaves Ctrl+Tab from the back button unanswered" 1 settings_tab
expect_poll "control: the copy's Details take the row's scroll: fixture content is ready" True page_scroll_ready 300
expect "control: the copy's Details take the row's scroll" 300 page_scrolled 300
type_keys -k Left || fail "control: sending Left to the copy's strip failed"
expect_poll "control: Left shows the copy's Settings" 0 settings_tab
expect_poll "control: the copy's Settings content is ready" True page_scroll_ready 300
expect "control: a page that drops the return keeps its scroll across the page change" '[300]' page_top
settings_page_close acme.probe
rm -rf -- "${page_copy:?}"
rm -rf -- "${scroll_fixture:?}"
rescan "a rescan drops the page control and scroll fixture"

# The dispatch queue, driven through the fixture's compositor capability.
# Every queue row ends on workspace 2 and is reset to workspace 1 without
# a row of its own; the reset is the same dispatch the row just proved.
reset_workspace() { probe dispatch "focusWorkspace 1" >/dev/null && expect_poll "the compositor is back on the first workspace" 1 active_ws; }
expect "two workspace requests are accepted back to back" "ok,ok" probe batch "focusWorkspace 2;focusWorkspace 1"
expect_poll "the compositor ends on the later of two queued requests" 1 active_ws
expect "two workspace requests in the other order are accepted" "ok,ok" probe batch "focusWorkspace 1;focusWorkspace 2"
expect_poll "the compositor ends on the later request in that order too" 2 active_ws
reset_workspace
if queue_limit="$(node -e 'process.stdout.write(String(require("./bin/lib/qml-library.js").load("shell/Core/Dispatch.js").QUEUE_LIMIT))')"; then
  expected_errors+=('compositor: refused: dispatch-queue=full ')
  overflow() { probe flood "$((queue_limit + 2)) focusWorkspace 1" | sed 's/ request=.*//'; }
  expect "the request past the queue bound is refused" "refused: dispatch-queue=full limit=$queue_limit" overflow
  # The overflow leaves the queue full until the request running at the
  # time finishes, and a request refused as full is not queued, so the
  # request is repeated until one is accepted. Under 40 busy loops on the
  # owner's machine (host cachy, AMD Ryzen 9 9950X, 32 threads) on
  # 2026-09-27, eleven runs of an instrumented copy of this row under
  # scripts/qml-smoke.sh saw acceptance within 187 ms after at most one
  # refusal, and the queue drain behind it within 1693 ms; expect_poll
  # polls both at 0.2 s for up to 5 s.
  expect_poll "a request after the overflow is accepted" ok probe dispatch "focusWorkspace 2"
  expect_poll "the queue drains after the overflow" 2 active_ws
  reset_workspace
else
  fail "Dispatch.QUEUE_LIMIT unreadable"
fi
# A hyprctl that cannot start: the request is logged as a failed start and
# the next request runs.
expected_errors+=('compositor: dispatch-start=failed ')
shim_hyprctl unstartable
expect "a request whose process cannot start is accepted" ok probe dispatch "focusWorkspace 2"
expect_log "the failed start is logged with its request" 1 'compositor: dispatch-start=failed request='
shim_hyprctl real
expect "a request after the failed start is accepted" ok probe dispatch "focusWorkspace 2"
expect_poll "the queue runs again after a failed start" 2 active_ws
reset_workspace
