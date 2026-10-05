# Sound, vgs.sound, over the sandbox's private PipeWire (S08,
# scripts/smoke/devices.sh): two null sinks, the speakers and the
# headphones, a filter chain in front of the speakers and one test source.
# devices_audio_play plays Smoke Player, a test stream, in the sandbox's
# environment alone. pactl is the harness's recording stand-in, whose
# `--format=json list sink-inputs` answer the row plants: the player,
# EasyEffects' output, a filter chain's output and a stream no app owns,
# as pipewire-pulse lists them. For the row, recording stand-ins that run
# the real command after they record also take wpctl, pw-cli, pw-cat,
# pw-play, pw-metadata, pamixer and amixer from the shell's PATH, so a
# process an audio widget would start shows. The row reads every volume,
# mute, default and link from the private PipeWire itself through
# devices_audio, never only from the plugin, and reads:
# - an app that starts while the pane is open getting its row;
# - the widget following a volume set by a click on the pane's output
#   slider, and the wheel and a middle click on the widget changing the
#   volume and the mute while no stand-in records a call;
# - a keyboard-only path: SUPER+COMMA opens System on the Sound section,
#   Enter enters it, Down on the output's Select chooses the headphones,
#   which become WirePlumber's default while pactl is asked to move the
#   player alone, then Tab reaches each control in turn, the output's mute
#   button and slider, the input's Select, mute button and slider and the
#   player's mute button and slider, Space mutes and unmutes through each
#   button and Down and Up step each slider, and Escape twice closes the
#   window;
# - the volume keys stepping by 5%, then by 10% once the setting says so,
#   a level above 100% kept by a step up and stepped down from, and the
#   display on the focused output alone of two, gone after `osd.duration`;
# - the Settings Keys row offering Use my binding for XF86AudioMicMute,
#   which a user bind holds, and its click unbinding the shortcut so the
#   user's bind takes the key;
# - with the filter chain as the default, Down on the slider lowering the
#   speakers it plays to and leaving the filter's own volume;
# - PipeWire stopped giving the unavailable state in the widget, the pane
#   and the service, and the widget reading the speakers once it starts,
#   both after a lost connection and in a shell that started while
#   PipeWire was stopped.
#
# Controls, each on a copy that wins over the shipped file: one user copy
# of the plugin whose widget's middle click runs wpctl, whose service runs
# no pactl after an output choice, whose Audio resolves no DSP sink, caps
# a step at 100%, builds its app rows once per snapshot, and whose display
# ignores the focused output; a Settings copy whose Use my binding sends
# the key in effect; and a tree copy whose runner leaves out the PipeWire
# reconnect variable.
#
# The row reads no latency; each reading polls every 200 ms for up to 5 s,
# as expect_poll does, and an absence stays absent for that bound. It
# leaves the user file, the plugins directory, the nested hyprland.lua and
# outputs, vgs.system's and vgs.sound's enablement, the shell's PATH
# directory and the pactl stand-in's replies as it found them, a shell
# started from the repository running, and the private PipeWire up.
# inputs: shell/plugins/vgs.sound/* shell/plugins/vgs.system/* shell/plugins/vgs.settings/* shell/Commons/Reply.js shell/Ui/controls/LevelSlider.qml shell/Ui/feedback/LevelLabel.qml shell/Ui/feedback/LevelOsd.qml shell/Ui/controls/ShortcutField.qml shell/Ui/controls/BindField.qml shell/Hosts/PaneHost.qml shell/Hosts/LayerHost.qml shell/Core/Layers.qml shell/Core/Capabilities.qml shell/Core/PluginStatus.qml shell/Core/ShortcutRegistry.qml shell/Core/IpcRegistry.qml shell/Core/Notices.qml shell/Core/HyprlandLayer.* shell/Core/HyprlandState.* bin/vgshell scripts/smoke/fixtures/devices/* scripts/smoke/rows/device-fakes.sh scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail
devices_ready sound || return 0

snd_file="$home/.config/vgshell/shell.json"
snd_saved="$sandbox/shell-before-sound.json"
snd_copy="$home/.config/vgshell/plugins/vgs.sound"
snd_settings_copy="$home/.config/vgshell/plugins/vgs.settings"
snd_spawns="$sandbox/sound-spawns.calls"
snd_recorded=(wpctl pw-cli pw-cat pw-play pw-metadata pamixer amixer)
snd_output=SMOKE-SOUND
cp -- "$snd_file" "$snd_saved"
read -r mon_w mon_h < <(hypr -j monitors | py_reply 'import json,sys; m=json.load(sys.stdin)[0]; print(m["width"], m["height"])')
snd_system_was="$(plugin_enabled vgs.system)" || fail "vgs.system's enabled state is unreadable"
snd_sound_was="$(plugin_enabled vgs.sound)" || fail "vgs.sound's enabled state is unreadable"
expect "disabling Sound before its row is allowed" ok ipc shell setPluginEnabled vgs.sound false
expect_poll "Sound starts the row disabled" False plugin_enabled vgs.sound
expect "no user copy of vgs.sound is installed" no bash -c '[[ -e $1 ]] && echo yes || echo no' _ "$snd_copy"

