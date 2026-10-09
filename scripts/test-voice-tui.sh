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

for tool in bash sleep python3 sed mkdir cp grep paste; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'test-voice-tui: status=not-measured missing=%s\n' "$tool"
    exit 77
  fi
done

tools="$TMP_ROOT/tools"
mkdir -p -- "$tools"
for tool in bash sleep python3 sed mkdir cp grep paste; do ln -s -- "$(command -v "$tool")" "$tools/$tool"; done
cat >"$tools/gum" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*"
SH
cat >"$tools/sudo" <<SH
#!/usr/bin/env bash
if [[ \${1:-} == -k ]]; then exit 0; fi
if [[ \${1:-} == -n ]]; then shift; fi
if [[ \$* == /usr/bin/true ]]; then exit 0; fi
printf 'sudo %s\n' "\$*" >>"$TMP_ROOT/calls"
exec "\$@"
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
  'config get engine --json')
    if [[ -f \${XDG_CONFIG_HOME:-\$HOME/.config}/voxtype/config.toml ]]; then printf '{"value":"parakeet"}\n'; else printf '{"value":"whisper"}\n'; fi ;;
  'config get parakeet.model --json') printf '{"value":"parakeet-tdt-0.6b-v3"}\n' ;;
  'config get whisper.model --json') printf '{"value":"base.en"}\n' ;;
  'info models --json') printf '{"engines":{"parakeet":{"models":[{"name":"parakeet-tdt-0.6b-v3","installed":false,"downloadable":true,"download_arg":"parakeet-tdt-0.6b-v3"}],"default":"parakeet-tdt-0.6b-v3"}},"verified":true}\n' ;;
  'info engines --json') printf '[{"name":"whisper","compiled":true,"active":true},{"name":"parakeet","compiled":false,"active":false}]\n' ;;
  *) ;;
esac
SH
chmod 755 "$tools/gum" "$tools/sudo" "$tools/systemctl" "$tools/voxtype"

run_setup() { # HOME [SCRIPT] [PATH]
  local home="$1" script="${2:-$plugin/tui/setup.sh}" path="${3:-$tools}"
  : >"$TMP_ROOT/calls"
  mkdir -p -- "$home"
  status=0
  env -i PATH="$path" HOME="$home" XDG_CONFIG_HOME="$home/.config" VGS_TUI_UNATTENDED=1 VGS_TUI_LIB="$repo/bin/lib/tui.sh" VGS_PLUGIN_DIR="$plugin" bash "$script" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" || status=$?
  calls="$(cat "$TMP_ROOT/calls")"
}

home1="$TMP_ROOT/home1"
run_setup "$home1"
config1="$home1/.config/voxtype/config.toml"
if [[ $status == 0 && -f $config1 ]]; then ok "setup copies default config when absent"; else fail "setup copy: status=$status err=$(cat "$TMP_ROOT/err")"; fi
if grep -q 'Download and set up the parakeet-tdt-0.6b-v3 speech model?' "$TMP_ROOT/out" && ! grep -q 'base.en\|size unknown' "$TMP_ROOT/out"; then ok "setup confirm names the copied default model and no guessed size"; else fail "setup confirm text: $(cat "$TMP_ROOT/out")"; fi
order="$(grep -E 'sudo voxtype setup onnx --enable|voxtype setup (--download --model parakeet-tdt-0.6b-v3 --no-post-install|systemd)|systemctl --user restart voxtype' "$TMP_ROOT/calls" | paste -sd '|' -)"
want='sudo voxtype setup onnx --enable|voxtype setup --download --model parakeet-tdt-0.6b-v3 --no-post-install|voxtype setup systemd|systemctl --user restart voxtype'
if [[ $order == "$want" ]]; then ok "setup calls sudo engine, download, systemd and restart in order"; else fail "setup order: got [$order]"; fi
# The run ends on the library's success line: the success colour, ANSI
# green with no theme, without the bold a step line carries.
ends_ready() {
  local last
  last="$(tail -n 1 "$TMP_ROOT/out")"
  [[ $status == 0 && $last == $'\033[32m'* && $last != *$'\033[1m'* ]]
}
if ends_ready; then ok "setup ends with a success line after the service restart"; else fail "setup end: status=$status last=[$(tail -n 1 "$TMP_ROOT/out")]"; fi
control="$TMP_ROOT/setup-unfinished.sh"
python3 - "$plugin/tui/setup.sh" "$control" <<'PY'
import sys
source = open(sys.argv[1]).read()
needle = 'vgs_tui_success "Voice is ready."\n'
if source.count(needle) != 1:
    raise SystemExit('success line count')
open(sys.argv[2], 'w').write(source.replace(needle, ''))
PY
chmod 755 "$control"
run_setup "$TMP_ROOT/home-unfinished" "$control"
if ends_ready; then fail "control success line: the copy without it still ended on a success line"; else ok "control success line turns the finished case red"; fi

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
run_setup "$home2" "$control"
if [[ -L $home2/.config/voxtype/config.toml && $(cat "$TMP_ROOT/dotfiles/config.toml") == 'kept=1' ]]; then fail "control symlink rewrite: setup still left the symlinked config untouched"; else ok "control symlink rewrite turns the symlink case red"; fi

control="$TMP_ROOT/setup-nosudo.sh"
python3 - "$plugin/tui/setup.sh" "$control" <<'PY'
import sys
source = open(sys.argv[1]).read()
needle = 'sudo voxtype setup onnx --enable'
if source.count(needle) != 1:
    raise SystemExit('sudo line count')
open(sys.argv[2], 'w').write(source.replace(needle, 'voxtype setup onnx --enable'))
PY
chmod 755 "$control"
rm -rf -- "${TMP_ROOT:?}/home3"
run_setup "$TMP_ROOT/home3" "$control"
order="$(grep -E 'sudo voxtype setup onnx --enable|voxtype setup (--download --model parakeet-tdt-0.6b-v3 --no-post-install|systemd)|systemctl --user restart voxtype' "$TMP_ROOT/calls" | paste -sd '|' -)"
if [[ $order == "$want" ]]; then fail "control sudo: setup still routed onnx through sudo"; else ok "control sudo turns the sudo route case red"; fi

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
    ! grep -q 'command not found' "$TMP_ROOT/err" && [[ ! -e $1/.config/voxtype ]] &&
    ! grep -q '^systemctl ' "$TMP_ROOT/calls"
}
for screen in setup configure model; do
  run_setup "$TMP_ROOT/home-$screen" "$plugin/tui/$screen.sh" "$no_voxtype"
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
  run_setup "$TMP_ROOT/home-$screen-control" "$control" "$no_voxtype"
  if missing_refused "$TMP_ROOT/home-$screen-control"; then fail "control voxtype check: the $screen copy without the check still refused cleanly"; else ok "control voxtype check turns the missing-voxtype $screen case red (status=$status)"; fi
done

if [[ $failures -gt 0 ]]; then
  printf 'test-voice-tui: failures=%d\n' "$failures"
  exit 1
fi
printf 'test-voice-tui: ok\n'
