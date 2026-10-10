#!/usr/bin/env bash
# Controls for bin/lib/tui.sh, the floating TUI presentation library, and
# for the plugin template that sources it. Each library row sources it into
# a fresh bash with an explicit environment and runs one snippet: stub gum, sudo, uname and pgrep record their arguments or answer
# as the row sets. A row that needs no terminal runs under `setsid --wait`,
# a session with no controlling terminal; one that needs a terminal runs on
# a pseudo-terminal script(1) opens.
set -euo pipefail

source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"
for tool in script setsid flock timeout gum; do
  command -v "$tool" >/dev/null || { echo "test-tui: status=not-measured missing=$tool"; exit 77; }
done
lib="$repo/bin/lib/tui.sh"
# The header width rows draw with the host's gum, on a PATH of its own.
mkdir -p "$tmp/real-gum"
ln -s "$(command -v gum)" "$tmp/real-gum/gum"
stubs="$tmp/stubs"; rt="$tmp/rt"
mkdir -p "$stubs" "$rt"
stub() { printf '#!/bin/sh\n%s\n' "$2" >"$stubs/$1"; chmod +x "$stubs/$1"; } # NAME BODY
# gum records its argv, one per line, prints an answer for captured prompts,
# and exits with $tmp/gum-exit, 0 when absent.
stub gum ": >\"$tmp/gum\"; cmd=\"\$1\"; for a; do printf '%s\\n' \"\$a\" >>\"$tmp/gum\"; done; case \"\$cmd\" in choose|input|filter) printf 'gum-answer\\n';; esac; st=0; [ -f \"$tmp/gum-exit\" ] && read -r st <\"$tmp/gum-exit\"; exit \"\$st\""
# sudo records each call; `sudo /usr/bin/true` exits 1 while $tmp/sudo-deny exists.
stub sudo "printf '%s\\n' \"\$*\" >>\"$tmp/sudo\"; [ \"\$*\" = /usr/bin/true ] && [ -e \"$tmp/sudo-deny\" ] && exit 1; exit 0"
# uname -r prints $tmp/release; pgrep prints $tmp/pids and exits with $tmp/pgrep-exit, else 1.
stub uname "cat \"$tmp/release\""
stub pgrep "cat \"$tmp/pids\" 2>/dev/null; st=1; [ -f \"$tmp/pgrep-exit\" ] && read -r st <\"$tmp/pgrep-exit\"; exit \"\$st\""

LIB="$lib"
lib_env=("${base_env[@]}" PATH="$stubs:$base_path" SHELL="$BASH" XDG_RUNTIME_DIR="$rt")
# run SNIPPET [ENV=VALUE...]: SNIPPET in bash after sourcing $LIB, with no
# controlling terminal; stdout in $tmp/out, stderr in $tmp/err, the exit
# status in $status.
run() {
  local snippet="$1"
  shift
  status=0
  "${lib_env[@]}" "$@" setsid --wait "$BASH" -c "set -euo pipefail; source $(printf '%q' "$LIB"); $snippet" \
    </dev/null >"$tmp/out" 2>"$tmp/err" || status=$?
}
# on_tty SNIPPET: the same on a pseudo-terminal; output in $tmp/out.
on_tty() {
  status=0
  "${lib_env[@]}" script -qec "$(printf '%q ' "$BASH" -c "set -euo pipefail; source $(printf '%q' "$LIB"); $1")" /dev/null \
    </dev/null >"$tmp/out" 2>&1 || status=$?
}
on_tty_capture() {
  status=0
  rm -f -- "$tmp/captured"
  "${lib_env[@]}" CAPTURE="$tmp/captured" script -qec "$(printf '%q ' "$BASH" -c "set -euo pipefail; source $(printf '%q' "$LIB"); $1 >\"\$CAPTURE\"")" /dev/null \
    </dev/null >"$tmp/out" 2>&1 || status=$?
}
err_first() { local line=""; [[ -s $tmp/err ]] && IFS= read -r line <"$tmp/err"; printf '%s' "$line"; }
starts_one_blank() { # FILE
  python3 - "$1" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text().replace("\r\n", "\n")
sys.exit(0 if text.startswith("\n") and not text.startswith("\n\n") else 1)
PY
}
esc=$'\033'

