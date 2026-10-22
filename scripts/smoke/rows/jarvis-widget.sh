# The Jarvis bar widget against private scripted Session ports: its
# section, every state read back as drawn, its icon beside the Voice
# widget's, a click on the widget that opens the console, and privacy mute
# by the Mute row of its right-click menu and by the physical Mute key. Its
# unconfigured tooltip draws a link that opens Jarvis's Setup tab; plain
# words fail the link reading.
# No audio, account, provider or
# network runs; no PAM, polkit, keyring or TUI is reached. No latency
# ceiling is measured. Widget and state reads poll once per nested IPC
# round trip; fixture callback gates poll at 10 ms.
# inputs: scripts/smoke/user-config.sh shell/plugins/vgs.jarvis/* shell/Ui/foundation/KeyNavLogic.js scripts/fixtures/jarvis/* scripts/smoke/keyboard/* scripts/smoke/rows/jarvis.sh scripts/smoke/rows/jarvis-keys.sh scripts/smoke/rows/hold-shortcuts.sh scripts/smoke/rows/hyprland-consent.sh shell/Core/Notifier.qml shell/plugins/vgs.notifications/* bin/lib/qml-library.js shell/Ui/overlay/Tooltip.qml shell/Ui/controls/BarItem.qml shell/Ui/feedback/LinkText.qml shell/Commons/PageReference.js shell/plugins/vgs.settings/manifest.json shell/plugins/vgs.settings/Window.qml shell/plugins/vgs.settings/ListPage.qml shell/plugins/vgs.settings/PluginPage.qml shell/plugins/vgs.settings/PageHeader.qml shell/plugins/vgs.settings/EditSet.qml shell/plugins/vgs.settings/Steps.js shell/plugins/vgs.settings/SettingField.qml shell/plugins/vgs.settings/ListField.qml shell/plugins/vgs.settings/KeyField.qml shell/plugins/vgs.settings/StatusRow.qml shell/plugins/vgs.settings/StatusLine.qml shell/plugins/vgs.settings/RequirementRow.qml shell/plugins/vgs.voice/Widget.qml shell/plugins/vgs.voice/manifest.json shell/Ui/BarWidget.qml
set -euo pipefail
# Jarvis holds `dictation`, and the shell finds no voxtype: the core's
# probe does not start at each enable.
expected_errors+=("${dictation_absent_errors[@]}")

jarvis_widget_config="$home/.config/vgshell/shell.json"
jarvis_widget_lua="$home/.config/hypr/hyprland.lua"
jarvis_widget_dir="$repo/shell/plugins/vgs.jarvis"
jarvis_widget_gates="$sandbox/jarvis-widget-gates"
jarvis_widget_files=(Service.qml Widget.qml WidgetView.js backend/jarvisd.js backend/ChainedEngine.js)
cp -- "$jarvis_widget_config" "$sandbox/jarvis-widget-config-before.json"
cp -- "$jarvis_widget_lua" "$sandbox/jarvis-widget-lua-before"
for jarvis_widget_file in "${jarvis_widget_files[@]}"; do
  cp -- "$jarvis_widget_dir/$jarvis_widget_file" "$sandbox/jarvis-widget-before-${jarvis_widget_file##*/}"
done
jarvis_widget_key="$(bar_key)"
expect "the widget row starts with Jarvis disabled" absent ipc smoke jarvisProcess
expect "a disabled Jarvis draws no widget" absent ipc smoke readInstance "$jarvis_widget_key" vgs.jarvis moduleName
"$node_bin" "$source_repo/scripts/fixtures/jarvis/scripted.js" "$jarvis_widget_dir/backend/jarvisd.js" "$jarvis_widget_gates"
jarvis_gate="$sandbox/jarvis-widget-startup-gate"
jarvis_seen="$sandbox/jarvis-widget-startup-seen"
"$node_bin" "$source_repo/scripts/fixtures/jarvis/prepare.js" --gate-daemon "$jarvis_widget_dir/backend/jarvisd.js" "$jarvis_gate" "$jarvis_seen"
jarvis_rescan

