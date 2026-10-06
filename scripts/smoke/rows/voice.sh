# Voice uses a stub voxtype and a stub voxtype-audio-bridge on PATH, never
# the host commands. The row enables the plugin, reads its status and bar
# widget, sends its toggle and hold keys through the nested virtual-keyboard
# helper, reads setup offered while the stub model is missing and withheld
# when the stub reports it installed, then disables the plugin and checks its
# shortcuts, its status child and its bridge child are gone. Without
# voxtype, the openTui IPC function, the launcher's route, raises the
# Voice requirement notice in place of Configure and opens no script, the
# notice drawing voxtype and its bridge under the one package of both; its
# control is a disposable manifest copy whose Configure declares no
# `requires`, which launches the script with no notice. Set up on the
# Settings page raises the same notice in place of its script. The Voice
# page's Setup section reads Voice's setup state: without voxtype the
# missing requirement with its step first and primary, once set up Ready
# with voxtype's version and the model and Set up again last and
# secondary. Without voxtype, Configure and Choose model, whose `requires`
# name it, draw disabled with a reason that names it, and every screen is
# active once it is found. Its controls are a disposable manifest copy whose
# setup entry is in no Setup group and offers no setup screen and whose
# Configure declares no `requires`, and a stopped service planted on the
# systemctl stand-in. Install hands the terminal voxtype-bin through the AUR helper,
# the row puts the stubs back as the package step would, and the scan after
# the run closes the notice and opens Set up on its own; the stubs then
# report the model and the service in place, a finished Set up shows one
# Voice toast, and the toggle shortcut runs a test dictation. Its control: Not now on that notice drops the Set up, so
# no setup TUI opens once a scan finds voxtype. A stand-in bin/vgshell-pkg
# answers detection with pacman and paru, whatever the host runs, for
# that part alone. The key delivery
# uses physical code overrides for the row, so the helper reaches the same
# generated bind path that hold-shortcuts.sh exercises. The device
# stand-in systemctl answers the service probe from a planted reply. It
# closes its client window and puts back the shell.json and the pointer
# position it found: its Settings clicks leave the pointer over the centre,
# where a later row's requirement notice would keep the keyboard.
# The on-screen display: the stub status stream follows a file the row
# appends states to, and the stub bridge prints the bridge's frames, and a
# disconnected line on request. The row reads the layer presented on the
# focused output only while recording or transcribing, under the plasma and
# ring settings, unmapped at idle, at stopped and under `osd: off`; a key
# typed and a click under the orb reach the focused client; the bridge
# child is the stand-in, runs only while the display shows, starts again a
# second after it exits and goes with a disable while recording; a status
# follower that exits unmaps the display and starts again; the orb rests
# cool, warms while recording and starts again from rest on a disconnected
# line; at motion scale 0 the shown orb presents no frame for two seconds.
# Three disposable copies, an Osd.qml whose `shown` ignores the state, an
# Osd.qml with a full input mask and a Plasma.qml whose driver ignores the
# motion scale, each fail the assertion they break. Every window, output,
# setting, theme and copy the display part changes is put back; it reuses
# the Voice client above. States and frames poll once per IPC round trip;
# no latency budget is claimed.
# inputs: shell/plugins/vgs.voice/* shell/plugins/vgs.voice/shaders/* shell/Ui/feedback/VoiceOrb.qml shell/Ui/feedback/shaders/* shell/Core/Layers.qml shell/Hosts/LayerHost.qml shell/Hosts/OverlaySurface.qml shell/Core/ShortcutRegistry.qml shell/Core/HyprlandLayer.js shell/Core/PluginStatus.qml shell/Core/TuiRunner.qml shell/Core/Notices.qml shell/Hosts/NoticeHost.qml shell/Ui/feedback/Badge.qml shell/Ui/foundation/Divider.qml shell/Core/PluginLogic.js shell/Core/PackageManagers.js bin/vgshell-pkg bin/vgshell-tui shell/plugins/vgs.settings/* scripts/smoke/keyboard/* scripts/smoke/toplevel/* scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail

voice_log="$sandbox/voice-record.log"
voice_status_pid="$sandbox/voice-status.pid"
voice_installed="$sandbox/voice-model-installed"
voice_setpriv_log="$sandbox/voice-setpriv.log"
voice_states="$sandbox/voice-states"
voice_status_hold="$sandbox/voice-status-hold"
voice_bridge_log="$sandbox/voice-bridge.log"
voice_bridge_drop="$sandbox/voice-bridge-drop"
voice_theme="$home/.config/vgshell/theme.json"
voice_stub="$shim/voxtype"
voice_bridge_stub="$shim/voxtype-audio-bridge"
printf '%s\n' '{"state":"recording","backend":"ONNX CPU","device":"default","model":"parakeet-tdt-0.6b-v3"}' >"$voice_states"
: >"$voice_bridge_log"
cat >"$voice_stub" <<EOF_STUB
#!/usr/bin/env bash
case "\$*" in
  'status --follow --extended --format json')
    printf '%s\n' "\$\$" >"$voice_status_pid"
    [[ -e "$voice_status_hold" ]] && exec sleep infinity
    exec tail -n +1 -f "$voice_states"
    ;;
  'record toggle'|'record start'|'record stop') printf '%s\n' "\$*" >>"$voice_log" ;;
  '--version') printf '%s\n' 'voxtype 1.1.0' ;;
  'config get engine --json') printf '%s\n' '{"value":"parakeet"}' ;;
  'config get parakeet.model --json') printf '%s\n' '{"value":"parakeet-tdt-0.6b-v3"}' ;;
  'info models --json')
    if [[ -e "$voice_installed" ]]; then
      printf '%s\n' '{"engines":{"parakeet":{"models":[{"name":"parakeet-tdt-0.6b-v3","installed":true,"downloadable":true,"download_arg":"parakeet-tdt-0.6b-v3"}],"default":"parakeet-tdt-0.6b-v3"}},"verified":true}'
    else
      printf '%s\n' '{"engines":{"parakeet":{"models":[{"name":"parakeet-tdt-0.6b-v3","installed":false,"downloadable":true,"download_arg":"parakeet-tdt-0.6b-v3"}],"default":"parakeet-tdt-0.6b-v3"}},"verified":true}'
    fi
    ;;
  'info engines --json') printf '%s\n' '[{"name":"whisper","compiled":true,"active":false},{"name":"parakeet","compiled":true,"active":true}]' ;;
  *) ;;
