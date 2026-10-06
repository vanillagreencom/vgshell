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
state_text() { ipc smoke statusValues vgs.screensaver | py_reply 'import json,sys; v=json.load(sys.stdin).get("state",{}); print(v.get("text","missing"))'; }
expect "on demand starts while idle is off" ok ipc vgs.screensaver invoke start ''
expect_poll "cover maps after on demand" 1 layer_count vgs:cover
expect_poll "status says running" Running state_text
argv_has_art() { [[ -s $ss_log ]] && grep -q -- '--canvas-width' "$ss_log" && echo yes || echo no; }
expect_poll "ttfx stand-in was started" yes argv_has_art
type_keys -k Escape || fail "typing Escape to close the screensaver failed"
expect_poll "cover is gone after keyboard input" 0 layer_count vgs:cover
expect_poll "status says off" Off state_text
expect "on demand starts for pointer dismissal" ok ipc vgs.screensaver invoke start ''
expect_poll "cover maps before pointer motion" 1 layer_count vgs:cover
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
: >"$ss_log"
expect "starts after custom art" ok ipc vgs.screensaver invoke start ''
argv_names_art() { grep -q -- "$art_dir/screensaver.txt" "$ss_log" && echo yes || echo no; }
expect_poll "ttfx argv names the art file" yes argv_names_art
expect "screensaver stops by IPC" ok ipc vgs.screensaver invoke stop ''
expect_poll "cover is gone after IPC stop" 0 layer_count vgs:cover
# Screensaver alone: lock disabled or absent is not needed for start.
expect "disabling lock is allowed" ok ipc shell setPluginEnabled vgs.lock false
expect "screensaver still starts with lock disabled" ok ipc vgs.screensaver invoke start ''
expect_poll "cover maps with lock disabled" 1 layer_count vgs:cover
expect "screensaver stops after lock-disabled check" ok ipc vgs.screensaver invoke stop ''
expect "disabling screensaver is allowed" ok ipc shell setPluginEnabled vgs.screensaver false
expect "enabling screensaver is allowed for later rows" ok ipc shell setPluginEnabled vgs.screensaver true
rm -f -- "${shim:?}/ttfx"
