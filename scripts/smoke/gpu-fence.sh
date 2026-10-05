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
# With an AMD path visible, CMD runs in a user namespace and a mount
# namespace bubblewrap makes: a tmpfs covers /dev/dri and /dev/char, every
# other node is bound back, and every link that does not resolve to an AMD
# node is made again, the /dev/dri/by-path ones included. The user
# namespace maps the caller's own uid and gid, so files of another owner
# read as nobody's. The PID namespace, the environment, the working
# directory, the open files and XDG_RUNTIME_DIR with its Wayland socket are
# the caller's, and the exit status is CMD's. CMD's parent is bubblewrap's
# monitor, which forwards no signal: a signal sent to that one pid ends the
# monitor and not CMD, and a caller's wait can return before CMD's own exit
# handling ends, so stop a run by its process group or its unit. bubblewrap
# sets no_new_privs, so a setuid program gains nothing inside.
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
# With no amdgpu node, or with none visible because the caller already
# runs inside the namespace, CMD runs directly and nothing is printed.
#
# --check asks whether the caller needs the namespace: exit 0 when no AMD
# path resolves here, exit 1 when one does, nothing printed. An entry
# point that starts a compositor, the shell, qmltestrunner or a browser
# goes on only after
#   gpu-fence.sh --check || exec gpu-fence.sh "$self" "${argv[@]}"
#
# --sys DIR and --dev DIR, before the mode, name the trees read in place
# of /sys and /dev: scripts/test-gpu-fence.sh hands it trees of ordinary
# files.
#
# The namespace hides the paths under /dev. A path through another
# process's root or open files, /proc/<pid>/root and /proc/<pid>/fd of a
# process outside it, still reaches the node: the PID namespace is the
# caller's so that the harness reads /proc.
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
    bwrap-missing) note "  an amdgpu node is visible and bubblewrap, which hides it, is not on PATH" ;;
    namespace-failed) note "  bubblewrap could not make the mount namespace; its output follows" ;;
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

case "$mode" in
  check)
    plan
    if exposed; then exit 1; fi
    exit 0 ;;
  inside)
    inside "$@" ;;
  run)
    (($#)) || { note "refused: argument=missing-command"; exit 2; }
    plan
    exposed || exec "$@"
    command -v bwrap >/dev/null 2>&1 || { fault bwrap-missing; exit 77; }
    self="$(readlink -f -- "${BASH_SOURCE[0]}")"
    fence=(bwrap --dev-bind / / "${rebuild[@]}" -- "$BASH" "$self" --inside "${hidden[@]}" -- "${kept[@]}" --)
    status=0
    probe="$("${fence[@]}" true 2>&1)" || status=$?
    case "$status" in
      0) ;;
      # The proof inside the probe named its own reason.
      77) printf '%s\n' "$probe" >&2; exit 77 ;;
      *) fault namespace-failed "exit=$status"; printf '%s\n' "$probe" >&2; exit 77 ;;
    esac
    exec "${fence[@]}" "$@" ;;
esac
