# Jarvis start bound: 107750 ms, from Service.qml's hello and retry timers,
# LocalSpeech.js's ready bound and LocalRuntime.qml's probe bound. Measured
# with scripts/jarvis-selftest.sh --cold 10 on 2026-10-10 in this lane:
# max setting 478 ms, CPU pressure some avg10=0.00 avg60=0.17 avg300=2.16.
# It polls once per nested IPC round trip.
# The real child runs inside J09, with synthetic audio commands and no
# account, real audio or desktop endpoint.
# The local voice's final words come from the core's `dictation` capability
# (D064, D106), over the shared voxtype stand-in on the shell's PATH, whose
# daemon hears the row's words; the sidecar is its stand-in too. While the
# shell finds no voxtype, Jarvis alone reads the core's daemon failed and
# its Voice step offers Set up dictation. With the stand-in and a disposable
# engine copy whose brain waits unanswered (scripted.js --dictation-brain),
# a held Talk with Jarvis the only holder records through the core: the
# stand-in's daemon notes a start and a stop, and the user's words are the
# stand-in's. The daemon killed during a recording, and the session locked
# during one, each leave no recording and a cancel note; its control is a
# service copy whose daemon end cancels nothing, which leaves the recording
# held. With Voice on too, Voice's toggle during a Jarvis recording answers
# busy and changes neither recording. With both off, no voxtype process
# runs. Each read polls once per nested IPC round trip.
# inputs: scripts/smoke/fixtures/voxtype/* shell/Core/Dictation.qml shell/Core/DictationModel.js shell/plugins/vgs.voice/* scripts/fixtures/jarvis-local-speech/standin.py shell/Core/Sounds.qml shell/plugins/vgs.launcher/* shell/plugins/vgs.jarvis/* bin/lib/account-folders.js bin/lib/codex-account.js bin/lib/anchored.js shell/Commons/AccountDirectories.js scripts/fixtures/jarvis/* scripts/fixtures/jarvis-setup/status.py scripts/smoke/fixtures/tui/vgs.jarvis/* shell/Core/TuiRunner.qml shell/Core/SessionLock.qml scripts/smoke/fixtures/plugins/acme.probe/* scripts/smoke/rows/capabilities.sh scripts/smoke/rows/plugins.sh scripts/smoke/rows/hyprland-consent.sh bin/vgshell-tui shell/Core/Notifier.qml shell/plugins/vgs.notifications/*
set -euo pipefail
expected_errors+=('WARN qml: jarvis: stderr=.*Killed.*')
expected_errors+=('WARN qml: jarvis: stderr=jarvis: node=21[.]0[.]0 need=22')
expected_errors+=('WARN qml: jarvis: hello=timeout')
expected_errors+=('WARN qml: jarvis: setup=probe-timeout check=[A-Za-z]+$')
expected_errors+=('WARN qml: jarvis: stderr=jarvis: fixture=warning')
expected_errors+=('.*jarvis-account-missing-helper.*')
# The readers log a failed check's safe cause; the page shows plain words.
expected_errors+=('WARN qml: jarvis-accounts: (process|output|diagnostic|added|directory|discovery)=[a-z-]+')
expected_errors+=('WARN qml: jarvis-keys: (presence|busctl)=[a-z-]+')
# The service logs a fault's, an audio fault's and an ended daemon's keyed
# cause; the bar and the page say what happened in plain words.
expected_errors+=('WARN qml: jarvis: (fault|audio-fault)=')
expected_errors+=('WARN qml: jarvis: ended cause=')
# Jarvis holds `dictation`, and the shell finds no voxtype: the core's probe
# does not start at each enable. Voice's toggle during Jarvis's recording
# logs the core's refusal.
expected_errors+=("${dictation_absent_errors[@]}")
expected_errors+=('WARN qml: voice: start refused: dictation=busy holder=vgs[.]jarvis$')

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
    except FileNotFoundError:
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
jarvis_setup_requirements() {
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
    printf '#!/bin/sh\nexit 99\n' >"$shim/$command"
    chmod 755 "$shim/$command"
    jarvis_requirement_standins+=("$command")
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

jarvis_restore_requirements() {
  local command
  for command in "${jarvis_requirement_standins[@]}"; do
    rm -f -- "${shim:?}/$command"
  done
  rescan "the setup requirement stand-ins are removed"
}

# jarvis_notice_close: the requirement notice enabling Jarvis raised while
# its required commands are missing goes on the scan that finds them, as
# in rows/jarvis-setup.sh; a scan raises no notice, so the stand-ins then
# go again and it stays closed. A row that raised it calls this before it
# ends, so no later row starts under it.
jarvis_notice_close() {
  jarvis_setup_requirements || { fail "the Jarvis requirement stand-ins are not written"; return 1; }
  rescan "the scan that finds Jarvis's required commands"
  expect_poll "the scan that finds Jarvis's required commands closes its notice" 0 layer_count vgs:notice
  jarvis_restore_requirements
}

jarvis_enable() {
  expect "Jarvis enables" ok ipc shell setPluginEnabled vgs.jarvis true
  expect "the real Jarvis daemon answers hello" ready jarvis_wait_ready
}

jarvis_reject_timeout_start() {
  (failures=0 behaviour_failures=0
   jarvis_enable >"$sandbox/jarvis-timeout-control-assertions.log"
   echo "$failures")
}

# The cards from Jarvis as [title, tone, icon].
jarvis_cards() { plugin_cards Jarvis | py_reply 'import json,sys; print(json.dumps([[r[0], r[3], r[4]] for r in json.load(sys.stdin)]))'; }
jarvis_unsent() { log_lines 'notify: unsent plugin=vgs\.jarvis '; }

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
  if ! before="$(jarvis_revision)"; then fail "Jarvis revision is unreadable before rescan"; return 1; fi
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

jarvis_exhaust() {
  local answer launcher daemon_pid retries kind
  for ((crash = 0; crash <= 5; crash++)); do
    answer="$(ipc smoke jarvisProcess)"
    launcher="$(jarvis_launcher_pid <<<"$answer")" || return 1
    daemon_pid="$(jarvis_descendants "$launcher" 2>&1)" || { printf '%s\n' "$daemon_pid"; return 1; }
    kill -KILL "$daemon_pid"
    # Wait for the service to observe this child exit, not just /proc loss.
    for ((attempt = 0; attempt < 300; attempt++)); do
      answer="$(ipc smoke jarvisProcess)"
      if ! kind="$(py_reply 'import json,sys; print(json.load(sys.stdin)["lifetime"]["kind"])' <<<"$answer")"; then
        fail "Jarvis lifetime is unreadable"
        return 1
      fi
      if ! retries="$(py_reply 'import json,sys; print(json.load(sys.stdin)["retries"])' <<<"$answer")" || [[ ! $retries =~ ^[0-9]+$ ]]; then
        fail "Jarvis retry count is unavailable: value=$retries"
        return 1
      fi
      if [[ $kind == problem || $retries -gt $crash ]]; then break; fi
      sleep 0.01
    done
    if [[ $crash -lt 5 ]]; then
      for ((ready_attempt = 0; ready_attempt < 1000; ready_attempt++)); do
        answer="$(jarvis_ready "$((crash + 1))")" || return 1
        [[ $answer != pending ]] || { sleep 0.01; continue; }
        break
      done
      if [[ $answer != ready ]]; then
        printf 'crash=%s readiness=%s\n' "$crash" "$answer"
        return 1
      fi
    fi
  done
  answer="$(ipc smoke jarvisProcess)"
  py_reply '
import json, sys
d = json.load(sys.stdin)
ok = d["lifetime"]["kind"] == "problem" and d["retries"] == 5 and d["pid"] is None
ok = ok and d["status"]["daemon"]["tone"] == "danger"
print("problem" if ok else "not-problem")
' <<<"$answer"
}

# The Daemon row, bar tooltip and Setup summary use plain words.
# The service log keeps the keyed cause.
jarvis_start_problem_words() {
  local process widget
  process="$(ipc smoke jarvisProcess)" || return
  widget="$(ipc smoke readInstance "$(bar_key)" vgs.jarvis view)" || return
  python3 - "$process" "$widget" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
widget = json.loads(sys.argv[2])
daemon = d["status"].get("daemon", {})
setup = d["status"].get("setup", {})
action = "Turn Jarvis off and on again in [Settings > Jarvis](page:vgs.jarvis/Settings)"
ok = d["lifetime"]["kind"] == "problem" and d["pid"] is None
ok = ok and daemon.get("tone") == "danger" and daemon.get("text") == "Jarvis did not answer in time"
ok = ok and daemon.get("lines") == ["Jarvis could not finish starting."] and daemon.get("hint") == action
ok = ok and setup.get("text") == "Jarvis did not answer in time"
ok = ok and setup.get("hint") == action and "lines" not in setup
ok = ok and widget.get("tooltip") == "Jarvis did not answer in time" and widget.get("tooltipDetails", [])[:1] == [action + "."]
ok = ok and not any("hello=timeout" in line for line in widget.get("tooltipDetails", []))
print("problem-words" if ok else "pending")
PY
}

jarvis_start_retry_words() {
  ipc smoke jarvisProcess | py_reply '
import json, sys
d = json.load(sys.stdin)
daemon = d["status"].get("daemon", {})
setup = d["status"].get("setup", {})
ok = d["lifetime"]["kind"] == "retry"
ok = ok and daemon.get("tone") == "warning" and daemon.get("text") == "Jarvis did not answer in time"
ok = ok and daemon.get("lines") == ["Jarvis could not finish starting."] and daemon.get("hint") == "Jarvis is trying again by itself"
ok = ok and setup.get("text") == "Jarvis did not answer in time"
ok = ok and setup.get("hint") == "Jarvis is trying again by itself"
ok = ok and "lines" not in setup
print("retry-words" if ok else "pending")
'
}

jarvis_probe_timeout_words() {
  local process widget
  process="$(ipc smoke jarvisProcess)" || return
  widget="$(ipc smoke readInstance "$(bar_key)" vgs.jarvis view)" || return
  python3 - "$process" "$widget" <<'PY'
import json, sys
status = json.loads(sys.argv[1])["status"]
widget = json.loads(sys.argv[2])
row = status.get("localRuntime", {})
setup = status.get("setup", {})
voice = status.get("setupVoice", {})
# The row is no open step under the ready summary: it offers no setup and
# draws no keyed cause, which the log keeps.
ok = row.get("tone") == "info" and row.get("text") == "Check did not finish"
ok = ok and row.get("action") is False and "lines" not in row
# The daemon never reads the probe timeout: the bar and the Setup status
# state the readiness of the daemon's own causes, the summary draws no
# keyed line, a ready bar shows it as a caution, and no step claims it.
ready = widget.get("state") == "ready"
ok = ok and ready == (setup.get("tone") == "ok") and "lines" not in setup
ok = ok and "jarvis: setup=probe-timeout" not in voice.get("lines", []) and "Check did not finish" not in voice.get("hint", "")
ok = ok and (not ready or setup.get("hint", "").rstrip(".") + "." in widget.get("tooltipDetails", []))
print("probe-timeout" if ok else "pending")
PY
}

jarvis_lock_assertion() { # expect | expect_poll
  "$1" "startup keeps the current lock snapshot without restarting" ready jarvis_ready 0
  "$1" "the reducer observes lock without capture" session jarvis_session locked
}

jarvis_lock_control() {
  (failures=0 behaviour_failures=0
   jarvis_lock_assertion expect >"$sandbox/jarvis-lock-control-assertions.log"
   echo "$failures")
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

# The Session state the service holds from the daemon, published or not,
# judged as jarvis_session judges the published one. A control that drops
# a publication waits for what its copy still does with the same message,
# then reads the assertion once: the publication had its turn in that
# handler, so no later read differs and none waits out the poll's 5 s.
jarvis_session_held() { # EXPECTED_GATE_REASON
  ipc smoke readInstance service vgs.jarvis sessionState | py_reply '
import json,sys
s=json.load(sys.stdin)
if s is None:
    print("pending")
else:
    ok=(s["gate"] == {"kind":"down","reason":sys.argv[1]} and s["capture"] == {"kind":"closed"}
        and s["action"] == {"kind":"none"} and s["gen"] == 1)
    print("held" if ok else "wrong-session")
' "$1"
}

jarvis_session_assertion() {
  (failures=0 behaviour_failures=0
   expect "the service consumes the real Session state" session jarvis_session unconfigured >"$sandbox/jarvis-session-control-assertions.log"
   echo "$failures")
}

# Whether the service has handled a device message: its handler reports
# the list ready after it publishes the offers.
jarvis_devices_handled() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
audio=json.load(sys.stdin)["status"].get("audio")
print("handled" if audio == {"tone":"ok","text":"Device list ready"} else "pending")
'
}

jarvis_devices_assertion() {
  (failures=0 behaviour_failures=0
   expect "the service publishes actual audio offers" devices jarvis_devices >"$sandbox/jarvis-devices-control-assertions.log"
   echo "$failures")
}

jarvis_audio_fault() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
d=json.load(sys.stdin)
ok=(d["status"].get("audio") or {}).get("tone")=="danger" and d["audioHealth"]=={"kind":"fault","reason":"capture-overflow"}
print("fault" if ok else "pending")
'
}

