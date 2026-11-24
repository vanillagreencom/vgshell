#!/usr/bin/env bash
# loads: shell/plugins/vgs.voice/tui/*.sh -- the cases run each screen they list
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
plugin="$repo/shell/plugins/vgs.voice"
TMP_ROOT="$(mktemp -d)" || { echo "test-voice-tui: scratch=mktemp-failed" >&2; exit 1; }
[[ -d $TMP_ROOT && ! -L $TMP_ROOT ]] || { echo "test-voice-tui: scratch=not-a-directory value=[$TMP_ROOT]" >&2; exit 1; }
TMP_ROOT="$(cd -- "$TMP_ROOT" && pwd -P)" || { echo "test-voice-tui: scratch=resolve-failed" >&2; exit 1; }
trap 'rm -rf -- "${TMP_ROOT:?}"' EXIT

failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

for tool in bash sleep python3 paste grep script gum; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'test-voice-tui: status=not-measured missing=%s\n' "$tool"
    exit 77
  fi
done
gum_bin="$(command -v gum)"
gum_bin="$(readlink -f -- "$gum_bin")"

# The screens' whole world: a gum that prints, an rm, a voxtype that
# records its call and answers `status` with the `alt` word in
# `voxtype-alt`, failing when a case wrote none, and a systemctl that
# records every call, answers `show` with the file `show` a case writes,
# and exits with the status in `exit-<verb>`, 0 when a case wrote none.
# Only Stop the other voxtype may call systemctl: the core runs voxtype,
# and no user unit does.
tools="$TMP_ROOT/tools"
mkdir -p -- "$tools"
for tool in bash sleep python3 rm; do ln -s -- "$(command -v "$tool")" "$tools/$tool"; done
cat >"$tools/gum" <<SH
#!/usr/bin/env bash
if [[ \$1 == choose ]]; then
  choices="\$(</dev/stdin)"
  printf '%s\n' "\$choices" >"$TMP_ROOT/choices"
  [[ ! -f $TMP_ROOT/choose-exit ]] || exit "\$(<"$TMP_ROOT/choose-exit")"
  wanted="\$(<"$TMP_ROOT/chosen")"
  # gum 2.0.2 choose/command.go uses label, value = strings.Cut(option,
  # LabelDelimiter), then maps each displayed label to its returned value.
  while IFS=\$'\t' read -r label key; do
    [[ \$key == "\$wanted":* ]] || continue
    printf '%s\n' "\$key"
    exit 0
  done <<<"\$choices"
  exit 1
fi
printf '%s\n' "\$*"
SH
cat >"$tools/voxtype" <<SH
#!/usr/bin/env bash
printf 'voxtype %s\n' "\$*" >>"$TMP_ROOT/calls"
if [[ \$1 == status ]]; then
  [[ -f $TMP_ROOT/voxtype-alt ]] || exit 1
  printf '{"text": "", "alt": "%s", "class": "%s"}\n' "\$(<"$TMP_ROOT/voxtype-alt")" "\$(<"$TMP_ROOT/voxtype-alt")"
fi
if [[ \$1 == info ]]; then
  [[ ! -f $TMP_ROOT/info-exit-\$2 ]] || exit "\$(<"$TMP_ROOT/info-exit-\$2")"
  printf '%s\n' "\$(<"$TMP_ROOT/\$2.json")"
fi
if [[ \$1 == setup ]]; then
  [[ ! -f $TMP_ROOT/download-exit ]] || exit "\$(<"$TMP_ROOT/download-exit")"
fi
SH
cat >"$tools/systemctl" <<SH
#!/usr/bin/env bash
printf 'systemctl %s\n' "\$*" >>"$TMP_ROOT/calls"
[[ \$2 != show ]] || printf '%s\n' "\$(<"$TMP_ROOT/show")"
code=0
[[ ! -f $TMP_ROOT/exit-\$2 ]] || read -r code <"$TMP_ROOT/exit-\$2"
exit "\$code"
SH
chmod 755 "$tools/gum" "$tools/systemctl" "$tools/voxtype"

