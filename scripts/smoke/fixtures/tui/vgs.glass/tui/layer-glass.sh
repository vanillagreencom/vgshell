#!/usr/bin/env bash
# Synthetic manager only: the row owns this state under its sandbox home.
set -euo pipefail
state="$XDG_STATE_HOME/vgshell/layer-glass-fixture"
[[ $# == 1 && $1 =~ ^(prepare|rebuild|enable|disable)$ && -d $state ]] || exit 2
printf '%s\n' "$1" >>"$state/calls"
hold="$state/hold"
[[ $1 != disable ]] || hold="$state/disable-hold"
for ((tick=0; tick<2400; tick++)); do
  [[ -e $hold ]] || break
  sleep 0.05
done
[[ ! -e $hold ]] || exit 1
code=0
[[ ! -f $state/exit ]] || read -r code <"$state/exit"
if [[ $1 == disable && -f $state/disable-exit ]]; then read -r code <"$state/disable-exit"; fi
[[ $code == 0 ]] || exit "$code"
case $1 in
  prepare) : ;;
  rebuild) printf 'false\n' >"$state/loaded" ;;
  enable) [[ $(<"$state/loaded") == true ]] || exit 1; printf 'true\n' >"$state/enabled" ;;
  disable) printf 'false\n' >"$state/loaded"; printf 'false\n' >"$state/enabled" ;;
esac
