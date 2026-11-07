# Physical Jarvis keys against private scripted Session ports. No audio,
# account, provider or network runs. No latency ceiling is measured.
# State/effect reads poll once per nested IPC round trip. Fixture callback
# gates poll at 10 ms; hold barriers use the shell's native marker.
# inputs: scripts/smoke/user-config.sh shell/plugins/vgs.jarvis/* scripts/fixtures/jarvis/* shell/Core/ShortcutRegistry.qml shell/Core/SessionLock.qml scripts/smoke/keyboard/* scripts/smoke/fixtures/plugins/acme.probe/* shell/plugins/vgs.bar/* shell/Core/Layers.qml shell/Hosts/AppWindow.qml shell/Hosts/SummonHost.qml scripts/smoke/toplevel/* shell/Core/HyprlandLayer.js scripts/smoke/rows/jarvis-bubble.sh scripts/smoke/rows/jarvis.sh scripts/smoke/rows/hold-shortcuts.sh scripts/smoke/rows/capabilities.sh scripts/smoke/rows/plugins.sh scripts/smoke/rows/hyprland-consent.sh shell/Core/Notifier.qml shell/plugins/vgs.notifications/* scripts/smoke/rows/diagnostics.sh
set -euo pipefail
# Jarvis holds `dictation`, and the shell finds no voxtype: the core's
# probe does not start at each enable.
expected_errors+=("${dictation_absent_errors[@]}")
# The key row runs the Jarvis fixtures, and the nested jarvis-bubble row reads
# this row's log window too, so it declares the set jarvis.sh does.
expected_errors+=("${jarvis_provoked_errors[@]}")

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
# Only short silent holds close the conversation; the real Session owns the bound.
jarvis_key_tap_ms="$(sed -n 's/^var TAP_MS = \([0-9][0-9]*\);$/\1/p' "$jarvis_key_session")"
expect "Session names its tap bound" True python3 -c 'import sys; print(sys.argv[1].isdigit())' "$jarvis_key_tap_ms"
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
elif sys.argv[1] == "holdToTalk":
    print(str(d["state"]["settings"]["holdToTalk"]).lower())
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
jarvis_key_gate() { : >"$jarvis_key_gates/$1"; }
jarvis_key_hold() { # true|false
  user_config_write python3 - "$jarvis_key_config" "$1" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]); value=json.loads(p.read_text())
row=next((r for r in value.setdefault("plugins",[]) if r["id"]=="vgs.jarvis"),None)
if row is None:
    row={"id":"vgs.jarvis"}; value["plugins"].append(row)
