#!/usr/bin/env bash
# Controls for `vgshell hypr` and `vgshell edit`: wire and unwire keep or
# remove the line that loads the Hyprland layer in hyprland.lua, edit opens
# cited configuration files, under a temporary HOME and XDG_CONFIG_HOME, and
# render asks a running shell through a stub qs. No row reads or writes the
# developer's own Hyprland configuration.
set -euo pipefail

source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"

# The stub answers `qs ipc ... call <target> <fn>` with STUB_REPLY and
# records its arguments in STUB_ARGS, as test-vgshell.sh's does.
cat >"$tmp/qs" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"${STUB_ARGS:-/dev/null}"
printf '%s\n' "${STUB_REPLY:-ok}"
EOF
chmod +x "$tmp/qs"
rt_live="$tmp/rt-live"; mkdir -p "$rt_live"; printf '%s\n' "$$" >"$rt_live/vgshell.lock"

layer="$tmp/home/.local/state/vgshell/hypr/vgs.lua"
line="pcall(dofile, \"$layer\")"
wired_first() { # LUA OWN_TEXT_FILE
  [[ "$(head -n 1 -- "$1")" == "$line" ]] && tail -n +2 -- "$1" | cmp -s - "$2"
}

# No hyprland.lua: state reports absent without creating anything, wire
# refuses and creates nothing; unwire has nothing to remove.
cfg="$tmp/cfg-none"; mkdir -p "$cfg"
inst "state with no hyprland.lua reports absent" "$cfg" "$rt_empty" 0 "ok hypr=absent path=$cfg/hypr/hyprland.lua" "" hypr state
check "state creates no hyprland.lua" test ! -e "$cfg/hypr"
inst "wire with no hyprland.lua is refused" "$cfg" "$rt_empty" 1 "" "vgshell: refused: hypr=wiring-file-absent path=$cfg/hypr/hyprland.lua" hypr wire
check "wire creates no hyprland.lua" test ! -e "$cfg/hypr"
inst "unwire with no hyprland.lua changes nothing" "$cfg" "$rt_empty" 0 "ok hypr=unchanged path=$cfg/hypr/hyprland.lua" "" hypr unwire
check "unwire creates no hyprland.lua" test ! -e "$cfg/hypr"

# A hyprland.lua takes the line first and keeps every other byte; a second
# wire, and a line the user moved lower, change nothing; the line inside a
# comment is no line.
cfg="$tmp/cfg-lua"; lua="$cfg/hypr/hyprland.lua"; mkdir -p "$cfg/hypr"
printf -- '-- mine: %s\nhl.config({ general = { border_size = 3 } })\n' "$line" >"$lua"; cp -- "$lua" "$tmp/own"
inst "state reports unwired before the line is whole" "$cfg" "$rt_empty" 0 "ok hypr=unwired path=$lua" "" hypr state
inst "wire keeps the line in hyprland.lua" "$cfg" "$rt_empty" 0 "ok hypr=wired path=$lua" "" hypr wire
check "the line goes first and every other byte stays" wired_first "$lua" "$tmp/own"
inst "state reports wired after wire" "$cfg" "$rt_empty" 0 "ok hypr=wired path=$lua" "" hypr state
cp -- "$lua" "$tmp/wired"
inst "a second wire changes nothing" "$cfg" "$rt_empty" 0 "ok hypr=unchanged path=$lua" "" hypr wire
check "the second wire leaves the file byte for byte" cmp -s -- "$lua" "$tmp/wired"
{ tail -n +2 -- "$tmp/wired"; printf '%s\n' "$line"; } >"$lua"; cp -- "$lua" "$tmp/moved"
inst "a wire over a line the user moved changes nothing" "$cfg" "$rt_empty" 0 "ok hypr=unchanged path=$lua" "" hypr wire
check "the moved line stays where the user put it" cmp -s -- "$lua" "$tmp/moved"
printf '%s\n' "$line" >>"$lua"
inst "unwire removes the line" "$cfg" "$rt_empty" 0 "ok hypr=unwired path=$lua" "" hypr unwire
check "unwire removes every copy and leaves the file as it was before wire" cmp -s -- "$lua" "$tmp/own"
inst "a second unwire changes nothing" "$cfg" "$rt_empty" 0 "ok hypr=unchanged path=$lua" "" hypr unwire

