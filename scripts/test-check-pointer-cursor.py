#!/usr/bin/env python3
"""One planted violation per rule of check-pointer-cursor.py, the elements it
must pass, the exemption marker's reach, the parser's edges, the unreadable
trees, a file at the owner's tree-relative path in another tree, and the
repository's own trees against a coverage floor, which also holds the one
real owner exempt. Each row builds a throwaway tree holding one plugin file,
runs the check on it and asserts the rule key, the line and the exit status."""
import os
import subprocess
import sys
import tempfile

CHECK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "check-pointer-cursor.py")
ENV = {"PATH": os.environ.get("PATH", ""), "LC_ALL": "C"}

# The owner's text, which only the repository's own copy may hold.
OWNER = "import QtQuick\nHoverHandler {\n    cursorShape: Qt.PointingHandCursor\n}\n"
HEAD = "import QtQuick\nimport QtQuick.Templates as T\nimport qs.Ui\n"
# Every element that takes a click, each with its cursor, the elements
# that take none, each without one, and views that take no mouse button.
CLEAN = HEAD + """Item {
    MouseArea { anchors.fill: parent; PointerCursor {} }
    T.Button { PointerCursor {} }
    T.Slider { PointerCursor {} }
    Item { TapHandler {} PointerCursor {} }
    MouseArea { acceptedButtons: Qt.NoButton }
    HoverHandler {}
    T.TextField {}
    T.ProgressBar {}
    Flickable { id: area; acceptedButtons: Qt.NoButton; TouchpadScroll { view: area } }
    ListView { id: list; acceptedButtons: Qt.NoButton; TouchpadScroll { view: list } }
}
"""


def body(inner):
    return HEAD + "Item {\n" + inner + "}\n"


