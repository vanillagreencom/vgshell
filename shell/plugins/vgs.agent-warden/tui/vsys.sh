#!/usr/bin/env bash
# The vgs.agent-warden TUI `vsys`: the vsys dashboard, presented plain in the
# wide window, so vsys draws the whole terminal and the window closes when
# it quits. The flyout's Open vsys opens it with the `open` arguments of the
# summary cause its line shows, which vsys reads as its own, and none
# otherwise.
set -euo pipefail
exec vsys "$@"
