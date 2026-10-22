# Dictation, capability `dictation` (D106), over the voxtype stand-in on
# the shell's PATH (scripts/smoke/fixtures/voxtype/): the daemon the core
# starts, its status follower and every record verb are the stand-in, whose
# daemon hears the words the row writes and types through the wtype
# stand-in beside it. No row reaches the host's voxtype, its daemon, a
# microphone or the host's wtype.
#
# The fixtures acme.dictation and acme.dictation-other hold the capability
# and drive it over IPC. Rows, on the tree:
# - a holder other than the fixtures, which an earlier row left, ends the
#   row with one failure that names it;
# - with no holder, the sandbox holds no stand-in process;
# - a holder starts one daemon and one follower, children of the shell;
# - one `text` request hands the stand-in's words to the stop's callback
#   and leaves no file in the 0700 dictation directory;
# - a second holder's start during the first's recording is refused and
#   names the holder, and the second records once the first is done;
# - a `type` recording goes to the stand-in's own output, the wtype
#   stand-in;
# - disabling a holder cancels its recording and keeps the daemon for the
#   other;
# - with the stand-in's cap at 3 s, a `text` recording never stopped is
#   cancelled by the core: the daemon notes a cancel and no cap, and the
#   wtype stand-in recorded no call;
# - with a stand-in daemon that takes the start and cannot capture, the
#   core's start check releases the holder, so a second start is taken
#   and a restart is not refused;
# - disabling the last holder during a `text` recording cancels it before
#   the daemon ends, so no file override outlives the daemon, and the next
#   daemon's `type` recording is typed;
# - with a stand-in daemon the row started, the holder reads `elsewhere`,
#   its start is refused, no second daemon was tried, and a restart after
#   that daemon ended reads ready; the global count includes the foreign
#   daemon while the shell-owned counts stay zero;
# - a failed child retries only on user start; unreadable liveness or
#   continuing tool failure launches none, and repair reaches one ready
#   child without retaining a refused recording;
# - foreign liveness with absent or unreadable readiness still reads
#   elsewhere, preserves the readiness path, and recovers through the
#   existing restart endpoint after the foreign daemon ends;
# - with the shell killed during a `text` recording, its runner stopped so
#   that no shell comes back first, no stand-in process remains and the
#   wtype stand-in recorded no call.
# - the next daemon after that kill removes the killed daemon's state file
#   before its child starts, reads `starting` while the new model loads,
#   then replaces the killed text recording's file override on a `type`
#   start;
# Controls, each its own edit of one copy of the tree, started in place of
# the tree: a probe that reads no daemon tries a second one, which the
# stand-in refuses; a `text` start that arms no deadline reaches the cap,
# which types; a last release that ends no child
# leaves the daemon with no holder. A second copy, whose last release sends
# no cancel, leaves the file override. The row ends with a fresh shell of
# the tree, both fixtures disabled and the stand-ins put away.
# Every poll is expect_poll's, one read each 0.2 s; no latency budget is
# claimed.
# inputs: scripts/smoke/fixtures/plugins/acme.dictation/* scripts/smoke/fixtures/plugins/acme.dictation-other/* scripts/smoke/fixtures/voxtype/* shell/Core/Dictation.qml shell/Core/DictationModel.js shell/Core/Capabilities.qml shell/Core/PluginLogic.js shell/Core/ConfigLogic.js bin/vgshell-dictation bin/vgshell-pkg bin/lib/voxtype.sh bin/lib/voxtype.py bin/lib/tui.sh config/runtime-libraries.json config/voxtype/* scripts/smoke/rows/capabilities.sh
set -euo pipefail
dictation_other="$home/.config/vgshell/plugins/acme.dictation-other"
dictation_dir="$rt_dir/vgshell/dictation"
dictation_words="$sandbox/voxtype-words"
dictation_cap="$sandbox/voxtype-max-secs"
dictation_notes="$sandbox/voxtype-daemon.log"
dictation_typed="$sandbox/voxtype-wtype.log"
dictation_deaf="$sandbox/voxtype-no-capture"
dictation_loading="$sandbox/voxtype-loading"
dictation_follow="$sandbox/voxtype-follow.log"
dictation_daemon_fail="$sandbox/voxtype-daemon-fail"
dictation_liveness_unreadable="$sandbox/voxtype-variants-unreadable"
mkdir -p "$dictation_fixture" "$dictation_other"
cp -R "$repo/scripts/smoke/fixtures/plugins/acme.dictation/." "$dictation_fixture/"
cp -R "$repo/scripts/smoke/fixtures/plugins/acme.dictation-other/." "$dictation_other/"
printf '%s' 'the stand-in heard this' >"$dictation_words"
rm -f -- "${dictation_cap:?}" "${dictation_notes:?}" "${dictation_typed:?}" "${dictation_deaf:?}" "${dictation_loading:?}" "${dictation_follow:?}" "${dictation_daemon_fail:?}" "${dictation_liveness_unreadable:?}"

