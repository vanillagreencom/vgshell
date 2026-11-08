#!/usr/bin/env python3
"""The clipboard programs and the store's files for Service.qml, one verb a run.

    clipboard.py STORE capture
    clipboard.py STORE drop IMAGE...
    clipboard.py STORE sweep IMAGE...
    clipboard.py STORE save
    clipboard.py STORE copy MIME [IMAGE]

STORE is the plugin's state directory: `history.json` and `images/`, the
directories owner-only (0700) and every file owner-only (0600). IMAGE is an
image copy's id, which is its file's name under images/.

`wl-paste --watch` runs `capture` once for each copy, the first for the copy
on the clipboard as the watcher starts, with the copy's state in
CLIPBOARD_STATE and its data on stdin. Service.qml reads one JSON line from
stdout for each copy recorded:

    {"type": "text", "id": SHA256, "time": SECONDS, "text": TEXT}
    {"type": "image", "id": SHA256, "time": SECONDS, "mime": MIME}

The non-secret data transfer is read to its end, used directly when its type is
the recorded type, otherwise requesting that type after the first ends.
Over-size data is drained without keeping it, within the capture deadline.
An image's bytes are whole in images/<SHA256> before its line is printed. A
copy that is not recorded prints nothing and exits 0: a secret, an empty or
over-size copy, text that is not UTF-8 and a copy that offers neither plain
text nor an image.

`drop` deletes the named image files. `sweep` makes the directories, sets
the modes and deletes every file under images/ that is not named, a file a
killed capture left among them. `save` writes stdin as history.json through
a rename. `copy` puts stdin, or the image file IMAGE, on the clipboard as
MIME with wl-copy.

Exit 0 on success, 1 on a failure and 2 on a bad invocation, each with one
first line `clipboard: <key>=<value>` on stderr. No line holds copied data.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time

# A password manager adds this type to a copy it wants no history to keep,
# and wl-paste states such a copy as CLIPBOARD_STATE=sensitive.
SECRET_TYPE = "x-kde-passwordManagerHint"
# The largest text copy and the largest image copy recorded, in bytes.
TEXT_LIMIT = 1024 * 1024
IMAGE_LIMIT = 16 * 1024 * 1024
# A source application that never sends its data must not hold the watcher:
# capture ends itself this many seconds after it starts.
CAPTURE_SECONDS = 5
# The types that state plain text: `text/plain`, with or without a
# parameter, and its X11 names. Markup such as `text/html` is not among
# them: a browser offers it beside a copied image.
PLAIN_TEXT = ("text/plain", "TEXT", "STRING", "UTF8_STRING")
IMAGE_TYPE = re.compile(r"image/[a-z0-9][a-z0-9.+-]*")
IMAGE_NAME = re.compile(r"[0-9a-f]{64}")


class Refusal(Exception):
    """One keyed line for stderr and the exit status that goes with it."""

    def __init__(self, line, status=1):
        super().__init__(line)
        self.status = status


def images(store):
    return store / "images"


def image(store, name):
    """The file of the image copy NAME, an id and never a path."""
    if IMAGE_NAME.fullmatch(name) is None:
        raise Refusal("image=malformed", 2)
    return images(store) / name


def offered():
    """The types of the copy on the clipboard, read before any of its data."""
    listed = subprocess.run(["wl-paste", "--list-types"], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return listed.stdout.decode(errors="replace").split("\n") if listed.returncode == 0 else []


def offers_text(types):
    return any(kind in PLAIN_TEXT or kind.startswith("text/plain;") for kind in types)


def stdin_type(types):
    # Service.qml's watcher has no --type and its stdout is a pipe. Selection
    # is UTF-8 plain, plain, first textual type, then first offered type:
    # https://github.com/bugaevc/wl-clipboard/blob/v2.3.0/src/wl-paste.c#L143-L175
    # The textual heuristic (including markup and application types) is:
    # https://github.com/bugaevc/wl-clipboard/blob/v2.3.0/src/util/string.c#L26-L59
    for preferred in ("text/plain;charset=utf-8", "text/plain"):
        if preferred in types:
            return preferred
    return next((kind for kind in types if kind.startswith("text/") or kind in PLAIN_TEXT
                 or "json" in kind or kind.endswith(("script", "xml", "yaml", "csv", "ini", "pgp-keys"))
                 or "application/vnd.ms-publisher" in kind), next(iter(types), None))


def bounded(source, limit):
    """Read SOURCE to its end, keeping no bytes beyond LIMIT."""
    data = source.read(limit + 1)
    if len(data) <= limit:
        return data
    while source.read(1024 * 1024):
        pass
    return None


def emit(kind, digest, **fields):
    print(json.dumps({"type": kind, "id": digest, "time": int(time.time()), **fields}), flush=True)


def capture_text(source, reader):
    data = bounded(source, TEXT_LIMIT)
    if data is None or (reader is not None and reader.wait() != 0):
        return
    try:
        text = data.decode()
    except UnicodeDecodeError:
        return
    if text.strip() != "":
        emit("text", hashlib.sha256(data).hexdigest(), text=text)


def capture_image(store, mime, source, reader):
    """Stream the image into images/ under a private name, bounded as it arrives, then name it by its id."""
    handle, path = tempfile.mkstemp(prefix="incoming-", dir=images(store))
    digest, size, kept = hashlib.sha256(), 0, False
    try:
        with os.fdopen(handle, "wb") as out:
            while True:
                chunk = source.read(1024 * 1024)
                if not chunk:
                    break
                size += len(chunk)
                if size <= IMAGE_LIMIT:
                    digest.update(chunk)
                    out.write(chunk)
        kept = 0 < size <= IMAGE_LIMIT and (reader is None or reader.wait() == 0)
    finally:
        if not kept:
            os.unlink(path)
    if not kept:
        return
    os.replace(path, images(store) / digest.hexdigest())
    emit("image", digest.hexdigest(), mime=mime)


def capture(store):
    def expired(signum, frame):
        raise Refusal(f"capture=timeout seconds={CAPTURE_SECONDS}")
    signal.signal(signal.SIGALRM, expired)
    signal.alarm(CAPTURE_SECONDS)
    state = os.environ.get("CLIPBOARD_STATE")
    if state is None:
        # Only wl-paste ties a secret mark to the data on stdin. Without its
        # word the next copy's types could pass for this copy's.
        raise Refusal("clipboard-state=absent")
    # The secret check comes before any read of the copy's data: the copy's
    # own state first, then the types the clipboard offers now.
    if state != "data":
        return
    types = offered()
    if SECRET_TYPE in types:
        return
    incoming = stdin_type(types)
    if offers_text(types):
        mime = incoming if offers_text([incoming]) else next(kind for kind in types if offers_text([kind]))
    else:
        mime = next((kind for kind in types if IMAGE_TYPE.fullmatch(kind)), None)
    if mime is None:
        bounded(sys.stdin.buffer, 0)
        return
    reader = None
    try:
        source = sys.stdin.buffer
        if incoming != mime:
            # wl-copy can serve transfers serially: finish the handed one
            # before requesting a different type, without retaining it.
            bounded(source, 0)
            reader = subprocess.Popen(["wl-paste", "--no-newline", "--type", mime], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            source = reader.stdout
        if offers_text([mime]):
            capture_text(source, reader)
        else:
            capture_image(store, mime, source, reader)
    finally:
        if reader is not None:
            if reader.poll() is None:
                reader.kill()
            reader.wait()


def drop(store, names):
    for name in names:
        image(store, name).unlink(missing_ok=True)


def sweep(store, names):
    kept = {image(store, name).name for name in names}
    for folder in (store, images(store)):
        folder.mkdir(mode=0o700, parents=True, exist_ok=True)
        folder.chmod(0o700)
    history = store / "history.json"
    if history.exists():
        history.chmod(0o600)
    for entry in images(store).iterdir():
        if entry.name in kept:
            entry.chmod(0o600)
        else:
            entry.unlink()


def save(store):
    target = store / "history.json"
    pending = store / "history.json.next"
    # Made anew each time, so the mode it is made with is the mode it has.
    pending.unlink(missing_ok=True)
    handle = os.open(pending, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(handle, "wb") as out:
        out.write(sys.stdin.buffer.read())
        out.flush()
        os.fsync(out.fileno())
    os.replace(pending, target)


def copy(store, mime, name):
    """wl-copy forks its provider once the copy is set, so its exit is the answer."""
    if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.+;=/-]*", mime) is None:
        raise Refusal("mime=malformed", 2)
    source = sys.stdin if name is None else open(image(store, name), "rb")
    with source:
        # The provider outlives this helper; it holds none of its streams.
        status = subprocess.run(["wl-copy", "--type", mime], stdin=source, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
    if status != 0:
        raise Refusal(f"wl-copy=failed exit={status}")


def main(argv):
    if len(argv) < 3 or not os.path.isabs(argv[1]):
        raise Refusal("usage=STORE VERB [ARG...]", 2)
    store, verb, args = Path(argv[1]), argv[2], argv[3:]
    match verb, len(args):
        case "capture", 0:
            capture(store)
        case "drop", _:
            drop(store, args)
        case "sweep", _:
            sweep(store, args)
        case "save", 0:
            save(store)
        case "copy", 1 | 2:
            copy(store, args[0], args[1] if len(args) == 2 else None)
        case _:
            raise Refusal(f"verb={verb} args={len(args)}", 2)


if __name__ == "__main__":
    try:
        main(sys.argv)
    except Refusal as refusal:
        print(f"clipboard: {refusal}", file=sys.stderr)
        sys.exit(refusal.status)
    except OSError as error:
        print(f"clipboard: os-error={error.errno} {error.strerror}", file=sys.stderr)
        sys.exit(1)
