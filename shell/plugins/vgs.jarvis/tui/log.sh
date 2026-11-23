#!/usr/bin/env bash
# The vgs.jarvis `log` floating TUI, a Jarvis error card's View log: the
# newest 200 Jarvis lines of the running shell's log, under the presenter's
# close prompt. Jarvis's lines carry keyed causes and never provider text,
# a transcript or a key (docs/architecture/jarvis.md § The approach).
#
#   log.sh
set -euo pipefail
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"
(( $# == 0 )) || { vgs_tui_error "Select View log on the Jarvis error card again."; exit 2; }
# `vgshell log` reads the running shell's log through `qs log`; --tail
# bounds it to the newest lines.
if ! log="$(vgshell log --tail 20000)"; then
  vgs_tui_error "VGS could not read its log. Try again when VGS runs."
  exit 1
fi
lines="$(grep -a -F 'jarvis' <<<"$log" | tail -n 200)" || lines=""
if [[ -z $lines ]]; then
  vgs_tui_text "Jarvis wrote no lines to the VGS log."
  exit 0
fi
vgs_tui_text "The newest lines Jarvis wrote to the VGS log."
printf '%s\n' "$lines"