run_screen() { # HOME SCRIPT [PATH]
  local home="$1" script="$2" path="${3:-$tools}"
  : >"$TMP_ROOT/calls"
  mkdir -p -- "$home"
  status=0
  env -i PATH="$path" HOME="$home" XDG_CONFIG_HOME="$home/.config" VGS_TUI_UNATTENDED=1 VGS_TUI_LIB="$repo/bin/lib/tui.sh" VGS_PLUGIN_DIR="$plugin" bash "$script" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" || status=$?
  calls="$(paste -sd '|' "$TMP_ROOT/calls")"
}

# Configure runs voxtype's screen. The core restarts its own daemon when
# the screen ends; a copy that restarts a user unit must turn this red.
declare -A screen_call=([configure]='voxtype configure')
for screen in configure; do
  run_screen "$TMP_ROOT/home-$screen-run" "$plugin/tui/$screen.sh"
  if [[ $status == 0 && $calls == "${screen_call[$screen]}" ]]; then ok "$screen runs voxtype's screen and no systemctl"; else fail "$screen: status=$status calls=[$calls] err=$(cat "$TMP_ROOT/err")"; fi

  control="$TMP_ROOT/$screen-restarts.sh"
  cp -- "$plugin/tui/$screen.sh" "$control"
  printf '%s\n' 'systemctl --user restart voxtype' >>"$control"
  run_screen "$TMP_ROOT/home-$screen-restarts" "$control"
  if [[ $status == 0 && $calls == "${screen_call[$screen]}" ]]; then fail "control systemctl: the $screen copy that restarts a user unit still passed"; else ok "control systemctl turns the $screen case red (calls=[$calls])"; fi
done

# Without voxtype on PATH, each Voice screen refuses with its keyed line
# before it changes anything, and no shell error reaches the terminal. Each
# screen's control is a copy without its check.
no_voxtype="$TMP_ROOT/tools-no-voxtype"
mkdir -p -- "$no_voxtype"
for tool in "$tools"/*; do
  [[ ${tool##*/} == voxtype ]] || ln -s -- "$tool" "$no_voxtype/${tool##*/}"
done
missing_refused() { # HOME
  [[ $status == 1 && $(head -n 1 "$TMP_ROOT/err") == 'vgs-voice: refused: voxtype=missing' ]] &&
    ! grep -q 'command not found' "$TMP_ROOT/err" && [[ ! -e $1/.config/voxtype && -z $calls ]]
}
for screen in configure model; do
  run_screen "$TMP_ROOT/home-$screen" "$plugin/tui/$screen.sh" "$no_voxtype"
  if missing_refused "$TMP_ROOT/home-$screen"; then ok "$screen without voxtype refuses with one keyed line and changes nothing"; else fail "$screen without voxtype: status=$status err=$(cat "$TMP_ROOT/err")"; fi

  control="$TMP_ROOT/$screen-nocheck.sh"
  python3 - "$plugin/tui/$screen.sh" "$control" <<'PY'
import sys
source = open(sys.argv[1]).read()
needle = 'if ! command -v voxtype >/dev/null; then'
if source.count(needle) != 1:
    raise SystemExit('voxtype check count')
open(sys.argv[2], 'w').write(source.replace(needle, 'if false; then'))
PY
  chmod 755 "$control"
  run_screen "$TMP_ROOT/home-$screen-control" "$control" "$no_voxtype"
  if missing_refused "$TMP_ROOT/home-$screen-control"; then fail "control voxtype check: the $screen copy without the check still refused cleanly"; else ok "control voxtype check turns the missing-voxtype $screen case red (status=$status)"; fi
done

