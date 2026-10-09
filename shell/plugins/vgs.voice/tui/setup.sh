#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"

plugin_dir="${VGS_PLUGIN_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/voxtype"
config_file="$config_dir/config.toml"
sounds_dir="$config_dir/sounds/bloop"

json_value() {
  python3 -c 'import json,sys
try:
    data=json.load(sys.stdin)
except Exception:
    print(sys.argv[1]); raise SystemExit
if isinstance(data, dict) and "value" in data:
    print(data["value"])
elif isinstance(data, (str, int, float, bool)):
    print(data)
else:
    print(sys.argv[1])' "$1"
}

engine_compiled() {
  python3 -c 'import json,sys
engine=sys.argv[1]
rows=json.load(sys.stdin)
print("yes" if any(isinstance(row, dict) and row.get("name") == engine and row.get("compiled") is True for row in rows) else "no")' "$1"
}

copy_defaults_if_absent() {
  if [[ ! -e $config_file && ! -L $config_file ]]; then
    vgs_tui_step "Copying Voice defaults"
    mkdir -p -- "$config_dir" "$sounds_dir"
    cp -- "$plugin_dir/sounds/bloop/start.wav" "$sounds_dir/start.wav"
    cp -- "$plugin_dir/sounds/bloop/stop.wav" "$sounds_dir/stop.wav"
    cp -- "$plugin_dir/sounds/bloop/error.wav" "$sounds_dir/error.wav"
    cp -- "$plugin_dir/config.toml" "$config_file"
    absolute_sounds="$(cd -- "$sounds_dir" && pwd -P)"
    sed -i "s#__VGS_VOICE_BLOOP_THEME__#$absolute_sounds#g" "$config_file"
  fi
}

vgs_tui_header "Set up Voice" "Voice copies defaults only when no voxtype config exists."
# The core opens this script only once voxtype is found; a run from
# elsewhere without it stops here, before anything is copied.
if ! command -v voxtype >/dev/null; then
  printf 'vgs-voice: refused: voxtype=missing\n' >&2
  vgs_tui_error "Voice needs voxtype. Press Set up in Voice settings to install it."
  exit 1
fi
copy_defaults_if_absent
engine="$(voxtype config get engine --json | json_value parakeet)"
model_key="$engine.model"
model="$(voxtype config get "$model_key" --json | json_value parakeet-tdt-0.6b-v3)"
status=0
vgs_tui_confirm "Download and set up the $model speech model?" || status=$?
case "$status" in
  0) ;;
  1) exit 0 ;;
  *) exit "$status" ;;
esac

engines_json="$(voxtype info engines --json)"
if [[ $(printf '%s' "$engines_json" | engine_compiled "$engine") != yes ]]; then
  vgs_tui_step "Enabling the speech engine"
  printf 'This step changes system files, so it asks for your password next.\n'
  vgs_tui_sudo_session start
  sudo voxtype setup onnx --enable
  vgs_tui_sudo_session end
fi

vgs_tui_step "Downloading the speech model"
voxtype setup --download --model "$model" --no-post-install
vgs_tui_step "Enabling the Voice service"
voxtype setup systemd
systemctl --user restart voxtype
vgs_tui_success "Voice is ready."
