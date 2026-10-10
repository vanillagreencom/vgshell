#!/usr/bin/env bash
# Controls for the entry wiring of `vgshell theme apply`: a target whose wiring
# names links keeps one symlink per link in its application's theme or
# extension directory, pointing at its file in the state directory's
# theme/, and edits no configuration file. Whatever else holds an entry
# path is replaced by its managed form, except a directory, which stays, and
# a disabled target loses only its own links and its owned directory. Only fixture targets run here, every command is a stub on
# the rows' PATH, and HOME and XDG_RUNTIME_DIR are temporary, so no row
# reaches a real application or the developer's session.
set -euo pipefail

source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"
theme_tree
export THEME_PATH="$stubs:$theme_path"
home="$tmp/home"; live="$state/theme"
theme_pkg "$tree/themes/dusk" '{ "schemaVersion": 1, "name": "dusk", "tokens": { "palette": { "accent": "#111111" } } }'
theme_pkg "$tree/themes/nord" '{ "schemaVersion": 1, "name": "nord", "tokens": { "palette": { "accent": "#222222" } } }'

# `lnk` links one file into its application's own themes directory under
# the configuration home; `cpy` copies one there for applications that watch
# the file itself; `occ` links where the rows put something of the user's;
# `ext` owns an extension directory under HOME holding two links, as a local
# editor extension is laid out.
entry_target() { # NAME WIRING_JSON FILES_JSON
  mkdir -p "$tree/themes/targets/$1"
  printf '{ "app": "%s", "runsCode": false, "encoder": "hex6", "files": %s, "detect": [], "wiring": %s, "reload": null }\n' "$1" "$3" "$2" >"$tree/themes/targets/$1/target.json"
}
for name in lnk occ; do
  entry_target "$name" "{ \"base\": \"config\", \"dir\": \"$name/themes\", \"owned\": false, \"links\": { \"vgs.toml\": \"$name.toml\" } }" "[{ \"template\": \"$name.toml\", \"destination\": \"$name.toml\" }]"
  printf 'accent = "#@{palette.accent}"\n' >"$tree/themes/targets/$name/$name.toml"
done
entry_target cpy '{ "base": "config", "dir": "cpy/themes", "owned": false, "copies": { "vgs.toml": "cpy.toml" } }' '[{ "template": "cpy.toml", "destination": "cpy.toml" }]'
printf 'accent = "#@{palette.accent}"\n' >"$tree/themes/targets/cpy/cpy.toml"
entry_target ext '{ "base": "home", "dir": ".ext/extensions/vgs-theme", "owned": true, "links": { "package.json": "ext.pkg.json", "vgs-color-theme.json": "ext.json" } }' '[{ "template": "theme.json", "destination": "ext.json" }, { "template": "package.json", "destination": "ext.pkg.json" }]'
printf '{ "colors": { "editor.background": "#@{color.background}", "focusBorder": "#@{palette.accent}" } }\n' >"$tree/themes/targets/ext/theme.json"
printf '{ "name": "vgs-theme" }\n' >"$tree/themes/targets/ext/package.json"

