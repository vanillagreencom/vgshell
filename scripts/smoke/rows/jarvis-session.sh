# The Jarvis session row against the real core and the shipped helper,
# with a stand-in for the Jarvis package's `jarvis-session` in the home
# folder (scripts/fixtures/jarvis/session-package.py): it records each call
# and answers what the row wrote beside it, and starts nothing, so no
# session and no tmux server exists at any point. In a home without the
# command the row reads that no session can start and names the package.
# With Start Jarvis at boot off a shell start reads the session and asks
# for no start. Turned on in a running shell, the row reads that the next
# boot starts it, the session choices are offered and still no start is
# asked. Each shell start then asks the package for one boot start, in the
# home, for the account's app, and a second shell start asks again and VGS
# starts nothing itself. The Start step asks for a manual start. Disabling
# Jarvis asks for one stop with the app's Off, and a shell restart asks for
# none. A home selection that fails its check, None here, leaves the live
# session's home as the one the service holds, and the Off then stops the
# session there. A live session's model and start time show on the row,
# and a session the package gives neither for shows no line for them.
# The machine's Reboot and Shut down: systemctl is the row's stand-in over
# the harness's, which records each call's argv and time and restarts
# nothing. With no live session Jarvis answers `proceed` and the launcher's
# Reboot, its menu line run through the stand-ins, runs systemctl at once.
# With a live session it answers `held`: the shipped helper asks the
# package for one `prepare` in the session's home and runs systemctl once,
# after the saved answer, while the wait's card shows; a second Reboot
# runs systemctl at once, and so does the card's Shut down now while the
# session has not answered. In a copy whose helper bound is 2 s, a prepare
# that holds 10 s still reaches systemctl before it answers. A record the
# package saved before a machine restart offers its resume on the row and
# the bar widget while Start Jarvis at boot is off; Resume asks for one
# manual resume, the offer then ends, the row reads the resume and the
# widget each step's outcome and the failed step's cause, and a second
# Resume is refused. Do not resume hides the offer and asks for nothing.
# With Start Jarvis at boot on and Resume the last session, a shell start
# asks for one boot resume and no start. Controls: a tree whose helper
# asks twice reads two starts for one shell start, a tree whose service
# follows a refused selection holds the new home, a tree whose helper
# drops the model and start time shows neither, a tree whose power helper
# has no bound runs systemctl only after the hung prepare answers, and a
# tree whose Resume asks twice reads two resumes.
# No latency ceiling. Reads poll once per nested IPC round trip.
# The home's Jarvis package is the copy VGS writes there; the row adds only
# the stand-in command beside it.
# inputs: shell/plugins/vgs.jarvis/* shell/plugins/vgs.jarvis/backend/* packaging/jarvis-home/* scripts/fixtures/jarvis/session-package.py shell/Core/Plugins.qml shell/Commons/AccountDirectories.js bin/lib/account-folders.js bin/lib/anchored.js bin/lib/qml-library.js shell/Core/PluginStatus.qml scripts/smoke/rows/jarvis.sh shell/plugins/vgs.launcher/menu.json shell/Core/Layers.qml shell/Hosts/LayerHost.qml shell/Ui/overlay/Tooltip.qml shell/Ui/controls/BarItem.qml
set -euo pipefail
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
# The argv of each call of VERB the stand-in took, as a JSON list.
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
# The row as [text, hint], or pending before the service's first answer.
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
# The row's extra lines, [] for none, or pending before the first answer.
session_lines() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
value=json.load(sys.stdin)["status"].get("sessionStart")
print(json.dumps(value.get("lines", [])) if isinstance(value, dict) and "text" in value else "pending")
'
}
# The bar widget's reading of the session's Resume offer: null for none,
# or pending before the service published one.
session_offer() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
value=json.load(sys.stdin)["status"].get("jarvisSession")
print("pending" if value is None else json.dumps(value["offer"]))
'
}
session_tip() { ipc smoke readDescendant "$(bar_key)" vgs.jarvis Tooltip text; }
# The bar widget's tooltip lines that name a resume step.
session_steps() {
  ipc smoke readDescendant "$(bar_key)" vgs.jarvis Tooltip details | py_reply '
import json,sys
print(json.dumps([line for line in json.load(sys.stdin) if line.startswith(("Resumed ", "Could not resume ", "Waiting to resume "))]))
'
}
# VERB's calls as session_calls prints them, once two status reads follow
# the last of them, so a call a service queues behind it has been taken;
# pending before. The step reads of a resume with a pending step come
# every 2 s (SessionStart.qml stepPollMs).
session_calls_settled() { # VERB
  python3 - "$session_package/scripts/calls.log" "$1" <<'PY'
import json, os, sys
lines = open(sys.argv[1]).read().splitlines() if os.path.exists(sys.argv[1]) else []
try:
    argvs = [json.loads(line)["argv"] for line in lines]
except ValueError:
    print("partial"); sys.exit()
asked = [i for i, argv in enumerate(argvs) if argv[0] == sys.argv[2]]
reads = [argv for argv in argvs[asked[-1]:] if argv[0] == "status"] if asked else []
print(json.dumps([argvs[i] for i in asked]) if len(reads) >= 2 else "pending")
PY
}
# The stand-in's entry for VERB set to ENTRY, a JSON object in the form its
# header gives; the object of the entry and of each entry under its `then`
# names the row's home, harness and account. The calls stay.
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
# VALUES, a JSON object, written over Jarvis's settings; null removes a key.
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
  stop_shell || :
  start_shell "$1" "$sandbox/jarvis-session-$2.log"
  jarvis_enable
}

