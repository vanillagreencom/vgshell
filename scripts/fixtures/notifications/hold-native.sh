# The notifications row's real-store restart, lease and missed-delivery cases.
# The 15000 ms hold policy is carried by the shell entry, not restated here.
# hold-native.py polls the real graph every 10 ms and retains each reading.
# This is a policy-bound timer-wiring check, not a latency benchmark.
set -euo pipefail
note_hold_active=no
note_hold_delivery_backup=""
note_hold_fixture=$repo/scripts/fixtures/notifications

notification_hold_install() {
  expect "the private preinstall stops the notification service" ok ipc shell setPluginEnabled vgs.notifications false
  expect_poll "the private preinstall waits for service removal" False record_exists vgs.notifications
  expect_poll "the private preinstall waits for owned-file removal" removed notification_audio_removed
  [[ $(notification_audio_removed) == removed ]] || return 1
  node "$note_hold_fixture/sound-rule-files.js" "$repo/shell/plugins/vgs.notifications" "$home" >"$sandbox/notification-rule-version"
  if [[ $note_hold_active == no ]]; then
    note_hold_config="$sandbox/notification-pipewire"
    mkdir -p -- "$note_hold_config/pipewire.conf.d"
    cp -- "$devices_fixtures/pipewire/pipewire.conf" "$note_hold_config/pipewire.conf"
    cp -- "$home/.config/pipewire/pipewire.conf.d/90-vgs-notification-hold.conf" "$note_hold_config/pipewire.conf.d/"
    devices_audio_stop >"$sandbox/notification-audio-stop"
    expect "only the private audio daemons stop for the owned store" stopped cat "$sandbox/notification-audio-stop"
    spawn "$devices_dir/pipewire-notification.log" "${shell_env[@]}" PIPEWIRE_CONFIG_DIR="$note_hold_config" pipewire
    devices_pid[pipewire]="$spawn_pid"
    for _ in $(seq 1 50); do [[ -S $rt_dir/pipewire-0 ]] && break; sleep 0.1; done
    [[ -S $rt_dir/pipewire-0 ]] || { fail "the private store daemon did not create its socket"; return 1; }
    spawn "$devices_dir/wireplumber-notification.log" "${shell_env[@]}" wireplumber --profile vgs-smoke
    devices_pid[wireplumber]="$spawn_pid"
    note_hold_active=yes
  else
    rule_wireplumber_restart
  fi
  expect "the service returns over its owned private fixture" ok ipc shell setPluginEnabled vgs.notifications true
  expect_poll "the private preinstall waits for service startup" True record_exists vgs.notifications
  expect_poll "the privately preinstalled rule runs" '"running"' note_status soundRule.phase
}

notification_hold_restore_delivery() {
  [[ -n $note_hold_delivery_backup ]] || return 0
  node "$note_hold_fixture/held-delivery.js" restore-held "$repo/shell/plugins/vgs.notifications/Service.qml" "$note_hold_delivery_backup"
  note_hold_delivery_backup=""
  rescan "the row restores the actual rule-held delivery"
}

notification_hold_cases() {
  local mode variant status result evidence
  python3 "$note_hold_fixture/hold-native.py" judge-controls
  expect_poll "the custom audio deployment reports unsupported bootstrap" '"unavailable"' note_status soundRule.phase
  expect "unsupported bootstrap publishes the Settings requirement" True notification_hold_notice
  for mode in restart lease deadline; do
    if [[ $mode == deadline ]]; then
      note_hold_delivery_backup="$sandbox/notification-held-delivery"
      node "$note_hold_fixture/held-delivery.js" suppress-held "$repo/shell/plugins/vgs.notifications/Service.qml" "$note_hold_delivery_backup"
      rescan "the native missed-frame case omits the actual rule-held delivery"
    fi
    for variant in actual control; do
      notification_hold_install
      expect "Sound turns off before the native hold case" off notes sound off
      expect_poll "the native hold entry has an acquired shell writer" acquired notification_hold_writer
      if [[ $variant == control ]]; then
        python3 "$note_hold_fixture/hold-rule-control.py" "$mode" "$repo/shell/plugins/vgs.notifications/wireplumber/vgs-notification-sounds.lua" "$home/.local/share/wireplumber/scripts/vgs-notification-sounds.lua"
      fi
      if [[ $mode != deadline ]]; then
        kill -STOP "$shell_qs_pid"
        note_audio_shell_stopped=yes
      fi
      rule_wireplumber_restart
      expect_poll "the native case sees the restarted rule version" "$(cat "$sandbox/notification-rule-version" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')" notification_hold_version
      evidence="$note_hold_evidence/$mode-$variant.json"
      if [[ $mode == lease ]]; then
        "${shell_env[@]}" python3 "$note_hold_fixture/hold-native.py" kill-writer "$shell_qs_pid" >"$note_hold_evidence/lease-$variant-writer.json"
      fi
      status=0
      "${shell_env[@]}" python3 "$note_hold_fixture/hold-native.py" "$mode" "$note_hold_tone" "$evidence" >"$note_hold_evidence/$mode-$variant.out" 2>&1 || status=$?
      if [[ $mode != deadline ]]; then
        kill -CONT "$shell_qs_pid"
        note_audio_shell_stopped=no
      fi
      if [[ $variant == actual ]]; then
        expect "native hold $mode reaches its required real route" 0 echo "$status"
      else
        case $mode in
          restart) result='restart chime routes to mute hold before shell event' ;;
          lease) result='dead acquired lease routes new chime to real output' ;;
          deadline) result='deadline stream reaches real output within hold bound' ;;
        esac
        expect "native hold $mode control fails its actual routing assertion" 1 echo "$status"
        expect "native hold $mode control identifies its own defect" yes notification_hold_control_result "$note_hold_evidence/$mode-$variant.out" "$result"
      fi
    done
    [[ $mode != deadline ]] || notification_hold_restore_delivery
  done
  notification_hold_install
  expect "Sound returns on after native hold cases" on notes sound on
}

notification_hold_writer() {
  if "${shell_env[@]}" python3 "$note_hold_fixture/hold-native.py" writer "$shell_qs_pid" >"$sandbox/notification-writer.json" 2>/dev/null; then echo acquired; else echo waiting; fi
}
notification_hold_notice() {
  ipc smoke statusValues vgs.notifications | py_reply 'import json,sys
value=json.load(sys.stdin).get("soundRuleSetup",{})
print(value.get("available") is False and value.get("tone")=="info" and bool(value.get("hint")))'
}
notification_hold_version() {
  "${shell_env[@]}" pw-dump | py_reply 'import json,sys
objects=json.load(sys.stdin)
values=[m.get("value") for o in objects if o.get("type")=="PipeWire:Interface:Metadata" and o.get("props",{}).get("metadata.name")=="vgs-notification-sounds" for m in o.get("metadata",[]) if m.get("key")=="version"]
print(json.dumps(values[0]) if len(values)==1 else "absent")'
}
notification_hold_control_result() {
  python3 -c 'import pathlib,sys; print("yes" if pathlib.Path(sys.argv[1]).read_text().strip()=="hold-native: failed="+sys.argv[2] else "no")' "$1" "$2"
}