# The fixture's later list names one other microphone, so a service that
# publishes it has handled the device message that follows the fault.
jarvis_later_devices() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
status=json.load(sys.stdin)["status"]
print("later" if status.get("microphones")==[{"label":"System default","value":"@DEFAULT_AUDIO_SOURCE@"},{"label":"Later microphone","value":"fixture.later"}] else "pending")
'
}

jarvis_audio_recovered_assertion() {
  (failures=0 behaviour_failures=0
   expect "a device list after an audio fault clears the audio problem" handled jarvis_devices_handled >"$sandbox/jarvis-audio-fault-control-assertions.log"
   echo "$failures")
}

# The mute the service holds from the daemon's Session state.
jarvis_mute_held() {
  ipc smoke readInstance service vgs.jarvis sessionState | py_reply '
import json,sys
s=json.load(sys.stdin)
print("pending" if s is None else s["mute"]["kind"])
'
}

# A daemon that writes a warning to stderr and keeps running still takes
# intents. The mute round trip ends unmuted, so later cases start unmuted.
jarvis_stderr_case() {
  expect_poll "the daemon's warning reaches the log" logged jarvis_logged "jarvis: fixture=warning" "$jarvis_warnings"
  expect "mute reaches the daemon after its warning" ok ipc vgs.jarvis invoke mute ""
  expect_poll "the daemon mutes after its warning" on jarvis_mute_held
  expect "unmute reaches the daemon after its warning" ok ipc vgs.jarvis invoke mute ""
  expect_poll "the daemon unmutes after its warning" off jarvis_mute_held
  expect "the warning neither restarts nor ends the daemon" ready jarvis_ready 0
}

jarvis_stderr_assertion() {
  (failures=0 behaviour_failures=0
   jarvis_stderr_case >"$sandbox/jarvis-stderr-control-assertions.log"
   echo "$failures")
}

jarvis_transcript() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
t=json.load(sys.stdin)["status"].get("transcript")
print("current" if isinstance(t,dict) and t.get("text")=="current caption" and t.get("role")=="assistant" else "pending")
'
}

# The fixture writes the other generation's caption after the current
# one, so a service that publishes it has handled both.
jarvis_transcript_other() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
t=json.load(sys.stdin)["status"].get("transcript")
print("other" if isinstance(t,dict) and t.get("text")=="other caption" else "pending")
'
}

jarvis_transcript_assertion() { # expect | expect_poll
  (failures=0 behaviour_failures=0
   "$1" "the service publishes only the current generation's caption" current jarvis_transcript >"$sandbox/jarvis-transcript-control-assertions.log"
   echo "$failures")
}

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

jarvis_lock_case() { # real | control
  rm -f -- "$jarvis_gate" "$jarvis_seen"
  expect "the test-only holder unlocks before startup" ok probe unlock
  expect "the gated Jarvis service enables" ok ipc shell setPluginEnabled vgs.jarvis true
  # Each startup reader sends hello on completion. Finish those sends
  # before locking, so none can repair the control with a locked snapshot.
  # The local voice reader's end starts the cloned voice reader's check.
  expect_poll "the startup key reader is idle before locking" idle jarvis_setup_reader_idle Keys
  expect_poll "the startup local voice reader is idle before locking" idle jarvis_setup_reader_idle LocalRuntime
  expect_poll "the startup cloned voice reader is idle before locking" idle jarvis_setup_reader_idle CloneRuntime
  expect_poll "the startup account reader is idle before locking" idle jarvis_accounts_reader_idle
  expect_poll "the daemon has queued its unlocked hello answer" seen jarvis_seen_hello
  expect "the real test-only holder locks during startup" ok probe lock
  expect_poll "the compositor confirms the fixture lock" true read_service lockSecure
  : >"$jarvis_gate"
  if [[ $1 == real ]]; then
    jarvis_lock_assertion expect_poll
  else
    # Ready acknowledges that the mutant handled the withheld answer.
    # Its missing lock snapshot then fails the same assertion as above.
    expect_poll "the lock control handles the stale hello answer" ready jarvis_ready 0
    expect "the stale startup snapshot breaks the real lock assertion" 1 jarvis_lock_control
  fi
  expect "the fixture unlocks without authentication" ok probe unlock
  if [[ $1 == real ]]; then
    expect_poll "the reducer observes unlock without capture" session jarvis_session unconfigured
    expect "the running daemon stays ready without restarting" ready jarvis_ready 0
  fi
  expect "the gated service disables" ok ipc shell setPluginEnabled vgs.jarvis false
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

# A failed key check: no key rows, and the keyring row's warning that
# still offers Add key.
jarvis_key_unavailable() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
status=json.load(sys.stdin)["status"]
store=status.get("keyStore", {})
print("matched" if status.get("keys") == [] and store.get("tone") == "warning" and store.get("action") is True else "pending")
'
}
# The count of instance log lines holding TEXT, and `logged` once it
# passes BEFORE: a reader's safe cause reaches the log, not the page.
jarvis_log_count() { grep -c -F -- "$1" "$instance_log" || :; }
jarvis_logged() { # TEXT BEFORE
  local now
  now="$(jarvis_log_count "$1")"
  if (( now > $2 )); then echo logged; else echo pending; fi
}
# `plain` while no key or account row's hint or state text carries a
# key=value diagnostic or a helper's key prefix.
jarvis_status_plain() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
status=json.load(sys.stdin)["status"]
texts=[item.get("hint", "") for key in ("keys", "accounts") for item in status.get(key, [])]
texts+=[status.get(key, {}).get("text", "") for key in ("keyStore", "accountSearch")]
print("plain" if not any("=" in t or "jarvis-" in t for t in texts) else "diagnostic")
'
}

jarvis_enable
expect_poll "the healthy skeleton keeps the Session gate unconfigured" session jarvis_session unconfigured
expect_poll "Jarvis publishes only the fixture key presence" matched jarvis_key_value present
expect_poll "the real audio owner publishes stable microphone and speaker offers" devices jarvis_devices
jarvis_disable

mkdir -p -- "$home/.local/share/vgshell/jarvis/local/venv/bin" "$home/.local/state/vgshell/jarvis"
cp -- "$source_repo/scripts/fixtures/jarvis-local-speech/standin.py" "$home/.local/share/vgshell/jarvis/local/venv/bin/python"
chmod 700 -- "$home/.local/share/vgshell/jarvis/local/venv/bin/python"
python3 - "$repo/shell/plugins/vgs.jarvis/artifacts.json" "$home/.local/share/vgshell/jarvis/local" "$home/.local/state/vgshell/jarvis/local-ready.json" <<'PY'
import json, os, sys
tier = next(iter(json.load(open(sys.argv[1]))["tiers"]))
open(sys.argv[3], "w").write(json.dumps({"tier": tier, "data": os.path.realpath(sys.argv[2])}))
open(os.path.join(sys.argv[2], "scenario.json"), "w").write(json.dumps({"start": "ready"}))
PY
printf 'hang\n' >"$sandbox/jarvis-world/local-mode"
expect "the hanging setup-probe fixture enables" ok ipc shell setPluginEnabled vgs.jarvis true
expect_poll "the hanging setup-probe fixture reads its setup cause" probe-timeout jarvis_probe_timeout_words
expect_log "the log keeps the setup probe's keyed cause" 1 'WARN qml: jarvis: setup=probe-timeout check=localRuntime$'
expect "the hanging setup-probe fixture disables" ok ipc shell setPluginEnabled vgs.jarvis false
rm -f -- "$home/.local/state/vgshell/jarvis/local-ready.json"
printf 'absent\n' >"$sandbox/jarvis-world/local-mode"

jarvis_service="$repo/shell/plugins/vgs.jarvis/Service.qml"
jarvis_backend="$repo/shell/plugins/vgs.jarvis/backend/jarvisd.js"
cp -- "$jarvis_service" "$sandbox/jarvis-service-original"
cp -- "$jarvis_backend" "$sandbox/jarvis-backend-original"
jarvis_shell_owner="$repo/shell/plugins/vgs.jarvis/backend/Sandbox.js"
cp -- "$jarvis_shell_owner" "$sandbox/jarvis-shell-original"

# The disposable service exposes its ordinary launcher capability to the row.
# Both homes are accepted through the Settings write. No brain turn runs.
# J09 normally creates a fresh HOME and state on every daemon restart. This
# scoped lease keeps only this row's empty home history across those restarts.
jarvis_launcher_home="$sandbox/jarvis-launcher-home"
jarvis_launcher_lease="$sandbox/jarvis-launcher-lease.sh"
mkdir -p -- "$jarvis_launcher_home"
python3 - "$jarvis_launcher_lease" "$jarvis_launcher_home" <<'PYHOME'
from pathlib import Path
import shlex,sys
p=Path(sys.argv[1])
p.write_text('\n'.join(['#!/bin/bash', 'set -euo pipefail', 'exec 3<&0',
    'exec bash "$1" "$2" -- bash -c \'export HOME="$1" XDG_STATE_HOME="$1/.local/state"; shift; exec node "$@" <&3 3<&-\' jarvis-lease '+shlex.quote(sys.argv[2])+' "$3" --tree "$4"', '']))
