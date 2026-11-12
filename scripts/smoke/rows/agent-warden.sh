# vgs.agent-warden, shell/plugins/vgs.agent-warden/README.md § How it works. The service is the one reader of the warden's
# status file. The row writes vsys's own fixture documents into the
# sandbox's runtime dir, $rt_dir/agent-warden/status.json, each replaced by
# rename as the warden replaces it, with its time and its events' set to
# now, so it is fresh, or ten minutes back, so it is stale. It reads each
# state back through the plugin's `status` IPC function, which answers the
# record the core holds: the state, its reason, each item's kind and level
# as vsys gave them, and the levels of the summary's causes. It reads each
# state: not set up, calm, information only, a warning, a problem, and not
# checking for each of its reasons, and the plugin's Settings rows from
# the Settings window. An empty directory reads as Not set up. The vsys
# requirement reads missing or present from the scan as a stand-in on the
# sandbox PATH comes and goes; the host's PATH sets its first answer. The
# stand-in vsys answers `--once --summary` from a file the row writes, a
# summary that finds nothing or one memory warning in vsys's own wording,
# and fails, or exits 2 after the summary, while a flag file exists. The
# service runs it once for each status and when vsys comes or goes, so the
# row writes the summary before the status that reads it, and every 30 s
# while the flyout is open and no fresh status comes, so a summary that
# changes while the warden is not set up reaches the open flyout's state
# with no status written. The Settings
# page draws a step only while the step applies: none anywhere while the
# warden checks and vsys is present, Set up while the warden is not set
# up, and Review all missing or outdated tools on the Tools step and the
# Warden setup step while vsys is missing. A status written 85 s back and
# left unchanged turns stale on the service's own timer, with no file
# change.
# The shield in the bar and its panel are read back as drawn for each
# state: the icon, tone, count and tooltip, every text the panel draws and
# the memory meter's fill, the calm shield's grey. A warning row names its
# problem in vsys's words with its actions as links, and the summary's
# warning is a row of its own whose title draws as plain text. An item's
# action and a summary row's action hand the stand-in terminal the vsys
# TUI's argv with the action's arguments, Open vsys with none, and Set up
# the setup TUI's, which runs neither script
# (scripts/test-agent-warden-tui.sh runs them); Start checks hands a
# stand-in systemctl its arguments, and, on a host without vsys, Install
# vsys raises the core's notice, which the scan that finds vsys closes. A
# summary that exits 2 still draws its row, and one that fails drops it.
# A stand-in notify-send records every notice. The service touches the
# warden's heartbeat while a status reads, and again at once when one
# reads after an unreadable one. It sends one notice per item across
# ticks, and again after the item clears, as Agent Warden with its
# level's urgency and the item's actions, sends information only under
# notify: everything and nothing under notify: off, and a press on a
# notice's first action hands the stand-in terminal the vsys TUI's argv.
# Controls are copies of the plugin installed over the bundled one: a
# logic copy that ignores staleness reads the stale document as calm, a
# service copy whose timer derives nothing keeps the ageing status calm
# past its stale moment, a panel copy without its plain rows and neutral
# meter draws the summary's title in the default text format and the
# meter in another colour, a service copy that keeps its causes after a
# failed summary still counts the warning, a notices copy without episode
# memory sends a lane's notice again on its next tick, and a service copy
# that ignores failed delivery keeps the failed episode.
# The harness starts the plugin disabled; the row ends with it disabled,
# its runtime files gone and no stub on PATH.
# inputs: shell/plugins/vgs.agent-warden/* shell/plugins/vgs.settings/manifest.json shell/plugins/vgs.settings/Window.qml shell/plugins/vgs.settings/ListPage.qml shell/plugins/vgs.settings/PluginPage.qml shell/plugins/vgs.settings/PageHeader.qml shell/plugins/vgs.settings/EditSet.qml shell/plugins/vgs.settings/Steps.js shell/Ui/controls/SettingField.qml shell/plugins/vgs.settings/KeyField.qml shell/plugins/vgs.settings/StatusRow.qml shell/plugins/vgs.settings/StatusLine.qml shell/plugins/vgs.settings/RequirementRow.qml shell/Ui/controls/InfoButton.qml shell/Ui/controls/Field.qml shell/Ui/controls/RowAction.qml shell/Ui/controls/FormRow.qml shell/Ui/feedback/Dialog.qml shell/Ui/overlay/Popover.qml shell/Commons/Reply.js scripts/smoke/fixtures/agent-warden/* scripts/smoke/fixtures/plugins/acme.probe/* shell/Core/PluginLogic.js shell/Core/ConfigLogic.js shell/Core/Registry.qml shell/Core/PluginStatus.qml shell/Core/Notices.qml shell/Core/Notifier.qml shell/Core/TuiRunner.qml scripts/smoke/rows/manager.sh bin/vgshell-tui shell/Commons/Duration.js shell/Commons/qmldir shell/plugins/vgs.notifications/manifest.json shell/plugins/vgs.notifications/Service.qml
set -euo pipefail
warden_probe_was="$(plugin_enabled acme.probe)"
expect "the fixture holds the notification server for Warden core sends" ok ipc shell setPluginEnabled acme.probe true
expect_poll "the Warden notification fixture service is built" True record_exists acme.probe
warden_copy="$home/.config/vgshell/plugins/vgs.agent-warden"
rm -rf -- "$warden_dir"
# warden_raw TEXT: TEXT as status.json, replaced into place by rename.
warden_raw() { printf '%s' "$1" >"$warden_dir/status.tmp.raw" && mv -T -- "$warden_dir/status.tmp.raw" "$warden_dir/status.json"; }
warden_values() { ipc vgs.agent-warden invoke status ''; }
# warden_value KEY: one published value as JSON, `null` when unpublished.
warden_value() { warden_values | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin).get(sys.argv[1])))' "$1"; }
# warden_step KEY: warden_value without the value's hint, which is copy.
warden_step() { warden_values | py_reply 'import json,sys; v=json.load(sys.stdin).get(sys.argv[1]); print(json.dumps(v if v is None else {k: v[k] for k in v if k != "hint"}))' "$1"; }
# The published detail's state and reason, each item's kind and level, and
# the levels of the summary's causes, null while none was read.
warden_state() { warden_values | py_reply 'import json,sys; d=json.load(sys.stdin).get("detail"); print("unpublished" if d is None else json.dumps([d["state"], d["reason"], [[i["kind"], i["level"]] for i in d["items"]], None if d["causes"] is None else [c["level"] for c in d["causes"]]]))'; }
warden_lent() { ipc shell lent | py_reply 'import json,sys; r=json.load(sys.stdin)["status"].get("vgs.agent-warden"); print(json.dumps(r if r is None else r["keys"]))'; }
warden_rows() { settings_rows | py_reply 'import json,sys; r=[p for p in json.load(sys.stdin) if p["id"] == "vgs.agent-warden"][0]["status"]; print(json.dumps([[s["label"], s["report"], s["value"], s["tone"]] for s in r]))'; }
# The answer the scan gives for vsys on the sandbox PATH, as a requirement
# row's state.
vsys_on_path() { if [[ $(shell_resolves vsys) != none ]]; then echo present; else echo missing; fi; }
# The open Settings page as drawn. warden_detail_drawn: the texts of the
# Warden reading on the Details tab, a Field. warden_setup_drawn: the texts
# of the Warden setup step on the Setup tab, a Field. no_show_command
# checks the visible page for a Show command control. warden_tools_drawn
# reads the required Tools step's
# chip, explanation and offered text action.
warden_detail_drawn() { ipc smoke itemTexts window vgs.settings Field | py_reply 'import json,sys; r=[r for r in json.load(sys.stdin) if r and r[0] == "Warden"]; print(json.dumps(r[0] if len(r) == 1 else "rows=%d" % len(r)))'; }
warden_setup_drawn() { ipc smoke itemTexts window vgs.settings Field | py_reply 'import json,sys; r=[r for r in json.load(sys.stdin) if r and r[0] == "Warden setup"]; print(json.dumps(r[0] if len(r) == 1 else "rows=%d" % len(r)))'; }
no_show_command() { ipc smoke itemTexts window vgs.settings PluginPage | py_reply 'import json,sys; print(str(not any("Show command" in r for r in json.load(sys.stdin))).lower())'; }
warden_tools_drawn() { ipc smoke setupRows window vgs.settings | py_reply 'import json,sys; rows=[r for r in json.load(sys.stdin) if r["key"]=="required-tools"]; print(json.dumps([rows[0]["chips"], rows[0]["lines"], [b["text"] for b in rows[0]["buttons"]]]) if len(rows)==1 else "rows=%d" % len(rows))'; }
warden_info="Shows whether Agent Warden watches your agents and whether any needs your attention."
# The Warden setup step's own hint while vsys is missing.
warden_vsys_hint="Install vsys first. Agent Warden needs it."
# info_label TEXT: whether an open info dialog draws TEXT.
info_label() { ipc smoke popupItemGeometry window vgs.settings "" "" Label "$1" | py_reply 'import sys; print("shown" if sys.stdin.read().strip().startswith("[") else "absent")'; }
warden_info_dialog() { printf '%s|%s\n' "$(info_label Warden)" "$(info_label "$warden_info")"; }
warden_info_closed() { info_label "$warden_info"; }
warden_info_focus() { ipc smoke focused window vgs.settings | py_reply 'import json,sys; t=sys.stdin.read().strip(); print(t if not t.startswith("[") else json.dumps(json.loads(t)[:2]))'; }
info_close_click() {
  local rect x y
  rect="$(ipc smoke popupItemGeometry window vgs.settings Dialog "$1" Button Close)" || return 1
  [[ $rect == \[* ]] || { echo "info_close_click: no Close button in dialog $1: $rect" >&2; return 1; }
  read -r x y < <(at_centre window:Plugins "$rect") || return 1
  click "$x" "$y"
}
outside_surface_point() { # SURFACE
  local box monitors
  box="$(surface_box "$1")" || return 1
  [[ $box == \[* ]] || return 1
  monitors="$(hypr -j monitors)" || return 1
  python3 - "$box" "$monitors" <<'PY'
import json, sys

box = json.loads(sys.argv[1])
monitors = json.loads(sys.argv[2])
bx, by, bw, bh = [float(v) for v in box]
cx, cy = bx + bw / 2, by + bh / 2
mon = next((m for m in monitors if m["x"] <= cx <= m["x"] + m["width"] / m["scale"] and m["y"] <= cy <= m["y"] + m["height"] / m["scale"]), monitors[0])
mx, my = float(mon["x"]), float(mon["y"])
mw, mh = mon["width"] / mon["scale"], mon["height"] / mon["scale"]
margin = max(1, min(bw, bh) / 10)
def clamp(v, lo, hi): return min(max(v, lo), hi)
if bx - margin >= mx:
    x, y = bx - margin, cy
elif bx + bw + margin <= mx + mw:
    x, y = bx + bw + margin, cy
elif by - margin >= my:
    x, y = cx, by - margin
else:
    x, y = cx, by + bh + margin
print(round(clamp(x, mx, mx + mw - 1)), round(clamp(y, my, my + mh - 1)))
PY
}
# The core's notify-send stand-in records each notification and returns
# primary transport action when the row presses Open vsys.
warden_sent="$sandbox/warden-notify-send"
warden_press="$sandbox/warden-press"
warden_delivery_fails="$sandbox/warden-delivery-fails"
cat >"$shim/notify-send" <<EOF
#!/usr/bin/env bash
python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "\$@" >>"$warden_sent"
if [[ -e "$warden_delivery_fails" ]]; then exit 17; fi
if [[ -e "$warden_press" ]]; then echo default; fi
EOF
chmod 755 "$shim/notify-send"
# The calls the stand-in recorded.
warden_sent_count() { if [[ -f $warden_sent ]]; then wc -l <"$warden_sent"; else echo 0; fi; }
# warden_notices_since N: each call after the first N as [urgency, title,
# whether it offers Open vsys], sorted, one JSON list. The runs one status
# starts write in any order. A record still being appended has no newline
# yet, so these readers ignore that last record until the next poll.
warden_record_read() {
  python3 - "$warden_sent" "$@" <<'PY'
import json, os, sys

def records(path):
    if not os.path.exists(path):
        return []
    text = open(path).read()
    lines = text.split("\n")[:-1]
    return [json.loads(line) for line in lines]

calls = records(sys.argv[1])[int(sys.argv[2]):]
print(json.dumps(sorted([next(x.split("=", 1)[1] for x in a if x.startswith("--urgency=")), a[a.index("--") + 1], any(x.startswith("--action=") for x in a)] for a in calls)))
PY
}
warden_notices_since() { warden_record_read "$1"; }
warden_whole_line_control() {
  local planted="$sandbox/warden-cut-records"
  printf '%s\n' '["--app-name=Agent Warden", "--urgency=low", "--", "Whole", "body"]' >"$planted"
  printf '%s' '["--app-name=Agent Warden", "--urgency=low", "--", "Cut' >>"$planted"
  (warden_sent="$planted"; warden_notices_since 0)
}
expect "control: the whole-line notice reader ignores a cut final record" '[["low", "Whole", false]]' warden_whole_line_control
# The heartbeat as the warden reads it: `fresh` when the file holds a time
# in milliseconds and was written in the last 10 s, `stale` otherwise, or
# `absent`.
warden_heartbeat() {
  python3 - "$warden_dir/notifier" <<'PY'
import os, sys, time
path = sys.argv[1]
if not os.path.exists(path):
    print("absent"); sys.exit()
text, now = open(path).read().strip(), time.time()
print("fresh" if text.isdigit() and abs(int(text) / 1000 - now) < 10 and now - os.stat(path).st_mtime < 10 else "stale")
PY
}
# The scan's answer for one of the plugin's requirement commands.
warden_requirement() { ipc shell listPlugins | py_reply 'import json,sys; p=[p for p in json.load(sys.stdin)["plugins"] if p["id"]=="vgs.agent-warden"][0]; print([r["state"] for r in p["requirements"] if r["name"]==sys.argv[1]][0])' "$1"; }
# The stand-in vsys, first on the shell's PATH while it exists. It answers
# `--once --summary` with the summary warden_summary_put wrote last; it
# fails while $warden_vsys_fails exists, and exits 2 after the summary
# while $warden_vsys_partial exists, as vsys does when it could not read a
# source.
warden_vsys_fails="$sandbox/warden-vsys-fails"
warden_vsys_partial="$sandbox/warden-vsys-partial"
warden_summary_file="$sandbox/warden-summary.json"
# The memory warning's title, as vsys words it (VSY-279), and the vsys
# arguments that open vsys at it.
warden_high="1 group is near the memory threshold"
warden_open_args=(--lane vsy-52)
# warden_summary_put quiet|memory: the summary the stand-in prints next,
# one that finds nothing or one memory warning whose programs are node,
# bash and node again, beside a scratch cause vsys skipped.
warden_summary_put() {
  local verdict='[]'
  [[ $1 == quiet ]] || verdict='[{"cause": "memory-high", "level": "warn", "subject": "/agents.slice/agent-warden-100-200.scope", "title": "'"$warden_high"'", "processes": [{"pid": 4242, "name": "node"}, {"pid": 4243, "name": "bash"}, {"pid": 4244, "name": "node"}], "open": ["--lane", "vsy-52"]}, {"cause": "scratch", "level": null, "subject": null}]'
  if ! { printf '{"schema": "vsys.summary.v2", "time": 1, "verdict": %s, "meters": [], "errors": []}\n' "$verdict" >"$warden_summary_file.tmp" &&
    mv -f -- "$warden_summary_file.tmp" "$warden_summary_file"; }; then
    fail "writing the stand-in vsys's $1 summary failed"
  fi
}
warden_vsys_stub() {
  cat >"$shim/vsys" <<SH
#!/usr/bin/env bash
[[ "\$*" == "--once --summary" ]] || exit 0
if [[ -e "$warden_vsys_fails" ]]; then echo "vsys: stand-in summary failed" >&2; exit 1; fi
cat -- "$warden_summary_file"
if [[ -e "$warden_vsys_partial" ]]; then exit 2; fi
SH
  chmod 755 "$shim/vsys"
}
expected_errors+=('agent-warden: status=unreadable cause=json ' 'agent-warden: status=schema schema=2\.0 ' 'agent-warden: status=old-vsys schema=1\.2 ' 'agent-warden: summary=failed ' 'plugins: hidden by a higher-precedence plugin with the same id: vgs\.agent-warden' 'agent-warden: notice=[^ ]+ refused: notify=busy')
expected_errors+=('notify: unsent plugin=vgs\.agent-warden exit=\{"code":17,"status":0\}')

rescan "a rescan after the notify-send stand-in arrives starts"
expect "enabling the agent warden is allowed" ok ipc shell setPluginEnabled vgs.agent-warden true
expect_poll "the agent warden's service is built" True record_exists vgs.agent-warden
expect_poll "no warden directory reads as not set up" '["not-set-up", null, [], null]' warden_state
expect "no status leaves the heartbeat alone" absent warden_heartbeat
expect "an absent status logs nothing" 0 log_lines 'agent-warden: status='
vsys_first="$(vsys_on_path)"
expect "the warden row says it is not set up with no action" '{"tone": "info", "text": "Not set up"}' warden_value warden
if [[ $vsys_first == present ]]; then
  expect "the setup row offers Set up while the warden is not set up" '{"tone": "warning", "text": "Not set up", "action": true}' warden_value setup
else
  expect "the setup row offers the missing tools' Review while vsys is missing" '{"tone": "warning", "text": "Not set up", "action": "tools"}' warden_step setup
fi
expect "no agent count is published before a status" null warden_value agents
expect "the lending record holds the published keys" '["detail", "setup", "warden"]' warden_lent
expect "the vsys requirement reads as the scan finds it on the sandbox PATH" "$vsys_first" warden_requirement vsys

calm_time="$(warden_put calm 0)"
expect_poll "a fresh calm status reads as calm" '["calm", null, [], null]' warden_state
expect_poll "a status that reads starts the heartbeat" fresh warden_heartbeat
expect "the warden row reads Running with no action" '{"tone": "ok", "text": "Running"}' warden_value warden
expect "the setup row reads Done with no action" '{"tone": "ok", "text": "Done"}' warden_value setup
expect "one agent runs in the calm status" 1 warden_value agents
expect "the last check is the status time" "$((calm_time * 1000))" warden_value lastCheck
expect "the lending record holds every declared key" '["agents", "detail", "lastCheck", "setup", "warden"]' warden_lent

# Each document replaces the last by rename, as the warden writes it. The
# state is the most serious level among vsys's items.
warden_put near-limit 0 >/dev/null
expect_poll "a lane near its limits is a warning" '["warn", null, [["near-limit", "warn"]], null]' warden_state
expect "the warden row says warnings need attention" '{"tone": "warning", "text": "Warnings need attention"}' warden_value warden
warden_put holding-off 0 >/dev/null
expect_poll "memory nearly full is a problem" '["danger", null, [["memory-full", "danger"]], null]' warden_state
expect "the warden row says problems need attention" '{"tone": "danger", "text": "Problems need attention"}' warden_value warden
warden_put leftover-idle 0 >/dev/null
expect_poll "idle leftover work is information" '["info", null, [["leftover", "info"]], null]' warden_state
expect "information leaves the warden row Running" '{"tone": "ok", "text": "Running"}' warden_value warden
warden_put reaped 600 >/dev/null
expect_poll "a status ten minutes old reads as not checking" '["not-checking", "stale", [], null]' warden_state
expect "the warden row says it stopped checking" '{"tone": "warning", "text": "Stopped checking"}' warden_value warden
# A fresh status the warden stops rewriting: the file stays as it is and
# the service's timer turns it stale at its time plus 90 s, which is about
# 5 s after the write. The poll allows 15 s.
warden_stamp() { stat -c '%i %Y' -- "$warden_dir/status.json"; }
# warden_ages LABEL: polls for up to 15 s until the unchanged status reads
# as stale, then checks the file was not replaced meanwhile.
warden_ages() {
  local stamp got="" i
  stamp="$(warden_stamp)" || { fail "$1: the status file is unreadable"; return; }
  for i in $(seq 1 75); do
    got="$(warden_state)" || got=""
    [[ $got == '["not-checking", "stale", [], null]' ]] && break
    sleep 0.2
  done
  if [[ $got != '["not-checking", "stale", [], null]' ]]; then fail "$1: got $got"; return; fi
  if [[ $(warden_stamp) == "$stamp" ]]; then ok "$1"; else fail "$1: the status file changed during the wait"; fi
}
warden_put calm 85 >/dev/null
expect_poll "a status 85 s old reads as calm" '["calm", null, [], null]' warden_state
warden_ages "the unchanged status turns stale at its moment"
warden_raw '{'
expect_poll "a status that is not JSON reads as not checking" '["not-checking", "unreadable", [], null]' warden_state
expect "the warden row says the status is unreadable" '{"tone": "danger", "text": "Could not read status"}' warden_value warden
expect_log "the unreadable status is logged" 1 'agent-warden: status=unreadable cause=json '
# The heartbeat stops while no status reads. The file goes now, so the
# write that starts it again is told apart from the next minute's.
rm -f -- "$warden_dir/notifier"
warden_raw '{"schema": "2.0"}'
expect_poll "a newer major reads as not checking" '["not-checking", "schema", [], null]' warden_state
expect_log "the unsupported major is logged" 1 'agent-warden: status=schema schema=2\.0 '
warden_raw '{"schema": "1.2"}'
expect_poll "a status from a vsys before items reads as not checking" '["not-checking", "old-vsys", [], null]' warden_state
expect "the warden row says vsys needs an update" '{"tone": "warning", "text": "Needs a newer vsys"}' warden_value warden
expect_log "the status from an older vsys is logged" 1 'agent-warden: status=old-vsys schema=1\.2 '
calm_time="$(warden_put calm 0)"
expect_poll "a fresh status after the refusals reads as calm again" '["calm", null, [], null]' warden_state
expect_poll "a status that reads again touches the heartbeat at once" fresh warden_heartbeat

# The Settings page draws the reading rows and setup row, never `detail`,
# and no status row for vsys, which the Tools step lists.
expect "the Settings window is summoned" ok ipc shell summon window vgs.settings '{}'
expect_poll "the Settings rows show the warden, setup, agents and last check" "$(python3 -c 'import json,sys; print(json.dumps([["Warden", "reported", {"tone": "ok", "text": "Running"}, "success"], ["Warden setup", "reported", {"tone": "ok", "text": "Done"}, "success"], ["Agents running", "reported", 1, ""], ["Last check", "reported", int(sys.argv[1]) * 1000, ""]]))' "$calm_time")" warden_rows
# Enabling a plugin with a missing required command raises its notice.
# The existing PATH stand-in satisfies it before the action refusal check.
expect_poll "enabling without vsys raises its required-command notice" '["vgs.agent-warden", ["vsys"], ["vsys"], false]' notice_shown
warden_summary_put quiet
warden_vsys_stub
rescan "a rescan after vsys arrives starts"
expect_poll "vsys reads as present" present warden_requirement vsys
expect_poll "the scan that finds vsys clears the enable notice" null notice_shown
# The control of Set up, D061: a warden that checks offers no Set up, the
# Warden reading declares no action, and the setup step refuses the act
# then.
expect_poll "a checking warden offers no Set up" '[["setup", "Set up", false]]' offered_actions vgs.agent-warden
expected_errors+=('settings: vgs\.agent-warden/warden refused: action=warden reason=undeclared' 'settings: vgs\.agent-warden/setup refused: action=setup reason=not-offered')
expect "the manager refuses the Warden reading because it declares no action" "refused: action=warden reason=undeclared" settings_act vgs.agent-warden warden
expect "the manager refuses Set up for a checking warden" "refused: action=setup reason=not-offered" settings_act vgs.agent-warden setup
expect "the refused act raised no notice" null notice_shown
expect "the Settings window is hidden" ok ipc shell hide window vgs.settings
expect_poll "the Settings window is gone" 0 window_count Plugins

# vsys follows the scan: a stub on the sandbox PATH is present after a
# rescan and gone after the next, and the service is not rebuilt. With the
# warden checking and vsys present nothing is left to set up, so the page
# draws the Warden setup step done with no command, the Warden reading on
# Details, the Tools step Done, and no install action. The
# control of Install all missing, D061: its call with nothing missing is
# refused and raises no notice.
settings_page_open vgs.agent-warden
settings_setup
expect_poll "a checking warden with vsys present offers no Set up" '[["setup", "Set up", false]]' offered_actions vgs.agent-warden
expect_poll "the Warden setup row draws Done and no action" "$(words "Warden setup" Done)" warden_setup_drawn
settings_details
expect_poll "the Warden reading draws Running and no step" "$(words Warden Running)" warden_detail_drawn
settings_press --type InfoButton "About Warden" Field Warden || fail "the click on the Warden row's info icon failed"
expect_poll "the Warden info dialog opens with its title and text" "shown|shown" warden_info_dialog
info_close_click Warden || fail "the click on the Warden info dialog's Close button failed"
expect_poll "the Warden info dialog closes from its Close button" absent warden_info_closed
expect_poll "the Warden info dialog returns focus to its icon after Close" '["InfoButton", "About Warden"]' warden_info_focus
settings_press --type InfoButton "About Warden" Field Warden || fail "the second click on the Warden row's info icon failed"
expect_poll "the Warden info dialog opens again for the outside press" "shown|shown" warden_info_dialog
read -r warden_info_outside_x warden_info_outside_y < <(outside_surface_point window:Plugins) || fail "the outside point for the Warden info dialog is unreadable"
click "$warden_info_outside_x" "$warden_info_outside_y" || fail "the outside press for the Warden info dialog failed"
expect_poll "a press outside closes the Warden info dialog" absent warden_info_closed
warden_info_unready() {
  (control_hovered() { echo false; }
   if settings_press --type InfoButton "About Warden" Field Warden 2>&1 >/dev/null; then echo pressed; fi)
}
expect "a scoped press the Warden row's info icon cannot take yet fails at the press with its cause" "settings_press: pointer-not-ready=InfoButton About Warden" warden_info_unready
# Observe the reveal request while forwarding the real IPC and click. The
# request must carry the same scope as the subsequent pointer lookup even
# when the page currently has only one matching InfoButton.
printf 'warden_reveal_%s\n' "$(declare -f ipc)" >"$sandbox/warden-reveal-ipc.sh"
declare -f settings_press | python3 -c 'import sys
text = sys.stdin.read()
before = "ipc smoke revealScopedText window vgs.settings \"$2\" \"$3\" \"$type\" \"$1\""
after = "ipc smoke revealText window vgs.settings \"$type\" \"$1\""
assert text.count(before) == 1, "scoped reveal control match"
changed = text.replace(before, after)
assert changed != text, "scoped reveal control unchanged"
print(changed)' >"$sandbox/warden-reveal-unscoped.sh" || fail "the unscoped settings_press control could not be written"
warden_scoped_reveal() {
  (
    source "$sandbox/warden-reveal-ipc.sh" || return 1
    ipc() {
      if [[ $1 == smoke && ( $2 == revealText || $2 == revealScopedText ) ]]; then
        printf '%s\n' "$@" >"$sandbox/warden-reveal-args"
      fi
      warden_reveal_ipc "$@"
    }
    settings_press --type InfoButton "About Warden" Field Warden || return 1
    cat -- "$sandbox/warden-reveal-args"
  )
}
warden_scoped_reveal_check() {
  expect "a scoped press reveals its own scope before pointing" $'smoke\nrevealScopedText\nwindow\nvgs.settings\nField\nWarden\nInfoButton\nAbout Warden' warden_scoped_reveal
}
warden_scoped_reveal_check
expect_poll "the scoped reveal regression opens Warden's info dialog" "shown|shown" warden_info_dialog
info_close_click Warden || fail "closing the scoped reveal regression's info dialog failed"
expect_poll "the scoped reveal regression's info dialog closes" absent warden_info_closed
warden_scoped_reveal_control() {
  (
    source "$sandbox/warden-reveal-unscoped.sh" || return 1
    failures=0 behaviour_failures=0
    warden_scoped_reveal_check >"$sandbox/warden-reveal-control.log"
    echo "$failures"
  )
}
expect "control: restoring page-wide reveal fails the same scope assertion" 1 warden_scoped_reveal_control
sed 's/^/  CONTROL  /' "$sandbox/warden-reveal-control.log"
expect_poll "the page-wide reveal control still reaches the real info button" "shown|shown" warden_info_dialog
info_close_click Warden || fail "closing the page-wide reveal control's info dialog failed"
expect_poll "the page-wide reveal control's info dialog closes" absent warden_info_closed
warden_first_absent() {
  (control_box() { echo absent; }
   if point_item scoped:Plugins window vgs.settings Field Warden InfoButton "About Warden" 2>&1 >/dev/null; then echo pointed; fi)
}
expect "a first absent box names its reading and lookup" "point_item: reading=first box=absent lookup=scoped:Plugins window vgs.settings Field Warden InfoButton About Warden" warden_first_absent
# The copy sits beside DismissScope, a type internal to qs.Ui, which the
# directory's own files reach and a file outside the module does not.
info_control_dir="$repo/shell/Ui/overlay"
python3 - "$repo/shell/Ui/controls/InfoButton.qml" "$info_control_dir/InfoButtonControl.qml" <<'PY'
import sys
src, dst = sys.argv[1:]
text = open(src).read()
needle = "onRejected: root.closeInfo()"
replacement = "onRejected: {}"
if text.count(needle) != 1:
    raise SystemExit("needle count is %d" % text.count(needle))
open(dst, "w").write(text.replace(needle, replacement))
PY
cat >"$info_control_dir/InfoButtonControlItem.qml" <<'QML'
import QtQuick

Item {
    id: root
    width: 240
    height: 80
    property bool opened: info.infoOpen
    function openInfo() { info.openInfo(Qt.TabFocusReason); }
    InfoButtonControl {
        id: info
        title: "Control"
        info: "Control copy without the Close action."
    }
}
QML
expect "the info dialog close control builds" ok ipc smoke popupLoad info-control "$info_control_dir/InfoButtonControlItem.qml" window vgs.settings '{}'
expect "the info dialog close control opens" ok ipc smoke popupCall info-control openInfo
expect_poll "the info dialog close control is open" true ipc smoke popupRead info-control opened
info_close_click Control || fail "the click on the control info dialog's Close button failed"
expect "control: an info dialog whose Close action is removed stays open" true ipc smoke popupRead info-control opened
expect "the info dialog close control is released" ok ipc smoke popupDrop info-control
rm -- "${info_control_dir:?}/InfoButtonControl.qml" "${info_control_dir:?}/InfoButtonControlItem.qml" || fail "removing the info dialog close control failed"
# The required Tools step stays visible after its tools are available.
settings_setup
expect_poll "Tools reads Done when every required tool is installed" '[[["Done", "success"]], ["Every required tool is installed"], []]' warden_tools_drawn
expect "the healthy page draws no Show command anywhere" true no_show_command
expected_errors+=('settings: vgs\.agent-warden/action:tools refused: requirements=vgs\.agent-warden reason=satisfied')
expect "the manager refuses Install all missing with nothing missing" "refused: requirements=vgs.agent-warden reason=satisfied" ipc smoke invokeInstance window vgs.settings installRequirements vgs.agent-warden
expect "the refused Install all missing raised no notice" null notice_shown
settings_page_close vgs.agent-warden
rm -f -- "$shim/vsys"
rescan "a rescan after vsys goes starts"
expect_poll "vsys reads as the host PATH gives it again" "$vsys_first" warden_requirement vsys

rm -f -- "$warden_dir/status.json"
expect_poll "an empty directory reads as not set up again" '["not-set-up", null, [], null]' warden_state

# The shield and its panel, read back as drawn. Enabling placed the widget
# in its default section. The shield is read as its icon, the
# Theme.color state role it draws in, its count and its tooltip; the panel
# as every text it draws, with the check time's number written N, and its
# memory meter as the state role its fill draws in. Stand-ins in the
# shell's own PATH directory: the stand-in vsys above, and a systemctl
# that records its arguments, so Start checks never reaches a user
# manager. The terminal is harness.sh's recording stand-in, written again
# over the one rows/updates.sh left.
warden_key="$(bar_key)"
warden_systemctl_log="$sandbox/warden-systemctl-argv"
# It stands over the harness's systemctl stand-in, which
# sentinel_restore puts back after the press.
warden_systemctl_stub() {
  sentinel_stand_over "$shim/systemctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$warden_systemctl_log"
EOF
}
warden_section() { ipc shell listShellConfig | py_reply 'import json,sys; l=json.load(sys.stdin)["bar"]["layout"]; print(([s for s in ("left","center","right") if any(e["id"]==sys.argv[1] for e in l.get(s,[]))] + ["none"])[0])' vgs.agent-warden; }
warden_tones="$(python3 -c 'import json,sys; print(json.dumps(dict(zip(["neutral", "warning", "danger"], [json.loads(v).lower() for v in sys.argv[1:]]))))' \
  "$(ipc smoke themeValue color.textMuted)" "$(ipc smoke themeValue color.warning)" "$(ipc smoke themeValue color.danger)")" || fail "the state colours are unreadable"
# The shield as [icon, tone, count, tooltip], or `absent`.
warden_shield() {
  local icon colours tip texts
  icon="$(ipc smoke readDescendant "$warden_key" vgs.agent-warden Icon name)" && colours="$(ipc smoke itemColours "$warden_key" vgs.agent-warden Widget Icon)" \
    && tip="$(ipc smoke readDescendant "$warden_key" vgs.agent-warden Tooltip text)" && texts="$(ipc smoke itemTexts "$warden_key" vgs.agent-warden Widget)" || return
  python3 - "$icon" "$colours" "$tip" "$texts" "$warden_tones" <<'PY'
import json, sys
icon, colours, tip, texts, tones = sys.argv[1:6]
if "absent" in (icon, colours, tip, texts):
    print("absent"); sys.exit()
colour = json.loads(colours)[0][0]
names = [name for name, value in json.loads(tones).items() if "#" + value[3:9] + value[1:3] == colour]
print(json.dumps([json.loads(icon), names[0] if len(names) == 1 else "colour=" + colour, (json.loads(texts)[0] + [""])[0], json.loads(tip)]))
PY
}
# `grey` while the panel's memory meter fills in the calm shield's grey,
# textMuted, `other` while it fills in another colour, `empty` when the
# probe finds no rectangle in it, or `absent` with no meter. Its track
# draws in the border colour. The probe matches a plain Rectangle by its
# class name, QQuickRectangle.
warden_meter() {
  local colours
  colours="$(ipc smoke itemColours panel vgs.agent-warden ProgressBar QQuickRectangle)" || return
  [[ $colours == \[\[* ]] || { echo absent; return; }
  python3 - "$colours" "$warden_tones" <<'PY'
import json, sys
colours, tones = json.loads(sys.argv[1])[0], json.loads(sys.argv[2])
grey = "#" + tones["neutral"][3:9] + tones["neutral"][1:3]
print("empty" if not colours else "grey" if grey in colours else "other")
PY
}
warden_panel_shown() { [[ $(ipc smoke readInstance panel vgs.agent-warden detail) != absent ]] && echo shown || echo hidden; }
warden_focused() { ipc smoke focused panel vgs.agent-warden | py_reply 'import json,sys; t=sys.stdin.read().strip(); print(t if not t.startswith("[") else json.dumps([json.loads(t)[1], json.loads(t)[2], json.loads(t)[3], json.loads(t)[4]]))'; }
# Every text the panel draws, or `absent`.
warden_panel() { ipc smoke itemTexts panel vgs.agent-warden Panel | py_reply '
import json, re, sys
t = sys.stdin.read().strip()
rows = [] if t == "absent" else json.loads(t)
print(json.dumps([re.sub(r"^Checked \d+[smhd] ago$", "Checked N ago", x) for x in rows[0]]) if rows else "absent")'; }
warden_systemctl_argv() { [[ -f $warden_systemctl_log ]] && cat -- "$warden_systemctl_log" || echo absent; }
# The notice the core shows as [plugin, commands], or null.
warden_notice() { notice_shown | py_reply 'import json,sys; s=json.load(sys.stdin); print(json.dumps(None if s is None else s[:2]))'; }
# warden_open LABEL: a click on the shield opens the panel.
warden_open() {
  click_centre "$warden_key" vgs.agent-warden || fail "$1: the click on the shield failed"
  expect_poll "$1: a click on the shield opens the panel" shown warden_panel_shown
}
# The stand-in summary's row: vsys's title with its full stop, its
# programs, each once, with no process id or scope unit, and Show in vsys,
# since the summary gives the place in vsys.
warden_row=("$warden_high." "The main programs are node and bash." "Show in vsys")
# The text format the panel draws the summary's title in, Text.PlainText
# being 0 and the default Text.AutoText 2
# (https://doc.qt.io/qt-6/qml-qtquick-text.html#textFormat-prop), or
# `absent` while no label draws it.
warden_title_format() { ipc smoke readMatchingDescendant panel vgs.agent-warden Label text "$warden_high." textFormat; }
warden_meter_calm="Agents use 38 GB and slow down at 64 GB."
warden_clear="vsys found no problems on this computer."

expect "enabling placed the shield in the bar's right section" right warden_section
expect_poll "the shield is built on the bar" '"vgs.agent-warden"' ipc smoke readInstance "$warden_key" vgs.agent-warden moduleName
terminal_stand_in
warden_summary_put memory
warden_vsys_stub
rescan "a rescan after the stand-in vsys arrives starts"
expect_poll "the stand-in vsys reads as present" present warden_requirement vsys
# vsys judges the computer apart from the warden: its warning is a row
# while the warden is not set up too, and the shield still asks for setup.
expect_poll "the arrival of vsys runs its summary" '["not-set-up", null, [], ["warn"]]' warden_state

expect_poll "the shield reads not set up" '["shield-question-mark", "neutral", "", "Agent Warden isn'"'"'t set up"]' warden_shield
# Keyboard-only path.
expect "the Agent Warden panel is closed before the keyboard path" ok ipc shell hide panel vgs.agent-warden
# The shortcut's summon has no anchor, so the panel is the summon host's
# layer, which covers the screen: a press on the desktop's bottom left
# corner, beside the centred panel, closes it (SummonLayer's catcher;
# rows/surfaces.sh holds the control).
expect "the Agent Warden shortcut opens the panel for an outside press" ok hypr dispatch 'hl.dsp.global("vgs.agent-warden:toggle")'
expect_poll "the shortcut's panel is one panel layer" 1 layer_count vgs:panel
summon_drawn panel vgs.agent-warden || fail "the shortcut's panel never drew before the outside press"
read -r warden_outside_x warden_outside_y < <(outside_surface_point vgs:panel) || fail "the outside point for the Agent Warden panel is unreadable"
click "$warden_outside_x" "$warden_outside_y" || fail "the press outside the Agent Warden panel failed"
expect_poll "a press on the desktop closes the shortcut's Agent Warden panel" hidden warden_panel_shown
expect_poll "the closed Agent Warden panel leaves no panel layer" 0 layer_count vgs:panel
expect "the Agent Warden shortcut opens the panel" ok hypr dispatch 'hl.dsp.global("vgs.agent-warden:toggle")'
expect_poll "the shortcut focuses the primary button without a ring" '["Set up", false, false, true]' warden_focused
forget_record
type_keys -k Down || fail "sending Down to the Agent Warden control failed"
expect "control: Down on the primary button runs no TUI" absent recorded_tail
type_keys -k Return || fail "sending Return to the focused Set up button failed"
expect_poll "Return on Set up hands the terminal the setup TUI" "$(words vgs.agent-warden/setup tui/setup.sh)" recorded_tail
expect_poll "the keyboard Set up hand-off closes the panel" hidden warden_panel_shown
expect_run_end "the keyboard setup run ends" vgs.agent-warden/setup
expect "the Agent Warden shortcut opens the panel for Escape" ok hypr dispatch 'hl.dsp.global("vgs.agent-warden:toggle")'
expect_poll "the Agent Warden panel is open before Escape" shown warden_panel_shown
type_keys -k Escape || fail "sending Escape to the Agent Warden panel failed"
expect_poll "Escape closes the Agent Warden panel" hidden warden_panel_shown
warden_open "not set up"
expect_poll "the not-set-up panel offers Set up, the summary's row and the link" "$(words Agents "Agent Warden isn't set up." "${warden_row[@]}" "Set up" "Open vsys")" warden_panel
click_item panel vgs.agent-warden Button "Set up" || fail "the click on Set up failed"
expect_poll "Set up hands the terminal the setup TUI" "$(words vgs.agent-warden/setup tui/setup.sh)" recorded_tail
expect_poll "the Set up hand-off closes the panel" hidden warden_panel_shown
expect_run_end "the setup run ends" vgs.agent-warden/setup

# Set up from the Settings page, D061: a warden not set up, with vsys
# present, offers Set up, and its button opens the same setup TUI. The
# same readers read the healthy page above as drawing neither.
settings_page_open vgs.agent-warden
settings_setup
expect_poll "a warden not set up offers Set up" '[["setup", "Set up", true]]' offered_actions vgs.agent-warden
expect_poll "the Warden setup row draws To do with Set up and its state explanation" "$(words "Warden setup" "To do" "Set up" "Not set up")" warden_setup_drawn
expect "the page draws no Show command control" true no_show_command
forget_record
settings_press --type RowAction "Set up" || fail "the click on the Settings page's Set up failed"
expect_poll "the Settings page's Set up hands the terminal the setup TUI" "$(words vgs.agent-warden/setup tui/setup.sh)" recorded_tail
expect_run_end "the Settings page's setup run ends" vgs.agent-warden/setup
settings_page_close vgs.agent-warden

# While no status comes and the flyout is open, the summary keeps its own
# pace, so a verdict that changes after the open reaches the not-set-up
# state with no status written. The wait allows one summary interval,
# 30 s, and the run.
warden_open "the summary's own pace"
warden_summary_put quiet
warden_unpaced() {
  local got="" i
  for i in $(seq 1 225); do
    got="$(warden_state)" || got=""
    [[ $got == '["not-set-up", null, [], []]' ]] && break
    sleep 0.2
  done
  if [[ $got == '["not-set-up", null, [], []]' ]]; then ok "$1"; else fail "$1: got $got"; fi
}
warden_unpaced "a summary that clears while the flyout is open and no status is written clears the not-set-up state's warning"
expect "the flyout of the summary's own pace is hidden" ok ipc shell hide panel vgs.agent-warden
expect_poll "the flyout of the summary's own pace is gone" hidden warden_panel_shown

# Fresh states, each status written after the summary it reads. The calm
# state and information alone draw the grey shield with a grey count and
# no warning; a warning draws yellow with its actions, and a problem red,
# each counted on the shield as in the heading.
warden_put calm 0 >/dev/null
expect_poll "a calm status under a summary that finds nothing reads as calm" '["calm", null, [], []]' warden_state
expect_poll "the shield reads calm with one agent" '["shield-check", "neutral", "1", "1 agent running within its limits"]' warden_shield
warden_open "calm"
expect_poll "the calm panel says so, with the meter, the summary's line and the link" \
  "$(words Agents "1 agent is running within its limits." "$warden_meter_calm" "$warden_clear" "Checked N ago" "Open vsys")" warden_panel
expect "the memory meter draws in the calm shield's grey" grey warden_meter
warden_put leftover-idle 0 >/dev/null
expect_poll "the shield reads information alone as calm" '["shield-check", "neutral", "1", "1 agent running within its limits"]' warden_shield
expect_poll "the information panel draws its row and its action" \
  "$(words Agents "1 agent is running within its limits." "Leftover work from 5 finished agents is still running." "5 processes. The warden stops it if it gets busy." "Show in vsys" "$warden_meter_calm" "$warden_clear" "Checked N ago" "Open vsys")" warden_panel
warden_put near-limit 0 >/dev/null
expect_poll "the shield reads a warning" '["shield-alert", "warning", "1", "claude in vsy-52 is near its memory and task limits"]' warden_shield
expect_poll "the warning panel draws its row with its actions" \
  "$(words Agents "1 warning needs your attention." "claude in vsy-52 is near its memory and task limits." "Memory: 50 of 64 GB; past it the system slows this agent. Tasks: 6200 of 8192 tasks; past it the agent cannot start processes." "Show in vsys" "Stop" "$warden_meter_calm" "$warden_clear" "Checked N ago" "Open vsys")" warden_panel
forget_record
click_item panel vgs.agent-warden RowAction "Stop" || fail "the click on the warning's Stop failed"
expect_poll "the warning's Stop hands the terminal the vsys TUI with the action's arguments" "$(words vgs.agent-warden/vsys tui/vsys.sh --lane agent-warden-100-200.scope --stop)" recorded_tail
expect_poll "the Stop hand-off closes the panel" hidden warden_panel_shown
expect_run_end "the vsys run from Stop ends" vgs.agent-warden/vsys

# The summary's warning is a row of its own, counted on the shield and in
# the heading, its title drawn as plain text.
warden_summary_put memory
warden_put calm 0 >/dev/null
expect_poll "a calm status under the summary's warning reads as a warning" '["warn", null, [], ["warn"]]' warden_state
expect_poll "the shield counts the summary's warning" '["shield-alert", "warning", "1", "'"$warden_high"'"]' warden_shield
warden_open "the summary's warning"
expect_poll "the panel draws the summary's warning as a row" \
  "$(words Agents "1 warning needs your attention." "${warden_row[@]}" "$warden_meter_calm" "Checked N ago" "Open vsys")" warden_panel
expect "the summary's title draws as plain text" 0 warden_title_format
# A summary that fails leaves no earlier verdict behind.
touch -- "$warden_vsys_fails"
warden_put calm 1 >/dev/null
expect_poll "a failed summary drops its row" '["calm", null, [], null]' warden_state
expect_poll "the panel after a failed summary draws no row and no summary line" \
  "$(words Agents "1 agent is running within its limits." "$warden_meter_calm" "Checked N ago" "Open vsys")" warden_panel
expect_log "the failed summary is logged" 1 'agent-warden: summary=failed '
rm -f -- "${warden_vsys_fails:?}"
# vsys exits 2 after the summary when it could not read a source; the
# summary still draws its row.
touch -- "$warden_vsys_partial"
warden_put calm 2 >/dev/null
expect_poll "the next summary, which exits 2, draws its row again" '["warn", null, [], ["warn"]]' warden_state
rm -f -- "${warden_vsys_partial:?}"
forget_record
click_item panel vgs.agent-warden RowAction "Show in vsys" || fail "the click on the summary row's Show in vsys failed"
expect_poll "the row's Show in vsys hands the terminal the vsys TUI with the summary's open" "$(words vgs.agent-warden/vsys tui/vsys.sh "${warden_open_args[@]}")" recorded_tail
expect_poll "the row's hand-off closes the panel" hidden warden_panel_shown
expect_run_end "the vsys run from the row ends" vgs.agent-warden/vsys

warden_put holding-off 0 >/dev/null
expect_poll "the shield reads a problem and a warning" '["shield-x", "danger", "2", "Agents are close to their memory limit"]' warden_shield
warden_open "a problem"
expect_poll "the problem panel draws the problem first, then the warning, and the meter past its point" \
  "$(words Agents "1 problem and 1 warning need your attention." "Agents are close to their memory limit." "73 of 80 GB in use. The warden holds back 1 agent until memory frees." "Show in vsys" "${warden_row[@]}" "Agents use 73 GB and are slowed down above 64 GB." "Checked N ago" "Open vsys")" warden_panel
# The warden's status cannot be read: the crossed shield with no count,
# the heading that says so, and the summary's row under it.
warden_raw '{'
expect_poll "an unreadable status under the summary's warning keeps its own state" '["not-checking", "unreadable", [], ["warn"]]' warden_state
expect_poll "the shield reads not checking with no count" '["shield-off", "neutral", "", "Agent Warden'"'"'s status can'"'"'t be read"]' warden_shield
expect_poll "the unreadable panel draws its heading and the summary's row" \
  "$(words Agents "Agent Warden's status can't be read." "${warden_row[@]}" "Open vsys")" warden_panel
forget_record
click_item panel vgs.agent-warden Button "Open vsys" || fail "the click on Open vsys failed"
expect_poll "Open vsys hands the terminal the vsys TUI with no arguments" "$(words vgs.agent-warden/vsys tui/vsys.sh)" recorded_tail
expect_poll "the Open vsys hand-off closes the panel" hidden warden_panel_shown
expect_run_end "the vsys run ends" vgs.agent-warden/vsys

# Notices, with the stand-in vsys present. A calm status first clears every
# episode the rows above opened. warden_ticks: a lane near its limits, the
# same lane a tick later, then memory nearly full, each read before the
# next is written; the row then reads what the stand-in notify-send was
# handed since MARK. Each notice is vsys's item: its title, the urgency of
# its level, and its actions as the notification's buttons.
warden_ticks() {
  local at
  at="$(warden_put near-limit 10)" || { fail "warden_ticks: the first status was not written"; return; }
  expect_poll "a lane near its limits is read" "$((at * 1000))" warden_value lastCheck
  at="$(warden_put near-limit 5)" || { fail "warden_ticks: the next tick was not written"; return; }
  expect_poll "the next tick of the same lane is read" "$((at * 1000))" warden_value lastCheck
  warden_put holding-off 0 >/dev/null
  expect_poll "memory nearly full is read" '["danger", null, [["memory-full", "danger"]], []]' warden_state
}
# warden_notify MODE: the plugin's `notify` setting written into its
# plugins row, or taken out of it for an empty MODE; then the service reads
# it.
warden_notify() {
  python3 - "$home/.config/vgshell/shell.json" "$1" <<'PY'
import json, os, sys
path, mode = sys.argv[1], sys.argv[2]
data = json.load(open(path))
rows = data.setdefault("plugins", [])
at = [i for i, r in enumerate(rows) if r == "vgs.agent-warden" or (isinstance(r, dict) and r.get("id") == "vgs.agent-warden")]
if not at:
    rows.append({"id": "vgs.agent-warden"})
    at = [len(rows) - 1]
row = rows[at[0]] if isinstance(rows[at[0]], dict) else {"id": "vgs.agent-warden"}
if mode:
    row["notify"] = mode
else:
    row.pop("notify", None)
rows[at[0]] = row
json.dump(data, open(path + ".tmp", "w"), indent=2)
os.replace(path + ".tmp", path)
PY
  expect_poll "the service reads notify: ${1:-problems}" "\"${1:-problems}\"" ipc smoke readInstance service vgs.agent-warden mode
}
warden_near_title="claude in vsy-52 is near its memory and task limits."
warden_near_notices='[["normal", "'"$warden_near_title"'", true]]'
warden_full_notice='["critical", "Agents are close to their memory limit.", true]'

warden_summary_put quiet
warden_put calm 0 >/dev/null
expect_poll "a calm status clears the episodes" '["calm", null, [], []]' warden_state
warden_mark="$(warden_sent_count)"
warden_ticks
expect_poll "one notice per item across ticks: the lane's, then memory nearly full's" \
  "$(python3 -c 'import json,sys; print(json.dumps(sorted([json.loads(sys.argv[2])] + json.loads(sys.argv[1]))))' "$warden_near_notices" "$warden_full_notice")" warden_notices_since "$warden_mark"
warden_mark="$(warden_sent_count)"
warden_put near-limit 0 >/dev/null
expect_poll "the lane near its limits again, after it cleared, sends its notice again" "$warden_near_notices" warden_notices_since "$warden_mark"
warden_put partial 0 >/dev/null
expect_poll "a partial move sends one notice with its action" '[["normal", "The warden moved only part of 1 agent into its limits.", true]]' warden_notices_since "$((warden_mark + 1))"

# A failed notify-send completion forgets both actionable and action-free
# episodes. The next real status tick retries; successful dismissal keeps
# the episodes, so a further tick sends nothing.
warden_retry_state() {
  local runs episodes
  runs="$(ipc smoke themeNoticeRuns)" || return
  episodes="$(ipc smoke readInstance service vgs.agent-warden episodes)" || return
  python3 -c 'import json,sys; print(json.dumps([int(sys.argv[1]), len(json.loads(sys.argv[2]))]))' "$runs" "$episodes"
}
while read -r warden_retry_fixture warden_retry_age warden_retry_count; do
  warden_put calm 0 >/dev/null
  expect_poll "${warden_retry_fixture}: calm clears the retry episodes" '[0, 0]' warden_retry_state
  warden_mark="$(warden_sent_count)"
  touch -- "$warden_delivery_fails"
  at="$(warden_put "$warden_retry_fixture" "$warden_retry_age")"
  expect_poll "${warden_retry_fixture}: the failed-delivery status is read" "$((at * 1000))" warden_value lastCheck
  expect_poll "${warden_retry_fixture}: the core attempts each notice" "$((warden_mark + warden_retry_count))" warden_sent_count
  expect_poll "${warden_retry_fixture}: failed completion releases its runs and episodes" '[0, 0]' warden_retry_state
  rm -f -- "$warden_delivery_fails"
  at="$(warden_put "$warden_retry_fixture" "$((warden_retry_age + 1))")"
  expect_poll "${warden_retry_fixture}: the next status tick is read" "$((at * 1000))" warden_value lastCheck
  expect_poll "${warden_retry_fixture}: the next status retries each failed notice" "$((warden_mark + 2 * warden_retry_count))" warden_sent_count
  expect_poll "${warden_retry_fixture}: successful dismissal retains the episodes" "[0, $warden_retry_count]" warden_retry_state
  at="$(warden_put "$warden_retry_fixture" "$((warden_retry_age + 2))")"
  expect_poll "${warden_retry_fixture}: a further status tick is read" "$((at * 1000))" warden_value lastCheck
  expect "${warden_retry_fixture}: delivered episodes send no duplicate" "$((warden_mark + 2 * warden_retry_count))" warden_sent_count
done <<'RETRIES'
near-limit 0 1
calm 600 1
RETRIES

# A press on a notice's first action, Show in vsys, opens the vsys TUI
# with that action's arguments, none for memory nearly full.
forget_record
touch -- "$warden_press"
warden_put holding-off 0 >/dev/null
expect_poll "a press on the notice's Show in vsys hands the terminal the vsys TUI" "$(words vgs.agent-warden/vsys tui/vsys.sh)" recorded_tail
rm -f -- "$warden_press"
expect_run_end "the vsys run from the notice ends" vgs.agent-warden/vsys

# notify: off sends nothing, and an episode that opened meanwhile stays
# unsent when notices come back on; the next one that opens goes out.
warden_notify off
warden_mark="$(warden_sent_count)"
warden_put calm 0 >/dev/null
expect_poll "a calm status clears the episodes while notices are off" '["calm", null, [], []]' warden_state
warden_ticks
warden_notify ""
warden_put near-limit 0 >/dev/null
expect_poll "notify: off sent nothing, and back on only the lane that opened again goes out" "$warden_near_notices" warden_notices_since "$warden_mark"

# notify: everything adds information through the core: one low,
# transient notification from Agent Warden, whose click only dismisses
# since the item offers no action.
warden_notify everything
warden_mark="$(warden_sent_count)"
warden_put reaped 0 >/dev/null
expect_poll "under notify: everything information goes out without an action" '[["low", "The warden stopped leftover work from 1 finished agent.", false]]' warden_notices_since "$warden_mark"
warden_notify ""

# A warden that stopped: Start checks runs the timer through the stand-in,
# pressed only once the stand-in comes first on the shell's PATH.
warden_systemctl_stub
warden_put calm 600 >/dev/null
expect_poll "the shield reads not checking" '["shield-off", "neutral", "", "Agent Warden hasn'"'"'t checked in 10m"]' warden_shield
warden_open "stopped"
expect_poll "the stopped panel offers Start checks" "$(words Agents "Agent Warden has stopped checking." "$warden_clear" "Start checks" "Checked N ago" "Open vsys")" warden_panel
if [[ "$("${shell_env[@]}" PATH="$shim:$PATH" bash -c 'command -v systemctl')" == "$shim/systemctl" ]]; then
  click_item panel vgs.agent-warden Button "Start checks" || fail "the click on Start checks failed"
  expect_poll "Start checks runs the warden's timer through systemctl --user" "--user start agent-warden.timer" warden_systemctl_argv
  expect_poll "the Start checks hand-off closes the panel" hidden warden_panel_shown
else
  fail "the stand-in systemctl does not come first on the shell's PATH, so Start checks was not pressed"
  ipc shell hide panel vgs.agent-warden >/dev/null
fi
sentinel_restore "$shim/systemctl"

# Without vsys the panel offers it through the core's notice, and a scan
# that finds it closes the notice with no rest.
rm -f -- "$shim/vsys" "$warden_dir/status.json"
rescan "a rescan after the stand-in vsys goes starts"
expect_poll "vsys reads as the host PATH gives it" "$vsys_first" warden_requirement vsys
if [[ $vsys_first == missing ]]; then
  # Required Tools names missing vsys, and the Warden setup step offers the
  # same Review action, which opens the existing install notice. The row
  # presses the step's; the manager and settings rows press Tools'. A scan
  # that finds vsys closes that notice.
  settings_page_open vgs.agent-warden
  settings_setup
  expect_poll "a warden not set up without vsys offers no Set up" '[["setup", "Set up", false]]' offered_actions vgs.agent-warden
  expect_poll "the Warden setup row draws To do with Review and why while vsys is missing" "$(words "Warden setup" "To do" "Review all missing or outdated tools" "$warden_vsys_hint" "Not set up")" warden_setup_drawn
  expect_poll "Tools names missing vsys and offers its install text link" '[[["To do", "warning"]], ["vsys (missing)"], ["Review all missing or outdated tools"]]' warden_tools_drawn
  expect "the page without vsys draws no Show command" true no_show_command
  settings_press --type RowAction "Review all missing or outdated tools" Field "Warden setup" || fail "the click on the Warden setup step's Review failed"
  expect_poll "Install all missing raises the notice for vsys" '["vgs.agent-warden", ["vsys"]]' warden_notice
  expect_poll "the Install all missing notice holds the keyboard" true ipc smoke noticeFocused
  warden_vsys_stub
  rescan "a rescan after the stand-in vsys arrives for the notice starts"
  expect_poll "the scan that finds vsys closes the Install all missing notice" null warden_notice
  notice_rests() { ipc shell lent | py_reply 'import json,sys; print(str(sys.argv[1] in json.load(sys.stdin)["notices"]["resting"]).lower())' "$1"; }
  expect "the closed Install all missing notice rests none of the plugin's offers" false notice_rests vgs.agent-warden
  rm -f -- "$shim/vsys"
  rescan "a rescan after the stand-in vsys goes again starts"
  expect_poll "vsys reads missing again" missing warden_requirement vsys
  settings_page_close vgs.agent-warden
  warden_open "without vsys"
  expect_poll "the panel without vsys offers Get vsys once" "$(words Agents "Install vsys to set up Agent Warden." "Install vsys")" warden_panel
  click_item panel vgs.agent-warden Button "Install vsys" || fail "the click on Get vsys failed"
  expect_poll "Get vsys raises the notice for vsys" '["vgs.agent-warden", ["vsys"]]' warden_notice
  expect_poll "the Get vsys hand-off closes the panel" hidden warden_panel_shown
  # Get vsys is a press, which no Not now rests, so a second press after
  # Not now shows the notice again.
  expect_poll "the Get vsys notice holds the keyboard" true ipc smoke noticeFocused
  type_keys -k Escape || fail "sending Escape to the Get vsys notice failed"
  expect_poll "Not now closes the Get vsys notice" null warden_notice
  expect "Not now on the Get vsys notice rests the plugin" true notice_rests vgs.agent-warden
  warden_open "after Not now"
  click_item panel vgs.agent-warden Button "Install vsys" || fail "the second click on Get vsys failed"
  expect_poll "a second Get vsys after Not now raises the notice again" '["vgs.agent-warden", ["vsys"]]' warden_notice
  expect_poll "the second Get vsys hand-off closes the panel" hidden warden_panel_shown
  warden_vsys_stub
  rescan "a rescan after vsys arrives starts"
  expect_poll "the scan that finds vsys closes the notice" null warden_notice
  expect_poll "the closed notice leaves no surface" 0 layer_count vgs:notice
else
  fail "vsys reads $vsys_first, so Install all missing and Get vsys were not pressed"
fi
expect_poll "the stand-in vsys reads as present again" present warden_requirement vsys

expect "disabling the agent warden is allowed" ok ipc shell setPluginEnabled vgs.agent-warden false
expect_poll "the disabled plugin holds no status record" null warden_lent

# warden_control FILE NEEDLE REPLACEMENT: the plugin copied over the
# bundled one with NEEDLE, which must occur once in FILE, replaced; then a
# rescan and the copy enabled. warden_uncontrol: the copy disabled and
# removed with the runtime files, and the bundled plugin back. The
# stand-in vsys's summary finds nothing unless a control writes another.
warden_control() {
  local scans file="$warden_copy/$1"
  shift
  mkdir -p -- "$warden_copy"
  cp -R -- "$repo/shell/plugins/vgs.agent-warden/." "$warden_copy/"
  if python3 -c '
import sys
path, *edits = sys.argv[1:]
if len(edits) % 2:
    sys.exit("edits must be NEEDLE REPLACEMENT pairs")
text = open(path).read()
for needle, replacement in zip(edits[0::2], edits[1::2]):
    if text.count(needle) != 1:
        sys.exit("the rule occurs %d times: %s" % (text.count(needle), needle))
    text = text.replace(needle, replacement)
open(path, "w").write(text)' "$file" "$@"; then ok "the control copy of ${file#$warden_copy/} drops its rule"; else fail "the control copy of ${file#$warden_copy/} could not be made"; fi
  # The scan has landed when rescan returns; its log line says whether it
  # replaced the plugin set, which the landing does not.
  scans="$(log_lines 'plugins: scan complete changed=true')" || fail "the instance log is unreadable before the control copy"
  rescan "a rescan after installing the control copy starts"
  expect_log "the rescan publishes the control copy" "$((scans + 1))" 'plugins: scan complete changed=true'
  expect "enabling the control copy is allowed" ok ipc shell setPluginEnabled vgs.agent-warden true
  expect_poll "the control copy made the warden directory and reads no warden" '["not-set-up", null, [], []]' warden_state
}
warden_uncontrol() {
  local scans
  expect "disabling the control copy is allowed" ok ipc shell setPluginEnabled vgs.agent-warden false
  rm -rf -- "$warden_copy" "$warden_dir"
  scans="$(log_lines 'plugins: scan complete changed=true')" || fail "the instance log is unreadable after the control copy"
  rescan "a rescan after removing the control copy starts"
  expect_log "the rescan brings the bundled plugin back" "$((scans + 1))" 'plugins: scan complete changed=true'
  expect_poll "the bundled agent warden is known again" True plugin_known vgs.agent-warden
  warden_summary_put quiet
}
warden_summary_put quiet

# Control: a logic copy that ignores staleness reads the stale document as
# calm, so the stale rows above turn red on it.
warden_control WardenLogic.js "if (Math.abs(now - checkedAt) > STALE_AFTER_MS) {" "if (false) {"
warden_put calm 600 >/dev/null
expect_poll "the staleness control reads the stale document as calm" '["calm", null, [], []]' warden_state
warden_uncontrol

# Control: a service copy whose timer derives nothing keeps an unchanged
# status calm past its stale moment, so the ageing row above turns red on
# it. The final read waits until the copied timer has fired, then reads the
# published state.
warden_control Service.qml "property bool heartbeatFailed: false" "property bool heartbeatFailed: false
    property int smokeDeadlineTicks: 0" "onTriggered: root.derive()" "onTriggered: { root.smokeDeadlineTicks += 1 }"
warden_put calm 85 >/dev/null
expect_poll "the timer control reads the fresh status as calm" '["calm", null, [], []]' warden_state
expect_poll "the timer control's stale deadline fired" 1 ipc smoke readInstance service vgs.agent-warden smokeDeadlineTicks
expect "the timer control keeps the unchanged status calm past its stale moment" '["calm", null, [], []]' warden_state
warden_uncontrol

# Control: a panel copy whose rows are not plain and whose meter takes the
# default accent draws the summary's title in the default text format and
# the meter in another colour, so the plain-text and grey meter rows
# above turn red on it.
warden_control Panel.qml "                    plain: true
" "" "                tone: \"neutral\"
" ""
warden_summary_put memory
warden_put calm 0 >/dev/null
expect_poll "the panel control reads the summary's warning" '["warn", null, [], ["warn"]]' warden_state
expect "the panel control's panel is summoned" ok ipc shell summon panel vgs.agent-warden '{}'
expect_poll "the panel control draws the summary's title in the default text format" 2 warden_title_format
expect "the panel control draws the meter in another colour" other warden_meter
expect "the panel control's panel is hidden" ok ipc shell hide panel vgs.agent-warden
warden_uncontrol

# Control: a service copy that keeps its causes after a failed summary
# still counts the earlier warning, so the failed-summary row above turns
# red on it.
warden_control Service.qml "                root.causes = null;
                const failure" "                const failure"
warden_summary_put memory
warden_put calm 0 >/dev/null
expect_poll "the causes control reads the summary's warning" '["warn", null, [], ["warn"]]' warden_state
warden_failed="$(log_lines 'agent-warden: summary=failed ')" || fail "the instance log is unreadable before the causes control"
touch -- "$warden_vsys_fails"
warden_put calm 1 >/dev/null
expect_log "the causes control's summary fails" "$((warden_failed + 1))" 'agent-warden: summary=failed '
expect "the causes control still counts the earlier warning" '["warn", null, [], ["warn"]]' warden_state
rm -f -- "${warden_vsys_fails:?}"
warden_uncontrol

# Control: a notices copy without episode memory sends the lane's notice
# again on its next tick, so the once-per-episode row above turns red on
# it.
warden_control Notices.js "        if (next.indexOf(e.key) !== -1) return;
" ""
# Whether the lane's notice went out more than once since MARK.
warden_repeated() { warden_notices_since "$1" | py_reply 'import json,sys; print(sum(1 for n in json.load(sys.stdin) if n[1] == sys.argv[1]) >= 2)' "$warden_near_title"; }
warden_mark="$(warden_sent_count)"
warden_ticks
expect_poll "the memory control sends the lane's notice again on the next tick" True warden_repeated "$warden_mark"
warden_uncontrol

# Control: the same completion arriving at a service that ignores failed
# delivery retains the episode, which the retry-state reader distinguishes.
warden_control Service.qml 'if (delivery === "failed") {' 'if (false) {'
touch -- "$warden_delivery_fails"
warden_put near-limit 0 >/dev/null
expect_poll "the failed-delivery control retains the failed episode" '[0, 1]' warden_retry_state
rm -f -- "$warden_delivery_fails"
warden_uncontrol

# A real action-free notification completes delivery while its nontransient
# card stays on screen or in History. The stand-in retry matrix above does
# not exercise notify-send's native --wait lifetime.
rm -f -- "$shim/notify-send"
expect "enabling Warden for real delivery is allowed" ok ipc shell setPluginEnabled vgs.agent-warden true
expect_poll "the real-delivery Warden owns its directory and reads no status" '["not-set-up", null, [], []]' warden_state
notes_on "Warden delivery lifetime"
warden_delivery_state() {
  local runs episodes cards
  runs="$(ipc smoke themeNoticeRuns)" || return
  episodes="$(ipc smoke readInstance service vgs.agent-warden episodes)" || return
  cards="$(ipc smoke modelRows vgs.notifications rows app,summary,leaving)" || return
  python3 - "$runs" "$episodes" "$cards" "$home/.local/state/vgshell/notifications/state.json" "$1" <<'PY'
import json, pathlib, sys
runs, episodes, cards, state, title = sys.argv[1:]
rows = [] if cards == "absent" else json.loads(cards)
present = any(r[0] == "Agent Warden" and r[1] == title and r[2] == "" for r in rows)
path = pathlib.Path(state)
if path.exists():
    present = present or any(r["app"] == "Agent Warden" and r["summary"] == title for r in json.loads(path.read_text())["history"])
print(json.dumps([int(runs), len(json.loads(episodes)), present]))
PY
}
warden_put calm 0 >/dev/null
expect_poll "real delivery starts with no episodes or core runs" '[0, 0]' warden_retry_state
warden_put calm 600 >/dev/null
expect_poll "real Warden delivery of the stopped notice releases its run with the card retained" '[0, 1, true]' warden_delivery_state "Agent Warden has stopped checking"
notes_clear "the stopped notice's delivery assertion finished"
notes_off "Warden delivery lifetime"
expect "disabling Warden after real delivery is allowed" ok ipc shell setPluginEnabled vgs.agent-warden false
expect_poll "the real-delivery Warden releases its status" null warden_lent
rm -rf -- "$warden_dir"

rm -f -- "$shim/vsys" "$shim/notify-send" "$warden_summary_file"
expect "the Warden notification fixture returns to its incoming enablement" ok ipc shell setPluginEnabled acme.probe "${warden_probe_was,,}"
