# Physical Jarvis keys against private scripted Session ports. No audio,
# account, provider or network runs. No latency ceiling is measured.
# State/effect reads poll once per nested IPC round trip. Fixture callback
# gates poll at 10 ms; hold barriers use the shell's native marker.
# inputs: scripts/smoke/user-config.sh shell/plugins/vgs.jarvis/* scripts/fixtures/jarvis/* shell/Core/ShortcutRegistry.qml scripts/smoke/keyboard/* scripts/smoke/fixtures/plugins/acme.probe/* shell/plugins/vgs.bar/* shell/Ui/feedback/VoiceOrb.qml shell/Core/Layers.qml shell/Hosts/AppWindow.qml shell/Hosts/SummonHost.qml scripts/smoke/toplevel/* shell/Core/HyprlandLayer.js scripts/smoke/rows/jarvis-bubble.sh scripts/smoke/rows/jarvis.sh scripts/smoke/rows/hold-shortcuts.sh scripts/smoke/rows/capabilities.sh scripts/smoke/rows/plugins.sh scripts/smoke/rows/hyprland-consent.sh shell/Core/Notifier.qml shell/plugins/vgs.notifications/*
set -euo pipefail
# Jarvis holds `dictation`, and the shell finds no voxtype: the core's
# probe does not start at each enable.
expected_errors+=("${dictation_absent_errors[@]}")

jarvis_key_config="$home/.config/vgshell/shell.json"
jarvis_key_lua="$home/.config/hypr/hyprland.lua"
jarvis_key_service="$repo/shell/plugins/vgs.jarvis/Service.qml"
jarvis_key_backend="$repo/shell/plugins/vgs.jarvis/backend/jarvisd.js"
jarvis_key_engine="$repo/shell/plugins/vgs.jarvis/backend/ChainedEngine.js"
jarvis_key_session="$repo/shell/plugins/vgs.jarvis/Session.js"
jarvis_key_gates="$sandbox/jarvis-key-gates"
cp -- "$jarvis_key_config" "$sandbox/jarvis-key-config-before.json"
cp -- "$jarvis_key_lua" "$sandbox/jarvis-key-lua-before"
cp -- "$jarvis_key_service" "$sandbox/jarvis-key-service-before"
cp -- "$jarvis_key_backend" "$sandbox/jarvis-key-backend-before"
cp -- "$jarvis_key_engine" "$sandbox/jarvis-key-engine-before"
cp -- "$jarvis_key_session" "$sandbox/jarvis-key-session-before"
# Session's own bounds: a release sooner than TAP_MS is a tap, and a tapped
# request ends by itself TAP_SILENCE_MS after the tap or its last words.
jarvis_key_tap_ms="$(sed -n 's/^var TAP_MS = \([0-9][0-9]*\);$/\1/p' "$jarvis_key_session")"
jarvis_key_silence_ms="$(sed -n 's/^var TAP_SILENCE_MS = \([0-9][0-9]*\);$/\1/p' "$jarvis_key_session")"
expect "Session names its tap and silence bounds" ok \
  python3 -c 'import sys; print("ok" if all(v.isdigit() for v in sys.argv[1:]) else sys.argv[1:])' "$jarvis_key_tap_ms" "$jarvis_key_silence_ms"
expect "the key row starts with Jarvis disabled" absent ipc smoke jarvisProcess
"$node_bin" "$source_repo/scripts/fixtures/jarvis/scripted.js" "$jarvis_key_backend" "$jarvis_key_gates" --mapped-indicator
python3 - "$jarvis_key_backend" "$jarvis_key_gates/received-intents.jsonl" <<'PY'
from pathlib import Path
import json,sys
p=Path(sys.argv[1])
s=p.read_text()
needle='if (message.type === "intent") {\n                    intentIdentity(message);'
assert s.count(needle)==1
record='\n                    fs.appendFileSync('+json.dumps(sys.argv[2])+', JSON.stringify(message.intent) + "\\n");'
p.write_text(s.replace(needle,needle+record))
PY
cp -- "$jarvis_key_backend" "$sandbox/jarvis-key-scripted-before"
jarvis_gate="$sandbox/jarvis-key-startup-gate"
jarvis_seen="$sandbox/jarvis-key-startup-seen"
"$node_bin" "$source_repo/scripts/fixtures/jarvis/prepare.js" --gate-daemon "$jarvis_key_backend" "$jarvis_gate" "$jarvis_seen"
jarvis_rescan

