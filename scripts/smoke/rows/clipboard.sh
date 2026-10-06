# The clipboard history, vgs.clipboard: a first-party service and overlay.
# Its manifest sets `optIn`, so it is off until its plugins row exists; the
# row reads that no disabled list names it, enables it through the manager,
# which writes the row, copies on the nested instance's own clipboard with the real wl-copy, and
# reads the history back through the plugin's IPC and the drawn rows through
# the probe. A copy made before the plugin is enabled, a text copy and an
# image copy are recorded, a repeat moves to the front, and a copy made with
# `wl-copy --sensitive` is not recorded, read after a later copy is. The
# image is larger than the largest pipe the host allows, so its capture and
# its paste go through the real wl-copy while the copy's first transfer
# waits on the helper's stdin. A watcher ended by its PID is started again,
# and the copy after that is recorded. The store's directories and files
# are owner-only, and the overlay decodes the image entry's thumbnail from
# the file the store names by the entry's id. The plugin's key shows in the
# Key Hints window. SUPER+CTRL+V, typed on the nested seat, opens the
# history; typing filters the drawn rows; Enter pastes the selected entry
# into the window that had the keyboard: a window whose desktop entry is a
# terminal receives V with Ctrl and Shift, another application V with Ctrl
# alone, each after the window has the keyboard back from the overlay, read
# from the toplevel helper's keyboard, key and modifier log, and a window
# no desktop entry names receives no key and a toast shows. A change the
# service refuses shows a toast too. Shift+Enter sends no key. Ctrl+P pins,
# Delete removes an image entry and its file, and Shift+Delete then Enter
# clears all but the pin. Disabling the plugin leaves no watcher among the
# shell's children.
# The control is one copy of the plugin with eight rules removed, each read
# by the assertion that holds it: a shortcut that opens nothing, a watcher
# whose lines are dropped, a filter the overlay does not send, a terminal
# sent the application's chord, a helper without the secret checks, a
# thumbnail whose URL names another directory, a refusal without its toast,
# and a service that starts no watcher again.
# Every clipboard program runs with the nested socket in its environment.
# `input:resolve_binds_by_sym` is on while the row types its key
# (runtime-hyprland-capture.md), and the row puts the harness hyprland.lua
# back at its end.
# No latency is measured; each reading polls every 200 ms for up to 5 s,
# the watcher's return for up to 8 s, and a control that reads nothing
# happen reads it for 2 s, or for those 8 s where it waits for no watcher.
# inputs: shell/plugins/vgs.clipboard/* shell/plugins/vgs.keyhints/* shell/Core/Compositor.qml shell/Core/Dispatch.js shell/Core/Capabilities.qml shell/Core/IpcRegistry.qml shell/Core/ShortcutRegistry.qml shell/Core/HyprlandLayer.js shell/Core/Toasts.qml shell/Core/PluginLogic.js shell/Hosts/Summon* shell/Hosts/OverlaySurface.qml shell/Hosts/PluginSlot.qml shell/Hosts/ServiceHost.qml shell/Ui/foundation/KeyNav* shell/Ui/layout/ListCursor* shell/Ui/layout/ListItem.qml shell/Ui/layout/ScrollArea.qml shell/Ui/controls/TextField.qml shell/Ui/feedback/Dialog.qml scripts/smoke/toplevel/* scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail

for clip_tool in wl-copy wl-paste; do
  command -v -- "$clip_tool" >/dev/null || { fail "clipboard: $clip_tool is unavailable"; return 0; }
