#!/usr/bin/env bash
# Drive scripts/smoke/shot.sh, the sandbox capture helpers, with no
# sandbox: plain Unix sockets stand in for the caller's and the nested
# Wayland sockets, and a stub grim on PATH writes the image each case
# needs. Each case pins the exit status and the first line on stderr. The controls at
# the end plant one defect per guard in a copy of the file and require the
# case that guard owns to go red. The scene cases drive
# scripts/sandbox-shots.sh itself up to its harness, in a scratch git
# repository, and the export cases drive scripts/smoke/tree.sh, which
# sandbox-shots.sh and the harness share.
#
# Exit 0 when every case and control holds, 1 otherwise, 77 when the scene
# cases could not run because scripts/smoke/gpu-fence.sh reported
# not-measured.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
helper="$repo/scripts/smoke/shot.sh"

# The EXIT trap is armed only on the directory mktemp made: an empty or
# non-directory answer never reaches rm -rf.
tmp="$(mktemp -d)" || { echo "test-sandbox-shots: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $tmp && ! -L $tmp ]] || { echo "test-sandbox-shots: scratch=not-a-directory value=[$tmp]" >&2; exit 1; }
tmp="$(cd -- "$tmp" && pwd -P)"
trap 'rm -rf -- "${tmp:?}"' EXIT
node_bin="$(node -e 'process.stdout.write(process.execPath)')"
export PATH="${node_bin%/*}:$PATH"
failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

# Execute the Google Drive scene's confirmation fixture with the device
# gum already present. Only confirmation sees the private answer; failure
# and interruption leave the caller's PATH and command bytes unchanged.
if python3 - "$repo" "$tmp" "$BASH" <<'PYCONFIRM'
from pathlib import Path
import os
import subprocess
import sys

repo, scratch, bash = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
text = (repo / "scripts/sandbox-shots.sh").read_text()
start = text.index('    local confirmation="$cs/confirmation"\n')
end = text.index('    rm -- "$home/googledrive-', start)
block = text[start:end]
scope = '      shell_start_path="$confirmation:$shell_start_path"\n'
assert block.count(scope) == 2
script = r'''set -euo pipefail
cs=$1 shim=$2 mode=$3
shell_start_path="$shim:/usr/bin:/bin"
before_path=$shell_start_path
failures=0
fail() { failures=$((failures + 1)); }
csr() {
  [[ $# == 3 && $1 == initialize && $2 == --pair ]] || return 91
  printf '%s\n' "$3" >>"$cs/calls"
  case $mode in
    failed) return 23 ;;
    interrupted) kill -TERM "$BASHPID"; return 92 ;;
  esac
  env -i PATH="$shell_start_path" VGS_TEST_RUN=1 "$BASH" -c \
    'source "$1"; vgs_tui_confirm fixture --default=false' _ "$cs/confirmation-fixture.sh"
}
exercise() {
''' + block + r'''}
status=0
exercise || status=$?
[[ $shell_start_path == "$before_path" ]] || exit 93
printf 'status=%s failures=%s\n' "$status" "$failures"
'''

def run(name, mode, source=script, occupied=False):
    root = scratch / ("confirmation-" + name)
    cs, shim = root / "scene", root / "shim"
    cs.mkdir(parents=True)
    shim.mkdir()
    gum = shim / "gum"
    original = b"#!/bin/sh\nexit 99\n"
    gum.write_bytes(original)
    gum.chmod(0o751)
    if occupied:
        (cs / "confirmation").mkdir()
        (cs / "confirmation/gum").write_bytes(b"owned elsewhere\n")
    result = subprocess.run([bash, "-c", source, "_", str(cs), str(shim), mode],
                            env={"PATH": os.environ["PATH"], "VGS_TEST_RUN": "1"},
                            capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, (name, result.returncode, result.stderr)
    assert gum.read_bytes() == original and gum.stat().st_mode & 0o777 == 0o751, name
    if occupied:
        assert (cs / "confirmation/gum").read_bytes() == b"owned elsewhere\n", name
    calls = (cs / "calls").read_text().splitlines() if (cs / "calls").exists() else []
    return result.stdout.strip(), calls

for mode, want in (("confirmed", "status=0 failures=0"),
                   ("failed", "status=0 failures=2"),
                   ("interrupted", "status=0 failures=2")):
    got, calls = run(mode, mode)
    assert got == want and calls == ["documents", "uploads"], (mode, got, calls)
got, calls = run("occupied", "confirmed", occupied=True)
assert got == "status=0 failures=1" and calls == [], (got, calls)
got, calls = run("shared-path-control", "confirmed", script.replace(scope, '      shell_start_path="$shell_start_path"\n'))
assert got == "status=0 failures=2" and calls == ["documents", "uploads"], (got, calls)
print("confirmation-fixture: inherited-gum=unchanged exits=confirmed,failed,interrupted private-occupied=refused control=shared-path-failed")
PYCONFIRM
then
  ok "Google Drive confirmation is private and preserves an inherited gum on every exit"
else
  fail "Google Drive confirmation fixture ownership"
fi

# Run each scene/row's actual rclone fixture through the production
# initializer. A preceding native-export fixture must not erase directory
# identity, and a local listing must never be enriched from the Drive root.
# These are admission checks, not a capture or an alternate sync model.
if python3 - "$repo" "$tmp" "$BASH" "$node_bin" <<'PYINITIALIZE'
from pathlib import Path
import json
import os
import shutil
import subprocess
import sys

repo, scratch, bash, node = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], sys.argv[4]
host_rclone = shutil.which("rclone")
assert host_rclone is not None, "rclone=missing"
row = (repo / "scripts/smoke/rows/googledrive.sh").read_text()
scene = (repo / "scripts/sandbox-shots.sh").read_text()
harness = (repo / "scripts/smoke/harness.sh").read_text()
start = harness.index("py_reply() {")
reader = harness[start:harness.index("\n}\n", start) + 3]
start = row.index("cs_values_recovery() {")
recovery = row[start:row.index("\n}\n", start) + 3]
pair_match = 'r.get("pairLabel")=="Two-way fixture"'
assert recovery.count(pair_match) == 1

def heredoc(text, opening):
    assert text.count(opening) == 1, opening
    start = text.index(opening)
    return text[start:text.index("\nSH\n", start) + 4]

fixtures = [
    ("smoke", heredoc(row, '  cat >"$shim/rclone" <<SH\n')),
    ("capture", heredoc(scene, '  cat >"$shim/rclone" <<SH\n')),
]
secret = heredoc(row, '  sentinel_stand_over "$shim/secret-tool" <<SH\n').replace(
    'sentinel_stand_over "$shim/secret-tool"', 'cat >"$shim/secret-tool"', 1)
bootstrap = r'''set -euo pipefail
shim=$1 cs_stub=$2 cs=$2 drive=$3 host_rclone=$4 host_node=$5
auth_log="$cs/auth.calls"
reply_reader="$(declare -f py_reply)"
'''
local_scope = r'[[ -n \$list && \$* == *vgsdrive:* ]]'
export_read = 'exports=set(open(sys.argv[2]).read().split()) if os.path.isfile(sys.argv[2]) else set()'
assert fixtures[0][1].count(export_read) == 1
assert fixtures[1][1].count(local_scope) == 1
controls = [
    # The old export branch returned Size-adjusted lsjson before ID
    # enrichment. Its directory listing had no exports to adjust.
    ("smoke-export-bypass", fixtures[0][1].replace(export_read,
        'if os.path.isfile(sys.argv[2]): print(json.dumps(items)); sys.exit()\n' + export_read), "identity-unknown"),
    ("capture-local-root", fixtures[1][1].replace(local_scope, r'[[ -n \$list ]]'), "rclone-failed"),
]

for name, fixture, cause in [(name, fixture, None) for name, fixture in fixtures] + controls:
    root = scratch / ("initialization-" + name)
    home, shim, stub = root / "home", root / "shim", root / "stub"
    drive, local = root / "googledrive-drive", home / "googledrive/two-way"
    remote, runtime = drive / "TwoWay", root / "runtime"
    for directory in (shim, stub / "secrets", local, remote, runtime):
        directory.mkdir(parents=True)
    for directory in (local, remote):
        for rel, content in [("RCLONE_TEST", "access\n"), ("subject.txt", "recover these exact bytes\n")] + [
                ("neutral-%s.txt" % n, "neutral %s\n" % n) for n in range(1, 9)]:
            file = directory / rel
            file.write_text(content)
            os.utime(file, (1700000000, 1700000000))
    # The native document belongs to the preceding copy fixture, not this
    # pair. Its marker is still present when initialization reads identity.
    (stub / "exports").write_text("native.docx\n")
    for key, value in (("client-id", "fixture-id"), ("client-secret", "fixture-secret"),
                       ("token", '{"access_token":"fixture-token","token_type":"Bearer"}'),
                       ("token.user", "someone@example.com")):
        (stub / "secrets" / key).write_text(value)
    setup = subprocess.run([bash, "-c", reader + bootstrap + fixture + secret +
                            '\nchmod 755 "$shim/rclone" "$shim/secret-tool"\n',
                            "_", str(shim), str(stub), str(drive), host_rclone, node],
                           env={"PATH": os.environ["PATH"], "VGS_TEST_RUN": "1"},
                           capture_output=True, text=True, timeout=10)
    assert setup.returncode == 0, (name, setup.stderr)
    pairs = home / ".config/vgshell/google-drive/pairs.json"
    pairs.parent.mkdir(parents=True)
    pairs.write_text(json.dumps({"pairs": [
        {"id": "two-way", "label": "Two-way fixture", "remote": "TwoWay", "local": str(local)}]}))
    lib = stub / "confirmation-fixture.sh"
    lib.write_text('vgs_tui_confirm() { gum confirm "$2" -- "$1"; }\n')
    gum = shim / "gum"
    gum.write_text('#!/usr/bin/env bash\n[[ $1 == confirm && $2 == --default=false ]] || exit 2\nexit 0\n')
    gum.chmod(0o755)
    env = {"PATH": str(shim) + ":" + os.environ["PATH"], "HOME": str(home),
           "XDG_CONFIG_HOME": str(home / ".config"), "XDG_STATE_HOME": str(home / ".local/state"),
           "XDG_DATA_HOME": str(home / ".local/share"), "XDG_RUNTIME_DIR": str(runtime),
           "TMPDIR": str(root), "VGS_TUI_LIB": str(lib), "VGS_TEST_RUN": "1", "LANG": "C.UTF-8"}
    result = subprocess.run([node, str(repo / "shell/plugins/vgs.google-drive/bin/google-drive"),
                             "initialize", "--pair", "two-way"], env=env,
                            capture_output=True, text=True, timeout=120)
    state = json.loads((home / ".local/state/vgshell/google-drive/pairs/two-way/state.json").read_text())
    if cause is None:
        assert result.returncode == 0 and result.stdout.endswith("initialized=two-way\n"), (
            name, result.returncode, result.stdout, result.stderr)
        assert state["baseline"] is not None, name
        (remote / "subject.txt").unlink()
        command = [node, str(repo / "shell/plugins/vgs.google-drive/bin/google-drive")]
        synced = subprocess.run(command + ["run", "--pair", "two-way"], env=env,
                                capture_output=True, text=True, timeout=120)
        assert synced.returncode == 0 and synced.stdout == "pair=two-way result=idle\n", (
            name, synced.returncode, synced.stdout, synced.stderr)
        assert not (local / "subject.txt").exists(), name
        record = subprocess.run(command + ["status"], env=env,
                                capture_output=True, text=True, timeout=10)
        assert record.returncode == 0, (name, record.stderr)
        conflicts = json.loads(record.stdout)["conflicts"]
        # cloudValue publishes pairLabel, not the runner record's pair.
        # This exercises the row's reader on real recovery bytes with that
        # published field contract; native smoke owns actual publication.
        for conflict in conflicts:
            conflict.pop("pair")
        published = json.dumps({"cloud": {"conflicts": conflicts}})
        for label, function, want in [
                ("published", recovery, ["two-way", "completed", "local-recovery", "recover these exact bytes\n"]),
                ("raw-pair-control", recovery.replace(pair_match, 'r.get("pair")=="two-way"'), None)]:
            readback = subprocess.run([bash, "-c", reader + '\nreply=$1\n' +
                'cs_values() { printf "%s\\n" "$reply"; }\n' + function + "\ncs_values_recovery\n",
                "_", published], env={"PATH": env["PATH"], "VGS_TEST_RUN": "1"},
                capture_output=True, text=True, timeout=10)
            assert readback.returncode == 0 and json.loads(readback.stdout) == want, (
                name, label, readback.returncode, readback.stdout, readback.stderr)
        print("recovery-reader: case=%s exact-bytes=retained published-pairLabel=read raw-pair-control=null" % name)
    else:
        print("initialization-fixture-control: case=%s exit=%s stderr=%s" % (
            name, result.returncode, json.dumps(result.stderr)), flush=True)
        assert result.returncode == 1 and "initialize=" + cause in result.stderr, (
            name, result.returncode, result.stdout, result.stderr)
        assert state["baseline"] is None, name
        assert (local / "subject.txt").read_bytes() == (remote / "subject.txt").read_bytes() == b"recover these exact bytes\n", name
    print("initialization-fixture: case=%s result=%s" % (name, "initialized" if cause is None else cause))
PYINITIALIZE
then
  ok "Google Drive fixtures preserve remote identity and local listing admission"
else
  fail "Google Drive initialization fixture boundary"
fi

# Execute the harness's PATH builder with planted host files. Lookup alone
# must find each registry stand-in, then none after it is moved away. The
# builder's account home is a scratch directory, so the cases hold wherever
# the caller's TMPDIR lies; the home case requires a shim link in a PATH
# directory under that home, and a host link that resolves into it, to
# resolve to none, while an ordinary host command still resolves. Each of
# the builder's two home checks has a control that drops it alone.
if python3 - "$repo" "$tmp" "$BASH" <<'PYPATH'
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys

repo, scratch, bash = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
harness = (repo / "scripts/smoke/harness.sh").read_text()
devices = (repo / "scripts/smoke/devices.sh").read_text()
registry = re.search(r"(?m)^device_stand_in_names=\([^)]*\)", devices).group()
auth = re.search(r"(?m)^auth_sentinels=\([^)]*\)", harness).group()
start = harness.index('python3 - "$sandbox/host-path"')
builder = harness[start:harness.index('shell_start_path="$shim:$shell_host_path"', start)]
resolver = next(line for line in harness.splitlines() if line.startswith("shell_resolves() {"))
needle = '"${device_stand_in_names[@]}" "${auth_sentinels[@]}" crontab hyprctl '
assert builder.count(needle) == 1
account_home = "pwd.getpwuid(os.getuid()).pw_dir"
assert builder.count(account_home) == 1
in_home_directory = "    if in_home(directory):\n        continue\n"
in_home_file = " or in_home(file)"
assert builder.count(in_home_directory) == 1 and builder.count(in_home_file) == 1
def run(name, code, own="", check=None, plant=None):
    """CODE, a copy of the builder, over a host directory of planted files
    and a scratch account home; CHECK, when given, replaces the registry
    loop, and PLANT(host, home) adds files and returns extra PATH entries."""
    root = scratch / name
    shim, host, sandbox, home = root / "shim", root / "host", root / "sandbox", root / "home"
    for directory in (shim, host, sandbox, home):
        directory.mkdir(parents=True)
    path = [str(host)] + (plant(host, home) if plant else [])
    code = code.replace(account_home, repr(str(home)))
    script = root / "case.sh"
    script.write_text('set -euo pipefail\n' + registry + '\n' + auth + '\n' +
        'shim=$1 sandbox=$2 node_bin=$3\nshell_hidden_commands=(' + own + ')\n' +
        'names=("${device_stand_in_names[@]}" "${auth_sentinels[@]}" crontab hyprctl)\n' +
        'for name in "${names[@]}"; do printf "#!/bin/sh\\nexit 99\\n" >"$shim/$name"; /bin/chmod 755 "$shim/$name"; /bin/cp "$shim/$name" "$4/$name"; done\n' +
        code + 'shell_start_path="$shim:$shell_host_path"\n' + resolver + '\n' +
        (check or 'for name in "${names[@]}"; do [[ $(shell_resolves "$name") == "$shim/$name" ]] || exit 21; /bin/mv "$shim/$name" "$shim/$name.moved"; [[ $(shell_resolves "$name") == none ]] || exit 22; done\n'))
    (host / "python3").symlink_to(shutil.which("python3"))
    return subprocess.run([bash, str(script), str(shim), str(sandbox), "/usr/bin/true", str(host)],
                          env={"PATH": ":".join(path), "LC_ALL": "C"}, capture_output=True, text=True, timeout=10)
for runner, own in (("qml-smoke", "vsys voxtype claude codex"), ("sandbox-shots", "voxtype voxtype-audio-bridge")):
    result = run(runner + "-world", builder, own)
    assert result.returncode == 0, (runner, result.returncode, result.stderr)
    result = run(runner + "-mutant", builder.replace(needle, ""), own)
    assert result.returncode == 22, (runner, result.returncode, result.stderr)
    print("registry-hiding: runner=%s stand-ins=present missing=none control=host-fixture-found" % runner)
def home_plant(host, home):
    # pi: a version manager's shim, a link in a PATH directory under the
    # home whose file is outside it (mise's shims link to /usr/bin/mise).
    # agent-cli: a host PATH link whose file is in the home. host-tool:
    # neither.
    outside = home.parent / "outside"
    for directory, name in ((outside, "mise"), (home / "tools", "agent-cli"), (host, "host-tool")):
        directory.mkdir(exist_ok=True)
        (directory / name).write_text("#!/bin/sh\nexit 0\n")
        (directory / name).chmod(0o755)
    (home / "bin").mkdir()
    (home / "bin" / "pi").symlink_to(outside / "mise")
    (host / "agent-cli").symlink_to(home / "tools" / "agent-cli")
    return [str(home / "bin")]
home_check = 'for name in pi agent-cli host-tool; do shell_resolves "$name"; done\n'
def home_case(name, code):
    result = run(name, code, check=home_check, plant=home_plant)
    assert result.returncode == 0, (name, result.returncode, result.stderr)
    return [line.rsplit("/", 2)[-2:] if line != "none" else "none" for line in result.stdout.splitlines()]
got = home_case("home-world", builder)
assert got == ["none", "none", ["host-path", "host-tool"]], got
got = home_case("home-no-directory-check", builder.replace(in_home_directory, ""))
assert got == [["host-path", "pi"], "none", ["host-path", "host-tool"]], got
got = home_case("home-no-file-check", builder.replace(in_home_file, ""))
assert got == ["none", ["host-path", "agent-cli"], ["host-path", "host-tool"]], got
print("home-commands: pi=none agent-cli=none host-tool=linked controls=directory-check:pi-linked,file-check:agent-cli-linked")
PYPATH
then
  ok "both runners hide the whole stand-in registry and reject a harness without registry hiding"
  ok "the host PATH links no command from the account home and rejects a harness without the home rule"
else
  fail "stand-in registry hiding or the home rule"
fi

# These records come from the scene desktop before a modal scrim opens.
# Run the shot script's pair check itself without starting its sandbox.
mkdir -p "$tmp/desktop-before" "$tmp/desktop-after"
printf 'polkit\tlight\tbefore\t100\t100\t000000\n' >"$tmp/desktop-before/desktop.tsv"
desktop_pair_case() { # SCRIPT RGB EXPECTED_EXIT
  local status=0
  printf 'polkit\tlight\tafter\t100\t100\t%s\n' "$2" >"$tmp/desktop-after/desktop.tsv"
  "$BASH" "$1" --check-desktop-pair "$tmp/desktop-before" "$tmp/desktop-after" >"$tmp/desktop-pair.log" 2>&1 || status=$?
  [[ $status -eq $3 ]]
}
for spec in '000000 0' '111111 1' 'unreadable 1'; do
  read -r rgb expected <<<"$spec"
  if desktop_pair_case "$repo/scripts/sandbox-shots.sh" "$rgb" "$expected"; then
    ok "desktop pair: $rgb exits $expected"
  else
    fail "desktop pair: $rgb does not exit $expected"
  fi
done
desktop_mutant="$tmp/desktop-mutant.sh"
python3 - "$repo/scripts/sandbox-shots.sh" "$desktop_mutant" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
needle = '        if a != b:\n'
assert text.count(needle) == 1
pathlib.Path(sys.argv[2]).write_text(text.replace(needle, '        if False:\n'))
PY
if desktop_pair_case "$desktop_mutant" 111111 1; then
  fail "control: removing the desktop comparison leaves its differing-pair case green"
else
  ok "control: removing the desktop comparison fails its differing-pair case"
fi

# A newly mapped Settings window takes pointer presses only after a move.
# Exercise the harness's real coordinate and click helpers without a shell.
click_helper="$tmp/click-helper.sh"
sed -n '/^at_centre() {/,/^}/p; /^click_in() {/,/^}/p' "$repo/scripts/smoke/harness.sh" >"$click_helper"
click_case() {
  env -i PATH="$PATH" bash -c '
set -euo pipefail
source "$1"
ipc() { printf "%s\n" "[20, 30, 40, 20]"; }
surface_box() { printf "%s\n" "[100, 200, 800, 600]"; }
hover() { [[ $1 == 141 && $2 == 240 ]] && moved=true; }
click() { [[ ${moved:-false} == true && $1 == 140 && $2 == 240 ]]; }
click_in window:Plugins window vgs.settings Button Install
' _ "$1"
}
if click_case "$click_helper"; then ok "a click moves the pointer before pressing in a newly mapped window"; else fail "the pointer press did not reach the mapped window"; fi
click_mutant="$tmp/click-mutant.sh"
python3 - "$click_helper" "$click_mutant" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
needle = '  hover "$((x + 1))" "$y" || return $?\n'
assert text.count(needle) == 1
pathlib.Path(sys.argv[2]).write_text(text.replace(needle, ""))
PY
if click_case "$click_mutant"; then fail "control: a click without a pointer move reached the mapped window"; else ok "control: a click without a pointer move misses the mapped window"; fi

# Bar geometry includes clipped widgets. Drive the real reveal helper
# against the probe's section/drop contract, recording the scroll button
# it presses; the nested scene proves event delivery and tooltip drawing.
bar_helper="$tmp/bar-helper.sh"
sed -n '/^bar_widget_reveal() {/,/^}/p; /^centre_of() {/p' "$repo/scripts/sandbox-shots.sh" >"$bar_helper"
bar_reveal_case() { # HELPER SIDE X BUTTON
  local helper="$1" side="$2" x="$3" button="$4"
  rm -f -- "$tmp/bar-clicks" "$tmp/bar-ready" "$tmp/bar-hovered" "$tmp/bar-target"
  env -i PATH="$tmp/bin:$PATH" T="$tmp" SIDE="$side" X="$x" "$BASH" -c '
set -euo pipefail
source "$1"
bar_key() { echo bar; }
smoke_poll_tries() { smoke_poll_n=6; }
py_reply() { python3 -c "$@"; }
ipc() {
  case $2 in
    instanceGeometry) echo "[100, 0, 32, 28]"; return ;;
    descendantGeometry)
      [[ $3 == bar && $4 == vgs.bar ]] || return 1
      printf "[{\"name\":\"bar-zone-%s-%s\",\"visible\":true,\"box\":[10,0,20,28]}]\n" "$SIDE" "$([[ $X == 80 ]] && echo start || echo end)"
      return ;;
    readMatchingDescendant)
      [[ $3 == bar && $4 == vgs.bar && $5 == BarItem && $6 == objectName && $8 == hovered ]] || return 1
      [[ -f $T/bar-hovered ]] || return 1
      printf "%s\n" "$7" >"$T/bar-target"
      echo true; return ;;
    barParticipationGeometry) ;;
    *) return 1 ;;
  esac
  python3 - "$SIDE" "$X" "$T/bar-ready" <<"PYBAR"
import json, os, sys
side, x, ready=sys.argv[1:]
drop={"widgets": [{"locator": {"id": "test.widget"}, "x": 120 if os.path.exists(ready) else int(x), "width": 32}]}
if side != "center": drop["shown"]={"x": 100, "width": 80}
print(json.dumps({"sections": [{"section": side, "drop": drop}]}))
PYBAR
}
hover() { [[ $1 == 21 && $2 == 14 ]] && : >"$T/bar-hovered"; }
click() { [[ $1 == 20 && $2 == 14 ]] && cat "$T/bar-target" >>"$T/bar-clicks" && : >"$T/bar-ready"; }
bar_widget_reveal test.widget
' _ "$helper" || return 1
  if [[ $button == none ]]; then [[ ! -e $tmp/bar-clicks ]]
  else [[ -f $tmp/bar-clicks && $(cat "$tmp/bar-clicks") == "$button" ]]; fi
}
while read -r side x button; do
  if bar_reveal_case "$bar_helper" "$side" "$x" "$button"; then ok "bar reveal: $side at $x presses $button"; else fail "bar reveal: $side at $x presses $button"; fi
done <<'BARCASES'
left 80 bar-zone-left-start
left 180 bar-zone-left-end
right 80 bar-zone-right-start
right 180 bar-zone-right-end
right 120 none
center 80 none
BARCASES
bar_mutant="$tmp/bar-mutant.sh"
python3 - "$bar_helper" "$bar_mutant" <<'PY'
import pathlib, sys
text=pathlib.Path(sys.argv[1]).read_text()
needle='print("bar-zone-" + side + "-start")'
assert text.count(needle) == 1
pathlib.Path(sys.argv[2]).write_text(text.replace(needle, 'print("ready")'))
PY
if bar_reveal_case "$bar_mutant" right 80 bar-zone-right-start; then fail "control: a clipped widget is accepted without scrolling"; else ok "control: a clipped widget is rejected without scrolling"; fi

# These readiness readers consume instanceGeometry's machine replies. A
# failed ipc_via operation prints ipc-failed and exits 1, not shown.
panel_helper="$tmp/panel-helper.sh"
python3 - "$repo/scripts/sandbox-shots.sh" "$panel_helper" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
parts = []
for name in ("tailscale_shot_panel", "vpn_locked_panel"):
    needle = name + "() {\n"
    assert source.count(needle) == 1
    start = source.index(needle)
    end = source.index("\n}\n", start) + 3
    parts.append(source[start:end])
pathlib.Path(sys.argv[2]).write_text("\n".join(parts))
PY
panel_case() { # HELPER
  local helper="$1" reader response expected_status expected_state status state
  for reader in tailscale_shot_panel vpn_locked_panel; do
    while IFS='|' read -r response expected_status expected_state; do
      status=0
      state="$(env -i PATH="$PATH" REPLY="$response" STATUS="$expected_status" "$BASH" -c '
set -euo pipefail
source "$1"
locked_id=vgs.tailscale
ipc() { printf "%s\n" "$REPLY"; return "$STATUS"; }
"$2"
' _ "$helper" "$reader")" || status=$?
      [[ $status -eq $expected_status && $state == "$expected_state" ]] || return 1
    done <<'PANELCASES'
[100,0,32,28]|0|shown
absent|0|hidden
ipc-failed|1|
PANELCASES
  done
}
if panel_case "$panel_helper"; then ok "backend panel readers distinguish shown, absent and failed IPC"; else fail "backend panel reader accepts unavailable geometry"; fi
panel_mutant="$tmp/panel-mutant.sh"
python3 - "$panel_helper" "$panel_mutant" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
needle = ' || return $?'
assert source.count(needle) == 2
changed = source.replace(needle, ' || :')
assert changed != source
pathlib.Path(sys.argv[2]).write_text(changed)
PY
if panel_case "$panel_mutant"; then fail "control: dropping backend panel IPC statuses stayed green"; else ok "control: dropping backend panel IPC statuses fails"; fi

