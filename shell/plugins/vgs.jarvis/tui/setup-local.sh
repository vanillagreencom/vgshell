#!/usr/bin/env bash
# The core presents this script from a private copy of the whole plugin.
set -euo pipefail
source "$VGS_TUI_LIB"
[[ $# == 0 ]] || { printf 'jarvis-setup: arguments=none\n' >&2; exit 2; }
for tool in gum uv curl unshare python3; do
  command -v "$tool" >/dev/null || { printf 'jarvis-setup: command=missing name=%s\n' "$tool" >&2; exit 77; }
done
vgs_tui_header "Set up local voice" "Downloads the selected models and a private Python runtime; each choice shows its download size." "No microphone, speaker or system settings are opened."
# One LABEL<TAB>TIER row per tier this computer can run; gum prints the TIER.
rows="$(python3 -I "$VGS_PLUGIN_DIR/setup-local" choices)" || exit 1
tier="$(vgs_tui_choose --label-delimiter=$'\t' <<<"$rows")" || exit 130
[[ -n $tier ]] || exit 130
exec python3 -I "$VGS_PLUGIN_DIR/setup-local" install "$tier"