jarvis_setup_requirements
session_set "$(python3 -c 'import json,sys; print(json.dumps({"brain": sys.argv[1], "home": "~/SmokeJarvis"}))' "$session_brain")"
session_shell_start "$repo" no-package
expect_poll "a home without the package's command reads that no session can start" \
  '["Cannot start", "Install or update the Jarvis package in this home folder"]' session_row

mkdir -p -- "$session_package/scripts"
cp -- "$source_repo/scripts/fixtures/jarvis/session-package.py" "$session_package/scripts/jarvis-session"
chmod 755 "$session_package/scripts/jarvis-session"
session_answers "stopped never-started" "running existing" "stopping stop-requested"
session_shell_start "$repo" off
expect_poll "with the setting off the row reads not started" "Not started" session_text
expect "with the setting off the page is offered no session choice" '[]' session_modes
expect "with the setting off a shell start asks for no start" '[]' session_calls start

session_set '{"startAtBoot": true}'
expect "the configuration reloads with the setting on" ok ipc shell reloadConfig
expect_poll "turned on in a running shell, the row reads the next boot" "Starts at the next boot" session_text
expect "the page is offered both session choices" '["resume", "new"]' session_modes
expect "turning the setting on asks for no start" '[]' session_calls start

session_answers "running existing" "running existing" "stopping stop-requested"
session_shell_start "$repo" first
expect_poll "a shell start with the setting on asks the package for one boot start" "$(session_start_words resume boot)" session_calls start
expect_poll "the row reads the session the package answers" Running session_text
expect "a session the package names no model or start time for shows neither" '[]' session_lines
session_shell_start "$repo" second
expect_poll "a second shell start asks the package again" "$(session_start_words resume boot boot)" session_calls start
expect_poll "the row reads running after the second start" Running session_text
expect "VGS itself starts no session" '[]' session_tmux

copy_tree jarvis-session-twice
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
session_shell_start "$repo" manual
expect_poll "with the setting off again the shell start only reads" "Not started" session_text
expect "the Start step is taken" ok ipc vgs.jarvis invoke start-session ''
expect_poll "the Start step asks the package for a manual start in the chosen mode" "$(session_start_words new manual)" session_calls start

# The home the service holds for the session, and the block of a selection
# that failed its check, as [home, block].
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
copy_tree jarvis-session-follows
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

# A live session's model and start time. The start time shows as the
# shell's local clock, which the shell's environment sets.
session_model="claude-opus-4-1"
session_since="2026-10-17T18:02:00Z"
session_named="$("${shell_env[@]}" python3 -c 'import datetime,json,sys; at=datetime.datetime.fromisoformat(sys.argv[2].replace("Z", "+00:00")).astimezone(); print(json.dumps(["Model: " + sys.argv[1], "Running since " + at.strftime("%H:%M")]))' "$session_model" "$session_since")" \
  || fail "the shell's local start time is unreadable"
