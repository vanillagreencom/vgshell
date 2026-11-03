# Stay awake (VGS-2257): `shell.idle.stayAwake` holds the core's idle
# pause through its `stayAwake` source, the one pause every idle watch
# obeys (D116), for a whole number of seconds or until it is ended. The
# fixture acme.stayawake takes holds through capability `idle`, read
# through the lending record's `idlePause`; that every watch obeys the
# pause is scripts/smoke/rows/idle-inhibit.sh's. The row reads:
# - the provider refuses a hold past a day with the core's refusal;
# - a hold until released pauses the idle source;
# - of two holds, ending the second keeps the pause, and ending the first
#   ends it;
# - a 2 s hold ends by its timer and calls its end once, and a hold
#   released before its timer calls no end;
# - disabling the holder ends its hold, and the holder built again holds
#   none, since nothing stores a hold;
# - on a copy whose holds check their end every second
#   (STAY_AWAKE_STEP_MS 1000), a 4 s hold is still held at 2 s and ends
#   at its time with one end call: the timer re-arms after a check that
#   finds time left;
# - on a copy that also reads the clock an hour on at each check, as at
#   the wake from an hour's suspend, a 600 s hold ends at its first check:
#   the first wait is one step and the end is judged from the wall clock.
# The wait arithmetic is scripts/test-plugin-logic.js's stayAwakeWait
# rows. vgs.power's own hold, its timer end, its End, the critical
# battery end and the unchanged settings file are
# scripts/smoke/rows/power.sh's.
# Controls, each a copy of the tree started in place of it with one edit
# to shell/Core/IdleRegistry.qml: a hold that sets no pause source, a
# timer that never starts, an end that ends nothing, a hold the
# instance's lifetime does not hold, and, on the stepped copies, a timer
# that never re-arms and a first wait of the whole hold. Each control
# runs the row's own check and passes only on that check's failure. The
# row restores the user file and removes its fixture.
# A released hold's end is read 3 s after its 2 s timer would have fired,
# and a stepped hold 2 s after it was taken, since no event marks a thing
# that did not happen. Every other reading polls through expect_poll; no
# latency budget is claimed.
# inputs: scripts/smoke/fixtures/plugins/acme.stayawake/* shell/Core/IdleRegistry.qml shell/Core/Capabilities.qml shell/Core/PluginLogic.js shell/Core/Lifetime.js shell/Core/Plugins.qml
set -euo pipefail
sa_config="$home/.config/vgshell/shell.json"
sa_saved="$sandbox/stay-awake-shell-before.json"
sa_fixture="$home/.config/vgshell/plugins/acme.stayawake"
sa_held='[["stayAwake"], ["acme.stayawake"]]'
sa_free='[[], []]'
cp -- "$sa_config" "$sa_saved"
mkdir -p -- "$sa_fixture"
cp -R "$repo/scripts/smoke/fixtures/plugins/acme.stayawake/." "$sa_fixture/"

