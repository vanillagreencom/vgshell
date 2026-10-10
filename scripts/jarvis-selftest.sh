#!/usr/bin/env bash
# Run one real Jarvis turn in the nested sandbox and write one record of it.
#
# Usage: scripts/jarvis-selftest.sh (--wav FILE | --tts TEXT | --type TEXT)
#                                   --brain ID [--home PATH]
#                                   [--voice local|realtime]
#                                   [--confirm key|none] [--out FILE]
#
# The sandbox is the smoke's own (scripts/smoke/harness.sh), with the
# checkout's Jarvis plugin put back over the harness's instrumented copy, so
# the daemon, its engine, its speech sidecar and its audio children are the
# shipped ones and run as in a session: nothing is scripted or stood in.
# The rules this run keeps are docs/architecture/validation.md § Jarvis
# self-test.
#
# The input is one of:
#   --wav FILE   a recorded voice, played into the sandbox PipeWire's voice
#                feed (scripts/smoke/devices.sh), whose source side is the
#                microphone Jarvis records with its own pw-record. The feed
#                starts only once the bar widget reads the microphone open
#                and a capture stream reads that source.
#   --tts TEXT   the same, over a WAV the pinned voice that made the plugin's
#                probe.wav speaks from TEXT (fixtures/PROVENANCE).
#   --type TEXT  the line sent through the plugin's `say` IPC handler.
# A voice input opens the conversation through the service's Talk intent, in
# Toggle talk mode, so the engine's own end-of-speech judge commits the turn.
#
# --brain ID is an account id the Jarvis AI model list offers. A sign-in
# account's own directory variable is the one value of the caller's
# environment that enters the sandbox.
# --voice realtime listens and speaks through OpenAI's Realtime session with
# the caller's one saved OpenAI key, the key the plugin's Accounts page
# chooses by itself; local, the default, is the prepared local voice below.
# A saved key, the brain's or the realtime voice's, is read under the
# owner's exception in docs/architecture/validation.md § Jarvis self-test.
# Its reference, which holds no secret, is saved in the sandbox by the
# plugin's own writer. Jarvis's own `secret-tool lookup` of it goes to the
# caller's session bus through a filter, an xdg-dbus-proxy that passes the
# calls a lookup of an unlocked key makes to org.freedesktop.secrets and
# nothing else: no other bus name and no unlock, so a locked keyring fails
# the lookup and shows no prompt. Before Jarvis starts, the run reads
# through that filter whether each key is there and unlocked.
# --home PATH copies that folder into the sandbox's HOME and names the copy
# as the Jarvis home folder; the folder itself is read twice, for its
# checksums before and after, and never written.
# --confirm key confirms each request Jarvis shows as its Confirm key does,
# with one press a request, made once Session's draw guard has passed;
# none, the default, answers none, so a request ends on Jarvis's own bound.
# --out FILE is the record; the default is a new file under
# tmp/selftest-records/.
#
# The local voice and the --tts speaker run from prepared inputs: JARVIS_LOCAL_MODELS and
# JARVIS_LOCAL_PYTHON name the models and the interpreter of one setup the
# plugin's own setup-local made under a scratch HOME,
# <HOME>/.local/share/vgshell/jarvis/local/models and
# .../local/venv/bin/python, and the run reads that setup's ready marker,
# <HOME>/.local/state/vgshell/jarvis/local-ready.json.
#
# The record is one JSON object: `input` {kind, value}, `brain`, `home`,
# `voice`, `confirm`, `heard` (the text Session committed as the user turn),
# `sentences` (each sentence released to speech as {ms, text}; with --voice
# realtime, whose transcript of its own speech arrives in fragments, each
# assistant caption segment whole as {ms of its first words, text}), `tools`
# (each audit record of a tool call as {tool, decision, confirmed, outcome},
# names only), `widget` (each bar widget state as {ms, state}), `end`
# {kind, phase, fault} and `passed`. Every ms counts from the input's start
# on the shell's own clock. `end.kind` is completed, fault, gate-down or
# timeout; `passed` is true only for a completed turn with a heard text, in
# a run whose --home folder, when named, reads as before, that reached no
# authentication stand-in and failed no sandbox check.
#
# The last line is `selftest=<key>`: `selftest=<end.kind> record=<file>`
# after a turn, else the reason no turn ran. Exit 0 for a passed record, 1
# for any other record or a failed step, 2 for a refused argument, and 77
# when the run could not run, which is never a pass:
#   selftest=keyring-no-key            no key is stored: `key=unsaved` where
#                                      no OpenAI key is saved for the realtime
#                                      voice, `key=absent` where the keyring
#                                      holds no item for a saved one
#   selftest=keyring-locked            the keyring holds the key locked
#   selftest=keyring-unavailable       no session bus, no keyring on it, or a
#                                      program the read needs, `missing=`
#   selftest=local-inputs-unavailable  no prepared local voice
#   selftest=account-judge-unavailable no node to run the plugin's judge
#   selftest=devices-unavailable       the device fakes' prerequisites
# or the harness's own `qml-smoke: status=not-measured` line.
# The turn's bound, 300 s, bounds a missing observation; it is no latency
# budget.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"

