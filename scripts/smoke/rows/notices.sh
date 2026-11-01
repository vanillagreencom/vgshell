# The requirement notice, raised for the fixture acme.needs, which misses
# one command it needs and two optional ones. Runs after rows/tui.sh and
# reuses the stand-in xdg-terminal-exec harness.sh's terminal_stand_in
# wrote, which records the argv the core's TUI launch hands the terminal
# and runs the core's command as `true`, and the harness's helpers. A stand-in bin/vgshell-pkg answers detection with pacman and
# paru, whatever the host runs. The notice is the core's, with the Plugins
# window closed throughout. Rows: `vgshell plugin add` raises the notice
# through pluginInstalled, which maps one surface on the focused monitor
# holding the keyboard and drawing one chip per package its step handles,
# with its state beside it and the purposes under it, then one per
# required package a later step installs, with a line naming its manager,
# which its message does not repeat, its title counting every chip it draws
# that is not optional, an optional chip reading Optional; the surface fills the monitor less the bar's reserved space less
# `dialog.margin`, clears the bar by that margin and centres the dialog; a
# click on the bar's acme.tick widget reaches it while the notice shows; a
# click beside the dialog lands on the scrim, which fills the surface in
# `color.scrim`, dims what lies behind it and takes no input, so it reaches
# the acme.layers fixture's layer below, which rows/layers.sh installed and
# left disabled, and a click on the dialog's title does not, which is the
# mask's control;
# Escape closes it and rests the offers the plugin raises with no press;
# enabling the plugin raises it again; the plugin's offer merges into a
# held notice, a suggestion is refused while it rests and an offer, a
# press, is not, and an offer is refused for a command it did not
# declare and for a value that is no list of commands; Install hands the
# terminal `vgshell pkg run install` with the primary's package, the notice
# has no surface while the run is live, and comes back with the keyboard,
# naming the package the run left missing, when the rescan after the run
# still misses it; a scan that finds
# the command while the run is live keeps the installing notice in front of
# a second plugin's waiting one, and the scan after the run closes it and
# brings the waiting one forward; a command below the floor its manifest
# gives it reads outdated once the read enabling its plugin starts has
# ended, and neither that enable nor turning the plugin off and on raises a
# notice for it; a scan ends while the command's `--version` still hangs,
# and its reading arrives once the command answers; its offer raises a
# notice whose one step is Update, or Install and update with a missing
# package of the same manager beside it,
# which hands the terminal `vgshell pkg run update` for the manager that
# owns the command path; a run that ends with code 0 and leaves the command
# below its floor brings the notice back with a line naming its package,
# the version read and the floor, and the read after a run that reaches the
# floor closes it, while the same offer of a command at its floor answers
# satisfied, which is that state's control; the Install and update notice
# draws its two entries as a GroupList with its hairline between them, and
# its run that changes nothing names both packages; a
# detection that fails shows the commands
# alone with Close. The enable trigger's control is
# scripts/smoke/rows/notices-control.sh, the suite's last row: a shell copy
# without the trigger raises no notice.
# inputs: scripts/smoke/fixtures/plugins/acme.needs/* shell/Core/Notices.qml shell/Hosts/NoticeHost.qml shell/Ui/foundation/Scrim.qml shell/Ui/feedback/Badge.qml shell/Ui/foundation/Divider.qml shell/Ui/layout/GroupList.qml shell/Core/PackageManagers.js bin/vgshell-pkg bin/vgshell shell/Core/PluginLogic.js shell/Core/ConfigLogic.js scripts/smoke/fixtures/plugins/acme.layers/* scripts/smoke/fixtures/plugins/acme.bare/* scripts/smoke/fixtures/plugins/acme.status/* scripts/smoke/rows/layers.sh scripts/smoke/rows/manager.sh scripts/smoke/rows/settings.sh bin/vgshell-tui bin/vgshell-scan shell/Core/Registry.qml shell/Core/Capabilities.qml scripts/fixtures/pkg-review/* bin/lib/pkg-review.js bin/lib/pkg-review.sh bin/lib/pkg-review-settings.sh bin/lib/pkg-config.js bin/lib/judge-files.js shell/Core/PackageReview.js config/shell.json
set -euo pipefail
leak_plugin_setup acme.layers false || { fail "notices: fixture precondition failed"; return 1; }
needs_src="$sandbox/src/acme.needs"
mkdir -p "$needs_src"
cp -R "$repo/scripts/smoke/fixtures/plugins/acme.needs/." "$needs_src/"
needs_git() { "${sandbox_env[@]}" git -C "$needs_src" -c user.name=smoke -c user.email=smoke@invalid "$@" >>"$sandbox/git.log" 2>&1; }
if needs_git init -q && needs_git add -A && needs_git commit -q -m fixture; then ok "the needs fixture is committed to a local repository"; else fail "needs fixture repository: $(tail -n 3 "$sandbox/git.log")"; fi

