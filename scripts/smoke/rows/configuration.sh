# An unreadable user file settles, keeps the bar, and refuses every write
# until it reads again. A user file the shell reads and the disk refuses to
# write answers the write with the refusal and keeps its value.
# inputs: shell/Core/Config.qml shell/Core/PluginLogic.js shell/Core/Registry.qml shell/plugins/vgs.bar/manifest.json shell/plugins/vgs.bar/Bar.qml bin/vgshell shell/Commons/WatchedFile.qml bin/vgshell-plugin-judge scripts/smoke/rows/capability-release.sh
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

# Model the pending bar cutover in a disposable tree. Its manifest and bar
# both retire left; the saved field stays in the file and gets one notice.
configuration_retire_bar() {
  local name="$1"
  copy_tree "$name" && edit_tree "$name" shell/plugins/vgs.bar/manifest.json \
    $'    "left": ["workspaces"],\n' '' && edit_tree "$name" shell/plugins/vgs.bar/Bar.qml \
    'const names = shell.settings[section];' 'const names = section === "left" ? [] : shell.settings[section];'
}
configuration_setting_notices() {
  ipc shell listPlugins | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps([{"id":e["id"],"keys":e["keys"]} for e in d["errors"] if e.get("kind")=="unknown-settings" and e.get("id")=="vgs.bar"], sort_keys=True))'
}
configuration_saved_left() {
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps(next(e["left"] for e in d["plugins"] if e["id"]=="vgs.bar")))' "$home/.config/vgshell/shell.json"
}
if configuration_retire_bar configuration-retired-setting; then
  stop_shell || :
  python3 - "$home/.config/vgshell/shell.json" <<'PY'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p))
d["plugins"] = [e for e in d.get("plugins", []) if e["id"] != "vgs.bar"] + [{"id":"vgs.bar", "left":["workspaces"]}]
json.dump(d, open(p + ".tmp", "w"), indent=2)
os.replace(p + ".tmp", p)
PY
  if start_shell "$sandbox/tree-configuration-retired-setting" "$sandbox/configuration-retired-setting-qs.log"; then
    expect_poll "the retired bar field gets one typed notice" '[{"id": "vgs.bar", "keys": ["left"]}]' configuration_setting_notices
    expect "editing another plugin leaves the retired field in the file" ok ipc shell setPluginEnabled acme.tick false
    expect "the saved retired field stays after the edit" '["workspaces"]' configuration_saved_left
    expect "the other plugin is enabled again" ok ipc shell setPluginEnabled acme.tick true
    stop_shell || :
    if edit_tree configuration-retired-setting shell/Core/Registry.qml \
        'errors.concat(extra, watchError, unknownSettings)' 'errors.concat(extra, watchError)'; then
      if start_shell "$sandbox/tree-configuration-retired-setting" "$sandbox/configuration-hidden-setting-qs.log"; then
        expect_poll "control: removing the notice makes the positive typed check fail" '[]' configuration_setting_notices
        expect "control: the retired field still reaches the shell's saved file" '["workspaces"]' configuration_saved_left
      fi
    fi
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
