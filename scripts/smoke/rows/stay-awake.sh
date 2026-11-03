# Stay awake (VGS-2257): `shell.idle.stayAwake` holds the core's idle
# pause through its `stayAwake` source, the one pause every idle watch
# obeys (D116), for a whole number of seconds or until its disposer runs.
# The fixture acme.stayawake takes holds and one plain idle watch through
# capability `idle`, read through the lending record's `idlePause`. The
# row reads:
# - the provider refuses a hold past a day with the core's refusal;
# - a hold until released pauses the idle source and holds a 1 s watch
#   past its time;
# - of two holds, the second one's disposer keeps the pause, and the
#   first's ends it, after which the watch goes idle;
# - a 2 s hold ends by its timer and calls its end once, and a hold
#   released before its timer calls no end;
# - disabling the holder ends its hold, and the holder built again holds
#   none, since nothing stores a hold.
# vgs.power's own hold, its End, the critical battery end and the
# unchanged settings file are scripts/smoke/rows/power.sh's.
# Controls, each a copy of the tree started in place of it with one edit
# to shell/Core/IdleRegistry.qml: a hold that sets no pause source, a
# timer that never starts, a disposer that ends nothing and a hold the
# instance's lifetime does not hold. Each control runs the row's own check
# and passes only on that check's failure. The row restores the user file
# and removes its fixture.
# A held watch is read 3 s after it was created, three times its 1 s
# time, and a released hold's end 3 s after its 2 s timer would have
# fired, since no event marks a thing that did not happen. Every other
# reading polls through expect_poll; no latency budget is claimed.
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
# The fixture's plain 1 s watch: `true` or `false` while it is idle or
# not, `none` with no such watch.
sa_watch() { ipc shell lent | py_reply 'import json,sys; w=[x for x in json.load(sys.stdin)["idle"] if x["id"] == "acme.stayawake" and x["timeout"] == 1]; print(json.dumps(w[0]["idle"]) if len(w) == 1 else "none")'; }
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
  expect "the fixture runs its hold's disposer" ok sa_invoke release
  expect_poll "the disposer ends the hold" "$sa_free" sa_pause
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
  local label="$1" check="$2" log others
  sa_controls=$((sa_controls + 1))
  log="$sandbox/stay-awake-control-$sa_controls.log"
  shift 2
  ( "$@" ) >"$log" 2>&1 || true
  others="$(grep -F -- '  FAIL  ' "$log" | grep -v -F -- "  FAIL  $check: " || true)"
  if [[ -n $others ]]; then
    fail "control: $label: another check failed: ${others//$'\n'/ | }"
  elif grep -q -F -- "  FAIL  $check: " "$log"; then
    ok "control: $label"
  else
    fail "control: $label: the row's check passed"
  fi
  control_output "$log"
}
# sa_control NAME OLD NEW LABEL CHECK CMD...: a copy of the tree with OLD
# in IdleRegistry.qml replaced by NEW, started with the fixture built, and
# CMD run against it as sa_must_fail runs it.
sa_control() { # NAME OLD NEW LABEL CHECK CMD...
  local name="$1" old="$2" new="$3"
  shift 3
  copy_tree "$name"
  edit_tree "$name" shell/Core/IdleRegistry.qml "$old" "$new" || return 0
  stop_shell || :
  start_shell "$sandbox/tree-$name" "$sandbox/$name.log" || return 0
  expect_poll "control: the $name copy builds the fixture" True record_exists acme.stayawake
  expect_poll "control: the $name copy starts with no hold" "$sa_free" sa_pause
  sa_must_fail "$@"
}

sa_built
expect_poll "with no hold the pause holds no Stay awake source" "$sa_free" sa_pause
expect "the provider refuses a hold past a day" "refused: stay-awake=86401 want=0..86400" sa_invoke hold 86401
expect "a refused hold pauses nothing" "$sa_free" sa_pause

sa_hold_check
expect "the fixture takes a 1 s watch during the hold" ok sa_invoke watch 1
sleep 3
expect "a hold keeps a 1 s watch from going idle past its time" false sa_watch
expect "the fixture takes a second hold" ok sa_invoke hold 0
expect "the second hold's disposer is run" ok sa_invoke release
expect "the first hold keeps the pause" "$sa_held" sa_pause
sa_release_check
expect_poll "the watch counts again and goes idle" true sa_watch
expect "the disposer again ends nothing more" none sa_invoke release

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
expect "the holder built again counts no end" 0 sa_invoke ends

sa_control stay-awake-unpaused '        setPause("stayAwake", true);' '' \
  "a hold that sets no pause source pauses nothing" "a hold pauses the idle source" sa_hold_check
stop_shell || :
sa_control stay-awake-untimed '            timer.start();' '' \
  "a timer that never starts keeps the hold" "the timer ends the hold" sa_timer_check
stop_shell || :
sa_control stay-awake-kept $'        setPause("stayAwake", true);\n        return release;' $'        setPause("stayAwake", true);\n        return () => {};' \
  "a disposer that ends nothing keeps the hold" "the disposer ends the hold" sa_held_release_check
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