jarvis_key_state() { # FIELD
  ipc smoke jarvisProcess | py_reply '
import json,sys
d=json.load(sys.stdin)["status"].get("detail")
if d is None:
    print("pending")
elif sys.argv[1] == "phase":
    print(d["phase"])
elif sys.argv[1] == "stale":
    print(d["state"]["stale"])
elif sys.argv[1] == "mode":
    print(d["state"]["settings"]["mode"])
else:
    print(d["state"][sys.argv[1]]["kind"])
' "$1"
}
jarvis_key_effects() { # KIND
  python3 - "$jarvis_key_gates/effects.jsonl" "$1" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
print(sum(json.loads(line)["kind"] == sys.argv[2] for line in p.read_text().splitlines()) if p.exists() else 0)
PY
}
jarvis_key_intents="$jarvis_key_gates/received-intents.jsonl"
jarvis_key_received() { # count|START_INDEX
  python3 - "$jarvis_key_intents" "$1" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
rows=[json.loads(line) for line in p.read_text().splitlines()] if p.exists() else []
print(len(rows) if sys.argv[2]=='count' else json.dumps(rows[int(sys.argv[2]):]))
PY
}
jarvis_key_received_control() { # FIXTURE_FILE
  (failures=0 behaviour_failures=0
   jarvis_key_intents="$1"
   expect "the exact muted key inputs and unmute must arrive in order" '["talk-down", "talk-up", "stop", "mute"]' jarvis_key_received 0 >"$sandbox/jarvis-key-received-control.log"
   echo "$failures")
}
jarvis_key_gate() { : >"$jarvis_key_gates/$1"; }
jarvis_key_mode() { # MODE
  user_config_write python3 - "$jarvis_key_config" "$1" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]); value=json.loads(p.read_text())
row=next((r for r in value.setdefault("plugins",[]) if r["id"]=="vgs.jarvis"),None)
if row is None:
    row={"id":"vgs.jarvis"}; value["plugins"].append(row)
row["mode"]=sys.argv[2]
print(json.dumps(value))
PY
  expect "deliver the Jarvis talk mode" ok ipc shell reloadConfig
  expect_poll "the running daemon receives its mode" "$1" jarvis_key_state mode
}
# Sleep until MS milliseconds have passed since AT, a now_ms reading.
jarvis_key_wait_past() { # AT MS
  local left=$(( $1 + $2 - $(now_ms) ))
  (( left <= 0 )) || sleep "$((left / 1000)).$(printf '%03d' $((left % 1000)))"
}
jarvis_key_talk_down() { hold_send "down 133" "down 108"; jarvis_key_down_at="$(now_ms)"; }
# A hold: the release comes 300 ms past Session's tap bound, so it ends the
# request at the release.
jarvis_key_talk_up() {
  jarvis_key_wait_past "$jarvis_key_down_at" $((jarvis_key_tap_ms + 300))
  hold_send "up 108" "up 133"
}
# A tap: both edges at once, far inside the tap bound.
jarvis_key_tap() { hold_send "down 133" "down 108" "up 108" "up 133"; jarvis_key_tapped_at="$(now_ms)"; }
# Whether the request is sent, phase thinking, before DEADLINE, a now_ms
# reading: a tapped request reaches thinking by itself only after Session's
# silence bound, so a send before it comes from the key.
jarvis_key_sent_before() { # DEADLINE
  local phase
  while :; do
    phase="$(jarvis_key_state phase)" || return
    if [[ $phase == thinking ]]; then echo sent; return; fi
    if (( $(now_ms) >= $1 )); then echo "phase=$phase at the bound"; return; fi
    sleep 0.1
  done
}
# A tap, then the wait past the tap bound and the key barrier, which counts
# its marker in this shell, never in a control's subshell.
jarvis_key_tap_wait() {
  jarvis_key_tap
  jarvis_key_wait_past "$jarvis_key_tapped_at" $((jarvis_key_tap_ms + 300))
  hold_barrier
}
jarvis_key_tap_keeps() { expect "a tap keeps listening past the tap bound" tapped jarvis_key_state input; }
jarvis_key_tap_listens() { jarvis_key_tap_wait; jarvis_key_tap_keeps; }
jarvis_key_hold_sends() {
  local released
  jarvis_key_talk_down
  expect_poll "the held talk key starts listening" listening jarvis_key_state phase
  jarvis_key_talk_up
  released="$(now_ms)"
  expect "a hold past the tap bound sends at its release" sent jarvis_key_sent_before $((released + jarvis_key_silence_ms))
}
jarvis_key_second_tap_sends() {
  local first="$jarvis_key_tapped_at"
  jarvis_key_tap
  expect "the second tap sends the tapped request" sent jarvis_key_sent_before $((first + jarvis_key_silence_ms))
}
# One Session copy per tap rule: NEEDLE becomes REPLACEMENT, SETUP runs
# ("-" for none), and JUDGED's one assertion must then fail once.
jarvis_key_tap_control() { # LABEL NEEDLE REPLACEMENT SETUP JUDGED
  python3 - "$jarvis_key_session" "$2" "$3" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); assert not p.is_symlink()