row["holdToTalk"]=json.loads(sys.argv[2])
print(json.dumps(value))
PY
  expect "deliver the Jarvis hold setting" ok ipc shell reloadConfig
  expect_poll "the running daemon receives Hold to talk" "$1" jarvis_key_state holdToTalk
}
# Sleep until MS milliseconds have passed since AT, a now_ms reading.
jarvis_key_wait_past() { # AT MS
  local left=$(( $1 + $2 - $(now_ms) ))
  (( left <= 0 )) || sleep "$((left / 1000)).$(printf '%03d' $((left % 1000)))"
}
jarvis_key_talk_down() { hold_send "down 133" "down 44"; jarvis_key_down_at="$(now_ms)"; }
# A hold: the release comes 300 ms past Session's tap bound, so it ends the
# request at the release.
jarvis_key_talk_up() {
  jarvis_key_wait_past "$jarvis_key_down_at" $((jarvis_key_tap_ms + 300))
  hold_send "up 44" "up 133"
}
# A tap: both edges at once, far inside the tap bound.
jarvis_key_tap() { hold_send "down 133" "down 44" "up 44" "up 133"; jarvis_key_tapped_at="$(now_ms)"; }
jarvis_key_stop() { hold_send "down 133" "down 37" "down 53" "up 53" "up 37" "up 133"; }
jarvis_key_commit() { expect_poll "release commits the scripted utterance" thinking jarvis_key_state phase; }
jarvis_key_commit_control() {
  (failures=0 behaviour_failures=0
   jarvis_key_commit >"$sandbox/jarvis-key-release-control.log"
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
jarvis_key_stopped() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
d=json.load(sys.stdin)["status"].get("detail")
s=d["state"] if d is not None else None
ok=s is not None and d["phase"]=="idle" and all(s[k]["kind"]==v for k,v in
    {"conversation":"active","capture":"closed","playback":"idle","turn":"none"}.items())
print("stopped" if ok else "pending")
'
}
jarvis_key_stop_assertion() { expect_poll "active physical Stop cancels the turn and keeps the conversation" stopped jarvis_key_stopped; }
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
  read_count stale "jarvis-keys: stale callbacks before" jarvis_key_state stale
  jarvis_key_gate "$late"
  # The scripted fixture emits transcript, play and brain-done callbacks for
  # the late brain; the speech path waits only for its late playback callback.
  if [[ $1 == thinking ]]; then stale=$((stale + 3)); else stale=$((stale + 1)); fi
  expect_poll "the prior turn's callback is received and discarded" "$stale" jarvis_key_state stale
  jarvis_key_stop_assertion
  expect "a stale callback starts no new playback" "$starts" jarvis_key_effects playback-start
}
# The inner row can replace the Probe that owns this registration/counter.
jarvis_key_resume_marker() {
  local reply
  reply="$(ipc smoke holdMarkerStart)" || { fail "jarvis-keys: marker reacquisition failed"; return 1; }
  if [[ $reply != ok && $reply != held ]]; then
    fail "jarvis-keys: marker reacquisition reply=$reply"
    return 1
  fi
  expect_poll "the observer's native ordering marker is registered after the bubble" 1 hold_native smoke:hold-marker
  read_count hold_markers "jarvis-keys: ordering markers after the bubble" ipc smoke holdMarkerCount
}
jarvis_key_startup() {
  rm -f -- "$jarvis_gate" "$jarvis_seen"
  expect "the gated key service enables" ok ipc shell setPluginEnabled vgs.jarvis true
  expect_poll "the startup daemon consumes hello" seen jarvis_seen_hello
}
jarvis_key_unavailable_stop_assertion() {
  expect "unavailable physical Stop ends the startup lifetime" '{"kind":"stopped"}' ipc smoke readInstance service vgs.jarvis lifetime
}
jarvis_key_unavailable_stop_control() {
  (failures=0 behaviour_failures=0
   jarvis_key_unavailable_stop_assertion >"$sandbox/jarvis-key-unavailable-stop-control.log"
   echo "$failures")
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

printf '%s\n' \
  'hl.config({ input = { resolve_binds_by_sym = false } })' \
  'hl.bind("code:67", hl.dsp.global("smoke:hold-marker"), { description = "smoke:hold-marker", ignore_mods = true })' >>"$jarvis_key_lua"
expect "Jarvis keys use the physical evdev map" ok hypr reload config-only
expect "the observer provides the key ordering marker" ok ipc smoke holdMarkerStart
hold_markers="$(ipc smoke holdMarkerCount)"
hold_delayed_keyboard=""
hold_start_keyboard jarvis "$sandbox/keyboard" us ""

# Restore the previous unavailable Stop behavior in the disposable plugin.
# Only the lifetime assertion runs against this copy.
python3 - "$jarvis_key_service" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); assert not p.is_symlink()
s=p.read_text()
needle='if (name === "stop" && (lifetime.kind !== "ready" || cause !== "" || !child.running)) {'
assert s.count(needle)==1
changed=s.replace(needle, 'if (false && name === "stop" && (lifetime.kind !== "ready" || cause !== "" || !child.running)) {')
assert changed!=s
p.write_text(changed)
PY
jarvis_rescan
jarvis_key_startup
jarvis_key_stop
hold_barrier
expect "previous unavailable Stop behavior fails the startup lifetime assertion" 1 jarvis_key_unavailable_stop_control
jarvis_disable
cp -- "$sandbox/jarvis-key-service-before" "$jarvis_key_service"
jarvis_rescan

