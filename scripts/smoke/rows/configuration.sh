# An unreadable user file settles, keeps the bar, and refuses every write
# until it reads again. A user file the shell reads and the disk refuses to
# write answers the write with the refusal and keeps its value. A version 1
# user file is written as version 4 once the shell reads it, its layout
# entry's settings moved into the plugin's row; a copy whose read migrates
# nothing is its control, and refuses the file. A user file that disables a
# plugin's former id and places its widget names the plugin by its new id
# before the scan publishes it, so the plugin is never built; a copy that
# renames after the scan publishes is its control, and builds it.
# inputs: scripts/smoke/fixtures/plugins/vgs.fixture-renamed/* scripts/smoke/fixtures/plugins/vgs.fixture-split/* shell/Core/Config.qml shell/Core/PluginLogic.js shell/Core/ConfigLogic.js shell/Core/Registry.qml shell/Core/Plugins.qml shell/Core/Capabilities.qml shell/plugins/vgs.settings/Window.qml shell/plugins/vgs.bar/manifest.json shell/plugins/vgs.bar/Bar.qml shell/plugins/vgs.bar/Service.qml bin/vgshell shell/Commons/WatchedFile.qml bin/vgshell-plugin-judge scripts/smoke/rows/capability-release.sh
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

# A user file that parses but fails ConfigLogic.configError is malformed: the
# defect is logged, the last good value keeps the bar, and writes are refused
# until the file passes again.
user_good="$(cat "$home/.config/vgshell/shell.json")"
expected_errors+=('config: .*/shell\.json malformed: plugins\.0 must be an object with a string id')
printf '{ "version": 2, "plugins": ["acme.tick"] }\n' >"$home/.config/vgshell/shell.json.tmp" && mv -T -- "$home/.config/vgshell/shell.json.tmp" "$home/.config/vgshell/shell.json"
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

# A user file of the previous format version is migrated where the shell
# reads it: a key of a layout entry moves into the plugin's row, where the
# row's own value wins, the file is written once as version 4 and the log
# names it.
config_plant_version_one() {
  python3 - "$home/.config/vgshell/shell.json" <<'PY'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p))
d["version"] = 1
d["plugins"] = [r for r in d.get("plugins", []) if r["id"] != "acme.tick"] + [{"id": "acme.tick", "format": "row-wins"}]
entries = [e for s in ("left", "center", "right") for e in d["bar"]["layout"].get(s, []) if e["id"] == "acme.tick"]
assert len(entries) == 1, entries
entries[0].update(format="entry-loses", extra="moves")
json.dump(d, open(p + ".tmp", "w"), indent=2)
os.replace(p + ".tmp", p)
PY
}
# config_migration_read: the user file's version, acme.tick's layout
# entries and its plugins row.
config_migration_read() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); l=d["bar"]["layout"]; print(json.dumps([d.get("version"), [e for s in ("left", "center", "right") for e in l.get(s, []) if e["id"] == "acme.tick"], [r for r in d.get("plugins", []) if r["id"] == "acme.tick"]]))' "$home/.config/vgshell/shell.json"; }
config_migrated_before="$(log_lines 'config: user file migrated: ')" || fail "the instance log is unreadable before the migration"
config_plant_version_one || fail "planting the version 1 user file failed"
expect_poll "a version 1 user file is written as version 4 once it is read" '[4, [{"id": "acme.tick"}], [{"id": "acme.tick", "format": "row-wins", "extra": "moves"}]]' config_migration_read
expect_log "the migration names the file and the version" "$((config_migrated_before + 1))" 'config: user file migrated: file=.*/shell\.json version=4'
expect "the migrated user file reads as loaded" loaded config_user_state
expect_poll "the widget reads the row's value" '"row-wins"' ipc smoke readInstance "$(bar_key)" acme.tick format
printf '%s\n' "$user_good" >"$home/.config/vgshell/shell.json.tmp" && mv -T -- "$home/.config/vgshell/shell.json.tmp" "$home/.config/vgshell/shell.json"
expect_poll "the user file reads as loaded once it is put back" loaded config_user_state

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
    printf '{ "version": 2, "plugins": ["acme.tick"] }\n' >"$home/.config/vgshell/shell.json.tmp" && mv -T -- "$home/.config/vgshell/shell.json.tmp" "$home/.config/vgshell/shell.json"
    expect_poll "control: the malformed file reaches the overwrite copy" malformed config_user_state
    expect "control: a shell that ignores the bad-state gate overwrites a malformed user file" ok ipc shell setPluginEnabled acme.tick false
    expect "control: the overwritten malformed file disables the plugin" True file_disables acme.tick
  fi
  configuration_control_restore
fi

