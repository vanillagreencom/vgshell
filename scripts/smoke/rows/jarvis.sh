# Shared Jarvis smoke helpers and warning state for downstream rows.
# inputs: shell/plugins/vgs.jarvis/* bin/lib/account-folders.js scripts/fixtures/jarvis/* scripts/lib/jarvis-env.sh packaging/jarvis-home/* scripts/smoke/rows/plugins.sh scripts/smoke/rows/capabilities.sh shell/plugins/vgs.jarvis/backend/skills/*.md
set -euo pipefail

# A fixture selects disposable inputs; the leak owner never restores source
# bytes. Keep the run tree and its command directory untouched for successors.
jarvis_fixture_copy() { # NAME SOURCE COMMANDS
  local repo="$2"
  copy_tree "$1" || return 1
  mkdir -p -- "$sandbox/tree-$1/scripts/fixtures" "$sandbox/tree-$1/scripts/lib" "$sandbox/tree-$1/packaging" || return 1
  cp -R -- "$repo/scripts/fixtures/jarvis" "$sandbox/tree-$1/scripts/fixtures/jarvis" || return 1
  cp -- "$repo/scripts/lib/jarvis-env.sh" "$sandbox/tree-$1/scripts/lib/jarvis-env.sh" || return 1
  ln -s -- "$repo/scripts/smoke" "$sandbox/tree-$1/scripts/smoke" || return 1
  cp -R -- "$repo/packaging/jarvis-home" "$sandbox/tree-$1/packaging/jarvis-home" || return 1
  rm -rf -- "$sandbox/tree-$1.commands" || return 1
  mkdir -p -- "$sandbox/tree-$1.commands" || return 1
  [[ -z $3 ]] || cp -R -- "$3/." "$sandbox/tree-$1.commands/" || return 1
}
jarvis_fixture_begin() { # [SOURCE [COMMANDS]]
  local source="${1:-$repo}" commands="${2:-}" previous=""
  jarvis_fixture_serial=$((${jarvis_fixture_serial:-0} + 1))
  jarvis_fixture_name="$smoke_row_name-$BASHPID-$leak_seq-$jarvis_fixture_serial"
  jarvis_fixture_copy "$jarvis_fixture_name" "$source" "$commands" || return 1
  if [[ -n ${shell_qs_pid:-} ]]; then previous="$(jarvis_revision)" || return 1; fi
  if [[ -n ${jarvis_fixture_tree:-} && -n ${instance_log:-} ]]; then
    row_log_read "$smoke_row_name: fixture shell log" "$instance_log"
  fi
  stop_shell || return 1
  jarvis_fixture_tree="$sandbox/tree-$jarvis_fixture_name"
  jarvis_fixture_shim="$sandbox/tree-$jarvis_fixture_name.commands"
  start_shell "$jarvis_fixture_tree" "$smoke_log_dir/$jarvis_fixture_name.log" bar PATH="$jarvis_fixture_shim:$shim:$shell_host_path" || return 1
  jarvis_fixture_revision="$previous"
}
jarvis_fixture_terminal() {
  local tui_terminal="$jarvis_fixture_shim/${tui_terminal##*/}"
  local tui_terminal_written="$jarvis_fixture_shim/terminal-written"
  terminal_stand_in "$@"
}
jarvis_fixture_dictation() {
  local shell_start_path="$jarvis_fixture_shim:$shim:$shell_host_path"
  local shim="$jarvis_fixture_shim"
  dictation_stand_ins "$@"
}
jarvis_fixture_dictation_processes() {
  local shim="$jarvis_fixture_shim"
  dictation_processes "$@"
}
jarvis_fixture_resolves() {
  local shell_start_path="$jarvis_fixture_shim:$shim:$shell_host_path"
  shell_resolves "$@"
}
# Every row that starts the Jarvis fixtures declares this set, as the
# real daemon's fixtures provoke it: jarvis_provoked_errors is the one place.
jarvis_provoked_errors=()
jarvis_provoked_errors+=('WARN qml: jarvis: stderr=.*Killed.*')
jarvis_provoked_errors+=('WARN qml: jarvis: stderr=jarvis: node=21[.]0[.]0 need=22')
jarvis_provoked_errors+=('WARN qml: jarvis: hello=timeout')
jarvis_provoked_errors+=('WARN qml: jarvis: setup=probe-timeout check=[A-Za-z]+$')
jarvis_provoked_errors+=('WARN qml: jarvis: stderr=jarvis: fixture=warning')
jarvis_provoked_errors+=('.*jarvis-account-missing-helper.*')
# The readers log a failed check's safe cause; the page shows plain words.
jarvis_provoked_errors+=('WARN qml: jarvis-accounts: (process|output|diagnostic|added|directory|discovery)=[a-z-]+')
jarvis_provoked_errors+=('WARN qml: jarvis-keys: (presence|busctl)=[a-z-]+')
# The service logs a fault's, an audio fault's and an ended daemon's keyed
# cause; the bar and the page say what happened in plain words.
jarvis_provoked_errors+=('WARN qml: jarvis: (fault|audio-fault)=')
jarvis_provoked_errors+=('WARN qml: jarvis: ended cause=')
# Jarvis holds `dictation`, and the shell finds no voxtype: the core's probe
# does not start at each enable. Voice's toggle during Jarvis's recording
# logs the core's refusal.
jarvis_provoked_errors+=("${dictation_absent_errors[@]}")
jarvis_provoked_errors+=('WARN qml: voice: start refused: dictation=busy holder=vgs[.]jarvis$')
expected_errors+=("${jarvis_provoked_errors[@]}")

