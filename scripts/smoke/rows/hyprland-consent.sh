# The first write of the Hyprland layer asks before wiring hyprland.lua.
# This row runs first, while the harness file still lacks the loading line
# and the sandbox's state holds no welcome-seen marker, so the question
# comes inside the first-start welcome. The welcome must fit a 1440x900
# output without scrolling; a 1440x320 output, where it cannot, is that
# reading's control. It answers the welcome the first shell raised and
# wires the Hyprland layer. A disposable copy fails after Connect; its
# successor checks the managed start classes and the completed consent
# unit after restarting. Restoring only the unwired loader must fail the
# same successor while the welcome-seen marker remains present.
# leaves: layers options
# inputs: shell/Core/HyprlandLayer.* shell/Core/HyprlandState.* shell/Core/Notices.qml shell/Core/PluginLogic.js shell/Core/ConfigLogic.js config/shell.json bin/vgshell bin/vgshell-tui shell/Core/TuiRunner.qml shell/Core/TuiRecords.qml scripts/smoke/toplevel/* shell/Hosts/NoticeHost.qml shell/Ui/feedback/Dialog.qml shell/Ui/feedback/LinkText.qml shell/Commons/PageReference.js shell/Ui/feedback/KeyCaps.qml shell/Ui/feedback/Kbd.qml shell/Ui/layout/Pane.qml shell/plugins/vgs.settings/manifest.json shell/plugins/vgs.settings/Window.qml scripts/smoke/Probe.qml
set -euo pipefail
if [[ ${hc_running:-false} != true ]]; then
  hc_running=true
  hc_dir="$sandbox/consent-boundary"
  mkdir -p -- "$hc_dir"
  cp -- "$source_repo/scripts/smoke/rows/hyprland-consent.sh" "$hc_dir/consent-forced.sh"
  printf '\nfail "hyprland-consent: forced-after-connect"\n' >>"$hc_dir/consent-forced.sh"
  cat >"$hc_dir/consent-successor.sh" <<'SH'
# leaves: layers options
expect "the successor starts at the boundary-owned original classes" "" hc_owned_classes
stop_shell || fail "the consent successor stops its shell"
start_shell "$repo" "$sandbox/consent-successor-$hc_case.log" || fail "the consent successor starts its shell"
expect_poll "the successor completes its consent probe" ready hc_consent_ready
expect "consent-successor: no-notice: the completed consent unit survives restart" $'1\tpresent\twired\tnull\t0' hc_consent_state
printf 'consent-successor=continued case=%s\n' "$hc_case"
SH
  hc_consent_state() {
    local wires marker phase record layers
    wires="$(wire_count)" && marker="$(welcome_marker)" && phase="$(hypr_consent_phase)" && record="$(hypr_consent_record)" && layers="$(layer_count vgs:notice)" || return 1
    printf '%s\t%s\t%s\t%s\t%s\n' "$wires" "$marker" "$phase" "$record" "$layers"
  }
  hc_owned_classes() {
    local verdicts
    verdicts="$(leak_judge "$source_repo/scripts/smoke/rows/hyprland-consent.sh" "$hc_baseline" "${leak_starts[-1]}")" || return 1
    awk -F '\t' '$1 != "declared" && NF' <<<"$verdicts"
  }
  hc_consent_ready() {
    local phase layers
    phase="$(hypr_consent_phase)" && layers="$(layer_count vgs:notice)" || return 1
    case "$phase:$layers" in wired:0|asking:1) echo ready ;; *) printf '%s:%s\n' "$phase" "$layers" ;; esac
  }
  leak_dir_next
  hc_baseline="$leak_next"
  hc_saved_failures="$failures" hc_saved_behaviour="$behaviour_failures"
  failures=0 behaviour_failures=0
  smoke_row consent-forced "$hc_dir" >"$sandbox/consent-forced.log" 2>&1
  hc_result="$failures"
  failures="$hc_saved_failures" behaviour_failures="$hc_saved_behaviour"
  control_output "$sandbox/consent-forced.log"
  expect "the real consent row keeps only its forced failure after Connect" 1 printf '%s\n' "$hc_result"
  expect "the original forced failure survives restoration" 1 grep -c -x -F '  FAIL  hyprland-consent: forced-after-connect' "$sandbox/consent-forced.log"
  expect "the failed consent row takes one full restoration" 1 grep -c '^qml-smoke: restore=begin row=consent-forced scope=full original-status=1 ' "$sandbox/consent-forced.log"
  hc_case=retained
  smoke_row consent-successor "$hc_dir"
  hypr_lua_save consent-complete

  # Reintroduce the old partial rollback in a disposable function copy.
  # The seen marker is untouched, so the successor names the file's cause.
  declare -f leak_restore_start >"$hc_dir/restore.sh"
  python3 - "$hc_dir/restore.sh" "$hc_dir/legacy.sh" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
