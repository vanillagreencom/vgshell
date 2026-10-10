# The notifications inbox shortcut pressed as keys. Super+N typed on the
# nested seat, five times in a row, alternates the inbox open, closed,
# open, closed, open; the same holds after a press on the desktop beside
# the open inbox closed it (SummonLayer's catcher) and after an Escape
# closed it. "Open" is the summon host's panel layer mapped and drawn at
# its size, "closed" no panel layer and no panel instance.
# Controls: with Hyprland's default `input:resolve_binds_by_sym`, false,
# wtype's keys reach no bind and a press leaves the inbox closed, which
# is how the same presses read on a live session with that default, so
# the row's presses are key presses a bind takes and not a dispatch; and
# a copy of the service whose shortcut summons where it should toggle
# leaves the inbox open on the second press.
# A long inbox, forty rows whose newest carries actions, opened by the
# key eight times, shows its first card whole each time: panel_fit
# (rows/notifications.sh) reads its top below the gutter under the header.
# rows/hidpi.sh reads the same opens at scale 2. The same
# opens hold on the first monitor at a scale that leaves a room shorter
# than the panel's
# panelMaxHeight, where the list takes what is under the header; their
# control is a Panel.qml copy whose list keeps its whole height, which runs
# the list past the panel's bottom (clipped=list) on all eight opens.
# One more open shows the list at the panel bottom at both scroll ends.
# A copy with a reserved bottom gap must fail the same reading.
# No latency is measured; each reading polls every 200 ms for up to 5 s.
# A press that reaches nothing changes nothing to poll for, so the
# controls read after a native key marker on the same virtual keyboard.
# inputs: shell/plugins/vgs.notifications/* shell/Hosts/SummonLayer.qml shell/Ui/layout/SurfaceHeight.qml scripts/smoke/toplevel/* scripts/smoke/rows/notifications.sh scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail

