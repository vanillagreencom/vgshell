#!/usr/bin/env bash
# The VS Code-family target, vscode, through `vgshell theme apply`: for each
# editor whose command is on PATH, in turn, it copies one generated
# extension, publisher `local`, into that editor's extensions directory
# under an id made from the colour theme's sha256, registers that id in the
# directory's extensions.json, unmarks it in `.obsolete`, sets
# workbench.colorTheme in the editor's settings file, created when absent,
# to the theme that extension alone contributes, and then removes every
# other extension the target made but the one whose theme the settings
# selected before, which the next apply removes. An open window adds only
# an extension whose id is new to it, applies a selection change, and falls
# back to its default theme when the theme it shows leaves its theme list.
# Every command is a stub on the rows' PATH under a temporary HOME and
# XDG_CONFIG_HOME, so no row starts an editor. The controls at the end apply
# a tree copy that lacks one rule and require the row's assertion to turn.
set -euo pipefail

source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"
theme_tree vscode
home="$tmp/home"; base="local.vgs-theme"

# Detection never runs a command: each editor's command records a run and
# exits 1. $codium holds codium alone, $code_codium VS Code and codium.
for stub in code code-insiders codium cursor; do
  printf '#!/bin/sh\n: >"%s/ran-$(basename "$0")"\nexit 1\n' "$tmp" >"$stubs/$stub"
  chmod +x "$stubs/$stub"
done
codium="$tmp/stubs-codium"; mkdir -p "$codium"; ln -s -- "$stubs/codium" "$codium/codium"
code_codium="$tmp/stubs-code-codium"; mkdir -p "$code_codium"; ln -s -- "$stubs/codium" "$code_codium/codium"; ln -s -- "$stubs/code" "$code_codium/code"
with_codium="$codium:$theme_path"; with_all="$stubs:$theme_path"; with_code_codium="$code_codium:$theme_path"

# `dusk`, `nord` and `ember` differ only in their accent, which the colour
# theme writes, so each makes its own id.
theme_pkg "$tree/themes/dusk" '{ "schemaVersion": 1, "name": "dusk", "tokens": { "palette": { "accent": "#111111" } } }'
theme_pkg "$tree/themes/nord" '{ "schemaVersion": 1, "name": "nord", "tokens": { "palette": { "accent": "#222222" } } }'
theme_pkg "$tree/themes/ember" '{ "schemaVersion": 1, "name": "ember", "tokens": { "palette": { "accent": "#333333" } } }'

