#!/usr/bin/env bash
# Synthetic manager only: the row owns this state under its sandbox home.
set -euo pipefail
state="$XDG_STATE_HOME/vgshell/layer-glass-fixture"
[[ $# == 1 && $1 =~ ^(enable|disable|rebuild)$ && -d $state ]] || exit 2
printf '%s\n' "$1" >>"$state/calls"
for ((tick=0; tick<2400; tick++)); do
  [[ -e $state/hold ]] || break
  sleep 0.05
done
[[ ! -e $state/hold ]] || exit 1
code=0
[[ ! -f $state/exit ]] || read -r code <"$state/exit"
[[ $code == 0 ]] || exit "$code"
if [[ $1 == disable ]]; then printf 'false\n' >"$state/loaded"; else printf 'true\n' >"$state/loaded"; fi
