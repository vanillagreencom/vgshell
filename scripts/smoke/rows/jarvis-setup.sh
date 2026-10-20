# No latency budget. Poll once per nested IPC round trip.
# Process, local-speech and allow-listed TUI stand-ins run here.
# Setup reads the real daemon's required Model and Voice answers by
# manifest key, Done or To do chip, and offered text action. Optional
# local voice, browser, input and cloned voice actions belong on Settings. A fresh profile
# reads the AI model and local voice to do; an AI model whose account is
# not there yet stays to do until an Accounts screen ends with the
# account added, and local voice until its marker is there, its setup
# run ends and the sidecar reports ready. Its
# controls are two Service copies, one whose key and account readers send
# no snapshot when their checks end and one whose local voice reader
# sends none. Last, a `pi` stand-in below the floor the manifest gives Pi:
# chosen as the AI model, the daemon refuses it, the AI model step reads to
# do and offers no step, and the Setup section draws no button beside it,
# while its Account setting holds the outdated tool reading. The
# same Pi at its floor reads present, which is the control. The local
# voice records through the core's dictation, so the row puts the voxtype
# stand-in on the shell's PATH (rows/capabilities.sh) for its ready reads
# and takes it away at its end. The Local voice setting: a start opens no
# local setup, which a reader copy that reads its start setting from the
# binding breaks; a change opens local setup with the wanted tier,
# Automatic with none; the run's end writes back the tier it left ready,
# which opens nothing, and nor does a wanted tier that is ready. Its
# control is a LocalTier copy that opens no run. The Cloned voice: the
# Settings tab's Local voice section draws its setting and attached state.
# Details draws no copy. The reader answers as setup-local does. Its text
# action opens the clone setup.
# Beside no large tier the row offers nothing; once a local voice setup's
# run ends beside a ready one, with no rescan, it opens the clone setup
# while the voice resolves Local, and offers nothing with Realtime chosen.
# A successful Remove recording run turns the Cloned voice setting off, so
# the setting and attached state agree.
# The fleet reader checks again when the daemon publishes homes after setup,
# without a settings write, requirement scan or terminal completion. A copy
# that drops that refresh retains its earlier optional reading.
# inputs: scripts/fixtures/jarvis/audio-tool.py shell/plugins/vgs.jarvis/* shell/plugins/vgs.settings/* shell/Commons/Reply.js scripts/smoke/fixtures/tui/vgs.jarvis/* shell/Core/TuiRunner.qml scripts/fixtures/jarvis-setup/status.py scripts/fixtures/jarvis-local-speech/standin.py scripts/smoke/rows/jarvis.sh bin/vgshell-tui bin/lib/account-folders.js bin/lib/codex-account.js bin/lib/anchored.js shell/Commons/AccountDirectories.js bin/lib/qml-library.js bin/vgshell-scan shell/Core/Registry.qml shell/Core/Notices.qml shell/Core/PluginLogic.js shell/Core/ConfigLogic.js scripts/smoke/rows/capabilities.sh scripts/smoke/fixtures/voxtype/* shell/Core/Dictation.qml shell/Core/DictationModel.js scripts/fixtures/jarvis/prepare.js
set -euo pipefail
# Jarvis holds `dictation`, and the shell finds no voxtype: the core's
# probe does not start at each enable.
expected_errors+=("${dictation_absent_errors[@]}")
local_reader="$repo/shell/plugins/vgs.jarvis/LocalRuntime.qml"
local_tui="$repo/shell/plugins/vgs.jarvis/tui/setup-local.sh"
cp -- "$local_reader" "$sandbox/local-reader-original"
cp -- "$local_tui" "$sandbox/local-tui-original"
cp -- "$source_repo/scripts/smoke/fixtures/tui/vgs.jarvis/tui/setup-local.sh" "$local_tui"
accounts_tui="$repo/shell/plugins/vgs.jarvis/tui/accounts.sh"
cp -- "$accounts_tui" "$sandbox/accounts-tui-original"
cp -- "$source_repo/scripts/smoke/fixtures/tui/vgs.jarvis/tui/accounts.sh" "$accounts_tui"
sign_in_tui="$repo/shell/plugins/vgs.jarvis/tui/sign-in.sh"
cp -- "$sign_in_tui" "$sandbox/sign-in-tui-original"
cp -- "$source_repo/scripts/smoke/fixtures/tui/vgs.jarvis/tui/sign-in.sh" "$sign_in_tui"
jarvis_setup_requirements
dictation_stand_ins on || fail "the shell does not resolve voxtype to the stand-in: $(shell_resolves voxtype)"
terminal_stand_in
terminal_ready "Jarvis local setup"
# A `pi` for the last section. The daemon's world copies its stand-ins when
# it starts (scripts/lib/jarvis-env.sh), so the program is written before
# Jarvis is enabled; it answers `--version` with the line setup_pi_version
# holds and nothing else, and fails while that file is absent.
setup_pi_version="$sandbox/jarvis-world/pi-version"
setup_pi_standin="$sandbox/jarvis-world/standins/pi"
printf '#!/bin/bash\n[[ $# == 1 && $1 == --version ]] || exit 2\nexec cat %q\n' "$setup_pi_version" >"$setup_pi_standin" && chmod 755 "$setup_pi_standin" ||
  fail "the daemon's Pi stand-in is not written"
jarvis_rescan
forget_record
jarvis_enable
settings_page_open vgs.jarvis
settings_setup

