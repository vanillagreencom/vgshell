#!/usr/bin/env bash
# The vgs.agent-debug floating TUIs, shell/plugins/vgs.agent-debug/tui/
# diagnose.sh and unmute.sh, under a scratch HOME and a PATH of stand-ins.
# diagnose.sh: each agent starts in its default mode with the whole prompt as
# one argument, in its own folder under the runtime dir, the prompt holds
# every fact and never the run record's lines, a sync run short of a fact
# starts no agent, the vgs-diagnose skill is
# copied into the agent's own skills folder where no file or only VGS's own
# copy stands, a foreign file, a link and a linked folder are left as they
# are with the prompt naming the plugin's copy. unmute.sh: a yes asks the
# service to unmute that program, a program already unmuted is done, and a
# refusal ends the run failed with a sentence, never the reply's key. No run
# reaches a real agent or the shell: each agent and vgshell is a stand-in
# that records its argv.
#
# The controls at the end edit a copy of a script, one rule at a time, and
# require a case to fail on each copy.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
plugin="$repo/shell/plugins/vgs.agent-debug"
TMP_ROOT="$(mktemp -d)" || { echo "test-agent-debug-tui: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $TMP_ROOT && ! -L $TMP_ROOT ]] || { echo "test-agent-debug-tui: scratch=not-a-directory value=[$TMP_ROOT]" >&2; exit 1; }
TMP_ROOT="$(cd -- "$TMP_ROOT" && pwd -P)" || { echo "test-agent-debug-tui: scratch=resolve-failed" >&2; exit 1; }
trap 'rm -rf -- "${TMP_ROOT:?}"' EXIT
for tool in setsid node python3 awk cmp mktemp; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'test-agent-debug-tui: status=not-measured missing=%s\n' "$tool"
    exit 77
  fi
done

failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

tools="$TMP_ROOT/tools"
mkdir -p "$tools"
for tool in bash node python3 awk cmp mkdir mktemp cp mv rm cat; do ln -s -- "$(command -v "$tool")" "$tools/$tool"; done
# Each agent and vgshell records its argv as one JSON line in
# $TMP_ROOT/calls, and its working folder in $TMP_ROOT/cwd. vgshell answers what $TMP_ROOT/answer holds.
for agent in claude codex copilot pi opencode vgshell; do
  cat >"$tools/$agent" <<SH
#!/usr/bin/env bash
python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "\${0##*/}" "\$@" >>"$TMP_ROOT/calls"
printf '%s' "\$PWD" >"$TMP_ROOT/cwd"
if [[ \${0##*/} == vgshell ]]; then cat -- "$TMP_ROOT/answer"; fi
SH
done
# gum draws the library's header as its words.
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*"\n' >"$tools/gum"
chmod 755 "$tools"/{claude,codex,copilot,pi,opencode,vgshell,gum}

# The plugin as bin/vgshell-tui hands it to a script: a private copy.
snapshot="$TMP_ROOT/snapshot"
cp -R -- "$plugin" "$snapshot"
shipped="$snapshot/skills/vgs-diagnose/SKILL.md"
home="$TMP_ROOT/home"
runtime="$TMP_ROOT/runtime"
mkdir -p "$runtime"

# run SCRIPT ARGS...: SCRIPT with ARGS under a fresh HOME the case may
# have planted first, no terminal and a PATH of the stand-ins; the exit
# status in $status, the recorded calls in $calls. The library answers its
# yes or no question Yes with no terminal (VGS_TUI_UNATTENDED); its No and
# the answers' codes are scripts/test-tui.sh's.
run() {
  local script="$1"
  shift
  : >"$TMP_ROOT/calls"
  status=0
  setsid -w env -i PATH="$tools" HOME="$home" XDG_RUNTIME_DIR="$runtime" VGS_PLUGIN_DIR="$snapshot" VGS_TUI_LIB="$repo/bin/lib/tui.sh" VGS_TUI_UNATTENDED=1 \
    bash "$script" "$@" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" </dev/null || status=$?
  calls="$(cat "$TMP_ROOT/calls")"
}
fresh_home() { rm -rf -- "${home:?}"; mkdir -p -- "$home"; }
# words ARGS...: ARGS as one JSON list, as the stand-ins record them.
words() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@"; }
# A run record holding a token-shaped line, which no prompt may carry.
record="$TMP_ROOT/run/core@requirements-install@k3q9x2.ended.json"
mkdir -p "$TMP_ROOT/run"
printf '{"code":1,"package":{"kind":"package-failed","lines":["token=agent-debug-secret"]}}\n' >"$record"
# The agents' working folder under the runtime dir.
work="$runtime/vgshell/agent-debug"
crash_facts=(crash "ad 'x;\$(id)" 4242 SIGSEGV "2026-11-03T13:40:00-08:00" "/tmp/ad bin")
task_facts=(task vgs.printers install pacman "cups, gum" "2026-11-03T13:40:00-08:00" "$record")
sync_facts=(sync scribd-brain-backup.service "Scribd brain" rsync "/home/u/brain \$(id)" /mnt/backup/brain "rsync error: some files could not be transferred (code 23)" "2026-11-03T13:40:00-08:00")
crash_prompt() { # SKILL
  printf '%s\n' "A program crashed on this computer and I want to know why." "What systemd-coredump recorded:" \
    "- Program: ad 'x;\$(id)" "- Process ID: 4242" "- Binary: /tmp/ad bin" "- Signal: SIGSEGV" "- Time: 2026-11-03T13:40:00-08:00" \
    "Use the vgs-diagnose skill. If you cannot load skills, read $1 and follow it." "Diagnose only: change nothing on this computer." | python3 -c 'import sys; sys.stdout.write(sys.stdin.read()[:-1])'
}
task_prompt() { # SKILL
  printf '%s\n' "A VGS setup task failed on this computer and I want to know why." "- Task: install the tools of the VGS plugin vgs.printers" \
    "- Package manager: pacman" "- Packages: cups, gum" "- Time: 2026-11-03T13:40:00-08:00" "- Run record: $record" \
    "Use the vgs-diagnose skill. If you cannot load skills, read $1 and follow it." "Diagnose only: change nothing on this computer." | python3 -c 'import sys; sys.stdout.write(sys.stdin.read()[:-1])'
}
sync_prompt() { # SKILL
  printf '%s\n' "A sync job on this computer failed and I want to know why." "- System job: scribd-brain-backup.service (a systemd user unit)" \
    "- Name: Scribd brain" "- Engine: rsync" "- From: /home/u/brain \$(id)" "- To: /mnt/backup/brain" \
    "- Last error line: rsync error: some files could not be transferred (code 23)" "- Time: 2026-11-03T13:40:00-08:00" \
    "Use the vgs-diagnose skill. If you cannot load skills, read $1 and follow it." "Diagnose only: change nothing on this computer." | python3 -c 'import sys; sys.stdout.write(sys.stdin.read()[:-1])'
}

# The cases, each a check on one or more runs: they return 1 on a miss.
# Each agent's argv and skills folder: [agent, folder, argv before the
# prompt].
AGENT_ROWS=(
  "claude|.claude/skills|--permission-mode default"
  "codex|.agents/skills|--sandbox read-only --ask-for-approval on-request"
  "copilot|.copilot/skills|--interactive"
  "pi|.pi/agent/skills|"
  "opencode|.config/opencode/skills|--prompt"
)
case_each_agent_starts_with_the_prompt_and_its_skill() {
  local row agent folder flags copy
  for row in "${AGENT_ROWS[@]}"; do
    IFS='|' read -r agent folder flags <<<"$row"
    fresh_home
    run "$1" "$agent" "${crash_facts[@]}"
    copy="$home/$folder/vgs-diagnose/SKILL.md"
    # shellcheck disable=SC2086
    [[ $status == 0 && $calls == "$(words "$agent" $flags "$(crash_prompt "$copy")")" ]] || { detail="agent=$agent"; return 1; }
    [[ $(cat "$TMP_ROOT/cwd") == "$work" ]] || { detail="agent=$agent cwd=$(cat "$TMP_ROOT/cwd")"; return 1; }
    cmp -s -- "$shipped" "$copy" || { detail="agent=$agent skill"; return 1; }
  done
}
case_the_task_prompt_names_the_record_never_its_lines() {
  fresh_home
  run "$1" claude "${task_facts[@]}"
  [[ $status == 0 && $calls == "$(words claude --permission-mode default "$(task_prompt "$home/.claude/skills/vgs-diagnose/SKILL.md")")" ]]
}
case_the_sync_prompt_holds_every_fact() {
  fresh_home
  run "$1" claude "${sync_facts[@]}"
  [[ $status == 0 && $calls == "$(words claude --permission-mode default "$(sync_prompt "$home/.claude/skills/vgs-diagnose/SKILL.md")")" ]]
}
# A sync run missing its time starts no agent.
case_a_short_sync_run_is_refused() {
  fresh_home
  run "$1" claude "${sync_facts[@]:0:7}"
  [[ $status == 2 && -z $calls ]]
}
case_an_older_vgs_copy_is_replaced() {
  fresh_home
  mkdir -p "$home/.claude/skills/vgs-diagnose"
  printf -- '---\nname: vgs-diagnose\nmetadata:\n  source: vgshell\n---\nold\n' >"$home/.claude/skills/vgs-diagnose/SKILL.md"
  run "$1" claude "${crash_facts[@]}"
  [[ $status == 0 ]] && cmp -s -- "$shipped" "$home/.claude/skills/vgs-diagnose/SKILL.md" && [[ -z $(ls -A -- "$home/.claude/skills/vgs-diagnose" | grep -v -x SKILL.md) ]]
}
case_a_foreign_skill_is_left_and_the_prompt_names_the_shipped_copy() {
  fresh_home
  mkdir -p "$home/.claude/skills/vgs-diagnose"
  printf -- '---\nname: vgs-diagnose\n---\nmine, source: vgshell\n' >"$home/.claude/skills/vgs-diagnose/SKILL.md"
  run "$1" claude "${crash_facts[@]}"
  [[ $status == 0 && $(cat "$home/.claude/skills/vgs-diagnose/SKILL.md") == $'---\nname: vgs-diagnose\n---\nmine, source: vgshell' ]] &&
    [[ $calls == "$(words claude --permission-mode default "$(crash_prompt "$shipped")")" ]]
}
case_a_linked_skill_is_left() {
  fresh_home
  mkdir -p "$home/.claude/skills/vgs-diagnose" "$TMP_ROOT/elsewhere"
  printf -- '---\nmetadata:\n  source: vgshell\n---\nlinked\n' >"$TMP_ROOT/elsewhere/SKILL.md"
  ln -s -- "$TMP_ROOT/elsewhere/SKILL.md" "$home/.claude/skills/vgs-diagnose/SKILL.md"
  run "$1" claude "${crash_facts[@]}"
  [[ $status == 0 && -L $home/.claude/skills/vgs-diagnose/SKILL.md && $(cat "$TMP_ROOT/elsewhere/SKILL.md") == $'---\nmetadata:\n  source: vgshell\n---\nlinked' ]] &&
    [[ $calls == "$(words claude --permission-mode default "$(crash_prompt "$shipped")")" ]]
}
case_a_linked_folder_is_left() {
  fresh_home
  mkdir -p "$home/.claude/skills" "$TMP_ROOT/folder"
  ln -s -- "$TMP_ROOT/folder" "$home/.claude/skills/vgs-diagnose"
  run "$1" claude "${crash_facts[@]}"
  [[ $status == 0 && -z $(ls -A -- "$TMP_ROOT/folder") ]] && [[ $calls == "$(words claude --permission-mode default "$(crash_prompt "$shipped")")" ]]
}
case_unmute_yes_asks_the_service() {
  printf 'ok\n' >"$TMP_ROOT/answer"
  run "$1" "Web Content"
  [[ $status == 0 && $calls == "$(words vgshell ipc call vgs.agent-debug invoke unmute "Web Content")" ]]
}
case_unmute_of_an_unmuted_program_is_done() {
  printf 'refused: program=unmuted\n' >"$TMP_ROOT/answer"
  run "$1" firefox
  [[ $status == 0 && $calls == "$(words vgshell ipc call vgs.agent-debug invoke unmute firefox)" ]]
}
# A refusal fails the run with a sentence, never the service's key.
case_unmute_refused_fails_plainly() {
  printf 'refused: user-config=malformed path=/x\n' >"$TMP_ROOT/answer"
  run "$1" firefox
  [[ $status == 1 && $(cat "$TMP_ROOT/err") != *"user-config"* ]]
}
CASES=(case_each_agent_starts_with_the_prompt_and_its_skill case_the_task_prompt_names_the_record_never_its_lines
  case_the_sync_prompt_holds_every_fact case_a_short_sync_run_is_refused case_an_older_vgs_copy_is_replaced
  case_a_foreign_skill_is_left_and_the_prompt_names_the_shipped_copy case_a_linked_skill_is_left case_a_linked_folder_is_left
  case_unmute_yes_asks_the_service case_unmute_of_an_unmuted_program_is_done case_unmute_refused_fails_plainly)
SCRIPTS=(diagnose.sh diagnose.sh diagnose.sh diagnose.sh diagnose.sh diagnose.sh diagnose.sh diagnose.sh unmute.sh unmute.sh unmute.sh)
for i in "${!CASES[@]}"; do
  case="${CASES[i]}"
  detail="" status="" calls=""
  if "$case" "$plugin/tui/${SCRIPTS[i]}"; then ok "${case#case_}"; else fail "${case#case_}: $detail status=$status calls=[${calls//$'\n'/;}] err=[$(head -n 1 "$TMP_ROOT/err")]"; fi
done

# Controls: a case, the script, the line it needs and a replacement
# without the rule.
CONTROL_CASES=(case_each_agent_starts_with_the_prompt_and_its_skill case_each_agent_starts_with_the_prompt_and_its_skill case_each_agent_starts_with_the_prompt_and_its_skill
  case_a_foreign_skill_is_left_and_the_prompt_names_the_shipped_copy case_a_linked_skill_is_left case_a_linked_folder_is_left
  case_the_sync_prompt_holds_every_fact case_a_short_sync_run_is_refused
  case_unmute_yes_asks_the_service case_unmute_of_an_unmuted_program_is_done case_unmute_refused_fails_plainly)
CONTROL_SCRIPTS=(diagnose.sh diagnose.sh diagnose.sh diagnose.sh diagnose.sh diagnose.sh diagnose.sh diagnose.sh unmute.sh unmute.sh unmute.sh)
CONTROL_LINES=(
  '  codex) exec codex --sandbox read-only --ask-for-approval on-request "$prompt" ;;'
  'if install_skill 2>/dev/null; then skill="$copy"; else skill="$shipped"; fi'
  'cd -- "$work"'
  '    ours "$copy" || return 1'
  '  [[ -f $1 && ! -L $1 ]] || return 1'
  '  [[ ! -L $folder ]] || return 1'
  '  sync) (( $# == 9 )) || refuse ;;'
  '  sync) (( $# == 9 )) || refuse ;;'
  'answer="$(vgshell ipc call vgs.agent-debug invoke unmute "$program")" || answer=""'
  '  ok | "refused: program=unmuted") ;;'
  '  "refused: user-config="*) vgs_tui_error "VGS could not save its settings file, so $program stays muted."; exit 1 ;;'
)
CONTROL_REPLACEMENTS=(
  '  codex) exec codex --sandbox danger-full-access --ask-for-approval never "$prompt" ;;'
  'skill="$shipped"'
  'cd -- "$HOME"'
  '    true'
  '  [[ -f $1 ]] || return 1'
  '  true'
  '  sync) refuse ;;'
  '  sync) (( $# >= 8 )) || refuse ;;'
  'answer="$(vgshell ipc call vgs.agent-debug invoke unmute "x")" || answer=""'
  '  ok) ;;'
  '  "refused: user-config="*) vgs_tui_error "$answer"; exit 1 ;;'
)
for i in "${!CONTROL_CASES[@]}"; do
  case="${CONTROL_CASES[i]}"
  copy="$TMP_ROOT/copy.sh"
  if ! python3 - "$plugin/tui/${CONTROL_SCRIPTS[i]}" "$copy" "${CONTROL_LINES[i]}" "${CONTROL_REPLACEMENTS[i]}" <<'PY'
import sys
lines = open(sys.argv[1]).read().split("\n")
hits = [i for i, line in enumerate(lines) if line == sys.argv[3]]
if len(hits) != 1:
    sys.exit("control line occurs %d times: %s" % (len(hits), sys.argv[3]))
lines[hits[0]] = sys.argv[4]
open(sys.argv[2], "w").write("\n".join(lines))
PY
  then
    fail "control $i $case: its line must occur once"
  elif "$case" "$copy"; then
    fail "control $i $case: passed on a copy without the rule"
  else
    ok "control $i $case"
  fi
done

if [[ $failures -gt 0 ]]; then
  printf 'test-agent-debug-tui: failures=%d\n' "$failures"
  exit 1
fi
printf 'test-agent-debug-tui: ok cases=%d controls=%d\n' "${#CASES[@]}" "${#CONTROL_CASES[@]}"
