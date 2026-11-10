# The restart notice, for a shell whose own files changed under it. Runs
# after rows/hyprland-consent.sh, a core row, has answered the first-start
# welcome, so the consent slot holds no notice of its own here. The row
# compiles acme.drift before the core changes and leaves acme.drift-b
# unbuilt. The core watcher sees the sandbox copy's qs.Ui/qmldir
# modification, while the new DriftMark.qml file alone would not count,
# and raises Restart to update without a plugin rescan. A rescan after that
# change holds the manifest map, so the open panel keeps its old snapshot
# and the unbuilt copy is refused with `refused: restart=owed`, not built
# against the changed core; the notice that refusal owes waits while a
# floating TUI run is live and shows once it ends. Restart is pressed only after the row proves
# the notice belongs to the sandbox shell. The relaunched shell then builds
# both panels from the changed core. Cleanup removes the fixtures and type
# and starts the sandbox tree again. A pacman-conf stand-in in the shell's
# own PATH directory names a package database under the sandbox for the
# whole row, so no watcher reads the host's pacman lock. The last block,
# on that fresh shell, holds the database's lock while the bundled fonts
# are gone and the core changes, as pacman's unlink-then-write leaves them
# mid-transaction, and requires an unbuilt copy, acme.drift-c, refused at
# once and the restart notice only after the fonts are back and the lock
# is gone, drawn from the shell's private font copies and no fallback face.
# The block after it, on a fresh shell, writes the mono font's bytes over
# the sans font file in place, and requires the restart notice and a panel
# window first drawn after that to read as the text they draw, from the
# copies the shell started with, and a restart to load a copy of the new
# bytes. A last start clears the debt it raises.
# inputs: scripts/smoke/fixtures/plugins/acme.drift/* bin/vgshell-scan shell/assets/fonts/InterVariable.ttf shell/assets/fonts/JetBrainsMono-Variable.ttf shell/Commons/Theme.qml shell/Ui/foundation/Label.qml scripts/smoke/Probe.qml bin/vgshell shell/Core/Registry.qml shell/Core/Plugins.qml shell/Core/Notices.qml shell/Hosts/NoticeHost.qml shell/Core/TuiRunner.qml shell/Hosts/PluginSlot.qml shell/Hosts/SummonHost.qml shell/Ui/qmldir scripts/smoke/rows/hyprland-consent.sh bin/lib/dbus_wire.py scripts/smoke/fonts.sh
set -euo pipefail
source "$repo/scripts/smoke/fonts.sh"
expected_errors+=('NoticeHost[.]qml.*Unable to assign [[]undefined[]] to QString')
drift="$home/.config/vgshell/plugins/acme.drift"
drift_b="$home/.config/vgshell/plugins/acme.drift-b"
drift_qmldir="$repo/shell/Ui/qmldir"
drift_type="$repo/shell/Ui/DriftMark.qml"
drift_owed() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["notices"]["restart"]))'; }
drift_drawn() { ipc smoke noticeDrawn | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps(d[sys.argv[1]]))' "$1"; }
drift_revision() { ipc shell listPlugins | py_reply 'import json,sys; rows=[p["revision"] for p in json.load(sys.stdin)["plugins"] if p["id"] == sys.argv[1]]; print(rows[0] if rows else "absent")' "$1"; }
# `sandboxed` when the shell the row addresses has the sandbox's runtime
# directory in its environment and is the pid the sandbox's lock names.
drift_sandboxed() {
  local held
  grep -q -z -x -F -e "XDG_RUNTIME_DIR=$rt_dir" -- "/proc/$shell_qs_pid/environ" || { echo "runtime-dir=other"; return; }
  IFS= read -r held <"$rt_dir/vgshell.lock" || held=""
  if [[ $held == "$shell_qs_pid" ]]; then echo sandboxed; else echo "lock=[$held] shell=$shell_qs_pid"; fi
}
# The live pid the sandbox's lock names once it is no longer OLD_PID, the
# relaunched shell's, else `none`.
drift_relaunched() { # OLD_PID
  local pid
  if IFS= read -r pid 2>/dev/null <"$rt_dir/vgshell.lock" && [[ $pid =~ ^[0-9]+$ && $pid != "$1" && -d /proc/$pid ]]; then echo "$pid"; else echo none; fi
}
drift_relaunch_deadline_ms=120000
# The stand-in package database. It holds no lock until the font block.
drift_db="$sandbox/core-drift-pacman"
drift_fonts="$repo/shell/assets/fonts"
drift_copy_dir="$rt_dir/vgshell/fonts"
drift_faces_before="$sandbox/core-drift-faces.before"
# drift_watch_hold: `held` once the shell's core watcher holds an inotify
# watch on the stand-in database, the watcher's own sign that it saw a core
# change and the lock, else `watching`, or `no-watcher` when no child of
# the shell runs --watch-core. The kernel prints each watch in fdinfo as
# `inotify wd:%x ino:%lx ...` (fs/notify/fdinfo.c).
drift_watch_hold() {
  python3 - "$shell_qs_pid" "$drift_db" <<'PY'
import os, sys
qs, database = sys.argv[1:]
try:
    ino = " ino:%x " % os.stat(database).st_ino
    children = set()
    for task in os.listdir(f"/proc/{qs}/task"):
        with open(f"/proc/{qs}/task/{task}/children") as fh:
            children.update(fh.read().split())
except OSError as exc:
    print(f"unreadable={type(exc).__name__}")
    sys.exit(0)
state = "no-watcher"
for pid in sorted(children):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as fh:
            argv = fh.read().split(b"\0")
        if b"--watch-core" not in argv:
            continue
        state = "watching"
        for name in os.listdir(f"/proc/{pid}/fdinfo"):
            with open(f"/proc/{pid}/fdinfo/{name}") as fh:
                if any(line.startswith("inotify ") and ino in line for line in fh.read().splitlines()):
                    state = "held"
    except OSError:
        continue
print(state)
PY
}
# drift_faces [BEFORE]: the font files the shell maps outside the bundled
# directory, one path per line; with BEFORE, the comma-joined ones BEFORE
# does not list, or `none`. Run A of VGS-2359 drew the restart notice with
# the bundled fonts' glyph numbers from such fallback faces.
drift_faces() {
  python3 - "$shell_qs_pid" "$drift_fonts" "${1:-}" <<'PY'
import os, re, sys
qs, bundled, before = sys.argv[1:]
font = re.compile(r"\.(ttf|otf|ttc|otc|pfb|pfa|woff2?)$", re.IGNORECASE)
try:
    with open(f"/proc/{qs}/maps") as fh:
        lines = fh.read().splitlines()
    if before:
        with open(before) as fh:
            known = set(fh.read().splitlines())
    else:
        known = None
except OSError as exc:
    print(f"unreadable={type(exc).__name__}")
    sys.exit(1)
faces = set()
for line in lines:
    parts = line.split(None, 5)
    if len(parts) < 6:
        continue
    path = parts[5].removesuffix(" (deleted)")
    if font.search(path) and os.path.dirname(path) != bundled:
        faces.add(path)
if known is None:
    print("\n".join(sorted(faces)))
else:
    print(",".join(sorted(faces - known)) or "none")
PY
}
# drift_copies: `copies` once the shell maps the font copy each of its
# VGSHELL_FONT_SANS and VGSHELL_FONT_MONO names, a file of the sandbox
# runtime's vgshell/fonts at the inode its path names now, and maps no file
# of the bundled font directory, deleted or not; else each difference.
drift_copies() {
  font_copies_read "$shell_qs_pid" "$drift_fonts" "$drift_copy_dir"
}
# drift_font_env NAME: the value of the shell's environment variable NAME,
# `unset` when it has none.
drift_font_env() {
  python3 - "$shell_qs_pid" "$1" <<'PY'
import os, sys
qs, name = sys.argv[1:]
try:
    with open(f"/proc/{qs}/environ", "rb") as fh:
        env = dict(item.split(b"=", 1) for item in fh.read().split(b"\0") if b"=" in item)
except OSError as exc:
    print(f"unreadable={type(exc).__name__}")
    sys.exit(0)
value = env.get(name.encode())
print("unset" if value is None else os.fsdecode(value))
PY
}
# drift_sans_copy: `current` when the shell's VGSHELL_FONT_SANS names the
# copy of the bundled sans file's bytes as they are now, a file of the
# sandbox runtime's vgshell/fonts named by those bytes' SHA-256 and holding
# them; else what it names.
drift_sans_copy() {
  local named want
  named="$(drift_font_env VGSHELL_FONT_SANS)" || return
  want="$(sha256sum -- "$drift_fonts/InterVariable.ttf")" || return
  want="$drift_copy_dir/${want%% *}.ttf"
  if [[ $named == "$want" ]] && cmp -s -- "$named" "$drift_fonts/InterVariable.ttf"; then echo current; else echo "named=$named"; fi
}
# drift_message: the message the restart notice draws, as text.
drift_message() { ipc smoke noticeDrawn | py_reply 'import json,sys; print(json.load(sys.stdin)["message"])'; }
# drift_reads NAME TEXT: `reads` when tesseract finds every word of TEXT, in
# order, among the words of a capture of the nested output, kept as
# $smoke_log_dir/core-drift-NAME.png; else `unread=` and the words it found.
# Text shaped with one font's glyph numbers and drawn from another font's
# file reads as other letters (the VGS-2359 cause note's decode).
drift_reads() { # NAME TEXT
  local socket output png="$smoke_log_dir/core-drift-$1.png" words status=0
  socket="$(shot_socket "$rt_dir" "$nested_socket")" || return
  output="$(first_name)" || return
  shot_grim "$socket" "$rt_dir" -o "$output" -t png "$png" || { echo "capture=failed"; return; }
  words="$(tesseract "$png" - 2>"$sandbox/core-drift-ocr.err")" || status=$?
  if [[ $status != 0 ]]; then echo "ocr=failed status=$status $(head -c 200 -- "$sandbox/core-drift-ocr.err")"; return; fi
  python3 -c '
import re, sys
want = re.findall(r"[a-z0-9]+", sys.argv[1].lower())
got = re.findall(r"[a-z0-9]+", sys.stdin.read().lower())
found = any(got[i:i + len(want)] == want for i in range(len(got) - len(want) + 1))
print("reads" if want and found else "unread=" + " ".join(got)[:400])
' "$2" <<<"$words"
}
# drift_read_poll LABEL NAME TEXT: drift_reads again until it reads `reads`
# or smoke_poll_bound_ms has passed, timed by the clock rather than counted
# in steps, since each capture and OCR pass takes about a second.
drift_read_poll() { # LABEL NAME TEXT
  local got deadline=$(( $(now_ms) + smoke_poll_bound_ms ))
  while :; do
    got="$(drift_reads "$2" "$3")" || got="reader-failed status=$?"
    [[ $got != reads ]] || { ok "$1"; return; }
    (( $(now_ms) < deadline )) || break
    sleep 0.2
  done
  fail "$1: got $got"
}