jarvis_key_startup
jarvis_key_stop_launcher="$(ipc smoke jarvisProcess | jarvis_launcher_pid)"
jarvis_key_stop_daemon="$(jarvis_descendants "$jarvis_key_stop_launcher")"
jarvis_key_stop
hold_barrier
jarvis_key_unavailable_stop_assertion
expect "unavailable Stop releases the real daemon" absent jarvis_no_pid "$jarvis_key_stop_daemon"
expect "unavailable Stop releases the namespace launcher" absent jarvis_no_pid "$jarvis_key_stop_launcher"
expect "the stopped startup service disables" ok ipc shell setPluginEnabled vgs.jarvis false
expect_poll "disable drops the stopped startup owner" absent ipc smoke jarvisProcess

jarvis_key_startup
jarvis_shortcut_assertion
expect_poll "the service reads the effective default key map" \
  '{"talk":"SUPER+code:44","voice-mute":"SUPER+CTRL+M","stop":"SUPER+CTRL+X","confirm":"SUPER+CTRL+Y","deny":null,"console":"SUPER+ALT+C"}' \
  ipc smoke readInstance service vgs.jarvis effectiveKeys
: >"$jarvis_gate"
expect_poll "ready acknowledges the startup" '{"kind":"ready"}' ipc smoke readInstance service vgs.jarvis lifetime
jarvis_key_hold true
jarvis_key_active_stop thinking
jarvis_key_active_stop speaking
# A restart can restore files and flags, not an in-memory conversation.
# Close the held conversation before the nested row captures its baseline.
jarvis_key_gate silent-capture
jarvis_key_tap
expect_poll "the bubble boundary has no retained active conversation" ended jarvis_key_state conversation
expect_poll "the bubble boundary has released capture" closed jarvis_key_state capture
expect_poll "the bubble boundary has no incoming orb layer" 0 layer_count vgs:layer
rm -f -- "$jarvis_key_gates/silent-capture"
# The bubble's requirement stand-ins span its row boundary: the scan closes
# Jarvis's enable-time notice before the nested row captures its baseline.
jarvis_setup_requirements
rescan "the bubble requirement stand-ins are ready before its boundary"
expect_poll "no requirement notice enters the bubble row" null notice_shown
smoke_row jarvis-bubble
jarvis_restore_requirements
jarvis_key_resume_marker
jarvis_key_initial_opens="$(jarvis_key_effects capture-open)"
jarvis_key_talk_down
expect_poll "the physical talk key starts listening" listening jarvis_key_state phase
expect "one key press opens one scripted capture" "$((jarvis_key_initial_opens + 1))" jarvis_key_effects capture-open
jarvis_key_received_before="$(jarvis_key_received count)"
hold_send "down 44" "down 44"
hold_barrier
expect "physical repeat opens no second capture" "$((jarvis_key_initial_opens + 1))" jarvis_key_effects capture-open
jarvis_key_talk_up
jarvis_key_commit
expect "physical repeat sends only the release intent" "$((jarvis_key_received_before + 1))" jarvis_key_received count
jarvis_key_gate brain
expect_poll "the scripted brain starts speaking" speaking jarvis_key_state phase
jarvis_key_gate played
expect_poll "scripted playback returns to idle" idle jarvis_key_state phase

# The checked hold leaves the conversation open after the reply. A silent
# short tap closes it using the engine's explicit final-empty outcome.
expect "the held reply keeps its conversation" active jarvis_key_state conversation
jarvis_key_gate silent-capture
jarvis_key_tap
expect_poll "a silent short tap closes the conversation" ended jarvis_key_state conversation
expect_poll "a silent tap releases capture" closed jarvis_key_state capture
expect "silence is no fault" none jarvis_key_state fault
rm -f -- "$jarvis_key_gates/silent-capture"

