#!/usr/bin/env bash
# Drive the host side of scripts/jarvis-selftest.sh with no sandbox, no
# account, no model and no audio.
#
# The runner cases run a copy of the runner in a scratch tree, beside a
# stand-in fence that records how it was called and a stand-in harness
# that makes a scratch sandbox with an instrumented Jarvis copy and ends
# the run at its first shell start. The accounts are a scratch HOME's: one
# sign-in folder and the saved key references a case writes, whose ids the
# plugin's own account helper lists with no command on its PATH. The prepared
# local voice is a scratch setup of empty files. `pw-dump` is a stub that
# prints a planted graph, which the real devices_voice_feed_state reads.
# The keyring is a stand-in secrets service on a scratch bus this file
# starts, never the caller's: it holds one item, present, locked or absent
# as a case sets it, logs each call it gets, and owns a second bus name. The
# runner's own filter, a real xdg-dbus-proxy, and the real secret-tool and
# busctl reach it. Without one of those programs the keyring cases are not
# measured and the file exits 77 once the others have run.
# The function cases run the runner's own functions, cut from its file,
# over planted traces, audit records and folders, with the harness's own
# py_reply.
# Each control plants one defect in a copy of the runner and requires the
# case that rule owns to go red.
#
# Exit 0 when every case and control holds, 1 when one does not, and 77
# when all that ran hold and the keyring cases could not run.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
runner="$repo/scripts/jarvis-selftest.sh"

tmp="$(mktemp -d)" || { echo "test-jarvis-selftest: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $tmp && ! -L $tmp ]] || { echo "test-jarvis-selftest: scratch=not-a-directory value=[$tmp]" >&2; exit 1; }
tmp="$(cd -- "$tmp" && pwd -P)" || { echo "test-jarvis-selftest: scratch=resolve-failed" >&2; exit 1; }
# The scratch bus and the stand-in service end by the pids this file
# started, and are reaped before their scratch root goes.
bus_pids=()
trap 'for pid in "${bus_pids[@]}"; do kill "$pid" 2>/dev/null || true; done; wait; rm -rf -- "${tmp:?}"' EXIT
failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }
# holds LABEL CMD...: CMD succeeds. control LABEL CMD...: CMD fails, as the
# case it names does over the planted defect.
holds() { local label="$1"; shift; if "$@"; then ok "$label"; else fail "$label"; show; fi; }
control() { local label="$1"; shift; if "$@"; then fail "control: $label stayed green"; else ok "control: $label"; fi; }
show() { for file in out err harness.log fence.log; do [[ ! -s $tmp/$file ]] || sed "s/^/        $file: /" -- "$tmp/$file"; done; }
# mutate SOURCE OLD NEW DEST: DEST is SOURCE with its one OLD replaced.
mutate() {
  python3 - "$@" <<'PY'
import sys
source, old, new, dest = sys.argv[1:]
text = open(source).read()
assert text.count(old) == 1, f"the mutation must match once: {old!r} matched {text.count(old)}"
open(dest, "w").write(text.replace(old, new))
PY
}

# node on PATH may be a version manager's shim, which fails under a scratch
# HOME; every case's PATH leads with the directory of the binary itself.
node_bin="$(node -e 'process.stdout.write(process.execPath)')"
mkdir -p "$tmp/bin" "$tmp/empty"
printf '#!/bin/sh\ncat -- "%s"\n' "$tmp/graph.json" >"$tmp/bin/pw-dump"
chmod +x "$tmp/bin/pw-dump"
path="$tmp/bin:$(dirname -- "$node_bin"):$PATH"

# The accounts: a sign-in folder, and the saved key references a case names
# as PROVIDER/ACCOUNT words. account_id KIND LABEL is the id the plugin's own
# helper lists for one.
world="$tmp/world"
state="$world/.local/state/vgshell/jarvis"
mkdir -p "$world/.claude" "$state"
saved_keys() { # PROVIDER/ACCOUNT...
  python3 - "$state/keys.json" "$@" <<'PY'
import json, sys
origins = {"openai": "https://api.openai.com", "anthropic": "https://api.anthropic.com"}
rows = []
for word in sys.argv[2:]:
    provider, account = word.split("/")
    rows.append({"provider": provider, "account": account, "origin": origins[provider],
                 "attributes": {"service": "vgs-jarvis", "provider": provider, "account": account, "origin": origins[provider]}})
json.dump(rows, open(sys.argv[1], "w"))
PY
}
account_id() { # KIND LABEL
  env -i PATH="$tmp/empty" HOME="$world" "$node_bin" "$repo/shell/plugins/vgs.jarvis/backend/accounts.js" --tree "$repo" list |
    python3 -c 'import json,sys; print(next(r["id"] for r in json.load(sys.stdin) if r["source"]["kind"] == sys.argv[1] and r["label"] == sys.argv[2]))' "$1" "$2"
}
saved_keys openai/selftest anthropic/other
sign_in="$(account_id cli default)"
saved_key="$(account_id keyring selftest)"

# The prepared local voice, and one whose interpreter is another setup's.
prepared() { # HOME
  local data="$1/.local/share/vgshell/jarvis/local"
  mkdir -p "$data/models" "$data/venv/bin" "$1/.local/state/vgshell/jarvis"
  printf '#!/bin/sh\nexit 0\n' >"$data/venv/bin/python"
  chmod +x "$data/venv/bin/python"
  echo '{}' >"$1/.local/state/vgshell/jarvis/local-ready.json"
}
prepared "$tmp/voice"
prepared "$tmp/other-voice"
voice_root="$tmp/voice/.local/share/vgshell/jarvis/local"
voice_inputs=(JARVIS_LOCAL_MODELS="$voice_root/models" JARVIS_LOCAL_PYTHON="$voice_root/venv/bin/python")

