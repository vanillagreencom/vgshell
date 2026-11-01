#!/usr/bin/env bash
# The package owner's same-terminal review and retry questions. Only
# submitted choice values reach stdout; cancellation propagates without
# becoming consent.
set -euo pipefail
# shellcheck source=SCRIPTDIR/tui.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/tui.sh"

# gum 2.0.2's fixed-grey key help misses the dark-theme readability floor.
# Like vgs_tui_confirm, put themed key help in the prompt it erases.
vgs_pkg_review_choose() {
    local header=$1 help
    shift
    printf -v help '\033[22m%s↑↓ choose • Enter confirm • Esc cancel\033[0m' "$(vgs_tui_sgr "${GUM_PAGER_HELP_FOREGROUND:-}" 39)"
    vgs_tui_choose --no-show-help --header "$header"$'\n\n'"$help" "$@"
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
  # Every review kind, the editor included, draws blocks under the caller's
  # screen and clears none of it, so the caller's plan and log path stay
  # above the review and its next step follows it.
  customize)
    # shellcheck source=SCRIPTDIR/pkg-review-settings.sh
    source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/pkg-review-settings.sh"
    vgs_pkg_review_settings "$1" inline ;;
  offer)
    vgs_tui_step 'Review third-party packages' >&2
    vgs_tui_text "${2:-Package source information is unavailable.}" >&2
    vgs_tui_text 'An AI agent can check these packages before installation.' >&2
    vgs_pkg_review_choose 'Review before installation?' --selected "$1" -- Review 'Install without review' ;;
  # PACKAGES, the offer's package line, when the agent choice does not
  # follow the offer that shows it.
  agent) # LABEL [PACKAGES]
    vgs_tui_step 'Choose the review agent' >&2
    [[ -z ${2:-} ]] || vgs_tui_text "$2" >&2
    vgs_tui_text 'The agent reads package sources as your user. Installation follows your review choices.' >&2
    vgs_pkg_review_choose 'Review agent' --selected "Use $1" -- "Use $1" Customize Back ;;
  # The result opens a block of its own: it may follow the agent's output.
  unavailable)
    vgs_tui_step 'Review result' >&2
    vgs_tui_warn 'The package review is unavailable or incomplete.' >&2
    vgs_pkg_review_choose 'Continue without a review?' --selected No -- No Yes ;;
  concern)
    vgs_tui_step 'Review result' >&2
    vgs_tui_warn "$1" >&2
    vgs_pkg_review_choose "Install $2 despite the review result?" --selected Skip -- Skip 'Install anyway' ;;
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