# rows: name, file text, expected rule key or None, expected line or None.
# HEAD is three lines and `Item {` the fourth, so an element on the first
# line of `inner` is on line 5.
ROWS = [
    ("clean tree", CLEAN, None, None),
    ("a MouseArea without the cursor", body("    MouseArea { anchors.fill: parent }\n"), "cursor-missing", 5),
    ("a MouseArea's cursor nested one object deeper does not count", body("    MouseArea {\n        Item { PointerCursor {} }\n    }\n"), "cursor-missing", 5),
    ("a NoButton inside a child object does not excuse the area", body("    MouseArea {\n        Item { property int acceptedButtons: Qt.NoButton }\n    }\n"), "cursor-missing", 5),
    ("a MouseArea that takes every button", body("    MouseArea { acceptedButtons: Qt.AllButtons }\n"), "cursor-missing", 5),
    ("a TapHandler whose parent holds no cursor", body("    Item { TapHandler {} }\n"), "cursor-missing", 5),
    ("a cursor one object below a TapHandler's parent does not count", body("    Item {\n        TapHandler { }\n        Item { PointerCursor {} }\n    }\n"), "cursor-missing", 6),
    ("a template button without the cursor", body("    T.Button { text: \"x\" }\n"), "cursor-missing", 5),
    ("a template delegate without the cursor", body("    T.ItemDelegate { }\n"), "cursor-missing", 5),
    ("a template slider without the cursor", body("    T.Slider { }\n"), "cursor-missing", 5),
    ("a template control under another alias", "import QtQuick\nimport QtQuick.Templates as QT\nItem {\n    QT.Switch { }\n}\n", "cursor-missing", 4),
    ("a template control declared as a property value", body("    property Component c: Component { T.MenuItem { } }\n"), "cursor-missing", 5),
    ("a template text field keeps its I-beam", body("    T.TextField { }\n"), None, None),
    ("a HoverHandler takes no click", body("    HoverHandler { }\n"), None, None),
    ("a wheel area takes no click", body("    MouseArea { acceptedButtons: Qt.NoButton; onWheel: w => {} }\n"), None, None),
    ("a marker directly above exempts", body("    // pointer-cursor-exempt: a click away, not a control\n    MouseArea { }\n"), None, None),
    ("a marker inside the comment block above exempts", body("    // pointer-cursor-exempt: a click away, not a control\n    // The catcher also takes hover.\n    MouseArea { }\n"), None, None),
    ("a marker above a TapHandler exempts it", body("    Item {\n        // pointer-cursor-exempt: it watches presses only\n        TapHandler { }\n    }\n"), None, None),
    ("a marker with no reason exempts nothing", body("    // pointer-cursor-exempt:\n    MouseArea { }\n"), "cursor-missing", 6),
    ("a marker cut off by a code line exempts nothing", body("    // pointer-cursor-exempt: a click away\n    property int x: 1\n    MouseArea { }\n"), "cursor-missing", 7),
    ("a marker cut off by a blank line exempts nothing", body("    // pointer-cursor-exempt: a click away\n\n    MouseArea { }\n"), "cursor-missing", 7),
    ("a cursor in a comment does not count", body("    MouseArea {\n        // PointerCursor {}\n    }\n"), "cursor-missing", 5),
    ("a closing brace in a string closes no block", body("    MouseArea { property string s: \"}\"; PointerCursor {} }\n"), None, None),
    ("an opening brace in a string hides no area", body("    property string s: \"{\"\n    MouseArea { }\n"), "cursor-missing", 6),
    ("an area after a JavaScript block is read", body("    function f() { if (true) { return; } }\n    MouseArea { }\n"), "cursor-missing", 6),
    ("the hand named outside the owner", body("    MouseArea { cursorShape: Qt.PointingHandCursor; PointerCursor {} }\n"), "cursor-literal", 5),
    ("the hand named in a comment is no finding", body("    // cursorShape: Qt.PointingHandCursor\n"), None, None),
    ("a Flickable that drags with the mouse", body("    Flickable { id: area; clip: true; TouchpadScroll { view: area } }\n"), "mouse-drag", 5),
    ("a ListView set as a property value", body("    property Item c: ListView { id: list; TouchpadScroll { view: list } }\n"), "mouse-drag", 5),
    ("a GridView that takes the left button", body("    GridView { id: grid; acceptedButtons: Qt.LeftButton; TouchpadScroll { view: grid } }\n"), "mouse-drag", 5),
    ("a TableView without the setting", body("    TableView { id: table; TouchpadScroll { view: table } }\n"), "mouse-drag", 5),
    ("a view named through an aliased import", "import QtQuick as Q\nimport qs.Ui as Ui\nQ.Item {\n    Q.ListView { id: list; Ui.TouchpadScroll { view: list } }\n}\n", "mouse-drag", 4),
    ("a NoButton inside a child object does not excuse the view", body("    Flickable { id: area; TouchpadScroll { view: area }\n        Item { property int acceptedButtons: Qt.NoButton }\n    }\n"), "mouse-drag", 5),
    ("a NoButton in a comment does not excuse the view", body("    ListView { id: list; TouchpadScroll { view: list }\n        // acceptedButtons: Qt.NoButton\n    }\n"), "mouse-drag", 5),
    ("the cursor marker exempts no view", body("    // pointer-cursor-exempt: a list\n    Flickable { id: area; TouchpadScroll { view: area } }\n"), "mouse-drag", 6),
    ("a view that takes no mouse button", body("    GridView { id: grid; acceptedButtons: Qt.NoButton; TouchpadScroll { view: grid } }\n"), None, None),
    ("a view named in a comment is no finding", body("    // Flickable { }\n"), None, None),
    ("a ListCursor in a Column", body("    Column {\n        ListCursor { id: plate }\n        Repeater { }\n    }\n"), "cursor-positioner", 6),
    ("a ListCursor in a Row", body("    Row { ListCursor { } }\n"), "cursor-positioner", 5),
    ("a ListCursor in a Flow", body("    Flow { ListCursor { } }\n"), "cursor-positioner", 5),
    ("a ListCursor in a Grid", body("    Grid { ListCursor { } }\n"), "cursor-positioner", 5),
    ("a qualified ListCursor in a qualified Column", "import QtQuick as Q\nimport qs.Ui as Ui\nQ.Item {\n    Q.Column { Ui.ListCursor { } }\n}\n", "cursor-positioner", 4),
    ("a ListCursor beside the Column passes", body("    ListCursor { id: plate }\n    Column { Repeater { } }\n"), None, None),
    ("a ListCursor in an item inside a Column passes", body("    Column { Item { ListCursor { } } }\n"), None, None),
    ("a ListCursor named in a comment inside a Column is no finding", body("    Column {\n        // ListCursor { }\n    }\n"), None, None),
    ("the cursor marker exempts no ListCursor", body("    Column {\n        // pointer-cursor-exempt: a list\n        ListCursor { }\n    }\n"), "cursor-positioner", 7),
]