# The scratch tree: the runner's copy, the checkout's shell and bin, a fence
# that answers --check from fence-answer and records every other call, and
# the harness stand-in. The stand-in holds the harness's own spawn and
# sentinel stand-over, cut from its file, a secret-tool sentinel that
# answers as the harness's does, and an exit path that ends what the run
# spawned. Its start_shell sources at-start.sh where a case left one, so
# the case reads the run's filter and its secret-tool while they stand.
tree="$tmp/tree"
mkdir -p "$tree/scripts/smoke"
ln -s -- "$repo/shell" "$tree/shell"
ln -s -- "$repo/bin" "$tree/bin"
cat >"$tree/scripts/smoke/gpu-fence.sh" <<SH
#!/usr/bin/env bash
if [[ \${1:-} == --check ]]; then echo check >>"$tmp/fence.log"; exit "\$(<"$tmp/fence-answer")"; fi
printf 'run' >>"$tmp/fence.log"
for word in "\$@"; do printf ' [%s]' "\$word" >>"$tmp/fence.log"; done
echo >>"$tmp/fence.log"
SH
chmod +x "$tree/scripts/smoke/gpu-fence.sh"
cat >"$tree/scripts/smoke/harness.sh" <<SH
echo harness-reached >>"$tmp/harness.log"
source_repo="\$repo"
sandbox="$tmp/sandbox"
home="\$sandbox/home"
repo="\$sandbox/repo"
rm -rf -- "\${sandbox:?}"
mkdir -p "\$home/.config/vgshell" "\$repo/shell/plugins/vgs.jarvis"
echo instrumented >"\$repo/shell/plugins/vgs.jarvis/Service.qml"
echo '{"version": 1, "plugins": [{"id": "vgs.settings"}], "disabledPlugins": ["vgs.jarvis"]}' >"\$home/.config/vgshell/shell.json"
failures=0 instance_log="" devices_state=down auth_log="\$sandbox/auth.calls" shell_env=()
rt_dir="$tmp/rt" shim="\$sandbox/shim" sentinels_saved="\$sandbox/sentinels" sentinels_stood="\$sandbox/sentinels.stood" pgids=()
rm -rf -- "\${rt_dir:?}"
mkdir -p "\$rt_dir" "\$shim" "\$sentinels_saved"
trap 'for pid in "\${pgids[@]}"; do kill -TERM -- "-\$pid" 2>/dev/null || true; done' EXIT
printf '#!/usr/bin/env bash\ncase "\${1:-}" in search) exit 0 ;; lookup) exit 1 ;; esac\nprintf "%%s\\n" "secret-tool \$*" >>%q\nexit 1\n' "\$auth_log" >"\$shim/secret-tool"
chmod 755 "\$shim/secret-tool"
stop_shell() { echo stop_shell >>"$tmp/harness.log"; }
devices_up() { devices_state=up; }
start_shell() {
  echo "start_shell \${*:4}" >>"$tmp/harness.log"
  [[ ! -e "$tmp/at-start.sh" ]] || source "$tmp/at-start.sh"
  exit 0
}
SH
{ sed -n '/^spawn() {/,/^}/p; /^sentinel_saved() {/p; /^sentinel_stand_over() {/,/^}/p' "$repo/scripts/smoke/harness.sh"
  sed -n '/^devices_voice_feed_sink=/p; /^devices_voice_feed_source=/p; /^devices_voice_feed_state() {/,/^}/p' "$repo/scripts/smoke/devices.sh"; } >>"$tree/scripts/smoke/harness.sh"

# graph READER NODE...: the planted graph, the named nodes with ids from 30
# and, for READER `read`, a link that leaves the last of them.
graph() {
  python3 - "$tmp/graph.json" "$@" <<'PY'
import json, sys
path, reader, names = sys.argv[1], sys.argv[2], sys.argv[3:]
objects = [{"id": 30 + i, "type": "PipeWire:Interface:Node", "info": {"props": {"node.name": name}}} for i, name in enumerate(names)]
if reader == "read":
    objects.append({"id": 90, "type": "PipeWire:Interface:Link", "info": {"output-node-id": 30 + len(names) - 1, "input-node-id": 80}})
json.dump(objects, open(path, "w"))
PY
}
# run ARGS...: the tree's runner over the scratch accounts, the words of
# `inputs` and, where a case names one, the session bus of `session_bus`.
# Sets status; stdout and stderr go to out and err.
inputs=("${voice_inputs[@]}")
session_bus=()
run() {
  : >"$tmp/fence.log"; : >"$tmp/harness.log"
  status=0
  (cd -- "$tmp" && env -i PATH="$path" HOME="$world" "${inputs[@]}" "${session_bus[@]}" "$BASH" "$tree/scripts/jarvis-selftest.sh" "$@") >"$tmp/out" 2>"$tmp/err" || status=$?
}
plant() { cp -- "$1" "$tree/scripts/jarvis-selftest.sh"; }
# ends WANT_STATUS WANT_LINE ARGS...: the run ends with that status and that
# last line on stdout, having started nothing.
ends() {
  local want_status="$1" want_line="$2"
  shift 2
  run "$@"
  [[ $status -eq $want_status && "$(tail -n 1 -- "$tmp/out")" == "$want_line" && ! -s $tmp/fence.log && ! -s $tmp/harness.log ]]
}

