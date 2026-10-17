#!/usr/bin/env bash
# Pins nested_xwayland_check in scripts/smoke/harness.sh, the up check
# that fails a nested run whose compositor reads Xwayland on: a killed
# Xwayland leaves its X socket and lock file in the host's /tmp. Each case
# runs the extracted function in a clean bash that sources
# scripts/smoke/hypr-call.sh, the harness's one nested hyprctl caller, with
# a stand-in hyprctl first on PATH and in shell_env, and no
# WAYLAND_DISPLAY, DISPLAY, HYPRLAND_INSTANCE_SIGNATURE or XDG_RUNTIME_DIR,
# so no call reaches a live compositor. The stand-in answers the getoption
# reply its case names: the bool reply Hyprland 0.56.2 gives with
# `xwayland = { enabled = false }`, the same reply reading on, as without
# that line, a failed call and replies that hold no bool. The
# controls at the end plant one defect per rule in a copy of the function
# and require the case that rule owns to go red.
#
# Exit 0 when every case and control holds, 1 otherwise.
set -euo pipefail
unset WAYLAND_DISPLAY WAYLAND_SOCKET DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_RUNTIME_DIR

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"

tmp="$(mktemp -d)" || { echo "test-smoke-xwayland: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $tmp && ! -L $tmp ]] || { echo "test-smoke-xwayland: scratch=not-a-directory value=[$tmp]" >&2; exit 1; }
tmp="$(cd -- "$tmp" && pwd -P)" || { echo "test-smoke-xwayland: scratch=resolve-failed" >&2; exit 1; }
trap 'rm -rf -- "${tmp:?}"' EXIT

failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

# The stand-in logs its argv and answers its case's reply file; a reply
# file holding `exit N` makes it fail with status N and print nothing.
stubs="$tmp/stubs"
mkdir -p -- "$stubs"
cat >"$stubs/hyprctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CASE_DIR/calls"
reply="$(<"$CASE_DIR/reply")"
if [[ $reply == "exit "* ]]; then exit "${reply#exit }"; fi
printf '%s\n' "$reply"
SH
chmod 755 "$stubs/hyprctl"

subject="$tmp/xwayland-check.sh"
sed -n '/^nested_xwayland_check() {/,/^}/p' "$repo/scripts/smoke/harness.sh" >"$subject"
if [[ $(grep -c '^nested_xwayland_check() {' "$subject") != 1 || $(grep -c 'hypr -j getoption xwayland:enabled' "$subject") != 1 ]]; then
  echo "test-smoke-xwayland: extract=missing-or-ambiguous harness=scripts/smoke/harness.sh" >&2
  exit 1
fi

# NAME|REPLY|WANT: WANT is `ok` or the value the keyed failure names.
cases=(
  'the compositor reads Xwayland off|{"option": "xwayland:enabled", "bool": false, "set": true}|ok'
  'the compositor without the config line reads Xwayland on|{"option": "xwayland:enabled", "bool": true, "set": false}|1'
  'a failed call is no pass|exit 3|unreadable'
  'a reply that is not JSON is no pass|no such option|unreadable'
  'a reply with no bool is no pass|{"option": "xwayland:enabled", "set": false}|unreadable'
  'a bool given as text is no pass|{"option": "xwayland:enabled", "bool": "false", "set": true}|unreadable'
)

# run_case FUNCTION REPLY WANT: prints nothing when the check gives WANT
# and asked the nested instance once, else the problems found.
run_case() {
  local function="$1" reply="$2" want="$3" dir out status=0 problems=()
  dir="$(mktemp -d "$tmp/case.XXXXXX")"
  mkdir -p -- "$dir/sandbox"
  printf '%s\n' "$reply" >"$dir/reply"
  out="$(timeout -k 1 20 env -i PATH="$stubs:$PATH" HOME="$tmp" LC_ALL=C CASE_DIR="$dir" "$BASH" -c '
    set -euo pipefail
    ok() { printf "  ok    %s\n" "$*"; }
    fail() { printf "  FAIL  %s\n" "$*"; }
    smoke_finish() { exit 1; }
    sandbox="$CASE_DIR/sandbox" signature=test-signature
    shell_env=(env -i PATH="$PATH" CASE_DIR="$CASE_DIR")
    source "$1"
    source "$2"
    nested_xwayland_check' _ "$repo/scripts/smoke/hypr-call.sh" "$function" </dev/null 2>&1)" || status=$?
  [[ $status -eq 0 ]] || problems+=("status=$status")
  if [[ $want == ok ]]; then
    grep -qx '  ok    .*xwayland:enabled 0' <<<"$out" || problems+=("no ok line")
    [[ $out != *'  FAIL  '* ]] || problems+=("a FAIL line was printed")
  else
    [[ $(grep -cx "  FAIL  nested-xwayland: enabled=$want want=0" <<<"$out") == 1 ]] || problems+=("no keyed failure enabled=$want")
    [[ $(grep -c '^  FAIL  ' <<<"$out") == 1 ]] || problems+=("FAIL lines other than the keyed one")
    [[ $out != *'  ok    '* ]] || problems+=("an ok line was printed")
  fi
  if [[ ! -e $dir/calls || $(<"$dir/calls") != '-i test-signature -j getoption xwayland:enabled' ]]; then
    problems+=("calls=[$(cat -- "$dir/calls" 2>/dev/null || true)] want one call to the nested instance")
  fi
  [[ ${#problems[@]} -eq 0 ]] && return 0
  printf '%s;' "${problems[@]}"
  printf ' output: %s\n' "${out//$'\n'/ | }"
  return 1
}

for row in "${cases[@]}"; do
  IFS='|' read -r label reply want <<<"$row"
  if detail="$(run_case "$subject" "$reply" "$want")"; then ok "$label"; else fail "$label"; printf '        %s\n' "$detail"; fi
done

# mutate OLD NEW OUT: a copy of the function with OLD, which must occur
# once, replaced by NEW.
mutate() {
  local text rest count
  text="$(<"$subject")"
  rest="${text//"$1"/}"
  count=$(( (${#text} - ${#rest}) / ${#1} ))
  if [[ $count -ne 1 ]]; then
    printf '        mutation matched %s times: %s\n' "$count" "$1"
    return 1
  fi
  printf '%s\n' "${text/"$1"/"$2"}" >"$3"
  cmp -s -- "$subject" "$3" && { printf '        mutation left the file unchanged: %s\n' "$1"; return 1; }
  return 0
}

# Rows: label @ text @ replacement @ the case label that must go red. A
# field holds no `@`, the separator.
controls=(
  "Xwayland on passes@[[ \$enabled == 0 ]]@[[ \$enabled == 0 || \$enabled == 1 ]]@the compositor without the config line reads Xwayland on"
  "a failed call passes@getoption xwayland:enabled)\"; then
    enabled=unreadable@getoption xwayland:enabled)\"; then
    enabled=0@a failed call is no pass"
  "a reply with no bool passes@    print(\"unreadable\")@    print(0)@a reply with no bool is no pass"
  "the call skips the nested instance@hypr -j getoption@hyprctl -j getoption@the compositor reads Xwayland off"
)
for i in "${!controls[@]}"; do
  IFS='@' read -r -d '' label old new target <<<"${controls[i]}" || true
  target="${target%$'\n'}"
  mutant="$tmp/mutant-$i.sh"
  if ! mutate "$old" "$new" "$mutant"; then fail "control: $label"; continue; fi
  row=""
  for candidate in "${cases[@]}"; do [[ ${candidate%%|*} == "$target" ]] && row="$candidate"; done
  if [[ -z $row ]]; then fail "control: $label names no case: $target"; continue; fi
  IFS='|' read -r _ reply want <<<"$row"
  if detail="$(run_case "$mutant" "$reply" "$want")"; then
    fail "control: $label left '$target' green"
  else
    ok "control: $label"
    printf '  CONTROL  %s\n' "$detail"
  fi
done

if [[ $failures -gt 0 ]]; then
  echo "test-smoke-xwayland: failed=$failures"
  exit 1
fi
echo "test-smoke-xwayland: ok"
