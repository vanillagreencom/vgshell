# Screensaver plugin Phase B row. It uses a ttfx stand-in whose help carries
# one planted effect and whose frames are deterministic. Latency polls use
# expect_poll's 0.2 s cadence. Measured row runtime on host cachy on
# 2026-10-05 under the nested sandbox: under 20 s. The conversion
# deadline checks add an unmeasured wait.
# inputs: shell/plugins/vgs.screensaver/* shell/plugins/vgs.screensaver/bin/transcode-ascii shell/Core/PluginLogic.js shell/Core/ConfigLogic.js shell/Core/Compositor.qml shell/Hosts/BackgroundHost.qml scripts/smoke/toplevel/* scripts/smoke/mode-hold.sh scripts/smoke/fixtures/screensaver-ttfx scripts/smoke/rows/capability-release.sh scripts/smoke/rows/lock.sh scripts/smoke/rows/capabilities.sh
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
art_status() { ipc smoke statusValues vgs.screensaver | py_reply 'import json,sys; v=json.load(sys.stdin).get("art"); print("absent" if v is None else v.get("text"))'; }
art_setting() { python3 -c 'import json,sys; row=next((r for r in json.load(open(sys.argv[1])).get("plugins",[]) if r.get("id")=="vgs.screensaver"),{}); print(row.get("art",""))' "$ss_config"; }
cover_count() { layer_count vgs:cover; }
output_count() { hypr -j monitors | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
standin_alive() { pgrep -P "$shell_qs_pid" -f -- "$shim/ttfx" >/dev/null && echo yes || echo no; }
ss_effect_count() { local count; count="$(pgrep -c -P "$shell_qs_pid" -f -- "$shim/ttfx")" || [[ $count == 0 ]]; printf '%s\n' "$count"; }
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
expect_poll "the VGS logo shows no art problem" absent art_status
expect "enabling lock for lock order status is allowed" ok ipc shell setPluginEnabled vgs.lock true
set_screensaver '{"idleEnabled": true, "idleSeconds": 2}'
expect "lock order reload before ok status" ok ipc shell reloadConfig
expect_poll "lock order reads lock time as ok" '["ok", "Lock follows at 300 s"]' lock_order
set_screensaver '{"idleEnabled": true, "idleSeconds": 301}'
expect "lock order reload before warning status" ok ipc shell reloadConfig
expect_poll "lock order warns when lock is before screensaver" '["warning", "Lock follows at 300 s"]' lock_order
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

# Both fixtures use a nonblack background, so even a dark theme catches
# forwarding Theme.color.background to ttfx instead of the cover's black.
ss_theme_file="$home/.config/vgshell/theme.json"
ss_theme_before="$(ipc smoke themeName)"
ss_theme_had_file=false
if [[ -f $ss_theme_file ]]; then
  cp -- "$ss_theme_file" "$sandbox/screensaver-theme-before.json"
  ss_theme_had_file=true
fi
ss_background_arg() {
  awk '{for (i = 1; i < NF; i++) if ($i == "--terminal-background-color") value = $(i + 1)} END {print value == "" ? "pending" : value}' "$ss_log"
}
for ss_theme_mode in dark light; do
  case $ss_theme_mode in
    dark) ss_theme_background='#102030'; ss_theme_ink='#d7d7d9' ;;
    light) ss_theme_background='#fffdf0'; ss_theme_ink='#101010' ;;
  esac
  printf '{"schemaVersion":1,"name":"screensaver-%s","tokens":{"scheme":{"mode":"%s"},"palette":{"background":"%s","foreground":"%s"}}}\n' \
    "$ss_theme_mode" "$ss_theme_mode" "$ss_theme_background" "$ss_theme_ink" >"$ss_theme_file.next"
  mv -T -- "$ss_theme_file.next" "$ss_theme_file"
  expect_poll "the $ss_theme_mode screensaver theme fixture is published" "screensaver-$ss_theme_mode" ipc smoke themeName
  : >"$ss_log"
  expect "screensaver starts under the $ss_theme_mode theme" ok ipc vgs.screensaver invoke start ''
  expect_poll "the $ss_theme_mode theme passes black to ttfx" '#000000' ss_background_arg
  expect "screensaver stops after the $ss_theme_mode background check" ok ipc vgs.screensaver invoke stop ''
  expect_poll "the $ss_theme_mode background check releases its cover" 0 cover_count
