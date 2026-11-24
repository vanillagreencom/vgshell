#!/usr/bin/env bash
# Run a command where no amdgpu DRM node exists, so nothing it starts can
# open one. The amdgpu driver's per-open path can stop the kernel
# (docs/decisions/D099-no-amdgpu-node-in-validation-runs.md). The nested
# compositor and the shell list /dev/dri and open nodes from that listing,
# whatever device an environment variable names, and which library opened
# the amdgpu node is not proven. So the node is hidden, not deselected.
# REVISIT(D099): a kernel that fixes the amdgpu open path needs no fence.
#
# Usage: scripts/smoke/gpu-fence.sh [DECLARATIONS] -- CMD [ARG...]
#        scripts/smoke/gpu-fence.sh --throwaway-host [DECLARATIONS] -- CMD [ARG...]
#        scripts/smoke/gpu-fence.sh --check
#
# The DRM nodes are read on every run from /sys/class/drm/<node>: `dev`
# holds the device number and `device/driver` names the driver. A node
# whose driver is amdgpu is an AMD node; no number is fixed.
#
# CMD runs in the test world: the host is read-only, /dev keeps device
# access, /tmp, /dev/shm and XDG_RUNTIME_DIR are private tmpfs mounts,
# the caller runtime and the system buses are hidden, and the network is
# unshared unless --net names the selftest exception. D112 owns this boundary.
# On a host the run declares it created, CMD runs in the throwaway world
# below instead (D142).
# Its PATH is the caller's behind one directory that holds the native node
# alone, so every command the caller puts on PATH keeps its place.
#
# The world exclusively creates VGSHELL_WORLD_ROOT under the caller TMPDIR,
# named for its owner: this process's pid, start time and PID namespace.
# Every temporary tree lives there. After the PID namespace ends, this
# process alone retains row evidence, restores owner write bits and removes
# that root. --keep keeps it, marks it kept in its name and prints its path.
# SIGKILL of this process ends the namespace but runs no trap and leaves the
# root; the next run to make a root under the same TMPDIR removes it
# (reap_orphans in scripts/smoke/reap.sh) and never one whose owner is
# alive or cannot be read. A root with no owner in its name (older code
# made it) goes only when older than 10800 s and no process holds it as a
# cwd, descriptor or mount point.
#
# --out DIR declares a writable output directory. A directory which is or
# contains the checkout, its git directory or the caller HOME is refused.
# --input DIR preserves prepared input through private mounts, read-only.
# --nix-store DIR copies an exported /nix into the owned root and binds that
# copy at /nix, writable. D113 owns the root built from host mounts.
# --secrets starts the selftest's filtered bus outside the namespace and
# binds only its socket inside. --sign-in VARIABLE DIR declares the selected
# account directory, its variable and its writable bind. Neither exception
# supplies the caller's raw bus. The rules below own the allowed bus calls.
# --fresh gives a validate row its own root even when validate itself is
# inside a test world. Other entry points reuse the world they already have.
#
# The fence remains bubblewrap's parent. TERM, INT and HUP each go once to
# every process group of CMD's session that CMD's processes are in, CMD's
# foreground command included; bubblewrap's monitor ignores them, so a
# stop that signals every process, as a systemd unit's stop does, ends CMD
# by its own exit handling before the namespace ends. A stop that comes
# before the proof has given them back to CMD ends the world at once. The
# PID namespace and --die-with-parent end every descendant after CMD ends,
# including children in other sessions and stopped children; in a
# throwaway world the fence's sweep ends them (below).
# Its /proc exposes no outside process or descriptor.
#
# --throwaway-host declares that the caller created this host and will
# delete it. Only a sandbox runner's outermost call passes it; no entry
# point in this repository does. CMD then runs on the host itself, without
# bubblewrap. It keeps the owned root and its name, the reaper, --keep, the
# --out and --input refusals, evidence retention, the ceiling and the
# declared environment table, passed by env -i with XDG_RUNTIME_DIR at
# <root>/xdg, whose `owned` links to <root>/runtime as the bwrap world's
# /tmp/vr/owned binds it. It drops the read-only host, the private /tmp and
# /dev/shm, the unshared network and the PID namespace, so it refuses the
# declarations that need a mount namespace or a host view of its own:
#   gpu-fence: refused: throwaway=<--secrets|--sign-in|--nix-store|--sys|--dev>
# A nested call inherits the throwaway world only when VGSHELL_WORLD_ROOT
# holds that world's `throwaway` marker and the owner the root's name
# records is a live ancestor of the caller. Every throwaway start, declared
# or inherited, first reads the real /sys and /run and stops at the first
# fact of a person's computer: an amdgpu node plan finds, an entry under
# /sys/class/input, a connector under /sys/class/drm, or a live session (an
# entry under /run/user or /run/systemd/sessions, /run/dbus/system_bus_socket
# or /run/tailscale). Before CMD starts the fence makes itself the child
# subreaper of CMD's tree, so every orphan in it, one in another session
# included, becomes the fence's child. CMD runs in a process group of its
# own in the caller's session, where a read from a controlling terminal
# would stop it, so the runner starts the fence with none. TERM, INT and
# HUP each go once to every process group of that session that CMD's
# processes are in. When CMD ends the fence KILLs every process left in its
# tree, and only then retains evidence and removes the root; a process
# still there after 5 s is named on a cleanup=sweep-failed line and keeps
# the root, renamed to kind k so no reaper removes it. A SIGKILL of the
# fence leaves that tree to the nearest living subreaper: the outer fence
# of a nested world, which ends it only once its own CMD ends, or else the
# host the runner deletes. So a stop that must end the tree KILLs CMD, the
# child-pid the root's info holds with the host's PID namespace, and the
# fence sweeps; the root is named for the fence, so a caller that holds
# the fence's pid finds it before CMD writes anything. stderr carries
#   gpu-fence: world=throwaway
# in place of the proof lines, before the ceiling line.
#
# Every process the world starts runs under one data ceiling, RLIMIT_DATA
# (setrlimit(2): the heap and private writable mappings), which prlimit sets
# on bubblewrap before it starts, so the whole namespace inherits it (in a
# throwaway world, on CMD before it starts).
# VGS_VALIDATE_ROW_MEMORY names the ceiling in bytes; unset or empty, it is
# 17179869184 (16 GiB), on the readings docs/architecture/validation.md
# § Host safety names. A world started under a lower limit keeps that
# limit, so a nested world never raises the one it inherited. An
# allocation past the ceiling fails in the process that asks for it. The
# ceiling bounds each process, not the sum of a world's processes. A check
# that enters no world has none. A value that is no positive whole number
# of bytes is refused before anything starts:
#   gpu-fence: refused: row-memory=<value>
# The same call sets RLIMIT_CORE to 0, so a world writes no core: a process
# that aborts at the ceiling leaves no core of its memory on the host.
# systemd-coredump, where core_pattern pipes to it, processes a core only
# when that limit is sufficient (systemd-coredump(8)).
#
# Before CMD starts inside the namespace, the proof stats every path, with
# no open, and prints one line each on stderr:
#   gpu-fence: absent path=<path>
#   gpu-fence: present path=<path> dev=<major:minor>
# An AMD path that resolves, or another node or link the host had that no
# longer does, stops the run, and its reason lines come before every proof
# line. A namespace made around `true` runs the same proof first, so a
# failure there is the namespace's and never CMD's. After a proof that
# holds, the ceiling in force, read back inside the namespace, follows the
# proof lines, so a failed row's log names it:
#   gpu-fence: ceiling=data limit=<bytes>
#
# --check reads access permissions and mounts: the checkout must be read-only,
# the owned root writable and every AMD path absent. In a throwaway world it
# passes when the world is inherited as above, the host passes the
# throwaway refusals and the root is writable. It never writes.
# An entry point continues only after
#   gpu-fence.sh --check || exec gpu-fence.sh [DECLARATIONS] "$self" "${argv[@]}"
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
# never a run outside the namespace but in a declared throwaway world; the
# first status=not-measured line on stderr names why (cleanup= lines may
# come before it):
#   gpu-fence: status=not-measured reason=bwrap-missing
#   gpu-fence: status=not-measured reason=throwaway-refused fact=<amdgpu|input|connector|session> path=<path>
#   gpu-fence: status=not-measured reason=subreaper-failed <errno=<n>|python3=unusable|path=<path>>
#   gpu-fence: status=not-measured reason=invariant <name>=<value>
#   gpu-fence: status=not-measured reason=owner-record-unreadable path=<path>
#   gpu-fence: status=not-measured reason=root-failed
#   gpu-fence: status=not-measured reason=namespace-failed exit=<status>
#   gpu-fence: status=not-measured reason=amd-node-visible path=<path>
#   gpu-fence: status=not-measured reason=node-missing path=<path>
#   gpu-fence: status=not-measured reason=sysfs-unreadable path=<path>
#   gpu-fence: status=not-measured reason=entry-unclassified path=<path>
#   gpu-fence: status=not-measured reason=links-unreadable count=<n>
#   gpu-fence: status=not-measured reason=limits-unreadable path=<path>
set -euo pipefail

