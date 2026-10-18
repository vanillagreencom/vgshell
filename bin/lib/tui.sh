# shellcheck shell=bash
# bin/lib/tui.sh: the floating TUI presentation library. A script that
# bin/vgshell-tui runs sources it as `source "$VGS_TUI_LIB"`; bin/vgshell-tui
# sources it for its own colours. It defines functions and sets no shell
# option. Colours are the #rrggbb values `vgshell-tui present` exports from
# gum.env (VGS_TUI_ACCENT, VGS_TUI_SUCCESS, VGS_TUI_WARNING, VGS_TUI_DANGER,
# and gum's GUM_PAGER_HELP_FOREGROUND for the confirm's key help), each with
# an ANSI fallback when absent or empty.
#
# Every refusal prints one keyed line on stderr first:
# `vgs-tui: refused: <key>=<value>`. A function that refuses returns 2 for a
# missing terminal or a bad argument, 75 for a held lock, 1 otherwise.
#
# Every line the library draws outside the header's box, the question and
# its buttons included, starts at the box's content edge and wraps at
# spaces before the same edge on the right; vgs_tui_split passes a redrawn
# progress line as it is.
#
#   vgs_tui_header TITLE [LINE...]   one blank line, then a bordered box:
#                                    TITLE, then each LINE, wrapped to fit
#                                    the terminal
#   vgs_tui_clear                    clear the screen; the next block starts
#                                    on its first row, with no blank line
#   vgs_tui_text TEXT                TEXT in the terminal's own colour, each of
#                                    its lines wrapped at the content edges
#   vgs_tui_commands COMMAND...      a left-marked block, one blank marked row
#                                    between commands; wraps at spaces with
#                                    a continuation mark, never inside a word
#   vgs_tui_step TEXT                a bold accent line after a blank line
#   vgs_tui_success TEXT             a success line after a blank line
#   vgs_tui_warn TEXT                a warning line on stderr
#   vgs_tui_error TEXT               an error line on stderr
#   vgs_tui_cancelled TEXT           print TEXT and, when there is a terminal,
#                                    wait for one key to close
#   vgs_tui_confirm QUESTION [GUM_FLAG...]
#                                    gum confirm under a key help line in the
#                                    theme; yes under VGS_TUI_UNATTENDED=1
#   vgs_tui_choose|input|filter [GUM_ARG...]
#                                    gum choose, input or filter
#   vgs_tui_edit FILE [LINE]         VISUAL, then EDITOR, else a choice of
#                                    installed editors; the editor's status
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
#                                    keeping SGR colour and dropping terminal controls;
#                                    the run reads its unchanged output at
#                                    $VGS_TUI_TRANSCRIPT
#   vgs_tui_logged FILE COMMAND [ARG...]
#                                    run COMMAND with its stderr added to FILE, so its
#                                    keyed causes reach the log and not the screen;
#                                    COMMAND's status
#   vgs_tui_split FILE KEY COMMAND [ARG...]
#                                    run COMMAND with stdout and stderr merged; append
#                                    lines that start with `KEY: ` to FILE, and show
#                                    every other line on stdout; COMMAND's status
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
#                                    `● Done.` for 0, no word for 69, a refusal
#                                    before anything ran, `● The task failed.`
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
  _vgs_tui_has_terminal || _vgs_tui_refuse 2 "$1=no-terminal" "This task needs a terminal. Open it again from VGS."
}
# _vgs_tui_gap_left marks a row that already stands where a block's blank
# line would go: the blank line above a question, which gum leaves when it
# erases the answered question, the top of a cleared screen, or the blank
# row under the logo, which bin/vgshell-tui hands the script it runs as
# VGS_TUI_GAP_LEFT=1. The next blank line is then not drawn, and every
# library write clears the mark. A line a program the script runs itself
# writes does not clear it. The hand-off reaches only the first script that
# sources the library, so a script that one runs draws its own blank line.
_vgs_tui_gap_left="${VGS_TUI_GAP_LEFT:-}"
unset VGS_TUI_GAP_LEFT
_vgs_tui_gap() {
  [[ -n $_vgs_tui_gap_left ]] || printf '\n'
  _vgs_tui_gap_left=""
}
_vgs_tui_prompt_gap() { _vgs_tui_gap >&2; }
_vgs_tui_header_gap() { _vgs_tui_gap; }

# The header's content edge: its border and left padding, in columns. Every
# line the library draws outside the box starts there and ends that far
# from the right edge, so text and the question's buttons line up with the
# text inside the box.
_vgs_tui_edge=3
_vgs_tui_sgr_rule=$'\e''\[[0123456789;:]*m'