done
if "$ss_theme_had_file"; then
  mv -T -- "$sandbox/screensaver-theme-before.json" "$ss_theme_file"
else
  rm -- "$ss_theme_file"
fi
expect_poll "the screensaver background checks restore the theme" "$ss_theme_before" ipc smoke themeName
screensaver_output=SMOKE-SCREENSAVER
base_outputs="$(output_count)"
# A headless output can stay unsized on NVIDIA; the harness sink gives
# the second Cover a drawable Wayland output.
expect "the screensaver monitor has a mode rule before creation" ok hypr eval "hl.monitor({ output = \"$screensaver_output\", mode = \"preferred\", position = \"auto-right\", scale = 1 })"
expect "the nested compositor adds a monitor for screensaver focus" ok hypr output create wayland "$screensaver_output"
expect_poll "the added monitor is visible to the shell" "$((base_outputs + 1))" output_count
ss_output_sized() { unscaled_mode_of "$screensaver_output" >/dev/null && echo sized; }
expect_poll "the added monitor has usable geometry before starting covers" sized ss_output_sized
expect "on demand starts on every output" ok ipc vgs.screensaver invoke start ''
expect_poll "one cover maps per output with two outputs" "$(output_count)" cover_count
sleep 2
expect "two-output covers stay running after focus settles" Running state_text
expect "enabling the dispatch fixture while lock is disabled is allowed" ok ipc shell setPluginEnabled acme.probe true
expect_poll "the dispatch fixture is built for display power" True record_exists acme.probe
expect_poll "every cover stays mapped after the dispatch fixture is enabled" "$((base_outputs + 1))" cover_count
expect_poll "each output has a running ttfx child before display off" "$((base_outputs + 1))" ss_effect_count
expect "the core queues display off while covers run" ok probe dispatch "displayPower off"
expect_poll "display off is confirmed through session" true ipc smoke readInstance service vgs.screensaver displaysOff
expect_poll "display off stops the screensaver service" Off state_text
expect_poll "display off removes every cover" 0 cover_count
expect_poll "display off ends every ttfx child" no standin_alive
ss_starts_off="$(wc -l <"$ss_log")"
expect "an explicit screensaver start is refused while displays stay off" 'refused: screensaver=displays-off' ipc vgs.screensaver invoke start ''
set_screensaver '{"idleEnabled": true, "idleSeconds": 1}'
expect "reload arms the idle screensaver behind dark displays" ok ipc shell reloadConfig
sleep 2 # Cross the one-second idle notification while sending no input.
expect "idle start keeps the screensaver off behind dark displays" Off state_text
expect "idle start leaves no ttfx child behind dark displays" no standin_alive
expect "neither start launched ttfx behind dark displays" "$ss_starts_off" wc -l <"$ss_log"
expect "display off still holds after both start paths" true ipc smoke readInstance service vgs.screensaver displaysOff
type_keys -k Shift_L || fail "waking the nested displays after the screensaver check failed"
expect_poll "input clears the display off fact" false ipc smoke readInstance service vgs.screensaver displaysOff
set_screensaver '{"idleEnabled": false}'
expect "reload restores manual screensaver start" ok ipc shell reloadConfig
expect "disabling the dispatch fixture releases lock again" ok ipc shell setPluginEnabled acme.probe false
expect "the nested compositor removes the screensaver focus monitor" ok hypr output remove "$screensaver_output"
expect_poll "the removed screensaver monitor is gone" "$base_outputs" output_count
expect "reloading removes the screensaver monitor's temporary rule" ok hypr reload config-only
ss_cover_host="cover:$(hypr -j monitors | py_reply 'import json,sys; print(json.load(sys.stdin)[0]["name"])')"
hover 20 20 || fail "resting the pointer before the screensaver failed"
expect "on demand starts for pointer dismissal" ok ipc vgs.screensaver invoke start ''
expect_poll "cover is showing before pointer motion" true ipc smoke readInstance "$ss_cover_host" vgs.screensaver shown
expect_poll "cover has the pointer entry position" true ipc smoke readInstance "$ss_cover_host" vgs.screensaver pointerReady
hover 240 240 || fail "motion hover failed"
expect_poll "cover is gone after the first pointer motion" 0 cover_count
expect "pointer dismissal stops the screensaver" Off state_text

