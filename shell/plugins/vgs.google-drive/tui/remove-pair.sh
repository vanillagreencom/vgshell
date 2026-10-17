#!/usr/bin/env bash
# The vgs.google-drive `remove-pair` floating TUI: removes the folder pair
# ID names, or the one the user selects from the list, after a yes, through
# the runner's `pair-remove`, which deletes no file. An ID the runner does
# not list is refused. Keyed lines go to the Google Drive setup log; the
# screen shows a plain sentence.
#
#   remove-pair.sh [ID]
set -euo pipefail
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"
log="${XDG_STATE_HOME:-$HOME/.local/state}/vgshell/google-drive/setup.log"
runner="$VGS_PLUGIN_DIR/bin/google-drive"
mkdir -p -- "${log%/*}"
[[ $# -le 1 ]] || vgs_tui_refuse "$log" 2 "google-drive: refused: arguments=at-most-one" "Open Remove a folder pair from the Google Drive page in Settings." || exit
vgs_tui_header "Remove a folder pair" "VGS stops syncing the folder pair. Its files stay on this computer and on Google Drive."
pairs="$(vgs_tui_logged "$log" "$runner" pairs --lines)" ||
  { vgs_tui_failed "$log" "VGS could not read the folder pairs."; exit 1; }
# Each line is `<id>\t<label>`.
if [[ $# == 1 ]]; then
  id="$1" label=""
  while IFS=$'\t' read -r listed name; do [[ $listed != "$id" ]] || label="$name"; done <<<"$pairs"
  [[ -n $label ]] || vgs_tui_refuse "$log" 1 "google-drive: refused: pair=unknown id=${id//[^abcdefghijklmnopqrstuvwxyz0123456789-]/?}" "This folder pair no longer exists." || exit
  vgs_tui_step "$label"
else
  if [[ -z $pairs ]]; then
    vgs_tui_step "There are no folder pairs."
    exit 0
  fi
  # gum shows the label and prints the id.
  choices=""
  while IFS=$'\t' read -r listed name; do choices+="$name"$'\t'"$listed"$'\n'; done <<<"$pairs"
  id="$(vgs_tui_choose --label-delimiter=$'\t' --header "Select the folder pair to remove." <<<"${choices%$'\n'}")" || exit 130
  [[ -n $id ]] || exit 130
fi
status=0
vgs_tui_confirm "Remove this folder pair? Its files stay." || status=$?
case "$status" in
  0) ;;
  1) exit 0 ;;
  *) exit "$status" ;;
esac
vgs_tui_logged "$log" "$runner" pair-remove "$id" >>"$log" ||
  { vgs_tui_failed "$log" "VGS could not remove the folder pair."; exit 1; }
vgs_tui_success "VGS no longer syncs this folder pair. Its files stay."
