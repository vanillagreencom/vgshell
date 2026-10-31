# The lock, vgs.lock: a first-party service on the core's `lock`
# capability. The harness starts it disabled; this row enables it and locks
# the nested session through each entry point: its IPC function, `vgshell
# lock`, SUPER+DELETE on the nested seat, its idle watch and its before-sleep
# hook. Each lock is read back from the compositor, a monitor naming LOCK
# among the reasons it cannot go solitary in `hyprctl -j monitors`, and
# from the core's lending record. The lock screen's geometry holds the
# design standard on every screen (docs/architecture/design-system.md):
# each part inside its surface, the time and the date at least `stack.row`
# apart, the field and the status line each at least `stack.group` below
# the block above, the field at least `size.control.md` tall and centred;
# its control is a planted reading with the field `stack.group` short.
# While a second lock client, the harness's
# lock-client standing in for another locker, holds the session, the
# plugin's lock takes over under the restore option; the client's unlock
# then unlocks the session, the core ends the plugin's lock, and the plugin
# publishes it and locks again. A sleep whose budget runs out before the
# lock is confirmed is published and sent as a critical notification once
# unlocked, read as its card while vgs.notifications is enabled for it.
# A hook that cannot start is published as such and taken again once the
# setting turns it back on. Disabling the plugin while locked keeps
# the session locked, and the rebuilt plugin hands its lock screen over
# again. The shell killed by its pid while locked leaves the session
# locked, the runner starts the next shell (D069), and that shell's lock
# plugin reads the stranded lock and takes it over through the layer's
# `misc.allow_session_lock_restore`. A sampler reads the session lock from
# the compositor every 100 ms from before the kill until the new shell's
# lock is confirmed and must find it locked each time; its control runs it
# across the second lock client's unlock, which unlocks the session. An
# unlock shorter than one 100 ms sample, between two readings, is not
# read. The runner's relaunch line for each kill names session=locked,
# the runner's own reading of the same lock. The time from the kill to the
# confirmed lock with the lock screen is judged against lock_back_budget_ms,
# below, by harness.sh's latency_pressure_check with the host's CPU
# pressure over the same window; its control is a planted reading one
# millisecond over the budget at the pressure limit, which must read over.
#
# No row types a password: PAM would check it against the real account,
# whose pam_faillock counts each failure. The sandbox's own probe releases
# the core's lock with no password, test code that never ships
# (docs/decisions/D062-native-lock-and-polkit-plugins.md). The evidence that no
# check ran spans the whole row, every plugin rebuild and every shell
# relaunch: each shell's log, kept before its stop or kill, holds a
# `lock: check=started` line for every check started, and the harness's
# watcher records every authentication helper it sees under the sandbox.
# A control copy of the plugin starts one stand-in check, which runs no
# PAM, before the restarts, and a stand-in named unix_chkpwd, a copy of
# sleep, runs early too: at the row's end the whole-row readings must hold
# exactly those two, so a reading of the last instance or the last shell
# alone would fail.
#
# The before-sleep hook runs under stand-ins in the shell's stand-in
# directory: a systemd-inhibit that runs its command with no inhibitor and
# logs the command's lines, a busctl that answers logind's 5 s default and
# no preparation under way, and a dbus-monitor that prints the bus's
# NameAcquired at once and announces one PrepareForSleep once the row
# creates its trigger file, or ends as a failed listener once the row
# creates its stop file. The sandbox's system bus holds no logind.
# Temporary access uses the installed runner's IPC path. Every accepted
# request outlives that client process and keeps the runner-selected shell
# PID. Expiry, overlap refusal, revocation, manual/idle/sleep lock, a hook
# that ends, owner disposal, and a shell stopped or killed during a release,
# which the next shell relocks from the core's release marker, read both
# compositor state and the service's lock facts. The sleep startup cases
# select false, true and unknown preparation using the same busctl
# stand-in; only false may announce ready, and unknown keeps the hook,
# which reads the state again and announces ready once it reads false.
#
# The control installs a copy of the plugin, in the user directory whose id
# wins, that never locks a stranded session: after a kill and a restart the
# session is still locked while the core holds no lock, so the takeover
# reading is not vacuous. `lock` is exclusive, so the row disables the
# capability rows' fixture, acme.probe, when an earlier row left it
# enabled. The row ends with the plugin disabled, the fixture as it found
# it, the stand-ins gone and hyprland.lua as the consent row left it.
# inputs: shell/plugins/vgs.lock/* shell/plugins/vgs.settings/manifest.json shell/plugins/vgs.settings/Window.qml shell/plugins/vgs.settings/ListPage.qml shell/plugins/vgs.settings/PluginPage.qml shell/plugins/vgs.settings/PageHeader.qml shell/plugins/vgs.settings/EditSet.qml shell/plugins/vgs.settings/Steps.js shell/plugins/vgs.settings/SettingField.qml shell/plugins/vgs.settings/KeyField.qml shell/plugins/vgs.settings/StatusRow.qml shell/plugins/vgs.settings/StatusLine.qml shell/plugins/vgs.settings/RequirementRow.qml shell/Core/SessionLock.qml shell/Core/CoverPresentation.qml shell/Commons/SessionLockState.js shell/Hosts/LockHost.qml shell/Core/IdleRegistry.qml shell/Core/Capabilities.qml shell/Core/PluginLogic.js shell/Core/Lifetime.js shell/Core/Plugins.qml shell/shell.qml bin/vgshell bin/vgshell-lock scripts/smoke/lock/* shell/Core/HyprlandLayer.js scripts/smoke/rows/hyprland-consent.sh shell/Core/Notifier.qml shell/plugins/vgs.notifications/*
set -euo pipefail
lock_user_config="$home/.config/vgshell/shell.json"
lock_hypr_lua="$home/.config/hypr/hyprland.lua"
sleep_log="$sandbox/sleep-watch.log"
sleep_trigger="$sandbox/prepare-sleep"
monitor_stop="$sandbox/end-monitor"
# `locked` while any nested monitor names LOCK among the reasons it cannot
# go solitary, which Hyprland keeps while an ext-session-lock holds, its
# client dead or not; `unlocked` otherwise.
session_lock() { hypr -j monitors | py_reply 'import json,sys; print("locked" if any("LOCK" in (m.get("solitaryBlockedBy") or []) for m in json.load(sys.stdin)) else "unlocked")'; }
# The core's lock as [requested, secure, content].
core_requested() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["lock"]["requested"]))'; }
# The cause the core recorded for the request that took the session.
lock_cause() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["lock"]["cause"]))'; }
lock_cover() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["cover"]["placement"]))'; }
core_lock() { ipc shell lent | py_reply 'import json,sys; l=json.load(sys.stdin)["lock"]; print(json.dumps([l["requested"], l["secure"], l["content"]]))'; }
lock_status() { ipc vgs.lock invoke status '' | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps([d[k] for k in sys.argv[1:]]))' "$@"; }
# These calls use the same argv contract as the external tool. `ok` is a
# request acknowledgement; compositor and status transitions are read below.
lock_delegate() { ipc vgs.lock invoke delegate-unlock "$1"; }
lock_pid() { "${shell_env[@]}" "$repo/bin/vgshell" pid; }
lock_service() { ipc smoke readInstance service vgs.lock "$1"; }
lock_sleep_count() { python3 -c 'import sys; print(sum(line.startswith(sys.argv[2]) for line in open(sys.argv[1])))' "$sleep_log" "$1"; }
lock_busctl() { # PreparingForSleep output, InhibitDelayMaxUSec output
  printf '#!/bin/sh\ncase "$5" in PreparingForSleep) echo "%s" ;; *) echo "%s" ;; esac\n' "$1" "${2:-t 5000000}" >"$shim/busctl"
}
lock_released() { # LABEL
  expect_poll "$1: the compositor releases the session" unlocked session_lock
  expect_poll "$1: status confirms temporary desktop access" '[false, false, true]' lock_status locked secure delegateActive
  expect "$1: the runner still selects the same shell" "$shell_qs_pid" lock_pid
}
lock_relocked() { # LABEL
  expect_poll "$1: the compositor locks the session" locked session_lock
  expect_poll "$1: status confirms secure relock and no release" '[true, true, false]' lock_status locked secure delegateActive
  expect "$1: the runner still selects the same shell" "$shell_qs_pid" lock_pid
}
sleep_status() { ipc smoke statusValues vgs.lock | py_reply 'import json,sys; v=json.load(sys.stdin).get("sleep"); print(v["tone"] if v else "unpublished")'; }
# A published status value of vgs.lock as [tone, text], or null.
status_value() { ipc smoke statusValues vgs.lock | py_reply 'import json,sys; v=json.load(sys.stdin).get(sys.argv[1]); print(json.dumps(v if v is None else [v["tone"], v["text"]]))' "$1"; }
# The cards from Lock as [title, tone, urgency, icon].
lock_cards() { plugin_cards Lock | py_reply 'import json,sys; print(json.dumps([[r[0], r[3], r[2], r[4]] for r in json.load(sys.stdin)]))'; }
# lock_no_card_for: `quiet` when no Lock card shows for 2 s, else the cards.
# It reads only while vgs.notifications draws, Silence off.
lock_no_card_for() { local got; for _ in $(seq 1 10); do got="$(lock_cards)" || return 1; [[ $got == '[]' ]] || { echo "$got"; return 0; }; sleep 0.2; done; echo quiet; }
# `vgshell lock`'s first line and its exit status.
vgshell_lock() { local out status=0; out="$("${shell_env[@]}" "$repo/bin/vgshell" lock 2>&1)" || status=$?; printf '%s exit=%s\n' "$(head -n 1 <<<"$out")" "$status"; }
client_said() { if grep -q -x -- "$2" "$1" 2>/dev/null; then echo "$2"; else echo waiting; fi; }
# The lock's binds in the default map; the overlay capture submap repeats
# every plugin bind (hyprland.md).
lock_binds() { hypr -j binds | py_reply 'import json,sys; print(json.dumps(sorted([b["modmask"], b["key"], b["description"]] for b in json.load(sys.stdin) if b["description"].startswith("vgs.lock") and b.get("submap", "") in ("", "default"))))'; }
lock_lent() { ipc shell lent | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps([[s for s in d["shortcuts"] if s.startswith("vgs.lock")], [t for t in d["ipcTargets"] if t == "vgs.lock"], [[w["id"], w["timeout"]] for w in d["idle"] if w["id"] == "vgs.lock"]]))'; }
# The `lock: check=started` lines in every shell log of the row: the kept
# logs of the killed shells and the running shell's.
kept_logs=()
check_starts() { cat -- "${kept_logs[@]}" "$instance_log" | grep -c -F 'lock: check=started' || :; }
no_checks() { expect "$1: no PAM check started and no attempt failed" '[false, 0, 0]' lock_status checking checks failures; }
# The lock screens vgs.lock reports, as the probe reads them.
lock_screens() { ipc smoke lockScreens vgs.lock; }
# Read a lockScreens reply on stdin against the standard: `ok`, or the
# first rule a screen breaks. Arguments: size.control.md, stack.group and
# stack.row.
lock_geometry_check() { py_reply 'import json,sys
screens = json.load(sys.stdin)
control, group, row = (float(v) for v in sys.argv[1:4])
def bad(text):
    print(text)
    sys.exit(0)
if not isinstance(screens, list) or not screens:
    bad("no-screen")
for i, screen in enumerate(screens):
    width, height, parts = screen["width"], screen["height"], screen["parts"]
    for key in ("time", "date", "field", "status"):
        if key not in parts:
            bad("screen%d: no %s" % (i, key))
        x, y, w, h = parts[key]
        if w <= 0 or h <= 0 or x < 0 or y < 0 or x + w > width + 0.5 or y + h > height + 0.5:
            bad("screen%d: %s outside the screen" % (i, key))
    time, date, field, status = (parts[k] for k in ("time", "date", "field", "status"))
    if date[1] < time[1] + time[3] + row - 0.5:
        bad("screen%d: the date is less than stack.row under the time" % i)
    if field[1] < date[1] + date[3] + group - 0.5:
        bad("screen%d: the field is less than stack.group under the date" % i)
    if status[1] < field[1] + field[3] + group - 0.5:
        bad("screen%d: the status line is less than stack.group under the field" % i)
    if field[3] < control - 0.5:
        bad("screen%d: the field is shorter than size.control.md" % i)
    if abs(field[0] + field[2] / 2 - width / 2) > 1:
        bad("screen%d: the field is off centre" % i)
print("ok")' "$@"; }
standard_values() { local key; for key in size.control.md stack.group stack.row; do ipc smoke themeValue "$key" || return; done; }
alive() { if [[ $1 =~ ^[0-9]+$ ]] && kill -0 "$1" 2>/dev/null; then echo alive; else echo gone; fi; }
# Release the core's lock with the probe and read the session unlocked.
release() { # LABEL
  expect "$1: the probe releases the lock" ok ipc smoke sessionUnlock
  expect_poll "$1: the session is unlocked" unlocked session_lock
  expect_poll "$1: the core holds no lock" false core_requested
}
# Set vgs.lock's setting KEY in shell.json, or drop it for null.
set_setting() { # KEY VALUE
  python3 - "$lock_user_config" "$1" "$2" <<'PY'
import json, os, sys
path, key, value = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
config = json.load(open(path))
rows = config.setdefault("plugins", [])
row = next((r for r in rows if r.get("id") == "vgs.lock"), None)
if row is None:
    row = {"id": "vgs.lock"}
    rows.append(row)
if value is None:
    row.pop(key, None)
else:
    row[key] = value
with open(path + ".tmp", "w") as out:
    json.dump(config, out)
os.replace(path + ".tmp", path)
PY
}
restore_lock_hypr_lua() { { printf '%s\n' "pcall(dofile, \"$home/.local/state/vgshell/hypr/vgs.lua\")"; cat -- "$sandbox/hyprland-harness.lua"; } >"$lock_hypr_lua.next" && mv -T -- "$lock_hypr_lua.next" "$lock_hypr_lua"; }
# The session lock sampler: session_lock appended to FILE every 100 ms
# until FILE.stop exists, for 60 s at most, so a row that fails before it
# stops the sampler leaves no reader behind. samples_read FILE:
# `never-unlocked` when every sample, three at least, read locked; else
# the first other reading and the count of samples.
sampler_start() { # FILE
  rm -f -- "$1" "$1.stop"
  (
    for _ in $(seq 1 600); do
      [[ -e $1.stop ]] && break
      session_lock >>"$1" 2>/dev/null || echo unreadable >>"$1"
      sleep 0.1
    done
  ) &
  sampler_pid=$!
}
sampler_stop() { : >"$1.stop"; wait "$sampler_pid" 2>/dev/null || :; } # FILE
samples_read() { # FILE
  local other count
  count="$(wc -l <"$1")" || return
  other="$(grep -v -x -m 1 locked -- "$1" || :)"
  if [[ -n $other ]]; then echo "$other samples=$count"
  elif ((count < 3)); then echo "too-few samples=$count"
  else echo never-unlocked; fi
}
first_sample() { if [[ -s $1 ]]; then head -n 1 -- "$1"; else echo waiting; fi; }
# The ceiling on the time from a SIGKILL to the shell while locked to the
# relaunched shell's confirmed lock with its lock screen, read from the
# core's lending record every 50 ms, so the reading carries at most one
# poll. It holds the runner's first delay, 0.5 s, the new shell's start
# and its stranded-lock reading. Twice the highest of six readings of this
# row on host cachy on 2026-09-30, at load average 5 to 8: 1497 to
# 1606 ms.
lock_back_budget_ms=3212
# Kill the shell by its pid while locked; the runner starts the next shell,
# which the row takes up with harness.sh's adopt_shell, and the sampler
# reads the session lock from before the kill until the caller stops it.
# The killed shell's log is checked and kept first: the rows after this one
# read the next shell's.
# relaunch_lines: the runner's relaunch lines in its log, one per line.
# The relaunch count and the delay depend on how long the shell before ran
# (docs/architecture/runtime.md § Process), so a line is read without
# them.
relaunch_lines() { grep -E '^vgshell: shell=exited .* relaunch=' -- "$shell_log" | sed -E 's/ relaunch=[0-9]+ delay=[0-9.]+//' || :; }
relaunch_count() { relaunch_lines | wc -l; }
last_relaunch() { relaunch_lines | tail -n 1; }
kill_and_relaunch() { # LABEL
  local killed="$shell_qs_pid" kept="$sandbox/lock-shell-${#kept_logs[@]}.log" before
  before="$(relaunch_count)"
  check_unexpected_log "$1: the shell's log before the kill" "$instance_log"
  no_checks "$1: before the kill"
  cp -- "$instance_log" "$kept" || fail "$1: keeping the shell's log failed"
  kept_logs+=("$kept")
  sampler_start "$sandbox/lock-samples"
  expect_poll "$1: the sampler recorded the locked session before the kill" locked first_sample "$sandbox/lock-samples"
  killed_ms="$(now_ms)"
  killed_cpu_us="$(cpu_some_us)"
  kill -KILL "$killed" || fail "$1: SIGKILL to the shell pid $killed failed"
  expect_poll "$1: the killed shell is gone" gone alive "$killed"
  if adopt_shell "$killed"; then ok "$1: the runner started the next shell"; fi
  expect "$1: the runner logged one relaunch for the kill" $((before + 1)) relaunch_count
  expect "$1: the runner read the session locked before the relaunch" "vgshell: shell=exited status=137 session=locked" last_relaunch
}
# The time from the kill to the core's confirmed lock with the plugin's
# lock screen, polled every 50 ms for up to 20 s; `none` past that.
lock_back_ms() {
  for _ in $(seq 1 400); do
    [[ $(core_lock 2>/dev/null) == '[true, true, true]' ]] && { echo $(( $(now_ms) - killed_ms )); return; }
    sleep 0.05
  done
  echo none
}

# The before-sleep stand-ins, ahead of the host's commands on the shell's PATH.
cat >"$shim/systemd-inhibit" <<SH
#!/usr/bin/env bash
set -o pipefail
while [[ \${1:-} == --* ]]; do shift; done
"\$@" | tee -a $(printf %q "$sleep_log")
SH
lock_busctl 'b false'
cat >"$shim/dbus-monitor" <<SH
#!/usr/bin/env bash
echo 'signal sender=org.freedesktop.DBus -> destination=:1.9 serial=2 path=/org/freedesktop/DBus; interface=org.freedesktop.DBus; member=NameAcquired'
until [[ -e $(printf %q "$sleep_trigger") ]]; do
  [[ ! -e $(printf %q "$monitor_stop") ]] || { rm -f -- $(printf %q "$monitor_stop"); exit 3; }
  sleep 0.1
done
rm -f -- $(printf %q "$sleep_trigger")
echo '   boolean true'
exec sleep 600
SH
chmod 755 "$shim/systemd-inhibit" "$shim/busctl" "$shim/dbus-monitor"
rm -f -- "${sleep_log:?}" "${sleep_trigger:?}" "${monitor_stop:?}"

expect "the session is unlocked before the row" unlocked session_lock
auth_watch_start "$sandbox/lock-auth-helpers.log"
# The watcher's stand-in: a copy of sleep named unix_chkpwd, run by the
# harness, never PAM's.
mkdir -p -- "$sandbox/stand-in"
cp -- "$(command -v sleep)" "$sandbox/stand-in/unix_chkpwd"
"$sandbox/stand-in/unix_chkpwd" 30 &
standin_pid=$!
expect_poll "control: the watcher recorded the stand-in unix_chkpwd" "unix_chkpwd $standin_pid" cat -- "$sandbox/lock-auth-helpers.log"
kill -TERM "$standin_pid" || fail "stopping the stand-in unix_chkpwd pid $standin_pid failed"
wait "$standin_pid" 2>/dev/null || :
probe_enabled="$(plugin_enabled acme.probe)" || probe_enabled=unreadable
case "$probe_enabled" in
  True) expect "disabling the capability fixture, which holds lock, is allowed" ok ipc shell setPluginEnabled acme.probe false ;;
  False|absent) ;;
  *) fail "the capability fixture's enabled state is unreadable: $probe_enabled" ;;
