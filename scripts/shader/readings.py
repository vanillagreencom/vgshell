#!/usr/bin/env python3
"""Read Qt 6.11 threaded-render-loop logs from one standalone layer.

Each directory holds one pass of one shader, the one --shader names; its
record is that shader's entry under `shaders` in the ceilings file.

Qt's window-addressed sync/render log is CPU submission, in integer ms.
QSG_RHI_PROFILE supplies GPU timestamp frame durations, independent of
Wayland frame callback pacing. Presentation is the layer's frameSwapped
interval in the GUI thread, in ms, not time spent executing on the GPU.
Each stream discards 120 warmup readings and retains 600 samples, and
its reading is their nearest-rank 90th percentile, so a few frames a
busy host delays do not set it. The report's GPU cost is paired
on-minus-off GPU frame time, not CPU time or presentation interval.
Calibration reads one directory per pass and an identical off/null pair
that measures the instrument's GPU spread. Each ceiling is twice the highest
shader reading over every pass, floored at the logged resolution and, for
GPU cost, the highest null-pair reading. It writes the shader's record into the
file, keeping every other shader's. Every scene in every calibration pass
needs a quiet .load record; loaded, missing or unreadable records exit 77
without writing that shader's ceiling. Calibration records each accepted
scene's CPU pressure, mean foreign GPU load, device-wide mean and peak
GPU utilization, clock state, and retake flag. Device-wide utilization
is evidence, not part of admission. Check mode judges one directory.
A loaded or unreadable on-scene CPU pressure qualifies only CPU readings.
A GPU exceedance is not measured if its on or off scene remains loaded
by foreign GPU use or clocks after a retake, or lacks load evidence.
A within-ceiling reading keeps its verdict, and costly GPU controls
must exceed the ceiling at any load.
Software devices exit 77; absent samples fail.
"""
import argparse
import json
import math
from pathlib import Path
import re
import socket
from datetime import datetime, timezone
import sys

WARMUP = 120
SAMPLES = 600
# The reading of a stream is its nearest-rank percentile.
PERCENTILE = 90
READINGS = ("cpu_sync_ms", "cpu_render_ms", "gpu_cost_ms", "presentation_ms")
CPU_READINGS = ("cpu_sync_ms", "cpu_render_ms")
CHECK_MODES = ("off", "on", "costly")
CALIBRATION_MODES = ("off", "null", "on", "costly")
# QSGRenderThread::syncAndRender truncates CPU times to integer ms and
# prints GPU timestamps with %.4f ms (Qt 6.11.2 qsgthreadedrenderloop.cpp).
# Scene.qml's Date.now() presentation clock resolves whole ms.
RESOLUTION_MS = dict(zip(READINGS, (1, 1, 0.0001, 1), strict=True))


class Unmeasured(Exception):
    """The run cannot provide measured evidence for every reading."""


def samples(values, name):
    """Refuse an empty or incomplete stream before taking its sample window."""
    if len(values) < WARMUP + SAMPLES:
        raise ValueError(f"samples={name} count={len(values)} need={WARMUP + SAMPLES}")
    result = values[WARMUP:WARMUP + SAMPLES]
    if any(not math.isfinite(v) or v < 0 for v in result):
        raise ValueError(f"samples={name} invalid-value")
    return result


def scene(log, state, scale):
    """Attribute each stream to the layer's actual QQuickWindow."""
    if re.search(r"software (?:adaptation|backend)|backend Software", log, re.I):
        raise Unmeasured("backend=software")
    # Qt's QRhi Vulkan selection log names each enumerated device followed
    # by 'using this physical device' only for the one it selects.
    device = re.search(r"Physical device \d+: '([^']+)'.* type (\d+)\)\n[^\n]*using this physical device", log)
    if device is None:
        raise ValueError("backend=device-unreadable")
    if int(device[2]) == 4:
        raise Unmeasured(f"backend=software device={device[1]}")
    if int(device[2]) not in (1, 2):
        raise Unmeasured(f"backend=non-gpu device={device[1]} type={device[2]}")
    window = re.fullmatch(r"ProxiedWindow\((0x[0-9a-f]+)\)", state["window"])
    if window is None:
        raise ValueError("window=unreadable")
    address = window[1]
    if state["scale"] != scale:
        raise ValueError(f"scale={state['scale']} want={scale}")
    if state["complete"] is not True:
        raise ValueError("scene=incomplete")
    if not re.search(rf"Creating QRhi with backend Vulkan for window {address}\b", log):
        raise ValueError("backend=not-vulkan-for-layer")
    if "Swap interval is 0, attempting to disable vsync when presenting." not in log:
        raise ValueError("swap-interval=unverified")
    lines = [line for line in log.splitlines()
             if "qt.scenegraph.time.renderloop:" in line and f"[window {address}]" in line]
    cpu = [tuple(map(float, match.groups())) for line in lines
           if (match := re.search(r"frame rendered in \d+ms, sync=(\d+), render=(\d+), swap=\d+", line))]
    gpu = [float(match[1]) for line in lines
           if (match := re.search(r"last retrieved GPU frame time was ([0-9.]+) ms", line))]
    return {
        "backend": "Vulkan", "device": device[1], "window": address, "scale": scale,
        "cpu_sync_ms": samples([p[0] for p in cpu], "cpu-sync"),
        "cpu_render_ms": samples([p[1] for p in cpu], "cpu-render"),
        "gpu_frame_ms": samples(gpu, "gpu"),
        "presentation_ms": samples(state["presentation"], "presentation"),
    }


