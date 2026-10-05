#!/usr/bin/env bash
# Controls for vgs.greeter's helpers: bin/copy-theme, which keeps the
# login screen's copy of the applied theme, and bin/sessions, which lists
# the session files and looks commands up. Every row runs a helper over a
# tree under the suite's scratch directory and nothing else. Each control
# runs the rows against a copy of one helper missing one rule, and the
# rows must fail.
set -euo pipefail

# shellcheck source=scripts/vgshell-rows.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"
suite=test-greeter-helpers
plugin="$repo/shell/plugins/vgs.greeter"
why="$tmp/why"

# A PATH with every command copy-theme runs but readlink.
no_readlink="$tmp/no-readlink"; mkdir -p "$no_readlink"
for tool in bash sha256sum mktemp install mv rm mkdir; do
  found="$(command -v "$tool")" || { echo "$suite: status=not-measured missing=$tool"; exit 77; }
  ln -s -- "$found" "$no_readlink/$tool"
done

# copy-theme's world: a theme file, a background link and the step's
# directory, fresh for each row.
c="$tmp/copy"
copy_world() {
  rm -rf -- "${c:?}"
  mkdir -p "$c/config/vgshell" "$c/state/vgshell" "$c/images" "$c/dest"
  printf '{"schemaVersion":1}\n' >"$c/config/vgshell/theme.json"
  printf 'image one' >"$c/images/one.png"
  ln -s "$c/images/one.png" "$c/state/vgshell/background"
}
copy_run() { # HELPER [PATH]: copy-theme's stdout in $tmp/out, stderr in $tmp/err, exit in $status
  status=0
  env -i PATH="${2:-$base_path}" bash "$1" "$c/config/vgshell/theme.json" "$c/state/vgshell/background" "$c/dest" >"$tmp/out" 2>"$tmp/err" || status=$?
}
out_is() { [[ "$(cat -- "$tmp/out")" == "$1" ]] || { printf 'out=[%s] want=[%s] err=[%s]\n' "$(cat -- "$tmp/out")" "$1" "$(cat -- "$tmp/err")" >"$why"; return 1; }; }
first_err_is() { [[ "$(head -n 1 -- "$tmp/err")" == "$1" ]] || { printf 'err=[%s] want=[%s]\n' "$(cat -- "$tmp/err")" "$1" >"$why"; return 1; }; }
inode() { stat -c %i -- "$1"; }

row_copy_first() {
  copy_world; copy_run "$1"
  [[ $status == 0 ]] && out_is "theme=copied background=copied" || return 1
  cmp -s -- "$c/config/vgshell/theme.json" "$c/dest/vgshell/theme.json" && cmp -s -- "$c/images/one.png" "$c/dest/vgshell/background"
}
row_copy_mode() {
  copy_world; copy_run "$1"
  [[ "$(stat -c %a -- "$c/dest/vgshell/theme.json") $(stat -c %a -- "$c/dest/vgshell/background")" == "644 644" ]]
}
row_copy_unchanged() {
  local before
  copy_world; copy_run "$1"; before="$(inode "$c/dest/vgshell/theme.json")"
  copy_run "$1"
  [[ $status == 0 ]] && out_is "theme=unchanged background=unchanged" && [[ $(inode "$c/dest/vgshell/theme.json") == "$before" ]]
}
row_copy_renamed() {
  local before
  copy_world; copy_run "$1"; before="$(inode "$c/dest/vgshell/theme.json")"
  printf '{"schemaVersion":1,"name":"b"}\n' >"$c/config/vgshell/theme.json"
  copy_run "$1"
  [[ $status == 0 ]] && out_is "theme=copied background=unchanged" && cmp -s -- "$c/config/vgshell/theme.json" "$c/dest/vgshell/theme.json" \
    && [[ $(inode "$c/dest/vgshell/theme.json") != "$before" && "$(ls -A -- "$c/dest/vgshell" | tr '\n' ' ')" == "background theme.json " ]]
}
row_copy_removed() {
  copy_world; copy_run "$1"
  rm -f -- "$c/state/vgshell/background" "$c/config/vgshell/theme.json"
  copy_run "$1"
  [[ $status == 0 ]] && out_is "theme=removed background=removed" && [[ ! -e $c/dest/vgshell/background && ! -e $c/dest/vgshell/theme.json ]]
}
row_copy_dangling() {
  copy_world; copy_run "$1"
  rm -f -- "$c/images/one.png"
  copy_run "$1"
  [[ $status == 0 ]] && out_is "theme=unchanged background=removed"
}
row_copy_symlink() {
  copy_world; mkdir -p "$c/dest/vgshell"; ln -s "$c/elsewhere" "$c/dest/vgshell/theme.json"
  copy_run "$1"
  [[ $status == 1 ]] && first_err_is "copy-theme: refused: dest=symlink path=$c/dest/vgshell/theme.json" && [[ ! -e $c/elsewhere ]]
}
row_copy_no_dest() {
  copy_world; rmdir -- "$c/dest"
  copy_run "$1"
  [[ $status == 1 ]] && first_err_is "copy-theme: refused: dest=missing path=$c/dest"
}
row_copy_unresolved() {
  copy_world; copy_run "$1"
  copy_run "$1" "$no_readlink"
  [[ $status == 1 ]] && first_err_is "copy-theme: refused: background=unresolved path=$c/state/vgshell/background" && [[ -e $c/dest/vgshell/background ]]
}