SCROLL_ROWS = [
    ("a Flickable without TouchpadScroll", body("    Flickable { id: entries; acceptedButtons: Qt.NoButton }\n"), "touchpad-scroll", 5, "entries"),
    ("a ListView without TouchpadScroll", body("    ListView { id: entries; acceptedButtons: Qt.NoButton }\n"), "touchpad-scroll", 5, "entries"),
    ("a GridView without TouchpadScroll", body("    GridView { id: entries; acceptedButtons: Qt.NoButton }\n"), "touchpad-scroll", 5, "entries"),
    ("TouchpadScroll bound to another view", body("    ListView { id: entries; acceptedButtons: Qt.NoButton; TouchpadScroll { view: other } }\n"), "touchpad-scroll", 5, "entries"),
    ("TouchpadScroll without a view binding", body("    ListView { id: entries; acceptedButtons: Qt.NoButton; TouchpadScroll {} }\n"), "touchpad-scroll", 5, "entries"),
    ("a view without its own id", body("    ListView { acceptedButtons: Qt.NoButton; TouchpadScroll { view: entries } }\n"), "touchpad-scroll", 5, "<missing>"),
    ("an id on a child does not name the view", body("    ListView { acceptedButtons: Qt.NoButton; Item { id: entries } TouchpadScroll { view: entries } }\n"), "touchpad-scroll", 5, "<missing>"),
    ("a nested TouchpadScroll is no direct child", body("    ListView { id: entries; acceptedButtons: Qt.NoButton; Item { TouchpadScroll { view: entries } } }\n"), "touchpad-scroll", 5, "entries"),
    ("a nested view's handler does not serve the outer view", body("    Flickable { id: entries; acceptedButtons: Qt.NoButton\n        ListView { id: inner; acceptedButtons: Qt.NoButton; TouchpadScroll { view: inner } }\n    }\n"), "touchpad-scroll", 5, "entries"),
    ("a child property does not bind TouchpadScroll", body("    ListView { id: entries; acceptedButtons: Qt.NoButton; TouchpadScroll { Item { property var view: entries } } }\n"), "touchpad-scroll", 5, "entries"),
    ("a commented TouchpadScroll does not count", body("    ListView { id: entries; acceptedButtons: Qt.NoButton\n        // TouchpadScroll { view: entries }\n    }\n"), "touchpad-scroll", 5, "entries"),
    ("a commented view binding does not count", body("    ListView { id: entries; acceptedButtons: Qt.NoButton; TouchpadScroll {\n        /* view: entries */\n    } }\n"), "touchpad-scroll", 5, "entries"),
    ("a TouchpadScroll in a string does not count", body('    ListView { id: entries; acceptedButtons: Qt.NoButton; property string hint: "TouchpadScroll { view: entries }" }\n'), "touchpad-scroll", 5, "entries"),
    ("a quoted id is no view binding", body('    ListView { id: entries; acceptedButtons: Qt.NoButton; TouchpadScroll { view: "entries" } }\n'), "touchpad-scroll", 5, "entries"),
    ("a member of the view is no view binding", body("    ListView { id: entries; acceptedButtons: Qt.NoButton; TouchpadScroll { view: entries.contentItem } }\n"), "touchpad-scroll", 5, "entries"),
    ("a conditional expression is no direct id binding", body("    ListView { id: entries; acceptedButtons: Qt.NoButton; TouchpadScroll { view: entries || other } }\n"), "touchpad-scroll", 5, "entries"),
    ("a cursor exemption does not exempt TouchpadScroll", body("    // pointer-cursor-exempt: a list\n    ListView { id: entries; acceptedButtons: Qt.NoButton }\n"), "touchpad-scroll", 6, "entries"),
    ("both scroll rules report their own finding", body("    ListView { id: entries }\n"), ("mouse-drag", "touchpad-scroll"), 5, "entries"),
    ("aliased views and TouchpadScroll pass", "import QtQuick as Q\nimport qs.Ui as Ui\nQ.Item {\n    Q.ListView { id: entries; acceptedButtons: Qt.NoButton; Ui.TouchpadScroll { view: entries } }\n}\n", None, None, None),
    ("multiline bindings with comments pass", body("    ListView {\n        id: /* name */ entries\n        acceptedButtons: Qt.NoButton\n        TouchpadScroll {\n            view: /* target */ entries // this list\n        }\n    }\n"), None, None, None),
    ("nested views with their own handlers pass", body("    Flickable { id: outer; acceptedButtons: Qt.NoButton; TouchpadScroll { view: outer }\n        ListView { id: inner; acceptedButtons: Qt.NoButton; TouchpadScroll { view: inner } }\n    }\n"), None, None, None),
]
SCROLL_ROWS += [
    (f"{kind} with its own handler passes", body(f"    {kind} {{ id: entries; acceptedButtons: Qt.NoButton; TouchpadScroll {{ view: entries }} }}\n"), None, None, None)
    for kind in ("Flickable", "ListView", "GridView", "TableView", "TreeView", "HorizontalHeaderView", "VerticalHeaderView")
]

