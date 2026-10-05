#!/usr/bin/env bash
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
plugin="$repo/shell/plugins/vgs.voice"
TMP_ROOT="$repo/tmp/voice-tui-test-$$"
rm -rf -- "${TMP_ROOT:?}"
mkdir -p -- "$TMP_ROOT"
trap 'rm -rf -- "${TMP_ROOT:?}"' EXIT

failures=0
ok() { printf '  ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf '  FAIL  %s\n' "$*"; }

for tool in bash sleep python3 tr sed mkdir cp grep; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'test-voice-tui: status=not-measured missing=%s\n' "$tool"
    exit 77
  fi
done

tools="$TMP_ROOT/tools"
mkdir -p -- "$tools"
ln -s -- "$(command -v bash)" "$tools/bash"
ln -s -- "$(command -v sleep)" "$tools/sleep"
ln -s -- "$(command -v tr)" "$tools/tr"
ln -s -- "$(command -v sed)" "$tools/sed"
ln -s -- "$(command -v mkdir)" "$tools/mkdir"
ln -s -- "$(command -v cp)" "$tools/cp"
ln -s -- "$(command -v grep)" "$tools/grep"
cat >"$tools/gum" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*"
SH
cat >"$tools/sudo" <<'SH'
#!/usr/bin/env bash
if [[ ${1:-} == -k ]]; then exit 0; fi
if [[ ${1:-} == -n ]]; then shift; fi
if [[ $# -gt 0 ]]; then exit 0; fi
exit 0
SH
cat >"$tools/systemctl" <<SH
#!/usr/bin/env bash
printf 'systemctl %s\n' "\$*" >>"$TMP_ROOT/calls"
if [[ \$* == "--user is-enabled voxtype" ]]; then printf 'disabled\n'; fi
SH
cat >"$tools/voxtype" <<SH
#!/usr/bin/env bash
printf 'voxtype %s\n' "\$*" >>"$TMP_ROOT/calls"
case "\$*" in
  'config get engine --json') printf '{"value":"parakeet"}\n' ;;
  'config get parakeet.model --json') printf '{"value":"parakeet-tdt-0.6b-v3"}\n' ;;
  'info models --json') printf '{"models":[{"name":"parakeet-tdt-0.6b-v3","installed":false,"size":"600 MB"}]}\n' ;;
  'info engines --json') printf '{"engines":[{"name":"parakeet","available":false}]}\n' ;;
  *) ;;
esac
SH
chmod 755 "$tools/gum" "$tools/sudo" "$tools/systemctl" "$tools/voxtype"

run_setup() {
  local home="$1"
  : >"$TMP_ROOT/calls"
  mkdir -p -- "$home"
  status=0
  env -i PATH="$tools" HOME="$home" XDG_CONFIG_HOME="$home/.config" VGS_TUI_UNATTENDED=1 VGS_TUI_LIB="$repo/bin/lib/tui.sh" VGS_PLUGIN_DIR="$plugin" bash "$plugin/tui/setup.sh" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" || status=$?
  calls="$(cat "$TMP_ROOT/calls")"
}

home1="$TMP_ROOT/home1"
run_setup "$home1"
config1="$home1/.config/voxtype/config.toml"
if [[ $status == 0 && -f $config1 ]]; then ok "setup copies default config when absent"; else fail "setup copy: status=$status err=$(cat "$TMP_ROOT/err")"; fi
if [[ -f $home1/.config/voxtype/sounds/bloop/start.wav && -f $home1/.config/voxtype/sounds/bloop/stop.wav && -f $home1/.config/voxtype/sounds/bloop/error.wav ]]; then ok "setup copies the bloop sounds"; else fail "setup did not copy every sound"; fi
if grep -q "__VGS_VOICE_BLOOP_THEME__" "$config1"; then fail "setup left the sound placeholder in config"; else ok "setup writes the absolute sound path"; fi
order="$(grep -E 'voxtype setup (onnx --enable|--download --model parakeet-tdt-0.6b-v3 --no-post-install|systemd)|systemctl --user restart voxtype' "$TMP_ROOT/calls" | paste -sd '|' -)"
want='voxtype setup onnx --enable|voxtype setup --download --model parakeet-tdt-0.6b-v3 --no-post-install|voxtype setup systemd|systemctl --user restart voxtype'
if [[ $order == "$want" ]]; then ok "setup calls engine, download, systemd and restart in order"; else fail "setup order: got [$order]"; fi

home2="$TMP_ROOT/home2"
mkdir -p -- "$home2/.config/voxtype" "$TMP_ROOT/dotfiles"
printf 'kept=1\n' >"$TMP_ROOT/dotfiles/config.toml"
ln -s -- "$TMP_ROOT/dotfiles/config.toml" "$home2/.config/voxtype/config.toml"
run_setup "$home2"
if [[ -L $home2/.config/voxtype/config.toml && $(cat "$TMP_ROOT/dotfiles/config.toml") == 'kept=1' ]]; then ok "setup leaves an existing symlinked config untouched"; else fail "setup changed an existing symlinked config"; fi

control="$TMP_ROOT/setup-copy.sh"
python3 - "$plugin/tui/setup.sh" "$control" <<'PY'
import sys
source = open(sys.argv[1]).read()
needle = 'if [[ ! -e $config_file && ! -L $config_file ]]; then'
if source.count(needle) != 1:
    raise SystemExit('copy guard count')
open(sys.argv[2], 'w').write(source.replace(needle, 'if true; then'))
PY
chmod 755 "$control"
: >"$TMP_ROOT/calls"
status=0
env -i PATH="$tools" HOME="$home2" XDG_CONFIG_HOME="$home2/.config" VGS_TUI_UNATTENDED=1 VGS_TUI_LIB="$repo/bin/lib/tui.sh" VGS_PLUGIN_DIR="$plugin" bash "$control" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" || status=$?
if [[ -L $home2/.config/voxtype/config.toml ]]; then fail "control symlink rewrite: setup still left the symlink"; else ok "control symlink rewrite turns the symlink case red"; fi

control="$TMP_ROOT/setup-order.sh"
python3 - "$plugin/tui/setup.sh" "$control" <<'PY'
import sys
source = open(sys.argv[1]).read()
needle = 'voxtype setup onnx --enable\n  vgs_tui_sudo_session end'
if source.count(needle) != 1:
    raise SystemExit('order line count')
open(sys.argv[2], 'w').write(source.replace(needle, ':\n  vgs_tui_sudo_session end'))
PY
chmod 755 "$control"
rm -rf -- "${TMP_ROOT:?}/home3"
: >"$TMP_ROOT/calls"
status=0
env -i PATH="$tools" HOME="$TMP_ROOT/home3" XDG_CONFIG_HOME="$TMP_ROOT/home3/.config" VGS_TUI_UNATTENDED=1 VGS_TUI_LIB="$repo/bin/lib/tui.sh" VGS_PLUGIN_DIR="$plugin" bash "$control" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" || status=$?
order="$(grep -E 'voxtype setup (onnx --enable|--download --model parakeet-tdt-0.6b-v3 --no-post-install|systemd)|systemctl --user restart voxtype' "$TMP_ROOT/calls" | paste -sd '|' -)"
if [[ $order == "$want" ]]; then fail "control order: setup still matched the required order"; else ok "control order turns the call order case red"; fi

if [[ $failures -gt 0 ]]; then
  printf 'test-voice-tui: failures=%d\n' "$failures"
  exit 1
fi
printf 'test-voice-tui: ok\n'