jarvis_widget_gate() { : >"$jarvis_widget_gates/$1"; }
jarvis_widget_section() { ipc shell listShellConfig | py_reply 'import json,sys; l=json.load(sys.stdin)["bar"]["layout"]; print(([s for s in ("left","center","right") if any(e["id"]==sys.argv[1] for e in l.get(s,[]))] + ["none"])[0])' vgs.jarvis; }
jarvis_widget_tones="$(python3 -c 'import json,sys; print(json.dumps(dict(zip(["calm", "neutral", "accent", "info", "danger"], [json.loads(v).lower() for v in sys.argv[1:]]))))' \
  "$(ipc smoke themeValue bar.foreground)" "$(ipc smoke themeValue color.textMuted)" \
  "$(ipc smoke themeValue color.accent)" "$(ipc smoke themeValue color.info)" \
  "$(ipc smoke themeValue color.danger)")" || fail "the widget tones are unreadable"
# The widget as drawn: [icon, tone, tooltip], the tone named by the token
# whose colour the icon draws in, or `absent`.
jarvis_widget() {
  local icon colours tip details
  icon="$(ipc smoke readDescendant "$jarvis_widget_key" vgs.jarvis Icon name)" \
    && colours="$(ipc smoke itemColours "$jarvis_widget_key" vgs.jarvis Widget Icon)" \
    && tip="$(ipc smoke readDescendant "$jarvis_widget_key" vgs.jarvis Tooltip text)" \
    && details="$(ipc smoke readDescendant "$jarvis_widget_key" vgs.jarvis Tooltip details)" || return
  python3 - "$icon" "$colours" "$tip" "$details" "$jarvis_widget_tones" <<'PY'
import json, sys
icon, colours, tip, details, tones = sys.argv[1:6]
if "absent" in (icon, colours, tip, details):
    print("absent"); sys.exit()
colour = json.loads(colours)[0][0]
names = [name for name, value in json.loads(tones).items() if "#" + value[3:9] + value[1:3] == colour]
tip_text = json.loads(tip)
detail_lines = json.loads(details)
if detail_lines:
    tip_text += "\n" + "\n".join(str(line) for line in detail_lines)
print(json.dumps([json.loads(icon), names[0] if len(names) == 1 else "colour=" + colour, tip_text]))
PY
}
# One fact a line after the state's first: the AI model, then the voice
# (the scripted brain, the default Local), then what a click does.
jarvis_widget_facts='AI model: Scripted\nVoice: Local\nClick or press Super+Alt+C to open the console.'
jarvis_widget_ready="[\"vgs-letter-j\", \"calm\", \"Ready to talk\\nTap or hold Super+Right Alt, then speak.\\n${jarvis_widget_facts}\"]"
jarvis_widget_listening="[\"audio-lines\", \"accent\", \"Jarvis is listening\\nSpeak now.\\n${jarvis_widget_facts}\"]"
jarvis_widget_muted="[\"mic-off\", \"neutral\", \"Jarvis is muted\\nPress Super+Shift+Right Alt to unmute.\\n${jarvis_widget_facts}\"]"
jarvis_widget_click() { click_centre "$jarvis_widget_key" vgs.jarvis || fail "the click on the Jarvis widget failed"; }
jarvis_widget_consoles() { window_count Jarvis; }
jarvis_widget_click_opens() { expect_poll "a click on the widget opens the console" 1 jarvis_widget_consoles; }
jarvis_widget_console_close() {
  expect "the console opened from the widget hides" ok ipc shell hide window vgs.jarvis
  expect_poll "the console opened from the widget is gone" 0 jarvis_widget_consoles
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
jarvis_widget_menu_mutes() { expect_poll "the menu's Mute row mutes Jarvis" "$jarvis_widget_muted" jarvis_widget; }
jarvis_widget_menu_control() {
  (failures=0 behaviour_failures=0
   jarvis_widget_menu_mutes >"$sandbox/jarvis-widget-menu-control.log"
   echo "$failures")
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
jarvis_widget_closing() { expect_poll "the widget reads listening while muting closes capture" "$jarvis_widget_listening" jarvis_widget; }
jarvis_widget_closing_control() {
  (failures=0 behaviour_failures=0
   jarvis_widget_closing >"$sandbox/jarvis-widget-closing-control.log"
   echo "$failures")
}
jarvis_widget_closing_control_check() { expect "a view that ignores capture fails the closing assertion" 1 jarvis_widget_closing_control; }
# A toggle conversation, then the physical Mute key while the scripted
# capture holds its close; ASSERTION reads the widget before the close.
jarvis_widget_mute_while_listening() { # ASSERTION
  jarvis_key_mode toggle
  jarvis_key_talk_down
  jarvis_key_talk_up
  expect_poll "a toggle press opens a conversation" listening jarvis_key_state phase
  jarvis_widget_gate hold-close
  jarvis_key_mute
  expect_poll "mute waits for the scripted capture teardown" muting jarvis_key_state mute
  "$1"
  jarvis_widget_gate close
  expect_poll "mute completes once capture closes" on jarvis_key_state mute
  rm -- "$jarvis_widget_gates/hold-close"
  jarvis_widget_menu_choose "Unmute Jarvis"
  expect_poll "the menu's Unmute row unmutes after the conversation" off jarvis_key_state mute
  jarvis_key_mode hold
}
# With Jarvis disabled, put FILE's copy from before the row back with each
# NEEDLE replaced by its REPLACEMENT once, and rescan.
jarvis_widget_plant() { # FILE NEEDLE REPLACEMENT [NEEDLE REPLACEMENT]...
  python3 - "$sandbox/jarvis-widget-before-$1" "$jarvis_widget_dir/$1" "${@:2}" <<'PY'
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
  python3 - "$widget" "$process" <<'PY'
import json, sys
t, p = sys.argv[1], sys.argv[2]
r = None if t == "absent" else json.loads(t)
d = None if p in ("absent", "missing") else json.loads(p)
ok = (r is not None and d is not None and r[:2] == ["circle-alert", "danger"]
      and d["lifetime"]["kind"] == "retry" and d["status"]["daemon"]["tone"] == "warning"
      and d["status"]["daemon"].get("hint") == "Jarvis is trying again by itself")
print("restarting" if ok else t)
PY
}
# The widget's icon and tone alone.
jarvis_widget_look() { jarvis_widget | py_reply 'import json,sys; t=sys.stdin.read().strip(); print(t if t == "absent" else json.dumps(json.loads(t)[:2]))'; }
# The widget's icon, tone and tooltip line, beside whether the service
# offers the local voice step, for the line WidgetView.js says while that
# step is to do.
jarvis_widget_setup() {
  local widget process
  widget="$(jarvis_widget)" && process="$(ipc smoke jarvisProcess)" || return
  python3 - "$widget" "$process" <<'PY'
import json, sys
t, p = sys.argv[1], sys.argv[2]
if "absent" in (t, p) or p == "missing":
    print("absent"); sys.exit()
r, d = json.loads(t), json.loads(p)
step = d["status"].get("setupVoice") or {}
print(json.dumps([r[0], r[1], r[2].split("\n")[0], step.get("action")], separators=(",", ":")))
PY
}
jarvis_widget_voice_line() {
  "$node_bin" -e 'const { load } = require(process.argv[1]);
const PageReference = load(process.argv[3]);
const view = load(process.argv[2], { "qs.Commons 1.0": { PageReference } });
process.stdout.write(JSON.stringify(["vgs-letter-j", "neutral", view.SETUP_TEXT.find(row => row[0] === "setupVoice")[1].title, "setup"]));' \
    "$repo/bin/lib/qml-library.js" "$repo/shell/plugins/vgs.jarvis/WidgetView.js" "$repo/shell/Commons/PageReference.js"
}
jarvis_widget_restart_assertion() { expect_poll "the widget reads loading after the daemon ends" restarting jarvis_widget_restarting; }
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
jarvis_widget_restore() { # FILE
  jarvis_disable
  cp -- "$sandbox/jarvis-widget-before-$1" "$jarvis_widget_dir/$1"
  jarvis_rescan
}

printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = false } })' >>"$jarvis_widget_lua"
expect "Jarvis keys use the physical evdev map" ok hypr reload config-only
hold_start_keyboard jarvis-widget "$sandbox/keyboard" us ""