jarvis_key_hold false
jarvis_key_talk_down
expect_poll "default Talk opens a conversation" listening jarvis_key_state phase
jarvis_key_talk_up
hold_barrier
expect "default release keeps listening" conversation jarvis_key_state input
jarvis_key_gate final
expect_poll "the turn detector commits speech" thinking jarvis_key_state phase
jarvis_key_gate brain
expect_poll "the answer speaks" speaking jarvis_key_state phase
jarvis_key_gate played
expect_poll "default Talk listens after its answer" listening jarvis_key_state phase
sleep 0.25 # A distinct press comes after the native repeat-collapse bound.
jarvis_key_talk_down
jarvis_key_talk_up
expect_poll "the next press closes its conversation" ended jarvis_key_state conversation
expect_poll "closing releases capture" closed jarvis_key_state capture
expect "closing leaves no fault" none jarvis_key_state fault

sleep 0.25 # A distinct press comes after the native repeat-collapse bound.
jarvis_key_talk_down
jarvis_key_talk_up
expect_poll "a new default conversation listens" listening jarvis_key_state phase
jarvis_key_gate final
expect_poll "the next default turn commits" thinking jarvis_key_state phase
jarvis_key_gate brain
expect_poll "the next default answer speaks" speaking jarvis_key_state phase
jarvis_key_stop
expect_poll "default Stop resumes listening" listening jarvis_key_state phase
expect "default Stop keeps its conversation" active jarvis_key_state conversation
expect "default Stop flushes playback" idle jarvis_key_state playback
jarvis_key_gate final
expect_poll "speech after Stop commits in the same conversation" thinking jarvis_key_state phase
jarvis_key_gate brain
expect_poll "the answer after Stop speaks" speaking jarvis_key_state phase
jarvis_key_talk_down
jarvis_key_talk_up
expect_poll "default Talk also closes during a reply" ended jarvis_key_state conversation
expect_poll "closing during a reply releases capture" closed jarvis_key_state capture
expect_poll "closing during a reply flushes playback" idle jarvis_key_state playback
expect "closing during a reply is no fault" none jarvis_key_state fault

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
  jarvis_key_hold true
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
jarvis_key_hold true
jarvis_key_talk_down
expect_poll "the release control retains actual key-down delivery" listening jarvis_key_state phase
jarvis_key_talk_up
hold_barrier
expect "dropping release delivery breaks the real phase assertion" 1 jarvis_key_commit_control
jarvis_disable
jarvis_rescan
expect_poll "disable unregisters every Jarvis key" 0 hold_native vgs.jarvis:
hold_barrier
hold_stop_keyboard
expect "the observer releases its ordering marker" ok ipc smoke holdMarkerStop
cp -- "$sandbox/jarvis-key-service-before" "$jarvis_key_service"
cp -- "$sandbox/jarvis-key-backend-before" "$jarvis_key_backend"
cp -- "$sandbox/jarvis-key-engine-before" "$jarvis_key_engine"
cp -- "$sandbox/jarvis-key-session-before" "$jarvis_key_session"
rm -- "$repo/shell/plugins/vgs.jarvis/backend/scripted-fixture.js"
jarvis_rescan
user_config_restore "$sandbox/jarvis-key-config-before.json"
cp -- "$sandbox/jarvis-key-lua-before" "$jarvis_key_lua"
expect "restore the Jarvis key configuration" ok ipc shell reloadConfig
expect "restore the nested keyboard configuration" ok hypr reload config-only
jarvis_enable
expect_poll "the restored stock daemon remains unconfigured" session jarvis_session unconfigured
expect "the restored nested keys have no configuration errors" '[]' hypr_reload_errors
jarvis_disable
jarvis_notice_close
