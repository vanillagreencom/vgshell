#!/usr/bin/env bash
# Test-only owner of a Jarvis world. Source and call jarvis_env_run, or run:
#   scripts/lib/jarvis-env.sh STANDINS -- COMMAND [ARG...]
# STANDINS holds executable regular files, not links or host-tool overrides.
# COMMAND and every descendant share one private user/network/PID namespace.
# The PID namespace ends surviving children when COMMAND ends.
# TERM, INT or HUP stops the world; the owner then exits 143, 130 or 129, and
# only after every process of its world has ended.
# Exit 77 means a host dependency or namespaces are unavailable, not a pass.
# Other command statuses pass through unchanged; invalid arguments exit 2.
# JARVIS_TEST_ROOT and JARVIS_TEST_TMUX_SOCKET name this invocation's scratch
# world. No caller environment entries pass through. Fixture parameters are
# command arguments or scratch files, never inherited environment variables.
# JARVIS_TEST_SCRATCH_ROOT selects the parent directory for fresh worlds.
# Default: the caller's TMPDIR, else /tmp. The launcher resolves it physically;
# this parent setting and the caller's TMPDIR never enter the child.
# The world's runtime directory, which holds its private Unix sockets, is a
# fresh directory under the caller's XDG_RUNTIME_DIR, else /tmp, so no
# checkout path lengthens a socket path. Only that directory enters the child.
# A session bus path longer than dbus-daemon accepts refuses with
# scratch=socket-path-too-long and exit 1 before services start.

_jarvis_env_error() {
  printf 'jarvis-env: %s\n' "$*" >&2
}

# The allow-list is deliberately disjoint from desktop, audio, account,
# browser and installer commands. PATH resolves those only as stand-ins.
_jarvis_env_tools=(bash sh env node python3 cat mkdir rm cp mv ln chmod sleep flock
  readlink dirname basename stat grep sed awk sort cut wc true false setpriv timeout gdbus)

# _jarvis_env_mkdtemp PARENT: print a fresh private directory under PARENT,
# resolved physically. $allocator is the caller's fixed-path python3.
_jarvis_env_mkdtemp() {
  local made
  made="$(/usr/bin/env -i LC_ALL=C "$allocator" -I - "$1" <<'PY'
import sys, tempfile
try:
    print(tempfile.mkdtemp(prefix="jv-", dir=sys.argv[1]))
except OSError as error:
    print(f"jarvis-env: scratch=create-failed parent={sys.argv[1]} error={error}", file=sys.stderr)
    sys.exit(1)
PY
)" || return 1
  [[ -d $made && ! -L $made ]] || { _jarvis_env_error "scratch=not-a-directory value=[$made]"; return 1; }
  (cd -- "$made" && pwd -P) || { _jarvis_env_error 'scratch=resolve-failed'; return 1; }
}

# jarvis_env_run STANDINS -- COMMAND [ARG...]: preserve the sourced caller's
# traps, options, directories and environment in a subshell.
jarvis_env_run() ( _jarvis_env_run "$@"; )