s=p.read_text(); assert s.count(sys.argv[2])==1
changed=s.replace(sys.argv[2], sys.argv[3])
assert changed!=s
p.write_text(changed)
PY
  jarvis_rescan
  jarvis_enable
  jarvis_key_mode hold
  [[ $4 == - ]] || "$4"
  expect "$1 breaks its tap assertion" 1 jarvis_key_tap_judged "$5"
  jarvis_disable
  cp -- "$sandbox/jarvis-key-session-before" "$jarvis_key_session"
}
jarvis_key_tap_judged() { # FUNCTION
  (failures=0 behaviour_failures=0
   "$1" >"$sandbox/jarvis-key-tap-control-$1.log"
   echo "$failures")
}
jarvis_key_mute() { hold_send "down 133" "down 50" "down 108" "up 108" "up 50" "up 133"; }
jarvis_key_stop() { hold_send "down 133" "down 64" "down 60" "up 60" "up 64" "up 133"; }
jarvis_key_commit() { expect_poll "release commits the scripted utterance" thinking jarvis_key_state phase; }
jarvis_key_commit_control() {
  (failures=0 behaviour_failures=0
   jarvis_key_commit >"$sandbox/jarvis-key-release-control.log"
   echo "$failures")
}
jarvis_key_muted() {
  expect_poll "startup Mute is delivered and keeps capture closed" on jarvis_key_state mute
  expect "startup Mute does not acquire capture" closed jarvis_key_state capture
}
jarvis_key_mute_control() {
  (failures=0 behaviour_failures=0
   jarvis_key_muted >"$sandbox/jarvis-key-startup-control.log"
   echo "$failures")
}
jarvis_key_pending() { ipc smoke readInstance service vgs.jarvis lifetime; }
# One pending privacy request while no daemon is ready. Service.qml's
# helloDeadline (5000 ms) ends a daemon that holds its hello answer and its
# retry keeps the request, so a held start reads starting or retry.
jarvis_key_one_pending() { # [READING]
  local reading="${1-}"
  [[ -n $reading ]] || reading="$(jarvis_key_pending)" || return
  python3 -c '
import json,sys
d=json.loads(sys.argv[1])
print("one" if d.get("kind") in ("starting","retry") and d.get("pendingMute")=="waiting" and len(d)==2 else sys.argv[1])
' "$reading"
}
# Always mode's resting orb: the one presented bubble waits for the word with
# no words, and its orb ticks no frame and draws no level.
jarvis_key_resting() {
  local bubbles orbs
  bubbles="$(ipc smoke layerItems vgs.jarvis Bubble presented,phase,words)" &&
    orbs="$(ipc smoke layerItems vgs.jarvis VoiceOrb active,level,secondaryLevel)" || return 1
  python3 -c '
import json,sys
bubbles,orbs=map(json.loads,sys.argv[1:3])
shown=[(screen,v) for screen,_,v in bubbles if v["presented"]]
if len(shown)!=1: print("presented=%d" % len(shown)); sys.exit()
screen,bubble=shown[0]
if bubble["phase"]!="armed" or bubble["words"]!="": print("phase=%s words=%d" % (bubble["phase"],len(bubble["words"]))); sys.exit()
orb=[v for s,_,v in orbs if s==screen]
if len(orb)!=1: print("orbs=%d" % len(orb)); sys.exit()
o=orb[0]
print("resting" if o["active"] is False and o["level"]==0 and o["secondaryLevel"]==0
      else "active=%s level=%s secondary=%s" % (o["active"],o["level"],o["secondaryLevel"]))
' "$bubbles" "$orbs"
}
jarvis_key_resting_assertion() { expect_poll "Always mode presents the still resting orb" resting jarvis_key_resting; }
jarvis_key_resting_control() {
  (failures=0 behaviour_failures=0
   jarvis_key_resting_assertion >"$sandbox/jarvis-key-resting-control.log"
   echo "$failures")
}

jarvis_shortcuts() {
  hypr globalshortcuts | python3 -c 'import json,re,sys; print(json.dumps(sorted(set(re.findall(r"vgs\.jarvis:[A-Za-z0-9_.-]+", sys.stdin.read())))))'
}
# Compare the exact shipped binding and menu shortcut IDs at their owner.
jarvis_shipped_shortcuts() {
  python3 - "$repo/shell/plugins/vgs.jarvis/manifest.json" <<'PYSHORTCUTS'
import json,sys
manifest=json.load(open(sys.argv[1]))
binds=manifest["hyprland"]["binds"]
names={bind["shortcut"] for bind in binds}
names.update(bind["shortcut"]+".release" for bind in binds if bind.get("hold") is True)
names.update(row["shortcut"] for row in manifest["menu"].values())
print(json.dumps(sorted(manifest["id"]+":"+name for name in names)))
PYSHORTCUTS
}
jarvis_shortcut_assertion() {
  expect_poll "Jarvis registers exactly its shipped binding and menu shortcuts" "$(jarvis_shipped_shortcuts)" jarvis_shortcuts
}
jarvis_shortcut_control() {
  (failures=0 behaviour_failures=0
   jarvis_shortcut_assertion >"$sandbox/jarvis-home-shortcut-control.log"
   echo "$failures")
}
jarvis_key_kind() { ipc smoke readInstance service vgs.jarvis lifetime | py_reply 'import json,sys; print(json.load(sys.stdin)["kind"])'; }
# A daemon start that never comes: a launcher this row starts, with no
# daemon below it, held past the bound or ended after 0.5 s. The daemon
# read waits its whole bound, or ends when the launcher does, then names
# the cause and returns, so the caller decides; it ends no run.
jarvis_daemon_wait_control() { # held|ended
  local standin started got status=0 elapsed waited=early
  if [[ $1 == held ]]; then sleep 30 </dev/null >/dev/null 2>&1 & else sleep 0.5 </dev/null >/dev/null 2>&1 & fi
  standin=$!
  started="$(now_ms)"
  got="$(jarvis_descendants "$standin" 2>&1)" || status=$?
  elapsed=$(( $(now_ms) - started ))
  # Only the held stand-in still runs: the ended one exited before the read
  # returned, and its number is no longer this row's to signal.
  [[ $1 != held ]] || kill "$standin"
  wait "$standin" || true
  # The bound plus one poll and a Python start.
  if (( elapsed > jarvis_daemon_bound_ms + 2000 )); then waited=unbounded; elif (( elapsed >= jarvis_daemon_bound_ms )); then waited=bounded; fi
  printf 'status=%s waited=%s cause=%s\n' "$status" "$waited" "${got% launcher=*}"
}
# The Jarvis cards that say Mute was not saved for TITLE, the words of its cause.
jarvis_key_refusals() { # TITLE
  plugin_card_count Jarvis "Jarvis mute not saved" "$1"
}
jarvis_key_refusal_assertion() { expect_poll "unavailable Mute reports its actual cause" "$1" jarvis_key_refusals "$2"; }
jarvis_key_refusal_control() {
  (failures=0 behaviour_failures=0
   jarvis_key_refusal_assertion "$1" "$2" >"$sandbox/jarvis-key-refusal-control.log"
   echo "$failures")
}
jarvis_key_stopped() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
d=json.load(sys.stdin)["status"].get("detail")
s=d["state"] if d is not None else None
ok=s is not None and d["phase"]=="idle" and all(s[k]["kind"]==v for k,v in
    {"conversation":"ended","capture":"closed","playback":"idle","brain":"closed","turn":"none"}.items())
