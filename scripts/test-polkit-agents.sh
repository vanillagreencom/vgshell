#!/usr/bin/env bash
# vgs.polkit's bin/agents and its two floating TUIs, tui/uninstall.sh and
# tui/stop.sh, against fakes alone. The suite runs inside a process
# namespace of its own, so the script's scan of /proc sees, and its SIGTERM
# reaches, only the stand-in agents the suite starts: copies of sleep named
# as a polkit agent is. A stand-in `vgsh` in a stand-in tree is the package
# manager: it answers `pkg owner` and `pkg removable` for those programs,
# and logs `pkg run remove` and exits with the status the row planted. No
# run reaches polkitd, a real agent, a package manager or sudo.
#
# It proves: `check` names each other agent of this system bus and this
# Hyprland instance with whether its package can be removed, and ends only
# the agents `stop` recorded; `uninstall` removes nothing while one agent's
# package is required or unowned, removes the packages and then ends the
# agents, and leaves them running when the removal fails; `stop` records
# and ends them and changes no package; an agent that does not end is
# refused; an agent that is not dumpable is counted, and recorded and ended
# again by its name, and a process of another user namespace or of a
# process namespace under the script's is not counted; a process that took
# an ended agent's pid is left alone; and each TUI script runs its own
# verb, only under the presenter.
#
# The controls at the end edit a copy of the plugin, one rule at a time, and
# require the rows to fail on each copy.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
for tool in unshare nsenter node python3 sleep setsid; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'test-polkit-agents: status=not-measured missing=%s\n' "$tool"
    exit 77
  fi
done
if [[ -z ${VGS_POLKIT_SUITE_NS:-} ]]; then
  if ! unshare -Urpf --mount-proc true 2>/dev/null; then
    printf 'test-polkit-agents: status=not-measured missing=process-namespace\n'
    exit 77
  fi
  VGS_POLKIT_SUITE_NS=1 exec unshare -Urpf --mount-proc "$self"
fi

TMP_ROOT="$(mktemp -d)" || { echo "test-polkit-agents: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $TMP_ROOT && ! -L $TMP_ROOT ]] || { echo "test-polkit-agents: scratch=not-a-directory value=[$TMP_ROOT]" >&2; exit 1; }
TMP_ROOT="$(cd -- "$TMP_ROOT" && pwd -P)" || { echo "test-polkit-agents: scratch=resolve-failed" >&2; exit 1; }
trap 'rm -rf -- "${TMP_ROOT:?}"' EXIT

failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

node_bin="$(node -e 'process.stdout.write(process.execPath)')"
world="$TMP_ROOT/world"
tree="$TMP_ROOT/tree"
programs="$TMP_ROOT/programs"
mkdir -p "$world" "$tree/bin/lib" "$programs" "$TMP_ROOT/home"
cp -- "$repo/bin/lib/qml-library.js" "$repo/bin/lib/tui.sh" "$tree/bin/lib/"
sleep_bin="$(command -v sleep)"
bash_bin="$(command -v bash)"
for name in polkit-acme-agent polkit-shared-agent polkit-lone-agent acme-daemon; do cp -- "$sleep_bin" "$programs/$name"; done
cp -- "$bash_bin" "$programs/polkit-deaf-agent"
cat >"$tree/bin/vgsh" <<SH
#!$bash_bin
printf '%s\n' "\$*" >>"$world/calls"
case "\$1 \$2" in
  "pkg owner")
    case "\$3" in
      */polkit-acme-agent) echo '{"manager":"pacman","package":"acme-polkit","version":"1.0"}' ;;
      */polkit-shared-agent) echo '{"manager":"pacman","package":"shared-polkit","version":"1.0"}' ;;
      */polkit-deaf-agent) echo '{"manager":"pacman","package":"deaf-polkit","version":"1.0"}' ;;
      *) echo "vgsh: refused: path=\$3 reason=unowned manager=pacman exit=1" >&2; exit 1 ;;
    esac ;;
  "pkg removable")
    case "\$3" in
      acme-polkit|deaf-polkit) echo "{\"manager\":\"pacman\",\"package\":\"\$3\",\"removable\":true}" ;;
      *) echo "{\"manager\":\"pacman\",\"package\":\"\$3\",\"removable\":false}" ;;
    esac ;;
  "pkg run")
    # The reused row: the agent named in the row's file exits during the
    # removal and a plain sleep takes its pid, the next the namespace
    # hands out once ns_last_pid names the one before it.
    if [[ -e "$world/reuse" ]]; then
      pid="\$(<"$world/reuse")"
      kill -KILL "\$pid"
      for _ in {1..500}; do [[ -d /proc/\$pid ]] || break; "$sleep_bin" 0.01; done
      echo "\$((pid - 1))" >/proc/sys/kernel/ns_last_pid
      "$sleep_bin" 300 </dev/null >/dev/null 2>&1 &
      echo "\$!" >"$world/reused"
    fi
    exit "\$(<"$world/remove-status")" ;;
  *) exit 99 ;;
