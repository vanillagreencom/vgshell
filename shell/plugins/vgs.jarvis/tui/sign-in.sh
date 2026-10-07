#!/usr/bin/env bash
# The vendor's prompts and sign-in result stay on the terminal.
set -euo pipefail
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"
log="${XDG_STATE_HOME:-$HOME/.local/state}/vgshell/jarvis/setup.log"
opened_elsewhere="Open Sign in from the Jarvis page in Settings."
[[ $# == 0 && -t 0 ]] || vgs_tui_refuse "$log" 2 "jarvis-accounts: sign-in=terminal-required" "$opened_elsewhere" || exit
tree="${VGS_TUI_LIB%/bin/lib/tui.sh}"
[[ $tree != "$VGS_TUI_LIB" && $tree == /* ]] ||
  vgs_tui_refuse "$log" 2 "jarvis-accounts: tui=lib-outside-tree" "$opened_elsewhere" || exit
child_env=(env -i PATH="$PATH" HOME="$HOME" LANG=C.UTF-8
  XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-}" XDG_STATE_HOME="${XDG_STATE_HOME:-}"
  XDG_DATA_HOME="${XDG_DATA_HOME:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}"
  DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-}"
  DISPLAY="${DISPLAY:-}" WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}"
  VGS_TUI_ACCENT="${VGS_TUI_ACCENT:-}" VGS_TUI_SUCCESS="${VGS_TUI_SUCCESS:-}"
  VGS_TUI_WARNING="${VGS_TUI_WARNING:-}" VGS_TUI_DANGER="${VGS_TUI_DANGER:-}")
gum() { "${child_env[@]}" gum "$@"; }
program="$VGS_PLUGIN_DIR/backend/accounts.js"
vgs_tui_header "Sign in to an AI account" "Use your Claude Code or Codex account as the Jarvis AI model." \
  "The app runs its own sign-in. Jarvis does not read or copy its login token."
choices="$(vgs_tui_logged "$log" "${child_env[@]}" node "$program" --tree "$tree" providers cli "$(vgs_tui_columns)")" ||
  { vgs_tui_failed "$log" "Jarvis could not list the apps. Close this window and try again."; exit 1; }
selected="$(vgs_tui_choose --label-delimiter=$'\t' --header "Select the app to sign in to." <<<"$choices")" || exit 130
dir="$(vgs_tui_input --header "The full path of the folder where the app keeps this sign-in" \
  --placeholder "for example $HOME/.$selected-work. Jarvis creates the folder if needed.")" || exit 130
label="$(vgs_tui_input --header "A name for this account" --placeholder "for example work")" || exit 130
code=0
"${child_env[@]}" node "$program" --tree "$tree" sign-in "$selected" "$dir" "$label" || code=$?
case "$code" in
  0) vgs_tui_success "You are signed in. Select the account as the AI model on the Jarvis page." ;;
  69) vgs_tui_warn "The app is not installed. Use its Install button on the Jarvis page, then try Sign in again."; exit 69 ;;
  *) vgs_tui_error "Sign in did not complete."; vgs_tui_error "Check the folder path and the app's sign-in, then try again."; exit "$code" ;;
esac
