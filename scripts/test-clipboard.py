#!/usr/bin/env python3
"""The clipboard helper's verbs against stand-in wl-paste and wl-copy programs.

Every child runs with a private PATH that holds the two stand-ins alone, a
scratch store and no desktop, bus or Wayland variable, so no run reaches a
real clipboard. The stand-ins read one world file: the types the clipboard
offers, the bytes behind each type, and whether a read hangs, waits for the
writer on the helper's stdin or a copy fails. Each records its argv, so a
test reads which data the helper asked for.

Controls: each rule is removed from a copy of the helper, and the case that
holds the rule must then fail. The secret rule has one control for each of
its two triggers.
"""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parent.parent
HELPER = REPO / "shell/plugins/vgs.clipboard/helper/clipboard.py"
SECRET = "x-kde-passwordManagerHint"
TEXT_LIMIT = 1024 * 1024
IMAGE_LIMIT = 16 * 1024 * 1024
CAPTURE_SECONDS = 5

# A source's first transfer: SIZE bytes into stdout, the helper's stdin, and
# then one word in the file DONE: `sent` when a reader took them all,
# `closed` when the reader closed its end first.
WRITER = r'''import os, sys
from pathlib import Path
done, size, byte = Path(sys.argv[1]), int(sys.argv[2]), sys.argv[3].encode()
try:
    sys.stdout.buffer.write(byte * size)
    sys.stdout.buffer.flush()
    word = "sent"
except BrokenPipeError:
    word = "closed"
    os.dup2(os.open(os.devnull, os.O_WRONLY), 1)
done.write_text(word)
'''

STAND_IN = r'''#!%(python)s
import json, os, signal, sys, time
from pathlib import Path
root = Path(%(root)r)
tool = os.path.basename(sys.argv[0])
world = json.loads((root / "world.json").read_text())
with (root / "calls.jsonl").open("a") as log:
    log.write(json.dumps({"tool": tool, "args": sys.argv[1:]}) + "\n")
if tool == "wl-paste":
    if "--list-types" in sys.argv:
        if world.get("empty"):
            sys.exit("Nothing is copied")
        print("\n".join(world["types"]))
        sys.exit(0)
    mime = sys.argv[sys.argv.index("--type") + 1]
    if world.get("hang"):
        (root / "reader-pid").write_text(str(os.getpid()))
        while True:
            signal.pause()
    # A source that serves one transfer at a time: this read gets its data
    # once the transfer into the helper's stdin has ended.
    while world.get("afterWriter") and not (root / "writer-done").exists():
        time.sleep(0.01)
    if mime not in world["types"]:
        sys.exit("No suitable type of content copied")
    size = world.get("size", {}).get(mime)
    data = b"I" * size if size is not None else world["data"][mime].encode("latin-1")
    sys.stdout.buffer.write(data)
    sys.exit(world.get("pasteExit", 0))
if tool == "wl-copy":
    (root / "clipboard").write_bytes(sys.stdin.buffer.read())
    sys.exit(world.get("copyExit", 0))
sys.exit("stand-in: unknown tool " + tool)
'''


def plant(root, world):
    """A world: its stand-ins first and alone on PATH, and an empty call log."""
    (root / "bin").mkdir(parents=True, exist_ok=True)
    (root / "world.json").write_text(json.dumps(world))
    (root / "calls.jsonl").write_text("")
    for tool in ("wl-paste", "wl-copy"):
        path = root / "bin" / tool
        path.write_text(STAND_IN % {"python": sys.executable, "root": str(root)})
        path.chmod(0o755)