done
clip_store="$home/.local/state/vgshell/clipboard"
clip_image="$sandbox/clipboard-image.png"
clip_plugin="$repo/shell/plugins/vgs.clipboard"
# A 640 by 640 opaque PNG of seeded noise, built here so the row ships no
# binary. The harness's solid_png does not serve: one colour compresses to
# a few kilobytes, and the row needs a file no pipe holds. The cat that
# wl-copy sends a copy with grows its pipe: read with F_GETPIPE_SZ on host
# cachy on 2026-10-04, GNU coreutils 9.11 grew it from 65,536 to 524,288
# bytes, and with a 256 by 256 image of the same noise the row passed
# without the helper's close. /proc/sys/fs/pipe-max-size is the largest
# pipe a user's process can ask for.
python3 - "$clip_image" <<'PY'
import random, struct, sys, zlib
def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
noise = random.Random(777)
rows = b"".join(b"\x00" + noise.randbytes(3 * 640) for _ in range(640))
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 640, 640, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows, 1)) + chunk(b"IEND", b"")
open(sys.argv[1], "wb").write(png)
PY
expect "the row's image is larger than the largest pipe" True python3 -c 'import os,sys; print(os.path.getsize(sys.argv[1]) > int(open("/proc/sys/fs/pipe-max-size").read()))' "$clip_image"

