# Unsaved edits on a Settings page (settings-window.md). The row installs
# its own fixture, acme.unsaved, whose page draws an unbounded number, Gap,
# in a text field, a preset string, Label, with its Custom text field, a
# list, Notes, whose one item holds a number, Size, in a text field and a
# switch, Wide, and Open for the fixture's window, and works it with the
# nested seat's pointer
# and keys. A typed value shows
# the save bar and writes nothing, and a loss of focus writes nothing
# either. Discard puts the saved value back; Save writes shell.json, the
# bar reads Saved and leaves; Ctrl+S writes every edited field; Enter
# writes the field it is pressed in and Escape there puts that field back.
# A list item's typed value waits the same way and outlives a write of the
# list by the item's switch, and the bar's Save, pressed by the keyboard, hands the
# keyboard to the tab strip as it leaves. A value the manager refuses stays
# in its field with the bar, and the prompt's Save with one stays on the
# page. Open summons the fixture's window and asks nothing. With an
# edit pending, the Details tab by a click and by Ctrl+Tab, the back
# button, Escape, a jump to another plugin, a deep link to another page and
# a hide by the shell each raise one prompt: Escape, a press beside the
# card and Cancel stay, Discard leaves without a write and Save writes and
# leaves; a deep link to the page shown asks nothing, and a second hide
# raises no second prompt. A close through Hyprland asks nothing and writes
# nothing, and a plugin disabled under an edit drops it. On the Settings
# plugin's own page a key typed as text waits the same way, as the page's
# only edit it holds the Details tab behind the prompt, and a refused one
# returns to its text entry.
# Controls. A copy of the Settings plugin, installed over the shipped one,
# whose text field writes when it loses focus, whose bar is bound to no
# edit, whose Discard and Ctrl+S do nothing and whose window asks nothing
# before it leaves: the same readers read a write after Tab, a bar that
# stays after Save, a typed value that outlives Discard, no write on Ctrl+S
# and a page left at once with no prompt. A copy of the tree whose list
# hands its item fields no set and keys its items by nothing, whose page
# moves no keyboard when its last edit goes, whose key field
# reads its text entry's visibility, whose window host asks no instance
# before it hides and whose window leaves after a refused save: the same
# readers read no bar over a list item's typed value and that value gone
# after the switch's write, the keyboard off the strip after the bar's Save,
# Details shown over a typed key with no prompt, a hide that closes the
# window with its edit lost and a page popped with its refused value.
# No latency is measured; each reading polls every 200 ms for up to 5 s.
# The bar holds its Saved line for saveBar.duration, 1600 ms, and fades for
# motion.duration.normal, 150 ms (Tokens.js), so the control waits 3 s
# before it reads a bar still drawn.
# inputs: shell/plugins/vgs.settings/* scripts/smoke/fixtures/plugins/acme.unsaved/* shell/Ui/feedback/SaveBar.qml shell/Ui/feedback/Dialog.qml shell/Ui/foundation/Scrim.qml shell/Ui/controls/TextField.qml shell/Ui/controls/ShortcutField.qml shell/Ui/controls/BindField.qml shell/Ui/controls/Button.qml shell/Ui/layout/Pane.qml shell/Ui/layout/TabPages.qml shell/Ui/layout/Tabs.qml shell/Hosts/SummonHost.qml shell/Hosts/AppWindow.qml shell/Hosts/PluginSlot.qml shell/Core/Plugins.qml shell/Core/Registry.qml shell/Core/Capabilities.qml shell/Core/Config.qml shell/Core/PluginLogic.js shell/Commons/Reply.js shell/Commons/Tokens.js bin/vgshell bin/vgshell-scan
set -euo pipefail

us_id=acme.unsaved
us_file="$home/.config/vgshell/shell.json"
us_saved="$sandbox/shell-before-unsaved.json"
us_prompt_title="Save your changes?"
cp -- "$us_file" "$us_saved"

