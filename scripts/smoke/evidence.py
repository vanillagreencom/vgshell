#!/usr/bin/env python3
"""Retain failed or interrupted smoke rows after the namespace ends.

The harness writes private metadata under its sandbox's evidence directory.
The world calls this once after all namespace processes stop.
Each row keeps at most 8 MiB, including its index; each file keeps at most
1 MiB. ANR spans are frozen at observation; other files keep their tail.
ipc.log keeps the tail of the span the row wrote, from its first reading's
recorded size to its last's, or to the end for an interrupted row.
This is a storage cap, not a latency or product memory budget.
"""
import json
import os
from pathlib import Path
import stat
import sys

ROW_BYTES = 8 * 1024 * 1024
FILE_BYTES = 1024 * 1024
INDEX_BYTES = 8192


def reading(sandbox, snapshot):
    """Advisory diagnostics only; required leak classes keep their own verdict."""
    active = sandbox / "evidence/active"
    world = Path(os.environ["VGSHELL_WORLD_ROOT"]).resolve(strict=True)
    owned = sandbox.resolve(strict=True)
    if not owned.is_relative_to(world) or snapshot.resolve(strict=True).parent != owned / "leaks":
        raise ValueError("reading outside nested sandbox")
    # Register before acquisition so an interrupted reading also survives.
    with active.open("a") as stream:
        stream.write(snapshot.name + "\n")
    # Taken before this reading's own IPC calls append to ipc.log.
    try:
        info = os.lstat(owned / "ipc.log")
        if stat.S_ISREG(info.st_mode):
            (snapshot / "ipc-offset").write_text("%d\n" % info.st_size)
    except FileNotFoundError:
        (snapshot / "ipc-offset").write_text("0\n")
    # harness.sh fixes XDG_STATE_HOME to this owned home. No caller HOME,
    # credential store or image bytes enter this diagnostic.
    home = owned / "home"
    source = home / ".local/state/vgshell/backgrounds.json"
    observation = {"source": str(source), "status": "unavailable"}
    data = None
    try:
        # Hold each parent while opening its child. A replaced link cannot
        # redirect a diagnostic into the caller's readable home.
        flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
        directory = os.open(owned, flags)
        try:
            for part in ("home", ".local", "state", "vgshell"):
                child = os.open(part, flags, dir_fd=directory)
                os.close(directory)
                directory = child
            fd = os.open("backgrounds.json", os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW, dir_fd=directory)
        finally:
            os.close(directory)
        with os.fdopen(fd, "rb") as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode):
                raise ValueError("wallpaper state is not a regular file")
            data = stream.read(FILE_BYTES + 1)
            if len(data) > FILE_BYTES:
                data = None
                raise ValueError("wallpaper state exceeds evidence file bound")
        observation.update(status="present", bytes=len(data))
    except FileNotFoundError:
        observation["status"] = "absent"
    except (OSError, ValueError) as error:
        observation["cause"] = str(error)
        print("qml-smoke: evidence=wallpaper-state-unavailable reading=%s cause=%s" % (snapshot.name, error), flush=True)
    if data is not None:
        (snapshot / "backgrounds.json").write_bytes(data)
    (snapshot / "background-state.json").write_text(json.dumps(observation) + "\n")


