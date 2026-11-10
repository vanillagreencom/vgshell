# The first write of the Hyprland layer asks before wiring hyprland.lua.
# This row runs first, while the harness file still lacks the loading line
# and the sandbox's state holds no welcome-seen marker, so the question
# comes inside the first-start welcome. The welcome must fit a 1440x900
# output without scrolling; a 1440x320 output, where it cannot, is that
# reading's control. It answers the welcome the first shell raised and
# wires the Hyprland layer, so every later row starts with the notice
# layer gone and the layer's options loaded.
# leaves: layers options
# inputs: shell/Core/HyprlandLayer.* shell/Core/HyprlandState.* shell/Core/Notices.qml shell/Core/PluginLogic.js shell/Core/ConfigLogic.js config/shell.json bin/vgshell bin/vgshell-tui shell/Core/TuiRunner.qml shell/Core/TuiRecords.qml scripts/smoke/toplevel/* shell/Hosts/NoticeHost.qml shell/Ui/feedback/Dialog.qml shell/Ui/feedback/LinkText.qml shell/Commons/PageReference.js shell/Ui/feedback/KeyCaps.qml shell/Ui/feedback/Kbd.qml shell/Ui/layout/Pane.qml scripts/smoke/Probe.qml
set -euo pipefail
leak_plugin_setup vgs.themes true || { fail "hyprland-consent: fixture precondition failed"; return 1; }

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
# consent_readiness: the publisher's readiness, which the Probe reads
# without changing it: available, admitted, current plan, writer phase and
# whether keys are resolving.
consent_readiness() {
  ipc smoke hyprlandReadiness | py_reply 'import json,sys
d=json.load(sys.stdin)
print(json.dumps([d.get(k) for k in ("available", "admitted", "currentPlan", "writerPhase", "resolvingKeys")]))'
}
welcome_shape_asking='{"actions": ["Connect", "Not now"], "keys": [{"shortcut": "SUPER+SHIFT+T", "text": "picks a theme."}], "lineCount": 3, "link": {"path": "hypr/hyprland.lua", "text": "hyprland.lua"}, "state": "unseen"}'

expect "the harness starts without the VGS loading line" 0 wire_count
expect "the sandbox starts without the welcome-seen marker" absent welcome_marker
expect_poll "the first start's welcome asks the Hyprland question" '{"title": "Welcome to VGS", "failure": ""}' hypr_consent_record
# The question needs only the core. The welcome's key row and chips come
# from the admitted shortcut plan, which key resolution publishes later.
expect_poll "the core admits current keys after the question" '[true, true, true, "idle", false]' consent_readiness
# No key-hints plugin is installed, so its row is absent; the themes
# plugin binds Super+Shift+T.
expect_poll "the welcome is recorded with its link, key row and Connect, Not now" "$welcome_shape_asking" welcome_shape
expect_poll "the welcome maps" 1 layer_count vgs:notice
expect_poll "the welcome holds the keyboard" true ipc smoke noticeFocused
expect_poll "the welcome draws link text, key chips, Connect and Not now without Show command" '{"actions": ["Connect", "Not now"], "busy": false, "focused": "Connect", "hasLinkText": true, "keys": [{"shortcut": "SUPER+SHIFT+T", "text": "picks a theme."}], "keysTitle": "Quick commands", "rowCount": 3, "title": "Welcome to VGS"}' welcome_drawn_shape
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

# These are the notice's own continuations, not unrelated windows under
# its Exclusive keyboard. Read native input from the terminal stand-in,
# and retain the unanswered consent until that destination closes.
terminal_stand_in
terminal_ready "notice references"
notice_reference_focus() {
  local layers
  layers="$(layer_count vgs:notice)" || return 1
  [[ $layers == 0 ]] || { echo notice-mapped; return; }
  python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); rows=[r for r in p.read_text().splitlines() if r.startswith("keyboard ")] if p.exists() else []; print("native" if rows and rows[-1]=="keyboard enter" else "not-focused")' "$tui_record.window"
}
notice_reference_keys() { local status=0; grep -cE '^key ' "$tui_record.window" || status=$?; [[ $status -le 1 ]]; }
notice_reference_input() { # LABEL
  local before
  expect_poll "$1: the notice unmaps and the editor receives native keyboard focus" native notice_reference_focus
  before="$(notice_reference_keys)" || { fail "$1: the editor's native log is unreadable"; return; }
  type_keys -k F8 || fail "$1: typing into the editor failed"
  expect_poll "$1: the editor receives the typed key" "$((before + 2))" notice_reference_keys
  expect "$1: opening the reference does not answer Connect or Not now" 0 wire_count
  expect "$1: opening the reference leaves the welcome unseen" absent welcome_marker
}
hold_runs
forget_record
type_keys -k Return || fail "activating the welcome's file link failed"
expect_poll "the welcome link opens its actual file through the core editor" "$(words core/edit "$core_vgshell" edit hypr/hyprland.lua)" recorded_tail
notice_reference_input "welcome file"
expect "the welcome's question stays pending while its editor is open" asking hypr_consent_phase
release_runs
expect_run_end "the welcome file's editor ends" core/edit
expect_poll "the unanswered welcome returns with the keyboard" true ipc smoke noticeFocused
expect_poll "the returned welcome keeps its original consent" "$welcome_shape_asking" welcome_shape