# Detection answers through bin/vgshell-pkg, which the shell and the add's
# judge both run under node; each stand-in is swapped in whole.
pkg_real="$sandbox/vgshell-pkg.real"
cp -- "$repo/bin/vgshell-pkg" "$pkg_real"
# The core presenter delegates its real requirement argv into the common
# package owner in an isolated stand-in world, before its end record. Keep
# detection fixtures and requirement postchecks owned by this row.
notice_review_tree="$sandbox/notice-review-owner"
mkdir -p "$notice_review_tree/bin"
cp -- "$pkg_real" "$notice_review_tree/bin/vgshell-pkg"
ln -s "$repo/bin/lib" "$notice_review_tree/bin/lib"
for entry in shell config; do ln -s "$repo/$entry" "$notice_review_tree/$entry"; done
cp -- "$tui_terminal" "$sandbox/notice-terminal-before"
python3 - "$tui_terminal" "$repo/scripts/fixtures/pkg-review/route-owner.js" "$notice_review_tree/bin/vgshell-pkg" "$sandbox/notice-review.jsonl" <<'PY_NOTICE'
import pathlib, sys, shlex
p=pathlib.Path(sys.argv[1]); text=p.read_text()
needle='if [[ $window == yes ]]; then\n'
assert text.count(needle)==2
node_args=' '.join(shlex.quote(s) for s in ['/usr/bin/node',sys.argv[2],'--surface','success','--owner',sys.argv[3],'--proof',sys.argv[4]])
addition='''if [[ $key == core/requirements-install || $key == core/requirements-update ]]; then
  bridge=('''+node_args+''' --route "$key" "${@:4}")
  if [[ -e $hold ]]; then
    run[${#run[@]}-3]+='; shift; exec "$@"'
    run+=("${bridge[@]}")
  else
    unset 'run[-1]'
    run+=("${bridge[@]}")
  fi
fi
'''
p.write_text(text.replace(needle,addition+needle,1))
PY_NOTICE
pkg_stub() { # DETECT_JSON, or "" for a detection that fails; HOLDER aur|none
  local body holder="${2:-none}" aur_owner=null
  if [[ $holder == aur ]]; then
    aur_owner='"vgs-smoke-old-aur"'
  fi
  if [[ -n $1 ]]; then
    body="if (process.argv[2] === \"detect\" && process.argv[3] === \"--json\") { const doc = $1; const at = process.argv.indexOf(\"--holders\"); if (at !== -1) { doc.holders = {}; for (const command of process.argv.slice(at + 1)) doc.holders[command] = command === \"vgs-smoke-old\" ? { path: \"$shim/vgs-smoke-old\", owners: { pacman: null, aur: $aur_owner } } : { path: null, owners: {} }; } process.stdout.write(JSON.stringify(doc) + \"\\n\"); process.exit(0); }"
  else
    body=""
  fi
  printf '#!/usr/bin/env node\n%s\nprocess.stderr.write("vgshell: refused: stub=vgshell-pkg\\n");\nprocess.exit(70);\n' "$body" >"$sandbox/vgshell-pkg.stub"
  chmod 755 "$sandbox/vgshell-pkg.stub"
  cp -- "$sandbox/vgshell-pkg.stub" "$repo/bin/vgshell-pkg.next" && mv -T -- "$repo/bin/vgshell-pkg.next" "$repo/bin/vgshell-pkg"
}
pkg_stub '{"primary":{"id":"pacman","binary":"pacman"},"overlays":[{"id":"aur","binary":"paru"}],"sources":[]}'