# selftest_accounts TREE BRAIN VOICE: two lines from TREE's own account
# judge over the caller's folders and saved references, with no vendor
# command and no keyring call. The first is the account BRAIN names:
# `cli<TAB>VARIABLE<TAB>DIRECTORY` for a sign-in, VARIABLE its harness's
# directory variable; `keyring<TAB>REFERENCE` for a saved key, REFERENCE its
# reference as JSON, which holds no secret; `local` for a model server on
# this computer; `unknown`. The second is the key of the voice VOICE: `local`
# for the local voice, else `keyring<TAB>ID<TAB>REFERENCE` for the one saved
# OpenAI key, `none` with no such key and `several` with more than one.
selftest_accounts() { # TREE BRAIN VOICE
  local name words=()
  for name in HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME CLAUDE_CONFIG_DIR CODEX_HOME COPILOT_HOME PI_CODING_AGENT_DIR; do
    [[ -z ${!name:-} ]] || words+=("$name=${!name}")
  done
  env -i PATH="$PATH" "${words[@]}" "$selftest_node" - "$@" <<'JS'
    const path = require("node:path");
    const [tree, id, voice] = process.argv.slice(2);
    const Core = require(path.join(tree, "shell/plugins/vgs.jarvis/backend/Core.js"));
    Core.use(tree);
    const { Accounts } = require(path.join(tree, "shell/plugins/vgs.jarvis/backend/Accounts.js"));
    const state = path.join(process.env.XDG_STATE_HOME || path.join(process.env.HOME, ".local/state"), "vgshell/jarvis");
    const judge = new Accounts(state, process.env);
    const line = (...words) => console.log(words.join("\t"));
    const found = judge.resolve(id);
    if (found === null) line("unknown");
    else if (found.source.kind === "cli") line("cli", Core.accounts().harness(found.provider).variable, found.source.directory);
    else if (found.source.kind === "keyring") line("keyring", JSON.stringify(found.source.reference));
    else line(found.source.kind);
    const keys = voice === "local" ? [] : judge.keyringRows().filter(key => key.row.id === "openai");
    if (voice === "local") line("local");
    else if (keys.length !== 1) line(keys.length === 0 ? "none" : "several");
    else line("keyring", judge.account(keys[0].row, keys[0].label, { kind: "found" }, keys[0].source).id, JSON.stringify(keys[0].source.reference));
JS
}

# The filtered secrets bus's rules: the four calls `secret-tool lookup` of
# libsecret 0.21.8 makes for an unlocked key, SearchItems the plugin's
# presence read too, as `xdg-dbus-proxy --log` 0.1.9 listed them on a scratch
# bus on 2026-10-09. A name given calls alone has no talk right, so the
# service's Unlock and its prompts answer AccessDenied there, and every
# other name reads as having no owner.
selftest_secrets_rules=(
  --call=org.freedesktop.secrets=org.freedesktop.Secret.Service.SearchItems@/org/freedesktop/secrets
  --call=org.freedesktop.secrets=org.freedesktop.Secret.Service.OpenSession@/org/freedesktop/secrets
  --call=org.freedesktop.secrets=org.freedesktop.Secret.Service.GetSecrets@/org/freedesktop/secrets
  --call=org.freedesktop.secrets=org.freedesktop.DBus.Properties.GetAll@/org/freedesktop/secrets
)

# selftest_key_presence TREE BUS REFERENCE: whether the keyring on the bus
# BUS holds the key REFERENCE names, as TREE's own key judge reads it with
# no unlock: present, locked, absent or unavailable.
selftest_key_presence() { # TREE BUS REFERENCE
  env -i PATH="$PATH" DBUS_SESSION_BUS_ADDRESS="$2" "$selftest_node" - "$1" "$3" <<'JS'
    const path = require("node:path");
    const [tree, reference] = process.argv.slice(2);
    const { Secrets } = require(path.join(tree, "shell/plugins/vgs.jarvis/backend/Secrets.js"));
    console.log(new Secrets(tree, process.env).presence(JSON.parse(reference)).value);
JS
}