target_state() { # NAME: the target's [state, reason] in $tmp/apply.json
  python3 -c 'import json,sys; print(*[(t["state"], t["reason"]) for t in json.load(open(sys.argv[1]))["targets"] if t["name"] == sys.argv[2]][0])' "$tmp/apply.json" "$1"
}
apply_json() { # NAME WANT_EXIT PACKAGE [WANT_FIRST_STDERR]: apply with --json into $tmp/apply.json
  tinst "$1" "$cfg" "$rt_empty" "$2" "$any_out" "${4:-}" theme apply --json "$3"
  tail -n 1 "$tmp/out" >"$tmp/apply.json"
}
links_to() { [[ -L $1 && "$(readlink -- "$1")" == "$2" ]]; } # PATH TARGET
names_in() { [[ "$(find "$1" -mindepth 1 -printf '%P\n' | sort | tr '\n' ' ')" == "$2" ]]; } # DIR "NAME ..."
regular_with() { [[ -f $1 && ! -L $1 && "$(cat -- "$1"; printf x)" == "$2"x ]]; } # PATH TEXT
stamp() { stat -c '%i %Y' -- "$1"; } # PATH
ext_dir="$home/.ext/extensions/vgs-theme"
disable() { printf '{ "disabledTargets": [%s] }\n' "$1" >"$cfg/vgshell/shell.json"; }
# Each case starts from no configuration and no extension directory, with
# lnk's directory a dotfile manager's link into another tree and occ's
# link path holding the user's own file.
fresh() { # NAME
  cfg="$tmp/cfg-$1"; mkdir -p "$cfg/vgshell" "$tmp/dotfiles-$1/lnk/themes" "$cfg/occ/themes"
  rm -rf -- "$home/.ext"
  ln -s -- "$tmp/dotfiles-$1/lnk" "$cfg/lnk"
  printf 'mine\n' >"$cfg/occ/themes/vgs.toml"
}

fresh rows
apply_json "an apply with entry targets" 0 dusk
check "a linked target is written" test "$(target_state lnk)" == "written None"
check "a copied target is written" test "$(target_state cpy)" == "written None"
check "an owning target is written" test "$(target_state ext)" == "written None"
check "a link stands in the application's directory, through the dotfile link, naming its state file" links_to "$tmp/dotfiles-rows/lnk/themes/vgs.toml" "$live/lnk.toml"
check "a copy stands in the application's directory as a regular file" regular_with "$cfg/cpy/themes/vgs.toml" $'accent = "#111111"\n'
check "the dotfile manager's directory link stays a link" test -L "$cfg/lnk"
check "the link reads the rendered file" test "$(cat "$cfg/lnk/themes/vgs.toml")" == 'accent = "#111111"'
check "nothing else is written in the application's directory" names_in "$tmp/dotfiles-rows/lnk" "themes themes/vgs.toml "
check "an owned directory is created under HOME holding only its links" names_in "$ext_dir" "package.json vgs-color-theme.json "
check "an owned directory's links name their state files" links_to "$ext_dir/package.json" "$live/ext.pkg.json"
check "each link names its own state file" links_to "$ext_dir/vgs-color-theme.json" "$live/ext.json"
check "a path holding the user's file is written" test "$(target_state occ)" == "written None"
check "the user's file is replaced by the managed link" links_to "$cfg/occ/themes/vgs.toml" "$live/occ.toml"
if ! inode="$(stat -c %i -- "$cfg/lnk/themes/vgs.toml")"; then fail "the link can be read before the second package"; inode=none; fi
if ! copy_stamp="$(stamp "$cfg/cpy/themes/vgs.toml")"; then fail "the copy can be read before the second package"; copy_stamp=none; fi
apply_json "an unchanged package" 0 dusk
check "an unchanged copy is not rewritten" test "$(stamp "$cfg/cpy/themes/vgs.toml")" == "$copy_stamp"
apply_json "a second package" 0 nord
check "a managed link is left as it is" test "$(stat -c %i -- "$cfg/lnk/themes/vgs.toml")" == "$inode"
check "the link reads the new render" test "$(cat "$cfg/lnk/themes/vgs.toml")" == 'accent = "#222222"'
check "a changed copy is replaced by rename" test "$(stamp "$cfg/cpy/themes/vgs.toml")" != "$copy_stamp"
check "the copy holds the new render" regular_with "$cfg/cpy/themes/vgs.toml" $'accent = "#222222"\n'

fresh symlink
mkdir -p "$cfg/cpy/themes"
ln -s -- "$live/cpy.toml" "$cfg/cpy/themes/vgs.toml"
apply_json "a symlink at a copy path" 0 dusk
check "a symlink at a copy path is written" test "$(target_state cpy)" == "written None"
check "the symlink at the copy path is replaced by the copy" regular_with "$cfg/cpy/themes/vgs.toml" $'accent = "#111111"\n'

