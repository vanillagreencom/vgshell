#!/usr/bin/env bash
# Only metadata reaches the shell. The key goes from gum's masked box,
# through a pipe, to the stdin of backend/keys.js and on to the stdin of
# secret-tool store: no argument, shell variable, log or transcript holds it
# (docs/architecture/secrets.md). With no argument the window asks for the
# provider; with `voice`, the add-voice-key declaration's argument, it adds
# the key of the cloud voice the Jarvis settings name, names that company
# and opens only its key page in the browser, through the core's open rule
# (shell/Commons/DesktopLaunch.js open: gio open). Every keyed line goes to
# the Jarvis setup log; the screen shows a plain sentence, worded by the
# keys.js exit status for the refusals it names and pointing to the log for
# the rest.
set -euo pipefail
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"
log="${XDG_STATE_HOME:-$HOME/.local/state}/vgshell/jarvis/setup.log"
opened_elsewhere="Open Add key from the Jarvis page in Settings."
[[ $# == 0 || ( $# == 1 && $1 == voice ) ]] || vgs_tui_refuse "$log" 2 "jarvis-keys: arguments=none-or-voice" "$opened_elsewhere" || exit
keys() { vgs_tui_logged "$log" node "$VGS_PLUGIN_DIR/backend/keys.js" "$@"; }
list_full() {
  vgs_tui_failed "$log" "Jarvis cannot add a key: its key list is full." \
    "Remove a key you no longer use under API keys on the Setup tab of the Jarvis page, then try again."
}
# The add-key refusals keys.js gives an exit status of their own.
refused() { # STATUS
  case $1 in
    5) vgs_tui_failed "$log" "A key name takes at most 80 characters. Close this window and try again with a shorter name." ;;
    6) list_full ;;
    *) return 1 ;;
  esac
}
[[ -t 0 ]] || vgs_tui_refuse "$log" 2 "jarvis-keys: store=terminal-required" "$opened_elsewhere" || exit

if [[ $# == 1 ]]; then
  lib="$VGS_TUI_LIB"
  tree="${lib%/bin/lib/tui.sh}"
  settings="$(vgs_tui_logged "$log" "$tree/bin/vgshell" plugin settings "$VGS_PLUGIN_ID")" ||
    vgs_tui_refuse "$log" 1 "jarvis-keys: settings=unreadable" "VGS could not read the Jarvis settings." "Close this window and try again." || exit
  voice="$(vgs_tui_logged "$log" node -e 'process.stdout.write(String(JSON.parse(process.argv[1]).voiceProvider))' "$settings")" ||
    vgs_tui_refuse "$log" 1 "jarvis-keys: settings=unreadable" "VGS could not read the Jarvis settings." "Close this window and try again." || exit
  status=0
  row="$(keys voice-key "$voice")" || status=$?
  case $status in
    0) ;;
    7) vgs_tui_refuse "$log" 1 "jarvis-keys: voice=$voice" "Choose a cloud voice under Voice provider on the Jarvis page first." || exit ;;
    6) list_full; exit 1 ;;
    *) vgs_tui_failed "$log" "Jarvis could not read its key list."; exit 1 ;;
  esac
  IFS=$'\t' read -r provider company product page page_name account <<<"$row"
  vgs_tui_header "Add your $company key" "$product uses your $company key. The key stays in your desktop keyring."
else
  vgs_tui_header "Add an API key" "An API key from an AI or voice provider lets Jarvis use that provider." \
    "The key stays in your desktop keyring. Jarvis does not show it."
  choices="$(keys providers "$(vgs_tui_columns)")" ||
    { vgs_tui_failed "$log" "Jarvis could not list the providers. Close this window and try again."; exit 1; }
  provider="$(vgs_tui_choose --label-delimiter=$'\t' --header "Select the provider of your key." <<<"$choices")" || exit 130
  [[ -n $provider ]] || exit 130
  row="$(keys key-page "$provider")" ||
    { vgs_tui_failed "$log" "Jarvis could not read that provider. Close this window and try again."; exit 1; }
  IFS=$'\t' read -r company page page_name <<<"$row"
  account="$(vgs_tui_input --header "A name for this key, to find it in the account list" --placeholder "for example work")" || exit 130
  [[ -n $account ]] || exit 130
fi

# A key the list cannot take is refused before the box asks for it.
status=0
keys add-check "$provider" "$account" >/dev/null || status=$?
if [[ $status != 0 ]]; then
  refused "$status" || vgs_tui_failed "$log" "Jarvis could not read its key list."
  exit 1
fi
if [[ -n $page ]]; then
  # The window opens the page itself, after the user's own choice to add a
  # key; a page that does not open leaves the step to the user's browser.
  if vgs_tui_logged "$log" gio open "$page"; then
    vgs_tui_text "$page_name is open in your browser."
  else
    vgs_tui_note "$log" "jarvis-keys: key-page=unopened provider=$provider"
    vgs_tui_text "Open $page_name in your browser."
  fi
  vgs_tui_text "Sign in, create a key there, then copy the key."
fi
vgs_tui_step "Paste your $company key in the box below. The key does not show while you type."
vgs_tui_text "Enter saves the key in your keyring. Escape closes this window."
# The pipeline's own statuses: the box's, 130 on Escape, then the store's.
set +e
vgs_tui_input --password --placeholder "$company key" --width 0 | keys add-key "$provider" "$account" >>"$log"
codes=("${PIPESTATUS[@]}")
set -e
box=${codes[0]} status=${codes[1]}
if [[ $box != 0 ]]; then
  printf 'No key was saved.\n'
  exit 130
fi
case $status in
  0) ;;
  3) printf 'No key was saved.\n'; exit 130 ;;
  4) vgs_tui_failed "$log" "That text is longer than an API key." "Copy the key again from the provider's page, then try again."; exit 1 ;;
  *) refused "$status" || vgs_tui_failed "$log" "Jarvis could not save the key." "If your keyring is locked, unlock it, then try again."; exit 1 ;;
esac
if [[ $# == 1 ]]; then
  vgs_tui_success "Your $company key is in your keyring. Jarvis uses it for $product."
else
  vgs_tui_success "Your $company key is in your keyring. Select it as the AI model, or as the Voice key, on the Jarvis page."
fi
