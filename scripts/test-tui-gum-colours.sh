#!/usr/bin/env bash
# Every floating TUI script, each shell/plugins/*/tui/*.sh the tree holds,
# must start gum with the colours bin/vgshell-tui present exported. Each
# script runs under the real presenter, `present --presentation plain
# --plugin <id> --dir <plugin dir> -- tui/<name>.sh`, on a pseudo-terminal
# script(1) opens, under timeout, with stdin /dev/null, `env -i`, scratch
# HOME and XDG directories, TERM=xterm-256color, COLORTERM=truecolor and a
# synthetic gum.env of distinct values. PATH is one stub directory: a stub
# gum and links to the harmless tools `allowed` names, so a script stops at
# the first command it lacks, and no sudo, polkit, keyring, network or
# session tool is there to start. The stub gum compares its environment
# with every gum.env key but VGS_TUI_*, which gum does not read, and TERM
# and COLORTERM, records one line per call and exits 130, a cancel, so the
# script ends at its first gum call. Its paths are written into its text,
# since a script's own `env -i` drops any variable naming them.
#
# One verdict per script: `ok` when every gum call saw every value;
# `tui-gum=uncoloured script=<path> missing=<names>`, a failure, when a call
# did not; `tui-gum=unreached`, no failure, when the script ended or timed
# out before any gum call. The required members must reach gum, and the
# discovery floor below fails a broken discovery, stub or presenter.
#
# Controls: (a) a planted script in a copy of a plugin that runs gum under
# `env -i` is uncoloured; with no gum.env, (b) a copy of the presenter
# without its no-gum.env branch is uncoloured, and (c) the real presenter
# is coloured, judged by the presence of each key since the values are the
# vgs package's. (b) and (c) need node for the theme judge, so their stub
# directory also links node and runs only a planted script that calls gum.
set -euo pipefail

source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"
for tool in script timeout; do
  command -v "$tool" >/dev/null || { echo "test-tui-gum-colours: status=not-measured missing=$tool"; exit 77; }
done
script_bin="$(command -v script)"
presenter="$repo/bin/vgshell-tui"
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

# stub_dir DIR MODE [node]: DIR/bin holds the allowed tools, node too when
# asked, and a gum that appends `call=<verb> missing=<names>` to DIR/gum.log
# and exits 130. MODE `value` misses a name whose value differs from the
# expected one; `present` misses only an unset name.
stub_dir() {
  local dir="$1" mode="$2" tool test
  mkdir -p -- "$dir/bin"
  for tool in "${allowed[@]}"; do ln -s -- "${tool_at[$tool]}" "$dir/bin/$tool"; done
  if [[ ${3:-} == node ]]; then ln -s -- "$node_bin" "$dir/bin/node"; fi
  case "$mode" in
    value) test='[[ ${!name-} == "${pair#*=}" ]]' ;;
    present) test='[[ -n ${!name+set} ]]' ;;
  esac
  {
    printf '#!%s\n' "$BASH"
    printf 'expected=(%s)\n' "$(printf '%q ' "${expected[@]}")"
    printf 'missing=()\n'
    printf 'for pair in "${expected[@]}"; do name="${pair%%%%=*}"; %s || missing+=("$name"); done\n' "$test"
    printf 'names="${missing[*]}"\n'
    printf 'printf '\''call=%%s missing=%%s\\n'\'' "${1:-}" "${names// /,}" >>%q\n' "$dir/gum.log"
    printf 'exit 130\n'
  } >"$dir/bin/gum"
  chmod +x -- "$dir/bin/gum"
}