# Readings. snd_audio PATH: one value of devices_audio's object, by a
# Python subscript such as ["defaults"]["sink"]. snd_volume NAME: that
# node's volume as a whole percentage.
snd_audio() { devices_audio | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps(eval("d" + sys.argv[1])))' "$1"; }
snd_volume() { devices_audio | py_reply 'import json,sys; n=json.load(sys.stdin)["nodes"].get(sys.argv[1]); print(round(n[0] * 100) if n else "absent")' "$1"; }
snd_muted() { snd_audio "[\"nodes\"][\"$1\"][1]"; }
snd_widget() { ipc smoke readInstance "$(bar_key)" vgs.sound "$1"; }
# The Settings page's buttons that draw Use my binding.
snd_use_mine() { ipc smoke itemTexts window vgs.settings Button | py_reply 'import json,sys; print(sum("Use my binding" in texts for texts in json.load(sys.stdin)))'; }
snd_status() { ipc smoke statusValues vgs.sound | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin).get("streams"), sort_keys=True))'; }
snd_binds() { hypr -j binds | py_reply 'import json,sys; print(json.dumps(sorted([b["key"], b["description"]] for b in json.load(sys.stdin) if b["description"].startswith("vgs.sound:") and b.get("submap", "") in ("", "default"))))'; }
snd_pactl() { device_calls pactl; }
# Every call the device stand-ins and the row's recorders took, so a
# process the widget starts under any of those names shows.
snd_calls_all() { local name out=""; for name in "${device_stand_in_names[@]}"; do out+="$name=$(device_calls "$name");"; done; printf '%s spawns=%s\n' "$out" "$(cat -- "$snd_spawns" 2>/dev/null)"; }
snd_spawned() { [[ -s $snd_spawns ]] && python3 -c 'import json,sys; print(json.dumps([json.loads(l) for l in open(sys.argv[1])]))' "$snd_spawns" || echo '[]'; }
snd_focus() { ipc smoke activeFocusItem window vgs.sound; }
snd_placed() { bar_widget_ids | py_reply 'import json,sys; print(any("vgs.sound" in ids for ids in json.load(sys.stdin)))'; }
snd_search_focused() { [[ $(ipc smoke activeFocusItem window vgs.system) == *TextField* ]] && echo true || echo false; }
snd_texts_hold() { ipc smoke itemTexts window vgs.sound "$1" | py_reply 'import json,sys; print(json.dumps(any(sys.argv[1] in t for row in json.load(sys.stdin) for t in row)))' "$2"; }
snd_marker() { [[ -f $1 ]] && echo 1 || echo 0; }
snd_changed() { [[ $(snd_volume "$1") != "$2" ]] && echo changed || echo same; }
snd_tooltip_names() { [[ $(snd_widget tooltip) == "\"$1: "* ]] && echo true || echo false; }
snd_osd() { ipc smoke layerWindows vgs.sound | py_reply 'import json,sys; print(json.dumps(sorted(w["screen"] for w in json.load(sys.stdin) if w["shown"])))'; }
snd_osd_screens() { ipc smoke layerWindows vgs.sound | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
snd_osd_text() { ipc smoke layerItems vgs.sound LevelOsd text,visible | py_reply 'import json,sys; print(json.dumps([r[2]["text"] for r in json.load(sys.stdin) if r[2]["visible"]]))'; }
snd_focused_screen() { hypr -j monitors | py_reply 'import json,sys; print(json.dumps([m["name"] for m in json.load(sys.stdin) if m["focused"]]))'; }
snd_all_screens() { hypr -j monitors | py_reply 'import json,sys; print(json.dumps(sorted(m["name"] for m in json.load(sys.stdin))))'; }
snd_pgid_kept() { local g; for g in "${pgids[@]}"; do [[ $g == "${devices_pid[pipewire]}" ]] && { echo kept; return; }; done; echo lost; }
# snd_stays WANT CMD...: `stayed` when CMD reads WANT at every 200 ms
# poll for 5 s, the bound each expect_poll gives the change it waits for,
# else what it read instead.
snd_stays() {
  local want="$1" got
  shift
  for _ in $(seq 1 25); do
    got="$("$@" 2>&1)" || true
    [[ $got == "$want" ]] || { printf '%s\n' "$got"; return; }
    sleep 0.2
  done
  echo stayed
}
# snd_row_set KEY JSON: vgs.sound's plugins row in the user file with KEY
# set to the JSON value, or removed for `-`, the rest of the file as it
# was; the caller reloads the configuration.
snd_row_set() {
  python3 - "$snd_file" "$1" "$2" <<'PY'
import json, os, sys
path, key, value = sys.argv[1:]
doc = json.load(open(path))
rows = doc.setdefault("plugins", [])
row = next((r for r in rows if r["id"] == "vgs.sound"), None)
if row is None:
    row = {"id": "vgs.sound"}
    rows.append(row)
if value == "-": row.pop(key, None)
else: row[key] = json.loads(value)
json.dump(doc, open(path + ".next", "w"))
os.replace(path + ".next", path)
PY
}
snd_key() { python3 -c 'import json,sys; rows=[r for r in json.load(open(sys.argv[1])).get("plugins", []) if r["id"] == "vgs.sound"]; k=rows[0].get("keys", {}) if rows else {}; print(json.dumps(k[sys.argv[2]]) if sys.argv[2] in k else "absent")' "$snd_file" "$1"; }
# snd_at_widget: the layout point at the widget's centre, as `X Y`.
snd_at_widget() { local rect; rect="$(ipc smoke instanceGeometry "$(bar_key)" vgs.sound)" && at_centre vgs:bar "$rect"; }
# snd_slider_at SHARE: the layout point SHARE along the pane's output
# slider, the first Slider the pane draws, as `X Y`.
snd_slider_at() {
  local rect
  rect="$(ipc smoke descendantGeometry window vgs.sound | py_reply 'import json,sys; r=[i["box"] for i in json.load(sys.stdin) if i["type"] == "Slider" and i["visible"]]; print(json.dumps(r[0]) if r else "absent")')" || return 1
  [[ $rect == \[* ]] || { echo "snd_slider_at: no slider: $rect" >&2; return 1; }
  read -r x y < <(at_centre window:System "$rect") || return 1
  python3 -c 'import json,sys; r=json.loads(sys.argv[1]); print(int(int(sys.argv[2]) - r[2] / 2 + r[2] * float(sys.argv[4])), sys.argv[3])' "$rect" "$x" "$y" "$1"
}
# snd_key_step LABEL KEY NODE WANT: KEY typed on the nested seat and NODE's
# volume read as WANT, with the display reading WANT% on the focused
# output alone.
snd_key_step() {
  type_keys -k "$2" || fail "$1: $2 failed"
  expect_poll "$1" "$4" snd_volume "$3"
  expect_poll "$1: the display reads the level" "[\"$4%\"]" snd_osd_text
}
# The answer pactl's stand-in gives `--format=json list sink-inputs`.
snd_inputs='[{"index":42,"sink":1,"properties":{"application.name":"Smoke Player","node.name":"smoke-player"}},{"index":43,"sink":1,"properties":{"application.name":"EasyEffects","node.name":"ee_soe_output_level"}},{"index":44,"sink":1,"properties":{"application.name":"pipewire","node.name":"vgs-smoke-equalizer.output","node.link-group":"filter-chain-smoke"}},{"index":45,"sink":1,"properties":{"node.name":"alsa_playback.speaker-test"}}]'
snd_list='[["--format=json", "list", "sink-inputs"]'

# snd_plugin_copy FILE OLD NEW...: a user copy of vgs.sound with each OLD,
# which must occur once in FILE, replaced by NEW.
snd_plugin_copy() {
  rm -rf -- "${snd_copy:?}"
  cp -R -- "$repo/shell/plugins/vgs.sound" "$snd_copy"
  python3 - "$snd_copy" "$@" <<'PY'
import os, sys
root, edits = sys.argv[1], sys.argv[2:]
for i in range(0, len(edits), 3):
    path = os.path.join(root, edits[i])
    text = open(path).read()
    assert text.count(edits[i + 1]) == 1, edits[i + 1]
    open(path, "w").write(text.replace(edits[i + 1], edits[i + 2]))
PY
}

# The recorders: each name in the shell's PATH directory records its argv
# as one JSON line, then runs the host's command when there is one.
: >"$snd_spawns"
for snd_name in "${snd_recorded[@]}"; do
  [[ ! -e $shim/$snd_name ]] || fail "the shell's PATH directory already holds $snd_name"
  snd_real="$(PATH="$shell_start_path" command -v -- "$snd_name" || true)"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'python3 -c %q "$0" "$@" >>%q\n' 'import json,os,sys; print(json.dumps([os.path.basename(sys.argv[1])] + sys.argv[2:]))' "$snd_spawns"
    if [[ -n $snd_real ]]; then printf 'exec %q "$@"\n' "$snd_real"; else printf 'exit 127\n'; fi
  } >"$shim/$snd_name"
  chmod 755 "$shim/$snd_name"
done

device_reply_clear pactl
rm -f -- "${devices_dir:?}/calls/pactl.calls"
device_reply pactl 0 "$snd_inputs" --format=json list sink-inputs
for snd_sink in vgs-smoke-speakers vgs-smoke-headphones vgs-smoke-equalizer; do device_reply pactl 0 "" move-sink-input 42 "$snd_sink"; done
expect_poll "the filter chain plays to the speakers" true snd_audio '["links"].__contains__(["vgs-smoke-equalizer.output", "vgs-smoke-speakers"])'
expect "the speakers start as WirePlumber's default" '"vgs-smoke-speakers"' snd_audio '["defaults"]["sink"]'

expect "enabling the System window is allowed" ok ipc shell setPluginEnabled vgs.system true
expect "enabling Sound is allowed" ok ipc shell setPluginEnabled vgs.sound true
expect_poll "the Sound widget is placed in the bar" True snd_placed
snd_all_binds='[["XF86AUDIOLOWERVOLUME", "vgs.sound:volume-down"], ["XF86AUDIOMICMUTE", "vgs.sound:mic-mute"], ["XF86AUDIOMUTE", "vgs.sound:mute"], ["XF86AUDIORAISEVOLUME", "vgs.sound:volume-up"]]'
expect_poll "the Hyprland layer binds the four audio keys to the Sound shortcuts" "$snd_all_binds" snd_binds
expect_poll "with pactl on PATH the service says playing apps move" '{"text": "Apps that play now move to the output you choose.", "tone": "ok"}' snd_status
speakers="$(snd_volume vgs-smoke-speakers)"
expect_poll "the widget reads the speakers' level from PipeWire" "\"Smoke Speakers: ${speakers}%\"" snd_widget tooltip

# An app that starts while the pane is open gets its row once PipeWire
# hands its properties to the bound stream.
expect "System opens on the Sound section" ok ipc shell summon window vgs.system '{"pane":"vgs.sound"}'
expect_poll "the Sound pane is mounted" '["vgs.sound"]' window_panes
expect "no app plays before the player starts" false snd_texts_hold FormRow 'Smoke Player'
devices_audio_play
expect_poll "the test stream plays to the speakers" true snd_audio '["links"].__contains__(["smoke-player", "vgs-smoke-speakers"])'
expect_poll "the open pane lists the app that started" true snd_texts_hold FormRow 'Smoke Player'

# A click on the output slider sets the volume, and the widget follows it.
read -r sx sy < <(snd_slider_at 0.3) || fail "the pane's output slider has no box"
hover "$sx" "$sy" || fail "hovering the output slider failed"
click "$sx" "$sy" || fail "the click on the output slider failed"
expect_poll "the click moved the speakers' volume" changed snd_changed vgs-smoke-speakers "$speakers"
speakers="$(snd_volume vgs-smoke-speakers)"
expect_poll "the widget follows the volume set in the pane" "\"Smoke Speakers: ${speakers}%\"" snd_widget tooltip
expect "the pane's level reads the same volume" true snd_texts_hold LevelSlider "$speakers%"
expect "System hides" ok ipc shell hide window vgs.system

# The widget's wheel and middle click go through the service and start no
# process.
calls_before="$(snd_calls_all)"
read -r wx wy < <(snd_at_widget) || fail "the widget has no box"
hover "$wx" "$wy" || fail "hovering the widget failed"
wheel "$wx" "$wy" -1 || fail "the wheel on the widget failed"
expect_poll "a wheel notch up on the widget raises the speakers by the step" "$((speakers + 5))" snd_volume vgs-smoke-speakers
middle_click "$wx" "$wy" || fail "the middle click on the widget failed"
expect_poll "a middle click mutes the speakers" true snd_muted vgs-smoke-speakers
expect_poll "the widget draws the muted icon" '"volume-x"' snd_widget iconName
middle_click "$wx" "$wy" || fail "the second middle click on the widget failed"
expect_poll "a second middle click unmutes them" false snd_muted vgs-smoke-speakers
expect "the widget's actions started no process a stand-in or recorder sees" "$calls_before" snd_calls_all

# The nested instance for the keys: binds by keysym, the user's own bind
# on XF86AudioMicMute, and monitor focus held while a second output comes.
hypr_lua_save sound
{
  printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = true, follow_mouse = 0 }, cursor = { no_warps = true }, misc = { mouse_move_focuses_monitor = false } })'
  printf '%s\n' "hl.bind(\"XF86AudioMicMute\", hl.dsp.exec_cmd(\"touch $sandbox/sound-user-mic\"), { description = \"Smoke user mic mute\" })"
} >>"$home/.config/hypr/hyprland.lua"
expect "the nested instance reloads with the Sound row's binds" ok hypr reload config-only
expect_poll "the nested instance holds no configuration error" '[]' hypr_config_errors

