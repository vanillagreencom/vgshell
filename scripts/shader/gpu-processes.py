#!/usr/bin/env python3
"""Own a shader run's host pmon trace and read foreign load by scene window.

`run DIRECTORY FENCE [OPTIONS] -- COMMAND ...` starts the fence as a child
and supplies the trace path to COMMAND. `window FILE START_MS END_MS` reads
only complete JSONL records in that inclusive epoch-ms interval. It prints
the mean load and a JSON array of foreign GPU peers on separate lines.
"""
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time


def epoch_ms():
    return time.time_ns() // 1_000_000


def cgroup(path):
    """Read the unified hierarchy. An exited or unreadable PID is not own."""
    try:
        for line in path.read_text().splitlines():
            if line.startswith("0::/"):
                return line[3:]
    except (OSError, UnicodeError):
        pass
    return None


def blocks(lines, own_cgroup, pid_cgroup, clock=epoch_ms):
    """Split `nvidia-smi pmon -s u -d 1 -o DT` by timestamp or header.

    NVIDIA's Process Monitoring docs describe the SM column and "-" values.
    The VGS-2619 RTX 5090 probe also saw a blank command column.
    https://docs.nvidia.com/deploy/nvidia-smi/#process-monitoring
    """
    stamp = None
    rows = []
    prefix = own_cgroup.rstrip("/") + "/"

    def record():
        return {
            "epoch_ms": clock(),
            "foreign_sm_pct": sum(sm for _, sm, own, _, _ in rows if not own),
            "own_sm_pct": sum(sm for _, sm, own, _, _ in rows if own),
            "processes": rows,
        }

    for line in lines:
        if not line.endswith("\n"):
            raise ValueError("pmon=partial-line")
        line = line.strip()
        if not line:
            continue
        if line.startswith("#"):
            if stamp is not None:
                yield record()
                stamp, rows = None, []
            continue
        fields = line.split(maxsplit=11)
        if (len(fields) < 11 or not re.fullmatch(r"[0-9]{8}", fields[0])
                or not re.fullmatch(r"[0-9]{2}:[0-9]{2}:[0-9]{2}", fields[1])):
            raise ValueError("pmon=unreadable-row")
        if stamp is not None and stamp != fields[:2]:
            yield record()
            rows = []
        stamp = fields[:2]
        pid, sm = fields[3], fields[5]
        if pid == "-" and sm == "-":
            continue
        if not re.fullmatch(r"[0-9]+", pid) or not re.fullmatch(r"[0-9]{1,3}|-", sm):
            raise ValueError("pmon=unreadable-pid-or-sm")
        sm = 0 if sm == "-" else int(sm)
        if sm > 100:
            raise ValueError("pmon=sm-out-of-range")
        pid = int(pid)
        group = pid_cgroup(pid)
        own = group is not None and (group == own_cgroup or group.startswith(prefix))
        unit = next((part for part in reversed(group.split("/")) if part.endswith((".service", ".scope"))),
                    "") if group is not None else ""
        rows.append([pid, sm, own, fields[11] if len(fields) == 12 else "", unit])
    if stamp is not None:
        yield record()


def capture(source, output, own_cgroup):
    with source:
        try:
            for block in blocks(source, own_cgroup, lambda pid: cgroup(Path(f"/proc/{pid}/cgroup"))):
                print(json.dumps(block), file=output, flush=True)
        except (OSError, ValueError) as error:
            print(f"shader-cost: gpu-processes=unavailable cause={error}", file=sys.stderr)


def send(child, sig):
    # A pidfd binds the signal to the direct child that only this thread
    # waits on. Neither the fence nor pmon inherits the descriptor.
    if child.returncode is not None:
        return
    try:
        fd = os.pidfd_open(child.pid)
    except ProcessLookupError:
        return
    except OSError:
        # An unreaped direct child still reserves its PID.
        child.send_signal(sig)
        return
    try:
        signal.pidfd_send_signal(fd, sig)
    except ProcessLookupError:
        pass
    finally:
        os.close(fd)


