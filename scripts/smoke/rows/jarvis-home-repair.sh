# No latency budget. Poll once per nested IPC round trip.
# A missing Kendex-owned Home persona reaches the production home=package
# refusal. The Settings Repair press runs only the allow-listed TUI fixture.
# Its completion must cause the real daemon to open the current Home again.
# The control disables that completion callback in a disposable Service copy:
# the same repair restores the file but leaves the Home step To do.
# inputs: scripts/smoke/rows/jarvis.sh scripts/smoke/fixtures/tui/vgs.jarvis/tui/repair-home.sh shell/plugins/vgs.jarvis/* packaging/jarvis-home/* shell/plugins/vgs.settings/manifest.json shell/plugins/vgs.settings/Window.qml shell/plugins/vgs.settings/ListPage.qml shell/plugins/vgs.settings/PluginPage.qml shell/plugins/vgs.settings/PageHeader.qml shell/plugins/vgs.settings/EditSet.qml shell/plugins/vgs.settings/Steps.js shell/plugins/vgs.settings/SettingField.qml shell/plugins/vgs.settings/ListField.qml shell/plugins/vgs.settings/KeyField.qml shell/plugins/vgs.settings/StatusRow.qml shell/plugins/vgs.settings/StatusLine.qml shell/plugins/vgs.settings/RequirementRow.qml shell/Core/TuiRunner.qml bin/vgshell-tui bin/lib/tui.sh
set -euo pipefail
expected_errors+=("${dictation_absent_errors[@]}")
expected_errors+=('WARN qml: jarvis-session: (change|status|build)=blocked block=package' 'WARN qml: jarvis: stderr=jarvis: home=package')
# Accepted homes are remembered even after their folders go away. Preserve
# the incoming profile as well as its history, while no daemon can write it.
repair_homes="$home/.local/state/vgshell/jarvis/homes.json"
cp -- "$home/.config/vgshell/shell.json" "$sandbox/repair-home-config-original"
repair_homes_present=false
if [[ -e $repair_homes ]]; then
  cp -- "$repair_homes" "$sandbox/repair-home-homes-original"
  repair_homes_present=true
fi
repair_home_restore_profile() {
  user_config_restore "$sandbox/repair-home-config-original"
  if [[ $repair_homes_present == true ]]; then
    cp -- "$sandbox/repair-home-homes-original" "$repair_homes"
  else
    rm -f -- "$repair_homes"
  fi
}
repair_home_profile() {
  if ! cmp -s -- "$sandbox/repair-home-config-original" "$home/.config/vgshell/shell.json"; then
    echo changed-config
  elif [[ $repair_homes_present == true ]]; then
    if cmp -s -- "$sandbox/repair-home-homes-original" "$repair_homes"; then echo restored; else echo changed-homes; fi
  elif [[ -e $repair_homes ]]; then
    echo changed-homes
  else
    echo restored
  fi
}
repair_service="$repo/shell/plugins/vgs.jarvis/Service.qml"
repair_reader="$repo/shell/plugins/vgs.jarvis/HomeRepair.qml"
repair_tui="$repo/shell/plugins/vgs.jarvis/tui/repair-home.sh"
cp -- "$repair_service" "$sandbox/repair-home-service-original"
cp -- "$repair_reader" "$sandbox/repair-home-reader-original"
cp -- "$repair_tui" "$sandbox/repair-home-tui-original"
cp -- "$source_repo/scripts/smoke/fixtures/tui/vgs.jarvis/tui/repair-home.sh" "$repair_tui"
jarvis_setup_requirements
terminal_stand_in
terminal_ready "Jarvis Home repair"

# Keep the daemon's isolated HOME aligned with the shell's scratch HOME.
# Its usual J09 launcher still owns every child and all executable doubles.
python3 - "$sandbox/repair-home-lease.sh" "$home" "$repair_service" "$sandbox/jarvis-world/lease.sh" <<'PYREPAIR'
from pathlib import Path
import json,shlex,sys
lease=Path(sys.argv[1])
lease.write_text('\n'.join(['#!/bin/bash','set -euo pipefail','exec 3<&0',
    'exec bash "$1" "$2" -- bash -c \'export HOME="$1"; shift; exec node "$@" <&3 3<&-\' jarvis-home '+shlex.quote(sys.argv[2])+' "$3" --tree "$4"','']))
lease.chmod(0o700)
p=Path(sys.argv[3]); source=p.read_text(); old=json.dumps(sys.argv[4])
assert source.count(old)==1
changed=source.replace(old,json.dumps(str(lease)))
assert changed!=source
p.write_text(changed)
PYREPAIR

