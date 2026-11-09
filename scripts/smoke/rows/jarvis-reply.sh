# Jarvis's reply card under the bar J (VGS-2339). While Jarvis Voice is
# muted and the orb is hidden, an answer shows on the card on the focused
# output and a new answer replaces it; the card hides replyCard.duration
# after the answer settles, and stays while the pointer is on it; a click on
# it, or the Open Jarvis console shortcut, opens the console at that answer
# and marks it; a fault reads only on the card while it shows, the overlay's
# hidden-orb fault line stepping aside until it hides; a top-right
# notification stack stands below the card while it shows. The scripted
# daemon fixture answers each typed turn with its reply-text gate's words, or
# fails it with brain=stream-error while its fail-brain gate exists. No
# audio, account, provider or network runs; no PAM, polkit, keyring or TUI
# is reached. No latency ceiling is measured: card and state reads poll once
# per nested IPC round trip and fixture gates at 10 ms, and the hold check
# waits the card's own replyCard.duration, read from the theme, plus one
# second.
# inputs: shell/plugins/vgs.jarvis/manifest.json shell/plugins/vgs.jarvis/Service.qml shell/plugins/vgs.jarvis/Widget.qml shell/plugins/vgs.jarvis/ReplyCard.qml shell/plugins/vgs.jarvis/WidgetView.js shell/plugins/vgs.jarvis/Console.qml shell/plugins/vgs.jarvis/Bubble.qml shell/plugins/vgs.jarvis/backend/* scripts/fixtures/jarvis/* scripts/smoke/rows/jarvis.sh scripts/smoke/user-config.sh shell/Core/Layers.qml shell/Core/Capabilities.qml shell/Hosts/BarHost.qml shell/Ui/BarWidget.qml shell/plugins/vgs.notifications/manifest.json shell/plugins/vgs.notifications/Service.qml shell/plugins/vgs.notifications/Stack.qml
set -euo pipefail
local jarvis_fixture_tree="" jarvis_fixture_shim="" jarvis_fixture_name="" jarvis_fixture_revision=""
jarvis_fixture_begin
expected_errors+=("${jarvis_provoked_errors[@]}")
expected_errors+=("${dictation_absent_errors[@]}")
# The failed turn this row plants is the service's own keyed fault line.
expected_errors+=('WARN qml: jarvis: fault=brain=stream-error kind=error')

reply_config="$home/.config/vgshell/shell.json"
reply_dir="$jarvis_fixture_tree/shell/plugins/vgs.jarvis"
reply_gates="$sandbox/jarvis-reply-gates"
reply_key="$(bar_key)"
cp -- "$reply_config" "$sandbox/jarvis-reply-config-before.json"
"$node_bin" "$source_repo/scripts/fixtures/jarvis/scripted.js" "$reply_dir/backend/jarvisd.js" "$reply_gates" --mapped-indicator
jarvis_rescan
jarvis_enable
# Jarvis enabled on the fixture tree: the configuration the toast step
# returns to.
cp -- "$reply_config" "$sandbox/jarvis-reply-config-enabled.json"

