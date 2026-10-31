#!/usr/bin/env bash
# The core presents this script from a private copy of the whole plugin.
# It refuses before the header unless the Large local voice tier can host
# the clone, then asks consent. A No explains what was kept and waits for a
# key. After consent it clears the screen, downloads the model, records ten
# seconds and publishes the checked recording.
set -euo pipefail
# The recording log and state directory hold a user's voice setup evidence.
umask 077
source "$VGS_TUI_LIB"
[[ $# == 0 ]] || { printf 'jarvis-clone: arguments=none\n' >&2; exit 2; }
state="${XDG_STATE_HOME:-$HOME/.local/state}/vgshell/jarvis"
log="$state/clone-voice.log"
mkdir -p -- "$state"
: >"$log"
details() {
  vgs_tui_error "The details are in ${log/#"$HOME"/\~}."
}
# 69 is setup-local's refusal before anything ran: its sentence says what
# to set up first, and present closes it without Failed.
status=0
vgs_tui_split "$log" jarvis-setup python3 -I "$VGS_PLUGIN_DIR/setup-local" clone check || status=$?
case "$status" in
  0) ;;
  69) exit 69 ;;
  *) details; exit 1 ;;
esac
# The recording's length, inside setup-local's bounds of 5 to 15 s.
seconds=10
declined() {
  vgs_tui_cancelled "Nothing was downloaded or stored."
  exit 130
}
vgs_tui_header "Set up cloned voice" \
  "Jarvis will speak in a voice recorded on this computer, with Chatterbox Turbo by Resemble AI. The model and the recording stay on this computer." \
  "Resemble AI's model card says:" \
  "\"Don't use this model to do bad things. Prompts are sourced from freely available data on the internet.\""
vgs_tui_confirm "Have you read Resemble AI's text above?" || declined
vgs_tui_confirm "Is the voice you will record your own, or do you have the speaker's permission?" || declined
# The download and the recording start on a cleared screen under the title
# alone: below the logo and the consent text they would overflow the window
# and scroll part of the logo off its top.
vgs_tui_clear
vgs_tui_header "Set up cloned voice"
vgs_tui_step "Downloading the model"
if ! vgs_tui_split "$log" jarvis-setup python3 -I "$VGS_PLUGIN_DIR/setup-local" clone install; then
  details
  exit 1
fi
vgs_tui_step "Recording"
vgs_tui_text "Recording runs for $seconds seconds. Read this aloud in your normal voice:"$'\n\n''"The quick brown fox jumps over the lazy dog. I am recording my voice so that Jarvis can speak with it on this computer."'
vgs_tui_confirm "Start recording?" || { vgs_tui_cancelled "The model stays for a later setup. No recording was stored."; exit 130; }
capture() {
  local status=0
  timeout --signal=INT "$seconds" pw-record --raw --rate 24000 --channels 1 --format s16 - || status=$?
  # timeout answers 124 when the bound ends the recording, as it should.
  [[ $status == 0 || $status == 124 ]]
}
vgs_tui_step "Recording now: read the text aloud. Recording stops after $seconds seconds."
if ! capture | vgs_tui_split "$log" jarvis-setup python3 -I "$VGS_PLUGIN_DIR/setup-local" clone record; then
  details
  exit 1
fi
vgs_tui_success "The cloned voice is ready. Turn on Cloned voice under Local voice on the Jarvis page."
