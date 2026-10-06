#!/usr/bin/env bash
set -Eeuo pipefail
refuse() { printf 'screensaver-art: refused: %s\n' "$1" >&2; exit "${2:-1}"; }
[[ -n ${VGS_TUI_LIB:-} ]] || refuse "tui=missing" 2
# shellcheck source=SCRIPTDIR/../../../../bin/lib/tui.sh
source "$VGS_TUI_LIB"
trap 'status=$?; [[ $status == 0 ]] || vgs_tui_close_prompt "$status"' EXIT
plugin_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/vgshell"
art="$config_dir/screensaver.txt"
mkdir -p -- "$config_dir"
choice="$(gum choose "From image" "Edit text" "Reset")" || exit $?
case "$choice" in
  "From image")
    while :; do
      image="$(gum file "$HOME")" || exit $?
      case "${image,,}" in
        *.png|*.svg) break ;;
        *) gum style --foreground 1 "Choose a PNG or SVG image." ;;
      esac
    done
    "$plugin_dir/bin/transcode-ascii" "$image" "$art"
    ;;
  "Edit text")
    [[ -f $art ]] || cp -- "$plugin_dir/logo.txt" "$art"
    [[ -n ${EDITOR:-} ]] || refuse "editor=missing" 1
    read -r -a editor <<<"$EDITOR"
    "${editor[@]}" "$art"
    ;;
  "Reset") cp -- "$plugin_dir/logo.txt" "$art" ;;
  *) refuse "choice=unknown" 2 ;;
esac