dictate() { ipc "$1" invoke "$2" "${3:-}"; } # ID VERB [ARG]
# A holder's reading of the capability's state: daemon, phase and the
# recording's holder, `-` for none.
dictation_state() { ipc smoke readInstance service "$1" state | py_reply 'import json,sys; d=json.load(sys.stdin); print(d["daemon"], d["phase"], d["holder"] or "-")'; }
dictation_last() { ipc smoke readInstance service "$1" last | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin), sort_keys=True))'; }
# The dictation directory's mode and how many files it holds.
dictation_files() {
  [[ -d $dictation_dir ]] || { echo absent; return 0; }
  printf '%s %s\n' "$(stat -c %a -- "$dictation_dir")" "$(find "$dictation_dir" -mindepth 1 | wc -l)"
}
# What the stand-in's daemons noted, in order, and what its wtype was
# handed; `none` for no line.
dictation_noted() { if [[ -s $dictation_notes ]]; then tr '\n' ' ' <"$dictation_notes" | sed 's/ $//'; echo; else echo none; fi; }
dictation_wtype() { if [[ -s $dictation_typed ]]; then cat -- "$dictation_typed"; else echo none; fi; }
dictation_forget() { rm -f -- "${dictation_notes:?}" "${dictation_typed:?}"; }
# Every state the stand-in's follower printed, in order; `none` for none.
dictation_followed() { if [[ -s $dictation_follow ]]; then tr '\n' ' ' <"$dictation_follow" | sed 's/ $//'; echo; else echo none; fi; }
# Whether the stand-in's file override, which outlives its daemon, is there.
dictation_override() { if [[ -e $rt_dir/voxtype/output_mode_override ]]; then echo kept; else echo absent; fi; }
dictation_none="daemon=0 follower=0 other=0"
dictation_one="daemon=1 follower=1 other=0"
# The shell dies with SIGKILL while its runner is stopped, so the runner
# starts no shell before the row has read what the dead one left; the
# runner is then killed and reaped, and its lock is free.
dictation_kill_shell() {
  shell_memory_note
  kill -STOP "$shell_pid" && kill -KILL "$shell_qs_pid" || fail "the shell pid $shell_qs_pid could not be killed"
}
dictation_reap_runner() {
  kill -KILL "$shell_pid" 2>/dev/null || true
  wait "$shell_pid" 2>/dev/null || true
  shell_pid=""
}
# A daemon the row itself starts and ends, as one the user's session runs.
dictation_own_pid=""
dictation_own_daemon() {
  "${shell_env[@]}" PATH="$shell_start_path" "$shim/voxtype" daemon >>"$sandbox/dictation-own-daemon.log" 2>&1 &
  dictation_own_pid=$!
}
dictation_own_state() { "${shell_env[@]}" PATH="$shell_start_path" "$shim/voxtype" status --format json | py_reply 'import json,sys; print(json.load(sys.stdin)["alt"])'; }
dictation_own_liveness() { "${shell_env[@]}" PATH="$shell_start_path" "$shim/voxtype" info variants --json | py_reply 'import json,sys; print(json.load(sys.stdin)["daemon_pid"])'; }
dictation_readiness_path() { if [[ -d $rt_dir/voxtype/state ]]; then echo directory; elif [[ -e $rt_dir/voxtype/state ]]; then echo file; else echo absent; fi; }
dictation_own_end() {
  [[ -z $dictation_own_pid ]] || { kill -TERM "$dictation_own_pid" 2>/dev/null || true; wait "$dictation_own_pid" 2>/dev/null || true; }
  dictation_own_pid=""
}
# TERM to each stand-in process a dead shell of this row left: a pid the
# sandbox's own stand-in path names, read from /proc.
dictation_end_left() {
  local pid
  for pid in $(dictation_processes pids); do kill -TERM "$pid" 2>/dev/null || true; done
}

# Holders of the dictation lending record, read as JSON on stdin, that are
# not this row's fixtures; `none` for none.
dictation_strangers() { py_reply 'import json,sys; print(",".join(h for h in (json.load(sys.stdin) or []) if h not in sys.argv[1:]) or "none")' acme.dictation acme.dictation-other; }
expect "control: a holder outside the fixtures is named" vgs.jarvis dictation_strangers <<<'["acme.dictation", "vgs.jarvis"]'

rescan "rescan after adding the dictation fixtures answers ok"
expect_poll "the dictation fixture is discovered" True plugin_known acme.dictation
expect_poll "the second dictation fixture is discovered" True plugin_known acme.dictation-other
if ! dictation_stand_ins on; then
  fail "the shell does not resolve voxtype to the stand-in: $(shell_resolves voxtype)"
  dictation_stand_ins off
  return 0
fi
# A holder an earlier row left would fail every lending check below, so
# the row names it once and ends.
dictation_others="$(lent holders.dictation | dictation_strangers)" || dictation_others="unread: $dictation_others"
if [[ $dictation_others == none ]]; then
  ok "no plugin outside the row's fixtures holds dictation"
else
  fail "no plugin outside the row's fixtures holds dictation: got $dictation_others"
  dictation_stand_ins off
  return 0
fi

expect "with no holder, no voxtype process runs" "$dictation_none" dictation_processes all
expect "with no holder, the lending record reads no daemon" "absent none -" dictation_lent
# The setup readings gate the actual core child, including for a holder
# other than Voice. Read both the child's absence and the shared reason.
dictation_setup_read() { ipc smoke readInstance service acme.dictation state | py_reply 'import json,sys; s=json.load(sys.stdin).get("setup"); print("unread" if s is None else json.dumps(s, sort_keys=True))'; }
for dictation_missing in engine model; do
  if [[ $dictation_missing == engine ]]; then
    touch -- "$sandbox/voxtype-engine-missing"
    dictation_expected_setup='{"compiled": false, "engine": "parakeet", "installed": true, "model": "parakeet-tdt-0.6b-v3", "version": "voxtype 1.1.0"}'
  else
    rm -f -- "${sandbox:?}/voxtype-model-installed"
    dictation_expected_setup='{"compiled": true, "engine": "parakeet", "installed": false, "model": "parakeet-tdt-0.6b-v3", "version": "voxtype 1.1.0"}'
  fi
  expect "a holder with a missing $dictation_missing enables" ok ipc shell setPluginEnabled acme.dictation true
  expect_poll "the holder reads its missing $dictation_missing" "$dictation_expected_setup" dictation_setup_read
  expect "a missing $dictation_missing starts no voxtype process" "$dictation_none" dictation_processes all
  expect "a missing $dictation_missing never reached the daemon" none dictation_noted
  expect "a start with a continuing missing $dictation_missing returns its setup refusal" 'refused: dictation=daemon-absent' dictate acme.dictation start text
  expect "a continuing missing $dictation_missing still starts no child" "$dictation_none" dictation_processes all
  expect "the holder with a missing $dictation_missing disables" ok ipc shell setPluginEnabled acme.dictation false
  rm -f -- "${sandbox:?}/voxtype-engine-missing"
  touch -- "$sandbox/voxtype-model-installed"
