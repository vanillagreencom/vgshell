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
#
# The world exclusively creates VGSHELL_WORLD_ROOT under the caller TMPDIR.
# Every temporary tree lives there. After the PID namespace ends, this
# process alone retains row evidence, restores owner write bits and removes
# that root. --keep keeps it and prints its path. SIGKILL of this process
# ends the namespace but leaves the root.
#
# --out DIR declares a writable output directory. A directory which is or
# contains the checkout, its git directory or the caller HOME is refused.
# --secrets starts the selftest's filtered bus outside the namespace and
# binds only its socket inside. --sign-in VARIABLE DIR declares the selected
# account directory, its variable and its writable bind. Neither exception
# supplies the caller's raw bus. The rules below own the allowed bus calls.
# --fresh gives a validate row its own root even when validate itself is
# inside a test world. Other entry points reuse the world they already have.
#
# The fence remains bubblewrap's parent. TERM, INT and HUP each go to CMD
# once. The PID namespace and --die-with-parent end every descendant after
# CMD ends, including children in other sessions and stopped children.
# Its /proc exposes no outside process or descriptor.
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
# --check reads access permissions and mounts: the checkout must be read-only,
# the owned root writable and every AMD path absent. It never writes.
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
# never a run outside the namespace; the first line on stderr names why:
#   gpu-fence: status=not-measured reason=bwrap-missing
#   gpu-fence: status=not-measured reason=root-failed
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
    root-failed) note "  the world could not make its owned run root" ;;
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
world_runtime=/tmp/vr
self="$(readlink -f -- "${BASH_SOURCE[0]}")"
checkout="$(cd -- "${self%/*}/../.." && pwd -P)"
outputs=()
output_roots=()
keep=false
fresh=false
network=(--unshare-net)
secrets=false
sign_in_name="" sign_in_dir=""
while (($#)); do
  case "$1" in
    --out|--checkout|--sign-in)
      [[ $# -ge 2 && -n $2 ]] || { note "refused: argument=$1"; exit 2; }
      case "$1" in
        --out) outputs+=("$2"); shift 2 ;;
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

# Wait for the namespace's init to leave before reading evidence or removing
# the one root this process acquired. PID 1 exits after the kernel reaps
# every other process in its namespace.
release() {
  local init="" ns="" path _
  [[ -n ${fence_dir-} ]] || return 0
  if [[ -n ${proxy_pid:-} ]]; then
    exec {proxy_read}<&-
    wait "$proxy_pid" 2>/dev/null || true
  fi
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
  for path in "$fence_dir"/tmp/vgshell-smoke.*/evidence/destination; do
    [[ ! -f $path ]] || python3 "${self%/*}/evidence.py" "$fence_dir" "${path%/evidence/destination}" "${output_roots[@]}" || true
  done
  chmod -R u+rwX -- "$fence_dir" 2>/dev/null || note "cleanup=chmod-failed path=$fence_dir"
  if [[ $keep == true ]]; then
    note "kept root=$fence_dir"
  else
    rm -rf -- "${fence_dir:?}" 2>/dev/null || note "cleanup=rm-failed path=$fence_dir"
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
  exec "$@"
}

# ours PID: true while PID is the fence's child. The fence reaps the
# monitor only in its own wait and starts no other child after it, so a
# pid whose parent reads as the fence is still the monitor.
ours() {
  local stat=()
  read -r -a stat 2>/dev/null <"/proc/$1/stat" && [[ ${stat[3]-} == "$$" ]]
}