print("stopped" if ok else "pending")
'
}
jarvis_key_stop_assertion() { expect_poll "active physical Stop ends the turn and idles playback" stopped jarvis_key_stopped; }
jarvis_key_stop_control() {
  (failures=0 behaviour_failures=0
   jarvis_key_stop_assertion >"$sandbox/jarvis-key-stop-$1-control.log"
   echo "$failures")
}
jarvis_key_turn() { # PHASE
  jarvis_key_talk_down
  expect_poll "the physical Stop case starts capture" listening jarvis_key_state phase
  jarvis_key_talk_up
  jarvis_key_commit
  if [[ $1 == speaking ]]; then
    local starts
    starts="$(jarvis_key_effects playback-start)"
    jarvis_key_gate brain
    expect_poll "the physical Stop case starts speaking" speaking jarvis_key_state phase
    expect_poll "the scripted playback actually starts" "$((starts + 1))" jarvis_key_effects playback-start
  fi
}
jarvis_key_active_stop() { # PHASE
  local effect late stale before starts
  jarvis_key_turn "$1"
  if [[ $1 == thinking ]]; then effect=brain-cancel; late=late-brain; else effect=playback-flush; late=late-played; fi
  before="$(jarvis_key_effects "$effect")"
  starts="$(jarvis_key_effects playback-start)"
  jarvis_key_stop
  jarvis_key_stop_assertion
  expect "active physical Stop delivers $effect" "$((before + 1))" jarvis_key_effects "$effect"
  stale="$(jarvis_key_state stale)"
  jarvis_key_gate "$late"
  # The scripted fixture emits transcript, play and brain-done callbacks for
  # the late brain; the speech path waits only for its late playback callback.
  if [[ $1 == thinking ]]; then stale=$((stale + 3)); else stale=$((stale + 1)); fi
  expect_poll "the prior turn's callback is received and discarded" "$stale" jarvis_key_state stale
  jarvis_key_stop_assertion
  expect "a stale callback starts no new playback" "$starts" jarvis_key_effects playback-start
}
jarvis_key_startup() {
  rm -f -- "$jarvis_gate" "$jarvis_seen"
  expect "the gated key service enables" ok ipc shell setPluginEnabled vgs.jarvis true
  expect_poll "the startup daemon consumes hello before the physical key" seen jarvis_seen_hello
  jarvis_key_mute
  jarvis_key_mute
  jarvis_key_talk_down
  jarvis_key_talk_up
  jarvis_key_stop
  hold_barrier
  expect "unavailable repeated Mute keeps one pending privacy request" one jarvis_key_one_pending
}

# Remove only the new home registration. The manifest still offers it.
python3 - "$jarvis_key_service" <<'PYSHORTCUTS'
from pathlib import Path
import sys
p=Path(sys.argv[1]); source=p.read_text()
needle='            shell.shortcut.register("home", "Switch Jarvis home", item => switchHome(item));'
assert source.count(needle)==1
p.write_text(source.replace(needle, '            // The home registration control removes this effect.'))
PYSHORTCUTS
jarvis_rescan
# A seen file an earlier start left would answer before this daemon exists.
rm -f -- "$jarvis_seen"
expect "the missing-home shortcut control enables" ok ipc shell setPluginEnabled vgs.jarvis true
expect_poll "the shortcut control's daemon consumes hello" seen jarvis_seen_hello
expect "removing the home registration breaks the shipped shortcut assertion" 1 jarvis_shortcut_control
jarvis_disable
cp -- "$sandbox/jarvis-key-service-before" "$jarvis_key_service"
jarvis_rescan