# The Local voice reading on Details by its value: [tone and text, whether
# a hint says why, its line count]. It never offers an action: the Voice
# step's Set up local voice sets it up. While the Voice step offers that
# setup the row is a state of it, in the info tone with one line saying why
# the step asks for it (`-under-voice`); beside a Voice step that offers
# none it keeps its reading's tone (`-open`).
local_value() {
  status_row vgs.jarvis localRuntime | py_reply '
import json,sys
r=json.load(sys.stdin)
expected={"absent-under-voice":({"tone":"info","text":"Not set up"},False,1),
          "absent-open":({"tone":"warning","text":"Not set up"},False,0),
          "optional":({"tone":"info","text":"Not set up"},False,0),
          "ready":({"tone":"ok","text":"Ready: small"},False,0),
          "failed-open":({"tone":"warning","text":"Setup check failed"},True,0),
          "invalid-open":({"tone":"warning","text":"Setup check returned invalid status"},True,0)}[sys.argv[1]]
v=r["value"]
fields,reasoned,lines=expected
ok=isinstance(v,dict) and set(v)<=set(fields)|{"hint","lines"} and {k:v.get(k) for k in fields}==fields
ok=ok and ("hint" in v)==reasoned and len(v.get("lines",[]))==lines
print("matched" if ok and r["action"] is None else "pending")
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
# Required Setup rows use manifest ids. Read the two daemon-controlled
# steps independently of Tools and the Home folder's state.
setup_rows() {
  ipc smoke setupRows window vgs.settings | py_reply '
import json,sys
rows=json.load(sys.stdin)
out=[]
for key in ("setupModel", "setupVoice"):
    matches=[r for r in rows if r["key"] == key]
    if len(matches) != 1:
        print("rows=%s:%d" % (key,len(matches))); sys.exit()
    r=matches[0]
    out.append([key, r["chips"], [b["text"] for b in r["buttons"]]])
print(json.dumps(out))
'
}
setup_fresh='[["setupModel", [["To do", "warning"]], []], ["setupVoice", [["To do", "warning"]], ["Set up local voice"]]]'
setup_voice_left='[["setupModel", [["Done", "success"]], []], ["setupVoice", [["To do", "warning"]], ["Set up local voice"]]]'
setup_ready='[["setupModel", [["Done", "success"]], []], ["setupVoice", [["To do", "warning"]], ["Check microphone"]]]'
# The Setup tab draws no optional rows or screens and each required step
# uses the required chip vocabulary. Required local voice setup appears once.
setup_once() {
  ipc smoke setupRows window vgs.settings | py_reply '
import json,sys
rows=json.load(sys.stdin)
forbidden={"setup", "clonedVoiceSetup", "browser", "input", "localRuntime", "keys", "copilotMemory", "setupFleet"}
violations=[r["key"] for r in rows if r["key"] in forbidden or r["chips"] not in ([["To do","warning"]], [["Done","success"]]) and not (r["key"] == "optional-tools" and r["chips"] == [["Optional","neutral"]])]
if sum(b["text"] == "Set up local voice" for r in rows for b in r["buttons"]) > 1: violations.append("setup-local-repeated")
print(json.dumps(violations) if rows else "absent")
'
}
# BRAIN as the Jarvis AI model setting, "" for none, delivered by a reload.
setup_brain() { # BRAIN
  user_config_write python3 - "$setup_config" "$1" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]); value=json.loads(p.read_text())
row=next((r for r in value.setdefault("plugins",[]) if r["id"]=="vgs.jarvis"),None)
if row is None:
    row={"id":"vgs.jarvis"}; value["plugins"].append(row)
if sys.argv[2]: row["brain"]=sys.argv[2]
else: row.pop("brain",None)
print(json.dumps(value))
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
  expect_poll "$1: the cloned voice reader is idle" idle jarvis_setup_reader_idle CloneRuntime
  expect_poll "$1: the account reader is idle" idle jarvis_accounts_reader_idle
  expect_poll "$1: the key reader is idle" idle setup_keys_idle
}
setup_accounts_end() {
  forget_record
  expect "the launcher opens the accounts screen" ok ipc shell openTui vgs.jarvis/accounts
  expect_run_end "the fixture accounts terminal ends" vgs.jarvis/accounts
}
setup_sign_in_end() {
  forget_record
  expect "the launcher opens the declared vendor sign-in terminal" ok ipc shell openTui vgs.jarvis/sign-in
  expect_poll "sign-in uses the core floating terminal and declared script" \
    '["vgs.jarvis/sign-in", "tui/sign-in.sh"]' recorded_tail
  expect_run_end "the fixture sign-in terminal ends without authentication" vgs.jarvis/sign-in
}
# A Service copy whose readers named by NEEDLES send no snapshot. A local
# voice end reaches the daemon twice: its own hello and the cloned voice
# check it starts, whose end sends one too; the copy drops both.
setup_service_without() { # NEEDLE...
  python3 - "$setup_service" "$@" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
assert not p.is_symlink()
s=p.read_text()
for needle in sys.argv[2:]:
    assert s.count(needle)==1, needle
    dropped=needle.replace("; onRefreshed: root.hello() }", " }").replace("            root.hello();\n            cloneRuntime.refresh();", "            if (false) { root.hello(); cloneRuntime.refresh(); }")
    assert dropped!=needle, needle
    s=s.replace(needle, dropped)
p.write_text(s)
PY
}
setup_keys_hook="Jarvis.Keys { shell: root.shell; onRefreshed: root.hello() }"
setup_accounts_hook="Jarvis.Accounts { id: accountReader; shell: root.shell; onRefreshed: root.hello() }"
setup_local_hook=$'onRefreshed: {\n            if (!root.publishShellSetup()) return;\n            root.hello();\n            cloneRuntime.refresh();\n        }'
# The Local voice reader's answer (scripts/fixtures/jarvis-setup/status.py
# --choices): PICK, READY ("none" for none) and the offers of a machine that
# runs every English tier.
setup_tiers="$sandbox/jarvis-world/local-tiers.json"
setup_tiers_answer() { # PICK READY
  python3 - "$setup_tiers" "$1" "$2" <<'PY'
import json,os,sys
path,pick,ready=sys.argv[1],sys.argv[2],None if sys.argv[3]=="none" else sys.argv[3]
labels={"small":"Small: English, quick setup, 685 MB","medium":"Medium: English, many voices, 968 MB",
        "large":"Large: English, graphics card, 1.2 GB"}
choices=[{"value":"auto","label":"Auto: "+labels[pick].replace(": ",", ",1)}]+[{"value":t,"label":l} for t,l in labels.items() if t!=pick]
open(path+".next","w").write(json.dumps({"pick":pick,"ready":ready,"choices":choices}))
os.replace(path+".next",path)
PY
}
# The reader's last answer as [pick, ready] once no read is running.
setup_tier_reading() {
  ipc smoke itemValues service vgs.jarvis LocalTier reading,pending,code | py_reply '
import json,sys
rows=json.load(sys.stdin)
r=rows[0] if len(rows)==1 else {}
print(json.dumps([r["reading"]["pick"], r["reading"]["ready"]]) if r.get("reading") and r["pending"] is False and r["code"]==0 else "pending")
'
}
# The first offer the service publishes for the page's Local voice field.
setup_tiers_published() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
offers=json.load(sys.stdin)["status"].get("localTiers") or []
print(json.dumps(offers[0]) if offers else "none")
'
}
# VALUE as the Local voice setting, delivered by a reload.
setup_tier() { # VALUE
  user_config_write python3 - "$setup_config" "$1" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]); value=json.loads(p.read_text())