fresh edited
apply_json "a copy before editing" 0 dusk

printf 'mine\n' >"$cfg/cpy/themes/vgs.toml"
apply_json "an edited copy path" 0 nord
check "an edited copy's target is written" test "$(target_state cpy)" == "written None"
check "an edited copy is replaced by the new render" regular_with "$cfg/cpy/themes/vgs.toml" $'accent = "#222222"\n'

# A foreign link at a link's path, dangling here, is replaced. A directory
# at an entry path, or a file where the entry directory belongs, fails its
# target and stays as it was.
rm -- "$cfg/occ/themes/vgs.toml"; ln -s -- "$tmp/elsewhere.toml" "$cfg/occ/themes/vgs.toml"
apply_json "a foreign link at a link's path" 0 dusk
check "a foreign link's target is written" test "$(target_state occ)" == "written None"
check "a foreign link is replaced by the managed link" links_to "$cfg/occ/themes/vgs.toml" "$live/occ.toml"
rm -- "$cfg/occ/themes/vgs.toml" "$cfg/cpy/themes/vgs.toml"
mkdir -- "$cfg/occ/themes/vgs.toml" "$cfg/cpy/themes/vgs.toml"
printf 'mine\n' >"$cfg/occ/themes/vgs.toml/notes"; printf 'mine\n' >"$cfg/cpy/themes/vgs.toml/notes"
apply_json "a directory at each entry path" 3 nord "vgshell: refused: target=cpy reason=unwritable path=$cfg/cpy/themes/vgs.toml error=EISDIR"
check "a directory at a copy path fails its target" test "$(target_state cpy)" == "failed unwritable"
check "a directory at a link path fails its target" test "$(target_state occ)" == "failed unwritable"
check "the directory at the copy path keeps its content" regular_with "$cfg/cpy/themes/vgs.toml/notes" $'mine\n'
check "the directory at the link path keeps its content" regular_with "$cfg/occ/themes/vgs.toml/notes" $'mine\n'
check "a failed link rename leaves no sibling beside the directory" names_in "$cfg/occ/themes" "vgs.toml vgs.toml/notes "
check "a failed copy rename leaves no sibling beside the directory" names_in "$cfg/cpy/themes" "vgs.toml vgs.toml/notes "
rm -r -- "$cfg/occ/themes"; printf 'mine\n' >"$cfg/occ/themes"
apply_json "a file where the directory belongs" 3 nord "vgshell: refused: target=cpy reason=unwritable path=$cfg/cpy/themes/vgs.toml error=EISDIR"
check "a file at the directory fails its target" test "$(target_state occ)" == "failed unwritable"
check "the file at the directory is kept" regular_with "$cfg/occ/themes" $'mine\n'

# A disabled target loses its own links and its owned directory once that
# is empty; the application's directory, anything the user put there and a
# path the target never managed stay.
printf 'yours\n' >"$cfg/lnk/themes/other.toml"
fresh disabled
apply_json "entry targets before disable" 0 dusk
printf 'yours\n' >"$cfg/lnk/themes/other.toml"
rm -- "$cfg/occ/themes/vgs.toml"; printf 'mine\n' >"$cfg/occ/themes/vgs.toml"
disable '"lnk", "cpy", "ext", "occ"'
apply_json "disabling the entry targets" 0 dusk
check "a disabled target is skipped" test "$(target_state lnk)" == "skipped disabled"
check "a disabled target's link is removed and the rest of its directory stays" names_in "$tmp/dotfiles-disabled/lnk" "themes themes/other.toml "
check "a disabled target's managed copy is removed" test ! -e "$cfg/cpy/themes/vgs.toml"
check "a disabled target's owned directory is removed" test ! -e "$ext_dir" -a -d "$home/.ext/extensions"
check "a disabled target's files leave theme/" test ! -e "$live/lnk.toml" -a ! -e "$live/cpy.toml" -a ! -e "$live/ext.json"
check "a disabled target never removes the user's file" test "$(cat "$cfg/occ/themes/vgs.toml")" == mine
disable ''
apply_json "enabling them again" 0 nord
check "the links come back" links_to "$ext_dir/package.json" "$live/ext.pkg.json"
printf 'mine\n' >"$cfg/cpy/themes/vgs.toml"
disable '"cpy"'
apply_json "disabling a user-edited copy" 0 dusk
check "a disabled target never removes the user's edited copy" regular_with "$cfg/cpy/themes/vgs.toml" $'mine\n'
disable ''
printf 'notes\n' >"$ext_dir/notes.txt"
disable '"ext"'
apply_json "disabling an owned directory the user wrote into" 0 dusk
check "an owned directory holding the user's file keeps it and loses the links" names_in "$ext_dir" "notes.txt "

