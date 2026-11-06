# vgs.agent-debug, shell/plugins/vgs.agent-debug/README.md. The service
# follows the journal for the core dumps of the user's programs once an
# agent is chosen, reads the core's failed setup tasks through capability
# `doctor`, and sends each new one as one notification with Diagnose.
# Nothing here crashes a program or reads the host journal: a stand-in
# journalctl in the shell's own PATH directory records its argv and pid,
# empties $ad_journal and follows it with `exec tail`, so the follower's pid
# is tail's, and a crash is one line in journalctl's `-o json` shape the row
# appends there. A stand-in notify-send records each argv and prints the
# action $ad_press names, as notify-send prints the action pressed. claude
# and codex are stand-ins the scan finds; neither runs. A failed task is
# acme.needs' requirement install, which the stand-in terminal ends with
# code 1 while $ad_fail exists, after a stand-in bin/vgshell-pkg answers
# detection with pacman.
# Rows: with no agent chosen no process starts and nothing notifies; the
# follower's argv; one notification per program inside the minute, a second
# program its own; a failed task notifies once, its Diagnose names the run's
# ended record, a shell restart tells the kept failure again never, and the
# next failed run once; the follower's own pid never notifies, another pid
# with its name does; Mute and the IPC mute silence a program, and unmute
# brings it back; Diagnose hands the terminal the diagnose TUI with every
# fact as its own argument, a name holding a quote and `$(` included, in
# the agent chosen at the press; a disable leaves no follower, and a
# follower that ends reads Stopped until the agent changes. Each check is paired with
# the control that reads its other side. A line the row expects to be
# skipped is followed by a marker crash, and the check reads once the
# marker's notification is recorded, since the follower reads lines in
# order.
# The harness starts the plugin disabled; the row enables it with no agent
# and ends with it disabled, its stand-ins gone and the failure it planted
# cleared.
# Jarvis handoff uses the actual notification callback, offer, and Console
# composer, with only the offline scripted daemon. It checks exact scalar
# text, no conversation, occupied text, saved unavailable selection and
# explicit one-off recovery. The altered-builder control edits only the
# world's disposable plugin copy and must fail the exact-text assertion.
# No latency ceiling; state polling is once per nested IPC round trip.
# inputs: shell/plugins/vgs.agent-debug/manifest.json shell/plugins/vgs.agent-debug/Service.qml shell/plugins/vgs.agent-debug/Debug.js shell/plugins/vgs.agent-debug/Diagnose.js shell/plugins/vgs.agent-debug/Recovery.qml shell/Core/Capabilities.qml shell/Core/HandoffRegistry.qml shell/Core/Notices.qml shell/plugins/vgs.jarvis/* packaging/jarvis-home/* scripts/fixtures/jarvis/* scripts/smoke/jarvis-console.sh scripts/smoke/rows/jarvis.sh scripts/smoke/fixtures/plugins/acme.needs/* scripts/smoke/fixtures/plugins/acme.probe/* bin/vgshell-tui
set -euo pipefail
source "$source_repo/scripts/smoke/jarvis-console.sh"
expected_errors+=("${jarvis_provoked_errors[@]}")
ad_probe_was="$(plugin_enabled acme.probe)"
expect "the fixture holds the notification server for core sends" ok ipc shell setPluginEnabled acme.probe true
expect_poll "the notification fixture service is built" True record_exists acme.probe
ad_dir="$sandbox/agent-debug"
mkdir -p -- "$ad_dir"
ad_journal="$ad_dir/journal.jsonl"
ad_journal_calls="$ad_dir/journalctl.calls"
ad_notify_calls="$ad_dir/notify.calls"
ad_press="$ad_dir/press"
ad_fail="$ad_dir/install-fail"
: >"$ad_journal"
ad_uid="$(id -u)"
expected_errors+=('agent-debug: watch=stopped exit=')
# The harness stops this row's children before it runs this on an early
# end: the stand-in terminal and bin/vgshell-pkg the row replaced go back,
# and the row's stand-ins leave the shell's PATH.
ad_abandon() {
  local result=0
  if [[ ${ad_jarvis_prepared:-false} == true ]]; then ad_jarvis_restore || result=1; fi
  terminal_stand_in || result=1
  if [[ -f $ad_dir/vgshell-pkg.real ]]; then cp -- "$ad_dir/vgshell-pkg.real" "$repo/bin/vgshell-pkg" || result=1; fi
  rm -f -- "${shim:?}/journalctl" "${shim:?}/notify-send" "${shim:?}/claude" "${shim:?}/codex" || result=1
  ipc shell setPluginEnabled vgs.agent-debug false >/dev/null || result=1
  return "$result"
}
smoke_row_abandon=(ad_abandon)
terminal_stand_in

