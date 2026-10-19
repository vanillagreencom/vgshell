# Voice dictates through the core's `dictation` capability (D106), over the
# voxtype stand-in on the shell's PATH (scripts/smoke/fixtures/voxtype/):
# the daemon the core starts for it, its status follower and every record
# verb are the stand-in, whose daemon hears the words the row writes and
# types through the wtype stand-in beside it. The row's copy is a stub that
# answers the config and info verbs from the row's files; the bridge is a
# stub too. No row reaches the host's voxtype, its daemon, a microphone or
# the host's wtype. The row enables the plugin, reads the core's one daemon
# and follower, Voice's status and bar widget, sends its toggle and hold
# keys through the nested virtual-keyboard helper, reads setup offered
# while the stub model is missing and withheld when the stub reports it
# installed, then disables the plugin and reads its shortcuts, the core's
# daemon and its bridge child gone.
# The keys: the toggle key starts a `type` recording through the core, and
# the next press stops it, after which the wtype stand-in holds the
# stand-in's words; F9 held starts on the press and stops on the release.
# The key delivery uses physical code overrides for the row, so the helper
# reaches the same generated bind path that hold-shortcuts.sh exercises.
# The tap shortcut keeps its default keys: a lone Right Alt tap and a lone
# Right Ctrl tap each start a recording and the next tap stops it, and
# Right Alt used as AltGr with W starts none: the toggle key typed after
# it starts the one recording, where a chord that had started one would
# have had it stopped. Its control: with the tap unbound in the plugins
# row, a Right Alt tap before the toggle key reads the same.
# Another holder: while the fixture acme.dictation holds a `text`
# recording, Voice's widget reads idle and no display maps, and a Voice
# key, and the toggle the widget and the keys run, answer busy and leave
# that recording and Voice as they were. Two disposable copies of the
# service's logic, one that shows the phase whatever the holder and one
# whose toggle starts only while nobody records, each fail the reading
# they break.
# Enabling Voice without voxtype raises the requirement notice for voxtype
# itself, which the row closes with Not now after each enable.
# Without voxtype, the openTui IPC function, the launcher's route, raises
# the Voice requirement notice for voxtype alone, the one command Configure
# requires, in place of Configure and opens no script;
# its control is a disposable manifest copy whose Configure requires
# nothing, which launches the script with no notice. The Plugins list
# marks Voice Setup needed, for voxtype and its bridge, with no warning
# icon, since no optional tool is missing. The Voice page states voxtype missing once, in the
# Requirements row on Setup: the tab draws no Setup section, no headline
# and no step, since Install all missing installs it, and Settings draws
# Configure and Choose model, which are no setup screens and whose
# `requires` name voxtype, taking a press, which asks for voxtype first;
# Details states no status of voxtype, missing or found. Once set up, the
# section reads Ready with voxtype's version and the model. Install all
# missing raises the
# notice for voxtype and its bridge, and its Install hands the terminal
# voxtype-bin through the AUR helper, the row puts the stubs back as the
# package step would, and the scan after the run closes the notice; Voice
# then has the core start its daemon, and the section offers Set up, which
# opens `core/dictation-setup`; its end with code 0 starts the daemon
# again, Voice reads the model the stub then reports, and the section
# reads Ready. Its control: the core's daemon ended by the row reads Set up
# needed with Set up first, and Set up's run brings Ready back. With a
# stand-in daemon the row starts, as a voxtype user unit runs one, Voice
# reads the daemon elsewhere and the section offers Stop the other voxtype,
# `vgs.voice/stop-other`; the row ends that daemon while the run is held,
# and the run's end with code 0 has the core start its own daemon in the
# same shell. Its control: a disposable VoiceLogic.js whose RESTART_TUIS
# leaves out stop-other keeps elsewhere once Voice reads the end and over
# three times the shipped restart's time, at least two seconds. A stand-in
# bin/vgshell-pkg answers detection with pacman and paru, whatever the
# host runs, for that part alone. It closes its client window and puts
# back the shell.json and the pointer position it found: its Settings
# clicks leave the pointer over the centre, where a later row's
# requirement notice would keep the keyboard.
# The on-screen display: Voice's own recording, held by the row, and the
# stand-in's held transcribing drive it, and the stub bridge prints the
# bridge's frames, and a disconnected line on request. The row reads the
# layer presented on the focused output only while recording or
# transcribing, under the plasma and ring settings, unmapped at idle and
# under `osd: off`; a key typed and a click under the orb reach the
# focused client; the bridge child is the stand-in, runs only while the
# display shows, starts again a second after it exits and goes with a
# disable while recording; the orb rests cool, warms while recording and
# starts again from rest on a disconnected line; at motion scale 0 the
# shown orb presents no frame for two seconds.
# Three disposable copies, an Osd.qml whose `shown` ignores the state, an
# Osd.qml with a full input mask and a Plasma.qml whose driver ignores the
# motion scale, each fail the assertion they break. Every window, output,
# setting, theme and copy the display part changes is put back; it reuses
# the Voice client above. States and frames poll once per IPC round trip;
# no latency budget is claimed. The install reading prints the presenter's
# end stamp, the core's record read, status writes, scan completion and IPC
# observer window in milliseconds. Date.now has millisecond resolution;
# endedAt precedes the presenter's atomic rename. Host load and CPU pressure
# cover the idle observer. The ceiling and poll interval are harness.sh's.
# Dictation sounds, the manifest's held sound event, whose value voxtype's
# config holds: the stub voxtype answers `config get` from a file under the
# sandbox and records each `config set`, the restart is the core's, read as
# a new start of the stand-in's daemon, and the config file the service
# looks at is under the sandbox home, so no host file is read or written.
# The row reads that Voice states voxtype's value to the Sounds section and
# that its first read, and a choice of the value already there, write and
# restart nothing; that Off chosen in the Sounds section with the pointer
# and the keyboard runs one `config set`, one restart and a read back; and
# each way a choice does not take effect, by its problem key: a symbolic
# link, which stays a link, no config file, a refused write, which restarts
# nothing, a restart the core refuses during a recording, a value voxtype
# did not keep, and a value that cannot be read. A value that is neither
# choice and a choice made without voxtype start nothing.
# Control run on 2026-10-09, host cachy, through this row on a source_tree
# copy of the service whose holder answers the page's choice without
# running it and whose choice does not ask for voxtype: "Off from the
# Sounds section reaches voxtype's config and its read back" failed,
# reading ["own",""], and "without voxtype a dictation sounds choice is
# refused" failed, reading ok.
# The bar widget: the row reads one start, the widget at recording and the
# display presented after the typed toggle key, then the same three after
# a pointer click on the widget, which opens no Configure; a second click
# stops the dictation. A right click opens the widget menu, which reads
# Hide, Voxtype Settings, Readme, Settings, and Voxtype Settings hands the terminal
# Configure.
# A refused start opens the existing correction: Setup for an absent or
# failed daemon, Settings at Other dictation service for a foreign one.
# A failed-state start reports pending while it retries. The open page
# follows the actual result, including a continuing child failure.
# Without voxtype, a click on the widget starts no recording and offers
# voxtype and its bridge in the requirement notice; Not now closes it, and
# a click after it raises the notice again.
# The stand-in's lock: an ended daemon its parent has not reaped, planted
# in voxtype.lock, holds nothing, so the row's own daemon starts beside it
# and reads idle, and a second daemon beside that live one is refused. Its
# control: a copy of the stand-in that judges the holder by signal 0
# refuses the daemon beside the same planted holder.
# inputs: scripts/smoke/fixtures/voxtype/* scripts/smoke/fixtures/plugins/acme.dictation/* scripts/smoke/rows/capabilities.sh shell/Core/Dictation.qml shell/Core/DictationModel.js shell/Core/Sounds.qml shell/plugins/vgs.sounds/* shell/plugins/vgs.system/* shell/plugins/vgs.voice/* shell/plugins/vgs.voice/shaders/* shell/Ui/feedback/VoiceOrb.qml shell/Ui/feedback/shaders/* shell/Core/Layers.qml shell/Hosts/LayerHost.qml shell/Hosts/OverlaySurface.qml shell/Core/ShortcutRegistry.qml shell/Core/HyprlandLayer.js shell/Core/PluginStatus.qml shell/Core/TuiRunner.qml shell/Core/Notices.qml shell/Hosts/NoticeHost.qml shell/Ui/feedback/Badge.qml shell/Ui/foundation/Divider.qml shell/Core/PluginLogic.js shell/Core/ConfigLogic.js shell/Core/PackageManagers.js bin/vgshell-pkg bin/vgshell-tui shell/plugins/vgs.settings/* scripts/smoke/keyboard/* scripts/smoke/toplevel/* scripts/smoke/rows/hyprland-consent.sh shell/Core/IpcRegistry.qml shell/Ui/BarWidget.qml shell/Ui/controls/BarItem.qml shell/Ui/overlay/Menu.qml shell/Ui/overlay/MenuItem.qml shell/Core/Capabilities.qml
set -euo pipefail

voice_installed="$sandbox/voice-model-installed"
voice_bridge_log="$sandbox/voice-bridge.log"
voice_bridge_drop="$sandbox/voice-bridge-drop"
voice_theme="$home/.config/vgshell/theme.json"
voice_stub="$shim/voxtype"
voice_wtype="$shim/wtype"
voice_feedback="$sandbox/voice-feedback-value"
voice_feedback_sets="$sandbox/voice-feedback-sets"
voice_feedback_unreadable="$sandbox/voice-feedback-unreadable"
voice_feedback_refused="$sandbox/voice-feedback-refused"
voice_feedback_dropped="$sandbox/voice-feedback-dropped"
# The shared stand-in's own files (its header): the words its daemon
# hears, what its daemons noted, what its wtype was handed, its held
# transcribing and its cap, which the row lifts over its longest recording.
voice_words="$sandbox/voxtype-words"
voice_notes="$sandbox/voxtype-daemon.log"
voice_typed="$sandbox/voxtype-wtype.log"
voice_transcribing="$sandbox/voxtype-transcribing"
voice_cap="$sandbox/voxtype-max-secs"
printf 'true\n' >"$voice_feedback"
: >"$voice_feedback_sets"
printf '%s' 'the stand-in heard this' >"$voice_words"
printf '%s\n' 3600 >"$voice_cap"
rm -f -- "${voice_notes:?}" "${voice_typed:?}" "${voice_transcribing:?}"
voice_bridge_stub="$shim/voxtype-audio-bridge"
: >"$voice_bridge_log"
cat >"$voice_stub" <<EOF_STUB
#!/usr/bin/env bash
# The smoke's one voxtype stand-in, over this row's files.
voice_installed=$(printf %q "$voice_installed")
voice_feedback=$(printf %q "$voice_feedback")
voice_feedback_sets=$(printf %q "$voice_feedback_sets")
voice_feedback_unreadable=$(printf %q "$voice_feedback_unreadable")
voice_feedback_refused=$(printf %q "$voice_feedback_refused")
voice_feedback_dropped=$(printf %q "$voice_feedback_dropped")
. $(printf %q "$repo/scripts/smoke/fixtures/voxtype/voxtype")
EOF_STUB
cp -- "$repo/scripts/smoke/fixtures/voxtype/wtype" "$voice_wtype"
chmod 755 "$voice_stub" "$voice_wtype"
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
# Copies the package step puts back once the row has removed the stubs.
cp -- "$voice_stub" "$sandbox/voice-voxtype.stub"
cp -- "$voice_bridge_stub" "$sandbox/voice-bridge.stub"

