# Shared production-console fixture and readers for smoke and capture.
# The package command is copied into a private Home; no mailbox is read.
set -euo pipefail

jarvis_asks_fixture() { # SOURCE_TREE
  # The shell and fixture daemon share the outer world's private HOME.
  # Its package Home survives each daemon's J09 world and cleanup; the
  # lease installs the actual command before starting the daemon.
  # The outer world owns this Home and its teardown. Keep each scene's
  # fixture separate without installing another EXIT trap over the harness.
  jarvis_asks_serial=$((${jarvis_asks_serial:-0} + 1))
  jarvis_asks_home="$home/jarvis-asks-$jarvis_asks_serial"
  mkdir -- "$jarvis_asks_home" || return 1
  local name="${jarvis_asks_home##*/}" world="$sandbox/jarvis-world"
  local scripts="$jarvis_asks_home/.agents/skills/jarvis/scripts"
  # A home Setup set up: the daemon writes nothing in a home (D126).
  "$node_bin" -e 'require(process.argv[1]).jarvisHome(process.argv[2], process.argv[3])' \
    "$1/scripts/fixtures/jarvis/home.js" "$jarvis_asks_home" "$1" || return 1
  mkdir -p -- "$scripts" || return 1
  cp -- "$1/scripts/fixtures/jarvis/owner-asks.js" "$scripts/jarvis-session" || return 1
  chmod 755 "$scripts/jarvis-session" || return 1
  "$node_bin" "$scripts/jarvis-session" --seed "$jarvis_asks_home" || return 1
  jarvis_asks_handoff="$world/owner-asks-home"
  jarvis_asks_lease_before="$sandbox/$name-lease-before"
  cp -- "$world/lease.sh" "$jarvis_asks_lease_before" || return 1
  rm -f -- "$jarvis_asks_handoff" || return 1
  cat >"$world/owner-asks-bootstrap.sh" <<'ASKBOOTSTRAP'
#!/bin/bash
set -euo pipefail
fixture_source="$1" fixture_name="$2" fixture_handoff="$3" fixture_user_home="$4"
shift 4
fixture_home="$fixture_user_home/$fixture_name"
fixture_command="$fixture_home/.agents/skills/jarvis/scripts/jarvis-session"
mkdir -p -- "${fixture_command%/*}"
cp -- "$fixture_source" "$fixture_command"
chmod 755 "$fixture_command"
if [[ ! -e $fixture_home/.owner-asks-fixture.json ]]; then
  node "$fixture_command" --seed "$fixture_home"
fi
printf '%s\n' "$fixture_home" >"$fixture_handoff.next"
mv -T -- "$fixture_handoff.next" "$fixture_handoff"
exec env HOME="$fixture_user_home" node "$@"
ASKBOOTSTRAP
  # Keep prepare.js's inherited pipe descriptor until the innermost shell
  # restores it; J09 starts its namespace supervisor asynchronously.
  python3 - "$world/lease.sh" "$world/owner-asks-bootstrap.sh" "$1/scripts/fixtures/jarvis/owner-asks.js" "$name" "$jarvis_asks_handoff" "$home" <<'ASKLEASE'
from pathlib import Path
import shlex,sys
Path(sys.argv[1]).write_text('#!/bin/bash\nset -euo pipefail\nexec 3<&0\n'
    'exec bash "$1" "$2" -- bash -c \'exec bash "$@" <&3 3<&-\' jarvis-lease '
    + shlex.join(sys.argv[2:]) + ' "$3" --tree "$4"\n')
ASKLEASE
  user_config_write python3 - "$home/.config/vgshell/shell.json" "~/$name" <<'PYASKHOME'
import json,sys
from pathlib import Path
value=json.loads(Path(sys.argv[1]).read_text())
row=next((row for row in value.setdefault("plugins", []) if row["id"]=="vgs.jarvis"), None)
if row is None:
    row={"id":"vgs.jarvis"}; value["plugins"].append(row)
row["home"]=sys.argv[2]
print(json.dumps(value))
PYASKHOME
}

jarvis_asks_restore() {
  cp -- "$jarvis_asks_lease_before" "$sandbox/jarvis-world/lease.sh"
  rm -f -- "$sandbox/jarvis-world/owner-asks-bootstrap.sh" "$jarvis_asks_handoff"
}

jarvis_asks_control() { # FIXTURE_VERB [ARGS...]
  "$node_bin" "$jarvis_asks_home/.agents/skills/jarvis/scripts/jarvis-session" "$1" "$jarvis_asks_home" "${@:2}"
}

