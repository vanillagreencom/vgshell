# Not now records a marker for this Hyprland session. A restart in the same
# compositor session does not ask again, and a control copy that ignores
# the marker does ask. The consent row left the welcome-seen marker, so
# this later start with an unwired hyprland.lua asks the plain question:
# the welcome's second-start control.
#
# Then the welcome's own answers. With the marker removed, Escape on the
# welcome that asks declines and writes both markers; a copy whose decline
# marker write takes 2 s more shows the welcome, busy, while the decline
# runs, and the same copy with a judge that marks the welcome seen on the
# answer shows the plain question there, the reading's control. Once
# hyprland.lua is wired again, a start without the marker draws the welcome
# with Close alone, Escape closes it and writes the marker, and the next
# start, with the marker, draws nothing. The Close-alone welcome's theme
# line shows only while vgs.themes binds its shortcut, and earlier rows
# leave that plugin either way, so the row enables it for those starts. The
# row leaves hyprland.lua wired, the welcome seen, vgs.themes disabled only
# when it found it so and the real shell running.
# inputs: shell/Core/HyprlandLayer.* shell/Core/Notices.qml bin/vgsh bin/vgsh-hypr-judge shell/Hosts/NoticeHost.qml shell/Core/PluginLogic.js config/shell.json shell/plugins/vgs.themes/manifest.json scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail

hypr_lua="$home/.config/hypr/hyprland.lua"
hypr_layer="$home/.local/state/vgs/hypr/vgs.lua"
marker="$rt_dir/vgs/hypr/consent-declined"
wire_line="pcall(dofile, \"$hypr_layer\")"
vgsh_run() { "${shell_env[@]}" "$repo/bin/vgsh" "$@"; }
wire_count() { grep -cxF -- "$wire_line" "$hypr_lua" || true; }
tail_matches_harness() { tail -n +2 -- "$hypr_lua" | cmp -s - "$sandbox/hyprland-harness.lua" && echo same || echo differs; }
marker_content() { cat -- "$marker" 2>/dev/null || true; }
prepare_unwired_start() { vgsh_run hypr unwire >/dev/null; }
welcome_record() { ipc shell lent | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["notices"]["welcome"]))'; }
welcome_seen="$home/.local/state/vgs/welcome-seen"
welcome_marker() { [[ -e $welcome_seen ]] && echo present || echo absent; }
# Whether the user file on disk lists vgs.themes as disabled, which the
# next start reads; with no user file the shipped set holds it enabled.
themes_on_disk() { [[ -e $home/.config/vgs/shell.json ]] || { echo enabled; return; }; python3 -c 'import json,sys; print("disabled" if "vgs.themes" in json.load(open(sys.argv[1])).get("disabledPlugins", []) else "enabled")' "$home/.config/vgs/shell.json"; }
# The consent phase, its queued answer and the slot's title, while an
# answer runs.
decline_view() { ipc shell lent | py_reply 'import json,sys; n=json.load(sys.stdin)["notices"]; s=n.get("consentState") or {}; c=n["consent"]; print(json.dumps({"phase": s.get("phase"), "queued": s.get("queued"), "title": None if c is None else c["title"]}))'; }
welcome_lines='["VGS is a bar and a set of plugins on top of your Hyprland. Turn plugins on and off from the plugins button at the top right of the bar.", "VGS adds one line to the top of your hyprland.lua. It loads a file VGS generates. Your own settings come after it and win. VGS changes nothing else in that file.", "Super+T picks a theme."]'

prepare_unwired_start
if stop_shell && start_shell "$repo" "$sandbox/hypr-consent-decline.log"; then
  ok "the real shell restarts for the consent decline row"
fi
expect_poll "the restarted shell asks before wiring an unchanged layer" '{"title": "Let VGS manage its Hyprland settings?", "command": "vgsh hypr wire", "failure": ""}' hypr_consent_record
expect "a later start with the welcome seen draws no welcome" '{"state": "seen", "lines": null, "actions": null}' welcome_record
type_keys -k Escape || fail "sending Escape to the Hyprland consent notice failed"
expect_poll "Not now reaches the declined consent state" declined hypr_consent_phase
expect_poll "Not now closes the Hyprland consent notice" null hypr_consent_record
expect_poll "Not now leaves hyprland.lua unwired" 0 wire_count
expect_poll "Not now writes this Hyprland session's marker" "$signature" marker_content
expect "a forced render after Not now is accepted" ok vgsh_run hypr render
expect_poll "the forced render leaves hyprland.lua unwired" 0 wire_count
rescan "a rescan after Not now is accepted"
expect_poll "the rescan after Not now keeps the declined consent state" declined hypr_consent_phase
expect "the rescan after Not now raises no consent notice" null hypr_consent_record

