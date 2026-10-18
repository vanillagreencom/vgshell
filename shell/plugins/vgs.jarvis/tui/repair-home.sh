#!/usr/bin/env bash
# The Home step keeps package ownership with Kendex or the VGS install.
set -euo pipefail
source "$VGS_TUI_LIB"
log="${XDG_STATE_HOME:-$HOME/.local/state}/vgshell/jarvis/setup.log"
lib="$VGS_TUI_LIB"
tree="${lib%/bin/lib/tui.sh}"
[[ $# == 0 && $tree != "$lib" && -n ${VGS_PLUGIN_ID:-} && -n ${VGS_PLUGIN_DIR:-} ]] ||
  vgs_tui_refuse "$log" 2 "jarvis: home-repair=arguments" \
    "Open Repair from the Home folder step in Jarvis Settings." || exit
vgs_tui_header "Repair the Home folder" "The package owner restores the Jarvis files."
settings="$(vgs_tui_logged "$log" "$tree/bin/vgshell" plugin settings "$VGS_PLUGIN_ID")" ||
  vgs_tui_refuse "$log" 1 "jarvis: home-repair=settings-unreadable" "VGS could not read the Jarvis settings." || exit
setting="$(vgs_tui_logged "$log" node -e '
const home = JSON.parse(process.argv[1]).home;
if (typeof home !== "string") process.exit(1);
process.stdout.write(home);
' "$settings")" ||
  vgs_tui_refuse "$log" 1 "jarvis: home-repair=settings-unreadable" "VGS could not read the Home folder setting." || exit
# Keep all terminal streams connected. Kendex owns its edit questions.
node "$VGS_PLUGIN_DIR/backend/fleet-setup.js" --tree "$tree" repair "$setting"