row=next((r for r in value.setdefault("plugins",[]) if r["id"]=="vgs.jarvis"),None)
if row is None:
    row={"id":"vgs.jarvis"}; value["plugins"].append(row)
row["localTier"]=sys.argv[2]
print(json.dumps(value))
PY
  expect "deliver the Local voice setting $1" ok ipc shell reloadConfig
}
setup_tier_saved() {
  python3 -c 'import json,sys; print(next((r.get("localTier","unset") for r in json.load(open(sys.argv[1])).get("plugins",[]) if r["id"]=="vgs.jarvis"),"unset"))' "$setup_config"
}
# The run id of the last terminal the launcher started, "absent" for none.
setup_run_id() {
  python3 -c '
import os,sys
w=open(sys.argv[1]).read().split("\n") if os.path.exists(sys.argv[1]) else []
print(w[w.index("--run")+1] if "--run" in w else "absent")' "$tui_record"
}
# A launch a delivered setting asks for is pending in the turn that
# delivers it, so once the key is idle no later terminal is to come.
setup_tier_opens_none() { # LABEL RUN_ID
  expect_run_end "$1: no local setup is pending" vgs.jarvis/setup-local
  expect "$1: no terminal opened" "$2" setup_run_id
}
setup_tier_reader="$repo/shell/plugins/vgs.jarvis/LocalTier.qml"
# A start with the default answer, small the pick and nothing ready, opens
# no local setup: the reader acts only on a change of the setting.
setup_tier_start_none() {
  expect_poll "the Local voice reader reads the default answer at start" '["small", null]' setup_tier_reading
  expect_run_end "no local setup is pending after the start" vgs.jarvis/setup-local
  expect "the start opened no local setup" absent recorded
}
setup_tier_start_none
# Control: a reader copy that takes the start setting from its binding,
# which still reads "" when the shell arrives, opens local setup at start.
cp -- "$setup_tier_reader" "$sandbox/local-tier-original"
python3 - "$setup_tier_reader" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
assert not p.is_symlink()
s=p.read_text()
needle="decided = shell.settings.localTier;"
assert s.count(needle)==1
p.write_text(s.replace(needle, "decided = wanted;"))
PY
forget_record
jarvis_rescan
setup_tier_start_control() {
  (failures=0 behaviour_failures=0
   setup_tier_start_none >"$sandbox/tier-start-control.log"
   echo "$failures")
}
expect "a start setting read from the binding opens local setup" 1 local_control_count setup_tier_start_control
cp -- "$sandbox/local-tier-original" "$setup_tier_reader"
jarvis_rescan
# The Voice step offers its setup while the daemon reads local voice to do:
# a status open follows local_ready with every reader idle, so no hello
# reaches the daemon between the marker and the press.
local_open() { # status | launcher
  local revision snapshot
  revision="$(jarvis_revision)" || return 1
  snapshot="$rt_dir/vgshell-sources-$shell_qs_pid/$revision"
  forget_record
  if [[ $1 == status ]]; then
    expect "Settings starts the Voice step's local setup action" ok settings_act vgs.jarvis setupVoice
  else
    expect "the launcher starts its listed local setup" ok ipc shell openTui vgs.jarvis/setup-local
  fi
  expect_poll "setup receives the private plugin snapshot and declared argv" \
    "$(words --app-id=org.vgs.tui "--title=VGS · Set up Jarvis local voice" -- "$tui_self" present --presentation full \
      --plugin vgs.jarvis --dir "$snapshot" --record vgs.jarvis/setup-local --run RUN --record-dir "$rt_dir/vgshell/tui" \
      --app-id org.vgs.tui --window-title "VGS · Set up Jarvis local voice" -- tui/setup-local.sh)" recorded
  expect_run_end "the fixture local setup terminal ends" vgs.jarvis/setup-local
}
local_ready() { printf 'ready\n' >"$sandbox/jarvis-world/local-mode" && setup_write_marker; }
expect_poll "Local voice reads not set up and leaves its setup to the Voice step" matched local_value absent-under-voice
ipc shell listTuis | py_reply '
import json,sys
rows=json.load(sys.stdin)
assert any(row["key"]=="vgs.jarvis/setup-local" and row["group"]=="Jarvis" for row in rows)
'
expect_poll "the Setup fixture retains its present key" matched jarvis_key_value present
expect_poll "the Setup fixture retains its signed-in app" matched jarvis_account_hint signed-in
expect_poll "a fresh profile's Setup section reads the AI model and local voice to do" "$setup_fresh" setup_rows
expect_poll "a fresh profile's Setup tab holds only required steps with Done or To do chips" '[]' setup_once
setup_sign_in_end
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
setup_sign_in_end
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
expect_poll "the restored local voice reader is idle" idle jarvis_setup_reader_idle LocalRuntime

setup_readers_idle "before the Voice step's local setup"
local_ready || fail "local setup's marker is not written"
local_open status
expect_poll "the service rereads readiness after the Settings action ends" matched local_value ready
expect_poll "the ended local setup reaches the daemon: the Setup section reads ready" "$setup_ready" setup_rows
expect_poll "the Setup tab keeps optional steps out after local voice setup" '[]' setup_once

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

