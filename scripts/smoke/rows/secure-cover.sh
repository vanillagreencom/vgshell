# The secure cover: the screensaver stage owner's cover held inside the
# session lock (CoverPresentation, CoverHost, LockHost's barrier). The
# fixture acme.cover owns the screensaver stage, ahead of vgs.screensaver
# by id, and draws a planted magenta square and a frame its one renderer
# process prints for each line written to it; vgs.lock locks from its own
# lock stage watch. Each idle start comes from one key, so every watch
# counts from that key unless the row recreates one later.
#
# Per lock it reads the same cover instance (its identity stamp), the same
# renderer pid and its frame across the move into the lock, the square on
# the lock surface, no lock screen built under the cover, and the first
# move, key or click ending the cover with the lock content seeing none of
# it, while the next key reaches the lock's field and starts no PAM check
# (no Enter is typed). Equal Lock and Screensaver times start the cover
# from Lock's own idle event when the screensaver watch was recreated
# later, and move the running cover in when the lock watch was; a
# Screensaver edit leaves the lock watch's generation and deadline alone.
# A revoked idle ticket starts nothing. Manual and restore locks end the
# cover; display off, a renderer failure and a disable end it with the
# lock still held and leave no renderer. A cover that fails to build
# claims no presentation, so the lock screen shows at once. A second output gets its own
# cover in its own lock surface and takes it away again when it goes.
# Idle readings poll at expect_poll's 0.2 s; the lock deadline reading
# polls every 0.1 s. Measured on host cachy on 2026-10-31 under the nested
# sandbox: the row took 66 s in two runs, and the 4 s lock read 4026, 4136
# and 4138 ms in three, inside its 3.5..5 s window.
# inputs: scripts/smoke/fixtures/plugins/acme.cover/* scripts/smoke/fixtures/plugins/acme.probe/manifest.json shell/Core/CoverPresentation.qml shell/Core/IdleRegistry.qml shell/Core/SessionLock.qml shell/Core/Capabilities.qml shell/Core/PluginLogic.js shell/Hosts/CoverHost.qml shell/Hosts/CoverBarrier.qml shell/Hosts/LockHost.qml shell/Hosts/BackgroundHost.qml shell/Hosts/PluginSlot.qml shell/plugins/vgs.lock/* shell/plugins/vgs.screensaver/manifest.json shell/plugins/vgs.screensaver/Cover.qml shell/plugins/vgs.screensaver/Service.qml
set -euo pipefail
expected_errors+=('plugins: acme[.]cover failed to load: .*Cover[.]qml')
sc_config="$home/.config/vgshell/shell.json"
sc_probe="$(plugin_enabled acme.probe)" || sc_probe=unreadable
sc_lock_was="$(plugin_enabled vgs.lock)" || sc_lock_was=unreadable
sc_saver_was="$(plugin_enabled vgs.screensaver)" || sc_saver_was=unreadable
for sc_state in "$sc_probe" "$sc_lock_was" "$sc_saver_was"; do
  case "$sc_state" in True|False|absent) ;; *) fail "a plugin's enabled state is unreadable: $sc_state" ;; esac
done
# `lock` is exclusive and acme.probe holds it while enabled.
[[ $sc_probe != True ]] || expect "disabling the capability fixture, which holds lock, is allowed" ok ipc shell setPluginEnabled acme.probe false

