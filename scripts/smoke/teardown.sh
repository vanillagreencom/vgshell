# Sourced by harness.sh before it makes the sandbox, and by
# scripts/test-smoke-teardown.sh. Defines cleanup, the smoke's teardown, and
# arms it on EXIT. It reads the caller's pgids (the process groups spawn
# recorded), keep (true under --keep), sandbox and rt_dir (empty until made)
# and the optional source_tree (a caller's export of another tree). Once
# harness.sh has started the sink and defined sink_alive, a sink that has
# exited is printed as `qml-smoke: sink=exited ...` before the groups are
# signalled, whichever runner sourced the harness. It needs no Wayland
# session; git checks the source export before deletion.
#
# Bash runs the EXIT trap on TERM, INT and HUP as well. A second of those
# signals that arrives during the trap ends the shell there and leaves the
# sandbox behind, as when a timeout signals the runner and then the stopping
# systemd unit signals every process in it. The trap ignores the three
# signals first, and the commands it starts inherit that. SIGKILL cannot be
# ignored: scripts/smoke/gpu-fence.sh then ends the sandbox's processes and
# removes the directories the harness named in its ledger.
set -euo pipefail

# teardown_step KEY PATH CMD...: run CMD. On failure print
# `qml-smoke: cleanup=KEY path=PATH` on stderr, then CMD's own stderr.
teardown_step() {
  local key="$1" path="$2" err
  shift 2
  err="$("$@" 2>&1 >/dev/null)" && return 0
  printf 'qml-smoke: cleanup=%s path=%s\n' "$key" "$path" >&2
  [[ -z $err ]] || printf '%s\n' "$err" >&2
  return 0
}

# The shots runner records its exclusively created export in the fence's
# ledger before handing it to the harness. A source_tree argument alone
# grants no ownership, even when it names a directory inside the checkout.
teardown_source_tree_check() {
  [[ -n ${source_tree:-} ]] || return 0
  local cause="" recorded owned=false canonical top probe_status
  if [[ $source_tree != /* || $source_tree == *$'\n'* ]]; then
    cause=invalid-path
  elif [[ -z ${VGSHELL_FENCE_LEDGER:-} || ! -f $VGSHELL_FENCE_LEDGER || ! -r $VGSHELL_FENCE_LEDGER ]]; then
    cause=ledger-unreadable
  else
    while IFS= read -r recorded; do
      [[ $recorded != "$source_tree" ]] || owned=true
    done <"$VGSHELL_FENCE_LEDGER"
    if [[ $owned != true ]]; then
      cause=unrecorded-export
    elif [[ -L $source_tree ]]; then
      cause=symlink
    elif [[ -e $source_tree/.git || -L $source_tree/.git ]]; then
      cause=git-checkout
    elif [[ -e $source_tree ]]; then
      if ! canonical="$(realpath -e -- "$source_tree")"; then
        cause=path-unreadable
      elif ! command -v git >/dev/null 2>&1; then
        cause=git-unavailable
      else
        probe_status=0
        # Cross mount boundaries so an outside export has one explicit
        # no-repository result; every other failed lookup refuses deletion.
        top="$(LC_ALL=C GIT_DISCOVERY_ACROSS_FILESYSTEM=1 git -C "$source_tree" rev-parse --show-toplevel 2>&1)" || probe_status=$?
        if [[ $probe_status == 0 ]]; then
          [[ $canonical != "$top" ]] || cause=git-checkout
        elif [[ $probe_status != 128 || $top != 'fatal: not a git repository (or any of the parent directories): .git' ]]; then
          cause=git-probe-failed
        fi
      fi
    fi
  fi
  [[ -n $cause ]] || return 0
  printf 'teardown: source-tree-refused path=%s cause=%s\n' "$source_tree" "$cause" >&2
  return 1
}

cleanup() {
  local original_status=$?
  trap '' TERM INT HUP
  local source_tree_status=0
  teardown_source_tree_check || source_tree_status=$?
  local pg path
  if [[ -n ${display_record_pid:-} ]]; then
    if ! display_record_close "$original_status" cleanup; then
      printf 'qml-smoke: cleanup=recorder-close-failed path=%s\n' "${display_record_dir:-unavailable}" >&2
    fi
  fi
  if declare -F sink_alive >/dev/null && ! sink_alive; then
    printf 'qml-smoke: %s\n' "$sink_exit"
  fi
  for pg in "${pgids[@]}"; do
    [[ $pg == "${display_record_pid:-}" ]] || kill -TERM -- "-$pg" 2>/dev/null || true
  done
  sleep 0.5
  for pg in "${pgids[@]}"; do
    [[ $pg == "${display_record_pid:-}" ]] || kill -KILL -- "-$pg" 2>/dev/null || true
  done
  if [[ -n ${display_record_pid:-} ]]; then
    if ! display_record_finish "$original_status"; then
      printf 'qml-smoke: cleanup=recorder-finalization-failed path=%s\n' "${display_record_dir:-unavailable}" >&2
    fi
  fi
  if [[ -n $sandbox && -f $sandbox/evidence/destination ]]; then
    python3 "${source_repo:?}/scripts/smoke/evidence.py" "$sandbox" || true
  fi
  # The read-only prefix row takes the write bits off part of the sandbox
  # and gives them back only at its end, and rm -rf cannot empty a directory
  # without them. A kept sandbox gets them back too, so plain rm -rf
  # removes it.
  [[ -z $sandbox ]] || teardown_step chmod-failed "$sandbox" chmod -R u+rwX -- "$sandbox"
  if [[ $keep == true ]]; then
    echo "qml-smoke: sandbox kept at $sandbox (runtime dir $rt_dir)"
  else
    for path in "$sandbox" "$rt_dir"; do
      [[ -z $path ]] || teardown_step rm-failed "$path" rm -rf -- "$path"
    done
  fi
  # A caller's export of another tree is read only by the sandbox's copy.
  [[ $source_tree_status == 0 ]] || return "$source_tree_status"
  [[ -z ${source_tree:-} ]] || teardown_step rm-failed "$source_tree" rm -rf -- "$source_tree"
}
trap cleanup EXIT