# The picker runs on script(1)'s terminal, with the real TUI and voxtype
# reading libraries. Its sibling core step and every voxtype are stand-ins.
model_lib="$TMP_ROOT/core/lib"
mkdir -p -- "$model_lib" "$TMP_ROOT/onnx"
cp -- "$repo/bin/lib/tui.sh" "$repo/bin/lib/voxtype.sh" "$model_lib/"
cat >"$TMP_ROOT/onnx/voxtype-onnx-avx2" <<SH
#!/usr/bin/env bash
printf 'onnx %s\n' "\$*" >>"$TMP_ROOT/calls"
[[ ! -f $TMP_ROOT/info-exit-onnx ]] || exit "\$(<"$TMP_ROOT/info-exit-onnx")"
printf '%s\n' "\$(<"$TMP_ROOT/onnx-engines.json")"
SH
cat >"$TMP_ROOT/core/vgshell-system" <<SH
#!/usr/bin/env bash
printf 'system %s engine=%s\n' "\$*" "\${VOXTYPE_ENGINE:-}" >>"$TMP_ROOT/calls"
[[ ! -f $TMP_ROOT/system-exit ]] || exit "\$(<"$TMP_ROOT/system-exit")"
# Like the core probe, an apply with the current Whisper engine is ready
# and changes nothing. The picker must hand it the selected engine.
[[ \${VOXTYPE_ENGINE:-whisper} != whisper && ! -f $TMP_ROOT/system-no-change ]] || exit 0
printf '%s\n' "\$(<"$TMP_ROOT/onnx-engines.json")" >"$TMP_ROOT/engines.json"
SH
chmod 755 "$TMP_ROOT/core/vgshell-system" "$TMP_ROOT/onnx/voxtype-onnx-avx2"
model_screen="$plugin/tui/model.sh"
model_world() { # whisper|onnx|missing|cpu|gpu|absent
  rm -f -- "$TMP_ROOT/choose-exit" "$TMP_ROOT/download-exit" "$TMP_ROOT/system-exit" "$TMP_ROOT/system-no-change" "$TMP_ROOT"/info-exit-*
  python3 - "$TMP_ROOT" "$1" <<'PY'
import json, pathlib, sys
root, build = pathlib.Path(sys.argv[1]), sys.argv[2]
rows = {
    "whisper": [dict(name="base.en", installed=True, downloadable=True, download_arg="base.en")],
    "parakeet": [dict(name="parakeet-tdt-0.6b-v3", installed=False, downloadable=True, download_arg="parakeet-tdt-0.6b-v3")],
    "moonshine": [dict(name="base", installed=False, downloadable=True, download_arg="moonshine-base")],
    "sensevoice": [dict(name="small", installed=False, downloadable=True, download_arg="sensevoice-small")],
}
engines = [dict(name=name, compiled=build == "onnx" or name == "whisper", active=name == "whisper") for name in rows]
all_engines = [dict(row, compiled=True) for row in engines]
inventory = dict(install_kind="package", package_lib_dir=str(root / "onnx"), variants=[])
if build != "missing":
    inventory["variants"] = [dict(variant="onnx-avx2", binary_name="voxtype-onnx-avx2", installed=build != "absent", runs_on_this_cpu=build != "cpu", gpu_available=build != "gpu")]
for name, value in [("models",dict(engines={engine:dict(models=items) for engine,items in rows.items()})), ("engines",engines), ("onnx-engines",all_engines), ("variants",inventory)]:
    (root / (name + ".json")).write_text(json.dumps(value))
PY
}
model_run() { # NAME SCRIPT ENGINE:DOWNLOAD_ARG
  local home="$TMP_ROOT/home-model-$1" script="$2"
  mkdir -p -- "$home"
  : >"$TMP_ROOT/calls"
  : >"$TMP_ROOT/err"
  rm -f -- "$TMP_ROOT/choices"
  printf '%s\n' "$3" >"$TMP_ROOT/chosen"
  status=0
  env -i PATH="$tools" HOME="$home" XDG_CONFIG_HOME="$home/.config" SHELL="$BASH" VGS_TUI_UNATTENDED=1 VGS_TUI_LIB="$model_lib/tui.sh" VGS_PLUGIN_DIR="$plugin" "$(command -v script)" -qec "$(printf '%q ' "$BASH" "$script")" /dev/null </dev/null >"$TMP_ROOT/out" 2>&1 || status=$?
  calls="$(paste -sd '|' "$TMP_ROOT/calls")"
}
model_copy() { # NAME NEEDLE REPLACEMENT
  control="$TMP_ROOT/model-$1.sh"
  python3 - "$model_screen" "$control" "$2" "$3" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
assert source.count(sys.argv[3]) == 1, sys.argv[3]
changed = source.replace(sys.argv[3],sys.argv[4])
assert changed != source
pathlib.Path(sys.argv[2]).write_text(changed)
PY
}
model_read='voxtype info models --json|voxtype info engines --json|voxtype info variants --json'
download='voxtype setup --download --model'
for build in whisper onnx; do
  for choice in whisper:base.en parakeet:parakeet-tdt-0.6b-v3 moonshine:moonshine-base sensevoice:sensevoice-small; do
    model_world "$build"
    model_run "$build-${choice%%:*}" "$model_screen" "$choice"
    expected="$model_read|onnx info engines --json"
    if [[ $build == whisper && $choice != whisper:* ]]; then
      expected+="|system apply voxtype-engine engine=${choice%%:*}|voxtype info engines --json"
    fi
    expected+="|$download ${choice#*:} --no-post-install --activate"
    if [[ $status == 0 && $calls == "$expected" ]] && ! grep -Eiq 'rebuild|--features' "$TMP_ROOT/out"; then
      ok "model $build selects $choice with required engine before download and activation"
    else fail "model $build $choice: status=$status calls=[$calls] out=$(cat "$TMP_ROOT/out")"; fi
    # gum prints the key after TAB. The displayed cells carry model data;
    # check the sizes and distinct language/download states, not full copy.
    if python3 - "$TMP_ROOT/choices" <<'PY'
