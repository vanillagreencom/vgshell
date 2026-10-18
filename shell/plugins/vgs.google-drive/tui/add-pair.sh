#!/usr/bin/env bash
# The vgs.google-drive `add-pair` floating TUI: asks for a folder pair's
# name, Google Drive folder and folder on this computer, and
# hands it to the runner's `pair-add`, which judges it and, for the first
# pair, installs the hourly sync. Keyed lines go to the Google Drive setup
# log; the screen shows a plain sentence.
#
#   add-pair.sh
set -euo pipefail
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"
log="${XDG_STATE_HOME:-$HOME/.local/state}/vgshell/google-drive/setup.log"
runner="$VGS_PLUGIN_DIR/bin/google-drive"
mkdir -p -- "${log%/*}"
[[ $# == 0 ]] || vgs_tui_refuse "$log" 2 "google-drive: refused: arguments=none" "Open Add a folder pair from the Google Drive page in Settings." || exit

# A JSON string of $1: a backslash and a quote escaped. A control
# character stays, and the runner refuses the definition.
json_string() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; printf '"%s"' "$s"; }
# The pair's id from its name: lower case letters and digits, each other
# run as one dash, at most 32 characters (the runner's id rule).
pair_id() {
  local s="${1,,}"
  s="${s//[^abcdefghijklmnopqrstuvwxyz0123456789]/-}"
  while [[ $s == *--* ]]; do s="${s//--/-}"; done
  s="${s#-}"
  s="${s:0:32}"
  s="${s%-}"
  printf '%s' "${s:-pair}"
}

vgs_tui_header "Add a folder pair" "VGS copies a Google Drive folder and a folder on this computer both ways." \
  "Newer files win. It never deletes a file."
label="$(vgs_tui_input --header "A name for this folder pair. The bar shows it." --placeholder "for example Documents")" || exit 130
[[ -n $label ]] || exit 130
remote="$(vgs_tui_input --header "The Google Drive folder, from the top of your Drive." --placeholder "for example Documents/Taxes")" || exit 130
[[ -n $remote ]] || exit 130
local_dir="$(vgs_tui_input --header "The folder on this computer, as a full path." --value "$HOME/")" || exit 130
[[ -n $local_dir ]] || exit 130
remote="${remote#/}"
remote="${remote%/}"
local_dir="${local_dir%/}"
definition="{\"id\":$(json_string "$(pair_id "$label")"),\"label\":$(json_string "$label"),\"remote\":$(json_string "$remote"),\"local\":$(json_string "$local_dir")}"
logged="$(stat -c %s -- "$log" 2>/dev/null)" || logged=0
answer=""
if answer="$(vgs_tui_logged "$log" "$runner" pair-add --definition "$definition")"; then
  printf '%s\n' "$answer" >>"$log"
  # The pair stands; the runner could not install the hourly sync.
  if [[ $'\n'"$answer" == *$'\n'install=failed* ]]; then
    vgs_tui_success "VGS added $label."
    vgs_tui_failed "$log" "VGS could not set up the hourly sync. Select Set up again beside Hourly sync on the Google Drive page in Settings."
    exit 1
  fi
  vgs_tui_success "VGS added $label. It syncs both ways at the next hourly run, or when you select Sync now."
  exit 0
fi
# The refusal this run logged, not an earlier run's.
refusal="$(tail -c "+$((logged + 1))" -- "$log" | grep '^google-drive: refused: ' | tail -n 1)" || refusal=""
case "$refusal" in
  *pairs=invalid*) sentence="The folder pair list is not valid. Select Start the folder pair list again on the Google Drive page in Settings." ;;
  *rule=home-or-above*) sentence="Choose a folder inside your home folder, not your home folder itself." ;;
  *rule=repository-root*) sentence="Choose a folder that is not a Git repository." ;;
  *rule=repository-inside*) sentence="Choose a folder that holds no Git repository." ;;
  *rule=vgs-overlap* | *rule=unit-overlap*) sentence="Choose a folder outside the folders that hold VGS and your system services." ;;
  *rule=drive-root*) sentence="Choose a Google Drive folder, not the whole Drive." ;;
  *rule=local-overlap* | *rule=remote-overlap*) sentence="This folder overlaps a folder of another folder pair." ;;
  *rule=state-overlap*) sentence="Choose a folder outside the folder where VGS keeps its Google Drive records." ;;
  *rule=remote) sentence="Enter the Google Drive folder as a path, such as Documents/Taxes." ;;
  *rule=local) sentence="Enter the folder on this computer as a full path, such as $HOME/Documents." ;;
  *rule=duplicate-id*) sentence="A folder pair with this name exists. Choose another name." ;;
  *rule=label*) sentence="Enter a name of 1 to 64 characters." ;;
  *) sentence="VGS could not add the folder pair." ;;
esac
vgs_tui_failed "$log" "$sentence"
exit 1
