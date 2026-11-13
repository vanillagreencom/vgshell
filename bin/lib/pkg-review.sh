#!/usr/bin/env bash
# The package owner's same-terminal review and retry questions. Only
# submitted choice values reach stdout; cancellation propagates without
# becoming consent.
set -euo pipefail
# shellcheck source=SCRIPTDIR/tui.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/tui.sh"

vgs_pkg_review_choose() {
    local header=$1
    shift
    vgs_tui_choose --no-show-help --header "$header" "$@"
}

# A command block under its heading, each word shell-quoted only where the
# shell would read it otherwise.
vgs_pkg_review_command() { # HEADING WORD...
    local shown
    vgs_tui_step "$1" >&2
    shift
    printf -v shown '%q ' "$@"
    vgs_tui_commands "${shown% }" >&2
}

kind="${1:-}"
shift
case "$kind" in
  agent-run) # OUTPUT COMMAND ARG...
    vgs_tui_transcript "$kind" "$@"
    capture=$1
    shift
    status=0
    vgs_tui_interval_open
    "$@" || status=$?
    vgs_tui_interval_cut "$capture" || :
    exit "$status" ;;
  settings-open)
    # A desktop caller opens the page, including from its own terminal.
    # The runner judges transport errors; this caller requires the page's ok.
    # shellcheck source=SCRIPTDIR/ipc-reply.sh
    source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/ipc-reply.sh"
    reply="$("$1" ipc call shell summon window vgs.system '{"pane":"vgs.packages"}')" || exit $?
    vgs_ipc_last_line_into "$reply"
    vgs_ipc_strip_into "$vgs_ipc_last_line"
    if [[ $vgs_ipc_stripped != ok ]]; then
      printf 'vgshell: refused: review-settings=open-unconfirmed\nVGS could not open the Packages page. Close any open question, then try again.\n' >&2
      exit 1
    fi
    ;;
  settings-ipc)
    # Raw vgshell ipc preserves qs log lines. Use its existing reply owner
    # before a persisted write can be reported as confirmed.
    # shellcheck source=SCRIPTDIR/ipc-reply.sh
    source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/ipc-reply.sh"
    status=0
    reply="$("$1" ipc call config packageReviewWrite "$2")" || status=$?
    vgs_ipc_last_line_into "$reply"
    vgs_ipc_strip_into "$vgs_ipc_last_line"
    printf '%s\n' "$vgs_ipc_stripped"
    exit "$status" ;;
  settings)
    # shellcheck source=SCRIPTDIR/pkg-review-settings.sh
    source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/pkg-review-settings.sh"
    vgs_pkg_review_settings "$1" ;;
  # Review questions retain the caller's plan and log above their blocks.
  offer) # SELECTED PACKAGES
    vgs_tui_step 'Review AUR packages' >&2
    vgs_tui_text "${2:-Package source information is unavailable.}" >&2
    vgs_pkg_review_choose 'Review before installation?' --selected "$1" -- Review 'Install without review' ;;
  result)
    vgs_tui_step 'Review result' >&2
    vgs_tui_text "$1" >&2 ;;
  # The result opens a block of its own: it may follow the agent's output.
  unavailable)
    vgs_tui_step 'Review result' >&2
    vgs_tui_text "$1" >&2
    vgs_pkg_review_choose 'Continue without a review?' --selected No -- No Yes ;;
  agent-failed) # LABEL LAST_LINE OTHER_LABEL
    vgs_tui_step 'Review result' >&2
    vgs_tui_warn "The $1 review stopped without a result. Its last line: $2" >&2
    if [[ -n ${3:-} ]]; then
      vgs_pkg_review_choose 'Review AUR packages' --selected "Use $3" -- "Use $3" 'Install without review' 'Skip AUR packages'
    else
      vgs_pkg_review_choose 'Review AUR packages' --selected 'Skip AUR packages' -- 'Install without review' 'Skip AUR packages'
    fi ;;
  flagged) # NAMES CONCERNS
    vgs_tui_step 'Review result' >&2
    vgs_tui_warn "$2" >&2
    vgs_pkg_review_choose 'Install flagged packages?' --selected "Skip $1" -- "Skip $1" 'Install anyway' Stop ;;
  # A build whose own tests alone failed (PackageReview.classifyInstallFailure):
  # the one retry without them, which the helper also applies to every
  # dependency it builds, or Stop.
  retry) # PACKAGE
    vgs_tui_step 'Package tests failed' >&2
    vgs_tui_warn "The tests in $1 failed. This build was not installed." >&2
    vgs_tui_text 'This retry skips package tests, including tests for any dependency the helper builds. It does not turn off source checks.' >&2
    vgs_pkg_review_choose "Retry $1 without tests?" --selected Stop -- 'Retry without tests' Stop ;;
  show) vgs_pkg_review_command "$@" ;;
  *) exit 2 ;;
esac
