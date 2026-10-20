# Google Drive, vgs.google-drive. The harness starts it disabled; this row
# stands in every command it and its runner reach in the shell's own PATH
# directory, then enables it: automations_stand_ins' systemctl, which logs
# every verb, and its notify-send; a secret-tool that answers the plugin's
# accounts from files under the row's directory and every other call as the
# harness's sentinel does; and an rclone that logs its argv, swaps the
# drive remote for rclone's `local` backend rooted at a fixture Drive
# beside the run's home and runs the host's rclone. No call reaches the
# host's systemd user manager, keyring, Google Drive or network. The row
# runs the runner, bin/google-drive, as the systemd service runs it, with
# the sandbox's directories, and reads what the shell's service publishes.
#
# Rows: the service publishes its declared status, its record and IPC
# target go with a disable, and it reads the stand-in keyring's presence
# into the key list, the sign-in step, which offers Sign out once signed
# in, and the account, which names the address its token carries; with no folder pair nothing offers the hourly
# sync's setup, the first pair's add installs the units, and a pair whose
# units are gone offers Set up again, whose press hands the terminal the
# setup TUI; the Settings list holds one row per pair, whose Remove hands
# the terminal the remove TUI for that pair; with one file that needs the
# user and eight notes the bar counts 1, and a click on the bar icon opens
# the popover, no Google Drive window, whose Needs you lists that file and
# whose eight files that need no action fold into one line a click
# unfolds; a click on Dismiss under the first of them has the runner keep
# its key, takes the row out of the published list and the fold line's
# count, and the row stays out across a shell restart; its Sync now is held
# while a run holds its copy, and asks systemd to start the one service,
# which the systemctl stand-in logs, and runs no rclone; a click on the
# file's name, a link, hands the terminal the core editor on that file
# and closes the popover; a click outside
# it and Escape close it, and its gear opens the plugin's page; with the
# download client ID missing it hides its footer and its callout's fix
# opens the Setup tab; an invalid pair list publishes its repair to the
# Setup tab and the popover, whose fix hands the terminal the reset TUI,
# and one row that says so to the Settings list, and
# the runner keeps the damaged file beside an empty list, whose Add hands
# the terminal the add TUI; a Drive-side add and change reach the mirror after one run; a
# local edit since the last download keeps both versions and reads
# `both-changed` in the published status, and the service asks for one
# notification for it, which the core delivers or drops by its own rule
# (rows/notify.sh), and has the runner record it as notified; a Drive
# deletion keeps the file and reads `removed-on-drive`; a run during
# another is `busy` and starts no copy;
# pause stops the next run's copy and survives a shell restart, read
# through the published status, whose headline still names the file that
# needs the user; the bar widget stays hidden until a folder pair exists, then
# takes the headline as its tooltip title over the published labels and
# states, never a file name. Must-fail controls:
# runner copies with a dry-run copy, with every displaced file taken as
# the runner's own, with the pair lock always granted and with a dismiss
# that keeps no key each fail their check in a world of their own; a
# plugin copy whose service drops every read of the record leaves a pause
# the runner writes unpublished. The row ends with the pair removed, the
# units gone and the plugin disabled, as it found it, and its stand-ins
# removed. No latency reading.
# inputs: shell/plugins/vgs.google-drive/* shell/plugins/vgs.settings/* shell/plugins/vgs.notifications/* shell/Commons/PageReference.js shell/Ui/feedback/LinkText.qml shell/Ui/feedback/Callout.qml shell/Ui/layout/ListItem.qml shell/Ui/layout/Pane.qml shell/Hosts/SummonPopup.qml shell/Hosts/PluginSlot.qml shell/Commons/WatchedFile.qml shell/Core/PluginStatus.qml shell/Core/TuiRunner.qml bin/vgshell-tui
set -euo pipefail
cs_dir="$sandbox/googledrive"
cs_stub="$cs_dir/stub"
cs_runner="$repo/shell/plugins/vgs.google-drive/bin/google-drive"
cs_err="$cs_dir/runner.err"
mkdir -p -- "$cs_stub/secrets" "$cs_dir/controls"
: >"$cs_err"