if stop_shell && start_shell "$repo" "$sandbox/hypr-consent-decline-restart.log"; then
  ok "the real shell restarts with the decline marker"
fi
expect_poll "the restart with the marker scans plugins" true ipc shell guarded
expect_poll "the restart with the marker reaches the declined consent state" declined hypr_consent_phase
expect "the restart with the marker raises no consent notice" null hypr_consent_record
expect "the restart with the marker leaves hyprland.lua unwired" 0 wire_count

mutant="$sandbox/hypr-consent-mutant"
mkdir -p -- "$mutant"
cp -R -- "$repo/shell" "$mutant/shell"
cp -R -- "$repo/bin" "$mutant/bin"
for dir in config themes; do ln -s -- "$repo/$dir" "$mutant/$dir"; done
for file in VERSION LICENSE README.md; do cp -- "$repo/$file" "$mutant/$file"; done
layer_qml="$mutant/shell/Core/HyprlandLayer.qml"
if python3 - "$layer_qml" <<'PY'
import sys
path = sys.argv[1]
old = '            root.feed({ type: "declineChecked", declined: failure === "" && text === root.hyprlandSignature, failure: failure });\n'
text = open(path).read()
if text.count(old) != 1:
    sys.exit("marker check occurs %d times" % text.count(old))
open(path, "w").write(text.replace(old, '            root.feed({ type: "declineChecked", declined: false, failure: failure });\n'))
PY
then ok "the decline control copy ignores the marker by reporting it absent"; else fail "the decline control copy could not change the marker check"; fi

if stop_shell && start_shell "$mutant" "$sandbox/hypr-consent-mutant.log"; then
  ok "the decline control copy starts"
fi
expect_poll "control: ignoring the marker reaches the asking consent state" asking hypr_consent_phase
expect_poll "control: ignoring the marker asks again after restart" '{"title": "Let VGS manage its Hyprland settings?", "command": "vgsh hypr wire", "failure": ""}' hypr_consent_record

printf '%s\n' "other-session" >"$marker"
if stop_shell && start_shell "$repo" "$sandbox/hypr-consent-other-session.log"; then
  ok "the real shell restarts with another session's marker"
fi
expect_poll "a marker from another Hyprland session is ignored" asking hypr_consent_phase
expect_poll "a marker from another Hyprland session asks again" '{"title": "Let VGS manage its Hyprland settings?", "command": "vgsh hypr wire", "failure": ""}' hypr_consent_record

# Escape on the welcome that asks. The slow copy's decline marker write
# sleeps 2 s first, so the readings between the answer and the decline see
# what the slot draws meanwhile.
marker_write='"[[ -n \"$3\" ]] || exit 3; mkdir'
slow_marker_write='"sleep 2; [[ -n \"$3\" ]] || exit 3; mkdir'
copy_tree welcome-slow
edit_tree welcome-slow shell/Core/HyprlandLayer.qml "$marker_write" "$slow_marker_write" || :
rm -f -- "${marker:?}" "${welcome_seen:?}"
if stop_shell && start_shell "$sandbox/tree-welcome-slow" "$sandbox/hypr-welcome-decline.log"; then
  ok "the slow welcome copy starts without either marker"
fi
expect_poll "an unwired start without the welcome-seen marker asks inside the welcome" '{"title": "Welcome to VGS", "command": "vgsh hypr wire", "failure": ""}' hypr_consent_record
expect_poll "the asking welcome holds the keyboard" true ipc smoke noticeFocused
type_keys -k Escape || fail "sending Escape to the asking welcome failed"
expect_poll "the welcome stays, busy, while its decline runs" '{"phase": "asking", "queued": "decline", "title": "Welcome to VGS"}' decline_view
expect_poll "Escape on the welcome reaches the declined consent state" declined hypr_consent_phase
expect_poll "Escape on the welcome closes it" null hypr_consent_record
expect_poll "Escape on the welcome writes this Hyprland session's marker" "$signature" marker_content
expect_poll "Escape on the welcome writes the welcome-seen marker" present welcome_marker
expect "Escape on the welcome leaves hyprland.lua unwired" 0 wire_count

