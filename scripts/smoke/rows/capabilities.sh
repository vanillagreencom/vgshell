# Capabilities, each driven through the fixture's own IPC target and read
# back from the fixture, the core's lending record and the compositor or bus
# the capability reaches.
# dictation: the fixture acme.dictation holds it over the voxtype stand-in,
# scripts/smoke/fixtures/voxtype/, which is on the shell's PATH only while
# a row holds the capability, so no row starts the host's voxtype; the
# daemon the core starts for the holder is the stand-in. The row puts the
# stand-ins away again and leaves the fixture disabled.
# inputs: scripts/smoke/fixtures/plugins/acme.probe/* scripts/smoke/fixtures/plugins/acme.bare/* scripts/smoke/fixtures/plugins/acme.dictation/* scripts/smoke/fixtures/voxtype/* shell/Core/Dictation.qml shell/Core/DictationModel.js shell/Core/Capabilities.qml shell/Core/ShortcutRegistry.qml shell/Core/IpcRegistry.qml shell/Core/IdleRegistry.qml shell/Core/PluginLogic.js shell/Core/Registry.qml shell/plugins/vgs.lock/manifest.json shell/Core/SessionLock.qml shell/Core/NotificationHub.qml shell/Core/Compositor.qml shell/Core/Dispatch.js bin/vgshell-dictation bin/lib/voxtype.sh bin/lib/voxtype.py scripts/smoke/rows/plugins.sh
set -euo pipefail
leak_plugin_setup acme.probe true acme.bare true || { fail "capabilities: fixture precondition failed"; return 1; }
expect_poll "the shared fixture is built before its dependent reads" True record_exists acme.probe
lent() { ipc shell lent | py_reply 'import json,sys; d=json.load(sys.stdin); v=d
for k in sys.argv[1].split("."): v=v.get(k) if isinstance(v, dict) else None
print(json.dumps(v))' "$1"; }
# qs ipc reads a bracketed argument as a list, so no argument here is JSON
# with brackets: `set` takes key=value with a JSON value, `dispatch` a
# dispatcher and its arguments separated by spaces.
probe() { ipc acme.probe invoke "$1" "${2:-}"; }
# The fixture holds every capability and the bare fixture none; another
# plugin may hold a shared capability beside the fixture.
lent_holds() { ipc shell lent | py_reply 'import json,sys; h=json.load(sys.stdin)["holders"].get(sys.argv[1],[]); print("acme.probe" in h and "acme.bare" not in h)' "$1"; }
for cap in compositor configure cover idle ipc lock notifications polkit run screens shortcut notify theme; do
  expect "the $cap capability is lent to the fixture and not the bare plugin" True lent_holds "$cap"
done

fixture_shortcuts() { ipc shell lent | py_reply 'import json,sys; print(json.dumps([s for s in json.load(sys.stdin)["shortcuts"] if s.startswith("acme.")]))'; }
expect "the fixture's shortcut is registered under its id" '["acme.probe:ping"]' fixture_shortcuts
count_lines() { python3 -c 'import sys; print(sum(1 for line in sys.stdin if sys.argv[1] in line))' "$1"; }
hypr_shortcuts() { hypr globalshortcuts | count_lines 'acme.probe:ping'; }
expect_poll "the compositor lists the fixture's shortcut" 1 hypr_shortcuts
declare presses_before
capabilities_count_control() {
  python3 - "$repo/scripts/smoke/rows/capabilities.sh" "$repo/scripts/smoke/verdict.sh" "$BASH" <<'PY'
import os, pathlib, subprocess, sys
row, verdict, bash = sys.argv[1:]
lines = pathlib.Path(row).read_text().splitlines()
read = [line for line in lines if line.startswith(('read_count presses_before ', 'presses_before='))]
check = [line for line in lines if line.startswith("expect_poll \"the fixture's shortcut handler ran\"")]
if len(read) != 1 or len(check) != 1:
    sys.exit('capabilities-count-control: operations-unread')
script = '''set -euo pipefail
source "$1"
read_service() { echo absent; }
expect_poll() { printf 'later-check=%s\n' "$2"; }
''' + read[0] + '\n' + check[0] + '''
echo later-row=ran
smoke_verdict "$failures" "$behaviour_failures" /dev/null
'''
run = subprocess.run([bash, '-c', script, '_', verdict], env={'PATH': os.environ['PATH']}, capture_output=True, text=True)
lines = run.stdout.splitlines()
if run.returncode == 1 and len(lines) == 4 and lines[0].startswith('  FAIL  capabilities: shortcut presses before:') and lines[1:] == ['later-check=1', 'later-row=ran', 'qml-smoke: failed=1']:
    print('red-and-continued')
else:
    print(f'status={run.returncode} stdout={run.stdout!r} stderr={run.stderr!r}')
PY
}
expect "control: an absent probe count fails and later checks and rows run" red-and-continued capabilities_count_control
read_count presses_before "capabilities: shortcut presses before" read_service presses
expect "the compositor triggers the fixture's shortcut" ok hypr dispatch 'hl.dsp.global("acme.probe:ping")'
expect_poll "the fixture's shortcut handler ran" "$((presses_before + 1))" read_service presses
expect "a second shortcut with the same name is refused" '"refused: shortcut=acme.probe:ping held"' read_service duplicateShortcut

ipc_targets() { "${shell_env[@]}" qs ipc --pid "$shell_qs_pid" show 2>>"$sandbox/ipc.log" | count_lines 'target acme.probe'; }
expect "qs lists the fixture's IPC target" 1 ipc_targets
expect "the fixture answers on its IPC target" hello probe echo hello
expect "a second IPC handler with the same name is refused" '"refused: ipc=acme.probe:echo held"' read_service duplicateIpc
# shell.ipc.call reaches the calling plugin's own handlers in the shell;
# scripts/test-ipc-logic.js holds a control for each of its rules.
expect "a plugin's call reaches its own handler" hello probe call "echo hello"
expect "a plugin's call names a handler it holds none of as unknown" "unknown: nope" probe call nope
expected_errors+=('capabilities: ipc acme\.probe:throws threw: planted')
expect "a plugin's call answers a throwing handler's error" "error: planted" probe call throws
expect "a plugin's call with an argument that is not text is refused" "refused: ipc=echo arg=not-a-string" probe call-number

expect "configure writes a declared setting" ok probe set 'label="via-configure"'
expect_poll "the running service received the setting it wrote" '"via-configure"' read_service label
expect "configure refuses a value of the wrong type" "refused: setting=label want=string" probe set 'label=3'
expect "configure refuses a setting the manifest does not declare" "refused: setting=absent undeclared" probe set 'absent="x"'
expect "configure refuses another type for a setting with no schema entry" "refused: setting=tags want=list" probe set 'tags="x"'
expect "configure refuses to unset an undeclared setting" "refused: setting=id undeclared" probe unset id

# A widget placed twice writes its plugins row, which its service and both
# placements read; its layout entries keep their ids alone.
right_entries() {
  python3 - "$home/.config/vgshell/shell.json" "$1" <<'PY'
import json, os, sys
p, action = sys.argv[1], sys.argv[2]
d = json.load(open(p))
right = d["bar"]["layout"]["right"]
if action == "add":
    right.append({"id": "acme.probe"})
elif action == "drop":
    last = max(i for i, e in enumerate(right) if e["id"] == "acme.probe")
    del right[last]
else:
    print(json.dumps([e for e in right if e["id"] == "acme.probe"]))
    sys.exit(0)
json.dump(d, open(p + ".tmp", "w"), indent=2)
os.replace(p + ".tmp", p)
PY
}
probe_widgets() { ipc shell built | py_reply 'import json,sys; d=json.load(sys.stdin); print(sum(1 for r in d[sys.argv[1]] if r["id"]=="acme.probe"))' "$(bar_key)"; }
# probe_widget_labels: the label each acme.probe widget under the first bar
# holds, in the bar's item order.
probe_widget_labels() { ipc smoke itemValues "$(bar_key)" vgs.bar Widget moduleName,label | py_reply 'import json,sys; print(json.dumps([w["label"] for w in json.load(sys.stdin) if w["moduleName"] == "acme.probe"]))'; }
probe_row_label() { python3 -c 'import json,sys; print(json.dumps([e.get("label") for e in json.load(open(sys.argv[1])).get("plugins",[]) if e["id"]=="acme.probe"]))' "$home/.config/vgshell/shell.json"; }
right_entries add
expect_poll "the fixture widget is placed twice" 2 probe_widgets
expect "a widget's configure writes its plugins row" ok ipc smoke invokeInstance "$(bar_key)" acme.probe setLabel only-first
expect_poll "the plugins row holds the widget's setting" '["only-first"]' probe_row_label
expect "the layout entries keep their ids alone" '[{"id": "acme.probe"}, {"id": "acme.probe"}]' right_entries show
expect_poll "the service reads the setting the widget wrote" '"only-first"' read_service label
expect_poll "both placements read the setting one of them wrote" '["only-first", "only-first"]' probe_widget_labels
right_entries drop
expect_poll "the second placement is gone" 1 probe_widgets

expect "run starts a detached process" ok probe touch "$sandbox/touched-by-run"
touched() { [[ -f $sandbox/touched-by-run ]] && echo yes || echo no; }
expect_poll "the detached process ran" yes touched
# A detached program is the user's, not the shell's: it starts without the
# shell's marker, which `vgshell pkg run` refuses, and with the rest of the
# shell's environment.
expect "run starts a process that writes its environment" ok probe environ "$sandbox/detached-env"
detached_env() { [[ -s $sandbox/detached-env ]] || { echo pending; return; }; grep -q '^PATH=' "$sandbox/detached-env" && ! grep -q '^VGSHELL_RUNNER_PID=' "$sandbox/detached-env" && echo clean || echo marked; }
expect_poll "the detached process has no VGSHELL_RUNNER_PID" clean detached_env

bus_owner() { "${shell_env[@]}" gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.NameHasOwner "$1" 2>>"$sandbox/ipc.log"; }
expect_poll "the core's notification server owns the bus name" "(true,)" bus_owner org.freedesktop.Notifications
notify() { "${shell_env[@]}" gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.Notify smoke 0 '' probe-summary probe-body '[]' '{}' 5000 >/dev/null 2>>"$sandbox/ipc.log" && echo sent; }
expect "a client sends a notification" sent notify
expect_poll "the fixture's subscriber received it" '"probe-summary"' read_service lastSummary

expect "the polkit agent exists while the fixture holds it" true lent polkitAgent
expect "the fixture reads the lent polkit agent" true read_service hasAgent
expect "the agent reports no registration on a bus without polkitd" false read_service agentRegistered
expect "the lending record reports the registration" false lent polkitRegistered

# The lock route takes closed causes, and an idle lock only with a ticket
# the holder's own lock stage watch minted; the cover provider serves only
# the screensaver stage's owner.
expect "a lock request with no cause is refused" 'refused: lock-cause=undefined want=idle|manual|sleep|restore' probe lock-request '{}'
expect "a lock request with an unknown cause is refused" 'refused: lock-cause="later" want=idle|manual|sleep|restore' probe lock-request '{"cause":"later"}'
expect "a manual lock request carrying a ticket is refused" 'refused: lock-request=cause,ticket want=cause' probe lock-request '{"cause":"manual","ticket":{}}'
expect "an idle lock request with a forged ticket is refused" 'refused: lock-ticket=stale' probe lock-request '{"cause":"idle","ticket":{}}'
expect "the refused requests left the session unlocked" false lent lock.requested
stage_refusal() { local reply; reply="$(probe idle-watch-stage "$1")" || return; echo "${reply%% owner=*}"; }
expect "a plugin that owns no lock stage cannot hold its stage watch" 'refused: idle-stage=lock' stage_refusal lock
expect "a plugin that owns no screensaver stage cannot present a cover" 'refused: cover=not-owner' probe cover-present
expect "a plugin that owns no screensaver stage cannot stop a cover" 'refused: cover=not-owner' probe cover-stop
expect "the fixture locks the session" ok probe lock
expect_poll "the compositor confirms the lock" true read_service lockSecure
# A rebuild while locked keeps the session locked, and the rebuilt holder
# hands its screen over again. Change the holder's own source revision.
python3 - "$home/.config/vgshell/plugins/acme.probe/manifest.json" <<'PY'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p))
d["version"] = "0.1.1"
json.dump(d, open(p + ".tmp", "w"))
os.replace(p + ".tmp", p)
PY
lock_content() { lent lock.content; }
if before="$(builds)"; then
  rescan "a rescan while locked answers ok"
  rebuilt() { local now; now="$(builds)" && [[ $now -gt $before ]] && echo rebuilt || echo same; }
  expect_poll "the changed manifest rebuilt the holder" rebuilt rebuilt
  expect "only the holder service and its widgets rebuilt" "$((before + monitors + 1))" builds
  expect "the replacement service starts with no shortcut presses" 0 read_service presses
  expect_poll "the rebuilt holder handed its screen over again" true lock_content
  expect "the session stayed locked through the rebuild" true read_service lockSecure
  expect "the rebuilt fixture answers on its IPC target" hello probe echo hello
  read_count presses_before "capabilities: rebuilt shortcut presses before" read_service presses
  expect "the compositor triggers the rebuilt fixture's shortcut" ok hypr dispatch 'hl.dsp.global("acme.probe:ping")'
  expect_poll "the rebuilt fixture's shortcut handler ran" "$((presses_before + 1))" read_service presses