p.chmod(0o700)
PYHOME
python3 - "$jarvis_service" "$sandbox/jarvis-world/lease.sh" "$jarvis_launcher_lease" <<'PYHOME'
from pathlib import Path
import json,sys
p=Path(sys.argv[1]); source=p.read_text()
lease=json.dumps(sys.argv[2])
assert source.count(lease)==1
source=source.replace(lease, json.dumps(sys.argv[3]))
needle='    function homeOffers(homes) {'
assert source.count(needle)==1
fixture='''    function fixtureHomeRows() { return JSON.stringify(shell.shortcut.rows("homes")); }
    function fixtureHomeActivate(item) { return shell.shortcut.activate("vgs.jarvis:home", item); }
    function fixtureHomeSet(value) { return shell.configure.set("home", value); }
'''
changed=source.replace(needle, fixture+needle)
assert changed != source
p.write_text(changed)
PYHOME
cp -- "$jarvis_service" "$sandbox/jarvis-home-fixture"
jarvis_rescan
jarvis_enable
jarvis_home_set() { ipc smoke invokeInstance service vgs.jarvis fixtureHomeSet "$1"; }
jarvis_home_held() {
  ipc smoke readInstance service vgs.jarvis homeMessage | py_reply 'import json,sys; print(json.load(sys.stdin)["current"])'
}
jarvis_home_current() {
  ipc smoke jarvisProcess | py_reply 'import json,sys
status=json.load(sys.stdin)["status"]
rows=status.get("homeRows", [])
chosen=[row["label"] for row in rows if row["icon"]=="folder-check"]
home=status.get("setupHome", {})
print(chosen[0] if len(chosen)==1 and home.get("tone")=="ok" and home.get("hidden") is not True else "pending")'
}
jarvis_home_rows() {
  ipc smoke invokeInstance service vgs.jarvis fixtureHomeRows "" | py_reply 'import hashlib,json,sys
rows=json.load(sys.stdin)
expected={"~/Launcher One", "~/Launcher Two"}
valid={row["label"] for row in rows}==expected
for row in rows:
    label=row["label"]
    current=label==sys.argv[2]
    expected_id="h"+hashlib.sha256((sys.argv[1]+"/"+label[2:]).encode()).hexdigest()[:12]
    valid=valid and row["id"]=="homes."+expected_id and row["item"]==expected_id and row["shortcut"]=="vgs.jarvis:home"
    valid=valid and row["icon"]==("folder-check" if current else "folder")
    valid=valid and row["description"]==("Current" if current else "")
print("listed" if valid else "pending")' "$jarvis_launcher_home" "$1"
}
jarvis_home_activate() { ipc smoke invokeInstance service vgs.jarvis fixtureHomeActivate "$1"; }
jarvis_home_saved() {
  python3 - "$home/.config/vgshell/shell.json" <<'PYHOME'
import json,sys
config=json.load(open(sys.argv[1]))
print(next(p for p in config["plugins"] if p["id"]=="vgs.jarvis").get("home", ""))
PYHOME
}
expect "the first launcher home is configured" ok jarvis_home_set "~/Launcher One"
expect_poll "the first launcher home is accepted" "~/Launcher One" jarvis_home_current
expect "the second launcher home is configured" ok jarvis_home_set "~/Launcher Two"
expect_poll "both launcher homes appear with the accepted home marked" listed jarvis_home_rows "~/Launcher Two"
printf 'jarvis-home-message=%s\n' "$(ipc smoke readInstance service vgs.jarvis homeMessage)"
printf 'jarvis-home-rows=%s\n' "$(ipc smoke invokeInstance service vgs.jarvis fixtureHomeRows "")"
jarvis_home_first="$(python3 - "$jarvis_launcher_home/Launcher One" <<'PYHOME'
import hashlib,sys
print("h"+hashlib.sha256(sys.argv[1].encode()).hexdigest()[:12])
PYHOME
)" || { fail "the first home id is unavailable"; return 1; }
expect "a home id no published row holds is refused" "refused: shortcut=vgs.jarvis:home item=h000000000000 reason=unlisted" jarvis_home_activate h000000000000
expect "an unlisted home id writes no setting" "~/Launcher Two" jarvis_home_saved
expect "the other launcher home activates" ok jarvis_home_activate "$jarvis_home_first"
expect "the launcher writes the Home folder setting" "~/Launcher One" jarvis_home_saved
expect_poll "the next status accepts the selected launcher home" "~/Launcher One" jarvis_home_current
expect "reordering keeps both launcher row ids and the current mark" listed jarvis_home_rows "~/Launcher One"
# Read the right-edge Text children, including the other home's empty text.
jarvis_home_detail() {
  ipc smoke itemValues overlay vgs.launcher QQuickText parent.label,parent.kind,text,x,width,parent.width | py_reply 'import json,sys
rows=[r for r in json.load(sys.stdin) if r.get("parent.kind")=="plugin"]
valid=all(r["text"]=="" or r["x"]>r["parent.width"]/2 for r in rows)
print(json.dumps(sorted([[r["parent.label"],r["text"]] for r in rows])) if valid else "misplaced")'
}
jarvis_notice_close
expect "the launcher enables for Jarvis homes" ok ipc shell setPluginEnabled vgs.launcher true
expect "the launcher opens Jarvis homes" ok ipc shell summon overlay vgs.launcher '{"menu":"homes"}'
expect_poll "only the current home has right-edge text" '[["~/Launcher One", "Current"], ["~/Launcher Two", ""]]' jarvis_home_detail
expect "the launcher searches the current home" ok ipc shell summon overlay vgs.launcher '{"menu":"homes","query":"Launcher One"}'
expect_poll "search shows no right-edge copy" '[["~/Launcher One", ""]]' jarvis_home_detail
expect "search keeps its detail line" true ipc smoke readMatchingDescendant overlay vgs.launcher LauncherRow label "~/Launcher One" showsDetail
expect "the home search hides" ok ipc shell hide overlay vgs.launcher
jarvis_home_row="$repo/shell/plugins/vgs.launcher/LauncherRow.qml"
cp -- "$jarvis_home_row" "$sandbox/jarvis-home-row-kept"
python3 - "$jarvis_home_row" <<'PYROW'
from pathlib import Path
import sys
p=Path(sys.argv[1]); source=p.read_text()
start=source.index('    // Qt Text elides only')
end=source.index('    ChevronGlyph {', start)
old='rightDetail.text.length > 0 ? rightDetail.left : chevron.left'
assert source.count(old)==1
changed=(source[:start]+source[end:]).replace(old, 'chevron.left')
assert changed != source
p.write_text(changed)
PYROW
rescan "the launcher row before the right-edge change builds"
expect "the previous row opens Jarvis homes" ok ipc shell summon overlay vgs.launcher '{"menu":"homes"}'
jarvis_home_list_count() { ipc smoke launcherRows overlay vgs.launcher | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
expect_poll "the previous row lists both homes" 2 jarvis_home_list_count
jarvis_home_detail_control() {
  (failures=0 behaviour_failures=0
   expect "the current home has right-edge text" '[["~/Launcher One", "Current"], ["~/Launcher Two", ""]]' jarvis_home_detail >"$sandbox/jarvis-home-detail-control.log"
   echo "$failures")
}
expect "the previous row fails the right-edge assertion" 1 jarvis_home_detail_control
expect "the previous row hides" ok ipc shell hide overlay vgs.launcher
cp -- "$sandbox/jarvis-home-row-kept" "$jarvis_home_row"
rescan "the right-edge home detail returns"
expect "the launcher disables after Jarvis homes" ok ipc shell setPluginEnabled vgs.launcher false
jarvis_disable
# Each control keeps its handler and removes only its effect.
for jarvis_home_control in publish write; do
  python3 - "$jarvis_service" "$jarvis_home_control" <<'PYHOME'
from pathlib import Path
import sys
p=Path(sys.argv[1]); source=p.read_text()
needle,replacement={"publish": ('["homeRows", rows]', '["homeRows", []]'),
    "write": ('const reply = shell.configure.set("home", choice.value);', 'const reply = "ok";')}[sys.argv[2]]
assert source.count(needle)==1
changed=source.replace(needle,replacement)
assert changed != source
p.write_text(changed)
PYHOME
  jarvis_rescan
  jarvis_enable
  if [[ $jarvis_home_control == publish ]]; then
    # The held message proves the handler consumed its accepted snapshot.
    expect_poll "the publication control holds the current home" "~/Launcher One" jarvis_home_held
    jarvis_home_control_result() {
      (failures=0 behaviour_failures=0
       expect "published home rows reach the launcher" listed jarvis_home_rows "~/Launcher One" >"$sandbox/jarvis-home-publish-control.log"
       echo "$failures")
    }
  else
    expect "the write control restores the first home after clearing" ok jarvis_home_set "~/Launcher One"
    expect_poll "the write control lists both homes" listed jarvis_home_rows "~/Launcher One"
    expect "the write control accepts the published second home" ok jarvis_home_set "~/Launcher Two"
    expect_poll "the write control starts with the second home" "~/Launcher Two" jarvis_home_current
    expect "the write control still activates the listed first home" ok jarvis_home_activate "$jarvis_home_first"
    jarvis_home_control_result() {
      (failures=0 behaviour_failures=0
       expect "the launcher must write the selected setting" "~/Launcher One" jarvis_home_saved >"$sandbox/jarvis-home-write-control.log"
       echo "$failures")
    }
  fi
  expect "the $jarvis_home_control control breaks its consumer assertion" 1 jarvis_home_control_result
  expect "the control clears the home without a brain turn" ok jarvis_home_set ""
  jarvis_disable
  cp -- "$sandbox/jarvis-home-fixture" "$jarvis_service"
done
jarvis_rescan
jarvis_enable
expect "the home row leaves no home set" "" jarvis_home_saved
expect "the accepted home is empty after clearing" "" jarvis_home_held
jarvis_disable

# One typed turn on the scripted chained brain with a home set, inside the
# same lease: the engine composes the home's layers over the fixture plan's
# guidance, and the reply reaches the transcript. The fixture's reply gate
# polls every 10 ms. The home clears before the next scripted row.
jarvis_engine="$repo/shell/plugins/vgs.jarvis/backend/ChainedEngine.js"
cp -- "$jarvis_engine" "$sandbox/jarvis-engine-original"
jarvis_turn_gates="$sandbox/jarvis-home-turn-gates"
"$node_bin" "$source_repo/scripts/fixtures/jarvis/scripted.js" "$jarvis_backend" "$jarvis_turn_gates"
"$node_bin" "$source_repo/scripts/fixtures/jarvis/scripted.js" --chained-engine "$jarvis_engine"
jarvis_rescan
jarvis_enable
jarvis_home_reply() {
  ipc smoke statusValues vgs.jarvis | py_reply 'import json,sys
t=json.load(sys.stdin)["transcript"]
print("replied" if t is not None and t["role"] == "assistant" and "scripted reply" in t["text"] else "pending")'
}
expect "the turn's home is configured" ok jarvis_home_set "~/Launcher One"
expect_poll "the turn's home is accepted" "~/Launcher One" jarvis_home_current
expect "Jarvis takes typed words with a home set" ok ipc vgs.jarvis invoke say "Tell me something."
: >"$jarvis_turn_gates/reply"
expect_poll "the scripted brain replies with a home set" replied jarvis_home_reply
expect "the turn's home clears" ok jarvis_home_set ""
expect_poll "no home is held after the turn" "" jarvis_home_held
jarvis_disable
cp -- "$sandbox/jarvis-backend-original" "$jarvis_backend"
cp -- "$sandbox/jarvis-engine-original" "$jarvis_engine"
rm -- "${repo:?}/shell/plugins/vgs.jarvis/backend/scripted-fixture.js"
cp -- "$sandbox/jarvis-service-original" "$jarvis_service"
jarvis_rescan

# Kernel behavior is exercised through the real tool by the offline shell
# row. These scoped readiness fixtures isolate daemon-to-service delivery.
jarvis_shell_status() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
want = {"ready": {"tone":"ok", "text":"Ready"},
        "missing": {"tone":"warning", "text":"Unavailable", "hint":"[Review all missing or outdated tools on Setup](page:vgs.jarvis/Setup) to enable shell commands"}}[sys.argv[1]]
print("matched" if json.load(sys.stdin)["status"].get("shell") == want else "pending")
' "$1"
}
jarvis_shell_assertion() {
  (failures=0 behaviour_failures=0
   expect_poll "the service publishes shell readiness" matched jarvis_shell_status ready >"$sandbox/jarvis-shell-control.log"
   echo "$failures")
}
"$node_bin" "$source_repo/scripts/fixtures/jarvis/prepare.js" --shell-availability "$jarvis_shell_owner" available
jarvis_rescan
jarvis_enable
expect_poll "the service reports a confined shell executor ready" matched jarvis_shell_status ready
jarvis_disable
python3 - "$jarvis_service" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); source=p.read_text()
needle='const result = shell.status.set("shell", value);'
assert source.count(needle)==1
changed=source.replace(needle, 'const result = false ? shell.status.set("shell", value) : "ok";')
assert changed != source
p.write_text(changed)
PY
jarvis_rescan
jarvis_enable
expect "removing shell status publication breaks its consumer assertion" 1 jarvis_shell_assertion
jarvis_disable
cp -- "$sandbox/jarvis-service-original" "$jarvis_service"
cp -- "$sandbox/jarvis-shell-original" "$jarvis_shell_owner"
"$node_bin" "$source_repo/scripts/fixtures/jarvis/prepare.js" --shell-availability "$jarvis_shell_owner" unavailable
jarvis_rescan
jarvis_enable
expect_poll "missing confinement exposes the one-click requirement action" matched jarvis_shell_status missing
jarvis_disable
cp -- "$sandbox/jarvis-shell-original" "$jarvis_shell_owner"
jarvis_rescan