echo "--- what the run refuses before it starts anything"
plant "$runner"
echo 1 >"$tmp/fence-answer"
graph none vgs-smoke-speakers vgs-smoke-voice-feed vgs-smoke-voice
# One table for the prepared local voice: what the two variables name.
local_rows=(
  "no variable|"
  "a models folder that is absent|JARVIS_LOCAL_MODELS=$tmp/absent JARVIS_LOCAL_PYTHON=$voice_root/venv/bin/python"
  "an interpreter of another setup|JARVIS_LOCAL_MODELS=$voice_root/models JARVIS_LOCAL_PYTHON=$tmp/other-voice/.local/share/vgshell/jarvis/local/venv/bin/python"
  "a setup with no ready marker|JARVIS_LOCAL_MODELS=$tmp/unready/.local/share/vgshell/jarvis/local/models JARVIS_LOCAL_PYTHON=$tmp/unready/.local/share/vgshell/jarvis/local/venv/bin/python"
)
prepared "$tmp/unready"
rm -- "$tmp/unready/.local/state/vgshell/jarvis/local-ready.json"
local_case() { # ROW
  read -r -a inputs <<<"${1#*|}"
  local held=0
  ends 77 selftest=local-inputs-unavailable --type hello --brain "$sign_in" || held=1
  inputs=("${voice_inputs[@]}")
  return "$held"
}
for row in "${local_rows[@]}"; do holds "${row%%|*} ends as selftest=local-inputs-unavailable, exit 77" local_case "$row"; done
refused() { # WANT_FIRST_STDERR_LINE ARGS...
  local want="$1"
  shift
  run "$@"
  [[ $status -eq 2 && "$(head -n 1 -- "$tmp/err")" == "$want" && ! -s $tmp/fence.log && ! -s $tmp/harness.log ]]
}
holds "an id no account has is refused" refused "jarvis-selftest: refused: argument=--brain value=cli:none reason=unknown-account" --type hello --brain cli:none
holds "a second input is refused" refused "jarvis-selftest: refused: argument=--tts reason=one-input" --type hello --tts hello --brain "$sign_in"
holds "no input is refused" refused "jarvis-selftest: refused: argument=input reason=missing want=--wav|--tts|--type" --brain "$sign_in"
holds "a WAV that is not there is refused" refused "jarvis-selftest: refused: argument=--wav value=$tmp/absent.wav reason=unreadable" --wav "$tmp/absent.wav" --brain "$sign_in"
# What a key read ends on with nothing started. Each case saves its own
# references and leaves the one OpenAI key and the Anthropic key behind.
unsaved_voice() {
  local held=0
  saved_keys anthropic/other
  ends 77 "selftest=keyring-no-key key=unsaved" --type hello --brain "$sign_in" --voice realtime || held=1
  saved_keys openai/selftest anthropic/other
  return "$held"
}
several_voices() {
  local held=0
  saved_keys openai/selftest openai/second
  refused "jarvis-selftest: refused: argument=--voice value=realtime reason=several-openai-keys" --type hello --brain "$sign_in" --voice realtime || held=1
  saved_keys openai/selftest anthropic/other
  return "$held"
}
no_session_bus() { ends 77 "selftest=keyring-unavailable missing=session-bus" --type hello --brain "$saved_key"; }
holds "the realtime voice with no OpenAI key saved ends as selftest=keyring-no-key key=unsaved, exit 77" unsaved_voice
holds "the realtime voice with two OpenAI keys saved is refused" several_voices
holds "a saved key with no session bus ends as selftest=keyring-unavailable, exit 77" no_session_bus

mutant="$tmp/mutant.sh"
mutate "$runner" '  none) unavailable keyring-no-key key=unsaved ;;' '  none) ;;' "$mutant" && plant "$mutant"
control "a runner that starts the realtime voice with no key saved" unsaved_voice
mutate "$runner" '  several) refuse "argument=--voice value=realtime reason=several-openai-keys" ;;' '  several) ;;' "$mutant" && plant "$mutant"
control "a runner that starts the realtime voice with two keys saved" several_voices
mutate "$runner" '  [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || unavailable keyring-unavailable missing=session-bus' '  :' "$mutant" && plant "$mutant"
control "a runner that goes on to a key read with no session bus" no_session_bus
mutate "$runner" 'selftest_local_inputs)" || unavailable local-inputs-unavailable' 'selftest_local_inputs)" || local_inputs=/nowhere$'"'"'\n'"'"'/nowhere' "$mutant" && plant "$mutant"
control "a runner that goes on without a prepared local voice" local_case "${local_rows[0]}"
mutate "$runner" '  [[ $models -ef $root/models && $python -ef $root/venv/bin/python ]] || return 1' '' "$mutant" && plant "$mutant"
control "a runner that takes an interpreter of another setup" local_case "${local_rows[2]}"
mutate "$runner" '  [[ -f $marker ]] || return 1' '' "$mutant" && plant "$mutant"
control "a runner that takes a setup with no ready marker" local_case "${local_rows[3]}"

echo "--- the fence"
words=(--type "two words" --brain "$sign_in" --confirm key)
enters() {
  echo 1 >"$tmp/fence-answer"
  run "${words[@]}"
  local want="check"$'\n'"run [$tree/scripts/jarvis-selftest.sh]" word
  for word in "${words[@]}"; do want+=" [$word]"; done
  [[ $status -eq 0 && "$(<"$tmp/fence.log")" == "$want" && ! -s $tmp/harness.log ]]
}
goes_on() {
  echo 0 >"$tmp/fence-answer"
  run "${words[@]}"
  [[ "$(<"$tmp/fence.log")" == check && "$(head -n 1 -- "$tmp/harness.log")" == harness-reached ]]
}
plant "$runner"
holds "the runner hands itself and its arguments to the fence before it makes anything" enters
holds "the runner goes on to the harness where the fence's check passes" goes_on
mutate "$runner" '--check || exec ' '--check || : ' "$mutant" && plant "$mutant"
control "a runner that never enters the fence" enters
mutate "$runner" '--check || exec ' '--check; exec ' "$mutant" && plant "$mutant"
control "a runner that always enters the fence" goes_on