# us_value KEY: the fixture's setting KEY in the user file, as JSON, or
# `unset` while its row holds none.
us_value() { python3 -c 'import json,sys; rows=[r for r in json.load(open(sys.argv[1])).get("plugins", []) if r["id"] == sys.argv[2]]; print(json.dumps(rows[0][sys.argv[3]]) if rows and sys.argv[3] in rows[0] else "unset")' "$us_file" "$us_id" "$1"; }
# us_writes: the configuration changes the shell has published.
us_writes() { ipc smoke configChanges; }
# us_bar: the save bar's state: `unsaved` while the page holds an edit,
# `saved` while it draws its Saved line, `hidden` once it draws nothing.
us_bar() { ipc smoke itemValues window vgs.settings SaveBar dirty,saved,drawn,height | py_reply 'import json,sys; b=json.load(sys.stdin)[0]; print("hidden" if not b["drawn"] and b["height"] == 0 else "undrawn" if not b["drawn"] or b["height"] == 0 else "unsaved" if b["dirty"] else "saved" if b["saved"] else "fading")'; }
# us_bar_read: whether the bar's line last read Saved, which holds from the
# accepted save until the next edit, so no reading races the line's wait.
us_bar_read() { ipc smoke readDescendant window vgs.settings SaveBar saved; }
# us_text KEY: the text the fixture's field KEY draws in its text field.
us_text() { ipc smoke invokeInstance window vgs.settings fieldCustom "{\"id\":\"$us_id\",\"key\":\"$1\"}" | py_reply 'import json,sys; print(json.load(sys.stdin)["text"])'; }
us_focus() { ipc smoke activeFocusItem window vgs.settings; }
us_page() { ipc smoke readInstance window vgs.settings page; }
# us_prompt: True while the window draws its prompt.
us_prompt() { ipc smoke dialogCard window vgs.settings | py_reply 'import json,sys; print(json.load(sys.stdin)["shown"])'; }
us_prompt_press() { click_scoped_in window:Plugins window vgs.settings Dialog "$us_prompt_title" Button "$1"; }
us_bar_press() { click_scoped_in window:Plugins window vgs.settings SaveBar "Unsaved changes" Button "$1"; }
us_line() { [[ $(ipc smoke windowGeometry window vgs.settings Label "$1") == absent ]] && echo absent || echo drawn; }
# us_refused ID: whether the window holds a refusal for plugin ID's page.
us_refused() { ipc smoke readInstance window vgs.settings replies | py_reply 'import json,sys; print("refused" if json.load(sys.stdin).get(sys.argv[1], "") != "" else "none")' "$1"; }
# us_left TEXT: `left` once the text field drawing TEXT holds no keyboard.
us_left() { [[ $(us_focus) == "[\"DraftField\",\"$1\"]" ]] && echo held || echo left; }
# us_drawn TEXT: whether a setting's text field draws TEXT.
us_drawn() { [[ $(ipc smoke windowGeometry window vgs.settings DraftField "$1") == absent ]] && echo absent || echo drawn; }
# us_press TYPE TEXT: a click on the shown item of TYPE that reads TEXT,
# scrolled into view when a scroll area holds it, once two readings of its
# box 0.1 s apart match, for up to 3 s: a page that has just opened still
# slides. The pointer moves there a pixel off first, since a window mapped
# since the last press takes no click until the pointer moves
# (validation-smoke.md).
us_press() {
  local box="" last="" x y
  ipc smoke revealText window vgs.settings "$1" "$2" >/dev/null || return 1
  for _ in $(seq 1 30); do
    last="$box"
    box="$(ipc smoke windowGeometry window vgs.settings "$1" "$2")" || return 1
    [[ $box == \[* && $box == "$last" ]] && break
    sleep 0.1
  done
  [[ $box == \[* && $box == "$last" ]] || { echo "us_press: the $1 reading $2 never rested: $box" >&2; return 1; }
  read -r x y < <(at_centre window:Plugins "$box") || return 1
  hover "$((x + 1))" "$y" || return 1
  click "$x" "$y"
}
# us_field_press SHOWN: that click on the text field that draws SHOWN.
us_field_press() { us_press DraftField "$1"; }
# us_tab_to FOCUS: Tab, pressed until FOCUS, an us_focus reading, holds the
# keyboard, 12 times at most; each press waits up to 5 s for the keyboard
# to move.
us_tab_to() {
  local was now=""
  for _ in $(seq 1 12); do
    was="$(us_focus)" || return 1
    type_keys -k Tab || return 1
    for _ in $(seq 1 25); do
      now="$(us_focus)" || return 1
      [[ $now != "$was" ]] && break
      sleep 0.2
    done
    [[ $now == "$1" ]] && return 0
  done
  echo "us_tab_to: $1 never took the keyboard: $now" >&2
  return 1
}
# us_wide_press: a click on the list item's Wide switch.
us_wide_press() { click_scoped_in window:Plugins window vgs.settings SettingField Wide Switch ""; }
# us_strip: whether the page's tab strip holds the keyboard.
us_strip() { ipc smoke activeFocusWithin window vgs.settings Tabs; }
# us_edit LABEL SHOWN TYPED: that click, then TYPED over the field's
# selected text, as a user replaces a value.
us_edit() {
  us_field_press "$2" || { fail "$1: the click on the field failed"; return; }
  expect_poll "$1: the clicked field holds the keyboard" "[\"DraftField\",\"$2\"]" us_focus
  type_keys -M ctrl -k a -m ctrl || fail "$1: selecting the field's text failed"
  type_keys "$3" || fail "$1: typing failed"
  expect_poll "$1: the field draws the typed text" "[\"DraftField\",\"$3\"]" us_focus
}
# us_open: the fixture's page, shown by the window itself.
us_open() {
  expect "the window opens the fixture's page" ok ipc smoke invokeInstance window vgs.settings openPlugin "$us_id"
  expect_poll "the fixture's page draws its Gap field" drawn us_line Gap
}

install_plugin_copy acme.unsaved "$us_id" Unsaved
rescan "a rescan finds the unsaved-edits fixture"
expect "enabling the unsaved-edits fixture is allowed" ok ipc shell setPluginEnabled "$us_id" true
expect_poll "the fixture's service is built" True record_exists "$us_id"
settings_page_open "$us_id"
expect_poll "the Settings window is mapped for the edits" 1 window_count Plugins
expect_poll "the fixture's page draws its Gap field" drawn us_line Gap
expect "a page with no edit draws no save bar" hidden us_bar

# An edit, a loss of focus and Discard.
us_before="$(us_writes)" || fail "the configuration counter is unreadable before the edits"
us_edit "the Gap edit" 4 73
expect_poll "a typed value shows the save bar" unsaved us_bar
type_keys -k Tab || fail "tabbing out of the edited field failed"
expect_poll "Tab takes the keyboard from the edited field" left us_left 73
expect "the field keeps its typed text without the keyboard" 73 us_text gap
expect "a loss of focus writes no configuration" "$us_before" us_writes
expect "a loss of focus leaves the user file without the value" unset us_value gap
expect "the bar stays while the edit waits" unsaved us_bar
us_bar_press Discard || fail "the click on Discard failed"
expect_poll "Discard puts the saved value back" 4 us_text gap
expect_poll "the bar leaves after Discard" hidden us_bar
expect "Discard reads no Saved line" false us_bar_read
expect "Discard writes no configuration" "$us_before" us_writes

# Save.
us_edit "the Gap edit for Save" 4 73
us_bar_press Save || fail "the click on Save failed"
expect_poll "Save writes the value to the user file" 73 us_value gap
expect_poll "the bar reads Saved after the write" true us_bar_read
expect_poll "the bar leaves after its Saved line" hidden us_bar
expect "a click on Save leaves the keyboard in the field" '["DraftField","73"]' us_focus

# Ctrl+S writes every edited field.
us_edit "the Gap edit for Ctrl+S" 73 81
us_edit "the Label edit for Ctrl+S" probe gamma
expect_poll "two edits show one bar" unsaved us_bar
expect "the number is not written before Ctrl+S" 73 us_value gap
expect "the text is not written before Ctrl+S" unset us_value label
type_keys -M ctrl -k s -m ctrl || fail "sending Ctrl+S failed"
expect_poll "Ctrl+S writes the number" 81 us_value gap
expect_poll "Ctrl+S writes the text" '"gamma"' us_value label
expect_poll "the bar reads Saved after Ctrl+S" true us_bar_read
expect_poll "the bar leaves after Ctrl+S" hidden us_bar

# Enter writes one field, and Escape puts one back.
us_edit "the Label edit for Enter" gamma delta
us_edit "the Gap edit for Enter" 81 90
type_keys -k Return || fail "sending Return to the Gap field failed"
expect_poll "Enter writes the field it is pressed in" 90 us_value gap
expect "Enter leaves the other field's edit unwritten" '"gamma"' us_value label
expect "the bar stays for the other field's edit" unsaved us_bar
us_field_press delta || fail "the click on the edited Label field failed"
expect_poll "the edited Label field holds the keyboard" '["DraftField","delta"]' us_focus
type_keys -k Escape || fail "sending Escape to the edited field failed"
expect_poll "Escape in an edited field puts its saved value back" gamma us_text label
expect_poll "the bar leaves once no edit is left" hidden us_bar
expect "Escape in an edited field stays on the page" "\"$us_id\"" us_page
expect "Escape wrote nothing" '"gamma"' us_value label

# A list item's typed value waits, outlives a write of the list by the
# item's switch and is written by the bar's Save, which the keyboard
# presses here.
us_edit "the list item's edit" 33 34
expect_poll "a list item's typed value shows the save bar" unsaved us_bar
us_wide_press || fail "the click on the list item's switch failed"
expect_poll "the item's switch writes the list without the typed value" '[{"name": "1", "size": 33, "wide": true}]' us_value notes
expect "the list item keeps its typed value over the list's write" drawn us_drawn 34
expect "the bar stays for the list item's edit" unsaved us_bar
us_tab_to '["Button","Save"]' || fail "tabbing to the bar's Save failed"
type_keys -k Return || fail "pressing the bar's Save with Return failed"
expect_poll "the bar's Save writes the list with the item's value" '[{"name": "1", "size": 34, "wide": true}]' us_value notes
expect_poll "the strip takes the keyboard the bar's Save held" true us_strip
expect_poll "the bar leaves after the keyboard's Save" hidden us_bar

# A refused value stays in its field, with the bar and the reason.
expected_errors+=('settings: acme\.unsaved refused: setting=gap want=number')
us_edit "the refused Gap edit" 90 abc
type_keys -M ctrl -k s -m ctrl || fail "sending Ctrl+S for the refused value failed"
expect_log "the manager refuses the value as no number" 1 'settings: acme\.unsaved refused: setting=gap want=number'
expect_poll "the page holds the refusal" refused us_refused "$us_id"
expect "a refused value stays in its field" abc us_text gap
expect "a refused value keeps the bar" unsaved us_bar
expect "a refused value reads no Saved line" false us_bar_read
expect "a refused value is not written" 90 us_value gap
expect "back with the refused value is held" "refused: unsaved=$us_id" ipc smoke invokeInstance window vgs.settings back ''
expect_poll "back asks about the refused value" True us_prompt
expect_poll "the prompt for the refused value holds the keyboard on Save" '["Button","Save"]' us_focus
type_keys -k Return || fail "sending Return to the prompt for the refused value failed"
expect_log "the prompt's Save sends the refused value again" 2 'settings: acme\.unsaved refused: setting=gap want=number'
expect_poll "a refused Save closes the prompt" False us_prompt
expect "a refused Save stays on the page" "\"$us_id\"" us_page
expect "a refused Save stays on Settings" 0 settings_tab
expect "a refused Save keeps the typed text" abc us_text gap
expect "a refused Save leaves the stored value" 90 us_value gap
expect "a refused Save keeps the refusal" refused us_refused "$us_id"

# The Details tab, by a click and by the keyboard.
settings_tab_click Details || fail "the click on the Details tab failed"
expect_poll "the Details tab asks about the unsaved edit" True us_prompt
expect "the page stays on Settings while the prompt asks" 0 settings_tab
expect_poll "the prompt holds the keyboard on Save" '["Button","Save"]' us_focus
type_keys -k Escape || fail "sending Escape to the prompt failed"
expect_poll "Escape closes the prompt" False us_prompt
expect "Escape in the prompt stays on Settings" 0 settings_tab
expect "Escape in the prompt keeps the edit" abc us_text gap
type_keys -M ctrl -k Tab -m ctrl || fail "sending Ctrl+Tab with an unsaved edit failed"
expect_poll "Ctrl+Tab asks about the unsaved edit" True us_prompt
expect "the page stays on Settings under the second prompt" 0 settings_tab
us_prompt_press Discard || fail "the click on the prompt's Discard failed"
expect_poll "Discard in the prompt shows Details" 1 settings_tab
expect "Discard in the prompt closes it" False us_prompt
expect "Discard in the prompt writes nothing" 90 us_value gap
settings_tab_click Settings || fail "the click back to the Settings tab failed"
expect_poll "the page shows Settings again" 0 settings_tab
expect_poll "the discarded field draws its saved value" 90 us_text gap

# The back button, a press beside the prompt, Escape and the prompt's Save.
us_edit "the Gap edit for back" 90 55
expect "back with an unsaved edit is held" "refused: unsaved=$us_id" ipc smoke invokeInstance window vgs.settings back ''
expect_poll "back asks about the unsaved edit" True us_prompt
expect "the page is not left while the prompt asks" "\"$us_id\"" us_page
if us_box="$(surface_box window:Plugins)" && read -r us_x us_y < <(python3 -c 'import json,sys; b=json.loads(sys.argv[1]); print(int(b[0] + 12), int(b[1] + 12))' "$us_box"); then
  hover "$((us_x + 1))" "$us_y" || fail "moving the pointer beside the prompt failed"
  click "$us_x" "$us_y" || fail "the press beside the prompt failed"
else
  fail "the Settings window's box is unreadable for the press beside the prompt"
fi
expect_poll "a press beside the prompt closes it" False us_prompt
expect "a press beside the prompt stays on the page" "\"$us_id\"" us_page
expect "a press beside the prompt keeps the edit" 55 us_text gap
expect_poll "the edited field has the keyboard back" '["DraftField","55"]' us_focus
type_keys -k Tab || fail "tabbing out of the edited field before Escape failed"
expect_poll "Tab leaves the edited field before Escape" left us_left 55
type_keys -k Escape || fail "sending Escape with an unsaved edit failed"
expect_poll "Escape on the page asks about the unsaved edit" True us_prompt
expect "the page is not popped while the prompt asks" "\"$us_id\"" us_page
type_keys -k Return || fail "sending Return to the prompt failed"
expect_poll "Save in the prompt writes the edit" 55 us_value gap
expect_poll "Save in the prompt then pops the page" '""' us_page
expect "Save in the prompt closes it" False us_prompt

# A jump to another plugin and a deep link.
us_open
us_edit "the Gap edit for the jump" 55 60
us_before="$(us_writes)" || fail "the configuration counter is unreadable before Open"
us_press Button Open || fail "the click on Open failed"
expect_poll "Open maps the fixture's window" 1 window_count Unsaved
expect "Open with an unsaved edit asks nothing" False us_prompt
expect "Open stays on the page" "\"$us_id\"" us_page
expect "Open keeps the typed text" 60 us_text gap
expect "Open keeps the save bar" unsaved us_bar
expect "Open writes no configuration" "$us_before" us_writes
expect "Open leaves the user file as it was" 55 us_value gap
expect "hiding the window Open summoned is allowed" ok ipc shell hide window "$us_id"
expect_poll "the window Open summoned is gone" 0 window_count Unsaved
expect "a jump to another plugin is held" "refused: unsaved=$us_id" ipc smoke invokeInstance window vgs.settings openPlugin vgs.settings
expect_poll "the jump asks about the unsaved edit" True us_prompt
us_prompt_press Cancel || fail "the click on the prompt's Cancel failed"
expect_poll "Cancel closes the prompt" False us_prompt
expect "Cancel stays on the page" "\"$us_id\"" us_page
expect "a deep link to the page shown is allowed" ok ipc shell summon window vgs.settings "{\"plugin\":\"$us_id\"}"
expect "a deep link to the page shown asks nothing" False us_prompt
expect "a deep link to the page shown keeps the edit" 60 us_text gap
expect "a deep link to another page is allowed" ok ipc shell summon window vgs.settings '{"plugin":"vgs.settings"}'
expect_poll "a deep link to another page asks about the unsaved edit" True us_prompt
expect "the deep link waits on the page shown" "\"$us_id\"" us_page
expect_poll "the summon leaves the keyboard on the prompt" '["Button","Save"]' us_focus
us_prompt_press Discard || fail "the click on Discard for the deep link failed"
expect_poll "Discard then opens the linked page" '"vgs.settings"' us_page
expect "Discard for the deep link writes nothing" 55 us_value gap

# A hide by the shell: its IPC and the plugin's own toggle.
expected_errors+=('settings: toggle refused: held=vgs\.settings')
us_open
us_edit "the Gap edit for the hide" 55 61
expect "a hide with an unsaved edit is held" "refused: held=vgs.settings" ipc shell hide window vgs.settings
expect_poll "the hide asks about the unsaved edit" True us_prompt
expect "the window stays open while the prompt asks" 1 window_count Plugins
expect "a second hide is held the same" "refused: held=vgs.settings" ipc shell hide window vgs.settings
type_keys -k Escape || fail "sending Escape to the hide's prompt failed"
expect_poll "one Escape closes the prompt after two hides" False us_prompt
sleep 0.5 # A second prompt queued behind the first would show within a frame.
expect "no second prompt follows" False us_prompt
expect "the window stays open after Cancel" 1 window_count Plugins
expect "Cancel keeps the edit under the held hide" 61 us_text gap
expect "the plugin's toggle is held too" "refused: held=vgs.settings" ipc vgs.settings invoke toggle ''
expect_poll "the toggle asks about the unsaved edit" True us_prompt
us_prompt_press Save || fail "the click on Save for the toggle failed"
expect_poll "Save writes the edit before the window hides" 61 us_value gap
expect_poll "the window then hides itself" 0 window_count Plugins
expect_poll "the host dropped the hidden window's instance" absent us_page

# A close through Hyprland asks nothing and writes nothing.
expect "Settings is summoned on the fixture's page again" ok ipc shell summon window vgs.settings "{\"plugin\":\"$us_id\"}"
expect_poll "the Settings window maps again" 1 window_count Plugins
expect_poll "the reopened page draws its Gap field" drawn us_line Gap
us_edit "the Gap edit for the close" 61 62
us_before="$(us_writes)" || fail "the configuration counter is unreadable before the close"
if us_address="$(window_address Plugins)" && [[ $us_address == 0x* ]]; then
  expect "a close dispatch aimed at the window answers ok" ok hypr dispatch "hl.dsp.window.close({ window = \"address:$us_address\" })"
  expect_poll "the close dispatch closes the window with its unsaved edit" 0 window_count Plugins
  expect_poll "the host dropped the closed window's instance" absent us_page
  expect "a closed window writes no configuration" "$us_before" us_writes
  expect "a closed window leaves the user file as it was" 61 us_value gap
else
  fail "the Settings window's address is unreadable: ${us_address:-}"
fi

# A plugin disabled under an edit drops it and asks nothing.
expect "Settings is summoned on the fixture's page for the disable" ok ipc shell summon window vgs.settings "{\"plugin\":\"$us_id\"}"
expect_poll "the Settings window maps for the disable" 1 window_count Plugins
expect_poll "the page draws its Gap field for the disable" drawn us_line Gap
us_edit "the Gap edit for the disable" 61 63
expect_poll "the edit shows the bar before the disable" unsaved us_bar
expect "disabling the fixture under its edit is allowed" ok ipc shell setPluginEnabled "$us_id" false
expect_poll "a disabled plugin's field draws its saved value" 61 us_text gap
expect_poll "a disabled plugin's page draws no bar" hidden us_bar
expect "a disabled plugin's page is left with no prompt" ok ipc smoke invokeInstance window vgs.settings back ''
expect "no prompt shows for the disabled plugin" False us_prompt
expect "enabling the fixture again is allowed" ok ipc shell setPluginEnabled "$us_id" true
expect_poll "the fixture's service is built again" True record_exists "$us_id"

# A key typed as text, on the Settings plugin's own page.
expected_errors+=('settings: vgs\.settings refused: key=toggle ')
expect "the window opens the Settings plugin's own page" ok ipc smoke invokeInstance window vgs.settings openPlugin vgs.settings
expect_poll "the Settings shortcut's Keys row is drawn" false settings_key_field typing
us_before="$(us_writes)" || fail "the configuration counter is unreadable before the key"
expect "the Keys row's text entry opens" typing settings_key_invoke typeKeyField
type_keys "shift+super+k" || fail "typing the key failed"
expect_poll "a typed key shows the save bar" unsaved us_bar
type_keys -k Tab || fail "tabbing out of the key's text entry failed"
expect "the text entry stays open without the keyboard" true settings_key_field typing
expect "a typed key is not written by a loss of focus" "$us_before" us_writes
settings_tab_click Details || fail "the click on the Details tab over the typed key failed"
expect_poll "the Details tab asks about a typed key, the page's only edit" True us_prompt
expect "the page stays on Settings over the typed key" 0 settings_tab
type_keys -k Escape || fail "sending Escape to the typed key's prompt failed"
expect_poll "Escape closes the typed key's prompt" False us_prompt
expect "the typed key stays in its text entry" true settings_key_field typing
type_keys -M ctrl -k s -m ctrl || fail "sending Ctrl+S for the typed key failed"
expect_poll "Ctrl+S writes the typed key" '"SUPER+SHIFT+K"' settings_key
expect_poll "the written key closes the text entry" false settings_key_field typing
expect_poll "the bar reads Saved after the key" true us_bar_read
expect "the Keys row's text entry opens for a refused key" typing settings_key_invoke typeKeyField
type_keys "SUPER+" || fail "typing the malformed key failed"
type_keys -M ctrl -k s -m ctrl || fail "sending Ctrl+S for the malformed key failed"
expect_log "the manager refuses the key" 1 'settings: vgs\.settings refused: key=toggle '
expect_poll "the page holds the key's refusal" refused us_refused vgs.settings
expect "a refused key returns to its text entry" true settings_key_field typing
expect "a refused key keeps the bar" unsaved us_bar
expect "a refused key is not written" '"SUPER+SHIFT+K"' settings_key
us_bar_press Discard || fail "the click on Discard for the refused key failed"
expect_poll "Discard closes the text entry" false settings_key_field typing
expect_poll "the bar leaves after the key's Discard" hidden us_bar
settings_page_close "$us_id"

# Control of the page's rules: a copy of the Settings plugin, installed
# over the shipped one, that breaks each, read by the same readers.
expected_errors+=('plugins: hidden by a higher-precedence plugin with the same id: vgs\.settings')
us_copy="$home/.config/vgshell/plugins/vgs.settings"
rm -rf -- "${us_copy:?}"
mkdir -p -- "$(dirname -- "$us_copy")"
cp -R -- "$repo/shell/plugins/vgs.settings" "$us_copy"
if python3 - "$us_copy" <<'PYCOPY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
edits = (
    ("SettingField.qml", "        onAccepted: field.save()\n", "        onEditingFinished: field.save()\n"),
    ("PluginPage.qml", "                dirty: page.dirty\n", "                dirty: true\n"),
    ("PluginPage.qml", "                onDiscard: page.discard()\n", "                onDiscard: {}\n"),
    ("PluginPage.qml", "        if (event.key !== Qt.Key_S || event.modifiers !== Qt.ControlModifier) return;\n", "        return;\n"),
    ("Window.qml", "        if (!detail.dirty) {\n            then();\n            return true;\n        }\n", "        then();\n        return true;\n"),
)
for name, old, new in edits:
    path = root / name
    text = path.read_text()
    if text.count(old) != 1:
        sys.exit("%s: %r occurs %d times" % (name, old, text.count(old)))
    path.write_text(text.replace(old, new))
PYCOPY
then ok "the control copy writes on focus loss, binds its bar to no edit, drops Discard and Ctrl+S and asks nothing"; else fail "the control copy could not be written"; fi
rescan "a rescan picks the control copy"
settings_page_open "$us_id"
expect_poll "control: the copy's page draws its Gap field" drawn us_line Gap
us_edit "control: the Gap edit for the focus loss" 61 70
type_keys -k Tab || fail "control: tabbing out of the edited field failed"
expect_poll "control: a field that writes on focus loss writes the value" 70 us_value gap
us_before="$(us_writes)" || fail "control: the configuration counter is unreadable"
us_edit "control: the Gap edit for Ctrl+S" 70 71
type_keys -M ctrl -k s -m ctrl || fail "control: sending Ctrl+S failed"
sleep 1 # The real reading's write lands within one poll, 200 ms.
expect "control: a page without the key writes nothing on Ctrl+S" "$us_before" us_writes
us_bar_press Discard || fail "control: the click on Discard failed"
sleep 1 # The real Discard restores the value within one poll, 200 ms.
expect "control: a Discard that does nothing leaves the typed value" 71 us_text gap
us_bar_press Save || fail "control: the click on Save failed"
expect_poll "control: Save still writes the value" 71 us_value gap
sleep 3 # The real bar is gone 1750 ms after the write.
expect "control: a bar bound to no edit stays after Save" unsaved us_bar
us_edit "control: the Gap edit for back" 71 72
expect "control: a window that asks nothing leaves at once" ok ipc smoke invokeInstance window vgs.settings back ''
expect_poll "control: the page is popped" '""' us_page
expect "control: no prompt shows" False us_prompt
settings_page_close "$us_id"
rm -rf -- "${us_copy:?}"
rescan "a rescan drops the control copy"

# Control of the rules the page's own copy cannot break alone: a tree whose
# list hands its item fields no set and keys its items by nothing, whose
# page moves no keyboard when its last edit goes, whose key field reads
# its entry's visibility, whose window host asks no instance and whose
# window leaves after a refused save.
if copy_tree unsaved-host \
  && edit_tree unsaved-host shell/Hosts/SummonHost.qml 'instance.holdsHide()) return "refused: held=" + id;' 'false) return "refused: held=" + id;' \
  && edit_tree unsaved-host shell/plugins/vgs.settings/ListField.qml 'edits: root.edits' 'edits: null' \
  && edit_tree unsaved-host shell/plugins/vgs.settings/ListField.qml 'objectProp: "name"' '' \
  && edit_tree unsaved-host shell/plugins/vgs.settings/PluginPage.qml 'onEditedChanged: if (!edited && saveBar.activeFocus) tabs.tabs.forceActiveFocus(Qt.TabFocusReason)' 'onEditedChanged: {}' \
  && edit_tree unsaved-host shell/Ui/controls/ShortcutField.qml 'readonly property alias typing: entry.open' 'readonly property bool typing: entry.visible' \
  && edit_tree unsaved-host shell/plugins/vgs.settings/Window.qml 'choice === "save" ? detail.save() : choice === "discard";' 'choice === "save" ? (detail.save(), true) : choice === "discard";'; then
  stop_shell
  start_shell "$sandbox/tree-unsaved-host" "$sandbox/unsaved-host.log" || fail "the control shell of the tree copy starts"
  settings_page_open "$us_id"
  expect_poll "control: the page draws its Gap field" drawn us_line Gap
  us_edit "control: the list item's edit" 34 35
  expect "control: a list that hands its fields no set shows no bar" hidden us_bar
  us_wide_press || fail "control: the click on the list item's switch failed"
  expect_poll "control: the item's switch writes the list" '[{"name": "1", "size": 34, "wide": false}]' us_value notes
  expect "control: a list that keys its items by nothing drops the item's typed value" absent us_drawn 35
  us_held="$(us_value gap)" || fail "control: the fixture's saved value is unreadable"
  us_edit "control: the Gap edit for the keyboard's Save" "$us_held" 75
  us_tab_to '["Button","Save"]' || fail "control: tabbing to the bar's Save failed"
  type_keys -k Return || fail "control: pressing the bar's Save with Return failed"
  expect_poll "control: the bar's Save writes the value" 75 us_value gap
  expect "control: a page that moves no keyboard leaves it off the strip" false us_strip
  expect "control: the window opens the Settings plugin's own page" ok ipc smoke invokeInstance window vgs.settings openPlugin vgs.settings
  expect_poll "control: the Settings shortcut's Keys row is drawn" false settings_key_field typing
  expect "control: the Keys row's text entry opens" typing settings_key_invoke typeKeyField
  type_keys "shift+super+j" || fail "control: typing the key failed"
  expect_poll "control: the typed key shows the save bar" unsaved us_bar
  settings_tab_click Details || fail "control: the click on the Details tab over the typed key failed"
  expect_poll "control: a key field that reads its entry's visibility lets Details show" 1 settings_tab
  expect "control: no prompt asks about the typed key" False us_prompt
  settings_tab_click Settings || fail "control: the click back to the Settings tab failed"
  expect_poll "control: the typed key shows the bar again" unsaved us_bar
  us_bar_press Discard || fail "control: the click on Discard for the typed key failed"
  expect_poll "control: Discard closes the text entry" false settings_key_field typing
  us_open
  us_edit "control: the Gap edit for the hide" 75 74
  expect_poll "control: the edit shows the bar" unsaved us_bar
  expect "control: a host that asks no instance hides the window" ok ipc shell hide window vgs.settings
  expect_poll "control: the window is gone with its unsaved edit" 0 window_count Plugins
  expect "control: the hidden window's edit is lost" 75 us_value gap
  expect "control: Settings is summoned on the fixture's page again" ok ipc shell summon window vgs.settings "{\"plugin\":\"$us_id\"}"
  expect_poll "control: the Settings window maps again" 1 window_count Plugins
  expect_poll "control: the reopened page draws its Gap field" drawn us_line Gap
  us_edit "control: the refused Gap edit" 75 abc
  expect "control: back with the refused value is held" "refused: unsaved=$us_id" ipc smoke invokeInstance window vgs.settings back ''
  expect_poll "control: back asks about the refused value" True us_prompt
  expect_poll "control: the prompt holds the keyboard on Save" '["Button","Save"]' us_focus
  type_keys -k Return || fail "control: sending Return to the prompt failed"
  expect_poll "control: a window that leaves after a refused save pops the page" '""' us_page
  expect "control: the refused value is not written" 75 us_value gap
  expect "control: hiding the window after the refused save is allowed" ok ipc shell hide window vgs.settings
  expect_poll "control: the window is gone after the refused save" 0 window_count Plugins
  expect "control: disabling Settings after the control is allowed" ok ipc shell setPluginEnabled vgs.settings false
  stop_shell
  start_shell "$repo" "$sandbox/unsaved-restart.log" || fail "the shell starts again after the held-hide control"
fi

expect "disabling the unsaved-edits fixture is allowed" ok ipc shell setPluginEnabled "$us_id" false
expect_poll "the fixture's service is gone" False record_exists "$us_id"
rm -rf -- "${home:?}/.config/vgshell/plugins/$us_id"
cp -- "$us_saved" "$us_file.tmp" && mv -T -- "$us_file.tmp" "$us_file" || fail "putting the user file back failed"
rescan "a rescan drops the unsaved-edits fixture"
expect "the fixture is no longer listed" False plugin_known "$us_id"
