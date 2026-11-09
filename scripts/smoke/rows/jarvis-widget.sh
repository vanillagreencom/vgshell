# The Jarvis widget keeps its J, draws the shared state dot and asks count,
# opens the console and controls independent hidden and voice-mute choices
# through the shared menu. The hidden J retains the same dot and asks count.
# No audio, account, provider or
# network runs; no PAM, polkit, keyring or TUI is reached. No latency
# ceiling is measured. Widget and state reads poll once per nested IPC
# round trip; fixture callback gates poll at 10 ms.
# inputs: scripts/smoke/user-config.sh shell/plugins/vgs.jarvis/* shell/Ui/foundation/KeyNavLogic.js scripts/fixtures/jarvis/* scripts/smoke/keyboard/* scripts/smoke/rows/jarvis.sh scripts/smoke/rows/jarvis-keys.sh scripts/smoke/rows/hold-shortcuts.sh scripts/smoke/rows/hyprland-consent.sh shell/Core/Notifier.qml shell/Core/Layers.qml shell/Hosts/BarHost.qml shell/plugins/vgs.notifications/* bin/lib/qml-library.js shell/Ui/overlay/Tooltip.qml shell/Ui/controls/BarItem.qml shell/Ui/feedback/LinkText.qml shell/Commons/PageReference.js shell/plugins/vgs.settings/manifest.json shell/plugins/vgs.settings/Window.qml shell/plugins/vgs.settings/ListPage.qml shell/plugins/vgs.settings/PluginPage.qml shell/plugins/vgs.settings/PageHeader.qml shell/plugins/vgs.settings/EditSet.qml shell/plugins/vgs.settings/Steps.js shell/Ui/controls/SettingField.qml shell/plugins/vgs.settings/ListField.qml shell/plugins/vgs.settings/KeyField.qml shell/plugins/vgs.settings/StatusRow.qml shell/plugins/vgs.settings/StatusLine.qml shell/plugins/vgs.settings/RequirementRow.qml shell/plugins/vgs.voice/Widget.qml shell/plugins/vgs.voice/manifest.json shell/Ui/BarWidget.qml shell/plugins/vgs.jarvis/backend/skills/*.md
set -euo pipefail
local jarvis_fixture_tree="" jarvis_fixture_shim="" jarvis_fixture_name="" jarvis_fixture_revision=""
jarvis_fixture_begin
# The Jarvis fixtures log the set jarvis.sh declares.
expected_errors+=("${jarvis_provoked_errors[@]}")
# Jarvis holds `dictation`, and the shell finds no voxtype: the core's
# probe does not start at each enable.
expected_errors+=("${dictation_absent_errors[@]}")

jarvis_widget_config="$home/.config/vgshell/shell.json"
jarvis_widget_lua="$home/.config/hypr/hyprland.lua"
jarvis_widget_dir="$jarvis_fixture_tree/shell/plugins/vgs.jarvis"
jarvis_widget_gates="$sandbox/jarvis-widget-gates"
local jarvis_key_gates="$jarvis_widget_gates"
cp -- "$jarvis_widget_config" "$sandbox/jarvis-widget-config-before.json"
cp -- "$jarvis_widget_lua" "$sandbox/jarvis-widget-lua-before"
notes_on "the widget's deliberate daemon failures"
jarvis_widget_notes=true
jarvis_fixture_copy jarvis-widget-stock "$jarvis_fixture_tree" "$jarvis_fixture_shim"
jarvis_widget_input=jarvis-widget-scripted
jarvis_widget_keyboard=false
jarvis_widget_select() {
  jarvis_fixture_begin "$sandbox/tree-$jarvis_widget_input" "$sandbox/tree-$jarvis_widget_input.commands"
  jarvis_widget_dir="$jarvis_fixture_tree/shell/plugins/vgs.jarvis"
  if [[ $jarvis_widget_notes == true ]]; then
    expect_poll "the widget's notification server is ready after input selection" True notes_quiet
  fi
  [[ $jarvis_widget_keyboard != true ]] || jarvis_key_resume_marker
}
jarvis_widget_key="$(bar_key)"
expect "the widget row starts with Jarvis disabled" absent ipc smoke jarvisProcess
expect "a disabled Jarvis draws no widget" absent ipc smoke readInstance "$jarvis_widget_key" vgs.jarvis moduleName
"$node_bin" "$source_repo/scripts/fixtures/jarvis/scripted.js" "$jarvis_widget_dir/backend/jarvisd.js" "$jarvis_widget_gates" --mapped-indicator
jarvis_gate="$sandbox/jarvis-widget-startup-gate"
jarvis_seen="$sandbox/jarvis-widget-startup-seen"
"$node_bin" "$source_repo/scripts/fixtures/jarvis/prepare.js" --gate-daemon "$jarvis_widget_dir/backend/jarvisd.js" "$jarvis_gate" "$jarvis_seen"
jarvis_fixture_copy jarvis-widget-scripted "$jarvis_fixture_tree" "$jarvis_fixture_shim"
jarvis_rescan

