#!/usr/bin/env bash
# Every floating TUI script, each shell/plugins/*/tui/*.sh the tree holds,
# must start gum with the colours bin/vgshell-tui present exported. Each
# script runs under a byte copy of the presenter, `present --presentation
# plain --plugin <id> --dir <plugin dir> -- tui/<name>.sh`, on a
# pseudo-terminal script(1) opens, under timeout, with stdin /dev/null,
# `env -i`, scratch HOME and XDG directories, TERM=xterm-256color,
# COLORTERM=truecolor and a synthetic gum.env of distinct values. The
# scripts run side by side, each in a world of its own, and are judged in
# discovery order once all have ended.
#
# What keeps a script from any privileged tool is where it runs, not the
# order of the steps inside it. The presenter runs from a scratch tree
# that holds only copies of bin/vgshell-tui and bin/lib/, so VGS_TUI_LIB
# names that tree and a script that finds the VGS tree from it finds no
# bin/vgshell and no vgshell-* helper, the programs that can put the system
# PATH back and start sudo. PATH is one stub directory: a stub gum and
# links to the harmless tools `allowed` names, so a script stops at the
# first other command it runs. Neither closes a program a script names by
# an absolute path, or a lookup through `env -i` without PATH, which falls
# back to the system directories; no shipped script does either.
#
# The stub gum compares its environment with every gum.env key but
# VGS_TUI_*, which gum does not read, and TERM and COLORTERM, value for
# value, records one line per call and exits 130, a cancel, so the script
# ends at its first gum call. Its paths are written into its text, since a
# script's own `env -i` drops any variable naming them.
#
# One verdict per script: `ok` when every gum call saw every value;
# `tui-gum=uncoloured script=<path> missing=<names>`, a failure, when a call
# did not; `tui-gum=unreached`, no failure, when the script ended or timed
# out before any gum call. The required members must reach gum, and the
# discovery floor below fails a broken discovery, stub or presenter.
#
# Controls, planted scripts in a copy of one plugin: (a) gum under `env -i`
# is uncoloured; (b) gum under TERM=xterm, one changed value, is uncoloured
# and misses TERM alone. The presenter's colours with no gum.env are
# scripts/test-theme-gum.js's.
set -euo pipefail

source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"
for tool in script timeout; do
  command -v "$tool" >/dev/null || { echo "test-tui-gum-colours: status=not-measured missing=$tool"; exit 77; }
done
script_bin="$(command -v script)"
# The scratch tree the header describes.
mkdir -p -- "$tmp/tree/bin"
cp -- "$repo/bin/vgshell-tui" "$tmp/tree/bin/vgshell-tui"
cp -R -- "$repo/bin/lib" "$tmp/tree/bin/lib"
presenter="$tmp/tree/bin/vgshell-tui"
# A script that waits on a key past this many seconds, as a close prompt
# does, is unreached; a script that reaches gum ends within one.
ceiling=5

# What the presenter and the scripts' preambles run before gum. Nothing
# here can elevate, prompt, reach the network or reach the session.
allowed=(bash env dirname basename cat readlink mkdir mktemp cp rm date id head tail tr cut sed grep sort wc touch stat)
declare -A tool_at
for tool in "${allowed[@]}"; do
  at="$(command -v -- "$tool")" && [[ $at == /* ]] ||
    { echo "test-tui-gum-colours: status=not-measured missing=$tool"; exit 77; }
  tool_at[$tool]="$at"
done

synthetic="$tmp/gum.env"
printf '%s\n' \
  'FOREGROUND=#101112' 'BACKGROUND=#202122' 'BORDER_FOREGROUND=#303132' \
  'GUM_CHOOSE_CURSOR_FOREGROUND=#404142' 'GUM_CONFIRM_PROMPT_FOREGROUND=#505152' \
  'GUM_INPUT_PROMPT_FOREGROUND=#606162' 'GUM_FILTER_MATCH_FOREGROUND=#707172' \
  'GUM_SPIN_SPINNER_FOREGROUND=#808182' 'VGS_TUI_ACCENT=#909192' >"$synthetic"
expected=(TERM=xterm-256color COLORTERM=truecolor)
while IFS= read -r line; do
  [[ $line == VGS_TUI_* ]] || expected+=("$line")
done <"$synthetic"

# stub_dir DIR: DIR/bin holds the allowed tools and a gum that appends
# `call=<verb> missing=<names>` to DIR/gum.log and exits 130, a name
# missing when its value differs from the expected one.
stub_dir() {
  local dir="$1" tool
  mkdir -p -- "$dir/bin"
  for tool in "${allowed[@]}"; do ln -s -- "${tool_at[$tool]}" "$dir/bin/$tool"; done
  {
    printf '#!%s\n' "$BASH"
    printf 'expected=(%s)\n' "$(printf '%q ' "${expected[@]}")"
    printf 'missing=()\n'
    printf 'for pair in "${expected[@]}"; do name="${pair%%%%=*}"; [[ ${!name-} == "${pair#*=}" ]] || missing+=("$name"); done\n'
    printf 'names="${missing[*]}"\n'
    printf 'printf '\''call=%%s missing=%%s\\n'\'' "${1:-}" "${names// /,}" >>%q\n' "$dir/gum.log"
    printf 'exit 130\n'
  } >"$dir/bin/gum"
  chmod +x -- "$dir/bin/gum"
}

# run_tui DIR PLUGIN_DIR SCRIPT: one presented run of SCRIPT, relative to
# PLUGIN_DIR, in DIR, a fresh stub directory and scratch world. The gum
# calls land in DIR/gum.log, the terminal's text in DIR/out and the exit
# status in DIR/status.
run_tui() {
  local dir="$1" world="$1/world" cmd status=0
  stub_dir "$dir"
  mkdir -p -- "$world/home" "$world/state/vgshell/theme" "$world/config" "$world/data" "$world/rt"
  cp -- "$synthetic" "$world/state/vgshell/theme/gum.env"
  cmd="$(printf '%q ' "$presenter" present --presentation plain --plugin "${2##*/}" --dir "$2" -- "$3")"
  timeout -k 2 "$ceiling" env -i PATH="$dir/bin" HOME="$world/home" XDG_STATE_HOME="$world/state" \
    XDG_CONFIG_HOME="$world/config" XDG_DATA_HOME="$world/data" XDG_RUNTIME_DIR="$world/rt" \
    TERM=xterm-256color COLORTERM=truecolor "$script_bin" -qec "$cmd" /dev/null </dev/null >"$dir/out" 2>&1 ||
    status=$?
  printf '%s\n' "$status" >"$dir/status"
}