result() { # STATE[:REASON] THEME
  local s="$1"
  if [[ $s == *:* ]]; then s="\"state\":\"${s%%:*}\",\"reason\":\"${s#*:}\""; else s="\"state\":\"$s\",\"reason\":null"; fi
  printf '{"state":"applied","shell":"applied","targets":[{"name":"vscode",%s,"dropped":[]}],"theme":"%s","reason":null}' "$s" "$2"
}
fresh() { # NAME: a new configuration home, and a home holding no editor directory
  cfg="$tmp/cfg-$1"; mkdir -p "$cfg/vgshell"
  rm -rf -- "${home:?}/.vscode" "${home:?}/.vscode-insiders" "${home:?}/.vscode-oss" "${home:?}/.cursor"
}
# The theme SETTINGS_FILE selects.
selected() { # SETTINGS_FILE
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["workbench.colorTheme"])' "$1" 2>/dev/null
}
# The id of the generated extension whose theme SETTINGS_FILE selects.
current_id() { # SETTINGS_FILE
  local value
  value="$(selected "$1")" && [[ $value == vgs-* ]] && printf '%s-%s' "$base" "${value#vgs-}"
}
# The theme SETTINGS_FILE selects is the one theme, labelled vgs, of a
# registered extension in EXTENSIONS_DIR: one folder of two regular files
# whose manifest names publisher local and `vgs-theme-` and the stamp made
# from its colour theme, the theme's first 32 sha256 bits in decimal, and
# whose theme id is `vgs-` and that stamp.
extension_is_current() { # EXTENSIONS_DIR SETTINGS_FILE
  python3 - "$1" "$2" "$base" 2>/dev/null <<'PY'
import hashlib, json, os, sys
directory, settings, base = sys.argv[1:4]
value = json.load(open(settings))["workbench.colorTheme"]
assert value.startswith("vgs-")
ident = base + "-" + value[4:]
own = [e for e in json.load(open(os.path.join(directory, "extensions.json"))) if e["identifier"]["id"] == ident]
assert len(own) == 1, own
folder = os.path.join(directory, own[0]["relativeLocation"])
assert own[0]["location"] == {"$mid": 1, "path": folder, "scheme": "file"}
assert own[0]["metadata"]["source"] == "vsix"
assert sorted(os.listdir(folder)) == ["package.json", "vgs-color-theme.json"]
assert not any(os.path.islink(os.path.join(folder, name)) for name in os.listdir(folder))
theme = open(os.path.join(folder, "vgs-color-theme.json"), "rb").read()
assert value == "vgs-" + str(int(hashlib.sha256(theme).hexdigest()[:8], 16))
manifest = json.load(open(os.path.join(folder, "package.json")))
assert manifest["publisher"] + "." + manifest["name"] == ident
assert os.path.basename(folder) == ident + "-" + manifest["version"] and own[0]["version"] == manifest["version"]
assert [(t["id"], t["label"]) for t in manifest["contributes"]["themes"]] == [(value, "vgs")]
PY
}
# The extensions the target made in EXTENSIONS_DIR, by registration and by
# folder, are exactly the IDs, and with OTHERS_ARE its other registrations
# are exactly that space-separated list.
ids_are() { # EXTENSIONS_DIR [OTHERS_ARE=ID...] ID...
  local dir="$1"; shift
  python3 - "$dir" "$base" "$@" 2>/dev/null <<'PY'
import json, os, re, sys
directory, base, args = sys.argv[1], sys.argv[2], sys.argv[3:]
others = [a for a in args if a.startswith("OTHERS_ARE=")]
want = sorted(a for a in args if not a.startswith("OTHERS_ARE="))
mine = lambda i: i == base or re.fullmatch(re.escape(base) + r"-[0-9]+", i) is not None
ids = [e["identifier"]["id"] for e in json.load(open(os.path.join(directory, "extensions.json")))]
folders = [m.group(1) for m in (re.fullmatch(r"(.+)-[0-9]+\.[0-9]+\.[0-9]+", n) for n in os.listdir(directory)) if m and mine(m.group(1))]
assert sorted(i for i in ids if mine(i)) == want and sorted(folders) == want, (ids, folders, want)
if others:
    assert [i for i in ids if not mine(i)] == others[0].split("=", 1)[1].split(), ids
PY
}
obsolete_is() { # EXTENSIONS_DIR JSON: .obsolete holds exactly JSON
  python3 -c 'import json,sys; assert json.load(open(sys.argv[1] + "/.obsolete")) == json.loads(sys.argv[2])' "$1" "$2" 2>/dev/null
}
file_is() { cmp -s -- "$1" <(printf '%s' "$2"); } # FILE TEXT
# The extension of an earlier release in EXTENSIONS_DIR: the one id, no
# stamp, whose theme is selected as `vgs`, registered and in its folder.
plant_unstamped() { # EXTENSIONS_DIR
  mkdir -p "$1/$base-1.0.5"
  printf '{"name":"vgs-theme","publisher":"local","version":"1.0.5","contributes":{"themes":[{"label":"vgs","uiTheme":"vs-dark","path":"./vgs-color-theme.json"}]}}' >"$1/$base-1.0.5/package.json"
  printf '{}' >"$1/$base-1.0.5/vgs-color-theme.json"
  python3 -c 'import json,os,sys; p=sys.argv[1]+"/extensions.json"; e=json.load(open(p)) if os.path.exists(p) else []; e.append({"identifier":{"id":sys.argv[2]},"version":"1.0.5","relativeLocation":sys.argv[2]+"-1.0.5"}); json.dump(e,open(p,"w"))' "$1" "$base"
}
oss="$home/.vscode-oss/extensions"

fresh none
tinst "an apply with no editor on PATH skips vscode" "$cfg" "$rt_empty" 0 "$(result skipped:not-detected dusk)" "" theme apply --json dusk
check "an undetected editor gets no directory" test ! -e "$home/.vscode" -a ! -e "$home/.vscode-oss" -a ! -e "$home/.cursor" -a ! -e "$cfg/VSCodium"