jarvis_widget_gate() { : >"$jarvis_widget_gates/$1"; }
jarvis_widget_section() { ipc shell listShellConfig | py_reply 'import json,sys; l=json.load(sys.stdin)["bar"]["layout"]; print(([s for s in ("left","center","right") if any(e["id"]==sys.argv[1] for e in l.get(s,[]))] + ["none"])[0])' vgs.jarvis; }
jarvis_widget_tones="$(python3 -c 'import json,sys; print(json.dumps(dict(zip(["calm", "neutral", "accent", "info", "danger"], [json.loads(v).lower() for v in sys.argv[1:]]))))' \
  "$(ipc smoke themeValue bar.foreground)" "$(ipc smoke themeValue color.textMuted)" \
  "$(ipc smoke themeValue color.accent)" "$(ipc smoke themeValue color.info)" \
  "$(ipc smoke themeValue color.danger)")" || fail "the widget tones are unreadable"
jarvis_widget_dot_colours="$(python3 -c 'import json,sys; print(json.dumps(dict(zip(["info", "success", "warning", "danger"], [json.loads(v).lower() for v in sys.argv[1:]]))))' \
  "$(ipc smoke themeValue color.info)" "$(ipc smoke themeValue color.success)" \
  "$(ipc smoke themeValue color.warning)" "$(ipc smoke themeValue color.danger)")" || fail "the widget dot colours are unreadable"