# The keyboard alone: SUPER+COMMA, Enter into the section, Down on the
# output's Select, then Tab through every control, Space on each button
# and Down and Up on each slider, and Escape twice.
type_keys -M logo -k comma -m logo || fail "SUPER+COMMA failed"
expect_poll "SUPER+COMMA opens System on the Sound section" '["vgs.sound"]' window_panes
expect_poll "System opens with the keyboard in its search field" true snd_search_focused
type_keys -k Return || fail "Enter failed"
expect_poll "Enter puts the keyboard on the output's Select" '["Select",""]' snd_focus
expect "the Select shows the speakers" '"Smoke Speakers"' ipc smoke readDescendant window vgs.sound Select currentText
rm -f -- "${devices_dir:?}/calls/pactl.calls"
type_keys -k Down || fail "Down on the Select failed"
expect_poll "Down chooses the headphones" '"Smoke Headphones"' ipc smoke readDescendant window vgs.sound Select currentText
expect_poll "the headphones become WirePlumber's default sink" '"vgs-smoke-headphones"' snd_audio '["defaults"]["sink"]'
expect_poll "pactl is asked to move the player alone" "$snd_list, [\"move-sink-input\", \"42\", \"vgs-smoke-headphones\"]]" snd_pactl
headphones="$(snd_volume vgs-smoke-headphones)"
expect_poll "the widget reads the headphones" "\"Smoke Headphones: ${headphones}%\"" snd_widget tooltip
# snd_tab_button LABEL NODE: Tab to the mute button LABEL names, then
# Space mutes NODE and Space again unmutes it.
snd_tab_button() {
  type_keys -k Tab || fail "Tab to $1 failed"
  expect_poll "Tab reaches $1" "[\"IconButton\",\"$1\"]" snd_focus
  type_keys -k space || fail "Space on $1 failed"
  expect_poll "Space on $1 mutes $2" true snd_muted "$2"
  type_keys -k space || fail "the second Space on $1 failed"
  expect_poll "a second Space unmutes $2" false snd_muted "$2"
}
# snd_tab_slider LABEL NODE: Tab to the next slider, then Down lowers
# NODE by the step and Up raises it back.
snd_tab_slider() {
  local was
  was="$(snd_volume "$2")"
  type_keys -k Tab || fail "Tab to $1 failed"
  expect_poll "Tab reaches $1" '["Slider",null]' snd_focus
  type_keys -k Down || fail "Down on $1 failed"
  expect_poll "Down on $1 lowers $2 by the step" "$((was - 5))" snd_volume "$2"
  type_keys -k Up || fail "Up on $1 failed"
  expect_poll "Up on $1 raises it back" "$was" snd_volume "$2"
}
snd_tab_button "Mute output" vgs-smoke-headphones
snd_tab_slider "the output's slider" vgs-smoke-headphones
type_keys -k Tab || fail "Tab to the input's Select failed"
expect_poll "Tab reaches the input's Select" '["Select",""]' snd_focus
expect "the input's Select shows the microphone" true snd_texts_hold Select 'Smoke Microphone'
snd_tab_button "Mute microphone" vgs-smoke-microphone
snd_tab_slider "the microphone's slider" vgs-smoke-microphone
snd_tab_button "Mute Smoke Player" smoke-player
snd_tab_slider "the player's slider" smoke-player
type_keys -k Escape || fail "Escape in the section failed"
expect_poll "Escape returns the keyboard to the search field" true snd_search_focused
type_keys -k Escape || fail "Escape in the search field failed"
expect_poll "a second Escape closes System" 0 window_count System