voice_shortcuts() { hypr globalshortcuts | grep -c 'vgs.voice:' || true; }
voice_toggle() { ipc vgs.voice invoke toggle ""; }
# The capability's state as Voice reads it: daemon, phase and the
# recording's holder, `-` for none.
voice_state() { ipc smoke readInstance service vgs.voice dictationState | py_reply 'import json,sys; d=json.load(sys.stdin); print(d["daemon"], d["phase"], d["holder"] or "-")'; }
voice_shown() { ipc smoke readInstance service vgs.voice dictation; }
# The live recording's holder and mode in the core's lending record.
voice_recording() { lent dictation | py_reply 'import json,sys; d=json.load(sys.stdin); print(d["holder"] or "-", d["mode"] or "-")'; }
# What the stand-in's daemons noted since voice_forget, in order, and the
# last thing its wtype was handed; `none` for no line.
voice_noted() { if [[ -s $voice_notes ]]; then tr '\n' ' ' <"$voice_notes" | sed 's/ $//'; echo; else echo none; fi; }
voice_last_typed() { if [[ -s $voice_typed ]]; then tail -n 1 -- "$voice_typed"; else echo none; fi; }
voice_forget() { rm -f -- "${voice_notes:?}" "${voice_typed:?}"; }
voice_daemon_starts() { local status=0; grep -c '^started$' "$voice_notes" 2>/dev/null || status=$?; [[ $status -le 1 ]]; }
# voice_to STATE LABEL: Voice's own dictation moved to recording,
# transcribing or idle from where the service shows it: a recording starts
# and stops through the service's one toggle, transcribing is the
# stand-in's held one, and idle waits for the daemon's own idle, before
# which the core takes no start.
voice_to() { # recording|transcribing|idle LABEL
  local now
  now="$(voice_shown)" || now=unread
  case "$1:$now" in
    recording:'"recording"'|transcribing:'"transcribing"'|idle:'"idle"') ;;
    recording:'"idle"')
      expect_poll "$2: the core's daemon is ready and idle" "ready idle -" voice_state
      expect "$2: Voice starts a recording" ok voice_toggle ;;
    transcribing:'"recording"')
      : >"$voice_transcribing"
      expect "$2: Voice stops the recording" ok voice_toggle ;;
    idle:'"recording"') expect "$2: Voice stops the recording" ok voice_toggle ;;
    idle:'"transcribing"') ;;
    *) fail "$2: no step from $now to $1" ;;
  esac
  [[ $1 != idle ]] || rm -f -- "${voice_transcribing:?}"
  expect_poll "$2: Voice shows $1" "\"$1\"" voice_shown
  [[ $1 != idle ]] || expect_poll "$2: the daemon reads idle" "ready idle -" voice_state
}
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
  got="$(voice_client_counts)" || return 1
  [[ $got == "$voice_click_want" ]] && echo ok || echo "got=[$got] want=[$voice_click_want]"
}
voice_client_counts() {
  local down up
  down="$(voice_client_events '^button 272 pressed$')" && up="$(voice_client_events '^button 272 released$')" || return 1
  echo "$down $up"
}
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
# stopped once the display presents no frame over 0.5 s, read at most three
# times in a row; advancing when each of the three reads a frame.
voice_frames_settled() {
  local before after
  before="$(ipc smoke layerFrames)" || return 1
  for _ in 1 2 3; do
    sleep 0.5
    after="$(ipc smoke layerFrames)" || return 1
    [[ $before =~ ^[0-9]+$ && $after =~ ^[0-9]+$ ]] || { echo "unreadable before=$before after=$after"; return; }
    if ((after == before)); then echo stopped; return; fi
    before=$after
  done
  echo advancing
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
# Only the scale changes: the theme keeps its name and other tokens, so
# the Hyprland layer, whose borders line names the theme, is not written
# again, and Hyprland reloads no configuration while the display is read
# (VGS-1447).
voice_motion_still() {
  local name
  if [[ -e $voice_theme ]]; then cp -- "$voice_theme" "$sandbox/voice-theme-before"; else rm -f -- "$sandbox/voice-theme-before"; fi
  name="$(ipc smoke themeValue name)" || return 1
  python3 - "$voice_theme" "$name" <<'PY'
import json, os, sys
path, name = sys.argv[1], json.loads(sys.argv[2])
theme = json.load(open(path)) if os.path.exists(path) else {"schemaVersion": 1, "name": name}
theme.setdefault("tokens", {}).setdefault("motion", {})["scale"] = 0
with open(path + ".tmp", "w") as f:
    json.dump(theme, f)
os.replace(path + ".tmp", path)
PY
}
voice_motion_restore() {
  if [[ -e $sandbox/voice-theme-before ]]; then mv -T -- "$sandbox/voice-theme-before" "$voice_theme"; else rm -f -- "$voice_theme"; fi
}
# The orb watched for two seconds at motion scale 0 while transcribing; the
# theme and the watcher are put back whatever the reading. The two seconds
# start once the display has settled: the frame that draws the stopped
# orb, the tail of the palette fade and the frames the window presents with
# no item changed, read up to half a second after the motion change, fall
# before them. A WANT of swapped expects the frames to keep advancing.
voice_still_frames() { # LABEL WANT
  local settled=stopped
  [[ $2 == quiet ]] || settled=advancing
  voice_to recording "$1"
  voice_to transcribing "$1"
  expect_poll "$1: transcribing presents the display" presented voice_osd
  expect "$1: the display's window is watched" ok ipc smoke watchLayerFrames vgs.voice
  expect_poll "$1: the transcribing orb presents frames" advancing voice_frames_advancing
  voice_motion_still || fail "$1: zero motion is written to the theme file"
  expect_poll "$1: zero motion reaches the shell" 0 ipc smoke themeValue motion.scale
  expect "$1: the orb's frames read $settled at zero motion" "$settled" voice_frames_settled
  expect "$1" "$2" voice_frames_quiet
  voice_motion_restore
  expect_poll "$1: the motion scale is restored" 1 ipc smoke themeValue motion.scale
  expect "$1: the window watcher is released" ok ipc smoke dropLayerFrames
  voice_to idle "$1"
  expect_poll "$1: idle unmaps the display" unmapped voice_osd
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
voice_set_keys() { # [unbind-tap]
  python3 - "$home/.config/vgshell/shell.json" "${1:-}" <<'PY'
import json, os, sys
path, mode = sys.argv[1:]
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
if mode == "unbind-tap":
    row["keys"]["tap"] = None
with open(path + ".next", "w") as f:
    json.dump(config, f, indent=2)
os.replace(path + ".next", path)
PY
}
voice_requirement() { ipc shell listPlugins | py_reply 'import json,sys; p=[p for p in json.load(sys.stdin)["plugins"] if p["id"]=="vgs.voice"][0]; print([r["state"] for r in p["requirements"] if r["name"]==sys.argv[1]][0])' "$1"; }
# The setup entry's action Voice's setup state names, `none` for none.
voice_setup_offered() { ipc smoke readInstance service vgs.voice setupValue | py_reply 'import json,sys; v=json.load(sys.stdin); print(v["action"] or "none")'; }
voice_dictation() { ipc smoke readInstance "$(bar_key)" vgs.voice dictation; }
# The bar mic's recording tone beside a shell token, the accent unless
# another is named, each as #rrggbb: same while they match. Voice's look
# fills its accent from color.accent (vgs.voice/Appearance.js).
voice_mic_tone() { # [TOKEN]
  local tone want
  tone="$(ipc smoke readInstance "$(bar_key)" vgs.voice itemTone)" && want="$(ipc smoke themeValue "${1:-color.accent}")" || return 1
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
  got="$(voice_mic_tone color.info)" || return 1
  [[ $got == got=* ]] && echo differs || echo "$got"
}
voice_status_value() { ipc shell lent | py_reply 'import json,sys; r=json.load(sys.stdin)["status"].get("vgs.voice"); print("absent" if r is None else json.dumps(r["keys"]))'; }
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
  nested_input_check "$sandbox/keyboard" || return 1
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
# The centre of the Voice bar widget, as voice_widget_x and voice_widget_y.
voice_widget_point() {
  local box
  box="$(ipc smoke instanceGeometry "$(bar_key)" vgs.voice)" || box=""
  if [[ $box == \[* ]]; then
    read -r voice_widget_x voice_widget_y < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(int(x+w/2), int(y+h/2))' "$box")
  else
    fail "the Voice widget has no box: $box"
    # The rest corner, clear of the bar: a click there reaches no widget,
    # so each reading after it fails on its own.
    voice_widget_x=10 voice_widget_y="$((mon_h - 10))"
  fi
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
# Voice holds `dictation`, so the core starts a daemon once it is on: only
# over the stand-in.
if [[ $(shell_resolves voxtype) != "$voice_stub" ]]; then
  fail "the shell does not resolve voxtype to the row's stand-in: $(shell_resolves voxtype)"
  rm -f -- "${voice_stub:?}" "${voice_wtype:?}" "${voice_bridge_stub:?}" "${voice_cap:?}"
  hypr_lua_restore voice || fail "Voice restores hyprland.lua"
  return 0
fi
voice_layers_base="$(layer_count vgs:layer)" || fail "the layer count before Voice is unreadable"
expect "enabling Voice is allowed" ok ipc shell setPluginEnabled vgs.voice true
expect "placing Voice in the bar is allowed" ok ipc shell setPluginPlaced vgs.voice true
voice_set_keys
expect "Voice physical key overrides are reloaded" ok ipc shell reloadConfig
expect "Hyprland reloads Voice physical key overrides" ok hypr reload config-only
expect_poll "Voice builds" True record_exists vgs.voice
expect_poll "Voice reads the physical key overrides and the first default tap key" '{"toggle":"SUPER+CTRL+code:53","tap":"code:108","talk":"code:75"}' ipc smoke readInstance service vgs.voice shortcutKeys
expect_poll "Voice sees voxtype present" true ipc smoke readInstance service vgs.voice voxtypePresent
expect_poll "Voice registers its three shortcuts and the release companion" 4 voice_shortcuts
expect_poll "the holder reads the missing speech model" setup voice_setup_offered
expect_poll "a missing model keeps the core daemon absent" "absent idle -" voice_state
expect_poll "a missing model starts neither daemon nor follower" "daemon=0 follower=0 other=0" dictation_processes all
expected_errors+=('WARN qml: voice: start refused: dictation=daemon-absent')
expect "a start with a missing model is refused" "refused: dictation=daemon-absent" voice_toggle
expect_poll "the absent daemon refusal opens the existing correction window" 1 window_count Plugins
expect_poll "the absent daemon refusal shows Voice Setup" '"vgs.voice/Setup"' ipc smoke readInstance window vgs.settings shownPage
expect "the absent daemon refusal keeps the setup action available" setup voice_setup_offered
settings_page_close vgs.voice
touch -- "$voice_installed"
expect "the holder rereads setup after installing the model" ok ipc smoke invokeInstance service vgs.voice restartDaemon ""
expect_poll "the core lends Voice dictation and starts its daemon" "ready running vgs.voice" dictation_lent
expect_poll "one daemon and one follower run, children of the shell" "daemon=1 follower=1 other=0" dictation_processes owned
expect_poll "Voice reads the core's daemon ready" "ready idle -" voice_state
expect_poll "Set up is withheld while dictation is ready" none voice_setup_offered
voice_to recording "Voice's first recording"
expect_poll "the recording reaches plugin status" '["dictation", "model", "otherService", "setup"]' voice_status_value
expect_poll "the recording state reaches the bar widget" '"recording"' voice_dictation
expect "the recording mic draws the shell's accent" same voice_mic_tone
expect "control: the same reader tells the mic from the info tone" differs voice_mic_tone_control
expect_poll "the recording state reaches dictation status" '"recording"' ipc smoke readInstance service vgs.voice dictationStatus
voice_to idle "Voice's first recording"
expect_poll "the stopped recording reaches the bar widget as idle" '"idle"' voice_dictation

# Dictation sounds.
expected_errors+=('WARN qml: voice: feedback wanted=("own"|""|null) problem=(link|no-config|write|restart|mismatch|unread) ' 'voice: bridge exited code=0 status=0')
voice_config_dir="$home/.config/voxtype"
voice_config="$voice_config_dir/config.toml"
voice_dotfile="$sandbox/voice-dotfile-config.toml"
# The value and the problem key the service last stated, once no run is in
# flight: `running` until then.
voice_feedback_state() {
  local run
  run="$(ipc smoke readInstance service vgs.voice feedbackRun)" || return
  [[ $run == null ]] || { echo running; return; }
  printf '[%s,%s]\n' "$(ipc smoke readInstance service vgs.voice feedbackValue)" "$(ipc smoke readInstance service vgs.voice feedbackProblem)"
}
voice_feedback_choose() { ipc smoke invokeInstance service vgs.voice chooseFeedback "$1"; }
# How many `config set` calls the stub recorded and the last one, then how
# many times the stand-in's daemon started since this part began: each
# restart the core takes is one start.
voice_feedback_sets_read() { printf '%s %s\n' "$(wc -l <"$voice_feedback_sets")" "$(tail -n 1 -- "$voice_feedback_sets" | awk '{ print $NF }')"; }
voice_feedback_calls() { printf '%s %s\n' "$(voice_feedback_sets_read)" "$(( $(voice_daemon_starts) - voice_starts_before ))"; }
voice_starts_before="$(voice_daemon_starts)" || fail "the stand-in daemon's notes are unreadable"
# The Dictation sounds row of the Sounds section: PROPERTY as JSON.
voice_sound_row() { ipc smoke readMatchingDescendant window vgs.sounds FormRow label "Dictation sounds" "$1"; }
voice_system_was="$(plugin_enabled vgs.system)" || fail "vgs.system's enabled state is unreadable"
voice_page_was="$(plugin_enabled vgs.sounds)" || fail "vgs.sounds's enabled state is unreadable"
mkdir -p -- "$voice_config_dir"
printf '%s\n' '[audio.feedback]' 'enabled = true' >"$voice_config"
expect_poll "Voice states voxtype's dictation sounds value, with no problem" '["own",""]' voice_feedback_state
expect "the first read writes nothing and restarts nothing" "0  0" voice_feedback_calls
expect "a choice of the value voxtype holds is taken" ok voice_feedback_choose own
expect_poll "the choice of the value voxtype holds ends as it began" '["own",""]' voice_feedback_state
expect "a choice of the value voxtype holds writes nothing and restarts nothing" "0  0" voice_feedback_calls
expect "a value that is neither choice is refused" 'refused: feedback="chime" reason=value' voice_feedback_choose chime
expect "a refused value starts no run" '["own",""]' voice_feedback_state
# Off, chosen in the Sounds section: a click opens the row's picker, Up
# moves to Off and Return takes it.
expect "enabling the System window for the Sounds section is allowed" ok ipc shell setPluginEnabled vgs.system true
expect "enabling vgs.sounds for the Sounds section is allowed" ok ipc shell setPluginEnabled vgs.sounds true
expect "the Sounds section summons for Voice" ok ipc shell summon window vgs.system '{"pane":"vgs.sounds"}'
expect_poll "the Sounds section is mounted for Voice" '["vgs.sounds"]' window_panes
expect_poll "the Dictation sounds row shows voxtype's value, its own tones" 1 voice_sound_row chosen
voice_picker_box="$(ipc smoke scopedWindowGeometry window vgs.sounds FormRow "Dictation sounds" Select "Dictation tones")" || voice_picker_box=""
if read -r voice_px voice_py < <(at_centre "window:System Settings" "$voice_picker_box"); then
  hover "$voice_px" "$voice_py" || fail "hovering the Dictation sounds picker failed"
  click "$voice_px" "$voice_py" || fail "clicking the Dictation sounds picker failed"
  expect_poll "the click opens the Dictation sounds picker" true ipc smoke readMatchingDescendant window vgs.sounds Select currentText "Dictation tones" listOpen
  type_keys -k Up -k Return || fail "choosing Off in the Dictation sounds picker failed"
else
  fail "the Dictation sounds picker has no box: $voice_picker_box"
fi
expect_poll "Off from the Sounds section reaches voxtype's config and its read back" '["",""]' voice_feedback_state
expect_poll "Off runs one config set of false and one restart" "1 false 1" voice_feedback_calls
expect_poll "the Dictation sounds row shows Off" 0 voice_sound_row chosen
expect "the Dictation sounds row shows its description, muted" '"muted"' voice_sound_row warningTone
# A symbolic link is left as it is, and the row says why.
printf '%s\n' 'kept=1' >"$voice_dotfile"
rm -f -- "${voice_config:?}"
ln -s -- "$voice_dotfile" "$voice_config"
expect "a choice over a linked config is taken" ok voice_feedback_choose own
expect_poll "a linked config keeps voxtype's value and names the link" '["","link"]' voice_feedback_state
expect "a linked config is not written and nothing restarts" "1 false 1" voice_feedback_calls
expect "the link is still a link to the same text" "link kept=1" bash -c '[[ -L $1 ]] && printf "link %s\n" "$(cat -- "$2")"' _ "$voice_config" "$voice_dotfile"
expect_poll "the Dictation sounds row shows the problem in the warning tone" '"warning"' voice_sound_row warningTone
# No config file.
rm -f -- "${voice_config:?}"
expect "a choice with no config file is taken" ok voice_feedback_choose own
expect_poll "no config file keeps voxtype's value and names the missing file" '["","no-config"]' voice_feedback_state
expect "no config file is written and nothing restarts" "1 false 1" voice_feedback_calls
# A write voxtype refuses restarts nothing.
printf '%s\n' '[audio.feedback]' 'enabled = false' >"$voice_config"
touch -- "$voice_feedback_refused"
expect "a choice voxtype refuses to write is taken" ok voice_feedback_choose own
expect_poll "a refused write keeps voxtype's value and names the write" '["","write"]' voice_feedback_state
expect "a refused write was asked once and restarts nothing" "2 true 1" voice_feedback_calls
rm -f -- "${voice_feedback_refused:?}"
# A restart the core refuses, as during a recording: the value is written,
# read back and the row says the change waits.
voice_to recording "a refused restart"
expect "a choice whose restart is refused is taken" ok voice_feedback_choose own
expect_poll "a refused restart shows the written value and names the restart" '["own","restart"]' voice_feedback_state
expect "a refused restart follows one more config set and starts no daemon" "3 true 1" voice_feedback_calls
voice_to idle "a refused restart"
# A value voxtype did not keep.
touch -- "$voice_feedback_dropped"
expect "a choice voxtype does not keep is taken" ok voice_feedback_choose ""
expect_poll "a value voxtype did not keep shows the value read back and names the mismatch" '["own","mismatch"]' voice_feedback_state
expect_poll "a value voxtype did not keep was asked once and restarted the daemon once more" "4 false 2" voice_feedback_calls
rm -f -- "${voice_feedback_dropped:?}"
# A value that cannot be read, as with a config voxtype cannot parse: the
# Sounds section's refresh has Voice read it.
touch -- "$voice_feedback_unreadable"
expect "the System window hides before the Sounds section opens again" ok ipc shell hide window vgs.system
expect_poll "the System window is gone before the Sounds section opens again" 0 window_count 'System Settings'
expect "the Sounds section summons again for Voice" ok ipc shell summon window vgs.system '{"pane":"vgs.sounds"}'
expect_poll "opening the Sounds section has Voice read a value it cannot read" '[null,"unread"]' voice_feedback_state
expect_poll "the Dictation sounds row shows no choice" -1 voice_sound_row chosen
rm -f -- "${voice_feedback_unreadable:?}"
expect "the System window hides after the Sounds section" ok ipc shell hide window vgs.system
expect_poll "the System window is gone after the Sounds section" 0 window_count 'System Settings'
expect "vgs.sounds's enablement goes back to what Voice found" ok ipc shell setPluginEnabled vgs.sounds "$([[ $voice_page_was == True ]] && echo true || echo false)"
expect "vgs.system's enablement goes back to what Voice found" ok ipc shell setPluginEnabled vgs.system "$([[ $voice_system_was == True ]] && echo true || echo false)"
rm -rf -- "${voice_config_dir:?}" "${voice_dotfile:?}"
voice_feedback_sets_before="$(voice_feedback_sets_read)" || fail "the dictation sounds calls are unreadable"

open_toplevel "$sandbox/voice-client.log" smoke.voice-client "Voice client"
voice_client_pid="$toplevel_pid"
expect_poll "the Voice client has keyboard focus" '["smoke.voice-client", "Voice client"]' active_window
voice_start_keyboard
# voice_stops LABEL: the recording the keys before it started is stopped,
# typed through the wtype stand-in, and the daemon idle again.
voice_stops() { # LABEL
  expect_poll "$1 stops the recording" "start stop" voice_noted
  expect_poll "$1: the wtype stand-in typed the stand-in's words" "-d 10 -- the stand-in heard this" voice_last_typed
  expect_poll "$1: the daemon reads idle" "ready idle -" voice_state
}
expect_poll "the daemon is idle before the keys" "ready idle -" voice_state
voice_forget
voice_toggle_key
voice_sync "the Voice keyboard delivered the toggle keys"
expect_poll "the typed toggle key starts a recording through the core" "ready recording vgs.voice" voice_state
expect "the recording is Voice's own, in type mode" "vgs.voice type" voice_recording
expect_poll "the typed toggle key ran one start" start voice_noted
voice_toggle_key
voice_sync "the Voice keyboard delivered the toggle keys again"
voice_stops "the next press of the toggle key"
voice_forget
voice_f9_press
voice_sync "the Voice keyboard delivered F9 press"
expect_poll "F9 press starts a recording" "ready recording vgs.voice" voice_state
expect_poll "F9 press ran a start and no stop" start voice_noted
voice_f9_release
voice_sync "the Voice keyboard delivered F9 release"
voice_stops "the release of held F9"
voice_forget
voice_send "down 108" "up 108"
voice_sync "the Voice keyboard delivered a lone Right Alt tap"
expect_poll "a lone Right Alt tap, the default tap key, starts a recording" "ready recording vgs.voice" voice_state
voice_send "down 108" "up 108"
voice_sync "the Voice keyboard delivered a second lone Right Alt tap"
voice_stops "the next Right Alt tap"
voice_forget
voice_send "down 105" "up 105"
voice_sync "the Voice keyboard delivered a lone Right Ctrl tap"
expect_poll "a lone Right Ctrl tap, the second default tap key, starts a recording" "ready recording vgs.voice" voice_state
voice_send "down 105" "up 105"
voice_sync "the Voice keyboard delivered a second lone Right Ctrl tap"
voice_stops "the next Right Ctrl tap"
# The toggle key after the chord: one start and no stop say the chord
# started no recording, which the toggle key would have stopped.
voice_forget
voice_send "down 108" "down 25" "up 25" "up 108"
voice_toggle_key
voice_sync "the Voice keyboard delivered Right Alt as AltGr with W, then the toggle keys"
expect_poll "Right Alt used as AltGr starts no recording before the toggle key's" "ready recording vgs.voice" voice_state
expect "Right Alt used as AltGr and the toggle key ran one start and no stop" start voice_noted
voice_toggle_key
voice_sync "the Voice keyboard delivered the toggle keys after the chord"
voice_stops "the toggle key after the chord"
voice_set_keys unbind-tap
expect "control: Voice's unbound tap is reloaded" ok ipc shell reloadConfig
expect "control: Hyprland reloads Voice's unbound tap" ok hypr reload config-only
expect_poll "control: Voice reads its tap unbound" '{"toggle":"SUPER+CTRL+code:53","tap":null,"talk":"code:75"}' ipc smoke readInstance service vgs.voice shortcutKeys
voice_forget
voice_send "down 108" "up 108"
voice_toggle_key
voice_sync "control: the Voice keyboard delivered a lone Right Alt tap, then the toggle keys"
expect_poll "control: the unbound Right Alt tap starts no recording before the toggle key's" "ready recording vgs.voice" voice_state
expect "control: the unbound Right Alt tap and the toggle key ran one start and no stop" start voice_noted
voice_toggle_key
voice_sync "control: the Voice keyboard delivered the toggle keys after the unbound tap"
voice_stops "control: the toggle key after the unbound tap"

# Another holder's recording: Voice shows none of it, and its keys, its
# widget and its toggle start nothing during it. The fixture is the one
# capabilities.sh installs.
voice_other() { ipc acme.dictation invoke "$1" "${2:-}"; } # VERB [ARG]
voice_other_last() { ipc smoke readInstance service acme.dictation last | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin), sort_keys=True))'; }
voice_other_hidden() { echo "$(voice_dictation) $(voice_osd)"; }
voice_other_hidden_assertion() {
  (failures=0 behaviour_failures=0
   expect "another holder's recording leaves Voice's widget idle and maps no display" '"idle" unmapped' voice_other_hidden >"$sandbox/voice-other-hidden-assertion.log"
   echo "$failures")
}
voice_other_busy_assertion() {
  (failures=0 behaviour_failures=0
   expect "Voice's toggle during another holder's recording answers busy" "refused: dictation=busy holder=acme.dictation" voice_toggle >"$sandbox/voice-other-busy-assertion.log"
   echo "$failures")
}
expected_errors+=('WARN qml: voice: start refused: dictation=busy holder=acme\.dictation')
expect_poll "the dictation fixture is known" True plugin_known acme.dictation
expect "enabling the dictation fixture beside Voice is allowed" ok ipc shell setPluginEnabled acme.dictation true
expect_poll "the fixture is built" True record_exists acme.dictation
expect_poll "both holders are lent the one daemon" "ready running vgs.voice,acme.dictation" dictation_lent
expect "a second holder starts no second daemon" "daemon=1 follower=1 other=0" dictation_processes owned
voice_forget
expect "the fixture starts a text recording" ok voice_other start text
expect_poll "Voice reads the fixture's recording" "ready recording acme.dictation" voice_state
expect "the fixture's recording leaves Voice's widget idle and maps no display" '"idle" unmapped' voice_other_hidden
expect "the fixture's recording runs no bridge child" "stand-in=0 host=0" voice_bridges
voice_toggle_key
voice_sync "the Voice keyboard delivered the toggle keys during the fixture's recording"
expect "Voice's toggle, which its keys and its widget run, answers busy and names the holder" "refused: dictation=busy holder=acme.dictation" voice_toggle
expect "a Voice key and its toggle leave the fixture's recording as it was" "ready recording acme.dictation" voice_state
expect "a Voice key and its toggle start no recording of Voice's" '"idle" unmapped' voice_other_hidden
expect "the daemon took the fixture's start alone" start voice_noted
expect "the fixture stops its recording" ok voice_other stop
expect_poll "the fixture gets the stand-in's words" '{"kind": "text", "text": "the stand-in heard this"}' voice_other_last
expect "the fixture's recording typed nothing" none voice_last_typed
expect_poll "the daemon reads idle after the fixture's recording" "ready idle -" voice_state
# Controls: a disposable copy of the service's logic that shows the phase
# whatever the holder, and one of the service whose toggle starts only
# while nobody records; each fails the reading it breaks. Each copy is put
# back before the next.
expected_errors+=('WARN qml: voice: stop refused: dictation=not-holder holder=acme\.dictation')
for voice_other_mutant in holder toggle; do
  voice_other_file="$repo/shell/plugins/vgs.voice/VoiceLogic.js"
  [[ $voice_other_mutant != toggle ]] || voice_other_file="$repo/shell/plugins/vgs.voice/Service.qml"
  cp -- "$voice_other_file" "$sandbox/voice-other-before"
  expect "disabling Voice for the $voice_other_mutant control is allowed" ok ipc shell setPluginEnabled vgs.voice false
  python3 - "$voice_other_file" "$voice_other_mutant" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); assert not p.is_symlink()
needle, replacement = {
    "holder": ("if (state.holder === HOLDER) return { own: true, phase: state.phase };", 'if (state.holder !== "") return { own: true, phase: state.phase };'),
    "toggle": ("return dictationState.holder === VoiceLogic.HOLDER ? stop() : start();", 'return dictationState.holder !== "" ? stop() : start();'),
}[sys.argv[2]]
s = p.read_text(); assert s.count(needle) == 1
changed = s.replace(needle, replacement); assert changed != s
p.write_text(changed)
PY
  rescan "the Voice $voice_other_mutant control copy is scanned"
  expect "enabling Voice for the $voice_other_mutant control is allowed" ok ipc shell setPluginEnabled vgs.voice true
  expect_poll "Voice builds for the $voice_other_mutant control" True record_exists vgs.voice
  expect_poll "control: the daemon reads idle for the $voice_other_mutant copy" "ready idle -" voice_state
  expect "control: the fixture records beside the $voice_other_mutant copy" ok voice_other start text
  expect_poll "control: the $voice_other_mutant copy reads the fixture's recording" "ready recording acme.dictation" voice_state
  case "$voice_other_mutant" in
    holder) expect "control: a service that shows the phase whatever the holder fails the idle reading" 1 voice_other_hidden_assertion ;;
    toggle) expect "control: a toggle that starts only while nobody records fails the busy reading" 1 voice_other_busy_assertion ;;
  esac
  expect "control: the fixture cancels its recording beside the $voice_other_mutant copy" ok voice_other cancel
  expect_poll "control: the daemon reads idle after the $voice_other_mutant copy" "ready idle -" voice_state
  expect "disabling Voice after the $voice_other_mutant control is allowed" ok ipc shell setPluginEnabled vgs.voice false
  cp -- "$sandbox/voice-other-before" "$voice_other_file"
