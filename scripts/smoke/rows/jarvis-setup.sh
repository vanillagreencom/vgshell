# No latency budget. Poll once per nested IPC round trip.
# Only J09's process double and the allow-listed TUI fixture run here.
# The Setup section reads the real daemon's engine answer: Not ready on a
# fresh profile with the AI model and local voice to do, each with its
# step beside it, then Ready once an AI model the engine takes is chosen
# and local voice's marker is there and its setup run ends. Browser and
# input are optional rows. Its control is a Service copy whose readers
# send no snapshot when their checks end.
# inputs: shell/plugins/vgs.jarvis/* shell/plugins/vgs.settings/* shell/Commons/Reply.js scripts/smoke/fixtures/tui/vgs.jarvis/* shell/Core/TuiRunner.qml scripts/fixtures/jarvis-setup/status.py scripts/smoke/rows/jarvis.sh bin/vgshell-tui
set -euo pipefail
local_reader="$repo/shell/plugins/vgs.jarvis/LocalRuntime.qml"
local_tui="$repo/shell/plugins/vgs.jarvis/tui/setup-local.sh"
cp -- "$local_reader" "$sandbox/local-reader-original"
cp -- "$local_tui" "$sandbox/local-tui-original"
cp -- "$source_repo/scripts/smoke/fixtures/tui/vgs.jarvis/tui/setup-local.sh" "$local_tui"
jarvis_setup_requirements
terminal_stand_in
terminal_ready "Jarvis local setup"
jarvis_rescan
jarvis_enable
settings_page_open vgs.jarvis

local_value() {
  status_row vgs.jarvis localRuntime | py_reply '
import json,sys
r=json.load(sys.stdin)
expected={"absent":{"tone":"warning","text":"Not set up","action":True},
          "ready":{"tone":"ok","text":"Ready: small","action":False},
          "failed":{"tone":"warning","text":"Setup check failed","action":True},
          "invalid":{"tone":"warning","text":"Setup check returned invalid status","action":True}}[sys.argv[1]]
print("matched" if r["value"]==expected and r["action"]["offered"]==expected["action"] else "pending")
' "$1"
}
local_control_count() {
  local output
  output="$("$@")" || return 1
  printf '%s\n' "${output##*$'\n'}"
}
# The daemon's state and data roots, the hand-added Codex account the
# engine takes as its AI model, and local setup's marker.
setup_state="$home/.local/state/vgshell/jarvis"
setup_data="$home/.local/share/vgshell/jarvis"
setup_codex="$home/setup-codex"
setup_marker="$setup_state/local-ready.json"
setup_config="$home/.config/vgshell/shell.json"
setup_service="$repo/shell/plugins/vgs.jarvis/Service.qml"
# The Setup section by row: a required row as [label, chips, buttons,
# line count], an optional row as [label, whether its chip reads Done or
# Optional], since its readers' states depend on the world.
setup_rows() {
  ipc smoke setupRows window vgs.settings | py_reply '
import json,sys
rows=json.load(sys.stdin)
out=[]
for r in rows:
    if r["label"] in ("Browser", "Input"):
        out.append([r["label"], len(r["chips"]) == 1 and r["chips"][0][0] in ("Done", "Optional")])
    else:
        out.append([r["label"], r["chips"], [b[0] for b in r["buttons"]], len(r["lines"])])
print(json.dumps(out))
'
}
# BRAIN as the Jarvis AI model setting, "" for none, delivered by a reload.
setup_brain() { # BRAIN
  python3 - "$setup_config" "$1" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]); value=json.loads(p.read_text())
row=next((r for r in value.setdefault("plugins",[]) if r["id"]=="vgs.jarvis"),None)
if row is None:
    row={"id":"vgs.jarvis"}; value["plugins"].append(row)
