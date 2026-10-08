# An unreadable user file settles, keeps the bar, and refuses every write
# until it reads again. A user file the shell reads and the disk refuses to
# write answers the write with the refusal and keeps its value.
# inputs: shell/Core/Config.qml shell/Core/PluginLogic.js shell/Core/Registry.qml shell/Core/Plugins.qml shell/Core/Capabilities.qml shell/plugins/vgs.settings/Window.qml shell/plugins/vgs.bar/manifest.json shell/plugins/vgs.bar/Bar.qml shell/plugins/vgs.bar/Service.qml bin/vgshell shell/Commons/WatchedFile.qml bin/vgshell-plugin-judge scripts/smoke/rows/capability-release.sh
set -euo pipefail
config_user_state() { ipc shell listPlugins | py_reply 'import json,sys; print(json.load(sys.stdin)["config"]["user"])'; }
expected_errors+=('config: user file unreadable at ')
chmod 000 "$home/.config/vgshell/shell.json"
expect "reloading an unreadable user file answers ok" ok ipc shell reloadConfig
expect_poll "the user file reads as unreadable" unreadable config_user_state
expect "a write to an unreadable user file is refused" "refused: user-config=unreadable path=$home/.config/vgshell/shell.json" ipc shell setPluginEnabled acme.tick false
expect "the bar stays with an unreadable user file" "$monitors" bar_count
chmod 644 "$home/.config/vgshell/shell.json"
expect "reloading the readable user file answers ok" ok ipc shell reloadConfig
expect_poll "the user file reads as loaded again" loaded config_user_state

# A read-only user file: FileView refuses the write, the answer is the keyed
# refusal naming the file with the error after it, and neither the plugin
# nor the file changes. Writable again, a write answers ok and the file
# holds it; that write is polled, since every write is refused until the
# shell has read the file again after the failure.
unwritable_reply() {
  local reply
  reply="$(ipc shell setPluginEnabled acme.tick false)" || return
  if [[ $reply == "refused: user-config=unwritable path=$home/.config/vgshell/shell.json error="?* ]]; then echo keyed; else printf '%s\n' "$reply"; fi
}
file_disables() { python3 -c 'import json,sys; print(sys.argv[2] in json.load(open(sys.argv[1])).get("disabledPlugins", []))' "$home/.config/vgshell/shell.json" "$1"; }
expected_errors+=('config: user file not written at ')
cp -p -- "$home/.config/vgshell/shell.json" "$sandbox/configuration-unwritable.json"
chmod 444 "$home/.config/vgshell/shell.json"
expect "a write the disk refuses answers the unwritable refusal with its error" keyed unwritable_reply
expect "the plugin stays enabled after the refused write" True plugin_enabled acme.tick
expect "the read-only user file keeps its bytes" same bash -c 'cmp -s -- "$1" "$2" && echo same' _ "$sandbox/configuration-unwritable.json" "$home/.config/vgshell/shell.json"
chmod 644 "$home/.config/vgshell/shell.json"
expect_poll "a write to the writable user file answers ok" ok ipc shell setPluginEnabled acme.tick false
expect "the user file holds the write" True file_disables acme.tick
expect "enabling the plugin again answers ok" ok ipc shell setPluginEnabled acme.tick true
expect "the user file holds the plugin enabled again" False file_disables acme.tick
expect_widgets "the widget is back after the unwritable rows" '["acme.tick"]'

# A user file that parses but fails PluginLogic.configError is malformed: the
# defect is logged, the last good value keeps the bar, and writes are refused
# until the file passes again.
user_good="$(cat "$home/.config/vgshell/shell.json")"
expected_errors+=('config: .*/shell\.json malformed: plugins\.0 must be an object with a string id')
printf '{ "version": 1, "plugins": ["acme.tick"] }\n' >"$home/.config/vgshell/shell.json.tmp" && mv -T -- "$home/.config/vgshell/shell.json.tmp" "$home/.config/vgshell/shell.json"
expect_poll "a user file with a malformed plugins row reads as malformed" malformed config_user_state
expect_log "the malformed row is logged with its path in the file" 1 'config: .*/shell\.json malformed: plugins\.0 must be an object with a string id'
expect "a write to a malformed user file is refused" "refused: user-config=malformed path=$home/.config/vgshell/shell.json" ipc shell setPluginEnabled acme.tick false
expect "the bar stays with a malformed user file" "$monitors" bar_count
expect_widgets "the placed widget stays with a malformed user file" '["acme.tick"]'
printf '%s\n' "$user_good" >"$home/.config/vgshell/shell.json.tmp" && mv -T -- "$home/.config/vgshell/shell.json.tmp" "$home/.config/vgshell/shell.json"
expect_poll "the user file reads as loaded once the row is fixed" loaded config_user_state

