#!/usr/bin/env bash
# Measure each passive shader layer on a real GPU in the nested sandbox:
# VoiceOrb and Voice's plasma orb.
# Usage: scripts/measure-shader.sh [--shader NAME] [--calibrate FILE [--runs N]] [--keep]
# Default: check every shader against its record in
# scripts/shader/ceilings.json and prove its 256-step control. --shader
# measures one, voiceorb or plasma.
# Calibration measures N passes, 1 by default, in one sandbox and derives
# each shader's ceilings as twice its highest reading over every pass and
# scale, written as that shader's record in FILE beside the others.
# Each CPU, GPU, and presentation stream discards 120 warmup readings and
# keeps 600 samples; a reading is their 90th percentile. GPU timestamps
# keep compositor pacing out of GPU cost.
# A scene the host's configure moved off the held mode runs again, a
# bounded number of times, and each scene line records the host's CPU
# pressure.
# Vulkan is required for device identity and timestamps. QSG_NO_VSYNC=1
# requests swap interval 0; Wayland can still pace frameSwapped callbacks.
# Exit 77: missing dependency, uncalibrated/software device, or sandbox fault.
# Exit 1: missing samples, failed scene, ceiling exceeded, or accepted control.
# The result names the machine, UTC date, backend, GPU, and separate readings.
set -euo pipefail
self="$(readlink -f -- "${BASH_SOURCE[0]}")" || exit 1
repo="$(cd -- "$(dirname -- "$self")/.." && pwd -P)" || exit 1
choice=(--check "$repo/scripts/shader/ceilings.json")
keep=false
runs=""
shaders=(voiceorb plasma)
argv=("$@")
while (($#)); do
  case "$1" in
    --calibrate)
      [[ $# -ge 2 ]] || { echo 'shader-cost: refused argument=--calibrate'; exit 2; }
      choice=(--calibrate "$2"); shift 2 ;;
    --runs)
      [[ $# -ge 2 && $2 =~ ^[1-9][0-9]*$ ]] || { printf 'shader-cost: refused argument=--runs value=%s\n' "${2:-}"; exit 2; }
      runs="$2"; shift 2 ;;
    --shader)
      [[ $# -ge 2 && ( $2 == voiceorb || $2 == plasma ) ]] || { printf 'shader-cost: refused argument=--shader value=%s\n' "${2:-}"; exit 2; }
      shaders=("$2"); shift 2 ;;
    --keep) keep=true; shift ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$self"; exit 0 ;;
    *) printf 'shader-cost: refused argument=%s\n' "$1"; exit 2 ;;
  esac
done
# Check mode judges one pass against the committed record.
if [[ -n $runs && ${choice[0]} != --calibrate ]]; then
  echo 'shader-cost: refused argument=--runs without=--calibrate'; exit 2
fi
runs="${runs:-1}"
# No process this run starts may open an amdgpu node, so the run goes on
# only where none is visible: scripts/smoke/gpu-fence.sh.
"$repo/scripts/smoke/gpu-fence.sh" --check || exec "$repo/scripts/smoke/gpu-fence.sh" "$self" "${argv[@]}"
source_repo="$repo"
if ! mkdir -p -- "$source_repo/tmp"; then
  printf 'shader-cost: failed scratch=%s\n' "$source_repo/tmp"; exit 1
fi
export TMPDIR="$source_repo/tmp"
# The compiler owner has a hyphenated filename; import through its path.
compiler="$(python3 - "$repo/scripts/check-voiceorb-shader.py" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("shader", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print(module.qsb_tool() or "")
print(*module.OPTIONS, sep="\n")
PY
)" || exit 1
mapfile -t compiler_words <<<"$compiler"
[[ -n ${compiler_words[0]} ]] || { echo 'shader-cost: status=not-measured missing=qsb'; exit 77; }
timeout_s=90
plugin_set=smoke
harness_scene_only=true
source "$repo/scripts/smoke/harness.sh"
cp -- "$source_repo/scripts/shader/Scene.qml" "$repo/shell/ShaderScene.qml"
# Each shader's costly copy adds a 256-step dependent loop before its
# output, each step made of that shader's own work: VoiceOrb's trigonometry,
# and two of the plasma's four-octave noises. On host cachy on 2026-10-05
# the trigonometric loop added 0.026 ms of GPU cost to the plasma's
# 0.127 ms at scale 1, under the plasma's 0.548 ms ceiling (run
# shader-cost-1791193446-3856419), and one noise a step read 0.642 ms
# against a 0.513 ms ceiling (run shader-cost-1791193734-224301).
for shader in "${shaders[@]}"; do
  python3 - "$shader" "$repo" "$sandbox/costly-$shader.frag" <<'PY'
from pathlib import Path
import sys
shader, repo, output = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
source, needle, seed, step, scaled = {
    "voiceorb": ("shell/Ui/feedback/shaders/voiceorb.frag",
                 "fragColor = ink * max(ring, arcs) * qt_Opacity;", "angle + phase",
                 "sin(cost * 1.31 + float(i)) + cos(cost * 0.73 + radius) + atan(cost, 0.71)",
                 "fragColor = ink * max(ring, arcs) * qt_Opacity * (0.99 + 0.01 * sin(cost));"),
    "plasma": ("shell/plugins/vgs.voice/shaders/plasma.frag",
               "fragColor = vec4(outc, clamp(a, 0.0, 1.0)) * qt_Opacity;", "ang + uTime",
               "fbm(vec3(uv * 3.0, cost + float(i) * 0.37)) + fbm(vec3(uv.yx * 2.0, cost - float(i) * 0.21))",
               "fragColor = vec4(outc, clamp(a, 0.0, 1.0)) * qt_Opacity * (0.99 + 0.01 * sin(cost));"),
}[shader]
text = (repo / source).read_text()
assert text.count(needle) == 1, "costly shader: output must match once"
changed = text.replace(needle, f"""
float cost = {seed};
for (int i = 0; i < 256; ++i)
    cost = {step};
{scaled}
""")
assert changed != text
output.write_text(changed)
PY
  if ! env -i PATH=/usr/bin:/bin HOME="$home" LC_ALL=C "${compiler_words[@]}" -o "$repo/shell/costly-$shader.frag.qsb" "$sandbox/costly-$shader.frag"; then
    printf 'shader-cost: failed costly-shader=compile shader=%s\n' "$shader"; exit 1
  fi
done
logs="$source_repo/tmp/shader-cost-$(date +%s)-$$"
mkdir -p -- "$logs"
printf 'shader-cost: logs=%s\n' "$logs"
source "$source_repo/scripts/shader/measure-scene.sh"
output="$(first_name)" || exit 1
mode="$(unscaled_mode_of "$output")" || exit 1
double="$(hidpi_mode_of "$output")" || exit 1
passes=()
for ((run = 1; run <= runs; run++)); do
  pass="$logs/run-$run"
  mkdir -p -- "$pass"
  passes+=("$pass")
  for scale in 1 2; do
    target_mode="$mode"
    [[ $scale == 1 ]] || target_mode="$double"
    hold_mode "shader scale $scale" "$output" "$target_mode" "$scale"
    [[ ${#mode_hold[@]} -gt 0 ]] || { echo 'shader-cost: failed output=not-held'; exit 1; }
    for shader in "${shaders[@]}"; do
      mkdir -p -- "$pass/$shader"
      for scene in off on costly; do
        measure_held_scene "$scale" "$scene" "$pass/$shader/scale-$scale-$scene"
      done
    done
    release_mode "release shader scale $scale" "$output" "$mode" 1
    [[ $failures -eq 0 ]] || { echo 'shader-cost: failed output=release'; exit 1; }
  done
done
# Every shader is judged; a failure outranks a shader that could not be
# measured.
verdict=0
for shader in "${shaders[@]}"; do
  status=0
  python3 "$source_repo/scripts/shader/readings.py" "${passes[@]/%//$shader}" --shader "$shader" "${choice[@]}" || status=$?
  if [[ $status -ne 0 && ( $verdict -eq 0 || $verdict -eq 77 ) ]]; then verdict=$status; fi
done
exit "$verdict"