sc_lent() { ipc shell lent | py_reply 'import json,sys; v=json.load(sys.stdin)
for k in sys.argv[1].split("."): v=v.get(k) if isinstance(v, dict) else None
print(json.dumps(v))' "$1"; }
# The presentation as [owner, placement, origin].
sc_cover() { ipc shell lent | py_reply 'import json,sys; c=json.load(sys.stdin)["cover"]; print(json.dumps([c["owner"], c["placement"], c["origin"]]))'; }
# The plugins whose cover sits in a lock surface, over every surface.
sc_held() { ipc shell lent | py_reply 'import json,sys; c=json.load(sys.stdin)["cover"]["secure"]; print(json.dumps(sorted(set(i for ids in c.values() for i in ids))))'; }
sc_held_surfaces() { ipc shell lent | py_reply 'import json,sys; c=json.load(sys.stdin)["cover"]["secure"]; print(sum(1 for ids in c.values() if "acme.cover" in ids))'; }
sc_session() { hypr -j monitors | py_reply 'import json,sys; print("locked" if any("LOCK" in (m.get("solitaryBlockedBy") or []) for m in json.load(sys.stdin)) else "unlocked")'; }
sc_outputs() { hypr -j monitors | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
sc_host="cover:$(hypr -j monitors | py_reply 'import json,sys; print(json.load(sys.stdin)[0]["name"])')"
sc_read() { ipc smoke readInstance "$sc_host" acme.cover "$1"; }
sc_fixture() { ipc acme.cover invoke "$1" ''; }
# The fixture's renderer processes under the shell, one per cover drawing.
sc_renderers() { local count; count="$(pgrep -c -P "$shell_qs_pid" -f 'echo frame-')" || [[ $count == 0 ]]; printf '%s\n' "$count"; }
sc_views() { ipc smoke lockScreens vgs.lock | py_reply 'import json,sys; v=json.load(sys.stdin); print(len(v) if isinstance(v, list) else v)'; }
sc_lock_status() { ipc vgs.lock invoke status '' | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps([d[k] for k in sys.argv[1:]]))' "$@"; }
sc_password() { ipc smoke readInstance service vgs.lock password; }
sc_saver_watch() { ipc shell lent | py_reply 'import json,sys; print(json.dumps([[x["id"], x["timeout"]] for x in json.load(sys.stdin)["idle"] if x["stage"] == "screensaver"]))'; }
sc_built() { [[ $(sc_read identity) == '"cover-'* ]] && echo true || echo false; }
sc_present_tail() { sc_fixture status | py_reply 'import json,sys; p=json.load(sys.stdin)["presents"]; print(json.dumps([len(p)] + p[-1:]))'; }
sc_lock_timeouts() { ipc shell lent | py_reply 'import json,sys; print(json.dumps([[x["id"], x["timeout"]] for x in json.load(sys.stdin)["idle"] if x["stage"] == "lock"]))'; }
sc_lock_watch() { ipc shell lent | py_reply 'import json,sys; w=[x for x in json.load(sys.stdin)["idle"] if x["stage"] == "lock"]; print(json.dumps([[x["id"], x["timeout"], x["generation"]] for x in w]))'; }
sc_set() { # PLUGIN JSON: patch that plugin's row of the user file
  python3 - "$sc_config" "$1" "$2" <<'PY'
import json, os, sys
path, plugin, patch = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
doc = json.load(open(path))
rows = doc.setdefault("plugins", [])
row = next((r for r in rows if r.get("id") == plugin), None)
if row is None:
    row = {"id": plugin}
    rows.append(row)
for key, value in patch.items():
    if value is None:
        row.pop(key, None)
    else:
        row[key] = value
with open(path + ".next", "w") as out:
    json.dump(doc, out)
os.replace(path + ".next", path)
PY
}
sc_times() { # SCREENSAVER LOCK: both stage times, written and reloaded
  sc_set acme.cover "{\"seconds\": $1}"
  sc_set vgs.lock "{\"idleLockSeconds\": $2}"
  expect "reload for screensaver $1 s and lock $2 s" ok ipc shell reloadConfig
}
sc_placement() { sc_lent cover.placement; }
# yes when the last presentation ended for one of the |-separated REASONS.
sc_ended_by() { local ended; ended="$(sc_lent cover.ended)" || return; [[ "|$1|" == *"|${ended//\"/}|"* ]] && echo yes || echo "$ended"; }
sc_release() { # LABEL
  expect "$1: the probe releases the lock" ok ipc smoke sessionUnlock
  expect_poll "$1: the session is unlocked" unlocked sc_session
  expect_poll "$1: no cover is presented" '"none"' sc_placement
  expect_poll "$1: no renderer is left" 0 sc_renderers
}
sc_idle_start() { type_keys -k Shift_L || fail "$1: the idle-start key failed"; sc_started_ms="$(now_ms)"; }

install_plugin_copy acme.cover acme.cover Cover
sc_set vgs.lock '{"lockBeforeSleep": false}'
sc_times 0 0
rescan "rescan after adding the cover fixture answers ok"
expect "enabling the cover fixture is allowed" ok ipc shell setPluginEnabled acme.cover true
expect "enabling vgs.screensaver beside it is allowed" ok ipc shell setPluginEnabled vgs.screensaver true
expect "enabling vgs.lock is allowed" ok ipc shell setPluginEnabled vgs.lock true
expect_poll "the cover fixture's service is built" True record_exists acme.cover
expect_poll "vgs.lock is built" True record_exists vgs.lock
# Enabling a plugin whose required commands the sandbox lacks, as
# vgs.screensaver without ttfx, raises its requirement notice, which takes
# the keyboard. Not now (Escape) closes it, so the row's keys reach the
# surfaces the row reads and the row leaves no notice behind.
sc_close_notices() { # LABEL
  printf 'secure-cover: notice label=%s shown=%s\n' "$1" "$(notice_shown)"
  for _ in 1 2 3 4; do
    [[ $(notice_shown) == null ]] && break
    type_keys -k Escape || fail "$1: closing the requirement notice failed"
    sleep 0.5
  done
  expect_poll "$1: no requirement notice stands" null notice_shown
}
sc_close_notices "after enabling"
# Hyprland reads idle inhibitors again on a window event. Run directly
# after rows/session.sh, whose inhibiting window has closed, this row saw no
# idle notification in two nested runs; one window mapped and closed here
# puts it on a fresh reading whichever row ran before it.
open_toplevel "$sandbox/secure-cover-window.log" smoke.secure-cover "Idle recheck" || fail "the recheck window maps"
close_toplevel "$toplevel_pid" "the recheck window exits"
expect_poll "the fixture owns the presentation, the first screensaver stage owner by id" '["acme.cover", "none", ""]' sc_cover
expect_poll "the fixture's cover is built on the first screen" true sc_built
expect "no renderer runs while no cover is presented" 0 sc_renderers

# Lock over a running cover, ended by the first move, key and click.
sc_transfer() { # FIRST(move|key|click)
  local first="$1" id pid frame starts
  sc_times 2 5
  expect_poll "$first: only the stage owner holds the screensaver stage watch" '[["acme.cover", 2]]' sc_saver_watch
  if [[ $first == click ]]; then hover 400 400 || fail "$first: resting the pointer failed"; else hover 20 20 || fail "$first: resting the pointer failed"; fi
  sc_idle_start "$first"
  expect_poll "$first: the stage watch starts the cover on the desktop" '["acme.cover", "desktop", "idle"]' sc_cover
  expect_poll "$first: one cover layer per output" "$(sc_outputs)" layer_count vgs:cover
  expect_poll "$first: one renderer per output" "$(sc_outputs)" sc_renderers
  expect "$first: the renderer advances" ok ipc smoke invokeInstance "$sc_host" acme.cover advance ''
  expect_poll "$first: the cover shows frame 2" '"frame-2"' sc_read frame
  id="$(sc_read identity)"; pid="$(sc_read rendererPid)"; frame="$(sc_read frame)"; starts="$(sc_read rendererStarts)"
  expect_poll "$first: the lock stage watch locks the session" locked sc_session
  expect_poll "$first: the cover moved into the lock" '["acme.cover", "secure", "idle"]' sc_cover
  expect "$first: the lock was an idle lock" '"idle"' sc_lent lock.cause
  expect "$first: the same cover instance" "$id" sc_read identity
  expect "$first: the same renderer" "$pid" sc_read rendererPid
  expect "$first: no renderer started for the move" "$starts" sc_read rendererStarts
  expect "$first: the frame held across the move" "$frame" sc_read frame
  expect_poll "$first: no cover layer maps under the lock" 0 layer_count vgs:cover
  expect "$first: only the stage owner's cover is in a lock surface" '["acme.cover"]' sc_held
  expect_poll "$first: the planted square shows on the lock surface" ff00ff pixel 130 130
  expect "$first: no lock screen is built under the cover" 0 sc_views
  expect "$first: the renderer advances under the lock" ok ipc smoke invokeInstance "$sc_host" acme.cover advance ''
  expect_poll "$first: the held cover shows frame 3" '"frame-3"' sc_read frame
  case "$first" in
    move) hover 240 240 || fail "$first: the first move failed" ;;
    key) type_keys x || fail "$first: the first key failed" ;;
    click) click 400 400 || fail "$first: the first click failed" ;;
  esac
  expect_poll "$first: the first $first ended the cover" '["acme.cover", "none", ""]' sc_cover
  expect "$first: it ended by input" '"input"' sc_lent cover.ended
  expect_poll "$first: its renderer is gone" 0 sc_renderers
  expect "$first: the session stays locked" locked sc_session
  expect "$first: the cover took none of the input under the lock" 0 sc_read inputs
  expect_poll "$first: the lock screen is built once the cover ends" "$(sc_outputs)" sc_views
  expect "$first: the first $first reached no field" '""' sc_password
  expect "$first: a revoked idle ticket starts nothing" 'refused: cover=idle-ticket-stale' sc_fixture present-last-ticket
  sleep 0.5 # LockView focuses its field on the turn after it is built.
  type_keys b || fail "$first: the next key failed"
  expect_poll "$first: the next key reaches the lock's field" '"b"' sc_password
  expect "$first: no PAM check started" '[false, 0, 0]' sc_lock_status checking checks failures
  sc_release "$first"
}
sc_transfer move
sc_transfer key
sc_transfer click

