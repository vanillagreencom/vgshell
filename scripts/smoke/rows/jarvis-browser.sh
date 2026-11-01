# No latency budget. Poll once per nested IPC round trip.
# Only J09's process double and the allow-listed TUI fixture run here.
# inputs: shell/plugins/vgs.jarvis/* shell/plugins/vgs.settings/manifest.json shell/plugins/vgs.settings/Window.qml shell/plugins/vgs.settings/ListPage.qml shell/plugins/vgs.settings/PluginPage.qml shell/plugins/vgs.settings/PageHeader.qml shell/plugins/vgs.settings/EditSet.qml shell/plugins/vgs.settings/Steps.js shell/Ui/controls/SettingField.qml shell/plugins/vgs.settings/ListField.qml shell/plugins/vgs.settings/KeyField.qml shell/plugins/vgs.settings/StatusRow.qml shell/plugins/vgs.settings/StatusLine.qml shell/plugins/vgs.settings/RequirementRow.qml shell/Commons/Reply.js scripts/smoke/fixtures/tui/vgs.jarvis/* shell/Core/TuiRunner.qml scripts/fixtures/jarvis/browser-status.js scripts/smoke/rows/jarvis.sh bin/vgshell-tui bin/vgshell-scan shell/Core/Registry.qml shell/Core/Notices.qml shell/Core/PluginLogic.js shell/Core/ConfigLogic.js
set -euo pipefail
expected_errors+=("${dictation_absent_errors[@]}")
browser_reader="$repo/shell/plugins/vgs.jarvis/LocalRuntime.qml"
browser_tui="$repo/shell/plugins/vgs.jarvis/tui/setup-browser.sh"
cp -- "$browser_reader" "$sandbox/browser-reader-original"
cp -- "$browser_tui" "$sandbox/browser-tui-original"
cp -- "$source_repo/scripts/smoke/fixtures/tui/vgs.jarvis/tui/setup-browser.sh" "$browser_tui"
jarvis_setup_requirements
terminal_stand_in
terminal_ready "Jarvis browser setup"
# A stand-in driver on the sandbox PATH, so every read until the row's end
# finds agent-browser whatever the host holds. It prints no version, so
# the scan reads its presence alone; with no readiness marker the daemon
# offers no browser tool.
printf '#!/bin/sh\nexit 0\n' >"$shim/agent-browser"; chmod 755 "$shim/agent-browser"
jarvis_rescan
jarvis_enable
settings_page_open vgs.jarvis

