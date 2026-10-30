#!/usr/bin/env python3
"""Required literal checkpoint of the wallpaper writer's two outputs.

The row owner supplies quiescence and ordering. This process alone holds the
product lock; it never starts children or hands its lock to a shell.
Exit 0; 1 when compare finds the units differ; 2 refused, with a keyed
`qml-smoke: persisted-inputs=` line and, for capture, a receipt; 3 when the
--bound ends while --hold keeps a complete capture, keyed `hold-expired`.
"""
import argparse
import base64
import contextlib
import fcntl
import json
import os
from pathlib import Path
import signal
import stat
import sys
import time
import uuid

CAP = 1024 * 1024
NAMES = ("background", "backgrounds.json")  # writer publication order
META = "persisted-inputs.json"
DIRECTORY = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
REGULAR = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC


class Refused(Exception):
    def __init__(self, operation, cause):
        super().__init__(f"operation={operation} cause={cause}")
        self.operation, self.cause = operation, str(cause)


def identity(info):
    return info.st_dev, info.st_ino


def version(info):
    return identity(info), info.st_size, info.st_mtime_ns, info.st_ctime_ns, info.st_mode


class OwnedPaths:
    """Hold every no-follow parent and verify the live names still reach it."""
    def __init__(self, sandbox):
        world = os.environ.get("VGSHELL_WORLD_ROOT")
        if not world:
            raise Refused("unsafe-path", "world-root-missing")
        self.world = os.path.abspath(world)
        self.sandbox = os.path.abspath(sandbox)
        relative = os.path.relpath(self.sandbox, self.world)
        if relative == "." or relative == ".." or relative.startswith("../"):
            raise Refused("unsafe-path", "sandbox-outside-world")
        self.fds, self.edges = [], []
        try:
            self.root = os.open(self.world, DIRECTORY)
            self.fds.append(self.root)
            info = os.fstat(self.root)
            if info.st_uid != os.getuid() or info.st_mode & 0o022:
                raise Refused("unsafe-path", "world-owner-or-mode")
            self.home = self.walk(self.root, (*relative.split(os.sep), "home"))
            if self.home is None:
                raise Refused("unsafe-path", "home-missing")
        except BaseException:
            self.close()
            raise

    def walk(self, parent, parts, create=False):
        for name in parts:
            try:
                child = os.open(name, DIRECTORY, dir_fd=parent)
            except FileNotFoundError:
                if not create:
                    return None
                try:
                    os.mkdir(name, 0o700, dir_fd=parent)
                except FileExistsError as error:
                    raise Refused("changed", f"parent-created:{name}") from error
                child = os.open(name, DIRECTORY, dir_fd=parent)
            except OSError as error:
                raise Refused("unsafe-path", f"parent:{name}:{error}") from error
            self.fds.append(child)
            info = os.fstat(child)
            if info.st_uid != os.getuid():
                raise Refused("unsafe-path", f"parent-owner:{name}")
            self.edges.append((parent, name, identity(info)))
            parent = child
        return parent

    def state(self, create=False):
        return self.walk(self.home, (".local", "state", "vgshell"), create)

    def verify(self):
        try:
            if identity(os.stat(self.world, follow_symlinks=False)) != identity(os.fstat(self.root)):
                raise Refused("changed", "world-replaced")
            for parent, name, expected in self.edges:
                if identity(os.stat(name, dir_fd=parent, follow_symlinks=False)) != expected:
                    raise Refused("changed", f"parent-replaced:{name}")
        except OSError as error:
            raise Refused("changed", error) from error

    @contextlib.contextmanager
    def locked(self):
        parent = self.walk(self.home, (".config", "vgshell"), True)
        try:
            descriptor = os.open("theme.lock", os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW |
                                 os.O_NONBLOCK | os.O_CLOEXEC, 0o600, dir_fd=parent)
        except OSError as error:
            raise Refused("lock", f"open:{error}") from error
        try:
            info = os.fstat(descriptor)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
                raise Refused("unsafe-path", "theme-lock-type-or-owner")
            # SIGALRM and the parent's timeout bound this kernel wait.
            fcntl.flock(descriptor, fcntl.LOCK_EX)
            if identity(os.stat("theme.lock", dir_fd=parent, follow_symlinks=False)) != identity(info):
                raise Refused("changed", "theme-lock-replaced")
            self.verify()
            yield
            self.verify()
            if identity(os.stat("theme.lock", dir_fd=parent, follow_symlinks=False)) != identity(info):
                raise Refused("changed", "theme-lock-replaced")
        finally:
            os.close(descriptor)

    def close(self):
        for descriptor in reversed(self.fds):
            os.close(descriptor)
        self.fds.clear()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