session_live_named() {
  session_answers "running existing" "running existing" "stopping stop-requested"
  session_answer status "$(python3 -c 'import json,sys; print(json.dumps({"exit": 0, "object": {"state": "running", "reason": "existing", "model": sys.argv[1], "since": sys.argv[2]}}))' "$session_model" "$session_since")"
}
session_live_named
session_shell_start "$repo" named
expect_poll "a live session's model and start time show on the row" "$session_named" session_lines
copy_tree jarvis-session-unnamed
if edit_tree jarvis-session-unnamed shell/plugins/vgs.jarvis/backend/session-control.js \
    '...Object.fromEntries(["model", "since", "restart"]' '...Object.fromEntries(["restart"]'; then
  session_live_named
  session_shell_start "$sandbox/tree-jarvis-session-unnamed" unnamed
  expect_poll "control: the copy reads the running session" Running session_text
  expect "control: a helper that drops the model and start time shows neither" '[]' session_lines
fi

# The machine's Reboot and Shut down. The row's systemctl stands over the
# harness's and records each call's argv and time; sentinel_restore puts
# the harness's back once every helper has asked for its last one.
session_systemctl_log="$sandbox/jarvis-session-systemctl.calls"
session_bin="$sandbox/jarvis-session-bin"
mkdir -p -- "$session_bin"
ln -sfn -- "$repo/bin/vgshell" "$session_bin/vgshell"
sentinel_stand_over "$shim/systemctl" <<EOF
#!/usr/bin/env bash
exec $(printf %q "$(command -v python3)") -c 'import json,sys,time; open(sys.argv[1], "a").write(json.dumps({"argv": sys.argv[2:], "time": time.time()}) + "\n")' $(printf %q "$session_systemctl_log") "\$@"
EOF
# The systemctl argv lists recorded, as one JSON list.
session_systemctl() {
  python3 - "$session_systemctl_log" <<'PY'
import json, os, sys
lines = open(sys.argv[1]).read().splitlines() if os.path.exists(sys.argv[1]) else []
try:
    print(json.dumps([json.loads(line)["argv"] for line in lines]))
except ValueError:
    print("partial")
PY
}
# When the first systemctl call since the stand-in's last prepare came:
# before-answer while that prepare still held its answer, after-answer once
# it had answered; absent with no call since, no-prepare with no prepare.
session_power_when() {
  python3 - "$session_package/scripts" "$session_systemctl_log" <<'PY'
import json, os, sys
folder, log = sys.argv[1:]
def rows(path):
    return [json.loads(line) for line in open(path).read().splitlines()] if os.path.exists(path) else []
try:
    prepares = [row for row in rows(os.path.join(folder, "calls.log")) if row["argv"][0] == "prepare"]
    powers = rows(log)
except ValueError:
    print("partial"); sys.exit()
if not prepares:
    print("no-prepare"); sys.exit()
asked = prepares[-1]["time"]
hold = json.load(open(os.path.join(folder, "answers.json")))["prepare"].get("hold", 0)
since = [row["time"] for row in powers if row["time"] >= asked]
print("absent" if not since else "after-answer" if since[0] >= asked + hold else "before-answer")
PY
}
# The wait's card: shown while a copy draws it, hidden while every copy is
# hidden, none with no card layer.
session_card() {
  ipc smoke layerItems vgs.jarvis PowerCard shown | py_reply '
import json,sys
rows=json.load(sys.stdin)
print("none" if not rows else "shown" if any(row[2]["shown"] for row in rows) else "hidden")
'
}
# The launcher's System menu ITEM, its argv run as menu.json gives it, with
# the row's stand-ins first on its PATH and the tree's vgshell as vgshell.
session_path="$session_bin:$shell_start_path"
session_resolves() { "${shell_env[@]}" PATH="$session_path" bash -c 'command -v -- "$1"' _ "$1"; }
session_menu() { # ITEM
  local words
  local -a run
  words="$(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["items"][sys.argv[2]]["run"]))' "$repo/shell/plugins/vgs.launcher/menu.json" "$1")" || return
  mapfile -t run <<<"$words"
  "${shell_env[@]}" PATH="$session_path" "${run[@]}"
}
session_prepare_words() { # FOR
  python3 -c 'import json,sys; print(json.dumps([["prepare", "--for", sys.argv[1], "--home", sys.argv[2]]]))' "$1" "$session_home"
}
# A live session whose prepare answers after HOLD seconds; the calls and
# systemctl's record start over.
session_live_holding() { # HOLD
  session_answers "running existing" "running existing" "stopping stop-requested"
  session_answer prepare "{\"exit\": 0, \"hold\": $1, \"object\": {\"state\": \"running\", \"reason\": \"existing\", \"saved\": true}}"
  rm -f -- "$session_systemctl_log"
}

