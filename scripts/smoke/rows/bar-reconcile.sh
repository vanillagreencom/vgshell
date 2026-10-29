# inputs: shell/plugins/vgs.launcher/* shell/plugins/vgs.tray/* scripts/smoke/fixtures/tray/* scripts/smoke/fixtures/devices/hid-world.json scripts/smoke/fixtures/devices/hid-fake.py config/shell.json shell/Core/PluginLogic.js shell/Core/ConfigLogic.js shell/plugins/vgs.sound/* shell/plugins/vgs.network/* shell/plugins/vgs.bluetooth/* shell/plugins/vgs.displays/* shell/plugins/vgs.keyboard/* shell/plugins/vgs.tailscale/* shell/plugins/vgs.vpn/* shell/plugins/vgs.sudo/* shell/plugins/vgs.mouse/* shell/plugins/vgs.bar/* scripts/smoke/fixtures/plugins/acme.tick/* scripts/smoke/fixtures/plugins/acme.idle/* shell/Hosts/BarHost.qml shell/Ui/controls/BarItem.qml shell/Ui/BarWidget.qml shell/Core/Plugins.qml shell/Core/Config.qml shell/Commons/Workspaces.qml shell/Commons/Time.qml shell/plugins/*/manifest.json shell/Core/Capabilities.qml shell/Ui/overlay/Menu.qml shell/Ui/overlay/MenuItem.qml shell/Commons/Tokens.js shell/plugins/vgs.settings/manifest.json shell/plugins/vgs.settings/Service.qml shell/plugins/vgs.settings/Widget.qml shell/plugins/vgs.settings/Window.qml shell/plugins/vgs.settings/ListPage.qml shell/plugins/vgs.settings/PluginPage.qml shell/plugins/vgs.settings/PageHeader.qml shell/plugins/vgs.settings/EditSet.qml shell/plugins/vgs.settings/Steps.js shell/plugins/vgs.settings/StatusRow.qml shell/plugins/vgs.settings/StatusLine.qml shell/plugins/vgs.settings/RequirementRow.qml shell/plugins/vgs.agent-warden/* shell/plugins/vgs.ai-usage/* shell/plugins/vgs.capture/* shell/plugins/vgs.jarvis/* shell/plugins/vgs.power/* shell/plugins/vgs.traffic/* shell/plugins/vgs.updates/* shell/plugins/vgs.voice/* shell/plugins/vgs.sysmon/* shell/Ui/controls/IconButton.qml shell/Ui/controls/Button.qml shell/Hosts/SummonPopup.qml shell/Commons/DesktopLaunch.js shell/Commons/AnchorTracker.qml scripts/smoke/fixtures/plugins/acme.tiplink/* shell/Ui/overlay/Tooltip.qml shell/Ui/feedback/LinkText.qml shell/Commons/PageReference.js shell/Hosts/NoticeHost.qml shell/Core/KeyCapture.qml shell/Core/HyprlandLayer.qml scripts/smoke/rows/bar.sh
# Diagnostics reads the measured reply-to-built result from this row.
set -euo pipefail


# Disable only lists the id: the layout entry and the settings row stay,
# so re-enabling restores the exact screen. The effective configuration is
# read back for the entry, the user file for what the manager wrote.
# Latency from a setPluginEnabled reply to `built` reflecting it, polled
# with qs ipc against the shell's pid; the reading carries one IPC round trip.
# Use the runner's EPOCHREALTIME clock conversion in this shell so date,
# seq and tail processes add no caller work to that interval.
reconcile_ms=""
reconcile_cpu_some_pct=unmeasured
if disable_reply="$(ipc shell setPluginEnabled acme.tick false)"; then
  replied_ms=$(( ${EPOCHREALTIME//[!0-9]/} / 1000 ))
  reconcile_cpu_start="$(cpu_some_us)"
  reconcile_poll_count=0
  for ((reconcile_poll = 0; reconcile_poll < 500; ++reconcile_poll)); do
    reconcile_poll_count=$((reconcile_poll_count + 1))
    if built_output="$("${shell_env[@]}" qs ipc --pid "$shell_qs_pid" call shell built 2>>"$sandbox/ipc.log")"; then
      vgs_ipc_last_line_into "$built_output"
      built_now="$vgs_ipc_last_line"
      if [[ $built_now == \{*\} && $built_now != *'"id":"acme.tick"'* ]]; then
        reconcile_ms=$(( ${EPOCHREALTIME//[!0-9]/} / 1000 - replied_ms ))
        reconcile_cpu_some_pct="$(cpu_some_pct "$reconcile_cpu_start" "$(cpu_some_us)" "$reconcile_ms")"
        break
      fi
    fi
    sleep 0.005
  done
fi
printf '  reconcile_observation polls=%s latency_ms=%s cpu_some_pct=%s\n' "${reconcile_poll_count:-0}" "$reconcile_ms" "$reconcile_cpu_some_pct"
if [[ $disable_reply == ok ]]; then ok "disabling a widget is allowed"; else fail "disabling a widget is allowed: got $disable_reply"; fi
tick_entry() { ipc shell listShellConfig | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps([e for e in d["bar"]["layout"]["center"] if e["id"]=="acme.tick"]))'; }
tick_row() { ipc shell listShellConfig | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps([e for e in d.get("plugins",[]) if e["id"]=="acme.tick"]))'; }
user_keys() { python3 -c 'import json,sys; print(",".join(sorted(json.load(open(sys.argv[1])).keys())))' "$home/.config/vgshell/shell.json"; }
expect_widgets "the bar dropped the disabled widget" '[]'
expect_builtins "the built-ins stay while a plugin widget leaves" '["vgs.bar/center-clock","vgs.bar/left-workspaces"]'
expect "widget reads disabled after the user file changed" False plugin_enabled acme.tick
expect "the disabled widget keeps its layout entry" '[{"id": "acme.tick"}]' tick_entry
expect "the disabled widget keeps its settings row" '[{"id": "acme.tick", "format": "ddd d MMM  HH:mm"}]' tick_row
expect "disable wrote only the disabled list" "bar,disabledPlugins,plugins,version" user_keys
expect "re-enabling the widget is allowed" ok ipc shell setPluginEnabled acme.tick true
expect_widgets "the bar rebuilt the re-enabled widget" '["acme.tick"]'
expect "re-enable wrote only the disabled list" "bar,disabledPlugins,plugins,version" user_keys