# Hold a disposable cover mapped while its typed shown property is false.
# This reproduces the old layer-only wait without depending on scheduling.
# Both copies use Cover.qml's real MouseArea; only the old copy drops the
# entry baseline. No ttfx subprocess runs in these input-only controls.
ss_pointer_dir="$repo/shell/plugins/vgs.screensaver/PointerControls"
mkdir -p -- "$ss_pointer_dir"
python3 - "$repo/shell/plugins/vgs.screensaver" "$ss_pointer_dir" <<'PYPOINTER'
from pathlib import Path
import sys
source, controls = map(Path, sys.argv[1:])
text = (source / 'Cover.qml').read_text()
baseline = '''        pointerReady = shown && pointer.containsMouse;
        if (pointerReady) {
            firstX = pointer.mouseX;
            firstY = pointer.mouseY;
        }'''
entered = '''        onEntered: {
            if (!root.shown) return;
            root.firstX = mouseX;
            root.firstY = mouseY;
            root.pointerReady = true;
        }
'''
assert text.count(baseline) == 1 and text.count(entered) == 1
old = text.replace(baseline, '        pointerReady = false;').replace(entered, '')
assert old != text
for name, cover in [('current', text), ('old', old)]:
    directory = controls / name
    directory.mkdir()
    needle = '        id: pointer\n'
    assert cover.count(needle) == 1
    (directory / 'Cover.qml').write_text(cover.replace(needle, needle + '        objectName: "screensaverPointer"\n'))
    for sibling in ['ScreensaverLogic.js', 'logo.txt']:
        (directory / sibling).write_bytes((source / sibling).read_bytes())
PYPOINTER
for ss_pointer_case in current old; do
  cat >"$ss_pointer_dir/$ss_pointer_case/Control.qml" <<'QMLPOINTER'
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: control
    required property var reference
    property string requestedState: "Off"
    property int stops: 0
    readonly property bool shown: cover.shown
    readonly property bool pointerReady: cover.pointerReady
    readonly property real firstX: cover.firstX
    readonly property var pointer: Array.from(cover.children).find(child => child.objectName === "screensaverPointer")
    readonly property real pointerX: pointer === undefined ? -1 : pointer.mouseX
    screen: reference.screen
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "vgs:screensaver-motion-control"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    visible: stops === 0
    function showCover() { requestedState = "Running"; }
    Cover {
        id: cover
        anchors.fill: parent
        shell: ({ status: { values: { state: { text: control.requestedState } } },
            session: { locked: false }, requirements: { missing: ["ttfx"] },
            settings: { effect: "planted", frameRate: 30 },
            ipc: { call: () => { control.stops += 1; } } })
    }
}
QMLPOINTER
  hover 10 10 || fail "$ss_pointer_case: resting the control pointer failed"
  expect "the $ss_pointer_case pointer control builds" ok ipc smoke popupLoad "ss-pointer-$ss_pointer_case" "$ss_pointer_dir/$ss_pointer_case/Control.qml" "$ss_cover_host" vgs.screensaver '{"reference":"@instance"}'
  expect_poll "$ss_pointer_case: the old wait sees a mapped layer" 1 layer_count vgs:screensaver-motion-control
  expect "$ss_pointer_case: the mapped cover is not showing" false ipc smoke popupRead "ss-pointer-$ss_pointer_case" shown
  hover 20 20 || fail "$ss_pointer_case: pre-showing motion failed"
  expect_poll "$ss_pointer_case: pre-showing motion reached the cover" 20 ipc smoke popupRead "ss-pointer-$ss_pointer_case" pointerX
  expect "$ss_pointer_case: motion before showing keeps the cover" 0 ipc smoke popupRead "ss-pointer-$ss_pointer_case" stops
  expect "$ss_pointer_case: the cover starts showing" ok ipc smoke popupCall "ss-pointer-$ss_pointer_case" showCover
  expect_poll "$ss_pointer_case: the typed cover state is showing" true ipc smoke popupRead "ss-pointer-$ss_pointer_case" shown
  hover 240 240 || fail "$ss_pointer_case: first showing motion failed"
  if [[ $ss_pointer_case == current ]]; then
    expect_poll "the first real motion after showing dismisses the cover" 0 layer_count vgs:screensaver-motion-control
    expect "the first real motion calls stop once" 1 ipc smoke popupRead ss-pointer-current stops
  else
    expect_poll "control: the second old-wait move only sets the baseline" 240 ipc smoke popupRead ss-pointer-old firstX
    expect "control: the old layer-only wait fails pointer dismissal" 1 layer_count vgs:screensaver-motion-control
    expect "control: the old input handler never calls stop" 0 ipc smoke popupRead ss-pointer-old stops
  fi
  expect "the $ss_pointer_case pointer control is released" ok ipc smoke popupDrop "ss-pointer-$ss_pointer_case"