# Colours: a #rrggbb value becomes a truecolor escape, anything else the
# ANSI fallback.
# Rows: value | fallback | escape after ESC[
rows=(
  "#ff5a36|33|38;2;255;90;54m"
  "#FF5A36|33|38;2;255;90;54m"
  "#000000|31|38;2;0;0;0m"
  "|33|33m"
  "red|32|32m"
  "#ff5a3|31|31m"
  "#ff5a366|31|31m"
  "ff5a36|31|31m"
)
for row in "${rows[@]}"; do
  IFS='|' read -r value fallback want <<<"$row"
  run "vgs_tui_sgr $(printf '%q' "$value") $fallback"
  check "colour [$value] is ESC[$want" test "$(cat "$tmp/out")" == "${esc}[$want"
done
run 'vgs_tui_step "Updating"' VGS_TUI_ACCENT='#010203'
check "a step is an accent bold line after a blank line" test "$(cat "$tmp/out")" == $'\n'"${esc}[38;2;1;2;3m${esc}[1mUpdating${esc}[0m"
run 'vgs_tui_success "Ready."' VGS_TUI_SUCCESS='#070809'
check "a success line is in the success colour after a blank line" test "$(cat "$tmp/out")" == $'\n'"${esc}[38;2;7;8;9mReady.${esc}[0m"
run 'vgs_tui_success "Ready."'
check "a success line without a theme is ANSI green" test "$(cat "$tmp/out")" == $'\n'"${esc}[32mReady.${esc}[0m"
run 'vgs_tui_warn "careful"' VGS_TUI_WARNING='#040506'
check "a warning is on stderr alone" test ! -s "$tmp/out"
check "a warning is in the warning colour" test "$(cat "$tmp/err")" == "${esc}[38;2;4;5;6mcareful${esc}[0m"
run 'vgs_tui_error "broken"'
check "an error is on stderr alone" test ! -s "$tmp/out"
check "an error without a theme is ANSI red" test "$(cat "$tmp/err")" == "${esc}[31mbroken${esc}[0m"

run 'vgs_tui_header "-Title" "a line"'
check "a header is one bordered gum style" test "$(cat "$tmp/gum")" == "$(printf '%s\n' style --border normal --padding "1 2" -- -Title "a line")"
check "a header starts with one blank line" starts_one_blank "$tmp/out"

# Questions need the terminal; unattended, confirm answers yes and asks nothing.
rm -f -- "$tmp/gum"
run 'vgs_tui_confirm "Remove it?" --default=false' VGS_TUI_UNATTENDED=1
check "an unattended confirm answers yes" test "$status" == 0
check "an unattended confirm starts with one blank line" starts_one_blank "$tmp/out"
check "an unattended confirm includes the caller's question" grep -Fq "Remove it?" "$tmp/out"
check "an unattended confirm runs no gum" test ! -e "$tmp/gum"
for fn in confirm choose input filter; do
  run "vgs_tui_$fn 'Question?'"
  check "$fn with no terminal returns 2" test "$status" == 2
  check "$fn with no terminal is refused" test "$(err_first)" == "vgs-tui: refused: $fn=no-terminal"
  check "$fn with no terminal runs no gum" test ! -e "$tmp/gum"
done
on_tty 'vgs_tui_confirm "Remove it?" --default=false'
check "a confirm on a terminal asks gum" test "$(cat "$tmp/gum")" == "$(printf '%s\n' confirm --default=false -- "Remove it?")"
check "a confirm answers gum's yes" test "$status" == 0
check "a confirm on a terminal starts with one blank line" starts_one_blank "$tmp/out"
echo 1 >"$tmp/gum-exit"
on_tty 'vgs_tui_confirm "Remove it?"'
check "a confirm answers gum's no" test "$status" == 1
rm -f -- "$tmp/gum-exit"
on_tty 'printf "a\nb\n" | vgs_tui_choose --header Pick'
check "a choose on a terminal hands gum its arguments" test "$(cat "$tmp/gum")" == "$(printf '%s\n' choose --header Pick)"
check "a choose on a terminal starts with one blank line on the terminal stream" starts_one_blank "$tmp/out"
on_tty 'vgs_tui_input --placeholder Name'
check "an input on a terminal starts with one blank line on the terminal stream" starts_one_blank "$tmp/out"
on_tty 'printf "a\nb\n" | vgs_tui_filter --placeholder Search'
check "a filter on a terminal starts with one blank line on the terminal stream" starts_one_blank "$tmp/out"
on_tty_capture 'printf "a\nb\n" | vgs_tui_choose --header Pick'
check "a choose answer has no prompt blank on stdout" test "$(cat "$tmp/captured")" == gum-answer
on_tty_capture 'vgs_tui_input --placeholder Name'
check "an input answer has no prompt blank on stdout" test "$(cat "$tmp/captured")" == gum-answer
on_tty_capture 'printf "a\nb\n" | vgs_tui_filter --placeholder Search'
check "a filter answer has no prompt blank on stdout" test "$(cat "$tmp/captured")" == gum-answer