esac
expect "enabling the lock plugin is allowed" ok ipc shell setPluginEnabled vgs.lock true
expect_poll "the lock service registered its shortcut, IPC target and idle watch" '[["vgs.lock:lock"], ["vgs.lock"], [["vgs.lock", 300]]]' lock_lent
expect_poll "the nested instance binds SUPER+DELETE to the lock" '[[64, "DELETE", "vgs.lock:lock"]]' lock_binds
expect_poll "the before-sleep hook holds" ok sleep_status
expect "the hook read logind's delay" "ready budget_ms=4000" head -n 1 -- "$sleep_log"
expect "the lock read no stranded lock at start" '[false, true]' lock_status locked strandedDone

settings_page_open vgs.lock
expect_poll "the Lock settings page shows SUPER+DELETE" '"SUPER+DELETE"' key_field vgs.lock lock key
settings_page_close vgs.lock

# The IPC lock, and `vgshell lock` while locked.
expect "the IPC lock answers ok" ok ipc vgs.lock invoke lock ''
expect_poll "the compositor reports the session locked" locked session_lock
expect "the IPC lock is a manual lock" '"manual"' lock_cause
expect_poll "the core holds the confirmed lock with the plugin's lock screen" '[true, true, true]' core_lock
mapfile -t standard < <(standard_values) || :
if [[ ${#standard[@]} -eq 3 ]]; then
  lock_geometry() { lock_screens | lock_geometry_check "${standard[@]}"; }
  expect_poll "the lock screen holds the design standard's geometry" ok lock_geometry
  planted='[{"width": 1000, "height": 800, "parts": {"time": [400, 300, 200, 40], "date": [400, 344, 200, 24], "field": [400, 370, 200, 32], "status": [400, 414, 200, 20]}}]'
  got="$(lock_geometry_check "${standard[@]}" <<<"$planted")" || got=unreadable
  if [[ $got == ok ]]; then fail "control: a planted field stack.group short of the date passed the geometry reading"; else ok "control: a planted field too close to the date fails the geometry reading ($got)"; fi
else
  fail "the standard's values are unreadable: ${standard[*]}"
fi
expect "vgshell lock while locked answers ok" ok "${shell_env[@]}" "$repo/bin/vgshell" lock
expect "the session stays locked" locked session_lock
release "the IPC lock"

# SUPER+DELETE on the nested seat. wtype's keys resolve a bind by keysym
# only, so the row turns that on.
printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = true } })' >>"$lock_hypr_lua"
expect "the nested instance reloads with binds resolved by keysym" ok hypr reload config-only
type_keys -M logo -k Delete -m logo || fail "typing SUPER+DELETE failed"
expect_poll "SUPER+DELETE locked the session" locked session_lock
expect "SUPER+DELETE is a manual lock" '"manual"' lock_cause
release "the SUPER+DELETE lock"
restore_lock_hypr_lua || fail "hyprland.lua is put back after SUPER+DELETE"
expect "the nested instance reloads the consent-wired hyprland.lua" ok hypr reload config-only

