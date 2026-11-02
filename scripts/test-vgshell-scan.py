#!/usr/bin/env python3
"""One temp tree per row for bin/vgshell-scan. Each listing row plants files
under a throwaway directory, removes permission bits where the row says so,
runs the scanner on the named base with the row's options, and asserts the
JSON elements it prints (the dir, either a text entry or the start of the
error, and the failing path where the row names one) plus the exit status.
The revision rows then read the scanner twice over one tree and compare
revisions, snapshots and pruning. The probe rows run the scanner with a PATH
of one stub directory and read each plugin's `missing` list. The D-Bus rows
run it against a private dbus-daemon and read owned, activatable and absent
names; their controls answer every name present and ignore activatable names.
The command probe control runs rows against a copy of the scanner that finds every command. The core
rows probe a --core requirements file beside a plugin; their control reads
that file as a manifest. The version rows run --versions with a PATH of
stub programs and read each command's line, or null with the cause its
stderr line names; one row runs a copy whose bound is one second against a
program that never ends. Their controls keep every line, pass no argument,
read a failed command, hand down the whole environment, start in the
scanner's directory, run a path and leave the stalled program alone. The core watch rows run --watch-core with bounded
pipe reads and prove edits to core files and new directories produce one
changed revision while the top-level plugins directory is neither watched
nor hashed. The URL rows publish a snapshot under a root whose
path needs quoting, and run a scan in a child interpreter that reports
whether urllib.request was imported; their controls quote nothing and spell
the URL through pathlib's as_uri. Permission rows need a uid that
permissions bind; under euid 0 the script reports status=not-measured and
exits 77 instead of passing vacuously."""
import importlib.machinery
import importlib.util
import fcntl
import json
import os
import pathlib
import select
import signal
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from unittest import mock

SCAN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bin", "vgshell-scan")
MANIFEST = '{"id": "acme.widget"}'
ENV = {"PATH": os.environ.get("PATH", ""), "LC_ALL": "C"}
# listing rows: name, files {relative path: text or bytes}, modes {relative path: mode}, base (relative),
# want [(dir, "text" | "error:<prefix>"[, failing path])], options, links {relative path: target}
ROWS = [
    ("absent base is skipped", {}, {}, "plugins", []),
    ("absent base under --require-base is an error", {}, {}, "plugins", [("plugins", "error:cannot list: ", "plugins")], ["--require-base"]),
    ("base that is a file is an error", {"plugins": "x"}, {}, "plugins", [("plugins", "error:cannot list: ")]),
    ("plugin dir without a manifest is skipped", {"plugins/a/Widget.qml": ""}, {}, "plugins", []),
    ("entry that is a file is skipped", {"plugins/README": ""}, {}, "plugins", []),
    ("readable manifest is a text entry", {"plugins/a/manifest.json": MANIFEST}, {}, "plugins", [("plugins/a", "text")]),
    ("plugin dir without its search bit is an error", {"plugins/a/manifest.json": MANIFEST, "plugins/b/manifest.json": MANIFEST}, {"plugins/a": 0o000}, "plugins",
     [("plugins/a", "error:cannot read manifest: ", "plugins/a/manifest.json"), ("plugins/b", "text")]),
    ("manifest without read permission is an error", {"plugins/a/manifest.json": MANIFEST}, {"plugins/a/manifest.json": 0o000}, "plugins",
     [("plugins/a", "error:cannot read manifest: ", "plugins/a/manifest.json")]),
    ("base without permission bits is an error", {"plugins/a/manifest.json": MANIFEST}, {"plugins": 0o000}, "plugins", [("plugins", "error:cannot list: ")]),
    ("inaccessible ancestor of the base is an error", {"root/plugins/a/manifest.json": MANIFEST}, {"root": 0o000}, "root/plugins", [("root/plugins", "error:cannot list: ")]),
    ("unreadable source file inside a plugin names the file", {"plugins/a/manifest.json": MANIFEST, "plugins/a/lib/Helper.qml": ""}, {"plugins/a/lib/Helper.qml": 0o000}, "plugins",
     [("plugins/a", "error:cannot read source: ", "plugins/a/lib/Helper.qml")]),
    ("unreadable directory inside a plugin names the directory", {"plugins/a/manifest.json": MANIFEST, "plugins/a/lib/Helper.qml": ""}, {"plugins/a/lib": 0o000}, "plugins",
     [("plugins/a", "error:cannot read source: ", "plugins/a/lib")]),
    ("manifest that is not UTF-8 is an error", {"plugins/a/manifest.json": b"\xff{}"}, {}, "plugins", [("plugins/a", "error:manifest is not UTF-8: ", "plugins/a/manifest.json")]),
    ("symbolic link cycle inside a plugin is an error", {"plugins/a/manifest.json": MANIFEST}, {}, "plugins", [("plugins/a", "error:cannot read source: directory cycle", "plugins/a/loop")], [], {"plugins/a/loop": "."}),
    ("entry that is neither a file nor a directory is an error", {"plugins/a/manifest.json": MANIFEST}, {}, "plugins", [("plugins/a", "error:cannot read source: not a regular file", "plugins/a/null")], [], {"plugins/a/null": "/dev/null"}),
    ("a symbolic link to a file is read as that file", {"plugins/a/manifest.json": MANIFEST, "shared/Helper.qml": "Item {}"}, {}, "plugins", [("plugins/a", "text")], [], {"plugins/a/Helper.qml": "../../shared/Helper.qml"}),
]


def element_kind(element):
    if "text" in element:
        return "text"
    return "error:" + element["error"]


def matches(got, want):
    if len(got) != len(want):
        return False
    for (got_dir, got_kind, got_path), want_row in zip(got, want):
        want_dir, want_kind = want_row[0], want_row[1]
        if got_dir != want_dir:
            return False
        if want_kind == "text" and got_kind != "text":
            return False
        if want_kind != "text" and not got_kind.startswith(want_kind):
            return False
        if len(want_row) == 3 and got_path != want_row[2]:
            return False
    return True