# The pause's sources and the plugin id of each Stay awake hold, from the
# lending record.
sa_pause() { ipc shell lent | py_reply 'import json,sys; p=json.load(sys.stdin).get("idlePause"); print("absent" if p is None else json.dumps([p.get("sources"), p.get("stayAwake")]))'; }
# IPC invoke takes one argument, empty for a handler that reads none.
sa_invoke() { ipc acme.stayawake invoke "$1" "${2:-}"; }
sa_built() {
  rescan "a rescan after adding the Stay awake fixture answers ok"
  expect_poll "the Stay awake fixture is discovered" True plugin_known acme.stayawake
  expect "enabling the Stay awake fixture is allowed" ok ipc shell setPluginEnabled acme.stayawake true
  expect_poll "the Stay awake fixture is built" True record_exists acme.stayawake
}
sa_hold_check() {
  expect "the fixture takes a hold until released" ok sa_invoke hold 0
  expect_poll "a hold pauses the idle source" "$sa_held" sa_pause
}
sa_release_check() {
  expect "the fixture ends its hold" ok sa_invoke release
  expect_poll "the end ends the hold" "$sa_free" sa_pause
}
sa_timer_check() {
  expect "the fixture takes a 2 s hold" ok sa_invoke hold 2
  expect_poll "the 2 s hold pauses the idle source" "$sa_held" sa_pause
  expect_poll "the timer ends the hold" "$sa_free" sa_pause
}
sa_disable_check() {
  expect "disabling the holder is allowed" ok ipc shell setPluginEnabled acme.stayawake false
  expect_poll "disabling the holder ends its hold" "$sa_free" sa_pause
}
# The two checks a control runs over a hold it takes first.
sa_held_release_check() { sa_hold_check; sa_release_check; }
sa_held_disable_check() { sa_hold_check; sa_disable_check; }
# sa_must_fail LABEL CHECK CMD...: CMD, run in a subshell against a control
# copy, holds the row's own check labelled CHECK and must fail that check
# and nothing else.
sa_controls=0
sa_must_fail() { # LABEL CHECK CMD...
  local label="$1" check="$2" log others="" found
  sa_controls=$((sa_controls + 1))
  log="$sandbox/stay-awake-control-$sa_controls.log"
  shift 2
  ( "$@" ) >"$log" 2>&1 || true
  if found="$(grep -F -- '  FAIL  ' "$log" | grep -v -F -- "  FAIL  $check: ")"; then others="$found"; fi
  if [[ -n $others ]]; then
    fail "control: $label: another check failed: ${others//$'\n'/ | }"
  elif grep -q -F -- "  FAIL  $check: " "$log"; then
    ok "control: $label"
  else
    fail "control: $label: the row's check passed"
  fi
  control_output "$log"
}
# sa_copy NAME [FILE OLD NEW]...: a copy of the tree with OLD in each
# FILE, a path under it, replaced by NEW, started in place of the running
# shell with the fixture built and no hold. Returns 1, with the row
# failed, when an edit or the start fails.
sa_copy() { # NAME [FILE OLD NEW]...
  local name="$1"
  shift
  copy_tree "$name"
  while (( $# >= 3 )); do
    edit_tree "$name" "$1" "$2" "$3" || return 1
    shift 3
  done
  stop_shell || :
  start_shell "$sandbox/tree-$name" "$sandbox/$name.log" || return 1
  expect_poll "the $name copy builds the fixture" True record_exists acme.stayawake
  expect_poll "the $name copy starts with no hold" "$sa_free" sa_pause
}
# sa_control NAME OLD NEW LABEL CHECK CMD...: a copy of the tree with OLD
# in IdleRegistry.qml replaced by NEW, started by sa_copy, and CMD run
# against it as sa_must_fail runs it.
sa_control() { # NAME OLD NEW LABEL CHECK CMD...
  local name="$1" old="$2" new="$3"
  shift 3
  sa_copy "$name" shell/Core/IdleRegistry.qml "$old" "$new" || return 0
  sa_must_fail "$@"
}
# The copy edits that make a hold check its end every second, and read the
# clock an hour later at each check, as a timer stopped by an hour's
# suspend reads it at the wake.
sa_step=(shell/Core/PluginLogic.js 'var STAY_AWAKE_STEP_MS = 60000;' 'var STAY_AWAKE_STEP_MS = 1000;')
sa_slept=(shell/Core/IdleRegistry.qml 'const wait = Logic.stayAwakeWait(endsAt, Date.now());' 'const wait = Logic.stayAwakeWait(endsAt, Date.now() + 3600000);')
# A 4 s hold checked every second, read at 2 s: a timer that re-arms after
# a check that finds time left still holds it, one that stops at its first
# check ended it at 1 s.
sa_rearm_check() {
  expect "the fixture takes a 4 s hold" ok sa_invoke hold 4
  sleep 2
  expect "a 4 s hold checked every second is held at 2 s" "$sa_held" sa_pause
  expect_poll "a 4 s hold checked every second ends at its time" "$sa_free" sa_pause
  expect "the stepped hold's end runs once" 1 sa_invoke ends
}
# A 600 s hold whose first check reads the clock an hour on ends at that
# check, a second after it was taken; a first wait of the whole hold
# would not check for ten minutes.
sa_slept_check() {
  expect "the fixture takes a 600 s hold" ok sa_invoke hold 600
  expect_poll "a 600 s hold whose end passed asleep ends at its first check" "$sa_free" sa_pause
}

sa_built
expect_poll "with no hold the pause holds no Stay awake source" "$sa_free" sa_pause
expect "the provider refuses a hold past a day" "refused: stay-awake=86401 want=0..86400" sa_invoke hold 86401
expect "a refused hold pauses nothing" "$sa_free" sa_pause

sa_hold_check
expect "the fixture takes a second hold" ok sa_invoke hold 0
expect "the second hold is ended" ok sa_invoke release
expect "the first hold keeps the pause" "$sa_held" sa_pause
sa_release_check

sa_timer_check
expect_poll "the timer calls the hold's end once" 1 sa_invoke ends
expect "the fixture takes a 2 s hold to release" ok sa_invoke hold 2
expect "the fixture releases it before its timer" ok sa_invoke release
expect_poll "the released hold ends the pause" "$sa_free" sa_pause
sleep 3
expect "a released hold's timer calls no end" 1 sa_invoke ends

sa_hold_check
sa_disable_check
expect "enabling the holder again is allowed" ok ipc shell setPluginEnabled acme.stayawake true
expect_poll "the holder is built again" True record_exists acme.stayawake
expect "the holder built again holds nothing" "$sa_free" sa_pause

if sa_copy stay-awake-step "${sa_step[@]}"; then sa_rearm_check; fi
stop_shell || :
if sa_copy stay-awake-slept "${sa_step[@]}" "${sa_slept[@]}"; then sa_slept_check; fi
stop_shell || :

if sa_copy stay-awake-unarmed "${sa_step[@]}" shell/Core/IdleRegistry.qml $'                if (wait > 0) {\n                    timer.interval = wait;\n                    timer.start();\n                    return;\n                }\n' ''; then
  sa_must_fail "a timer that never re-arms ends a hold at its first check" "a 4 s hold checked every second is held at 2 s" sa_rearm_check
fi
stop_shell || :
if sa_copy stay-awake-whole "${sa_step[@]}" "${sa_slept[@]}" shell/Core/IdleRegistry.qml '{ interval: Logic.stayAwakeWait(endsAt, Date.now()) }' '{ interval: seconds * 1000 }'; then
  sa_must_fail "a first wait of the whole hold misses an end that passed asleep" "a 600 s hold whose end passed asleep ends at its first check" sa_slept_check
fi
stop_shell || :
sa_control stay-awake-unpaused '        setPause("stayAwake", true);' '' \
  "a hold that sets no pause source pauses nothing" "a hold pauses the idle source" sa_hold_check
stop_shell || :
sa_control stay-awake-untimed $'            timer.start();\n        }\n        const next' $'        }\n        const next' \
  "a timer that never starts keeps the hold" "the timer ends the hold" sa_timer_check
stop_shell || :
sa_control stay-awake-kept '        return Object.freeze({ endsAt: endsAt, end: release });' '        return Object.freeze({ endsAt: endsAt, end: () => {} });' \
  "an end that ends nothing keeps the hold" "the end ends the hold" sa_held_release_check
stop_shell || :
sa_control stay-awake-unowned '        const release = ctx.onDispose(end);' '        const release = end;' \
  "a hold the lifetime does not hold outlives its holder" "disabling the holder ends its hold" sa_held_disable_check
stop_shell || :

start_shell "$repo" "$sandbox/stay-awake-restored.log"
user_config_restore "$sa_saved"
expect "reloading the user file the row found is allowed" ok ipc shell reloadConfig
expect "disabling the Stay awake fixture is allowed" ok ipc shell setPluginEnabled acme.stayawake false
rm -rf -- "${sa_fixture:?}"
rescan "a rescan removes the Stay awake fixture"
expect_poll "acme.stayawake is absent after the row" False plugin_known acme.stayawake
expect "the row leaves no Stay awake hold" "$sa_free" sa_pause
