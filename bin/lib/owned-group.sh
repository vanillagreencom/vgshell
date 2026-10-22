#!/usr/bin/env bash
# Private owner of an explicitly isolated query group. Call through
# env --default-signal=TERM,INT,HUP setpriv --pdeathsig TERM -- owned-group.sh
# PARENT GRACE COMMAND... in a new session. The live session/group leader
# retains its identity while it signals the group, so no reused PGID is used.
# This transparent launcher passes the query's environment and argv unchanged.
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
exit "$status"