if sys.argv[2]: row["brain"]=sys.argv[2]
else: row.pop("brain",None)
p.write_text(json.dumps(value))
PY
  expect "deliver the Jarvis AI model" ok ipc shell reloadConfig
}
# Local setup's marker for the plugin's first declared tier and the data
# root the engine compares (LocalSpeech.select).
setup_write_marker() {
  mkdir -p -- "$setup_data/local" &&
  python3 - "$repo/shell/plugins/vgs.jarvis/artifacts.json" "$setup_data/local" "$setup_marker" <<'PY'
import json,os,sys
tier=next(iter(json.load(open(sys.argv[1]))["tiers"]))
open(sys.argv[3],"w").write(json.dumps({"tier": tier, "data": os.path.realpath(sys.argv[2])}))
PY
}
setup_fresh='[["Status", [["Not ready", "warning"]], [], 1], ["AI model", [["To do", "warning"]], ["Add key"], 1], ["Local voice", [["To do", "warning"]], ["Set up local voice"], 1], ["Browser", true], ["Input", true]]'
setup_voice_left='[["Status", [["Not ready", "warning"]], [], 1], ["AI model", [["Done", "success"]], [], 0], ["Local voice", [["To do", "warning"]], ["Set up local voice"], 1], ["Browser", true], ["Input", true]]'
setup_ready='[["Status", [["Ready", "success"]], [], 1], ["AI model", [["Done", "success"]], [], 0], ["Local voice", [["Done", "success"]], [], 0], ["Browser", true], ["Input", true]]'
local_open() { # manager action or listed launcher entry
  local revision snapshot
  revision="$(jarvis_revision)" || return 1
  snapshot="$rt_dir/vgshell-sources-$shell_qs_pid/$revision"
  forget_record
  if [[ $1 == status ]]; then
    expect "Settings starts its declared local setup action" ok settings_act vgs.jarvis localRuntime
  else
    expect "the launcher starts its listed local setup" ok ipc shell openTui vgs.jarvis/setup-local
  fi
  expect_poll "setup receives the private plugin snapshot and declared argv" \
    "$(words --app-id=org.vgs.tui "--title=VGS · Set up Jarvis local voice" -- "$tui_self" present --presentation full \
      --plugin vgs.jarvis --dir "$snapshot" --record vgs.jarvis/setup-local --run RUN --record-dir "$rt_dir/vgshell/tui" \
      --app-id org.vgs.tui --window-title "VGS · Set up Jarvis local voice" -- tui/setup-local.sh)" recorded
  expect_run_end "the fixture local setup terminal ends" vgs.jarvis/setup-local
}
expect_poll "local setup is offered before verification" matched local_value absent
ipc shell listTuis | py_reply '
import json,sys
rows=json.load(sys.stdin)
assert any(row["key"]=="vgs.jarvis/setup-local" and row["group"]=="Jarvis" for row in rows)
'
expect_poll "a fresh profile's Setup section reads Not ready with the AI model and local voice to do" "$setup_fresh" setup_rows
# An AI model the engine takes: a hand-added Codex folder, by the id
# Accounts gives it.
mkdir -p -- "$setup_codex"
[[ ! -e $setup_state/accounts.json ]] || cp -- "$setup_state/accounts.json" "$sandbox/setup-accounts-before"
python3 - "$setup_state/accounts.json" "$setup_codex" <<'PY'
import json,sys
open(sys.argv[1],"w").write(json.dumps([{"provider": "codex", "directory": sys.argv[2], "label": "setup"}]))
PY
setup_brain_id="$(python3 -c 'import hashlib,json,sys; print("cli:" + hashlib.sha256(json.dumps(["codex", sys.argv[1]], separators=(",", ":")).encode()).hexdigest()[:32])' "$setup_codex")"
setup_brain "$setup_brain_id"
expect_poll "with an AI model the engine takes, only local voice remains" "$setup_voice_left" setup_rows
setup_write_marker || fail "local setup's marker is not written"
printf 'ready\n' >"$sandbox/jarvis-world/local-mode"
local_open status
expect_poll "the service rereads readiness after the Settings action ends" matched local_value ready
expect_poll "the ended local setup reaches the daemon: the Setup section reads Ready" "$setup_ready" setup_rows