# Installation completion requests the ordinary core scan. It does not
# change plugin source or restart its service. The fixture never installs.
jarvis_shell_state="$sandbox/jarvis-shell-state.json"
jarvis_shell_evidence="$sandbox/jarvis-shell-evidence.json"
jarvis_shell_put() {
  printf '%s\n' "$1" >"$jarvis_shell_state.next"
  mv -- "$jarvis_shell_state.next" "$jarvis_shell_state"
}
jarvis_shell_offers() {
  python3 - "$jarvis_shell_evidence" "$1" <<'PYREAD'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
if not p.exists(): print("pending"); sys.exit(0)
d=json.loads(p.read_text())
want=sys.argv[2]
offers=[v for v in d["offers"] if v.startswith("shell.")]
valid=d["scan"] >= 0 and d["availability"]["kind"] == want
valid=valid and offers == (["shell.argv","shell.line"] if want == "available" else [])
print("matched" if valid else "pending")
PYREAD
}
jarvis_shell_dependency_scan() {
  local pid before
  if ! before="$(jarvis_revision)"; then fail "Jarvis revision is unreadable before dependency scan"; return 1; fi
  if ! pid="$(ipc smoke jarvisProcess | jarvis_launcher_pid)"; then return 1; fi
  jarvis_shell_put '{"kind":"available"}'
  rescan "dependency installation completion uses the core rescan"
  expect_poll "completed dependency scan refreshes shell readiness" matched jarvis_shell_status ready
  expect_poll "completed dependency scan exposes both actual router offers" matched jarvis_shell_offers available
  expect "dependency scan retains plugin source revision" "$before" jarvis_revision
  local after
  if ! after="$(ipc smoke jarvisProcess | jarvis_launcher_pid)"; then return 1; fi
  expect "dependency scan retains the daemon lease" "$pid" printf '%s' "$after"
}
jarvis_shell_rescan_assertion() {
  (failures=0 behaviour_failures=0
   jarvis_shell_dependency_scan >"$sandbox/jarvis-shell-rescan-control.log"
   echo "$failures")
}
jarvis_shell_put '{"kind":"unavailable","reason":"bwrap-missing"}'
"$node_bin" "$source_repo/scripts/fixtures/jarvis/prepare.js" --shell-state "$jarvis_shell_owner" "$jarvis_backend" "$jarvis_shell_state" "$jarvis_shell_evidence"
jarvis_rescan
jarvis_enable
expect_poll "the retained service starts with unavailable confinement" matched jarvis_shell_status missing
expect_poll "the first requirement observation reaches the readiness owner" matched jarvis_shell_offers unavailable
jarvis_shell_dependency_scan
jarvis_shell_put '{"kind":"unavailable","reason":"bwrap-missing"}'
rescan "dependency loss uses the same core rescan"
expect_poll "dependency loss removes readiness" matched jarvis_shell_status missing
expect_poll "dependency loss removes both shell offers" matched jarvis_shell_offers unavailable
jarvis_disable
cp -- "$sandbox/jarvis-service-original" "$jarvis_service"
python3 - "$jarvis_service" <<'PYCONTROL'
from pathlib import Path
import sys
p=Path(sys.argv[1]); source=p.read_text()
# Keep the initial observation but block later scans from every caller.
needle='|| requirementsRevision <= sentRequirementsRevision) return;'
assert source.count(needle)==1
changed=source.replace(needle, '|| sentRequirementsRevision >= 0 || requirementsRevision <= sentRequirementsRevision) return;')
assert changed != source
p.write_text(changed)
PYCONTROL
jarvis_shell_put '{"kind":"unavailable","reason":"bwrap-missing"}'
jarvis_rescan
jarvis_enable
expect_poll "the control reaches initial missing readiness" matched jarvis_shell_offers unavailable
expect "removing later requirement scan delivery breaks recovery" 2 jarvis_shell_rescan_assertion
jarvis_disable
cp -- "$sandbox/jarvis-service-original" "$jarvis_service"
cp -- "$sandbox/jarvis-backend-original" "$jarvis_backend"
cp -- "$sandbox/jarvis-shell-original" "$jarvis_shell_owner"
jarvis_rescan

# The control keeps the receive branch but removes its publication. The
# ordinary state read, not a text pin, must fail on this disposable copy.
python3 - "$jarvis_service" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
needle='const result = shell.status.set("detail", { phase: message.phase, seq: message.seq, state: message.state, brain: message.brain });'
assert s.count(needle)==1
changed=s.replace(needle, needle.replace("= shell.status", "= false ? shell.status").replace(" });", ' }) : "ok";'))
assert changed != s
p.write_text(changed)
PY
jarvis_rescan
jarvis_enable
expect_poll "the control's service holds the Session state it does not publish" held jarvis_session_held unconfigured
expect "removing Session publication breaks its real consumer assertion" 1 jarvis_session_assertion
jarvis_disable
cp -- "$sandbox/jarvis-service-original" "$jarvis_service"
jarvis_rescan

# Feedback sounds: the choice for the manifest's `feedback` sound event,
# shell.json `sounds`, which the Sounds page writes, reaches the service
# and, in a new hello, the daemon, whose Session settings say whether its
# tones play. Two disposable copies each fail the Off reading: a service
# that does not read the choice, and one that reads it and sends no hello.
jarvis_sounds_config="$home/.config/vgshell/shell.json"
# The service's reading of the choice, then the published Session
# settings' `sounds`, `pending` before a Session state is published.
jarvis_sounds_sent() { ipc smoke jarvisProcess | py_reply 'import json,sys; d=json.load(sys.stdin)["status"].get("detail"); print("pending" if d is None else json.dumps(d["state"]["settings"].get("sounds")))'; }
jarvis_sounds() {
  local held sent
  held="$(ipc smoke readInstance service vgs.jarvis feedbackSounds)" || return
  sent="$(jarvis_sounds_sent)" || return
  printf '%s %s\n' "$held" "$sent"
}
# The Off choice goes into the file as it is with Jarvis enabled, and
# jarvis_sounds_back puts that file back.
jarvis_sounds_off() {
  cp -- "$jarvis_sounds_config" "$sandbox/shell-before-jarvis-sounds.json"
  python3 -c 'import json,os,sys
path = sys.argv[1]
config = json.load(open(path))
config.setdefault("sounds", {}).setdefault("vgs.jarvis", {})["feedback"] = ""
with open(path + ".next", "w") as out:
    json.dump(config, out)
os.replace(path + ".next", path)' "$jarvis_sounds_config" || fail "the Jarvis Off choice could not be written"
  expect "the Jarvis Off choice is reloaded" ok ipc shell reloadConfig
}
jarvis_sounds_back() {
  cp -- "$sandbox/shell-before-jarvis-sounds.json" "$jarvis_sounds_config.next" && mv -T -- "$jarvis_sounds_config.next" "$jarvis_sounds_config"
  expect "the shell.json the Jarvis sound part found is reloaded" ok ipc shell reloadConfig
}
jarvis_sounds_assertion() {
  (failures=0 behaviour_failures=0
   expect_poll "the Off choice reaches the service and the daemon's Session settings" "false false" jarvis_sounds >"$sandbox/jarvis-sounds-control-assertions.log"
   echo "$failures")
}
jarvis_sounds_control() { # LABEL NEEDLE REPLACEMENT
  python3 -c 'import sys
from pathlib import Path
path = Path(sys.argv[1])
source = path.read_text()
assert source.count(sys.argv[2]) == 1
path.write_text(source.replace(sys.argv[2], sys.argv[3]))' "$jarvis_service" "$2" "$3" || fail "$1: the disposable service copy could not be written"
  jarvis_rescan
  jarvis_enable
  expect_poll "$1: the daemon starts with feedback sounds on" true jarvis_sounds_sent
  # Each startup reader sends hello on completion. Finish those sends
  # before the choice, so none can repair the control with its snapshot.
  # The local voice reader's end starts the cloned voice reader's check.
  expect_poll "$1: the startup key reader is idle" idle jarvis_setup_reader_idle Keys
  expect_poll "$1: the startup local voice reader is idle" idle jarvis_setup_reader_idle LocalRuntime
  expect_poll "$1: the startup cloned voice reader is idle" idle jarvis_setup_reader_idle CloneRuntime
  expect_poll "$1: the startup account reader is idle" idle jarvis_accounts_reader_idle
  jarvis_sounds_off
  expect "$1 breaks the Off reading" 1 jarvis_sounds_assertion
  jarvis_sounds_back
  jarvis_disable
  cp -- "$sandbox/jarvis-service-original" "$jarvis_service"
  jarvis_rescan
}
jarvis_enable
expect_poll "with no choice the service and the daemon have feedback sounds on" "true true" jarvis_sounds
jarvis_sounds_off
expect_poll "the Off choice reaches the service and the daemon's Session settings" "false false" jarvis_sounds
jarvis_sounds_back
expect_poll "without the choice the service and the daemon have feedback sounds on again" "true true" jarvis_sounds
jarvis_disable
jarvis_sounds_control "a service that does not read the choice" 'shell !== null && shell.sounds.choices.feedback !== ""' 'shell !== null'
jarvis_sounds_control "a service that sends no hello on the choice" 'onFeedbackSoundsChanged: hello()' 'onFeedbackSoundsChanged: {}'