# The sudo session: drop the credential, authorize once, keep it alive in
# the background, and drop it again at end, on exit and on a signal, with
# the keepalive gone each time.
keepalive_gone() { local pid; pid="$(cat "$tmp/keepalive")"; [[ -n $pid ]] && ! kill -0 "$pid" 2>/dev/null; }
session="vgs_tui_sudo_session start; printf '%s' \"\$_vgs_tui_keepalive_pid\" >$(printf '%q' "$tmp/keepalive")"
# Rows: name | what runs after start | exit
rows=(
  "an ended session||0"
  "an exiting session|exit 3|3"
  "a terminated session|kill -TERM \$\$; sleep 5|143"
  "a hung-up session|kill -HUP \$\$; sleep 5|129"
)
for row in "${rows[@]}"; do
  IFS='|' read -r name after want_exit <<<"$row"
  rm -f -- "$tmp/sudo" "$tmp/keepalive"
  run "$session; ${after:-vgs_tui_sudo_session end}"
  check "$name exits $want_exit" test "$status" == "$want_exit"
  check "$name drops, authorizes and drops again" test "$(cat "$tmp/sudo")" == "$(printf '%s\n' -k /usr/bin/true -k)"
  check "$name leaves no keepalive" keepalive_gone
done
rm -f -- "$tmp/sudo"; touch "$tmp/sudo-deny"
run 'vgs_tui_sudo_session start; echo started'
check "a refused password fails start" test "$status" == 1
check "a refused password is named" test "$(err_first)" == "vgs-tui: refused: sudo=not-authorized"
check "a refused password starts no session" test "$(cat "$tmp/sudo")" == "$(printf '%s\n' -k /usr/bin/true)"
rm -f -- "$tmp/sudo-deny"
run 'vgs_tui_sudo_session begin'
check "an unknown session step is refused" test "$status:$(err_first)" == "2:vgs-tui: refused: sudo-session=begin"

# The guard asks for nothing and drops the credential however the script
# ends, keeping its exit status. guard_rows QUIET: every row against $LIB;
# ok and FAIL lines unless QUIET is `quiet`; returns the failing rows.
guard_rows() {
  local row name after want_exit want_calls got red=0
  # Rows: name | what runs after guard | exit | the sudo calls, space-delimited
  for row in "an ended guard|vgs_tui_sudo_session end|0|-k" \
    "a command that authorizes and fails under a guard|sudo /usr/bin/true; exit 7|7|/usr/bin/true -k" \
    "a terminated guard|kill -TERM \$\$; sleep 5|143|-k" "an interrupted guard|kill -INT \$\$; sleep 5|130|-k"; do
    IFS='|' read -r name after want_exit want_calls <<<"$row"
    : >"$tmp/sudo"
    run "vgs_tui_sudo_session guard; $after"
    got="$(tr '\n' ' ' <"$tmp/sudo" | sed 's/ $//')" || got="unreadable"
    if [[ $status == "$want_exit" && $got == "$want_calls" ]]; then
      [[ $1 == quiet ]] || ok "$name exits $want_exit and drops the credential last"
    else
      red=$((red + 1))
      [[ $1 == quiet ]] || fail "$name: exit=$status calls=[$got]"
    fi
  done
  return "$red"
}
guard_rows loud || true