# forward SIGNAL STATUS: hand the first SIGNAL of its kind to CMD, the one
# child of the namespace's init, which is the monitor's one child, and drop
# a repeat of that kind, so CMD's exit handling gets each kind once. A
# signal can run this again inside a run of it, so the count is read and
# raised in one command. Before the monitor starts nothing has, and the fence exits with
# STATUS. Before CMD has started, the monitor's group holds what has.
declare -A forwarded=()
forward() {
  ((forwarded[$1]++ == 0)) || return 0
  local monitor="${!:-}" init="" child=""
  # The EXIT trap's release must not be cut short by another kind.
  [[ -n $monitor ]] || { trap '' TERM INT HUP; exit "$2"; }
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
    if [[ $fresh == false ]]; then ! fenced || exposed || exec "$@"; fi
    command -v bwrap >/dev/null 2>&1 || { fault bwrap-missing; exit 77; }
    fence_dir="$(mktemp -d "${TMPDIR:-/tmp}/vgshell-world.XXXXXX")" || { fault root-failed; exit 77; }
    [[ -d $fence_dir && ! -L $fence_dir ]] || { fault root-failed; exit 77; }
    fence_dir="$(realpath -e -- "$fence_dir")" || { fault root-failed; exit 77; }
    trap release EXIT
    mkdir -p -- "$fence_dir"/{home,config,data,state,cache,tmp,runtime}
    chmod 700 -- "$fence_dir" "$fence_dir/runtime"
    # Version-manager shims need the caller's trust state. Resolve the
    # native node before HOME is redirected, as the harness requires.
    if command -v node >/dev/null 2>&1; then
      world_node="$(node -e 'process.stdout.write(process.execPath)')" || { note 'refused: node=binary-unavailable'; exit 2; }
      export PATH="${world_node%/*}:$PATH"
    fi
    # These are the complete environment tables. Graphics/session variables
    # never enter either table. Prepared selftest values hold paths or account
    # references, never credentials; the runner computes them before entry.
    environment=(--clearenv
      --setenv HOME "$fence_dir/home" --setenv XDG_CONFIG_HOME "$fence_dir/config"
      --setenv XDG_DATA_HOME "$fence_dir/data" --setenv XDG_STATE_HOME "$fence_dir/state"
      --setenv XDG_CACHE_HOME "$fence_dir/cache" --setenv TMPDIR "$fence_dir/tmp"
      --setenv XDG_RUNTIME_DIR "$world_runtime" --setenv VGSHELL_WORLD_ROOT "$fence_dir"
      --setenv VGS_TEST_RUN 1)
    passed=(PATH USER LOGNAME LANG LC_ALL TERM QML_UNIT_RUNNER
      VGSHELL_SMOKE_RSS_CEILING_KIB VGSHELL_SMOKE_FIRST_BAR_BUDGET_MS
      VGSHELL_SMOKE_DEFAULT_FIRST_BAR_BUDGET_MS VGSHELL_SMOKE_RECONCILE_BUDGET_MS
      VGSHELL_SMOKE_EMOJI_TOAST_BUDGET_MS VGSHELL_SMOKE_EMOJI_INBOX_BUDGET_MS
      JARVIS_LOCAL_MODELS JARVIS_LOCAL_PYTHON VOXTYPE_MODELS
      VGSHELL_SELFTEST_ACCOUNTS VGSHELL_SELFTEST_PROGRAM VGSHELL_SHOTS_SOURCE)
    for name in "${passed[@]}"; do
      [[ ! -v $name ]] || environment+=(--setenv "$name" "${!name}")
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
    # CMD gets a session of its own: in the caller's session, with the
    # monitor's group in the background, a terminal would stop it on a read
    # or a mode change.
    # bubblewrap --help: ro-bind is nodev; dev-bind restores device access.
    # The private runtime's child uses root-owned backing storage so the
    # after-namespace copier can still read logs after tmpfs disappears.
    fence=(bwrap --ro-bind / / --dev-bind /dev /dev
      --tmpfs /dev/shm --tmpfs /tmp --perms 0700 --tmpfs "$world_runtime"
      "${parent_mounts[@]}" --bind "$fence_dir" "$fence_dir"
      --bind "$fence_dir/runtime" "$world_runtime/owned"
      "${mounts[@]}" "${rebuild[@]}" "${network[@]}" --unshare-pid --proc /proc --die-with-parent --new-session
      "${environment[@]}")
    proof=(-- "$BASH" "$self" --inside "${hidden[@]}" -- "${kept[@]}" --)
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
    if ((${#skipped_service_masks[@]})); then
      skipped_service_names="$(IFS=,; printf '%s' "${skipped_service_masks[*]}")"
      note "service-masks skipped=$skipped_service_names"
    fi
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
