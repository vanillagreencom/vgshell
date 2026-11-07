# Local Sync, vgs.local-sync, shell/plugins/vgs.local-sync/README.md. The
# harness starts it disabled; this row enables it over a fixture sync job
# that lives only in the sandbox's stand-in user manager: the device
# stand-in systemctl (scripts/smoke/devices.sh) answers the unit list, the
# unit's properties and Remove's disable from replies the row plants; a
# stand-in journalctl in the shell's own PATH directory answers the unit's
# journal from $ls_journal and follows the manager's lines in
# $ls_manager with `exec tail`; a stand-in busctl answers systemd's
# GetUnitProcesses for the unit with the live processes of the fixture's
# wrapper, which the row starts and owns. The wrapper is a script the
# plugin reads as data and never runs: it waits on a FIFO, then runs the
# host's real rsync, slowed by --bwlimit, from one sandbox folder to
# another, and the real inotifywait on the host's rsync program wakes the
# copy check. No call reaches the host's user manager or journal: every
# command the plugin runs for a job resolves to a stand-in first, and the
# sandbox's runtime directory and buses are its own.
# Rows: the widget is placed in the bar; an inactive unit whose wrapper
# names rsync is listed with the wrapper's From and To and no copy; once
# its wrapper runs and the manager reports the unit, the job watches and
# copies nothing, the bar item still with no state dot; a copy the FIFO
# starts is seen through the exec watch alone, the bar item spinning with
# the info dot, and a stand-in that hides the engine processes reads no
# copy (the control: only an engine process is a copy); the copy's end,
# which has no event of its own, returns the job to idle with a clean end
# recorded; an rsync error line in the job's journal fails the job, the
# bar item in danger with the danger dot; the flyout opens from the bar
# item, draws the failed card with View log and Send to agent and hands
# the terminal the log TUI with the unit as its one argument, then
# summons over IPC onto one panel layer and hides with it; Remove of an unknown unit is refused and Remove of
# the fixture asks the stand-in systemctl to disable and stop it; a
# disable leaves no record and stops the follower.
# No latency ceiling; each state is polled once per nested IPC round trip.
# inputs: shell/plugins/vgs.local-sync/manifest.json shell/plugins/vgs.local-sync/Service.qml shell/plugins/vgs.local-sync/SyncLogic.js shell/plugins/vgs.local-sync/Widget.qml shell/plugins/vgs.local-sync/Panel.qml shell/plugins/vgs.local-sync/PathChip.qml shell/plugins/vgs.local-sync/tui/log.sh shell/Ui/BarWidget.qml shell/Ui/controls/BarItem.qml shell/Hosts/SummonLayer.qml shell/Core/TuiRunner.qml bin/vgshell-tui bin/lib/qml-library.js scripts/smoke/user-config.sh
set -euo pipefail
ls_dir="$sandbox/local-sync"
ls_unit=smoke-folder-sync.service
ls_journal="$ls_dir/journal.jsonl"
ls_manager="$ls_dir/manager.jsonl"
ls_follows="$ls_dir/follow.calls"
ls_wrapper="$ls_dir/sync-wrapper.sh"
ls_go="$ls_dir/go"
ls_main="$ls_dir/main.pid"
ls_hide="$ls_dir/hide-engines"
ls_from="$home/local-sync/from"
ls_to="$home/local-sync/to"
ls_saved="$sandbox/local-sync-before.json"
ls_replies="$devices_dir/replies/systemctl.json"
ls_replies_saved="$ls_dir/systemctl-replies.json"
ls_wrapper_pid=""
mkdir -p -- "$ls_dir" "$ls_from" "$ls_to"
cp -- "$home/.config/vgshell/shell.json" "$ls_saved"
if [[ -e $ls_replies ]]; then cp -- "$ls_replies" "$ls_replies_saved"; fi
: >"$ls_journal"
: >"$ls_manager"
# A disable stops the two watches the service keeps up, and each says so.
expected_errors+=('WARN qml: local-sync: watch=stopped ' 'WARN qml: local-sync: follow=stopped ')