done
rescan "the shipped Voice service is scanned again"
expect "enabling Voice after the holder controls is allowed" ok ipc shell setPluginEnabled vgs.voice true
expect_poll "Voice builds after the holder controls" True record_exists vgs.voice
expect "disabling the dictation fixture is allowed" ok ipc shell setPluginEnabled acme.dictation false
expect_poll "Voice alone holds dictation again" "ready running vgs.voice" dictation_lent

# The on-screen display, over Voice's own recording.
voice_osd_orb=Plasma
voice_to recording "the display"
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
voice_to transcribing "the display"
expect_poll "transcribing keeps the display presented" presented voice_osd
expect "transcribing keeps the bridge child" "stand-in=1 host=0" voice_bridges
voice_to idle "the display"
expect_poll "idle unmaps the display" unmapped voice_osd
expect_poll "idle stops the bridge child" "stand-in=0 host=0" voice_bridges
expect_poll "the orb rests in the cool palette" "#4a72e0" voice_plasma_rim
voice_still_frames "zero motion presents no display frame over two seconds" quiet
expect "an osd setting of off is written" ok voice_set_osd off
expect_poll "the service reads osd off" '"off"' ipc smoke readInstance service vgs.voice osdMode
voice_to recording "osd off"
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

# The bar widget's click, read beside the toggle key: each runs one start,
# so the widget and the display read the same dictation after either.
voice_widget_pointer="$pointer_at"
voice_to idle "before the toggle key"
expect_poll "idle unmaps the display before the toggle key" unmapped voice_osd
expect_poll "the bar widget reads idle before the toggle key" '"idle"' voice_dictation
voice_forget
voice_toggle_key
voice_sync "the Voice keyboard delivered the toggle keys for the widget's reading"
expect_poll "the toggle key runs one start" start voice_noted
expect_poll "the toggle key's dictation reaches the bar widget as recording" '"recording"' voice_dictation
expect_poll "the toggle key's dictation presents the display" presented voice_osd
voice_to idle "before the widget's click"
expect_poll "idle unmaps the display before the widget's click" unmapped voice_osd
expect_poll "the bar widget reads idle before its click" '"idle"' voice_dictation
voice_widget_point
forget_record
voice_forget
hover "$((voice_widget_x - 1))" "$voice_widget_y" && click "$voice_widget_x" "$voice_widget_y" || fail "the click on the Voice widget failed"
expect_poll "a click on the Voice widget runs one start, as the toggle key does" start voice_noted
expect_poll "the click's dictation reaches the bar widget as recording" '"recording"' voice_dictation
expect_poll "the click's dictation presents the display" presented voice_osd
expect "the click ran no second start" start voice_noted
expect "a click on the Voice widget opens no Configure" absent recorded
click "$voice_widget_x" "$voice_widget_y" || fail "the second click on the Voice widget failed"
expect_poll "a second click on the Voice widget stops the dictation" "start stop" voice_noted
expect_poll "the second click's stop reaches the bar widget as idle" '"idle"' voice_dictation
expect_poll "the second click's stop unmaps the display" unmapped voice_osd
expect_poll "the daemon reads idle after the widget's dictation" "ready idle -" voice_state
# The widget menu: Voxtype Settings sits between the bar's own Hide and
# Readme, and opens Configure. The stand-in terminal records the run and
# runs none of voxtype's own screen; the run's end with code 0 has the
# core start its daemon again, which is all the daemon notes.
voice_menu() { ipc smoke readInstance "$(bar_key)" vgs.voice "$1"; }
voice_forget
hover "$((voice_widget_x - 1))" "$voice_widget_y" && right_click "$voice_widget_x" "$voice_widget_y" || fail "the right click on the Voice widget failed"
expect_poll "a right click on the Voice widget opens its menu" true voice_menu frameMenuOpen
expect "the menu holds Hide, Voxtype Settings, Readme and Settings" '["Hide","Voxtype Settings","Readme","Settings"]' voice_menu frameMenuEntries
expect "a right click on the Voice widget opens no Configure" absent recorded
voice_menu_index="$(voice_menu frameMenuEntries | py_reply 'import json,sys; rows=json.load(sys.stdin); print(rows.index("Voxtype Settings") if "Voxtype Settings" in rows else "absent")')" || voice_menu_index=unreadable
if [[ $voice_menu_index =~ ^[0-9]+$ ]]; then
  type_keys -k Home || fail "Home on the Voice widget's menu failed"
  for ((voice_menu_step = 0; voice_menu_step < voice_menu_index; voice_menu_step++)); do type_keys -k Down || fail "Down on the Voice widget's menu failed"; done
  type_keys -k Return || fail "Return on the Voice widget's menu failed"
  expect_poll "Voxtype Settings hands the terminal Configure" "$(words vgs.voice/configure tui/configure.sh)" recorded_tail
  expect_poll "Voxtype Settings closes the menu" false voice_menu frameMenuOpen
  expect_run_end "the Configure run from the menu ends" vgs.voice/configure
  expect_poll "Configure's end with code 0 starts the daemon again, and the menu started no recording" "stopped started" voice_noted