esac
SH
chmod 755 "$tree/bin/vgsh"

# The environment of every run and of every stand-in agent of this session:
# no system bus address, as on a real system, and one Hyprland instance.
run_env=(env -i PATH="$(dirname -- "$node_bin"):/usr/bin:/bin" HOME="$TMP_ROOT/home" XDG_STATE_HOME="$TMP_ROOT/state" HYPRLAND_INSTANCE_SIGNATURE=suite)

# start NAME [ENV...]: a stand-in agent; its pid in $started. The job is
# disowned, so the shell prints nothing when a row or stop_all ends it. A
# row sleeps after its starts: a real wait, until each stand-in has run its
# program and /proc names it.
pids=()
start() {
  local name="$1"
  shift
  env -i HYPRLAND_INSTANCE_SIGNATURE=suite "$@" "$programs/$name" 300 &
  started=$!
  pids+=("$started")
  disown "$started"
}
alive() { [[ -d /proc/$1 ]] && [[ "$(awk '{print $3}' "/proc/$1/stat")" != Z ]]; }
# stop_all: ends every stand-in agent the rows left, and forgets the record.
stop_all() {
  local pid
  for pid in "${pids[@]}"; do kill -KILL "$pid" 2>/dev/null || true; done
  pids=()
  rm -rf -- "${TMP_ROOT:?}/state" "${world:?}/reuse" "${world:?}/reused"
  : >"$world/calls"
  echo 0 >"$world/remove-status"
}
# run PLUGIN VERB...: bin/agents of PLUGIN; exit status in $status, stdout
# in $out, stderr's first line in $first.
run() {
  local plugin="$1"
  shift
  status=0 first=""
  out="$("${run_env[@]}" "$plugin/bin/agents" --tree "$tree" "$@" 2>"$TMP_ROOT/err")" || status=$?
  [[ -s $TMP_ROOT/err ]] && IFS= read -r first <"$TMP_ROOT/err"
  return 0
}
# The agents of a check answer, sorted, as `name:removable` words, then the
# count it ended.
answer() { python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(" ".join(sorted(a["name"]+":"+str(a["removable"]).lower() for a in d["agents"])), d["stopped"])' "$out"; }
removals() { grep -c '^pkg run remove' "$world/calls" || true; }
expect() { # NAME WANT GOT
  if [[ $2 == "$3" ]]; then ok "$1"; else fail "$1: got [$3] want [$2]"; fi
}

# rows PLUGIN: every row but the slow one, against PLUGIN's copy of the
# plugin.
rows() {
  local plugin="$1" acme shared lone
  stop_all
  run "$plugin" check
  expect "check with no other agent" "0  0" "$status $(answer)"

  start polkit-acme-agent; acme=$started
  start acme-daemon
  start polkit-acme-agent DBUS_SYSTEM_BUS_ADDRESS=unix:path=/nowhere
  start polkit-acme-agent HYPRLAND_INSTANCE_SIGNATURE=another
  sleep 0.05
  run "$plugin" check
  expect "check names the one agent of this bus and this instance, by its package" "0 acme-polkit:true 0" "$status $(answer)"
  if alive "$acme"; then ok "check leaves an agent the user did not stop running"; else fail "check ended an agent the user did not stop"; fi

  start polkit-shared-agent; shared=$started
  sleep 0.05
  run "$plugin" check
  expect "check names a package another requires as not removable" "0 acme-polkit:true shared-polkit:false 0" "$status $(answer)"
  run "$plugin" uninstall
  expect "uninstall removes nothing while one agent's package is required" "1 0 polkit: refused: package=shared-polkit reason=required" "$status $(removals) $first"
  if alive "$acme" && alive "$shared"; then ok "a refused uninstall ends no agent"; else fail "a refused uninstall ended an agent"; fi

  stop_all
  start polkit-lone-agent; lone=$started
  sleep 0.05
  run "$plugin" check
  expect "check names a program no package owns by its file name, not removable" "0 polkit-lone-agent:false 0" "$status $(answer)"
  run "$plugin" uninstall
  expect "uninstall removes nothing for a program no package owns" "1 0 polkit: refused: program=polkit-lone-agent reason=unowned" "$status $(removals) $first"
  if alive "$lone"; then ok "the unowned agent still runs"; else fail "the unowned agent ended"; fi

  stop_all
  start polkit-acme-agent; acme=$started
  sleep 0.05
  echo 3 >"$world/remove-status"
  run "$plugin" uninstall
  expect "uninstall exits with the removal's status" "3 1" "$status $(removals)"
  if alive "$acme"; then ok "a failed removal ends no agent"; else fail "a failed removal ended the agent"; fi
  echo 0 >"$world/remove-status"
  : >"$world/calls"
  run "$plugin" uninstall
  expect "uninstall removes the agent's package through vgsh pkg run" "0 pkg run remove acme-polkit" "$status $(grep '^pkg run' "$world/calls")"
  if alive "$acme"; then fail "uninstall left the agent running"; else ok "uninstall ends the agent after the removal"; fi
  expect "uninstall records no program" no "$([[ -e $TMP_ROOT/state/vgs/polkit/stopped.json ]] && echo yes || echo no)"

  stop_all
  start polkit-shared-agent; shared=$started
  sleep 0.05
  run "$plugin" stop
  expect "stop changes no package" "0 0" "$status $(removals)"
  if alive "$shared"; then fail "stop left the agent running"; else ok "stop ends the agent"; fi
  expect "stop records the agent's program" "[\"$programs/polkit-shared-agent\"]" "$(cat "$TMP_ROOT/state/vgs/polkit/stopped.json" 2>/dev/null)"
  start polkit-shared-agent; shared=$started
  start polkit-acme-agent; acme=$started
  sleep 0.05
  run "$plugin" check
  expect "check ends the agent the user stopped before and names the other" "0 acme-polkit:true 1" "$status $(answer)"
  if alive "$shared"; then fail "check left a stopped agent running"; else ok "the stopped agent is gone"; fi
  if alive "$acme"; then ok "check leaves the other agent running"; else fail "check ended an agent the user did not stop"; fi

  stop_all
  status=0
  "${run_env[@]}" "$plugin/bin/agents" check >/dev/null 2>"$TMP_ROOT/err" || status=$?
  expect "a call without a tree is a bad invocation" "2 polkit: refused: usage" "$status $(head -n 1 "$TMP_ROOT/err")"

  # The TUI scripts: each runs its own verb, only under the presenter.
  local verb
  for verb in uninstall stop; do
    status=0
    "${run_env[@]}" "$plugin/tui/$verb.sh" >/dev/null 2>"$TMP_ROOT/err" || status=$?
    expect "tui/$verb.sh refuses outside the presenter" "2 polkit: refused: tui=missing" "$status $(head -n 1 "$TMP_ROOT/err")"
    stop_all
    start polkit-acme-agent; acme=$started
    sleep 0.05
    status=0
    "${run_env[@]}" VGS_TUI_LIB="$tree/bin/lib/tui.sh" VGS_PLUGIN_DIR="$plugin" "$plugin/tui/$verb.sh" >/dev/null 2>"$TMP_ROOT/err" || status=$?
    expect "tui/$verb.sh runs $verb" "0 $([[ $verb == uninstall ]] && echo 1 || echo 0) $([[ $verb == stop ]] && echo yes || echo no)" \
      "$status $(removals) $([[ -e $TMP_ROOT/state/vgs/polkit/stopped.json ]] && echo yes || echo no)"
    if alive "$acme"; then fail "tui/$verb.sh left the agent running"; else ok "tui/$verb.sh ends the agent"; fi
  done
  stop_all
}

# deaf PLUGIN: an agent that ignores SIGTERM is refused. The script waits its
# END_WAIT_MS for the process, so the row takes that long.
deaf() {
  local plugin="$1" pid
  stop_all
  env -i HYPRLAND_INSTANCE_SIGNATURE=suite "$programs/polkit-deaf-agent" -c 'trap "" TERM; while :; do sleep 1; done' &
  pid=$!
  pids+=("$pid")
  disown "$pid"
  sleep 0.3
  run "$plugin" stop
  expect "an agent that does not end is refused" "1 polkit: refused: agent=deaf-polkit reason=running" "$status $first"
  if alive "$pid"; then ok "the deaf agent still runs"; else fail "the deaf agent ended"; fi
  stop_all
}

# nodump PLUGIN: an agent that is not dumpable, as KDE's is, named
# polkit-kde-auth. Every other run is the namespace's root, which reads any
# process. The runs and the stand-in here are an unprivileged user of one
# further user namespace, which a held sleep keeps: there, as on a real
# system, the stand-in denies its environment and its program's path, and
# its /proc files are not the user's. The user's id there, 1000, is any id
# but root's. A dumpable stand-in of a second such
# namespace denies the same reads, and its files are the user's.
# start_nodump [PREFIX...]: the stand-in, started through PREFIX; its pid,
# or PREFIX's, in $started.
as_user=()
start_nodump() {
  rm -f -- "${world:?}/nodump-ready"
  "$@" "${as_user[@]}" env -i HYPRLAND_INSTANCE_SIGNATURE=suite python3 -c 'import ctypes, sys, time
libc = ctypes.CDLL(None)
libc.prctl(4, 0, 0, 0, 0)
libc.prctl(15, b"polkit-kde-auth", 0, 0, 0)
open(sys.argv[1], "w").close()
time.sleep(300)' "$world/nodump-ready" &
  started=$!
  pids+=("$started")
  disown "$started"
  # A real wait, until the stand-in has named itself.
  until [[ -e $world/nodump-ready ]]; do sleep 0.05; done
}
nodump() {
  local plugin="$1" pid holder
  stop_all
  unshare -U --map-user=1000 --map-group=1000 "$sleep_bin" 300 &
  holder=$!
  pids+=("$holder")
  disown "$holder"
  # A real wait, until unshare has written the namespace's user map.
  until [[ -n "$(cat "/proc/$holder/uid_map")" ]]; do sleep 0.05; done
  as_user=(nsenter --preserve-credentials -U -t "$holder")
  local run_env=("${as_user[@]}" "${run_env[@]}")
  unshare -U --map-user=1000 --map-group=1000 env -i HYPRLAND_INSTANCE_SIGNATURE=suite "$programs/polkit-acme-agent" 300 &
  pids+=("$!")
  disown "$!"
  sleep 0.05
  run "$plugin" check
  expect "check counts no dumpable agent of another user namespace" "0  0" "$status $(answer)"
  # The stand-in inside a process namespace under the suite's, as a
  # container's process is: unshare holds that namespace and takes the
  # stand-in with it when the row ends it.
  start_nodump unshare -pf --kill-child; pid=$started
  run "$plugin" check
  expect "check counts no agent of a process namespace under its own" "0  0" "$status $(answer)"
  kill -KILL "$pid"
  start_nodump; pid=$started
  run "$plugin" check
  expect "check names an agent that is not dumpable by its name, not removable" "0 polkit-kde-auth:false 0" "$status $(answer)"
  run "$plugin" stop
  expect "stop changes no package for an agent that is not dumpable" "0 0" "$status $(removals)"
  if alive "$pid"; then fail "stop left the agent that is not dumpable running"; else ok "stop ends the agent that is not dumpable"; fi
  expect "stop records an agent whose program cannot be read by its name" '["polkit-kde-auth"]' "$(cat "$TMP_ROOT/state/vgs/polkit/stopped.json" 2>/dev/null)"
  start_nodump; pid=$started
  run "$plugin" check
  expect "check ends the agent recorded by its name" "0  1" "$status $(answer)"
  if alive "$pid"; then fail "check left the agent recorded by its name running"; else ok "the agent recorded by its name is gone"; fi
  stop_all
}

# reused PLUGIN: the agent exits during the package removal and another
# process takes its pid before uninstall ends the agents. The stand-in vgsh
# does both, and the row first requires that the pid was taken.
reused() {
  local plugin="$1" acme other
  stop_all
  start polkit-acme-agent; acme=$started
  sleep 0.05
  echo "$acme" >"$world/reuse"
  run "$plugin" uninstall
  other="$(cat "$world/reused" 2>/dev/null)" || other=none
  [[ $other == none ]] || pids+=("$other")
  expect "a process started during the removal took the ended agent's pid" "0 $acme" "$status $other"
  if alive "$acme"; then ok "uninstall leaves the process that took the agent's pid alone"; else fail "uninstall ended the process that took the agent's pid"; fi
  stop_all
}

rows "$repo/shell/plugins/vgs.polkit"
deaf "$repo/shell/plugins/vgs.polkit"
nodump "$repo/shell/plugins/vgs.polkit"
reused "$repo/shell/plugins/vgs.polkit"

# Must-fail controls: a copy of the plugin with one rule edited must fail the
# rows.
control() { # NAME FILE NEEDLE REPLACEMENT [deaf]
  local copy="$TMP_ROOT/control-$1" got
  cp -R -- "$repo/shell/plugins/vgs.polkit" "$copy"
  NEEDLE="$3" REPLACEMENT="$4" python3 - "$copy/$2" <<'PY'
import os, sys
text = open(sys.argv[1]).read()
assert text.count(os.environ["NEEDLE"]) == 1, "control: the needle must match once: " + os.environ["NEEDLE"]
open(sys.argv[1], "w").write(text.replace(os.environ["NEEDLE"], os.environ["REPLACEMENT"]))
PY
  local before="$failures"
  got="$("${5:-rows}" "$copy"; echo "failed=$((failures - before))")"
  failures="$before"
  if [[ ${got##*failed=} != 0 ]]; then ok "control: $1"; else fail "control: $1 passed every row"; fi
}
control required-package-removed bin/agents 'if (!agent.removable) refuse(' 'if (false) refuse('
control unowned-program-removed bin/agents 'if (agent.package === null) refuse(' 'if (false) refuse('
control refusal-read-as-removable bin/agents 'removable: answer !== null && answer.removable === true,' 'removable: true,'
control check-ends-every-agent bin/agents 'filter(agent => list.indexOf(agent.key) !== -1)' 'filter(agent => true)'
control other-bus-counted bin/agents 'if (environValue(environ, "DBUS_SYSTEM_BUS_ADDRESS") !== process.env.DBUS_SYSTEM_BUS_ADDRESS) continue;' ''
control other-instance-counted bin/agents 'if (instance !== undefined && theirs !== undefined && theirs !== instance) continue;' ''
control stop-records-nothing bin/agents '        remember(agents.map(agent => agent.key));' ''
control stop-keeps-agents bin/agents $'        remember(agents.map(agent => agent.key));\n        endAll(agents);' '        remember(agents.map(agent => agent.key));'
control stop-removes-package bin/agents $'    if (verb === "stop") {\n' $'    if (verb === "stop") {\n        childProcess.spawnSync(VGSH, ["pkg", "run", "remove"], { stdio: "inherit" });\n'
control failed-removal-ends-agents bin/agents 'if (removal.status !== 0) return removal.status === null ? 1 : removal.status;' ''
control uninstall-keeps-agents bin/agents $'    if (removal.status !== 0) return removal.status === null ? 1 : removal.status;\n    endAll(agents);' '    if (removal.status !== 0) return removal.status === null ? 1 : removal.status;'
control tui-uninstall-runs-outside-presenter tui/uninstall.sh 'if [[ -z $lib || $tree == "$lib" || -z ${VGS_PLUGIN_DIR:-} ]]; then' 'if false; then'
control tui-stop-runs-outside-presenter tui/stop.sh 'if [[ -z $lib || $tree == "$lib" || -z ${VGS_PLUGIN_DIR:-} ]]; then' 'if false; then'
control tui-uninstall-stops tui/uninstall.sh '--tree "$tree" uninstall' '--tree "$tree" stop'
control tui-stop-uninstalls tui/stop.sh '--tree "$tree" stop' '--tree "$tree" uninstall'
control deaf-agent-read-as-ended bin/agents 'if (left.length > 0) refuse("agent="' 'if (false) refuse("agent="' deaf
control nondumpable-agent-skipped bin/agents '            if (!undumpable(pid) || contained(pid)) continue;' '            continue;' nodump
control other-user-namespace-counted bin/agents '            if (!undumpable(pid) || contained(pid)) continue;' '            if (contained(pid)) continue;' nodump
control contained-agent-counted bin/agents '            if (!undumpable(pid) || contained(pid)) continue;' '            if (!undumpable(pid)) continue;' nodump
control unreadable-program-not-recorded bin/agents 'key: file === null ? program : file' 'key: file === null ? "" : file' nodump
control reused-pid-ended bin/agents '        if (startOf(agent.pid) !== agent.start) continue;' '' reused

if [[ $failures -gt 0 ]]; then echo "test-polkit-agents: failed=$failures"; exit 1; fi
echo "test-polkit-agents: ok"