# An id the user file lists that no discovered plugin has, as a removed
# plugin leaves behind, is reported by `vgshell plugin list` under the key
# that lists it, and the file keeps it. The rows read the one id they
# plant; the failed-builds rows leave their own removed fixture listed.
plugin_list_unknown() {
  local listed
  listed="$("${shell_env[@]}" "$repo/bin/vgshell" plugin list)" || return
  grep -F 'unknown vgs.background ' <<<"$listed" || [[ $? == 1 ]]
}
python3 - "$home/.config/vgshell/shell.json" <<'PY'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p))
d["disabledPlugins"] = d.get("disabledPlugins", []) + ["vgs.background"]
json.dump(d, open(p + ".tmp", "w"), indent=2)
os.replace(p + ".tmp", p)
PY
expect_poll "vgshell plugin list names a disabled id no plugin has" "unknown vgs.background in disabledPlugins" plugin_list_unknown
printf '%s\n' "$user_good" >"$home/.config/vgshell/shell.json.tmp" && mv -T -- "$home/.config/vgshell/shell.json.tmp" "$home/.config/vgshell/shell.json"
expect_poll "vgshell plugin list names no unknown id once the file drops it" "" plugin_list_unknown

configuration_control_restore() {
  chmod 644 "$home/.config/vgshell/shell.json" || :
  printf '%s\n' "$user_good" >"$home/.config/vgshell/shell.json.tmp" && mv -T -- "$home/.config/vgshell/shell.json.tmp" "$home/.config/vgshell/shell.json"
  stop_shell || :
  start_shell "$repo" "$sandbox/configuration-restored-qs.log" || fail "the configuration controls restore the repository shell"
  expect_poll "the user file reads as loaded after the configuration controls restore it" loaded config_user_state
}

if copy_tree configuration-overwrites-malformed && edit_tree configuration-overwrites-malformed shell/Core/Config.qml \
    'if (userState !== "loaded" && userState !== "absent") return "refused: user-config=" + userState + " path=" + userPath;' \
    'if (false && userState !== "loaded" && userState !== "absent") return "refused: user-config=" + userState + " path=" + userPath;'; then
  stop_shell || :
  if start_shell "$sandbox/tree-configuration-overwrites-malformed" "$sandbox/configuration-overwrites-malformed-qs.log"; then
    printf '{ "version": 1, "plugins": ["acme.tick"] }\n' >"$home/.config/vgshell/shell.json.tmp" && mv -T -- "$home/.config/vgshell/shell.json.tmp" "$home/.config/vgshell/shell.json"
    expect_poll "control: the malformed file reaches the overwrite copy" malformed config_user_state
    expect "control: a shell that ignores the bad-state gate overwrites a malformed user file" ok ipc shell setPluginEnabled acme.tick false
    expect "control: the overwritten malformed file disables the plugin" True file_disables acme.tick
  fi
  configuration_control_restore
fi

# Model the pending bar cutover in a disposable tree. The manifest and bar
# retire left; ordinary manager and configure writes discard its saved key.
configuration_retire_bar() {
  local name="$1"
  copy_tree "$name" && edit_tree "$name" shell/plugins/vgs.bar/manifest.json \
    $'    "left": ["workspaces"],\n' '' && edit_tree "$name" shell/plugins/vgs.bar/Bar.qml \
    'const names = shell.settings[section];' 'const names = section === "left" ? [] : shell.settings[section];' && \
    edit_tree "$name" shell/plugins/vgs.bar/Bar.qml \
    'property var shell: null' 'property var shell: null; readonly property bool retiredDelivered: shell !== null && Object.prototype.hasOwnProperty.call(shell.settings, "left")'
}
configuration_saved_left() {
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(any("left" in e for e in d.get("plugins", []) if e["id"]=="vgs.bar"))' "$home/.config/vgshell/shell.json"
}
configuration_plant_left() {
  python3 - "$home/.config/vgshell/shell.json" <<'PYDATA'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p))