# The CLI calls the owner directly, so its returned PID owns cancellation.
_jarvis_env_run() {
  set -euo pipefail
  export LC_ALL=C
  if [[ $# -lt 3 || $2 != -- || -z $3 ]]; then
    _jarvis_env_error 'refused=arguments'; return 2
  fi
  local standins self scratch allocator root run="" tool real entry name owner stop="" status=0
  standins="$(cd -- "$1" && pwd -P)" || { _jarvis_env_error "standins=unreadable path=$1"; return 1; }
  shift 2
  self="$(readlink -f -- "${BASH_SOURCE[0]}")" || return 1
  scratch="${JARVIS_TEST_SCRATCH_ROOT-${TMPDIR:-/tmp}}"
  [[ -n $scratch ]] || { _jarvis_env_error 'scratch-parent=empty'; return 1; }
  umask 077
  if ! mkdir -p -- "$scratch" 2>/dev/null; then
    _jarvis_env_error "scratch-parent=create-failed path=$scratch"; return 1
  fi
  scratch="$(cd -- "$scratch" && pwd -P)" ||
    { _jarvis_env_error "scratch-parent=resolve-failed path=$scratch"; return 1; }
  allocator="$(PATH=/usr/bin:/usr/sbin:/bin:/sbin type -P -- python3)" ||
    { _jarvis_env_error 'status=not-measured missing=python3'; return 77; }
  unset TMPDIR
  root="$(_jarvis_env_mkdtemp "$scratch")" || return 1
  _jarvis_env_cleanup() {
    local result=$?
    if [[ -n $stop ]]; then
      # The request ends the world (_jarvis_env_inside). unshare --fork, which
      # ignores TERM and INT, exits only after it reaps init, and the kernel
      # reaps a PID namespace's init only once every other process of that
      # namespace is released (kernel/pid_namespace.c zap_pid_ns_processes).
      # So this wait returns after the whole world has ended. Waiting for
      # every child also covers a world started before $owner was assigned.
      printf '\n' >&"$stop" || result=1
      wait 2>/dev/null || :
    fi
    rm -rf -- "${root:?}" || { _jarvis_env_error "cleanup=failed path=$root"; exit 1; }
    if [[ -n $run ]]; then rm -rf -- "${run:?}" || { _jarvis_env_error "cleanup=failed path=$run"; exit 1; }; fi
    exit "$result"
  }
  trap _jarvis_env_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  run="$(_jarvis_env_mkdtemp "${XDG_RUNTIME_DIR:-/tmp}")" || exit 1
  # dbus-daemon refuses a listen path over 99 bytes, below the 107 of Linux
  # sun_path: _DBUS_MAX_SUN_PATH_LENGTH in dbus/dbus-sysdeps.h (1.16.2).
  # https://gitlab.freedesktop.org/dbus/dbus/-/blob/dbus-1.16.2/dbus/dbus-sysdeps.h
  # Session bus is this world's longest socket.
  "$allocator" -I - "$run/session.bus" <<'PY' || exit 1
import os, sys
size = len(os.fsencode(sys.argv[1]))
if size > 99:
    print(f"jarvis-env: scratch=socket-path-too-long bytes={size} max=99 path={sys.argv[1]}", file=sys.stderr)
    sys.exit(1)
PY
  umask 077
  mkdir -p "$root"/{standins,tools,bootstrap,home,config,data,state,cache,tmp} || exit 1
  for tool in "${_jarvis_env_tools[@]}" unshare ip dbus-daemon tmux; do
    # A fixed search path avoids a login-shell function or version-manager
    # shim that opens the developer's configuration before the test starts.
    real="$(PATH=/usr/bin:/usr/sbin:/bin:/sbin type -P -- "$tool")" ||
      { _jarvis_env_error "status=not-measured missing=$tool"; exit 77; }
    case "$tool" in
      unshare)
        ln -s -- "$real" "$root/bootstrap/$tool" || exit 1
        ln -s -- "$real" "$root/tools/$tool" || exit 1 ;;
      ip|dbus-daemon|tmux) ln -s -- "$real" "$root/bootstrap/$tool" || exit 1 ;;
      *) ln -s -- "$real" "$root/tools/$tool" || exit 1 ;;
    esac
  done
  shopt -s nullglob dotglob
  for entry in "$standins"/*; do
    name="${entry##*/}"
    if [[ ! -f $entry || ! -x $entry || -L $entry ]]; then
      _jarvis_env_error "standin=not-executable-file name=$name"; exit 1
    fi
    if [[ -e $root/tools/$name || -e $root/bootstrap/$name ]]; then
      _jarvis_env_error "standin=host-tool-collision name=$name"; exit 1
    fi
    cp -- "$entry" "$root/standins/$name" || exit 1
  done
  # Force the socket and an empty config even when the caller uses tmux
  # directly. getopts follows tmux 3.7c tmux.c::main's global syntax, including
  # clusters and c/T values. Unknown global syntax fails closed.
  printf '%s\n' '#!/bin/bash' 'set -euo pipefail' \
    'while getopts ":2c:CDdf:hlL:NqS:T:uUvV" option; do' \
    '  case "$option" in' \
    '    S|L|f|\?|:) echo "jarvis-env: tmux=override-refused" >&2; exit 2 ;;' \
    '    *) ;;' \
    '  esac' \
    'done' \
    'exec "$JARVIS_TEST_ROOT/bootstrap/tmux" -f /dev/null -S "$JARVIS_TEST_TMUX_SOCKET" "$@"' \
    >"$root/tools/tmux" || exit 1
  chmod 700 "$root/tools/tmux" || exit 1
  local clean_env=(/usr/bin/env -i
    PATH="$root/standins:$root/tools" HOME="$root/home"
    XDG_CONFIG_HOME="$root/config" XDG_DATA_HOME="$root/data"
    XDG_STATE_HOME="$root/state" XDG_CACHE_HOME="$root/cache"
    XDG_RUNTIME_DIR="$run" TMPDIR="$root/tmp"
    TMUX_TMPDIR="$run" JARVIS_TEST_TMUX_SOCKET="$run/tmux.sock"
    PIPEWIRE_RUNTIME_DIR="$run" PIPEWIRE_REMOTE=jarvis-test-no-pipewire
    PULSE_RUNTIME_PATH="$run" PULSE_SERVER="unix:$run/no-pulse"
    LC_ALL=C LANG=C TZ=UTC VGS_TEST_RUN=1
    JARVIS_TEST_ROOT="$root")
  if ! "${clean_env[@]}" "$root/bootstrap/unshare" -rn --pid --fork --mount-proc --kill-child -- \
    "$root/tools/true" 2>"$root/namespace.log"; then
    _jarvis_env_error 'status=not-measured reason=namespaces-unavailable'
    cat -- "$root/namespace.log" >&2 || exit 1
    exit 77
  fi
  # The stop channel: a pipe that the owner and the world hold read-write, so
  # it never reaches end of file and only a request line wakes the world. Its
  # name is gone before the world starts.
  "$allocator" -I -c 'import os, sys; os.mkfifo(sys.argv[1], 0o600)' "$root/stop" || exit 1
  exec {stop}<>"$root/stop" || exit 1
  rm -- "$root/stop" || exit 1
  "${clean_env[@]}" "$root/bootstrap/unshare" -rn --pid --fork --mount-proc --kill-child -- \
    "$root/tools/bash" --noprofile --norc "$self" --inside "$root" "$stop" "$@" &
  owner=$!
  wait "$owner" || status=$?
  # Namespace creation can fail between the probe and the real start.
  if [[ ! -f $root/started ]]; then
    _jarvis_env_error 'status=not-measured reason=namespace-start-failed'
    exit 77
  fi
  # Exit while the owner's local resource bindings still exist for its trap.
  exit "$status"
}