# The volume keys, with a second output beside the focused one.
expect "the nested compositor adds a second output" ok hypr output create headless "$snd_output"
expect_poll "the display has a copy on each output" 2 snd_osd_screens
snd_focused="$(snd_focused_screen)"
expect "the first output keeps the focus" true bash -c '[[ $1 != *"$2"* ]] && echo true || echo false' _ "$snd_focused" "$snd_output"
expect_poll "the service reads the focused output" "$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])[0]))' "$snd_focused")" ipc smoke readInstance service vgs.sound focusedOutput
headphones="$(snd_volume vgs-smoke-headphones)"
snd_key_step "XF86AudioLowerVolume lowers the headphones by the 5% step" XF86AudioLowerVolume vgs-smoke-headphones "$((headphones - 5))"
expect_poll "the display shows on the focused output alone" "$snd_focused" snd_osd
expect_poll "the display is gone after its time" '[]' snd_osd
snd_key_step "XF86AudioRaiseVolume raises them by the 5% step" XF86AudioRaiseVolume vgs-smoke-headphones "$headphones"
expect "the headphones go to 150% from outside the shell" "" "${shell_env[@]}" wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.5
expect_poll "the headphones read 150%" 150 snd_volume vgs-smoke-headphones
snd_key_step "XF86AudioRaiseVolume keeps a level above 100%" XF86AudioRaiseVolume vgs-smoke-headphones 150
snd_key_step "XF86AudioLowerVolume steps down from it" XF86AudioLowerVolume vgs-smoke-headphones 145
expect "the headphones go back to 50% from outside the shell" "" "${shell_env[@]}" wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5
snd_row_set volumeStep 10
expect "the configuration reloads with a 10% step" ok ipc shell reloadConfig
expect_poll "the service reads the 10% step" 10 ipc smoke readInstance service vgs.sound step
expect_poll "the headphones read 50%" 50 snd_volume vgs-smoke-headphones
snd_key_step "XF86AudioLowerVolume lowers the headphones by the 10% step" XF86AudioLowerVolume vgs-smoke-headphones 40
snd_key_step "XF86AudioRaiseVolume raises them by the 10% step" XF86AudioRaiseVolume vgs-smoke-headphones 50
snd_row_set volumeStep -
expect "the configuration reloads with the 5% step" ok ipc shell reloadConfig
expect_poll "the service reads the 5% step again" 5 ipc smoke readInstance service vgs.sound step