# The widget as drawn: [icon, tone, state, action-line count, dot role, count].
# Read the shared loaders and their painted badges too: a role alone cannot
# prove a dot is drawn, and a private badge must not duplicate either one.
# Probe matches native class names. Qt 6.11 registers Loader as QQuickLoader:
# https://code.qt.io/cgit/qt/qtdeclarative.git/tree/src/quick/items/qquickloader_p.h?h=6.11
jarvis_widget() {
  local icon colours tip details view item loaders badges
  icon="$(ipc smoke readDescendant "$jarvis_widget_key" vgs.jarvis Icon name)" \
    && colours="$(ipc smoke itemColours "$jarvis_widget_key" vgs.jarvis Widget Icon)" \
    && tip="$(ipc smoke readDescendant "$jarvis_widget_key" vgs.jarvis Tooltip text)" \
    && details="$(ipc smoke readDescendant "$jarvis_widget_key" vgs.jarvis Tooltip details)" \
    && view="$(ipc smoke readInstance "$jarvis_widget_key" vgs.jarvis view)" \
    && item="$(ipc smoke itemValues "$jarvis_widget_key" vgs.jarvis BarItem stateDot,count)" \
    && loaders="$(ipc smoke itemValues "$jarvis_widget_key" vgs.jarvis QQuickLoader objectName,active,item.text,item.displayedText)" \
    && badges="$(ipc smoke itemColours "$jarvis_widget_key" vgs.jarvis Widget Badge)" || return
  py_reply '
import json, sys
icon, colours, tip, details, tones, items, loaders, badges, dot_colours = sys.argv[1:]
if any(value in ("absent", "undefined", "missing", "empty") for value in (icon, colours, tip, details, items, loaders, badges)):
    print("absent"); sys.exit()
colours, items, loaders, badges = map(json.loads, (colours, items, loaders, badges))
if len(colours) != 1 or len(colours[0]) != 1 or len(items) != 1 or len(badges) != 1:
    print("draw-incomplete"); sys.exit()
colour = colours[0][0]
names = [name for name, value in json.loads(tones).items() if "#" + value[3:9] + value[1:3] == colour]
view = json.load(sys.stdin)
drawn = json.loads(tip) == view["tooltip"] and json.loads(details) == view["tooltipDetails"]
dot, count = items[0].get("stateDot"), items[0].get("count")
for name, active in (("bar-item-state-dot", bool(dot)), ("bar-item-count", bool(count))):
    found = [loader for loader in loaders if loader.get("objectName") == name]
    if len(found) != 1 or found[0].get("active") != active:
        print("badge-loader-mismatch"); sys.exit()
    if name == "bar-item-count" and active and found[0].get("item.text") != count:
        print("count-draw-mismatch"); sys.exit()
if len(badges[0]) != int(bool(dot)) + int(bool(count)):
    print("badge-draw-mismatch"); sys.exit()
if dot:
    value = json.loads(dot_colours).get(dot)
    if value is None or "#" + value[3:9] + value[1:3] not in badges[0]:
        print("dot-colour-mismatch"); sys.exit()
print(json.dumps([json.loads(icon), names[0] if len(names) == 1 else "colour=" + colour,
    view["state"] if drawn else "draw-mismatch", len(json.loads(details)), dot, count]))
' "$icon" "$colours" "$tip" "$details" "$jarvis_widget_tones" "$item" "$loaders" "$badges" "$jarvis_widget_dot_colours" <<<"$view"
}
jarvis_widget_ready='["vgs-letter-j", "calm", "ready", 0, "", ""]'
jarvis_widget_listening='["vgs-letter-j", "accent", "listening", 0, "success", ""]'
jarvis_widget_hidden_ready='["vgs-letter-j-hidden", "calm", "ready", 0, "", ""]'
jarvis_widget_hidden_listening='["vgs-letter-j-hidden", "accent", "listening", 0, "success", ""]'
jarvis_widget_records() {
  python3 - "$home/.local/state/vgshell/jarvis" <<'PY'
import json,sys
from pathlib import Path
root=Path(sys.argv[1])
try: hidden=json.loads((root/"hidden.json").read_text()); voice=json.loads((root/"voice-mute.json").read_text())
except (OSError,ValueError): print("unreadable"); sys.exit()
if not isinstance(hidden,dict) or set(hidden)!={"hidden"} or type(hidden["hidden"]) is not bool: print("hidden-shape"); sys.exit()
if not isinstance(voice,dict) or set(voice)!={"muted"} or type(voice["muted"]) is not bool: print("voice-shape"); sys.exit()
print(json.dumps([hidden["hidden"],voice["muted"]]))
PY
}
jarvis_widget_click() { click_centre "$jarvis_widget_key" vgs.jarvis || fail "the click on the Jarvis widget failed"; }
jarvis_widget_consoles() { window_count Jarvis; }
jarvis_widget_click_opens() { expect_poll "a click on the widget opens the console" 1 jarvis_widget_consoles; }
jarvis_widget_console_close() {
  expect "the console opened from the widget hides" ok ipc shell hide window vgs.jarvis
  expect_poll "the console opened from the widget is gone" 0 jarvis_widget_consoles
}
# Read Console's real Needs you tab and the shared corner badge, not only
# the widget's input. The fixture supplies one status publication to both.
jarvis_widget_count() {
  local asks count loaders tabs
  asks="$(ipc smoke readInstance "$jarvis_widget_key" vgs.jarvis ownerAsks)" \
    && count="$(ipc smoke readDescendant "$jarvis_widget_key" vgs.jarvis BarItem count)" \
    && loaders="$(ipc smoke itemValues "$jarvis_widget_key" vgs.jarvis QQuickLoader objectName,active,item.text,item.displayedText)" \
    && tabs="$(ipc smoke itemValues window vgs.jarvis Tabs unreadCounts)" || return
  py_reply '
import json, sys
asks, count, loaders = sys.argv[1:]
if any(value in ("absent", "undefined", "missing", "empty") for value in (asks, count, loaders)):
    print("absent"); sys.exit()
asks, count, loaders = map(json.loads, (asks, count, loaders))
tabs = json.load(sys.stdin)
badge = [loader for loader in loaders if loader.get("objectName") == "bar-item-count"]
if len(tabs) != 1 or len(badge) != 1 or not isinstance(tabs[0].get("unreadCounts"), dict):
    print("count-incomplete"); sys.exit()
badge = badge[0]
if badge.get("active") != bool(count) or count and badge.get("item.text") != count:
    print("count-draw-mismatch"); sys.exit()
console = tabs[0]["unreadCounts"].get("Needs you")
print(json.dumps([asks.get("kind") if isinstance(asks, dict) else "unpublished", count,
    "" if console is None else str(console), badge.get("item.displayedText") if count else ""]))
' "$asks" "$count" "$loaders" <<<"$tabs"
}
jarvis_widget_click_control() {
  (failures=0 behaviour_failures=0
   jarvis_widget_click_opens >"$sandbox/jarvis-widget-click-control.log"
   echo "$failures")
}
# The widget's right-click menu: a real right click, the pointer moved a
# pixel off first so the press follows a motion, then Home, Down to ROW and
# Return, as rows/voice.sh walks the Voice widget's menu.
jarvis_widget_menu() { ipc smoke readInstance "$jarvis_widget_key" vgs.jarvis "$1"; }
jarvis_widget_menu_choose() { # ROW [ENTRIES]: ENTRIES, the open menu's rows
  local box x y index step
  box="$(ipc smoke instanceGeometry "$jarvis_widget_key" vgs.jarvis)" && [[ $box == \[* ]] \
    && read -r x y < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(int(x+w/2), int(y+h/2))' "$box") \
    && hover "$((x - 1))" "$y" && right_click "$x" "$y" || { fail "the right click on the Jarvis widget failed"; return; }
  expect_poll "a right click on the Jarvis widget opens its menu" true jarvis_widget_menu frameMenuOpen
  [[ -z ${2-} ]] || expect "the menu offers $(python3 -c 'import json,sys; rows=json.loads(sys.argv[1]); print(", ".join(rows[:-1]) + " and " + rows[-1])' "$2")" "$2" jarvis_widget_menu frameMenuEntries
  index="$(jarvis_widget_menu frameMenuEntries | py_reply 'import json,sys; rows=json.load(sys.stdin); print(rows.index(sys.argv[1]) if sys.argv[1] in rows else "absent")' "$1")" || index=unreadable
  if [[ ! $index =~ ^[0-9]+$ ]]; then
    fail "the Jarvis widget's menu has no $1: $index"
    type_keys -k Escape || fail "Escape on the Jarvis widget's menu failed"
    return
  fi
  type_keys -k Home || fail "Home on the Jarvis widget's menu failed"
  for ((step = 0; step < index; step++)); do type_keys -k Down || fail "Down on the Jarvis widget's menu failed"; done
  type_keys -k Return || fail "Return on the Jarvis widget's menu failed"
  expect_poll "$1 closes the Jarvis widget's menu" false jarvis_widget_menu frameMenuOpen
}
# The icon each widget's BarItem draws.
jarvis_widget_item_icon() { ipc smoke readDescendant "$jarvis_widget_key" "$1" BarItem iconName; }
jarvis_widget_notice_moved() { ipc shell lent | py_reply 'import json,sys; s=json.load(sys.stdin)["notices"]["shown"]; print(str(s is None or s["plugin"] != sys.argv[1]).lower())' "$1"; }
# Enabling Voice raises its requirement notice (no voxtype in the
# sandbox); Escape closes each notice shown, as rows/keyhints.sh does.
jarvis_widget_notices_close() {
  local shown
  for _ in 1 2 3 4; do
    shown="$(ipc shell lent | py_reply 'import json,sys; s=json.load(sys.stdin)["notices"]["shown"]; print("none" if s is None else s["plugin"])')" || shown=unread
    [[ $shown == none ]] && return
    expect_poll "the notice of $shown holds the keyboard" true ipc smoke noticeFocused
    type_keys -k Escape || fail "sending Escape to the notice of $shown failed"
    expect_poll "Escape closes the notice of $shown" true jarvis_widget_notice_moved "$shown"
  done
  expect_poll "no notice is left after the Voice widget's icon read" null notice_shown
}
# With Jarvis disabled, edit only the selected disposable input.
jarvis_widget_plant() { # FILE NEEDLE REPLACEMENT [NEEDLE REPLACEMENT]...
  python3 - "$jarvis_widget_dir/$1" "$jarvis_widget_dir/$1" "${@:2}" <<'PY'
from pathlib import Path
import sys
source, target, *pairs = sys.argv[1:]
assert pairs and len(pairs) % 2 == 0, pairs
p = Path(target); assert not p.is_symlink()
s = Path(source).read_text()
for needle, replacement in zip(pairs[::2], pairs[1::2]):
    assert s.count(needle) == 1, needle
    changed = s.replace(needle, replacement)
    assert changed != s
    s = changed
p.write_text(s)
PY
  jarvis_rescan
}
# The widget during the retry wait: `restarting` for the problem look while
# the service waits to retry and its daemon row says it is trying again, otherwise the
# reading itself.
jarvis_widget_restarting() {
  local widget process
  widget="$(jarvis_widget)" && process="$(ipc smoke jarvisProcess)" || return
  py_reply '
import json, sys
r, p = json.load(sys.stdin), sys.argv[1]
d = None if p in ("absent", "missing") else json.loads(p)
ok = (d is not None and r == ["vgs-letter-j", "danger", "problem", 1, "danger", ""]
      and d["lifetime"]["kind"] == "retry" and d["status"]["daemon"]["tone"] == "warning"
      and d["status"]["daemon"].get("hint") == "Jarvis is trying again by itself")
print("restarting" if ok else json.dumps(r))
' "$process" <<<"$widget"
}
jarvis_widget_restart_assertion() { expect_poll "the widget reads a problem while the daemon retries" restarting jarvis_widget_restarting; }
jarvis_widget_restart_control() {
  (failures=0 behaviour_failures=0
   jarvis_widget_restart_assertion >"$sandbox/jarvis-widget-restart-control.log"
   echo "$failures")
}
# Kill the running daemon by the PID below its Process-owned launcher.
jarvis_widget_kill() {
  local launcher
  launcher="$(ipc smoke jarvisProcess | jarvis_launcher_pid)" || return
  kill -KILL "$(jarvis_descendants "$launcher")"
}
# Keep the real retry timer, with a fixture delay long enough to read the
# widget before the next start.
jarvis_widget_retry_needle='retry.interval = 250 * Math.pow(2, retries);'
jarvis_widget_retry_delay='retry.interval = 3000;'
jarvis_widget_reset() {
  jarvis_disable
  jarvis_widget_select
  jarvis_rescan
}

printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = false } })' >>"$jarvis_widget_lua"
expect "Jarvis keys use the physical evdev map" ok hypr reload config-only
hold_start_keyboard jarvis-widget "$sandbox/keyboard" us ""
jarvis_widget_keyboard=true
jarvis_key_resume_marker

