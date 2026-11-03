# No latency budget. Poll once per nested IPC round trip.
# Main Jarvis host chosen on the Settings page reaches the Jarvis package's
# main-host setting through the real daemon, against the package stand-in
# scripts/fixtures/jarvis/satellite-package.py (the setter is KEN-4874's),
# and the console's Now line reads the package's status --main answer: the
# main reachable, the main that did not answer, this computer, and a package
# older than the satellite contract. The control drops the choice's hand-off
# in a disposable Service copy: the same choice never reaches the package.
# inputs: scripts/smoke/rows/jarvis.sh scripts/fixtures/jarvis/satellite-package.py shell/plugins/vgs.jarvis/* packaging/jarvis-home/* shell/plugins/vgs.settings/manifest.json shell/plugins/vgs.settings/Window.qml shell/plugins/vgs.settings/ListPage.qml shell/plugins/vgs.settings/PluginPage.qml shell/plugins/vgs.settings/PageHeader.qml shell/plugins/vgs.settings/EditSet.qml shell/plugins/vgs.settings/Steps.js shell/Ui/controls/SettingField.qml shell/Ui/feedback/LinkText.qml
set -euo pipefail
# The real daemon logs the set jarvis.sh declares, and the older package's
# refused setter by its key.
expected_errors+=("${jarvis_provoked_errors[@]}")
expected_errors+=('WARN qml: jarvis: stderr=jarvis: satellite=main-host cause=package-old')
satellite_homes="$home/.local/state/vgshell/jarvis/homes.json"
cp -- "$home/.config/vgshell/shell.json" "$sandbox/satellite-config-original"
satellite_homes_present=false
if [[ -e $satellite_homes ]]; then
  cp -- "$satellite_homes" "$sandbox/satellite-homes-original"
  satellite_homes_present=true
fi
satellite_service="$repo/shell/plugins/vgs.jarvis/Service.qml"
cp -- "$satellite_service" "$sandbox/satellite-service-original"
satellite_home="$home/Satellite Home"
satellite_scripts="$satellite_home/.agents/skills/jarvis/scripts"
jarvis_setup_requirements

# The daemon's isolated HOME is the shell's scratch HOME, so the Home folder
# setting names the folder the stand-in records in (rows/jarvis-home-repair.sh).
python3 - "$sandbox/satellite-lease.sh" "$home" "$satellite_service" "$sandbox/jarvis-world/lease.sh" <<'PYLEASE'
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
PYLEASE

# A Kendex-owned Home, so VGS writes no package file over the stand-in.
node - "$repo" "$satellite_home" <<'JSSATELLITE'
const fs = require("node:fs"), path = require("node:path");
const [tree, folder] = process.argv.slice(2);
require(path.join(tree, "shell/plugins/vgs.jarvis/backend/Core.js")).use(tree);
require(path.join(tree, "shell/plugins/vgs.jarvis/backend/Home.js")).layout(folder);
fs.copyFileSync(path.join(tree, "packaging/jarvis-home/.kendex-lock.json"), path.join(folder, ".kendex-lock.json"));
JSSATELLITE
mkdir -p -- "$satellite_scripts"
cp -- "$repo/scripts/fixtures/jarvis/satellite-package.py" "$satellite_scripts/jarvis-session"
chmod 755 "$satellite_scripts/jarvis-session"

satellite_state() { printf '%s\n' "$1" >"$satellite_scripts/satellite.json"; }
# The last value the package's main-host setting took, or none.
satellite_set() {
  python3 - "$satellite_scripts/calls.log" <<'PYSET'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
rows=[json.loads(line)["argv"] for line in p.read_text().splitlines()] if p.exists() else []
sets=[a[1].split("=",1)[1] for a in rows if a[0]=="main-host" and a[1].startswith("--set=")]
print(sets[-1] if sets else "none")
PYSET
}
# The Now line as drawn, a file link's path left out, or hidden.
satellite_line() {
  ipc smoke itemValues window vgs.jarvis LinkText objectName,text,visible | py_reply '
import json,re,sys
rows=[r for r in json.load(sys.stdin) if r.get("objectName")=="mainReachLine"]
print(re.sub(r"\(file:[^)]*\)","(file)",rows[0]["text"]) if len(rows)==1 and rows[0]["visible"] else "hidden" if rows else "absent")'
}
satellite_choose() { # VALUE
  expect "choose Main Jarvis host $1" ok ipc smoke invokeInstance window vgs.settings applySetting "{\"id\":\"vgs.jarvis\",\"key\":\"mainHost\",\"value\":\"$1\"}"
}
satellite_prepare() {
  jarvis_rescan
  jarvis_enable
  settings_page_open vgs.jarvis
  expect "select the stand-in's Home" ok ipc smoke invokeInstance window vgs.settings applySetting '{"id":"vgs.jarvis","key":"home","value":"~/Satellite Home"}'
}

satellite_prepare
expect_poll "a Home choice hands the setting to that Home" "" satellite_set
expect "the console opens" ok ipc vgs.jarvis invoke console ''
expect_poll "an empty Main Jarvis host is this computer" "This computer runs your main Jarvis." satellite_line
satellite_state '{"reachable": true}'
satellite_choose cachy
expect_poll "the choice reaches the package as the main and this Home's path" "cachy:$satellite_home" satellite_set
expect_poll "the Now line reads the main as reachable" "Your main Jarvis on cachy is reachable." satellite_line
satellite_state "{\"main\": \"cachy:$satellite_home\", \"reachable\": false}"
satellite_choose jarvis
expect_poll "the Now line names a main that did not answer" "Your main Jarvis on jarvis did not answer. Forwarded requests wait here." satellite_line
satellite_choose ""
expect_poll "choosing This computer clears the package's setting" "" satellite_set
expect_poll "the Now line reads this computer as the main" "This computer runs your main Jarvis." satellite_line
satellite_state '{"package": "old"}'
satellite_choose cachy
expect_poll "an older package cannot forward" "The Jarvis package in your [home folder](file) cannot forward to cachy." satellite_line
settings_page_close vgs.jarvis
jarvis_disable

# The control drops only the hand-off, leaving the choice handler, the
# daemon and the stand-in present, so the missing setting names the defect.
python3 - "$satellite_service" <<'PYCONTROL'
from pathlib import Path
import sys
p=Path(sys.argv[1]); source=p.read_text()
old='send({ type: "intent", intent: "main-host",'
assert source.count(old)==1
changed=source.replace(old,'void ({ type: "intent", intent: "main-host",')
assert changed!=source
p.write_text(changed)
PYCONTROL
satellite_state '{}'
rm -f -- "$satellite_scripts/calls.log"
user_config_restore "$sandbox/satellite-config-original"
satellite_prepare
satellite_choose cachy
satellite_control() {
  (failures=0 behaviour_failures=0
   expect_poll "the choice must reach the package" "cachy:$satellite_home" satellite_set >"$sandbox/satellite-control.log"
   echo "$failures")
}
expect "dropping the hand-off leaves the package's setting unset" 1 satellite_control
settings_page_close vgs.jarvis
jarvis_disable
cp -- "$sandbox/satellite-service-original" "$satellite_service"
rm -rf -- "${home:?}/Satellite Home"
user_config_restore "$sandbox/satellite-config-original"
if [[ $satellite_homes_present == true ]]; then
  cp -- "$sandbox/satellite-homes-original" "$satellite_homes"
else
  rm -f -- "$satellite_homes"
fi
expect "the restored user profile is read again" ok ipc shell reloadConfig
rescan "the original Jarvis service is restored"
jarvis_restore_requirements