# Only codium: VSCodium's directories alone, its registry holding another
# extension and the unstamped extension of an earlier release, which it
# also marks obsolete, and no settings file yet, so no window shows that
# extension's theme.
fresh codium; settings="$cfg/VSCodium/User/settings.json"
mkdir -p "$oss"
printf '[{"identifier":{"id":"pub.other"},"version":"2.0.0","relativeLocation":"pub.other-2.0.0"}]' >"$oss/extensions.json"
plant_unstamped "$oss"
printf '{"%s-1.0.5":true,"pub.gone-1.0.0":true}' "$base" >"$oss/.obsolete"
THEME_PATH="$with_codium" tinst "codium alone lands vscode" "$cfg" "$rt_empty" 0 "$(result written nord)" "" theme apply --json nord
check "VSCodium's settings select the generated extension's theme" extension_is_current "$oss" "$settings"
nord_id="$(current_id "$settings")" || nord_id=""
check "VSCodium's settings file is created holding the selection alone" file_is "$settings" $'{\n  "workbench.colorTheme": "vgs-'"${nord_id#"$base"-}"$'"\n}\n'
check "VSCodium holds that extension alone beside the other one, the unselected earlier release gone" ids_are "$oss" OTHERS_ARE=pub.other "$nord_id"
check "VSCodium's .obsolete no longer marks the extension" obsolete_is "$oss" '{"pub.gone-1.0.0":true}'
check "no other editor gets a directory" test ! -e "$home/.vscode" -a ! -e "$home/.vscode-insiders" -a ! -e "$home/.cursor" -a ! -e "$cfg/Code" -a ! -e "$cfg/Cursor"

# A new palette is a new id and a new selection, which an open window
# applies. The theme the window showed stays registered, so it never falls
# back to its default; the next new palette removes it.
THEME_PATH="$with_codium" tinst "a new palette lands a new id" "$cfg" "$rt_empty" 0 "$(result written dusk)" "" theme apply --json dusk
check "VSCodium's settings select the new extension's theme" extension_is_current "$oss" "$settings"
dusk_id="$(current_id "$settings")" || dusk_id=""
check "an open window reads another theme and another extension id" test -n "$dusk_id" -a "$dusk_id" != "$nord_id"
check "the theme the window showed stays registered" ids_are "$oss" OTHERS_ARE=pub.other "$nord_id" "$dusk_id"
THEME_PATH="$with_codium" tinst "a third palette lands a third id" "$cfg" "$rt_empty" 0 "$(result written ember)" "" theme apply --json ember
check "VSCodium's settings select the third extension's theme" extension_is_current "$oss" "$settings"
ember_id="$(current_id "$settings")" || ember_id=""
check "the third apply removes the first id" ids_are "$oss" OTHERS_ARE=pub.other "$dusk_id" "$ember_id"
# A palette whose extension is still registered only moves the selection.
cp -- "$oss/extensions.json" "$tmp/registry-before"
THEME_PATH="$with_codium" tinst "the previous palette again" "$cfg" "$rt_empty" 0 "$(result written dusk)" "" theme apply --json dusk
check "a registered palette moves the selection" test "$(current_id "$settings")" == "$dusk_id"
check "a registered palette keeps extensions.json byte for byte" cmp -s -- "$tmp/registry-before" "$oss/extensions.json"
THEME_PATH="$with_codium" tinst "the same palette again" "$cfg" "$rt_empty" 0 "ok theme=dusk state=unchanged shell=unchanged" "" theme apply dusk
check "the same palette again removes the theme no window shows" ids_are "$oss" OTHERS_ARE=pub.other "$dusk_id"
cp -- "$oss/extensions.json" "$tmp/registry-before"
THEME_PATH="$with_codium" tinst "the same palette a third time" "$cfg" "$rt_empty" 0 "ok theme=dusk state=unchanged shell=unchanged" "" theme apply dusk
check "an unchanged apply keeps extensions.json byte for byte" cmp -s -- "$tmp/registry-before" "$oss/extensions.json"

# An install of an earlier release: its one extension's theme is selected
# as `vgs`, so an open window shows it. The first apply keeps it, the next
# removes it.
fresh unstamped; settings="$cfg/VSCodium/User/settings.json"
plant_unstamped "$oss"
mkdir -p "$cfg/VSCodium/User"; printf '{\n  "workbench.colorTheme": "vgs"\n}\n' >"$settings"
THEME_PATH="$with_codium" tinst "the first apply over an earlier release" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply --json nord
check "the first apply over an earlier release selects its own theme" extension_is_current "$oss" "$settings"
check "the first apply keeps the earlier release's extension a window shows" ids_are "$oss" "$base" "$nord_id"
THEME_PATH="$with_codium" tinst "the second apply over an earlier release" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply --json dusk
check "the second apply removes the earlier release's extension" ids_are "$oss" "$nord_id" "$dusk_id"