# Keep the branch, but omit its status write. The real offers assertion fails
# before any microphone or speaker can start.
python3 - "$jarvis_service" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
needle='const reply = shell.status.set(key, deviceOffers(key, message[key]));'
assert s.count(needle)==1
changed=s.replace(needle, 'const reply = false ? shell.status.set(key, deviceOffers(key, message[key])) : "ok";')
assert changed != s
p.write_text(changed)
PY
jarvis_rescan
jarvis_enable
expect_poll "the control's service handles the device message it does not publish" handled jarvis_devices_handled
expect "removing offer publication breaks the real consumer assertion" 1 jarvis_devices_assertion
jarvis_disable
cp -- "$sandbox/jarvis-service-original" "$jarvis_service"
jarvis_rescan

# Control: the device lists go out without the system default offer, so
# the unset value would read as the first device.
python3 - "$jarvis_service" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
needle='return [{ label: "System default", value: systemDefault }].concat(devices);'
assert s.count(needle)==1
changed=s.replace(needle, 'return devices;')
assert changed != s
p.write_text(changed)
PY
jarvis_rescan
jarvis_enable
expect_poll "the control's service handles the device message without a default offer" handled jarvis_devices_handled
expect "dropping the system default offer breaks the real consumer assertion" 1 jarvis_devices_assertion
jarvis_disable
cp -- "$sandbox/jarvis-service-original" "$jarvis_service"
jarvis_rescan

# The fixture holds its later device list until the row has seen the
# service publish the fault, so the list provably follows the fault.
jarvis_audio_gate="$sandbox/jarvis-audio-devices-gate"
"$node_bin" "$source_repo/scripts/fixtures/jarvis/prepare.js" --audio-fault-devices "$jarvis_backend" "$jarvis_audio_gate"
jarvis_rescan
rm -f -- "${jarvis_audio_gate:?}"
jarvis_enable
expect_poll "the fault fixture still publishes real device offers" devices jarvis_devices
expect_poll "the service publishes the audio fault" fault jarvis_audio_fault
: >"$jarvis_audio_gate"
expect_poll "the service handles the later device list" later jarvis_later_devices
expect "a device list after an audio fault clears the audio problem" handled jarvis_devices_handled
jarvis_disable
# Control: only the first device list reports ready, so the later list
# leaves the fault shown.
python3 - "$jarvis_service" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
needle='if (audioHealth.kind !== "ready")'
assert s.count(needle)==1
changed=s.replace(needle, 'if (audioHealth.kind === "reading")')
assert changed != s
p.write_text(changed)
PY
jarvis_rescan
rm -f -- "${jarvis_audio_gate:?}"
jarvis_enable
expect_poll "the status control publishes the audio fault" fault jarvis_audio_fault
: >"$jarvis_audio_gate"
expect_poll "the status control handles the later device list" later jarvis_later_devices
expect "a reading-only ready rule breaks the cleared-fault assertion" 1 jarvis_audio_recovered_assertion
jarvis_disable
rm -f -- "${jarvis_audio_gate:?}"
cp -- "$sandbox/jarvis-service-original" "$jarvis_service"
cp -- "$sandbox/jarvis-backend-original" "$jarvis_backend"
jarvis_rescan

# A caption for another generation must not replace the current one. Each
# control keeps its branch and breaks one rule; the same assertion fails.
"$node_bin" "$source_repo/scripts/fixtures/jarvis/prepare.js" --transcripts "$jarvis_backend"
jarvis_rescan
jarvis_enable
expect_poll "the service publishes the current generation's caption" current jarvis_transcript
jarvis_disable
for jarvis_transcript_control in generation write; do
  python3 - "$jarvis_service" "$jarvis_transcript_control" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
needle={"generation": "if (sessionState !== null && message.gen === sessionState.gen) {\n                        const reply = shell.status.set(\"transcript\"",
        "write": "const reply = shell.status.set(\"transcript\""}[sys.argv[2]]
replacement={"generation": "if (sessionState !== null) {\n                        const reply = shell.status.set(\"transcript\"",
             "write": "const reply = false ? null : \"ok\"; void (\"transcript\""}[sys.argv[2]]
assert s.count(needle)==1
changed=s.replace(needle, replacement)
assert changed != s
p.write_text(changed)
PY
  jarvis_rescan
  jarvis_enable
  # The write control publishes nothing to wait for, so its assertion
  # polls its 5 s out.
  if [[ $jarvis_transcript_control == generation ]]; then
    expect_poll "the generation control publishes the other generation's caption" other jarvis_transcript_other
    expect "a generation control breaks the caption assertion" 1 jarvis_transcript_assertion expect
  else
    expect "a $jarvis_transcript_control control breaks the caption assertion" 1 jarvis_transcript_assertion expect_poll
  fi
  jarvis_disable
  cp -- "$sandbox/jarvis-service-original" "$jarvis_service"
  jarvis_rescan
done
cp -- "$sandbox/jarvis-backend-original" "$jarvis_backend"
jarvis_rescan

jarvis_drop="$sandbox/jarvis-dropped-first-reply"
"$node_bin" "$source_repo/scripts/fixtures/jarvis/prepare.js" --drop-initial-replies "$jarvis_backend" "$jarvis_drop"
jarvis_rescan
jarvis_timeouts="$(log_lines 'jarvis: hello=timeout')" || { fail "Jarvis timeout log is unreadable"; return 1; }
expect "a timeout recovery fails the actual ordinary startup assertion once" 1 jarvis_reject_timeout_start
expect "the intentional recovery still reaches ready with its explicit allowance" ready jarvis_wait_ready 1
expect_log "the control retains its real hello timeout log" "$((jarvis_timeouts + 1))" 'jarvis: hello=timeout'
expect "the first-reply suppression control disables" ok ipc shell setPluginEnabled vgs.jarvis false
cp -- "$sandbox/jarvis-backend-original" "$jarvis_backend"
jarvis_rescan

python3 - "$jarvis_backend" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
needle='if (!process.stdout.write(wire + "\\n")) process.stdin.pause();'
assert s.count(needle)==1
p.write_text(s.replace(needle, 'void wire;'))
PY
jarvis_rescan
# The timeout after the fifth retry sends the stopped notice, so a notifications
# holder draws it. Each unsent check counts only the lines its own case
# adds to the shell log, from a mark taken before the case.
notes_on "jarvis hello-less daemon"
jarvis_unsent_mark="$(jarvis_unsent)" || { fail "the shell log is unreadable before the hello-less daemon"; jarvis_unsent_mark=unread; }
expect "the hello-less daemon fixture enables" ok ipc shell setPluginEnabled vgs.jarvis true
expect_poll "the hello-less daemon names the first failed start" retry-words jarvis_start_retry_words
expect_poll "the hello-less daemon reads problem with words" problem-words jarvis_start_problem_words
expect_poll "the hello-less daemon sends one Jarvis notification" '[["Jarvis did not answer in time", "danger", "mic"]]' jarvis_cards
expect "the hello-less daemon logs no unsent notice" "$jarvis_unsent_mark" jarvis_unsent
expect "the hello-less daemon service disables" ok ipc shell setPluginEnabled vgs.jarvis false
notes_off "jarvis hello-less daemon"
cp -- "$sandbox/jarvis-backend-original" "$jarvis_backend"
jarvis_rescan

jarvis_gate="$sandbox/jarvis-first-reply-gate"
jarvis_seen="$sandbox/jarvis-first-hello"
expect "the test-only session holder enables" ok ipc shell setPluginEnabled acme.probe true
"$node_bin" "$source_repo/scripts/fixtures/jarvis/prepare.js" --gate-daemon "$jarvis_backend" "$jarvis_gate" "$jarvis_seen"
# The gate holds every reply until the compositor confirms the lock, a poll
# with no bound under load, so these cases run without the hello deadline.
# The first-reply suppression check above proves that deadline.
python3 - "$jarvis_service" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
needle='if (root.cause === "") helloDeadline.start();'
assert s.count(needle)==1
p.write_text(s.replace(needle, ""))
PY
jarvis_rescan
jarvis_lock_case real
# Control: a service that neither resends hello on the startup lock nor
# drops the reply to the earlier snapshot publishes that stale answer.
python3 - "$jarvis_service" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
for needle, replacement in (
        ("            cancelDictation();\n        }\n        hello();\n    }", '            cancelDictation();\n        }\n        if (lifetime.kind === "ready") hello();\n    }'),
        ('if (message.daemon !== (lockObservation() ? "locked" : "ready")) continue;', "")):
    assert s.count(needle)==1
    s=s.replace(needle, replacement)
p.write_text(s)
PY
jarvis_rescan
jarvis_lock_case control
cp -- "$sandbox/jarvis-service-original" "$jarvis_service"
cp -- "$sandbox/jarvis-backend-original" "$jarvis_backend"
jarvis_rescan

# The permanent stop sends the stopped notice, so a notifications holder
# draws it; with none, the core logs it unsent and the log checks fail.
notes_on "jarvis permanent stop"
"$node_bin" "$source_repo/scripts/fixtures/jarvis/prepare.js" --floor-daemon "$jarvis_backend"
jarvis_rescan
jarvis_unsent_mark="$(jarvis_unsent)" || { fail "the shell log is unreadable before the permanent stop"; jarvis_unsent_mark=unread; }
expect "the unsupported Node fixture enables" ok ipc shell setPluginEnabled vgs.jarvis true
expect_poll "Node exit 78 is a permanent problem without retries" permanent jarvis_permanent
expect_poll "the permanent stop sends one Jarvis notification" '[["Jarvis needs Node 22 or later", "danger", "mic"]]' jarvis_cards
expect "the permanent stop logs no unsent notice" "$jarvis_unsent_mark" jarvis_unsent
expect "the unsupported Node service disables" ok ipc shell setPluginEnabled vgs.jarvis false
python3 - "$jarvis_service" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
needle="completion.code === 78"
assert s.count(needle)==1
p.write_text(s.replace(needle, "completion.code === 79"))
PY
jarvis_rescan
expect "the Node-floor recovery control enables" ok ipc shell setPluginEnabled vgs.jarvis true
expect_poll "the missing permanent-exit rule wrongly retries" retried jarvis_permanent
expect "the recovery control disables" ok ipc shell setPluginEnabled vgs.jarvis false
notes_off "jarvis permanent stop"
cp -- "$sandbox/jarvis-service-original" "$jarvis_service"
cp -- "$sandbox/jarvis-backend-original" "$jarvis_backend"
jarvis_rescan

notes_on "jarvis retries"
jarvis_enable
expect "five retries end in problem status" problem jarvis_exhaust
expect_poll "retry exhaustion sends one Jarvis notification" '[["Jarvis daemon stopped", "danger", "mic"]]' jarvis_cards
expect "the exhausted service disables" ok ipc shell setPluginEnabled vgs.jarvis false
notes_off "jarvis retries"

