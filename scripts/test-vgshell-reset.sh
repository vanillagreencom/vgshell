#!/usr/bin/env bash
# Controls for `vgshell reset` and `vgshell reset restore`. Every row runs a
# copy of the tree (theme_tree) against a fixture home of its own under the
# suite's scratch root: HOME and every XDG directory the verbs read are set
# on each run and checked to lie under that root first, so no row reaches
# the developer's own files. The configuration directory is a symlink into
# a fixture dotfiles checkout, as on the owner's machine. The fixture fills
# every class of path VGS writes: the user layer, an installed theme
# package applied and then hand-edited, an installed plugin, the launcher,
# automations and backgrounds folders, the state files a run leaves (the
# applied theme, welcome-seen, migrations, the Hyprland layer, plugin
# state), data folders beside a curl install's own entries, and cache
# files. No shell runs, so every reset ends with shell=not-running. The
# PATH holds only the tools the verbs run, so the theme apply detects no
# application target and writes no file outside the fixture.
#
# A reset moves every path into one backup byte for byte and leaves the
# link, the theme lock and the install entries; a restore returns every
# file, the hand-edited theme file included, with only the backups folder
# new. `n` on a terminal and a run with neither a terminal nor a shell move
# nothing. The controls run copies of bin/vgshell with one rule changed and
# a row must fail against each.
set -euo pipefail

# shellcheck source=scripts/vgshell-rows.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"
command -v script >/dev/null || { echo "test-vgshell-reset: status=not-measured missing=script"; exit 77; }

theme_tree
bash_bin="$(command -v bash)"
for tool in date rmdir realpath cp head script; do
  tool_bin="$(command -v "$tool")" || { echo "test-vgshell-reset: status=not-measured missing=$tool"; exit 77; }
  ln -s -- "$tool_bin" "$theme_path/$tool"
done

# fixture NAME: a fresh home at $f, filled with every class of path, and
# its snapshot at $f/snap, taken before any verb under test runs. The
# planting apply runs the tree's own vgshell, never the copy under test.
fixture() { # NAME
  f="$tmp/fixtures/$1"
  home="$f/home"
  cfg="$home/.config/vgshell" st="$home/.local/state/vgshell" dat="$home/.local/share/vgshell" cch="$home/.cache/vgshell"
  dot="$home/dotfiles/vgshell/.config/vgshell"
  mkdir -p "$dot" "$home/.config" "$f/run"
  ln -s ../dotfiles/vgshell/.config/vgshell "$cfg"
  mkdir -p "$cfg/themes/moss" "$cfg/plugins/acme.probe" "$cfg/launcher" "$cfg/automations" "$cfg/backgrounds"
  doc moss >"$cfg/themes/moss/theme.json"
  run_in "$tree/bin/vgshell" theme apply moss >/dev/null 2>&1 || { echo "test-vgshell-reset: fixture=theme-apply status=$run_status" >&2; exit 1; }
  # A hand edit of the applied theme file, which restore keeps.
  printf '\n' >>"$cfg/theme.json"
  printf '{ "version": 1, "bar": { "layout": { "left": [{ "id": "acme.probe" }] } }, "disabledPlugins": ["vgs.launcher"] }\n' >"$cfg/shell.json"
  manifest acme.probe 0.1.0 >"$cfg/plugins/acme.probe/manifest.json"
  printf 'launcher\n' >"$cfg/launcher/pins.json"
  printf 'automation\n' >"$cfg/automations/night.json"
  printf 'image\n' >"$cfg/backgrounds/sea.png"
  mkdir -p "$st/migrations" "$st/hypr" "$st/plugins/acme.probe" "$st/notifications"
  : >"$st/welcome-seen"
  : >"$st/migrations/0001-fixture"
  printf 'hl.config({})\n' >"$st/hypr/vgs.lua"
  printf 'state\n' >"$st/plugins/acme.probe/state.json"
  printf 'notifications\n' >"$st/notifications/history.json"
  mkdir -p "$dat/automations" "$dat/jarvis" "$dat/0.1.0/bin" "$dat/git"
  printf 'data\n' >"$dat/automations/runs.json"
  printf 'jarvis\n' >"$dat/jarvis/memory.json"
  printf '0.1.0\n' >"$dat/0.1.0/VERSION"
  ln -s 0.1.0 "$dat/current"
  : >"$dat/.self.lock"
  mkdir -p "$cch/launcher" "$cch/theme-assets"
  printf 'history\n' >"$cch/launcher/history"
  printf 'asset\n' >"$cch/theme-assets/moss.tar.gz"
  mkdir -p "$f/snap"
  cp -a -- "$home" "$f/snap/home"
}