done
expect "enabling the dictation fixture is allowed" ok ipc shell setPluginEnabled acme.dictation true
expect_poll "the holder reads the daemon ready" "ready idle -" dictation_state acme.dictation
expect_poll "one daemon and one follower run, children of the shell" "$dictation_one" dictation_processes owned
expect "the dictation directory is the owner's alone and empty" "700 0" dictation_files

# The terminal runs the shipped setup only inside a private copy. Its
# system helper refuses, and its voxtype is the stand-in, so even a setup
# regression can reach neither authentication nor systemctl.
dictation_setup_tree="$sandbox/dictation-setup-tree"
mkdir -p "$dictation_setup_tree/bin/lib" "$dictation_setup_tree/config" "$dictation_setup_tree/commands"
cp -- "$repo/bin/vgshell-dictation" "$repo/bin/vgshell-pkg" "$dictation_setup_tree/bin/"
cp -- "$repo/bin/lib/tui.sh" "$repo/bin/lib/voxtype.sh" "$repo/bin/lib/voxtype.py" "$dictation_setup_tree/bin/lib/"
cp -- "$repo/config/runtime-libraries.json" "$dictation_setup_tree/config/"
cp -R -- "$repo/config/voxtype" "$dictation_setup_tree/config/"
printf '#!/bin/sh\nprintf "%%s\\n" forbidden >>%q\nexit 64\n' "$sandbox/dictation-setup-forbidden" >"$dictation_setup_tree/bin/vgshell-system"
for name in sudo systemctl; do
  cp -- "$dictation_setup_tree/bin/vgshell-system" "$dictation_setup_tree/commands/$name"
