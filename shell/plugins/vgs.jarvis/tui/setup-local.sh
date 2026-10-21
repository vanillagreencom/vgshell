#!/usr/bin/env bash
# The core presents this script from a private copy of the whole plugin.
# No argument installs the tier the Local voice model setting names, or the
# tier setup-local picks for this computer while it reads Auto; the Jarvis
# page's Local voice choice passes another tier, which setup-local judges.
# Before it installs, setup-local release asks Jarvis to close its local
# voice, whose speech program holds the setup lock while it runs. Every
# keyed line goes to the setup log, which every failure names; setup-local
# words each failure, and leaves an install's cause in its record for the
# Voice step.
set -euo pipefail
umask 077
source "$VGS_TUI_LIB"
state="${XDG_STATE_HOME:-$HOME/.local/state}/vgshell/jarvis"
log="$state/setup-local.log"
tree="${VGS_TUI_LIB%/bin/lib/tui.sh}"
[[ $# -le 1 ]] || vgs_tui_refuse "$log" 2 "jarvis-setup: arguments=at-most-one" \
  "Open Set up local voice from the Jarvis page in Settings." || exit
missing=()
for tool in gum uv curl unshare python3; do
  command -v "$tool" >/dev/null || missing+=("$tool")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  vgs_tui_refuse "$log" 77 "jarvis-setup: command=missing name=${missing[*]}" \
    "Jarvis needs ${missing[*]} to set up the local voice." \
    "Select Review all missing or outdated tools on the Setup tab of the Jarvis page, then try again." || exit
fi
unreadable() {
  vgs_tui_header "Set up local voice" "No microphone, speaker or system settings are opened."
  vgs_tui_refuse "$log" 1 "jarvis-setup: $1" "Jarvis could not read the local voice models for this computer." \
    "Close this window and try again." || exit
}
tier="${1:-}"
if [[ -z $tier ]]; then
  # The model the page names, as setup-fleet.sh reads the home folder.
  settings="$(vgs_tui_logged "$log" "$tree/bin/vgshell" plugin settings "$VGS_PLUGIN_ID")" || unreadable settings=unreadable
  tier="$(vgs_tui_logged "$log" python3 -I -c '
import json, sys
tier = json.loads(sys.argv[1]).get("localTier")
if not isinstance(tier, str):
    sys.exit("jarvis-setup: setting=localTier")
print("" if tier == "auto" else tier)
' "$settings")" || unreadable setting=localTier
fi
# Install removes the ready tier before it downloads, so a replacement asks
# first, and so does a first download; setup-local's plan names the tier and
# its size as the page's Local voice list does.
plan="$(vgs_tui_logged "$log" python3 -I "$VGS_PLUGIN_DIR/setup-local" plan ${tier:+"$tier"})" || unreadable plan=failed
{ IFS= read -r download; IFS= read -r question || question=""; } <<<"$plan"
vgs_tui_header "Set up local voice" "$download" "No microphone, speaker or system settings are opened."
if [[ -n $question ]] && ! vgs_tui_confirm "$question"; then
  printf 'Nothing was downloaded.\n'
  exit 130
fi
vgs_tui_step "Setting up local voice"
# The split takes setup-local's stderr too: its keyed lines go to the log,
# and its plain lines, curl's progress among them, reach the screen. Each
# failure printed its own plain line; the window adds the log.
status=0
vgs_tui_split "$log" jarvis-setup python3 -I "$VGS_PLUGIN_DIR/setup-local" release "$tree/bin/vgshell" || status=$?
if [[ $status == 0 ]]; then
  vgs_tui_split "$log" jarvis-setup python3 -I "$VGS_PLUGIN_DIR/setup-local" install ${tier:+"$tier"} || status=$?
fi
[[ $status == 0 ]] && exit 0
vgs_tui_failed "$log"
exit "$status"
