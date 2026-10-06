# Key Hints. SUPER+SLASH, typed on the nested seat, opens one window that
# draws one row for each bind of an enabled first-party plugin: the same
# set as the binds `hyprctl -j binds` reports with a `vgs.` description in
# the default submap, a hold's release companion folded into its bind. A
# harness user bind on SUPER+T, the Themes shortcut's default key, shows
# the hint under the Themes row with no key or click. Typing while the
# Themes row's field has the focus goes into the search field and filters
# the rows, and clearing the search draws them all again. A key typed into
# the Themes row's field is written to the Themes `plugins[].keys` in
# shell.json. A key the manager refuses leaves shell.json as it was and
# reads over the rows as the shared reply line says it, from the manager's
# own key judge under node; the next saved key clears it. The Settings
# page's Keys row for the same shortcut shows the
# same hint, and the same key written from there is the same shell.json
# value, which this window then shows. The row's unbind writes null: the
# bind leaves `hyprctl binds` and its row stays. SUPER+SLASH closes the
# window, opens it again, and the window is then read as every
# application window is (app_window_rows, scripts/smoke/app-window.sh),
# ending closed by Escape. The control starts a tree whose window lists
# every plugin's binds, enabled or not, and whose rows name no bind for
# their field, and disables the launcher, which owns a bind, whatever set
# the shell started over: its rows hold a bind `hyprctl binds` does not
# and the Themes row shows no hint. It leaves the launcher as it found it.
# Every key goes to the nested instance alone, through wtype on its seat,
# with `input:resolve_binds_by_sym` on so a typed key reaches its bind
# (runtime-hyprland-capture.md), and the row puts the harness hyprland.lua
# back at its end.
# No latency is measured; each reading polls every 200 ms for up to 5 s.
# inputs: shell/plugins/vgs.keyhints/* shell/plugins/vgs.settings/* shell/Commons/Reply.js shell/plugins/vgs.themes/manifest.json shell/plugins/vgs.launcher/manifest.json shell/Ui/controls/ShortcutField.qml shell/Ui/controls/BindField.qml shell/Core/KeyCapture.qml shell/Core/HyprlandState.qml shell/Core/HyprlandState.js shell/Core/PluginLogic.js shell/Core/Registry.qml shell/Core/Plugins.qml shell/Core/HyprlandLayer.js bin/lib/qml-library.js
set -euo pipefail