# Read the actual daemon below the Process-owned J09 launcher. PIDs come
# only from that launcher's /proc descendants, never a name-based search.
# The launcher exists before its daemon does, so the read polls every 20 ms
# until it finds exactly one daemon, for jarvis_daemon_bound_ms at most:
# the service's hello deadline (Service.qml helloDeadline), past which the
# service ends that launcher. It prints the PID, or exits 1 with a named
# cause on stderr: daemon-wait=launcher-ended (gone or a zombie) or
# daemon-wait=timeout.
jarvis_daemon_bound_ms=5000
jarvis_descendants() { # LAUNCHER_PID
  python3 - "$1" "$jarvis_daemon_bound_ms" <<'PY'
import pathlib, sys, time
launcher, bound_ms = int(sys.argv[1]), int(sys.argv[2])
deadline = time.monotonic() + bound_ms / 1000
def daemons():
    pending = [launcher]
    found = []
    while pending:
        pid = pending.pop()
        try:
            children = pathlib.Path(f"/proc/{pid}/task/{pid}/children").read_text().split()
            pending.extend(map(int, children))
            args = pathlib.Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
            executable = pathlib.Path(f"/proc/{pid}/exe").resolve().name
        except FileNotFoundError:
            continue
        if executable == "node" and any(arg.endswith(b"/backend/jarvisd.js") for arg in args):
            found.append(pid)
    return found
def running():
    try:
        stat = pathlib.Path(f"/proc/{launcher}/stat").read_text()
    except (FileNotFoundError, ProcessLookupError):
        return False
    return stat[stat.rindex(")") + 2] != "Z"
while True:
    found = daemons()
    if len(found) == 1:
        print(found[0])
        break
    if not running():
        sys.exit(f"jarvis-row: daemon-wait=launcher-ended daemon-count={len(found)} launcher={launcher}")
    if time.monotonic() >= deadline:
        sys.exit(f"jarvis-row: daemon-wait=timeout daemon-count={len(found)} bound_ms={bound_ms} launcher={launcher}")
    time.sleep(0.02)
PY
}

# Positive Settings setup cases need the plugin's required commands present.
# These scanner-facing stand-ins exit if called; J09 owns executable doubles.
jarvis_setup_requirements() { # COMMANDS
  local shell_start_path="$1:$shim:$shell_host_path"
  local shim="$1"
  local commands command
  jarvis_requirement_standins=()
  commands="$(python3 - "$repo/shell/plugins/vgs.jarvis/manifest.json" <<'PYTHON'
import json,sys
with open(sys.argv[1]) as source:
    manifest=json.load(source)
for row in manifest["requirements"]:
    if not row.get("optional", False):
        if "command" in row:
            print(row["command"])
PYTHON
)" || return 1
  while IFS= read -r command; do
    [[ $(shell_resolves "$command") == none ]] || continue
    (set -o noclobber; : >"$shim/$command") || return 1
    jarvis_requirement_standins+=("$command")
    printf '#!/bin/sh\nexit 99\n' >"$shim/$command" || return 1
    chmod 755 "$shim/$command" || return 1
  done <<<"$commands"
}
# A published ready value can precede the reader's queued initialization
# check. Wait for that check before changing the control's probe answer.
jarvis_setup_reader_idle() { # QML_TYPE
  ipc smoke itemValues service vgs.jarvis "$1" pending,code | py_reply '
import json,sys
rows=json.load(sys.stdin)
print("idle" if len(rows)==1 and rows[0]=={"pending":False,"code":0} else "pending")
'
}
# The run's end starts the Accounts discovery in the same change the core
# reports, so a reader with no discovery pending or starting has published
# the one that end asked for. A value the previous step left can match first.
jarvis_accounts_reader_idle() {
  ipc smoke itemValues service vgs.jarvis Accounts pending,completion | py_reply '
import json,sys
rows=json.load(sys.stdin)
print("idle" if len(rows)==1 and rows[0]["pending"] is False and rows[0]["completion"]["kind"] in ("exited","crashed") else "pending")
'
}