# Every editor: each its own directories, the Insiders settings directory
# holding spaces. A settings file with comments and a trailing comma keeps
# every byte but its theme.
fresh all
mkdir -p "$cfg/Code/User"
printf '{\n    // mine\n    "workbench.colorTheme": "Default Dark Modern", /* was */\n    "editor.fontSize": 14,\n}\n' >"$cfg/Code/User/settings.json"
THEME_PATH="$with_all" tinst "every editor lands vscode" "$cfg" "$rt_empty" 0 "$(result written nord)" "" theme apply --json nord
for pair in ".vscode/extensions|Code/User" ".vscode-insiders/extensions|Code - Insiders/User" ".vscode-oss/extensions|VSCodium/User" ".cursor/extensions|Cursor/User"; do
  # VS Code's settings hold comments, which the byte check below reads.
  [[ $pair == *"|Code/User" ]] || check "${pair#*|} selects the theme of the extension in ${pair%%|*}" extension_is_current "$home/${pair%%|*}" "$cfg/${pair#*|}/settings.json"
  check "${pair%%|*} holds that extension alone" ids_are "$home/${pair%%|*}" "$nord_id"
done
check "VS Code's commented settings keep every other byte" file_is "$cfg/Code/User/settings.json" $'{\n    // mine\n    "workbench.colorTheme": "vgs-'"${nord_id#"$base"-}"$'", /* was */\n    "editor.fontSize": 14,\n}\n'
check "detection ran no editor" test ! -e "$tmp/ran-code" -a ! -e "$tmp/ran-code-insiders" -a ! -e "$tmp/ran-codium" -a ! -e "$tmp/ran-cursor"

# A registry the editor cannot have written skips the target before
# anything lands in any editor.
fresh refused
mkdir -p "$oss"; printf '{}' >"$oss/extensions.json"
THEME_PATH="$with_all" tinst "an extensions.json that is no array skips vscode" "$cfg" "$rt_empty" 0 "$(result skipped:registry-refused dusk)" "" theme apply --json dusk
check "a refused registry lands no extension anywhere" test ! -e "$home/.vscode" -a ! -e "$home/.cursor" -a "$(cat -- "$oss/extensions.json")" == '{}'

# A disabled vscode loses its folders and registrations, the unstamped
# extension of an earlier release's included; the settings stay.
fresh disabled
# The state directory is shared, so nord's files are already in place.
THEME_PATH="$with_codium" tinst "codium lands before the disable" "$cfg" "$rt_empty" 0 "$(result unchanged nord)" "" theme apply --json nord
plant_unstamped "$oss"
printf '{ "disabledTargets": ["vscode"] }\n' >"$cfg/vgshell/shell.json"
THEME_PATH="$with_codium" tinst "a disabled vscode" "$cfg" "$rt_empty" 0 "$(result skipped:disabled dusk)" "" theme apply --json dusk
check "a disabled vscode leaves no extension registered or in a folder" ids_are "$oss"

# One editor whose settings cannot be written fails the target and keeps
# its own extensions; every other editor still moves and cleans up.
fresh one-stuck
mkdir -p "$cfg/Code/User"; printf '{}\n' >"$cfg/Code/User/settings.json"; chmod a-w -- "$cfg/Code/User"
for theme in nord dusk ember; do
  THEME_PATH="$with_code_codium" tinst "an unwritable VS Code settings file fails vscode on $theme" "$cfg" "$rt_empty" 3 "$any_out" "$any_out" theme apply "$theme"
done
chmod u+w -- "$cfg/Code/User"
check "VSCodium still selects the last palette's theme" extension_is_current "$oss" "$cfg/VSCodium/User/settings.json"
check "VSCodium still removes the extension no window shows" ids_are "$oss" "$dusk_id" "$ember_id"

