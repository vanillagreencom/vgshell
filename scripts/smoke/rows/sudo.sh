# vgs.sudo, the passwordless sudo lock, over the core's `sudo` capability
# (D103), with no host sudo. The sandbox copy of bin/vgshell-sudo-grant
# resolves every command in $sudo_grant_root, the harness's tree, whose
# sudo is a copy of the sudo sentinel. The row plants a root half there and
# stands a sudo over the sentinel that answers `-n -l -l` with the listing
# the row writes, as sudo 1.9.17 lists a grant, or `a password is
# required` while it holds none, and logs any other call to the one
# authentication log, which rows/auth-sentinel.sh reads empty. The stand-in
# terminal runs no grant: a core command becomes `true`, held while the row
# changes the listing, so the run's end is what makes the core read again.
# A notify-send stand-in in the shell's own PATH directory records each
# notice; vgs.notifications is enabled for the row, so the core sends.
#
# Rows: with no root half the core reads `absent` and runs no sudo; a click
# on the lock hands the terminal `vgshell sudo grant 15`, the setting's
# default, and the core reads the grant only after the run ends: the lock
# opens in the warning tone, the tooltip names the deadline's time, the
# deadline timer is armed and one warning notice goes out. With the
# Settings page's Indefinitely, a click on the open lock hands the
# terminal `vgshell sudo revoke` in the plain presentation, the lock closes
# and one success notice goes out; the next click hands it `vgshell sudo
# grant indefinite`, the lock opens with no deadline and no timer, and a
# revoke whose read still finds the grant sends one danger notice. A run
# the launcher opens is read after it ends too, and sends no notice. A
# timed grant six seconds long closes the lock at its deadline with no
# run. Controls: a duration outside the judge's is refused and starts no
# terminal; a plugin that names no `sudo` holds no `shell.sudo`; each read
# before a run's end shows the change is that run's read.
# Every reading is expect_poll's: 200 reads 0.2 s apart; a run's end is
# expect_run_end's.
# inputs: shell/plugins/vgs.sudo/* shell/Core/SudoGrant.qml shell/Core/Capabilities.qml shell/Core/TuiRunner.qml shell/Core/TuiRecords.qml shell/Core/PluginLogic.js shell/Core/Notifier.qml shell/Core/NotificationHub.qml bin/vgshell-sudo-grant bin/vgshell-tui bin/vgshell bin/vgshell-pkg bin/lib/tui.sh shell/Ui/controls/BarItem.qml shell/Ui/BarWidget.qml shell/plugins/vgs.settings/* shell/plugins/vgs.notifications/* scripts/smoke/toplevel/* scripts/smoke/rows/capabilities.sh
set -euo pipefail
sudo_uid="$(id -u)"
sudo_bin="$sudo_grant_root/usr/bin"
sudo_half="$sudo_grant_root/usr/local/bin/vgs-sudo-grant"
sudo_timed_file="$sudo_grant_root/etc/sudoers.d/99-vgs-nopasswd-$sudo_uid"
sudo_indefinite_file="$sudo_grant_root/etc/sudoers.d/99-vgs-permanent-nopasswd-$sudo_uid"
sudo_list="$sandbox/sudo-row.list"
sudo_calls="$sandbox/sudo-row.calls"
sudo_sent="$sandbox/sudo-row.notices"
sudo_config="$sandbox/sudo-row.shell.json"
sentinel_of() { if grep -q -F -- "$auth_log" "$1"; then echo sentinel; else echo replaced; fi; }
auth_count() { if [[ -e $auth_log ]]; then wc -l <"$auth_log"; else echo 0; fi; }
expect "the sandbox copy of the grant resolves in the stand-in tree" 1 grep -c -x -F -- "prefix=$sudo_grant_root" "$repo/bin/vgshell-sudo-grant"
expect "the tree's sudo is the harness's sentinel" sentinel sentinel_of "$sudo_bin/sudo"
expect "the tree holds no root half" absent bash -c '[[ -e $1 ]] && echo present || echo absent' _ "$sudo_half"