cat >"$shim/journalctl" <<EOF
#!/usr/bin/env bash
: >"$ad_journal"
python3 -c 'import json,os,sys; print(json.dumps({"pid": os.getppid(), "argv": sys.argv[1:]}))' "\$@" >>"$ad_journal_calls"
exec tail -n +1 -F -- "$ad_journal"
EOF
cat >"$shim/notify-send" <<EOF
#!/usr/bin/env bash
python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "\$@" >>"$ad_notify_calls"
if [[ -e "$ad_press" ]]; then cat -- "$ad_press"; fi
EOF
for agent in claude codex; do printf '#!/bin/sh\nexit 0\n' >"$shim/$agent"; done
chmod 755 "$shim/journalctl" "$shim/notify-send" "$shim/claude" "$shim/codex"
rescan "a rescan after the stand-ins arrive starts"

ad_values() { ipc smoke statusValues vgs.agent-debug; }
ad_value() { ad_values | py_reply 'import json,sys; v=json.load(sys.stdin); print(json.dumps(v.get(sys.argv[1])))' "$1"; }
ad_watch() { ad_value watch | py_reply 'import json,sys; v=json.load(sys.stdin); print(v["text"] if v else "unpublished")'; }
# ad_set KEY JSON: the plugin's setting KEY written into its plugins row,
# or taken out of it for an empty JSON; the service then reads it.
ad_set() {
  python3 - "$home/.config/vgshell/shell.json" "$1" "$2" <<'PY'
import json, os, sys
path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(path))
rows = data.setdefault("plugins", [])
at = [i for i, r in enumerate(rows) if r == "vgs.agent-debug" or (isinstance(r, dict) and r.get("id") == "vgs.agent-debug")]
if not at:
    rows.append({"id": "vgs.agent-debug"})
    at = [len(rows) - 1]
row = rows[at[0]] if isinstance(rows[at[0]], dict) else {"id": "vgs.agent-debug"}
if value:
    row[key] = json.loads(value)
else:
    row.pop(key, None)