done
rm -r -- "${ss_pointer_dir:?}"
art_dir="$home/.config/vgshell"
mkdir -p -- "$art_dir"
fixture="$sandbox/screensaver-fixture.png"
expected="$sandbox/screensaver-expected.txt"
magick -size 4x4 xc:none -fill black -draw 'point 0,0 point 1,1 point 0,2 point 1,3' "$fixture"
"$repo/shell/plugins/vgs.screensaver/bin/transcode-ascii" "$fixture" "$sandbox/screensaver-transcode.txt" --width 2 --height 1
printf '⢕\n' >"$expected"
art_matches() { cmp -s -- "$expected" "$sandbox/screensaver-transcode.txt" && echo same || echo different; }
expect "image transcode writes expected art" same art_matches
converted="$home/.local/state/vgshell/screensaver-art.txt"
rm -f -- "${home:?}/.local/state/vgshell/screensaver-art.txt"
converted_ready() { [[ -s $converted ]] && echo yes || echo no; }
argv_names() { grep -q -- "$1" "$ss_log" && echo yes || echo no; }
art_patch() { python3 -c 'import json,sys; print(json.dumps({"art": sys.argv[1]}))' "$1"; }
art_in_use() { ipc smoke statusValues vgs.screensaver | py_reply 'import json,sys; print(json.load(sys.stdin).get("artFile", ""))'; }
slow_magick_alive() { pgrep -f -- "$shim/magick" >/dev/null && echo yes || echo no; }
kill_slow_magick() {
  local pid
  while IFS= read -r pid; do
    [[ -n $pid ]] || continue
    case "$pid" in (*[!0-9]*) fail "slow magick pid is not numeric: $pid"; return ;; esac
    kill "$pid" 2>/dev/null || true
  done < <(pgrep -f -- "$shim/magick" || true)
}
write_slow_magick() {
  cat >"$shim/magick" <<'PYMAGICK'
#!/usr/bin/env python3
import time
time.sleep(600)
PYMAGICK
  chmod 755 "$shim/magick"
}
set_screensaver "$(art_patch "$fixture")"
expect "reload config for image art" ok ipc shell reloadConfig
expect_poll "the Art setting converts the image" yes converted_ready
expect_poll "a readable art image shows no art problem" absent art_status
expect_poll "the converted image is the art in use" "$converted" art_in_use
: >"$ss_log"
expect "starts after image art" ok ipc vgs.screensaver invoke start ''
expect_poll "ttfx argv names the converted art" yes argv_names "$converted"
expect "screensaver stops by IPC" ok ipc vgs.screensaver invoke stop ''
expect_poll "cover is gone after IPC stop" 0 layer_count vgs:cover
text_art="$sandbox/screensaver-art-text.txt"
printf 'VGS\n' >"$text_art"
set_screensaver "$(art_patch "$text_art")"
expect "reload config for text art" ok ipc shell reloadConfig
expect_poll "text art shows no art problem" absent art_status
expect_poll "text art is the art in use" "$text_art" art_in_use
: >"$ss_log"
expect "starts after text art" ok ipc vgs.screensaver invoke start ''
expect_poll "ttfx argv names the text art file" yes argv_names "$text_art"
expect "screensaver stops by IPC after text art" ok ipc vgs.screensaver invoke stop ''
expect_poll "cover is gone after text art stop" 0 layer_count vgs:cover
set_screensaver "$(art_patch "$sandbox/screensaver-missing.png")"
expect "reload config for a missing art image" ok ipc shell reloadConfig
expect_poll "a missing art image shows the art problem" "Cannot read the art image" art_status
expect "a failed image keeps the text art in use" "$text_art" art_in_use
: >"$ss_log"
expect "starts after failed image art" ok ipc vgs.screensaver invoke start ''
expect_poll "ttfx argv still names the previous text art" yes argv_names "$text_art"
expect "screensaver stops by IPC after failed image" ok ipc vgs.screensaver invoke stop ''
expect_poll "cover is gone after failed image stop" 0 layer_count vgs:cover
jpeg_art="$sandbox/screensaver-art.jpg"
magick "$fixture" "$jpeg_art"
set_screensaver "$(art_patch "$jpeg_art")"
expect "reload config for JPEG art" ok ipc shell reloadConfig
expect_poll "JPEG art is refused as the wrong type" "Art must be a PNG or SVG image or a text file" art_status
expect "refused JPEG art keeps the previous art in use" "$text_art" art_in_use
set_screensaver "$(art_patch "$sandbox/screensaver-missing.txt")"
expect "reload config for missing text art" ok ipc shell reloadConfig
expect_poll "missing text art shows the art problem" "Cannot read the art file" art_status
expect "unreadable text art keeps the previous art in use" "$text_art" art_in_use
printf '#!/usr/bin/env bash\nexit 1\n' >"$shim/magick"
chmod 755 "$shim/magick"
set_screensaver "$(art_patch "$fixture")"
expect "reload config for a failing image conversion" ok ipc shell reloadConfig
expect_poll "a failed image conversion shows the art problem" "Cannot read the art image" art_status
rm -f -- "${shim:?}/magick"
rescan "rescan after a failed conversion answers ok"
expect_poll "a failed conversion retries after a rescan" absent art_status
expect_poll "the retried conversion is the art in use" "$converted" art_in_use
slow_fixture="$sandbox/screensaver-slow.png"
cp -- "$fixture" "$slow_fixture"
write_slow_magick
set_screensaver "$(art_patch "$slow_fixture")"
expect "reload config for slow image conversion" ok ipc shell reloadConfig
expect_poll "the slow image conversion starts magick" yes slow_magick_alive
set_screensaver "$(art_patch "$text_art")"
expect "reload config to replace a slow conversion with text" ok ipc shell reloadConfig
expect_poll "a new Art value ends the running magick" no slow_magick_alive
expect_poll "the replacement text art has no problem" absent art_status
expect_poll "the replacement text art is in use" "$text_art" art_in_use
set_screensaver "$(art_patch "$slow_fixture")"
expect "reload config for disable during conversion" ok ipc shell reloadConfig
expect_poll "the slow conversion starts before disable" yes slow_magick_alive
expect "disabling screensaver during conversion is allowed" ok ipc shell setPluginEnabled vgs.screensaver false
expect_poll "disabling the plugin ends magick" no slow_magick_alive
expect "enabling screensaver during conversion check is allowed" ok ipc shell setPluginEnabled vgs.screensaver true
expect_poll "screensaver service is rebuilt after conversion disable" True record_exists vgs.screensaver
expect_poll "the rebuilt service starts the pending conversion" yes slow_magick_alive
expect_poll "a slow image conversion shows the timeout problem" "The art image took too long to convert" art_status
expect_poll "the timeout ends magick" no slow_magick_alive
expect "disabling screensaver for transcode process controls is allowed" ok ipc shell setPluginEnabled vgs.screensaver false
transcode_control_dir="$sandbox/screensaver-transcode-control"
rm -rf -- "$transcode_control_dir"
mkdir -p -- "$transcode_control_dir"
python3 - "$repo/shell/plugins/vgs.screensaver/bin/transcode-ascii" "$transcode_control_dir/transcode-no-held" <<'PYCONTROL'
from pathlib import Path
import sys
source, target = map(Path, sys.argv[1:])
text = source.read_text()
replacements = [
    ('"${held_quiet[@]}" magick', 'magick', 1),
    ('"${held[@]}" magick', 'magick', 1),
    ('"${held[@]}" awk', 'awk', 2),
]
for old, new, count in replacements:
    actual = text.count(old)
    if actual != count:
        raise SystemExit(f'{old}: count={actual} want={count}')
    text = text.replace(old, new)