# run_in BIN ARGS...: BIN against the fixture's home with no terminal on
# stdin. Stdout lands in $tmp/out, stderr in $tmp/err, the status in
# run_status. Every directory the verbs act on is checked to lie under the
# suite's scratch root before BIN starts.
run_in() { # BIN ARGS...
  local bin="$1"
  shift
  fixture_contained || { echo "test-vgshell-reset: fixture=outside home=[$home]" >&2; exit 1; }
  run_status=0
  "${base_env[@]}" PATH="$theme_path" HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" \
    XDG_DATA_HOME="$home/.local/share" XDG_CACHE_HOME="$home/.cache" XDG_RUNTIME_DIR="$f/run" \
    "$bin" "$@" >"$tmp/out" 2>"$tmp/err" </dev/null || run_status=$?
}
# run_term BIN ANSWER ARGS...: as run_in, on a pseudo-terminal script(1)
# opens with ANSWER typed on it; stdout and stderr together land in
# $tmp/out. script(1) runs the command through SHELL, else the user's
# login shell, which would write its own files into the fixture home.
run_term() { # BIN ANSWER ARGS...
  local bin="$1" answer="$2"
  shift 2
  fixture_contained || { echo "test-vgshell-reset: fixture=outside home=[$home]" >&2; exit 1; }
  run_status=0
  "${base_env[@]}" PATH="$theme_path" HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" \
    XDG_DATA_HOME="$home/.local/share" XDG_CACHE_HOME="$home/.cache" XDG_RUNTIME_DIR="$f/run" SHELL="$bash_bin" \
    script -qec "$(printf '%q ' "$bin" "$@")" /dev/null <<<"$answer" >"$tmp/out" 2>&1 || run_status=$?
}
fixture_contained() {
  local dir
  for dir in "$home" "$home/.config" "$home/.local/state" "$home/.local/share" "$home/.cache" "$f/run"; do
    [[ $dir == "$tmp/fixtures/"* ]] || return 1
  done
  [[ $(realpath -m -- "$cfg") == "$tmp/fixtures/"* ]]
}

out_has() { tr -d '\r' <"$tmp/out" | grep -qxF -- "$1"; }
out_holds() { tr -d '\r' <"$tmp/out" | grep -qF -- "$1"; }
err_first() { local line=""; [[ -s $tmp/err ]] && IFS= read -r line <"$tmp/err"; [[ $line == "$1" ]]; }
# The folder a reset or restore line names: KEY's value on the line led
# by PREFIX.
out_value() { # PREFIX KEY
  tr -d '\r' <"$tmp/out" | sed -n "s|^$1.* $2=\\([^ ]*\\).*|\\1|p" | head -n 1
}
link_kept() { [[ -L $cfg && $(readlink -- "$cfg") == ../dotfiles/vgshell/.config/vgshell && -d $dot ]]; }
# Whether the fixture home is exactly as its snapshot holds it, the
# configuration read through the link in both.
unchanged() { diff -r -- "$f/snap/home" "$home" >/dev/null && link_kept; }
# names DIR: DIR's entries, sorted, one line, hidden ones included.
names() { local -a all=(); local n; shopt -s nullglob dotglob; all=("$1"/*); shopt -u nullglob dotglob; for n in "${all[@]}"; do printf '%s\n' "${n##*/}"; done | LC_ALL=C sort | tr '\n' ' '; }

# What reset moves out of the snapshot, by class: every entry but the ones
# the install and the lock own, stated here and not read from bin/vgshell.
snap_class() { # CLASS: the snapshot of CLASS's directory with the kept entries left out, at $f/want/CLASS
  local src
  case "$1" in
    config) src="$f/snap/home/dotfiles/vgshell/.config/vgshell" ;;
    state) src="$f/snap/home/.local/state/vgshell" ;;
    data) src="$f/snap/home/.local/share/vgshell" ;;
    cache) src="$f/snap/home/.cache/vgshell" ;;
  esac
  mkdir -p "$f/want"
  cp -a -- "$src" "$f/want/$1"
  case "$1" in
    config) rm -f -- "$f/want/config/theme.lock" ;;
    data) rm -rf -- "$f/want/data/current" "$f/want/data/0.1.0" "$f/want/data/git" "$f/want/data/.self.lock" ;;
  esac
}

