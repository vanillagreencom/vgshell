#!/usr/bin/env bash
# Run a command where no amdgpu DRM node exists, so nothing it starts can
# open one. The amdgpu driver's per-open path can stop the kernel
# (docs/decisions/D099-no-amdgpu-node-in-validation-runs.md). The nested
# compositor and the shell list /dev/dri and open nodes from that listing,
# whatever device an environment variable names, and which library opened
# the amdgpu node is not proven. So the node is hidden, not deselected.
# REVISIT(D099): a kernel that fixes the amdgpu open path needs no fence.
#
# Usage: scripts/smoke/gpu-fence.sh CMD [ARG...]
#        scripts/smoke/gpu-fence.sh --check
#
# The DRM nodes are read on every run from /sys/class/drm/<node>: `dev`
# holds the device number and `device/driver` names the driver. A node
# whose driver is amdgpu is an AMD node; no number is fixed.
#
# CMD runs in a user, mount and PID namespace bubblewrap makes. With an
# AMD path visible, a tmpfs covers /dev/dri and /dev/char, every other node
# is bound back, and every link that does not resolve to an AMD node is
# made again, the /dev/dri/by-path ones included. The user namespace maps
# the caller's own uid and gid, so files of another owner read as nobody's.
# The environment, the working directory, the open files and
# XDG_RUNTIME_DIR with its Wayland socket are the caller's, and the exit
# status is CMD's.
#
# The fence owns every process CMD starts. The PID namespace has its own
# /proc, and bubblewrap's init is its PID 1. The init ends once CMD has
# ended and bubblewrap's monitor has returned, or at once when the fence
# dies (--die-with-parent, SIGKILL included). The kernel then kills every
# process left in the namespace, one in another session or one a terminal
# stopped included. The fence names a ledger file in VGSHELL_FENCE_LEDGER;
# a command appends one absolute path a line for each directory it makes
# and wants gone. Once the namespace has ended, the fence gives the owner
# read, write and search back on each path and removes it, so a run
# ended by a signal, CMD's SIGKILL included, leaves no directory it named.
# A failed step prints `gpu-fence: cleanup=chmod-failed path=<path>` or
# `gpu-fence: cleanup=rm-failed path=<path>` on stderr. A SIGKILL of the
# fence itself ends every process and leaves the paths.
#
# The fence stays the parent of
# bubblewrap's monitor, which forwards no signal. The monitor runs in a
# process group of its own and CMD in a session of its own, with no
# controlling terminal. The first TERM, INT or HUP the fence gets goes to
# CMD once; the fence drops the later ones, waits for CMD's own exit
# handling to end and returns its status. A signal to every process of a
# unit reaches CMD directly as well. bubblewrap sets no_new_privs, so a
# setuid program gains nothing inside.
#
# Before CMD starts inside the namespace, the proof stats every path, with
# no open, and prints one line each on stderr:
#   gpu-fence: absent path=<path>
#   gpu-fence: present path=<path> dev=<major:minor>
# An AMD path that resolves, or another node or link the host had that no
# longer does, stops the run, and its reason lines come before every proof
# line. A namespace made around `true` runs the same proof first, so a
# failure there is the namespace's and never CMD's.
#
# Inside a fence's namespace, where VGSHELL_FENCE_LEDGER names a file and
# no AMD path is visible, CMD runs directly and nothing is printed.
#
# --check asks whether the caller needs the namespace: exit 0 inside a
# fence's namespace where no AMD path resolves, exit 1 otherwise, nothing
# printed. An entry
# point that starts a compositor, the shell, qmltestrunner or a browser
# goes on only after
#   gpu-fence.sh --check || exec gpu-fence.sh "$self" "${argv[@]}"
#
# --sys DIR and --dev DIR, before the mode, name the trees read in place
# of /sys and /dev: scripts/test-gpu-fence.sh hands it trees of ordinary
# files.
#
# The namespace hides the paths under /dev. Its /proc lists no process
# outside it, so /proc/<pid>/root and /proc/<pid>/fd reach no node through
# one.
#
# The amdgpu nodes that are no DRM nodes stay visible: /dev/fb*,
# /dev/drm_dp_aux* and /dev/kfd. The recorded fault's call path is the DRM
# file open, amdgpu_driver_open_kms into amdgpu_vm_init. That an open of
# those nodes stays out of it is read from that call path and not tested;
# the decision record holds what was measured of the programs run here.
#
# Exit: CMD's status. 2 on a refused argument. 77 when nothing was started,
# never a run outside the namespace; the first line on stderr names why:
#   gpu-fence: status=not-measured reason=bwrap-missing
#   gpu-fence: status=not-measured reason=ledger-failed
#   gpu-fence: status=not-measured reason=namespace-failed exit=<status>
#   gpu-fence: status=not-measured reason=amd-node-visible path=<path>
#   gpu-fence: status=not-measured reason=node-missing path=<path>
#   gpu-fence: status=not-measured reason=sysfs-unreadable path=<path>
#   gpu-fence: status=not-measured reason=entry-unclassified path=<path>
#   gpu-fence: status=not-measured reason=links-unreadable count=<n>
set -euo pipefail