def plant(tmp, files, links=None):
    for rel, text in files.items():
        path = os.path.join(tmp, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as fh:
            fh.write(text if isinstance(text, bytes) else text.encode("utf-8"))
    for rel, target in (links or {}).items():
        path = os.path.join(tmp, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        os.symlink(target, path)


def scan(*args, script=SCAN, env=ENV):
    return subprocess.run([sys.executable, script, *args], capture_output=True, text=True, check=False, env=env)


def run_row(name, files, modes, base, want, options=(), links=None):
    with tempfile.TemporaryDirectory() as tmp:
        plant(tmp, files, links)
        try:
            for rel, mode in modes.items():
                os.chmod(os.path.join(tmp, rel), mode)
            proc = scan(*options, os.path.join(tmp, base))
        finally:
            for rel in modes:
                os.chmod(os.path.join(tmp, rel), 0o755)
        try:
            elements = json.loads(proc.stdout)
        except ValueError:
            elements = None
        got = None if elements is None else [(os.path.relpath(e["dir"], tmp), element_kind(e), os.path.relpath(e["path"], tmp) if "path" in e else None) for e in elements]
        good = proc.returncode == 0 and got is not None and matches(got, want)
        return report(name, good, f" (exit={proc.returncode} got={got})\n{proc.stdout}{proc.stderr}")


def report(name, good, detail=""):
    print(("  ok    " if good else "  FAIL  ") + name + ("" if good else detail))
    return good


def one_entry(proc):
    """The single element a clean scan of one plugin prints, or None."""
    if proc.returncode != 0:
        return None
    elements = json.loads(proc.stdout)
    if len(elements) != 1 or "error" in elements[0]:
        return None
    return elements[0]


def revision_rows():
    """Revisions, snapshots and pruning, read back from one tree the rows edit in place."""
    results = []
    with tempfile.TemporaryDirectory() as tmp:
        base = os.path.join(tmp, "plugins")
        plugin = os.path.join(base, "a")
        root = os.path.join(tmp, "snapshots")
        plant(tmp, {"plugins/a/manifest.json": MANIFEST, "plugins/a/Widget.qml": "import QtQuick\nItem {}\n", "plugins/a/lib/Helper.qml": "Item {}\n", "plugins/a/.git/HEAD": "ref: refs/heads/main\n"})
        first = one_entry(scan(base))
        again = one_entry(scan(base))
        results.append(report("the same bytes give the same revision", first is not None and again is not None and first["revision"] == again["revision"] and first["text"] == MANIFEST, f"\n{first}\n{again}"))
        with open(os.path.join(plugin, ".git", "HEAD"), "w", encoding="utf-8") as fh:
            fh.write("ref: refs/heads/other\n")
        results.append(report("a change under .git keeps the revision", one_entry(scan(base))["revision"] == first["revision"]))
        with open(os.path.join(plugin, "lib", "Helper.qml"), "w", encoding="utf-8") as fh:
            fh.write("Item { property int edited: 1 }\n")
        second = one_entry(scan(base))
        results.append(report("an edit to a sibling file changes the revision and keeps the manifest text", second["revision"] != first["revision"] and second["text"] == MANIFEST))
        os.chmod(os.path.join(plugin, "Widget.qml"), 0o755)
        third = one_entry(scan(base))
        results.append(report("an executable bit changes the revision", third["revision"] not in (first["revision"], second["revision"])))

        published = one_entry(scan("--snapshot-dir", root, base))
        snapshot = os.path.join(root, third["revision"])
        results.append(report("a snapshot is published under its revision and named by loadUrl", published["loadUrl"] == pathlib.Path(snapshot).as_uri() and os.path.isdir(snapshot)))
        try:
            with open(os.path.join(snapshot, "lib", "Helper.qml"), "rb") as fh:
                helper = fh.read()
            same_bytes = helper == b"Item { property int edited: 1 }\n"
            executable = os.access(os.path.join(snapshot, "Widget.qml"), os.X_OK) and not os.access(os.path.join(snapshot, "manifest.json"), os.X_OK)
            no_git = not os.path.exists(os.path.join(snapshot, ".git"))
        except OSError as exc:
            same_bytes = executable = no_git = False
            print(f"        snapshot unreadable: {exc}")
        results.append(report("the snapshot holds every source file's bytes and executable bit and no .git", same_bytes and executable and no_git))

        with open(os.path.join(plugin, "Widget.qml"), "w", encoding="utf-8") as fh:
            fh.write("import QtQuick\nItem { property int v: 2 }\n")
        fourth = one_entry(scan("--snapshot-dir", root, "--retain", third["revision"], base))
        listed = sorted(os.listdir(root))
        results.append(report("a retained revision survives the scan that publishes the next one", listed == sorted([third["revision"], fourth["revision"]]), f"\n{listed}"))
        os.mkdir(os.path.join(root, ".writing-stale"))
        fifth = one_entry(scan("--snapshot-dir", root, base))
        listed = sorted(os.listdir(root))
        results.append(report("a scan with no error prunes unretained revisions and half-written trees", fifth["revision"] == fourth["revision"] and listed == [fourth["revision"]], f"\n{listed}"))

        with open(os.path.join(plugin, "lib", "Helper.qml"), "w", encoding="utf-8") as fh:
            fh.write("Item { property int edited: 3 }\n")
        os.chmod(os.path.join(plugin, "lib", "Helper.qml"), 0o000)
        try:
            failed = scan("--snapshot-dir", root, base)
        finally:
            os.chmod(os.path.join(plugin, "lib", "Helper.qml"), 0o644)
        elements = json.loads(failed.stdout) if failed.returncode == 0 else []
        listed = sorted(os.listdir(root))
        results.append(report("a scan with an error publishes nothing and prunes nothing", len(elements) == 1 and "error" in elements[0] and listed == [fourth["revision"]], f"\n{failed.stdout}\n{listed}"))
        results.append(report("a retained revision that is not on disk is not an error", one_entry(scan("--snapshot-dir", root, "--retain", "0" * 64, base)) is not None))
        refused = scan("--retain", "x", base)
        results.append(report("--retain without --snapshot-dir is refused", refused.returncode == 2 and refused.stdout == ""))
    return results


def migration_rows(script=SCAN, quiet=False):
    results = []
    for name, files, modes, expected in [
        ("executable migration entry", {"migrate": "#!/bin/sh\nexit 0\n"}, {"migrate": 0o755}, True),
        ("non-executable migration entry", {"migrate": "exit 0\n"}, {}, False),
        ("absent migration entry", {}, {}, False),
        ("nested migration executable", {"bin/migrate": "exit 0\n"}, {"bin/migrate": 0o755}, False),
    ]:
        with tempfile.TemporaryDirectory() as tmp:
            plant(tmp, {"plugins/a/manifest.json": MANIFEST, **{"plugins/a/" + key: value for key, value in files.items()}})
            for relative, mode in modes.items():
                os.chmod(os.path.join(tmp, "plugins/a", relative), mode)
            entry = one_entry(scan("--snapshot-dir", os.path.join(tmp, "snapshots"), os.path.join(tmp, "plugins"), script=script))
            good = entry is not None and (entry.get("migrate") is True if expected else "migrate" not in entry)
            if good and expected:
                published = os.path.join(tmp, "snapshots", entry["revision"], "migrate")
                good = os.access(published, os.X_OK) and pathlib.Path(published).read_text() == files["migrate"]
            results.append(good if quiet else report(name, good, str(entry)))
    return results


def requirement(command):
    return {"command": command, "purpose": "p"}


# probe rows: name, {plugin dir: manifest text}, {plugin dir: missing list}.
# The stub PATH holds `here` (executable) and `inert` (not executable).
PROBE_ROWS = [
    ("a declared command on PATH is not missing", {"a": {"id": "acme.a", "requirements": [requirement("here")]}}, {"a": []}),
    ("a declared command absent from PATH is missing", {"a": {"id": "acme.a", "requirements": [requirement("gone")]}}, {"a": ["gone"]}),
    ("a file without its executable bit is missing", {"a": {"id": "acme.a", "requirements": [requirement("inert")]}}, {"a": ["inert"]}),
    ("missing keeps declaration order and names a command once", {"a": {"id": "acme.a", "requirements": [requirement("zeta"), requirement("here"), requirement("alpha"), requirement("zeta")]}}, {"a": ["zeta", "alpha"]}),
    ("two plugins declaring one command both report it", {"a": {"id": "acme.a", "requirements": [requirement("gone")]}, "b": {"id": "acme.b", "requirements": [requirement("gone"), requirement("here")]}}, {"a": ["gone"], "b": ["gone"]}),
    ("a manifest without requirements misses nothing", {"a": {"id": "acme.a"}}, {"a": []}),
    ("requirements that are not a list miss nothing", {"a": {"id": "acme.a", "requirements": {"command": "gone"}}}, {"a": []}),
    ("an entry without a string command is not probed", {"a": {"id": "acme.a", "requirements": ["gone", {"command": 3}, {"purpose": "p"}]}}, {"a": []}),
    ("a manifest that is not JSON misses nothing", {"a": "{not json"}, {"a": []}),
]


DBUS_ROWS = [
    ("an owned session bus name is present", {"a": {"id": "acme.a", "requirements": [{"dbus": {"bus": "session", "name": "org.vgshell.Owned"}, "purpose": "p"}]}}, {"a": []}, "owned"),
    ("an activatable session bus name is present", {"a": {"id": "acme.a", "requirements": [{"dbus": {"bus": "session", "name": "org.vgshell.Activatable"}, "purpose": "p"}]}}, {"a": []}, "activatable"),
    ("an unowned non-activatable session bus name is missing", {"a": {"id": "acme.a", "requirements": [{"dbus": {"bus": "session", "name": "org.vgshell.Missing"}, "purpose": "p"}]}}, {"a": ["org.vgshell.Missing"]}, "plain"),
    ("a failed bus probe reports the D-Bus name missing", {"a": {"id": "acme.a", "requirements": [{"dbus": {"bus": "session", "name": "org.vgshell.Missing"}, "purpose": "p"}]}}, {"a": ["org.vgshell.Missing"]}, "failed"),
]


def probe_rows(script=SCAN, quiet=False):
    """Each probe row's verdict, run against SCRIPT."""
    results = []
    for name, manifests, want in PROBE_ROWS:
        with tempfile.TemporaryDirectory() as tmp:
            files = {os.path.join("plugins", d, "manifest.json"): (m if isinstance(m, str) else json.dumps(m)) for d, m in manifests.items()}
            files["stubs/here"] = "#!/bin/sh\n"
            files["stubs/inert"] = "#!/bin/sh\n"
            plant(tmp, files)
            os.chmod(os.path.join(tmp, "stubs", "here"), 0o755)
            os.chmod(os.path.join(tmp, "stubs", "inert"), 0o644)
            proc = scan(os.path.join(tmp, "plugins"), script=script, env={"PATH": os.path.join(tmp, "stubs"), "LC_ALL": "C"})
            try:
                got = {os.path.basename(e["dir"]): e.get("missing") for e in json.loads(proc.stdout)}
            except (ValueError, KeyError):
                got = None
            good = proc.returncode == 0 and got == want
            results.append(good if quiet else report(name, good, f" (exit={proc.returncode} got={got})\n{proc.stderr}"))
    return results


def mutant_control(label, needle, replacement, rows):
    """The rows ROWS(script, quiet) runs must fail on a copy of the scanner
    with NEEDLE, which occurs once, replaced by REPLACEMENT."""
    with open(SCAN, encoding="utf-8") as fh:
        source = fh.read()
    if source.count(needle) != 1:
        return report(f"control: {needle!r} occurs once in the scanner", False, f" (count={source.count(needle)})")
    with tempfile.TemporaryDirectory() as tmp:
        mutant = os.path.join(tmp, "vgshell-scan")
        with open(mutant, "w", encoding="utf-8") as fh:
            fh.write(source.replace(needle, replacement))
        return report(f"control: {label}", not all(rows(mutant, quiet=True)))


def probe_control():
    """The probe rows must fail on a copy of the scanner that answers every
    command present."""
    return mutant_control("the probe rows fail on a scanner that finds every command",
                          "probed[name] = shutil.which(name) is not None", "probed[name] = True", probe_rows)


def nm_vpn_rows(script=SCAN, quiet=False):
    """The scanner reads private directories through the same disposable
    source-copy boundary as its other file and timing controls."""
    service = "org.freedesktop.NetworkManager.openvpn"
    keyfile = "[VPN Connection]\nname=openvpn\nservice=" + service + "\n"
    rows = [
        ("no directory", {}, False),
        ("installed under usr/lib", {"lib/plugin.name": keyfile}, True),
        ("installed under etc", {"etc/plugin.name": keyfile}, True),
        ("another service", {"lib/plugin.name": keyfile.replace("openvpn", "vpnc")}, False),
        ("another extension", {"lib/plugin.conf": keyfile}, False),
        ("another section", {"lib/plugin.name": keyfile.replace("VPN Connection", "libnm")}, False),
        ("DEFAULT is an ordinary group", {"lib/plugin.name": "[DEFAULT]\nservice=" + service + "\n[VPN Connection]\nname=openvpn\n"}, False),
        ("whitespace and CRLF", {"etc/plugin.name": keyfile.replace("service=", "service = ").replace("\n", "\r\n")}, True),
        ("a malformed file beside the installed one", {"lib/broken.name": "not a keyfile", "etc/plugin.name": keyfile}, True),
    ]
    source = pathlib.Path(script).read_text()
    needle = 'NM_VPN_DIRECTORIES = ("/usr/lib/NetworkManager/VPN", "/etc/NetworkManager/VPN")'
    assert source.count(needle) == 1
    results = []
    for name, files, present in rows:
        with tempfile.TemporaryDirectory() as tmp:
            requirement = {"nmVpn": {"service": service, "label": "OpenVPN plugin"}, "purpose": "p"}
            plant(tmp, {"plugins/a/manifest.json": json.dumps({"id": "acme.a", "requirements": [requirement]}), **files})
            target = pathlib.Path(tmp, "vgshell-scan")
            target.write_text(source.replace(needle, "NM_VPN_DIRECTORIES = " + repr((os.path.join(tmp, "lib"), os.path.join(tmp, "etc")))))
            entry = one_entry(scan(os.path.join(tmp, "plugins"), script=str(target)))
            good = entry is not None and entry["missing"] == ([] if present else [service])
            results.append(good if quiet else report("nmVpn: " + name, good, str(entry)))
    return results


def scanner_module(script):
    loader = importlib.machinery.SourceFileLoader("vgshell_scan_under_test", script)
    spec = importlib.util.spec_from_loader("vgshell_scan_under_test", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def listing_lifetime_rows(script=SCAN, quiet=False):
    """Settings removes its page-link fixture while scans may enumerate it.
    Interpose after the real listdir, before scan_base can stat the entry."""
    module = scanner_module(script)
    results = []
    rows = [("removed", []), ("unsearchable", [("plugins/acme.page-link", "error:cannot stat: ", "plugins/acme.page-link")])]
    for state, want in rows:
        with tempfile.TemporaryDirectory() as tmp:
            base = os.path.join(tmp, "plugins")
            plugin = os.path.join(base, "acme.page-link")
            plant(tmp, {"plugins/acme.page-link/manifest.json": MANIFEST})
            listdir = os.listdir

            def listed(path):
                names = listdir(path)
                assert path == base and names == ["acme.page-link"]
                if state == "removed":
                    shutil.rmtree(plugin)
                else:
                    os.chmod(base, 0o000)
                return names

            out = []
            try:
                with mock.patch.object(module.os, "listdir", side_effect=listed):
                    module.scan_base(base, out, False, None, {}, {})
            finally:
                os.chmod(base, 0o755)
            got = [(os.path.relpath(e["dir"], tmp), element_kind(e), os.path.relpath(e["path"], tmp)) for e in out]
            good = matches(got, want)
            results.append(good if quiet else report("listed plugin: " + state, good, str(out)))
    return results


def start_dbus_daemon(tmp):
    daemon = shutil.which("dbus-daemon")
    if daemon is None:
        return None, None
    service_dir = os.path.join(tmp, "services")
    os.makedirs(service_dir)
    with open(os.path.join(service_dir, "org.vgshell.Activatable.service"), "w", encoding="utf-8") as fh:
        fh.write("[D-BUS Service]\nName=org.vgshell.Activatable\nExec=/bin/false\n")
    address = "unix:path=" + os.path.join(tmp, "bus")
    config = os.path.join(tmp, "dbus.conf")
    with open(config, "w", encoding="utf-8") as fh:
        fh.write(f"""<busconfig>
  <type>session</type>
  <listen>{address}</listen>
  <servicedir>{service_dir}</servicedir>
  <policy context="default">
    <allow send_destination="*"/>
    <allow receive_sender="*"/>
    <allow own="*"/>
  </policy>
</busconfig>
""")
    proc = subprocess.Popen([daemon, "--nofork", "--print-address", "--config-file", config], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    printed = proc.stdout.readline().strip()
    if not printed:
        kill_process(proc)
        raise RuntimeError("dbus-daemon printed no address")
    return proc, printed


def connect_scanner_bus(module, address):
    old = os.environ.get("DBUS_SESSION_BUS_ADDRESS")
    os.environ["DBUS_SESSION_BUS_ADDRESS"] = address
    deadline = time.monotonic() + 2
    uid_hex = str(os.getuid()).encode("ascii").hex().encode("ascii")
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.settimeout(2)
        sock.connect(module.bus_address("session"))
        sock.sendall(b"\0AUTH EXTERNAL " + uid_hex + b"\r\n")
        line = module.read_auth_line(sock, deadline)
        if not line.startswith(b"OK "):
            raise RuntimeError("auth " + repr(line))
        sock.sendall(b"BEGIN\r\n")
        module.dbus_call(sock, 1, "Hello", deadline)
        return sock, old
    except Exception:
        sock.close()
        if old is None:
            os.environ.pop("DBUS_SESSION_BUS_ADDRESS", None)
        else:
            os.environ["DBUS_SESSION_BUS_ADDRESS"] = old
        raise


def request_name(module, sock, name):
    body = bytearray(module.pack_string(name))
    body.extend(b"\0" * module.align(len(body), 4))
    body.extend((0).to_bytes(4, "little"))
    module.dbus_call(sock, 2, "RequestName", time.monotonic() + 2, "su", bytes(body))


def dbus_rows(script=SCAN, quiet=False):
    daemon = shutil.which("dbus-daemon")
    if daemon is None:
        message = "dbus-daemon-missing"
        return [True if quiet else report("D-Bus rows are not measured", True, f" ({message})")]
    results = []
    for name, manifests, want, mode in DBUS_ROWS:
        # This fixture binds a Unix socket, so use the world's short runtime.
        with tempfile.TemporaryDirectory(dir=os.path.join(os.environ["XDG_RUNTIME_DIR"], "owned")) as tmp:
            files = {os.path.join("plugins", d, "manifest.json"): json.dumps(m) for d, m in manifests.items()}
            plant(tmp, files)
            proc = owner = old_address = None
            try:
                if mode == "failed":
                    address = "unix:path=" + os.path.join(tmp, "missing-bus")
                else:
                    proc, address = start_dbus_daemon(tmp)
                if mode == "owned":
                    module = scanner_module(script)
                    owner, old_address = connect_scanner_bus(module, address)
                    request_name(module, owner, "org.vgshell.Owned")
                env = {"PATH": os.environ.get("PATH", ""), "LC_ALL": "C", "DBUS_SESSION_BUS_ADDRESS": address, "DBUS_SYSTEM_BUS_ADDRESS": address}
                scan_proc = scan(os.path.join(tmp, "plugins"), script=script, env=env)
                try:
                    got = {os.path.basename(e["dir"]): e.get("missing") for e in json.loads(scan_proc.stdout)}
                except (ValueError, KeyError):
                    got = None
                failed_line = "vgshell-scan: bus=session probe=failed" in scan_proc.stderr
                good = scan_proc.returncode == 0 and got == want and (mode != "failed" or failed_line)
                results.append(good if quiet else report(name, good, f" (exit={scan_proc.returncode} got={got})\n{scan_proc.stderr}"))
            finally:
                if owner is not None:
                    owner.close()
                if old_address is not None:
                    os.environ["DBUS_SESSION_BUS_ADDRESS"] = old_address
                elif mode == "owned":
                    os.environ.pop("DBUS_SESSION_BUS_ADDRESS", None)
                if proc is not None:
                    kill_process(proc)
    return results


def dbus_controls():
    daemon = shutil.which("dbus-daemon")
    if daemon is None:
        print("test-vgshell-scan: status=not-measured reason=dbus-daemon-missing")
        return [False]
    return [
        mutant_control("the D-Bus rows fail on a scanner that marks every bus name present",
                       'present = bus_cache[bus] is not None and name in bus_cache[bus]',
                       'present = True', dbus_rows),
        mutant_control("the D-Bus rows fail on a scanner that ignores activatable names",
                       'return owned | activatable',
                       'return owned', dbus_rows),
    ]


# core rows: name, the --core file's text (None: no file), {plugin dir:
# manifest}, want as the first element's kind and its missing list or error
# prefix, then {plugin dir: missing list}. The stub PATH is the probe rows'.
CORE_ROWS = [
    ("the core's absent command is missing and comes first", json.dumps([requirement("gone"), requirement("here")]), {"a": {"id": "acme.a", "requirements": [requirement("gone")]}},
     ("core", ["gone"]), {"a": ["gone"]}),
    ("the core's list of present commands misses nothing", json.dumps([requirement("here")]), {}, ("core", []), {}),
    ("a core file that is no list misses nothing", json.dumps({"requirements": [requirement("gone")]}), {}, ("core", []), {}),
    ("an absent core file is an error element", None, {"a": {"id": "acme.a", "requirements": [requirement("gone")]}},
     ("error", "cannot read core requirements: "), {"a": ["gone"]}),
]


def core_rows(script=SCAN, quiet=False):
    """Each core row's verdict, run against SCRIPT."""
    results = []
    for name, core, manifests, want_core, want_plugins in CORE_ROWS:
        with tempfile.TemporaryDirectory() as tmp:
            files = {os.path.join("plugins", d, "manifest.json"): json.dumps(m) for d, m in manifests.items()}
            files["stubs/here"] = "#!/bin/sh\n"
            if core is not None:
                files["requirements.json"] = core
            plant(tmp, files)
            os.chmod(os.path.join(tmp, "stubs", "here"), 0o755)
            proc = scan("--core", os.path.join(tmp, "requirements.json"), os.path.join(tmp, "plugins"), script=script, env={"PATH": os.path.join(tmp, "stubs"), "LC_ALL": "C"})
            try:
                elements = json.loads(proc.stdout)
                first = elements[0]
                got_core = ("error", first["error"][:len(want_core[1])]) if "error" in first else ("core" if first["core"].endswith("requirements.json") and "text" in first else "?", first["missing"])
                got_plugins = {os.path.basename(e["dir"]): e["missing"] for e in elements[1:]}
            except (ValueError, KeyError, IndexError):
                got_core, got_plugins = None, None
            good = proc.returncode == 0 and got_core == want_core and got_plugins == want_plugins
            results.append(good if quiet else report(name, good, f" (exit={proc.returncode} core={got_core} plugins={got_plugins})\n{proc.stderr}"))
    return results


def core_control():
    """The core rows must fail on a copy of the scanner that reads the core
    file as a manifest."""
    return mutant_control("the core rows fail on a scanner that reads the core list as a manifest",
                          "missing_requirements(text, probed, bus_cache, core=True)", "missing_requirements(text, probed, bus_cache)", core_rows)


# core watch rows use --watch-core as a long-running process. Every pipe
# read has a parent deadline and kills the child on timeout.
WATCH_TREE = {"shell/shell.qml": "ShellRoot {}", "shell/Ui/Card.qml": "Item {}\n", "shell/Ui/plugins/Deep.qml": "Item {}\n",
              "shell/plugins/a/manifest.json": MANIFEST, "shell/plugins/a/Widget.qml": "Item {}\n"}


def start_watch(source, script=SCAN):
    return subprocess.Popen([sys.executable, script, "--watch-core", source], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=ENV)


def kill_process(proc):
    if proc.poll() is None:
        proc.kill()
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=2)


def read_revision(proc, timeout=2):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        ready, _, _ = select.select([proc.stdout], [], [], max(0, deadline - time.monotonic()))
        if not ready:
            break
        line = proc.stdout.readline()
        if line == "":
            break
        try:
            revision = json.loads(line)["revision"]
        except (ValueError, KeyError, TypeError):
            return None
        if isinstance(revision, str) and len(revision) == 64:
            return revision
        return None
    kill_process(proc)
    return None


def wait_success(proc, timeout=2):
    try:
        return proc.wait(timeout=timeout) == 0
    except subprocess.TimeoutExpired:
        kill_process(proc)
        return False


def fresh_revision(source, script):
    proc = start_watch(source, script)
    revision = read_revision(proc)
    kill_process(proc)
    return revision


def append_text(path, text):
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(text)


def watch_rows(script=SCAN, quiet=False):
    results = []
    core_edit = "Item { property int core: 1 }\n"
    with tempfile.TemporaryDirectory() as tmp:
        plant(tmp, WATCH_TREE)
        source = os.path.join(tmp, "shell")
        proc = start_watch(source, script)
        armed = read_revision(proc)
        append_text(os.path.join(source, "Ui", "Card.qml"), "Item { property int edited: 1 }\n")
        changed = read_revision(proc)
        good = armed is not None and changed is not None and changed != armed and wait_success(proc)
        results.append(good if quiet else report("an append to an existing core file prints a new revision and exits", good, f" (armed={armed} changed={changed})"))
    with tempfile.TemporaryDirectory() as tmp:
        plant(tmp, WATCH_TREE)
        source = os.path.join(tmp, "shell")
        proc = start_watch(source, script)
        armed = read_revision(proc)
        os.makedirs(os.path.join(source, "New"))
        with open(os.path.join(source, "New", "Type.qml"), "w", encoding="utf-8") as fh:
            fh.write("Item {}\n")
        append_text(os.path.join(source, "Ui", "Card.qml"), core_edit)
        changed = read_revision(proc)
        with tempfile.TemporaryDirectory() as expect_tmp:
            plant(expect_tmp, WATCH_TREE)
            append_text(os.path.join(expect_tmp, "shell", "Ui", "Card.qml"), core_edit)
            expected = fresh_revision(os.path.join(expect_tmp, "shell"), script)
        good = armed is not None and changed is not None and changed == expected and wait_success(proc)
        results.append(good if quiet else report("an added file in a new subdirectory is ignored by the armed hash set", good, f" (armed={armed} changed={changed} expected={expected})"))
    with tempfile.TemporaryDirectory() as tmp:
        plant(tmp, WATCH_TREE)
        source = os.path.join(tmp, "shell")
        proc = start_watch(source, script)
        armed = read_revision(proc)
        os.remove(os.path.join(source, "Ui", "Card.qml"))
        changed = read_revision(proc)
        good = armed is not None and changed is not None and changed != armed and wait_success(proc)
        results.append(good if quiet else report("removing an existing core file prints a new revision and exits", good, f" (armed={armed} changed={changed})"))
    with tempfile.TemporaryDirectory() as tmp:
        plant(tmp, WATCH_TREE)
        source = os.path.join(tmp, "shell")
        proc = start_watch(source, script)
        armed = read_revision(proc)
        append_text(os.path.join(source, "plugins", "a", "Widget.qml"), "Item { property int pluginOnly: 1 }\n")
        append_text(os.path.join(source, "Ui", "Card.qml"), core_edit)
        changed = read_revision(proc)
        with tempfile.TemporaryDirectory() as expect_tmp:
            plant(expect_tmp, WATCH_TREE)
            append_text(os.path.join(expect_tmp, "shell", "Ui", "Card.qml"), core_edit)
            expected = fresh_revision(os.path.join(expect_tmp, "shell"), script)
        good = armed is not None and changed == expected and wait_success(proc)
        results.append(good if quiet else report("an edit under top-level plugins is neither watched nor hashed", good,
                                                 f" (armed={armed} changed={changed} expected={expected})"))
    with tempfile.TemporaryDirectory() as tmp:
        missing = os.path.join(tmp, "absent")
        proc = scan("--watch-core", missing, script=script)
        good = proc.returncode == 1 and proc.stdout == "" and proc.stderr.startswith("vgshell-scan: core-watch=failed")
        results.append(good if quiet else report("an absent core watch directory fails with a stable key", good, f" (exit={proc.returncode})\n{proc.stderr}"))
    return results


def watch_controls():
    """The watch rows fail when the watcher hashes no core file, hashes the
    plugins directory too, or lets additions enter the armed hash set."""
    return [
        mutant_control("the watch rows fail on a watcher that hashes no core file", "files = list(source_files(directory, skip=(\"plugins\",)))", "files = []", watch_rows),
        mutant_control("the watch rows fail on a watcher that hashes plugins with the core", "files = list(source_files(directory, skip=(\"plugins\",)))", "files = list(source_files(directory))", watch_rows),
        mutant_control("the watch rows fail on a watcher that lets additions count", "return source_revision(files), changed", "return source_revision(source_files(directory, skip=(\"plugins\",))), changed", watch_rows),
    ]


# A snapshot root whose path holds every character class the URL must
# quote: a space, a percent sign that reads as an escape, a fragment mark
# and a non-ASCII letter.
AWKWARD_ROOT = "snap shots %41 #1 \u00e9"

# Runs the scanner as its own entry point would, then prints on stderr
# whether urllib.request is loaded and the scanner's exit status.
IMPORT_PROBE = """
import json, runpy, sys
script = sys.argv[1]
sys.argv = [script, *sys.argv[2:]]
status = 0
try:
    runpy.run_path(script, run_name="__main__")
except SystemExit as exc:
    status = exc.code
sys.stderr.write(json.dumps({"status": status, "urllib.request": "urllib.request" in sys.modules}) + "\\n")
"""


def url_spelling_rows(script=SCAN, quiet=False):
    """The URL spelling row, run against SCRIPT: pathlib's as_uri, which the
    scanner must not call, is the oracle."""
    with tempfile.TemporaryDirectory() as tmp:
        plant(tmp, {"plugins/a/manifest.json": MANIFEST})
        root = os.path.join(tmp, AWKWARD_ROOT)
        entry = one_entry(scan("--snapshot-dir", root, os.path.join(tmp, "plugins"), script=script))
        want = None if entry is None else pathlib.Path(os.path.join(root, entry["revision"])).as_uri()
        good = entry is not None and entry.get("loadUrl") == want
        return [good if quiet else report("loadUrl spells a root that needs quoting as pathlib's as_uri does", good, f" (got={entry and entry.get('loadUrl')} want={want})")]


def url_import_rows(script=SCAN, quiet=False):
    """The import row, run against SCRIPT in a child interpreter."""
    with tempfile.TemporaryDirectory() as tmp:
        plant(tmp, {"plugins/a/manifest.json": MANIFEST})
        base = os.path.join(tmp, "plugins")
        # -I keeps the child's imports to the interpreter's own: no user
        # site directory and no PYTHON* variable.
        proc = subprocess.run([sys.executable, "-I", "-c", IMPORT_PROBE, script, "--snapshot-dir", os.path.join(tmp, "snapshots"), base],
                              capture_output=True, text=True, check=False, env={"PATH": os.environ.get("PATH", ""), "LC_ALL": "C"})
        try:
            probe = json.loads(proc.stderr.splitlines()[-1])
            published = [e for e in json.loads(proc.stdout) if "loadUrl" in e]
        except (ValueError, IndexError):
            probe, published = None, []
        good = proc.returncode == 0 and probe is not None and probe["status"] == 0 and len(published) == 1 and probe["urllib.request"] is False
        return [good if quiet else report("a scan that publishes a snapshot leaves urllib.request unimported", good, f" (probe={probe} published={len(published)})\n{proc.stderr}")]


def url_quote_control():
    """The URL spelling row must fail on a scanner that quotes nothing."""
    return mutant_control("the URL spelling row fails on a scanner that quotes nothing",
                          'return "file://" + urllib.parse.quote(path, encoding=sys.getfilesystemencoding(), errors=sys.getfilesystemencodeerrors())',
                          'return "file://" + path', url_spelling_rows)


def url_import_control():
    """The import row must fail on a scanner that imports urllib.request
    when it publishes a snapshot. The mutant imports the module itself, so
    the control holds on every Python, whatever as_uri imports there."""
    return mutant_control("the import row fails on a scanner that imports urllib.request",
                          "    return file_url(os.path.abspath(destination))",
                          "    import urllib.request\n    return file_url(os.path.abspath(destination))", url_import_rows)


# version rows: name, the commands asked for, the answer per command, and
# the cause each failed read's stderr line names. The stub PATH holds one
# program per name below; `gone` is on no PATH.
VERSION_STUBS = {
    "named": 'echo "named 0.9.1"\necho "built 2026"\n',
    "bare": 'echo 1.2.3\n',
    "argued": 'echo "$#:$1"\n',
    "fails": 'echo 9.9.9\nexit 3\n',
    "silent": '',
    "counted": 'echo x >>"$0.count"\necho 1.0.0\n',
    "placed": 'echo "${SECRET-unset}|$LC_ALL|$(pwd)"\n',
    "stalled": 'while :; do :; done\n',
}
VERSION_ROWS = [
    ("a version is the first line the command prints", ["named", "bare"], {"named": "named 0.9.1", "bare": "1.2.3"}, {}),
    ("the command is asked with --version alone", ["argued"], {"argued": "1:--version"}, {}),
    ("a command that exits non-zero has no reading", ["fails", "bare"], {"fails": None, "bare": "1.2.3"}, {"fails": "exit=3"}),
    ("a command that prints nothing has no reading", ["silent"], {"silent": None}, {"silent": "empty"}),
    ("a command on no PATH has no reading", ["gone"], {"gone": None}, {"gone": "absent"}),
    ("a path is never run", ["/bin/true"], {"/bin/true": None}, {"/bin/true": "name"}),
    ("a command named twice is read once", ["counted", "counted"], {"counted": "1.0.0"}, {}),
    ("a read gets the selected environment and starts in HOME", ["placed"], {"placed": "unset|C|{home}"}, {}),
]


def version_scan(tmp, commands, script):
    env = {"PATH": os.path.join(tmp, "stubs"), "HOME": os.path.join(tmp, "home"), "SECRET": "leaked", "LC_ALL": "en_US.UTF-8"}
    return subprocess.run([sys.executable, script, "--versions", *commands], capture_output=True, text=True, check=False, env=env, cwd=tmp, timeout=8)


def plant_version_stubs(tmp):
    plant(tmp, {os.path.join("stubs", name): "#!/bin/sh\n" + body for name, body in VERSION_STUBS.items()})
    for name in VERSION_STUBS:
        os.chmod(os.path.join(tmp, "stubs", name), 0o755)
    os.mkdir(os.path.join(tmp, "home"))


def version_rows(script=SCAN, quiet=False):
    """Each version row's verdict, run against SCRIPT, then the stalled
    read: a copy of SCRIPT whose bound is one second answers null for the
    program that never ends, and ends itself inside the test's own bound."""
    results = []
    for name, commands, want, causes in VERSION_ROWS:
        with tempfile.TemporaryDirectory() as tmp:
            plant_version_stubs(tmp)
            proc = version_scan(tmp, commands, script)
            try:
                got = json.loads(proc.stdout)
            except ValueError:
                got = None
            expected = {command: line if line is None else line.replace("{home}", os.path.realpath(os.path.join(tmp, "home"))) for command, line in want.items()}
            named = all(f"version=unread command={command} cause={cause}" in proc.stderr for command, cause in causes.items())
            counted = name != "a command named twice is read once" or open(os.path.join(tmp, "stubs", "counted.count"), encoding="utf-8").read() == "x\n"
            good = proc.returncode == 0 and got == expected and named and counted
            results.append(good if quiet else report("versions: " + name, good, f" (exit={proc.returncode} got={got})\n{proc.stderr}"))
    with open(script, encoding="utf-8") as fh:
        source = fh.read()
    with tempfile.TemporaryDirectory() as tmp:
        plant_version_stubs(tmp)
        short = os.path.join(tmp, "vgshell-scan")
        with open(short, "w", encoding="utf-8") as fh:
            fh.write(source.replace("VERSION_SECONDS = 10\n", "VERSION_SECONDS = 1\n"))
        try:
            proc = version_scan(tmp, ["stalled", "bare"], short)
            good = source.count("VERSION_SECONDS = 10\n") == 1 and proc.returncode == 0 and json.loads(proc.stdout) == {"stalled": None, "bare": "1.2.3"} and "command=stalled cause=timeout=1" in proc.stderr
            detail = f" (exit={proc.returncode})\n{proc.stdout}{proc.stderr}"
        except subprocess.TimeoutExpired:
            good, detail = False, " (the scan outlived the stalled program's bound)"
        results.append(good if quiet else report("versions: a program that never ends is killed at the bound, and the others are read", good, detail))
    return results


def version_controls():
    return [
        mutant_control("the version rows fail on a scanner that keeps every line", "out[name] = lines[0].strip()[:VERSION_LINE_MAX]", "out[name] = heads[name].decode()", version_rows),
        mutant_control("the version rows fail on a scanner that asks with no argument", '[program, "--version"]', "[program]", version_rows),
        mutant_control("the version rows fail on a scanner that reads a failed command", "if child.returncode != 0:", "if False:", version_rows),
        mutant_control("the version rows fail on a scanner that hands down its whole environment", "environment = {name: os.environ[name] for name in VERSION_ENVIRONMENT if name in os.environ}", "environment = dict(os.environ)", version_rows),
        mutant_control("the version rows fail on a scanner that reads from its own directory", 'cwd=os.environ.get("HOME") or "/"', "cwd=None", version_rows),
        mutant_control("the version rows fail on a scanner that runs a path", "if os.sep in name:", "if False:", version_rows),
        mutant_control("the version rows fail on a scanner that leaves a stalled program running", "os.killpg(child.pid, signal.SIGKILL)", "pass", version_rows),
    ]


SNAPSHOT_BARRIER = r'''
import os, runpy, signal, sys
namespace = runpy.run_path(sys.argv[1])
main = namespace["main"]
mode, root, base = sys.argv[2:]
if mode == "removed":
    original = os.open
    def opened(path, flags, *args, **kwargs):
        fd = original(path, flags, *args, **kwargs)
        if path == root:
            print("ready", file=sys.stderr, flush=True)
            sys.stdin.buffer.read(1)
        return fd
    os.open = opened
else:
    original = main.__globals__["publish_source"]
    def publishing(*args):
        print("ready", file=sys.stderr, flush=True)
        if mode == "owner":
            signal.pause()
        else:
            sys.stdin.buffer.read(1)
        return original(*args)
    main.__globals__["publish_source"] = publishing
sys.exit(main([sys.argv[1], "--snapshot-dir", root, base]))
'''


def snapshot_lifetime_rows(script=SCAN, quiet=False):
    results = []
    for mode in ("writing", "removed", "owner"):
        with tempfile.TemporaryDirectory() as tmp:
            plant(tmp, {"plugins/a/manifest.json": MANIFEST})
            root = os.path.join(tmp, "sources")
            os.mkdir(root)
            fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
            command = [sys.executable, "-I", "-c", SNAPSHOT_BARRIER, script, mode, root, os.path.join(tmp, "plugins")]
            owner_fd = None
            if mode == "removed":
                fcntl.flock(fd, fcntl.LOCK_EX)
            if mode == "owner":
                supervisor = 'import subprocess,sys; p=subprocess.Popen(sys.argv[1:],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL); print(p.pid,file=sys.stderr,flush=True); sys.stdin.buffer.read(1)'
                command = [sys.executable, "-I", "-c", supervisor, *command]
            proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=ENV, bufsize=0)
            try:
                ready = select.select([proc.stderr], [], [], 5)[0]
                line = proc.stderr.readline() if ready else b""
                if mode == "owner" and line.strip().isdigit():
                    owner_fd = os.pidfd_open(int(line))
                    ready = select.select([proc.stderr], [], [], 5)[0]
                    line = proc.stderr.readline() if ready else b""
                good = line == b"ready\n"
                if good and mode == "writing":
                    try:
                        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        good = False
                    except BlockingIOError:
                        pass
                    fcntl.flock(fd, fcntl.LOCK_UN)
                elif good and mode == "removed":
                    shutil.rmtree(root)
                    fcntl.flock(fd, fcntl.LOCK_UN)
                elif good and mode == "owner":
                    proc.terminate()
                    proc.wait(timeout=5)
                    good = bool(select.select([owner_fd], [], [], 5)[0])
                    if good:
                        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        good = os.listdir(root) == []
                if mode != "owner":
                    stdout, stderr = proc.communicate(b"x", timeout=5)
                    if mode == "removed":
                        entries = json.loads(stdout)
                        good = good and not os.path.exists(root) and len(entries) == 1 and "error" in entries[0]
                    else:
                        good = good and proc.returncode == 0 and bool(json.loads(stdout)[0].get("loadUrl"))
                results.append(good if quiet else report(f"snapshot lifetime: {mode}", good))
            finally:
                kill_process(proc)
                if owner_fd is not None:
                    if not select.select([owner_fd], [], [], 0)[0]:
                        signal.pidfd_send_signal(owner_fd, signal.SIGKILL)
                        select.select([owner_fd], [], [], 5)
                    os.close(owner_fd)
                os.close(fd)
    return results


def snapshot_lifetime_controls():
    return [
        mutant_control("snapshot writers must hold their root lock", "fcntl.flock(snapshot_fd, fcntl.LOCK_EX)", "pass", snapshot_lifetime_rows),
        mutant_control("a queued scan cannot recreate a removed root", "not os.path.samestat(os.fstat(snapshot_fd), os.stat(args.snapshot_dir))", "False", snapshot_lifetime_rows),
        mutant_control("a snapshot writer stops with its parent", "libc = ctypes.CDLL(None, use_errno=True)\n            if not set_parent_death_signal(libc, ctypes, parent_pid):", "libc = ctypes.CDLL(None, use_errno=True)\n            if False:", snapshot_lifetime_rows),
    ]


def main():
    if os.geteuid() == 0:
        print("status=not-measured reason=euid-0")
        return 77
    if shutil.which("dbus-daemon") is None:
        print("test-vgshell-scan: status=not-measured reason=dbus-daemon-missing")
        return 77
    results = [run_row(*row) for row in ROWS]
    results += listing_lifetime_rows()
    results.append(mutant_control("listing lifetime rows reject the old cannot-stat error for a removed plugin",
                                  "        except FileNotFoundError:\n            # Plugin removal can finish after listdir returned its name.\n            continue\n", "", listing_lifetime_rows))
    results += revision_rows()
    results += migration_rows()
    results.append(mutant_control("migration entry discovery", 'entry["migrate"] = True', 'pass', migration_rows))
    results += probe_rows()
    results.append(probe_control())
    results += nm_vpn_rows()
    results.append(mutant_control("the VPN rows reject treating a missing plugin as present",
                                  'present = name in probed[("nmVpn",)]', 'present = True', nm_vpn_rows))
    results += dbus_rows()
    results += dbus_controls()
    results += core_rows()
    results.append(core_control())
    results += watch_rows()
    results += watch_controls()
    results += version_rows()
    results += version_controls()
    results += snapshot_lifetime_rows()
    results += snapshot_lifetime_controls()
    results += url_spelling_rows()
    results += url_import_rows()
    results.append(url_quote_control())
    results.append(url_import_control())
    if all(results):
        print("test-vgshell-scan: ok")
        return 0
    print("test-vgshell-scan: failing")
    return 1


if __name__ == "__main__":
    sys.exit(main())
