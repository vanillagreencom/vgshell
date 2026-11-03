# org.freedesktop.ScreenSaver inhibits (D116): the core's helper,
# bin/vgshell-idle-inhibit, answers the name on the sandbox's private
# session bus while a stage can fire, and a live inhibit pauses every idle
# watch. The stand-in callers, scripts/smoke/fixtures/idle-inhibit/client.py,
# run on that bus alone: their starter refuses any other address, the
# owner's bus among them, and an empty one, which its control reads with a
# stand-in spawn that starts nothing. The fixture acme.idlewatch holds one
# plain idle watch, read through the lending record. With the screensaver
# stage at 600 s, the row reads:
# - the helper, a child of the shell, owns the name, and GetActive answers
#   false;
# - with no inhibit live, the 1 s watch goes idle, so the compositor itself
#   holds no inhibitor that would hide a hold;
# - an Inhibit pauses the source and holds a 1 s watch past its time, and
#   another caller's UnInhibit of that cookie keeps it;
# - the caller's UnInhibit ends the pause and the watch goes idle;
# - a second Inhibit takes the idle watch back as input does, and that
#   caller killed with SIGKILL ends the pause;
# - an Inhibit while the screensaver runs, its 1 s activity watch idle,
#   stops it as input does, and a watch created during that pause stays
#   not idle past its time, then goes idle once the pause ends;
# - with every stage at Never, VGS holds no bus role and the name is
#   unowned;
# - with a stand-in owner started before a shell restart, the helper logs
#   the other owner once and the stand-in still owns the name.
# Controls, each a copy of the tree started in place of it with one edit:
# a helper that ignores NameOwnerChanged keeps the pause after its caller
# is killed; a helper whose UnInhibit keeps the cookie keeps the pause
# after UnInhibit; a helper that asks REPLACE_EXISTING displaces the
# stand-in, which allows replacement; a core whose monitors ignore the
# pause lets the watch go idle while inhibited. Each control runs the
# row's own check and passes only on that check's failure. The row restores the user file and the plugins'
# enablement, removes its fixture and its ttfx stand-in, and ends with a
# fresh shell of the tree.
# A held watch is read 3 s after it was created, three times its 1 s time,
# since no event marks a watch that stays active. Every other reading
# polls through expect_poll; no latency budget is claimed.
# inputs: bin/vgshell-idle-inhibit bin/lib/dbus_wire.py scripts/smoke/fixtures/idle-inhibit/* scripts/smoke/fixtures/plugins/acme.idlewatch/* scripts/smoke/fixtures/screensaver-ttfx shell/Core/IdleRegistry.qml shell/Core/Capabilities.qml shell/Core/PluginLogic.js shell/Core/ConfigLogic.js shell/Core/CoverPresentation.qml shell/Hosts/CoverHost.qml shell/plugins/vgs.screensaver/* shell/plugins/*/manifest.json
set -euo pipefail
ii_bus="unix:path=$rt_dir/bus"
ii_client="$repo/scripts/smoke/fixtures/idle-inhibit/client.py"
ii_config="$home/.config/vgshell/shell.json"
ii_saved="$sandbox/idle-inhibit-shell-before.json"
ii_fixture="$home/.config/vgshell/plugins/acme.idlewatch"
ii_held='[["screensaver"], "taken"]'
ii_free='[[], "taken"]'
ii_owned_line='idle: org[.]freedesktop[.]ScreenSaver is held by another owner; VGS does not answer it'
ii_saver_enabled="$(plugin_enabled vgs.screensaver)" || ii_saver_enabled=unreadable
case "$ii_saver_enabled" in
  True|False|absent) ;;
  *) fail "the screensaver's enabled state is unreadable: $ii_saver_enabled" ;;
esac
cp -- "$ii_config" "$ii_saved"
mkdir -p -- "$ii_fixture"
cp -R "$repo/scripts/smoke/fixtures/plugins/acme.idlewatch/." "$ii_fixture/"
cp -- "$repo/scripts/smoke/fixtures/screensaver-ttfx" "$shim/ttfx"
chmod 755 "$shim/ttfx"