jarvis_asks_read() { # FIELD [ROW_ID]
  ipc smoke jarvisProcess | py_reply '
import json,sys
v=json.load(sys.stdin).get("status", {}).get("ownerAsks")
field=sys.argv[1]
if not isinstance(v,dict): print("missing")
elif field=="kind": print(v.get("kind", "missing"))
elif v.get("kind")!="ready": print(v.get("kind", "missing"))
elif field=="counts": print(json.dumps([v.get("activeCount"),v.get("snoozedCount")]))
elif field=="row":
    row=next((r for r in v.get("active",[])+v.get("snoozed",[]) if r.get("id")==sys.argv[2]),None)
    print("absent" if row is None else row.get("state", "missing"))
elif field=="active": print(json.dumps([r.get("id") for r in v.get("active",[])]))
elif field=="snoozed": print(json.dumps([r.get("id") for r in v.get("snoozed",[])]))
else: print(json.dumps(v.get(field)))
' "$@"
}

jarvis_asks_ready() {
  expect_poll "the console reads canonical asks from the package" ready jarvis_asks_read kind
  # The ready snapshot follows bootstrap. Controls and receipts must use
  # this exact live daemon world's Home, never the shell's separate copy.
  read -r jarvis_asks_home <"$jarvis_asks_handoff" || return 1
  [[ -f $jarvis_asks_home/.owner-asks-fixture.json ]] || return 1
}
jarvis_asks_refresh() { ipc vgs.jarvis invoke owner-asks-refresh ''; }
jarvis_asks_tab() { # Now|Needs you|History
  click_item window:Jarvis window vgs.jarvis QQuickTabButton "$1"
}
jarvis_asks_action() { # ROW_TITLE ACTION
  ipc smoke revealScopedText window vgs.jarvis MessageRow "$1" Button "$2" >/dev/null || return 1
  click_scoped_in window:Jarvis window vgs.jarvis MessageRow "$1" Button "$2"
}
jarvis_asks_badge() {
  ipc smoke itemValues "$(bar_key)" vgs.jarvis QQuickLoader objectName,active,item.text,item.displayedText | py_reply '
import json,sys
rows=[r for r in json.load(sys.stdin) if r.get("objectName")=="bar-item-count"]
if len(rows)!=1:
    print("count-loaders="+str(len(rows)))
elif not rows[0].get("active"):
    print("absent")
elif rows[0].get("item.text")!=rows[0].get("item.displayedText"):
    print("count-draw-mismatch")
else:
    print(rows[0].get("item.text"))
'
}
jarvis_asks_tab_badge() {
  ipc smoke itemValues window vgs.jarvis Tabs unreadCounts | py_reply 'import json,sys; rows=json.load(sys.stdin); print(rows[0]["unreadCounts"].get("Needs you", "absent") if len(rows)==1 else "tabs="+str(len(rows)))'
}
# The action ids the History task row titled GOAL offers, its own Open and
# Stop, read from the row itself: no selection stands between them.
jarvis_console_task_actions() { # GOAL
  ipc smoke readMatchingDescendant window vgs.jarvis MessageRow title "$1" actions | py_reply 'import json,sys; print(json.dumps([a["id"] for a in json.load(sys.stdin)]))'
}