rm -f -- "$jarvis_gate" "$jarvis_seen"
expect "the gated widget service enables" ok ipc shell setPluginEnabled vgs.jarvis true
expect_poll "enabling places the widget in the bar's right section" right jarvis_widget_section
expect_poll "the startup daemon consumes hello" seen jarvis_seen_hello
expect_poll "the widget reads loading before the first state" '["loader", "info", "Jarvis is starting\nWait for Jarvis to start.\nClick or press Super+Alt+C to open the console."]' jarvis_widget
: >"$jarvis_gate"
expect "the gated daemon answers hello" ready jarvis_wait_ready
expect_poll "the widget reads ready" "$jarvis_widget_ready" jarvis_widget
jarvis_key_mode hold
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
expect_poll "the widget reads working while Jarvis thinks" "[\"brain\", \"info\", \"Jarvis is thinking\\nPress Super+Alt+Period to stop.\\n${jarvis_widget_facts}\"]" jarvis_widget
jarvis_widget_gate brain
expect_poll "the scripted brain speaks" speaking jarvis_key_state phase
expect_poll "the widget reads speaking during playback" "[\"volume-2\", \"accent\", \"Jarvis is speaking\\nPress Super+Alt+Period to stop.\\n${jarvis_widget_facts}\"]" jarvis_widget
jarvis_widget_gate played
expect_poll "scripted playback returns to idle" idle jarvis_key_state phase
expect_poll "the widget reads ready after the answer" "$jarvis_widget_ready" jarvis_widget