kh_title="Key Hints"
kh_themes='{"id":"vgs.themes","shortcut":"themes"}'
kh_own='{"id":"vgs.keyhints","shortcut":"toggle"}'
# kh_rows: the drawn rows as "<plugin id>:<shortcut>", sorted, or the
# probe's answer; kh_rows vgs. keeps the plugin ids starting so.
kh_rows() {
  ipc smoke itemValues window vgs.keyhints BindField pluginId,bind | py_reply 'import json,sys
print(json.dumps(sorted("%s:%s" % (r["pluginId"], r["bind"]["shortcut"]) for r in json.load(sys.stdin) if r["pluginId"].startswith(sys.argv[1]))))' "${1:-}"
}
# kh_bound: the descriptions of the binds `hyprctl -j binds` reports in the
# default submap starting with `vgs.`, a `.release` companion read as its
# bind, sorted, each once.
kh_bound() {
  hypr -j binds | py_reply 'import json,sys
seen = set()
for b in json.load(sys.stdin):
    d = b["description"]
    if b["submap"] in ("", "default") and d.startswith("vgs."):
        seen.add(d[:-len(".release")] if d.endswith(".release") else d)
print(json.dumps(sorted(seen)))'
}
# kh_same: `same` when the window's vgs. rows are hyprctl's vgs. binds and
# hold this window's own and the Themes one, else both lists.
kh_same() {
  local rows bound
  rows="$(ipc smoke itemValues window vgs.keyhints BindField pluginId,bind)" && bound="$(kh_bound)" || return 1
  python3 -c 'import json,sys
items, b = json.loads(sys.argv[1]), json.loads(sys.argv[2])
rows = sorted("%s:%s" % (r["pluginId"], r["bind"]["shortcut"]) for r in items if r["pluginId"].startswith("vgs.") and r["bind"]["key"] is not None)
keyless = sorted("%s:%s" % (r["pluginId"], r["bind"]["shortcut"]) for r in items if r["pluginId"].startswith("vgs.") and r["bind"]["key"] is None)
required = {"vgs.keyhints:toggle", "vgs.themes:themes"}
print("same" if rows == b and required <= set(rows) and "vgs.voice:tap" in keyless else "rows=%s binds=%s keyless=%s" % (json.dumps(rows), sys.argv[2], json.dumps(keyless)))' "$rows" "$bound"
}
# kh_field ARG PROPERTY: one property of a drawn row's ShortcutField (the
# probe's keyField, which reads the window's rows as it reads the Settings
# page's), as JSON; settings_field PROPERTY: the Settings page's Themes row.
kh_field() { ipc smoke invokeInstance window vgs.keyhints keyField "$1" | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)[sys.argv[1]]))' "$2"; }
settings_field() { ipc smoke invokeInstance window vgs.settings keyField "$kh_themes" | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)[sys.argv[1]]))' "$1"; }
# themes_key: the key the user file gives the Themes shortcut, as JSON, or
# `absent`.
themes_key() { python3 -c 'import json,sys; rows=[r for r in json.load(open(sys.argv[1])).get("plugins", []) if r["id"] == "vgs.themes"]; k=rows[0].get("keys", {}) if rows else {}; print(json.dumps(k["themes"]) if "themes" in k else "absent")' "$home/.config/vgshell/shell.json"; }
kh_toggle() { type_keys -M logo -k slash -m logo; }
# The lines the row appends to the harness hyprland.lua: typed keys reach
# their binds, and a user bind on SUPER+T, the Themes shortcut's default.
kh_lua() {
  printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = true } })' \
    'hl.bind("SUPER + T", hl.dsp.exec_cmd("true"), { description = "Smoke keyhints t" })' >>"$home/.config/hypr/hyprland.lua"
}
# kh_refused: the line the window shows for the Themes key SUPER+, as JSON:
# the manager's key judge's refusal, worded by the shared reply line.
kh_refused() {
  node -e 'const { load } = require(process.argv[1]); const logic = load(process.argv[2]); const reply = load(process.argv[3]);
const manifest = JSON.parse(require("node:fs").readFileSync(process.argv[4], "utf8"));
process.stdout.write(JSON.stringify(reply.line(logic.keyRefusal(manifest, "themes", "SUPER+"))) + "\n");' \
    "$repo/bin/lib/qml-library.js" "$repo/shell/Core/PluginLogic.js" "$repo/shell/Commons/Reply.js" "$repo/shell/plugins/vgs.themes/manifest.json"
}
expected_errors+=('keyhints: key vgs\.themes:themes refused: key=themes has an empty part')
# kh_hint_within ARG HINT: `shown` once the row's hint reads HINT within
# expect_poll's window, 25 readings 200 ms apart, else `absent`.
kh_hint_within() {
  local got
  for _ in $(seq 1 25); do
    got="$(kh_field "$1" conflict)" || return 1
    [[ $got == "$2" ]] && { echo shown; return 0; }
    sleep 0.2
  done
  echo absent
}

hypr_lua_save keyhints
kh_lua
expect "the nested instance reloads with the Key Hints harness bind" ok hypr reload config-only
kh_user_hint="\"Also used by your Hyprland config at ~/.config/hypr/hyprland.lua line $(grep -nF 'hl.bind("SUPER + T"' "$home/.config/hypr/hyprland.lua" | cut -d: -f1).\""
kh_config_errors() { hypr -j configerrors | py_reply 'import json,sys; print(json.dumps([e for e in json.load(sys.stdin) if e]))'; }
expect_poll "the nested instance holds no configuration error" '[]' kh_config_errors

expect "enabling Key Hints is allowed" ok ipc shell setPluginEnabled vgs.keyhints true
expect_poll "the Key Hints service is built" True record_exists vgs.keyhints
kh_toggle || fail "typing SUPER+SLASH failed"
expect_poll "SUPER+SLASH opens the Key Hints window" 1 window_count "$kh_title"
expect_poll "the Key Hints window has the keyboard" "[\"$shell_class\", \"$kh_title\"]" active_window
expect_poll "the window draws exactly the vgs. binds hyprctl reports" same kh_same
expect_poll "the Themes row shows the user bind on its default key with no interaction" "$kh_user_hint" kh_field "$kh_themes" conflict