# The shared message-reference path keeps the origin on a missing file,
# and opens Settings without answering the pending welcome.
forget_record
expected_errors+=('notices: reference refused: file=.*notice-gone\.txt.* reason=missing')
expect "a message reference enters the existing file route" ok ipc smoke noticeReference "file:$sandbox/notice-gone.txt" ""
expect_log "the asynchronous missing-file refusal reaches the notice owner" 1 'notices: reference refused: file=.*notice-gone\.txt.* reason=missing'
expect "a refused reference starts no editor" absent recorded
expect "a refused reference keeps the notice keyboard" true ipc smoke noticeFocused
expect "a page reference opens the manager's existing window route" ok ipc smoke noticeReference vgs.themes Settings
expect_poll "the page reference unmaps the welcome" 0 layer_count vgs:notice
expect_poll "the page reference receives actual keyboard focus" true window_keyboard vgs.settings
expect "the page reference leaves the consent unanswered" asking hypr_consent_phase
expect "closing the reference window uses its normal lifetime" ok ipc shell hide window vgs.settings
expect_poll "the welcome returns after the reference window closes" true ipc smoke noticeFocused

# A newer-format notice's actual message link goes through Dialog and
# the same host callback. Restore the user bytes without answering it.
notice_reference_saved="$sandbox/notice-reference-user.json"
cp -- "$home/.config/vgshell/shell.json" "$notice_reference_saved"
python3 - "$home/.config/vgshell/shell.json" <<'PY'
import json, os, sys
path = sys.argv[1]
doc = json.load(open(path))
doc["version"] += 1
with open(path + ".tmp", "w") as out:
    json.dump(doc, out)
os.replace(path + ".tmp", path)
PY
expected_errors+=('config: user file newer: version=')
notice_reference_config_state() { ipc shell listPlugins | py_reply 'import json,sys; print(json.load(sys.stdin)["config"]["user"])'; }
expect_poll "the newer-format file is classified by the configuration owner" newer notice_reference_config_state
expect_poll "the newer-format notice holds the keyboard before its link" true ipc smoke noticeFocused
hold_runs
forget_record
expect "the newer-format notice activates its actual message reference" ok ipc smoke noticeReference "" ""
expect_poll "the newer-format message link opens its actual user file" "$(words core/edit "$core_vgshell" edit "$home/.config/vgshell/shell.json")" recorded_tail
notice_reference_input "newer-format file"
release_runs
expect_run_end "the newer-format file's editor ends" core/edit
expect_poll "the newer-format notice returns with the keyboard after the editor" true ipc smoke noticeFocused
expect "the newer-format file remains newer after its editor closes" newer notice_reference_config_state
cp -- "$notice_reference_saved" "$home/.config/vgshell/shell.json.tmp" && mv -T -- "$home/.config/vgshell/shell.json.tmp" "$home/.config/vgshell/shell.json"
expect_poll "the restored user file is loaded" loaded notice_reference_config_state
expect_poll "restoring the user file returns the pending welcome" true ipc smoke noticeFocused
expect_poll "the welcome still offers its original consent after the newer file" "$welcome_shape_asking" welcome_shape

# Removing only the accepted handoff leaves the editor mapped but unable
# to receive the keyboard. The same native-focus reader must reject it.
stop_shell
if copy_tree notice-reference-retained \
  && edit_tree notice-reference-retained shell/Hosts/NoticeHost.qml 'host.referenceNotice = id;' 'host.referenceNotice = "";'; then
  start_shell "$sandbox/tree-notice-reference-retained" "$sandbox/notice-reference-retained.log" || fail "the retained-origin control starts"
  terminal_ready "reference control"
  expect_poll "control: the pending welcome has actual keyboard focus" true ipc smoke noticeFocused
  type_keys -M shift -k Tab -m shift || fail "control: reaching the welcome link failed"
  expect_poll "control: the welcome link is focused" "link:hyprland.lua" welcome_focused
  hold_runs
  forget_record
  rm -f -- "${tui_record:?}.window"
  type_keys -k Return || fail "control: activating the welcome file link failed"
  expect_poll "control: the editor is launched before reading focus" busy key_idle core/edit
  notice_reference_mapped() { python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); print(p.exists() and "mapped org.vgs.tui" in p.read_text().splitlines())' "$tui_record.window"; }
  expect_poll "control: the editor's native window maps" True notice_reference_mapped
  expect "control: the same reader rejects the editor behind its originating notice" notice-mapped notice_reference_focus
  release_runs
  expect_run_end "control: the editor ends" core/edit
  stop_shell
fi
start_shell "$repo" "$sandbox/notice-reference-restored.log" || fail "the shell returns after the notice-reference control"
expect_poll "the welcome returns with its consent unchanged after the control" "$welcome_shape_asking" welcome_shape
expect_poll "the restored welcome has actual keyboard focus" true ipc smoke noticeFocused
type_keys -M shift -k Tab -m shift || fail "returning to the welcome link after the control failed"
expect_poll "the welcome link remains reachable after the control" "link:hyprland.lua" welcome_focused
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