[[ $shell_tree == "$repo" ]] || fail "the row needs the sandbox's own tree as the running shell, found $shell_tree"
mkdir -p -- "$drift_db"
printf '#!/bin/sh\nprintf "%%s\\n" %q\n' "$drift_db/" >"$shim/pacman-conf"
chmod 755 "$shim/pacman-conf"
install_plugin_copy acme.drift acme.drift Drift
install_plugin_copy acme.drift acme.drift-b DriftB
expected_errors+=('plugins: acme\.drift failed to load: ')
rescan "rescan after adding the drift fixtures answers ok"
expect_poll "the drift fixture is discovered" True plugin_known acme.drift
expect_poll "the second drift fixture is discovered" True plugin_known acme.drift-b
expect "enabling the drift fixture is allowed" ok ipc shell setPluginEnabled acme.drift true
expect "enabling the second drift fixture is allowed" ok ipc shell setPluginEnabled acme.drift-b true
expect "the panel summons before anything changes" ok ipc shell summon panel acme.drift '{}'
expect "the panel hides" ok ipc shell hide panel acme.drift

# Acceptance: a plugin-only change over an unchanged core still hot-loads.
# Must-fail control: the same kind of plugin change after coreChanged is
# held below, where the listed revision must not move and `scan held` must
# be logged.
drift_before="$(drift_revision acme.drift)"
printf 'import QtQuick\nItem { width: 24; height: 24 }\n' >"$drift/Mark.qml"
rescan "rescan after a plugin-only drift change answers ok"
drift_after="$(drift_revision acme.drift)"
if [[ $drift_after != "$drift_before" && $drift_after != absent ]]; then ok "the plugin-only change publishes a new revision"; else fail "the plugin-only change did not publish a new revision: before=$drift_before after=$drift_after"; fi
expect "the changed plugin revision summons without restart debt" ok ipc shell summon panel acme.drift '{}'
expect "the changed plugin revision hides" ok ipc shell hide panel acme.drift
expect "the plugin-only change owes no restart notice" false drift_owed