# sessions' world: two data directories, the first with a file the second
# shadows by name.
s="$tmp/share"
sessions_world() {
  rm -rf -- "${s:?}"
  mkdir -p "$s/one/wayland-sessions" "$s/one/xsessions" "$s/two/wayland-sessions"
  printf '[Desktop Entry]\nName=A\nExec=a' >"$s/one/wayland-sessions/a.desktop"
  printf '[Desktop Entry]\nName=X\n' >"$s/one/xsessions/x.desktop"
  printf 'not a session\n' >"$s/one/wayland-sessions/readme.txt"
  printf '[Desktop Entry]\nName=B\n' >"$s/two/wayland-sessions/b.desktop"
}
sessions_run() { # HELPER ARGS...: stdout in $tmp/out, stderr in $tmp/err, exit in $status
  local h="$1"; shift
  status=0
  env -i PATH="$base_path" bash "$h" "$@" >"$tmp/out" 2>"$tmp/err" || status=$?
}
row_sessions_list() {
  sessions_world; sessions_run "$1" list "$s/one" "$s/missing" "$s/two"
  [[ $status == 0 ]] && out_is "$(printf '%s\n' \
    "@ wayland-sessions $s/one/wayland-sessions/a.desktop" '|[Desktop Entry]' '|Name=A' '|Exec=a' \
    "@ xsessions $s/one/xsessions/x.desktop" '|[Desktop Entry]' '|Name=X' \
    "@ wayland-sessions $s/two/wayland-sessions/b.desktop" '|[Desktop Entry]' '|Name=B')"
}
row_sessions_newline_name() {
  sessions_world; printf '[Desktop Entry]\n' >"$s/two/wayland-sessions/odd"$'\n'"name.desktop"
  sessions_run "$1" list "$s/two"
  [[ $status == 0 ]] && out_is "$(printf '%s\n' "@ wayland-sessions $s/two/wayland-sessions/b.desktop" '|[Desktop Entry]' '|Name=B')"
}
row_sessions_unreadable() {
  sessions_world; chmod 0000 "$s/two/wayland-sessions/b.desktop"
  sessions_run "$1" list "$s/two"
  chmod 0644 "$s/two/wayland-sessions/b.desktop"
  [[ $status == 1 ]] && first_err_is "sessions: refused: unreadable path=$s/two/wayland-sessions/b.desktop"
}
row_sessions_relative() {
  sessions_run "$1" list share
  [[ $status == 2 ]] && first_err_is "sessions: refused: dir=share"
}
row_sessions_which() {
  sessions_run "$1" which bash vgs-no-such-command "$(command -v bash)"
  [[ $status == 0 ]] && out_is "$(printf '%s\n' "found bash" "missing vgs-no-such-command" "found $(command -v bash)")"
}