expect_poll "the Themes row's field takes the focus" focused ipc smoke invokeInstance window vgs.keyhints focusKeyField "$kh_themes"
type_keys "wallpaper" || fail "typing on the Themes row's field failed"
expect_poll "typing on a row's field filters the rows" '["vgs.themes:wallpapers"]' kh_rows
type_keys -M ctrl -k a -m ctrl -k BackSpace || fail "clearing the search field failed"
expect_poll "a cleared search draws every row again" same kh_same

expect "the Themes row's text entry opens" typing ipc smoke invokeInstance window vgs.keyhints typeKeyField "$kh_themes"
type_keys "super+slash" || fail "typing the Themes key failed"
type_keys -k Return || fail "Return in the Themes row's text entry failed"
expect_poll "the typed key is written to the Themes keys in shell.json" '"SUPER+SLASH"' themes_key
kh_written="$(themes_key)"
expect_poll "the Themes row names this window's shortcut on the same key" '"Also used by Key Hints (toggle)."' kh_field "$kh_themes" conflict
expect_poll "this window's own row names the Themes shortcut" '"Also used by Themes (themes)."' kh_field "$kh_own" conflict
kh_refusal="$(kh_refused)" || fail "the manager's key refusal could not be worded"
[[ $kh_refusal != '""' ]] || fail "the shared reply line words the key refusal as nothing"
expect "a key the manager refuses is applied" applied ipc smoke invokeInstance window vgs.keyhints applyKey '{"id":"vgs.themes","shortcut":"themes","key":"SUPER+"}'
expect_poll "the refusal reads over the rows in the shared reply line's words" "$kh_refusal" ipc smoke readInstance window vgs.keyhints notice
expect "the refused key leaves shell.json as it was" "$kh_written" themes_key
expect "the same key again is applied" applied ipc smoke invokeInstance window vgs.keyhints applyKey '{"id":"vgs.themes","shortcut":"themes","key":"SUPER+SLASH"}'
expect_poll "the saved key clears the refusal" '""' ipc smoke readInstance window vgs.keyhints notice

expect "Settings is summoned on the Themes page" ok ipc shell summon window vgs.settings '{"plugin":"vgs.themes"}'
expect_poll "the Settings window shows the Themes page" '"vgs.themes"' ipc smoke readInstance window vgs.settings page
expect_poll "the Settings Keys row shows the key written here" '"SUPER+SLASH"' settings_field key
expect_poll "the Settings Keys row shows the same hint" '"Also used by Key Hints (toggle)."' settings_field conflict
expect "the Settings Keys row's reset is applied" applied ipc smoke invokeInstance window vgs.settings applyKey "$kh_themes"
expect_poll "the reset removes the Themes key from shell.json" absent themes_key
expect_poll "the Themes row here shows the default key again" '"SUPER+T"' kh_field "$kh_themes" key
expect "the Settings Keys row writes the same key" applied ipc smoke invokeInstance window vgs.settings applyKey '{"id":"vgs.themes","shortcut":"themes","key":"super+slash"}'
expect_poll "the Settings page writes the value this window wrote" "$kh_written" themes_key
expect_poll "the Themes row here shows the key the Settings page wrote" '"SUPER+SLASH"' kh_field "$kh_themes" key
kh_settings_hint="$(settings_field conflict)" || kh_settings_hint=unread
expect "the Settings Keys row still names this window's shortcut" '"Also used by Key Hints (toggle)."' printf '%s\n' "$kh_settings_hint"
expect_poll "the Themes row here shows the hint the Settings page shows" "$kh_settings_hint" kh_field "$kh_themes" conflict
expect "the Settings window is hidden" ok ipc shell hide window vgs.settings
expect_poll "the Settings window is gone" 0 window_count Plugins

