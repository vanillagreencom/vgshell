# Automations, vgs.automations. The harness starts it disabled; this row
# enables it over the harness's automations_stand_ins in the shell's own
# PATH directory: a systemctl that logs every verb, a systemd-run that logs
# its argv and runs the argv after `--`, a notify-send that logs its argv
# and prints an id; the harness's loginctl sentinel, which answers
# show-user with lingering off, and its crontab stand-in serve the whole
# run. No call can reach the
# host's systemd user manager or the user's crontab: the sandbox's runtime
# directory and session bus are its own, and every command the plugin runs
# resolves to a stand-in first, save busctl, which reaches the sandbox's
# own session and system buses alone. The row drives the engine,
# bin/automations, as the shell's service runs it, with the shell's
# environment.
#
# Rows: the service publishes its declared status, and its start with no
# automation runs no systemctl verb but show-environment; crontab resolves
# to the stand-in, with a control reading the host's PATH; an automation the
# engine adds writes its timer and service under the sandbox home, enables
# the timer and reaches only the stand-in crontab; the service counts it
# scheduled from the store change alone; a failed sync stays the Engine
# status after a list succeeds and clears once a sync succeeds; a
# failing Run now goes through systemd-run, sends the error notification
# with the VGS hints and reaches the Last runs status through the service's
# runs listing; the linger TUI opens through the stand-in terminal, from
# the IPC and from the Settings page's Enable while logged out, whose run's
# end lists lingering again and withdraws the action; the Automations
# window creates, edits (a custom rule, then every 10 minutes from the
# Repeat every list, its summary and its preview's 10-minute gaps read
# back), pauses, runs, removes and clears through the
# nested seat's pointer and keyboard alone, the CLI only reading each
# result back, its History page building no row while another tab shows,
# though the window has read the runs, listing the runs once its tab
# opens, and its Down, Up, Return and Enter moving the drawn selection
# and opening the run it shows; and the control, a copy of the plugin whose service lists
# neither after a run file lands nor after the store changes and whose
# window's engine door drops every write and skips the transcript TUI,
# leaves the count as it was after the engine pauses the automation, Last
# runs as it was after the next failing run, and the store, the history
# and the TUI record as they were after the same clicks and keys. Then a
# scheduled run of a slot missed in a suspend waits while the sandbox's
# NetworkManager mock reads disconnected and starts once the row sets it
# online, and three failing runs and a success keep one notice, the
# notify-send stand-in's later calls each replacing the first's id. The
# row ends with the plugin disabled, the mock's Connectivity as the row found it,
# its stand-ins removed and the shim files they covered restored.
# inputs: shell/plugins/vgs.automations/* shell/plugins/vgs.automations/bin/automations shell/plugins/vgs.settings/manifest.json shell/plugins/vgs.settings/Window.qml shell/plugins/vgs.settings/ListPage.qml shell/plugins/vgs.settings/PluginPage.qml shell/plugins/vgs.settings/PageHeader.qml shell/plugins/vgs.settings/EditSet.qml shell/plugins/vgs.settings/Steps.js shell/plugins/vgs.settings/SettingField.qml shell/plugins/vgs.settings/StatusRow.qml shell/plugins/vgs.settings/StatusLine.qml shell/plugins/vgs.settings/RequirementRow.qml shell/Commons/Reply.js shell/Core/PluginStatus.qml shell/Core/TuiRunner.qml bin/vgshell-tui bin/vgshell bin/lib/qml-library.js shell/Ui/feedback/Dialog.qml shell/Commons/Duration.js shell/Commons/qmldir shell/Ui/controls/RowAction.qml shell/Core/NotificationHub.qml scripts/smoke/rows/capabilities.sh
set -euo pipefail
auto_stub="$sandbox/automations-stub"
# The systemctl stand-in fails daemon-reload while $auto_stub/fail-reload
# exists, so a row can make a sync fail.
automations_stand_ins "$auto_stub"
auto_nm_original=""
auto_copy=""
auto_net_control=""
# The harness stops this row's children before invoking its registered
# abandonment cleanup. Restore owned state even when a fixture step fails.
auto_abandon() {
  local result=0 saved
  if [[ -n $auto_nm_original ]]; then nm_set "$auto_nm_original" >/dev/null || result=1; fi
  if [[ -n $auto_net_control && -d $auto_net_control ]]; then rm -rf -- "${auto_net_control:?}" || result=1; fi
  if [[ -n $auto_copy && -d $auto_copy ]]; then
    rm -rf -- "${auto_copy:?}" || result=1
    rescan "abandonment restores the shipped automations plugin"
  fi
  ipc shell setPluginEnabled vgs.automations false >/dev/null || result=1
  saved="$(sentinel_saved "$shim/loginctl")" || return
  if [[ -e $saved ]]; then sentinel_restore "$shim/loginctl" || result=1; fi
  automations_stand_ins_restore "$auto_stub" || result=1
  return "$result"
}
smoke_row_abandon=(auto_abandon)
terminal_stand_in

auto_engine="$repo/shell/plugins/vgs.automations/bin/automations"
shell_path="$(tr '\0' '\n' <"/proc/$shell_qs_pid/environ" | sed -n 's/^PATH=//p')"
[[ -n $shell_path ]] || fail "the shell's PATH is unreadable"
automations() { "${shell_env[@]}" PATH="$shell_path" "$auto_engine" --tree "$repo" "$@" 2>>"$sandbox/automations.err"; }
# The last line a verb prints: a verb that syncs prints sync's line first.
auto_last() { local out; out="$(automations "$@")" || return; printf '%s\n' "${out##*$'\n'}"; }
auto_status() { ipc vgs.automations invoke status "" | py_reply 'import json,sys; v=json.load(sys.stdin); print(json.dumps(v.get(sys.argv[1], "unset")))' "$1"; }
auto_status_tone() { auto_status "$1" | py_reply 'import json,sys; v=json.load(sys.stdin); print(v.get("tone") if isinstance(v, dict) else json.dumps(v))'; }
auto_status_tone_action() { auto_status "$1" | py_reply 'import json,sys; v=json.load(sys.stdin); print(json.dumps([v.get("tone"), v.get("action")]) if isinstance(v, dict) else json.dumps(v))'; }
auto_lent() { ipc shell lent | py_reply 'import json,sys; d=json.load(sys.stdin); r=d["status"].get("vgs.automations"); print(json.dumps([sorted(r["keys"]) if r else None, "vgs.automations" in d["ipcTargets"]]))'; }
# The systemctl verbs logged since the row began, show-environment left out.
auto_verbs() { if [[ -f $auto_stub/systemctl.calls ]]; then py_reply 'import json,sys; print(json.dumps([c[1] for c in map(json.loads, sys.stdin) if c[1] != "show-environment"]))' <"$auto_stub/systemctl.calls"; else echo '[]'; fi; }
auto_units() {
  if [[ ! -d $home/.config/systemd/user ]]; then echo '[]'; return; fi
  local names
  names="$(cd -- "$home/.config/systemd/user" && ls)" || return
  if [[ -z $names ]]; then echo '[]'; else py_reply 'import json,sys; print(json.dumps(sys.stdin.read().split()))' <<<"$names"; fi
}
# The VGS hints of the last notification, as its x-vgs names and values.
auto_hints() { if [[ -f $auto_stub/notify-send.calls ]]; then tail -n 1 -- "$auto_stub/notify-send.calls" | py_reply 'import json,sys; a=json.load(sys.stdin); print(json.dumps([h.split(":", 2)[1] + "=" + ("<path>" if h.split(":", 2)[1] == "x-vgs-open" else h.split(":", 2)[2]) for h in a if h.startswith("--hint=string:x-vgs-")]))'; else echo absent; fi; }
# resolved COMMAND PATH_LIST: the file COMMAND runs from on PATH_LIST, or
# none. The harness's crontab stand-in stays for the whole run, since
# crontab picks the caller's own table by user, not by HOME.
resolved() { PATH="$2" bash -c 'command -v "$1" || echo none' _ "$1"; }
crontab_calls() { if [[ -f $sandbox/crontab.calls ]]; then py_reply 'import json,sys; print(json.dumps(sys.stdin.read().splitlines()))' <"$sandbox/crontab.calls"; else echo '[]'; fi; }
last_systemd_run_prefix() { tail -n 1 -- "$auto_stub/systemd-run.calls" | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)[:3]))'; }
: >"$sandbox/crontab.calls"
# auto_problem: the Engine status as `<tone> <operation>` and the exit word,
# or `ok None`.
auto_problem() { auto_status problem | py_reply 'import json,sys; v=json.load(sys.stdin); print(" ".join([v["tone"]] + v["text"].split(" ")[:2]))'; }
failing='{"name": "Nightly", "command": "echo nope >&2; exit 3", "schedule": {"frequency": "weekly", "interval": 2, "weekdays": ["mon"], "times": ["03:00"], "start": "2026-01-05", "end": {"type": "never"}}}'

