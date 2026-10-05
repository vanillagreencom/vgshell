#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"

config_file="${XDG_CONFIG_HOME:-$HOME/.config}/voxtype/config.toml"
vgs_tui_header "Configure Voice" "Change voxtype options in its setup screen."
if [[ -L $config_file ]]; then
  vgs_tui_warn "Your voxtype config is a symlink. The configure screen can replace it."
  status=0
  vgs_tui_confirm "Continue?" || status=$?
  case "$status" in
    0) ;;
    1) exit 0 ;;
    *) exit "$status" ;;
  esac
fi
vgs_tui_step "Opening Voice configuration"
voxtype configure
systemctl --user restart voxtype