else
  fail "buildCount unreadable before the lock rebuild rows"
fi
expect "the fixture unlocks the session" ok probe unlock
expect_poll "the compositor released the lock" false read_service lockSecure

expect "the fixture service sees every screen" "$monitors" read_service screenCount
expect "a service draws on no screen" true read_service noCurrentScreen
expect "the fixture widget draws on its bar's screen" "\"$(bar_key | sed 's/^bar://')\"" read_widget currentScreen

special_ws() { hypr -j monitors | py_reply 'import json,sys; print(json.load(sys.stdin)[0]["specialWorkspace"]["name"])'; }
expect "the fixture toggles a special workspace" ok probe dispatch 'toggleSpecialWorkspace probe'
expect_poll "the compositor shows the special workspace" "special:probe" special_ws
expect_poll "the fixture closes the special workspace again" ok probe dispatch 'toggleSpecialWorkspace probe'
expect_poll "the compositor hides the special workspace" "" special_ws
expect "the fixture focuses a workspace" ok probe dispatch 'focusWorkspace 2'
expect_poll "the compositor moved to that workspace" 2 active_ws
expect_poll "the fixture focuses the first workspace again" ok probe dispatch 'focusWorkspace 1'
expect_poll "the compositor moved back" 1 active_ws

# idle: a watch reports idle once the nested seat has had no input for its
# timeout and active again at the next key; the lending record lists it,
# and its disposer drops it. A zero timeout is refused.
idle_watches() { ipc shell lent | py_reply 'import json,sys; print(json.dumps([[w["id"], w["timeout"]] for w in json.load(sys.stdin)["idle"]]))'; }
expect "an idle watch of zero seconds is refused" "refused: idle-timeout=0 want=1..86400" probe idle-watch 0
expect "the fixture watches for one second without input" ok probe idle-watch 1
expect "the lending record lists the watch" '[["acme.probe", 1]]' idle_watches
# The first two changes: the seat goes idle again a second after the key.
idle_changes() { read_service idleChanges | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)[:2]))'; }
expect_poll "the watch reports idle after a second without input" '["idle"]' idle_changes
type_keys -k Shift_L || fail "typing a key for the idle watch failed"
expect_poll "a key reports the seat active again" '["idle", "active"]' idle_changes
expect "the disposer drops the watch" ok probe idle-unwatch
expect "the lending record lists no watch after the disposer" '[]' idle_watches