# The world a runner call runs in: HOME, the runtime directory and the
# runner file. The fixture Drive is googledrive-drive beside HOME, which the
# rclone stand-in reads from the HOME the runner hands it.
cs_use() { # HOME RUNTIME RUNNER
  cs_home="$1" cs_rt="$2" cs_file="$3"
  cs_drive="$(dirname -- "$1")/googledrive-drive/Docs"
  cs_second="$(dirname -- "$1")/googledrive-second/Shared"
  cs_mirror="$1/googledrive/docs"
  cs_state="$1/.local/state/vgshell/google-drive"
  mkdir -p -- "$cs_drive"
}
cs() {
  env -i HOME="$cs_home" PATH="$shell_start_path" LANG=C.UTF-8 XDG_RUNTIME_DIR="$cs_rt" XDG_CONFIG_HOME="$cs_home/.config" \
    XDG_STATE_HOME="$cs_home/.local/state" XDG_DATA_HOME="$cs_home/.local/share" node "$cs_file" "$@" 2>>"$cs_err"
}
# The runner's answer to ARGS and its exit status on one line.
cs_answer() { local out status=0; out="$(cs "$@")" || status=$?; printf '%s exit=%s\n' "${out//$'\n'/ }" "$status"; }
# The runner's `added=` line for ARGS, a pair add: an add on a home with
# no hourly units also prints the install's line, which a check that adds
# a pair in a world of its own does not judge.
cs_added() { cs "$@" | grep '^added='; }
cs_put() { mkdir -p -- "$(dirname -- "$cs_drive/$1")" && printf '%s' "$2" >"$cs_drive/$1"; }
cs_read() { if [[ -f $cs_mirror/$1 ]]; then cat -- "$cs_mirror/$1"; else echo absent; fi; }
# The runner's record, read afresh: KEY's [kind, path] pairs of conflicts.
cs_conflicts() { cs status | py_reply 'import json,sys; print(json.dumps(sorted([c["kind"], c["path"]] for c in json.load(sys.stdin)["conflicts"])))'; }
cs_kept() { cs status | py_reply 'import json,sys; c=[c for c in json.load(sys.stdin)["conflicts"] if c["kind"] == "both-changed"]; print(open(c[0]["storedPath"]).read() if c else "none")'; }
cs_copies() { if [[ -f $cs_stub/rclone.calls ]]; then grep -c '"copy"' -- "$cs_stub/rclone.calls" || true; else echo 0; fi; }
cs_blocked() { if [[ -e $cs_stub/blocked ]]; then echo yes; else echo no; fi; }
cs_second_shared() { if [[ -e $cs_second/local.txt ]]; then echo yes; else echo no; fi; }
cs_path_state() { if [[ -e $1 ]]; then echo "$2"; else echo "$3"; fi; }
# The values the shell's service publishes, and one of them.
cs_values() { ipc vgs.google-drive invoke status ""; }
cs_value() { cs_values | py_reply 'import json,sys; v=json.load(sys.stdin)
for part in sys.argv[1].split("."):
    if not isinstance(v, dict) or part not in v:
        print("unset"); sys.exit()
    v = v[part]
print(json.dumps(v))' "$1"; }
cs_last_sync() { cs_value lastSync | py_reply 'import sys; t=sys.stdin.read().strip(); print("set" if t.isdigit() else t)'; }
# The state value KEY's tone and text, and with `action` the action it
# offers.
cs_state() { cs_values | py_reply 'import json,sys; v=json.load(sys.stdin).get(sys.argv[1]); print(json.dumps(v if v is None else [v["tone"], v["text"]] + ([v.get("action")] if sys.argv[2] == "action" else [])))' "$1" "${2:-}"; }
cs_sync() { cs_state sync; }
cs_schedule() { cs_state schedule action; }
cs_sign_in() { cs_state connection action; }
# The Settings list of pairs: each row's id, its state's tone and the row
# actions it offers; and each row's second line.
cs_pairs() { cs_values | py_reply 'import json,sys; v=json.load(sys.stdin).get("pairs"); print(json.dumps(None if v is None else [[r["id"], r["state"]["tone"], r.get("actions", [])] for r in v]))'; }
cs_pair_lines() { cs_values | py_reply 'import json,sys; v=json.load(sys.stdin).get("pairs"); print(json.dumps(None if v is None else [r.get("secondary") for r in v], ensure_ascii=False))'; }
# The Setup repair of the pair list: its tone, text and action.
cs_pair_list() { cs_state pairList action; }
# The account: its text and the action it offers.
cs_account() { cs_values | py_reply 'import json,sys; v=json.load(sys.stdin); a=v.get("account"); print(json.dumps(None if a is None else [a["text"], a.get("action")]))'; }
# A row action of the Settings list: the manager's answer to ROW's
# ROW_ACTION of entry KEY, as the row's button hands it to the window.
settings_row_act() { ipc smoke invokeInstanceArgs window vgs.settings act "{\"args\":[\"$1\",\"$2\",\"$3\",\"$4\"]}"; }
# The dismissed keys the runner's record holds; whether the published
# list holds the row of KEY, `listed` or `absent`; the key of the first
# row the popover folds, the one whose Dismiss is drawn first.
cs_record_dismissed() { cs status | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["dismissed"]))'; }
cs_published_has() { cs_values | py_reply 'import json,sys; c=json.load(sys.stdin).get("cloud", {}).get("conflicts", []); print("listed" if any(x["key"] == sys.argv[1] for x in c) else "absent")' "$1"; }
cs_first_folded_key() { ipc smoke readInstance panel vgs.google-drive review | py_reply 'import json,sys; r=json.load(sys.stdin)["notes"]; print(r[0]["action"]["key"] if r and r[0]["action"] and r[0]["action"]["kind"] == "dismiss" else "none")'; }
cs_folded_count() { ipc smoke readInstance panel vgs.google-drive review | py_reply 'import json,sys; print(len(json.load(sys.stdin)["notes"]))'; }
cs_published_conflicts() { cs_values | py_reply 'import json,sys; c=json.load(sys.stdin).get("cloud", {}).get("conflicts", []); print(json.dumps(sorted([x["kind"], x["path"]] for x in c)))'; }
cs_keys() { cs_values | py_reply 'import json,sys; v=json.load(sys.stdin); print(json.dumps([[k["secret"], k["value"]] for k in v.get("keys", [])]))'; }
cs_lent() { ipc shell lent | py_reply 'import json,sys; d=json.load(sys.stdin); r=d["status"].get("vgs.google-drive"); print(json.dumps([sorted(r["keys"]) if r else None, "vgs.google-drive" in d["ipcTargets"]]))'; }
# The systemctl calls the stand-in logged for Google Drive: a reload and
# each call that names one of its units.
cs_systemctl() { if [[ -f $cs_stub/systemd/systemctl.calls ]]; then py_reply 'import json,sys; print(json.dumps([c for c in map(json.loads, sys.stdin) if "daemon-reload" in c or any(a.startswith("vgs-google-drive.") for a in c)]))' <"$cs_stub/systemd/systemctl.calls"; else echo '[]'; fi; }
# The popover: `shown` or `hidden`; its footer as [shown, whether Sync
# now can start]; its review as [the names Needs you lists, the count of
# notes]; whether its notes are unfolded; whether an item TYPE reading
# TEXT is drawn in it, `drawn` or `absent`. cs_badge: the count the bar
# icon draws.
cs_panel_shown() { [[ $(ipc smoke instanceGeometry panel vgs.google-drive) != absent ]] && echo shown || echo hidden; }
cs_panel_footer() { ipc smoke readInstance panel vgs.google-drive footer | py_reply 'import json,sys; f=json.load(sys.stdin); print(json.dumps([f["shown"], f["shown"] and f["sync"]["reason"] == ""]))'; }
cs_panel_review() { ipc smoke readInstance panel vgs.google-drive review | py_reply 'import json,sys; r=json.load(sys.stdin); print(json.dumps([[x["name"] for x in r["needs"]], len(r["notes"])]))'; }
cs_gone_files() { ipc smoke readInstance panel vgs.google-drive goneFiles; }
# cs_item_settled TYPE TEXT: `stable` once the popover's item holds its box
# across a moment, so a click after a scroll lands on it.
cs_item_settled() {
  local before after
  before="$(ipc smoke itemGeometry panel vgs.google-drive "$1" "$2")"
  sleep 0.4
  after="$(ipc smoke itemGeometry panel vgs.google-drive "$1" "$2")"
  [[ $before == \[* && $before == "$after" ]] && echo stable || echo moving
}
# The `gio` calls the stand-in recorded after the first N, as JSON.
cs_gio_since() { device_calls gio | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)[int(sys.argv[1]):]))' "$1"; }
cs_gio_count() { device_calls gio | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
cs_notes_open() { ipc smoke readInstance panel vgs.google-drive notesOpen; }
cs_panel_drawn() { [[ $(ipc smoke itemGeometry panel vgs.google-drive "$1" "$2") == \[* ]] && echo drawn || echo absent; }
cs_badge() { ipc smoke readInstance "$(bar_key)" vgs.google-drive view | py_reply 'import json,sys; print(json.load(sys.stdin)["badge"])'; }
# cs_open_popover LABEL: a click on the bar icon opens the popover, drawn.
cs_open_popover() {
  click_centre "$(bar_key)" vgs.google-drive || { fail "$1: the click on the bar icon failed"; return 1; }
  expect_poll "$1: a click on the bar icon opens the popover" shown cs_panel_shown
  summon_drawn panel vgs.google-drive || fail "$1: the popover never drew"
}
# cs_panel_click BOX: a click on the centre of BOX, [x, y, w, h] on the
# output, the pointer moved there a pixel off first, since a popup mapped
# while the pointer rests on the bar takes no click until the pointer
# moves. cs_panel_press TYPE TEXT: that click on the popover's item;
# cs_gear_press: on its Settings gear, which draws no text.
cs_panel_click() {
  local x y
  [[ $1 == \[* ]] || { echo "cs_panel_click: no box: $1" >&2; return 1; }
  read -r x y < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(int(x+w/2), int(y+h/2))' "$1") || return 1
  hover "$((x + 1))" "$y" || return 1
  click "$x" "$y" && echo ok
}
cs_panel_press() { cs_panel_click "$(ipc smoke itemGeometry panel vgs.google-drive "$1" "$2")"; }
cs_gear_press() { cs_panel_click "$(ipc smoke labelledGeometry panel vgs.google-drive IconButton Settings)"; }
# The page the Settings window shows, without its tab.
cs_page_plugin() { cs_page | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin).split("/")[0]))'; }
# cs_more_notes: six more files Drive removed and the run put back, which
# need nothing; the sixth is a PDF, whose link opens in its default
# application.
cs_notes=(n1.txt n2.txt n3.txt n4.txt n5.txt n6.pdf)
cs_more_notes() {
  local n
  for n in "${cs_notes[@]}"; do cs_put "$n" "note $n"; done
  expect "a run copies six more files" "pair=docs result=idle exit=0" cs_answer run
  for n in "${cs_notes[@]}"; do rm -- "${cs_drive:?}/$n"; done
  expect "a run puts the six files back on Drive" "pair=docs result=idle exit=0" cs_answer run
}
cs_reset_output() { cs_answer pairs-reset | py_reply 'import sys
s=sys.stdin.read().strip()
print("reset=kept exit=0" if s.startswith("reset=pairs.json.damaged-") and s.endswith(" exit=0") else s)'; }
cs_pairs_json() { python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))))' "$cs_home/.config/vgshell/google-drive/pairs.json"; }
cs_kept_pairs_bytes() { python3 -c 'import glob,sys
files=glob.glob(sys.argv[1] + "/pairs.json.damaged-*")
print(open(files[0]).read() if len(files) == 1 else "kept-count=%d" % len(files))' "$cs_home/.config/vgshell/google-drive"; }
cs_remove_kept_pairs() { rm -f -- "$cs_home"/.config/vgshell/google-drive/pairs.json.damaged-*; }
cs_dropped() { ipc smoke readInstance service vgs.google-drive smokeDropped; }
cs_dropped_after() { local now; now="$(cs_dropped)" || return; [[ $now =~ ^[0-9]+$ && $now -gt $1 ]] && echo read || echo "$now"; }
# The attention key the runner's record holds, and the one the service
# last asked a notification for.
cs_attention() { cs status | py_reply 'import json,sys; a=json.load(sys.stdin)["attention"]; print(a["key"] if a else "none")'; }
cs_notified() { ipc smoke readInstance service vgs.google-drive notifiedKey | py_reply 'import json,sys; print(json.load(sys.stdin) or "none")'; }
# Whether the runner's record holds its attention as notified.
cs_record_notified() { cs status | py_reply 'import json,sys; a=json.load(sys.stdin)["attention"]; print(json.dumps(a["notified"] if a else None))'; }
cs_widget_shown() { ipc smoke readInstance "$(bar_key)" vgs.google-drive visible; }
cs_widget() { ipc smoke readInstance "$(bar_key)" vgs.google-drive tip | py_reply 'import json,sys; t=json.load(sys.stdin); print(json.dumps([t["title"], t["details"].split("\n")[:1]]))'; }
cs_widget_names_files() { ipc smoke readInstance "$(bar_key)" vgs.google-drive tip | py_reply 'import json,sys; t=json.load(sys.stdin); print(any(n in t["title"] + t["details"] for n in sys.argv[1:]))' a.txt b.txt; }
cs_page() { ipc smoke readInstance window vgs.settings shownPage; }
cs_notice() {
  ipc smoke modelRows vgs.notifications rows app,summary,hintPage,leaving | py_reply 'import json,sys; print(json.dumps(next((r[2] for r in json.load(sys.stdin) if r[0] == "Google Drive" and r[1] == "Google Drive needs a sign-in" and r[3] == ""), "none")))'
}
# The checks the controls replay against a broken runner: each runs in the
# world cs_use set and fails through expect.
check_copy() {
  expect "the pair is added" added=docs cs_added pair-add --definition "{\"id\":\"docs\",\"label\":\"Documents\",\"remote\":\"Docs\",\"local\":\"$cs_mirror\"}"
  cs_put a.txt "one"
  expect "a run copies the Drive folder" "pair=docs result=idle exit=0" cs_answer run
  expect "the Drive-side add reaches the mirror" one cs_read a.txt
  cs_put a.txt "one, changed on Drive"
  cs_put b.txt "added on Drive"
  expect "the next run copies the change and the add" "pair=docs result=idle exit=0" cs_answer run
  expect "the Drive-side change reaches the mirror after one run" "one, changed on Drive" cs_read a.txt
  expect "the second Drive-side add reaches the mirror" "added on Drive" cs_read b.txt
}
check_local_add() {
  printf '%s' "local add" >"$cs_mirror/local.txt"
  expect "a run after a local add finishes" "pair=docs result=idle exit=0" cs_answer run
  expect "the local add reaches Drive" "local add" cat -- "$cs_drive/local.txt"
}
check_local_edit() {
  local want='[["both-changed", "a.txt"]]'
  if [[ -n ${cs_local_edit_records:-} ]]; then want="$cs_local_edit_records"; fi
  printf '%s' "edited here, a longer local version" >"$cs_mirror/a.txt"
  touch -d '2000-01-01T00:00:00Z' -- "$cs_mirror/a.txt"
  expect "a run after a local edit finishes" "pair=docs result=idle exit=0" cs_answer run
  expect "the mirror holds the Drive version" "one, changed on Drive" cs_read a.txt
  expect "the local edit is kept" "edited here, a longer local version" cs_kept
  expect "the record reads both-changed" "$want" cs_conflicts
}
check_removed() {
  local want='[["removed-on-drive", "b.txt"]]'
  if [[ -n ${cs_removed_records:-} ]]; then want="$cs_removed_records"; fi
  rm -- "$cs_drive/b.txt"
  expect "a run after a Drive deletion finishes" "pair=docs result=idle exit=0" cs_answer run
  expect "the file Drive removed stays" "added on Drive" cs_read b.txt
  expect "the file Drive removed returns to Drive" "added on Drive" cat -- "$cs_drive/b.txt"
  expect "the record reads removed-on-drive" "$want" cs_conflicts
}
check_dismiss() {
  local key
  key="$(cs status | py_reply 'import json,sys; print(next((c["key"] for c in json.load(sys.stdin)["conflicts"] if c["path"] == "b.txt"), "none"))')" || key=none
  expect "the runner dismisses the Drive deletion's row" "dismissed=$key" cs dismiss "$key"
  expect "the runner keeps the dismissal across a render" "[\"$key\"]" cs_record_dismissed
}
check_removed_locally() {
  cs_put local-gone.txt "drive copy"
  expect "a first run copies the file" "pair=docs result=idle exit=0" cs_answer run
  rm -- "$cs_mirror/local-gone.txt"
  expect "a run after a local deletion finishes" "pair=docs result=idle exit=0" cs_answer run
  expect "the local deletion deletes nothing on Drive" "drive copy" cat -- "$cs_drive/local-gone.txt"
  expect "the local deletion returns from Drive" "drive copy" cs_read local-gone.txt
  expect "the record reads removed-locally" '[["removed-locally", "local-gone.txt"]]' cs_conflicts
}
check_export() {
  cs_put native.docx "exported"
  printf '%s\n' native.docx >"$cs_stub/exports"
  expect "a first run downloads the export" "pair=docs result=idle exit=0" cs_answer run
  printf '%s' "local export edit" >"$cs_mirror/native.docx"
  expect "a run with a local export edit finishes" "pair=docs result=idle exit=0" cs_answer run
  expect "the export did not upload" "exported" cat -- "$cs_drive/native.docx"
}
check_prune() {
  local prune_drive prune_local old young
  prune_drive="$(dirname -- "$cs_drive")/Prune"
  prune_local="$cs_home/googledrive/prune"
  mkdir -p -- "$prune_drive" "$prune_local"
  expect "the prune pair is added" added=prune cs_added pair-add --definition "{\"id\":\"prune\",\"label\":\"Prune\",\"remote\":\"Prune\",\"local\":\"$prune_local\"}"
  old="$cs_state/pairs/prune/conflicts/20000101T000000Z-1/old.txt"
  young="$cs_state/pairs/prune/conflicts/29990101T000000Z-1/young.txt"
  mkdir -p -- "$(dirname -- "$old")" "$(dirname -- "$young")"
  printf old >"$old"
  printf young >"$young"
  printf '%s' "one" >"$prune_drive/prune.txt"
  expect "a run prunes old conflict storage" "pair=prune result=idle exit=0" cs_answer run --pair prune
  expect "the old conflict store is pruned" old-pruned cs_path_state "$old" old-present old-pruned
  expect "the young conflict store is kept" young-kept cs_path_state "$young" young-kept young-gone
  expect "the prune pair is removed" removed=prune cs pair-remove prune
  rm -rf -- "$prune_local" "$prune_drive" "$cs_state/pairs/prune"
}
check_shared_folder() {
  mkdir -p -- "$(dirname -- "$cs_drive")/Shared" "$cs_home/googledrive/shared"
  printf '%s' "made outside Google Drive" >"$(dirname -- "$cs_drive")/Shared/original.txt"
  expect "the shared pair is added" added=shared cs_added pair-add --definition "{\"id\":\"shared\",\"label\":\"Shared\",\"remote\":\"Shared\",\"local\":\"$cs_home/googledrive/shared\"}"
  printf '%s' "local add" >"$cs_home/googledrive/shared/local.txt"
  expect "a run uploads into the existing shared Drive folder" "pair=shared result=idle exit=0" cs_answer run --pair shared
  expect "the local add reaches the shared Drive folder" "local add" cat -- "$(dirname -- "$cs_drive")/Shared/local.txt"
  expect "no second shared folder is created" no cs_second_shared
  expect "the shared pair is removed" removed=shared cs pair-remove shared
}
# cs_release: the held copy let go, through a write that waits at most
# 10 s for the stand-in to open the pipe, so a copy that never reached its
# wait fails the row instead of hanging it.
cs_release() { timeout 10 bash -c 'printf "go\n" >"$1"' _ "$cs_stub/release"; }
# cs_finished PID: `ended` once the held runner PID has exited, within
# 60 s; past that it is killed and reads `killed`.
cs_finished() {
  local n
  for n in $(seq 1 600); do
    kill -0 "$1" 2>/dev/null || { echo ended; return; }
    sleep 0.1
  done
  kill "$1" 2>/dev/null || true
  echo killed
}
# cs_hold OUT: a run started and held inside its copy, its output in OUT
# and its PID in cs_held.
cs_hold() {
  rm -f -- "${cs_stub:?}/blocked" "${cs_stub:?}/release"
  mkfifo -- "$cs_stub/release"
  : >"$cs_stub/block"
  # Started without the cs function, so $! is the runner itself (env
  # execs node), whose PID the row may signal.
  env -i HOME="$cs_home" PATH="$shell_start_path" LANG=C.UTF-8 XDG_RUNTIME_DIR="$cs_rt" XDG_CONFIG_HOME="$cs_home/.config" \
    XDG_STATE_HOME="$cs_home/.local/state" XDG_DATA_HOME="$cs_home/.local/share" node "$cs_file" run >"$1" 2>>"$cs_err" &
  cs_held=$!
  expect_poll "the held run holds its copy" yes cs_blocked
}
# cs_let_go: the held run released and ended.
cs_let_go() {
  local released=no
  rm -f -- "${cs_stub:?}/block"
  if [[ $(cs_blocked) == yes ]]; then
    if cs_release; then released=yes; else fail "the held copy took no release within 10 s"; fi
  fi
  expect "the held run ends" ended cs_finished "$cs_held"
  wait "$cs_held" || true
  # A runner killed past its deadline leaves its copy waiting on the pipe.
  [[ $released == yes || $(cs_blocked) == no ]] || cs_release || true
  rm -f -- "${cs_stub:?}/release" "${cs_stub:?}/blocked"
}
check_lock() {
  local held_out="$cs_dir/held.out" before
  cs_put c.txt "held"
  cs_hold "$held_out"
  before="$(cs_copies)"
  expect "a run during another is busy" "pair=docs result=busy exit=75" cs_answer run
  expect "the busy run starts no copy" "$before" cs_copies
  cs_let_go
  expect "the held run finishes" "pair=docs result=idle" cat -- "$held_out"
}
# control_red NAME CHECK...: the checks against a runner copy whose FROM
# reads TO, in a world of its own; `red` when they fail, as they must.
control_red() { # NAME FROM TO CHECK...
  local from="$2" to="$3" dir="$cs_dir/controls/$1" log edit_error
  shift 3
  mkdir -p -- "$dir/home" "$dir/run"
  log="$dir/checks.log"
  if ! edit_error="$(python3 - "$cs_runner" "$dir/google-drive" "$from" "$to" 2>&1 <<'PY'
import sys
source, target, old, new = sys.argv[1:]
text = open(source).read()
if text.count(old) != 1:
    sys.exit("occurs %d times" % text.count(old))
open(target, "w").write(text.replace(old, new))
PY
  )"; then
    printf 'edit-failed %s\n' "$edit_error"
    return
  fi
  cmp -s -- "$cs_runner" "$dir/google-drive" && { echo unchanged; return; }
  (
    failures=0 behaviour_failures=0
    cs_use "$dir/home" "$dir/run" "$dir/google-drive"
    for check; do "$check"; done
    rm -f -- "$cs_stub/block" "$cs_stub/release" "$cs_stub/blocked"
    if [[ $failures -gt 0 ]]; then echo red; else echo green; fi
  ) 2>&1 | tee "$log" | tail -n 1
}