needle = 'hypr_config_reload ||'
assert source.count(needle) == 1, 'legacy restore mutation must match once'
changed = source.replace(needle, 'cp -- "$sandbox/hyprland-harness.lua" "$home/.config/hypr/hyprland.lua" || leak_restore_step "$1" hyprland-config write;\n        hypr_config_reload ||')
assert changed != source
pathlib.Path(sys.argv[2]).write_text(changed)
PY
  source "$hc_dir/legacy.sh"
  printf '# leaves: layers options\nfail "consent-legacy: forced-after-connect"\n' >"$hc_dir/consent-legacy.sh"
  hc_saved_failures="$failures" hc_saved_behaviour="$behaviour_failures"
  failures=0 behaviour_failures=0
  smoke_row consent-legacy "$hc_dir" >"$sandbox/consent-legacy.log" 2>&1
  hc_result="$failures"
  failures="$hc_saved_failures" behaviour_failures="$hc_saved_behaviour"
  source "$hc_dir/restore.sh"
  control_output "$sandbox/consent-legacy.log"
  expect "the legacy partial rollback keeps its original forced failure" 1 printf '%s\n' "$hc_result"
  hc_case=legacy
  hc_saved_failures="$failures" hc_saved_behaviour="$behaviour_failures"
  failures=0 behaviour_failures=0
  smoke_row consent-successor "$hc_dir" >"$sandbox/consent-legacy-successor.log" 2>&1
  hc_result="$failures"
  failures="$hc_saved_failures" behaviour_failures="$hc_saved_behaviour"
  control_output "$sandbox/consent-legacy-successor.log"
  expect "control: the same no-notice successor rejects isolated Lua rollback" 1 printf '%s\n' "$hc_result"
  expect "control: the legacy failure names the no-notice assertion" 1 grep -c '^  FAIL  consent-successor: no-notice:' "$sandbox/consent-legacy-successor.log"
  expect "control: the rejected successor still runs" 1 grep -c -x -F 'consent-successor=continued case=legacy' "$sandbox/consent-legacy-successor.log"
  expect "control: unwired Lua raises a question despite the seen marker" $'0\tpresent\tasking\t1' hc_legacy_cause
  hypr_lua_restore consent-complete || fail "the legacy fixture restores its completed loader"
  hypr_config_reload || fail "the legacy fixture reloads its completed loader"
  stop_shell || fail "the legacy fixture stops its shell"
  start_shell "$repo" "$sandbox/consent-control-restored.log" || fail "the legacy fixture restores its shell"
  expect_poll "the consent controls leave the completed unit" $'1\tpresent\twired\tnull\t0' hc_consent_state
  return
fi
hc_legacy_cause() {
  local wires marker phase layers
  wires="$(wire_count)" && marker="$(welcome_marker)" && phase="$(hypr_consent_phase)" && layers="$(layer_count vgs:notice)" || return 1
  printf '%s\t%s\t%s\t%s\n' "$wires" "$marker" "$phase" "$layers"
}
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
expect "Settings opens behind the notice before its editor" ok ipc shell summon window vgs.settings '{}'
expect_poll "Settings is present before the notice opens its editor" 1 window_count Plugins
expect_poll "the notice keeps the keyboard over the existing Settings window" true ipc smoke noticeFocused
hold_runs
forget_record
type_keys -k Return || fail "activating the welcome's file link failed"
expect_poll "the welcome link opens its actual file through the core editor" "$(words core/edit "$core_vgshell" edit hypr/hyprland.lua)" recorded_tail
notice_reference_input "welcome file"
expect "the welcome's question stays pending while its editor is open" asking hypr_consent_phase
release_runs
expect_run_end "the welcome file's editor ends" core/edit
expect "the existing Settings window stays open after the notice's editor ends" 1 window_count Plugins
expect_poll "the unanswered welcome returns with the keyboard" true ipc smoke noticeFocused
expect_poll "the returned welcome keeps its original consent" "$welcome_shape_asking" welcome_shape
expect "Settings closes after the editor returns to the notice" ok ipc shell hide window vgs.settings
expect_poll "Settings is gone before the page-reference check" 0 window_count Plugins

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
expected_errors+=('config: .*/shell\.json newer: version=')
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
  && edit_tree notice-reference-retained shell/Hosts/NoticeHost.qml 'host.reference = continuation;' 'host.reference = null;'; then
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
  expect_poll "control: the same reader rejects the editor behind its originating notice" notice-mapped notice_reference_focus
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

