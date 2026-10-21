# vgs.printers over the sandbox's CUPS stand-ins
# (docs/architecture/validation.md § Host safety): `lpstat` and `ipptool`
# are the recorded stand-ins in the shell's PATH directory, which answer
# from the CUPS world scripts/smoke/fixtures/devices/cups.py keeps, and
# the cups-pk-helper stand-in owns org.opensuse.CupsPkHelper.Mechanism on
# the sandbox system bus, where it changes that world, answers
# NotPrivileged while the world refuses, and sends the
# org.cups.cupsd.Notifier signals cupsd's dbus notifier sends. No step
# reaches the host's CUPS, its socket, its helper, polkit or a printer. The
# service holds `system`, so the core probes the system steps in the
# fakes' system tree (devices_system_tree), where the systemctl stand-in
# answers that cups.service runs.
#
# Rows: with the section closed the enabled service runs no watcher and
# CUPS holds no subscription of it; opening the section starts the watcher,
# which asks CUPS for one subscription with the dbus:// recipient and
# reports ready; the pane, mounted in the System window, reads back no
# printer, one, two with a default, a busy one with its jobs and a stopped
# one with its message in the danger tone, each after the world changed
# and CUPS notified;
# Set as default calls PrinterSetDefault, Remove calls PrinterDelete, Add
# on a found driverless device calls PrinterAdd with the everywhere model,
# then enables it and lets it take jobs, Add on the address field does the
# same for the address, and each change reaches the world and the list; a
# found device that needs a driver opens Print Settings and calls the
# helper not at all; an address of another scheme, or of a printer
# already added, is refused and calls nothing; with CUPS silent a change outside VGS stays off the list, so
# the list follows CUPS's notifications and polls nothing, and the
# service's own change reads lpstat at its end, which shows both; a
# refused authorisation leaves the world as it was and the pane shows the
# change's failure; closing the section cancels the subscription and
# leaves no watcher process or dbus-monitor, and opening it again reads
# the change the world took while it was closed and subscribes again;
# after disable with the section open the subscription is cancelled and
# nothing of the watcher remains. A copy without lpstat reads printing not
# installed, names the install action on its line, whose Review Setup
# draws on the step's row, Install printing in the section
# and no Print Settings, which needs CUPS, and
# the press raises the requirement notice for the missing command. The
# controls: a copy of the plugin that starts its watcher at enable, keeps
# it running after the section closes, whose changes call echo in place of
# the helper and whose watcher subscribes over TCP naming no owner: the
# closed section runs a watcher, Set as default, Remove and Add each leave
# the world as it was, the closed section keeps the subscription live, and
# after disable the owner rule leaves it live too. Every reading is
# expect_poll's: 25 reads 0.2 s apart; a reading that something stays is
# pr_stays's: 10 reads 0.2 s apart. The row leaves vgs.printers and
# vgs.system enabled or disabled as it found them, the world empty and no
# planted systemctl answer.
# inputs: shell/plugins/vgs.printers/* shell/plugins/vgs.system/* scripts/smoke/fixtures/devices/* scripts/smoke/devices.sh shell/Ui/layout/DeviceList.qml shell/Core/SystemSteps.qml shell/Core/PluginStatus.qml shell/Core/Capabilities.qml shell/Core/PluginLogic.js shell/Core/ConfigLogic.js shell/Hosts/PaneHost.qml bin/vgshell-system scripts/smoke/rows/device-fakes.sh
set -euo pipefail

pr_helper=org.opensuse.CupsPkHelper.Mechanism
pr_copy="$home/.config/vgshell/plugins/vgs.printers"