d["plugins"] = [e for e in d.get("plugins", []) if e["id"] != "vgs.bar"] + [{"id":"vgs.bar", "left":["workspaces"], "keys":{"toggle":"SUPER+SHIFT+SPACE"}}]
json.dump(d, open(p + ".tmp", "w"), indent=2)
os.replace(p + ".tmp", p)
PYDATA
}
configuration_runtime_left() {
  local key
  key="$(bar_key)" || return
  ipc smoke readInstance "$key" vgs.bar retiredDelivered
}
if configuration_retire_bar configuration-retired-setting; then
  stop_shell || :
  configuration_plant_left
  if start_shell "$sandbox/tree-configuration-retired-setting" "$sandbox/configuration-retired-setting-qs.log"; then
    expect_poll "the retired bar field never enters runtime settings" false configuration_runtime_left
    expect "loading the saved field makes no cleanup write" True configuration_saved_left
    expect "Settings opens for an ordinary setting write" ok ipc shell summon window vgs.settings '{}'
    expect "the ordinary Settings write accepts a declared bar field" ok ipc smoke invokeInstance window vgs.settings applySetting '{"id":"vgs.bar","key":"clockFormat","value":"HH:mm"}'
    expect "the ordinary Settings write removes the saved retired field" False configuration_saved_left
    expect "the ordinary Settings write keeps the declared value and shortcuts" '["HH:mm", {"toggle": "SUPER+SHIFT+SPACE"}]' python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); e=next(e for e in d["plugins"] if e["id"]=="vgs.bar"); print(json.dumps([e["clockFormat"],e["keys"]],sort_keys=True))' "$home/.config/vgshell/shell.json"
    stop_shell || :
    configuration_plant_left
    if start_shell "$sandbox/tree-configuration-retired-setting" "$sandbox/configuration-retired-configure-qs.log"; then
      expect_poll "the configure write starts with no retired runtime setting" false configuration_runtime_left
      expect "the bar service accepts an ordinary configure write" ok ipc vgs.bar invoke toggle ''
      expect "the ordinary configure write removes the saved retired field" False configuration_saved_left
      expect "the bar service restores its visibility" ok ipc vgs.bar invoke toggle ''
    fi
  fi
  configuration_control_restore
fi

if configuration_retire_bar configuration-copy-all-settings && edit_tree configuration-copy-all-settings shell/Core/PluginLogic.js \
    'if (hasOwn(manifest.settings, k) || (stored && ENTRY_RESERVED_KEYS.indexOf(k) !== -1))' \
    'if (stored || ENTRY_RESERVED_KEYS.indexOf(k) === -1)'; then
  stop_shell || :
  configuration_plant_left
  if start_shell "$sandbox/tree-configuration-copy-all-settings" "$sandbox/configuration-copy-all-settings-qs.log"; then
    expect_poll "control: copy-everything delivers the retired runtime field" true configuration_runtime_left
    expect "control: the bar service makes the same ordinary setting write" ok ipc vgs.bar invoke toggle ''
    expect "control: copy-everything leaves the retired field after the write" True configuration_saved_left
    expect "control: the bar service restores its visibility" ok ipc vgs.bar invoke toggle ''
  fi
  configuration_control_restore
fi

if copy_tree configuration-ignores-save-error && edit_tree configuration-ignores-save-error shell/Core/Config.qml \
    $'userView.write(content);\n        if (saveError !== "") return "refused: user-config=unwritable path=" + userPath + " error=" + saveError;\n        user = value;' \
    $'userView.write(content);\n        if (false && saveError !== "") return "refused: user-config=unwritable path=" + userPath + " error=" + saveError;\n        user = value;'; then
  stop_shell || :
  if start_shell "$sandbox/tree-configuration-ignores-save-error" "$sandbox/configuration-ignores-save-error-qs.log"; then
    cp -p -- "$home/.config/vgshell/shell.json" "$sandbox/configuration-save-error-control.json"
    chmod 444 "$home/.config/vgshell/shell.json"
    expect "control: a shell that ignores FileView saveError answers ok for a refused disk write" ok ipc shell setPluginEnabled acme.tick false
    expect "control: the read-only file still keeps its bytes in the saveError control" same bash -c 'cmp -s -- "$1" "$2" && echo same' _ "$sandbox/configuration-save-error-control.json" "$home/.config/vgshell/shell.json"
    chmod 644 "$home/.config/vgshell/shell.json"
  fi
  configuration_control_restore
fi

plugin_list_unknown_with() {
  local bin="$1" listed
  listed="$("${shell_env[@]}" "$bin" plugin list)" || return
  grep -F 'unknown vgs.background ' <<<"$listed" || [[ $? == 1 ]]
}
if copy_tree configuration-hides-unknown && edit_tree configuration-hides-unknown bin/vgshell-plugin-judge \
    'for (const u of reply.unknown) lines.push("unknown " + u.id + " in " + u.key);' \
    'for (const u of []) lines.push("unknown " + u.id + " in " + u.key);'; then
  python3 - "$home/.config/vgshell/shell.json" <<'PY'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p))
d["disabledPlugins"] = d.get("disabledPlugins", []) + ["vgs.background"]
json.dump(d, open(p + ".tmp", "w"), indent=2)
os.replace(p + ".tmp", p)
PY
  expect_poll "control: the repository plugin list sees the planted unknown id" "unknown vgs.background in disabledPlugins" plugin_list_unknown
  expect_poll "control: a plugin list that hides unknown rows prints no unknown id" "" plugin_list_unknown_with "$sandbox/tree-configuration-hides-unknown/bin/vgshell"
  printf '%s\n' "$user_good" >"$home/.config/vgshell/shell.json.tmp" && mv -T -- "$home/.config/vgshell/shell.json.tmp" "$home/.config/vgshell/shell.json"
  expect_poll "the user file reads as loaded after the unknown-row control" loaded config_user_state
fi
