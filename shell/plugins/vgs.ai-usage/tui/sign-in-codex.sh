#!/usr/bin/env bash
# Codex's own sign-in, which opens its sign-in page in the browser and keeps
# what it gets in its own folder. AI Usage reads that folder after the run
# ends; this script opens no file of it.
set -euo pipefail
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"
vgs_tui_header "Sign in to Codex" "Codex opens its sign-in page in your browser."
codex login
