#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
GUARD="$ROOT/bin/vgshell-display-guard"
SCRATCH="$ROOT/tmp/test-display-guard-$$"
rm -rf -- "$SCRATCH"
mkdir -p -- "$SCRATCH/bin"
trap 'rm -rf -- "$SCRATCH"' EXIT

cat >"$SCRATCH/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HYPRCTL_LOG"
if [[ $* == *"monitors all"* ]]; then
  printf '[{"name":"DP-1","width":100,"height":100,"refreshRate":60,"scale":1,"transform":0,"disabled":false}]\n'
else
  printf 'ok\n'
fi
SH
chmod +x "$SCRATCH/bin/hyprctl"

failures=0
check() {
  local name=$1 got=$2 want=$3
  if [[ $got == "$want" ]]; then
    printf '  ok    %s\n' "$name"
  else
    failures=$((failures + 1))
    printf '  FAIL  %s\n        got  %s\n        want %s\n' "$name" "$got" "$want"
  fi
}

export PATH="$SCRATCH/bin:$PATH"
export HYPRCTL_LOG="$SCRATCH/hyprctl.log"

: >"$SCRATCH/token"
: >"$HYPRCTL_LOG"
"$GUARD" "$(date +%s)" "$SCRATCH/token" "sig" 'hl.monitor({ output = "DP-1", scale = 1 })' '{"DP-1":{"scale":1}}' >"$SCRATCH/revert.out"
check "deadline reverts" "$(wc -l <"$HYPRCTL_LOG")" "2"
check "deadline log" "$(cut -d' ' -f1 <"$SCRATCH/revert.out")" "display-guard:"
check "deadline readback compares" "$(grep -o 'readback=[^ ]*' "$SCRATCH/revert.out")" "readback=match"

: >"$SCRATCH/token"
mv -- "$SCRATCH/token" "$SCRATCH/token.keep"
: >"$HYPRCTL_LOG"
"$GUARD" "$(date +%s)" "$SCRATCH/token" "sig" 'hl.monitor({ output = "DP-1", scale = 1 })' >"$SCRATCH/keep.out"
check "keep wins before deadline" "$(wc -l <"$HYPRCTL_LOG")" "0"
check "keep log" "$(cat "$SCRATCH/keep.out")" "display-guard: token=kept path=$SCRATCH/token"

: >"$SCRATCH/token"
: >"$HYPRCTL_LOG"
(
  "$GUARD" "$(( $(date +%s) + 1 ))" "$SCRATCH/token" "sig" 'hl.monitor({ output = "DP-1", scale = 1 })' >"$SCRATCH/killed-parent.out"
) &
guard_pid=$!
sleep 0.1
wait "$guard_pid"
check "guard outlives its launcher wait" "$(wc -l <"$HYPRCTL_LOG")" "2"

for mutant in never-reverts restores-before-claim; do
  copy="$SCRATCH/$mutant"
  cp -- "$GUARD" "$copy"
  case $mutant in
    never-reverts) python3 - "$copy" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
s = s.replace('hyprctl --instance "$instance" eval "$restore_lua" >/dev/null || eval_status=$?', ': || eval_status=$?')
p.write_text(s)
PY
      ;;
    restores-before-claim) python3 - "$copy" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
s = s.replace('if ! mv -- "$token" "$claim" 2>/dev/null; then', 'hyprctl --instance "$instance" eval "$restore_lua" >/dev/null || true\nif ! mv -- "$token" "$claim" 2>/dev/null; then')
p.write_text(s)
PY
      ;;
  esac
  chmod +x "$copy"
  : >"$SCRATCH/token"
  : >"$HYPRCTL_LOG"
  "$copy" "$(date +%s)" "$SCRATCH/token" "sig" 'hl.monitor({ output = "DP-1", scale = 1 })' >/dev/null
  case $mutant in
    never-reverts) check "control $mutant is detected" "$(grep -c 'eval' "$HYPRCTL_LOG" || true)" "0" ;;
    restores-before-claim) check "control $mutant is detected" "$(grep -c 'eval' "$HYPRCTL_LOG" || true)" "2" ;;
  esac
done

if (( failures > 0 )); then
  printf 'test-display-guard: %s failing\n' "$failures"
  exit 1
fi
printf 'test-display-guard: ok\n'