esac
EOF_STUB
chmod 755 "$voice_stub"
# The bridge's protocol: a connected line, then one frame each 50 ms, and a
# disconnected line once the row asks for it.
cat >"$voice_bridge_stub" <<EOF_BRIDGE
#!/usr/bin/env bash
printf '%s %s\n' "\$\$" "\$(date +%s%3N)" >>"$voice_bridge_log"
printf '%s\n' '{"status":"connected"}'
trap 'exit 0' TERM
while :; do
  if [[ -e "$voice_bridge_drop" ]]; then
    rm -f -- "$voice_bridge_drop"
    printf '%s\n' '{"status":"disconnected"}'
  fi
  printf '{"peak":0.42,"rms":0.18,"vad":1,"ts_ms":%s}\n' "\$(date +%s%3N)"
  sleep 0.05
done
EOF_BRIDGE
chmod 755 "$voice_bridge_stub"
# Copies the package step puts back once the row has removed both stubs.
cp -- "$voice_stub" "$sandbox/voice-voxtype.stub"
cp -- "$voice_bridge_stub" "$sandbox/voice-bridge.stub"
device_reply systemctl 0 enabled --user is-enabled voxtype
device_reply systemctl 0 active --user is-active voxtype
cat >"$shim/setpriv" <<'EOF_SETPRIV'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"__VOICE_SETPRIV_LOG__"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --) shift; exec "$@" ;;
    --pdeathsig) shift 2 ;;
    *) shift ;;
  esac
done
EOF_SETPRIV
python3 - "$shim/setpriv" "$voice_setpriv_log" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
path.write_text(path.read_text().replace("__VOICE_SETPRIV_LOG__", sys.argv[2]))
PY
chmod 755 "$shim/setpriv"
: >"$voice_log"