rm -f -- "$jarvis_gate" "$jarvis_seen"
expect "the gated widget service enables" ok ipc shell setPluginEnabled vgs.jarvis true
expect_poll "enabling places the widget in the bar's right section" right jarvis_widget_section
expect_poll "the startup daemon consumes hello" seen jarvis_seen_hello
expect_poll "the widget reads loading before the first state" '["vgs-letter-j", "info", "loading", 0, "info", ""]' jarvis_widget
: >"$jarvis_gate"
expect "the gated daemon answers hello" ready jarvis_wait_ready
expect_poll "the widget reads ready" "$jarvis_widget_ready" jarvis_widget
jarvis_key_hold true
# Jarvis draws its own J; the Voice widget beside it keeps the microphone.
expect "the Jarvis widget draws the J" '"vgs-letter-j"' jarvis_widget_item_icon vgs.jarvis
jarvis_widget_voice_before="$(plugin_enabled vgs.voice)" || jarvis_widget_voice_before=unread
[[ $jarvis_widget_voice_before == True ]] || expect "Voice enables beside Jarvis for its icon" ok ipc shell setPluginEnabled vgs.voice true
expect_poll "the Voice widget draws the microphone" '"mic"' jarvis_widget_item_icon vgs.voice
if [[ $jarvis_widget_voice_before != True ]]; then
  expect "Voice disables after its icon read" ok ipc shell setPluginEnabled vgs.voice false
  jarvis_widget_notices_close