jarvis_restore_requirements() { # COMMANDS
  local shim="$1"
  local command result=0
  for command in "${jarvis_requirement_standins[@]}"; do
    rm -f -- "${shim:?}/$command" || result=1
  done
  rescan "the setup requirement stand-ins are removed" || result=1
  return "$result"
}

# jarvis_notice_close: the requirement notice enabling Jarvis raised while
# its required commands are missing goes on the scan that finds them, as
# in rows/jarvis-setup.sh; a scan raises no notice, so the stand-ins then
# go again and it stays closed. A row that raised it calls this before it
# ends, so no later row starts under it.
jarvis_notice_close() { # COMMANDS
  jarvis_setup_requirements "$1" || { fail "the Jarvis requirement stand-ins are not written"; return 1; }
  rescan "the scan that finds Jarvis's required commands"
  expect_poll "the scan that finds Jarvis's required commands closes its notice" 0 layer_count vgs:notice
  jarvis_restore_requirements "$1"
}

# Startup evidence excludes conversation text and separates a pre-launch
# publication return from a running child awaiting hello.
jarvis_startup() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
d=json.load(sys.stdin)
status=d.get("status",{})
detail=status.get("detail")
print(json.dumps({**{k:d.get(k) for k in ("pid","lifetime","retries","cause","audioHealth")},
    "gate":detail.get("state",{}).get("gate") if isinstance(detail,dict) else None,
    "setup":status.get("setup")}))
'
}
jarvis_enable() {
  expect "Jarvis enables" ok ipc shell setPluginEnabled vgs.jarvis true
  expect "the real Jarvis daemon answers hello" ready jarvis_wait_ready
  printf 'jarvis-startup='
  jarvis_startup
}
jarvis_revision() {
  ipc shell listPlugins | py_reply 'import json,sys; print(next(p["revision"] for p in json.load(sys.stdin)["plugins"] if p["id"] == "vgs.jarvis"))'
}

jarvis_launcher_pid() {
  local launcher
  if ! launcher="$(py_reply 'import json,sys; print(json.load(sys.stdin)["pid"])')" || [[ ! $launcher =~ ^[1-9][0-9]*$ ]]; then
    fail "Jarvis launcher PID is unavailable: value=$launcher"
    return 1
  fi
  printf '%s\n' "$launcher"
}

jarvis_rescan() {
  local before current
  if [[ -n ${jarvis_fixture_revision:-} ]]; then
    before="$jarvis_fixture_revision"
    jarvis_fixture_revision=""
  elif ! before="$(jarvis_revision)"; then fail "Jarvis revision is unreadable before rescan"; return 1; fi
  rescan "the changed Jarvis service rescans"
  if ! current="$(jarvis_revision)"; then fail "Jarvis revision is unreadable after rescan"; return 1; fi
  [[ $current == "$before" ]] || return 0
  fail "Jarvis source revision did not change"
  return 1
}

jarvis_no_pid() { # PID
  for ((attempt = 0; attempt < 200; attempt++)); do
    if [[ ! -e /proc/$1 ]]; then echo absent; return; fi
    sleep 0.01
  done
  echo present
}

# The service's launcher PID. Between a retry's backoff and its start the
# service reports none, so the read polls every 50 ms for
# jarvis_daemon_bound_ms at most, longer than the longest backoff
# (Service.qml retry.interval, 4000 ms). On the bound it prints
# launcher-wait=timeout with the last reading and returns 1.
jarvis_launcher_wait() {
  local deadline launcher
  deadline=$(( $(now_ms) + jarvis_daemon_bound_ms ))
  while :; do
    launcher="$(ipc smoke jarvisProcess | py_reply 'import json,sys; print(json.load(sys.stdin)["pid"])')" || true
    if [[ $launcher =~ ^[1-9][0-9]*$ ]]; then printf '%s\n' "$launcher"; return 0; fi
    if (( $(now_ms) >= deadline )); then
      printf 'jarvis-row: launcher-wait=timeout last=%s bound_ms=%s\n' "$launcher" "$jarvis_daemon_bound_ms"
      return 1
    fi
    sleep 0.05
  done
}

