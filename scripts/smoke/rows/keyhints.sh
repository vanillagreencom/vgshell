# Key Hints. SUPER+SLASH, typed on the nested seat, opens one window that
# draws one row for each bind of an enabled first-party plugin: the same
# set as the binds `hyprctl -j binds` reports with a `vgs.` description in
# the default submap, a hold's release companion folded into its bind, and
# one row with no key for a bind that has none. The row enables Voice for
# that keyless bind, its tap shortcut, whatever set the shell started over,
# and unbinds the tap from its row, then resets it, which binds its default
# keys again; with Voice disabled the window draws the same keyed rows and
# no Voice tap row, the keyless reading's control. It then leaves Voice as
# it found it. A harness user bind on SUPER+SHIFT+T, the Themes shortcut's default key, shows
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
# with `input:resolve_binds_by_sym` on so a typed key reaches its bind,
# since a bind resolves a virtual keyboard's key only by keysym, and the
# row puts the harness hyprland.lua
# back at its end.
# The open budget is the owner's 200 ms. VGS-1057's nested baseline on
# 2026-10-07 on host cachy built 34 rows with all 32 shipped plugins enabled: the first
# native frame took 4478 ms (tmp/VGS-1057/baseline.json). The timer reads
# the shortcut handler and QQuickWindow.frameSwapped, before visibility;
# polling every 200 ms only waits for those timestamped readings. CPU
# pressure spans shortcut send through native-frame readback; each open
# prints its actual pressure sampling interval. The ceiling holds at any pressure.
# Restoring eager Tooltip window construction must exceed the same budget.
# inputs: shell/plugins/vgs.keyhints/* shell/plugins/vgs.settings/* shell/Commons/Reply.js shell/plugins/vgs.themes/manifest.json shell/plugins/vgs.launcher/manifest.json shell/plugins/vgs.voice/manifest.json shell/Ui/controls/ShortcutField.qml shell/Ui/controls/BindField.qml shell/Ui/controls/Field.qml shell/Ui/controls/FormRow.qml shell/Ui/overlay/Tooltip.qml shell/Ui/overlay/AnchorTracker.qml shell/Hosts/AppWindow.qml shell/Core/KeyCapture.qml shell/Core/HyprlandState.qml shell/Core/HyprlandState.js shell/Core/PluginLogic.js shell/Core/Registry.qml shell/Core/Plugins.qml shell/Core/HyprlandLayer.js bin/lib/qml-library.js
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
# kh_bound_has BIND: whether hyprctl reports the bind "<plugin id>:<shortcut>".
kh_bound_has() { kh_bound | py_reply 'import json,sys; print(sys.argv[1] in json.load(sys.stdin))' "$1"; }
# kh_same: `same` when the window's keyed vgs. rows are hyprctl's vgs. binds,
# hold this window's own and the Themes one, and its keyless rows hold the
# Voice tap; `tap-missing` and the keyless rows when only the Voice tap is
# absent; else every list.
kh_same() {
  local rows bound
  rows="$(ipc smoke itemValues window vgs.keyhints BindField pluginId,bind)" && bound="$(kh_bound)" || return 1
  python3 -c 'import json,sys
items, b = json.loads(sys.argv[1]), json.loads(sys.argv[2])
rows = sorted("%s:%s" % (r["pluginId"], r["bind"]["shortcut"]) for r in items if r["pluginId"].startswith("vgs.") and r["bind"]["key"] is not None)
keyless = sorted("%s:%s" % (r["pluginId"], r["bind"]["shortcut"]) for r in items if r["pluginId"].startswith("vgs.") and r["bind"]["key"] is None)
required = {"vgs.keyhints:toggle", "vgs.themes:themes"}
keyed = rows == b and required <= set(rows)
if keyed and "vgs.voice:tap" in keyless:
    print("same")
elif keyed:
    print("tap-missing keyless=%s" % json.dumps(keyless))
else:
    print("rows=%s binds=%s keyless=%s" % (json.dumps(rows), sys.argv[2], json.dumps(keyless)))' "$rows" "$bound"
}
# kh_verdict: the first word of kh_same.
kh_verdict() { local got; got="$(kh_same)" || return 1; echo "${got%% *}"; }
# kh_field ARG PROPERTY: one property of a drawn row's ShortcutField (the
# probe's keyField, which reads the window's rows as it reads the Settings
# page's), as JSON; settings_field PROPERTY: the Settings page's Themes row.
kh_field() { ipc smoke invokeInstance window vgs.keyhints keyField "$1" | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)[sys.argv[1]]))' "$2"; }
kh_spacing() { ipc smoke itemValues window vgs.keyhints Section rowSpacing | py_reply 'import json,sys; rows=json.load(sys.stdin); print(bool(rows and all(r["rowSpacing"] == float(sys.argv[1]) for r in rows)))' "$(ipc smoke themeValue stack.group)"; }
settings_field() { ipc smoke invokeInstance window vgs.settings keyField "$kh_themes" | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)[sys.argv[1]]))' "$1"; }
# themes_key: the key the user file gives the Themes shortcut, as JSON, or
# `absent`.
themes_key() { python3 -c 'import json,sys; rows=[r for r in json.load(open(sys.argv[1])).get("plugins", []) if r["id"] == "vgs.themes"]; k=rows[0].get("keys", {}) if rows else {}; print(json.dumps(k["themes"]) if "themes" in k else "absent")' "$home/.config/vgshell/shell.json"; }
kh_toggle() { type_keys -M logo -k slash -m logo; }
# The lines the row appends to the harness hyprland.lua: typed keys reach
# their binds, and a user bind on SUPER+SHIFT+T, the Themes shortcut's default.
kh_lua() {
  printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = true } })' \
    'hl.bind("SUPER + SHIFT + T", hl.dsp.exec_cmd("true"), { description = "Smoke keyhints t" })' >>"$home/.config/hypr/hyprland.lua"
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

