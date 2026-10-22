#!/usr/bin/env bash
# The public app manifest contains no credential. Only Settings' Add key
# takes the installed app's token, through the core's masked field.
set -euo pipefail
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"
slack_manifest="$(dirname -- "${BASH_SOURCE[0]}")/../slack-app.json"
slack_url=""

slack_prepare_url() {
  # Slack's documented sharing link fills app creation from the public manifest.
  slack_url="$(node -p "'https://api.slack.com/apps?new_app=1&manifest_json=' + encodeURIComponent(require('node:fs').readFileSync(process.argv[1], 'utf8'))" "$slack_manifest" 2>/dev/null)"
}

slack_open_browser() {
  # The foreground opener shares the terminal's Ctrl+C; Bash runs the
  # cancellation trap after that child ends, before the next guide view.
  xdg-open "$slack_url" >/dev/null 2>&1
}

slack_header() {
  vgs_tui_clear
  vgs_tui_header 'Create Slack app' "Create the User OAuth Token used for your workspace's sender photos."
}

slack_steps() {
  vgs_tui_step '1. Choose the workspace'
  vgs_tui_text 'Sign in to Slack if asked. Select the workspace whose photos you want to show.'
  vgs_tui_step '2. Create the app'
  vgs_tui_text 'Review the requested permissions, then select Create.'
  vgs_tui_step '3. Install the app'
  vgs_tui_text 'Open OAuth & Permissions. Select Install to Workspace and allow access.'
  vgs_tui_step '4. Copy the token'
  vgs_tui_text 'Copy the User OAuth Token for this workspace, not a Bot User OAuth Token.'
  vgs_tui_step '5. Save it in Notifications'
  vgs_tui_text 'Sign in to this workspace in the Slack desktop app. Return to Notifications and open the Settings tab. Turn on Slack photos. Under Slack tokens, select Add key for this workspace. Paste the token into the masked field and select Save.'
}

slack_state=intro
trap 'slack_state=cancelled' INT TERM HUP
while :; do
  slack_header
  case "$slack_state" in
    intro)
      vgs_tui_text 'VGS fills the Slack app details. You choose your workspace and approve access in your browser. The app reads sender photos, workspace details and custom emoji. It does not request message or channel access.'$'\n\n''After installation, copy the User OAuth Token and paste it into the masked field in Notifications.'
      slack_action="$(vgs_tui_choose --header 'Choose:' -- 'Open Slack' 'Cancel')" || slack_action=Cancel
      ;;
    opening)
      vgs_tui_text 'Opening Slack in your browser…'
      if [[ -z $slack_url ]] && ! slack_prepare_url; then
        [[ $slack_state == cancelled ]] || slack_state=prepare-failed
      elif [[ $slack_state != cancelled ]]; then
        if slack_open_browser; then
          [[ $slack_state == cancelled ]] || slack_state=steps
        else
          [[ $slack_state == cancelled ]] || slack_state=open-failed
        fi
      fi
      continue
      ;;
    steps)
      slack_steps
      slack_action="$(vgs_tui_choose --header 'Choose:' -- 'Return to Notifications' 'Open Slack again' 'App approval needed' 'Cancel')" || slack_action=Cancel
      ;;
    open-failed)
      vgs_tui_text 'VGS could not open Slack in your browser.'
      slack_action="$(vgs_tui_choose --header 'Choose:' -- 'Retry opening' 'Continue in browser' 'Cancel')" || slack_action=Cancel
      ;;
    prepare-failed)
      vgs_tui_text 'VGS could not prepare the Slack app page. Close this guide and try again.'
      slack_action="$(vgs_tui_choose --header 'Choose:' -- 'Close')" || slack_action=Cancel
      ;;
    approval)
      vgs_tui_text 'If your workspace requires app approval, ask its administrator to approve VGS notification photos. Then open these steps again to install the app. Your saved tokens have not changed.'
      slack_action="$(vgs_tui_choose --header 'Choose:' -- 'Back to steps' 'Return to Notifications')" || slack_action=Cancel
      ;;
    return)
      vgs_tui_text 'Return to Notifications and open the Settings tab. Turn on Slack photos. Under Slack tokens, select Add key for the workspace. Paste its User OAuth Token into the masked field and select Save. VGS stores it in your keyring.'
      slack_action="$(vgs_tui_choose --header 'Choose:' -- 'Close')" || slack_action=Cancel
      ;;
    cancelled)
      vgs_tui_cancelled 'Setup cancelled. Your saved tokens have not changed.'
      exit 130
      ;;
    *)
      printf 'slack-setup: state=unexpected\n' >&2
      exit 1
      ;;
  esac
  case "$slack_action" in
    'Open Slack'|'Open Slack again'|'Retry opening') slack_state=opening ;;
    'Continue in browser'|'Back to steps') slack_state=steps ;;
    'App approval needed') slack_state=approval ;;
    'Return to Notifications') slack_state=return ;;
    Cancel) slack_state=cancelled ;;
    Close)
      [[ $slack_state != prepare-failed ]] || exit 69
      exit 0
      ;;
    *)
      printf 'slack-setup: choice=unexpected\n' >&2
      exit 1
      ;;
  esac
done
