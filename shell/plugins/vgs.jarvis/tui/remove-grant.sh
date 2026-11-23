#!/usr/bin/env bash
# Jarvis's Remove, the Always allowed row action on its Settings page: the
# row's standing grant key is the one argument. It asks one yes or no
# question about the row's label; on yes it asks the plugin's service to
# remove the key, so Jarvis asks again before that kind of request. The core
# judges the row id before the run (PluginLogic.tuiArgsValid).
#
#   remove-grant.sh KEY
set -euo pipefail
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"
[[ $# == 1 ]] ||
  { vgs_tui_error "Select Remove beside a request on the Jarvis page in Settings."; exit 2; }
key="$1"
# The service's answers: the row's label, `refused: always-allow=unknown`
# for a key no longer saved, or nothing when VGS did not answer.
label="$(vgshell ipc call vgs.jarvis invoke grant-label "$key")" || label=""
case "$label" in
  "refused: always-allow=unknown") vgs_tui_success "Jarvis already asks before this request."; exit 0 ;;
  "") vgs_tui_error "VGS did not answer. Try again when VGS runs."; exit 1 ;;
esac
vgs_tui_header "Remove an allowed request" "Jarvis asks you again before it does this."
vgs_tui_step "$label"
# gum confirm answers 1 for No, which ends the script as a success. 130 is a
# Ctrl-C, which present closes on without a prompt, and any other status is
# a refusal: both leave with their own code.
status=0
vgs_tui_confirm "Remove this allowed request?" || status=$?
case "$status" in
  0) ;;
  1) exit 0 ;;
  *) exit "$status" ;;
esac
# `ok`, `refused: always-allow=unknown` for a key already removed,
# `refused: user-config=...` when the settings file could not be written
# (Service.removeGrant), or nothing when VGS did not answer. Any other
# reply goes to the log, not the screen.
answer="$(vgshell ipc call vgs.jarvis invoke remove-grant "$key")" || answer=""
case "$answer" in
  ok | "refused: always-allow=unknown") ;;
  "refused: user-config="*) vgs_tui_error "VGS could not save its settings file, so Jarvis still does this without asking."; exit 1 ;;
  "") vgs_tui_error "VGS did not answer, so Jarvis still does this without asking. Try again when VGS runs."; exit 1 ;;
  *)
    vgs_tui_refuse "${XDG_STATE_HOME:-$HOME/.local/state}/vgshell/jarvis/remove-grant.log" 1 "jarvis: remove-grant=refused answer=$answer" \
      "Jarvis could not remove this request. Try again from the Jarvis page in Settings." || exit
    ;;
esac
vgs_tui_success "Jarvis asks you again before it does this."