# The control changes the live retry rule in a disposable plugin copy.
# Its six-crash observation must not satisfy the five-retry assertion.
# The copy waits 50 ms before each retry: the count is the rule under
# control, and the five-retry case above runs under the real backoff.
python3 - "$jarvis_service" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
needle = "if (permanent || retries === 5)"
wait = "retry.interval = 250 * Math.pow(2, retries);"
assert s.count(needle) == 1 and s.count(wait) == 1
p.write_text(s.replace(needle, "if (permanent || retries === 6)").replace(wait, "retry.interval = 50;"))
PY
jarvis_rescan
jarvis_enable
expect "the six-retry control breaks the five-retry assertion" not-problem jarvis_exhaust
expect "the control disables" ok ipc shell setPluginEnabled vgs.jarvis false
cp -- "$sandbox/jarvis-service-original" "$jarvis_service"
jarvis_rescan

# A daemon diagnostic goes to the log and ends nothing.
"$node_bin" "$source_repo/scripts/fixtures/jarvis/prepare.js" --stderr-warning "$jarvis_backend"
jarvis_rescan
jarvis_warnings="$(jarvis_log_count "jarvis: fixture=warning")"
jarvis_enable
jarvis_stderr_case
jarvis_disable
# Control: the stderr handler takes each line as the end of communication.
python3 - "$jarvis_service" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
needle='root.lastDiagnostic = line;'
assert s.count(needle)==1
changed=s.replace(needle, 'root.lastDiagnostic = line;\n                        root.cause = line;')
assert changed != s
p.write_text(changed)
PY
jarvis_rescan
jarvis_warnings="$(jarvis_log_count "jarvis: fixture=warning")"
jarvis_enable
expect "a warning that sets the cause breaks the delivered-mute assertion" 1 jarvis_stderr_assertion
jarvis_disable
cp -- "$sandbox/jarvis-service-original" "$jarvis_service"
cp -- "$sandbox/jarvis-backend-original" "$jarvis_backend"
jarvis_rescan
jarvis_enable

# The core's floating terminal receives only the declared script path.
# Its disposable script is a no-auth fixture, not the real key entry flow.
jarvis_keys="$repo/shell/plugins/vgs.jarvis/Keys.qml"
cp -- "$jarvis_keys" "$sandbox/jarvis-keys-original"
cp -- "$repo/shell/plugins/vgs.jarvis/tui/add-key.sh" "$sandbox/jarvis-add-key-original"
printf '#!/bin/sh\nexit 0\n' >"$repo/shell/plugins/vgs.jarvis/tui/add-key.sh"
terminal_stand_in
terminal_ready "Jarvis Add key"
jarvis_rescan
jarvis_listed_key() {
  ipc shell listTuis | py_reply '
import json,sys
rows=json.load(sys.stdin)
want={"key":"vgs.jarvis/add-key","plugin":"vgs.jarvis","name":"add-key",
      "title":"Add Jarvis key","label":"Add key","icon":"key-round","group":"Jarvis"}
print("listed" if want in rows else "missing")
'
}
expect "the key-entry action is listed" listed jarvis_listed_key
jarvis_open_key() {
  local revision snapshot
  revision="$(jarvis_revision)" || return 1
  snapshot="$rt_dir/vgshell-sources-$shell_qs_pid/$revision"
  forget_record
  expect "Add key opens by its core TUI key" ok ipc shell openTui vgs.jarvis/add-key
  expect_poll "Add key hands the terminal only its declared script" \
    "$(words --app-id=org.vgs.tui "--title=VGS · Add Jarvis key" -- "$tui_self" present --presentation full \
      --plugin vgs.jarvis --dir "$snapshot" --record vgs.jarvis/add-key --run RUN --record-dir "$rt_dir/vgshell/tui" \
      --app-id org.vgs.tui --window-title "VGS · Add Jarvis key" -- tui/add-key.sh)" recorded
  expect_run_end "the fixture Add key terminal ends" vgs.jarvis/add-key
}
expect_poll "the key row starts present" matched jarvis_key_value present
printf 'locked\n' >"$sandbox/jarvis-world/key-mode"
jarvis_open_key
expect_poll "the service checks presence after Add key ends" matched jarvis_key_value locked
# A key the keyring cannot answer for reads unavailable with plain words;
# the presence check's own key reaches the log alone.
jarvis_key_unchecked() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
status=json.load(sys.stdin)["status"]
rows=status.get("keys", [])
store=status.get("keyStore", {})
ok=(len(rows) == 1 and rows[0].get("value") == "unavailable" and rows[0].get("hint", "") != ""
    and store.get("tone") == "warning" and store.get("action") is True)
print("matched" if ok else "pending")
'
}
printf 'failed\n' >"$sandbox/jarvis-world/key-mode"
bus_failures_logged="$(jarvis_log_count "jarvis-keys: busctl=failed")"
jarvis_open_key
expect_poll "a key the keyring cannot check reads unavailable and warns" matched jarvis_key_unchecked
expect_poll "the key check's own cause reaches the log" logged jarvis_logged "jarvis-keys: busctl=failed" "$bus_failures_logged"
expect "the unchecked key shows no diagnostic" plain jarvis_status_plain
printf 'present\n' >"$sandbox/jarvis-world/key-mode"
jarvis_open_key
expect_poll "the key row is present before the whole-probe failure" matched jarvis_key_value present
printf 'probe-failed\n' >"$sandbox/jarvis-world/key-mode"
key_failures_logged="$(jarvis_log_count "jarvis-keys: presence=failed")"
jarvis_open_key
expect_poll "a nonzero whole probe clears the key rows and warns on the keyring row" matched jarvis_key_unavailable
expect_poll "the failed key check's cause reaches the log" logged jarvis_logged "jarvis-keys: presence=failed" "$key_failures_logged"
expect "the failed key check shows no diagnostic" plain jarvis_status_plain
printf 'present\n' >"$sandbox/jarvis-world/key-mode"
jarvis_open_key
expect_poll "restoring the probe replaces unavailable with present" matched jarvis_key_value present
python3 - "$jarvis_keys" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
assert not p.is_symlink()
s=p.read_text()
needle='if (code !== 0) throw new Error("probe");'
assert s.count(needle)==1
changed=s.replace(needle, "if (code !== 0) return;")
assert changed != s
p.write_text(changed)
PY
jarvis_rescan
expect_poll "the stale-row control first publishes present" matched jarvis_key_value present
printf 'probe-failed\n' >"$sandbox/jarvis-world/key-mode"
jarvis_open_key
jarvis_failure_control() {
  (failures=0 behaviour_failures=0
   expect_poll "a failed probe must replace stale present rows" matched jarvis_key_unavailable >"$sandbox/jarvis-probe-control.log"
   echo "$failures")
}
expect "retaining stale rows breaks the actual whole-probe assertion" 1 jarvis_failure_control
expect "the control leaves the previous present row" matched jarvis_key_value present
cp -- "$sandbox/jarvis-keys-original" "$jarvis_keys"
printf 'present\n' >"$sandbox/jarvis-world/key-mode"
jarvis_rescan
expect_poll "restored whole-probe handling publishes present" matched jarvis_key_value present
python3 - "$jarvis_keys" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
needle="onEndedAtChanged: if (endedAt !== null) refresh()"
assert s.count(needle)==1
p.write_text(s.replace(needle, "onEndedAtChanged: {}"))
PY
printf 'present\n' >"$sandbox/jarvis-world/key-mode"
jarvis_rescan
expect_poll "the no-refresh control first publishes present" matched jarvis_key_value present
printf 'locked\n' >"$sandbox/jarvis-world/key-mode"
jarvis_open_key
jarvis_refresh_control() {
  (failures=0 behaviour_failures=0
   expect_poll "Add key must refresh presence" matched jarvis_key_value locked >"$sandbox/jarvis-refresh-control.log"
   echo "$failures")
}
expect "removing the end refresh breaks its actual assertion" 1 jarvis_refresh_control
cp -- "$sandbox/jarvis-keys-original" "$jarvis_keys"
cp -- "$sandbox/jarvis-add-key-original" "$repo/shell/plugins/vgs.jarvis/tui/add-key.sh"
printf 'present\n' >"$sandbox/jarvis-world/key-mode"
jarvis_rescan
expect_poll "restored key status contains no secret" matched jarvis_key_value present

