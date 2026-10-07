# No latency budget. Poll once per nested IPC round trip.
# Process, local-speech and allow-listed TUI stand-ins run here.
# The Setup section reads the real daemon's engine answer by row: label,
# chip tone, the screen beside a step and its line count. A fresh profile
# reads the AI model and local voice to do; an AI model whose account is
# not there yet stays to do until an Accounts screen ends with the
# account added, and local voice until its marker is there, its setup
# run ends and the sidecar reports ready. Browser and input are optional rows. Its
# controls are two Service copies, one whose key and account readers send
# no snapshot when their checks end and one whose local voice reader
# sends none.
# inputs: shell/plugins/vgs.jarvis/* shell/plugins/vgs.settings/* shell/Commons/Reply.js scripts/smoke/fixtures/tui/vgs.jarvis/* shell/Core/TuiRunner.qml scripts/fixtures/jarvis-setup/status.py scripts/fixtures/jarvis-local-speech/standin.py scripts/smoke/rows/jarvis.sh bin/vgshell-tui bin/lib/account-folders.js bin/lib/codex-account.js bin/lib/anchored.js shell/Commons/AccountDirectories.js bin/lib/qml-library.js
set -euo pipefail
local_reader="$repo/shell/plugins/vgs.jarvis/LocalRuntime.qml"
local_tui="$repo/shell/plugins/vgs.jarvis/tui/setup-local.sh"
cp -- "$local_reader" "$sandbox/local-reader-original"
cp -- "$local_tui" "$sandbox/local-tui-original"
cp -- "$source_repo/scripts/smoke/fixtures/tui/vgs.jarvis/tui/setup-local.sh" "$local_tui"
accounts_tui="$repo/shell/plugins/vgs.jarvis/tui/accounts.sh"
cp -- "$accounts_tui" "$sandbox/accounts-tui-original"
cp -- "$source_repo/scripts/smoke/fixtures/tui/vgs.jarvis/tui/accounts.sh" "$accounts_tui"
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
# The Setup section by row: a required row as [label, chip tones, the TUI
# of each button beside it, line count], an optional row as [label,
# whether its chip reads done or optional], since its readers' states
# depend on the world.
setup_rows() {
  ipc smoke setupRows window vgs.settings | py_reply '
import json,sys
rows=json.load(sys.stdin)
out=[]
for r in rows:
    if r["label"] in ("Browser", "Input"):
        out.append([r["label"], len(r["chips"]) == 1 and r["chips"][0][1] in ("success", "info")])
    else:
        out.append([r["label"], [c[1] for c in r["chips"]], [b["tui"] for b in r["buttons"]], len(r["lines"])])
print(json.dumps(out))
'
}
setup_fresh='[["Status", ["warning"], [], 1], ["AI model", ["warning"], ["add-key"], 1], ["Local voice", ["warning"], ["setup-local"], 1], ["Browser", true], ["Input", true]]'
setup_voice_left='[["Status", ["warning"], [], 1], ["AI model", ["success"], [], 0], ["Local voice", ["warning"], ["setup-local"], 1], ["Browser", true], ["Input", true]]'
setup_ready='[["Status", ["success"], [], 1], ["AI model", ["success"], [], 0], ["Local voice", ["success"], [], 0], ["Browser", true], ["Input", true]]'
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
# The AI model setting the running daemon's Session holds.
setup_daemon_brain() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
d=json.load(sys.stdin)
detail=d.get("status",{}).get("detail") if isinstance(d,dict) else None
print(json.dumps(detail["state"]["settings"]["brain"]) if isinstance(detail,dict) else "none")
'
}
# The hand-added Codex folder in the account list, and its id as the
# account helper lists it. The helper runs with no PATH entry, so no
# vendor command or port read starts.
setup_add_codex() {
  python3 - "$setup_state/accounts.json" "$setup_codex" <<'PY'
import json,sys
open(sys.argv[1],"w").write(json.dumps([{"provider": "codex", "directory": sys.argv[2], "label": "setup"}]))
PY
}
setup_codex_id() {
  mkdir -p -- "$sandbox/setup-no-path" &&
  env -i PATH="$sandbox/setup-no-path" HOME="$home" XDG_STATE_HOME="$home/.local/state" XDG_CONFIG_HOME="$home/.config" \
    XDG_DATA_HOME="$home/.local/share" "$node_bin" "$repo/shell/plugins/vgs.jarvis/backend/accounts.js" --tree "$repo" list |
    py_reply 'import json,sys; print(next(a["id"] for a in json.load(sys.stdin) if a["source"].get("directory")==sys.argv[1]))' "$setup_codex"
}
# Local setup's marker for the plugin's first declared tier and the data
# root the engine compares (LocalSpeech.select).
setup_write_marker() {
  mkdir -p -- "$setup_data/local/venv/bin" &&
  cp -- "$source_repo/scripts/fixtures/jarvis-local-speech/standin.py" "$setup_data/local/venv/bin/python" &&
  chmod 700 -- "$setup_data/local/venv/bin/python" &&
  python3 - "$repo/shell/plugins/vgs.jarvis/artifacts.json" "$setup_data/local" "$setup_marker" <<'PY'
import json,os,sys
tier=next(iter(json.load(open(sys.argv[1]))["tiers"]))
open(sys.argv[3],"w").write(json.dumps({"tier": tier, "data": os.path.realpath(sys.argv[2])}))
open(os.path.join(sys.argv[2],"scenario.json"),"w").write(json.dumps({"start":"ready"}))
PY
}
# The key reader with no check pending, its last one ended.
setup_keys_idle() {
  ipc smoke itemValues service vgs.jarvis Keys pending,code | py_reply '
import json,sys
rows=json.load(sys.stdin)
print("idle" if len(rows)==1 and rows[0]["pending"] is False and rows[0]["code"] != -1 else "pending")
'
}
# Every reader whose end sends a snapshot is idle, so a later snapshot is
# the step's own.
setup_readers_idle() { # LABEL
  expect_poll "$1: the local voice reader is idle" idle jarvis_setup_reader_idle LocalRuntime
  expect_poll "$1: the account reader is idle" idle jarvis_accounts_reader_idle
  expect_poll "$1: the key reader is idle" idle setup_keys_idle
}
setup_accounts_end() {
  forget_record
  expect "the launcher opens the accounts screen" ok ipc shell openTui vgs.jarvis/accounts
  expect_run_end "the fixture accounts terminal ends" vgs.jarvis/accounts
}
# A Service copy whose readers named by NEEDLES send no snapshot.
setup_service_without() { # NEEDLE...
  python3 - "$setup_service" "$@" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
assert not p.is_symlink()
s=p.read_text()
for needle in sys.argv[2:]:
    assert s.count(needle)==1, needle
    s=s.replace(needle, needle.replace("; onRefreshed: root.hello() }", " }"))
p.write_text(s)
PY
}
setup_keys_hook="Jarvis.Keys { shell: root.shell; onRefreshed: root.hello() }"
setup_accounts_hook="Jarvis.Accounts { shell: root.shell; onRefreshed: root.hello() }"
setup_local_hook="Jarvis.LocalRuntime { shell: root.shell; onRefreshed: root.hello() }"
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
expect_poll "a fresh profile's Setup section reads the AI model and local voice to do" "$setup_fresh" setup_rows
# An AI model the engine takes: a hand-added Codex folder, by the id the
# account helper lists. Chosen while its account is not there, it stays
# to do; an Accounts screen that ends with the account added sends the
# daemon a fresh snapshot, with no rescan.
mkdir -p -- "$setup_codex"
[[ ! -e $setup_state/accounts.json ]] || cp -- "$setup_state/accounts.json" "$sandbox/setup-accounts-before"
setup_add_codex
setup_brain_id="$(setup_codex_id)" || fail "the account helper lists no id for the Codex folder"
rm -- "$setup_state/accounts.json"
setup_brain "$setup_brain_id"
expect_poll "the daemon holds the chosen AI model" "\"$setup_brain_id\"" setup_daemon_brain
expect_poll "an AI model whose account is not there stays to do" "$setup_fresh" setup_rows
setup_readers_idle "before the account is added"
setup_add_codex
setup_accounts_end
expect_poll "the ended Accounts screen reaches the daemon: only local voice remains" "$setup_voice_left" setup_rows