target.write_text(text)
target.chmod(0o755)
PYCONTROL
run_transcode_kill() {
  local script="$1" label="$2" pid
  local out="$transcode_control_dir/$label.out"
  PATH="$shim:$PATH" "$script" "$fixture" "$out" --width 2 --height 1 >/dev/null 2>&1 &
  pid=$!
  case "$pid" in (*[!0-9]*) fail "$label transcode pid is not numeric: $pid"; return ;; esac
  expect_poll "$label starts the slow magick stand-in" yes slow_magick_alive
  kill -KILL "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}
run_transcode_kill "$transcode_control_dir/transcode-no-held" control-no-held
expect "control: a conversion without the parent-death signal leaves magick running" yes slow_magick_alive
kill_slow_magick
expect_poll "control cleanup ends the unheld magick" no slow_magick_alive
run_transcode_kill "$repo/shell/plugins/vgs.screensaver/bin/transcode-ascii" control-held
expect_poll "the real transcode script ends magick with the parent-death signal" no slow_magick_alive
rm -rf -- "${transcode_control_dir:?}"
rm -f -- "${shim:?}/magick"
expect "enabling screensaver after transcode controls is allowed" ok ipc shell setPluginEnabled vgs.screensaver true
stop_shell || fail "the shell stops before lock-order checks"
# D107: art made before the Art setting sat in screensaver.txt; the service
# moves it once into the file the setting names.
set_screensaver '{"art": ""}'
rm -f -- "${art_dir:?}/screensaver-art.txt"
printf 'OLD\n' >"$art_dir/screensaver.txt"
rm -f -- "${shim:?}/ttfx"
expect "the shell PATH has no ttfx before restart" none shell_resolves ttfx
start_shell "$repo" "$sandbox/screensaver-lock-order-qs.log" || fail "the shell starts again before lock-order checks"
expect_poll "screensaver service is rebuilt before lock-order checks" True record_exists vgs.screensaver
rescan "rescan with ttfx missing answers ok"
cp -- "$repo/scripts/smoke/fixtures/screensaver-ttfx" "$shim/ttfx"
chmod 755 "$shim/ttfx"
rescan "rescan after ttfx arrives answers ok"
expect_poll "effect choices publish after ttfx arrives" '[{"label": "Random", "value": "random"}, {"label": "planted", "value": "planted"}, {"label": "beams", "value": "beams"}]' choices
if grep -F 'QList("ttfx"' "$shell_log"; then fail "ttfx missing wrote a process warning"; else ok "ttfx missing wrote no process warning"; fi
expect_poll "earlier art moves into the Art setting" "$art_dir/screensaver-art.txt" art_setting
legacy_art_moved() { [[ ! -e $art_dir/screensaver.txt ]] && [[ $(cat -- "$art_dir/screensaver-art.txt") == OLD ]] && echo yes || echo no; }
expect "earlier art keeps its text at its new path" yes legacy_art_moved
set_screensaver '{"art": ""}'
expect "reload config after the art migration" ok ipc shell reloadConfig
rm -f -- "${art_dir:?}/screensaver-art.txt"
printf 'OLD2\n' >"$art_dir/screensaver.txt"
printf 'EXISTING\n' >"$art_dir/screensaver-art.txt"
expect "disabling screensaver for migration skip check is allowed" ok ipc shell setPluginEnabled vgs.screensaver false
expect "enabling screensaver for migration skip check is allowed" ok ipc shell setPluginEnabled vgs.screensaver true
expect_poll "screensaver service is rebuilt for migration skip check" True record_exists vgs.screensaver
sleep 1 # The move finishes in milliseconds; a skipped move writes no service status.
legacy_art_still_there() { [[ -e $art_dir/screensaver.txt ]] && [[ $(cat -- "$art_dir/screensaver.txt") == OLD2 ]] && echo yes || echo no; }
expect "a skipped migration keeps the Art setting unchanged" "" art_setting
expect "a skipped migration keeps the legacy file" yes legacy_art_still_there
rm -f -- "${art_dir:?}/screensaver.txt" "${art_dir:?}/screensaver-art.txt"
idle_start() { # LABEL
  type_keys -k Shift_L || fail "$1: typing the idle-start key failed"
  idle_started_ms="$(now_ms)"
}
ms_since_idle() { echo $(( $(now_ms) - idle_started_ms )); }
measure_idle_order() { # LABEL WANT_COVER_FIRST yes|no [window]
  local label="$1" want_cover_first="$2" control="${3:-}" deadline cover_ms="" lock_ms="" covers="" lock="" window_pid=""
  deadline=$(( $(now_ms) + 10000 ))
  while (( $(now_ms) < deadline )); do
    covers="$(cover_count)" || covers=unread
    lock="$(session_lock)" || lock=unread
    if [[ -z $cover_ms && $covers == "$(output_count)" ]]; then
      cover_ms="$(ms_since_idle)"
      if [[ $control == window ]]; then
        open_toplevel "$sandbox/screensaver-window-control.log" smoke.screensaver-control "Idle restart control" || { fail "$label: control window maps"; return; }
        window_pid="$toplevel_pid"
      fi
    fi
    if [[ -z $lock_ms && $lock == locked ]]; then lock_ms="$(ms_since_idle)"; break; fi
    sleep 0.2
  done
  printf 'screensaver-order: label=%s cover_ms=%s lock_ms=%s covers=%s lock=%s\n' "$label" "${cover_ms:-none}" "${lock_ms:-none}" "$covers" "$lock"
  [[ -z $window_pid ]] || close_toplevel "$window_pid" "$label: the control window exits"
  if [[ -z $lock_ms ]]; then fail "$label: the session locks on idle"; return; fi
  if [[ $control == window ]]; then
    if (( lock_ms > 6500 )); then ok "$label: mapping a window fails the 6.5 s lock deadline (t=${lock_ms}ms)"; else fail "$label: mapping a window must delay the lock past 6.5 s (t=${lock_ms}ms)"; fi
  elif (( lock_ms >= 4500 && lock_ms <= 6500 )); then
    ok "$label: the 5 s lock stays within 4.5..6.5 s (t=${lock_ms}ms)"
  else
    fail "$label: the 5 s lock stays within 4.5..6.5 s (t=${lock_ms}ms)"
  fi
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
set_lock_seconds 5
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
idle_start "window mapping control"
measure_idle_order "control window restarts idle" yes window
release "screensaver window mapping control"
set_lock_seconds 5
set_screensaver '{"idleEnabled": true, "idleSeconds": 6}'
expect "reload for lock-before-screensaver control" ok ipc shell reloadConfig
expect_poll "the record warns when the lock time is below the screensaver" '["warning", "Lock follows at 5 s"]' lock_order
idle_start "lock-before-screensaver control"
measure_idle_order "control lock before screensaver" no
release "screensaver lock-before-screensaver control"
set_lock_seconds 5
set_screensaver '{"idleEnabled": true, "idleSeconds": 2}'
expect "reload for dismissal before lock" ok ipc shell reloadConfig
idle_start "dismissal before lock"
expect_poll "dismissal maps cover before lock" "$(output_count)" cover_count
while (( $(ms_since_idle) < 3000 )); do sleep 0.1; done
type_keys -k Escape || fail "typing Escape before the lock failed"
expect_poll "dismissal removed cover" 0 layer_count vgs:cover
while (( $(ms_since_idle) < 6500 )); do sleep 0.1; done
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