# The service-built reader preserves failed and malformed replies as unread.
kh_record_reader="$(declare -f record_exists)"
expect 'the readiness reader finds a built service' True bash -c "$kh_record_reader
ipc() { printf '%s\n' '{\"services\":[{\"id\":\"vgs.keyhints\"}]}'; }
record_exists vgs.keyhints"
expect 'the readiness reader finds an absent service' False bash -c "$kh_record_reader
ipc() { printf '%s\n' '{\"services\":[]}'; }
record_exists vgs.keyhints"
expect 'control: unavailable built reply stays unread' unavailable bash -c "$kh_record_reader
ipc() { return 1; }
record_exists vgs.keyhints"
expect 'control: malformed built reply stays unread' unavailable bash -c "$kh_record_reader
ipc() { printf '%s\n' 'unavailable'; }
record_exists vgs.keyhints"
expect 'control: wrong built reply shape stays unread' unavailable bash -c "$kh_record_reader
ipc() { printf '%s\n' '{\"services\":[{}]}'; }
record_exists vgs.keyhints"
unset kh_record_reader

hypr_lua_save keyhints
kh_lua
expect "the nested instance reloads with the Key Hints harness bind without configuration errors" '[]' hypr_reload_errors
kh_user_hint="\"Also used by your Hyprland config at ~/.config/hypr/hyprland.lua line $(grep -nF 'hl.bind("SUPER + SHIFT + T"' "$home/.config/hypr/hyprland.lua" | cut -d: -f1).\""

kh_voice_before="$(plugin_enabled vgs.voice)" || kh_voice_before=unread
kh_themes_before="$(plugin_enabled vgs.themes)" || kh_themes_before=unread
expect "enabling Themes for its Key Hints row is allowed" ok ipc shell setPluginEnabled vgs.themes true
expect_poll "the Themes shortcut reaches Hyprland before its row is read" True kh_bound_has vgs.themes:themes
expect "enabling Voice is allowed" ok ipc shell setPluginEnabled vgs.voice true
expect_poll "the Voice service is built" True record_exists vgs.voice
expect "enabling Key Hints is allowed" ok ipc shell setPluginEnabled vgs.keyhints true
expect_poll "the Key Hints service is built" True record_exists vgs.keyhints
expect_poll "the Key Hints shortcut reaches Hyprland before its first key" True kh_bound_has vgs.keyhints:toggle
kh_toggle || fail "typing SUPER+SLASH failed"
expect_poll "SUPER+SLASH opens the Key Hints window" 1 window_count "$kh_title"
expect_poll "the Key Hints window has the keyboard" "[\"$shell_class\", \"$kh_title\"]" active_window
expect "the Voice tap row's unbind is applied" applied ipc smoke invokeInstance window vgs.keyhints applyKey '{"id":"vgs.voice","shortcut":"tap","key":null}'
expect_poll "the unbound Voice tap leaves hyprctl binds" False kh_bound_has vgs.voice:tap
expect_poll "the window draws exactly the vgs. binds hyprctl reports" same kh_same
expect "Key Hints rows use the shared group spacing token" True kh_spacing
expect_poll "the Themes row shows the user bind on its default key with no interaction" "$kh_user_hint" kh_field "$kh_themes" conflict