import pathlib, sys
rows = {key: label for label, key in (line.split("\t",1) for line in pathlib.Path(sys.argv[1]).read_text().splitlines())}
values = {key.split(":",1)[0]:label.split(" · ") for key,label in rows.items()}
assert all(len(fields)==4 and all(fields) for fields in values.values())
assert values["whisper"][1] == "142 MB"
assert values["parakeet"][1] == "2600 MB"
assert values["moonshine"][1] == "237 MB"
assert values["sensevoice"][1] == "239 MB"
assert values["whisper"][2] != values["sensevoice"][2]
assert values["whisper"][3] != values["parakeet"][3]
PY
    then ok "model $build offers model data to gum"; else fail "model $build data"; fi
  done
done
model_key_returned() {
  local row selected
  IFS= read -r row <"$TMP_ROOT/choices" || return
  # Exercise the real parser on a row the production picker emitted.
  # model.sh consumes this structured value after gum choose returns it.
  selected="$("$gum_bin" choose --label-delimiter=$'\t' --select-if-one -- "$row")" || return
  [[ $selected == whisper:base.en:1 ]]
}
model_world onnx
model_run protocol "$model_screen" whisper:base.en
if model_key_returned; then ok "real gum returns the production row's structured model key"; else fail "real gum returned a different model value"; fi
model_copy reversed-columns 'print(f"{display}\t{value}")' 'print(f"{value}\t{display}")'
model_run reversed-columns "$control" whisper:base.en
if model_key_returned; then fail "control reversed columns still returns the model key"; else ok "control reversed columns turns the real-gum value assertion red"; fi
for reason in missing absent cpu gpu; do
  model_world "$reason"
  model_run "$reason" "$model_screen" whisper:base.en
  if [[ $status == 0 && $calls == "$model_read|$download base.en --no-post-install --activate" ]] && ! grep -q $'\tparakeet:' "$TMP_ROOT/choices"; then
    ok "model excludes ONNX models when its shipped build is $reason"
  else fail "model unsupported $reason: status=$status calls=[$calls]"; fi
done
for flag in installed runs_on_this_cpu gpu_available; do
  case "$flag" in installed) reason=absent ;; runs_on_this_cpu) reason=cpu ;; gpu_available) reason=gpu ;; esac
  model_world "$reason"
  model_copy "no-$flag" " and row[\"$flag\"]" ''
  model_run "control-$flag" "$control" whisper:base.en
  if [[ $status == 0 ]] && ! grep -q $'\tparakeet:' "$TMP_ROOT/choices"; then fail "control model $flag still excludes ONNX"; else ok "control model $flag turns unsupported-build case red"; fi
