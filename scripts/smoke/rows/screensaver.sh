# Screensaver plugin Phase B row. It uses a ttfx stand-in whose help carries
# one planted effect and whose frames are deterministic. Latency polls use
# expect_poll's 0.2 s cadence. Measured row runtime on host cachy on
# 2026-10-05 under the nested sandbox: under 20 s.
# inputs: shell/plugins/vgs.screensaver/* shell/Core/PluginLogic.js shell/Hosts/BackgroundHost.qml scripts/smoke/fixtures/screensaver-ttfx scripts/smoke/rows/capability-release.sh scripts/smoke/rows/lock.sh
set -euo pipefail
# lock is exclusive: acme.probe can hold it and block vgs.lock from building.
# Free it for this row, then restore acme.probe and vgs.lock to their starting
# states. setPluginEnabled persists across the mid-row shell restart.
ss_probe_enabled="$(plugin_enabled acme.probe)" || ss_probe_enabled=unreadable
ss_lock_enabled="$(plugin_enabled vgs.lock)" || ss_lock_enabled=unreadable
case "$ss_probe_enabled" in
  True) expect "disabling the capability fixture, which holds lock, is allowed" ok ipc shell setPluginEnabled acme.probe false ;;
  False|absent) ;;
  *) fail "the capability fixture's enabled state is unreadable: $ss_probe_enabled" ;;
esac
case "$ss_lock_enabled" in
  True|False|absent) ;;
  *) fail "the lock plugin's enabled state is unreadable: $ss_lock_enabled" ;;
