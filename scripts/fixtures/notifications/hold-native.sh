# The notifications row's real-store restart, lease and missed-delivery cases.
# The 15000 ms hold policy is carried by the shell entry, not restated here.
# hold-native.py polls the real graph every 10 ms and retains each reading.
# The deadline case is a timer-wiring check, not a latency benchmark: it
# proves the real timer releases the hold within its bound. Its timed
# window is judged as docs/architecture/validation.md § Latency budgets
# judges a reading, "by the CPU pressure of its own world": a late release
# above harness.sh's latency_pressure_limit is not measured, and at or
# below it fails. A hold that never releases fails at any pressure, as that
# section's run that never ends does; the deadline control rests on that
# failure. Every other judge kind proves the route or the hold, not its
# timing, and fails at any pressure, as the restart and lease cases do.
set -euo pipefail
note_hold_active=no
note_hold_delivery_backup=""
note_hold_deadline_backup=""
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
  [[ -n $note_hold_delivery_backup || -n $note_hold_deadline_backup ]] || return 0
  if [[ -n $note_hold_delivery_backup ]]; then
    node "$note_hold_fixture/held-delivery.js" restore-held "$repo/shell/plugins/vgs.notifications/Service.qml" "$note_hold_delivery_backup" || return 1
    note_hold_delivery_backup=""
  fi
  if [[ -n $note_hold_deadline_backup ]]; then
    node "$note_hold_fixture/held-delivery.js" restore-deadline "$repo/shell/plugins/vgs.notifications/NotificationLogic.js" "$note_hold_deadline_backup" || return 1
    note_hold_deadline_backup=""
  fi
  rescan "the row restores the actual rule-held delivery"
}

notification_hold_cases() {
  local mode variant status result evidence world_us host_us start_ms window_ms pressure
  python3 "$note_hold_fixture/hold-native.py" judge-controls
  expect "control: the native hold deadline excuses only a late release, and only by its world's pressure" ok notification_hold_deadline_cases
  expect_poll "the custom audio deployment reports unsupported bootstrap" '"unavailable"' note_status soundRule.phase
  expect "unsupported bootstrap publishes the Settings requirement" True notification_hold_notice
  for mode in restart lease deadline; do
    if [[ $mode == deadline ]]; then
      expect_poll "the published policy has its acquired writer before the timer fixture" acquired notification_hold_writer
      expect "the published hold keeps the production duration" 15000 python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["deadlineMs"])' "$sandbox/notification-writer.json"
      note_hold_delivery_backup="$sandbox/notification-held-delivery"
      note_hold_deadline_backup="$sandbox/notification-short-deadline"
      node "$note_hold_fixture/held-delivery.js" suppress-held "$repo/shell/plugins/vgs.notifications/Service.qml" "$note_hold_delivery_backup"
      # This exercises the same real timeout callback, not fifteen seconds
      # of policy already held by test-notifications-logic.js. The native
      # reader takes its duration from the published deadlineMs.
      node "$note_hold_fixture/held-delivery.js" short-deadline "$repo/shell/plugins/vgs.notifications/NotificationLogic.js" "$note_hold_deadline_backup"
      rescan "the native missed-frame case omits the actual rule-held delivery"
    fi
    for variant in actual control; do
      notification_hold_install
      expect "Sound turns off before the native hold case" off notes sound off
      expect_poll "the native hold entry has an acquired shell writer" acquired notification_hold_writer
      if [[ $mode == deadline ]]; then
        expect "the real timer reads the fixture's short published duration" 1000 python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["deadlineMs"])' "$sandbox/notification-writer.json"
      fi
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
      if [[ $mode == deadline && $variant == actual ]]; then
        world_us="$(cpu_some_us)" host_us="$(host_cpu_some_us)" start_ms="$(now_ms)"
      fi
      status=0
      "${shell_env[@]}" python3 "$note_hold_fixture/hold-native.py" "$mode" "$note_hold_tone" "$evidence" >"$note_hold_evidence/$mode-$variant.out" 2>&1 || status=$?
      if [[ $mode == deadline && $variant == actual ]]; then
        window_ms=$(( $(now_ms) - start_ms ))
        pressure="$(cpu_some_pct "$world_us" "$(cpu_some_us)" "$window_ms")"
        printf '  native_hold_deadline status=%s window_ms=%s cpu_some_pct=%s host_cpu_some_pct=%s\n' "$status" "$window_ms" "$pressure" "$(cpu_some_pct "$host_us" "$(host_cpu_some_us)" "$window_ms")"
      fi
      if [[ $mode != deadline ]]; then
        kill -CONT "$shell_qs_pid"
        note_audio_shell_stopped=no
      fi
      if [[ $variant == actual && $mode == deadline ]]; then
        notification_hold_deadline_check "$status" "$pressure"
      elif [[ $variant == actual ]]; then
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
  expect_poll "the production policy has an acquired writer after the timer fixture" acquired notification_hold_writer
  expect "the timer fixture restores the published production duration" 15000 python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["deadlineMs"])' "$sandbox/notification-writer.json"
  expect "Sound returns on after native hold cases" on notes sound on
}

