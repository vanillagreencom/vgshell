# The polkit agent, vgs.polkit: a first-party service and overlay. The
# harness starts it disabled, since polkit is exclusive and the capability
# rows' fixture, acme.probe, holds it. This row disables the fixture when
# an earlier row left it enabled, enables vgs.polkit once no plugin holds
# polkit, reads the agent the core lends it
# and the agent status its service publishes back, asserts that no prompt
# surface exists without an authentication flow and that a summon with none
# is refused, and disables it again, which destroys the agent.
#
# A live flow cannot run here: it needs polkitd and the setuid
# polkit-agent-helper-1, which would run PAM against the real account and
# could trip pam_faillock. The sandbox's system bus has no polkitd, so the
# agent stays unregistered. The row reads that no flow ever went live, from
# the core's count over the shell's whole life, which the row never
# restarts, and that the harness's helper watcher saw no
# polkit-agent-helper-1 or other authentication helper over the whole row;
# the lock row's stand-in is the watcher's control. What the prompt draws from a flow is
# scripts/test-polkit-model.js's.
#
# The control installs a copy of the plugin in the user directory, whose id
# wins, with the prompt's refusal of a flowless summon removed: the same
# summon reading maps a prompt then, so the reading is not vacuous.
#
# Another agent in the way. A stand-in polkitd, fixtures/polkit/authority.py,
# joins the sandbox's system bus: it takes one agent, refuses a second, and
# never begins an authentication. A stand-in agent, fixtures/polkit/agent.py
# run from a copy of the Python interpreter named polkit-acme-agent,
# registers with it first. A stand-in pacman in the shell's stand-in
# directory is the package manager: it names acme-polkit as the owner of
# that program, and its removal dry run answers from a file the row plants,
# so the row reads Uninstall while nothing requires the package and Stop
# while another installed package does; the two readings are each other's
# control. The row presses each through the Settings window's act and reads
# the plugin's own TUI in the argv the stand-in terminal recorded. That
# terminal runs no shipped script, so the row ends the stand-in agent
# itself while the run is held, as the step does, and reads that VGS's agent
# registers when the run ends, in the shell the row started with. In the
# Stop stage a second stand-in agent runs, the same interpreter copied as
# polkit-beta-agent, which pacman names as beta-polkit's: the row reads
# that the status value names both and that the page draws one Badge for
# each. The Uninstall stage, with one agent, reads one Badge and is that
# reading's control. A program
# `stop` recorded is ended by the service's own check, with no press. The
# last control is a plugin copy whose service never asks polkitd again:
# after the same steps its agent stays unregistered. The host needs pacman
# as its primary package manager, as the Dev Tools row does. The row ends
# with vgs.polkit disabled and the fixture as it found it.
#
# The row reads no latency: each reading polls at the harness's interval
# until the harness's ceiling.
# inputs: shell/plugins/vgs.polkit/* shell/Core/Capabilities.qml shell/Core/PluginLogic.js shell/Core/PluginStatus.qml shell/Core/PackageManagers.js shell/Core/TuiRunner.qml shell/plugins/vgs.settings/* scripts/smoke/fixtures/polkit/* scripts/smoke/rows/capabilities.sh bin/vgshell bin/vgshell-pkg bin/vgshell-tui bin/lib/qml-library.js
set -euo pipefail
polkit_lent() { ipc shell lent | py_reply 'import json,sys; v=json.load(sys.stdin)
for k in sys.argv[1].split("."): v=v.get(k) if isinstance(v, dict) else None
print(json.dumps(v))' "$1"; }
polkit_status() { ipc smoke statusValues vgs.polkit | py_reply 'import json,sys; v=json.load(sys.stdin).get("agent"); print(json.dumps(v if v is None else [v["tone"], v["text"], v.get("lines", [])]))'; }
# The Badges the Settings window draws for the other agents, as their texts.
polkit_badges() { ipc smoke itemTexts window vgs.settings Badge | py_reply 'import json,sys; print(json.dumps([t for badge in json.load(sys.stdin) for t in badge if t.startswith("Another app is showing password prompts: ")]))'; }
# The summon a request would make, with no request live: the host's answer.
flowless_summon() { ipc shell summon overlay vgs.polkit '{}'; }
unregistered='["warning", "Password prompts are unavailable. No other app is showing them.", []]'
ready='["ok", "Ready to show password prompts", []]'
other='["warning", "Another app is showing password prompts: acme-polkit.", []]'
# With the second agent, which starts first and so is the first the scan
# of /proc reads.
other_two='["warning", "Another app is showing password prompts: beta-polkit.", ["Another app is showing password prompts: acme-polkit."]]'

auth_watch_start "$sandbox/polkit-auth-helpers.log"
expect "the helper watcher scans the tree that holds the shell" yes in_harness_tree "$shell_qs_pid"
expect "the polkit plugin starts disabled in the sandbox" False plugin_enabled vgs.polkit
probe_enabled="$(plugin_enabled acme.probe)" || probe_enabled=unreadable
case "$probe_enabled" in
  True) expect "disabling the capability fixture, which holds polkit, is allowed" ok ipc shell setPluginEnabled acme.probe false ;;
  False|absent) ;;
  *) fail "the capability fixture's enabled state is unreadable: $probe_enabled" ;;