fi

jarvis_key_talk_down
expect_poll "talk down opens capture" listening jarvis_key_state phase
expect_poll "the widget reads listening while Jarvis listens" "$jarvis_widget_listening" jarvis_widget
jarvis_key_talk_up
expect_poll "release commits the scripted utterance" thinking jarvis_key_state phase
expect_poll "the widget reads working while Jarvis thinks" '["vgs-letter-j", "info", "working", 0, "info", ""]' jarvis_widget
jarvis_widget_gate brain
expect_poll "the scripted brain speaks" speaking jarvis_key_state phase
expect_poll "the widget reads speaking during playback" '["vgs-letter-j", "accent", "speaking", 0, "success", ""]' jarvis_widget
jarvis_widget_gate played
expect_poll "scripted playback returns to idle" idle jarvis_key_state phase
expect_poll "the widget reads ready after the answer" "$jarvis_widget_ready" jarvis_widget

jarvis_widget_click
jarvis_widget_click_opens
jarvis_widget_console_close
# JarvisProtocol.ownerAsksPage permits an empty final page with a cursor;
# its activeCount still supplies the total. Substitute only the service's
# publication in the disposable tree, leaving both consumers unchanged.
for jarvis_widget_asks_count in 3 0 unavailable; do
  jarvis_disable
  jarvis_widget_select
  if [[ $jarvis_widget_asks_count == unavailable ]]; then
    jarvis_widget_asks_snapshot='{ kind: "unavailable", cause: "Fixture asks unavailable" }'
    jarvis_widget_asks_expected='["unavailable", "", "", ""]'
    jarvis_widget_bar_count=""
  else
    jarvis_widget_asks_snapshot="{ kind: \"ready\", homeId: \"fixture-home\", revision: \"fixture-revision\", observedAt: \"2026-11-06T15:00:00.000Z\", activeCount: $jarvis_widget_asks_count, snoozedCount: 0, active: [], snoozed: [], activeCursor: \"fixture-last-page\", activeNextCursor: null, snoozedCursor: null, snoozedNextCursor: null }"
    jarvis_widget_bar_count=""
    [[ $jarvis_widget_asks_count == 0 ]] || jarvis_widget_bar_count="$jarvis_widget_asks_count"
    jarvis_widget_asks_expected="[\"ready\", \"$jarvis_widget_bar_count\", \"$jarvis_widget_bar_count\", \"$jarvis_widget_bar_count\"]"
  fi
  jarvis_widget_plant Service.qml 'StatusPublication.write(shell.status, "ownerAsks", message.snapshot)' \
    "StatusPublication.write(shell.status, \"ownerAsks\", $jarvis_widget_asks_snapshot)"
  jarvis_enable
  expect_poll "asks $jarvis_widget_asks_count keeps the J and uses the shared count" \
    "[\"vgs-letter-j\", \"calm\", \"ready\", 0, \"\", \"$jarvis_widget_bar_count\"]" jarvis_widget
  jarvis_widget_click
  jarvis_widget_click_opens
  expect_poll "asks $jarvis_widget_asks_count agrees with Console and its drawn corner count" "$jarvis_widget_asks_expected" jarvis_widget_count
  jarvis_widget_console_close
  if [[ $jarvis_widget_asks_count == 3 ]]; then
    expect_poll "the count fixture has a completed host frame before Hide" present jarvis_key_state barIndicator
    jarvis_widget_menu_choose "Hide Jarvis"
    expect_poll "the hidden J keeps the same shared asks badge" \
      "[\"vgs-letter-j-hidden\", \"calm\", \"ready\", 0, \"\", \"$jarvis_widget_bar_count\"]" jarvis_widget
    jarvis_widget_click
    jarvis_widget_click_opens
    expect_poll "the hidden J and Console still agree on the drawn count" "$jarvis_widget_asks_expected" jarvis_widget_count
    jarvis_widget_console_close
    jarvis_widget_menu_choose "Show Jarvis"
    expect_poll "Show keeps the same shared asks badge" \
      "[\"vgs-letter-j\", \"calm\", \"ready\", 0, \"\", \"$jarvis_widget_bar_count\"]" jarvis_widget
  fi