voice_shortcuts() { hypr globalshortcuts | grep -c 'vgs.voice:' || true; }
voice_set_state() { printf '{"state":"%s"}\n' "$1" >>"$voice_states"; }
voice_set_osd() { # MODE, or default to drop the row's setting
  python3 - "$home/.config/vgshell/shell.json" "$1" <<'PY'
import json, os, sys
path, mode = sys.argv[1:]
config = json.load(open(path))
row = next(r for r in config["plugins"] if isinstance(r, dict) and r.get("id") == "vgs.voice")
if mode == "default":
    row.pop("osd", None)
else:
    row["osd"] = mode
with open(path + ".next", "w") as f:
    json.dump(config, f, indent=2)
os.replace(path + ".next", path)
PY
  ipc shell reloadConfig
}
voice_focused_output() { hypr -j monitors | py_reply 'import json,sys; print(next(m["name"] for m in json.load(sys.stdin) if m["focused"]))'; }
# The display as the host and the compositor hold it: presented, one copy
# mapped on the compositor's focused output and the compositor's layer
# count one above the row's baseline; unmapped, no copy requesting or
# holding a map and the count at the baseline; unregistered, no copy on
# some screen.
voice_osd() {
  local rows focused layers
  rows="$(ipc smoke layerWindows vgs.voice)" && focused="$(voice_focused_output)" && layers="$(layer_count vgs:layer)" || return 1
  py_reply '
import json,sys
rows=json.load(sys.stdin); focused,layers,base,screens=sys.argv[1],int(sys.argv[2]),int(sys.argv[3]),int(sys.argv[4])
if len(rows)!=screens: print("unregistered"); sys.exit()
mapped=[r for r in rows if r["shown"] or r["visible"]]
if not mapped and layers==base: print("unmapped"); sys.exit()
ok=(len(mapped)==1 and mapped[0]["screen"]==focused and mapped[0]["visible"] and mapped[0]["presented"]
    and mapped[0]["width"]>0 and layers==base+1)
print("presented" if ok else "wrong: layers=%d %s" % (layers, json.dumps(mapped)))
' "$focused" "$layers" "$voice_layers_base" "$(hypr -j monitors | py_reply 'import json,sys; print(len(json.load(sys.stdin)))')" <<<"$rows"
}
# Which orb the shown copy draws: plasma or ring.
voice_osd_drawn() {
  local plasma ring
  plasma="$(ipc smoke layerItemsWith vgs.voice Plasma active true)" && ring="$(ipc smoke layerItemsWith vgs.voice VoiceOrb active true)" || return 1
  echo "plasma=$plasma ring=$ring"
}
# Only the copy on the compositor's focused output, whichever that is,
# requests or holds a map.
voice_osd_focused() {
  local rows focused
  rows="$(ipc smoke layerWindows vgs.voice)" && focused="$(voice_focused_output)" || return 1
  py_reply '
import json,sys
rows=json.load(sys.stdin); focused=sys.argv[1]
ok=any(r["screen"]==focused and r["shown"] for r in rows) and all(r["screen"]==focused for r in rows if r["shown"] or r["visible"])
print("focused" if ok else "wrong-output")
' "$focused" <<<"$rows"
}
# Bridge children of the shell: the host's own command by its executable,
# and the stand-in by any argument naming voxtype-audio-bridge, the bare
# name the service hands setpriv and env or the stub's path; shell=gone
# when the shell itself is gone, so no absence reads true against it.
voice_bridges() {
  python3 - "$shell_pid" <<'PY'
import pathlib, sys
if not pathlib.Path(f"/proc/{sys.argv[1]}").is_dir():
    print("shell=gone")
    sys.exit()
pending, stand_in, host = [int(sys.argv[1])], 0, 0
while pending:
    pid = pending.pop()
    try:
        pending.extend(map(int, pathlib.Path(f"/proc/{pid}/task/{pid}/children").read_text().split()))
        args = pathlib.Path(f"/proc/{pid}/cmdline").read_bytes().decode(errors="replace").split("\0")
        executable = pathlib.Path(f"/proc/{pid}/exe").resolve().name
    except (FileNotFoundError, ProcessLookupError):
        continue
    if executable == "voxtype-audio-bridge":
        host += 1
    elif any(arg.endswith("voxtype-audio-bridge") for arg in args):
        stand_in += 1
print(f"stand-in={stand_in} host={host}")
PY
}
voice_level_flowing() { ipc smoke readInstance service vgs.voice level | py_reply 'import json,sys; print("flowing" if json.load(sys.stdin) > 0 else "still")'; }
voice_client_events() { local status=0; grep -cE -- "$1" "$sandbox/voice-client.log" || status=$?; [[ $status -le 1 ]]; }
# voice_osd_click_begin clicks the centre of the drawn orb, voice_osd_orb,
# and keeps the client's press and release counts it expects after;
# voice_osd_click_result reads ok once the client below has counted both.
voice_osd_click_begin() {
  local box x y down up
  box="$(control_box vgs:layer vgs.voice "$voice_osd_orb" visible true)" || return 1
  [[ $box == \[* ]] || { echo "voice: osd-orb=absent type=$voice_osd_orb" >&2; return 1; }
  read -r x y < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(round(x+w/2),round(y+h/2))' "$box")
  down="$(voice_client_events '^button 272 pressed$')" && up="$(voice_client_events '^button 272 released$')" || return 1
  voice_click_before="$down $up"
  voice_click_want="$((down + 1)) $((up + 1))"
  hover "$((x - 1))" "$y" && click "$x" "$y"
}
voice_osd_click_result() {
  local got
  got="$(voice_client_events '^button 272 pressed$') $(voice_client_events '^button 272 released$')" || return 1
  [[ $got == "$voice_click_want" ]] && echo ok || echo "got=[$got] want=[$voice_click_want]"
}
voice_client_counts() { echo "$(voice_client_events '^button 272 pressed$') $(voice_client_events '^button 272 released$')"; }
voice_osd_click_assertion() {
  (failures=0 behaviour_failures=0
   expect_poll "a click under the orb reaches the client" ok voice_osd_click_result >"$sandbox/voice-osd-click-assertion.log"
   echo "$failures")
}
# The rim colour of the plasma copy on the compositor's first output, as
# #rrggbb.
voice_plasma_rim() {
  ipc smoke layerItems vgs.voice QQuickShaderEffect uColA | py_reply '
import json,sys
rows=[values["uColA"] for screen,box,values in json.load(sys.stdin) if values.get("uColA") is not None]
print("#"+str(rows[0]).lower()[-6:] if rows else "absent")
'
}
# The plasma's clock, uTime, on the shown copy, in seconds.
voice_plasma_clock() {
  ipc smoke layerItems vgs.voice QQuickShaderEffect uTime,visible | py_reply '
import json,sys
rows=[values["uTime"] for screen,box,values in json.load(sys.stdin) if values.get("uTime") is not None and values["visible"]]
print(rows[0] if len(rows)==1 else "copies=%d"%len(rows))
'
}
voice_plasma_running() { local t; t="$(voice_plasma_clock)" || return 1; python3 -c 'import sys; print("running" if float(sys.argv[1]) > 1 else "starting")' "$t" 2>/dev/null || echo "$t"; }
voice_plasma_rewound() { local t; t="$(voice_plasma_clock)" || return 1; python3 -c 'import sys; print("rewound" if float(sys.argv[1]) < float(sys.argv[2]) else "ahead")' "$t" "$voice_clock_before" 2>/dev/null || echo "$t"; }
# The display's own window, read through the probe's layer frame watcher:
# advancing when it presents a frame within 0.2 s, quiet when it presents
# none over a two-second window that starts 0.2 s after the call.
voice_frames_advancing() {
  local before after
  before="$(ipc smoke layerFrames)" || return 1
  sleep 0.2
  after="$(ipc smoke layerFrames)" || return 1
  [[ $before =~ ^[0-9]+$ && $after =~ ^[0-9]+$ ]] || { echo "unreadable before=$before after=$after"; return; }
  if ((after > before)); then echo advancing; else echo stopped; fi
}
voice_frames_quiet() {
  local before after
  sleep 0.2
  before="$(ipc smoke layerFrames)" || return 1
  sleep 2
  after="$(ipc smoke layerFrames)" || return 1
  [[ $before =~ ^[0-9]+$ && $after =~ ^[0-9]+$ ]] || { echo "unreadable before=$before after=$after"; return; }
  if ((after == before)); then echo quiet; else echo swapped; fi
}
# Motion scale 0 through the user's theme file, and the file as it was.
voice_motion_still() {
  if [[ -e $voice_theme ]]; then cp -- "$voice_theme" "$sandbox/voice-theme-before"; else rm -f -- "$sandbox/voice-theme-before"; fi
  printf '%s\n' '{"schemaVersion":1,"name":"still","tokens":{"motion":{"scale":0}}}' >"$voice_theme.tmp"
  mv -T -- "$voice_theme.tmp" "$voice_theme"
}
voice_motion_restore() {
  if [[ -e $sandbox/voice-theme-before ]]; then mv -T -- "$sandbox/voice-theme-before" "$voice_theme"; else rm -f -- "$voice_theme"; fi
}
# The orb watched for two seconds at motion scale 0 while transcribing; the
# theme and the watcher are put back whatever the reading.
voice_still_frames() { # LABEL WANT
  voice_set_state transcribing
  expect_poll "$1: transcribing presents the display" presented voice_osd
  expect "$1: the display's window is watched" ok ipc smoke watchLayerFrames vgs.voice
  expect_poll "$1: the transcribing orb presents frames" advancing voice_frames_advancing
  voice_motion_still
  expect_poll "$1: zero motion reaches the shell" 0 ipc smoke themeValue motion.scale
  expect "$1" "$2" voice_frames_quiet
  voice_motion_restore
  expect_poll "$1: the motion scale is restored" 1 ipc smoke themeValue motion.scale
  expect "$1: the window watcher is released" ok ipc smoke dropLayerFrames
  voice_set_state idle
  expect_poll "$1: idle unmaps the display" unmapped voice_osd
}
voice_status_restarted() {
  local pid
  pid="$(cat "$voice_status_pid")"
  [[ $pid != "$voice_follower" && -d /proc/$pid ]] && echo restarted || echo "pid=$pid"
}
voice_osd_copies() { ipc smoke layerWindows vgs.voice | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
voice_osd_idle_assertion() {
  (failures=0 behaviour_failures=0
   expect_poll "idle maps no on-screen display" unmapped voice_osd >"$sandbox/voice-osd-idle-assertion.log"
   echo "$failures")
}
# The stand-in bridge killed, then the next one's start read from its log:
# restarted when it came a second or more after the kill.
voice_bridge_restart() {
  local pid killed next started
  pid="$(tail -n 1 "$voice_bridge_log" | cut -d' ' -f1)"
  [[ $pid =~ ^[0-9]+$ ]] || { echo "no-bridge"; return; }
  killed="$(date +%s%3N)"
  kill -TERM "$pid"
  for _ in $(seq 1 50); do
    read -r next started < <(tail -n 1 "$voice_bridge_log")
    if [[ $next != "$pid" ]]; then
      (( started - killed >= 1000 )) && echo restarted || echo "early gap=$((started - killed))"
      return
    fi
    sleep 0.1
  done
  echo "not-restarted"
}
voice_set_keys() {
  python3 - "$home/.config/vgshell/shell.json" <<'PY'
import json, os, sys
path = sys.argv[1]
config = json.load(open(path))
rows = config.setdefault("plugins", [])
row = None
for index, candidate in enumerate(rows):
    if candidate == "vgs.voice":
        row = {"id": "vgs.voice"}
        rows[index] = row
        break
    if isinstance(candidate, dict) and candidate.get("id") == "vgs.voice":
        row = candidate
        break
if row is None:
    row = {"id": "vgs.voice"}
    rows.append(row)
row["keys"] = {"toggle": "SUPER+CTRL+code:53", "talk": "code:75"}
with open(path + ".next", "w") as f:
    json.dump(config, f, indent=2)
os.replace(path + ".next", path)
PY
}
voice_requirement() { ipc shell listPlugins | py_reply 'import json,sys; p=[p for p in json.load(sys.stdin)["plugins"] if p["id"]=="vgs.voice"][0]; print([r["state"] for r in p["requirements"] if r["name"]==sys.argv[1]][0])' "$1"; }
voice_status_alive() { local pid; [[ -f $voice_status_pid ]] || { echo absent; return; }; pid="$(cat "$voice_status_pid")"; python3 - "$pid" <<'PY'
import pathlib, sys
pid = sys.argv[1]
print('alive' if pid.isdigit() and pathlib.Path('/proc', pid).exists() else 'gone')
PY
}
voice_setup_offered() { ipc smoke readInstance service vgs.voice setupValue | py_reply 'import json,sys; v=json.load(sys.stdin); print(v.get("action"))'; }
voice_dictation() { ipc smoke readInstance "$(bar_key)" vgs.voice dictation; }
# The bar mic's recording tone beside a shell token, the badge accent
# foreground unless another is named, each as #rrggbb: same while they
# match.
voice_mic_tone() { # [TOKEN]
  local tone want
  tone="$(ipc smoke readInstance "$(bar_key)" vgs.voice itemTone)" && want="$(ipc smoke themeValue "${1:-badge.tone.accent.foreground}")" || return 1
  python3 -c '
import json,sys
# A colour property reads as its channels, a token as its #aarrggbb name.
def rgb(text):
    value=json.loads(text)
    if isinstance(value,dict) and all(k in value for k in "rgb"):
        return "#"+"".join("%02x"%round(value[k]*255) for k in "rgb")
    value=str(value).lower()
    return "#"+value[-6:] if len(value) in (7, 9) and value.startswith("#") else "unreadable:"+value
got,want=rgb(sys.argv[1]),rgb(sys.argv[2])
print("same" if got==want and not got.startswith("unreadable") else "got=%s want=%s"%(got,want))
' "$tone" "$want"
}
voice_mic_tone_control() {
  local got
  got="$(voice_mic_tone badge.tone.info.foreground)" || return 1
  [[ $got == got=* ]] && echo differs || echo "$got"
}
voice_status_value() { ipc shell lent | py_reply 'import json,sys; r=json.load(sys.stdin)["status"].get("vgs.voice"); print("absent" if r is None else json.dumps(r["keys"]))'; }
voice_drawn_status() { ipc smoke itemTexts window vgs.settings StatusRow | py_reply 'import json,sys; rows=[row for row in json.load(sys.stdin) if row and row[0] in ("voxtype", "Setup")]; print(json.dumps(rows))'; }
voice_requirement_drawn() { ipc smoke itemTexts window vgs.settings RequirementRow | py_reply 'import json,sys; rows=[row for row in json.load(sys.stdin) if row and row[0] == "voxtype"]; print(json.dumps(rows[0] if rows else []))'; }
voice_ensure_hypr_wired() {
  local phase wires
  phase="$(hypr_consent_phase)" || return
  wires="$(hypr_wire_count)" || return
  if [[ $phase == wired || $wires == 1 ]]; then
    ok "Voice row finds Hyprland consent already wired"
    return 0
  fi
  hypr_consent_connect "Voice row answers Hyprland consent"
}
voice_start_keyboard() {
  voice_keyboard_log="$sandbox/voice-keyboard.log"
  voice_fifo="$sandbox/voice-keyboard.fifo"
  mkfifo "$voice_fifo"
  exec {voice_fd}<>"$voice_fifo"
  spawn "$voice_keyboard_log" "${shell_env[@]}" "$sandbox/keyboard" "$voice_fifo" us ""
  voice_keyboard_pid="$spawn_pid"
  expect_poll "the Voice keyboard connects to the nested seat" 1 log_lines '^ready$' "$voice_keyboard_log"
  voice_syncs=0
}
voice_send() { printf '%s\n' "$@" >&"$voice_fd"; }
voice_sync() {
  voice_syncs=$((voice_syncs + 1))
  voice_send sync
  expect_poll "$1" "$voice_syncs" log_lines '^sync$' "$voice_keyboard_log"
}
voice_stop_keyboard() {
  voice_send quit
  exec {voice_fd}>&-
  local status=0
  wait "$voice_keyboard_pid" || status=$?
  expect "the Voice keyboard exits with all keys released" 0 printf '%s\n' "$status"
}
voice_toggle_key() { voice_send "down 133" "down 37" "down 53" "up 53" "up 37" "up 133"; }
voice_f9_press() { voice_send "down 75"; }
voice_f9_release() { voice_send "up 75"; }
voice_new_lines() {
  tail -n +$((before + 1)) "$voice_log" | paste -sd '|' -
}
voice_toggle_only() {
  local got
  got="$(voice_new_lines)"
  [[ $got == "record toggle" ]] && echo ok || echo "$got"
}
voice_press_only() {
  local got
  got="$(voice_new_lines)"
  [[ $got == "record start" ]] && echo ok || echo "$got"
}
voice_hold_pair() {
  local got
  got="$(voice_new_lines)"
  [[ $got == "record start|record stop" ]] && echo ok || echo "$got"
}

voice_saved_config="$sandbox/shell-before-voice.json"
voice_pointer="$(hypr -j cursorpos | py_reply 'import json,sys; p=json.load(sys.stdin); print(p["x"], p["y"])')"
cp -- "$home/.config/vgshell/shell.json" "$voice_saved_config"
voice_ensure_hypr_wired
hypr_lua_save voice
printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = false } })' >>"$home/.config/hypr/hyprland.lua"
expect "Voice key resolution is reloaded" ok hypr reload config-only
rescan "rescan discovers the Voice stub"
expect_poll "the Voice plugin is known" True plugin_known vgs.voice
expect_poll "the Voice voxtype requirement is present" present voice_requirement voxtype
expect_poll "the Voice bridge requirement is present" present voice_requirement voxtype-audio-bridge
voice_layers_base="$(layer_count vgs:layer)" || fail "the layer count before Voice is unreadable"
expect "enabling Voice is allowed" ok ipc shell setPluginEnabled vgs.voice true
expect "placing Voice in the bar is allowed" ok ipc shell setPluginPlaced vgs.voice true
voice_set_keys
expect "Voice physical key overrides are reloaded" ok ipc shell reloadConfig
expect "Hyprland reloads Voice physical key overrides" ok hypr reload config-only
expect_poll "Voice builds" True record_exists vgs.voice
expect_poll "Voice reads the physical key overrides" '{"toggle":"SUPER+CTRL+code:53","tap":null,"talk":"code:75"}' ipc smoke readInstance service vgs.voice shortcutKeys
expect_poll "Voice sees voxtype present" true ipc smoke readInstance service vgs.voice voxtypePresent
expect_poll "Voice starts its status process" true ipc smoke readInstance service vgs.voice statusRunning
expect_poll "Voice registers its three shortcuts and the release companion" 4 voice_shortcuts
expect_poll "the Voice status child starts" true ipc smoke readInstance service vgs.voice statusRunning
expect_poll "the status stream reaches plugin status" '["dictation", "model", "setup", "voxtype"]' voice_status_value
expect_poll "the recording state reaches the bar widget" '"recording"' voice_dictation
expect "the recording mic draws the shell's badge accent" same voice_mic_tone
expect "control: the same reader tells the mic from the info tone" differs voice_mic_tone_control
expect_poll "the recording state reaches dictation status" '"recording"' ipc smoke readInstance service vgs.voice dictationStatus
expect_poll "Set up is offered while the model is missing" True voice_setup_offered