esac
expect_poll "no plugin holds polkit before the row" null polkit_lent holders.polkit
expect_poll "the core builds no agent while nothing holds polkit" false polkit_lent polkitAgent
expect "enabling the polkit plugin is allowed" ok ipc shell setPluginEnabled vgs.polkit true
expect_poll "the polkit service is built" True record_exists vgs.polkit
expect_poll "vgs.polkit holds polkit" '["vgs.polkit"]' polkit_lent holders.polkit
expect_poll "the core built the agent for it" true polkit_lent polkitAgent
expect "the agent is not registered on a bus without polkitd" false polkit_lent polkitRegistered
expect_poll "the service publishes that polkitd did not accept the agent and no other app holds the session" "$unregistered" polkit_status
expect "no prompt surface exists without a flow" 0 layer_count vgs:overlay
expected_errors+=('summon host: vgs\.polkit open\(\) failed: polkit: refused: flow=none')
expect "a summon with no flow is refused" "refused: open-failed=vgs.polkit" flowless_summon
expect "the refused summon maps no prompt surface" 0 layer_count vgs:overlay
expect "no authentication helper runs under the shell" none auth_helpers "$shell_qs_pid"

# Control: the same reading over a prompt that opens with no flow.
control_dir="$home/.config/vgshell/plugins/vgs.polkit"
mkdir -p -- "$control_dir"
cp -R -- "$repo/shell/plugins/vgs.polkit/." "$control_dir/"
python3 - "$control_dir/Prompt.qml" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
needle = '        if (flow === null) throw new Error("polkit: refused: flow=none");\n'
assert text.count(needle) == 1, "polkit control: the refusal must match once"
open(path, "w").write(text.replace(needle, ""))
PY
expected_errors+=('plugins: .*vgs\.polkit')
rescan "rescan over the control copy answers ok"
control_dir_of() { ipc shell listPlugins | py_reply 'import json,sys; print([p["dir"] for p in json.load(sys.stdin)["plugins"] if p["id"] == "vgs.polkit"][0])'; }
expect_poll "the control copy is the plugin the shell runs" "$control_dir" control_dir_of
expect_poll "the control copy's agent is lent" true polkit_lent polkitAgent
got="$(flowless_summon)" || got="unreadable"
if [[ $got == ok ]]; then ok "control: a prompt that opens with no flow is summoned"; else fail "control: the flowless summon reading got [$got] over a prompt that opens with no flow"; fi
expect_poll "control: the prompt that opened with no flow maps a surface" 1 layer_count vgs:overlay
expect "the control copy's prompt hides" ok ipc shell hide overlay vgs.polkit
rm -r -- "$control_dir"
rescan "rescan after removing the control copy answers ok"
expect_poll "the shipped plugin runs again" "$repo/shell/plugins/vgs.polkit" control_dir_of
expect_poll "no prompt surface is left" 0 layer_count vgs:overlay

# Another agent in the way.
polkit_fixtures="$repo/scripts/smoke/fixtures/polkit"
polkit_dir="$sandbox/polkit"
polkit_log="$polkit_dir/authority.log"
polkit_bus="unix:path=$rt_dir/system-bus"
polkit_program="$polkit_dir/polkit-acme-agent"
polkit_second="$polkit_dir/polkit-beta-agent"
polkit_record="$home/.local/state/vgshell/polkit/stopped.json"
mkdir -p -- "$polkit_dir"
cp -- "$(readlink -f -- "$(command -v python3)")" "$polkit_program" || fail "the stand-in agent's program could not be copied"
cp -- "$polkit_program" "$polkit_second" || fail "the second stand-in agent's program could not be copied"
polkit_python_home="$(python3 -c 'import sys; print(sys.base_prefix)')" || fail "python3's prefix is unreadable"
# pacman as the queries of `vgshell pkg owner` and `vgshell pkg removable` call
# it: the owner and version of each stand-in's program, and the removal dry
# run, which fails while the row's `required` file exists and for
# beta-polkit always.
cat >"$shim/pacman" <<SH
#!/bin/sh
case "\$1 \$2 \$3" in
  "-Qoq $polkit_program ") echo acme-polkit ;;
  "-Q -- acme-polkit") echo "acme-polkit 1.0-1" ;;
  "-Qoq $polkit_second ") echo beta-polkit ;;
  "-Q -- beta-polkit") echo "beta-polkit 1.0-1" ;;
  "-Rs --print --")
    if [ "\$4" = acme-polkit ] && [ ! -e "$polkit_dir/required" ]; then echo acme-polkit-1.0-1; exit 0; fi
    echo ":: removing \$4 breaks dependency '\$4' required by acme-desktop" >&2; exit 1 ;;
  *) echo "error: No package owns \$2" >&2; exit 1 ;;
