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
# (rows/notifications.sh) reads its top under the header and inside the
# list's clip. Its control is a Panel.qml copy that reveals the selected
# card only in the refresh, before the list has taken its cards' height,
# which scrolled the first card under the header on every open after a
# first, uncounted one (long_inbox_warm) in the sandbox on 2026-10-02, at
# scale 1 and at scale 2; each control asserts that every counted open
# read its defect. rows/hidpi.sh
# reads the same opens at scale 2. The same opens hold on the first
# monitor held at a scale that leaves a room shorter than the panel's
# panelMaxHeight, where the list takes what is under the header; their
# control is a Panel.qml copy whose list keeps its whole height, which ran
# the list past the panel's bottom (clipped=list) on all eight opens in the
# sandbox on 2026-10-02.
# No latency is measured; each reading polls every 200 ms for up to 5 s.
# A press that reaches nothing changes nothing to poll for, so the
# controls read after a native key marker on the same virtual keyboard.
# inputs: shell/plugins/vgs.notifications/* shell/Hosts/SummonLayer.qml scripts/smoke/toplevel/* scripts/smoke/rows/notifications.sh scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail

nk_hypr_lua="$home/.config/hypr/hyprland.lua"
read -r mon_w mon_h < <(hypr -j monitors | py_reply 'import json,sys; m=json.load(sys.stdin)[0]; print(m["width"], m["height"])')
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
# long_inbox_cut TOGGLE...: eight opens of the long inbox by the command
# TOGGLE, which also closes it. Each open is read once the panel lists the
# newest row and has drawn, with panel_fit until it reads `fits` or a
# reading began long_inbox_settle_s or more after the first: a first card
# scrolled under the header stays there, so a reading that stays off fits
# for the settle is the cut. The settle is counted on the clock, since one
# reading of forty cards takes longer than a poll's sleep. Prints the one
# reading every open gave, such as `fits` or
# `cut-top=card under-header=card`, `mixed` when the opens differ, or
# `open=<n> <failure>` at the first open the instrument could not read:
# `unlisted` when the panel never listed the newest row, `unread` when
# panel_fit read no header, list or card, `not-drawn`, or a toggle that
# failed. Each open's reading goes to $sandbox/long-inbox.txt, which
# long_inbox_readings prints.
long_inbox_settle_s=1
long_inbox_cut() {
  local n reading listed opened began readings=() first
  rm -f -- "${sandbox:?}/long-inbox.txt"
  for n in 1 2 3 4 5 6 7 8; do
    "$@" >/dev/null || { echo "open=$n toggle-failed"; return; }
    listed=False
    for _ in $(seq 1 25); do
      listed="$(has_row panel "Long newest")" || listed=False
      [[ $listed == True ]] && break
      sleep 0.2
    done
    [[ $listed == True ]] || { echo "open=$n unlisted"; return; }
    summon_drawn panel vgs.notifications || { echo "open=$n not-drawn"; return; }
    reading=""
    opened="${EPOCHREALTIME/[.,]/}"
    while :; do
      began="${EPOCHREALTIME/[.,]/}"
      reading="$(panel_fit)" || reading="unread"
      [[ $reading == fits ]] && break
      (( began - opened >= long_inbox_settle_s * 1000000 )) && break
      sleep 0.2
    done
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
  click 40 "$((mon_h - 40))" || fail "the press on the desktop beside the inbox failed"
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

expect "the long inbox's toasts leave the screen" 0 long_inbox_rows
geometry expect "a long inbox opened by the key eight times shows its first card whole each time" fits long_inbox_cut nk_press
ok "long inbox readings: $(long_inbox_readings)"
expect "disabling the notifications before the panel copy is allowed" ok ipc shell setPluginEnabled vgs.notifications false
expect_poll "the compositor lists no inbox shortcut before the panel copy" 0 note_shortcuts
nk_panel="$repo/shell/plugins/vgs.notifications/Panel.qml"
cp -- "$nk_panel" "$sandbox/Panel.qml.keys-kept"
python3 - "$nk_panel" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
needle = "onViewHeightChanged: reveal(root.currentIndex)"
assert text.count(needle) == 1, "the reveal at the list's height occurs once"
open(path, "w").write(text.replace(needle, "onViewHeightChanged: {}"))
PY
rescan "a rescan reads the refresh-only reveal panel copy"
expect "enabling the notifications beside the panel copy is allowed" ok ipc shell setPluginEnabled vgs.notifications true
expect_poll "the service is built beside the panel copy" True record_exists vgs.notifications
expect_poll "the inbox shortcut is listed beside the panel copy" 1 note_shortcuts
long_inbox_warm nk_press || fail "the refresh-only reveal copy's first open failed"
geometry expect "control: a panel that reveals only in the refresh scrolls the long inbox's first card under the header on every open" "cut-top=card under-header=card" long_inbox_cut nk_press
ok "control long inbox readings: $(long_inbox_readings)"
cp -- "$sandbox/Panel.qml.keys-kept" "$nk_panel"
rescan "a rescan restores the panel"
expect_poll "the service is built beside the restored panel" True record_exists vgs.notifications
notes dismiss-all >/dev/null # `none` once every toast's clock ran out
expect "clearing the long inbox's history is allowed" ok notes clear-history

# The short room: the first monitor held at its own mode and the scale
# from 2 to 4 that whole_scale_mode picks, the mode trimmed by under one
# logical pixel a side when no scale divides it into whole logical pixels.
# A running shell does not follow a scale change
# (docs/architecture/runtime-qml.md), so the shell starts again under the
# hold, and again at scale 1 after it.
nk_output="$(first_name)"
nk_room=""
if ! nk_base="$(unscaled_mode_of "$nk_output" 2>&1)"; then
  nk_room_error="the short room reads no own mode on ${nk_output:-unread}: $nk_base"
elif ! nk_room="$(whole_scale_mode "$nk_base")"; then
  nk_room_error="the short room finds no mode on ${nk_output:-unread}: $nk_room"
  nk_room=""
fi
if [[ -n $nk_room ]]; then
  read -r nk_mode nk_scale <<<"$nk_room"
  stop_shell || :
  hold_mode "the first monitor is held at $nk_mode, its own mode $nk_base, and scale $nk_scale for the short room" "$nk_output" "$nk_mode" "$nk_scale"
  start_shell "$repo" "$sandbox/notifications-keys-short.log" || fail "the shell starts under the short room's hold"
  expect_poll "the service is built in the short room" True record_exists vgs.notifications
  expect_poll "the inbox shortcut is listed in the short room" 1 note_shortcuts
  # True while the open panel is laid out shorter than its panelMaxHeight.
  room_caps() {
    local box max
    box="$(ipc smoke instanceGeometry panel vgs.notifications)" || return
    max="$(ipc smoke readInstance panel vgs.notifications panelMaxHeight)" || return
    python3 -c 'import json,sys; print(json.loads(sys.argv[1])[3] < float(sys.argv[2]))' "$box" "$max"
  }
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
needle = "            Layout.fillHeight: true\n            Layout.minimumHeight: 0\n            Layout.maximumHeight: listScroll.implicitHeight\n"
assert text.count(needle) == 1, "the list's room under the header occurs once"
open(path, "w").write(text.replace(needle, ""))
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
  stop_shell || :
  release_mode "the first monitor gets its own mode at scale 1 back after the short room" "$nk_output" "$nk_base"
  start_shell "$repo" "$sandbox/notifications-keys-restart.log" || fail "the shell starts again after the short room"
  expect_poll "the service is built after the short room" True record_exists vgs.notifications
  expect "the observer provides the notifications key ordering marker after the short room" ok ipc smoke holdMarkerStart
else
  fail "$nk_room_error"
fi

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
expect "the observer releases the notifications key ordering marker" ok ipc smoke holdMarkerStop
hypr_lua_restore notifications-keys || fail "the key rows put the harness hyprland.lua back"
expect "the nested instance reloads the harness hyprland.lua after the key rows" ok hypr reload config-only