# A symlinked hyprland.lua, as a dotfile manager keeps it: the file it names
# is edited with its mode, and the link stays a link.
cfg="$tmp/cfg-link"; mkdir -p "$cfg/hypr" "$tmp/dotfiles"
printf 'hl.config({})\n' >"$tmp/dotfiles/hyprland.lua"; chmod 600 -- "$tmp/dotfiles/hyprland.lua"; cp -- "$tmp/dotfiles/hyprland.lua" "$tmp/linked-own"
ln -s -- "$tmp/dotfiles/hyprland.lua" "$cfg/hypr/hyprland.lua"
inst "wire through a symlink" "$cfg" "$rt_empty" 0 "ok hypr=wired path=$cfg/hypr/hyprland.lua" "" hypr wire
check "the symlink stays a link to the same file" test "$(readlink -- "$cfg/hypr/hyprland.lua")" == "$tmp/dotfiles/hyprland.lua"
check "the linked file takes the line first" wired_first "$tmp/dotfiles/hyprland.lua" "$tmp/linked-own"
check "the linked file keeps its mode" test "$(stat -c %a -- "$tmp/dotfiles/hyprland.lua")" == 600

# Refusals: a hyprland.lua that cannot be read, a state directory no Lua
# string can hold, and bad invocations.
cfg="$tmp/cfg-dir"; mkdir -p "$cfg/hypr/hyprland.lua"
inst "an unreadable hyprland.lua is refused" "$cfg" "$rt_empty" 1 "" "vgshell: refused: hypr=unreadable path=$cfg/hypr/hyprland.lua error=EISDIR" hypr wire
cfg="$tmp/cfg-lua"
saved_env=("${base_env[@]}")
base_env+=(XDG_STATE_HOME="$tmp/st\"ate")
inst "a state directory holding a quote is refused" "$cfg" "$rt_empty" 1 "" "vgshell: refused: hypr=unquotable path=$tmp/st\"ate/vgshell/hypr/vgs.lua" hypr wire
inst "state with a quoted state directory is refused" "$cfg" "$rt_empty" 1 "" "vgshell: refused: hypr=unquotable path=$tmp/st\"ate/vgshell/hypr/vgs.lua" hypr state
base_env=("${saved_env[@]}")
check "the refused wire leaves hyprland.lua" cmp -s -- "$lua" "$tmp/own"
inst "an unknown hypr subcommand is exit 2" "$cfg" "$rt_empty" 2 "" "vgshell: refused: hypr-subcommand=frobnicate" hypr frobnicate
inst "a missing hypr subcommand is exit 2" "$cfg" "$rt_empty" 2 "" "vgshell: refused: hypr-subcommand=missing" hypr
inst "an argument after wire is exit 2" "$cfg" "$rt_empty" 2 "" "vgshell: refused: argument=now" hypr wire now
inst "an argument after state is exit 2" "$cfg" "$rt_empty" 2 "" "vgshell: refused: argument=now" hypr state now

