# No latency budget. Poll once per nested IPC round trip.
# Main Jarvis host chosen on the Settings page reaches the Jarvis package's
# main-host setting through the real daemon, against the package stand-in
# scripts/fixtures/jarvis/satellite-package.py (the setter is KEN-4874's),
# and the console's Now line reads the package's status --main answer: the
# main reachable, the main that did not answer, this computer, a package
# older than the satellite contract and one without the setter. The
# launcher's Switch Jarvis home hands the setting to the home it switches
# to, and a choice made while the daemon's answers are held reaches the
# package once it is ready. The control drops the choice's hand-off in a
# disposable Service copy: the same choice never reaches the package.
# inputs: scripts/smoke/rows/jarvis.sh scripts/fixtures/jarvis/satellite-package.py scripts/fixtures/jarvis/prepare.js shell/plugins/vgs.jarvis/* packaging/jarvis-home/* shell/plugins/vgs.settings/manifest.json shell/plugins/vgs.settings/Window.qml shell/plugins/vgs.settings/ListPage.qml shell/plugins/vgs.settings/PluginPage.qml shell/plugins/vgs.settings/PageHeader.qml shell/plugins/vgs.settings/EditSet.qml shell/plugins/vgs.settings/Steps.js shell/Ui/controls/SettingField.qml shell/Ui/feedback/LinkText.qml
set -euo pipefail
# The real daemon logs the set jarvis.sh declares, and the setter an older
# package or one before KEN-4874 refuses, by its key.
expected_errors+=("${jarvis_provoked_errors[@]}")
expected_errors+=('WARN qml: jarvis: stderr=jarvis: satellite=main-host cause=setter-absent')
satellite_homes="$home/.local/state/vgshell/jarvis/homes.json"
cp -- "$home/.config/vgshell/shell.json" "$sandbox/satellite-config-original"
satellite_homes_present=false
if [[ -e $satellite_homes ]]; then
  cp -- "$satellite_homes" "$sandbox/satellite-homes-original"
  satellite_homes_present=true
fi
satellite_service="$repo/shell/plugins/vgs.jarvis/Service.qml"
cp -- "$satellite_service" "$sandbox/satellite-service-original"
satellite_daemon="$repo/shell/plugins/vgs.jarvis/backend/jarvisd.js"
cp -- "$satellite_daemon" "$sandbox/satellite-daemon-original"
satellite_home="$home/Satellite Home"
satellite_two="$home/Satellite Two"
jarvis_setup_requirements

# The daemon's isolated HOME is the shell's scratch HOME, so the Home folder
# setting names the folder the stand-in records in (rows/jarvis-home-repair.sh).
# The launcher's home rows are activated as jarvis-controls.sh does.
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
needle='    function homeOffers(homes) {'
assert changed.count(needle)==1
changed=changed.replace(needle,'    function fixtureHomeActivate(item) { return shell.shortcut.activate("vgs.jarvis:home", item); }\n'+needle)
assert changed!=source
p.write_text(changed)
PYLEASE

# Kendex-owned Homes, so VGS writes no package file over the stand-in.
for satellite_folder in "$satellite_home" "$satellite_two"; do
  node - "$repo" "$satellite_folder" <<'JSSATELLITE'
const fs = require("node:fs"), path = require("node:path");
const [tree, folder] = process.argv.slice(2);
require(path.join(tree, "shell/plugins/vgs.jarvis/backend/Core.js")).use(tree);
require(path.join(tree, "shell/plugins/vgs.jarvis/backend/Home.js")).layout(folder);
fs.copyFileSync(path.join(tree, "packaging/jarvis-home/.kendex-lock.json"), path.join(folder, ".kendex-lock.json"));
JSSATELLITE
  mkdir -p -- "$satellite_folder/.agents/skills/jarvis/scripts"
  cp -- "$repo/scripts/fixtures/jarvis/satellite-package.py" "$satellite_folder/.agents/skills/jarvis/scripts/jarvis-session"
  chmod 755 "$satellite_folder/.agents/skills/jarvis/scripts/jarvis-session"