def percentile(values):
    """The nearest-rank PERCENTILE of values: the smallest sample with at
    least PERCENTILE percent of the samples at or below it."""
    ordered = sorted(values)
    rank = -(-len(ordered) * PERCENTILE // 100)
    return ordered[rank - 1]


def reading(on, off, *, resolved=True):
    """Keep submission, GPU delta, and presentation readings separate."""
    if on["device"] != off["device"] or on["backend"] != off["backend"]:
        raise ValueError("baseline=device-mismatch")
    delta = [a - b for a, b in zip(on["gpu_frame_ms"], off["gpu_frame_ms"], strict=True)]
    cost = percentile(delta)
    if cost <= 0 and resolved:
        raise ValueError(f"gpu-cost=not-resolved reading_ms={cost}")
    return {
        "cpu_sync_ms": percentile(on["cpu_sync_ms"]),
        "cpu_render_ms": percentile(on["cpu_render_ms"]),
        "gpu_cost_ms": cost,
        "presentation_ms": percentile(on["presentation_ms"]),
    }


def over_ceiling(reading, ceilings, names=READINGS):
    """Compare instrument ticks, so subtraction residue cannot add a tick."""
    return [name for name in names
            if round(reading[name] / RESOLUTION_MS[name]) > round(ceilings[name] / RESOLUTION_MS[name])]


def measure(root, identity=None, *, calibrating=False):
    """Read one pass's scenes at both scales, each scene's backend and
    device matched to identity when one is given."""
    scenes = {}
    for scale in (1, 2):
        scenes[scale] = {}
        for mode in (CALIBRATION_MODES if calibrating else CHECK_MODES):
            stem = root / f"scale-{scale}-{mode}"
            scenes[scale][mode] = scene(
                stem.with_suffix(".log").read_text(),
                json.loads(stem.with_suffix(".json").read_text()), scale)
            measured = scenes[scale][mode]
            if identity is not None and (
                measured["device"] != identity["device"] or measured["backend"] != identity["backend"]
            ):
                raise Unmeasured(
                    f"calibration=identity-mismatch scale={scale} scene={mode} "
                    f"want=[{identity['backend']}:{identity['device']}] "
                    f"got=[{measured['backend']}:{measured['device']}]")
    return {
        "backend": scenes[1]["on"]["backend"], "device": scenes[1]["on"]["device"],
        "readings": {str(scale): reading(rows["on"], rows["off"]) for scale, rows in scenes.items()},
        "costly_control": {str(scale): reading(rows["costly"], rows["off"]) for scale, rows in scenes.items()},
        "gpu_null_readings_ms": {str(scale): reading(rows["null"], rows["off"], resolved=False)["gpu_cost_ms"]
                                 for scale, rows in scenes.items()} if calibrating else {},
    }


def prove_control(run, ceilings, suffix=""):
    """The costly shader must exceed the GPU ceiling at every scale."""
    for scale, control in run["costly_control"].items():
        # The control proves GPU cost, not a scheduling hiccup on the CPU.
        if not over_ceiling(control, ceilings, ("gpu_cost_ms",)):
            raise ValueError(
                f"costly-control=accepted scale={scale} gpu_cost_ms={control['gpu_cost_ms']} "
                f"ceiling={ceilings['gpu_cost_ms']}{suffix}")


def record(run, ceilings):
    """The fields every result carries, calibration or check."""
    return {
        "machine": socket.gethostname(), "date": datetime.now(timezone.utc).isoformat(),
        "backend": run["backend"], "device": run["device"],
        "warmup": WARMUP, "samples": SAMPLES, "percentile": PERCENTILE,
        "method": f"nearest-rank p{PERCENTILE} of each stream; GPU timestamp frame time on minus off, "
                  "paired by sample; QSG_NO_VSYNC=1",
        "ceilings": ceilings,
    }


def unmeasured_cpu(run, pressure_limit):
    """Only the on scene produces the CPU readings judged by a ceiling."""
    return {scale: f"scale={scale} cpu_some_pct={value} limit={pressure_limit} "
                   + " ".join(f"{name}={run['readings'][scale][name]}" for name in CPU_READINGS)
            for scale, value in run["on_cpu_some_pct"].items()
            if value == "unmeasured" or value > pressure_limit}


def check(root, baseline, pressure_limit):
    """Judge one pass at both scales, and its costly shader, against the
    committed ceilings."""
    run = measure(root, baseline)
    run["on_cpu_some_pct"] = {scale: pressure(root / f"scale-{scale}-on") for scale in run["readings"]}
    ceilings = baseline["ceilings"]
    cpu_unmeasured = unmeasured_cpu(run, pressure_limit)
    gpu_unmeasured = []
    for scale, row in run["readings"].items():
        broken = over_ceiling(row, ceilings)
        if scale in cpu_unmeasured:
            broken = [name for name in broken if name not in CPU_READINGS]
        if "gpu_cost_ms" in broken and (load := paired_gpu_load(root, scale)):
            gpu_unmeasured.append(f"scale={scale} gpu_cost_ms={row['gpu_cost_ms']} "
                                  f"ceiling_gpu_cost_ms={ceilings['gpu_cost_ms']} {load}")
            broken.remove("gpu_cost_ms")
        if broken:
            values = " ".join(f"{name}={row[name]} ceiling_{name}={ceilings[name]}" for name in broken)
            raise ValueError(f"ceiling=exceeded scale={scale} readings={','.join(broken)} "
                             f"{values} cpu_some_pct={run['on_cpu_some_pct'][scale]}")
    prove_control(run, ceilings)
    reasons = []
    if cpu_unmeasured:
        reasons.append("cpu-pressure " + "; ".join(cpu_unmeasured.values()))
    if gpu_unmeasured:
        reasons.append("reason=gpu-load " + "; ".join(gpu_unmeasured))
    if reasons:
        raise Unmeasured("; ".join(reasons))
    return dict(record(run, ceilings), gpu_null_spread_ms=baseline["gpu_null_spread_ms"],
                readings=run["readings"], costly_control=run["costly_control"],
                on_cpu_some_pct=run["on_cpu_some_pct"])


def pressure(stem):
    """Read check mode's on-scene CPU pressure."""
    value = stem.with_suffix(".cpu").read_text().strip()
    if value == "unmeasured":
        return "unmeasured"
    if not re.fullmatch(r"[0-9]+\.[0-9]", value):
        raise ValueError(f"cpu-pressure=unreadable value={value}")
    return float(value)


def evidence(path):
    try:
        return path.read_text().strip()
    except (OSError, UnicodeError):
        return "unmeasured"


def scene_load(stem):
    """Read the runner's final attempt, separate from the archived retake input."""
    state = evidence(stem.with_suffix(".load"))
    cpu_field = r"([0-9]+\.[0-9]|unmeasured)"
    device_field = r"([0-9]{1,3}|unmeasured)"
    quiet = re.fullmatch(rf"quiet cpu={cpu_field} gpu_foreign=([0-9]+) gpu={device_field} "
                         rf"gpu_peak={device_field} clock=(steady) retaken=(true|false)", state)
    if quiet:
        cpu, foreign, gpu, peak, clock, retaken = quiet.groups()
        return "quiet", {"cpu_some_pct": float(cpu) if cpu != "unmeasured" else cpu,
                         "gpu_foreign_pct": int(foreign), "gpu_pct": int(gpu) if gpu != "unmeasured" else gpu,
                         "gpu_peak_pct": int(peak) if peak != "unmeasured" else peak,
                         "clock": clock, "retaken": retaken == "true"}
    loaded = re.fullmatch(r"loaded cpu=(\S+) gpu_foreign=(\S+) gpu=(\S+) gpu_peak=(\S+) "
                          r"clock=(steady|changed|differs|unmeasured)", state)
    if loaded:
        cpu, foreign, gpu, peak, clock = loaded.groups()
        state = "loaded"
    else:
        cpu, foreign, gpu, peak = (evidence(stem.with_suffix(suffix))
                                  for suffix in (".cpu", ".gpu-foreign", ".gpu", ".gpu-peak"))
        state = "missing-or-unreadable"
        clock = "unmeasured"
    return state, {"cpu_some_pct": cpu, "gpu_foreign_pct": foreign, "gpu_pct": gpu, "gpu_peak_pct": peak, "clock": clock}


def paired_gpu_load(root, scale):
    """In check mode the runner's marker judges foreign GPU load and clocks."""
    pair = {mode: scene_load(root / f"scale-{scale}-{mode}") for mode in ("on", "off")}
    if all(state == "quiet" for state, _ in pair.values()):
        return ""
    details = []
    for mode, (state, readings) in pair.items():
        stem = root / f"scale-{scale}-{mode}"
        peers = evidence(stem.with_suffix(".gpu-foreign-peers"))
        clock = evidence(stem.with_suffix(".gpu-clock"))
        details.append(f"{mode}_gpu_foreign_pct={readings['gpu_foreign_pct']} "
                       f"{mode}_gpu_foreign_peers={peers} {mode}_scene_load={state} "
                       f"{mode}_clock={readings['clock']} {mode}_clock_record=[{clock}]")
    return " ".join(details)


def scene_loads(root, run_name):
    """Require every scene in a calibration pass to have a quiet attempt."""
    loads = {}
    for scale in ("1", "2"):
        loads[scale] = {}
        for mode in CALIBRATION_MODES:
            state, readings = scene_load(root / f"scale-{scale}-{mode}")
            if state != "quiet" or readings["cpu_some_pct"] == "unmeasured":
                values = " ".join(f"{key}={value}" for key, value in readings.items())
                raise Unmeasured(f"scene-load={state} run={run_name} scale={scale} scene={mode} {values}")
            loads[scale][mode] = readings
    return loads


def calibrate(roots):
    """Derive ceilings from quiet passes and measured instrument spread;
    every costly control must exceed the GPU ceiling."""
    runs = []
    for root in roots:
        run_name = "/".join(root.parts[-3:])
        loads = scene_loads(root, run_name)
        run = measure(root, runs[0] if runs else None, calibrating=True)
        run["run"] = run_name
        run["scene_loads"] = loads
        run["cpu_some_pct"] = max(load["cpu_some_pct"] for modes in loads.values() for load in modes.values())
        run["on_cpu_some_pct"] = {scale: modes["on"]["cpu_some_pct"] for scale, modes in loads.items()}
        runs.append(run)
    readings = {scale: {name: max(run["readings"][scale][name] for run in runs) for name in READINGS}
                for scale in ("1", "2")}
    ceilings = {name: max(RESOLUTION_MS[name], 2 * max(row[name] for row in readings.values()))
                for name in READINGS}
    # Identical scenes expose variation unrelated to the shader. Keep the
    # calibrated cost rule, but do not claim resolution below that spread.
    null_spread = max(0.0, *(value for run in runs for value in run["gpu_null_readings_ms"].values()))
    ceilings["gpu_cost_ms"] = max(ceilings["gpu_cost_ms"], null_spread)
    for run in runs:
        prove_control(run, ceilings, f" run={run['run']}")
    return dict(record(runs[0], ceilings), readings=readings, gpu_null_spread_ms=null_spread,
                gpu_null_method="scripts/measure-shader.sh --calibrate: nearest-rank p90 of identical off/null GPU timestamp frames, paired by sample; maximum over passes and scales",
                calibration_runs=[
        {"run": run["run"], "cpu_some_pct": run["cpu_some_pct"],
         "on_cpu_some_pct": run["on_cpu_some_pct"],
         "scene_loads": run["scene_loads"],
         "gpu_null_readings_ms": run["gpu_null_readings_ms"],
         "readings": run["readings"], "costly_control": run["costly_control"]}
        for run in runs])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, nargs="+")
    parser.add_argument("--shader", required=True)
    parser.add_argument("--cpu-pressure-limit", type=float, required=True)
    choice = parser.add_mutually_exclusive_group(required=True)
    choice.add_argument("--calibrate", type=Path)
    choice.add_argument("--check", type=Path)
    args = parser.parse_args()
    if args.check and len(args.directory) != 1:
        print(f"shader-cost: refused directories={len(args.directory)} check=1")
        return 2
    try:
        if args.check:
            records = json.loads(args.check.read_text())["shaders"]
            if args.shader not in records:
                raise ValueError("baseline=absent")
            result = check(args.directory[0], records[args.shader], args.cpu_pressure_limit)
        else:
            result = calibrate(args.directory)
            records = json.loads(args.calibrate.read_text()) if args.calibrate.exists() else {"shaders": {}}
            records["shaders"][args.shader] = result
            args.calibrate.write_text(json.dumps(records, indent=2) + "\n")
        print(json.dumps(result, indent=2))
    except Unmeasured as error:
        print(f"shader-cost: status=not-measured shader={args.shader} {error}")
        return 77
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"shader-cost: failed shader={args.shader} {error}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
