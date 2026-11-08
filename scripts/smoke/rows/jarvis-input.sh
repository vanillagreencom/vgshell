# No latency budget. TUI actions run the nested allow-listed fixture only.
# inputs: shell/plugins/vgs.jarvis/* shell/plugins/vgs.settings/manifest.json shell/plugins/vgs.settings/Window.qml shell/plugins/vgs.settings/ListPage.qml shell/plugins/vgs.settings/PluginPage.qml shell/plugins/vgs.settings/PageHeader.qml shell/plugins/vgs.settings/EditSet.qml shell/plugins/vgs.settings/Steps.js shell/Ui/controls/SettingField.qml shell/plugins/vgs.settings/ListField.qml shell/plugins/vgs.settings/KeyField.qml shell/plugins/vgs.settings/StatusRow.qml shell/plugins/vgs.settings/StatusLine.qml shell/plugins/vgs.settings/RequirementRow.qml shell/Commons/Reply.js scripts/smoke/fixtures/tui/vgs.jarvis/* shell/Core/TuiRunner.qml scripts/smoke/rows/jarvis.sh bin/vgshell-tui
set -euo pipefail
expected_errors+=("${dictation_absent_errors[@]}")
local jarvis_fixture_tree="" jarvis_fixture_shim="" jarvis_fixture_name="" jarvis_fixture_revision=""
jarvis_fixture_begin
cp -- "$source_repo/scripts/smoke/fixtures/tui/vgs.jarvis/tui/setup-input.sh" "$jarvis_fixture_tree/shell/plugins/vgs.jarvis/tui/setup-input.sh"
jarvis_setup_requirements "$jarvis_fixture_shim"
jarvis_fixture_terminal
terminal_ready "Jarvis input check"
jarvis_rescan
jarvis_enable
settings_page_open vgs.jarvis
input_open() {
  local revision snapshot
  revision="$(jarvis_revision)" || return 1
  snapshot="$rt_dir/vgshell-sources-$shell_qs_pid/$revision"
  forget_record
  if [[ $1 == status ]]; then
    expect "Settings opens the input readiness terminal" ok settings_act vgs.jarvis input
  else
    expect "the launcher opens the input readiness terminal" ok ipc shell openTui vgs.jarvis/setup-input
  fi
  expect_poll "input setup receives only the declared snapshot and argv" \
    "$(words     --app-id=org.vgs.tui "--title=VGS · Check Jarvis input" -- "$jarvis_fixture_tree/bin/vgshell-tui" present --presentation full \
      --plugin vgs.jarvis --dir "$snapshot" --record vgs.jarvis/setup-input --run RUN --record-dir "$rt_dir/vgshell/tui" \
      --app-id org.vgs.tui --window-title "VGS · Check Jarvis input" -- tui/setup-input.sh)" recorded
  expect_run_end "the input readiness fixture ends" vgs.jarvis/setup-input
}
input_action() { status_row vgs.jarvis input | py_reply 'import json,sys; print("offered" if json.load(sys.stdin)["action"]["offered"] else "pending")'; }
jarvis_input_control_start() { # NAME
  stop_shell || :
  start_shell "$sandbox/tree-$1" "$sandbox/jarvis-input-$1.log" bar PATH="$sandbox/tree-$1.commands:$shim:$shell_host_path"
  jarvis_enable
  settings_page_open vgs.jarvis
}
jarvis_fixture_copy jarvis-input-not-offered "$jarvis_fixture_tree" "$jarvis_fixture_shim"
cp -- "$source_repo/scripts/smoke/fixtures/tui/vgs.jarvis/tui/setup-input.sh" "$sandbox/tree-jarvis-input-not-offered/shell/plugins/vgs.jarvis/tui/setup-input.sh"
if edit_tree jarvis-input-not-offered shell/plugins/vgs.jarvis/Service.qml \
    '        if (!publishInput({ tone: "warning", text: "Input tools unavailable", action: true })) return;' \
    '        if (!publishInput({ tone: "warning", text: "Input tools unavailable", action: false })) return;'; then
  jarvis_input_control_start jarvis-input-not-offered
  expect_poll "control: a service that does not offer the input action leaves it pending" pending input_action
  input_offered_control() {
    (failures=0 behaviour_failures=0
     expect "the input readiness action is offered" offered input_action >"$sandbox/jarvis-input-offered-control.log"
     echo "$failures")
  }
  expect "a missing input action breaks the offered-action assertion" 1 input_offered_control
  settings_page_close vgs.jarvis
  jarvis_disable
fi
jarvis_fixture_copy jarvis-input-wrong-script "$jarvis_fixture_tree" "$jarvis_fixture_shim"
cp -- "$source_repo/scripts/smoke/fixtures/tui/vgs.jarvis/tui/setup-input.sh" "$sandbox/tree-jarvis-input-wrong-script/shell/plugins/vgs.jarvis/tui/setup-input.sh"
cp -- "$source_repo/scripts/smoke/fixtures/tui/vgs.jarvis/tui/accounts.sh" "$sandbox/tree-jarvis-input-wrong-script/shell/plugins/vgs.jarvis/tui/accounts.sh"
if edit_tree jarvis-input-wrong-script shell/plugins/vgs.jarvis/manifest.json \
    '"setup-input": {"script": "tui/setup-input.sh", "title": "Check Jarvis input", "entry": {"label": "Check input", "icon": "mouse-pointer", "group": "Jarvis"}}' \
    '"setup-input": {"script": "tui/accounts.sh", "title": "Check Jarvis input", "entry": {"label": "Check input", "icon": "mouse-pointer", "group": "Jarvis"}}'; then
  jarvis_input_control_start jarvis-input-wrong-script
  revision="$(jarvis_revision)" || revision=""
  snapshot="$rt_dir/vgshell-sources-$shell_qs_pid/$revision"
  forget_record
  expect "control: Settings opens the input readiness terminal from the wrong script copy" ok settings_act vgs.jarvis input
  expect_poll "control: a manifest that names the wrong script sends that argv" \
    "$(words --app-id=org.vgs.tui "--title=VGS · Check Jarvis input" -- "$sandbox/tree-jarvis-input-wrong-script/bin/vgshell-tui" present --presentation full \
      --plugin vgs.jarvis --dir "$snapshot" --record vgs.jarvis/setup-input --run RUN --record-dir "$rt_dir/vgshell/tui" \
      --app-id org.vgs.tui --window-title "VGS · Check Jarvis input" -- tui/accounts.sh)" recorded
  expect_run_end "control: the wrong-script input run ends" vgs.jarvis/setup-input
  settings_page_close vgs.jarvis
  jarvis_disable
fi
stop_shell || :
start_shell "$jarvis_fixture_tree" "$sandbox/jarvis-input-restored.log" bar PATH="$jarvis_fixture_shim:$shim:$shell_host_path"
jarvis_enable
settings_page_open vgs.jarvis
expect_poll "the input readiness action is offered" offered input_action
input_open status
input_open launcher
settings_page_close vgs.jarvis
jarvis_disable
jarvis_restore_requirements "$jarvis_fixture_shim"
stop_shell
start_shell "$repo" "$sandbox/jarvis-input-stock.log"
