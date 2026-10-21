#!/usr/bin/env bash
# Drive the host side of scripts/jarvis-selftest.sh with no sandbox, no
# account, no model and no audio.
#
# The runner cases run a copy of the runner in a scratch tree, beside a
# stand-in fence that records how it was called and a stand-in harness
# that makes a scratch sandbox with an instrumented Jarvis copy and ends
# the run once its shell has started, or, where a case leaves the device
# guard's answer, at the step after the guard. The accounts are a scratch
# HOME's: one sign-in folder and the saved key references a case writes,
# whose ids the plugin's own account helper lists with no command on its
# PATH. The prepared local voice is a scratch setup of empty files.
# `pw-dump` is a stub that prints a planted graph, which the real
# devices_voice_feed_state reads.
# The keyring is a stand-in secrets service on a scratch bus this file
# starts, never the caller's: it holds one item, present, locked or absent
# as a case sets it, logs each call it gets, and owns a second bus name. The
# world's own filter, a real xdg-dbus-proxy, and the real secret-tool and
# busctl reach it. Without one of those programs the keyring cases are not
# measured and the file exits 77 once the others have run.
# The function cases run the runner's own functions, cut from its file,
# over planted traces, audit records and folders, with the harness's own
# py_reply. The comparison, audio and wake cases drive the suite records,
# synthetic captures and trace readers without a sandbox. The mailbox cases
# hand a request with the plugin's own executor
# through a copy of the checkout's kendex mail tool in a scratch home, as
# Jarvis does, and read it back with the checkout's lane-mail, as the run
# does.
# Each control plants one defect in a copy of the runner and requires the
# case that rule owns to go red. A defect whose text the runner no longer
# holds fails its control. The runner's call of the fence is held by
# scripts/test-gpu-fence.sh.
#
# Exit 0 when every case and control holds, 1 when one does not, and 77
# when all that ran hold and the keyring cases could not run.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
runner="$repo/scripts/jarvis-selftest.sh"

tmp="$(mktemp -d /var/tmp/test-jarvis-selftest.XXXXXX)" || { echo "test-jarvis-selftest: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $tmp && ! -L $tmp ]] || { echo "test-jarvis-selftest: scratch=not-a-directory value=[$tmp]" >&2; exit 1; }
tmp="$(cd -- "$tmp" && pwd -P)" || { echo "test-jarvis-selftest: scratch=resolve-failed" >&2; exit 1; }
# The scratch bus and the stand-in service end by the pids this file
# started, and are reaped before their scratch root goes.
bus_pids=()
trap 'for pid in "${bus_pids[@]}"; do kill "$pid" 2>/dev/null || true; done; wait; rm -rf -- "${tmp:?}"' EXIT
failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }
# holds LABEL CMD...: CMD succeeds.
holds() { local label="$1"; shift; if "$@"; then ok "$label"; else fail "$label"; show; fi; }
show() { for file in out err harness.log fence.log gate-failure.out gate-failure.err; do [[ ! -s $tmp/$file ]] || sed "s/^/        $file: /" -- "$tmp/$file"; done; }
# mutate SOURCE OLD NEW DEST: DEST is SOURCE with its one OLD replaced by
# NEW. Returns 1, with the reason, where OLD does not occur once or DEST
# would read as SOURCE.
mutate() {
  python3 - "$@" <<'PY'
import sys
source, old, new, dest = sys.argv[1:]
text = open(source).read()
reason = f"matched {text.count(old)} times" if text.count(old) != 1 else "left the file unchanged" if old == new else ""
if reason:
    print(f"        mutation {reason}: {old!r}")
    sys.exit(1)
open(dest, "w").write(text.replace(old, new))
PY
}

# node on PATH may be a version manager's shim, which fails under a scratch
# HOME; every case's PATH leads with the directory of the binary itself.
node_bin="$(node -e 'process.stdout.write(process.execPath)')"
mkdir -p "$tmp/bin" "$tmp/empty"
cat >"$tmp/bin/pw-dump" <<SH
#!/usr/bin/env bash
python3 - "$tmp/graph.json" "$tmp/default-source" <<'PY'
import json, os, sys
graph, default_source = sys.argv[1:]
objects = json.load(open(graph))
if os.path.exists(default_source):
    objects.append({"id": 200, "type": "PipeWire:Interface:Metadata",
                    "props": {"metadata.name": "default"},
                    "metadata": [{"key": "default.audio.source",
                                  "value": {"name": open(default_source).read().strip()}}]})
json.dump(objects, sys.stdout)
PY
SH
cat >"$tmp/bin/pw-metadata" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$tmp/pw-metadata.calls"
if [[ -f "$tmp/planted-default-source" ]]; then cat -- "$tmp/planted-default-source" >"$tmp/default-source"; else printf '%s\n' vgs-smoke-voice >"$tmp/default-source"; fi
SH
chmod +x "$tmp/bin/pw-dump" "$tmp/bin/pw-metadata"
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
account_id() { # KIND LABEL [PROVIDER]
  env -i PATH="$tmp/empty" HOME="$world" "$node_bin" "$repo/shell/plugins/vgs.jarvis/backend/accounts.js" --tree "$repo" list |
    python3 -c 'import json,sys; print(next(r["id"] for r in json.load(sys.stdin) if r["source"]["kind"] == sys.argv[1] and r["label"] == sys.argv[2] and (not sys.argv[3] or r["provider"] == sys.argv[3])))' "$1" "$2" "${3:-}"
}
saved_keys openai/selftest anthropic/other
sign_in="$(account_id cli default)"
saved_key="$(account_id keyring selftest)"
mkdir -p "$world/.copilot" "$world/.codex" "$world/.pi/agent"
copilot_id="$(account_id cli default copilot)"
codex_id="$(account_id cli default codex)"
pi_id="$(account_id cli default pi)"
local_id="$(account_id local local)"
# A caller's account wrapper is first on PATH. mise resolves each provider
# into a separate installation whose program prints its selected account.
# No program here reaches a vendor or a real account.
cat >"$tmp/bin/mise" <<SH
#!/usr/bin/env bash
[[ \$1 == which && ! -e "$tmp/brain-lookup-fails" ]] || exit 1
printf '%s\n' "$tmp/vendor/\$2/\$2"
SH
chmod +x "$tmp/bin/mise"
for pair in claude:CLAUDE_CONFIG_DIR codex:CODEX_HOME copilot:COPILOT_HOME pi:PI_CODING_AGENT_DIR; do
  command_name="${pair%:*}" account_name="${pair#*:}"
  mkdir -p "$tmp/vendor/$command_name"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${%s:-}"\n' "$account_name" >"$tmp/vendor/$command_name/$command_name"
  printf '#!/usr/bin/env bash\necho wrapper-replaced-account\n' >"$tmp/bin/$command_name"
  chmod +x "$tmp/vendor/$command_name/$command_name" "$tmp/bin/$command_name"
done

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
voxtype_models="$tmp/voxtype-models"
voxtype_builds="$tmp/voxtype-builds"
voxtype_cpuinfo="$tmp/cpuinfo"
mkdir -p "$voxtype_models/parakeet-tdt-0.6b-v3"
mkdir -p "$voxtype_builds"
echo model >"$voxtype_models/parakeet-tdt-0.6b-v3/model.bin"
printf '#!/bin/sh\nexit 0\n' >"$voxtype_builds/voxtype-onnx-avx2"
printf '#!/bin/sh\nexit 0\n' >"$voxtype_builds/voxtype-onnx-avx512"
chmod +x "$voxtype_builds/voxtype-onnx-avx2" "$voxtype_builds/voxtype-onnx-avx512"
echo 'flags	: avx2 avx512f' >"$voxtype_cpuinfo"
voice_inputs=(JARVIS_LOCAL_MODELS="$voice_root/models" JARVIS_LOCAL_PYTHON="$voice_root/venv/bin/python" VOXTYPE_MODELS="$voxtype_models")

# The scratch tree: the runner's copy, the checkout's shell, bin and agent
# skills, a fence
# that answers --check from fence-answer and records every other call, and
# the harness stand-in. The stand-in holds the harness's own spawn and
# sentinel stand-over, cut from its file, a secret-tool sentinel that
# answers as the harness's does, and an exit path that ends what the run
# spawned. Its start_shell sources at-start.sh where a case left one, so
# the case reads the run's filter and its secret-tool while they stand, and
# then ends the run. Where a case left guard-answer the run goes on: the
# stand-in device guard answers that word, or fails for `unreadable`, and
# the stand-in ipc records its call and answers nothing, which stops the
# run at its next step.
tree="$tmp/tree"
mkdir -p "$tree/scripts/smoke"
ln -s -- "$repo/shell" "$tree/shell"
ln -s -- "$repo/bin" "$tree/bin"
ln -s -- "$repo/config" "$tree/config"
ln -s -- "$repo/.agents" "$tree/.agents"
ln -s -- "$repo/scripts/jarvis-selftest-cases" "$tree/scripts/jarvis-selftest-cases"
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
echo '{"version": 2, "plugins": [{"id": "vgs.settings"}], "disabledPlugins": ["vgs.jarvis"]}' >"\$home/.config/vgshell/shell.json"
failures=0 instance_log="" devices_state=down auth_log="\$sandbox/auth.calls" shell_env=()
rt_dir="$tmp/rt" shim="\$sandbox/shim" sentinels_saved="\$sandbox/sentinels" sentinels_stood="\$sandbox/sentinels.stood" pgids=()
shell_start_path="\$shim:\$PATH"
rm -rf -- "\${rt_dir:?}"
mkdir -p "\$rt_dir" "\$shim" "\$sentinels_saved"
ln -s -- "$repo/config" "\$repo/config"
trap 'for pid in "\${pgids[@]}"; do kill -TERM -- "-\$pid" 2>/dev/null || true; done' EXIT
printf '#!/usr/bin/env bash\ncase "\${1:-}" in search) exit 0 ;; lookup) exit 1 ;; esac\nprintf "%%s\\n" "secret-tool \$*" >>%q\nexit 1\n' "\$auth_log" >"\$shim/secret-tool"
chmod 755 "\$shim/secret-tool"
stop_shell() { echo stop_shell >>"$tmp/harness.log"; }
devices_up() { devices_state=up; }
start_shell() {
  echo "start_shell \${*:4}" >>"$tmp/harness.log"
  shell_qs_pid=\$\$
  [[ ! -e "$tmp/at-start.sh" ]] || source "$tmp/at-start.sh"
  [[ -e "$tmp/guard-answer" ]] || exit 0
}
devices_guard() {
  local answer
  answer="\$(<"$tmp/guard-answer")"
  [[ \$answer != unreadable ]] || return 1
  printf '%s\\n' "\$answer"
}
ipc() { echo "ipc \$*" >>"$tmp/harness.log"; }
shell_resolves() { PATH="\$shell_start_path" command -v -- "\$1" || echo none; }
SH
{ sed -n '/^spawn() {/,/^}/p; /^sentinel_saved() {/p; /^sentinel_stand_over() {/,/^}/p' "$repo/scripts/smoke/harness.sh"
  sed -n '/^devices_audio() {/,/^}/p; /^devices_voice_feed_sink=/p; /^devices_voice_feed_source=/p; /^devices_voice_feed_state() {/,/^}/p; /^devices_voice_feed_default_source() {/,/^}/p; /^devices_voice_feed_default() {/,/^}/p' "$repo/scripts/smoke/devices.sh"; } >>"$tree/scripts/smoke/harness.sh"

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
selftest_proxy_env=()
run() {
  : >"$tmp/fence.log"; : >"$tmp/harness.log"; rm -f -- "$tmp/default-source" "$tmp/pw-metadata.calls"
  status=0
  (cd -- "$tmp" && env -i PATH="$path" HOME="$world" "${inputs[@]}" "${session_bus[@]}" "${selftest_proxy_env[@]}" "$BASH" "$tree/scripts/jarvis-selftest.sh" "$@") >"$tmp/out" 2>"$tmp/err" || status=$?
}
# Outside a control the tree's runner and the cut functions are the
# checkout's own: plant FILE puts FILE in the tree as the runner, and
# cut_functions FILE cuts FILE's functions, with the harness's py_reply,
# for call.
plant() {
  cp -- "$1" "$tree/scripts/jarvis-selftest.sh"
  python3 - "$tree/scripts/jarvis-selftest.sh" "$voxtype_builds" "$voxtype_cpuinfo" <<'PY'
import re, sys
path, builds, cpuinfo = sys.argv[1:]
text = open(path).read()
text = re.sub(r"^selftest_voxtype_builds=.*$", f"selftest_voxtype_builds={builds}", text, count=1, flags=re.M)
text = re.sub(r"^selftest_cpuinfo=.*$", f"selftest_cpuinfo={cpuinfo}", text, count=1, flags=re.M)
open(path, "w").write(text)
PY
}
functions="$tmp/functions.sh"
cut_functions() { # RUNNER
  { sed -n '/^py_reply() {/,/^}/p; /^now_ms() {/p' "$repo/scripts/smoke/harness.sh"
    for name in selftest_tree_sum selftest_home_copy selftest_overseer selftest_mailbox selftest_daemon selftest_last selftest_service_phase selftest_voice_state selftest_gate_context selftest_turn selftest_wait selftest_draw_ms selftest_shown selftest_confirm \
      selftest_woke selftest_end selftest_audio selftest_audio_record selftest_wav_tail selftest_speech_tail selftest_open selftest_dictation_sample selftest_dictation_record selftest_case_check selftest_compare selftest_case_child_args selftest_tts_voice selftest_suite_summary selftest_suite_stopped selftest_record selftest_voxtype_models_kept selftest_sidecar stopped stopped_gate selftest_finish; do sed -n "/^$name() {/,/^}/p" "$1"; done
    sed -n '/^devices_speaker_sounds() {/,/^}/p' "$repo/scripts/smoke/devices.sh"; } >"$functions"
}
call() { selftest_node="$node_bin" bash -c 'set -euo pipefail; source "$1"; shift; "$@"' _ "$functions" "$@"; }
plant "$runner"
cut_functions "$runner"
# control HOW LABEL OLD NEW CASE...: the runner with its one OLD replaced by
# NEW, put in place by HOW, plant or cut_functions, must fail CASE, the case
# of the rule the defect breaks. A defect that does not apply fails the
# control: nothing is put in place and CASE does not run.
mutant="$tmp/mutant.sh"
control() {
  local how="$1" label="$2" old="$3" new="$4"
  shift 4
  if ! mutate "$runner" "$old" "$new" "$mutant"; then fail "control: $label: its defect did not apply"; return; fi
  "$how" "$mutant"
  if "$@"; then fail "control: $label stayed green"; else ok "control: $label"; fi
  "$how" "$runner"
}
# The control's own control: a defect whose text the runner does not hold
# counts one failure, runs no case and leaves the tree's runner as it was.
# It runs in a substitution, so its count stays there.
unapplied="$(failures=0; control plant "a defect the runner does not hold" 'no line of the runner reads so' ':' touch "$tmp/case-ran" >/dev/null; echo "$failures")"
if [[ $unapplied == 1 && ! -e $tmp/case-ran ]]; then
  ok "control: a defect that does not apply fails its control and runs no case"
else
  fail "control: a defect that does not apply fails its control and runs no case"
fi
# ends WANT_STATUS WANT_LINE ARGS...: the run ends with that status and that
# last line on stdout, having started nothing.
ends() {
  local want_status="$1" want_line="$2"
  shift 2
  run "$@"
  [[ $status -eq $want_status && "$(tail -n 1 -- "$tmp/out")" == "$want_line" && ! -s $tmp/fence.log && ! -s $tmp/harness.log ]]
}