if copy_tree configuration-unmigrated && edit_tree configuration-unmigrated shell/Core/Config.qml \
    'const r = root.judge(path, content, true);' 'const r = root.judge(path, content, false);'; then
  stop_shell || :
  if start_shell "$sandbox/tree-configuration-unmigrated" "$sandbox/configuration-unmigrated-qs.log"; then
    expected_errors+=('config: .*/shell\.json malformed: version must be 4, got 1')
    config_plant_version_one || fail "control: planting the version 1 user file failed"
    expect_poll "control: a shell that migrates nothing refuses the version 1 file" malformed config_user_state
    expect "control: the version 1 file stays as it was" '[1, [{"id": "acme.tick", "format": "entry-loses", "extra": "moves"}], [{"id": "acme.tick", "format": "row-wins"}]]' config_migration_read
  fi
  configuration_control_restore
fi

# A bundled plugin shipped under a new id declares the id it had in its
# manifest's formerIds; only a bundled plugin's claim renames the user file
# (PluginLogic.formerIdClaims). The fixture lands in a tree copy's bundled
# plugins directory, where the scan reads it as bundled. Planted before the
# shell starts, with a user file that disables the former id and places its
# widget, the file takes the new id before anything is built from the scan:
# the plugin never builds, the bar shows no widget for it, and the file
# names it by its new id alone. The fixture is first-party, so it runs
# unless the file disables its new id, and its background builds in the
# turn the scan publishes it; it logs `renamed-fixture: built` from every
# instance.
config_plant_renamed() { # TREE_NAME
  cp -R -- "$repo/scripts/smoke/fixtures/plugins/vgs.fixture-renamed" "$sandbox/tree-$1/shell/plugins/vgs.fixture-renamed" || return
  python3 - "$home/.config/vgshell/shell.json" <<'PY'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p))
d["disabledPlugins"] = d.get("disabledPlugins", []) + ["vgs.fixture-formerly"]
d["bar"]["layout"]["right"] = d["bar"]["layout"].get("right", []) + [{"id": "vgs.fixture-formerly"}]
json.dump(d, open(p + ".tmp", "w"), indent=2)
os.replace(p + ".tmp", p)
PY
}
# config_renamed_read: the user file's disabledPlugins entries and layout
# entries that name the fixture by either id.
config_renamed_read() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); ids=("vgs.fixture-formerly", "vgs.fixture-renamed"); l=d["bar"]["layout"]; print(json.dumps([[i for i in d.get("disabledPlugins", []) if i in ids], [e["id"] for s in ("left", "center", "right") for e in l.get(s, []) if e["id"] in ids]]))' "$home/.config/vgshell/shell.json"; }
config_renamed_restore() {
  stop_shell || :
  configuration_control_restore
}
if copy_tree configuration-renamed; then
  stop_shell || :
  config_plant_renamed configuration-renamed || fail "planting the renamed plugin and its user file failed"
  if start_shell "$sandbox/tree-configuration-renamed" "$sandbox/configuration-renamed-qs.log"; then
    expect_log "the shell's first scan publishes the renamed plugin" 1 'plugins: scan complete changed=true'
    expect_poll "the user file names the renamed plugin by its new id alone" '[["vgs.fixture-renamed"], ["vgs.fixture-renamed"]]' config_renamed_read
    expect_widgets "the bar shows no widget for the renamed plugin its user disabled" '["acme.tick"]'
    expect "the renamed plugin its user disabled is never built" 0 log_lines 'renamed-fixture: built'
  fi
  config_renamed_restore
fi

if copy_tree configuration-renames-late && edit_tree configuration-renames-late shell/Core/Registry.qml \
    $'        if (isChanged) renameUserFile(next);\n        if (isChanged) root.manifests = next;\n        // `scanned` gates every slot key, so it moves after the map.\n        root.scanned = true;\n' \
    $'        if (isChanged) root.manifests = next;\n        // `scanned` gates every slot key, so it moves after the map.\n        root.scanned = true;\n        if (isChanged) renameUserFile(next);\n'; then
  stop_shell || :
  config_plant_renamed configuration-renames-late || fail "control: planting the renamed plugin and its user file failed"
  if start_shell "$sandbox/tree-configuration-renames-late" "$sandbox/configuration-renames-late-qs.log"; then
    expect_log "control: a shell that renames after the scan publishes builds the plugin its user disabled" 1 'renamed-fixture: built'
  fi
  config_renamed_restore
fi

# A bundled split must take its source's saved values before the map can
# build it. A background builds in the publication turn, so the late-map
# control exposes the transient enable even though the file is copied later.
config_plant_split() {
  cp -R -- "$repo/scripts/smoke/fixtures/plugins/vgs.fixture-split" "$sandbox/tree-$1/shell/plugins/vgs.fixture-split" || return
  python3 - "$home/.config/vgshell/shell.json" <<'PYDATA'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p))
