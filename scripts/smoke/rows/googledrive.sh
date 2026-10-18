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
# into the key list and connection, the download connection naming
# the account its token carries; the Settings page offers Set up hourly
# sync while no unit is installed and its press hands the terminal the
# setup TUI; the window maps with the record, holds Sync now off while a
# run holds its copy and while the download client ID is missing, and its
# Sync now asks systemd
# to start the one service, which the systemctl stand-in logs, and runs no
# rclone, and its Remove beside a pair hands the terminal the remove TUI
# for that pair; an invalid pair list publishes the reset step to Settings
# and the window, and the runner keeps the damaged file beside an empty
# list; a Drive-side add and change reach the mirror after one run; a
# local edit since the last download keeps both versions and reads
# `both-changed` in the published status, and the service asks for one
# notification for it, which the core delivers or drops by its own rule
# (rows/notify.sh), and has the runner record it as notified; a Drive
# deletion keeps the file and reads `removed-on-drive`; a run during
# another is `busy` and starts no copy;
# pause stops the next run's copy and survives a shell restart, read
# through the published status, whose headline still names the files to
# review; the bar widget stays hidden until a folder pair exists, then
# takes the headline as its tooltip title over the published labels and
# states, never a file name. Must-fail controls:
# runner copies with a dry-run copy, with every displaced file taken as
# the runner's own and with the pair lock always granted each fail their
# check in a world of their own; a plugin copy whose service drops every
# read of the record leaves a pause the runner writes unpublished. The row
# ends with the pair removed, the units gone and the plugin disabled, as
# it found it, and its stand-ins removed. No latency reading.
# inputs: shell/plugins/vgs.google-drive/* shell/plugins/vgs.settings/* shell/plugins/vgs.notifications/* shell/Commons/PageReference.js shell/Ui/feedback/LinkText.qml shell/Commons/WatchedFile.qml shell/Core/PluginStatus.qml shell/Core/TuiRunner.qml bin/vgshell-tui
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
cs_pairs() { cs_state pairs action; }
# The connection: its text and the action it offers.
cs_account() { cs_values | py_reply 'import json,sys; v=json.load(sys.stdin); a=v.get("account"); print(json.dumps(None if a is None else [a["text"], a.get("action")]))'; }
cs_published_conflicts() { cs_values | py_reply 'import json,sys; c=json.load(sys.stdin).get("cloud", {}).get("conflicts", []); print(json.dumps(sorted([x["kind"], x["path"]] for x in c)))'; }
cs_keys() { cs_values | py_reply 'import json,sys; v=json.load(sys.stdin); print(json.dumps([[k["secret"], k["value"]] for k in v.get("keys", [])]))'; }
cs_lent() { ipc shell lent | py_reply 'import json,sys; d=json.load(sys.stdin); r=d["status"].get("vgs.google-drive"); print(json.dumps([sorted(r["keys"]) if r else None, "vgs.google-drive" in d["ipcTargets"]]))'; }
# The systemctl calls the stand-in logged for Google Drive: a reload and
# each call that names one of its units.
cs_systemctl() { if [[ -f $cs_stub/systemd/systemctl.calls ]]; then py_reply 'import json,sys; print(json.dumps([c for c in map(json.loads, sys.stdin) if "daemon-reload" in c or any(a.startswith("vgs-google-drive.") for a in c)]))' <"$cs_stub/systemd/systemctl.calls"; else echo '[]'; fi; }
cs_click_sync() { click_in "window:Google Drive" window vgs.google-drive Button "Sync now" && echo ok; }
# The window footer's primary action and whether it is enabled.
cs_window_primary() { ipc smoke readInstance window vgs.google-drive footer | py_reply 'import json,sys; p=json.load(sys.stdin)["primary"]; print(json.dumps([p["action"], p["enabled"]]))'; }
cs_click_remove() { click_in "window:Google Drive" window vgs.google-drive RowAction Remove && echo ok; }
cs_click_reset() { click_in "window:Google Drive" window vgs.google-drive Button "Start the folder pair list again" && echo ok; }
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
cs_link_text='A Google Drive key or connection is missing. Add the client ID and secret, then [select Connect on the Google Drive page](page:vgs.google-drive/Setup).'
cs_linked() { ipc smoke readMatchingDescendant window vgs.google-drive LinkText text "$cs_link_text" linked; }
cs_page() { ipc smoke readInstance window vgs.settings shownPage; }
cs_notice() {
  ipc smoke modelRows vgs.notifications rows app,summary,hintPage,leaving | py_reply 'import json,sys; print(json.dumps(next((r[2] for r in json.load(sys.stdin) if r[0] == "Google Drive" and r[1] == "Google Drive needs Connect" and r[3] == ""), "none")))'
}
cs_click_link() {
  local box spans pitch rect x y
  box="$(ipc smoke windowGeometry window vgs.google-drive LinkText "$cs_link_text")" || return 1
  spans="$(ipc smoke readMatchingDescendant window vgs.google-drive LinkText text "$cs_link_text" underlined)" || return 1
  pitch="$(ipc smoke readMatchingDescendant window vgs.google-drive LinkText text "$cs_link_text" linePitch)" || return 1
  rect="$(py_reply 'import json,sys; b=json.loads(sys.argv[1]); p=float(sys.argv[2]); s=json.load(sys.stdin)[0]; print(json.dumps([b[0]+s["left"], b[1]+s["line"]*p, s["right"]-s["left"], p]))' "$box" "$pitch" <<<"$spans")" || return 1
  read -r x y < <(at_centre "window:Google Drive" "$rect") || return 1
  hover "$x" "$y" || return 1
  expect_poll "the pointer reaches the Google Drive page link" true ipc smoke readMatchingDescendant window vgs.google-drive LinkText text "$cs_link_text" hoveredLink
  click "$x" "$y"
}