# A disable whose removal fails in one editor still clears every other.
fresh disable-stuck
THEME_PATH="$with_code_codium" tinst "VS Code and codium land before the disable" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply nord
printf '{ "disabledTargets": ["vscode"] }\n' >"$cfg/vgshell/shell.json"
chmod a-w -- "$home/.vscode/extensions"
THEME_PATH="$with_code_codium" tinst "a disable that cannot clear VS Code fails vscode" "$cfg" "$rt_empty" 3 "$any_out" "$any_out" theme apply dusk
chmod u+w -- "$home/.vscode/extensions"
check "a disable that fails in VS Code still clears VSCodium" ids_are "$oss"

# The old extension leaves only once the new one is registered and
# selected: an old folder that cannot be removed fails the target with the
# new theme already registered and selected.
fresh order; settings="$cfg/VSCodium/User/settings.json"
THEME_PATH="$with_codium" tinst "codium lands nord before the stuck folder" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply nord
THEME_PATH="$with_codium" tinst "codium lands dusk before the stuck folder" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply dusk
stuck="$oss/$nord_id-1.0.0"; chmod a-w -- "$stuck"
THEME_PATH="$with_codium" tinst "an old folder that cannot go fails vscode" "$cfg" "$rt_empty" 3 \
  '{"state":"partial","shell":"applied","targets":[{"name":"vscode","state":"failed","reason":"unwritable","dropped":[]}],"theme":"ember","reason":null}' \
  "vgshell: refused: target=vscode reason=unwritable path=$stuck error=EACCES" theme apply --json ember
chmod u+w -- "$stuck"
check "the new theme is registered and selected before the old folder goes" extension_is_current "$oss" "$settings"

# Controls: each mutant drops one rule, and the assertion that pins it
# must turn. The rows above use the same assertions.
turned() { test "$("$@"; echo $?)" == 1; } # CMD...: the assertion fails
two_palettes() { # NAME: apply nord then dusk to codium alone under the mutant
  fresh "$1"; settings="$cfg/VSCodium/User/settings.json"
  THEME_PATH="$with_codium" tinst "the $1 mutant applies nord" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply nord
  THEME_PATH="$with_codium" tinst "the $1 mutant applies dusk" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply dusk
}
tree_control unstamped-name themes/targets/vscode/package.json '"name": "vgs-theme-@{extension.stamp}"' '"name": "vgs-theme"'
two_palettes unstamped-name
check "the unstamped-name mutant's manifest misses the theme's id" turned extension_is_current "$oss" "$settings"
tree_control one-selection themes/targets/vscode/target.json '"value": "vgs-@{extension.stamp}"' '"value": "vgs"'
two_palettes one-selection
check "the one-selection mutant never moves an open window's selection" turned extension_is_current "$oss" "$settings"
tree_control one-theme-id themes/targets/vscode/package.json '"id": "vgs-@{extension.stamp}", ' ''
two_palettes one-theme-id
check "the one-theme-id mutant contributes no theme the selection names" turned extension_is_current "$oss" "$settings"
tree_control one-id bin/lib/theme-render.js 'return { id: target.wiring.extension + "-" + stamp, version: EXTENSION_VERSION, stamp };' 'return { id: target.wiring.extension, version: EXTENSION_VERSION, stamp };'
two_palettes one-id
check "the one-id mutant gives an open window no new extension id" turned extension_is_current "$oss" "$settings"
judge_control no-registry "utf8Edit(text => render.registeredText(logic, text, extension.id, extension.version, editor.extensions))));" 'utf8Edit(text => null)));'
two_palettes no-registry
check "the no-registry mutant registers nothing" turned extension_is_current "$oss" "$settings"
judge_control keeps-obsolete "throwFailure(editFile(key, path.join(editor.extensions, OBSOLETE_FILE), false, utf8Edit(text => render.unobsoletedText(logic, text, target.wiring.extension))));" ''
fresh keeps-obsolete
mkdir -p "$oss"; printf '{"%s-1.0.5":true,"pub.gone-1.0.0":true}' "$base" >"$oss/.obsolete"
THEME_PATH="$with_codium" tinst "the keeps-obsolete mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply nord
check "the keeps-obsolete mutant leaves the extension marked" turned obsolete_is "$oss" '{"pub.gone-1.0.0":true}'
judge_control drops-shown 'keep.push(...shownExtensions(target, editor, selection));' ''
two_palettes drops-shown
check "the drops-shown mutant unregisters the theme a window shows" turned ids_are "$oss" "$nord_id" "$dusk_id"
judge_control drops-nothing '    dropExtension(key, target, editor, keep);' ''
two_palettes drops-nothing
THEME_PATH="$with_codium" tinst "the drops-nothing mutant applies ember" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply ember
check "the drops-nothing mutant keeps the first id" turned ids_are "$oss" "$dusk_id" "$ember_id"
judge_control keeps-folders 'for (const old of extensionFolders(editor.extensions, target, keep)) writing(' 'for (const old of []) writing('
two_palettes keeps-folders
THEME_PATH="$with_codium" tinst "the keeps-folders mutant applies ember" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply ember
check "the keeps-folders mutant keeps the first folder" turned ids_are "$oss" "$dusk_id" "$ember_id"
judge_control keeps-registered 'utf8Edit(text => render.unregisteredText(logic, text, target.wiring.extension, keep))));' 'utf8Edit(text => null)));'
two_palettes keeps-registered
THEME_PATH="$with_codium" tinst "the keeps-registered mutant applies ember" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply ember
check "the keeps-registered mutant keeps the first id registered" turned ids_are "$oss" "$dusk_id" "$ember_id"
judge_control drops-first '    keepExtension(key, target, entry.files, extension, editor);' '    dropExtension(key, target, editor, [extension.id]);
    keepExtension(key, target, entry.files, extension, editor);'
