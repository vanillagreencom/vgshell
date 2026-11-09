# The Jarvis session row against the real core and shipped helper, with
# the inert package command scripts/fixtures/jarvis/session-package.py.
# Boot and manual starts retain their mode/origin. Refused home choices
# leave the live session's home held for Off. Model/since remain on Setup.
# Controls retain duplicate-start detection, refused-home ownership and
# model/since publication at these existing boundaries.
# No latency ceiling. Reads poll once per nested IPC round trip.
# inputs: shell/plugins/vgs.jarvis/* shell/plugins/vgs.jarvis/backend/* packaging/jarvis-home/* scripts/fixtures/jarvis/session-package.py shell/Core/Plugins.qml shell/plugins/vgs.settings/PluginPage.qml shell/plugins/vgs.settings/Window.qml shell/Commons/PageReference.js shell/Commons/AccountDirectories.js bin/lib/account-folders.js bin/lib/anchored.js bin/lib/qml-library.js shell/Core/PluginStatus.qml scripts/smoke/rows/jarvis.sh shell/plugins/vgs.jarvis/backend/skills/*.md
set -euo pipefail
local jarvis_fixture_tree="" jarvis_fixture_shim="" jarvis_fixture_name="" jarvis_fixture_revision=""
jarvis_fixture_begin
# Retained task observations can notify during the real daemon's session
# checks. Give only this row's J09 lease a recorded command double, never
# a host notify-send or a replacement in the shared command directory.
python3 - "$sandbox/jarvis-world/standins" "$sandbox/jarvis-session-standins" \
  "$jarvis_fixture_tree/shell/plugins/vgs.jarvis/Service.qml" "$smoke_log_dir/jarvis-session-notify.jsonl" <<'PYNOTIFY'
from pathlib import Path
import json,shutil,sys
source,owned,service,record=map(Path,sys.argv[1:])
shutil.copytree(source,owned)
command=owned/"notify-send"
assert not command.exists()
command.write_text("#!/usr/bin/env python3\nimport json,sys\nwith open("+repr(str(record))+", 'a') as out:\n    out.write(json.dumps(sys.argv[1:])+'\\n')\n")
command.chmod(0o700)
assert not service.is_symlink()
text=service.read_text()
needle=json.dumps(str(source))
assert text.count(needle)==1
changed=text.replace(needle,json.dumps(str(owned)))
assert changed!=text
service.write_text(changed)
PYNOTIFY
expected_errors+=("${dictation_absent_errors[@]}")
session_config="$home/.config/vgshell/shell.json"
session_home="$home/SmokeJarvis"
session_account="$home/.claude"
session_package="$session_home/.agents/skills/jarvis"
mkdir -p -- "$session_home"
session_account_made=false
[[ -d $session_account ]] || { mkdir -- "$session_account"; session_account_made=true; }
# The account's id as the Jarvis page saves it.
session_brain="$(python3 -c 'import hashlib,json,sys; print("cli:" + hashlib.sha256(json.dumps(["claude", sys.argv[1]], separators=(",", ":")).encode()).hexdigest()[:32])' "$session_account")"

