#!/usr/bin/env bash
# The VS Code-family target, vscode, through `vgshell theme apply`: for each
# editor whose command is on PATH it copies one generated extension,
# publisher `local`, into that editor's extensions directory under a version
# made from the colour theme's sha256, registers that version in the
# directory's extensions.json, unmarks it in `.obsolete`, removes every
# other version, and sets workbench.colorTheme in the editor's settings
# file, created when absent. Every command is a stub on the rows' PATH under
# a temporary HOME and XDG_CONFIG_HOME, so no row starts an editor. The
# controls at the end apply a tree copy that lacks one rule and require the
# row's assertion to turn.
set -euo pipefail

source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"
theme_tree vscode
home="$tmp/home"; id="local.vgs-theme"

# Detection never runs a command: each editor's command records a run and
# exits 1. $codium holds codium alone.
for stub in code code-insiders codium cursor; do
  printf '#!/bin/sh\n: >"%s/ran-$(basename "$0")"\nexit 1\n' "$tmp" >"$stubs/$stub"
  chmod +x "$stubs/$stub"
done
codium="$tmp/stubs-codium"; mkdir -p "$codium"; ln -s -- "$stubs/codium" "$codium/codium"
with_codium="$codium:$theme_path"; with_all="$stubs:$theme_path"

# `dusk` and `nord` differ only in their accent, which the colour theme
# writes, so each makes its own version.
theme_pkg "$tree/themes/dusk" '{ "schemaVersion": 1, "name": "dusk", "tokens": { "palette": { "accent": "#111111" } } }'
theme_pkg "$tree/themes/nord" '{ "schemaVersion": 1, "name": "nord", "tokens": { "palette": { "accent": "#222222" } } }'