done

satellite_state() { printf '%s\n' "$1" >"$satellite_home/.agents/skills/jarvis/scripts/satellite.json"; }
satellite_forget() { rm -f -- "${satellite_home:?}/.agents/skills/jarvis/scripts/calls.log"; }
# The last value the package's main-host setting in HOME took, or none.
satellite_set() { # [HOME]
  python3 - "${1:-$satellite_home}/.agents/skills/jarvis/scripts/calls.log" <<'PYSET'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
rows=[json.loads(line)["argv"] for line in p.read_text().splitlines()] if p.exists() else []
sets=[a[1].split("=",1)[1] for a in rows if a[0]=="main-host" and a[1].startswith("--set=")]
print(sets[-1] if sets else "none")
PYSET
}
# The Now line as drawn, or hidden.
satellite_line() {
  ipc smoke itemValues window vgs.jarvis LinkText objectName,text,visible | py_reply '
import json,sys
rows=[r for r in json.load(sys.stdin) if r.get("objectName")=="mainReachLine"]
print(rows[0]["text"] if len(rows)==1 and rows[0]["visible"] else "hidden" if rows else "absent")'
}
satellite_choose() { # KEY VALUE
  expect "choose $1 $2" ok ipc smoke invokeInstance window vgs.settings applySetting "{\"id\":\"vgs.jarvis\",\"key\":\"$1\",\"value\":\"$2\"}"
}
satellite_prepare() {
  jarvis_rescan
  jarvis_enable
  settings_page_open vgs.jarvis
  satellite_choose home "~/Satellite Home"
}
# The launcher row id of the remembered home FOLDER (jarvis-controls.sh).
satellite_home_item() { # FOLDER
  python3 -c 'import hashlib,sys; print("h"+hashlib.sha256(sys.argv[1].encode()).hexdigest()[:12])' "$1"
}
# Whether the gated daemon has answered hello, its answer held (prepare.js
# --gate-daemon records each line it holds).
satellite_held() {
  python3 - "$satellite_seen" <<'PYSEEN'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
rows=[json.loads(line) for line in p.read_text().split("\n")[:-1]] if p.exists() else []
print("held" if any(r.get("type")=="status" and r.get("daemon")=="ready" for r in rows) else "pending")
PYSEEN
}

satellite_prepare
expect_poll "a Home choice hands the setting to that Home" "" satellite_set
expect "the console opens" ok ipc vgs.jarvis invoke console ''
expect_poll "an empty Main Jarvis host is this computer" "This computer runs your main Jarvis." satellite_line
satellite_state '{"reachable": true}'
satellite_choose mainHost cachy
expect_poll "the choice reaches the package as the main and this Home's path" "cachy:$satellite_home" satellite_set
expect_poll "the Now line reads the main as reachable" "Your main Jarvis on cachy is reachable." satellite_line
satellite_state "{\"main\": \"cachy:$satellite_home\", \"reachable\": false}"
satellite_choose mainHost jarvis
expect_poll "the Now line names a main that did not answer" "Your main Jarvis on jarvis did not answer. Forwarded requests wait here." satellite_line
satellite_choose mainHost ""
expect_poll "choosing This computer clears the package's setting" "" satellite_set
expect_poll "the Now line reads this computer as the main" "This computer runs your main Jarvis." satellite_line
satellite_state '{"package": "old"}'
satellite_choose mainHost cachy
expect_poll "an older package cannot forward" "Jarvis cannot forward to cachy: the Jarvis package in your home folder is missing or out of date. [Repair it in Setup](page:vgs.jarvis/Setup/sessionStart)." satellite_line
satellite_state '{"setter": "absent"}'
satellite_choose mainHost jarvis
expect_poll "a package without the setter has not taken it" "Jarvis cannot forward to jarvis: the Jarvis package in your home folder does not take [Main Jarvis host](page:vgs.jarvis/Settings/mainHost) yet." satellite_line