echo "--- what the run refuses before it starts anything"
echo 1 >"$tmp/fence-answer"
sandbox="$tmp/sandbox"
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
voxtype_rows=(
  "no VOXTYPE_MODELS|JARVIS_LOCAL_MODELS=$voice_root/models JARVIS_LOCAL_PYTHON=$voice_root/venv/bin/python"
  "a VOXTYPE_MODELS folder that is absent|JARVIS_LOCAL_MODELS=$voice_root/models JARVIS_LOCAL_PYTHON=$voice_root/venv/bin/python VOXTYPE_MODELS=$tmp/absent-voxtype-models"
  "a VOXTYPE_MODELS folder without the configured model|JARVIS_LOCAL_MODELS=$voice_root/models JARVIS_LOCAL_PYTHON=$voice_root/venv/bin/python VOXTYPE_MODELS=$tmp/empty-voxtype-models"
)
mkdir -p "$tmp/empty-voxtype-models"
voxtype_case() { # ROW
  read -r -a inputs <<<"${1#*|}"
  local held=0
  ends 77 "selftest=input-missing name=VOXTYPE_MODELS" --type hello --brain "$sign_in" || held=1
  inputs=("${voice_inputs[@]}")
  return "$held"
}
for row in "${voxtype_rows[@]}"; do holds "${row%%|*} ends as selftest=input-missing name=VOXTYPE_MODELS, exit 77" voxtype_case "$row"; done
cpu_fixture() { # FLAGS AVX2 AVX512
  printf 'flags\t: %s\n' "$1" >"$voxtype_cpuinfo"
  rm -f -- "$voxtype_builds/voxtype-onnx-avx2" "$voxtype_builds/voxtype-onnx-avx512"
  if [[ $2 == yes ]]; then printf '#!/bin/sh\nexit 0\n' >"$voxtype_builds/voxtype-onnx-avx2" && chmod +x "$voxtype_builds/voxtype-onnx-avx2"; fi
  if [[ $3 == yes ]]; then printf '#!/bin/sh\nexit 0\n' >"$voxtype_builds/voxtype-onnx-avx512" && chmod +x "$voxtype_builds/voxtype-onnx-avx512"; fi
}
cpu_rows=(
  "avx512f flag and avx512 present chooses avx512|avx2 avx512f|yes|yes|$voxtype_builds/voxtype-onnx-avx512|0"
  "no avx512f flag chooses avx2|avx2|yes|yes|$voxtype_builds/voxtype-onnx-avx2|0"
  "no CPU build ends input-missing|avx2 avx512f|no|no||77"
)
cpu_case() { # ROW
  local label flags avx2 avx512 want status_want held=0
  IFS='|' read -r label flags avx2 avx512 want status_want <<<"$1"
  cpu_fixture "$flags" "$avx2" "$avx512"
  if [[ $status_want == 77 ]]; then
    ends 77 "selftest=input-missing name=voxtype-cpu" --type hello --brain "$sign_in" || held=1
  else
    echo 0 >"$tmp/fence-answer"
    run --type hello --brain "$sign_in"
    [[ $status -eq 0 ]] || held=1
    [[ "$(grep '^exec ' "$sandbox/shim/voxtype")" == "exec $want \"\$@\"" ]] || held=1
    echo 1 >"$tmp/fence-answer"
  fi
  cpu_fixture "avx2 avx512f" yes yes
  return "$held"
}
for row in "${cpu_rows[@]}"; do holds "${row%%|*}" cpu_case "$row"; done
refused() { # WANT_FIRST_STDERR_LINE ARGS...
  local want="$1"
  shift
  run "$@"
  [[ $status -eq 2 && "$(head -n 1 -- "$tmp/err")" == "$want" && ! -s $tmp/fence.log && ! -s $tmp/harness.log ]]
}
holds "an id no account has is refused" refused "jarvis-selftest: refused: argument=--brain value=cli:none reason=unknown-account" --type hello --brain cli:none
holds "a second input is refused" refused "jarvis-selftest: refused: argument=--tts reason=one-input" --type hello --tts hello --brain "$sign_in"
holds "no input is refused" refused "jarvis-selftest: refused: argument=input reason=missing want=--wav|--tts|--type" --brain "$sign_in"
holds "a local server without a model is refused before the sandbox starts" refused "jarvis-selftest: refused: argument=--model reason=missing-local-model" --type hello --brain "$local_id"
control plant "a local server that starts without a model" '  local) [[ -n $model ]] || refuse "argument=--model reason=missing-local-model" ;;' '  local) true || refuse "argument=--model reason=missing-local-model" ;;' refused "jarvis-selftest: refused: argument=--model reason=missing-local-model" --type hello --brain "$local_id"
holds "an empty model argument is refused" refused "jarvis-selftest: refused: argument=--model value=" --type hello --brain "$local_id" --model ""
brain_lookup_refused() {
  touch "$tmp/brain-lookup-fails"
  local held=0
  ends 77 'selftest=brain-program-unavailable command=claude' --type hello --brain "$sign_in" || held=1
  rm -- "${tmp:?}/brain-lookup-fails"
  return "$held"
}
holds "a failed installed-program lookup never uses the account wrapper" brain_lookup_refused
control plant "a failed installed-program lookup that selects the account wrapper" '      brain_program="$(mise which "$brain_provider" 2>/dev/null)" || unavailable brain-program-unavailable "command=$brain_provider"' '      brain_program="$(mise which "$brain_provider" 2>/dev/null)" || brain_program="$(command -v -- "$brain_provider")"' brain_lookup_refused
holds "a WAV that is not there is refused" refused "jarvis-selftest: refused: argument=--wav value=$tmp/absent.wav reason=unreadable" --wav "$tmp/absent.wav" --brain "$sign_in"
bad_wav_refused() {
  python3 - "$tmp/bad.wav" <<'PY'
import wave, sys
with wave.open(sys.argv[1], "wb") as f:
    f.setnchannels(1); f.setsampwidth(1); f.setframerate(8000); f.writeframes(b"\x80" * 80)
PY
  refused "jarvis-selftest: refused: argument=--wav value=$tmp/bad.wav reason=wav-not-pcm16" --wav "$tmp/bad.wav" --brain "$sign_in"
}
holds "a WAV that is not 16-bit PCM is refused" bad_wav_refused
holds "cold start mode rejects a turn input" refused "jarvis-selftest: refused: argument=--cold reason=exclusive-with-input" --cold 1 --type hello
holds "cold start mode rejects a brain" refused "jarvis-selftest: refused: argument=--cold reason=exclusive-with-brain" --cold 1 --brain "$sign_in"
holds "cold start mode rejects a model" refused "jarvis-selftest: refused: argument=--cold reason=exclusive-with-model" --cold 1 --model 'selftest-model:small'
control plant "cold start mode that accepts a model" '  [[ -z $model ]] || refuse "argument=--cold reason=exclusive-with-model"' '  true || refuse "argument=--cold reason=exclusive-with-model"' refused "jarvis-selftest: refused: argument=--cold reason=exclusive-with-model" --cold 1 --model 'selftest-model:small'
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
  refused "jarvis-selftest: refused: argument=--voice value=realtime reason=several-keys" --type hello --brain "$sign_in" --voice realtime || held=1
  saved_keys openai/selftest anthropic/other
  return "$held"
}
no_session_bus() { ends 77 "selftest=keyring-unavailable missing=session-bus" --type hello --brain "$saved_key"; }
# The Gemini voice takes a Gemini key: the saved OpenAI key is not one.
unsaved_gemini() { ends 77 "selftest=keyring-no-key key=unsaved" --type hello --brain "$sign_in" --voice gemini; }
# The ElevenLabs voice takes an ElevenLabs key, and Always mode keeps it:
# the local voice hears the room, so the run goes on to its missing key.
unsaved_elevenlabs() { ends 77 "selftest=keyring-no-key key=unsaved" --tts hello --mode always --brain "$sign_in" --voice elevenlabs; }
holds "the realtime voice with no OpenAI key saved ends as selftest=keyring-no-key key=unsaved, exit 77" unsaved_voice
holds "the realtime voice with two OpenAI keys saved is refused" several_voices
holds "a saved key with no session bus ends as selftest=keyring-unavailable, exit 77" no_session_bus
holds "the gemini voice with only an OpenAI key saved ends as selftest=keyring-no-key key=unsaved, exit 77" unsaved_gemini
holds "the elevenlabs voice in Always mode with only an OpenAI key saved ends as selftest=keyring-no-key key=unsaved, exit 77" unsaved_elevenlabs

control plant "a runner that starts the realtime voice with no key saved" '  none) unavailable keyring-no-key key=unsaved ;;' '  none) ;;' unsaved_voice
control plant "a runner that starts the realtime voice with two keys saved" '  several) refuse "argument=--voice value=$voice reason=several-keys" ;;' '  several) ;;' several_voices
control plant "a runner that serves the gemini voice with an OpenAI key" 'const provider = { gemini: "gemini", elevenlabs: "elevenlabs" }[voice] ?? "openai";' 'const provider = "openai";' unsaved_gemini
control plant "a runner that serves the elevenlabs voice with an OpenAI key" '{ gemini: "gemini", elevenlabs: "elevenlabs" }[voice]' '{ gemini: "gemini" }[voice]' unsaved_elevenlabs
control plant "a runner that refuses Always mode with the elevenlabs voice" '  local|elevenlabs) hears_here=true ;;' '  local) hears_here=true ;;' unsaved_elevenlabs
control plant "a runner that goes on to a key read with no session bus" '  [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || unavailable keyring-unavailable missing=session-bus' '  :' no_session_bus
control plant "a runner that goes on without a prepared local voice" 'selftest_local_inputs)" || unavailable local-inputs-unavailable' 'selftest_local_inputs)" || local_inputs=/nowhere$'"'"'\n'"'"'/nowhere' local_case "${local_rows[0]}"
control plant "a runner that takes an interpreter of another setup" '  [[ $models -ef $root/models && $python -ef $root/venv/bin/python ]] || return 1' '' local_case "${local_rows[2]}"
control plant "a runner that takes a setup with no ready marker" '  [[ -f $marker ]] || return 1' '' local_case "${local_rows[3]}"
control plant "a runner that starts with the configured voxtype model absent" 'if not os.path.isdir(model_path):
    raise SystemExit(3)' 'if False and not os.path.isdir(path):
    raise SystemExit(3)' voxtype_case "${voxtype_rows[2]}"
control plant "a runner that skips every VOXTYPE_MODELS pre-start guard" 'voxtype_models=""
voxtype_models_sum=""
voxtype_cpu=""
if [[ $hears_here == true ]]; then' 'voxtype_models=""
voxtype_models_sum=""
voxtype_cpu=""
if false; then' voxtype_case "${voxtype_rows[0]}"
control plant "a runner that takes avx2 while avx512f is available" 'if grep -qw avx512f "$selftest_cpuinfo" && [[ -x $selftest_voxtype_builds/voxtype-onnx-avx512 ]]; then' 'if false && grep -qw avx512f "$selftest_cpuinfo" && [[ -x $selftest_voxtype_builds/voxtype-onnx-avx512 ]]; then' cpu_case "${cpu_rows[0]}"
control plant "a runner that starts without a CPU voxtype build" '  voxtype_cpu="$(selftest_voxtype_cpu)" || unavailable input-missing name=voxtype-cpu' '  voxtype_cpu="$selftest_voxtype_builds/voxtype-onnx-avx2"' cpu_case "${cpu_rows[2]}"

echo "--- what the run makes before its shell starts"
echo 0 >"$tmp/fence-answer"
# The run's own word for every shell it starts: where the daemon writes its
# trace of brain text.
trace_word="VGS_JARVIS_TRACE=$sandbox/selftest-brain.jsonl"
row_of() { python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); print(json.dumps([r for r in c["plugins"] if r["id"] == "vgs.jarvis"] + [c["disabledPlugins"]], sort_keys=True))' "$sandbox/home/.config/vgshell/shell.json"; }
starts() { run --type hello --brain "$sign_in" "$@"; [[ $status -eq 0 ]]; }
plugin_restored() { starts && diff -r -q -- "$repo/shell/plugins/vgs.jarvis" "$sandbox/repo/shell/plugins/vgs.jarvis" >/dev/null; }
account_alone() { starts && [[ "$(<"$tmp/harness.log")" == "harness-reached"$'\n'"stop_shell"$'\n'"start_shell CLAUDE_CONFIG_DIR=$world/.claude $trace_word" ]]; }
settings_named() {
  starts && [[ "$(row_of)" == "[{\"brain\": \"$sign_in\", \"id\": \"vgs.jarvis\", \"microphone\": \"vgs-smoke-voice\", \"mode\": \"toggle\", \"speaker\": \"vgs-smoke-speakers\", \"voiceProvider\": \"local\"}, [\"vgs.jarvis\"]]" ]]
}
voice_linked() { starts && [[ $sandbox/home/.local/share/vgshell/jarvis/local -ef $voice_root ]] && cmp -s -- "$tmp/voice/.local/state/vgshell/jarvis/local-ready.json" "$sandbox/home/.local/state/vgshell/jarvis/local-ready.json"; }
voxtype_configured() {
  local before
  before="$(call selftest_tree_sum "$voxtype_models")" || return 1
  starts || return 1
  [[ "$(call selftest_tree_sum "$voxtype_models")" == "$before" ]] || return 1
  python3 - "$sandbox/home/.config/voxtype/config.toml" "$voxtype_models" "$repo/config/voxtype/config.toml" "$sandbox/home/.local/share/voxtype/models" <<'PY'
import os, sys, tomllib
config, prepared, source, inventory = sys.argv[1:]
data = tomllib.load(open(config, "rb"))
original = tomllib.load(open(source, "rb"))
engine = original["engine"]
model = original[engine]["model"]
text = open(config).read()
theme = data["audio"]["feedback"]["theme"]
if data[engine]["model"] != model or os.path.isabs(data[engine]["model"]) or "__VGS_DICTATION_BLOOP_THEME__" in text or not os.path.isdir(theme):
    raise SystemExit(1)
if os.listdir(inventory) != [model] or not os.path.samefile(os.path.join(inventory, model), os.path.join(prepared, model)):
    raise SystemExit(1)
if not os.path.islink(os.path.join(inventory, model)):
    raise SystemExit(1)
PY
}
voxtype_foreign_inventory() { # ENTRY_KIND
  local kind="$1" held=0
  cp -- "$tree/scripts/smoke/harness.sh" "$tmp/harness-model-owned.sh"
  python3 - "$tree/scripts/smoke/harness.sh" "$tmp/foreign-model" "$kind" <<'PY'
import pathlib,shlex,sys
file, foreign, kind = sys.argv[1:]
pathlib.Path(foreign).mkdir(exist_ok=True)
pathlib.Path(foreign,"kept").write_text("kept")
source=pathlib.Path(file).read_text()
needle='stop_shell() { echo stop_shell'
assert source.count(needle) == 1
plant='mkdir -p "$home/.local/share/voxtype/models"\n'
if kind == "parent-link":
    plant='mkdir -p "$home/.local/share/voxtype"\nln -s -- '+shlex.quote(foreign)+' "$home/.local/share/voxtype/models"\n'
elif kind == "model-link":
    plant+='ln -s -- '+shlex.quote(foreign)+' "$home/.local/share/voxtype/models/parakeet-tdt-0.6b-v3"\n'
else:
    plant+='mkdir "$home/.local/share/voxtype/models/parakeet-tdt-0.6b-v3"\nprintf kept >"$home/.local/share/voxtype/models/parakeet-tdt-0.6b-v3/kept"\n'
pathlib.Path(file).write_text(source.replace(needle,plant+needle))
PY
  run --type hello --brain "$sign_in"
  [[ $status -eq 1 ]] && grep -qxF selftest=voxtype-config-unread "$tmp/out" || held=1
  [[ "$(<"$tmp/foreign-model/kept")" == kept ]] || held=1
  if [[ $kind == directory ]]; then
    [[ "$(<"$sandbox/home/.local/share/voxtype/models/parakeet-tdt-0.6b-v3/kept")" == kept ]] || held=1
  fi
  [[ $(find "$tmp/foreign-model" -mindepth 1 -maxdepth 1 | wc -l) -eq 1 ]] || held=1
  cp -- "$tmp/harness-model-owned.sh" "$tree/scripts/smoke/harness.sh"
  return "$held"
}
voxtype_cpu_shim() { starts && [[ "$(grep '^exec ' "$sandbox/shim/voxtype")" == "exec $voxtype_builds/voxtype-onnx-avx512 \"\$@\"" ]]; }
feed_defaulted() { starts && [[ "$(<"$tmp/default-source")" == vgs-smoke-voice ]] && grep -qxF -- '-n default 0 default.configured.audio.source { "name": "vgs-smoke-voice" } Spa:String:JSON' "$tmp/pw-metadata.calls"; }
default_refused() {
  printf '%s\n' vgs-other-source >"$tmp/planted-default-source"
  run --type hello --brain "$sign_in"
  local held=0
  [[ $status -eq 1 && "$(tail -n 1 -- "$tmp/out")" == "selftest=no-voice-feed default=vgs-other-source" ]] || held=1
  rm -f -- "$tmp/planted-default-source"
  return "$held"
}
holds "the sandbox's Jarvis plugin is the checkout's, byte for byte" plugin_restored
holds "the shell starts with two extra words: the account's directory variable and the run's own trace path" account_alone
holds "Jarvis's settings name the brain, the feed's source and the null speakers, with Jarvis still disabled" settings_named
local_model_named() {
  run --type hello --brain "$local_id" --model 'selftest-model:small'
  [[ $status -eq 0 ]] && python3 - "$sandbox/home/.config/vgshell/shell.json" "$local_id" <<'PY'
import json, sys
config = json.load(open(sys.argv[1]))
row = next(r for r in config["plugins"] if r["id"] == "vgs.jarvis")
sys.exit(row.get("model") != "selftest-model:small" or row["brain"] != sys.argv[2] or "vgs.jarvis" not in config["disabledPlugins"])
PY
}
holds "the local server model is written while Jarvis is disabled" local_model_named
control plant "a runner that drops the local server model" '    row["model"] = model' '    pass' local_model_named
suite_model_named() {
  mkdir -p "$tmp/model-voices"
  python3 - "$tmp/model-voices/volume.wav" <<'PY'
import sys, wave
with wave.open(sys.argv[1], "wb") as file:
    file.setnchannels(1); file.setsampwidth(2); file.setframerate(16000); file.writeframes(b"\0\0" * 160)
PY
  run --suite volume --voices "$tmp/model-voices" --brain "$local_id" --model 'selftest-model:small'
  [[ $status -eq 1 ]] && grep -qxF 'case=volume source=local verdict=failed status=0' "$tmp/out" &&
    python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); sys.exit(next(r for r in c["plugins"] if r["id"] == "vgs.jarvis").get("model") != "selftest-model:small")' "$sandbox/home/.config/vgshell/shell.json"
}
holds "a suite passes the model argument to its sandbox child" suite_model_named
control plant "a suite that drops its child model argument" '    [[ -z $model ]] || child_args+=(--model "$model")' '    :' suite_model_named
holds "the prepared setup is linked as the sandbox's local voice, with its marker" voice_linked
holds "the sandbox keeps the named model, exposes only its prepared directory and leaves its source unchanged" voxtype_configured
for model_entry in parent-link model-link directory; do holds "an existing $model_entry in the sandbox model inventory stays untouched" voxtype_foreign_inventory "$model_entry"; done
holds "the sandbox shell resolves voxtype to the CPU wrapper" voxtype_cpu_shim
holds "the voice feed is the sandbox PipeWire default source before Jarvis starts" feed_defaulted
holds "a default source that is not the feed stops the run before Jarvis starts" default_refused
control plant "a runner that keeps the harness's instrumented plugin" \
  'rm -rf -- "${repo:?}/shell/plugins/vgs.jarvis"'$'\n''cp -R -- "$plugin" "$repo/shell/plugins/vgs.jarvis"' ':' plugin_restored