# Must-fail control for the log reader and unchanged-core notice rule: a
# real plugin load failure increments the failed-load count, refuses the
# summon, and still owes no restart.
loads_before="$(log_lines 'plugins: acme\.drift failed to load: ')" || fail "the instance log is unreadable before the defect control"
printf 'import QtQuick\nimport qs.Ui\nDriftAbsent {}\n' >"$drift/Mark.qml"
rescan "rescan after the plugin took a type no core has answers ok"
expect "control: the summon of the plugin's own defect is refused" "refused: build-failed=acme.drift" ipc shell summon panel acme.drift '{}'
expect_log "control: the core logged the failed build" "$((loads_before + 1))" 'plugins: acme\.drift failed to load: '
expect "control: a build failure over an unchanged core owes no restart notice" false drift_owed
expect "control: no notice is drawn" absent ipc smoke noticeDrawn
printf 'import QtQuick\nItem { width: 28; height: 28 }\n' >"$drift/Mark.qml"
rescan "rescan after the plugin defect is restored answers ok"
drift_open_revision="$(drift_revision acme.drift)"
expect "the restored panel summons and stays open" ok ipc shell summon panel acme.drift '{}'
expect "the restored panel has a live build record" True record_exists acme.drift

# Acceptance: the core watcher raises restart debt with no rescan. If the
# watcher is broken, this poll never sees the notice.
owed_logs="$(log_lines 'notices: restart=owed')" || fail "the instance log is unreadable before the core change"
drift_title_warnings="$(log_lines 'NoticeHost[.]qml.*Unable to assign [[]undefined[]] to QString')" || fail "the instance log is unreadable before the notice title binds"
loads_after_control="$(log_lines 'plugins: acme\.drift failed to load: ')" || fail "the instance log is unreadable after the defect control"
cp -- "$drift_qmldir" "$sandbox/core-drift-qmldir.orig"
printf 'import QtQuick\nItem {\n    width: 20\n    height: 20\n}\n' >"$drift_type"
printf 'DriftMark 1.0 DriftMark.qml\n' >>"$drift_qmldir"
expect_poll "the core watcher raises restart debt without a rescan" true drift_owed
expect "the restart notice was raised once" "$((owed_logs + 1))" log_lines 'notices: restart=owed'
expect_poll "the restart notice is the one notice surface" 1 layer_count vgs:notice
expect_poll "the restart notice names the action" '"Restart to update"' drift_drawn title
expect "the restart notice offers Restart and Not now" '["Restart", "Not now"]' drift_drawn actions
expect "the restart notice draws no Show command row" '[]' drift_drawn rows
expect "no row of the notice's body draws a command" '[]' drift_drawn rows
expect "a notice without key rows adds no undefined string warning" "$drift_title_warnings" log_lines 'NoticeHost[.]qml.*Unable to assign [[]undefined[]] to QString'