done
# shellcheck disable=SC2016 # source text, not an expansion in this test
model_copy no-override '  VOXTYPE_ENGINE="$engine" ' '  '
model_world whisper
model_run no-override "$control" parakeet:parakeet-tdt-0.6b-v3
if [[ $status == 0 && $calls == *"$download"* ]]; then fail "control model missing selected engine still downloads"; else ok "control selected-engine override turns switching case red"; fi
model_world whisper
printf '1\n' >"$TMP_ROOT/system-no-change"
model_run no-change "$model_screen" parakeet:parakeet-tdt-0.6b-v3
if [[ $status == 1 && $calls != *"$download"* ]]; then ok "model refuses a system step that did not enable its engine"; else fail "model unchanged engine: status=$status calls=[$calls]"; fi
# shellcheck disable=SC2016
model_copy no-verify '  [[ $compiled == yes ]] || {' '  true || {'
model_run no-verify "$control" parakeet:parakeet-tdt-0.6b-v3
if [[ $status == 1 && $calls != *"$download"* ]]; then fail "control model skipped verification still refuses"; else ok "control enabled-engine verification turns unchanged-engine case red"; fi
for failure in choose system download models engines variants onnx; do
  model_world whisper
  case "$failure" in
    choose) printf '130\n' >"$TMP_ROOT/choose-exit"; expected_status=130 ;;
    system) printf '1\n' >"$TMP_ROOT/system-exit"; expected_status=1 ;;
    download) printf '1\n' >"$TMP_ROOT/download-exit"; expected_status=1 ;;
    *) printf '1\n' >"$TMP_ROOT/info-exit-$failure"; expected_status=1 ;;
  esac
  model_run "failed-$failure" "$model_screen" parakeet:parakeet-tdt-0.6b-v3
  if [[ $status == "$expected_status" && ( $failure == download || $calls != *"$download"* ) ]]; then ok "model $failure failure stops before further changes"; else fail "model $failure: status=$status calls=[$calls]"; fi
done

# Stop the other voxtype. Each case writes what `systemctl --user show`
# answers, plants the unit file it names, sets what the stand-ins answer,
# and runs the screen, which confirms unattended. Each control is a copy of
# the screen with one rule taken out, and must turn its case red.
stop_screen="$plugin/tui/stop-other.sh"
show_call='systemctl --user show voxtype.service --property=LoadState,ActiveState,FragmentPath'
disable_call='systemctl --user disable --now voxtype.service'
reload_call='systemctl --user daemon-reload'
status_call='voxtype status --format json'
package_unit="$TMP_ROOT/usr/lib/systemd/user/voxtype.service"
own_unit() { printf '%s\n' "$TMP_ROOT/home-stop-$1/.config/systemd/user/voxtype.service"; } # NAME
stop_world() { # LOAD ACTIVE FRAGMENT [SETTING...]
  # SETTING: alt=WORD, the `alt` voxtype status reads (the read fails when
  # absent); VERB=CODE, systemctl VERB's exit status.
  local setting
  rm -f -- "${TMP_ROOT:?}"/exit-* "${TMP_ROOT:?}/voxtype-alt"
  printf 'LoadState=%s\nActiveState=%s\nFragmentPath=%s\n' "$1" "$2" "$3" >"$TMP_ROOT/show"
  if [[ -n $3 ]]; then mkdir -p -- "${3%/*}"; printf '[Unit]\n' >"$3"; fi
  shift 3
  for setting; do
    case "$setting" in
      alt=*) printf '%s\n' "${setting#alt=}" >"$TMP_ROOT/voxtype-alt" ;;
      *=*) printf '%s\n' "${setting#*=}" >"$TMP_ROOT/exit-${setting%%=*}" ;;
      *) printf 'test-voice-tui: setting=%s\n' "$setting" >&2; exit 2 ;;
    esac
  done
}
stop_run() { # NAME SCRIPT LOAD ACTIVE FRAGMENT [SETTING...]
  local name="$1" script="$2"
  shift 2
  stop_world "$@"
  run_screen "$TMP_ROOT/home-stop-$name" "$script" "${stop_path:-$tools}"
  first_err="$(head -n 1 -- "$TMP_ROOT/err")"
}
stop_copy() { # NAME NEEDLE REPLACEMENT: a copy of the screen with NEEDLE replaced, once
  control="$TMP_ROOT/stop-other-$1.sh"
  python3 - "$stop_screen" "$control" "$2" "$3" <<'PY'
import sys
source = open(sys.argv[1]).read()
if source.count(sys.argv[3]) != 1:
    raise SystemExit('needle count: ' + sys.argv[3])
changed = source.replace(sys.argv[3], sys.argv[4])
if changed == source:
    raise SystemExit('unchanged: ' + sys.argv[3])
open(sys.argv[2], 'w').write(changed)
PY
}