# A nested run's session joins a live owner's: it drops nothing when it
# ends or fails, so the owner's credential stays for its later steps, and
# the owner's end drops it once. An owner pid naming no process starts a
# session of its own. The nested run is a child bash sourcing the same
# library, as bin/lib/pkg-run.sh is under the Updates pipeline.
nested() { printf '%s -c %q %q' "$BASH" "source \"\$0\"; vgs_tui_sudo_session start; $1" "$LIB"; } # SNIPPET
dead_pid="$(sh -c 'echo $$')"
# nested_rows QUIET: every row against $LIB; prints ok and FAIL lines unless
# QUIET is `quiet`; returns the number of failing rows. A row is a name, a
# snippet and the sudo calls it makes, space-delimited; the rows are built
# at each call, so a control's copy reaches the nested run too.
nested_rows() {
  local names=() snippets=() wants=() i got red=0
  names+=("a nested session joins its owner's")
  snippets+=("vgs_tui_sudo_session start; $(nested 'vgs_tui_sudo_session end'); vgs_tui_sudo_session end")
  wants+=("-k /usr/bin/true /usr/bin/true -k")
  names+=("a failing nested run keeps its owner's credential")
  snippets+=("vgs_tui_sudo_session start; $(nested 'exit 3') || true; vgs_tui_sudo_session end")
  wants+=("-k /usr/bin/true /usr/bin/true -k")
  names+=("an owner that is gone is not joined")
  snippets+=("export VGS_TUI_SUDO_SESSION=$dead_pid; vgs_tui_sudo_session start; vgs_tui_sudo_session end")
  wants+=("-k /usr/bin/true -k")
  for i in "${!names[@]}"; do
    rm -f -- "$tmp/sudo"
    run "${snippets[i]}"
    got="$(tr '\n' ' ' <"$tmp/sudo" | sed 's/ $//')" || got="unreadable"
    if [[ $status == 0 && $got == "${wants[i]}" ]]; then
      [[ $1 == quiet ]] || ok "${names[i]}"
    else
      red=$((red + 1))
      [[ $1 == quiet ]] || fail "${names[i]}: exit=$status calls=[$got]"
    fi
  done
  return "$red"
}
nested_rows loud || true
run 'vgs_tui_sudo_session start; vgs_tui_sudo_session end; printf "%s" "${VGS_TUI_SUDO_SESSION-unset}"'
check "an ended session unexports its pid" test "$(cat "$tmp/out")" == unset

# The lock: one holder per name, a lower-case name only.
# Two holders of one name: this shell, then a child bash that sources the
# same library.
lock_twice() { run "vgs_tui_lock update; st=0; $BASH -c 'source \"\$0\"; vgs_tui_lock update' $(printf '%q' "$LIB") || st=\$?; echo second=\$st"; }
lock_twice
check "a second holder is refused busy" grep -qxF second=75 "$tmp/out"
check "a second holder is named" test "$(err_first)" == "vgs-tui: refused: lock=update reason=busy"
check "the lock file is under the runtime dir" test -f "$rt/vgs-tui-update.lock"
for name in "../x" "Update" "" "-x" "a/b"; do
  run "vgs_tui_lock $(printf '%q' "$name")"
  check "lock name [$name] is refused" test "$status:$(err_first)" == "2:vgs-tui: refused: lock-name=$name"
done

# The log: the script runs again under script(1) with its arguments, the
# file keeps its output and the exit status is the script's.
printf 'source "$LIB"\nvgs_tui_log %q "$@"\necho "logged=$VGS_TUI_LOGGED args=$*"\nexit 7\n' "$tmp/run.log" >"$tmp/logged.sh"
status=0
"${lib_env[@]}" LIB="$LIB" "$BASH" "$tmp/logged.sh" 'a b' c </dev/null >"$tmp/out" 2>&1 || status=$?
check "a logged script exits with its own status" test "$status" == 7
check "a logged script shows its output" grep -qF "logged=1 args=a b c" "$tmp/out"
check "the log keeps the output" grep -qF "logged=1 args=a b c" "$tmp/run.log"

cat >"$tmp/log-bytes.sh" <<'SH'
source "$LIB"
vgs_tui_log "$LOG_FILE" "$@"
python3 - <<'PY'
import sys
esc = "\x1b"
text = (
    esc + "[?2026$p" + esc + "[?2027$p" + esc + "[?25l" + esc + "[?5W"
    + esc + "[?2004h" + esc + "[>4;2m" + esc + "[>1u" + esc + "[?u"
    + "\r" + esc + "[J" + esc + "[J" + "Remove 4 orphaned package(s)?\r\n"
    + "n No\r" + esc + "[>4m" + esc + "[<1u" + esc + "[A" + esc + "[J"
    + esc + "[?25h" + esc + "[?2004l" + "Keeping the orphaned packages.\r\n"
    + esc + "[31mred" + esc + "[0m\r\n"
    + "progress 10%\rprogress 100%\r\n"
    + esc + "]0;title\x07" + esc + "(B" + "plain\r\n"
)
sys.stdout.buffer.write(text.encode("latin1"))
PY
exit "$1"
SH
log_bytes_ok() { # FILE
  python3 - "$1" <<'PY'
import pathlib, re, sys
data = pathlib.Path(sys.argv[1]).read_bytes()
without_sgr = re.sub(rb"\x1b\[[0-9;:]*m", b"", data)
lines = [b"Remove 4 orphaned package(s)?\n", b"Keeping the orphaned packages.\n", b"\x1b[31mred\x1b[0m\n", b"progress 100%\n", b"plain\n"]
at = 0
for line in lines:
    found = data.find(line, at)
    if found < 0:
        sys.exit(1)
    at = found + len(line)
sys.exit(0 if b"\r" not in data and b"\x1b[31m" in data and b"\x1b" not in without_sgr else 1)
PY
}
log_bytes_row() { # LIB_PATH
  local row_lib="$1"
  rm -f -- "$tmp/clean.log"
  status=0
  "${lib_env[@]}" LIB="$row_lib" LOG_FILE="$tmp/clean.log" timeout 5 "$BASH" "$tmp/log-bytes.sh" 23 >"$tmp/out" 2>&1 || status=$?
  [[ $status == 23 ]] && log_bytes_ok "$tmp/clean.log"
}
check "a logged script keeps SGR and drops other terminal controls" log_bytes_row "$LIB"
check "a logged script does not hang while filtering" test "$status" == 23
copy_with unfiltered-log "$lib" '_vgs_tui_log_clean >&"$fd"' 'cat >&"$fd"'
check "the unfiltered-log mutant fails the clean-log row" test "$(log_bytes_row "$copy" && echo green || echo red)" == red

