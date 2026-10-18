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
# The content edge: the header's border and left padding.
edge="   "

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
check "a step is an accent bold line after a blank line" test "$(cat "$tmp/out")" == $'\n'"$edge${esc}[38;2;1;2;3m${esc}[1mUpdating${esc}[0m"
run 'vgs_tui_success "Ready."' VGS_TUI_SUCCESS='#070809'
check "a success line is in the success colour after a blank line" test "$(cat "$tmp/out")" == $'\n'"$edge${esc}[38;2;7;8;9mReady.${esc}[0m"
run 'vgs_tui_success "Ready."'
check "a success line without a theme is ANSI green" test "$(cat "$tmp/out")" == $'\n'"$edge${esc}[32mReady.${esc}[0m"
run 'vgs_tui_warn "careful"' VGS_TUI_WARNING='#040506'
check "a warning is on stderr alone" test ! -s "$tmp/out"
check "a warning is in the warning colour" test "$(cat "$tmp/err")" == "$edge${esc}[38;2;4;5;6mcareful${esc}[0m"
run 'vgs_tui_error "broken"'
check "an error is on stderr alone" test ! -s "$tmp/out"
check "an error without a theme is ANSI red" test "$(cat "$tmp/err")" == "$edge${esc}[31mbroken${esc}[0m"

run 'vgs_tui_header "-Title" "a line"'
check "a header is one bordered gum style with a bold title" test "$(cat "$tmp/gum")" == "$(printf '%s\n' style --border normal --padding "1 2" -- $'\033[1m-Title\033[0m' "a line")"
check "a header starts with one blank line" starts_one_blank "$tmp/out"
check "a header with no terminal writes nothing on stderr" test ! -s "$tmp/err"

# Command blocks are an output format: the reader can recover each command
# after removing the left mark, separators and continuation marks.
command_rows() { # QUIET: the same contract also judges the old-form control
  local columns kind row command snippet red=0 token rows=() commands=()
  printf -v token '%100s' ''; token="${token// /x}"
  rows=("80|normal" "120|normal" "80|wide-word" "80|heredoc" "120|heredoc")
  for row in "${rows[@]}"; do
    IFS='|' read -r columns kind <<<"$row"
    commands=("sudo install -m 0644 -o root -g root -T -- /usr/share/vgshell/config/system/udev/60-vgs-apple-displays.rules /etc/udev/rules.d/60-vgs-apple-displays.rules"
      "sudo mv -fT -- /var/lib/vgshell/system/.tailscale-operator /var/lib/vgshell/system/tailscale-operator"
      "printf %s \$(touch commands-ran); \`touch commands-ran\`; * > file")
    [[ $kind != wide-word ]] || commands=("curl https://example.invalid/$token --output file")
    [[ $kind != heredoc ]] || commands=($'sudo tee -- /var/lib/vgshell/system/.tailscale-operator <<\'VGS_SYSTEM_INPUT\'\nuid=1000\noperator=method\n\n  previous=\n'"a body line with enough words to wrap at both terminal widths $(printf '%s ' {a..y})z"$'\nVGS_SYSTEM_INPUT')
    printf -v snippet 'stty cols %s; cd %q; vgs_tui_commands ' "$columns" "$tmp"
    for command in "${commands[@]}"; do printf -v snippet '%s%q ' "$snippet" "$command"; done
    on_tty_capture "$snippet"
    if [[ $status == 0 ]] && python3 - "$tmp/captured" "$columns" "$kind" "${commands[@]}" <<'PY'
import pathlib, sys

lines = pathlib.Path(sys.argv[1]).read_text().replace("\r\n", "\n").splitlines()
columns, kind, expected = int(sys.argv[2]), sys.argv[3], sys.argv[4:]
assert lines and all(line.startswith("   │") for line in lines)
assert lines[0] != "   │" and lines[-1] != "   │"
assert sum(line == "   │" for line in lines) == len(expected) - 1
commands, current = [], ""
continued = False
input_rows = []
for line in lines:
    if line == "   │":
        commands.append(current)
        current = ""
        continue
    assert line.startswith("   │ ")
    text = line[5:]
    if text.startswith("↳ "):
        assert current
        current += " " + text[2:]
        continued = True
    else:
        if current:
            assert kind == "heredoc"
            current += "\n" + text
            input_rows.append(text)
        else:
            current = text
    if kind != "wide-word":
        assert len(line) <= columns - 3
commands.append(current)
assert commands == expected, (commands, expected)
assert continued
if kind == "heredoc":
    assert input_rows[:4] == ["uid=1000", "operator=method", "", "  previous="]
    assert input_rows[-1] == "VGS_SYSTEM_INPUT"
    assert len(input_rows) == len(expected[0].split("\n")) - 1
if kind == "wide-word":
    assert any(len(line) > columns for line in lines)
PY
    then
      [[ $1 == quiet ]] || ok "command block $row preserves commands and marks every row"
    else
      red=$((red + 1))
      [[ $1 == quiet ]] || fail "command block $row: exit=$status"
    fi
    if [[ -e $tmp/commands-ran ]]; then red=$((red + 1)); fi
  done
  return "$red"
}
command_rows loud || true
check "shell metacharacters in a command block stay inert" test ! -e "$tmp/commands-ran"

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
check "a confirm on a terminal asks gum" test "$(cat "$tmp/gum")" == "$(printf '%s\n' confirm "${confirm_margins[@]}" --default=false -- "$(confirm_prompt "Remove it?")")"
check "a confirm answers gum's yes" test "$status" == 0
check "a confirm on a terminal starts with one blank line" starts_one_blank "$tmp/out"
echo 1 >"$tmp/gum-exit"
on_tty 'vgs_tui_confirm "Remove it?"'
check "a confirm without caller flags still aligns gum" test "$(cat "$tmp/gum")" == "$(printf '%s\n' confirm "${confirm_margins[@]}" -- "$(confirm_prompt "Remove it?")")"
check "a confirm answers gum's no" test "$status" == 1
rm -f -- "$tmp/gum-exit"
# gum erases an answered question but not the blank line above it, which
# the next question or step keeps as its own.
gap_after_questions() { on_tty 'vgs_tui_confirm "Remove it?"; vgs_tui_confirm "Sure?"; vgs_tui_step "Removing"'; starts_one_blank "$tmp/out"; }
gap_after_text() {
  on_tty 'vgs_tui_confirm "Remove it?"; vgs_tui_text "Kept."; vgs_tui_step "Removing"'
  test "$(tr -d '\r' <"$tmp/out")" == $'\n'"${edge}Kept."$'\n\n'"$edge${esc}[32m${esc}[1mRemoving${esc}[0m"
}
check "two questions and a step after them share one blank line" gap_after_questions
check "a step after a line under a question keeps its own blank line" gap_after_text
gap_after_split() { # COMMAND: a question, a split COMMAND, then a step; output in $tmp/out
  on_tty "vgs_tui_confirm 'Remove it?'; vgs_tui_split $(printf %q "$tmp/gap-split.log") jarvis-setup $1; vgs_tui_step Removing"
  tr -d '\r' <"$tmp/out" >"$tmp/gap-split.out"
}
gap_after_quiet_split() { gap_after_split "echo 'jarvis-setup: step=quiet'" && starts_one_blank "$tmp/gap-split.out"; }
gap_after_split_line() { gap_after_split "echo shown" && test "$(cat "$tmp/gap-split.out")" == $'\n'"${edge}shown"$'\n\n'"$edge${esc}[32m${esc}[1mRemoving${esc}[0m"; }
check "a step after a split that showed nothing shares the question's blank line" gap_after_quiet_split
check "a step after a split that showed a line keeps its own blank line" gap_after_split_line
cleared_step() { on_tty 'vgs_tui_clear; vgs_tui_step "Removing"'; test "$(tr -d '\r' <"$tmp/out")" == "${esc}[H${esc}[2J$edge${esc}[32m${esc}[1mRemoving${esc}[0m"; }
check "a step on a cleared screen starts on its first row" cleared_step
# bin/vgshell-tui hands the blank row under its logo to the first script
# that sources the library, as VGS_TUI_GAP_LEFT=1, and to that script's
# logged run.
logo_gap_header() { rm -f -- "$tmp/gum"; run 'vgs_tui_header "-Title" "a line"' VGS_TUI_GAP_LEFT=1; [[ ! -s $tmp/out && -s $tmp/gum ]]; }
logo_gap_spent() { run 'printenv VGS_TUI_GAP_LEFT || echo unset' VGS_TUI_GAP_LEFT=1; test "$(cat "$tmp/out")" == unset; }
printf 'source "$LIB"\nvgs_tui_log %q\nvgs_tui_header "-Title"\n' "$tmp/gap.log" >"$tmp/logged-gap.sh"
logo_gap_logged() { "${lib_env[@]}" LIB="$LIB" VGS_TUI_GAP_LEFT=1 "$BASH" "$tmp/logged-gap.sh" </dev/null >"$tmp/out" 2>&1 && test ! -s "$tmp/out"; }
check "a header under the logo draws no blank line" logo_gap_header
check "the logo's mark reaches no program the script runs" logo_gap_spent
check "a logged script's header under the logo draws no blank line" logo_gap_logged
# Every colour a yes-or-no question draws, against the colour under it,
# meets 4.5 to 1, the WCAG ratio for text, on vgs dark and flexoki-light.
# The host's gum draws the question through the library on an 80-column
# pseudo-terminal with each theme's gum colours, pinned from the render of
# themes/targets/gum for each package on 2026-10-12; FOREGROUND and
# BACKGROUND stand for the terminal's own text and background. Each drawn
# character is judged by its foreground and background. A colour from the
# terminal's own 16-colour palette, or faint text, has no value to measure
# and fails. The prompt, both buttons and the key help must each be drawn,
# so a run that draws nothing, or a judge that reads no colour, fails.
# Rows: theme | text | background | prompt | selected text | selected fill | unselected text | key help
contrast_themes=(
  "vgs-dark|#d7d7d9|#000000|#ff5a36|#000000|#ff5a36|#d7d7d9|#7d7d7e"
  "flexoki-light|#100f0f|#fffcf0|#205ea6|#ffffff|#205ea6|#100f0f|#6b6965"
)
cat >"$tmp/contrast.py" <<'PY'
import re
import sys