# The Local voice setting, with small ready and large the pick. A rescan
# is a requirement scan, after which the reader reads again.
cp -- "$setup_tiers" "$sandbox/local-tiers-original"
setup_tiers_answer large small
rescan "the Local voice reader reads large as the pick"
expect_poll "the Local voice reader reads large as the pick, small ready" '["large", "small"]' setup_tier_reading
expect "the page offers Auto first, with the pick's description and size" '{"value": "auto", "label": "Auto: Large, English, graphics card, 1.2 GB"}' setup_tiers_published
forget_record
setup_tier medium
expect_poll "choosing Medium opens local setup for medium" '["vgs.jarvis/setup-local", "tui/setup-local.sh", "medium"]' recorded_tail
expect_run_end "the Medium run ends" vgs.jarvis/setup-local
setup_tier_run="$(setup_run_id)"
expect_poll "the run's end writes back the ready tier" small setup_tier_saved
setup_tier_opens_none "the written-back tier" "$setup_tier_run"
setup_tier auto
expect_poll "Automatic opens local setup with no tier" '["vgs.jarvis/setup-local", "tui/setup-local.sh"]' recorded_tail
expect_run_end "the Automatic run ends" vgs.jarvis/setup-local
expect_poll "the run's end writes back the ready tier again" small setup_tier_saved
# A wanted tier that is ready opens nothing, by name or as Automatic.
setup_tiers_answer large large
rescan "the Local voice reader reads large ready"
expect_poll "the Local voice reader reads large ready" '["large", "large"]' setup_tier_reading
setup_tier_run="$(setup_run_id)"
setup_tier large
setup_tier_opens_none "Large while large is ready" "$setup_tier_run"
setup_tier auto
setup_tier_opens_none "Automatic while the pick is ready" "$setup_tier_run"
# Control: a reader copy that opens no run breaks the Medium read.
cp -- "$setup_tier_reader" "$sandbox/local-tier-original"
python3 - "$setup_tier_reader" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
assert not p.is_symlink()
s=p.read_text()
needle='const answer = shell.tui.run("setup-local", args);'
assert s.count(needle)==1
p.write_text(s.replace(needle, 'const answer = "ok";'))
PY
jarvis_rescan
expect_poll "the run control's reader reads large ready" '["large", "large"]' setup_tier_reading
setup_tiers_answer large small
rescan "the run control's reader reads small ready"
expect_poll "the run control's reader reads small ready" '["large", "small"]' setup_tier_reading
forget_record
setup_tier medium
setup_tier_control() {
  (failures=0 behaviour_failures=0
   expect_poll "choosing Medium must open local setup" '["vgs.jarvis/setup-local", "tui/setup-local.sh", "medium"]' recorded_tail
   echo "$failures")
}
expect "a reader that opens no run breaks the Medium read" 1 local_control_count setup_tier_control
cp -- "$sandbox/local-tier-original" "$setup_tier_reader"
cp -- "$sandbox/local-tiers-original" "$setup_tiers"
setup_tier auto
jarvis_rescan
expect_poll "the restored Local voice reader reads the default answer" '["small", null]' setup_tier_reading
printf 'failed\n' >"$sandbox/jarvis-world/local-mode"
local_open launcher
expect_poll "exit 77 replaces a previous ready status" matched local_value failed-open
printf 'invalid\n' >"$sandbox/jarvis-world/local-mode"
local_open launcher
expect_poll "invalid output cannot retain ready" matched local_value invalid-open

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
   expect_poll "the completed TUI must replace ready" matched local_value failed-open
   echo "$failures")
}
expect "removing end refresh breaks its consumer read" 1 local_control_count local_refresh_control
cp -- "$sandbox/local-reader-original" "$local_reader"
printf 'absent\n' >"$sandbox/jarvis-world/local-mode"
jarvis_rescan
expect_poll "the restored reader reads not set up" matched local_value absent-open

python3 - "$local_reader" <<'PY'
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
printf 'ready\n' >"$sandbox/jarvis-world/local-mode"
jarvis_rescan
expect_poll "the failed-probe control first reads ready" matched local_value ready
expect_poll "the failed-probe control first reads ready: reader is idle" idle jarvis_setup_reader_idle LocalRuntime
printf 'failed\n' >"$sandbox/jarvis-world/local-mode"
local_open launcher
local_failure_control() {
  (failures=0 behaviour_failures=0
   expect_poll "a failed check must clear ready" matched local_value failed-open
   echo "$failures")
}
expect "retaining ready after probe failure breaks its consumer read" 1 local_control_count local_failure_control
cp -- "$sandbox/local-reader-original" "$local_reader"
cp -- "$sandbox/local-tui-original" "$local_tui"
cp -- "$sandbox/accounts-tui-original" "$accounts_tui"
cp -- "$sandbox/sign-in-tui-original" "$sign_in_tui"
printf 'absent\n' >"$sandbox/jarvis-world/local-mode"
jarvis_rescan
expect_poll "the restored reader reads not set up again" matched local_value absent-open
rm -f -- "$setup_marker" "$setup_state/accounts.json"
[[ ! -e $sandbox/setup-accounts-before ]] || cp -- "$sandbox/setup-accounts-before" "$setup_state/accounts.json"
rm -rf -- "${setup_codex:?}"
setup_brain ""
expect_poll "without the AI model and the marker the Setup section reads both steps to do again" "$setup_fresh" setup_rows

# The Cloned voice (VGS-1385). The reader's answer is setup-local clone
# status's (scripts/fixtures/jarvis-setup/status.py --clone); the voice the
# daemon runs comes from the Voice provider setting, left unset at the end.
setup_clone_status="$sandbox/jarvis-world/clone-status.json"
setup_clone_reader="$repo/shell/plugins/vgs.jarvis/CloneRuntime.qml"
cp -- "$setup_clone_status" "$sandbox/clone-status-original"
cp -- "$setup_clone_reader" "$sandbox/clone-runtime-original"
# The clone status answer with nothing set up, TIER_READY whether a large
# tier is ready.
setup_clone_answer() { # TIER_READY
  python3 - "$setup_clone_status" "$1" <<'PY'
import json,os,sys
open(sys.argv[1]+".next","w").write(json.dumps({"tone":"info","text":"Not set up","action":"setup","recording":False,"tierReady":sys.argv[2]=="true"}))
os.replace(sys.argv[1]+".next",sys.argv[1])
PY
}
setup_clone_ready_answer() { # TIER_READY
  python3 - "$setup_clone_status" "$1" <<'PY'
import json,os,sys
open(sys.argv[1]+".next","w").write(json.dumps({"tone":"ok","text":"Ready","action":"remove","recording":True,"tierReady":sys.argv[2]=="true"}))
os.replace(sys.argv[1]+".next",sys.argv[1])
PY
}
# VALUE as the Voice provider setting, "" for none, delivered by a reload.
setup_provider() { # VALUE
  user_config_write python3 - "$setup_config" "$1" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]); value=json.loads(p.read_text())