# The launcher's Switch Jarvis home hands the setting to the home it
# switches to, as a choice on the page does.
satellite_state '{}'
satellite_choose mainHost cachy
satellite_choose home "~/Satellite Two"
expect_poll "a Home choice hands the setting to the new Home" "cachy:$satellite_two" satellite_set "$satellite_two"
satellite_forget
expect_poll "the launcher switches back to the first Home" ok ipc smoke invokeInstance service vgs.jarvis fixtureHomeActivate "$(satellite_home_item "$satellite_home")"
expect_poll "the switch hands the setting to the Home it chose" "cachy:$satellite_home" satellite_set
settings_page_close vgs.jarvis
jarvis_disable

# A choice made while the daemon's answers are held waits for it to be
# ready, then reaches the package.
satellite_gate="$sandbox/satellite-gate"
satellite_seen="$sandbox/satellite-seen"
rm -f -- "$satellite_gate" "$satellite_seen"
"$node_bin" "$source_repo/scripts/fixtures/jarvis/prepare.js" --gate-daemon "$satellite_daemon" "$satellite_gate" "$satellite_seen"
jarvis_rescan
satellite_forget
expect "Jarvis enables with its answers held" ok ipc shell setPluginEnabled vgs.jarvis true
expect_poll "the held daemon has answered hello" held satellite_held
settings_page_open vgs.jarvis
satellite_choose mainHost jarvis
: >"$satellite_gate"
# Service.qml's helloDeadline (5000 ms) may end the held daemon and start
# another before the gate opens (rows/jarvis-keys.sh); the choice waits
# through that restart too.
satellite_ready() {
  ipc smoke jarvisProcess | py_reply 'import json,sys; d=json.load(sys.stdin); print("ready" if d["lifetime"]["kind"]=="ready" and d["retries"]<=1 else "pending")'
}
expect_poll "the real Jarvis daemon answers hello" ready satellite_ready
expect_poll "the choice made before the daemon was ready reaches the package" "jarvis:$satellite_home" satellite_set
settings_page_close vgs.jarvis
jarvis_disable
cp -- "$sandbox/satellite-daemon-original" "$satellite_daemon"

# The control drops only the hand-off, leaving the choice handler, the
# daemon and the stand-in present, so the missing setting names the defect.
python3 - "$satellite_service" <<'PYCONTROL'
from pathlib import Path
import sys
p=Path(sys.argv[1]); source=p.read_text()
old='send({ type: "intent", intent: "main-host" });'
assert source.count(old)==1
changed=source.replace(old,'void ({ type: "intent", intent: "main-host" });')
assert changed!=source
p.write_text(changed)
PYCONTROL
satellite_state '{}'
satellite_forget
user_config_restore "$sandbox/satellite-config-original"
satellite_prepare
satellite_choose mainHost cachy
satellite_control() {
  (failures=0 behaviour_failures=0
   expect_poll "the choice must reach the package" "cachy:$satellite_home" satellite_set >"$sandbox/satellite-control.log"
   echo "$failures")
}
expect "dropping the hand-off leaves the package's setting unset" 1 satellite_control
settings_page_close vgs.jarvis
jarvis_disable
cp -- "$sandbox/satellite-service-original" "$satellite_service"
rm -rf -- "${home:?}/Satellite Home" "${home:?}/Satellite Two"
user_config_restore "$sandbox/satellite-config-original"
if [[ $satellite_homes_present == true ]]; then
  cp -- "$sandbox/satellite-homes-original" "$satellite_homes"
else
  rm -f -- "$satellite_homes"
fi
expect "the restored user profile is read again" ok ipc shell reloadConfig
rescan "the original Jarvis service is restored"
jarvis_restore_requirements
