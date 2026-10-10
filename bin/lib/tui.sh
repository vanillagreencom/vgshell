# shellcheck shell=bash
# bin/lib/tui.sh: the floating TUI presentation library. A script that
# bin/vgshell-tui runs sources it as `source "$VGS_TUI_LIB"`; bin/vgshell-tui
# sources it for its own colours. It defines functions and sets no shell
# option. Colours are the #rrggbb values `vgshell-tui present` exports from
# gum.env (VGS_TUI_ACCENT, VGS_TUI_SUCCESS, VGS_TUI_WARNING, VGS_TUI_DANGER),
# each with an ANSI fallback when absent or empty.
#
# Every refusal prints one keyed line on stderr first:
# `vgs-tui: refused: <key>=<value>`. A function that refuses returns 2 for a
# missing terminal or a bad argument, 75 for a held lock, 1 otherwise.
#
#   vgs_tui_header TITLE [LINE...]   one blank line, then a bordered box:
#                                    TITLE, then each LINE, wrapped to fit
#                                    the terminal
#   vgs_tui_step TEXT                a bold accent line after a blank line
#   vgs_tui_success TEXT             a success line after a blank line
#   vgs_tui_warn TEXT                a warning line on stderr
#   vgs_tui_error TEXT               an error line on stderr
#   vgs_tui_confirm QUESTION [GUM_FLAG...]
#                                    gum confirm; yes under VGS_TUI_UNATTENDED=1
#   vgs_tui_choose|input|filter [GUM_ARG...]
#                                    gum choose, input or filter
#   vgs_tui_gum_env ARRAY            set ARRAY to NAME=VALUE for each exported
#                                    colour or bold variable gum reads, an empty
#                                    colour, gum's no colour, included, and TERM and
#                                    COLORTERM: the words a script that runs gum
#                                    under `env -i` hands gum, so it keeps the
#                                    presenter's colours and the terminal's
#                                    colour support
#   vgs_tui_sudo_session start|guard|end
#                                    one sudo authorization kept alive for this script,
#                                    joined by a nested run's session; guard only drops
#                                    the credential when the script ends
#   vgs_tui_lock NAME                hold $XDG_RUNTIME_DIR/vgs-tui-NAME.lock until exit
#   vgs_tui_log FILE [ARG...]        run this script again under script(1) into FILE,
#                                    keeping SGR colour and dropping terminal controls
#   vgs_tui_logged FILE COMMAND [ARG...]
#                                    run COMMAND with its stderr added to FILE, so its
#                                    keyed causes reach the log and not the screen;
#                                    COMMAND's status
#   vgs_tui_note FILE LINE           add LINE, a keyed cause, to the log FILE
#   vgs_tui_failed FILE LINE...      an error line per LINE, then a line naming FILE,
#                                    the log that holds the cause, with $HOME as ~
#   vgs_tui_refuse FILE STATUS KEY_LINE SENTENCE...
#                                    KEY_LINE to the log FILE, the SENTENCEs and the
#                                    log's name on the screen, as vgs_tui_failed;
#                                    returns STATUS
#   vgs_tui_columns                  the terminal's width in columns, 80 when it
#                                    reports none
#   vgs_tui_reboot_check             print why a reboot is needed; 1 when none is
#   vgs_tui_close_prompt CODE [MARKER]
#                                    `● Done!` for 0, `● Failed (exit code CODE)!`
#                                    otherwise, and one key, or MARKER's removal
#                                    when given, on /dev/tty; nothing for 130, a
#                                    Ctrl-C, or with no terminal