row=next((r for r in value.setdefault("plugins",[]) if r["id"]=="vgs.jarvis"),None)
if row is None:
    row={"id":"vgs.jarvis"}; value["plugins"].append(row)
if sys.argv[2]: row["voiceProvider"]=sys.argv[2]
else: row.pop("voiceProvider",None)
print(json.dumps(value))
PY
  expect "deliver the Voice provider ${1:-default}" ok ipc shell reloadConfig
}
setup_clone_setting() { # VALUE: true|false
  python3 - "$setup_config" "$1" <<'PY'
import json,os,sys
from pathlib import Path
p=Path(sys.argv[1]); value=json.loads(p.read_text())
row=next((r for r in value.setdefault("plugins",[]) if r["id"]=="vgs.jarvis"),None)
if row is None:
    row={"id":"vgs.jarvis"}; value["plugins"].append(row)
if sys.argv[2] == "true":
    row["clonedVoice"] = True
else:
    row.pop("clonedVoice", None)
tmp=str(p)+".next"
open(tmp,"w").write(json.dumps(value))
os.replace(tmp,p)
PY
  expect "deliver the Cloned voice setting $1" ok ipc shell reloadConfig
}
setup_clone_setting_value() {
  python3 - "$setup_config" <<'PY'
import json,sys
row=next((r for r in json.load(open(sys.argv[1])).get("plugins",[]) if r.get("id")=="vgs.jarvis"),{})
print("true" if row.get("clonedVoice", False) else "false")
PY
}
# The setup row as [offered, the screen its press opens].
setup_clone_row() {
  status_row vgs.jarvis clonedVoiceSetup | py_reply 'import json,sys; r=json.load(sys.stdin); print(json.dumps([r["action"]["offered"], r["action"]["tui"]]))'
}
# Whether the shown tab's SECTION section draws LABEL.
setup_tab_section() { # SECTION LABEL
  ipc smoke itemTexts window vgs.settings Section | py_reply 'import json,sys
r=[s for s in json.load(sys.stdin) if s and s[0]==sys.argv[1]]
print(json.dumps(any(sys.argv[2] in s for s in r)) if r else "absent")' "$1" "$2"
}
# Whether any section of the shown tab draws LABEL.
setup_tab_draws() { # LABEL
  ipc smoke itemTexts window vgs.settings Section | py_reply 'import json,sys; print(json.dumps(any(sys.argv[1] in s for s in json.load(sys.stdin))))' "$1"
}
# The shown tab's Cloned voice state: its Settings field owner, none on
# Details, chip tones and visible action words, enabled state and tone.
setup_clone_drawn() {
  ipc smoke settingRows window vgs.settings | py_reply 'import json,sys
r=[x for x in json.load(sys.stdin) if x["key"]=="clonedVoiceSetup"]
print(json.dumps([r[0]["field"], [c[1] for c in r[0]["chips"]], [[b["text"],b["enabled"],b["tone"]] for b in r[0]["buttons"]]]) if len(r)==1 else "rows=%d" % len(r))'
}
{ read -r setup_clone_setting_label && read -r setup_clone_step && read -r setup_clone_press && read -r setup_clone_remove; } < <(python3 -c 'import json,sys
m=json.load(open(sys.argv[1])); row=m["status"]["clonedVoiceSetup"]
print(m["schema"]["clonedVoice"]["label"]); print(row["label"]); print(row["actions"]["setup"]["label"]); print(row["actions"]["remove"]["label"])' "$repo/shell/plugins/vgs.jarvis/manifest.json") ||
  fail "the manifest names no Cloned voice setting, setup row or Set up action"
settings_details
setup_clone_answer false
rescan "a rescan reads the clone status beside no large tier"
expect_poll "beside no large tier the setup row offers nothing" '[false, ""]' setup_clone_row
expect_poll "Details draws Cloned voice with no action before the large tier is ready" '["", ["info"], []]' setup_clone_drawn
# A local voice setup's end reads the row again, with no rescan: the
# Large model now ready, the row offers the clone setup.
setup_clone_answer true
forget_record
expect "the launcher opens local voice setup" ok ipc shell openTui vgs.jarvis/setup-local
expect_run_end "the local voice setup terminal ends" vgs.jarvis/setup-local
expect_poll "after a local voice setup the setup row opens the clone setup while the voice resolves Local" '[true, "clone-voice"]' setup_clone_row
expect_poll "Details draws the declared clone setup text link beside Cloned voice" '["", ["info"], [["Set up cloned voice", true, "accent"]]]' setup_clone_drawn
settings_tab_click Settings || fail "the click on the Settings tab failed"
expect_poll "the plugin page shows Settings" Settings settings_tab_text
expect_poll "the Settings tab's Local voice section draws the Cloned voice setting" true setup_tab_section "Local voice" "$setup_clone_setting_label"
expect_poll "Settings draws no Cloned voice step" rows=0 setup_clone_drawn
settings_details
expect_poll "Details draws Cloned voice in its Local voice section" true setup_tab_section "Local voice" "$setup_clone_step"
forget_record
settings_press --type RowAction "$setup_clone_press" || fail "the click on $setup_clone_press failed"
expect_poll "the step's button opens the clone setup in the core floating terminal" '["vgs.jarvis/clone-voice", "tui/clone-voice.sh"]' recorded_tail
expect_run_end "the clone setup terminal ends" vgs.jarvis/clone-voice
setup_provider realtime
expect_poll "with Realtime chosen the setup row offers nothing" '[false, ""]' setup_clone_row
expect_poll "with Realtime chosen Local voice reads optional and offers no setup" matched local_value optional
setup_provider ""
expect_poll "the default voice, Local, hands Local voice setup to the Voice step again" matched local_value absent-under-voice
expect_poll "the default voice, Local, offers the clone setup again" '[true, "clone-voice"]' setup_clone_row

setup_clone_ready_answer true
rescan "a rescan reads the ready cloned voice"
expect_poll "a ready recording offers Remove recording" '[true, "clone-voice-remove"]' setup_clone_row
setup_clone_setting true
expect_poll "Cloned voice is on before Remove recording" true setup_clone_setting_value
hold_runs
settings_press --type RowAction "$setup_clone_remove" || fail "the click on $setup_clone_remove failed"
expect_poll "Remove recording opens its declared terminal" '["vgs.jarvis/clone-voice-remove", "tui/clone-voice-remove.sh"]' recorded_tail
setup_clone_answer true
release_runs
expect_run_end "the clone remove terminal ends" vgs.jarvis/clone-voice-remove
expect_poll "Remove recording turns Cloned voice off" false setup_clone_setting_value
expect_poll "after Remove recording the setup row offers Set up" '[true, "clone-voice"]' setup_clone_row

python3 - "$setup_clone_reader" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
needle='        const reply = shell.configure.unset("clonedVoice");\n        if (reply !== "ok") console.warn("jarvis-clone: setting=unwritten reply=" + reply);\n'
assert s.count(needle)==1
p.write_text(s.replace(needle, ""))
PY
jarvis_rescan
setup_clone_ready_answer true
rescan "the Remove control reads the ready cloned voice"
setup_clone_setting true
hold_runs
settings_press --type RowAction "$setup_clone_remove" || fail "control: the click on $setup_clone_remove failed"
setup_clone_answer true
release_runs
expect_run_end "control: the clone remove terminal ends" vgs.jarvis/clone-voice-remove
clone_remove_control() {
  (failures=0 behaviour_failures=0
   expect_poll "Remove recording must turn Cloned voice off" false setup_clone_setting_value
   echo "$failures")
}
expect "dropping the unset call leaves Cloned voice on after Remove recording" 1 local_control_count clone_remove_control
cp -- "$sandbox/clone-runtime-original" "$setup_clone_reader"
jarvis_rescan
setup_clone_setting false
cp -- "$sandbox/clone-status-original" "$setup_clone_status"

settings_setup

# A Pi below its floor. The stand-in answers `--version` and nothing else,
# so no Pi program runs a turn; its folder is added by hand, as the Codex
# folder above is. The shell's scan reads the same program from the
# sandbox PATH, and the daemon the copy its world took at its start.
setup_pi="$home/.pi/agent"
pi_version() { # VERSION
  printf '%s\n' "$1" >"$setup_pi_version.next" && mv -T -- "$setup_pi_version.next" "$setup_pi_version"
}
cp -- "$setup_pi_standin" "$shim/pi" && chmod 755 "$shim/pi" || fail "the shell's Pi stand-in is not written"
setup_pi_id() {
  env -i PATH="$sandbox/setup-no-path" HOME="$home" XDG_STATE_HOME="$home/.local/state" XDG_CONFIG_HOME="$home/.config" \
    XDG_DATA_HOME="$home/.local/share" "$node_bin" "$repo/shell/plugins/vgs.jarvis/backend/accounts.js" --tree "$repo" list |
    py_reply 'import json,sys; print(next(a["id"] for a in json.load(sys.stdin) if a["source"].get("directory")==sys.argv[1]))' "$setup_pi"
}
# The AI model step's published action, the label of its button and
# whether the button is offered.
setup_model_step() {
  status_row vgs.jarvis setupModel | py_reply 'import json,sys; r=json.load(sys.stdin); print(json.dumps([r["value"].get("tone"), r["value"].get("action"), r["action"]["offered"]]))'
}
# Pi's state in the plugin's requirements, beside its Account setting.
setup_pi_requirement() { ipc shell listPlugins | py_reply 'import json,sys; p=[p for p in json.load(sys.stdin)["plugins"] if p["id"]=="vgs.jarvis"][0]; print([r["state"] for r in p["requirements"] if r["name"]=="pi"][0])'; }
# The actions the Setup section draws beside its AI model step, each as
# its displayed words and whether it takes a press.
setup_model_drawn() {
  ipc smoke setupRows window vgs.settings | py_reply 'import json,sys
t=sys.stdin.read()
r=[x for x in (json.loads(t) if t.startswith("[") else []) if x["label"]=="AI model"]
print(json.dumps([[b["text"], b["enabled"]] for b in r[0]["buttons"]]) if r else "absent")'
}
pi_floor="$(python3 -c 'import json,sys; print(next(r["floor"] for r in json.load(open(sys.argv[1]))["requirements"] if r.get("command")=="pi"))' "$repo/shell/plugins/vgs.jarvis/manifest.json")" || fail "the manifest gives Pi no floor"
mkdir -p -- "$setup_pi" && printf '{}\n' >"$setup_pi/auth.json" || fail "the Pi folder is not written"
[[ ! -e $setup_state/accounts.json ]] || cp -- "$setup_state/accounts.json" "$sandbox/setup-accounts-before-pi"
python3 - "$setup_state/accounts.json" "$setup_pi" <<'PY' || fail "the Pi folder is not added to the account list"
import json,os,sys
held=json.load(open(sys.argv[1])) if os.path.exists(sys.argv[1]) else []
open(sys.argv[1],"w").write(json.dumps(held + [{"provider": "pi", "directory": sys.argv[2], "label": "setup"}]))
PY
pi_version 1.0.2 || fail "the Pi stand-in below its floor is not written"
rescan "a rescan after the Pi stand-in appears starts"
setup_pi_brain="$(setup_pi_id)" || fail "the account helper lists no id for the Pi folder"
setup_brain "$setup_pi_brain"
expect_poll "the daemon holds Pi as the chosen AI model" "\"$setup_pi_brain\"" setup_daemon_brain
expect_poll "a Pi below its floor leaves the AI model step to do, with no step of its own" '["warning", null, false]' setup_model_step
expect_poll "the Setup section draws no button beside the AI model" '[]' setup_model_drawn
expect_poll "the selected account tool reads Pi outdated" outdated setup_pi_requirement
# The control: the daemon judges the choice again when it is made again.
pi_version "$pi_floor" || fail "the Pi stand-in at its floor is not written"
rescan "a rescan with Pi at its floor starts"
setup_brain ""
expect_poll "the daemon holds no AI model between the two choices" '""' setup_daemon_brain
setup_brain "$setup_pi_brain"
expect_poll "the daemon holds Pi at its floor as the chosen AI model" "\"$setup_pi_brain\"" setup_daemon_brain
expect_poll "a Pi at its floor reads present in the requirements record" present setup_pi_requirement
rm -f -- "${shim:?}/pi" "${setup_state:?}/accounts.json" "${setup_pi_version:?}" "${setup_pi_standin:?}"
[[ ! -e $sandbox/setup-accounts-before-pi ]] || cp -- "$sandbox/setup-accounts-before-pi" "$setup_state/accounts.json"
rm -rf -- "${home:?}/.pi"
setup_brain ""
rescan "a rescan after the Pi stand-in goes starts"
expect_poll "without Pi the Setup section reads both steps to do again" "$setup_fresh" setup_rows
# The check uses the daemon's selected synthetic source and local wake
# sidecar. No brain is selected and no utterance is sent.
setup_brain ""
setup_readers_idle "before the voice check's local setup"
local_ready || fail "the voice-check marker is not written"
python3 - "$setup_data/local/scenario.json" <<'PYSCENARIO'
import json,sys
open(sys.argv[1],"w").write(json.dumps({"start":"ready", "checks":[{"afterFrames":1},{},{}]}))
PYSCENARIO
local_open status
jarvis_disable
jarvis_enable
setup_check_state() {
  ipc smoke jarvisProcess | py_reply 'import json,sys; d=json.load(sys.stdin)["status"].get("detail"); print(json.dumps(d["state"]["check"]) if d else "pending")'
}
setup_check_result() {
  ipc smoke jarvisProcess | py_reply 'import json,sys; d=json.load(sys.stdin)["status"].get("detail"); s=d["state"] if d else {}; c=s.get("check",{}); print(c.get("result","pending") if c.get("kind")=="done" and s["capture"]["kind"]=="closed" and s["turn"]["kind"]=="none" and s["brain"]["kind"]=="closed" else "pending")'
}
setup_check_row() {
  status_row vgs.jarvis setupVoice | py_reply 'import json,sys; r=json.load(sys.stdin); v=r["value"]; print(json.dumps([v["tone"],v["text"],v.get("hint"),r["action"]["tui"]]))'
}
setup_check_row_hint_present() {
  setup_check_row | py_reply 'import json,sys; r=json.load(sys.stdin); r[2]=isinstance(r[2],str) and bool(r[2].strip()); print(json.dumps(r))'
}
expect_poll "local voice can be checked before choosing an AI model" '{"kind": "ready"}' setup_check_state
setup_check_pid="$(ipc smoke jarvisProcess | jarvis_launcher_pid)"
setup_check_pid="$(jarvis_descendants "$setup_check_pid")"
setup_check_home="$(python3 - "$setup_check_pid" <<'PYHOME'
from pathlib import Path
import sys
values=dict(value.split(b"=",1) for value in Path("/proc/"+sys.argv[1]+"/environ").read_bytes().split(b"\0") if b"=" in value)
print(values[b"HOME"].decode())
PYHOME
)" || fail "the synthetic audio world's home is unreadable"
expect "Check microphone asks the daemon to start" ok ipc vgs.jarvis invoke check-microphone ''
expect_poll "the selected stand-in source wakes the detector" ready setup_check_result
expect_poll "Voice reports Ready and keeps the check action" '["ok", "Ready", null, "check-microphone"]' setup_check_row
expect "Check microphone can run again" ok ipc vgs.jarvis invoke check-microphone ''
expect_poll "sound without the wake phrase is not Ready" not-heard setup_check_result
expect_poll "Voice gives not-heard guidance and keeps the check action" '["warning", "Not heard", true, "check-microphone"]' setup_check_row_hint_present
: >"${setup_check_home:?}/capture-silent"
expect "Check microphone can check a silent source" ok ipc vgs.jarvis invoke check-microphone ''
expect_poll "an all-zero stand-in source is silent" silent setup_check_result
expect_poll "Voice gives the default microphone's Settings path in full" '["warning", "Muted or silent", "The default microphone is muted or sends silence: [check it in System > Sound](page:vgs.sound)", "check-microphone"]' setup_check_row
rm -f -- "${setup_check_home:?}/capture-silent"