if [[ $(session_resolves systemctl) == "$shim/systemctl" && $(session_resolves vgshell) == "$session_bin/vgshell" \
    && $(shell_resolves systemctl) == "$shim/systemctl" ]]; then
  session_answers "stopped ended" "running existing" "stopping stop-requested"
  rm -f -- "$session_systemctl_log"
  session_shell_start "$repo" power-none
  expect_poll "with no live session the row reads not started" "Not started" session_text
  expect "with no live session Jarvis lets a reboot proceed" proceed ipc vgs.jarvis invoke power reboot
  expect "the launcher's Reboot runs with no live session" "" session_menu system.reboot
  expect "the launcher's Reboot with no live session runs systemctl reboot at once" '[["reboot"]]' session_systemctl
  expect "with no live session nothing asks the package to save" '[]' session_calls prepare

  session_live_holding 1
  session_shell_start "$repo" power
  expect_poll "the power wait reads the live session" Running session_text
  expect "the launcher's Reboot runs while a session lives" "" session_menu system.reboot
  expect_poll "the wait's card shows while the reboot waits" shown session_card
  expect_poll "the reboot asks the package once to save the session for a restart, in its home" "$(session_prepare_words restart)" session_calls prepare
  expect_poll "systemctl reboot runs after the session's saved answer" after-answer session_power_when
  expect "the held reboot runs systemctl once" '[["reboot"]]' session_systemctl
  expect "a second Reboot while the wait shows runs" "" session_menu system.reboot
  expect "the second Reboot runs systemctl reboot at once" '[["reboot"], ["reboot"]]' session_systemctl
  expect_poll "the second Reboot ends the wait's card" none session_card

  session_live_holding 15
  expect "Shut down while a session lives is held" held ipc vgs.jarvis invoke power poweroff
  expect_poll "the shutdown asks the package once to save the session for a shutdown" "$(session_prepare_words shutdown)" session_calls prepare
  expect_poll "the wait's card shows while the shutdown waits" shown session_card
  if click_item vgs:layer vgs.jarvis Button text "Shut down now"; then
    expect_poll "the card's Shut down now runs systemctl poweroff before the session answers" before-answer session_power_when
    expect_poll "Shut down now ends the wait's card" none session_card
  else
    fail "the click on the card's Shut down now failed"
  fi
  expect_poll "the helper still asks for the shutdown once the session answers" '[["poweroff"], ["poweroff"]]' session_systemctl

  copy_tree jarvis-power-bound
  if edit_tree jarvis-power-bound shell/plugins/vgs.jarvis/backend/power-wait.js 'const PREPARE_MS = 60000;' 'const PREPARE_MS = 2000;'; then
    session_live_holding 10
    session_shell_start "$sandbox/tree-jarvis-power-bound" power-bound
    expect_poll "the copy with a 2 s bound reads the live session" Running session_text
    expect "a reboot in the copy is held" held ipc vgs.jarvis invoke power reboot
    expect_poll "a prepare that holds past the bound still reaches systemctl reboot before it answers" before-answer session_power_when
    expect "the bound runs systemctl once" '[["reboot"]]' session_systemctl
  fi
  copy_tree jarvis-power-unbound
  if edit_tree jarvis-power-unbound shell/plugins/vgs.jarvis/backend/power-wait.js \
      '        const bound = setTimeout(() => {
            prepare.kill("SIGKILL");
            power("bound");
        }, PREPARE_MS);' '        const bound = null;'; then
    session_live_holding 10
    session_shell_start "$sandbox/tree-jarvis-power-unbound" power-unbound
    expect_poll "control: the copy reads the live session" Running session_text
    expect "control: a reboot in the copy is held" held ipc vgs.jarvis invoke power reboot
    expect_poll "control: a helper with no bound runs systemctl reboot only after the hung prepare answers" after-answer session_power_when
  fi
else
  fail "systemctl or vgshell does not resolve to the row's stand-in, so no power action was asked"
fi
sentinel_restore "$shim/systemctl"
rm -rf -- "${session_bin:?}" "$session_systemctl_log"

