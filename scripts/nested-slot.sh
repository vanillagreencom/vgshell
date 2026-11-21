#!/usr/bin/env bash
# Fleet slot for one nested sandbox run.
#   bash /home/method/dev/vgshell/scripts/nested-slot.sh <command that starts the nested sandbox...>
# Waits for one of NESTED_SLOTS (8 since gen 55: 9 live waiters, 20 min waits at load 11 on 32 cores, cpu pressure 0.5%; 7 since gen 26: 9-ticket queue, 12-14 min waits at load 9.7, cpu pressure 1%; 6 at gen 25; 5 before)
# flock slots, then runs the command with the slot held until it exits. A waiter
# the owner hold refuses marks its ticket .wait and lets later waiters pass it.
# Admission requires load1 below 8 (VGS-2627, owner safety boundary after a
# validation fork storm made home unreachable). This protects the desktop;
# each timing row still judges its own world's CPU pressure.
# This script holds the lock and waits; the command runs with the lock's file
# descriptor closed, so no child inherits it. Exit status is the command's. TERM, INT and
# HUP sent to this wrapper are forwarded to the command as TERM.
# Waiters take slots in arrival order: each one writes a ticket under
# queue/ and tries the slots only while its ticket is the oldest live one,
# so a run that arrives late cannot pass one that waited longer (gen 49:
# polling alone let waits run 2 min for one lane and 91 min for another).
set -u
# Every test run stays in agents.slice (CPUWeight 25), below the owner's
# desktop in session.slice (owner, Slack 1794013926; Jarvis note 1794013972).
# A unit started without --slice=agents.slice lands in app.slice at the
# desktop's weight, so this wrapper refuses to run there.
if ! grep -q '/agents\.slice/' /proc/self/cgroup; then
  printf 'nested-slot: refused cause=outside-agents-slice cgroup=%s fix=start the unit with systemd-run --user --slice=agents.slice\n' "$(cut -d: -f3 /proc/self/cgroup)" >&2
  exit 2