# Equal times with unequal watch baselines. Lock first: the screensaver
# watch is recreated 1.5 s after the key, so Lock's watch fires first and
# starts the cover with the lock; the screensaver's own later callback
# changes nothing. Its edit leaves the lock watch alone.
sc_deadline() { # LABEL WANT: wait for WANT from sc_session, print its ms
  local deadline=$(( $(now_ms) + 10000 ))
  while (( $(now_ms) < deadline )); do
    [[ $(sc_session) == "$2" ]] && { echo $(( $(now_ms) - sc_started_ms )); return; }
    sleep 0.1
  done
  echo none
}
sc_times 5 4
sc_presents_before="$(sc_fixture status | py_reply 'import json,sys; print(len(json.load(sys.stdin)["presents"]))')"
sc_watch_before="$(sc_lock_watch)"
sc_idle_start "lock first"
sleep 1.5
sc_set acme.cover '{"seconds": 4}'
expect "lock first: the screensaver edit reloads" ok ipc shell reloadConfig
expect_poll "lock first: the screensaver watch follows its edit" '[["acme.cover", 4]]' sc_saver_watch
expect "lock first: the screensaver edit leaves the lock watch's generation" "$sc_watch_before" sc_lock_watch
sc_lock_ms="$(sc_deadline "lock first" locked)" || sc_lock_ms=unread
printf 'secure-cover: label=lock-first lock_ms=%s\n' "$sc_lock_ms"
if [[ $sc_lock_ms =~ ^[0-9]+$ ]] && (( sc_lock_ms >= 3500 && sc_lock_ms <= 5000 )); then ok "lock first: the lock keeps its 4 s deadline (t=${sc_lock_ms}ms)"; else fail "lock first: the lock keeps its 4 s deadline (t=${sc_lock_ms}ms)"; fi
expect_poll "lock first: Lock's idle event starts the cover in the lock" '["acme.cover", "secure", "lock"]' sc_cover
expect_poll "lock first: one renderer per output" "$(sc_outputs)" sc_renderers
expect "lock first: no lock screen is built under the cover" 0 sc_views
expect_poll "lock first: the screensaver's own later callback is idempotent" "[$((sc_presents_before + 1)), \"ok\"]" sc_present_tail
expect "lock first: the cover still started from the lock" '["acme.cover", "secure", "lock"]' sc_cover
expect "lock first: still one renderer per output" "$(sc_outputs)" sc_renderers
sc_release "lock first"

