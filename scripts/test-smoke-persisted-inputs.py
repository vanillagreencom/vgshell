#!/usr/bin/env python3
"""Real fixed-unit mechanics, unsafe-path controls and a disabled-restore mutant."""
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import patch

REPO = Path(__file__).resolve().parent.parent
PROGRAM = REPO / "scripts/smoke/persisted-inputs.py"
spec = importlib.util.spec_from_file_location("persisted_inputs", PROGRAM)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
ENV = {key: os.environ[key] for key in ("PATH", "TMPDIR", "VGSHELL_WORLD_ROOT")}


def require_refusal(operation, action):
    try:
        action()
    except helper.Refused as error:
        assert error.operation == operation, error
        return
    raise AssertionError("refusal-missing:" + operation)


with tempfile.TemporaryDirectory(prefix="persisted-input-controls-", dir=ENV["TMPDIR"]) as temporary:
    root = Path(temporary)

    def fixture(name):
        sandbox = root / name
        (sandbox / "home").mkdir(parents=True)
        return sandbox

    def state(sandbox):
        path = sandbox / "home/.local/state/vgshell"
        path.mkdir(parents=True, exist_ok=True)
        return path

    def snapshot(sandbox, name):
        directory = sandbox / name
        directory.mkdir()
        with helper.OwnedPaths(sandbox) as owned, owned.locked():
            unit = helper.capture(owned)
            assert not unit[2], unit
            helper.save(directory, unit)
        return directory

    def restore(sandbox, baseline):
        with helper.OwnedPaths(sandbox) as owned, owned.locked():
            helper.restore(owned, helper.load(baseline))

    def exact(sandbox, baseline):
        with helper.OwnedPaths(sandbox) as owned, owned.locked():
            assert helper.equal(helper.load(baseline), helper.capture(owned)), "unit-not-restored"

    # Both entries accept all literal kinds. No JSON parser or target reader
    # participates, including a dangling link and a non-UTF-8 link target.
    for kind in ("absent", "regular", "symlink", "dangling"):
        sandbox = fixture(kind)
        folder = state(sandbox)
        external = root / (kind + "-external")
        external.write_bytes(b"must-not-be-read-or-written")
        for name in helper.NAMES:
            path = folder / name
            if kind == "regular":
                path.write_bytes(b"malformed\x00\xff\n" + os.fsencode(name))
                path.chmod(0o640)
            elif kind in ("symlink", "dangling"):
                path.symlink_to(external if kind == "symlink" else os.fsdecode(b"missing-\xff"))
        baseline = snapshot(sandbox, "start")
        stored = json.loads((baseline / helper.META).read_text())
        assert all(item["kind"] == ("symlink" if kind in ("symlink", "dangling") else kind)
                   for item in stored["entries"].values())
        for name in helper.NAMES:
            path = folder / name
            path.unlink(missing_ok=True)
            path.write_bytes(b"changed")
        restore(sandbox, baseline)
        exact(sandbox, baseline)
        for name in helper.NAMES:
            path = folder / name
            if kind == "absent":
                assert not path.exists() and not path.is_symlink()
            elif kind == "regular":
                assert not path.is_symlink() and path.read_bytes() == b"malformed\x00\xff\n" + os.fsencode(name)
            else:
                assert path.is_symlink()
                assert os.readlink(os.fsencode(path)) == (os.fsencode(external) if kind == "symlink" else b"missing-\xff")
        assert external.read_bytes() == b"must-not-be-read-or-written"
        if kind == "regular":
            assert all((folder / name).stat().st_mode & 0o7777 == 0o640 for name in helper.NAMES)
        # Deletion and recreation of both populated members.
        if kind != "absent":
            for name in helper.NAMES:
                (folder / name).unlink()
            restore(sandbox, baseline)
            exact(sandbox, baseline)
        print("persisted-inputs: literal=" + kind + " restore=exact")

    sandbox = fixture("parent-link")
    outside = root / "outside"
    outside.mkdir()
    (sandbox / "home/.local").symlink_to(outside)
    with helper.OwnedPaths(sandbox) as owned:
        require_refusal("unsafe-path", lambda: helper.capture(owned))
    assert not list(outside.iterdir())
    print("persisted-inputs: symlink-parent=refused external=untouched")

    for name in ("fifo", "directory", "unreadable", "oversize", "aggregate"):
        sandbox = fixture(name)
        folder = state(sandbox)
        path = folder / "backgrounds.json"
        if name == "fifo":
            os.mkfifo(path)
        elif name == "directory":
            path.mkdir()
        else:
            path.write_bytes(b"x" * (helper.CAP if name in ("oversize", "aggregate") else 1))
            if name == "unreadable":
                path.chmod(0)
        if name == "aggregate":
            (folder / "background").write_bytes(b"second")
        try:
            with helper.OwnedPaths(sandbox) as owned, owned.locked():
                unit = helper.capture(owned)
                assert unit[2], name
                assert unit[0]["entries"]["backgrounds.json"]["kind"] == "unavailable", name
        finally:
            if name == "unreadable":
                path.chmod(0o600)
        print("persisted-inputs: unavailable=" + name)

    sandbox = fixture("changed-acquisition")
    folder = state(sandbox)
    path = folder / "backgrounds.json"
    path.write_bytes(b"before")
    original_read = os.read
    changed = False

    def changing_read(descriptor, size):
        global changed
        data = original_read(descriptor, size)
        if not changed:
            changed = True
            path.write_bytes(b"after-is-longer")
        return data

    with helper.OwnedPaths(sandbox) as owned, owned.locked(), patch.object(helper.os, "read", changing_read):
        unit = helper.capture(owned)
        assert unit[2] == ["backgrounds.json"], unit
        assert unit[0]["entries"]["backgrounds.json"]["operation"] == "changed"
    print("persisted-inputs: changed-acquisition=unavailable")

    sandbox = fixture("parent-replaced")
    folder = state(sandbox)
    (folder / "backgrounds.json").write_bytes(b"original")
    baseline = snapshot(sandbox, "start")
    def replaced_parent_restore():
        with helper.OwnedPaths(sandbox) as owned, owned.locked():
            owned.state()
            folder.rename(folder.with_name("removed"))
            folder.mkdir()
            require_refusal("changed", lambda: helper.restore(owned, helper.load(baseline)))

    require_refusal("changed", replaced_parent_restore)
    assert not list(folder.iterdir())
    print("persisted-inputs: replaced-parent=refused")

    sandbox = fixture("refused-publication")
    folder = state(sandbox)
    (folder / "backgrounds.json").write_bytes(b"original")
    baseline = snapshot(sandbox, "start")
    (folder / "backgrounds.json").unlink()
    (folder / "backgrounds.json").mkdir()
    with helper.OwnedPaths(sandbox) as owned, owned.locked():
        require_refusal("read", lambda: helper.restore(owned, helper.load(baseline)))
    assert (folder / "backgrounds.json").is_dir()
    print("persisted-inputs: special-replacement=refused")

    sandbox = fixture("partial-publication")
    folder = state(sandbox)
    (folder / "background").symlink_to("baseline-image")
    (folder / "backgrounds.json").write_bytes(b"baseline-json")
    baseline = snapshot(sandbox, "start")
    (folder / "background").unlink()
    (folder / "background").symlink_to("changed-image")
    (folder / "backgrounds.json").write_bytes(b"changed-json")
    original_replace = os.replace
    published = []

    def refused_replace(source, destination, **kwargs):
        published.append(destination)
        if destination == "backgrounds.json":
            raise OSError("publication-fault")
        return original_replace(source, destination, **kwargs)

    with helper.OwnedPaths(sandbox) as owned, owned.locked(), patch.object(helper.os, "replace", refused_replace):
        require_refusal("rename", lambda: helper.restore(owned, helper.load(baseline)))
    assert published == list(helper.NAMES)
    assert os.readlink(folder / "background") == "baseline-image"
    assert (folder / "backgrounds.json").read_bytes() == b"changed-json"
    assert not list(folder.glob(".smoke-selection-*"))
    print("persisted-inputs: partial-publication=failure-preserved order=link-json")

    sandbox = fixture("lock")
    reading = sandbox / "start"
    reading.mkdir()
    process = subprocess.Popen([sys.executable, str(PROGRAM), "capture", str(sandbox), str(reading), "--hold", "--bound", "3"],
                               env=ENV, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        # Parent bounds readiness as well as the helper's own alarm.
        import selectors
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            assert selector.select(4), "capture-readiness-deadline"
            assert process.stdout.readline() == "ready\n"
        second = sandbox / "second"
        second.mkdir()
        result = subprocess.run([sys.executable, str(PROGRAM), "capture", str(sandbox), str(second), "--bound", ".2"],
                                env=ENV, capture_output=True, text=True, timeout=2)
        assert result.returncode == 2 and "operation=busy" in result.stderr, result
        assert json.loads((second / helper.META).read_text())["entries"]["background"]["kind"] == "unavailable"
        output, error = process.communicate("release\n", timeout=4)
        assert process.returncode == 0, error
        with (sandbox / "home/.config/vgshell/theme.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    finally:
        if process.poll() is None:
            process.kill()
        process.wait(timeout=4)
    print("persisted-inputs: lock=exclusive bounded released")

    with helper.OwnedPaths(sandbox) as owned, owned.locked():
        lock_path = str(sandbox / "home/.config/vgshell/theme.lock")
        descriptors = []
        for item in Path("/proc/self/fd").iterdir():
            try:
                if os.readlink(item) == lock_path:
                    descriptors.append(int(item.name))
            except FileNotFoundError:
                continue
        assert descriptors, "held-lock-not-found"
        assert all(not os.get_inheritable(descriptor) for descriptor in descriptors), "lock-enters-child"
    print("persisted-inputs: lock-descriptor=close-on-exec")

    # The helper acknowledges capture while holding its real dirfds/lock.
    # Replacing the live parent before release must fail final verification.
    sandbox = fixture("held-parent-race")
    folder = state(sandbox)
    (folder / "backgrounds.json").write_bytes(b"before")
    reading = sandbox / "start"
    reading.mkdir()
    process = subprocess.Popen([sys.executable, str(PROGRAM), "capture", str(sandbox), str(reading), "--hold", "--bound", "3"],
                               env=ENV, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            assert selector.select(4), "parent-race-readiness-deadline"
            assert process.stdout.readline() == "ready\n"
        folder.rename(folder.with_name("old"))
        folder.mkdir()
        output, error = process.communicate("release\n", timeout=4)
        assert process.returncode == 2 and "operation=changed" in error, error
        assert not list(folder.iterdir())
        assert (reading / "persisted-backgrounds.json").read_bytes() == b"before"
    finally:
        if process.poll() is None:
            process.kill()
        process.wait(timeout=4)
    print("persisted-inputs: held-parent-replacement=terminal captured-bytes=retained")

    sandbox = fixture("fifo-target")
    folder = state(sandbox)
    target = sandbox / "external-fifo"
    os.mkfifo(target)
    (folder / "background").symlink_to(target)
    reading = sandbox / "start"
    reading.mkdir()
    result = subprocess.run([sys.executable, str(PROGRAM), "capture", str(sandbox), str(reading), "--bound", "2"],
                            env=ENV, capture_output=True, text=True, timeout=4)
    assert result.returncode == 0, result.stderr
    import base64
    item = json.loads((reading / helper.META).read_text())["entries"]["background"]
    assert item["kind"] == "symlink" and base64.b64decode(item["targetBase64"]) == os.fsencode(target)
    print("persisted-inputs: external-fifo-target=not-opened")

    # A real disposable implementation with its one restoration call removed
    # must fail the same exact-byte assertion, not merely a return-code check.
    sandbox = fixture("disabled-control")
    folder = state(sandbox)
    (folder / "backgrounds.json").write_bytes(b"baseline")
    baseline = snapshot(sandbox, "start")
    (folder / "backgrounds.json").write_bytes(b"changed")
    mutant = root / "disabled.py"
    source = PROGRAM.read_text()
    needle = "                    restore(paths, load(args.snapshot))"
    assert source.count(needle) == 1
    mutant.write_text(source.replace(needle, "                    pass # " + needle.strip()))
    receipt = sandbox / "receipt"
    receipt.mkdir()
    result = subprocess.run([sys.executable, str(mutant), "restore", str(sandbox), str(baseline), str(receipt)],
                            env=ENV, capture_output=True, text=True, timeout=4)
    assert result.returncode == 0, result.stderr
    try:
        exact(sandbox, baseline)
    except AssertionError as error:
        assert str(error) == "unit-not-restored", error
    else:
        raise AssertionError("disabled-restore-survived")
    print("persisted-inputs: control=disabled-restore-rejected")

    # The shipped boundary wrapper, scripts/smoke/leaks.sh `leak_inputs`,
    # run against a held theme lock: the helper's own deadline must win, so
    # its keyed line and its receipt land. The previous wrapper, whose
    # timeout ended the helper at the same bound, is the control.
    import re
    import selectors
    import shutil
    leaks = (REPO / "scripts/smoke/leaks.sh").read_text()
    wrapper = re.search(r"(?m)^leak_inputs\(\) \{.*\}$", leaks)
    assert wrapper, "leak_inputs-missing"
    bash = shutil.which("bash")
    assert bash, "bash-missing"

    def wrapped(function, sandbox, *words, **popen):
        script = function + '\nleak_inputs "$@"\n'
        command = [bash, "-c", script, "leak-inputs", *words]
        env = dict(ENV, repo=str(REPO), stop_lock_wait_s="1")
        if popen:
            return subprocess.Popen(command, env=env, text=True, **popen)
        return subprocess.run(command, env=env, capture_output=True, text=True, timeout=6)

    def held_capture(function, name):
        sandbox = fixture(name)
        state(sandbox)
        lock = sandbox / "home/.config/vgshell/theme.lock"
        lock.parent.mkdir(parents=True, exist_ok=True)
        reading = sandbox / "reading"
        reading.mkdir()
        with lock.open("a") as held:
            fcntl.flock(held, fcntl.LOCK_EX)
            result = wrapped(function, sandbox, "capture", str(sandbox), str(reading))
        receipt = reading / helper.META
        keyed = "qml-smoke: persisted-inputs=capture operation=busy cause=operation-deadline" in result.stderr
        unavailable = receipt.exists() and all(item["kind"] == "unavailable" for item in json.loads(receipt.read_text())["entries"].values())
        return result.returncode, keyed, unavailable

    status, keyed, unavailable = held_capture(wrapper.group(), "wrapper-held-lock")
    assert (status, keyed, unavailable) == (2, True, True), (status, keyed, unavailable)
    print("persisted-inputs: wrapper=helper-deadline-first keyed-line=landed receipt=unavailable")
    previous = wrapper.group().replace('timeout --signal=KILL "$(( ${stop_lock_wait_s:-10} + 2 ))"', 'timeout --kill-after=1 "${stop_lock_wait_s:-10}"')
    assert previous != wrapper.group()
    status, keyed, unavailable = held_capture(previous, "wrapper-equal-bound")
    assert not (keyed and unavailable), (status, keyed, unavailable)
    print("persisted-inputs: control=equal-outer-bound rejected")

    # A complete capture whose hold outlives the bound answers its own key,
    # never a refused reading, and its unit stays complete on disk.
    sandbox = fixture("hold-expired")
    (state(sandbox) / "backgrounds.json").write_bytes(b"held")
    reading = sandbox / "reading"
    reading.mkdir()
    process = wrapped(wrapper.group(), sandbox, "capture", str(sandbox), str(reading), "--hold",
                      stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            assert selector.select(4), "hold-readiness-deadline"
            assert process.stdout.readline() == "ready\n"
        # The owner keeps the hold open and sends no release.
        process.wait(timeout=6)
        error = process.stderr.read()
        assert process.returncode == 3, (process.returncode, error)
        assert re.search(r"(?m)^qml-smoke: persisted-inputs=hold-expired elapsed-ms=\d+$", error), error
        assert (reading / "persisted-backgrounds.json").read_bytes() == b"held"
        assert json.loads((reading / helper.META).read_text())["entries"]["backgrounds.json"]["kind"] == "regular"
    finally:
        if process.poll() is None:
            process.kill()
        process.wait(timeout=4)
        for stream in (process.stdin, process.stdout, process.stderr):
            stream.close()
    print("persisted-inputs: hold-expired=keyed unit=complete")