# selftest_keys_save TREE STATE REFERENCE...: each REFERENCE saved under the
# Jarvis state folder STATE by TREE's own writer, and printed as the words
# Jarvis's `secret-tool lookup` of it carries, joined by the unit separator,
# a character no word of a reference holds.
selftest_keys_save() { # TREE STATE REFERENCE...
  env -i PATH="$PATH" "$selftest_node" - "$@" <<'JS'
    const path = require("node:path");
    const [tree, state, ...references] = process.argv.slice(2);
    const { Secrets } = require(path.join(tree, "shell/plugins/vgs.jarvis/backend/Secrets.js"));
    const secrets = new Secrets(state, process.env);
    for (const reference of references) console.log(secrets.attributes(secrets.remember(JSON.parse(reference))).join("\x1f"));
JS
}

# selftest_local_inputs: the prepared local voice the header names, as its
# data root and its ready marker, one a line. Returns 1 when a variable is
# unset or a part is absent.
selftest_local_inputs() {
  local models="${JARVIS_LOCAL_MODELS:-}" python="${JARVIS_LOCAL_PYTHON:-}" root marker
  [[ -n $models && -n $python && -d $models && -x $python ]] || return 1
  root="$(cd -- "$models/.." && pwd -P)" || return 1
  [[ $models -ef $root/models && $python -ef $root/venv/bin/python ]] || return 1
  marker="$root/../../../../state/vgshell/jarvis/local-ready.json"
  [[ -f $marker ]] || return 1
  printf '%s\n%s\n' "$root" "$(readlink -f -- "$marker")"
}

# selftest_speak PLUGIN ROOT TEXT OUT: TEXT spoken into the WAV OUT by the
# pinned voice that made PLUGIN's probe.wav, loaded by PLUGIN's own artifact
# judge from the prepared setup ROOT, in a network namespace as the plugin's
# sidecar runs, with OUT's directory as its HOME. Exit 77 when ROOT holds
# no such voice.
selftest_speak() { # PLUGIN ROOT TEXT OUT
  env -i PATH="$PATH" HOME="$(dirname -- "$4")" LC_ALL=C.UTF-8 unshare --map-current-user --net -- \
    "$2/venv/bin/python" -I - "$1" "$2/models" "$3" "$4" <<'PY'
import importlib.machinery, importlib.util, sys, wave
from pathlib import Path
plugin, models, text, out = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], sys.argv[4]
loader = importlib.machinery.SourceFileLoader("jarvis_measure", str(plugin / "measure-local"))
judge = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(judge)
voice = next(a for a in judge.manifest(plugin / "artifacts.json")["artifacts"] if a["id"] == "piper")
if not (models / voice["directory"]).is_dir():
    sys.exit(77)
import numpy as np
import sherpa_onnx as sherpa
audio = judge.load(voice, models, "cpu", np, sherpa).generate(text, sid=0, speed=1)
samples = np.clip(np.asarray(audio.samples), -1, 1)
with wave.open(out, "wb") as file:
    file.setnchannels(1)
    file.setsampwidth(2)
    file.setframerate(audio.sample_rate)
    file.writeframes((samples * 32767).astype("<i2").tobytes())
PY
}

# selftest_tree_sum DIR: one checksum over every entry under DIR, its type,
# its link target and each regular file's bytes, so a file added, removed or
# changed under DIR changes it.
selftest_tree_sum() { # DIR
  (cd -- "$1" && find . -printf '%y %p %l\n' -type f -exec sha256sum -- {} + | LC_ALL=C sort | sha256sum | cut -d' ' -f1)
}

# selftest_home_copy SOURCE DEST: DEST made as a copy of the folder SOURCE
# that shares no file with it, links kept as links.
selftest_home_copy() { # SOURCE DEST
  cp -a -- "$1" "$2"
}

# selftest_daemon WANT_JSON: `applied` once the Jarvis service on stdin, the
# probe's jarvisProcess reply, is ready and its Session holds every setting
# of WANT_JSON; else the first thing still missing: the probe's own word,
# `daemon=<lifetime>`, `detail=none` or `setting=<key>`.
selftest_daemon() { # WANT_JSON
  py_reply '
import json, sys
service, want = json.load(sys.stdin), json.loads(sys.argv[1])
detail = service["status"].get("detail")
held = detail["state"]["settings"] if detail else {}
missing = [key for key in want if held.get(key) != want[key]]
print("daemon=" + service["lifetime"]["kind"] if service["lifetime"]["kind"] != "ready" else "detail=none" if not detail else "setting=" + missing[0] if missing else "applied")
' "$1"
}