# The daemon's installer and its completion publication have their backend
# controls. Replay its accepted homes message here to isolate the shell's
# refresh consumer, using the real read-only fleet status command.
setup_fleet_home="$home/Setup Fleet"
setup_fleet_tool="$setup_fleet_home/.agents/skills/mailbox/scripts/lane-mail"
setup_fleet_before="$(python3 - "$setup_config" <<'PYHOME'
import json,sys
row=next((r for r in json.load(open(sys.argv[1])).get("plugins",[]) if r.get("id")=="vgs.jarvis"),{})
print(json.dumps({"id":"vgs.jarvis","key":"home","value":row.get("home","")}))
PYHOME
)" || { fail "the fleet refresh case cannot read the previous home setting"; return 1; }
mkdir -p -- "$setup_fleet_home/.git" "${setup_fleet_tool%/*}"
cp -- "$setup_service" "$sandbox/setup-fleet-service-original"
setup_fleet_value() {
  status_row vgs.jarvis setupFleet | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["value"]))'
}
setup_fleet_current() {
  ipc smoke readInstance service vgs.jarvis homeMessage | py_reply 'import json,sys; print(json.load(sys.stdin).get("current","pending"))'
}
setup_fleet_publish() {
  local message
  message="$(ipc smoke readInstance service vgs.jarvis homeMessage)" || return 1
  ipc smoke invokeInstance service vgs.jarvis receive "$message"$'\n'
}
setup_fleet_optional='{"tone": "info", "text": "Optional", "action": true}'
setup_fleet_done='{"tone": "ok", "text": "Done", "action": false}'
expect "select the fleet refresh fixture home" ok ipc smoke invokeInstance window vgs.settings applySetting '{"id":"vgs.jarvis","key":"home","value":"~/Setup Fleet"}'
expect_poll "the daemon accepts the fleet refresh fixture home" '~/Setup Fleet' setup_fleet_current
expect_poll "without the canonical reader fleet setup is optional" "$setup_fleet_optional" setup_fleet_value
expect_poll "the fleet reader is idle before its completion message" idle jarvis_setup_reader_idle FleetRuntime
printf '#!/bin/sh\nexit 99\n' >"$setup_fleet_tool"
chmod 700 -- "$setup_fleet_tool"
expect "the accepted homes completion message reaches the service" '' setup_fleet_publish
expect_poll "homes publication refreshes fleet setup to done" "$setup_fleet_done" setup_fleet_value