fi
dir=/home/method/dev/vgshell/tmp/nested-slots
mkdir -p "$dir"
n=${NESTED_SLOTS:-8}
# A run naming no --rows (a full or range validation) also takes the one
# full-run lock (gen 276: such runs peak near 77 GB of the 123 GB host; three
# at once on 2026-11-09 18:00Z drove user-slice memory pressure to 89% and
# systemd-oomd killed every lane, the overseer and three validation units).
# Gen 280: off by default after VGS-2196, the last lane on a base before
# 3671c4331 (VGS-2424), landed; NESTED_FULL_LOCK=1 takes it again.
full=0
for ((a = 1; a <= $#; a++)); do
  if [ "${!a}" = --rows ]; then
    full=0
  fi
done
# A caller whose selection preview shows no `Jarvis audio owner` row (the ~75 GB
# row until VGS-2424 lands; other full runs peak at 16 GB or less) sets
# NESTED_FULL_LOCK=0 to skip the full-run lock (gen 276).
if [ "${NESTED_FULL_LOCK:-}" = 0 ]; then full=0; fi
if [ "${NESTED_FULL_LOCK:-}" = 1 ]; then full=1; fi
[ $# -gt 0 ] || { echo "nested-slot: no command" >&2; exit 2; }
# A command already running under a held slot (an outer nested-slot.sh call,
# such as a lane's named unit around `orch-runtime validate entry`, whose
# configured command calls this script again) runs at once: one run holds
# one slot.
if [ "${NESTED_SLOT_HELD:-}" = 1 ]; then exec "$@"; fi
start=$(date +%s)
# Run-time warning (gen 290, VGS-2465, Jarvis 1794460659/1794461043): past the
# expected time the run logs one warning line and goes on; no fixed-time stop.
# Temporary until kendex's warning ships (KEN-5083); the expected time is
# DEV_VALIDATE_EXPECTED_SECS, read where the run starts.
warn=
expected=$(.agents/skills/orch/scripts/orch-env DEV_VALIDATE_EXPECTED_SECS "" 2>/dev/null)
if [[ $expected =~ ^[1-9][0-9]*$ ]]; then
  ( trap 'kill "$s" 2>/dev/null; exit 0' TERM
    sleep "$expected" </dev/null >/dev/null 2>&1 & s=$!
    wait "$s" || exit 0
    printf 'nested-slot: warning run-time=over elapsed-secs=%s expected-secs=%s note="a time is a reading; do not drop or weaken a needed check to meet it"\n' \
      "$(( $(date +%s) - start ))" "$expected" >&2 ) &
  warn=$!
fi
q="$dir/queue"; mkdir -p "$q"
ticket="$q/$(date +%s%N)-$$"
: > "$ticket"
trap 'rm -f -- "${ticket:?}" "${ticket:?}.wait" "${ticket:?}.fullwait"; [ -n "$warn" ] && kill "$warn" 2>/dev/null' EXIT
trap 'exit 143' TERM INT HUP
head_of_queue() {
  local t pid
  for t in $(ls "$q" 2>/dev/null | grep -v -e '[.]wait$' -e '[.]fullwait$' | sort -n); do
    pid=${t#*-}
    if [ "$q/$t" = "$ticket" ]; then return 0; fi
    # A waiter the owner hold refuses steps aside, so admitted runs pass it.
    if [ -e "$q/$t.wait" ] && kill -0 "$pid" 2>/dev/null; then continue; fi
    # A full run waiting for full.lock keeps its place among full runs, so a
    # later full run cannot pass it, but a run that needs no full lock still
    # passes it (VGS-2328 run 4 was passed by VGS-2424's later ticket, gen 277).
    if [ -e "$q/$t.fullwait" ] && [ "$full" != 1 ] && kill -0 "$pid" 2>/dev/null; then continue; fi
    if kill -0 "$pid" 2>/dev/null && grep -qa nested-slot "/proc/$pid/cmdline" 2>/dev/null; then return 1; fi
    rm -f -- "${q:?}/$t"
  done
  return 1
}
load_ready() {
  local load rest
  if ! read -r load rest < /proc/loadavg || [[ ! $load =~ ^[0-9]+[.][0-9]+$ ]]; then
    printf 'nested-slot: held cause=load-unread\n' >&2
    return 1
  fi
  if (( ${load%%.*} >= 8 )); then
    printf 'nested-slot: held cause=host-load load=%s limit=8\n' "$load" >&2
    return 1
  fi
  return 0
}
while :; do
  # An owner hold (the overseer writes $dir/hold, gen 223, Jarvis 1793657330)
  # queues every new run until the file is removed at resume; a run already
  # holding a slot is not affected. A hold file whose first line names a
  # worktree admits only runs from that worktree (gen 284, Jarvis 1794366368:
  # VGS-2387 quiet-host timing measurement).
  if [ -e "$dir/hold" ]; then
    # gen 290: every line that starts with / names an admitted worktree.
    admitted=0
    while IFS= read -r allow; do
      case "$allow" in /*) case "$PWD/" in "$allow"/*) admitted=1 ;; esac ;; esac
    done < "$dir/hold"
    if [ "$admitted" != 1 ]; then : > "${ticket:?}.wait"; sleep 15; continue; fi
  fi
  rm -f -- "${ticket:?}.wait"
  if ! head_of_queue; then sleep 5; continue; fi
  if ! load_ready; then sleep 15; continue; fi
  exec {ffd}>/dev/null
  if [ "$full" = 1 ]; then
    exec {ffd}>"$dir/full.lock"
    if ! flock -n "$ffd"; then exec {ffd}>&-; : > "${ticket:?}.fullwait"; sleep 15; continue; fi
  fi
  for i in $(seq 1 "$n"); do
    exec {fd}>"$dir/slot-$i.lock"
    if flock -n "$fd"; then
      # Load can rise while the locks are acquired. Release before waiting.
      if ! load_ready; then exec {fd}>&-; break; fi
      rm -f -- "${ticket:?}" "${ticket:?}.wait" "${ticket:?}.fullwait"; trap - EXIT
      got=$(date +%s); now=$got
      echo "nested-slot: slot=$i full=$full waited=$(( now - start ))s slot_wait=$(( got - start ))s load=$(cut -d' ' -f1 /proc/loadavg) at=$(date -u +%FT%TZ) pid=$$ cwd=$PWD" | tee -a "$dir/log" >&2
      # The command runs as a child so a TERM, INT or HUP sent to this
      # wrapper reaches it (the GPU fence then cleans up its sandbox);
      # without forwarding, ending the wrapper orphaned the run (VGS-987).
      # A background command in a script starts with INT and QUIT ignored;
      # env puts them back so the command (the GPU fence) can handle them.
      env --default-signal=INT,QUIT NESTED_SLOT_HELD=1 XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" "$@" {fd}>&- {ffd}>&- <&0 &
      child=$!
      trap 'kill -TERM "$child" 2>/dev/null' TERM INT HUP
      wait "$child"; rc=$?
      while kill -0 "$child" 2>/dev/null; do wait "$child"; rc=$?; done
      [ -n "$warn" ] && kill "$warn" 2>/dev/null
      trap - TERM INT HUP
      echo "nested-slot: slot=$i released rc=$rc secs=$(( $(date +%s) - now )) at=$(date -u +%FT%TZ) pid=$$" >> "$dir/log"
      exit "$rc"
    fi
    exec {fd}>&-
  done
  exec {ffd}>&-
  sleep 5
done