row_reset_yes() {
  local bin="$1" backup class
  fixture reset-yes
  run_in "$bin" reset --yes
  [[ $run_status == 0 ]] && out_has "shell=not-running" || return 1
  backup="$(out_value "ok reset" backup)"
  [[ $backup =~ ^$dat/backups/[0-9]{8}T[0-9]{6}Z$ && -d $backup ]] || return 1
  # Every moved path, byte for byte, under its class.
  for class in config state data cache; do
    snap_class "$class"
    diff -r -- "$f/want/$class" "$backup/$class" >/dev/null 2>&1 || return 1
  done
  [[ $(names "$backup") == "cache config data state " ]] || return 1
  # The link stays a link, and the files the install and the lock own stay.
  link_kept || return 1
  [[ -e $cfg/theme.lock && -L $dat/current && -f $dat/0.1.0/VERSION && -d $dat/git && -e $dat/.self.lock ]] || return 1
  [[ $(names "$dat") == ".self.lock 0.1.0 backups current git " ]] || return 1
  # What a fresh install has, with the defaults applied.
  [[ $(names "$cfg") == "theme.json theme.lock " ]] || return 1
  cmp -s -- "$cfg/theme.json" "$tree/themes/vgs/theme.json" || return 1
  [[ $(head -n 1 -- "$st/theme.name") == vgs && ! -e $st/welcome-seen && ! -e $st/hypr ]] || return 1
  [[ ! -e $cch || -z $(names "$cch") ]] || return 1
  [[ $(cat -- "$st/reset-backup") == "$backup" ]]
}
row_restore_yes() {
  local bin="$1" backup aside
  fixture restore-yes
  run_in "$tree/bin/vgshell" reset --yes
  [[ $run_status == 0 ]] || return 1
  backup="$(out_value "ok reset" backup)"
  run_in "$bin" reset restore --yes
  [[ $run_status == 0 ]] && out_has "shell=not-running" || return 1
  [[ $(out_value "ok restored" backup) == "$backup" ]] || return 1
  aside="$(out_value "ok restored" aside)"
  [[ $aside == "$dat/backups/"* && -d $aside && ! -e $backup ]] || return 1
  # What the reset made moved aside, not deleted.
  [[ $(cat -- "$aside/state/reset-backup") == "$backup" && $(head -n 1 -- "$aside/state/theme.name") == vgs ]] || return 1
  # Every file back as the snapshot holds it, the hand-edited theme file
  # included; only the backups folder, which holds the aside, is new.
  diff -r -x backups -- "$f/snap/home" "$home" >/dev/null || return 1
  [[ $(names "$dat/backups") == "${aside##*/} " ]] || return 1
  link_kept
}
# A restore with no folder named takes the newest one.
row_restore_newest() {
  local bin="$1" first second
  fixture restore-newest
  run_in "$tree/bin/vgshell" reset --yes
  first="$(out_value "ok reset" backup)"
  printf 'second\n' >"$cfg/second.json"
  run_in "$tree/bin/vgshell" reset --yes
  second="$(out_value "ok reset" backup)"
  [[ $first != "$second" ]] || return 1
  run_in "$bin" reset restore --yes
  [[ $run_status == 0 && $(out_value "ok restored" backup) == "$second" && -f $cfg/second.json && -d $first ]]
}
row_declined() {
  local bin="$1"
  fixture declined
  run_term "$bin" n reset
  [[ $run_status == 1 ]] && out_holds "vgshell: reset VGS? [y/N] vgshell: refused: declined=reset" \
    && out_has "  $cfg/shell.json" && unchanged && [[ ! -e $dat/backups ]]
}
row_confirmed() {
  local bin="$1"
  fixture confirmed
  run_term "$bin" y reset
  [[ $run_status == 0 ]] && out_holds "vgshell: reset VGS? [y/N] ok reset backup=$dat/backups/" && [[ ! -e $cfg/shell.json ]] && link_kept
}
row_no_terminal() {
  local bin="$1"
  fixture no-terminal
  run_in "$bin" reset
  [[ $run_status == 1 ]] && err_first "vgshell: refused: no-terminal=reset" && unchanged && [[ ! -e $dat/backups ]]
}
row_restore_no_terminal() {
  local bin="$1" backup
  fixture restore-no-terminal
  run_in "$tree/bin/vgshell" reset --yes
  backup="$(out_value "ok reset" backup)"
  run_in "$bin" reset restore
  [[ $run_status == 1 ]] && err_first "vgshell: refused: no-terminal=restore" && [[ -d $backup && ! -e $cfg/shell.json ]]
}
row_restore_outside() {
  local bin="$1"
  fixture restore-outside
  mkdir -p "$f/elsewhere/config"
  run_in "$bin" reset restore --yes "$f/elsewhere"
  [[ $run_status == 1 ]] && err_first "vgshell: refused: backup=$f/elsewhere reason=outside" && unchanged
}
row_restore_none() {
  local bin="$1"
  fixture restore-none
  run_in "$bin" reset restore --yes
  [[ $run_status == 1 ]] && err_first "vgshell: refused: backup=none path=$dat/backups" && unchanged
}