note() { printf 'gpu-fence: %s\n' "$*" >&2; }

# fault REASON [KEY=VALUE]: the stable first line and what it means.
fault() {
  local reason="$1"
  shift
  note "status=not-measured reason=$reason${*:+ $*}"
  case "$reason" in
    bwrap-missing) note "  bubblewrap, which makes the namespace, is not on PATH" ;;
    ledger-failed) note "  the fence could not make the scratch directory that holds its ledger" ;;
    namespace-failed) note "  bubblewrap could not make the namespace; its output follows" ;;
    amd-node-visible) note "  a path to an amdgpu node resolves inside the namespace" ;;
    node-missing) note "  a node or link the host had does not resolve inside the namespace" ;;
    sysfs-unreadable) note "  a DRM node's device number or driver could not be read" ;;
    entry-unclassified) note "  an entry under the device tree is no node sysfs lists and no link, so the namespace cannot place it" ;;
    links-unreadable) note "  the links under the device tree could not be resolved" ;;
    *) note "  internal error: no text for this reason" ;;
  esac
}

sys=/sys
dev=/dev
mode=run
while (($#)); do
  case "$1" in
    --sys|--dev)
      [[ $# -ge 2 && -n $2 ]] || { note "refused: argument=$1"; exit 2; }
      if [[ $1 == --sys ]]; then sys="$2"; else dev="$2"; fi
      shift 2 ;;
    --check) mode=check; shift; break ;;
    --inside) mode=inside; shift; break ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    -*) note "refused: argument=$1"; exit 2 ;;
    *) break ;;
  esac
done

# The paths that must not resolve, the ones that must, and the bubblewrap
# words that rebuild the two directories; plan fills them.
hidden=()
kept=()
rebuild=()