# Must-fail control for the hot-load acceptance: after coreChanged, a plugin
# source edit is held. The listed revision stays at the open panel's old
# revision, the old instance stays alive, and no load failure is added.
held_before="$(log_lines 'plugins: scan held reason=core-changed')" || fail "the instance log is unreadable before the held scan"
printf 'import QtQuick\nimport qs.Ui\nDriftMark {}\n' >"$drift/Mark.qml"
rescan "rescan after the core changed and the plugin took the new type answers ok"
expect_log "the differing scan is held while restart is owed" "$((held_before + 1))" 'plugins: scan held reason=core-changed'
expect "the held scan leaves the listed plugin revision unchanged" "$drift_open_revision" drift_revision acme.drift
expect "the open panel keeps its live build record" True record_exists acme.drift
expect "the held scan adds no failed load" "$loads_after_control" log_lines 'plugins: acme\.drift failed to load: '
expect "the held scan does not raise the notice again" "$((owed_logs + 1))" log_lines 'notices: restart=owed'

type_keys -k Escape || fail "sending Escape to the restart notice failed"
expect_poll "Escape closes the restart notice" false drift_owed
expect_poll "the closed restart notice leaves no surface" 0 layer_count vgs:notice
expect "the compiled panel hides after restart debt" ok ipc shell hide panel acme.drift
expect "the compiled panel summons again under restart debt" ok ipc shell summon panel acme.drift '{}'
expect "the compiled panel hides again" ok ipc shell hide panel acme.drift