done
jarvis_widget_reset
jarvis_enable
jarvis_widget_menu_choose "Mute Jarvis's voice" "[\"Hide\",\"Mute Jarvis's voice\",\"Mute microphone\",\"Stop Jarvis\",\"New conversation\",\"Hide Jarvis\",\"Key hints\",\"Readme\",\"Settings\"]"
expect_poll "the menu toggles independent voice mute" on jarvis_key_state voiceMute
expect_poll "voice mute leaves the state-only tooltip ready" "$jarvis_widget_ready" jarvis_widget
jarvis_widget_microphone_before="$(ipc smoke readInstance service vgs.jarvis microphoneMute)" || fail "the system microphone reading is unavailable before Hide"
expect_poll "Hide waits for the actual widget's completed host frame" present jarvis_key_state barIndicator
jarvis_widget_menu_choose "Hide Jarvis" "[\"Hide\",\"Unmute Jarvis's voice\",\"Mute microphone\",\"Stop Jarvis\",\"New conversation\",\"Hide Jarvis\",\"Key hints\",\"Readme\",\"Settings\"]"
expect_poll "the bar's Hide route stores the independent choice" hidden jarvis_key_state visibility
expect_poll "Hide uses the held J without a private badge" "$jarvis_widget_hidden_ready" jarvis_widget
expect "Hide keeps the independent voice mute" on jarvis_key_state voiceMute
expect "Hide keeps the system microphone reading" "$jarvis_widget_microphone_before" ipc smoke readInstance service vgs.jarvis microphoneMute
expect "hidden and voice mute have independent durable records" '[true, true]' jarvis_widget_records
jarvis_disable
jarvis_enable
expect_poll "the hidden choice survives daemon restart" hidden jarvis_key_state visibility
expect_poll "voice mute survives daemon restart" on jarvis_key_state voiceMute
expect_poll "the restarted hidden choice draws the held J" "$jarvis_widget_hidden_ready" jarvis_widget
expect "restoring choices changes neither durable value" '[true, true]' jarvis_widget_records
expect "restoring choices never toggles the system microphone" "$jarvis_widget_microphone_before" ipc smoke readInstance service vgs.jarvis microphoneMute
jarvis_widget_menu_choose "Unmute Jarvis's voice"
expect_poll "voice unmute leaves Jarvis hidden" off jarvis_key_state voiceMute
expect "voice unmute changes only its own record" '[true, false]' jarvis_widget_records
expect_poll "voice unmute keeps the held J" "$jarvis_widget_hidden_ready" jarvis_widget
jarvis_widget_menu_choose "Mute Jarvis's voice"
expect_poll "voice mute returns without showing the orb" on jarvis_key_state voiceMute
expect "voice mute keeps the hidden record" '[true, true]' jarvis_widget_records
case "$jarvis_widget_microphone_before" in
  '{"kind":"ready","muted":false}')
    jarvis_widget_menu_choose "Mute microphone"
    expect_poll "the shared menu mutes only the system microphone" '{"kind":"ready","muted":true}' ipc smoke readInstance service vgs.jarvis microphoneMute
    expect "system mute keeps the hidden choice" hidden jarvis_key_state visibility
    expect "system mute keeps voice mute" on jarvis_key_state voiceMute
    jarvis_widget_menu_choose "Unmute microphone" ;;
  '{"kind":"ready","muted":true}')
    jarvis_widget_menu_choose "Unmute microphone"
    expect_poll "the shared menu unmutes only the system microphone" '{"kind":"ready","muted":false}' ipc smoke readInstance service vgs.jarvis microphoneMute
    expect "system unmute keeps the hidden choice" hidden jarvis_key_state visibility
    expect "system unmute keeps voice mute" on jarvis_key_state voiceMute
    jarvis_widget_menu_choose "Mute microphone" ;;
  '{"kind":"unavailable"}')
    expect "a missing system source does not clear either saved choice" '[true, true]' jarvis_widget_records ;;
  *) fail "the system microphone has an unrecognized reading: $jarvis_widget_microphone_before" ;;
