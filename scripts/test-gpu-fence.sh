#!/usr/bin/env bash
# Drive scripts/smoke/gpu-fence.sh over trees of ordinary files: a sysfs
# tree that names each node's driver, and a device tree that holds a file
# for each node and the links to it. No case reads /sys/class/drm or
# /dev/dri, and none opens a device node. The namespace cases make a real
# bubblewrap namespace over the device tree; the refusal cases put a
# stand-in bwrap, or none, on PATH. In the trees the amdgpu nodes are card1
# and renderD128, so a fence that went by a fixed number hides the wrong
# ones.
#
# Each case pins the exit status and the keyed lines the fence's header
# promises. The proof lines are pinned whole: the orchestrator reads them
# as the evidence that a run was restricted.
#
# The stop cases send TERM, INT or HUP to a fence whose command has an exit
# trap that takes a second. The command must get the signal once, and its
# trap must have ended when the fence returns. The carry case sends INT
# while the command waits on a foreground command that exits 0, which bash
# carries on from, then TERM, which must end the run. The terminal case
# runs the fence from a real terminal, where a command that changes the
# terminal's mode or reads it must not stop. A SIGKILL of the fence must end every
# process its command started, one in another session and one stopped
# included. The cases that can leave a process run in a PID namespace of
# their own that util-linux unshare makes, whose end ends what a defect
# leaves.
#
# The controls plant one defect per rule in a copy of the fence and
# require the case that rule owns to go red. The first is the fence with
# no restriction: its namespace covers nothing, and the proof inside
# reports every amdgpu path it still sees, by stat, and starts nothing. A
# control whose label no case carries is a failure, never a pass: a planted
# one must turn the controls loop red.
#
# The wiring cases run a copy of each entry point beside a stand-in fence.
# Each must hand its own path and arguments to the fence before it makes
# anything, and go on by itself where the fence's check passes. A copy of
# the harness, cut after its check, must stop where the check fails, having
# started none of its tools but pkg-config, which its prerequisite check
# asks first. The stand-ins for the harness's tools are the list the
# harness itself prints with nothing on PATH.
#
# Exit 0 when every case and control holds, 1 otherwise, 77 when
# bubblewrap cannot make a namespace here, since the namespace cases then
# measured nothing:
#   test-gpu-fence: status=not-measured missing=bwrap-namespace
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
fence="$repo/scripts/smoke/gpu-fence.sh"