# Pointer targets and reserved space use logical dimensions at every scale.
size_helper="$tmp/size-helper.sh"
sed -n '/^monitor_size() {/p; /^bar_settled_judge() {/,/^}/p' "$repo/scripts/smoke/harness.sh" >"$size_helper"
size_case() {
  env -i PATH="$PATH" bash -c '
set -euo pipefail
source "$1"
py_reply() { python3 -c "$@"; }
for scale in 1 2; do
  monitors="[{\"name\":\"WAYLAND-1\",\"width\":$((1440 * scale)),\"height\":$((900 * scale)),\"scale\":$scale,\"reserved\":[0,36,0,0]}]"
  hypr() { printf "%s\n" "$monitors"; }
  [[ $(monitor_size) == "1440 900 36" ]] || exit 1
  layers="{\"WAYLAND-1\":{\"levels\":{\"2\":[{\"namespace\":\"vgs:bar\",\"pid\":123}]}}}"
  [[ $(printf "%s\n%s\n" "$monitors" "$layers" | bar_settled_judge WAYLAND-1) == "1440 900 36" ]] || exit 1
done
' _ "$1"
}
if size_case "$size_helper"; then ok "monitor and settled-bar readers return logical sizes at scales 1 and 2"; else fail "monitor or settled-bar reader returned a physical size"; fi
for reader in monitor_size bar_settled_judge; do
  size_mutant="$tmp/size-$reader-mutant.sh"
  python3 - "$size_helper" "$size_mutant" "$reader" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
start = text.index(sys.argv[3] + '() {')
end = text.index('\n}', start) + 2 if sys.argv[3] == 'bar_settled_judge' else text.index('\n', start)
body = text[start:end]
assert body.count(' / m["scale"]') == 2
pathlib.Path(sys.argv[2]).write_text(text[:start] + body.replace(' / m["scale"]', '') + text[end:])
PY
  if size_case "$size_mutant"; then fail "control: $reader physical sizes passed the scale-2 pointer case"; else ok "control: $reader physical sizes fail the scale-2 pointer case"; fi
done

# The caller's runtime dir with its socket, and the sandbox's beneath it,
# as the harness makes them.
host="$(mktemp -d "$XDG_RUNTIME_DIR/owned/shots.XXXXXX")" || exit 1
rt="$host/vs.test"
mkdir -p "$rt" "$tmp/bin" "$tmp/checkout/tmp"
python3 - "$host/wayland-1" "$host/wayland-2" "$rt/wayland-1" <<'PY'
import socket, sys
for path in sys.argv[1:]:
    socket.socket(socket.AF_UNIX).bind(path)
PY
ln -s "$host/wayland-1" "$rt/wayland-9"
: >"$rt/wayland-file"

# The stub grim: the mode file beside it picks what it writes to its last
# argument, since shot.sh runs grim in an empty environment. fixed-a and
# fixed-b write one image each time; counter writes a new one each call;
# hang never returns; unsized-layout fails as grim 1.5.0 does when the
# layout holds an output with no size, unless -o names the sized output
# WAYLAND-1. pixel-scale2 follows grim's default output scale of 2,
# unless -s sets the image scale to 1. It records its environment in env.log.
cat >"$tmp/bin/grim" <<'SH'
#!/usr/bin/env bash
out="${!#}"
here="${0%/*}"
env | sort >"$here/env.log"
case "$(cat "$here/mode")" in
  fixed-a) printf 'image-a' >"$out" ;;
  fixed-b) printf 'image-b' >"$out" ;;
  counter) n=$(( $(cat "$here/count" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$here/count"; printf 'image-%s' "$n" >"$out" ;;
  hang) sleep 5 ;;
  unsized-layout) if [[ $1 == -o && $2 == WAYLAND-1 ]]; then printf 'image-b' >"$out"; else echo "failed to create buffer" >&2; exit 1; fi ;;
  pixel-scale2)
    if [[ $1 == -s && $2 == 1 ]]; then
      printf 'P6\n1 1\n255\n\x33\x66\x99'
    else
      printf 'P6\n2 2\n255\n\x33\x66\x99\x33\x66\x99\x33\x66\x99\x33\x66\x99'
    fi ;;
esac
SH
chmod 755 "$tmp/bin/grim"
hash_a="$(printf 'image-a' | sha256sum | cut -d' ' -f1)"
# run_case FILE LABEL SNIPPET STATUS LINE: true when the helper FILE gives
# the status and first stderr line. The snippet runs with the helper
# sourced, in an empty environment holding a marker that must never reach
# grim: T the test dir, RT the sandbox's runtime dir, HOST the caller's,
# which XDG_RUNTIME_DIR names, D an empty dir under the checkout's tmp/,
# and SHOT_DIR, SHOT_SOCKET and SHOT_RUNTIME_DIR and SHOT_OUTPUT set for
# `shot`.
run_case() {
  local file="$1" label="$2" snippet="$3" want_status="$4" want_line="$5" err status=0 dir
  dir="$tmp/checkout/tmp/case-$RANDOM$RANDOM"
  mkdir -p "$dir"
  env -i PATH="$tmp/bin:$PATH" HOST_MARKER=live T="$tmp" RT="$rt" HOST="$host" XDG_RUNTIME_DIR="$host" D="$dir" HASH_A="$hash_a" \
    SHOT_DIR="$dir" SHOT_SOCKET="$rt/wayland-1" SHOT_RUNTIME_DIR="$rt" SHOT_OUTPUT=WAYLAND-1 \
    bash -c 'set -euo pipefail; source "$1"; eval "$2"' _ "$file" "$snippet" >"$dir/out" 2>"$dir/err" || status=$?
  err="$(head -n 1 "$dir/err")"
  [[ $status -eq $want_status && $err == "$want_line" ]] && return 0
  printf '        %s: status=%s want=%s first stderr line: %s\n' "$label" "$status" "$want_status" "$err"
  return 1
}

