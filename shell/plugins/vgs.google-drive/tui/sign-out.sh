#!/usr/bin/env bash
# Signs out of Google Drive. The runner's `sign-out` clears the token from
# the keyring after a yes. The client ID, client secret and every file stay.
set -euo pipefail
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"
log="${XDG_STATE_HOME:-$HOME/.local/state}/vgshell/google-drive/setup.log"
runner="$VGS_PLUGIN_DIR/bin/google-drive"
mkdir -p -- "${log%/*}"
[[ $# == 0 ]] || vgs_tui_refuse "$log" 2 "google-drive: refused: arguments=none" "Select Sign out on the Google Drive page in Settings." || exit
vgs_tui_header "Sign out of Google Drive" "Sign out stops the sync until you sign in again." \
  "Your files stay on this computer and on Google Drive."
status=0
vgs_tui_confirm "Sign out of Google Drive?" || status=$?
case "$status" in
  0) ;;
  1) exit 0 ;;
  *) exit "$status" ;;
esac
logged="$(stat -c %s -- "$log" 2>/dev/null)" || logged=0
if vgs_tui_logged "$log" "$runner" sign-out >>"$log"; then
  vgs_tui_success "Google Drive is signed out."
  exit 0
fi
refusal="$(tail -c "+$((logged + 1))" -- "$log" | grep '^google-drive: refused: ' | tail -n 1)" || refusal=""
case "$refusal" in
  *credential=locked*) vgs_tui_failed "$log" "Your keyring is locked. Unlock it, then try again." ;;
  *) vgs_tui_failed "$log" "VGS could not sign out of Google Drive." ;;
esac
exit 1