control plant "a runner that hands the shell another word of the caller's" 'bar "${account_word[@]}"' 'bar "${account_word[@]}" "HOME=$HOME"' account_alone
control plant "a runner that names the daemon no trace path" ' "VGS_JARVIS_TRACE=$sandbox/selftest-brain.jsonl" || stopped shell-not-started' ' || stopped shell-not-started' account_alone
control plant "a runner that leaves the microphone to the default" '"microphone": microphone,' '' settings_named
control plant "a runner that changes the inventory model name to an absolute path" 'rendered = body.replace(token, json.dumps(bloop))' 'rendered = body.replace(token, json.dumps(bloop)).replace(model_name, model_path)' voxtype_configured
control plant "a runner that exposes no prepared model in the sandbox inventory" 'os.symlink(model_path, os.path.join(inventory, model_name))' 'pass' voxtype_configured
control plant "a runner that does not make the feed the default source" '  devices_voice_feed_default || stopped no-voice-feed default-failed' '  :' feed_defaulted
control plant "a runner that does not verify the feed became the default source" '  selftest_wait 10 "$devices_voice_feed_source" devices_voice_feed_default_source || stopped no-voice-feed "default=$reading"' '  :' default_refused

# The device guard: the run goes on only where the guard reads the shell
# inside. One table: the guard's answer, the run's last line, and whether
# the step after the guard, the first ipc call, was made.
guard_rows=(
  "a device guard that reads a leak stops the run|leak=pipewire-runtime value=PIPEWIRE_RUNTIME_DIR=/run/user/1000|selftest=device-guard leak=pipewire-runtime value=PIPEWIRE_RUNTIME_DIR=/run/user/1000|no"
  "a device guard that cannot read the shell stops the run|unreadable|selftest=device-guard unreadable|no"
  "a device guard that reads the shell inside lets the run go on to its next step|inside|selftest=jarvis-not-enabled |yes"
)
guard_case() { # ROW
  local answer line went held=0 steps=""
  IFS='|' read -r _ answer line went <<<"$1"
  printf '%s\n' "$answer" >"$tmp/guard-answer"
  run --type hello --brain "$sign_in"
  rm -- "${tmp:?}/guard-answer"
  [[ $went == no ]] || steps=$'\n'"ipc shell setPluginEnabled vgs.jarvis true"
  [[ $status -eq 1 && "$(tail -n 1 -- "$tmp/out")" == "$line" &&
    "$(<"$tmp/harness.log")" == "harness-reached"$'\n'"stop_shell"$'\n'"start_shell CLAUDE_CONFIG_DIR=$world/.claude $trace_word$steps" ]] || held=1
  return "$held"
}
for row in "${guard_rows[@]}"; do holds "${row%%|*}" guard_case "$row"; done
control plant "a runner that goes on past a device guard's leak" '[[ $guard == inside ]] || stopped device-guard "$guard"' ':' guard_case "${guard_rows[0]}"
control plant "a runner that takes an unread device guard as inside" '|| stopped device-guard unreadable' '|| guard=inside' guard_case "${guard_rows[1]}"
control plant "a runner that stops at every device guard" '[[ $guard == inside ]] || stopped device-guard "$guard"' 'stopped device-guard "$guard"' guard_case "${guard_rows[2]}"
models_changed_stopped() {
  printf '%s\n' inside >"$tmp/guard-answer"
  cat >"$tmp/at-start.sh" <<SH
echo changed >"$voxtype_models/planted-during-start"
SH
  run --type hello --brain "$sign_in"
  rm -f -- "$tmp/guard-answer" "$tmp/at-start.sh" "$voxtype_models/planted-during-start"
  grep -qxF -- "selftest: the voxtype models folder changed during the run: $voxtype_models" "$tmp/out" &&
    [[ "$(tail -n 1 -- "$tmp/out")" == "selftest=jarvis-not-enabled " ]]
}
holds "a stopped run reports a write under VOXTYPE_MODELS" models_changed_stopped
control plant "a stopped run that skips the voxtype models checksum" '  selftest_voxtype_models_kept || model_status=$?' '  :' models_changed_stopped

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
# kendex_home DIR: DIR made a git repository of its own holding a copy of
# the checkout's kendex orch skill, as the Install kendex setup leaves a
# Jarvis home.
kendex_home() { # DIR
  mkdir -p "$1/.agents/skills" && git -C "$1" init -q && cp -a -- "$repo/.agents/skills/orch" "$repo/.agents/skills/mailbox" "$1/.agents/skills/"
}
# workflow_get DIR EXPR: EXPR of DIR's own fleet state, read by DIR's own
# workflow-state.
workflow_get() { (cd -- "$1" && env -i PATH="$path" "$BASH" .agents/skills/orch/scripts/workflow-state get oversee "$2" 2>>"$tmp/err"); }
# lane_send DIR FILE: the text in FILE sent to the Jarvis session's mailbox
# in DIR by DIR's own lane-mail.
lane_send() { # DIR FILE
  (cd -- "$1" && env -i PATH="$path" "$BASH" .agents/skills/mailbox/scripts/lane-mail send --item overseer --directive \
    --file "$2" --root "$1") >"$tmp/out" 2>"$tmp/err"
}
home_untouched() {
  local before copy="$sandbox/home/jarvis-home"
  make_folder
  before="$(call selftest_tree_sum "$folder")" || return 1
  starts --home "$folder" || return 1
  [[ "$(row_of | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["home"])')" == "$copy" ]] || return 1
  echo memory >"$copy/state/turn.json" && echo changed >>"$copy/AGENTS.md" && rm -- "$copy/skills/notes/SKILL.md" || return 1
  [[ "$(call selftest_tree_sum "$folder")" == "$before" ]]
}
holds "a write under the home copy's state/ leaves the named folder byte for byte unchanged" home_untouched
control plant "a runner whose home copy is the folder itself" '  cp -a -- "$1" "$2"' '  ln -s -- "$1" "$2"' home_untouched
control plant "a runner whose home copy lies outside the sandbox's HOME" '  home_copy="$home/jarvis-home"' '  home_copy="$sandbox/jarvis-home"' home_untouched
control plant "a runner whose settings name the folder itself" '"$devices_voice_feed_source" "$home_copy" "$voice"' '"$devices_voice_feed_source" "$home_source" "$voice"' home_untouched
# The Jarvis session's mailbox in the home copy: the run reads it before
# Jarvis starts, as the Jarvis session does, which makes it where the folder
# has none and leaves no row the folder held to be taken as the turn's.
mail_row='{"id":"1791633000-1-1","text":"an earlier request"}'
mail_made() {
  make_folder
  starts --home "$folder" || return 1
  [[ -d $sandbox/home/jarvis-home/tmp/lane-mail/overseer && ! -e $folder/tmp ]]
}
mail_read_before() {
  local rows
  make_folder
  kendex_home "$folder" && call selftest_overseer "$folder" || return 1
  printf 'an earlier request\n' >"$tmp/request.txt"
  lane_send "$folder" "$tmp/request.txt" || return 1
  starts --home "$folder" || return 1
  rows="$(call selftest_mailbox "$repo" "$sandbox/home/jarvis-home")" || return 1
  [[ -z $rows ]]
}
holds "a folder with no mailbox gets one in the home copy alone" mail_made
holds "a row the folder's mailbox held is read before Jarvis starts" mail_read_before
control plant "a runner that makes no mailbox in the home copy" '  selftest_mailbox "$source_repo" "$home_copy" >/dev/null || stopped mailbox-unread' '  :' mail_made
control plant "a runner that leaves the folder's own mail unread" '  selftest_mailbox "$source_repo" "$home_copy" >/dev/null || stopped mailbox-unread' '  :' mail_read_before
control plant "a reader that leaves the mailbox's cursor where it was" 'inbox --item overseer' 'inbox --peek --item overseer' mail_read_before
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
control cut_functions "a checksum of names alone" " -type f -exec sha256sum -- {} +" "" sum_moves bash -c 'echo instructions >"$1/AGENTS.md"' _ "$folder"

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
holds "with the loopback absent the run ends as selftest=no-voice-feed, exit 1, before Jarvis starts and with no record" no_feed
control plant "a runner that starts Jarvis without the feed" 'selftest_wait 10 absent=recorder devices_voice_feed_state || stopped no-voice-feed "$reading"' ':' no_feed
graph none vgs-smoke-speakers vgs-smoke-voice-feed vgs-smoke-voice

# More refusals added by the acceptance suite contract.
holds "Always mode refuses typed input" refused "jarvis-selftest: refused: argument=--mode value=always reason=always-needs-voice" --type hello --mode always --brain "$sign_in"
holds "Always mode refuses the realtime voice" refused "jarvis-selftest: refused: argument=--mode value=always reason=always-needs-local-voice" --tts hello --mode always --voice realtime --brain "$sign_in"
holds "Always mode refuses the gemini voice" refused "jarvis-selftest: refused: argument=--mode value=always reason=always-needs-local-voice" --tts hello --mode always --voice gemini --brain "$sign_in"
control plant "a runner that takes Always mode with the gemini voice" '  [[ $mode != always || $hears_here == true ]] || refuse' '  [[ $mode != always || $voice != realtime ]] || refuse' \
  refused "jarvis-selftest: refused: argument=--mode value=always reason=always-needs-local-voice" --tts hello --mode always --voice gemini --brain "$sign_in"
holds "a suite refuses a direct input" refused "jarvis-selftest: refused: argument=--suite reason=exclusive-with-input" --suite volume --tts hello --brain "$sign_in"
holds "a suite refuses a direct mode" refused "jarvis-selftest: refused: argument=--suite reason=exclusive-with-mode" --suite volume --mode toggle --brain "$sign_in"
holds "a suite refuses a direct confirmation mode" refused "jarvis-selftest: refused: argument=--suite reason=exclusive-with-confirm" --suite volume --confirm key --brain "$sign_in"
holds "an unknown suite case is refused" refused "jarvis-selftest: refused: argument=--suite value=absent reason=unknown-case" --suite absent --brain "$sign_in"
holds "voices without a suite is refused" refused "jarvis-selftest: refused: argument=--voices reason=requires-suite" --type hello --voices "$tmp" --brain "$sign_in"
holds "a voices directory that is absent is refused" refused "jarvis-selftest: refused: argument=--voices value=$tmp/no-voices reason=not-a-directory" --suite volume --voices "$tmp/no-voices" --brain "$sign_in"


echo "--- the acceptance case files and comparison"
compare_case="$tmp/case.json"
compare_record="$tmp/compare-record.json"
write_compare_case() {
  cat >"$compare_case" <<'JSON'
{"input":{"tts":"Please tell me what two plus two is."},"mode":"toggle","confirm":"none","heard":["two|2","plus"],"tool":"none","said":["four|4"]}
JSON
}
write_compare_record() { # HEARD TOOLS SENTENCE FIRST PASSED
  python3 - "$compare_record" "$@" <<'PY'
import json, sys
path, heard, tools, sentence, first, passed = sys.argv[1:]
json.dump({"passed": passed == "true", "heard": heard, "tools": json.loads(tools), "sentences": [{"ms": 1, "text": sentence}], "audio": {"firstMs": None if first == "null" else int(first), "longestGapMs": 10, "speechEndMs": 0, "sounds": []}}, open(path, "w"))
PY
}
compare_match() { write_compare_case; write_compare_record "two plus two" '[]' "It is 4." 300 true; [[ "$(call selftest_compare "$compare_case" "$compare_record" case)" == match ]] && grep -q '"source": "case"' "$compare_record" && grep -q '"differs": \[\]' "$compare_record"; }
compare_heard() { write_compare_case; write_compare_record 'two "two"' '[]' "It is 4." 300 true; [[ "$(call selftest_compare "$compare_case" "$compare_record")" == 'differs fields=heard heard="two \"two\"" expected="two|2 plus"' ]]; }
compare_tool_missing() { write_compare_case; python3 - "$compare_case" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["tool"]="media.volume"; json.dump(d, open(p,"w"))
PY
  write_compare_record "two plus" '[]' "It is 4." 300 true; [[ "$(call selftest_compare "$compare_case" "$compare_record")" == "differs fields=tool heard=\"two plus\" expected=\"two|2 plus\"" ]]; }
compare_tool_none() { write_compare_case; write_compare_record "two plus" '[{"tool":"media.volume","outcome":"completed"}]' "It is 4." 300 true; [[ "$(call selftest_compare "$compare_case" "$compare_record")" == "differs fields=tool heard=\"two plus\" expected=\"two|2 plus\"" ]]; }
compare_said() { write_compare_case; write_compare_record "two plus" '[]' "It is five." 300 true; [[ "$(call selftest_compare "$compare_case" "$compare_record")" == "differs fields=said heard=\"two plus\" expected=\"two|2 plus\"" ]]; }
compare_turn_audio() { write_compare_case; write_compare_record "two plus" '[]' "It is 4." null false; [[ "$(call selftest_compare "$compare_case" "$compare_record")" == "differs fields=turn,audio heard=\"two plus\" expected=\"two|2 plus\"" ]]; }
holds "comparison accepts matching heard words, no tool, spoken alternatives and audio" compare_match
holds "comparison differs when the heard transcript lacks a word" compare_heard
holds "comparison differs when an expected completed tool call is absent" compare_tool_missing
holds "comparison differs when a tool call exists where none is expected" compare_tool_none
holds "comparison differs when the spoken reply lacks a word" compare_said
holds "comparison accepts alternatives and reports turn plus missing audio" compare_turn_audio
control cut_functions "a comparison that skips the heard field" 'if not has_words(record.get("heard"), case["heard"]):' 'if False and not has_words(record.get("heard"), case["heard"]):' compare_heard
control cut_functions "a comparison that skips the tool field" 'elif not any(row.get("tool") == case["tool"] for row in tools):' 'elif False and not any(row.get("tool") == case["tool"] for row in tools):' compare_tool_missing
control cut_functions "a comparison line that leaves out the heard words" '" heard=" + quoted(record.get("heard") or "")' '""' compare_heard
control cut_functions "a comparison that skips the said field" 'if not has_words(spoken, case["said"]):' 'if False and not has_words(spoken, case["said"]):' compare_said