# kh_bound_has BIND: whether hyprctl reports the bind "<plugin id>:<shortcut>".
kh_bound_has() { kh_bound | py_reply 'import json,sys; print(sys.argv[1] in json.load(sys.stdin))' "$1"; }
expect "the Themes row's unbind is applied" applied ipc smoke invokeInstance window vgs.keyhints applyKey '{"id":"vgs.themes","shortcut":"themes","key":null}'
expect_poll "the unbind writes null to shell.json" null themes_key
expect_poll "the unbound Themes bind leaves hyprctl binds" False kh_bound_has vgs.themes:themes
kh_drawn_has() { kh_rows vgs.themes | py_reply 'import json,sys; print("vgs.themes:themes" in json.load(sys.stdin))'; }
expect "the unbound Themes row stays drawn" True kh_drawn_has
expect_poll "the unbound Themes row holds no key" '""' kh_field "$kh_themes" key
expect "the Themes key is reset" applied ipc smoke invokeInstance window vgs.keyhints applyKey "$kh_themes"
expect_poll "the reset Themes bind is back in hyprctl binds" True kh_bound_has vgs.themes:themes

kh_toggle || fail "typing SUPER+SLASH to close failed"
expect_poll "SUPER+SLASH closes the Key Hints window" 0 window_count "$kh_title"
kh_toggle || fail "typing SUPER+SLASH to open again failed"
expect_poll "SUPER+SLASH opens the Key Hints window again" 1 window_count "$kh_title"
hypr_lua_restore keyhints || fail "Key Hints puts the harness hyprland.lua back"
expect "the nested instance reloads the harness hyprland.lua" ok hypr reload config-only
app_window_rows "$kh_title" vgs.keyhints

# The control: a window that lists every plugin's binds, and rows that name
# no bind for their field. With the launcher disabled its rows hold a bind
# hyprctl lacks, and a user bind on the Themes key draws no hint.
if copy_tree keyhints-unfiltered \
  && edit_tree keyhints-unfiltered shell/plugins/vgs.keyhints/Window.qml 'shell.manager.plugins.filter(p => p.enabled)' 'shell.manager.plugins.filter(p => true)' \
  && edit_tree keyhints-unfiltered shell/Ui/controls/BindField.qml '        pluginId: root.pluginId' '        pluginId: ""'; then
  hypr_lua_save keyhints-control
  kh_lua
  expect "control: the nested instance reloads with the harness bind" ok hypr reload config-only
  stop_shell
  start_shell "$sandbox/tree-keyhints-unfiltered" "$sandbox/keyhints-unfiltered.log" || fail "the Key Hints control shell starts"
  expect_poll "control: the Key Hints service is built" True record_exists vgs.keyhints
  expect "control: Key Hints is summoned" ok ipc shell summon window vgs.keyhints '{}'
  expect_poll "control: the window maps" 1 window_count "$kh_title"
  kh_launcher_before="$(plugin_enabled vgs.launcher)" || kh_launcher_before=unread
  expect "control: disabling the launcher is allowed" ok ipc shell setPluginEnabled vgs.launcher false
  expect_poll "control: the disabled launcher's bind is not in hyprctl binds" False kh_bound_has vgs.launcher:toggle
  expect_poll "control: the unfiltered window draws the disabled launcher's row" '["vgs.launcher:toggle"]' kh_rows vgs.launcher
  kh_differs() { local got; got="$(kh_same)" || return 1; [[ $got == same ]] && echo same || echo differs; }
  expect_poll "control: rows of disabled plugins differ from hyprctl's binds" differs kh_differs
  expect "control: the Themes row draws no hint within the real reading's window" absent kh_hint_within "$kh_themes" "$kh_user_hint"
  expect "control: Key Hints is hidden" ok ipc shell hide window vgs.keyhints
  case "$kh_launcher_before" in
    True)
      expect "control: the launcher is enabled again" ok ipc shell setPluginEnabled vgs.launcher true
      expect_poll "control: the launcher's bind is back in hyprctl binds" True kh_bound_has vgs.launcher:toggle
      ;;
    False) ;;
    *) fail "control: the launcher's enabled state before the control: got $kh_launcher_before" ;;
  esac
  stop_shell
  hypr_lua_restore keyhints-control || fail "the Key Hints control puts the harness hyprland.lua back"
  expect "control: the nested instance reloads the harness hyprland.lua" ok hypr reload config-only
  start_shell "$repo" "$sandbox/keyhints-restart.log" || fail "the shell starts again after the Key Hints control"
fi
expect "disabling Key Hints is allowed" ok ipc shell setPluginEnabled vgs.keyhints false
expect_poll "the Key Hints service is gone" False record_exists vgs.keyhints
