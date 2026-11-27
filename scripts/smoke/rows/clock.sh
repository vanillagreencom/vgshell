# Manage widgets removes the stock Clock and adds it at the clicked left
# section. The remounted widget keeps its saved format and opens the
# calendar. The three clock settings appear on Clock's page, and the Bar
# page draws no Clock section. No latency budget: reads poll state.
set -euo pipefail

clock_saved="$sandbox/clock-before-chooser.json"
cp -- "$home/.config/vgshell/shell.json" "$clock_saved"
clock_restore() {
  cp -- "$clock_saved" "$home/.config/vgshell/shell.json.tmp" &&
    mv -T -- "$home/.config/vgshell/shell.json.tmp" "$home/.config/vgshell/shell.json" ||
    { fail "the original Clock placement could not be restored"; return 1; }
  expect "the original Clock placement reloads" ok ipc shell reloadConfig
}
smoke_row_abandon=(clock_restore)

# The section holding one mounted and visible Clock with a nonempty box.
clock_section() {
  ipc smoke barParticipationGeometry "$(bar_key)" | py_reply 'import json,sys
matches=[(s["section"], e) for s in json.load(sys.stdin)["sections"] for e in s["entries"] if e["id"]=="vgs.clock"]
if not matches: print("absent")
elif len(matches)==1:
    section, entry=matches[0]
    print(section if entry["present"] and entry["visible"] and min(entry["box"][2:])>0 else "unmounted")
else: print("duplicate")'
}
aw_open left
expect_poll "Manage widgets lists the placed Clock with its switch on" '["Switch", "", true]' aw_control vgs.clock
aw_click vgs.clock control
expect_poll "the switch removes Clock from the saved bar layout" False aw_placed vgs.clock
expect_poll "no Clock stays mounted after removal" absent bar_clock_format
expect_poll "Manage widgets still offers Clock with its switch off" '["Switch", "", false]' aw_control vgs.clock
aw_click vgs.clock control
expect_poll "the chooser saves Clock in the clicked left section" '{"left":["vgs.workspaces","vgs.clock"],"center":["acme.tick"],"right":[]}' bar_saved_layout
expect_poll "the switch places Clock at the clicked left section" left clock_section
expect_poll "the remounted Clock receives its saved format" '"dddd HH:mm"' bar_clock_format
expect "the widget chooser closes" ok ipc shell hide window vgs.bar
expect_poll "the bar is ready for a clock click" 0 window_count Bar

expect "clicking the re-added Clock reaches it" ok bar_clock_click
expect_poll "the re-added Clock opens the calendar on the current month" "$(calendar_want 0)" calendar_read
expect_poll "the calendar presents a frame" drawn ipc smoke windowDrawn panel vgs.clock
expect "the anchored calendar opens as a popup" 0 layer_count vgs:panel
expect "the Clock calendar accepts hide" ok ipc shell hide panel vgs.clock
expect_poll "the calendar closes" closed calendar_read

clock_setting() {
  local reply
  reply="$(ipc smoke invokeInstance window vgs.settings fieldChoice "{\"id\":\"vgs.clock\",\"key\":\"$1\"}")" || return
  py_reply 'import json,sys
raw=sys.stdin.read().strip()
print(json.dumps(json.loads(raw)["value"]) if raw.startswith("{") else raw)' <<<"$reply"
}
settings_page_open vgs.clock
expect_poll "the Clock format field reads the saved format" '"dddd HH:mm"' clock_setting clockFormat
expect_poll "the Calendar field reads the saved address" '"https://example.invalid/calendar/{year}/{month}/{day}"' clock_setting calendarUrl
expect_poll "the Open with field reads the saved browser profile" '"chromium/Default"' clock_setting openWith
settings_page_close vgs.clock

clock_bar_heading() {
  ipc smoke itemTexts window vgs.settings SectionHeader | py_reply 'import json,sys
headings={t for group in json.load(sys.stdin) for t in group}
print("Bar" in headings and "Clock" not in headings)'
}
settings_page_open vgs.bar
expect_poll "the Bar page shows its Bar section without a Clock section" True clock_bar_heading
settings_page_close vgs.bar

clock_restore
expect_poll "Clock returns to its original centre section" center clock_section
smoke_row_abandon=()