user_unit="$(own_unit own)"
stop_run own "$stop_screen" loaded active "$user_unit"
if [[ $status == 0 && $calls == "$show_call|$disable_call|$reload_call" && ! -e $user_unit ]]; then ok "stop-other turns off the user's own running unit, removes its file and reloads"; else fail "stop-other own unit: status=$status calls=[$calls] err=$(cat "$TMP_ROOT/err")"; fi

package_kept() {
  [[ $status == 0 && $calls == "$show_call|$disable_call" && -f $package_unit ]]
}
stop_run package "$stop_screen" loaded active "$package_unit"
if package_kept; then ok "stop-other turns off a package's running unit and keeps its file"; else fail "stop-other package unit: status=$status calls=[$calls] err=$(cat "$TMP_ROOT/err")"; fi

# shellcheck disable=SC2016 # the needle and its replacement are source text
stop_copy anypath '[[ ${fragment%/*} == "$user_units" ]] && own=true' 'own=true'
stop_run package-control "$control" loaded active "$package_unit"
if package_kept; then fail "control path check: the copy that removes any unit file still kept the package's file"; else ok "control path check turns the package case red (calls=[$calls])"; fi

# A unit that is loaded but does not run did not start the other voxtype:
# the screen changes no unit and no file, reads the daemon, and refuses
# while one still answers.
inactive_unit="$(own_unit inactive)"
inactive_refused() {
  [[ $status == 1 && $first_err == 'vgs-voice: refused: unit=not-running load=loaded active=inactive daemon=idle' && $calls == "$show_call|$status_call" && -f $inactive_unit ]]
}
stop_run inactive "$stop_screen" loaded inactive "$inactive_unit" alt=idle
if inactive_refused; then ok "stop-other keeps an inactive own unit and refuses while another daemon answers"; else fail "stop-other inactive unit: status=$status calls=[$calls] err=$(cat "$TMP_ROOT/err")"; fi

stop_copy noactive 'active | activating | reloading) service_runs=true ;;' '*) service_runs=true ;;'
inactive_unit="$(own_unit inactive-control)"
stop_run inactive-control "$control" loaded inactive "$inactive_unit" alt=idle
if inactive_refused; then fail "control active check: the copy that acts on an inactive unit still kept its file"; else ok "control active check turns the inactive-unit case red (calls=[$calls])"; fi

# No voxtype unit at all: once the daemon reads stopped the place is free,
# and exit 0 has the core start its own; while a daemon answers, or its
# status cannot be read, the screen refuses.
stop_run gone "$stop_screen" not-found inactive "" alt=stopped
if [[ $status == 0 && $calls == "$show_call|$status_call" ]]; then ok "stop-other with no unit and no daemon running ends with 0 and changes nothing"; else fail "stop-other no unit, stopped: status=$status calls=[$calls] err=$(cat "$TMP_ROOT/err")"; fi

elsewhere_refused() { # DAEMON
  [[ $status == 1 && $first_err == "vgs-voice: refused: unit=not-running load=not-found active=inactive daemon=$1" && $calls == "$show_call|$status_call" ]]
}
stop_run elsewhere "$stop_screen" not-found inactive "" alt=idle
if elsewhere_refused idle; then ok "stop-other with no unit refuses with one keyed line while another daemon answers"; else fail "stop-other no unit, idle: status=$status calls=[$calls] err=$(cat "$TMP_ROOT/err")"; fi

stop_run unanswered "$stop_screen" not-found inactive ""
if elsewhere_refused unread; then ok "stop-other with no unit refuses with one keyed line when the daemon's status cannot be read"; else fail "stop-other no unit, unread status: status=$status calls=[$calls] err=$(cat "$TMP_ROOT/err")"; fi