echo "--- what the run makes before its shell starts"
echo 0 >"$tmp/fence-answer"
sandbox="$tmp/sandbox"
row_of() { python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); print(json.dumps([r for r in c["plugins"] if r["id"] == "vgs.jarvis"] + [c["disabledPlugins"]], sort_keys=True))' "$sandbox/home/.config/vgshell/shell.json"; }
starts() { run --type hello --brain "$sign_in" "$@"; [[ $status -eq 0 ]]; }
plugin_restored() { starts && diff -r -q -- "$repo/shell/plugins/vgs.jarvis" "$sandbox/repo/shell/plugins/vgs.jarvis" >/dev/null; }
account_alone() { starts && [[ "$(<"$tmp/harness.log")" == "harness-reached"$'\n'"stop_shell"$'\n'"start_shell CLAUDE_CONFIG_DIR=$world/.claude" ]]; }
settings_named() {
  starts && [[ "$(row_of)" == "[{\"brain\": \"$sign_in\", \"id\": \"vgs.jarvis\", \"microphone\": \"vgs-smoke-voice\", \"mode\": \"toggle\", \"speaker\": \"vgs-smoke-speakers\", \"voiceProvider\": \"local\"}, [\"vgs.jarvis\"]]" ]]
}
voice_linked() { starts && [[ $sandbox/home/.local/share/vgshell/jarvis/local -ef $voice_root ]] && cmp -s -- "$tmp/voice/.local/state/vgshell/jarvis/local-ready.json" "$sandbox/home/.local/state/vgshell/jarvis/local-ready.json"; }
plant "$runner"
holds "the sandbox's Jarvis plugin is the checkout's, byte for byte" plugin_restored
holds "the shell starts with the account's directory variable as its one extra word" account_alone
holds "Jarvis's settings name the brain, the feed's source and the null speakers, with Jarvis still disabled" settings_named
holds "the prepared setup is linked as the sandbox's local voice, with its marker" voice_linked
mutate "$runner" 'cp -R -- "$plugin" "$repo/shell/plugins/vgs.jarvis"' 'cp -R -- "$repo/shell/plugins" "$sandbox/kept"' "$mutant"
mutate "$mutant" 'rm -rf -- "${repo:?}/shell/plugins/vgs.jarvis"' ':' "$mutant" && plant "$mutant"
control "a runner that keeps the harness's instrumented plugin" plugin_restored
mutate "$runner" 'bar "${account_word[@]}"' 'bar "${account_word[@]}" "HOME=$HOME"' "$mutant" && plant "$mutant"
control "a runner that hands the shell another word of the caller's" account_alone
mutate "$runner" '"microphone": microphone,' '' "$mutant" && plant "$mutant"
control "a runner that leaves the microphone to the default" settings_named

# The home folder: the settings name a copy, and a write under the copy's
# state/ leaves the folder's checksum as it was.
folder="$tmp/jarvis home"
make_folder() {
  rm -rf -- "${folder:?}"
  mkdir -p "$folder/state" "$folder/skills/notes"
  echo instructions >"$folder/AGENTS.md"
  echo skill >"$folder/skills/notes/SKILL.md"
  ln -s AGENTS.md "$folder/CLAUDE.md"
}
functions="$tmp/functions.sh"
cut_functions() { # RUNNER
  { sed -n '/^py_reply() {/,/^}/p' "$repo/scripts/smoke/harness.sh"
    for name in selftest_tree_sum selftest_home_copy selftest_daemon selftest_last selftest_turn selftest_record selftest_wait; do sed -n "/^$name() {/,/^}/p" "$1"; done; } >"$functions"
}
call() { bash -c 'set -euo pipefail; source "$1"; shift; "$@"' _ "$functions" "$@"; }
home_untouched() {
  local before copy="$sandbox/jarvis-home"
  make_folder
  before="$(call selftest_tree_sum "$folder")" || return 1
  starts --home "$folder" || return 1
  [[ "$(row_of | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["home"])')" == "$copy" ]] || return 1
  echo memory >"$copy/state/turn.json" && echo changed >>"$copy/AGENTS.md" && rm -- "$copy/skills/notes/SKILL.md" || return 1
  [[ "$(call selftest_tree_sum "$folder")" == "$before" ]]
}
cut_functions "$runner"
plant "$runner"
holds "a write under the home copy's state/ leaves the named folder byte for byte unchanged" home_untouched
mutate "$runner" '  cp -a -- "$1" "$2"' '  ln -s -- "$1" "$2"' "$mutant" && plant "$mutant"
control "a runner whose home copy is the folder itself" home_untouched
mutate "$runner" '"$devices_voice_feed_source" "$home_copy" <<' '"$devices_voice_feed_source" "$home_source" <<' "$mutant" && plant "$mutant"
control "a runner whose settings name the folder itself" home_untouched
# The checksum is the instrument: each kind of change must move it.
make_folder
sum_moves() { # CHANGE...
  local before
  before="$(call selftest_tree_sum "$folder")" || return 1
  "$@" || return 1
  [[ "$(call selftest_tree_sum "$folder")" != "$before" ]]
}
holds "the checksum moves on a changed byte" sum_moves bash -c 'echo Instructions >"$1/AGENTS.md"' _ "$folder"
holds "the checksum moves on an added empty file" sum_moves touch "$folder/state/new"
holds "the checksum moves on a link that names another file" sum_moves ln -sfn state/new "$folder/CLAUDE.md"
mutate "$runner" " -type f -exec sha256sum -- {} +" "" "$mutant"
cut_functions "$mutant"
control "a checksum of names alone" sum_moves bash -c 'echo instructions >"$1/AGENTS.md"' _ "$folder"