# A disable issued during a daemon start: with no gate the daemon's hello
# answer is held, the service can report no launcher yet, and a launcher
# can exist before its daemon does.
rm -f -- "$jarvis_gate" "$jarvis_seen"
expect "the held start enables" ok ipc shell setPluginEnabled vgs.jarvis true
expect_poll "the disable comes while the service is starting" starting jarvis_key_kind
jarvis_disable
expect "a launcher whose daemon never starts fails the daemon read with its named cause" \
  "status=1 waited=bounded cause=jarvis-row: daemon-wait=timeout daemon-count=0 bound_ms=$jarvis_daemon_bound_ms" jarvis_daemon_wait_control held
expect "a launcher that ends before its daemon starts ends the daemon read early with its named cause" \
  "status=1 waited=early cause=jarvis-row: daemon-wait=launcher-ended daemon-count=0" jarvis_daemon_wait_control ended
# A disable with no start: the launcher wait passes its bound. The row
# fails with the named cause and goes on; under the row's set -e a return
# 1 would end the subshell before it writes its result.
set +e
(set -e; failures=0 behaviour_failures=0
 jarvis_disable >"$sandbox/jarvis-disable-control.log" 2>&1
 echo "$failures" >"$sandbox/jarvis-disable-control.failures")
jarvis_disable_control_status=$?
set -e
expect "a disable with no start fails the row with its named cause and ends no run" \
  "status=0 row=failed cause=launcher-wait=timeout" python3 -c '
import os, re, sys
log = open(sys.argv[1]).read()
failures = open(sys.argv[2]).read().strip() if os.path.exists(sys.argv[2]) else "unwritten"
row = "failed" if failures.isdigit() and int(failures) > 0 else failures
cause = re.search(r"FAIL  the Jarvis launcher is unreadable before disable: jarvis-row: (launcher-wait=[a-z]+)", log)
print("status=%s row=%s cause=%s" % (sys.argv[3], row, cause.group(1) if cause else "none"))
' "$sandbox/jarvis-disable-control.log" "$sandbox/jarvis-disable-control.failures" "$jarvis_disable_control_status"

# Every startup Mute sends its pending notice, so vgs.notifications draws
# them from the first one on.
notes_on "jarvis mute notices"
printf '%s\n' \
  'hl.config({ input = { resolve_binds_by_sym = false } })' \
  'hl.bind("code:67", hl.dsp.global("smoke:hold-marker"), { description = "smoke:hold-marker", ignore_mods = true })' >>"$jarvis_key_lua"
expect "Jarvis keys use the physical evdev map" ok hypr reload config-only
expect "the observer provides the key ordering marker" ok ipc smoke holdMarkerStart
hold_markers="$(ipc smoke holdMarkerCount)"
hold_delayed_keyboard=""
hold_start_keyboard jarvis "$sandbox/keyboard" us ""
jarvis_key_startup
for planted in '{"kind":"retry","pendingMute":["waiting","waiting"]}' '{"kind":"starting","pendingMute":"none"}'; do
  expect "a planted pending Mute reading other than one request fails the judge" "$planted" jarvis_key_one_pending "$planted"
done
jarvis_shortcut_assertion
expect_poll "the service reads the effective default key map" \
  '{"talk":"SUPER+code:108","mute":"SUPER+SHIFT+code:108","stop":"SUPER+ALT+PERIOD","confirm":"SUPER+ALT+Y","console":"SUPER+ALT+C"}' \
  ipc smoke readInstance service vgs.jarvis effectiveKeys
: >"$jarvis_gate"
jarvis_key_muted
expect "ready acknowledges the pending Mute" '{"kind":"ready","pendingMute":"none"}' jarvis_key_pending
jarvis_disable
jarvis_key_startup
: >"$jarvis_gate"
jarvis_key_muted
expect "pending startup Mute never toggles restored mute off" 0 jarvis_key_effects capture-open
jarvis_key_mute
expect_poll "a ready explicit Mute can unmute without capture" off jarvis_key_state mute