# judge_log LOG: sets verdict to ok, uncoloured, unreached or unparsed, and
# missing to the names any call lacked, comma-separated.
judge_log() {
  local line names=()
  verdict=unreached missing=""
  [[ -s $1 ]] || return 0
  verdict=ok
  while IFS= read -r line; do
    if [[ ! $line =~ ^call=[^\ ]*\ missing=([^\ ]*)$ ]]; then verdict=unparsed; return 0; fi
    if [[ -n ${BASH_REMATCH[1]} ]]; then verdict=uncoloured; names+=("${BASH_REMATCH[1]}"); fi
  done <"$1"
  if [[ ${#names[@]} -gt 0 ]]; then
    missing="$(printf '%s\n' "${names[@]}" | tr ',' '\n' | sort -u | paste -sd, -)"
  fi
}

# The controls' planted scripts, in a scratch copy of one plugin.
plugin="$tmp/plugins/vgs.ai-usage"
mkdir -p -- "$plugin"
cp -R -- "$repo/shell/plugins/vgs.ai-usage/." "$plugin/"
planted=(stripped 'env -i PATH="$PATH" gum choose a b' recoloured 'TERM=xterm gum choose a b')
for ((i = 0; i < ${#planted[@]}; i += 2)); do
  printf '#!/usr/bin/env bash\n%s\n' "${planted[i + 1]}" >"$plugin/tui/${planted[i]}.sh"
  chmod +x -- "$plugin/tui/${planted[i]}.sh"
done

# Discovery from the tree: every shipped TUI script. They and the planted
# scripts start at once; a close prompt holds its script to the ceiling.
shopt -s nullglob
scripts=("$repo"/shell/plugins/*/tui/*.sh)
shopt -u nullglob
check "discovery finds TUI scripts" test "${#scripts[@]}" -gt 0
runs=("${scripts[@]}" "$plugin/tui/stripped.sh" "$plugin/tui/recoloured.sh")
# Each run's own stderr takes the shell's notice of a run timeout killed.
pids=()
mkdir -p -- "$tmp/run"
for i in "${!runs[@]}"; do
  run_tui "$tmp/run/$i" "${runs[i]%/tui/*}" "tui/${runs[i]##*/}" 2>"$tmp/run/$i.err" &
  pids+=("$!")
done
for i in "${!pids[@]}"; do
  wait "${pids[i]}" || fail "tui-gum=run-failed script=${runs[i]} err=$(paste -sd' ' "$tmp/run/$i.err")"
done

reached=0
declare -A verdict_of
for i in "${!scripts[@]}"; do
  rel="${scripts[i]#"$repo"/}"
  judge_log "$tmp/run/$i/gum.log"
  verdict_of[$rel]="$verdict"
  case "$verdict" in
    ok) reached=$((reached + 1)); ok "tui-gum=ok script=$rel" ;;
    uncoloured) reached=$((reached + 1)); fail "tui-gum=uncoloured script=$rel missing=$missing" ;;
    unreached) printf '  note  tui-gum=unreached script=%s exit=%s\n' "$rel" "$(cat -- "$tmp/run/$i/status")" ;;
    *) fail "tui-gum=unparsed script=$rel log=$(paste -sd' ' "$tmp/run/$i/gum.log")" ;;
  esac
done

# The issue's scripts: each opens with the library's header, a gum call.
for rel in shell/plugins/vgs.notifications/tui/setup-slack.sh shell/plugins/vgs.ai-usage/tui/gateway-key.sh; do
  case "${verdict_of[$rel]:-absent}" in
    ok|uncoloured) ok "tui-gum=reached script=$rel" ;;
    *) fail "tui-gum=required-unreached script=$rel verdict=${verdict_of[$rel]:-absent}" ;;
  esac
done
# The floor: 14 of the 33 scripts reached gum in this check's run on
# 2026-10-07, each through a header or a question asked before any tool
# outside `allowed`. A stub gum off PATH, a presenter that runs no script
# or a discovery that lists the wrong files reaches none or a few; 10
# leaves room for a few scripts to start asking later, and is above the
# two required members, so the check proves more than those.
floor=10
check "tui-gum=floor reached=$reached floor=$floor" test "$reached" -ge "$floor"

# (a) gum under `env -i` loses every colour the presenter exported.
judge_log "$tmp/run/${#scripts[@]}/gum.log"
check "control: a script that strips the environment is uncoloured" test "$verdict" == uncoloured
# (b) one changed value is uncoloured, missing that name alone.
judge_log "$tmp/run/$((${#scripts[@]} + 1))/gum.log"
check "control: a script that changes TERM is uncoloured missing TERM" test "$verdict:$missing" == uncoloured:TERM

rows_done test-tui-gum-colours