# The browser is an optional Setup step: its reading keeps its own tone,
# and the page draws the Optional chip (Steps.stepReading).
# A failed or unreadable check also says why in a hint that names Set up
# browser: [tone, text and action, whether that hint shows].
browser_value() {
  status_row vgs.jarvis browser | py_reply '
import json,sys
r=json.load(sys.stdin)
with open(sys.argv[2]) as stream:
    label=json.load(stream)["status"]["browser"]["action"]["label"]
expected={"absent":({"tone":"warning","text":"Browser needs setup","action":True},False),
          "ready":({"tone":"ok","text":"Private browser ready","action":False},False),
          "failed":({"tone":"warning","text":"Setup check failed","action":True},True),
          "invalid":({"tone":"warning","text":"Setup check returned invalid status","action":True},True),
          "withheld":({"tone":"warning","text":"Needs agent-browser","action":False},False)}[sys.argv[1]]
v=r["value"]
fields,reasoned=expected
ok=isinstance(v,dict) and set(v)<=set(fields)|{"hint"} and {k:v.get(k) for k in fields}==fields
ok=ok and ("hint" in v)==reasoned and (not reasoned or label in v["hint"])
print("matched" if ok and r["action"]["offered"]==fields["action"] else "pending")
' "$1" "$repo/shell/plugins/vgs.jarvis/manifest.json"
}
# The browser driver's own row says whether the scan finds the driver,
# misses it or reads it below the floor the manifest gives it, and offers
# no step: the Requirements section installs or updates it.
driver_value() {
  status_row vgs.jarvis browserDriver | py_reply '
import json,sys
r=json.load(sys.stdin)
value={"found":{"tone":"ok","text":"Installed"},
       "missing":{"tone":"warning","text":"Not installed"},
       "outdated":{"tone":"warning","text":"Needs an update"}}[sys.argv[1]]
print("matched" if r["value"]==value and r["action"] is None else "pending")
' "$1"
}
# The driver's state in the plugin's requirements, which the Setup tab's
# Requirements section draws.
driver_requirement() { ipc shell listPlugins | py_reply 'import json,sys; p=[p for p in json.load(sys.stdin)["plugins"] if p["id"]=="vgs.jarvis"][0]; print([r["state"] for r in p["requirements"] if r["name"]=="agent-browser"][0])'; }
# A stand-in driver that answers `--version` with VERSION.
driver_version() { # VERSION
  printf '#!/bin/sh\necho "agent-browser %s"\n' "$1" >"$shim/agent-browser.next" && chmod 755 "$shim/agent-browser.next" && mv -T -- "$shim/agent-browser.next" "$shim/agent-browser"
}
browser_open() { # manager action or listed launcher entry
  local revision snapshot
  revision="$(jarvis_revision)" || return 1
  snapshot="$rt_dir/vgshell-sources-$shell_qs_pid/$revision"
  forget_record
  if [[ $1 == status ]]; then
    expect "Settings starts its declared browser setup action" ok settings_act vgs.jarvis browser
  else
    expect "the launcher starts its listed browser setup" ok ipc shell openTui vgs.jarvis/setup-browser
  fi
  expect_poll "setup receives the private plugin snapshot and declared argv" \
    "$(words --app-id=org.vgs.tui "--title=VGS · Set up Jarvis browser" -- "$tui_self" present --presentation full \
      --plugin vgs.jarvis --dir "$snapshot" --record vgs.jarvis/setup-browser --run RUN --record-dir "$rt_dir/vgshell/tui" \
      --app-id org.vgs.tui --window-title "VGS · Set up Jarvis browser" -- tui/setup-browser.sh)" recorded
  expect_run_end "the fixture browser setup terminal ends" vgs.jarvis/setup-browser
}
expect_poll "browser setup is offered before verification" matched browser_value absent
expect_poll "a found browser driver reads Installed" matched driver_value found
ipc shell listTuis | py_reply '
import json,sys
rows=json.load(sys.stdin)
assert any(row["key"]=="vgs.jarvis/setup-browser" and row["group"]=="Jarvis" for row in rows)
'
printf 'ready\n' >"$sandbox/jarvis-world/browser-mode"
browser_open status
expect_poll "the service rereads readiness after the Settings action ends" matched browser_value ready
printf 'failed\n' >"$sandbox/jarvis-world/browser-mode"
browser_open launcher
expect_poll "exit 77 replaces a previous ready status" matched browser_value failed
printf 'invalid\n' >"$sandbox/jarvis-world/browser-mode"
browser_open launcher
expect_poll "invalid output cannot retain ready" matched browser_value invalid
# A scan that changes no plugin file hands Jarvis no new shell, so only the
# reader's scan refresh reads the probe again.
printf 'ready\n' >"$sandbox/jarvis-world/browser-mode"
rescan "a rescan that changes no plugin file starts"
expect_poll "the service rereads readiness after a requirement scan" matched browser_value ready

# Preserve the handler text and drop its effect on a disposable copy.
python3 - "$browser_reader" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
assert not p.is_symlink()
s=p.read_text()
needle="onEndedAtChanged: if (endedAt !== null) refresh()"
assert s.count(needle)==1
changed=s.replace(needle,"onEndedAtChanged: if (false && endedAt !== null) refresh()")
assert changed != s
p.write_text(changed)
PY
printf 'ready\n' >"$sandbox/jarvis-world/browser-mode"
jarvis_rescan
expect_poll "the refresh control first reads ready" matched browser_value ready
expect_poll "the refresh control first reads ready: reader is idle" idle jarvis_setup_reader_idle BrowserRuntime
printf 'failed\n' >"$sandbox/jarvis-world/browser-mode"
browser_open launcher
browser_refresh_control() {
  (failures=0 behaviour_failures=0
   expect_poll "the completed TUI must replace ready" matched browser_value failed
   echo "$failures")
}
browser_control_count() {
  local output
  output="$("$@")" || return 1
  printf '%s\n' "${output##*$'\n'}"
}
expect "removing end refresh breaks its consumer read" 1 browser_control_count browser_refresh_control
cp -- "$sandbox/browser-reader-original" "$browser_reader"
printf 'absent\n' >"$sandbox/jarvis-world/browser-mode"
jarvis_rescan
expect_poll "the restored reader offers setup" matched browser_value absent