# clip_copy ARGS...: wl-copy on the nested clipboard. Its provider keeps no
# stream of the row's, so no reader waits on it.
clip_copy() { "${shell_env[@]}" wl-copy "$@" >/dev/null 2>&1 </dev/null; }
clip_copy_file() { "${shell_env[@]}" wl-copy --type "$1" >/dev/null 2>&1 <"$2"; }
clip_copy_secret() { printf '%s' "$1" | "${shell_env[@]}" wl-copy --sensitive >/dev/null 2>&1; }
# clip_holds: the nested clipboard's text. clip_holds_image: `same` when its
# PNG bytes are the fixture's.
clip_holds() { "${shell_env[@]}" wl-paste --no-newline; }
clip_holds_image() { if "${shell_env[@]}" wl-paste --type image/png | cmp -s -- - "$clip_image"; then echo same; else echo differs; fi; }
clip_invoke() { ipc vgs.clipboard invoke "$1" "${2:-}"; }
# clip_labels [FILTER]: the history's rows for FILTER as the service
# answers them, each [type, label], pinned first.
clip_labels() { clip_invoke rows "${1:-}" | py_reply 'import json,sys; print(json.dumps([[r["type"], r["label"]] for r in json.load(sys.stdin)["rows"]]))'; }
clip_pins() { clip_invoke rows "" | py_reply 'import json,sys; print(json.dumps([r["label"] for r in json.load(sys.stdin)["rows"] if r["pinned"]]))'; }
clip_has() { clip_invoke rows "" | py_reply 'import json,sys; print(any(r["label"] == sys.argv[1] for r in json.load(sys.stdin)["rows"]))' "$1"; }
clip_count() { clip_invoke rows "" | py_reply 'import json,sys; print(json.load(sys.stdin)["total"])'; }
clip_first() { clip_invoke rows "" | py_reply 'import json,sys; print(json.load(sys.stdin)["rows"][0]["label"])'; }
clip_id() { clip_invoke rows "" | py_reply 'import json,sys; print(next(r["id"] for r in json.load(sys.stdin)["rows"] if r["label"] == sys.argv[1]))' "$1"; }
# clip_drawn: the labels of the rows the overlay draws, in order; clip_selected: the selected row's label.
clip_drawn() { ipc smoke itemValues overlay vgs.clipboard ListItem text | py_reply 'import json,sys; print(json.dumps([r["text"] for r in json.load(sys.stdin)]))'; }
clip_drawn_count() { ipc smoke itemValues overlay vgs.clipboard ListItem text | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
clip_selected() { ipc smoke itemValues overlay vgs.clipboard ListItem text,highlighted | py_reply 'import json,sys; print(json.dumps([r["text"] for r in json.load(sys.stdin) if r["highlighted"]]))'; }
# clip_thumbs: the images the overlay draws from a file, each [path, status]
# once: the thumbnail of each image entry's row, and the preview while an
# image entry is selected.
clip_thumbs() { ipc smoke images overlay vgs.clipboard | py_reply 'import json,sys; print(json.dumps(sorted({(r[0], r[1]) for r in json.load(sys.stdin) if r[0] != ""})))'; }
clip_read() { ipc smoke readInstance "$1" vgs.clipboard "$2"; }
clip_lent() { ipc shell lent | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps([[s for s in d["shortcuts"] if s.startswith("vgs.clipboard")], [t for t in d["ipcTargets"] if t == "vgs.clipboard"]]))'; }
# clip_listed: whether the user file's disabledPlugins and its plugins name
# the plugin, as a JSON pair.
clip_listed() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps(["vgs.clipboard" in d.get("disabledPlugins", []), any(r.get("id") == "vgs.clipboard" for r in d.get("plugins", []))]))' "$home/.config/vgshell/shell.json"; }
# clip_toasts: the plugin's toasts, shown and waiting. clip_no_toast_past N:
# `quiet` when their count stays at or under N for 2 s.
clip_toasts() { ipc shell lent | py_reply 'import json,sys; rows=json.load(sys.stdin)["toasts"]; print(sum(r["plugin"] == "vgs.clipboard" for k in ("visible", "waiting") for r in rows[k]))'; }
clip_no_toast_past() { local got; for _ in $(seq 1 10); do got="$(clip_toasts)" || return 1; ((got <= $1)) || { echo "$got"; return 0; }; sleep 0.2; done; echo quiet; }
# An id no entry has.
clip_no_id="$(printf 'f%.0s' $(seq 1 64))"
clip_modes() { python3 -c 'import os,stat,sys; print(" ".join(oct(stat.S_IMODE(os.stat(p).st_mode))[2:] for p in sys.argv[1:]))' "$@"; }
clip_image_files() { python3 -c 'import os,sys; print(len(os.listdir(sys.argv[1])))' "$clip_store/images"; }
# clip_watcher_pids: the PIDs of the shell's own children that watch the
# clipboard, on one line. clip_watchers: how many they are.
# clip_watcher_returns: 1 once the service runs one watcher again. A real
# wait: the service starts an ended watcher again on its own 5 s timer, in
# the running shell, so the reading polls for 8 s.
# clip_end_watcher LABEL: the one watcher ended by its PID, never by name,
# and read gone; `clip_ended` holds that PID.
clip_watcher_pids() { ps -e -o pid=,ppid=,args= | python3 -c 'import sys; print(" ".join(w[0] for w in (l.split(None, 2) for l in sys.stdin) if len(w) == 3 and w[1] == sys.argv[1] and "wl-paste --watch" in w[2]))' "$shell_qs_pid"; }
clip_watchers() { local pids; pids="$(clip_watcher_pids)" || return 1; wc -w <<<"$pids"; }
clip_watcher_returns() { local got; for _ in $(seq 1 40); do got="$(clip_watchers)" || return 1; [[ $got != 1 ]] || break; sleep 0.2; done; echo "$got"; }
clip_end_watcher() {
  clip_ended="$(clip_watcher_pids)" || clip_ended=unread
  [[ $clip_ended =~ ^[0-9]+$ ]] || { fail "$1: the watcher's PID reads $clip_ended, not one PID"; return 1; }
  kill -TERM "$clip_ended" || { fail "$1: ending the watcher, PID $clip_ended, failed"; return 1; }
  expect_poll "$1: the ended watcher leaves none" 0 clip_watchers
}
clip_key() { type_keys -M logo -M ctrl -k v -m ctrl -m logo; }
clip_focused() { expect_poll "${1:-the clipboard history holds the keyboard}" true ipc smoke activeFocusIn overlay vgs.clipboard; }
# clip_open LABEL: the history opened by its key and holding the keyboard.
clip_open() {
  clip_key || fail "$1: typing SUPER+CTRL+V failed"
  expect_poll "$1: SUPER+CTRL+V opens the clipboard history" 1 layer_count vgs:overlay
  clip_focused "$1: the open history holds the keyboard"
}
# clip_keys_of LOG FROM: what the window of LOG received after line FROM,
# in order, as a JSON list: `enter` and `leave` as the keyboard comes and
# goes, and for each key press the depressed modifier mask it arrived with:
# 4 is Ctrl and 5 Ctrl with Shift in the map wtype brings. FROM is read
# while the overlay has the keyboard, so `enter` before a mask says the key
# came after the overlay gave the keyboard back. clip_lines LOG: the lines
# LOG holds.
clip_lines() { python3 -c 'import sys; print(sum(1 for _ in open(sys.argv[1])))' "$1"; }
clip_keys_of() {
  python3 -c 'import json,sys
mask, out = 0, []
for line in list(open(sys.argv[1]))[int(sys.argv[2]):]:
    words = line.split()
    if words[:1] == ["modifiers"]: mask = int(words[1])
    elif words[:1] == ["keyboard"]: out.append(words[1])
    elif words[:1] == ["key"] and words[2] == "pressed": out.append(mask)
print(json.dumps(out))' "$1" "$2"
}
# clip_window LOG APP_ID TITLE: the toplevel helper mapped with the keyboard.
clip_window() {
  open_toplevel "$1" "$2" "$3" || { fail "the helper window $2 maps"; return 1; }
  expect_poll "the helper window $2 has the keyboard" "[\"$2\", \"$3\"]" active_window
}
# clip_entry ID NAME CATEGORIES: a desktop entry that names the helper
# window's class, which the core reads its kind from.
clip_entry() { printf '[Desktop Entry]\nType=Application\nName=%s\nExec=true\nStartupWMClass=%s\nCategories=%s\n' "$2" "$1" "$3" >"$home/.local/share/applications/$1.desktop"; }