else
  fail "the Voice widget's menu has no Voxtype Settings: $voice_menu_index"
  type_keys -k Escape || fail "Escape on the Voice widget's menu failed"
  expect_poll "Escape closes the Voice widget's menu" false voice_menu frameMenuOpen
fi
forget_record
expect_poll "the Voice client has keyboard focus again after the menu" '["smoke.voice-client", "Voice client"]' active_window
read -r voice_widget_back_x voice_widget_back_y <<<"${voice_widget_pointer:-10 $((mon_h - 10))}"
hover "$voice_widget_back_x" "$voice_widget_back_y" || fail "putting the pointer back after the Voice widget's menu failed"
voice_to recording "after the widget's menu"
expect_poll "recording presents the display again after the widget's menu" presented voice_osd
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
voice_to idle "after the second output"
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
      voice_to recording "control"
      expect_poll "control: the full-mask copy is presented" presented voice_osd
      voice_osd_click_begin || fail "the click under the full-mask copy could not be made"
      expect "control: a full input mask fails the click assertion" 1 voice_osd_click_assertion
      expect "control: the full mask leaves the client's press and release counts unchanged" "$voice_click_before" voice_client_counts
      voice_to idle "control"
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
expect_poll "Set up is withheld once the model is installed" none voice_setup_offered
voice_to recording "before the disable"
expect_poll "recording before the disable runs the stand-in bridge" "stand-in=1 host=0" voice_bridges
expect "disabling Voice is allowed" ok ipc shell setPluginEnabled vgs.voice false
expect_poll "disabling Voice removes its shortcuts" 0 voice_shortcuts
expect_poll "disabling Voice clears its status" absent voice_status_value
expect_poll "disabling Voice, the last holder, ends the core's daemon and its follower" "daemon=0 follower=0 other=0" dictation_processes all
expect "the lending record reads no daemon and no holder" "absent none -" dictation_lent
expect_poll "disabling Voice leaves no bridge child" "stand-in=0 host=0" voice_bridges
voice_stop_keyboard
close_toplevel "$voice_client_pid" "the Voice client exits 0 on SIGTERM"
hypr_lua_restore voice || fail "Voice restores hyprland.lua"
expect "Voice key resolution restore is reloaded" ok hypr reload config-only
rm -f -- "${voice_stub:?}" "${voice_wtype:?}" "${voice_bridge_stub:?}" "${voice_installed:?}"
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
voice_notice_groups() { ipc smoke noticeDrawn | py_reply 'import json,sys; print(json.dumps([[g[0], len(g[1])] for g in json.load(sys.stdin)["groups"]]))'; }
# The required dictation step's chip and text actions, separate from Tools.
voice_setup_section() { ipc smoke setupRows window vgs.settings | py_reply 'import json,sys; rows=[r for r in json.load(sys.stdin) if r["key"]=="setup"]; print(json.dumps({"chips":rows[0]["chips"],"buttons":[[b["text"],b["tone"],b["enabled"]] for b in rows[0]["buttons"]]}) if len(rows)==1 else "rows=%d" % len(rows))'; }
voice_tools_step() { ipc smoke setupRows window vgs.settings | py_reply 'import json,sys; rows=[r for r in json.load(sys.stdin) if r["key"]=="required-tools"]; print(json.dumps([rows[0]["chips"], [b["text"] for b in rows[0]["buttons"]]]) if len(rows)==1 else "rows=%d" % len(rows))'; }
# The Setup section's lines against Voice's own Setup value: the value's
# action ("none" once set up), how many lines it holds, and whether the
# section draws exactly those lines, in order, one under the other. VALUE,
# when given, stands in for the service's value.
voice_setup_lines() { # [VALUE]
  local value="${1-}"
  if [[ -z $value ]]; then value="$(ipc smoke readInstance service vgs.voice setupValue)" || return 1; fi
  ipc smoke setupSection window vgs.settings | py_reply 'import json,sys
v = json.loads(sys.argv[1]); want = v["lines"]; drawn = json.load(sys.stdin)["lines"]
shown = any(drawn[i:i + len(want)] == want for i in range(len(drawn) - len(want) + 1))
print(json.dumps({"action": v["action"] or "none", "lines": len(want), "drawn": shown}))' "$value"
}
# Control: Voice's own Setup value with its last line changed.
voice_setup_value_changed() { ipc smoke readInstance service vgs.voice setupValue | py_reply 'import json,sys; v=json.load(sys.stdin); v["lines"][-1] += " (changed)"; print(json.dumps(v))'; }
voice_setup_needed='{"chips": [["To do", "warning"]], "buttons": [["Set up", "accent", true]]}'
voice_setup_ready='{"chips": [["Done", "success"]], "buttons": []}'
# The shown tab's Configure and Choose model, each as whether it is
# drawn, then whether it takes a press. Configure is a More settings
# screen on Settings; Choose model is a Details action.
voice_screen() { # TEXT
  local any on
  any="$(ipc smoke shownWindowGeometry window vgs.settings RowAction "$1")" || return
  on="$(ipc smoke windowGeometry window vgs.settings RowAction "$1")" || return
  [[ $any == \[* ]] && any=drawn
  [[ $on == \[* ]] && on=enabled
  printf '%s %s\n' "$any" "$on"
}
voice_screens() { printf '%s, %s\n' "$(voice_screen Configure)" "$(voice_screen "Choose model")"; }
voice_engine_installed() {
  cp -- "$sandbox/voice-voxtype.stub" "$voice_stub" && cp -- "$repo/scripts/smoke/fixtures/voxtype/wtype" "$voice_wtype" && cp -- "$sandbox/voice-bridge.stub" "$voice_bridge_stub" && chmod 755 "$voice_stub" "$voice_wtype" "$voice_bridge_stub"
}
voice_engine_removed() { rm -f -- "${voice_stub:?}" "${voice_wtype:?}" "${voice_bridge_stub:?}"; }
voice_notice_escape() { # LABEL
  expect_poll "$1: the notice holds the keyboard" true ipc smoke noticeFocused
  type_keys -k Escape || fail "$1: sending Escape failed"
  expect_poll "$1: Escape closes the notice" null notice_shown
}
voice_asked='["vgs.voice", ["voxtype", "voxtype-audio-bridge"], ["voxtype", "voxtype-audio-bridge"], false]'
# Enabling Voice without voxtype raises its notice by itself, since voxtype
# and its bridge are required. Not now closes it, so each reading after an
# enable starts with no notice shown.
voice_enabled_notice() { # LABEL
  expect_poll "$1: enabling Voice without voxtype raises the notice for voxtype and its bridge" "$voice_asked" notice_shown
  voice_notice_escape "$1"
}
# Details holds the action for another dictation service, beside its
# reading and on no Settings field.
voice_other_service() { ipc smoke settingRows window vgs.settings | py_reply 'import json,sys; rows=[r for r in json.load(sys.stdin) if r["key"]=="otherService"]; print(json.dumps([rows[0]["field"], [[b["text"],b["enabled"]] for b in rows[0]["buttons"]]]) if len(rows)==1 else "rows=%d" % len(rows))'; }
voice_offered_actions() { offered_actions vgs.voice | py_reply 'import json,sys; print(json.dumps([row for row in json.load(sys.stdin) if row[2]]))'; }
# The Voice row of the Plugins list: its required Setup mark and the
# absence of the removed optional-tool icon.
voice_list_mark() { ipc smoke scopedWindowGeometry window vgs.settings ListItem Voice "$1" "$2" | py_reply 'import sys; print("absent" if sys.stdin.read().strip() == "absent" else "drawn")'; }
voice_list_marks() { printf '%s %s\n' "$(voice_list_mark Badge "Setup needed")" "$(voice_list_mark IconButton "Open setup")"; }
# Voice holds `dictation`, and the shell finds no voxtype: the core's probe
# does not start, at each start and each restart Voice asks for.
expected_errors+=("${dictation_absent_errors[@]}")

expect "enabling Voice without voxtype is allowed" ok ipc shell setPluginEnabled vgs.voice true
expect_poll "Voice without voxtype is built" True record_exists vgs.voice
voice_enabled_notice "enabling without voxtype"
expect_poll "without voxtype Voice states no dictation sounds value and names voxtype" '[null,"missing"]' voice_feedback_state
expect "without voxtype a dictation sounds choice is refused" 'refused: feedback="" reason=voxtype-missing' voice_feedback_choose ""
expect "a choice refused without voxtype writes nothing" "$voice_feedback_sets_before" voice_feedback_sets_read

# The bar widget's click without voxtype: the service starts no recording,
# and the click offers voxtype and its bridge, every missing command of
# Voice, in the notice. Not now closes it; a press never rests, so a
# second click raises the notice again, as the opens below do. The install
# opens no screen after it.
expect_poll "without voxtype the bar widget reads idle" '"idle"' voice_dictation
expect_poll "without voxtype the core's daemon reads failed" "failed idle -" voice_state
expect "no notice shows before the click without voxtype" null notice_shown
voice_widget_pointer="$pointer_at"
voice_widget_point
hover "$((voice_widget_x - 1))" "$voice_widget_y" && click "$voice_widget_x" "$voice_widget_y" || fail "the click on the Voice widget without voxtype failed"
expect_poll "a click on the Voice widget without voxtype raises the notice for voxtype and its bridge" "$voice_asked" notice_shown
expect "the click without voxtype starts no recording" "failed idle -" voice_state
expect "the click's notice holds no screen to open after the install" '{}' voice_resumes
voice_notice_escape "the click's notice"
hover "$((voice_widget_x - 1))" "$voice_widget_y" && click "$voice_widget_x" "$voice_widget_y" || fail "the click on the Voice widget after Not now failed"
expect_poll "a click on the Voice widget after Not now raises the notice again" "$voice_asked" notice_shown
voice_notice_escape "the notice after Not now"
read -r voice_widget_back_x voice_widget_back_y <<<"${voice_widget_pointer:-10 $((mon_h - 10))}"
hover "$voice_widget_back_x" "$voice_widget_back_y" || fail "putting the pointer back after the click without voxtype failed"

# openTui, the route of the launcher and Dev Tools, judges the screen's
# `requires` as a press on the Settings page does: Configure without voxtype raises the
# notice for voxtype alone, the one command it requires, and opens no script.
forget_record
expect "openTui of Configure without voxtype is answered" ok ipc shell openTui vgs.voice/configure
expect_poll "openTui of Configure without voxtype raises the notice for its own command in place of its script" '["vgs.voice", ["voxtype"], ["voxtype"], false]' notice_shown
expect "the notice holds the Configure the open asked for" '{"vgs.voice": "configure"}' voice_resumes
expect_poll "the notice draws voxtype alone under its package" '[["voxtype-bin", 1]]' voice_notice_groups
expect "no Configure run is asked for while the notice shows" idle key_idle vgs.voice/configure
expect "the terminal is handed no Configure script" absent recorded
voice_notice_escape "the Configure notice"
expect "Not now drops the Configure" '{}' voice_resumes
# Control: a disposable manifest copy whose Configure requires nothing
# leaves the judge no command to find missing, so the same open launches
# the script and raises no notice.
voice_manifest="$repo/shell/plugins/vgs.voice/manifest.json"
cp -- "$voice_manifest" "$sandbox/voice-manifest-before"
expect "disabling Voice for the requires control is allowed" ok ipc shell setPluginEnabled vgs.voice false
python3 - "$voice_manifest" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1]); assert not p.is_symlink()
manifest = json.loads(p.read_text())
assert "voxtype" in manifest["tui"]["configure"]["requires"]
manifest["tui"]["configure"]["requires"] = []
p.write_text(json.dumps(manifest, indent=2) + "\n")
PY
rescan "the Voice requires control copy is scanned"
expect "enabling Voice for the requires control is allowed" ok ipc shell setPluginEnabled vgs.voice true
expect_poll "Voice builds for the requires control" True record_exists vgs.voice
voice_enabled_notice "for the requires control"
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
voice_enabled_notice "after the requires control"