JS_ROWS = [
    ("the hand named in a JavaScript file", ".pragma library\nvar hand = Qt.PointingHandCursor;\n", "cursor-literal", 2),
    ("a JavaScript file is no QML structure", ".pragma library\nfunction MouseArea() { return {}; }\n", None, None),
]


def build(tmp, qml, js=None):
    root = os.path.join(tmp, "shell")
    os.makedirs(os.path.join(root, "plugins", "acme.widget"))
    with open(os.path.join(root, "plugins", "acme.widget", "Widget.qml"), "w", encoding="utf-8") as fh:
        fh.write(qml)
    if js is not None:
        with open(os.path.join(root, "plugins", "acme.widget", "logic.js"), "w", encoding="utf-8") as fh:
            fh.write(js)
    return root


def report(name, good, proc):
    print(("  ok    " if good else "  FAIL  ") + name + ("" if good else f" (exit={proc.returncode})\n{proc.stdout}{proc.stderr}"))
    return good


def run_row(name, qml, want, line, js=None, view_id=None):
    with tempfile.TemporaryDirectory() as tmp:
        root = build(tmp, qml, js)
        proc = subprocess.run([sys.executable, CHECK, root], capture_output=True, text=True, check=False, env=ENV)
        findings = [l for l in proc.stdout.splitlines() if not l.startswith("check-pointer-cursor:")]
        if want is None:
            good = proc.returncode == 0 and not findings and proc.stdout.startswith("check-pointer-cursor: ok ")
        else:
            where = os.path.join(root, "plugins", "acme.widget", "logic.js" if js is not None else "Widget.qml")
            keys = (want,) if isinstance(want, str) else want
            good = proc.returncode == 1 and len(findings) == len(keys) and all(
                finding.startswith(f"{key} {where}:{line} ") for key, finding in zip(keys, findings)
            )
            if view_id is not None:
                # This suite reads the check's documented diagnostic fields.
                target = "<view-id>" if view_id == "<missing>" else view_id
                good = good and any(
                    finding.startswith("touchpad-scroll ")
                    and f" id={view_id} " in finding
                    and f'required="TouchpadScroll {{ view: {target} }}"' in finding
                    for finding in findings
                )
        return report(name, good, proc)


