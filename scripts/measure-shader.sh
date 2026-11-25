#!/usr/bin/env bash
# Measure each passive shader layer on a real GPU in the nested sandbox:
# VoiceOrb, Voice's plasma orb, Jarvis's orb in each style of its Orb
# style setting and in the reduced look of the setting's default style,
# the shared RadialBackdrop as the disc behind Voice's plasma orb, and
# GlassSurface's lens as the largest plate of Jarvis's overlay.
# Usage: scripts/measure-shader.sh [--shader NAME] [--calibrate FILE [--runs N]] [--keep]
# Default: check every shader against its record in
# scripts/shader/ceilings.json and prove its 256-step control. --shader
# measures one, voiceorb, plasma, jarvis-orb-STYLE for each option of the
# Jarvis manifest's Orb style setting, jarvis-orb-reduced, radial-backdrop
# or glass-lens. --shader launcher or --shader notification-stack measures
# the whole glass, flat form and edge light, of the launcher's card or of
# a stack of notification cards, in its off and on scenes alone, and
# prints the readings with no ceiling, costly control or calibration.
# Calibration measures N passes, 1 by default, in one sandbox and derives
# each shader's ceilings as twice its highest reading over every pass and
# scale, floored at each stream's instrument resolution and the measured
# GPU spread of identical off/null scenes. FILE records each pass's readings
# and each scene's CPU pressure, foreign GPU load, device-wide mean and
# peak GPU utilization, and retake flag. Start outside the world to sample
# host process cgroups and name the GPU peers in each window.
# Each CPU, GPU, and presentation stream discards 120 warmup readings and
# keeps 600 samples; a reading is their 90th percentile. GPU timestamps
# keep compositor pacing out of GPU cost.
# A scene after which the output no longer reads the held mode fails.
# The quiet-host hold covers the fresh 1 s gate and scene. The scene line
# records UTC epoch start/end in ms, world CPU pressure, mean foreign GPU
# load, GPU peers, device-wide mean and peak, and GPU clocks. If the hold
# wait reaches VGS_SMOKE_IDLE_SECS (default 600), the window runs without
# the hold and logs hold=none.
# Vulkan is required for device identity and timestamps. QSG_NO_VSYNC=1
# requests swap interval 0; Wayland can still pace frameSwapped callbacks.
# In check mode an over-limit or unread gate ends a partial run. In either
# mode the compilation gate can stop the run. Both modes retake a scene
# once if mean foreign GPU load exceeds its limit or is unread, or if its
# clock record is unread, its P-state or memory clock changes within the
# window, or either differs from its off scene's. The core (SM) boost
# clock moves within one P-state: each scene's load record keeps its
# min/median/max as evidence, not as a gate.
# Calibration also retakes for CPU load and refuses a ceiling after a
# second loaded attempt.
# Check mode reports an over-ceiling GPU cost as not measured if its on or
# off scene remains loaded by foreign GPU use or clocks. Within-ceiling
# costs and costly controls retain their verdicts. Only the on scene's
# pressure qualifies CPU readings.
# A failure outranks not-measured results.
# Exit 77: missing dependency or smoke hold files, uncalibrated/software
# device, unread or loaded window as judged above, or sandbox fault.
# Exit 1: missing samples, failed scene, ceiling exceeded, or accepted control.
# The result names the machine, UTC date, backend, GPU, and separate readings.
# loads: shell/costly-*.frag.qsb -- the measurement compiles the shader the caller names
set -euo pipefail
self="$(readlink -f -- "${BASH_SOURCE[0]}")" || exit 1
repo="$(cd -- "$(dirname -- "$self")/.." && pwd -P)" || exit 1
choice=(--check "$repo/scripts/shader/ceilings.json")
keep=false
runs=""
# shader_judge JUDGE ASK: what scripts/check-voiceorb-shader.py at JUDGE
# owns, one word a line: `compiler`, its qsb path (empty when absent) and
# options; `orb-styles`, the Jarvis manifest's default orb style and then
# each style. A refused orb style list prints its key and fails. The
# judge's filename is hyphenated, so it is imported through its path.
shader_judge() {
  python3 - "$1" "$2" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("shader", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
if sys.argv[2] == "compiler":
    print(module.qsb_tool() or "")
    print(*module.OPTIONS, sep="\n")
else:
    try:
        default, styles = module.orb_styles()
    except module.OrbStylesRefused as error:
        print(f"shader-cost: failed {error}")
        sys.exit(1)
    print(default, *styles, sep="\n")
PY
}
orb="$(shader_judge "$repo/scripts/check-voiceorb-shader.py" orb-styles)" || { printf '%s\n' "$orb"; exit 1; }
mapfile -t orb_styles <<<"$orb"
orb_default="${orb_styles[0]}"
orb_styles=("${orb_styles[@]:1}")
# Every scene Scene.qml draws; --shader names one of them.
scenes=(voiceorb plasma "${orb_styles[@]/#/jarvis-orb-}" jarvis-orb-reduced radial-backdrop glass-lens)
# orb_scene SHADER: sets orb_style and orb_reduced, which
# scripts/shader/measure-scene.sh hands the scene: the style a
# jarvis-orb-STYLE scene names, the default style in the reduced look for
# jarvis-orb-reduced, and no style for any other scene.
orb_scene() {
  orb_style="" orb_reduced=0
  case "$1" in
    jarvis-orb-reduced) orb_style="$orb_default" orb_reduced=1 ;;
    jarvis-orb-*) orb_style="${1#jarvis-orb-}" ;;
  esac
}
# Scenes measured for their readings alone, which only --shader names.
reported=(launcher notification-stack)
shaders=("${scenes[@]}")
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
      known=false
      for scene in "${scenes[@]}" "${reported[@]}"; do [[ $# -ge 2 && $2 == "$scene" ]] && known=true; done
      [[ $known == true ]] || { printf 'shader-cost: refused argument=--shader value=%s\n' "${2:-}"; exit 2; }
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
measure_modes=(off on costly)
[[ ${choice[0]} != --calibrate ]] || measure_modes=(off null on costly)
# The shaders whose costly copy the run builds.
costly=("${shaders[@]}")
for scene in "${reported[@]}"; do
  [[ ${shaders[0]} == "$scene" ]] || continue
  [[ ${choice[0]} != --calibrate ]] || { printf 'shader-cost: refused argument=--calibrate shader=%s\n' "$scene"; exit 2; }
  choice=(--report) measure_modes=(off on) costly=()
done
# The overseer's VGS-2619 ruling bounds GPU use by other processes, not the
# runner's own launch, pipeline creation or costly control.
shader_gpu_busy_limit=5
# No process this run starts may open an amdgpu node, so the run goes on
# only where none is visible: scripts/smoke/gpu-fence.sh.
world_args=(--out "$repo/tmp/shader-cost" --out "$repo/tmp/display-record" --out "$repo/tmp/qml-smoke")
[[ $keep != true ]] || world_args+=(--keep)
if [[ ${choice[0]} == --calibrate ]]; then
  calibration="$(realpath -m -- "${choice[1]}")"
  world_args+=(--out "${calibration%/*}")
fi
in_world=true
"$repo/scripts/smoke/gpu-fence.sh" --check || in_world=false
if ! smoke_hold_dir="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || [[ ! -d $smoke_hold_dir ]]; then
  printf 'shader-cost: status=not-measured missing=smoke-hold cause=git-common-dir-unread repo=%s\n' "$repo" >&2
  exit 77
fi
# As in qml-smoke.sh, create the shared files only before world entry.
# Noclobber lets concurrent drivers agree on the same inode (D112).
for lock in "$smoke_hold_dir/vgs-smoke-hold" "$smoke_hold_dir/vgs-smoke-turn"; do
  [[ ! -f $lock ]] || continue
  if [[ $in_world == true ]]; then
    printf 'shader-cost: status=not-measured missing=smoke-hold cause=lock-file-absent path=%s\n' "$lock" >&2
    exit 77
  fi
  if ! (set -C; : >"$lock") 2>/dev/null && [[ ! -f $lock ]]; then
    printf 'shader-cost: status=not-measured missing=smoke-hold cause=create-failed path=%s\n' "$lock" >&2
    exit 77
  fi
done
qml_smoke_idle_secs="${VGS_SMOKE_IDLE_SECS:-600}"
if [[ ! $qml_smoke_idle_secs =~ ^[1-9][0-9]*$ ]]; then
  printf 'shader-cost: refused VGS_SMOKE_IDLE_SECS=%s want=positive-seconds\n' "$qml_smoke_idle_secs" >&2
  exit 2
fi
if [[ $in_world == false ]]; then
  # Carry the explicit wait bound and host trace through the world boundary.
  world_cmd=("$self" "${argv[@]}")
  if [[ -v VGS_SMOKE_IDLE_SECS ]]; then
    world_cmd=(env "VGS_SMOKE_IDLE_SECS=$qml_smoke_idle_secs" "${world_cmd[@]}")
  fi
  exec python3 "$repo/scripts/shader/gpu-processes.py" run "$repo/tmp/shader-cost" \
    "$repo/scripts/smoke/gpu-fence.sh" "${world_args[@]}" -- "${world_cmd[@]}"
fi
source_repo="$repo"
timeout_s=90
plugin_set=smoke
harness_scene_only=true
source "$repo/scripts/smoke/harness.sh"
# The preceding costly scene can leave avg10 high after its process ends.
# Sample a fresh window after teardown instead of judging that history.
# The scene's own window still judges its CPU readings.
shader_pressure_gate() {
  local scene="$1" pressure start_us start_ms end_us elapsed_ms result
  start_us="$(cpu_some_us)"
  start_ms="$(now_ms)"
  sleep 1
  end_us="$(cpu_some_us)"
  elapsed_ms="$(( $(now_ms) - start_ms ))"
  pressure="$(cpu_some_pct "$start_us" "$end_us" "$elapsed_ms")"
  result="$(latency_pressure_verdict 0 "$pressure" 0)"
  gate_cpu_some_pct="$pressure" gate_result="$result"
  printf 'shader-cost: pressure-gate scene=%s cpu_some_pct=%s window_ms=%s limit=%s result=%s\n' "$scene" "$pressure" "$elapsed_ms" "$latency_pressure_limit" "$result"
  [[ $result == within ]] || {
    [[ $scene != setup && ${choice[0]} == --calibrate ]] && return 0
    printf 'shader-cost: status=not-measured reason=cpu-pressure scene=%s cpu_some_pct=%s window_ms=%s limit=%s result=%s\n' "$scene" "$pressure" "$elapsed_ms" "$latency_pressure_limit" "$result"
    return 77
  }
}
shader_pressure_gate setup
compiler="$(shader_judge "$source_repo/scripts/check-voiceorb-shader.py" compiler)" || exit 1
mapfile -t compiler_words <<<"$compiler"
[[ -n ${compiler_words[0]} ]] || { echo 'shader-cost: status=not-measured missing=qsb'; exit 77; }
cp -- "$source_repo/scripts/shader/Scene.qml" "$repo/shell/ShaderScene.qml"
# Each shader's costly copy adds a 256-step dependent loop before its
# output, each step made of that shader's own work: VoiceOrb's,
# RadialBackdrop's and the lens's trigonometry,
# two of the plasma's four-octave noises, and three of orb.glsl's value
# noises in every orb style. On the orb's one shader before its styles,
# at its 255 px canvas, two noises read 0.1573 ms at scale 1 against the
# 0.1572 ms ceiling twice its scale-2 reading sets (run
# 1793675342-2/run-3, cachy, 2026-11-03). On host cachy on 2026-10-05
# the trigonometric loop added 0.026 ms of GPU cost to the plasma's
# 0.127 ms at scale 1, under the plasma's 0.548 ms ceiling (run
# shader-cost-1791193446-3856419), and one noise a step read 0.642 ms
# against a 0.513 ms ceiling (run shader-cost-1791193734-224301).
# Every orb style includes orb.glsl, which qsb resolves beside the
# including source, so it goes beside the costly copies.
cp -- "$repo/shell/plugins/vgs.jarvis/shaders/orb.glsl" "$sandbox/orb.glsl"
for shader in "${costly[@]}"; do
  orb_scene "$shader"
  python3 - "$shader" "$repo" "$sandbox/costly-$shader.frag" "$orb_style" <<'PY'
from pathlib import Path
import sys
shader, repo, output, orb_style = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4]
costly = {
    "voiceorb": ("shell/Ui/feedback/shaders/voiceorb.frag",
                 "fragColor = ink * max(ring, arcs) * qt_Opacity;", "angle + phase",
                 "sin(cost * 1.31 + float(i)) + cos(cost * 0.73 + radius) + atan(cost, 0.71)",
                 "fragColor = ink * max(ring, arcs) * qt_Opacity * (0.99 + 0.01 * sin(cost));"),
    "plasma": ("shell/plugins/vgs.voice/shaders/plasma.frag",
               "fragColor = vec4(outc, clamp(a, 0.0, 1.0)) * qt_Opacity;", "ang + uTime",
               "fbm(vec3(uv * 3.0, cost + float(i) * 0.37)) + fbm(vec3(uv.yx * 2.0, cost - float(i) * 0.21))",
               "fragColor = vec4(outc, clamp(a, 0.0, 1.0)) * qt_Opacity * (0.99 + 0.01 * sin(cost));"),
    "radial-backdrop": ("shell/Ui/feedback/shaders/radialbackdrop.frag",
                        "fragColor = vec4(rgb, a) * qt_Opacity;", "p.x * 0.01 + uJoin.x",
                        "sin(cost * 1.31 + float(i)) + cos(cost * 0.73 + p.y * 0.01) + atan(cost, 0.71)",
                        "fragColor = vec4(rgb, a) * qt_Opacity * (0.99 + 0.01 * sin(cost));"),
    "glass-lens": ("shell/Ui/foundation/shaders/glasslens.frag",
                   "fragColor = (vec4(colour, alpha) * cover + vec4(0.0, 0.0, 0.0, outer)) * qt_Opacity;", "p.x * 0.01 + uRadius",
                   "sin(cost * 1.31 + float(i)) + cos(cost * 0.73 + p.y * 0.01) + atan(cost, 0.71)",
                   "fragColor = (vec4(colour, alpha) * cover + vec4(0.0, 0.0, 0.0, outer)) * qt_Opacity * (0.99 + 0.01 * sin(cost));"),
}
if orb_style:
    # Each style's shader ends main with its one output line, with uv, r,
    # uFlow and orb.glsl's vnoise in scope.
    source = f"shell/plugins/vgs.jarvis/shaders/{orb_style}.frag"
    outputs = [line.strip() for line in (repo / source).read_text().splitlines()
               if line.strip().startswith("fragColor = ")]
    assert len(outputs) == 1, "costly shader: one output line"
    costly[shader] = (source, outputs[0], "r + uFlow",
                      "vnoise(vec3(uv * 3.0, cost + float(i) * 0.37)) + vnoise(vec3(uv.yx * 2.0, cost - float(i) * 0.21)) + vnoise(vec3(uv * 5.0, cost * 0.5 + float(i) * 0.13))",
                      outputs[0].removesuffix(";") + " * (0.99 + 0.01 * sin(cost));")
source, needle, seed, step, scaled = costly[shader]
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
logs="$source_repo/tmp/shader-cost/$(date +%s)-$$"
mkdir -p -- "$logs"
printf 'shader-cost: logs=%s\n' "$logs"
source "$source_repo/scripts/shader/measure-scene.sh"
# Each attempt acquires its own quiet-host window. Even in check mode,
# release the hold and print its evidence if the fresh gate refuses.
shader_window() {
  local scale="$1" scene="$2" stem="$3" label="$4" status=0
  smoke_hold_begin shader-cost "$label"
  if ((failures)); then
    status=1
  elif shader_pressure_gate "$label"; then
    measure_held_scene "$scale" "$scene" "$stem" || status=$?
  else
    status=$?
  fi
  smoke_hold_end
  return "$status"
}
# A window is steady while it holds one P-state and one memory clock, and
# differs where either is not its off scene's. The owner's delegate's
# 2026-11-23 ruling refuses a P-state drop but lets the SM boost clock
# range within one P-state, so no SM figure is judged.
shader_clock_state() {
  local stem="$1" off="$2" record mem states
  local pattern='^clock_sm=[1-9][0-9]*/[1-9][0-9]*([.]5)?/[1-9][0-9]* clock_mem=([1-9][0-9]*)/([1-9][0-9]*) pstates=(P[0-9]+(,P[0-9]+)*) clock_samples=[1-9][0-9]*$'
  if ! IFS= read -r record 2>/dev/null <"$stem.gpu-clock" || [[ ! $record =~ $pattern ]]; then
    echo unmeasured; return
  fi
  mem="${BASH_REMATCH[2]}" states="${BASH_REMATCH[4]}"
  if [[ $states == *,* || $mem != "${BASH_REMATCH[3]}" ]]; then
    echo changed; return
  fi
  if [[ $stem != "$off" ]]; then
    if ! IFS= read -r record 2>/dev/null <"$off.gpu-clock" || [[ ! $record =~ $pattern ]]; then
      echo unmeasured; return
    fi
    if [[ $states != "${BASH_REMATCH[4]}" || $mem != "${BASH_REMATCH[2]}" || $mem != "${BASH_REMATCH[3]}" ]]; then
      echo differs; return
    fi
  fi
  echo steady
}
shader_attempts() {
  local scale="$1" scene="$2" stem="$3" label="${3#"$logs"/}"
  # Off runs first, so every pair reads the final off record, not its archive.
  local off="${3%/*}/scale-$1-off" attempt action evidence cpu_quiet clock_state clock_sm record retaken=false
  for attempt in 1 2; do
    shader_window "$scale" "$scene" "$stem" "$label"
    clock_state="$(shader_clock_state "$stem" "$off")"
    clock_sm=unmeasured
    if IFS= read -r record 2>/dev/null <"$stem.gpu-clock" && [[ $record =~ ^clock_sm=([^ ]+)\  ]]; then
      clock_sm="${BASH_REMATCH[1]}"
    fi
    cpu_quiet=true
    if [[ ${choice[0]} == --calibrate ]]; then
      if [[ $gate_result != within || $(latency_pressure_verdict 0 "$scene_cpu_some_pct" 0) != within ]]; then
        cpu_quiet=false
      fi
    fi
    if [[ $cpu_quiet == true && $scene_gpu_foreign_pct != unmeasured && $clock_state == steady ]] \
      && ((scene_gpu_foreign_pct <= shader_gpu_busy_limit)); then
      printf 'quiet cpu=%s gpu_foreign=%s gpu=%s gpu_peak=%s clock_sm=%s clock=%s retaken=%s\n' \
        "$scene_cpu_some_pct" "$scene_gpu_foreign_pct" "$scene_gpu_pct" "$scene_gpu_peak_pct" "$clock_sm" "$clock_state" "$retaken" >"$stem.load"
      return 0
    fi
    printf 'loaded cpu=%s gpu_foreign=%s gpu=%s gpu_peak=%s clock_sm=%s clock=%s\n' \
      "$scene_cpu_some_pct" "$scene_gpu_foreign_pct" "$scene_gpu_pct" "$scene_gpu_peak_pct" "$clock_sm" "$clock_state" >"$stem.load"
    action=retake
    [[ $attempt == 1 ]] || action=none
    printf 'shader-cost: loaded scene=%s attempt=%s cpu_some_pct=%s gpu_foreign_pct=%s gpu_pct=%s gpu_peak_pct=%s gate_cpu_some_pct=%s cpu_limit=%s gpu_limit=%s clock=%s accepted=false action=%s\n' \
      "$label" "$attempt" "$scene_cpu_some_pct" "$scene_gpu_foreign_pct" "$scene_gpu_pct" "$scene_gpu_peak_pct" "$gate_cpu_some_pct" \
      "$latency_pressure_limit" "$shader_gpu_busy_limit" "$clock_state" "$action"
    [[ $action == retake ]] || return 0
    for evidence in "$stem".*; do
      mv -- "$evidence" "$stem.loaded.${evidence#"$stem".}"
    done
    retaken=true
  done
}
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
      orb_scene "$shader"
      mkdir -p -- "$pass/$shader"
      for scene in "${measure_modes[@]}"; do
        shader_attempts "$scale" "$scene" "$pass/$shader/scale-$scale-$scene"
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
  python3 "$source_repo/scripts/shader/readings.py" "${passes[@]/%//$shader}" --shader "$shader" "${choice[@]}" --cpu-pressure-limit "$latency_pressure_limit" || status=$?
  if [[ $status -ne 0 && ( $verdict -eq 0 || $verdict -eq 77 ) ]]; then verdict=$status; fi
done
exit "$verdict"