# The Plugins list marks Voice Setup needed, for its missing required
# voxtype and bridge, with no separate optional-tool icon.
settings_page_open vgs.voice
expect "the window shows its list for Voice's row" '' ipc smoke invokeInstance window vgs.settings showList ''
expect_poll "the list is shown for Voice's row" '""' ipc smoke readInstance window vgs.settings page
expect_poll "without voxtype Voice's row draws Setup needed and no optional icon" "drawn absent" voice_list_marks
settings_page_close vgs.voice
settings_page_open vgs.voice
settings_setup
expect_poll "Setup keeps dictation pending without its required tools and offers Review on its row" '{"chips": [["To do", "warning"]], "buttons": [["Review all missing or outdated tools", "accent", true]]}' voice_setup_section
expect_poll "Setup groups missing required tools in one pending step" '[[["To do", "warning"]], ["Review all missing or outdated tools"]]' voice_tools_step
settings_tab_click Settings || fail "the click on Voice Settings failed"
expect_poll "Settings draws Configure alone, taking a press without voxtype" "drawn enabled, absent absent" voice_screens
settings_tab_click Details || fail "the click on Voice Details failed"
expect_poll "Details draws Choose model alone, taking a press without voxtype" "absent absent, drawn enabled" voice_screens
settings_setup
expect_poll "the Voice page offers no dictation action without voxtype" '[]' voice_offered_actions
expect_poll "the Tools step still offers its install text link" '[[["To do", "warning"]], ["Review all missing or outdated tools"]]' voice_tools_step