note() { printf 'gpu-fence: %s\n' "$*" >&2; }

# fault REASON [KEY=VALUE]: the stable first line and what it means.
fault() {
  local reason="$1"
  shift
  note "status=not-measured reason=$reason${*:+ $*}"
  case "$reason" in
    bwrap-missing) note "  bubblewrap, which makes the namespace, is not on PATH" ;;
    owner-record-unreadable) note "  the world could not read its own start time or PID namespace for the owner record" ;;
    root-failed) note "  the world could not make its owned run root" ;;
    namespace-failed) note "  bubblewrap could not make the namespace; its output follows" ;;
    amd-node-visible) note "  a path to an amdgpu node resolves inside the namespace" ;;
    node-missing) note "  a node or link the host had does not resolve inside the namespace" ;;
    sysfs-unreadable) note "  a DRM node's device number or driver, or a directory the throwaway refusals list, could not be read" ;;
    throwaway-refused) note "  the host shows an amdgpu node, an input device, a display output or a live session, so the throwaway world does not start on it (D142)" ;;
    subreaper-failed) note "  the fence could not make itself the subreaper that ends CMD's descendants in a throwaway world" ;;
    invariant) note "  a value the fence sets itself holds none of its cases: a defect of the fence" ;;
    entry-unclassified) note "  an entry under the device tree is no node sysfs lists and no link, so the namespace cannot place it" ;;
    links-unreadable) note "  the links under the device tree could not be resolved" ;;
    limits-unreadable) note "  the data limit this process runs under could not be read" ;;
    *) note "  internal error: no text for this reason" ;;
  esac
}