# The engine processes under the wrapper, which the row started: rsync
# runs as more than one process for a local copy.
ls_engines() {
  [[ -n $ls_wrapper_pid ]] || return 0
  python3 - "$ls_wrapper_pid" <<'PY'
import os, sys
root = int(sys.argv[1])
parents = {}
for entry in os.listdir("/proc"):
    if entry.isdigit():
        try:
            with open(f"/proc/{entry}/stat") as stat:
                parents[int(entry)] = int(stat.read().rsplit(")", 1)[1].split()[1])
        except (OSError, IndexError, ValueError):
            pass
found, queue = [], [root]
while queue:
    pid = queue.pop()
    for child, parent in parents.items():
        if parent == pid:
            queue.append(child)
            try:
                if open(f"/proc/{child}/comm").read().strip() == "rsync":
                    found.append(child)
            except OSError:
                pass
print(" ".join(map(str, found)))
PY
}
ls_engine_seen() { local pids; pids="$(ls_engines)" || return; if [[ -n $pids ]]; then echo true; else echo false; fi; }
ls_stop_engines() {
  local pids
  pids="$(ls_engines)" || return
  [[ -z $pids ]] || kill -TERM $pids 2>/dev/null || true
}
ls_stop_wrapper() {
  [[ -n $ls_wrapper_pid ]] || return 0
  ls_stop_engines
  kill -TERM "$ls_wrapper_pid" 2>/dev/null || true
  wait "$ls_wrapper_pid" 2>/dev/null || true
  ls_wrapper_pid=""
  rm -f -- "$ls_main"
}
ls_restore() {
  local result=0 name
  ls_stop_wrapper || result=1
  ipc shell setPluginEnabled vgs.local-sync false >/dev/null || result=1
  for name in journalctl busctl; do
    if [[ -e $ls_dir/saved-$name ]]; then mv -f -- "$ls_dir/saved-$name" "$shim/$name" || result=1; else rm -f -- "${shim:?}/$name" || result=1; fi
  done
  if [[ -e $ls_replies_saved ]]; then cp -- "$ls_replies_saved" "$ls_replies" || result=1; else rm -f -- "$ls_replies" || result=1; fi
  user_config_restore "$ls_saved" || result=1
  ipc shell reloadConfig >/dev/null || result=1
  return "$result"
}
# The harness stops this row's children before it runs this on an early
# end; the wrapper's engines are its grandchildren, so they go first.
smoke_row_abandon=(ls_restore)
terminal_stand_in
terminal_ready local-sync

for name in journalctl busctl; do
  if [[ -e $shim/$name ]]; then mv -- "$shim/$name" "$ls_dir/saved-$name"; fi
done
cat >"$shim/journalctl" <<EOF
#!/usr/bin/env bash
python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "\$@" >>"$ls_dir/journalctl.calls"
if [[ "\$*" == "--user --follow --lines=0 --output=json _SYSTEMD_USER_UNIT=init.scope" ]]; then
  printf '%s\n' "\$\$" >>"$ls_follows"
  exec tail -n 0 -F -- "$ls_manager"