# The before-sleep hook: logind's PrepareForSleep locks, and the hook lets
# go once the lock is confirmed. Its lock names the sleep cause, which ends
# any screensaver and shows the lock screen (scripts/test-session-lock.sh,
# scripts/test-plugin-logic.js).
: >"$sleep_trigger"
expect_poll "a sleep locked the session" locked session_lock
expect "the before-sleep hook's lock is a sleep lock" '"sleep"' lock_cause
expect_poll "the hook let the sleep go once the lock was confirmed" "released reason=secure" bash -c 'grep -x "released reason=secure" -- "$1" || :' _ "$sleep_log"
expect "the hook announced the sleep with its budget" "sleep budget_ms=4000" bash -c 'grep -x "sleep budget_ms=[0-9]*" -- "$1" || :' _ "$sleep_log"
release "the sleep lock"
expect_poll "the hook is taken again after the sleep" 2 bash -c 'grep -c -x "ready budget_ms=4000" -- "$1" || :' _ "$sleep_log"
expect "the last sleep is published as locked" '["ok", "The session was locked before the last sleep"]' status_value lastSleep

# Disabled opt-in is a service-policy refusal for this ordinary session
# caller. It supplies no evidence about an excluded identity's transport.
notes_on "temporary access"
expect "temporary access is disabled by default" '[false, false]' lock_status delegateAllowed delegateActive
expect "the delegate tests request a secure lock" ok ipc vgs.lock invoke lock ''
lock_relocked "before temporary access"
expect "the ordinary session caller is refused while disabled" 'refused: delegate-unlock=disabled' lock_delegate '{"seconds":60}'
lock_relocked "disabled temporary access"
set_setting allowDelegateUnlock true
expect_poll "the opt-in reaches the running lock service" '[true]' lock_status delegateAllowed
for lock_argument in '' '{' '{}' '{"seconds":0}' '{"seconds":-1}' '{"seconds":1.5}' '{"seconds":61}' '{"seconds":"1"}' '{"seconds":true}' '{"seconds":null}' '{"seconds":1,"extra":true}'; do
  expect "an invalid duration argument is refused" 'refused: delegate-unlock=argument' lock_delegate "$lock_argument"