open_toplevel "$sandbox/voice-client.log" smoke.voice-client "Voice client"
voice_client_pid="$toplevel_pid"
expect_poll "the Voice client has keyboard focus" '["smoke.voice-client", "Voice client"]' active_window
voice_start_keyboard
before="$(wc -l <"$voice_log")"
voice_toggle_key
voice_sync "the Voice keyboard delivered the toggle keys"
expect_poll "the typed toggle key runs only voxtype record toggle" ok voice_toggle_only
before="$(wc -l <"$voice_log")"
voice_f9_press
voice_sync "the Voice keyboard delivered F9 press"
expect_poll "F9 press logs start and no stop" ok voice_press_only
voice_f9_release
voice_sync "the Voice keyboard delivered F9 release"
expect_poll "held F9 runs start then stop through release" ok voice_hold_pair

# The on-screen display, with the stand-in status at recording.
voice_osd_orb=Plasma
expected_errors+=('voice: bridge exited code=0 status=0' 'voice: status exited ')
expect_poll "recording presents the display on the focused output" presented voice_osd
expect_poll "the recording orb has faded to the warm palette" "#5a52e8" voice_plasma_rim
expect "the plasma setting draws the plasma orb" "plasma=1 ring=0" voice_osd_drawn
expect_poll "the display runs one bridge child, the stand-in" "stand-in=1 host=0" voice_bridges
expect_poll "the stand-in's frames reach the service's level" flowing voice_level_flowing
voice_client_keys="$(voice_client_events '^key [0-9]+ released$')" || fail "the Voice client's key count is unreadable"
type_keys z || fail "typing while the display is shown failed"
expect_poll "a key typed while the display is shown reaches the focused client" "$((voice_client_keys + 1))" voice_client_events '^key [0-9]+ released$'
expect "the display takes no keyboard focus" '["smoke.voice-client", "Voice client"]' active_window
voice_osd_click_begin || fail "the click under the plasma orb could not be made"
expect_poll "a click under the plasma orb reaches the client with press and release" ok voice_osd_click_result
expect_poll "the plasma's clock runs while recording" running voice_plasma_running
voice_clock_before="$(voice_plasma_clock)" || fail "the plasma's clock is unreadable"
touch -- "$voice_bridge_drop"
expect_poll "the bridge's disconnected line starts the orb again from rest" rewound voice_plasma_rewound
expect "a bridge that exits starts again a second later" restarted voice_bridge_restart
expect_poll "the restarted bridge is the one stand-in child" "stand-in=1 host=0" voice_bridges
voice_set_state transcribing
expect_poll "the transcribing state reaches the service" '"transcribing"' ipc smoke readInstance service vgs.voice dictation
expect_poll "transcribing keeps the display presented" presented voice_osd
expect "transcribing keeps the bridge child" "stand-in=1 host=0" voice_bridges
voice_set_state idle
expect_poll "idle unmaps the display" unmapped voice_osd
expect_poll "idle stops the bridge child" "stand-in=0 host=0" voice_bridges
expect_poll "the orb rests in the cool palette" "#4a72e0" voice_plasma_rim
voice_set_state stopped
expect_poll "the stopped state reaches the service" '"stopped"' ipc smoke readInstance service vgs.voice dictation
# A wrong map or bridge would follow the state within the second; the
# recording reads above find both on their first poll.
sleep 1
expect "stopped maps no display" unmapped voice_osd
expect "stopped runs no bridge child" "stand-in=0 host=0" voice_bridges
voice_still_frames "zero motion presents no display frame over two seconds" quiet
voice_set_state recording
expect_poll "recording presents the display before the follower exits" presented voice_osd
touch -- "$voice_status_hold"
voice_follower="$(cat "$voice_status_pid")"
kill -TERM "$voice_follower"
expect_poll "a status follower that exits unmaps the display" unmapped voice_osd
expect_poll "a status follower that exits stops the bridge child" "stand-in=0 host=0" voice_bridges
expect_poll "the status follower starts again" restarted voice_status_restarted
rm -f -- "$voice_status_hold"
kill -TERM "$(cat "$voice_status_pid")"
expect_poll "the next follower reads recording again" presented voice_osd
voice_set_state idle
expect_poll "idle unmaps the display after the follower's return" unmapped voice_osd
expect "an osd setting of off is written" ok voice_set_osd off
expect_poll "the service reads osd off" '"off"' ipc smoke readInstance service vgs.voice osdMode
voice_set_state recording
expect_poll "recording under osd off reaches the service" '"recording"' ipc smoke readInstance service vgs.voice dictation
expect "osd off maps no display while recording" unmapped voice_osd
expect "osd off runs no bridge child" "stand-in=0 host=0" voice_bridges
expect "an osd setting of ring is written" ok voice_set_osd ring
expect_poll "the ring setting presents the display while recording" presented voice_osd
expect_poll "the ring setting draws VoiceOrb" "plasma=0 ring=1" voice_osd_drawn
expect_poll "the ring display runs the stand-in bridge" "stand-in=1 host=0" voice_bridges
voice_osd_orb=VoiceOrb
voice_osd_click_begin || fail "the click under the ring could not be made"
expect_poll "a click under the ring reaches the client with press and release" ok voice_osd_click_result
expect "the default osd setting is restored" ok voice_set_osd default
expect_poll "the default draws the plasma orb again" "plasma=1 ring=0" voice_osd_drawn
voice_osd_orb=Plasma
# Monitor focus held while the second output comes and goes, as sound.sh
# holds it: under Hyprland's default mouse focus the add and the remove move
# the cursor and the focus that the later rows' selectors and pads start from.
printf '%s\n' 'hl.config({ input = { follow_mouse = 0 }, cursor = { no_warps = true }, misc = { mouse_move_focuses_monitor = false } })' >>"$home/.config/hypr/hyprland.lua"
expect "the nested instance holds monitor focus for the second output" ok hypr reload config-only
expect "the nested compositor adds a second output for Voice" ok hypr output create headless SMOKE-VOICE
expect_poll "the second output gets its own display copy" 2 voice_osd_copies
expect_poll "only the focused output shows the display" focused voice_osd_focused
expect "the nested compositor removes the second output" ok hypr output remove SMOKE-VOICE
expect_poll "the display is presented on the one output again" presented voice_osd
voice_set_state idle
expect_poll "idle unmaps the display again" unmapped voice_osd

