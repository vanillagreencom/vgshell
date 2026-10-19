#!/usr/bin/env python3
"""Retain failed or interrupted smoke rows before either owner removes them.

The harness writes private metadata under its sandbox's evidence directory.
Both teardown and the fence's ledger release call this after producers stop.
Each row keeps at most 8 MiB, including its index; each file keeps its last
1 MiB. This is a storage cap, not a latency or product memory budget.
"""
import os
from pathlib import Path
import stat
import sys

ROW_BYTES = 8 * 1024 * 1024
FILE_BYTES = 1024 * 1024
INDEX_BYTES = 8192


def retain(sandbox):
    metadata = sandbox / "evidence"
    if not (metadata / "destination").is_file():
        return
    rows = list((metadata / "failed").glob("*"))
    if (metadata / "active").is_file():
        rows.append(metadata / "active")
    if not rows:
        return
    runtime = Path((metadata / "runtime").read_text().strip())
    destination = Path((metadata / "destination").read_text().strip())
    destination = destination / ("smoke-evidence-" + sandbox.name)
    for record in rows:
        row, initial_log, *readings = record.read_text().splitlines()
        if not row or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789-" for c in row):
            raise ValueError("invalid row name")
        target = destination / row
        # The fence can follow teardown after an interrupted copy. Keep a
        # complete snapshot once, and never append duplicate retained bytes.
        if (target / "index.txt").exists():
            continue
        target.mkdir(parents=True, exist_ok=True)
        candidates = []
        instances = sorted(runtime.glob("quickshell/by-id/*/log.log"),
                           key=lambda p: p.stat().st_mtime_ns, reverse=True)
        logs = [str(instances[0]) if instances else "", initial_log]
        for log in dict.fromkeys(logs):
            if log:
                candidates.append((Path(log), "instance-" + Path(log).parent.name + ".log"))
        candidates += [(p, "compositor-" + p.parent.name + ".log")
                       for p in sorted(runtime.glob("hypr/*/hyprland.log"))]
        candidates.append((sandbox / "hyprland.log", "compositor-launch.log"))
        candidates.append((sandbox / "sink.log", "sink.log"))
        candidates.append((sandbox / "rows" / (row + ".out"), "row/" + row + ".out"))
        for entry in sorted((sandbox / "rows").glob(row + ".*")):
            if entry.is_dir() and not entry.is_symlink():
                candidates += [(p, "row/" + str(p.relative_to(sandbox / "rows")))
                               for p in sorted(entry.rglob("*")) if p.is_file()]
            else:
                candidates.append((entry, "row/" + entry.name))
        for reading in readings:
            folder = sandbox / "leaks" / reading
            candidates += [(p, "probes/" + reading + "/" + p.name) for p in sorted(folder.glob("*"))]
        candidates += [(p, "instance-" + p.parent.name + ".log") for p in instances]
        remaining = ROW_BYTES - INDEX_BYTES
        index = ["row=" + row, "state=" + ("interrupted" if record.name == "active" else "failed")]
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
                    length = min(size, FILE_BYTES, remaining)
                    stream.seek(max(0, size - length))
                    data = stream.read(length)
                out = target / name
                out.parent.mkdir(parents=True, exist_ok=True)
                out.write_bytes(data)
                remaining -= len(data)
                index.append("file=%s source-bytes=%d kept-bytes=%d" % (name, size, len(data)))
            except FileNotFoundError:
                index.append("missing=" + name)
        (target / "index.txt").write_bytes(("\n".join(index) + "\n").encode()[:INDEX_BYTES])
        print("qml-smoke: evidence=%s row=%s bound-bytes=%d" % (target, row, ROW_BYTES), flush=True)


if __name__ == "__main__":
    try:
        retain(Path(sys.argv[1]))
    except (OSError, ValueError) as error:
        print("qml-smoke: evidence=copy-failed cause=%s" % error, file=sys.stderr)
        sys.exit(1)