esac
expect_poll "the system microphone returns to its entry reading" "$jarvis_widget_microphone_before" ipc smoke readInstance service vgs.jarvis microphoneMute
jarvis_key_talk_down
expect_poll "Talk keeps the hidden choice while capture starts" hidden jarvis_key_state visibility
expect_poll "the hidden J draws the existing listening dot" "$jarvis_widget_hidden_listening" jarvis_widget
expect_poll "hidden capture receives the core's listening observation" listening jarvis_key_state barIndicator
expect_poll "hidden Talk opens capture behind that badge" open jarvis_key_state capture
jarvis_key_talk_up
jarvis_key_commit
jarvis_widget_menu_choose "Stop Jarvis"
jarvis_key_stop_assertion
expect "the shared Stop route never shows the orb" hidden jarvis_key_state visibility
read_count jarvis_widget_resets "the scripted reset calls before New conversation" jarvis_key_effects brain-reset
jarvis_widget_menu_choose "New conversation"
expect_poll "New conversation reaches the scripted brain reset port once" "$((jarvis_widget_resets + 1))" jarvis_key_effects brain-reset
expect "New conversation keeps the current daemon without a retry" ready jarvis_ready 0
expect_poll "a new conversation keeps the hidden choice" hidden jarvis_key_state visibility
expect "Talk, Stop and New conversation keep both independent records" '[true, true]' jarvis_widget_records
jarvis_widget_menu_choose "Show Jarvis" "[\"Hide\",\"Unmute Jarvis's voice\",\"Mute microphone\",\"Stop Jarvis\",\"New conversation\",\"Show Jarvis\",\"Key hints\",\"Readme\",\"Settings\"]"
expect_poll "the bar's Show route restores the shown choice" shown jarvis_key_state visibility
expect_poll "Show restores the ordinary J" "$jarvis_widget_ready" jarvis_widget
expect "Show never unmutes Jarvis's voice" on jarvis_key_state voiceMute
expect "Show changes only its own durable record" '[false, true]' jarvis_widget_records
jarvis_disable
jarvis_enable
expect_poll "the explicit shown choice survives daemon restart" shown jarvis_key_state visibility
expect "the shown restart keeps voice mute" on jarvis_key_state voiceMute
jarvis_widget_menu_choose "Unmute Jarvis's voice"
expect_poll "the menu unmutes Jarvis's voice" off jarvis_key_state voiceMute
expect_poll "voice unmute leaves the state-only tooltip ready" "$jarvis_widget_ready" jarvis_widget
jarvis_disable
jarvis_widget_plant Service.qml "$jarvis_widget_retry_needle" "$jarvis_widget_retry_delay"
jarvis_enable
expect_poll "the retry case draws the ready widget" "$jarvis_widget_ready" jarvis_widget
jarvis_widget_kill
jarvis_widget_restart_assertion
expect_poll "the restarted daemon answers after one retry" ready jarvis_ready 1
expect_poll "the widget reads ready after the restart" "$jarvis_widget_ready" jarvis_widget
jarvis_widget_reset

# Keep the retry. Drop only the report hint that makes a retry a problem
# with plain action text.
jarvis_widget_plant Service.qml "$jarvis_widget_retry_needle" "$jarvis_widget_retry_delay" \
  $'lifetime = { kind: "retry" };\n        publishDaemon(Gate.startStatus(cause, true));' \
  'lifetime = { kind: "retry" }; publish("warning", Gate.startStatus(cause, true).text);'
jarvis_enable
expect_poll "the clear control draws the ready widget" "$jarvis_widget_ready" jarvis_widget
jarvis_widget_kill
expect "a retry report with no action line fails the restarting assertion" 1 jarvis_widget_restart_control
expect_poll "the clear control's daemon answers after one retry" ready jarvis_ready 1
jarvis_widget_reset

# Keep the widget's button and its handler. Drop only the click's call.
jarvis_widget_plant Widget.qml 'onClicked: root.openConsole()' 'onClicked: {}'
jarvis_enable
expect_poll "the click control draws the ready widget" "$jarvis_widget_ready" jarvis_widget
jarvis_widget_click
expect "a widget click that calls nothing fails the click assertion" 1 jarvis_widget_click_control
jarvis_widget_reset

jarvis_widget_input=jarvis-widget-stock
jarvis_widget_select
"$node_bin" "$source_repo/scripts/fixtures/jarvis/prepare.js" --floor-daemon "$jarvis_widget_dir/backend/jarvisd.js"
jarvis_rescan
expect "the permanent-problem widget service enables" ok ipc shell setPluginEnabled vgs.jarvis true
expect_poll "the real service reports its permanent cause" permanent jarvis_permanent
expect_poll "the widget reads the permanent problem" '["vgs-letter-j", "danger", "problem", 1, "danger", ""]' jarvis_widget
expect "the permanent-problem service disables" ok ipc shell setPluginEnabled vgs.jarvis false

