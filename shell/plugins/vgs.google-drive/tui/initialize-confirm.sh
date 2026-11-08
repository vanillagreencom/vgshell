#!/usr/bin/env bash
# Private confirmation phase of initialize, invoked by the snapshot runner
# while it owns the pair lock. Never an unattended initialization.
set -euo pipefail
[[ $# == 0 && -n ${VGS_TUI_LIB:-} ]] || exit 2
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"
unset VGS_TUI_UNATTENDED
vgs_tui_confirm "Have you settled all earlier removals and native exports, and paused other writers? Initialize these equal folders?" --default=false