# selftest_last KIND: the last value of KIND, widget or phase, in the
# probe's trace on stdin, `none` before the first.
selftest_last() { # KIND
  py_reply '
import json, sys
values = [e["value"] for e in json.load(sys.stdin) if e["kind"] == sys.argv[1]]
print(values[-1] if values else "none")
' "$1"
}

# selftest_turn: the turn's progress, from the Session phases after the
# `input` mark in the probe's trace on stdin: `ended=<phase>` once Jarvis has
# worked and rests again (idle, listening or armed), or a fault or the gate
# stopped it (error, down); `confirming` while a request waits for the
# user; else `waiting`.
selftest_turn() {
  py_reply '
import json, sys
events = json.load(sys.stdin)
marks = [i for i, e in enumerate(events) if e["kind"] == "mark" and e["value"] == "input"]
phases = [e["value"] for e in events[marks[0]:] if e["kind"] == "phase"] if marks else []
last = phases[-1] if phases else ""
worked = any(phase in ("thinking", "speaking", "acting", "confirming") for phase in phases)
ended = last in ("error", "down") or worked and last in ("idle", "listening", "armed")
print("ended=" + last if ended else "confirming" if last == "confirming" else "waiting")
'
}

# selftest_wait SECONDS WANT CMD...: CMD's answer polled every 0.2 s until
# it is WANT, for SECONDS at most; the last answer is left in `reading`.
selftest_wait() { # SECONDS WANT CMD...
  local until=$((SECONDS + $1)) want="$2"
  shift 2
  while :; do
    reading="$("$@")" || reading=unread
    [[ $reading != "$want" ]] || return 0
    ((SECONDS < until)) || return 1
    sleep 0.2
  done
}

# selftest_draw_ms TREE: Session's draw guard in milliseconds, from TREE's
# own Session.js: how long after a request is shown Session refuses a
# confirm of it as early.
selftest_draw_ms() { # TREE
  env -i "$selftest_node" - "$1" <<'JS'
    const path = require("node:path");
    const [tree] = process.argv.slice(2);
    const { load } = require(path.join(tree, "bin/lib/qml-library.js"));
    const bound = load(path.join(tree, "shell/plugins/vgs.jarvis/Session.js")).APPROVAL_DRAW_MS;
    if (!Number.isSafeInteger(bound) || bound < 0) process.exit(1);
    console.log(bound);
JS
}

# selftest_shown: the request Jarvis holds and has shown, from the probe's
# jarvisProcess reply on stdin, as `<gen>:<id>`; `none` with no request held
# or one Session has no shown time for yet.
selftest_shown() {
  py_reply '
import json, sys
detail = json.load(sys.stdin)["status"].get("detail")
held = detail["state"]["approval"] if detail else {"kind": "none"}
print("%s:%s" % (held["gen"], held["id"]) if held["kind"] == "held" and held["shownAt"] is not None else "none")
'
}

# selftest_confirm DRAW_MS NOW_MS REQUEST: the Confirm key pressed once for
# REQUEST, selftest_shown's word, and no sooner than DRAW_MS after this run
# first read it as shown, which is later than the time Session counts from.
# Session refuses an earlier press and the audit records that as a refused
# tool call, which the record would list as Jarvis's own refusal. A press
# the probe did not send is made again at a later call. `confirm_seen`,
# `confirm_seen_ms` and `confirm_pressed` carry the request between calls.
selftest_confirm() { # DRAW_MS NOW_MS REQUEST
  local reply
  [[ $3 == *:* && $3 != "${confirm_pressed:-}" ]] || return 0
  if [[ $3 != "${confirm_seen:-}" ]]; then confirm_seen="$3" confirm_seen_ms="$2"; fi
  (($2 - confirm_seen_ms >= $1)) || return 0
  reply="$(ipc smoke jarvisConfirm)" || return 0
  [[ $reply != sent ]] || confirm_pressed="$3"
}

# selftest_end TURN: the record's end.kind for selftest_turn's last word: a
# turn a fault stopped is fault, one the gate stopped is gate-down, any
# other ended turn is completed, and a turn that never ended is timeout.
selftest_end() { # TURN
  case "$1" in
    ended=error) echo fault ;;
    ended=down) echo gate-down ;;
    ended=*) echo completed ;;
    *) echo timeout ;;
  esac
}