esac
ss_config="$home/.config/vgshell/shell.json"
ss_log="$home/.local/state/vgshell/screensaver-ttfx.log"
cp -- "$repo/scripts/smoke/fixtures/screensaver-ttfx" "$shim/ttfx"
chmod 755 "$shim/ttfx"
state_text() { ipc smoke statusValues vgs.screensaver | py_reply 'import json,sys; v=json.load(sys.stdin).get("state",{}); print(v.get("text","missing"))'; }
lock_order() { ipc smoke statusValues vgs.screensaver | py_reply 'import json,sys; v=json.load(sys.stdin).get("lockOrder"); print("absent" if v is None else json.dumps([v.get("tone"), v.get("text")]))'; }
art_status() { ipc smoke statusValues vgs.screensaver | py_reply 'import json,sys; v=json.load(sys.stdin).get("art",{}); print(v.get("text","missing"))'; }
cover_count() { layer_count vgs:cover; }
output_count() { hypr -j monitors | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
standin_alive() { pgrep -f -- "$shim/ttfx" >/dev/null && echo yes || echo no; }
plant_art_record() {
  local dir="$rt_dir/vgshell/tui" run="smoke-stale-art"
  mkdir -p -- "$dir"
  printf '{"key":"vgs.screensaver/art","run":"%s","state":"ended","code":0,"startedAt":"2026-10-06T00:00:00Z","endedAt":"2026-10-06T00:00:01Z","window":{"appId":"org.vgshell.tui.vgs.screensaver.art","title":"Screensaver art"}}\n' "$run" >"$dir/vgs.screensaver@art@$run.ended.json"
}
tui_art_loaded() { ipc shell lent | py_reply 'import json,sys; slot=json.load(sys.stdin)["tui"]["runs"].get("vgs.screensaver/art"); print(slot is not None and slot.get("ended") is not None)'; }
set_screensaver() { # JSON
  python3 - "$ss_config" "$1" <<'PY'
import json, os, sys
path, patch = sys.argv[1], json.loads(sys.argv[2])
doc = json.load(open(path))
rows = doc.setdefault("plugins", [])
row = next((r for r in rows if r.get("id") == "vgs.screensaver"), None)
if row is None:
    row = {"id": "vgs.screensaver"}
    rows.append(row)
row.update(patch)
with open(path + ".next", "w") as out:
    json.dump(doc, out)
os.replace(path + ".next", path)
PY
}
set_screensaver '{"idleEnabled": false, "idleSeconds": 2, "effect": "planted", "frameRate": 30}'
expect "reload config for screensaver settings" ok ipc shell reloadConfig
expect "disabling screensaver before stale art record is allowed" ok ipc shell setPluginEnabled vgs.screensaver false
plant_art_record
expect_poll "the planted art run is loaded" True tui_art_loaded
expect "enabling screensaver for its row is allowed" ok ipc shell setPluginEnabled vgs.screensaver true
sleep 1
expect "a stale art run does not start the cover" 0 layer_count vgs:cover
expect "disabling lock before screensaver checks is allowed" ok ipc shell setPluginEnabled vgs.lock false
rescan "rescan after adding ttfx stand-in answers ok"
expect_poll "screensaver service is built" True record_exists vgs.screensaver
choices() { ipc smoke statusValues vgs.screensaver | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin).get("effects", [])))'; }
expect_poll "effect choices come from ttfx help" '[{"label": "Random", "value": "random"}, {"label": "planted", "value": "planted"}, {"label": "beams", "value": "beams"}]' choices
expect_poll "default art status is truthful" "Default art" art_status
expect "enabling lock for lock order status is allowed" ok ipc shell setPluginEnabled vgs.lock true
set_screensaver '{"idleEnabled": true, "idleSeconds": 2}'
expect "lock order reload before ok status" ok ipc shell reloadConfig
expect_poll "lock order reads lock time as ok" '["ok", "Lock follows at 300 s"]' lock_order
set_screensaver '{"idleEnabled": true, "idleSeconds": 300}'
expect "lock order reload before warning status" ok ipc shell reloadConfig
expect_poll "lock order warns when screensaver is not before lock" '["warning", "Lock follows at 300 s"]' lock_order
expect "disabling lock clears lock order" ok ipc shell setPluginEnabled vgs.lock false
expect_poll "lock order is absent with lock disabled" absent lock_order
set_screensaver '{"idleSeconds": 2}'
expect "lock order reload after restore" ok ipc shell reloadConfig
set_screensaver '{"idleEnabled": false, "idleSeconds": 2}'
expect "idle disabled reload for idle control" ok ipc shell reloadConfig
sleep 4
expect "idle disabled keeps cover hidden" 0 layer_count vgs:cover
set_screensaver '{"idleEnabled": true, "idleSeconds": 2}'
expect "idle enabled reload for idle start" ok ipc shell reloadConfig
expect_poll "idle start maps one cover per output" "$(output_count)" cover_count
type_keys -k Escape || fail "typing Escape to close the idle screensaver failed"
expect_poll "idle cover is gone after keyboard input" 0 layer_count vgs:cover
set_screensaver '{"idleEnabled": false, "idleSeconds": 2}'
expect "idle disabled reload before on demand" ok ipc shell reloadConfig
expect "on demand starts while idle is off" ok ipc vgs.screensaver invoke start ''
expect_poll "cover maps after on demand" "$(output_count)" cover_count
expect_poll "status says running" Running state_text
argv_has_art() { [[ -s $ss_log ]] && grep -q -- '--canvas-width' "$ss_log" && echo yes || echo no; }
expect_poll "ttfx stand-in was started" yes argv_has_art
sleep 1.2
type_keys -k Escape || fail "typing Escape to close the screensaver failed"
expect_poll "cover is gone after keyboard input" 0 layer_count vgs:cover
expect_poll "status says off" Off state_text
screensaver_output=SMOKE-SCREENSAVER
base_outputs="$(output_count)"
expect "the nested compositor adds a monitor for screensaver focus" ok hypr output create headless "$screensaver_output"
expect_poll "the added monitor is visible to the shell" "$((base_outputs + 1))" output_count
expect "on demand starts on every output" ok ipc vgs.screensaver invoke start ''
expect_poll "one cover maps per output with two outputs" "$(output_count)" cover_count
sleep 2
expect "two-output covers stay running after focus settles" Running state_text
type_keys -k Escape || fail "typing Escape to close the two-output screensaver failed"
expect_poll "two-output covers are gone after keyboard input" 0 layer_count vgs:cover
expect "the nested compositor removes the screensaver focus monitor" ok hypr output remove "$screensaver_output"
expect_poll "the removed screensaver monitor is gone" "$base_outputs" output_count
expect "on demand starts for pointer dismissal" ok ipc vgs.screensaver invoke start ''
expect_poll "cover maps before pointer motion" "$(output_count)" cover_count
hover 20 20 || fail "initial hover failed"
sleep 0.2
hover 240 240 || fail "motion hover failed"
for _ in $(seq 1 50); do
  [[ "$(layer_count vgs:cover)" == 0 ]] && { ok "cover is gone after pointer motion"; break; }
  sleep 0.2
done
if [[ "$(layer_count vgs:cover)" != 0 ]]; then
  fail "cover is gone after pointer motion"
  ipc vgs.screensaver invoke stop '' >/dev/null || true