pr_view() { ipc smoke statusValues vgs.printers | py_reply 'import json,sys; v=json.load(sys.stdin).get("printers"); print("unpublished" if v is None else json.dumps(v[sys.argv[1]], sort_keys=True))' "$1"; }
pr_pane() { ipc smoke readInstance window vgs.printers "$1"; }
# The pane's printers as [name, state, jobs, default], and the drawn list
# as [name, badged].
pr_printers() { pr_pane printers | py_reply 'import json,sys; print(json.dumps([[p["name"], p["state"], p["jobs"], p["isDefault"]] for p in json.load(sys.stdin)]))'; }
pr_list() { ipc smoke readMatchingDescendant window vgs.printers DeviceList objectName printers-list rows | py_reply 'import json,sys; print(json.dumps([[r["text"], r["badge"] != ""] for r in json.load(sys.stdin)]))'; }
pr_found() { ipc smoke readMatchingDescendant window vgs.printers DeviceList objectName printers-found rows | py_reply 'import json,sys; print(json.dumps([[r["key"], r["driverless"]] for r in json.load(sys.stdin)]))'; }
# One key of the CUPS world: `names`, the printers' names, `printer:NAME`,
# that printer as [state, accepting, uri], or a key of the world itself.
pr_world() { cups_world_read | py_reply 'import json,sys
w=json.load(sys.stdin); k=sys.argv[1]
if k == "names": print(json.dumps(sorted(p["name"] for p in w["printers"])))
elif k.startswith("printer:"):
    p=[p for p in w["printers"] if p["name"] == k[8:]]
    print(json.dumps([p[0]["state"], p[0]["accepting"], p[0]["uri"]]) if p else "absent")
else: print(json.dumps(w[k], sort_keys=True))' "$1"; }
pr_world_state() { cups_world_read | py_reply 'import json,sys; w=json.load(sys.stdin); print(json.dumps([w["printers"], w["default"]], sort_keys=True))'; }
pr_message() { pr_pane printers | py_reply 'import json,sys; print(json.dumps([p["message"] for p in json.load(sys.stdin) if p["name"] == sys.argv[1]][0]))' "$1"; }
pr_printing() { ipc smoke statusValues vgs.printers | py_reply 'import json,sys; v=json.load(sys.stdin).get("printing"); print("unpublished" if v is None else json.dumps(v.get(sys.argv[1])))' "$1"; }
pr_offered() { pr_pane printingAction | py_reply 'import json,sys; print("none" if json.load(sys.stdin) is None else "offered")'; }
pr_tones() { ipc smoke readMatchingDescendant window vgs.printers DeviceList objectName printers-list rows | py_reply 'import json,sys; print(json.dumps([r["secondaryTone"] for r in json.load(sys.stdin)]))'; }
pr_settings_shown() { ipc smoke readMatchingDescendant window vgs.printers Button objectName printers-settings visible; }
pr_count() { device_calls "$1" | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
pr_calls_since() { device_calls cups-pk-helper | py_reply 'import json,sys; print(json.dumps([[c["method"], c["args"]] for c in json.load(sys.stdin)[int(sys.argv[1]):]]))' "$1"; }
# The subscription calls ipptool took since call N as [test file,
# recipient], "" for none; the default's reads are left out.
pr_ipptool_since() { device_calls ipptool | py_reply 'import json,sys
out=[]
for c in json.load(sys.stdin)[int(sys.argv[1]):]:
    if c[-1].endswith("/default.test"): continue
    recipient=[w.split("=",1)[1] for w in c if w.startswith("recipient=")]
    out.append([c[-1].rsplit("/",1)[-1], recipient[0] if recipient else ""])
print(json.dumps(out))' "$1"; }
# `live`, `cancelled` or `unknown` for subscription ID.
pr_subscription() { pr_world subscriptions | py_reply 'import json,sys; s=json.load(sys.stdin); i=int(sys.argv[1]); print("live" if i in s["live"] else "cancelled" if i in s["cancelled"] else "unknown")' "$1"; }
pr_last_subscription() { pr_world subscriptions | py_reply 'import json,sys; print(json.load(sys.stdin)["next"] - 1)'; }
pr_live_count() { pr_world subscriptions | py_reply 'import json,sys; print(len(json.load(sys.stdin)["live"]))'; }
# pr_world_jobs NAME N: printer NAME's queued jobs set to N in the world,
# as a change outside VGS makes it, with no notification.
pr_world_jobs() {
  local doc
  doc="$(cups_world_read | py_reply 'import json,sys
w=json.load(sys.stdin)
for p in w["printers"]:
    if p["name"] == sys.argv[1]: p["jobs"] = int(sys.argv[2])
print(json.dumps({"printers": w["printers"]}))' "$1" "$2")" || return 1
  cups_world "$doc"
}
pr_act() { ipc smoke invokeInstanceArgs window vgs.printers "$1" "{\"args\": $2}"; }
# The watcher's processes the sandbox runs, from /proc: printers-watch's
# two and its dbus-monitor, each with the sandbox's system bus.
pr_watchers() {
  python3 - "$rt_dir" <<'PY'
import json, os, sys
bus = ("DBUS_SYSTEM_BUS_ADDRESS=unix:path=" + sys.argv[1] + "/system-bus").encode()
count = {"watch": 0, "monitor": 0}
for pid in filter(str.isdigit, os.listdir("/proc")):
    try:
        argv = open(f"/proc/{pid}/cmdline", "rb").read().split(b"\0")
        environ = open(f"/proc/{pid}/environ", "rb").read().split(b"\0")
    except OSError:
        continue
    if bus not in environ:
        continue
    if any(a.endswith(b"bin/printers-watch") for a in argv):
        count["watch"] += 1
    elif argv[0].endswith(b"dbus-monitor") and any(b"org.cups.cupsd.Notifier" in a for a in argv):
        count["monitor"] += 1
print(json.dumps(count, sort_keys=True))
PY
}
# `stays` while CMD prints WANT for 10 reads 0.2 s apart, else what it
# printed.
pr_stays() { # WANT CMD...
  local want="$1" now
  shift
  for _ in $(seq 1 10); do
    now="$("$@")" || return
    [[ $now == "$want" ]] || { printf '%s\n' "$now"; return 0; }
    sleep 0.2
  done
  echo stays
}
# `shown` while the pane draws its problem line with the change's
# failure, else `absent`.
pr_problem() {
  local visible drawn problem
  visible="$(ipc smoke readMatchingDescendant window vgs.printers Label objectName printers-problem visible)" || return 1
  drawn="$(ipc smoke readMatchingDescendant window vgs.printers Label objectName printers-problem text)" || return 1
  problem="$(pr_pane problem)" || return 1
  if [[ $visible == true && $drawn == "$problem" && $drawn != '""' ]]; then echo shown; else echo absent; fi
}
pr_requirement() { ipc shell listPlugins | py_reply 'import json,sys; p=[p for p in json.load(sys.stdin)["plugins"] if p["id"] == "vgs.printers"]; r=[r for r in p[0]["requirements"] if r["name"] == sys.argv[1]] if p else []; print(r[0]["state"] if r else "absent")' "$1"; }
pr_status_record() { ipc shell lent | py_reply 'import json,sys; print("held" if "vgs.printers" in json.load(sys.stdin)["status"] else "absent")'; }
pr_enable() { # LABEL
  expect "enabling $1 is allowed" ok ipc shell setPluginEnabled vgs.printers true
  expect_poll "$1's service is built" True record_exists vgs.printers
}
# Open the section and wait for its watcher and its first reading.
pr_open() { # LABEL
  expect "$1's section summons" ok ipc shell summon window vgs.system '{"pane":"vgs.printers"}'
  expect_poll "$1's section is mounted" '["vgs.printers"]' window_panes
  expect_poll "$1's watcher reports ready" '"ready"' pr_view watch
  expect_poll "$1 reads the scheduler running" '"read"' pr_view cups
}

pr_main() {
  devices_ready printers || return 0
  local tree
  tree="$(devices_system_tree)" || { fail "printers: the fakes' system tree: $tree"; return 0; }
  device_reply systemctl 0 "" is-active --quiet cups.service
  pr_was_system="$(plugin_enabled vgs.system)" || { fail "printers: vgs.system's enabled state is unreadable"; return 0; }
  pr_was="$(plugin_enabled vgs.printers)" || { fail "printers: vgs.printers's enabled state is unreadable"; pr_was=""; return 0; }
  expect "the world starts with no printer and no subscription" world=set cups_world '{"down": false, "printers": [], "default": "", "devices": [], "refuse": false, "quiet": false, "subscriptions": {"next": 1, "live": [], "cancelled": []}}'
  expect "enabling vgs.system is allowed" ok ipc shell setPluginEnabled vgs.system true
  rescan "a scan reads the printer helper on the sandbox's bus"

  local ipp_before calls_before subscription
  ipp_before="$(pr_count ipptool)" || { fail "printers: the ipptool stand-in's calls are unreadable"; return 0; }
  pr_enable "vgs.printers"
  expect "the printer helper reads present" present pr_requirement "$pr_helper"
  expect "with the section closed no watcher runs" stays pr_stays '{"monitor": 0, "watch": 0}' pr_watchers
  expect "with the section closed CUPS holds no subscription" 0 pr_live_count
  expect "with the section closed the service asked CUPS for no subscription" '[]' pr_ipptool_since "$ipp_before"
  pr_open "vgs.printers"
  expect "opening the section made one subscription with the dbus:// recipient" '[["subscribe.test", "dbus://"]]' pr_ipptool_since "$ipp_before"
  expect "the open section's watcher runs as two processes beside one dbus-monitor" '{"monitor": 1, "watch": 2}' pr_watchers
  subscription="$(pr_last_subscription)" || { fail "printers: the world's subscriptions are unreadable"; return 0; }
  expect "CUPS holds the watcher's subscription" live pr_subscription "$subscription"

  # The list, each state after the world changed and CUPS notified.
  expect_poll "no printer: the section lists none" '[]' pr_list
  expect "one printer joins the world" world=set cups_world '{"printers": [{"name": "Office", "uri": "ipp://office.local/ipp/print", "state": "idle", "message": "", "jobs": 0, "accepting": true}]}'
  expect "CUPS notifies the new printer" signal=sent cups_signal PrinterAdded Office
  expect_poll "one printer: idle, no default" '[["Office", "idle", 0, false]]' pr_printers
  expect_poll "one printer: the section draws it" '[["Office", false]]' pr_list
  expect "a second printer is the default" world=set cups_world '{"printers": [{"name": "Office", "uri": "ipp://office.local/ipp/print", "state": "idle", "message": "", "jobs": 0, "accepting": true}, {"name": "Lab", "uri": "ipp://lab.local/ipp/print", "state": "idle", "message": "", "jobs": 0, "accepting": true}], "default": "Lab"}'
  expect "CUPS notifies the second printer" signal=sent cups_signal PrinterAdded Lab
  expect_poll "two printers: Lab is the default" '[["Lab", "idle", 0, true], ["Office", "idle", 0, false]]' pr_printers
  expect_poll "two printers: the section badges the default" '[["Lab", true], ["Office", false]]' pr_list
  expect "Office prints two jobs" world=set cups_world '{"printers": [{"name": "Office", "uri": "ipp://office.local/ipp/print", "state": "printing", "message": "", "jobs": 2, "accepting": true}, {"name": "Lab", "uri": "ipp://lab.local/ipp/print", "state": "idle", "message": "", "jobs": 0, "accepting": true}]}'
  expect "CUPS notifies the job" signal=sent cups_signal JobCreated Office
  expect_poll "busy: Office prints with two jobs queued" '[["Lab", "idle", 0, true], ["Office", "printing", 2, false]]' pr_printers
  expect "Lab stops" world=set cups_world '{"printers": [{"name": "Office", "uri": "ipp://office.local/ipp/print", "state": "printing", "message": "", "jobs": 2, "accepting": true}, {"name": "Lab", "uri": "ipp://lab.local/ipp/print", "state": "stopped", "message": "Paper jam", "jobs": 0, "accepting": true}]}'
  expect "CUPS notifies the stop" signal=sent cups_signal PrinterStateChanged Lab
  expect_poll "error: Lab reads stopped" '[["Lab", "stopped", 0, true], ["Office", "printing", 2, false]]' pr_printers
  expect "the stopped printer keeps its message" '"Paper jam"' pr_message Lab
  expect "error: the stopped printer's state line takes the danger tone, the printing one none" '["danger", ""]' pr_tones
  expect "Print Settings is offered while CUPS answers" true pr_settings_shown
  expect "both printers are idle again" world=set cups_world '{"printers": [{"name": "Office", "uri": "ipp://office.local/ipp/print", "state": "idle", "message": "", "jobs": 0, "accepting": true}, {"name": "Lab", "uri": "ipp://lab.local/ipp/print", "state": "idle", "message": "", "jobs": 0, "accepting": true}]}'
  expect "CUPS notifies the jobs' end" signal=sent cups_signal JobCompleted Office
  expect_poll "both printers read idle" '[["Lab", "idle", 0, true], ["Office", "idle", 0, false]]' pr_printers

  # Set as default.
  calls_before="$(pr_count cups-pk-helper)"
  expect "Set as default answers ok" ok pr_act setDefault '["Office"]'
  expect_poll "Set as default makes Office CUPS's default" '"Office"' pr_world default
  expect_poll "the list follows: Office is the default" '[["Lab", false], ["Office", true]]' pr_list
  expect "Set as default called PrinterSetDefault once" '[["PrinterSetDefault", ["Office"]]]' pr_calls_since "$calls_before"

  # Remove.
  calls_before="$(pr_count cups-pk-helper)"
  expect "Remove answers ok" ok pr_act remove '["Lab"]'
  expect_poll "Remove takes Lab out of CUPS" '["Office"]' pr_world names
  expect_poll "the list follows: Lab is gone" '[["Office", true]]' pr_list
  expect "Remove called PrinterDelete once" '[["PrinterDelete", ["Lab"]]]' pr_calls_since "$calls_before"

  # Add from the devices CUPS finds.
  expect "CUPS can reach two devices" world=set cups_world '{"devices": [{"class": "network", "info": "Lab Printer", "make": "HP LaserJet", "uri": "ipp://lab.local:631/ipp/print"}, {"class": "direct", "info": "Brother HL-L2350DW", "make": "Brother HL-L2350DW", "uri": "usb://Brother/HL-L2350DW?serial=E7"}]}'
  calls_before="$(pr_count cups-pk-helper)"
  expect "Find printers answers ok" ok pr_act find '[]'
  expect_poll "the section lists the found devices, the USB one needing a driver" '[["ipp://lab.local:631/ipp/print", true], ["usb://Brother/HL-L2350DW?serial=E7", false]]' pr_found
  expect "Add on the found printer answers ok" ok pr_act addFound '["ipp://lab.local:631/ipp/print"]'
  expect_poll "Add makes an enabled queue that takes jobs" '["idle", true, "ipp://lab.local:631/ipp/print"]' pr_world printer:Lab_Printer
  expect_poll "the list follows: the new printer is listed" '[["Lab_Printer", "idle", 0, false], ["Office", "idle", 0, true]]' pr_printers
  expect "Add called PrinterAdd with the everywhere model, then enabled it" '[["DevicesGet", [10, 32, [], []]], ["PrinterAdd", ["Lab_Printer", "ipp://lab.local:631/ipp/print", "everywhere", "Lab Printer", ""]], ["PrinterSetEnabled", ["Lab_Printer", true]], ["PrinterSetAcceptJobs", ["Lab_Printer", true, ""]]]' pr_calls_since "$calls_before"
  local settings_before
  calls_before="$(pr_count cups-pk-helper)"
  settings_before="$(pr_count system-config-printer)"
  expect "Add on the device that needs a driver opens Print Settings" ok pr_act addFound '["usb://Brother/HL-L2350DW?serial=E7"]'
  expect_poll "Print Settings starts system-config-printer" "$((settings_before + 1))" pr_count system-config-printer
  expect "the device that needs a driver calls the helper not at all" '[]' pr_calls_since "$calls_before"

  # Add from the address field.
  calls_before="$(pr_count cups-pk-helper)"
  expect "an address of another scheme is refused" "refused: address=scheme" pr_act addAddress '["lpd://192.0.2.7/queue"]'
  expect "the refused address calls the helper not at all" '[]' pr_calls_since "$calls_before"
  expect "Add on an address answers ok" ok pr_act addAddress '["192.0.2.7"]'
  expect_poll "the address becomes an enabled IPP queue" '["idle", true, "ipp://192.0.2.7/ipp/print"]' pr_world printer:192.0.2.7
  calls_before="$(pr_count cups-pk-helper)"
  expect "Add again on the address a printer uses is refused" "refused: address=installed" pr_act addAddress '["192.0.2.7"]'
  expect "Add again adds no second queue" '[]' pr_calls_since "$calls_before"
  expect_poll "the list follows: the address's printer is listed" '[["192.0.2.7", "idle", 0, false], ["Lab_Printer", "idle", 0, false], ["Office", "idle", 0, true]]' pr_printers

  # Silent CUPS: a change outside VGS stays off the list, and the service's
  # own change reads lpstat at its end.
  expect "CUPS goes silent" world=set cups_world '{"quiet": true}'
  expect "a change outside VGS queues three jobs on Office" world=set pr_world_jobs Office 3
  expect "without a notification the list keeps Office with no job" stays pr_stays '[["192.0.2.7", "idle", 0, false], ["Lab_Printer", "idle", 0, false], ["Office", "idle", 0, true]]' pr_printers
  expect "Set as default on the address's printer answers ok" ok pr_act setDefault '["192.0.2.7"]'
  expect_poll "the silent change reaches CUPS" '"192.0.2.7"' pr_world default
  expect_poll "the change's own end reads lpstat: the new default and Office's jobs" '[["192.0.2.7", "idle", 0, true], ["Lab_Printer", "idle", 0, false], ["Office", "idle", 3, false]]' pr_printers
  expect "CUPS speaks again" world=set cups_world '{"quiet": false}'

  # A refused authorisation.
  local world_before
  world_before="$(pr_world_state)"
  expect "polkit refuses" world=set cups_world '{"refuse": true}'
  expect "Remove under a refusal answers ok" ok pr_act remove '["Office"]'
  expect_poll "the refused change fails as refused" '{"kind": "remove", "phase": "failed", "problem": "refused", "target": "Office"}' pr_view op
  expect "the refused change leaves the world as it was" "$world_before" pr_world_state
  expect_poll "the section shows the change's failure" shown pr_problem
  expect "polkit allows again" world=set cups_world '{"refuse": false}'

  # Close: the subscription is cancelled and nothing of the watcher stays.
  expect "the watcher runs as two processes beside one dbus-monitor" '{"monitor": 1, "watch": 2}' pr_watchers
  expect "the System window closes" ok ipc shell hide window vgs.system
  expect_poll "closing the section cancels the subscription" cancelled pr_subscription "$subscription"
  expect_poll "closing the section leaves no watcher process or dbus-monitor" '{"monitor": 0, "watch": 0}' pr_watchers
  expect "the watcher stopped and ended with no complaint in the log" 0 log_lines 'printers: watcher (stopped|ended)'
  expect "a change outside VGS while closed clears Office's jobs" world=set pr_world_jobs Office 0
  expect "the closed section starts no watcher" stays pr_stays '{"monitor": 0, "watch": 0}' pr_watchers
  ipp_before="$(pr_count ipptool)" || { fail "printers: the ipptool stand-in's calls are unreadable"; return 0; }
  pr_open "the reopened section"
  expect_poll "opening the section reads the change it missed" '[["192.0.2.7", "idle", 0, true], ["Lab_Printer", "idle", 0, false], ["Office", "idle", 0, false]]' pr_printers
  expect "opening the section subscribes again" '[["subscribe.test", "dbus://"]]' pr_ipptool_since "$ipp_before"
  subscription="$(pr_last_subscription)" || { fail "printers: the world's subscriptions are unreadable"; return 0; }
  expect "CUPS holds the new subscription" live pr_subscription "$subscription"

  # Disable with the section open: the subscription is cancelled and
  # nothing of the watcher stays.
  expect "disabling vgs.printers with its section open is allowed" ok ipc shell setPluginEnabled vgs.printers false
  expect_poll "the service is gone" False record_exists vgs.printers
  expect_poll "disable cancels the subscription" cancelled pr_subscription "$subscription"
  expect_poll "no watcher process or dbus-monitor remains" '{"monitor": 0, "watch": 0}' pr_watchers
  expect_poll "the status record is gone" absent pr_status_record
  expect "the System window closes after the disable" ok ipc shell hide window vgs.system

  pr_uninstalled
  pr_controls
}

# Printing not installed: a copy whose lpstat no PATH holds
# (cups_uninstalled_copy). The `printing` line names the one install
# action, and the pane offers Install printing. Its press raises the
# notice for the missing command alone; Escape answers Not now.
pr_uninstalled() {
  rm -rf -- "${pr_copy:?}"
  expect "the not-installed copy is written" copy=written cups_uninstalled_copy "$pr_copy"
  rescan "a scan reads the not-installed copy"
  pr_enable "the not-installed copy"
  expect "the not-installed copy's section summons" ok ipc shell summon window vgs.system '{"pane":"vgs.printers"}'
  expect_poll "the not-installed copy's section is mounted" '["vgs.printers"]' window_panes
  expect_poll "not installed: the service reads printing not installed" '"missing"' pr_view cups
  expect_poll "not installed: the printing line names the install action" '"tools"' pr_printing action
  expect_poll "not installed: the section offers Install printing" offered pr_offered
  expect "not installed: the section offers no Print Settings" false pr_settings_shown
  expect "not installed: the section's action answers ok" ok pr_act runPrintingAction '[]'
  expect_poll "not installed: the notice offers the missing command alone" '["vgs.printers", ["vgs-smoke-lpstat"], ["vgs-smoke-lpstat"], false]' notice_shown
  expect_poll "not installed: the notice holds the keyboard" true ipc smoke noticeFocused
  type_keys -k Escape || fail "sending Escape to the notice failed"
  expect_poll "not installed: Escape closes the notice" null notice_shown
  expect "the not-installed copy's window closes" ok ipc shell hide window vgs.system
  expect "disabling the not-installed copy is allowed" ok ipc shell setPluginEnabled vgs.printers false
  expect_poll "the not-installed copy's service is gone" False record_exists vgs.printers
  rm -rf -- "${pr_copy:?}"
  rescan "a scan drops the not-installed copy"
}

# The controls: a copy that starts its watcher at enable and keeps it after
# the section closes, whose changes call echo in place of the helper, and
# whose watcher asks CUPS in the old form, over TCP and naming no owner, so
# its subscription is anonymous and the owner rule refuses its cancel.
pr_controls() {
  rm -rf -- "${pr_copy:?}"
  cp -R -- "$repo/shell/plugins/vgs.printers" "$pr_copy"
  python3 - "$pr_copy" <<'PY'
import os, sys
root = sys.argv[1]
logic = os.path.join(root, "PrintersLogic.js")
text = open(logic).read()
fake = '[["echo", "(\'\',)"]]'
for old in ['function defaultSteps(name) { return [helperArgv("PrinterSetDefault", [quoted(name)])]; }',
            'function removeSteps(name) { return [helperArgv("PrinterDelete", [quoted(name)])]; }',
            'function addSteps(name, uri, info) {\n    return [']:
    assert text.count(old) == 1, old
new = text.replace('function defaultSteps(name) { return [helperArgv("PrinterSetDefault", [quoted(name)])]; }', 'function defaultSteps(name) { return ' + fake + '; }')
new = new.replace('function removeSteps(name) { return [helperArgv("PrinterDelete", [quoted(name)])]; }', 'function removeSteps(name) { return ' + fake + '; }')
new = new.replace('function addSteps(name, uri, info) {\n    return [', 'function addSteps(name, uri, info) {\n    return ' + fake + ';\n    return [')
assert new != text
open(logic, "w").write(new)
service = os.path.join(root, "Service.qml")
text = open(service).read()
for old, rep in [('        shell.ipc.handle("view", arg => root.viewCall(arg));\n', '        shell.ipc.handle("view", arg => root.viewCall(arg));\n        read();\n'),
                 ("if (shown && reading.state", "if (reading.state"),
                 ('            watch = "stopping";\n            watcher.running = false;\n', '            watch = "ready";\n')]:
    assert text.count(old) == 1, old
    text = text.replace(old, rep)
open(service, "w").write(text)
text = open(logic).read()
old = 'var CUPS_URI = "ipp://%2Frun%2Fcups%2Fcups.sock/";'
assert text.count(old) == 1
open(logic, "w").write(text.replace(old, 'var CUPS_URI = "ipp://localhost/";'))
test = os.path.join(root, "ipp", "subscribe.test")
text = open(test).read()
old = "\tATTR name requesting-user-name $user\n"
assert text.count(old) == 1
open(test, "w").write(text.replace(old, ""))
PY
  rescan "a scan reads the Printers control copy"
  local subscription
  pr_enable "the control copy"
  expect_poll "control: a copy that watches at enable runs its watcher while the section is closed" '{"monitor": 1, "watch": 2}' pr_watchers
  pr_open "the control copy"
  subscription="$(pr_last_subscription)" || { fail "printers: the world's subscriptions are unreadable"; return 0; }
  expect "control: Set as default answers ok" ok pr_act setDefault '["Office"]'
  expect "control: a copy that drops PrinterSetDefault leaves CUPS's default" stays pr_stays '"192.0.2.7"' pr_world default
  expect "control: Remove answers ok" ok pr_act remove '["Office"]'
  expect "control: a copy that drops PrinterDelete leaves the printer" stays pr_stays '["192.0.2.7", "Lab_Printer", "Office"]' pr_world names
  expect "control: Add on an address answers ok" ok pr_act addAddress '["192.0.2.8"]'
  expect "control: a copy that drops PrinterAdd adds no printer" stays pr_stays '["192.0.2.7", "Lab_Printer", "Office"]' pr_world names
  expect "the control copy's window closes" ok ipc shell hide window vgs.system
  expect "control: a copy that keeps watching after close leaves the subscription live" stays pr_stays live pr_subscription "$subscription"
  expect "disabling the control copy is allowed" ok ipc shell setPluginEnabled vgs.printers false
  expect_poll "the control copy's watcher is gone" '{"monitor": 0, "watch": 0}' pr_watchers
  expect "control: an anonymous subscription over TCP is not the caller's to cancel" live pr_subscription "$subscription"
  rm -rf -- "${pr_copy:?}"
  rescan "a scan drops the Printers control copy"
}

pr_was_system=""
pr_was=""
pr_main
rm -rf -- "${pr_copy:?}"
case "$pr_was" in
  True) expect "vgs.printers is enabled again as the row found it" ok ipc shell setPluginEnabled vgs.printers true ;;
  False) expect "vgs.printers is disabled as the row found it" ok ipc shell setPluginEnabled vgs.printers false ;;
esac
if [[ $pr_was_system == False ]]; then expect "vgs.system is disabled again as the row found it" ok ipc shell setPluginEnabled vgs.system false; fi
cups_world '{"down": false, "printers": [], "default": "", "devices": [], "refuse": false, "quiet": false}' >/dev/null
device_reply_clear systemctl
