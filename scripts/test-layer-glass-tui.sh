#!/usr/bin/env bash
# Actual layer-glass TUI against a private command world. No fixture reaches
# the host compositor, manager, elevation, configuration or package state.
set -euo pipefail
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"
script="$repo/shell/plugins/vgs.windows/tui/layer-glass.sh"
mkdir -p "$tmp/tools" "$tmp/state" "$tmp/install/bin/lib"
for name in bash cat python3 rm; do ln -s "$(command -v "$name")" "$tmp/tools/$name"; done
ln -s "$node_bin" "$tmp/tools/node"
ln -s "$repo/bin/lib/qml-library.js" "$tmp/install/bin/lib/qml-library.js"
ln -s "$repo/shell" "$tmp/install/shell"
for name in cpio cmake pkg-config g++ gcc git; do ln -s "$(type -P true)" "$tmp/tools/$name"; done
cat >"$tmp/install/bin/lib/tui.sh" <<'LIB'
vgs_tui_header() { :; }
vgs_tui_step() { :; }
vgs_tui_success() { :; }
vgs_tui_error() { printf '%s\n' "$*" >&2; }
vgs_tui_commands() { printf '%s\n' "$@" >>"$STATE_DIR/presented"; }
vgs_tui_confirm() { return "$ANSWER"; }
LIB
cat >"$tmp/tools/hyprpm" <<'STUB'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >>"$STATE_DIR/calls"
state=$(cat "$STATE_DIR/manager")
case $1 in
list)
  [[ $state != unread ]] || exit 1
  [[ $state != malformed ]] || { echo garbage; exit; }
  if [[ -f $STATE_DIR/first-use ]]; then
    # DataState::ensureStateStoreExists, through infoString/Colors::RESET,
    # Hyprland efb50993780079460b0cbed1363e2166a2de1d9f.
    printf '\033[0m→\033[0m The hyprpm state store doesn\x27t exist. Creating now...\n'
    rm "$STATE_DIR/first-use"
  fi
  if [[ $state != absent ]]; then
    echo '→ Repository HyprGlass (by hyprnux):'
    echo '  │ Plugin hyprglass'
    case $state in enabled) echo '  └─ enabled: true';; disabled) echo '  └─ enabled: false';; failed) echo '  └─ enabled: Plugin failed to build';; esac
  fi
  if [[ -f $STATE_DIR/unrelated ]]; then cat "$STATE_DIR/unrelated"; fi
  ;;
update)
  if [[ -f $STATE_DIR/fail-update ]]; then read -r code <"$STATE_DIR/fail-update"; exit "$code"; fi
  [[ $state != failed ]] || printf 'disabled' >"$STATE_DIR/manager"
  if [[ $(<"$STATE_DIR/enabled") == true ]]; then
    printf 'enabled' >"$STATE_DIR/manager"
    printf '[{"name":"hyprglass","author":"hyprnux","handle":"opaque","version":"1.1.1","description":"Glass"}]' >"$STATE_DIR/loaded"
  fi
  ;;
add) printf 'disabled' >"$STATE_DIR/manager"; printf 'false' >"$STATE_DIR/enabled" ;;
enable)
  if [[ ! -f $STATE_DIR/false-success ]]; then
    printf 'enabled' >"$STATE_DIR/manager"
    printf 'true' >"$STATE_DIR/enabled"
    printf '[{"name":"hyprglass","author":"hyprnux","handle":"opaque","version":"1.1.1","description":"Glass"}]' >"$STATE_DIR/loaded"
  fi
  ;;
disable)
  [[ $state == failed ]] || printf 'disabled' >"$STATE_DIR/manager"
  printf 'false' >"$STATE_DIR/enabled"
  [[ -f $STATE_DIR/false-success ]] || printf '[]' >"$STATE_DIR/loaded"
  ;;