# selftest_record TRACE AUDIT OUT PHASE FAULT KIND VALUE BRAIN HOME VOICE
# CONFIRM END KEPT: the record the header describes, written to OUT by
# rename, from the probe's trace in the file TRACE and the audit records
# under AUDIT, which may be absent. HOME is "" for none, END is
# selftest_end's word and KEPT says whether the run kept every rule
# selftest_finish reads. Prints `passed` or `failed`.
selftest_record() {
  python3 - "$@" <<'PY'
import json, os, sys
trace, audit, out, phase, fault, kind, value, brain, home, voice, confirm, end, kept = sys.argv[1:]
events = json.load(open(trace))
first = next(i for i, e in enumerate(events) if e["kind"] == "mark" and e["value"] == "input")
start = events[first]["at"]
heard, sentences, shown, segment = None, [], "", None
for event in events[first:]:
    if event["kind"] != "caption":
        continue
    caption = event["value"]
    if caption["role"] != "assistant":
        if heard is None and caption["stage"] == "final":
            heard = caption["text"]
        shown, segment = "", None
        continue
    text = caption["text"]
    if voice == "realtime":
        # Realtime.js writes a segment once for each fragment of the voice's
        # transcript, so a write is no sentence: the segment is one entry,
        # timed at its first write and holding its last.
        if segment is None and text.strip():
            segment = {"ms": event["at"] - start, "text": ""}
            sentences.append(segment)
        if segment is not None:
            segment["text"] = text.strip()
        if caption["stage"] == "final":
            segment = None
        continue
    # ChainedEngine.js grows a segment by one released sentence a write.
    new = (text[len(shown):] if text.startswith(shown) else text).strip()
    if new:
        sentences.append({"ms": event["at"] - start, "text": new})
    shown = "" if caption["stage"] == "final" else text
tools = []
for name in sorted(os.listdir(audit)) if os.path.isdir(audit) else []:
    for line in open(os.path.join(audit, name)):
        row = json.loads(line)
        if row["kind"] == "action":
            tools.append({key: row[key] for key in ("tool", "decision", "confirmed", "outcome")})
passed = end == "completed" and heard is not None and kept == "true"
record = {"input": {"kind": kind, "value": value}, "brain": brain, "home": home or None, "voice": voice,
          "confirm": confirm, "heard": heard, "sentences": sentences, "tools": tools,
          "widget": [{"ms": e["at"] - start, "state": e["value"]} for e in events if e["kind"] == "widget" and e["value"]],
          "end": {"kind": end, "phase": phase, "fault": fault or None}, "passed": passed}
with open(out + ".next", "w") as file:
    json.dump(record, file, indent=2, ensure_ascii=False)
    file.write("\n")
os.replace(out + ".next", out)
print("passed" if passed else "failed")
PY
}

