# Remote desktop, vgs.remote-desktop, over stand-ins for gliff and
# gliff-server and a loopback test sshd. No call reaches a host gliff or a
# remote computer: `gliff` is a stand-in in the shell's PATH directory
# that records its argv, one JSON list a line, and answers --version as
# gliff 0.4.1; `gliff-server` there is a python stand-in whose kernel name
# is gliff-server, which the row starts with SSH_CONNECTION naming a
# TEST-NET-1 viewer. The sandbox HOME's SSH settings name smoke-alpha and,
# through `Include %d/.ssh/config.d/*.conf`, smoke-beta (hashed in
# known_hosts), smoke-stale (not in it) and a 70-character alias, and
# smoke-sshd, the row's sshd on 127.0.0.1, which runs as this user with
# its own host key, takes keys alone and runs each command with HOME in the
# row's remote home. The fakes' systemctl answers sshd.service as stopped.
# Read back, as states and argv, never wording or pixels: the seed writes
# one profile per known host and one launcher row each, the long host's too;
# with SSH off, Hosting has its text and the SSH step offers its action;
# idle, the widget is hidden and the poll timer stopped; one grim frame in
# the nested session raises Hyprland's `screencast` event, which shows the
# widget with the viewer and starts the poll; the viewer leaving, with no
# event, hides it through the poll, which stops; the launcher's Connect to
# smoke-beta hands gliff that profile's argv; the pane's Set up sign-in
# hands the terminal the sign-in script and the host; the script, run
# against smoke-sshd with the bootstrap key in an ssh-agent standing in
# for the typed password and an askpass for the typed passphrase, makes a
# key, installs it and signs in with it, keeps a key whose .pub is missing,
# refuses a passphrase key while no agent runs and loads it into the agent
# when one does; with hosting off, the service ends a
# new session by SIGTERM, and while the core reads `pending-restart` the
# Hosting field has its text. The control, a tree whose poll never runs,
# restarts the shell: the widget stays shown after the viewer left.
# The script's ssh goes through a wrapper that names the sandbox's SSH
# files, since ssh reads ~/.ssh from the account's home, not HOME.
# No latency is measured; each reading polls every 200 ms for up to 30 s.
# inputs: shell/plugins/vgs.remote-desktop/* shell/plugins/vgs.remote-desktop/helper/* shell/plugins/vgs.remote-desktop/tui/* shell/plugins/vgs.launcher/* shell/plugins/vgs.system/* shell/Ui/controls/BarItem.qml shell/Ui/BarWidget.qml shell/Ui/layout/ListItem.qml bin/lib/tui.sh scripts/smoke/shot.sh
set -euo pipefail
rd_id=vgs.remote-desktop
rd_dir="$sandbox/remote-desktop"
rd_user="$home/.config/vgshell/shell.json"
rd_remote="$rd_dir/remote-home"
rd_long="smoke-$(printf 'l%.0s' $(seq 1 64))"
rd_pid="" rd_sshd_pid="" rd_agent_pid=""
devices_ready remote-desktop || return 0
mkdir -p -- "$rd_dir/bin" "$home/.ssh/config.d" "$rd_remote/.ssh"
rd_python="$(command -v python3)" || { fail "remote-desktop: python3 is unavailable"; return 0; }
rd_sshd_bin="$(command -v sshd)" || rd_sshd_bin=""
cp -p -- "$rd_user" "$rd_dir/shell.json.before"
ssh-keygen -q -t ed25519 -N '' -f "$rd_dir/host_key" && ssh-keygen -q -t ed25519 -N '' -f "$rd_dir/bootstrap" || { fail "remote-desktop: the test keys could not be made"; return 0; }
cp -- "$rd_dir/bootstrap.pub" "$rd_remote/.ssh/authorized_keys"
rd_port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
printf 'Port %s\nListenAddress 127.0.0.1\nHostKey %s\nPidFile %s\nAuthorizedKeysFile %s\nUsePAM no\nPermitUserRC no\nStrictModes no\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nForceCommand env HOME=%s /bin/sh -c "$SSH_ORIGINAL_COMMAND"\n' \
  "$rd_port" "$rd_dir/host_key" "$rd_dir/sshd.pid" "$rd_remote/.ssh/authorized_keys" "$rd_remote" >"$rd_dir/sshd_config"