TMP_ROOT="$(mktemp -d)" || { echo "test-gpu-fence: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $TMP_ROOT && ! -L $TMP_ROOT ]] || { echo "test-gpu-fence: scratch=not-a-directory value=[$TMP_ROOT]" >&2; exit 1; }
TMP_ROOT="$(cd -- "$TMP_ROOT" && pwd -P)" || { echo "test-gpu-fence: scratch=resolve-failed" >&2; exit 1; }
trap 'rm -rf -- "${TMP_ROOT:?}"' EXIT
failures=0
unmeasured=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

# Three PATH directories, each holding the tools the fence and the cases
# run and nothing else: `none` has no bwrap, `broken` a stand-in that
# records its call and fails, `real` the host's bubblewrap.
mkdir -p "$TMP_ROOT/bin-none" "$TMP_ROOT/bin-broken" "$TMP_ROOT/bin-real" "$TMP_ROOT/cwd" "$TMP_ROOT/empty"
for tool in chmod mktemp readlink realpath rm sed seq setsid stat sh sleep stty touch true; do
  tool_path="$(type -P "$tool")" || { echo "test-gpu-fence: missing=$tool" >&2; exit 1; }
  for bin in none broken real; do ln -s -- "$tool_path" "$TMP_ROOT/bin-$bin/$tool"; done
done
printf '#!/bin/sh\n: >"%s"\necho "bwrap: stand-in makes no namespace" >&2\nexit 1\n' "$TMP_ROOT/bwrap-called" >"$TMP_ROOT/bin-broken/bwrap"
chmod +x "$TMP_ROOT/bin-broken/bwrap"
# The terminal case runs the fence under script(1), which makes a real
# terminal, inside a time limit.
for tool in script timeout python3; do
  type -P "$tool" >/dev/null || { echo "test-gpu-fence: missing=$tool" >&2; exit 1; }
done
# contain: the case's own PID namespace. --kill-child ends its PID 1 when
# unshare ends, and the kernel then ends every process in it. unshare
# blocks TERM and INT while it waits, so a time limit over it ends it with
# KILL after its grace.
contain=(unshare --user --map-current-user --pid --fork --kill-child --mount-proc)
namespace=false
if real_bwrap="$(type -P bwrap)" && "$real_bwrap" --dev-bind / / --unshare-pid --proc /proc true 2>/dev/null &&
   "${contain[@]}" true 2>/dev/null; then
  namespace=true
  ln -s -- "$real_bwrap" "$TMP_ROOT/bin-real/bwrap"
fi
own_pidns="$(readlink /proc/self/ns/pid)" || { echo "test-gpu-fence: pidns=unreadable" >&2; exit 1; }
: >"$TMP_ROOT/ledger"

# The paths of the device tree, by what the namespace must do with each.
amd_paths=(dri/card1 char/226:1 dri/renderD128 char/226:128
  dri/by-path/alias dri/by-path/pci-0000:79:00.0-card dri/by-path/pci-0000:79:00.0-render)
other_paths=(dri/card0 dri/renderD129 dri/by-path/pci-0000:01:00.0-card dri/by-path/pci-0000:01:00.0-render
  char/226:0 char/226:129)

# world DIR: card1 and renderD128 under amdgpu, card0 under nvidia and
# renderD129 with no driver link, a connector and the version file, which
# carry no device number, and under dev a file per node, the by-path and
# char links, a link to a link, and one link to a device that is no DRM node.
world() {
  local dir="$1" drm="$1/sys/class/drm" node name major minor driver number
  mkdir -p "$drm/card1-DP-1" "$dir/dev/dri/by-path" "$dir/dev/char"
  echo 1.1.0 >"$drm/version"
  for node in card0:226:0:nvidia card1:226:1:amdgpu renderD128:226:128:amdgpu renderD129:226:129:; do
    IFS=: read -r name major minor driver <<<"$node"
    number="$major:$minor"
    mkdir -p "$drm/$name/device"
    echo "$number" >"$drm/$name/dev"
    [[ -z $driver ]] || ln -s "../../../bus/pci/drivers/$driver" "$drm/$name/device/driver"
    : >"$dir/dev/dri/$name"
    ln -s "../dri/$name" "$dir/dev/char/$number"
  done
  : >"$dir/dev/null"
  ln -s ../null "$dir/dev/char/1:3"
  ln -s ../card0 "$dir/dev/dri/by-path/pci-0000:01:00.0-card"
  ln -s ../renderD129 "$dir/dev/dri/by-path/pci-0000:01:00.0-render"
  ln -s ../card1 "$dir/dev/dri/by-path/pci-0000:79:00.0-card"
  ln -s ../renderD128 "$dir/dev/dri/by-path/pci-0000:79:00.0-render"
  ln -s pci-0000:79:00.0-card "$dir/dev/dri/by-path/alias"
}
# amd: the host as it is. plain: the same nodes under another driver.
# inside: the view the namespace leaves, with every amdgpu path gone.
# stray-*: one entry the fence cannot place. junk: a device number that is
# none.
world "$TMP_ROOT/amd"
world "$TMP_ROOT/plain"
for node in card1 renderD128; do
  ln -sfn ../../../bus/pci/drivers/i915 "$TMP_ROOT/plain/sys/class/drm/$node/device/driver"
done
world "$TMP_ROOT/inside"
for path in "${amd_paths[@]}"; do rm -- "$TMP_ROOT/inside/dev/$path"; done
world "$TMP_ROOT/stray-node"
ln -sfn ../../../bus/pci/drivers/i915 "$TMP_ROOT/stray-node/sys/class/drm/card1/device/driver"
ln -sfn ../../../bus/pci/drivers/i915 "$TMP_ROOT/stray-node/sys/class/drm/renderD128/device/driver"
: >"$TMP_ROOT/stray-node/dev/dri/card7"
world "$TMP_ROOT/stray-file"
: >"$TMP_ROOT/stray-file/dev/char/9:9"
world "$TMP_ROOT/junk"
echo junk >"$TMP_ROOT/junk/sys/class/drm/card1/dev"

# What a command inside reads: each path as resolves, dangling or none, a
# kept link's own target, the PID namespace, the working directory and one
# variable of the caller's environment. It exits 9.
cat >"$TMP_ROOT/report.sh" <<'SH'
dev="$1"; shift
for path in "$@"; do
  if [ -e "$dev/$path" ]; then state=resolves; elif [ -L "$dev/$path" ]; then state=dangling; else state=none; fi
  echo "$state $path"
done
echo "target $(readlink "$dev/char/226:0")"
echo "pidns $(readlink /proc/self/ns/pid)"
echo "cwd $PWD"
echo "env ${FENCE_TEST_VALUE-unset}"
exit 9
SH
want_report="$(
  printf 'none %s\n' "${amd_paths[@]}"
  printf 'resolves %s\n' "${other_paths[@]}" char/1:3
  printf 'target ../dri/card0\npidns other\ncwd %s\nenv kept\n' "$TMP_ROOT/cwd"
)"
# What the report reads where no node is hidden: every path resolves.
want_plain="$(
  printf 'resolves %s\n' "${amd_paths[@]}" "${other_paths[@]}" char/1:3
  printf 'target ../dri/card0\npidns other\ncwd %s\nenv kept\n' "$TMP_ROOT/cwd"
)"
# What a stopped command does: a line for each TERM, INT or HUP it gets,
# then an exit trap that ends with a line a second after it starts. It
# exits with a status a signal never gives, so a fence that returns the
# status of its own interrupted wait shows.
cat >"$TMP_ROOT/stop.sh" <<'SH'
log="$1"
trap 'kill "$idle" 2>/dev/null; echo exit-start >>"$log"; sleep 1; echo exit-end >>"$log"' EXIT
for pair in TERM:43 INT:30 HUP:29; do
  trap "echo ${pair%:*} >>\"\$log\"; exit ${pair#*:}" "${pair%:*}"
done
sleep 10 &
idle=$!
echo started >>"$log"
wait "$idle"
SH
# What bash does with an INT and no trap for it: the foreground command it
# waits on exits 0, so bash carries on. The run then idles until a TERM.
cat >"$TMP_ROOT/carry.sh" <<'SH'
log="$1"
sh -c 'echo started >>"$1"; sleep 1' sh "$log"
echo carried-on >>"$log"
sleep 10 &
wait "$!"
echo idle-end >>"$log"
SH
# A command that changes the terminal's mode and reads a line typed into it.
# It first records its PID namespace beside its log.
cat >"$TMP_ROOT/tty.sh" <<'SH'
readlink /proc/self/ns/pid >"$1.ns"
stty -echo && stty echo && echo mode-set >>"$1"
read -r line && echo "read=$line" >>"$1"
SH
want_proof="$(
  {
    for path in "${amd_paths[@]}"; do printf 'gpu-fence: absent path=%s/amd/dev/%s\n' "$TMP_ROOT" "$path"; done
    for path in "${other_paths[@]}"; do printf 'gpu-fence: present path=%s/amd/dev/%s dev=0:0\n' "$TMP_ROOT" "$path"; done
  } | LC_ALL=C sort
)"