# rows: label | function. Each runs against the vgshell it is handed.
declare -a ROWS=(
  "reset --yes moves every path into one backup and keeps the link, the lock and the install|row_reset_yes"
  "restore --yes returns every file and moves what the reset made aside|row_restore_yes"
  "restore without a folder takes the newest backup|row_restore_newest"
  "n on a terminal moves nothing|row_declined"
  "y on a terminal resets|row_confirmed"
  "no terminal, no --yes and no shell moves nothing|row_no_terminal"
  "restore without a terminal or --yes moves nothing|row_restore_no_terminal"
  "restore refuses a folder outside the backups|row_restore_outside"
  "restore refuses an empty backups folder|row_restore_none"
)
run_row() { "$1" "$2"; }
row_fns=" "
for row in "${ROWS[@]}"; do
  IFS='|' read -r name fn <<<"$row"
  row_fns+="$fn "
  if run_row "$fn" "$tree/bin/vgshell"; then ok "$name"; else fail "$name: exit=$run_status out=[$(tr -d '\r' <"$tmp/out" | tail -n 3)] err=[$(tail -n 3 -- "$tmp/err")]"; fi
  rm -rf -- "${tmp:?}/fixtures"
done

tinst "reset refuses an argument" "$tmp/cfg-usage" "$rt_empty" 2 "" "vgshell: refused: argument=x" reset x
tinst "reset restore refuses a second argument" "$tmp/cfg-usage" "$rt_empty" 2 "" "vgshell: refused: argument=y" reset restore x y

# controls: label, the text in bin/vgshell and its replacement, and the
# function of the row the rule serves, one control per four entries.
declare -a CONTROLS=(
  "the link stays a link" \
    '      mv -T -- "$dir/$entry" "$1/${reset_classes[i]}/$entry" || refuse 1 "move=failed path=$dir/$entry to=$1/${reset_classes[i]}"' \
    '      [[ -L $dir ]] && { rmdir -- "$1/${reset_classes[i]}"; mv -T -- "$dir" "$1/${reset_classes[i]}"; break; }; mv -T -- "$dir/$entry" "$1/${reset_classes[i]}/$entry"' \
    row_reset_yes
  "a terminal reset asks first" '  confirm_change reset VGS "nothing moved" reset' '' row_declined
  "state moves with the rest" '    config:theme.lock | data:backups' '    state:* | config:theme.lock | data:backups' row_reset_yes
  "the install's own entries stay" ' | data:current | ' ' | ' row_reset_yes
  "restore returns the cache" '    [[ -d $from ]] || continue' '    [[ -d $from && ${reset_classes[i]} != cache ]] || continue' row_restore_yes
  "restore puts the restored theme file back" '      mv -fT -- "$saved/$i" "${restore_kept[i]}" || refuse 1 "keep=failed path=${restore_kept[i]}"' '      :' row_restore_yes
  "restore takes the newest backup" '    set -- "${folders[-1]}"' '    set -- "${folders[0]}"' row_restore_newest
  "no terminal and no shell moves nothing" '    shell_pid >/dev/null 2>&1 ||' '    true ||' row_no_terminal
)
for ((i = 0; i < ${#CONTROLS[@]}; i += 4)); do
  label="${CONTROLS[i]}" fn="${CONTROLS[i + 3]}"
  [[ $row_fns == *" $fn "* ]] || { echo "test-vgshell-reset: control=$((i / 4)) row=unknown value=[$fn]" >&2; exit 1; }
  tree_control "reset-$((i / 4))" bin/vgshell "${CONTROLS[i + 1]}" "${CONTROLS[i + 2]}"
  vgshell_copy_loads "$THEME_BIN" || { echo "test-vgshell-reset: control=$((i / 4)) copy=does-not-load" >&2; exit 1; }
  if run_row "$fn" "$THEME_BIN"; then fail "control: $label: $fn passes without the rule"; else ok "control: $fn fails without the rule: $label"; fi
  rm -rf -- "${tmp:?}/fixtures"
  unset THEME_BIN
done

rows_done test-vgshell-reset
