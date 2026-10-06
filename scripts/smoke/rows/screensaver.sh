# Screensaver plugin Phase B row. It uses a ttfx stand-in whose help carries
# one planted effect and whose frames are deterministic. Latency polls use
# expect_poll's 0.2 s cadence. Measured row runtime on host cachy on
# 2026-10-05 under the nested sandbox: under 20 s.
# inputs: shell/plugins/vgs.screensaver/* shell/Core/PluginLogic.js shell/Hosts/BackgroundHost.qml scripts/smoke/fixtures/screensaver-ttfx scripts/smoke/rows/lock.sh
set -euo pipefail
ss_config="$home/.config/vgshell/shell.json"
ss_log="$home/.local/state/vgshell/screensaver-ttfx.log"
cp -- "$repo/scripts/smoke/fixtures/screensaver-ttfx" "$shim/ttfx"
chmod 755 "$shim/ttfx"
state_text() { ipc smoke statusValues vgs.screensaver | py_reply 'import json,sys; v=json.load(sys.stdin).get("state",{}); print(v.get("text","missing"))'; }
lock_order() { ipc smoke statusValues vgs.screensaver | py_reply 'import json,sys; v=json.load(sys.stdin).get("lockOrder"); print("absent" if v is None else json.dumps([v.get("tone"), v.get("text")]))'; }
art_status() { ipc smoke statusValues vgs.screensaver | py_reply 'import json,sys; v=json.load(sys.stdin).get("art",{}); print(v.get("text","missing"))'; }
cover_count() { layer_count vgs:cover; }
output_count() { hypr -j monitors | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
standin_alive() { pgrep -f screensaver-ttfx >/dev/null && echo yes || echo no; }
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
expect "enabling screensaver for its row is allowed" ok ipc shell setPluginEnabled vgs.screensaver true
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
type_keys -k Escape || fail "typing Escape to close the screensaver failed"
expect_poll "cover is gone after keyboard input" 0 layer_count vgs:cover
expect_poll "status says off" Off state_text
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
expect "enabling lock for ordering is allowed" ok ipc shell setPluginEnabled vgs.lock true
python3 - "$ss_config" <<'PY'
import json, os, sys
path = sys.argv[1]
doc = json.load(open(path))
row = next(r for r in doc.setdefault("plugins", []) if r.get("id") == "vgs.lock")
row["idleLockSeconds"] = 4
with open(path + ".next", "w") as out: json.dump(doc, out)
os.replace(path + ".next", path)
PY
set_screensaver '{"idleEnabled": true, "idleSeconds": 2}'
expect "reload for lock ordering" ok ipc shell reloadConfig
expect_poll "lock service is built for lock ordering" True record_exists vgs.lock
expect_poll "lock ordering maps cover first" "$(output_count)" cover_count
sleep 2
expect "lock ordering asks lock after cover" ok ipc vgs.lock invoke lock ''
expect_poll "lock ordering locks later" locked session_lock
expect_poll "cover is gone under lock" 0 layer_count vgs:cover
expect_poll "ttfx stand-in is gone under lock" no standin_alive
release "screensaver lock-order"
set_screensaver '{"idleEnabled": true, "idleSeconds": 2}'
expect "reload for dismissal before lock" ok ipc shell reloadConfig
expect "dismissal starts cover before lock" ok ipc vgs.screensaver invoke start ''
expect_poll "dismissal maps cover before lock" "$(output_count)" cover_count
sleep 1
type_keys -k Escape || fail "typing Escape before the lock failed"
expect_poll "dismissal removed cover" 0 layer_count vgs:cover
sleep 3
expect "dismissal prevents lock" unlocked session_lock
set_screensaver '{"idleEnabled": false, "idleSeconds": 2}'
expect "reload before plugin-alone checks" ok ipc shell reloadConfig
# Screensaver alone: lock disabled or absent is not needed for start.
expect "disabling lock is allowed" ok ipc shell setPluginEnabled vgs.lock false
expect "screensaver still starts with lock disabled" ok ipc vgs.screensaver invoke start ''
expect_poll "cover maps with lock disabled" "$(output_count)" cover_count
expect "screensaver stops after lock-disabled check" ok ipc vgs.screensaver invoke stop ''
expect "disabling screensaver is allowed" ok ipc shell setPluginEnabled vgs.screensaver false
expect "enabling lock for lock-alone check is allowed" ok ipc shell setPluginEnabled vgs.lock true
python3 - "$ss_config" <<'PY'
import json, os, sys
path = sys.argv[1]
doc = json.load(open(path))
row = next(r for r in doc.setdefault("plugins", []) if r.get("id") == "vgs.lock")
row["idleLockSeconds"] = 4
with open(path + ".next", "w") as out: json.dump(doc, out)
os.replace(path + ".next", path)
PY
expect "reload for lock-alone check" ok ipc shell reloadConfig
expect_poll "lock service is built for lock-alone" True record_exists vgs.lock
sleep 4
expect "lock alone asks lock at its time" ok ipc vgs.lock invoke lock ''
expect_poll "lock alone locks at its time" locked session_lock
release "screensaver lock-alone"
expect "disabling lock after lock-alone check" ok ipc shell setPluginEnabled vgs.lock false
expect "enabling screensaver is allowed for later rows" ok ipc shell setPluginEnabled vgs.screensaver true
rm -f -- "${shim:?}/ttfx"
