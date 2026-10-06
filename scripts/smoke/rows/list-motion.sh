# The list motion of qs.Ui, ListCursor, in the Settings plugin list and the
# launcher: under a slowed motion scale the cursor travels between rows, a
# reading caught between where it stood and where it rests, which is the
# contrast that proves the reader sees motion; at motion.scale 0 it lands at
# once, with no reading between; at the shipped motion a hover moves the
# Settings list's plate on its first frame and rests it within a ceiling
# the old travel misses, and the launcher's selection goes back to the
# keys' row when the pointer leaves the list. The rows run with the launcher disabled as the rows
# before left it, and leave it so, with the default theme.
# inputs: shell/Ui/layout/ListCursor* shell/Ui/layout/ListItem.qml shell/Commons/Tokens.js scripts/smoke/fixtures/list-cursor/* shell/plugins/vgs.settings/* shell/Commons/Reply.js shell/plugins/vgs.launcher/*
set -euo pipefail
motion_theme="$home/.config/vgshell/theme.json"
write_motion_theme() { printf '%s\n' "$1" >"$motion_theme.tmp" && mv -T -- "$motion_theme.tmp" "$motion_theme"; }
cursor_y() { ipc smoke readShownDescendant "$1" "$2" ListCursor y; }
# glide_seen HOST ID KEY: press KEY in the list the instance HOST/ID draws
# and read its ListCursor's y six times after. `moving` when two readings in
# a row both left where the cursor stood and differ, as a travel reads;
# `still` when none did, as a cursor that lands at once reads its old place
# and then only its new one.
glide_seen() {
  local from reading readings=()
  from="$(cursor_y "$1" "$2")" || return
  [[ $from =~ ^-?[0-9.e+-]+$ ]] || { echo "unreadable: $from"; return; }
  type_keys -k "$3" || return
  for _ in 1 2 3 4 5 6; do
    reading="$(cursor_y "$1" "$2")" || return
    readings+=("$reading")
  done
  python3 - "$from" "${readings[@]}" <<'PY'
import sys
start, *seen = (float(v) for v in sys.argv[1:])
moved = [v for v in seen if v != start]
print("moving" if any(a != b for a, b in zip(moved, moved[1:])) else "still")
PY
}

# Motion four times slower: the Settings list travels over 100 * 4 ms and
# the launcher's over its own 250 * 4 ms.
write_motion_theme '{ "schemaVersion": 1, "name": "slowlist", "tokens": { "motion": { "scale": 4 } } }'
expect_poll "the slowed scale reaches the list motion" 400 ipc smoke themeValue motion.list.travel.duration

expect "the Settings window summons for the list motion" ok ipc shell summon window vgs.settings '{}'
expect_poll "the Settings window takes the keyboard" true ipc smoke activeFocusIn window vgs.settings
expect_poll "the Settings list's cursor holds its first row" true ipc smoke readShownDescendant window vgs.settings ListCursor shown
render expect "the Settings list's cursor travels to the next row under a slowed scale" moving glide_seen window vgs.settings Down
write_motion_theme '{ "schemaVersion": 1, "name": "still", "tokens": { "motion": { "scale": 0 } } }'
expect_poll "motion scale 0 reaches the list motion" 0 ipc smoke themeValue motion.list.travel.duration
expect "at motion scale 0 the Settings list's cursor lands on the row at once" still glide_seen window vgs.settings Up
# A filter moves rows under a resting pointer: the list disarms the pointer
# first, so a row that lands under it takes nothing from the keyboard. The
# pointer arrives on the second row by two motions, which arm it.
settings_second="$(ipc smoke itemTexts window vgs.settings ListItem | py_reply 'import json,sys; print(json.load(sys.stdin)[1][0])')" || settings_second=""
settings_row_box="$(ipc smoke windowGeometry window vgs.settings ListItem "$settings_second")" || settings_row_box=""
if read -r row_x row_y < <(at_centre window:Plugins "$settings_row_box") && hover "$((row_x - 6))" "$row_y" && hover "$row_x" "$row_y"; then
  expect_poll "a moving pointer arms the Settings list" true ipc smoke readShownDescendant window vgs.settings ListCursor armed
  type_keys e || fail "typing a filter into the Settings search failed"
  expect_poll "the filter reaches the Settings list" '"e"' ipc smoke readShownDescendant window vgs.settings ListPage query
  expect "a filter disarms the pointer resting over the Settings list" false ipc smoke readShownDescendant window vgs.settings ListCursor armed
  rest_pointer || fail "moving the pointer off the Settings list failed"
else
  fail "the pointer did not reach the Settings list's row ${settings_second:-unread}"
fi
expect "hiding the Settings window after the list motion is allowed" ok ipc shell hide window vgs.settings
expect_poll "the Settings window is gone" 0 window_count Plugins