jarvis_disable
# Keep the real retry timer, with a fixture delay long enough for physical
# input and its ordering barrier to complete before the next start.
python3 - "$jarvis_key_service" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); assert not p.is_symlink()
s=p.read_text(); needle='retry.interval = 250 * Math.pow(2, retries);'
assert s.count(needle)==1
changed=s.replace(needle, 'retry.interval = 4500;')
assert changed!=s
p.write_text(changed)
PY
jarvis_rescan
jarvis_key_startup
jarvis_key_launcher="$(ipc smoke jarvisProcess | jarvis_launcher_pid)"
jarvis_key_pid="$(jarvis_descendants "$jarvis_key_launcher")"
rm -- "$jarvis_seen"
kill -KILL "$jarvis_key_pid"
expect_poll "pending startup Mute remains owned during retry" '{"kind":"retry","pendingMute":"waiting"}' jarvis_key_pending
jarvis_key_mute
jarvis_key_mute
hold_barrier
expect "repeated physical Mute during retry stays one request" one jarvis_key_one_pending
# The fixture's retry delay is not daemon startup time. Start the hello
# read only after the service has started its next child.
expect_poll "the retry starts its next daemon with Mute pending" '{"kind":"starting","pendingMute":"waiting"}' jarvis_key_pending
expect_poll "the restarted daemon consumes hello" seen jarvis_seen_hello
: >"$jarvis_gate"
jarvis_key_muted
expect "retry uses the existing restart allowance" ready jarvis_wait_ready 1
jarvis_disable
cp -- "$sandbox/jarvis-key-service-before" "$jarvis_key_service"
jarvis_rescan
jarvis_key_startup
expect "the test-only lock holder enables" ok ipc shell setPluginEnabled acme.probe true
expect "the fixture locks before pending Mute delivery" ok probe lock
expect_poll "the nested compositor confirms the fixture lock" true read_service lockSecure
: >"$jarvis_gate"
jarvis_key_muted
expect "the pending request uses the current locked snapshot" '{"kind":"ready","pendingMute":"none"}' jarvis_key_pending
expect "the fixture unlocks without authentication" ok probe unlock
expect_poll "unlock leaves privacy Mute on" on jarvis_key_state mute
jarvis_key_talk_down
jarvis_key_talk_up
hold_barrier
expect "unlock plus Talk cannot acquire muted capture" closed jarvis_key_state capture
jarvis_key_mute
expect_poll "explicit ready unmute clears only privacy state" off jarvis_key_state mute

jarvis_disable
notes_clear "the earlier pending Mute notices"
jarvis_key_startup
expect_poll "pending Mute tells the user that disable cancels the request" 1 \
  plugin_card_count Jarvis "Jarvis mute pending" "disabling Jarvis cancels this request"
expect "disable ends the pending service" ok ipc shell setPluginEnabled vgs.jarvis false
expect_poll "disable drops the pending owner" absent ipc smoke jarvisProcess
expect "a cancelled request never changes the persisted privacy state" False \
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["muted"])' "$home/.local/state/vgshell/jarvis/mute.json"
jarvis_key_startup
: >"$jarvis_gate"
jarvis_key_muted
jarvis_key_mute
expect_poll "ready unmute is explicit after the new request" off jarvis_key_state mute

# Keep the key registration and pending request. Remove only its delivery.
jarvis_disable
python3 - "$jarvis_key_service" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); assert not p.is_symlink()
s=p.read_text(); needle='sendIntent("mute");'
assert s.count(needle)==1
changed=s.replace(needle, 'if (false) ' + needle)
assert changed!=s
p.write_text(changed)
PY
jarvis_rescan
jarvis_key_startup
: >"$jarvis_gate"
expect "dropping pending delivery breaks the same startup Mute assertion" 1 jarvis_key_mute_control
jarvis_disable
cp -- "$sandbox/jarvis-key-service-before" "$jarvis_key_service"
cp -- "$sandbox/jarvis-key-backend-before" "$jarvis_key_backend"
"$node_bin" "$source_repo/scripts/fixtures/jarvis/prepare.js" --floor-daemon "$jarvis_key_backend"
jarvis_rescan
expect "the permanent-problem key service enables" ok ipc shell setPluginEnabled vgs.jarvis true
expect_poll "the real service reports its permanent cause" permanent jarvis_permanent
jarvis_key_refused="$(jarvis_key_refusals 'Jarvis needs Node 22 or later')"
jarvis_key_mute
hold_barrier
jarvis_key_refusal_assertion "$((jarvis_key_refused + 1))" 'Jarvis needs Node 22 or later'
expect "the permanent-problem service disables" ok ipc shell setPluginEnabled vgs.jarvis false
python3 - "$jarvis_key_service" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); assert not p.is_symlink()
s=p.read_text(); needle='notice(Gate.muteRefusedNotice(cause));\n                return;'
assert s.count(needle)==1
changed=s.replace(needle, 'return;')
assert changed!=s
p.write_text(changed)
PY
jarvis_rescan
expect "the refusal control enables without changing the key trigger" ok ipc shell setPluginEnabled vgs.jarvis true
expect_poll "the refusal control reaches the same permanent cause" permanent jarvis_permanent
jarvis_key_refused="$(jarvis_key_refusals 'Jarvis needs Node 22 or later')"
jarvis_key_mute
hold_barrier
expect "dropping refusal breaks its same cause assertion" 1 jarvis_key_refusal_control "$((jarvis_key_refused + 1))" 'Jarvis needs Node 22 or later'
expect "the refusal control disables" ok ipc shell setPluginEnabled vgs.jarvis false
notes_off "jarvis mute notices"
cp -- "$sandbox/jarvis-key-service-before" "$jarvis_key_service"
cp -- "$sandbox/jarvis-key-scripted-before" "$jarvis_key_backend"
jarvis_rescan
jarvis_enable
jarvis_key_mode hold
jarvis_key_active_stop thinking
jarvis_key_active_stop speaking
smoke_row jarvis-bubble
jarvis_key_initial_opens="$(jarvis_key_effects capture-open)"
jarvis_key_talk_down
expect_poll "the physical talk key starts listening" listening jarvis_key_state phase
expect "one key press opens one scripted capture" "$((jarvis_key_initial_opens + 1))" jarvis_key_effects capture-open
jarvis_key_received_before="$(jarvis_key_received count)"
hold_send "down 108" "down 108"
hold_barrier
expect "physical repeat opens no second capture" "$((jarvis_key_initial_opens + 1))" jarvis_key_effects capture-open
jarvis_key_talk_up
jarvis_key_released="$(now_ms)"
expect "a hold past the tap bound sends at its release" sent jarvis_key_sent_before $((jarvis_key_released + jarvis_key_silence_ms))
expect "physical repeat sends only the release intent" "$((jarvis_key_received_before + 1))" jarvis_key_received count
jarvis_key_gate brain
expect_poll "the scripted brain starts speaking" speaking jarvis_key_state phase
jarvis_key_gate played
expect_poll "scripted playback returns to idle" idle jarvis_key_state phase