# Controls: disposable copies of Osd.qml and Plasma.qml, each breaking one
# rule; the same assertion must fail. Each copy is put back before the
# next.
for voice_osd_mutant in idle mask motion; do
  voice_osd_file="$repo/shell/plugins/vgs.voice/Osd.qml"
  [[ $voice_osd_mutant != motion ]] || voice_osd_file="$repo/shell/plugins/vgs.voice/Plasma.qml"
  cp -- "$voice_osd_file" "$sandbox/voice-osd-before"
  expect "disabling Voice for the $voice_osd_mutant control is allowed" ok ipc shell setPluginEnabled vgs.voice false
  python3 - "$voice_osd_file" "$voice_osd_mutant" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); assert not p.is_symlink()
needle, replacement = {
    "idle": ("service !== null && service.osdActive && screen !== null", "service !== null && screen !== null"),
    "mask": ("property var inputItems: []", "property var inputItems: []\n    property bool inputAll: true"),
    "motion": ("root.active && root.visible && root.look.motion.scale > 0", "root.active && root.visible"),
}[sys.argv[2]]
s = p.read_text(); assert s.count(needle) == 1
changed = s.replace(needle, replacement); assert changed != s
p.write_text(changed)
PY
  rescan "the Voice $voice_osd_mutant control copy is scanned"
  expect "enabling Voice for the $voice_osd_mutant control is allowed" ok ipc shell setPluginEnabled vgs.voice true
  expect_poll "Voice builds for the $voice_osd_mutant control" True record_exists vgs.voice
  case "$voice_osd_mutant" in
    idle)
      expect_poll "control: the idle state reaches the copy" '"idle"' ipc smoke readInstance service vgs.voice dictation
      expect_poll "control: the copy that ignores the state is presented at idle" presented voice_osd
      expect "control: a shown that ignores the state fails the idle assertion" 1 voice_osd_idle_assertion ;;
    mask)
      voice_set_state recording
      expect_poll "control: the full-mask copy is presented" presented voice_osd
      voice_osd_click_begin || fail "the click under the full-mask copy could not be made"
      expect "control: a full input mask fails the click assertion" 1 voice_osd_click_assertion
      expect "control: the full mask leaves the client's press and release counts unchanged" "$voice_click_before" voice_client_counts
      voice_set_state idle
      expect_poll "control: the full-mask copy unmaps at idle" unmapped voice_osd ;;
    motion)
      voice_still_frames "control: a driver that ignores the motion scale presents frames at zero motion" swapped ;;
  esac
  expect "disabling Voice after the $voice_osd_mutant control is allowed" ok ipc shell setPluginEnabled vgs.voice false
  cp -- "$sandbox/voice-osd-before" "$voice_osd_file"
