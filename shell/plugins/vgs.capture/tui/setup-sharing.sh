#!/usr/bin/env bash
# Explicit Settings action. A service probe must never run this write/restart.
set -euo pipefail
source "$VGS_TUI_LIB"
[[ $# == 0 ]] || exit 2
lib="$VGS_TUI_LIB"
tree="${lib%/bin/lib/tui.sh}"
[[ $tree != "$lib" && -n ${VGS_PLUGIN_ID:-} ]] || exit 2
vgs_tui_lock capture-sharing
vgs_tui_header "Set up screen sharing" "Applies the VGS picker to screen sharing requests."
vgs_tui_warn "A running screen share stops when setup applies the picker."
vgs_tui_confirm "Apply the VGS picker?" || exit 130
if "$tree/bin/vgshell-share-picker" --configure; then
  vgs_tui_step "The VGS screen sharing picker is ready."
else
  result=$?
  if [[ $result == 75 ]]; then
    vgs_tui_warn "Setup could not apply the picker to the running portal. The picker takes effect at the next portal start."
  else
    vgs_tui_error "Screen sharing setup failed. Open Capture settings to try again."
  fi
  exit "$result"
fi