# notification_hold_deadline_verdict STATUS CPU_SOME_PCT: pass for status
# 0 and failed for any status but 3, hold-native.py's LATE_RELEASE_STATUS.
# A late release takes latency_pressure_verdict's answer for a miss:
# unmeasured above the limit, over at or below it, and unread for a
# pressure that is not a reading.
notification_hold_deadline_verdict() {
  if [[ $1 == 0 ]]; then echo pass
  elif [[ $1 == 3 ]]; then latency_pressure_verdict 1 "$2" 0
  else echo failed
  fi
}
notification_hold_deadline_check() { # STATUS CPU_SOME_PCT
  local verdict
  verdict="$(notification_hold_deadline_verdict "$1" "$2")"
  case "$verdict" in
    pass) ok "native hold deadline reaches its required real route" ;;
    unmeasured) not_measured notifications "native_hold_deadline-late-release-cpu_some_pct=$2-above-$latency_pressure_limit" ;;
    *) fail "native hold deadline reaches its required real route: got $1 verdict=$verdict cpu_some_pct=$2" ;;
  esac
}
# The control for that check: each named judge-controls case of
# hold-native.py runs through the native run's exit path, and its status is
# checked at a literal world pressure, as the row's actual case is. A row
# reads the failures and not-measured records it adds. The subshell keeps
# them, and its check-secs and journal writes, out of the row's own outcome.
# A late release is excused only above the limit, an unread pressure never
# excuses one, and a hold that never releases or an unproved hold
# transition fails at any pressure.
notification_hold_deadline_cases() {
  local dir="$sandbox/hold-deadline-pressure" name pressure failed unmeasured message status got
  mkdir -p -- "$dir"
  while read -r name pressure failed unmeasured message; do
    status=0
    python3 "$note_hold_fixture/hold-native.py" judge-planted "$name" >"$dir/$name.out" 2>&1 || status=$?
    if [[ $message == - ]]; then [[ ! -s $dir/$name.out ]] || { echo "case=$name output=unexpected"; return; }
    elif [[ $(notification_hold_control_result "$dir/$name.out" "$message") != yes ]]; then echo "case=$name output=unmatched"; return
    fi
    got="$(failures=0 behaviour_failures=0 not_measured_rows=() smoke_check_fd=""
      notification_hold_deadline_check "$status" "$pressure" >"$dir/$name-$pressure-check.log"
      printf '%s %s' "$failures" "${#not_measured_rows[@]}")"
    [[ $got == "$failed $unmeasured" ]] || { echo "case=$name pressure=$pressure status=$status got=$got want=$failed $unmeasured"; return; }
  done <<'CASES'
direct-crossing 50.0 0 0 -
late-release 2.8 1 0 deadline-bracket:late-release
late-release 2.9 0 1 deadline-bracket:late-release
late-release unmeasured 1 0 deadline-bracket:late-release
unproved-silence 50.0 1 0 deadline-bracket:hold-transition-unproved
no-release 50.0 1 0 deadline stream reaches real output within hold bound
CASES
  echo ok
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