# The stand-in's answers by verb, as "STATE REASON" words; its calls start over.
session_answers() { # STATUS START STOP
  python3 - "$session_package/scripts" "$session_home" "$session_account" "$@" <<'PY'
import json, os, sys
folder, home, account = sys.argv[1:4]
answers = {}
for verb, words in zip(["status", "start", "stop"], sys.argv[4:]):
    state, reason = words.split()
    answers[verb] = {"exit": 0, "object": {"state": state, "reason": reason, "home": home, "harness": "claude", "account": account}}
json.dump(answers, open(os.path.join(folder, "answers.json"), "w"))
if os.path.exists(os.path.join(folder, "calls.log")):
    os.unlink(os.path.join(folder, "calls.log"))
PY
}
session_calls() { # VERB
  python3 - "$session_package/scripts/calls.log" "$1" <<'PY'
import json, os, sys
lines = open(sys.argv[1]).read().splitlines() if os.path.exists(sys.argv[1]) else []
try:
    print(json.dumps([row["argv"] for row in map(json.loads, lines) if row["argv"][0] == sys.argv[2]]))
except ValueError:
    print("partial")
PY
}
session_start_words() { # MODE ORIGIN...
  python3 -c 'import json,sys; print(json.dumps([["start", "--harness", "claude", "--account", sys.argv[1], "--mode", sys.argv[3], "--origin", origin, "--home", sys.argv[2]] for origin in sys.argv[4:]]))' \
    "$session_account" "$session_home" "$@"
}
session_row() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
value=json.load(sys.stdin)["status"].get("sessionStart")
print(json.dumps([value["text"], value.get("hint", "")]) if isinstance(value, dict) and "text" in value else "pending")
'
}
session_text() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
value=json.load(sys.stdin)["status"].get("sessionStart")
print(value["text"] if isinstance(value, dict) and "text" in value else "pending")
'
}
session_modes() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
print(json.dumps([choice["value"] for choice in json.load(sys.stdin)["status"].get("sessionModes") or []]))
'
}
session_lines() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
value=json.load(sys.stdin)["status"].get("sessionStart")
print(json.dumps(value.get("lines", [])) if isinstance(value, dict) and "text" in value else "pending")
'
}
# ENTRY follows the fixture's contract. Each returned object names this home.
session_answer() { # VERB ENTRY
  python3 - "$session_package/scripts" "$session_home" "$session_account" "$1" "$2" <<'PY'
import json, os, sys
folder, home, account, verb, entry = sys.argv[1:6]
path = os.path.join(folder, "answers.json")
answers = json.load(open(path))
entry = json.loads(entry)
for one in [entry] + list(entry.get("then", {}).values()):
    if "object" in one:
        one["object"] = {"home": home, "harness": "claude", "account": account, **one["object"]}
answers[verb] = entry
with open(path + ".row", "w") as out:
    json.dump(answers, out)
os.replace(path + ".row", path)
PY
}
session_tmux() {
  local listed
  listed="$(env -u TMUX -u TMUX_PANE TMUX_TMPDIR="$rt_dir" tmux list-sessions -F '#{session_name}' 2>/dev/null)" || listed=""
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1].split()))' "$listed"
}
session_set() { # VALUES
  user_config_write python3 - "$session_config" "$1" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1]); value = json.loads(path.read_text())
row = next((r for r in value.setdefault("plugins", []) if r["id"] == "vgs.jarvis"), None)
if row is None:
    row = {"id": "vgs.jarvis"}; value["plugins"].append(row)
for key, setting in json.loads(sys.argv[2]).items():
    if setting is None: row.pop(key, None)
    else: row[key] = setting
print(json.dumps(value))
PY
}
session_shell_start() { # TREE NAME
  row_log_read "$smoke_row_name: fixture shell log" "$instance_log"
  stop_shell || :
  devices_private_shim=""
  start_shell "$1" "$sandbox/jarvis-session-$2.log" bar PATH="$1.commands:$shim:$shell_host_path"
  jarvis_enable
}

jarvis_setup_requirements "$jarvis_fixture_shim"
session_set "$(python3 -c 'import json,sys; print(json.dumps({"brain": sys.argv[1], "home": "~/SmokeJarvis"}))' "$session_brain")"
session_shell_start "$jarvis_fixture_tree" no-package
expect_poll "the home VGS laid out reads that it offers no session" \
  '["Not offered in this home folder", "VGS made this Home folder without the Jarvis session program. Voice Jarvis works without it. [Choose a Kendex Jarvis home](page:vgs.jarvis/Settings/home)."]' session_row

mkdir -p -- "$session_package/scripts"
cp -- "$source_repo/scripts/fixtures/jarvis/session-package.py" "$session_package/scripts/jarvis-session"
chmod 755 "$session_package/scripts/jarvis-session"
session_answers "stopped never-started" "running existing" "stopping stop-requested"
session_shell_start "$jarvis_fixture_tree" off
expect_poll "with the setting off the row reads not started" "Not started" session_text
expect "with the setting off the page is offered no session choice" '[]' session_modes
expect "with the setting off a shell start asks for no start" '[]' session_calls start

session_fault_target="$(python3 -c 'import re,sys; print(re.search(r"^var SESSION_FAULT = \"\[[^]]*\]\(page:([^)]*)\)\";$", open(sys.argv[1]).read(), re.M).group(1))' \
  "$repo/shell/plugins/vgs.jarvis/SetupGate.js")" || session_fault_target=unread
