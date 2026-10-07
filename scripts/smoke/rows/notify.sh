# Plugin messages: the fixture service sends system notifications through
# its `notify` capability, and the row reads them back as the cards
# vgs.notifications draws, its saved History, the fixture's own
# notification subscription and the shell log. A card names the fixture's
# manifest name as its sender and carries the tone, icon and urgency it
# was sent with and a click that only dismisses; its message arrives with
# `&`, `<` and `>` escaped, since the server reads a body as markup. A
# transient message's card leaves no History entry and a lasting one's
# does. Under Silence a critical message still draws its card, as the
# x-vgs-plugin hint the core adds lets it, and a normal one goes to History
# unseen. Each malformed option is refused with its key, and a burst past
# the run ceiling is refused as busy. With vgs.notifications disabled the
# fixture's own subscription keeps the core's server up and the fixture
# receives the message; with no plugin holding the `notifications` role,
# acme.notifier's message is dropped and the shell logs one unsent line.
# inputs: scripts/smoke/fixtures/plugins/acme.probe/* scripts/smoke/fixtures/plugins/acme.notifier/* shell/Core/Notifier.qml shell/Core/PluginLogic.js shell/Core/Capabilities.qml shell/Core/NotificationHub.qml shell/plugins/vgs.notifications/* scripts/smoke/rows/plugins.sh
set -euo pipefail
notify_send() { ipc acme.probe invoke notify "$1"; }
# notify_refused_key OPTIONS_JSON: the key a refusal names, the word after
# `refused: notify=`, or the whole reply when it is no refusal.
notify_refused_key() {
  local reply
  reply="$(notify_send "$1")" || return
  if [[ $reply != "refused: notify="* ]]; then printf '%s\n' "$reply"; return; fi
  reply="${reply#refused: notify=}"
  printf '%s\n' "${reply%% *}"
}
# probe_card SUMMARY: the fixture's card with SUMMARY as plugin_cards reads
# it, less the summary, or none.
probe_card() { plugin_cards Probe | py_reply 'import json,sys; print(json.dumps(next((r[1:] for r in json.load(sys.stdin) if r[0] == sys.argv[1]), "none")))' "$1"; }
probe_heard() { ipc smoke readInstance service acme.probe lastSummary; }
notify_server() { ipc shell lent | py_reply 'import json,sys; print(json.load(sys.stdin)["notificationServer"])'; }
# in_probe_history SUMMARY: whether History holds the fixture's SUMMARY;
# False before the store's first save.
in_probe_history() {
  python3 -c 'import json,pathlib,sys
p = pathlib.Path(sys.argv[1])
print(p.exists() and any(e["app"] == "Probe" and e["summary"] == sys.argv[2] for e in json.loads(p.read_text())["history"]))' "$home/.local/state/vgshell/notifications/state.json" "$1"
}
# burst_shape REPLIES: `busy-last` when the replies are oks and then the
# busy refusal, at least one of each, else the replies.
burst_shape() {
  python3 -c 'import sys
r = sys.argv[1].split(",")
busy = "refused: notify=busy limit=" + sys.argv[2]
n = r.index(busy) if busy in r else len(r)
print("busy-last" if 0 < n < len(r) and all(x == "ok" for x in r[:n]) and all(x == busy for x in r[n:]) else sys.argv[1])' "$1" "$2"
}

expect "enabling the fixture for the notify rows is allowed" ok ipc shell setPluginEnabled acme.probe true
expect_poll "the fixture service is built for the notify rows" True record_exists acme.probe
notes_on "notify"

# One card per message: the sender's name, its tone, icon and urgency,
# a click that only dismisses, and the message escaped.
expect "a message with every option is sent" ok notify_send '{"title": "Probe saved", "message": "a<b> & c", "tone": "success", "icon": "circle-check", "urgency": "critical"}'
expect_poll "its card names the fixture and carries its options" '["a&lt;b&gt; &amp; c", 2, "success", "circle-check", "none"]' probe_card "Probe saved"
notes_first_card "the critical card"
expect "a transient low message is sent" ok notify_send '{"title": "Probe passing", "tone": "info", "icon": "bell", "urgency": "low", "transient": true}'
expect_poll "its card carries low urgency" '["", 0, "info", "bell", "none"]' probe_card "Probe passing"
expect "a message with a title alone is sent" ok notify_send '{"title": "Probe plain"}'
expect_poll "its card is normal urgency with no tone or icon" '["", 1, "", "", "none"]' probe_card "Probe plain"
# Control: a card from the same sender that did not come through the
# core's route carries none of its hints, and the reader tells it apart.
"${shell_env[@]}" gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
  --method org.freedesktop.Notifications.Notify Probe 0 "" "Probe planted" "a<b> & c" '[]' '{"urgency": <byte 2>}' 0 >/dev/null \
  || fail "notify: the planted card was not sent"
expect_poll "control: a card sent around the route reads without its hints" '["a<b> & c", 2, "", "", ""]' probe_card "Probe planted"