# Acceptance: a never-compiled entry is refused before Qt.createComponent.
# Must-fail control: the unchanged-core defect above proves the failed-load
# counter can move when the engine is allowed to compile. A floating TUI
# run held live meanwhile holds the owed notice back, so it never comes up
# in the middle of a setup flow; it shows once the run ends. The reading
# while the run is live and the one after it are each other's control.
hold_runs
expect "a core TUI opens while the restart notice is closed" ok ipc shell openTui core/doctor
expect_poll "the core TUI's run is live" busy key_idle core/doctor
expect "the never-built panel is refused because restart is owed" "refused: restart=owed" ipc shell summon panel acme.drift-b '{}'
expect "the refused first build adds no failed load" "$loads_after_control" log_lines 'plugins: acme\.drift failed to load: '
expect "the refused first build raises the restart notice again" "$((owed_logs + 2))" log_lines 'notices: restart=owed'
expect "the owed restart notice is held while a TUI run is live" true drift_owed
expect "the held restart notice draws no dialog" absent ipc smoke noticeDrawn
expect "the held restart notice maps no surface" 0 layer_count vgs:notice
release_runs
expect_run_end "the core TUI's run ends" core/doctor
expect_poll "the restart notice is one surface again" 1 layer_count vgs:notice
expect_poll "the restart notice holds the keyboard" true ipc smoke noticeFocused
expect_poll "Restart holds the keyboard first" '"Restart"' drift_drawn focused

# Restart, pressed only on the sandbox's own shell. The runner Hyprland's
# dispatch starts is no child of the harness, so its process group joins
# the teardown's, as in rows/start-order.sh.
drift_old="$shell_qs_pid"
drift_new=none
drift_where="$(drift_sandboxed)" || drift_where=unreadable
if [[ $drift_where == sandboxed ]]; then
  drift_deadline=$(( $(now_ms) + drift_relaunch_deadline_ms ))
  ok "the shell that draws the notice is the sandbox's"
  type_keys -k Return || fail "sending Return to Restart failed"
  while :; do
    drift_new="$(drift_relaunched "$drift_old")"
    [[ $drift_new == none ]] || break
    (( $(now_ms) < drift_deadline )) || break
    sleep 0.2
  done