# run_fence FILE BIN ARG...: FILE with ARG... from the scratch working
# directory, under an environment that holds PATH, the BIN directory alone,
# HOME, TMPDIR, the report's variable and the words in `placed`, which the
# call empties. Sets status; the streams are $TMP_ROOT/out and
# $TMP_ROOT/err.
placed=()
run_fence() {
  local file="$1" bin="$2" words=("${placed[@]}")
  shift 2
  placed=()
  rm -f -- "$TMP_ROOT/marker" "$TMP_ROOT/bwrap-called"
  status=0
  (cd -- "$TMP_ROOT/cwd" && env -i PATH="$TMP_ROOT/bin-$bin" HOME="$TMP_ROOT" TMPDIR="$TMP_ROOT" FENCE_TEST_VALUE=kept "${words[@]}" "$BASH" "$file" "$@") \
    >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" || status=$?
}
# place WHERE: `fenced` puts the next run inside a fence's namespace, which
# names an existing ledger there; anything else puts it outside.
place() { placed=(); [[ $1 != fenced ]] || placed=(VGSHELL_FENCE_LEDGER="$TMP_ROOT/ledger"); }
# seen_report: the report with its PID namespace read as the test's own,
# `same`, or `other`.
seen_report() { awk -v mine="pidns $own_pidns" '/^pidns / { print ($0 == mine ? "pidns same" : "pidns other"); next } { print }' "$TMP_ROOT/out"; }
# roots WORLD: sets at, the words that point the fence at WORLD's trees.
roots() { at=(--sys "$TMP_ROOT/$1/sys" --dev "$TMP_ROOT/$1/dev"); }
first_error() { local line=""; read -r line <"$TMP_ROOT/err" || true; printf '%s\n' "$line"; }
# stopped FILE BIN LINE ARG...: exit 77, LINE first on stderr, and the
# command, which would make the marker, never started.
stopped() {
  local file="$1" bin="$2" line="$3"
  shift 3
  run_fence "$file" "$bin" "$@" touch "$TMP_ROOT/marker"
  [[ $status -eq 77 && "$(first_error)" == "gpu-fence: status=not-measured reason=$line" && ! -e $TMP_ROOT/marker ]]
}