fi
art_dir="$home/.config/vgshell"
mkdir -p -- "$art_dir"
fixture="$sandbox/screensaver-fixture.png"
expected="$sandbox/screensaver-expected.txt"
magick -size 4x4 xc:none -fill black -draw 'point 0,0 point 1,1 point 0,2 point 1,3' "$fixture"
"$repo/shell/plugins/vgs.screensaver/bin/transcode-ascii" "$fixture" "$art_dir/screensaver.txt" --width 2 --height 1
printf '⢕\n' >"$expected"
art_matches() { cmp -s -- "$expected" "$art_dir/screensaver.txt" && echo same || echo different; }
expect "image transcode writes expected art" same art_matches
expect_poll "custom art status is truthful" "Custom art" art_status
: >"$ss_log"
expect "starts after custom art" ok ipc vgs.screensaver invoke start ''
argv_names_art() { grep -q -- "$art_dir/screensaver.txt" "$ss_log" && echo yes || echo no; }
expect_poll "ttfx argv names the art file" yes argv_names_art
expect "screensaver stops by IPC" ok ipc vgs.screensaver invoke stop ''
expect_poll "cover is gone after IPC stop" 0 layer_count vgs:cover
rm -f -- "$art_dir/screensaver.txt"
stop_shell || fail "the shell stops before lock-order checks"
start_shell "$repo" "$sandbox/screensaver-lock-order-qs.log" || fail "the shell starts again before lock-order checks"
expect_poll "screensaver service is rebuilt before lock-order checks" True record_exists vgs.screensaver
idle_start() { # LABEL
  type_keys -k Shift_L || fail "$1: typing the idle-start key failed"
  idle_started_ms="$(now_ms)"
}
ms_since_idle() { echo $(( $(now_ms) - idle_started_ms )); }
measure_idle_order() { # LABEL WANT_COVER_FIRST yes|no
  local label="$1" want_cover_first="$2" deadline cover_ms="" lock_ms="" covers="" lock=""
  deadline=$(( $(now_ms) + 8000 ))
  while (( $(now_ms) < deadline )); do
    covers="$(cover_count)" || covers=unread
    lock="$(session_lock)" || lock=unread
    if [[ -z $cover_ms && $covers == "$(output_count)" ]]; then cover_ms="$(ms_since_idle)"; fi
    if [[ -z $lock_ms && $lock == locked ]]; then lock_ms="$(ms_since_idle)"; break; fi
    sleep 0.2
  done
  printf 'screensaver-order: label=%s cover_ms=%s lock_ms=%s covers=%s lock=%s\n' "$label" "${cover_ms:-none}" "${lock_ms:-none}" "$covers" "$lock"
  if [[ -z $lock_ms ]]; then fail "$label: the session locks on idle"; return; fi
  if [[ $lock_ms -lt 3500 ]]; then fail "$label: lock waits at least 3.5 s from idle start"; else ok "$label: lock waits at least 3.5 s from idle start (t=${lock_ms}ms)"; fi
  if [[ $want_cover_first == yes ]]; then
    if [[ -z $cover_ms ]]; then fail "$label: cover maps before lock"; return; fi
    if [[ $cover_ms -lt 1500 ]]; then fail "$label: cover waits at least 1.5 s from idle start"; else ok "$label: cover waits at least 1.5 s from idle start (t=${cover_ms}ms)"; fi
    if [[ $cover_ms -lt $lock_ms ]]; then ok "$label: cover maps before lock (cover=${cover_ms}ms lock=${lock_ms}ms)"; else fail "$label: cover maps before lock (cover=${cover_ms}ms lock=${lock_ms}ms)"; fi
  else
    if [[ -z $cover_ms ]]; then ok "$label: no cover maps before lock"; else fail "$label: no cover maps before lock (cover=${cover_ms}ms lock=${lock_ms}ms)"; fi
  fi
}
set_lock_seconds() { # SECONDS
  python3 - "$ss_config" "$1" <<'PYSETLOCK'
import json, os, sys
path, seconds = sys.argv[1], int(sys.argv[2])
doc = json.load(open(path))
doc["disabledPlugins"] = [p for p in doc.get("disabledPlugins", []) if p != "vgs.lock"]
rows = doc.setdefault("plugins", [])
row = next((r for r in rows if r.get("id") == "vgs.lock"), None)
if row is None:
    row = {"id": "vgs.lock"}
    rows.append(row)
row["idleLockSeconds"] = seconds
with open(path + ".next", "w") as out:
    json.dump(doc, out)
os.replace(path + ".next", path)
PYSETLOCK
}
expect "enabling lock for ordering is allowed" ok ipc shell setPluginEnabled vgs.lock true
set_lock_seconds 4
set_screensaver '{"idleEnabled": true, "idleSeconds": 2}'
expect "reload for lock ordering" ok ipc shell reloadConfig
rescan "rescan after enabling lock for ordering answers ok"
expect "lock remains enabled after ordering config writes" ok ipc shell setPluginEnabled vgs.lock true
rescan "rescan after confirming lock for ordering answers ok"
expect_poll "lock service is built for lock ordering" True record_exists vgs.lock
idle_start "lock ordering"
expect_poll "ordering maps covers before lock" "$(output_count)" cover_count
expect_poll "ttfx stand-in is alive before lock" yes standin_alive
measure_idle_order "lock ordering" yes
expect_poll "cover is gone under lock" 0 layer_count vgs:cover
expect_poll "ttfx stand-in is gone under lock" no standin_alive
release "screensaver lock-order"
set_lock_seconds 4
set_screensaver '{"idleEnabled": true, "idleSeconds": 6}'
expect "reload for lock-before-screensaver control" ok ipc shell reloadConfig
idle_start "lock-before-screensaver control"
measure_idle_order "control lock before screensaver" no
release "screensaver lock-before-screensaver control"
set_lock_seconds 4
set_screensaver '{"idleEnabled": true, "idleSeconds": 2}'
expect "reload for dismissal before lock" ok ipc shell reloadConfig
idle_start "dismissal before lock"
expect_poll "dismissal maps cover before lock" "$(output_count)" cover_count
while (( $(ms_since_idle) < 3000 )); do sleep 0.1; done
type_keys -k Escape || fail "typing Escape before the lock failed"
expect_poll "dismissal removed cover" 0 layer_count vgs:cover
while (( $(ms_since_idle) < 5500 )); do sleep 0.1; done
expect "dismissal prevents lock at the original deadline" unlocked session_lock
expect_poll "dismissal lets lock run after activity restarts idle" locked session_lock
release "screensaver dismissal restart"
set_screensaver '{"idleEnabled": false, "idleSeconds": 2}'
expect "reload before plugin-alone checks" ok ipc shell reloadConfig
# Screensaver alone: lock disabled or absent is not needed for start.
expect "disabling lock is allowed" ok ipc shell setPluginEnabled vgs.lock false
expect "screensaver still starts with lock disabled" ok ipc vgs.screensaver invoke start ''
expect_poll "cover maps with lock disabled" "$(output_count)" cover_count
expect "screensaver stops after lock-disabled check" ok ipc vgs.screensaver invoke stop ''
expect "disabling screensaver is allowed" ok ipc shell setPluginEnabled vgs.screensaver false
expect "enabling lock for lock-alone check is allowed" ok ipc shell setPluginEnabled vgs.lock true
set_lock_seconds 4
expect "reload for lock-alone check" ok ipc shell reloadConfig
rescan "rescan after enabling lock alone answers ok"
expect "lock remains enabled after lock-alone config writes" ok ipc shell setPluginEnabled vgs.lock true
rescan "rescan after confirming lock alone answers ok"
expect_poll "lock service is built for lock-alone" True record_exists vgs.lock
idle_start "lock alone"
for _ in $(seq 1 30); do
  [[ "$(session_lock)" == locked ]] && break
  sleep 0.2
done
expect "lock alone locks at its time" locked session_lock
release "screensaver lock-alone"
expect "disabling lock after lock-alone check" ok ipc shell setPluginEnabled vgs.lock false
expect "enabling screensaver is allowed for later rows" ok ipc shell setPluginEnabled vgs.screensaver true
set_lock_seconds 300
set_screensaver '{"idleEnabled": true, "idleSeconds": 150, "effect": "random", "frameRate": 30}'
expect "reload after screensaver row restore" ok ipc shell reloadConfig
if [[ $ss_lock_enabled == True ]]; then
  expect "enabling lock after screensaver row is allowed" ok ipc shell setPluginEnabled vgs.lock true
else
  expect "disabling lock restores its state before the row" ok ipc shell setPluginEnabled vgs.lock false
  expect_poll "the lock service is gone after the row" False record_exists vgs.lock
fi
if [[ $ss_probe_enabled == True ]]; then
  expect "re-enabling the capability fixture is allowed" ok ipc shell setPluginEnabled acme.probe true
  expect_poll "the capability fixture is built again after the row" True record_exists acme.probe
fi
rm -f -- "${shim:?}/ttfx"