jarvis_widget_click
jarvis_widget_click_opens
expect "a click on the widget leaves mute off" off jarvis_key_state mute
jarvis_widget_console_close
jarvis_widget_menu_choose "Mute Jarvis" '["Hide","Mute Jarvis","Readme","Settings"]'
jarvis_widget_menu_mutes
expect "the menu's Mute row reached the service's mute" on jarvis_key_state mute
jarvis_key_mute
expect_poll "the physical Mute key unmutes what the menu muted" "$jarvis_widget_ready" jarvis_widget
jarvis_key_mute
expect_poll "the physical Mute key mutes again" "$jarvis_widget_muted" jarvis_widget
jarvis_widget_menu_choose "Unmute Jarvis"
expect_poll "the menu's Unmute row unmutes Jarvis" "$jarvis_widget_ready" jarvis_widget
expect "unmute alone keeps capture closed" closed jarvis_key_state capture
jarvis_widget_mute_while_listening jarvis_widget_closing
expect_poll "the widget reads ready after the toggle case" "$jarvis_widget_ready" jarvis_widget

jarvis_disable
jarvis_widget_plant Service.qml "$jarvis_widget_retry_needle" "$jarvis_widget_retry_delay"
jarvis_enable
expect_poll "the retry case draws the ready widget" "$jarvis_widget_ready" jarvis_widget
jarvis_widget_kill
jarvis_widget_restart_assertion
expect_poll "the restarted daemon answers after one retry" ready jarvis_ready 1
expect_poll "the widget reads ready after the restart" "$jarvis_widget_ready" jarvis_widget
jarvis_widget_restore Service.qml

# Keep the retry. Drop only the report hint that makes a retry a problem
# with plain action text.
jarvis_widget_plant Service.qml "$jarvis_widget_retry_needle" "$jarvis_widget_retry_delay" \
  $'lifetime = { kind: "retry", pendingMute: lifetime.pendingMute };\n        publishDaemon(Gate.startStatus(cause, true));' \
  'lifetime = { kind: "retry", pendingMute: lifetime.pendingMute }; publish("warning", Gate.startStatus(cause, true).text);'
jarvis_enable
expect_poll "the clear control draws the ready widget" "$jarvis_widget_ready" jarvis_widget
jarvis_widget_kill
expect "a retry report with no action line fails the restarting assertion" 1 jarvis_widget_restart_control
expect_poll "the clear control's daemon answers after one retry" ready jarvis_ready 1
jarvis_widget_restore Service.qml