echo "--- the voice feed"
feed_reads() { # WANT READER NODE...
  local want="$1"
  shift
  graph "$@"
  [[ "$(PATH="$path" bash -c 'set -euo pipefail; shell_env=(); source "$1"; devices_voice_feed_state' _ <(sed -n '/^devices_voice_feed_sink=/p; /^devices_voice_feed_source=/p; /^devices_voice_feed_state() {/,/^}/p' "$repo/scripts/smoke/devices.sh"))" == "$want" ]]
}
holds "a graph with no feed sink reads absent=sink" feed_reads absent=sink none vgs-smoke-speakers vgs-smoke-voice
holds "a graph with no feed source reads absent=source" feed_reads absent=source none vgs-smoke-voice-feed vgs-smoke-speakers
holds "a feed no capture reads is absent=recorder" feed_reads absent=recorder none vgs-smoke-voice-feed vgs-smoke-voice
holds "a link that leaves another node is no reader of the feed" feed_reads absent=recorder read vgs-smoke-voice-feed vgs-smoke-voice vgs-smoke-microphone
holds "a feed a capture reads is ready" feed_reads ready read vgs-smoke-voice-feed vgs-smoke-voice
no_feed() {
  rm -f -- "$tmp/record.json"
  graph none vgs-smoke-speakers vgs-smoke-headphones vgs-smoke-microphone
  run --type hello --brain "$sign_in" --out "$tmp/record.json"
  [[ $status -eq 1 && "$(tail -n 1 -- "$tmp/out")" == "selftest=no-voice-feed absent=sink" && "$(<"$tmp/harness.log")" == "harness-reached"$'\n'"stop_shell" && ! -e $tmp/record.json ]]
}
plant "$runner"
holds "with the loopback absent the run ends as selftest=no-voice-feed, exit 1, before Jarvis starts and with no record" no_feed
mutate "$runner" 'selftest_wait 10 absent=recorder devices_voice_feed_state || stopped no-voice-feed "$reading"' ':' "$mutant" && plant "$mutant"
control "a runner that starts Jarvis without the feed" no_feed
graph none vgs-smoke-speakers vgs-smoke-voice-feed vgs-smoke-voice