copy_tree welcome-early
edit_tree welcome-early shell/Core/HyprlandLayer.qml "$marker_write" "$slow_marker_write" || :
edit_tree welcome-early shell/Core/PluginLogic.js $'        case "connect":\n        case "decline":\n            return keep;\n' \
  $'        case "connect":\n            return keep;\n        case "decline":\n            return welcomeState === "unseen" ? seen : keep;\n' || :
rm -f -- "${marker:?}" "${welcome_seen:?}"
if stop_shell && start_shell "$sandbox/tree-welcome-early" "$sandbox/hypr-welcome-early.log"; then
  ok "the welcome control copy starts without either marker"
fi
expect_poll "control: the copy asks inside the welcome" '{"title": "Welcome to VGS", "command": "vgsh hypr wire", "failure": ""}' hypr_consent_record
expect_poll "control: the copy's welcome holds the keyboard" true ipc smoke noticeFocused
type_keys -k Escape || fail "sending Escape to the control copy's welcome failed"
expect_poll "control: marking the welcome seen on the answer shows the plain question while the decline runs" '{"phase": "asking", "queued": "decline", "title": "Let VGS manage its Hyprland settings?"}' decline_view
expect_poll "control: the copy's decline reaches the declined consent state" declined hypr_consent_phase

rm -f -- "$marker"
if stop_shell && start_shell "$repo" "$sandbox/hypr-consent-final.log"; then
  ok "the real shell restarts after the decline control"
fi
expect_poll "the real shell asks again after the marker is removed" '{"title": "Let VGS manage its Hyprland settings?", "command": "vgsh hypr wire", "failure": ""}' hypr_consent_record
type_keys -k Return || fail "sending Return to the final Hyprland consent notice failed"
expect_poll "the final Connect reaches the wired consent state" wired hypr_consent_phase
expect_poll "the final Connect closes the Hyprland consent notice" null hypr_consent_record
expect_poll "the final Connect adds the loading line exactly once" 1 wire_count
expect_poll "the final Connect keeps the loading line first" "$wire_line" head -n 1 -- "$hypr_lua"
expect_poll "the final Connect changes no other hyprland.lua byte" same tail_matches_harness

# The welcome with Close alone, over the wired hyprland.lua.
themes_were_enabled="$(plugin_enabled vgs.themes)" || themes_were_enabled=unread
expect "enabling vgs.themes for the Close-alone welcome is allowed" ok ipc shell setPluginEnabled vgs.themes true
expect_poll "the user file holds vgs.themes enabled before the restart" enabled themes_on_disk
rm -f -- "${welcome_seen:?}"
if stop_shell && start_shell "$repo" "$sandbox/hypr-welcome-close.log"; then
  ok "the real shell restarts wired without the welcome-seen marker"
fi
expect_poll "a wired start without the marker draws the welcome with Close alone" "{\"state\": \"unseen\", \"lines\": $welcome_lines, \"actions\": [\"Close\"]}" welcome_record
expect "the Close-alone welcome follows the wired consent state" wired hypr_consent_phase
expect_poll "the Close-alone welcome holds the keyboard" true ipc smoke noticeFocused
type_keys -k Escape || fail "sending Escape to the Close-alone welcome failed"
expect_poll "Escape closes the Close-alone welcome" null hypr_consent_record
expect_poll "Escape on the Close-alone welcome writes the welcome-seen marker" present welcome_marker
expect "Escape on the Close-alone welcome marks it seen" '{"state": "seen", "lines": null, "actions": null}' welcome_record

if stop_shell && start_shell "$repo" "$sandbox/hypr-welcome-seen.log"; then
  ok "the real shell restarts wired with the welcome-seen marker"
fi
expect_poll "control: a wired start with the marker reads the welcome seen" '{"state": "seen", "lines": null, "actions": null}' welcome_record
expect_poll "control: a wired start with the marker reaches the wired consent state" wired hypr_consent_phase
expect "control: a wired start with the marker draws nothing" null hypr_consent_record
if [[ $themes_were_enabled == False ]]; then
  expect "disabling vgs.themes again after the welcome rows is allowed" ok ipc shell setPluginEnabled vgs.themes false
  expect_poll "vgs.themes' service is gone after the welcome rows" False record_exists vgs.themes
fi