# The cause log: a command's stderr goes to the file, which is made with its
# directory and added to; its stdout and status stay the command's.
causes="$tmp/causes/setup.log"
logged_row() {
  rm -rf -- "${tmp:?}/causes"
  run "cmd() { echo out; echo key=\$1 >&2; return 5; }; vgs_tui_logged $(printf %q "$causes") cmd one || echo st=\$?; vgs_tui_logged $(printf %q "$causes") cmd two || :"
  [[ $(cat "$tmp/out") == $'out\nst=5\nout' && $(cat "$causes" 2>/dev/null) == $'key=one\nkey=two' && ! -s $tmp/err ]]
}
check "a logged command's stderr goes to the log, its output and status stay" logged_row
run "vgs_tui_logged /proc/version/causes.log true"
check "an unopenable log is refused" test "$status:$(err_first)" == "1:vgs-tui: refused: logged=/proc/version/causes.log reason=open-failed"
# A refusal: the keyed line to the log, each sentence and the log's name on
# the screen, and the status it was given.
refuse_row() {
  rm -rf -- "${tmp:?}/causes"
  run "vgs_tui_refuse $(printf %q "$causes") 3 'jarvis: key=value' 'One.' 'Two.' || echo st=\$?"
  [[ $(cat "$tmp/out") == st=3 && $(cat "$causes" 2>/dev/null) == 'jarvis: key=value' ]] &&
    [[ $(wc -l <"$tmp/err") == 3 ]] && ! grep -qF 'key=value' "$tmp/err"
}
check "a refusal logs its key, shows each sentence and keeps its status" refuse_row
# The failure lines name the log, $HOME as ~.
failed_row() {
  run 'vgs_tui_failed "$HOME/state/setup.log" "Could not."'
  grep -qF '~/state/setup.log' "$tmp/err" && ! grep -qF "$tmp/home" "$tmp/err"
}
check "a failure names its log under ~" failed_row
# The width: a sized terminal's columns, 80 for one that reports none.
columns_row() {
  on_tty_capture '{ vgs_tui_columns; stty cols 132 </dev/tty; vgs_tui_columns; }'
  [[ $(cat "$tmp/captured") == $'80\n132' ]]
}
check "the width is the terminal's, 80 when it reports none" columns_row
# The header in a terminal COLS wide, drawn by the host's gum: every row,
# SGR stripped, no wider than COLS, one unbroken border, and every character
# of the lines in order; gum breaks a line at a space or after a hyphen. A
# box that fits keeps its own width, narrower than COLS.
long_line="Review: paru checks 6 third-party packages: 1password, agent-browser-bin, vsys-git, vgshell-git, visual-studio-code-bin, and 1 more"
header_row() { # COLS FITS|FILLS
  rm -f -- "${tmp:?}/captured"
  local snippet='vgs_tui_header "Update everything" "" "$LONG" "" "Log: ~/.local/state/vgshell/updates/2026-10-10T00-45-23.log"'
  [[ $2 == FITS ]] && snippet='vgs_tui_header "Short" "a line"'
  "${lib_env[@]}" PATH="$tmp/real-gum:$base_path" LONG="$long_line" CAPTURE="$tmp/captured" \
    script -qec "$(printf '%q ' "$BASH" -c "set -euo pipefail; source $(printf '%q' "$LIB"); stty cols $1 </dev/tty; $snippet >\"\$CAPTURE\"")" /dev/null \
    </dev/null >"$tmp/out" 2>&1 || return 1
  python3 - "$tmp/captured" "$1" "$2" "$long_line" <<'PY'