expect_poll "the Themes row's field takes the focus" focused ipc smoke invokeInstance window vgs.keyhints focusKeyField "$kh_themes"
type_keys "wallpaper" || fail "typing on the Themes row's field failed"
expect_poll "typing on a row's field filters the rows" '["vgs.themes:wallpapers"]' kh_rows
type_keys -M ctrl -k a -m ctrl -k BackSpace || fail "clearing the search field failed"
expect_poll "a cleared search draws every row again" same kh_same
expect "the Voice tap key is reset" applied ipc smoke invokeInstance window vgs.keyhints applyKey '{"id":"vgs.voice","shortcut":"tap"}'
expect_poll "the reset Voice tap is back in hyprctl binds" True kh_bound_has vgs.voice:tap

expect "control: disabling Voice is allowed" ok ipc shell setPluginEnabled vgs.voice false
expect_poll "control: with Voice disabled the keyed rows match hyprctl and no keyless Voice tap row is drawn" tap-missing kh_verdict
case "$kh_voice_before" in
  True)
    expect "Voice is enabled again as the row found it" ok ipc shell setPluginEnabled vgs.voice true
    expect_poll "the Voice service is built again" True record_exists vgs.voice
    ;;
  False) ;;
  *) fail "Voice's enabled state before the row: got $kh_voice_before" ;;
esac
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
expect_poll "the Themes row here shows the default key again" '"SUPER+SHIFT+T"' kh_field "$kh_themes" key
expect "the Settings Keys row writes the same key" applied ipc smoke invokeInstance window vgs.settings applyKey '{"id":"vgs.themes","shortcut":"themes","key":"super+slash"}'
expect_poll "the Settings page writes the value this window wrote" "$kh_written" themes_key
expect_poll "the Themes row here shows the key the Settings page wrote" '"SUPER+SLASH"' kh_field "$kh_themes" key
kh_settings_hint="$(settings_field conflict)" || kh_settings_hint=unread
expect "the Settings Keys row still names this window's shortcut" '"Also used by Key Hints (toggle)."' printf '%s\n' "$kh_settings_hint"
expect_poll "the Themes row here shows the hint the Settings page shows" "$kh_settings_hint" kh_field "$kh_themes" conflict
expect "the Settings window is hidden" ok ipc shell hide window vgs.settings
expect_poll "the Settings window is gone" 0 window_count Plugins

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
  && edit_tree keyhints-unfiltered shell/plugins/vgs.keyhints/Window.qml 'rowSpacing: Theme.stack.group' 'rowSpacing: Theme.stack.row' \
  && edit_tree keyhints-unfiltered shell/Ui/controls/BindField.qml '        pluginId: root.pluginId' '        pluginId: ""'; then
  hypr_lua_save keyhints-control
  kh_lua
  expect "control: the nested instance reloads with the harness bind" ok hypr reload config-only
  stop_shell
  start_shell "$sandbox/tree-keyhints-unfiltered" "$sandbox/keyhints-unfiltered.log" || fail "the Key Hints control shell starts"
  expect_poll "control: the Key Hints service is built" True record_exists vgs.keyhints
  expect "control: Key Hints is summoned" ok ipc shell summon window vgs.keyhints '{}'
  expect_poll "control: the window maps" 1 window_count "$kh_title"
  expect "control: the old spacing fails the shared group-spacing check" False kh_spacing
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

