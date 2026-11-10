#!/usr/bin/env bash
# Opens the whole AGENTS.md of the home the daemon judged ready, the home's
# instructions, whose path the service answers, in the user's editor. The
# presentation is plain, so a failure holds the window on the library's own
# close prompt.
set -Eeuo pipefail
source "$VGS_TUI_LIB"
trap 'status=$?; [[ $status == 0 ]] || vgs_tui_close_prompt "$status"' EXIT
file="$(vgshell ipc call vgs.jarvis invoke instructions-file '')" || exit 1
[[ $file == /* ]] || { vgs_tui_error "Jarvis has no home folder. Choose a home folder first in Settings > Jarvis > Home folder."; exit 1; }
vgs_tui_edit "$file"