done
printf -v lock_oversized '%065d' 0
expect "an argument above the input ceiling is refused" 'refused: delegate-unlock=argument' lock_delegate "$lock_oversized"
lock_relocked "invalid temporary access arguments"
release "before the not-secure refusal"
expect "a delegate cannot release an unlocked session" 'refused: delegate-unlock=not-secure' lock_delegate '{"seconds":60}'
expect "the not-secure refusal leaves the session unlocked" unlocked session_lock
expect "the expiry test requests a secure lock" ok ipc vgs.lock invoke lock ''
lock_relocked "before expiry"
# Five seconds leave the reads below time to see the release before it
# expires.
expect "a short grant returns after recording its expiry" ok lock_delegate '{"seconds":5}'
expect "a second request cannot renew the short grant" 'refused: delegate-unlock=busy' lock_delegate '{"seconds":60}'
lock_released "the short grant"
# The client process has ended. No client-side cleanup is sent: the
# production SessionLock timer must recover access on its own.
lock_relocked "expiry after the delegate client has ended"
expect "expiry relocks with cause release-end" '"release-end"' lock_cause
no_checks "after expiry and overlap refusal"

expect "a sixty-second grant is accepted" ok lock_delegate '{"seconds":60}'
lock_released "the sixty-second grant"
# External desk tools and the runner's restart gate read `shell locked`:
# the released desktop is open.
expect "the desk tools' lock reading is false during temporary access" false ipc shell locked
expect "the external tool's normal cleanup locks early" ok ipc vgs.lock invoke lock ''
lock_relocked "explicit cleanup"
expect "the tool's own cleanup is a manual lock" '"manual"' lock_cause
expect "a grant before setting revocation is accepted" ok lock_delegate '{"seconds":60}'
lock_released "before revocation"
set_setting allowDelegateUnlock false
lock_relocked "setting revocation"
expect "revocation relocks with cause release-end" '"release-end"' lock_cause
expect_poll "revocation also disables new requests" '[false]' lock_status delegateAllowed
expect "a revoked caller cannot get another grant" 'refused: delegate-unlock=disabled' lock_delegate '{"seconds":60}'
set_setting allowDelegateUnlock true
expect_poll "temporary access is enabled again" '[true]' lock_status delegateAllowed

