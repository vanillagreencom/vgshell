#!/usr/bin/env bash
# The Jarvis session row's Resume: asks the service, which asks the Jarvis
# package in the home folder to resume the session saved before the
# computer restarted. The presentation is plain, so a failure holds the
# window on the library's own close prompt.
set -Eeuo pipefail
source "$VGS_TUI_LIB"
trap 'status=$?; [[ $status == 0 ]] || vgs_tui_close_prompt "$status"' EXIT
answer="$(vgshell ipc call vgs.jarvis invoke resume-session '')" || exit 1
case "$answer" in
  ok) ;;
  refused:*) vgs_tui_error "Jarvis has no session to resume. It resumed already, or you chose Do not resume."; exit 1 ;;
  *) vgs_tui_error "Jarvis is not running. Turn on Enabled on the Jarvis page."; exit 1 ;;
esac