rows[at[0]] = row
json.dump(data, open(path + ".tmp", "w"), indent=2)
os.replace(path + ".tmp", path)
PY
}
# The muted list as the user file holds it.
ad_muted_stored() { python3 -c 'import json,sys; r=[p for p in json.load(open(sys.argv[1])).get("plugins", []) if isinstance(p, dict) and p.get("id") == "vgs.agent-debug"]; print(json.dumps(r[0].get("muted") if r else None))' "$home/.config/vgshell/shell.json"; }
ad_count() { if [[ -f $1 ]]; then wc -l <"$1"; else echo 0; fi; }
ad_starts() { ad_count "$ad_journal_calls"; }
ad_sent() { ad_count "$ad_notify_calls"; }
# ad_crash COMM PID: one coredump entry of the user's uid appended to the
# journal the follower reads, written whole with its newline.
ad_crash() {
  python3 - "$ad_journal" "$1" "$2" "$ad_uid" <<'PY'
import json, sys
path, comm, pid, uid = sys.argv[1:5]
entry = {"__CURSOR": "s=ad;i=" + pid, "COREDUMP_COMM": comm, "COREDUMP_PID": pid, "COREDUMP_EXE": "/tmp/ad bin",
         "COREDUMP_SIGNAL_NAME": "SIGSEGV", "COREDUMP_SIGNAL": "11", "COREDUMP_UID": uid, "COREDUMP_TIMESTAMP": "1793742000123456"}
with open(path, "a") as out:
    out.write(json.dumps(entry) + "\n")
PY
}
# ad_titles N: the title of each notification after the first N, in order,
# as one JSON list; a record still being written has no newline yet and
# waits for the next read.
ad_titles() {
  python3 - "$ad_notify_calls" "$1" <<'PY'
import json, os, sys
path, skip = sys.argv[1], int(sys.argv[2])
lines = open(path).read().split("\n")[:-1] if os.path.exists(path) else []
print(json.dumps([a[a.index("--") + 1] for a in map(json.loads, lines[skip:])]))
PY
}
# ad_start N: the record of the follower start after the first N, as
# { pid, argv }, or `absent`.
ad_start() { python3 -c 'import json,sys; l=open(sys.argv[1]).read().split("\n")[:-1]; print(l[int(sys.argv[2])] if len(l) > int(sys.argv[2]) else "absent")' "$ad_journal_calls" "$1"; }
ad_pid() { ad_start "$1" | py_reply 'import json,sys; print(json.load(sys.stdin)["pid"])'; }
# ad_marked N: one marker crash, polled until it is told after the first N
# notifications, so every line planted before it has been read.
ad_marker=0
ad_marked() { # N
  ad_marker=$((ad_marker + 1))
  ad_crash "ad-marker-$ad_marker" "$((90000 + ad_marker))"
  expect_poll "the marker crash ad-marker-$ad_marker is told" true ad_told "$1" "ad-marker-$ad_marker crashed"
}
ad_told() { ad_titles "$1" | py_reply 'import json,sys; print(str(sys.argv[1] in json.load(sys.stdin)).lower())' "$2"; }
# ad_without_markers N: ad_titles less the markers'.
ad_without_markers() { ad_titles "$1" | py_reply 'import json,sys; print(json.dumps([t for t in json.load(sys.stdin) if not t.startswith("ad-marker-")]))'; }
# ad_alive PID: `alive` while PID is a tail that follows $ad_journal.
ad_alive() { if { tr '\0' ' ' <"/proc/$1/cmdline"; } 2>/dev/null | grep -q -F -- "tail -n +1 -F -- $ad_journal"; then echo alive; else echo gone; fi; }
ad_offered() { ad_value agents | py_reply 'import json,sys; print(json.dumps([o["value"] for o in json.load(sys.stdin) or [] if o["value"] in ("claude", "codex")]))'; }
ad_start_argv() { ad_start "$1" | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["argv"]))'; }
ad_seeded() { ipc smoke readInstance service vgs.agent-debug failuresSeen | py_reply 'import json,sys; v=json.load(sys.stdin); print(str(isinstance(v, list) and any(k.startswith("acme.needs:") for k in v)).lower())'; }
ad_failure() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["notices"]["failures"].get("acme.needs") is not None))'; }
# The planted crash time as the prompt writes it, in the sandbox's local
# time with its offset.
ad_time="$(date -d @1793742000 +%Y-%m-%dT%H:%M:%S%:z)"
# `ok` when the recorded diagnose run is a task Diagnose of acme.needs'
# failed install in Claude Code whose last argument is that run's ended
# record under the sandbox runtime; else the recorded words.
ad_task_diagnosed() {
  recorded_tail | py_reply 'import json,re,sys
w = json.load(sys.stdin)
fixed = ["vgs.agent-debug/diagnose", "tui/diagnose.sh", "claude", "task", "acme.needs", "install", "pacman", "vgs-smoke-needs-pkg"]
record = re.fullmatch(re.escape(sys.argv[1]) + r"/vgshell/tui/core@requirements-install@[A-Za-z0-9-]+\.ended\.json", w[-1]) if isinstance(w, list) and len(w) == 10 else None
print("ok" if isinstance(w, list) and w[:8] == fixed and record else json.dumps(w))' "$rt_dir"
}