jarvis_history_filter() { # All types|Conversations|Tasks|Problems
  local current
  current="$(ipc smoke readShownDescendant window vgs.jarvis ResultsFilter currentText | py_reply 'import json,sys; print(json.load(sys.stdin))')" || return 1
  click_in window:Jarvis window vgs.jarvis ResultsFilter "$current" || return 1
  expect_poll "the History filter opens" true ipc smoke readShownDescendant window vgs.jarvis ResultsFilter listOpen
  jarvis_console_list_click "$1" || return 1
  expect_poll "the History filter chooses $1" "\"$1\"" ipc smoke readShownDescendant window vgs.jarvis ResultsFilter currentText
}
# jarvis_console_list_click TEXT: one click on the open list's entry TEXT
# once it reports the pointer at two readings in a row at one box, as
# point_item settles. popupItemGeometry answers a popup of this toplevel in
# the Jarvis window's frame, which at_centre places with the window
# (settings.sh info_link_click). click_item's popup lookup adds no surface
# position (control_box), so on the console it aimed at window coordinates
# as screen ones: no entry was chosen and the open list kept the keyboard.
# The pointer moves one pixel apart each try, so each move is a motion.
jarvis_console_list_click() { # TEXT
  local rect="" seen="" x="" y="" held=0 i
  smoke_poll_tries 100
  for i in $(seq 1 "$smoke_poll_n"); do
    rect="$(ipc smoke popupItemGeometry window vgs.jarvis "" "" MenuItem "$1")" || return 1
    if [[ $rect != \[* ]]; then held=0; seen=""; sleep 0.1; continue; fi
    if [[ $rect != "$seen" ]]; then
      held=0; seen="$rect"
      read -r x y < <(at_centre window:Jarvis "$rect") || return 1
    fi
    hover "$((x + i % 2))" "$y" || return 1
    if [[ $(ipc smoke popupItemHovered window vgs.jarvis "" "" MenuItem "$1") == true ]]; then held=$((held + 1)); else held=0; fi
    if (( held >= 2 )) && [[ $(ipc smoke popupItemGeometry window vgs.jarvis "" "" MenuItem "$1") == "$seen" ]]; then click "$((x + i % 2))" "$y"; return; fi
    sleep 0.1
  done
  echo "jarvis_console_list_click: no hovered entry $1: $rect" >&2
  return 1
}

jarvis_asks_picker_open() { ipc smoke readShownDescendant window vgs.jarvis DateField pickerOpen; }
jarvis_asks_editor() { ipc smoke readInstance window vgs.jarvis editingAction; }
jarvis_asks_editing() { ipc smoke readInstance window vgs.jarvis editingAsk | py_reply 'import json,sys; print("closed" if json.load(sys.stdin) is None else "open")'; }
jarvis_asks_button_focus() { # LABEL
  ipc smoke itemValues window vgs.jarvis Button text,activeFocus | py_reply 'import json,sys; print(str(any(r.get("text")==sys.argv[1] and r.get("activeFocus") for r in json.load(sys.stdin))).lower())' "$1"
}
jarvis_asks_button_reason() { # LABEL
  ipc smoke itemValues window vgs.jarvis Button text,disabledReason | py_reply 'import json,sys; rows=[r for r in json.load(sys.stdin) if r.get("text")==sys.argv[1]]; print(json.dumps(rows[0].get("disabledReason")) if len(rows)==1 else "buttons="+str(len(rows)))' "$1"
}

# Cover real dialogs as well as the independent package-boundary checks.
# The Later path chooses with the existing calendar and time controls; it
# never types a command or requires the date library's storage format.
jarvis_asks_ui_path() {
  jarvis_asks_tab "Needs you" || fail "opening Needs you failed"
  expect_poll "Needs you shares the canonical bar count" 3 jarvis_asks_badge
  expect_poll "Needs you shares the canonical tab count" 3 jarvis_asks_tab_badge
  jarvis_asks_action "Choose the voice for tomorrow's briefing" Reply || fail "opening the original ask's Reply failed"
  expect_poll "Reply gives its editor keyboard focus" true ipc smoke activeFocusWithin window vgs.jarvis TextArea
  expect "an empty reply explains why Send reply is unavailable" '"Write your reply first."' jarvis_asks_button_reason "Send reply"
  type_keys -k Tab || fail "tabbing from the empty reply failed"
  expect_poll "the disabled Send reply remains reachable" true jarvis_asks_button_focus "Send reply"
  type_keys -k Tab || fail "tabbing to Reply Cancel failed"
  expect_poll "Reply Cancel is reachable" true jarvis_asks_button_focus Cancel
  type_keys -k Tab || fail "cycling Reply back to its editor failed"
  expect_poll "Reply cycles back to its editor" true ipc smoke activeFocusWithin window vgs.jarvis TextArea
  type_keys "Answer from Needs you" || fail "typing the original-thread reply failed"
  expect_poll "a typed reply enables Send reply" '""' jarvis_asks_button_reason "Send reply"
  type_keys -k Tab -k Return || fail "sending the original-thread reply by keyboard failed"
  expect_poll "Reply closes only after its canonical answer" closed jarvis_asks_editing
  expect_poll "Reply reaches the package once" 1 jarvis_asks_calls reply count
  expect "Reply preserves its original-thread text through stdin" '"Answer from Needs you"' jarvis_asks_call_text reply
  jarvis_asks_action "Review the console design" Done || fail "claiming Done for the tracker ask failed"
  expect_poll "Done shows canonical checking" checking jarvis_asks_read row tracker-design
  expect_poll "Done keeps the canonical unread count until verified" 3 jarvis_asks_badge
  jarvis_asks_action "Approve the update on px13" Later || fail "opening the fleet ask's Later failed"
  expect_poll "Later opens its date editor" '"later"' jarvis_asks_editor
  expect_poll "Later focuses its date field" true ipc smoke activeFocusWithin window vgs.jarvis DateField
  type_keys -k Down || fail "opening Later's calendar by keyboard failed"
  expect_poll "Later's calendar opens" true jarvis_asks_picker_open
  type_keys -k Right -k Return || fail "choosing a future calendar day failed"
  expect_poll "choosing a day closes the calendar" false jarvis_asks_picker_open
  expect_poll "the calendar returns focus to the date field" true ipc smoke activeFocusWithin window vgs.jarvis DateField
  type_keys -k Tab -k Down || fail "choosing Later's return time failed"
  expect_poll "Later chooses a readable return time" '"Noon"' ipc smoke readShownDescendant window vgs.jarvis ResultsFilter currentText
  type_keys -k Tab || fail "reaching Snooze from the return time failed"
  expect_poll "Later's Snooze button is reachable" true jarvis_asks_button_focus Snooze
  type_keys -k Return || fail "snoozing by keyboard failed"
  expect_poll "Snooze closes only after its canonical answer" closed jarvis_asks_editing
  expect_poll "Later publishes its snoozed row" snoozed jarvis_asks_read row fleet-update
  expect_poll "Later updates the canonical counts" '[2, 1]' jarvis_asks_read counts
  expect_poll "the bar badge excludes the snoozed ask" 2 jarvis_asks_badge
  expect_poll "the tab badge excludes the snoozed ask" 2 jarvis_asks_tab_badge
  click_item window:Jarvis window vgs.jarvis RowAction "Snoozed (1)" || fail "expanding the canonical snoozed section failed"
  expect_poll "the snoozed section expands" true ipc smoke readInstance window vgs.jarvis snoozedExpanded
  expect_poll "the visible snoozed row uses the canonical state" '"Snoozed"' ipc smoke readMatchingDescendant window vgs.jarvis MessageRow title "Approve the update on px13" stateText
  jarvis_asks_control --seed 3
  expect "the UI path restores its three asks" ok jarvis_asks_refresh
  jarvis_asks_ready
  jarvis_asks_tab Now || fail "returning to Now after asks failed"
}
jarvis_asks_calls() { # VERB FIELD
  python3 - "$jarvis_asks_home/.owner-asks-fixture-calls.jsonl" "$1" "$2" <<'PYASKCALLS'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
rows=[json.loads(line) for line in p.read_text().splitlines()] if p.exists() else []
rows=[row for row in rows if len(row.get("argv", []))>1 and row["argv"][1]==sys.argv[2]]
if sys.argv[3]=="count": print(len(rows))
elif not rows: print("absent")
else:
    row=rows[-1]
    print(json.dumps(row.get("input")))
PYASKCALLS
}

# Exercise the actual daemon/package boundary. These requests deliberately
# use the public IPC, not a fixture-only method on the production view.
jarvis_asks_request() { # ACTION ID TEXT [UNTIL]
  local request
  request="$(ipc smoke jarvisProcess | py_reply '
import json,sys,uuid
v=json.load(sys.stdin)["status"]["ownerAsks"]
row=next(r for r in v["active"]+v["snoozed"] if r["id"]==sys.argv[2])
print(json.dumps({"action":sys.argv[1],"id":row["id"],"requestId":"smoke-"+str(uuid.uuid4()),
    "expectedRevision":row["revision"],"text":sys.argv[3],"until":sys.argv[4] if len(sys.argv)>4 else None}))
' "$@")" || return 1
  # expect executes its command in a subshell; retain request identity in
  # the private fixture Home rather than relying on a shell assignment.
  printf '%s\n' "$request" >"$jarvis_asks_home/.owner-asks-smoke-request.json" || return 1
  ipc vgs.jarvis invoke owner-ask-action "$request"
}

jarvis_asks_answer() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
from pathlib import Path
v=json.load(sys.stdin).get("status",{}).get("ownerAskAnswer")
request=json.loads(Path(sys.argv[1]).read_text())
answer="waiting"
if isinstance(v,dict) and isinstance(v.get("request"),dict) and v["request"].get("requestId")==request["requestId"]:
    if v.get("kind") in ("unknown","not-sent"): answer=v["kind"]
    elif v.get("kind")=="answered" and isinstance(v.get("result"),dict) and v["result"].get("requestId")==request["requestId"]:
        answer=v["result"].get("kind","waiting")
print(answer)
' "$jarvis_asks_home/.owner-asks-smoke-request.json"
}

