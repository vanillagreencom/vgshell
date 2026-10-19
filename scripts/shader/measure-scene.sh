# Sourced by scripts/measure-shader.sh after scripts/smoke/harness.sh and
# scripts/smoke/verdict.sh; measures one scene of the shader instrument
# under the nested output's held mode. It reads the harness's sandbox, its
# spawn and its process-group leases, the hold's readers, and the runner's
# `shader`, the shader the scene draws.

# measure_scene SCALE SCENE STEM: one standalone layer, VGS_SHADER_MODE
# SCENE and VGS_SHADER_NAME shader, until its result reads complete or
# timeout_s passes. Writes STEM.launch.log, the instance log as STEM.log,
# the result as STEM.json and cpu_some_pct of the scene's window as
# STEM.cpu, which scripts/shader/readings.py records with a calibration,
# reaps the layer and ends its process group's lease, and sets
# scene_cpu_some_pct to that reading. Exits 1, with the cause, when the layer leaves no
# instance, exits other than by the TERM it is sent, or never completes its
# samples.
measure_scene() {
  local scale="$1" scene="$2" stem="$3" scene_pid result done=false instance scene_exit=0 start_us start_ms poll group remaining=()
  start_us="$(cpu_some_us)"
  start_ms="$(now_ms)"
  spawn_display "$stem.launch.log" "${shell_env[@]}" VGS_SHADER_MODE="$scene" VGS_SHADER_NAME="$shader" \
    QSG_RHI_BACKEND=vulkan QSG_RHI_PROFILE=1 QSG_NO_VSYNC=1 \
    QT_LOGGING_RULES='qt.scenegraph.time.renderloop.debug=true;qt.scenegraph.general=true;qt.rhi.general=true' \
    -- qs -p "$repo/shell/ShaderScene.qml" || return 1
  scene_pid="$spawn_pid"
  result=""
  for ((poll=0; poll<timeout_s*5; poll++)); do
    kill -0 "$scene_pid" 2>/dev/null || break
    if result="$("${shell_env[@]}" qs ipc --pid "$scene_pid" call shader result 2>/dev/null)" \
      && [[ $result == *'"complete":true'* ]]; then done=true; break; fi
    sleep 0.2
  done
  scene_cpu_some_pct="$(cpu_some_pct "$start_us" "$(cpu_some_us)" "$(( $(now_ms) - start_ms ))")"
  printf '%s\n' "$scene_cpu_some_pct" >"$stem.cpu"
  # Read the flushed instance log by the scene's own pid, not its stdout.
  # The listing answers none or unlisted when no instance names the pid.
  if ! instance="$(qs_list --all | py_reply 'import json,sys; print(next((i["id"] for i in json.load(sys.stdin) if i["pid"] == int(sys.argv[1])), "unlisted"))' "$scene_pid")" \
    || [[ $instance == none || $instance == unlisted ]]; then
    echo "shader-cost: failed scene=$scene scale=$scale instance=${instance:-unreadable}"; cat -- "$stem.launch.log"; exit 1;
  fi
  cp -- "$rt_dir/quickshell/by-id/$instance/log.log" "$stem.log"
  printf '%s\n' "$result" >"$stem.json"
  kill -TERM "$scene_pid"
  wait "$scene_pid" || scene_exit=$?
  # Reaping ends this process group's lease; teardown must not retain a
  # pid that the kernel can give to an unrelated process during later runs.
  for group in "${pgids[@]}"; do
    [[ $group == "$scene_pid" ]] || remaining+=("$group")
  done
  pgids=("${remaining[@]}")
  [[ $scene_exit == 0 || $scene_exit == 143 ]] || {
    printf 'shader-cost: failed scene=%s scale=%s exit=%s\n' "$scene" "$scale" "$scene_exit"; exit 1;
  }
  [[ $done == true ]] || { echo "shader-cost: failed scene=$scene scale=$scale samples=incomplete"; exit 1; }
}

# measure_held_scene SCALE SCENE STEM: measure_scene under the held mode.
# The scene applies no monitor rule, so a scene after which the output
# still reads the held mode ran under it from start to end. One after
# which the output reads another mode, or cannot be read, fails with
# `shader-cost: failed output=<state> scene=<scene> scale=<n> got=[<reading>]`.
measure_held_scene() {
  local scale="$1" scene="$2" stem="$3" state got
  measure_scene "$scale" "$scene" "$stem"
  state="$(held_mode_state)"
  if [[ $state != held ]]; then
    got="$(mode_scale_of "${mode_hold[0]}")" || got=unreadable
    printf 'shader-cost: failed output=%s scene=%s scale=%s got=[%s]\n' "$state" "$scene" "$scale" "$got"
    exit 1
  fi
  printf 'shader-cost: scene=%s scale=%s samples=600 cpu_some_pct=%s log=%s\n' "$scene" "$scale" "$scene_cpu_some_pct" "$stem.log"
}
