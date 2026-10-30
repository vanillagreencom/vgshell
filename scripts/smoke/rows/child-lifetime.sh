# Managed Process children and ordinary descendants end with their shell.
# Actual Sound and Lock services run against the existing private audio
# world and inert sleep tools; a stubborn fork of the fake dbus-monitor
# proves cleanup reaches descendants. Quickshell.execDetached's bounded
# fixture survives, preserving the intentional application handoff.
# Each case holds pidfds before ending the shell and reads their exit
# before cleanup. The observer polls at 20 ms with a 10 s completion bound;
# this is a cleanup guarantee, not a latency measurement. Run the same row
# against the pre-fix engine to prove its survivor assertion fails.
# inputs: scripts/smoke/fixtures/child-lifetime.py scripts/smoke/fixtures/devices/* shell/plugins/vgs.sound/* shell/plugins/vgs.lock/* shell/Core/Registry.qml shell/Core/Capabilities.qml bin/vgshell bin/vgshell-scan packaging/arch/vgshell-quickshell/* scripts/smoke/rows/device-fakes.sh
set -euo pipefail
devices_ready child-lifetime || return 0

cl_config="$home/.config/vgshell/shell.json"
cl_saved="$sandbox/child-lifetime-config.json"
cp -- "$cl_config" "$cl_saved"
devices_child_lifetime_setup
mkfifo -- "$devices_dir/pactl.events"
device_reply pactl 0 '[]' --format=json list sources
device_reply pactl 0 '[]' --format=json list cards
expect "the fixture lock holder releases its exclusive capability" ok ipc shell setPluginEnabled acme.probe false
expect "Sound is enabled for its subscriber" ok ipc shell setPluginEnabled vgs.sound true
expect "Lock is enabled for its sleep watcher" ok ipc shell setPluginEnabled vgs.lock true

cl_ready() {
  local value
  value="$(ipc smoke statusValues vgs.lock | py_reply 'import json,sys; print(json.load(sys.stdin).get("sleep", {}).get("tone", "absent"))')" || return
  [[ $value == ok && -s $devices_dir/pactl.subscriber && -s $devices_dir/child-lifetime.stubborn ]] && echo ready || echo waiting
}
cl_file() { if [[ -s $1 ]]; then echo ready; else echo waiting; fi; }
cl_crash_report() { local reports; reports="$(shell_crash_reports)"; [[ -n $reports ]] && echo ready || echo waiting; }
cl_verdict() {
  [[ -s $1 ]] || { echo absent; return; }
  # py_reply judges its stdin; the observer's result is that reply.
  py_reply 'import json,sys; d=json.load(sys.stdin); print("ended detached-alive acknowledged" if not d["survivors"] and d["detachedAlive"] and d["cleanupAcknowledged"] else json.dumps(d, sort_keys=True))' <"$1"
}

for cl_case in orderly hard crash; do
  expect_poll "$cl_case: subscriber and sleep watcher are ready" ready cl_ready
  cl_prefix="$sandbox/child-lifetime-$cl_case"
  cl_gate="$cl_prefix.detached-gate"
  expect "$cl_case: intentional detached work starts" ok ipc smoke holdUntil "$cl_gate" 120
  "${shell_env[@]}" python3 "$repo/scripts/smoke/fixtures/child-lifetime.py" observe "$shell_qs_pid" "$cl_prefix" "$cl_gate" "$devices_dir" >"$cl_prefix.observer.log" 2>&1 &
  cl_observer=$!
  expect_poll "$cl_case: pidfds hold the complete managed tree and detached work" ready cl_file "$cl_prefix.ready"
  if [[ ! -s $cl_prefix.ready ]]; then
    [[ ! -f $cl_prefix.error ]] || cat -- "$cl_prefix.error"
    fail "$cl_case: child inventory did not finish"
    touch -- "$cl_prefix.check" "$cl_gate"
    wait "$cl_observer" || true
    break
  fi
  cat -- "$cl_prefix.ready"
  cl_killed="$shell_qs_pid"
  case "$cl_case" in
    orderly) stop_shell ;;
    hard) kill -KILL "$cl_killed" ;;
    crash) shell_crash_expect "$cl_killed" && kill -SEGV "$cl_killed" ;;
  esac
  touch -- "$cl_prefix.check"
  cl_status=0
  wait "$cl_observer" || cl_status=$?
  expect "$cl_case: no managed child survives, responsive cleanup ran, and detached work remains" 'ended detached-alive acknowledged' cl_verdict "$cl_prefix.result"
  expect "$cl_case: the process observer completed successfully" 0 echo "$cl_status"
  cat -- "$cl_prefix.result"
  touch -- "$cl_gate"
  if [[ $cl_case == orderly ]]; then
    start_shell "$repo" "$sandbox/child-lifetime-after-$cl_case.log"
  else
    adopt_shell "$cl_killed"
  fi
  if [[ $cl_case == crash ]]; then
    expect_poll "the intentional crash has a retained report" ready cl_crash_report
    shell_crash_consume "$cl_prefix.crashes" || :
    cat -- "$cl_prefix.crashes"
  fi
  [[ $cl_status == 0 ]] || break
done

# Control: a declared crash that never happens fails the row. It must also
# read no report, or a real crash it marked read would not reach the
# boundary's crash check.
cl_crash_absent() {
  (failures=0 behaviour_failures=0 smoke_row_crash_expected=""
   shell_crash_expect "$shell_qs_pid" && shell_crash_consume "$sandbox/child-lifetime-absent.crashes" >"$sandbox/child-lifetime-absent.log" 2>&1 || :
   if [[ -s $sandbox/child-lifetime-absent.crashes ]]; then echo "$failures reports=read"; else echo "$failures reports=none"; fi)
}
expect "control: a declared crash that never happens fails the row" "1 reports=none" cl_crash_absent

stop_shell || true
cp -- "$cl_saved" "$cl_config"
devices_child_lifetime_restore
rm -f -- "${devices_dir:?}/pactl.events" "${devices_dir:?}/pactl.subscriber" "${devices_dir:?}/child-lifetime.stubborn"
rm -f -- "${devices_dir:?}/child-lifetime.responsive" "${devices_dir:?}"/child-lifetime.term-ack.*
device_reply_clear pactl
start_shell "$repo" "$sandbox/child-lifetime-restored.log"