# Hold only the acceptance callback until the editor has mapped. The
# source-first yield must already have released its keyboard at that
# barrier; restoring the late yield is the same native reader's control.
notice_order_saved="$sandbox/notice-order-user.json"
cp -- "$home/.config/vgshell/shell.json" "$notice_order_saved"
notice_order_newer() {
  python3 - "$home/.config/vgshell/shell.json" <<'PY'
import json, os, sys
path = sys.argv[1]
with open(path) as source:
    doc = json.load(source)
doc["version"] += 1
with open(path + ".tmp", "w") as out:
    json.dump(doc, out)
os.replace(path + ".tmp", path)
PY
}
notice_order_mapped() { hypr -j clients | py_reply 'import json,sys; print(sum(c["class"] == "org.vgs.tui" for c in json.load(sys.stdin)))'; }
for notice_order in early late; do
  stop_shell
  cp -- "$notice_order_saved" "$home/.config/vgshell/shell.json.tmp" && mv -T -- "$home/.config/vgshell/shell.json.tmp" "$home/.config/vgshell/shell.json"
  copy_tree "notice-order-$notice_order"
  edit_tree "notice-order-$notice_order" shell/Hosts/NoticeHost.qml 'property var reference: null' 'property var reference: null; property var heldOpen: null; property var heldDone: null'
  edit_tree "notice-order-$notice_order" shell/Hosts/NoticeHost.qml 'const answer = open(done);' 'host.heldOpen = () => open(answer => { host.heldDone = () => done(answer); }); const answer = "ok";'
  # Probe is injected into the disposable tree, outside edit_tree's shipped-source inventory.
  python3 - "$sandbox/tree-notice-order-$notice_order/shell/Probe.qml" <<'PYPROBE'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
needle = "function noticeFocused(): bool {"
assert text.count(needle) == 1, "the probe insertion must match once"
methods = """function noticeOrderHeld(): bool { return Plugins.hosts.notice.heldDone !== null; }
        function noticeOrderPending(): bool { const host = Plugins.hosts.notice; return host.reference !== null && host.reference.opening; }
        function noticeOrderOpen(): string { const host = Plugins.hosts.notice; const open = host.heldOpen; host.heldOpen = null; return open === null ? "absent" : open(); }
        function noticeOrderRelease(): string { const host = Plugins.hosts.notice; const done = host.heldDone; host.heldDone = null; if (done === null) return "absent"; done(); return "ok"; }
        """