# The cases. Each takes the fence file first.
check_is() { # FILE WORLD STATUS WHERE
  roots "$2"
  place "$4"
  run_fence "$1" none "${at[@]}" --check
  [[ $status -eq $3 && ! -s $TMP_ROOT/out && ! -s $TMP_ROOT/err ]]
}
runs_directly() { # FILE WORLD
  roots "$2"
  place fenced
  run_fence "$1" broken "${at[@]}" sh -c 'touch "$1"; exit 9' _ "$TMP_ROOT/marker"
  [[ $status -eq 9 && -e $TMP_ROOT/marker && ! -e $TMP_ROOT/bwrap-called && ! -s $TMP_ROOT/err ]]
}
hides() { # FILE
  local seen
  roots amd
  run_fence "$1" real "${at[@]}" sh "$TMP_ROOT/report.sh" "$TMP_ROOT/amd/dev" "${amd_paths[@]}" "${other_paths[@]}" char/1:3
  seen="$(seen_report)" || return 1
  [[ $status -eq 9 && $seen == "$want_report" && "$(LC_ALL=C sort -- "$TMP_ROOT/err")" == "$want_proof" ]]
}
# plain_namespace FILE: outside a fence on a host with no amdgpu node the
# command runs in a PID namespace of its own, with every path as it was
# and no proof line.
plain_namespace() {
  local seen
  roots plain
  run_fence "$1" real "${at[@]}" sh "$TMP_ROOT/report.sh" "$TMP_ROOT/plain/dev" "${amd_paths[@]}" "${other_paths[@]}" char/1:3
  seen="$(seen_report)" || return 1
  [[ $status -eq 9 && $seen == "$want_plain" && ! -s $TMP_ROOT/err ]]
}
# A command that leaves a process in another session and a stopped one,
# then says it is ready.
cat >"$TMP_ROOT/leave.sh" <<'SH'
setsid sleep 300 &
sleep 301 &
kill -STOP $!
echo ready >"$1"
while :; do sleep 0.1; done
SH
# killed.sh FENCE VERDICT ARG...: PID 1 of the case's namespace. It runs the
# fence over ARG... with leave.sh, sends the fence SIGKILL once leave.sh is
# ready, and writes to VERDICT how many processes but its own are left in
# the namespace once none is, or after 5 s. A zombie has ended.
cat >"$TMP_ROOT/killed.sh" <<'SH'
fence="$1" verdict="$2" ready="$2.ready" bin="$3" home="$4"
shift 4
env -i PATH="$bin" HOME="$home" TMPDIR="$home" "$BASH" "$fence" "$@" sh "$home/leave.sh" "$ready" >/dev/null 2>&1 &
pid=$!
for _ in $(seq 1 100); do [[ -s $ready ]] && break; sleep 0.05; done
[[ -s $ready ]] || { echo unready >"$verdict"; exit 0; }
kill -KILL "$pid"
wait "$pid" 2>/dev/null
for _ in $(seq 1 100); do
  left=0
  for entry in /proc/[0-9]*; do
    [[ ${entry#/proc/} != 1 ]] || continue
    read -r line 2>/dev/null <"$entry/stat" || continue
    rest="${line##*) }"
    [[ ${rest%% *} == Z ]] || left=$((left + 1))
  done
  ((left == 0)) && break
  sleep 0.05
done
echo "left=$left" >"$verdict"
SH
# fence_killed FILE: a SIGKILL of the fence leaves no process its command
# started.
fence_killed() {
  local verdict="$TMP_ROOT/killed.verdict"
  roots plain
  rm -f -- "$verdict" "$verdict.ready"
  status=0
  timeout -k 2 20 "${contain[@]}" "$BASH" "$TMP_ROOT/killed.sh" "$1" "$verdict" "$TMP_ROOT/bin-real" "$TMP_ROOT" "${at[@]}" \
    >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" || status=$?
  [[ $status -eq 0 && -r $verdict && "$(<"$verdict")" == left=0 ]]
}
no_bwrap() { # FILE
  roots amd
  stopped "$1" none bwrap-missing "${at[@]}"
}
no_namespace() { # FILE
  roots amd
  stopped "$1" broken "namespace-failed exit=1" "${at[@]}" && grep -qxF 'bwrap: stand-in makes no namespace' "$TMP_ROOT/err"
}
proof_sees() { stopped "$1" none "amd-node-visible path=$TMP_ROOT/amd/dev/dri/card1" --inside "$TMP_ROOT/amd/dev/dri/card1" -- --; }
proof_misses() { stopped "$1" none "node-missing path=$TMP_ROOT/amd/dev/dri/gone" --inside -- "$TMP_ROOT/amd/dev/dri/gone" --; }
# Two paths in each list, one good and one bad: both reasons come first, in
# the order read, then the proof lines of the good paths. The indented
# lines under a reason are its explanation and are not pinned.
proof_orders() { # FILE
  local dri="$TMP_ROOT/amd/dev/dri" want
  want="gpu-fence: status=not-measured reason=amd-node-visible path=$dri/card1
gpu-fence: status=not-measured reason=node-missing path=$dri/gone-b
gpu-fence: absent path=$dri/gone-a
gpu-fence: present path=$dri/card0 dev=0:0"
  stopped "$1" none "amd-node-visible path=$dri/card1" --inside "$dri/gone-a" "$dri/card1" -- "$dri/card0" "$dri/gone-b" -- &&
    [[ "$(grep -v '^gpu-fence:   ' "$TMP_ROOT/err")" == "$want" ]]
}
unplaced() { # FILE WORLD PATH
  roots "$2"
  stopped "$1" none "entry-unclassified path=$TMP_ROOT/$2/dev/$3" "${at[@]}"
}
unreadable() { # FILE
  roots junk
  stopped "$1" none "sysfs-unreadable path=$TMP_ROOT/junk/sys/class/drm/card1/dev" "${at[@]}"
}
# stops_once FILE HOW SIGNAL STATUS: the fence runs stop.sh in the
# namespace, in a process group of its own as a terminal's job is, and gets
# SIGNAL. `pid` sends it to the fence's pid and, once the command has it,
# twice more, 0.2 s apart, so each lands on its own; `twice` sends it to
# the fence's pid twice at once, as timeout does; `group` sends it to the
# fence's group, as timeout and a terminal do. The command gets it once,
# and its exit trap has ended when the fence returns the command's STATUS.
stops_once() {
  local file="$1" how="$2" signal="$3" log="$TMP_ROOT/stop.log" fenced i
  roots amd
  : >"$log"
  status=0
  set -m
  (cd -- "$TMP_ROOT/cwd" && exec env -i PATH="$TMP_ROOT/bin-real" HOME="$TMP_ROOT" "$BASH" "$file" "${at[@]}" sh "$TMP_ROOT/stop.sh" "$log") \
    >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" &
  set +m
  fenced=$!
  for ((i = 0; i < 100; i++)); do
    [[ "$(<"$log")" != started ]] || break
    sleep 0.05
  done
  if [[ $how == group ]]; then
    kill -s "$signal" -- "-$fenced"
  elif [[ $how == twice ]]; then
    kill -s "$signal" -- "$fenced"
    kill -s "$signal" -- "$fenced"
  else
    kill -s "$signal" -- "$fenced"
    for ((i = 0; i < 100; i++)); do
      [[ "$(<"$log")" != started$'\n'"$signal"* ]] || break
      sleep 0.05
    done
    kill -s "$signal" -- "$fenced" 2>/dev/null || true
    sleep 0.2
    kill -s "$signal" -- "$fenced" 2>/dev/null || true
  fi
  wait "$fenced" || status=$?
  [[ $status -eq $4 && "$(<"$log")" == "started"$'\n'"$signal"$'\n'"exit-start"$'\n'"exit-end" ]]
# The shell reports on stderr a job a signal ended; the status says it.
} 2>/dev/null
# int_then_term FILE: the fence runs carry.sh under bash in the namespace
# and gets INT while the foreground command runs, then TERM once bash has
# carried on. The TERM ends the run with bash's status for it, long before
# the idle command would end.
int_then_term() {
  local file="$1" log="$TMP_ROOT/carry.log" fenced i
  roots amd
  : >"$log"
  status=0
  set -m
  (cd -- "$TMP_ROOT/cwd" && exec env -i PATH="$TMP_ROOT/bin-real" HOME="$TMP_ROOT" "$BASH" "$file" "${at[@]}" "$BASH" "$TMP_ROOT/carry.sh" "$log") \
    >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" &
  set +m
  fenced=$!
  for ((i = 0; i < 100; i++)); do
    [[ "$(<"$log")" != started ]] || break
    sleep 0.05
  done
  kill -s INT -- "$fenced"
  for ((i = 0; i < 100; i++)); do
    [[ "$(<"$log")" != started$'\n'carried-on ]] || break
    sleep 0.05
  done
  kill -s TERM -- "$fenced"
  wait "$fenced" || status=$?
  [[ $status -eq 143 && "$(<"$log")" == "started"$'\n'"carried-on" ]]
# The shell reports on stderr a job a signal ended; the status says it.
} 2>/dev/null
# on_terminal FILE: the fence runs tty.sh from a real terminal, and a line
# is typed into it. In a background group of the terminal's own session the
# command would stop on its mode change or its read.
# The terminal runs in the case's own PID namespace: timeout ends unshare,
# which ends the namespace, a command a terminal stopped included.
on_terminal() {
  local log="$TMP_ROOT/tty.log" run
  roots amd
  : >"$log"
  rm -f -- "$log.ns"
  printf -v run '%q ' env -i PATH="$TMP_ROOT/bin-real" HOME="$TMP_ROOT" TMPDIR="$TMP_ROOT" "$BASH" "$1" "${at[@]}" sh "$TMP_ROOT/tty.sh" "$log"
  status=0
  terminal_started=$SECONDS
  # The shell reports on stderr a job a signal ended; the status says it.
  { { echo typed; sleep 2; } | timeout -k 2 5 "${contain[@]}" script -qec "$run" /dev/null >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" || status=$?; } 2>/dev/null
  terminal_secs=$((SECONDS - terminal_started))
  [[ $status -eq 0 && "$(<"$log")" == "mode-set"$'\n'"read=typed" ]]
}
# terminal_ends FILE: the terminal case over FILE, whatever its verdict,
# returns within 9 s, timeout's 5 s, its 2 s grace and the time to end
# the namespace, and
# leaves no process in the PID namespace tty.sh ran in.
terminal_ends() {
  local ns left
  on_terminal "$1" || true
  ns="$(<"$TMP_ROOT/tty.log.ns")" || return 1
  left="$(python3 -c 'import os, sys
for pid in filter(str.isdigit, os.listdir("/proc")):
    try:
        if os.readlink(f"/proc/{pid}/ns/pid") == sys.argv[1]:
            print(pid)
    except OSError:
        pass' "$ns")" || return 1
  [[ $terminal_secs -le 9 && -z $left ]]
}
refused() { # FILE WANT ARG...
  local file="$1" want="$2"
  shift 2
  run_fence "$file" none "$@"
  [[ $status -eq 2 && "$(first_error)" == "gpu-fence: refused: argument=$want" ]]
}

# Rows: label | whether the case makes a namespace | the case and its words.
cases=(
  "a visible amdgpu node needs the fence|no|check_is amd 1 outside"
  "a visible amdgpu node inside a fence needs the fence|no|check_is amd 1 fenced"
  "a host with no amdgpu node needs the fence|no|check_is plain 1 outside"
  "inside a fence a host with no amdgpu node needs none|no|check_is plain 0 fenced"
  "inside a fence a view with every amdgpu path gone needs none|no|check_is inside 0 fenced"
  "inside a fence a host with no amdgpu node runs the command directly|no|runs_directly plain"
  "inside a fence a view with every amdgpu path gone runs the command directly|no|runs_directly inside"
  "the namespace hides every amdgpu path, keeps the rest and proves both|yes|hides"
  "a host with no amdgpu node runs the command in a PID namespace with every path kept|yes|plain_namespace"
  "a SIGKILL of the fence ends every process its command started|yes|fence_killed"
  "TERM to the fence reaches the command once and its exit trap ends before the fence returns|yes|stops_once pid TERM 43"
  "INT to the fence reaches the command once and its exit trap ends before the fence returns|yes|stops_once pid INT 30"
  "HUP to the fence reaches the command once and its exit trap ends before the fence returns|yes|stops_once pid HUP 29"
  "TERM to the fence's process group reaches the command once|yes|stops_once group TERM 43"
  "two TERMs at once to the fence reach the command once|yes|stops_once twice TERM 43"
  "a TERM after an INT the command carried on from ends the run|yes|int_then_term"
  "a command run from a terminal changes its mode and reads it|yes|on_terminal"
  "a host with no bubblewrap starts nothing|no|no_bwrap"
  "a namespace bubblewrap cannot make starts nothing|no|no_namespace"
  "an amdgpu path that resolves inside starts nothing|no|proof_sees"
  "a kept node gone inside starts nothing|no|proof_misses"
  "a failed proof names its reasons before the paths it read|no|proof_orders"
  "a node sysfs does not list starts nothing|no|unplaced stray-node dri/card7"
  "an entry that is no link starts nothing|no|unplaced stray-file char/9:9"
  "a device number that is none starts nothing|no|unreadable"
  "a call with no command is refused|no|refused missing-command"
  "an unknown option is refused|no|refused --nope --nope"
)
# run_case FILE LABEL: 0 green, 1 red, 2 when it needs a namespace this
# host cannot make, 3 when no case carries LABEL.
run_case() {
  local file="$1" row label needs words
  for row in "${cases[@]}"; do
    IFS='|' read -r label needs words <<<"$row"
    [[ $label == "$2" ]] || continue
    [[ $needs == no || $namespace == true ]] || return 2
    # shellcheck disable=SC2086 # the row's words are the case and its arguments
    if ${words%% *} "$file" ${words#"${words%% *}"}; then return 0; fi
    return 1
  done
  return 3
}
show() { printf '        exit=%s\n' "$status"; sed 's/^/        /' -- "$TMP_ROOT/out" "$TMP_ROOT/err"; }
for row in "${cases[@]}"; do
  label="${row%%|*}"
  result=0
  run_case "$fence" "$label" || result=$?
  case "$result" in
    0) ok "$label" ;;
    2) unmeasured=$((unmeasured + 1)); printf '  skip  %s\n' "$label" ;;
    *) fail "$label"; show ;;
  esac
done

# mutate FILE OLD NEW OUT: a copy of FILE with OLD, which must occur once,
# replaced by NEW.
mutate() {
  local text rest count
  text="$(<"$1")"
  rest="${text//"$2"/}"
  count=$(( (${#text} - ${#rest}) / ${#2} ))
  if [[ $count -ne 1 ]]; then
    printf '        mutation matched %s times: %s\n' "$count" "$2"
    return 1
  fi
  printf '%s\n' "${text/"$2"/"$3"}" >"$4"
  ! cmp -s -- "$1" "$4" || { printf '        mutation left the file unchanged: %s\n' "$2"; return 1; }
}

# Controls, four fields each: label, text, replacement, and the case that
# must go red.
# shellcheck disable=SC2034 # run_controls reads the table by name
controls=(
  "the fence with no restriction"
  'fence=(bwrap --dev-bind / / "${rebuild[@]}" --' 'fence=(bwrap --dev-bind / / --'
  "the namespace hides every amdgpu path, keeps the rest and proves both"
  "a host with a visible amdgpu node runs the command directly"
  '! fenced || exposed || exec "$@"' 'exec "$@"'
  "the namespace hides every amdgpu path, keeps the rest and proves both"
  "outside a fence a host with no amdgpu node runs the command directly"
  '! fenced || exposed || exec "$@"' 'exposed || exec "$@"'
  "a host with no amdgpu node runs the command in a PID namespace with every path kept"
  "the check passes outside a fence"
  'if exposed || ! fenced; then exit 1; fi' 'if exposed; then exit 1; fi'
  "a host with no amdgpu node needs the fence"
  "the check passes a visible amdgpu node inside a fence"
  'if exposed || ! fenced; then exit 1; fi' 'if ! fenced; then exit 1; fi'
  "a visible amdgpu node inside a fence needs the fence"
  "the amdgpu nodes are the ones of a fixed number"
  'if [[ $driver == amdgpu ]]; then' 'if [[ $name == card0 || $name == renderD129 ]]; then'
  "inside a fence a view with every amdgpu path gone needs none"
  "a link to an amdgpu node is made again"
  'elif [[ -n ${amd_target[$target]:-} ]]; then' 'elif false; then'
  "the namespace hides every amdgpu path, keeps the rest and proves both"
  "no other node is bound back"
  'rebuild+=(--dev-bind "$entry" "$entry")' ':'
  "the namespace hides every amdgpu path, keeps the rest and proves both"
  "no link is made again"
  'rebuild+=("${symlinks[@]}")' ':'
  "the namespace hides every amdgpu path, keeps the rest and proves both"
  "the namespace is no PID namespace"
  ' --unshare-pid --proc /proc' ''
  "the namespace hides every amdgpu path, keeps the rest and proves both"
  "bubblewrap outlives the fence"
  '--proc /proc --die-with-parent --new-session' '--proc /proc --new-session'
  "a SIGKILL of the fence ends every process its command started"
  "the command's status is lost"
  'exit "$status" ;;' 'exit $((status ? 1 : 0)) ;;'
  "the namespace hides every amdgpu path, keeps the rest and proves both"
  "the fence hands itself to bubblewrap"
  '"${fence[@]}" --info-fd 3 "${proof[@]}" "$@" 3>"$fence_dir/info" &' 'exec "${fence[@]}" "${proof[@]}" "$@"'
  "TERM to the fence reaches the command once and its exit trap ends before the fence returns"
  "TERM is not handed on"
  "trap 'forward TERM 143' TERM" ':'
  "TERM to the fence reaches the command once and its exit trap ends before the fence returns"
  "INT is not handed on"
  "trap 'forward INT 130' INT" ':'
  "INT to the fence reaches the command once and its exit trap ends before the fence returns"
  "HUP is not handed on"
  "trap 'forward HUP 129' HUP" ':'
  "HUP to the fence reaches the command once and its exit trap ends before the fence returns"
  "a signal goes to the namespace's init"
  '[[ -z $init ]] || read -r child _ 2>/dev/null <"/proc/$init/task/$init/children" || true' 'child="$init"'
  "TERM to the fence reaches the command once and its exit trap ends before the fence returns"
  "a later signal is handed on too"
  '((forwarded[$1]++ == 0)) || return 0' ':'
  "TERM to the fence reaches the command once and its exit trap ends before the fence returns"
  "a later signal of another kind is dropped"
  $'declare -A forwarded=()\nforward() {\n  ((forwarded[$1]++ == 0))' $'forwarded=0\nforward() {\n  ((forwarded++ == 0))'
  "a TERM after an INT the command carried on from ends the run"
  "the fence returns when the signal arrives"
  'while ours "$monitor"; do' 'while false; do'
  "TERM to the fence reaches the command once and its exit trap ends before the fence returns"
  "the fence waits a fixed number of times"
  'while ours "$monitor"; do' 'for _ in 1 2; do'
  "TERM to the fence reaches the command once and its exit trap ends before the fence returns"
  "bubblewrap runs in the caller's process group"
  $'    set -m\n    "${fence[@]}"' '    "${fence[@]}"'
  "TERM to the fence's process group reaches the command once"
  "the command stays in the caller's terminal session"
  '--die-with-parent --new-session' '--die-with-parent'
  "a command run from a terminal changes its mode and reads it"
  "a missing bubblewrap runs the command"
  'command -v bwrap >/dev/null 2>&1 || { fault bwrap-missing; exit 77; }' 'command -v bwrap >/dev/null 2>&1 || exec "$@"'
  "a host with no bubblewrap starts nothing"
  "a failed namespace runs the command"
  '*) fault namespace-failed "exit=$status"; printf '\''%s\n'\'' "$probe" >&2; exit 77 ;;' '*) exec "$@" ;;'
  "a namespace bubblewrap cannot make starts nothing"
  "the proof passes an amdgpu path that resolves"
  'fault amd-node-visible "path=$1"; broken=true' 'fault amd-node-visible "path=$1"'
  "an amdgpu path that resolves inside starts nothing"
  "the proof passes a kept node that is gone"
  'fault node-missing "path=$1"; broken=true' 'fault node-missing "path=$1"'
  "a kept node gone inside starts nothing"
  "a proof line is printed as its path is read"
  'proof+=("absent path=$1")' 'note "absent path=$1"'
  "a failed proof names its reasons before the paths it read"
  "a node sysfs does not list is passed"
  $'    else\n      fault entry-unclassified "path=$entry"; exit 77\n' $'    else\n      :\n'
  "a node sysfs does not list starts nothing"
  "an entry that is no link is dropped"
  '[[ -L $entry ]] || { fault entry-unclassified "path=$entry"; exit 77; }' '[[ -L $entry ]] || continue'
  "an entry that is no link starts nothing"
  "any text is a device number"
  '[[ $number =~ ^[0-9]+:[0-9]+$ ]] ||' 'true ||'
  "a device number that is none starts nothing"
  "a call with no command runs nothing and passes"
  '(($#)) || { note "refused: argument=missing-command"; exit 2; }' '(($#)) || exit 0'
  "a call with no command is refused"
)
# run_controls TABLE: each control of the array TABLE planted in a copy of
# the fence must turn its case red. A control that leaves the case green,
# or that names no case, fails.
run_controls() {
  local -n plants="$1"
  local i label mutant result
  for (( i = 0; i < ${#plants[@]}; i += 4 )); do
    label="${plants[i]}"
    mutant="$TMP_ROOT/mutant-$1-$i.sh"
    if ! mutate "$fence" "${plants[i + 1]}" "${plants[i + 2]}" "$mutant"; then fail "control: $label"; continue; fi
    result=0
    run_case "$mutant" "${plants[i + 3]}" >/dev/null || result=$?
    case "$result" in
      0) fail "control: $label left '${plants[i + 3]}' green" ;;
      1) ok "control: $label" ;;
      2) unmeasured=$((unmeasured + 1)); printf '  skip  control: %s\n' "$label" ;;
      3) fail "control: $label names no case: ${plants[i + 3]}" ;;
      *) fail "control: $label: run_case answered $result" ;;
    esac
  done
}
run_controls controls
# The loop's own control: a planted control whose label no case carries.
# The loop runs in a substitution, so its failure count stays there.
# shellcheck disable=SC2034 # run_controls reads the table by name
planted_control=("a control with no case" 'exposed || exec "$@"' 'exec "$@"' "no case carries this label")
planted_out="$(failures=0; run_controls planted_control; echo "failures=$failures")"
if [[ $planted_out == "  FAIL  control: a control with no case names no case: no case carries this label"$'\n'"failures=1" ]]; then
  ok "control: a control that names no case fails the controls loop"
else
  fail "control: a control that names no case fails the controls loop"; printf '%s\n' "$planted_out" | sed 's/^/        /'
fi

# A fence whose command stays in the terminal's session stops on its mode
# change. The terminal case over it must still end within its bound and
# leave no process, stopped or not.
if [[ $namespace == true ]]; then
  if ! mutate "$fence" '--die-with-parent --new-session' '--die-with-parent' "$TMP_ROOT/stops-on-terminal.sh"; then
    fail "a command a terminal stops ends with the terminal case"
  elif terminal_ends "$TMP_ROOT/stops-on-terminal.sh"; then
    ok "a command a terminal stops ends with the terminal case, within its bound"
  else
    fail "a command a terminal stops ends with the terminal case, within its bound (${terminal_secs}s)"; show
  fi
else
  unmeasured=$((unmeasured + 1))
  printf '  skip  a command a terminal stops ends with the terminal case\n'
fi

# The fence with no restriction, read for what it reports: every amdgpu
# path, each seen by stat, and no command started.
if [[ $namespace == true ]]; then
  roots amd
  want_seen="$(for path in "${amd_paths[@]}"; do printf 'gpu-fence: status=not-measured reason=amd-node-visible path=%s/amd/dev/%s\n' "$TMP_ROOT" "$path"; done | LC_ALL=C sort)"
  run_fence "$TMP_ROOT/mutant-controls-0.sh" real "${at[@]}" touch "$TMP_ROOT/marker"
  seen="$(grep -F 'reason=amd-node-visible' "$TMP_ROOT/err" | LC_ALL=C sort)" || seen=""
  if [[ $status -eq 77 && $seen == "$want_seen" && ! -e $TMP_ROOT/marker ]]; then
    ok "control: the fence with no restriction reports the ${#amd_paths[@]} amdgpu paths it sees and starts nothing"
  else
    fail "control: the fence with no restriction reports the amdgpu paths it sees and starts nothing"; show
  fi
else
  unmeasured=$((unmeasured + 1))
  printf '  skip  control: the fence with no restriction reports the amdgpu paths it sees\n'
fi

# The wiring. A stand-in fence answers --check with the status in
# fence-answer and records each call in fence.log; called to run a command
# it records the words and runs nothing.
cat >"$TMP_ROOT/fence-stand-in" <<SH
#!/bin/sh
if [ "\$1" = --check ]; then
  echo check >>"$TMP_ROOT/fence.log"
  read -r answer <"$TMP_ROOT/fence-answer"
  exit "\$answer"
fi
printf 'run' >>"$TMP_ROOT/fence.log"
for word in "\$@"; do printf ' [%s]' "\$word" >>"$TMP_ROOT/fence.log"; done
echo >>"$TMP_ROOT/fence.log"
SH
printf '#!/bin/sh\necho runner-started >>"%s"\n' "$TMP_ROOT/fence.log" >"$TMP_ROOT/runner"
chmod +x "$TMP_ROOT/fence-stand-in" "$TMP_ROOT/runner"

# Entry points: the script and the arguments each case hands it, one of
# them holding a space.
entry_points=(qml-smoke.sh sandbox-shots.sh measure-shader.sh qml-unit.sh)
entry_words() {
  case "$1" in
    qml-smoke.sh) words=(--timeout "6 0" --keep) ;;
    sandbox-shots.sh) words=(--out "o ut" --scale 2 gallery) ;;
    measure-shader.sh) words=(--calibrate "out file.json" --keep) ;;
    qml-unit.sh) words=(--ui "$TMP_ROOT/u i") ;;
    *) printf '        no words for entry point: %s\n' "$1"; return 1 ;;
  esac
}
# entry FILE NAME ANSWER: FILE as scripts/NAME of a scratch tree whose
# fence is the stand-in answering ANSWER, whose harness is a stand-in
# that only says it was reached, and which holds the repository's smoke
# row list, which qml-smoke.sh reads before the fence. Leaves the calls in fence.log.
entry() {
  local file="$1" name="$2" tree="$TMP_ROOT/tree-$2"
  entry_words "$name" || return 1
  rm -rf -- "$tree" "$TMP_ROOT/entry-tmp"
  mkdir -p "$tree/scripts/smoke" "$TMP_ROOT/entry-tmp"
  cp -- "$file" "$tree/scripts/$name"
  cp -- "$TMP_ROOT/fence-stand-in" "$tree/scripts/smoke/gpu-fence.sh"
  cp -- "$repo/scripts/smoke/rows.list" "$tree/scripts/smoke/rows.list"
  printf 'echo harness-reached\nexit 0\n' >"$tree/scripts/smoke/harness.sh"
  : >"$TMP_ROOT/fence.log"
  echo "$3" >"$TMP_ROOT/fence-answer"
  status=0
  (cd -- "$TMP_ROOT/cwd" && env -i PATH="$PATH" HOME="$TMP_ROOT" TMPDIR="$TMP_ROOT/entry-tmp" QML_UNIT_RUNNER="$TMP_ROOT/runner" \
    "$BASH" "$tree/scripts/$name" "${words[@]}") >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" || status=$?
}
# enters FILE NAME: where the check fails, the fence gets the script's own
# path and every argument, the script's status is the fence's, and nothing
# was made under the tree or the scratch directory before.
enters() {
  local want word
  entry "$1" "$2" 1 || return 1
  want="check"$'\n'"run [$TMP_ROOT/tree-$2/scripts/$2]"
  for word in "${words[@]}"; do want+=" [$word]"; done
  [[ $status -eq 0 && "$(<"$TMP_ROOT/fence.log")" == "$want" && -z "$(ls -A -- "$TMP_ROOT/entry-tmp")" && ! -e $TMP_ROOT/tree-$2/tmp ]]
}
# goes_on FILE NAME: where the check passes, the fence is asked once and
# never run.
goes_on() {
  entry "$1" "$2" 0 || return 1
  [[ "$(<"$TMP_ROOT/fence.log")" == check ]]
}
for name in "${entry_points[@]}"; do
  if enters "$repo/scripts/$name" "$name"; then ok "$name hands itself and its arguments to the fence before it makes anything"; else fail "$name hands itself and its arguments to the fence before it makes anything"; show; sed 's/^/        /' -- "$TMP_ROOT/fence.log"; fi
  if goes_on "$repo/scripts/$name" "$name"; then ok "$name goes on by itself where the check passes"; else fail "$name goes on by itself where the check passes"; sed 's/^/        /' -- "$TMP_ROOT/fence.log"; fi
  mutant="$TMP_ROOT/mutant-$name"
  if ! mutate "$repo/scripts/$name" '--check || exec ' '--check || : ' "$mutant"; then fail "control: $name without its fence line"; continue; fi
  if enters "$mutant" "$name"; then fail "control: $name that never enters the fence stayed green"; else ok "control: $name that never enters the fence"; fi
  if ! mutate "$repo/scripts/$name" '--check || exec ' '--check; exec ' "$mutant"; then fail "control: $name that always enters"; continue; fi
  if goes_on "$mutant" "$name"; then fail "control: $name that always enters the fence stayed green"; else ok "control: $name that always enters the fence"; fi