# Install all missing without voxtype: the notice installs voxtype and its
# bridge, and the install opens no screen after it.
forget_record
expect "Install all missing without voxtype is answered" ok ipc smoke invokeInstance window vgs.settings installRequirements vgs.voice
expect_poll "Install all missing without voxtype raises the notice" "$voice_asked" notice_shown
expect "the notice holds no screen to open after the install" '{}' voice_resumes
expect_poll "the Install all missing notice holds the keyboard for Install" true ipc smoke noticeFocused
hold_runs
type_keys -k Return || fail "sending Return to the Install all missing notice failed"
expect_poll "Install hands the terminal voxtype-bin through the AUR helper" "$(core_words core/requirements-install "Install requirements" org.vgs.tui pkg run install --manager aur voxtype-bin)" recorded
expect_poll "the notice records its install running" '["vgs.voice", ["voxtype", "voxtype-audio-bridge"], ["voxtype", "voxtype-audio-bridge"], true]' notice_shown
voice_forget
voice_engine_installed
forget_record
expect "the install stage observer starts" ok ipc smoke beginRunTrace core/requirements-install
voice_idle_start="$(now_ms)"
voice_idle_cpu_start="$(cpu_some_us)"
release_runs
expect_run_end "the voxtype install run ends" core/requirements-install
voice_idle_end="$(now_ms)"
voice_idle_pct="$(cpu_some_pct "$voice_idle_cpu_start" "$(cpu_some_us)" "$((voice_idle_end - voice_idle_start))")"
expect_poll "the scan after the install closes the notice" null notice_shown
expect_poll "Voice sees voxtype after the install" true ipc smoke readInstance service vgs.voice voxtypePresent
voice_idle_trace="$(ipc smoke endRunTrace)" || fail "the install stages are unreadable"
if ! python3 - "$rt_dir/vgshell/tui" "$voice_idle_trace" "$voice_idle_start" "$voice_idle_end" "$voice_idle_pct" "$(cat /proc/loadavg)" <<'PY_STAGES'
import datetime, glob, json, sys
try:
    records = glob.glob(sys.argv[1] + "/core@requirements-install@*.ended.json")
    if len(records) != 1:
        raise ValueError("ended-record-unavailable")
    else:
        record = json.load(open(records[0]))
        ended = round(datetime.datetime.fromisoformat(record["endedAt"].replace("Z", "+00:00")).timestamp() * 1000)
        events = json.loads(sys.argv[2])
        if not any(event["stage"] == "core-read" and event["value"]["endedAt"] == record["endedAt"] and not event["value"]["running"] for event in events):
            raise ValueError("core-ended-stage-unavailable")
        stages = [{"stage": event["stage"], "after_end_ms": event["at"] - ended, "value": event["value"]} for event in events]
        print("  run_end_stages=" + json.dumps({"run": record["run"], "presenter_end_ms": ended,
            "observer_start_after_end_ms": int(sys.argv[3]) - ended, "observer_end_after_end_ms": int(sys.argv[4]) - ended, "stages": stages}))
    print("  run_end_contention=" + json.dumps({"cpu_some_pct": None if sys.argv[5] == "unmeasured" else float(sys.argv[5]), "loadavg": sys.argv[6].split()[:3]}))
except (OSError, ValueError, TypeError, KeyError) as error:
    print("run-end-stages: unreadable=" + str(error), file=sys.stderr)
    sys.exit(1)
PY_STAGES
then fail "the install stages could not be read"; fi
expect "the terminal is handed nothing once the install ended" absent recorded
# Voice has the core start its daemon once voxtype is found: the one that
# failed without it never ran.
expect_poll "a found voxtype with no model starts no daemon" none voice_noted
expect_poll "Voice reads the daemon absent until setup" "absent idle -" voice_state
expect_poll "Set up is offered once voxtype is found and the model is missing" setup voice_setup_offered
# Set up: the page's Setup section offers it first, and its press opens
# the core's dictation setup. The stand-in terminal runs `true` for it, so
# the stub takes the state the setup leaves, which
# scripts/test-vgshell-dictation.sh reads, before the run ends; its end
# with code 0 starts the daemon again, and Voice then reads the model. The
# page opens again on its Settings tab, and the row chooses Setup.
settings_page_close vgs.voice
settings_page_open vgs.voice
settings_setup
expect_poll "Tools reads Done after every required tool is present" '[[["Done", "success"]], []]' voice_tools_step
expect_poll "the Setup section offers Set up alone" "$voice_setup_needed" voice_setup_section
expect "the Setup section draws the service's one setup line for the missing model" '{"action": "setup", "lines": 1, "drawn": true}' voice_setup_lines
voice_setup_changed="$(voice_setup_value_changed)" || fail "control: the service's Setup value is unreadable"
expect "control: a drawn line that differs from the service value reads undrawn" '{"action": "setup", "lines": 1, "drawn": false}' voice_setup_lines "$voice_setup_changed"
voice_forget
forget_record
hold_runs
expect "Set up is answered" ok settings_act vgs.voice setup
expect_poll "Set up hands the terminal core/dictation-setup" "$(core_words core/dictation-setup "Set up dictation" org.vgs.tui dictation setup)" recorded
touch -- "$voice_installed"
release_runs
expect_run_end "the dictation setup run ends" core/dictation-setup
expect_poll "the setup run's end with code 0 starts the core's daemon again" "started" voice_noted
expect_poll "Set up is withheld once the model is in place and the daemon runs" none voice_setup_offered
# Done: the required step keeps the service's state line.
expect_poll "the Setup section reads Ready and draws no step and no screen" "$voice_setup_ready" voice_setup_section
expect "the Setup section draws the service's one Ready line" '{"action": "none", "lines": 1, "drawn": true}' voice_setup_lines
settings_tab_click Settings || fail "the click on Voice Settings after installation failed"
expect_poll "Settings draws Configure alone, active with voxtype" "drawn enabled, absent absent" voice_screens
settings_tab_click Details || fail "the click on Voice Details after installation failed"
expect_poll "Details draws Choose model alone, active with voxtype" "absent absent, drawn enabled" voice_screens
settings_setup
# Control: the core's daemon ended by the row, the stand-in whose pid its
# own lock names, turns the same reading red: Setup needed, and Set up
# first. Set up's run starts a daemon, and the step reads Done.
expected_errors+=('WARN qml: dictation: daemon stderr=' 'WARN qml: dictation: daemon=failed reason=ended code=0$')
voice_daemon_pid="$(cat -- "$rt_dir/voxtype/voxtype.lock")" || voice_daemon_pid=unread
if [[ $voice_daemon_pid =~ ^[0-9]+$ && " $(dictation_processes pids) " == *" $voice_daemon_pid "* ]]; then
  kill -TERM "$voice_daemon_pid" || fail "control: the stand-in daemon could not be ended"
