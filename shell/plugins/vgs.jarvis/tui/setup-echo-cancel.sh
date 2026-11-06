#!/usr/bin/env bash
# The core runs this explicit action from the published plugin snapshot.
# The confirmed plan is the only file write. No audio service is restarted.
set -euo pipefail
umask 077
source "$VGS_TUI_LIB"
tree="${VGS_TUI_LIB%/bin/lib/tui.sh}"
log="${XDG_STATE_HOME:-$HOME/.local/state}/vgshell/jarvis/setup-echo-cancel.log"
helper="$VGS_PLUGIN_DIR/backend/echo-cancel-setup.js"
[[ $# == 0 ]] || vgs_tui_refuse "$log" 2 "jarvis-echo-cancel: arguments=none" \
  "Open Set up echo cancellation from the Jarvis page in Settings." || exit
vgs_tui_header "Set up echo cancellation" \
  "Jarvis can listen during replies with Realtime and Gemini. Local and ElevenLabs keep the microphone closed during replies." \
  "This writes one user PipeWire file. It changes no global default and restarts no audio service."
settings="$(vgs_tui_logged "$log" "$tree/bin/vgshell" plugin settings "$VGS_PLUGIN_ID")" || {
  vgs_tui_refuse "$log" 1 "jarvis-echo-cancel: settings=unreadable" \
    "Jarvis could not read the selected microphone and speaker. Close this window and try again." || exit
}
plan="$(vgs_tui_logged "$log" node "$helper" plan "$tree" <<<"$settings")" || {
  vgs_tui_refuse "$log" 1 "jarvis-echo-cancel: plan=unavailable" \
    "Jarvis could not prepare echo cancellation. Choose a physical microphone and speaker on the Jarvis page, then try again." \
    "An existing file changed by another program or a linked path is kept." || exit
}
vgs_tui_logged "$log" node "$helper" describe "$tree" <<<"$plan" || {
  vgs_tui_failed "$log"
  exit 1
}
vgs_tui_text "Noise suppression and gain control stay off. The high-pass filter stays on."
vgs_tui_text "The file takes effect at the next PipeWire start or login. This can require ending your current audio session."
if ! vgs_tui_confirm "Write this echo cancellation setup?"; then
  vgs_tui_text "No file was changed."
  exit 130
fi
vgs_tui_step "Writing echo cancellation setup"
if ! vgs_tui_logged "$log" node "$helper" install "$tree" <<<"$plan"; then
  vgs_tui_refuse "$log" 1 "jarvis-echo-cancel: install=failed" \
    "Jarvis could not write its echo cancellation file. An existing file changed by another program is kept." || exit
fi
vgs_tui_text "The file is installed. Settings shows whether the named audio route is active."
vgs_tui_text "Until that route is active, Jarvis keeps the microphone closed during replies."
