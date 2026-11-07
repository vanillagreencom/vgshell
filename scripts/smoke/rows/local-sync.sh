# Local Sync, vgs.local-sync, shell/plugins/vgs.local-sync/README.md. The
# harness starts it disabled; this row enables it over fixture sync jobs
# that live only in the sandbox's stand-in user manager,
# harness.sh's local_sync_stand_ins over $ls_dir: the device stand-in
# systemctl (scripts/smoke/devices.sh) answers the unit list, the units'
# properties and Remove's disable from replies the row plants; a stand-in
# journalctl answers each job's journal from $ls_dir/journal.jsonl and
# follows the manager's lines in $ls_dir/manager.jsonl; a stand-in busctl
# answers systemd's GetUnitProcesses for the fixture unit with the live
# processes of its wrapper, which the row starts and owns. The wrapper is a
# script the plugin reads as data and never runs: it waits on a FIFO, then
# runs rsync, slowed by --bwlimit, from one sandbox folder to another. Its
# rsync is a copy of the host's program in the shell's own PATH
# directory, so the real inotifywait on that copy wakes the copy check and
# the row can replace the copy. No call reaches the host's user manager or
# journal: every command the plugin runs for a job resolves to a stand-in
# first, and the sandbox's runtime directory and buses are its own.
# Rows: the widget is placed in the bar; an inactive unit whose wrapper
# names rsync is listed with the wrapper's From and To and no copy; once
# its wrapper runs and the manager reports the unit, the job watches and
# copies nothing, the bar item still with no state dot, and in one of three
# windows of 2.5 s, longer than the 2 s copy poll, no copy check runs (a
# timer-wiring check: no poll runs while no job copies); a copy the FIFO
# starts is seen through the exec watch, the bar item spinning with the
# info dot, and a stand-in that hides the engine processes reads no copy
# (the control: only an engine process is a copy); the copy's end, which
# has no event of its own, returns the job to idle with a clean end
# recorded; an rsync error line in the job's journal fails the job, the bar
# item in danger with the danger dot; the flyout opens from the bar item and
# draws the failed card with View log and Send to agent; its Job options
# menu opens Details for the job and goes back, and its Remove asks first
# and, accepted, has the stand-in systemctl disable and stop the unit; View
# log hands the terminal the log TUI with the unit as its one argument; the
# flyout summons over IPC onto one panel layer and hides with it; Remove of
# an unknown unit is refused; a replaced rsync program is watched again, so
# running the new file wakes the copy check, and a version-2 Automations
# store written after the start lists its sync automation by its stored
# name. Each of those two has a control on the world's copy of Service.qml:
# without the re-arm the new file's copy is never seen, and without the
# store's change handler the automation is never listed. A disable leaves
# no record and stops the follower.
# No latency ceiling; each state is polled once per nested IPC round trip.
# inputs: shell/plugins/vgs.local-sync/manifest.json shell/plugins/vgs.local-sync/Service.qml shell/plugins/vgs.local-sync/SyncLogic.js shell/plugins/vgs.local-sync/Widget.qml shell/plugins/vgs.local-sync/Panel.qml shell/plugins/vgs.local-sync/PathChip.qml shell/plugins/vgs.local-sync/tui/log.sh shell/Ui/BarWidget.qml shell/Ui/controls/BarItem.qml shell/Ui/controls/IconButton.qml shell/Ui/overlay/Menu.qml shell/Ui/overlay/MenuItem.qml shell/Ui/feedback/Dialog.qml shell/Commons/WatchedFile.qml shell/Hosts/SummonLayer.qml shell/Hosts/SummonPopup.qml shell/Core/TuiRunner.qml bin/vgshell-tui bin/lib/qml-library.js scripts/smoke/user-config.sh
set -euo pipefail
ls_dir="$sandbox/local-sync"
ls_unit=smoke-folder-sync.service
ls_auto_unit=vgs-automation-smokestore.service
ls_journal="$ls_dir/journal.jsonl"
ls_manager="$ls_dir/manager.jsonl"
ls_follows="$ls_dir/follow.calls"
ls_wrapper="$ls_dir/sync-wrapper.sh"
ls_go="$ls_dir/go"
ls_main="$ls_dir/pids/$ls_unit"
ls_hide="$ls_dir/hide-engines"
ls_engine="$shim/rsync"
ls_from="$home/local-sync/from"
ls_to="$home/local-sync/to"
ls_saved="$sandbox/local-sync-before.json"
ls_store="$home/.config/vgshell/automations/automations.json"
ls_service="$repo/shell/plugins/vgs.local-sync/Service.qml"
ls_wrapper_pid=""
mkdir -p -- "$ls_dir" "$ls_from" "$ls_to" "${ls_store%/*}"
cp -- "$home/.config/vgshell/shell.json" "$ls_saved"
cp -p -- "$ls_service" "$ls_dir/Service.qml.real"
if [[ -e $ls_store ]]; then cp -p -- "$ls_store" "$ls_dir/store.real"; fi
rm -f -- "$ls_store"
if [[ -e $ls_engine ]]; then mv -- "$ls_engine" "$ls_dir/rsync.saved"; fi
cp -- "$(command -v rsync)" "$ls_engine"

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
  local result=0
  ls_stop_wrapper || result=1
  ipc shell setPluginEnabled vgs.local-sync false >/dev/null || result=1
  if ! cmp -s -- "$ls_dir/Service.qml.real" "$ls_service"; then
    cp -p -- "$ls_dir/Service.qml.real" "$ls_service.next" && mv -T -- "$ls_service.next" "$ls_service" || result=1
    ipc shell rescanPlugins >/dev/null || result=1
  fi
  local_sync_stand_ins_restore "$ls_dir" || result=1
  if [[ -e $ls_dir/rsync.saved ]]; then mv -f -- "$ls_dir/rsync.saved" "$ls_engine" || result=1; else rm -f -- "${shim:?}/rsync" || result=1; fi
  if [[ -e $ls_dir/store.real ]]; then cp -p -- "$ls_dir/store.real" "$ls_store" || result=1; else rm -f -- "$ls_store" || result=1; fi
  user_config_restore "$ls_saved" || result=1
  ipc shell reloadConfig >/dev/null || result=1
  return "$result"
}
# The harness stops this row's children before it runs this on an early
# end; the wrapper's engines are its grandchildren, so they go first.
smoke_row_abandon=(ls_restore)
terminal_stand_in
terminal_ready local-sync
local_sync_stand_ins "$ls_dir" || fail "local-sync: the stand-ins could not be written"