# smoke-sshd stands in the main file: ssh expands %d to the account's
# home, where the include names nothing.
printf 'Include %%d/.ssh/config.d/*.conf\nHost smoke-alpha\n  HostName 192.0.2.10\nHost smoke-sshd\n  HostName 127.0.0.1\n  Port %s\n  User %s\n' "$rd_port" "$(id -un)" >"$home/.ssh/config"
printf 'Host smoke-beta\n  HostName 192.0.2.20\nHost smoke-stale\n  HostName 192.0.2.30\nHost %s\n  HostName 192.0.2.40\n' "$rd_long" >"$home/.ssh/config.d/smoke.conf"
python3 - "$home/.ssh/known_hosts" "$rd_long" "$rd_port" "$rd_dir/host_key.pub" <<'PY'
import base64, hashlib, hmac, os, sys
path, long, port, host_key = sys.argv[1:]
salt = os.urandom(20)
hashed = "|1|%s|%s" % (base64.b64encode(salt).decode(), base64.b64encode(hmac.new(salt, b"192.0.2.20", hashlib.sha1).digest()).decode())
key = " ".join(open(host_key).read().split()[:2])
open(path, "w").write("smoke-alpha %s\n%s %s\n%s %s\n[127.0.0.1]:%s %s\n" % (key, hashed, key, long, key, port, key))
PY
printf '#!/usr/bin/env bash\n[[ ${1:-} == --version ]] && { echo "gliff 0.4.1"; exit 0; }\npython3 -c %q "$@" >>%q\n' \
  'import json,sys; print(json.dumps(sys.argv[1:]))' "$rd_dir/gliff.argv" >"$shim/gliff"
printf '#!%s\nimport time\nwhile True: time.sleep(3600)\n' "$rd_python" >"$shim/gliff-server"
printf '#!/usr/bin/env bash\nexec %q -F %q -o UserKnownHostsFile=%q -o IdentityFile=none "$@"\n' \
  "$(command -v ssh)" "$home/.ssh/config" "$home/.ssh/known_hosts" >"$rd_dir/bin/ssh"
# The askpass answers ssh-add for the passphrase a user types.
printf '#!/bin/sh\necho smoke-pass\n' >"$rd_dir/askpass"
chmod 755 "$shim/gliff" "$shim/gliff-server" "$rd_dir/bin/ssh" "$rd_dir/askpass"
device_reply systemctl 3 "" is-active --quiet sshd.service
device_reply systemctl 0 loaded show --property=LoadState --value sshd.service
terminal_stand_in
printf 'import QtQuick\nQtObject {\n    property var service: null\n    readonly property var timer: service === null ? null : Array.from(service.resources).find(r => r.objectName === "remote-desktop-poll") || null\n    readonly property var running: timer === null ? null : timer.running\n}\n' >"$rd_dir/PollObserver.qml"