def stop_sampler(sampler, reader):
    send(sampler, signal.SIGTERM)
    try:
        sampler.wait(timeout=1)
    except subprocess.TimeoutExpired:
        send(sampler, signal.SIGKILL)
        sampler.wait()
    if reader is not None:
        reader.join()
    else:
        sampler.stdout.close()


def run(directory, command):
    """Keep the trace producer in the fence's outer cgroup and PID view."""
    stopped = None

    def request_stop(signum, _frame):
        nonlocal stopped
        if stopped is None:
            stopped = signum

    for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(signum, request_stop)

    trace = sampler = reader = None
    try:
        # The outer shell execs this driver, so /proc/self is still the run
        # owner. The fence changes the PID view but does not move cgroups.
        try:
            own = cgroup(Path("/proc/self/cgroup"))
            if own is None:
                raise OSError("own-cgroup-unreadable")
            directory.mkdir(parents=True, exist_ok=True)
            trace = tempfile.NamedTemporaryFile(
                mode="w", dir=directory, delete=False, suffix=".jsonl",
                prefix=f"gpu-processes-{epoch_ms()}-{os.getpid()}-")
            sampler = subprocess.Popen(
                ["stdbuf", "-oL", "nvidia-smi", "pmon", "-s", "u", "-d", "1", "-o", "DT"],
                stdout=subprocess.PIPE, stdin=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace")
            worker = threading.Thread(target=capture, args=(sampler.stdout, trace, own))
            worker.start()
            reader = worker
            print(f"shader-cost: gpu-processes={trace.name}", flush=True)
            split = command.index("--") + 1
            command = [*command[:split], "env", f"VGS_SHADER_GPU_PROCESSES={trace.name}", *command[split:]]
        except (OSError, RuntimeError) as error:
            print(f"shader-cost: gpu-processes=unavailable cause={error}", file=sys.stderr)
        if stopped is not None:
            return 128 + stopped
        fence = subprocess.Popen(command)
        forwarded = False
        while True:
            if stopped is not None and not forwarded:
                forwarded = True
                send(fence, stopped)
                if sampler is not None:
                    stop_sampler(sampler, reader)
                    sampler = None
            try:
                status = fence.wait(timeout=0.1)
                return status if status >= 0 else 128 - status
            except subprocess.TimeoutExpired:
                continue
    finally:
        if sampler is not None:
            stop_sampler(sampler, reader)
        if trace is not None:
            trace.close()


def window(path, start, end):
    """Round half up using integer math; an absent reading is never zero."""
    total = count = 0
    peers = set()
    try:
        with path.open() as records:
            for line in records:
                if not line.endswith("\n"):
                    # The outside writer may be appending its next record.
                    break
                record = json.loads(line)
                epoch, load = record["epoch_ms"], record["foreign_sm_pct"]
                if type(epoch) is not int or type(load) is not int or load < 0:
                    return "unmeasured", []
                if start <= epoch <= end:
                    total += load
                    count += 1
                    for pid, sm, own, command, unit in record["processes"]:
                        if sm > 0 and not own:
                            name = command or f"pid:{pid}"
                            peers.add(f"{name}@{unit}" if unit else name)
    except (OSError, ValueError, TypeError, KeyError):
        return "unmeasured", []
    return ((2 * total + count) // (2 * count), sorted(peers)) if count else ("unmeasured", [])


if __name__ == "__main__":
    verb, path, *args = sys.argv[1:]
    if verb == "run":
        sys.exit(run(Path(path), args))
    if verb == "window":
        mean, peers = window(Path(path), *map(int, args))
        print(mean)
        print(json.dumps(peers, separators=(",", ":")))
    else:
        sys.exit(f"gpu-processes: refused verb={verb}")