# The account probe also runs through J09. The core terminal runs only a
# no-auth fixture; the actual accounts script has its own private TTY suite.
jarvis_accounts="$repo/shell/plugins/vgs.jarvis/Accounts.qml"
cp -- "$jarvis_accounts" "$sandbox/jarvis-accounts-original"
cp -- "$repo/shell/plugins/vgs.jarvis/tui/accounts.sh" "$sandbox/jarvis-accounts-tui-original"
cp -- "$repo/scripts/smoke/fixtures/tui/vgs.jarvis/tui/accounts.sh" "$repo/shell/plugins/vgs.jarvis/tui/accounts.sh"
jarvis_rescan
# The hint AccountStatus.js words for the fixture's Claude Code / team in
# STATE: signed in on plan pro as team@example.invalid, whose folder name
# names no identity, or found with neither. A found folder is signed out,
# so its row reads signed-out and carries no hint.
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
row=next((item for item in rows if item["label"] == "Claude Code / team"), None)
ok=row is not None and row["value"] == ("signed-out" if sys.argv[2] == "found" else "present") and row.get("hint", "") == sys.argv[1]
print("matched" if ok else "pending")
' "$want" "$1"
}
# The search row's tone and whether it offers Accounts, as JSON, with the
# accounts and choices it publishes beside it emptied or not.
jarvis_account_search() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
status=json.load(sys.stdin)["status"]
search=status.get("accountSearch", {})
print(json.dumps([search.get("tone"), search.get("action"), status.get("accounts") == [], status.get("brains") == []]))
'
}
# A failed check: no accounts or choices, and a danger row without Accounts.
jarvis_account_failed() {
  [[ "$(jarvis_account_search)" == '["danger", false, true, true]' ]] && echo matched || echo pending
}
jarvis_open_accounts() {
  local revision snapshot
  revision="$(jarvis_revision)" || return 1
  snapshot="$rt_dir/vgshell-sources-$shell_qs_pid/$revision"
  forget_record
  expect "Accounts opens through its core TUI key" ok ipc shell openTui vgs.jarvis/accounts
  expect_poll "Accounts hands the terminal only its declared fixture script" \
    "$(words --app-id=org.vgs.tui "--title=VGS · Jarvis accounts" -- "$tui_self" present --presentation full \
      --plugin vgs.jarvis --dir "$snapshot" --record vgs.jarvis/accounts --run RUN --record-dir "$rt_dir/vgshell/tui" \
      --app-id org.vgs.tui --window-title "VGS · Jarvis accounts" -- tui/accounts.sh)" recorded
  expect_run_end "the no-auth Accounts terminal ends" vgs.jarvis/accounts
}
expect_poll "account status shows a login hint, not verification" matched jarvis_account_hint signed-in
expect_poll "the search reports the accounts it found and offers Accounts" '["ok", true, false, false]' jarvis_account_search
printf 'found\n' >"$sandbox/jarvis-world/account-mode"
jarvis_open_accounts
expect_poll "Accounts end refreshes account metadata" matched jarvis_account_hint found
printf 'failed\n' >"$sandbox/jarvis-world/account-mode"
jarvis_open_accounts
expect_poll "failed discovery clears both stale accounts and choices" matched jarvis_account_failed
printf 'signed-in\n' >"$sandbox/jarvis-world/account-mode"
jarvis_open_accounts
expect_poll "restored discovery reports login hints" matched jarvis_account_hint signed-in
# A home folder too large to search whole is a partial search: the
# folders read before the bound and the config home's stay, and the row
# warns and offers Accounts. The fixture writes the labels of those
# folders, read from its own listing, beside the mode file.
jarvis_account_labels() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
rows=json.load(sys.stdin)["status"].get("accounts", [])
labels=sorted(row["label"][len("Claude Code / "):] for row in rows if row["label"].startswith("Claude Code / "))
want=json.load(open(sys.argv[1]))
print("matched" if [label for label in labels if label != "default"] == want else "pending")
' "$sandbox/jarvis-world/account-labels"
}
rm -f -- "${sandbox:?}/jarvis-world/account-labels"
printf 'entry-limit\n' >"$sandbox/jarvis-world/account-mode"
jarvis_open_accounts
expect_poll "a partial search warns and offers Accounts" '["warning", true, false, false]' jarvis_account_search
expect_poll "a partial search keeps the folders read before its bound" matched jarvis_account_labels
expect "the partial search shows no diagnostic" plain jarvis_status_plain
# A copy that drops the folders read once the bound is met.
jarvis_folders="$repo/bin/lib/account-folders.js"
cp -- "$jarvis_folders" "$sandbox/jarvis-folders-original"
python3 - "$jarvis_folders" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
assert not p.is_symlink()
s=p.read_text()
needle='{ partial ||= "entry-limit"; break; }'
assert s.count(needle)==1
changed=s.replace(needle, '{ partial ||= "entry-limit"; folders.length = 0; break; }')
assert changed != s
p.write_text(changed)
PY
rm -f -- "${sandbox:?}/jarvis-world/account-labels"
# The core file lies outside the plugin, so no rescan rebuilds anything:
# the next discovery, after an Accounts run ends, reads the copy.
jarvis_open_accounts
expect_poll "the bound control's discovery is published" idle jarvis_accounts_reader_idle
expect_poll "the bound control publishes its partial search" '["warning", true, false, false]' jarvis_account_search
jarvis_account_bound_control() {
  (failures=0 behaviour_failures=0
   expect "the folders read before the bound must stay" matched jarvis_account_labels >"$sandbox/jarvis-account-bound-control.log"
   echo "$failures")
}
expect "dropping the folders read before the bound breaks the folder read" 1 jarvis_account_bound_control
cp -- "$sandbox/jarvis-folders-original" "$jarvis_folders"
rm -f -- "${sandbox:?}/jarvis-world/account-labels"
jarvis_open_accounts
expect_poll "the restored search's discovery is published" idle jarvis_accounts_reader_idle
expect_poll "the restored search keeps its folders again" matched jarvis_account_labels
# A linked config home is not followed: the search is partial, keeps the
# home's folders, warns and offers Accounts.
printf 'parent-unreadable\n' >"$sandbox/jarvis-world/account-mode"
jarvis_open_accounts
expect_poll "a linked parent makes the search partial" '["warning", true, false, false]' jarvis_account_search
expect_poll "the home's folders stay beside a linked parent" matched jarvis_account_hint signed-in
expect "the linked parent shows no diagnostic" plain jarvis_status_plain
# Each failure shows the page's words alone; its safe cause reaches the log.
for diagnostic_case in \
  'raw-error|jarvis-accounts: process=failed' \
  'oversize-error|jarvis-accounts: diagnostic=oversize' \
  'invalid-output|jarvis-accounts: output=invalid' \
  'failed|jarvis-accounts: added=json'; do
  IFS='|' read -r diagnostic_mode diagnostic_cause <<<"$diagnostic_case"
  printf 'signed-in\n' >"$sandbox/jarvis-world/account-mode"
  jarvis_open_accounts
  expect_poll "discovery is restored before the $diagnostic_mode failure" matched jarvis_account_hint signed-in
  cause_logged="$(jarvis_log_count "$diagnostic_cause")"
  printf '%s\n' "$diagnostic_mode" >"$sandbox/jarvis-world/account-mode"
  jarvis_open_accounts
  expect_poll "a failed check clears its rows and offers no Accounts: $diagnostic_mode" matched jarvis_account_failed
  expect_poll "the safe cause reaches the log: $diagnostic_mode" logged jarvis_logged "$diagnostic_cause" "$cause_logged"
  expect "the failure shows no diagnostic: $diagnostic_mode" plain jarvis_status_plain
done
# A copy that logs a generic cause in place of the helper's: the page
# reads the same, and only the log read finds the loss.
python3 - "$jarvis_accounts" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
assert not p.is_symlink()
s=p.read_text()
needle="const reason = Providers.probeFailure(completion, diagnostic);"
assert s.count(needle)==1
changed=s.replace(needle, 'const reason = "jarvis-accounts: process=failed";')
assert changed != s
p.write_text(changed)
PY
printf 'signed-in\n' >"$sandbox/jarvis-world/account-mode"
jarvis_rescan
expect_poll "the cause control first reports login hints" matched jarvis_account_hint signed-in
cause_logged="$(jarvis_log_count "jarvis-accounts: added=json")"
printf 'failed\n' >"$sandbox/jarvis-world/account-mode"
jarvis_open_accounts
expect_poll "the cause control publishes its failed discovery" matched jarvis_account_failed
jarvis_account_cause_control() {
  (failures=0 behaviour_failures=0
   expect "the named helper cause must reach the log" logged jarvis_logged "jarvis-accounts: added=json" "$cause_logged" >"$sandbox/jarvis-account-cause-control.log"
   echo "$failures")
}
expect "discarding the named helper cause breaks its log assertion" 1 jarvis_account_cause_control
cp -- "$sandbox/jarvis-accounts-original" "$jarvis_accounts"
# A copy that forwards the safe cause into the search row: the plain-words
# read must refuse it.
python3 - "$jarvis_accounts" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
assert not p.is_symlink()
s=p.read_text()
needle='Words.searchValue({ kind: "failed", reason: reason })'
assert s.count(needle)==1
changed=s.replace(needle, '({ tone: "danger", text: reason, action: false })')
assert changed != s
p.write_text(changed)
PY
printf 'failed\n' >"$sandbox/jarvis-world/account-mode"
jarvis_rescan
expect_poll "the raw control publishes its failed discovery" matched jarvis_account_failed
jarvis_account_raw_control() {
  (failures=0 behaviour_failures=0
   expect "the failed check's cause must stay off the page" plain jarvis_status_plain >"$sandbox/jarvis-account-raw-control.log"
   echo "$failures")
}
expect "forwarding the cause into status breaks its plain-words assertion" 1 jarvis_account_raw_control
cp -- "$sandbox/jarvis-accounts-original" "$jarvis_accounts"
python3 - "$jarvis_accounts" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
assert not p.is_symlink()
s=p.read_text()
lines=s.splitlines()
matches=[i for i,line in enumerate(lines) if "probe.command = [" in line]
assert len(matches)==1
lines[matches[0]]='        probe.command = ["jarvis-account-missing-helper"];'
changed="\n".join(lines)+"\n"
assert changed != s
p.write_text(changed)
PY
cause_logged="$(jarvis_log_count "jarvis-accounts: process=start-failed")"
jarvis_rescan
expect_poll "a process that cannot start clears its rows" matched jarvis_account_failed
expect_poll "a process that cannot start logs its own safe cause" logged jarvis_logged "jarvis-accounts: process=start-failed" "$cause_logged"
cp -- "$sandbox/jarvis-accounts-original" "$jarvis_accounts"
printf 'signed-in\n' >"$sandbox/jarvis-world/account-mode"
jarvis_rescan
expect_poll "restored reader clears the prior failure" matched jarvis_account_hint signed-in
python3 - "$jarvis_accounts" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
assert not p.is_symlink()
s=p.read_text()
needle='if (code !== 0) throw new Error("probe");'
assert s.count(needle)==1
changed=s.replace(needle, 'if (code !== 0) return;')
assert changed != s
p.write_text(changed)
PY
jarvis_rescan
expect_poll "the stale-account control first sees signed in" matched jarvis_account_hint signed-in
printf 'failed\n' >"$sandbox/jarvis-world/account-mode"
jarvis_open_accounts
jarvis_account_failure_control() {
  (failures=0 behaviour_failures=0
   expect_poll "failed discovery must clear accounts and choices" matched jarvis_account_failed >"$sandbox/jarvis-account-failure-control.log"
   echo "$failures")
}
expect "retaining stale accounts breaks the failed-discovery assertion" 1 jarvis_account_failure_control
cp -- "$sandbox/jarvis-accounts-original" "$jarvis_accounts"
printf 'signed-in\n' >"$sandbox/jarvis-world/account-mode"
jarvis_rescan
expect_poll "restored failed-discovery handling reports current accounts" matched jarvis_account_hint signed-in
python3 - "$jarvis_accounts" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
assert not p.is_symlink()
s=p.read_text()
needle="function refresh() {\n        if (shell === null) return;"
assert s.count(needle)==1
changed=s.replace(needle, needle + '\n        if (output !== "") return;')
assert changed != s
p.write_text(changed)
PY
jarvis_rescan
expect_poll "the account refresh control first sees signed in" matched jarvis_account_hint signed-in
printf 'found\n' >"$sandbox/jarvis-world/account-mode"
jarvis_open_accounts
jarvis_account_refresh_control() {
  (failures=0 behaviour_failures=0
   expect_poll "Accounts must refresh discovery after its terminal ends" matched jarvis_account_hint found >"$sandbox/jarvis-account-refresh-control.log"
   echo "$failures")
}
expect "keeping stale Accounts discovery after its terminal ends breaks its assertion" 1 jarvis_account_refresh_control
cp -- "$sandbox/jarvis-accounts-original" "$jarvis_accounts"
printf 'signed-in\n' >"$sandbox/jarvis-world/account-mode"
jarvis_rescan
expect_poll "restored account status never claims verified access" matched jarvis_account_hint signed-in
printf 'locked\n' >"$sandbox/jarvis-world/key-mode"
jarvis_open_accounts
expect_poll "Accounts end also refreshes remembered-key presence" matched jarvis_key_value locked
printf 'present\n' >"$sandbox/jarvis-world/key-mode"
jarvis_open_accounts
expect_poll "key presence is restored before its Accounts-end control" matched jarvis_key_value present
python3 - "$jarvis_keys" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
assert not p.is_symlink()
s=p.read_text()
needle="if (shell === null) return;"
assert s.count(needle)==1
changed=s.replace(needle, needle + '\n        if (output !== "") return;')
assert changed != s
p.write_text(changed)
PY
jarvis_rescan
expect_poll "the key Accounts-end control first sees present" matched jarvis_key_value present
printf 'locked\n' >"$sandbox/jarvis-world/key-mode"
jarvis_open_accounts
jarvis_account_keys_control() {
  (failures=0 behaviour_failures=0
   expect_poll "Accounts end must refresh remembered-key presence" matched jarvis_key_value locked >"$sandbox/jarvis-account-keys-control.log"
   echo "$failures")
}
expect "keeping stale Keys presence after Accounts ends breaks its assertion" 1 jarvis_account_keys_control
cp -- "$sandbox/jarvis-keys-original" "$jarvis_keys"
cp -- "$sandbox/jarvis-accounts-tui-original" "$repo/shell/plugins/vgs.jarvis/tui/accounts.sh"
printf 'present\n' >"$sandbox/jarvis-world/key-mode"
jarvis_rescan
expect_poll "restored Keys account refresh shows present" matched jarvis_key_value present
jarvis_disable