def retain(root, sandbox, outputs):
    metadata = sandbox / "evidence"
    if not (metadata / "destination").is_file():
        return
    rows = list((metadata / "failed").glob("*"))
    if (metadata / "active").is_file():
        rows.append(metadata / "active")
    if not rows:
        return
    runtime_alias = Path((metadata / "runtime").read_text().strip())
    runtime = Path((metadata / "runtime-backing").read_text().strip())
    if not sandbox.resolve().is_relative_to(root.resolve()) or not runtime.resolve().is_relative_to(root.resolve()):
        raise ValueError("evidence source outside owned root")
    def backing(path):
        candidate = Path(path)
        return runtime / candidate.relative_to(runtime_alias) if candidate.is_relative_to(runtime_alias) else candidate
    destination = Path((metadata / "destination").read_text().strip())
    if not any(destination.resolve().is_relative_to(output.resolve()) for output in outputs):
        raise ValueError("evidence destination not declared at entry")
    destination = destination / ("smoke-evidence-" + sandbox.name)
    for record in rows:
        row, initial_log, *readings = record.read_text().splitlines()
        if not row or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789-" for c in row):
            raise ValueError("invalid row name")
        target = destination / row
        # A retried copy keeps a complete snapshot once.
        if (target / "index.txt").exists():
            continue
        target.mkdir(parents=True, exist_ok=True)
        index = ["row=" + row, "state=" + ("interrupted" if record.name == "active" else "failed")]
        candidates = []
        incident_root = sandbox / "rows" / (row + ".anr")
        candidates += [(p, "row/" + str(p.relative_to(sandbox / "rows")))
                       for p in sorted(incident_root.rglob("*"), key=lambda p: (p.name != "incident.json", str(p))) if p.is_file()]
        incident_count = len(candidates)
        instances = sorted(runtime.glob("quickshell/by-id/*/log.log"),
                           key=lambda p: p.stat().st_mtime_ns, reverse=True)
        logs = [str(instances[0]) if instances else "", initial_log]
        for log in dict.fromkeys(logs):
            if log:
                candidates.append((backing(log), "instance-" + Path(log).parent.name + ".log"))
        candidates += [(p, "compositor-" + p.parent.name + ".log")
                       for p in sorted(runtime.glob("hypr/*/hyprland.log"))]
        candidates.append((sandbox / "hyprland.log", "compositor-launch.log"))
        candidates.append((sandbox / "sink.log", "sink.log"))
        candidates.append((sandbox / "rows" / (row + ".out"), "row/" + row + ".out"))
        # Other rows' calls share ipc.log, so only this row's span is kept.
        spans = {}
        try:
            first, last = (int((sandbox / "leaks" / r / "ipc-offset").read_text()) for r in (readings[0], readings[-1]))
            spans[sandbox / "ipc.log"] = (first, None if record.name == "active" else last)
            candidates.append((sandbox / "ipc.log", "ipc.log"))
        except (IndexError, OSError, ValueError) as error:
            index.append("unavailable=ipc.log cause=%s" % error)
        for entry in sorted((sandbox / "rows").glob(row + ".*")):
            if entry.is_dir() and not entry.is_symlink():
                candidates += [(p, "row/" + str(p.relative_to(sandbox / "rows")))
                               for p in sorted(entry.rglob("*")) if p.is_file()]
            else:
                candidates.append((entry, "row/" + entry.name))
        # Keep frozen ANR spans first, then boundary inputs, then log tails.
        boundary = []
        for reading in dict.fromkeys(readings):
            folder = sandbox / "leaks" / reading
            boundary += [(p, "probes/" + reading + "/" + p.name) for p in sorted(folder.glob("*"))]
        candidates[incident_count:incident_count] = boundary
        candidates += [(p, "instance-" + p.parent.name + ".log") for p in instances]
        remaining = ROW_BYTES - INDEX_BYTES
        seen = set()
        for source, name in candidates:
            if source in seen or remaining <= 0:
                continue
            seen.add(source)
            try:
                # Only regular files from the two owned trees are evidence.
                resolved = source.resolve()
                if not any(resolved.is_relative_to(root.resolve()) for root in (sandbox, runtime)):
                    continue
                fd = os.open(source, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
                with os.fdopen(fd, "rb") as stream:
                    size = os.fstat(stream.fileno()).st_size
                    if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                        continue
                    start, end = spans.get(source, (0, None))
                    end = size if end is None else end
                    if not start <= end <= size:
                        index.append("unavailable=%s cause=span start=%d end=%d size=%d" % (name, start, end, size))
                        continue
                    length = min(end - start, FILE_BYTES, remaining)
                    stream.seek(end - length)
                    data = stream.read(length)
                out = target / name
                out.parent.mkdir(parents=True, exist_ok=True)
                out.write_bytes(data)
                remaining -= len(data)
                index.append("file=%s source-bytes=%d kept-bytes=%d" % (name, end - start, len(data)))
            except FileNotFoundError:
                index.append("missing=" + name)
        (target / "index.txt").write_bytes(("\n".join(index) + "\n").encode()[:INDEX_BYTES])
        print("qml-smoke: evidence=%s row=%s bound-bytes=%d" % (target, row, ROW_BYTES), flush=True)


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--reading":
        try:
            reading(Path(sys.argv[2]), Path(sys.argv[3]))
        except (OSError, ValueError, KeyError) as error:
            # Evidence is advisory: unavailable diagnostics preserve the
            # original row verdict, as after-namespace copy errors do.
            print("qml-smoke: evidence=reading-unavailable cause=%s" % error, file=sys.stderr)
    else:
        try:
            retain(Path(sys.argv[1]), Path(sys.argv[2]), [Path(path) for path in sys.argv[3:]])
        except (OSError, ValueError) as error:
            print("qml-smoke: evidence=copy-failed cause=%s" % error, file=sys.stderr)
            sys.exit(1)