# Keep the widget's button and its handler. Drop only the click's call.
jarvis_widget_plant Widget.qml 'onClicked: root.view.click === "resume" ? root.offer("resume-session") : root.openConsole()' 'onClicked: {}'
jarvis_enable
expect_poll "the click control draws the ready widget" "$jarvis_widget_ready" jarvis_widget
jarvis_widget_click
expect "a widget click that calls nothing fails the click assertion" 1 jarvis_widget_click_control
jarvis_widget_restore Widget.qml

# Keep the IPC handler and its reply. Drop only the mute intent it sends.
jarvis_widget_plant Service.qml 'intent("mute"); return "ok";' 'return "ok";'
jarvis_enable
expect_poll "the handler control draws the ready widget" "$jarvis_widget_ready" jarvis_widget
jarvis_widget_menu_choose "Mute Jarvis"
expect "a handler that sends no intent fails the menu's Mute assertion" 1 jarvis_widget_menu_control
jarvis_widget_restore Service.qml

# Judge the microphone by the phase instead of the capture region.
jarvis_widget_plant WidgetView.js 'microphoneOpen(state.capture)) return' '(detail.phase === "listening" || detail.phase === "armed")) return'
jarvis_enable
jarvis_widget_mute_while_listening jarvis_widget_closing_control_check
jarvis_widget_restore WidgetView.js

cp -- "$sandbox/jarvis-widget-before-jarvisd.js" "$jarvis_widget_dir/backend/jarvisd.js"
"$node_bin" "$source_repo/scripts/fixtures/jarvis/prepare.js" --floor-daemon "$jarvis_widget_dir/backend/jarvisd.js"
jarvis_rescan
expect "the permanent-problem widget service enables" ok ipc shell setPluginEnabled vgs.jarvis true
expect_poll "the real service reports its permanent cause" permanent jarvis_permanent
expect_poll "the widget reads the permanent problem" '["circle-alert", "danger"]' jarvis_widget_look
# The refusal is a Jarvis card, read while vgs.notifications draws with
# Silence off; it goes back to disabled, as the row found it, after.
notes_on "the problem-state refusal"
jarvis_widget_refused="$(jarvis_key_refusals 'Jarvis needs Node 22 or later')"
jarvis_widget_menu_choose "Mute Jarvis"
expect_poll "the menu's Mute row in the problem state reports the refusal" "$((jarvis_widget_refused + 1))" jarvis_key_refusals 'Jarvis needs Node 22 or later'
expect "the permanent-problem service disables" ok ipc shell setPluginEnabled vgs.jarvis false
notes_off "the problem-state refusal"

hold_stop_keyboard
for jarvis_widget_file in "${jarvis_widget_files[@]}"; do
  cp -- "$sandbox/jarvis-widget-before-${jarvis_widget_file##*/}" "$jarvis_widget_dir/$jarvis_widget_file"
done
rm -- "$jarvis_widget_dir/backend/scripted-fixture.js"
rm -- "$home/.local/state/vgshell/jarvis/mute.json"
jarvis_rescan
user_config_restore "$sandbox/jarvis-widget-config-before.json"
cp -- "$sandbox/jarvis-widget-lua-before" "$jarvis_widget_lua"
expect "restore the Jarvis widget configuration" ok ipc shell reloadConfig
expect "restore the nested keyboard configuration" ok hypr reload config-only
jarvis_enable
expect_poll "the restored stock daemon remains unconfigured" session jarvis_session unconfigured
jarvis_widget_voice_expected="$(jarvis_widget_voice_line)" || fail "WidgetView.js's local voice line is unreadable"
expect_poll "the widget names the remaining setup step for the unconfigured daemon" "$jarvis_widget_voice_expected" jarvis_widget_setup

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
jarvis_notice_close
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
jarvis_widget_restore WidgetView.js
jarvis_enable
expect "the restored nested keys have no configuration errors" '[]' hypr_reload_errors
expect "the widget row leaves no Jarvis state file" False \
  python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).exists())' "$home/.local/state/vgshell/jarvis/mute.json"
jarvis_disable
expect_poll "disable removes the widget" absent ipc smoke readInstance "$jarvis_widget_key" vgs.jarvis moduleName
jarvis_notice_close
