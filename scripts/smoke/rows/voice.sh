# Voice uses a stub voxtype on PATH, never the host command. The row enables
# the plugin, reads its status and bar widget, sends its toggle and hold keys
# through the nested virtual-keyboard helper, reads setup offered while the
# stub model is missing and withheld when the stub reports it installed, then
# disables the plugin and checks its shortcuts and status child are gone. The
# key delivery uses physical code overrides for the row, so the helper reaches
# the same generated bind path that hold-shortcuts.sh exercises. It closes its
# client window and puts back the shell.json it found.
# inputs: shell/plugins/vgs.voice/* shell/Core/ShortcutRegistry.qml shell/Core/HyprlandLayer.js shell/Core/PluginStatus.qml shell/Core/TuiRunner.qml shell/plugins/vgs.settings/* scripts/smoke/keyboard/* scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail

voice_log="$sandbox/voice-record.log"
voice_status_pid="$sandbox/voice-status.pid"
voice_installed="$sandbox/voice-model-installed"
voice_setpriv_log="$sandbox/voice-setpriv.log"
voice_stub="$shim/voxtype"
cat >"$voice_stub" <<EOF_STUB
#!/usr/bin/env bash
case "\$*" in
  'status --follow --extended --format json')
    printf '%s\n' '{"state":"recording","backend":"ONNX CPU","device":"default","model":"parakeet-tdt-0.6b-v3"}'
    printf '%s\n' "\$\$" >"$voice_status_pid"
    trap 'exit 0' TERM
    while :; do sleep 1; done
    ;;
  'record toggle'|'record start'|'record stop') printf '%s\n' "\$*" >>"$voice_log" ;;
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
cat >"$shim/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
case "$*" in
  '--user is-enabled voxtype') printf 'enabled\n' ;;
  *) ;;
esac
EOF_SYSTEMCTL
chmod 755 "$shim/systemctl"
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
voice_requirement() { ipc shell listPlugins | py_reply 'import json,sys; p=[p for p in json.load(sys.stdin)["plugins"] if p["id"]=="vgs.voice"][0]; print([r["state"] for r in p["requirements"] if r["command"]==sys.argv[1]][0])' "$1"; }
voice_status_alive() { local pid; [[ -f $voice_status_pid ]] || { echo absent; return; }; pid="$(cat "$voice_status_pid")"; python3 - "$pid" <<'PY'
import pathlib, sys
pid = sys.argv[1]
print('alive' if pid.isdigit() and pathlib.Path('/proc', pid).exists() else 'gone')
PY
}
voice_setup_offered() { ipc smoke readInstance service vgs.voice setupValue | py_reply 'import json,sys; v=json.load(sys.stdin); print(v.get("action"))'; }
voice_dictation() { ipc smoke readInstance "$(bar_key)" vgs.voice dictation; }
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
cp -- "$home/.config/vgshell/shell.json" "$voice_saved_config"
voice_ensure_hypr_wired
hypr_lua_save voice
printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = false } })' >>"$home/.config/hypr/hyprland.lua"
expect "Voice key resolution is reloaded" ok hypr reload config-only
rescan "rescan discovers the Voice stub"
expect_poll "the Voice plugin is known" True plugin_known vgs.voice
expect_poll "the Voice voxtype requirement is present" present voice_requirement voxtype
expect "enabling Voice is allowed" ok ipc shell setPluginEnabled vgs.voice true
expect "placing Voice in the bar is allowed" ok ipc shell setPluginPlaced vgs.voice true
voice_set_keys
expect "Voice physical key overrides are reloaded" ok ipc shell reloadConfig
expect "Hyprland reloads Voice physical key overrides" ok hypr reload config-only
expect_poll "Voice builds" True record_exists vgs.voice
expect_poll "Voice reads the physical key overrides" '{"toggle":"SUPER+CTRL+code:53","talk":"code:75"}' ipc smoke readInstance service vgs.voice shortcutKeys
expect_poll "Voice sees voxtype present" true ipc smoke readInstance service vgs.voice voxtypePresent
expect_poll "Voice starts its status process" true ipc smoke readInstance service vgs.voice statusRunning
expect_poll "Voice registers its two shortcuts and the release companion" 3 voice_shortcuts
expect_poll "the Voice status child starts" true ipc smoke readInstance service vgs.voice statusRunning
expect_poll "the status stream reaches plugin status" '["dictation", "model", "setup", "voxtype"]' voice_status_value
expect_poll "the recording state reaches the bar widget" '"recording"' voice_dictation
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

touch -- "$voice_installed"
rescan "the Voice rescan rereads setup state"
expect_poll "Set up is withheld once the model is installed" False voice_setup_offered
expect "disabling Voice is allowed" ok ipc shell setPluginEnabled vgs.voice false
expect_poll "disabling Voice removes its shortcuts" 0 voice_shortcuts
expect_poll "disabling Voice clears its status" absent voice_status_value
expect_poll "disabling Voice stops the status child" gone voice_status_alive
voice_stop_keyboard
close_toplevel "$voice_client_pid" "the Voice client exits 0 on SIGTERM"
hypr_lua_restore voice || fail "Voice restores hyprland.lua"
expect "Voice key resolution restore is reloaded" ok hypr reload config-only
rm -f -- "${voice_stub:?}" "${shim:?}/systemctl" "${shim:?}/setpriv" "${voice_installed:?}"
rescan "rescan after removing the Voice stubs"
expect_poll "the Voice voxtype requirement is missing after stub removal" missing voice_requirement voxtype
expect "enabling Voice without voxtype is allowed" ok ipc shell setPluginEnabled vgs.voice true
expect_poll "Voice without voxtype is built" True record_exists vgs.voice
settings_page_open vgs.voice
settings_details
expect_poll "the Voice page offers Install and withholds Set up without voxtype" '[["voxtype", "Install\u2026", true], ["setup", "Set up", false]]' offered_actions vgs.voice
expect_poll "the Voice status row offers voxtype install" '[["voxtype", "Absent", "Voice needs voxtype to capture speech.", "Install\u2026"], ["Setup", "Install voxtype first", "Setup copies defaults, downloads the speech model and enables the service."]]' voice_drawn_status
expect_poll "the Voice Requirements row says voxtype is missing" "$(words voxtype "Missing, optional" "Captures speech and inserts dictated text")" voice_requirement_drawn
settings_page_close vgs.voice
expect "disabling Voice after the missing-requirement check is allowed" ok ipc shell setPluginEnabled vgs.voice false
cp -- "$voice_saved_config" "$home/.config/vgshell/shell.json.next" && mv -T -- "$home/.config/vgshell/shell.json.next" "$home/.config/vgshell/shell.json"
expect "the shell.json Voice found is reloaded" ok ipc shell reloadConfig