rd_service() { ipc smoke readInstance service "$rd_id" "$1"; }
rd_widget() { ipc smoke readInstance "$(bar_key)" "$rd_id" "$1"; }
# rd_polling: whether the service's poll timer runs.
rd_polling() {
  local reading
  ipc smoke popupLoad rd-poll-observer "$rd_dir/PollObserver.qml" service "$rd_id" '{"service":"@instance"}' >/dev/null || return 1
  reading="$(ipc smoke popupRead rd-poll-observer running)" || return 1
  ipc smoke popupDrop rd-poll-observer >/dev/null || return 1
  printf '%s\n' "$reading"
}
rd_last_argv() { if [[ -f $rd_dir/gliff.argv ]]; then tail -n 1 -- "$rd_dir/gliff.argv"; else echo none; fi; }
rd_settings() { python3 -c 'import json,sys; r=[p for p in json.load(open(sys.argv[1])).get("plugins", []) if p["id"] == "vgs.remote-desktop"]; print(json.dumps([p["host"] for p in r[0].get("profiles", [])]) if r else "absent")' "$rd_user"; }
# rd_values EXPRESSION: the python EXPRESSION over the plugin's status
# values `v`, as JSON.
rd_values() { ipc smoke statusValues "$rd_id" | py_reply 'import json,sys; v=json.load(sys.stdin); print(json.dumps(eval(sys.argv[1])))' "$1"; }
# rd_set KEY JSON: one setting in the plugin's row, read by the shell; KEY
# beta merges JSON into smoke-beta's profile.
rd_set() {
  python3 - "$rd_user" "$1" "$2" <<'PY'
import json, os, sys
path, key, value = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
d = json.load(open(path))
row = next(p for p in d["plugins"] if p["id"] == "vgs.remote-desktop")
if key == "beta":
    row["profiles"] = [dict(p, **value) if p["host"] == "smoke-beta" else p for p in row["profiles"]]
else:
    row[key] = value
json.dump(d, open(path + ".next", "w"))
os.replace(path + ".next", path)
PY
  expect "the shell reads the $1 change" ok ipc shell reloadConfig
  expect_poll "the shell has read the $1 change" true ipc smoke configSettled
}
rd_viewer() { spawn "$rd_dir/server.log" env SSH_CONNECTION='192.0.2.10 52814 192.0.2.2 22' "$shim/gliff-server"; rd_pid="$spawn_pid"; }
rd_first_row() { ipc smoke launcherRows overlay vgs.launcher | py_reply 'import json,sys; t=sys.stdin.read(); r=json.loads(t) if t.startswith("[") else []; print(json.dumps(r[0][1]) if r else t.strip())'; }
rd_capture() { shot_grim "$(shot_socket "$rt_dir" "$nested_socket")" "$rt_dir" -t ppm "$rd_dir/frame.ppm" 2>>"$sandbox/grim.log"; }
# rd_gone PID: `gone` once the stand-in, this shell's child, has ended;
# rd_status PID: its exit status, read in this shell, 143 for SIGTERM.
rd_gone() { if [[ -e /proc/$1 && $(cut -d' ' -f3 "/proc/$1/stat" 2>/dev/null) != Z ]]; then echo running; else echo gone; fi; }
rd_status() { rd_exit=0; wait "$1" || rd_exit=$?; }
rd_listening() { python3 -c 'import socket,sys; socket.create_connection(("127.0.0.1", int(sys.argv[1])), 1).close(); print("up")' "$rd_port" 2>/dev/null || echo down; }
# rd_sign_in [none]: the sign-in script against smoke-sshd, with the
# row's agent, or with none.
rd_sign_in() {
  local agent=(SSH_AUTH_SOCK="$rd_dir/agent.sock")
  [[ ${1:-} != none ]] || agent=()
  env -i PATH="$rd_dir/bin:$PATH" HOME="$home" USER="$(id -un)" TERM=dumb "${agent[@]}" SSH_ASKPASS="$rd_dir/askpass" SSH_ASKPASS_REQUIRE=force \
    VGS_TUI_LIB="$repo/bin/lib/tui.sh" VGS_TUI_UNATTENDED=1 bash "$repo/shell/plugins/vgs.remote-desktop/tui/sign-in.sh" smoke-sshd </dev/null >>"$rd_dir/sign-in.log" 2>&1 && echo ok || echo "failed: $(tail -n 4 -- "$rd_dir/sign-in.log" | tr '\n' '|') sshd: $(tail -n 4 -- "$rd_dir/sshd.log" | tr '\n' '|')"
}
rd_refused() { [[ $(rd_sign_in none) == failed:* ]] && echo refused || echo ran; }
rd_new_key_signs_in() { SSH_AUTH_SOCK="$rd_dir/agent.sock" "$rd_dir/bin/ssh" -o BatchMode=yes -o IdentitiesOnly=yes -i "$home/.ssh/id_ed25519" smoke-sshd true </dev/null && echo yes || echo no; }
rd_restore() {
  local pid
  for pid in "$rd_pid" "$rd_sshd_pid" "$rd_agent_pid"; do [[ -z $pid ]] || kill -TERM -- "$pid" 2>/dev/null || true; done
  rm -f -- "${shim:?}/gliff" "${shim:?}/gliff-server"
  rm -rf -- "${home:?}/.ssh"
  device_reply_clear systemctl
  ipc shell hide window vgs.system >/dev/null || true
  ipc shell setPluginEnabled "$rd_id" false >/dev/null || true
  [[ $rd_launcher_before == True ]] || ipc shell setPluginEnabled vgs.launcher false >/dev/null || true
  cp -p -- "$rd_dir/shell.json.before" "$rd_user.next" && mv -T -- "$rd_user.next" "$rd_user"
  ipc shell reloadConfig >/dev/null || true
}
smoke_row_abandon=(rd_restore)