# Use my binding: the user's own bind holds XF86AudioMicMute.
settings_page_open vgs.sound
expect_poll "the microphone mute key names the user's bind" '"Also used by your other shortcuts."' key_field vgs.sound mic-mute conflict
expect "only the key a user bind holds offers Use my binding" 1 snd_use_mine
settings_press "Use my binding" || fail "the click on Use my binding failed"
expect_poll "Use my binding unbinds the microphone mute shortcut" null snd_key mic-mute
expect_poll "the Hyprland layer no longer binds XF86AudioMicMute" \
  '[["XF86AUDIOLOWERVOLUME", "vgs.sound:volume-down"], ["XF86AUDIOMUTE", "vgs.sound:mute"], ["XF86AUDIORAISEVOLUME", "vgs.sound:volume-up"]]' snd_binds
rm -f -- "$sandbox/sound-user-mic"
type_keys -k XF86AudioMicMute || fail "XF86AudioMicMute failed"
expect_poll "the user's bind takes XF86AudioMicMute" 1 snd_marker "$sandbox/sound-user-mic"
expect "the microphone stays unmuted" false snd_muted vgs-smoke-microphone
settings_page_close vgs.sound

# Control: a Settings copy whose Use my binding sends the key in effect
# leaves the shortcut bound. Its write lands in the user file, so the
# reading follows the press.
snd_row_set keys -
expect "the configuration reloads with the manifest's keys" ok ipc shell reloadConfig
expect_poll "XF86AudioMicMute is the Sound shortcut's again" "$snd_all_binds" snd_binds
rm -rf -- "${snd_settings_copy:?}"
cp -R -- "$repo/shell/plugins/vgs.settings" "$snd_settings_copy"
python3 - "$snd_settings_copy/KeyField.qml" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = "            onClicked: root.applyKey(null)"
assert text.count(old) == 1, old
open(path, "w").write(text.replace(old, "            onClicked: root.applyKey(root.shown)"))
PY
rescan "rescan picks the Settings copy"
settings_page_open vgs.sound
expect_poll "control: the copy's microphone mute key names the user's bind" '"Also used by your other shortcuts."' key_field vgs.sound mic-mute conflict
expect_poll "control: the copy offers Use my binding too" 1 snd_use_mine
# The window mapped where the last press was, so the pointer moves before
# it presses (validation-smoke.md).
rest_pointer || fail "control: resting the pointer failed"
settings_press "Use my binding" || fail "control: the click on the copy's Use my binding failed"
expect_poll "control: the copy's Use my binding writes the key in effect" '"XF86AUDIOMICMUTE"' snd_key mic-mute
expect "control: a Use my binding that sends the key in effect leaves the shortcut bound" stayed snd_stays "$snd_all_binds" snd_binds
settings_page_close vgs.sound
rm -rf -- "${snd_settings_copy:?}"
rescan "rescan drops the Settings copy"
snd_row_set keys -
expect "the configuration reloads without the control's key" ok ipc shell reloadConfig