# An idle lock retains its normal authority during temporary access.
set_setting idleLockSeconds 2
expect_poll "the early-lock test owns its two-second idle watch" '[["vgs.lock:lock"], ["vgs.lock"], [["vgs.lock", 2]]]' lock_lent
expect "a grant before idle lock is accepted" ok lock_delegate '{"seconds":60}'
lock_released "before idle relock"
lock_relocked "idle relock during temporary access"
expect "an idle lock during a release keeps its idle cause" '"idle"' lock_cause
set_setting idleLockSeconds null
expect_poll "the idle watch returns to its default" '[["vgs.lock:lock"], ["vgs.lock"], [["vgs.lock", 300]]]' lock_lent

# A hook that ends takes logind's delay with it, so the release ends at once.
expect_poll "the hook is ready before it ends" true lock_service sleepReady
expect "a grant before the hook ends is accepted" ok lock_delegate '{"seconds":60}'
lock_released "before the hook ends"
hook_ends_before="$(log_lines 'lock: delegate-release=ending reason=sleep-hook')" || fail "the instance log is unreadable before the hook ends"
: >"$monitor_stop"
# The cause, not the end state: the grant's own expiry would relock too.
expect_log "the hook's end, not the grant's expiry, ends the release" "$((hook_ends_before + 1))" 'lock: delegate-release=ending reason=sleep-hook'
lock_relocked "the hook ending during temporary access"
expect "the hook's end relocks with cause release-end" '"release-end"' lock_cause
expect_poll "the ended hook is published as unavailable" warning sleep_status
set_setting lockBeforeSleep false
expect_poll "the hook stops before it is taken again" info sleep_status
set_setting lockBeforeSleep null
expect_poll "the hook holds again after it ended" ok sleep_status
expect_poll "the hook taken again restores readiness" true lock_service sleepReady

# Grant first: sleep preparation clears readiness and ends the release.
# The busctl stand-in stays preparing after secure acknowledgement, so a
# restarted hook cannot falsely announce a new non-preparing ready.
expect "a grant before sleep preparation is accepted" ok lock_delegate '{"seconds":60}'
lock_released "before sleep relock"
lock_ready_before="$(lock_sleep_count 'ready ')"
lock_busctl 'b true'
: >"$sleep_trigger"
lock_relocked "sleep preparation during temporary access"
expect "sleep during a release keeps its sleep cause" '"sleep"' lock_cause
expect_poll "sleep preparation clears readiness before locking" false lock_service sleepReady
expect "secure acknowledgement cannot authorize another grant" 'refused: delegate-unlock=sleep' lock_delegate '{"seconds":60}'

# Sleep first: startup true enters sleep without ready, including a
# plugin rebuilt while logind remains preparing.
expect "the preparing lock plugin can be disabled" ok ipc shell setPluginEnabled vgs.lock false
expect_poll "the preparing plugin's content is gone but its lock holds" '[true, true, false]' core_lock
expect "the preparing lock plugin can be rebuilt" ok ipc shell setPluginEnabled vgs.lock true
expect_poll "the rebuilt preparing plugin confirms its lock" '[true, true, true]' core_lock
expect_poll "the rebuilt preparing hook still has no readiness" false lock_service sleepReady
expect "a rebuilt plugin refuses access during preparation" 'refused: delegate-unlock=sleep' lock_delegate '{"seconds":60}'
expect "preparing startup emitted no ready" "$lock_ready_before" lock_sleep_count 'ready '

# Unknown startup state keeps the hook but announces no ready, and grants
# remain refused. The running hook reads the state again every 10 s, so a
# state that turns readable restores readiness with no restart.
set_setting lockBeforeSleep false
expect_poll "the hook stops before its unknown-state startup" info sleep_status
lock_busctl unreadable
set_setting lockBeforeSleep null
expect_poll "unknown preparation still holds the hook" 1 lock_sleep_count 'unconfirmed '
status_hinted() { ipc smoke statusValues vgs.lock | py_reply 'import json,sys; v=json.load(sys.stdin).get(sys.argv[1]); print(json.dumps(v if v is None else [v["tone"], v["text"], v.get("hint")]))' "$1"; }
expect_poll "the unconfirmed hook is published apart from a working one" '["info", "The session locks before sleep", "Temporary unlock waits until VGS can read the sleep state."]' status_hinted sleep
expect "unknown preparation cannot establish readiness" false lock_service sleepReady
expect "unknown preparation emitted no ready" "$lock_ready_before" lock_sleep_count 'ready '
expect "unknown preparation refuses temporary access" 'refused: delegate-unlock=sleep' lock_delegate '{"seconds":60}'
lock_busctl 'b false'
expect_poll "the running hook announces ready once the state reads false" "$((lock_ready_before + 1))" lock_sleep_count 'ready '
expect_poll "the later false state restores readiness" true lock_service sleepReady
expect_poll "the hook is published as working again" ok sleep_status
release "the temporary-access sleep cases"
no_checks "after the temporary-access policy and sleep cases"
notes_off "temporary access"

