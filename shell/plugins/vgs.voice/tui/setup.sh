#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"

plugin_dir="${VGS_PLUGIN_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/voxtype"
config_file="$config_dir/config.toml"
sounds_dir="$config_dir/sounds/bloop"

json_value() {
  local text value
  text="$(printf '%s' "$1" | tr -d '\r\n')"
  if [[ $text =~ ^\"([^\"]*)\"$ ]]; then printf '%s\n' "${BASH_REMATCH[1]}"; return; fi
  value="$(sed -n 's/.*"value"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$text")"
  [[ -n $value ]] && { printf '%s\n' "$value"; return; }
  printf '%s\n' "$text" | sed 's/^ *//;s/ *$//'
}

model_size() {
  local model="$1" text size
  text="$(printf '%s' "$2" | tr -d '\r\n')"
  size="$(sed -n 's/.*"'"$model"'"[^}]*"size"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$text")"
  [[ -n $size ]] || size="$(sed -n 's/.*"'"$model"'"[^}]*"download_size"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$text")"
  printf '%s\n' "${size:-size unknown}"
}

engine_available() {
  local engine="$1" text="$2"
  grep -q '"'"$engine"'"' <<<"$text" || return 1
  ! grep -q '"'"$engine"'"[^}]*"available"[[:space:]]*:[[:space:]]*false' <<<"$text"
}

vgs_tui_header "Set up Voice" "Voice copies defaults only when no voxtype config exists."
engine="$(json_value "$(voxtype config get engine --json 2>/dev/null || printf '"parakeet"')")"
model_key="$engine.model"
model="$(json_value "$(voxtype config get "$model_key" --json 2>/dev/null || printf '"parakeet-tdt-0.6b-v3"')")"
models_json="$(voxtype info models --json)"
size="$(model_size "$model" "$models_json")"
status=0
vgs_tui_confirm "Download and set up the $model speech model ($size)?" || status=$?
case "$status" in
  0) ;;
  1) exit 0 ;;
  *) exit "$status" ;;
esac

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

engine="$(json_value "$(voxtype config get engine --json)")"
model_key="$engine.model"
model="$(json_value "$(voxtype config get "$model_key" --json)")"
engines_json="$(voxtype info engines --json)"
if ! engine_available "$engine" "$engines_json"; then
  vgs_tui_step "Enabling the speech engine"
  vgs_tui_sudo_session start
  voxtype setup onnx --enable
  vgs_tui_sudo_session end
fi

vgs_tui_step "Downloading the speech model"
voxtype setup --download --model "$model" --no-post-install
vgs_tui_step "Enabling the Voice service"
voxtype setup systemd
systemctl --user restart voxtype