mkdir -p "$home/.local/share/applications"
clip_entry smoke.clipboard-terminal "Clipboard terminal" "System;TerminalEmulator;"
clip_entry smoke.clipboard-app "Clipboard application" "Utility;"
hypr_lua_save clipboard
printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = true } })' >>"$home/.config/hypr/hyprland.lua"
expect "the nested instance reloads with typed keys reaching binds" ok hypr reload config-only

# A copy made before the plugin is enabled is the watcher's first event.
clip_copy "smoke before enable"
expect "no disabled list and no plugins row names the clipboard history" '[false, false]' clip_listed
expect "the clipboard history is off until enabled" False plugin_enabled vgs.clipboard
expect "enabling the clipboard history is allowed" ok ipc shell setPluginEnabled vgs.clipboard true
expect_poll "enabling wrote the plugins row" '[false, true]' clip_listed
expect_poll "the clipboard service is built" True record_exists vgs.clipboard
expect_poll "the service registered its shortcut and IPC target" '[["vgs.clipboard:toggle"], ["vgs.clipboard"]]' clip_lent
expect_poll "the store is ready" '"ready"' clip_read service store
expect_poll "the service runs one watcher" 1 clip_watchers
expect_poll "the copy made before the plugin was enabled is recorded" '[["text", "smoke before enable"]]' clip_labels

# The watcher ends while it is wanted: the service starts it again, and the
# new watcher records the copies below.
expected_errors+=('clipboard: watcher ended, started again in 5000 ms')
if clip_end_watcher "restart"; then
  expect "the service starts the watcher again" 1 clip_watcher_returns
  expect "the new watcher is another process" True python3 -c 'import sys; print(sys.argv[1] != sys.argv[2] and sys.argv[2].isdigit())' "$clip_ended" "$(clip_watcher_pids)"
fi