reply_short="Your next meeting is the design review at 3 PM in room 4."
reply_long="Three things changed this week. The bar shows a Jarvis icon that tells you when Jarvis listens, works or has a problem, and you can hide the orb from its menu. The console has a History tab for past conversations, tasks and problems."
reply_gate() { : >"$reply_gates/$1"; }
reply_state() { # phase|REGION
  ipc smoke jarvisProcess | py_reply 'import json,sys
d=json.load(sys.stdin)["status"].get("detail")
print("pending" if d is None else d["phase"] if sys.argv[1]=="phase" else d["state"][sys.argv[1]]["kind"])' "$1"
}
# The card as drawn: MODE:TEXT, the fault's title for a fault, or hidden.
reply_drawn() {
  local shown drawn
  shown="$(ipc smoke readDescendant "$reply_key" vgs.jarvis ReplyCard shown)" \
    && drawn="$(ipc smoke readDescendant "$reply_key" vgs.jarvis ReplyCard drawn)" || return
  py_reply 'import json,sys
shown, drawn = sys.argv[1], sys.stdin.read().strip()
if shown != "true": print("hidden"); sys.exit()
d = json.loads(drawn)
print(d["mode"] + ":" + (d["title"] if d["mode"] == "fault" else d["text"]))' "$shown" <<<"$drawn"
}
# The answer the service's card names, as {gen, at}, or none.
reply_answer() { ipc smoke readInstance service vgs.jarvis replyShown | py_reply 'import json,sys
raw = sys.stdin.read().strip()
v = json.loads(raw) if raw[:1] in "{n" else None
print(json.dumps(v["answer"]) if v else "none")'; }
reply_ask() { # QUESTION WORDS
  printf '%s\n' "$2" >"$reply_gates/reply-text"
  expect "the typed turn is said: $1" ok ipc vgs.jarvis invoke say "$1"
  expect_poll "the typed turn thinks: $1" thinking reply_state phase
  reply_gate brain
  expect_poll "the scripted reply speaks: $1" speaking reply_state phase
}
reply_settle() {
  reply_gate played
  expect_poll "the reply's playback ends" idle reply_state playback
}
reply_card_point() { # the card's centre under the J, as [x, y]
  ipc smoke instanceGeometry "$reply_key" vgs.jarvis | py_reply 'import json,sys
x, y, w, h = json.load(sys.stdin)
print(int(x + w - 180), int(y + h + 50))'
}
reply_leave() { hover 400 600 || fail "the pointer leaves the card"; }
reply_console() { window_count Jarvis; }
reply_marked() { # the console's marked answer, and how many rows draw the mark
  local marked rows
  marked="$(ipc smoke readInstance window vgs.jarvis markedAnswer)" \
    && rows="$(ipc smoke itemValues window vgs.jarvis MessageRow marked)" || return
  py_reply 'import json,sys
raw = sys.argv[1]
marked = json.loads(raw) if raw[:1] in "{n" else raw
rows = json.load(sys.stdin)
print(json.dumps([marked, sum(1 for r in rows if r.get("marked") is True)]))' "$marked" <<<"$rows"
}
reply_console_close() {
  expect "the console opened at the answer hides" ok ipc shell hide window vgs.jarvis
  expect_poll "the console opened at the answer is gone" 0 reply_console
}

expect "Jarvis's voice mutes for the card" ok ipc vgs.jarvis invoke voice-mute ''
expect_poll "the voice mute is published" on reply_state voiceMute
expect_poll "the J is presented before Hide" '"present"' ipc smoke readInstance service vgs.jarvis barIndicator
expect "Jarvis hides its orb for the card" ok ipc vgs.jarvis invoke hide ''
expect_poll "the hidden choice is published" hidden reply_state visibility
expect "no card shows before an answer" hidden reply_drawn

# Show, then replace: the newest answer alone.
reply_ask "When is my next meeting?" "$reply_short"
expect_poll "a muted, hidden Jarvis's answer shows on the card under the J" "answer:$reply_short" reply_drawn
reply_settle
reply_ask "What changed in the shell this week?" "$reply_long"
expect_poll "a new answer replaces the card's text" "answer:$reply_long" reply_drawn

# Auto-hide: no sooner than the theme's hold after the answer settles.
reply_hold_ms="$(ipc smoke themeValue replyCard.duration)" || reply_hold_ms=unread
[[ $reply_hold_ms =~ ^[0-9]+$ ]] || { fail "the card's hold is unreadable: $reply_hold_ms"; reply_hold_ms=0; }
reply_settle
reply_settled_at="$(now_ms)"
expect "the card stays as its answer settles" "answer:$reply_long" reply_drawn
expect_poll "the card hides after its hold" hidden reply_drawn
reply_hidden_after=$(( $(now_ms) - reply_settled_at ))
expect "the card hid no sooner than its ${reply_hold_ms} ms hold" true \
  python3 -c 'import sys; print(str(int(sys.argv[1]) >= int(sys.argv[2]) - 200).lower())' "$reply_hidden_after" "$reply_hold_ms"

# Hover-hold: the pointer on the card holds it past its hold; leaving lets it go.
reply_ask "Is the build green?" "The build is green. Every check passed."
expect_poll "the next answer shows on the card" "answer:The build is green. Every check passed." reply_drawn
reply_settle
read -r reply_x reply_y < <(reply_card_point) || fail "the card has no point under the J"
hover "$reply_x" "$reply_y" || fail "the pointer reaches the card"
expect_poll "the card reports the pointer on it" true ipc smoke readDescendant "$reply_key" vgs.jarvis ReplyCard hovered
expect_poll "the service holds the card under the pointer" true ipc smoke readInstance service vgs.jarvis replyHovered
sleep "$(( (reply_hold_ms + 1000) / 1000 )).$(printf '%03d' $(( (reply_hold_ms + 1000) % 1000 )))"
expect "the pointer holds the card past its hold" "answer:The build is green. Every check passed." reply_drawn
reply_leave
expect_poll "the card hides after the pointer leaves" hidden reply_drawn

# Click to the console: at the card's answer, marked; the card hides.
reply_ask "Where is the design review?" "The design review is in room 4."
expect_poll "the answer for the click shows on the card" "answer:The design review is in room 4." reply_drawn
reply_clicked="$(reply_answer)" || reply_clicked=unread
read -r reply_x reply_y < <(reply_card_point) || fail "the card has no point under the J"
hover "$reply_x" "$reply_y" && click "$reply_x" "$reply_y" || fail "the click on the card is delivered"
expect_poll "a click on the card opens the console" 1 reply_console
expect_poll "the console opens at the card's answer and marks it alone" "[$reply_clicked, 1]" reply_marked
expect_poll "the clicked card hides" hidden reply_drawn
reply_leave
reply_console_close
reply_settle

# The Open Jarvis console shortcut takes the same path while a card shows.
reply_ask "What is on tomorrow?" "Tomorrow holds two meetings and one review."
expect_poll "the answer for the shortcut shows on the card" "answer:Tomorrow holds two meetings and one review." reply_drawn
reply_shortcut="$(reply_answer)" || reply_shortcut=unread
expect "the Open Jarvis console shortcut fires" ok hypr dispatch 'hl.dsp.global("vgs.jarvis:console")'
expect_poll "the shortcut opens the console" 1 reply_console
expect_poll "the shortcut opens the console at the card's answer" "[$reply_shortcut, 1]" reply_marked
expect_poll "the card hides as the shortcut opens the console" hidden reply_drawn
reply_console_close
reply_settle

# Owner choice 3: a top-right toast stands below the card while it shows.
reply_toast_y() { # the newest toast's top in its layer, or none
  ipc smoke layerItems vgs.notifications NotificationCard summary | py_reply 'import json,sys
rows = [r for r in json.load(sys.stdin) if r[2].get("summary") == "Build finished"]
print(rows[0][1][1] if rows else "none")'
}
reply_covers() { ipc smoke readInstance service vgs.notifications barCovers | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
reply_toast_clear() { # whether the toast's top is at or below every cover's bottom
  local toast covers
  toast="$(reply_toast_y)" && covers="$(ipc smoke readInstance service vgs.notifications barCovers)" || return
  py_reply 'import json,sys
covers = json.load(sys.stdin)
bottom = max([c["bottom"] for c in covers] or [0])
print("none" if sys.argv[1] == "none" else "clear" if covers and float(sys.argv[1]) >= bottom else "covered")' "$toast" <<<"$covers"
}
user_config_write python3 - "$reply_config" <<'PY'
import json,sys
from pathlib import Path
config = json.loads(Path(sys.argv[1]).read_text())
rows = [r for r in config.setdefault("plugins", []) if r["id"] == "vgs.notifications"]
row = rows[0] if rows else None
if row is None:
    row = {"id": "vgs.notifications"}
    config["plugins"].append(row)
row["position"] = "top-right"
print(json.dumps(config))
PY
expect "the toast position reloads at top right" ok ipc shell reloadConfig
notes_on "the card beside a top-right toast"
"${shell_env[@]}" gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
  --method org.freedesktop.Notifications.Notify smoke-build 0 "" "Build finished" "vgs main is green" '[]' '{"urgency": <byte 2>}' 0 >/dev/null \
  || fail "the top-right toast is sent"
expect_poll "the top-right toast is on screen" 1 notes_on_screen
reply_ask "Who reviews the change?" "Ana reviews the change today."
expect_poll "the card shows beside the toast" "answer:Ana reviews the change today." reply_drawn
expect_poll "the bar host publishes the card's box" 1 reply_covers
expect_poll "the top-right toast stands below the card" clear reply_toast_clear
reply_cover_bottom="$(ipc smoke readInstance service vgs.notifications barCovers | py_reply 'import json,sys; print(max([c["bottom"] for c in json.load(sys.stdin)] or [0]))')" || reply_cover_bottom=0
reply_toast_risen() { # whether the toast's top is back above the card's former bottom
  local toast
  toast="$(reply_toast_y)" || return
  [[ $reply_cover_bottom =~ ^[0-9.]+$ ]] || { echo "no-cover"; return; }
  py_reply 'import sys; print("top" if float(sys.stdin.read()) < float(sys.argv[1]) else "below")' "$reply_cover_bottom" <<<"$toast"
}
reply_settle
expect_poll "the card hides beside the toast" hidden reply_drawn
expect_poll "the toast returns to the top once the card is gone" top reply_toast_risen
notes_off "the card beside a top-right toast"
user_config_restore "$sandbox/jarvis-reply-config-enabled.json"
expect "the toast position reloads as it was" ok ipc shell reloadConfig

# Owner choice 1: with the orb hidden, a fault reads only on the card while
# it shows; the overlay's hidden-orb fault line returns once it hides.
reply_fault_lines() { ipc smoke layerItemsWith vgs.jarvis LinkText visible true; }
reply_gate fail-brain
expect "the failing turn is said" ok ipc vgs.jarvis invoke say "Summarize my unread mail"
expect_poll "the failing turn thinks" thinking reply_state phase
reply_gate brain
expect_poll "the failed turn reaches the fault" error reply_state phase
expect_poll "the fault reads on the card" "fault:The AI model did not answer" reply_drawn
expect_poll "the overlay draws no hidden-orb fault line while the card shows" 0 reply_fault_lines
expect_poll "the card hides after its hold" hidden reply_drawn
expect_poll "the overlay's hidden-orb fault line returns once the card hides" 1 reply_fault_lines

jarvis_disable
rm -f -- "${home:?}/.local/state/vgshell/jarvis/voice-mute.json" "${home:?}/.local/state/vgshell/jarvis/hidden.json"
user_config_restore "$sandbox/jarvis-reply-config-before.json"
expect "the reply row's configuration reloads" ok ipc shell reloadConfig
stop_shell
start_shell "$repo" "$smoke_log_dir/jarvis-reply-stock.log"