d["disabledPlugins"] = d.get("disabledPlugins", []) + ["acme.tick"]
d["plugins"] = [r for r in d.get("plugins", []) if r["id"] != "acme.tick"] + [{"id": "acme.tick", "format": "split-saved"}]
json.dump(d, open(p + ".tmp", "w"), indent=2)
os.replace(p + ".tmp", p)
PYDATA
}
config_split_read() {
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); ids=("acme.tick", "vgs.fixture-split"); print(json.dumps([[i for i in d.get("disabledPlugins", []) if i in ids], [e["id"] for s in ("left", "center", "right") for e in d["bar"]["layout"].get(s, []) if e["id"] in ids], [r for r in d.get("plugins", []) if r["id"] == "vgs.fixture-split"]]))' "$home/.config/vgshell/shell.json"
}
config_split_runtime() {
  ipc smoke readInstance window vgs.settings plugins | py_reply 'import json,sys; row=next((r for r in json.load(sys.stdin) if r["id"] == "vgs.fixture-split"), {}); print(json.dumps([row.get("enabled"), row.get("placed"), row.get("settings", {}).get("format")]))'
}
if copy_tree configuration-split; then
  stop_shell || :
  config_plant_split configuration-split || fail "planting the split fixture and source configuration failed"
  if start_shell "$sandbox/tree-configuration-split" "$sandbox/configuration-split-qs.log"; then
    expect_log "the shell publishes the scan holding the split" 1 'plugins: scan complete changed=true'
    expect_poll "the split receives the source disable, placement and declared setting before building" '[["acme.tick", "vgs.fixture-split"], ["vgs.fixture-split", "acme.tick"], [{"id": "vgs.fixture-split", "format": "split-saved"}]]' config_split_read
    expect "Settings opens for the split runtime readback" ok ipc shell summon window vgs.settings '{}'
    expect_poll "the runtime split inherits disable, placement and setting before construction" '[false, true, "split-saved"]' config_split_runtime
    expect "the split disabled before publication never builds" 0 log_lines 'split-fixture: built'
    expect "the user can enable the split independently" ok ipc shell setPluginEnabled vgs.fixture-split true
    expect_log "the enabled split builds with the copied setting" 1 'split-fixture: built format=split-saved'
    expect "a later source disable is accepted" ok ipc shell setPluginEnabled acme.tick false
    expect "the later source disable leaves the split enabled" '[["acme.tick"], ["vgs.fixture-split", "acme.tick"], [{"id": "vgs.fixture-split", "format": "split-saved"}]]' config_split_read
    stop_shell || :
    if start_shell "$sandbox/tree-configuration-split" "$sandbox/configuration-split-restart-qs.log"; then
      expect_log "a restart keeps the independently enabled split" 1 'split-fixture: built format=split-saved'
    fi
  fi
  configuration_control_restore
fi
if copy_tree configuration-splits-late && edit_tree configuration-splits-late shell/Core/Registry.qml \
    $'        if (isChanged) renameUserFile(next);\n        if (isChanged) root.manifests = next;\n        // `scanned` gates every slot key, so it moves after the map.\n        root.scanned = true;\n' \
    $'        if (isChanged) root.manifests = next;\n        // `scanned` gates every slot key, so it moves after the map.\n        root.scanned = true;\n        if (isChanged) renameUserFile(next);\n'; then
  stop_shell || :
  config_plant_split configuration-splits-late || fail "control: planting the split fixture failed"
  if start_shell "$sandbox/tree-configuration-splits-late" "$sandbox/configuration-splits-late-qs.log"; then
    expect_log "control: splitting after publication builds the disabled source's target" 1 'split-fixture: built format='
  fi
  configuration_control_restore
fi

# Read the saved undeclared field from runtime settings in a disposable
# tree; ordinary manager and configure writes must discard its saved key.
configuration_bar_settings_reader() {
  local name="$1"
  copy_tree "$name" && edit_tree "$name" shell/plugins/vgs.bar/Bar.qml \
    'property var shell: null' 'property var shell: null; readonly property bool retiredDelivered: shell !== null && Object.prototype.hasOwnProperty.call(shell.settings, "left")'
}
configuration_saved_left() {
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(any("left" in e for e in d.get("plugins", []) if e["id"]=="vgs.bar"))' "$home/.config/vgshell/shell.json"
}
configuration_saved_declared() {
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); e=next(e for e in d["plugins"] if e["id"]=="vgs.bar"); print(json.dumps([e["clockFormat"],e["keys"]],sort_keys=True))' "$home/.config/vgshell/shell.json"
}
configuration_plant_left() {
  python3 - "$home/.config/vgshell/shell.json" <<'PYDATA'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p))