result() { # STATE[:REASON] THEME
  local s="$1"
  if [[ $s == *:* ]]; then s="\"state\":\"${s%%:*}\",\"reason\":\"${s#*:}\""; else s="\"state\":\"$s\",\"reason\":null"; fi
  printf '{"state":"applied","shell":"applied","targets":[{"name":"vscode",%s,"dropped":[]}],"theme":"%s","reason":null}' "$s" "$2"
}
fresh() { # NAME: a new configuration home, and a home holding no editor directory
  cfg="$tmp/cfg-$1"; mkdir -p "$cfg/vgshell"
  rm -rf -- "${home:?}/.vscode" "${home:?}/.vscode-insiders" "${home:?}/.vscode-oss" "${home:?}/.cursor"
}
# The one folder of the extension in EXTENSIONS_DIR.
folder_of() { # EXTENSIONS_DIR
  local found=("$1/$id"-*)
  [[ ${#found[@]} == 1 && -d ${found[0]} ]] || return 1
  printf '%s' "${found[0]}"
}
# The extension in EXTENSIONS_DIR is one folder of two regular files whose
# manifest names publisher local, its id's name and the version made from
# its colour theme: `1.0.` and the theme's first 32 sha256 bits in decimal.
extension_is_current() { # EXTENSIONS_DIR
  local folder
  folder="$(folder_of "$1")" || return 1
  [[ -f $folder/package.json && ! -L $folder/package.json && -f $folder/vgs-color-theme.json && ! -L $folder/vgs-color-theme.json ]] || return 1
  python3 - "$folder" "$id" 2>/dev/null <<'PY'
import hashlib, json, os, sys
folder, ident = sys.argv[1], sys.argv[2]
theme = open(os.path.join(folder, "vgs-color-theme.json"), "rb").read()
version = "1.0." + str(int(hashlib.sha256(theme).hexdigest()[:8], 16))
manifest = json.load(open(os.path.join(folder, "package.json")))
assert sorted(os.listdir(folder)) == ["package.json", "vgs-color-theme.json"]
assert manifest["publisher"] + "." + manifest["name"] == ident
assert manifest["version"] == version
assert os.path.basename(folder) == ident + "-" + version
assert manifest["contributes"]["themes"][0]["label"] == "vgs"
PY
}
# extensions.json in EXTENSIONS_DIR registers the one folder of the
# extension, by id, version and location, and with OTHER_ID keeps exactly
# that other entry.
registered() { # EXTENSIONS_DIR [OTHER_ID]
  local folder
  folder="$(folder_of "$1")" || return 1
  python3 - "$1" "$folder" "$id" "${2:-}" 2>/dev/null <<'PY'
import json, os, sys
directory, folder, ident, other = sys.argv[1:5]
entries = json.load(open(os.path.join(directory, "extensions.json")))
own = [e for e in entries if e["identifier"]["id"] == ident]
assert len(own) == 1, own
version = json.load(open(os.path.join(folder, "package.json")))["version"]
assert own[0]["version"] == version
assert own[0]["relativeLocation"] == os.path.basename(folder)
assert own[0]["location"] == {"$mid": 1, "path": folder, "scheme": "file"}
assert own[0]["metadata"]["source"] == "vsix"
if other:
    assert [e["identifier"]["id"] for e in entries if e["identifier"]["id"] != ident] == [other]
PY
}
unregistered() { # EXTENSIONS_DIR
  python3 -c 'import json,sys; assert all(e["identifier"]["id"] != sys.argv[2] for e in json.load(open(sys.argv[1] + "/extensions.json")))' "$1" "$id" 2>/dev/null
}
obsolete_is() { # EXTENSIONS_DIR JSON: .obsolete holds exactly JSON
  python3 -c 'import json,sys; assert json.load(open(sys.argv[1] + "/.obsolete")) == json.loads(sys.argv[2])' "$1" "$2" 2>/dev/null
}
selects_vgs() { # SETTINGS_FILE
  python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["workbench.colorTheme"] == "vgs"' "$1" 2>/dev/null
}
file_is() { cmp -s -- "$1" <(printf '%s' "$2"); } # FILE TEXT
oss="$home/.vscode-oss/extensions"

fresh none
tinst "an apply with no editor on PATH skips vscode" "$cfg" "$rt_empty" 0 "$(result skipped:not-detected dusk)" "" theme apply --json dusk
check "an undetected editor gets no directory" test ! -e "$home/.vscode" -a ! -e "$home/.vscode-oss" -a ! -e "$home/.cursor" -a ! -e "$cfg/VSCodium"

# Only codium: VSCodium's directories alone, its registry already holding
# another extension and marking an old version of this one obsolete, and
# no settings file yet.
fresh codium
mkdir -p "$oss/$id-1.0.5"
printf '[{"identifier":{"id":"pub.other"},"version":"2.0.0","relativeLocation":"pub.other-2.0.0"}]' >"$oss/extensions.json"
printf '{"%s-1.0.5":true,"pub.gone-1.0.0":true}' "$id" >"$oss/.obsolete"
THEME_PATH="$with_codium" tinst "codium alone lands vscode" "$cfg" "$rt_empty" 0 "$(result written nord)" "" theme apply --json nord
check "VSCodium holds the generated extension at its version" extension_is_current "$oss"
check "VSCodium's extensions.json registers it beside the other extension" registered "$oss" pub.other
check "VSCodium's .obsolete no longer marks the extension" obsolete_is "$oss" '{"pub.gone-1.0.0":true}'
check "VSCodium's settings file is created selecting vgs" file_is "$cfg/VSCodium/User/settings.json" $'{\n  "workbench.colorTheme": "vgs"\n}\n'
check "no other editor gets a directory" test ! -e "$home/.vscode" -a ! -e "$home/.vscode-insiders" -a ! -e "$home/.cursor" -a ! -e "$cfg/Code" -a ! -e "$cfg/Cursor"
nord_folder="$(folder_of "$oss")"

# A new palette is a new version: the old folder goes and the registry
# names the new one. The same palette again changes nothing.
THEME_PATH="$with_codium" tinst "a new palette lands a new version" "$cfg" "$rt_empty" 0 "$(result written dusk)" "" theme apply --json dusk
check "VSCodium holds the new version alone" extension_is_current "$oss"
check "the new version is another folder" test "$(folder_of "$oss")" != "$nord_folder" -a ! -e "$nord_folder"
check "VSCodium's extensions.json registers the new version" registered "$oss" pub.other
cp -- "$oss/extensions.json" "$tmp/registry-before"
THEME_PATH="$with_codium" tinst "the same palette again" "$cfg" "$rt_empty" 0 "ok theme=dusk state=unchanged shell=unchanged" "" theme apply dusk
check "an unchanged apply keeps extensions.json byte for byte" cmp -s -- "$tmp/registry-before" "$oss/extensions.json"

# Every editor: each its own directories, the Insiders settings directory
# holding spaces. A settings file with comments and a trailing comma keeps
# every byte but its theme.
fresh all
mkdir -p "$cfg/Code/User"
printf '{\n    // mine\n    "workbench.colorTheme": "Default Dark Modern", /* was */\n    "editor.fontSize": 14,\n}\n' >"$cfg/Code/User/settings.json"
THEME_PATH="$with_all" tinst "every editor lands vscode" "$cfg" "$rt_empty" 0 "$(result written nord)" "" theme apply --json nord
for pair in ".vscode/extensions|Code/User" ".vscode-insiders/extensions|Code - Insiders/User" ".vscode-oss/extensions|VSCodium/User" ".cursor/extensions|Cursor/User"; do
  check "${pair%%|*} holds the current extension" extension_is_current "$home/${pair%%|*}"
  check "${pair%%|*} registers it" registered "$home/${pair%%|*}"
  [[ $pair == *"|Code/User" ]] || check "${pair#*|} selects vgs" selects_vgs "$cfg/${pair#*|}/settings.json"
done
check "VS Code's commented settings keep every other byte" file_is "$cfg/Code/User/settings.json" $'{\n    // mine\n    "workbench.colorTheme": "vgs", /* was */\n    "editor.fontSize": 14,\n}\n'
check "detection ran no editor" test ! -e "$tmp/ran-code" -a ! -e "$tmp/ran-code-insiders" -a ! -e "$tmp/ran-codium" -a ! -e "$tmp/ran-cursor"

# A registry the editor cannot have written skips the target before
# anything lands in any editor.
fresh refused
mkdir -p "$oss"; printf '{}' >"$oss/extensions.json"
THEME_PATH="$with_all" tinst "an extensions.json that is no array skips vscode" "$cfg" "$rt_empty" 0 "$(result skipped:registry-refused dusk)" "" theme apply --json dusk
check "a refused registry lands no extension anywhere" test ! -e "$home/.vscode" -a ! -e "$home/.cursor" -a "$(cat -- "$oss/extensions.json")" == '{}'

# A disabled vscode loses its folders and registrations; the settings stay.
fresh disabled
# The state directory is shared, so nord's files are already in place.
THEME_PATH="$with_codium" tinst "codium lands before the disable" "$cfg" "$rt_empty" 0 "$(result unchanged nord)" "" theme apply --json nord
printf '{ "disabledTargets": ["vscode"] }\n' >"$cfg/vgshell/shell.json"
THEME_PATH="$with_codium" tinst "a disabled vscode" "$cfg" "$rt_empty" 0 "$(result skipped:disabled dusk)" "" theme apply --json dusk
check "a disabled vscode leaves no extension folder" test -z "$(find "$oss" -mindepth 1 -maxdepth 1 -name "$id-*" -print)"
check "a disabled vscode is unregistered" unregistered "$oss"

# Controls: each mutant drops one rule, and the assertion that pins it
# must turn. The rows above use the same assertions.
turned() { test "$("$@"; echo $?)" == 1; } # CMD...: the assertion fails
tree_control fixed-version themes/targets/vscode/package.json '"version": "@{extension.version}"' '"version": "1.0.0"'
fresh fixed-version
THEME_PATH="$with_codium" tinst "the fixed-version mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply nord
check "the fixed-version mutant's manifest misses the theme's version" turned extension_is_current "$oss"
judge_control no-registry "utf8Edit(text => render.registeredText(logic, text, id, version, editor.extensions)));" 'utf8Edit(text => null));'
fresh no-registry
THEME_PATH="$with_codium" tinst "the no-registry mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply nord
check "the no-registry mutant's extension is in place" extension_is_current "$oss"
check "the no-registry mutant registers nothing" turned registered "$oss"
judge_control keeps-obsolete "editFile(key, path.join(editor.extensions, OBSOLETE_FILE), false, utf8Edit(text => render.unobsoletedText(logic, text, id))) ||" 'null ||'
fresh keeps-obsolete
mkdir -p "$oss"; printf '{"%s-1.0.5":true,"pub.gone-1.0.0":true}' "$id" >"$oss/.obsolete"
THEME_PATH="$with_codium" tinst "the keeps-obsolete mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply nord
check "the keeps-obsolete mutant leaves the extension marked" turned obsolete_is "$oss" '{"pub.gone-1.0.0":true}'
judge_control keeps-versions 'for (const old of otherVersions(editor.extensions, id, folder)) writing(' 'for (const old of []) writing('
fresh keeps-versions
THEME_PATH="$with_codium" tinst "the keeps-versions mutant applies nord" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply nord
THEME_PATH="$with_codium" tinst "the keeps-versions mutant applies dusk" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply dusk
check "the keeps-versions mutant keeps two folders" turned extension_is_current "$oss"
judge_control no-settings-create 'select.selectedText(selection.format, text === undefined && create ? "{}\n" : text,' 'select.selectedText(selection.format, text,'
fresh no-settings-create
THEME_PATH="$with_codium" tinst "the no-create mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply nord
check "the no-create mutant writes no settings file" turned selects_vgs "$cfg/VSCodium/User/settings.json"
tree_control codium-elsewhere themes/targets/vscode/target.json '"extensions": ".vscode-oss/extensions"' '"extensions": ".vscode-codium/extensions"'
fresh codium-elsewhere
THEME_PATH="$with_codium" tinst "the misplaced-codium mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply nord
check "the misplaced-codium mutant misses VSCodium's extensions directory" turned extension_is_current "$oss"
unset THEME_BIN

rows_done test-vgshell-vscode