# Refusals, one per option, each naming its key.
expect "options that are no object are refused" options notify_refused_key '"Probe"'
expect "an unknown option is refused" duration notify_refused_key '{"title": "t", "duration": 0}'
expect "a message without a title is refused" title notify_refused_key '{"message": "m"}'
expect "a blank title is refused" title notify_refused_key '{"title": " "}'
expect "a message that is no text is refused" message notify_refused_key '{"title": "t", "message": 4}'
expect "a tone the hint does not take is refused" tone notify_refused_key '{"title": "t", "tone": "neutral"}'
expect "an icon outside the Lucide grammar is refused" icon notify_refused_key '{"title": "t", "icon": "Camera"}'
expect "an unknown urgency is refused" urgency notify_refused_key '{"title": "t", "urgency": "high"}'
expect "a transient that is no boolean is refused" transient notify_refused_key '{"title": "t", "transient": "yes"}'

# A burst in one call: no run can end while the call runs, so at most
# PluginLogic.NOTIFY_RUNS_MAX are in flight and the rest answer busy.
burst="$(ipc acme.probe invoke notify-burst '9 {"title": "Probe burst", "urgency": "low", "transient": true}')" || burst="unread"
expect "a burst past the run ceiling ends in busy" busy-last burst_shape "$burst" 8

# A dismissed transient card leaves no History entry and a lasting one
# does. The lasting one goes second, so the History read after it is a
# save that already followed the transient card's leaving.
notes_clear "notify"
expect "a transient message is sent" ok notify_send '{"title": "Probe quiet", "transient": true}'
expect_poll "the transient card shows" '["", 1, "", "", "none"]' probe_card "Probe quiet"
notes_clear "notify: the transient card"
expect "a lasting message is sent" ok notify_send '{"title": "Probe kept"}'
expect_poll "the lasting card shows" '["", 1, "", "", "none"]' probe_card "Probe kept"
notes_clear "notify: the lasting card"
expect_poll "the dismissed lasting card went to History" True in_probe_history "Probe kept"
expect "the dismissed transient card left no History entry" False in_probe_history "Probe quiet"

# Under Silence a critical plugin message draws its card and a normal one
# goes to History unseen. The normal one goes first, so once the critical
# card shows the normal one was judged too.
expect "Silence turns on" on ipc vgs.notifications invoke silence on
expect "a normal message is sent under Silence" ok notify_send '{"title": "Probe hushed"}'
expect "a critical message is sent under Silence" ok notify_send '{"title": "Probe urgent", "urgency": "critical"}'
expect_poll "the critical message draws its card under Silence" '["", 2, "", "", "none"]' probe_card "Probe urgent"
expect_poll "the normal message went to History under Silence" True in_probe_history "Probe hushed"
expect "the normal message draws no card under Silence" '"none"' probe_card "Probe hushed"
expect "Silence turns off" off ipc vgs.notifications invoke silence off
notes_off "notify"

# With vgs.notifications disabled the fixture's own subscription keeps the
# core's server up: the message reaches it, and nothing is logged.
expect "the server stays up for the fixture's subscription" True notify_server
expect "a message with no drawing plugin is sent" ok notify_send '{"title": "Probe unseen"}'
expect_poll "the server holding the name received it" '"Probe unseen"' probe_heard
expect "the delivered message logs no unsent line" 0 log_lines 'notify: unsent plugin=acme\.probe '

# With no plugin holding the `notifications` role nothing draws: the core
# drops the message and logs one line naming the sender. This reads the
# case where the shell already built its own server, which keeps the
# notification name for the rest of its life (NotificationHub.holdsName):
# notes_on built it above, so the case where no server was ever built, in
# which notify-send itself fails, cannot be reached in a running smoke. The
# delivered message above, which logged no line, is this reading's
# counterpart.
expected_errors+=('notify: unsent plugin=acme\.notifier ')
notifier_dir="$home/.config/vgshell/plugins/acme.notifier"
mkdir -p -- "$notifier_dir"
cp -R "$repo/scripts/smoke/fixtures/plugins/acme.notifier/." "$notifier_dir/"
rescan "rescan after adding the notifier fixture answers ok"
expect_poll "the notifier fixture is discovered" True plugin_known acme.notifier
expect "disabling the fixture for the undrawn message is allowed" ok ipc shell setPluginEnabled acme.probe false
expect_poll "the fixture service is gone" False record_exists acme.probe
expect "enabling the notifier fixture is allowed" ok ipc shell setPluginEnabled acme.notifier true
expect_poll "the notifier fixture service is built" True record_exists acme.notifier
expect_poll "no plugin keeps the notification server up" False notify_server
layers_before="$(layer_count vgs:layer)" || layers_before=unread
expect "a message nothing draws answers ok" ok ipc acme.notifier invoke notify '{"title": "Notifier dropped"}'
expect_log "the core logs the dropped message" 1 'notify: unsent plugin=acme\.notifier reason=no-drawer'
expect "the core logs it once" 1 log_lines 'notify: unsent plugin=acme\.notifier '
expect "the dropped message draws no surface" "$layers_before" layer_count vgs:layer
expect "disabling the notifier fixture is allowed" ok ipc shell setPluginEnabled acme.notifier false
expect_poll "the notifier fixture service is gone" False record_exists acme.notifier
rm -rf -- "${notifier_dir:?}"
rescan "rescan after removing the notifier fixture answers ok"
expect_poll "the notifier fixture is forgotten" False plugin_known acme.notifier
expect "re-enabling the fixture is allowed" ok ipc shell setPluginEnabled acme.probe true
expect_poll "the fixture is back" True record_exists acme.probe