# The width a line has between the content edges, 1 at least.
_vgs_tui_width() {
  local width=$(( $(vgs_tui_columns) - 2 * _vgs_tui_edge ))
  (( width > 0 )) || width=1
  printf '%s\n' "$width"
}

_vgs_tui_visible() { # VAR TEXT: TEXT's columns, its SGR escapes taking none
  local -n _vgs_tui_count="$1"
  local text="$2"
  while [[ $text =~ $_vgs_tui_sgr_rule ]]; do text="${text/"${BASH_REMATCH[0]}"/}"; done
  _vgs_tui_count=${#text}
}

# ARRAY gets TEXT's lines broken to WIDTH columns at the last space that
# fits. The spaces at a break are dropped, so no continuation starts with
# one; a line's own leading spaces stay, and a word wider than WIDTH breaks
# inside it, unless MODE is commands, which keeps each word whole.
# _vgs_tui_wrapped records which rows continue a width break.
_vgs_tui_lines() { # ARRAY WIDTH TEXT [MODE]
  local -n _vgs_tui_out="$1"
  local width="$2" text="$3" line rest lead word gap cur cur_n word_n started wrapped more=1
  _vgs_tui_out=()
  _vgs_tui_wrapped=()
  while (( more )); do
    line="${text%%$'\n'*}"
    if [[ $text == *$'\n'* ]]; then text="${text#*$'\n'}"; else more=0; fi
    lead="${line%%[! ]*}"
    rest="${line#"$lead"}"
    cur="$lead" cur_n=${#lead} started="" gap="" wrapped=0
    while [[ -n $rest ]]; do
      word="${rest%% *}"
      rest="${rest#"$word"}"
      _vgs_tui_visible word_n "$word"
      if [[ -n $started ]] && (( cur_n + ${#gap} + word_n <= width )); then
        cur+="$gap$word" cur_n=$(( cur_n + ${#gap} + word_n ))
      else
        if [[ -n $started ]]; then _vgs_tui_wrapped+=("$wrapped"); wrapped=1; fi
        if [[ -n $started ]]; then _vgs_tui_out+=("$cur"); cur="" cur_n=0; fi
        while [[ ${4:-text} != commands ]] && (( cur_n + word_n > width )); do
          if [[ $word =~ ^$_vgs_tui_sgr_rule ]]; then
            cur+="${BASH_REMATCH[0]}" word="${word#"${BASH_REMATCH[0]}"}"
          elif (( cur_n == width )); then
            _vgs_tui_out+=("$cur"); cur="" cur_n=0
            _vgs_tui_wrapped+=("$wrapped"); wrapped=1
          else
            cur+="${word:0:1}" word="${word:1}" cur_n=$(( cur_n + 1 )) word_n=$(( word_n - 1 ))
          fi
        done
        cur+="$word" cur_n=$(( cur_n + word_n ))
      fi
      started=1
      gap="${rest%%[! ]*}"
      rest="${rest#"$gap"}"
    done
    _vgs_tui_out+=("$cur")
    _vgs_tui_wrapped+=("$wrapped")
  done
}

# Each line of TEXT, wrapped to WIDTH or the terminal's, at the content
# edge in the SGR escape; an empty line has no indent.
_vgs_tui_print() { # SGR TEXT [WIDTH]
  local lines=() line pad
  _vgs_tui_gap_left=""
  _vgs_tui_lines lines "${3:-$(_vgs_tui_width)}" "$2"
  for line in "${lines[@]}"; do
    pad=""
    [[ -z $line ]] || printf -v pad '%*s' "$_vgs_tui_edge" ''
    if [[ -n $1 ]]; then printf '%s%s%s\033[0m\n' "$pad" "$1" "$line"; else printf '%s%s\n' "$pad" "$line"; fi
  done
}

# gum sizes the box to its longest line, and the terminal wraps a row wider
# than itself, which breaks the border on every row. A line that does not fit
# beside the border and padding, 6 columns, gives the box the terminal's
# width: gum 2.0.2 counts the border and padding inside --width and wraps the
# lines at word boundaries within it. A box that fits keeps its own width.
vgs_tui_header() { # TITLE [LINE...]
  local columns line title title_line width=()
  columns="$(vgs_tui_columns)"
  title_line="$1"
  shift
  for line in "$title_line" "$@"; do
    if (( ${#line} + 6 > columns )); then width=(--width "$columns"); break; fi
  done
  printf -v title '\033[1m%s\033[0m' "$title_line"
  _vgs_tui_header_gap
  gum style --border normal --padding "1 2" "${width[@]}" -- "$title" "$@"
}

vgs_tui_clear() { printf '\033[H\033[2J'; _vgs_tui_gap_left=1; }

vgs_tui_text() { # TEXT
  _vgs_tui_print "" "$*"
}

vgs_tui_commands() { # COMMAND...
  local lines=() command line i width first=1 continued pad
  width=$(( $(_vgs_tui_width) - 4 ))
  (( width > 0 )) || width=1
  printf -v pad '%*s' "$_vgs_tui_edge" ''
  _vgs_tui_gap_left=""
  for command; do
    (( first )) || printf '%s│\n' "$pad"
    first=0 continued=""
    _vgs_tui_lines lines "$width" "$command" commands
    for i in "${!lines[@]}"; do
      line="${lines[i]}" continued=""
      [[ ${_vgs_tui_wrapped[i]} == 1 ]] && continued='↳ '
      printf '%s│ %s%s\n' "$pad" "$continued" "$line"
    done
  done
}

vgs_tui_step() { # TEXT
  _vgs_tui_gap
  _vgs_tui_print "$(vgs_tui_sgr "${VGS_TUI_ACCENT:-}" 32)"$'\033[1m' "$*"
}

vgs_tui_success() { # TEXT
  _vgs_tui_gap
  _vgs_tui_print "$(vgs_tui_sgr "${VGS_TUI_SUCCESS:-}" 32)" "$*"
}

vgs_tui_warn() { # TEXT
  _vgs_tui_print "$(vgs_tui_sgr "${VGS_TUI_WARNING:-}" 33)" "$*" >&2
}

vgs_tui_error() { # TEXT
  _vgs_tui_print "$(vgs_tui_sgr "${VGS_TUI_DANGER:-}" 31)" "$*" >&2
}

vgs_tui_cancelled() { # TEXT
  vgs_tui_text "$*"
  _vgs_tui_has_terminal || return 0
  _vgs_tui_drain_terminal
  printf '\n%*s%s● \033[0mPress any key to close.' "$_vgs_tui_edge" '' "$(vgs_tui_sgr "${VGS_TUI_ACCENT:-}" 36)" >/dev/tty
  read -rsn 1 _ </dev/tty || return 0
  printf '\n' >/dev/tty
}

# Answers yes without asking under VGS_TUI_UNATTENDED=1 and prints the
# question with that answer. Otherwise gum asks; its status is the answer:
# 0 yes, 1 no, 130 cancelled.
#
# gum 2.0.2 draws its own key help in fixed greys no GUM_ variable themes,
# under 4.5 to 1 on a dark background, so gum's is off. The key help goes
# in gum's prompt instead, one blank line under the question, so it sits
# above the Yes and No row it explains, in the gum target's help colour,
# GUM_PAGER_HELP_FOREGROUND, or the terminal's own text colour without one.
# gum erases its whole view, prompt included, once the question is
# answered, and nothing gum draws can go below the buttons: its first write
# erases the screen from the cursor down. Checked in private tmux runs of
# gum 2.0.2 for VGS-1492 on 2026-10-12.
vgs_tui_confirm() { # QUESTION [GUM_FLAG...]
  local question="$1" flag previous="" yes=Yes no=No help lines=() margin answer=0
  shift
  if [[ ${VGS_TUI_UNATTENDED:-} == 1 ]]; then
    printf '\n'
    _vgs_tui_print "" "$question Yes (automatic answer)."
    return 0
  fi
  _vgs_tui_terminal confirm || return
  for flag; do
    case "$previous" in --affirmative) yes="$flag" ;; --negative) no="$flag" ;; esac
    case "$flag" in --affirmative=*) yes="${flag#*=}" ;; --negative=*) no="${flag#*=}" ;; esac
    previous="$flag"
  done
  printf -v help '\033[22m%s←→ choose • Enter confirm • y %s • n %s\033[0m' \
    "$(vgs_tui_sgr "${GUM_PAGER_HELP_FOREGROUND:-}" 39)" "$yes" "$no"
  # gum 2.0.2 cuts a question wider than the terminal at its last column,
  # seen in a script(1) run for VGS-1521 on 2026-10-12, so it is wrapped
  # here to the content edges.
  _vgs_tui_lines lines "$(_vgs_tui_width)" "$question"
  printf -v question '%s\n' "${lines[@]}"
  margin="0 0 0 $_vgs_tui_edge"
  _vgs_tui_prompt_gap
  # gum 2.0.2 accepts these margin keys though `gum confirm --help` omits
  # them; checked in a private tmux run for VGS-1475 on 2026-10-12. The
  # same left margin on both buttons puts Yes at the edge and keeps No
  # that far from it.
  GUM_CONFIRM_SHOW_HELP=false gum confirm --prompt.margin "$margin" --selected.margin "$margin" --unselected.margin "$margin" "$@" -- "$question"$'\n'"$help" || answer=$?
  _vgs_tui_gap_left=1
  return "$answer"
}

# gum's --padding moves the header, cursor, items and key help together.
vgs_tui_choose() { _vgs_tui_terminal choose || return; _vgs_tui_prompt_gap; gum choose --padding "0 0 0 $_vgs_tui_edge" "$@"; }
vgs_tui_input() { _vgs_tui_terminal input || return; _vgs_tui_prompt_gap; gum input --padding "0 0 0 $_vgs_tui_edge" "$@"; }
vgs_tui_filter() { _vgs_tui_terminal filter || return; _vgs_tui_prompt_gap; gum filter --padding "0 0 0 $_vgs_tui_edge" "$@"; }

_vgs_tui_editor_takes_line() { # EDITOR_ARGV0
  # These terminal editors accept +LINE before the path.
  case "${1##*/}" in
    vi|vim|nvim|nano|emacs|emacsclient|micro|kak|ne|joe|mg) return 0 ;;
    *) return 1 ;;
  esac
}

# Editor variables are argv words, never shell code. VS Code's --wait (-w)
# waits for the file to close (src/vs/platform/environment/node/argv.ts),
# so omit it for the graphical launch: the floating terminal closes once
# the launcher returns, while launch errors keep their stderr and status.
vgs_tui_edit() { # FILE [LINE]
  local file="$1" selected="${VISUAL:-${EDITOR:-}}" name word
  local editor=() installed=() launch=()
  if [[ -z $selected ]]; then
    for name in nvim vim nano micro hx vi code codium code-insiders vscodium gvim; do
      command -v "$name" >/dev/null 2>&1 && installed+=("$name")
    done
    if [[ ${#installed[@]} == 0 ]]; then
      _vgs_tui_refuse 1 "editor=missing" "VGS cannot find a text editor. Install one, then open the file again."
      return
    fi
    selected="$(vgs_tui_choose --header "Choose an editor" -- "${installed[@]}")" || return
  fi
  read -r -a editor <<<"$selected"
  [[ ${#editor[@]} -gt 0 ]] || { _vgs_tui_refuse 2 "editor=empty" "The text editor setting is empty. Set a text editor for this terminal session, then open the file again."; return; }
  name="${editor[0]##*/}"
  for word in "${editor[@]:1}"; do
    case "$name:$word" in
      code:--wait|code:-w|codium:--wait|codium:-w|code-insiders:--wait|code-insiders:-w|vscodium:--wait|vscodium:-w) ;;
      *) launch+=("$word") ;;
    esac
  done
  if [[ -n ${2:-} ]] && _vgs_tui_editor_takes_line "${editor[0]}"; then launch+=("+$2"); fi
  "${editor[0]}" "${launch[@]}" "$file"
}

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
      _vgs_tui_gap_left=""
      if [[ $outer =~ ^[123456789][0123456789]*$ ]] && kill -0 "$outer" 2>/dev/null; then
        sudo /usr/bin/true || _vgs_tui_refuse 1 "sudo=not-authorized" "VGS cannot get permission to change the system. Try the action again and approve the password request." || return
        _vgs_tui_sudo_joined=1
        return 0
      fi
      sudo -k || _vgs_tui_refuse 1 "sudo=reset-failed" "VGS cannot clear sudo's saved permission. Close this task and check the sudo error above." || return
      sudo /usr/bin/true || _vgs_tui_refuse 1 "sudo=not-authorized" "VGS cannot get permission to change the system. Try the action again and approve the password request." || return
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
      sudo -k || _vgs_tui_refuse 1 "sudo=revoke-failed" "VGS cannot clear sudo's saved permission. End your session before leaving this computer."
      ;;
    *) _vgs_tui_refuse 2 "sudo-session=${1:-missing}" "VGS cannot read this task's permission request. Close this task and report the details above." ;;
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
  [[ $name =~ ^$_vgs_tui_lower($_vgs_tui_lower|-)*$ ]] || _vgs_tui_refuse 2 "lock-name=$name" "VGS cannot identify this task. Close it and report the details above." || return
  path="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/vgs-tui-$name.lock"
  { exec {_vgs_tui_lock_fd}>>"$path"; } 2>/dev/null || _vgs_tui_refuse 1 "lock=$name reason=open path=$path" "VGS cannot save this task's running state. Check access to $path, then try again." || return
  flock -n -E 75 "$_vgs_tui_lock_fd" || status=$?
  case "$status" in
    0) ;;
    75) _vgs_tui_refuse 75 "lock=$name reason=busy" "This task is already running. Finish or close its other window first." ;;
    *) _vgs_tui_refuse 1 "lock=$name reason=flock-failed path=$path" "VGS cannot check whether this task is already running. Close it and try again." ;;
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
# script(1) also logs its output unchanged, every byte the run's terminal
# received in order, to a private file in the runtime directory that the
# run finds at $VGS_TUI_TRANSCRIPT; the Updates pipeline cuts a step's
# output from it. -f flushes each write to both logs. The file is removed
# when this process exits, which a hangup or TERM makes it do; these
# traps replace the caller's.
_vgs_tui_transcript=""
vgs_tui_log() { # FILE [ARG...]
  [[ ${VGS_TUI_LOGGED:-} == 1 ]] && return 0
  local file="${1:-}" cmd fd status=0
  [[ -n $file ]] || _vgs_tui_refuse 2 "log=missing" "VGS has no log file for this task. Close it and report the details above." || return
  shift
  cmd="$(printf '%q ' "$BASH" "$0" "$@")"
  exec {fd}>"$file" || _vgs_tui_refuse 1 "log=$file reason=open-failed" "VGS cannot write the task log. Check access to $file, then try again." || return
  _vgs_tui_transcript="$(mktemp -p "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" vgs-tui-transcript.XXXXXXXX)" ||
    _vgs_tui_refuse 1 "transcript=unmade" "VGS cannot save this task's output. Check free space and access to your temporary folder, then try again." || return
  trap 'rm -f -- "${_vgs_tui_transcript:?}"' EXIT
  trap 'exit 129' HUP
  trap 'exit 143' TERM
  env VGS_TUI_LOGGED=1 VGS_TUI_TRANSCRIPT="$_vgs_tui_transcript" VGS_TUI_GAP_LEFT="$_vgs_tui_gap_left" SHELL="$BASH" \
    script -qef --log-out >(_vgs_tui_log_clean >&"$fd") --log-out "$_vgs_tui_transcript" -c "$cmd" {fd}>&- || status=$?
  exec {fd}>&-
  wait "$!" || :
  exit "$status"
}

# FILE's directory is made when absent. A FILE that cannot be opened is
# refused before COMMAND runs.
vgs_tui_logged() { # FILE COMMAND [ARG...]
  local file="${1:-}"
  [[ -n $file && $# -ge 2 ]] || _vgs_tui_refuse 2 "logged=missing" "VGS cannot start this task because its command or log file is missing. Close it and report the details above." || return
  shift
  { mkdir -p -- "$(dirname -- "$file")" && : >>"$file"; } 2>/dev/null ||
    _vgs_tui_refuse 1 "logged=$file reason=open-failed" "VGS cannot write the task log. Check access to $file, then try again." || return
  [[ ! -t 1 ]] || _vgs_tui_gap_left=""
  "$@" 2>>"$file"
}

# A line ended by a newline that no carriage return came before is shown
# through _vgs_tui_print; a carriage-return segment, as a progress line
# redraws, and the newline that ends it pass as they are, since a wrap
# would break the redraw. The reader exits 4 when it showed nothing, which
# keeps a question's blank line marked.
vgs_tui_split() { # FILE KEY COMMAND [ARG...]
  local file="${1:-}" key="${2:-}" fd status piped had_errexit="" segment="" char terminator redrawn="" width
  [[ -n $file && -n $key && $# -ge 3 ]] || _vgs_tui_refuse 2 "split=missing" "VGS cannot show this task's output because its request is incomplete. Close it and report the details above." || return
  shift 2
  { mkdir -p -- "$(dirname -- "$file")" && : >>"$file"; } 2>/dev/null ||
    _vgs_tui_refuse 1 "split=$file reason=open-failed" "VGS cannot write the task log. Check access to $file, then try again." || return
  exec {fd}>>"$file" || _vgs_tui_refuse 1 "split=$file reason=open-failed" "VGS cannot write the task log. Check access to $file, then try again." || return
  [[ $- == *e* ]] && had_errexit=1
  set +e
  width="$(_vgs_tui_width)"
  ( exec {fd}>&-; "$@" ) 2>&1 | {
    shown=""
    while LC_ALL=C IFS= read -r -N 1 char; do
      case "$char" in
        $'\n'|$'\r')
          terminator="$char"
          if [[ $terminator == $'\n' && $segment == "$key":\ * ]]; then
            printf '%s\n' "$segment" >&"$fd" || exit 1
          elif [[ $terminator == $'\r' || -n $redrawn ]]; then
            printf '%s%s' "$segment" "$terminator" || exit 1
            shown=1
          else
            _vgs_tui_print "" "$segment" "$width" || exit 1
            shown=1
          fi
          [[ $terminator == $'\n' ]] && redrawn="" || redrawn=1
          segment=""
          ;;
        *) segment+="$char" ;;
      esac
    done
    if [[ -n $segment ]]; then
      case "$segment" in
        "$key":\ *) printf '%s\n' "$segment" >&"$fd" || exit 1 ;;
        *) printf '%s' "$segment" || exit 1; shown=1 ;;
      esac
    fi
    [[ -n $shown ]] || exit 4
  }
  piped=("${PIPESTATUS[@]}")
  status=${piped[0]}
  [[ ${piped[1]} == 4 ]] || _vgs_tui_gap_left=""
  [[ -z $had_errexit ]] || set -e
  exec {fd}>&-
  return "$status"
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
# pseudo-terminal a test opens. Without a terminal the open of /dev/tty
# fails, and bash reports a redirection it cannot make on the stderr in
# force then, so stderr is silenced first.
vgs_tui_columns() {
  local size
  size="$(stty size 2>/dev/null </dev/tty)" || size=""
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
# 69, sysexits' EX_UNAVAILABLE, is a refusal before anything ran, whose
# sentence already says what the user needs: nothing failed, so the prompt
# names no outcome.
vgs_tui_close_prompt() { # CODE [MARKER]
  local code="$1" marker="${2:-}" status
  [[ $code != 130 ]] || return 0
  _vgs_tui_has_terminal || return 0
  _vgs_tui_drain_terminal
  if [[ $code == 0 ]]; then
    printf '\n%*s%s● \033[0mDone. Press any key to close.' "$_vgs_tui_edge" '' "$(vgs_tui_sgr "${VGS_TUI_SUCCESS:-}" 32)" >/dev/tty
  elif [[ $code == 69 ]]; then
    printf '\n%*s%s● \033[0mPress any key to close.' "$_vgs_tui_edge" '' "$(vgs_tui_sgr "${VGS_TUI_ACCENT:-}" 36)" >/dev/tty
  else
    printf '\n%*s%s● \033[0mThe task failed. Press any key to close.' "$_vgs_tui_edge" '' "$(vgs_tui_sgr "${VGS_TUI_DANGER:-}" 31)" >/dev/tty
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

_vgs_tui_drain_terminal() {
  while read -rsn 1 -t 0.1 _ </dev/tty; do :; done
}

# Prints one `reboot=<reason>` line per reason and returns 0 when a reboot
# is needed, 1 when none is: `kernel` when the running kernel's module
# directory is gone, as after a kernel upgrade; `hyprland` when this
# session's compositor runs a binary that was replaced.
vgs_tui_reboot_check() {
  local release exe reasons=()
  release="$(uname -r)" || _vgs_tui_refuse 1 "reboot-check=uname" "VGS cannot check whether you need to restart the computer. Check the system error above, then try again." || return
  [[ -d /lib/modules/$release ]] || reasons+=(kernel)
  # shellcheck source=bin/lib/hyprland-instance.sh
  source "${BASH_SOURCE[0]%/*}/hyprland-instance.sh" || _vgs_tui_refuse 1 "reboot-check=library" "VGS cannot load a required file. Repair the VGS installation, then try again." || return
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && vgs_hyprland_instance "$HYPRLAND_INSTANCE_SIGNATURE" &&
    exe="$(readlink -- "/proc/$vgs_hyprland_pid/exe" 2>/dev/null)" ||
    _vgs_tui_refuse 1 "reboot-check=hyprland" "VGS cannot check whether Hyprland needs a restart. Check the system error above, then try again." || return
  [[ $exe != *' (deleted)' ]] || reasons+=(hyprland)
  [[ ${#reasons[@]} -gt 0 ]] || return 1
  printf 'reboot=%s\n' "${reasons[@]}"
}