# The fixed clock and every XDG directory live under the row's sandbox tree.
# This runs the same scheduler entry point as a timer, at the UTC month edge
# that is still 5 pm on the Pacific side of the November clock change.
utc_test="$sandbox/automations-utc"
mkdir -p -- "$utc_test/home" "$utc_test/config" "$utc_test/data" "$utc_test/state" "$utc_test/run" "$utc_test/bin"
chmod 700 -- "$utc_test/run"
cat >"$utc_test/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@")" >>"$UTC_STUB/systemctl.calls"
exit 0
EOF
chmod 755 -- "$utc_test/bin/systemctl"
utc_slot_ms="$(python3 -c 'from datetime import datetime,timezone; print(int(datetime(2026,11,1,tzinfo=timezone.utc).timestamp()*1000))')"
cat >"$utc_test/fixed-date.js" <<EOF
const RealDate = Date;
global.Date = class FixedDate extends RealDate {
  constructor(...args) { super(...(args.length === 0 ? [$utc_slot_ms] : args)); }
  static now() { return $utc_slot_ms; }
};
EOF
utc_automations() {
  "${shell_env[@]}" PATH="$utc_test/bin:$shell_path" HOME="$utc_test/home" XDG_CONFIG_HOME="$utc_test/config" XDG_DATA_HOME="$utc_test/data" XDG_STATE_HOME="$utc_test/state" XDG_RUNTIME_DIR="$utc_test/run" STUB="$auto_stub" UTC_STUB="$utc_test" TZ=America/Los_Angeles NODE_OPTIONS="--require=$utc_test/fixed-date.js" "$auto_engine" --tree "$repo" "$@" 2>>"$sandbox/automations-utc.err"
}
utc_last() { local out; out="$(utc_automations "$@")" || return; printf '%s\n' "${out##*$'\n'}"; }
utc_fire() { utc_automations run --scheduled utc-month-end >/dev/null && echo ok; }
utc_run_record() { python3 -c 'import glob,json,sys; p=glob.glob(sys.argv[1]+"/*.ended.json"); r=json.load(open(p[0])); print(json.dumps([r["trigger"],r["outcome"],r["slot"]],separators=(",",":")))' "$utc_test/state/vgshell/automations/runs"; }
utc_definition='{"name":"UTC month end","command":"echo utc-slot","schedule":{"frequency":"monthly","interval":1,"monthly":{"by":"date","day":1},"times":["00:00"],"start":"2026-11-01","end":{"type":"never"},"zone":"utc"}}'
expect "the nested scheduler stores the UTC month-end rule in its temporary XDG tree" added=utc-month-end utc_last add --definition "$utc_definition"
expect "the UTC timer carries its schedule zone" True python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); print("OnCalendar=*-*-01 00:00:00 UTC" in p.read_text())' "$utc_test/config/systemd/user/vgs-automation-utc-month-end.timer"
mkdir -p -- "$utc_test/state/vgshell/automations/guard"
printf '{"handledThrough":%s}\n' "$((utc_slot_ms - 86400000))" >"$utc_test/state/vgshell/automations/guard/utc-month-end.json"
expect "the nested scheduler executes the scheduled UTC trigger" ok utc_fire
expect "the scheduled UTC occurrence runs at 5 pm Pacific on the previous local month end" '["scheduled","succeeded",1793491200000]' utc_run_record

expect "enabling the automations is allowed" ok ipc shell setPluginEnabled vgs.automations true
expect_poll "the service holds its status record and IPC target" '[["active", "lastRuns", "linger", "nextRun", "problem", "scheduler"], true]' auto_lent
expect_poll "the scheduler reads the stand-in's systemd user manager" ok auto_status_tone scheduler
expect_poll "lingering reads off, offering its action" '["info", true]' auto_status_tone_action linger
expect "a start with no automation runs no systemctl verb" '[]' auto_verbs
expect "no unit is written with no automation" '[]' auto_units
expect "the shell's PATH resolves crontab to the harness's stand-in" "$shim/crontab" resolved crontab "$shell_path"
# The reader's control: the host's PATH alone resolves no stand-in, so the
# reading above is the shell's PATH and not the reader.
expect "the host's PATH alone resolves no stand-in crontab" True python3 -c 'import sys; print(sys.argv[1] != sys.argv[2])' "$(resolved crontab "$PATH")" "$shim/crontab"

expect "the engine adds an automation" added=nightly auto_last add --definition "$failing"
expect "its timer and service are under the sandbox home" '["vgs-automation-nightly.service", "vgs-automation-nightly.timer"]' auto_units
expect "the add reloads the manager and enables the timer" '["daemon-reload", "enable"]' auto_verbs
expect "the add's sync read the stand-in crontab twice" '["-l", "-l"]' crontab_calls
expect_poll "the service lists the engine's store change with no IPC call" 1 auto_status active
expect_poll "no run has failed yet" ok auto_status_tone lastRuns

# A sync that fails stays the Engine status after the list that follows
# it succeeds, until a sync succeeds. The missing timer gives sync work.
: >"$auto_stub/fail-reload"
expected_errors+=('automations: sync exit=1 automations: refused: systemctl=failed args=daemon-reload exit=1')
unlink -- "$home/.config/systemd/user/vgs-automation-nightly.timer"
expect "the service syncs on request" ok ipc vgs.automations invoke sync ""
expect_poll "a failed sync is the Engine status after the list succeeds" "danger The scheduler" auto_problem
expect_poll "the list after the failed sync still counts it" 1 auto_status active
unlink -- "$auto_stub/fail-reload"
expect "the service syncs again" ok ipc vgs.automations invoke sync ""
expect_poll "a sync that succeeds clears the Engine status" "ok None" auto_problem
expect "the timer is written again" '["vgs-automation-nightly.service", "vgs-automation-nightly.timer"]' auto_units