# The core's read as `state until rootHalf`, one field of its record, and
# the holders of `sudo`.
sudo_core() { ipc shell lent | py_reply 'import json,sys; s=json.load(sys.stdin)["sudo"]["state"]; print(s["state"] + " " + s["until"] + " " + s["rootHalf"])'; }
sudo_record() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["sudo"][sys.argv[1]]))' "$1"; }
sudo_holders() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["holders"].get("sudo", [])))'; }
sudo_warning="$(ipc smoke themeValue badge.tone.warning.foreground)" || fail "the warning tone is unreadable"
# The lock as drawn, `<icon> <tone> <tooltip>`: the tone `warning` or
# `other`, the tooltip `off`, `clock HH:MM` when it names a time, or
# `no-clock` for an open lock's that names none; `absent` before it is
# drawn.
sudo_lock() {
  local key icon colours tip granted
  key="$(bar_key)" || return
  icon="$(ipc smoke readDescendant "$key" vgs.sudo Icon name)" && colours="$(ipc smoke itemColours "$key" vgs.sudo Widget Icon)" \
    && tip="$(ipc smoke readInstance "$key" vgs.sudo tooltipText)" && granted="$(ipc smoke readInstance "$key" vgs.sudo granted)" || return
  python3 - "$icon" "$colours" "$tip" "$granted" "$sudo_warning" <<'PY'
import json, re, sys
icon, colours, tip, granted, warning = sys.argv[1:6]
if "absent" in (icon, colours, tip, granted):
    print("absent"); sys.exit()
colour = json.loads(colours)[0][0]
value = json.loads(warning).lower()
tone = "warning" if "#" + value[3:9] + value[1:3] == colour else "other"
m = re.search(r"[0-9][0-9]:[0-9][0-9]", json.loads(tip))
kind = ("clock " + m.group(0)) if m else ("no-clock" if json.loads(granted) else "off")
print(json.loads(icon) + " " + tone + " " + kind)
PY
}
# sudo_listing none|indefinite|timed SECONDS: the listing the stand-in
# prints, as sudo 1.9.17p2 lists the grant files under LC_ALL=C; prints
# the timed grant's deadline as ISO 8601.
sudo_listing() {
  case "$1" in
    none) rm -f -- "$sudo_list"; return ;;
    indefinite) printf 'User %s may run the following commands on host:\n\nSudoers entry: %s\n    RunAsUsers: ALL\n    Options: !authenticate\n    Commands:\n\tALL\n' "$USER" "$sudo_indefinite_file" >"$sudo_list" ;;
    timed)
      python3 - "$2" "$sudo_timed_file" "$sudo_list" "$USER" <<'PY'
import datetime, sys
seconds, entry, out, user = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
at = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0) + datetime.timedelta(seconds=seconds)
with open(out, "w") as f:
    f.write("User %s may run the following commands on host:\n\nSudoers entry: %s\n    RunAsUsers: ALL\n    Options: !authenticate\n    NotAfter: %s\n    Commands:\n\tALL\n" % (user, entry, at.strftime("%Y%m%d%H%M%SZ")))
print(at.strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
      ;;
  esac
}
# The local HH:MM of ISO.
sudo_clock() { python3 -c 'import datetime,sys; print(datetime.datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00")).astimezone().strftime("%H:%M"))' "$1"; }
# The notices the stand-in recorded after the first N, each [tone, icon].
sudo_notices_since() {
  python3 - "$sudo_sent" "$1" <<'PY'
import json, os, sys
path, skip = sys.argv[1], int(sys.argv[2])
calls = [json.loads(l) for l in open(path).read().split("\n")[:-1]] if os.path.exists(path) else []
def hint(a, name):
    found = [x.split(":", 2)[2] for x in a if x.startswith("--hint=string:x-vgs-" + name + ":")]
    return found[0] if found else None
print(json.dumps([[hint(a, "tone"), hint(a, "icon")] for a in calls[skip:]]))
PY
}
sudo_notice_count() { if [[ -f $sudo_sent ]]; then wc -l <"$sudo_sent"; else echo 0; fi; }
sudo_words() { # PRESENTATION KEY ARGS...
  local presentation="$1" key="$2"
  shift 2
  words "--app-id=org.vgs.tui" "--title=VGS · Passwordless sudo" -- "$tui_self" present --presentation "$presentation" \
    --record "$key" --run RUN --record-dir "$rt_dir/vgshell/tui" --app-id org.vgs.tui --window-title "VGS · Passwordless sudo" -- "$core_vgshell" sudo "$@"
}
sudo_click() { click_centre "$(bar_key)" vgs.sudo || fail "sudo: the click on the lock failed"; }

# The notices reach the stand-in: with vgs.notifications enabled the core
# sends whether or not the shell already holds the notification name.
cp -- "$home/.config/vgshell/shell.json" "$sudo_config"
sudo_notifications_were="$(plugin_enabled vgs.notifications)"
if [[ $sudo_notifications_were == False ]]; then
  expect "enabling vgs.notifications for the lock's notices is allowed" ok ipc shell setPluginEnabled vgs.notifications true