# A second lock client, the harness's lock-client, holds the session. It
# runs no authentication and is stopped by its pid. With the VGS layer's
# misc:allow_session_lock_restore on, Hyprland lets the plugin's lock
# replace the client's and tells the client nothing; the client's unlock
# then unlocks the session under the plugin's confirmed lock, and the
# core's reading of Hyprland ends that lock as the compositor's.
expected_errors+=('capabilities: lock=ended-by-compositor')
# Wait up to 12 s for CMD to print WANT, and fail nothing: the expect that
# follows reads it. The core reads Hyprland every 2 s and ends a lock on
# the second unlocked reading.
settle() { # WANT CMD...
  local want="$1"; shift
  for _ in $(seq 1 60); do [[ $("$@" 2>/dev/null) == "$want" ]] && return 0; sleep 0.2; done
}
# spawn truncates the client's log, so each start reads its own lines.
start_lock_client() { # LABEL
  spawn_display "$sandbox/lock-client.log" "${shell_env[@]}" -- "$sandbox/lock-client" || return 1
  client_pid="$spawn_pid"
  expect_poll "$1: the second lock client holds the session" locked client_said "$sandbox/lock-client.log" locked
  expect "$1: the session is locked by the other client" locked session_lock
}
stop_lock_client() { # LABEL
  kill -TERM "$client_pid" || fail "$1: SIGTERM to the lock client pid $client_pid failed"
  expect_poll "$1: the other client let the session go" unlocked client_said "$sandbox/lock-client.log" unlocked
}
start_lock_client "takeover"
expect "takeover: vgshell lock takes the lock over" "ok exit=0" vgshell_lock
expect_poll "takeover: the core holds the confirmed lock" '[true, true, true]' core_lock
# Control for the sampler: across the other client's unlock it reads the
# session unlocked.
sampler_start "$sandbox/lock-samples-control"
stop_lock_client "takeover"
settle '[false, false, true]' core_lock
sampler_stop "$sandbox/lock-samples-control"
got="$(samples_read "$sandbox/lock-samples-control")" || got=unreadable
if [[ $got == unlocked\ samples=* ]]; then ok "control: the sampler reads the unlock the other client made ($got)"; else fail "control: the sampler across the other client's unlock read $got"; fi
expect "takeover: the core ended the lock the other client's unlock released" '[false, false, true]' core_lock
expect "takeover: the session is unlocked" unlocked session_lock
expect_poll "takeover: the plugin counted the end" '[1, false, false]' lock_status refusals locked secure
expect "takeover: the lock status warns of it" '["warning", "Hyprland refused or ended the last lock: another lock screen may hold the session"]' status_value lock
expect "takeover: vgshell lock locks again" "ok exit=0" vgshell_lock
expect_poll "takeover: the core holds the confirmed lock again" '[true, true, true]' core_lock
expect "takeover: the lock status is ready again" '["ok", "Ready"]' status_value lock
release "the lock after the takeover"

# A sleep whose budget runs out before the lock is confirmed: logind's delay
# reads 1 s, so the hook's budget is 1 ms. The hook lets the sleep go as
# timed out, the plugin publishes it, and the user sees its notification
# once back at the desktop, not over the lock screen.
expected_errors+=('lock: sleep=unlocked reason=timeout')
retake_hook() { # LABEL
  set_setting lockBeforeSleep false
  expect_poll "$1: turning the setting off publishes the hook off" info sleep_status
  set_setting lockBeforeSleep null
  expect_poll "$1: the hook holds again" ok sleep_status
}
notes_on "lock timeout"
lock_busctl 'b false' 't 1000000'
retake_hook "a 1 s delay"
expect_poll "timeout: the hook read the short delay" "ready budget_ms=1" tail -n 1 -- "$sleep_log"
: >"$sleep_trigger"
expect_poll "timeout: the hook let the sleep go on its budget" "released reason=timeout" bash -c 'grep -x "released reason=timeout" -- "$1" || :' _ "$sleep_log"
expect_poll "timeout: the sleep still locked the session" locked session_lock
expect_poll "timeout: the last sleep is published as unconfirmed" '["danger", "The computer slept before VGS confirmed the lock"]' status_value lastSleep
expect "timeout: no notification shows over the lock screen" quiet lock_no_card_for
release "the timed-out sleep lock"
expect_poll "timeout: the user is told once back at the desktop" '[["The session was not locked before sleep", "danger", 2, "lock-open"]]' lock_cards
notes_off "lock timeout"
lock_busctl 'b false'
retake_hook "logind's default delay"
expect_poll "the hook read logind's default delay again" "ready budget_ms=4000" tail -n 1 -- "$sleep_log"

# A hook that cannot start, here a systemd-inhibit whose interpreter does
# not exist, is published as such, and turning the setting back on takes it
# again at once.
mv -- "$shim/systemd-inhibit" "$sandbox/systemd-inhibit.good"
set_setting lockBeforeSleep false
expect_poll "turning the setting off publishes the hook off" info sleep_status
printf '#!/nonexistent/interpreter\n' >"$shim/systemd-inhibit"
chmod 755 "$shim/systemd-inhibit"
set_setting lockBeforeSleep null
expect_poll "a hook that cannot start is published as such" '["warning", "Locking before sleep is unavailable. Lock the screen before sleep."]' status_value sleep
mv -- "$sandbox/systemd-inhibit.good" "$shim/systemd-inhibit"
set_setting lockBeforeSleep false
expect_poll "the setting off again" info sleep_status
set_setting lockBeforeSleep null
expect_poll "the hook holds again once it can start" ok sleep_status

# The idle watch: two seconds with no input lock the session. The setting
# goes back before any key, which would start the next idle period.
set_setting idleLockSeconds 2
expect_poll "the idle watch follows the setting" '[["vgs.lock:lock"], ["vgs.lock"], [["vgs.lock", 2]]]' lock_lent
expect_poll "two seconds without input locked the session" locked session_lock
expect "the lock stage watch's lock is an idle lock" '"idle"' lock_cause
set_setting idleLockSeconds null
expect_poll "the idle watch is back at its default" '[["vgs.lock:lock"], ["vgs.lock"], [["vgs.lock", 300]]]' lock_lent
release "the idle lock"