else
  fail "control: the stand-in daemon's pid is unreadable: $voice_daemon_pid"
fi
expect_poll "control: Voice reads the ended daemon failed" "failed idle -" voice_state
expect_poll "control: an ended daemon draws Setup needed with Set up first" "$voice_setup_needed" voice_setup_section
expect "control: the Setup section draws the service's one setup line for the ended daemon" '{"action": "setup", "lines": 1, "drawn": true}' voice_setup_lines
# Keep the child failure true while these starts retry. A repaired child
# correctly reaches ready and cannot be a continuing-failure control.
: >"$sandbox/voxtype-daemon-fail"
expected_errors+=('WARN qml: voice: start refused: dictation=daemon-starting' 'WARN qml: dictation: daemon=failed reason=ended code=1$')
settings_page_close vgs.voice
expect "the toggle shortcut delivers the failed-state retry" ok hypr dispatch 'hl.dsp.global("vgs.voice:toggle")'
expect_poll "the failed toggle opens the existing correction window" 1 window_count Plugins
expect_poll "the failed toggle shows Voice Setup" '"vgs.voice/Setup"' ipc smoke readInstance window vgs.settings shownPage
expect_poll "the failed toggle draws the existing setup action" "$voice_setup_needed" voice_setup_section
expect_poll "the pending toggle retry publishes the actual continuing failure" "failed idle -" voice_state
expect "the failed toggle draws the current failure lines" '{"action": "setup", "lines": 1, "drawn": true}' voice_setup_lines
settings_page_close vgs.voice
voice_widget_point
hover "$((voice_widget_x - 1))" "$voice_widget_y" && click "$voice_widget_x" "$voice_widget_y" || fail "the failed daemon microphone click failed"
expect_poll "the failed microphone click opens the existing correction window" 1 window_count Plugins
expect_poll "the failed microphone click shows Voice Setup" '"vgs.voice/Setup"' ipc smoke readInstance window vgs.settings shownPage
expect_poll "the failed microphone click draws the existing setup action" "$voice_setup_needed" voice_setup_section
expect_poll "the pending microphone retry publishes the actual continuing failure" "failed idle -" voice_state
expect_poll "continuing failure leaves no child or follower" 'daemon=0 follower=0 other=0' dictation_processes all
# Control: remove the pending result from the same correction branch.
# The child still fails, but the same user start no longer opens its page.
settings_page_close vgs.voice
voice_pending_file="$repo/shell/plugins/vgs.voice/Service.qml"
cp -- "$voice_pending_file" "$sandbox/voice-pending-before"
expect "disabling Voice for the pending correction control is allowed" ok ipc shell setPluginEnabled vgs.voice false
python3 - "$voice_pending_file" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); assert not p.is_symlink()
needle = ' || answer === "refused: dictation=daemon-starting"'
s = p.read_text(); assert s.count(needle) == 1
changed = s.replace(needle, ""); assert changed != s
p.write_text(changed)
PY
rescan "the Voice pending correction control copy is scanned"
expect "enabling Voice for the pending correction control is allowed" ok ipc shell setPluginEnabled vgs.voice true
expect_poll "control: Voice reads the continuing child failure" "failed idle -" voice_state
expect "control: a user start still reports pending" 'refused: dictation=daemon-starting' voice_toggle
expect_poll "control: the pending retry still ends in actual failure" "failed idle -" voice_state
expect "control: ignoring pending leaves the correction window closed" 0 window_count Plugins
expect "disabling Voice after the pending correction control is allowed" ok ipc shell setPluginEnabled vgs.voice false
cp -- "$sandbox/voice-pending-before" "$voice_pending_file"
rescan "the shipped Voice correction branch is scanned again"
expect "enabling Voice after the pending correction control is allowed" ok ipc shell setPluginEnabled vgs.voice true
expect_poll "the restored service reads the continuing child failure" "failed idle -" voice_state
: >"$sandbox/voxtype-loading"
rm -f -- "${sandbox:?}/voxtype-daemon-fail"
settings_page_open vgs.voice
settings_setup
voice_forget
forget_record
expect "Set up after the ended daemon is answered" ok settings_act vgs.voice setup
expect_poll "Set up hands the terminal core/dictation-setup again" "$(core_words core/dictation-setup "Set up dictation" org.vgs.tui dictation setup)" recorded
expect_run_end "the second dictation setup run ends" core/dictation-setup
expect_poll "the second setup run's end starts a daemon" started voice_noted
expect_poll "repaired setup keeps the child starting while its model loads" "starting idle -" voice_state
voice_setup_pending() { ipc smoke readInstance service vgs.voice dictationState | py_reply 'import json,sys; d=json.load(sys.stdin); s=d["setup"]; print(d["daemon"], s["compiled"], s["installed"])'; }
expect "the pending child already has completed engine and model readings" 'starting True True' voice_setup_pending
voice_setup_phase() { ipc smoke readInstance service vgs.voice setupValue | py_reply 'import json,sys; s=json.load(sys.stdin); print(json.dumps([s["tone"], s["action"], s["lines"]]))'; }
expect "pending setup publishes information without a failure or action" '["info", "", []]' voice_setup_phase
rm -f -- "${sandbox:?}/voxtype-loading"
expect_poll "the Setup section reads Ready again" "$voice_setup_ready" voice_setup_section
expect_poll "the three dictation shortcuts and the release companion are registered after setup" 4 voice_shortcuts
expect_poll "the daemon reads idle before the test dictation" "ready idle -" voice_state
voice_forget
expect "the toggle shortcut reaches Voice" ok hypr dispatch 'hl.dsp.global("vgs.voice:toggle")'
expect_poll "a test dictation starts a recording through the core" "ready recording vgs.voice" voice_state
expect "the toggle shortcut reaches Voice again" ok hypr dispatch 'hl.dsp.global("vgs.voice:toggle")'
expect_poll "the test dictation is stopped and typed" "start stop" voice_noted
expect_poll "the wtype stand-in typed the test dictation" "-d 10 -- the stand-in heard this" voice_last_typed
expect_poll "the daemon reads idle after the test dictation" "ready idle -" voice_state
settings_page_close vgs.voice

# Stop the other voxtype: a stand-in daemon the row starts, as a voxtype
# user unit runs one, holds the place the core's daemon takes. Voice reads
# it elsewhere and Settings offers its stop action; the row ends that daemon
# while the step's run is held, as the step's systemctl would, and the
# run's end with code 0 has the core start its own daemon in the same
# shell.
voice_own_pid=""
voice_own_daemon() {
  "${shell_env[@]}" PATH="$shell_start_path" "$voice_stub" daemon >>"$sandbox/voice-own-daemon.log" 2>&1 &
  voice_own_pid=$!
}
voice_own_state() { "${shell_env[@]}" PATH="$shell_start_path" "$voice_stub" status --format json | py_reply 'import json,sys; print(json.load(sys.stdin)["alt"])'; }
voice_own_end() {
  [[ -z $voice_own_pid ]] || { kill -TERM "$voice_own_pid" 2>/dev/null || true; wait "$voice_own_pid" 2>/dev/null || true; }
  voice_own_pid=""
}
# The shell's start time in clock ticks, field 22 of /proc/PID/stat: the
# same value while no shell has started in its place; `gone` once it ends.
voice_shell_start() {
  python3 - "$shell_qs_pid" <<'PY'
import sys
try:
    print(open(f"/proc/{sys.argv[1]}/stat").read().rsplit(")", 1)[1].split()[19])
except (OSError, IndexError):
    print("gone")
PY
}
# The stop-other run as Voice's service reads it, shell.tui.state: `ended
# code=N` once it reads an end other than BEFORE, the endedAt before the
# run, else `waiting`. The service restarts the daemon in the handler of
# that same change, so a restart it asks for has begun once this reads
# ended.
voice_stop_other_end() { ipc smoke readInstance service vgs.voice tuiState | py_reply 'import json,sys; r=(json.load(sys.stdin) or {}).get("stop-other") or {}; print(json.dumps(r.get("endedAt")))'; }
voice_stop_other_ended() { # BEFORE
  ipc smoke readInstance service vgs.voice tuiState | py_reply '
import json,sys
r=(json.load(sys.stdin) or {}).get("stop-other") or {}
ended=r.get("endedAt")
print("ended code=%s" % r.get("code") if ended is not None and json.dumps(ended) != sys.argv[1] and not r.get("running") else "waiting")
' "$1"
}
# What the stand-in's daemons note over MS milliseconds: the first note,
# or `none` when they note nothing in that time.
voice_noted_within() { # MS
  local until=$(( $(now_ms) + $1 ))
  while [[ $(voice_noted) == none ]] && (( $(now_ms) < until )); do sleep 0.2; done
  voice_noted
}
# voice_stop_other LABEL: from Voice enabled over the core's daemon, the
# row's own daemon holds the place, Voice offers the step, the step's run
# is held while that daemon ends, and the run ends; the stand-in's notes
# are forgotten after that daemon's end, so a start after it is the core's.
voice_stop_other() { # LABEL
  expect "$1: disabling Voice is allowed" ok ipc shell setPluginEnabled vgs.voice false
  expect_poll "$1: disabling Voice ends the core's daemon" "daemon=0 follower=0 other=0" dictation_processes all
  voice_own_daemon
  expect_poll "$1: the row's own stand-in daemon answers" idle voice_own_state
  expect "$1: the row's own daemon is the one stand-in process, no child of the shell" "daemon=1 follower=0 other=0" dictation_processes all
  expect "$1: the row's own daemon contributes no shell-owned role" "daemon=0 follower=0 other=0" dictation_processes owned
  voice_forget
  expect "$1: enabling Voice beside that daemon is allowed" ok ipc shell setPluginEnabled vgs.voice true
  expect_poll "$1: Voice builds beside that daemon" True record_exists vgs.voice
  expect_poll "$1: Voice reads that daemon elsewhere" "elsewhere idle -" voice_state
  expect "$1: the core tried no second daemon" none voice_noted
  expect_poll "$1: Voice reports another voxtype to stop" stop voice_setup_offered
  settings_page_open vgs.voice
  settings_setup
  expect_poll "$1: Setup stays To do and offers no stop action" '{"chips": [["To do", "warning"]], "buttons": []}' voice_setup_section
  settings_page_close vgs.voice
  expect "$1: a start beside the other daemon is refused" "refused: dictation=daemon-elsewhere" voice_toggle
  expect_poll "$1: the foreign daemon refusal opens the correction window" 1 window_count Plugins
  expect_poll "$1: the foreign daemon refusal opens Voice Details" '"vgs.voice/Details"' ipc smoke readInstance window vgs.settings shownPage
  expect_poll "$1: Details offers Stop beside Other dictation service" '["", [["Stop the other voxtype", true]]]' voice_other_service
  voice_stop_other_before="$(voice_stop_other_end)" || voice_stop_other_before=unread
  forget_record
  hold_runs
  expect "$1: Stop the other voxtype is answered" ok settings_act vgs.voice otherService
  expect_poll "$1: Stop the other voxtype hands the terminal its screen" "$(words vgs.voice/stop-other tui/stop-other.sh)" recorded_tail
  voice_own_end
  expect_poll "$1: the row's own daemon is gone while the run is held" "daemon=0 follower=0 other=0" dictation_processes all
  voice_forget
  release_runs
  expect_run_end "$1: the Stop the other voxtype run ends" vgs.voice/stop-other
  voice_stop_other_at="$(now_ms)"
  expect_poll "$1: Voice reads the run's end with code 0" "ended code=0" voice_stop_other_ended "$voice_stop_other_before"
  forget_record
  settings_page_close vgs.voice
}
if [[ $(shell_resolves systemctl) == none ]]; then
  fail "the shell resolves no systemctl, which Stop the other voxtype requires, so its press would raise a notice"