import re, sys
text = re.sub(r"\x1b\[[0-9;:]*m", "", open(sys.argv[1], encoding="utf-8").read())
cols, mode, long_line = int(sys.argv[2]), sys.argv[3], sys.argv[4]
rows = text.split("\n")[1:-1]
if len(rows) < 3 or len({len(r) for r in rows}) != 1 or len(rows[0]) > cols:
    sys.exit(1)
if not (rows[0][0] + rows[0][-1] == "┌┐" and rows[-1][0] + rows[-1][-1] == "└┘"
        and all(r[0] + r[-1] == "││" for r in rows[1:-1])):
    sys.exit(1)
text = "".join("".join(r[1:-1].split()) for r in rows[1:-1])
want = "".join(("Short a line" if mode == "FITS" else
                "Update everything " + long_line + " Log: ~/.local/state/vgshell/updates/2026-10-10T00-45-23.log").split())
sys.exit(0 if text == want and (len(rows[0]) < cols) == (mode == "FITS") else 1)
PY
}
for cols in 60 80 100; do
  check "a header wider than $cols columns wraps inside its border" header_row "$cols" FILLS
done
check "a header that fits 100 columns keeps its own width" header_row 100 FITS
# gum's words: each exported colour or bold variable gum reads, an empty
# colour, gum's no colour, included, and TERM and COLORTERM, value for
# value; never a gum behaviour option, a VGS_TUI_
# colour, an unrelated, a lowercase or a longer name, or a variable the
# script did not export.
gum_env_row() {
  run 'GUM_LOCAL_ONLY_FOREGROUND="#131313"; vgs_tui_gum_env words; printf "%s\n" "${words[@]}"' \
    GUM_CHOOSE_CURSOR_FOREGROUND='#010203' FOREGROUND='#040506' BACKGROUND='#070809' BORDER_FOREGROUND='#0a0b0c' \
    TERM=xterm-256color COLORTERM=truecolor VGS_TUI_ACCENT='#0d0e0f' SECRET_TOKEN=fixture-secret \
    gum_choose_cursor_foreground='#101112' GUM_CONFIRM_TIMEOUT=3s TERM_PROGRAM=kitty X_FOREGROUND='#141414' \
    GUM_CHOOSE_HEADER_FOREGROUND= GUM_CHOOSE_CURSOR_BOLD=true
  [[ $status == 0 && $(cat "$tmp/out") == "$(printf '%s\n' BACKGROUND='#070809' BORDER_FOREGROUND='#0a0b0c' \
    COLORTERM=truecolor FOREGROUND='#040506' GUM_CHOOSE_CURSOR_BOLD=true GUM_CHOOSE_CURSOR_FOREGROUND='#010203' \
    GUM_CHOOSE_HEADER_FOREGROUND= \
    TERM=xterm-256color)" ]]
}
check "gum's words are its exported colours, TERM and COLORTERM" gum_env_row