repair_home_value() {
  status_row vgs.jarvis setupHome | py_reply 'import json,sys
v=json.load(sys.stdin)["value"]
print(json.dumps([v["tone"],v.get("action")]))'
}
repair_home_seed() {
  node - "$repo" "$home/Repair Home" "$home/.repair-home-persona" <<'JSREPAIR'
const fs = require("node:fs"), path = require("node:path");
const [tree, folder, saved] = process.argv.slice(2);
require(path.join(tree, "shell/plugins/vgs.jarvis/backend/Core.js")).use(tree);
const Home = require(path.join(tree, "shell/plugins/vgs.jarvis/backend/Home.js"));
Home.layout(folder);
fs.copyFileSync(path.join(tree, "packaging/jarvis-home/.kendex-lock.json"), path.join(folder, ".kendex-lock.json"));
const persona = path.join(folder, ".agents/skills/jarvis/persona.md");
fs.copyFileSync(persona, saved);
fs.rmSync(persona);
JSREPAIR
}
repair_home_press() {
  expect_poll "the local voice reader is idle before Repair" idle jarvis_setup_reader_idle LocalRuntime
  expect_poll "the cloned voice reader is idle before Repair" idle jarvis_setup_reader_idle CloneRuntime
  expect_poll "the account reader is idle before Repair" idle jarvis_accounts_reader_idle
  expect_poll "the key reader is idle before Repair" idle repair_home_keys_idle
  forget_record
  settings_press --type RowAction Repair || { fail "the Repair press failed"; return 1; }
  expect_run_end "the fixture Home repair ends" vgs.jarvis/repair-home
  expect_poll "Repair runs its allow-listed fixture" repaired cat "$home/.repair-home-pressed"
}
repair_home_keys_idle() {
  ipc smoke itemValues service vgs.jarvis Keys pending,code | py_reply 'import json,sys
rows=json.load(sys.stdin)
print("idle" if len(rows)==1 and rows[0]["pending"] is False and rows[0]["code"] != -1 else "pending")'
}
repair_home_prepare() {
  repair_home_seed || { fail "the scratch Home is not prepared"; return 1; }
  jarvis_rescan
  jarvis_enable
  settings_page_open vgs.jarvis
  expect "select the damaged scratch Home" ok ipc smoke invokeInstance window vgs.settings applySetting '{"id":"vgs.jarvis","key":"home","value":"~/Repair Home"}'
  settings_setup
  expect_poll "a damaged Home offers Repair" '["warning", "repair"]' repair_home_value
}
repair_home_prepare
repair_home_press
expect_poll "Repair completion reopens the selected Home without Talk" '["ok", null]' repair_home_value
settings_page_close vgs.jarvis
jarvis_disable

# The control changes only the completion effect, leaving the reader and
# the Repair press present, so the observed missing outcome names the defect.
python3 - "$repair_reader" <<'PYREPAIR'
from pathlib import Path
import sys
p=Path(sys.argv[1]); source=p.read_text()
old='if (endedAt !== null) { refresh(); recheck(); }'
assert source.count(old)==1
changed=source.replace(old,'if (endedAt !== null) { refresh(); }')
assert changed!=source
p.write_text(changed)
PYREPAIR
rm -f -- "${home:?}/.repair-home-pressed"
repair_home_prepare
repair_home_press
repair_home_control() {
  (failures=0 behaviour_failures=0
   expect_poll "completion must recheck the repaired Home" '["ok", null]' repair_home_value >"$sandbox/repair-home-control-assertions.log"
   echo "$failures")
}
expect "removing the completion recheck rejects the repaired outcome" 1 repair_home_control
settings_page_close vgs.jarvis
jarvis_disable
cp -- "$repair_homes" "$sandbox/repair-home-homes-leaked"
cp -- "$sandbox/repair-home-service-original" "$repair_service"
cp -- "$sandbox/repair-home-reader-original" "$repair_reader"
cp -- "$sandbox/repair-home-tui-original" "$repair_tui"
rm -rf -- "${home:?}/Repair Home"
rm -f -- "${home:?}/.repair-home-persona" "${home:?}/.repair-home-pressed"
repair_home_restore_profile
expect "Home repair restores the incoming profile and used homes" restored repair_home_profile
# Plant the original leak after the daemon ends: removing a folder alone
# must fail the same restoration assertion, without relying on a later row.
cp -- "$sandbox/repair-home-homes-leaked" "$repair_homes"
repair_home_profile_control() {
  (failures=0 behaviour_failures=0
   expect "Home repair restores the incoming profile and used homes" restored repair_home_profile >"$sandbox/repair-home-profile-control.log"
   echo "$failures")
}
expect "a leaked used home breaks the profile restoration assertion" 1 repair_home_profile_control
repair_home_restore_profile
expect "the profile is restored after its leak control" restored repair_home_profile
expect "the restored user profile is read again" ok ipc shell reloadConfig
rescan "the original Home repair service is restored"
jarvis_restore_requirements
