#!/usr/bin/env bash
# The vgs.updates `review` floating TUI: the AI agent that reviews one
# update run's third-party packages, in a window of its own, so the user
# can talk to it. tui/pipeline.sh opens it through the service's `review`
# IPC handler and waits for it to end:
# shell/plugins/vgs.updates/pipeline.md § Third-party review.
#
#   review.sh <dir>
#
# <dir> is the run's review directory, which the pipeline made inside the
# stable review start directory and filled: `command`, the agent's command
# words one per line, and `packages.txt`, the packages to review. The
# script holds <dir>/review.lock while it lives, writes <dir>/started once
# it holds it, and then runs the words with the text of
# review/third-party.md as one more argument, from <dir>'s parent. The
# agent's folder trust is keyed on that stable parent, so the user trusts
# it once. The prompt names <dir>, where the agent writes its verdict. The
# agent does not inherit the lock, so the lock goes when this script ends,
# as it does when the window closes. Nothing here elevates.
#
# Refuses, exiting 2, with `updates: refused: argument=<arg>` for a bad
# invocation, and exiting 1 with `review=command-missing dir=<dir>` when
# <dir> names no command and `review=busy dir=<dir>` when another review
# holds its lock.
set -Eeuo pipefail
# shellcheck source=SCRIPTDIR/pipeline.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/pipeline.sh"
[[ -n ${VGS_TUI_LIB:-} && -n ${VGS_PLUGIN_DIR:-} ]] || _updates_refuse 2 "tui=missing" "run this through the vgs.updates floating TUI, which sets VGS_TUI_LIB and VGS_PLUGIN_DIR"
[[ $# -eq 1 && -d ${1:-} ]] || _updates_refuse 2 "argument=${1:-missing}" "usage: review.sh <dir>"
dir="$(cd -- "$1" && pwd -P)" || _updates_refuse 2 "argument=$1" "usage: review.sh <dir>"
words=()
if [[ -s $dir/command ]]; then mapfile -t words <"$dir/command"; fi
[[ ${#words[@]} -gt 0 ]] || _updates_refuse 1 "review=command-missing dir=$dir"
prompt="$(<"$VGS_PLUGIN_DIR/review/third-party.md")"
prompt="${prompt//\{review_dir\}/$dir}"
exec {lock}>>"$dir/review.lock"
flock -n "$lock" || _updates_refuse 1 "review=busy dir=$dir"
: >"$dir/started"
cd -- "${dir%/*}"
"${words[@]}" "$prompt" {lock}>&-
