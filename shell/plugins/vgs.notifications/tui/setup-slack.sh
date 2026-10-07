#!/usr/bin/env bash
# The public app manifest contains no credential. Only Settings Connect
# takes the installed app's token, through the core's masked field.
set -euo pipefail
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"
slack_manifest="$(dirname -- "${BASH_SOURCE[0]}")/../slack-app.json"
vgs_tui_header "Set up Slack photos" "Add sender photos, workspace icons and custom emoji to Slack notifications."
wl-copy --type text/plain <"$slack_manifest"
xdg-open https://api.slack.com/apps
printf '%s\n' \
  'VGS copied the app details and opened Slack Apps.' \
  'Select Create New App, then From a manifest.' \
  'Select your workspace. Paste the copied text into the JSON field.' \
  'Review the permissions, then select Create.' \
  'Under OAuth & Permissions, select Install to Workspace and allow access.' \
  'Copy the User OAuth Token.' \
  'Sign in to this workspace in the Slack desktop app.' \
  'Return to Notifications in Settings. Turn on Slack photos.' \
  'Select Connect beside that workspace. Paste the token into the masked field.' \
  'If your workspace requires approval, ask its administrator to approve the app.'
while :; do
  slack_action="$(gum choose 'Close' 'Show details' 'Copy app details again')"
  case "$slack_action" in
    Close) break ;;
    'Show details') cat -- "$slack_manifest" ;;
    'Copy app details again') wl-copy --type text/plain <"$slack_manifest" ;;
  esac
done
