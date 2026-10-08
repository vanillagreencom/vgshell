#!/usr/bin/env bash
# Pins the libsecret stand-in's store ordering: a recorded store call means
# stdin reached EOF and the whole secret is on disk. The control moves the
# call recording before the stdin read in a disposable extracted copy and
# requires the ordering check to fail while stdin is still open.
#
# Exit 0 when the order check and the control hold, 1 otherwise.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
harness="${1:-$repo/scripts/smoke/harness.sh}"
if [[ $# -gt 1 ]]; then
  echo "test-secret-tool-stand-in: args=too-many"
  exit 2
fi

# The EXIT trap is armed only on the directory mktemp made: an empty or
# non-directory answer never reaches rm -rf.
tmp="$(mktemp -d)" || { echo "test-secret-tool-stand-in: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $tmp && ! -L $tmp ]] || { echo "test-secret-tool-stand-in: scratch=not-a-directory value=[$tmp]" >&2; exit 1; }
tmp="$(cd -- "$tmp" && pwd -P)"
trap 'rm -rf -- "${tmp:?}"' EXIT
mkdir -p -- "$tmp/home"
test_env=(env -i PATH="$PATH" HOME="$tmp/home" LC_ALL=C TMPDIR="$tmp")

failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

extract_functions() { # HARNESS OUT
  "${test_env[@]}" python3 - "$1" "$2" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
start = source.find("slack_states() {")
end = source.find("\n# set_slack_photos", start)
if start == -1 or end == -1 or end <= start:
    print("test-secret-tool-stand-in: extract=missing", file=sys.stderr)
    raise SystemExit(1)
section = source[start:end].strip() + "\n"
if section.count("slack_states() {") != 1 or section.count("secret_tool_stand_in() {") != 1:
    print("test-secret-tool-stand-in: extract=wrong-functions", file=sys.stderr)
    raise SystemExit(1)
if not section.strip():
    print("test-secret-tool-stand-in: extract=empty", file=sys.stderr)
    raise SystemExit(1)
Path(sys.argv[2]).write_text(section)
PY
}

mutate_to_main_order() { # IN OUT
  "${test_env[@]}" python3 - "$1" "$2" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
fixed = """  cat >"$shim/secret-tool.stdin.\\$6"
  set_state "\\$6" present
  printf '%s\\\\n' "\\$*" >>"$shim/secret-tool.calls\""""
main_order = """  printf '%s\\\\n' "\\$*" >>"$shim/secret-tool.calls"
  cat >"$shim/secret-tool.stdin.\\$6"
  set_state "\\$6" present"""
if source.count(fixed) != 1:
    print("test-secret-tool-stand-in: control-edit=match-count value=" + str(source.count(fixed)), file=sys.stderr)
    raise SystemExit(1)
mutant = source.replace(fixed, main_order, 1)
if mutant == source:
    print("test-secret-tool-stand-in: control-edit=unchanged", file=sys.stderr)
    raise SystemExit(1)
Path(sys.argv[2]).write_text(mutant)
PY
}

install_stand_in() { # FUNCTIONS SHIM
  local functions="$1" shim_dir="$2"
  mkdir -p -- "$shim_dir"
  (
    set -euo pipefail
    shim="$shim_dir"
    sentinel_stand_over() { cat >"$1" && chmod 755 "$1"; }
    # shellcheck disable=SC1090
    source "$functions"
    secret_tool_stand_in "slack:T0ACME absent"
  )
}

control_problem=""
order_check() { # LABEL FUNCTIONS [no-record]
  local label="$1" functions="$2" case_dir shim fifo expected expected_call fd
  local secret_size=5000000
  local secret_pid secret_status=0 calls states problems=()
  case_dir="$tmp/$label"
  shim="$case_dir/shim"
  mkdir -p -- "$case_dir"
  install_stand_in "$functions" "$shim"
  fifo="$case_dir/stdin.fifo"
  mkfifo -- "$fifo"
  expected="$case_dir/expected.secret"
  "${test_env[@]}" python3 - "$expected" "$secret_size" <<'PY'
from pathlib import Path
import sys

Path(sys.argv[1]).write_bytes(b"S" * int(sys.argv[2]))
PY
  expected_call="store --label=VGS notifications Slack token slack:T0ACME service vgs-notifications account slack:T0ACME"

  timeout 10 "${test_env[@]}" bash -c 'exec "$1" store "--label=VGS notifications Slack token slack:T0ACME" service vgs-notifications account slack:T0ACME <"$2"' \
    _ "$shim/secret-tool" "$fifo" &
  secret_pid=$!
  # The test shell holds the stand-in's stdin. On Linux a read-write open
  # of a FIFO never blocks, and this fd never reads, so every byte goes to
  # the stand-in, which sees EOF only when the fd closes. A write larger
  # than the pipe buffer returns only once the stand-in has read most of
  # it, so the check below runs while the stand-in is reading an open stdin.
  exec {fd}<>"$fifo"
  if ! timeout 10 cat -- "$expected" >&"$fd"; then
    problems+=("writer=timeout-or-failed")
  elif [[ -e $shim/secret-tool.calls ]] && grep -F -x -q -- "$expected_call" "$shim/secret-tool.calls"; then
    problems+=("store-call-before-stdin-eof")
  fi
  exec {fd}>&-
  wait "$secret_pid" || secret_status=$?

  [[ $secret_status -eq 0 ]] || problems+=("secret-tool-exit=$secret_status")

  if [[ ! -r $shim/secret-tool.calls ]]; then
    problems+=("calls=missing")
  else
    calls="$(cat -- "$shim/secret-tool.calls")"
    [[ $calls == "$expected_call" ]] || problems+=("calls=[$calls]")
  fi
  if [[ ! -r $shim/secret-tool.stdin.slack:T0ACME ]]; then
    problems+=("stdin=missing")
  else
    [[ $(stat -c '%s' -- "$shim/secret-tool.stdin.slack:T0ACME") == "$secret_size" ]] || problems+=("stdin-size=$(stat -c '%s' -- "$shim/secret-tool.stdin.slack:T0ACME")")
    cmp -s -- "$expected" "$shim/secret-tool.stdin.slack:T0ACME" || problems+=("stdin=differs")
  fi
  if [[ ! -r $shim/secret-tool.states ]]; then
    problems+=("states=missing")
  else
    states="$(cat -- "$shim/secret-tool.states")"
    [[ $states == "slack:T0ACME present" ]] || problems+=("states=[$states]")
  fi

  if [[ ${#problems[@]} -gt 0 ]]; then
    if [[ ${3:-record} == no-record ]]; then
      control_problem="${problems[*]}"
    else
      fail "$label: ${problems[*]}"
    fi
    return 1
  fi
  ok "$label: store call waits for stdin EOF"
}

extracted="$tmp/extracted-secret-tool.sh"
if extract_functions "$harness" "$extracted" && [[ -s $extracted ]]; then
  ok "extract: slack_states and secret_tool_stand_in found"
else
  fail "extract: slack_states and secret_tool_stand_in not found"
fi

if [[ -s $extracted ]]; then
  order_check fixed "$extracted" || true

  mutant="$tmp/mutant-secret-tool.sh"
  if mutate_to_main_order "$extracted" "$mutant" && [[ -s $mutant ]]; then
    ok "control: store branch edit matched once"
    control_problem=""
    if order_check control "$mutant" no-record; then
      fail "control: main-order mutant stayed green"
    else
      ok "control: main-order mutant goes red: $control_problem"
    fi
  else
    fail "control: store branch edit did not match exactly once"
  fi
fi

if [[ $failures -gt 0 ]]; then
  echo "test-secret-tool-stand-in: failures=$failures"
  exit 1
fi
echo "test-secret-tool-stand-in: ok"