# Screensaver first: the lock watch is recreated 1.5 s after the key, so
# the screensaver's watch starts the cover on the desktop and Lock's later
# idle event moves that cover into the lock.
sc_times 4 5
sc_idle_start "screensaver first"
sleep 1.5
sc_set vgs.lock '{"idleLockSeconds": 4}'
expect "screensaver first: the lock edit reloads" ok ipc shell reloadConfig
expect_poll "screensaver first: the screensaver watch starts the cover first" '["acme.cover", "desktop", "idle"]' sc_cover
sc_id="$(sc_read identity)"; sc_pid="$(sc_read rendererPid)"
expect_poll "screensaver first: Lock's later idle event locks the session" locked sc_session
expect_poll "screensaver first: the running cover moved into the lock" '["acme.cover", "secure", "idle"]' sc_cover
expect "screensaver first: the same cover instance" "$sc_id" sc_read identity
expect "screensaver first: the same renderer" "$sc_pid" sc_read rendererPid
sc_release "screensaver first"

# Unequal times with no cover running expose the lock screen at once.
sc_times 0 3
sc_idle_start "no cover"
expect_poll "no cover: the lock stage watch locks the session" locked sc_session
expect "no cover: no cover is presented" '["acme.cover", "none", ""]' sc_cover
expect_poll "no cover: the lock screen shows" "$(sc_outputs)" sc_views
sc_release "no cover"