jarvis_asks_page() { # VIEW next|first
  local request
  request="$(ipc smoke jarvisProcess | py_reply '
import json,sys
v=json.load(sys.stdin)["status"]["ownerAsks"]
view=sys.argv[1]
print(json.dumps({"view":view,"cursor":v[view+"NextCursor"] if sys.argv[2]=="next" else None,"expectedRevision":v["revision"]}))
' "$@")" || return 1
  ipc vgs.jarvis invoke owner-asks-page "$request"
}

jarvis_asks_tomorrow() {
  python3 -c 'from datetime import datetime,timedelta,timezone; print((datetime.now(timezone.utc)+timedelta(days=1)).isoformat(timespec="seconds").replace("+00:00","Z"))'
}

jarvis_asks_states() {
  expect "Done sends evidence through the package boundary" ok jarvis_asks_request done tracker-design "The design has been checked."
  expect_poll "the package accepts Done for this exact request" accepted jarvis_asks_answer
  expect_poll "Done stays checking until the package verifies it" checking jarvis_asks_read row tracker-design
  expect_poll "checking retains all three active asks" '[3, 0]' jarvis_asks_read counts
  local until
  until="$(jarvis_asks_tomorrow)" || return 1
  expect "Later sends the chosen date through the package boundary" ok jarvis_asks_request later fleet-update "" "$until"
  expect_poll "the package accepts Later for this exact request" accepted jarvis_asks_answer
  expect_poll "Later moves the ask into the canonical snoozed page" snoozed jarvis_asks_read row fleet-update
  expect_poll "the canonical count excludes the snoozed ask" '[2, 1]' jarvis_asks_read counts
}