# Cases, four fields each: label, snippet, status, first stderr line.
cases=(
  "the nested socket resolves"
  '[[ $(shot_socket "$RT" wayland-1) == "$RT/wayland-1" ]]' 0 ""
  "the caller's runtime dir is refused"
  'shot_socket "$HOST" wayland-1' 1 "shot: refused: reason=caller-runtime-dir value=$host"
  "a link out of the sandbox's runtime dir is refused"
  'shot_socket "$RT" wayland-9' 1 "shot: refused: reason=outside-runtime-dir value=$host/wayland-1"
  "a caller with no runtime dir named is refused"
  'unset XDG_RUNTIME_DIR; shot_socket "$RT" wayland-1' 1 "shot: refused: reason=caller-runtime-dir-unnamed value=$rt"
  "a path for a socket name is refused"
  'shot_socket "$RT" ../wayland-1' 1 "shot: refused: reason=socket-not-a-name value=../wayland-1"
  "a file that is no socket is refused"
  'shot_socket "$RT" wayland-file' 1 "shot: refused: reason=not-a-socket value=$rt/wayland-file"
  "an output dir under tmp/ is made"
  '[[ $(shot_dir_under "$T/checkout" "$T/checkout/tmp/shots/a") == "$T/checkout/tmp/shots/a" ]]' 0 ""
  "an output dir outside tmp/ is refused"
  'shot_dir_under "$T/checkout" "$T/elsewhere"' 1 "shot: refused: reason=out-dir-outside-tmp value=$tmp/elsewhere"
  "a new settled capture is taken"
  'echo fixed-b >"$T/bin/mode"; shot one >/dev/null; want="$(printf "one\t%s\t-\tsettled\t-" "$(printf image-b | sha256sum | cut -d" " -f1)")"; [[ $(cat "$D/shots.tsv") == "$want" && $(cat "$D/one.png") == image-b ]]' 0 ""
  "a capture equal to the previous shot is stale"
  'echo fixed-a >"$T/bin/mode"; shot_last_name=before; shot_last_hash="$HASH_A"; SHOT_SETTLE_S=1 shot two' 1 "shot: stale name=two previous=before sha256=$hash_a"
  "a capture that keeps changing is taken as animated"
  'echo counter >"$T/bin/mode"; SHOT_SETTLE_S=1 shot three >/dev/null; [[ $(cut -f1,4 "$D/shots.tsv") == $(printf "three\tanimated") ]]' 0 ""
  "a grim that never returns fails the shot"
  'echo hang >"$T/bin/mode"; SHOT_GRIM_TIMEOUT_S=1 shot four' 1 "shot: capture-failed name=four grim-status=timeout"
  "grim sees only the nested socket"
  'echo fixed-b >"$T/bin/mode"; shot five >/dev/null; grep -qx WAYLAND_DISPLAY=wayland-1 "$T/bin/env.log"; grep -qx "XDG_RUNTIME_DIR=$RT" "$T/bin/env.log"; ! grep -q HOST_MARKER "$T/bin/env.log"' 0 ""
  "a layout pixel on a scale-2 output reads its colour"
  'echo pixel-scale2 >"$T/bin/mode"; [[ $(shot_pixel "$RT/wayland-1" "$RT" 10 20) == 336699 ]]' 0 ""
  "a capture of its own output is taken while another output has no size"
  'echo unsized-layout >"$T/bin/mode"; shot nine >/dev/null; [[ $(cat "$D/nine.png") == image-b ]]' 0 ""
  "a shot with no output named is refused"
  'echo fixed-b >"$T/bin/mode"; SHOT_OUTPUT= shot ten' 1 "shot: refused: reason=output-unnamed value=ten"
  "a shot records clean chrome"
  'echo fixed-b >"$T/bin/mode"; chrome() { echo clean; }; SHOT_CHROME_READER=chrome shot sixteen >/dev/null; [[ $(cut -f1,5 "$D/shots.tsv") == $(printf "sixteen\tclean") && -e $D/sixteen.png ]]' 0 ""
  "a shot with required clean chrome is taken"
  'echo fixed-b >"$T/bin/mode"; chrome() { echo clean; }; SHOT_CHROME_READER=chrome SHOT_CHROME_REQUIRE=clean shot seventeen >/dev/null; [[ $(cut -f1,5 "$D/shots.tsv") == $(printf "seventeen\tclean") && -e $D/seventeen.png ]]' 0 ""
  "a shot with tooltip chrome is refused"
  'echo fixed-b >"$T/bin/mode"; chrome() { echo tooltip; }; s=0; SHOT_CHROME_READER=chrome SHOT_CHROME_REQUIRE=clean shot eighteen >/dev/null || s=$?; [[ ! -e $D/shots.tsv && ! -e $D/eighteen.png ]] || exit 9; exit "$s"' 1 "shot: refused: reason=chrome value=tooltip"
)
# run_cases FILE CASES: every case of the array CASES against FILE.
run_cases() {
  local file="$1" i
  local -n rows="$2"
  for (( i = 0; i < ${#rows[@]}; i += 4 )); do
    if run_case "$file" "${rows[@]:i:4}"; then ok "${rows[i]}"; else fail "${rows[i]}"; fi
  done
}
run_cases "$helper" cases

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
  cmp -s -- "$1" "$4" && { printf '        mutation left the file unchanged: %s\n' "$2"; return 1; }
  return 0
}

# run_controls FILE CASES CONTROLS: each control of the array CONTROLS
# planted in a copy of FILE must turn its case of the array CASES red.
run_controls() {
  local file="$1" i j label target mutant row
  local -n rows="$2" plants="$3"
  for (( i = 0; i < ${#plants[@]}; i += 4 )); do
    label="${plants[i]}"; target="${plants[i + 3]}"
    mutant="$tmp/mutant-${file##*/}-$i.sh"
    if ! mutate "$file" "${plants[i + 1]}" "${plants[i + 2]}" "$mutant"; then fail "control: $label"; continue; fi
    row=()
    for (( j = 0; j < ${#rows[@]}; j += 4 )); do [[ ${rows[j]} == "$target" ]] && row=("${rows[@]:j:4}"); done
    if [[ ${#row[@]} -eq 0 ]]; then fail "control: $label names no case: $target"; continue; fi
    if run_case "$mutant" "${row[@]}" >/dev/null; then fail "control: $label left '$target' green"; else ok "control: $label"; fi
  done
}

# Controls, four fields each: label, text, replacement, and the case that
# must go red.
controls=(
  "the caller's runtime dir is not compared"
  '[[ $rt_real != "$(readlink -f -- "$XDG_RUNTIME_DIR")" ]] ||' 'true ||' "the caller's runtime dir is refused"
  "a socket outside the sandbox's runtime dir is taken"
  '[[ $path == "$rt_real/$name" ]] ||' 'true ||' "a link out of the sandbox's runtime dir is refused"
  "an unnamed caller runtime dir is accepted"
  '[[ -n ${XDG_RUNTIME_DIR:-} ]] ||' 'true ||' "a caller with no runtime dir named is refused"
  "a socket name may be a path"
  '[[ -n $name && $name != */* && $name != . && $name != .. ]] ||' '[[ -n $name ]] ||' "a path for a socket name is refused"
  "the output dir may lie outside tmp/"
  '[[ $dir == "$root"/* ]] ||' 'true ||' "an output dir outside tmp/ is refused"
  "a capture is not compared with the previous shot"
  'if [[ $hash != "$shot_last_hash" ]]; then' 'if true; then' "a capture equal to the previous shot is stale"
  "a grim timeout is not named"
  '[[ $status -eq 124 ]] && echo timeout' '[[ $status -eq 0 ]] && echo timeout' "a grim that never returns fails the shot"
  "grim inherits the caller's environment"
  'env -i PATH="$PATH"' 'env PATH="$PATH"' "grim sees only the nested socket"
  "a layout pixel uses the output scale"
  '-s 1 -g "$3,$4 1x1"' '-g "$3,$4 1x1"' "a layout pixel on a scale-2 output reads its colour"
  "the capture takes the whole layout"
  '-o "$3" -t png "$4"' '-t png "$4"' "a capture of its own output is taken while another output has no size"
  "an unnamed output goes on to grim"
  '[[ -n ${SHOT_OUTPUT:-} ]] ||' 'true ||' "a shot with no output named is refused"
  "the required chrome state is not compared"
  'if [[ -n ${SHOT_CHROME_REQUIRE:-} && $chrome != "$SHOT_CHROME_REQUIRE" ]]; then' 'if false; then' "a shot with tooltip chrome is refused"
)
run_controls "$helper" cases controls

# Execute the Probe's actual JavaScript methods with a captured console and
# owner-data fixtures. This does not exercise QML bindings or signal wiring;
# the normal nested pair owns that evidence.
cat >"$tmp/probe-display-control.cjs" <<'JS'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
try {
    const source = fs.readFileSync(process.argv[2], 'utf8');
    function method(name, indent) {
        const pattern = new RegExp('^' + ' '.repeat(indent) + 'function ' + name
            + '\\([^\\n]*\\)(?:: string)? \\{[\\s\\S]*?^' + ' '.repeat(indent) + '\\}', 'gm');
        const matches = [...source.matchAll(pattern)];
        if (matches.length !== 1) throw new Error('Probe method extraction: ' + name);
        // Remove only QML's type annotations from the IPC signature.
        return matches[0][0].replace(/^([^\n]*?)\(reason: string\): string/m, '$1(reason)');
    }
    const methods = ['encodeDisplayEvent', 'displayEventEnvelope', 'emitDisplayEvent',
        'endDisplayEvents', 'detachDisplayEvents', 'armDisplayEvents', 'displayEventMonitorFacts',
        'displayEventQueueFacts', 'displayEventLayerFacts', 'displayEventReloaderFacts'].map(name => method(name, 4));
    methods.push(method('displayEventStop', 8));
    const capacities = {};
    for (const name of ['displayEventCapacityEvents', 'displayEventCapacityChars', 'displayEventTerminalReserve']) {
        const matches = [...source.matchAll(new RegExp('^    readonly property int ' + name + ': (\\d+)$', 'gm'))];
        if (matches.length !== 1) throw new Error('Probe capacity extraction: ' + name);
        capacities[name] = Number(matches[0][1]);
    }
    function fixture(status = 'armed') {
        const lines = [];
        let clock = 1000;
        const state = Object.assign({}, capacities, {
            displayEventInstance: 'fixture/instance', displayEventStatus: status,
            displayEventReason: '', displayEventSequence: 0, displayEventChars: 0,
            displayEventPriming: false,
            console: { log: line => lines.push(line) }, Date: { now: () => clock++ }
        });
        for (const name of ['Monitors', 'Compositor', 'Loader', 'Layer', 'Reloader', 'Hyprland', 'Quickshell'])
            state['displayEvent' + name] = { fixture: name };
        state.root = state;
        vm.createContext(state);
        vm.runInContext(methods.join('\n'), state);
        return { state, lines };
    }
    function record(f, expectedInstance = 'fixture/instance') {
        const prefix = 'VGS_DISPLAY_EVENT ';
        const events = f.lines.map(line => {
            assert.ok(line.startsWith(prefix), 'machine prefix');
            return JSON.parse(line.slice(prefix.length));
        });
        assert.ok(events.length <= f.state.displayEventCapacityEvents, 'finite event count');
        let chars = 0;
        for (const [index, event] of events.entries()) {
            assert.equal(event.sequence, index + 1, 'contiguous emitted sequence');
            assert.equal(event.instance, expectedInstance, 'instance survives delivery');
            assert.equal(event.schema, 'VGS-1714.display-event.v1', 'event schema');
            assert.equal(typeof event.realtimeMs, 'number', 'clock field');
            chars += f.lines[index].length - prefix.length;
        }
        assert.equal(chars, f.state.displayEventChars, 'aggregate JSON accounting');
        assert.ok(chars <= f.state.displayEventCapacityChars, 'finite JSON characters');
        return events;
    }
    function detached(f) {
        for (const name of ['Monitors', 'Compositor', 'Loader', 'Layer', 'Reloader', 'Hyprland', 'Quickshell'])
            assert.equal(f.state['displayEvent' + name], null, 'release ' + name);
        const count = f.lines.length;
        assert.equal(f.state.emitDisplayEvent('boundary', 'fixture', {}), false, 'terminal blocks later events');
        f.state.endDisplayEvents('interrupted', 'later');
        assert.equal(f.lines.length, count, 'terminal is emitted once');
    }
    {
        // Without the layer's reload Process the Probe refuses to arm.
        const f = fixture('absent');
        Object.assign(f.state, { LazyLoader: class {}, HyprlandLayer: class {}, Process: class {} });
        f.state.hyprland = Object.assign(new f.state.LazyLoader(), { active: true,
            item: Object.assign(new f.state.HyprlandLayer(), { reloadProcess: null }) });
        assert.equal(f.state.armDisplayEvents('no-reloader'), 'refused: display-events=reloader-identity', 'reloader refusal');
        assert.deepEqual(record(f).map(e => [e.kind, e.data.reason]), [['missing', 'reloader-identity']], 'reloader refusal terminal');
    }
    if (process.argv[3] !== undefined && process.argv[3] !== '--packets')
        throw new Error('unknown Probe control mode');
    if (process.argv[3] === '--packets') {
        // The collector consumes actual Probe output. Fixture owner values
        // drive the real arm/facts methods and notification handler bodies;
        // this does not simulate QML property binding or signal delivery.
        const f = fixture('absent');
        const state = f.state;
        Object.assign(state, { displayEventInstance: '73/100',
            LazyLoader: class {}, HyprlandLayer: class {}, Process: class {} });
        const monitors = { active: false, ownerId: '', outputs: [],
            trialState: { phase: 'idle', token: '', deadline: 0, failure: '' },
            tokenPath: '', trialLua: '', restoreLua: '', restoreRules: {}, keptRules: {} };
        const compositor = { queue: [], pending: null, pendingJudged: false, completion: null, reply: '' };
        const reloader = Object.assign(new state.Process(), {
            running: false, command: ['hyprctl', 'reload', 'config-only'], completion: null });
        const layer = Object.assign(new state.HyprlandLayer(), { reloadProcess: reloader,
            highestMonitorScale: 1, rendered: { text: 'fixture layer' }, machine: { phase: 'idle' } });
        Object.assign(state, {
            hyprland: Object.assign(new state.LazyLoader(), { active: true, item: layer }),
            Capabilities: { monitors }, Compositor: compositor, Hyprland: {}, Quickshell: {},
            displayEventGeometry: { screens: [], monitors: [] }
        });
        assert.equal(state.armDisplayEvents('collector-payloads'), 'ok', 'packet arm');
        function notify(owner, signal, field, value, args = []) {
            if (field !== null) state['displayEvent' + owner][field] = value;
            const matches = [...source.matchAll(new RegExp('^    Connections \\{\\n'
                + '        target: root\\.displayEvent' + owner + '\\n([\\s\\S]*?)^    \\}', 'gm'))];
            if (matches.length !== 1 || !matches[0][1].includes('function ' + signal + '('))
                throw new Error('Probe notification extraction: ' + owner + '.' + signal);
            state.fixtureSignalArguments = args;
            vm.runInContext('(function() {\n' + matches[0][1] + '\n' + signal
                + '(...fixtureSignalArguments);\n})()', state);
        }
        const trialLua = 'hl.monitor({ output = "WAYLAND-1", scale = 2 })';
        const restoreLua = 'hl.monitor({ output = "WAYLAND-1", scale = 1 })';
        const argv = ['hyprctl', 'eval', trialLua];
        for (const [signal, field, value] of [
            ['onActiveChanged', 'active', true],
            ['onOwnerIdChanged', 'ownerId', 'fixture.owner'],
            ['onTokenPathChanged', 'tokenPath', '/fixture/trial.token'],
            ['onTrialLuaChanged', 'trialLua', trialLua],
            ['onRestoreLuaChanged', 'restoreLua', restoreLua],
            ['onRestoreRulesChanged', 'restoreRules', { 'WAYLAND-1': { scale: 1 } }],
            ['onKeptRulesChanged', 'keptRules', { 'WAYLAND-1': { scale: 2 } }],
            ['onTrialStateChanged', 'trialState', { phase: 'arming', token: '/fixture/trial.token', deadline: 15, failure: '' }],
            ['onOutputsChanged', 'outputs', [{ name: 'WAYLAND-1', scale: 2 }]],
            ['onOutputsChanged', 'outputs', null]
        ]) notify('Monitors', signal, field, value);
        notify('Compositor', 'onQueueChanged', 'queue', [{ argv, judged: true }]);
        compositor.queue = [];
        notify('Compositor', 'onPendingChanged', 'pending', argv);
        notify('Compositor', 'onPendingJudgedChanged', 'pendingJudged', true);
        notify('Compositor', 'onReplyChanged', 'reply', 'ok');
        notify('Compositor', 'onCompletionChanged', 'completion', { code: 0, status: 0 });
        notify('Compositor', 'onCompletionChanged', 'completion', null);
        notify('Compositor', 'onPendingChanged', 'pending', null);
        notify('Layer', 'onHighestMonitorScaleChanged', 'highestMonitorScale', 2);
        notify('Layer', 'onRenderedChanged', 'rendered', { text: 'fixture scaled layer' });
        notify('Layer', 'onMachineChanged', 'machine', { phase: 'reloading', reloadOwner: 'layer' });
        state.displayEventGeometry = { screens: [{ name: 'WAYLAND-1', width: 1440, height: 900,
            x: 0, y: 0, devicePixelRatio: 2 }], monitors: [{ id: 0, name: 'WAYLAND-1',
            width: 2880, height: 1800, x: 0, y: 0, scale: 2, lastIpcObject: { scale: 2 } }] };
        const geometry = [...source.matchAll(/^    onDisplayEventGeometryChanged: \{\n([\s\S]*?)^    \}/gm)];
        if (geometry.length !== 1) throw new Error('Probe geometry notification extraction');
        vm.runInContext('(function() {\n' + geometry[0][1] + '\n})()', state);
        notify('Reloader', 'onRunningChanged', 'running', true);
        notify('Reloader', 'onCompletionChanged', 'completion', { code: 0, status: 0 });
        notify('Reloader', 'onExited', null, null, [0, 0]);
        notify('Reloader', 'onCompletionChanged', 'completion', null);
        notify('Reloader', 'onRunningChanged', 'running', false);
        notify('Reloader', 'onCommandChanged', 'command', ['hyprctl', 'reload', 'config-only']);
        notify('Compositor', 'onPendingJudgedChanged', 'pendingJudged', false);
        notify('Monitors', 'onActiveChanged', 'active', false);
        assert.equal(state.displayEventStop('fixture-end'), 'ok', 'packet stop');
        const packets = record(f, '73/100');
        assert.equal(packets[0].kind, 'arm', 'packet arm first');
        assert.equal(packets.at(-1).kind, 'stopped', 'packet stop last');
        detached(f);
        process.stdout.write(f.lines.join('\n') + '\n');
    } else {
    {
        const f = fixture();
        for (let i = 0; i < f.state.displayEventCapacityEvents; i++)
            f.state.emitDisplayEvent('boundary', 'fixture', { label: 'event ceiling' });
        const events = record(f);
        assert.equal(f.state.displayEventStatus, 'overflow', 'event ceiling stops capture');
        assert.equal(events.at(-1).kind, 'overflow', 'event ceiling retains terminal');
        assert.equal(events.at(-1).data.reason, 'capacity-events', 'event ceiling reason');
        detached(f);
    }
    {
        const f = fixture();
        const payload = 'x'.repeat(Math.ceil(f.state.displayEventCapacityChars / 16));
        // Enough payloads exceed the character budget before the event cap.
        for (let i = 0; i < 17 && f.state.displayEventStatus === 'armed'; i++)
            f.state.emitDisplayEvent('outputsChanged', 'MonitorState', { fixture: payload });
        const events = record(f);
        assert.equal(f.state.displayEventStatus, 'overflow', 'character ceiling stops capture');
        assert.equal(events.at(-1).data.reason, 'capacity-chars', 'character ceiling reason');
        detached(f);
    }
    for (const [initial, status, reason] of [
        ['armed', 'stopped', 'row-end'], ['armed', 'interrupted', 'probe-destroyed'],
        ['absent', 'missing', 'reloader-identity']
    ]) {
        const f = fixture(initial);
        if (status === 'stopped') assert.equal(f.state.displayEventStop(reason), 'ok', 'IPC stop');
        else f.state.endDisplayEvents(status, reason);
        const events = record(f);
        assert.equal(events.length, 1, 'terminal-only fixture');
        assert.equal(events[0].kind, status, 'terminal kind');
        assert.equal(events[0].data.reason, reason, 'terminal reason');
        assert.equal(f.state.displayEventStatus, status, 'terminal state');
        detached(f);
    }
    {
        const f = fixture();
        assert.equal(f.state.displayEventStop('x'.repeat(f.state.displayEventTerminalReserve)),
            'refused: display-events=overflow', 'long stop reason refuses');
        const events = record(f);
        assert.equal(events.at(-1).data.reason, 'capacity-stop-reason', 'long reason terminal');
        detached(f);
    }
    console.log('probe-display-control: pass');
    }
} catch (error) {
    if (error.code === 'ERR_ASSERTION') {
        console.error('probe-display-control: assertion-failed ' + error.message);
        process.exitCode = 1;
    } else {
        console.error('probe-display-control: unavailable ' + error.message);
        process.exitCode = 2;
    }
}
JS

# Exercise the actual embedded collector against owned original logs and public
# socket-shaped fixtures. This proves recording and failure states, not
# Hyprland delivery or QML notification wiring, which the smoke observes.
source "$repo/scripts/smoke/display-record.sh"
display_record_program >"$tmp/display-record.py"
display_record_root="$(mktemp -d "$XDG_RUNTIME_DIR/owned/record.XXXXXX")" || exit 1
if node "$tmp/probe-display-control.cjs" "$repo/scripts/smoke/Probe.qml" --packets >"$tmp/probe-display-packets.jsonl" &&
   python3 - "$tmp/display-record.py" "$display_record_root" "$repo/scripts/smoke/harness.sh" "$tmp/probe-display-packets.jsonl" <<'PY'
import contextlib, json, os, pathlib, re, runpy, signal, socket, subprocess, sys

program, root, harness, packet_path = map(pathlib.Path, sys.argv[1:])
text, harness_text = program.read_text(), harness.read_text()
fixture_directories = {}
packet_bytes = packet_path.read_bytes()
assert packet_bytes and packet_bytes.endswith(b'\n'), 'probe-source-packets-present'
packet_lines = packet_bytes.splitlines(keepends=True)
assert all(line.startswith(b'VGS_DISPLAY_EVENT ') for line in packet_lines), 'probe-source-packet-prefix'
source_packets = [json.loads(line[len(b'VGS_DISPLAY_EVENT '):]) for line in packet_lines]
assert [p['sequence'] for p in source_packets] == list(range(1, len(source_packets) + 1)), 'probe-source-packet-sequence'
assert source_packets[0]['kind'] == 'arm' and source_packets[-1]['kind'] == 'stopped', 'probe-source-packet-boundaries'

def payloads(producer, kind):
    return [p['data'] for p in source_packets if (p['producer'], p['kind']) == (producer, kind)]

assert payloads('MonitorState', 'tokenPathChanged') == ['/fixture/trial.token'], 'probe-source-string-present'
assert payloads('MonitorState', 'activeChanged') == [True, False], 'probe-source-booleans-present'
assert all(type(p) is bool for p in payloads('MonitorState', 'activeChanged')), 'probe-source-boolean-types'
assert payloads('HyprlandLayer', 'highestMonitorScaleChanged') == [2], 'probe-source-number-present'
assert type(payloads('HyprlandLayer', 'highestMonitorScaleChanged')[0]) is int, 'probe-source-number-type'
assert payloads('MonitorState', 'outputsChanged') == [[dict(name='WAYLAND-1', scale=2)], None], 'probe-source-array-null-present'
assert [p['completion'] for p in payloads('Compositor', 'completionChanged')] == [dict(code=0, status=0), None], 'probe-source-completion-reset-present'
assert payloads('HyprlandLayer.reloader', 'exited') == [dict(code=0, status=0)], 'probe-source-exit-present'

def fixture_directory(name):
    # Confined scratch prefixes are long. AF_UNIX names include this path.
    directory = root / ("r" + str(len(fixture_directories)))
    directory.mkdir()
    fixture_directories[name] = directory
    (directory / "fixture-name").write_text(name + "\n")
    return directory

def extract(source, name):
    match = re.search(r'^' + name + r'\(\) \{.*?^\}', source, re.M | re.S)
    assert match, 'source-extraction-' + name
    return match.group()

@contextlib.contextmanager
def server(name, source=text):
    directory = fixture_directory(name)
    recorder = directory / 'recorder.py'
    recorder.write_text(source)
    os.mkfifo(directory / 'ready')
    def expired(*_):
        raise TimeoutError('collector fixture: ' + (directory / 'stderr').read_text())
    signal.signal(signal.SIGALRM, expired)
    signal.alarm(30)
    with (directory / 'stderr').open('wb') as err:
        child = subprocess.Popen([sys.executable, '-u', str(recorder), 'serve', str(directory)],
                                 env={}, stdout=subprocess.DEVNULL, stderr=err)
        try:
            with (directory / 'ready').open() as ready:
                assert ready.readline() == 'ready\n', 'collector-ready'
            def request(command, *args, error=None):
                with socket.socket(socket.AF_UNIX, socket.SOCK_SEQPACKET) as client:
                    client.settimeout(10)
                    client.connect(str(directory / 'control'))
                    client.sendall(json.dumps([command, *args]).encode())
                    reply = json.loads(client.recv(1048576))
                if error is not None:
                    assert not reply['ok'] and reply['error'] == error, ('expected-refusal', reply)
                    return
                assert reply['ok'], ('collector-runtime', reply)
                return reply['value']
            yield directory, recorder, child, request
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()
            signal.alarm(0)

def events(directory):
    return [json.loads(line) for line in (directory / 'events.jsonl').read_text().splitlines()]

def terminal(directory):
    rows = events(directory)
    assert rows[-1]['kind'] == 'terminal', 'terminal-retained'
    return rows[-1]['data']

# Actual shared launch/stop. Every signalled child belongs to this fixture.
def boundary(directory, recorder, mode='registered', source=harness_text):
    helper = directory / ('boundary-' + mode + '.sh')
    helper.write_text('\n'.join(extract(source, n) for n in ('spawn', 'shell_stop', 'stop_shell', 'in_harness_tree', 'shell_answers', 'py_reply', 'now_ms')) + r'''
set -u
recorder=$1 fixture=$2 mode=$3
control=$fixture/control
pgids=()
trap 'for pid in $(jobs -pr); do kill -TERM "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; done' EXIT
rt_dir=$fixture
stop_lock_wait_s=1
shell_memory_note() { :; }
fail() { printf '%s\n' "$*" >&2; }
lock_holders() { :; }
display_record_call() { python3 "$recorder" request "$control" "$@"; }
display_stream_kind=probe
[[ $mode != generic ]] || display_stream_kind=''
mkfifo "$fixture/ready-child"
if [[ $mode == supervised ]]; then
  mkfifo "$fixture/qs-launch" "$fixture/qs-ready" "$fixture/qs-ended"
  cp -- "$(command -v sleep)" "$fixture/qs"
  cat >"$fixture/supervised-runner.sh" <<'SH'
fixture=$1 child=''
trap 'if [ -n "$child" ]; then kill "$child" 2>/dev/null || :; wait "$child" 2>/dev/null || :; fi' EXIT
trap 'exit 0' TERM
for generation in 1 2; do
  IFS= read -r launch <"$fixture/qs-launch"
  "$fixture/qs" 60 &
  child=$!
  printf '%s\n' "$child" >"$fixture/qs-pid"
  printf '%s\n' "$child" >"$fixture/qs-ready"
  wait "$child" || :
  child=''
  printf 'ended\n' >"$fixture/qs-ended"
done
exec sleep 60
SH
fi
spawn_pid=stale
spawn "$fixture/child.log" sh -c 'printf "stdout\n"; printf "stderr\n" >&2; printf "ready\n" >"$1"; if [ "$2" = supervised ]; then exec sh "$3/supervised-runner.sh" "$3"; fi; exec sleep 60' _ "$fixture/ready-child" "$mode" "$fixture"
IFS= read -r ready <"$fixture/ready-child"
shell_pid=$spawn_pid
printf '%s\n' "$shell_pid" "${pgids[-1]:-missing}" >"$fixture/pids"
if [[ $mode == adopted || $mode == direct-restart ]]; then
  kill -TERM "$shell_pid"
  wait "$shell_pid" 2>/dev/null || true
  setsid sh -c 'exec sleep 60' >"$fixture/adopted.log" 2>&1 &
  shell_pid=$!
  pgids+=("$shell_pid")
fi
shell_log=$fixture/child.log
# Probe stream registration alone grants no shell-stop ownership. Bind
# this fixture's own generation as shell_answers does for supervised qs.
if [[ $mode != supervised ]]; then
  display_record_call mark shell-identity "$shell_pid" "$shell_pid" "$fixture" "$shell_log" >/dev/null
fi
if [[ $mode == supervised ]]; then
  shell_env=() shell_pids_started=()
  timeout_s=1 instance_log=''
  ok() { :; }
  ipc() { printf 'ok\n'; }
  qs_list() { printf '[{"id":"fixture","pid":%s}]\n' "$(<"$fixture/qs-pid")"; }
  mkdir -p "$fixture/bin" "$rt_dir/quickshell/by-id/fixture"
  : >"$rt_dir/quickshell/by-id/fixture/log.log"
  printf '#!/bin/sh\ncat "${0%%/bin/vgshell}/qs-pid"\n' >"$fixture/bin/vgshell"
  chmod +x "$fixture/bin/vgshell"
  for generation in 1 2; do
    printf '%s\n' "$generation" >"$fixture/qs-launch"
    IFS= read -r qs_child <"$fixture/qs-ready"
    for _ in $(seq 1 50); do
      [[ $(cat "/proc/$qs_child/comm") != qs ]] || break
    done
    shell_answers "$fixture" "$shell_log" || exit 2
    kill -TERM "$qs_child"
    IFS= read -r ended <"$fixture/qs-ended"
  done
fi
if [[ $mode == already-reaped || $mode == clear-direct-reap ]]; then
  kill -TERM "$shell_pid"
  wait "$shell_pid" 2>/dev/null || true
  [[ $mode != clear-direct-reap ]] || shell_pid=''
fi
status=0
stop_shell || status=$?
printf '%s\n' "$status" "$shell_pid" >>"$fixture/pids"
stop_shell || true
for pid in "${pgids[@]}"; do wait "$pid" 2>/dev/null || true; done
''')
    result = subprocess.run(['bash', str(helper), str(recorder), str(directory), mode],
                            env={'PATH': os.getenv('PATH')}, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=25)
    assert result.returncode == 0, ('boundary-runtime', result.stderr)
    receipt = (directory / 'pids').read_text().splitlines()
    assert receipt[0].isdigit() and receipt[0] == receipt[1], 'original-launch-preserved'
    assert receipt[2:] == ['0', ''], 'stop-clears-ended-owner'
    assert (directory / 'child.log').read_bytes() == b'stdout\nstderr\n', 'original-output-preserved'

for mode in ('registered', 'generic', 'adopted', 'direct-restart', 'already-reaped', 'clear-direct-reap', 'supervised'):
    with server('boundary-' + mode) as (directory, recorder, child, request):
        boundary(directory, recorder, mode)
        current, rows = request('read'), events(directory)
        if mode in ('registered', 'already-reaped', 'supervised'):
            assert current['activeStreams'] == 0, 'typed-stop-retires'
            assert len([e for e in rows if e['kind'] == 'local-owner-end']) == 1, 'typed-stop-once'
            if mode == 'supervised':
                identities = [e['data']['registration'] for e in rows if e['kind'] == 'shell-observation-context']
                assert len(identities) == 2 and len(set(identities)) == 1, 'relaunch-keeps-acquired-generation'
        elif mode != 'clear-direct-reap':
            assert any(e['kind'] == 'unobserved-adoption-end' for e in rows), 'adoption-is-context'
            assert not any(e['kind'] == 'local-owner-end' for e in rows), 'adoption-cannot-end-registration'
            assert not current['problems'], 'adoption-no-false-missing'
        else:
            assert current['activeStreams'] == 1, 'direct-reap-retained-until-cleanup'
        request('close', '1', 'fixture-cleanup'); request('stop', 'normal'); child.wait(timeout=10)

# Capacity refusal executes the same real stop boundary and cannot stop
# the original spawn. Pending registrations are intentionally incomplete.
with server('full-original-launch') as (directory, recorder, child, request):
    with contextlib.ExitStack() as stack:
        for index in range(128):
            writer = stack.enter_context((directory / ('pending-' + str(index))).open('wb'))
            request('log', 'probe', str(writer.name), f'/proc/{os.getpid()}/fd/{writer.fileno()}')
        boundary(directory, recorder)
        assert 'launch:expected-registration-refused' in request('read')['problems'], 'full-launch-explicit-refusal'
        request('close', '1', 'cleanup'); request('stop', 'normal'); child.wait(timeout=10)
        assert terminal(directory)['localRecord'] == 'incomplete', 'full-launch-record-incomplete'

# Actual methods isolate generation rules. These flags are fixture context,
# not proof of a public subscription or a complete end-to-end record.
module = runpy.run_path(str(program))
def local(name, source=text):
    path = root / (name + '.py'); path.write_text(source)
    api = runpy.run_path(str(path))
    directory = fixture_directory(name)
    record = api['Record'](directory)
    record.bound = True
    record.set_scope('shader-context', 'fixture', '0')
    return record, api

def finish(record):
    record.close_window('1', 'fixture')
    record.stop_reason, record.stopping = 'normal', True
    record.run()
    return terminal(record.directory)

@contextlib.contextmanager
def acquired(record, index, bind=True, path=None):
    path = path or record.directory / ('log-' + str(index))
    with path.open('wb', buffering=0) as writer:
        key = record.watch_log('probe', str(path), f'/proc/{os.getpid()}/fd/{writer.fileno()}')
        child = subprocess.Popen(['sleep', '60'], stdout=writer, stderr=writer) if bind else None
        try:
            if child: record.launched('probe', key, str(child.pid), str(path))
            yield path, writer, key, child
        finally:
            if child is not None:
                if child.poll() is None: child.terminate()
                child.wait()

def end(record, child):
    context = record.owner_context(str(child.pid))
    child.terminate(); child.wait()
    record.end_owner(context, str(child.pid))

def many_stops(name, source=text):
    # 130 generations cross the 128-stream capacity if retirement leaks.
    # The boundary cases above cover spawn/stop wiring. Use the collector's
    # real methods here to avoid a recorder client process for each operation.
    record, _ = local(name, source)
    try:
        for index in range(130):
            with acquired(record, index, path=record.directory / 'child.log') as (_, _, _, child):
                end(record, child)
            # Catch missing retirement before it causes a capacity refusal.
            assert len(record.streams) == 0, 'completed-resource-retired'
    finally:
        finish(record)
    rows = events(record.directory)
    bindings = [e['data']['source'] for e in rows if e['kind'] == 'log-binding']
    assert len(bindings) == 130 and len(set(bindings)) == 130, 'unique-registration-generation'
    assert len([e for e in rows if e['kind'] == 'local-owner-end']) == 130, 'every-stop-owned-generation'
many_stops('retire-many')
record, _ = local('reader-close')
with acquired(record, 1) as (path, writer, key, child):
    writer.write(b'irrelevant\n'); record.drain()
    with path.open('rb') as reader: assert reader.read() == b'irrelevant\n'
    with path.open('ab'): pass
    record.drain()
    assert len(record.streams) == 1, 'reader-close-does-not-retire'
    assert not record.problems, 'ordinary-reader-preserved'
    end(record, child)
finish(record)

record, _ = local('capacity')
with contextlib.ExitStack() as stack:
    active = stack.enter_context(acquired(record, 0))
    for index in range(1, 128): stack.enter_context(acquired(record, index, bind=False))
    with (record.directory / 'refused.log').open('wb') as writer:
        try: record.watch_log('probe', str(writer.name), f'/proc/{os.getpid()}/fd/{writer.fileno()}')
        except ValueError as error: assert str(error) == 'capacity-streams', 'capacity-refusal'
        else: raise AssertionError('capacity-refusal')
    end(record, active[3])
    stack.enter_context(acquired(record, 129, bind=False))
    assert len(record.streams) == 128, 'capacity-reacquired'
finish(record)

for mode in ('reuse', 'truncate', 'replace', 'wrong-owner', 'duplicate-end', 'required-no-event', 'missing-launch'):
    record, _ = local('identity-' + mode)
    with acquired(record, 1, bind=mode != 'missing-launch') as (path, writer, key, child):
        if mode == 'reuse':
            alias = path.with_name('alias'); os.link(path, alias)
            try: record.watch_log('probe', str(alias), f'/proc/{os.getpid()}/fd/{writer.fileno()}')
            except ValueError as error: assert str(error) == 'log-inode-overlap-or-unproved-reuse', 'overlap-refused'
            else: raise AssertionError('overlap-refused')
            end(record, child)
            with acquired(record, 2, path=path) as (_, _, second, new_child):
                assert key != second, 'reuse-new-generation'
                end(record, new_child)
        elif mode in ('truncate', 'replace'):
            writer.write(b'x\n'); record.drain()
            if mode == 'truncate':
                os.ftruncate(writer.fileno(), 0); expected = ':truncated-history'
            else:
                path.rename(path.with_name('old')); path.write_bytes(b''); expected = ':replacement-or-watch-lost'
            record.drain()
            assert any(expected in p for p in record.problems), 'lost-history-rejected'
        elif mode in ('wrong-owner', 'duplicate-end'):
            context = record.owner_context(str(child.pid))
            if mode == 'wrong-owner':
                try: record.end_owner(context, str(os.getpid()))
                except ValueError as error: assert str(error) == 'owner-end-wrong-pid', 'wrong-owner-rejected'
                else: raise AssertionError('wrong-owner-rejected')
            child.terminate(); child.wait(); record.end_owner(context, str(child.pid))
            try: record.end_owner(context, str(child.pid))
            except ValueError as error: assert str(error) == 'owner-context-missing-or-ended', 'duplicate-end-rejected'
            else: raise AssertionError('duplicate-end-rejected')
        elif mode == 'required-no-event':
            record.scope = dict(role='display-smoke', displayRequired=True)
            record.shell_pids['fixture-qs'] = key
            record.require_display(str(child.pid), 'fixture-qs'); end(record, child)
            assert record.registrations[key]['fd'] is not None, 'required-reader-retained-before-event'
    result = finish(record)
    if mode == 'required-no-event': assert 'probe:missing' in result['problems'], 'missing-required-producer-rejected'
    if mode == 'missing-launch': assert any('registration:launch-missing:' in p for p in result['problems']), 'missing-expected-launch-rejected'

record, api = local('refused-and-unverified')
with subprocess.Popen(['sleep', '60'], stdout=subprocess.DEVNULL) as child:
    record.launched('probe', 'refused', str(child.pid), 'refused.log')
    assert record.resolve_owner(str(child.pid))['tag'] == 'expected-refused', 'refusal-is-expected'
    record.launches[0]['identity'] = dict(status='unavailable')
    assert record.resolve_owner(str(child.pid))['tag'] == 'expected-unverified', 'unknown-is-not-adoption'
    child.terminate(); child.wait()
assert 'launch:expected-registration-refused' in finish(record)['problems'], 'refusal-stays-incomplete'

def complete_case(name, source=text, omission=None, changed=False, context=False, packets=None, mixed=False):
    with server(name, source) as (directory, recorder, child, request):
        request('scope', 'shader-context' if context else 'display-smoke', 'fixture', '0', *([] if context else ['displays-modes']))
        connections = []
        listener = socket.socket(socket.AF_UNIX)
        listener.bind(str(directory / 'nested')); listener.listen()
        request('bind', 'fixture', str(directory / 'nested'), '71', 'wayland')
        peer, _ = listener.accept(); peer.sendall(b'monitoradded>>FIXTURE\n')
        connections.extend((peer, listener))
        with (directory / 'wayland.log').open('wb', buffering=0) as writer:
            key = request('log', 'wayland', str(writer.name), f'/proc/{os.getpid()}/fd/{writer.fileno()}')
            request('launched', 'wayland', key, str(os.getpid()), str(writer.name))
            writer.write(b'[100] xdg_toplevel@8.configure(100, 200, array[0])\n')
            writer.write(b'[100] wl_display#1.delete_id(26)\n')
            if omission == 'partial': writer.write(b'partial')
            if omission == 'line': writer.write(b'x' * 1048577 + b'\n')
        if not context and omission != 'arm-boundary':
            with (directory / 'probe.log').open('wb', buffering=0) as writer:
                key = request('log', 'probe', str(writer.name), f'/proc/{os.getpid()}/fd/{writer.fileno()}')
                producer = subprocess.Popen(['sleep', '60'], stdout=writer, stderr=writer)
                try:
                    request('launched', 'probe', key, str(producer.pid), str(writer.name))
                    request('mark', 'shell-identity', str(producer.pid), '73', 'fixture', str(writer.name))
                    request('require-display', str(producer.pid), '73')
                    request('mark', 'display-request', 'trialRules', '{}')
                    request('mark', 'display-reply', 'trialRules', '0', 'ok' if changed else 'refused: fixture')
                    notifications = [('Probe', 'arm', {})]
                    notifications += [(owner, 'initial-sample', {}) for owner in ('MonitorState', 'Compositor', 'HyprlandLayer', 'HyprlandLayer.reloader', 'Quickshell/Hyprland')]
                    if changed:
                        notifications += [('MonitorState', 'trialStateChanged', dict(phase='arming', token='fixture', deadline=100, failure='')), ('Compositor', 'completionChanged', dict(completion=dict(code=1, status=0))), ('HyprlandLayer.reloader', 'exited', dict(code=1, status=0))]
                    notifications += [('Probe', 'stopped', {})]
                    if packets is not None:
                        writer.write(packets)
                    else:
                        for sequence, (owner, kind, data) in enumerate(notifications, 1):
                            if omission == kind or omission == owner: continue
                            value = dict(schema='VGS-1714.display-event.v1', instance='73/100', sequence=sequence, realtimeMs=100, producer=owner, kind=kind, data=data)
                            writer.write(b'VGS_DISPLAY_EVENT ' + json.dumps(value).encode() + b'\n')
                    request('read')
                    context_key = request('owner-context', str(producer.pid))
                    producer.terminate(); producer.wait(); request('owner-end', context_key, str(producer.pid))
                    assert any(s['required'] for s in request('read')['streams']), 'required-reader-retained'
                finally:
                    if producer.poll() is None: producer.terminate(); producer.wait()
        request('close', '1', 'explicit'); request('close', '0', 'cleanup')
        if omission == 'interrupted': child.terminate()
        else: request('stop', 'normal')
        child.wait(timeout=10)
        for connection in connections: connection.close()
        result, rows = terminal(directory), events(directory)
        if mixed:
            # JSON text comparison preserves booleans versus numbers, nulls,
            # nested arrays, every metadata field and the producer clock.
            observed = [e['data'] for e in rows if e['kind'] == 'probe-observation']
            assert json.dumps(observed, sort_keys=True) == json.dumps(source_packets, sort_keys=True), 'probe-mixed-payloads-preserved'
        if omission != 'overflow':
            assert len([e for e in rows if e['kind'] == 'window-end']) == 1, ('window-end-first-fact', name, result)
            assert next(e for e in rows if e['kind'] == 'window-end')['data']['originalStatus'] == '1', 'window-end-original-status'
        if not omission:
            wayland = [e['data'] for e in rows if e['source'].startswith('wayland:')]
            assert any('xdg_toplevel@8.configure(' in d for d in wayland) and not any('delete_id' in d for d in wayland), 'wayland-bookkeeping-not-recorded'
        if omission: assert result['localRecord'] == 'incomplete', 'missing-or-lost-input-rejected'
        else:
            assert result['localRecord'] == 'complete', 'armed-zero-events-valid-collection'
            facts = result['factAvailability']
            if context: assert facts['queue-completion']['status'] == 'not-requested', 'context-facts-not-requested'
            else:
                assert facts['queue-completion']['status'] == ('observed' if changed else 'not-observed'), 'samples-are-not-history'
                assert result['displayOutcome'] == ('facts-observed' if changed else 'not-established'), 'fact-availability-separate'
                if changed and not mixed:
                    assert any(e['kind'] == 'probe-observation' and isinstance(e['data']['data'], dict) and e['data']['data'].get('code') == 1 for e in rows), 'failed-reload-exit-retained'
                if mixed:
                    assert all(facts[key]['observationCount'] == 1 for key in ('phase-token-deadline', 'trial-acceptance-publication', 'queue-completion', 'actual-layer-reload')), 'probe-event-specific-facts'
                    assert not any('probe-unparsed' in p or 'sequence-gap' in p for p in result['problems']), 'probe-valid-payload-continuity'
            cost = result['observationCost']
            prefix = (directory / 'events.jsonl').read_bytes().splitlines(keepends=True)[:-1]
            assert cost['prefixRecordEvents'] == len(prefix) and cost['prefixRecordBytes'] == sum(map(len, prefix)), 'cost-prefix-exact'
            assert cost['readBytes']['files'] > 0 and cost['userCpuSeconds'] >= 0 and cost['systemCpuSeconds'] >= 0 and cost['peakResidentKiB'] > 0, 'collector-cost-retained'
        return result

complete_case('complete-zero')
complete_case('complete-changes', changed=True)
complete_case('source-mixed', changed=True, packets=packet_bytes, mixed=True)
complete_case('context-no-probe', context=True)
for omission in ('arm-boundary', 'arm', 'MonitorState', 'stopped', 'partial', 'line', 'interrupted'):
    complete_case('missing-' + omission, omission=omission)
complete_case('event-overflow', text.replace('CAP_EVENTS = 65536', 'CAP_EVENTS = 3'), omission='overflow')

record, api = local('socket-eof')
left, right = socket.socketpair(); left.setblocking(False)
record.streams[left] = dict(source='nested-ipc', buffer=b'', kind='ipc', log=None, clipped=False, ended=False)
record.selector.register(left, api['selectors'].EVENT_READ, ('stream', left))
right.close(); record.read(left)
record.close_window('1', 'cleanup'); record.close_window('0', 'later')
assert 'nested-ipc:unexpected-eof' in finish(record)['problems'], 'preclose-eof-sticky'
record, api = local('notification-overflow')
record.notification(-1, api['IN_Q_OVERFLOW'], 0)
assert 'notification:overflow' in finish(record)['problems'], 'notification-overflow-rejected'
record, _ = local('missing-scope'); record.scope = None
assert 'scope:missing' in finish(record)['problems'], 'unknown-scope-incomplete'

def mutant(name, needle, replacement, check, assertion):
    assert text.count(needle) == 1, ('mutation-source', name)
    try: check(text.replace(needle, replacement))
    except AssertionError as error:
        assert str(error) == assertion, ('wrong-mutation-assertion', name, error)
        print('  CONTROL display collector: ' + name + ' fails ' + assertion)
    else: raise AssertionError(name + ' mutation survived')

# Every packet in this positive case came from actual Probe source. A global
# object-only filter must fail preservation, not an incidental runtime error.
mutant('object-only-payload', 'or not isinstance(value["kind"], str) or not value["kind"] or "data" not in value):',
       'or not isinstance(value["kind"], str) or not value["kind"] or "data" not in value or not isinstance(value["data"], dict)):',
       lambda source: complete_case('mut-object-only', source, changed=True, packets=packet_bytes, mixed=True), 'probe-mixed-payloads-preserved')

# Object-id release events outnumber the window facts in a full run and,
# recorded, fill the event cap before the facts arrive.
mutant('display-bookkeeping', 'wl_(?:compositor|surface|output)).*(?:configure|ack_configure|get_xdg_surface|get_toplevel|create_surface|enter\\(|leave\\(|destroy\\()', 'wl_(?:compositor|surface|output|display)).*(?:configure|ack_configure|get_xdg_surface|get_toplevel|create_surface|enter\\(|leave\\(|delete_id|destroy\\()',
       lambda source: complete_case('mut-bookkeeping', source), 'wayland-bookkeeping-not-recorded')

# Disposable envelope/fact mutations use the source-encoded positive packets.
# Invalid envelopes, sequence history, launch binding and event-specific fact
# errors have separate retained reasons. They never become no-change success.
def encode_packets(values):
    return b''.join(b'VGS_DISPLAY_EVENT ' + json.dumps(value).encode() + b'\n' for value in values)

def packet_variant():
    return json.loads(json.dumps(source_packets))

for name, field, value in (('schema', 'schema', 'wrong'), ('sequence-bool', 'sequence', True),
                           ('clock-bool', 'realtimeMs', True), ('clock-string', 'realtimeMs', '1000'),
                           ('clock-nan', 'realtimeMs', float('nan')), ('clock-inf', 'realtimeMs', float('inf'))):
    values = packet_variant(); values[0][field] = value
    result = complete_case('invalid-' + name, packets=encode_packets(values), omission='invalid-probe')
    assert any('probe-unparsed' in p for p in result['problems']), 'malformed-envelope-rejected'
values = packet_variant(); del values[0]['data']
assert any('probe-unparsed' in p for p in complete_case('invalid-data-absent', packets=encode_packets(values), omission='invalid-probe')['problems']), 'missing-payload-rejected'
values = packet_variant(); values[0]['realtimeMs'] = 1.0
huge = encode_packets(values).replace(b'"realtimeMs": 1.0', b'"realtimeMs": 1e9999', 1)
assert any('probe-unparsed' in p for p in complete_case('invalid-number-overflow', packets=huge, omission='invalid-probe')['problems']), 'nonfinite-json-number-rejected'
values = packet_variant(); del values[1]
assert any('probe:sequence-gap:' in p for p in complete_case('invalid-sequence-gap', packets=encode_packets(values), omission='invalid-probe')['problems']), 'probe-sequence-gap-rejected'
values = packet_variant()
for value in values: value['instance'] = '74/100'
assert any('probe:launch-unbound:' in p for p in complete_case('invalid-instance-binding', packets=encode_packets(values), omission='invalid-probe')['problems']), 'probe-instance-binding-rejected'

for producer, kind, fact, field, invalid in (
        ('MonitorState', 'trialStateChanged', 'phase-token-deadline', 'deadline', True),
        ('Compositor', 'completionChanged', 'queue-completion', 'completion', dict(code=True, status=0)),
        ('HyprlandLayer.reloader', 'exited', 'actual-layer-reload', 'status', '0')):
    for variant in ('wrong-type', 'missing-field', 'scalar'):
        values = packet_variant()
        target = next(p for p in values if (p['producer'], p['kind']) == (producer, kind))
        if variant == 'scalar': target['data'] = None
        elif variant == 'missing-field': del target['data'][field]
        else: target['data'][field] = invalid
        name = 'invalid-fact-' + producer + '-' + variant
        result = complete_case(name, packets=encode_packets(values), omission='invalid-probe')
        assert any('probe-fact-payload-invalid:' + producer + ':' + kind in p for p in result['problems']), 'invalid-fact-distinguished'
        assert not any('probe-unparsed' in p or 'sequence-gap' in p for p in result['problems']), 'valid-envelope-keeps-continuity'
        assert result['factAvailability'][fact]['status'] == 'not-observed', 'invalid-fact-not-observed'
        observed = [e['data'] for e in events(fixture_directories[name]) if e['kind'] == 'probe-observation']
        assert json.dumps(observed, sort_keys=True) == json.dumps(values, sort_keys=True), 'invalid-fact-raw-retained'
print('  CONTROL display collector: source-encoded mixed payloads and distinct invalid envelope/fact/history/binding cases pass')

mutant('retirement', 'if not registration["required"]:', 'if False:', lambda source: many_stops('mut-retirement', source), 'completed-resource-retired')
mutant('required-before-events', 'if not registration["required"]:', 'if True:', lambda s: complete_case('mut-required', s), 'required-reader-retained')
mutant('snapshots-not-history', 'observed = self.fact_counts[(self.display_registration, producer, kind)]', 'observed = 1', lambda s: complete_case('mut-snapshot', s), 'samples-are-not-history')
mutant('scope-required', 'expected = self.scope is not None and self.scope["displayRequired"]', 'expected = False', lambda s: complete_case('mut-scope', s, omission='arm-boundary'), 'missing-or-lost-input-rejected')
mutant('event-cap', 'if not terminal and (self.events >= CAP_EVENTS or self.bytes + len(text) > CAP_BYTES):', 'if False:', lambda s: complete_case('mut-cap', s.replace('CAP_EVENTS = 65536', 'CAP_EVENTS = 3'), omission='overflow'), 'missing-or-lost-input-rejected')

# Mutations at the shared stop authority cover every caller using it.
def stop_mutation():
    needle = 'display_record_call owner-end "$shell_stop_owner" "$shell_stop_pid" >/dev/null || true'
    assert harness_text.count(needle) == 1, 'owner-end-mutation-source'
    with server('mut-stop') as (directory, recorder, child, request):
        boundary(directory, recorder, source=harness_text.replace(needle, ':'))
        assert request('read')['activeStreams'] == 0, 'typed-stop-retires'
try:
    stop_mutation()
except AssertionError as error:
    assert str(error) == 'typed-stop-retires', ('wrong-stop-mutation', error)
    print('  CONTROL display collector: stop authority fails typed-stop-retires')
else:
    raise AssertionError('stop mutation survived')

# The actual spawn on recorder refusal preserves output, status and fresh
# PID. A failed original open clears stale identity before returning.
def spawn_failure(source, name):
    directory = root / name; directory.mkdir()
    helper = directory / 'launch.sh'
    helper.write_text(extract(source, 'spawn') + r'''
set -u
fixture=$1
pgids=()
display_record_call() { return 1; }
spawn_pid=stale
display_stream_kind=probe
status=0
spawn "$fixture/original.log" sh -c 'printf "stdout\n"; printf "stderr\n" >&2; exit 23' || status=$?
printf '%s\n' "$status" "$spawn_pid" "${pgids[0]:-missing}" >"$fixture/receipt"
if [[ $spawn_pid =~ ^[0-9]+$ ]]; then
  status=0
  wait "$spawn_pid" || status=$?
  printf '%s\n' "$status" >>"$fixture/receipt"
fi
spawn_pid=stale
display_stream_kind=probe
status=0
spawn "$fixture/absent/log" true || status=$?
printf '%s\n' "$status" "$spawn_pid" >>"$fixture/receipt"
''')
    result = subprocess.run(['bash', str(helper), str(directory)], env={'PATH': os.getenv('PATH')},
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert result.returncode == 0, ('spawn-fixture-runtime', result.stderr)
    receipt = (directory / 'receipt').read_text().splitlines()
    assert receipt[0] == '0' and receipt[1].isdigit() and receipt[1] == receipt[2], 'refusal-launch-preserved'
    assert receipt[3:] == ['23', '1', ''], 'refusal-status-and-stale-pid'
    assert (directory / 'original.log').read_bytes() == b'stdout\nstderr\n', 'refusal-output-preserved'
spawn_failure(harness_text, 'spawn-refused')
needle = '|| registration=refused'
assert harness_text.count(needle) == 1, 'spawn-refusal-mutation-source'
try:
    spawn_failure(harness_text.replace(needle, '|| return 1'), 'mut-spawn-refused')
except AssertionError as error:
    assert str(error) == 'refusal-launch-preserved', ('wrong-spawn-mutation', error)
    print('  CONTROL display collector: refusal fails refusal-launch-preserved')
else:
    raise AssertionError('refusal mutation survived')

# Execute actual caller scope logic before producer launch. Selection is
# supplied by the caller's existing judge, not rebuilt from notifications.
scope_helper = root / 'scope.sh'
scope_helper.write_text(extract(harness_text, 'display_record_scope') + r'''
set -u
source_repo=/fixture
self=$1
first_bar_runs=$2
qml_smoke_only=$3
qml_smoke_rows=(start displays-modes finish)
argv=(--rows "$qml_smoke_only")
qml_smoke_wanted() { [[ -z $qml_smoke_only || $qml_smoke_only == *",$1,"* ]]; }
display_record_call() { printf '%s\n' "$@" >&2; }
display_record_scope
''')
for caller, first, selected, role in (
    ('qml-smoke.sh', '', '', 'display-smoke'),
    ('qml-smoke.sh', '', ',start,', 'smoke-context'),
    ('qml-smoke.sh', '1', '', 'first-bar-context'),
    ('measure-shader.sh', '', '', 'shader-context'),
    ('sandbox-shots.sh', '', '', 'screenshot-context'),
    ('unknown.sh', '', '', 'unknown')):
    output = subprocess.run(['bash', str(scope_helper), '/fixture/scripts/' + caller, first, selected],
                            env={'PATH': os.getenv('PATH')}, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert output.stderr.decode().splitlines()[:2] == ['scope', role], 'declared-scope-before-events'
assert harness_text.index('display_record_close()') < harness_text.index('display_record_pid="$spawn_pid"'), 'partial-bootstrap-close-defined'
assert harness_text.index('display_record_finish()') < harness_text.index('display_record_pid="$spawn_pid"'), 'partial-bootstrap-finish-defined'

# Execute the actual client-failure receipt without a listening collector.
client_directory = fixture_directory('missing-control-client')
(client_directory / 'recorder.py').write_text(text)
client_helper = root / 'client-failure.sh'
client_helper.write_text(extract(harness_text, 'display_record_call') + r'''
set -u
display_record_dir=$1
display_record_call close 1 cleanup
''')
client_result = subprocess.run(['bash', str(client_helper), str(client_directory)],
                               env={'PATH': os.getenv('PATH')}, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
assert client_result.returncode == 1 and (client_directory / 'request-failed').read_text() == 'close\n', 'actual-client-failure-receipt'

for name, first, again, refusal in (
    ('unknown', None, ['unknown', 'fixture', '0'], 'scope-unknown'),
    ('repeated', ['shader-context', 'fixture', '0'], ['shader-context', 'fixture', '0'], 'scope-repeated'),
    ('mismatch', None, ['display-smoke', 'fixture', '0'], 'scope-selection-mismatch')):
    with server('scope-' + name) as (directory, recorder, child, request):
        if first: request('scope', *first)
        request('scope', *again, error=refusal)
        request('close', '1', 'cleanup'); request('stop', 'normal'); child.wait(timeout=10)
        assert 'control:' + refusal in terminal(directory)['problems'], 'invalid-scope-incomplete'
record, _ = local('missing-close')
record.stopping, record.stop_reason = True, 'normal'
record.run()
assert 'window-end:missing' in terminal(record.directory)['problems'], 'missing-close-incomplete'

# A newly adopted runner never inherits a missing expected registration.
def adoption_check(source):
    with server('mut-adoption', source) as (directory, recorder, child, request):
        boundary(directory, recorder, 'adopted')
        assert not request('read')['problems'], 'adoption-no-false-missing'
        request('close', '1', 'cleanup'); request('stop', 'normal'); child.wait(timeout=10)
mutant('adoption-type', 'return dict(tag="unobserved-adoption", pid=pid, snapshot=snapshot,',
       'return dict(tag="expected-unverified", pid=pid, snapshot=snapshot,', adoption_check, 'adoption-no-false-missing')

def failed_start(name, source):
    directory = fixture_directory(name)
    helper = directory / 'start.sh'
    helper.write_text('\n'.join(extract(source, n) for n in ('nested_input_check', 'spawn', 'spawn_display', 'start_shell')) + r'''
set -u
fixture=$1
pgids=() shell_start_words=()
rt_dir="$fixture/runtime" nested_socket=wayland-test signature=test-instance
shell_env=(env -i XDG_RUNTIME_DIR="$rt_dir" WAYLAND_DISPLAY="$nested_socket" HYPRLAND_INSTANCE_SIGNATURE="$signature" VGS_TEST_RUN=1)
cpu_some_us() { echo 0; }
now_ms() { echo 0; }
fail() { :; }
shell_answers() { :; }
display_record_call() { printf '%s\n' "$1 $2" >>"$fixture/marks"; }
spawn_pid=stale shell_pid=stale
status=0
start_shell "$fixture" "$fixture/absent/log" no-bar || status=$?
printf '%s\n' "$status" "$spawn_pid" "$shell_pid" >"$fixture/receipt"
''')
    result = subprocess.run(['bash', str(helper), str(directory)], env={'PATH': os.getenv('PATH')},
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert result.returncode == 0, ('start-fixture-runtime', result.stderr)
    assert (directory / 'receipt').read_text().splitlines() == ['1', '', ''], 'failed-start-clears-identities'
    assert 'mark shell-runner' not in (directory / 'marks').read_text(), 'failed-start-no-runner-binding'
failed_start('failed-start', harness_text)
needle = '    fail "start_shell: launch=failed log=$log"\n    return 1'
assert harness_text.count(needle) == 1, 'failed-start-mutation-source'
try:
    failed_start('mut-start', harness_text.replace(needle, needle.replace('return 1', ':')))
except AssertionError as error:
    assert str(error) == 'failed-start-clears-identities', ('wrong-start-mutation', error)
    print('  CONTROL display collector: failed start fails failed-start-clears-identities')
else:
    raise AssertionError('failed-start mutation survived')

# A missing stdout descriptor is not proof that a process disappeared.
def missing_stdout(source, name):
    source_file = root / (name + '.py'); source_file.write_text(source)
    api = runpy.run_path(str(source_file))
    # The child closes stdout itself and never execs again: while an exec is
    # in flight, /proc/PID/fd reads EACCES, which also reads as unavailable.
    child = 'import os, sys, time; os.close(1); sys.stderr.write("ready\\n"); sys.stderr.flush(); time.sleep(60)'
    with subprocess.Popen([sys.executable, '-c', child], stderr=subprocess.PIPE) as process:
        assert process.stderr.readline() == b'ready\n', 'closed-stdout-ready'
        try:
            assert api['process_binding'](str(process.pid))['status'] == 'unavailable', 'missing-stdout-is-unavailable'
        finally:
            process.terminate(); process.wait()
missing_stdout(text, 'closed-stdout')
mutant('closed-stdout-identity',
       'return dict(status="gone") if not path.exists() else dict(status="unavailable", error="identity-component-missing")',
       'return dict(status="gone")', lambda source: missing_stdout(source, 'mut-closed-stdout'), 'missing-stdout-is-unavailable')
record, _ = local('missing-wayland-producer')
assert 'wayland-producer:missing' in finish(record)['problems'], 'missing-wayland-producer-incomplete'

def terminal_reserve(source, name):
    record, api = local(name, source)
    record.scope['argv'] = ['x' * api['CAP_LINE']]
    result = finish(record)
    assert 'terminal:overflow' in result['problems'], 'terminal-reserve-incomplete'
    assert len((record.directory / 'events.jsonl').read_bytes().splitlines()[-1]) < api['CAP_LINE'], 'terminal-reserve-bounded'
terminal_reserve(text, 'terminal-reserve')
mutant('terminal-reserve', 'if terminal and len(text) > CAP_LINE:', 'if False:',
       lambda source: terminal_reserve(source, 'mut-terminal-reserve'), 'terminal-reserve-incomplete')
mutant('cost-prefix', 'prefixRecordEvents=self.events, prefixRecordBytes=self.bytes,',
       'prefixRecordEvents=self.events + 1, prefixRecordBytes=self.bytes,',
       lambda source: complete_case('mut-cost-prefix', source), 'cost-prefix-exact')

# Finalization preserves failed control requests and partial final output.
retained = fixture_directories['complete-zero']
for name in ('scratch', 'runtime', 'home'): (root / ('retain-' + name)).mkdir()
scratch = root / 'retain-scratch'
(scratch / 'original.log').write_bytes(b'original bytes without newline')
(scratch / 'alias.log').symlink_to(scratch / 'original.log')
module['retain_record'](str(retained), str(scratch), str(root / 'retain-runtime'), str(root / 'retain-home'))
assert (retained / 'logs/sandbox/original.log').read_bytes() == b'original bytes without newline'
assert not (retained / 'logs/sandbox/alias.log').exists()
for errors, expected in (('0', 'complete'), ('1', 'incomplete')):
    module['complete_record'](str(retained), errors)
    assert json.loads((retained / 'completeness.json').read_text())['localRecord'] == expected, 'finalizer-failure-incomplete'
(retained / 'request-failed').write_text('close\n')
module['complete_record'](str(retained), '0')
assert 'control:client-request-failed' in json.loads((retained / 'completeness.json').read_text())['problems'], 'lost-client-receipt-incomplete'
for name, data, problem in (('partial', b'{"kind":', 'record:partial-final-record'), ('missing', b'{}\n', 'record:terminal-missing'), ('malformed', b'invalid\n', 'record:unreadable')):
    path = root / ('bad-' + name); path.write_bytes(data)
    assert problem in module['read_record'](path)['problems'], 'partial-terminal-incomplete'
PY
then ok "display collector preserves streams and rejects missing, interrupted, partial, truncated and overflow records"; else fail "display collector contract"; fi

# Drive missing tools through the real screensaver and Power branches,
# device readiness reader, scene loop and verdict without a compositor.
# Capture stands for the later frame producer.
scene_continuation_case() {
  local script="$1" scenario="${2:-screensaver}" expected="${3:-77}" dir status=0 out
  dir="$(mktemp -d "$tmp/scene-continuation.XXXXXX")" || return 1
  mkdir -p "$dir/bin" "$dir/shots"
  for tool in wc awk tr; do ln -s "$(command -v "$tool")" "$dir/bin/$tool"; done
  python3 - "$script" "$dir/runner.sh" "$repo/scripts/smoke/devices.sh" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
start = text.index('scene_screensaver() {')
end = text.index('\n# The setup each scene needs', start)
tail = text.index('# The first shot is the bare desktop;')
power, = re.findall(r'^scene_power\(\) \{.*?^\}', text, re.M | re.S)
ready, = re.findall(r'^devices_ready\(\) \{.*?^\}', open(sys.argv[3]).read(), re.M | re.S)
scene_run, = re.findall(r'^shots_scene_run\(\) \{.*?^\}', text, re.M | re.S)
open(sys.argv[2], 'w').write('\n'.join((power, ready, scene_run, text[start:end], text[tail:])))
PY
  : >"$dir/auth.log"
  env -i PATH="$dir/bin" "$BASH" -c '
    set -euo pipefail
    SHOT_DIR="$1/shots"
    auth_log="$1/auth.log"
    source "$2/scripts/smoke/verdict.sh"
    unmeasured=0
    baseline_side=""
    mode_list=(dark)
    case $3 in
      clean) scenes=(capture) ;;
      screensaver) scenes=(screensaver capture) ;;
      registry) scenes=(power capture) ;;
      both) scenes=(screensaver power capture) ;;
      failure) scenes=(capture); failures=1 ;;
      failure-registry) scenes=(power capture); failures=1 ;;
      mode-drift) scenes=(mode-drift capture) ;;
      *) exit 2 ;;
    esac
    devices_state=missing=pipewire
    devices_up() { return 77; }
    enable_ids=() disable_ids=()
    park_pointer() { :; }
    set_mode() { mode_theme="$1"; }
    scene_desktop() { :; }
    capture_state_record() { :; }
    take() { printf "frame\n" >"$SHOT_DIR/$1.png"; printf "%s\ts\tp\tsettled\tclean\n" "$1" >>"$SHOT_DIR/shots.tsv"; }
    scene_capture() { [[ $mode_theme == "$1" ]]; take "capture-$1-panel"; }
    scene_mode-drift() { mode_theme=other; }
    ok() { :; }
    fail() { failures=$((failures + 1)); }
    source "$1/runner.sh"
  ' _ "$dir" "$repo" "$scenario" >"$dir/out" 2>"$dir/err" || status=$?
  printf '%s\n' "$status" >"$dir/exit"
  out="$(cat -- "$dir/out")"
  [[ $status -eq $expected && -e $dir/shots/capture-dark-panel.png && ! -e $dir/shots/screensaver-dark-cover.png ]] || return 1
  case $scenario in
    screensaver|both) [[ $out == *'scene=screensaver mode=dark status=not-measured missing=ttfx'* ]] || return 1 ;;
  esac
  case $scenario in
    registry|both|failure-registry)
      if [[ $expected -eq 77 ]]; then
        [[ $out == *'rows=power-shot:missing=pipewire'* ]] || return 1
      fi ;;
  esac
  return 0
}
scene_continuation_cases() { # SCRIPT
  local scenario expected
  while read -r scenario expected; do
    scene_continuation_case "$1" "$scenario" "$expected" || return 1
  done <<'CONTINUATION_CASES'
clean 0
screensaver 77
registry 77
both 77
failure 1
failure-registry 1
mode-drift 0
CONTINUATION_CASES
}
if scene_continuation_cases "$repo/scripts/sandbox-shots.sh"; then
  ok "scene verdicts preserve later captures, unavailable causes and failure precedence"
else
  fail "scene continuation or unavailable verdict contract"
fi
continuation_controls=(
  'a mode written only before the scene list leaks scene state' $'  for scene in "${scenes[@]}"; do\n    set_mode "$mode" || { fail "the $scene $mode capture theme could not be set"; continue; }' $'  set_mode "$mode"\n  for scene in "${scenes[@]}"; do'
  'the old whole-run exit stops later Capture' '    return 0' '    exit 77'
  'a missing scene becomes a passing run' 'if [[ $unmeasured -ne 0 || ${#not_measured_rows[@]} -gt 0 ]]; then' 'if false; then'
  'a device registry entry becomes a passing run' ' || ${#not_measured_rows[@]} -gt 0' ''
)
for (( i = 0; i < ${#continuation_controls[@]}; i += 3 )); do
  label="${continuation_controls[i]}"; needle="${continuation_controls[i + 1]}"; replacement="${continuation_controls[i + 2]}"
  continuation_mutant="$tmp/continuation-mutant.sh"
  # Limit the return mutation to the missing-tool branch, leaving other
  # scenes and every statement after that branch unchanged.
  python3 - "$repo/scripts/sandbox-shots.sh" "$continuation_mutant" "$needle" "$replacement" <<'PY'
import sys
source, destination, needle, replacement = sys.argv[1:]
text = open(source).read()
if needle == '    return 0':
    start = text.index('scene_screensaver() {')
    end = text.index('\n  python3', start)
else:
    start, end = 0, len(text)
block = text[start:end]
assert block.count(needle) == 1
changed = block.replace(needle, replacement)
assert changed != block
open(destination, 'w').write(text[:start] + changed + text[end:])
PY
  if scene_continuation_cases "$continuation_mutant"; then fail "control: $label stayed green"; else ok "control: $label"; fi
done

# Drive the real scene_tailscale-section, its shots and its take through
# the scene loop and verdict over stand-ins, with no compositor. A state
# read that fails inside the shots is recorded, the scene's teardown still
# runs and the later scene is still taken; a failed step that records
# nothing names its scene, mode, command, source and status once before exit.
tailscale_stop_case() { # SCRIPT FAULT STATUS TEARDOWN
  local script="$1" fault="$2" expected="$3" teardown="$4" dir command source status=0
  dir="$(mktemp -d "$tmp/tailscale-stop.XXXXXX")" || return 1
  mkdir -p -- "$dir/shots" "$dir/sandbox" "$dir/shim" "$dir/root/usr/bin" "$dir/bin"
  : >"$dir/shim/tailscale"
  : >"$dir/auth.log"
  python3 - "$script" "$dir/runner.sh" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
names = ('scene_tailscale-section', 'tailscale_section_shots', 'tailscale_section_take', 'shots_scene_run', 'shots_baseline_safety')
bodies = [re.findall(r'^' + re.escape(n) + r'\(\) \{.*?^\}', text, re.M | re.S) for n in names]
assert all(len(b) == 1 for b in bodies), 'tailscale-stop-extraction'
tail = text.index('\npark_pointer\ntake "00-desktop"\n')
open(sys.argv[2], 'w').write('\n'.join([b[0] for b in bodies] + [text[tail:]]))
# The Launcher heredoc is a shipped multiline BASH_COMMAND producer.
start = text.index('  python3 - "$theme_file" <<' + "'PYLAUNCHER'")
end = text.index('\nPYLAUNCHER', start) + len('\nPYLAUNCHER')
open(sys.argv[2].replace('runner.sh', 'multiline.sh'), 'w').write(text[start + 2:end] + '\n')
PY
  if [[ $fault == multiline ]]; then
    printf '#!%s\nexit 1\n' "$BASH" >"$dir/bin/python3"
    chmod +x "$dir/bin/python3"
  fi
  env -i PATH="$dir/bin:$PATH" "$BASH" -c '
    set -euo pipefail
    case_dir="$1" fault="$2" repo="$3"
    theme_file="$case_dir/theme.json" SHOT_DIR="$case_dir/shots" auth_log="$case_dir/auth.log" sandbox="$case_dir/sandbox" shim="$case_dir/shim" devices_system_root="$case_dir/root"
    failures=0 unmeasured=0 baseline_side="" not_measured_rows=() mode_list=(dark) scenes=(tailscale-section capture) enable_ids=() disable_ids=()
    ok() { :; }
    fail() { failures=$((failures + 1)); printf "FAIL %s\n" "$*"; }
    take() { printf "frame\n" >"$SHOT_DIR/$1.png"; printf "%s\n" "$1" >>"$SHOT_DIR/shots.tsv"; }
    take_posed() { take "$1"; }
    ipc() { if [[ $fault == read && $2 == statusValues ]]; then return 1; fi; echo 1; }
    # The first scroll fails, inside the shots; the later one in the scene body does not.
    tailscale_section_top() { if [[ $fault == multiline ]]; then source "$case_dir/multiline.sh"; fi; [[ $fault != unrecorded || -e $case_dir/top-failed ]] || { : >"$case_dir/top-failed"; return 1; }; }
    tailscale_shot_finish() { : >"$case_dir/teardown"; }
    scene_capture() { take "capture-$1-panel"; }
    expect() { :; }; expect_poll() { :; }
    park_pointer() { :; }; set_mode() { :; }; scene_desktop() { :; }; capture_state_record() { :; }
    devices_ready() { :; }; device_reply() { :; }; device_reply_clear() { :; }; tree_rescan() { :; }; tree_has() { return 1; }
    tailscale_fixture() { printf "%s/scripts/fixtures/tailscale/%s" "$repo" "$1"; }
    sentinel_saved() { :; }; sentinel_stand_over() { cat >/dev/null; }; sentinel_restore() { :; }
    shell_resolves() { echo none; }
    click_in() { :; }; click_item() { :; }; type_keys() { :; }
    source "$case_dir/runner.sh"
  ' _ "$dir" "$fault" "$repo" >"$dir/out" 2>"$dir/err" || status=$?
  [[ $status -eq $expected ]] || return 1
  if [[ $fault == unrecorded || $fault == multiline ]]; then
    command='return 1' source="$dir/runner.sh"
    if [[ $fault == multiline ]]; then
      command="$(cat "$dir/multiline.sh")"$'\n' source="$dir/multiline.sh"
    fi
    printf -v command '%q' "$command"
    # VGS-2263 defines this diagnostic as the result of an unrecorded abort.
    [[ ! -s $dir/out ]] || return 1
    [[ $(wc -l <"$dir/err") -eq 1 ]] || return 1
    [[ $(cat "$dir/err") =~ ^sandbox-shots:\ aborted\ scene=tailscale-section\ mode=dark\ command="$command"\ source="$source":[1-9][0-9]*\ status=1$ ]] || return 1
  else
    [[ ! -s $dir/err ]] || return 1
  fi
  [[ $teardown == no ]] || [[ -e $dir/teardown && -e $dir/shots/capture-dark-panel.png ]]
}
tailscale_stop_cases() { # SCRIPT [FAULT]
  local fault expected teardown
  while read -r fault expected teardown; do
    [[ -z ${2:-} || $fault == $2 ]] || continue
    tailscale_stop_case "$1" "$fault" "$expected" "$teardown" || return 1
  done <<'TAILSCALE_STOP_CASES'
clean 0 yes
read 1 yes
unrecorded 1 no
multiline 1 no
TAILSCALE_STOP_CASES
}
if tailscale_stop_cases "$repo/scripts/sandbox-shots.sh"; then
  ok "a failed Tailscale section step is recorded, runs the scene's teardown and fails the run"
else
  fail "Tailscale section stop contract"
fi
tailscale_stop_controls=(
  'multiline' 'a raw multiline command cannot split the abort diagnostic' 'command=%q source=%s:%s status=%s' 'command=%s source=%s:%s status=%s'
  'unrecorded' 'an unrecorded abort without its diagnostic is rejected' 'printf "sandbox-shots: aborted scene=%s' ': "sandbox-shots: aborted scene=%s'
  'unrecorded' 'shots called in an || list hide a failure nothing recorded' '  tailscale_section_shots "$mode" "$dir"' '  tailscale_section_shots "$mode" "$dir" || true'
  'read' 'an unread state that ends the shots skips the teardown' '|| { fail "shot tailscale-section-$1-$2 not taken: its state is unreadable"; return; }' '|| return 1'
)
for (( i = 0; i < ${#tailscale_stop_controls[@]}; i += 4 )); do
  label="${tailscale_stop_controls[i + 1]}"
  tailscale_stop_mutant="$tmp/tailscale-stop-mutant.sh"
  mutate "$repo/scripts/sandbox-shots.sh" "${tailscale_stop_controls[i + 2]}" "${tailscale_stop_controls[i + 3]}" "$tailscale_stop_mutant" || { fail "control: $label could not be planted"; continue; }
  if tailscale_stop_cases "$tailscale_stop_mutant" "${tailscale_stop_controls[i]}"; then fail "control: $label stayed green"; else ok "control: $label"; fi
done

# Run the System scene's geometry wait against a compositor fixture. A
# queued layer reload reads the active Lua configuration after both readers
# agree, before capture. A stale service or unapplied rule prevents capture.
displays_geometry_case() { # SCRIPT
  local script="$1" dir status=0
  dir="$(mktemp -d "$tmp/displays-geometry.XXXXXX")" || return 1
  python3 - "$script" "$repo/scripts/smoke/harness.sh" "$dir/scene.sh" <<'PY'
import sys
text = open(sys.argv[1]).read()
harness = open(sys.argv[2]).read()
blocks = [text[text.index('system_shown() {'):text.index('\nsound_lists_player() {')]]
for start, end in [('py_reply() {', '\n# jarvis_ready'), ('expect() {', '\n# rescan LABEL'), ('hypr_lua_save() {', '\n# The key capture rows')]:
    offset = harness.index(start)
    blocks.append(harness[offset:harness.index(end, offset)])
shim_functions = [line for line in harness.splitlines() if line.startswith('shim_hyprctl() {')]
assert len(shim_functions) == 1
blocks.extend(shim_functions)
open(sys.argv[3], 'w').write('\n'.join(blocks))
PY
  cat >"$dir/monitor.py" <<'PY'
import json, re, sys
rules = open(sys.argv[1]).read()
monitors = []
for body in re.findall(r'hl\.monitor\(\{([^}]+)\}\)', rules):
    fields = dict(re.findall(r'(\w+)\s*=\s*("[^"]*"|-?[\d.]+)', body))
    if json.loads(fields['output']) != 'VGS-PLANTED-VRR':
        continue
    width, height = map(int, json.loads(fields['mode']).split('@')[0].split('x'))
    x, y = map(int, json.loads(fields['position']).split('x'))
    monitors = [dict(name='VGS-PLANTED-VRR', identifier='VGS-PLANTED-VRR',
                     width=width, height=height, x=x, y=y,
                     scale=float(fields['scale']), transform=int(fields['transform']))]
print(json.dumps(monitors))
PY
  env -i PATH="$PATH" D="$dir" bash -c '
    set -euo pipefail
    source "$D/scene.sh"
    sandbox="$D" home="$D/home" shim="$D/shim"
    ipc_timeout_log="$sandbox/ipc-timeout.log"
    mkdir -p "$home/.local/state/vgshell/plugins/vgs.displays" "$home/.config/hypr" "$shim"
    printf "#!/usr/bin/env bash\nexit 1\n" >"$shim/hyprctl.real"
    printf "%s\n" '\''hl.monitor({ output = "VGS-PLANTED-VRR", mode = "5120x2880@60", position = "1755x0", scale = 2, transform = 0 })'\'' >"$D/original.lua"
    cp "$D/original.lua" "$home/.config/hypr/hyprland.lua"
    ok() { :; }
    fail() { failures=$((failures + 1)); }
    reader_stderr() { [[ ! -s $2 ]]; }
    smoke_poll_tries() { smoke_poll_n=5 smoke_poll_control=false; }
    poll_clock=0
    now_ms() { echo "$poll_clock"; }
    sleep() {
      local fraction="${1#*.}"
      while ((${#fraction} < 3)); do fraction+=0; done
      poll_clock=$((poll_clock + ${1%%.*} * 1000 + 10#$fraction))
    }
    ships_plugin() { [[ $1 == vgs.displays ]]; }
    devices_up() { :; }
    devices_system_tree() { echo fixture; }
    park_pointer() { :; }
    take() {
      if [[ $1 == *-displays ]]; then
        # Receipts prove agreement before the queued reload. No eval can
        # repair the configuration between that reload and capture.
        assert_geometry "$D/compositor-read" -1440 -620 1
        assert_geometry "$D/service-read" -1440 -620 1
        hypr reload config-only >/dev/null
        : >"$D/reloaded"
        cp "$D/compositor" "$D/captured-compositor"
        cp "$D/service" "$D/captured-service"
      fi
    }
    assert_geometry() {
      python3 - "$@" <<PY
import json, sys
m, = json.load(open(sys.argv[1]))
assert (m["width"], m["height"], m["x"], m["y"], m["scale"], m["transform"]) == (5120, 2880, int(sys.argv[2]), int(sys.argv[3]), 2, int(sys.argv[4]))
PY
    }
    load_config() {
      if [[ -e $D/output ]]; then
        python3 "$D/monitor.py" "$1" >"$D/compositor"
      else
        echo "[]" >"$D/compositor"
      fi
    }
    emit_output() {
      cp "$1" "$1-read"
      cat "$1"
    }
    ipc() {
      if [[ $* == "smoke instanceGeometry window vgs.system" ]]; then cat "$D/window"
      elif [[ $* == "smoke readInstance service vgs.displays outputs" ]]; then emit_output "$D/service"
      elif [[ $* == "shell summon window vgs.system "* ]]; then echo shown >"$D/window"; echo ok
      elif [[ $* == "shell hide window vgs.system" ]]; then echo absent >"$D/window"; echo ok
      elif [[ $* == *"focusInstance"* ]]; then echo focused
      else echo ok
      fi
    }
    hypr() {
      case "$*" in
        eval*)
          if [[ $scenario != blocked ]]; then
            printf "%s\n" "$2" >"$D/eval.lua"
            load_config "$D/eval.lua"
          fi
          echo eval >>"$D/evals"; echo ok ;;
        "-j monitors all") emit_output "$D/compositor" ;;
        "output create wayland VGS-PLANTED-VRR") : >"$D/output"; echo ok ;;
        "output remove VGS-PLANTED-VRR-READ")
          if [[ $scenario == reload && ! -e $D/reset ]]; then
            : >"$D/reset"; load_config "$D/original.lua"
          fi
          [[ $scenario == stale ]] || cp "$D/compositor" "$D/service"
          echo ok ;;
        "output remove VGS-PLANTED-VRR")
          rm "$D/output"; echo "[]" >"$D/compositor"; echo "[]" >"$D/service"; echo ok ;;
        "reload config-only")
          load_config "$home/.config/hypr/hyprland.lua"
          cp "$D/compositor" "$D/service"; echo ok ;;
        *) echo ok ;;
      esac
    }
    displays_listed() { echo 3; }
    window_panes() { echo "[\"vgs.displays\"]"; }
    for scenario in reload stale blocked; do
      failures=0
      rm -f -- "${D:?}/captured-compositor" "${D:?}/captured-service" "${D:?}/reloaded" "${D:?}/reset" "${D:?}/evals" "${D:?}/compositor-read" "${D:?}/service-read"
      : >"$D/output"
      load_config "$D/original.lua"; cp "$D/compositor" "$D/service"; echo absent >"$D/window"
      scene_system dark
      cmp "$shim/hyprctl.real" "$shim/hyprctl" || exit 1
      cmp "$D/original.lua" "$home/.config/hypr/hyprland.lua" || exit 1
      [[ $(cat "$D/compositor") == "[]" && $(cat "$D/service") == "[]" && ! -e $D/output ]] || exit 1
      if [[ $scenario == reload ]]; then
        [[ $failures == 0 && -e $D/reset && -e $D/reloaded ]] || exit 1
        assert_geometry "$D/captured-compositor" -1440 -620 1
        assert_geometry "$D/captured-service" -1440 -620 1
      else
        [[ $failures -gt 0 && ! -e $D/captured-compositor && ! -e $D/reloaded && -s $D/evals ]] || exit 1
      fi
      hypr output create wayland VGS-PLANTED-VRR >/dev/null
      hypr reload config-only >/dev/null
      assert_geometry "$D/compositor" 1755 0 0
      assert_geometry "$D/service" 1755 0 0
    done
  ' >"$dir/out" 2>"$dir/err" || status=$?
  [[ $status == 0 ]]
}
if displays_geometry_case "$repo/scripts/sandbox-shots.sh"; then
  ok "Displays keeps exact geometry across a reload after agreement, restores it, and refuses capture without agreement"
else
  fail "Displays keeps exact geometry across a reload after agreement, restores it, and refuses capture without agreement"
fi
displays_mutant="$tmp/displays-without-wait.sh"
python3 - "$repo/scripts/sandbox-shots.sh" "$displays_mutant" <<'PY'
import sys
text = open(sys.argv[1]).read()
lines = text.splitlines(keepends=True)
matches = [i for i, line in enumerate(lines) if 'expect_poll "displays-geometry-not-applied:' in line]
assert len(matches) == 1
lines[matches[0]] = '      :\n'
changed = ''.join(lines)
assert changed != text
open(sys.argv[2], 'w').write(changed)
PY
if displays_geometry_case "$displays_mutant"; then
  fail "control: Displays without its wait stayed green"
else
  ok "control: Displays without its wait fails geometry"
fi
displays_mutant="$tmp/displays-without-saved-rule.sh"
if mutate "$repo/scripts/sandbox-shots.sh" '      printf '\''%s\n'\'' "$displays_output_rule" >>"$home/.config/hypr/hyprland.lua"' '      :' "$displays_mutant"; then
  if displays_geometry_case "$displays_mutant"; then
    fail "control: Displays without its saved rule stayed green"
  else
    ok "control: Displays without its saved rule fails geometry after the queued reload"
  fi
else
  fail "control: Displays saved-rule mutation"
fi

# The scene choice of scripts/sandbox-shots.sh, before any sandbox starts:
# a tree ships either the Settings plugin or the bar's manager built-in, a
# plugin scene needs its plugins' manifests, and a scene the tree does not
# ship is refused with exit 2. A scratch git
# repository holds the script, a link to the smoke directory, a revision
# with the bar's manager and a later one with vgs.settings, so --rev reads
# an older tree. A scene the tree ships passes the choice and reaches the
# harness, which, with no Wayland socket in the environment, exits 77.
shots_repo="$tmp/shots-repo"
mkdir -p "$shots_repo/scripts" "$shots_repo/shell/plugins/vgs.bar" "$shots_repo/bin" "$shots_repo/config" "$shots_repo/themes" "$shots_repo/tmp"
mkdir -p "$shots_repo/scripts/smoke"
for smoke_helper in "$repo"/scripts/smoke/*; do
  [[ ${smoke_helper##*/} == harness.sh ]] || ln -s "$smoke_helper" "$shots_repo/scripts/smoke/${smoke_helper##*/}"
done
printf 'echo "qml-smoke: status=not-measured missing=fixture-harness"\nexit 77\n' >"$shots_repo/scripts/smoke/harness.sh"
: >"$shots_repo/shell/plugins/vgs.bar/Manager.qml"; : >"$shots_repo/bin/vgshell"; : >"$shots_repo/config/shell.json"; : >"$shots_repo/themes/.keep"
git_quiet() { git -C "$shots_repo" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@" >/dev/null; }
cp -- "$repo/VERSION" "$repo/LICENSE" "$repo/README.md" "$shots_repo/"
git_quiet init -q
git_quiet add shell bin config themes VERSION LICENSE README.md
git_quiet commit -q -m manager
old_rev="$(git -C "$shots_repo" rev-parse HEAD)"
mkdir -p "$shots_repo/shell/plugins/vgs.settings" "$shots_repo/shell/plugins/vgs.themes" "$shots_repo/shell/plugins/vgs.polkit" "$shots_repo/shell/plugins/vgs.capture"
: >"$shots_repo/shell/plugins/vgs.settings/manifest.json"
# The checkout ships the theme browsers, so their scene reaches the theme
# card check; it ships no Dev Tools, whose scene is refused. It ships the
# polkit prompt, which the earlier revision does not.
: >"$shots_repo/shell/plugins/vgs.themes/manifest.json"
: >"$shots_repo/shell/plugins/vgs.polkit/manifest.json"
: >"$shots_repo/shell/plugins/vgs.capture/manifest.json"
git -C "$shots_repo" rm -q shell/plugins/vgs.bar/Manager.qml
git_quiet add shell
git_quiet commit -q -m settings
# The harness loads bin/lib/ipc-reply.sh from the checkout it runs in.
ln -s "$repo/bin/lib" "$shots_repo/bin/lib"
# Only the checkout's working tree holds the demo catalog package, so a
# catalog mode reads it with no --rev and finds it absent from a revision.
mkdir -p "$shots_repo/themes/catalog/demo"
printf '{ "schemaVersion": 1, "name": "demo", "tokens": {} }\n' >"$shots_repo/themes/catalog/demo/theme.json"
# scene_case SCRIPT LABEL STATUS LINE ARG...: SCRIPT run from the scratch
# repository gives STATUS and LINE on stderr, or with STATUS 77 a stdout
# line starting LINE. On a host with an amdgpu node the run enters
# scripts/smoke/gpu-fence.sh, whose cleanup and proof lines come first on
# stderr and are not the script's; scene_skip matches them. Where the fence
# could not make or prove its namespace no scene case measured anything:
# the suite prints `test-sandbox-shots: status=not-measured` with the
# fence's own line and exits 77.
scene_skip='^gpu-fence: \(\(absent\|present\) path\|cleanup\)='
scene_case() {
  local script="$1" label="$2" want_status="$3" want_line="$4" status=0 out err
  shift 4
  cp -- "$script" "$shots_repo/scripts/sandbox-shots.sh"
  out="$(env -i PATH="$tmp/bin:$PATH" HOME="$tmp" TMPDIR="$TMPDIR" VGSHELL_WORLD_ROOT="$VGSHELL_WORLD_ROOT" "$BASH" "$shots_repo/scripts/sandbox-shots.sh" --out "$shots_repo/tmp/shots-$RANDOM$RANDOM" "$@" 2>"$tmp/scene.err")" || status=$?
  err="$(sed -n "/$scene_skip/!{p;q}" "$tmp/scene.err")"
  if [[ $status -eq 77 && $err == "gpu-fence: status=not-measured "* ]]; then
    printf 'test-sandbox-shots: status=not-measured %s\n' "$err"
    exit 77
  fi
  if [[ $status -eq $want_status && ( $err == "$want_line" || ( $want_status -eq 77 && $out == "$want_line"* ) ) ]]; then return 0; fi
  echo "$label: exit=$status stderr=$err stdout=$(head -n 1 <<<"$out")"
  return 1
}
scene_cases=(
  "a checkout with the Settings plugin refuses the manager scene" 2 "sandbox-shots: refused: scene=manager tree=checkout" manager
  "a revision before the Settings plugin refuses the settings scene" 2 "sandbox-shots: refused: scene=settings tree=$old_rev" --rev "$old_rev" settings
  "a revision before the Settings plugin takes the manager scene" 77 "qml-smoke: status=not-measured" --rev "$old_rev" manager
  "a checkout with the Settings plugin takes the settings scene" 77 "qml-smoke: status=not-measured" settings
  "a checkout with the Settings plugin takes the plugin-pages scene" 77 "qml-smoke: status=not-measured" plugin-pages
  "a revision before the Settings plugin refuses the plugin-pages scene" 2 "sandbox-shots: refused: scene=plugin-pages tree=$old_rev" --rev "$old_rev" plugin-pages
  "a scale other than 1 or 2 is refused" 2 "sandbox-shots: refused: scale=3" --scale 3 settings
  "scale 2 is taken" 77 "qml-smoke: status=not-measured" --scale 2 settings
  "a theme card that is no catalog name is refused" 2 "sandbox-shots: refused: theme-card=../x" --theme-card ../x settings
  "a theme card the catalog lacks is refused" 2 "sandbox-shots: refused: theme-card=nosuch tree=checkout" --theme-card nosuch theme-browser
  "a checkout without the Dev Tools plugin refuses the devtools scene" 2 "sandbox-shots: refused: scene=devtools tree=checkout" devtools
  "a checkout with the polkit plugin takes the polkit scene" 77 "qml-smoke: status=not-measured" polkit
  "a revision without the polkit plugin refuses the polkit scene" 2 "sandbox-shots: refused: scene=polkit tree=$old_rev" --rev "$old_rev" polkit
  "a checkout without the Gallery plugin refuses the focus scene" 2 "sandbox-shots: refused: scene=focus tree=checkout" focus
  "a checkout with the Capture plugin takes the capture scene" 77 "qml-smoke: status=not-measured" capture
  "a revision without the Capture plugin refuses the capture scene" 2 "sandbox-shots: refused: scene=capture tree=$old_rev" --rev "$old_rev" capture
  "a checkout without the AI Usage plugin refuses the ai-usage scene" 2 "sandbox-shots: refused: scene=ai-usage tree=checkout" ai-usage
  "a checkout with a catalog package takes its mode" 77 "qml-smoke: status=not-measured" --modes catalog-demo settings
  "a revision without a catalog package refuses its mode" 2 "sandbox-shots: refused: mode=catalog-demo" --rev "$old_rev" --modes catalog-demo manager
  "a malformed enable list is refused" 2 "sandbox-shots: refused: enable=vgs.themes," --enable vgs.themes, settings
  "a revision without the polkit plugin refuses enabling it" 2 "sandbox-shots: refused: enable=vgs.polkit tree=$old_rev" --rev "$old_rev" --enable vgs.polkit manager
  "a checkout with the polkit plugin takes enabling it" 77 "qml-smoke: status=not-measured" --enable vgs.polkit,vgs.themes settings
  "a malformed disable list is refused" 2 "sandbox-shots: refused: disable=vgs.themes," --disable vgs.themes, settings
  "a revision without the polkit plugin refuses disabling it" 2 "sandbox-shots: refused: disable=vgs.polkit tree=$old_rev" --rev "$old_rev" --disable vgs.polkit manager
  "a checkout with the polkit plugin takes disabling it" 77 "qml-smoke: status=not-measured" --disable vgs.polkit,vgs.themes settings
  "a plugin cannot be enabled and disabled together" 2 "sandbox-shots: refused: state=vgs.themes reason=enabled-and-disabled" --enable vgs.themes --disable vgs.themes settings
)
# Each case is label, status, line, then its arguments up to the next case,
# counted by the arguments each row above carries.
scene_arity=(1 3 3 1 1 3 3 3 3 3 1 1 3 1 1 3 1 3 5 3 5 3 3 5 3 5)
# Where each case starts in scene_cases and how many arguments it takes, by
# label, for the controls below.
declare -A scene_at scene_argc
at=0
for n in "${!scene_arity[@]}"; do
  label="${scene_cases[at]}"; status="${scene_cases[at + 1]}"; line="${scene_cases[at + 2]}"
  scene_at[$label]=$at; scene_argc[$label]=${scene_arity[n]}
  args=("${scene_cases[@]:at + 3:${scene_arity[n]}}")
  at=$((at + 3 + ${scene_arity[n]}))
  if scene_case "$repo/scripts/sandbox-shots.sh" "$label" "$status" "$line" "${args[@]}"; then ok "$label"; else fail "$label"; fi
done

# Drive the production assertion boundary and closing verdict without
# starting a compositor. Commands below are fixtures, never replacements
# for expect, reader_stderr, verdict.sh or the baseline decision.
if python3 - "$repo" "$tmp" "$BASH" <<'PYBASELINE_TEST'
from pathlib import Path
import json
import os
import subprocess
import sys

repo, scratch, bash = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
source = (repo / "scripts/sandbox-shots.sh").read_text()
harness = (repo / "scripts/smoke/harness.sh").read_text()
jarvis = (repo / "scripts/smoke/jarvis-console.sh").read_text()
power = (repo / "scripts/smoke/power-fakes.sh").read_text()
root = scratch / "baseline"
root.mkdir()

def function(name, text=harness):
    start = text.index("\n" + name + "()") + 1
    return text[start:text.index("\n}\n", start) + 3]

assertions = root / "assertions.sh"
assertions.write_text("\n".join(function(name) for name in ("reader_stderr", "expect", "expect_poll", "smoke_poll_tries", "py_reply")) + "\n" +
                      "\n".join(next(line for line in harness.splitlines() if line.startswith(name + "() {"))
                                for name in ("ok", "settings_act", "settings_open_tui")) + "\n")
driver = root / "driver.sh"
driver.write_text(r'''
set -euo pipefail
self=$1 baseline_side=$2 baseline_ledger=$3 kind=$4
scene=$5 mode=$6 label=$7 got_fixture=$8 want_fixture=$9
sandbox=${10} SHOT_DIR=${10} auth_log=${10}/auth ipc_timeout_log=${10}/timeout
home="$sandbox/home" repo="$sandbox/repo" rt_dir="$VGSHELL_WORLD_ROOT/runtime/owned/vs.${sandbox##*.}"
dependency=${17} settings_kind=window
mkdir -p "$sandbox"
jarvis_asks_home="$sandbox"
shim="$sandbox/shim" power_display_wake_saved="$sandbox/power-display-wake"
mkdir -p "$home/.config/hypr" "$shim" "$power_display_wake_saved"
printf 'fixture\n' >"$power_display_wake_saved/hyprland.lua"
printf 'fixture\n' >"$power_display_wake_saved/hyprctl"
: >"$auth_log"
: >"$SHOT_DIR/shots.tsv"
source "${11}"
source "${12}"
source "${13}"
source "${15}"
source "${16}"
unmeasured=0 smoke_poll_scope=0 smoke_poll_bound_ms=200
shots_baseline_start
reading() {
  case "$kind" in
    operation) printf '%s' "$got_fixture"; return 23 ;;
    reader) printf 'Traceback (most recent call last):\n' >&2 ;;
    *) printf '%s' "$got_fixture" ;;
  esac
}
ipc() {
  [[ $dependency != ipc && ( $dependency != scroll || $2 != scrollAreas ) ]] ||
    { printf 'ipc-failed\n'; printf 'fixture-ipc-failed\n' >&2; return 23; }
  if [[ $2 == scrollAreas ]]; then printf '[{"bar":[1,1,1,1]}]\n'; return 0; fi
  if [[ $kind == wrapped-jarvis-* && $2 == jarvisProcess ]]; then
    printf '{"status":{"ownerAsks":{"revision":"fixture","active":[{"id":"tracker-design","revision":"fixture"},{"id":"fleet-update","revision":"fixture"},{"id":"jarvis-briefing","revision":"fixture"}],"snoozed":[],"activeNextCursor":"fixture"}}}\n'
    return 0
  fi
  if [[ $kind == displays ]]; then printf '[]\n'; else reading; fi
}
preview_tmux() {
  [[ $dependency != tmux ]] || { printf 'fixture-tmux-failed\n' >&2; return 23; }
  reading
}
recorded() {
  [[ $dependency != recorded ]] || { printf 'fixture-record-failed\n' >&2; return 23; }
  printf '[]\n'
}
key_idle() {
  [[ $dependency != key-idle ]] || { printf 'fixture-key-read-failed\n' >&2; return 23; }
  printf 'idle\n'
}
layer_count() {
  [[ $dependency != layers ]] || { printf 'fixture-layer-read-failed\n' >&2; return 23; }
  printf '1\n'
}
bar_key() { printf 'bar\n'; }
hypr() {
  local step
  if [[ $kind == wrapped-wake-* ]]; then reading; return; fi
  case "$1" in eval) step=eval ;; -j) step=monitors ;; *) step=$2 ;; esac
  [[ $dependency != "$step" ]] || { printf 'fixture-hypr-%s-failed\n' "$step" >&2; return 23; }
  [[ $dependency != "$step-refused" ]] || { printf 'refused\n'; return 0; }
  if [[ $step == monitors ]]; then
    if [[ $dependency == create* || $dependency == remove* ]]; then
      printf '[{"name":"VGS-PLANTED-VRR","width":5120,"height":2880,"x":-1440,"y":-620,"scale":2,"transform":1}]\n'
    else printf '[]\n'; fi
  else printf 'ok\n'; fi
}
probe() {
  case "$kind" in
    timeout) : >"$ipc_timeout_log"; printf 'latched\n' >"$ipc_timeout_log"; expect_poll "$label" "$want_fixture" reading ;;
    poll) expect_poll "$label" "$want_fixture" reading ;;
    safety) shots_baseline_safety expect "$label" "$want_fixture" reading ;;
    acknowledgement) expect "$label" "$want_fixture" ipc shell summon ;;
    observation) expect "$label" "$want_fixture" ipc smoke "$label" ;;
    wrapped-*) "operation_${kind#wrapped-}" dark fixture ;;
    settings-empty) expect "$label" "$want_fixture" settings_empty ;;
    updates-action) expect "$label" "$want_fixture" updates_action ;;
    outdated-notice) expect "$label" "$want_fixture" outdated_notice_back ;;
    preview-drawn) expect "$label" "$want_fixture" preview_drawn ;;
    displays) expect "$label" "$want_fixture" displays_outputs_applied ;;
    control-inner)
      rejected="$(failures=0; expect "$label" "$want_fixture" reading >/dev/null; printf '%s' "$failures")"
      expect 'control: planted assertion is detected' 1 printf '%s' "$rejected" ;;
    *) expect "$label" "$want_fixture" reading ;;
  esac
  printf 'continued\n'
}
shots_scene_run probe
source "${14}"
''')
tail = root / "closing.sh"
tail.write_text(source[source.index("# No scene may authenticate against the host user:"):])

def prepare(text, name):
    script = root / (name + ".sh")
    script.write_text(text)
    boundary = root / (name + "-boundary.sh")
    start = text.index("# Ledger records are JSON tuples")
    boundary.write_text(text[start:text.index("if [[ ${1:-} == --check-desktop-pair", start)])
    readers = root / (name + "-readers.sh")
    names = ("settings_empty", "updates_action", "outdated_notice_back", "preview_drawn",
             "displays_output_taken", "displays_outputs_applied")
    blocks = []
    for owner in names:
        at = text.index("\n" + owner + "()") + 1
        blocks.append(text[at:text.index("\n}\n", at) + 3])
    blocks.append(next(line for line in text.splitlines() if line.startswith("displays_second_output()")))
    blocks.append(next(line for line in text.splitlines() if line.startswith("settings_scroll()")))
    blocks.append(next(line for line in text.splitlines() if line.startswith("tooltip_link_call()")))
    blocks.extend(function(owner, jarvis) for owner in ("jarvis_asks_request", "jarvis_asks_page"))
    blocks.append(next(line for line in jarvis.splitlines() if line.startswith("jarvis_asks_refresh()")))
    blocks.extend(function(owner, power) for owner in
                  ("power_display_wake_set", "power_display_wake_transport", "power_display_wake_end"))
    blocks.extend(next(line for line in text.splitlines() if line.startswith(key + "="))
                  for key in ("displays_output", "displays_output_rule"))
    readers.write_text("\n".join(blocks) + "\n")
    operations = root / (name + "-operations.sh")
    # Execute existing scene assertion lines, not another classification
    # model. The wrappers themselves also come from their real owners.
    blocks = []
    watcher = function("scene_restart-owed", text)
    start = watcher.index("  restart_shot_armed()")
    blocks.append(watcher[start:watcher.index("\n  }\n", start) + 5])
    for key, call, producer in (
        ("act", "settings_act", text), ("tui", "settings_open_tui", text),
        ("keyboard", "tooltip_link_call holdKeyboard true", text),
        ("focus", "tooltip_link_call focusItem", text),
        ("restart-watcher", "restart_shot_armed", text),
        ("jarvis-done", "jarvis_asks_request done", jarvis),
        ("jarvis-later", "jarvis_asks_request later", jarvis),
        ("jarvis-reply", "jarvis_asks_request reply", jarvis),
        ("jarvis-refresh", "jarvis_asks_refresh", jarvis),
        ("jarvis-page", "jarvis_asks_page", jarvis),
        ("wake-set", "power_display_wake_set", text),
        ("wake-end", "power_display_wake_end", text),
    ):
        line = next(line.strip() for line in producer.splitlines()
                    if "expect " in line or "expect_poll " in line
                    if " " + call in line)
        blocks.append("operation_" + key + "() {\n  local until=2099-01-01T00:00:00Z key=true pointer=false state=fixture\n  " + line + "\n}\n")
    operations.write_text("\n".join(blocks))
    return script, boundary, readers, operations

def run(pair, side, ledger, kind="assertion", scene="gallery", mode="dark",
        label="fixture-value", got="old", want="expected", dependency="none"):
    world = root / ("world-" + str(run.serial))
    sandbox = world / "tmp" / ("vgshell-smoke.identity" + str(run.serial))
    run.serial += 1
    def paths(value):
        return (value.replace("@SANDBOX@", str(sandbox)).replace("@HOME@", str(sandbox / "home"))
                .replace("@REPO@", str(sandbox / "repo")).replace("@WORLD@", str(world))
                .replace("@RUNTIME@", str(world / "runtime/owned" / ("vs." + sandbox.name.split(".")[-1]))))
    return subprocess.run([bash, str(driver), str(pair[0]), side, str(ledger), kind,
                           scene, mode, label, paths(got), paths(want), str(sandbox),
                           str(repo / "scripts/smoke/verdict.sh"), str(assertions), str(pair[1]), str(tail),
                           str(pair[2]), str(pair[3]), dependency],
                          env={"PATH": os.environ["PATH"], "HOME": str(world), "LC_ALL": "C",
                               "VGSHELL_WORLD_ROOT": str(world)},
                          capture_output=True, text=True, timeout=10)
run.serial = 0

def suite(text, name):
    pair = prepare(text, name)
    ledger = root / (name + ".jsonl")
    result = run(pair, "before", ledger)
    assert result.returncode == 0 and "continued\n" in result.stdout, ("before-continue", result)
    records = ledger.read_text().splitlines()
    assert json.loads(records[0]) == ["gallery", "dark", "fixture-value", "old", "expected"], "recorded-tuple"
    result = run(pair, "after", ledger)
    assert result.returncode == 0, ("same-omission", result)
    # Every field is part of the match, especially both product values.
    for changed in ({"scene": "settings"}, {"mode": "light"}, {"label": "another"},
                    {"got": "new"}, {"want": "another"}, {"got": "7312"}, {"got": "/tmp/product-123"}):
        result = run(pair, "after", ledger, **changed)
        assert result.returncode == 1, ("changed-key", changed, result)
    for side in ("before", "after"):
        for kind, label, got, want, status in (
            ("assertion", "control: planted mismatch", "old", "expected", 1),
            ("control-inner", "fixture-value", "old", "expected", 0),
            ("operation", "fixture-value", "old", "expected", 1),
            ("acknowledgement", "operation-ack", "refused", "ok", 1),
            ("reader", "fixture-value", "old", "expected", 1),
            ("assertion", "fixture-value", "unreadable", "expected", 1),
            ("timeout", "fixture-value", "old", "expected", 124),
            ("safety", "fixture-value", "old", "expected", 1),
        ):
            target = root / (name + "-" + side + "-" + kind + "-" + label.replace(":", "") + ".jsonl") if side == "before" else ledger
            result = run(pair, side, target, kind=kind, label=label, got=got, want=want)
            assert result.returncode == status, ("ordinary-failure", side, kind, result)
            if side == "before":
                content = target.read_text()
                if status:
                    assert content == "", ("not-recorded-or-sealed", kind, content)
                else:
                    assert len(content.splitlines()) == 1, ("control-not-recorded", content)
    empty = root / (name + "-empty.jsonl")
    assert run(pair, "before", empty, got="expected").returncode == 0, "empty-before"
    assert run(pair, "after", empty, got="expected").returncode == 0, "empty-after"
    assert run(pair, "after", empty).returncode == 1, "empty-new-failure"
    # Readiness is a prerequisite even when IPC succeeds. Keep the
    # structured watcher failure in the diagnostic, not in an omission.
    for ready, error, status in (
        (True, "", 0),
        (False, "", 1),
        (False, "vgshell-scan did not start", 1),
        (True, "vgshell-scan exited before a core change", 1),
    ):
        state = json.dumps({"ready": ready, "changed": False, "error": error})
        for side in ("before", "after"):
            target = root / (name + "-watcher-" + str(run.serial) + ".jsonl") if side == "before" else empty
            result = run(pair, side, target, kind="wrapped-restart-watcher", got=state)
            assert result.returncode == status, ("restart-prerequisite", ready, error, side, result)
            if status:
                assert state in result.stdout, ("restart-failure-observation", result)
            if side == "before":
                assert (len(target.read_text().splitlines()) == 1 if status == 0 else target.read_text() == ""), (
                    "restart-prerequisite-seal", ready, error, result)
    assert run(pair, "before", ledger).returncode == 1, "exclusive-acquisition"
    assert ledger.read_text().splitlines() == records, "existing-ledger-preserved"
    for token in ("@HOME@/white.png", "@REPO@/themes/vgs/backgrounds/black.png",
                  "@SANDBOX@/file", "@RUNTIME@/lock", "@WORLD@/scratch/file"):
        target = root / (name + "-paths-" + token.split("@")[1] + ".jsonl")
        assert run(pair, "before", target, got=token + " loading", want=token + " ready").returncode == 0
        assert run(pair, "after", target, got=token + " loading", want=token + " ready").returncode == 0, "owned-path-matches"
        assert run(pair, "after", target, got=token + " loading", want=token + " absent").returncode == 1, "product-state-preserved"
    for first, second in (("/tmp/vgshell-smoke.ABC/home/white.png", "/tmp/vgshell-smoke.XYZ/home/white.png"),
                          ("lock-pid=123", "lock-pid=456")):
        target = root / (name + "-unowned-" + str(run.serial) + ".jsonl")
        assert run(pair, "before", target, got=first).returncode == 0
        assert run(pair, "after", target, got=second).returncode == 1, "unowned-identity-preserved"
    # Current Probe.qml observations, including a normal absent-focus
    # reply, remain assertions rather than operation acknowledgements.
    for observation, got, want in (("noticeFocused", "false", "true"),
                                   ("themeValue", "0", "1"),
                                   ("galleryMissing", '["field"]', "[]")):
        target = root / (name + "-" + observation + ".jsonl")
        assert run(pair, "before", target, kind="observation", label=observation, got=got, want=want).returncode == 0, "observation-eligible"
        assert run(pair, "after", target, kind="observation", label=observation, got=got, want=want).returncode == 0, "observation-matches"
    # Each successful absence can seal, but the same reader with an
    # unavailable required dependency cannot seal or match that omission.
    for kind, got, want, faults in (
        ("settings-empty", "absent", "shown", ("ipc",)),
        ("updates-action", "[0,0,1,1]", "shown", ("ipc", "scroll")),
        ("outdated-notice", '{"notices":{"shown":null}}', "back", ("ipc", "recorded", "key-idle", "layers")),
        ("preview-drawn", "", "True", ("tmux",)),
        ("displays", "[]", "5120x2880@-1440,-620 scale=2 transform=1",
         ("ipc", "eval", "eval-refused", "monitors", "create", "create-refused", "remove", "remove-refused")),
    ):
        target = root / (name + "-reader-" + kind + ".jsonl")
        assert run(pair, "before", target, kind=kind, got=got, want=want).returncode == 0, ("reader-absence", kind)
        assert run(pair, "after", target, kind=kind, got=got, want=want).returncode == 0, ("reader-absence-match", kind)
        for fault in faults:
            for side in ("before", "after"):
                failed = root / (name + "-" + kind + "-" + fault + ".jsonl") if side == "before" else target
                result = run(pair, side, failed, kind=kind, got=got, want=want, dependency=fault)
                assert result.returncode == 1, ("dependency-failure", kind, fault, side, result)
                if side == "before":
                    assert failed.read_text() == "", ("dependency-not-sealed", kind, fault)
    for kind, got in (("wrapped-act", "not-offered"), ("wrapped-tui", "busy"),
                      ("wrapped-keyboard", "absent"), ("wrapped-focus", "false"),
                      ("wrapped-jarvis-done", "refused: owner-ask=unconfirmed"),
                      ("wrapped-jarvis-done", "refused: owner-ask=locked"),
                      ("wrapped-jarvis-done", "refused: owner-ask=pending"),
                      ("wrapped-jarvis-later", "refused: owner-ask=unconfirmed"),
                      ("wrapped-jarvis-reply", "refused: owner-ask=pending"),
                      ("wrapped-jarvis-refresh", "refused: jarvis=not-ready"),
                      ("wrapped-jarvis-page", "refused: jarvis=not-ready"),
                      ("wrapped-wake-set", "refused"),
                      ("wrapped-wake-end", "refused")):
        target = root / (name + "-" + kind + "-" + str(run.serial) + ".jsonl")
        result = run(pair, "before", target, kind=kind, got=got)
        assert result.returncode == 1 and target.read_text() == "", ("wrapped-operation", kind, result)
        # Supply a verified record for this tuple to prove the after side
        # cannot treat an operation as an observation even if it is known.
        acknowledgement = root / (target.stem + "-known.jsonl")
        operation_record = result.stdout.split("FAIL  ", 1)[1].split(": got ", 1)[0]
        assert run(pair, "before", acknowledgement, label=operation_record, got=got,
                   want="true" if kind == "wrapped-focus" else "ok").returncode == 0
        assert run(pair, "after", acknowledgement, kind=kind, got=got).returncode == 1, ("wrapped-operation-after", kind)
        successful = root / (target.stem + "-success.jsonl")
        assert run(pair, "before", successful, kind=kind,
                   got="true" if kind == "wrapped-focus" else "ok").returncode == 0, ("wrapped-operation-success", kind)
        assert len(successful.read_text().splitlines()) == 1, ("successful-operation-not-recorded", kind)
    poll = root / (name + "-poll.jsonl")
    assert run(pair, "before", poll, kind="poll").returncode == 0
    assert run(pair, "after", poll, kind="poll").returncode == 0, "successful-poll-read-mismatch"
    damaged = root / (name + "-damaged.jsonl")
    damaged.write_text(ledger.read_text().replace('"old"', '"tampered"'))
    # A matching observation must still refuse corrupt evidence; a new
    # mismatch would redden the case even if the seal guard were missing.
    assert run(pair, "after", damaged, got="expected").returncode == 1, "ledger-hash"
    unsealed = root / (name + "-unsealed.jsonl")
    unsealed.write_text(records[0] + "\n")
    assert run(pair, "after", unsealed).returncode == 1, "unsealed"
    wrong = prepare(text + "\n# different harness\n", name + "-wrong")
    assert run(wrong, "after", ledger).returncode == 1, "script-hash"
    absent = root / (name + "-absent.jsonl")
    assert run(pair, "after", absent).returncode == 1, "unreadable-ledger"
    fifo = root / (name + "-fifo.jsonl")
    os.mkfifo(fifo)
    assert run(pair, "after", fifo).returncode == 1, "special-ledger"

suite(source, "production")
print("baseline: recorded continuation, exact pair, empty seal, integrity and ordinary failures pass")
controls = (
    ("recording", '      printf \'%s\\n\' "$key" >&"$shots_baseline_fd" || return',
     '      : # omitted record', "recorded-tuple"),
    ("same-omission", 'elif [[ -z ${shots_baseline_keys["$key"]+known} ]]; then',
     'elif true; then', "same-omission"),
    ("exact-match", 'elif [[ -z ${shots_baseline_keys["$key"]+known} ]]; then',
     'elif false; then', "changed-key"),
    ("seal", 'if seal != {"script": script_hash, "sha256": hashlib.sha256(body).hexdigest()}:',
     'if False:', "ledger-hash"),
    ("planted-control", '${label:-} != control:*', 'true', "ordinary-failure"),
    ("observation", "shell:hide|shell:summon|", "smoke:noticeFocused|shell:hide|shell:summon|", "observation-eligible"),
    ("owned-root", 'roots = [(sandbox, "<sandbox>"), (runtime, "<runtime>"), (world, "<world>")]',
     'roots = [(world, "<world>")]', "owned-path-matches"),
    ("reader-status", 'box="$(ipc smoke itemGeometry "$settings_kind" vgs.settings Label \'No plugin matches "zzqxv"\')" || return',
     'box="$(ipc smoke itemGeometry "$settings_kind" vgs.settings Label \'No plugin matches "zzqxv"\')" || :', "dependency-failure"),
    ("wrapped-operation", '    jarvis_asks_request|jarvis_asks_refresh|jarvis_asks_page|power_display_wake_set|power_display_wake_end)',
     '    jarvis_asks_refresh|jarvis_asks_page|power_display_wake_set|power_display_wake_end)', "wrapped-operation"),
    ("restart-prerequisite", '  shots_baseline_safety expect_poll "the restart capture\'s source watcher is armed"',
     '  expect_poll "the restart capture\'s source watcher is armed"', "restart-prerequisite"),
)
for name, needle, replacement, expected in controls:
    assert source.count(needle) == 1, ("control-needle", name)
    try:
        suite(source.replace(needle, replacement), "control-" + name)
    except (AssertionError, IndexError) as error:
        assert expected in str(error) or (name == "recording" and isinstance(error, IndexError)), (name, error)
        print("baseline control: %s rejected by %s" % (name, expected))
    else:
        raise AssertionError("baseline control survived: " + name)
PYBASELINE_TEST
then
  ok "sealed baseline assertions and their must-fail controls"
else
  fail "sealed baseline assertions or their must-fail controls"
fi

# Controls, four fields each: label, the refusal's text, which must match
# once, its replacement, and the refused case. A copy with that refusal
# planted away must send the case's arguments on to the harness, which
# exits 77 here, as the scenes the tree ships do; a copy that still refuses
# them, or fails for another reason, leaves the control red.
shots_controls=(
  "an unshipped scene is not refused"
  "  if ! scene_ships \"\$scene\"; then" "  if false; then"
  "a checkout with the Settings plugin refuses the manager scene"
  "the manager's scene is not read"
  "    settings|manager) [[ \$1 == \"\$manager_scene\" ]] ;;" "    settings|manager) true ;;"
  "a checkout with the Settings plugin refuses the manager scene"
  "a scene's plugin is not looked for"
  "[[ -f \$tree/shell/plugins/\$id/manifest.json ]] || return 1" "true || return 1"
  "a checkout without the Dev Tools plugin refuses the devtools scene"
  "the polkit scene's plugin is not looked for"
  "    polkit) ships_plugin vgs.polkit ;;" "    polkit) true ;;"
  "a revision without the polkit plugin refuses the polkit scene"
  "a refused scale goes on to the harness"
  "refused: scale=%s\\n' \"\$scale\" >&2; exit 2; }" "refused: scale=%s\\n' \"\$scale\" >&2; }"
  "a scale other than 1 or 2 is refused"
  "a refused theme card goes on to the harness"
  "refused: theme-card=%s\\n' \"\$theme_card\" >&2; exit 2; }" "refused: theme-card=%s\\n' \"\$theme_card\" >&2; }"
  "a theme card that is no catalog name is refused"
  "a theme card the catalog lacks goes on to the harness"
  "if [[ \$scene == theme-browser && ! -f \$tree/themes/catalog/\$theme_card/theme.json ]]; then" "if false; then"
  "a theme card the catalog lacks is refused"
  "a catalog mode is looked for in the checkout"
  "-f \$tree/themes/catalog/\${mode#catalog-}/theme.json" "-f \$checkout/themes/catalog/\${mode#catalog-}/theme.json"
  "a revision without a catalog package refuses its mode"
  "a malformed enable list goes on to the harness"
  "refused: enable=%s\\n' \"\$enable_arg\" >&2; exit 2; }" "refused: enable=%s\\n' \"\$enable_arg\" >&2; }"
  "a malformed enable list is refused"
  "an enable id is not looked for in the tree"
  "ships_plugin \"\$id\" || { printf 'sandbox-shots: refused: enable=" "true || { printf 'sandbox-shots: refused: enable="
  "a revision without the polkit plugin refuses enabling it"
)
shots_mutant="$tmp/sandbox-shots-mutant.sh"
for (( i = 0; i < ${#shots_controls[@]}; i += 4 )); do
  label="${shots_controls[i]}"; target="${shots_controls[i + 3]}"
  if [[ -z ${scene_at[$target]+set} ]]; then fail "control: $label names no case: $target"; continue; fi
  args=("${scene_cases[@]:${scene_at[$target]} + 3:${scene_argc[$target]}}")
  if python3 -c '
import sys
src, dst, needle, replacement = sys.argv[1:]
text = open(src).read()
assert text.count(needle) == 1, "the refusal must match once"
open(dst, "w").write(text.replace(needle, replacement))' "$repo/scripts/sandbox-shots.sh" "$shots_mutant" "${shots_controls[i + 1]}" "${shots_controls[i + 2]}"; then
    if scene_case "$shots_mutant" "control: $label" 77 "qml-smoke: status=not-measured" "${args[@]}"; then ok "control: $label"; else fail "control: $label did not take '$target' on to the harness"; fi
  else
    fail "control: $label could not be planted"
  fi
done
# A fence that reaped a root before it could not make its namespace prints
# cleanup lines before its not-measured line. A stand-in for the script
# prints both and exits 77; run in a subshell, scene_case must end it with
# the suite's not-measured line naming the fence's. The control plants the
# old skip, which took the cleanup line for the script's.
fence_stand_in="$tmp/fence-cleanup-first.sh"
printf '%s\n' 'echo "gpu-fence: cleanup=reaped path=/x" >&2' 'echo "gpu-fence: status=not-measured reason=bwrap-missing" >&2' 'exit 77' >"$fence_stand_in"
# cleanup_first SKIP: true when scene_case, skipping SKIP, exits 77 with the
# fence's not-measured line.
cleanup_first() {
  local said status=0
  said="$(scene_skip="$1"; scene_case "$fence_stand_in" "a fence's cleanup line" 77 "qml-smoke: status=not-measured")" || status=$?
  [[ $status -eq 77 && $said == "test-sandbox-shots: status=not-measured gpu-fence: status=not-measured reason=bwrap-missing" ]]
}
if cleanup_first "$scene_skip"; then
  ok "a fence's not-measured line after its cleanup lines ends the scene cases unmeasured"
else
  fail "a fence's not-measured line after its cleanup lines ends the scene cases unmeasured"
fi
if cleanup_first '^gpu-fence: \(absent\|present\) path='; then
  fail "control: a skip that keeps cleanup lines still found the fence's not-measured line"
else
  ok "control: a skip that keeps cleanup lines misses the fence's not-measured line"
fi

# The Gallery title comes from the tree in the sandbox. Read the same
# helper block without starting the harness, against old and current
# snapshot fixtures. A fixed title must fail one of these readings.
gallery_reader="$tmp/gallery-reader.sh"
python3 - "$repo/scripts/sandbox-shots.sh" "$gallery_reader" <<'PY'
import sys
text = open(sys.argv[1]).read()
start = text.index('summoned_kind() {')
end = text.index('settings_kind=panel', start)
open(sys.argv[2], 'w').write(text[start:end])
PY
gallery_title_case() { # READER
  local reader="$1" root="$tmp/gallery-title" title surface
  mkdir -p "$root/shell/plugins/vgs.gallery"
  for title in Gallery 'VGS Components'; do
    python3 - "$root/shell/plugins/vgs.gallery/manifest.json" "$title" <<'PY'
import json, sys
with open(sys.argv[1], 'w') as out:
    json.dump({'name': sys.argv[2], 'kinds': ['window']}, out)
PY
    surface="$(env -i PATH="$PATH" bash -c 'set -euo pipefail; tree="$1"; fail() { exit 1; }; source "$2"; printf "%s" "$gallery_surface"' _ "$root" "$reader")" || return 1
    [[ $surface == "window:$title" ]] || return 1
  done
}
if gallery_title_case "$gallery_reader"; then ok "Gallery reads the title of each snapshot"; else fail "Gallery reads the title of each snapshot"; fi
gallery_mutant="$tmp/gallery-fixed-title.sh"
if python3 - "$gallery_reader" "$gallery_mutant" <<'PY'
import sys
text = open(sys.argv[1]).read()
needle = 'gallery_surface="$(summoned_surface "$gallery_kind" "$gallery_name")"'
assert text.count(needle) == 1, 'the title control must match once'
open(sys.argv[2], 'w').write(text.replace(needle, 'gallery_surface="$(summoned_surface "$gallery_kind" "VGS Components")"'))
PY
then
  if gallery_title_case "$gallery_mutant"; then fail "control: a fixed Gallery title stayed green"; else ok "control: a fixed Gallery title fails an older snapshot"; fi
else
  fail "control: a fixed Gallery title could not be planted"
fi

# A current revision exports its runtime helpers in bin/lib, its Jarvis base
# package and its installer files. The harness copies this revision's product
# files and this checkout's smoke scripts, without starting a compositor.
helper_repo="$tmp/helper-repo"
mkdir -p "$helper_repo/bin/lib" "$helper_repo/shell" "$helper_repo/config" "$helper_repo/themes" "$helper_repo/packaging/jarvis-home"
mkdir -p "$helper_repo/themes/targets"
: >"$helper_repo/themes/targets/fixture"
printf 'revision persona\n' >"$helper_repo/packaging/jarvis-home/persona.md"
printf 'module.exports = { where: "bin/lib" };\n' >"$helper_repo/bin/lib/qml-library.js"
printf 'process.stdout.write(require(require("path").join(__dirname, "lib", "qml-library.js")).where);\n' >"$helper_repo/bin/judge"
: >"$helper_repo/shell/shell.qml"; : >"$helper_repo/config/shell.json"; : >"$helper_repo/themes/.keep"
for file in VERSION LICENSE README.md; do printf 'revision %s\n' "$file" >"$helper_repo/$file"; done
printf '9.9.9\n' >"$helper_repo/VERSION"
cp -- "$repo/bin/lib/engine.js" "$helper_repo/bin/lib/engine.js"
mkdir -p "$tmp/managed-engine/bin"
: >"$tmp/managed-engine/bin/qs"
helper_git() { git -C "$helper_repo" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@" >/dev/null; }
helper_git init -q
helper_git add -A
helper_git commit -q -m product
product_rev="$(git -C "$helper_repo" rev-parse HEAD)"
harness_copy_case() { # LIB
  local lib="$1" dir target out status=0
  dir="$tmp/harness-export"; target="$tmp/harness-copy"
  rm -rf -- "${dir:?}" "${target:?}"
  mkdir -p -- "$dir" "$target"
  out="$({
    source "$lib"
    tree_export "$helper_repo" "$product_rev" "$dir" || { echo "tree_export failed"; exit 1; }
    rm -- "$dir/README.md" "$dir/LICENSE"
    mkdir -- "$dir/.engines"
    ln -s -- "$tmp/managed-engine" "$dir/.engines/git-original-identity"
    chmod -R a-w -- "$dir"
    tree_harness_copy "$repo" "$target" "$dir"
    printf 'observer edit\n' >>"$target/shell/shell.qml" || { echo "sandbox copy is not writable"; exit 1; }
    rm -r -- "$target/themes/targets" || { echo "sandbox copied directory is not removable"; exit 1; }
    [[ ! -s $dir/shell/shell.qml && ! -w $dir/shell/shell.qml && ! -w $dir/themes/targets ]] || { echo "read-only input changed"; exit 1; }
    tree_harness_engine "$dir" "$target" "$target/data"
    [[ $(readlink -f -- "$target/data/vgshell/.engines/release-9.9.9") == "$tmp/managed-engine" ]] || { echo "managed engine not restored"; exit 1; }
    [[ -e "$target/packaging/install-system.sh" ]] || { echo "packaging missing"; exit 1; }
    [[ -e "$target/scripts/qml-smoke.sh" ]] || { echo "scripts missing"; exit 1; }
    [[ $(node "$target/bin/judge") == bin/lib ]] || { echo "runtime helper missing"; exit 1; }
    cmp -s -- "$helper_repo/packaging/jarvis-home/persona.md" "$target/packaging/jarvis-home/persona.md" || { echo "revision base package missing"; exit 1; }
    cmp -s -- "$helper_repo/VERSION" "$target/VERSION" || { echo "revision version missing"; exit 1; }
    for file in LICENSE README.md; do
      cmp -s -- "$repo/$file" "$target/$file" || { echo "checkout documentation missing: $file"; exit 1; }
    done
    echo ok
  } 2>&1)" || status=$?
  # These are this case's exclusively owned disposable fixtures. Restore
  # their write bits only after the source-preservation assertions.
  chmod -R u+w -- "$dir" "$target" || return 1
  [[ $status -eq 0 && $out == ok ]] && return 0
  echo "exit=$status out=$(head -n 1 <<<"$out")"
  return 1
}
if harness_copy_case "$repo/scripts/smoke/tree.sh"; then ok "the harness copies the revision's product and current smoke scripts"; else fail "the harness copies the revision's product and current smoke scripts"; fi
# A control copies the checkout's version instead of the tested tree's.
copy_mutant="$tmp/tree-copy-mutant.sh"
if python3 - "$repo/scripts/smoke/tree.sh" "$copy_mutant" <<'PYCONTROL'
import sys
src, dst = sys.argv[1:]
text = open(src).read()
needle = 'origin = (tree if file_name == "VERSION" else source) / file_name'
assert text.count(needle) == 1, "installer file source must match once"
open(dst, "w").write(text.replace(needle, 'origin = source / file_name'))
PYCONTROL
then
  if harness_copy_case "$copy_mutant" >/dev/null; then fail "control: wrong revision installer files stayed green"; else ok "control: wrong revision installer files fail"; fi
else
  fail "control: wrong revision installer files could not be planted"
fi
# A control exports no base package, and one copies the checkout's.
package_controls=(
  'read-only sandbox copy|owned.chmod(mode | stat.S_IWUSR)|pass'
  'managed engine under the wrong identity|ln -s -- "$engine" "$root"|ln -s -- "$engine" "$root.wrong"'
  'a revision exported without its base package|package+=("$at")|:'
  'the checkout base package|shutil.copytree(tree / package, target / package)|shutil.copytree(source / package, target / package)'
)
for spec in "${package_controls[@]}"; do
  IFS='|' read -r label needle replacement <<<"$spec"
  if ! mutate "$repo/scripts/smoke/tree.sh" "$needle" "$replacement" "$copy_mutant"; then
    fail "control: $label could not be planted"
  elif harness_copy_case "$copy_mutant" >/dev/null; then
    fail "control: $label stayed green"
  else
    ok "control: $label fails"
  fi
done

# With --rev, a shot's catalog package is the revision's: preview_package
# and set_mode read the sandbox copy the harness made, which outlives the
# export it came from. A scratch repository commits REV's package values
# and its working tree, the checkout, holds others; the real functions run
# against the sandbox copy after the export is removed, without a harness.
catalog_repo="$tmp/catalog-repo"
mkdir -p "$catalog_repo/shell" "$catalog_repo/bin" "$catalog_repo/config" \
  "$catalog_repo/themes/catalog/demo/targets/ghostty" "$catalog_repo/themes/catalog/flexoki-light"
: >"$catalog_repo/shell/shell.qml"; : >"$catalog_repo/bin/vgshell"; : >"$catalog_repo/config/shell.json"
for file in VERSION LICENSE README.md; do printf '%s\n' "$file" >"$catalog_repo/$file"; done
# catalog_plant VALUE: every catalog file the shot reads holds VALUE.
catalog_plant() {
  printf '{"name": "demo", "value": "%s"}\n' "$1" >"$catalog_repo/themes/catalog/demo/theme.json"
  printf '{"background": "%s"}\n' "$1" >"$catalog_repo/themes/catalog/demo/terminal.json"
  printf '%s\n' "$1" >"$catalog_repo/themes/catalog/demo/targets/ghostty/theme"
  printf '{"name": "flexoki-light", "value": "%s"}\n' "$1" >"$catalog_repo/themes/catalog/flexoki-light/theme.json"
}
catalog_plant rev
catalog_git() { git -C "$catalog_repo" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@" >/dev/null; }
catalog_git init -q
catalog_git add -A
catalog_git commit -q -m rev
catalog_rev="$(git -C "$catalog_repo" rev-parse HEAD)"
catalog_plant checkout
catalog_export="$tmp/catalog-export"; catalog_sandbox="$tmp/catalog-sandbox"
mkdir -p -- "$catalog_export" "$catalog_sandbox"
(
  source "$repo/scripts/smoke/tree.sh"
  tree_export "$catalog_repo" "$catalog_rev" "$catalog_export" &&
  tree_harness_copy "$repo" "$catalog_sandbox" "$catalog_export"
) || fail "the catalog revision could not be exported and copied"
rm -rf -- "${catalog_export:?}"
printf 'wallpaper\n' >"$tmp/catalog-wallpaper.png"
# catalog_extract NAME FILE: the body of the function NAME in sandbox-shots.sh.
catalog_extract() {
  python3 - "$repo/scripts/sandbox-shots.sh" "$1" "$2" <<'PY'
import sys
src, name, dst = sys.argv[1:]
text = open(src).read()
start_marker = name + "() {"
assert text.count(start_marker) == 1, name + " must be defined once"
start = text.index(start_marker)
end = text.index("\n}\n", start) + 3
open(dst, "w").write(text[start:end])
PY
}
# catalog_mutant SRC DST COUNT NEEDLE: SRC with its COUNT reads of NEEDLE
# pointed back at the checkout's catalog.
catalog_mutant() {
  python3 - "$@" <<'PY'
import sys
src, dst, count, needle = sys.argv[1:]
text = open(src).read()
assert text.count(needle) == int(count), "catalog reads must match %s times" % count
changed = text.replace(needle, needle.replace("$repo/", "$checkout/"))
assert changed != text
open(dst, "w").write(changed)
PY
}
# catalog_run FUNCTIONS SCRIPT: SCRIPT in a clean bash with the extracted
# FUNCTIONS, repo the sandbox copy and checkout the scratch working tree.
catalog_run() {
  local home
  home="$(mktemp -d "$tmp/catalog-home.XXXXXX")" || return 1
  env -i PATH="$PATH" "$BASH" -c '
    set -euo pipefail
    repo="$1" checkout="$2" home="$3"
    declare -A preview_wallpaper=([demo]="$4")
    theme_file="$home/.config/vgshell/theme.json"
    mkdir -p -- "$home/.config/vgshell"
    expect_poll() { :; }
    theme_idle() { echo idle; }
    source "$5"
    eval "$6"
  ' _ "$catalog_sandbox" "$catalog_repo" "$home" "$tmp/catalog-wallpaper.png" "$1" "$2"
}
# preview_case FUNCTIONS: the installed demo package holds REV's values.
preview_case() {
  catalog_run "$1" '
    preview_package demo
    dest="$home/.config/vgshell/themes/demo"
    [[ $(<"$dest/terminal.json") == "{\"background\": \"rev\"}" ]]
    [[ $(<"$dest/theme.json") == "{\"name\": \"demo\", \"value\": \"rev\"}" ]]
    [[ $(<"$dest/targets/ghostty/theme") == rev ]]
  '
}
# mode_case FUNCTIONS MODE NAME: MODE publishes REV's theme.json of NAME.
mode_case() {
  catalog_run "$1" "set_mode $2; [[ \$(<\"\$theme_file\") == '{\"name\": \"$3\", \"value\": \"rev\"}' ]]"
}
preview_reader="$tmp/preview-package.sh"
mode_reader="$tmp/set-mode.sh"
catalog_extract preview_package "$preview_reader"
catalog_extract set_mode "$mode_reader"
catalog_extract capture_mode_name "$tmp/mode-name.sh"
cat -- "$tmp/mode-name.sh" >>"$mode_reader"
if preview_case "$preview_reader"; then ok "a revision's preview package holds its catalog values"; else fail "a revision's preview package holds its catalog values"; fi
if mode_case "$mode_reader" catalog-demo demo; then ok "a revision's catalog mode holds its catalog values"; else fail "a revision's catalog mode holds its catalog values"; fi
if mode_case "$mode_reader" light flexoki-light; then ok "a revision's light mode holds its catalog values"; else fail "a revision's light mode holds its catalog values"; fi
catalog_controls=(
  "preview package reads the checkout's catalog|$preview_reader|5|\$repo/themes/catalog|preview_case|"
  "catalog mode reads the checkout's catalog|$mode_reader|1|\"\$repo/themes/catalog/\$name/theme.json\"|mode_case|catalog-demo demo"
  "light mode reads the checkout's catalog|$mode_reader|1|\"\$repo/themes/catalog/\$name/theme.json\"|mode_case|light flexoki-light"
)
for spec in "${catalog_controls[@]}"; do
  IFS='|' read -r label reader count needle check check_args <<<"$spec"
  catalog_mutant_file="$tmp/catalog-mutant.sh"
  read -r -a check_args <<<"$check_args"
  if ! catalog_mutant "$reader" "$catalog_mutant_file" "$count" "$needle"; then
    fail "control: $label could not be planted"
  elif "$check" "$catalog_mutant_file" "${check_args[@]}"; then
    fail "control: $label stayed green"
  else
    ok "control: $label"
  fi
done

# The same observer setup instruments a source copy and an installed copy.
# Drive its actual file edits without starting QML or a compositor.
observer_case() {
  local tree_helper="$1" target count
  target="$(mktemp -d "$tmp/observer.XXXXXX")" || return 1
  mkdir -p "$target/shell/Core" "$target/shell/Hosts" &&
  cp -- "$repo/shell/shell.qml" "$target/shell/shell.qml" &&
  cp -- "$repo/shell/Core/Config.qml" "$target/shell/Core/Config.qml" &&
  cp -- "$repo/shell/Hosts/BackgroundHost.qml" "$target/shell/Hosts/BackgroundHost.qml" &&
  env -i PATH="/usr/bin:/bin" HOME="$tmp" "$BASH" -c '
    set -euo pipefail
    source "$1"
    tree_smoke_observer "$2" "$3"
  ' _ "$tree_helper" "$repo" "$target" &&
  cmp -s -- "$repo/scripts/smoke/Probe.qml" "$target/shell/Probe.qml" || return 1
  count="$(grep -Fc '    Probe {}' "$target/shell/shell.qml")" || return 1
  [[ $count == 1 ]] || return 1
  count="$(grep -Fc 'property alias smokeUserView: userView' "$target/shell/Core/Config.qml")" || return 1
  [[ $count == 1 ]] || return 1
  count="$(grep -Fc 'onBrokenKeysChanged: console.info("smoke: backgroundFailures="' "$target/shell/Hosts/BackgroundHost.qml")" || return 1
  [[ $count == 1 ]]
}
if observer_case "$repo/scripts/smoke/tree.sh"; then
  ok "the shared observer instruments a disposable runtime tree"
else
  fail "the shared observer instruments a disposable runtime tree"
fi
observer_controls=(
  'the root gets no probe|    Probe {}|    QtObject {}'
  'the user view gets no readable alias|property alias smokeUserView:|property alias unusedUserView:'
  'background failures get no observer|onBrokenKeysChanged:|onParentChanged:'
)
for spec in "${observer_controls[@]}"; do
  IFS='|' read -r label needle replacement <<<"$spec"
  observer_mutant="$tmp/observer-mutant.sh"
  if ! mutate "$repo/scripts/smoke/tree.sh" "$needle" "$replacement" "$observer_mutant"; then
    fail "control: $label could not be planted"
  elif observer_case "$observer_mutant" >/dev/null; then
    fail "control: $label left the observer setup green"
  else
    ok "control: $label"
  fi
done

# The harness names a missing ImageMagick among its prerequisites, since the
# notifications row and the Slack scene draw converted emoji: with no tool
# on PATH its not-measured line lists magick, and a copy without the check
# leaves it out.
# harness_missing HARNESS: the harness's missing list with an empty PATH.
harness_missing() {
  local out status=0
  out="$(env -i PATH="$tmp/no-tools" HOME="$tmp" "$BASH" -c 'repo="$1"; source "$2"' _ "$repo" "$1" 2>/dev/null)" || status=$?
  [[ $status -eq 77 ]] || { echo "exit=$status"; return; }
  sed -n 's/^qml-smoke: status=not-measured missing=//p' <<<"$out"
}
mkdir -p "$tmp/no-tools"
has_magick() { tr ',' '\n' <<<"$1" | grep -qx magick; }
got="$(harness_missing "$repo/scripts/smoke/harness.sh")"
if has_magick "$got"; then ok "the harness names a missing ImageMagick"; else fail "the harness names a missing ImageMagick: got $got"; fi
harness_mutant="$tmp/harness-mutant.sh"
needle='|| missing+=("magick")'
if [[ $(grep -cF -- "$needle" "$repo/scripts/smoke/harness.sh") -eq 1 ]]; then
  text="$(<"$repo/scripts/smoke/harness.sh")"
  printf '%s\n' "${text/"$needle"/|| true}" >"$harness_mutant"
  got="$(harness_missing "$harness_mutant")"
  if has_magick "$got"; then fail "control: a harness without the ImageMagick check still names it"; else ok "control: a harness without the ImageMagick check leaves it out"; fi
else
  fail "control: the ImageMagick check could not be planted"
fi

# Drive scene ownership through the real functions, with a failed theme
# operation, an initially disabled notification service and duplicate bottom
# views. These callbacks model the scene's external producers, not its cleanup.
if python3 - "$repo" "$tmp" "$BASH" <<'PYSCENES'
from pathlib import Path
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

repo, scratch, bash = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
source = (repo / 'scripts/sandbox-shots.sh').read_text()
harness = (repo / 'scripts/smoke/harness.sh').read_text()
devices = (repo / 'scripts/smoke/devices.sh').read_text()
registry = re.search(r'(?m)^device_stand_in_names=\([^)]*\)', devices).group()

def functions(text, names):
    result = []
    for name in names:
        marker = name + '() {'
        if marker not in text:
            assert name == 'dictation_setup_capture', name
            continue
        assert text.count(marker) == 1, name
        start = text.index(marker)
        result.append(text[start:text.index('\n}\n', start) + 3])
    return '\n'.join(result)

def run_case(text, case):
    world = Path(tempfile.mkdtemp(prefix='capture-scenes-', dir=scratch))
    environment = {'PATH': os.environ['PATH'], 'LC_ALL': 'C'}
    if case.startswith('dictation-'):
        for directory in ('repo/bin', 'repo/themes/targets/chromium', 'repo/scripts/smoke/fixtures', 'home', 'shim', 'sandbox', 'devices'):
            (world / directory).mkdir(parents=True)
        daemon = world / 'repo/bin/vgshell-dictation'
        daemon.write_text('#!/bin/sh\nexit 99\n'); daemon.chmod(0o755)
        (world / 'repo/themes/targets/chromium/owner').write_text('other scene\n')
        shutil.copytree(repo / 'scripts/smoke/fixtures/voxtype', world / 'repo/scripts/smoke/fixtures/voxtype')
        shutil.copytree(repo / 'themes/targets/gum', world / 'targets/gum')
        body = r'''
repo="$world/repo" home="$world/home" shim="$world/shim" sandbox="$world/sandbox"
fixtures="$original/scripts/smoke/fixtures/plugins" fixture_targets="$world/targets"
devices_dir="$world/devices" devices_fixtures="$original/scripts/smoke/fixtures/devices"
tui_terminal="$world/terminal" tui_self="$world/presenter" core_vgshell="$world/vgshell" settings_kind=window
devices_write_stand_ins
cp -p -- "$shim/gum" "$world/original-gum"
case $scenario in
  *-symlink) mv -- "$shim/gum" "$world/gum-target"; ln -s ../gum-target "$shim/gum" ;;
  *-dangling) rm -- "$shim/gum"; ln -s missing-gum "$shim/gum" ;;
  *-absent) rm -- "$shim/gum" ;;
esac
failures=0
kitty() { :; }
gum() { :; }
rescan() { :; }
set_mode() { :; }
shell_resolves() { echo "$shim/$1"; }
record_exists() { :; }
expect_poll() { :; }
close_notices() { :; }
fail() { failures=$((failures + 1)); }
expect() { local label="$1" want="$2" got; shift 2; got="$("$@")"; [[ $got == "$want" ]]; }
ipc() {
  if [[ $* == 'shell setPluginEnabled acme.dictation true' ]]; then : >"$world/holder";
  elif [[ $* == 'shell setPluginEnabled acme.dictation false' ]]; then rm -f -- "$world/holder";
  elif [[ $* == 'smoke themeName' ]]; then
    [[ $scenario != dictation-theme-name ]] || return 1
    echo vgs; return
  elif [[ $* == 'smoke themeValue color.background' ]]; then echo '"#000000"'; return
  elif [[ $* == 'smoke themeValue color.text' ]]; then echo '"#ffffff"'; return
  fi
  echo ok
}
sandbox_vgshell() {
  : >"$world/apply"
  if [[ ! -f $repo/themes/targets/gum/target.json || -e $repo/themes/targets/chromium ]]; then : >"$world/wrong-targets"; fi
  [[ $scenario != dictation-wrapper-* ]] || return 0
  return 1
}
terminal_stand_in() { : >"$world/terminal-restored"; }
voice_setup_launcher_ready() { :; }
settings_setup() {
  ! cmp -s -- "$world/original-gum" "$shim/gum" || return 1
  : >"$world/wrapper-reached"
  return 1
}
settings_count() { :; }
scene_dictation-setup dark
[[ $failures -gt 0 && ! -e $world/holder && -e $world/terminal-restored ]]
[[ ! -e $shim/voxtype && ! -e $shim/wtype ]]
case $scenario in
  *-symlink) [[ -L $shim/gum && $(readlink -- "$shim/gum") == ../gum-target ]]; cmp -s -- "$world/original-gum" "$world/gum-target" ;;
  *-dangling) [[ -L $shim/gum && ! -e $shim/gum && $(readlink -- "$shim/gum") == missing-gum ]] ;;
  *-absent) [[ ! -e $shim/gum && ! -L $shim/gum ]] ;;
  *) [[ -f $shim/gum && -x $shim/gum && ! -L $shim/gum ]]; cmp -s -- "$world/original-gum" "$shim/gum" ;;
esac
[[ $(<"$repo/themes/targets/chromium/owner") == 'other scene' && ! -e $repo/themes/targets/gum ]]
[[ ! -e $world/wrong-targets ]]
[[ $scenario == dictation-theme-name || -e $world/apply ]]
[[ $scenario != dictation-wrapper-* || -e $world/wrapper-reached ]]
'''
        code = functions(devices, ('devices_write_stand_ins',)) + '\n' + registry + '\n' + functions(text, ('scene_dictation-setup', 'dictation_setup_capture', 'shots_baseline_safety'))
        expected = 0
    elif case == 'notifications-light':
        body = r'''
notes_on() { : >"$world/notifications-enabled"; }
notify() { [[ -e $world/notifications-enabled ]] || exit 88; exit 42; }
scene_notifications light
'''
        code = functions(text, ('scene_notifications',))
        expected = 42  # The first notification reaches an enabled service.
    else:
        context = {'home': world / 'home', 'tree': world / 'tree', 'repo': world / 'tree',
                   'rt_dir': world / 'runtime', 'power_sleep_replies': world / 'replies',
                   'power_profiles_pid': 'fixture'}
        for directory in (context['home'] / '.config/vgshell/plugins', context['tree'] / 'shell/plugins/vgs.power',
                          context['rt_dir'], context['power_sleep_replies']):
            directory.mkdir(parents=True)
        (context['tree'] / 'shell/plugins/vgs.power/manifest.json').write_text('{"wakeOnLan":true}\n')
        body = '\n'.join(name + '=' + shlex.quote(str(value)) for name, value in context.items()) + r'''
hovered=no
fail() { exit 1; }
power_stage_owners() { :; }
tree_rescan() { :; }
expect() { :; }
expect_poll() { :; }
ipc() { echo 477.90625; }
power_revealed() { [[ $1 == 477.90625 ]]; }
park_pointer() { hovered=no; }
power_shot_pane_pages() { :; }
point_item() {
  [[ $# == 7 && $1 == 'scoped:System Settings' && $2 == window && $3 == vgs.power && $4 == Field && $5 == 'Wake on LAN' && $6 == Switch && -z $7 ]] || return 1
  hovered=yes
}
take() { [[ $1 != power-dark-pane-wake ]] || { park_pointer; [[ $hovered == yes ]]; }; }
take_posed() { [[ $1 != power-dark-pane-wake ]] || { [[ $hovered == yes ]]; : >"$world/wake-captured"; }; }
device_reply() { :; }
click_scoped_in() { :; }
power_stage_setting() { :; }
power_stop_mock() { :; }
power_shot_pages() { :; }
power_start_profiles() { :; }
settings_close() { :; }
power_shot_pane dark
[[ -e $world/wake-captured ]]
'''
        code = functions(text, ('power_shot_pane',))
        expected = 0
    runner = world / 'case.sh'
    runner.write_text('set -euo pipefail\nworld=$1 original=$2 scenario=$3\n' + code + '\n' + body)
    result = subprocess.run([bash, str(runner), str(world), str(repo), case],
                            env=environment, text=True, capture_output=True, timeout=20)
    return result.returncode == expected, (case, result.returncode, result.stderr)

cases = ('dictation-apply', 'dictation-theme-name', 'dictation-wrapper-file', 'dictation-wrapper-symlink',
         'dictation-wrapper-dangling', 'dictation-apply-absent', 'notifications-light', 'power-wake')
for case in cases:
    passed, detail = run_case(source, case)
    assert passed, detail

controls = (
    ('dictation-targets', 'dictation-apply',
     '    dictation_setup_capture "$mode" "$phase" "$key" "$holder"',
     '    cp -R -- "$target_store/targets/chromium" "$repo/themes/targets/chromium"\n    dictation_setup_capture "$mode" "$phase" "$key" "$holder"'),
    ('dictation-holder', 'dictation-apply',
     '  expect "the setup holder disables" ok ipc shell setPluginEnabled "$holder" false', '  :'),
    ('dictation-gum-restore', 'dictation-wrapper-file',
     '    mv -- "$target_store/gum" "$shim/gum"',
     '    if false; then mv -- "$target_store/gum" "$shim/gum"; else rm -f -- "$target_store/gum"; fi'),
    ('notifications-enable', 'notifications-light', '  notes_on "Notifications shots"', '  :'),
    ('power-posed', 'power-wake', '      take_posed "power-$1-pane-wake"', '      take "power-$1-pane-wake"'),
)
for name, case, before, after in controls:
    assert source.count(before) == 1, name
    passed, detail = run_case(source.replace(before, after), case)
    assert not passed, (name, 'control stayed green', detail)

# Power's section shots over a modelled content scroll: revealText puts a
# field a third of the way down the view, clamped, as Probe.qml's revealIn
# does. The view is 590 px and the after section 1182 px with "Sleep after"
# at 483, read off the VGS-2033 after run's 1920x1080 power-dark-pane frames;
# the rows are a section two frames cover, that after section, one too tall
# for three frames and a middle field that leaves a gap below the top frame.
def pages_case(text, content, sleep_after):
    world = Path(tempfile.mkdtemp(prefix='power-pages-', dir=scratch))
    body = r'''
height=590 content=$1 sleep_after=$2
echo 0 >"$world/y"
py_reply() { python3 -c "$@"; }
take() { echo "$1" >>"$world/shots"; }
fail() { echo "$1" >>"$world/failures"; }
expect_poll() { local label="$1" want="$2"; shift 2; [[ $("$@") == "$want" ]] || fail "$label"; }
ipc() {
  local at
  case "$2 ${6-}" in
    "revealText Dim") at=0 ;;
    "revealText Sleep after") at=$sleep_after ;;
    "revealText Wake sources") at=$content ;;
    "viewHolding ") printf '{"contentY": %s, "contentHeight": %s, "height": %s}\n' "$(<"$world/y")" "$content" "$height"; return ;;
    *) return 1 ;;
  esac
  python3 -c 'import sys; at,ch,h=map(float,sys.argv[1:]); print(max(0,min(at-h/3,ch-h)))' "$at" "$content" "$height" | tee "$world/y"
}
power_shot_pane_pages power-dark-pane
'''
    runner = world / 'case.sh'
    runner.write_text('set -euo pipefail\nworld=$3 sandbox=$3 tree=$3\nsource "$4/scripts/smoke/power-fakes.sh"\n'
                      + functions(text, ('power_shot_pane_pages', 'power_shot_pane_coverage')) + '\n' + body)
    subprocess.run([bash, str(runner), str(content), str(sleep_after), str(world), str(repo)],
                   env={'PATH': os.environ['PATH'], 'LC_ALL': 'C'}, check=True, timeout=20)
    read = lambda name: (world / name).read_text().split('\n')[:-1] if (world / name).exists() else []
    return read('shots'), bool(read('failures'))

pages_rows = (
    ('before', 1100, 483, ['power-dark-pane', 'power-dark-pane-end'], False),
    ('after', 1182, 483, ['power-dark-pane', 'power-dark-pane-middle', 'power-dark-pane-end'], False),
    ('too-tall', 1800, 483, ['power-dark-pane', 'power-dark-pane-middle', 'power-dark-pane-end'], True),
    ('middle-gap', 1182, 900, ['power-dark-pane', 'power-dark-pane-middle', 'power-dark-pane-end'], True),
)
for name, content, sleep_after, shots, failed in pages_rows:
    assert pages_case(source, content, sleep_after) == (shots, failed), name

pages_controls = (
    ('end-from-top', 'after', '"end": y+h+1>=ch and y<=at+h-40', '"end": y+h+1>=ch and y<=h-40'),
    ('next-unchecked', 'middle-gap', '"next": at<y<=at+h-40', '"next": True'),
)
for name, row, before, after in pages_controls:
    assert source.count(before) == 1, name
    _, content, sleep_after, shots, failed = next(r for r in pages_rows if r[0] == row)
    assert pages_case(source.replace(before, after), content, sleep_after) != (shots, failed), (name, 'control stayed green')

# A scan's follow uses the real judge and its applied.json, not a model of
# package/digest rules. Dictation removes targets before its rescan; the
# prior dark apply must not replace the requested mode at the terminal.
def mode_case(text, mode, want, mismatch=''):
    world = Path(tempfile.mkdtemp(prefix='capture-mode-', dir=scratch))
    files = ('bin/vgshell-theme-judge', 'bin/lib/qml-library.js', 'bin/lib/judge-files.js',
             'bin/lib/theme-render.js', 'bin/lib/theme-backgrounds.js', 'bin/lib/theme-select.js',
             'bin/lib/theme-catalog.js', 'bin/lib/account-folders.js', 'bin/lib/anchored.js',
             'shell/Commons/ThemeLogic.js', 'shell/Commons/Tokens.js', 'shell/Commons/AccountDirectories.js', 'shell/Commons/Glass.js',
             'shell/Core/ConfigLogic.js', 'shell/Core/PackageManagers.js')
    for file in files:
        dest = world / 'repo' / file
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(repo / file, dest)
    for directory in ('home/.config/vgshell', 'home/.local/state/vgshell', 'shim', 'sandbox',
                      'repo/config', 'repo/themes/targets', 'repo/bin'):
        (world / directory).mkdir(parents=True, exist_ok=True)
    terminal = {'schemaVersion': 1, 'slots': {'color'+str(i): '#222222' for i in range(16)}}
    for name, directory in (('vgs', 'repo/themes/vgs'), ('flexoki-light', 'repo/themes/catalog/flexoki-light'),
                            ('demo', 'repo/themes/catalog/demo')):
        package = world / directory
        package.mkdir(parents=True)
        (package / 'theme.json').write_text(json.dumps({'schemaVersion': 1, 'name': name, 'tokens': {}}))
        (package / 'terminal.json').write_text(json.dumps(terminal))
    (world / 'repo/config/shell.json').write_text('{}')
    shutil.copytree(repo / 'themes/targets/gum', world / 'repo/themes/targets/gum')
    shutil.copytree(repo / 'themes/targets/gum', world / 'targets/gum')
    shutil.copytree(repo / 'scripts/smoke/fixtures/voxtype', world / 'repo/scripts/smoke/fixtures/voxtype')
    (world / 'repo/bin/vgshell-dictation').touch(mode=0o755)
    code = functions(text, ('shots_baseline_safety', 'capture_mode_name', 'capture_theme_check', 'set_mode',
                            'scene_dictation-setup', 'dictation_setup_capture',
                            'clone_terminal_on',
                            'capture_state_record', 'page_state_record'))
    runner = world / 'case.sh'
    runner.write_text('set -euo pipefail\nworld=$1 original=$2 mode=$3 want=$4 mismatch=$5 node_bin=$6\n' + code + r'''
repo="$world/repo" home="$world/home" shim="$world/shim" sandbox="$world/sandbox"
fixtures="$original/scripts/smoke/fixtures/plugins" fixture_targets="$world/targets"
tui_terminal="$world/terminal" tui_self="$world/presenter" core_vgshell="$world/vgshell" settings_kind=window
theme_file="$home/.config/vgshell/theme.json" theme_state_dir="$home/.local/state/vgshell"
SHOT_DIR="$world" capture_source=fixture enable_ids=() disable_ids=()
failures=0
fail() { failures=$((failures + 1)); }
judge() {
  local verb="$1"; shift
  env -i PATH="$PATH" HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" TMPDIR="$world" VGS_TEST_RUN=1 \
    "$node_bin" "$repo/bin/vgshell-theme-judge" "$verb" json "$home/.config/vgshell" "$theme_state_dir" held "$@"
}
exec 9>>"$home/.config/vgshell/theme.lock"
flock 9
judge apply vgs >"$world/dark-apply.json"
rescan() { judge follow >"$world/follow.json"; }
theme_idle() { rescan; echo idle; }
ipc() {
  case "$*" in
    'smoke themeName') python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$theme_file"; return ;;
    'smoke themeValue color.background') [[ $mismatch != clone ]] || exit 42; echo '"#000000"'; return ;;
    'smoke themeValue color.text') [[ $mismatch != clone ]] || exit 42; echo '"#ffffff"'; return ;;
    'shell listPlugins') echo '{"plugins":[{"id":"vgs.voice","enabled":true,"kinds":["service"],"requirements":[]}]}'; return ;;
    'smoke readInstance window vgs.settings plugins') echo '[{"id":"vgs.voice","enabled":true,"kinds":["service"],"settings":{},"settingChoices":{},"status":[],"requirements":[],"errors":[]}]'; return ;;
  esac
  echo ok
}
expect() { local label="$1" want="$2" got; shift 2; got="$("$@")" && [[ $got == "$want" ]]; }
expect_poll() { [[ $1 != *'theme ('* ]] || expect "$@"; }
kitty() { :; }
gum() { :; }
shell_resolves() { echo "$shim/$1"; }
record_exists() { :; }
close_notices() { :; }
sandbox_vgshell() { [[ $1 == theme && $2 == apply ]]; judge apply "$3"; }
terminal_stand_in() { :; }
voice_setup_launcher_ready() { :; }
settings_count() { echo 1; }
settings_setup() {
  [[ $(ipc smoke themeName) == "$want" ]] || return 99
  python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["name"]==sys.argv[2]' "$theme_state_dir/applied.json" "$want"
  : >"$world/terminal-theme-correct"
  return 1
}
py_reply() { python3 -c "$@"; }
set_mode "$mode"
if [[ $mismatch == clone ]]; then
  printf '\n' >>"$repo/themes/targets/gum/gum.env"
  rescan
  clone_terminal_on kitty gum "$mode"
  exit 93
fi
scene_dictation-setup "$mode"
[[ $failures == 1 && -f $world/terminal-theme-correct ]]
capture_state_record dictation-setup "$mode"
page_state_record terminal "$mode" vgs.voice
if [[ -n $mismatch ]]; then
  printf '{"schemaVersion":1,"name":"vgs","tokens":{}}\n' >"$theme_file"
  if [[ $mismatch == scene ]]; then
    capture_state_record observe light && exit 91
  else
    page_state_record observe light vgs.voice && exit 92
  fi
  [[ $failures == 2 ]]
fi
''')
    result = subprocess.run([bash, str(runner), str(world), str(repo), mode, want, mismatch, shutil.which('node')],
                            env={'PATH': os.environ['PATH'], 'LC_ALL': 'C'}, text=True, capture_output=True, timeout=20)
    if mismatch == 'clone':
        name = json.loads((world / 'home/.config/vgshell/theme.json').read_text())['name']
        return result.returncode == 42 and name == want, (mode, mismatch, result.returncode, name, result.stderr)
    return result.returncode == 0, (mode, mismatch, result.returncode, result.stderr)

for mode, want in (('dark', 'vgs'), ('light', 'flexoki-light'), ('rounded', 'rounded'), ('catalog-demo', 'demo')):
    passed, detail = mode_case(source, mode, want)
    assert passed, detail
for record in ('scene', 'page'):
    passed, detail = mode_case(source, 'light', 'flexoki-light', record)
    assert passed, detail
    guard = '  [[ $2 == "$want" ]] || { fail "capture-theme: mode=$1 actual=$2 expected=$want"; return 1; }'
    assert source.count(guard) == 1
    passed, detail = mode_case(source.replace(guard, '  [[ $2 == "$want" ]] || true'), 'light', 'flexoki-light', record)
    assert not passed, ('mode mismatch control stayed green', detail)
restore = '  set_mode "$mode" || { fail "dictation-setup: the requested capture mode is not published"; return; }'
assert source.count(restore) == 1
passed, detail = mode_case(source.replace(restore, '  :'), 'light', 'flexoki-light')
assert not passed, ('Dictation follow control stayed green', detail)
passed, detail = mode_case(source, 'light', 'flexoki-light', 'clone')
assert passed, detail
clone_restore = '  set_mode "$3" || return 1'
assert source.count(clone_restore) == 1
passed, detail = mode_case(source.replace(clone_restore, '  :'), 'light', 'flexoki-light', 'clone')
assert not passed, ('clone follow control stayed green', detail)

def tab_case(text, reply, ipc_status, click_status, expected, clicked):
    world = Path(tempfile.mkdtemp(prefix='capture-tabs-', dir=scratch))
    runner = world / 'case.sh'
    runner.write_text('set -euo pipefail\nworld=$1 reply=$2 ipc_status=$3 click_status=$4\n' +
        functions(text, ('settings_tab_click',)) + r'''
ipc() {
  [[ $* == 'smoke revealText window vgs.settings QQuickTabButton Setup' ]] || return 99
  printf '%s\n' "$reply"
  return "$ipc_status"
}
click_item() {
  [[ $* == 'window:Plugins window vgs.settings QQuickTabButton Setup' ]] || return 98
  : >"$world/clicked"
  return "$click_status"
}
settings_tab_click Setup
''')
    result = subprocess.run([bash, str(runner), str(world), reply, str(ipc_status), str(click_status)],
                            env={'PATH': os.environ['PATH'], 'LC_ALL': 'C'}, capture_output=True, timeout=5)
    return result.returncode == expected and (world / 'clicked').exists() == clicked

for case in (('0', 0, 0, 0, True), ('477.90625', 0, 0, 0, True), ('unscrolled', 0, 0, 0, True),
             ('absent', 0, 0, 1, False), ('bad-state', 0, 0, 1, False), ('unscrolled', 69, 0, 1, False),
             ('unscrolled', 0, 1, 1, True)):
    assert tab_case(harness, *case), case
guard = '[[ $shown =~ ^[0-9.]+$ || $shown == unscrolled ]]'
assert harness.count(guard) == 1
assert not tab_case(harness.replace(' || $shown == unscrolled', ''), 'unscrolled', 0, 0, 0, True)
assert not tab_case(harness.replace(guard, guard[:-3] + ' || true ]]'), 'absent', 0, 0, 1, False)
print('capture-scenes: gum-only=true teardown=true gum-restored=true notifications-ready=true wake-hover=true tab-clicks=guarded controls=failed-as-required')
PYSCENES
then ok "capture scenes isolate theme targets, release failed setup, enable Notifications and pose the wake switch"; else fail "capture scene ownership and visible state"; fi

# Drive the Power scene's setup order without starting a sandbox. The
# plugin check must read a scan made after the fake daemon owns its name.
# The tree ships Power's section, whose shots, its page's among them,
# follow the panel's.
power_scene="$tmp/power-scene.sh"
catalog_extract scene_power "$power_scene"
power_tree="$tmp/power-tree"
mkdir -p "$power_tree/shell/plugins/vgs.power"
: >"$power_tree/shell/plugins/vgs.power/Pane.qml"
power_scene_case() { # SCENE [WANT [TREE]]
  local want="${2:-$'power-dark-bar\npower-dark-panel\npower-dark-pane\npower-dark-notice-low\npower-dark-notice-critical\npower-dark-panel-no-battery'}"
  env -i PATH="$PATH" tree="${3:-$power_tree}" "$BASH" -c '
    set -euo pipefail
    source "$1"
    devices_ready() { :; }
    devices_usb_wake() { :; }
    power_logind_start() { logind=ready; power_sleep_replies="$tree/replies"; mkdir -p -- "$power_sleep_replies"; }
    power_logind_stop() { logind=stopped; }
    power_start_mocks() { daemon=up; }
    tree_rescan() { [[ ${daemon:-} == up ]] && scanned=yes; }
    ipc() {
      if [[ $* == "shell setPluginEnabled vgs.power true" ]]; then
        [[ ${daemon:-} == up && ${scanned:-} == yes && ${logind:-} == ready ]] || return 1
      fi
      echo ok
    }
    expect() { local label="$1" want="$2" got; shift 2; got="$("$@")"; [[ $got == "$want" ]]; }
    expect_poll() { :; }
    power_add_battery() { echo /org/freedesktop/UPower/devices/mock_BAT0; }
    notice_shown() { echo null; }
    power_discharging() { :; }
    power_no_battery() { :; }
    park_pointer() { :; }
    click_centre() { :; }
    bar_key() { echo bar; }
    notes_on() { :; }
    notes_clear() { :; }
    notes_off() { :; }
    power_stop_mocks() { :; }
    power_shot_pane() { take "power-$1-pane"; }
    fail() { exit 1; }
    take() { printf "%s\n" "$1"; }
    scene_power dark
    [[ $logind == stopped ]]
  ' _ "$1" >"$tmp/power-scene.out" &&
    [[ $(<"$tmp/power-scene.out") == "$want" ]]
}
if power_scene_case "$power_scene"; then ok "Power scans its fake daemon before enable and captures both notices and its panel with no battery"; else fail "Power scene order or captures failed"; fi
# A tree that ships Stay awake adds its bar and flyout shots with and
# without a battery; the section's own shot is power_shot_pane's.
power_awake_tree="$tmp/power-awake-tree"
mkdir -p "$power_awake_tree/shell/plugins/vgs.power"
: >"$power_awake_tree/shell/plugins/vgs.power/Pane.qml"
: >"$power_awake_tree/shell/plugins/vgs.power/StayAwake.qml"
if power_scene_case "$power_scene" $'power-dark-bar\npower-dark-panel\npower-dark-bar-stay-awake\npower-dark-panel-stay-awake\npower-dark-pane\npower-dark-notice-low\npower-dark-notice-critical\npower-dark-panel-no-battery\npower-dark-bar-no-battery-stay-awake\npower-dark-panel-no-battery-stay-awake' "$power_awake_tree"; then
  ok "a tree with Stay awake adds its bar and flyout shots with and without a battery"
else
  fail "Power scene Stay awake captures failed"
fi
power_mutant="$tmp/power-scene-mutant.sh"
for defect in no-scan late-daemon; do
  python3 - "$power_scene" "$power_mutant" "$defect" <<'PYCONTROL'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
needle = '  tree_rescan "the Power shots\' fake daemon is scanned"\n' if sys.argv[3] == 'no-scan' else '  power_start_mocks shots-power balanced\n'
assert text.count(needle) == 1
changed = text.replace(needle, '')
if sys.argv[3] == 'late-daemon':
    at = '  expect "Power enables for its shot" ok ipc shell setPluginEnabled vgs.power true\n'
    assert changed.count(at) == 1
    changed = changed.replace(at, at + needle)
assert changed != text
pathlib.Path(sys.argv[2]).write_text(changed)
PYCONTROL
  if power_scene_case "$power_mutant"; then fail "control: Power $defect stayed green"; else ok "control: Power $defect fails"; fi
done

# Drive the capture state owner against a published shell world. Windows
# and panes are enabled without an instance. The probe initially owns lock,
# Jarvis enablement adds a required-tool notice, and fixture preparation has
# left the requested off plugins on. No compositor or authentication runs.
capture_state_case() { # SCRIPT
  local dir
  dir="$(mktemp -d "$tmp/capture-state.XXXXXX")" || return 1
  mkdir -p "$dir/home/.config/vgshell/plugins/acme.probe" "$dir/shots"
  cp -- "$repo/scripts/smoke/fixtures/plugins/acme.probe/manifest.json" "$dir/home/.config/vgshell/plugins/acme.probe/"
  printf '{"version":2,"plugins":[]}\n' >"$dir/home/.config/vgshell/shell.json"
  python3 - "$1" "$repo/scripts/smoke/harness.sh" "$dir/helpers.sh" <<'PY'
import pathlib,sys
script,harness,dst=map(pathlib.Path,sys.argv[1:])
parts=[]
for source,names in ((script,("capture_mode_name","capture_theme_check","capture_probe_release","capture_plugin_states","capture_state_record","page_state_record","lock_row_quiet","scene_desktop","close_notices","notice_plugin","notice_moved_from")),(harness,("py_reply","notice_shown"))):
    text=source.read_text()
    for name in names:
        start=text.index("\n"+name+"() {")+1
        # One-line readers end on their declaration line.
        line_end=text.index("\n",start)
        if text[start:line_end].rstrip().endswith("}"): end=line_end
        else: end=text.index("\n}\n",start)+3
        parts.append(text[start:end])
dst.write_text("\n".join(parts))
PY
  cat >"$dir/world.py" <<'PY'
import json,pathlib,sys
root=pathlib.Path(sys.argv[1]); op=sys.argv[2]; args=sys.argv[3:]
file=root/"world.json"
if op=="plant":
    rows={}
    for id,kinds,on in (("vgs.gallery",["window"],False),("vgs.fonts",["pane"],False),("vgs.lock",["service"],False),("vgs.jarvis",["service"],False),("vgs.notifications",["service"],True),("vgs.devtools",["service","window"],True),("vgs.themes",["service","background"],True),("vgs.bar",["bar","service"],True),("acme.probe",["service"],True)):
        rows[id]={"id":id,"enabled":on,"kinds":kinds,"requirements":[],"settings":{"model":"fixture-model","localTier":"small"},"settingChoices":{},"status":[],"errors":[]}
    file.write_text(json.dumps({"rows":rows,"notices":["fixture."+str(i) for i in range(5)]}))
    sys.exit(0)
world=json.loads(file.read_text()); rows=world["rows"]; notices=world["notices"]
if op=="set":
    id,on=args; rows[id]["enabled"]=on=="true"
    if id=="vgs.jarvis" and on=="true": notices.append(id)
    file.write_text(json.dumps(world)); print("ok")
elif op=="enabled": print(rows[args[0]]["enabled"])
elif op=="built":
    row=rows[args[0]]
    print(row["enabled"] and "service" in row["kinds"] and not (row["id"]=="vgs.lock" and rows["acme.probe"]["enabled"]))
elif op=="list": print(json.dumps({"plugins":list(rows.values())}))
elif op=="manager": print(json.dumps(list(rows.values())))
elif op=="lent": print(json.dumps({"notices":{"shown":None if not notices else {"plugin":notices[0],"commands":["missing-tool"],"required":True,"installing":False},"waiting":notices[1:]}}))
elif op=="layer": print(int(bool(notices)))
elif op=="escape":
    if not notices: sys.exit(1)
    notices.pop(0); file.write_text(json.dumps(world))
PY
  python3 "$dir/world.py" "$dir" plant || return 1
  env -i PATH="$PATH" "$BASH" -c '
    set -euo pipefail
    at="$1" repo="$2" checkout="$2" home="$1/home" SHOT_DIR="$1/shots" capture_source=fixture-sha settings_kind=window main_name=WAYLAND-1
    node_bin="$(command -v node)"
    enable_ids=(vgs.gallery vgs.fonts vgs.lock vgs.jarvis)
    disable_ids=(vgs.notifications vgs.devtools vgs.themes vgs.bar)
    world() { python3 "$at/world.py" "$at" "$@"; }
    ipc() {
      case "$*" in
        "shell listShellConfig") printf "{\"bar\":{\"id\":\"vgs.bar\"}}\n" ;;
        "shell setPluginEnabled "*) world set "$3" "$4" ;;
        "shell listPlugins") world list ;;
        "shell lent") world lent ;;
        "smoke readInstance window vgs.settings plugins") world manager ;;
        "smoke themeName") printf "%s\n" "$mode_theme" ;;
        "smoke noticeFocused") echo true ;;
        *) exit 2 ;;
      esac
    }
    plugin_enabled() { world enabled "$1"; }
    record_exists() { world built "$1"; }
    layer_count() { world layer; }
    type_keys() { [[ $* == "-k Escape" ]] && world escape; }
    fail() { echo "$*" >&2; exit 1; }
    expect() { local label="$1" want="$2" got; shift 2; got="$("$@")" && [[ $got == "$want" ]] || fail "$label: $got != $want"; }
    expect_poll() { expect "$@"; }
    pixel() { echo 112233; }
    bg_state_names() { :; }
    background_image_on() { fail "an off Themes service was read"; }
    source "$at/helpers.sh"
    lock_row_quiet
    while read -r mode mode_theme; do
      capture_plugin_states "$mode"
      [[ $(plugin_enabled vgs.gallery) == True && $(plugin_enabled vgs.fonts) == True && $(record_exists vgs.lock) == True ]]
      [[ $(plugin_enabled vgs.notifications) == False && $(plugin_enabled vgs.devtools) == False && $(plugin_enabled vgs.themes) == False && $(plugin_enabled vgs.bar) == True ]]
      [[ $(notice_shown) == null && $(layer_count vgs:notice) == 0 ]]
      scene_desktop plugin-pages "$mode"
      capture_state_record plugin-pages "$mode"
      page_state_record "jarvis-$mode_theme" "$mode" vgs.jarvis
    done <<MODES
dark vgs
light flexoki-light
MODES
  ' _ "$dir" "$repo" >"$dir/out" 2>"$dir/err" || { cat -- "$dir/err" >&2; return 1; }
  python3 - "$dir" <<'PY'
import csv,json,pathlib,sys
root=pathlib.Path(sys.argv[1])
config=json.loads((root/"home/.config/vgshell/shell.json").read_text())
rows={r["id"]:r for r in config["plugins"]}
assert rows["vgs.lock"]["idleLockSeconds"]==0 and rows["vgs.lock"]["lockBeforeSleep"] is False
assert rows["vgs.screensaver"]["idleEnabled"] is False
with (root/"shots/plugin-states.tsv").open() as file:
    records=list(csv.reader(file,delimiter="\t"))
assert {r[3] for r in records}=={"vgs","flexoki-light"}
for r in records:
    states={p["id"]:p for p in json.loads(r[-1])}
    assert states["vgs.themes"]["requested"]=="off" and states["vgs.themes"]["enabled"] is False
    assert states["vgs.bar"]["requested"]=="off" and states["vgs.bar"]["enabled"] is True and states["vgs.bar"]["reason"]=="active-bar"
with (root/"shots/page-states.tsv").open() as file:
    records=list(csv.reader(file,delimiter="\t"))
assert {r[3] for r in records}=={"vgs","flexoki-light"}
for r in records:
    state=json.loads(r[-1]); assert state["enabled"] is True and state["settings"]["model"]=="fixture-model" and "status" in state and "requirements" in state
with (root/"shots/desktop.tsv").open() as file:
    assert all(r[-1]=="112233" for r in csv.reader(file,delimiter="\t"))
PY
}
if capture_state_case "$repo/scripts/sandbox-shots.sh"; then ok "capture states cover on-demand hosts, exclusive release, notices, explicit off and actual records in both themes"; else fail "capture state contract"; fi
capture_controls=(
  "on-demand builds are required" '[[ $live != True ]] || expect_poll' 'expect_poll'
  "the probe retains its exclusive capability" '"the probe releases its capabilities for $conflicts" ok ipc shell setPluginEnabled acme.probe false' '"the probe releases its capabilities for $conflicts" ok echo ok'
  "enable notices are not closed" $'  close_notices\n}\n\n# The published inventory' $'  :\n}\n\n# The published inventory'
  "explicit off never writes" '"disabling $id for the run is allowed" ok ipc shell setPluginEnabled "$id" false' '"disabling $id for the run is allowed" ok echo ok'
  "quiet lock keeps its idle timer" '"idleLockSeconds": 0' '"idleLockSeconds": 300'
  "notice cleanup is capped before the queue ends" 'i<count' 'i<4'
)
for ((i=0; i<${#capture_controls[@]}; i+=3)); do
  label="${capture_controls[i]}"; needle="${capture_controls[i+1]}"; replacement="${capture_controls[i+2]}"
  capture_mutant="$tmp/capture-mutant.sh"
  if ! mutate "$repo/scripts/sandbox-shots.sh" "$needle" "$replacement" "$capture_mutant"; then
    fail "control: $label could not be planted"
  elif capture_state_case "$capture_mutant" >"$tmp/capture-control.out" 2>&1; then
    fail "control: $label stayed green"
  else
    ok "control: $label fails the capture state contract"
  fi
done

if node "$tmp/probe-display-control.cjs" "$repo/scripts/smoke/Probe.qml"; then
  ok "Probe source methods retain finite events, JSON characters and terminal states"
else
  fail "Probe source methods violate their bounded output contract"
fi
probe_controls=(
  "event ceiling" 'if (displayEventSequence >= displayEventCapacityEvents - 1)' 'if (false && displayEventSequence >= displayEventCapacityEvents - 1)'
  "aggregate character ceiling" 'displayEventCapacityChars - displayEventTerminalReserve - displayEventChars' 'displayEventCapacityChars - displayEventTerminalReserve'
)
for ((i=0; i<${#probe_controls[@]}; i+=3)); do
  probe_mutant="$tmp/probe-display-mutant.qml"
  if ! mutate "$repo/scripts/smoke/Probe.qml" "${probe_controls[i+1]}" "${probe_controls[i+2]}" "$probe_mutant"; then
    fail "control: Probe ${probe_controls[i]} could not be planted"
    continue
  fi
  probe_status=0
  node "$tmp/probe-display-control.cjs" "$probe_mutant" >"$tmp/probe-display-control.log" 2>&1 || probe_status=$?
  if [[ $probe_status -eq 1 ]]; then
    ok "control: bypassing the Probe ${probe_controls[i]} fails its source-method assertions"
  else
    fail "control: bypassing the Probe ${probe_controls[i]} did not produce an assertion failure (exit $probe_status)"
    cat -- "$tmp/probe-display-control.log"
  fi
done

# These source fixtures explain why connected owners can publish no actual
# trial, completion or reload event. They do not judge record completeness
# or turn an initial owner sample into event history.
cat >"$tmp/display-expected-facts.cjs" <<'JS'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
try {
    const repo = process.argv[2], scratch = process.argv[3];
    const { load } = require(path.join(repo, 'bin/lib/qml-library.js'));
    const core = path.join(repo, 'shell/Core');
    const monitors = load(path.join(core, 'MonitorLogic.js'));
    const dispatch = load(path.join(core, 'Dispatch.js'));
    const files = { monitor: path.join(core, 'MonitorState.qml'),
        compositor: path.join(core, 'Compositor.qml'), layer: path.join(core, 'HyprlandLayer.js') };
    const sources = Object.fromEntries(Object.entries(files).map(([key, file]) => [key, fs.readFileSync(file, 'utf8')]));

    function sourceMethod(source, name, indent) {
        const pad = ' '.repeat(indent);
        const matches = [...source.matchAll(new RegExp('^' + pad + 'function ' + name
            + '\\([^\\n]*\\) \\{[\\s\\S]*?^' + pad + '\\}', 'gm'))];
        if (matches.length !== 1) throw new Error('expected-facts extraction: ' + name);
        return matches[0][0];
    }
    function context(source, names, indent, state) {
        state.root = state;
        vm.createContext(state);
        vm.runInContext(names.map(name => sourceMethod(source, name, indent)).join('\n'), state);
        return state;
    }
    function check(name, value, expected) {
        try { assert.equal(value, expected, name); }
        catch (error) { error.expectedFact = name; throw error; }
    }
    const parsed = monitors.parseOutputs(JSON.stringify([{
        id: 0, name: 'WAYLAND-1', description: '', make: '', model: '', serial: '',
        width: 1440, height: 900, refreshRate: 60, x: 0, y: 0, scale: 1, transform: 0,
        vrr: false, disabled: false, mirrorOf: 'none', availableModes: [],
        currentFormat: 'XRGB8888', colorManagementPreset: 'srgb', sdrBrightness: 1, sdrSaturation: 1
    }]));
    if (!parsed.ok) throw new Error('expected-facts monitor fixture rejected');

    const cases = [
        { id: 'trial-wrong-owner', owner: 'monitor', method: 'trial', caller: 'other' },
        { id: 'trial-unread-outputs', owner: 'monitor', method: 'trial', unread: true },
        { id: 'trial-active', owner: 'monitor', method: 'trial', phase: 'holding' },
        { id: 'trial-plan-rejected', owner: 'monitor', method: 'trial', rules: { UNKNOWN: { scale: 1 } } },
        { id: 'keep-wrong-token', owner: 'monitor', method: 'keep', phase: 'holding' },
        { id: 'revert-wrong-token', owner: 'monitor', method: 'revert', phase: 'holding' },
        { id: 'queue-invalid-request', owner: 'compositor', operation: 'invalid' },
        { id: 'queue-full', owner: 'compositor', operation: 'full' },
        { id: 'queue-empty', owner: 'compositor', operation: 'empty' },
        { id: 'layer-unchanged', owner: 'layer', operation: 'begin' },
        { id: 'layer-missing-input', owner: 'layer', operation: 'missing' },
        { id: 'layer-busy', owner: 'layer', operation: 'busy' },
        { id: 'layer-prepare-refused', owner: 'layer', operation: 'prepare' },
        { id: 'layer-save-refused', owner: 'layer', operation: 'save' }
    ];
    function runCase(row, source) {
        if (row.owner === 'monitor') {
            let trialState = { phase: row.phase || 'idle', token: 'existing-token', deadline: 0, failure: '' };
            let publications = 0;
            const state = { ownerId: 'owner', outputs: row.unread ? null : parsed.outputs,
                support: {}, Monitors: monitors };
            Object.defineProperty(state, 'trialState', { configurable: true,
                get: () => trialState, set: value => { trialState = value; publications++; } });
            context(source, ['mustOwn', 'trial', 'keep', 'revert'], 4, state);
            const answer = row.method === 'trial'
                ? state.trial(row.caller || 'owner', row.rules || { 'WAYLAND-1': { scale: 1 } }, {})
                : state[row.method]('owner', 'wrong-token');
            check(row.id + ':no-trial-publication', publications, 0);
            check(row.id + ':refused', typeof answer === 'string' && answer.startsWith('refused:'), true);
            return;
        }
        if (row.owner === 'compositor') {
            let starts = 0, completions = 0, completion = null;
            const proc = {};
            Object.defineProperty(proc, 'running', { set: value => { if (value === true) starts++; } });
            const state = { Dispatch: dispatch, Hyprland: { usingLua: true }, proc,
                console: { error: () => {} }, pending: null, pendingDone: null, pendingJudged: false, reply: '',
                queue: row.operation === 'full' ? Array.from({ length: dispatch.QUEUE_LIMIT }, () =>
                    ({ argv: ['hyprctl', 'fixture'], done: null, judged: false })) : [] };
            Object.defineProperty(state, 'completion', { configurable: true,
                get: () => completion, set: value => { completion = value; if (value !== null) completions++; } });
            context(source, ['monitorEval', 'enqueue', 'drain'], 4, state);
            let answer;
            if (row.operation === 'invalid') answer = state.monitorEval('not-monitor-lua', null);
            else if (row.operation === 'full') answer = state.enqueue(['hyprctl', 'fixture'], null, false);
            else state.drain();
            check(row.id + ':no-completion-publication', completions, 0);
            check(row.id + ':no-process-start', starts, 0);
            if (row.operation !== 'empty')
                check(row.id + ':refused', typeof answer === 'string' && answer.startsWith('refused:'), true);
            return;
        }
        const layer = context(source, ['initialState', 'withChanges', 'expectPhase', 'consentChanges',
            'begin', 'written', 'reload', 'idleDecision', 'step'], 0, {});
        const state = layer.withChanges(layer.initialState(), {
            phase: row.operation === 'busy' || row.operation === 'save' ? 'writing'
                : row.operation === 'prepare' ? 'preparing' : 'idle',
            onDisk: 'existing-layer', pending: 'changed-layer',
            consent: { phase: 'settled', queued: '', failure: '' }
        });
        let result;
        if (row.operation === 'begin') result = layer.begin(state, 'existing-layer');
        else if (row.operation === 'missing') result = layer.begin(state, null);
        else if (row.operation === 'busy') result = layer.step(state, { type: 'render' }, 'changed-layer');
        else result = layer.step(state, {
            type: row.operation === 'prepare' ? 'mkdirDone' : 'saveFailed', failure: 'fixture-refusal'
        }, 'changed-layer');
        check(row.id + ':no-reload-action', result.action === 'reload', false);
        check(row.id + ':next-action', result.action, row.operation === 'save' ? 'read' : 'none');
    }
    for (const row of cases) runCase(row, sources[row.owner]);

    // Each mutation introduces the forbidden fact at the actual return
    // boundary. It keeps the refusal/control text, so an unrelated parse
    // failure cannot count as the intended assertion's rejection.
    const publish = 'trialState = { phase: "arming" }; ';
    const ownerReturn = 'if (ownership !== "") return ownership;';
    const tokenReturn = 'return "refused: monitors-token=unknown";';
    const mutations = [
        ['trial-wrong-owner', 'trial', ownerReturn, 'if (ownership !== "") { ' + publish + 'return ownership; }', 'no-trial-publication'],
        ['trial-unread-outputs', 'trial', 'if (outputs === null) return "refused: monitors=unread";',
            'if (outputs === null) { ' + publish + 'return "refused: monitors=unread"; }', 'no-trial-publication'],
        ['trial-active', 'trial', 'if (trialState.phase !== "idle") return "refused: monitors-trial=active";',
            'if (trialState.phase !== "idle") { ' + publish + 'return "refused: monitors-trial=active"; }', 'no-trial-publication'],
        ['trial-plan-rejected', 'trial', 'if (!trial.ok) return trial.error;',
            'if (!trial.ok) { ' + publish + 'return trial.error; }', 'no-trial-publication'],
        ['keep-wrong-token', 'keep', tokenReturn, '{ ' + publish + tokenReturn + ' }', 'no-trial-publication'],
        ['revert-wrong-token', 'revert', tokenReturn, '{ ' + publish + tokenReturn + ' }', 'no-trial-publication'],
        ['queue-invalid-request', 'monitorEval', 'return r.error;',
            'root.completion = { code: 0, status: 0 }; return r.error;', 'no-completion-publication'],
        ['queue-full', 'enqueue', 'return error;', 'proc.running = true; return error;', 'no-process-start'],
        ['queue-empty', 'drain', 'while (queue.length > 0) {',
            'if (queue.length === 0) proc.running = true;\n        while (queue.length > 0) {', 'no-process-start'],
        ['layer-unchanged', 'begin', 'return { state: withChanges(state, { forcing: false }), action: "none" };',
            'return { state: withChanges(state, { forcing: false }), action: "reload" };', 'no-reload-action'],
        ['layer-missing-input', 'begin', 'return { state: withChanges(state, { forcing: false }), action: "none" };',
            'return { state: withChanges(state, { forcing: false }), action: "reload" };', 'no-reload-action'],
        ['layer-busy', 'step', 'return state.phase === "idle" ? begin(state, text) : { state: state, action: "none" };',
            'return state.phase === "idle" ? begin(state, text) : { state: state, action: "reload" };', 'no-reload-action'],
        ['layer-prepare-refused', 'step',
            'if (event.failure !== "") return idleDecision(withChanges(state, { failedText: state.pending }), event.failure, text, true);',
            'if (event.failure !== "") return written(state);', 'no-reload-action'],
        ['layer-save-refused', 'step',
            'return idleDecision(withChanges(state, { stale: true, failedText: state.pending }), event.failure, text, true);',
            'return written(state);', 'no-reload-action']
    ];
    for (const [id, method, needle, replacement, intended] of mutations) {
        const row = cases.find(candidate => candidate.id === id);
        const source = sources[row.owner];
        const body = sourceMethod(source, method, row.owner === 'layer' ? 0 : 4);
        if (body.split(needle).length !== 2) throw new Error('expected-facts mutation match: ' + id);
        const changed = body.replace(needle, replacement);
        if (changed === body) throw new Error('expected-facts mutation unchanged: ' + id);
        const mutant = path.join(scratch, 'expected-facts-' + id + path.extname(files[row.owner]));
        fs.writeFileSync(mutant, source.replace(body, changed), { flag: 'wx' });
        let killed = false;
        try { runCase(row, fs.readFileSync(mutant, 'utf8')); }
        catch (error) {
            if (error.code !== 'ERR_ASSERTION' || error.expectedFact !== id + ':' + intended)
                throw new Error('expected-facts mutation failed outside intended assertion: ' + id + ': ' + error.message);
            killed = true;
        }
        check(id + ':mutation-rejected', killed, true);
        console.log('display-expected-facts: mutation-rejected=' + id + ' assertion=' + intended);
    }
    console.log('display-expected-facts: pass');
} catch (error) {
    if (error.code === 'ERR_ASSERTION') {
        console.error('display-expected-facts: assertion-failed=' + error.expectedFact + ' ' + error.message);
        process.exitCode = 1;
    } else {
        console.error('display-expected-facts: unavailable ' + error.message);
        process.exitCode = 2;
    }
}
JS
if node "$tmp/display-expected-facts.cjs" "$repo" "$tmp"; then
  ok "actual refusal and no-change paths do not imply trial, completion or reload history"
else
  fail "actual source expected-fact controls did not pass"
fi

if [[ $failures -gt 0 ]]; then
  echo "test-sandbox-shots: failed=$failures"
  exit 1
fi
echo "test-sandbox-shots: ok"