# A manual lock over a running cover shows the lock screen.
sc_times 0 0
hover 20 20 || fail "manual: resting the pointer failed"
expect "manual: the fixture starts its cover on demand" ok sc_fixture present
expect_poll "manual: the cover runs on the desktop" '["acme.cover", "desktop", "manual"]' sc_cover
expect "manual: Lock's IPC locks" ok ipc vgs.lock invoke lock ''
expect_poll "manual: the session is locked" locked sc_session
expect "manual: the lock was manual" '"manual"' sc_lent lock.cause
expect_poll "manual: the manual lock ended the cover" '["acme.cover", "none", ""]' sc_cover
expect "manual: it ended superseded" '"superseded"' sc_lent cover.ended
expect_poll "manual: the lock screen shows" "$(sc_outputs)" sc_views
expect "manual: an on-demand start is refused over the lock" 'refused: cover=locked' sc_fixture present
sc_release "manual"

# A cover held in the lock, for the ends that keep the lock.
sc_hold() { # LABEL
  sc_times 2 3
  hover 20 20 || fail "$1: resting the pointer failed"
  sc_idle_start "$1"
  expect_poll "$1: the cover is held in the lock" '["acme.cover", "secure", "idle"]' sc_cover
  expect_poll "$1: one renderer per output" "$(sc_outputs)" sc_renderers
  sc_times 0 0
}
sc_ended_locked() { # LABEL REASON[|REASON]
  expect_poll "$1: the cover ended" '["acme.cover", "none", ""]' sc_cover
  expect "$1: it ended by $2" yes sc_ended_by "$2"
  expect_poll "$1: no renderer is left" 0 sc_renderers
  expect "$1: the session stays locked" locked sc_session
  expect_poll "$1: the lock screen shows" "$(sc_outputs)" sc_views
}

# A rebuilt holder hands its screen over again as a restore lock.
sc_hold restore
expect "restore: disabling vgs.lock keeps the session locked" ok ipc shell setPluginEnabled vgs.lock false
expect "restore: enabling vgs.lock again is allowed" ok ipc shell setPluginEnabled vgs.lock true
expect_poll "restore: vgs.lock is built again" True record_exists vgs.lock
sc_close_notices restore
sc_ended_locked restore superseded
sc_release restore

sc_hold "renderer failure"
expect "renderer failure: the fixture reports its failure" ok sc_fixture failed
sc_ended_locked "renderer failure" failed
expect "renderer failure: a stop under the lock has nothing to stop" ok sc_fixture stop
sc_release "renderer failure"

sc_hold "display off"
expect "display off: the fixture turns the panels off" ok sc_fixture display-off
expect_poll "display off: the core confirms the panels off" true ipc smoke readInstance service vgs.screensaver displaysOff
sc_ended_locked "display off" displays-off
type_keys -k Shift_L || fail "display off: waking the panels failed"
expect_poll "display off: input lights the panels" false ipc smoke readInstance service vgs.screensaver displaysOff
sc_release "display off"