rd_launcher_before="$(plugin_enabled vgs.launcher)" || rd_launcher_before=unread
rescan "a rescan after the stand-ins answers ok"
leak_plugin_setup vgs.launcher true vgs.system true "$rd_id" true || { fail "remote-desktop: fixture precondition failed"; rd_restore; return 0; }
expect_poll "the service is built" True record_exists "$rd_id"
expect_poll "the seed writes one profile per computer known_hosts holds" "[\"smoke-beta\", \"$rd_long\", \"smoke-alpha\", \"smoke-sshd\"]" rd_settings
expect_poll "the launcher lists one row per profile, the long host's too" 4 rd_values 'len(v.get("connectRows", []))'
expect_poll "with SSH off, Hosting has its text and the SSH step its action" '["warning", true, true]' rd_values '[v["ssh"]["tone"], v["ssh"]["action"], v.get("hostingProblem") is not None] if "ssh" in v else "unpublished"'

# Idle: hidden, and no poll runs.
expect_poll "idle, the service reads no session" false rd_service active
expect "idle, the widget is hidden" false rd_widget shown
expect "idle, the poll timer is stopped" false rd_polling

# Someone views: the screencast event starts the probe.
rd_viewer
rd_capture || fail "the row's grim capture failed: $sandbox/grim.log"
expect_poll "a session after a capture shows the widget" true rd_widget shown
expect "the widget names the viewer by address and SSH name" '{"active":true,"peers":[{"address":"192.0.2.10","name":"smoke-alpha"}]}' rd_widget session
expect "the poll timer runs while a session is active" true rd_polling

# The viewer leaves with no event: the 2 s poll hides the widget.
kill -TERM -- "$rd_pid"
expect_poll "the stand-in session ends" gone rd_gone "$rd_pid"
rd_status "$rd_pid"
rd_pid=""
expect_poll "the poll hides the widget after the viewer left" false rd_widget shown
expect_poll "the poll timer stops once no session is active" false rd_polling

# A profile connects from the launcher with its own options.
rd_set beta '{"screen":"private","video":"cpu","capture":"shm","clipboard":false}'
expect "the launcher opens searching for smoke-beta" ok ipc shell summon overlay vgs.launcher '{"query":"Connect to smoke-beta"}'
expect_poll "the launcher holds the keyboard" true ipc smoke activeFocusIn overlay vgs.launcher
expect_poll "the launcher lists Connect to smoke-beta first" '"Connect to smoke-beta"' rd_first_row
type_keys -k Return || fail "Return in the launcher failed"
expect_poll "Connect hands gliff the profile's argv" '["--release-hotkey", "shift+escape", "--no-clipboard", "--video", "cpu", "--headless", "--server-bin", "gliff-server --capture shm", "--", "smoke-beta"]' rd_last_argv

# Set up sign-in: the pane hands the terminal the script and the host.
forget_record
expect "System Settings opens Remote desktop" ok ipc shell summon window vgs.system '{"pane":"vgs.remote-desktop"}'
click_item window:"System Settings" window vgs.system RowAction "Set up sign-in" || fail "the click on Set up sign-in failed"
expect_poll "Set up sign-in hands the terminal the sign-in script and the first computer" "$(words vgs.remote-desktop/sign-in tui/sign-in.sh smoke-beta)" recorded_tail
expect "System Settings closes" ok ipc shell hide window vgs.system

# The script against the test sshd: a key made, installed and used; a
# private key with no .pub kept, its .pub derived; a passphrase key with no
# agent refused before anything runs, and with one loaded into it.
if [[ -z $rd_sshd_bin ]]; then
  not_measured remote-desktop-sign-in "no sshd on PATH"