d["plugins"] = [e for e in d.get("plugins", []) if e["id"] != "vgs.bar"] + [{"id":"vgs.bar", "left":["workspaces"], "clockFormat":"HH:mm", "keys":{"toggle":"SUPER+SHIFT+SPACE"}}]
json.dump(d, open(p + ".tmp", "w"), indent=2)
os.replace(p + ".tmp", p)
PYDATA
}
configuration_runtime_left() {
  local key
  key="$(bar_key)" || return
  ipc smoke readInstance "$key" vgs.bar retiredDelivered
}
if configuration_bar_settings_reader configuration-retired-setting; then
  stop_shell || :
  configuration_plant_left
  cp -- "$home/.config/vgshell/shell.json" "$sandbox/configuration-retired-saved.json"
  if start_shell "$sandbox/tree-configuration-retired-setting" "$sandbox/configuration-retired-setting-qs.log"; then
    expect_poll "the retired bar field never enters runtime settings" false configuration_runtime_left
    expect "loading the saved field makes no cleanup write" True configuration_saved_left
    expect "loading the saved field keeps the owner's file unchanged" same bash -c 'cmp -s -- "$1" "$2" && echo same' _ "$sandbox/configuration-retired-saved.json" "$home/.config/vgshell/shell.json"
    expect "Settings opens for an ordinary setting write" ok ipc shell summon window vgs.settings '{}'
    expect "the ordinary Settings write accepts a declared bar field" ok ipc smoke invokeInstance window vgs.settings applySetting '{"id":"vgs.bar","key":"clockFormat","value":"HH:mm"}'
    expect "the ordinary Settings write removes the saved retired field" False configuration_saved_left
    expect "the ordinary Settings write keeps the declared value and shortcuts" '["HH:mm", {"toggle": "SUPER+SHIFT+SPACE"}]' configuration_saved_declared
    stop_shell || :
    configuration_plant_left
    if start_shell "$sandbox/tree-configuration-retired-setting" "$sandbox/configuration-retired-configure-qs.log"; then
      expect_poll "the configure write starts with no retired runtime setting" false configuration_runtime_left
      expect "the bar service accepts an ordinary configure write" ok ipc vgs.bar invoke toggle ''
      expect "the ordinary configure write removes the saved retired field" False configuration_saved_left
      expect "the ordinary configure write keeps the declared value and shortcuts" '["HH:mm", {"toggle": "SUPER+SHIFT+SPACE"}]' configuration_saved_declared
      expect "the bar service restores its visibility" ok ipc vgs.bar invoke toggle ''
    fi
  fi
  configuration_control_restore
fi

if configuration_bar_settings_reader configuration-copy-all-settings && edit_tree configuration-copy-all-settings shell/Core/PluginLogic.js \
    'if (hasOwn(manifest.settings, k) || (stored && ENTRY_RESERVED_KEYS.indexOf(k) !== -1))' \
    'if (stored || ENTRY_RESERVED_KEYS.indexOf(k) === -1)'; then
  stop_shell || :
  configuration_plant_left
  if start_shell "$sandbox/tree-configuration-copy-all-settings" "$sandbox/configuration-copy-all-settings-qs.log"; then
    expect_poll "control: copy-everything delivers the retired runtime field" true configuration_runtime_left
    expect "control: Settings opens for the same ordinary setting write" ok ipc shell summon window vgs.settings '{}'
    expect "control: the ordinary Settings write accepts a declared bar field" ok ipc smoke invokeInstance window vgs.settings applySetting '{"id":"vgs.bar","key":"clockFormat","value":"HH:mm"}'
    expect "control: copy-everything leaves the retired field after the Settings write" True configuration_saved_left
    expect "control: the Settings write keeps the declared value and shortcuts" '["HH:mm", {"toggle": "SUPER+SHIFT+SPACE"}]' configuration_saved_declared
    stop_shell || :
    configuration_plant_left
    if start_shell "$sandbox/tree-configuration-copy-all-settings" "$sandbox/configuration-copy-all-configure-qs.log"; then
      expect_poll "control: the configure write starts with the retired runtime field" true configuration_runtime_left
      expect "control: the bar service makes the same ordinary setting write" ok ipc vgs.bar invoke toggle ''
      expect "control: copy-everything leaves the retired field after the configure write" True configuration_saved_left
      expect "control: the configure write keeps the declared value and shortcuts" '["HH:mm", {"toggle": "SUPER+SHIFT+SPACE"}]' configuration_saved_declared
      expect "control: the bar service restores its visibility" ok ipc vgs.bar invoke toggle ''
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