case_files_hold() {
  for file in "$repo/scripts/jarvis-selftest-cases"/*.json; do call selftest_case_check "$file" || return 1; done
  [[ -f $repo/scripts/jarvis-selftest-cases/volume.json && -f $repo/scripts/jarvis-selftest-cases/question.json && -f $repo/scripts/jarvis-selftest-cases/long.json && -f $repo/scripts/jarvis-selftest-cases/wake.json ]]
}
case_file_malformed() {
  printf '{"input":{"tts":"hello"},"mode":"toggle","confirm":"none","heard":["hello"],"tool":"none","said":["ok"],"extra":true}\n' >"$tmp/bad-case.json"
  ! call selftest_case_check "$tmp/bad-case.json" >/dev/null 2>&1
}
holds "every acceptance case file is well formed and the required cases exist" case_files_hold
holds "a malformed acceptance case file is refused" case_file_malformed
case_file_empty_words() {
  printf '{"input":{"tts":"hello"},"mode":"toggle","confirm":"none","heard":[],"tool":"none","said":["ok"]}\n' >"$tmp/bad-case.json"
  ! call selftest_case_check "$tmp/bad-case.json" >/dev/null 2>&1
}
case_file_bad_alt() {
  printf '{"input":{"tts":"hello"},"mode":"toggle","confirm":"none","heard":["two words"],"tool":"none","said":["ok"]}\n' >"$tmp/bad-case.json"
  ! call selftest_case_check "$tmp/bad-case.json" >/dev/null 2>&1
}
holds "an acceptance case file with an empty word list is refused" case_file_empty_words
holds "an acceptance case file with an invalid alternative token is refused" case_file_bad_alt
control cut_functions "a case check that accepts extra keys" 'if not required.issubset(data) or set(data) - (required | {"followUp", "clonedVoice"}):' 'if not required.issubset(data) and set(data) - (required | {"followUp", "clonedVoice"}):' case_file_malformed

case_child_args_local() {
  local voices="$tmp/voices" got
  mkdir -p "$voices"
  : >"$voices/volume.wav"
  got="$(call selftest_case_child_args "$repo/scripts/jarvis-selftest-cases/volume.json" "$voices")" || return 1
  [[ "$got" == $'source=local\n--wav\n'"$voices/volume.wav"$'\n--mode\ntoggle\n--confirm\nkey' ]]
}
case_child_args_case() {
  local voices="$tmp/voices" got
  mkdir -p "$voices"
  got="$(call selftest_case_child_args "$repo/scripts/jarvis-selftest-cases/question.json" "$voices")" || return 1
  [[ "$got" == $'source=case\n--tts\nPlease tell me what two plus two is.\n--mode\ntoggle\n--confirm\nnone' ]]
}
holds "a local recording replaces that case's input and reports source local" case_child_args_local
holds "a case without a local recording keeps its tracked input and reports source case" case_child_args_case
control cut_functions "a suite child argument builder that ignores local recordings" 'if local and os.path.isfile(local):' 'if False and local and os.path.isfile(local):' case_child_args_local


# The text-to-speech voice is the one the prepared setup's tier loads.
tts_voice_case() { # TIER WANT
  printf '{"tier": "%s"}\n' "$1" >"$tmp/tts-marker.json"
  [[ "$(call selftest_tts_voice "$repo/shell/plugins/vgs.jarvis" "$tmp/tts-marker.json")" == "$2" ]]
}
holds "a prepared setup that selects kokoro speaks with kokoro" tts_voice_case medium kokoro
holds "a prepared setup that selects piper speaks with piper" tts_voice_case small piper
control cut_functions "a fixed piper voice" 'print(speech.roles(artifacts, tier)["tts"]["id"])' 'print("piper")' tts_voice_case medium kokoro

echo "--- the audio measure"
audio_capture="$tmp/audio.jsonl"
write_audio_capture() {
  : >"$audio_capture"
  python3 - "$audio_capture" <<'PY'
import json, sys
path=sys.argv[1]
loud = set(list(range(900, 980, 10)) + list(range(1100, 1220, 10)) + list(range(1300, 1330, 10)) + list(range(1370, 1510, 10)) + list(range(1800, 2060, 10)))
with open(path, "w") as out:
    for at in range(880, 2080, 10):
        out.write(json.dumps({"at": at, "peak": 200 if at in loud else 0}) + "\n")
    out.write('{"at":')
PY
}
audio_measure_case() {
  write_audio_capture
  sounds="$(call devices_speaker_sounds "$audio_capture")" || return 1
  [[ $sounds == '[[900,980],[1100,1220],[1300,1510],[1800,2060]]' ]] || { echo "sounds=$sounds" >&2; return 1; }
  [[ "$(call selftest_audio "$sounds" 1000 2200)" == '{"firstMs":300,"longestGapMs":290}' ]] || return 1
  [[ "$(call selftest_audio '[[1200,1500]]' 1000 1600)" == '{"firstMs":200,"longestGapMs":200}' ]]
}
empty_audio_case() { [[ "$(call devices_speaker_sounds "$tmp/absent-capture.jsonl")" == '[]' && "$(call selftest_audio '[]' 1000 1400)" == '{"firstMs":null,"longestGapMs":400}' ]]; }
speech_tail_case() {
  python3 - "$tmp/tail.wav" <<'PY'
import array, math, sys, wave
rate=16000
samples=array.array("h", [round(12000*math.sin(2*math.pi*440*n/rate)) for n in range(rate//10)] + [0]*(rate//2))
with wave.open(sys.argv[1], "wb") as f:
    f.setnchannels(1); f.setsampwidth(2); f.setframerate(rate); f.writeframes(samples.tobytes())
PY
  [[ "$(call selftest_speech_tail "$tmp/tail.wav")" == 500 ]]
}
holds "speaker sounds join short closures and audio reports first speech and longest silence" audio_measure_case
holds "an absent capture has no sounds and no first audio" empty_audio_case
holds "speech tail reads a WAV's trailing silence" speech_tail_case
control cut_functions "an audio measure that counts an earcon as speech" 'if e - s >= 200' 'if e - s >= 100' audio_measure_case
control cut_functions "an audio measure that starts gaps at first sound" 'gaps, cursor = [], speech_end' 'gaps, cursor = [], reply[0][0]' audio_measure_case
control_devices() { # LABEL OLD NEW CASE
  local label="$1" old="$2" new="$3" case="$4"
  if ! mutate "$repo/scripts/smoke/devices.sh" "$old" "$new" "$mutant"; then fail "control: $label: its defect did not apply"; return; fi
  { sed -n '/^py_reply() {/,/^}/p; /^now_ms() {/p' "$repo/scripts/smoke/harness.sh"
    for name in selftest_tree_sum selftest_home_copy selftest_overseer selftest_mailbox selftest_daemon selftest_last selftest_service_phase selftest_voice_state selftest_gate_context selftest_turn selftest_wait selftest_draw_ms selftest_shown selftest_confirm \
      selftest_woke selftest_end selftest_audio selftest_audio_record selftest_wav_tail selftest_speech_tail selftest_open selftest_case_check selftest_compare selftest_case_child_args selftest_tts_voice selftest_suite_summary selftest_suite_stopped selftest_record selftest_voxtype_models_kept selftest_sidecar stopped stopped_gate selftest_finish; do sed -n "/^$name() {/,/^}/p" "$runner"; done
    sed -n '/^devices_speaker_sounds() {/,/^}/p' "$mutant"; } >"$functions"
  if "$case"; then fail "control: $label stayed green"; else ok "control: $label"; fi
  cut_functions "$runner"
}
control_devices "a sound reader that does not join a short closure" 'elif at - current[1] < 60:' 'elif at - current[1] < 0:' audio_measure_case


echo "--- wake opening and no-wake"
# open_run MODE PHASE VOICE: selftest_open over a service whose phase is
# PHASE and whose status.setupVoice is the JSON VOICE, logged in open.log.
# Its sleep moves the clock 100 s, so a wait that never ends times out at once.
open_run() { # MODE PHASE VOICE
  : >"$tmp/open.log"
  bash -c 'set -euo pipefail; source "$1"; log="$2"; mode="$3"; phase_word="$4"; voice="$5"
    traced() { case "$1" in phase) echo "$phase_word" ;; widget) echo listening ;; esac; }
    devices_voice_feed_state() { echo ready; }
    devices_voice_feed() { echo feed >>"$log"; }
    selftest_speech_tail() { echo 0; }
    sleep() { SECONDS=$((SECONDS + 100)); }
    stopped() { echo "stopped $*" >>"$log"; return 1; }
    stopped_gate() { echo "stopped $*" >>"$log"; return 1; }
    ipc() { echo "ipc $*" >>"$log"; case "$*" in smoke\ jarvisProcess) printf "%s\n" "{\"status\":{\"detail\":{\"phase\":\"$phase_word\"},\"setupVoice\":$voice}}" ;; *markJarvisTrace*) echo ok ;; *say*) echo ok ;; *) echo ok ;; esac; }
    selftest_open wav "$mode" ignored "$log.wav" 0
  ' _ "$functions" "$tmp/open.log" "$1" "$2" "$3"
}
open_case() { # MODE WANT_INTENT WANT_PHASE
  open_run "$1" "$3" null || return 1
  if [[ $2 == yes ]]; then grep -q 'intent talk-down' "$tmp/open.log"; else ! grep -q 'intent talk-down' "$tmp/open.log"; fi
}
# voice_case VOICE WANT: an Always open over status.setupVoice VOICE feeds
# (WANT feed) or stops as voice-loading without a feed.
voice_case() { # VOICE WANT
  open_run always armed "$1" || true
  if [[ $2 == feed ]]; then grep -qx feed "$tmp/open.log" && ! grep -q '^stopped' "$tmp/open.log"
  else ! grep -qx feed "$tmp/open.log" && grep -q '^stopped voice-loading voice=loading' "$tmp/open.log"; fi
}
open_always() { open_case always no armed; }
open_toggle() { open_case toggle yes listening; }
wake_trace() { python3 - <<'PY'
import json
print(json.dumps([{"kind":"mark","at":50,"value":"input"},{"kind":"phase","at":60,"value":"armed"},{"kind":"phase","at":70,"value":"armed"}]))
PY
}
wake_empty_trace() { python3 - <<'PY'
import json
print(json.dumps([{"kind":"mark","at":50,"value":"input"}]))
PY
}
wake_reads_armed() { [[ "$(wake_trace | call selftest_woke)" == armed && "$(wake_empty_trace | call selftest_woke)" == armed && "$(call selftest_end no-wake)" == no-wake ]]; }
wake_woke_trace() { python3 - <<'PY'
import json
print(json.dumps([{"kind":"mark","at":50,"value":"input"},{"kind":"phase","at":60,"value":"armed"},{"kind":"phase","at":70,"value":"thinking"}]))
PY
}
wake_reads_woke() { [[ "$(wake_woke_trace | call selftest_woke)" == woke ]]; }
holds "Always mode opens without a Talk intent and waits for armed" open_always
holds "Toggle mode opens with the Talk intent" open_toggle
holds "Always mode waits out a loading voice and stops as voice-loading" voice_case '{"tone":"info","text":"Loading","action":false}' voice-loading
holds "Always mode feeds once the voice step is done" voice_case '{"tone":"ok","text":"Done","action":false}' feed
holds "Always mode feeds over a loaded voice whose microphone is not checked" voice_case '{"tone":"info","text":"Not checked","action":"check"}' feed
holds "a trace that stays armed after the input mark reads no-wake" wake_reads_armed
holds "a wake trace that leaves armed reads woke" wake_reads_woke
control cut_functions "an Always open that sends the Talk intent" 'if [[ $mode == always ]]; then
    selftest_wait 30 armed selftest_service_phase' 'if [[ $mode == always ]]; then
    ipc smoke invokeInstance service vgs.jarvis intent talk-down >/dev/null || stopped talk-not-sent
    selftest_wait 30 armed selftest_service_phase' open_always
control cut_functions "an Always open that feeds while the voice loads" '    selftest_wait 60 loaded selftest_voice_state || stopped_gate voice-loading "voice=$reading"' '    :' voice_case '{"tone":"info","text":"Loading","action":false}' voice-loading
control cut_functions "an Always open that reads an unchecked microphone as a loading voice" ' and not offered else "loaded")' ' else "loaded")' voice_case '{"tone":"info","text":"Not checked","action":"check"}' feed
control cut_functions "a verdict that takes no-wake as completed" '    no-wake) echo no-wake ;;' '    no-wake) echo completed ;;' wake_reads_armed

suite_summary_case() { # CASES MATCHED DIFFER NOT_RUN FAILED DIR WANT_STATUS
  local cases="$1" matched="$2" differ="$3" not_run="$4" failed="$5" dir="$6" want_status="$7" status=0
  call selftest_suite_summary "$cases" "$matched" "$differ" "$not_run" "$failed" "$dir" >"$tmp/out" || status=$?
  [[ $status -eq $want_status ]]
}
holds "suite summary exits 0 when all cases matched" suite_summary_case 2 2 0 0 0 "$tmp/suite" 0
holds "suite summary exits 1 when any case differs" suite_summary_case 2 1 1 0 0 "$tmp/suite" 1
holds "suite summary exits 77 when a case could not run and none differed" suite_summary_case 2 1 0 1 0 "$tmp/suite" 77
holds "suite summary exits 1 when a case failed without a record and none differed" suite_summary_case 2 1 0 0 1 "$tmp/suite" 1
suite_stopped_case() { local status=0; call selftest_suite_stopped 2 1 0 0 0 "$tmp/suite" >"$tmp/out" || status=$?; [[ $status -eq 1 && "$(<"$tmp/out")" == "selftest=suite cases=2 matched=1 differ=0 not-run=0 dir=$tmp/suite stopped=signal" ]]; }
holds "a stopped suite prints a signal summary and exits 1" suite_stopped_case
control cut_functions "a stopped suite summary that exits successfully" '  return 1 # signal stops the suite' '  return 0 # signal stops the suite' suite_stopped_case

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

class Manager(dbus.service.Object):
    @dbus.service.method("org.freedesktop.systemd1.Manager", in_signature="ssa(sv)a(sa(sv))", out_signature="o")
    def StartTransientUnit(self, name, mode, properties, auxiliary):
        note("StartTransientUnit")
        return dbus.ObjectPath("/org/freedesktop/systemd1/job/1")

class Item(dbus.service.Object):
    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="ss", out_signature="v")
    def Get(self, interface, property):
        note("Get " + property)
        return dbus.Boolean(open(mode_file).read().strip() == "locked", variant_level=1)
    @dbus.service.method("org.freedesktop.Secret.Item", in_signature="o", out_signature="(oayays)")
    def GetSecret(self, session):
        note("GetSecret")
        if open(mode_file).read().strip() != "present":
            raise dbus.exceptions.DBusException("locked", name="org.freedesktop.Secret.Error.IsLocked")
        return (dbus.ObjectPath(SESSION), dbus.ByteArray(b""), dbus.ByteArray(b"stand-in-key"), "text/plain")
    @dbus.service.method("org.freedesktop.Secret.Item", out_signature="o")
    def Delete(self):
        note("Delete")
        return dbus.ObjectPath("/")

DBusGMainLoop(set_as_default=True)
session = dbus.SessionBus()
names = [dbus.service.BusName(name, session) for name in ("org.freedesktop.secrets", "org.vgshell.SelftestOther", "org.freedesktop.systemd1")]
objects = [Service(session, "/org/freedesktop/secrets"), Other(session, "/org/vgshell/SelftestOther"), Item(session, ITEM), Manager(session, "/org/freedesktop/systemd1")]
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

  # The real world owns this proxy on the scratch bus. The consumer tests
  # below use its filtered socket; their stand-in harness starts no shell.
  local proxy_world_pid="" proxy_root=""
  mkdir -p "$tmp/proxy-output"
  proxy_start() { # FENCE
    rm -f -- "$tmp/proxy-output/root"
    env -i PATH="$path" HOME="$world" TMPDIR=/tmp DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
      "$BASH" "$1" --checkout "$repo" --out "$tmp/proxy-output" --secrets --sign-in COPILOT_HOME "$world/.copilot" \
      "$BASH" -c 'printf "%s\n" "$VGSHELL_WORLD_ROOT" >"$1/root"; while :; do sleep 1 & wait $!; done' _ "$tmp/proxy-output" >"$tmp/proxy-output/log" 2>&1 &
    proxy_world_pid=$!
    for _ in $(seq 1 100); do [[ ! -s $tmp/proxy-output/root ]] || break; kill -0 "$proxy_world_pid" 2>/dev/null || break; sleep 0.05; done
    [[ -s $tmp/proxy-output/root ]] || { cat "$tmp/proxy-output/log"; return 1; }
    proxy_root="$(<"$tmp/proxy-output/root")"
    selftest_proxy_env=(XDG_RUNTIME_DIR="$proxy_root")
  }
  proxy_stop() {
    kill -TERM "$proxy_world_pid" 2>/dev/null || true
    wait "$proxy_world_pid" 2>/dev/null || true
    [[ ! -e $proxy_root ]]
  }
  fence_control() { # LABEL OLD NEW CASE...
    local label="$1" old="$2" new="$3"
    shift 3
    proxy_stop || { fail "proxy root remains"; return; }
    if ! mutate "$repo/scripts/smoke/gpu-fence.sh" "$old" "$new" "$tmp/proxy-mutant.sh"; then
      fail "control: $label mutation"
    elif ! proxy_start "$tmp/proxy-mutant.sh"; then
      fail "control: $label proxy start"
    elif "$@"; then
      fail "control: $label stayed green"
    else
      ok "control: $label"
    fi
    proxy_stop || fail "control: $label proxy root remains"
    proxy_start "$repo/scripts/smoke/gpu-fence.sh" || { fail "proxy restart"; return; }
  }
  proxy_owner_lifetime() { # FENCE
    local result=0 owner_status=0
    proxy_start "$1" || return 1
    python3 - "$proxy_world_pid" <<'PY' || result=$?
import os
from pathlib import Path
import select
import signal
import sys

owner = int(sys.argv[1])
children = list(map(int, Path(f"/proc/{owner}/task/{owner}/children").read_text().split()))
proxies = []
for child in children:
    try:
        command = Path(f"/proc/{child}/cmdline").read_bytes().split(b"\0")[0]
    except FileNotFoundError:
        continue
    if Path(os.fsdecode(command)).name == "xdg-dbus-proxy":
        proxies.append(child)
assert len(proxies) == 1, proxies
proxy = proxies[0]
owner_fd, proxy_fd = os.pidfd_open(owner), os.pidfd_open(proxy)
ended = False
try:
    lease = os.readlink(f"/proc/{proxy}/fd/1")
    pending = children[:]
    while pending:
        child = pending.pop()
        if child == proxy:
            continue
        directory = Path(f"/proc/{child}")
        try:
            pending.extend(map(int, (directory / f"task/{child}/children").read_text().split()))
            for descriptor in (directory / "fd").iterdir():
                try:
                    assert os.readlink(descriptor) != lease, (child, str(descriptor))
                except FileNotFoundError:
                    pass
        except FileNotFoundError:
            pass
    signal.pidfd_send_signal(owner_fd, signal.SIGKILL)
    ended = bool(select.select([proxy_fd], [], [], 5)[0])
    print("proxy-owner-kill: proxy=" + ("exited" if ended else "alive"))
finally:
    if not select.select([owner_fd], [], [], 0)[0]:
        signal.pidfd_send_signal(owner_fd, signal.SIGKILL)
    if not select.select([proxy_fd], [], [], 0)[0]:
        signal.pidfd_send_signal(proxy_fd, signal.SIGKILL)
        assert select.select([proxy_fd], [], [], 5)[0], "proxy cleanup"
    os.close(proxy_fd)
    os.close(owner_fd)
sys.exit(0 if ended else 1)
PY
    wait "$proxy_world_pid" 2>/dev/null || owner_status=$?
    [[ $owner_status == 137 && -d $proxy_root ]] || result=1
    # SIGKILL deliberately leaves this acquired fixture root.
    chmod -R u+rwX -- "$proxy_root"
    rm -rf -- "${proxy_root:?}"
    return "$result"
  }
  holds "the outside filtered proxy exits when its world owner is killed" proxy_owner_lifetime "$repo/scripts/smoke/gpu-fence.sh"
  if ! mutate "$repo/scripts/smoke/gpu-fence.sh" 'exec env -i "$(command -v xdg-dbus-proxy)" --fd=1' \
    'printf x; exec env -i "$(command -v xdg-dbus-proxy)"' "$tmp/proxy-lease-mutant.sh"; then
    fail "control: proxy lifetime mutation"
  elif proxy_owner_lifetime "$tmp/proxy-lease-mutant.sh"; then
    fail "control: an outside proxy without its lifetime lease stayed green"
  else
    ok "control: an outside proxy without its lifetime lease"
  fi
  proxy_start "$repo/scripts/smoke/gpu-fence.sh" || { fail "world proxy start"; return; }

  suite_account_entry() { # BRAIN VOICE MODEL SIGN_IN
    local brain_id="$1" selected_voice="$2" selected_model="$3" sign_in_dir="$4" held=0
    local old_session_bus=("${session_bus[@]}") expected
    session_bus=(DBUS_SESSION_BUS_ADDRESS="unix:path=$bus")
    echo 1 >"$tmp/fence-answer"
    run --suite volume --brain "$brain_id" --voice "$selected_voice" --model "$selected_model" --out "$tmp/suite-entry"
    expected=check$'\n'"run [--net] [--out] [$tree/tmp/display-record] [--out] [$tree/tmp/selftest-records] [--out] [$tree/tmp/qml-smoke] [--out] [$tmp/suite-entry]"
    [[ -z $sign_in_dir ]] || expected+=" [--sign-in] [CLAUDE_CONFIG_DIR] [$sign_in_dir]"
    expected+=" [--secrets] [$tree/scripts/jarvis-selftest.sh] [--suite] [volume] [--brain] [$brain_id] [--voice] [$selected_voice] [--model] [$selected_model] [--out] [$tmp/suite-entry]"
    [[ $status == 0 && $(<"$tmp/fence.log") == "$expected" && ! -s $tmp/harness.log ]] || held=1
    echo 0 >"$tmp/fence-answer"
    session_bus=("${old_session_bus[@]}")
    return "$held"
  }
  suite_entries=("$sign_in|realtime|fixture-model|$world/.claude" "$saved_key|local|fixture-model|" "$local_id|realtime|fixture-model|")
  for suite_entry in "${suite_entries[@]}"; do
    IFS='|' read -r suite_brain suite_voice suite_model suite_sign_in <<<"$suite_entry"
    holds "suite prepares its $suite_voice voice and selected account before world entry" suite_account_entry "$suite_brain" "$suite_voice" "$suite_model" "$suite_sign_in"
  done
  control plant "a suite that enters before preparing its selected account" '# node on PATH may be a version manager' \
    'if [[ -n $suite_name ]]; then selftest_suite "$suite_name"; exit $?; fi
# node on PATH may be a version manager' suite_account_entry "$sign_in" realtime fixture-model "$world/.claude"

  # The two calls the filter must stop, asked of the scratch bus itself
  # first: each reaches the stand-in there.
  other=(org.vgshell.SelftestOther /org/vgshell/SelftestOther org.vgshell.SelftestOther Ping)
  unlock=(org.freedesktop.secrets /org/freedesktop/secrets org.freedesktop.Secret.Service Unlock ao 1 /org/freedesktop/secrets/collection/selftest/1)
  transient=(org.freedesktop.systemd1 /org/freedesktop/systemd1 org.freedesktop.systemd1.Manager StartTransientUnit 'ssa(sv)a(sa(sv))' fixture.service replace 0 0)
  direct() { : >"$tmp/keyring.calls"; env -i PATH="$PATH" DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" busctl --user --auto-start=no --timeout=5 --json=short call "$@" >/dev/null; }
  got() { grep -q -x -e "$1" -- "$tmp/keyring.calls"; }
  other_direct() { direct "${other[@]}" && got Ping; }
  unlock_direct() { direct "${unlock[@]}" && got Unlock; }
  transient_direct() { direct "${transient[@]}" && got StartTransientUnit; }
  holds "on the scratch bus itself the second name answers" other_direct
  holds "on the scratch bus itself an unlock reaches the stand-in" unlock_direct
  holds "on the scratch bus itself StartTransientUnit reaches the stand-in" transient_direct

  # What a case reads while the run's filter and secret-tool stand: each
  # probe's stdout and status, and the references the sandbox holds.
  cat >"$tmp/at-start.sh" <<SH
probe() { # NAME CMD...
  local name="\$1" answer=0
  shift
  "\$@" >"$tmp/probe.\$name" 2>"$tmp/probe.\$name.err" </dev/null || answer=\$?
  echo "\$answer" >"$tmp/probe.\$name.status"
}
filtered=(env -i PATH="\$PATH" DBUS_SESSION_BUS_ADDRESS="unix:path=\$secrets_bus" busctl --user --auto-start=no --timeout=5 --json=short call)
probe own "\$shim/secret-tool" lookup service vgs-jarvis provider openai account selftest origin https://api.openai.com
probe foreign "\$shim/secret-tool" lookup service vgs-notifications account selftest
probe store "\$shim/secret-tool" store --label=planted service vgs-jarvis
probe other "\${filtered[@]}" ${other[*]}
probe unlock "\${filtered[@]}" ${unlock[*]}
probe transient "\${filtered[@]}" org.freedesktop.systemd1 /org/freedesktop/systemd1 org.freedesktop.systemd1.Manager StartTransientUnit 'ssa(sv)a(sa(sv))' fixture.service replace 0 0
probe properties "\${filtered[@]}" org.freedesktop.secrets /org/freedesktop/secrets org.freedesktop.DBus.Properties GetAll s org.freedesktop.Secret.Service
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
  key_read() { key_run present "${brain_key[@]}" && [[ $status -eq 0 ]] && answered own 0 && answered properties 0 && got 'SearchItems .*' && got OpenSession && got GetSecrets && got GetAll && [[ "$(<"$tmp/probe.own")" == stand-in-key ]]; }
  key_alone() {
    key_run present "${brain_key[@]}" && [[ "$(tail -n 1 -- "$tmp/harness.log")" == "start_shell $trace_word" ]] &&
      python3 -c 'import json,sys; saved, world = (json.load(open(a)) for a in sys.argv[1:]); sys.exit(saved != [r for r in world if r["provider"] == "openai"])' "$tmp/probe.keys" "$state/keys.json"
  }
  foreign_stays() { key_run present "${brain_key[@]}" && answered foreign 1 && ! grep -q -F vgs-notifications -- "$tmp/keyring.calls"; }
  store_logged() { key_run present "${brain_key[@]}" && answered store 1 && [[ "$(<"$sandbox/auth.calls")" == "secret-tool store --label=planted service vgs-jarvis" ]]; }
  other_hidden() { key_run present "${brain_key[@]}" && [[ $status == 0 && -f $tmp/probe.other.status ]] && ! answered other 0 && ! got Ping; }
  unlock_denied() { key_run present "${brain_key[@]}" && [[ $status == 0 && -f $tmp/probe.unlock.status ]] && ! answered unlock 0 && ! got Unlock; }
  transient_denied() { key_run present "${brain_key[@]}" && [[ $status == 0 && -f $tmp/probe.transient.status ]] && ! answered transient 0 && ! got StartTransientUnit; }
  holds "Jarvis's own lookup of the run's key reads it through the filter" key_read
  holds "the sandbox holds the reference of the run's key alone, and the shell starts with no account word" key_alone
  holds "a lookup of another key never reaches the bus" foreign_stays
  holds "a store stays the sentinel's, which logs it" store_logged
  holds "the filter hides a bus name other than org.freedesktop.secrets" other_hidden
  holds "the filter refuses an unlock" unlock_denied
  holds "the world proxy refuses StartTransientUnit" transient_denied

  # One table for what the keyring answers before Jarvis starts: the case,
  # the keyring's mode, the session bus the run is given and the run's last
  # line. The run ends 77 with the harness's shell stopped and never
  # started, and no unlock asked.
  key_rows=(
    "a keyring that holds no item for the key|absent|unix:path=$bus|selftest=keyring-no-key key=absent"
    "a keyring that holds the key locked|locked|unix:path=$bus|selftest=keyring-locked"
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
    python3 - "$tmp/voice.wav" <<'PY'
import array, sys, wave
with wave.open(sys.argv[1], "wb") as f:
    f.setnchannels(1); f.setsampwidth(2); f.setframerate(16000); f.writeframes(array.array("h", [0] * 160).tobytes())
PY
    inputs=()
    key_run present --wav "$tmp/voice.wav" --brain "$sign_in" --voice realtime
    [[ $status -eq 0 && "$(tail -n 1 -- "$tmp/harness.log")" == "start_shell CLAUDE_CONFIG_DIR=$world/.claude $trace_word" && ! -e $sandbox/home/.local/share/vgshell/jarvis/local &&
      "$(row_of)" == "[{\"brain\": \"$sign_in\", \"id\": \"vgs.jarvis\", \"microphone\": \"vgs-smoke-voice\", \"mode\": \"toggle\", \"speaker\": \"vgs-smoke-speakers\", \"voiceAccount\": \"$saved_key\", \"voiceProvider\": \"realtime\"}, [\"vgs.jarvis\"]]" ]] || held=1
    inputs=("${voice_inputs[@]}")
    return "$held"
  }
  holds "the realtime voice names the one saved OpenAI key as its account and takes no prepared local voice" voice_named


  control plant "a runner that starts Jarvis with no key stored" '      absent) unavailable keyring-no-key key=absent ;;' '      absent) ;;' key_refused "${key_rows[0]}"
  control plant "a runner that starts Jarvis over a locked keyring" '      locked) unavailable keyring-locked ;;' '      locked) ;;' key_refused "${key_rows[1]}"
  fence_control "a world whose bus is no filter" '"$fence_dir/secrets-bus" --filter "${selftest_secrets_rules[@]}"' '"$fence_dir/secrets-bus"' other_hidden
  fence_control "a filter that lets the secrets service's every call through" \
    '  --call=org.freedesktop.secrets=org.freedesktop.Secret.Service.SearchItems@/org/freedesktop/secrets' '  --talk=org.freedesktop.secrets' unlock_denied
  control plant "a secret-tool that sends every call to the bus" 'exec $(printf %q "$(sentinel_saved "$shim/secret-tool")") "\$@"' \
    'DBUS_SESSION_BUS_ADDRESS=$(printf %q "unix:path=$secrets_bus") exec $(printf %q "$secret_tool") "\$@"' foreign_stays
  control plant "a runner that hands the sandbox every saved reference" '>"$sandbox/selftest-lookups" || stopped keys-not-saved' \
    '>"$sandbox/selftest-lookups" && cp -- "$HOME/.local/state/vgshell/jarvis/keys.json" "$home/.local/state/vgshell/jarvis/keys.json" || stopped keys-not-saved' key_alone
  control plant "a runner that names no account for the realtime voice" '    row["voiceAccount"] = voice_account' '    pass' voice_named
  # Copilot's native store uses Item.GetSecret and Properties.Get rather
  # than libsecret's Service.GetSecrets. Read these through the bus passed
  # to the shell, not a socket constructed independently of that word.
  cat >"$tmp/at-start.sh" <<SH
address=""
for word in "\${@:4}"; do [[ \$word != DBUS_SESSION_BUS_ADDRESS=* ]] || address="\${word#*=}"; done
filtered=(env -i PATH="\$PATH" DBUS_SESSION_BUS_ADDRESS="\$address" busctl --user --auto-start=no --timeout=5 --json=short call)
"\${filtered[@]}" org.freedesktop.secrets /org/freedesktop/secrets org.freedesktop.Secret.Service SearchItems 'a{ss}' 1 service vgs-jarvis >"$tmp/native.search"
"\${filtered[@]}" org.freedesktop.secrets /org/freedesktop/secrets/collection/selftest/1 org.freedesktop.DBus.Properties Get ss org.freedesktop.Secret.Item Locked >"$tmp/native.locked"
native_status=0
"\${filtered[@]}" org.freedesktop.secrets /org/freedesktop/secrets/collection/selftest/1 org.freedesktop.Secret.Item GetSecret o /org/freedesktop/secrets/session/1 >/dev/null 2>&1 || native_status=\$?
printf '%s\n' "\$native_status" >"$tmp/native.status"
"\${filtered[@]}" ${unlock[*]} >/dev/null 2>&1 || true
"\${filtered[@]}" org.freedesktop.secrets /org/freedesktop/secrets/collection/selftest/1 org.freedesktop.Secret.Item Delete >/dev/null 2>&1 || true
SH
  copilot_reads() {
    key_run "$1" --type hello --brain "$copilot_id"
    [[ $status -eq 0 && ! -e $sandbox/home/.local/state/vgshell/jarvis/keys.json ]] &&
      grep -q -F -- "start_shell COPILOT_HOME=$world/.copilot DBUS_SESSION_BUS_ADDRESS=unix:path=$proxy_root/secrets-bus $trace_word" "$tmp/harness.log" &&
      got 'Get Locked' && got GetSecret && ! got Unlock && ! got Delete || return 1
    python3 - "$tmp/native.search" "$tmp/native.locked" "$1" <<'PY'
import json, sys
search, locked = (json.load(open(p))["data"] for p in sys.argv[1:3])
mode = sys.argv[3]
sys.exit(bool(search[0]) != (mode == "present") or bool(search[1]) != (mode == "locked") or locked[0]["data"] != (mode == "locked"))
PY
    [[ $? -eq 0 ]] || return 1
    if [[ $1 == present ]]; then [[ $(<"$tmp/native.status") == 0 ]]; else [[ $(<"$tmp/native.status") != 0 ]]; fi
  }
  for key_mode in present locked absent; do holds "Copilot's filtered bus allows native reads with $key_mode credentials and refuses unlocks and deletes" copilot_reads "$key_mode"; done
  control plant "a Copilot runner that hands no filtered bus to its native store" '  [[ $copilot_keyring == false ]] || account_word+=("DBUS_SESSION_BUS_ADDRESS=unix:path=$secrets_bus")' '  :' copilot_reads present
  fence_control "a Copilot filter that drops the native item read" "        '--call=org.freedesktop.secrets=org.freedesktop.Secret.Item.GetSecret@/org/freedesktop/secrets/collection/*'" '' copilot_reads present
  fence_control "a Copilot filter that drops its native lock-state read" "        '--call=org.freedesktop.secrets=org.freedesktop.DBus.Properties.Get@/org/freedesktop/secrets/collection/*'" '' copilot_reads present
  fence_control "a Copilot filter that permits item writes" "        '--call=org.freedesktop.secrets=org.freedesktop.Secret.Item.GetSecret@/org/freedesktop/secrets/collection/*'" "        '--call=org.freedesktop.secrets=org.freedesktop.Secret.Item.*@/org/freedesktop/secrets/collection/*'" copilot_reads present

  provider_program() { # PROVIDER BRAIN ACCOUNT_DIRECTORY
    printf 'env -i PATH="$shell_start_path" HOME="$home" "${@:4}" %q >%q\n' "$1" "$tmp/program-account" >"$tmp/at-start.sh"
    key_run present --type hello --brain "$2"
    [[ $status -eq 0 && $(<"$tmp/program-account") == "$3" ]]
  }
  provider_rows=("claude|$sign_in|$world/.claude" "codex|$codex_id|$world/.codex" "copilot|$copilot_id|$world/.copilot" "pi|$pi_id|$world/.pi/agent")
  for provider_row in "${provider_rows[@]}"; do
    IFS='|' read -r provider brain_id account_directory <<<"$provider_row"
    holds "$provider executes its installed program and keeps the selected account" provider_program "$provider" "$brain_id" "$account_directory"
  done
  control plant "a runner whose sandbox PATH keeps the account-changing wrapper first" '[[ -z $brain_program ]] || export PATH="$(dirname -- "$brain_program"):$PATH"' ':' provider_program codex "$codex_id" "$world/.codex"
  proxy_stop || fail "world proxy cleanup"
  selftest_proxy_env=()
  session_bus=()
  rm -f -- "$tmp/at-start.sh"
}
# What the keyring cases need. An import that fails is named by the package
# that holds it: the stand-in service's dbus is python-dbus's and its main
# loop, gi, python-gobject's.
bus_missing=()
for tool in dbus-daemon xdg-dbus-proxy secret-tool busctl; do command -v -- "$tool" >/dev/null || bus_missing+=("$tool"); done
python3 -c 'import dbus.service, dbus.mainloop.glib' 2>/dev/null || bus_missing+=(python-dbus)
python3 -c 'from gi.repository import GLib' 2>/dev/null || bus_missing+=(python-gobject)
if [[ ${#bus_missing[@]} -gt 0 ]]; then
  printf '  not measured: missing=%s\n' "$(IFS=,; echo "${bus_missing[*]}")"
else
  keyring_cases
fi

echo "--- the readers of the service and the trace"
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
gate_context_reads() {
  local reply='{"status":{"setup":{"tone":"warning","lines":["choose a brain"]},"daemon":{"tone":"danger","text":"offline"},"detail":{"state":{"gate":{"kind":"unconfigured","reason":"brain"}}}}}'
  [[ "$(printf '%s\n' "$reply" | call selftest_gate_context)" == 'gate=unconfigured'$'\n''selftest: setup={"lines":["choose a brain"],"tone":"warning"} setupVoice=null daemon={"text":"offline","tone":"danger"} gate={"kind":"unconfigured","reason":"brain"} causes=null' ]]
}
gate_context_absent_detail() {
  [[ "$(printf '%s\n' '{"status":{"setup":null,"daemon":null}}' | call selftest_gate_context)" == 'gate=none'$'\n''selftest: setup=null setupVoice=null daemon=null gate={"kind":"none"} causes=null' ]]
}
holds "the gate context reader names gate, setup and daemon from jarvisProcess" gate_context_reads
holds "the gate context reader reports gate none with absent detail" gate_context_absent_detail
gate_failure_data() { # TONE CAUSES_JSON
  local tone="$1" causes="$2" status=0
  python3 - "$tmp/gate-reply.json" "$tmp/gate-answer.json" "$tone" "$causes" <<'PY'
import json,sys
reply, answer, tone, causes = sys.argv[1:]
json.dump({"status":{"setupVoice":{"tone":tone,"text":"diagnostic input","action":False},
                     "detail":{"state":{"gate":{"kind":"down","reason":"unconfigured"}}}}}, open(reply,"w"))
if causes == "unavailable":
    open(answer,"w").write("absent")
else:
    json.dump({"kind":"answered","causes":json.loads(causes)}, open(answer,"w"))
PY
  selftest_node="$node_bin" bash -c '
    set -euo pipefail
    source "$1"
    fixture_reply_file=$2 fixture_answer_file=$3
    trap '\''rm -f -- "$fixture_reply_file" "$fixture_answer_file"'\'' EXIT
    ipc() {
      case "$*" in
        "smoke jarvisProcess") cat -- "$fixture_reply_file" ;;
        "smoke readInstance service vgs.jarvis setupAnswer") cat -- "$fixture_answer_file" ;;
        *) return 1 ;;
      esac
    }
    selftest_voxtype_models_kept() { return 0; }
    stopped_gate not-ready widget=off
  ' _ "$functions" "$tmp/gate-reply.json" "$tmp/gate-answer.json" >"$tmp/gate-failure.out" 2>"$tmp/gate-failure.err" || status=$?
  [[ $status -eq 1 && ! -e $tmp/gate-reply.json && ! -e $tmp/gate-answer.json && ! -s $tmp/gate-failure.err ]] || return 1
  python3 - "$tmp/gate-failure.out" "$tone" "$causes" <<'PY'
import json,sys
lines=open(sys.argv[1]).read().splitlines()
assert lines[-1] == "selftest=not-ready widget=off gate=down"
line=next(value for value in lines if value.startswith("selftest: "))[10:]
decoder=json.JSONDecoder()
values={}
while line:
    key,rest=line.split("=",1)
    value,end=decoder.raw_decode(rest)
    values[key]=value
    line=rest[end:].lstrip()
assert values["setupVoice"]["tone"] == sys.argv[2]
assert values["setupVoice"]["action"] is False
assert values["causes"] == (None if sys.argv[3] == "unavailable" else json.loads(sys.argv[3]))
assert values["gate"] == {"kind":"down","reason":"unconfigured"}
PY
}
for gate_row in 'warning|["speech=local-not-set-up"]' 'danger|["speech=dictation-failed","brain=unselected"]' 'info|unavailable'; do
  holds "stopped_gate retains typed voice and daemon causes before teardown for ${gate_row%%|*}" gate_failure_data "${gate_row%%|*}" "${gate_row#*|}"
done
control cut_functions "a stopped diagnostic that drops the actual voice row" 'compact(values.get("setupVoice"))' 'compact(None)' gate_failure_data warning '["speech=local-not-set-up"]'
control cut_functions "a stopped diagnostic that drops the actual daemon causes" 'compact(causes)' 'compact(None)' gate_failure_data warning '["speech=local-not-set-up"]'
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
control cut_functions "a service reader that compares no setting" 'missing = [key for key in want if held.get(key) != want[key]]' 'missing = []' daemon_reads "${daemon_rows[3]}"
control cut_functions "a gate context reader that ignores the live gate" 'gate = state.get("gate") or {"kind": "none"}' 'gate = {"kind": "none"}' gate_context_reads
control cut_functions "a turn reader that ends before Jarvis worked" 'or worked and last in' 'or last in' turn_reads "${turn_rows[3]}"
control cut_functions "a turn reader that counts the phases before the input" 'phases = [e["value"] for e in events[marks[-1]:] if e["kind"] == "phase"] if marks else []
last = phases[-1]' 'phases = [e["value"] for e in events if e["kind"] == "phase"] if marks else []
last = phases[-1]' turn_reads "${turn_rows[1]}"

echo "--- the Confirm key"
# The request reader: the request Jarvis holds, once Session has its shown
# time.
approval() { service ready "\"detail\": {\"phase\": \"confirming\", \"state\": {\"approval\": $1}}"; }
shown_rows=(
  'none|{"kind": "none"}'
  'none|{"kind": "held", "gen": 4, "id": "call-7", "shownAt": null}'
  '4:call-7|{"kind": "held", "gen": 4, "id": "call-7", "shownAt": 91250.5}'
)
shown_reads() { [[ "$(approval "${1#*|}" | call selftest_shown)" == "${1%%|*}" ]]; }
for row in "${shown_rows[@]}"; do holds "the request reader answers ${row%%|*} for the approval ${row#*|}" shown_reads "$row"; done
control cut_functions "a request reader that takes a request Jarvis has not shown" ' and held["shownAt"] is not None' '' shown_reads "${shown_rows[1]}"
# pressed DRAW POLL...: the times of the presses of one run that polls at
# each POLL, NOW:ANSWER:REQUEST, ANSWER being the probe's reply to a press
# made then.
pressed() {
  local draw="$1"
  shift
  : >"$tmp/presses"
  bash -c 'set -euo pipefail; source "$1"; draw="$2" log="$3"; shift 3
    ipc() { echo "$now" >>"$log"; echo "$answer"; }
    for poll in "$@"; do
      IFS=: read -r now answer request <<<"$poll"
      selftest_confirm "$draw" "$now" "$request"
    done' _ "$functions" "$draw" "$tmp/presses" "$@" || return 1
  tr '\n' ' ' <"$tmp/presses"
}
# One table: the polls and the times a press must be made at. The guard is
# 500 in every row, a number of no clock.
press_rows=(
  "a request shown is pressed once, at the first poll the guard has passed by|1000:sent:none 1200:sent:4:a 1400:sent:4:a 1699:sent:4:a 1700:sent:4:a 1900:sent:4:a 2400:sent:4:a|1700 "
  "a second request waits its own guard|1000:sent:4:a 1500:sent:4:a 1600:sent:4:b 2000:sent:4:b 2100:sent:4:b 2300:sent:4:b|1500 2100 "
  "a press the probe did not send is made again|1000:sent:4:a 1500:none:4:a 1700:sent:4:a 1900:sent:4:a|1500 1700 "
  "a reader's word that names no request is never pressed|1000:sent:absent 2000:sent:absent|"
)
press_case() { # ROW
  local polls want
  IFS='|' read -r _ polls want <<<"$1"
  # shellcheck disable=SC2086 # the row's polls are the words
  [[ "$(pressed 500 $polls)" == "$want" ]]
}
for row in "${press_rows[@]}"; do holds "${row%%|*}" press_case "$row"; done
control cut_functions "a runner that presses before the draw guard has passed" '  (($2 - confirm_seen_ms >= $1)) || return 0' '  :' press_case "${press_rows[0]}"
control cut_functions "a runner that presses a request at every poll" '  [[ $reply != sent ]] || confirm_pressed="$3"' '  :' press_case "${press_rows[0]}"
control cut_functions "a runner that counts a second request's guard from the first" 'confirm_seen="$3" confirm_seen_ms="$2"' 'confirm_seen="$3" confirm_seen_ms="${confirm_seen_ms:-$2}"' press_case "${press_rows[1]}"
control cut_functions "a runner that takes an unsent press as made" '  [[ $reply != sent ]] || confirm_pressed="$3"' '  confirm_pressed="$3"' press_case "${press_rows[2]}"
control cut_functions "a runner that presses for a word that names no request" '[[ $3 == *:* && ' '[[ ' press_case "${press_rows[3]}"
# The guard itself is Session's: the runner's read of it against the one
# line of Session.js that sets it.
draw_read() {
  local line
  line="$(grep -E '^var APPROVAL_DRAW_MS = [0-9]+;$' "$repo/shell/plugins/vgs.jarvis/Session.js")" || return 1
  line="${line#var APPROVAL_DRAW_MS = }"
  [[ "$(call selftest_draw_ms "$repo")" == "${line%;}" ]]
}
holds "the draw guard the runner waits is the one Session.js sets" draw_read
control cut_functions "a runner that waits another of Session's bounds" ').APPROVAL_DRAW_MS;' ').APPROVAL_TIMEOUT_MS;' draw_read

echo "--- the record"
mkdir -p "$tmp/audit"
cat >"$tmp/audit/2026-10-10.jsonl" <<'JSONL'
{"time": "2026-10-10T00:00:00.000Z", "kind": "action", "gen": 1, "op": 3, "tool": "shell.argv", "args": {"argv": "PLANTED-ARGUMENT"}, "effect": "exec", "decision": "confirm", "confirmed": "none", "outcome": "pending"}
{"time": "2026-10-10T00:00:01.000Z", "kind": "release", "gen": 1, "op": 4, "tool": "release", "args": {}, "effect": null, "decision": "send", "confirmed": "none", "outcome": "completed"}
{"time": "2026-10-10T00:00:02.000Z", "kind": "action", "gen": 1, "op": 3, "tool": "shell.argv", "args": {"argv": "PLANTED-ARGUMENT"}, "effect": "exec", "decision": "confirm", "confirmed": "physical", "outcome": "completed"}
JSONL
# The daemon's own trace of brain text: one turn in two text events, then a
# second turn.
cat >"$tmp/brain.jsonl" <<'JSONL'
{"gen": 1, "op": 5, "text": "It is **noon**. "}
{"gen": 1, "op": 5, "text": "`date` says so."}
{"gen": 1, "op": 8, "text": "Anything else?"}
JSONL
# planted_trace USER_FINAL [FORM]: a turn whose answer is two sentences in
# one caption segment, which closes, and a second segment that repeats the
# first sentence and stays open. In the `sentences` form, ChainedEngine.js's,
# a write adds a sentence; in the `fragments` form, Realtime.js's, a write
# adds a fragment of the voice's transcript.
planted_trace() {
  python3 - "$tmp/trace.json" "$1" "${2:-sentences}" <<'PY'
import json, sys
def caption(at, role, text, stage): return {"kind": "caption", "at": at, "value": {"gen": 1, "role": role, "text": text, "stage": stage, "rev": at}}
events = [{"kind": "widget", "at": 900, "value": "ready"}, {"kind": "phase", "at": 900, "value": "idle"},
          caption(950, "user", "an earlier turn", "final"), caption(960, "assistant", "An earlier answer.", "final"),
          {"kind": "mark", "at": 1000, "value": "input"}, {"kind": "widget", "at": 1040, "value": "listening"},
          caption(1100, "user", "what time", "partial")]
if sys.argv[2] == "final":
    events.append(caption(1200, "user", "What time is it?", "final"))
events += [{"kind": "widget", "at": 1250, "value": "working"}, {"kind": "phase", "at": 1250, "value": "thinking"},
           {"kind": "phase", "at": 1900, "value": "speaking"}]
if sys.argv[3] == "sentences":
    events += [caption(2000, "assistant", "It is noon.", "partial"), caption(2500, "assistant", "It is noon. Anything else?", "partial")]
else:
    events += [caption(2000 + 100 * i, "assistant", text, "partial")
               for i, text in enumerate(["It", "It is", "It is noon.", "It is noon. Any", "It is noon. Anything", "It is noon. Anything else?"])]
events += [caption(2600, "assistant", "It is noon. Anything else?", "final"),
           caption(3000, "assistant", "It is noon.", "partial"), {"kind": "widget", "at": 3100, "value": "ready"},
           {"kind": "phase", "at": 3100, "value": "idle"}]
json.dump(events, open(sys.argv[1], "w"))
PY
}
dictation_json='{"daemon":[{"ms":10,"daemon":"ready","child":"running"}],"recordings":[{"ms":20,"phase":"recording"},{"ms":30,"phase":"released"}],"unread":1}'
record() { # END KEPT [VOICE] [MAILBOX] → the verdict word; the record in record.json
  call selftest_record "$tmp/trace.json" "$tmp/audit" "$tmp/record.json" idle "" wav /voice.wav cli:b "/a home" "${3:-local}" toggle key "${4:-}" "$1" "$2" "$tmp/brain.jsonl" '{"speechEndMs":1200,"firstMs":350,"longestGapMs":120,"sounds":[[1050,1130],[1550,1900]]}' "$dictation_json"
}
# sentences_are VOICE FORM WANT_JSON: the record's sentences for a trace of
# FORM read as VOICE's.
sentences_are() {
  planted_trace final "$2"
  record completed true "$1" >/dev/null || return 1
  python3 -c 'import json,sys; sys.exit(json.load(open(sys.argv[1]))["sentences"] != json.loads(sys.argv[2]))' "$tmp/record.json" "$3"
}
realtime_sentences() { sentences_are realtime fragments '[{"ms": 1000, "text": "It is noon. Anything else?"}, {"ms": 2000, "text": "It is noon."}]'; }
gemini_sentences() { sentences_are gemini fragments '[{"ms": 1000, "text": "It is noon. Anything else?"}, {"ms": 2000, "text": "It is noon."}]'; }
local_sentences() { sentences_are local sentences '[{"ms": 1000, "text": "It is noon."}, {"ms": 1500, "text": "Anything else?"}, {"ms": 2000, "text": "It is noon."}]'; }
# ElevenLabs speaks the engine's released sentences, as the local voice does.
elevenlabs_sentences() { sentences_are elevenlabs sentences '[{"ms": 1000, "text": "It is noon."}, {"ms": 1500, "text": "Anything else?"}, {"ms": 2000, "text": "It is noon."}]'; }
record_holds() {
  planted_trace final
  [[ "$(record completed true)" == passed ]] || return 1
  python3 - "$tmp/record.json" <<'PY'
import json, sys
want = {"input": {"kind": "wav", "value": "/voice.wav"}, "brain": "cli:b", "home": "/a home", "voice": "local", "mode": "toggle", "confirm": "key",
        "heard": "What time is it?",
        "sentences": [{"ms": 1000, "text": "It is noon."}, {"ms": 1500, "text": "Anything else?"}, {"ms": 2000, "text": "It is noon."}],
        "raw": ["It is **noon**. `date` says so.", "Anything else?"],
        "tools": [{"tool": "shell.argv", "decision": "confirm", "confirmed": "none", "outcome": "pending"},
                  {"tool": "shell.argv", "decision": "confirm", "confirmed": "physical", "outcome": "completed"}],
        "dictation": {"daemon": [{"ms": 10, "daemon": "ready", "child": "running"}], "recordings": [{"ms": 20, "phase": "recording"}, {"ms": 30, "phase": "released"}], "unread": 1},
        "sidecar": {"reference": None},
        "mailbox": [],
        "widget": [{"ms": -100, "state": "ready"}, {"ms": 40, "state": "listening"}, {"ms": 250, "state": "working"}, {"ms": 2100, "state": "ready"}],
        "phases": [{"ms": -100, "phase": "idle"}, {"ms": 250, "phase": "thinking"}, {"ms": 900, "phase": "speaking"}, {"ms": 2100, "phase": "idle"}],
        "audio": {"speechEndMs": 200, "firstMs": 350, "longestGapMs": 120, "sounds": [[50, 130], [550, 900]]},
        "end": {"kind": "completed", "phase": "idle", "fault": None}, "passed": True}
got = json.load(open(sys.argv[1]))
if got != want:
    print("        got:  " + json.dumps(got, sort_keys=True) + "\n        want: " + json.dumps(want, sort_keys=True))
    sys.exit(1)
PY
}
names_only() { planted_trace final; record completed true >/dev/null && ! grep -q -F PLANTED-ARGUMENT -- "$tmp/record.json"; }
# mailbox_is WANT_JSON HOME: the record's mailbox for a run of the home HOME
# whose last mailbox read printed two rows.
mailbox_is() {
  planted_trace final
  call selftest_record "$tmp/trace.json" "$tmp/audit" "$tmp/record.json" idle "" wav /voice.wav cli:b "$2" local toggle key \
    "$mail_row"$'\n''{"id":"1791633001-1-2","text":"a second row"}' completed true "$tmp/brain.jsonl" '{"speechEndMs":null,"firstMs":null,"longestGapMs":null,"sounds":[]}' '{"daemon":[],"recordings":[],"unread":0}' >/dev/null || return 1
  python3 -c 'import json,sys; sys.exit(json.load(open(sys.argv[1]))["mailbox"] != json.loads(sys.argv[2]))' "$tmp/record.json" "$1"
}
mailbox_rows() { mailbox_is "[$mail_row, {\"id\": \"1791633001-1-2\", \"text\": \"a second row\"}]" "/a home"; }
mailbox_none() { mailbox_is null ""; }
# One table for the mark: END, KEPT and the user's final caption.
failed_rows=("timeout true final" "fault true final" "gate-down true final" "completed false final" "completed true none")
not_passed() { # "END KEPT USER_FINAL"
  local end kept final
  read -r end kept final <<<"$1"
  planted_trace "$final"
  [[ "$(record "$end" "$kept")" == failed && "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["passed"])' "$tmp/record.json")" == False ]]
}
holds "the record holds the heard text, each released sentence, each turn's brain text, each tool call's names, the widget states, the Session phases and the end" record_holds
holds "the record holds no argument of a tool call" names_only
holds "the record holds each row the mailbox read printed, whole" mailbox_rows
holds "a run with no home folder records no mailbox" mailbox_none
holds "the realtime voice's record holds each caption segment whole, timed at its first words" realtime_sentences
holds "the gemini voice's record holds each caption segment whole, timed at its first words" gemini_sentences
holds "the ElevenLabs voice's record holds each released sentence, as the local voice's" elevenlabs_sentences
dictation_samples() {
  local state="$tmp/lent.json" daemon="$tmp/dictation-daemon.jsonl" recordings="$tmp/dictation-recordings.jsonl" unread="$tmp/dictation-unread"
  rm -f -- "$daemon" "$recordings" "$unread"
  bash -c 'set -euo pipefail; source "$1"; state="$2"; daemon="$3"; recordings="$4"; unread="$5"
    ipc() { [[ $1 == shell && $2 == lent ]] || return 1; cat -- "$state"; }
    printf "%s\n" "{\"dictation\":{\"daemon\":\"absent\",\"child\":\"none\",\"holders\":[],\"holder\":\"\",\"mode\":\"\"}}" >"$state"
    selftest_dictation_sample 0 "$daemon" "$recordings" "$unread"
    printf "%s\n" "{\"dictation\":{\"daemon\":\"ready\",\"child\":\"running\",\"holders\":[\"p\"],\"holder\":\"\",\"mode\":\"\"}}" >"$state"
    selftest_dictation_sample 40 "$daemon" "$recordings" "$unread"
    printf "%s\n" "{\"dictation\":{\"daemon\":\"ready\",\"child\":\"running\",\"holders\":[\"p\"],\"holder\":\"p\",\"mode\":\"text\"}}" >"$state"
    selftest_dictation_sample 80 "$daemon" "$recordings" "$unread"
    printf "%s\n" "{\"dictation\":{\"daemon\":\"ready\",\"child\":\"running\",\"holders\":[\"p\"],\"holder\":\"\",\"mode\":\"\"}}" >"$state"
    selftest_dictation_sample 120 "$daemon" "$recordings" "$unread"
    ipc() { return 1; }
    selftest_dictation_sample 160 "$daemon" "$recordings" "$unread"
    selftest_dictation_record "$daemon" "$recordings" "$unread"
  ' _ "$functions" "$state" "$daemon" "$recordings" "$unread" >"$tmp/out"
  [[ "$(<"$tmp/out")" == '{"daemon":[{"ms":0,"daemon":"absent","child":"none"},{"ms":40,"daemon":"ready","child":"running"}],"recordings":[{"ms":80,"phase":"recording"},{"ms":120,"phase":"released"}],"unread":1}' ]]
}
holds "the dictation record logs daemon changes and recording phases without inventing a failed lent read" dictation_samples
for row in "${failed_rows[@]}"; do holds "a record for [$row] is not marked passed" not_passed "$row"; done
control cut_functions "a record that keeps the audit record whole" 'tools.append({key: row[key] for key in ("tool", "decision", "confirmed", "outcome")})' 'tools.append(row)' names_only
control cut_functions "a record that drops dictation" '"dictation": dictation,' '' record_holds
control cut_functions "a dictation sampler that never writes released" 'elif not holder and last is not None and last.get("phase") == "recording":' 'elif False and not holder and last is not None and last.get("phase") == "recording":' dictation_samples
control cut_functions "a record that drops the brain's own text" '"raw": raw,' '"raw": [],' record_holds
control cut_functions "a record that drops the Session phases" 'for e in events if e["kind"] == "phase" and e["value"]],' 'for e in events if False],' record_holds
control cut_functions "a record that reads two turns' brain text as one" '    if (row["gen"], row["op"]) != turn:' '    if turn is None:' record_holds
control cut_functions "a record that drops the mailbox rows" '[json.loads(line) for line in mailbox.splitlines()] if home' '[] if home' mailbox_rows
control cut_functions "a record that lists a mailbox for a run with no home folder" ' if home else None,' ',' mailbox_none
control cut_functions "a record that reads the realtime voice's fragments as sentences" '    if voice not in ("local", "elevenlabs"):' '    if False:' realtime_sentences
control cut_functions "a record that reads the local voice's sentences as one segment" '    if voice not in ("local", "elevenlabs"):' '    if True:' local_sentences
control cut_functions "a record that reads only the realtime voice's fragments as segments" '    if voice not in ("local", "elevenlabs"):' '    if voice == "realtime":' gemini_sentences
control cut_functions "a record that reads the ElevenLabs voice's sentences as one segment" '    if voice not in ("local", "elevenlabs"):' '    if voice != "local":' elevenlabs_sentences
control cut_functions "a mark that passes a turn that did not complete" 'end == "completed" and ' '' not_passed "${failed_rows[0]}"
control cut_functions "a mark that passes a run that broke a rule" ' and kept == "true"' '' not_passed "${failed_rows[3]}"
control cut_functions "a mark that passes a turn with no heard text" 'heard is not None and ' '' not_passed "${failed_rows[4]}"

echo "--- the verdict"
# One table for the run's end: the turn reader's last word, what the run
# broke outside its turn, the exit status, and the record's end and mark.
# The run's last line names the same end.
finish_rows=(
  "a completed turn in a run that broke nothing|ended=idle|nothing|0|completed|True"
  "a turn that ended listening again|ended=listening|nothing|0|completed|True"
  "a turn a fault stopped|ended=error|nothing|1|fault|False"
  "a turn the gate stopped|ended=down|nothing|1|gate-down|False"
  "a turn that never woke|no-wake|nothing|1|no-wake|False"
  "a turn that never ended|waiting|nothing|1|timeout|False"
  "a home folder that changed during the run|ended=idle|home|1|completed|False"
  "a voxtype models folder that changed during the run|ended=idle|models|1|completed|False"
  "an authentication stand-in the run reached|ended=idle|auth|1|completed|False"
  "a sandbox check the harness counted as failed|ended=idle|checks|1|completed|False"
)
finish_copy="$tmp/finish copy"
finish_case() { # ROW
  local turn broke want_status end passed sum model_sum checks=0 status=0
  IFS='|' read -r _ turn broke want_status end passed <<<"$1"
  planted_trace final
  make_folder
  sum="$(call selftest_tree_sum "$folder")" || return 1
  model_sum="$(call selftest_tree_sum "$voxtype_models")" || return 1
  rm -rf -- "${finish_copy:?}"
  cp -a -- "$folder" "$finish_copy"
  : >"$tmp/auth.calls"
  rm -f -- "${tmp:?}/record.json"
  case "$broke" in
    home) echo memory >"$folder/state/turn.json" ;;
    models) echo changed >"$voxtype_models/parakeet-tdt-0.6b-v3/changed" ;;
    auth) echo "secret-tool store --label=planted service vgs-jarvis" >"$tmp/auth.calls" ;;
    checks) checks=1 ;;
  esac
  call selftest_finish "$turn" "$sum" "$tmp/auth.calls" "$checks" "$tmp/trace.json" "$tmp/audit" "$tmp/record.json" \
    idle "" wav /voice.wav cli:b "$folder" local toggle key "$repo" "$finish_copy" "$tmp/brain.jsonl" '{"speechEndMs":1200,"firstMs":350,"longestGapMs":120,"sounds":[[1550,1900]]}' "$dictation_json" "$model_sum" "$voxtype_models" >"$tmp/out" 2>"$tmp/err" || status=$?
  [[ $broke != models ]] || rm -f -- "$voxtype_models/parakeet-tdt-0.6b-v3/changed"
  [[ $status -eq $want_status && "$(tail -n 1 -- "$tmp/out")" == "selftest=$end record=$tmp/record.json" ]] || return 1
  [[ "$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(r["end"]["kind"], r["passed"], json.dumps(r["dictation"], separators=(",", ":")))' "$tmp/record.json")" == "$end $passed $dictation_json" ]]
}
for row in "${finish_rows[@]}"; do
  IFS='|' read -r label _ _ want_status end passed <<<"$row"
  holds "$label ends the run with exit $want_status, end $end and passed $passed" finish_case "$row"
done
control cut_functions "a verdict that takes a fault as a completed turn" '    ended=error) echo fault ;;' '    ended=error) echo completed ;;' finish_case "${finish_rows[2]}"
control cut_functions "a verdict that takes a stopped gate as a completed turn" '    ended=down) echo gate-down ;;' '    ended=down) echo completed ;;' finish_case "${finish_rows[3]}"
control cut_functions "a verdict that takes no-wake as a completed turn" '    no-wake) echo no-wake ;;' '    no-wake) echo completed ;;' finish_case "${finish_rows[4]}"
control cut_functions "a verdict that takes a turn that never ended as completed" '    *) echo timeout ;;' '    *) echo completed ;;' finish_case "${finish_rows[5]}"
control cut_functions "a verdict that reads no home checksum" '[[ $sum == "$home_sum" ]] || {' 'true || {' finish_case "${finish_rows[6]}"
control cut_functions "a verdict that reads no voxtype models checksum" '[[ $sum == "$voxtype_models_sum" ]] || {' 'true || {' finish_case "${finish_rows[7]}"
control cut_functions "a verdict that passes a run that reached an authentication stand-in" 'if [[ -s $auth_log ]]; then kept=false;' 'if [[ -s $auth_log ]]; then' finish_case "${finish_rows[8]}"
control cut_functions "a verdict that passes a run with a failed sandbox check" '[[ $failures -eq 0 ]] || { kept=false;' '[[ $failures -eq 0 ]] || {' finish_case "${finish_rows[9]}"
control cut_functions "a run whose exit status is not its record's mark" '  [[ $verdict == passed ]] || exit 1' '  :' finish_case "${finish_rows[6]}"
control cut_functions "a record written before the run's rules are read" '"$end" "$kept" "$brain_text" "$audio_json" "$dictation_json" "$sidecar_json")' '"$end" true "$brain_text" "$audio_json" "$dictation_json" "$sidecar_json")'$'\n''  [[ $kept == true ]] || verdict=failed' finish_case "${finish_rows[8]}"
control cut_functions "a finish record that drops dictation" '"$end" "$kept" "$brain_text" "$audio_json" "$dictation_json" "$sidecar_json")' '"$end" "$kept" "$brain_text" "$audio_json" "" "$sidecar_json")' finish_case "${finish_rows[0]}"
runner_final_wires_dictation() { grep -q -F -- '"$audio_json" "$dictation_json" "$voxtype_models_sum" "$voxtype_models"' "$tree/scripts/jarvis-selftest.sh"; }
holds "the runner final call passes the dictation record into the verdict" runner_final_wires_dictation
control plant "a runner final call that passes an empty dictation record" '"$audio_json" "$dictation_json" "$voxtype_models_sum" "$voxtype_models"' '"$audio_json" "" "$voxtype_models_sum" "$voxtype_models"' runner_final_wires_dictation

echo "--- the mailbox"
# The record the run writes in the home copy: with it lane-mail's send
# lands, an overseer record already there is kept, and a home without
# kendex gets none. A fleet state that lies outside the copy is refused
# before anything is written.
overseer_dir="$tmp/overseer home"
overseer_lands() {
  rm -rf -- "${overseer_dir:?}"
  kendex_home "$overseer_dir" || return 1
  call selftest_overseer "$overseer_dir" || return 1
  printf 'a request\n' >"$tmp/request.txt"
  lane_send "$overseer_dir" "$tmp/request.txt"
}
overseer_kept() {
  rm -rf -- "${overseer_dir:?}"
  kendex_home "$overseer_dir" || return 1
  call selftest_overseer "$overseer_dir" || return 1
  (cd -- "$overseer_dir" && env -i PATH="$path" "$BASH" .agents/skills/orch/scripts/workflow-state update oversee \
    '.overseer = {"server": "kept"}' >/dev/null) || return 1
  call selftest_overseer "$overseer_dir" || return 1
  [[ "$(workflow_get "$overseer_dir" .overseer.server)" == kept ]]
}
overseer_none() {
  rm -rf -- "${overseer_dir:?}"
  mkdir -p "$overseer_dir"
  call selftest_overseer "$overseer_dir" && [[ -z "$(ls -A -- "$overseer_dir")" ]]
}
overseer_outside() {
  local tool="$overseer_dir/.agents/skills/orch/scripts/workflow-state"
  rm -rf -- "${overseer_dir:?}" "${tmp:?}/overseer-writes"
  mkdir -p "$(dirname -- "$tool")"
  printf '#!/usr/bin/env bash\n[[ $1 == path ]] && { echo %q; exit 0; }\necho "$@" >>%q\n' "$tmp/elsewhere/state.json" "$tmp/overseer-writes" >"$tool"
  chmod +x "$tool"
  ! call selftest_overseer "$overseer_dir" 2>/dev/null && [[ ! -e $tmp/overseer-writes ]]
}
holds "the overseer record the run writes in a kendex home lets lane-mail's send land" overseer_lands
holds "an overseer record already in the home copy is kept" overseer_kept
holds "a home without kendex gets no fleet state" overseer_none
holds "a fleet state outside the home copy is refused before any write" overseer_outside
control cut_functions "a run that records no overseer" \
  "  (cd -- \"\$1\" && env -i PATH=\"\$PATH\" \"\$BASH\" \"\$tool\" update oversee '.overseer //= {}' >/dev/null)" '  :' overseer_lands
control cut_functions "a run that replaces the overseer record" "'.overseer //= {}'" "'.overseer = {}'" overseer_kept
control cut_functions "a run that writes a fleet state outside the home copy" \
  '  [[ $file == "$1"/* || $file == "$real"/* ]] ||' '  true ||' overseer_outside
# The runner writes the record in its copy of the home, never in the folder.
overseer_copy() {
  make_folder
  kendex_home "$folder" || return 1
  starts --home "$folder" || return 1
  [[ "$(workflow_get "$sandbox/home/jarvis-home" '.overseer | type')" == object && ! -e $folder/tmp ]]
}
holds "the run records an overseer in the home copy alone" overseer_copy
control plant "a runner that records no overseer in the home copy" '  selftest_overseer "$home_copy" || stopped overseer-unrecorded' '  :' overseer_copy
# hands HOME TEXT_JSON: the text TEXT_JSON spells as a JSON string, which
# can hold half of a surrogate pair as a model's call can, handed to the
# Jarvis session's mailbox in HOME by the plugin's guidance executor with
# HOME's kendex mail tool, as Jarvis hands a request; prints its answer.
hands() { # HOME TEXT_JSON
  env -i PATH="$path" HOME="$world" "$node_bin" - "$repo" "$@" <<'JS'
    const path = require("node:path");
    const [tree, home, text] = process.argv.slice(2);
    const backend = path.join(tree, "shell/plugins/vgs.jarvis/backend");
    require(path.join(backend, "Core.js")).use(tree);
    require(path.join(backend, "ComputerHelp.js")).create(undefined, null, () => home, process.env)
        .start({ id: "fleet.request", args: { text: JSON.parse(text) } }, answer => {
            if (answer.outcome !== "completed") { process.stderr.write(JSON.stringify(answer) + "\n"); process.exitCode = 1; }
            else console.log(answer.content);
        });
JS
}
# finish_mail: a request Jarvis's executor hands over between the run's two
# mailbox reads is in the record whole, the row its answer names, the half
# of a surrogate pair in it as U+FFFD.
finish_mail() {
  local sum answer
  planted_trace final
  make_folder
  sum="$(call selftest_tree_sum "$folder")" || return 1
  rm -rf -- "${finish_copy:?}"
  cp -a -- "$folder" "$finish_copy"
  kendex_home "$finish_copy" || return 1
  call selftest_overseer "$finish_copy" || return 1
  : >"$tmp/auth.calls"
  call selftest_mailbox "$repo" "$finish_copy" >/dev/null || return 1
  answer="$(hands "$finish_copy" '"Rebase the lanes.\nThen report \ud83d."')" || return 1
  call selftest_finish ended=idle "$sum" "$tmp/auth.calls" 0 "$tmp/trace.json" "$tmp/audit" "$tmp/record.json" \
    idle "" type hello cli:b "$folder" local toggle key "$repo" "$finish_copy" "$tmp/brain.jsonl" '{"speechEndMs":1000,"firstMs":300,"longestGapMs":100,"sounds":[[1300,1700]]}' >"$tmp/out" 2>"$tmp/err" || return 1
  python3 - "$tmp/record.json" "$answer" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))["mailbox"]
sys.exit(not (len(rows) == 1 and rows[0]["text"] == "Rebase the lanes.\nThen report �." and rows[0]["id"] in sys.argv[2]))
PY
}
holds "a request Jarvis's executor hands over during the turn is in the record, as the Jarvis session's reader prints it" finish_mail
control cut_functions "a verdict that reads no mailbox" '    mailbox="$(selftest_mailbox "$tree" "$home_copy")" || stopped mailbox-unread' '    :' finish_mail
control cut_functions "a reader of another lane's mailbox" 'inbox --item overseer' 'inbox --item other' finish_mail

# The cloned voice (VGS-1385). A case asks for it with "clonedVoice": true,
# which reaches the child run as --cloned-voice; the run turns the setting
# on, copies the prepared clone marker and recording as this user's 0600
# files, and records whether the sidecar was handed the recording.
echo "--- the cloned voice"
clone_prepared() { # HOME
  printf '{}\n' >"$1/.local/state/vgshell/jarvis/clone-ready.json"
  printf 'RIFF synthetic reference\n' >"$1/.local/state/vgshell/jarvis/voice-reference.wav"
  chmod 644 "$1/.local/state/vgshell/jarvis/voice-reference.wav"
  mkdir -p "$1/.local/share/vgshell/jarvis/local/clone/venv/bin"
  printf '#!/bin/sh\nexit 0\n' >"$1/.local/share/vgshell/jarvis/local/clone/venv/bin/python"
  chmod +x "$1/.local/share/vgshell/jarvis/local/clone/venv/bin/python"
}
clone_prepared "$tmp/voice"
cloned_case() {
  printf '{"input":{"tts":"hello"},"mode":"toggle","confirm":"none","clonedVoice":true,"heard":["hello"],"tool":"none","said":["ok"]}\n' >"$tmp/cloned-case.json"
  call selftest_case_check "$tmp/cloned-case.json" || return 1
  printf '{"input":{"tts":"hello"},"mode":"toggle","confirm":"none","clonedVoice":false,"heard":["hello"],"tool":"none","said":["ok"]}\n' >"$tmp/bad-case.json"
  ! call selftest_case_check "$tmp/bad-case.json" >/dev/null 2>&1 || return 1
  [[ "$(call selftest_case_child_args "$tmp/cloned-case.json" "")" == $'source=case\n--tts\nhello\n--mode\ntoggle\n--confirm\nnone\n--cloned-voice' ]] || return 1
  python3 -c 'import json,sys; sys.exit(json.load(open(sys.argv[1])).get("clonedVoice") is not True)' "$repo/scripts/jarvis-selftest-cases/cloned-voice.json"
}
cloned_settings() {
  starts --cloned-voice && [[ "$(row_of)" == "[{\"brain\": \"$sign_in\", \"clonedVoice\": true, \"id\": \"vgs.jarvis\", \"microphone\": \"vgs-smoke-voice\", \"mode\": \"toggle\", \"speaker\": \"vgs-smoke-speakers\", \"voiceProvider\": \"local\"}, [\"vgs.jarvis\"]]" ]] || return 1
  local state="$sandbox/home/.local/state/vgshell/jarvis" name
  for name in clone-ready.json voice-reference.wav; do
    cmp -s -- "$tmp/voice/.local/state/vgshell/jarvis/$name" "$state/$name" || return 1
    [[ $(stat -c %a -- "$state/$name") == 600 ]] || return 1
  done
}
cloned_setting_off() { starts && [[ ! -e $sandbox/home/.local/state/vgshell/jarvis/voice-reference.wav ]] && ! grep -q clonedVoice -- "$sandbox/home/.config/vgshell/shell.json"; }
cloned_missing() {
  local held=0
  mv -- "$tmp/voice/.local/state/vgshell/jarvis/voice-reference.wav" "$tmp/held-reference.wav"
  ends 77 "selftest=input-missing name=voice-reference.wav" --type hello --brain "$sign_in" --cloned-voice || held=1
  mv -- "$tmp/held-reference.wav" "$tmp/voice/.local/state/vgshell/jarvis/voice-reference.wav"
  return "$held"
}
cloned_realtime() { refused "jarvis-selftest: refused: argument=--cloned-voice reason=needs-local-voice" --type hello --brain "$sign_in" --voice realtime --cloned-voice; }
# The sidecar's argv: a process this test starts and holds, named as the
# daemon's sidecar is, with and without the recording.
cloned_sidecar() { # WITH_REFERENCE WANT
  local state="$tmp/sidecar-state" pid got held=0
  mkdir -p "$state"
  local -a words=(-c 'import time; time.sleep(60)' /plugin/backend/local-speech.py --state "$state" --data /data --parent 1)
  [[ $1 == no ]] || words+=(--reference "$state/voice-reference.wav")
  python3 "${words[@]}" & pid=$!
  until [[ -r /proc/$pid/cmdline ]] && grep -q -a local-speech.py "/proc/$pid/cmdline"; do sleep 0.05; done
  got="$(call selftest_sidecar "$state")" || held=1
  kill "$pid"; wait "$pid" 2>/dev/null || true
  [[ $held -eq 0 && $got == "$2" ]]
}
cloned_record() {
  planted_trace final
  call selftest_record "$tmp/trace.json" "$tmp/audit" "$tmp/record.json" idle "" tts hello cli:b "" local toggle none "" completed true "$tmp/brain.jsonl" \
    '{"speechEndMs":1200,"firstMs":350,"longestGapMs":120,"sounds":[[1050,1130]]}' '{"daemon":[],"recordings":[],"unread":0}' '{"reference": true}' >/dev/null || return 1
  python3 -c 'import json,sys; sys.exit(json.load(open(sys.argv[1]))["sidecar"] != {"reference": True})' "$tmp/record.json" || return 1
  printf '{"input":{"tts":"hello"},"mode":"toggle","confirm":"none","clonedVoice":true,"heard":["time"],"tool":"shell.argv","said":["noon"]}\n' >"$tmp/cloned-case.json"
  python3 - "$tmp/record.json" <<'PY'
import json, sys
record = json.load(open(sys.argv[1]))
record["sidecar"] = {"reference": False}
json.dump(record, open(sys.argv[1] + ".tier", "w"))
PY
  [[ "$(call selftest_compare "$tmp/cloned-case.json" "$tmp/record.json" case)" == match ]] || return 1
  [[ "$(call selftest_compare "$tmp/cloned-case.json" "$tmp/record.json.tier" case | cut -d' ' -f1-2)" == "differs fields=clonedVoice" ]]
}
holds "a cloned voice case is well formed, its key true alone, and its child run asks for the cloned voice" cloned_case
holds "the cloned voice run turns the setting on and copies the clone marker and recording as 0600 files" cloned_settings
holds "a run without it leaves the setting and the recording out" cloned_setting_off
holds "a prepared setup without its recording ends as input-missing, exit 77" cloned_missing
holds "the cloned voice with the realtime voice is refused" cloned_realtime
holds "the sidecar handed the recording reads reference true" cloned_sidecar yes '{"reference": true}'
holds "the sidecar without it reads reference false" cloned_sidecar no '{"reference": false}'
holds "the record holds the sidecar field and a case that wanted the clone differs without it" cloned_record
control cut_functions "a case check that takes any clonedVoice value" 'if data.get("clonedVoice", True) is not True:' 'if False:' cloned_case
control cut_functions "a child argument builder that drops the cloned voice" '    print("--cloned-voice")' '    pass' cloned_case
control plant "a runner that leaves the setting off" '    row["clonedVoice"] = True' '    pass' cloned_settings
control plant "a runner that copies the recording with its own mode" 'install -m 600 -- "$clone_state/clone-ready.json"' 'cp -- "$clone_state/clone-ready.json"' cloned_settings
control plant "a runner that goes on without the prepared recording" '    [[ -f $clone_state/$name ]] || unavailable input-missing "name=$name"' '    :' cloned_missing
control plant "a runner that takes the cloned voice with the realtime voice" '  [[ $cloned == false || $voice == local ]] || refuse "argument=--cloned-voice reason=needs-local-voice"' '  :' cloned_realtime
control cut_functions "a sidecar reader that ignores the recording" 'found = "--reference" in argv' 'found = False' cloned_sidecar yes '{"reference": true}'
control cut_functions "a comparison that skips the cloned voice" 'if case.get("clonedVoice") and (record.get("sidecar") or {}).get("reference") is not True:' 'if False:' cloned_record

if [[ $failures -gt 0 ]]; then
  printf 'test-jarvis-selftest: %d failure(s)\n' "$failures"
  exit 1
fi
if [[ ${#bus_missing[@]} -gt 0 ]]; then
  printf 'test-jarvis-selftest: status=not-measured missing=%s\n' "$(IFS=,; echo "${bus_missing[*]}")"
  exit 77
fi
echo "test-jarvis-selftest: ok"