# Whether plugin ID's own offers rest, in the notices core's lending record.
# rows/notices-control.sh reads it on a copy whose Not now records no rest.
notice_rests() { ipc shell lent | py_reply 'import json,sys; print(str(sys.argv[1] in json.load(sys.stdin)["notices"]["resting"]).lower())' "$1"; }
drawn() { ipc smoke noticeDrawn | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps(d[sys.argv[1]]))' "$1"; }
needs() { ipc acme.needs invoke "$1" "${2:-}"; }
# `placed` when the notice's one surface is the focused monitor less the
# space other layers reserve less `dialog.margin` on every edge, and the
# dialog sits in its centre to within a pixel; else the readings.
notice_placed() {
  local layers card margin
  layers="$(layers_of vgs:notice)" || return 1
  card="$(ipc smoke noticeWindowGeometry card)" || return 1
  [[ $card == \[* ]] || { echo "card=$card"; return; }
  margin="$(ipc smoke themeValue dialog.margin)" || return 1
  hypr -j monitors | py_reply '
import json, sys
ls, card, margin = json.loads(sys.argv[1]), json.loads(sys.argv[2]), int(json.loads(sys.argv[3]))
m = [m for m in json.load(sys.stdin) if m["focused"]]
if len(ls) != 1 or len(m) != 1:
    print("layers=%d focused=%d" % (len(ls), len(m))); sys.exit()
m = m[0]
left, top, right, bottom = m["reserved"]
mw, mh = m["width"] / m["scale"], m["height"] / m["scale"]
want = [m["x"] + left + margin, m["y"] + top + margin, mw - left - right - 2 * margin, mh - top - bottom - 2 * margin]
x, y, w, h = ls[0]
cx, cy, cw, ch = card
fills = ls[0] == want
centred = abs(cx + cw / 2 - w / 2) <= 1 and abs(cy + ch / 2 - h / 2) <= 1
print("placed" if fills and centred else json.dumps({"layer": ls[0], "want": want, "card": card}))' "$layers" "$card" "$margin"
}
# hover_click X Y: the pointer moves a pixel off first, since a surface
# mapped since the last press takes no click until the pointer moves,
# then one click at (X, Y).
hover_click() { hover "$(($1 + 1))" "$2" && click "$1" "$2"; }
read_tick() { ipc smoke readInstance "$(bar_key)" acme.tick "$1"; }
# notice_gap_point: the layout point on the notice's surface halfway
# between its left edge and the dialog's, at the dialog's middle height.
notice_gap_point() {
  local layer card
  layer="$(surface_box vgs:notice)" || return 1
  card="$(ipc smoke noticeWindowGeometry card)" || return 1
  python3 -c 'import json,sys
l, c = json.loads(sys.argv[1]), json.loads(sys.argv[2])
if not isinstance(l, list) or not isinstance(c, list) or c[0] < 2: sys.exit(1)
print(int(l[0] + c[0] / 2), int(l[1] + c[1] + c[3] / 2))' "$layer" "$card"
}
# notice_on_scrim X Y: for the notice's scrim drawn under the dialog,
# above opacity 0 and in `color.scrim`, `ok` when the layout point lies
# inside it and `outside` when it does not; else the readings.
notice_on_scrim() {
  local layer box drawn
  layer="$(surface_box vgs:notice)" || return 1
  box="$(ipc smoke noticeWindowGeometry scrim)" || return 1
  drawn="$(ipc smoke noticeScrim)" || return 1
  [[ $box == \[* && $drawn == \{* ]] || { echo "box=$box drawn=$drawn"; return; }
  python3 -c 'import json,sys
l, b, d, x, y = json.loads(sys.argv[1]), json.loads(sys.argv[2]), json.loads(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
inside = l[0] + b[0] <= x < l[0] + b[0] + b[2] and l[1] + b[1] <= y < l[1] + b[1] + b[3]
drawn = d["visible"] and d["opacity"] > 0 and d["token"] and d["under"]
print(("ok" if inside else "outside") if drawn else json.dumps({"layer": l, "point": [x, y], "box": b, "drawn": d}))' "$layer" "$box" "$drawn" "$1" "$2"
}
install_words() {
  words --app-id=org.vgs.tui "--title=VGS · Install requirements" -- "$tui_self" present --presentation full \
    --record core/requirements-install --run RUN --record-dir "$rt_dir/vgshell/tui" --app-id org.vgs.tui --window-title "VGS · Install requirements" -- "$core_vgshell" pkg run install "$@"
}
# The notice draws one entry per package its step handles, then one per
# package a later step offers: its name as a chip with each purpose under
# it, or the command's name when no package is known (D061), and for a
# later one a line naming its manager. group_shape reads each entry as
# [chip, the number of lines under it], and group_states the state drawn
# beside each chip.
group_shape() { ipc smoke noticeDrawn | py_reply 'import json,sys; print(json.dumps([[g[0], len(g[1])] for g in json.load(sys.stdin)["groups"]]))'; }
group_states() { ipc smoke noticeDrawn | py_reply 'import json,sys; print(json.dumps([g[2] for g in json.load(sys.stdin)["groups"]]))'; }
# `equal` when the number the drawn title counts is the number of name
# chips the notice draws whose state is not Optional, else [the title's
# number, the chips]. `chip` reads one chip fewer, the check's planted
# control.
title_counts_chips() { # [chip]
  ipc smoke noticeDrawn | py_reply 'import json,re,sys
d = json.load(sys.stdin)
m = re.search(r" needs (one|\d+) ", d["title"])
counted = None if m is None else 1 if m.group(1) == "one" else int(m.group(1))
chips = len([g for g in d["groups"] if g[2] != ["Optional"]]) - (1 if sys.argv[1] == "chip" else 0)
print("equal" if counted == chips else json.dumps([counted, chips]))' "${1:-}"
}
needs_groups='[["vgs-smoke-needs-pkg", 1]]'
# The packages the notice draws for a later step, each as [package,
# manager] from the line under its chip, in drawn order; [] when it draws
# none.
entry_later() { ipc smoke noticeDrawn | py_reply 'import json,re,sys
later = [[g[0], m.group(1)] for g in json.load(sys.stdin)["groups"] for m in [re.fullmatch(r"Offered after this step, through (\S+)\.", line) for line in g[1]] if m]
print(json.dumps(later))'; }
notice_message_holds() { ipc smoke noticeDrawn | py_reply 'import json,sys; print(str(sys.argv[1] in json.load(sys.stdin)["message"]).lower())' "$1"; }
rows_hold() { ipc smoke noticeDrawn | py_reply 'import json,sys; print(str(any(sys.argv[1] in r for r in json.load(sys.stdin)["rows"])).lower())' "$1"; }
row_drawn() { ipc smoke noticeDrawn | py_reply 'import json,sys; print(str(sys.argv[1] in json.load(sys.stdin)["rows"]).lower())' "$1"; }
all_needs='["vgs-smoke-needs", "vgs-smoke-extra", "vgs-smoke-unmapped"]'
# What the shown notice's last run left, Notices.failure in the lending
# record, and whether one line the notice draws holds every WORD.
notice_failure() { ipc shell lent | py_reply 'import json,sys; s=json.load(sys.stdin)["notices"]["shown"]; print(json.dumps(None if s is None else s["failure"]))'; }
line_holds() { ipc smoke noticeDrawn | py_reply 'import json,sys; print(str(any(all(w in r for w in sys.argv[1:]) for r in json.load(sys.stdin)["rows"])).lower())' "$@"; }

expect "no notice shows at first" null notice_shown
expect "the notice host has no surface at first" 0 layer_count vgs:notice
# The layer under the notice counts the presses that pass its surface.
expect "enabling the layers fixture under the notice is allowed" ok ipc shell setPluginEnabled acme.layers true
expect_poll "the layers fixture under the notice is built" True record_exists acme.layers
expect "the layer under the notice is shown" ok layered draw
expect "the layer under the notice takes input everywhere" ok layered full 1

# pluginInstalled: add lands the plugin disabled, the shell scans and then
# raises the notice for the commands the scan did not find.
add_out=""
if add_out="$("${shell_env[@]}" "$repo/bin/vgshell" plugin add --yes "file://$needs_src" 2>>"$sandbox/ipc.log")" \
  && [[ $add_out == "ok added=acme.needs path=$home/.config/vgshell/plugins/acme.needs config=unchanged lands=disabled"$'\n'"shell=rescan-started"$'\n'"requires vgs-smoke-needs (vgs-smoke-needs-pkg)"$'\n'"requires vgs-smoke-extra (vgs-smoke-extra-git) optional"$'\n'"requires vgs-smoke-unmapped optional"$'\n'"install: vgshell pkg run install vgs-smoke-needs-pkg"$'\n'"install: vgshell pkg run install --manager aur vgs-smoke-extra-git" ]]; then
  ok "vgshell plugin add installs the needs fixture and names its missing packages"
else
  fail "vgshell plugin add of the needs fixture: $add_out"
fi
expect_poll "pluginInstalled raises the notice for every missing command" "[\"acme.needs\", $all_needs, [\"vgs-smoke-needs\"], false]" notice_shown
expect_poll "the notice host maps one surface" 1 layer_count vgs:notice
geometry expect "the notice fills the monitor less the bar and its margin, the dialog centred" placed notice_placed
expect "the layer/bar overlap predicate rejects an overlap" "violation overlap" layer_bar_contract_value <<<"layer=200,20,400,40 bar=0,0,800,40 margin=8"
geometry expect "the notice surface clears the bar by the dialog margin" ok layer_bar_clear vgs:notice dialog.margin
expect_poll "the notice holds the keyboard" true ipc smoke noticeFocused

# The bar and the layer below take their own clicks; the dialog takes its
# own. A press that passes through leaves nothing to wait for, so the
# control's click on the title is followed by a click on the Tick widget:
# the bar, the notice and the layer are all surfaces of the shell's one
# Wayland connection, so the compositor delivers the presses in order, and
# the Tick's press arriving proves the title's press arrived first. The
# layer's count then still reads the one click beside the dialog.
expect "the Tick widget is on the bar under the notice" True record_exists acme.tick
read_count tick_presses "the Tick widget's presses under the notice" read_tick presses
tick_rect="$(ipc smoke instanceGeometry "$(bar_key)" acme.tick)" || tick_rect=""
read -r tick_x tick_y < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(int(x+w/2), int(y+h/2))' "$tick_rect") || fail "the Tick widget was not measured"
hover_click "$tick_x" "$tick_y" || fail "the click on the Tick widget failed"
expect_poll "a click on the bar's widget while the notice shows reaches it" "$((tick_presses + 1))" read_tick presses
read -r gap_x gap_y < <(notice_gap_point) || fail "the notice surface beside the dialog was not measured"
read_count presses "the presses of the layer below the notice" read_layers presses
expect "the point beside the dialog lies on the drawn scrim" ok notice_on_scrim "$gap_x" "$gap_y"
read -r off_x < <(surface_box vgs:notice | py_reply 'import json,sys; print(int(json.load(sys.stdin)[0]) - 1)') || fail "the notice surface's left edge was not measured"
expect "control: a point off the notice surface does not lie on the scrim" outside notice_on_scrim "$off_x" "$gap_y"
hover_click "$gap_x" "$gap_y" || fail "the click beside the dialog failed"
expect_poll "a click on the scrim beside the dialog reaches the layer below" "$((presses + 1))" read_layers presses
title_rect="$(ipc smoke noticeWindowGeometry title)" || title_rect=""
read -r title_x title_y < <(at_centre vgs:notice "$title_rect") || fail "the dialog's title was not measured"
hover_click "$title_x" "$title_y" || fail "the click on the dialog's title failed"
hover_click "$tick_x" "$tick_y" || fail "the marker click on the Tick widget failed"
expect_poll "the marker click on the Tick widget after the title's arrives" "$((tick_presses + 2))" read_tick presses
expect "control: a click on the dialog's title does not reach the layer below" "$((presses + 1))" read_layers presses
expect "a click on the dialog's title leaves the notice showing" "[\"acme.needs\", $all_needs, [\"vgs-smoke-needs\"], false]" notice_shown
expect "the layer under the notice is hidden" ok layered undraw
expect "disabling the layers fixture under the notice is allowed" ok ipc shell setPluginEnabled acme.layers false
expect_poll "the layers fixture under the notice is gone" False record_exists acme.layers
expect_poll "the notice holds the keyboard after the clicks" true ipc smoke noticeFocused
expect "the notice draws one chip per package its step handles" "$needs_groups" group_shape
expect "the chip's package reads missing" '[["Missing"]]' group_states
expect "the title counts the package the step handles" '"Acme Sync needs one package"' drawn title
expect "the notice draws nothing for later: it closes once its one required command is found" '[]' entry_later
expect "no line names a command whose package is known" false row_drawn "vgs-smoke-needs"
expect "control: the same reading finds the package's chip" true row_drawn "vgs-smoke-needs-pkg"
expect "no line marks a requirement optional" false rows_hold "optional"
expect "the notice draws no Show command control" false rows_hold "Show command"
expect "no row of the notice's body draws a command line" false rows_hold "pkg run install"
expect "control: the same reading finds a purpose the body draws" true rows_hold "The command the fixture runs"
expect_poll "the notice's Install holds the keyboard first" '"Install"' drawn focused
type_keys -k Tab || fail "sending Tab to the notice failed"
expect_poll "Tab reaches Not now" '"Not now"' drawn focused
type_keys -k Tab || fail "sending Tab past Not now failed"
expect_poll "Tab wraps back to Install" '"Install"' drawn focused
expect "an installable notice offers Install and Not now" '["Install", "Not now"]' drawn actions
expect "the plugin landed disabled" False plugin_enabled acme.needs
expect "the plugin's offers do not rest before Not now" false notice_rests acme.needs

# Escape answers Not now: the notice goes and the plugin's own offers rest.
type_keys -k Escape || fail "sending Escape failed"
expect_poll "Escape closes the notice" null notice_shown
expect_poll "the closed notice leaves no surface" 0 layer_count vgs:notice
# Notices.dismiss records the rest in the call that takes the notice off,
# so the read after the notice goes is decisive.
expect "the plugin's offers rest after Not now" true notice_rests acme.needs

# setPluginEnabled: enabling the plugin raises the notice again, whatever
# the rest, since the user asked.
expect "enabling the needs fixture is allowed" ok ipc shell setPluginEnabled acme.needs true
expect_poll "enabling a plugin that misses a command raises the notice" "[\"acme.needs\", $all_needs, [\"vgs-smoke-needs\"], false]" notice_shown
expect_poll "the needs fixture's service is built" True record_exists acme.needs

# The requirements capability: an offer merges into the plugin's held
# notice. While the notice is gone and the plugin rests, a suggestion, raised
# with no press, is refused, and an offer, a user's press, raises the notice.
# `missing` lists the declared commands the last scan did not find; the
# rows after the install and after the command goes read it change.
expect "the capability lists the declared commands the scan did not find" '["vgs-smoke-needs","vgs-smoke-extra","vgs-smoke-unmapped"]' needs missing
expect "an offer while the notice shows merges into it" ok needs offer "vgs-smoke-extra"
expect "an offer of a present command is satisfied" satisfied needs offer "sh"
expect "an offer of a command the manifest does not declare is refused" "refused: requirement=pacman reason=undeclared" needs offer "vgs-smoke-needs|pacman"
expect "an offer that is not a list is refused" "refused: requirements=malformed" needs offer-json '"vgs-smoke-needs"'
expect "the merged notice is still the one notice" "[\"acme.needs\", $all_needs, [\"vgs-smoke-needs\", \"vgs-smoke-extra\"], false]" notice_shown
expect_poll "the merged notice names the AUR package for a later step under its chip, and not the command no manager provides" '[["vgs-smoke-extra-git", "aur"]]' entry_later
expect "the merged notice's message does not name the later package again" false notice_message_holds "vgs-smoke-extra-git"
expect "the merged notice marks the later optional package Optional" '[["Missing"], ["Optional"]]' group_states
expect "the merged notice's title counts the step's package, not the optional later one" '"Acme Sync needs one package"' drawn title
expect "the merged notice draws the step's package, then the later one with a line naming its manager" '[["vgs-smoke-needs-pkg", 1], ["vgs-smoke-extra-git", 2]]' group_shape
expect "the merged notice's title counts every chip it draws" equal title_counts_chips
expect "control: a reading of one chip fewer is refused" '[1, 0]' title_counts_chips chip
expect_poll "the notice holds the keyboard again" true ipc smoke noticeFocused
type_keys -k Escape || fail "sending Escape failed"
expect_poll "Escape closes the enabled notice" null notice_shown
resting_suggestion() { needs suggest vgs-smoke-needs | sed -E 's/retry-ms=[0-9]+$/retry-ms=N/'; }
expect "a suggestion while the plugin rests is refused" "refused: requirements=acme.needs reason=resting retry-ms=N" resting_suggestion
expect "a refused suggestion raises no notice" 0 layer_count vgs:notice
expect "an offer while the plugin rests is admitted" ok needs offer vgs-smoke-needs
expect_poll "the offer after Not now shows the notice" '["acme.needs", ["vgs-smoke-needs"], ["vgs-smoke-needs"], false]' notice_shown
expect_poll "the offer's notice holds the keyboard" true ipc smoke noticeFocused
type_keys -k Escape || fail "sending Escape failed"
expect_poll "Escape closes the offer's notice" null notice_shown

# Install: the primary's package through the core's TUI. While hold_runs
# holds the core run open (terminal_stand_in in harness.sh), the notice has
# no surface, so the terminal shows whole. The command stays missing after
# the run's rescan, so the notice comes back with the keyboard.
notice_waiting() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["notices"]["waiting"]))'; }
notice_front() { ipc shell lent | py_reply 'import json,sys; s=json.load(sys.stdin)["notices"]["shown"]; print(json.dumps(None if s is None else s["plugin"]))'; }
# `settled` once no install is in flight: the notice in front is not
# installing, or none shows. After a run ends, Notices.qml starts one scan,
# and that scan's version read clears the install, settles the queue and
# judges what the run left in one callback, so the rows read right after it
# need no poll. No enabled plugin gives a command a floor while the install
# rows run, so that read starts no process and follows the scan's end in
# the same turn. The chain from
# the run's end being read to that callback, one scan, is bounded by
# install_settle_ceiling_ms, read as latency_install_settle_ms: twice the
# highest of 12 readings, 245 ms, from the six runs that measured
# run_end_ceiling_ms in harness.sh.
install_settle_ceiling_ms=500
install_settled() { ipc shell lent | py_reply 'import json,sys; s=json.load(sys.stdin)["notices"]["shown"]; print("settled" if s is None or not s["installing"] else "installing")'; }
needs_state() { ipc shell listPlugins | py_reply 'import json,sys; print(json.dumps([r["state"] for p in json.load(sys.stdin)["plugins"] if p["id"]=="acme.needs" for r in p["requirements"]][0]))'; }
expect "enabling the enabled fixture raises the notice again" ok ipc shell setPluginEnabled acme.needs true
expect_poll "the notice is back" "[\"acme.needs\", $all_needs, [\"vgs-smoke-needs\"], false]" notice_shown
expect_poll "the notice holds the keyboard for Install" true ipc smoke noticeFocused
expect "no install ran before the rows" idle key_idle core/requirements-install
hold_runs
forget_record
type_keys -k Return || fail "sending Return failed"
expect_poll "Install hands the terminal vgshell pkg run install with the primary's package" "$(install_words vgs-smoke-needs-pkg)" recorded
expect_poll "the notice records its install running" "[\"acme.needs\", $all_needs, [\"vgs-smoke-needs\"], true]" notice_shown
expect_poll "a live install leaves the notice no surface" 0 layer_count vgs:notice
expect "the install's run is live while the notice is gone" busy key_idle core/requirements-install
release_runs
expect_run_end "the install run ends" core/requirements-install
expect_within "the scan after the install run settles the notice" install_settle settled "$install_settle_ceiling_ms" install_settled
expect "the rescan after an install that left the command missing keeps the notice" "[\"acme.needs\", $all_needs, [\"vgs-smoke-needs\"], false]" notice_shown
expect "the kept notice names the package the install left missing" '{"kind": "unchanged", "left": [{"kind": "missing", "name": "vgs-smoke-needs-pkg", "optional": false}]}' notice_failure
expect_poll "the kept notice maps its surface again" 1 layer_count vgs:notice
expect_poll "the kept notice holds the keyboard after the install" true ipc smoke noticeFocused
expect "the notice still offers Install" '["Install", "Not now"]' drawn actions

# A second plugin's notice waits behind the install. The installed
# command appears and a scan runs while the install's terminal is still
# open, as `vgshell pkg run` asks for one when its steps end: the installing
# notice stays and the waiting one stays behind it until the run ends.
# acme.other is acme.needs under another id, needing vgs-smoke-other.
other_dir="$home/.config/vgshell/plugins/acme.other"
mkdir -p -- "$other_dir"
cp -R -- "$repo/scripts/smoke/fixtures/plugins/acme.needs/." "$other_dir/"
if python3 -c '
import sys
path = sys.argv[1]
text = open(path).read()
edits = [("\"id\": \"acme.needs\"", "\"id\": \"acme.other\""), ("\"command\": \"vgs-smoke-needs\"", "\"command\": \"vgs-smoke-other\"")]
for old, new in edits:
    if text.count(old) != 1:
        sys.exit("%s occurs %d times" % (old, text.count(old)))
    text = text.replace(old, new)
open(path, "w").write(text)' "$other_dir/manifest.json"; then ok "acme.other is acme.needs under another id and command"; else fail "acme.other's manifest could not be derived from acme.needs"; fi
rescan "a rescan after adding acme.other starts"
expect_poll "acme.other is discovered" True plugin_known acme.other
expect "enabling acme.other is allowed" ok ipc shell setPluginEnabled acme.other true
expect_poll "acme.other's notice waits behind acme.needs'" '["acme.other"]' notice_waiting
expect_poll "the notice holds the keyboard for the second Install" true ipc smoke noticeFocused
hold_runs
forget_record
type_keys -k Return || fail "sending Return failed"
expect_poll "the second Install reaches the terminal" "$(install_words vgs-smoke-needs-pkg)" recorded
expect_poll "the second install runs" "[\"acme.needs\", $all_needs, [\"vgs-smoke-needs\"], true]" notice_shown
printf '#!/bin/sh\nexit 0\n' >"$shim/vgs-smoke-needs"; chmod 755 "$shim/vgs-smoke-needs"
rescan "a rescan while the install's terminal is open starts"
expect_poll "that scan finds the installed command" '"present"' needs_state
expect_poll "the capability no longer lists the installed command" '["vgs-smoke-extra","vgs-smoke-unmapped"]' needs missing
expect "the installing notice stays after a scan that finds its command" "[\"acme.needs\", $all_needs, [\"vgs-smoke-needs\"], true]" notice_shown
expect "the waiting notice stays behind the live install" '["acme.other"]' notice_waiting
expect "no notice surface maps while the install runs" 0 layer_count vgs:notice
release_runs
expect_run_end "the second install run ends" core/requirements-install
expect_within "the scan after the second install run settles the notice" install_settle settled "$install_settle_ceiling_ms" install_settled
expect "the scan after the run closes the satisfied notice and brings the waiting one forward" '"acme.other"' notice_front
expect_poll "the waiting notice maps its surface" 1 layer_count vgs:notice
expect_poll "the waiting notice holds the keyboard" true ipc smoke noticeFocused
type_keys -k Escape || fail "sending Escape failed"
expect_poll "Escape closes acme.other's notice" null notice_shown
expect_poll "no notice leaves a surface" 0 layer_count vgs:notice
expect "disabling acme.other is allowed" ok ipc shell setPluginEnabled acme.other false
other_removed() { local out; out="$("${shell_env[@]}" "$repo/bin/vgshell" plugin remove --yes acme.other 2>>"$sandbox/ipc.log")" || return 1; printf '%s\n' "${out%%$'\n'*}"; }
expect "acme.other is removed" "ok removed=acme.other" other_removed
expect_poll "acme.other leaves the list" False plugin_known acme.other
rm -f -- "$shim/vgs-smoke-needs"
rescan "a rescan after the command goes starts"
expect_poll "the removed command is missing again" '"missing"' needs_state
expect_poll "the capability lists the removed command again" '["vgs-smoke-needs","vgs-smoke-extra","vgs-smoke-unmapped"]' needs missing

# A command below its floor. acme.floor is acme.needs under another id,
# whose needed command is vgs-smoke-old with the floor 2.0.0, and the
# stand-in prints the version old_version wrote. No row here rescans
# between the enable and the first read of the state: enabling a plugin
# that gives a present command a floor starts the read of its version,
# with no scan (Registry.qml). A scan's version read returns after the scan
# has ended, so a state that follows a rescan is polled.
floor_dir="$home/.config/vgshell/plugins/acme.floor"
mkdir -p -- "$floor_dir"
cp -R -- "$repo/scripts/smoke/fixtures/plugins/acme.needs/." "$floor_dir/"
if python3 -c '
import sys
path = sys.argv[1]
text = open(path).read()
edits = [("\"id\": \"acme.needs\"", "\"id\": \"acme.floor\""),
         ("{ \"command\": \"vgs-smoke-needs\", \"packages\": { \"pacman\": \"vgs-smoke-needs-pkg\" }, ", "{ \"command\": \"vgs-smoke-old\", \"packages\": { \"pacman\": \"vgs-smoke-old-pkg\", \"aur\": \"vgs-smoke-old-aur\" }, \"floor\": \"2.0.0\", ")]
for old, new in edits:
    if text.count(old) != 1:
        sys.exit("%s occurs %d times" % (old, text.count(old)))
    text = text.replace(old, new)
open(path, "w").write(text)' "$floor_dir/manifest.json"; then ok "acme.floor is acme.needs under another id, with a floor on its command"; else fail "acme.floor's manifest could not be derived from acme.needs"; fi
old_version() { # VERSION
  printf '#!/bin/sh\necho "vgs-smoke-old %s"\n' "$1" >"$shim/vgs-smoke-old.next" && chmod 755 "$shim/vgs-smoke-old.next" && mv -T -- "$shim/vgs-smoke-old.next" "$shim/vgs-smoke-old"
}
# A stand-in that answers nothing until old_gate exists, then VERSION. The
# reader's own bound ends one the row never releases.
old_gate="$sandbox/vgs-smoke-old.gate"
old_version_held() { # VERSION
  printf '#!/bin/sh\nwhile [ ! -e %q ]; do sleep 0.05; done\necho "vgs-smoke-old %s"\n' "$old_gate" "$1" >"$shim/vgs-smoke-old.next" && chmod 755 "$shim/vgs-smoke-old.next" && mv -T -- "$shim/vgs-smoke-old.next" "$shim/vgs-smoke-old"
}
floor_state() { ipc shell listPlugins | py_reply 'import json,sys; print(json.dumps([r["state"] for p in json.load(sys.stdin)["plugins"] if p["id"]=="acme.floor" for r in p["requirements"] if r["name"]=="vgs-smoke-old"]))'; }
floor_plugin() { ipc acme.floor invoke "$1" "${2:-}"; }
update_words() {
  words --app-id=org.vgs.tui "--title=VGS · Update requirements" -- "$tui_self" present --presentation full \
    --record core/requirements-update --run RUN --record-dir "$rt_dir/vgshell/tui" --app-id org.vgs.tui --window-title "VGS · Update requirements" -- "$core_vgshell" pkg run update "$@"
}
not_recorded_words() { [[ "$(recorded)" != "$(update_words "$@")" ]] && echo true || echo false; }
floor_shown='["acme.floor", ["vgs-smoke-old"], ["vgs-smoke-old"]'
old_version 1.9.0 || fail "the stand-in below the floor is not written"
rescan "a rescan after adding acme.floor starts"
expect_poll "acme.floor is discovered" True plugin_known acme.floor
expect "a disabled plugin's command has no version read" '["present"]' floor_state
floor_scans="$(ipc shell scanRevision)" || fail "the scan revision is unreadable before acme.floor is enabled"
expect "enabling acme.floor is allowed" ok ipc shell setPluginEnabled acme.floor true
expect_poll "the read enabling the plugin starts finds its command below the floor" '["outdated"]' floor_state
expect "enabling the plugin started no scan" "$floor_scans" ipc shell scanRevision
expect "the capability lists the outdated command" '["vgs-smoke-old"]' floor_plugin outdated
expect "the capability lists no outdated command as missing" '["vgs-smoke-extra","vgs-smoke-unmapped"]' floor_plugin missing
expect "a scan raises no notice for the outdated command" null notice_shown
# Off and on with the reading still held: Notices.enabled runs before
# setPluginEnabled replies, so the read after the reply is decisive, and
# the state read after it shows the trigger judged an outdated command.
expect "disabling acme.floor with its command outdated is allowed" ok ipc shell setPluginEnabled acme.floor false
expect "enabling acme.floor again is allowed" ok ipc shell setPluginEnabled acme.floor true
expect "a plugin turned off and on with its command outdated raises no notice" null notice_shown
expect "the reading was held across the off and on" '["outdated"]' floor_state
expect_poll "acme.floor's service is built again" True record_exists acme.floor
# A scan does not wait for the version read. The stand-in answers nothing
# while old_gate is absent, so once the scan has landed the state still
# reads the last reading: a scan that waited would land only when the
# reader's bound ended the stand-in, with no reading and the state present.
# The released stand-in answers the floor, which that same read then holds,
# and the same offer of the command at its floor raises nothing, the
# control of the offer below.
rm -f -- "${old_gate:?}"
old_version_held 2.0.0 || fail "the held stand-in is not written"
rescan "a rescan lands while the command's version read hangs"
expect "the scan ended before its version read: the last reading stands" '["outdated"]' floor_state
: >"$old_gate"
expect_poll "the reading arrives once the command answers, and reads its floor" '["present"]' floor_state
expect "an offer of a command at its floor is satisfied" satisfied floor_plugin offer vgs-smoke-old
expect "the satisfied offer raises no notice" null notice_shown
old_version 1.9.0 || fail "the stand-in below the floor is not written again"
rm -f -- "${old_gate:?}"
rescan "a rescan with the command below its floor starts"
expect_poll "a command below its floor reads outdated again" '["outdated"]' floor_state
expect "an offer of the outdated command raises the notice" ok floor_plugin offer vgs-smoke-old
expect_poll "the notice lists the outdated command" "$floor_shown, false]" notice_shown
expect_poll "the update notice holds the keyboard" true ipc smoke noticeFocused
expect "the update notice counts its update" '"Acme Sync needs one update"' drawn title
expect "the update notice draws the package as its chip" '[["vgs-smoke-old-pkg", 1]]' group_shape
expect "the update notice offers Update" '["Update", "Not now"]' drawn actions
expect "the notice names no run before one ended" null notice_failure
expect "control: no line holds the package, its version and its floor before a run" false line_holds vgs-smoke-old-pkg 1.9.0 2.0.0
expect "no update ran before the rows" idle key_idle core/requirements-update
# An update that changes nothing: the stand-in terminal runs the core's
# command as `true`, which ends with code 0, and the command stays at 1.9.0,
# as it does when the package manager holds nothing newer.
hold_runs
forget_record
type_keys -k Return || fail "sending Return failed"
expect_poll "Update hands the terminal vgshell pkg run update with the primary's package" "$(update_words vgs-smoke-old-pkg)" recorded
expect_poll "the notice records its update running" "$floor_shown, true]" notice_shown
expect_poll "a live update leaves the notice no surface" 0 layer_count vgs:notice
release_runs
expect_run_end "the update run that changes nothing ends" core/requirements-update
expect_poll "the read after that run settles the notice" settled install_settled
expect "an update that left the command below its floor keeps the notice" "$floor_shown, false]" notice_shown
expect "the kept notice names the package, the version read and the floor" '{"kind": "unchanged", "left": [{"kind": "outdated", "name": "vgs-smoke-old-pkg", "version": "1.9.0", "floor": "2.0.0"}]}' notice_failure
expect_poll "the kept update notice maps its surface again" 1 layer_count vgs:notice
expect_poll "the kept update notice holds the keyboard" true ipc smoke noticeFocused
expect "one line of the notice holds the package, its version and its floor" true line_holds vgs-smoke-old-pkg 1.9.0 2.0.0
expect "no line of the notice draws a command line" false rows_hold "pkg run"
expect "the kept notice still offers Update" '["Update", "Not now"]' drawn actions
# The same press with a run that reaches the floor: no line, and no notice.
hold_runs
forget_record
type_keys -k Return || fail "sending Return for the second update failed"
expect_poll "the second Update reaches the terminal" "$(update_words vgs-smoke-old-pkg)" recorded
expect_poll "the notice records its second update running" "$floor_shown, true]" notice_shown
expect "a second press clears what the first run left" null notice_failure
old_version 2.0.0 || fail "the updated stand-in is not written"
release_runs
expect_run_end "the update run ends" core/requirements-update
expect_poll "the read after the update run settles the notice" settled install_settled
expect "the read that finds the floor closes the update notice" null notice_shown
expect "the updated command reads present" '["present"]' floor_state
expect "the capability lists no outdated command after the update" '[]' floor_plugin outdated
pkg_stub '{"primary":{"id":"pacman","binary":"pacman"},"overlays":[{"id":"aur","binary":"paru"}],"sources":[]}' aur
old_version 1.9.0 || fail "the stand-in below the floor is written for the held-manager check"
rescan "a rescan with the command below its floor and a holder answer starts"
expect_poll "the held-manager command reads outdated" '["outdated"]' floor_state
expect "an offer of the held outdated command raises the notice" ok floor_plugin offer vgs-smoke-old
expect_poll "the held-manager notice lists the outdated command" "$floor_shown, false]" notice_shown
expect "the held-manager update notice draws the AUR package as its chip" '[["vgs-smoke-old-aur", 1]]' group_shape
hold_runs
forget_record
type_keys -k Return || fail "sending Return for the held-manager update failed"
expect_poll "Update hands the terminal the AUR package, not the first-listed package" "$(update_words --manager aur vgs-smoke-old-aur)" recorded
expect "control: the held-manager update did not hand the terminal the first-listed package" true not_recorded_words vgs-smoke-old-pkg
old_version 2.0.0 || fail "the held-manager stand-in is updated"
release_runs
expect_run_end "the held-manager update run ends" core/requirements-update
expect_poll "the read after the held-manager update settles the notice" settled install_settled
expect "the held-manager update notice closes" null notice_shown
# A notice that holds an outdated command and a missing one of the same
# manager, the AUR helper here, runs both in one press: the update, then
# the missing package after --install (VGS-1490). The stand-in run changes
# nothing, so the notice comes back naming both packages.
old_version 1.9.0 || fail "the stand-in below the floor is written for the mixed notice"
rescan "a rescan with the command below its floor starts for the mixed notice"
expect_poll "the command reads outdated for the mixed notice" '["outdated"]' floor_state
expect "an offer of the outdated command and a missing extra raises the notice" ok floor_plugin offer 'vgs-smoke-old|vgs-smoke-extra'
expect_poll "the mixed notice lists both commands" '["acme.floor", ["vgs-smoke-old", "vgs-smoke-extra"], ["vgs-smoke-old", "vgs-smoke-extra"], false]' notice_shown
expect_poll "the mixed notice offers one step for both" '["Install and update", "Not now"]' drawn actions
expect "the mixed notice draws both packages" '[["vgs-smoke-old-aur", 1], ["vgs-smoke-extra-git", 1]]' group_shape
expect "the mixed notice marks one outdated and one optional" '[["Outdated"], ["Optional"]]' group_states
expect "the mixed notice counts the update, not the optional package" '"Acme Sync needs one update"' drawn title
expect "the mixed notice's title counts every chip it draws" equal title_counts_chips
# The mixed notice's two entries are groups of a GroupList with one shown
# hairline in the gap between them, drawn within a pixel of the place
# GroupList computes from the entries' ink (Theme.inkBelow of the entry
# above, Theme.inkAbove of the entry below). The probe reads that ink with
# the same calls, so the check proves the composition, not the ink:
# tst_grouplist.qml reads the centring from an image. One control plants
# the same reading with the hairline 3 px low and one with it gone, which
# the check refuses on each rule. `[]` is the pass.
entry_hairlines() { # [low|line]
  local ink
  ink="$(ipc smoke noticeEntryInk)" || return
  python3 - "$ink" "${1:-}" <<'PY'
import json, sys
if not sys.argv[1].startswith("{"):
    print(json.dumps(["ink=%s" % sys.argv[1]])); sys.exit()
d, plant = json.loads(sys.argv[1]), sys.argv[2]
entries, lines = d["entries"], d["hairlines"]
if plant == "low" and lines: lines[0] = dict(lines[0], y=lines[0]["y"] + 3)
if plant == "line": lines = lines[1:]
out = []
if len(entries) < 2: out.append("entries=%d" % len(entries))
elif len(lines) != len(entries) - 1: out.append("hairlines=%d entries=%d" % (len(lines), len(entries)))
else:
    for k in range(1, len(entries)):
        centre = lines[k - 1]["y"] + lines[k - 1]["height"] / 2
        want = (entries[k - 1]["bottom"] + entries[k]["top"]) / 2
        if abs(centre - want) > 1: out.append("hairline%d=%.2f want=%.2f" % (k, centre, want))
print(json.dumps(out))
PY
}
geometry expect_poll "the mixed notice's entries are a GroupList with one hairline at the place it computes" '[]' entry_hairlines
hairline_planted() { entry_hairlines "$1" | py_reply 'import json,sys; o=json.load(sys.stdin); print(any(sys.argv[1] in e for e in o))' "$2"; }
expect "control: a hairline 3 px low is refused" True hairline_planted low hairline1=
expect "control: a missing hairline is refused" True hairline_planted line hairlines=
expect_poll "the mixed notice holds the keyboard" true ipc smoke noticeFocused
hold_runs
forget_record
type_keys -k Return || fail "sending Return for the mixed step failed"
expect_poll "one press hands the terminal the update and the install" "$(update_words --manager aur vgs-smoke-old-aur --install vgs-smoke-extra-git)" recorded
release_runs
expect_run_end "the mixed run ends" core/requirements-update
expect_poll "the read after the mixed run settles the notice" settled install_settled
expect "a mixed run that changed nothing names both packages" '{"kind": "unchanged", "left": [{"kind": "outdated", "name": "vgs-smoke-old-aur", "version": "1.9.0", "floor": "2.0.0"}, {"kind": "missing", "name": "vgs-smoke-extra-git", "optional": true}]}' notice_failure
expect "one line of the kept mixed notice names the missing package beside the outdated one" true line_holds vgs-smoke-old-aur 1.9.0 vgs-smoke-extra-git
expect "the kept mixed notice says the optional package is optional and the step it ran left it out" true line_holds "vgs-smoke-extra-git is optional. Install and update left it out, and Acme Sync works without it."
expect "control: the kept mixed notice does not call the optional package still missing" false line_holds "vgs-smoke-extra-git is still missing"
expect_poll "the kept mixed notice maps its surface again" 1 layer_count vgs:notice
expect_poll "the kept mixed notice holds the keyboard" true ipc smoke noticeFocused
type_keys -k Escape || fail "sending Escape to the mixed notice failed"
expect_poll "Escape closes the mixed notice" null notice_shown
expect "disabling acme.floor is allowed" ok ipc shell setPluginEnabled acme.floor false
floor_removed() { local out; out="$("${shell_env[@]}" "$repo/bin/vgshell" plugin remove --yes acme.floor 2>>"$sandbox/ipc.log")" || return 1; printf '%s\n' "${out%%$'\n'*}"; }
expect "acme.floor is removed" "ok removed=acme.floor" floor_removed
expect_poll "acme.floor leaves the list" False plugin_known acme.floor
rm -f -- "${shim:?}/vgs-smoke-old" "${old_gate:?}"

# A detection that fails: the notice lists the commands with no package
# and offers Close alone.
pkg_stub ""
expected_errors+=('notices: detect=failed exit=70 status=0 vgshell: refused: stub=vgshell-pkg')
expect "enabling the fixture while detection fails raises the notice" ok ipc shell setPluginEnabled acme.needs true
expect_poll "the notice shows with detection failed" 1 layer_count vgs:notice
expect_log "the failed detection is logged" 1 'notices: detect=failed exit=70 status=0 vgshell: refused: stub=vgshell-pkg'
expect "a notice without managers draws each requirement's command as its chip" '[["vgs-smoke-needs", 1], ["vgs-smoke-extra", 1], ["vgs-smoke-unmapped", 1]]' group_shape
expect "a notice without an install draws no Show command control" false rows_hold "Show command"
expect "a notice without an install offers Close alone" '["Close"]' drawn actions
expect "the message says detection failed" '"VGS could not detect this system'"'"'s package manager. Install these requirements by hand."' drawn message
expect_poll "the notice without an install holds the keyboard" true ipc smoke noticeFocused
type_keys -k Escape || fail "sending Escape failed"
expect_poll "Escape closes the notice without an install" 0 layer_count vgs:notice

cp -- "$pkg_real" "$repo/bin/vgshell-pkg.next" && mv -T -- "$repo/bin/vgshell-pkg.next" "$repo/bin/vgshell-pkg"
expect "disabling the needs fixture is allowed" ok ipc shell setPluginEnabled acme.needs false
remove_out() { local out; out="$("${shell_env[@]}" "$repo/bin/vgshell" plugin remove --yes acme.needs 2>>"$sandbox/ipc.log")" || return 1; printf '%s\n' "${out%%$'\n'*}"; }
expect "the needs fixture is removed" "ok removed=acme.needs" remove_out
expect_poll "the removed fixture leaves the list" False plugin_known acme.needs

cp -- "$sandbox/notice-terminal-before" "$tui_terminal"
python3 - "$sandbox/notice-review.jsonl" "$repo/scripts/fixtures/pkg-review/route-owner.js" "$notice_review_tree/bin/vgshell-pkg" <<'PY_NOTICE_PROOF'
import json,subprocess,sys
rows=[json.loads(line) for line in open(sys.argv[1])]
assert any(r['args'][:2]==['run','install'] for r in rows),rows
assert any(r['args'][:2]==['run','update'] and '--install' not in r['args'] for r in rows),rows
assert any(r['args'][:2]==['run','update'] and '--install' in r['args'] for r in rows),rows
# Each timed command runs one successful owner transaction. Keep the
# additional owner-failure assertions on those exact argv outside that
# interval; the route's own postcheck/status assertions stay above.
for row in rows:
    subprocess.run(['/usr/bin/node',sys.argv[2],'--surface','failures','--owner',sys.argv[3],'--proof',sys.argv[1],'--route',row['route'],*row['args']],check=True)
for line in open(sys.argv[1]): print('package-route-proof: '+line.rstrip())
PY_NOTICE_PROOF