googledrive_row() {
  local host_rclone shell_path
  host_rclone="$(command -v rclone)"
  automations_stand_ins "$cs_stub/systemd"
  terminal_stand_in
  cat >"$cs_stub/export-size.py" <<'PY'
import json
import sys

exports = set(open(sys.argv[1]).read().split())
with open(sys.argv[2]) as listing:
    items = json.load(listing)
for item in items:
    if item.get("Path") in exports:
        item["Size"] = -1
print(json.dumps(items))
PY
  cat >"$shim/rclone" <<SH
#!/usr/bin/env bash
python3 -c 'import json,os,sys; print(json.dumps({"argv": sys.argv[1:], "env": {k: v for k, v in os.environ.items() if k.startswith("RCLONE_")}}))' "\$@" >>"$cs_stub/rclone.calls"
scope="\${RCLONE_CONFIG_VGSDRIVE_SCOPE:-}"
if [[ \$scope != drive && \$3 == copy && \${6:-} == vgsdrive:Shared ]]; then
  second="\$(dirname -- "\$HOME")/googledrive-second/Shared"
  mkdir -p -- "\$second"
  cp -a -- "\$5/." "\$second/"
  exit 0
fi
export RCLONE_CONFIG_VGSDRIVE_TYPE=local
unset RCLONE_CONFIG_VGSDRIVE_CLIENT_ID RCLONE_CONFIG_VGSDRIVE_CLIENT_SECRET RCLONE_CONFIG_VGSDRIVE_TOKEN RCLONE_CONFIG_VGSDRIVE_SCOPE
cd "\$(dirname -- "\$HOME")/googledrive-drive" || exit 9
if [[ -f "$cs_stub/block" && ! -e "$cs_stub/blocked" && \$3 == copy ]]; then
  : >"$cs_stub/blocked"
  read -r _ <"$cs_stub/release"
fi
if [[ -f "$cs_stub/exports" && \$3 == lsjson && \$* == *vgsdrive:* ]]; then
  listing="$cs_stub/listing.\$\$"
  "$host_rclone" "\$@" >"\$listing" || { status=\$?; rm -f -- "\$listing"; exit "\$status"; }
  python3 "$cs_stub/export-size.py" "$cs_stub/exports" "\$listing"
  status=\$?
  rm -f -- "\$listing"
  exit "\$status"
fi
exec "$host_rclone" "\$@"
SH
  chmod 755 "$shim/rclone"
  sentinel_stand_over "$shim/secret-tool" <<SH
#!/usr/bin/env bash
if [[ \${1:-} == search && \${2:-} == service && \${3:-} == vgs-google-drive && \${4:-} == account && \$# -eq 5 ]]; then
  if [[ -f "$cs_stub/secrets/\$5" ]]; then
    printf '[/1]\\nlabel = VGS Google Drive %s\\nsecret = %s\\n' "\$5" "\$(<"$cs_stub/secrets/\$5")"
    printf 'attribute.service = vgs-google-drive\\nattribute.account = %s\\n' "\$5" >&2
    if [[ -f "$cs_stub/secrets/\$5.user" ]]; then printf 'attribute.user = %s\\n' "\$(<"$cs_stub/secrets/\$5.user")" >&2; fi
  fi
  exit 0
fi
case "\${1:-}" in
  search) exit 0 ;;
  lookup) exit 1 ;;
esac
printf '%s\\n' "secret-tool \$*" >>"$auth_log"
exit 1
SH
  expect "the rclone command resolves to the row's stand-in on the shell's PATH" "$shim/rclone" shell_resolves rclone
  cs_use "$home" "$rt_dir" "$cs_runner"

  # The service, built over the stand-ins.
  expect "Google Drive starts disabled" '[null, false]' cs_lent
  expect "enabling Google Drive is allowed" ok ipc shell setPluginEnabled vgs.google-drive true
  expect "placing Google Drive's widget is allowed" ok ipc shell setPluginPlaced vgs.google-drive true
  expect_poll "the service holds its status record and IPC target" '[["account", "cloud", "cloudKeys", "connection", "firstPair", "keys", "pairList", "pairs", "schedule", "sync"], true]' cs_lent
  expect_poll "with no pair and no unit the sync reads no folder pairs" '["warning", "No folder pairs"]' cs_sync
  expect_poll "with no pair and no unit the hourly sync asks for no setup" '["info", "Off", null]' cs_schedule
  expect_poll "with no folder pair the Settings list holds no row" '[]' cs_pairs
  expect_poll "a pair list that reads is done and offers no repair" '["ok", "Readable", null]' cs_pair_list
  expect_poll "with no folder pair the widget is hidden" false cs_widget_shown
  expect_poll "with no key stored every key reads absent" '[["client-id", "absent"], ["client-secret", "absent"]]' cs_keys
  expect_poll "with no key stored the sign-in step waits for the keys" '["info", "Keys needed", null]' cs_sign_in
  expect_poll "with no key stored the account reads not signed in" '["Not signed in", null]' cs_account
  printf 'fixture-client' >"$cs_stub/secrets/client-id"
  printf 'fixture-secret' >"$cs_stub/secrets/client-secret"
  printf '{"access_token":"fixture","token_type":"Bearer","refresh_token":"fixture-refresh"}' >"$cs_stub/secrets/token"
  printf 'a.person@example.com' >"$cs_stub/secrets/token.user"
  expect "the service reads the keys again on request" ok ipc vgs.google-drive invoke refresh ""
  expect_poll "the stored keys read present" '[["client-id", "present"], ["client-secret", "present"]]' cs_keys
  expect_poll "with a sign-in stored the sign-in step is done and offers Sign out" '["ok", "Signed in", "signOut"]' cs_sign_in
  expect_poll "the account is the address its token carries, with no action" '["a.person@example.com", null]' cs_account

  # The hourly sync is no step (D061, VGS-1744): with no folder pair the
  # Settings page offers no setup for it, the first pair's add installs
  # it, and a pair whose units are gone offers Set up again, whose press
  # opens the setup TUI. The stand-in terminal runs no shipped script, so
  # the row runs the install the script runs.
  settings_page_open vgs.google-drive
  expect "with no pair Set up again is not offered" "refused: action=schedule reason=not-offered" settings_act vgs.google-drive schedule
  settings_page_close vgs.google-drive

  # A Drive-side add and change, a local edit and a Drive deletion, each
  # after one run, and the service's reading of each.
  check_copy
  expect "the first pair's add reloads the stand-in manager and enables the timer" '[["--user", "daemon-reload"], ["--user", "enable", "--now", "vgs-google-drive.timer"]]' cs_systemctl
  expect "the service reads the record again after the first pair" ok ipc vgs.google-drive invoke refresh ""
  expect_poll "with the first pair the hourly sync reads on" '["ok", "On", null]' cs_schedule
  rm -f -- "$home/.config/systemd/user/vgs-google-drive.service" "$home/.config/systemd/user/vgs-google-drive.timer"
  expect "the service reads the record again with the units gone" ok ipc vgs.google-drive invoke refresh ""
  expect_poll "with a pair and no unit the sync reads not set up" '["warning", "Not set up"]' cs_sync
  expect_poll "with a pair and no unit the hourly sync offers Set up again" '["warning", "Not on", true]' cs_schedule
  settings_page_open vgs.google-drive
  forget_record
  expect "Set up again is pressed" ok settings_act vgs.google-drive schedule
  expect_poll "Set up again hands the terminal the setup TUI" "$(words vgs.google-drive/setup tui/setup.sh)" recorded_tail
  expect_run_end "the setup run ends" vgs.google-drive/setup
  settings_page_close vgs.google-drive
  expect "the install the setup TUI runs writes the units" "installed=vgs-google-drive.timer changed=2 exit=0" cs_answer install
  expect "the service reads the record again after the setup run" ok ipc vgs.google-drive invoke refresh ""
  expect_poll "with the units installed again the hourly sync reads on" '["ok", "On", null]' cs_schedule
  check_local_add
  check_removed_locally
  check_export
  check_prune
  expect_poll "the service publishes the pair's state, which a note leaves up to date" '["Documents: Up to date"]' cs_value sync.lines
  expect_poll "the Settings list holds the pair with Remove" '[["docs", "ok", ["remove"]]]' cs_pairs
  expect_poll "the pair's row names its Drive folder and its folder here" '["Drive/Docs ⇄ ~/googledrive/docs"]' cs_pair_lines
  expect_poll "the service publishes the last sync" set cs_last_sync
  cs_local_edit_records='[["both-changed", "a.txt"], ["removed-locally", "local-gone.txt"]]' check_local_edit
  expect_poll "the service publishes the local edit" '[["both-changed", "a.txt"], ["removed-locally", "local-gone.txt"]]' cs_published_conflicts
  expected_errors+=('notify: unsent plugin=vgs\.google-drive')
  expect_poll "the service asks for one notification for the local edit" "$(cs_attention)" cs_notified
  expect_poll "the service has the runner record the local edit as notified" true cs_record_notified
  cs_removed_records='[["both-changed", "a.txt"], ["removed-locally", "local-gone.txt"], ["removed-on-drive", "b.txt"]]' check_removed
  check_shared_folder
  expect_poll "the service publishes the Drive deletion" '[["both-changed", "a.txt"], ["removed-locally", "local-gone.txt"], ["removed-on-drive", "b.txt"]]' cs_published_conflicts
  check_lock

  # The widget names the pair and its state, never a file, and counts
  # only the file that needs the user.
  expect "with a folder pair the widget shows" true cs_widget_shown
  expect_poll "the widget's tooltip leads with the file that needs the user and names the pair" '["Google Drive: 1 file needs you", ["Documents: 1 file needs you"]]' cs_widget
  expect "the widget's tooltip names no file" False cs_widget_names_files

  # One file that needs the user and eight notes: the bar counts 1, and
  # the popover a click on the bar icon opens lists the file under Needs
  # you and folds the notes into one line a click unfolds.
  cs_more_notes
  expect "the service reads the six notes" ok ipc vgs.google-drive invoke refresh ""
  expect_poll "the bar counts only the file that needs the user" 1 cs_badge
  cs_open_popover "the popover"
  expect "no Google Drive window exists" 0 window_count "Google Drive"
  expect_poll "Needs you lists the file that needs the user, and eight notes fold" '[["a.txt"], 8]' cs_panel_review
  expect_poll "Needs you draws the file's name as a link" drawn cs_panel_drawn LinkText a.txt
  expect "a folded note is not drawn" absent cs_panel_drawn LinkText n1.txt
  expect "the popover offers Sync now with a folder pair" '[true, true]' cs_panel_footer
  expect "the notes line is clicked" ok cs_panel_press ListItem "8 files need no action · nothing was lost"
  expect_poll "the notes line unfolds the notes" true cs_notes_open
  expect_poll "an unfolded note draws its name as a link" drawn cs_panel_drawn LinkText n1.txt

  # Sync now is held while a run holds its copy, then asks systemd to
  # start the one service.
  cs_hold "$cs_dir/panel-held.out"
  expect_poll "the popover holds Sync now while a sync runs" '[true, false]' cs_panel_footer
  cs_let_go
  expect_poll "the popover offers Sync now again once the sync ends" '[true, true]' cs_panel_footer
  local copies
  copies="$(cs_copies)"
  : >"$cs_stub/systemd/systemctl.calls"
  expect "Sync now is clicked" ok cs_panel_press Button "Sync now"
  expect_poll "Sync now asks systemd to start the one service" '[["--user", "start", "--no-block", "vgs-google-drive.service"]]' cs_systemctl
  expect "Sync now runs no rclone of its own" "$copies" cs_copies

  # A click on the name of the file that needs the user opens that file,
  # which is on this computer, in the core editor through the core's one
  # file route, and closes the popover. The record is cleared first, so a
  # click that opens nothing reads `absent`.
  forget_record
  expect "the file's name is clicked" ok cs_panel_press LinkText a.txt
  expect_poll "the name hands the terminal the core editor on the file" "$(words core/edit "$core_vgshell" edit "$cs_mirror/a.txt")" recorded_tail
  expect_poll "the name closes the popover" hidden cs_panel_shown
  expect_run_end "the file's editor run ends" core/edit

  # The route reads the file before it opens it. A note whose file is gone
  # from this computer keeps its row, which says so, and starts nothing;
  # a PDF note opens in its default application, through `gio open`, and
  # starts no editor, and closes the popover as the editor's file does.
  cs_open_popover "the popover for a gone file"
  expect "the notes line is clicked for the gone file" ok cs_panel_press ListItem "8 files need no action · nothing was lost"
  expect_poll "the notes line unfolds for the gone file" true cs_notes_open
  # The last notes sit below the popover's fold, so the body scrolls to
  # them before a click lands on one.
  ipc smoke scrollTo panel vgs.google-drive 99999 >/dev/null || fail "googledrive: the popover did not scroll to its last notes"
  expect_poll "the last note draws its name as a link" drawn cs_panel_drawn LinkText n6.pdf
  expect_poll "the scroll to the last notes settles" stable cs_item_settled LinkText n5.txt
  forget_record
  gio_before="$(cs_gio_count)"
  mv -- "$cs_mirror/n5.txt" "$cs_mirror/n5.txt.away"
  expect "the name of the gone file is clicked" ok cs_panel_press LinkText n5.txt
  expect_poll "the row of the gone file says so" "[\"$cs_mirror/n5.txt\"]" cs_gone_files
  expect "the gone file keeps its row" drawn cs_panel_drawn LinkText n5.txt
  expect "the gone file keeps the popover open" shown cs_panel_shown
  expect "the gone file starts no editor" absent recorded_tail
  expect "the gone file starts no default application" '[]' cs_gio_since "$gio_before"
  mv -- "$cs_mirror/n5.txt.away" "$cs_mirror/n5.txt"
  expect "the name of the PDF is clicked" ok cs_panel_press LinkText n6.pdf
  expect_poll "the PDF opens through gio open" "[[\"open\", \"$cs_mirror/n6.pdf\"]]" cs_gio_since "$gio_before"
  expect_poll "the PDF closes the popover" hidden cs_panel_shown
  expect "the PDF starts no editor" absent recorded_tail

  # A click outside the popover and Escape each close it; its gear opens
  # the plugin's page and closes it.
  cs_open_popover "the popover for a click outside"
  rest_pointer
  click 10 "$((mon_h - 10))" || fail "googledrive: the click outside the popover failed"
  expect_poll "a click outside closes the popover" hidden cs_panel_shown
  cs_open_popover "the popover for Escape"
  type_keys -k Escape || fail "googledrive: Escape to the popover failed"
  expect_poll "Escape closes the popover" hidden cs_panel_shown
  cs_open_popover "the popover for its gear"
  expect "the gear is clicked" ok cs_gear_press
  expect_poll "the gear opens Google Drive's page" '"vgs.google-drive"' cs_page_plugin
  expect_poll "the gear closes the popover" hidden cs_panel_shown
  settings_page_close vgs.google-drive

  # With the download client ID missing no sync can run: the popover hides
  # its footer, and its callout's fix opens the Setup tab, where the keys
  # are added.
  mv -- "$shim/notify-send" "$cs_stub/notify-send.link-test"
  notes_on googledrive-links
  rm -- "${cs_stub:?}/secrets/client-id"
  expect "a run without the download client ID waits for it" "pair=docs result=authorization-required exit=1" cs_answer run
  expect "the service reads the missing key" ok ipc vgs.google-drive invoke refresh ""
  cs_open_popover "the popover without a key"
  expect_poll "the popover hides its footer while no sync can run" '[false, false]' cs_panel_footer
  expect_poll "the needs-sign-in notice holds its page link" '"[sign in on the Google Drive Setup tab](page:vgs.google-drive/Setup)"' cs_notice
  expect "the callout's fix is clicked" ok cs_panel_press RowAction "Add the keys"
  expect_poll "the callout's fix opens Google Drive Setup" '"vgs.google-drive/Setup"' cs_page
  expect_poll "the callout's fix closes the popover" hidden cs_panel_shown
  settings_page_close vgs.google-drive
  click_item vgs:layer vgs.notifications NotificationCard summary "Google Drive needs a sign-in" 24 - || fail "googledrive: the notice page link click failed"
  expect_poll "the needs-sign-in notice opens Google Drive Setup" '"vgs.google-drive/Setup"' cs_page
  settings_page_close vgs.google-drive
  notes_off googledrive-links

  # The same missing-key state with its page reference removed must fail
  # the notice's link reader. The control preserves the drawn words.
  local link_copy="$home/.config/vgshell/plugins/vgs.google-drive"
  mkdir -p -- "$link_copy"
  cp -R -- "$repo/shell/plugins/vgs.google-drive/." "$link_copy/"
  expected_errors+=('plugins: hidden by a higher-precedence plugin with the same id: vgs\.google-drive')
  # An installed copy's former ids rename nothing (PluginLogic.formerIdClaims).
  expected_errors+=('plugins: former id claim ignored id=vgs\.google-drive reason=installed ')
  if edit_file_once "$link_copy/GoogleDriveLogic.js" '[sign in on the Google Drive Setup tab](page:vgs.google-drive/Setup)' 'sign in on the Google Drive Setup tab'; then
    notes_on googledrive-link-control
    rescan "the copy without the page reference is scanned"
    printf 'fixture-client' >"$cs_stub/secrets/client-id"
    expect "a good run clears the control attention" "pair=docs result=idle exit=0" cs_answer run
    expect_poll "the control service reads the cleared error" null cs_value cloud.lastError
    rm -- "${cs_stub:?}/secrets/client-id"
    expect "a missing-key run renews attention for the notice control" "pair=docs result=authorization-required exit=1" cs_answer run
    expect_poll "control: the notice without a reference fails the link reader" '""' cs_notice
    click_item vgs:layer vgs.notifications NotificationCard summary "Google Drive needs a sign-in" 24 - || fail "googledrive: the control notice click failed"
    expect_poll "control: the notice without a reference leaves" '"none"' cs_notice
    expect "control: the notice without a reference leaves Settings closed" absent cs_page
    notes_off googledrive-link-control
  else
    fail "googledrive: the page-reference control edit failed"
  fi
  rm -r -- "$link_copy"
  mv -- "$cs_stub/notify-send.link-test" "$shim/notify-send"
  rescan "the shipped page reference is scanned again"
  printf 'fixture-client' >"$cs_stub/secrets/client-id"
  expect "a run with the client ID back copies again" "pair=docs result=idle exit=0" cs_answer run
  expect "the service reads the key back" ok ipc vgs.google-drive invoke refresh ""
  settings_page_open vgs.google-drive
  forget_record
  expect "Remove on the Settings row of the pair is pressed" ok settings_row_act vgs.google-drive pairs docs remove
  expect_poll "the Settings Remove hands the terminal the remove TUI for that pair" "$(words vgs.google-drive/remove-pair tui/remove-pair.sh docs)" recorded_tail
  expect_run_end "the Settings remove run ends" vgs.google-drive/remove-pair
  settings_page_close vgs.google-drive

  # Dismiss under the first file that needs no action has the runner keep
  # its key, and the row leaves the published list and the fold line; the
  # pause section's restart below reads it still out.
  local dismissed_key folded
  cs_open_popover "the popover for Dismiss"
  expect "the fold line is clicked for Dismiss" ok cs_panel_press ListItem "8 files need no action · nothing was lost"
  expect_poll "the fold line unfolds for Dismiss" true cs_notes_open
  expect_poll "the first Dismiss holds its box" stable cs_item_settled RowAction Dismiss
  dismissed_key="$(cs_first_folded_key)" || dismissed_key=none
  folded="$(cs_folded_count)" || folded=0
  expect "the first folded row is listed before Dismiss" listed cs_published_has "$dismissed_key"
  expect "Dismiss is clicked" ok cs_panel_press RowAction Dismiss
  expect_poll "the runner keeps the dismissed key" "[\"$dismissed_key\"]" cs_record_dismissed
  expect_poll "the dismissed row leaves the published list" absent cs_published_has "$dismissed_key"
  expect_poll "the fold line counts one row fewer" "$((folded - 1))" cs_folded_count
  expect "the popover hides after Dismiss" ok ipc shell hide panel vgs.google-drive
  expect_poll "the popover is gone after Dismiss" hidden cs_panel_shown

  # Pause stops the next run's copy and survives a restart.
  cs_put d.txt "while paused"
  expect "Pause through the service" ok ipc vgs.google-drive invoke pause ""
  expect_poll "the service publishes the pause" true cs_value cloud.paused
  expect "a paused run copies nothing" "pair=docs result=paused exit=0" cs_answer run
  expect "the paused run left the add on Drive" absent cs_read d.txt
  stop_shell || fail "googledrive: the shell stops before the restart"
  start_shell "$repo" "$sandbox/qs-googledrive.log" || return 0
  expect_poll "after a restart the service publishes the pause" true cs_value cloud.paused
  expect_poll "after a restart the sync still names the file that needs the user" '["warning", "1 file needs you"]' cs_sync
  expect_poll "after a restart the pair reads paused" '["Documents: Paused"]' cs_value sync.lines
  expect_poll "after a restart the dismissed row stays out of the published list" absent cs_published_has "$dismissed_key"
  expect "after a restart the runner still keeps the dismissed key" "[\"$dismissed_key\"]" cs_record_dismissed
  expect "Resume through the service" ok ipc vgs.google-drive invoke resume ""
  expect_poll "the service publishes the resume" false cs_value cloud.paused
  expect "a resumed run copies the add" "pair=docs result=idle exit=0" cs_answer run
  expect "the add made while paused reaches the mirror" "while paused" cs_read d.txt

  # Controls: each runner rule broken in a copy, in a world of its own.
  expect "control: a dry-run download copy fails the copy check" red control_red copy '["copy", "--update", remotePath(pair), pair.local,' '["copy", "--dry-run", remotePath(pair), pair.local,' check_copy
  expect "control: a dry-run upload copy fails the local add check" red control_red upload-copy '["copy", "--update", pair.local, remotePath(pair)]' '["copy", "--dry-run", pair.local, remotePath(pair)]' check_copy check_local_add
  expect "control: removed-locally record branch is needed" red control_red removed-locally 'addRecord(records, { kind: "removed-locally", path: rel });' '' check_copy check_removed_locally
  expect "control: removed-on-drive record branch is needed" red control_red removed-on-drive 'addRecord(records, { kind: to === null ? "removed-on-drive" : "renamed", path: rel, to: to });' '' check_copy check_removed
  expect "control: export exclude is needed" red control_red export-exclude 'if (excludes !== null) uploadArgs.push("--exclude-from", excludes);' '' check_copy check_export
  expect "control: old conflict storage must prune" red control_red prune 'const cutoff = Date.now() - KEEP_MS;' 'const cutoff = 0;' check_copy check_prune
  expect "control: every displaced file taken as the runner's own fails the both-changed check" red control_red both-changed "const unedited = base !== undefined" "const unedited = true || base !== undefined" check_copy check_local_edit
  expect "control: drive.file creates a second shared folder" red control_red full-drive-scope 'const DRIVE_SCOPE = "drive";' 'const DRIVE_SCOPE = "drive.file";' check_shared_folder
  expect "control: a lock always granted fails the lock check" red control_red lock "if (out.status === 0) return fd;" "if (out.status === 0 || true) return fd;" check_copy check_lock
  expect "control: a dismiss that keeps no key fails the dismiss check" red control_red dismiss 'if (control.dismissed.indexOf(key) === -1) writeJson(controlFile, Object.assign(control, { dismissed: control.dismissed.concat([key]) }));' '' check_copy check_removed check_dismiss

  # Control: a plugin copy whose service drops every read of the record
  # leaves a pause the runner writes unpublished.
  local copy="$home/.config/vgshell/plugins/vgs.google-drive" dropped
  mkdir -p -- "$copy"
  cp -R -- "$repo/shell/plugins/vgs.google-drive/." "$copy/"
  expected_errors+=('plugins: hidden by a higher-precedence plugin with the same id: vgs\.google-drive')
  # An installed copy's former ids rename nothing (PluginLogic.formerIdClaims).
  expected_errors+=('plugins: former id claim ignored id=vgs\.google-drive reason=installed ')
  if edit_file_once "$copy/Service.qml" "            onLoaded: content => root.accept(content)" "            onLoaded: content => root.smokeDropped += 1" &&
    edit_file_once "$copy/Service.qml" "    property bool registered: false" "    property bool registered: false
    property int smokeDropped: 0"; then
    rescan "the control copy is scanned"
    expect_poll "the control copy's service reads the record" read cs_dropped_after 0
    dropped="$(cs_dropped)" || fail "the control copy's read count is unreadable"
    expect "the runner pauses under the control" paused=all cs pause
    expect_poll "the control copy's service reads the paused record" read cs_dropped_after "$dropped"
    expect "the control copy leaves the pause unpublished" unset cs_value cloud.paused
    expect "the runner resumes under the control" resumed=all cs resume
  else
    fail "the plugin control's edit failed"
  fi
  rm -r -- "$copy"
  rescan "the shipped plugin is scanned again"
  expect_poll "the shipped service publishes the record again" false cs_value cloud.paused

  # The world as the row found it.
  expect "the pair is removed" removed=docs cs pair-remove docs
  printf '{"pairs": [' >"$cs_home/.config/vgshell/google-drive/pairs.json"
  expect "the service reads the damaged pair list" ok ipc vgs.google-drive invoke refresh ""
  expect_poll "the damaged pair list offers its repair on Setup" '["danger", "Not readable", true]' cs_pair_list
  expect_poll "the Settings list says the list cannot be read and offers no Remove" '[["unreadable", "danger", []]]' cs_pairs
  cs_open_popover "the popover for the damaged pair list"
  forget_record
  expect "the popover's repair is clicked" ok cs_panel_press RowAction "Start the list again"
  expect_poll "the popover's repair hands the terminal the reset TUI" "$(words vgs.google-drive/reset-pairs tui/reset-pairs.sh)" recorded_tail
  expect_run_end "the popover reset run ends" vgs.google-drive/reset-pairs
  expect_poll "the repair closes the popover" hidden cs_panel_shown
  settings_page_open vgs.google-drive
  forget_record
  expect "the Setup pair-list repair is pressed" ok settings_act vgs.google-drive pairList
  expect_poll "Settings hands the terminal the reset TUI" "$(words vgs.google-drive/reset-pairs tui/reset-pairs.sh)" recorded_tail
  expect_run_end "the Settings reset run ends" vgs.google-drive/reset-pairs
  settings_page_close vgs.google-drive
  expect "the runner resets the damaged pair list" "reset=kept exit=0" cs_reset_output
  expect "the damaged pair list is kept" '{"pairs": [' cs_kept_pairs_bytes
  expect "the new pair list is empty" '{"pairs": []}' cs_pairs_json
  expect "the service reads the empty pair list" ok ipc vgs.google-drive invoke refresh ""
  expect_poll "the empty pair list holds no row" '[]' cs_pairs
  expect_poll "the empty pair list is done and offers no repair" '["ok", "Readable", null]' cs_pair_list
  settings_page_open vgs.google-drive
  forget_record
  expect "Add under the empty list is pressed" ok settings_act vgs.google-drive pairs
  expect_poll "Add hands the terminal the add TUI" "$(words vgs.google-drive/add-pair tui/add-pair.sh)" recorded_tail
  expect_run_end "the add run ends" vgs.google-drive/add-pair
  settings_page_close vgs.google-drive
  cs_remove_kept_pairs
  rm -f -- "$home/.config/systemd/user/vgs-google-drive.service" "$home/.config/systemd/user/vgs-google-drive.timer"
  expect "the service reads the record again" ok ipc vgs.google-drive invoke refresh ""
  expect_poll "at the end, with no pair and no unit, the sync reads no folder pairs" '["warning", "No folder pairs"]' cs_sync
  expect_poll "at the end, with no pair and no unit, the hourly sync asks for no setup" '["info", "Off", null]' cs_schedule
  expect "unplacing Google Drive's widget is allowed" ok ipc shell setPluginPlaced vgs.google-drive false
  expect "disabling Google Drive is allowed" ok ipc shell setPluginEnabled vgs.google-drive false
  expect_poll "the disabled plugin holds no status record or IPC target" '[null, false]' cs_lent
  sentinel_restore "$shim/secret-tool"
  rm -f -- "$shim/rclone"
  automations_stand_ins_restore "$cs_stub/systemd"
}

# edit_file_once FILE OLD NEW: FILE with its one OLD replaced by NEW.
edit_file_once() {
  python3 - "$@" <<'PY'
import sys
path, old, new = sys.argv[1:]
text = open(path).read()
if text.count(old) != 1:
    sys.exit("%s: occurs %d times: %s" % (path, text.count(old), old))
open(path, "w").write(text.replace(old, new))
PY
}

if command -v rclone >/dev/null 2>&1; then
  googledrive_row
else
  not_measured googledrive missing=rclone
fi
