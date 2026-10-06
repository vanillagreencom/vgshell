#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"

config_file="${XDG_CONFIG_HOME:-$HOME/.config}/voxtype/config.toml"
vgs_tui_header "Configure Voice" "Change voxtype options in its setup screen."
# The core opens this script only once voxtype is found; a run from
# elsewhere without it stops here, before anything changes.
if ! command -v voxtype >/dev/null; then
  printf 'vgs-voice: refused: voxtype=missing\n' >&2
  vgs_tui_error "Voice needs voxtype. Press Set up in Voice settings to install it."
  exit 1
fi
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