else
  fail "Restart is not pressed: $drift_where"
  type_keys -k Escape || fail "sending Escape to the unpressed notice failed"
fi
if [[ $drift_new != none ]]; then
  ok "Restart brought a new shell: pid=$drift_new replaced pid=$drift_old"
  shell_pid="$(awk '$1 == "PPid:" { print $2 }' "/proc/$drift_new/status")" || shell_pid=""
  if [[ $shell_pid =~ ^[0-9]+$ ]] && pgid="$(ps -o pgid= -p "$shell_pid")"; then pgids+=("${pgid// /}"); else fail "the relaunched shell's runner is unreadable: [$shell_pid]"; fi
  if shell_answers "$shell_tree" "$shell_log"; then
    expect "the relaunched shell answers as the guarded instance" true ipc shell guarded
    expect "the relaunched shell summons the panel that needs the new type" ok ipc shell summon panel acme.drift '{}'
    expect "the relaunched shell summons the never-built copy" ok ipc shell summon panel acme.drift-b '{}'
    expect "the relaunched shell owes no restart notice" false drift_owed
    expect "the panel hides after the restart" ok ipc shell hide panel acme.drift
    expect "the copy hides after the restart" ok ipc shell hide panel acme.drift-b
  fi
elif [[ $drift_where == sandboxed ]]; then
  fail "Restart brought no live replacement shell before the restart deadline: deadline_ms=$drift_relaunch_deadline_ms lock=[$(cat -- "$rt_dir/vgshell.lock" 2>/dev/null)]"
fi

# The fixtures and the type go, and the sandbox's tree starts again over
# the core as it was.
expect "disabling the drift fixture is allowed" ok ipc shell setPluginEnabled acme.drift false
expect "disabling the second drift fixture is allowed" ok ipc shell setPluginEnabled acme.drift-b false
rm -rf -- "${drift:?}" "${drift_b:?}"
cp -- "$sandbox/core-drift-qmldir.orig" "$drift_qmldir"
rm -f -- "${drift_type:?}"
if stop_shell && start_shell "$repo" "$sandbox/core-drift-qs.log"; then
  expect "the shell started again owes no restart notice" false drift_owed
fi