python3 - "$browser_reader" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
needle='        reading = Gate.setupValue(checked(), requires, shell.requirements.missing);'
assert s.count(needle)==1
changed=s.replace(needle, '        if (code !== 0) return;\n' + needle)
assert changed != s
p.write_text(changed)
PY
printf 'ready\n' >"$sandbox/jarvis-world/browser-mode"
jarvis_rescan
expect_poll "the failed-probe control first reads ready" matched browser_value ready
expect_poll "the failed-probe control first reads ready: reader is idle" idle jarvis_setup_reader_idle BrowserRuntime
printf 'failed\n' >"$sandbox/jarvis-world/browser-mode"
browser_open launcher
browser_failure_control() {
  (failures=0 behaviour_failures=0
   expect_poll "a failed check must clear ready" matched browser_value failed
   echo "$failures")
}
expect "retaining ready after probe failure breaks its consumer read" 1 browser_control_count browser_failure_control
cp -- "$sandbox/browser-reader-original" "$browser_reader"

python3 - "$browser_reader" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
needle="onRequirementsRevisionChanged: refresh()"
assert s.count(needle)==1
changed=s.replace(needle,"onRequirementsRevisionChanged: if (false) refresh()")
assert changed != s
p.write_text(changed)
PY
printf 'ready\n' >"$sandbox/jarvis-world/browser-mode"
jarvis_rescan
expect_poll "the scan refresh control first reads ready" matched browser_value ready
expect_poll "the scan refresh control first reads ready: reader is idle" idle jarvis_setup_reader_idle BrowserRuntime
printf 'failed\n' >"$sandbox/jarvis-world/browser-mode"
rescan "the control's rescan starts"
browser_scan_control() {
  (failures=0 behaviour_failures=0
   expect_poll "a requirement scan must replace ready" matched browser_value failed
   echo "$failures")
}
expect "removing the scan refresh breaks its consumer read" 1 browser_control_count browser_scan_control
cp -- "$sandbox/browser-reader-original" "$browser_reader"
cp -- "$sandbox/browser-tui-original" "$browser_tui"
printf 'absent\n' >"$sandbox/jarvis-world/browser-mode"
jarvis_rescan
expect_poll "the restored setup action is offered" matched browser_value absent
# A driver below the manifest's floor: its row reads Needs an update and
# takes no press, and the Requirements section reads the driver outdated.
# The same driver at its floor reads present, which is the control.
driver_version 0.37.9 || fail "the stand-in driver below its floor is not written"
rescan "a rescan with the driver below its floor starts"
expect_poll "a driver below its floor reads Needs an update" matched driver_value outdated
expect_poll "the Requirements section reads the driver outdated" outdated driver_requirement
expected_errors+=('settings: vgs.jarvis/browserDriver refused: action=browserDriver reason=undeclared')
expect "the driver's row takes no press" "refused: action=browserDriver reason=undeclared" settings_act vgs.jarvis browserDriver
expect "the refused press raises no notice" null notice_shown
floor="$(python3 -c 'import json,sys; print(next(r["floor"] for r in json.load(open(sys.argv[1]))["requirements"] if r.get("command")=="agent-browser"))' "$repo/shell/plugins/vgs.jarvis/manifest.json")" || fail "the manifest gives the driver no floor"
driver_version "$floor" || fail "the stand-in driver at its floor is not written"
rescan "a rescan with the driver at its floor starts"
expect_poll "a driver at its floor reads Installed" matched driver_value found
expect_poll "the Requirements section reads the driver at its floor present" present driver_requirement
# Without the stand-in the scan reads the host's PATH again. Only a host
# without agent-browser shows the missing driver, with no step, and browser
# setup withheld.
rm -f -- "${shim:?}/agent-browser"
rescan "a rescan after the stand-in driver goes starts"
if [[ $(shell_resolves agent-browser) == none ]]; then
  expect_poll "a missing browser driver reads Not installed" matched driver_value missing
  expect_poll "a missing browser driver withholds browser setup" matched browser_value withheld
else
  expect_poll "the host's browser driver reads as found" matched driver_value found
  expect_poll "the host's browser driver keeps browser setup offered" matched browser_value absent
fi
settings_page_close vgs.jarvis
jarvis_disable
jarvis_restore_requirements