expect "the session fault names the session row on Setup" vgs.jarvis/Setup/sessionStart echo "$session_fault_target"
session_unread_hint="The Jarvis session program did not answer as expected. Try again."
session_revealed() {
  ipc smoke itemValues window vgs.settings PluginPage revealedRow.statusKey | py_reply '
import json,sys
rows=json.load(sys.stdin)
print(json.dumps(rows[0].get("revealedRow.statusKey")) if len(rows) == 1 else "pages=%d" % len(rows))
'
}
session_in_view() { # HINT
  local box view
  box="$(ipc smoke windowGeometry window vgs.settings QQuickText "$1")" || return 1
  view="$(ipc smoke viewHolding window vgs.settings "$1")" || return 1
  python3 -c '
import json,sys
try: box, view = json.loads(sys.argv[1]), json.loads(sys.argv[2])["box"]
except (ValueError, KeyError, TypeError): print("unread"); sys.exit()
print(str(box[1] >= view[1] and box[1] + box[3] <= view[1] + view[3]).lower())' "$box" "$view"
}
session_answer status '{"exit": 2, "raw": ""}'
expected_errors+=('WARN qml: jarvis-session: status=blocked block=unread cause=jarvis: session-status=exit=2$')
expect "the session fault's reference opens the Jarvis page" ok ipc shell summon window vgs.settings \
  "$(python3 -c 'import json,sys; page, tab = sys.argv[1].split("/", 1); print(json.dumps({"plugin": page, "tab": tab}))' "$session_fault_target")"
expect_poll "a status outside the contract reads its own cause" "$(python3 -c 'import json,sys; print(json.dumps(["Cannot start", sys.argv[1]]))' "$session_unread_hint")" session_row
expect_poll "the reference opens Setup" Setup settings_tab_text
expect_poll "the reference marks the session row" '"sessionStart"' session_revealed
expect_poll "the marked session row lies in view" true session_in_view "$session_unread_hint"
settings_page_close vgs.jarvis
session_answer status '{"exit": 0, "object": {"state": "stopped", "reason": "never-started"}}'
expect "the Jarvis page opens again on Setup" ok ipc shell summon window vgs.settings '{"plugin": "vgs.jarvis", "tab": "Setup"}'
expect_poll "viewed again, the row reads not started" "Not started" session_text
settings_page_close vgs.jarvis

session_set '{"startAtBoot": true}'
expect "the configuration reloads with the setting on" ok ipc shell reloadConfig
expect_poll "turned on in a running shell, the row reads the next boot" "Starts at the next boot" session_text
expect "the page is offered both session choices" '["resume", "new"]' session_modes
expect "turning the setting on asks for no start" '[]' session_calls start

session_answers "running existing" "running existing" "stopping stop-requested"
session_shell_start "$jarvis_fixture_tree" first
expect_poll "a shell start with the setting on asks the package for one boot start" "$(session_start_words resume boot)" session_calls start
expect_poll "the row reads the session the package answers" Running session_text
expect "a session the package names no model or start time for shows neither" '[]' session_lines
session_shell_start "$jarvis_fixture_tree" second
expect_poll "a second shell start asks the package again" "$(session_start_words resume boot boot)" session_calls start
expect_poll "the row reads running after the second start" Running session_text
expect "VGS itself starts no session" '[]' session_tmux

jarvis_fixture_copy jarvis-session-twice "$jarvis_fixture_tree" "$jarvis_fixture_shim"
if edit_tree jarvis-session-twice shell/plugins/vgs.jarvis/backend/session-control.js \
    '        if (started === null) return failed;' \
    '        await run(at, ["start", "--harness", who.harness, "--account", who.directory, "--mode", mode, "--origin", origin]);
        if (started === null) return failed;'; then
  session_answers "running existing" "running existing" "stopping stop-requested"
  session_shell_start "$sandbox/tree-jarvis-session-twice" twice
  expect_poll "control: a helper that asks twice reads two starts for one shell start" "$(session_start_words resume boot boot)" session_calls start
fi

session_answers "stopped ended" "running new-requested" "stopping stop-requested"
session_set '{"bootSession": "new", "startAtBoot": false}'
session_shell_start "$jarvis_fixture_tree" manual
expect_poll "with the setting off again the shell start only reads" "Not started" session_text
expect "the Start step is taken" ok ipc vgs.jarvis invoke start-session ''
expect_poll "the Start step asks the package for a manual start in the chosen mode" "$(session_start_words new manual)" session_calls start