# idle stages: shell.idle.stages, the core's record of the stage each
# enabled plugin declares, read bound by the fixture as [stage, plugin,
# setting, seconds, before]. vgs.lock is enabled here but never built,
# because the fixture holds the exclusive lock, so it locks nothing; the
# fixture is not rebuilt while vgs.lock is enabled, so the lock cannot pass
# to it. vgs.displays and vgs.screensaver build services that reach the
# panels and ttfx, which this row has no stand-ins for:
# scripts/test-plugin-logic.js reads all three bundled stages from their
# shipped manifests.
idle_stages() { read_service idleStages | py_reply 'import json,sys; print(json.dumps([[s["stage"], s["plugin"], s["setting"], s["seconds"], s["before"]] for s in json.loads(json.load(sys.stdin))]))'; }
idle_problems() { ipc shell listPlugins | py_reply 'import json,sys; print(json.dumps(sorted(e["error"].split(" skipped:")[0] for e in json.load(sys.stdin)["errors"] if e["error"].startswith("idle: "))))'; }
lock_row() { # KEY VALUE: one value of vgs.lock's plugins row, null removes it
  python3 - "$home/.config/vgshell/shell.json" "$1" "$2" <<'PY'
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
json.dump(config, open(path + ".tmp", "w"), indent=2)
os.replace(path + ".tmp", path)
PY
}
probe_stages() { # declare|drop: the fixture copy's own idle stages
  python3 - "$home/.config/vgshell/plugins/acme.probe/manifest.json" "$1" <<'PY'
import json, os, sys
p, action = sys.argv[1], sys.argv[2]
d = json.load(open(p))
if action == "declare":
    d["idleStages"] = {"screensaver": {"seconds": "delay", "enabled": "accent"}, "lock": {"seconds": "size"}}
else:
    del d["idleStages"]
json.dump(d, open(p + ".tmp", "w"))
os.replace(p + ".tmp", p)
PY
}
expect "no enabled plugin owns an idle stage" '[]' idle_stages
expect "vgs.lock starts disabled" False plugin_enabled vgs.lock
expect "enabling vgs.lock while the fixture holds the lock is allowed" ok ipc shell setPluginEnabled vgs.lock true
expect_poll "the record lists the bundled lock stage at its default" '[["lock", "vgs.lock", "idleLockSeconds", 300, []]]' idle_stages
expect "the fixture alone holds the lock" '["acme.probe"]' lent holders.lock
expect "the fixture reads every entry frozen" true read_service idleStagesFrozen
lock_row idleLockSeconds 0
expect_poll "the bundled lock set to 0 reads Never" '[["lock", "vgs.lock", "idleLockSeconds", 0, []]]' idle_stages
lock_row idleLockSeconds null
expect_poll "the bundled lock reads its default again" '[["lock", "vgs.lock", "idleLockSeconds", 300, []]]' idle_stages
expect "disabling vgs.lock before the fixture declares stages is allowed" ok ipc shell setPluginEnabled vgs.lock false
expect_poll "the disabled lock owns no stage" '[]' idle_stages
probe_stages declare
rescan "a rescan after the fixture declares idle stages answers ok"
expect_poll "a lock due first fires before the screensaver" '[["screensaver", "acme.probe", "delay", 800, []], ["lock", "acme.probe", "size", 12, ["screensaver"]]]' idle_stages
expect "the fixture turns its screensaver stage off" ok probe set 'accent=false'
expect_poll "a stage turned off reads Never and nothing fires before it" '[["screensaver", "acme.probe", "delay", 0, []], ["lock", "acme.probe", "size", 12, []]]' idle_stages
expect "the fixture turns its screensaver stage on again" ok probe unset accent
expect "no idle stage is a problem before a second declarer" '[]' idle_problems
expect "enabling vgs.lock beside the fixture's lock stage is allowed" ok ipc shell setPluginEnabled vgs.lock true
expect_poll "vgs.lock, the second declarer of the lock, is reported" '["idle: stage lock of vgs.lock"]' idle_problems
expect "the first declarer by id keeps the lock stage" '[["screensaver", "acme.probe", "delay", 800, []], ["lock", "acme.probe", "size", 12, ["screensaver"]]]' idle_stages
expect "disabling vgs.lock again is allowed" ok ipc shell setPluginEnabled vgs.lock false
expect_poll "the disabled declarer is no problem" '[]' idle_problems
probe_stages drop
rescan "a rescan after the fixture drops its idle stages answers ok"
expect_poll "the record is empty again" '[]' idle_stages