# No agent chosen: no process starts and nothing is told.
expect "enabling Agent Debug is allowed" ok ipc shell setPluginEnabled vgs.agent-debug true
expect_poll "the plugin's service is built" True record_exists vgs.agent-debug
expect "enabling Agent Debug, its required tools found, raises no notice" null notice_shown
expect_poll "the select offers the agents the scan found" '["claude", "codex"]' ad_offered
expect_poll "Crash watch reads Off while no agent is chosen" Off ad_watch
ad_crash ad-first 7001
expect "with no agent chosen no follower starts" 0 ad_starts
expect "with no agent chosen nothing is told" 0 ad_sent
ad_set agent '"claude"'
expect_poll "control: choosing Claude Code starts one follower" 1 ad_starts
expect_poll "Crash watch reads Watching" Watching ad_watch
ad_crash ad-first 7001
expect_poll "control: with an agent chosen the same crash is told" '["ad-first crashed"]' ad_titles 0

# The follower: journalctl's own match keeps it to this user's programs.
expect "the follower reads new coredump entries of this user's programs" \
  "$(words -f -n 0 -o json --output-fields=COREDUMP_COMM,COREDUMP_PID,COREDUMP_EXE,COREDUMP_SIGNAL_NAME,COREDUMP_SIGNAL,COREDUMP_TIMESTAMP MESSAGE_ID=fc2e22bc6ee647b6b90729ab34a250b1 "COREDUMP_UID=$ad_uid")" \
  ad_start_argv 0

# One notification per program a minute.
n="$(ad_sent)"
ad_crash ad-crasher 7010
ad_crash ad-crasher 7011
ad_marked "$n"
expect "two crashes of one program inside the minute are told once" '["ad-crasher crashed"]' ad_without_markers "$n"
ad_crash ad-other 7012
expect_poll "control: another program inside the minute is told" '["ad-crasher crashed", "ad-other crashed"]' ad_without_markers "$n"

# The service's own processes.
n="$(ad_sent)"
ad_crash tail "$(ad_pid 0)"
ad_marked "$n"
expect "a crash with the follower's pid is not told" '[]' ad_without_markers "$n"
ad_crash tail 7020
expect_poll "control: the same name with another pid is told" '["tail crashed"]' ad_without_markers "$n"

# Mute, from the notification and from the skill's IPC call.
printf '1\n' >"$ad_press"
ad_crash ad-crasher2 7030
expect_poll "Mute on a crash keeps the program muted" '["ad-crasher2"]' ad_muted_stored
rm -f -- "${ad_press:?}"
expect_poll "Muted programs lists it with Unmute" '[{"id": "ad-crasher2", "label": "ad-crasher2", "actions": ["unmute"]}]' ad_value muted
expect "the IPC mute mutes a program" ok ipc vgs.agent-debug invoke mute ad-quiet
expect_poll "both programs are muted" '["ad-crasher2", "ad-quiet"]' ad_muted_stored
n="$(ad_sent)"
ad_crash ad-quiet 7031
ad_marked "$n"
expect "a muted program's crash is not told" '[]' ad_without_markers "$n"
expect "the IPC unmute unmutes it" ok ipc vgs.agent-debug invoke unmute ad-quiet
expect_poll "only the first program stays muted" '["ad-crasher2"]' ad_muted_stored
ad_crash ad-quiet 7032
expect_poll "control: unmuted, its next crash inside the minute is told" '["ad-quiet crashed"]' ad_without_markers "$n"