# run_tui STUBS PRESENTER PLUGIN_ID PLUGIN_DIR SCRIPT GUM_ENV: one presented
# run with PATH the stub directory STUBS/bin and a fresh scratch world under
# STUBS, its gum.env the synthetic one with GUM_ENV `with`, none with
# `without`. The gum calls land in STUBS/gum.log, the terminal's text in
# STUBS/out and the status in run_status.
run_tui() {
  local stubs="$1" world="$1/world" cmd
  rm -rf -- "$world" "$stubs/gum.log"
  mkdir -p -- "$world/home" "$world/state/vgshell/theme" "$world/config" "$world/data" "$world/rt"
  if [[ $6 == with ]]; then cp -- "$synthetic" "$world/state/vgshell/theme/gum.env"; fi
  cmd="$(printf '%q ' "$2" present --presentation plain --plugin "$3" --dir "$4" -- "$5")"
  run_status=0
  timeout -k 2 "$ceiling" env -i PATH="$stubs/bin" HOME="$world/home" XDG_STATE_HOME="$world/state" \
    XDG_CONFIG_HOME="$world/config" XDG_DATA_HOME="$world/data" XDG_RUNTIME_DIR="$world/rt" \
    TERM=xterm-256color COLORTERM=truecolor "$script_bin" -qec "$cmd" /dev/null </dev/null >"$stubs/out" 2>&1 ||
    run_status=$?
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

stub_dir "$tmp/plain" value

# Discovery from the tree: every shipped TUI script.
shopt -s nullglob
scripts=("$repo"/shell/plugins/*/tui/*.sh)
shopt -u nullglob
check "discovery finds TUI scripts" test "${#scripts[@]}" -gt 0
reached=0
declare -A verdict_of
for file in "${scripts[@]}"; do
  rel="${file#"$repo"/}"
  plugin_dir="${file%/tui/*}"
  run_tui "$tmp/plain" "$presenter" "${plugin_dir##*/}" "$plugin_dir" "tui/${file##*/}" with
  judge_log "$tmp/plain/gum.log"
  verdict_of[$rel]="$verdict"
  case "$verdict" in
    ok) reached=$((reached + 1)); ok "tui-gum=ok script=$rel" ;;
    uncoloured) reached=$((reached + 1)); fail "tui-gum=uncoloured script=$rel missing=$missing" ;;
    unreached) printf '  note  tui-gum=unreached script=%s exit=%s\n' "$rel" "$run_status" ;;
    *) fail "tui-gum=unparsed script=$rel log=$(paste -sd' ' "$tmp/plain/gum.log")" ;;
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

# The controls each run one planted script from a scratch copy of a plugin.
planted_plugin() { # NAME BODY: sets plugin to the copy holding tui/NAME.sh
  plugin="$tmp/plugins/$1/vgs.ai-usage"
  mkdir -p -- "$plugin"
  cp -R -- "$repo/shell/plugins/vgs.ai-usage/." "$plugin/"
  printf '#!/usr/bin/env bash\n%s\n' "$2" >"$plugin/tui/$1.sh"
  chmod +x -- "$plugin/tui/$1.sh"
}

# (a) gum under `env -i` loses every colour the presenter exported.
planted_plugin stripped 'env -i PATH="$PATH" gum choose a b'
run_tui "$tmp/plain" "$presenter" vgs.ai-usage "$plugin" tui/stripped.sh with
judge_log "$tmp/plain/gum.log"
check "control: a script that strips the environment is uncoloured" test "$verdict" == uncoloured

# (b) and (c): no gum.env, with node for the judge and a script that only
# calls gum.
stub_dir "$tmp/node" present node
planted_plugin asks 'gum choose a b'
copy_with no-default "$presenter" \
  '  text="$(node "$root/bin/vgshell-theme-judge" default-file gum 2>/dev/null)" || status=$?' '  return 0'
mkdir -p -- "$tmp/no-default/bin"
cp -- "$copy" "$tmp/no-default/bin/vgshell-tui"
chmod +x -- "$tmp/no-default/bin/vgshell-tui"
ln -s -- "$repo/bin/lib" "$tmp/no-default/bin/lib"
ln -s -- "$repo/bin/vgshell-theme-judge" "$tmp/no-default/bin/vgshell-theme-judge"
run_tui "$tmp/node" "$tmp/no-default/bin/vgshell-tui" vgs.ai-usage "$plugin" tui/asks.sh without
judge_log "$tmp/node/gum.log"
check "control: a presenter without its no-gum.env branch is uncoloured" test "$verdict" == uncoloured
run_tui "$tmp/node" "$presenter" vgs.ai-usage "$plugin" tui/asks.sh without
judge_log "$tmp/node/gum.log"
check "with no gum.env the presenter colours gum from the vgs package" test "$verdict" == ok

rows_done test-tui-gum-colours
