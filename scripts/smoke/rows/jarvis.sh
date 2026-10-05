# This row has no latency ceiling. It polls once per nested IPC round trip.
# The real child runs inside J09, with synthetic audio commands and no
# account, real audio or desktop endpoint.
# inputs: shell/plugins/vgs.jarvis/* bin/lib/account-folders.js bin/lib/anchored.js shell/Commons/AccountDirectories.js scripts/fixtures/jarvis/* scripts/smoke/fixtures/tui/vgs.jarvis/* shell/Core/TuiRunner.qml shell/Core/SessionLock.qml scripts/smoke/fixtures/plugins/acme.probe/* scripts/smoke/rows/capabilities.sh scripts/smoke/rows/plugins.sh bin/vgshell-tui
set -euo pipefail
expected_errors+=('WARN qml: jarvis: stderr=.*Killed.*')
expected_errors+=('WARN qml: jarvis: stderr=jarvis: node=21[.]0[.]0 need=22')
expected_errors+=('WARN qml: jarvis: hello=timeout')
expected_errors+=('.*jarvis-account-missing-helper.*')
# The readers log a failed check's safe cause; the page shows plain words.
expected_errors+=('WARN qml: jarvis-accounts: (process|output|diagnostic|added|directory|discovery)=[a-z-]+')
expected_errors+=('WARN qml: jarvis-keys: (presence|busctl)=[a-z-]+')