# Time the real shortcut and first native frame. Each copy changes only
# measurement callbacks; the control removes the LazyLoader wrapper and
# restores direct-owned eager PopupWindow construction, as in the baseline.
kh_timing_tree() {
  local name="$1"
  copy_tree "$name" \
    && edit_tree "$name" shell/plugins/vgs.keyhints/Service.qml '    function toggle() {' '    function toggle() { console.info("keyhints-timing: shortcut=" + Date.now());' \
    && edit_tree "$name" shell/Hosts/AppWindow.qml '    visible: false' '    property bool timed: false
    Connections {
        target: win.contentItem.Window.window
        function onFrameSwapped() {
            if (!win.timed && win.pluginId === "vgs.keyhints") {
                win.timed = true;
                console.info("keyhints-timing: frame=" + Date.now());
            }
        }
    }
    visible: false'
}
kh_timing_samples() {
  python3 - "$instance_log" <<'PY_TIMES'
import json,re,sys
samples=[]
start=None
for line in open(sys.argv[1]):
    found=re.search(r'keyhints-timing: (shortcut|frame)=(\d+)',line)
    if found is None: continue
    kind,at=found.group(1),int(found.group(2))
    if kind == 'shortcut': start=at
    elif start is not None:
        samples.append(at-start)
        start=None
print(json.dumps(samples))
PY_TIMES
}
kh_timing_count() { kh_timing_samples | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
kh_timing_budget() { kh_timing_samples | py_reply 'import json,sys; a=json.load(sys.stdin); print(bool(len(a)>1 and a[0]<=4478 and all(t<=200 for t in a[1:])))'; }
kh_timing_later_budget() { kh_timing_samples | py_reply 'import json,sys; a=json.load(sys.stdin); print(bool(len(a)>1 and all(t<=200 for t in a[1:])))'; }
kh_timing_rows() { ipc smoke itemValues window vgs.keyhints BindField pluginId,bind | py_reply 'import json,sys; print(sum(r["pluginId"].startswith("vgs.") for r in json.load(sys.stdin)))'; }
kh_timing_opens() {
  local count="$1" n before="$failures" pressure start end elapsed sample profile
  expect_poll 'the measured Key Hints shortcut is available' True record_exists vgs.keyhints
  [[ $failures == "$before" ]] || return 1
  profile="$(ipc shell listPlugins | py_reply 'import json,pathlib,sys
plugins={p["id"]:p for p in json.load(sys.stdin)["plugins"]}
shipped=[json.loads(p.read_text())["id"] for p in pathlib.Path(sys.argv[1]).glob("*/manifest.json")]
if not shipped or not all(p in plugins and plugins[p]["enabled"] is True for p in shipped):
    raise ValueError("the measured profile does not enable every shipped plugin")
print(len(shipped))' "$repo/shell/plugins")" || { fail 'the measured all-shipped-plugin profile is unreadable or incomplete'; return 1; }
  printf '  keyhints-profile enabled_shipped=%s baseline_bind_floor=34\n' "$profile"
  rest_pointer || { fail 'the measurement pointer move failed'; return 1; }
  for ((n=1; n<=count; n++)); do
    pressure="$(cpu_some_us)"
    [[ -n $pressure ]] || { fail 'the starting CPU pressure reading is unavailable'; return 1; }
    start="$(now_ms)"
    kh_toggle || { fail 'the measured SUPER+SLASH was not sent'; return 1; }
    expect_poll "the measured open $n presents its first native frame" "$n" kh_timing_count
    [[ $failures == "$before" ]] || return 1
    end="$(cpu_some_us)"
    elapsed=$(( $(now_ms) - start ))
    [[ -n $end && $elapsed -gt 0 ]] || { fail 'the completed CPU pressure interval is unavailable'; return 1; }
    sample="$(kh_timing_samples | py_reply 'import json,sys; print(json.load(sys.stdin)[-1])')" || { fail 'the completed frame sample is unreadable'; return 1; }
    printf '  keyhints-open index=%s latency_ms=%s cpu_some_pct=%s pressure_interval_ms=%s machine=cachy\n' "$n" "$sample" "$(cpu_some_pct "$pressure" "$end" "$elapsed")" "$elapsed"
    expect "the measured open $n has the keyboard" "[\"$shell_class\", \"$kh_title\"]" active_window
    expect "the measured open $n holds the baseline bind workload" True bash -c '[[ "$1" -ge 34 ]] && echo True || echo False' _ "$(kh_timing_rows)"
    [[ $failures == "$before" ]] || return 1
    if ! ipc shell hide window vgs.keyhints; then fail 'the measured window hide failed'; return 1; fi
    expect_poll 'the measured window is destroyed on hide' 0 window_count "$kh_title"
    [[ $failures == "$before" ]] || return 1
  done
  printf '  keyhints-open-ms=%s budget_ms=200\n' "$(kh_timing_samples)"
}

cp -p -- "$home/.config/vgshell/shell.json" "$sandbox/keyhints-timing-config.json"
# The owner's profile includes every shipped plugin. Hardware access and
# authentication remain the harness's device fakes and private buses.
while IFS= read -r id; do
  expect "the measured profile enables $id" ok ipc shell setPluginEnabled "$id" true
done < <(python3 - "$repo/shell/plugins" <<'PY_PLUGINS'
import json,pathlib,sys
for file in sorted(pathlib.Path(sys.argv[1]).glob('*/manifest.json')):
    print(json.loads(file.read_text())['id'])
PY_PLUGINS
)
hypr_lua_save keyhints-timing
printf '%s\n' 'hl.config({ input = { resolve_binds_by_sym = true } })' >>"$home/.config/hypr/hyprland.lua"
expect 'the timed shortcut reloads without configuration errors' '[]' hypr_reload_errors
if kh_timing_tree keyhints-timing; then
  stop_shell
  if start_shell "$sandbox/tree-keyhints-timing" "$sandbox/keyhints-timing.log" && kh_timing_opens 5; then
    expect 'first open is no slower than baseline and all later opens meet 200 ms' True kh_timing_budget
    # Every bind is still a row after the timed window was destroyed.
    expect 'the timed Key Hints window opens for its row count' ok ipc shell summon window vgs.keyhints '{}'
    expect 'the all-plugin measurement holds at least the baseline bind count' True bash -c '[[ "$1" -ge 34 ]] && echo True || echo False' _ "$(kh_timing_rows)"
    expect 'Key Hints sections use the shared group spacing token' True kh_spacing
    expect 'the row-count window is hidden' ok ipc shell hide window vgs.keyhints
  fi
  stop_shell
fi
if kh_timing_tree keyhints-slow \
  && edit_tree keyhints-slow shell/Ui/overlay/Tooltip.qml 'popup.item !== null && popup.item.visible' 'window.visible' \
  && edit_tree keyhints-slow shell/Ui/overlay/Tooltip.qml 'popup.item === null ? null : popup.item.tracker' 'window.tracker' \
  && edit_tree keyhints-slow shell/Ui/overlay/Tooltip.qml '    LazyLoader {
        id: popup
        active: root.shown

        PopupWindow {' '    PopupWindow {' \
  && edit_tree keyhints-slow shell/Ui/overlay/Tooltip.qml '            visible: root.shown' '            visible: root.shown
            onVisibleChanged: if (!visible) root.shown = false' \
  && edit_tree keyhints-slow shell/Ui/overlay/Tooltip.qml '        }
    }

    Connections {
        target: popup.item
        function onVisibleChanged() { if (popup.item !== null && !popup.item.visible) root.shown = false; }
    }' '    }'; then
  if start_shell "$sandbox/tree-keyhints-slow" "$sandbox/keyhints-slow.log" && kh_timing_opens 2; then
    expect 'control: eager popup construction fails the actual later-open budget' False kh_timing_later_budget
  fi
  stop_shell
fi
cp -- "$sandbox/keyhints-timing-config.json" "$home/.config/vgshell/shell.json.next"
mv -T -- "$home/.config/vgshell/shell.json.next" "$home/.config/vgshell/shell.json"
hypr_lua_restore keyhints-timing || fail 'the measured run restores the harness keymap'
expect 'the restored keymap reloads' ok hypr reload config-only
start_shell "$repo" "$sandbox/keyhints-timing-restored.log" || fail 'the original shell starts after measurement'
expect "disabling Key Hints is allowed" ok ipc shell setPluginEnabled vgs.keyhints false
expect_poll "the Key Hints service is gone" False record_exists vgs.keyhints
case "$kh_themes_before" in
  True) ;;
  False)
    expect "Themes is disabled again as the row found it" ok ipc shell setPluginEnabled vgs.themes false
    expect_poll "the restored Themes state removes its shortcut" False kh_bound_has vgs.themes:themes
    ;;
  *) fail "Themes' enabled state before the row: got $kh_themes_before" ;;
esac