# Disabling the owner under the lock ends its cover; the screensaver stage
# passes to vgs.screensaver, which takes its stage watch.
sc_hold disable
expect "disable: disabling the cover fixture under the lock is allowed" ok ipc shell setPluginEnabled acme.cover false
expect_poll "disable: the stage passes to vgs.screensaver with nothing presented" '["vgs.screensaver", "none", ""]' sc_cover
expect "disable: it ended with its owner" '"owner"' sc_lent cover.ended
expect_poll "disable: no renderer is left" 0 sc_renderers
expect "disable: the session stays locked" locked sc_session
expect_poll "disable: the lock screen shows" "$(sc_outputs)" sc_views
expect_poll "disable: the new owner holds the screensaver stage watch" '[["vgs.screensaver", 150]]' sc_saver_watch
sc_release disable
expect "disable: enabling the cover fixture again is allowed" ok ipc shell setPluginEnabled acme.cover true
expect_poll "disable: the fixture owns the stage again" '["acme.cover", "none", ""]' sc_cover
expect_poll "disable: vgs.screensaver let its stage watch go" '[]' sc_saver_watch

# A rebuilt owner (its source changed) ends the cover its old instances
# drew, through the old service's release, the revision change or its
# last cover instance going, whichever the core hears first; the lock
# stays and no renderer is left.
sc_hold rebuild
python3 - "$home/.config/vgshell/plugins/acme.cover/manifest.json" <<'PY'
import json, os, sys
path = sys.argv[1]
doc = json.load(open(path))
doc["version"] = "0.1.1"
json.dump(doc, open(path + ".tmp", "w"))
os.replace(path + ".tmp", path)
PY
rescan "rebuild: a rescan under the lock answers ok"
sc_ended_locked rebuild 'owner|released|unbuilt'
expect_poll "rebuild: the rebuilt fixture owns the stage again" '["acme.cover", "none", ""]' sc_cover
sc_release rebuild

# A cover whose build fails, here an installed source that does not parse,
# leaves the owner with no instance: nothing claims a presentation, and an
# idle lock at equal times shows the lock screen at once rather than a
# barrier over an empty lock surface. A source that builds again restores it.
sc_cover_file="$home/.config/vgshell/plugins/acme.cover/Cover.qml"
cp -- "$sc_cover_file" "$sandbox/secure-cover-Cover.qml"
printf 'import QtQuick\nItem {\n' >"$sc_cover_file"
rescan "broken build: a rescan over the unparsable cover answers ok"
expect_poll "broken build: the owner holds no built cover" 0 sc_lent cover.built
expect "broken build: an on-demand start is refused" 'refused: cover=not-built' sc_fixture present
expect "broken build: the presentation stays off" '"none"' sc_placement
sc_times 3 3
sc_presents_before="$(sc_fixture status | py_reply 'import json,sys; print(len(json.load(sys.stdin)["presents"]))')"
hover 20 20 || fail "broken build: resting the pointer failed"
sc_idle_start "broken build"
expect_poll "broken build: the idle lock still locks" locked sc_session
expect "broken build: no cover is held in the lock" '"none"' sc_placement
expect_poll "broken build: the lock screen shows at once" "$(sc_outputs)" sc_views
expect_poll "broken build: the screensaver's own idle start is refused" "[$((sc_presents_before + 1)), \"refused: cover=not-built\"]" sc_present_tail
expect "broken build: no renderer runs" 0 sc_renderers
sc_times 0 0
sc_release "broken build"
cp -- "$sandbox/secure-cover-Cover.qml" "$sc_cover_file"
rescan "broken build: a rescan over the restored cover answers ok"
expect_poll "broken build: the restored cover is built on every output" "$(sc_outputs)" sc_lent cover.built

# Screensaver reloads and edits leave Lock's watch where it was.
sc_times 0 30
sc_watch_before="$(sc_lock_watch)"
expect "reload: Lock holds its one stage watch at 30 s" '[["vgs.lock", 30]]' sc_lock_timeouts
expect "reload: disabling the cover fixture is allowed" ok ipc shell setPluginEnabled acme.cover false
expect "reload: enabling the cover fixture is allowed" ok ipc shell setPluginEnabled acme.cover true
expect_poll "reload: the fixture is built again" True record_exists acme.cover
sc_set acme.cover '{"seconds": 7}'
expect "reload: a screensaver edit reloads" ok ipc shell reloadConfig
expect_poll "reload: the screensaver watch follows its edit" '[["acme.cover", 7]]' sc_saver_watch
expect "reload: Lock's watch is the one it had" "$sc_watch_before" sc_lock_watch
sc_times 0 0