def run(root, helper, args, state=None, stdin=b"", timeout=30):
    env = {"PATH": str(root / "bin"), "HOME": str(root / "home"), "LC_ALL": "C", "VGS_TEST_RUN": "1"}
    if state is not None:
        env["CLIPBOARD_STATE"] = state
    done = subprocess.run([sys.executable, str(helper), str(root / "store"), *args], env=env, input=stdin, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    return done.returncode, done.stdout.decode(), done.stderr.decode()


def calls(root):
    return [json.loads(line) for line in (root / "calls.jsonl").read_text().splitlines()]


def payload_reads(root):
    """The wl-paste runs that asked for a copy's data."""
    return [call["args"] for call in calls(root) if call["tool"] == "wl-paste" and "--type" in call["args"]]


def mode(path):
    return stat.S_IMODE(path.stat().st_mode)


def image_files(root):
    folder = root / "store/images"
    return sorted(entry.name for entry in folder.iterdir()) if folder.exists() else []


def ready(root, helper):
    code, out, err = run(root, helper, ["sweep"])
    assert (code, out) == (0, ""), ("sweep", code, out, err)


# Each case answers whether its rule holds for HELPER in a fresh world ROOT.

# types, handed bytes, requested type (None uses stdin), stored type, stored bytes.
INPUTS = [
    (["text/html", "text/plain;charset=utf-8", "text/plain"], "héllo\n  wörld".encode(), None, "text", "héllo\n  wörld".encode()),
    (["text/plain;charset=ascii", "text/plain"], b"plain", None, "text", b"plain"),
    (["image/png", "STRING"], b"both", None, "text", b"both"),
    (["UTF8_STRING", "image/png"], b"utf8", None, "text", b"utf8"),
    (["TEXT", "image/png"], b"text", None, "text", b"text"),
    (["text/html", "STRING"], b"<b>markup</b>", "STRING", "text", b"plain"),
    (["text/html", "image/png"], b"<img>", "image/png", "image/png", b"PNG"),
    (["image/png", "text/html"], b"<img>", "image/png", "image/png", b"PNG"),
    (["image/jpeg", "image/png"], b"first image", None, "image/jpeg", b"first image"),
    (["application/x-other", "image/jpeg", "image/png"], b"other", "image/jpeg", "image/jpeg", b"JPEG"),
    (["image/png"], b"\x89PNG\r\n\x1a\nimage bytes", None, "image/png", b"\x89PNG\r\n\x1a\nimage bytes"),
    (["image/png", "application/json"], b"{}", "image/png", "image/png", b"PNG"),
    (["image/png", "application/javascript"], b"script", "image/png", "image/png", b"PNG"),
    (["image/png", "application/xml"], b"xml", "image/png", "image/png", b"PNG"),
    (["image/png", "application/yaml"], b"yaml", "image/png", "image/png", b"PNG"),
    (["image/png", "application/csv"], b"csv", "image/png", "image/png", b"PNG"),
    (["image/png", "application/ini"], b"ini", "image/png", "image/png", b"PNG"),
    (["image/png", "application/vnd.ms-publisher"], b"key", "image/png", "image/png", b"PNG"),
    (["image/png", "application/pgp-keys"], b"key", "image/png", "image/png", b"PNG"),
]


def input_types_are_recorded(root, helper):
    for index, (types, stdin, requested, stored, data) in enumerate(INPUTS):
        case = root / str(index)
        plant(case, {"types": types, "data": {requested: data.decode("latin-1")} if requested else {}})
        ready(case, helper)
        code, out, err = run(case, helper, ["capture"], "data", stdin)
        lines = out.splitlines()
        if code != 0 or len(lines) != 1:
            return False
        line = json.loads(lines[0])
        digest = hashlib.sha256(data).hexdigest()
        reads = [["--no-newline", "--type", requested]] if requested else []
        kind = "text" if stored == "text" else "image"
        field = "text" if kind == "text" else "mime"
        value = data.decode() if kind == "text" else stored
        if not (set(line) == {"type", "id", "time", field} and line["type"] == kind and line[field] == value
                and line["id"] == digest and isinstance(line["time"], int) and payload_reads(case) == reads
                and image_files(case) == ([] if kind == "text" else [digest])):
            return False
        if kind == "image":
            final = case / "store/images" / digest
            if final.read_bytes() != data or mode(final) != 0o600:
                return False
    return True


# The handed transfer exceeds a pipe in every row. A serial source sends a
# requested image only after that transfer ends. Normal runs wait on progress;
# a broken control is bounded by the helper and the parent process deadline.
TRANSFERS = [
    ("first image delivery", ["image/png"], 128 * 1024, "I", True, False),
    ("image behind markup", ["text/html", "image/png"], 128 * 1024, "F", True, True),
    ("oversize text", ["text/plain"], TEXT_LIMIT + 128 * 1024, "F", False, False),
    ("oversize image", ["image/png"], IMAGE_LIMIT + 2 * 1024 * 1024, "I", False, False),
]


def image_behind_a_blocked_transfer_is_recorded(root, helper):
    for index, (label, types, size, byte, recorded, requested) in enumerate(TRANSFERS):
        case = root / str(index)
        source, sink = os.pipe()
        # The stopped reader's remaining bytes must exceed both its last
        # buffered read and this pipe's capacity, or the writer can finish
        # without the drain. Keep the table's overflow margins as well.
        size += 2 * fcntl.fcntl(source, fcntl.F_GETPIPE_SZ)
        plant(case, {"types": types, "size": {"image/png": size}, "afterWriter": True})
        ready(case, helper)
        env = {"PATH": str(case / "bin"), "HOME": str(case / "home"), "LC_ALL": "C", "VGS_TEST_RUN": "1", "CLIPBOARD_STATE": "data"}
        writer = subprocess.Popen([sys.executable, "-c", WRITER, str(case / "writer-done"), str(size), byte], env=env, stdin=subprocess.DEVNULL, stdout=sink)
        os.close(sink)
        capture = subprocess.Popen([sys.executable, str(helper), str(case / "store"), "capture"], env=env, stdin=source, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        os.close(source)
        try:
            out, err = capture.communicate(timeout=CAPTURE_SECONDS + 3)
        finally:
            capture.kill()
            capture.wait()
            writer.wait(timeout=30)
        digest = hashlib.sha256(b"I" * size).hexdigest()
        lines = out.decode().splitlines()
        if not (capture.returncode == 0 and (case / "writer-done").read_text() == "sent"
                and payload_reads(case) == ([["--no-newline", "--type", "image/png"]] if requested else [])
                and image_files(case) == ([digest] if recorded else [])):
            return False
        if (recorded and (len(lines) != 1 or json.loads(lines[0])["id"] != digest)) or (not recorded and lines):
            return False
    return True


def nothing_recorded(root, helper, world, state, stdin=b"", reads=None):
    """The helper prints nothing, keeps no file and reads only the data READS names."""
    plant(root, world)
    ready(root, helper)
    code, out, err = run(root, helper, ["capture"], state, stdin)
    return code == 0 and out == "" and image_files(root) == [] and payload_reads(root) == (reads or [])


def sensitive_state_is_skipped(root, helper):
    return nothing_recorded(root, helper, {"types": ["text/plain"]}, "sensitive", b"hunter2")


def secret_type_is_skipped(root, helper):
    return (nothing_recorded(root / "text", helper, {"types": ["text/plain", SECRET]}, "data", b"hunter2")
            and nothing_recorded(root / "image", helper, {"types": ["image/png", SECRET], "data": {"image/png": "secret image"}}, "data"))


def absent_state_is_refused(root, helper):
    plant(root, {"types": ["text/plain"]})
    ready(root, helper)
    code, out, err = run(root, helper, ["capture"], None, b"text")
    return code == 1 and out == "" and err.splitlines()[:1] == ["clipboard: clipboard-state=absent"] and calls(root) == []


def text_limit_holds(root, helper):
    plant(root / "at", {"types": ["text/plain"]})
    ready(root / "at", helper)
    code, out, err = run(root / "at", helper, ["capture"], "data", b"a" * TEXT_LIMIT)
    return (code == 0 and len(json.loads(out)["text"]) == TEXT_LIMIT
            and nothing_recorded(root / "over", helper, {"types": ["text/plain"]}, "data", b"a" * (TEXT_LIMIT + 1)))


def image_limit_holds(root, helper):
    plant(root / "at", {"types": ["image/png"], "size": {"image/png": IMAGE_LIMIT}})
    ready(root / "at", helper)
    code, out, err = run(root / "at", helper, ["capture"], "data", b"I" * IMAGE_LIMIT)
    return (code == 0 and json.loads(out)["type"] == "image" and (root / "at/store/images" / json.loads(out)["id"]).stat().st_size == IMAGE_LIMIT
            and nothing_recorded(root / "over", helper, {"types": ["image/png"]}, "data", b"I" * (IMAGE_LIMIT + 1)))


def stalled_source_ends(root, helper):
    """A real wait: the helper's own deadline is what the case reads."""
    plant(root, {"types": ["text/html", "image/png"], "hang": True})
    ready(root, helper)
    try:
        code, out, err = run(root, helper, ["capture"], "data", timeout=CAPTURE_SECONDS + 3)
    except subprocess.TimeoutExpired:
        code, out, err = None, "", ""
    # The helper ends the reader it started; one still alive is ended here.
    reader_left = True
    try:
        os.kill(int((root / "reader-pid").read_text()), 9)
    except ProcessLookupError:
        reader_left = False
    return (not reader_left and code == 1 and out == ""
            and err.splitlines()[:1] == [f"clipboard: capture=timeout seconds={CAPTURE_SECONDS}"] and image_files(root) == [])


def store_is_owner_only(root, helper):
    store = root / "store"
    (store / "images").mkdir(parents=True)
    store.chmod(0o755)
    (store / "images").chmod(0o755)
    (store / "history.json").write_text("{}")
    (store / "history.json").chmod(0o644)
    kept = "a" * 64
    for name in (kept, "b" * 64, "incoming-stale"):
        (store / "images" / name).write_text(name)
        (store / "images" / name).chmod(0o644)
    plant(root, {"types": []})
    code, out, err = run(root, helper, ["sweep", kept])
    return ((code, out) == (0, "") and mode(store) == 0o700 and mode(store / "images") == 0o700 and mode(store / "history.json") == 0o600
            and image_files(root) == [kept] and mode(store / "images" / kept) == 0o600)


def save_is_owner_only(root, helper):
    plant(root, {"types": []})
    ready(root, helper)
    os.umask(0o022)
    for content in (b'{"entries": []}\n', b'{"entries": [1]}\n'):
        code, out, err = run(root, helper, ["save"], stdin=content)
        target = root / "store/history.json"
        if (code, out) != (0, "") or target.read_bytes() != content or mode(target) != 0o600:
            return False
    return sorted(entry.name for entry in (root / "store").iterdir()) == ["history.json", "images"]


def names_are_no_paths(root, helper):
    plant(root, {"types": []})
    ready(root, helper)
    history = root / "store/history.json"
    history.write_text("kept")
    gone = "c" * 64
    (root / "store/images" / gone).write_text("x")
    code, out, err = run(root, helper, ["drop", gone, "d" * 64])
    if (code, out) != (0, "") or image_files(root) != []:
        return False
    refused = [["drop", "../history.json"], ["sweep", "../history.json"], ["copy", "image/png", "../history.json"]]
    for args in refused:
        code, out, err = run(root, helper, args)
        if code != 2 or out != "" or not err.startswith("clipboard: ") or history.read_text() != "kept":
            return False
    return True


def copy_reaches_wl_copy(root, helper):
    plant(root, {"types": []})
    ready(root, helper)
    code, out, err = run(root, helper, ["copy", "text/plain;charset=utf-8"], stdin="tëxt".encode())
    if (code, out) != (0, "") or (root / "clipboard").read_bytes() != "tëxt".encode() or calls(root)[-1] != {"tool": "wl-copy", "args": ["--type", "text/plain;charset=utf-8"]}:
        return False
    name = "e" * 64
    (root / "store/images" / name).write_bytes(b"\x89PNG image")
    code, out, err = run(root, helper, ["copy", "image/png", name])
    if (code, out) != (0, "") or (root / "clipboard").read_bytes() != b"\x89PNG image" or calls(root)[-1] != {"tool": "wl-copy", "args": ["--type", "image/png"]}:
        return False
    plant(root, {"types": [], "copyExit": 3})
    code, out, err = run(root, helper, ["copy", "text/plain;charset=utf-8"], stdin=b"text")
    return code == 1 and out == "" and err.splitlines()[:1] == ["clipboard: wl-copy=failed exit=3"]


# Copies that record nothing, each { label: (world, state, stdin, payload reads) }.
SKIPPED = {
    "an empty clipboard": ({"types": []}, "nil", b"", None),
    "a cleared clipboard": ({"types": []}, "clear", b"", None),
    "a state the helper does not know": ({"types": ["text/plain"]}, "later", b"text", None),
    "types that cannot be read": ({"empty": True}, "data", b"text", None),
    "white space alone": ({"types": ["text/plain"]}, "data", b" \n\t", None),
    "text that is not UTF-8": ({"types": ["text/plain"]}, "data", b"\x89PNG\r\n", None),
    "neither text nor an image": ({"types": ["application/pdf"]}, "data", b"%PDF", None),
    "markup alone": ({"types": ["text/html"]}, "data", b"<b>bold</b>", None),
    "an empty image": ({"types": ["image/png"], "size": {"image/png": 0}}, "data", b"", None),
    "an image the source fails to send": ({"types": ["image/png"], "pasteExit": 1}, "data", b"", None),
    "a failed requested image": ({"types": ["text/html", "image/png"], "data": {"image/png": "part"}, "pasteExit": 1}, "data", b"<img>", [["--no-newline", "--type", "image/png"]]),
}

CASES = [
    ("the handed type and recorded type select the data read", input_types_are_recorded),
    ("first and oversize transfers complete before an image request", image_behind_a_blocked_transfer_is_recorded),
    ("a sensitive copy is skipped", sensitive_state_is_skipped),
    ("a copy with the secret type is skipped", secret_type_is_skipped),
    ("a copy without a state is refused", absent_state_is_refused),
    ("the text ceiling holds", text_limit_holds),
    ("the image ceiling holds", image_limit_holds),
    ("a stalled source ends the capture", stalled_source_ends),
    ("the store is owner-only", store_is_owner_only),
    ("a saved history is owner-only", save_is_owner_only),
    ("a file name is never a path", names_are_no_paths),
    ("a copy reaches wl-copy with its type", copy_reaches_wl_copy),
]

# Each control: the case it must fail, the text removed and what replaces it.
CONTROLS = [
    ("secret-state", sensitive_state_is_skipped, '    if state != "data":\n        return\n', '    if state not in ("data", "sensitive"):\n        return\n'),
    ("secret-type", secret_type_is_skipped, "    if SECRET_TYPE in types:\n        return\n", "    if False:\n        return\n"),
    ("absent-state", absent_state_is_refused, "    if state is None:\n", "    if False:\n"),
    ("image-before-text", input_types_are_recorded, "    if offers_text(types):\n", "    if offers_text(types) and not any(IMAGE_TYPE.fullmatch(kind) for kind in types):\n"),
    ("markup-as-text", input_types_are_recorded, '    return any(kind in PLAIN_TEXT or kind.startswith("text/plain;") for kind in types)\n', '    return any(kind in PLAIN_TEXT or kind.startswith("text/") for kind in types)\n'),
    ("first-image-type", input_types_are_recorded, "        mime = next((kind for kind in types if IMAGE_TYPE.fullmatch(kind)), None)\n", "        mime = next((kind for kind in reversed(types) if IMAGE_TYPE.fullmatch(kind)), None)\n"),
    ("unnamed-image", input_types_are_recorded, "    os.replace(path, images(store) / digest.hexdigest())\n", "    os.replace(path, path)\n"),
    ("unread-first-transfer", image_behind_a_blocked_transfer_is_recorded, "            bounded(source, 0)\n", "            os.close(source.fileno())\n"),
    ("second-image-transfer", input_types_are_recorded, "        if incoming != mime:\n", "        if True:\n"),
    ("undrained-text", image_behind_a_blocked_transfer_is_recorded, "    while source.read(1024 * 1024):\n        pass\n", "    if False:\n        source.read(1024 * 1024)\n"),
    ("undrained-image", image_behind_a_blocked_transfer_is_recorded, "            while True:\n", "            while size <= IMAGE_LIMIT:\n"),
    ("text-ceiling", text_limit_holds, "TEXT_LIMIT = 1024 * 1024\n", "TEXT_LIMIT = 2 * 1024 * 1024\n"),
    ("image-ceiling", image_limit_holds, "IMAGE_LIMIT = 16 * 1024 * 1024\n", "IMAGE_LIMIT = 32 * 1024 * 1024\n"),
    ("no-deadline", stalled_source_ends, "    signal.alarm(CAPTURE_SECONDS)\n", "    signal.alarm(0)\n"),
    ("open-folders", store_is_owner_only, "        folder.chmod(0o700)\n", "        folder.chmod(0o755)\n"),
    ("unswept-files", store_is_owner_only, "        else:\n            entry.unlink()\n", "        else:\n            pass\n"),
    ("open-history", save_is_owner_only, "os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)", "os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)"),
    ("path-names", names_are_no_paths, "    if IMAGE_NAME.fullmatch(name) is None:\n", "    if False:\n"),
    ("untyped-copy", copy_reaches_wl_copy, '["wl-copy", "--type", mime]', '["wl-copy"]'),
]


def main():
    with tempfile.TemporaryDirectory(prefix="clipboard-test-") as temp:
        base = Path(temp).resolve()
        for label, case in CASES:
            assert case(base / "cases" / case.__name__, HELPER), label
        for index, (label, (world, state, stdin, reads)) in enumerate(SKIPPED.items()):
            assert nothing_recorded(base / "skipped" / str(index), HELPER, world, state, stdin, reads), label
        code, out, err = run(base / "cases" / "usage", HELPER, ["reverse"])
        assert code == 2 and err.splitlines()[:1] == ["clipboard: verb=reverse args=0"], ("usage", code, err)
        source = HELPER.read_text()
        for name, case, before, after in CONTROLS:
            assert source.count(before) == 1, f"control {name}: the text to replace must occur once"
            mutant = base / "controls" / name / "clipboard.py"
            mutant.parent.mkdir(parents=True)
            mutant.write_text(source.replace(before, after))
            assert not case(base / "controls" / name / "world", mutant), f"control did not fail: {name}"
    print("test-clipboard: pass; controls=" + ",".join(name for name, _, _, _ in CONTROLS))


if __name__ == "__main__":
    main()