def entry(parent, name):
    if parent is None:
        return {"kind": "absent"}, None
    try:
        before = os.stat(name, dir_fd=parent, follow_symlinks=False)
    except FileNotFoundError:
        return {"kind": "absent"}, None
    if stat.S_ISLNK(before.st_mode):
        target = os.readlink(os.fsencode(name), dir_fd=parent)
        result, payload = {"kind": "symlink", "targetBase64": base64.b64encode(target).decode("ascii")}, None
    elif stat.S_ISREG(before.st_mode):
        if before.st_size > CAP:
            raise Refused("read", f"oversize:{name}")
        descriptor = os.open(name, REGULAR, dir_fd=parent)
        try:
            if version(os.fstat(descriptor)) != version(before):
                raise Refused("changed", f"open:{name}")
            chunks, size = [], 0
            while True:
                chunk = os.read(descriptor, min(65536, CAP + 1 - size))
                if not chunk:
                    break
                chunks.append(chunk)
                size += len(chunk)
                if size > CAP:
                    raise Refused("read", f"oversize:{name}")
            if version(os.fstat(descriptor)) != version(before) or size != before.st_size:
                raise Refused("changed", f"read:{name}")
            payload = b"".join(chunks)
            result = {"kind": "regular", "mode": stat.S_IMODE(before.st_mode), "payload": "persisted-" + name}
        finally:
            os.close(descriptor)
    else:
        raise Refused("unsupported", f"entry:{name}:mode={before.st_mode:o}")
    if version(os.stat(name, dir_fd=parent, follow_symlinks=False)) != version(before):
        raise Refused("changed", f"named-entry:{name}")
    return result, payload


def encode(document):
    return (json.dumps(document, sort_keys=True, separators=(",", ":")) + "\n").encode()


def capture(paths):
    metadata, payloads, errors = {"version": 1, "entries": {}}, {}, []
    parent = paths.state()
    for name in NAMES:
        try:
            item, payload = entry(parent, name)
            if payload is not None:
                payloads[item["payload"]] = payload
        except (OSError, Refused) as error:
            item = {"kind": "unavailable", "operation": getattr(error, "operation", "read"), "cause": str(error)}
            errors.append(name)
        metadata["entries"][name] = item
    paths.verify()
    if len(encode(metadata)) + sum(map(len, payloads.values())) > CAP:
        metadata["entries"] = {name: {"kind": "unavailable", "operation": "read", "cause": "unit-aggregate-oversize"} for name in NAMES}
        payloads, errors = {}, list(NAMES)
    return metadata, payloads, errors


def write_new(directory, name, data):
    descriptor = os.open(directory / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(data)


def save(directory, unit):
    metadata, payloads, _ = unit
    for name, data in payloads.items():
        write_new(directory, name, data)
    write_new(directory, META, encode(metadata))


def read_regular(path):
    descriptor = os.open(path, REGULAR)
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_size > CAP:
            raise Refused("read", f"checkpoint-type-or-size:{path.name}")
        with os.fdopen(descriptor, "rb", closefd=False) as stream:
            data = stream.read(CAP + 1)
        if len(data) != before.st_size or version(before) != version(os.fstat(descriptor)):
            raise Refused("changed", f"checkpoint:{path.name}")
        return data
    finally:
        os.close(descriptor)


def load(directory):
    raw = read_regular(directory / META)
    metadata = json.loads(raw)
    if metadata.get("version") != 1 or set(metadata["entries"]) != set(NAMES):
        raise Refused("read", "checkpoint-schema")
    payloads = {}
    for name, item in metadata["entries"].items():
        kind = item["kind"]
        if kind == "regular":
            if item["payload"] != "persisted-" + name or type(item["mode"]) is not int or not 0 <= item["mode"] <= 0o7777:
                raise Refused("read", "checkpoint-regular-schema")
            payloads[item["payload"]] = read_regular(directory / item["payload"])
        elif kind == "symlink":
            target = base64.b64decode(item["targetBase64"], validate=True)
            if not target or b"\0" in target:
                raise Refused("read", "checkpoint-link-schema")
        elif kind != "absent":
            raise Refused("read", "checkpoint-unavailable")
    if len(raw) + sum(map(len, payloads.values())) > CAP:
        raise Refused("read", "checkpoint-aggregate-oversize")
    return metadata, payloads, []


def equal(left, right):
    return not left[2] and not right[2] and left[:2] == right[:2]


def restore(paths, target):
    current = capture(paths)
    if current[2]:
        raise Refused("read", "current-unit-unavailable")
    if equal(target, current):
        return
    parent = paths.state(True)
    staged = {}
    try:
        for name in NAMES:
            wanted = target[0]["entries"][name]
            if wanted["kind"] == "absent":
                continue
            temporary = ".smoke-selection-" + uuid.uuid4().hex
            try:
                if wanted["kind"] == "symlink":
                    os.symlink(base64.b64decode(wanted["targetBase64"]), os.fsencode(temporary), dir_fd=parent)
                else:
                    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600, dir_fd=parent)
                    staged[name] = temporary
                    with os.fdopen(descriptor, "wb") as stream:
                        stream.write(target[1][wanted["payload"]])
                        stream.flush()
                        os.fchmod(stream.fileno(), wanted["mode"])
                staged[name] = temporary
            except OSError as error:
                raise Refused("stage", f"{name}:{error}") from error
        paths.verify()
        if not equal(current, capture(paths)):
            raise Refused("changed", "pre-publication-unit")
        for name in NAMES:
            paths.verify()
            # Refuse special replacements even if a noncooperating actor races.
            entry(parent, name)
            try:
                if name in staged:
                    os.replace(staged[name], name, src_dir_fd=parent, dst_dir_fd=parent)
                    del staged[name]
                elif current[0]["entries"][name]["kind"] != "absent":
                    os.unlink(name, dir_fd=parent)
            except OSError as error:
                raise Refused("rename" if name in staged else "remove", f"{name}:{error}") from error
        if not equal(target, capture(paths)):
            raise Refused("post-mismatch", "published-unit")
    finally:
        for temporary in staged.values():
            os.unlink(temporary, dir_fd=parent)