# Diagnose: the facts as data, in the agent chosen at the press.
forget_record
printf 'default\n' >"$ad_press"
ad_crash "ad 'x;\$(id)" 7040
expect_poll "Diagnose hands the terminal the diagnose TUI with each fact its own argument" \
  "$(words vgs.agent-debug/diagnose tui/diagnose.sh claude crash "ad 'x;\$(id)" 7040 SIGSEGV "$ad_time" '/tmp/ad bin')" recorded_tail
rm -f -- "${ad_press:?}"
expect_poll "the diagnose run ends" idle key_idle vgs.agent-debug/diagnose
ad_set agent '"codex"'
expect_poll "the service reads Codex" '"codex"' ipc smoke readInstance service vgs.agent-debug agent
forget_record
printf 'default\n' >"$ad_press"
ad_crash ad-y 7041
expect_poll "control: Diagnose opens the agent chosen at the press" \
  "$(words vgs.agent-debug/diagnose tui/diagnose.sh codex crash ad-y 7041 SIGSEGV "$ad_time" '/tmp/ad bin')" recorded_tail
rm -f -- "${ad_press:?}"
expect_poll "the second diagnose run ends" idle key_idle vgs.agent-debug/diagnose
ad_set agent '"claude"'
expect_poll "the service reads Claude Code again" '"claude"' ipc smoke readInstance service vgs.agent-debug agent

# A failed setup task: acme.needs' install, which the stand-in terminal
# ends with code 1 while $ad_fail exists, after detection answers pacman.
install_plugin_copy acme.needs acme.needs "Acme Sync"
rescan "a rescan after acme.needs arrives starts"
expect_poll "acme.needs is discovered" True plugin_known acme.needs
ad_pkg_real="$ad_dir/vgshell-pkg.real"
cp -- "$repo/bin/vgshell-pkg" "$ad_pkg_real"
pkg_stub '{"primary":{"id":"pacman","binary":"pacman"},"overlays":[],"sources":[]}'
terminal_fails_install "$ad_fail"
# ad_install: the acme.needs notice an enable raises, and its Install.
ad_install() {
  expect "enabling acme.needs raises its notice" ok ipc shell setPluginEnabled acme.needs true
  expect_poll "the notice holds the keyboard" true ipc smoke noticeFocused
  type_keys -k Return || fail "sending Return to the notice failed"
  expect_poll "the install run ends" idle key_idle core/requirements-install
}
n="$(ad_sent)"
: >"$ad_fail"
forget_record
printf 'default\n' >"$ad_press"
ad_install
expect_poll "a failed install is told once" '["Could not install tools"]' ad_without_markers "$n"
expect_poll "its Diagnose names the run's ended record" ok ad_task_diagnosed
rm -f -- "${ad_press:?}"
expect_poll "the task's diagnose run ends" idle key_idle vgs.agent-debug/diagnose
stop_shell || :
start_shell "$repo" "$sandbox/agent-debug-restarted-qs.log" || fail "the shell starts again over the kept failure"
expect_poll "the restarted service is built" True record_exists vgs.agent-debug
expect_poll "the restarted service has read the kept failure" true ad_seeded
expect_poll "the restarted follower watches" Watching ad_watch
ad_marked "$n"
expect "a shell restart tells the kept failure again never" '["Could not install tools"]' ad_without_markers "$n"
ad_install
expect_poll "control: the next failed run is told once" '["Could not install tools", "Could not install tools"]' ad_without_markers "$n"
rm -f -- "${ad_fail:?}"
ad_install
expect_poll "a run that ends with code 0 clears the failure" false ad_failure
expect_poll "the notice of the command still missing holds the keyboard" true ipc smoke noticeFocused
type_keys -k Escape || fail "sending Escape to the notice failed"
expect_poll "Escape closes the notice" null notice_shown
terminal_stand_in
cp -- "$ad_pkg_real" "$repo/bin/vgshell-pkg.next" && mv -T -- "$repo/bin/vgshell-pkg.next" "$repo/bin/vgshell-pkg"
expect "disabling acme.needs is allowed" ok ipc shell setPluginEnabled acme.needs false
ad_removed() { local out; out="$("${shell_env[@]}" "$repo/bin/vgshell" plugin remove --yes acme.needs 2>>"$sandbox/ipc.log")" || return 1; printf '%s\n' "${out%%$'\n'*}"; }
expect "acme.needs is removed" "ok removed=acme.needs" ad_removed
expect_poll "acme.needs leaves the list" False plugin_known acme.needs

