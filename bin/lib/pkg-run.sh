#!/usr/bin/env bash
# bin/lib/pkg-run.sh: runs the steps of one package plan in the terminal
# the user sees. bin/vgshell-pkg's `run` decides everything first (the caller,
# the terminal, the plan and the elevation command) and then starts this
# file with bash, so the steps run under bin/lib/tui.sh's sudo session. The
# vgs.devtools engine starts it with ELEVATOR none for its mise, container
# and installer steps, so every step a floating TUI runs is shown alike.
#
#   pkg-run.sh [--evidence DIR] ELEVATOR COUNT ARG... [COUNT ARG...]...
#
# ELEVATOR is `sudo`, `doas`, `run0` or `none`. Each step is COUNT, a
# positive number, then that many arguments, the step's argv. The steps
# reach this file as argv from node, never as a shell string, and run as
# lists: a package name holding `$(...)` stays one literal word.
#
# The steps run in the directory this file starts in, which bin/vgshell-pkg
# sets to $HOME. Each step runs in order with ELEVATOR before it, unless
# ELEVATOR is none,
# after a step line in the theme accent. The first step that fails ends the
# run with its exit status. Under sudo every run holds one sudo session
# (tui.sh's vgs_tui_sudo_session): the password is asked once, before the
# first step, and the credential is dropped when the run ends, whatever the
# number of steps. A run started inside another script's sudo session, as
# the Updates pipeline starts `vgshell pkg run upgrade`, joins that session and
# leaves the credential to its owner. doas and run0 get no keepalive: each
# step asks as the system's own rules say, doas.conf's `persist` or polkit's
# `auth_admin_keep`, since neither has a command that refreshes a
# credential without running a program as root.
#
# With --evidence, DIR is a private directory the package owner made for
# one build. The run then keeps a transcript of its terminal, the run's own
# or, under a script that already keeps one, that one (tui.sh's
# vgs_tui_transcript), and when a step fails it writes the step's output,
# cut between tui.sh's interval marks, to DIR/interval, and one line to
# DIR/result: `step=<k> status=<n> cut=<ok|absent|late|lost|copy-failed|
# skipped>`, k counting steps from 1, skipped for a step a signal ended,
# whose output nobody reads. The owner reads both once the run exits. The
# steps run in the directory this file starts in, as without --evidence.
#
# The ending, Done or Failed, is `vgshell-tui present`'s: this file prints no
# verdict. A bad invocation prints `vgshell: refused: pkg-run=<key>` and exits
# 2; a sudo session that cannot start exits 1 after tui.sh's refusal line.
set -euo pipefail

# shellcheck source=tui.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/tui.sh"

bad() { printf 'vgshell: refused: pkg-run=%s\n' "$1" >&2; exit 2; }

evidence=""
if [[ ${1:-} == --evidence ]]; then
  [[ $# -ge 2 && $2 == /* && -d $2 && ! -L $2 && -O $2 ]] || bad "evidence value=${2:-missing}"
  evidence="$2"
  # A transcript that cannot start leaves the cut absent: unread evidence,
  # never a reason to keep the user's build from running.
  if command -v script >/dev/null; then vgs_tui_transcript "$@" || :; fi
  shift 2
fi
elevator="${1:-}"
[[ $# -gt 0 ]] && shift
case "$elevator" in
  sudo|doas|run0) prefix=("$elevator") ;;
  none|build) prefix=() ;;
  *) bad "elevator value=${elevator:-missing}" ;;
esac

args=("$@")
starts=()
counts=()
i=0
while [[ $i -lt ${#args[@]} ]]; do
  count="${args[i]}"
  [[ $count =~ ^[123456789][0123456789]*$ ]] || bad "count value=$count"
  [[ $((i + 1 + count)) -le ${#args[@]} ]] || bad "step=short"
  starts+=("$((i + 1))")
  counts+=("$count")
  i=$((i + 1 + count))
done
[[ ${#starts[@]} -gt 0 ]] || bad "steps=missing"

if [[ $elevator == build ]]; then
  [[ -z ${VGS_TUI_SUDO_SESSION:-} ]] || bad outer-credential-session
  if command -v sudo >/dev/null; then vgs_tui_sudo_session guard; fi
fi
if [[ $elevator == sudo ]]; then
  vgs_tui_sudo_session start || exit 1
fi
for k in "${!starts[@]}"; do
  step=("${prefix[@]}" "${args[@]:${starts[k]}:${counts[k]}}")
  vgs_tui_step 'Run this step to make the selected software change.'
  printf -v shown '%q ' "${step[@]}"
  vgs_tui_commands "${shown% }"
  status=0
  [[ -z $evidence ]] || vgs_tui_interval_open
  "${step[@]}" || status=$?
  if [[ $status -ne 0 && -n $evidence ]]; then
    cut=skipped
    if [[ $status -lt 128 ]]; then
      if vgs_tui_interval_cut "$evidence/interval"; then cut=ok; else cut="$vgs_tui_unread"; fi
    fi
    printf 'step=%d status=%d cut=%s\n' "$((k + 1))" "$status" "$cut" >"$evidence/result"
  fi
  # The sudo session's EXIT trap drops the credential on the way out.
  [[ $status -eq 0 ]] || exit "$status"
done
if [[ $elevator == sudo ]]; then
  vgs_tui_sudo_session end || exit 1
fi
exit 0