done

# The harness. Its prerequisites come first, so the stand-ins for its tools
# are the names it prints as missing with nothing on PATH; each records
# that it started.
harness="$repo/scripts/smoke/harness.sh"
needs="$(env -i PATH="$TMP_ROOT/empty" HOME="$TMP_ROOT" "$BASH" -c 'repo="$1"; source "$2"' _ "$repo" "$harness" 2>/dev/null)" || true
needs="$(sed -n 's/^qml-smoke: status=not-measured missing=//p' <<<"$needs")"
IFS=, read -r -a needed <<<"$needs"
mkdir -p "$TMP_ROOT/bin-harness" "$TMP_ROOT/run" "$TMP_ROOT/harness-tree/scripts/smoke" "$TMP_ROOT/harness-tree/bin"
for tool in "${needed[@]}"; do
  # The two variables it names beside its tools are set below.
  [[ $tool != WAYLAND_DISPLAY && $tool != XDG_RUNTIME_DIR ]] || continue
  printf '#!/bin/sh\necho "%s" >>"%s"\n' "$tool" "$TMP_ROOT/started" >"$TMP_ROOT/bin-harness/$tool"
  chmod +x "$TMP_ROOT/bin-harness/$tool"
done
for tool in Hyprland qs dbus-daemon; do
  [[ -x $TMP_ROOT/bin-harness/$tool ]] || fail "the harness's own list of tools no longer names $tool: the reader of its missing line is broken (read: $needs)"