jarvis_asks_contract_check() {
  jarvis_asks_ready
  expect_poll "the initial count comes from the package" '[3, 0]' jarvis_asks_read counts
  expect "Reply sends owner text through the package boundary" ok jarvis_asks_request reply jarvis-briefing $'Use the existing voice.\nKeep this reply in the briefing thread.'
  expect_poll "the package accepts Reply for this exact request" accepted jarvis_asks_answer
  jarvis_asks_ready
  expect "the package receives reply text through JSON stdin" $'"Use the existing voice.\\nKeep this reply in the briefing thread."' jarvis_asks_call_text reply
  jarvis_asks_states
  jarvis_asks_control --verify tracker-design
  expect "a package verification refresh is requested" ok jarvis_asks_refresh
  expect_poll "the package alone closes the verified ask" absent jarvis_asks_read row tracker-design
  expect_poll "verification changes the canonical active count" '[1, 1]' jarvis_asks_read counts

  jarvis_asks_control --seed 7
  expect "paging starts with a canonical refresh" ok jarvis_asks_refresh
  expect_poll "a backlog larger than one page stays available" '[7, 0]' jarvis_asks_read counts
  expect_poll "the first bounded page contains three asks" '["jarvis-briefing", "tracker-design", "fleet-update"]' jarvis_asks_read active
  expect "the next bounded page is requested" ok jarvis_asks_page active next
  expect_poll "the next page replaces the visible rows" '["ask-3", "ask-4", "ask-5"]' jarvis_asks_read active
  expect "paging preserves the full canonical count" '[7, 0]' jarvis_asks_read counts
  expect "the first bounded page is requested again" ok jarvis_asks_page active first
  expect_poll "returning to first restores its rows" '["jarvis-briefing", "tracker-design", "fleet-update"]' jarvis_asks_read active

  # This malformed source control is distinct from an empty successful list.
  # It returns exit 0 and therefore plants no process-error excuse.
  jarvis_asks_control --mode malformed
  expect "a malformed package response is refreshed" ok jarvis_asks_refresh
  expect_poll "an unreadable source is unavailable rather than zero asks" unavailable jarvis_asks_read kind
  jarvis_asks_control --seed 3
  expect "the capture fixture restores its original three asks" ok jarvis_asks_refresh
  jarvis_asks_ready
}

jarvis_asks_call_text() { # VERB
  jarvis_asks_calls "$1" input | python3 -c 'import json,sys; value=json.load(sys.stdin); print(json.dumps(value["text"]))'
}