# Character classes spelled out: a range such as [a-z] follows the collation
# of the user's locale, which the script under the presentation keeps.
_vgs_tui_hex='[0123456789abcdefABCDEF]'
_vgs_tui_lower='[abcdefghijklmnopqrstuvwxyz0123456789]'
_vgs_tui_upper='[ABCDEFGHIJKLMNOPQRSTUVWXYZ]'
# The style variables gum reads, each an unanchored alternation: its colour
# names, whose value is #rrggbb or empty, and its bold names, whose value
# is true. One rule for what bin/vgshell-tui present accepts from gum.env,
# beside its own VGS_TUI_ names, and for what vgs_tui_gum_env hands gum.
# Only styles: a GUM_ behaviour option from the session, such as
# GUM_CONFIRM_TIMEOUT, could answer a prompt for the user.
_vgs_tui_gum_colours="GUM_($_vgs_tui_upper|_)+_(FOREGROUND|BACKGROUND)|FOREGROUND|BACKGROUND|BORDER_FOREGROUND"
_vgs_tui_gum_bolds="GUM_($_vgs_tui_upper|_)+_BOLD"
_vgs_tui_gum_names="$_vgs_tui_gum_colours|$_vgs_tui_gum_bolds"

# The SGR escape that selects colour HEX (#rrggbb) as the foreground, or the
# ANSI colour FALLBACK (30-37) when HEX is not one.
vgs_tui_sgr() { # HEX FALLBACK
  local hex="$1"
  if [[ $hex =~ ^#($_vgs_tui_hex$_vgs_tui_hex)($_vgs_tui_hex$_vgs_tui_hex)($_vgs_tui_hex$_vgs_tui_hex)$ ]]; then
    printf '\033[38;2;%d;%d;%dm' "0x${BASH_REMATCH[1]}" "0x${BASH_REMATCH[2]}" "0x${BASH_REMATCH[3]}"
  else
    printf '\033[%sm' "$2"
  fi
}

_vgs_tui_refuse() { # STATUS FIRST_LINE [ENGLISH...]
  local status="$1"
  printf 'vgs-tui: refused: %s\n' "$2" >&2
  shift 2
  [[ $# -gt 0 ]] && printf '%s\n' "$@" >&2
  return "$status"
}

# gum draws on the controlling terminal and reads the keyboard there, even
# when stdin carries a list and stdout is captured, so the terminal is
# /dev/tty. The device node exists without one, so only opening it tells.
_vgs_tui_has_terminal() { : 2>/dev/null <>/dev/tty; }
_vgs_tui_terminal() { # KEY
  _vgs_tui_has_terminal || _vgs_tui_refuse 2 "$1=no-terminal" "run this in a terminal"
}
_vgs_tui_prompt_gap() { printf '\n' >&2; }
_vgs_tui_header_gap() { printf '\n'; }

# gum sizes the box to its longest line, and the terminal wraps a row wider
# than itself, which breaks the border on every row. A line that does not fit
# beside the border and padding, 6 columns, gives the box the terminal's
# width: gum 2.0.2 counts the border and padding inside --width and wraps the
# lines at word boundaries within it. A box that fits keeps its own width.
vgs_tui_header() { # TITLE [LINE...]
  local columns line width=()
  columns="$(vgs_tui_columns)"
  for line; do
    if (( ${#line} + 6 > columns )); then width=(--width "$columns"); break; fi
  done
  _vgs_tui_header_gap
  gum style --border normal --padding "1 2" "${width[@]}" -- "$@"
}

vgs_tui_step() { # TEXT
  printf '\n%s\033[1m%s\033[0m\n' "$(vgs_tui_sgr "${VGS_TUI_ACCENT:-}" 32)" "$*"
}

vgs_tui_success() { # TEXT
  printf '\n%s%s\033[0m\n' "$(vgs_tui_sgr "${VGS_TUI_SUCCESS:-}" 32)" "$*"
}

vgs_tui_warn() { # TEXT
  printf '%s%s\033[0m\n' "$(vgs_tui_sgr "${VGS_TUI_WARNING:-}" 33)" "$*" >&2
}

vgs_tui_error() { # TEXT
  printf '%s%s\033[0m\n' "$(vgs_tui_sgr "${VGS_TUI_DANGER:-}" 31)" "$*" >&2
}

# Answers yes without asking under VGS_TUI_UNATTENDED=1 and prints the
# question with that answer. Otherwise gum asks; its status is the answer:
# 0 yes, 1 no, 130 cancelled.
vgs_tui_confirm() { # QUESTION [GUM_FLAG...]
  local question="$1"
  shift
  if [[ ${VGS_TUI_UNATTENDED:-} == 1 ]]; then
    printf '\n%s yes (unattended)\n' "$question"
    return 0
  fi
  _vgs_tui_terminal confirm || return
  _vgs_tui_prompt_gap
  gum confirm "$@" -- "$question"
}

vgs_tui_choose() { _vgs_tui_terminal choose || return; _vgs_tui_prompt_gap; gum choose "$@"; }
vgs_tui_input() { _vgs_tui_terminal input || return; _vgs_tui_prompt_gap; gum input "$@"; }
vgs_tui_filter() { _vgs_tui_terminal filter || return; _vgs_tui_prompt_gap; gum filter "$@"; }

vgs_tui_gum_env() { # ARRAY
  local -n _vgs_tui_words="$1"
  local name
  _vgs_tui_words=()
  while IFS= read -r name; do
    if [[ $name =~ ^($_vgs_tui_gum_names|TERM|COLORTERM)$ ]]; then _vgs_tui_words+=("$name=${!name}"); fi
  done < <(compgen -e)
}

_vgs_tui_keepalive_pid=""
_vgs_tui_lock_fd=""
_vgs_tui_sudo_joined=""

# start drops any cached sudo credential, asks for the password once through
# `sudo /usr/bin/true` (sudo -v would prompt under a passwordless rule too)
# and keeps the credential fresh with `sudo -n /usr/bin/true` every 60 s
# while this script's process lives. It exports VGS_TUI_SUDO_SESSION, this
# process's pid, to every command the script runs. From then on EXIT, HUP,
# INT and TERM end the session: those traps replace any the caller set
# before. end stops the keepalive, clears those traps, drops the credential
# and unexports the pid.
#
# A start in a process whose VGS_TUI_SUDO_SESSION names a live process joins
# that session: it drops nothing, starts no keepalive and sets no trap, and
# its `sudo /usr/bin/true` answers from the owner's credential, asking only
# when it lapsed; its end drops nothing. The Updates pipeline runs
# `vgshell pkg run upgrade` inside its own session, and that run's end would
# otherwise revoke the credential the pipeline's later steps use. A pid that
# names no live process, as a command a step started that outlives the
# owner carries, starts a session of its own.
#
# guard asks for nothing and keeps nothing alive: it sets the traps start
# sets, so a credential a later command caches is dropped however the
# script ends, and end drops it and clears them. The Updates pipeline
# guards its AUR steps, which run after its session ends and whose helper
# asks sudo for itself. A script guards only while it holds no session.
vgs_tui_sudo_session() { # start|guard|end
  case "${1:-}" in
    start)
      local outer="${VGS_TUI_SUDO_SESSION:-}"
      if [[ $outer =~ ^[123456789][0123456789]*$ ]] && kill -0 "$outer" 2>/dev/null; then
        sudo /usr/bin/true || _vgs_tui_refuse 1 "sudo=not-authorized" || return
        _vgs_tui_sudo_joined=1
        return 0
      fi
      sudo -k || _vgs_tui_refuse 1 "sudo=reset-failed" || return
      sudo /usr/bin/true || _vgs_tui_refuse 1 "sudo=not-authorized" || return
      local owner=$$
      (
        [[ -z $_vgs_tui_lock_fd ]] || exec {_vgs_tui_lock_fd}>&-
        sleeper=""
        trap '[[ -z $sleeper ]] || kill "$sleeper" 2>/dev/null; exit 0' TERM
        while :; do
          sleep 60 &
          sleeper=$!
          wait "$sleeper"
          kill -0 "$owner" 2>/dev/null || exit 0
          sudo -n /usr/bin/true 2>/dev/null || exit 0
        done
      ) </dev/null &
      _vgs_tui_keepalive_pid=$!
      export VGS_TUI_SUDO_SESSION=$$
      _vgs_tui_sudo_traps
      ;;
    guard) _vgs_tui_sudo_traps ;;
    end)
      if [[ -n $_vgs_tui_sudo_joined ]]; then
        _vgs_tui_sudo_joined=""
        return 0
      fi
      unset VGS_TUI_SUDO_SESSION
      # The keepalive may have exited already, when sudo -n refused.
      if [[ -n $_vgs_tui_keepalive_pid ]]; then
        kill "$_vgs_tui_keepalive_pid" 2>/dev/null || :
        wait "$_vgs_tui_keepalive_pid" 2>/dev/null || :
        _vgs_tui_keepalive_pid=""
      fi
      trap - EXIT HUP INT TERM
      sudo -k || _vgs_tui_refuse 1 "sudo=revoke-failed" "the sudo credential may still be cached; run sudo -k"
      ;;
    *) _vgs_tui_refuse 2 "sudo-session=${1:-missing}" ;;
  esac
}

# EXIT ends the session; HUP, INT and TERM exit with 128 plus the signal's
# number, which runs EXIT.
_vgs_tui_sudo_traps() {
  trap 'vgs_tui_sudo_session end' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

# NAME is lower case letters, digits and dashes. The lock is held on a
# descriptor until this process exits; a second holder is refused busy.
# Call vgs_tui_log first: its script(1) run would inherit the descriptor
# and hold the lock against the script it runs.
vgs_tui_lock() { # NAME
  local name="${1:-}" path status=0
  [[ $name =~ ^$_vgs_tui_lower($_vgs_tui_lower|-)*$ ]] || _vgs_tui_refuse 2 "lock-name=$name" || return
  path="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/vgs-tui-$name.lock"
  { exec {_vgs_tui_lock_fd}>>"$path"; } 2>/dev/null || _vgs_tui_refuse 1 "lock=$name reason=open path=$path" || return
  flock -n -E 75 "$_vgs_tui_lock_fd" || status=$?
  case "$status" in
    0) ;;
    75) _vgs_tui_refuse 75 "lock=$name reason=busy" "another run holds $path" ;;
    *) _vgs_tui_refuse 1 "lock=$name reason=flock-failed path=$path" ;;
  esac
}

# Drops controls that gum writes around prompts while keeping SGR colour.
_vgs_tui_log_clean() {
  LC_ALL=C sed -u -E \
    -e $'s/\e\\][^\a\e]*(\a|\e\\\\)//g' \
    -e $'s/\e\\[[0-9;:]*[<=>?][0-?]*[ -/]*[@-~]//g' \
    -e $'s/\e\\[[0-9;:]*[ -/]+[@-~]//g' \
    -e $'s/\e\\[[0-9;:]*[@-ln-~]//g' \
    -e $'s/\e[ -/]*[0-Z\\\\^-~]//g' \
    -e $'s/\r+$//' \
    -e $'s/^.*\r//'
}

# Runs this script again, with ARGs, under script(1) logging clean text to
# FILE, so the terminal shows the run and FILE keeps a copy, and exits with
# that run's status; inside the run it returns at once. script(1) hands the
# command line to $SHELL, so SHELL is bash there, which reads the %q quoting.
vgs_tui_log() { # FILE [ARG...]
  [[ ${VGS_TUI_LOGGED:-} == 1 ]] && return 0
  local file="${1:-}" cmd fd status=0
  [[ -n $file ]] || _vgs_tui_refuse 2 "log=missing" || return
  shift
  cmd="$(printf '%q ' "$BASH" "$0" "$@")"
  exec {fd}>"$file" || _vgs_tui_refuse 1 "log=$file reason=open-failed" || return
  env VGS_TUI_LOGGED=1 SHELL="$BASH" script -qef --log-out >(_vgs_tui_log_clean >&"$fd") -c "$cmd" {fd}>&- || status=$?
  exec {fd}>&-
  wait "$!" || :
  exit "$status"
}

# FILE's directory is made when absent. A FILE that cannot be opened is
# refused before COMMAND runs.
vgs_tui_logged() { # FILE COMMAND [ARG...]
  local file="${1:-}"
  [[ -n $file && $# -ge 2 ]] || _vgs_tui_refuse 2 "logged=missing" || return
  shift
  { mkdir -p -- "$(dirname -- "$file")" && : >>"$file"; } 2>/dev/null ||
    _vgs_tui_refuse 1 "logged=$file reason=open-failed" || return
  "$@" 2>>"$file"
}

_vgs_tui_keyed() { printf '%s\n' "$1" >&2; }
vgs_tui_note() { vgs_tui_logged "$1" _vgs_tui_keyed "$2"; } # FILE LINE

vgs_tui_failed() { # FILE LINE...
  local file="$1" line
  shift
  for line; do vgs_tui_error "$line"; done
  vgs_tui_error "The details are in ${file/#"$HOME"/\~}."
}

vgs_tui_refuse() { # FILE STATUS KEY_LINE SENTENCE...
  local file="$1" refused="$2"
  vgs_tui_note "$file" "$3" || :
  shift 3
  vgs_tui_failed "$file" "$@"
  return "$refused"
}

# stty prints 0 columns for a terminal nobody gave a size, such as a
# pseudo-terminal a test opens.
vgs_tui_columns() {
  local size
  size="$(stty size </dev/tty 2>/dev/null)" || size=""
  size="${size##* }"
  [[ $size =~ ^[123456789][0123456789]*$ ]] || size=80
  printf '%s\n' "$size"
}

# The presenter's closing prompt, which a `plain` script that fails calls
# itself, since the presenter shows it only under the full presentation. It
# goes to /dev/tty, so a redirected caller still shows it. Replies to
# queries the command sent the terminal are still queued on the tty and
# would answer the keypress for the user, so they are dropped first. With
# MARKER, a file the caller made, the prompt also ends once the file is
# gone: the key is read with a 0.2 s timeout and the file looked for
# between reads, so a later run can close a window that waits here.
vgs_tui_close_prompt() { # CODE [MARKER]
  local code="$1" marker="${2:-}" status
  [[ $code != 130 ]] || return 0
  _vgs_tui_has_terminal || return 0
  while read -rsn 1 -t 0.1 _ </dev/tty; do :; done
  if [[ $code == 0 ]]; then
    printf '\n%s● \033[0mDone! Press any key to close...' "$(vgs_tui_sgr "${VGS_TUI_SUCCESS:-}" 32)" >/dev/tty
  else
    printf '\n%s● \033[0mFailed (exit code %d)! Press any key to close...' "$(vgs_tui_sgr "${VGS_TUI_DANGER:-}" 31)" "$code" >/dev/tty
  fi
  if [[ -n $marker ]]; then
    while [[ -e $marker ]]; do
      status=0
      read -rsn 1 -t 0.2 _ </dev/tty || status=$?
      # Above 128 is the timeout; any other end is a key, or a terminal
      # that can no longer be read.
      [[ $status -gt 128 ]] || break
    done
  else
    read -rsn 1 _ </dev/tty || :
  fi
  printf '\n' >/dev/tty
}

# Prints one `reboot=<reason>` line per reason and returns 0 when a reboot
# is needed, 1 when none is: `kernel` when the running kernel's module
# directory is gone, as after a kernel upgrade; `hyprland` when a Hyprland
# of this user runs a binary that was replaced.
vgs_tui_reboot_check() {
  local release pids pid exe status=0 reasons=()
  release="$(uname -r)" || _vgs_tui_refuse 1 "reboot-check=uname" || return
  [[ -d /lib/modules/$release ]] || reasons+=(kernel)
  # pgrep exits 1 when no process matches, and above 1 when it failed.
  pids="$(pgrep -x -u "$(id -u)" Hyprland)" || status=$?
  [[ $status -le 1 ]] || _vgs_tui_refuse 1 "reboot-check=pgrep exit=$status" || return
  for pid in $pids; do
    exe="$(readlink "/proc/$pid/exe" 2>/dev/null)" || continue
    if [[ $exe == *' (deleted)' ]]; then reasons+=(hyprland); break; fi
  done
  [[ ${#reasons[@]} -gt 0 ]] || return 1
  printf 'reboot=%s\n' "${reasons[@]}"
}