done
rescan "the shipped Voice display is scanned again"
expect "enabling Voice after the display controls is allowed" ok ipc shell setPluginEnabled vgs.voice true
expect_poll "Voice builds after the display controls" True record_exists vgs.voice

touch -- "$voice_installed"
rescan "the Voice rescan rereads setup state"
expect_poll "Set up is withheld once the model is installed" False voice_setup_offered
voice_set_state recording
expect_poll "recording before the disable runs the stand-in bridge" "stand-in=1 host=0" voice_bridges
expect "disabling Voice is allowed" ok ipc shell setPluginEnabled vgs.voice false
expect_poll "disabling Voice removes its shortcuts" 0 voice_shortcuts
expect_poll "disabling Voice clears its status" absent voice_status_value
expect_poll "disabling Voice stops the status child" gone voice_status_alive
expect_poll "disabling Voice leaves no bridge child" "stand-in=0 host=0" voice_bridges
voice_stop_keyboard
close_toplevel "$voice_client_pid" "the Voice client exits 0 on SIGTERM"
hypr_lua_restore voice || fail "Voice restores hyprland.lua"
expect "Voice key resolution restore is reloaded" ok hypr reload config-only
rm -f -- "${voice_stub:?}" "${voice_bridge_stub:?}" "${shim:?}/setpriv" "${voice_installed:?}"
device_reply_clear systemctl
rescan "rescan after removing the Voice stubs"
expect_poll "the Voice voxtype requirement is missing after stub removal" missing voice_requirement voxtype
# Detection answers through bin/vgshell-pkg, swapped in whole and put back
# after the install rows.
voice_pkg_real="$sandbox/voice-vgshell-pkg.real"
cp -- "$repo/bin/vgshell-pkg" "$voice_pkg_real"
cat >"$sandbox/voice-vgshell-pkg.stub" <<'EOF_PKG'
#!/usr/bin/env node
if (process.argv[2] === "detect" && process.argv[3] === "--json") {
    process.stdout.write('{"primary":{"id":"pacman","binary":"pacman"},"overlays":[{"id":"aur","binary":"paru"}],"sources":[]}\n');
    process.exit(0);
}
process.stderr.write("vgshell: refused: stub=vgshell-pkg\n");
process.exit(70);
EOF_PKG
chmod 755 "$sandbox/voice-vgshell-pkg.stub"
cp -- "$sandbox/voice-vgshell-pkg.stub" "$repo/bin/vgshell-pkg.next" && mv -T -- "$repo/bin/vgshell-pkg.next" "$repo/bin/vgshell-pkg"
voice_resumes() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["notices"]["resumes"]))'; }
# The notice's entries as [chip, the number of lines under it].
# The toasts Voice shows, shown or waiting; Voice shows none but the one a
# finished Set up raises.
voice_toasts() { ipc shell lent | py_reply 'import json,sys; t=json.load(sys.stdin)["toasts"]; print(sum(r["plugin"] == "vgs.voice" for k in ("visible", "waiting") for r in t[k]))'; }
voice_notice_groups() { ipc smoke noticeDrawn | py_reply 'import json,sys; print(json.dumps([[g[0], len(g[1])] for g in json.load(sys.stdin)["groups"]]))'; }
# The Voice page's Setup section on its Settings tab: its chips as [text,
# tone] and its buttons as [text, variant, enabled, whether its tooltip
# names voxtype], in drawn order.
voice_setup_section() { ipc smoke setupSection window vgs.settings | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps({"chips": d["chips"], "buttons": [[b[0], b[1], b[2], "voxtype" in b[3]] for b in d["buttons"]]}))'; }
# Whether a line of the Setup section holds TEXT.
voice_setup_line() { ipc smoke setupSection window vgs.settings | py_reply 'import json,sys; print(str(any(sys.argv[1] in l for l in json.load(sys.stdin)["lines"])).lower())' "$1"; }
voice_setup_missing='{"chips": [["Requirements missing", "warning"]], "buttons": [["Install requirements", "primary", true, false], ["Configure", "secondary", false, true], ["Choose model", "secondary", false, true]]}'
voice_setup_ready='{"chips": [["Ready", "success"]], "buttons": [["Configure", "secondary", true, false], ["Choose model", "secondary", true, false], ["Set up again", "secondary", true, false]]}'
voice_engine_installed() {
  cp -- "$sandbox/voice-voxtype.stub" "$voice_stub" && cp -- "$sandbox/voice-bridge.stub" "$voice_bridge_stub" && chmod 755 "$voice_stub" "$voice_bridge_stub"
}
voice_engine_removed() { rm -f -- "${voice_stub:?}" "${voice_bridge_stub:?}"; }
voice_notice_escape() { # LABEL
  expect_poll "$1: the notice holds the keyboard" true ipc smoke noticeFocused
  type_keys -k Escape || fail "$1: sending Escape failed"
  expect_poll "$1: Escape closes the notice" null notice_shown
}
voice_asked='["vgs.voice", ["voxtype", "voxtype-audio-bridge"], ["voxtype", "voxtype-audio-bridge"], false]'
# Idle, so the stubs the package step puts back show no recording.
voice_set_state idle
# The service a fresh install leaves, which Voice probes once voxtype is
# back.
device_reply systemctl 1 disabled --user is-enabled voxtype
device_reply systemctl 3 inactive --user is-active voxtype