drawn = open(sys.argv[1], "rb").read().decode("utf-8", "replace")
text, background = sys.argv[2], sys.argv[3]
required = dict(zip(("prompt", "selected", "unselected", "help"), sys.argv[4:8]))
selected_fill = sys.argv[8]
FLOOR = 4.5
CSI = re.compile(r"\x1b\[([0-?]*)([ -/]*)([@-~])")
OSC = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)")


def luminance(colour):
    channels = [int(colour[at:at + 2], 16) / 255 for at in (1, 3, 5)]
    linear = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def ratio(first, second):
    light, dark = sorted((luminance(first), luminance(second)), reverse=True)
    return (light + 0.05) / (dark + 0.05)


def indexed(n):
    """xterm's 256-colour table past the 16 the terminal's palette sets."""
    if n < 16:
        return "palette"
    if n < 232:
        levels = (0, 95, 135, 175, 215, 255)
        n -= 16
        return "#%02x%02x%02x" % (levels[n // 36], levels[n // 6 % 6], levels[n % 6])
    grey = 8 + 10 * (n - 232)
    return "#%02x%02x%02x" % (grey, grey, grey)


state = {"fg": None, "bg": None, "faint": False, "reverse": False}


def sgr(params):
    codes = params.replace(":", ";").split(";") if params else ["0"]
    at = 0
    while at < len(codes):
        code = int(codes[at] or 0)
        if code == 0:
            state.update(fg=None, bg=None, faint=False, reverse=False)
        elif code == 2:
            state["faint"] = True
        elif code == 22:
            state["faint"] = False
        elif code == 7:
            state["reverse"] = True
        elif code == 27:
            state["reverse"] = False
        elif code in (39, 49):
            state["fg" if code == 39 else "bg"] = None
        elif 30 <= code <= 37 or 90 <= code <= 97:
            state["fg"] = "palette"
        elif 40 <= code <= 47 or 100 <= code <= 107:
            state["bg"] = "palette"
        elif code in (38, 48):
            key = "fg" if code == 38 else "bg"
            if codes[at + 1] == "2":
                state[key] = "#%02x%02x%02x" % tuple(int(c) for c in codes[at + 2:at + 5])
                at += 4
            else:
                state[key] = indexed(int(codes[at + 2]))
                at += 2
        at += 1


pairs = {}
first_line = {}
line = 0
at = 0
while at < len(drawn):
    char = drawn[at]
    if char == "\n":
        line += 1
    if char == "\x1b":
        match = CSI.match(drawn, at) or OSC.match(drawn, at)
        if match is None:
            at += 2
            continue
        if match.re is CSI and match.group(3) == "m" and not match.group(2) and match.group(1)[:1] not in "<=>?":
            sgr(match.group(1))
        at = match.end()
        continue
    at += 1
    if char.isspace() or ord(char) < 0x20:
        continue
    fg, bg = state["fg"] or text, state["bg"] or background
    if state["reverse"]:
        fg, bg = bg, fg
    if state["faint"]:
        fg = "faint"
    pairs.setdefault((fg, bg), []).append(char)
    for element, colour in (("prompt", fg), ("help", fg), ("choices", bg)):
        wanted = selected_fill if element == "choices" else required[element]
        if colour == wanted:
            first_line.setdefault(element, line)

failed = 0
for (fg, bg), chars in pairs.items():
    if not fg.startswith("#") or not bg.startswith("#"):
        print(f"contrast=unmeasured fg={fg} bg={bg} drawn={''.join(chars)[:24]}")
        failed += 1
        continue
    value = ratio(fg, bg)
    verdict = "ok" if value >= FLOOR else "low"
    failed += verdict == "low"
    print(f"contrast={verdict} fg={fg} bg={bg} ratio={value:.2f} drawn={''.join(chars)[:24]}")
drawn_fgs = {fg for fg, _ in pairs}
for element, colour in required.items():
    if colour not in drawn_fgs:
        print(f"contrast=missing element={element} fg={colour}")
        failed += 1
# The first frame's rows: the key help sits under the question and one
# blank row above the Yes and No row it explains.
rows = [first_line.get(name) for name in ("prompt", "help", "choices")]
if None not in rows and rows[0] < rows[1] and rows[2] - rows[1] == 2:
    print("layout=adjacent")
else:
    print("layout=apart prompt=%s help=%s choices=%s" % tuple(rows))
sys.exit(1 if failed else 0)
PY
# contrast_row ROW: the question drawn under ROW's colours and judged; the
# judge's lines in $tmp/contrast, its status returned.
contrast_row() {
  local name fg bg prompt sel_fg sel_bg unsel help
  IFS='|' read -r name fg bg prompt sel_fg sel_bg unsel help <<<"$1"
  "${lib_env[@]}" PATH="$tmp/real-gum:$base_path" TERM=xterm-256color COLORTERM=truecolor \
    FOREGROUND="$fg" BACKGROUND="$bg" GUM_CONFIRM_PROMPT_FOREGROUND="$prompt" GUM_CONFIRM_PROMPT_BACKGROUND="$bg" \
    GUM_CONFIRM_SELECTED_FOREGROUND="$sel_fg" GUM_CONFIRM_SELECTED_BACKGROUND="$sel_bg" \
    GUM_CONFIRM_UNSELECTED_FOREGROUND="$unsel" GUM_CONFIRM_UNSELECTED_BACKGROUND="$bg" GUM_PAGER_HELP_FOREGROUND="$help" \
    timeout 20 script -qec "$(printf '%q ' "$BASH" -c "stty cols 80 rows 24; source $(printf '%q' "$LIB"); vgs_tui_confirm 'Remove it?' --timeout=1s")" /dev/null \
    </dev/null >"$tmp/drawn" 2>&1 || :
  python3 "$tmp/contrast.py" "$tmp/drawn" "$fg" "$bg" "$prompt" "$sel_fg" "$unsel" "$help" "$sel_bg" >"$tmp/contrast"
}
# layout_row ROW: the question drawn under ROW's colours; true when the key
# help sits one blank row above the choices and under the question.
layout_row() {
  contrast_row "$1" || :
  grep -qx 'layout=adjacent' "$tmp/contrast"
}
for row in "${contrast_themes[@]}"; do
  if contrast_row "$row"; then ok "every colour of a question meets 4.5 to 1 on ${row%%|*}"
  else fail "a colour of a question is under 4.5 to 1 on ${row%%|*}: $(paste -sd' ' "$tmp/contrast")"; fi
  if grep -qx 'layout=adjacent' "$tmp/contrast"; then ok "the key help sits right above the choices on ${row%%|*}"
  else fail "the key help is apart from the choices on ${row%%|*}: $(grep '^layout=' "$tmp/contrast")"; fi
done
# The content edge, column 3, read as an 80-column terminal shows the
# drawing, its wrap at the last column included: every row of a question
# longer than the terminal and the Yes button's fill start there, and so
# does every row of a pass-through line, an error and a plain text line
# longer than the terminal. A row that starts with a space starts past
# it, and gum cuts a question wider than the terminal, so the whole text
# must be drawn. The line is built so the terminal's own wrap would put a
# space first on its second row. A choose, an input and a filter draw in
# raw mode, where a line feed keeps the column and gum moves back with
# CSI D or CSI G: the first frame's header and cursor row start at the
# edge too, and every word the row names is drawn.
cat >"$tmp/edge.py" <<'PY'
import re
import sys

drawn = open(sys.argv[1], "rb").read().decode("utf-8", "replace")
mode, edge, cols = sys.argv[2], int(sys.argv[3]), 80
whole = "".join(sys.argv[4].split())
PROMPT, FILL = "#ff0000", "#00ff00"
CSI = re.compile(r"\x1b\[([0-?]*)([ -/]*)([@-~])")
OSC = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)")
fg = bg = None
row = col = 0
text, fill, chars = {}, {}, []
at = 0
while at < len(drawn):
    char = drawn[at]
    if char == "\x1b":
        match = CSI.match(drawn, at) or OSC.match(drawn, at)
        if match is None:
            at += 2
            continue
        at = match.end()
        if match.re is not CSI or match.group(2) or match.group(1)[:1] in "<=>?":
            continue
        params, final = match.group(1), match.group(3)
        if final == "m":
            codes = params.replace(":", ";").split(";") if params else ["0"]
            i = 0
            while i < len(codes):
                code = int(codes[i] or 0)
                if code == 0:
                    fg = bg = None
                elif code in (38, 48) and codes[i + 1] == "2":
                    value = "#%02x%02x%02x" % tuple(int(c) for c in codes[i + 2:i + 5])
                    fg, bg = (value, bg) if code == 38 else (fg, value)
                    i += 4
                elif code in (39, 49):
                    fg, bg = (None, bg) if code == 39 else (fg, None)
                i += 1
        elif final == "C":
            col += int(params or 1)
        elif final == "D":
            col = max(0, col - int(params or 1))
        elif final == "G":
            col = int(params or 1) - 1
        elif final in "AFHJ" and (text or fill):
            break  # gum redraws: the first frame is complete
        continue
    at += 1
    if char == "\r":
        col = 0
    elif char == "\n":
        row += 1
    else:
        if col >= cols:
            row, col = row + 1, 0
        if not char.isspace() and (mode != "confirm" or fg == PROMPT):
            text.setdefault(row, col)
            chars.append(char)
        if bg == FILL:
            fill.setdefault(row, col)
        col += 1
starts = sorted(set(text.values()))
fills = sorted(set(fill.values()))
drawn = "".join(chars)
complete = whole in drawn if mode in ("confirm", "lines") else all(w in drawn for w in sys.argv[4].split())
print(f"edge mode={mode} rows={len(text)} starts={starts} fills={fills} complete={complete}")
wanted_fills = [edge] if mode == "confirm" else []
sys.exit(0 if complete and starts == [edge] and fills == wanted_fills else 1)
PY
edge_long="$(printf 'ab %.0s' {1..40})end"
edge_row() { # LIB_PATH confirm|lines|choose|input|filter
  local snippet='vgs_tui_confirm "$LONG" --timeout=1s' long="$edge_long"
  case "$2" in
    lines) snippet='cmd() { printf "%s\n" "$LONG"; }; vgs_tui_split "$TMP/edge.log" jarvis-setup cmd; vgs_tui_error "$LONG"; vgs_tui_text "$LONG"' ;;
    choose|filter) snippet="echo alpha | vgs_tui_$2 --timeout=1s --header Pick" long="Pick alpha" ;;
    input) snippet='vgs_tui_input --timeout=1s --header Pick --placeholder Name' long="Pick Name" ;;
  esac
  "${lib_env[@]}" PATH="$tmp/real-gum:$base_path" TERM=xterm-256color COLORTERM=truecolor LONG="$long" TMP="$tmp" \
    GUM_CONFIRM_PROMPT_FOREGROUND='#ff0000' GUM_CONFIRM_SELECTED_FOREGROUND='#0000ff' \
    GUM_CONFIRM_UNSELECTED_FOREGROUND='#0000fe' GUM_CONFIRM_SELECTED_BACKGROUND='#00ff00' \
    timeout 20 script -qec "$(printf '%q ' "$BASH" -c "stty cols 80 rows 24; source $(printf '%q' "$1"); $snippet")" /dev/null \
    </dev/null >"$tmp/edge-drawn" 2>&1 || :
  python3 "$tmp/edge.py" "$tmp/edge-drawn" "$2" 3 "$long" >"$tmp/edge"
}
for mode in confirm lines choose input filter; do
  if edge_row "$LIB" "$mode"; then ok "every $mode row starts at the content edge"
  else fail "a $mode row is off the content edge: $(cat "$tmp/edge")"; fi