auto_rows_json() { automations list --json | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["automations"]))'; }
auto_row_value() { auto_rows_json | py_reply 'import json,sys; rows=json.load(sys.stdin); found=[r for r in rows if r["name"] == sys.argv[1] or r["id"] == sys.argv[1]];
if not found:
    print("absent"); raise SystemExit
row=found[0]; value=row;
for part in sys.argv[2].split("."): value=value.get(part) if isinstance(value,dict) else None
print(json.dumps(value))' "$1" "$2"; }
auto_id_by_name() { auto_rows_json | py_reply 'import json,sys; rows=[r for r in json.load(sys.stdin) if r["name"] == sys.argv[1]]; print(rows[0]["id"] if rows else "")' "$1"; }
auto_preview_first() { auto_rows_json | py_reply 'import json,subprocess,sys; rows=json.load(sys.stdin); row=[r for r in rows if r["id"] == sys.argv[1]][0]; out=subprocess.check_output([sys.argv[2],"--tree",sys.argv[3],"preview","--schedule",json.dumps(row["schedule"]),"--count","1"], text=True); print(str(json.loads(out)["occurrences"][0]))' "$1" "$auto_engine" "$repo"; }
auto_row_exists() { auto_rows_json | py_reply 'import json,sys; print("present" if any(r["id"] == sys.argv[1] for r in json.load(sys.stdin)) else "absent")' "$1"; }
auto_history_count() { automations history --json | py_reply 'import json,sys; print(len([r for r in json.load(sys.stdin)["rows"] if r["automation"] == sys.argv[1]]))' "$1"; }
auto_service_marker() { ipc smoke readInstance service vgs.automations smokeListSoonFired; }
auto_service_marker_after() { local now; now="$(auto_service_marker)" || return; [[ $now =~ ^[0-9]+$ && $now -gt $1 ]] && echo fired || echo "$now"; }
auto_window_run_marker() { ipc smoke readInstance window vgs.automations smokeRunCalls; }
auto_window_run_after() { local now; now="$(auto_window_run_marker)" || return; [[ $now =~ ^[0-9]+$ && $now -gt $1 ]] && echo fired || echo "$now"; }
auto_window_transcript_marker() { ipc smoke readInstance window vgs.automations smokeTranscriptCalls; }
auto_window_transcript_after() { local now; now="$(auto_window_transcript_marker)" || return; [[ $now =~ ^[0-9]+$ && $now -gt $1 ]] && echo fired || echo "$now"; }
# The window's rows drive it through the nested seat alone: every store,
# unit and history change below comes from a click or a key in the
# window, and the engine is only read back. Each helper fails when its
# control is not drawn or its input does not reach the seat.
# ui_reveal TYPE TEXT: the item's scroll area moved, as a wheel would, so
# the item lies in view before a click (the probe's revealText).
ui_revealed() { [[ $1 != absent && -n $1 ]]; }
ui_reveal() { ui_revealed "$(ipc smoke revealText window vgs.automations "$1" "$2")"; }
# ui_field_in LABEL TYPE TEXT NEW: the same inside the Field labelled LABEL.
ui_field_in() {
  ui_revealed "$(ipc smoke revealScopedText window vgs.automations Field "$1" "$2" "$3")" || return
  click_scoped_in window:Automations window vgs.automations Field "$1" "$2" "$3" || return
  type_keys -M ctrl -k a -m ctrl "$4" && echo ok
}
ui_click() { ui_reveal "$1" "$2" && click_in window:Automations window vgs.automations "$1" "$2" && echo ok; }
ui_click_in_row() { click_scoped_in window:Automations window vgs.automations AutomationRow "$1" "$2" "$3" && echo ok; }
ui_hover() {
  local rect x y
  rect="$(ipc smoke windowGeometry window vgs.automations "$1" "$2")" || return 1
  [[ $rect == \[* ]] || { echo "ui_hover: no $1 $2: $rect" >&2; return 1; }
  read -r x y < <(at_centre window:Automations "$rect") || return 1
  hover "$x" "$y" && echo ok
}
ui_hovered() { ipc smoke itemHovered window vgs.automations "$1" "$2"; }
ui_confirm() { ipc smoke readInstance window vgs.automations confirmAction; }
ui_keys() { type_keys "$@" && echo ok; }
ui_field_type() { # TYPE TEXT NEW: click the field of TYPE reading TEXT, select all, type NEW
  ui_click "$1" "$2" >/dev/null || return
  type_keys -M ctrl -k a -m ctrl "$3" && echo ok
}
ui_row_names() { ipc smoke readInstance window vgs.automations automations | py_reply 'import json,sys; print(json.dumps([r["name"] for r in json.load(sys.stdin)]))'; }
ui_editor_open() { ipc smoke readInstance window vgs.automations editorOpen; }
ui_draft() { ipc smoke readInstance window vgs.automations draft | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)[sys.argv[1]]))' "$1"; }
ui_preview_first() { ipc smoke readInstance window vgs.automations previewFirst | py_reply 'import json,sys; print(json.load(sys.stdin))'; }
ui_history_opens_transcript() { # NAME
  click_in window:Automations window vgs.automations HistoryRow "$1" || return
  recorded_tail | py_reply 'import json,sys; t=sys.stdin.read().strip(); print(json.dumps(json.loads(t)[:2]) if t.startswith("[") else t)'

}
ui_create() { # NAME COMMAND: New, the name, the command and Save, by the pointer and typed text
  ui_click Button New >/dev/null || return
  ui_field_type TextField "New automation" "$1" >/dev/null || return
  ui_click TextArea "" >/dev/null || return
  type_keys "$2" || return
  ui_click Button Save
}
ui_focus_type() { ipc smoke activeFocusItem window vgs.automations | py_reply 'import json,sys; r=json.load(sys.stdin); print(r[0] if isinstance(r, list) else r)'; }
# keyboard_create WHERE NAME COMMAND: Ctrl+N, the name, Tab to the
# command and Ctrl+S, each key sent once its field holds the focus; no
# pointer event.
keyboard_create() {
  expect_poll "the list holds the keys $1" true ipc smoke activeFocusWithin window vgs.automations AutomationListPage
  expect "Ctrl+N opens a new editor $1" ok ui_keys -M ctrl -k n -m ctrl
  expect_poll "the name field holds the keys $1" TextField ui_focus_type
  expect "the name is typed and Tab moves on $1" ok ui_keys -M ctrl -k a -m ctrl "$2" -k Tab
  expect_poll "Tab reaches the command $1" TextArea ui_focus_type
  expect "the command is typed and Ctrl+S saves $1" ok ui_keys "$3" -M ctrl -k s -m ctrl
}

expect "the automations window summons over IPC" ok ipc shell summon window vgs.automations '{}'
expect_poll "the automations window maps one window" 1 window_count Automations
expect_poll "the window takes the keyboard when it opens" true ipc smoke activeFocusIn window vgs.automations

# Create: New, typed fields and Save reach the engine's store.
expect "the pointer creates Smoke UI through the editor" ok ui_create "Smoke UI" "echo smoke-ui"
expect_poll "the CLI reads the automation the window created" '"echo smoke-ui"' auto_row_value smoke-ui command
expect "the window's draft is the saved automation" '"smoke-ui"' ui_draft id

# A pointer toggles the requirement and saves it. Space on that same
# focused switch toggles it back; Ctrl+S round-trips the keyboard edit.
expect "a new automation does not require the network" false auto_row_value smoke-ui requiresNetwork
expect "the pointer enables Needs internet" ok ui_click Switch "Needs internet"
expect_poll "the requirement reaches the draft" true ui_draft requiresNetwork
expect "Save stores the network requirement" ok ui_click Button Save
expect_poll "the CLI reads the network requirement" true auto_row_value smoke-ui requiresNetwork
expect "the pointer focuses Needs internet for its keyboard toggle" ok ui_click Switch "Needs internet"
expect_poll "the focused switch is off" false ui_draft requiresNetwork
expect "Space toggles the focused requirement on" ok ui_keys -k space
expect_poll "Space reaches the checked draft" true ui_draft requiresNetwork
expect "Space toggles it off and Ctrl+S stores the keyboard edit" ok ui_keys -k space -M ctrl -k s -m ctrl
expect_poll "the CLI reads the unchecked keyboard edit" false auto_row_value smoke-ui requiresNetwork

