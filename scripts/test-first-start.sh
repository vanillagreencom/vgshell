#!/usr/bin/env bash
# Controls for bin/lib/first-start.sh. The suite builds a package-shaped
# tree with stand-ins for runuser, timeout and getent, and a fake runtime
# root under this repository's tmp/. It never calls the host's runuser and
# never reads /run/user.
set -euo pipefail

repo="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)"
tmp="$repo/tmp/fs.$$"
rm -rf -- "$tmp"
mkdir -p -- "$tmp"
failures=0
socket_pids=()
cleanup() {
  local socket_pid
  for socket_pid in "${socket_pids[@]}"; do kill "$socket_pid" 2>/dev/null || true; done
  rm -rf -- "${tmp:?}"
}
trap cleanup EXIT

ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

pkg="$tmp/pkg"
mkdir -p -- "$pkg/bin/lib" "$tmp/path" "$tmp/home"
cp -- "$repo/bin/lib/first-start.sh" "$pkg/bin/lib/first-start.sh"
chmod 755 "$pkg/bin/lib/first-start.sh"
cat >"$pkg/bin/vgshell" <<'EOF'
#!/usr/bin/env bash
printf 'vgshell user=%s home=%s runtime=%s signature=%s args=%s\n' "${RUNUSER_USER:-}" "${HOME:-}" "${XDG_RUNTIME_DIR:-}" "${HYPRLAND_INSTANCE_SIGNATURE:-}" "$*" >>"${FIRST_START_LOG:?}"
if [[ -n ${FIRST_START_FAIL:-} ]]; then exit "$FIRST_START_FAIL"; fi
EOF
chmod 755 "$pkg/bin/vgshell"
test_uid="$(id -u)"
cat >"$tmp/path/getent" <<EOF
#!/usr/bin/env bash
[[ \${1:-} == passwd && \${2:-} == $test_uid ]] || exit 2
printf 'alice:x:$test_uid:$test_uid:Alice:/home/alice:/bin/bash\n'
EOF
cat >"$tmp/path/timeout" <<'EOF'
#!/usr/bin/env bash
printf 'timeout %s\n' "$*" >>"${FIRST_START_LOG:?}"
shift
exec "$@"
EOF
cat >"$tmp/path/runuser" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == -u && ${3:-} == -- ]] || exit 2
user="$2"
shift 3
printf 'runuser user=%s argv=%s\n' "$user" "$*" >>"${FIRST_START_LOG:?}"
if [[ ${1:-} == env && ${2:-} == -i ]]; then
  shift 2
  exec env -i FIRST_START_LOG="$FIRST_START_LOG" FIRST_START_FAIL="${FIRST_START_FAIL:-}" RUNUSER_USER="$user" "$@"
fi
RUNUSER_USER="$user" exec "$@"
EOF
chmod 755 "$tmp/path/getent" "$tmp/path/timeout" "$tmp/path/runuser"

start_socket() { # PATH
  python3 - "$1" <<'PY' &
import socket
import sys
import time
sock = socket.socket(socket.AF_UNIX)
sock.bind(sys.argv[1])
sock.listen(1)
time.sleep(60)
PY
  socket_pids+=("$!")
  for _ in $(seq 1 50); do
    [[ -S $1 ]] && return 0
    sleep 0.05
  done
  return 1
}

run_case() { # NAME RUNTIME [ENV...]
  case_name="$1"
  runtime="$2"
  shift 2
  log="$tmp/$case_name.log"
  err="$tmp/$case_name.err"
  set +e
  env -i PATH="$tmp/path:/usr/bin:/bin" FIRST_START_LOG="$log" "$@" "$pkg/bin/lib/first-start.sh" "$runtime" >"$tmp/$case_name.out" 2>"$err"
  status=$?
  set -e
}

rt="$tmp/rt"
mkdir -p -- "$rt/$test_uid/hypr/sig-a"
start_socket "$rt/$test_uid/hypr/sig-a/.socket.sock" || { echo "test-first-start: socket=failed" >&2; exit 77; }
run_case own "$rt"
if [[ $status == 0 ]] && grep -qxF -- "vgshell user=alice home=/home/alice runtime=$rt/$test_uid signature=sig-a args=start" "$log"; then
  ok "own socket starts vgshell for that Hyprland session"
else
  fail "own socket: exit=$status log=$(cat "$log" 2>/dev/null || :) err=$(cat "$err")"
fi
if grep -qxF -- "timeout 10s runuser -u alice -- env -i HOME=/home/alice PATH=/usr/local/bin:/usr/bin:/bin XDG_RUNTIME_DIR=$rt/$test_uid HYPRLAND_INSTANCE_SIGNATURE=sig-a $pkg/bin/vgshell start" "$log"; then
  ok "the hand-off uses timeout, runuser and a clean environment"
else
  fail "handoff argv: $(cat "$log" 2>/dev/null || :)"
fi

missing="$tmp/no-runtime"
run_case missing "$missing"
if [[ $status == 0 && ! -s $tmp/missing.out && ! -s $err && ! -e $log ]]; then
  ok "a missing runtime root quietly exits zero"
else
  fail "missing runtime root: exit=$status out=$(cat "$tmp/missing.out") err=$(cat "$err") log=$(cat "$log" 2>/dev/null || :)"
fi

plain="$tmp/plain"
mkdir -p -- "$plain/$test_uid/hypr/sig-b"
: >"$plain/$test_uid/hypr/sig-b/.socket.sock"
run_case plain "$plain"
if [[ $status == 0 && ! -e $log && ! -s $err ]]; then
  ok "control: a plain file named like the socket gets no hand-off"
else
  fail "plain file control: exit=$status log=$(cat "$log" 2>/dev/null || :) err=$(cat "$err")"
fi

two="$tmp/two"
mkdir -p -- "$two/$test_uid/hypr/sig-old" "$two/$test_uid/hypr/sig-new"
start_socket "$two/$test_uid/hypr/sig-old/.socket.sock" || { echo "test-first-start: socket=failed" >&2; exit 77; }
start_socket "$two/$test_uid/hypr/sig-new/.socket.sock" || { echo "test-first-start: socket=failed" >&2; exit 77; }
touch -d '2 minutes ago' -- "$two/$test_uid/hypr/sig-old/.socket.sock"
run_case two "$two"
if [[ $status == 0 && $(grep -c '^vgshell ' "$log") == 1 ]] && grep -qxF -- "vgshell user=alice home=/home/alice runtime=$two/$test_uid signature=sig-new args=start" "$log"; then
  ok "two sockets of one user get one hand-off, to the newest"
else
  fail "two sockets: exit=$status log=$(cat "$log" 2>/dev/null || :) err=$(cat "$err")"
fi

failrt="$tmp/failrt"
mkdir -p -- "$failrt/$test_uid/hypr/sig-c"
start_socket "$failrt/$test_uid/hypr/sig-c/.socket.sock" || { echo "test-first-start: socket=failed" >&2; exit 77; }
run_case failing "$failrt" FIRST_START_FAIL=5
if [[ $status == 0 ]] && grep -qxF -- "first-start: start=failed uid=$test_uid signature=sig-c" "$err"; then
  ok "a failing start reports one line and the install still succeeds"
else
  fail "failing start: exit=$status err=$(cat "$err")"
fi

if ((failures > 0)); then
  echo "test-first-start: failed=$failures"
  exit 1
fi
echo "test-first-start: ok"
