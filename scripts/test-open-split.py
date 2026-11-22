#!/usr/bin/env python3
"""Controls for scripts/smoke/open-split.py: the instrument edits the shipped
creation path once each and refuses a missing needle, and the reader splits
each open's figures from planted stamp logs. The row,
scripts/smoke/rows/open-split.sh, holds the in-shell control: a planted
attachment cost in a System window copy must land in attach_ms."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("open_split", ROOT / "scripts/smoke/open-split.py")
split = importlib.util.module_from_spec(spec)
spec.loader.exec_module(split)

KINDS = split.summonable(ROOT)
EDITED = ("shell/Core/Plugins.qml", "shell/Hosts/PluginSlot.qml", "shell/Hosts/SummonHost.qml", "shell/Hosts/PaneHost.qml",
          "shell/Ui/layout/FirstView.qml")


def stamp(event, kind, id_, t, **extra):
    return '2026-11-21 10:00:00 INFO qml: open-split: ' + json.dumps({"e": event, "id": id_, "kind": kind, "t": t, **extra})


def build(kind, id_, t, load=40, create=50, lend=2, attach=300, settle=5, open_ms=5):
    """A build's stamps from T, its open() included, and the time it ends."""
    lines, at = [stamp("attempt", kind, id_, t), stamp("load", kind, id_, t)], t + load
    lines.append(stamp("loaded", kind, id_, at)); at += create
    lines.append(stamp("created", kind, id_, at)); at += lend
    lines.append(stamp("attach", kind, id_, at)); at += attach
    lines.append(stamp("attached", kind, id_, at)); at += settle
    lines += [stamp("built", kind, id_, at), stamp("open", kind, id_, at)]
    return lines, at, open_ms


class Log:
    def __init__(self, test):
        self.dir = Path(tempfile.mkdtemp())
        test.addCleanup(shutil.rmtree, self.dir)
        self.path = self.dir / "shell.log"
        self.path.write_text("")

    def add(self, *lines):
        with self.path.open("a") as log:
            for line in lines:
                log.write(line + "\n")

    def size(self):
        return self.path.stat().st_size


def window_open(kind, id_, t, frame_after=200):
    lines, at, open_ms = build(kind, id_, t + 1)
    at += open_ms
    lines = [stamp("request", kind, id_, t)] + lines + [stamp("opened", kind, id_, at), stamp("returned", kind, id_, at + 2)]
    return lines + [stamp("start", kind, id_, at + 2 + frame_after - 10), stamp("frame", kind, id_, at + 2 + frame_after)]


class Instrument(unittest.TestCase):
    def copy(self):
        tree = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tree)
        for name in EDITED:
            (tree / name).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, tree / name)
        return tree

    def test_every_edit_applies_once_to_the_shipped_files(self):
        tree = self.copy()
        split.prepare(tree)
        for name in EDITED:
            self.assertNotEqual((tree / name).read_text(), (ROOT / name).read_text(), name)
        plugins = (tree / "shell/Core/Plugins.qml").read_text()
        for event in ("attempt", "load", "loaded", "created", "attach", "attached", "built"):
            self.assertEqual(plugins.count(f'openSplitMark("{event}", id, kind);'), 1, event)
        self.assertEqual((tree / "shell/Hosts/PluginSlot.qml").read_text().count("Plugins.openSplitFrame(pluginId, kind, slot);"), 1)
        summon = (tree / "shell/Hosts/SummonHost.qml").read_text()
        panes = (tree / "shell/Hosts/PaneHost.qml").read_text()
        for event in ("request", "returned", "open", "opened"):
            self.assertEqual(summon.count(f'Plugins.openSplitMark("{event}", id, host.kind);'), 1, event)
        for event, id_ in (("mount", "id"), ("mounted", "id"), ("open", "mounted.pluginId"), ("opened", "mounted.pluginId")):
            self.assertEqual(panes.count(f'Plugins.openSplitMark("{event}", {id_}, "pane");'), 1, event)
        view = (tree / "shell/Ui/layout/FirstView.qml").read_text()
        for marked in ('openSplitMark("view");', 'openSplitMark(settled ? "settled" : "unsettled")', 'openSplitMark("gone")',
                       'openSplitMark("step", { t: begin, ms: Date.now() - begin });', "function openSplitStep() {",
                       'view.openSplitMark("step", { t: openSplitBegin, ms: Date.now() - openSplitBegin, block: true });',
                       "openSplitBegin = begin;"):
            self.assertEqual(view.count(marked), 1, marked)

    def test_a_missing_needle_refuses(self):
        tree = self.copy()
        path = tree / "shell/Core/Plugins.qml"
        text = path.read_text()
        needle = "            instance.shell = facadeFor(manifest, settings, row.providers);\n"
        self.assertEqual(text.count(needle), 1)
        path.write_text(text.replace(needle, ""))
        with self.assertRaises(ValueError):
            split.prepare(tree)