# Control: no reader's end sends a snapshot, so the daemon keeps its
# earlier answer after the marker appears and local setup ends.
cp -- "$setup_service" "$sandbox/setup-service-original"
python3 - "$setup_service" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
assert not p.is_symlink()
s=p.read_text()
needle="; onRefreshed: root.hello() }"
assert s.count(needle)==3
changed=s.replace(needle, " }")
assert changed != s
p.write_text(changed)
PY
rm -- "$setup_marker"
jarvis_rescan
expect_poll "the snapshot control first reads local voice to do" "$setup_voice_left" setup_rows
expect_poll "the snapshot control first reads local voice to do: reader is idle" idle jarvis_setup_reader_idle LocalRuntime
setup_write_marker || fail "local setup's marker is not written"
local_open launcher
setup_snapshot_control() {
  (failures=0 behaviour_failures=0
   expect_poll "the ended local setup must reach the daemon" "$setup_ready" setup_rows
   echo "$failures")
}
expect "reader ends that send no snapshot break the Ready read" 1 local_control_count setup_snapshot_control
cp -- "$sandbox/setup-service-original" "$setup_service"
jarvis_rescan
expect_poll "the restored service reads Ready" "$setup_ready" setup_rows
printf 'failed\n' >"$sandbox/jarvis-world/local-mode"
local_open launcher
expect_poll "exit 77 replaces a previous ready status" matched local_value failed
printf 'invalid\n' >"$sandbox/jarvis-world/local-mode"
local_open launcher
expect_poll "invalid output cannot retain ready" matched local_value invalid

# Preserve the handler text and drop its effect on a disposable copy.
python3 - "$local_reader" <<'PY'
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
printf 'ready\n' >"$sandbox/jarvis-world/local-mode"
jarvis_rescan
expect_poll "the refresh control first reads ready" matched local_value ready
expect_poll "the refresh control first reads ready: reader is idle" idle jarvis_setup_reader_idle LocalRuntime
printf 'failed\n' >"$sandbox/jarvis-world/local-mode"
local_open launcher
local_refresh_control() {
  (failures=0 behaviour_failures=0
   expect_poll "the completed TUI must replace ready" matched local_value failed
   echo "$failures")
}
expect "removing end refresh breaks its consumer read" 1 local_control_count local_refresh_control
cp -- "$sandbox/local-reader-original" "$local_reader"
printf 'absent\n' >"$sandbox/jarvis-world/local-mode"
jarvis_rescan
expect_poll "the restored reader offers setup" matched local_value absent

python3 - "$local_reader" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
needle='if (code === 0) value = JSON.parse(output);'
assert s.count(needle)==1
changed=s.replace(needle, 'if (code !== 0) return;\n            ' + needle)
assert changed != s
p.write_text(changed)
PY
printf 'ready\n' >"$sandbox/jarvis-world/local-mode"
jarvis_rescan
expect_poll "the failed-probe control first reads ready" matched local_value ready
expect_poll "the failed-probe control first reads ready: reader is idle" idle jarvis_setup_reader_idle LocalRuntime
printf 'failed\n' >"$sandbox/jarvis-world/local-mode"
local_open launcher
local_failure_control() {
  (failures=0 behaviour_failures=0
   expect_poll "a failed check must clear ready" matched local_value failed
   echo "$failures")
}
expect "retaining ready after probe failure breaks its consumer read" 1 local_control_count local_failure_control
cp -- "$sandbox/local-reader-original" "$local_reader"
cp -- "$sandbox/local-tui-original" "$local_tui"
printf 'absent\n' >"$sandbox/jarvis-world/local-mode"
jarvis_rescan
expect_poll "the restored setup action is offered" matched local_value absent
rm -f -- "$setup_marker" "$setup_state/accounts.json"
[[ ! -e $sandbox/setup-accounts-before ]] || cp -- "$sandbox/setup-accounts-before" "$setup_state/accounts.json"
rm -rf -- "${setup_codex:?}"
setup_brain ""
expect_poll "without the AI model and the marker the Setup section reads Not ready again" "$setup_fresh" setup_rows
settings_page_close vgs.jarvis
jarvis_disable
jarvis_restore_requirements