# Text, an image, a repeat and a secret.
clip_copy "Smoke Alpha one"
expect_poll "a text copy is recorded first" '[["text", "Smoke Alpha one"], ["text", "smoke before enable"]]' clip_labels
clip_copy_file image/png "$clip_image"
expect_poll "an image copy is recorded" '[["image", "PNG image"], ["text", "Smoke Alpha one"], ["text", "smoke before enable"]]' clip_labels
clip_copy "smoke beta two"
expect_poll "a second text copy is recorded" True clip_has "smoke beta two"
clip_copy "Smoke Alpha one"
expect_poll "a repeat moves its entry to the front and adds none" '[["text", "Smoke Alpha one"], ["text", "smoke beta two"], ["image", "PNG image"], ["text", "smoke before enable"]]' clip_labels
clip_copy_secret "smoke secret zeta"
expect_poll "the secret is on the nested clipboard" "smoke secret zeta" clip_holds
clip_copy "smoke after secret"
expect_poll "the copy after the secret is recorded" True clip_has "smoke after secret"
expect "a copy marked sensitive is not recorded" False clip_has "smoke secret zeta"
expect "the history holds five entries" 5 clip_count
clip_png="$(python3 -c 'import os,sys; print(os.path.join(sys.argv[1], "images", os.listdir(os.path.join(sys.argv[1], "images"))[0]))' "$clip_store")" || fail "the image file is unreadable"
expect_poll "the saved history names the last copy" True python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["entries"][0]["text"] == "smoke after secret")' "$clip_store/history.json"
expect "the store's directories and files are owner-only" "700 700 600 600" clip_modes "$clip_store" "$clip_store/images" "$clip_store/history.json" "$clip_png"
expect "the image file holds the copied bytes" same bash -c 'cmp -s -- "$1" "$2" && echo same' _ "$clip_png" "$clip_image"

# The key shows in the Key Hints window.
clip_hints_before="$(plugin_enabled vgs.keyhints)" || clip_hints_before=unread
clip_hint() { ipc smoke itemValues window vgs.keyhints BindField pluginId,bind | py_reply 'import json,sys; print(json.dumps([[r["bind"]["shortcut"], r["bind"]["key"]] for r in json.load(sys.stdin) if r["pluginId"] == "vgs.clipboard"]))'; }
expect "enabling Key Hints is allowed" ok ipc shell setPluginEnabled vgs.keyhints true
expect_poll "the Key Hints service is built" True record_exists vgs.keyhints
expect "Key Hints is summoned" ok ipc shell summon window vgs.keyhints '{}'
expect_poll "the Key Hints window lists the clipboard key" '[["toggle", "SUPER+CTRL+V"]]' clip_hint
expect "Key Hints is hidden" ok ipc shell hide window vgs.keyhints
if [[ $clip_hints_before != True ]]; then expect "Key Hints is disabled again" ok ipc shell setPluginEnabled vgs.keyhints false; fi

# A terminal: the key opens the history, typing filters it, Enter pastes.
if clip_window "$sandbox/clipboard-terminal.log" smoke.clipboard-terminal "Clipboard terminal"; then
  clip_terminal_pid="$toplevel_pid"
  expect "a closed history holds no surface" 0 layer_count vgs:overlay
  clip_open "terminal"
  expect_poll "the history draws its entries, newest first" '["smoke after secret", "Smoke Alpha one", "smoke beta two", "PNG image", "smoke before enable"]' clip_drawn
  expect "the first entry is selected" '["smoke after secret"]' clip_selected
  expect_poll "the image entry's thumbnail is decoded from the file the store names by its id" "[[\"$clip_png\", \"ready\"]]" clip_thumbs
  type_keys "ALPHA" || fail "typing the filter failed"
  expect_poll "typing filters the entries without case" '["Smoke Alpha one"]' clip_drawn
  clip_from="$(clip_lines "$sandbox/clipboard-terminal.log")"
  type_keys -k Return || fail "sending Return failed"
  expect_poll "Enter closes the history" 0 layer_count vgs:overlay
  expect_poll "a terminal has the keyboard back, then receives V with Ctrl and Shift" '["enter", 5]' clip_keys_of "$sandbox/clipboard-terminal.log" "$clip_from"
  expect "the pasted entry is on the clipboard" "Smoke Alpha one" clip_holds
  expect "a paste shows no toast" 0 clip_toasts

  # Shift+Enter puts the entry on the clipboard and sends no key.
  clip_open "copy"
  type_keys "beta" || fail "typing the filter failed"
  expect_poll "the filter finds the second entry" '["smoke beta two"]' clip_drawn
  clip_from="$(clip_lines "$sandbox/clipboard-terminal.log")"
  type_keys -M shift -k Return -m shift || fail "sending Shift+Return failed"
  expect_poll "Shift+Enter closes the history" 0 layer_count vgs:overlay
  expect_poll "Shift+Enter puts the entry on the clipboard" "smoke beta two" clip_holds
  expect_poll "the copied entry is first in the history" "smoke beta two" clip_first
  expect "Shift+Enter gives the terminal the keyboard back and no key" '["enter"]' clip_keys_of "$sandbox/clipboard-terminal.log" "$clip_from"
  close_toplevel "$clip_terminal_pid" "the terminal helper exits 0 on SIGTERM"