# Control: the key and account readers' ends send no snapshot, so the
# daemon keeps its answer after the account is added.
cp -- "$setup_service" "$sandbox/setup-service-original"
setup_service_without "$setup_keys_hook" "$setup_accounts_hook"
rm -- "$setup_state/accounts.json"
jarvis_rescan
expect_poll "the account control first reads the AI model to do" "$setup_fresh" setup_rows
setup_readers_idle "the account control"
setup_add_codex
setup_accounts_end
setup_account_control() {
  (failures=0 behaviour_failures=0
   expect_poll "the ended Accounts screen must reach the daemon" "$setup_voice_left" setup_rows
   echo "$failures")
}
expect "account reader ends that send no snapshot break the AI model read" 1 local_control_count setup_account_control
cp -- "$sandbox/setup-service-original" "$setup_service"
jarvis_rescan
expect_poll "the restored service reads only local voice left" "$setup_voice_left" setup_rows

setup_write_marker || fail "local setup's marker is not written"
printf 'ready\n' >"$sandbox/jarvis-world/local-mode"
local_open status
expect_poll "the service rereads readiness after the Settings action ends" matched local_value ready
expect_poll "the ended local setup reaches the daemon: the Setup section reads ready" "$setup_ready" setup_rows

# Control: the local voice reader's end sends no snapshot, so the daemon
# keeps its answer after the marker appears and local setup ends.
setup_service_without "$setup_local_hook"
rm -- "$setup_marker"
jarvis_rescan
expect_poll "the local voice control first reads local voice to do" "$setup_voice_left" setup_rows
setup_readers_idle "the local voice control"
setup_write_marker || fail "local setup's marker is not written"
local_open launcher
setup_local_control() {
  (failures=0 behaviour_failures=0
   expect_poll "the ended local setup must reach the daemon" "$setup_ready" setup_rows
   echo "$failures")
}
expect "a local voice reader end that sends no snapshot breaks the ready read" 1 local_control_count setup_local_control
cp -- "$sandbox/setup-service-original" "$setup_service"
jarvis_rescan
expect_poll "the restored service reads ready" "$setup_ready" setup_rows
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
cp -- "$sandbox/accounts-tui-original" "$accounts_tui"
printf 'absent\n' >"$sandbox/jarvis-world/local-mode"
jarvis_rescan
expect_poll "the restored setup action is offered" matched local_value absent
rm -f -- "$setup_marker" "$setup_state/accounts.json"
[[ ! -e $sandbox/setup-accounts-before ]] || cp -- "$sandbox/setup-accounts-before" "$setup_state/accounts.json"
rm -rf -- "${setup_codex:?}"
setup_brain ""
expect_poll "without the AI model and the marker the Setup section reads both steps to do again" "$setup_fresh" setup_rows
settings_page_close vgs.jarvis
jarvis_disable
jarvis_restore_requirements