# The reboot check: the running kernel's modules and a replaced Hyprland.
kernel=""
for dir in /lib/modules/*/; do [[ -d $dir ]] && { kernel="$(basename -- "$dir")"; break; }; done
[[ -n $kernel ]] || { echo "test-tui: status=not-measured missing=/lib/modules/<release>"; exit 77; }
replaced_binary "$tmp/replaced"
# shellcheck disable=SC2154 # replaced_binary sets replaced_pid
# Rows: name | release | pids | exit | stdout
rows=(
  "a current system|$kernel||1|"
  "a replaced kernel|0.0.0-vgs-test||0|reboot=kernel"
  "a replaced Hyprland|$kernel|$replaced_pid|0|reboot=hyprland"
  "both replaced|0.0.0-vgs-test|$$ $replaced_pid|0|reboot=kernel reboot=hyprland"
  "a current Hyprland|$kernel|$$|1|"
)
for row in "${rows[@]}"; do
  IFS='|' read -r name release pids want_exit want_out <<<"$row"
  printf '%s\n' "$release" >"$tmp/release"
  printf '%s\n' $pids >"$tmp/pids"
  if [[ -n $pids ]]; then echo 0 >"$tmp/pgrep-exit"; else rm -f -- "$tmp/pgrep-exit"; fi
  run 'vgs_tui_reboot_check'
  check "$name exits $want_exit" test "$status" == "$want_exit"
  check "$name prints [$want_out]" test "$(tr '\n' ' ' <"$tmp/out" | sed 's/ $//')" == "$want_out"
done
echo 3 >"$tmp/pgrep-exit"; printf '%s\n' "$kernel" >"$tmp/release"; : >"$tmp/pids"
run 'vgs_tui_reboot_check'
check "a failed pgrep is refused" test "$status:$(err_first)" == "1:vgs-tui: refused: reboot-check=pgrep exit=3"

# The plugin template's confirm, .agents/skills/vgs-plugin/templates/tui.sh,
# run on a pseudo-terminal with a gum whose confirm answers as the row sets
# and whose other commands succeed: No ends the script with 0, and a Ctrl-C
# (130) or a refusal (2) leaves with its own code, so present shows no Done
# prompt for either.
template="$repo/.agents/skills/vgs-plugin/templates/tui.sh"
tstubs="$tmp/template-stubs"; mkdir -p "$tstubs"
printf '#!/bin/sh\n[ "$1" = confirm ] || exit 0\nread -r st <"%s"\nexit "$st"\n' "$tmp/confirm-exit" >"$tstubs/gum"
chmod +x "$tstubs/gum"
# run_template FILE CONFIRM_EXIT: FILE as a script, confirm answering
# CONFIRM_EXIT; the exit status in $status.
run_template() {
  printf '%s\n' "$2" >"$tmp/confirm-exit"
  status=0
  "${lib_env[@]}" PATH="$tstubs:$stubs:$base_path" VGS_TUI_LIB="$lib" script -qec "$(printf '%q ' "$BASH" "$1")" /dev/null \
    </dev/null >"$tmp/out" 2>&1 || status=$?
}
# run_template_rows FILE QUIET: every row through FILE; prints ok and FAIL
# lines unless QUIET is `quiet`; returns the number of failing rows.
run_template_rows() {
  local row confirm want red=0
  for row in "0|0" "1|0" "130|130" "2|2"; do
    IFS='|' read -r confirm want <<<"$row"
    run_template "$1" "$confirm"
    if [[ $status == "$want" ]]; then
      [[ $2 == quiet ]] || ok "the template exits $want when confirm answers $confirm"
    else
      red=$((red + 1))
      [[ $2 == quiet ]] || fail "the template exits $want when confirm answers $confirm: got $status"
    fi
  done
  return "$red"
}
run_template_rows "$template" loud || true

# Must-fail controls, each on a copy of the library missing one rule.
control() { # NAME NEEDLE REPLACEMENT: LIB names the copy
  copy_with "$1" "$lib" "$2" "$3"
  LIB="$copy"
}
control no-terminal-check '_vgs_tui_has_terminal() { : 2>/dev/null <>/dev/tty; }' '_vgs_tui_has_terminal() { true; }'
rm -f -- "$tmp/gum"
run 'vgs_tui_confirm "Remove it?"'
check "the no-terminal-check mutant asks gum with no terminal" test -e "$tmp/gum"
control kept-credential 'sudo -k || _vgs_tui_refuse 1 "sudo=revoke-failed"' 'true || _vgs_tui_refuse 1 "sudo=revoke-failed"'
rm -f -- "$tmp/sudo"
run "$session; exit 0"
check "the kept-credential mutant ends without sudo -k" test "$(cat "$tmp/sudo")" == "$(printf '%s\n' -k /usr/bin/true)"
control shared-lock 'flock -n -E 75 "$_vgs_tui_lock_fd" || status=$?' 'true || status=$?'
lock_twice
check "the shared-lock mutant lets a second holder in" grep -qxF second=0 "$tmp/out"
control never-joins '&& kill -0 "$outer" 2>/dev/null; then' '&& false; then'
check "the never-joins mutant fails a nested row" test "$(nested_rows quiet && echo green || echo red)" == red
control joins-the-dead '&& kill -0 "$outer" 2>/dev/null; then' '; then'
check "the joins-the-dead mutant fails a nested row" test "$(nested_rows quiet && echo green || echo red)" == red
control unguarded 'guard) _vgs_tui_sudo_traps ;;' 'guard) ;;'
check "the unguarded mutant fails a guard row" test "$(guard_rows quiet && echo green || echo red)" == red
control no-header-blank "_vgs_tui_header_gap() { printf '\\n'; }" "_vgs_tui_header_gap() { :; }"
run 'vgs_tui_header "-Title" "a line"'
check "the no-header-blank mutant fails the header blank row" test "$(starts_one_blank "$tmp/out" && echo green || echo red)" == red
control no-header-width '"${width[@]}" -- "$@"' '-- "$@"'
check "the no-header-width mutant breaks the border at 60 columns" test "$(header_row 60 FILLS && echo green || echo red)" == red
control header-always-fills '(( ${#line} + 6 > columns ))' 'true'
check "the header-always-fills mutant fails the fitting header row" test "$(header_row 100 FITS && echo green || echo red)" == red
control no-prompt-blank "_vgs_tui_prompt_gap() { printf '\\n' >&2; }" "_vgs_tui_prompt_gap() { :; }"
on_tty 'vgs_tui_confirm "Remove it?"'
check "the no-prompt-blank mutant fails the prompt blank row" test "$(starts_one_blank "$tmp/out" && echo green || echo red)" == red
control accent-success '"$(vgs_tui_sgr "${VGS_TUI_SUCCESS:-}" 32)" "$*"' '"$(vgs_tui_sgr "${VGS_TUI_ACCENT:-}" 32)" "$*"'
run 'vgs_tui_success "Ready."' VGS_TUI_SUCCESS='#070809' VGS_TUI_ACCENT='#010203'
check "the accent-success mutant fails the success colour row" test "$(cat "$tmp/out")" != $'\n'"${esc}[38;2;7;8;9mReady.${esc}[0m"
control stderr-on-screen '"$@" 2>>"$file"' '"$@"'
check "the stderr-on-screen mutant fails the cause log row" test "$(logged_row && echo green || echo red)" == red
control refuse-status 'return "$refused"' 'return 0'
check "the refuse-status mutant fails the refusal row" test "$(refuse_row && echo green || echo red)" == red
control refuse-one-sentence '  vgs_tui_failed "$file" "$@"' '  vgs_tui_failed "$file" "$1"'
check "the refuse-one-sentence mutant fails the refusal row" test "$(refuse_row && echo green || echo red)" == red
control no-home '"The details are in ${file/#"$HOME"/\~}."' '"The details are in $file."'
check "the no-home mutant fails the failure row" test "$(failed_row && echo green || echo red)" == red
control zero-width '[[ $size =~ ^[123456789][0123456789]*$ ]] || size=80' '[[ $size =~ ^[0123456789]+$ ]] || size=80'
check "the zero-width mutant fails the width row" test "$(columns_row && echo green || echo red)" == red
control gum-base-colours '|FOREGROUND|BACKGROUND|BORDER_FOREGROUND"' '"'
check "the gum-base-colours mutant fails the gum words row" test "$(gum_env_row && echo green || echo red)" == red
control gum-no-terminal-profile '|TERM|COLORTERM)$' ')$'
check "the gum-no-terminal-profile mutant fails the gum words row" test "$(gum_env_row && echo green || echo red)" == red
control gum-any-name '$_vgs_tui_gum_names|TERM|COLORTERM)$' '$_vgs_tui_gum_names|TERM|COLORTERM|.*)$'
check "the gum-any-name mutant fails the gum words row" test "$(gum_env_row && echo green || echo red)" == red
control gum-unexported 'done < <(compgen -e)' 'done < <(compgen -v)'
check "the gum-unexported mutant fails the gum words row" test "$(gum_env_row && echo green || echo red)" == red
control gum-behaviour-option 'GUM_($_vgs_tui_upper|_)+_(FOREGROUND|BACKGROUND)|' 'GUM_($_vgs_tui_upper|_)+|'
check "the gum-behaviour-option mutant fails the gum words row" test "$(gum_env_row && echo green || echo red)" == red
control gum-unanchored '[[ $name =~ ^($_vgs_tui_gum_names|TERM|COLORTERM)$ ]]' '[[ $name =~ ($_vgs_tui_gum_names|TERM|COLORTERM) ]]'
check "the gum-unanchored mutant fails the gum words row" test "$(gum_env_row && echo green || echo red)" == red
control gum-no-bold '_vgs_tui_gum_names="$_vgs_tui_gum_colours|$_vgs_tui_gum_bolds"' '_vgs_tui_gum_names="$_vgs_tui_gum_colours"'
check "the gum-no-bold mutant fails the gum words row" test "$(gum_env_row && echo green || echo red)" == red
control gum-drops-empty 'then _vgs_tui_words+=("$name=${!name}"); fi' 'then [[ -z ${!name} ]] || _vgs_tui_words+=("$name=${!name}"); fi'
check "the gum-drops-empty mutant fails the gum words row" test "$(gum_env_row && echo green || echo red)" == red
LIB="$lib"

# The template's control: a copy that turns every confirm status into success.
copy_with swallowed-confirm "$template" 'vgs_tui_confirm "Continue?" || status=$?' 'vgs_tui_confirm "Continue?" || exit 0'
check "the swallowed-confirm mutant fails a template row" test "$(run_template_rows "$copy" quiet && echo green || echo red)" == red

rows_done test-tui
