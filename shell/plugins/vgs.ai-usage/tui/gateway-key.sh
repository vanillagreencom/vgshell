#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"
vgs_tui_header "Get AI Gateway key" "Add a key to show AI Gateway credit figures."
xdg-open https://vercel.com/dashboard
printf '%s\n' \
  'In Vercel, open AI Gateway, then API keys, then Create key.' \
  'Return to AI Usage in Settings. Turn on AI Gateway credits.' \
  'Under Setup, select Add key beside AI Gateway.' \
  'Paste the key into the masked field. VGS stores it in your keyring.'