*) exit 99 ;;
esac
STUB
cat >"$tmp/tools/hyprctl" <<'STUB'
#!/usr/bin/env bash
[[ $* == '-j plugin list' ]] || exit 99
[[ ! -f $STATE_DIR/unread-loaded ]] || exit 1
cat "$STATE_DIR/loaded"
STUB
chmod +x "$tmp/tools/hyprpm" "$tmp/tools/hyprctl"
reset() {
  rm -f "${tmp:?}/state/"*
  printf '%s' "${1:-absent}" >"$tmp/state/manager"
  printf '%s' "${2:-[]}" >"$tmp/state/loaded"
  if [[ ${1:-absent} == enabled || ${1:-absent} == failed ]]; then printf 'true' >"$tmp/state/enabled"; else printf 'false' >"$tmp/state/enabled"; fi
  : >"$tmp/state/calls"
}
run_tui() {
  status=0
  env -i PATH="$tmp/tools" HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" XDG_DATA_HOME="$tmp/home/.local/share" XDG_STATE_HOME="$tmp/home/.local/state" XDG_CACHE_HOME="$tmp/home/.cache" VGS_TEST_RUN=1 STATE_DIR="$tmp/state" ANSWER="${answer:-0}" VGS_TUI_LIB="$tmp/install/bin/lib/tui.sh" "$BASH" "$file" "$@" >"$tmp/out" 2>"$tmp/err" || status=$?
  if ! calls=$(cat -- "$tmp/state/calls"); then
    fail 'manager-call-log-unread'
    return 1
  fi
}
loaded='[{"name":"hyprglass","author":"hyprnux","handle":"opaque","version":"1.1.1","description":"Glass"}]'
case_fresh() {
  local lifecycle
  for lifecycle in first-use initialized-empty; do
    reset
    if [[ $lifecycle == first-use ]]; then : >"$tmp/state/first-use"; fi
    run_tui prepare
    [[ $status == 0 && $calls == $'list\nlist\nupdate\nlist\nlist\nadd https://github.com/hyprnux/hyprglass\nlist' && $(<"$tmp/state/loaded") == '[]' && $(<"$tmp/state/enabled") == false ]] || return 1
  done
}
case_existing() { reset disabled "$loaded"; run_tui enable; [[ $status == 0 && $calls == $'list\nlist\nenable hyprglass\nlist' ]]; }
case_prepare_built() { for state in disabled enabled; do reset "$state" "$loaded"; run_tui prepare; [[ $status == 0 && $calls == list && $(<"$tmp/state/loaded") == "$loaded" ]] || return 1; done; }
case_loaded() { reset enabled "$loaded"; run_tui enable; [[ $status == 0 && $calls == list ]]; }
case_disable() { reset enabled "$loaded"; run_tui disable; [[ $status == 0 && $calls == $'list\nlist\ndisable hyprglass\nlist' ]]; }
case_cancel() { reset; answer=1 run_tui prepare; [[ $status == 10 && $calls == list ]]; }
case_interrupt() { reset; answer=130 run_tui prepare; [[ $status == 130 && $calls == list ]]; }
case_rebuild() {
  for verb in prepare rebuild; do
    reset failed
    run_tui "$verb"
    local update=update
    [[ $verb != rebuild ]] || update='update --force'
    [[ $status == 0 && $calls == "list"$'\nlist\ndisable hyprglass\nlist\nlist\n'"$update"$'\nlist' && $(<"$tmp/state/loaded") == '[]' && $(<"$tmp/state/enabled") == false ]] || return 1
  done
}
case_rebuild_loaded() {
  for state in enabled failed; do
    reset "$state" "$loaded"
    run_tui rebuild
    [[ $status == 0 && $calls == $'list\nlist\ndisable hyprglass\nlist\nlist\nupdate --force\nlist' && $(<"$tmp/state/loaded") == '[]' ]] || return 1
  done
}
case_unrelated() {
  for world in unmanaged-loaded managed-not-loaded; do
    reset disabled
    if [[ $world == unmanaged-loaded ]]; then
      printf '%s' '[{"name":"foreign","author":"someone","handle":"x","version":"1","description":"x"}]' >"$tmp/state/loaded"
    else
      printf '%s\n' '→ Repository other (by someone):' '  │ Plugin foreign' '  └─ enabled: true' >"$tmp/state/unrelated"
    fi
    run_tui prepare
    [[ $status == 1 && $calls == list ]] || return 1
  done
}
case_manual() { reset absent "$loaded"; run_tui disable; [[ $status == 1 && $calls == list ]]; }
case_residual() { reset enabled "$loaded"; : >"$tmp/state/false-success"; run_tui disable; [[ $status == 1 ]]; }
case_false_enable() { reset disabled "$loaded"; : >"$tmp/state/false-success"; run_tui enable; [[ $status == 1 ]]; }
case_update_failure() { reset failed; printf '1\n' >"$tmp/state/fail-update"; run_tui rebuild; [[ $status == 1 && $calls == $'list\nlist\ndisable hyprglass\nlist\nlist\nupdate --force' ]]; }
case_update_interrupt() { reset failed; printf '130\n' >"$tmp/state/fail-update"; run_tui rebuild; [[ $status == 130 && $calls == $'list\nlist\ndisable hyprglass\nlist\nlist\nupdate --force' ]]; }
case_rebuild_isolated() {
  for state in absent failed enabled; do
    reset "$state"
    printf '%s\n' '→ Repository other (by someone):' '  │ Plugin foreign' '  └─ enabled: false' >"$tmp/state/unrelated"
    run_tui rebuild
    [[ $status == 1 && $calls == list ]] || return 1
  done
}
case_enabled_unloaded() { for state in absent enabled disabled; do reset "$state"; run_tui enable; [[ $status == 1 && $calls == list && $(<"$tmp/state/loaded") == '[]' ]] || return 1; done; }
case_unread() { for state in unread malformed; do reset "$state"; run_tui enable; [[ $status == 1 && $calls == list ]] || return 1; done; }
case_bad_json() { for json in null '{}' '[{}]' '[{"name":"hyprglass"}]' "${loaded%]},${loaded#[}"; do reset disabled "$json"; run_tui prepare; [[ $status == 1 && $calls == list ]] || return 1; done; }
case_extra() { reset; run_tui enable extra; [[ $status == 2 && -z $calls ]]; }
case_missing() {
  reset; mv "$tmp/tools/cmake" "$tmp/cmake"; run_tui prepare
  local prepare_status=$status prepare_calls=$calls
  reset enabled "$loaded"; run_tui disable
  local disable_status=$status
  reset disabled "$loaded"; run_tui enable
  mv "$tmp/cmake" "$tmp/tools/cmake"
  [[ $prepare_status == 1 && -z $prepare_calls && $disable_status == 0 && $status == 0 ]]
}
file="$script"
for name in fresh existing prepare_built loaded disable cancel interrupt rebuild rebuild_loaded unrelated manual residual false_enable update_failure update_interrupt rebuild_isolated enabled_unloaded unread bad_json extra missing; do
  if "case_$name"; then ok "$name"; else fail "$name exit=$status calls=[$calls] err=[$(<"$tmp/err")]"; fi