# remove-bind takes one whole bind line out of a user file under the hypr
# directory, through the directory's symlink, with the mode kept and no
# other byte changed; restore-bind puts the printed line back byte for
# byte. Each refuses a line that is no whole call binding the key, a file
# outside the hypr directory and an absent file.
cfg="$tmp/cfg-binds"; mkdir -p "$cfg" "$tmp/dot-binds"; ln -s -- "$tmp/dot-binds" "$cfg/hypr"
binds="$cfg/hypr/binds.lua"
printf 'local mod = "SUPER"\nhl.bind("SUPER + F7", hl.dsp.exec_cmd("true")) -- mine\nhl.bind(\n  "SUPER + F8", hl.dsp.exec_cmd("true"))\n' >"$tmp/dot-binds/binds.lua"
chmod 640 -- "$tmp/dot-binds/binds.lua"; cp -- "$tmp/dot-binds/binds.lua" "$tmp/binds-own"
removed_line='hl.bind("SUPER + F7", hl.dsp.exec_cmd("true")) -- mine'
undo='{"text":"hl.bind(\"SUPER + F7\", hl.dsp.exec_cmd(\"true\")) -- mine\n","before":"local mod = \"SUPER\"\n","after":"hl.bind(\n"}'
inst "remove-bind takes the line out and prints it with its neighbours" "$cfg" "$rt_empty" 0 "ok hypr=bind-removed path=$binds line=2 undo=$undo" "" hypr remove-bind "$binds" 2 SUPER+F7
check "remove-bind leaves every other line as it was" cmp -s -- "$tmp/dot-binds/binds.lua" <(grep -vxF -- "$removed_line" "$tmp/binds-own")
check "remove-bind keeps the directory a symlink" test "$(readlink -- "$cfg/hypr")" == "$tmp/dot-binds"
check "remove-bind keeps the file's mode" test "$(stat -c %a -- "$tmp/dot-binds/binds.lua")" == 640
inst "restore-bind puts the line back" "$cfg" "$rt_empty" 0 "ok hypr=bind-restored path=$binds line=2" "" hypr restore-bind "$binds" 2 "$undo"
check "restore-bind gives the file its bytes back" cmp -s -- "$tmp/dot-binds/binds.lua" "$tmp/binds-own"
inst "a line binding another key is refused" "$cfg" "$rt_empty" 1 "" "vgshell: refused: hypr=user-bind path=$binds not-whole line=2 key=SUPER+F9" hypr remove-bind "$binds" 2 SUPER+F9
inst "a call over two lines is refused" "$cfg" "$rt_empty" 1 "" "vgshell: refused: hypr=user-bind path=$binds not-whole line=3 key=SUPER+F8" hypr remove-bind "$binds" 3 SUPER+F8
inst "a line past the end is refused" "$cfg" "$rt_empty" 1 "" "vgshell: refused: hypr=user-bind path=$binds no-line line=9 lines=4" hypr remove-bind "$binds" 9 SUPER+F7
inst "a restored line that is no bind call is refused" "$cfg" "$rt_empty" 1 "" "vgshell: refused: hypr=user-bind path=$binds not-whole line=1" hypr restore-bind "$binds" 1 '{"text":"os.execute(\"true\")\n","before":null,"after":"local mod = \"SUPER\"\n"}'
inst "an undo that is no JSON is refused" "$cfg" "$rt_empty" 1 "" "vgshell: refused: hypr=user-bind path=$binds undo-unread" hypr restore-bind "$binds" 1 'hl.bind("SUPER + F7", f)'
inst "a line whose neighbours no longer meet is refused" "$cfg" "$rt_empty" 1 "" "vgshell: refused: hypr=user-bind path=$binds moved line=2 places=0" hypr restore-bind "$binds" 2 "$undo"
check "the refusals leave the file as it was" cmp -s -- "$tmp/dot-binds/binds.lua" "$tmp/binds-own"
printf '%s\n' "$removed_line" >"$tmp/outside.lua"
inst "a file outside the hypr directory is refused" "$cfg" "$rt_empty" 1 "" "vgshell: refused: hypr=outside-config path=$tmp/outside.lua" hypr remove-bind "$tmp/outside.lua" 1 SUPER+F7
inst "a path climbing out of the hypr directory is refused" "$cfg" "$rt_empty" 1 "" "vgshell: refused: hypr=outside-config path=$cfg/hypr/../../outside.lua" hypr remove-bind "$cfg/hypr/../../outside.lua" 1 SUPER+F7
check "the outside file keeps its line" grep -qxF -- "$removed_line" "$tmp/outside.lua"
inst "an absent file is refused and not created" "$cfg" "$rt_empty" 1 "" "vgshell: refused: hypr=wiring-file-absent path=$cfg/hypr/none.lua" hypr remove-bind "$cfg/hypr/none.lua" 1 SUPER+F7
check "the absent file stays absent" test ! -e "$cfg/hypr/none.lua"
inst "remove-bind with two arguments is exit 2" "$cfg" "$rt_empty" 2 "" "vgshell: refused: arguments=2 want=3" hypr remove-bind "$binds" 2

# render asks the running shell, and needs one.
inst "render with no shell exits 69" "$cfg" "$rt_empty" 69 "" "vgshell: refused: shell=not-running lock=$rt_empty/vgshell.lock" hypr render
INST_REPLY=ok inst "render prints the shell's ok" "$cfg" "$rt_live" 0 "ok" "" hypr render
check "render calls the shell's renderHyprland" test "$(cat "$tmp/args")" == "ipc --pid $$ call shell renderHyprland"
INST_REPLY="refused: hyprland=pending" inst "a shell refusal is a refusal with exit 1" "$cfg" "$rt_live" 1 "" "vgshell: refused: hyprland=pending" hypr render