else
  spawn "$rd_dir/sshd.log" "$rd_sshd_bin" -D -e -f "$rd_dir/sshd_config"
  rd_sshd_pid="$spawn_pid"
  spawn "$rd_dir/agent.log" ssh-agent -D -a "$rd_dir/agent.sock"
  rd_agent_pid="$spawn_pid"
  expect_poll "the test sshd listens" up rd_listening
  expect_poll "the agent takes the bootstrap key" ok bash -c 'SSH_AUTH_SOCK="$1" ssh-add -q "$2" 2>/dev/null && echo ok' _ "$rd_dir/agent.sock" "$rd_dir/bootstrap"
  expect "Set up sign-in ends with sign-in working" ok rd_sign_in
  expect "the new key is in the remote authorized_keys" yes bash -c 'grep -qxF -- "$(cat "$1")" "$2" && echo yes' _ "$home/.ssh/id_ed25519.pub" "$rd_remote/.ssh/authorized_keys"
  expect "the new key alone signs in" yes rd_new_key_signs_in
  rd_key_sum="$(sha256sum <"$home/.ssh/id_ed25519")"
  rm -f -- "${home:?}/.ssh/id_ed25519.pub"
  expect "Set up sign-in with a key and no .pub ends with sign-in working" ok rd_sign_in
  expect "a key with no .pub stays as it was" "$rd_key_sum" bash -c 'sha256sum <"$1"' _ "$home/.ssh/id_ed25519"
  expect "the derived .pub adds no key line" 2 bash -c 'grep -c . "$1"' _ "$rd_remote/.ssh/authorized_keys"
  rm -f -- "${home:?}/.ssh/id_ed25519" "${home:?}/.ssh/id_ed25519.pub"
  ssh-keygen -q -t ed25519 -N smoke-pass -f "$home/.ssh/id_ed25519" </dev/null || fail "the passphrase key could not be made"
  rd_key_sum="$(sha256sum <"$home/.ssh/id_ed25519")"
  expect "a passphrase key with no agent is refused" refused rd_refused
  expect "the refused run copies no key" 2 bash -c 'grep -c . "$1"' _ "$rd_remote/.ssh/authorized_keys"
  expect "Set up sign-in loads a passphrase key into the agent and signs in" ok rd_sign_in
  expect "the passphrase key stays as it was" "$rd_key_sum" bash -c 'sha256sum <"$1"' _ "$home/.ssh/id_ed25519"
  expect "the passphrase key alone signs in through the agent" yes rd_new_key_signs_in
fi

# Hosting off: a session is ended, and pending-restart has its text.
# The sandbox has no notification server, so the core logs the notice
# unsent: that line is the service's one notice.
expected_errors+=('notify: unsent plugin=vgs\.remote-desktop ')
rd_viewer
rd_set hosting false
expect_poll "hosting off ends the session" gone rd_gone "$rd_pid"
rd_status "$rd_pid"
expect "the session ended by SIGTERM" 143 echo "$rd_exit"
rd_pid=""
expect_log "the service sends one notice for the ended session" 1 'notify: unsent plugin=vgs\.remote-desktop '
expect_poll "the core reads the permission block as pending-restart" '"pending-restart"' rd_service permission
expect_poll "while pending-restart, the Hosting field has its text" true rd_values 'v.get("hostingProblem") is not None'

# Control: with a poll that never runs, the widget stays shown after the
# viewer left, and the hiding assertion fails.
rd_hides_after_leaving() {
  (failures=0
   expect_poll "the poll hides the widget after the viewer left" false rd_widget shown >"$rd_dir/control.log"
   echo "$failures")
}
if copy_tree remote-desktop-no-poll && edit_tree remote-desktop-no-poll shell/plugins/vgs.remote-desktop/Service.qml \
    'running: root.active' 'running: false'; then
  rd_set hosting true
  stop_shell || :
  if start_shell "$sandbox/tree-remote-desktop-no-poll" "$sandbox/remote-desktop-no-poll-qs.log"; then
    expect_poll "control: the no-poll service is built" True record_exists "$rd_id"
    rd_viewer
    rd_capture || fail "control: the row's grim capture failed: $sandbox/grim.log"
    expect_poll "control: a session shows the widget" true rd_widget shown
    kill -TERM -- "$rd_pid"
    expect_poll "control: the stand-in session ends" gone rd_gone "$rd_pid"
    rd_status "$rd_pid"
    rd_pid=""
    expect "control: with no poll, the hiding assertion fails" 1 rd_hides_after_leaving
  fi
  stop_shell || :
  start_shell "$repo" "$sandbox/remote-desktop-restored-qs.log" || fail "the remote desktop control restores the repository shell"
fi

rd_restore
smoke_row_abandon=()