# The local voice records through the core's dictation (the header). The
# local row's marker and sidecar stand-in are the hanging-probe part's.
jarvis_local="$home/.local/share/vgshell/jarvis/local"
jarvis_local_marker="$home/.local/state/vgshell/jarvis/local-ready.json"
jarvis_dictation_words="$sandbox/voxtype-words"
jarvis_dictation_notes="$sandbox/voxtype-daemon.log"
jarvis_voxtype="$shim/voxtype"
mkdir -p -- "$jarvis_local/venv/bin" "$(dirname -- "$jarvis_local_marker")"
cp -- "$source_repo/scripts/fixtures/jarvis-local-speech/standin.py" "$jarvis_local/venv/bin/python"
chmod 700 -- "$jarvis_local/venv/bin/python"
python3 - "$repo/shell/plugins/vgs.jarvis/artifacts.json" "$jarvis_local" "$jarvis_local_marker" <<'PY'
import json, os, sys
tier = next(iter(json.load(open(sys.argv[1]))["tiers"]))
open(sys.argv[3], "w").write(json.dumps({"tier": tier, "data": os.path.realpath(sys.argv[2])}))
open(os.path.join(sys.argv[2], "scenario.json"), "w").write(json.dumps({"start": "ready",
    "utterances": [{"speech": True}] * 10, "speech": [{"rate": 16000, "samples": 4800}] * 20}))
PY
# The Voice step's offered action, "" for none; the core's daemon, its
# child and its holders; and the live recording's holder and mode.
jarvis_voice_action() { ipc smoke statusValues vgs.jarvis | py_reply 'import json,sys; v=json.load(sys.stdin).get("setupVoice") or {}; a=v.get("action"); print(a if isinstance(a,str) else "")'; }
jarvis_dictation_recording() { lent dictation | py_reply 'import json,sys; d=json.load(sys.stdin); print(d["holder"] or "-", d["mode"] or "-")'; }
# What the stand-in's daemons noted, in order, `none` for no line.
jarvis_dictation_noted() { if [[ -s $jarvis_dictation_notes ]]; then tr '\n' ' ' <"$jarvis_dictation_notes" | sed 's/ $//'; echo; else echo none; fi; }
# The Session gate and capture the service holds.
jarvis_gate_capture() { ipc smoke readInstance service vgs.jarvis sessionState | py_reply 'import json,sys; s=json.load(sys.stdin); print("pending" if s is None else s["gate"]["kind"] + " " + s["capture"]["kind"])'; }
# The user's last words in the conversation the service publishes.
jarvis_user_words() { ipc smoke statusValues vgs.jarvis | py_reply 'import json,sys; rows=[r for r in json.load(sys.stdin).get("conversation") or [] if r["role"] == "user"]; print(rows[-1]["text"] if rows else "none")'; }
jarvis_intent() { ipc smoke invokeInstance service vgs.jarvis intent "$1"; }
# SIGKILL to the daemon below the service's J09 launcher, as a crash ends it.
jarvis_kill_daemon() {
  local launcher daemon
  launcher="$(ipc smoke jarvisProcess | jarvis_launcher_pid)" || return 1
  daemon="$(jarvis_descendants "$launcher" 2>&1)" || { fail "the Jarvis daemon is unreadable: $daemon"; return 1; }
  kill -KILL "$daemon"
}
# A held Talk recording through the core, from a fresh note log.
jarvis_dictation_talk() { # LABEL
  rm -f -- "${jarvis_dictation_notes:?}"
  expect_poll "$1: the local voice takes Talk" "up closed" jarvis_gate_capture
  expect "$1: Talk goes down" "" jarvis_intent talk-down
  expect_poll "$1: Talk records through the core" "vgs.jarvis text" jarvis_dictation_recording
  expect_poll "$1: the stand-in's daemon records once" start jarvis_dictation_noted
}

dictation_stand_ins off
rescan "the shell finds no voxtype for Jarvis's recording"
jarvis_enable
expect_poll "without voxtype the core's daemon for Jarvis reads failed" "failed none vgs.jarvis" dictation_lent
expect_poll "without voxtype the Voice step offers Set up dictation" dictation jarvis_voice_action
jarvis_disable

# The stand-in answers Voice's config and info verbs from this part's files,
# as rows/voice.sh's copy does.
jarvis_voice_feedback="$sandbox/jarvis-voice-feedback"
jarvis_voice_installed="$sandbox/jarvis-voice-installed"
printf 'true\n' >"$jarvis_voice_feedback"
touch -- "$jarvis_voice_installed"
printf '%s' 'the stand-in heard this' >"$jarvis_dictation_words"
rm -f -- "${jarvis_dictation_notes:?}"
dictation_stand_ins on || fail "the shell does not resolve voxtype to the stand-in: $(shell_resolves voxtype)"
cat >"$jarvis_voxtype" <<EOF_STUB
#!/usr/bin/env bash
voice_installed=$(printf %q "$jarvis_voice_installed")
voice_feedback=$(printf %q "$jarvis_voice_feedback")
voice_feedback_sets=$(printf %q "$sandbox/jarvis-voice-feedback-sets")
voice_feedback_unreadable=$(printf %q "$sandbox/jarvis-voice-feedback-unreadable")
voice_feedback_refused=$(printf %q "$sandbox/jarvis-voice-feedback-refused")
voice_feedback_dropped=$(printf %q "$sandbox/jarvis-voice-feedback-dropped")
. $(printf %q "$repo/scripts/smoke/fixtures/voxtype/voxtype")
EOF_STUB
chmod 755 "$jarvis_voxtype"
# Voice requires voxtype-audio-bridge too; its stand-in prints the bridge's
# status line and idles until TERM, so enabling Voice beside Jarvis raises
# no requirement notice of its own.
jarvis_voice_bridge="$shim/voxtype-audio-bridge"
cat >"$jarvis_voice_bridge" <<'EOF_BRIDGE'
#!/usr/bin/env bash
printf '{"status":"connected"}\n'
trap 'exit 0' TERM
while :; do sleep 1; done
EOF_BRIDGE
chmod 755 "$jarvis_voice_bridge"
rescan "the shell finds the voxtype stand-in for Jarvis's recording"
cp -- "$jarvis_engine" "$sandbox/jarvis-engine-original"
"$node_bin" "$source_repo/scripts/fixtures/jarvis/scripted.js" --dictation-brain "$jarvis_engine"
jarvis_rescan
jarvis_enable
expect_poll "Jarvis's recording daemon reads ready" "ready running vgs.jarvis" dictation_lent
jarvis_dictation_talk "Jarvis alone"
expect "Jarvis alone: Talk comes up" "" jarvis_intent talk-up
expect_poll "Jarvis alone: the user's words are the stand-in voxtype's" "the stand-in heard this" jarvis_user_words
expect_poll "Jarvis alone: the recording was stopped" "start stop" jarvis_dictation_noted
expect "Jarvis alone: Stop ends the turn" "" jarvis_intent stop
jarvis_dictation_talk "the daemon's end"
jarvis_kill_daemon
expect_poll "the daemon's end cancels Jarvis's recording" "- -" jarvis_dictation_recording
expect_poll "the daemon's end reaches the stand-in as a cancel" "start cancel" jarvis_dictation_noted
expect "Jarvis starts its daemon again" ready jarvis_wait_ready 1
jarvis_dictation_talk "the lock"
expect "the lock: the test-only holder locks" ok probe lock
expect_poll "the lock cancels Jarvis's recording" "- -" jarvis_dictation_recording
expect_poll "the lock reaches the stand-in as a cancel" "start cancel" jarvis_dictation_noted
expect "the lock: the fixture unlocks without authentication" ok probe unlock
expect "Voice enables beside Jarvis" ok ipc shell setPluginEnabled vgs.voice true
expect_poll "both holders are lent the one daemon" "ready running vgs.jarvis,vgs.voice" dictation_lent
jarvis_dictation_talk "both on"
expect "Voice's toggle during Jarvis's recording answers busy" "refused: dictation=busy holder=vgs.jarvis" ipc vgs.voice invoke toggle ""
expect "Voice's toggle leaves Jarvis's recording" "vgs.jarvis text" jarvis_dictation_recording
expect "Voice's toggle starts no recording of its own" start jarvis_dictation_noted
expect "Voice shows no recording of its own" '"idle"' ipc smoke readInstance service vgs.voice dictation
expect "both on: Talk comes up" "" jarvis_intent talk-up
expect_poll "both on: the recording was stopped" "start stop" jarvis_dictation_noted
expect "both on: Stop ends the turn" "" jarvis_intent stop
expect "Voice disables" ok ipc shell setPluginEnabled vgs.voice false
jarvis_disable
# Control: a service whose daemon end cancels nothing leaves the recording
# held after the daemon is killed; the release at disable cancels it.
cp -- "$jarvis_service" "$sandbox/jarvis-dictation-service"
python3 - "$jarvis_service" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
needle="        startWait.stop();\n        cancelDictation();\n"
assert s.count(needle)==1
p.write_text(s.replace(needle, "        startWait.stop();\n"))
PY
jarvis_rescan
jarvis_enable
jarvis_dictation_talk "the cancel-free daemon end"
jarvis_kill_daemon
jarvis_dictation_end_control() {
  (failures=0 behaviour_failures=0
   expect_poll "the daemon's end cancels Jarvis's recording" "- -" jarvis_dictation_recording >"$sandbox/jarvis-dictation-end-control.log"
   echo "$failures")
}
expect "a service that cancels nothing at the daemon's end leaves the recording held" 1 jarvis_dictation_end_control
expect "the cancel-free service restarts its daemon" ready jarvis_wait_ready 1
jarvis_disable
expect_poll "the release cancels the held recording" "- -" jarvis_dictation_recording
cp -- "$sandbox/jarvis-dictation-service" "$jarvis_service"
jarvis_rescan
expect_poll "with Jarvis and Voice off, no voxtype process runs" "daemon=0 follower=0 other=0" dictation_processes all
cp -- "$sandbox/jarvis-engine-original" "$jarvis_engine"
rm -- "${repo:?}/shell/plugins/vgs.jarvis/backend/scripted-fixture.js"
rm -rf -- "${jarvis_local:?}"
rm -f -- "${jarvis_local_marker:?}" "${jarvis_voxtype:?}" "${jarvis_voice_bridge:?}" "${jarvis_dictation_words:?}" "${jarvis_dictation_notes:?}" "${jarvis_voice_feedback:?}" \
  "$sandbox/voxtype-follow.log" "$sandbox/jarvis-voice-feedback-sets" "$jarvis_voice_installed"
dictation_stand_ins off
jarvis_rescan
jarvis_notice_close