sys=/sys
dev=/dev
mode=run
world_runtime=/tmp/vr
self="$(readlink -f -- "${BASH_SOURCE[0]}")"
source "${self%/*}/reap.sh"
checkout="$(cd -- "${self%/*}/../.." && pwd -P)"
outputs=()
inputs=()
nix_store=""
output_roots=()
keep=false
fresh=false
network=(--unshare-net)
secrets=false
sign_in_name="" sign_in_dir=""
throwaway_declared=false
tree_flag=""
# --subreaper STATUS is the fence's own first argument when it has re-executed
# itself as the subreaper of a throwaway world: prctl's errno, 0 on success,
# or `unusable` when the program that sets it failed.
subreaper=""
fence_argv=("$@")
while (($#)); do
  case "$1" in
    --subreaper)
      [[ $# -ge 2 && $2 =~ ^([0-9]+|unusable)$ ]] || { note "refused: argument=$1"; exit 2; }
      subreaper="$2"; shift 2 ;;
    --throwaway-host) throwaway_declared=true; shift ;;
    --out|--input|--nix-store|--checkout|--sign-in)
      [[ $# -ge 2 && -n $2 ]] || { note "refused: argument=$1"; exit 2; }
      case "$1" in
        --out) outputs+=("$2"); shift 2 ;;
        --input) inputs+=("$2"); shift 2 ;;
        --nix-store) nix_store="$(realpath -e -- "$2")" && [[ -d $nix_store ]] || { note 'refused: nix-store=unreadable'; exit 2; }; shift 2 ;;
        --checkout) checkout="$2"; shift 2 ;;
        --sign-in)
          [[ $# -ge 3 && -d $3 ]] || { note "refused: argument=--sign-in"; exit 2; }
          case "$2" in CLAUDE_CONFIG_DIR|CODEX_HOME|COPILOT_HOME|PI_CODING_AGENT_DIR) ;; *) note "refused: argument=--sign-in variable=$2"; exit 2 ;; esac
          sign_in_name="$2" sign_in_dir="$(realpath -e -- "$3")"; shift 3 ;;
      esac ;;
    --keep) keep=true; shift ;;
    --fresh) fresh=true; shift ;;
    --net) network=(); shift ;;
    --secrets) secrets=true; shift ;;
    --) shift; break ;;
    --sys|--dev)
      [[ $# -ge 2 && -n $2 ]] || { note "refused: argument=$1"; exit 2; }
      if [[ $1 == --sys ]]; then sys="$2"; else dev="$2"; fi
      tree_flag="$1"
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

# data_limit: this process's RLIMIT_DATA as "<soft> <hard>", each a byte
# count or `unlimited`, from its "Max data size" line in /proc/<pid>/limits
# (proc_pid_limits(5)).
data_limit() {
  local line soft hard
  while read -r line; do
    [[ $line == "Max data size "* ]] || continue
    read -r _ _ _ soft hard _ <<<"$line"
    [[ $soft =~ ^([0-9]+|unlimited)$ && $hard =~ ^([0-9]+|unlimited)$ ]] || return 1
    printf '%s %s\n' "$soft" "$hard"
    return 0
  done <"/proc/$$/limits"
  return 1
}

# exposed: true when a hidden path resolves in the caller's view.
exposed() {
  local path
  for path in "${hidden[@]}"; do
    [[ ! -e $path ]] || return 0
  done
  return 1
}

# Check permissions and the world's root/runtime mounts without writing.
# The marker alone grants no permission to start or inherit a world.
fenced() {
  local readonly_tree="${1:-$checkout}" device mount_root mount_path mount_options
  local host_readonly=false own_root="" own_device="" runtime_root="" runtime_device=""
  [[ -n ${VGSHELL_WORLD_ROOT-} && -d $VGSHELL_WORLD_ROOT && -w $VGSHELL_WORLD_ROOT && ! -w $readonly_tree ]] || return 1
  # A read-only host filesystem alone is no world. Its owned runtime must
  # be backed by the same root that this invocation would inherit.
  while read -r _ _ device mount_root mount_path mount_options _; do
    printf -v mount_path '%b' "$mount_path"
    printf -v mount_root '%b' "$mount_root"
    if [[ $mount_path == / && ,$mount_options, == *,ro,* ]]; then host_readonly=true; fi
    if [[ $mount_path == "$VGSHELL_WORLD_ROOT" ]]; then own_root="$mount_root"; own_device="$device"; fi
    if [[ $mount_path == "$world_runtime/owned" ]]; then runtime_root="$mount_root"; runtime_device="$device"; fi
  done </proc/self/mountinfo
  [[ $host_readonly == true && -n $own_root && $runtime_device == "$own_device" && $runtime_root == "$own_root/runtime" ]]
}

# invariant NAME=VALUE: a value this script sets itself holds none of its
# cases.
invariant() { fault invariant "$1"; exit 77; }

# listing DIR: set listed to DIR's entries. A DIR that is no directory this
# process can list stops the run: an empty answer from it would read as a
# host that registers nothing.
listing() {
  local entry
  listed=()
  [[ -d $1 && -r $1 && -x $1 ]] || { fault sysfs-unreadable "path=$1"; exit 77; }
  for entry in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    if [[ -e $entry || -L $entry ]]; then listed+=("$entry"); fi
  done
}

# host_refused FACT PATH: the host shows FACT at PATH, so it is taken for a
# person's computer and nothing starts.
host_refused() { fault throwaway-refused "fact=$1 path=$2"; exit 77; }

# throwaway_host: the throwaway world's refusals (D142), read from the real
# /sys and /run; world_kind refuses --sys and --dev before this runs, so
# plan read the real trees too. /sys/class/input and /sys/class/drm must be
# listable: a host with no sysfs mounted would show neither fact. /run/user
# and /run/systemd/sessions may be absent, as on a host with no login
# manager. The order of the facts is the order of the reasons.
throwaway_host() {
  local entry dir
  local -a drm=()
  listing /sys/class/drm
  drm=("${listed[@]}")
  # plan hides an amdgpu node's paths, its /dev/dri name first; here
  # nothing could hide them (D099).
  ((${#hidden[@]} == 0)) || host_refused amdgpu "${hidden[0]}"
  listing /sys/class/input
  ((${#listed[@]} == 0)) || host_refused input "${listed[0]}"
  # The kernel names a connector card<N>-<connector> beside its card<N>
  # (drm_sysfs.c, drm_sysfs_connector_add); cachy lists card0-DP-4 and
  # card0-Writeback-1 beside card0 (VGS-2747).
  for entry in "${drm[@]}"; do
    [[ ${entry##*/} != card*-* ]] || host_refused connector "$entry"
  done
  for dir in /run/user /run/systemd/sessions; do
    [[ -e $dir || -L $dir ]] || continue
    listing "$dir"
    ((${#listed[@]} == 0)) || host_refused session "${listed[0]}"
  done
  for entry in /run/dbus/system_bus_socket /run/tailscale; do
    [[ ! -e $entry && ! -L $entry ]] || host_refused session "$entry"
  done
}

# throwaway_parent: true when VGSHELL_WORLD_ROOT is the root of a throwaway
# world this process runs in. The root holds the marker that world wrote,
# and the owner its name records (pid, start time and PID namespace,
# reap.sh's form) is an ancestor of this process, found by its parent
# links. A planted marker without such an owner is no world, and neither is
# a sibling run's root.
throwaway_parent() {
  local root="${VGSHELL_WORLD_ROOT-}" name pid start ns at line current
  local -a fields=()
  [[ -n $root && -d $root && -f $root/throwaway ]] || return 1
  name="${root##*/}"
  [[ $name == vgshell-world.* && ${name#vgshell-world.} =~ $root_owner_form ]] || return 1
  pid="${BASH_REMATCH[1]}" start="${BASH_REMATCH[2]}" ns="${BASH_REMATCH[3]}"
  at=$$
  while [[ $at != "$pid" ]]; do
    read -r line 2>/dev/null <"/proc/$at/stat" || return 1
    # Field 4 of stat (proc(5)) is the parent, counted from the last ") "
    # as in proc_start (reap.sh); init's is 0, past every ancestor.
    read -r -a fields <<<"${line##*) }"
    at="${fields[1]-}"
    [[ $at =~ ^[1-9][0-9]*$ ]] || return 1
  done
  current="$(proc_start "$pid")" && [[ $current == "$start" ]] &&
    current="$(pid_namespace "$pid")" && [[ $current == "$ns" ]]
}

# world_kind: the one decision of the world this call runs in, made once
# after argument parsing and plan. `bwrap` is the namespace D112 owns.
# `throwaway` is the host itself, declared by the runner that made it or
# inherited from a throwaway world this process runs in (D142); it is no
# fallback, so a host that fails its refusals never gets the bwrap world
# instead. Every branch on `world` names both and asserts on any other.
world_kind() {
  inherited_world=false
  if throwaway_parent; then inherited_world=true; fi
  if [[ $throwaway_declared == false && $inherited_world == false ]]; then
    [[ -z $subreaper ]] || { note "refused: argument=--subreaper"; exit 2; }
    world=bwrap
    return 0
  fi
  [[ -z $tree_flag ]] || { note "refused: throwaway=$tree_flag"; exit 2; }
  [[ $secrets == false ]] || { note "refused: throwaway=--secrets"; exit 2; }
  [[ -z $sign_in_name ]] || { note "refused: throwaway=--sign-in"; exit 2; }
  [[ -z $nix_store ]] || { note "refused: throwaway=--nix-store"; exit 2; }
  throwaway_host
  world=throwaway
}

# Run by python3 -I as the fence's own image with the fence's SigIgn mask:
# set the child subreaper attribute, then exec bash on the fence again with
# --subreaper and prctl's errno, so the pid the caller holds stays the
# fence's. PR_SET_CHILD_SUBREAPER is 36 (linux/prctl.h); the attribute "is
# preserved across execve(2)" and an orphan "will be reparented to the
# nearest still living ancestor subreaper" (PR_SET_CHILD_SUBREAPER(2const)).
# Python ignores SIGPIPE and SIGXFSZ at start (the signal module's
# documentation), an exec keeps an ignored signal ignored, and bash cannot
# trap or reset one ignored on entry (bash(1), trap): a recorded run of a
# python3 -I execv into bash read SigIgn 0x1001000 against the caller's
# 0x1000000. So both go back to their default unless the caller's mask,
# whose bit N-1 is signal N, ignores them. Any other failure of this
# program reaches the fence as `--subreaper unusable`.
become_subreaper='import os, sys
try:
    import ctypes, signal
    ignored = int(sys.argv[3], 16)
    for number in (signal.SIGPIPE, signal.SIGXFSZ):
        if not ignored >> (number - 1) & 1:
            signal.signal(number, signal.SIG_DFL)
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(ctypes.c_int(36), ctypes.c_ulong(1), ctypes.c_ulong(0), ctypes.c_ulong(0), ctypes.c_ulong(0)) == 0:
        status = "0"
    else:
        status = str(ctypes.get_errno() or "unusable")
except Exception:
    status = "unusable"
os.execv(sys.argv[1], [sys.argv[1], sys.argv[2], "--subreaper", status, *sys.argv[4:]])'

# Run by python3 -I with the fence's pid: KILL every process whose parent is
# the fence, wait for each to end, and list again until none is left, since
# a KILLed process's children become the fence's. A pid read from /proc may
# pass to another process once the fence reaps the one it named, which this
# process cannot hold off, so each KILL goes through a pidfd opened before
# the parent is read again: the pidfd names the one process (pidfd_open(2):
# it becomes readable when that process ends). This process and the command
# substitution that runs it are spared. A zombie has ended. The 5 s bound
# is the one release's namespace wait uses; a process still there after it,
# as one held in an uninterruptible sleep, is named and keeps the root.
sweep='import os, select, signal, sys, time
fence = sys.argv[1]
spared = {os.getpid(), os.getppid()}
deadline = time.monotonic() + 5
def parent(pid):
    try:
        with open("/proc/%d/stat" % pid) as stream:
            fields = stream.read().rpartition(") ")[2].split()
    except OSError:
        return None
    return None if fields[0] == "Z" else fields[1]
while True:
    left = [pid for pid in map(int, filter(str.isdigit, os.listdir("/proc"))) if pid not in spared and parent(pid) == fence]
    if not left:
        sys.exit(0)
    if time.monotonic() > deadline:
        print("left=" + ",".join(map(str, left)))
        sys.exit(1)
    poller, handles, pending = select.poll(), [], set()
    for pid in left:
        try:
            handle = os.pidfd_open(pid)
        except ProcessLookupError:
            continue
        handles.append(handle)
        if parent(pid) != fence:
            continue
        try:
            signal.pidfd_send_signal(handle, signal.SIGKILL)
        except ProcessLookupError:
            continue
        poller.register(handle, select.POLLIN)
        pending.add(handle)
    while pending and time.monotonic() < deadline:
        for handle, _ in poller.poll(max(1, int((deadline - time.monotonic()) * 1000))):
            poller.unregister(handle)
            pending.discard(handle)
    for handle in handles:
        os.close(handle)'

# Wait for the namespace's init to leave before reading evidence or removing
# the one root this process acquired. PID 1 exits after the kernel reaps
# every other process in its namespace. A throwaway world has no namespace:
# the fence, the subreaper of CMD's tree, ends what is left of it first,
# and keeps the root when it cannot.
release() {
  local init="" ns="" path error="" kept_dir swept=true _
  [[ -n ${fence_dir-} ]] || return 0
  if [[ -n ${proxy_pid:-} ]]; then
    exec {proxy_read}<&-
    wait "$proxy_pid" 2>/dev/null || true
  fi
  case "$world" in
    bwrap)
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
      fi ;;
    throwaway)
      # The wait has reaped CMD, so its pid may pass to another process in
      # the host's PID namespace, the one info names; the no-progress stop
      # (qml_smoke_end_world) must find no pid there to KILL.
      rm -f -- "$fence_dir/info"
      if ! error="$(python3 -I -c "$sweep" "$$" 2>&1)"; then
        note "cleanup=sweep-failed path=$fence_dir sweep-error=$(why "$error")"
        swept=false
      fi ;;
    *) invariant "world=$world" ;;
  esac
  for path in "$fence_dir"/tmp/vgshell-smoke.*/evidence/destination; do
    [[ ! -f $path ]] || python3 "${self%/*}/evidence.py" "$fence_dir" "${path%/evidence/destination}" "${output_roots[@]}" || true
  done
  if ! error="$(chmod -R u+rwX -- "$fence_dir" 2>&1)"; then
    note "cleanup=chmod-failed path=$fence_dir chmod-error=$(why "$error")"
  fi
  if [[ $keep == true ]]; then
    note "kept root=$fence_dir"
  elif [[ $swept == false ]]; then
    # A process the sweep could not end may still write under the root, so
    # it takes kind k, a kept root, which no reaper removes (reap.sh). The
    # mktemp suffix holds no '-', so the last "-r." is the kind's.
    kept_dir="${fence_dir%-r.*}-k.${fence_dir##*-r.}"
    error=""
    if [[ ! -e $kept_dir && ! -L $kept_dir ]] && error="$(mv -T -- "$fence_dir" "$kept_dir" 2>&1)"; then
      note "kept root=$kept_dir"
    else
      note "cleanup=rename-failed path=$fence_dir rename-error=$(why "${error:-target-exists}")"
    fi
  elif ! error="$(rm -rf -- "${fence_dir:?}" 2>&1)"; then
    note "cleanup=rm-failed path=$fence_dir rm-error=$(why "$error")"
  fi
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
  line="$(data_limit)" || { fault limits-unreadable "path=/proc/$$/limits"; exit 77; }
  note "ceiling=data limit=${line%% *}"
  # The proof's env has given back the stops bubblewrap's monitor ignores;
  # from here a stop forward hands this process ends it or reaches CMD.
  : >"$VGSHELL_WORLD_ROOT/stops-restored"
  exec "$@"
}

# ours PID: true while PID is the fence's child. The fence reaps the
# monitor only in its own wait and starts no other child after it, so a
# pid whose parent reads as the fence is still the monitor. In a throwaway
# world the monitor is CMD, and the orphans of its tree become the fence's
# children too; none of them can hold CMD's pid until the fence reaps CMD.
ours() {
  local stat=()
  read -r -a stat 2>/dev/null <"/proc/$1/stat" && [[ ${stat[3]-} == "$$" ]]
}

# stop_session SIGNAL PID: send SIGNAL to each process group of PID's
# session that PID or a descendant of it is in, PID's own first. A
# foreground command can lead a group of its own in that session, as GNU
# timeout makes for itself and its command unless given --foreground
# (coreutils timeout.c: setpgid (0, 0)), and the world bounds its IPC,
# hyprctl, grim and leak-input calls that way (harness.sh, hypr-call.sh,
# shot.sh, leaks.sh). A process in a session of its own, as spawn and a
# row's output filter make them (harness.sh), is left out with all it
# started, since a process joins only a group of its own session
# (setpgid(2)).
stop_session() {
  local session="" pid line task fields=() children=() queue=("$2")
  local -A seen=() sent=()
  while ((${#queue[@]})); do
    pid=${queue[0]}
    queue=("${queue[@]:1}")
    [[ -z ${seen[$pid]-} ]] || continue
    seen[$pid]=1
    line=""
    read -r line 2>/dev/null <"/proc/$pid/stat" || true
    # Fields 5 and 6 of stat (proc(5)), the process group and the session,
    # counted from the last ") " as in proc_start (reap.sh). A process that has ended
    # has none, and nothing below it is left to signal.
    read -r -a fields <<<"${line##*) }"
    [[ ${fields[2]-} =~ ^[1-9][0-9]*$ && ${fields[3]-} =~ ^[1-9][0-9]*$ ]] || continue
    [[ -n $session ]] || session=${fields[3]}
    [[ ${fields[3]} == "$session" ]] || continue
    if [[ -z ${sent[${fields[2]}]-} ]]; then
      sent[${fields[2]}]=1
      kill -s "$1" -- "-${fields[2]}" 2>/dev/null || true
    fi
    for task in "/proc/$pid/task/"*/children; do
      children=()
      read -r -a children 2>/dev/null <"$task" || true
      queue+=("${children[@]}")
    done
  done
}

# forward SIGNAL STATUS: hand the first SIGNAL of its kind to CMD, the one
# child of the namespace's init, which is the monitor's one child, and to
# its foreground command (stop_session), and drop a repeat of that kind,
# so CMD's exit handling gets each kind once. CMD's group is the init's:
# bubblewrap 0.13.1's init calls setsid and CMD inherits its group (read
# in a namespace on 2026-11-11: CMD pid=2 pgrp=1), and the init ignores
# the stops. The foreground command gets the signal with CMD, as a
# terminal's job does, so a CMD whose trap Bash runs only once that
# command ends acts on it at once. A command Bash starts after it has taken
# the signal gets none, and its trap waits for that command. A
# signal can run this again inside a run of it, so the count is read and
# raised in one command. Before the monitor starts nothing has, and the
# fence exits with STATUS. Until the proof has given the stops back
# (stops-restored in the root), every process the monitor has started
# ignores SIGNAL and no part of CMD needs its exit, so the fence ends the
# world (end_world) and exits with STATUS. In a throwaway world the fence
# started CMD itself, with no monitor, no init and no ignored stops, so
# SIGNAL goes to CMD and its foreground command at once.
stop_status=""
declare -A forwarded=()
forward() {
  ((forwarded[$1]++ == 0)) || return 0
  local monitor="${!:-}" init="" child=""
  # The EXIT trap's release must not be cut short by another kind.
  [[ -n $monitor ]] || { trap '' TERM INT HUP; exit "$2"; }
  ours "$monitor" || return 0
  case "$world" in
    bwrap)
      if [[ -e $fence_dir/stops-restored ]]; then
        read -r init _ 2>/dev/null <"/proc/$monitor/task/$monitor/children" || true
        [[ -z $init ]] || read -r child _ 2>/dev/null <"/proc/$init/task/$init/children" || true
        [[ -z $child ]] || stop_session "$1" "$child"
      else
        stop_status=$2
        end_world "$monitor"
      fi ;;
    throwaway) stop_session "$1" "$monitor" ;;
    *) invariant "world=$world" ;;
  esac
}

# end_world MONITOR: KILL the namespace's init and then MONITOR, and wait
# for the namespace to end. The init sets no parent-death signal until its
# own setup has forked CMD (bubblewrap 0.13.1, do_init) and leaves the
# monitor's process group at its setsid, so MONITOR's death alone can leave
# it running; a KILL from this, its parent namespace, ends it and every
# process in it (pid_namespaces(7)). MONITOR is stopped first, so it starts
# no init after its children are read.
end_world() {
  local line state="" tick init ns
  local -a inits=() spaces=()
  kill -s STOP -- "$1" 2>/dev/null || true
  # A real wait on the state the kernel reports; a stop takes effect at
  # the monitor's next return from the kernel.
  for ((tick = 0; tick < 100; tick++)); do
    read -r line 2>/dev/null <"/proc/$1/stat" || break
    line="${line##*) }"
    state="${line%% *}"
    [[ $state != [TtZX] ]] || break
    sleep 0.01
  done
  read -r -a inits 2>/dev/null <"/proc/$1/task/$1/children" || true
  for init in "${inits[@]}"; do
    ns="$(readlink -- "/proc/$init/ns/pid" 2>/dev/null)" && spaces+=("$init $ns")
    kill -s KILL -- "$init" 2>/dev/null || true
  done
  kill -s KILL -- "$1" 2>/dev/null || true
  # A real wait: the kernel ends a namespace within milliseconds.
  for line in "${spaces[@]}"; do
    for ((tick = 0; tick < 100; tick++)); do
      [[ "$(readlink -- "/proc/${line%% *}/ns/pid" 2>/dev/null)" == "${line#* }" ]] || break
      sleep 0.05
    done
  done
}

case "$mode" in
  check)
    plan
    world_kind
    case "$world" in
      bwrap)
        if exposed || ! fenced; then exit 1; fi ;;
      throwaway)
        [[ $inherited_world == true && -w $VGSHELL_WORLD_ROOT ]] || exit 1 ;;
      *) invariant "world=$world" ;;
    esac
    exit 0 ;;
  inside)
    inside "$@" ;;
  run)
    (($#)) || { note "refused: argument=missing-command"; exit 2; }
    ceiling="${VGS_VALIDATE_ROW_MEMORY:-17179869184}"
    # At most 18 digits, so bash's 64-bit arithmetic below cannot overflow.
    [[ $ceiling =~ ^[1-9][0-9]{0,17}$ ]] || { note "refused: row-memory=$(why "$ceiling")"; exit 2; }
    plan
    world_kind
    case "$world" in
      bwrap)
        if [[ $fresh == false ]]; then ! fenced || exposed || exec "$@"; fi
        command -v bwrap >/dev/null 2>&1 || { fault bwrap-missing; exit 77; } ;;
      throwaway)
        # An inherited throwaway world is reused as an inherited namespace
        # is: its fence already owns every descendant.
        [[ $fresh == true || $inherited_world == false ]] || exec "$@"
        if [[ -z $subreaper ]]; then
          # A python3 that is missing or cannot start, or has no ctypes,
          # would end this process with its own status in CMD's place.
          python3 -I -c 'import ctypes' >/dev/null 2>&1 || { fault subreaper-failed python3=unusable; exit 77; }
          # SigIgn in /proc/<pid>/status (proc(5)): the signals this process
          # ignores, as the caller left them.
          ignored=""
          { while read -r key value; do [[ $key != SigIgn: ]] || ignored="$value"; done <"/proc/$$/status"; } 2>/dev/null || true
          [[ $ignored =~ ^[0-9a-f]+$ ]] || { fault subreaper-failed "path=/proc/$$/status"; exit 77; }
          exec python3 -I -c "$become_subreaper" "$BASH" "$self" "$ignored" "${fence_argv[@]}"
        fi
        case "$subreaper" in
          0) ;;
          unusable) fault subreaper-failed python3=unusable; exit 77 ;;
          *) fault subreaper-failed "errno=$subreaper"; exit 77 ;;
        esac ;;
      *) invariant "world=$world" ;;
    esac
    world_start="$(proc_start "$$")" || { fault owner-record-unreadable "path=/proc/$$/stat"; exit 77; }
    world_ns="$(pid_namespace "$$")" || { fault owner-record-unreadable "path=/proc/$$/ns/pid"; exit 77; }
    inherited="$(data_limit)" || { fault limits-unreadable "path=/proc/$$/limits"; exit 77; }
    for limit in $inherited; do
      [[ $limit == unlimited ]] || ((limit >= ceiling)) || ceiling=$limit
    done
    reap_orphans gpu-fence vgshell-world. "$world_ns" '^[A-Za-z0-9]{6}$'
    kind=r
    [[ $keep == false ]] || kind=k
    fence_dir="$(mktemp -d "${TMPDIR:-/tmp}/vgshell-world.$$-$world_start-$world_ns-$kind.XXXXXX")" || { fault root-failed; exit 77; }
    [[ -d $fence_dir && ! -L $fence_dir ]] || { fault root-failed; exit 77; }
    fence_dir="$(realpath -e -- "$fence_dir")" || { fault root-failed; exit 77; }
    trap release EXIT
    mkdir -p -- "$fence_dir"/{home,config,data,state,cache,tmp,runtime}
    chmod 700 -- "$fence_dir" "$fence_dir/runtime"
    root_mounts=()
    # D113: bubblewrap's empty root admits /nix even when the host lacks it.
    # A top-level host entry created after this enumeration stays invisible.
    for host_entry in /* /.[!.]* /..?*; do
      [[ -e $host_entry || -L $host_entry ]] || continue
      [[ $host_entry != /nix || -z $nix_store ]] || continue
      if [[ -L $host_entry ]]; then
        root_mounts+=(--symlink "$(readlink -- "$host_entry")" "$host_entry")
      else
        root_mounts+=(--ro-bind "$host_entry" "$host_entry")
      fi
    done
    if [[ -n $nix_store ]]; then
      mkdir -- "$fence_dir/nix"
      cp -a --reflink=auto -- "$nix_store/." "$fence_dir/nix/"
      root_mounts+=(--bind "$fence_dir/nix" /nix)
    fi
    # Version-manager shims need the caller's trust state. Resolve the
    # native node before HOME is redirected, as the harness requires. PATH
    # leads with a directory that holds that node alone: the directory it
    # was installed to can hold other commands, such as an installed qs,
    # that would shadow the caller's own.
    if command -v node >/dev/null 2>&1; then
      world_node="$(node -e 'process.stdout.write(process.execPath)')" || { note 'refused: node=binary-unavailable'; exit 2; }
      mkdir -- "$fence_dir/node"
      ln -s -- "$world_node" "$fence_dir/node/node"
      export PATH="$fence_dir/node:$PATH"
    fi
    # These are the complete environment tables. Graphics/session variables
    # never enter either table. Prepared selftest values hold paths or account
    # references, never credentials; the runner computes them before entry.
    # A throwaway world has no private tmpfs at the runtime path, so it
    # gives the bwrap world's layout under the root: a 0700 directory whose
    # `owned` is the root's runtime. The harness makes its runtime there
    # (harness.sh: mktemp -d "$XDG_RUNTIME_DIR/owned/vs.XXXXXX") and records
    # its backing as <root>/runtime/<name>, which evidence.py reads.
    case "$world" in
      bwrap) runtime_dir="$world_runtime" ;;
      throwaway)
        runtime_dir="$fence_dir/xdg"
        mkdir -m 700 -- "$runtime_dir"
        ln -s -- "$fence_dir/runtime" "$runtime_dir/owned" ;;
      *) invariant "world=$world" ;;
    esac
    environment=(--clearenv
      --setenv HOME "$fence_dir/home" --setenv XDG_CONFIG_HOME "$fence_dir/config"
      --setenv XDG_DATA_HOME "$fence_dir/data" --setenv XDG_STATE_HOME "$fence_dir/state"
      --setenv XDG_CACHE_HOME "$fence_dir/cache" --setenv TMPDIR "$fence_dir/tmp"
      --setenv XDG_RUNTIME_DIR "$runtime_dir" --setenv VGSHELL_WORLD_ROOT "$fence_dir"
      --setenv VGS_TEST_RUN 1)
    passed=(PATH USER LOGNAME LANG LC_ALL TERM QML_UNIT_RUNNER
      VGSHELL_SMOKE_DEFAULT_FIRST_BAR_BUDGET_MS
      VGSHELL_SMOKE_EMOJI_TOAST_BUDGET_MS VGSHELL_SMOKE_EMOJI_INBOX_BUDGET_MS
      JARVIS_LOCAL_MODELS JARVIS_LOCAL_PYTHON VOXTYPE_MODELS
      VGSHELL_SELFTEST_ACCOUNTS VGSHELL_SELFTEST_PROGRAM VGSHELL_SHOTS_SOURCE AGENT_RUNTIME_CACHE)
    # AGENT_RUNTIME_CACHE passes only where it names a declared --input,
    # the kendex runtime cache its caller prepared before entry. A cache the
    # caller's environment names for itself, as an orch lane's does, stays
    # out of the world.
    input_declared() { # PATH
      local wanted input
      wanted="$(realpath -e -- "$1" 2>/dev/null)" || return 1
      for input in "${inputs[@]}"; do
        [[ $(realpath -e -- "$input" 2>/dev/null) != "$wanted" ]] || return 0
      done
      return 1
    }
    for name in "${passed[@]}"; do
      [[ -v $name ]] || continue
      [[ $name != AGENT_RUNTIME_CACHE ]] || input_declared "${!name}" || continue
      environment+=(--setenv "$name" "${!name}")
    done
    mounts=()
    parent_mounts=()
    # A suite inside a world may make a disposable checkout under its root
    # and enter a child world. Keep those input fixtures visible after /tmp
    # is masked, with only the child root writable.
    if fenced /; then
      parent_mounts+=(--ro-bind "$VGSHELL_WORLD_ROOT" "$VGSHELL_WORLD_ROOT")
    fi
    # Mask caller runtime even when its path is outside /tmp. No source from
    # it is mounted back, except the filtered selftest proxy socket below.
    if [[ -n ${XDG_RUNTIME_DIR:-} && $XDG_RUNTIME_DIR != /tmp && $XDG_RUNTIME_DIR != /tmp/* ]]; then
      mounts+=(--perms 0700 --tmpfs "$XDG_RUNTIME_DIR")
    fi
    skipped_service_masks=()
    for service_path in /run/dbus /run/tailscale; do
      # An absent service path exposes no socket. Creating its mask would
      # require a write below the world's read-only /run.
      if [[ -e $service_path ]]; then
        mounts+=(--tmpfs "$service_path")
      else
        skipped_service_masks+=("$service_path")
      fi
    done
    git_dir="$(git -C "$checkout" rev-parse --absolute-git-dir 2>/dev/null)" || git_dir="$checkout/.git"
    for input in "${inputs[@]}"; do
      input="$(realpath -e -- "$input")" && [[ -d $input ]] || { note 'refused: input=unreadable'; exit 2; }
      mounts+=(--ro-bind "$input" "$input")
    done
    for output in "${outputs[@]}"; do
      output="$(realpath -m -- "$output")" || { note "refused: output=$output reason=resolve-failed"; exit 2; }
      for protected in "$checkout" "$git_dir" "${HOME:-/}" /tmp /dev /run/dbus /run/tailscale "${XDG_RUNTIME_DIR:-$world_runtime}"; do
        protected="$(realpath -m -- "$protected")" || { note "refused: protected=$protected reason=resolve-failed"; exit 2; }
        if [[ $protected == "$output" || $protected == "$output/"* || $output == / ]]; then
          note "refused: output=$output protected=$protected"; exit 2
        fi
      done
      mkdir -p -- "$output"
      mounts+=(--bind "$output" "$output")
      output_roots+=("$output")
    done
    if [[ -n $sign_in_name ]]; then
      mounts+=(--bind "$sign_in_dir" "$sign_in_dir")
      environment+=(--setenv "$sign_in_name" "$sign_in_dir")
    fi
    if [[ $secrets == true ]]; then
      command -v xdg-dbus-proxy >/dev/null && [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || { note 'refused: selftest=bus-unavailable'; exit 2; }
      # libsecret 0.21.8 lookup's four read calls, measured with
      # xdg-dbus-proxy 0.1.9 on a scratch bus on 2026-10-09.
      selftest_secrets_rules=(
        --call=org.freedesktop.secrets=org.freedesktop.Secret.Service.SearchItems@/org/freedesktop/secrets
        --call=org.freedesktop.secrets=org.freedesktop.Secret.Service.OpenSession@/org/freedesktop/secrets
        --call=org.freedesktop.secrets=org.freedesktop.Secret.Service.GetSecrets@/org/freedesktop/secrets
        --call=org.freedesktop.secrets=org.freedesktop.DBus.Properties.GetAll@/org/freedesktop/secrets)
      copilot_rules=()
      if [[ $sign_in_name == COPILOT_HOME ]]; then
        # Copilot 1.0.91 / secret-service 5.2.0 reads Item.get_secret and
        # ensure_unlocked with property caching disabled.
        copilot_rules=(
          '--call=org.freedesktop.secrets=org.freedesktop.Secret.Item.GetSecret@/org/freedesktop/secrets/collection/*'
          '--call=org.freedesktop.secrets=org.freedesktop.DBus.Properties.Get@/org/freedesktop/secrets/collection/*')
      fi
      # xdg-dbus-proxy 0.1.9 dbus-proxy.c writes readiness to --fd and
      # exits on its pipe's ERR/HUP. Bash's coprocess descriptors do not
      # enter child executions, so only this owner holds the read end.
      coproc world_proxy {
        exec env -i "$(command -v xdg-dbus-proxy)" --fd=1 "$DBUS_SESSION_BUS_ADDRESS" "$fence_dir/secrets-bus" --filter "${selftest_secrets_rules[@]}" "${copilot_rules[@]}" 2>"$fence_dir/proxy.log"
      }
      proxy_pid=$world_proxy_PID
      proxy_read=${world_proxy[0]}
      proxy_input=${world_proxy[1]}
      exec {proxy_input}>&-
      if ! read -r -N 1 -t 5 proxy_ready <&"$proxy_read" || [[ $proxy_ready != x ]]; then
        note 'refused: selftest=proxy-not-started'; exit 2
      fi
      mounts+=(--ro-bind "$fence_dir/secrets-bus" "$world_runtime/secrets-bus")
    fi
    # With no AMD node nothing under /dev changes, and nothing is proved.
    if ((${#hidden[@]} == 0)); then rebuild=(); kept=(); fi
    case "$world" in
      bwrap)
        # CMD gets a session of its own: in the caller's session, with the
        # monitor's group in the background, a terminal would stop it on a read
        # or a mode change.
        # bubblewrap --help: ro-bind is nodev; dev-bind restores device access.
        # The private runtime's child uses root-owned backing storage so the
        # after-namespace copier can still read logs after tmpfs disappears.
        # bubblewrap's monitor ignores the signals the fence forwards. A unit's
        # stop (systemd.kill(5), KillMode=control-group) TERMs every process of
        # the unit, the monitor too, and bubblewrap 0.13.1 sets no handler: the
        # monitor would die, and --die-with-parent would kill the namespace
        # before CMD's exit trap ends. The disposition is inherited through
        # bubblewrap's exec, so the proof puts it back before CMD starts.
        fence=(env --ignore-signal=TERM,INT,HUP bwrap "${root_mounts[@]}" --dev-bind /dev /dev
          --tmpfs /dev/shm --tmpfs /tmp --perms 0700 --tmpfs "$world_runtime"
          "${parent_mounts[@]}" --bind "$fence_dir" "$fence_dir"
          --bind "$fence_dir/runtime" "$world_runtime/owned"
          "${mounts[@]}" "${rebuild[@]}" "${network[@]}" --unshare-pid --proc /proc --die-with-parent --new-session
          "${environment[@]}" --remount-ro /) ;;
      throwaway)
        # The same table, as env -i assignments: bubblewrap's words are
        # --clearenv, then --setenv NAME VALUE for each name.
        fence=(env -i)
        for ((slot = 1; slot < ${#environment[@]}; slot += 3)); do
          [[ ${environment[slot]} == --setenv ]] || invariant "environment=${environment[slot]}"
          fence+=("${environment[slot + 1]}=${environment[slot + 2]}")
        done ;;
      *) invariant "world=$world" ;;
    esac
    # prlimit sets the ceiling and the core limit on itself and execs the
    # rest, so bubblewrap and all it starts inherit both, and the monitor
    # keeps the pid the fence started.
    fence=(prlimit "--data=$ceiling:$ceiling" --core=0 -- "${fence[@]}")
    proof=(-- env --default-signal=TERM,INT,HUP "$BASH" "$self" --inside "${hidden[@]}" -- "${kept[@]}" --)
    case "$world" in
      bwrap)
        status=0
        probe="$(
          # Bash keeps coprocess descriptors in command substitutions alone.
          [[ -z ${proxy_read:-} ]] || exec {proxy_read}<&-
          "${fence[@]}" "${proof[@]}" true 2>&1
        )" || status=$?
        case "$status" in
          0) ;;
          # The proof inside the probe named its own reason.
          77) printf '%s\n' "$probe" >&2; exit 77 ;;
          *) fault namespace-failed "exit=$status"; printf '%s\n' "$probe" >&2; exit 77 ;;
        esac
        # The probe's proof wrote it; the run's own proof writes it again.
        rm -f -- "$fence_dir/stops-restored"
        if ((${#skipped_service_masks[@]})); then
          skipped_service_names="$(IFS=,; printf '%s' "${skipped_service_masks[*]}")"
          note "service-masks skipped=$skipped_service_names"
        fi ;;
      throwaway)
        # No namespace to prove: the refusals stopped a host with an amdgpu
        # node, so plan hid nothing. The marker is what a nested call
        # inherits this world by (throwaway_parent).
        note "world=throwaway"
        : >"$fence_dir/throwaway" ;;
      *) invariant "world=$world" ;;
    esac
    # bubblewrap's monitor forwards no signal, so the fence stays its parent.
    # The monitor gets a process group of its own: `set -m` makes it in
    # parent and child before `&` returns. A signal to the caller's group
    # then reaches the fence alone, a terminal's stop included. Without job
    # control bash would start the monitor with INT and QUIT ignored, and
    # CMD would inherit QUIT ignored. In a throwaway world the monitor is
    # CMD itself.
    trap 'forward TERM 143' TERM
    trap 'forward INT 130' INT
    trap 'forward HUP 129' HUP
    set -m
    case "$world" in
      bwrap) "${fence[@]}" --info-fd 3 "${proof[@]}" "$@" 3>"$fence_dir/info" & ;;
      # The proof's first word ends bubblewrap's options. With no path to
      # check it reads back the ceiling and execs CMD, so every exec keeps
      # the pid the fence started.
      throwaway) "${fence[@]}" "${proof[@]:1}" "$@" & ;;
      *) invariant "world=$world" ;;
    esac
    set +m
    monitor=$!
    case "$world" in
      bwrap) ;;
      # bubblewrap writes info through --info-fd. Here the fence writes its
      # two fields: CMD, which the no-progress stop KILLs
      # (qml_smoke_end_world), and the host's PID namespace it runs in.
      throwaway) printf '{\n    "child-pid": %s,\n    "pid-namespace": %s\n}\n' "$monitor" "$world_ns" >"$fence_dir/info" ;;
      *) invariant "world=$world" ;;
    esac
    # A trapped signal ends a wait early, and so can one that comes while
    # the trap runs. The shell keeps the monitor's status for the last wait.
    while ours "$monitor"; do
      wait "$monitor" || true
    done
    status=0
    wait "$monitor" || status=$?
    [[ -z $stop_status ]] || status=$stop_status
    exit "$status" ;;
esac