# Talk tap through the real bind: a press released inside Session's tap
# bound keeps listening past it on one capture, and the next tap sends the
# request before the tap's silence bound could.
jarvis_key_initial_opens="$(jarvis_key_effects capture-open)"
jarvis_key_tap_listens
expect "the tapped request still listens" listening jarvis_key_state phase
expect "a tap opens one capture" "$((jarvis_key_initial_opens + 1))" jarvis_key_effects capture-open
jarvis_key_second_tap_sends
expect "the second tap opens no capture" "$((jarvis_key_initial_opens + 1))" jarvis_key_effects capture-open
jarvis_key_gate brain
expect_poll "the tapped request's answer speaks" speaking jarvis_key_state phase
jarvis_key_gate played
expect_poll "the tapped request's playback returns to idle" idle jarvis_key_state phase

jarvis_key_mode toggle
jarvis_key_talk_down
expect_poll "toggle press opens a conversation" listening jarvis_key_state phase
jarvis_key_talk_up
hold_barrier
expect "toggle release leaves capture open" conversation jarvis_key_state input
jarvis_key_gate final
expect_poll "the scripted turn detector commits toggle speech" thinking jarvis_key_state phase
jarvis_key_gate brain
expect_poll "toggle's scripted answer speaks" speaking jarvis_key_state phase
jarvis_key_gate played
expect_poll "toggle resumes listening after its scripted answer" listening jarvis_key_state phase
sleep 0.25 # The next press must be outside Session's toggle-collapse interval.
jarvis_key_talk_down
jarvis_key_talk_up
expect_poll "the next toggle press closes its conversation" ended jarvis_key_state conversation
expect_poll "closing toggle releases capture" closed jarvis_key_state capture
jarvis_key_mode always
expect_poll "idle Always mode waits for the word" armed jarvis_key_state phase
jarvis_key_resting_assertion
jarvis_key_mode toggle
sleep 0.25 # The next conversation uses a separate permitted toggle edge.
jarvis_key_talk_down
jarvis_key_talk_up
expect_poll "a fresh toggle conversation listens" listening jarvis_key_state phase
jarvis_key_gate hold-close
jarvis_key_mute
expect_poll "mute waits for scripted capture teardown" muting jarvis_key_state mute
jarvis_key_opens="$(jarvis_key_effects capture-open)"
jarvis_key_talk_down
jarvis_key_talk_up
jarvis_key_stop
hold_barrier
jarvis_key_gate close
expect_poll "mute completes only after capture closes" on jarvis_key_state mute
expect "muting keys cannot acquire capture" "$jarvis_key_opens" jarvis_key_effects capture-open
rm -- "$jarvis_key_gates/hold-close"
jarvis_disable
jarvis_enable
expect_poll "mute survives a service and daemon restart" on jarvis_key_state mute
# State publications also include settings, presentation and completions.
# The fixture observes validated intent delivery independently of them.
jarvis_key_received_before="$(jarvis_key_received count)"
jarvis_key_talk_down
jarvis_key_talk_up
jarvis_key_stop
hold_barrier
expect "all implemented non-mute keys leave privacy mute on" on jarvis_key_state mute
expect "muted keys after restart acquire no capture" "$jarvis_key_opens" jarvis_key_effects capture-open
jarvis_key_mute
expect_poll "the mute key explicitly unmutes" off jarvis_key_state mute
expect "the daemon receives muted keys then the acknowledged unmute" '["talk-down", "talk-up", "stop", "mute"]' jarvis_key_received "$jarvis_key_received_before"
printf '"talk-down"\n"stop"\n"mute"\n' >"$sandbox/jarvis-key-missing-intent.jsonl"
expect "a missing muted key input fails the delivery assertion" 1 jarvis_key_received_control "$sandbox/jarvis-key-missing-intent.jsonl"
printf '"talk-up"\n"talk-down"\n"stop"\n"mute"\n' >"$sandbox/jarvis-key-reordered-intents.jsonl"
expect "reordered muted key inputs fail the delivery assertion" 1 jarvis_key_received_control "$sandbox/jarvis-key-reordered-intents.jsonl"
expect "unmute alone keeps capture closed" closed jarvis_key_state capture