fi

# Another application: an image entry, pasted with Ctrl+V alone.
if clip_window "$sandbox/clipboard-app.log" smoke.clipboard-app "Clipboard application"; then
  clip_app_pid="$toplevel_pid"
  clip_open "application"
  type_keys "png" || fail "typing the filter failed"
  expect_poll "the filter finds the image entry" '["PNG image"]' clip_drawn
  clip_from="$(clip_lines "$sandbox/clipboard-app.log")"
  type_keys -k Return || fail "sending Return failed"
  expect_poll "Enter closes the history over an application" 0 layer_count vgs:overlay
  expect_poll "an application has the keyboard back, then receives V with Ctrl alone" '["enter", 4]' clip_keys_of "$sandbox/clipboard-app.log" "$clip_from"
  expect "the pasted image is on the clipboard under its type" same clip_holds_image
  close_toplevel "$clip_app_pid" "the application helper exits 0 on SIGTERM"
fi

# A window no desktop entry names: no key, a toast, the entry on the clipboard.
expected_errors+=('clipboard: paste key not sent: refused: input=unknown-application')
expected_errors+=('QML Image at .*/Overlay\.qml\[[0-9:]+\]: Cannot open: file://.*/clipboard/images-moved/')
if clip_window "$sandbox/clipboard-unknown.log" smoke.clipboard-unknown "Clipboard unknown"; then
  clip_unknown_pid="$toplevel_pid"
  clip_open "unknown"
  type_keys "before" || fail "typing the filter failed"
  expect_poll "the filter finds the first copy" '["smoke before enable"]' clip_drawn
  clip_from="$(clip_lines "$sandbox/clipboard-unknown.log")"
  type_keys -k Return || fail "sending Return failed"
  expect_poll "Enter closes the history over an unknown window" 0 layer_count vgs:overlay
  expect_poll "a paste the core refuses shows a toast" 1 clip_toasts
  expect "a change of an entry the history does not hold is refused" "refused: entry=unknown" clip_invoke pin "$clip_no_id"
  expect_poll "the refused change shows a toast" 2 clip_toasts
  expect "an unknown window has the keyboard back and receives no key" '["enter"]' clip_keys_of "$sandbox/clipboard-unknown.log" "$clip_from"
  expect "the entry stays on the clipboard" "smoke before enable" clip_holds
  close_toplevel "$clip_unknown_pid" "the unknown helper exits 0 on SIGTERM"
fi

