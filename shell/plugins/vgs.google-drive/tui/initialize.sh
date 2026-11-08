#!/usr/bin/env bash
# initialize.sh [PAIR-ID]: the declared two-way initialization TUI.
# The runner owns comparison, preview, confirmation and the inherited pair
# lock. This script only selects a listed pair and opens that operation.
set -euo pipefail
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"
log="${XDG_STATE_HOME:-$HOME/.local/state}/vgshell/google-drive/setup.log"
runner="$VGS_PLUGIN_DIR/bin/google-drive"
mkdir -p -- "${log%/*}"
[[ $# -le 1 ]] || vgs_tui_refuse "$log" 2 "google-drive: refused: arguments=pair-id" "Open Initialize two-way sync from Google Drive Setup." || exit
vgs_tui_header "Initialize two-way sync" \
  "Settle earlier removals, moves and native-document copies with Jarvis first." \
  "Keep other computers and apps from changing these folders while you check them. This action keeps the pair's pause."
pairs="$(vgs_tui_logged "$log" "$runner" pairs --lines)" ||
  { vgs_tui_failed "$log" "VGS could not read the folder pairs."; exit 1; }
ids=()
labels=()
while IFS=$'\t' read -r id label; do
  [[ -n $id ]] || continue
  ids+=("$id")
  labels+=("$label ($id)")
done <<<"$pairs"
[[ ${#ids[@]} -gt 0 ]] ||
  vgs_tui_refuse "$log" 1 "google-drive: refused: pairs=empty" "Add a folder pair first." || exit
selected="${1:-}"
if [[ -z $selected ]]; then
  chosen="$(vgs_tui_choose -- "${labels[@]}")" || exit 130
  for index in "${!labels[@]}"; do [[ ${labels[index]} != "$chosen" ]] || selected="${ids[index]}"; done
fi
found=false
for id in "${ids[@]}"; do [[ $id != "$selected" ]] || found=true; done
[[ $found == true ]] ||
  vgs_tui_refuse "$log" 1 "google-drive: refused: pair=unknown" "This folder pair no longer exists." || exit
# Keep stdout on the terminal: the runner shows roots and old evidence;
# rclone's preview goes to the visible terminal.
vgs_tui_step "VGS compares both folders and shows a preview. No is selected until you confirm."
if "$runner" initialize --pair "$selected"; then
  vgs_tui_success "The initialization action ended. A canceled action changes no synced file."
  exit 0
fi
vgs_tui_failed "$log" "VGS could not initialize this pair. Check the comparison above. Settle any differences or missing access files, then try again."
exit 1