fi
[[ ! -e $shim/notify-send ]] || mv -- "$shim/notify-send" "$sandbox/sudo-row.notify-send.saved"
rm -f -- "$sudo_sent"
cat >"$shim/notify-send" <<EOF
#!/usr/bin/env bash
python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "\$@" >>"$sudo_sent"
EOF
chmod 755 "$shim/notify-send"

# No root half: the read runs no sudo.
sudo_auth_before="$(auth_count)"
expect "enabling the lock is allowed" ok ipc shell setPluginEnabled vgs.sudo true
expect_poll "the lock is built on the bar" '"vgs.sudo"' ipc smoke readInstance "$(bar_key)" vgs.sudo moduleName
expect_poll "the lock holds sudo" '["vgs.sudo"]' sudo_holders
expect_poll "with no root half the core reads absent" "absent  absent" sudo_core
expect "the absent read reached no sudo" "$sudo_auth_before" auth_count
expect_poll "the lock is closed, not in the warning tone, and its tooltip says off" "lock other off" sudo_lock

# A root half that is this copy, and a sudo that lists.
cp -- "$repo/bin/vgshell-sudo-grant" "$sudo_half"
chmod 755 "$sudo_half"
: >"$sudo_calls"
sudo_listing none
# The grant runs it with the tree's PATH, so it names cat by its path.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>%q\nif [ "$*" = "-n -l -l" ]; then\n  if [ -f %q ]; then %q %q; exit 0; fi\n  echo "sudo: a password is required" >&2\n  exit 1\nfi\nprintf "%%s\\n" "sudo $*" >>%q\nexit 1\n' \
  "$sudo_calls" "$sudo_list" "$(command -v cat)" "$sudo_list" "$auth_log" | sentinel_stand_over "$sudo_bin/sudo"
expect "the tree's sudo is the row's stand-in" row bash -c 'grep -q -F -- "$1" "$2" && echo row || echo other' _ "$sudo_calls" "$sudo_bin/sudo"

terminal_stand_in
terminal_ready "sudo"

# A click on the closed lock: the grant with the setting's default.
hold_runs
forget_record
sudo_sent_before="$(sudo_notice_count)"
sudo_click
expect_poll "a click on the closed lock hands the terminal vgshell sudo grant 15" "$(sudo_words full core/sudo-grant grant 15)" recorded
sudo_until="$(sudo_listing timed 3600)"
expect "the core reads the grant only once the run ends" "absent  absent" sudo_core
release_runs
expect_run_end "the grant run ends" core/sudo-grant
expect_poll "the run's end reads the timed grant" "active $sudo_until current" sudo_core
expect_poll "the lock opens in the warning tone, its tooltip naming the deadline's time" "lock-open warning clock $(sudo_clock "$sudo_until")" sudo_lock
expect "the core arms the deadline timer" true sudo_record deadline
expect_poll "the grant sends one warning notice with the open lock" '[["warning", "lock-open"]]' sudo_notices_since "$sudo_sent_before"
expect "the status reads listed the rules alone" "" bash -c 'grep -v -x -F -- "-n -l -l" "$1" || true' _ "$sudo_calls"

# The Settings page's default duration.
settings_page_open vgs.sudo
expect "the Settings page sets the default duration to Indefinitely" ok ipc smoke invokeInstance window vgs.settings applySetting '{"id":"vgs.sudo","key":"defaultDuration","value":"indefinite"}'
settings_page_close vgs.sudo

# A click on the open lock: the revoke, in the plain presentation.
hold_runs
forget_record
sudo_sent_before="$(sudo_notice_count)"
sudo_click
expect_poll "a click on the open lock hands the terminal vgshell sudo revoke" "$(sudo_words plain core/sudo-revoke revoke)" recorded
sudo_listing none
expect "the core reads the revoke only once the run ends" "active $sudo_until current" sudo_core
release_runs
expect_run_end "the revoke run ends" core/sudo-revoke
expect_poll "the revoke's end reads no grant" "inactive  current" sudo_core
expect_poll "the lock closes" "lock other off" sudo_lock
expect "no deadline timer runs" false sudo_record deadline
expect_poll "the revoke sends one success notice with the lock" '[["success", "lock"]]' sudo_notices_since "$sudo_sent_before"