rm -- "$setup_fleet_tool"
python3 - "$setup_service" <<'PYHOME'
from pathlib import Path
import sys
p=Path(sys.argv[1])
assert not p.is_symlink()
s=p.read_text()
needle='                    fleetRuntime.refresh();'
assert s.count(needle)==1
changed=s.replace(needle,'                    if (false) fleetRuntime.refresh();')
assert changed != s
p.write_text(changed)
PYHOME
jarvis_rescan
expect_poll "the refresh control accepts its fixture home" '~/Setup Fleet' setup_fleet_current
expect_poll "the refresh control first reads optional" "$setup_fleet_optional" setup_fleet_value
expect_poll "the control fleet reader is idle before its completion message" idle jarvis_setup_reader_idle FleetRuntime
printf '#!/bin/sh\nexit 99\n' >"$setup_fleet_tool"
chmod 700 -- "$setup_fleet_tool"
expect "the refresh control receives the same homes publication" '' setup_fleet_publish
setup_fleet_refresh_control() {
  (failures=0 behaviour_failures=0
   expect_poll "homes publication must replace the previous fleet reading" "$setup_fleet_done" setup_fleet_value
   echo "$failures")
}
expect "dropping the homes refresh breaks the fleet consumer read" 1 local_control_count setup_fleet_refresh_control
cp -- "$sandbox/setup-fleet-service-original" "$setup_service"
jarvis_rescan
expect "restore the previous home after the fleet refresh case" ok ipc smoke invokeInstance window vgs.settings applySetting "$setup_fleet_before"
rm -rf -- "${setup_fleet_home:?}"
# File actions use the shell's selected path even when the daemon refuses
# its contents. Keep this daemon's test home aligned with the shell's scratch
# HOME. The ordinary J09 launcher still owns its isolated children.
jarvis_disable
cp -- "$setup_service" "$sandbox/setup-home-service-original"
setup_home_lease="$sandbox/setup-home-lease.sh"
python3 - "$setup_home_lease" "$home" "$setup_service" "$sandbox/jarvis-world/lease.sh" <<'PYHOME'
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
PYHOME
jarvis_rescan
jarvis_enable
setup_home_dir="$home/Setup file é#%notes"
setup_home_setting='{"id":"vgs.jarvis","key":"home","value":"~/old/../Setup file é#%notes/"}'
expect "select a home whose path needs the canonical resolver" ok ipc smoke invokeInstance window vgs.settings applySetting "$setup_home_setting"
setup_home_path() {
  ipc smoke readInstance service vgs.jarvis homePathRead | py_reply 'import json,sys
r=json.load(sys.stdin)
print(r.get("path","pending") if r.get("kind")=="ready" else "pending")'
}
setup_home_tone() { status_row vgs.jarvis setupHome | py_reply 'import json,sys; print(json.load(sys.stdin)["value"]["tone"])'; }
setup_home_value() {
  status_row vgs.jarvis setupHome | py_reply 'import json,sys
v=json.load(sys.stdin)["value"]
print(json.dumps([v.get("action"),v.get("file")]))'
}
expect_poll "the shared resolver preserves file characters and removes dot segments" "$setup_home_dir" setup_home_path
expect_poll "the new scratch home is ready before the edit case" ok setup_home_tone
setup_readers_idle "before the home file edit"
printf '\377not plain text\n' >"$setup_home_dir/AGENTS.md"
expect "an explicit home judgement refuses the non-text file" '' ipc smoke invokeInstance service vgs.jarvis hello ''
expect_poll "the refused home offers its selected AGENTS file" "$(words agents "$setup_home_dir/AGENTS.md")" setup_home_value
: >"$sandbox/run-hold"
forget_record
expect "Open AGENTS uses the core file action" ok settings_act vgs.jarvis setupHome
expect_poll "the editor receives the refused home's exact file" "$(words vgs.jarvis/edit "$core_vgshell" edit "$setup_home_dir/AGENTS.md")" recorded_tail
printf '# Instructions\nUse plain text.\n' >"$setup_home_dir/AGENTS.md"
rm -f -- "${sandbox:?}/run-hold"
expect_run_end "the shared file editor run ends" vgs.jarvis/edit
expect_poll "editor completion judges the saved home without Talk" ok setup_home_tone
expect_poll "the saved home no longer offers an Open action" '[null, null]' setup_home_value
# A skill-count refusal opens the folder selected by that same resolver.
python3 - "$setup_home_dir/skills/own" <<'PYSKILLS'
from pathlib import Path
import sys
folder=Path(sys.argv[1]); folder.mkdir(parents=True,exist_ok=True)
for index in range(257):
    (folder/('entry-%s.md'%index)).write_text('# Skill\nSynthetic skill.\n')
PYSKILLS
expect "the daemon judges the oversized skill set" '' ipc smoke invokeInstance service vgs.jarvis hello ''
expect_poll "the refused skill set offers the selected skills folder" "$(words skills "$setup_home_dir/skills/")" setup_home_value
expect "restore the earlier home after the file actions" ok ipc smoke invokeInstance window vgs.settings applySetting "$setup_fleet_before"
jarvis_disable
cp -- "$sandbox/setup-home-service-original" "$setup_service"
jarvis_rescan
jarvis_enable
rm -rf -- "${setup_home_dir:?}"
settings_page_close vgs.jarvis
jarvis_disable
rm -f -- "${setup_marker:?}"
printf 'absent\n' >"$sandbox/jarvis-world/local-mode"
dictation_stand_ins off
rm -f -- "${sandbox:?}/voxtype-daemon.log" "${sandbox:?}/voxtype-follow.log"
jarvis_restore_requirements
