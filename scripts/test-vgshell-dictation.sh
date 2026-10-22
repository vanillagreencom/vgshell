#!/usr/bin/env bash
# Runs the shipped setup against stand-ins. No sudo, auth or unit starts.
set -euo pipefail
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"
suite=test-vgshell-dictation
tree="$tmp/tree"; commands="$tmp/commands"
mkdir -p "$tree/bin/lib" "$tree/config" "$commands" "$tmp/home"
cp -- "$repo/bin/vgshell" "$repo/bin/vgshell-dictation" "$tree/bin/"
cp -R -- "$repo/bin/lib/." "$tree/bin/lib/"
cp -R -- "$repo/config/voxtype" "$tree/config/"
cat >"$commands/voxtype" <<EOF2
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/voxtype.calls"
if [ "\${1:-}" = --config ]; then
  [ -f "\$2" ] || exit 65
  shift 2
fi
case "\$*" in
  'config get engine --json') echo '{"value":"parakeet"}' ;;
  'config get parakeet.model --json') echo '{"value":"parakeet-tdt-0.6b-v3"}' ;;
  'info engines --json') cat "$tmp/engines.json" ;;
  'info models --json') cat "$tmp/models.json" ;;
  'setup --download --model parakeet-tdt-0.6b-v3 --no-post-install') exit 0 ;;
  *) exit 64 ;;
esac
EOF2
cat >"$commands/gum" <<EOF2
#!/bin/sh
case "\$1" in
  style) exit 0 ;;
  confirm) exit "\$(cat "$tmp/answer")" ;;
  *) exit 64 ;;
esac
EOF2
cat >"$tree/bin/vgshell-system" <<EOF2
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/system.calls"
exit 0
EOF2
for name in sudo systemctl; do
  printf '#!/bin/sh\nprintf "%%s\\n" forbidden >>%q\nexit 64\n' "$tmp/forbidden" >"$commands/$name"