# Edit the recurrence: the preset menu to Custom by its typed letter, the
# interval to 2, Save; the engine stores it and the drawn preview's first
# occurrence is the engine's own for the stored rule.
expect "the preset menu opens" ok ui_click Select "Every weekday"
# Custom is the menu's last entry; the list stops there.
expect "Down to the last entry and Return choose Custom" ok ui_keys -k Down -k Down -k Down -k Down -k Down -k Down -k Down -k Down -k Down -k Down -k Return
expect_poll "the editor shows the custom rule" '"custom"' ui_draft preset
expect "the interval takes 2" ok ui_field_in Every TextField 1 2
expect_poll "the draft holds the interval" 2 ui_draft interval
expect "Save stores the edited recurrence" ok ui_click Button Save
expect_poll "the CLI reads the edited recurrence interval" 2 auto_row_value smoke-ui 'schedule.interval'
expect_poll "the drawn preview's first occurrence is the engine's" "$(auto_preview_first smoke-ui)" ui_preview_first

# Every 10 minutes: Repeat every's list moves from weeks up to minutes,
# whose Every field is a list of steps, 2 kept from the rule above; Down to
# 10 and Save. The engine stores the step, the summary reads it and the
# drawn preview's runs are 10 minutes apart.
ui_select_in() { # FIELD TEXT: click the Select reading TEXT inside the Field labelled FIELD
  ui_revealed "$(ipc smoke revealScopedText window vgs.automations Field "$1" Select "$2")" || return
  click_scoped_in window:Automations window vgs.automations Field "$1" Select "$2" && echo ok
}
ui_preview_gaps() { ipc smoke readInstance window vgs.automations previewRows | py_reply 'import json,sys; r=json.load(sys.stdin); print(json.dumps([len(r), sorted(set(b - a for a, b in zip(r, r[1:])))]))'; }
expect "Repeat every's list opens" ok ui_select_in Every weeks
expect "Up to its first entry and Return choose minutes" ok ui_keys -k Up -k Up -k Up -k Up -k Up -k Return
expect_poll "the draft repeats every N minutes" '"minutely"' ui_draft frequency
ui_step_shown() { ipc smoke itemValues window vgs.automations Select currentText,visible | py_reply 'import json,sys; print(any(r["visible"] and r["currentText"] == sys.argv[1] for r in json.load(sys.stdin)))' "$1"; }
expect_poll "the Every field shows the steps list on 2" True ui_step_shown 2
expect "the Every steps list opens on 2" ok ui_select_in Every 2
expect "Down to 10 and Return choose it" ok ui_keys -k Down -k Down -k Down -k Down -k Down -k Return
expect_poll "the draft holds the step" 10 ui_draft interval
expect "Save stores every 10 minutes" ok ui_click Button Save
expect_poll "the CLI reads the stored frequency" '"minutely"' auto_row_value smoke-ui schedule.frequency
expect_poll "the CLI reads the stored step" 10 auto_row_value smoke-ui schedule.interval
expect_poll "the engine's summary reads every 10 minutes" '"Every 10 minutes"' auto_row_value smoke-ui summary
expect_poll "the drawn summary reads every 10 minutes" '"Every 10 minutes"' ipc smoke readInstance window vgs.automations previewSummary
expect_poll "the drawn preview's five runs are 10 minutes apart" '[5, [600000]]' ui_preview_gaps

# Toggle: the row's switch pauses and resumes the automation.
expect "Escape returns to the list" ok ui_keys -k Escape
expect_poll "the list is shown" false ui_editor_open
expect "a click on the row's switch pauses it" ok ui_click_in_row "Smoke UI" Switch ""
expect_poll "the CLI reads the disabled state" false auto_row_value smoke-ui enabled
expect "a second click resumes it" ok ui_click_in_row "Smoke UI" Switch ""
expect_poll "the CLI reads the enabled state" true auto_row_value smoke-ui enabled

# Run now from the row twice, then the History tab opens a run's
# transcript in the transcript TUI, which the stand-in terminal records
# only.
expect "the row's Run now starts a run" ok ui_click_in_row "Smoke UI" IconButton "Run now"
expect_poll "the run reaches the history rows" 1 auto_history_count smoke-ui
expect "a second Run now starts a second run" ok ui_click_in_row "Smoke UI" IconButton "Run now"
expect_poll "the second run reaches the history rows" 2 auto_history_count smoke-ui
ui_answer_runs() { ipc smoke readInstance window vgs.automations historyAnswer | py_reply 'import json,sys; print(sum(r["automation"] == sys.argv[1] for r in json.load(sys.stdin)))' "$1"; }
ui_history_rows_built() { ipc smoke itemValues window vgs.automations HistoryRow visible | py_reply 'import json,sys; t=sys.stdin.read(); print(len(json.loads(t)) if t.startswith("[") else t.strip())'; }
expect_poll "the window reads both runs" 2 ui_answer_runs smoke-ui
expect "the hidden History page builds no row" 0 ui_history_rows_built
expect "the History tab opens" ok ui_click Label History
forget_record
expect_poll "a click on the history row opens its transcript TUI" "$(words vgs.automations/transcript tui/transcript.sh)" ui_history_opens_transcript "Smoke UI"

# The keyboard: Down and Up move the drawn selection between the two runs,
# newest first as the window read them, and Return and Enter open the run
# the selection shows.
ui_history_selected() { ipc smoke itemValues window vgs.automations HistoryRow highlighted,row.transcript | py_reply 'import json,sys; print(json.dumps([r["row.transcript"] for r in json.load(sys.stdin) if r["highlighted"]]))'; }
ui_answer_transcript() { ipc smoke readInstance window vgs.automations historyAnswer | py_reply 'import json,sys; print(json.dumps([json.load(sys.stdin)[int(sys.argv[1])]["transcript"]]))' "$1"; }
ui_opened_transcript() { recorded_tail | py_reply 'import json,sys; t=sys.stdin.read().strip(); print(json.dumps(json.loads(t)[2:]) if t.startswith("[") else t)'; }
newest_transcript="$(ui_answer_transcript 0)" || fail "the newest run's transcript is unreadable"
older_transcript="$(ui_answer_transcript 1)" || fail "the older run's transcript is unreadable"
expect_poll "the History page holds the keys" true ipc smoke activeFocusWithin window vgs.automations HistoryPage
expect "the newest run holds the selection" "$newest_transcript" ui_history_selected
expect "Down moves the selection" ok ui_keys -k Down
expect_poll "Down selects the older run" "$older_transcript" ui_history_selected
forget_record
expect "Return opens the selected run" ok ui_keys -k Return
expect_poll "Return hands the TUI the older run's transcript" "$older_transcript" ui_opened_transcript
expect "Up moves the selection back" ok ui_keys -k Up
expect_poll "Up selects the newest run" "$newest_transcript" ui_history_selected
forget_record
expect "Enter opens the selected run" ok ui_keys -k KP_Enter
expect_poll "Enter hands the TUI the newest run's transcript" "$newest_transcript" ui_opened_transcript