done
# Controls run just the assertion for the changed rule on a disposable copy.
for spec in \
  'unrelated|if unrelated_loaded != unrelated_enabled:|if False:' \
  'existing|hyprpm "$@"|hyprpm "$@" extra' \
  'disable|if [[ $managed != absent ]]; then mutate disable hyprglass; fi|if false; then mutate disable hyprglass; fi' \
  'bad_json|const read = state.layerGlassRead("plugins", process.argv[3], "");|const read = { ok: true, value: [] };' \
  'rebuild|    mutate disable hyprglass|    :' \
  'rebuild_isolated|unrelated = any(n != '\''HyprGlass'\'' for n in repositories) or any(n != '\''hyprglass'\'' for n in entries)|unrelated = False'; do
  IFS='|' read -r name needle replacement <<<"$spec"
  python3 - "$script" "$tmp/control" "$needle" "$replacement" <<'CONTROL'
import pathlib, sys
source, dest, needle, replacement = sys.argv[1:]
text = pathlib.Path(source).read_text()
assert text.count(needle) == 1, needle
pathlib.Path(dest).write_text(text.replace(needle, replacement))
CONTROL
  file="$tmp/control"
  if "case_$name"; then fail "control accepted $name"; else ok "control rejects $name"; fi
done
exit "$((failures > 0))"