esac
SH
chmod 755 "$shim/pacman"
polkit_said() { tail -n 1 -- "$polkit_log" 2>/dev/null || echo absent; }
polkit_other_start() {
  spawn "$polkit_dir/agent.out" "${shell_env[@]}" PYTHONHOME="$polkit_python_home" "$polkit_program" "$polkit_fixtures/agent.py" "$polkit_bus"
  polkit_other_pid="$spawn_pid"
  expect_poll "$1: the other agent holds the session first" "registered /org/vgshell/Smoke/OtherAgent" polkit_said
}
polkit_other_state() { if kill -0 "$polkit_other_pid" 2>/dev/null; then echo running; else echo gone; fi; }
# polkit_behind LABEL [STATUS]: vgs.polkit built behind the other agent,
# which polkitd refuses, and the row naming that agent, or reading STATUS.
polkit_behind() {
  polkit_other_start "$1"
  expect "$1: enabling the polkit plugin is allowed" ok ipc shell setPluginEnabled vgs.polkit true
  expect_poll "$1: the stand-in polkitd refused VGS's agent" "refused /org/quickshell/PolkitAgent" polkit_said
  expect "$1: VGS's agent is not registered" false polkit_lent polkitRegistered
  expect_poll "$1: the row names the other agent" "${2:-$other}" polkit_status
}
# polkit_step LABEL NAME BUTTON: the row offers BUTTON alone, its press
# opens the plugin's TUI NAME, and the row ends the other agent while the
# run is held, as the step does.
polkit_step() {
  expect_poll "$1: the row offers $3" "[[\"agent\", \"$3\", true]]" offered_actions vgs.polkit
  hold_runs
  forget_record
  expect "$1: $3 answers ok" ok settings_act vgs.polkit agent
  expect_poll "$1: $3 hands the terminal the plugin's $2 TUI" "$(words "vgs.polkit/$2" "tui/$2.sh")" recorded_tail
  kill "$polkit_other_pid" || fail "$1: ending the stand-in agent pid $polkit_other_pid failed"
  expect_poll "$1: the other agent let go of the session" "released /org/vgshell/Smoke/OtherAgent" polkit_said
  expect "$1: VGS's agent waits for the step's end" false polkit_lent polkitRegistered
  release_runs
  expect_run_end "$1: the $2 run ends" "vgs.polkit/$2"
}
polkit_off() {
  expect "$1: disabling the polkit plugin is allowed" ok ipc shell setPluginEnabled vgs.polkit false
  expect_poll "$1: disable destroyed the agent" false polkit_lent polkitAgent
}
polkit_registered() {
  expect_poll "$1: VGS's agent registers" true polkit_lent polkitRegistered
  expect_poll "$1: the row reads ready" "$ready" polkit_status
  expect "$1: the shell the row started with still runs" yes in_harness_tree "$shell_qs_pid"
}
polkit_record_plant() { python3 -c 'import json,sys; json.dump([sys.argv[1]], open(sys.argv[2], "w"))' "$polkit_program" "$polkit_record"; }

polkit_off "before the other agent"
spawn "$polkit_dir/authority.out" "${shell_env[@]}" python3 "$polkit_fixtures/authority.py" "$polkit_bus" "$polkit_log"
polkit_authority_pid="$spawn_pid"
expect_poll "the stand-in polkitd is on the sandbox's system bus" ready polkit_said
terminal_stand_in
terminal_ready "the polkit steps"
settings_page_open vgs.polkit

polkit_behind "a package nothing requires"
expect_poll "one other agent draws one Badge" '["Another app is showing password prompts: acme-polkit."]' polkit_badges
polkit_step "a package nothing requires" uninstall Uninstall
polkit_registered "after Uninstall"