# A second output under the lock gets its own cover in its own lock
# surface; the first input on one screen ends the cover on every screen,
# and removing an output takes its cover and renderer away. Hyprland moves
# the pointer when an output goes, which the lock surface reads as a move
# like any other, so the remaining cover may end with it; the lock holds
# either way and no renderer outlives its cover.
sc_extra=SMOKE-SECURE-COVER
sc_base_outputs="$(sc_outputs)"
sc_hold hotplug
expect "hotplug: the nested compositor adds an output under the lock" ok create_output "$sc_extra"
expect_poll "hotplug: the shell sees the added output" "$((sc_base_outputs + 1))" sc_outputs
sleep 2
printf 'secure-cover: hotplug cover=%s monitors=%s\n' "$(sc_lent cover)" "$(hypr -j monitors | py_reply 'import json,sys; print(json.dumps([[m["name"], m["width"], m["height"], m.get("solitaryBlockedBy")] for m in json.load(sys.stdin)]))')"
expect_poll "hotplug: each lock surface holds its own cover" "$((sc_base_outputs + 1))" sc_held_surfaces
expect_poll "hotplug: one renderer per output" "$((sc_base_outputs + 1))" sc_renderers
type_keys x || fail "hotplug: the first key failed"
expect_poll "hotplug: the first key ends the cover on every screen" '["acme.cover", "none", ""]' sc_cover
expect_poll "hotplug: no renderer is left on any screen" 0 sc_renderers
expect_poll "hotplug: every screen shows the lock screen" "$((sc_base_outputs + 1))" sc_views
expect "hotplug: the first key reached no field" '""' sc_password
sc_release "hotplug dismissal"
sc_hold hotplug
expect_poll "hotplug: each lock surface holds its cover again" "$((sc_base_outputs + 1))" sc_held_surfaces
expect "hotplug: the nested compositor removes the output" ok hypr output remove "$sc_extra"
expect_poll "hotplug: the output is gone" "$sc_base_outputs" sc_outputs
sc_renderers_left() { # one per output while the cover is held, none once it ended
  local placement count
  placement="$(sc_placement)" || return
  count="$(sc_renderers)" || return
  if [[ $placement == '"secure"' && $count == "$sc_base_outputs" ]] || [[ $placement == '"none"' && $count == 0 ]]; then echo matched; else echo "placement=$placement renderers=$count"; fi
}
expect_poll "hotplug: the removed output's cover and renderer went with it" matched sc_renderers_left
printf 'secure-cover: hotplug-removed cover=%s\n' "$(sc_lent cover)"
expect "hotplug: the session stays locked" locked sc_session
expect "hotplug: reloading drops the output's rule" ok hypr reload config-only
sc_release hotplug

# Put back what the row found: the plugins first, so the restored settings
# reach a lock plugin in the state the row found it.
expect "disabling the cover fixture after the row is allowed" ok ipc shell setPluginEnabled acme.cover false
sc_restore() { # PLUGIN STATE
  case "$2" in
    True) expect "$1 is enabled as the row found it" ok ipc shell setPluginEnabled "$1" true ;;
    False|absent) expect "$1 is disabled as the row found it" ok ipc shell setPluginEnabled "$1" false ;;
  esac
}
sc_restore vgs.screensaver "$sc_saver_was"
sc_restore vgs.lock "$sc_lock_was"
rm -rf -- "${home:?}/.config/vgshell/plugins/acme.cover"
python3 - "$sc_config" <<'PY'
import json, os, sys
path = sys.argv[1]
doc = json.load(open(path))
doc["plugins"] = [r for r in doc.get("plugins", []) if r.get("id") != "acme.cover"]
with open(path + ".next", "w") as out:
    json.dump(doc, out)
os.replace(path + ".next", path)
PY
sc_set vgs.lock '{"idleLockSeconds": null, "lockBeforeSleep": null}'
expect "reload after the secure cover row" ok ipc shell reloadConfig
rescan "rescan after removing the cover fixture answers ok"
expect_poll "the cover fixture is gone" False plugin_known acme.cover
if [[ $sc_probe == True ]]; then
  expect "re-enabling the capability fixture is allowed" ok ipc shell setPluginEnabled acme.probe true
  expect_poll "the capability fixture is built again after the row" True record_exists acme.probe
fi
sc_close_notices "after the row"