# The next click grants the setting's Indefinitely.
hold_runs
forget_record
sudo_sent_before="$(sudo_notice_count)"
sudo_click
expect_poll "a click hands the terminal the setting's vgshell sudo grant indefinite" "$(sudo_words full core/sudo-grant grant indefinite)" recorded
sudo_listing indefinite
release_runs
expect_run_end "the indefinite grant run ends" core/sudo-grant
expect_poll "the run's end reads the indefinite grant" "active indefinite current" sudo_core
expect_poll "the indefinite lock opens in the warning tone, its tooltip naming no time" "lock-open warning no-clock" sudo_lock
expect "no deadline timer runs for an indefinite grant" false sudo_record deadline
expect_poll "the indefinite grant sends one warning notice" '[["warning", "lock-open"]]' sudo_notices_since "$sudo_sent_before"

# A revoke whose read still finds the grant says so.
hold_runs
forget_record
sudo_sent_before="$(sudo_notice_count)"
sudo_reads_before="$(sudo_record reads)"
sudo_click
expect_poll "a click hands the terminal vgshell sudo revoke again" "$(sudo_words plain core/sudo-revoke revoke)" recorded
release_runs
expect_run_end "the failed revoke run ends" core/sudo-revoke
expect_poll "the failed revoke sends one danger notice" '[["danger", "lock-open"]]' sudo_notices_since "$sudo_sent_before"
expect "the core read again after the failed revoke" True python3 -c 'import sys; print(int(sys.argv[1]) > int(sys.argv[2]))' "$(sudo_record reads)" "$sudo_reads_before"
expect "the grant still reads indefinite" "active indefinite current" sudo_core

# A run the launcher opens is read after it ends and sends no notice.
hold_runs
forget_record
sudo_sent_before="$(sudo_notice_count)"
expect "the launcher opens the core grant" ok ipc shell openTui core/sudo-grant
expect_poll "the launcher hands the terminal vgshell sudo grant" "$(sudo_words full core/sudo-grant grant)" recorded
sudo_listing none
expect "the core reads the launcher's run only once it ends" "active indefinite current" sudo_core
release_runs
expect_run_end "the launcher's grant run ends" core/sudo-grant
expect_poll "the launcher's run's end reads no grant" "inactive  current" sudo_core
expect "the launcher's run sent no notice" "[]" sudo_notices_since "$sudo_sent_before"

# A timed grant closes the lock at its deadline, with no run.
hold_runs
forget_record
expect "the launcher opens the core grant for a short grant" ok ipc shell openTui core/sudo-grant
sudo_until="$(sudo_listing timed 6)"
release_runs
expect_run_end "the short grant run ends" core/sudo-grant
expect_poll "the run's end reads the short grant" "active $sudo_until current" sudo_core
expect "the core arms the short grant's deadline" true sudo_record deadline
sudo_reads_before="$(sudo_record reads)"
expect_poll "the deadline's read closes the lock" "inactive  current" sudo_core
expect "the deadline's read is the one read after the grant" "$((sudo_reads_before + 1))" sudo_record reads
expect "no deadline timer runs once the grant ended" false sudo_record deadline

# Controls: a duration outside the judge's starts no terminal, and a plugin
# that names no `sudo` holds none.
forget_record
expect "a duration outside the judge's is refused" 'refused: sudo=duration value="forever"' ipc smoke sudoGrant "$(bar_key)" vgs.sudo forever
expect "the refused duration started no terminal" absent recorded
expect "the bar, which names no sudo, holds no shell.sudo" absent ipc smoke sudoGrant "$(bar_key)" vgs.bar 15
expect "the bar's refusal started no terminal" absent recorded

# Hand the next row the state this row found.
expect "disabling the lock is allowed" ok ipc shell setPluginEnabled vgs.sudo false
expect_poll "no plugin holds sudo once the lock is disabled" '[]' sudo_holders
sentinel_restore "$sudo_bin/sudo"
expect "the tree's sudo is the sentinel again" sentinel sentinel_of "$sudo_bin/sudo"
rm -f -- "$sudo_half" "$sudo_list" "$sudo_calls"
rm -f -- "$shim/notify-send"
[[ ! -e $sandbox/sudo-row.notify-send.saved ]] || mv -- "$sandbox/sudo-row.notify-send.saved" "$shim/notify-send"
if [[ $sudo_notifications_were == False ]]; then
  expect "disabling vgs.notifications after the lock's notices is allowed" ok ipc shell setPluginEnabled vgs.notifications false
fi
user_config_restore "$sudo_config"
expect "the row reached no authentication" "$sudo_auth_before" auth_count