# The checks the controls replay against a broken runner: each runs in the
# world cs_use set and fails through expect.
check_copy() {
  expect "the pair is added" added=docs cs pair-add --definition "{\"id\":\"docs\",\"label\":\"Documents\",\"remote\":\"Docs\",\"local\":\"$cs_mirror\"}"
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
  expect "the prune pair is added" added=prune cs pair-add --definition "{\"id\":\"prune\",\"label\":\"Prune\",\"remote\":\"Prune\",\"local\":\"$prune_local\"}"
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
  expect "the shared pair is added" added=shared cs pair-add --definition "{\"id\":\"shared\",\"label\":\"Shared\",\"remote\":\"Shared\",\"local\":\"$cs_home/googledrive/shared\"}"
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
  expect_poll "the service holds its status record and IPC target" '[["account", "cloud", "connection", "firstPair", "keys", "pairs", "schedule", "sync"], true]' cs_lent
  expect_poll "with no pair and no unit the sync reads not set up" '["warning", "Not set up"]' cs_sync
  expect_poll "with no unit the hourly sync offers Set up" '["warning", "Not set up", true]' cs_schedule
  expect_poll "with no folder pair the pairs offer Add" '["warning", "None", "add"]' cs_pairs
  expect_poll "with no folder pair the widget is hidden" false cs_widget_shown
  expect_poll "with no key stored every key reads absent" '[["client-id", "absent"], ["client-secret", "absent"]]' cs_keys
  expect_poll "with no client stored no connection is offered" '["Not connected", null]' cs_account
  printf 'fixture-client' >"$cs_stub/secrets/client-id"
  printf 'fixture-secret' >"$cs_stub/secrets/client-secret"
  printf '{"access_token":"fixture","token_type":"Bearer","refresh_token":"fixture-refresh"}' >"$cs_stub/secrets/token"
  printf 'a.person@example.com' >"$cs_stub/secrets/token.user"
  expect "the service reads the keys again on request" ok ipc vgs.google-drive invoke refresh ""
  expect_poll "the stored keys read present" '[["client-id", "present"], ["client-secret", "present"]]' cs_keys
  expect_poll "the connection reads connected and offers Sign out" '["Connected", "signOut"]' cs_account
  expect_poll "the connection names the account its token carries" '"Connected as a.person@example.com."' cs_value account.hint

  # Set up hourly sync, D061: the Settings page offers the step while no
  # unit is installed, and its press opens the setup TUI. The stand-in
  # terminal runs no shipped script, so the row runs the install the
  # script runs.
  settings_page_open vgs.google-drive
  forget_record
  expect "Set up hourly sync is pressed" ok settings_act vgs.google-drive schedule
  expect_poll "Set up hands the terminal the setup TUI" "$(words vgs.google-drive/setup tui/setup.sh)" recorded_tail
  expect_run_end "the setup run ends" vgs.google-drive/setup
  settings_page_close vgs.google-drive
  expect "the install the setup TUI runs writes the units" "installed=vgs-google-drive.timer changed=2 exit=0" cs_answer install
  expect "install reloads the stand-in manager and enables the timer" '[["--user", "daemon-reload"], ["--user", "enable", "--now", "vgs-google-drive.timer"]]' cs_systemctl
  expect "the service reads the record again after the setup run" ok ipc vgs.google-drive invoke refresh ""
  expect_poll "with the units installed and no pair the sync reads no folder pairs" '["warning", "No folder pairs"]' cs_sync
  expect_poll "with the units installed the hourly sync reads on" '["ok", "On", null]' cs_schedule

  # A Drive-side add and change, a local edit and a Drive deletion, each
  # after one run, and the service's reading of each.
  check_copy
  check_local_add
  check_removed_locally
  check_export
  check_prune
  expect_poll "the service publishes the pair's state" '["Documents: 1 file to review"]' cs_value sync.lines
  expect_poll "the service publishes the pair and its Drive folder" '["Documents: Docs"]' cs_value pairs.lines
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

  # The widget names the pair and its state, never a file.
  expect "with a folder pair the widget shows" true cs_widget_shown
  expect_poll "the widget's tooltip leads with the files to review and names the pair" '["Google Drive: 3 files to review", ["Documents: 3 files to review"]]' cs_widget
  expect "the widget's tooltip names no file" False cs_widget_names_files

  # The window, and Sync now through the one service.
  expect "the window is summoned" ok ipc shell summon window vgs.google-drive '{}'
  expect_poll "the window maps, titled Google Drive" 1 window_count "Google Drive"
  expect_poll "the window offers Sync now with a folder pair" '["sync", true]' cs_window_primary
  # Sync now is off while a sync cannot start: a run holds its copy, then
  # the download client ID is missing.
  cs_hold "$cs_dir/window-held.out"
  expect_poll "the window holds Sync now off while a sync runs" '["sync", false]' cs_window_primary
  cs_let_go
  expect_poll "the window offers Sync now again once the sync ends" '["sync", true]' cs_window_primary
  mv -- "$shim/notify-send" "$cs_stub/notify-send.link-test"
  notes_on googledrive-links
  rm -- "${cs_stub:?}/secrets/client-id"
  expect "a run without the download client ID waits for it" "pair=docs result=authorization-required exit=1" cs_answer run
  expect_poll "the window holds Sync now off while a key is missing" '["sync", false]' cs_window_primary
  expect_poll "the missing-key window draws its page link" true cs_linked
  expect_poll "the needs-Connect notice holds its page link" '"[select Connect on the Google Drive page](page:vgs.google-drive/Setup)"' cs_notice
  cs_click_link || fail "googledrive: the window page link click failed"
  expect_poll "the window page link opens Google Drive Setup" '"vgs.google-drive/Setup"' cs_page
  settings_page_close vgs.google-drive
  click_item vgs:layer vgs.notifications NotificationCard summary "Google Drive needs Connect" 24 - || fail "googledrive: the notice page link click failed"
  expect_poll "the needs-Connect notice opens Google Drive Setup" '"vgs.google-drive/Setup"' cs_page
  settings_page_close vgs.google-drive
  notes_off googledrive-links

  # The same missing-key state with its page reference removed must fail
  # both link readers. The control preserves the drawn words.
  local link_copy="$home/.config/vgshell/plugins/vgs.google-drive"
  mkdir -p -- "$link_copy"
  cp -R -- "$repo/shell/plugins/vgs.google-drive/." "$link_copy/"
  expected_errors+=('plugins: hidden by a higher-precedence plugin with the same id: vgs\.google-drive')
  # An installed copy's former ids rename nothing (PluginLogic.formerIdClaims).
  expected_errors+=('plugins: former id claim ignored id=vgs\.google-drive reason=installed ')
  if edit_file_once "$link_copy/GoogleDriveLogic.js" '[select Connect on the Google Drive page](page:vgs.google-drive/Setup)' 'select Connect on the Google Drive page'; then
    expect "the window hides before the link control" ok ipc shell hide window vgs.google-drive
    notes_on googledrive-link-control
    rescan "the copy without the page reference is scanned"
    expect "the control window is summoned" ok ipc shell summon window vgs.google-drive '{}'
    expect_poll "the control window maps" 1 window_count "Google Drive"
    expect_poll "control: the window without a reference fails the link reader" absent cs_linked
    printf 'fixture-client' >"$cs_stub/secrets/client-id"
    expect "a good run clears the control attention" "pair=docs result=idle exit=0" cs_answer run
    expect_poll "the control service reads the cleared error" null cs_value cloud.lastError
    rm -- "${cs_stub:?}/secrets/client-id"
    expect "a missing-key run renews attention for the notice control" "pair=docs result=authorization-required exit=1" cs_answer run
    expect_poll "control: the notice without a reference fails the link reader" '""' cs_notice
    click_item vgs:layer vgs.notifications NotificationCard summary "Google Drive needs Connect" 24 - || fail "googledrive: the control notice click failed"
    expect_poll "control: the notice without a reference leaves" '"none"' cs_notice
    expect "control: the notice without a reference leaves Settings closed" absent cs_page
    notes_off googledrive-link-control
    expect "the control window hides" ok ipc shell hide window vgs.google-drive
  else
    fail "googledrive: the page-reference control edit failed"
  fi
  rm -r -- "$link_copy"
  mv -- "$cs_stub/notify-send.link-test" "$shim/notify-send"
  rescan "the shipped page reference is scanned again"
  expect "the shipped window is summoned again" ok ipc shell summon window vgs.google-drive '{}'
  printf 'fixture-client' >"$cs_stub/secrets/client-id"
  expect "a run with the client ID back copies again" "pair=docs result=idle exit=0" cs_answer run
  expect_poll "the window offers Sync now again with the key back" '["sync", true]' cs_window_primary
  local copies
  copies="$(cs_copies)"
  : >"$cs_stub/systemd/systemctl.calls"
  expect "Sync now is clicked" ok cs_click_sync
  expect_poll "Sync now asks systemd to start the one service" '[["--user", "start", "--no-block", "vgs-google-drive.service"]]' cs_systemctl
  expect "Sync now runs no rclone of its own" "$copies" cs_copies
  forget_record
  expect "Remove beside the folder pair is clicked" ok cs_click_remove
  expect_poll "Remove hands the terminal the remove TUI for that pair" "$(words vgs.google-drive/remove-pair tui/remove-pair.sh docs)" recorded_tail
  expect_run_end "the remove run ends" vgs.google-drive/remove-pair
  expect "the window is hidden" ok ipc shell hide window vgs.google-drive
  expect_poll "the window is gone" 0 window_count "Google Drive"

  # Pause stops the next run's copy and survives a restart.
  cs_put d.txt "while paused"
  expect "Pause through the service" ok ipc vgs.google-drive invoke pause ""
  expect_poll "the service publishes the pause" true cs_value cloud.paused
  expect "a paused run copies nothing" "pair=docs result=paused exit=0" cs_answer run
  expect "the paused run left the add on Drive" absent cs_read d.txt
  stop_shell || fail "googledrive: the shell stops before the restart"
  start_shell "$repo" "$sandbox/qs-googledrive.log" || return 0
  expect_poll "after a restart the service publishes the pause" true cs_value cloud.paused
  expect_poll "after a restart the sync still names the files to review" '["warning", "3 files to review"]' cs_sync
  expect_poll "after a restart the pair reads paused" '["Documents: Paused"]' cs_value sync.lines
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
  expect_poll "the damaged pair list offers Reset in status" '["danger", "Not readable", "reset"]' cs_pairs
  expect "the window is summoned for the damaged pair list" ok ipc shell summon window vgs.google-drive '{}'
  expect_poll "the window reads the damaged pair list" false ipc smoke readInstance window vgs.google-drive pairsValid
  forget_record
  expect "the window reset step is clicked" ok cs_click_reset
  expect_poll "the window reset hands the terminal the reset TUI" "$(words vgs.google-drive/reset-pairs tui/reset-pairs.sh)" recorded_tail
  expect_run_end "the window reset run ends" vgs.google-drive/reset-pairs
  expect "the damaged-list window is hidden" ok ipc shell hide window vgs.google-drive
  settings_page_open vgs.google-drive
  forget_record
  expect "the Settings pair-list repair is pressed" ok settings_act vgs.google-drive pairs
  expect_poll "Settings hands the terminal the reset TUI" "$(words vgs.google-drive/reset-pairs tui/reset-pairs.sh)" recorded_tail
  expect_run_end "the Settings reset run ends" vgs.google-drive/reset-pairs
  settings_page_close vgs.google-drive
  expect "the runner resets the damaged pair list" "reset=kept exit=0" cs_reset_output
  expect "the damaged pair list is kept" '{"pairs": [' cs_kept_pairs_bytes
  expect "the new pair list is empty" '{"pairs": []}' cs_pairs_json
  expect "the service reads the empty pair list" ok ipc vgs.google-drive invoke refresh ""
  expect_poll "the empty pair list offers Add again" '["warning", "None", "add"]' cs_pairs
  cs_remove_kept_pairs
  rm -f -- "$home/.config/systemd/user/vgs-google-drive.service" "$home/.config/systemd/user/vgs-google-drive.timer"
  expect "the service reads the record again" ok ipc vgs.google-drive invoke refresh ""
  expect_poll "with no pair and no unit the sync reads not set up" '["warning", "Not set up"]' cs_sync
  expect_poll "with no unit the hourly sync offers Set up again" '["warning", "Not set up", true]' cs_schedule
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