class Reading(unittest.TestCase):
    def test_a_summoned_window_splits_each_part(self):
        log = Log(self)
        log.add("unrelated line", *window_open("window", "vgs.gallery", 1000))
        result, missing = split.reading(split.stamps(log.path, 0), "window", "vgs.gallery")
        self.assertEqual(missing, [])
        self.assertEqual(result["builds"], [{"kind": "window", "id": "vgs.gallery", "within": "-", "load_ms": 40,
                                             "create_ms": 50, "lend_ms": 2, "attach_ms": 300, "settle_ms": 5, "open_ms": 5}])
        self.assertEqual((result["open"]["sync_ms"], result["open"]["first_content_ms"], result["open"]["frame_start_ms"]),
                         (405, 200, 190))

    def test_a_pane_built_in_the_window_open_is_its_own_build(self):
        log = Log(self)
        window, at, _ = build("window", "vgs.system", 11)
        pane, end, _ = build("pane", "vgs.displays", at + 2, attach=600)
        log.add(stamp("request", "window", "vgs.system", 10), *window, stamp("mount", "pane", "vgs.displays", at + 1), *pane,
                stamp("opened", "pane", "vgs.displays", end + 5), stamp("mounted", "pane", "vgs.displays", end + 6),
                stamp("opened", "window", "vgs.system", end + 7), stamp("returned", "window", "vgs.system", end + 8),
                stamp("start", "pane", "vgs.displays", end + 50), stamp("start", "window", "vgs.system", end + 50),
                stamp("frame", "window", "vgs.system", end + 60), stamp("frame", "pane", "vgs.displays", end + 60))
        result, missing = split.reading(split.stamps(log.path, 0), "window", "vgs.system")
        self.assertEqual(missing, [])
        rows = {row["id"]: row for row in result["builds"]}
        self.assertEqual(rows["vgs.displays"]["within"], "window:vgs.system")
        self.assertEqual(rows["vgs.displays"]["attach_ms"], 600)
        self.assertEqual(rows["vgs.system"]["attach_ms"], 300)
        self.assertEqual(rows["vgs.system"]["open_ms"], end + 7 - at)
        self.assertEqual(result["open"]["first_content_ms"], 52)

    def test_a_selected_pane_is_its_mount_not_a_mount_inside_a_summon(self):
        log = Log(self)
        nested, at, _ = build("pane", "vgs.power", 21, attach=900)
        log.add(stamp("request", "window", "vgs.system", 10), stamp("mount", "pane", "vgs.power", 20), *nested,
                stamp("opened", "pane", "vgs.power", at + 5), stamp("mounted", "pane", "vgs.power", at + 6),
                stamp("returned", "window", "vgs.system", at + 7))
        selected, end, _ = build("pane", "vgs.power", 5001, attach=7)
        log.add(stamp("mount", "pane", "vgs.power", 5000), *selected, stamp("opened", "pane", "vgs.power", end + 5),
                stamp("mounted", "pane", "vgs.power", end + 6), stamp("start", "pane", "vgs.power", end + 20),
                stamp("frame", "pane", "vgs.power", end + 30))
        result, missing = split.reading(split.stamps(log.path, 0), "pane", "vgs.power")
        self.assertEqual(missing, [])
        self.assertEqual([row["attach_ms"] for row in result["builds"]], [7])
        self.assertEqual(result["open"]["sync_ms"], end + 6 - 5000)

    def test_unmeasured_parts_are_named_never_zero(self):
        cases = (
            ("no frame yet", window_open("window", "vgs.gallery", 1000)[:-1], ["frame"], "pending"),
            ("a swap before any frame start", window_open("window", "vgs.gallery", 1000)[:-2]
             + [stamp("frame", "window", "vgs.gallery", 1300)], ["start", "frame"], "pending"),
            ("not returned", window_open("window", "vgs.gallery", 1000)[:-4], ["returned", "open_ms", "start", "frame"], "pending"),
            ("refused before the build", [stamp("request", "window", "vgs.gallery", 1),
                                          stamp("returned", "window", "vgs.gallery", 2)], ["build"], "no-build"),
            ("another surface only", window_open("panel", "vgs.vpn", 1000), ["open"], "no-open"),
            ("empty log", [], ["open"], "no-open"),
        )
        for label, lines, want, framed in cases:
            with self.subTest(label):
                log = Log(self)
                log.add(*lines)
                result, missing = split.reading(split.stamps(log.path, 0), "window", "vgs.gallery")
                self.assertEqual(missing, want)
                for figure, stamp_name in (("sync_ms", "returned"), ("first_content_ms", "frame"), ("frame_start_ms", "start")):
                    if result is not None and stamp_name in want:
                        self.assertIsNone(result["open"][figure])
                out = io.StringIO()
                with contextlib.redirect_stdout(out):
                    self.assertEqual(split.main(["open-split.py", "framed", str(log.path), "0", "window", "vgs.gallery"]), 0)
                self.assertEqual(out.getvalue().strip(), framed)

    def test_a_reopen_reads_after_its_offset(self):
        log = Log(self)
        log.add(*window_open("window", "vgs.gallery", 1000))
        offset = log.size()
        lines, _, _ = build("window", "vgs.gallery", 9001, load=0, attach=11)
        log.add(stamp("request", "window", "vgs.gallery", 9000), *lines, stamp("opened", "window", "vgs.gallery", 9070),
                stamp("returned", "window", "vgs.gallery", 9071), stamp("start", "window", "vgs.gallery", 9090),
                stamp("frame", "window", "vgs.gallery", 9100))
        result, missing = split.reading(split.stamps(log.path, offset), "window", "vgs.gallery")
        self.assertEqual(missing, [])
        self.assertEqual((result["builds"][0]["load_ms"], result["builds"][0]["attach_ms"]), (0, 11))

    def test_the_reading_command_writes_its_figures_and_judges_completeness(self):
        for lines, status in ((window_open("window", "vgs.gallery", 1000), 0),
                              (window_open("window", "vgs.gallery", 1000)[:-1], 1)):
            log = Log(self)
            log.add(*lines)
            out = log.dir / "reading.json"
            with contextlib.redirect_stdout(io.StringIO()):
                code = split.main(["open-split.py", "reading", str(log.path), "0", "window", "vgs.gallery",
                                   "gallery", "first", "0.4", str(out)])
            self.assertEqual(code, status)
            written = json.loads(out.read_text())
            self.assertEqual((written["place"], written["open"]["id"], written["cpu_some_pct"]), ("gallery", "vgs.gallery", "0.4"))
            self.assertEqual(written["missing"], [] if status == 0 else ["frame"])
            self.assertEqual([written["builds"][0][k] for k in ("load_ms", "create_ms", "lend_ms", "attach_ms")], [40, 50, 2, 300])

    def test_a_deferral_reads_its_steps_and_settle(self):
        log = Log(self)
        lines = window_open("window", "vgs.gallery", 1000)
        frame = json.loads(lines[-1].split("open-split: ")[1])["t"]
        log.add(stamp("view", "view", "view:1", 1100), *lines,
                stamp("step", "view", "view:1", frame + 5, ms=4), stamp("step", "view", "view:1", frame + 40, ms=12),
                stamp("settled", "view", "view:1", frame + 70),
                stamp("step", "view", "view:2", frame + 900, ms=99))
        result, missing = split.reading(split.stamps(log.path, 0), "window", "vgs.gallery")
        self.assertEqual(missing, [])
        self.assertEqual((result["open"]["settle_ms"], result["open"]["longest_step_ms"]), (70, 12))
        self.assertNotIn("longest_frame_gap_ms", result["open"])

    def test_an_open_with_no_view_reads_no_deferral(self):
        log = Log(self)
        log.add(*window_open("window", "vgs.gallery", 1000))
        result, _ = split.reading(split.stamps(log.path, 0), "window", "vgs.gallery")
        self.assertEqual((result["open"]["settle_ms"], result["open"]["longest_step_ms"]), (0, 0))

    def test_settled_waits_for_every_view(self):
        cases = (
            ("no view", [], True),
            ("a view building", [stamp("view", "view", "view:1", 1)], False),
            ("settled", [stamp("view", "view", "view:1", 1), stamp("settled", "view", "view:1", 5)], True),
            # The step that settles the view is logged after its settle.
            ("settled inside its last step", [stamp("view", "view", "view:1", 1), stamp("unsettled", "view", "view:1", 2),
                                              stamp("settled", "view", "view:1", 9), stamp("step", "view", "view:1", 5, ms=4)], True),
            ("unsettled by new values", [stamp("view", "view", "view:1", 1), stamp("settled", "view", "view:1", 2),
                                         stamp("unsettled", "view", "view:1", 3)], False),
            ("one of two settled", [stamp("view", "view", "view:1", 1), stamp("view", "view", "view:2", 2),
                                    stamp("settled", "view", "view:1", 5)], False),
            ("the other gone", [stamp("view", "view", "view:1", 1), stamp("view", "view", "view:2", 2),
                                stamp("gone", "view", "view:2", 3), stamp("settled", "view", "view:1", 5)], True),
        )
        for label, lines, want in cases:
            with self.subTest(label):
                log = Log(self)
                log.add(*lines)
                self.assertEqual(split.settled(split.stamps(log.path, 0)), want)

    def test_first_frame_content_must_equal_the_settled_content(self):
        items = ["Label:Surfaces", "Label:Typography"]
        frame = {"target": "Control(0x1)", "focus": True, "active": True, "views": 1, "items": items}
        settled_ = {"target": "Control(0x1)", "focus": True, "active": True, "views": 1, "items": list(reversed(items))}
        cases = (
            ("the same", frame, settled_, "equal"),
            ("a row built late", frame, dict(settled_, items=items + ["Label:Buttons"]), "differs"),
            ("focus lost once settled", frame, dict(settled_, focus=False), "differs"),
            ("no target at the frame", dict(frame, target=None), settled_, "differs"),
            ("another target once settled", frame, dict(settled_, target="Control(0x2)"), "differs"),
            # The compositor gives a new surface the keyboard after its
            # first frame; its target, built and focused, gets it then.
            ("the window takes the keyboard later", dict(frame, focus=False, active=False), settled_, "equal"),
            ("an empty first frame", dict(frame, items=[]), dict(settled_, items=[]), "differs"),
            ("no FirstView in the instance", dict(frame, views=0, items=["Label:Smoke"]), dict(settled_, views=0), "no-view"),
        )
        for label, first, after, want in cases:
            with self.subTest(label):
                log = Log(self)
                lines = window_open("window", "vgs.gallery", 1000)
                log.add(*lines, stamp("content", "window", "vgs.gallery", 2000, **first))
                verdict, report = split.content(split.stamps(log.path, 0), "window", "vgs.gallery", after)
                self.assertEqual(verdict, want)
                if label == "a row built late":
                    self.assertEqual(report["settled_only"], ["Label:Buttons"])

    # A `shell listPlugins` row as Registry.listJson writes it: the plugin's
    # dir and no source, which the probe's pluginSources answers apart.
    def listing(self, *rows):
        listed = [dict({"enabled": True, "requirements": []}, **row) for row in rows]
        listed += [{"id": id_, "enabled": False, "kinds": ["service"], "requirements": []}
                   for id_ in split.EXCLUDED if id_ not in {row["id"] for row in rows}]
        for row in listed:
            row.setdefault("dir", "/tree/shell/plugins/" + row["id"])
        return {"scanned": True, "plugins": listed}

    def sources(self, listing, installed=()):
        return {p["id"]: "installed" if p["id"] in installed else "bundled" for p in listing["plugins"]}

    def test_the_sweep_opens_every_place_discovery_finds(self):
        listing = self.listing(
            {"id": "vgs.gallery", "kinds": ["window"]},
            {"id": "vgs.system", "kinds": ["window", "service"]},
            {"id": "vgs.vpn", "kinds": ["panel", "pane", "bar-widget"]},
            {"id": "vgs.fonts", "kinds": ["pane"], "enabled": False},
            {"id": "vgs.printers", "kinds": ["pane", "panel"], "enabled": False,
             "requirements": [{"name": "lpstat", "state": "missing"}, {"name": "cups-browsed", "state": "missing", "optional": True}]},
            {"id": "vgs.lock", "kinds": ["overlay"], "enabled": False},
            {"id": "acme.local", "kinds": ["window"], "dir": "/home/.config/vgshell/plugins/acme.local"},
        )
        lines = split.sweep(listing, self.sources(listing, installed={"acme.local"}), ["window/vgs.gallery", "pane/vgs.vpn"], KINDS)
        self.assertIn("enable vgs.fonts", lines)
        self.assertIn("off vgs.printers needs=lpstat", lines)
        self.assertIn("excluded vgs.lock needs=" + split.EXCLUDED["vgs.lock"], lines)
        self.assertIn("entry window vgs.system", lines)
        self.assertIn("entry panel vgs.vpn", lines)
        self.assertIn("pane vgs.fonts", lines)
        for absent in ("entry window vgs.gallery", "pane vgs.vpn", "entry overlay vgs.lock", "pane vgs.printers",
                       "entry window acme.local", "enable vgs.lock"):
            self.assertNotIn(absent, lines)

    def test_an_incomplete_discovery_refuses(self):
        gallery = self.listing({"id": "vgs.gallery", "kinds": ["window"]})
        unsourced = dict(self.sources(gallery))
        del unsourced["vgs.gallery"]
        cases = (
            ("unscanned", {"scanned": False, "plugins": [{"id": "vgs.gallery"}]}, {"vgs.gallery": "bundled"}, []),
            ("empty", {"scanned": True, "plugins": []}, {}, []),
            ("an excluded plugin unlisted", {"scanned": True, "plugins": [{"id": "vgs.gallery", "kinds": ["window"], "dir": "/tree/shell/plugins/vgs.gallery"}]},
             {"vgs.gallery": "bundled"}, []),
            ("a listed plugin with no source", gallery, unsourced, []),
            ("a floor member undiscovered", gallery, self.sources(gallery), ["panel/vgs.themes"]),
        )
        for label, listing, sources, floor in cases:
            with self.subTest(label):
                with self.assertRaises(ValueError):
                    split.sweep(listing, sources, floor, KINDS)

    # The kinds come from PluginLogic, the one judge: a kind it adds is
    # opened with no edit here, and no kind read opens nothing.
    def test_the_sweep_opens_the_kinds_pluginlogic_names(self):
        self.assertTrue({"panel", "overlay", "menu", "window"} <= set(KINDS), KINDS)
        listing = self.listing({"id": "vgs.gallery", "kinds": ["window"]}, {"id": "acme.dock", "kinds": ["dock", "service"]})
        sources = self.sources(listing)
        self.assertNotIn("entry dock acme.dock", split.sweep(listing, sources, [], KINDS))
        self.assertIn("entry dock acme.dock", split.sweep(listing, sources, [], KINDS + ("dock",)))
        with self.assertRaises(ValueError):
            split.sweep(listing, sources, [], ())

    def test_an_unreadable_kind_set_refuses(self):
        tree = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tree)
        with self.assertRaises(ValueError):
            split.summonable(tree)

    def test_an_unreadable_stamp_refuses(self):
        for line in ('x open-split: {"e": "request", "id": "vgs.gallery"', 'x open-split: {"e": "request", "id": "a", "kind": "window", "t": "5"}',
                     'x open-split: {"e": "request", "id": "a", "kind": "window", "t": true}'):
            with self.subTest(line=line):
                log = Log(self)
                log.add(line)
                with self.assertRaises(ValueError):
                    split.stamps(log.path, 0)


if __name__ == "__main__":
    unittest.main()