argv=("$@")
input_kind=""
input_value=""
brain=""
home_source=""
voice=local
confirm=none
out=""
refuse() { printf 'jarvis-selftest: refused: %s\n' "$*" >&2; exit 2; }
# unavailable KEY...: the run could not run, which is never a pass.
unavailable() { printf 'selftest=%s\n' "$*"; exit 77; }
# stopped KEY...: a step of the run failed before it had a record. The
# shell's log, which holds the service's keyed causes, is shown when there
# is one.
stopped() {
  [[ -z ${instance_log:-} ]] || { echo "--- instance log tail"; tail -n 25 -- "$instance_log" || true; }
  printf 'selftest=%s\n' "$*"
  exit 1
}
# selftest_finish TURN HOME_SUM AUTH_LOG FAILURES TRACE AUDIT OUT PHASE FAULT
# KIND VALUE BRAIN HOME VOICE CONFIRM: the run's one verdict. It reads what
# the run broke outside its turn: the folder HOME, when named, no longer
# sums to HOME_SUM; an authentication stand-in was reached, a keyring store
# or unlock among them (harness.sh's sentinels), which AUTH_LOG lists; the
# harness counted FAILURES failed sandbox checks. selftest_record gets that
# with the end of the turn TURN, selftest_turn's last word, so the record's
# `passed` and the exit status are one answer. Prints a line for each rule
# broken, then the run's last line, and exits 0 for a passed record and 1
# for any other.
selftest_finish() {
  local turn="$1" home_sum="$2" auth_log="$3" failures="$4" out="$7" home_source="${13}" end sum kept=true verdict
  end="$(selftest_end "$turn")"
  if [[ -n $home_source ]]; then
    sum="$(selftest_tree_sum "$home_source")" || stopped home-unread
    [[ $sum == "$home_sum" ]] || { kept=false; printf 'selftest: the home folder changed during the run: %s\n' "$home_source"; }
  fi
  if [[ -s $auth_log ]]; then kept=false; printf 'selftest: an authentication stand-in was reached: %s\n' "$auth_log"; sed 's/^/        /' -- "$auth_log"; fi
  [[ $failures -eq 0 ]] || { kept=false; printf 'selftest: %s sandbox check(s) failed above\n' "$failures"; }
  mkdir -p -- "$(dirname -- "$out")"
  verdict="$(selftest_record "${@:5}" "$end" "$kept")" || stopped record-not-written
  printf 'selftest=%s record=%s\n' "$end" "$out"
  [[ $verdict == passed ]] || exit 1
  exit 0
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --wav|--tts|--type)
      [[ $# -ge 2 && -n $2 ]] || refuse "argument=$1 value=${2-}"
      [[ -z $input_kind ]] || refuse "argument=$1 reason=one-input"
      input_kind="${1#--}"; input_value="$2"; shift 2 ;;
    --brain|--home|--out)
      [[ $# -ge 2 && -n $2 ]] || refuse "argument=$1 value=${2-}"
      case "$1" in --brain) brain="$2" ;; --home) home_source="$2" ;; --out) out="$2" ;; esac
      shift 2 ;;
    --voice)
      [[ $# -ge 2 && $2 =~ ^(local|realtime)$ ]] || refuse "argument=--voice value=${2-}"
      voice="$2"; shift 2 ;;
    --confirm)
      [[ $# -ge 2 && $2 =~ ^(key|none)$ ]] || refuse "argument=--confirm value=${2-}"
      confirm="$2"; shift 2 ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *) refuse "argument=$1" ;;
  esac
done
[[ -n $input_kind ]] || refuse "argument=input reason=missing want=--wav|--tts|--type"
[[ -n $brain ]] || refuse "argument=--brain reason=missing"
if [[ $input_kind == wav ]]; then
  [[ -f $input_value && -r $input_value ]] || refuse "argument=--wav value=$input_value reason=unreadable"
  input_value="$(readlink -f -- "$input_value")"
fi
if [[ -n $home_source ]]; then
  [[ -d $home_source ]] || refuse "argument=--home value=$home_source reason=not-a-directory"
  home_source="$(cd -- "$home_source" && pwd -P)"
fi
[[ -n $out ]] || out="$repo/tmp/selftest-records/selftest-$(date -u +%Y%m%dT%H%M%SZ).json"

# node on PATH may be a version manager's shim, which fails under an
# environment that is not the caller's; a child runs the binary itself.
selftest_node="$(node -e 'process.stdout.write(process.execPath)')" || unavailable account-judge-unavailable missing=node
accounts="$(selftest_accounts "$repo" "$brain" "$voice")" || stopped account-unread
{ IFS=$'\t' read -r brain_kind brain_first brain_second; IFS=$'\t' read -r voice_kind voice_account voice_reference; } <<<"$accounts"
account_word=()
key_references=()
case "$brain_kind" in
  unknown) refuse "argument=--brain value=$brain reason=unknown-account" ;;
  cli) account_word=("$brain_first=$brain_second") ;;
  keyring) key_references+=("$brain_first") ;;
esac
case "$voice_kind" in
  none) unavailable keyring-no-key key=unsaved ;;
  several) refuse "argument=--voice value=realtime reason=several-openai-keys" ;;
  # A brain that is this same key has named it already.
  keyring) [[ ${key_references[*]:-} == "$voice_reference" ]] || key_references+=("$voice_reference") ;;