notes_off "the widget's deliberate daemon failures"
jarvis_widget_notes=false
hold_stop_keyboard
jarvis_widget_keyboard=false
rm -f -- "$home/.local/state/vgshell/jarvis/voice-mute.json"
rm -f -- "$home/.local/state/vgshell/jarvis/hidden.json"
user_config_restore "$sandbox/jarvis-widget-config-before.json"
cp -- "$sandbox/jarvis-widget-lua-before" "$jarvis_widget_lua"
expect "restore the Jarvis widget configuration" ok ipc shell reloadConfig
expect "restore the nested keyboard configuration" ok hypr reload config-only
row_log_read "$smoke_row_name: fixture shell log" "$instance_log"
jarvis_widget_input=jarvis-widget-stock
jarvis_fixture_begin "$sandbox/tree-$jarvis_widget_input" "$sandbox/tree-$jarvis_widget_input.commands"
jarvis_widget_dir="$jarvis_fixture_tree/shell/plugins/vgs.jarvis"
jarvis_enable
expect_poll "the restored stock daemon remains unconfigured" session jarvis_session unconfigured
expect_poll "the unconfigured widget keeps its state-only tooltip" '["vgs-letter-j", "neutral", "off", 1, "warning", ""]' jarvis_widget
# Tooltip links live in the popup, so read their screen box there. The
# click rests on the first underlined span through click_item, which waits
# for the link to report the pointer and restores a reset hold.
jarvis_widget_link_text='Set it up in [Setup > Voice](page:vgs.jarvis/Setup/setupVoice).'
jarvis_widget_link_box() { ipc smoke popupItemGeometry "$jarvis_widget_key" vgs.jarvis "" "" LinkText "$jarvis_widget_link_text"; }
jarvis_widget_link_drawn() {
  local box
  box="$(jarvis_widget_link_box)" || return
  [[ $box == \[* ]] && echo drawn || echo absent
}
jarvis_widget_link_assertion() { expect "the unconfigured tooltip draws its page link" drawn jarvis_widget_link_drawn; }
# Before each call the pointer sits in the hidden Settings window or on the
# destroyed tooltip, never on the widget, so point_item's moves enter it.
jarvis_widget_link_hover() {
  point_item "$jarvis_widget_key" vgs.jarvis BarItem "" >/dev/null || return
  expect_poll "the unconfigured widget opens its tooltip" true ipc smoke readDescendant "$jarvis_widget_key" vgs.jarvis Tooltip shown
}
jarvis_widget_link_click() {
  local spans pitch offset dx dy
  spans="$(ipc smoke popupItemRead "$jarvis_widget_key" vgs.jarvis "" "" LinkText "$jarvis_widget_link_text" underlined)" || return
  pitch="$(ipc smoke popupItemRead "$jarvis_widget_key" vgs.jarvis "" "" LinkText "$jarvis_widget_link_text" linePitch)" || return
  # An absent link or one with no underlined span has no point to click.
  [[ $spans == \[\{* && $pitch =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 1
  offset="$(python3 -c 'import json,sys; s=json.loads(sys.argv[1])[0]; p=float(sys.argv[2]); print((s["left"]+s["right"])/2, s["line"]*p+p/2)' "$spans" "$pitch")" || return
  read -r dx dy <<<"$offset" || return 1
  click_item popup:"$jarvis_widget_key" vgs.jarvis "" "" LinkText "$jarvis_widget_link_text" "$dx" "$dy"
}
jarvis_notice_close "$jarvis_fixture_shim"
settings_page_open vgs.jarvis
settings_tab_click Settings || fail "the tooltip's target page did not start on Settings"
expect_poll "the tooltip's target starts on the other tab" '"vgs.jarvis/Settings"' ipc smoke readInstance window vgs.settings shownPage
expect "the tooltip starts with Settings closed" ok ipc shell hide window vgs.settings
expect_poll "Settings is hidden before the tooltip link" 0 window_count Plugins
jarvis_widget_link_hover || fail "hovering the unconfigured Jarvis widget failed"
jarvis_widget_link_assertion
jarvis_widget_link_click || fail "the click on the Jarvis tooltip link failed"
expect_poll "the unconfigured tooltip opens Jarvis on Setup" '"vgs.jarvis/Setup"' ipc smoke readInstance window vgs.settings shownPage
settings_page_close vgs.jarvis
jarvis_disable
jarvis_widget_select
jarvis_widget_plant WidgetView.js 'action: "Set it up in [Setup > Voice](page:vgs.jarvis/Setup/setupVoice)."' 'action: "Set it up in Setup > Voice."'
jarvis_enable
expect_poll "the plain-link control reaches the unconfigured daemon" session jarvis_session unconfigured
jarvis_widget_link_hover || fail "hovering the plain-link control failed"
jarvis_widget_plain_link_control() {
  (failures=0 behaviour_failures=0
   jarvis_widget_link_assertion >"$sandbox/jarvis-widget-page-link-control.log"
   echo "$failures")
}
expect "plain tooltip words fail the rendered-link assertion" 1 jarvis_widget_plain_link_control
jarvis_widget_reset
jarvis_enable
expect "the restored nested keys have no configuration errors" '[]' hypr_reload_errors
jarvis_disable
expect_poll "disable removes the widget" absent ipc smoke readInstance "$jarvis_widget_key" vgs.jarvis moduleName
jarvis_notice_close "$jarvis_fixture_shim"
row_log_read "$smoke_row_name: fixture shell log" "$instance_log"
stop_shell
start_shell "$repo" "$smoke_log_dir/jarvis-widget-stock.log"