# The offer and composer remain production code. Only daemon ports and Home
# session reads use the existing offline fixture.
ad_jarvis_prepared=false
ad_jarvis_restore() {
  ipc shell hide window vgs.jarvis >/dev/null || return 1
  ipc shell hide window vgs.agent-debug >/dev/null || return 1
  ipc shell setPluginEnabled vgs.jarvis false >/dev/null || return 1
  cp -- "$ad_dir/jarvisd-before.js" "$repo/shell/plugins/vgs.jarvis/backend/jarvisd.js" || return 1
  cp -- "$ad_dir/engine-before.js" "$repo/shell/plugins/vgs.jarvis/backend/ChainedEngine.js" || return 1
  rm -f -- "$repo/shell/plugins/vgs.jarvis/backend/scripted-fixture.js" || return 1
  cp -- "$ad_dir/Diagnose-before.js" "$repo/shell/plugins/vgs.agent-debug/Diagnose.js" || return 1
  jarvis_asks_restore || return 1
  user_config_restore "$ad_dir/config-before-jarvis.json" || return 1
  ipc shell reloadConfig >/dev/null || return 1
  jarvis_restore_requirements || return 1
  ad_jarvis_prepared=false
}
cp -- "$home/.config/vgshell/shell.json" "$ad_dir/config-before-jarvis.json"
cp -- "$repo/shell/plugins/vgs.jarvis/backend/jarvisd.js" "$ad_dir/jarvisd-before.js"
cp -- "$repo/shell/plugins/vgs.jarvis/backend/ChainedEngine.js" "$ad_dir/engine-before.js"
cp -- "$repo/shell/plugins/vgs.agent-debug/Diagnose.js" "$ad_dir/Diagnose-before.js"
jarvis_setup_requirements
jarvis_asks_fixture "$source_repo"
ad_jarvis_prepared=true
expect "the handoff selects a private Home" ok ipc shell reloadConfig
"$node_bin" "$source_repo/scripts/fixtures/jarvis/scripted.js" "$repo/shell/plugins/vgs.jarvis/backend/jarvisd.js" "$ad_dir/gates" --mapped-indicator
rescan "the offline Jarvis ports are scanned"
expect "Jarvis enables for the handoff" ok ipc shell setPluginEnabled vgs.jarvis true
ad_target() {
  ipc smoke readInstance service vgs.agent-debug targets | py_reply 'import json,sys
r=next((r for r in json.load(sys.stdin) if r["label"]=="Jarvis"),None)
print("absent" if r is None else json.dumps([r["key"],r["available"]]))'
}
ad_conversation() { ipc smoke jarvisProcess | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["status"].get("conversation", [])))'; }
ad_draft() { ipc smoke readShownDescendant window vgs.jarvis TextArea text; }
ad_json_text() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }
ad_prompt() { # PROGRAM: expected text independent of the shared builder
  printf '%s\n' "A program crashed on this computer and I want to know why." "What systemd-coredump recorded:" \
    "- Program: $1" "- Process ID: 7890" "- Binary: /tmp/ad bin" "- Signal: SIGSEGV" "- Time: $ad_time" \
    "Use the vgs-diagnose skill." "Diagnose only: change nothing on this computer."
}
ad_dispatch() { # PROGRAM: same notification -> Diagnose -> offer -> Console
  forget_record
  printf 'default\n' >"$ad_press"
  ad_crash "$1" 7890
  expect_poll "the actual Diagnose notification opens Jarvis" 1 window_count Jarvis
  rm -f -- "${ad_press:?}"
}
ad_exact_draft() {
  expect "the actual Diagnose composer holds the exact facts-only prompt" "$(ad_json_text "$(ad_prompt "$1")")" ad_draft
}
expect_poll "Agent Debug discovers the live Jarvis offer" '["handoff:vgs.jarvis/compose", true]' ad_target
ad_set agent '"handoff:vgs.jarvis/compose"'
expect_poll "Jarvis is the saved diagnosis choice" '"handoff:vgs.jarvis/compose"' ipc smoke readInstance service vgs.agent-debug agent
ad_dispatch ad-jarvis
ad_exact_draft ad-jarvis
expect "opening the draft sends no conversation turn" '[]' ad_conversation
expect "opening the draft starts no terminal" absent recorded
expect "the unsent draft closes" ok ipc shell hide window vgs.jarvis