# shellcheck disable=SC2016 # the needle and its replacement are source text
stop_copy noread 'if [[ $service_runs != true ]]; then' $'if [[ $service_runs != true ]]; then\n  exit 0'
stop_run elsewhere-noread "$control" not-found inactive "" alt=idle
if elsewhere_refused idle; then fail "control status read: the copy that ends with 0 unread still refused"; else ok "control status read turns the no-unit idle case red (status=$status)"; fi

# shellcheck disable=SC2016 # the needle and its replacement are source text
stop_copy nogate 'if [[ $service_runs != true ]]; then' 'if false; then'
stop_run elsewhere-nogate "$control" not-found inactive "" alt=idle
if elsewhere_refused idle; then fail "control unit check: the copy without the check still refused cleanly"; else ok "control unit check turns the no-unit idle case red (status=$status calls=[$calls])"; fi

stop_run unread "$stop_screen" "" "" "" show=1
if [[ $status == 1 && $first_err == 'vgs-voice: refused: unit=unread' && $calls == "$show_call" ]]; then ok "stop-other refuses with one keyed line when systemctl cannot answer"; else fail "stop-other unread: status=$status calls=[$calls] err=$(cat "$TMP_ROOT/err")"; fi

# shellcheck disable=SC2016 # the needle and its replacement are source text
stop_copy unread 'if ! shown="$(systemctl --user show "$unit" --property=LoadState,ActiveState,FragmentPath)"; then' $'shown="$(systemctl --user show "$unit" --property=LoadState,ActiveState,FragmentPath)" || true\nif false; then'
stop_run unread-control "$control" "" "" "" show=1
if [[ $status == 1 && $first_err == 'vgs-voice: refused: unit=unread' ]]; then fail "control show check: the copy that ignores a failed show still refused as unread"; else ok "control show check turns the unread case red (first=[$first_err])"; fi

# Each change after the confirm that fails ends the run with its keyed line
# and exit 1, so the core does not start its daemon on a place still held.
disable_failed() { # FRAGMENT
  [[ $status == 1 && $first_err == 'vgs-voice: failed: disable=voxtype.service' && $calls == "$show_call|$disable_call" && -f $1 ]]
}
user_unit="$(own_unit disable-fails)"
stop_run disable-fails "$stop_screen" loaded active "$user_unit" disable=1
if disable_failed "$user_unit"; then ok "stop-other keeps the unit file and fails with one keyed line when disable fails"; else fail "stop-other disable fails: status=$status calls=[$calls] err=$(cat "$TMP_ROOT/err")"; fi

# shellcheck disable=SC2016 # the needle and its replacement are source text
stop_copy disable-ignored 'if ! systemctl --user disable --now "$unit"; then' 'if ! { systemctl --user disable --now "$unit" || true; }; then'
user_unit="$(own_unit disable-control)"
stop_run disable-control "$control" loaded active "$user_unit" disable=1
if disable_failed "$user_unit"; then fail "control disable check: the copy that ignores a failed disable still failed cleanly"; else ok "control disable check turns the failed-disable case red (calls=[$calls])"; fi

rm_fails="$TMP_ROOT/tools-rm-fails"
mkdir -p -- "$rm_fails"
for tool in "$tools"/*; do
  [[ ${tool##*/} == rm ]] || ln -s -- "$tool" "$rm_fails/${tool##*/}"
done
printf '#!/usr/bin/env bash\nexit 1\n' >"$rm_fails/rm"
chmod 755 "$rm_fails/rm"
remove_failed() { # FRAGMENT
  [[ $status == 1 && $first_err == "vgs-voice: failed: remove=$1" && $calls == "$show_call|$disable_call" ]]
}
user_unit="$(own_unit remove-fails)"
stop_path="$rm_fails" stop_run remove-fails "$stop_screen" loaded active "$user_unit"
if remove_failed "$user_unit"; then ok "stop-other fails with one keyed line when the unit file cannot be removed"; else fail "stop-other remove fails: status=$status calls=[$calls] err=$(cat "$TMP_ROOT/err")"; fi