# The wrapper the unit runs: a loop that copies once a line reaches its
# FIFO, with the shell's own PATH directory first, so its rsync is the
# copy there. The plugin reads its assignments and its rsync line as data.
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

ls_props="$(cat -- "$ls_dir/props")" || fail "local-sync: the unit property list is unreadable"
ls_exec="{ path=$ls_wrapper ; argv[]=$ls_wrapper ; ignore_errors=no ; start_time=[n/a] ; stop_time=[n/a] ; pid=0 ; code=(null) ; status=0/0 }"
ls_units=("$ls_unit")
ls_active=inactive ls_sub=dead ls_start=""
# ls_unit_state [ACTIVE SUB START_SECONDS]: the unit list and the units'
# properties planted for the service's next read, with the fixture unit's
# state kept from the last call when none is given. The automation's unit
# joins once ls_units names it.
ls_unit_state() { # [ACTIVE SUB START_SECONDS]
  local blocks unit list=""
  if [[ $# -gt 0 ]]; then
    ls_active="$1" ls_sub="$2" ls_start=""
    [[ $3 == 0 ]] || ls_start="@$3"
  fi
  blocks="$(printf '%s\n' "Id=$ls_unit" "Description=Smoke folder copy" "LoadState=loaded" "ActiveState=$ls_active" "SubState=$ls_sub" \
    "Result=success" "Type=simple" "ExecStart=$ls_exec" "TriggeredBy=" "FragmentPath=$home/.config/systemd/user/$ls_unit" \
    "UnitFileState=enabled" "ExecMainStatus=0" "ExecMainStartTimestamp=$ls_start" "ExecMainExitTimestamp=")"
  if [[ " ${ls_units[*]} " == *" $ls_auto_unit "* ]]; then
    blocks+=$'\n\n'"$(printf '%s\n' "Id=$ls_auto_unit" "Description=Smoke store copy" "LoadState=loaded" "ActiveState=inactive" "SubState=dead" \
      "Result=success" "Type=oneshot" "ExecStart=" "TriggeredBy=vgs-automation-smokestore.timer" "FragmentPath=$home/.config/systemd/user/$ls_auto_unit" \
      "UnitFileState=static" "ExecMainStatus=0" "ExecMainStartTimestamp=" "ExecMainExitTimestamp=")"
  fi
  for unit in "${ls_units[@]}"; do list+="$unit enabled enabled"$'\n'; done
  device_reply systemctl 0 "$list" --user list-unit-files --type=service --no-legend --plain
  device_reply systemctl 0 "$blocks" --user show --timestamp=unix -p "$ls_props" "*.service" "${ls_units[@]}"
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
# The automation's job as listed: [unit, name, from, to, via].
ls_auto_job() {
  ls_value jobs | py_reply 'import json,sys
t = sys.stdin.read().strip()
if t == "unpublished": print(t); sys.exit()
jobs = [j for j in json.loads(t) if j["unit"] == sys.argv[1]]
print(json.dumps([[j[k] for k in ("unit", "name", "from", "to", "via")] for j in jobs]))' "$ls_auto_unit"
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
ls_count() { if [[ -f $1 ]]; then wc -l <"$1"; else echo 0; fi; } # FILE
ls_follower_alive() {
  local pid
  pid="$(tail -n 1 -- "$ls_follows")" || return
  if kill -0 "$pid" 2>/dev/null; then echo alive; else echo gone; fi
}
# ls_quiet_window: `quiet` once one of three windows of 2.5 s, longer than
# the service's 2 s copy poll, passes with no GetUnitProcesses call; the
# copy check's count otherwise. A copy poll left running calls in every
# window; three windows let a check that a host program's run of the host
# rsync woke pass, since the shell watches that program too.
ls_quiet_window() {
  local before after
  for _ in 1 2 3; do
    before="$(ls_count "$ls_dir/busctl.calls")" || return
    sleep 2.5
    after="$(ls_count "$ls_dir/busctl.calls")" || return
    if [[ $before == "$after" ]]; then echo quiet; return; fi
  done
  echo "calls=$before..$after"
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
# ls_press LABEL: a click at the centre of the flyout's icon button LABEL,
# which the probe finds by its label, as an icon button draws no text.
ls_press() { # LABEL
  local box x y
  box="$(ipc smoke labelledGeometry panel vgs.local-sync IconButton "$1")" || return 1
  [[ $box == \[* ]] || { echo "ls_press: no $1: $box" >&2; return 1; }
  read -r x y < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(int(x+w/2), int(y+h/2))' "$box") || return 1
  hover "$((x + 1))" "$y" || return 1
  click "$x" "$y"
}
ls_disables() { device_calls systemctl | py_reply 'import json,sys; print(json.dumps([c for c in json.load(sys.stdin) if c[1:2] == ["disable"]]))'; }
# The pid of the exec watch on the shell's rsync copy, `none` without one.
ls_watch_pid() {
  python3 - "$ls_engine" <<'PY'
import os, sys
engine = sys.argv[1].encode()
found = []
for entry in os.listdir("/proc"):
    if entry.isdigit():
        try:
            words = open(f"/proc/{entry}/cmdline", "rb").read().split(b"\0")
        except OSError:
            continue
        if words and words[0].endswith(b"inotifywait") and engine in words:
            found.append(entry)
print(",".join(sorted(found)) or "none")
PY
}
ls_watch_moved() { local now; now="$(ls_watch_pid)" || return; if [[ $now != none && $now != "$1" ]]; then echo moved; else echo "$now"; fi; } # PID
# The journal reads the service made, one per job each read.
ls_journal_reads() { python3 -c 'import json,sys; print(sum(1 for l in open(sys.argv[1]) if "--follow" not in json.loads(l)))' "$ls_dir/journalctl.calls"; }
ls_reads_after() { local now; now="$(ls_journal_reads)" || return; if (( now > $1 )); then echo read; else echo "$now"; fi; } # COUNT
# ls_rebuild LABEL: a rescan that publishes the world's Service.qml as it
# is now, read once the rebuilt service has read the jobs and watches.
ls_revision() { ipc shell listPlugins | py_reply 'import json,sys; print([p["revision"] for p in json.load(sys.stdin)["plugins"] if p["id"]=="vgs.local-sync"][0])'; }
ls_revised() { [[ $(ls_revision) != "$1" ]] && echo revised || echo same; }
ls_rebuild() { # LABEL
  local before
  before="$(ls_revision)" || { fail "local-sync: the revision before $1 is unreadable"; return; }
  rescan "a rescan builds $1"
  expect_poll "the rescan publishes $1" revised ls_revised "$before"
  expect_poll "$1 lists the fixture job" "[[\"$ls_unit\", \"rsync\", \"$ls_from/\", \"$ls_to/\", \"script\", \"active\", true]]" ls_job
  expect_poll "$1 watches the copy programs" true ls_value watching
  ls_idle "$1"
}
# ls_idle LABEL: no read or copy check runs, read twice over the 500 ms
# the service waits before a read it was asked for (readSoon), so a read
# a start queued has run.
ls_service_busy() { ipc smoke readInstance service vgs.local-sync pending | py_reply 'import sys; print("idle" if sys.stdin.read().strip() == "null" else "busy")'; }
ls_idle() { # LABEL
  expect_poll "$1: no read runs" idle ls_service_busy
  sleep 0.6
  expect_poll "$1: no read runs after the queued one" idle ls_service_busy
}
# ls_edit LABEL OLD NEW: the world's Service.qml with its one OLD replaced
# by NEW, then rebuilt; ls_unedit LABEL rebuilds it as shipped.
ls_edit() { # LABEL OLD NEW
  python3 - "$ls_dir/Service.qml.real" "$ls_service.next" "$2" "$3" <<'PY' || { fail "local-sync: the $1 control's text occurs once in Service.qml"; return; }
import pathlib, sys
src, dst, old, new = sys.argv[1:]
text = pathlib.Path(src).read_text()
assert text.count(old) == 1, "control text must match once: " + old
pathlib.Path(dst).write_text(text.replace(old, new))
PY
  mv -T -- "$ls_service.next" "$ls_service"
  ls_rebuild "the $1 control"
}
ls_unedit() { # LABEL
  cp -p -- "$ls_dir/Service.qml.real" "$ls_service.next" && mv -T -- "$ls_service.next" "$ls_service"
  ls_rebuild "the service the $1 control replaced"
}
# ls_rearm_wakes: the shell's rsync copy replaced by a new file, as a
# package upgrade renames one over it; the watch moves to the new file, the
# read that follows ends, and a copy the new file runs reads copying; the
# copy is then stopped and read gone.
ls_rearm_wakes() {
  local pid reads
  pid="$(ls_watch_pid)" || { fail "local-sync: the exec watch is unreadable"; return; }
  reads="$(ls_journal_reads)" || { fail "local-sync: the journal reads are unreadable"; return; }
  cp -- "$ls_engine" "$ls_engine.next" && mv -f -T -- "$ls_engine.next" "$ls_engine" || { fail "local-sync: the rsync copy could not be replaced"; return; }
  expect_poll "a replaced rsync program moves the exec watch to the new file" moved ls_watch_moved "$pid"
  expect_poll "the read after the new watch ends" read ls_reads_after "$reads"
  ls_idle "the replaced program"
  printf 'go\n' >"$ls_go"
  expect_poll "a copy the replaced program runs starts" true ls_engine_seen
  expect_poll "running the replaced program wakes the copy check, which reads the job copying" "[\"$ls_unit\"]" ls_value copying
  ls_stop_engines
  expect_poll "the replaced program's copy ends" '[]' ls_value copying
}
# ls_store_lists: a version-2 Automations store written after the start,
# whole by rename as Automations writes it, lists its sync automation by
# its stored name and folders.
ls_store_lists() {
  python3 - "$ls_store" "$home" <<'PY' || { fail "local-sync: the store could not be written"; return; }
import json, os, sys
path, home = sys.argv[1:3]
doc = {"version": 2, "automations": [{"id": "smokestore", "name": "Smoke store copy",
       "command": 'rsync --archive "$HOME/store-from/" "$HOME/store-to/"'}]}
with open(path + ".next", "w") as out:
    json.dump(doc, out)
os.replace(path + ".next", path)
PY
  expect_poll "a store written after the start lists its sync automation by its stored name" \
    "[[\"$ls_auto_unit\", \"Smoke store copy\", \"$home/store-from/\", \"$home/store-to/\", \"automation\"]]" ls_auto_job
}
# The spinner turns only while the theme animates; at motion scale zero the
# item keeps its icon and the dot shows the copy.
ls_spins="$(ipc smoke themeValue spinner.duration | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin) > 0))')" || fail "local-sync: the spinner duration is unreadable"

ls_unit_state inactive dead 0
expect "Local Sync enables" ok ipc shell setPluginEnabled vgs.local-sync true
expect "Local Sync places its widget" ok ipc shell setPluginPlaced vgs.local-sync true
expect_poll "the bar builds the Local Sync item" '"vgs.local-sync"' ipc smoke readInstance "$(bar_key)" vgs.local-sync moduleName
expect_poll "the manager follower starts" 1 ls_count "$ls_follows"
expect_poll "the exec watch runs on the copy programs" true ls_value watching
expect_poll "an inactive unit whose wrapper names rsync is listed with the wrapper's folders" \
  "[[\"$ls_unit\", \"rsync\", \"$ls_from/\", \"$ls_to/\", \"script\", \"inactive\", true]]" ls_job
expect "the inactive job copies nothing" '[]' ls_value copying
expect "the inactive job's bar item is still with no dot" 'false|""' ls_bar

ls_unit_state active running "$(date +%s)"
PATH="$shim:$PATH" HOME="$home" bash "$ls_wrapper" >"$ls_dir/wrapper.log" 2>&1 &
ls_wrapper_pid=$!
printf '%s\n' "$ls_wrapper_pid" >"$ls_main"
ls_manager_line "Started Smoke folder copy."
expect_poll "the manager's line about the unit reads it running" \
  "[[\"$ls_unit\", \"rsync\", \"$ls_from/\", \"$ls_to/\", \"script\", \"active\", true]]" ls_job
expect "a wrapper that only watches copies nothing" '[]' ls_value copying
expect "the watching job's bar item is still with no dot" 'false|""' ls_bar
ls_idle "the watching job"
expect "no copy check runs while no job copies" quiet ls_quiet_window

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
ls_press "Job options" || fail "local-sync: the click on Job options failed"
click_item popup:panel vgs.local-sync "" "" MenuItem Details || fail "local-sync: the click on Details failed"
expect_poll "Details from the job's menu shows that job" "\"$ls_unit\"" ipc smoke readInstance panel vgs.local-sync detailsUnit
ls_press "Back to sync jobs" || fail "local-sync: the click on Back failed"
expect_poll "Back returns to the cards" '""' ipc smoke readInstance panel vgs.local-sync detailsUnit
ls_press "Job options" || fail "local-sync: the second click on Job options failed"
click_item popup:panel vgs.local-sync "" "" MenuItem Remove || fail "local-sync: the click on Remove failed"
expect_poll "Remove from the job's menu asks first" "\"$ls_unit\"" ipc smoke readInstance panel vgs.local-sync confirmUnit
expect "the question has stopped nothing yet" '[]' ls_disables
click_item panel vgs.local-sync Button "Stop and turn off" || fail "local-sync: the click on Stop and turn off failed"
expect_poll "the accepted Remove disables and stops the unit through systemctl" "[[\"--user\", \"disable\", \"--now\", \"--\", \"$ls_unit\"]]" ls_disables
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

# A replaced engine program, then the control without the re-arm.
ls_idle "the job before its engine is replaced"
ls_rearm_wakes
ls_edit "no re-arm" $'                } else {\n                    root.rescanEngines();\n                }' '                }'
ls_rearm_failures="$(
  failures=0 behaviour_failures=0
  ls_rearm_wakes >"$ls_dir/rearm-control.log"
  echo "$failures"
)"
expect "control: without the re-arm the replaced program's checks fail" True python3 -c 'import sys; print(int(sys.argv[1]) >= 1)' "$ls_rearm_failures"
expect "control: without the re-arm the new file's copy is never seen" 1 grep -c -F "  FAIL  running the replaced program wakes the copy check, which reads the job copying: got [] want" "$ls_dir/rearm-control.log"
control_output "$ls_dir/rearm-control.log"
ls_stop_engines
ls_unedit "no re-arm"

# The Automations store written after the start, then the control
# without the store's change handler.
ls_units=("$ls_unit" "$ls_auto_unit")
ls_unit_state
expect "the refresh that reads the automation's unit is accepted" ok ipc vgs.local-sync invoke refresh ""
ls_idle "the automation's unit"
expect "an automation's unit with no store lists no job" '[]' ls_auto_job
ls_store_lists
rm -f -- "$ls_store"
expect "the refresh after the store went is accepted" ok ipc vgs.local-sync invoke refresh ""
expect_poll "the store gone lists no automation job" '[]' ls_auto_job
ls_edit "no store change handler" '        onChanged: store.read()' '        onChanged: {}'
ls_store_failures="$(
  failures=0 behaviour_failures=0
  ls_store_lists >"$ls_dir/store-control.log"
  echo "$failures"
)"
expect "control: without the change handler the store's automation is never listed" 1 printf '%s\n' "$ls_store_failures"
expect "control: the store check reads no automation job instead" 1 grep -c -F '  FAIL  a store written after the start lists its sync automation by its stored name: got [] want' "$ls_dir/store-control.log"
control_output "$ls_dir/store-control.log"
rm -f -- "$ls_store"
ls_unedit "no store change handler"

ls_stop_wrapper
expect "the widget leaves the bar" ok ipc shell setPluginPlaced vgs.local-sync false
expect "Local Sync disables" ok ipc shell setPluginEnabled vgs.local-sync false
expect_poll "a disable leaves no Local Sync record" False record_exists vgs.local-sync
expect_poll "a disable stops the manager follower" gone ls_follower_alive
ls_restore || fail "local-sync: the row's state could not be restored"
