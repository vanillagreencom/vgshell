#!/usr/bin/env bash
# The vgs.local-sync `log` floating TUI: the newest 200 lines of one sync
# job's journal, under the presenter's close prompt.
#
#   log.sh UNIT
#
# UNIT is the job's systemd user unit, the name the panel lists. Anything but
# one argument naming one service unit, `^[A-Za-z0-9:_.@-]+\.service$`, ends
# the run with exit 2 and a sentence and runs nothing. The pattern holds no
# glob character, so journalctl's -u matches that one unit, and the name
# reaches journalctl as one argv word, never as shell text.
set -euo pipefail
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"

# The C locale makes the ranges plain ASCII whatever locale the terminal has.
one_unit() { local LC_ALL=C; (( $# == 1 )) && [[ $1 =~ ^[A-Za-z0-9:_.@-]+\.service$ ]]; }
if ! one_unit "$@"; then
  vgs_tui_error "Local Sync cannot show this job's log. Select View log on the job again."
  exit 2
fi
unit="$1"

vgs_tui_text "The newest lines this sync job wrote to its log."
journalctl --user -u "$unit" -n 200 --no-pager