# The filter chain as the default: Down on the pane's slider lowers the
# speakers it plays to.
expect "the filter chain becomes the default output" ok ipc vgs.sound invoke output vgs-smoke-equalizer
expect_poll "the filter chain is WirePlumber's default sink" '"vgs-smoke-equalizer"' snd_audio '["defaults"]["sink"]'
snd_dsp_step() { # LABEL
  local eq sp
  eq="$(snd_volume vgs-smoke-equalizer)"
  sp="$(snd_volume vgs-smoke-speakers)"
  expect "$1: System opens on the Sound section" ok ipc shell summon window vgs.system '{"pane":"vgs.sound"}'
  expect_poll "$1: the deep link puts the keyboard on the output's Select" '["Select",""]' snd_focus
  type_keys -k Tab -k Tab || fail "$1: Tab to the slider failed"
  expect_poll "$1: Tab reaches the output's slider" '["Slider",null]' snd_focus
  type_keys -k Down || fail "$1: Down on the slider failed"
  snd_dsp_was="$eq $sp"
}
snd_dsp_now() { echo "$(snd_volume vgs-smoke-equalizer) $(snd_volume vgs-smoke-speakers)"; }
snd_dsp_step "the filter chain"
read -r eq sp <<<"$snd_dsp_was"
expect_poll "Down lowers the speakers behind the filter and leaves the filter's own volume" "$eq $((sp - 5))" snd_dsp_now
expect "System hides" ok ipc shell hide window vgs.system