# Clear history: the button asks, Escape keeps the runs, Return clears.
expect "Clear history asks first" ok ui_click Button "Clear history"
expect_poll "the question shows" '"clear"' ui_confirm
expect "Escape dismisses the question" ok ui_keys -k Escape
expect_poll "the question is gone" '""' ui_confirm
expect "the dismissed question clears nothing" 2 auto_history_count smoke-ui
# The question's Dialog sits over a scrim that dismisses it on a click
# away; a click on the card's empty space, 3 px below its top edge in the
# padding above the title, leaves it open. The control turns the card's own
# area off through the probe, and the same click falls to the scrim. The
# click and the marker hover use the same sandbox pointer binary, so the
# marker is ordered after the click before the row reads the question.
dialog_card_click() {
  local card window x y
  card="$(ipc smoke dialogCard window vgs.automations)" || return 1
  [[ $card == \{* ]] || { echo "$card"; return 0; }
  window="$(surface_box window:Automations)" || return 1
  read -r x y < <(python3 -c 'import json,sys; c=json.loads(sys.argv[1])["box"]; w=json.loads(sys.argv[2]); print(int(w[0] + c[0] + c[2] / 2), int(w[1] + c[1] + 3))' "$card" "$window") || return 1
  hover "$x" "$((y + 1))" && click "$x" "$y" && echo ok
}
dialog_card_click_then_hover() { dialog_card_click >/dev/null || return 1; ui_hover "$1" "$2"; }
expect "Clear history asks for the card click" ok ui_click Button "Clear history"
expect_poll "the question shows for the card click" '"clear"' ui_confirm
expect "the Dialog card click and following hover are sent" ok dialog_card_click_then_hover Button Cancel
expect_poll "the marker hover reaches the question after the Dialog card click" true ui_hovered Button Cancel
expect "a click on the Dialog card's empty space leaves the question open" '"clear"' ui_confirm
expect "control: the probe turns the card's own area off" true ipc smoke setDialogCard window vgs.automations false
expect "control: the same click and following hover are sent" ok dialog_card_click_then_hover Button "Clear history"
expect_poll "control: the marker hover reaches the page after dismissal" true ui_hovered Button "Clear history"
expect_poll "control: the same click falls to the scrim, which dismisses the question" '""' ui_confirm
expect "the card's own area is on again" false ipc smoke setDialogCard window vgs.automations true
expect "Clear history asks again" ok ui_click Button "Clear history"
expect "Return confirms" ok ui_keys -k Return
expect_poll "the CLI reads history cleared by the window" 0 auto_history_count smoke-ui

# The keyboard alone: back to the Automations tab, then Ctrl+N, typing,
# Tab and Ctrl+S create an automation with no pointer event; the arrows
# reach its row, Delete asks, Escape keeps it and Delete, Return remove it.
expect "the Automations tab opens" ok ui_click Label Automations
keyboard_create "(keyboard)" "Smoke keyboard" "printf keyboard"
expect_poll "the CLI reads the keyboard-created automation" '"printf keyboard"' auto_row_value smoke-keyboard command
expect "Escape leaves the editor" ok ui_keys -k Escape
expect_poll "the list is shown again" false ui_editor_open
keyboard_row_index() { auto_rows_json | py_reply 'import json,sys; print([r["id"] for r in json.load(sys.stdin)].index(sys.argv[1]))' smoke-keyboard; }
list_current() { ipc smoke readInstance window vgs.automations listCurrent; }
select_keyboard_row() {
  local want i
  want="$(keyboard_row_index)" || return
  type_keys -k Home || return
  for ((i = 0; i < want; i++)); do type_keys -k Down || return; done
  list_current
}
expect_poll "the arrows select the keyboard row" "$(keyboard_row_index)" select_keyboard_row
expect "Delete asks to remove it" ok ui_keys -k Delete
expect_poll "the remove question shows" '"remove"' ui_confirm
expect "Escape keeps it" ok ui_keys -k Escape
expect_poll "the remove question is gone" '""' ui_confirm
expect "the kept automation remains" present auto_row_exists smoke-keyboard
expect "Delete asks again" ok ui_keys -k Delete
expect_poll "the remove question shows again" '"remove"' ui_confirm
expect "Return removes it" ok ui_keys -k Return
expect_poll "the CLI reads the keyboard-created automation removed" absent auto_row_exists smoke-keyboard

# The row menu removes the pointer-created automation.
expect "the row's menu opens" ok ui_click_in_row "Smoke UI" IconButton "More actions"
expect "a typed R and Return choose the menu's Remove" ok ui_keys r -k Return
expect_poll "the menu's remove question shows" '"remove"' ui_confirm
expect "Return removes it" ok ui_keys -k Return
expect_poll "the UI-created automation is gone before the controls" absent auto_row_exists smoke-ui

expect "Run now starts" started=nightly automations run-now nightly
expect "Run now goes through systemd-run" '["--user", "--collect", "--quiet"]' last_systemd_run_prefix
expect "the failure sends the error notification with its hints" '["x-vgs-avatar=calendar-clock", "x-vgs-icon=circle-x", "x-vgs-tone=danger", "x-vgs-click=open", "x-vgs-open=<path>"]' auto_hints
expect_poll "the run's records reach Last runs" danger auto_status_tone lastRuns

forget_record
expect "the linger IPC opens its TUI" ok ipc vgs.automations invoke linger ""
expect_poll "the terminal is handed the linger TUI" "$(words vgs.automations/linger tui/linger.sh)" recorded_tail
expect_run_end "the linger IPC's run ends" vgs.automations/linger

# Enable while logged out, D061: while lingering reads off, the Setup tab
# offers the declared action on the linger step, which reads Optional, on
# no Settings field. Its text link opens the linger TUI.
# The run's end lists again, whoever opened it, and a loginctl that now
# answers yes withdraws the action. The control: the manager refuses the
# act once lingering is on, and starts nothing.
expected_errors+=('settings: vgs\.automations/linger refused: action=linger reason=not-offered')
settings_page_open vgs.automations
settings_setup
automation_linger_location() { ipc smoke setupRows window vgs.settings | py_reply 'import json,sys; print(json.dumps([[row["key"], row["chips"], [b["text"] for b in row["buttons"]]] for row in json.load(sys.stdin) if row["key"]=="linger"]))'; }
expect_poll "the linger action is on its optional Setup step" '[["linger", [["Optional", "neutral"]], ["Enable while logged out"]]]' automation_linger_location
expect_poll "lingering off offers Enable while logged out" '[["linger", "Enable while logged out", true]]' offered_actions vgs.automations
forget_record
# The stand-in terminal runs no linger TUI, so the row itself turns
# lingering on: a loginctl that answers show-user with yes stands over the
# harness's sentinel before the press, and the service reads it when the
# run ends. Any other verb it logs as the sentinel does, and the sentinel
# comes back after.
printf '#!/usr/bin/env bash\nif [[ ${1:-} == show-user ]]; then echo yes; exit 0; fi\nprintf "%%s\\n" "loginctl $*" >>%q\nexit 1\n' "$auth_log" | sentinel_stand_over "$shim/loginctl"
expect "loginctl resolves to the row's stand-in on the shell's PATH" "$shim/loginctl" shell_resolves loginctl
settings_press --type RowAction "Enable while logged out" || fail "the click on Enable while logged out failed"
expect_poll "Enable while logged out hands the terminal the linger TUI" "$(words vgs.automations/linger tui/linger.sh)" recorded_tail
expect_run_end "the button's linger run ends" vgs.automations/linger
expect_poll "the run's end lists again and lingering reads on" ok auto_status_tone linger
expect_poll "lingering on offers no action" '[["linger", "Enable while logged out", false]]' offered_actions vgs.automations
forget_record
expect "the manager refuses the act while lingering is on" "refused: action=linger reason=not-offered" settings_act vgs.automations linger
expect "the refused act started no terminal" absent recorded
settings_page_close vgs.automations
sentinel_restore "$shim/loginctl"

# The control: a copy whose service lists neither after a run file lands
# nor after the store changes, the one timer both watchers restart. It
# carries a marker the row waits on, so every reading is the copy's. The
# engine clears the history first, so the copy's own start reads no
# failure; an engine change to the store and the next failing run then
# leave its status as it was.
expect "the history is cleared before the control" cleared=1 automations clear --all
auto_copy="$home/.config/vgshell/plugins/vgs.automations"
mkdir -p "$auto_copy"
cp -R "$repo/shell/plugins/vgs.automations/." "$auto_copy/"
expected_errors+=('plugins: hidden by a higher-precedence plugin with the same id: vgs\.automations')
python3 - "$auto_copy/Service.qml" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
needle = "        onTriggered: root.request([\"list\", \"--json\"])\n    }\n\n    Timer {\n        id: refresh"
assert text.count(needle) == 1, "the listSoon timer's list must occur once"
text = text.replace(needle, "        onTriggered: root.smokeListSoonFired += 1\n    }\n\n    Timer {\n        id: refresh", 1)
marker = "    id: root\n"
assert text.count(marker) == 1, "the root id must occur once"
open(path, "w").write(text.replace(marker, marker + "    property bool smokeControl: true\n    property int smokeListSoonFired: 0\n", 1))
PY
# The same copy's window reaches the engine for no change and opens no
# transcript TUI: its engine door drops every write, and its transcript
# open returns before the core's TUI. The UI steps above, run against it,
# must leave the store, the history and the TUI record as they were.
python3 - "$auto_copy/Window.qml" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
marker = "    id: root\n"
assert text.count(marker) == 1, "the root id must occur once"
text = text.replace(marker, marker + "    property int smokeRunCalls: 0\n    property int smokeTranscriptCalls: 0\n", 1)
for old, new in (
    ("    function run(args, done) {\n", "    function run(args, done) {\n        smokeRunCalls += 1;\n        if (done !== undefined) done(false, \"\", \"\", {});\n        return;\n"),
    ('shell.tui.run("transcript", [path])', '(smokeTranscriptCalls += 1, "ok")'),
):
    assert text.count(old) == 1, old
    text = text.replace(old, new, 1)
open(path, "w").write(text)
PY
rescan "the control copy is scanned"
expect_poll "the control copy's service is built" true ipc smoke readInstance service vgs.automations smokeControl
expect_poll "the control copy's start reads no failure" ok auto_status_tone lastRuns
expect_poll "the control copy's start counts the automation" 1 auto_status active
control_service_before="$(auto_service_marker)" || fail "the control service marker is readable before store and run changes"
expect "the engine pauses the automation under the control" disabled=nightly auto_last disable nightly
expect "Run now starts under the control" started=nightly automations run-now nightly
expect_poll "the control service observed the store or run change" fired auto_service_marker_after "$control_service_before"
expect "the control's count misses the store change" 1 auto_status active
expect "the control's Last runs misses the run" ok auto_status_tone lastRuns
expect "the control copy's window summons" ok ipc shell summon window vgs.automations '{}'
expect_poll "the control copy's window maps" 1 window_count Automations
expect_poll "the control copy's window lists the automation" '["Nightly"]' ui_row_names
control_run_before="$(auto_window_run_marker)" || fail "the control window run marker is readable before pointer create"
expect "the pointer create runs under the control" ok ui_create "Smoke control" "echo control"
expect_poll "the control window received the pointer create" fired auto_window_run_after "$control_run_before"
expect "the control's pointer create reaches no store" absent auto_row_exists smoke-control
expect "Escape leaves the control's editor" ok ui_keys -k Escape
control_run_before="$(auto_window_run_marker)" || fail "the control window run marker is readable before the switch"
expect "a click on the control's switch runs" ok ui_click_in_row Nightly Switch ""
expect_poll "the control window received the switch click" fired auto_window_run_after "$control_run_before"
expect "the control's switch reaches no store" false auto_row_value nightly enabled
control_run_before="$(auto_window_run_marker)" || fail "the control window run marker is readable before keyboard create"
keyboard_create "(control)" "Smoke control keys" "printf control"
expect_poll "the control window received the keyboard create" fired auto_window_run_after "$control_run_before"
expect "the control's keyboard create reaches no store" absent auto_row_exists smoke-control-keys
expect "Escape leaves the control's editor again" ok ui_keys -k Escape
expect "the control's History tab opens" ok ui_click Label History
forget_record
control_transcript_before="$(auto_window_transcript_marker)" || fail "the control window transcript marker is readable before history click"
expect "a click on the control's history row runs" ok ui_click HistoryRow Nightly
expect_poll "the control window received the history click" fired auto_window_transcript_after "$control_transcript_before"
expect "the control's history click opens no TUI" absent recorded
expect "the control's Clear history asks" ok ui_click Button "Clear history"
control_run_before="$(auto_window_run_marker)" || fail "the control window run marker is readable before clear"
expect "Return confirms under the control" ok ui_keys -k Return
expect_poll "the control window received the clear request" fired auto_window_run_after "$control_run_before"
expect "the control's clear removes no run" 1 auto_history_count nightly
rm -r -- "$auto_copy"
rescan "the shipped plugin is scanned again"
expect_poll "the shipped service lists the paused automation" 0 auto_status active

auto_runs_dir="$(automations list --json | py_reply 'import json,sys; print(json.load(sys.stdin)["runsDir"])')" || fail "the engine's runs directory is unreadable"
auto_guard_dir="${auto_runs_dir%/runs}/guard"

# The private NetworkManager mock exposes the generic UpdateProperties
# interface, which emits PropertiesChanged. Only this mock changes; no
# CheckConnectivity or real device action belongs to this row. The fixed
# wall/monotonic clocks below exercise grace and the existing late rule
# without a sixty-second or ten-minute sleep.
nm_state() { "${shell_env[@]}" busctl --system --json=short get-property org.freedesktop.NetworkManager /org/freedesktop/NetworkManager org.freedesktop.NetworkManager Connectivity | py_reply 'import json,sys; print(json.load(sys.stdin)["data"])'; }
nm_set() { "${shell_env[@]}" busctl --system call org.freedesktop.NetworkManager /org/freedesktop/NetworkManager org.freedesktop.DBus.Mock UpdateProperties 'sa{sv}' org.freedesktop.NetworkManager 1 Connectivity u "$1" && echo ok; }
auto_records() { # ID KIND in the ordinary UI world
  python3 -c 'import glob,sys; print(len(glob.glob(sys.argv[1] + "/" + sys.argv[2] + "@*." + sys.argv[3] + ".json")))' "$auto_runs_dir" "$1" "$2"
}
auto_net="$sandbox/automations-network"
mkdir -p -- "$auto_net/home" "$auto_net/config" "$auto_net/state" "$auto_net/data" "$auto_net/run"
chmod 700 -- "$auto_net/run"
cat >"$auto_net/clock.js" <<'EOF'
const fs = require("fs");
const clock = () => JSON.parse(fs.readFileSync(process.env.NETWORK_CLOCK, "utf8"));
const RealDate = Date;
global.Date = class extends RealDate {
    constructor(...args) { super(...(args.length ? args : [clock().now])); }
    static now() { return clock().now; }
};
process.hrtime.bigint = () => BigInt(clock().mono) * 1000000n;
EOF
auto_net_due=1793350800000 # 2026-10-30 09:00 UTC, read by the fixture schedule below
auto_net_clock() {
  printf '{"now":%s,"mono":%s}\n' "$1" "$2" >"$auto_net/clock.next"
  mv -- "$auto_net/clock.next" "$auto_net/clock.json"
}
auto_net_env=("${shell_env[@]}" PATH="$shell_path" HOME="$auto_net/home" XDG_CONFIG_HOME="$auto_net/config" XDG_STATE_HOME="$auto_net/state" XDG_DATA_HOME="$auto_net/data" XDG_RUNTIME_DIR="$auto_net/run" NETWORK_CLOCK="$auto_net/clock.json" NODE_OPTIONS="--require=$auto_net/clock.js" TZ=UTC)
auto_net_cli() { "${auto_net_env[@]}" "$auto_engine" --tree "$repo" "$@" 2>>"$sandbox/automations-network.err"; }
auto_net_last() { local out; out="$(auto_net_cli "$@")" || return; printf '%s\n' "${out##*$'\n'}"; }
auto_net_add() {
  auto_net_last add --definition '{"name":"'"$1"'","command":"true","requiresNetwork":true,"catchUp":'"$2"',"schedule":{"frequency":"daily","interval":1,"times":["09:00"],"start":"2026-10-30","end":{"type":"never"},"zone":"utc"}}' || return
  printf '{"handledThrough":0}\n' >"$auto_net/state/vgshell/automations/guard/$3.json"
}
auto_net_value() {
  auto_net_cli list --json | py_reply 'import json,sys; r=next(r for r in json.load(sys.stdin)["automations"] if r["id"]==sys.argv[1]); value=r
for part in sys.argv[2].split("."): value=value.get(part) if isinstance(value,dict) else None
print(json.dumps(value))' "$1" "$2"
}
auto_net_marker() { [[ -e $auto_net/state/vgshell/automations/runs/$1.pending.json ]] && echo present || echo absent; }
auto_net_records() { python3 -c 'import glob,sys; print(len(glob.glob(sys.argv[1]+"/"+sys.argv[2]+"@*."+sys.argv[3]+".json")))' "$auto_net/state/vgshell/automations/runs" "$1" "$2"; }
auto_net_ending() {
  python3 - "$auto_net/state/vgshell/automations/runs" "$1" <<'PYEND'
import glob,json,sys
files=glob.glob(sys.argv[1]+"/"+sys.argv[2]+"@*.ended.json")
if len(files)!=1:
    print("records="+str(len(files))); raise SystemExit
r=json.load(open(files[0]))
print(json.dumps([r["outcome"],r["reason"],r["slot"],r["durationMs"]]))
PYEND
}
# This is the assertion the FULL-bypass control must fail: an acknowledged
# waiting marker cannot coexist with a started command.
auto_net_prerequisite() {
  local pending started
  pending="$(auto_net_value "$1" state)" || return
  started="$(auto_net_records "$1" started)" || return
  [[ $pending == '"waiting"' && $started == 0 ]] && echo waiting || echo rejected
}
auto_net_spawn() {
  spawn "$sandbox/automations-network-$2.err" "${auto_net_env[@]}" "$1" --tree "$repo" run --scheduled "$2"
}
if devices_ready automations; then
  auto_nm_original="$(nm_state)" || fail "the NetworkManager mock's Connectivity is unreadable"
  expect "the NetworkManager mock reads NONE" ok nm_set 1
  auto_net_clock "$((auto_net_due + 300000))" 0
  expect "the engine adds the reconnect fixture" added=net-reconnect auto_net_add "Net reconnect" true net-reconnect
  auto_net_spawn "$auto_engine" net-reconnect
  expect_poll "the reconnect attempt is waiting in grace" '"grace"' auto_net_value net-reconnect pending.diagnostic
  expect "a non-FULL prerequisite starts no command" waiting auto_net_prerequisite net-reconnect
  expect "the NetworkManager mock reports FULL" ok nm_set 4
  expect_poll "the reconnect command ends once" 1 auto_net_records net-reconnect ended
  expect_poll "the ended reconnect owner clears its marker" absent auto_net_marker net-reconnect
  expect "another scheduled trigger handles no second run" '' auto_net_cli run --scheduled net-reconnect
  expect "the reconnect attempt ran once" 1 auto_net_records net-reconnect ended
  expect "the engine removes the reconnect fixture" removed=net-reconnect auto_net_last remove net-reconnect

  expect "the mock reads NONE for grace" ok nm_set 1
  expect "the engine adds the grace fixture" added=net-grace auto_net_add "Net grace" true net-grace
  auto_net_spawn "$auto_engine" net-grace
  expect_poll "the new attempt starts in grace" '"grace"' auto_net_value net-grace pending.diagnostic
  auto_net_clock "$((auto_net_due + 300000))" 60001
  expect "a LIMITED change wakes the grace attempt" ok nm_set 3
  expect_poll "active grace expiry becomes offline" '"offline"' auto_net_value net-grace pending.diagnostic
  expect "active grace expiry never grants offline admission" waiting auto_net_prerequisite net-grace
  expect "Cancel invalidates only the waiting attempt" cancelled=net-grace auto_net_cli cancel net-grace
  expect_poll "Cancel has a neutral ended record" '["skipped", "cancelled-before-start", 1793350800000, 0]' auto_net_ending net-grace
  expect "the engine removes the grace fixture" removed=net-grace auto_net_last remove net-grace

  auto_net_clock "$((auto_net_due + 300000))" 0
  expect "the mock reads NONE for the late fixture" ok nm_set 1
  expect "the engine adds the ordinary missed-rule fixture" added=net-late auto_net_add "Net late" false net-late
  auto_net_spawn "$auto_engine" net-late
  expect_poll "the late fixture first waits" '"grace"' auto_net_value net-late pending.diagnostic
  auto_net_clock "$((auto_net_due + 600001))" 60001
  expect "a property change wakes the now-late attempt" ok nm_set 2
  expect_poll "the ordinary late rule records a neutral skip while offline" '["skipped", "network-offline-late", 1793350800000, 0]' auto_net_ending net-late
  expect "a late skip starts no command" 0 auto_net_records net-late started
  expect "the engine removes the late fixture" removed=net-late auto_net_last remove net-late

  # Disposable control outside the checkout. Keep the FULL decision text
  # but bypass its branch, then require the same prerequisite assertion to
  # reject a command admitted with Connectivity NONE.
  auto_net_control="$(mktemp -d)" || fail "the FULL control scratch could not be created"
  cp -R -- "$repo/shell/plugins/vgs.automations" "$auto_net_control/vgs.automations"
  python3 - "$auto_net_control/vgs.automations/bin/automations" <<'PYCONTROL'
import pathlib,sys
p=pathlib.Path(sys.argv[1]); before=p.read_text(); needle="if (!admission.admit) {"
assert before.count(needle)==1
result=before.replace(needle,"if (false && !admission.admit) {",1)
assert result!=before
p.write_text(result)
PYCONTROL
  auto_net_clock "$((auto_net_due + 300000))" 0
  expect "the mock reads NONE for the FULL control" ok nm_set 1
  expect "the engine adds the FULL control fixture" added=net-control auto_net_add "Net control" true net-control
  auto_net_spawn "$auto_net_control/vgs.automations/bin/automations" net-control
  expect_poll "the control reaches the forbidden command start" 1 auto_net_records net-control started
  expect "the prerequisite assertion rejects the bypassed FULL guard" rejected auto_net_prerequisite net-control
  expect_poll "the control command ends before its scratch is removed" 1 auto_net_records net-control ended
  expect "the engine removes the FULL control fixture" removed=net-control auto_net_last remove net-control
  rm -rf -- "${auto_net_control:?}"

  # The ordinary UI world receives a real manual wait with a deliberately
  # absent private bus address for that runner alone. Window and Service
  # retain the sandbox buses and read its diagnostic through normal list.
  expect "the engine adds the visible manual fixture" added=network-manual auto_last add --definition '{"name":"Network manual","command":"true","requiresNetwork":true,"schedule":{"frequency":"daily","interval":1,"times":["09:00"],"start":"2026-01-01","end":{"type":"never"}}}'
  spawn "$sandbox/automations-manual-unavailable.err" "${shell_env[@]}" PATH="$shell_path" DBUS_SYSTEM_BUS_ADDRESS="unix:path=$sandbox/no-network-bus" "$auto_engine" --tree "$repo" run --manual network-manual
  expect_poll "the manual attempt reports unavailable" '"unavailable"' auto_row_value network-manual pending.diagnostic
  expect "the real window summons for the waiting manual run" ok ipc shell summon window vgs.automations '{}'
  expect_poll "the real window maps for the pending run" 1 window_count Automations
  auto_ui_pending() { ipc smoke readInstance window vgs.automations automations | py_reply 'import json,sys; r=next((r for r in json.load(sys.stdin) if r["id"]=="network-manual"),None); print(json.dumps([r["state"],r["pending"]["trigger"],r["pending"]["diagnostic"]]) if r and r.get("pending") else "absent")'; }
  expect_poll "the row exposes a visible unavailable manual wait" '["waiting", "manual", "unavailable"]' auto_ui_pending
  expect "the waiting row opens its editor" ok ui_click AutomationRow "Network manual"
  expect_poll "the editor follows the pending manual attempt" '"network-manual"' ui_draft id
  auto_ui_editor_pending() { ipc smoke readInstance window vgs.automations draftPending | py_reply 'import json,sys; r=json.load(sys.stdin); print(json.dumps(r["diagnostic"]) if r else "absent")'; }
  expect_poll "the editor exposes its unavailable diagnostic" '"unavailable"' auto_ui_editor_pending
  expect "the editor's one-click Cancel runs" ok ui_click RowAction "Cancel waiting run"
  expect_poll "Cancel ends the manual wait without starting a command" 1 auto_records network-manual ended
  expect "the cancelled manual attempt has no started record" 0 auto_records network-manual started

  # A real systemd manager takes ownership before returning. For this one
  # Test run, its private stand-in only records and acknowledges the launch;
  # the harness then starts exactly that recorded argv as a peer. A child
  # of EngineClient would be reaped by its Process lifetime on return.
  cp -- "$shim/systemd-run" "$auto_net/systemd-run.saved"
  cat >"$shim/systemd-run" <<EOFTEST
#!/usr/bin/env bash
python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "\$@" >>"$auto_stub/systemd-run.calls"
exit 0
EOFTEST
  expect_poll "the editor clears its cancelled pending answer" null ipc smoke readInstance window vgs.automations draftPending
  expect "the editor's Test run requests the real runner" ok ui_click Button "Test run"
  auto_ui_test_requested() { tail -n 1 -- "$auto_stub/systemd-run.calls" | py_reply 'import json,sys; a=json.load(sys.stdin); print(json.dumps(a[-3:]))'; }
  expect_poll "Test run records the manual runner argv" '["run", "--manual", "network-manual"]' auto_ui_test_requested
  auto_test_words_file="$auto_net/test-run.words"
  python3 - "$auto_stub/systemd-run.calls" >"$auto_test_words_file" <<'PYWORDS'
import json,sys
args=json.loads(open(sys.argv[1]).read().splitlines()[-1]); cut=args.index("--")
pairs=[a.split("=",1)[1] for a in args[:cut] if a.startswith("--setenv=")]
assert len(pairs)==3
assert args[-3:]==["run","--manual","network-manual"]
for word in pairs+args[cut+1:]:
    sys.stdout.buffer.write(word.encode()+b"\0")
PYWORDS
  mapfile -d '' -t auto_test_words <"$auto_test_words_file"
  spawn "$sandbox/automations-test-run-unavailable.err" "${shell_env[@]}" PATH="$shell_path" DBUS_SYSTEM_BUS_ADDRESS="unix:path=$sandbox/no-network-bus" "${auto_test_words[@]}"
  expect_poll "Test run follows its visible unavailable wait" '"unavailable"' auto_ui_editor_pending
  expect "a waiting Test run has no false running result" null ipc smoke readInstance window vgs.automations testRun
  expect "Test run's one-click Cancel runs through the queued engine" ok ui_click RowAction "Cancel waiting run"
  expect_poll "Cancel finalizes the second manual attempt" 2 auto_records network-manual ended
  expect "neither manual wait starts a command" 0 auto_records network-manual started
  mv -- "$auto_net/systemd-run.saved" "$shim/systemd-run"
  expect "Escape returns from the cancelled editor" ok ui_keys -k Escape
  expect "the engine removes the visible manual fixture" removed=network-manual auto_last remove network-manual
  expect "the NetworkManager mock gets back the Connectivity the row found" ok nm_set "$auto_nm_original"
fi

# One notice for a failing automation: three failing runs and a success,
# whose notify-send calls show the second and third failure and the
# recovered notice each replacing the id the stand-in printed for the
# first. A notice is replaced only on the server that showed it, so this
# needs the shell to own org.freedesktop.Notifications on the sandbox's
# session bus, which it holds from the capabilities row's notification
# server on (shell/Core/NotificationHub.qml).
auto_notifications_owned() { "${shell_env[@]}" busctl --user --json=short call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus NameHasOwner s org.freedesktop.Notifications; }
auto_manual() { if automations run --manual "$1"; then echo exit=0; else echo "exit=$?"; fi; }
# auto_notices_since N: each notify-send call after the first N as its
# urgency, the id it replaces (null for none) and its summary.
auto_notices_since() {
  python3 - "$auto_stub/notify-send.calls" "$1" <<'PY'
import json, sys
calls = [json.loads(line) for line in open(sys.argv[1])][int(sys.argv[2]):]
flag = lambda call, name: next((a.split("=", 1)[1] for a in call if a.startswith("--" + name + "=")), None)
print(json.dumps([[flag(c, "urgency"), flag(c, "replace-id"), c[-2]] for c in calls]))
PY
}
expect "the shell owns the sandbox's notification server name" '{"type":"b","data":[true]}' auto_notifications_owned
auto_streak_flag="$sandbox/automations-streak-fails"
: >"$auto_streak_flag"
expect "the engine adds an automation that fails while the flag exists" added=smoke-streak auto_last add --definition '{"name": "Smoke streak", "command": "test ! -e '"$auto_streak_flag"'", "schedule": {"frequency": "weekly", "interval": 2, "weekdays": ["mon"], "times": ["03:00"], "start": "2026-01-05", "end": {"type": "never"}}}'
auto_sent_before="$(python3 -c 'import os,sys; print(sum(1 for _ in open(sys.argv[1])) if os.path.exists(sys.argv[1]) else 0)' "$auto_stub/notify-send.calls")" || fail "the notify-send calls are unreadable"
for auto_round in 1 2 3; do expect "failing run $auto_round" exit=1 auto_manual smoke-streak; done
rm -- "$auto_streak_flag"
expect "the run after the failures succeeds" exit=0 auto_manual smoke-streak
expect "the failures keep one notice, replaced each time, and the success replaces it as recovered" '[["critical", null, "Smoke streak failed"], ["critical", "7", "Smoke streak failed"], ["critical", "7", "Smoke streak failed"], ["low", "7", "Smoke streak recovered"]]' auto_notices_since "$auto_sent_before"
expect "the engine removes the failing automation" removed=smoke-streak auto_last remove smoke-streak

expect "the engine removes the automation" removed=nightly auto_last remove nightly
expect "its units are gone" '[]' auto_units
expect "disabling the automations is allowed" ok ipc shell setPluginEnabled vgs.automations false
expect_poll "the disabled service holds no status record or IPC target" '[null, false]' auto_lent
automations_stand_ins_restore "$auto_stub"
smoke_row_abandon=()
