#!/usr/bin/env bash
# Private confirmation phase of initialize, invoked by the snapshot runner
# while it owns the pair lock. Never an unattended initialization.
set -euo pipefail
[[ $# == 0 && -n ${VGS_TUI_LIB:-} ]] || exit 2
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"
unset VGS_TUI_UNATTENDED
# The outer TUI logs runner diagnostics. Its visible stdout remains the
# terminal; give gum that terminal for its prompt on stderr as well.
if [[ -t 1 ]]; then exec 2>&1; fi
vgs_tui_confirm "Have you reviewed the preview and paused other writers? Create the listed access files, move the listed download copies, and start two-way sync?" --default=false