# rows: label | function | helper.
declare -a ROWS=(
  "copy-theme copies the theme and the background the link names|row_copy_first|copy-theme"
  "copy-theme makes each copy readable by the greeter account|row_copy_mode|copy-theme"
  "copy-theme leaves bytes that did not change alone|row_copy_unchanged|copy-theme"
  "copy-theme renames a changed copy into place and leaves no temporary file|row_copy_renamed|copy-theme"
  "copy-theme removes the copy of a source that is gone|row_copy_removed|copy-theme"
  "copy-theme reads a link to nothing as no background|row_copy_dangling|copy-theme"
  "copy-theme refuses a symbolic link at a copy|row_copy_symlink|copy-theme"
  "copy-theme refuses a directory the step did not make|row_copy_no_dest|copy-theme"
  "copy-theme refuses a link it cannot resolve and keeps the copy|row_copy_unresolved|copy-theme"
  "sessions lists each session file in directory order, every line led by a bar, the last without a newline too|row_sessions_list|sessions"
  "sessions skips a file whose name holds a newline|row_sessions_newline_name|sessions"
  "sessions refuses a file it cannot read|row_sessions_unreadable|sessions"
  "sessions refuses a relative directory|row_sessions_relative|sessions"
  "sessions which finds a command on PATH and by its path|row_sessions_which|sessions"
)
# run_rows HELPER_DIR QUIET: every row against the helpers in HELPER_DIR;
# prints ok/FAIL lines unless QUIET and returns the number that failed.
run_rows() {
  local dir="$1" quiet="$2" row name fn helper red=0
  for row in "${ROWS[@]}"; do
    IFS='|' read -r name fn helper <<<"$row"
    rm -f -- "$why"
    if "$fn" "$dir/$helper"; then
      [[ $quiet == quiet ]] || ok "$name"
    else
      red=$((red + 1))
      [[ $quiet == quiet ]] || fail "$name: exit=${status:-} $(cat -- "$why" 2>/dev/null || true)"
    fi
  done
  return "$red"
}
run_rows "$plugin/bin" loud || true

# controls: label, the helper, its text and the replacement, four entries
# each. The copy replaces that helper in a directory of its own.
declare -a CONTROLS=(
  "an unchanged source is not copied again" copy-theme '  if [[ -f $target ]] && [[ $(sum_of "$1") == "$(sum_of "$target")" ]]; then did=unchanged; return; fi' ''
  "a copy is renamed into place" copy-theme '  mv -fT -- "$staged" "$target" || refuse 1 "rename=failed path=$target"' '  cat -- "$staged" >"$target" || refuse 1 "rename=failed path=$target"'
  "a copy is mode 0644" copy-theme '  install -m 0644 -T -- "$1" "$staged"' '  install -m 0600 -T -- "$1" "$staged"'
  "a source that is gone removes its copy" copy-theme '      rm -f -- "$target" || refuse 1 "remove=failed path=$target"' '      :'
  "a symbolic link at a copy is refused" copy-theme '  [[ ! -L $target ]] || refuse 1 "dest=symlink path=$target"' '  :'
  "a link that cannot be resolved is refused" copy-theme '|| refuse 1 "background=unresolved path=$link"' '|| image=""'
  "the last line without a newline is listed" sessions 'while IFS= read -r line || [[ -n $line ]]; do' 'while IFS= read -r line; do'
  "an unreadable file is refused" sessions 'refuse 1 "unreadable path=$file"' 'true'
  "a name with a newline is skipped" sessions "[[ -f \$file && \$file != *\$'\\n'* ]] || continue" '[[ -f $file ]] || continue'
  "which answers what command -v finds" sessions '    if command -v -- "$name" >/dev/null; then' '    if true; then'
)
for ((i = 0; i < ${#CONTROLS[@]}; i += 4)); do
  label="${CONTROLS[i]}" helper="${CONTROLS[i + 1]}"
  copy_with "control-$((i / 4))" "$plugin/bin/$helper" "${CONTROLS[i + 2]}" "${CONTROLS[i + 3]}"
  dir="$tmp/helpers-$((i / 4))"; mkdir -p "$dir"
  cp -- "$plugin/bin/copy-theme" "$plugin/bin/sessions" "$dir/"
  cp -- "$copy" "$dir/$helper"
  if run_rows "$dir" quiet; then fail "control: $label: the rows pass without the rule"; else ok "control: the rows fail without the rule: $label"; fi
done

rows_done "$suite"