# edit opens a cited configuration file under XDG_CONFIG_HOME, with $EDITOR
# first and xdg-open as the fallback. It refuses paths outside that tree
# before it launches an opener.
edit_dir="$tmp/edit-bin"; mkdir -p "$edit_dir"
cat >"$edit_dir/stub" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$EDIT_RECORD"
EOF
chmod +x "$edit_dir/stub"
ln -s -- "$edit_dir/stub" "$edit_dir/nvim"
ln -s -- "$edit_dir/stub" "$edit_dir/code"
ln -s -- "$edit_dir/stub" "$edit_dir/xdg-open"
cfg="$tmp/cfg-edit"; mkdir -p "$cfg/hypr"; printf 'return {}\n' >"$cfg/hypr/hyprland.lua"
inst_env=(EDITOR="stub --wait" EDIT_RECORD="$tmp/edit-argv")
INST_PATH="$edit_dir:$base_path" inst "edit uses EDITOR split on spaces" "$cfg" "$rt_empty" 0 "" "" edit hypr/hyprland.lua
check "EDITOR receives the absolute file path after its own argument" test "$(tr '\n' ' ' <"$tmp/edit-argv")" == "--wait $cfg/hypr/hyprland.lua "
inst_env=(EDITOR="$edit_dir/nvim --wait" EDIT_RECORD="$tmp/edit-argv")
INST_PATH="$edit_dir:$base_path" inst "edit gives a line to an editor that accepts one" "$cfg" "$rt_empty" 0 "" "" edit hypr/hyprland.lua 12
check "nvim receives +LINE before the path" test "$(tr '\n' ' ' <"$tmp/edit-argv")" == "--wait +12 $cfg/hypr/hyprland.lua "
inst_env=(EDITOR="$edit_dir/code --wait" EDIT_RECORD="$tmp/edit-argv")
INST_PATH="$edit_dir:$base_path" inst "edit omits the line for another editor" "$cfg" "$rt_empty" 0 "" "" edit hypr/hyprland.lua 12
check "code receives no +LINE argument" test "$(tr '\n' ' ' <"$tmp/edit-argv")" == "--wait $cfg/hypr/hyprland.lua "
inst_env=(EDIT_RECORD="$tmp/edit-argv")
INST_PATH="$edit_dir:$base_path" inst "edit falls back to xdg-open" "$cfg" "$rt_empty" 0 "" "" edit hypr/hyprland.lua
check "xdg-open receives the absolute file path" test "$(cat "$tmp/edit-argv")" == "$cfg/hypr/hyprland.lua"
edit_min="$tmp/edit-min"; mkdir -p "$edit_min"
for tool in bash readlink dirname id basename; do ln -s -- "$(command -v "$tool")" "$edit_min/$tool"; done
inst_env=()
INST_PATH="$edit_min" inst "edit refuses without an opener" "$cfg" "$rt_empty" 1 "" "vgshell: refused: opener=missing" edit hypr/hyprland.lua
INST_PATH="$edit_dir:$base_path" inst "edit refuses an absolute path" "$cfg" "$rt_empty" 2 "" "vgshell: refused: edit=/etc/passwd reason=absolute" edit /etc/passwd
INST_PATH="$edit_dir:$base_path" inst "edit refuses a parent path" "$cfg" "$rt_empty" 2 "" "vgshell: refused: edit=hypr/../secret reason=parent" edit hypr/../secret
INST_PATH="$edit_dir:$base_path" inst "edit refuses a missing file" "$cfg" "$rt_empty" 1 "" "vgshell: refused: file=unreadable path=$cfg/hypr/missing.lua" edit hypr/missing.lua
INST_PATH="$edit_dir:$base_path" inst "edit refuses a bad line" "$cfg" "$rt_empty" 2 "" "vgshell: refused: line=0 reason=positive-integer" edit hypr/hyprland.lua 0
INST_PATH="$edit_dir:$base_path" inst "edit refuses an extra argument" "$cfg" "$rt_empty" 2 "" "vgshell: refused: argument=extra" edit hypr/hyprland.lua 1 extra
unset INST_PATH
inst_env=()