def deadline(*_):
    raise Refused("busy", "operation-deadline")


class HoldExpired(Exception):
    """The bound ended while a complete capture was held for the owner."""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("capture", "restore", "compare"))
    parser.add_argument("sandbox")
    parser.add_argument("snapshot", type=Path)
    parser.add_argument("other", type=Path, nargs="?")
    parser.add_argument("--hold", action="store_true")
    parser.add_argument("--bound", type=float, default=10)
    args = parser.parse_args()
    started, holding = time.monotonic(), False

    def expire(*_):
        if holding:
            raise HoldExpired(f"elapsed-ms={round((time.monotonic() - started) * 1000)}")
        deadline()
    signal.signal(signal.SIGALRM, expire)
    signal.setitimer(signal.ITIMER_REAL, args.bound)
    try:
        if args.operation == "compare":
            if args.other is None:
                raise Refused("read", "comparison-missing")
            return 0 if equal(load(args.snapshot), load(args.other)) else 1
        with OwnedPaths(args.sandbox) as paths, paths.locked():
            if args.operation == "capture":
                unit = capture(paths)
                save(args.snapshot, unit)
                if unit[2]:
                    raise Refused("read", "unit-unavailable:" + ",".join(unit[2]))
                if args.hold:
                    holding = True
                    print("ready", flush=True)
                    if sys.stdin.readline() != "release\n":
                        raise Refused("busy", "capture-owner-disconnected")
            else:
                if args.other is None:
                    raise Refused("read", "restore-receipt-missing")
                try:
                    restore(paths, load(args.snapshot))
                except (OSError, Refused) as error:
                    write_new(args.other, "persisted-restore.json", encode({"status": "failed", "error": str(error)}))
                    raise
                write_new(args.other, "persisted-restore.json", encode({"status": "restored"}))
        return 0
    except HoldExpired as error:
        # The unit on disk is complete; the owner's other readers outlasted
        # the hold, so their reading was not taken under the lock.
        print(f"qml-smoke: persisted-inputs=hold-expired {error}", file=sys.stderr)
        return 3
    except (OSError, Refused, ValueError, KeyError, TypeError) as error:
        # Even a refused lock/path gets an explicit required receipt. Never
        # overwrite a reading already frozen by the owner.
        if args.operation == "capture" and not (args.snapshot / META).exists():
            try:
                save(args.snapshot, ({"version": 1, "entries": {name: {
                    "kind": "unavailable", "operation": getattr(error, "operation", "read"),
                    "cause": str(error)} for name in NAMES}}, {}, list(NAMES)))
            except OSError as receipt_error:
                print(f"qml-smoke: persisted-inputs=receipt {receipt_error}", file=sys.stderr)
        print(f"qml-smoke: persisted-inputs={args.operation} {error}", file=sys.stderr)
        return 2
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)


if __name__ == "__main__":
    sys.exit(main())