done
chmod +x "$commands"/* "$tree/bin/vgshell-system"
setup_run() { # EXPECTED_EXIT [ANSWER_STATUS]
  local expected="${1:-0}" answer="${2:-0}" code=0
  printf '%s\n' "$answer" >"$tmp/answer"
  "${base_env[@]}" PATH="$commands:$base_path" XDG_CONFIG_HOME="$tmp/home/config & # \"quoted\"" SHELL="$BASH" \
    script -qec "$(printf '%q ' "$BASH" "$tree/bin/vgshell" dictation setup)" /dev/null \
    </dev/null >"$tmp/setup.out" 2>&1 || code=$?
  test "$code" == "$expected"
}
config_dir="$tmp/home/config & # \"quoted\"/voxtype"
no_changes() {
  [[ ! -e $config_dir && ! -e $tmp/system.calls ]] || return 1
  [[ -f $tmp/voxtype.calls ]] || return 1
  ! grep -E '^(daemon|setup)( |$)' "$tmp/voxtype.calls"
}
declined_clean() { # ANSWER_STATUS
  local result=0
  rm -rf -- "${tmp:?}/home/config & # \"quoted\"/voxtype"
  rm -f -- "$tmp/system.calls" "$tmp/voxtype.calls"
  setup_run 130 "$1" || result=$?
  no_changes || return 1
  test "$result" == 0
}
printf '[{"name":"parakeet","compiled":true}]\n' >"$tmp/engines.json"
printf '{"engines":{"parakeet":{"models":[{"name":"parakeet-tdt-0.6b-v3","installed":false}]}}}\n' >"$tmp/models.json"
check "No writes no config and starts no daemon, model download or system step" declined_clean 1
check "cancelling writes no config and starts no daemon, model download or system step" declined_clean 130
check "setup succeeds against the compiled stand-in" setup_run
check "setup copies the core defaults and expands the sound path" python3 -c 'import pathlib,sys,tomllib; p=pathlib.Path(sys.argv[1]); d=tomllib.loads((p/"config.toml").read_text()); assert d["audio"]["feedback"]["theme"]==str(p/"sounds/bloop"); assert all((p/"sounds/bloop"/n).is_file() for n in ["start.wav","stop.wav","error.wav","LICENSE"])' "$config_dir"
check "setup downloads the configured model without a user unit" grep -qxF -- 'setup --download --model parakeet-tdt-0.6b-v3 --no-post-install' "$tmp/voxtype.calls"
check "a compiled engine calls no system step" test ! -e "$tmp/system.calls"
printf 'custom config\n' >"$config_dir/config.toml"
check "existing config permits setup" setup_run
check "setup preserves existing config bytes" test "$(cat -- "$config_dir/config.toml")" == 'custom config'
printf '[{"name":"parakeet","compiled":false}]\n' >"$tmp/engines.json"
check "an uncompiled engine runs the system step" setup_run
check "the system step owns engine elevation" grep -qxF -- 'apply voxtype-engine' "$tmp/system.calls"
printf '{"engines":{}}\n' >"$tmp/models.json"
check "an absent model inventory entry permits setup" setup_run
printf '{"engines":{"parakeet":{"models":[{"name":"parakeet-tdt-0.6b-v3","installed":true}]}}}\n' >"$tmp/models.json"
rm -f -- "$tmp/voxtype.calls"
check "setup with an installed model succeeds" setup_run
no_download() { ! grep -E '^setup ' "$tmp/voxtype.calls"; }
check "an installed model is not downloaded" no_download
check "no setup run starts sudo or systemctl" test ! -e "$tmp/forbidden"
# Each control changes the shipped operation in the private tree and must
# fail the corresponding behavioral reading. Restore it after each rule.
cp -- "$tree/bin/vgshell-dictation" "$tmp/setup-source"
python3 - "$tree/bin/vgshell-dictation" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]); s=p.read_text()
start=s.index('if [[ ${#config_read[@]} != 0 ]]; then')
end=s.index('\nfi',start)+len('\nfi')
block=s[start:end]
s=s[:start]+s[end:]
assert s.count('status=0\n')==1
p.write_text(s.replace('status=0\n',block+'\nstatus=0\n'))
PY
check "control: copying before consent fails the no-write reading" test "$(declined_clean 1; echo $?)" != 0
cp -- "$tmp/setup-source" "$tree/bin/vgshell-dictation"
python3 - "$tree/bin/vgshell-dictation" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]); s=p.read_text(); a='case "$status" in 0) ;; 1) exit 130 ;; *) exit "$status" ;; esac'; assert s.count(a)==1; p.write_text(s.replace(a,':'))
PY
check "control: bypassing No fails the no-write and no-start reading" test "$(declined_clean 1; echo $?)" != 0
cp -- "$tmp/setup-source" "$tree/bin/vgshell-dictation"
python3 - "$tree/bin/vgshell-dictation" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]); s=p.read_text(); a='if [[ $installed != yes ]]; then\n  vgs_tui_step "Downloading the speech model"'; assert s.count(a)==1; p.write_text(s.replace(a,'if true; then\n  vgs_tui_step "Downloading the speech model"'))
PY
rm -f -- "$tmp/voxtype.calls"
setup_run
check "control: removing the installed-model gate fails the no-download reading" test "$(no_download; echo $?)" != 0
cp -- "$tmp/setup-source" "$tree/bin/vgshell-dictation"
printf '{"engines":{"parakeet":{"models":[{"name":"parakeet-tdt-0.6b-v3","installed":false}]}}}\n' >"$tmp/models.json"
# A changed model argument must fail the stand-in's download contract.
python3 - "$tree/bin/vgshell-dictation" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]); s=p.read_text(); a='--model "$model"'; assert s.count(a)==1; p.write_text(s.replace(a,'--model wrong-model'))
PY
check "control: the download contract rejects a wrong model" test "$(setup_run; echo $?)" == 1
# All three transports own both raw pipes. A finite hostile child makes
# the same failure reproducible without relying on a timeout or a device.
cp -- "$tmp/setup-source" "$tree/bin/vgshell-dictation"
cat >"$commands/voxtype" <<'STUB'
#!/usr/bin/env python3
import os, pathlib, sys
case = os.environ.get("DICTATION_STREAM_CASE", "valid")
if case == "argv":
    with open(os.environ["DICTATION_ARGV_FILE"], "w") as log:
        log.write(" ".join(sys.argv[1:]) + "\n" + pathlib.Path(os.environ["ALSA_CONFIG_PATH"]).read_text())
elif case in ("stdout", "stderr"):
    fd = 1 if case == "stdout" else 2
    for _ in range(2048):
        os.write(fd, b"x" * 4096)
elif case == "lines":
    for _ in range(256):
        os.write(1, b'{"alt":"idle"}\n')
elif case == "valid":
    if "status" in sys.argv:
        print('{"alt":"idle"}')
    elif "daemon" not in sys.argv:
        print('{"status":"ok","text":"bounded transcript"}')
    print("diagnostic", file=sys.stderr)
    sys.exit(3)
STUB
chmod +x "$commands/voxtype"
transport_readings() {
  "${base_env[@]}" PATH="$commands:$base_path" python3 - "$BASH" "$tree/bin/vgshell-dictation" "$tmp" <<'TEST'
import os, pathlib, shutil, subprocess, sys
bash, helper, scratch = sys.argv[1:]
def run(role, case, target=helper):
    args = [role] if role != "run" else ["run", "--", "voxtype", "probe"]
    return subprocess.run([bash, target, *args], env={**os.environ, "ALSA_CONFIG_PATH": "/vgs-deliberately-absent", "DICTATION_STREAM_CASE": case, "DICTATION_ARGV_FILE": scratch + "/transport.argv"}, capture_output=True, timeout=15)
for role in ("daemon", "follow", "run"):
    result = run(role, "valid")
    assert result.returncode == 3, (role, result)
    assert result.stderr.strip() == b"diagnostic", (role, result)
    assert (result.stdout == b"") == (role == "daemon"), (role, result)
    for stream in ("stdout", "stderr"):
        result = run(role, stream)
        assert result.returncode == 74, (role, stream, result.returncode)
        assert len(result.stdout) <= 1048576 and len(result.stderr) <= 200, (role, stream)
        assert b"stream=overflow" in result.stderr, (role, stream)
result = run("follow", "lines")
assert result.returncode == 74 and len(result.stdout.splitlines()) <= 32, result
result = run("daemon", "argv")
assert result.returncode == 0 and result.stdout == b"", result
args, route = pathlib.Path(scratch, "transport.argv").read_text().split("\n", 1)
assert args == "--audio-device default daemon"
assert "pcm.!default" in route and "ctl.!default" in route
assert 'playback_node "-1"' in route and 'capture_node "-1"' in route
assert "type hw" not in route and "<" not in route
# The same behavioral assertion must reject a disposable transport whose
# raw-byte governor is removed; its child is finite and needs no cleanup.
control = pathlib.Path(scratch) / "transport-control"
(control / "bin/lib").mkdir(parents=True)
shutil.copyfile(helper, control / "bin/vgshell-dictation")
source = pathlib.Path(helper).parent / "lib/voxtype.sh"
text = source.read_text()
needle = "            if credit < 0:\n"
assert text.count(needle) == 1
(control / "bin/lib/voxtype.sh").write_text(text.replace(needle, "            if False:\n"))
mutant = run("daemon", "stderr", str(control / "bin/vgshell-dictation"))
assert mutant.returncode != 74, mutant
print("transport readings: bounded daemon/follow/run stdout and stderr; control rejected")
TEST
}
check "private dictation transports bound all child streams and retain finite results" transport_readings
rows_done "$suite"