# The same exercised dispatch with changed delivered text. Qt and the
# scanner read a new published revision from this disposable world tree.
python3 - "$repo/shell/plugins/vgs.agent-debug/Diagnose.js" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
needle='return lines.join("\\n");'
assert s.count(needle)==1
t=s.replace(needle,'return lines.join("\\n") + "\\nchanged delivery";')
assert t!=s
p.write_text(t)
PY
rescan "the altered delivery control is published"
expect_poll "the control still discovers the actual Jarvis receiver" '["handoff:vgs.jarvis/compose", true]' ad_target
ad_dispatch ad-jarvis-control
ad_control="$(
  failures=0 behaviour_failures=0
  ad_exact_draft ad-jarvis-control >"$smoke_log_dir/agent-debug-handoff-control.log"
  printf '%s' "$failures"
)"
expect "the changed delivery fails exactly one composer assertion" 1 echo "$ad_control"
expect "the control fails the intended exact-text assertion" 1 grep -c 'FAIL.*the actual Diagnose composer holds the exact facts-only prompt' "$smoke_log_dir/agent-debug-handoff-control.log"
expect "the changed text actually reached the production composer" \
  "$(ad_json_text "$(ad_prompt ad-jarvis-control)"$'\nchanged delivery')" ad_draft
expect "the control still starts no conversation" '[]' ad_conversation
expect "the control console closes" ok ipc shell hide window vgs.jarvis
cp -- "$ad_dir/Diagnose-before.js" "$repo/shell/plugins/vgs.agent-debug/Diagnose.js"
rescan "the original shared builder is restored"
expect_poll "the restored service discovers Jarvis" '["handoff:vgs.jarvis/compose", true]' ad_target

# An occupied production TextArea must not lose any typed bytes.
expect "an empty console opens for typing" ok ipc shell summon window vgs.jarvis '{}'
expect_poll "the empty console maps" 1 window_count Jarvis
type_keys '  my unsent text  ' || fail "typing an occupied draft failed"
expect_poll "the composer keeps surrounding whitespace" "$(ad_json_text '  my unsent text  ')" ad_draft
printf 'default\n' >"$ad_press"
ad_crash ad-occupied 7891
expect_poll "occupied text opens explicit recovery" 1 window_count "Agent Debug"
rm -f -- "${ad_press:?}"
expect "a refused handoff preserves every typed byte" "$(ad_json_text '  my unsent text  ')" ad_draft
expect "an occupied handoff sends no conversation" '[]' ad_conversation
expect "occupied recovery cancels explicitly" ok ipc vgs.agent-debug invoke recover cancel
expect "the recovery window closes" ok ipc shell hide window vgs.agent-debug
expect "the occupied console closes" ok ipc shell hide window vgs.jarvis