# A record saved before a machine restart: each step pending, then, once
# the package's resume starts, the session resumed, overseer vgshell
# failed with its cause and lane VGS-1797 still pending. The calls start
# over.
session_offer_answers() {
  local step='{"kind": "%s", "name": "%s", "outcome": "%s", "cause": %s}'
  local pending resumed
  pending="{\"unlock\": null, \"steps\": [$(printf "$step, $step, $step" delegate jarvis pending null overseer vgshell pending null lane VGS-1797 pending null)]}"
  resumed="{\"unlock\": null, \"steps\": [$(printf "$step, $step, $step" delegate jarvis resumed null overseer vgshell failed '"settings-busy"' lane VGS-1797 pending null)]}"
  session_answers "stopped ended" "running existing" "stopping stop-requested"
  session_answer status "{\"exit\": 0, \"object\": {\"state\": \"stopped\", \"reason\": \"ended\", \"restart\": $pending}}"
  session_answer resume "{\"exit\": 0, \"object\": {\"state\": \"starting\", \"reason\": \"resuming\"}, \"then\": {\"status\": {\"exit\": 0, \"object\": {\"state\": \"starting\", \"reason\": \"resuming\", \"restart\": $resumed}}}}"
}
session_resume_words() { # ORIGIN...
  python3 -c 'import json,sys; print(json.dumps([["resume", "--origin", origin, "--home", sys.argv[1]] for origin in sys.argv[2:]]))' "$session_home" "$@"
}
session_offer_answers
session_shell_start "$repo" offer
expect_poll "a record saved before the restart offers its resume on the row" '["Saved before the restart", "Resume Jarvis from before the restart"]' session_row
expect_poll "the bar widget offers the resume" '"Resume Jarvis from before the restart"' session_tip
expect "the offer asks for no resume" '[]' session_calls resume
expect "Resume is taken" ok ipc vgs.jarvis invoke resume-session ''
expect_poll "Resume asks the package for one manual resume, in the session's home" "$(session_resume_words manual)" session_calls_settled resume
expect_poll "the offer ends once the resume starts" null session_offer
expect_poll "the row reads the resume" Resuming session_text
expect_poll "the widget shows each step's outcome and the failed step's cause" \
  '["Resumed the Jarvis session.", "Could not resume overseer vgshell: settings-busy.", "Waiting to resume lane VGS-1797."]' session_steps
expect "a second Resume is refused" "refused: resume=not-offered" ipc vgs.jarvis invoke resume-session ''
expect "the refused Resume asks for no resume" "$(session_resume_words manual)" session_calls resume

session_offer_answers
session_shell_start "$repo" dismiss
expect_poll "a new shell offers the record's resume" '{"unlock": null}' session_offer
expect "Do not resume is taken" ok ipc vgs.jarvis invoke dismiss-resume ''
expect_poll "Do not resume hides the offer" null session_offer
expect_poll "the row no longer offers the resume" "Not started" session_text
expect "Do not resume asks for no resume" '[]' session_calls resume

copy_tree jarvis-session-resume-twice
if edit_tree jarvis-session-resume-twice shell/plugins/vgs.jarvis/SessionStart.qml \
    '        call("resume", sessionHome, [sessionHome]);' \
    '        call("resume", sessionHome, [sessionHome]);
        call("resume", sessionHome, [sessionHome]);'; then
  session_offer_answers
  session_shell_start "$sandbox/tree-jarvis-session-resume-twice" resume-twice
  expect_poll "control: the copy offers the record's resume" '{"unlock": null}' session_offer
  expect "control: Resume is taken" ok ipc vgs.jarvis invoke resume-session ''
  expect_poll "control: a service whose Resume asks twice reads two resumes" "$(session_resume_words manual manual)" session_calls_settled resume
fi

session_set '{"startAtBoot": true, "bootSession": null}'
session_offer_answers
session_shell_start "$repo" boot-resume
expect_poll "with Start Jarvis at boot on a shell start asks for one boot resume" "$(session_resume_words boot)" session_calls_settled resume
expect "the boot resume asks for no start" '[]' session_calls start
expect "a record resumed at boot offers nothing" null session_offer
session_set '{"startAtBoot": false, "bootSession": "new"}'

session_answers "running existing" "running existing" "stopping stop-requested"
session_shell_start "$repo" restart
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
jarvis_restore_requirements
