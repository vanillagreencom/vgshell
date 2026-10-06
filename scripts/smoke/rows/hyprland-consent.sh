# The first write of the Hyprland layer asks before wiring hyprland.lua.
# This row runs first, while the harness file still lacks the loading line
# and the sandbox's state holds no welcome-seen marker, so the question
# comes inside the first-start welcome. The welcome must fit a 1440x900
# output without scrolling; a 1440x320 output, where it cannot, is that
# reading's control. It answers the welcome the first shell raised and
# wires the Hyprland layer, so every later row starts with the notice
# layer gone and the layer's options loaded.
# leaves: layers options
# inputs: shell/Core/HyprlandLayer.* shell/Core/Notices.qml shell/Core/PluginLogic.js config/shell.json bin/vgshell shell/Hosts/NoticeHost.qml shell/Ui/feedback/Dialog.qml shell/Ui/feedback/LinkText.qml shell/Ui/feedback/KeyCaps.qml shell/Ui/feedback/Kbd.qml shell/Ui/layout/Pane.qml scripts/smoke/Probe.qml
set -euo pipefail

hypr_lua="$home/.config/hypr/hyprland.lua"
hypr_layer="$home/.local/state/vgshell/hypr/vgs.lua"
wire_line="pcall(dofile, \"$hypr_layer\")"

wire_count() { grep -cxF -- "$wire_line" "$hypr_lua" || true; }
tail_matches_harness() { tail -n +2 -- "$hypr_lua" | cmp -s - "$sandbox/hyprland-harness.lua" && echo same || echo differs; }
welcome_record() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["notices"]["welcome"]))'; }
welcome_shape() { welcome_record | py_reply 'import json,sys; w=json.load(sys.stdin); print(json.dumps({"state": w["state"], "lineCount": None if w["lines"] is None else len(w["lines"]), "actions": w["actions"], "keys": w["keys"], "link": w["link"]}, sort_keys=True))'; }
welcome_marker() { [[ -e $home/.local/state/vgshell/welcome-seen ]] && echo present || echo absent; }
# notice_fit HEIGHT: `fits` while the notice dialog is no taller than its
# surface, nothing in it scrolls and the surface is at most HEIGHT high,
# so it reads the held output; otherwise the reading.
notice_fit() { ipc smoke noticeFit | py_reply 'import json,sys; f=json.load(sys.stdin); print("fits" if f["dialog"] <= f["surface"] <= int(sys.argv[1]) and f["overflowing"] == 0 else json.dumps(f, sort_keys=True))' "$1"; }
# notice_overflows HEIGHT: `yes` while the dialog is taller than its
# surface or scrolls, on a surface at most HEIGHT high.
notice_overflows() { ipc smoke noticeFit | py_reply 'import json,sys; f=json.load(sys.stdin); print("yes" if f["surface"] <= int(sys.argv[1]) and (f["dialog"] > f["surface"] or f["overflowing"] > 0) else json.dumps(f, sort_keys=True))' "$1"; }
welcome_drawn_shape() { ipc smoke noticeDrawn | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps({"title": d["title"], "rowCount": len(d["rows"]), "hasLinkText": any("hyprland.lua" in row for row in d["rows"]), "keysTitle": d["keysTitle"], "keys": d["keys"], "focused": d["focused"], "actions": d["actions"], "busy": d["busy"]}, sort_keys=True))'; }
welcome_focused() { ipc smoke noticeDrawn | py_reply 'import json,sys; print(json.load(sys.stdin)["focused"])'; }
welcome_shape_asking='{"actions": ["Connect", "Not now"], "keys": [{"shortcut": "Super+Ctrl+T", "text": "picks a theme."}], "lineCount": 3, "link": {"path": "hypr/hyprland.lua", "text": "hyprland.lua"}, "state": "unseen"}'

expect "the harness starts without the VGS loading line" 0 wire_count
expect "the sandbox starts without the welcome-seen marker" absent welcome_marker
expect_poll "the first start's welcome asks the Hyprland question" '{"title": "Welcome to VGS", "failure": ""}' hypr_consent_record
# No key-hints plugin is installed, so its row is absent; the themes
# plugin binds Super+Ctrl+T.
expect_poll "the welcome is recorded with its link, key row and Connect, Not now" "$welcome_shape_asking" welcome_shape
expect_poll "the welcome maps" 1 layer_count vgs:notice
expect_poll "the welcome holds the keyboard" true ipc smoke noticeFocused
expect_poll "the welcome draws link text, key chips, Connect and Not now without Show command" '{"actions": ["Connect", "Not now"], "busy": false, "focused": "Connect", "hasLinkText": true, "keys": [{"shortcut": "Super+Ctrl+T", "text": "picks a theme."}], "keysTitle": "Quick commands", "rowCount": 3, "title": "Welcome to VGS"}' welcome_drawn_shape
fit_monitor="$(first_name)" || fail "the first monitor's name is unreadable"
fit_base_mode="$(first_mode)" || fail "the first monitor's mode is unreadable"
hold_mode "the nested compositor holds $fit_monitor at 1440x900 for the welcome" "$fit_monitor" 1440x900
expect_poll "the welcome fits a 1440x900 output without scrolling" fits notice_fit 900
release_mode "the nested compositor gives $fit_monitor its own mode after 1440x900" "$fit_monitor" "$fit_base_mode"
hold_mode "the nested compositor holds $fit_monitor at 1440x320 for the welcome's control" "$fit_monitor" 1440x320
expect_poll "control: the welcome does not fit a 1440x320 output" yes notice_overflows 320
release_mode "the nested compositor gives $fit_monitor its own mode after 1440x320" "$fit_monitor" "$fit_base_mode"
expect_poll "the welcome holds the keyboard after the mode changes" true ipc smoke noticeFocused
type_keys -M shift -k Tab -m shift || fail "sending Shift+Tab to the welcome link failed"
expect_poll "Shift+Tab from Connect reaches the hyprland.lua link" "link:hyprland.lua" welcome_focused
type_keys -k Tab || fail "sending Tab from the welcome link back to Connect failed"
expect_poll "Tab from the hyprland.lua link returns to Connect" Connect welcome_focused
type_keys -k Return || fail "sending Return to the welcome failed"
expect_poll "Connect reaches the wired consent state" wired hypr_consent_phase
expect_poll "Connect closes the welcome" null hypr_consent_record
expect_poll "Connect marks the welcome seen" '{"actions": null, "keys": null, "lineCount": null, "link": null, "state": "seen"}' welcome_shape
expect_poll "Connect writes the welcome-seen marker" present welcome_marker
expect_poll "Connect adds the loading line exactly once" 1 wire_count
expect_poll "Connect keeps the loading line first" "$wire_line" head -n 1 -- "$hypr_lua"
expect_poll "Connect changes no other hyprland.lua byte" same tail_matches_harness
expect_poll "Hyprland reloads the consent-wired layer without config errors" '[]' hypr_reload_errors
