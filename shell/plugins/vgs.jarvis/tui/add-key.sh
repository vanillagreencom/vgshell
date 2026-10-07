#!/usr/bin/env bash
# Only metadata reaches the shell. secret-tool's terminal prompt masks the
# key and stores it directly. No transcript or shell variable holds it.
# Every keyed line goes to the Jarvis setup log; the screen shows a plain
# sentence.
set -euo pipefail
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"
log="${XDG_STATE_HOME:-$HOME/.local/state}/vgshell/jarvis/setup.log"
opened_elsewhere="Open Add key from the Jarvis page in Settings."
[[ $# == 0 ]] || vgs_tui_refuse "$log" 2 "jarvis-keys: arguments=none" "$opened_elsewhere" || exit
keys() { vgs_tui_logged "$log" node "$VGS_PLUGIN_DIR/backend/keys.js" "$@"; }
vgs_tui_header "Add an API key" "An API key from an AI provider lets Jarvis use that provider." \
  "The key stays in your desktop keyring. Jarvis does not show it."
[[ -t 0 ]] || vgs_tui_refuse "$log" 2 "jarvis-keys: store=terminal-required" "$opened_elsewhere" || exit
choices="$(keys providers "$(vgs_tui_columns)")" ||
  { vgs_tui_failed "$log" "Jarvis could not list the providers. Close this window and try again."; exit 1; }
provider="$(vgs_tui_choose --label-delimiter=$'\t' --header "Select the provider of your key. Make the key on its page first." \
  <<<"$choices")" || exit 130
[[ -n $provider ]] || exit 130
account="$(vgs_tui_input --header "A name for this key, to find it in the account list" --placeholder "for example work")" || exit 130
[[ -n $account ]] || exit 130
vgs_tui_step "Paste the key at the prompt. The key does not show while you type."
keys add-key "$provider" "$account" >>"$log" ||
  { vgs_tui_failed "$log" "Jarvis could not save the key." "Make sure that your keyring is unlocked, then try again."; exit 1; }
vgs_tui_success "The key is in your keyring. Select it as the AI model on the Jarvis page."
