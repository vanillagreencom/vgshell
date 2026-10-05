# Voice uses a stub voxtype on PATH, never the host command. The row enables
# the plugin, reads its status and bar widget, sends its default toggle key,
# sends and releases F9, reads setup offered while the stub model is missing
# and withheld when the stub reports it installed, then disables the plugin
# and checks its shortcuts and status child are gone. The F9 check reads a
# complete start and stop pair; a control that only sends the press would
# leave only start in the log and fail the same assertion.
# inputs: shell/plugins/vgs.voice/* scripts/smoke/fixtures/voice/* shell/Core/ShortcutRegistry.qml shell/Core/HyprlandLayer.js shell/Core/PluginStatus.qml shell/Core/TuiRunner.qml scripts/smoke/rows/hold-shortcuts.sh
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
    printf '%s\n' '{"state":"recording","engine":"parakeet","model":"parakeet-tdt-0.6b-v3"}'
    printf '%s\n' "\$\$" >"$voice_status_pid"
    trap 'exit 0' TERM
    while :; do sleep 1; done
    ;;
  'record toggle'|'record start'|'record stop') printf '%s\n' "\$*" >>"$voice_log" ;;
  'config get engine --json') printf '%s\n' '{"value":"parakeet"}' ;;
  'config get parakeet.model --json') printf '%s\n' '{"value":"parakeet-tdt-0.6b-v3"}' ;;
  'info models --json')
    if [[ -e "$voice_installed" ]]; then
      printf '%s\n' '{"models":[{"name":"parakeet-tdt-0.6b-v3","installed":true,"size":"600 MB"}]}'
    else
      printf '%s\n' '{"models":[{"name":"parakeet-tdt-0.6b-v3","installed":false,"size":"600 MB"}]}'
    fi
    ;;
  'info engines --json') printf '%s\n' '{"engines":[{"name":"parakeet","available":true}]}' ;;
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

hypr_lua_save voice
printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = true } })' >>"$home/.config/hypr/hyprland.lua"
expect "Voice key resolution is reloaded" ok hypr reload config-only
rescan "rescan discovers the Voice stub"
expect_poll "the Voice plugin is known" True plugin_known vgs.voice
expect_poll "the Voice voxtype requirement is present" present voice_requirement voxtype
expect "enabling Voice is allowed" ok ipc shell setPluginEnabled vgs.voice true
expect "placing Voice in the bar is allowed" ok ipc shell setPluginPlaced vgs.voice true
expect_poll "Voice builds" True record_exists vgs.voice
expect_poll "Voice sees voxtype present" true ipc smoke readInstance service vgs.voice voxtypePresent
expect_poll "Voice starts its status process" true ipc smoke readInstance service vgs.voice statusRunning
expect_poll "Voice registers its two shortcuts and the release companion" 3 voice_shortcuts
expect_poll "the Voice status child starts" true ipc smoke readInstance service vgs.voice statusRunning
expect_poll "the status stream reaches plugin status" '["dictation", "model", "setup", "voxtype"]' voice_status_value
expect_poll "the recording state reaches the bar widget" '"idle"' voice_dictation
expect_poll "Set up is offered while the model is missing" True voice_setup_offered

expect "the compositor triggers the Voice toggle shortcut" ok hypr dispatch 'hl.dsp.global("vgs.voice:toggle")'
expect_poll "the toggle shortcut runs voxtype record toggle" 'toggle' python3 - "$voice_log" <<'PY'
import pathlib, sys
calls = pathlib.Path(sys.argv[1]).read_text().splitlines()
print("toggle" if "record toggle" in calls else calls)
PY
before="$(wc -l <"$voice_log")"
expect "the compositor triggers the Voice hold press" ok hypr dispatch 'hl.dsp.global("vgs.voice:talk")'
expect "the Voice release callback is invoked" ok ipc smoke invokeInstance service vgs.voice record stop
expect_poll "hold press and release run start then stop" "record start|record stop" bash -c "tail -n +$((before + 1)) '$voice_log' | paste -sd '|' -"

expect "disabling Voice for setup refresh is allowed" ok ipc shell setPluginEnabled vgs.voice false
touch -- "$voice_installed"
expect "enabling Voice after the model is installed is allowed" ok ipc shell setPluginEnabled vgs.voice true
expect_poll "Set up is withheld once the model is installed" False voice_setup_offered
expect "disabling Voice is allowed" ok ipc shell setPluginEnabled vgs.voice false
expect_poll "disabling Voice removes its shortcuts" 0 voice_shortcuts
expect_poll "disabling Voice clears its status" absent voice_status_value
expect_poll "disabling Voice stops the status child" gone voice_status_alive
hypr_lua_restore voice || fail "Voice restores hyprland.lua"
expect "Voice key resolution restore is reloaded" ok hypr reload config-only
rm -f -- "${voice_stub:?}" "${shim:?}/systemctl" "${shim:?}/setpriv"
rescan "rescan after removing the Voice stubs"