# Controls: each judge copy drops one rule, and the row that pins it turns.
control() { # NAME NEEDLE REPLACEMENT
  judge_control "$1" "$2" "$3"; fresh "$1"
}
control any-link-managed 'return stat.isSymbolicLink() && fs.readlinkSync(file) === item.to ?' 'return stat.isSymbolicLink() ?'
rm -- "$cfg/occ/themes/vgs.toml"; ln -s -- "$tmp/elsewhere.toml" "$cfg/occ/themes/vgs.toml"
disable '"occ"'
apply_json "the any-link mutant disables occ" 0 dusk
check "the any-link mutant removes a link it never made" test ! -L "$cfg/occ/themes/vgs.toml"
control symlink-managed '        if (!stat.isFile()) return "occupied";' '        if (stat.isSymbolicLink()) return "managed";
        if (!stat.isFile()) return "occupied";'
mkdir -p "$cfg/cpy/themes"
ln -s -- "$live/cpy.toml" "$cfg/cpy/themes/vgs.toml"
apply_json "the symlink-managed mutant applies" 0 dusk
check "the symlink-managed mutant keeps the symlink at the copy path" links_to "$cfg/cpy/themes/vgs.toml" "$live/cpy.toml"
control any-copy-managed 'return item.newBytes !== undefined && bytes.equals(item.newBytes) ? "managed" : "occupied";' 'return "managed";'
mkdir -p "$cfg/cpy/themes"; printf 'mine\n' >"$cfg/cpy/themes/vgs.toml"
apply_json "the any-copy mutant applies" 0 dusk
check "the any-copy mutant keeps the user's copy" regular_with "$cfg/cpy/themes/vgs.toml" $'mine\n'
control leave-present 'if (entryState(file, item) === "managed") continue;' 'if (entryState(file, item) !== "absent") continue;'
apply_json "the leave-present mutant applies" 0 dusk
check "the leave-present mutant keeps the user's file at a link path" regular_with "$cfg/occ/themes/vgs.toml" $'mine\n'
control rm-entry 'if (item.kind === "link") writing(file, key, () => linkByRename(item.to, file));' 'if (item.kind === "link") writing(file, key, () => { fs.rmSync(file, { recursive: true, force: true }); linkByRename(item.to, file); });'
rm -- "$cfg/occ/themes/vgs.toml"; mkdir -- "$cfg/occ/themes/vgs.toml"; printf 'mine\n' >"$cfg/occ/themes/vgs.toml/notes"
apply_json "the rm-entry mutant applies" 0 dusk
check "the rm-entry mutant deletes the directory at the link path" test ! -e "$cfg/occ/themes/vgs.toml/notes"
control rm-dir-file 'writing(dir, key, () => fs.mkdirSync(dir, { recursive: true }));' 'writing(dir, key, () => { if (fs.lstatSync(dir, { throwIfNoEntry: false })?.isFile()) fs.unlinkSync(dir); fs.mkdirSync(dir, { recursive: true }); });'
rm -r -- "$cfg/occ/themes"; printf 'mine\n' >"$cfg/occ/themes"
apply_json "the rm-dir-file mutant applies" 0 dusk
check "the rm-dir-file mutant deletes the file where the directory belongs" test -d "$cfg/occ/themes"
tree_control keep-sibling bin/lib/judge-files.js '    const tmp = link + ".vgshell-" + process.pid;' '    const tmp = link + ".vgshell-" + process.pid; const rm = fs.rmSync; fs.rmSync = (p, o) => p === tmp ? undefined : rm(p, o);'; fresh keep-sibling
rm -- "$cfg/occ/themes/vgs.toml"; mkdir -- "$cfg/occ/themes/vgs.toml"; printf 'mine\n' >"$cfg/occ/themes/vgs.toml/notes"
apply_json "the keep-sibling mutant applies" 3 dusk "vgshell: refused: target=occ reason=unwritable path=$cfg/occ/themes/vgs.toml error=EISDIR"
check "the keep-sibling mutant leaves its link beside the directory" test -n "$(compgen -G "$cfg/occ/themes/vgs.toml.vgshell-*")"
control never-rmdir 'if (target.wiring.owned) writing(dir, key, () => {' 'if (false) writing(dir, key, () => {'
apply_json "the never-rmdir mutant applies" 0 dusk
disable '"ext"'
apply_json "the never-rmdir mutant disables ext" 0 nord
check "the never-rmdir mutant leaves the owned directory" test -d "$ext_dir"
control rm-recursive 'fs.rmdirSync(dir);' 'fs.rmSync(dir, { recursive: true });'
apply_json "the recursive mutant applies" 0 dusk
printf 'notes\n' >"$ext_dir/notes.txt"
disable '"ext"'
apply_json "the recursive mutant disables ext" 0 nord
check "the recursive mutant deletes the user's file" test ! -e "$ext_dir/notes.txt"
control remove-any 'if (entryState(file, item) === "managed") writing(file, key, () => fs.unlinkSync(file));' 'writing(file, key, () => fs.rmSync(file, { force: true }));'
disable '"occ"'
apply_json "the remove-any mutant disables occ" 0 dusk
check "the remove-any mutant deletes the user's file" test ! -e "$cfg/occ/themes/vgs.toml"
control home-as-config 'case "home": return os.homedir();' 'case "home": return configHome;'
apply_json "the home-as-config mutant applies" 0 dusk
check "the home-as-config mutant puts the owned directory under the configuration home" test -d "$cfg/.ext/extensions/vgs-theme" -a ! -e "$ext_dir"
unset THEME_BIN

