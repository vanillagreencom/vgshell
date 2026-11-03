#!/usr/bin/env bash
# Agent Debug's Unmute, the Muted programs row action on its Settings page:
# the row's program name is the one argument. It asks one yes or no
# question; on yes it asks the plugin's service to unmute the program, so
# Agent Debug notifies again when that program crashes. The core judges the
# row id before the run (PluginLogic.tuiArgsValid).
#
#   unmute.sh PROGRAM
set -euo pipefail
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"
[[ $# == 1 ]] ||
  { vgs_tui_error "Select Unmute beside a program on the Agent Debug page in Settings."; exit 2; }
program="$1"
vgs_tui_header "Unmute a program" "Agent Debug notifies you again when this program crashes."
vgs_tui_step "$program"
# gum confirm answers 1 for No, which ends the script as a success. 130 is a
# Ctrl-C, which present closes on without a prompt, and any other status is
# a refusal: both leave with their own code.
status=0
vgs_tui_confirm "Unmute $program?" || status=$?
case "$status" in
  0) ;;
  1) exit 0 ;;
  *) exit "$status" ;;
esac
# The service's answer: `ok`, `refused: program=unmuted` for a program
# already off the list, `refused: user-config=...` when the settings file
# could not be written (Service.keepMuted), or nothing when VGS did not
# answer. Any other reply goes to the log, not the screen.
answer="$(vgshell ipc call vgs.agent-debug invoke unmute "$program")" || answer=""
case "$answer" in
  ok | "refused: program=unmuted") ;;
  "refused: user-config="*) vgs_tui_error "VGS could not save its settings file, so $program stays muted."; exit 1 ;;
  "") vgs_tui_error "VGS did not answer, so $program stays muted. Try again when VGS runs."; exit 1 ;;
  *)
    vgs_tui_refuse "${XDG_STATE_HOME:-$HOME/.local/state}/vgshell/agent-debug/unmute.log" 1 "agent-debug: unmute=refused answer=$answer" \
      "Agent Debug could not unmute $program. Try again from the Agent Debug page in Settings." || exit
    ;;
esac
vgs_tui_success "Agent Debug notifies you again when $program crashes."