# A shell that stops during a release, as `vgshell restart` stops it by
# TERM to the runner, or that is killed, takes the expiry with it. The
# core's release marker, written before the unlock, makes the next shell
# lock at its start; the confirmed relock removes the marker. The control
# starts a copy whose root never reads the marker: it starts unlocked,
# with the marker still there, and the shipped shell after it relocks.
notes_on "release across a shell stop"
expected_errors+=('capabilities: lock-release=recovered')
release_marker="$rt_dir/vgshell/lock-release"
marker_state() { if [[ -e $release_marker ]]; then echo present; else echo absent; fi; }
# The running shell's log, checked and kept before the shell ends.
keep_shell_log() { # LABEL
  local kept="$sandbox/lock-shell-${#kept_logs[@]}.log"
  check_unexpected_log "$1: the shell's log before it ends" "$instance_log"
  cp -- "$instance_log" "$kept" || fail "$1: keeping the shell's log failed"
  kept_logs+=("$kept")
}
# A secure lock, then a sixty-second grant read back as released, with the
# marker on the disk.
grant_released() { # LABEL
  expect "$1: the test requests a secure lock" ok ipc vgs.lock invoke lock ''
  lock_relocked "$1: before the grant"
  expect_poll "$1: the sleep hook is ready" true lock_service sleepReady
  expect "$1: a grant is accepted" ok lock_delegate '{"seconds":60}'
  lock_released "$1"
  expect "$1: the core marked the release before the unlock" present marker_state
}
# The shell stopped as `vgshell restart` stops it, then TREE's shell started.
restart_shell() { # LABEL TREE
  keep_shell_log "$1"
  stop_shell || fail "$1: the shell did not stop"
  start_shell "$2" "$shell_log" no-bar || fail "$1: the next shell did not start"
}
recovered_relock() { # LABEL
  expect_poll "$1: the next shell asks for the lock at its start" true core_requested
  expect "$1: the recovered lock has cause release-end" '"release-end"' lock_cause
  lock_relocked "$1"
  expect_log "$1: the next shell read the release marker" 1 'capabilities: lock-release=recovered'
  expect_poll "$1: the confirmed relock removes the marker" absent marker_state
}
grant_released "restart"
restart_shell "restart during a release" "$repo"
recovered_relock "restart during a release relocks at the next start"

grant_released "kill"
keep_shell_log "kill during a release"
lock_killed="$shell_qs_pid"
kill -KILL "$lock_killed" || fail "kill during a release: SIGKILL to the shell pid $lock_killed failed"
expect_poll "kill during a release: the killed shell is gone" gone alive "$lock_killed"
if adopt_shell "$lock_killed"; then ok "kill during a release: the runner started the next shell"; fi
recovered_relock "a shell killed during a release relocks at the next start"

if copy_tree no-recover && edit_tree no-recover shell/shell.qml \
    $'        if (guarded) Capabilities.sessionLock.recoverRelease();\n' ''; then
  grant_released "control"
  restart_shell "control" "$sandbox/tree-no-recover"
  expect "control: a copy that never reads the marker starts with no lock" false core_requested
  expect "control: the desktop stays open under that copy" unlocked session_lock
  expect "control: the marker outlives that copy" present marker_state
  restart_shell "after the control" "$repo"
  recovered_relock "the shipped shell relocks the release the control left"
fi
release "the release across a shell stop"
notes_off "release across a shell stop"

# Disposing a release owner requests lock before removing its content.
notes_on "temporary-access owner lifecycle"
expect "the release-owner disposal test requests a secure lock" ok ipc vgs.lock invoke lock ''
lock_relocked "before release-owner disposal"
expect "a grant before disabling the owner is accepted" ok lock_delegate '{"seconds":60}'
lock_released "before release-owner disposal"
expect "disabling a temporarily released owner is allowed" ok ipc shell setPluginEnabled vgs.lock false
expect_poll "disposal relocks with no dead plugin content" '[true, true, false]' core_lock
expect "owner disposal relocks with cause release-end" '"release-end"' lock_cause
expect "the compositor is locked after disposing the release owner" locked session_lock
expect "disposal keeps the runner-selected shell" "$shell_qs_pid" lock_pid
expect "the disposed owner can be built again" ok ipc shell setPluginEnabled vgs.lock true
expect_poll "the replacement owner supplies the locked screen" '[true, true, true]' core_lock
expect_poll "the replacement owner establishes sleep readiness" true lock_service sleepReady
lock_relocked "the replacement after release-owner disposal"
release "the release-owner disposal lock"

# Disabling the plugin while locked keeps the session locked; the rebuilt
# plugin hands its lock screen over again.
no_checks "before the disable"
expect "the IPC lock answers ok before the disable" ok ipc vgs.lock invoke lock ''
expect_poll "the session is locked before the disable" '[true, true, true]' core_lock
expect "disabling the lock plugin while locked is allowed" ok ipc shell setPluginEnabled vgs.lock false
expect_poll "the disabled plugin's lock screen is gone and the lock stays" '[true, true, false]' core_lock
expect "the session stays locked with the plugin disabled" locked session_lock
expect "enabling the lock plugin again is allowed" ok ipc shell setPluginEnabled vgs.lock true
expect_poll "the rebuilt plugin hands its lock screen over again" '[true, true, true]' core_lock
release "the lock across a disable"

# Control: a copy whose IPC lock starts one stand-in check, with PAM's
# start taken out so no PAM runs. Its log line is in the first shell's log,
# which the two restarts below leave behind, and the row's last reading
# must still count it.
no_checks "before the stand-in check"
control_dir="$home/.config/vgshell/plugins/vgs.lock"
mkdir -p -- "$control_dir"
cp -R -- "$repo/shell/plugins/vgs.lock/." "$control_dir/"
python3 - "$control_dir/Service.qml" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
edits = [
    ('shell.ipc.handle("lock", () => root.lock("manual"));', 'shell.ipc.handle("lock", () => { const reply = root.lock("manual"); root.submit("stand-in"); root.checking = true; return reply; });'),
    ("        if (!pam.start()) fail();", "        fail();"),
]
for needle, replacement in edits:
    assert text.count(needle) == 1, "stand-in control: must match once: " + needle
    text = text.replace(needle, replacement)