esac
# What a key read needs, asked before anything starts.
if [[ ${#key_references[@]} -gt 0 ]]; then
  [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || unavailable keyring-unavailable missing=session-bus
  for tool in xdg-dbus-proxy secret-tool busctl; do
    command -v -- "$tool" >/dev/null || unavailable keyring-unavailable "missing=$tool"
  done
  secret_tool="$(command -v -- secret-tool)"
fi
# The prepared local voice is the local voice's and the --tts speaker's.
local_root=""
if [[ $voice == local || $input_kind == tts ]]; then
  local_inputs="$(selftest_local_inputs)" || unavailable local-inputs-unavailable
  { read -r local_root; read -r local_marker; } <<<"$local_inputs"
fi

# No process this run starts may open an amdgpu node, so the run goes on
# only where none is visible: scripts/smoke/gpu-fence.sh.
"$repo/scripts/smoke/gpu-fence.sh" --check || exec "$repo/scripts/smoke/gpu-fence.sh" "$self" "${argv[@]}"

# shellcheck disable=SC2034 # the harness sourced below reads both
keep=false timeout_s=60
source "$repo/scripts/smoke/harness.sh"
# From here $repo is the sandbox's copy and $source_repo the checkout.
plugin="$source_repo/shell/plugins/vgs.jarvis"
draw_ms=0
if [[ $confirm == key ]]; then draw_ms="$(selftest_draw_ms "$source_repo")" || stopped draw-guard-unread; fi

if [[ $input_kind == tts ]]; then
  wav="$sandbox/selftest-input.wav"
  status=0
  selftest_speak "$plugin" "$local_root" "$input_value" "$wav" || status=$?
  [[ $status -ne 77 ]] || unavailable local-inputs-unavailable
  [[ $status -eq 0 ]] || stopped tts-failed "exit=$status"
elif [[ $input_kind == wav ]]; then
  wav="$input_value"
fi

# The harness's shell started over its instrumented Jarvis copy and without
# the account. The checkout's plugin goes back whole, then the run's own
# shell starts with the account's variable as its one extra word.
stop_shell || stopped shell-not-stopped
rm -rf -- "${repo:?}/shell/plugins/vgs.jarvis"
cp -R -- "$plugin" "$repo/shell/plugins/vgs.jarvis"
install -d -m 700 -- "$home/.local/share/vgshell/jarvis" "$home/.local/state/vgshell/jarvis"
if [[ $voice == local ]]; then
  # The prepared setup's marker names its own data root, so the sandbox's
  # data root is a link to it and the sidecar's readiness judge reads the
  # setup where setup-local made it.
  ln -s -- "$local_root" "$home/.local/share/vgshell/jarvis/local"
  cp -- "$local_marker" "$home/.local/state/vgshell/jarvis/local-ready.json"
fi
if [[ ${#key_references[@]} -gt 0 ]]; then
  # The filter runs with no environment and ends with the harness's other
  # children. Its socket is there once it listens.
  secrets_bus="$rt_dir/secrets-bus"
  spawn "$sandbox/secrets-bus.log" env -i "$(command -v -- xdg-dbus-proxy)" "$DBUS_SESSION_BUS_ADDRESS" "$secrets_bus" --filter "${selftest_secrets_rules[@]}"
  secrets_bus_state() { if [[ -S $secrets_bus ]]; then echo listening; else echo absent; fi; }
  selftest_wait 10 listening secrets_bus_state || stopped secrets-bus-not-started "$sandbox/secrets-bus.log"
  for reference in "${key_references[@]}"; do
    presence="$(selftest_key_presence "$source_repo" "unix:path=$secrets_bus" "$reference")" || stopped key-unread
    case "$presence" in
      present) ;;
      locked) unavailable keyring-locked ;;
      absent) unavailable keyring-no-key key=absent ;;
      unavailable) unavailable keyring-unavailable ;;
      *) stopped key-unread "$presence" ;;
    esac
  done
  selftest_keys_save "$source_repo" "$home/.local/state/vgshell/jarvis" "${key_references[@]}" >"$sandbox/selftest-lookups" || stopped keys-not-saved
  # Jarvis's lookups of the run's own keys go to the filtered bus. Every
  # other call stays the harness's sentinel's, which answers a read with
  # nothing stored and logs a store, a clear or an unlock.
  sentinel_stand_over "$shim/secret-tool" <<SH || stopped secret-tool-not-stood-over
#!/usr/bin/env bash
asked="\$(IFS=\$'\x1f'; printf '%s' "\$*")"
while IFS= read -r own; do
  [[ \$asked != lookup\$'\x1f'"\$own" ]] || DBUS_SESSION_BUS_ADDRESS=$(printf %q "unix:path=$secrets_bus") exec $(printf %q "$secret_tool") "\$@"
done <$(printf %q "$sandbox/selftest-lookups")
exec $(printf %q "$(sentinel_saved "$shim/secret-tool")") "\$@"
SH
fi
home_copy=""
home_sum=""
if [[ -n $home_source ]]; then
  # Jarvis holds a home folder only inside the user's home directory
  # (Home.js resolve), so the copy lies in the sandbox's HOME.
  home_copy="$home/jarvis-home"
  home_sum="$(selftest_tree_sum "$home_source")" || stopped home-unread
  selftest_home_copy "$home_source" "$home_copy" || stopped home-not-copied
fi
# The settings Jarvis starts with, written while it is still disabled.
# Speech plays to a null sink and never into the feed, and the microphone is
# the feed's source by name, whatever WirePlumber's defaults are.
settings="$(python3 - "$home/.config/vgshell/shell.json" "$brain" "$devices_voice_feed_source" "$home_copy" "$voice" "${voice_account:-}" <<'PY'
import json, sys
path, brain, microphone, home, voice, voice_account = sys.argv[1:]
config = json.load(open(path))
row = {"mode": "toggle", "brain": brain, "voiceProvider": voice, "microphone": microphone, "speaker": "vgs-smoke-speakers"}
if voice_account:
    row["voiceAccount"] = voice_account
if home:
    row["home"] = home
config["plugins"] = [r for r in config["plugins"] if r["id"] != "vgs.jarvis"] + [dict(row, id="vgs.jarvis")]
json.dump(config, open(path, "w"))
print(json.dumps(row))
PY
)" || stopped settings-not-written

status=0
devices_up || status=$?
[[ $status -ne 77 ]] || unavailable devices-unavailable "$devices_state"
[[ $status -eq 0 ]] || stopped devices-failed "$devices_state"
# The feed's two sides are there before Jarvis starts, with no reader yet.
selftest_wait 10 absent=recorder devices_voice_feed_state || stopped no-voice-feed "$reading"
start_shell "$repo" "$sandbox/selftest-shell.log" bar "${account_word[@]}" || stopped shell-not-started
# The owner's microphone, speakers and buses stay out of reach: the guard
# reads the shell every Jarvis process descends from.
guard="$(devices_guard "$shell_qs_pid")" || stopped device-guard unreadable
[[ $guard == inside ]] || stopped device-guard "$guard"

# Enabled as a user enables it, so the core places its widget in the bar.
reply="$(ipc shell setPluginEnabled vgs.jarvis true)" || reply=unread
[[ $reply == ok ]] || stopped jarvis-not-enabled "$reply"
bar="$(bar_key)" || stopped bar-unread
daemon_applied() { ipc smoke jarvisProcess | selftest_daemon "$settings"; }
widget_state() { ipc smoke readInstance "$bar" vgs.jarvis view | py_reply 'import json,sys; print(json.load(sys.stdin)["state"])'; }
traced() { ipc smoke jarvisTrace | selftest_last "$1"; }
# The sidecar loads its models before the gate comes up: LocalSpeech.js
# gives it 60 s, and this wait bounds that and the account check.
selftest_wait 120 applied daemon_applied || stopped not-ready "$reading"
selftest_wait 120 ready widget_state || stopped not-ready "widget=$reading"
[[ $(ipc smoke beginJarvisTrace "$bar") == ok ]] || stopped trace-not-started

if [[ $input_kind == type ]]; then
  [[ $(ipc smoke markJarvisTrace input) == ok ]] || stopped trace-not-marked
  reply="$(ipc vgs.jarvis invoke say "$input_value")" || reply=unread
  [[ $reply == ok ]] || stopped say-refused "$reply"
else
  ipc smoke invokeInstance service vgs.jarvis intent talk-down >/dev/null || stopped talk-not-sent
  selftest_wait 30 listening traced widget || stopped microphone-not-open "widget=$reading"
  selftest_wait 30 listening traced phase || stopped microphone-not-open "phase=$reading"
  selftest_wait 10 ready devices_voice_feed_state || stopped no-voice-feed "$reading"
  [[ $(ipc smoke markJarvisTrace input) == ok ]] || stopped trace-not-marked
  devices_voice_feed "$wav" || stopped no-voice-feed player-failed
fi

turn=waiting
turn_until=$((SECONDS + 300))
while ((SECONDS < turn_until)); do
  turn="$(ipc smoke jarvisTrace | selftest_turn)" || turn=unread
  [[ $turn != ended=* ]] || break
  if [[ $turn == confirming && $confirm == key ]]; then
    request="$(ipc smoke jarvisProcess | selftest_shown)" || request=none
    selftest_confirm "$draw_ms" "$(now_ms)" "$request"
  fi
  sleep 0.2
done
phase="$(traced phase)" || phase=unread
fault="$(ipc smoke jarvisProcess | py_reply 'import json,sys; d=json.load(sys.stdin)["status"].get("detail"); print(d["state"]["fault"].get("reason", "") if d else "")')" || fault=unread
# Toggle mode listens again after its answer; Stop ends the conversation, so
# the trace ends with the widget at rest.
ipc vgs.jarvis invoke stop "" >/dev/null || true
selftest_wait 10 idle traced phase || true
ipc smoke jarvisTrace >"$sandbox/selftest-trace.json" || stopped trace-unread

selftest_finish "$turn" "$home_sum" "$auth_log" "$failures" "$sandbox/selftest-trace.json" "$home/.local/state/vgshell/jarvis/audit" "$out" \
  "$phase" "$fault" "$input_kind" "$input_value" "$brain" "$home_source" "$voice" "$confirm"