# Acceptance (VGS-2359): pacman replaces each file by unlinking it and
# writing the new one in place, under its database lock, so mid-transaction
# the shell's own files are absent or partly written. The shell draws from
# private font copies its start made (the VGS-2422 block below), so the
# notice maps those and no fallback face. The
# watcher reports the change as pending while the lock is held,
# which holds first builds at once, and the notice waits until the lock
# goes. The fonts go first, so a watcher that ignores the lock opens the
# notice while they are absent. acme.drift-c is enabled and never built, so
# its summon under the lock reads the hold and owes the notice.
# Must-fail control: the same block against bin/vgshell-scan before
# VGS-2359 raises the notice while the lock is held, mapping fallback faces.
drift_c="$home/.config/vgshell/plugins/acme.drift-c"
install_plugin_copy acme.drift acme.drift-c DriftC
rescan "rescan after adding the held-transaction fixture answers ok"
expect_poll "the held-transaction fixture is discovered" True plugin_known acme.drift-c
expect "enabling the held-transaction fixture is allowed" ok ipc shell setPluginEnabled acme.drift-c true
pending_logs="$(log_lines 'plugins: core=pending')" || fail "the instance log is unreadable before the font block"
drift_faces >"$drift_faces_before" || fail "the shell's mapped faces are unreadable before the font block"
mkdir -p -- "$sandbox/core-drift-fonts"
cp -p -- "$drift_fonts/InterVariable.ttf" "$drift_fonts/JetBrainsMono-Variable.ttf" "$sandbox/core-drift-fonts/"
: >"$drift_db/db.lck"
rm -- "${drift_fonts:?}/InterVariable.ttf" "${drift_fonts:?}/JetBrainsMono-Variable.ttf"
printf 'import QtQuick\nItem {\n    width: 20\n    height: 20\n}\n' >"$drift_type"
printf 'DriftMark 1.0 DriftMark.qml\n' >>"$drift_qmldir"
expect_poll "the core watcher holds its report while the package lock is held" held drift_watch_hold
expect_log "the shell reads the change as pending while the package lock is held" "$((pending_logs + 1))" 'plugins: core=pending'
expect "a first build while the package lock is held is refused" "refused: restart=owed" ipc shell summon panel acme.drift-c '{}'
expect "no restart is owed while the package lock is held" false drift_owed
expect "no notice is drawn while the package lock is held" absent ipc smoke noticeDrawn
expect "the shell maps no new fallback face while the package lock is held" none drift_faces "$drift_faces_before"
cp -p -- "$sandbox/core-drift-fonts/InterVariable.ttf" "$sandbox/core-drift-fonts/JetBrainsMono-Variable.ttf" "$drift_fonts/"
rm -- "${drift_db:?}/db.lck"
expect_poll "the core watcher raises restart debt once the package lock goes" true drift_owed
expect_poll "the restart notice after the transaction is the one notice surface" 1 layer_count vgs:notice
expect_poll "the restart notice after the transaction names the action" '"Restart to update"' drift_drawn title
expect_poll "the restart notice maps the shell's font copies and no bundled font file" copies drift_copies
expect "the restart notice maps no fallback face the shell did not map before" none drift_faces "$drift_faces_before"

cp -- "$sandbox/core-drift-qmldir.orig" "$drift_qmldir"
rm -f -- "${drift_type:?}"
expect "disabling the held-transaction fixture is allowed" ok ipc shell setPluginEnabled acme.drift-c false
rm -rf -- "${drift_c:?}"
if stop_shell && start_shell "$repo" "$sandbox/core-drift-qs.log"; then
  expect "the shell started after the transaction block owes no restart notice" false drift_owed
fi