open(path, "w").write(text)
PY
expected_errors+=('plugins: .*vgs\.lock')
lock_dir_of() { ipc shell listPlugins | py_reply 'import json,sys; print([p["dir"] for p in json.load(sys.stdin)["plugins"] if p["id"] == "vgs.lock"][0])'; }
rescan_theme_follow() {
  local label="$1" follows
  follows="$(log_lines 'INFO qml: theme: follow=')" || fail "$label: the instance log is unreadable before the rescan"
  rescan "$label"
  expect_log "$label: theme follow logged its completion" "$((follows + 1))" 'INFO qml: theme: follow='
  expect_poll "$label: theme follow is idle" idle theme_idle
}
expect "the rebuild test requests a secure lock" ok ipc vgs.lock invoke lock ''
lock_relocked "before rebuilding the release owner"
expect "a grant before rebuilding the owner is accepted" ok lock_delegate '{"seconds":60}'
lock_released "before rebuilding the release owner"
rescan_theme_follow "rescan over the stand-in copy answers ok"
expect_poll "the stand-in copy is the plugin the shell runs" "$control_dir" lock_dir_of
lock_relocked "rebuilding the release owner"
expect_poll "the rebuilt checking-state fixture has sleep readiness" true lock_service sleepReady
expect "the stand-in copy's IPC lock answers ok" ok ipc vgs.lock invoke lock ''
expect_poll "control: the stand-in copy started one check" '[1, 1]' lock_status checks failures
expect "the stand-in copy holds the checking state without PAM" '[true]' lock_status checking
expect "a pending check refuses temporary access" 'refused: delegate-unlock=checking' lock_delegate '{"seconds":60}'
lock_relocked "the pending-check refusal"
expect_poll "control: the shell's log holds the stand-in check" 1 check_starts
release "the stand-in check"
rm -r -- "${control_dir:?}"
rescan_theme_follow "rescan after removing the stand-in copy answers ok"
expect_poll "the shipped plugin runs again after the stand-in" "$repo/shell/plugins/vgs.lock" lock_dir_of
expect_poll "the rebuilt shipped plugin holds its sleep hook again" ok sleep_status
notes_off "temporary-access owner lifecycle"

# Control: a copy that never locks a stranded session. After the kill and
# the restart the session is still locked, and the core holds no lock.
mkdir -p -- "$control_dir"
cp -R -- "$repo/shell/plugins/vgs.lock/." "$control_dir/"
python3 - "$control_dir/Service.qml" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
needle = '                root.lock("restore");\n            }\n        }\n    }\n\n    Timer {\n        id: strandedRetry'
assert text.count(needle) == 1, "lock control: the stranded lock call must match once"
open(path, "w").write(text.replace(needle, '            }\n        }\n    }\n\n    Timer {\n        id: strandedRetry', 1))
PY
rescan_theme_follow "rescan over the control copy answers ok"
expect_poll "the control copy is the plugin the shell runs" "$control_dir" lock_dir_of
expect "the control's IPC lock answers ok" ok ipc vgs.lock invoke lock ''
expect_poll "the control's session is locked" '[true, true, true]' core_lock
kill_and_relaunch "the control"
expect_poll "the control's relaunched lock read the stranded lock" '[false, true]' lock_status locked strandedDone
sampler_stop "$sandbox/lock-samples"
expect "the control's session never read unlocked across the kill" never-unlocked samples_read "$sandbox/lock-samples"
got="$(core_lock)" || got=unreadable
if [[ $got == '[false, false, false]' && $(session_lock) == locked ]]; then ok "control: a copy that never takes a stranded lock over leaves the core without it"; else fail "control: the takeover reading got core=$got over a copy that never takes the lock over"; fi
expect "the probe takes the stranded lock over" ok ipc smoke sessionLockBare
expect_poll "the probe's lock is confirmed" '[true, true, false]' core_lock
release "the control"
rm -r -- "$control_dir"
rescan_theme_follow "rescan after removing the control copy answers ok"
expect_poll "the shipped plugin runs again" "$repo/shell/plugins/vgs.lock" lock_dir_of

# The shell dies while locked: the session stays locked, and the next
# shell's lock plugin takes the stranded lock over with its lock screen.
expect "the IPC lock answers ok before the kill" ok ipc vgs.lock invoke lock ''
expect_poll "the session is locked before the kill" '[true, true, true]' core_lock
kill_and_relaunch "the kill"
lock_back="$(lock_back_ms)"
lock_back_cpu_us="$(cpu_some_us)"
sampler_stop "$sandbox/lock-samples"
lock_back_pressure=unmeasured
[[ $lock_back =~ ^[0-9]+$ ]] && lock_back_pressure="$(cpu_some_pct "$killed_cpu_us" "$lock_back_cpu_us" "$lock_back")"
latency_pressure_check lock lock_back "$lock_back" "$lock_back_pressure" "$lock_back_budget_ms"
expect "control: lock back one millisecond over budget at the pressure limit fails" over latency_pressure_verdict "$((lock_back_budget_ms + 1))" "$latency_pressure_limit" "$lock_back_budget_ms"
echo "  lock samples=$(wc -l <"$sandbox/lock-samples")"
expect "the session never read unlocked from before the kill to the relaunched lock" never-unlocked samples_read "$sandbox/lock-samples"
expect "the session is still locked" locked session_lock
expect "the relaunched shell's lock is a restore lock" '"restore"' lock_cause
expect "a shell restarted into a locked session presents no cover" '"none"' lock_cover
release "the taken-over lock"

no_checks "the row's end"
expect "no authentication helper runs under the shell" none auth_helpers "$shell_qs_pid"
expect "over the whole row, every shell log holds the stand-in check alone" 1 check_starts
kill "$auth_watch_pid" 2>/dev/null || fail "stopping the helper watcher pid $auth_watch_pid failed"
expect "over the whole row, the watcher saw the stand-in unix_chkpwd alone" "unix_chkpwd $standin_pid" cat -- "$sandbox/lock-auth-helpers.log"
expect "disabling the lock plugin is allowed" ok ipc shell setPluginEnabled vgs.lock false
expect_poll "disable released the lock's shortcut, IPC target and idle watch" '[[], [], []]' lock_lent
expect_poll "the nested instance drops the lock's bind" '[]' lock_binds
set_setting allowDelegateUnlock null
rm -f -- "$shim/systemd-inhibit" "$shim/busctl" "$shim/dbus-monitor" "$sandbox/stand-in/unix_chkpwd" "$monitor_stop"
expect "hyprland.lua is as the consent row left it" same bash -c 'cmp -s <(sed 1d "$1") "$2" && echo same || echo differs' _ "$lock_hypr_lua" "$sandbox/hyprland-harness.lua"
if [[ $probe_enabled == True ]]; then
  expect "re-enabling the capability fixture is allowed" ok ipc shell setPluginEnabled acme.probe true
fi