expect "enabling Voice without voxtype is allowed" ok ipc shell setPluginEnabled vgs.voice true
expect_poll "Voice without voxtype is built" True record_exists vgs.voice

# openTui, the route of the launcher and Dev Tools, judges the screen's
# `requires` as Set up's press does: Configure without voxtype raises the
# same notice and opens no script.
forget_record
expect "openTui of Configure without voxtype is answered" ok ipc shell openTui vgs.voice/configure
expect_poll "openTui of Configure without voxtype raises the Voice notice in place of its script" "$voice_asked" notice_shown
expect "the notice holds the Configure the open asked for" '{"vgs.voice": "configure"}' voice_resumes
expect_poll "the notice draws voxtype and its bridge under the one package that provides both" '[["voxtype-bin", 2]]' voice_notice_groups
expect "no Configure run is asked for while the notice shows" idle key_idle vgs.voice/configure
expect "the terminal is handed no Configure script" absent recorded
voice_notice_escape "the Configure notice"
expect "Not now drops the Configure" '{}' voice_resumes
# Control: a disposable manifest copy whose Configure declares no
# `requires`, voxtype being optional, leaves the judge no command to find
# missing, so the same open launches the script and raises no notice.
voice_manifest="$repo/shell/plugins/vgs.voice/manifest.json"
cp -- "$voice_manifest" "$sandbox/voice-manifest-before"
expect "disabling Voice for the requires control is allowed" ok ipc shell setPluginEnabled vgs.voice false
python3 - "$voice_manifest" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1]); assert not p.is_symlink()
manifest = json.loads(p.read_text())
assert "voxtype" in manifest["tui"]["configure"]["requires"]
assert next(r for r in manifest["requirements"] if r["command"] == "voxtype")["optional"] is True
del manifest["tui"]["configure"]["requires"]
p.write_text(json.dumps(manifest, indent=2) + "\n")
PY
rescan "the Voice requires control copy is scanned"
expect "enabling Voice for the requires control is allowed" ok ipc shell setPluginEnabled vgs.voice true
expect_poll "Voice builds for the requires control" True record_exists vgs.voice
forget_record
expect "control: openTui of the copy's Configure is answered" ok ipc shell openTui vgs.voice/configure
expect_poll "control: a Configure without requires launches its script" "$(words vgs.voice/configure tui/configure.sh)" recorded_tail
expect "control: a Configure without requires raises no notice" null notice_shown
expect_run_end "control: the Configure run ends" vgs.voice/configure
expect "disabling Voice after the requires control is allowed" ok ipc shell setPluginEnabled vgs.voice false
cp -- "$sandbox/voice-manifest-before" "$voice_manifest"
rescan "the shipped Voice manifest is scanned again"
expect "enabling Voice after the requires control is allowed" ok ipc shell setPluginEnabled vgs.voice true
expect_poll "Voice builds after the requires control" True record_exists vgs.voice

settings_page_open vgs.voice
# The Setup section reads Voice's own setup state: without voxtype it names
# the requirement, and the step it offers comes first, primary; Configure
# and Choose model, which need voxtype, take no press and say so on hover.
expect_poll "the Setup section draws the missing requirement, its step first and the screens that need voxtype disabled" "$voice_setup_missing" voice_setup_section
expect "the Setup section's hint names voxtype" true voice_setup_line voxtype
# Control: a disposable manifest copy whose setup entry is in no Setup
# group and offers an install step, which opens no setup screen, and whose
# Configure declares no `requires`, draws no chip, no primary button, and
# Configure active: voxtype is optional, so it then needs nothing missing.
cp -- "$voice_manifest" "$sandbox/voice-manifest-before"
settings_page_close vgs.voice
expect "disabling Voice for the Setup section control is allowed" ok ipc shell setPluginEnabled vgs.voice false
python3 - "$voice_manifest" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1]); assert not p.is_symlink()
manifest = json.loads(p.read_text())
entry = manifest["status"]["setup"]
assert entry["group"] == "Setup" and entry["action"]["tui"] == "setup"
del entry["group"]
entry["action"] = {"label": "Set up", "install": ["voxtype"]}
assert "voxtype" in manifest["tui"]["configure"]["requires"]
del manifest["tui"]["configure"]["requires"]
p.write_text(json.dumps(manifest, indent=2) + "\n")
PY
rescan "the Voice Setup section control copy is scanned"
expect "enabling Voice for the Setup section control is allowed" ok ipc shell setPluginEnabled vgs.voice true
expect_poll "Voice builds for the Setup section control" True record_exists vgs.voice
settings_page_open vgs.voice
expect_poll "control: a setup entry in no group with a step that opens no screen, and a Configure with no requires, draw no chip, no primary button and Configure active" '{"chips": [], "buttons": [["Configure", "secondary", true, false], ["Choose model", "secondary", false, true], ["Set up again", "secondary", false, true]]}' voice_setup_section
settings_page_close vgs.voice
expect "disabling Voice after the Setup section control is allowed" ok ipc shell setPluginEnabled vgs.voice false
cp -- "$sandbox/voice-manifest-before" "$voice_manifest"
rescan "the shipped Voice manifest is scanned again after the Setup section control"
expect "enabling Voice after the Setup section control is allowed" ok ipc shell setPluginEnabled vgs.voice true
expect_poll "Voice builds after the Setup section control" True record_exists vgs.voice
settings_page_open vgs.voice
expect_poll "the Setup section reads the missing requirement again" "$voice_setup_missing" voice_setup_section
settings_details
# Without voxtype, Set up is offered, and the core withholds it behind the
# requirement it needs, naming what is missing.
expect_poll "the Voice page offers Install and Set up's requirements without voxtype" '[["voxtype", "Install\u2026", true], ["setup", "Install requirements", true]]' offered_actions vgs.voice
expect_poll "the Voice status rows name voxtype as missing" '[["voxtype", "Absent", "Voice needs voxtype to capture speech.", "Install\u2026"], ["Setup", "Requirements missing", "voxtype is missing. Install requirements installs it.", "Install requirements"]]' voice_drawn_status
expect_poll "the Voice Requirements row says voxtype is missing" "$(words voxtype "Missing, optional" "Captures speech and inserts dictated text")" voice_requirement_drawn

