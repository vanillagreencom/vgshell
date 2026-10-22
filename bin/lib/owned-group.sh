#!/usr/bin/env bash
# Private owner of an explicitly isolated query group. Call through
# env --default-signal=TERM,INT,HUP setpriv --pdeathsig TERM -- owned-group.sh
# PARENT GRACE COMMAND... in a new session. The live session/group leader
# retains its identity while it signals the group, so no reused PGID is used.
# This transparent launcher passes the query's environment and argv unchanged.
owned_group_stop() { # PID: an asynchronous job this Bash caller started
  local pid="$1" spec job_pid rest
  # Bash's jobspec kill blocks SIGCHLD and skips already reaped members;
  # a numeric kill can instead signal a reused pid (Bash jobs.c::kill_pid).
  while read -r spec job_pid rest; do
    [[ $job_pid == "$pid" && $spec == \[* ]] || continue
    spec="${spec#\[}"
    builtin kill -TERM -- "%${spec%%]*}" 2>/dev/null || true
    return
  done < <(jobs -l)
}
[[ ${BASH_SOURCE[0]} == "$0" ]] || return 0
set -euo pipefail
parent="${1:?owned-group: parent}"
grace="${2:?owned-group: grace}"
shift 2
child=""
stop_group() {
  trap '' TERM INT HUP
  # A trapped wait returns on TERM. A second wait in this handler gives a
  # responsive command its cleanup; the timer ends a stubborn command.
  ( sleep "$grace"; kill -KILL -- "-$$" ) &
  kill -TERM -- "-$$"
  [[ -z $child ]] || wait "$child" 2>/dev/null || true
  kill -KILL -- "-$$"
}
identity="$(<"/proc/$$/stat")"
identity="${identity##*) }"
read -r state observed_parent group session rest <<<"$identity"
if [[ $group != "$$" || $session != "$$" ]]; then
  printf 'owned-group: refused: session=unowned\n' >&2
  exit 1
fi
trap stop_group TERM INT HUP
if [[ $PPID != "$parent" ]]; then
  printf 'owned-group: refused: parent=changed\n' >&2
  exit 1
fi
"$@" &
child=$!
status=0
wait "$child" || status=$?
# Package checks, git transports and capture tools may fork before returning.
# A cleanup child keeps this group allocated after its leader returns the
# query's status. It holds no query streams and ends itself with the group.
trap '' TERM INT HUP
(
  kill -TERM -- "-$$"
  sleep "$grace"
  kill -KILL -- "-$$"
) </dev/null >/dev/null 2>&1 &
exit "$status"