echo "--- a saved key: the filtered secrets bus"
keyring_cases() {
  # The scratch bus, and on it the stand-in secrets service: one item with
  # the saved OpenAI key's attributes, in the state the file keyring-mode
  # names at each call, and a second name that answers Ping. It logs each
  # call it gets in keyring.calls, a search with the attributes asked.
  local bus="$tmp/bus"
  cat >"$tmp/bus.xml" <<XML
<busconfig><type>session</type><listen>unix:path=$bus</listen><auth>EXTERNAL</auth>
<policy context="default"><allow send_destination="*"/><allow receive_sender="*"/><allow own="*"/></policy></busconfig>
XML
  cat >"$tmp/secrets-service.py" <<'PY'
import sys
import dbus, dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

mode_file, log = sys.argv[1:3]
held = dict(pair.split("=", 1) for pair in sys.argv[3:])
SERVICE = "org.freedesktop.Secret.Service"
ITEM = "/org/freedesktop/secrets/collection/selftest/1"
SESSION = "/org/freedesktop/secrets/session/1"

def note(line):
    with open(log, "a") as file:
        file.write(line + "\n")

class Service(dbus.service.Object):
    @dbus.service.method(SERVICE, in_signature="a{ss}", out_signature="aoao")
    def SearchItems(self, attributes):
        note("SearchItems " + ",".join(f"{key}={value}" for key, value in sorted(attributes.items())))
        mode = open(mode_file).read().strip()
        found = all(held.get(key) == value for key, value in attributes.items())
        return ([ITEM] if found and mode == "present" else [], [ITEM] if found and mode == "locked" else [])
    @dbus.service.method(SERVICE, in_signature="sv", out_signature="vo")
    def OpenSession(self, algorithm, value):
        note("OpenSession")
        if algorithm != "plain":
            raise dbus.exceptions.DBusException("plain alone", name="org.freedesktop.DBus.Error.NotSupported")
        return dbus.String("", variant_level=1), dbus.ObjectPath(SESSION)
    @dbus.service.method(SERVICE, in_signature="aoo", out_signature="a{o(oayays)}")
    def GetSecrets(self, items, session):
        note("GetSecrets")
        return {ITEM: (dbus.ObjectPath(SESSION), dbus.ByteArray(b""), dbus.ByteArray(b"stand-in-key"), "text/plain")}
    @dbus.service.method(SERVICE, in_signature="ao", out_signature="aoo")
    def Unlock(self, objects):
        note("Unlock")
        return [], dbus.ObjectPath("/")
    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        note("GetAll")
        return {"Collections": dbus.Array([], signature="o")}

class Other(dbus.service.Object):
    @dbus.service.method("org.vgshell.SelftestOther", out_signature="s")
    def Ping(self):
        note("Ping")
        return "pong"

DBusGMainLoop(set_as_default=True)
session = dbus.SessionBus()
names = [dbus.service.BusName(name, session) for name in ("org.freedesktop.secrets", "org.vgshell.SelftestOther")]
objects = [Service(session, "/org/freedesktop/secrets"), Other(session, "/org/vgshell/SelftestOther")]
note("ready")
GLib.MainLoop().run()
PY
  echo present >"$tmp/keyring-mode"
  env -i PATH="$PATH" dbus-daemon --nofork --config-file="$tmp/bus.xml" >"$tmp/bus.log" 2>&1 &
  bus_pids+=($!)
  for _ in $(seq 1 100); do [[ ! -S $bus ]] || break; sleep 0.1; done
  env -i PATH="$PATH" DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" python3 "$tmp/secrets-service.py" "$tmp/keyring-mode" "$tmp/keyring.calls" \
    service=vgs-jarvis provider=openai account=selftest origin=https://api.openai.com >"$tmp/keyring.log" 2>&1 &
  bus_pids+=($!)
  for _ in $(seq 1 100); do [[ ! -s $tmp/keyring.calls ]] || break; sleep 0.1; done
  if [[ ! -s $tmp/keyring.calls ]]; then fail "the stand-in secrets service did not start: $(tail -n 3 -- "$tmp/bus.log" "$tmp/keyring.log" 2>&1)"; return; fi

  # The two calls the filter must stop, asked of the scratch bus itself
  # first: each reaches the stand-in there.
  other=(org.vgshell.SelftestOther /org/vgshell/SelftestOther org.vgshell.SelftestOther Ping)
  unlock=(org.freedesktop.secrets /org/freedesktop/secrets org.freedesktop.Secret.Service Unlock ao 1 /org/freedesktop/secrets/collection/selftest/1)
  direct() { : >"$tmp/keyring.calls"; env -i PATH="$PATH" DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" busctl --user --auto-start=no --timeout=5 --json=short call "$@" >/dev/null; }
  got() { grep -q -x -e "$1" -- "$tmp/keyring.calls"; }
  other_direct() { direct "${other[@]}" && got Ping; }
  unlock_direct() { direct "${unlock[@]}" && got Unlock; }
  holds "on the scratch bus itself the second name answers" other_direct
  holds "on the scratch bus itself an unlock reaches the stand-in" unlock_direct

  # What a case reads while the run's filter and secret-tool stand: each
  # probe's stdout and status, and the references the sandbox holds.
  cat >"$tmp/at-start.sh" <<SH
probe() { # NAME CMD...
  local name="\$1" answer=0
  shift
  "\$@" >"$tmp/probe.\$name" 2>"$tmp/probe.\$name.err" </dev/null || answer=\$?
  echo "\$answer" >"$tmp/probe.\$name.status"
}
filtered=(env -i PATH="\$PATH" DBUS_SESSION_BUS_ADDRESS="unix:path=\$rt_dir/secrets-bus" busctl --user --auto-start=no --timeout=5 --json=short call)
probe own "\$shim/secret-tool" lookup service vgs-jarvis provider openai account selftest origin https://api.openai.com
probe foreign "\$shim/secret-tool" lookup service vgs-notifications account selftest
probe store "\$shim/secret-tool" store --label=planted service vgs-jarvis
probe other "\${filtered[@]}" ${other[*]}
probe unlock "\${filtered[@]}" ${unlock[*]}
cp -- "\$home/.local/state/vgshell/jarvis/keys.json" "$tmp/probe.keys"
SH
  session_bus=(DBUS_SESSION_BUS_ADDRESS="unix:path=$bus")
  # key_run MODE ARGS...: a run with the keyring in MODE and the stand-in's
  # log emptied first.
  key_run() {
    echo "$1" >"$tmp/keyring-mode"
    shift
    rm -f -- "$tmp"/probe.*
    : >"$tmp/keyring.calls"
    run "$@"
  }
  brain_key=(--type hello --brain "$saved_key")
  answered() { [[ "$(<"$tmp/probe.$1.status")" == "$2" ]]; }
  key_read() { key_run present "${brain_key[@]}" && [[ $status -eq 0 ]] && answered own 0 && [[ "$(<"$tmp/probe.own")" == stand-in-key ]]; }
  key_alone() {
    key_run present "${brain_key[@]}" && [[ "$(tail -n 1 -- "$tmp/harness.log")" == "start_shell " ]] &&
      python3 -c 'import json,sys; saved, world = (json.load(open(a)) for a in sys.argv[1:]); sys.exit(saved != [r for r in world if r["provider"] == "openai"])' "$tmp/probe.keys" "$state/keys.json"
  }
  foreign_stays() { key_run present "${brain_key[@]}" && answered foreign 1 && ! grep -q -F vgs-notifications -- "$tmp/keyring.calls"; }
  store_logged() { key_run present "${brain_key[@]}" && answered store 1 && [[ "$(<"$sandbox/auth.calls")" == "secret-tool store --label=planted service vgs-jarvis" ]]; }
  other_hidden() { key_run present "${brain_key[@]}" && ! answered other 0 && ! got Ping; }
  unlock_denied() { key_run present "${brain_key[@]}" && ! answered unlock 0 && ! got Unlock; }
  plant "$runner"
  holds "Jarvis's own lookup of the run's key reads it through the filter" key_read
  holds "the sandbox holds the reference of the run's key alone, and the shell starts with no account word" key_alone
  holds "a lookup of another key never reaches the bus" foreign_stays
  holds "a store stays the sentinel's, which logs it" store_logged
  holds "the filter hides a bus name other than org.freedesktop.secrets" other_hidden
  holds "the filter refuses an unlock" unlock_denied

  # One table for what the keyring answers before Jarvis starts: the case,
  # the keyring's mode, the session bus the run is given and the run's last
  # line. The run ends 77 with the harness's shell stopped and never
  # started, and no unlock asked.
  key_rows=(
    "a keyring that holds no item for the key|absent|unix:path=$bus|selftest=keyring-no-key key=absent"
    "a keyring that holds the key locked|locked|unix:path=$bus|selftest=keyring-locked"
    "a session bus that is not there|present|unix:path=$tmp/no-bus|selftest=keyring-unavailable"
  )
  key_refused() { # ROW
    local mode address line held=0
    IFS='|' read -r _ mode address line <<<"$1"
    session_bus=(DBUS_SESSION_BUS_ADDRESS="$address")
    key_run "$mode" "${brain_key[@]}"
    [[ $status -eq 77 && "$(tail -n 1 -- "$tmp/out")" == "$line" && "$(<"$tmp/harness.log")" == "harness-reached"$'\n'"stop_shell" ]] && ! got Unlock || held=1
    session_bus=(DBUS_SESSION_BUS_ADDRESS="unix:path=$bus")
    return "$held"
  }
  for row in "${key_rows[@]}"; do holds "${row%%|*} ends as ${row##*|}, exit 77" key_refused "$row"; done

  # The realtime voice: the one saved OpenAI key is its account, and the run
  # needs no prepared local voice.
  voice_named() {
    local held=0
    : >"$tmp/voice.wav"
    inputs=()
    key_run present --wav "$tmp/voice.wav" --brain "$sign_in" --voice realtime
    [[ $status -eq 0 && "$(tail -n 1 -- "$tmp/harness.log")" == "start_shell CLAUDE_CONFIG_DIR=$world/.claude" && ! -e $sandbox/home/.local/share/vgshell/jarvis/local &&
      "$(row_of)" == "[{\"brain\": \"$sign_in\", \"id\": \"vgs.jarvis\", \"microphone\": \"vgs-smoke-voice\", \"mode\": \"toggle\", \"speaker\": \"vgs-smoke-speakers\", \"voiceAccount\": \"$saved_key\", \"voiceProvider\": \"realtime\"}, [\"vgs.jarvis\"]]" ]] || held=1
    inputs=("${voice_inputs[@]}")
    return "$held"
  }
  holds "the realtime voice names the one saved OpenAI key as its account and takes no prepared local voice" voice_named

  mutate "$runner" '      absent) unavailable keyring-no-key key=absent ;;' '      absent) ;;' "$mutant" && plant "$mutant"
  control "a runner that starts Jarvis with no key stored" key_refused "${key_rows[0]}"
  mutate "$runner" '      locked) unavailable keyring-locked ;;' '      locked) ;;' "$mutant" && plant "$mutant"
  control "a runner that starts Jarvis over a locked keyring" key_refused "${key_rows[1]}"
  mutate "$runner" '      unavailable) unavailable keyring-unavailable ;;' '      unavailable) ;;' "$mutant" && plant "$mutant"
  control "a runner that starts Jarvis with no keyring to read" key_refused "${key_rows[2]}"
  mutate "$runner" '"$secrets_bus" --filter "${selftest_secrets_rules[@]}"' '"$secrets_bus"' "$mutant" && plant "$mutant"
  control "a runner whose bus is no filter" other_hidden
  mutate "$runner" '  --call=org.freedesktop.secrets=org.freedesktop.Secret.Service.SearchItems@/org/freedesktop/secrets' '  --talk=org.freedesktop.secrets' "$mutant" && plant "$mutant"
  control "a filter that lets the secrets service's every call through" unlock_denied
  mutate "$runner" 'exec $(printf %q "$(sentinel_saved "$shim/secret-tool")") "\$@"' 'DBUS_SESSION_BUS_ADDRESS=$(printf %q "unix:path=$secrets_bus") exec $(printf %q "$secret_tool") "\$@"' "$mutant" && plant "$mutant"
  control "a secret-tool that sends every call to the bus" foreign_stays
  mutate "$runner" '>"$sandbox/selftest-lookups" || stopped keys-not-saved' '>"$sandbox/selftest-lookups" && cp -- "$HOME/.local/state/vgshell/jarvis/keys.json" "$home/.local/state/vgshell/jarvis/keys.json" || stopped keys-not-saved' "$mutant" && plant "$mutant"
  control "a runner that hands the sandbox every saved reference" key_alone
  mutate "$runner" '    row["voiceAccount"] = voice_account' '    pass' "$mutant" && plant "$mutant"
  control "a runner that names no account for the realtime voice" voice_named
  session_bus=()
  rm -f -- "$tmp/at-start.sh"
}
bus_missing=()
for tool in dbus-daemon xdg-dbus-proxy secret-tool busctl; do command -v -- "$tool" >/dev/null || bus_missing+=("$tool"); done
python3 -c 'import dbus.service, dbus.mainloop.glib; from gi.repository import GLib' 2>/dev/null || bus_missing+=(python-dbus)
if [[ ${#bus_missing[@]} -gt 0 ]]; then
  printf '  not measured: missing=%s\n' "$(IFS=,; echo "${bus_missing[*]}")"
else
  keyring_cases
fi

echo "--- the readers of the service and the trace"
cut_functions "$runner"
service() { printf '{"lifetime": {"kind": "%s"}, "status": {%s}}\n' "$1" "$2"; }
held='"detail": {"phase": "idle", "state": {"settings": {"mode": "toggle", "brain": "b"}}}'
daemon_rows=(
  'absent|absent|{"mode": "toggle"}'
  "daemon=starting|$(service starting "$held")|{\"mode\": \"toggle\"}"
  "detail=none|$(service ready '')|{\"mode\": \"toggle\"}"
  "setting=home|$(service ready "$held")|{\"mode\": \"toggle\", \"brain\": \"b\", \"home\": \"/copy\"}"
  "applied|$(service ready "$held")|{\"mode\": \"toggle\", \"brain\": \"b\"}"
)
daemon_reads() { local want="${1%%|*}" rest="${1#*|}"; [[ "$(call selftest_daemon "${rest#*|}" <<<"${rest%%|*}")" == "$want" ]]; }
for row in "${daemon_rows[@]}"; do holds "the service reader answers ${row%%|*}" daemon_reads "$row"; done
# trace PHASES_BEFORE PHASES_AFTER: phase events around the input mark.
trace() { python3 -c 'import json,sys; before, after = (a.split() for a in sys.argv[1:]); print(json.dumps([{"kind": "phase", "at": i, "value": p} for i, p in enumerate(before)] + [{"kind": "mark", "at": 50, "value": "input"}] + [{"kind": "phase", "at": 60 + i, "value": p} for i, p in enumerate(after)]))' "$1" "$2"; }
turn_rows=(
  "waiting|idle listening|"
  "waiting|thinking speaking idle|"
  "waiting||thinking"
  "waiting|idle|idle"
  "waiting|idle listening|listening"
  "confirming||thinking confirming"
  "waiting||thinking confirming acting"
  "ended=idle||thinking speaking idle"
  "ended=listening|idle listening|thinking speaking listening"
  "ended=error|idle listening|error"
  "ended=down||thinking down"
)
turn_reads() { local want="${1%%|*}" rest="${1#*|}"; [[ "$(trace "${rest%%|*}" "${rest#*|}" | call selftest_turn)" == "$want" ]]; }
for row in "${turn_rows[@]}"; do holds "the turn reader answers ${row%%|*} for phases [${row#*|}]" turn_reads "$row"; done
no_mark() { [[ "$(echo '[{"kind": "phase", "at": 1, "value": "thinking"}, {"kind": "phase", "at": 2, "value": "idle"}]' | call selftest_turn)" == waiting ]]; }
holds "the turn reader waits where the trace holds no input mark" no_mark
mutate "$runner" 'missing = [key for key in want if held.get(key) != want[key]]' 'missing = []' "$mutant" && cut_functions "$mutant"
control "a service reader that compares no setting" daemon_reads "${daemon_rows[3]}"
mutate "$runner" 'or worked and last in' 'or last in' "$mutant" && cut_functions "$mutant"
control "a turn reader that ends before Jarvis worked" turn_reads "${turn_rows[3]}"
mutate "$runner" 'events[marks[0]:]' 'events' "$mutant" && cut_functions "$mutant"
control "a turn reader that counts the phases before the input" turn_reads "${turn_rows[1]}"

echo "--- the record"
cut_functions "$runner"
mkdir -p "$tmp/audit"
cat >"$tmp/audit/2026-10-10.jsonl" <<'JSONL'
{"time": "2026-10-10T00:00:00.000Z", "kind": "action", "gen": 1, "op": 3, "tool": "shell.argv", "args": {"argv": "PLANTED-ARGUMENT"}, "effect": "exec", "decision": "confirm", "confirmed": "none", "outcome": "pending"}
{"time": "2026-10-10T00:00:01.000Z", "kind": "release", "gen": 1, "op": 4, "tool": "release", "args": {}, "effect": null, "decision": "send", "confirmed": "none", "outcome": "completed"}
{"time": "2026-10-10T00:00:02.000Z", "kind": "action", "gen": 1, "op": 3, "tool": "shell.argv", "args": {"argv": "PLANTED-ARGUMENT"}, "effect": "exec", "decision": "confirm", "confirmed": "physical", "outcome": "completed"}
JSONL
# planted_trace USER_FINAL: a turn whose answer grows by two sentences,
# closes its caption segment and opens a second that repeats its first.
planted_trace() {
  python3 - "$tmp/trace.json" "$1" <<'PY'
import json, sys
def caption(at, role, text, stage): return {"kind": "caption", "at": at, "value": {"gen": 1, "role": role, "text": text, "stage": stage, "rev": at}}
events = [{"kind": "widget", "at": 900, "value": "ready"}, {"kind": "phase", "at": 900, "value": "idle"},
          caption(950, "user", "an earlier turn", "final"), caption(960, "assistant", "An earlier answer.", "final"),
          {"kind": "mark", "at": 1000, "value": "input"}, {"kind": "widget", "at": 1040, "value": "live"},
          caption(1100, "user", "what time", "partial")]
if sys.argv[2] == "final":
    events.append(caption(1200, "user", "What time is it?", "final"))
events += [{"kind": "widget", "at": 1250, "value": "working"}, caption(2000, "assistant", "It is noon.", "partial"),
           caption(2500, "assistant", "It is noon. Anything else?", "partial"), caption(2600, "assistant", "It is noon. Anything else?", "final"),
           caption(3000, "assistant", "It is noon.", "partial"), {"kind": "widget", "at": 3100, "value": "ready"}]
json.dump(events, open(sys.argv[1], "w"))
PY
}
record() { # END UNCHANGED → the verdict word; the record in record.json
  call selftest_record "$tmp/trace.json" "$tmp/audit" "$tmp/record.json" "$1" idle "" wav /voice.wav cli:b "/a home" local key "$2"
}
record_holds() {
  planted_trace final
  [[ "$(record completed true)" == passed ]] || return 1
  python3 - "$tmp/record.json" <<'PY'
import json, sys
want = {"input": {"kind": "wav", "value": "/voice.wav"}, "brain": "cli:b", "home": "/a home", "voice": "local", "confirm": "key",
        "heard": "What time is it?",
        "sentences": [{"ms": 1000, "text": "It is noon."}, {"ms": 1500, "text": "Anything else?"}, {"ms": 2000, "text": "It is noon."}],
        "tools": [{"tool": "shell.argv", "decision": "confirm", "confirmed": "none", "outcome": "pending"},
                  {"tool": "shell.argv", "decision": "confirm", "confirmed": "physical", "outcome": "completed"}],
        "widget": [{"ms": -100, "state": "ready"}, {"ms": 40, "state": "live"}, {"ms": 250, "state": "working"}, {"ms": 2100, "state": "ready"}],
        "end": {"kind": "completed", "phase": "idle", "fault": None}, "passed": True}
got = json.load(open(sys.argv[1]))
if got != want:
    print("        got:  " + json.dumps(got, sort_keys=True) + "\n        want: " + json.dumps(want, sort_keys=True))
    sys.exit(1)
PY
}
names_only() { planted_trace final; record completed true >/dev/null && ! grep -q -F PLANTED-ARGUMENT -- "$tmp/record.json"; }
# One table for the mark: END, UNCHANGED and the user's final caption.
failed_rows=("timeout true final" "fault true final" "gate-down true final" "completed false final" "completed true none")
not_passed() { # "END UNCHANGED USER_FINAL"
  local end unchanged final
  read -r end unchanged final <<<"$1"
  planted_trace "$final"
  [[ "$(record "$end" "$unchanged")" == failed && "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["passed"])' "$tmp/record.json")" == False ]]
}
holds "the record holds the heard text, each released sentence, each tool call's names, the widget states and the end" record_holds
holds "the record holds no argument of a tool call" names_only
for row in "${failed_rows[@]}"; do holds "a record for [$row] is not marked passed" not_passed "$row"; done
mutate "$runner" 'tools.append({key: row[key] for key in ("tool", "decision", "confirmed", "outcome")})' 'tools.append(row)' "$mutant" && cut_functions "$mutant"
control "a record that keeps the audit record whole" names_only
for conjunct in 'end == "completed" and ' 'heard is not None and ' ' and unchanged == "true"'; do
  mutate "$runner" "$conjunct" '' "$mutant" && cut_functions "$mutant"
  red=0
  for row in "${failed_rows[@]}"; do not_passed "$row" || red=$((red + 1)); done
  if [[ $red -gt 0 ]]; then ok "control: a mark without [${conjunct}] turns $red row(s) red"; else fail "control: a mark without [${conjunct}] stayed green"; fi
done

if [[ $failures -gt 0 ]]; then
  printf 'test-jarvis-selftest: %d failure(s)\n' "$failures"
  exit 1
fi
if [[ ${#bus_missing[@]} -gt 0 ]]; then
  printf 'test-jarvis-selftest: status=not-measured missing=%s\n' "$(IFS=,; echo "${bus_missing[*]}")"
  exit 77
fi
echo "test-jarvis-selftest: ok"