# The cache base: `dir` is under ${XDG_CACHE_HOME:-~/.cache}, the fallback
# when the variable is unset and the variable when it is set.
entry_target cch '{ "base": "cache", "dir": "wal", "owned": false, "links": { "colors.json": "cch.json" } }' '[{ "template": "cch.json", "destination": "cch.json" }]'
printf '{ "special": { "background": "#@{color.background}" } }\n' >"$tree/themes/targets/cch/cch.json"
fresh cache
apply_json "a cache target without XDG_CACHE_HOME" 0 dusk
check "a cache target is written" test "$(target_state cch)" == "written None"
check "a cache target's link stands under ~/.cache" links_to "$home/.cache/wal/colors.json" "$live/cch.json"
xdg_cache="$tmp/xdg-cache"
base_env+=(XDG_CACHE_HOME="$xdg_cache")
apply_json "a cache target under XDG_CACHE_HOME" 0 nord
check "a cache target's link stands under XDG_CACHE_HOME" links_to "$xdg_cache/wal/colors.json" "$live/cch.json"
judge_control cache-as-home 'process.env.XDG_CACHE_HOME || path.join(os.homedir(), ".cache")' 'path.join(os.homedir(), ".cache")'
rm -r -- "$xdg_cache"
apply_json "the cache-as-home mutant applies" 0 dusk
check "the cache-as-home mutant ignores XDG_CACHE_HOME" test ! -e "$xdg_cache/wal/colors.json"
unset THEME_BIN

rows_done test-vgshell-entries