# Pin, remove and clear, from the keyboard. Each paste above copied its
# entry again, so the last one pasted is first.
expect_poll "the last pasted entry is first in the history" "smoke before enable" clip_first
clip_open "edit"
expect_poll "the history draws its five entries" '["smoke before enable", "PNG image", "smoke beta two", "Smoke Alpha one", "smoke after secret"]' clip_drawn
type_keys "x" || fail "typing a filter failed"
expect_poll "a filter no entry holds draws none" 0 clip_drawn_count
type_keys -k Escape || fail "sending Escape failed"
expect_poll "Escape clears the filter" 5 clip_drawn_count
expect "Escape with a filter leaves the history open" 1 layer_count vgs:overlay
type_keys -k Down -k Down || fail "sending Down failed"
expect_poll "Down moves the selection" '["smoke beta two"]' clip_selected
type_keys -M ctrl -k p -m ctrl || fail "sending Ctrl+P failed"
expect_poll "Ctrl+P pins the selected entry" '["smoke beta two"]' clip_pins
expect_poll "a pinned entry is drawn first" '["smoke beta two", "smoke before enable", "PNG image", "Smoke Alpha one", "smoke after secret"]' clip_drawn
expect_poll "the selection stays on the third row" '["PNG image"]' clip_selected
type_keys -k Delete || fail "sending Delete failed"
expect_poll "Delete removes the selected entry" False clip_has "PNG image"
expect_poll "the removed image entry's file is deleted" 0 clip_image_files
type_keys -M shift -k Delete -m shift || fail "sending Shift+Delete failed"
expect_poll "Shift+Delete asks first" true clip_read overlay confirming
expect "the question clears nothing" 4 clip_count
type_keys -k Return || fail "confirming the clear failed"
expect_poll "the confirmed clear keeps the pinned entry alone" '[["text", "smoke beta two"]]' clip_labels
type_keys -k Escape || fail "sending Escape failed"
expect_poll "Escape closes the history" 0 layer_count vgs:overlay
expect "the pin is let go" ok clip_invoke pin "$(clip_id "smoke beta two")"
expect_poll "no entry is pinned" '[]' clip_pins

# The control: one copy of the plugin with eight rules removed.
cp -R -- "$clip_plugin" "$sandbox/clipboard-plugin.kept"
python3 - "$clip_plugin" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
changes = [
    ("Service.qml", 'shell.shortcut.register("toggle", "Clipboard history", () => root.toggle());', 'shell.shortcut.register("toggle", "Clipboard history", () => "ok");'),
    ("Service.qml", "stdout: SplitParser { onRead: line => root.captured(line) }", "stdout: SplitParser { onRead: line => {} }"),
    ("Service.qml", 'History.pasteChord(kind === "terminal")', "History.pasteChord(false)"),
    ("Service.qml", "            retry.restart();\n", ""),
    ("Service.qml", '        notice(title, message);\n        return "refused: " + key;', '        return "refused: " + key;'),
    ("Overlay.qml", 'shell.ipc.call("rows", filter)', 'shell.ipc.call("rows", "")'),
    ("Overlay.qml", '(imagesDir + "/" + id)', '(imagesDir + "-moved/" + id)'),
    ("helper/clipboard.py", '    if state != "data":\n        return\n', '    if state not in ("data", "sensitive"):\n        return\n'),
    ("helper/clipboard.py", "    if SECRET_TYPE in types:\n        return\n", "    if False:\n        return\n"),
]
for name, before, after in changes:
    path = root / name
    assert not path.is_symlink(), name
    text = path.read_text()
    assert text.count(before) == 1, (name, before)
    path.write_text(text.replace(before, after))