# The pointer's travel in the Settings list at the shipped list motion: the
# plate moves on the first frame after a hover takes the row and rests
# within hover_ceiling_ms of it, read from the window's frames by the
# CursorFrames fixture. The pointer moves between the list's first two rows:
# hover_travel ROW moves it onto row ROW one pixel at a time, as a hand
# does, until the selection takes the row, then waits for the plate to
# rest, and prints the milliseconds from the selection to the first frame
# that moved the plate and to the first frame that shows it at rest, or a
# word naming what it missed: `late` when neither of the first two frames
# swapped after the selection moved the plate. The first may have been
# drawn before the selection and only swapped after it. On host cachy on 2026-10-05, nested
# frames 33 ms apart, main 85858b4 (travel 250 ms outQuint) read the rest
# at 166 to 193 ms over 16 hovers and the first moved frame 4 to 37 ms
# after the selection; the ceiling sits under the old travel's lowest
# reading, and the same reader under that travel is its control.
hover_ceiling_ms=150
hover_fixture="$repo/scripts/smoke/fixtures/list-cursor/CursorFrames.qml"
declare -A hover_x hover_y
hover_travel() {
  local i reading prev=""
  ipc smoke popupCall cursor-frames start >/dev/null || return
  for i in $(seq 1 20); do
    hover "$((hover_x[$1] + i % 3))" "${hover_y[$1]}" || return
    [[ $(ipc smoke popupRead cursor-frames targets) != "[]" ]] && break
    sleep 0.05
  done
  for i in $(seq 1 30); do
    sleep 0.1
    reading="$(ipc smoke readShownDescendant window vgs.settings ListCursor y)" || return
    [[ $reading == "$prev" ]] && break
    prev="$reading"
  done
  python3 - "$(ipc smoke popupRead cursor-frames targets)" "$(ipc smoke popupRead cursor-frames moves)" "$(ipc smoke popupRead cursor-frames frames)" <<'PY'
import json, sys
targets, moves, frames = (json.loads(v) for v in sys.argv[1:4])
if not targets: print("unselected"); sys.exit()
if not moves: print("unmoved"); sys.exit()
t0 = targets[0][0]
final = moves[-1][1]
before = [f for f in frames if f[0] < t0]
start = before[-1][1] if before else moves[0][1]
after = [f for f in frames if f[0] >= t0]
if not after: print("undrawn"); sys.exit()
moved = [f for f in after[:2] if abs(f[1] - start) >= 0.5]
if not moved: print("late"); sys.exit()
rest = [f for f in after if abs(f[1] - final) < 0.5]
print("%d %s" % (moved[0][0] - t0, (rest[0][0] - t0) if rest else "unrested"))
PY
}
# hover_readings N: N hover_travel readings, alternating the second row and
# the first, one per line; hover_verdict: `fast` when every reading moved
# on its first frame and rested within the ceiling, `slow` when every
# reading was read and one rested past it, else `unread`.
hover_readings() {
  local n
  for n in $(seq 1 "$1"); do
    hover_travel "$((n % 2))" || echo "unread"
  done
}
hover_verdict() {
  local readings
  readings="$(hover_readings 6)"
  echo "        hover readings: $(tr '\n' ';' <<<"$readings")" >&2
  python3 - "$hover_ceiling_ms" "$readings" <<'PY'
import sys
ceiling = int(sys.argv[1])
rows = [line.split() for line in sys.argv[2].splitlines() if line.strip()]
if len(rows) != 6 or not all(len(r) == 2 and r[0].isdigit() and r[1].isdigit() for r in rows): print("unread")
else: print("fast" if all(int(r[1]) <= ceiling for r in rows) else "slow")
PY
}

write_motion_theme '{ "schemaVersion": 1, "name": "vgs", "tokens": {} }'
expect_poll "the defaults return for the hover travel" vgs ipc smoke themeName
expect "the Settings window summons for the hover travel" ok ipc shell summon window vgs.settings '{}'
expect_poll "the Settings list's cursor holds a row for the hover travel" true ipc smoke readShownDescendant window vgs.settings ListCursor shown
expect "the probe builds the cursor frame trace" ok ipc smoke popupLoad cursor-frames "$hover_fixture" window vgs.settings '{"host":"@instance"}'
hover_rows="$(ipc smoke itemTexts window vgs.settings ListItem)" || hover_rows='[]'
for hover_row in 0 1; do
  hover_name="$(py_reply 'import json,sys; r=json.load(sys.stdin); i=int(sys.argv[1]); print(r[i][0] if len(r) > i else "")' "$hover_row" <<<"$hover_rows")" || hover_name=""
  read -r "hover_x[$hover_row]" "hover_y[$hover_row]" < <(at_centre window:Plugins "$(ipc smoke windowGeometry window vgs.settings ListItem "$hover_name")") || fail "the Settings list's row $hover_row is unplaced: ${hover_name:-unread}"
