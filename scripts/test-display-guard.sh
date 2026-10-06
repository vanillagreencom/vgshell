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
  printf '%s\n' "$HYPRCTL_MONITORS"
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
# The fields the read-back compares, as `hyprctl -j monitors all` prints
# them: DP-1 on and mirroring nothing.
ONE='[{"id":0,"name":"DP-1","description":"Dell U2720Q 8YT","width":100,"height":100,"refreshRate":60,"scale":1,"transform":0,"disabled":false,"mirrorOf":"none"}]'
export HYPRCTL_MONITORS=$ONE

# readback RESTORE_JSON MONITORS: the guard's read-back verdict for a
# restore of RESTORE_JSON when Hyprland then lists MONITORS. GUARD_COPY
# runs in place of the guard when set.
readback() {
  : >"$SCRATCH/token"
  HYPRCTL_MONITORS=$2 "${GUARD_COPY:-$GUARD}" "$(date +%s)" "$SCRATCH/token" "sig" 'hl.monitor({ output = "DP-2", scale = 1 })' "$1" | grep -o 'readback=[^ ]*'
}

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

MIRRORED='[{"id":0,"name":"DP-1","description":"Dell U2720Q 8YT","width":100,"height":100,"refreshRate":60,"scale":1,"transform":0,"disabled":false,"mirrorOf":"none"},{"id":1,"name":"DP-2","description":"","width":100,"height":100,"refreshRate":60,"scale":1,"transform":0,"disabled":false,"mirrorOf":"0"}]'
UNMIRRORED=${MIRRORED/\"mirrorOf\":\"0\"/\"mirrorOf\":\"none\"}
OFF=${ONE/\"disabled\":false/\"disabled\":true}
# rows: name|restore JSON|monitors|verdict
while IFS='|' read -r name restore monitors want; do
  check "readback: $name" "$(readback "$restore" "${!monitors}")" "readback=$want"
done <<'ROWS'
a mirror by description matches|{"DP-2":{"mirror":"desc:Dell U2720Q 8YT"}}|MIRRORED|match
a mirror by connector matches|{"DP-2":{"mirror":"DP-1"}}|MIRRORED|match
a mirror Hyprland dropped mismatches|{"DP-2":{"mirror":"DP-1"}}|UNMIRRORED|mismatch
a mirror onto another output mismatches|{"DP-2":{"mirror":"DP-3"}}|MIRRORED|mismatch
a mirror Hyprland kept mismatches a rule with none|{"DP-2":{"scale":1}}|MIRRORED|mismatch
an output left off mismatches a rule that turns it on|{"DP-1":{"scale":1}}|OFF|mismatch
an output off matches a rule that turns it off|{"DP-1":{"disabled":true}}|OFF|match
ROWS

for mutant in never-reverts restores-before-claim ignores-mirror ignores-disabled ignores-kept-mirror; do
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
    ignores-mirror|ignores-disabled|ignores-kept-mirror) python3 - "$copy" "$mutant" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
needle = {
    "ignores-mirror": 'ok = ok and target is not None and rule["mirror"] in (target["name"], "desc:" + target["description"])',
    "ignores-disabled": 'ok = ok and row.get("disabled") == rule.get("disabled", False)',
    "ignores-kept-mirror": 'ok = ok and row.get("mirrorOf") == "none"',
}[sys.argv[2]]
assert s.count(needle) == 1, needle
p.write_text(s.replace(needle, "pass"))
PY
      ;;
  esac
  chmod +x "$copy"
  case $mutant in
    ignores-mirror)
      check "control $mutant is detected" "$(GUARD_COPY=$copy readback '{"DP-2":{"mirror":"DP-1"}}' "$UNMIRRORED")" "readback=match"
      continue ;;
    ignores-disabled)
      check "control $mutant is detected" "$(GUARD_COPY=$copy readback '{"DP-1":{"scale":1}}' "$OFF")" "readback=match"
      continue ;;
    ignores-kept-mirror)
      check "control $mutant is detected" "$(GUARD_COPY=$copy readback '{"DP-2":{"scale":1}}' "$MIRRORED")" "readback=match"
      continue ;;
  esac
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
