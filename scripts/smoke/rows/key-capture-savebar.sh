# A Saved footer expiring after Unbind's pointer target was sampled must
# not move the button away from that point. VGS-2527's traced failure at
# tmp/coords2527-repeat-03 used a 600x329 Plugins window: the footer's
# expiry grew the viewport, clamped its scroll and moved Unbind before
# the native press. Hold the real confirmation timer, sample once, then
# expire it before the original hover and one click at that saved point.
# The saved user file, not a handler readback, must hold null afterwards.
# No latency is measured; reported states poll every 200 ms.
# inputs: shell/Core/KeyCapture.qml shell/Core/HyprlandLayer.js shell/Core/HyprlandLayer.qml shell/Core/Compositor.qml shell/Core/Dispatch.js shell/Core/HyprlandState.qml shell/Ui/controls/ShortcutField.qml shell/Ui/controls/BindField.qml shell/Ui/feedback/SaveBar.qml shell/Ui/layout/Pane.qml shell/plugins/vgs.settings/manifest.json shell/plugins/vgs.settings/Service.qml shell/plugins/vgs.settings/Window.qml shell/plugins/vgs.settings/ListPage.qml shell/plugins/vgs.settings/PluginPage.qml shell/plugins/vgs.settings/PageHeader.qml shell/plugins/vgs.settings/EditSet.qml shell/plugins/vgs.settings/Steps.js shell/plugins/vgs.settings/KeyField.qml shell/Commons/Reply.js shell/plugins/vgs.themes/manifest.json shell/plugins/vgs.themes/Service.qml shell/plugins/vgs.themes/Background.qml scripts/smoke/rows/hyprland-consent.sh
set -euo pipefail

kcs_overflow() {
  ipc smoke viewHolding window vgs.settings Unbind | py_reply 'import json,sys
d=json.load(sys.stdin)
print("overflowing" if d["contentHeight"] > d["height"] else json.dumps(d))'
}
kcs_expire_click() {
  local frame rect point x y
  expect "Saved expiry: the real confirmation clock is held" holding ipc smoke savedFooter window vgs.settings hold || return
  expect_poll "Saved expiry: the footer is fully drawn with its clock held" held ipc smoke savedFooter window vgs.settings phase || return
  ipc smoke revealText window vgs.settings IconButton Unbind >/dev/null || return
  # This is the sole target sample. The same reading proves there is
  # enough scroll and footer room for the old collapse to miss the button.
  frame="$(ipc smoke savedFooter window vgs.settings read)" || return
  rect="$(py_reply 'import json,sys
d=json.load(sys.stdin); b=d.get("button"); v=d["viewport"]
if (d.get("phase") == "held" and isinstance(b,list) and len(b) == 4
    and b[2] > 0 and b[3] > 0 and b[1] >= v[1] and b[1] + b[3] <= v[1] + v[3]
    and d["contentHeight"] > v[3]
    and d["contentY"] > b[3] and d["footerHeight"] + d["footerGap"] > b[3]):
    print(json.dumps(b))
else:
    print("unavailable " + json.dumps(d))' <<<"$frame")" || return
  [[ $rect == \[* ]] || { printf 'Saved expiry: target sample=%s\n' "$rect" >&2; return 1; }
  point="$(at_centre window:Plugins "$rect")" || return
  [[ $point =~ ^-?[0-9]+\ -?[0-9]+$ ]] || { printf 'Saved expiry: target centre=%s\n' "$point" >&2; return 1; }
  read -r x y <<<"$point"
  printf 'key-capture-savebar: held=%s target=%s centre=%s\n' "$frame" "$rect" "$point"
  expect "Saved expiry: the real confirmation clock expires" ok ipc smoke savedFooter window vgs.settings expire || return
  expect_poll "Saved expiry: the confirmation has finished fading" expired ipc smoke savedFooter window vgs.settings phase || return
  hover "$((x + 1))" "$y" || return
  click "$x" "$y"
}
leak_plugin_setup vgs.themes true || { fail "Saved expiry: Themes fixture precondition failed"; return 1; }
expect "Saved expiry: Plugins opens its own page" ok ipc shell summon window vgs.settings '{"plugin":"vgs.settings"}'
expect_poll "Saved expiry: Plugins shows its own page" '"vgs.settings"' ipc smoke readInstance window vgs.settings page
expect_poll "Saved expiry: Plugins has the keyboard" "[\"$shell_class\", \"Plugins\"]" active_window
key_reset "Saved expiry start"
expect "Saved expiry: the text entry opens" typing settings_key_invoke typeKeyField
type_keys SUPER+SHIFT+T || fail "Saved expiry: typing the key failed"
type_keys -k Return || fail "Saved expiry: accepting the typed key failed"
expect_poll "Saved expiry: the typed key is stored" '"SUPER+SHIFT+T"' settings_key
expect_poll "Saved expiry: the key field has the keyboard again" true settings_key_field focus
# The existing floating-window resize dispatcher is exercised by
# rows/settings.sh; read its actual size before the coordinate sequence.
expect "Saved expiry: Plugins takes the overflowing fixture size" ok hypr dispatch 'hl.dsp.window.resize({ x = 600, y = 329, relative = false, window = "title:^Plugins$" })'
geometry expect_poll "Saved expiry: the compositor reports the fixture size" '[[600, 329]]' window_of Plugins size
geometry expect_poll "Saved expiry: the Keys viewport overflows" overflowing kcs_overflow
coordinate_observation "Saved expiry" kcs_expire_click
expect_poll "Saved expiry: the sampled Unbind click stores null" null settings_key

expect "Saved expiry: the confirmation fixture is released" ok ipc smoke savedFooter window vgs.settings release
key_reset "Saved expiry end"
expect "Saved expiry: Plugins closes" ok ipc shell hide window vgs.settings
expect_poll "Saved expiry: the Plugins window is gone" 0 window_count Plugins
