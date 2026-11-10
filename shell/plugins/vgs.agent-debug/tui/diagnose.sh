#!/usr/bin/env bash
# Agent Debug's Diagnose: the agent the user chose, in its own terminal and
# its default mode, which asks before it runs a command, with a prompt that
# holds only the facts of one failure. The service hands the facts as
# arguments, which the core judges before the run (PluginLogic.tuiArgsValid):
#
#   diagnose.sh AGENT crash PROGRAM PID SIGNAL TIME BINARY
#   diagnose.sh AGENT task PLUGIN ACTION MANAGER PACKAGES TIME RECORD
#   diagnose.sh AGENT sync UNIT NAME ENGINE FROM TO ERROR TIME
#
# AGENT is claude, codex, copilot, pi or opencode. A fact the service could
# not give is `-`. The prompt names the run record of a failed task, never
# its lines, and tells the agent to use the vgs-diagnose skill, which this
# script copies from the plugin into the agent's own skills folder first:
# only where no file stands or where the file there is one VGS wrote, a
# regular file whose front matter carries `source: vgshell`, and never
# through a link. Elsewhere the prompt names the plugin's copy, which
# bin/vgshell-tui keeps until the agent exits, since the agent takes this
# script's place. Jarvis reads the same file in place as its help topic
# vgs-diagnose; nothing writes it into a Jarvis home (D126). The agent
# starts in a folder of its own under the runtime
# dir, which holds none of the user's files, so it asks before it reads any
# file of the home folder.
set -euo pipefail
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"
# The presentation is plain, so present shows no close prompt; a failure
# before the agent starts holds the window on the library's own.
trap 'status=$?; [[ $status == 0 ]] || vgs_tui_close_prompt "$status"' EXIT

refuse() { vgs_tui_error "Agent Debug cannot start this diagnosis. Press Diagnose on the notification again."; exit 2; }
(( $# >= 2 )) || refuse
agent="$1" kind="$2"
# Each agent's personal skills folder, from its own documentation: Claude
# Code https://code.claude.com/docs/en/skills, Codex's user root
# ~/.agents/skills (codex-rs/ext/skills/src/host_roots.rs; ~/.codex/skills
# is its deprecated one), Copilot `copilot skill --help`, Pi
# packages/coding-agent/docs/skills.md, OpenCode
# https://opencode.ai/docs/skills.
case "$agent" in
  claude) skills="$HOME/.claude/skills" name="Claude Code" ;;
  codex) skills="$HOME/.agents/skills" name="Codex" ;;
  copilot) skills="$HOME/.copilot/skills" name="Copilot" ;;
  pi) skills="$HOME/.pi/agent/skills" name="Pi" ;;
  opencode) skills="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills" name="OpenCode" ;;
  *) refuse ;;
esac
case "$kind" in
  crash) (( $# == 7 )) || refuse ;;
  task) (( $# == 8 )) || refuse ;;
  sync) (( $# == 9 )) || refuse ;;
  *) refuse ;;
esac
# An agent removed since the last requirement scan, which the select still
# offered.
command -v "$agent" >/dev/null || { vgs_tui_error "$name is not installed. Choose an installed agent on the Agent Debug page in Settings."; exit 1; }

shipped="${VGS_PLUGIN_DIR:?}/skills/vgs-diagnose/SKILL.md"
folder="$skills/vgs-diagnose"
copy="$folder/SKILL.md"
# Whether FILE is a copy VGS wrote: a regular file, not a link, whose front
# matter holds the mark.
ours() {
  [[ -f $1 && ! -L $1 ]] || return 1
  awk 'NR == 1 { if ($0 != "---") exit 1; next } $0 == "---" { exit 1 } $0 == "  source: vgshell" { found = 1; exit 0 } END { exit found ? 0 : 1 }' "$1"
}
# The shipped skill in the agent's folder, written whole under a hidden name
# and renamed into place, which replaces a file and never writes through a
# link; equal bytes are left as they are.
install_skill() {
  [[ ! -L $folder ]] || return 1
  if [[ -e $copy || -L $copy ]]; then
    ours "$copy" || return 1
    if cmp -s -- "$shipped" "$copy"; then return 0; fi
  fi
  mkdir -p -- "$folder" || return 1
  local next
  next="$(mktemp -- "$folder/.SKILL.md.XXXXXX")" || return 1
  if cp -- "$shipped" "$next" && mv -f -T -- "$next" "$copy"; then return 0; fi
  rm -f -- "$next"
  return 1
}
if install_skill 2>/dev/null; then skill="$copy"; else skill="$shipped"; fi

prompt="$(node - "${VGS_TUI_LIB%/*}/qml-library.js" "${VGS_PLUGIN_DIR:?}/Diagnose.js" "$skill" "${@:2}" <<'JS'
const { load } = require(process.argv[2]);
process.stdout.write(load(process.argv[3]).prompt(process.argv.slice(5), process.argv[4]));
JS
)"

# The prompt is one argument and never a shell string. Each form starts the
# agent's interactive session in its default mode, which asks before a
# command runs: Claude Code https://code.claude.com/docs/en/cli-reference,
# Codex codex-rs/tui/src/cli.rs and codex-rs/utils/cli/src/shared_options.rs
# (read-only lets it read the journal and the core; it asks to do more),
# Copilot `copilot --help`, Pi packages/coding-agent/docs/cli.md, OpenCode
# https://opencode.ai/docs/cli. The prompt starts with a letter, so no agent
# reads it as an option.
work="${XDG_RUNTIME_DIR:?}/vgshell/agent-debug"
mkdir -p -m 700 -- "$work"
cd -- "$work"
case "$agent" in
  claude) exec claude --permission-mode default "$prompt" ;;
  codex) exec codex --sandbox read-only --ask-for-approval on-request "$prompt" ;;
  copilot) exec copilot --interactive "$prompt" ;;
  pi) exec pi "$prompt" ;;
  opencode) exec opencode --prompt "$prompt" ;;
esac