# A launcher or daemon that does not start fails the row, not the run:
# Jarvis still disables, so the rows after this one start with it off.
jarvis_disable() {
  local launcher daemon_pid=""
  if ! launcher="$(jarvis_launcher_wait)"; then
    fail "the Jarvis launcher is unreadable before disable: $launcher"
    launcher=""
  elif ! daemon_pid="$(jarvis_descendants "$launcher" 2>&1)"; then
    fail "the Jarvis daemon is unreadable before disable: $daemon_pid"
    daemon_pid=""
  fi
  expect "Jarvis disables" ok ipc shell setPluginEnabled vgs.jarvis false
  [[ -z $daemon_pid ]] || expect "disable releases the real daemon" absent jarvis_no_pid "$daemon_pid"
  [[ -z $launcher ]] || expect "disable releases the namespace launcher" absent jarvis_no_pid "$launcher"
  expect "disable drops the service" absent ipc smoke jarvisProcess
}
jarvis_session() { # EXPECTED_GATE_REASON
  ipc smoke jarvisProcess | py_reply '
import json,sys
d=json.load(sys.stdin)["status"].get("detail")
if d is None:
    print("pending")
else:
    s=d["state"]
    ok=(d["phase"] == "down" and d["seq"] >= 1 and s["gate"] == {"kind":"down","reason":sys.argv[1]}
        and s["capture"] == {"kind":"closed"} and s["action"] == {"kind":"none"} and s["gen"] == 1)
    print("session" if ok else "wrong-session")
' "$1"
}
jarvis_seen="$sandbox/jarvis-first-hello"
jarvis_seen_hello() {
  py_reply '
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
if not p.exists():
    print("pending")
else:
    # Other startup messages precede the hello answer. The gated status
    # proves the unlocked snapshot was answered before the row locks.
    lines=p.read_text().split("\n")[:-1]
    seen=any(d.get("type")=="status" and d.get("daemon")=="ready" for d in map(json.loads, lines))
    print("seen" if seen else "pending")
' "$jarvis_seen" <<<'{}'
}

jarvis_permanent() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
d=json.load(sys.stdin)
if d["retries"] != 0:
    print("retried")
elif (d["lifetime"]["kind"] == "problem" and d["pid"] is None and d["cause"] == "jarvis: node=21.0.0 need=22"
        and d["status"]["daemon"]["tone"] == "danger"):
    print("permanent")
else:
    print("pending")
'
}
jarvis_key_value() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
d=json.load(sys.stdin)
rows=d["status"].get("keys", [])
expected=[{"label":"fixture / test", "value":sys.argv[1]}]
print("matched" if rows == expected else "pending")
' "$1"
}
# The hint AccountStatus.js words for the fixture's team folder in STATE:
# signed in on plan pro as team@example.invalid, or found with neither. A
# found folder is signed out, so its row reads signed-out and carries no
# hint. A label names the provider and the sign-in email, the provider
# alone while the email is unknown, and never the folder.
jarvis_hint_of() { # STATE
  "$node_bin" -e '
const words = require(process.argv[1]);
const state = process.argv[2];
process.stdout.write(words.accountHint(state === "signed-in"
    ? { state, source: "cli", value: "present", plan: "pro", email: "team@example.invalid", mismatch: false }
    : { state, source: "cli", value: "signed-out", plan: "", email: "", mismatch: false }));' "$source_repo/shell/plugins/vgs.jarvis/AccountStatus.js" "$1"
}
jarvis_account_hint() {
  local want
  want="$(jarvis_hint_of "$1")" || return 1
  ipc smoke jarvisProcess | py_reply '
import json,sys
rows=json.load(sys.stdin)["status"].get("accounts", [])
found=sys.argv[2] == "found"
label="Claude Code" if found else "Claude Code, team@example.invalid"
ok=any(item["label"] == label and item["value"] == ("signed-out" if found else "present") and item.get("hint", "") == sys.argv[1] for item in rows)
print("matched" if ok else "pending")
' "$want" "$1"
}