# Controls on one user copy of the plugin, each defect reaching one rule.
snd_plugin_copy \
  Widget.qml 'return answered("mute", shell.ipc.call("mute", ""));' 'Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]); return "ok";' \
  Widget.qml 'import qs.Commons' $'import Quickshell\nimport qs.Commons' \
  Service.qml 'if (!lister.running) root.list();' '' \
  Service.qml 'readonly property bool shown: root.osd !== null && screen !== null && screen.name === root.focusedOutput' 'readonly property bool shown: root.osd !== null && screen !== null' \
  Audio.qml 'readonly property string volumeSinkName: Logic.volumeTarget(sinkName, graph, links)' 'readonly property string volumeSinkName: sinkName' \
  Audio.qml 'audio.volume = Math.max(0, value);' 'audio.volume = Math.max(0, Math.min(1, value));' \
  Audio.qml '    readonly property var apps: root.nodes.filter(' '    property var apps: []
    function appRows() { return root.nodes.filter(' \
  Audio.qml '        .map(n => ({ name: String(n.name), label: root.property(n, "application.name"), node: n }))' '        .map(n => ({ name: String(n.name), label: root.property(n, "application.name"), node: n })); }' \
  Audio.qml '        root.inputs = all.filter(n => !n.isStream && !n.isSink).map(root.row);' '        root.inputs = all.filter(n => !n.isStream && !n.isSink).map(root.row);
        root.apps = root.appRows();'
rescan "rescan picks the Sound copy"
expect_poll "the copy's widget is placed" True snd_placed
expect_log "the copy is the one built" 1 'plugins: hidden by a higher-precedence plugin with the same id: vgs.sound'
snd_dsp_step "control"
read -r eq sp <<<"$snd_dsp_was"
expect_poll "control: an Audio with no DSP resolution moves the filter's own volume" "$((eq - 5)) $sp" snd_dsp_now
expect "System hides after the control" ok ipc shell hide window vgs.system
rm -f -- "${devices_dir:?}/calls/pactl.calls"
expect "control: the copy makes the headphones the default" ok ipc vgs.sound invoke output vgs-smoke-headphones
expect_poll "control: the headphones are the default" '"vgs-smoke-headphones"' snd_audio '["defaults"]["sink"]'
expect "control: a service that runs no pactl moves no player" stayed snd_stays '[]' snd_pactl
expect "control: the headphones go to 150% from outside the shell" "" "${shell_env[@]}" wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.5
expect_poll "control: the headphones read 150%" 150 snd_volume vgs-smoke-headphones
type_keys -k XF86AudioRaiseVolume || fail "control: XF86AudioRaiseVolume failed"
expect_poll "control: an Audio that caps a step at 100% lowers a level above it" 100 snd_volume vgs-smoke-headphones
expect_poll "control: a display that ignores the focused output shows on both" "$(snd_all_screens)" snd_osd
expect "control: the headphones go back to 50%" "" "${shell_env[@]}" wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5
kill -- "-$devices_player_pid" 2>/dev/null || true
expect_poll "control: the player is gone" false snd_audio '["nodes"].__contains__("smoke-player")'
expect "control: System opens on the Sound section" ok ipc shell summon window vgs.system '{"pane":"vgs.sound"}'
expect_poll "control: the Sound pane is mounted" '["vgs.sound"]' window_panes
devices_audio_play
expect_poll "control: the test stream plays" true snd_audio '["nodes"].__contains__("smoke-player")'
expect "control: an Audio that builds its app rows once per snapshot lists no app that started" stayed snd_stays false snd_texts_hold FormRow 'Smoke Player'
expect "System hides after the controls" ok ipc shell hide window vgs.system
expect "the nested compositor removes the second output" ok hypr output remove "$snd_output"
expect_poll "the bars are as many as before" "$monitors" bar_count
: >"$snd_spawns"
read -r wx wy < <(snd_at_widget) || fail "control: the widget has no box"
hover "$wx" "$wy" || fail "control: hovering the widget failed"
middle_click "$wx" "$wy" || fail "control: the middle click on the widget failed"
expect_poll "control: a widget whose middle click runs wpctl leaves a record" '[["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]]' snd_spawned
expect_poll "control: that wpctl muted the headphones" true snd_muted vgs-smoke-headphones
expect "control: the headphones unmute from outside the shell" "" "${shell_env[@]}" wpctl set-mute @DEFAULT_AUDIO_SINK@ 0
rm -rf -- "${snd_copy:?}"
rescan "rescan drops the Sound copy"
expect_poll "the shipped widget is placed again" True snd_placed
hypr_lua_restore sound || fail "hyprland.lua is put back after the Sound keys"
expect "the nested instance reloads without the Sound row's binds" ok hypr reload config-only

# PipeWire stopped: the unavailable state; started again: the speakers.
# Each stop and start runs in the row's own shell, so the new process
# groups reach the teardown's list.
devices_audio_stop >"$sandbox/sound-audio.out"
expect "the private PipeWire stops" stopped cat "$sandbox/sound-audio.out"
expect_poll "the widget draws the unavailable icon" '"volume-off"' snd_widget iconName
expect_poll "the widget says sound is not available" '"Sound is not available"' snd_widget tooltip
expect "a step answers unavailable" "refused: sound=unavailable" ipc vgs.sound invoke step up
expect "System opens on the Sound section without PipeWire" ok ipc shell summon window vgs.system '{"pane":"vgs.sound"}'
expect_poll "the pane says sound is not available" true snd_texts_hold EmptyState 'Sound is not available'
expect "System hides" ok ipc shell hide window vgs.system
devices_audio_start >"$sandbox/sound-audio.out"
expect "the private PipeWire starts again" started cat "$sandbox/sound-audio.out"
expect "the restarted PipeWire's process group is in the teardown's list" kept snd_pgid_kept
expect_poll "after a lost connection the widget reads the speakers again" true snd_tooltip_names 'Smoke Speakers'

# A shell that starts while PipeWire is stopped connects once it starts,
# and a runner copy without the reconnect variable never does.
snd_cold() { # LABEL TREE WANT
  devices_audio_stop >"$sandbox/sound-audio.out"
  expect "$1: the private PipeWire stops" stopped cat "$sandbox/sound-audio.out"
  stop_shell || fail "$1: the shell stops"
  start_shell "$2" "$sandbox/qs-sound-$3.log" || fail "$1: the shell starts with PipeWire stopped"
  expect_poll "$1: the widget starts unavailable" '"volume-off"' snd_widget iconName
  devices_audio_start >"$sandbox/sound-audio.out"
  expect "$1: the private PipeWire starts" started cat "$sandbox/sound-audio.out"
  expect "$1: its process group is in the teardown's list" kept snd_pgid_kept
}
snd_cold "a cold start" "$repo" cold
expect_poll "a shell started without PipeWire reads the speakers once it starts" true snd_tooltip_names 'Smoke Speakers'
if copy_tree sound-reconnect && edit_tree sound-reconnect bin/vgshell '  export QS_PIPEWIRE_IMMEDIATE_RECONNECT=1
' ''; then
  snd_cold "control" "$sandbox/tree-sound-reconnect" control
  expect "control: a runner without the reconnect variable leaves the widget unavailable" stayed snd_stays '"volume-off"' snd_widget iconName
  stop_shell || fail "the control shell stops"
  start_shell "$repo" "$sandbox/qs-sound-restored.log" || fail "the shell starts again after the reconnect control"
fi
expect_poll "the restored shell reads the speakers" true snd_tooltip_names 'Smoke Speakers'

kill -- "-$devices_player_pid" 2>/dev/null || true
for snd_name in "${snd_recorded[@]}"; do rm -f -- "${shim:?}/$snd_name"; done
device_reply_clear pactl
cp -- "$snd_saved" "$snd_file"
expect "the configuration reloads as the row found it" ok ipc shell reloadConfig
expect_poll "vgs.system's enablement is as the row found it" "$snd_system_was" plugin_enabled vgs.system
expect_poll "vgs.sound's enablement is as the row found it" "$snd_sound_was" plugin_enabled vgs.sound