# shellcheck disable=SC2016 # the needle and its replacement are source text
stop_copy remove-ignored 'if ! rm -f -- "$fragment"; then' 'if ! { rm -f -- "$fragment" || true; }; then'
user_unit="$(own_unit remove-control)"
stop_path="$rm_fails" stop_run remove-control "$control" loaded active "$user_unit"
if remove_failed "$user_unit"; then fail "control remove check: the copy that ignores a failed remove still failed cleanly"; else ok "control remove check turns the failed-remove case red (calls=[$calls])"; fi

reload_failed() { # FRAGMENT
  [[ $status == 1 && $first_err == 'vgs-voice: failed: reload' && $calls == "$show_call|$disable_call|$reload_call" && ! -e $1 ]]
}
user_unit="$(own_unit reload-fails)"
stop_run reload-fails "$stop_screen" loaded active "$user_unit" daemon-reload=1
if reload_failed "$user_unit"; then ok "stop-other fails with one keyed line when the reload fails"; else fail "stop-other reload fails: status=$status calls=[$calls] err=$(cat "$TMP_ROOT/err")"; fi

stop_copy reload-ignored 'if ! systemctl --user daemon-reload; then' 'if ! { systemctl --user daemon-reload || true; }; then'
user_unit="$(own_unit reload-control)"
stop_run reload-control "$control" loaded active "$user_unit" daemon-reload=1
if reload_failed "$user_unit"; then fail "control reload check: the copy that ignores a failed reload still failed cleanly"; else ok "control reload check turns the failed-reload case red (calls=[$calls])"; fi

# No at the confirm: the screen runs on a pseudo-terminal script(1) opens,
# without VGS_TUI_UNATTENDED, so vgs_tui_confirm asks gum, whose stand-in
# records that it was asked and answers No.
asked_no="$TMP_ROOT/tools-no"
mkdir -p -- "$asked_no"
for tool in "$tools"/*; do
  [[ ${tool##*/} == gum ]] || ln -s -- "$tool" "$asked_no/${tool##*/}"
done
cat >"$asked_no/gum" <<SH
#!/usr/bin/env bash
if [[ \$1 == confirm ]]; then
  printf '%s\n' "\$*" >"$TMP_ROOT/asked"
  exit 1
fi
printf '%s\n' "\$*"
SH
chmod 755 "$asked_no/gum"
script_bin="$(command -v script)"
bash_bin="$(command -v bash)"
stop_on_terminal() { # NAME SCRIPT FRAGMENT
  local home="$TMP_ROOT/home-stop-$1"
  stop_world loaded active "$3"
  rm -f -- "${TMP_ROOT:?}/asked"
  : >"$TMP_ROOT/calls"
  mkdir -p -- "$home"
  status=0
  env -i PATH="$asked_no" HOME="$home" XDG_CONFIG_HOME="$home/.config" SHELL="$bash_bin" VGS_TUI_LIB="$repo/bin/lib/tui.sh" VGS_PLUGIN_DIR="$plugin" "$script_bin" -qec "$(printf '%q ' "$bash_bin" "$2")" /dev/null </dev/null >"$TMP_ROOT/out" 2>&1 || status=$?
  calls="$(paste -sd '|' "$TMP_ROOT/calls")"
}
answered_no() { # FRAGMENT
  [[ $status == 0 && $calls == "$show_call" && -f $1 && -f $TMP_ROOT/asked ]]
}
user_unit="$(own_unit no)"
stop_on_terminal no "$stop_screen" "$user_unit"
if answered_no "$user_unit"; then ok "stop-other answered No changes nothing and ends with 0"; else fail "stop-other No: status=$status calls=[$calls] out=$(cat "$TMP_ROOT/out")"; fi

stop_copy no-proceeds '  1) exit 0 ;;' '  1) ;;'
user_unit="$(own_unit no-control)"
stop_on_terminal no-control "$control" "$user_unit"
if answered_no "$user_unit"; then fail "control No: the copy that goes on after No still changed nothing"; else ok "control No turns the answered-No case red (calls=[$calls])"; fi

if [[ $failures -gt 0 ]]; then
  printf 'test-voice-tui: failures=%d\n' "$failures"
  exit 1
fi
printf 'test-voice-tui: ok\n'