fi
if [[ \$# == 8 && "\${*:1:7}" == "--user --no-pager -o json -n 200 -u" ]]; then
  exec python3 -c 'import json,sys
unit = sys.argv[2]
lines = [l for l in open(sys.argv[1]).read().splitlines() if l and json.loads(l).get("_SYSTEMD_USER_UNIT") == unit]
print("\n".join(lines[-200:]))' "$ls_journal" "\$8"
fi
echo "stand-in journalctl: argv=\$*" >&2
exit 1
EOF
cat >"$shim/busctl" <<EOF
#!/usr/bin/env bash
python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "\$@" >>"$ls_dir/busctl.calls"
exec python3 - "$ls_main" "$ls_hide" "$ls_unit" "\$@" <<'PY'
import json, os, sys
main_file, hide, unit, argv = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
want = ["--user", "--json=short", "call", "org.freedesktop.systemd1", "/org/freedesktop/systemd1",
        "org.freedesktop.systemd1.Manager", "GetUnitProcesses", "s"]
if argv[:-1] != want or argv[-1] != unit:
    sys.exit("stand-in busctl: argv=" + json.dumps(argv))
procs = []
if os.path.exists(main_file):
    root = int(open(main_file).read())
    parents = {}
    for entry in os.listdir("/proc"):
        if entry.isdigit():
            try:
                parents[int(entry)] = int(open(f"/proc/{entry}/stat").read().rsplit(")", 1)[1].split()[1])
            except (OSError, IndexError, ValueError):
                pass
    tree, queue = [root], [root]
    while queue and not os.path.exists(hide):
        pid = queue.pop()
        for child, parent in parents.items():
            if parent == pid:
                tree.append(child)
                queue.append(child)
    for pid in tree:
        try:
            line = open(f"/proc/{pid}/cmdline").read().rstrip("\0").replace("\0", " ")
        except OSError:
            continue
        procs.append(["/user.slice/user-1000.slice/user@1000.service/app.slice/" + unit, pid, line])
print(json.dumps({"type": "a(sus)", "data": [procs]}))
PY
EOF
chmod 755 "$shim/journalctl" "$shim/busctl"

# The wrapper the unit runs: a loop that copies once a line reaches its
# FIFO. The plugin reads its assignments and its rsync line as data.
mkfifo -- "$ls_go"
head -c 1048576 /dev/zero >"$ls_from/payload.bin"
cat >"$ls_wrapper" <<EOF
#!/usr/bin/env bash
SRC="\$HOME/local-sync/from"
DST="\$HOME/local-sync/to"
GO="$ls_go"
while read -r _ <"\$GO"; do
  rsync --archive --bwlimit=1 "\$SRC/" "\$DST/"
done
EOF
chmod 755 "$ls_wrapper"

# The unit's properties as `systemctl --user show --timestamp=unix`
# prints them, for the argv the service reads them with: the property
# list SyncLogic.SHOW_PROPERTIES holds.
ls_props="$(node -e 'const { load } = require(process.argv[1]); process.stdout.write(load(process.argv[2]).SHOW_PROPERTIES.join(","))' \
  "$repo/bin/lib/qml-library.js" "$repo/shell/plugins/vgs.local-sync/SyncLogic.js")" || fail "local-sync: the unit's property list is unreadable"
ls_exec="{ path=$ls_wrapper ; argv[]=$ls_wrapper ; ignore_errors=no ; start_time=[n/a] ; stop_time=[n/a] ; pid=0 ; code=(null) ; status=0/0 }"
# ls_unit_state ACTIVE SUB START: the unit list and its properties planted
# for the service's next read.
ls_unit_state() { # ACTIVE SUB START_SECONDS
  local start=""
  [[ $3 == 0 ]] || start="@$3"
  device_reply systemctl 0 "$ls_unit enabled enabled" --user list-unit-files --type=service --no-legend --plain
  device_reply systemctl 0 "$(printf '%s\n' "Id=$ls_unit" "Description=Smoke folder copy" "LoadState=loaded" "ActiveState=$1" "SubState=$2" \
    "Result=success" "Type=simple" "ExecStart=$ls_exec" "TriggeredBy=" "FragmentPath=$home/.config/systemd/user/$ls_unit" \
    "UnitFileState=enabled" "ExecMainStatus=0" "ExecMainStartTimestamp=$start" "ExecMainExitTimestamp=")" \
    --user show --timestamp=unix -p "$ls_props" "*.service" "$ls_unit"
}
device_reply systemctl 0 "" --user disable --now -- "$ls_unit"
# ls_manager_line MESSAGE: one user-manager line about the unit, as
# journalctl -o json prints it, appended whole for the follower.
ls_manager_line() {
  python3 - "$ls_manager" "$ls_unit" "$1" <<'PY'
import json, sys, time
path, unit, message = sys.argv[1:4]
entry = {"__REALTIME_TIMESTAMP": str(int(time.time() * 1e6)), "MESSAGE": message, "_COMM": "systemd",
         "_SYSTEMD_USER_UNIT": "init.scope", "USER_UNIT": unit, "PRIORITY": "6"}
with open(path, "a") as out:
    out.write(json.dumps(entry) + "\n")
PY
}
# ls_job_line COMM PRIORITY MESSAGE: one line of the unit's own processes.
ls_job_line() {
  python3 - "$ls_journal" "$ls_unit" "$1" "$2" "$3" <<'PY'
import json, sys, time
path, unit, comm, priority, message = sys.argv[1:6]
entry = {"__REALTIME_TIMESTAMP": str(int(time.time() * 1e6)), "MESSAGE": message, "_COMM": comm,
         "_SYSTEMD_USER_UNIT": unit, "PRIORITY": priority}
with open(path, "a") as out:
    out.write(json.dumps(entry) + "\n")
PY
}

# The service's published value: one field of it, as JSON, or
# `unpublished` before the first complete read.
ls_value() { # KEY
  ipc vgs.local-sync invoke status "" | py_reply 'import json,sys; v=json.load(sys.stdin).get("jobs"); print("unpublished" if not v or not v["ready"] else json.dumps(v[sys.argv[1]]))' "$1"
}
# The fixture job as listed: [unit, engine, from, to, via, active, continuous].
ls_job() {
  ls_value jobs | py_reply 'import json,sys
t = sys.stdin.read().strip()
if t == "unpublished": print(t); sys.exit()
jobs = [j for j in json.loads(t) if j["unit"] == sys.argv[1]]
print(json.dumps([[j[k] for k in ("unit", "engine", "from", "to", "via", "active", "continuous")] for j in jobs]))' "$ls_unit"
}
ls_fact() { # KEY
  ls_value facts | py_reply 'import json,sys; t=sys.stdin.read().strip(); f=json.loads(t).get(sys.argv[1]) if t != "unpublished" else None; print("absent" if f is None else json.dumps(f[sys.argv[2]] > 0 if sys.argv[2] == "failedAt" else f[sys.argv[2]]))' "$ls_unit" "$1"
}
# The end of the job's last clean copy in ms, 0 for none.
ls_clean_at() { ls_value cleanEnds | py_reply 'import json,sys; t=sys.stdin.read().strip(); print(t if t == "unpublished" else json.loads(t).get(sys.argv[1], 0))' "$ls_unit"; }
ls_clean_after() { local at; at="$(ls_clean_at)" || return; if [[ $at =~ ^[0-9]+$ ]] && (( at > $1 )); then echo later; else echo "$at"; fi; } # MS
# The bar item as drawn: `SPINNING|STATE_DOT`.
ls_bar() {
  local key spinning dot
  key="$(bar_key)" || return
  spinning="$(ipc smoke readDescendant "$key" vgs.local-sync BarItem spinning)" && dot="$(ipc smoke readDescendant "$key" vgs.local-sync BarItem stateDot)" || return
  printf '%s|%s\n' "$spinning" "$dot"
}
ls_follower_count() { if [[ -f $ls_follows ]]; then wc -l <"$ls_follows"; else echo 0; fi; }
ls_follower_alive() {
  local pid
  pid="$(tail -n 1 -- "$ls_follows")" || return
  if kill -0 "$pid" 2>/dev/null; then echo alive; else echo gone; fi
}
ls_shown() {
  local geometry
  geometry="$(ipc smoke instanceGeometry panel vgs.local-sync)" || return
  if [[ $geometry == absent ]]; then echo hidden; else echo shown; fi
}
# The flyout's card for the fixture: [state, tone, actions].
ls_card() {
  ipc smoke readInstance panel vgs.local-sync cards | py_reply 'import json,sys
t = sys.stdin.read().strip()
if not t.startswith("["): print(t); sys.exit()
cards = [c for c in json.loads(t) if c["unit"] == sys.argv[1]]
print(json.dumps([[c["state"], c["tone"], c["actions"]] for c in cards]))' "$ls_unit"
}
ls_disables() { device_calls systemctl | py_reply 'import json,sys; print(json.dumps([c for c in json.load(sys.stdin) if c[1:2] == ["disable"]]))'; }
# The spinner turns only while the theme animates; at motion scale zero the
# item keeps its icon and the dot shows the copy.
ls_spins="$(ipc smoke themeValue spinner.duration | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin) > 0))')" || fail "local-sync: the spinner duration is unreadable"

ls_unit_state inactive dead 0
expect "Local Sync enables" ok ipc shell setPluginEnabled vgs.local-sync true
expect "Local Sync places its widget" ok ipc shell setPluginPlaced vgs.local-sync true
expect_poll "the bar builds the Local Sync item" '"vgs.local-sync"' ipc smoke readInstance "$(bar_key)" vgs.local-sync moduleName
expect_poll "the manager follower starts" 1 ls_follower_count
expect_poll "the exec watch runs on the copy programs" true ls_value watching
expect_poll "an inactive unit whose wrapper names rsync is listed with the wrapper's folders" \
  "[[\"$ls_unit\", \"rsync\", \"$ls_from/\", \"$ls_to/\", \"script\", \"inactive\", true]]" ls_job
expect "the inactive job copies nothing" '[]' ls_value copying
expect "the inactive job's bar item is still with no dot" 'false|""' ls_bar

ls_unit_state active running "$(date +%s)"
HOME="$home" bash "$ls_wrapper" >"$ls_dir/wrapper.log" 2>&1 &
ls_wrapper_pid=$!
printf '%s\n' "$ls_wrapper_pid" >"$ls_main"
ls_manager_line "Started Smoke folder copy."
expect_poll "the manager's line about the unit reads it running" \
  "[[\"$ls_unit\", \"rsync\", \"$ls_from/\", \"$ls_to/\", \"script\", \"active\", true]]" ls_job
expect "a wrapper that only watches copies nothing" '[]' ls_value copying
expect "the watching job's bar item is still with no dot" 'false|""' ls_bar

printf 'go\n' >"$ls_go"
expect_poll "the copy starts an rsync under the wrapper" true ls_engine_seen
expect_poll "running rsync wakes the copy check, which reads the job copying" "[\"$ls_unit\"]" ls_value copying
expect_poll "the bar item turns while the job copies, with the info dot" "$ls_spins|\"info\"" ls_bar
: >"$ls_hide"
expect "control: refresh is accepted while the engines are hidden" ok ipc vgs.local-sync invoke refresh ""
expect_poll "control: a unit whose processes hold no engine reads no copy" '[]' ls_value copying
rm -f -- "$ls_hide"
expect "refresh is accepted with the engines shown again" ok ipc vgs.local-sync invoke refresh ""
expect_poll "the engines shown again read the job copying" "[\"$ls_unit\"]" ls_value copying

ls_clean_before="$(ls_clean_at)" || fail "local-sync: the clean end is unreadable"
[[ $ls_clean_before =~ ^[0-9]+$ ]] || ls_clean_before=0
ls_stop_engines
expect_poll "the copy's end, which has no event, returns the job to idle" '[]' ls_value copying
expect_poll "a copy that ended with no error line records a later clean end" later ls_clean_after "$ls_clean_before"
expect_poll "the idle job's bar item is still with no dot" 'false|""' ls_bar
expect "no error line, no failure" false ls_fact failedAt

ls_job_line rsync 3 "rsync error: some files/attrs were not transferred (see previous errors) (code 23) at main.c(1338) [sender=3.4.1]"
ls_manager_line "$ls_unit: Main process exited, code=exited, status=23/n/a"
expect_poll "an rsync error line in the job's journal fails the job" true ls_fact failedAt
expect_poll "the failed job's bar item shows the danger dot" 'false|"danger"' ls_bar

click_centre "$(bar_key)" vgs.local-sync || fail "local-sync: the click on the bar item failed"
expect_poll "the bar item opens the flyout" shown ls_shown
expect_poll "the flyout draws the failed card with View log and Send to agent" "[[\"failed\", \"danger\", [\"log\", \"agent\"]]]" ls_card
forget_record
expect "View log hands the terminal the log TUI" ok ipc smoke invokeInstance panel vgs.local-sync viewLog "$ls_unit"
expect_poll "the log TUI takes the unit as its one argument" "$(words vgs.local-sync/log tui/log.sh "$ls_unit")" recorded_tail
expect_poll "View log closes the flyout" hidden ls_shown
expect "the flyout summons again" ok ipc shell summon panel vgs.local-sync '{}'
expect_poll "the summoned flyout shows" shown ls_shown
expect_poll "the summoned flyout is one panel layer" 1 layer_count vgs:panel
expect "the flyout hides" ok ipc shell hide panel vgs.local-sync
expect_poll "the hidden flyout leaves no panel layer" 0 layer_count vgs:panel
rest_pointer

expect "Remove refuses a unit that is not a listed job" "refused: unit=unknown" ipc vgs.local-sync invoke remove other.service
expect "Remove of the fixture is accepted" ok ipc vgs.local-sync invoke remove "$ls_unit"
expect_poll "Remove disables and stops the unit through systemctl" "[[\"--user\", \"disable\", \"--now\", \"--\", \"$ls_unit\"]]" ls_disables

ls_stop_wrapper
expect "the widget leaves the bar" ok ipc shell setPluginPlaced vgs.local-sync false
expect "Local Sync disables" ok ipc shell setPluginEnabled vgs.local-sync false
expect_poll "a disable leaves no Local Sync record" False record_exists vgs.local-sync
expect_poll "a disable stops the manager follower" gone ls_follower_alive
ls_restore || fail "local-sync: the row's state could not be restored"