session_held() {
  ipc smoke itemValues service vgs.jarvis SessionStart sessionHome,unapplied | py_reply '
import json,sys
rows=json.load(sys.stdin)
print(json.dumps([rows[0]["sessionHome"], rows[0]["unapplied"]]) if len(rows) == 1 else "pending")
'
}
session_refuse() { # LABEL
  session_set '{"home": null}'
  expect "$1: the configuration reloads with no home folder" ok ipc shell reloadConfig
}
jarvis_fixture_copy jarvis-session-follows "$jarvis_fixture_tree" "$jarvis_fixture_shim"
if edit_tree jarvis-session-follows shell/plugins/vgs.jarvis/SessionStart.qml \
    '        if (answer.kind === "answer" && answer.unapplied !== undefined) unapplied = answer.unapplied;' \
    '        if (answer.kind === "answer" && answer.unapplied !== undefined) { unapplied = answer.unapplied; sessionHome = current.home; }'; then
  session_answers "running existing" "running existing" "stopping stop-requested"
  session_shell_start "$sandbox/tree-jarvis-session-follows" follows
  expect_poll "control: the copy reads the running session" '["~/SmokeJarvis", ""]' session_held
  session_refuse control
  expect_poll "control: a service that follows a refused selection holds the new home" '["", "no-home"]' session_held
  session_set '{"home": "~/SmokeJarvis"}'
fi

session_model="claude-opus-4-1"
session_since="2026-10-17T18:02:00Z"
session_named="$("${shell_env[@]}" python3 -c 'import datetime,json,sys; at=datetime.datetime.fromisoformat(sys.argv[2].replace("Z", "+00:00")).astimezone(); print(json.dumps(["Model: " + sys.argv[1], "Running since " + at.strftime("%H:%M")]))' "$session_model" "$session_since")" \
  || fail "the shell's local start time is unreadable"
session_live_named() {
  session_answers "running existing" "running existing" "stopping stop-requested"
  session_answer status "$(python3 -c 'import json,sys; print(json.dumps({"exit": 0, "object": {"state": "running", "reason": "existing", "model": sys.argv[1], "since": sys.argv[2]}}))' "$session_model" "$session_since")"
}
session_live_named
session_shell_start "$jarvis_fixture_tree" named
expect_poll "a live session's model and start time show on the row" "$session_named" session_lines
jarvis_fixture_copy jarvis-session-unnamed "$jarvis_fixture_tree" "$jarvis_fixture_shim"
if edit_tree jarvis-session-unnamed shell/plugins/vgs.jarvis/backend/session-control.js \
    '...Object.fromEntries(["model", "since"]' '...Object.fromEntries([]'; then
  session_live_named
  session_shell_start "$sandbox/tree-jarvis-session-unnamed" unnamed
  expect_poll "control: the copy reads the running session" Running session_text
  expect "control: a helper that drops the model and start time shows neither" '[]' session_lines
fi

session_set '{"startAtBoot": true, "bootSession": "new"}'
session_answers "stopped ended" "running new-requested" "stopping stop-requested"
session_answer start '{"exit": 0, "object": {"state": "starting", "reason": "launching"}, "then": {"status": {"exit": 0, "object": {"state": "running", "reason": "new-requested"}}}}'
session_shell_start "$jarvis_fixture_tree" boot-new
expect_poll "with Start a new session a shell start asks for one boot start" "$(session_start_words new boot)" session_calls start
expect_poll "the new boot session runs" Running session_text
session_set '{"startAtBoot": false, "bootSession": "new"}'

session_answers "running existing" "running existing" "stopping stop-requested"
session_shell_start "$jarvis_fixture_tree" restart
expect_poll "the restarted shell reads the running session" Running session_text
expect "a shell restart asks for no stop" '[]' session_calls stop
session_refuse "a refused selection"
expect_poll "a refused home selection leaves the live session's home held" '["~/SmokeJarvis", "no-home"]' session_held
expect "the row still reads the session that runs" Running session_text
expect "a refused selection asks for no stop" '[]' session_calls stop
expect "disabling Jarvis is accepted" ok ipc shell setPluginEnabled vgs.jarvis false
expect_poll "disabling Jarvis asks for one stop, with the app's Off, in the home the session lives in" \
  "$(python3 -c 'import json,sys; print(json.dumps([["stop", "--origin", "app-off", "--home", sys.argv[1]]]))' "$session_home")" session_calls stop

session_set '{"startAtBoot": null, "bootSession": null, "brain": null, "home": null}'
expect "the configuration reloads with the manifest's settings" ok ipc shell reloadConfig
rm -f -- "${session_package:?}/scripts/jarvis-session" "${session_package:?}/scripts/answers.json" "${session_package:?}/scripts/calls.log"
rmdir -- "$session_package/scripts"
[[ $session_account_made == false ]] || rmdir -- "$session_account"
jarvis_restore_requirements "$jarvis_fixture_shim"
row_log_read "$smoke_row_name: fixture shell log" "$instance_log"
stop_shell
devices_private_shim=""
start_shell "$repo" "$smoke_log_dir/jarvis-session-stock.log"
