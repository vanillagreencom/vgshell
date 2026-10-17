#!/usr/bin/env bash
# The core presents this script from a private copy of the whole plugin.
# No argument installs the tier setup-local picks for this computer; the
# Jarvis page's Local voice choice passes another tier, which setup-local
# judges.
set -euo pipefail
umask 077
source "$VGS_TUI_LIB"
[[ $# -le 1 ]] || { printf 'jarvis-setup: arguments=at-most-one\n' >&2; exit 2; }
for tool in gum uv curl unshare python3; do
  command -v "$tool" >/dev/null || {
    printf 'jarvis-setup: command=missing name=%s\n' "$tool" >&2
    vgs_tui_error "Select Review all missing or outdated tools under Tools on the Jarvis page before you set up local voice."
    exit 77
  }
done
if [[ $# == 0 ]]; then
  vgs_tui_header "Set up local voice" "Downloads the local voice model that runs best on this computer and the tools it needs." \
    "You can choose another model under Local voice on the Jarvis page." "No microphone, speaker or system settings are opened."
else
  vgs_tui_header "Set up local voice" "Downloads the local voice model you chose on the Jarvis page and the tools it needs." \
    "No microphone, speaker or system settings are opened."
fi
# Install removes the ready tier before it downloads, so replacing one asks
# first. The question names the ready tier and the one to install, as
# setup-local's choices and the tier table give them; "" when none is ready.
answer="$(python3 -I "$VGS_PLUGIN_DIR/setup-local" choices)" || exit 1
question="$(python3 -I -c '
import json, sys
from pathlib import Path
value, tiers = json.loads(sys.argv[1]), json.loads(Path(sys.argv[2]).read_text())["tiers"]
target, ready = sys.argv[3] or value["pick"], value["ready"]
if ready is not None and ready != target and target in tiers:
    print(tiers[ready]["name"] + " is ready. Replace it with " + tiers[target]["name"] + ": " + tiers[target]["description"] + "?")
' "$answer" "$VGS_PLUGIN_DIR/artifacts.json" "${1:-}")" || exit 1
if [[ -n $question ]] && ! vgs_tui_confirm "$question"; then
  printf 'The ready local voice model stays.\n'
  exit 130
fi
log="${XDG_STATE_HOME:-$HOME/.local/state}/vgshell/jarvis/setup-local.log"
vgs_tui_step "Setting up local voice"
status=0
vgs_tui_split "$log" jarvis-setup vgs_tui_logged "$log" python3 -I "$VGS_PLUGIN_DIR/setup-local" install "$@" || status=$?
if [[ $status != 0 ]]; then
  vgs_tui_failed "$log" "Local voice setup did not finish."
fi
exit "$status"
