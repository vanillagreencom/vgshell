#!/usr/bin/env bash
# Google consent for the stored client keys' OAuth client: the runner's `authorize`
# opens Google's page in the browser through rclone and stores the token it
# returns in the keyring. The token never reaches this script, the screen or
# the log. Keyed lines go to the Google Drive setup log; the screen shows a
# plain sentence.
set -euo pipefail
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"
log="${XDG_STATE_HOME:-$HOME/.local/state}/vgshell/google-drive/setup.log"
runner="$VGS_PLUGIN_DIR/bin/google-drive"
mkdir -p -- "${log%/*}"
[[ $# == 0 ]] || vgs_tui_refuse "$log" 2 "google-drive: refused: arguments=none" "Select Sign in to Google on the Google Drive page in Settings." || exit
vgs_tui_header "Sign in to Google" "VGS copies your folder pairs both ways and never deletes a file." \
  "Signing in lets VGS read and change files in your Google Drive." \
  "The sign-in stays in your desktop keyring. VGS does not show it."
vgs_tui_step "Google opens in your browser. Come back here when the browser says that you can close it."
logged="$(stat -c %s -- "$log" 2>/dev/null)" || logged=0
if vgs_tui_logged "$log" "$runner" authorize >>"$log"; then
  vgs_tui_success "You are signed in to Google."
  exit 0
fi
refusal="$(tail -c "+$((logged + 1))" -- "$log" | grep '^google-drive: refused: ' | tail -n 1)" || refusal=""
case "$refusal" in
  *"credential=absent account=client-"*) vgs_tui_failed "$log" "Add the client ID and the client secret on the Google Drive page in Settings first." ;;
  *credential=locked*) vgs_tui_failed "$log" "Your keyring is locked. Unlock it, then try again." ;;
  *authorize=no-token*) vgs_tui_failed "$log" "Google did not finish the sign-in. Try again, and allow access in the browser." ;;
  *) vgs_tui_failed "$log" "VGS could not sign you in to Google." ;;
esac
exit 1