expect "turning Jarvis off withdraws its live receiver" ok ipc shell setPluginEnabled vgs.jarvis false
expect_poll "the declared Jarvis target remains unavailable" '["handoff:vgs.jarvis/compose", false]' ad_target
ad_unavailable_choice() { ad_value agents | py_reply 'import json,sys; print(any(r["value"]=="handoff:vgs.jarvis/compose" and "unavailable" in r["label"] for r in json.load(sys.stdin)))'; }
expect_poll "the picker marks saved Jarvis unavailable" True ad_unavailable_choice
for ad_recovery_agent in claude codex; do
  forget_record
  printf 'default\n' >"$ad_press"
  ad_crash "ad-unavailable-$ad_recovery_agent" 7892
  expect_poll "unavailable Jarvis opens recovery for $ad_recovery_agent" 1 window_count "Agent Debug"
  rm -f -- "${ad_press:?}"
  expect "recovery names Jarvis's actual disabled cause" '"Jarvis is turned off. Turn it on in Settings."' ipc smoke readInstance window vgs.agent-debug reason
  expect "unavailable Diagnose starts no terminal by itself" absent recorded
  expect "the user explicitly chooses $ad_recovery_agent for this failure" ok ipc vgs.agent-debug invoke recover "$ad_recovery_agent"
  expect_poll "one-off recovery passes the scalar facts to $ad_recovery_agent" \
    "$(words vgs.agent-debug/diagnose tui/diagnose.sh "$ad_recovery_agent" crash "ad-unavailable-$ad_recovery_agent" 7892 SIGSEGV "$ad_time" '/tmp/ad bin')" recorded_tail
  expect_poll "one-off terminal diagnosis ends" idle key_idle vgs.agent-debug/diagnose
  expect "one-off recovery keeps the saved Jarvis choice" '"handoff:vgs.jarvis/compose"' ipc smoke readInstance service vgs.agent-debug agent
  expect "the one-off recovery window closes" ok ipc shell hide window vgs.agent-debug
done
ad_jarvis_restore
expect_poll "the pre-handoff terminal choice returns" '"claude"' ipc smoke readInstance service vgs.agent-debug agent

# The follower's lifetime: its end with a disable, and a follower that
# ends on its own, which reads Stopped until the agent changes.
s="$(ad_starts)"
pid="$(ad_pid "$((s - 1))")"
expect "the follower is the tail its stand-in started" alive ad_alive "$pid"
expect "disabling the plugin is allowed" ok ipc shell setPluginEnabled vgs.agent-debug false
expect_poll "a disable removes the service's record" False record_exists vgs.agent-debug
expect_poll "a disable leaves no follower" gone ad_alive "$pid"
expect "enabling the plugin again is allowed" ok ipc shell setPluginEnabled vgs.agent-debug true
expect_poll "control: enabling it again starts one follower" "$((s + 1))" ad_starts
expect_poll "the enabled follower watches" Watching ad_watch
kill "$(ad_pid "$s")"
expect_poll "a follower that ends reads Stopped" Stopped ad_watch
expect "a stopped follower starts no other" "$((s + 1))" ad_starts
expect_log "the stop is logged with its exit" 1 'agent-debug: watch=stopped exit='
ad_set agent '"codex"'
expect_poll "control: a change of agent starts the follower again" "$((s + 2))" ad_starts
expect_poll "the follower watches again" Watching ad_watch

ad_set agent ""
ad_set muted ""
expect_poll "with no agent Crash watch reads Off again" Off ad_watch
expect_poll "the muted list is empty again" '[]' ad_value muted
expect "disabling Agent Debug again is allowed" ok ipc shell setPluginEnabled vgs.agent-debug false
expect_poll "Agent Debug's service is gone" False record_exists vgs.agent-debug
rm -f -- "${shim:?}/journalctl" "${shim:?}/notify-send" "${shim:?}/claude" "${shim:?}/codex"
expect "the notification fixture returns to its incoming enablement" ok ipc shell setPluginEnabled acme.probe "${ad_probe_was,,}"
rescan "a rescan after the stand-ins go starts"