done
python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$TMP_ROOT/run/wayland-test"
for file in "$repo"/scripts/smoke/*; do
  [[ ${file##*/} == gpu-fence.sh ]] || ln -s -- "$file" "$TMP_ROOT/harness-tree/scripts/smoke/${file##*/}"
done
ln -s -- "$repo/bin/lib" "$TMP_ROOT/harness-tree/bin/lib"
cp -- "$TMP_ROOT/fence-stand-in" "$TMP_ROOT/harness-tree/scripts/smoke/gpu-fence.sh"
# The harness up to the end of its check, which must come before it starts
# anything, then a line that says the harness went on.
check_block='if ! "$repo/scripts/smoke/gpu-fence.sh" --check; then
  printf '\''qml-smoke: status=not-measured missing=gpu-fence\n'\''
  exit 77
fi'
harness_text="$(<"$harness")"
harness_head="${harness_text%%"$check_block"*}"
if [[ $harness_head == "$harness_text" ]]; then
  fail "the harness holds no fence check"
elif [[ $harness_head == *'setsid "'* || $harness_head == *$'\nspawn '* ]]; then
  fail "the harness starts a process before its fence check"
else
  printf '%s%s\necho harness-went-on\nexit 0\n' "$harness_head" "$check_block" >"$TMP_ROOT/harness-cut.sh"
  # harness_run FILE ANSWER: sets status; the streams as above.
  harness_run() {
    : >"$TMP_ROOT/fence.log"; : >"$TMP_ROOT/started"
    echo "$2" >"$TMP_ROOT/fence-answer"
    status=0
    env -i PATH="$TMP_ROOT/bin-harness" HOME="$TMP_ROOT" WAYLAND_DISPLAY=wayland-test XDG_RUNTIME_DIR="$TMP_ROOT/run" \
      "$BASH" -c 'repo="$1"; source "$2"' _ "$TMP_ROOT/harness-tree" "$1" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" || status=$?
  }
  # pkg-config answers the harness's own prerequisite check, which comes
  # before the fence's; no other tool may have started.
  stops() {
    local others
    harness_run "$1" 1
    others="$(grep -c -v -x -F pkg-config -- "$TMP_ROOT/started")" || [[ $others == 0 ]] || return 1
    [[ $status -eq 77 && "$(<"$TMP_ROOT/out")" == "qml-smoke: status=not-measured missing=gpu-fence" && $others == 0 ]]
  }
  if stops "$TMP_ROOT/harness-cut.sh"; then ok "the harness stops where the fence's check fails, before it starts anything"; else fail "the harness stops where the fence's check fails, before it starts anything"; show; fi
  harness_run "$TMP_ROOT/harness-cut.sh" 0
  if [[ $status -eq 0 && "$(<"$TMP_ROOT/out")" == harness-went-on && "$(<"$TMP_ROOT/fence.log")" == check ]]; then
    ok "the harness goes on where the fence's check passes"
  else
    fail "the harness goes on where the fence's check passes"; show
  fi
  if ! mutate "$TMP_ROOT/harness-cut.sh" 'if ! "$repo/scripts/smoke/gpu-fence.sh" --check; then' 'if false; then' "$TMP_ROOT/harness-mutant.sh"; then
    fail "control: a harness that never asks the fence"
  elif stops "$TMP_ROOT/harness-mutant.sh"; then
    fail "control: a harness that never asks the fence stayed green"
  else
    ok "control: a harness that never asks the fence"
  fi
fi

if [[ $failures -gt 0 ]]; then
  echo "test-gpu-fence: failed=$failures"
  exit 1
fi
if [[ $unmeasured -gt 0 ]]; then
  echo "test-gpu-fence: status=not-measured missing=bwrap-namespace skipped=$unmeasured"
  exit 77
fi
echo "test-gpu-fence: ok"
