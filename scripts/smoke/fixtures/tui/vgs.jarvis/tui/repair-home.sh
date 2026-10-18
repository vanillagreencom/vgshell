#!/usr/bin/env bash
# Only the nested fixture's saved persona is restored. No installer runs.
set -euo pipefail
cp -- "$HOME/.repair-home-persona" "$HOME/Repair Home/.agents/skills/jarvis/persona.md"
printf 'repaired\n' >"$HOME/.repair-home-pressed"