# Refuses unless it is its PID namespace's init, so the stop watcher's KILL -1
# never reaches a process outside the world. The refusal follows the started
# marker so the owner reports it as exit 1, a defect, not as an unavailable
# namespace. Bootstrap tools never enter PATH.
_jarvis_env_inside() {
  set -euo pipefail
  local root="$1" stop="$2" bus address err
  shift 2
  : >"$root/started"
  [[ $$ -eq 1 ]] || { _jarvis_env_error "refused=not-namespace-init pid=$$"; return 1; }
  "$root/bootstrap/ip" link set lo up
  for bus in system session; do
    # No includes, servicedir or standard_session_servicedirs: a request on
    # either bus cannot activate a service from the host or a fixture.
    # D-Bus addresses escape every byte outside [-0-9A-Za-z_/.\*] as %xx and
    # accept either hex case; the daemon prints lower case.
    # https://dbus.freedesktop.org/doc/dbus-specification.html#addresses
    "$root/tools/python3" -I - "$root/$bus.conf" "$XDG_RUNTIME_DIR/$bus.bus" <<'PY' || return 1
import os, string, sys
from pathlib import Path
plain = (string.ascii_letters + string.digits + "-_/.\\*").encode()
path = "".join(chr(byte) if byte in plain else "%%%02x" % byte for byte in os.fsencode(sys.argv[2]))
Path(sys.argv[1]).write_text(
    '<busconfig><type>session</type><listen>unix:path=' + path +
    '</listen><auth>EXTERNAL</auth><policy context="default">'
    '<allow user="*"/><allow own="*"/><allow send_destination="*"/>'
    '<allow receive_sender="*"/></policy></busconfig>')
PY
    address="$("$root/bootstrap/dbus-daemon" --fork --print-address --config-file="$root/$bus.conf")" || return 1
    # Compare the socket the printed address names, not its escape spelling.
    "$root/tools/python3" -I - "$address" "$XDG_RUNTIME_DIR/$bus.bus" <<'PY' ||
import os, sys
from urllib.parse import unquote_to_bytes
transport, _, keys = sys.argv[1].partition(":")
pairs = (pair.partition("=") for pair in keys.split(","))
paths = [unquote_to_bytes(value) for key, sep, value in pairs if key == "path" and sep]
sys.exit(transport != "unix" or paths != [os.fsencode(sys.argv[2])])
PY
      { _jarvis_env_error "bus=unexpected-address kind=$bus"; return 1; }
    case "$bus" in
      session) export DBUS_SESSION_BUS_ADDRESS="$address" ;;
      system) export DBUS_SYSTEM_BUS_ADDRESS="$address" ;;
    esac
  done
  cd -- "$HOME"
  # Setup has finished, so from here on init's own stderr is /dev/null: a
  # killed command leaves no bash job report in the caller's stderr.
  exec {err}>&2 2>/dev/null
  # The owner's stop request is one line on descriptor $stop, pending until
  # this watcher reads it. The watcher ignores the signals a caller sends the
  # whole process group, puts the line back for the command's own check, then
  # KILLs -1: every process of this namespace but init and itself (kill(2)).
  {
    trap '' INT TERM HUP
    if read -r -u "$stop"; then
      printf '\n' >&"$stop" || :
      kill -KILL -1 2>/dev/null || :
    fi
  } &
  # Keep init alive until the command exits. The kernel then ends its buses,
  # private tmux server and all surviving grandchildren, even after a failure.
  # The forked child starts nothing once a request is pending, and a request
  # after its check finds it alive for the watcher's KILL.
  (read -t 0 -u "$stop" && exit 1; exec "$@" 2>&"$err" {err}>&- {stop}>&-)
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  if [[ ${1:-} == --inside ]]; then
    shift
    _jarvis_env_inside "$@"
  else
    _jarvis_env_run "$@"
  fi
fi
