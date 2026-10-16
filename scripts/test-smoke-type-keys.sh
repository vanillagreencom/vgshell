#!/usr/bin/env bash
# Pins the display guard of type_keys in scripts/smoke/harness.sh, the
# harness's one key tool: it calls wtype only when shell_env starts from an
# empty environment and names the socket the harness started, and every
# other shell_env gets the keyed refusal with no wtype process. Each case
# runs the extracted function in a clean bash whose PATH puts a recording
# wtype stub first and whose environment carries no WAYLAND_DISPLAY,
# DISPLAY or HYPRLAND_INSTANCE_SIGNATURE, so a guard the stub does not see
# reaches no display either. The host socket shares the nested socket's
# name, as wayland-1 can on a live session. The controls at the end plant
# one defect per rule in a copy of the function and require the case that
# rule owns to go red.
#
# Exit 0 when every case and control holds, 1 otherwise.
set -euo pipefail
unset WAYLAND_DISPLAY WAYLAND_SOCKET DISPLAY HYPRLAND_INSTANCE_SIGNATURE

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"

tmp="$(mktemp -d)" || { echo "test-smoke-type-keys: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $tmp && ! -L $tmp ]] || { echo "test-smoke-type-keys: scratch=not-a-directory value=[$tmp]" >&2; exit 1; }
tmp="$(cd -- "$tmp" && pwd -P)" || { echo "test-smoke-type-keys: scratch=resolve-failed" >&2; exit 1; }
trap 'rm -rf -- "${tmp:?}"' EXIT
# Case words split on spaces, so the paths they name hold none.
[[ $tmp != *[[:space:]]* ]] || { echo "test-smoke-type-keys: scratch=has-space value=[$tmp]" >&2; exit 1; }

failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

stubs="$tmp/stubs" calls="$tmp/wtype.calls"
mkdir -p -- "$stubs" "$tmp/rt" "$tmp/host"
printf '#!%s\nprintf %q "$*" "${WAYLAND_DISPLAY:-}" "${XDG_RUNTIME_DIR:-}" >>%q\n' \
  "$BASH" 'args=%s display=%s runtime=%s\n' "$calls" >"$stubs/wtype"
chmod 755 "$stubs/wtype"
test_env=(env -i PATH="$stubs:$PATH" HOME="$tmp" LC_ALL=C TMPDIR="$tmp")

subject="$tmp/type-keys.sh"
sed -n '/^type_keys() {/,/^}/p' "$repo/scripts/smoke/harness.sh" >"$subject"
if [[ $(grep -c '^type_keys() {' "$subject") != 1 || $(grep -c 'wtype "\$@"' "$subject") != 1 ]]; then
  echo "test-smoke-type-keys: extract=missing-or-ambiguous harness=scripts/smoke/harness.sh" >&2
  exit 1
fi

# NAME|WANT|SHELL_ENV words, @stubs, @rt and @host expanded. The nested
# socket is @rt/wayland-1; the host's is @host/wayland-1.
cases=(
  "the nested socket by name in the sandbox runtime directory|accepted|env -i PATH=@stubs XDG_RUNTIME_DIR=@rt WAYLAND_DISPLAY=wayland-1"
  "the nested socket by absolute path|accepted|env -i PATH=@stubs WAYLAND_DISPLAY=@rt/wayland-1"
  "shell_env replaced by command|refused|command"
  "an empty shell_env|refused|"
  "env without -i, which keeps the caller's environment|refused|env PATH=@stubs XDG_RUNTIME_DIR=@rt WAYLAND_DISPLAY=wayland-1"
  "no WAYLAND_DISPLAY word|refused|env -i PATH=@stubs XDG_RUNTIME_DIR=@rt"
  "the nested socket's name in the host runtime directory|refused|env -i PATH=@stubs XDG_RUNTIME_DIR=@host WAYLAND_DISPLAY=wayland-1"
  "a later WAYLAND_DISPLAY word naming the host socket|refused|env -i PATH=@stubs XDG_RUNTIME_DIR=@rt WAYLAND_DISPLAY=wayland-1 WAYLAND_DISPLAY=@host/wayland-1"
)

# run_case FUNCTION WANT WORDS: prints nothing when type_keys -k Escape
# gives WANT, else the problems found.
run_case() {
  local function="$1" want="$2" words="$3" status=0 refusals=0 line problems=()
  words="${words//@stubs/$stubs}"
  words="${words//@rt/$tmp/rt}"
  words="${words//@host/$tmp/host}"
  rm -f -- "$calls" "$tmp/fails"
  "${test_env[@]}" CASE_WORDS="$words" CASE_RT="$tmp/rt" CASE_FAILS="$tmp/fails" "$BASH" -c '
    set -euo pipefail
    fail() { printf "%s\n" "$*" >>"$CASE_FAILS"; }
    nested_socket=wayland-1 rt_dir="$CASE_RT"
    read -r -a shell_env <<<"$CASE_WORDS"
    source "$1"
    type_keys -k Escape' _ "$function" >/dev/null 2>&1 || status=$?
  if [[ -e $tmp/fails ]]; then
    while IFS= read -r line; do
      [[ $line != "type_keys: refused socket="* ]] || refusals=$((refusals + 1))
    done <"$tmp/fails"
  fi
  case $want in
    accepted)
      [[ $status == 0 ]] || problems+=("status=$status")
      [[ $refusals == 0 ]] || problems+=("refusals=$refusals")
      [[ -e $calls && $(<"$calls") =~ ^args=-k\ Escape\ display=(.*)\ runtime=(.*)$ ]] || problems+=("wtype-calls=[$(cat -- "$calls" 2>/dev/null)]")
      # The socket wtype reached, resolved as libwayland resolves it.
      local display="${BASH_REMATCH[1]:-}" runtime="${BASH_REMATCH[2]:-}"
      [[ $display == /* ]] || display="$runtime/$display"
      [[ $display == "$tmp/rt/wayland-1" ]] || problems+=("wtype-socket=$display")
      ;;
    refused)
      [[ $status == 1 ]] || problems+=("status=$status")
      [[ $refusals == 1 ]] || problems+=("refusals=$refusals")
      [[ ! -e $calls ]] || problems+=("wtype-calls=[$(<"$calls")]")
      ;;
  esac
  [[ ${#problems[@]} == 0 ]] || printf '%s\n' "${problems[*]}"
}

# case_seen: the wtype calls the stub recorded and the refusal, as the
# last case left them.
case_seen() {
  local count=0
  [[ ! -e $calls ]] || count="$(wc -l <"$calls")" || return 1
  printf 'wtype-calls=%s' "$count"
  [[ ! -e $tmp/fails ]] || printf ' %s' "$(<"$tmp/fails")"
}

for row in "${cases[@]}"; do
  IFS='|' read -r name want words <<<"$row"
  if found="$(run_case "$subject" "$want" "$words")" && [[ -z $found ]]; then
    ok "$want: $name: $(case_seen)"
  else
    fail "$want: $name: ${found:-run_case-failed}"
  fi
done

# control NAME CASE OLD NEW: in a copy of the function with OLD replaced by
# NEW once, the case named CASE must go red.
control() {
  local name="$1" target="$2" old="$3" new="$4" mutant="$tmp/mutant.sh" row case_name want words found
  "${test_env[@]}" python3 - "$subject" "$mutant" "$old" "$new" <<'PY' || { fail "control: $name: the defect could not be planted"; return; }
from pathlib import Path
import sys
source, out, old, new = Path(sys.argv[1]).read_text(), Path(sys.argv[2]), sys.argv[3], sys.argv[4]
if source.count(old) != 1:
    print("test-smoke-type-keys: control-edit=match-count value=" + str(source.count(old)), file=sys.stderr)
    raise SystemExit(1)
out.write_text(source.replace(old, new, 1))
PY
  for row in "${cases[@]}"; do
    IFS='|' read -r case_name want words <<<"$row"
    [[ $case_name == "$target" ]] || continue
    if found="$(run_case "$mutant" "$want" "$words")" && [[ -n $found ]]; then ok "control: $name turns \"$target\" red: $found"; else fail "control: $name leaves \"$target\" green"; fi
    return
  done
  fail "control: $name names no case \"$target\""
}

control "no refusal" "shell_env replaced by command" \
  'if [[ -z ${nested_socket:-} || -z ${rt_dir:-} || $socket != "$rt_dir/$nested_socket" ]]; then' 'if false; then'
control "no -i required" "env without -i, which keeps the caller's environment" \
  '&& ${shell_env[1]:-} == -i ]]' ']]'
control "the socket name alone compared" "the nested socket's name in the host runtime directory" \
  '$socket != "$rt_dir/$nested_socket"' '${socket##*/} != "$nested_socket"'
control "the first WAYLAND_DISPLAY word taken" "a later WAYLAND_DISPLAY word naming the host socket" \
  'display="${word#*=}"' 'display="${display:-${word#*=}}"'

if [[ $failures -gt 0 ]]; then echo "test-smoke-type-keys: failures=$failures"; exit 1; fi
echo "test-smoke-type-keys: ok"