# Control: Not now on the notice Set up raised drops the Set up, so a scan
# that later finds voxtype opens nothing.
forget_record
expect "Set up without voxtype is answered" ok settings_open_tui vgs.voice setup
expect_poll "Set up without voxtype raises the notice in place of its script" "$voice_asked" notice_shown
expect "the notice holds the Set up the press asked for" '{"vgs.voice": "setup"}' voice_resumes
voice_notice_escape "control: the Set up notice"
expect "control: Not now drops the Set up" '{}' voice_resumes
voice_engine_installed
rescan "control: a scan finds voxtype after Not now"
expect_poll "control: voxtype is present after Not now" present voice_requirement voxtype
expect "control: no setup TUI is asked for after Not now" idle key_idle vgs.voice/setup
expect "control: the terminal is handed nothing after Not now" absent recorded
voice_engine_removed
rescan "control: voxtype is removed again"
expect_poll "control: voxtype is missing again" missing voice_requirement voxtype

# One press of Set up: the notice installs voxtype, then Set up runs.
# The toast count before it and the one after its run ended are each
# other's control.
expect "no Voice toast shows before Set up runs" 0 voice_toasts
forget_record
expect "Set up without voxtype is answered again" ok settings_open_tui vgs.voice setup
expect_poll "Set up raises the notice again" "$voice_asked" notice_shown
expect_poll "the Set up notice holds the keyboard for Install" true ipc smoke noticeFocused
hold_runs
type_keys -k Return || fail "sending Return to the Set up notice failed"
expect_poll "Install hands the terminal voxtype-bin through the AUR helper" "$(core_words core/requirements-install "Install requirements" org.vgs.tui pkg run install --manager aur voxtype-bin)" recorded
expect_poll "the notice records its install running" '["vgs.voice", ["voxtype", "voxtype-audio-bridge"], ["voxtype", "voxtype-audio-bridge"], true]' notice_shown
voice_engine_installed
forget_record
release_runs
expect_run_end "the voxtype install run ends" core/requirements-install
expect_poll "the scan after the install closes the notice" null notice_shown
expect_poll "the closed notice opens Set up on its own" "$(words vgs.voice/setup tui/setup.sh)" recorded_tail
expect "nothing waits on a notice once Set up opened" '{}' voice_resumes
expect_run_end "the setup run ends" vgs.voice/setup
expect_poll "the setup run that ended with code 0 shows one Voice toast" 1 voice_toasts
expect_poll "Voice sees voxtype after the install" true ipc smoke readInstance service vgs.voice voxtypePresent
# The stand-in terminal runs `true` for the setup script, so the stubs take
# the state the script leaves, which scripts/test-voice-tui.sh reads.
touch -- "$voice_installed"
device_reply systemctl 0 enabled --user is-enabled voxtype
device_reply systemctl 0 active --user is-active voxtype
rescan "the Voice rescan reads setup's end state"
expect_poll "Set up is withheld once the model and the service are in place" False voice_setup_offered
# Ready: the Setup section reads Ready with voxtype's version and the
# model, and Set up again comes last, secondary. The page opens again on
# its Settings tab.
settings_page_close vgs.voice
settings_page_open vgs.voice
expect_poll "the Setup section reads Ready, every screen active, and Set up again last, secondary" "$voice_setup_ready" voice_setup_section
expect "the Setup section names voxtype's version and the model" true voice_setup_line "voxtype 1.1.0 · parakeet-tdt-0.6b-v3"
# Control: a planted stand-in answer of a stopped service turns the same
# reading red: Set up needed, and Set up first, primary.
device_reply systemctl 3 inactive --user is-active voxtype
rescan "the Voice rescan reads a stopped service"
expect_poll "control: a stopped service draws Set up needed with Set up first, primary" '{"chips": [["Set up needed", "warning"]], "buttons": [["Set up", "primary", true, false], ["Configure", "secondary", true, false], ["Choose model", "secondary", true, false]]}' voice_setup_section
expect "control: the Setup section names the stopped service" true voice_setup_line "The Voice service is not running."
device_reply systemctl 0 active --user is-active voxtype
rescan "the Voice rescan reads the running service again"
expect_poll "the Setup section reads Ready again" "$voice_setup_ready" voice_setup_section
expect_poll "the three dictation shortcuts and the release companion are registered after setup" 4 voice_shortcuts
before="$(wc -l <"$voice_log")"
expect "the toggle shortcut reaches Voice" ok hypr dispatch 'hl.dsp.global("vgs.voice:toggle")'
expect_poll "a test dictation runs only voxtype record toggle" ok voice_toggle_only
settings_page_close vgs.voice
expect "disabling Voice after the setup rows is allowed" ok ipc shell setPluginEnabled vgs.voice false
expect_poll "no Voice toast is left for the next row" 0 voice_toasts
cp -- "$voice_pkg_real" "$repo/bin/vgshell-pkg.next" && mv -T -- "$repo/bin/vgshell-pkg.next" "$repo/bin/vgshell-pkg"
voice_engine_removed
rm -f -- "${voice_installed:?}"
device_reply_clear systemctl
rescan "rescan after removing the Voice stubs again"
cp -- "$voice_saved_config" "$home/.config/vgshell/shell.json.next" && mv -T -- "$home/.config/vgshell/shell.json.next" "$home/.config/vgshell/shell.json"
expect "the shell.json Voice found is reloaded" ok ipc shell reloadConfig
read -r voice_pointer_x voice_pointer_y <<<"$voice_pointer"
hover "$voice_pointer_x" "$voice_pointer_y" || fail "Voice puts the pointer back where it found it"