done
cat >"$dictation_setup_tree/commands/gum" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
verb="${1:-}"
(($# == 0)) || shift
case "$verb" in
  style)
    while [[ $# -gt 0 && $1 != -- ]]; do
      case "$1" in --border|--padding|--width) [[ $# -ge 2 ]] || exit 64; shift 2 ;; *) exit 64 ;; esac
    done
    [[ $# -gt 0 && $1 == -- ]] || exit 64
    shift
    printf '%s\n' "$@"
    ;;
  confirm) [[ $# -eq 2 && $1 == -- ]] || exit 64 ;;
  *) printf 'dictation gum: refused verb=%s\n' "$verb" >&2; exit 64 ;;
esac
SCRIPT
chmod +x "$dictation_setup_tree/bin/vgshell-system" "$dictation_setup_tree/commands/"*
terminal_stand_in
terminal_ready "dictation setup"
cp -- "$tui_terminal" "$sandbox/dictation-terminal-default"
{
  printf '#!/usr/bin/env bash\n'
  printf 'fallback=%q record=%q setup_tree=%q stand_in=%q\n' "$sandbox/dictation-terminal-default" "$tui_record" "$dictation_setup_tree" "$shim/voxtype"
  cat <<'SCRIPT'
args=("$@")
for ((i=0; i < $#; i++)); do
  [[ ${args[i]##*/} != vgshell-tui ]] || break
done
if ((i >= $#)); then exec "$fallback" "$@"; fi
present=("${args[@]:i}")
for ((j=0; j < ${#present[@]}; j++)); do
  [[ ${present[j]} != -- ]] || break
done
key=""
for ((k=2; k < j; k+=2)); do
  [[ ${present[k]} != --record ]] || key="${present[k+1]}"
done
printf 'dictation adapter: key=%q presenter=%q\n' "$key" "${present[0]}" >>"$setup_tree/adapter.log"
if [[ $key != core/dictation-setup ]]; then
  printf 'dictation adapter: route=fallback\n' >>"$setup_tree/adapter.log"
  exec "$fallback" "$@"
fi
command=("${present[@]:j+1}")
expected_vgs="${present[0]%/bin/vgshell-tui}/shell/../bin/vgshell"
if [[ ${#command[@]} != 3 || ${command[0]} != "$expected_vgs" || ${command[1]} != dictation || ${command[2]} != setup ]]; then
  printf 'dictation adapter: refused argv=' >&2
  printf ' %q' "${command[@]}" >&2
  printf '\n' >&2
  printf 'dictation adapter: refused argv=' >"$setup_tree/setup.out"
  printf ' %q' "${command[@]}" >>"$setup_tree/setup.out"
  printf '\n' >>"$setup_tree/setup.out"
  exit 64
fi
: >"$record.next"
for a; do printf '%s\n' "$a" >>"$record.next"; done
mv -f -- "$record.next" "$record"
printf '#!/usr/bin/env bash\nexec %q "$@"\n' "$stand_in" >"$setup_tree/commands/voxtype"
chmod +x "$setup_tree/commands/voxtype"
printf 'dictation adapter: route=private command=' >>"$setup_tree/adapter.log"
printf ' %q' "${command[@]}" >>"$setup_tree/adapter.log"
printf '\n' >>"$setup_tree/adapter.log"
exec env VGS_TUI_UNATTENDED=1 PATH="$setup_tree/commands:$PATH" "${present[@]:0:j+1}" "$setup_tree/bin/vgshell-dictation" setup >"$setup_tree/setup.out" 2>&1
SCRIPT
} >"$tui_terminal.next"
chmod +x "$tui_terminal.next"
mv -T -- "$tui_terminal.next" "$tui_terminal"
dictation_setup_action() { ipc smoke invokeInstance service acme.dictation statusAct setup; }
dictation_setup_defaults() {
  python3 - "$home/.config/voxtype" <<'PY'
import pathlib,sys,tomllib
p=pathlib.Path(sys.argv[1]); f=p/'config.toml'
if not f.exists(): print('absent'); raise SystemExit
config=tomllib.loads(f.read_text())
print('copied' if config['engine']=='parakeet' and config['audio']['feedback']['theme']==str(p/'sounds/bloop') and all((p/'sounds/bloop'/n).is_file() for n in ['start.wav','stop.wav','error.wav','LICENSE']) else 'wrong')
PY
}
dictation_setup_start() {
  local expected_tree="${1:-$repo}" evidence_name ended_file
  local tui_self="$expected_tree/bin/vgshell-tui" core_vgshell="$expected_tree/shell/../bin/vgshell"
  forget_record
  expect "Set up opens the core dictation setup" ok dictation_setup_action
  expect_poll "Set up hands the terminal core/dictation-setup" "$(core_words core/dictation-setup "Set up dictation" org.vgs.tui dictation setup)" recorded
  expect_run_end "the core dictation setup ends" core/dictation-setup
  run_end_records core/dictation-setup
  for ended_file in "$rt_dir/vgshell/tui/core@dictation-setup@"*.ended.json; do
    [[ ! -f $ended_file ]] || cat -- "$ended_file"
  done
  for evidence_name in adapter.log setup.out; do
    if [[ -f $dictation_setup_tree/$evidence_name ]]; then
      printf 'dictation setup evidence: %s\n' "$evidence_name"
      cat -- "$dictation_setup_tree/$evidence_name"
    else
      printf 'dictation setup evidence: %s absent\n' "$evidence_name"
    fi
  done
}
rm -f -- "${sandbox:?}/voxtype-model-installed"
dictation_forget
dictation_setup_start
expect "dictation setup copied the core defaults into sandbox HOME" copied dictation_setup_defaults
expect "dictation setup downloaded the configured model" 'setup --download --model parakeet-tdt-0.6b-v3 --no-post-install' cat "$sandbox/voxtype-setup.log"
dictation_setup_safe() { if [[ -e $sandbox/dictation-setup-forbidden ]]; then echo forbidden; else echo clean; fi; }
expect "dictation setup reached no system helper, sudo or systemctl" clean dictation_setup_safe
expect_poll "a successful setup end restarts the core daemon" "stopped started" dictation_noted
expect_poll "the restarted dictation daemon reads ready" "ready idle -" dictation_state acme.dictation
# An invalid fixture with the same action but no capability is refused by
# the manifest judge. The manager therefore has no plugin to act on.
mkdir -p "$home/.config/vgshell/plugins/acme.dictation-no-cap"
python3 - "$dictation_fixture/manifest.json" "$home/.config/vgshell/plugins/acme.dictation-no-cap/manifest.json" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); p['id']='acme.dictation-no-cap'; p['capabilities'].remove('dictation'); json.dump(p,open(sys.argv[2],'w'))
PY
expected_errors+=('acme.dictation-no-cap.*dictation needs capability dictation')
rescan "the fixture without dictation is scanned"
settings_page_open acme.dictation
forget_record
expect "the manager refuses setup on a fixture without dictation" 'unknown: acme.dictation-no-cap' settings_act acme.dictation-no-cap setup
expect "the refused setup starts no terminal" absent recorded
rm -rf -- "${home:?}/.config/vgshell/plugins/acme.dictation-no-cap"
rescan "the refused fixture is removed"
settings_page_close "dictation setup"
cp -- "$tui_terminal" "$sandbox/dictation-terminal-setup"
terminal_stand_in

# Keep the same holder while the child fails, the public ownership read
# fails, and the tool is repaired. The file is a stand-in engine failure,
# never a real tool change or a hardware access.
dictation_forget
: >"$dictation_daemon_fail"
expected_errors+=('dictation: daemon=failed reason=ended code=1 stderr="Error: voxtype fixture cannot load its engine"$' 'dictation: probe code=1 stderr="Error: voxtype fixture inventory unavailable"' 'dictation: daemon=failed reason=probe code=1')
expect "a restart beside a broken tool uses the existing owner" ok dictate acme.dictation restart
expect_poll "the broken tool leaves the same holder failed" "failed idle -" dictation_state acme.dictation
expect_poll "the broken child and its follower both end" "$dictation_none" dictation_processes all
expect "the failed child was tried once" "stopped failed" dictation_noted
: >"$dictation_liveness_unreadable"
expect "a user start rechecks unavailable public liveness" 'refused: dictation=daemon-starting' dictate acme.dictation start text
expect_poll "unreadable public liveness remains a typed failure" "failed idle -" dictation_state acme.dictation
expect "unreadable public liveness never launches a child" "stopped failed" dictation_noted
rm -f -- "${dictation_liveness_unreadable:?}"
expect "a user start retries while the tool is still broken" 'refused: dictation=daemon-starting' dictate acme.dictation start text
expect_poll "the continuing child failure stays typed" "failed idle -" dictation_state acme.dictation
expect_poll "the continuing failure leaves no process" "$dictation_none" dictation_processes all
expect "the continuing failure adds one child attempt" "stopped failed failed" dictation_noted
rm -f -- "${dictation_daemon_fail:?}"
: >"$dictation_loading"
expect "the next user start retries the repaired tool" 'refused: dictation=daemon-starting' dictate acme.dictation start text
expect_poll "the repaired tool starts one daemon and follower while loading" "$dictation_one" dictation_processes owned
expect "another text start while loading is pending" 'refused: dictation=daemon-starting' dictate acme.dictation start text
expect "another type start while loading is pending" 'refused: dictation=daemon-starting' dictate acme.dictation start type
expect "pending starts launch no duplicate child" "stopped failed failed started" dictation_noted
rm -f -- "${dictation_loading:?}"
expect_poll "the repaired tool reaches ready with no deferred recording" "ready idle -" dictation_state acme.dictation
expect "repair keeps one owned daemon and follower" "$dictation_one" dictation_processes owned

expect "a text recording starts" ok dictate acme.dictation start text
expect_poll "the state names the recording's holder" "ready recording acme.dictation" dictation_state acme.dictation
expect "the text recording stops" ok dictate acme.dictation stop
expect_poll "a text request returns the stand-in's words" '{"kind": "text", "text": "the stand-in heard this"}' dictation_last acme.dictation
expect_poll "the text request leaves no file under the dictation directory" "700 0" dictation_files
expect "the text request typed nothing" none dictation_wtype

expect "enabling the second dictation fixture is allowed" ok ipc shell setPluginEnabled acme.dictation-other true
expect_poll "the second holder reads the same daemon" "ready idle -" dictation_state acme.dictation-other
expect "a second holder starts no second daemon" "$dictation_one" dictation_processes owned
expect "the first holder records" ok dictate acme.dictation start text
expect "the busy refusal names the holder" "refused: dictation=busy holder=acme.dictation" dictate acme.dictation-other start text
expect "the other holder's stop is refused" "refused: dictation=not-holder holder=acme.dictation" dictate acme.dictation-other stop
expect "restart preserves the current recording holder" "refused: dictation=busy holder=acme.dictation" dictate acme.dictation-other restart
expect "a refused restart keeps the held recording" "ready recording acme.dictation" dictation_state acme.dictation
printf '%s' 'first turn' >"$dictation_words"
expect "the first holder stops" ok dictate acme.dictation stop
expect_poll "the first holder gets its words" '{"kind": "text", "text": "first turn"}' dictation_last acme.dictation
expect_poll "the second holder reads the recording over" "ready idle -" dictation_state acme.dictation-other
expect "the second holder takes its turn" ok dictate acme.dictation-other start text
expect_poll "the state names the second holder" "ready recording acme.dictation-other" dictation_state acme.dictation
printf '%s' 'second turn' >"$dictation_words"
expect "the second holder stops" ok dictate acme.dictation-other stop
expect_poll "the second holder gets its words" '{"kind": "text", "text": "second turn"}' dictation_last acme.dictation-other
expect "the first holder's result is still its own" '{"kind": "text", "text": "first turn"}' dictation_last acme.dictation
expect_poll "two turns leave no file under the dictation directory" "700 0" dictation_files

expect_poll "the daemon is idle before the type recording" "ready idle -" dictation_state acme.dictation
expect "a type recording starts" ok dictate acme.dictation start type
expect_poll "the type recording runs" "ready recording acme.dictation" dictation_state acme.dictation
expect "the type recording stops" ok dictate acme.dictation stop
expect_poll "a type recording goes to the stand-in's own output" "-d 10 -- second turn" dictation_wtype
expect_poll "the type stop hands over typed" '{"kind": "typed"}' dictation_last acme.dictation

expect_poll "the daemon is idle before the release" "ready idle -" dictation_state acme.dictation-other
dictation_forget
expect "the first holder records before it is disabled" ok dictate acme.dictation start text
expect_poll "the daemon notes the start" start dictation_noted
expect "disabling the recording's holder is allowed" ok ipc shell setPluginEnabled acme.dictation false
expect_poll "releasing a holder cancels its recording" "start cancel" dictation_noted
expect_poll "the other holder reads no recording" "ready idle -" dictation_state acme.dictation-other
expect "the daemon stays for the other holder" "$dictation_one" dictation_processes owned
expect_poll "the cancelled recording leaves no file" "700 0" dictation_files
expect "the cancelled recording typed nothing" none dictation_wtype
expect "disabling the last holder is allowed" ok ipc shell setPluginEnabled acme.dictation-other false
expect_poll "the last release ends the daemon and its follower" "$dictation_none" dictation_processes all

# The cap: the daemon reads it when it starts, so it starts under a 3 s
# cap, and the core's deadline is a second before it.
printf '%s\n' 3 >"$dictation_cap"
dictation_forget
expected_errors+=('dictation: recording=cancelled reason=cap holder=acme\.dictation')
expect "enabling the fixture under a 3 s cap is allowed" ok ipc shell setPluginEnabled acme.dictation true
expect_poll "the holder reads the daemon ready under the cap" "ready idle -" dictation_state acme.dictation
expect "a text recording starts and is never stopped" ok dictate acme.dictation start text
expect_poll "the core cancels the text recording before the stand-in's cap" "started start cancel" dictation_noted
expect_log "the core logs the cancel it made" 1 'dictation: recording=cancelled reason=cap holder=acme\.dictation'
expect_poll "the holder reads no recording after the cancel" "ready idle -" dictation_state acme.dictation
expect "the cancelled recording reached no wtype call" none dictation_wtype
expect_poll "the cancelled recording left no file" "700 0" dictation_files
expect "disabling the fixture after the cap rows is allowed" ok ipc shell setPluginEnabled acme.dictation false
expect_poll "the daemon ends after the cap rows" "$dictation_none" dictation_processes all
rm -f -- "${dictation_cap:?}"

# A daemon that takes the start and cannot capture prints no state: the
# core's start check reads it idle and releases the holder, so the next
# start is taken and a restart is not refused. Then the last release
# during a text recording, and a type recording on the daemon after it.
dictation_forget
: >"$dictation_deaf"
expect "enabling the fixture beside a capture that fails is allowed" ok ipc shell setPluginEnabled acme.dictation true
expect_poll "the holder reads the daemon ready before the failed capture" "ready idle -" dictation_state acme.dictation
expect "a text recording is asked of a daemon that cannot capture" ok dictate acme.dictation start text
expect_poll "the daemon took the start and records nothing" "started no-capture" dictation_noted
expect_poll "the start check releases the recording that never ran" "ready idle -" dictation_state acme.dictation
expect "the second start after the recording that never ran is taken" ok dictate acme.dictation start text
expect_poll "the daemon took the second start" "started no-capture no-capture" dictation_noted
expect_poll "the start check releases the second recording that never ran" "ready idle -" dictation_state acme.dictation
expect "a restart after the recordings that never ran is not refused" ok dictate acme.dictation restart
expect_poll "the restart ends the daemon and starts the next" "started no-capture no-capture stopped started" dictation_noted
expect_poll "the restarted daemon reads ready" "ready idle -" dictation_state acme.dictation
expect "the recordings that never ran left no file" "700 0" dictation_files
rm -f -- "${dictation_deaf:?}"
dictation_forget
expect "the start after the recordings that never ran is taken" ok dictate acme.dictation start text
expect_poll "the daemon records the next start" start dictation_noted
expect "disabling the last holder during a text recording is allowed" ok ipc shell setPluginEnabled acme.dictation false
expect_poll "the last release cancels the text recording before the daemon ends" "start cancel stopped" dictation_noted
expect_poll "the daemon is gone after that release" "$dictation_none" dictation_processes all
expect "no file override outlives the daemon" absent dictation_override
expect_poll "the released recording leaves no file" "700 0" dictation_files
dictation_forget
expect "enabling the fixture after that release is allowed" ok ipc shell setPluginEnabled acme.dictation true
expect_poll "the holder reads the next daemon ready" "ready idle -" dictation_state acme.dictation
expect "a type recording starts on the next daemon" ok dictate acme.dictation start type
expect_poll "the next daemon's type recording runs" "ready recording acme.dictation" dictation_state acme.dictation
expect "the next daemon's type recording stops" ok dictate acme.dictation stop
expect_poll "the next daemon's type recording is typed" "-d 10 -- second turn" dictation_wtype
expect "the type recording wrote no file" "700 0" dictation_files
expect_poll "the daemon is idle before the fixture is disabled" "ready idle -" dictation_state acme.dictation
expect "disabling the fixture after the type recording is allowed" ok ipc shell setPluginEnabled acme.dictation false
expect_poll "the daemon ends after the type recording" "$dictation_none" dictation_processes all

# A daemon the shell did not start.
dictation_forget
: >"$dictation_loading"
rm -f -- "${rt_dir:?}/voxtype/state"
dictation_own_daemon
expect_poll "public liveness finds the row's retained daemon" "$dictation_own_pid" dictation_own_liveness
expect "the live foreign daemon has no readiness file" absent dictation_readiness_path
expect "missing readiness reports stopped while the foreign daemon lives" stopped dictation_own_state
expect "enabling the fixture beside that daemon is allowed" ok ipc shell setPluginEnabled acme.dictation true
expect_poll "the holder reads the daemon elsewhere" "elsewhere idle -" dictation_state acme.dictation
expect "a start beside a daemon elsewhere is refused" "refused: dictation=daemon-elsewhere" dictate acme.dictation start text
expect "the shell started no second daemon" "started" dictation_noted
expect "the row's daemon is the only stand-in process" "daemon=1 follower=0 other=0" dictation_processes all
expect "the foreign daemon contributes no shell-owned role" "$dictation_none" dictation_processes owned
# A directory makes the readiness read unavailable and detects any
# attempted state cleanup. The foreign daemon remains held in model load.
mkdir -- "$rt_dir/voxtype/state"
expect "a restart beside unreadable foreign readiness is allowed" ok dictate acme.dictation restart
expect_poll "unreadable readiness keeps the foreign ownership result" "elsewhere idle -" dictation_state acme.dictation
expect "foreign readiness is preserved before any cleanup" directory dictation_readiness_path
expect "unreadable foreign readiness launches no child" "started" dictation_noted
rmdir -- "$rt_dir/voxtype/state"
dictation_own_end
# Successful Voice Stop calls this same capability endpoint. Voice's
# existing row owns its action and terminal route; this row owns recovery.
expect "a restart after that daemon ended is allowed" ok dictate acme.dictation restart
expect_poll "post-Stop recovery starts one owned child while loading" "$dictation_one" dictation_processes owned
expect "a pending post-Stop start retains no recording" 'refused: dictation=daemon-starting' dictate acme.dictation start type
rm -f -- "${dictation_loading:?}"
expect_poll "the restart reads the shell's own daemon ready" "ready idle -" dictation_state acme.dictation
expect_poll "the shell's own daemon and follower run" "$dictation_one" dictation_processes owned

# The shell killed during a text recording.
dictation_forget
expect "a text recording starts before the kill" ok dictate acme.dictation start text
expect_poll "the daemon notes the recording before the kill" start dictation_noted
dictation_kill_shell
expect_poll "with the shell killed, no voxtype process remains" "$dictation_none" dictation_processes all
expect "the killed shell's recording reached no wtype call" none dictation_wtype
# The shell's group TERM can reach the daemon before its parent-death KILL.
# voxtype 1.1.0 on TERM discards the capture, aborts any transcription,
# removes its state file and exits without output (daemon.rs:4553-4653 at
# e2638ca63), so either ending is one with no cap and no typed text. The
# KILL can also cut that cleanup short: the stand-in's trap removes the
# state before it notes `stopped`, so a KILL between the two leaves
# `start` with no state file, still an ending with no cap.
dictation_killed_notes() { case "$(dictation_noted)" in start | "start stopped") echo "no cap" ;; *) dictation_noted ;; esac; }
dictation_killed_state() {
  local state=absent
  [[ ! -e $rt_dir/voxtype/state ]] || state="$(<"$rt_dir/voxtype/state")"
  case "$(dictation_noted) $state" in
    "start recording" | "start absent" | "start stopped absent") echo matches ;;
    *) echo "notes=$(dictation_noted) state=$state" ;;
  esac
}
expect "the killed shell's daemon noted no cap" "no cap" dictation_killed_notes
dictation_reap_runner

expect "the killed daemon's state file matches its ending" matches dictation_killed_state
expect "the killed text recording left its file override" kept dictation_override
: >"$dictation_loading"
rm -f -- "${dictation_follow:?}"
start_shell "$repo" "$sandbox/dictation-after-kill.log"
expect_poll "the next daemon and its follower run while the model loads" "$dictation_one" dictation_processes owned
expect_poll "the next daemon's follower prints its first state" stopped dictation_followed
expect "a start while the next daemon loads is refused" "refused: dictation=daemon-starting" dictate acme.dictation start type
expect "the holder reads the next daemon starting while it loads" "starting idle -" dictation_state acme.dictation
expect "while the next daemon loads, its follower printed no word of the killed one" stopped dictation_followed
rm -f -- "${dictation_loading:?}"
expect_poll "the next daemon's own word reads it ready" "ready idle -" dictation_state acme.dictation
dictation_forget
expect "a type recording starts after the killed text recording" ok dictate acme.dictation start type
expect_poll "the type recording after the kill runs" "ready recording acme.dictation" dictation_state acme.dictation
expect "the type recording after the kill stops" ok dictate acme.dictation stop
expect_poll "the type recording after the kill is typed" "-d 10 -- second turn" dictation_wtype
expect_poll "the type stop after the kill hands over typed" '{"kind": "typed"}' dictation_last acme.dictation
expect "the type recording after the kill wrote no file" "700 0" dictation_files
expect_poll "the daemon is idle after the type recording after the kill" "ready idle -" dictation_state acme.dictation
stop_shell || :
expect_poll "the stand-ins from the after-kill shell are gone" "$dictation_none" dictation_processes all

# The controls, on one copy of the tree with one edit per rule.
copy_tree dictation-controls
dictation_edits=true
edit_tree dictation-controls shell/Core/DictationModel.js \
  '            s.elsewhere = ownership === "elsewhere";' \
  '            s.elsewhere = false;' || dictation_edits=false
edit_tree dictation-controls shell/Core/DictationModel.js \
  '        setTimer(t, effects, "cap", (t.maxSecs - CAP_MARGIN_S) * 1000);
' '' || dictation_edits=false
edit_tree dictation-controls shell/Core/DictationModel.js \
  '    if (t.holders.length === 0) {
        end(t, effects, "");' \
  '    if (t.holders.length === 0) {' || dictation_edits=false
edit_tree dictation-controls shell/Core/Capabilities.qml \
  '            if (end.code === 0) dictation.restart();' \
  '            if (false) dictation.restart();' || dictation_edits=false
if [[ $dictation_edits == true ]]; then
  expected_errors+=('dictation: daemon=failed reason=ended code=1 stderr="Error: Another voxtype instance is already running"$')
  printf '%s\n' 3 >"$dictation_cap"
  dictation_forget
  dictation_own_daemon
  expect_poll "control: the row's own stand-in daemon answers" idle dictation_own_state
  start_shell "$sandbox/tree-dictation-controls" "$sandbox/dictation-controls.log"
  expect_poll "control: a probe that reads no daemon tries a second one, which fails" "failed idle -" dictation_state acme.dictation
  expect "control: the stand-in refused that second daemon" "started refused" dictation_noted
  dictation_own_end
  dictation_forget
  expect "control: a restart with no daemon elsewhere is allowed" ok dictate acme.dictation restart
  expect_poll "control: the copy's daemon reads ready" "ready idle -" dictation_state acme.dictation
  cp -- "$sandbox/dictation-terminal-setup" "$tui_terminal"
  dictation_setup_start "$sandbox/tree-dictation-controls"
  expect "control: suppressing the setup callback leaves the daemon unchanged" started dictation_noted
  terminal_stand_in
  expect "control: a text recording starts with no deadline" ok dictate acme.dictation start text
  expect_poll "control: a text recording no deadline cancels reaches the stand-in's cap" "started start cap" dictation_noted
  expect_poll "control: the capped text recording is typed" "-d 10 -- second turn" dictation_wtype
  expect_poll "control: the copy reads the capped recording over" "ready idle -" dictation_state acme.dictation
  stop_shell || :
  start_shell "$sandbox/tree-dictation-controls" "$sandbox/dictation-controls-release.log"
  expect_poll "control: the copy's daemon reads ready again" "ready idle -" dictation_state acme.dictation
  expect "control: disabling the last holder on the copy is allowed" ok ipc shell setPluginEnabled acme.dictation false
  expect_poll "control: the copy released the hold" null lent holders.dictation
  # The Bash follower forks for $(state_now); that child keeps its argv.
  # Count the shell's direct children, not those transient fixture forks.
  expect "control: a last release that ends no child leaves the daemon and follower with no holder" "$dictation_one" dictation_processes owned
  stop_shell || :
  dictation_end_left
  expect_poll "control: the stopped copy's children are gone" "$dictation_none" dictation_processes all
fi
# The second copy: its last release ends the daemon with no cancel first.
copy_tree dictation-uncancelled
if edit_tree dictation-uncancelled shell/Core/DictationModel.js \
  '    if (s.child === "running" && r !== null && r.mode === "text") {' \
  '    if (false) {'; then
  rm -f -- "${dictation_cap:?}"
  dictation_forget
  start_shell "$sandbox/tree-dictation-uncancelled" "$sandbox/dictation-uncancelled.log"
  expect "control: enabling the fixture on the second copy is allowed" ok ipc shell setPluginEnabled acme.dictation true
  expect_poll "control: the second copy's daemon reads ready" "ready idle -" dictation_state acme.dictation
  expect "control: a text recording starts on the second copy" ok dictate acme.dictation start text
  expect_poll "control: the daemon notes that recording" "started start" dictation_noted
  expect "control: disabling the last holder on the second copy is allowed" ok ipc shell setPluginEnabled acme.dictation false
  expect_poll "control: the second copy's daemon ends" "$dictation_none" dictation_processes all
  expect "control: the second copy's daemon ended with no cancel" "started start stopped" dictation_noted
  expect "control: a last release that sends no cancel leaves the file override" kept dictation_override
  stop_shell || :
  find "$dictation_dir" -mindepth 1 -delete
  rm -f -- "${rt_dir:?}/voxtype/output_mode_override"
fi
rm -f -- "${dictation_cap:?}"
start_shell "$repo" "$sandbox/dictation-restored.log"
expect "the fixture is disabled on the tree's shell" ok ipc shell setPluginEnabled acme.dictation false
expect_poll "the tree's shell holds no dictation after the controls" null lent holders.dictation
expect_poll "the tree's shell runs no stand-in process" "$dictation_none" dictation_processes all
# The pre-fix nested run on cachy, 2026-10-21, measured shell main CPU
# 99.592% at 87.8 MB/s stderr, cpu some avg10 0.79 -> 0.67. Require less
# than one quarter of a core over the same 5 s window. The failed state
# and ended children independently reject the old unbounded transport.
dictation_cpu_window() { # TRIGGER, empty for idle
  python3 -c 'import json,os,pathlib,sys,time
shell,daemon,trigger=sys.argv[1:]
def ticks(pid,main=False):
    try:
        p=pathlib.Path("/proc")/pid
        s=(p/("task/"+pid+"/stat" if main else "stat")).read_text().rsplit(")",1)[1].split()
        return int(s[11])+int(s[12])
    except (OSError,ValueError,IndexError): return None
before=ticks(shell,True); daemon_before=ticks(daemon)
pressure=pathlib.Path("/proc/pressure/cpu").read_text().strip()
start=time.monotonic()
if trigger: pathlib.Path(trigger).touch()
time.sleep(5)
seconds=time.monotonic()-start
after=ticks(shell,True); daemon_after=ticks(daemon)
clock=os.sysconf("SC_CLK_TCK")
def percent(a,b): return None if a is None or b is None else (b-a)/clock/seconds*100
print(json.dumps({"seconds":seconds,"shell_main_pct":percent(before,after),"voxtype_pct":percent(daemon_before,daemon_after),"voxtype_ended":daemon_after is None,"cpu_pressure_before":pressure,"cpu_pressure_after":pathlib.Path("/proc/pressure/cpu").read_text().strip()}))' "$shell_qs_pid" "$(cat "$rt_dir/voxtype/voxtype.lock")" "$1"
}
dictation_flood="$sandbox/voxtype-stderr-flood"
expected_errors+=('dictation: daemon=failed reason=stream-overflow role=daemon')
expect "the fixture enables for the stream reading" ok ipc shell setPluginEnabled acme.dictation true
expect_poll "the fixture is idle before its stream reading" "ready idle -" dictation_state acme.dictation
dictation_idle_cpu="$(dictation_cpu_window '')"
printf '  dictation_cpu phase=idle %s\n' "$dictation_idle_cpu"
dictation_flood_cpu="$(dictation_cpu_window "$dictation_flood")"
printf '  dictation_cpu phase=stderr-flood %s\n' "$dictation_flood_cpu"
expect "a stderr flood stays below a quarter shell main core" True py_reply 'import json,sys; d=json.load(sys.stdin); p=d.get("shell_main_pct"); print(isinstance(p,(int,float)) and 0<=p<25)' <<<"$dictation_flood_cpu"
expect_poll "a stderr flood leaves one failed dictation state" "failed idle -" dictation_state acme.dictation
expect_poll "the overflowing daemon and its follower are reaped" "$dictation_none" dictation_processes all
expect "one failure is logged for the overflowing daemon" 1 log_lines 'dictation: daemon=failed reason=stream-overflow role=daemon'
rm -f -- "${dictation_flood:?}"
expect "disabling the failed fixture releases its hold" ok ipc shell setPluginEnabled acme.dictation false

dictation_stand_ins off
rm -f -- "${dictation_words:?}" "${dictation_notes:?}" "${dictation_typed:?}" "${dictation_loading:?}" "${dictation_follow:?}" "${dictation_daemon_fail:?}" "${dictation_liveness_unreadable:?}"