# plan: classify every DRM node of $sys and every entry of $dev/dri and
# $dev/char. An entry it cannot classify stops the run: a node sysfs does
# not list has no known driver, and a tmpfs over the directory would lose
# an entry that is neither such a node nor a link.
plan() {
  local node name number driver entry target index
  local -a nodes=() links=() resolved=() raw=() dirs=() symlinks=()
  local -A amd=() other=() amd_target=() kept_target=() is_hidden=()
  for node in "$sys"/class/drm/*; do
    # A connector and the `version` file carry no device number.
    [[ -e $node/dev ]] || continue
    name="${node##*/}"
    number="$(<"$node/dev")" || number=""
    [[ $number =~ ^[0-9]+:[0-9]+$ ]] || { fault sysfs-unreadable "path=$node/dev"; exit 77; }
    driver=none
    if [[ -L $node/device/driver ]]; then
      driver="$(readlink -- "$node/device/driver")" || { fault sysfs-unreadable "path=$node/device/driver"; exit 77; }
      driver="${driver##*/}"
    fi
    if [[ $driver == amdgpu ]]; then
      amd[$name]="$number"
      hidden+=("$dev/dri/$name" "$dev/char/$number")
      is_hidden[$dev/dri/$name]=1
      is_hidden[$dev/char/$number]=1
    else
      other[$name]="$number"
    fi
    nodes+=("$dev/dri/$name")
  done
  for entry in "$dev"/dri/*; do
    [[ -e $entry || -L $entry ]] || continue
    if [[ -L $entry ]]; then
      links+=("$entry")
    elif [[ -d $entry ]]; then
      dirs+=(--dir "$entry")
    elif [[ -n ${amd[${entry##*/}]:-} ]]; then
      :
    elif [[ -n ${other[${entry##*/}]:-} ]]; then
      kept+=("$entry")
      rebuild+=(--dev-bind "$entry" "$entry")
    else
      fault entry-unclassified "path=$entry"; exit 77
    fi
  done
  # With no amdgpu node nothing is hidden and nothing is rebuilt.
  ((${#amd[@]})) || return 0
  for entry in "$dev"/dri/*/* "$dev"/char/*; do
    [[ -e $entry || -L $entry ]] || continue
    # A link to a directory is made again as that link, with nothing under it.
    [[ ! -L ${entry%/*} ]] || continue
    [[ -L $entry ]] || { fault entry-unclassified "path=$entry"; exit 77; }
    links+=("$entry")
  done
  # realpath and readlink read names only and open no node. Each prints
  # one line per argument, so a short answer is a failed read.
  if ! target="$(realpath -m -- "${nodes[@]}" "${links[@]}")" || ! mapfile -t resolved <<<"$target" ||
     [[ ${#resolved[@]} -ne $((${#nodes[@]} + ${#links[@]})) ]]; then
    fault links-unreadable "count=$((${#nodes[@]} + ${#links[@]}))"; exit 77
  fi
  if ((${#links[@]})); then
    if ! target="$(readlink -- "${links[@]}")" || ! mapfile -t raw <<<"$target" || [[ ${#raw[@]} -ne ${#links[@]} ]]; then
      fault links-unreadable "count=${#links[@]}"; exit 77
    fi
  fi
  for index in "${!nodes[@]}"; do
    name="${nodes[index]##*/}"
    if [[ -n ${amd[$name]:-} ]]; then amd_target[${resolved[index]}]=1; else kept_target[${resolved[index]}]=1; fi
  done
  for index in "${!links[@]}"; do
    entry="${links[index]}"
    target="${resolved[${#nodes[@]} + index]}"
    if [[ -n ${is_hidden[$entry]:-} ]]; then
      continue
    elif [[ -n ${amd_target[$target]:-} ]]; then
      hidden+=("$entry")
      continue
    fi
    symlinks+=(--symlink "${raw[index]}" "$entry")
    # Only a link to a DRM node is proved present; the rest stand as made.
    [[ -z ${kept_target[$target]:-} || ! -e $entry ]] || kept+=("$entry")
  done
  [[ ! -d $dev/dri ]] || rebuild=(--tmpfs "$dev/dri" "${rebuild[@]}" "${dirs[@]}")
  [[ ! -d $dev/char ]] || rebuild+=(--tmpfs "$dev/char")
  rebuild+=("${symlinks[@]}")
}

# exposed: true when a hidden path resolves in the caller's view.
exposed() {
  local path
  for path in "${hidden[@]}"; do
    [[ ! -e $path ]] || return 0
  done
  return 1
}

# fenced: true inside a fence's namespace, which names its ledger there.
fenced() { [[ -n ${VGSHELL_FENCE_LEDGER-} && -f $VGSHELL_FENCE_LEDGER ]]; }

# release: once the namespace has ended, give the owner bits back on each
# path the ledger names and remove it, then the fence's scratch directory.
# bubblewrap's monitor returns once CMD has ended, and the init it leaves
# is killed by --die-with-parent as the monitor exits, so the rest of the
# namespace can outlive the monitor by a moment. The namespace is empty
# once its init has left it: the kernel kills and reaps every other
# process before PID 1 exits. --info-fd names the init and its namespace.
release() {
  local init="" ns="" path _
  [[ -n ${fence_dir-} ]] || return 0
  if [[ -s $fence_dir/info ]]; then
    init="$(sed -n 's/^ *"child-pid": *\([0-9]*\),*$/\1/p' "$fence_dir/info")" || init=""
    ns="$(sed -n 's/^ *"pid-namespace": *\([0-9]*\),*$/\1/p' "$fence_dir/info")" || ns=""
  fi
  if [[ -n $init && -n $ns ]]; then
    # A real wait: the kernel ends the namespace within milliseconds.
    for _ in $(seq 1 100); do
      [[ "$(readlink "/proc/$init/ns/pid" 2>/dev/null)" == "pid:[$ns]" ]] || break
      sleep 0.05
    done
  fi
  while IFS= read -r path; do
    [[ $path == /* ]] && [[ -e $path || -L $path ]] || continue
    chmod -R u+rwX -- "$path" 2>/dev/null || note "cleanup=chmod-failed path=$path"
    rm -rf -- "${path:?}" 2>/dev/null || note "cleanup=rm-failed path=$path"
  done <"$fence_dir/ledger"
  rm -rf -- "${fence_dir:?}"
}

# inside ABSENT... -- PRESENT... -- CMD...: the proof, then CMD. Every path
# is read before the verdict, so the lines hold the whole view. A fault's
# lines are printed as it is found and the proof lines after the last
# path, so the first line of a failed proof is a reason.
inside() {
  local number broken=false list line
  local -a proof=()
  for list in absent present; do
    while [[ ${1-} != -- ]]; do
      (($#)) || { note "refused: argument=--inside"; exit 2; }
      if [[ $list == absent ]]; then
        if [[ -e $1 ]]; then fault amd-node-visible "path=$1"; broken=true; else proof+=("absent path=$1"); fi
      elif number="$(stat -L -c '%Hr:%Lr' -- "$1" 2>/dev/null)"; then
        proof+=("present path=$1 dev=$number")
      else
        fault node-missing "path=$1"; broken=true
      fi
      shift
    done
    shift
  done
  (($#)) || { note "refused: argument=--inside"; exit 2; }
  for line in "${proof[@]}"; do note "$line"; done
  [[ $broken == false ]] || exit 77
  exec "$@"
}

# ours PID: true while PID is the fence's child. The fence reaps the
# monitor only in its own wait and starts no other child after it, so a
# pid whose parent reads as the fence is still the monitor.
ours() {
  local stat=()
  read -r -a stat 2>/dev/null <"/proc/$1/stat" && [[ ${stat[3]-} == "$$" ]]
}

# forward SIGNAL STATUS: hand the first TERM, INT or HUP to CMD, the one
# child of the namespace's init, which is the monitor's one child, and drop
# every later one, so CMD's exit handling gets one signal. A signal can run
# this again inside a run of it, so the count is read and raised in one
# command. Before the monitor starts nothing has, and the fence exits with
# STATUS. Before CMD has started, the monitor's group holds what has.
forwarded=0
forward() {
  ((forwarded++ == 0)) || return 0
  local monitor="${!:-}" init="" child=""
  [[ -n $monitor ]] || exit "$2"
  ours "$monitor" || return 0
  read -r init _ 2>/dev/null <"/proc/$monitor/task/$monitor/children" || true
  [[ -z $init ]] || read -r child _ 2>/dev/null <"/proc/$init/task/$init/children" || true
  if [[ -n $child ]]; then
    kill -s "$1" -- "$child" 2>/dev/null || true
  else
    kill -s "$1" -- "-$monitor" 2>/dev/null || true
  fi
}

case "$mode" in
  check)
    plan
    if exposed || ! fenced; then exit 1; fi
    exit 0 ;;
  inside)
    inside "$@" ;;
  run)
    (($#)) || { note "refused: argument=missing-command"; exit 2; }
    plan
    ! fenced || exposed || exec "$@"
    command -v bwrap >/dev/null 2>&1 || { fault bwrap-missing; exit 77; }
    self="$(readlink -f -- "${BASH_SOURCE[0]}")"
    fence_dir="$(mktemp -d "${TMPDIR:-/tmp}/vgshell-fence.XXXXXX")" || { fault ledger-failed; exit 77; }
    trap release EXIT
    : >"$fence_dir/ledger"
    # With no AMD node nothing under /dev changes, and nothing is proved.
    if ((${#hidden[@]} == 0)); then rebuild=(); kept=(); fi
    # CMD gets a session of its own: in the caller's session, with the
    # monitor's group in the background, a terminal would stop it on a read
    # or a mode change.
    fence=(bwrap --dev-bind / / "${rebuild[@]}" --unshare-pid --proc /proc --die-with-parent --new-session
      --setenv VGSHELL_FENCE_LEDGER "$fence_dir/ledger")
    proof=(-- "$BASH" "$self" --inside "${hidden[@]}" -- "${kept[@]}" --)
    status=0
    probe="$("${fence[@]}" "${proof[@]}" true 2>&1)" || status=$?
    case "$status" in
      0) ;;
      # The proof inside the probe named its own reason.
      77) printf '%s\n' "$probe" >&2; exit 77 ;;
      *) fault namespace-failed "exit=$status"; printf '%s\n' "$probe" >&2; exit 77 ;;
    esac
    # bubblewrap's monitor forwards no signal, so the fence stays its parent.
    # The monitor gets a process group of its own: `set -m` makes it in
    # parent and child before `&` returns. A signal to the caller's group
    # then reaches the fence alone.
    trap 'forward TERM 143' TERM
    trap 'forward INT 130' INT
    trap 'forward HUP 129' HUP
    set -m
    "${fence[@]}" --info-fd 3 "${proof[@]}" "$@" 3>"$fence_dir/info" &
    set +m
    monitor=$!
    # A trapped signal ends a wait early, and so can one that comes while
    # the trap runs. The shell keeps the monitor's status for the last wait.
    while ours "$monitor"; do
      wait "$monitor" || true
    done
    status=0
    wait "$monitor" || status=$?
    exit "$status" ;;
esac