# Must-fail controls, each on a copy of the runner whose judge breaks one
# rule the rows above hold.
theme_tree
cfg="$tmp/cfg-control"; lua="$cfg/hypr/hyprland.lua"
tree_control creates bin/vgshell-hypr-judge 'editFile("hypr", file, false,' 'editFile("hypr", file, true,'
INST_BIN="$THEME_BIN" inst "the creating mutant wires with no hyprland.lua" "$cfg" "$rt_empty" 0 "$any_out" "" hypr wire
check "the creating mutant creates hyprland.lua" test -e "$lua"
rm -rf -- "${cfg:?}"; mkdir -p "$cfg/hypr"; cp -- "$tmp/own" "$lua"
tree_control unquoted bin/vgshell-hypr-judge 'if (/["\\\n\r]/.test(layer))' 'if (false)'
saved_env=("${base_env[@]}")
base_env+=(XDG_STATE_HOME="$tmp/st\"ate")
INST_BIN="$THEME_BIN" inst "the unquoted mutant wires a quoted state directory" "$cfg" "$rt_empty" 0 "$any_out" "" hypr wire
base_env=("${saved_env[@]}")
check "the unquoted mutant writes a line a Lua string cannot hold" grep -qF -- "$tmp/st\"ate" "$lua"
cp -- "$tmp/own" "$lua"
tree_control wires-on-unwire bin/vgshell-hypr-judge 'unwire: render.unwiredText' 'unwire: render.wiredText'
INST_BIN="$THEME_BIN" inst "the wiring mutant runs unwire" "$cfg" "$rt_empty" 0 "$any_out" "" hypr unwire
check "the wiring mutant adds the line unwire must remove" grep -qxF -- "$line" "$lua"
cp -- "$tmp/own" "$lua"
tree_control always-changed bin/vgshell-hypr-judge 'changed = typeof next === "string";' 'changed = true;'
INST_BIN="$THEME_BIN" inst "the always-changed mutant reports an unchanged unwire as a change" "$cfg" "$rt_empty" 0 "ok hypr=unwired path=$lua" "" hypr unwire
tree_control state-always-wired bin/vgshell-hypr-judge 'render.wiredText(text, line, undefined) === null ? "wired" : "unwired"' 'true ? "wired" : "unwired"'
INST_BIN="$THEME_BIN" inst "the state mutant reports an unwired file as wired" "$cfg" "$rt_empty" 0 "ok hypr=wired path=$lua" "" hypr state
cp -- "$tmp/binds-own" "$tmp/dot-binds/binds.lua"
tree_control binds-outside bin/vgshell-hypr-judge 'if (!State.bindFileEditable(target, path.join(path.resolve(configHome), "hypr")) || ' 'if ('
INST_BIN="$THEME_BIN" inst "the unconfined mutant edits a file outside the hypr directory" "$tmp/cfg-binds" "$rt_empty" 0 "$any_out" "" hypr remove-bind "$tmp/outside.lua" 1 SUPER+F7
check "the unconfined mutant removes the outside line" test ! -s "$tmp/outside.lua"
unset THEME_BIN
# shellcheck disable=SC2016
tree_control edit-parent bin/vgshell '[[ $part != .. ]] || return 3' '[[ $part != .. ]] || return 0'
inst_env=(EDIT_RECORD="$tmp/edit-argv")
INST_BIN="$THEME_BIN" INST_PATH="$edit_dir:$base_path" inst "the edit parent mutant accepts a parent path" "$cfg" "$rt_empty" 0 "" "" edit hypr/../hypr/hyprland.lua
check "control: the edit parent mutant opens a path with a parent component" grep -qxF -- "$cfg/hypr/../hypr/hyprland.lua" "$tmp/edit-argv"
# shellcheck disable=SC2016
tree_control edit-line bin/vgshell 'editor_takes_line "${opener[0]}"' 'true'
inst_env=(EDITOR="$edit_dir/code --wait" EDIT_RECORD="$tmp/edit-argv")
INST_BIN="$THEME_BIN" INST_PATH="$edit_dir:$base_path" inst "the edit line mutant opens code with a line" "$cfg" "$rt_empty" 0 "" "" edit hypr/hyprland.lua 12
check "control: the edit line mutant gives +LINE to code" grep -qxF -- "+12" "$tmp/edit-argv"
unset INST_BIN INST_PATH THEME_BIN
# shellcheck disable=SC2034
inst_env=()

rows_done test-vgshell-hypr