def run_unreadable_rows():
    results = []
    with tempfile.TemporaryDirectory() as tmp:
        empty = os.path.join(tmp, "empty")
        os.makedirs(os.path.join(empty, "sub"))
        proc = subprocess.run([sys.executable, CHECK, empty], capture_output=True, text=True, check=False, env=ENV)
        results.append(report("a tree with no QML file exits 2", proc.returncode == 2 and proc.stdout == f"check-pointer-cursor: unreadable: {empty}: no QML file found\n", proc))
        proc = subprocess.run([sys.executable, CHECK, os.path.join(tmp, "absent")], capture_output=True, text=True, check=False, env=ENV)
        results.append(report("an absent tree exits 2", proc.returncode == 2 and proc.stdout.startswith("check-pointer-cursor: unreadable: "), proc))
        root = build(tmp, CLEAN)
        invalid = os.path.join(root, "plugins", "acme.widget", "Widget.qml")
        with open(invalid, "wb") as fh:
            fh.write(b"\xff")
        proc = subprocess.run([sys.executable, CHECK, root], capture_output=True, text=True, check=False, env=ENV)
        results.append(report("undecodable bytes in a QML file exit 2", proc.returncode == 2 and proc.stdout.startswith(f"check-pointer-cursor: unreadable: {invalid}: "), proc))
    return results


def run_impostor_owner_row():
    """A plugin tree may hold its own Ui/foundation/PointerCursor.qml; only
    the repository's file of that path names the hand unflagged."""
    with tempfile.TemporaryDirectory() as tmp:
        root = os.path.join(tmp, "acme.widget")
        impostor = os.path.join(root, "Ui", "foundation", "PointerCursor.qml")
        os.makedirs(os.path.dirname(impostor))
        with open(impostor, "w", encoding="utf-8") as fh:
            fh.write(OWNER)
        proc = subprocess.run([sys.executable, CHECK, root], capture_output=True, text=True, check=False, env=ENV)
        findings = [l for l in proc.stdout.splitlines() if not l.startswith("check-pointer-cursor:")]
        good = proc.returncode == 1 and len(findings) == 1 and findings[0].startswith(f"cursor-literal {impostor}:3 ")
        return report("the owner's path under another tree names the hand as a finding", good, proc)


def run_repository_floor():
    """The repository's own trees pass and the parser found what they hold:
    142 QML files and 31 elements that take a click when this row was
    written, 7 views when the drag rule was added, and 16 ListCursor elements
    when the positioner rule was added. A count under the floor names the extractor as broken, not the
    tree as sparse. shell/Ui/foundation/PointerCursor.qml names the hand, so
    the pass also holds the one real owner exempt."""
    proc = subprocess.run([sys.executable, CHECK], capture_output=True, text=True, check=False, env=ENV)
    fields = dict(part.split("=", 1) for part in proc.stdout.strip().split()[2:] if "=" in part) if proc.returncode == 0 else {}
    good = proc.returncode == 0 and int(fields.get("files", 0)) >= 100 and int(fields.get("clickable", 0)) >= 25 and int(fields.get("views", 0)) >= 7 and int(fields.get("cursors", 0)) >= 15
    if proc.returncode == 0 and not good:
        print(f"  the extractor is broken: it found files={fields.get('files')} clickable={fields.get('clickable')} views={fields.get('views')} cursors={fields.get('cursors')}")
    return report("the repository's trees pass above the coverage floor", good, proc)


def main():
    results = [run_row(*row) for row in ROWS]
    results += [run_row(name, qml, want, line, view_id=view_id) for name, qml, want, line, view_id in SCROLL_ROWS]
    results += [run_row(name, CLEAN, want, line, js) for name, js, want, line in JS_ROWS]
    results += run_unreadable_rows()
    results.append(run_impostor_owner_row())
    results.append(run_repository_floor())
    if all(results):
        print("test-check-pointer-cursor: ok")
        return 0
    print("test-check-pointer-cursor: failing")
    return 1


if __name__ == "__main__":
    sys.exit(main())