path.write_text(text.replace(needle, methods + needle))
PYPROBE
  if [[ $notice_order == late ]]; then
    edit_tree notice-order-late shell/Hosts/NoticeHost.qml 'if (loader.item !== null) loader.item.visible = false;
        reference = continuation;' 'host.reference = null;'
  fi
  start_shell "$sandbox/tree-notice-order-$notice_order" "$sandbox/notice-order-$notice_order.log" || fail "the $notice_order yield fixture starts"
  terminal_ready "$notice_order yield"
  notice_order_newer
  expect_poll "$notice_order yield: the running shell reads the newer file" newer notice_reference_config_state
  expect_poll "$notice_order yield: the newer notice has the keyboard" true ipc smoke noticeFocused
  expect "$notice_order yield: Settings opens behind the notice" ok ipc shell summon window vgs.settings '{}'
  expect_poll "$notice_order yield: Settings maps behind the notice" 1 window_count Plugins
  hold_runs
  forget_record
  rm -f -- "${tui_record:?}.window"
  expect "$notice_order yield: the message activates its file" ok ipc smoke noticeReference "" ""
  if [[ $notice_order == early ]]; then
    expect_poll "the notice yields before the file probe starts" 0 layer_count vgs:notice
    expect "Settings closes while the file open is pending" ok ipc shell hide window vgs.settings
    expect_poll "Settings is gone while the file open is pending" 0 window_count Plugins
    expect "the continuation survives an unrelated window closing before its probe" true ipc smoke noticeOrderPending
    expect_poll "an unrelated window closing does not remap the pending notice" 0 layer_count vgs:notice
    expect "Settings opens again while the file open is pending" ok ipc shell summon window vgs.settings '{}'
    expect_poll "Settings is present before releasing the file probe" 1 window_count Plugins
    expect "the continuation survives an unrelated window opening before its probe" true ipc smoke noticeOrderPending
    expect_poll "an unrelated window opening does not remap the pending notice" 0 layer_count vgs:notice
  fi
  expect "$notice_order yield: the file probe starts after the pending barrier" ok ipc smoke noticeOrderOpen
  expect_poll "$notice_order yield: acceptance waits at the barrier" true ipc smoke noticeOrderHeld
  expect_poll "$notice_order yield: the editor maps before acceptance is delivered" 1 notice_order_mapped
  if [[ $notice_order == early ]]; then
    expect_poll "the source-first yield gives the mapped editor native keyboard focus before acceptance" native notice_reference_focus
    notice_order_before="$(notice_reference_keys)"
    type_keys -k F8 || fail "typing at the early-editor barrier failed"
    expect_poll "the source-first yield delivers both key events before acceptance" "$((notice_order_before + 2))" notice_reference_keys
  else
    (
      failures=0
      expect "the mapped editor has native keyboard focus before acceptance" native notice_reference_focus
      printf 'control-failures=%s\n' "$failures"
    ) >"$sandbox/notice-order-control.log"
    control_output "$sandbox/notice-order-control.log"
    expect "control: today's late yield fails the native-focus assertion" 1 sed -n 's/^control-failures=//p' "$sandbox/notice-order-control.log"
    expect "control: the notice still owns the keyboard after the editor maps" true ipc smoke noticeFocused
  fi
  expect "$notice_order yield: the accepted callback is released" ok ipc smoke noticeOrderRelease
  expect_poll "$notice_order yield: the notice closes after acceptance" 0 layer_count vgs:notice
  release_runs
  expect_run_end "$notice_order yield: the editor ends" core/edit
  expect_poll "$notice_order yield: the pending notice returns with the keyboard" true ipc smoke noticeFocused
  expect "$notice_order yield: Settings closes" ok ipc shell hide window vgs.settings
done
cp -- "$sandbox/notice-order-control.log" "$smoke_log_dir/notice-order-control.log"
stop_shell
cp -- "$notice_order_saved" "$home/.config/vgshell/shell.json.tmp" && mv -T -- "$home/.config/vgshell/shell.json.tmp" "$home/.config/vgshell/shell.json"
start_shell "$repo" "$sandbox/notice-order-restored.log" || fail "the source-first yield returns after its control"
terminal_ready "refused early yield"
notice_order_newer
expect_poll "the refusal fixture's running shell reads the newer file" newer notice_reference_config_state
expect_poll "the newer notice holds the keyboard before a refused open" true ipc smoke noticeFocused
forget_record
expected_errors+=('notices: reference refused: file=.*notice-order-missing\.txt.* reason=missing')
expect "the refused file uses the source-first yield" ok ipc smoke noticeReference "file:$sandbox/notice-order-missing.txt" ""
expect_log "the refused early open reaches the existing refusal path" 1 'notices: reference refused: file=.*notice-order-missing\.txt.* reason=missing'
expect_poll "a refused early open returns the notice and its keyboard" true ipc smoke noticeFocused
expect "a refused early open starts no editor" absent recorded
expect "a refused early open preserves the newer-file state" newer notice_reference_config_state
cp -- "$notice_order_saved" "$home/.config/vgshell/shell.json.tmp" && mv -T -- "$home/.config/vgshell/shell.json.tmp" "$home/.config/vgshell/shell.json"
expect_poll "the user file is restored after the ordered hand-off" loaded notice_reference_config_state
expect_poll "the connected notice is gone after the ordered hand-off" 0 layer_count vgs:notice