PY
rescan "a rescan builds the clipboard copy with its rules removed"
expect_poll "control: the copy's service is built" True record_exists vgs.clipboard
expect_poll "control: the copy's store is ready" '"ready"' clip_read service store
clip_key || fail "control: typing SUPER+CTRL+V failed"
clip_never_opens() { local got; for _ in $(seq 1 10); do got="$(layer_count vgs:overlay)" || return 1; [[ $got == 0 ]] || { echo opened; return 0; }; sleep 0.2; done; echo closed; }
expect "control: a shortcut that opens nothing leaves the history closed" closed clip_never_opens
clip_copy "smoke control text"
clip_copy_file image/png "$clip_image"
clip_never_records() { local got; for _ in $(seq 1 10); do got="$(clip_labels)" || return 1; [[ $got == '[["text", "smoke beta two"]]' ]] || { echo "$got"; return 0; }; sleep 0.2; done; echo unrecorded; }
expect "control: a watcher whose lines are dropped records no text and no image" unrecorded clip_never_records
python3 - "$clip_plugin/Service.qml" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
before, after = "stdout: SplitParser { onRead: line => {} }", "stdout: SplitParser { onRead: line => root.captured(line) }"
assert text.count(before) == 1
path.write_text(text.replace(before, after))
PY
rescan "a rescan gives the copy its watcher's lines back"
expect_poll "control: the second copy's store is ready" '"ready"' clip_read service store
clip_toasts_before="$(clip_toasts)" || clip_toasts_before=unread
expect "control: the copy refuses a change of an entry the history does not hold" "refused: entry=unknown" clip_invoke pin "$clip_no_id"
expect "control: a refusal without its toast shows none" quiet clip_no_toast_past "$clip_toasts_before"
clip_copy_file image/png "$clip_image"
expect_poll "control: the copy records the image" True clip_has "PNG image"
clip_copy "smoke control one"
expect_poll "control: the copy records again" True clip_has "smoke control one"
clip_copy_secret "smoke control secret"
clip_copy "smoke control two"
expect_poll "control: the copy records the copy after the secret" True clip_has "smoke control two"
expect "control: a helper without the secret checks records the secret" True clip_has "smoke control secret"
if clip_window "$sandbox/clipboard-control.log" smoke.clipboard-terminal "Clipboard terminal"; then
  clip_control_pid="$toplevel_pid"
  expect "control: the copy's history is summoned" ok clip_invoke toggle
  expect_poll "control: the copy's history maps" 1 layer_count vgs:overlay
  clip_focused "control: the copy's history holds the keyboard"
  type_keys "beta" || fail "control: typing the filter failed"
  expect_poll "control: the typed filter reaches the search field" '"beta"' clip_read overlay filter
  clip_unfiltered() { local got; for _ in $(seq 1 10); do got="$(clip_drawn)" || return 1; [[ $got != '["smoke beta two"]' ]] || { echo filtered; return 0; }; sleep 0.2; done; echo unfiltered; }
  expect "control: a filter the overlay does not send leaves every entry drawn" unfiltered clip_unfiltered
  expect_poll "control: a thumbnail whose URL names another directory is not decoded" "[[\"$clip_store/images-moved/${clip_png##*/}\", \"error\"]]" clip_thumbs
  clip_from="$(clip_lines "$sandbox/clipboard-control.log")"
  type_keys -k Return || fail "control: sending Return failed"
  expect_poll "control: Enter closes the copy's history" 0 layer_count vgs:overlay
  expect_poll "control: a terminal sent the application's chord receives V with Ctrl alone" '["enter", 4]' clip_keys_of "$sandbox/clipboard-control.log" "$clip_from"
  close_toplevel "$clip_control_pid" "the control's terminal helper exits 0 on SIGTERM"
fi
if clip_end_watcher "control"; then expect "control: a service that starts no watcher again leaves none" 0 clip_watcher_returns; fi
rm -rf -- "${clip_plugin:?}"
cp -R -- "$sandbox/clipboard-plugin.kept" "$clip_plugin"
rescan "a rescan restores the clipboard plugin"
expect_poll "the restored service is built" True record_exists vgs.clipboard
expect_poll "the restored store is ready" '"ready"' clip_read service store

expect "disabling the clipboard history is allowed" ok ipc shell setPluginEnabled vgs.clipboard false
expect_poll "disabling listed the id and kept the plugins row" '[true, true]' clip_listed
expect_poll "the disabled history leaves no service" False record_exists vgs.clipboard
expect_poll "the disabled history holds no registration" '[[], []]' clip_lent
expect_poll "the disabled history leaves no watcher" 0 clip_watchers
rm -f -- "$home/.local/share/applications/smoke.clipboard-terminal.desktop" "$home/.local/share/applications/smoke.clipboard-app.desktop"
hypr_lua_restore clipboard || fail "the clipboard row puts the harness hyprland.lua back"
expect "the nested instance reloads the harness hyprland.lua" ok hypr reload config-only