# Read the actual daemon below the Process-owned J09 launcher. PIDs come
# only from that launcher's /proc descendants, never a name-based search.
jarvis_descendants() { # LAUNCHER_PID
  python3 - "$1" <<'PY'
import pathlib, sys
pending = [int(sys.argv[1])]
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
if len(found) != 1:
    sys.exit(f"jarvis-row: daemon-count={len(found)}")
print(found[0])
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

jarvis_toasts() {
  ipc shell lent | py_reply 'import json,sys; d=json.load(sys.stdin)["toasts"]; print(sum(e["plugin"] == "vgs.jarvis" for e in d["visible"] + d["waiting"]))'
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

jarvis_disable() {
  local answer launcher daemon_pid
  answer="$(ipc smoke jarvisProcess)"
  launcher="$(jarvis_launcher_pid <<<"$answer")" || return 1
  daemon_pid="$(jarvis_descendants "$launcher")"
  expect "Jarvis disables" ok ipc shell setPluginEnabled vgs.jarvis false
  expect "disable releases the real daemon" absent jarvis_no_pid "$daemon_pid"
  expect "disable releases the namespace launcher" absent jarvis_no_pid "$launcher"
  expect "disable drops the service" absent ipc smoke jarvisProcess
}

jarvis_exhaust() {
  local answer launcher daemon_pid retries kind
  for ((crash = 0; crash <= 5; crash++)); do
    answer="$(ipc smoke jarvisProcess)"
    launcher="$(jarvis_launcher_pid <<<"$answer")" || return 1
    daemon_pid="$(jarvis_descendants "$launcher")"
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
      answer="$(jarvis_wait_ready "$((crash + 1))")" || return 1
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

jarvis_lock_answer() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
d=json.load(sys.stdin)
if d["retries"] != 0:
    print("stale")
elif d["lifetime"]["kind"] == "ready":
    print(d["status"]["daemon"]["text"])
else:
    print("pending")
'
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
status=json.load(sys.stdin)["status"]
expected={"tone":"danger","text":"capture-overflow"}
print("fault" if status.get("audio")==expected else "pending")
'
}

jarvis_audio_fault_assertion() {
  (failures=0 behaviour_failures=0
   expect_poll "device offers do not clear the capture fault" fault jarvis_audio_fault >"$sandbox/jarvis-audio-fault-control-assertions.log"
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
  [[ -s $jarvis_seen ]] && echo seen || echo pending
}

jarvis_permanent() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
d=json.load(sys.stdin)
if d["retries"] != 0:
    print("retried")
elif d["lifetime"]["kind"] == "problem" and d["pid"] is None and d["status"]["daemon"]["text"] == "Problem: jarvis: node=21.0.0 need=22":
    print("permanent")
else:
    print("pending")
'
}

jarvis_lock_case() { # EXPECTED
  rm -f -- "$jarvis_gate" "$jarvis_seen"
  expect "the test-only holder unlocks before startup" ok probe unlock
  expect "the gated Jarvis service enables" ok ipc shell setPluginEnabled vgs.jarvis true
  expect_poll "the daemon has consumed its first hello" seen jarvis_seen_hello
  expect "the real test-only holder locks during startup" ok probe lock
  expect_poll "the compositor confirms the fixture lock" true read_service lockSecure
  : >"$jarvis_gate"
  expect_poll "startup keeps the current lock snapshot without restarting" "$1" jarvis_lock_answer
  if [[ $1 == "Locked; no capture" ]]; then
    expect_poll "the reducer observes lock without capture" session jarvis_session locked
  fi
  expect "the fixture unlocks without authentication" ok probe unlock
  if [[ $1 == "Locked; no capture" ]]; then
    expect_poll "the reducer observes unlock without capture" session jarvis_session unconfigured
    expect_poll "the running daemon observes unlock" "Ready; no capture" jarvis_lock_answer
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

jarvis_service="$repo/shell/plugins/vgs.jarvis/Service.qml"
jarvis_backend="$repo/shell/plugins/vgs.jarvis/backend/jarvisd.js"
cp -- "$jarvis_service" "$sandbox/jarvis-service-original"
cp -- "$jarvis_backend" "$sandbox/jarvis-backend-original"
jarvis_shell_owner="$repo/shell/plugins/vgs.jarvis/backend/Sandbox.js"
cp -- "$jarvis_shell_owner" "$sandbox/jarvis-shell-original"

# Kernel behavior is exercised through the real tool by the offline shell
# row. These scoped readiness fixtures isolate daemon-to-service delivery.
jarvis_shell_status() {
  ipc smoke jarvisProcess | py_reply '
import json,sys
want = {"ready": {"tone":"ok", "text":"Ready"},
        "missing": {"tone":"warning", "text":"Unavailable: bwrap-missing", "action":True}}[sys.argv[1]]
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
needle='onRequirementsRevisionChanged: refreshShell()'
assert source.count(needle)==1
changed=source.replace(needle, 'onRequirementsRevisionChanged: { if (false) refreshShell(); }')
assert changed != source
p.write_text(changed)
PYCONTROL
jarvis_shell_put '{"kind":"unavailable","reason":"bwrap-missing"}'
jarvis_rescan
jarvis_enable
expect_poll "the control reaches initial missing readiness" matched jarvis_shell_offers unavailable
expect "removing requirement rescan delivery breaks recovery" 2 jarvis_shell_rescan_assertion
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
needle='const result = shell.status.set("detail", { phase: message.phase, seq: message.seq, state: message.state });'
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

# Keep the branch, but omit its status write. The real offers assertion fails
# before any microphone or speaker can start.
python3 - "$jarvis_service" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
needle='const reply = shell.status.set(key, message[key]);'
assert s.count(needle)==1
changed=s.replace(needle, 'const reply = false ? shell.status.set(key, message[key]) : "ok";')
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

"$node_bin" "$source_repo/scripts/fixtures/jarvis/prepare.js" --audio-fault-devices "$jarvis_backend"
jarvis_rescan
jarvis_enable
expect_poll "the fault fixture still publishes real device offers" devices jarvis_devices
expect_poll "a later device message retains the owning audio fault" fault jarvis_audio_fault
jarvis_disable
python3 - "$jarvis_service" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
needle='if (audioHealth.kind === "reading")'
assert s.count(needle)==1
changed=s.replace(needle, 'if (true)')
assert changed != s
p.write_text(changed)
PY
jarvis_rescan
jarvis_enable
expect_poll "the status control still publishes real offers" devices jarvis_devices
expect "offer-driven success breaks the actual fault-status assertion" 1 jarvis_audio_fault_assertion
jarvis_disable
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

jarvis_gate="$sandbox/jarvis-first-reply-gate"
jarvis_seen="$sandbox/jarvis-first-hello"
expect "the test-only session holder enables" ok ipc shell setPluginEnabled acme.probe true
"$node_bin" "$source_repo/scripts/fixtures/jarvis/prepare.js" --gate-daemon "$jarvis_backend" "$jarvis_gate" "$jarvis_seen"
jarvis_rescan
jarvis_lock_case "Locked; no capture"
python3 - "$jarvis_service" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
needle="onLockedChanged: hello()"
assert s.count(needle)==1
p.write_text(s.replace(needle, 'onLockedChanged: if (lifetime.kind === "ready") hello()'))
PY
jarvis_rescan
jarvis_lock_case stale
cp -- "$sandbox/jarvis-service-original" "$jarvis_service"
cp -- "$sandbox/jarvis-backend-original" "$jarvis_backend"
jarvis_rescan

"$node_bin" "$source_repo/scripts/fixtures/jarvis/prepare.js" --floor-daemon "$jarvis_backend"
jarvis_rescan
expect "the unsupported Node fixture enables" ok ipc shell setPluginEnabled vgs.jarvis true
expect_poll "Node exit 78 is a permanent problem without retries" permanent jarvis_permanent
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
cp -- "$sandbox/jarvis-service-original" "$jarvis_service"
cp -- "$sandbox/jarvis-backend-original" "$jarvis_backend"
jarvis_rescan

jarvis_enable
expect "five retries end in problem status" problem jarvis_exhaust
expect "retry exhaustion raises one Jarvis toast" 1 jarvis_toasts
expect "the exhausted service disables" ok ipc shell setPluginEnabled vgs.jarvis false

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
# names no identity, or found with neither.
jarvis_hint_of() { # STATE
  "$node_bin" -e '
const words = require(process.argv[1]);
const state = process.argv[2];
process.stdout.write(words.accountHint(state === "signed-in"
    ? { state, source: "cli", plan: "pro", email: "team@example.invalid", mismatch: false }
    : { state, source: "cli", plan: "", email: "", mismatch: false }));' "$source_repo/shell/plugins/vgs.jarvis/AccountStatus.js" "$1"
}
jarvis_account_hint() {
  local want
  want="$(jarvis_hint_of "$1")" || return 1
  ipc smoke jarvisProcess | py_reply '
import json,sys
rows=json.load(sys.stdin)["status"].get("accounts", [])
row=next((item for item in rows if item["label"] == "Claude Code / team"), None)
ok=row is not None and row["value"] == "present" and row["hint"] == sys.argv[1]
print("matched" if ok else "pending")
' "$want"
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
needle="if (shell === null) return;"
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
jarvis_notice_close