# Acceptance (VGS-2422): a package update that writes a different font over
# a bundled font file in place leaves the running shell drawing the font it
# started with. The main thread shapes text with the faces it opened at
# start, and each window's render thread opens the font files again at its
# first frame (the VGS-2359 cause note), so a window that opened the
# bundled path would draw the start's glyph numbers from the new file. The
# shell draws from copies bin/vgshell made at its start instead, so the
# restart notice the change raises and a panel window first drawn after it
# read as the text they draw. The mono font's bytes go over the sans file,
# unlinked and written as pacman does. A restart then loads a copy of the
# new bytes and removes the old copy. The panel's text names the theme's
# sans family, which the new bytes do not hold, so after the restart it
# reads in the family Qt picks for it, while the shell's sans font is the
# new file.
# Must-fail control: this block against shell/Commons/Theme.qml and
# bin/vgshell before VGS-2422 draws the notice's message with the wrong
# glyphs and maps the rewritten bundled file.
drift_d="$home/.config/vgshell/plugins/acme.drift-d"
drift_words="Readable after the update"
install_plugin_copy acme.drift acme.drift-d DriftD
printf 'import QtQuick\nimport qs.Ui\nItem {\n    property var shell: null\n    implicitWidth: 720\n    implicitHeight: 160\n    function open(payloadJson) {}\n    function close() {}\n    Label {\n        anchors.centerIn: parent\n        role: "display"\n        text: "%s"\n    }\n}\n' "$drift_words" >"$drift_d/Panel.qml"
rescan "rescan after adding the replaced-font fixture answers ok"
expect_poll "the replaced-font fixture is discovered" True plugin_known acme.drift-d
expect "enabling the replaced-font fixture is allowed" ok ipc shell setPluginEnabled acme.drift-d true
expect "the replaced-font panel builds before the font changes" ok ipc shell summon panel acme.drift-d '{}'
drift_read_poll "the replaced-font panel reads as its text before the font changes" panel-before "$drift_words"
expect "the replaced-font panel hides" ok ipc shell hide panel acme.drift-d
expect_poll "the replaced-font panel leaves no surface" 0 layer_count vgs:panel
expect "the shell maps its start's font copies before the font changes" copies drift_copies
drift_sans_start="$(drift_font_env VGSHELL_FONT_SANS)" || fail "the shell's environment is unreadable before the font changes"
drift_faces >"$drift_faces_before" || fail "the shell's mapped faces are unreadable before the font changes"
mkdir -p -- "$sandbox/core-drift-fonts"
cp -p -- "$drift_fonts/InterVariable.ttf" "$sandbox/core-drift-fonts/"
rm -- "${drift_fonts:?}/InterVariable.ttf"
cat -- "$drift_fonts/JetBrainsMono-Variable.ttf" >"$drift_fonts/InterVariable.ttf"
expect_poll "the core watcher raises restart debt for the rewritten font" true drift_owed
expect_poll "the restart notice after the rewrite is the one notice surface" 1 layer_count vgs:notice
expect_poll "the restart notice after the rewrite names the action" '"Restart to update"' drift_drawn title
drift_text="$(drift_message)" || fail "the restart notice's message is unreadable"
drift_read_poll "the restart notice first drawn after the rewrite reads as its message" notice-rewritten "$drift_text"
expect "the restart notice maps the start's font copies and no bundled font file" copies drift_copies
expect "the restart notice maps no fallback face the shell did not map before" none drift_faces "$drift_faces_before"
expect "the shell keeps the sans copy it started with" "$drift_sans_start" drift_font_env VGSHELL_FONT_SANS
expect_poll "the restart notice holds the keyboard after the rewrite" true ipc smoke noticeFocused
type_keys -k Escape || fail "sending Escape to the restart notice after the rewrite failed"
expect_poll "Escape closes the restart notice after the rewrite" false drift_owed
expect_poll "the closed notice after the rewrite leaves no surface" 0 layer_count vgs:notice
expect "the built panel summons a new window after the rewrite" ok ipc shell summon panel acme.drift-d '{}'
drift_read_poll "the panel window first drawn after the rewrite reads as its text" panel-rewritten "$drift_words"
expect "the panel window maps the start's font copies and no bundled font file" copies drift_copies
expect "the panel hides after the rewrite" ok ipc shell hide panel acme.drift-d
if stop_shell && start_shell "$repo" "$sandbox/core-drift-qs.log"; then
  expect "the restarted shell loads its sans font from a copy of the rewritten file" current drift_sans_copy
  if [[ $drift_sans_start == "$drift_copy_dir"/* && ! -e $drift_sans_start ]]; then ok "the restart removes the copy of the font it replaced"; else fail "the restart left the copy of the font it replaced: $drift_sans_start"; fi
  expect "the restarted shell builds the panel" ok ipc shell summon panel acme.drift-d '{}'
  drift_read_poll "the panel the restarted shell draws reads as its text" panel-restarted "$drift_words"
  expect "the restarted shell maps its font copies and no bundled font file" copies drift_copies
  expect "the panel hides after the restart" ok ipc shell hide panel acme.drift-d
fi

cp -p -- "$sandbox/core-drift-fonts/InterVariable.ttf" "$drift_fonts/"
expect "disabling the replaced-font fixture is allowed" ok ipc shell setPluginEnabled acme.drift-d false
rm -rf -- "${drift_d:?}"
rm -f -- "${shim:?}/pacman-conf"
rm -rf -- "${drift_db:?}" "${sandbox:?}/core-drift-fonts"
if stop_shell && start_shell "$repo" "$sandbox/core-drift-qs.log"; then
  expect "the shell started after the font blocks owes no restart notice" false drift_owed
fi