done
if [[ -n ${hover_x[0]:-} && -n ${hover_x[1]:-} ]]; then
  hover "$((hover_x[0] - 6))" "${hover_y[0]}"; hover "${hover_x[0]}" "${hover_y[0]}"
  render expect "a hover moves the Settings list's plate on its first frame and rests it within ${hover_ceiling_ms} ms" fast hover_verdict
  write_motion_theme '{ "schemaVersion": 1, "name": "oldtravel", "tokens": { "motion": { "list": { "travel": { "duration": 250, "easing": "outQuint" }, "resize": { "duration": 250 } } } } }'
  expect_poll "the old travel reaches the list motion" 250 ipc smoke themeValue motion.list.travel.duration
  render expect "under the old 250 ms travel the same reader reads the plate resting late" slow hover_verdict
fi
expect "the probe drops the cursor frame trace" ok ipc smoke popupDrop cursor-frames
rest_pointer || fail "moving the pointer off the Settings list failed"
expect "hiding the Settings window after the hover travel is allowed" ok ipc shell hide window vgs.settings
expect_poll "the Settings window is gone after the hover travel" 0 window_count Plugins

# The launcher's list: Ctrl+B lists the categories and the first Down
# gives the list its cursor, on the first row.
expect "enabling the launcher for the list motion is allowed" ok ipc shell setPluginEnabled vgs.launcher true
launcher_categories() {
  expect "the launcher summons for the list motion" ok ipc shell summon overlay vgs.launcher '{}'
  expect_poll "the launcher holds the keyboard for the list motion" true ipc smoke activeFocusIn overlay vgs.launcher
  type_keys -M ctrl -k b -m ctrl -k Down || fail "listing the categories failed"
  expect_poll "the launcher's cursor holds the first category" true ipc smoke readShownDescendant overlay vgs.launcher ListCursor shown
}
launcher_travel() { ipc smoke readInstance overlay vgs.launcher listMotion | py_reply 'import json,sys; print(json.load(sys.stdin)["travel"]["duration"])'; }
write_motion_theme '{ "schemaVersion": 1, "name": "slowlist", "tokens": { "motion": { "scale": 4 } } }'
launcher_categories
expect_poll "the slowed scale reaches the launcher's list motion" 1000 launcher_travel
render expect "the launcher's cursor travels to the next row under a slowed scale" moving glide_seen overlay vgs.launcher Down
write_motion_theme '{ "schemaVersion": 1, "name": "still", "tokens": { "motion": { "scale": 0 } } }'
expect_poll "motion scale 0 reaches the launcher's list motion" 0 launcher_travel
expect "at motion scale 0 the launcher's cursor lands on the row at once" still glide_seen overlay vgs.launcher Down
# The pointer takes another category and leaves the card: the launcher's
# selection goes back to the row the keys left it on. The hovered reading
# is the contrast.
launcher_index() { ipc smoke readInstance overlay vgs.launcher selectedIndex; }
launcher_keyed="$(launcher_index)" || launcher_keyed=""
launcher_other=0; [[ $launcher_keyed == 0 ]] && launcher_other=1
launcher_texts="$(ipc smoke itemTexts overlay vgs.launcher LauncherRow)" || launcher_texts='[]'
launcher_name="$(py_reply 'import json,sys; r=json.load(sys.stdin); i=int(sys.argv[1]); print(r[i][0] if len(r) > i and r[i] else "")' "$launcher_other" <<<"$launcher_texts")" || launcher_name=""
if [[ $launcher_keyed =~ ^[0-9]+$ ]] && read -r lx ly < <(at_centre vgs:overlay "$(ipc smoke windowGeometry overlay vgs.launcher LauncherRow "$launcher_name")"); then
  hover "$((lx - 6))" "$ly"; hover "$lx" "$ly"
  expect_poll "a hover moves the launcher's selection to $launcher_name" "$launcher_other" launcher_index
  rest_pointer || fail "moving the pointer off the launcher failed"
  expect_poll "with the pointer off the list the launcher's selection is back on the keys' row" "$launcher_keyed" launcher_index
else
  fail "the launcher's row ${launcher_name:-unread} is unplaced, or its selection ${launcher_keyed:-unread} unread"
fi
type_keys -k Escape -k Escape || fail "closing the launcher failed"
expect_poll "the launcher closes after the list motion" 0 layer_count vgs:overlay
expect "disabling the launcher after the list motion is allowed" ok ipc shell setPluginEnabled vgs.launcher false

write_motion_theme '{ "schemaVersion": 1, "name": "vgs", "tokens": {} }'
expect_poll "the defaults return after the list motion" vgs ipc smoke themeName