done
on_tty 'printf "a\nb\n" | vgs_tui_choose --header Pick'
check "a choose on a terminal hands gum its arguments" test "$(cat "$tmp/gum")" == "$(printf '%s\n' choose --padding "0 0 0 3" --header Pick)"
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

# The transcript: the run finds script(1)'s unchanged output in a private
# file under the runtime directory, which is gone once the run ends. The
# run copies the file once its last bytes reach it.
cat >"$tmp/transcript.sh" <<'SH'
source "$LIB"
vgs_tui_log "$LOG_FILE"
printf '%s\n' "$VGS_TUI_TRANSCRIPT" >"$SEEN"
stat -c %a -- "$VGS_TUI_TRANSCRIPT" >>"$SEEN"
printf 'a\033]8913;x\aB\033[31mred\033[0m end-of-transcript\n'
grep -q -F end-of-transcript < <(exec timeout 5 tail -c +1 -f -- "$VGS_TUI_TRANSCRIPT") && cat -- "$VGS_TUI_TRANSCRIPT" >"$COPY"
SH
transcript_ok() { # SEEN COPY
  local path mode
  { read -r path; read -r mode; } <"$1" || return 1
  [[ $path == "$rt"/* && $mode == 600 && ! -e $path ]] || return 1
  python3 - "$2" <<'PY'
import pathlib, sys
data = pathlib.Path(sys.argv[1]).read_bytes()
sys.exit(0 if b"a\x1b]8913;x\x07B\x1b[31mred\x1b[0m end-of-transcript\r\n" in data else 1)
PY
}
transcript_row() { # LIB_PATH
  rm -f -- "$tmp/seen" "$tmp/transcript-copy"
  "${lib_env[@]}" LIB="$1" LOG_FILE="$tmp/transcript.log" SEEN="$tmp/seen" COPY="$tmp/transcript-copy" \
    timeout 10 "$BASH" "$tmp/transcript.sh" </dev/null >"$tmp/out" 2>&1 || return 1
  transcript_ok "$tmp/seen" "$tmp/transcript-copy"
}
check "a logged run reads its unchanged output in a private transcript, removed at its end" transcript_row "$LIB"
check "the clean log leaves the private OSC out" test "$(grep -c 8913 "$tmp/transcript.log")" == 0
copy_with kept-transcript "$lib" "trap 'rm -f -- \"\${_vgs_tui_transcript:?}\"' EXIT" ':'
check "the kept-transcript mutant fails the transcript row" test "$(transcript_row "$copy" && echo green || echo red)" == red
copy_with unwritten-transcript "$lib" ' --log-out "$_vgs_tui_transcript"' ''
check "the unwritten-transcript mutant fails the transcript row" test "$(transcript_row "$copy" && echo green || echo red)" == red

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
# The split log: keyed stdout and stderr lines go to the file, while every
# plain line stays on stdout and the command keeps the caller's stdin.
split_row() {
  rm -rf -- "${tmp:?}/split"
  run "cmd() { IFS= read -r word; echo 'jarvis-setup: step=runtime'; echo \"plain \$word\"; echo 'jarvis-setup: failed=cause' >&2; echo 'plain error' >&2; return 6; }; printf input | vgs_tui_split $(printf %q "$tmp/split/clone.log") jarvis-setup cmd || echo st=\$?"
  [[ $(cat "$tmp/out") == "${edge}plain input"$'\n'"${edge}plain error"$'\n'st=6 ]] &&
    [[ $(cat "$tmp/split/clone.log" 2>/dev/null) == $'jarvis-setup: step=runtime\njarvis-setup: failed=cause' ]] && [[ ! -s $tmp/err ]]
}
check "a split command logs keyed lines, shows plain lines and keeps status" split_row
split_fd_row() {
  rm -rf -- "${tmp:?}/split"
  run "cmd() { for fd in /proc/\$BASHPID/fd/*; do readlink \"\$fd\"; done >$(printf %q "$tmp/child-fds"); }; vgs_tui_split $(printf %q "$tmp/split/clone.log") jarvis-setup cmd"
  ! grep -qxF "$tmp/split/clone.log" "$tmp/child-fds"
}
check "a split command does not inherit the log descriptor" split_fd_row
split_segment_row() { # LIB_PATH
  local row_lib="$1"
  rm -rf -- "${tmp:?}/split"
  mkdir -p -- "$tmp/split"
  status=0
  "${lib_env[@]}" LIB="$row_lib" TMP="$tmp" timeout 5 "$BASH" -c '
    set -euo pipefail
    source "$LIB"
    mkfifo "$TMP/split/terminal" "$TMP/split/ack"
    {
      IFS= read -r -N 2 first <"$TMP/split/terminal"
      printf "%s" "$first" >"$TMP/split/first"
      printf x >"$TMP/split/ack"
      IFS= read -r -N 4 rest <"$TMP/split/terminal"
      printf "%s" "$rest" >"$TMP/split/rest"
    } &
    reader=$!
    cmd() {
      printf "a\r"
      IFS= read -r -N 1 _ <"$TMP/split/ack"
      printf "b\rc\n"
      printf "jarvis-setup: hidden\n"
    }
    vgs_tui_split "$TMP/split/clone.log" jarvis-setup cmd >"$TMP/split/terminal"
    wait "$reader"
  ' >"$tmp/out" 2>"$tmp/err" || status=$?
  [[ $status == 0 ]] &&
    cmp -s "$tmp/split/first" <(printf 'a\r') &&
    cmp -s "$tmp/split/rest" <(printf 'b\rc\n') &&
    [[ $(cat "$tmp/split/clone.log") == 'jarvis-setup: hidden' && ! -s $tmp/err ]]
}
check "a split command streams carriage-return segments and logs keyed lines" split_segment_row "$LIB"
split_closed_row() { # LIB_PATH [LINE_END]: a newline unless LINE_END is r
  local row_lib="$1" end='\n'
  [[ ${2:-} == r ]] && end='\r'
  rm -rf -- "${tmp:?}/split"
  mkdir -p -- "$tmp/split"
  status=0
  "${lib_env[@]}" LIB="$row_lib" TMP="$tmp" END="$end" timeout 3 "$BASH" -c '
    set -o pipefail
    trap "" PIPE
    source "$LIB"
    cmd() { while :; do printf "plain$END" || exit 7; done; }
    vgs_tui_split "$TMP/split/closed.log" jarvis-setup cmd | :
    exit "${PIPESTATUS[0]}"
  ' >"$tmp/out" 2>"$tmp/err" || status=$?
  [[ $status != 0 && $status != 124 ]]
}
check "a split command stops when terminal output closes" split_closed_row "$LIB"
check "a split command of redrawn lines stops when terminal output closes" split_closed_row "$LIB" r
run "vgs_tui_split /proc/version/clone.log jarvis-setup true"
check "an unopenable split log is refused before the command" test "$status:$(err_first)" == "1:vgs-tui: refused: split=/proc/version/clone.log reason=open-failed"
# A refusal: the keyed line to the log, each sentence and the log's name on
# the screen, and the status it was given.
refuse_row() {
  rm -rf -- "${tmp:?}/causes"
  run "vgs_tui_refuse $(printf %q "$causes") 3 'jarvis: key=value' 'One.' 'Two.' || echo st=\$?"
  [[ $(cat "$tmp/out") == st=3 && $(cat "$causes" 2>/dev/null) == 'jarvis: key=value' ]] &&
    grep -qF 'One.' "$tmp/err" && grep -qF 'Two.' "$tmp/err" && ! grep -qF 'key=value' "$tmp/err"
}
check "a refusal logs its key, shows each sentence and keeps its status" refuse_row
# The failure lines name the log, $HOME as ~.
failed_row() {
  run 'vgs_tui_failed "$HOME/state/setup.log" "Could not."'
  grep -qF '~/state/setup.log' "$tmp/err" && ! grep -qF "$tmp/home" "$tmp/err"
}
check "a failure names its log under ~" failed_row
# A cancellation line says what happened, then waits only when a terminal
# can hold the window open for the user.
run 'vgs_tui_cancelled "Nothing changed."'
check "a cancellation without a terminal prints only its sentence" test "$(cat "$tmp/out")" == "${edge}Nothing changed."
check "a cancellation without a terminal exits 0" test "$status" == 0
check "a cancellation without a terminal prints no prompt" test ! -s "$tmp/err"
cancelled_wait_row() {
  rm -f -- "$tmp/cancel-out" "$tmp/cancel-in"
  mkfifo "$tmp/cancel-in"
  exec {cancel_fd}<>"$tmp/cancel-in"
  (
    found=0
    for _ in {1..200}; do
      if grep -qF "Press any key to close..." "$tmp/cancel-out" 2>/dev/null; then found=1; break; fi
      sleep 0.05
    done
    [[ $found == 1 ]] || exit 1
    printf x >"$tmp/cancel-in"
  ) &
  local writer=$!
  status=0
  "${lib_env[@]}" timeout 12 script -qec "$(printf '%q ' "$BASH" -c "set -euo pipefail; source $(printf '%q' "$LIB"); vgs_tui_cancelled 'Nothing changed.'")" /dev/null \
    <"$tmp/cancel-in" {cancel_fd}>&- >"$tmp/cancel-out" 2>&1 || status=$?
  local writer_status=0
  if kill -0 "$writer" 2>/dev/null; then kill "$writer" 2>/dev/null || :; fi
  wait "$writer" || writer_status=$?
  exec {cancel_fd}>&-
  [[ $status == 0 && $writer_status == 0 ]] && grep -qF "Nothing changed." "$tmp/cancel-out" &&
    grep -qF "● " "$tmp/cancel-out" && grep -qF "Press any key to close..." "$tmp/cancel-out"
}
check "a cancellation on a terminal waits until a key" cancelled_wait_row
cancelled_blocks_row() { # LIB_PATH
  local row_lib="$1"
  status=0
  "${lib_env[@]}" LIB="$row_lib" timeout 1 script -qec "$(printf '%q ' "$BASH" -c "set -euo pipefail; source \"\$LIB\"; vgs_tui_cancelled 'Nothing changed.'")" /dev/null \
    </dev/null >"$tmp/out" 2>&1 || status=$?
  [[ $status == 124 ]] && grep -qF "Press any key to close..." "$tmp/out"
}
check "a cancellation on a terminal blocks with no key" cancelled_blocks_row "$LIB"
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
control bare-commands "printf '%s│ %s%s\\n'" "printf '%s%s%s\\n'"
check "the old bare form fails the command block contract" test "$(command_rows quiet && echo green || echo red)" == red
control single-command-mark '[[ ${_vgs_tui_wrapped[i]} == 1 ]]' '[[ $i != 0 ]]'
check "marking input as wrapped fails the command block contract" test "$(command_rows quiet && echo green || echo red)" == red
control no-terminal-check '_vgs_tui_has_terminal() { : 2>/dev/null <>/dev/tty; }' '_vgs_tui_has_terminal() { true; }'
rm -f -- "$tmp/gum"
run 'vgs_tui_choose a b'
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
control no-header-blank "_vgs_tui_header_gap() { _vgs_tui_gap; }" "_vgs_tui_header_gap() { :; }"
run 'vgs_tui_header "-Title" "a line"'
check "the no-header-blank mutant fails the header blank row" test "$(starts_one_blank "$tmp/out" && echo green || echo red)" == red
control no-bold-header "printf -v title '\\033[1m%s\\033[0m' \"\$title_line\"" 'title="$title_line"'
run 'vgs_tui_header "-Title" "a line"'
check "the no-bold-header mutant fails the header argv row" test "$(cat "$tmp/gum")" != "$(printf '%s\n' style --border normal --padding "1 2" -- $'\033[1m-Title\033[0m' "a line")"
control captured-gum-header "printf -v title '\\033[1m%s\\033[0m' \"\$title_line\"" 'title="$(gum style --bold -- "$title_line")"'
run 'vgs_tui_header "-Title" "a line"'
check "the captured-gum-header mutant fails the header argv row" test "$(cat "$tmp/gum")" != "$(printf '%s\n' style --border normal --padding "1 2" -- $'\033[1m-Title\033[0m' "a line")"
control no-header-width '"${width[@]}" -- "$title" "$@"' '-- "$title" "$@"'
check "the no-header-width mutant breaks the border at 60 columns" test "$(header_row 60 FILLS && echo green || echo red)" == red
control columns-loud-without-terminal 'size="$(stty size 2>/dev/null </dev/tty)"' 'size="$(stty size </dev/tty 2>/dev/null)"'
run 'vgs_tui_header "-Title" "a line"'
check "the columns-loud-without-terminal mutant fails the quiet header row" test -s "$tmp/err"
control header-always-fills '(( ${#line} + 6 > columns ))' 'true'
check "the header-always-fills mutant fails the fitting header row" test "$(header_row 100 FITS && echo green || echo red)" == red
control gap-never-left '  _vgs_tui_gap_left=1' '  :'
check "the gap-never-left mutant fails the shared blank line row" test "$(gap_after_questions && echo green || echo red)" == red
control gap-kept-after-text '  local lines=() line pad' '  local lines=() line pad _vgs_tui_gap_left'
check "the gap-kept-after-text mutant fails the blank line after text row" test "$(gap_after_text && echo green || echo red)" == red
control split-always-shown '    [[ -n $shown ]] || exit 4' '    :'
check "the split-always-shown mutant fails the quiet split row" test "$(gap_after_quiet_split && echo green || echo red)" == red
control split-keeps-mark '  [[ ${piped[1]} == 4 ]] || _vgs_tui_gap_left=""' '  :'
check "the split-keeps-mark mutant fails the shown split row" test "$(gap_after_split_line && echo green || echo red)" == red
control clear-leaves-blank "printf '\\033[H\\033[2J'; _vgs_tui_gap_left=1; }" "printf '\\033[H\\033[2J'; }"
check "the clear-leaves-blank mutant fails the cleared screen row" test "$(cleared_step && echo green || echo red)" == red
control logo-gap-unread '_vgs_tui_gap_left="${VGS_TUI_GAP_LEFT:-}"' '_vgs_tui_gap_left=""'
check "the logo-gap-unread mutant fails the logo header row" test "$(logo_gap_header && echo green || echo red)" == red
control logo-gap-kept 'unset VGS_TUI_GAP_LEFT' ':'
check "the logo-gap-kept mutant fails the spent mark row" test "$(logo_gap_spent && echo green || echo red)" == red
control logo-gap-unlogged ' VGS_TUI_GAP_LEFT="$_vgs_tui_gap_left" SHELL' ' SHELL'
check "the logo-gap-unlogged mutant fails the logged logo header row" test "$(logo_gap_logged && echo green || echo red)" == red
control no-prompt-blank "_vgs_tui_prompt_gap() { _vgs_tui_gap >&2; }" "_vgs_tui_prompt_gap() { :; }"
on_tty 'vgs_tui_confirm "Remove it?"'
check "the no-prompt-blank mutant fails the prompt blank row" test "$(starts_one_blank "$tmp/out" && echo green || echo red)" == red
control confirm-margins-at-zero 'margin="0 0 0 $_vgs_tui_edge"' 'margin="0 0 0 0"'
check "the confirm-margins-at-zero mutant fails the confirm edge row" test "$(edge_row "$copy" confirm && echo green || echo red)" == red
control question-unwrapped '_vgs_tui_lines lines "$(_vgs_tui_width)" "$question"' 'lines=("$question")'
check "the question-unwrapped mutant fails the confirm edge row" test "$(edge_row "$copy" confirm && echo green || echo red)" == red
control split-passes-through '_vgs_tui_print "" "$segment" "$width" || exit 1' 'printf '\''%s\n'\'' "$segment" || exit 1'
check "the split-passes-through mutant fails the lines edge row" test "$(edge_row "$copy" lines && echo green || echo red)" == red
control text-unwrapped '_vgs_tui_print "" "$*"' 'printf '\''%s\n'\'' "$*"'
check "the text-unwrapped mutant fails the lines edge row" test "$(edge_row "$copy" lines && echo green || echo red)" == red
for mode in choose input filter; do
  control "$mode-unpadded" "gum $mode --padding \"0 0 0 \$_vgs_tui_edge\"" "gum $mode"
  check "the $mode-unpadded mutant fails the $mode edge row" test "$(edge_row "$copy" "$mode" && echo green || echo red)" == red
done
control break-keeps-space 'then _vgs_tui_out+=("$cur"); cur="" cur_n=0; fi' 'then _vgs_tui_out+=("$cur"); cur="$gap" cur_n=${#gap}; fi'
check "the break-keeps-space mutant fails the lines edge row" test "$(edge_row "$copy" lines && echo green || echo red)" == red
control gum-help-shown 'GUM_CONFIRM_SHOW_HELP=false gum confirm' 'gum confirm'
check "the gum-help-shown mutant fails the vgs-dark contrast row" test "$(contrast_row "${contrast_themes[0]}" && echo green || echo red)" == red
control help-low-colour '"$(vgs_tui_sgr "${GUM_PAGER_HELP_FOREGROUND:-}" 39)"' '"$(vgs_tui_sgr "#3a3a3a" 39)"'
check "the help-low-colour mutant fails the vgs-dark contrast row" test "$(contrast_row "${contrast_themes[0]}" && echo green || echo red)" == red
# The layout's control: the help printed on its own line above the
# question, gum's prompt the question alone.
copy_with help-above-question-1 "$lib" '"$@" -- "$question"$'"'"'\n'"'"'"$help"' '"$@" -- "$question"'
copy_with help-above-question "$copy" '  _vgs_tui_prompt_gap' '  _vgs_tui_prompt_gap; printf '"'"'%s\n'"'"' "$help" >/dev/tty'
LIB="$copy"
check "the help-above-question mutant fails the layout row" test "$(layout_row "${contrast_themes[0]}" && echo green || echo red)" == red
control accent-success '"$(vgs_tui_sgr "${VGS_TUI_SUCCESS:-}" 32)" "$*"' '"$(vgs_tui_sgr "${VGS_TUI_ACCENT:-}" 32)" "$*"'
run 'vgs_tui_success "Ready."' VGS_TUI_SUCCESS='#070809' VGS_TUI_ACCENT='#010203'
check "the accent-success mutant fails the success colour row" test "$(cat "$tmp/out")" != $'\n'"${esc}[38;2;7;8;9mReady.${esc}[0m"
control stderr-on-screen '"$@" 2>>"$file"' '"$@"'
check "the stderr-on-screen mutant fails the cause log row" test "$(logged_row && echo green || echo red)" == red
control split-key-on-screen '            printf '\''%s\n'\'' "$segment" >&"$fd" || exit 1' '            printf '\''%s\n'\'' "$segment" || exit 1'
check "the split-key-on-screen mutant fails the split row" test "$(split_row && echo green || echo red)" == red
control split-status-lost 'status=${piped[0]}' 'status=0'
check "the split-status-lost mutant fails the split row" test "$(split_row && echo green || echo red)" == red
control split-fd-inherited '( exec {fd}>&-; "$@" ) 2>&1' '( "$@" ) 2>&1'
check "the split-fd-inherited mutant fails the split descriptor row" test "$(split_fd_row && echo green || echo red)" == red
control split-line-buffered 'while LC_ALL=C IFS= read -r -N 1 char; do' 'while IFS= read -r char; do'
check "the split-line-buffered mutant fails the segment row" test "$(split_segment_row "$copy" && echo green || echo red)" == red
control split-terminal-ignored '_vgs_tui_print "" "$segment" "$width" || exit 1' '_vgs_tui_print "" "$segment" "$width"'
check "the split-terminal-ignored mutant fails the closed terminal row" test "$(split_closed_row "$copy" && echo green || echo red)" == red
control split-redraw-terminal-ignored 'printf '\''%s%s'\'' "$segment" "$terminator" || exit 1' 'printf '\''%s%s'\'' "$segment" "$terminator"'
check "the split-redraw-terminal-ignored mutant fails the redrawn closed terminal row" test "$(split_closed_row "$copy" r && echo green || echo red)" == red
control refuse-status 'return "$refused"' 'return 0'
check "the refuse-status mutant fails the refusal row" test "$(refuse_row && echo green || echo red)" == red
control refuse-one-sentence '  vgs_tui_failed "$file" "$@"' '  vgs_tui_failed "$file" "$1"'
check "the refuse-one-sentence mutant fails the refusal row" test "$(refuse_row && echo green || echo red)" == red
control no-home '"The details are in ${file/#"$HOME"/\~}."' '"The details are in $file."'
check "the no-home mutant fails the failure row" test "$(failed_row && echo green || echo red)" == red
control cancelled-no-wait 'read -rsn 1 _ </dev/tty || return 0' ':'
check "the cancelled-no-wait mutant fails the cancelled wait row" test "$(cancelled_blocks_row "$copy" && echo green || echo red)" == red
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

# The editor contract runs on an isolated PATH. The stand-ins receive argv
# and inherited stdin/stdout/stderr. A pseudo-terminal lets the actual choice
# prompt run; no installed editor or desktop service can be reached.
python3 - "$lib" "$tmp" "$BASH" "$(command -v script)" <<'PY' || failures=$((failures + 1))
import os, pathlib, shlex, subprocess, sys

library, scratch, bash, terminal = sys.argv[1:]
root = pathlib.Path(scratch) / "editors"
root.mkdir()
tools = root / "tools"
tools.mkdir()
file = root / "a file.md"
file.write_text("personality\n")
program = '#!' + bash + '''
printf '%s\\n' "${0##*/}" "$@" > "$EDIT_CALLS"
printf 'editor: output=value\\n'
printf 'editor: error=fixture\\n' >&2
exit "$EDIT_EXIT"
'''
for name in ["nvim", "vim", "nano", "code", "codium", "editor"]:
    target = tools / name
    target.write_text(program)
    target.chmod(0o700)
(tools / "gum").write_text('#!' + bash + '''
printf '%s\\n' "$@" > "$EDIT_CHOICE"
[[ $EDIT_CANCEL == 0 ]] || exit "$EDIT_CANCEL"
printf '%s\\n' "$EDIT_PICK"
''')
(tools / "gum").chmod(0o700)
empty = root / "empty"
empty.mkdir()
calls, choice = root / "calls", root / "choice"
# name, VISUAL, EDITOR, choice, exit, expected argv, expected status
rows = [
    ("visual", "nvim -R", "vim", "", 0, ["nvim", "-R"], 0),
    ("editor", "", "nano -w", "", 0, ["nano", "-w"], 0),
    ("literal", "editor $(touch) ;", "", "", 0, ["editor", "$(touch)", ";"], 0),
    ("absolute", str(tools / "nvim") + " -R", "", "", 0, ["nvim", "-R"], 0),
    ("failure", "", "editor", "", 4, ["editor"], 4),
    ("missing-command", "missing-editor", "vim", "", 0, None, 127),
    ("code", "code --wait --reuse-window -w", "vim", "", 0, ["code", "--reuse-window"], 0),
    ("codium", "", "codium -w --wait --new-window", "", 0, ["codium", "--new-window"], 0),
    ("pick", "", "", "vim", 0, ["vim"], 0),
    ("cancel", "", "", "cancel", 0, None, 130),
    ("none-installed", "", "", "none", 0, None, 1),
]
def verify(subject):
    for name, visual, editor, pick, code, expected, status in rows:
        calls.unlink(missing_ok=True)
        choice.unlink(missing_ok=True)
        environment = dict(PATH=str(empty if pick == "none" else tools), VISUAL=visual, EDITOR=editor,
            EDIT_CALLS=str(calls), EDIT_CHOICE=str(choice), EDIT_EXIT=str(code), EDIT_PICK=pick,
            EDIT_CANCEL="130" if pick == "cancel" else "0", SHELL=bash, TERM="xterm", VGS_TEST_RUN="1")
        snippet = "set -euo pipefail; source " + shlex.quote(str(subject)) + "; vgs_tui_edit " + shlex.quote(str(file))
        command = [bash, "-c", snippet]
        if pick not in ["", "none"]:
            command = [terminal, "-qec", shlex.join(command), "/dev/null"]
        result = subprocess.run(command, env=environment, stdin=subprocess.DEVNULL, capture_output=True, timeout=5)
        assert result.returncode == status, (name, result.returncode, result.stderr)
        actual = calls.read_text().splitlines() if calls.exists() else None
        assert actual == (expected + [str(file)] if expected else None), (name, actual)
        if expected:
            if pick:
                offered = choice.read_text().splitlines()
                assert offered[0] == "choose"
                assert offered[offered.index("--") + 1:] == ["nvim", "vim", "nano", "code", "codium"]
            else:
                assert not choice.exists(), name
                assert result.stdout == b"editor: output=value\n", name
                assert result.stderr == b"editor: error=fixture\n", name
        if name == "missing-command":
            assert b"missing-editor" in result.stderr
    return True
verify(library)
print("test-tui: editor-cases=" + str(len(rows)) + " passed=true")
# Run transcripts are a paging view. They use the same helper only when
# an editor is known; with neither editor variable, PAGER keeps its role.
pager = tools / "less"
pager.write_text(program)
pager.chmod(0o700)
transcript = pathlib.Path(library).parents[2] / "shell/plugins/vgs.automations/tui/transcript.sh"
def verify_transcript(subject):
    for visual, editor, expected in [("nvim -R", "nano", ["nvim", "-R"]), ("nvim -R", "", ["nvim", "-R"]), ("", "nano -w", ["nano", "-w"]), ("", "", ["less"])]:
        environment = dict(PATH=str(tools), VISUAL=visual, EDITOR=editor, PAGER="less", VGS_TUI_LIB=library,
            EDIT_CALLS=str(calls), EDIT_EXIT="0", VGS_TEST_RUN="1")
        result = subprocess.run([bash, str(subject), str(file)], env=environment, stdin=subprocess.DEVNULL, capture_output=True, timeout=5)
        assert result.returncode == 0, result.stderr
        assert calls.read_text().splitlines() == expected + [str(file)]
verify_transcript(transcript)
print("test-tui: transcript-editor-and-pager passed=true")
transcript_source = transcript.read_text()
needle = 'vgs_tui_edit "$path"'
assert transcript_source.count(needle) == 1
mutant = root / "transcript-drops-editor.sh"
mutant.write_text(transcript_source.replace(needle, ':'))
try:
    verify_transcript(mutant)
except AssertionError:
    print("test-tui: control=transcript-drops-editor rejected=true")
else:
    raise AssertionError("transcript editor control passed")
source = pathlib.Path(library).read_text()
needle = 'selected="${VISUAL:-${EDITOR:-}}"'
assert source.count(needle) == 1
mutant = root / "editor-ignores-visual.sh"
mutant.write_text(source.replace(needle, 'selected="${EDITOR:-${VISUAL:-}}"'))
try:
    verify(mutant)
except AssertionError:
    print("test-tui: control=editor-ignores-visual rejected=true")
else:
    raise AssertionError("editor choice control passed")
PY

# The template's control: a copy that turns every confirm status into success.
copy_with swallowed-confirm "$template" 'vgs_tui_confirm "Continue?" || status=$?' 'vgs_tui_confirm "Continue?" || exit 0'
check "the swallowed-confirm mutant fails a template row" test "$(run_template_rows "$copy" quiet && echo green || echo red)" == red

rows_done test-tui