fresh drops-first; settings="$cfg/VSCodium/User/settings.json"
THEME_PATH="$with_codium" tinst "the drops-first mutant applies nord" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply nord
stuck="$oss/$nord_id-1.0.0"; chmod a-w -- "$stuck"
THEME_PATH="$with_codium" tinst "the drops-first mutant fails dusk on the stuck folder" "$cfg" "$rt_empty" 3 "$any_out" "$any_out" theme apply dusk
chmod u+w -- "$stuck"
check "the drops-first mutant registers no new theme before the old folder goes" turned extension_is_current "$oss" "$settings"
judge_control stops-at-first-editor '        if (first === null) first = failure;' '        if (failure !== null) return failure;'
fresh stops-at-first-editor
mkdir -p "$cfg/Code/User"; printf '{}\n' >"$cfg/Code/User/settings.json"; chmod a-w -- "$cfg/Code/User"
for theme in nord dusk ember; do
  THEME_PATH="$with_code_codium" tinst "the stops-at-first-editor mutant applies $theme" "$cfg" "$rt_empty" 3 "$any_out" "$any_out" theme apply "$theme"
done
chmod u+w -- "$cfg/Code/User"
check "the stops-at-first-editor mutant leaves VSCodium behind" turned ids_are "$oss" "$dusk_id" "$ember_id"
judge_control disable-stops-at-first-editor '            if (firstFailure === null) firstFailure = failure;' '            if (failure !== null) return failure;'
fresh disable-stops-at-first-editor
THEME_PATH="$with_code_codium" tinst "the disable-stops-at-first-editor mutant lands nord" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply nord
printf '{ "disabledTargets": ["vscode"] }\n' >"$cfg/vgshell/shell.json"
chmod a-w -- "$home/.vscode/extensions"
THEME_PATH="$with_code_codium" tinst "the disable-stops-at-first-editor mutant disables" "$cfg" "$rt_empty" 3 "$any_out" "$any_out" theme apply dusk
chmod u+w -- "$home/.vscode/extensions"
check "the disable-stops-at-first-editor mutant leaves VSCodium's extension" turned ids_are "$oss"
judge_control no-settings-create 'select.selectedText(selection.format, text === undefined && create ? ["qtct", "userjs"].includes(selection.format) ? "" : "{}\n" : text,' 'select.selectedText(selection.format, text,'
fresh no-settings-create
THEME_PATH="$with_codium" tinst "the no-create mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply nord
check "the no-create mutant writes no settings file" turned test -f "$cfg/VSCodium/User/settings.json"
tree_control codium-elsewhere themes/targets/vscode/target.json '"extensions": ".vscode-oss/extensions"' '"extensions": ".vscode-codium/extensions"'
fresh codium-elsewhere
THEME_PATH="$with_codium" tinst "the misplaced-codium mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply nord
check "the misplaced-codium mutant misses VSCodium's extensions directory" turned extension_is_current "$oss" "$cfg/VSCodium/User/settings.json"
unset THEME_BIN

rows_done test-vgshell-vscode