nk_hypr_lua="$home/.config/hypr/hyprland.lua"
nk_press() { type_keys -M logo -k n -m logo; }
nk_press_with_key_marker() { type_keys -M logo -k n -m logo -k F9; }
nk_key_marker_after() { # COUNT
  local now
  now="$(ipc smoke holdMarkerCount)" || return
  [[ $now =~ ^[0-9]+$ && $now -gt $1 ]] && echo marked || echo "$now"
}
nk_key_barrier() { # LABEL BEFORE
  expect_poll "$1" marked nk_key_marker_after "$2"
}
nk_client_marker_after() { # LOG BEFORE
  local now
  now="$(log_lines '^key [0-9]+ released$' "$1")" || return
  [[ $now =~ ^[0-9]+$ && $now -gt $2 ]] && echo marked || echo "$now"
}
# The inbox as the user sees it: open, closed, or the readings between.
inbox_shown() {
  local layers window
  layers="$(layer_count vgs:panel)" || return
  window="$(ipc smoke windowDrawn panel vgs.notifications)" || return
  case "$layers $window" in
    "1 drawn") echo open ;;
    "0 absent") echo closed ;;
    *) echo "between layers=$layers window=$window" ;;
  esac
}
nk_panel_outside_point() {
  local layer box
  layer="$(surface_box vgs:panel)" || return
  box="$(ipc smoke instanceGeometry panel vgs.notifications)" || return
  python3 - "$layer" "$box" <<'PY'
import json, sys
lx, ly, lw, lh = json.loads(sys.argv[1])
px, py, pw, ph = json.loads(sys.argv[2])
candidates = []
if px > lx:
    candidates.append(((lx + px) // 2, py + ph // 2))
if px + pw < lx + lw:
    candidates.append(((px + pw + lx + lw) // 2, py + ph // 2))
if py > ly:
    candidates.append((px + pw // 2, (ly + py) // 2))
if py + ph < ly + lh:
    candidates.append((px + pw // 2, (py + ph + ly + lh) // 2))
for x, y in candidates:
    x = int(max(lx, min(lx + lw - 1, int(x))))
    y = int(max(ly, min(ly + lh - 1, int(y))))
    if not (px <= x < px + pw and py <= y < py + ph):
        print(x, y)
        raise SystemExit(0)
print(f"no-outside panel={[px, py, pw, ph]} layer={[lx, ly, lw, lh]}", file=sys.stderr)
raise SystemExit(1)
PY
}
nk_click_outside_panel() {
  local x y
  read -r x y < <(nk_panel_outside_point) || return
  click "$x" "$y"
}
room_caps() {
  local box max
  box="$(ipc smoke instanceGeometry panel vgs.notifications)" || return
  max="$(ipc smoke readInstance panel vgs.notifications panelMaxHeight)" || return
  python3 -c 'import json,sys; print(json.loads(sys.argv[1])[3] < float(sys.argv[2]))' "$box" "$max"
}
nk_bottom_reserved() {
  hypr -j monitors | py_reply 'import json,sys; m=json.load(sys.stdin)[0]; print(m["reserved"][3])'
}
nk_bottom_reserved_at_least() {
  local got
  got="$(nk_bottom_reserved)" || return
  [[ $got =~ ^[0-9]+$ && $got -ge $1 ]] && echo True || echo "$got"
}
nk_short_room_reserve() { # PANEL_MAX_HEIGHT
  local size
  size="$(monitor_size)" || return
  python3 - "$1" "$size" <<'PY'
import sys
max_height = float(sys.argv[1])
width, height, top = [int(float(part)) for part in sys.argv[2].split()]
if max_height <= 1:
    raise SystemExit(1)
target = max(1, min(int(max_height) - 1, max(240, int(max_height * 0.55))))
print(max(1, height - top - target))
PY
}
nk_install_short_room_fixture() { # RESERVE
  local dir="$home/.config/vgshell/plugins/acme.notifications-short-room"
  rm -rf -- "$dir"
  mkdir -p -- "$dir"
  cat >"$dir/manifest.json" <<'JSON'
{ "schemaVersion": 1, "id": "acme.notifications-short-room", "name": "Notifications short room", "version": "0.1.0", "author": "acme", "description": "smoke fixture reserving room below a panel", "kinds": ["service"], "entryPoints": { "service": "Service.qml" } }
JSON
  cat >"$dir/Service.qml" <<QML
import QtQuick
import Quickshell
import Quickshell.Wayland

Item {
    id: root
    property var shell: null
    readonly property int reserve: $1

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { bottom: true; left: true; right: true }
            implicitHeight: root.reserve
            color: "transparent"
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: root.reserve
            mask: emptyMask
            WlrLayershell.namespace: "vgs:notifications-short-room"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Region { id: emptyMask }
        }
    }
}
QML
}
# The long inbox's forty rows: thirty-nine tall cards and, newest, one
# with actions, the card a selected inbox opens on. They are low, so their
# toasts leave the screen within NotificationLogic's LOW_LIFETIME, and the
# inbox opens on history alone, as the owner's did: while a toast shows,
# opening the panel settles its clock, and the refresh that follows comes
# after the list has its height and hides a cut (read in the sandbox on
# 2026-10-02: the first three opens with live toasts fit on the refresh-only
# copy, the later ones did not). Prints 0 once no toast shows, polled every
# 200 ms for up to 15 s, else the count still showing.
long_inbox_rows() {
  local n shown=""
  for n in $(seq 1 39); do
    notify smoke-app 0 "Long $n" "A body long enough to wrap onto a second line of the card, so the card is tall" '[]' '{"urgency": <byte 0>}' 0 >/dev/null
  done
  notify smoke-app 0 "Long newest" "Waiting for your input" '["default", "Show"]' '{"urgency": <byte 0>}' 0 >/dev/null
  for _ in $(seq 1 75); do
    shown="$(note_status onScreen)" || return
    [[ $shown == 0 ]] && break
    sleep 0.2
  done
  echo "$shown"
}
# long_inbox_shown: `shown` once the open panel lists the long inbox's
# newest row and has drawn, else `unlisted` or `not-drawn`.
long_inbox_shown() {
  local listed=False
  for _ in $(seq 1 25); do
    listed="$(has_row panel "Long newest")" || listed=False
    [[ $listed == True ]] && break
    sleep 0.2
  done
  [[ $listed == True ]] || { echo unlisted; return; }
  summon_drawn panel vgs.notifications || { echo not-drawn; return; }
  echo shown
}
# long_inbox_settled: panel_fit until it reads `fits` or a reading began
# long_inbox_settle_s or more after the first: a first card scrolled under
# the header stays there, so a reading that stays off fits for the settle
# is the cut. The settle is counted on the clock, since one reading of
# forty cards takes longer than a poll's sleep. Prints the last reading,
# `unread...` when panel_fit read no header, list or card.
long_inbox_settle_s=1
long_inbox_settled() {
  local reading opened began
  opened="${EPOCHREALTIME/[.,]/}"
  while :; do
    began="${EPOCHREALTIME/[.,]/}"
    reading="$(panel_fit)" || reading="unread"
    [[ $reading == fits ]] && break
    (( began - opened >= long_inbox_settle_s * 1000000 )) && break
    sleep 0.2
  done
  echo "$reading"
}
# long_inbox_cut TOGGLE...: eight opens of the long inbox by the command
# TOGGLE, which also closes it, each read with long_inbox_settled once
# long_inbox_shown. Prints the one reading every open gave, such as `fits`
# or `cut-top=card in-gutter=card under-header=card`, `mixed` when the opens differ, or
# `open=<n> <failure>` at the first open the instrument could not read:
# long_inbox_shown's failure, `unread`, or a toggle that failed. Each
# open's reading goes to $sandbox/long-inbox.txt, which long_inbox_readings
# prints.
long_inbox_cut() {
  local n reading shown readings=() first
  rm -f -- "${sandbox:?}/long-inbox.txt"
  for n in 1 2 3 4 5 6 7 8; do
    "$@" >/dev/null || { echo "open=$n toggle-failed"; return; }
    shown="$(long_inbox_shown)"
    [[ $shown == shown ]] || { echo "open=$n $shown"; return; }
    reading="$(long_inbox_settled)"
    [[ $reading == unread* ]] && { echo "open=$n unread"; return; }
    readings+=("$reading")
    "$@" >/dev/null || { echo "close=$n toggle-failed"; return; }
    for _ in $(seq 1 25); do [[ $(layer_count vgs:panel) == 0 ]] && break; sleep 0.2; done
  done
  for n in "${!readings[@]}"; do printf 'open=%d %s; ' "$((n + 1))" "${readings[n]}"; done >"$sandbox/long-inbox.txt"
  first="${readings[0]}"
  for reading in "${readings[@]}"; do
    [[ $reading == "$first" ]] || { echo mixed; return; }
  done
  echo "$first"
}
long_inbox_readings() { if [[ -f $sandbox/long-inbox.txt ]]; then cat -- "$sandbox/long-inbox.txt"; else echo "none read"; fi; }
# long_inbox_warm TOGGLE...: one open and close of the long inbox that no
# reading counts, before a control's eight. The first open after a service
# starts can meet that start's status publication, whose refresh comes
# after the list has its height and scrolls it back: on one run of four in
# the sandbox on 2026-10-02 the refresh-only copy's first open fit and its
# other seven were cut.
long_inbox_warm() {
  "$@" >/dev/null || return
  summon_drawn panel vgs.notifications || return
  "$@" >/dev/null || return
  for _ in $(seq 1 25); do [[ $(layer_count vgs:panel) == 0 ]] && return 0; sleep 0.2; done
  return 1
}
# One open, read at the list top and at the full scroll travel. The end
# reading checks the bottom without requiring the first card in view.
long_inbox_ends() {
  local shown top end view spot x y
  "$@" >/dev/null || { echo toggle-failed; return; }
  shown="$(long_inbox_shown)"
  [[ $shown == shown ]] || { echo "$shown"; return; }
  top="$(long_inbox_settled)"
  for _ in 1 2 3 4 5 6 7 8; do
    view="$(view_at_rest panel vgs.notifications "Long newest")" || view=unread
    [[ $view == \{* ]] || { echo "view=$view"; return; }
    spot="$(python3 -c 'import json,sys; v=json.loads(sys.argv[1]); print("end" if v["contentY"] > 0 and v["contentY"] >= v["contentHeight"] - v["height"] - 0.5 else json.dumps(v["box"]))' "$view")" || spot=unread
    [[ $spot == end ]] && break
    read -r x y < <(panel_point "$spot" - -) || { echo "view=$view"; return; }
    wheel "$x" "$y" 10 || { echo wheel-failed; return; }
  done
  [[ $spot == end ]] || { echo "not-at-end $view"; return; }
  end="$(panel_fit bottom)"
  read -r x y < <(nk_panel_outside_point) && hover "$x" "$y"
  "$@" >/dev/null || { echo close-toggle-failed; return; }
  for _ in $(seq 1 25); do [[ $(layer_count vgs:panel) == 0 ]] && break; sleep 0.2; done
  echo "top=$top end=$end"
}
# PRESSES LABEL: five presses from a closed inbox, each read before the next.
nk_presses() {
  local want=open n
  for n in 1 2 3 4 5; do
    nk_press || fail "$1: press $n failed"
    expect_poll "$1: press $n leaves the inbox $want" "$want" inbox_shown
    if [[ $want == open ]]; then want=closed; else want=open; fi
  done
}

hypr_lua_save notifications-keys
printf '%s\n' 'hl.bind("code:67", hl.dsp.global("smoke:hold-marker"), { description = "smoke:hold-marker", ignore_mods = true })' >>"$nk_hypr_lua"
printf '%s\n' 'hl.bind("code:75", hl.dsp.global("smoke:hold-marker"), { description = "smoke:hold-marker", ignore_mods = true })' >>"$nk_hypr_lua"
printf '%s\n' 'hl.bind("F9", hl.dsp.global("smoke:hold-marker"), { description = "smoke:hold-marker", ignore_mods = true })' >>"$nk_hypr_lua"
expect "the notifications key row registers its ordering marker" ok hypr reload config-only
expect "the observer provides the notifications key ordering marker" ok ipc smoke holdMarkerStart
expect "enabling the notifications for the key rows is allowed" ok ipc shell setPluginEnabled vgs.notifications true
expect_poll "the notification service for the key rows is built" True record_exists vgs.notifications
expect_poll "the compositor lists the inbox shortcut for the key rows" 1 note_shortcuts
notify smoke-app 0 "Key rows" "" '[]' '{"urgency": <byte 0>}' 0 >/dev/null
expect_poll "the key rows' notification is live" True has_row live "Key rows"
expect "the inbox starts closed" closed inbox_shown

# Control: Hyprland's default bind resolution, the live session's.
nk_marker_log="$sandbox/notifications-keys-marker.log"
if open_toplevel "$nk_marker_log" smoke.notifications-keys-marker "Notifications key marker"; then
  nk_marker_pid="$toplevel_pid"
  expect_poll "the notifications key marker client has keyboard focus" '["smoke.notifications-keys-marker", "Notifications key marker"]' active_window
  nk_marker_before="$(log_lines '^key [0-9]+ released$' "$nk_marker_log")" || { fail "control default resolution: the marker log is unreadable"; nk_marker_before=0; }
  nk_press_with_key_marker || fail "control default resolution: the press and marker failed"
  expect_poll "control default resolution: the marker key is processed after Super+N" marked nk_client_marker_after "$nk_marker_log" "$nk_marker_before"
  expect "control: with the default bind resolution a typed Super+N leaves the inbox closed" closed inbox_shown
  close_toplevel "$nk_marker_pid" "the notifications key marker exits"
else
  fail "the notifications key marker client maps"
fi

printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = true } })' >>"$nk_hypr_lua"
expect "the nested instance reloads with binds resolved by symbol" ok hypr reload config-only

nk_presses "from closed"
if summon_drawn panel vgs.notifications; then
  nk_click_outside_panel || fail "the press on the desktop beside the inbox failed"
else
  fail "the inbox before the desktop press never drew"
fi
expect_poll "a press on the desktop closes the inbox" closed inbox_shown
nk_presses "after a desktop press"
type_keys -k Escape || fail "sending Escape to the inbox failed"
expect_poll "Escape closes the inbox" closed inbox_shown
nk_presses "after Escape"
type_keys -k Escape || fail "sending the last Escape to the inbox failed"
expect_poll "the last Escape closes the inbox" closed inbox_shown

# The panel lists every kept notification, so the history is emptied
# first and the long inbox lists its forty cards alone.
notes dismiss-all >/dev/null # `none` once every toast's clock ran out
expect_poll "no toast shows before the long inbox" 0 note_status onScreen
expect "clearing the history before the long inbox is allowed" ok notes clear-history
expect_poll "the history is empty before the long inbox" 0 note_status history
expect "the long inbox's toasts leave the screen" 0 long_inbox_rows
expect_poll "the long inbox holds its forty cards alone" 40 note_status history
geometry expect "a long inbox opened by the key eight times shows its first card whole each time" fits long_inbox_cut nk_press
ok "long inbox readings: $(long_inbox_readings)"
geometry expect "the long inbox list reaches the panel bottom at both scroll ends" "top=fits end=fits" long_inbox_ends nk_press
nk_panel="$repo/shell/plugins/vgs.notifications/Panel.qml"
# Control: a real list with a reserved bottom gap fails both scroll ends.
expect "disabling notifications before the bottom-gap copy is allowed" ok ipc shell setPluginEnabled vgs.notifications false
expect_poll "the bottom-gap copy has no inbox shortcut yet" 0 note_shortcuts
cp -- "$nk_panel" "$sandbox/Panel.qml.keys-kept"
python3 - "$nk_panel" <<'PY_BOTTOM_GAP'
from pathlib import Path
import sys
p=Path(sys.argv[1]); text=p.read_text()
needle="            anchors.fill: parent\n"
assert text.count(needle)==1
replacement="            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom; bottomMargin: Math.max(root.look.header.gap, column.stickyGap) }\n"
p.write_text(text.replace(needle,replacement))
PY_BOTTOM_GAP
rescan "a rescan reads the bottom-gap copy"
expect "enabling notifications with the bottom-gap copy is allowed" ok ipc shell setPluginEnabled vgs.notifications true
expect_poll "the bottom-gap service is built" True record_exists vgs.notifications
geometry expect "control: a real reserved bottom gap fails at both ends" "top=bottom-gap=list end=bottom-gap=list" long_inbox_ends nk_press
cp -- "$sandbox/Panel.qml.keys-kept" "$nk_panel"
rescan "a rescan restores the row-free panel"
expect_poll "the restored panel service is built" True record_exists vgs.notifications
notes dismiss-all >/dev/null # `none` once every toast's clock ran out
expect "clearing the long inbox's history is allowed" ok notes clear-history

# The short room: a row-owned fixture reserves the screen bottom, and the
# open panel reads shorter than its panelMaxHeight. The reserve is computed
# from the current monitor and the panel's own maximum height, so every
# monitor leaves a room below that maximum without a scale or mode divisor.
nk_press || fail "the short-room measurement opens the inbox"
expect_poll "the short-room measurement maps the inbox" open inbox_shown
nk_panel_max="$(ipc smoke readInstance panel vgs.notifications panelMaxHeight)" || { fail "the short-room panel maximum is unreadable"; nk_panel_max=0; }
nk_press || fail "the short-room measurement closes the inbox"
expect_poll "the short-room measurement leaves the inbox closed" closed inbox_shown
nk_short_reserved_before="$(nk_bottom_reserved)" || { fail "the short-room starting bottom reserve is unreadable"; nk_short_reserved_before=0; }
nk_short_reserve="$(nk_short_room_reserve "$nk_panel_max")" || { fail "the short-room reserve could not be derived"; nk_short_reserve=1; }
nk_install_short_room_fixture "$nk_short_reserve" || fail "the short-room fixture is written"
rescan "a rescan discovers the short-room fixture"
expect_poll "the short-room fixture is known" True plugin_known acme.notifications-short-room
expect "enabling the short-room fixture is allowed" ok ipc shell setPluginEnabled acme.notifications-short-room true
expect_poll "the short-room fixture reserves bottom space it owns" True nk_bottom_reserved_at_least "$((nk_short_reserved_before + nk_short_reserve))"
expect "the short room's long inbox toasts leave the screen" 0 long_inbox_rows
nk_press || fail "the short room's open press failed"
expect_poll "the short room lays the inbox out shorter than its panelMaxHeight" True room_caps
nk_press || fail "the short room's close press failed"
expect_poll "the short room's inbox closes" closed inbox_shown
geometry expect "a long inbox opened by the key eight times in a short room shows its first card whole each time" fits long_inbox_cut nk_press
ok "short room long inbox readings: $(long_inbox_readings)"
expect "disabling the notifications before the whole-height list copy is allowed" ok ipc shell setPluginEnabled vgs.notifications false
expect_poll "the compositor lists no inbox shortcut before the whole-height list copy" 0 note_shortcuts
cp -- "$nk_panel" "$sandbox/Panel.qml.keys-kept"
python3 - "$nk_panel" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
needle = "        height: Math.max(0, Math.min(listScroll.implicitHeight, root.height - y))\n"
assert text.count(needle) == 1, "the list's room under the header occurs once"
open(path, "w").write(text.replace(needle, "        height: listScroll.implicitHeight\n"))
PY
rescan "a rescan reads the whole-height list copy"
expect "enabling the notifications beside the whole-height list copy is allowed" ok ipc shell setPluginEnabled vgs.notifications true
expect_poll "the service is built beside the whole-height list copy" True record_exists vgs.notifications
expect_poll "the inbox shortcut is listed beside the whole-height list copy" 1 note_shortcuts
long_inbox_warm nk_press || fail "the whole-height list copy's first open failed"
geometry expect "control: a panel whose list keeps its whole height runs a long inbox past the short room's panel on every open" "clipped=list" long_inbox_cut nk_press
ok "control short room readings: $(long_inbox_readings)"
cp -- "$sandbox/Panel.qml.keys-kept" "$nk_panel"
rescan "a rescan restores the panel after the short room"
notes dismiss-all >/dev/null # `none` once every toast's clock ran out
expect "clearing the short room's history is allowed" ok notes clear-history
expect "disabling the short-room fixture is allowed" ok ipc shell setPluginEnabled acme.notifications-short-room false
expect_poll "the short-room fixture releases its bottom reservation" "$nk_short_reserved_before" nk_bottom_reserved
rm -rf -- "$home/.config/vgshell/plugins/acme.notifications-short-room"
rescan "a rescan removes the short-room fixture"
expect_poll "the short-room fixture is gone" False plugin_known acme.notifications-short-room

# Control: a service whose shortcut summons the open inbox again. The
# plugin goes off before the copy is planted and on after, so the shortcut
# the compositor lists is the copy's and no press lands between the two.
expect "disabling the notifications before the summon-only copy is allowed" ok ipc shell setPluginEnabled vgs.notifications false
expect_poll "the compositor lists no inbox shortcut before the copy" 0 note_shortcuts
nk_service="$repo/shell/plugins/vgs.notifications/Service.qml"
cp -- "$nk_service" "$sandbox/Service.qml.keys-kept"
python3 - "$nk_service" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
needle = "if (panelOpen) return closePanel();"
assert text.count(needle) == 1, "the shortcut's close branch occurs once"
open(path, "w").write(text.replace(needle, "if (false) return closePanel();"))
PY
rescan "a rescan reads the summon-only service copy"
expect "enabling the summon-only service copy is allowed" ok ipc shell setPluginEnabled vgs.notifications true
expect_poll "the summon-only service copy is built" True record_exists vgs.notifications
expect_poll "the summon-only copy's shortcut is listed" 1 note_shortcuts
nk_press || fail "control summon-only: the first press failed"
expect_poll "control summon-only: the first press opens the inbox" open inbox_shown
nk_marker_before="$(ipc smoke holdMarkerCount)" || { fail "control summon-only: the marker count is unreadable before the second Super+N"; nk_marker_before=0; }
nk_press_with_key_marker || fail "control summon-only: the second press and marker failed"
nk_key_barrier "control summon-only: the marker key is processed after the second Super+N" "$nk_marker_before"
expect_poll "control: the summon-only copy leaves the inbox open on the second press" open inbox_shown
type_keys -k Escape || fail "control summon-only: Escape failed"
expect_poll "control summon-only: Escape closes the inbox" closed inbox_shown
expect "disabling the summon-only service copy is allowed" ok ipc shell setPluginEnabled vgs.notifications false
expect_poll "the summon-only service copy is gone" False record_exists vgs.notifications
cp -- "$sandbox/Service.qml.keys-kept" "$nk_service"
rescan "a rescan restores the service"
# A service can summon the same live panel again. Its selected row stays,
# but action preview is keyboard state and must restart with no action ring.
nk_action_index() { ipc smoke readInstance panel vgs.notifications actionIndex; }
nk_focus_reopen() {
  expect "the focus fixture opens the inbox" ok notes panel
  expect_poll "the focus fixture inbox maps" open inbox_shown
  expect_poll "the opened inbox selects no action" -1 nk_action_index
  type_keys -k Right || fail "Right reaches the inbox action fixture"
  expect_poll "Right selects the first inbox action" 0 nk_action_index
  expect "the same inbox is summoned again" ok notes panel
}
expect "enabling notifications for the reopen focus proof is allowed" ok ipc shell setPluginEnabled vgs.notifications true
expect_poll "the reopen focus service is built" True record_exists vgs.notifications
notes dismiss-all >/dev/null
expect "clearing history before the reopen focus proof is allowed" ok notes clear-history
notify smoke-app 0 "Focus reopen" "Choose an action" '["default", "Open", "reply", "Reply"]' '{}' 0 >/dev/null
expect_poll "the reopen focus notification is live" True has_row live "Focus reopen"
nk_focus_reopen
expect_poll "the same-panel reopen clears its action preview" -1 nk_action_index
type_keys -k Right || fail "Right reaches the reopened inbox"
expect_poll "keyboard action selection still works after reopen" 0 nk_action_index
type_keys -k Escape || fail "Escape closes the reopen focus proof"
expect_poll "the reopen focus inbox closes" closed inbox_shown
expect "disabling notifications for the retained-action control is allowed" ok ipc shell setPluginEnabled vgs.notifications false
cp -- "$nk_panel" "$sandbox/Panel.qml.focus-kept"
python3 - "$nk_panel" <<'PYCONTROL'
import sys
path = sys.argv[1]
text = open(path).read()
needle = 'opened = true;\n        actionIndex = -1;'
assert text.count(needle) == 1, "the open owner resets its action preview once"
open(path, "w").write(text.replace(needle, 'opened = true;'))
PYCONTROL
rescan "a rescan reads the retained-action control"
expect "enabling the retained-action control is allowed" ok ipc shell setPluginEnabled vgs.notifications true
expect_poll "the retained-action service is built" True record_exists vgs.notifications
nk_focus_reopen
nk_reopen_no_preview() { expect "the same-panel reopen has no action preview" -1 nk_action_index; }
nk_reopen_preview_control() { (failures=0 behaviour_failures=0; nk_reopen_no_preview >"$sandbox/notifications-reopen-focus-control.log"; echo "$failures"); }
expect "control: retaining the prior action fails the same reopen assertion" 1 nk_reopen_preview_control
sed 's/^/  CONTROL  /' "$sandbox/notifications-reopen-focus-control.log"
type_keys -k Escape || fail "Escape closes the retained-action control"
expect "disabling the retained-action control is allowed" ok ipc shell setPluginEnabled vgs.notifications false
cp -- "$sandbox/Panel.qml.focus-kept" "$nk_panel"
rescan "a rescan restores the shipped reopen focus owner"
expect "the observer releases the notifications key ordering marker" ok ipc smoke holdMarkerStop
hypr_lua_restore notifications-keys || fail "the key rows put the harness hyprland.lua back"
expect "the nested instance reloads the harness hyprland.lua after the key rows" ok hypr reload config-only