# ii_refusal BUS: nothing for the sandbox's own session bus; for any other
# BUS, `refused: bus=<bus> reason=empty` or `reason=not-sandbox`, status 1.
ii_refusal() { # BUS
  if [[ -z $1 ]]; then echo "refused: bus= reason=empty"; return 1; fi
  if [[ $1 != "$ii_bus" ]]; then echo "refused: bus=$1 reason=not-sandbox"; return 1; fi
}
# ii_start BUS LOG VERB: a stand-in caller left running on BUS with no
# environment but PATH, HOME and that bus, its output in LOG and its pid in
# ii_pid; prints `started`. Any other BUS starts nothing.
ii_pid=""
ii_start() { # BUS LOG VERB
  ii_refusal "$1" || return 1
  spawn "$2" env -i PATH="$PATH" HOME="$home" DBUS_SESSION_BUS_ADDRESS="$1" python3 "$ii_client" "$repo/bin/lib" "$3"
  ii_pid="$spawn_pid"
  echo started
}
# ii_call BUS VERB [ARG]: one call of the stand-in caller on BUS, its
# output; any other BUS calls nothing.
ii_call() { # BUS VERB [ARG]
  ii_refusal "$1" || return 1
  env -i PATH="$PATH" HOME="$home" DBUS_SESSION_BUS_ADDRESS="$1" python3 "$ii_client" "$repo/bin/lib" "${@:2}"
}
# ii_refused BUS LOG: ii_start's answer for BUS, and whether it left LOG
# absent. Inside it a stand-in spawn only creates LOG, so a starter whose
# refusal broke reads `log=present` and connects nothing.
ii_refused() { local said; said="$(spawn() { : >"$1"; }; ii_start "$1" "$2" hold)" || true; if [[ -e $2 ]]; then echo "$said log=present"; else echo "$said log=absent"; fi; }
# ii_end PID SIGNAL: a stand-in caller ended by SIGNAL and reaped.
ii_end() { # PID SIGNAL
  kill "-$2" -- "$1" 2>/dev/null || true
  wait "$1" 2>/dev/null || true
}
# The pause's sources and the helper's bus hold, from the lending record.
ii_pause() { ipc shell lent | py_reply 'import json,sys; p=json.load(sys.stdin).get("idlePause"); print("absent" if p is None else json.dumps([p.get("sources"), p.get("bus")]))'; }
ii_start_pause="$(ii_pause)" || ii_start_pause=unreadable
# The fixture's plain watch, and the screensaver's 1 s activity watch:
# `true` or `false` while it is idle or not, `none` with no such watch.
ii_watch_of() { ipc shell lent | py_reply 'import json,sys; w=[x for x in json.load(sys.stdin)["idle"] if x["id"] == sys.argv[1] and x["stage"] == "" and x["timeout"] == 1]; print(json.dumps(w[0]["idle"]) if len(w) == 1 else "none")' "$1"; }
ii_watch() { ii_watch_of acme.idlewatch; }
ii_line() { # LOG WORD: `yes` once LOG holds a line starting WORD
  if grep -q -- "^$2" "$1" 2>/dev/null; then echo yes; else echo no; fi
}
ii_cookie() { sed -n 's/^cookie=//p' -- "$1"; }
# `helper` when the name's owner is a child of the shell running
# bin/vgshell-idle-inhibit, else the owner's pid or `none`.
ii_owner_relation() {
  local pid parent
  pid="$(ii_call "$ii_bus" owner)" || return 1
  [[ $pid =~ ^[0-9]+$ ]] || { echo "$pid"; return 0; }
  parent="$(awk '{ print $4 }' "/proc/$pid/stat" 2>/dev/null)" || parent=""
  if [[ $parent == "$shell_qs_pid" ]] && tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -q -F -- 'bin/vgshell-idle-inhibit'; then echo helper; else echo "$pid"; fi
}
ii_outputs() { hypr -j monitors | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
ii_saver_state() { ipc smoke statusValues vgs.screensaver | py_reply 'import json,sys; v=json.load(sys.stdin).get("state",{}); print(v.get("text","missing"))'; }
# ii_settings PATCH: merge {plugin id: {setting: value}} into the user file.
ii_settings() { # PATCH
  user_config_write python3 - "$ii_config" "$1" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
rows = doc.setdefault("plugins", [])
for plugin, patch in json.loads(sys.argv[2]).items():
    row = next((r for r in rows if r.get("id") == plugin), None)
    if row is None:
        row = {"id": plugin}
        rows.append(row)
    row.update(patch)
json.dump(doc, sys.stdout)
PY
}
# Every stage each shipped manifest declares, at Never: its `enabled`
# setting false where it has one, else its time 0.
ii_never() {
  python3 - "$repo/shell/plugins" <<'PY'
import json, pathlib, sys
patch = {}
for path in sorted(pathlib.Path(sys.argv[1]).glob("*/manifest.json")):
    manifest = json.loads(path.read_text())
    for entry in manifest.get("idleStages", {}).values():
        row = patch.setdefault(manifest["id"], {})
        if "enabled" in entry:
            row[entry["enabled"]] = False
        else:
            row[entry["seconds"]] = 0
print(json.dumps(patch))
PY
}
# ii_held_check LABEL: the fixture's 1 s watch, taken now, still reads not
# idle 3 s later.
ii_held_check() { # LABEL
  expect "the fixture takes a 1 s watch for: $1" ok ipc acme.idlewatch invoke watch 1
  sleep 3
  expect "$1" false ii_watch
}
ii_uninhibit_check() { expect_poll "UnInhibit ends the pause" "$ii_free" ii_pause; }
ii_release_check() { expect_poll "a caller killed with SIGKILL ends the pause" "$ii_free" ii_pause; }
ii_stand_in_check() { expect "the stand-in still owns the name" "$1" ii_call "$ii_bus" owner; }
# ii_must_fail LABEL CHECK CMD...: CMD, run in a subshell against a control
# copy, holds the row's own check labelled CHECK and must fail that check
# and nothing else; a failed precondition beside it fails the control.
ii_controls=0
ii_must_fail() { # LABEL CHECK CMD...
  local label="$1" check="$2" log others
  ii_controls=$((ii_controls + 1))
  log="$sandbox/idle-inhibit-control-$ii_controls.log"
  shift 2
  ( "$@" ) >"$log" 2>&1 || true
  others="$(grep -F -- '  FAIL  ' "$log" | grep -v -F -- "  FAIL  $check: " || true)"
  if [[ -n $others ]]; then
    fail "control: $label: another check failed: ${others//$'\n'/ | }"
  elif grep -q -F -- "  FAIL  $check: " "$log"; then
    ok "control: $label"
  else
    fail "control: $label: the row's check passed"
  fi
  control_output "$log"
}

expect "the caller starter refuses an empty bus and starts nothing" "refused: bus= reason=empty log=absent" ii_refused "" "$sandbox/idle-inhibit-refused-empty.log"
ii_owner_bus="unix:path=/run/user/$(id -u)/bus"
expect "the caller starter refuses the owner's bus and starts nothing" "refused: bus=$ii_owner_bus reason=not-sandbox log=absent" ii_refused "$ii_owner_bus" "$sandbox/idle-inhibit-refused-owner.log"

rescan "a rescan after adding the idle-watch fixture answers ok"
expect_poll "the idle-watch fixture is discovered" True plugin_known acme.idlewatch
expect "enabling the idle-watch fixture is allowed" ok ipc shell setPluginEnabled acme.idlewatch true
expect_poll "the idle-watch fixture is built" True record_exists acme.idlewatch
ii_settings '{"vgs.screensaver": {"idleEnabled": true, "idleSeconds": 600, "effect": "planted", "frameRate": 30}}'
expect "reloading the screensaver's stage at 600 s is allowed" ok ipc shell reloadConfig
expect "enabling the screensaver is allowed" ok ipc shell setPluginEnabled vgs.screensaver true
expect_poll "the screensaver service is built" True record_exists vgs.screensaver
expect_poll "with a stage that can fire, VGS takes org.freedesktop.ScreenSaver" "$ii_free" ii_pause
expect "the name's owner is the shell's helper" helper ii_owner_relation
expect "GetActive answers false" false ii_call "$ii_bus" active
expect "the fixture takes a 1 s watch with no inhibit live" ok ipc acme.idlewatch invoke watch 1
expect_poll "with no inhibit live the 1 s watch goes idle" true ii_watch

# An inhibit holds the watch; another caller cannot end it; its own
# UnInhibit does.
ii_start "$ii_bus" "$sandbox/idle-inhibit-hold.log" hold >/dev/null || fail "the holding caller did not start"
ii_holder="$ii_pid"
expect_poll "the inhibit is answered with a cookie" yes ii_line "$sandbox/idle-inhibit-hold.log" cookie=
expect_poll "a live inhibit pauses the idle source" "$ii_held" ii_pause
ii_held_check "an inhibit holds a 1 s watch past its time"
expect "another caller's UnInhibit of the cookie is answered" ok ii_call "$ii_bus" uninhibit "$(ii_cookie "$sandbox/idle-inhibit-hold.log")"
expect "another caller's UnInhibit keeps the pause" "$ii_held" ii_pause
kill -USR1 -- "$ii_holder" || fail "the holding caller could not be signalled"
expect_poll "the caller's UnInhibit is answered" yes ii_line "$sandbox/idle-inhibit-hold.log" released
ii_uninhibit_check
expect_poll "UnInhibit lets the watch go idle" true ii_watch
ii_end "$ii_holder" TERM

# A pause over an idle watch reads as input; a killed caller ends it.
ii_start "$ii_bus" "$sandbox/idle-inhibit-killed.log" hold >/dev/null || fail "the caller to kill did not start"
ii_killed="$ii_pid"
expect_poll "a second inhibit pauses the idle source" "$ii_held" ii_pause
expect_poll "the pause takes the idle watch back as input does" false ii_watch
ii_end "$ii_killed" KILL
ii_release_check
expect_poll "the watch counts again and goes idle" true ii_watch

# A pause that starts while the screensaver runs stops it; a watch
# created during the pause stays active until the pause ends.
expect "the screensaver starts on demand" ok ipc vgs.screensaver invoke start ''
expect_poll "the screensaver maps one cover per output" "$(ii_outputs)" layer_count vgs:cover
expect_poll "the screensaver's 1 s activity watch reads idle" true ii_watch_of vgs.screensaver
ii_start "$ii_bus" "$sandbox/idle-inhibit-saver.log" hold >/dev/null || fail "the caller over the screensaver did not start"
ii_saver_holder="$ii_pid"
expect_poll "an inhibit while the screensaver runs takes its covers down" 0 layer_count vgs:cover
expect_poll "the screensaver reads off after the pause" Off ii_saver_state
ii_held_check "a watch created during the pause stays not idle past its time"
kill -USR1 -- "$ii_saver_holder" || fail "the caller over the screensaver could not be signalled"
expect_poll "the pause over the screensaver ends" "$ii_free" ii_pause
expect_poll "the watch created during the pause goes idle once it ends" true ii_watch
ii_end "$ii_saver_holder" TERM

# With every stage at Never, no stage can fire and VGS holds no bus role.
ii_settings "$(ii_never)"
expect "reloading every stage at Never is allowed" ok ipc shell reloadConfig
expect_poll "with every stage at Never VGS stops its helper" '[[], "stopped"]' ii_pause
expect "with every stage at Never the name is unowned" none ii_call "$ii_bus" owner
ii_settings '{"vgs.screensaver": {"idleEnabled": true, "idleSeconds": 600}}'
expect "reloading the screensaver's stage again is allowed" ok ipc shell reloadConfig
expect_poll "a stage that can fire again takes the name again" "$ii_free" ii_pause

# A stand-in owner, which allows replacement, started before the shell:
# the helper leaves it in place and logs it once.
ii_owner_start() { # LOG
  ii_start "$ii_bus" "$1" own >/dev/null || fail "the stand-in owner did not start"
  ii_owner="$ii_pid"
  expect_poll "the stand-in owns the name" yes ii_line "$1" owner=primary
}
stop_shell || :
ii_owner_start "$sandbox/idle-inhibit-owner.log"
start_shell "$repo" "$sandbox/idle-inhibit-owned.log"
expect_poll "beside another owner the helper reads the name owned" '[[], "owned"]' ii_pause
expect_log "the helper logs the other owner" 1 "$ii_owned_line"
expect "the helper logs the other owner once" 1 log_lines "$ii_owned_line"
ii_stand_in_check "$ii_owner"
stop_shell || :
ii_end "$ii_owner" TERM

# Control: a helper that ignores NameOwnerChanged.
copy_tree idle-inhibit-orphan
if edit_tree idle-inhibit-orphan bin/vgshell-idle-inhibit '            if new == "" and name.startswith(":"):' '            if False:'; then
  start_shell "$sandbox/tree-idle-inhibit-orphan" "$sandbox/idle-inhibit-orphan.log"
  expect_poll "control: the orphan copy takes the name" "$ii_free" ii_pause
  ii_start "$ii_bus" "$sandbox/idle-inhibit-orphan-hold.log" hold >/dev/null || fail "control: the orphan copy's caller did not start"
  ii_orphan="$ii_pid"
  expect_poll "control: the orphan copy pauses on the inhibit" "$ii_held" ii_pause
  ii_end "$ii_orphan" KILL
  ii_must_fail "a helper that ignores NameOwnerChanged keeps the pause after its caller is killed" "a caller killed with SIGKILL ends the pause" ii_release_check
  stop_shell || :
fi

# Control: a helper whose UnInhibit keeps the cookie live.
copy_tree idle-inhibit-kept
if edit_tree idle-inhibit-kept bin/vgshell-idle-inhibit '            if self.cookies.get(cookie) == sender:' '            if False:'; then
  start_shell "$sandbox/tree-idle-inhibit-kept" "$sandbox/idle-inhibit-kept.log"
  expect_poll "control: the kept-cookie copy takes the name" "$ii_free" ii_pause
  ii_start "$ii_bus" "$sandbox/idle-inhibit-kept-hold.log" hold >/dev/null || fail "control: the kept-cookie copy's caller did not start"
  ii_kept="$ii_pid"
  expect_poll "control: the kept-cookie copy pauses on the inhibit" "$ii_held" ii_pause
  kill -USR1 -- "$ii_kept" || fail "control: the kept-cookie copy's caller could not be signalled"
  expect_poll "control: the kept-cookie copy answers the UnInhibit" yes ii_line "$sandbox/idle-inhibit-kept-hold.log" released
  ii_must_fail "a helper whose UnInhibit keeps the cookie keeps the pause" "UnInhibit ends the pause" ii_uninhibit_check
  ii_end "$ii_kept" TERM
  stop_shell || :
fi

# Control: a helper that asks REPLACE_EXISTING.
copy_tree idle-inhibit-replace
if edit_tree idle-inhibit-replace bin/vgshell-idle-inhibit 'wire.pack_body("su", [NAME, DO_NOT_QUEUE])' 'wire.pack_body("su", [NAME, DO_NOT_QUEUE | 2])'; then
  ii_owner_start "$sandbox/idle-inhibit-replace-owner.log"
  start_shell "$sandbox/tree-idle-inhibit-replace" "$sandbox/idle-inhibit-replace.log"
  expect_poll "control: the replacing copy takes the name" "$ii_free" ii_pause
  ii_must_fail "a helper that asks REPLACE_EXISTING displaces the stand-in" "the stand-in still owns the name" ii_stand_in_check "$ii_owner"
  stop_shell || :
  ii_end "$ii_owner" TERM
fi

# Control: a core whose monitors ignore the pause.
copy_tree idle-inhibit-unpaused
if edit_tree idle-inhibit-unpaused shell/Core/IdleRegistry.qml '            enabled: !root.paused' '            enabled: true'; then
  start_shell "$sandbox/tree-idle-inhibit-unpaused" "$sandbox/idle-inhibit-unpaused.log"
  expect_poll "control: the unpaused copy takes the name" "$ii_free" ii_pause
  ii_start "$ii_bus" "$sandbox/idle-inhibit-unpaused-hold.log" hold >/dev/null || fail "control: the unpaused copy's caller did not start"
  ii_unpaused="$ii_pid"
  expect_poll "control: the unpaused copy pauses on the inhibit" "$ii_held" ii_pause
  ii_must_fail "a core whose monitors ignore the pause lets the watch go idle while inhibited" "an inhibit holds a 1 s watch past its time" ii_held_check "an inhibit holds a 1 s watch past its time"
  ii_end "$ii_unpaused" TERM
  stop_shell || :
fi

start_shell "$repo" "$sandbox/idle-inhibit-restored.log"
user_config_restore "$ii_saved"
expect "reloading the user file the row found is allowed" ok ipc shell reloadConfig
expect "disabling the idle-watch fixture is allowed" ok ipc shell setPluginEnabled acme.idlewatch false
case "$ii_saver_enabled" in
  True) expect "the screensaver stays enabled as the row found it" ok ipc shell setPluginEnabled vgs.screensaver true ;;
  False|absent) expect "disabling the screensaver restores its state" ok ipc shell setPluginEnabled vgs.screensaver false ;;
esac
rm -rf -- "${ii_fixture:?}"
rm -f -- "${shim:?}/ttfx"
rescan "a rescan removes the idle-watch fixture"
expect_poll "acme.idlewatch is absent after the row" False plugin_known acme.idlewatch
expect_poll "the helper holds the name as the row found it" "$ii_start_pause" ii_pause
