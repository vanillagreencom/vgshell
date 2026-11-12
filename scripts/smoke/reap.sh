# Sourced by scripts/smoke/gpu-fence.sh and scripts/validate: the one
# reaper of the temporary roots a run leaves when it ends with no trap run,
# as a SIGKILL ends it, and the readers it rests on. Each caller names its
# roots for their owner and reaps before it makes its own.
# Both callers already run under these options.
set -euo pipefail

# why TEXT: a failed command's captured stderr on one line, at most 400
# characters, so a cleanup note stays one line of the run log.
why() {
  local text="${1:0:400}"
  printf '%s' "${text//$'\n'/; }"
}

# proc_start PID: PID's start time in clock ticks, field 22 of its stat. Its
# name field may hold spaces and parentheses, so the fields count from the
# last ") ".
proc_start() {
  local line rest fields=()
  read -r line 2>/dev/null <"/proc/$1/stat" || return 1
  rest="${line##*) }"
  read -r -a fields <<<"$rest"
  [[ ${fields[19]-} =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "${fields[19]}"
}

# pid_namespace PID: the inode number of PID's PID namespace.
pid_namespace() {
  local link
  link="$(readlink -- "/proc/$1/ns/pid")" && [[ $link =~ ^pid:\[([0-9]+)\]$ ]] || return 1
  printf '%s\n' "${BASH_REMATCH[1]}"
}

# proc_refs: every path a process holds as its cwd, an open descriptor or a
# mount point, one per line. A world's processes reach its root by a bind
# mount, and a descriptor opened through the runtime bind reads back under
# another path, so a mount point is the reference that lasts the world.
proc_refs() {
  local p ns seen=$'\n' dest
  for p in /proc/[0-9]*; do
    readlink -- "$p/cwd" "$p"/fd/* 2>/dev/null || true
    ns="$(readlink -- "$p/ns/mnt" 2>/dev/null)" || continue
    [[ $seen != *$'\n'"$ns"$'\n'* ]] || continue
    seen+="$ns"$'\n'
    while read -r _ _ _ _ dest _; do printf '%b\n' "$dest"; done 2>/dev/null <"$p/mountinfo" || true
  done
}

# reap_orphans LABEL PREFIX NAMESPACE OLD_FORM: before a run makes its root,
# remove each PREFIX* root under the caller TMPDIR whose owner has ended,
# so a run that was killed (SIGKILL runs no trap) leaves nothing behind for
# the next one. The owner is in the root's name, written by the one mktemp
# that makes it: PREFIX<pid>-<start>-<pid namespace>-<r|k>.XXXXXX. A root
# is reaped only when its owner is proved gone: its pid is absent or reads
# a different start time, in NAMESPACE, the caller's own. An owner that is
# alive, in another namespace, unreadable, or kept on purpose (k) keeps its
# root. Each root it removes, cannot remove or keeps for a reason but a
# live owner (a concurrent run's own root, which no line names) gets one
# line, led by `LABEL: `, on the caller's stderr, which is its run log:
#   cleanup=reaped path=<root>
#   cleanup=kept path=<root> reason=<why>
#   cleanup=rm-failed path=<root> rm-error=<rm's stderr>[ chmod-error=<chmod's stderr>]
# A kept root's reason is keep, other-namespace, owner-unreadable (a live
# pid whose start time cannot be read), no-owner-in-name, owner-unproved,
# referenced, not-owned or not-a-directory.
# A name whose rest after PREFIX matches the regular expression OLD_FORM
# predates the owner in the name. When OLD_FORM's first group captures the
# pid of the run that made it, as validate's does, a regular file of that
# form is an old root too, since that code made its scratch files there,
# and the entry is kept as owner-unproved while that pid exists in this PID
# namespace. Otherwise, as for the fence, whose old code made only
# directories, every non-directory is kept as not-a-directory. An old-form
# entry is removed only when it is older than ownerless_min_age and no
# process holds it as a cwd, descriptor or mount point, else it is kept as
# owner-unproved or referenced. The reaper touches nothing outside TMPDIR,
# and in it only a directory named PREFIX* or such an old-form file.
reap_orphans() {
  local label="$1" prefix="$2" own_ns="$3" old_form="$4"
  local root name pid start ns kind reason current modified chmod_error rm_error refs="" refs_read=false old old_pid
  # Seconds an old-form entry must have stood. The fence's old root holds no
  # reference only in the moments before bubblewrap mounts it, and a live
  # validate run's old entries are kept by the pid in their name; the age is
  # a margin over both, not a bound on how long a run lasts.
  local ownerless_min_age=10800
  for root in "${TMPDIR:-/tmp}/$prefix"*; do
    [[ -e $root || -L $root ]] || continue
    name="${root##*/}"
    name="${name#"$prefix"}"
    reason=""
    old=false old_pid=""
    if [[ $name =~ $old_form ]]; then old=true old_pid="${BASH_REMATCH[1]-}"; fi
    if [[ -L $root ]] || ! [[ -d $root || ( -f $root && -n $old_pid ) ]]; then
      reason=not-a-directory
    elif [[ $name =~ ^([0-9]+)-([0-9]+)-([0-9]+)-([rk])\.[A-Za-z0-9]{6}$ ]]; then
      pid="${BASH_REMATCH[1]}" start="${BASH_REMATCH[2]}" ns="${BASH_REMATCH[3]}" kind="${BASH_REMATCH[4]}"
      if [[ $kind == k ]]; then
        reason=keep
      elif [[ $ns != "$own_ns" ]]; then
        reason=other-namespace
      elif [[ ! -e /proc/$pid ]]; then
        :
      elif ! current="$(proc_start "$pid")"; then
        reason=owner-unreadable
      elif [[ $current == "$start" ]]; then
        continue
      fi
    elif [[ $old == true ]]; then
      # REVISIT(D107): the one-time migration of roots made before the owner
      # was named. Delete this branch, and OLD_FORM, with the first release
      # every host has run; a root that new code makes never reaches it.
      # Validate's old code held neither its run directory nor its changed-
      # paths file as a cwd or descriptor, so only the pid in the name keeps
      # a live old run's entries.
      if ! modified="$(stat -c %Y -- "$root")" || (($(printf '%(%s)T' -1) - modified < ownerless_min_age)); then
        reason=owner-unproved
      elif [[ -n $old_pid && -e /proc/$old_pid ]]; then
        reason=owner-unproved
      else
        if [[ $refs_read == false ]]; then
          if refs="$(proc_refs)"; then refs=$'\n'"$refs"$'\n'; else refs=unreadable; fi
          refs_read=true
        fi
        # References that could not be read may hold any root.
        [[ $refs != unreadable ]] || reason=referenced
        if [[ $refs == *$'\n'"$root"$'\n'* || $refs == *$'\n'"$root/"* ]]; then reason=referenced; fi
      fi
    else
      reason=no-owner-in-name
    fi
    if [[ -z $reason && ! -O $root ]]; then reason=not-owned; fi
    if [[ -n $reason ]]; then
      printf '%s: cleanup=kept path=%s reason=%s\n' "$label" "$root" "$reason" >&2
      continue
    fi
    # Owner bits first, as a world's release does: the fixtures are
    # read-only. A chmod failure is reported only as the cause of a failed rm.
    chmod_error="$(chmod -R u+rwX -- "$root" 2>&1)" || true
    if rm_error="$(rm -rf -- "$root" 2>&1)" || [[ ! -e $root ]]; then
      printf '%s: cleanup=reaped path=%s\n' "$label" "$root" >&2
    else
      printf '%s: cleanup=rm-failed path=%s rm-error=%s\n' "$label" "$root" "$(why "$rm_error")${chmod_error:+ chmod-error=$(why "$chmod_error")}" >&2
    fi
  done
}