# Preserve both registration and wire dispatch. Misroute only Stop.
jarvis_disable
python3 - "$jarvis_key_service" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); assert not p.is_symlink()
s=p.read_text(); needle='function sendIntent(name) {'
assert s.count(needle)==1
changed=s.replace(needle, needle + '\n        if (name === "stop") name = "talk-up";')
assert changed!=s
p.write_text(changed)
PY
jarvis_rescan
for jarvis_key_phase in thinking speaking; do
  jarvis_enable
  jarvis_key_mode hold
  jarvis_key_turn "$jarvis_key_phase"
  jarvis_key_stop
  hold_barrier
  expect "Stop-to-talk-up fails the same active $jarvis_key_phase assertion" 1 jarvis_key_stop_control "$jarvis_key_phase"
  jarvis_disable
done
cp -- "$sandbox/jarvis-key-service-before" "$jarvis_key_service"

# Preserve the registration and its pressed behavior. Drop only delivery of
# the release callback; the same commit assertion must fail once.
python3 - "$jarvis_key_service" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text(); needle='() => intent("talk-up")'
assert s.count(needle)==1
changed=s.replace(needle, "() => {}")
assert changed!=s
p.write_text(changed)
PY
jarvis_rescan
jarvis_enable
jarvis_key_mode hold
jarvis_key_talk_down
expect_poll "the release control retains actual key-down delivery" listening jarvis_key_state phase
jarvis_key_talk_up
hold_barrier
expect "dropping release delivery breaks the real phase assertion" 1 jarvis_key_commit_control
jarvis_disable
# Each tap rule's Session copy fails the same assertion once.
cp -- "$sandbox/jarvis-key-service-before" "$jarvis_key_service"
jarvis_key_tap_control "a Session whose every release ends the request" "var TAP_MS = $jarvis_key_tap_ms;" "var TAP_MS = 0;" jarvis_key_tap_wait jarvis_key_tap_keeps
jarvis_key_tap_control "a Session whose every release is a tap" "var TAP_MS = $jarvis_key_tap_ms;" "var TAP_MS = 60000;" - jarvis_key_hold_sends
jarvis_key_tap_control "a Session whose press after a tap starts a new hold" \
  "        if (s.input.kind === \"tapped\") {
            s.input = { kind: \"released\" };
            closeCapture(s, effects);
            break;
        }
        recover(s, effects, e.at);" "        recover(s, effects, e.at);" jarvis_key_tap_listens jarvis_key_second_tap_sends
jarvis_rescan
# Keep the bubble and Always mode. Let only the resting orb tick; the same
# resting assertion must fail once.
cp -- "$sandbox/jarvis-key-service-before" "$jarvis_key_service"
jarvis_key_bubble="$repo/shell/plugins/vgs.jarvis/Bubble.qml"
cp -- "$jarvis_key_bubble" "$sandbox/jarvis-key-bubble-before"
python3 - "$jarvis_key_bubble" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); assert not p.is_symlink()
s=p.read_text(); needle='active: root.shown && !resting'
assert s.count(needle)==1
changed=s.replace(needle, 'active: root.shown')
assert changed!=s
p.write_text(changed)
PY
jarvis_rescan
jarvis_enable
jarvis_key_mode always
expect_poll "the resting control waits for the word" armed jarvis_key_state phase
expect "a ticking resting orb breaks the same resting assertion" 1 jarvis_key_resting_control
jarvis_disable
cp -- "$sandbox/jarvis-key-bubble-before" "$jarvis_key_bubble"
expect_poll "disable unregisters every Jarvis key" 0 hold_native vgs.jarvis:
hold_barrier
hold_stop_keyboard
expect "the observer releases its ordering marker" ok ipc smoke holdMarkerStop
cp -- "$sandbox/jarvis-key-service-before" "$jarvis_key_service"
cp -- "$sandbox/jarvis-key-backend-before" "$jarvis_key_backend"
cp -- "$sandbox/jarvis-key-engine-before" "$jarvis_key_engine"
cp -- "$sandbox/jarvis-key-session-before" "$jarvis_key_session"
rm -- "$repo/shell/plugins/vgs.jarvis/backend/scripted-fixture.js"
rm -- "$home/.local/state/vgshell/jarvis/mute.json"
jarvis_rescan
user_config_restore "$sandbox/jarvis-key-config-before.json"
cp -- "$sandbox/jarvis-key-lua-before" "$jarvis_key_lua"
expect "restore the Jarvis key configuration" ok ipc shell reloadConfig
expect "restore the nested keyboard configuration" ok hypr reload config-only
jarvis_enable
expect_poll "the restored stock daemon remains unconfigured" session jarvis_session unconfigured
expect "the restored nested keys have no configuration errors" '[]' hypr_reload_errors
expect "the scripted control leaves no Jarvis state file" False \
  python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).exists())' "$home/.local/state/vgshell/jarvis/mute.json"
jarvis_disable
jarvis_notice_close
