# Sourced by scripts/measure-shader.sh after scripts/smoke/harness.sh and
# scripts/smoke/verdict.sh; measures one scene of the shader instrument
# under the nested output's held mode. It reads the harness's sandbox, its
# spawn and its process-group leases, the hold's readers, and the runner's
# `shader`, the shader the scene draws, with `orb_style` and `orb_reduced`,
# the orb style and look a jarvis-orb scene draws (empty and 0 for any other
# scene).

# measure_scene SCALE SCENE STEM: one standalone layer, VGS_SHADER_MODE
# SCENE (null repeats off), VGS_SHADER_NAME shader, VGS_ORB_STYLE orb_style
# and VGS_ORB_REDUCED orb_reduced, until its result reads complete or
# timeout_s passes. Writes STEM.launch.log, STEM.log and STEM.json for
# the layer. Records the window's world pressure in STEM.cpu, mean GPU
# utilization (rounded half up) in STEM.gpu, and peak in STEM.gpu-peak,
# from the raw 500 ms samples in STEM.gpu-samples. Sets scene_cpu_some_pct,
# scene_gpu_pct, scene_gpu_peak_pct and scene_{start,end}_ms (UTC epoch).
# STEM.gpu-clock and scene_gpu_clock hold the SM min/median/max, memory
# min/max, P-state set and clock sample count, or unmeasured.
# STEM.gpu-foreign and scene_gpu_foreign_pct hold the rounded mean of the
# outer pmon records completed within the window, or unmeasured. The
# foreign GPU peers are a JSON array in STEM.gpu-foreign-peers and
# scene_gpu_foreign_peers.
# Stops and reaps the sampler before tearing down the layer and ending its
# process group's lease. Returns 1 on a failed or incomplete scene.
measure_scene() {
  local scale="$1" scene="$2" stem="$3" scene_pid result done=false instance scene_exit=0 start_us end_us poll group remaining=()
  local gpu_pid gpu_stop foreign spawn_status=0
  start_us="$(cpu_some_us)"
  scene_start_ms="$(now_ms)"
  # NVIDIA's query loop reports device-wide utilization, not layer cost:
  # https://docs.nvidia.com/deploy/nvidia-smi/ (Selective Query Options).
  # The coprocess's input closes even if the runner exits. Its sole child
  # is bound by pidfd and joined before the caller reads the samples.
  coproc shader_gpu {
    exec python3 -c '
import os
from pathlib import Path
import re
import signal
from statistics import median
import subprocess
import sys

stem = sys.argv[1]
raw = Path(f"{stem}.gpu-samples")
mean = peak = clock = "unmeasured"
try:
    with raw.open("wb") as samples:
        sampler = subprocess.Popen(
            ["stdbuf", "-oL", "nvidia-smi", "--query-gpu=utilization.gpu,clocks.sm,clocks.mem,pstate",
             "--format=csv,noheader,nounits", "-lms", "500"],
            stdin=subprocess.DEVNULL, stdout=samples)
    try:
        fd = os.pidfd_open(sampler.pid)
    except OSError:
        # This process is the only waiter; the unreaped child still owns
        # its pid even if pidfd acquisition fails.
        sampler.kill()
        sampler.wait()
        raise
    try:
        try:
            sys.stdin.buffer.read()
        finally:
            try:
                signal.pidfd_send_signal(fd, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                status = sampler.wait(timeout=1)
            except subprocess.TimeoutExpired:
                try:
                    signal.pidfd_send_signal(fd, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                sampler.wait()
                status = None
    finally:
        os.close(fd)
    if status in (0, -signal.SIGTERM):
        rows = [line.split(b",", 1) for line in raw.read_bytes().splitlines()]
        utilization = [row[0].strip() for row in rows]
        if utilization and all(re.fullmatch(rb"[0-9]{1,3}", value) and int(value) <= 100
                               for value in utilization):
            values = list(map(int, utilization))
            count = len(values)
            # Add half before truncating, without floating-point ties.
            mean = (2 * sum(values) + count) // (2 * count)
            peak = max(values)
        clocks = [match.groups() for row in rows if len(row) == 2 and
                  (match := re.fullmatch(rb"\s*([1-9][0-9]*)\s*,\s*([1-9][0-9]*)\s*,\s*(P[0-9]+)\s*", row[1]))]
        if clocks:
            sm, memory, states = zip(*clocks)
            sm, memory = list(map(int, sm)), list(map(int, memory))
            pstates = b",".join(sorted(set(states))).decode("ascii")
            clock = (f"clock_sm={min(sm)}/{median(sm):g}/{max(sm)} "
                     f"clock_mem={min(memory)}/{max(memory)} pstates={pstates} clock_samples={len(clocks)}")
except OSError as error:
    print(error, file=sys.stderr)
    # Keep the control pipe open until the caller closes its end.
    sys.stdin.buffer.read()
Path(f"{stem}.gpu-peak").write_text(f"{peak}\n")
Path(f"{stem}.gpu-clock").write_text(f"{clock}\n")
print(mean)
' "$stem" >"$stem.gpu" 2>"$stem.gpu.log"
  }
  gpu_pid=$! gpu_stop="${shader_gpu[1]:-}"
  spawn_display "$stem.launch.log" "${shell_env[@]}" "${bundled_fonts[@]}" VGS_SHADER_MODE="${scene/null/off}" VGS_SHADER_NAME="$shader" \
    VGS_ORB_STYLE="$orb_style" VGS_ORB_REDUCED="$orb_reduced" \
    QSG_RHI_BACKEND=vulkan QSG_RHI_PROFILE=1 QSG_NO_VSYNC=1 \
    QT_LOGGING_RULES='qt.scenegraph.time.renderloop.debug=true;qt.scenegraph.general=true;qt.rhi.general=true' \
    -- qs -p "$repo/shell/ShaderScene.qml" || spawn_status=1
  if ((spawn_status == 0)); then
    scene_pid="$spawn_pid"
    result=""
    for ((poll=0; poll<timeout_s*5; poll++)); do
      kill -0 "$scene_pid" 2>/dev/null || break
      if result="$("${shell_env[@]}" qs ipc --pid "$scene_pid" call shader result 2>/dev/null)" \
        && [[ $result == *'"complete":true'* ]]; then done=true; break; fi
      sleep 0.2
    done
  fi
  end_us="$(cpu_some_us)"
  scene_end_ms="$(now_ms)"
  if [[ -n $gpu_stop && -n ${shader_gpu[1]:-} ]]; then exec {gpu_stop}>&-; fi
  if ! wait "$gpu_pid" || ! IFS= read -r scene_gpu_pct <"$stem.gpu" \
    || ! IFS= read -r scene_gpu_peak_pct <"$stem.gpu-peak"; then
    scene_gpu_pct=unmeasured scene_gpu_peak_pct=unmeasured
    printf '%s\n' "$scene_gpu_pct" >"$stem.gpu" || return 1
    printf '%s\n' "$scene_gpu_peak_pct" >"$stem.gpu-peak" || return 1
  fi
  if ! IFS= read -r scene_gpu_clock 2>/dev/null <"$stem.gpu-clock"; then
    scene_gpu_clock=unmeasured
    printf '%s\n' "$scene_gpu_clock" >"$stem.gpu-clock" || return 1
  fi
  ((spawn_status == 0)) || return 1
  scene_cpu_some_pct="$(cpu_some_pct "$start_us" "$end_us" "$((scene_end_ms - scene_start_ms))")" || return 1
  printf '%s\n' "$scene_cpu_some_pct" >"$stem.cpu" || return 1
  scene_gpu_foreign_pct=unmeasured scene_gpu_foreign_peers='[]'
  if [[ -n ${VGS_SHADER_GPU_PROCESSES:-} ]] \
    && foreign="$(python3 "$source_repo/scripts/shader/gpu-processes.py" window \
      "$VGS_SHADER_GPU_PROCESSES" "$scene_start_ms" "$scene_end_ms")"; then
    scene_gpu_foreign_pct="${foreign%%$'\n'*}"
    scene_gpu_foreign_peers="${foreign#*$'\n'}"
  fi
  printf '%s\n' "$scene_gpu_foreign_pct" >"$stem.gpu-foreign" || return 1
  printf '%s\n' "$scene_gpu_foreign_peers" >"$stem.gpu-foreign-peers" || return 1
  # Read the flushed instance log by the scene's own pid, not its stdout.
  # The listing answers none or unlisted when no instance names the pid.
  if ! instance="$(qs_list --all | py_reply 'import json,sys; print(next((i["id"] for i in json.load(sys.stdin) if i["pid"] == int(sys.argv[1])), "unlisted"))' "$scene_pid")" \
    || [[ $instance == none || $instance == unlisted ]]; then
    echo "shader-cost: failed scene=$scene scale=$scale instance=${instance:-unreadable}"; cat -- "$stem.launch.log"; return 1;
  fi
  cp -- "$rt_dir/quickshell/by-id/$instance/log.log" "$stem.log" || return 1
  printf '%s\n' "$result" >"$stem.json" || return 1
  kill -TERM "$scene_pid" || return 1
  wait "$scene_pid" || scene_exit=$?
  # Reaping ends this process group's lease; teardown must not retain a
  # pid that the kernel can give to an unrelated process during later runs.
  for group in "${pgids[@]}"; do
    [[ $group == "$scene_pid" ]] || remaining+=("$group")
  done
  pgids=("${remaining[@]}")
  [[ $scene_exit == 0 || $scene_exit == 143 ]] || {
    printf 'shader-cost: failed scene=%s scale=%s exit=%s\n' "$scene" "$scale" "$scene_exit"; return 1;
  }
  [[ $done == true ]] || { echo "shader-cost: failed scene=$scene scale=$scale samples=incomplete"; return 1; }
}

# measure_held_scene SCALE SCENE STEM: measure_scene under the held mode.
# The scene applies no monitor rule, so a scene after which the output
# still reads the held mode ran under it from start to end. One after
# which the output reads another mode, or cannot be read, fails with
# `shader-cost: failed output=<state> scene=<scene> scale=<n> got=[<reading>]`.
measure_held_scene() {
  local scale="$1" scene="$2" stem="$3" state got
  measure_scene "$scale" "$scene" "$stem" || return 1
  state="$(held_mode_state)" || state=unreadable
  if [[ $state != held ]]; then
    got="$(mode_scale_of "${mode_hold[0]}")" || got=unreadable
    printf 'shader-cost: failed output=%s scene=%s scale=%s got=[%s]\n' "$state" "$scene" "$scale" "$got"
    return 1
  fi
  printf 'shader-cost: scene=%s scale=%s samples=600 cpu_some_pct=%s gpu_foreign_pct=%s gpu_foreign_peers=%s gpu_pct=%s gpu_peak_pct=%s %s start_ms=%s end_ms=%s log=%s\n' \
    "$scene" "$scale" "$scene_cpu_some_pct" "$scene_gpu_foreign_pct" "$scene_gpu_foreign_peers" "$scene_gpu_pct" "$scene_gpu_peak_pct" \
    "${scene_gpu_clock/#unmeasured/clock=unmeasured}" "$scene_start_ms" "$scene_end_ms" "$stem.log"
}
