#!/usr/bin/env bash
# The core owns terminal presentation. This script carries metadata only.
# The helper prints the rows this screen shows; every keyed line and result
# goes to the Jarvis setup log, and the screen shows a plain sentence.
set -euo pipefail
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"
log="${XDG_STATE_HOME:-$HOME/.local/state}/vgshell/jarvis/setup.log"
opened_elsewhere="Open Accounts from the Jarvis page in Settings."
[[ $# == 0 ]] || vgs_tui_refuse "$log" 2 "jarvis-accounts: arguments=none" "$opened_elsewhere" || exit
[[ -t 0 ]] || vgs_tui_refuse "$log" 2 "jarvis-accounts: input=terminal-required" "$opened_elsewhere" || exit
program="$VGS_PLUGIN_DIR/backend/accounts.js"
# The VGS tree is the one VGS_TUI_LIB lies in; the helper reads the core's
# account rule from there.
tree="${VGS_TUI_LIB%/bin/lib/tui.sh}"
[[ $tree != "$VGS_TUI_LIB" && $tree == /* ]] ||
  vgs_tui_refuse "$log" 2 "jarvis-accounts: tui=lib-outside-tree" "$opened_elsewhere" || exit
child_env=(env -i PATH="$PATH" HOME="$HOME" LANG=C.UTF-8
  XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-}" XDG_STATE_HOME="${XDG_STATE_HOME:-}"
  XDG_DATA_HOME="${XDG_DATA_HOME:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}"
  DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-}"
  CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-}" CODEX_HOME="${CODEX_HOME:-}"
  COPILOT_HOME="${COPILOT_HOME:-}"
  VGS_TUI_ACCENT="${VGS_TUI_ACCENT:-}" VGS_TUI_SUCCESS="${VGS_TUI_SUCCESS:-}"
  VGS_TUI_WARNING="${VGS_TUI_WARNING:-}" VGS_TUI_DANGER="${VGS_TUI_DANGER:-}")
# The core presentation functions call this scoped executable wrapper too.
gum() { "${child_env[@]}" gum "$@"; }
# A selection carries a stable id, never a label, back into the judge. No
# secret value enters the shell.
accounts() { vgs_tui_logged "$log" "${child_env[@]}" node "$program" --tree "$tree" "$@"; }
choose() { vgs_tui_choose --label-delimiter=$'\t' "$@"; }
vgs_tui_header "Jarvis accounts" "The accounts Jarvis can use as its AI model." \
  "Signed in does not prove that the AI answers. Verify checks that."
# Each action with one line that says what it does.
actions="Show accounts      See each account Jarvis found and its status."$'\t'show
actions+=$'\n'"Add directory      Add a Claude Code, Codex or Copilot folder Jarvis did not find."$'\t'add
actions+=$'\n'"Use keyring item   Use an API key you saved in your keyring before."$'\t'item
actions+=$'\n'"Verify             Send one small paid request to check an account."$'\t'verify
actions+=$'\n'"Close              Close this window."$'\t'close
while true; do
  action="$(choose --header "Select an action." <<<"$actions")" || exit 130
  columns="$(vgs_tui_columns)"
  case "$action" in
    show)
      table="$(accounts table "$columns")" ||
        { vgs_tui_failed "$log" "Jarvis could not read your accounts. Close this window and try again."; continue; }
      if [[ -z $table ]]; then
        vgs_tui_warn "Jarvis found no account."
        vgs_tui_warn "Add a folder with Add directory, or a key with Add key."
      else
        gum table --print <<<"$table"
      fi
      ;;
    add)
      choices="$(accounts providers cli "$columns")" ||
        { vgs_tui_failed "$log" "Jarvis could not list the programs. Close this window and try again."; continue; }
      selected="$(choose --header "Select the program that signs in from this folder." <<<"$choices")" || exit 130
      dir="$(vgs_tui_input --header "The full path of the folder where the program keeps its sign-in" \
        --placeholder "for example $HOME/.claude-work")" || exit 130
      label="$(vgs_tui_input --header "A name for this account" --placeholder "for example work")" || exit 130
      if accounts add "$selected" "$dir" "$label" >>"$log"; then
        vgs_tui_success "Jarvis added the folder."
      else
        vgs_tui_failed "$log" "Jarvis could not add the folder." "Type the full path of a folder that exists, then try again."
      fi
      ;;
    item)
      choices="$(accounts items "$columns")" ||
        { vgs_tui_failed "$log" "Jarvis could not read your keyring. Unlock it, then try again."; continue; }
      [[ -n $choices ]] || { vgs_tui_warn "Your keyring has no API key that Jarvis can use. Add one with Add key."; continue; }
      item="$(choose --header "Select the keyring item that holds the API key." <<<"$choices")" || exit 130
      providers="$(accounts providers key "$columns")" ||
        { vgs_tui_failed "$log" "Jarvis could not list the providers. Close this window and try again."; continue; }
      selected="$(choose --header "Select the provider of this key." <<<"$providers")" || exit 130
      label="$(vgs_tui_input --header "A name for this key, to find it in the account list" --placeholder "for example work")" || exit 130
      if accounts remember "$item" "$selected" "$label" >>"$log"; then
        vgs_tui_success "Jarvis can use the key now."
      else
        vgs_tui_failed "$log" "Jarvis could not use this keyring item." "Select a different item, or add the key with Add key."
      fi
      ;;
    verify)
      choices="$(accounts accounts "$columns")" ||
        { vgs_tui_failed "$log" "Jarvis could not read your accounts. Close this window and try again."; continue; }
      [[ -n $choices ]] || { vgs_tui_warn "Jarvis found no account to check."; continue; }
      selected="$(choose --header "Select the account to check." <<<"$choices")" || exit 130
      model="$(vgs_tui_input --header "Model name. Leave it empty for the default. A local server needs one.")" || exit 130
      code=0
      vgs_tui_confirm "Send one small paid request to this account? It can cost money." || code=$?
      case "$code" in
        0)
          code=0
          accounts verify "$selected" user "$model" >>"$log" || code=$?
          case "$code" in
            0) vgs_tui_success "The account answered. Jarvis can use it." ;;
            69) vgs_tui_failed "$log" "The account did not answer." "Make sure that it is signed in or that its key is correct, then try again." ;;
            *) vgs_tui_failed "$log" "Jarvis could not check the account. Close this window and try again." ;;
          esac
          ;;
        1) ;;
        *) exit "$code" ;;
      esac
      ;;
    close) exit 0 ;;
    *) vgs_tui_refuse "$log" 2 "jarvis-accounts: selection=unknown" "$opened_elsewhere" || exit ;;
  esac
done
