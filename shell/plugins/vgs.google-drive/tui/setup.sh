#!/usr/bin/env bash
# The vgs.google-drive `setup` floating TUI: installs the hourly user timer
# and the service that the plugin's Sync now and the command line start,
# through the runner's `install`. The first folder pair installs them;
# this is Set up again, for units that are out of date or that an install
# could not finish. Keyed lines go to the Google Drive setup log; the
# screen shows a plain sentence.
#
#   setup.sh
set -euo pipefail
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"
log="${XDG_STATE_HOME:-$HOME/.local/state}/vgshell/google-drive/setup.log"
runner="$VGS_PLUGIN_DIR/bin/google-drive"
mkdir -p -- "${log%/*}"
[[ $# == 0 ]] || vgs_tui_refuse "$log" 2 "google-drive: refused: arguments=none" "Select Set up again beside Hourly sync on the Google Drive page in Settings." || exit
vgs_tui_header "Set up hourly sync again" "Google Drive syncs every hour while you are logged in, also while VGS is closed."
vgs_tui_logged "$log" "$runner" install >>"$log" ||
  { vgs_tui_failed "$log" "VGS could not set up the hourly sync."; exit 1; }
vgs_tui_success "Google Drive syncs every hour while you are logged in."
