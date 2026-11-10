#!/usr/bin/env bash
# The Home folder step's two setup choices, opened from the plugin's
# published snapshot once gum, node, git, python3 and kendex are found:
#
#   setup-home.sh new    makes the folder the Home folder setting names a new
#                        Jarvis home: kendex installs the Jarvis package in a
#                        folder of its own, then the package writes its
#                        starting files (D126). It refuses while Main Jarvis
#                        host names another computer, whose home the clone
#                        copies instead.
#   setup-home.sh clone  makes that folder a private clone of the main
#                        computer's home, whose place the user types, for
#                        this computer to forward to the Main Jarvis host
#
# backend/fleet-setup.js prints the steps (its plan verb), which the screen
# shows before the user confirms, then runs each in this terminal: git and
# kendex write here and git uses the user's SSH agent or asks here for an
# SSH passphrase, while kendex add runs with --yes and init's report is
# read, not shown. It reads the result back from the home. Every refusal
# prints its keyed line, `jarvis: fleet-setup=<key> ...`, and adds one to
# the Jarvis setup log; the screen ends with a plain sentence.
set -euo pipefail
source "$VGS_TUI_LIB"
log="${XDG_STATE_HOME:-$HOME/.local/state}/vgshell/jarvis/setup.log"
mode="${1:-}"
[[ $# == 1 && ( $mode == new || $mode == clone ) ]] ||
  vgs_tui_refuse "$log" 2 "jarvis: fleet-setup=arguments" \
    "Open Set up from the Home folder step on the Jarvis page in Settings." || exit
lib="$VGS_TUI_LIB"
tree="${lib%/bin/lib/tui.sh}"
[[ $tree != "$lib" && -n ${VGS_PLUGIN_ID:-} && -n ${VGS_PLUGIN_DIR:-} ]] ||
  vgs_tui_refuse "$log" 2 "jarvis: fleet-setup=tui=missing" \
    "Open Set up from the Home folder step on the Jarvis page in Settings." || exit
settings="$(vgs_tui_logged "$log" "$tree/bin/vgshell" plugin settings "$VGS_PLUGIN_ID")" ||
  vgs_tui_refuse "$log" 1 "jarvis: fleet-setup=settings-unreadable" \
    "VGS could not read the Jarvis settings." "Close this window and try again." || exit
# KEY of the settings, which must be text.
setting() {
  vgs_tui_logged "$log" node -e '
const value = JSON.parse(process.argv[1])[process.argv[2]];
if (typeof value !== "string") { process.stderr.write("jarvis: fleet-setup=setting key=" + process.argv[2] + "\n"); process.exit(1); }
process.stdout.write(value);
' "$settings" "$1"
}
home="$(setting home)" ||
  vgs_tui_refuse "$log" 1 "jarvis: fleet-setup=settings-unreadable" \
    "VGS could not read the Jarvis settings." "Close this window and try again." || exit
backend="$VGS_PLUGIN_DIR/backend/fleet-setup.js"
# Home.js judges the setting and the home, as Jarvis does.
folder="$(vgs_tui_logged "$log" node "$backend" --tree "$tree" folder "$home")" ||
  vgs_tui_refuse "$log" 1 "jarvis: fleet-setup=home-unchosen" \
    "Choose a new folder in Settings > Jarvis > Home folder, then try again." || exit
shown="${folder/#"$HOME"/\~}"

# Run VERB in this terminal; a failure keeps the worker's own line above.
run() { # VERB [ARG...]
  local status=0
  node "$backend" --tree "$tree" "$@" || status=$?
  (( status == 0 )) && return 0
  vgs_tui_note "$log" "jarvis: fleet-setup=$1-failed code=$status" || :
  return "$status"
}

main="$(setting mainHost)" ||
  vgs_tui_refuse "$log" 1 "jarvis: fleet-setup=settings-unreadable" \
    "VGS could not read the Jarvis settings." "Close this window and try again." || exit

# The steps fleet-setup.js runs, one command a line, shown as they run.
show_plan() { # ARG...
  local text steps=()
  text="$(vgs_tui_logged "$log" node "$backend" --tree "$tree" plan "$home" "$@")" ||
    vgs_tui_refuse "$log" 1 "jarvis: fleet-setup=plan-unreadable" \
      "VGS could not read the setup steps." "Close this window and try again." || return
  mapfile -t steps <<<"$text"
  vgs_tui_commands "${steps[@]}"
}

if [[ $mode == new ]]; then
  vgs_tui_header "Set up your Jarvis home" "kendex installs the Jarvis package in a folder of its own." \
    "The package then adds your instructions, memory index and state folder."
  [[ -z $main ]] ||
    vgs_tui_refuse "$log" 1 "jarvis: fleet-setup=main-host-set" \
      "This computer forwards to your main Jarvis, so its home is a copy of the main computer's home." \
      "Choose Use your Jarvis home from another computer in the Home folder step, or choose This computer in Settings > Jarvis > Main Jarvis host to set up a new home here." || exit
  if vgs_tui_logged "$log" node "$backend" --tree "$tree" ready "$home"; then
    vgs_tui_step "This Jarvis home is already set up"
    exit 0
  fi
  vgs_tui_text "Jarvis sets up $shown. It must be a new or empty folder outside any project."
  show_plan new || exit
  vgs_tui_confirm "Set up $shown as your Jarvis home?" || exit 130
  run setup "$home" "$main" || {
    vgs_tui_failed "$log" "VGS did not set up this folder. The reason is above." \
      "Choose a new folder in Settings > Jarvis > Home folder, or fix the reason, then try again."
    exit 1
  }
  vgs_tui_step "Jarvis home ready"
  vgs_tui_success "kendex keeps the Jarvis package in this folder up to date."
  exit 0
fi

vgs_tui_header "Use your Jarvis home from another computer" \
  "Jarvis copies your main computer's home here, so both computers share one memory." \
  "This computer then hands your requests to your main Jarvis."
[[ -n $main ]] ||
  vgs_tui_refuse "$log" 1 "jarvis: fleet-setup=main-host-unset" \
    "Choose your main computer in Settings > Jarvis > Main Jarvis host, then try again." || exit
source_place="$(vgs_tui_input --header "Where the home is on your main computer, as git clone takes it" \
  --placeholder "for example $main:Jarvis")" || exit 130
[[ -n $source_place ]] || exit 130
vgs_tui_text "Jarvis copies the home at $source_place into $shown, which must be a new or empty folder."
show_plan clone "$source_place" "$main" || exit
vgs_tui_confirm "Copy your Jarvis home into $shown?" || exit 130
status=0
run clone "$home" "$source_place" "$main" || status=$?
# fleet-setup.js exits 3 for credentials-committed, once it removed the copy.
if (( status == 3 )); then
  vgs_tui_failed "$log" "Your main Jarvis home's Git history holds its private env file, .env.local, with your keys and passwords." \
    "VGS kept nothing of it on this computer. Remove the file from the main home's history, then try again."
  exit 1
elif (( status != 0 )); then
  vgs_tui_failed "$log" "VGS did not copy your Jarvis home. The reason is above." \
    "Fix the reason or choose a new folder in Settings > Jarvis > Home folder, then try again."
  exit 1
fi
vgs_tui_step "Jarvis home ready on this computer"
vgs_tui_success "Your keys and passwords stay on your main computer. To use one here, ask your main Jarvis to move it with its secret transfer."