# dictation_stand_ins on|off: the voxtype and wtype stand-ins in the shell's
# stand-in directory, swapped whole. `on` returns 1 unless the shell then
# resolves voxtype to the stand-in, so no caller enables a holder over the
# host's command.
dictation_stand_ins() { # on|off
  local name
  if [[ $1 == off ]]; then
    rm -f -- "${shim:?}/voxtype" "${shim:?}/wtype"
    rm -f -- "${sandbox:?}/voxtype-model-installed"
    return 0
  fi
  for name in voxtype wtype; do
    cp -- "$repo/scripts/smoke/fixtures/voxtype/$name" "$shim/$name.next" && chmod 755 "$shim/$name.next" && mv -T -- "$shim/$name.next" "$shim/$name" || return 1
  done
  touch -- "$sandbox/voxtype-model-installed"
  [[ $(shell_resolves voxtype) == "$shim/voxtype" ]]
}
# The stand-in's processes by role: `all` includes foreign processes and
# orphans; `owned` counts direct children and raw children of exactly one
# direct dictation transport. Fixture forks are not another owned role.
# With `pids` it prints all matching pids for cleanup.
dictation_processes() { # all|owned|pids
  python3 - "$shim/voxtype" "${shell_qs_pid:-none}" "$1" "$shell_tree/bin/lib/voxtype.py" <<'PY'
import os, sys
stand_in, shell, want, helper = sys.argv[1:]
counts = {scope: {"daemon": 0, "follower": 0, "other": 0} for scope in ("all", "owned")}
pids = []
for pid in os.listdir("/proc"):
    # This reader's own arguments name the stand-in too.
    if not pid.isdigit() or int(pid) == os.getpid():
        continue
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            args = f.read().decode(errors="replace").split("\0")
        with open(f"/proc/{pid}/status") as f:
            parent = next(line.split()[1] for line in f if line.startswith("PPid:"))
    except (OSError, StopIteration, IndexError):
        continue
    if stand_in not in args:
        continue
    verb = args[args.index(stand_in) + 1:]
    while len(verb) >= 2 and verb[0] in ("--config", "--audio-device"):
        verb = verb[2:]
    kind = "daemon" if verb[:1] == ["daemon"] else "follower" if verb[:2] == ["status", "--follow"] else "other"
    counts["all"][kind] += 1
    owned = parent == shell
    if not owned:
        try:
            with open(f"/proc/{parent}/cmdline", "rb") as f:
                owner_args = f.read().decode(errors="replace").split("\0")
            with open(f"/proc/{parent}/status") as f:
                owner_parent = next(line.split()[1] for line in f if line.startswith("PPid:"))
            role = "daemon" if kind == "daemon" else "follow" if kind == "follower" else "run"
            owned = owner_parent == shell and os.path.basename(owner_args[0]) == "python3" and owner_args[1:5] == [helper, "supervise", role, "voxtype"]
        except (OSError, StopIteration, IndexError):
            pass
    if owned:
        counts["owned"][kind] += 1
    pids.append(pid)
print(" ".join(pids) if want == "pids" else " ".join(f"{k}={v}" for k, v in counts[want].items()))
PY
}
dictation_lent() { lent dictation | py_reply 'import json,sys; d=json.load(sys.stdin); print(d["daemon"], d["child"], ",".join(d["holders"]) or "-")'; }
dictation_fixture="$home/.config/vgshell/plugins/acme.dictation"
mkdir -p "$dictation_fixture"
cp -R "$repo/scripts/smoke/fixtures/plugins/acme.dictation/." "$dictation_fixture/"
rescan "rescan after adding the dictation fixture answers ok"
expect_poll "the dictation fixture is discovered" True plugin_known acme.dictation
expect "no holder of dictation leaves no daemon" "absent none -" dictation_lent
if dictation_stand_ins on; then
  expect "enabling the dictation fixture is allowed" ok ipc shell setPluginEnabled acme.dictation true
  dictation_holds() { ipc shell lent | py_reply 'import json,sys; h=json.load(sys.stdin)["holders"].get("dictation",[]); print("acme.dictation" in h and "acme.bare" not in h)'; }
  expect_poll "the dictation capability is lent to its fixture and not the bare plugin" True dictation_holds
  expect_poll "the core starts the daemon for the holder" "ready running acme.dictation" dictation_lent
  expect_poll "the daemon and its follower are the stand-in, children of the shell" "daemon=1 follower=1 other=0" dictation_processes owned
  expect "disabling the dictation fixture is allowed" ok ipc shell setPluginEnabled acme.dictation false
  expect_poll "the daemon ends with its holder" "daemon=0 follower=0 other=0" dictation_processes all
else
  fail "the shell does not resolve voxtype to the stand-in: $(shell_resolves voxtype)"
fi
dictation_stand_ins off
