#!/usr/bin/env bash
# Controls for `vgshell plugin settings <id>`: the settings one plugin hands its
# service, panel and floating TUIs, read offline from the shipped and user
# shell.json through bin/vgshell-plugin-judge. Every row runs a copy of the
# tree whose bundled plugin directory is empty, against a fixture plugin in
# the row's own user plugin directory, so no shipped plugin's defaults and
# no developer configuration reach a row. Each control runs the rows
# against a copy of the tree whose judge drops one rule, and a row must
# fail.
set -euo pipefail

# shellcheck source=scripts/vgshell-rows.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"

tree="$tmp/tree"
mkdir -p "$tree/shell/Core" "$tree/shell/Commons" "$tree/shell/Ui/icons" "$tree/shell/plugins" "$tree/config"
cp -R -- "$repo/bin" "$tree/"
cp -- "$repo/shell/Core/PluginLogic.js" "$repo/shell/Core/ConfigLogic.js" "$repo/shell/Core/PackageManagers.js" "$repo/shell/Core/PackageReview.js" "$repo/shell/Core/HyprlandLayer.js" "$repo/shell/Core/MonitorLogic.js" "$repo/shell/Core/Pads.js" "$tree/shell/Core/"
cp -- "$repo/shell/Commons/SettingValues.js" "$repo/shell/Commons/PageReference.js" "$tree/shell/Commons/"
cp -- "$repo/shell/Ui/icons/Lucide.js" "$repo/shell/Ui/icons/Own.js" "$tree/shell/Ui/icons/"
printf '{ "version": 3, "plugins": [], "disabledPlugins": [] }\n' >"$tree/config/shell.json"

cfg="$tmp/cfg"
probe="$cfg/vgshell/plugins/acme.probe"
mkdir -p "$probe"
manifest acme.probe 0.1.0 ', "settings": { "mode": "fast", "count": 2, "trust": false },
  "schema": { "mode": { "type": "enum", "label": "Mode", "options": [{ "value": "fast", "label": "Fast" }, { "value": "slow", "label": "Slow" }] }, "count": { "type": "number", "label": "Count", "min": 1, "max": 9 }, "trust": { "type": "boolean", "label": "Trust" } }' >"$probe/manifest.json"
printf 'import QtQuick\nItem { property var shell: null }\n' >"$probe/Service.qml"
user_file() { printf '%s\n' "$1" >"$cfg/vgshell/shell.json"; } # JSON

# settings_of BIN ID...: `BIN plugin settings ID...` against $cfg; stdout
# in $out, the first stderr line in $err, the exit status in $status.
settings_of() {
  local bin="$1"
  shift
  status=0
  out="$("${base_env[@]}" XDG_CONFIG_HOME="$cfg" "$bin" plugin settings "$@" 2>"$tmp/err" </dev/null)" || status=$?
  err=""
  [[ -s $tmp/err ]] && IFS= read -r err <"$tmp/err"
  return 0
}

# Rows: name | user shell.json, `-` for none | id | exit | stdout | first stderr line
rows=(
  "the manifest's defaults with no user file|-|acme.probe|0|{\"mode\":\"fast\",\"count\":2,\"trust\":false}|"
  "the user's plugins row over the defaults|{ \"plugins\": [{ \"id\": \"acme.probe\", \"count\": 5, \"trust\": true }] }|acme.probe|0|{\"mode\":\"fast\",\"count\":5,\"trust\":true}|"
  "a version 1 file's layout entry setting, read as migrated into the row|{ \"version\": 1, \"bar\": { \"layout\": { \"right\": [{ \"id\": \"acme.probe\", \"count\": 7 }] } }, \"plugins\": [{ \"id\": \"acme.probe\", \"trust\": true }] }|acme.probe|0|{\"mode\":\"fast\",\"count\":7,\"trust\":true}|"
  "a value the schema refuses|{ \"plugins\": [{ \"id\": \"acme.probe\", \"trust\": \"yes\" }] }|acme.probe|1||vgshell: refused: setting=trust want=boolean id=acme.probe"
  "a number past the schema's bound|{ \"plugins\": [{ \"id\": \"acme.probe\", \"count\": 12 }] }|acme.probe|1||vgshell: refused: setting=count want=at-most:9 id=acme.probe"
  "an id no plugin has|-|acme.none|1||vgshell: refused: unknown=acme.none"
  "no id|-||2||vgshell: refused: id=missing"
)
# settings_rows BIN QUIET: every row through BIN; prints ok and FAIL lines
# unless QUIET is `quiet`; returns the number of failing rows.
settings_rows() {
  local row name file id want_exit want_out want_err args red=0
  for row in "${rows[@]}"; do
    IFS='|' read -r name file id want_exit want_out want_err <<<"$row"
    if [[ $file == - ]]; then rm -f -- "$cfg/vgshell/shell.json"; else user_file "$file"; fi
    args=()
    [[ -z $id ]] || args=("$id")
    settings_of "$1" "${args[@]}"
    if [[ $status == "$want_exit" && $out == "$want_out" && $err == "$want_err" ]]; then
      [[ $2 == quiet ]] || ok "$name"
    else
      red=$((red + 1))
      [[ $2 == quiet ]] || fail "$name: exit=$status want=$want_exit out=[$out] want=[$want_out] err=[$err] want=[$want_err]"
    fi
  done
  return "$red"
}
settings_rows "$tree/bin/vgshell" loud || true

user_file '{ "plugins": 3 }'
settings_of "$tree/bin/vgshell" acme.probe
check "a user file the config judge refuses is refused" test "$status:${err%% error=*}" == "1:vgshell: refused: user-config=malformed path=$cfg/vgshell/shell.json"
settings_of "$tree/bin/vgshell" acme.probe extra
check "a second argument is refused" test "$status:$err" == "2:vgshell: refused: argument=extra"
# A read migrates in memory alone: the shell, the file's owner, writes the
# migrated file.
version_one='{ "version": 1, "bar": { "layout": { "right": [{ "id": "acme.probe", "count": 7 }] } } }'
user_file "$version_one"
settings_of "$tree/bin/vgshell" acme.probe
check "a read leaves a version 1 user file as it was" test "$status:$(cat -- "$cfg/vgshell/shell.json")" == "0:$version_one"

# Controls: a judge copy that reads no user file, one that hands a value
# the schema refuses through, and a reader that judges a version 1 user
# file unmigrated.
control() { # NAME FILE NEEDLE REPLACEMENT
  local copy_tree="$tmp/tree-$1"
  cp -R -- "$tree" "$copy_tree"
  copy_with "$1" "$tree/$2" "$3" "$4"
  cp -- "$copy" "$copy_tree/$2"
  check "the $1 mutant fails a row" test "$(settings_rows "$copy_tree/bin/vgshell" quiet && echo green || echo red)" == red
}
control ignores-user bin/vgshell-plugin-judge 'settingsFor(configLogic.effectiveConfig(shipped, user)' 'settingsFor(configLogic.effectiveConfig(shipped, null)'
control skips-schema bin/vgshell-plugin-judge 'if (refusal !== "") refuse(refusal.slice(' 'if (false) refuse(refusal.slice('
control unmigrated bin/lib/judge-files.js 'const moved = logic.migrateConfig(config, packageReviewSettingsSource);' 'const moved = { config: config, migrated: false };'

rows_done test-vgshell-plugin-settings