polkit_off "before the required package"
expect_poll "VGS's destroyed agent let go of the session" "released /org/quickshell/PolkitAgent" polkit_said
: >"$polkit_dir/required"
# The second agent holds no session: it only runs, named as an agent is.
spawn "$polkit_dir/second.out" "${shell_env[@]}" PYTHONHOME="$polkit_python_home" "$polkit_second" -c 'import signal; signal.pause()'
polkit_second_pid="$spawn_pid"
expect_poll "the second agent runs under its program's name" polkit-beta-age cat "/proc/$polkit_second_pid/comm"
polkit_behind "a package another requires" "$other_two"
expect_poll "two other agents draw one Badge each" '["Another app is showing password prompts: beta-polkit.", "Another app is showing password prompts: acme-polkit."]' polkit_badges
polkit_step "a package another requires" stop Stop
kill "$polkit_second_pid" || fail "ending the second stand-in agent pid $polkit_second_pid failed"
polkit_registered "after Stop"

# A program the user stopped before: the service's check ends it and asks
# polkitd again, with no press.
polkit_off "before the recorded program"
expect_poll "VGS's destroyed agent let go of the session again" "released /org/quickshell/PolkitAgent" polkit_said
mkdir -p -- "${polkit_record%/*}"
polkit_record_plant || fail "the stop record could not be planted"
polkit_other_start "a recorded program"
expect "a recorded program: enabling the polkit plugin is allowed" ok ipc shell setPluginEnabled vgs.polkit true
expect_poll "a recorded program: the service's check ended it" gone polkit_other_state
polkit_registered "after the check ended the recorded program"

# Control: a copy whose service never asks polkitd again. The same steps
# leave its agent unregistered: after the step's end, and after its check
# ended the recorded program.
polkit_off "before the control"
expect_poll "VGS's destroyed agent let go of the session before the control" "released /org/quickshell/PolkitAgent" polkit_said
rm -f -- "${polkit_record:?}" "${polkit_dir:?}/required"
mkdir -p -- "$control_dir"
cp -R -- "$repo/shell/plugins/vgs.polkit/." "$control_dir/"
python3 - "$control_dir/Service.qml" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
for needle, replacement in (
    ("        seenEnds = ends;\n        register();\n", "        seenEnds = ends;\n"),
    ("        if (answer.ok && answer.stopped > 0) register();\n", ""),
):
    assert text.count(needle) == 1, "polkit control: the register call must match once: " + needle
    text = text.replace(needle, replacement)
open(path, "w").write(text)
PY
rescan "rescan over the second control copy answers ok"
expect_poll "the second control copy is the plugin the shell runs" "$control_dir" control_dir_of
polkit_behind "control"
polkit_step "control" uninstall Uninstall
# A real wait: the control's agent must stay unregistered past the turn in
# which the shipped service asks polkitd again.
sleep 1
expect "control: a service that never asks again stays unregistered after the step" false polkit_lent polkitRegistered
polkit_off "control, before the recorded program"
polkit_record_plant || fail "the stop record could not be planted for the control"
polkit_other_start "control, a recorded program"
expect "control, a recorded program: enabling the polkit plugin is allowed" ok ipc shell setPluginEnabled vgs.polkit true
expect_poll "control, a recorded program: the check ended it" gone polkit_other_state
expect_poll "control: the check that ended it found no other agent" "$unregistered" polkit_status
expect "control: a service that never asks again stays unregistered after its check" false polkit_lent polkitRegistered
rm -r -- "${control_dir:?}"
rescan "rescan after removing the second control copy answers ok"
expect_poll "the shipped plugin runs after the second control" "$repo/shell/plugins/vgs.polkit" control_dir_of

settings_page_close vgs.polkit
kill "$polkit_authority_pid" || fail "stopping the stand-in polkitd pid $polkit_authority_pid failed"
rm -f -- "${shim:?}/pacman" "${polkit_record:?}"

expect "no authentication request went live in this shell" 0 polkit_lent polkitFlows
expect "no authentication helper runs under the shell at the row's end" none auth_helpers "$shell_qs_pid"
kill "$auth_watch_pid" 2>/dev/null || fail "stopping the helper watcher pid $auth_watch_pid failed"
expect "over the whole row, the watcher saw no authentication helper" "" cat -- "$sandbox/polkit-auth-helpers.log"
expect "disabling the polkit plugin is allowed" ok ipc shell setPluginEnabled vgs.polkit false
expect_poll "disable destroyed the agent" false polkit_lent polkitAgent
expect "disable released polkit" null polkit_lent holders.polkit
polkit_record() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["status"].get("vgs.polkit")))'; }
expect "disable dropped the plugin's status record" null polkit_record
if [[ $probe_enabled == True ]]; then
  expect "re-enabling the capability fixture is allowed" ok ipc shell setPluginEnabled acme.probe true
  expect_poll "the fixture holds polkit again" '["acme.probe"]' polkit_lent holders.polkit
fi