fi
voice_shell_started="$(voice_shell_start)"
expected_errors+=('WARN qml: voice: start refused: dictation=daemon-elsewhere')
voice_stop_other "Stop the other voxtype"
expect_poll "the run's end with code 0 has the core start its own daemon" started voice_noted
voice_restart_ms="$(( $(now_ms) - voice_stop_other_at ))"
expect_poll "Voice reads the core's own daemon ready" "ready idle -" voice_state
expect_poll "the core's daemon and follower run, children of the shell" "daemon=1 follower=1 other=0" dictation_processes owned
expect "the core started its daemon once" started voice_noted
expect_poll "nothing is offered once the core's daemon runs" none voice_setup_offered
expect "the shell is the one that ran before the step, with no restart" "$voice_shell_started" voice_shell_start
# Control: a disposable copy of VoiceLogic.js whose RESTART_TUIS leaves out
# stop-other, today's probe, restarts nothing at the same run's end: the
# daemon still reads elsewhere, though the row's own daemon is gone. The
# service's handler that would restart has run once Voice reads the end,
# so the core's record reads elsewhere then; the stand-in's notes are read
# over three times the shipped restart's time, at least two seconds.
voice_restart_file="$repo/shell/plugins/vgs.voice/VoiceLogic.js"
cp -- "$voice_restart_file" "$sandbox/voice-restart-before"
expect "disabling Voice for the stop-other control is allowed" ok ipc shell setPluginEnabled vgs.voice false
python3 - "$voice_restart_file" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); assert not p.is_symlink()
needle, replacement = 'var RESTART_TUIS = ["configure", "model", "stop-other"];', 'var RESTART_TUIS = ["configure", "model"];'
s = p.read_text(); assert s.count(needle) == 1
changed = s.replace(needle, replacement); assert changed != s
p.write_text(changed)
PY
rescan "the Voice stop-other control copy is scanned"
expect "enabling Voice for the stop-other control is allowed" ok ipc shell setPluginEnabled vgs.voice true
expect_poll "Voice builds for the stop-other control" True record_exists vgs.voice
expect_poll "control: the copy reads the core's daemon ready" "ready idle -" voice_state
voice_stop_other "control"
expect "control: once Voice reads the end, the core's record still reads the daemon elsewhere" "elsewhere none vgs.voice" dictation_lent
voice_settle_ms=$(( voice_restart_ms * 3 > 2000 ? voice_restart_ms * 3 : 2000 ))
expect "control: a run end that restarts nothing has the core start no daemon in ${voice_settle_ms} ms" none voice_noted_within "$voice_settle_ms"
expect "control: Voice still reads the daemon elsewhere" "elsewhere idle -" voice_state
expect "control: Voice still reports the other service to stop" stop voice_setup_offered
expect "control: no stand-in daemon runs" "daemon=0 follower=0 other=0" dictation_processes all
expect "disabling Voice after the stop-other control is allowed" ok ipc shell setPluginEnabled vgs.voice false
cp -- "$sandbox/voice-restart-before" "$voice_restart_file"
rescan "the shipped Voice logic is scanned again after the stop-other control"
expect "enabling Voice after the stop-other control is allowed" ok ipc shell setPluginEnabled vgs.voice true
expect_poll "Voice builds after the stop-other control" True record_exists vgs.voice
expect_poll "Voice reads the core's daemon ready after the stop-other control" "ready idle -" voice_state
expect_poll "one daemon and one follower run after the stop-other control" "daemon=1 follower=1 other=0" dictation_processes owned
expect_poll "nothing is offered after the stop-other control" none voice_setup_offered
expect "the shell is still the one that ran before the step" "$voice_shell_started" voice_shell_start
expect "disabling Voice after the setup rows is allowed" ok ipc shell setPluginEnabled vgs.voice false
expect_poll "disabling Voice after the setup rows ends the core's daemon" "daemon=0 follower=0 other=0" dictation_processes all
# The stand-in's lock beside an ended holder: a child that ended under a
# parent that never reaps it is written to voxtype.lock. It reads state Z
# and still takes signal 0. Control first, while the lock names it: a copy
# of the stand-in whose daemon_pid is the signal 0 check refuses its
# daemon. The stand-in then starts its daemon over the same lock, and
# refuses a second one beside that live daemon.
voice_zombie_file="$sandbox/voice-zombie-pid"
voice_signal0="$sandbox/voice-signal0"
voice_zombie_state() { { awk '{ print $3 }' "/proc/$(cat -- "$voice_zombie_file")/stat" || echo gone; } 2>/dev/null; }
voice_zombie_signal() { if kill -0 "$(cat -- "$voice_zombie_file")" 2>/dev/null; then echo taken; else echo refused; fi; }
# voice_daemon_try STUB NOTES: the exit of STUB's daemon, ended after 20
# seconds when it starts, and what it noted.
voice_daemon_try() { # STUB NOTES
  local status=0
  timeout 20 "${shell_env[@]}" PATH="$shell_start_path" "$1" daemon >>"$sandbox/voice-own-daemon.log" 2>&1 || status=$?
  echo "exit=$status notes=$(tr '\n' ' ' <"$2" | sed 's/ $//')"
}
rm -rf -- "${voice_signal0:?}"
mkdir -p -- "$voice_signal0/bin"
python3 - "$repo/scripts/smoke/fixtures/voxtype/voxtype" "$voice_signal0/bin/voxtype" <<'PY'
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text()
opening = "daemon_pid() {\n"
assert s.count(opening) == 1
start = s.index(opening); end = s.index("\n}\n", start) + 3
signal0 = opening + '  local pid\n  pid="$(cat -- "$lock" 2>/dev/null)" && [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null && printf \'%s\\n\' "$pid"\n}\n'
assert s[start:end] != signal0
Path(sys.argv[2]).write_text(s[:start] + signal0 + s[end:])
PY
chmod 755 "$voice_signal0/bin/voxtype"
# Hold the old Bash form before exec. A gone child while that Bash still
# runs proves its SIGCHLD handler reaped the child, before any adoption.
voice_zombie_old="$(timeout 20 python3 - "$BASH" <<'PY'
import os, pathlib, select, subprocess, sys, time
parent = subprocess.Popen([sys.argv[1], "-c", 'true & printf "%s\\n" "$!"; read -r gate; exec sleep 600'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
try:
    child = int(parent.stdout.readline())
    stat = pathlib.Path(f"/proc/{child}/stat")
    deadline = time.monotonic() + 5
    while stat.exists() and time.monotonic() < deadline:
        select.select([], [], [], 0.01)
    state = "present" if stat.exists() else "gone"
    executable = pathlib.Path(os.readlink(f"/proc/{parent.pid}/exe")).name
    print(f"{state} parent={executable}" if parent.poll() is None else "parent=ended")
finally:
    parent.terminate()
    parent.communicate(timeout=5)
PY
)"
expect "control: the old holder is reaped by Bash before exec" "gone parent=bash" echo "$voice_zombie_old"
rm -f -- "${voice_zombie_file:?}"
# The child cannot end until exec closes the parent's pipe writer. The
# replacement parent waits for a signal and never reaps the ended child.
python3 - "$voice_zombie_file" <<'PY' &
import os, pathlib, sys
reader, writer = os.pipe2(os.O_CLOEXEC)
child = os.fork()
if child == 0:
    os.close(writer)
    os.read(reader, 1)
    os._exit(0)
os.close(reader)
pathlib.Path(sys.argv[1]).write_text(f"{child}\n")
os.execl(sys.executable, sys.executable, "-c", "import signal; signal.pause()")
PY
voice_zombie_parent=$!
expect_poll "the planted lock holder has ended and is not reaped" Z voice_zombie_state
expect "the planted lock holder still takes signal 0" taken voice_zombie_signal
cp -- "$voice_zombie_file" "$rt_dir/voxtype/voxtype.lock"
voice_forget
expect "control: the signal 0 copy refuses its daemon beside the planted holder" "exit=1 notes=refused" voice_daemon_try "$voice_signal0/bin/voxtype" "$voice_signal0/voxtype-daemon.log"
expect "the planted holder is still unreaped after the control" Z voice_zombie_state
expect "the planted holder is still the lock's after the control" "$(cat -- "$voice_zombie_file")" cat -- "$rt_dir/voxtype/voxtype.lock"
voice_own_daemon
expect_poll "the stand-in reads idle beside the planted holder" idle voice_own_state
expect "the stand-in started its daemon beside the planted holder" started voice_noted
voice_forget
expect "a second daemon beside the live one is refused" "exit=1 notes=refused" voice_daemon_try "$voice_stub" "$voice_notes"
expect "the live daemon still answers after the refusal" idle voice_own_state
voice_own_end
expect_poll "the row's own daemon is gone after the lock case" "daemon=0 follower=0 other=0" dictation_processes all
kill -TERM "$voice_zombie_parent" 2>/dev/null || true
wait "$voice_zombie_parent" 2>/dev/null || true
rm -rf -- "${voice_zombie_file:?}" "${voice_signal0:?}"
cp -- "$voice_pkg_real" "$repo/bin/vgshell-pkg.next" && mv -T -- "$repo/bin/vgshell-pkg.next" "$repo/bin/vgshell-pkg"
voice_engine_removed
rm -f -- "${voice_installed:?}" "${voice_cap:?}" "${voice_words:?}" "${voice_transcribing:?}"
voice_forget
rescan "rescan after removing the Voice stubs again"
cp -- "$voice_saved_config" "$home/.config/vgshell/shell.json.next" && mv -T -- "$home/.config/vgshell/shell.json.next" "$home/.config/vgshell/shell.json"
expect "the shell.json Voice found is reloaded" ok ipc shell reloadConfig
read -r voice_pointer_x voice_pointer_y <<<"$voice_pointer"
hover "$voice_pointer_x" "$voice_pointer_y" || fail "Voice puts the pointer back where it found it"
