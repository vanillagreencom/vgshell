import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.settings" as Settings
import "../../shell/plugins/vgs.updates" as Updates
import "../../shell/plugins/vgs.automations" as Automations
import "../../shell/plugins/vgs.automations/AutomationsViewLogic.js" as AutomationsView

// One hover on every list (design-system.md § Motion), on shipped lists:
// the pointer over a row puts the list's one plate on it and draws the
// row's title in listItem.selectedForeground, and the row draws no fill
// of its own. The pointer moves neither the list's selection, the
// keyboard focus nor a scroll (§ Pointer). The Updates window's
// disclosures hold no selection and take the keyboard row by row; the
// Settings Plugins list takes its keys from the search field; the
// Automations history scrolls a row into view when its selection reaches
// it, so a hover that moved the selection would scroll it.
Item {
    id: root
    width: 960
    height: 720

    readonly property var updatesShell: ({
        screens: { current: null },
        status: { values: { sources: [
            { source: "pacman", label: "System", count: 3, checkedAt: 0, error: null, packages: [{ name: "linux", old: "6.16.8", new: "6.16.9" }] },
            { source: "aur", label: "AUR", count: 1, checkedAt: 0, error: null, packages: [{ name: "vsys-bin", old: "0.9.0", new: "0.9.1" }] },
            { source: "mise", label: "mise", count: 1, checkedAt: 0, error: null, packages: [{ name: "node", old: "22.19.0", new: "22.20.0" }] },
            { source: "plugins", label: "Plugins", count: 0, checkedAt: 0, error: null, packages: [] }
        ] } },
        tui: { run: (name, args) => "ok" },
        ipc: { call: (name, payload) => "started" }
    })

    Item {
        id: pluginsPanel
        property string title: "Plugins"
        property string notice: ""
        readonly property var plugins: ["Bar", "Bluetooth", "Capture", "Clipboard", "Displays"].map((name, index) => ({
            id: "vgs.p" + index, name: name, description: "", version: "0.1.0", source: "bundled", icon: "blocks",
            errors: [], alwaysOn: false, enabled: true, status: [], requirements: []
        }))
        function openRow(id, reason) {}
        function setEnabled(id, enabled) {}
        function addPlugin() {}
        function resetVgs() {}
    }

    Item {
        id: historyPanel
        property var shell: null
        readonly property var automations: []
        readonly property var groups: AutomationsView.historyGroups(Array.from({ length: 14 }, (unused, index) => ({
            automation: "backup", run: "run" + index, name: "Backup " + index, transcript: "/runs/" + index, outcome: "succeeded",
            tone: "success", icon: "check", startedAt: 1792300000000 - index * 60000, durationMs: 1000
        })), 0)
        function filteredHistoryGroups(id) { return groups; }
    }

    Settings.ListPage { id: pluginsPage; panel: pluginsPanel; width: 320; height: 520 }
    Updates.Window { id: updatesWindow; x: 320; width: 320; height: 520; shell: root.updatesShell }
    Automations.HistoryPage { id: historyPage; x: 640; width: 320; height: 360; panel: historyPanel }

    TestCase {
        name: "listHover"
        when: windowShown

        function init() { compare(UnitTheme.override({ motion: { scale: 0 } }), "ok"); }
        function cleanup() { mouseMove(root, root.width - 1, root.height - 1); }
        function cleanupTestCase() { UnitTheme.reset(); }

        function descendants(item) {
            const out = [];
            const stack = [item];
            while (stack.length > 0) {
                const at = stack.pop();
                out.push(at);
                for (const child of at.children) stack.push(child);
            }
            return out;
        }
        function cursorOf(item) { return descendants(item).find(child => child.follow !== undefined && child.placed !== undefined); }
        // The row's title, not a trailing control's own label.
        function titleOf(row) { return descendants(row.contentItem).find(child => child.role === "item" && child.text === row.text); }
        function scrolls(item) { return descendants(item).filter(child => child.contentY !== undefined).map(child => child.contentY); }
        // Two readings a pixel apart: a cursor takes a hover once the
        // pointer moved (ListCursor.hoverTakes).
        function point(row, y) {
            mouseMove(row, row.width / 3, y);
            mouseMove(row, row.width / 3 + 1, y);
        }

        // The row drawing no fill of its own, its title in the accent, and
        // the list's plate on it: the hover the Plugins list draws.
        function verifyHover(owner, row, label) {
            compare(row.hovered, true, label + ": the pointer is over the row");
            compare(String(row.background.color), "#00000000", label + ": the row draws no fill of its own");
            compare(String(titleOf(row).color), String(Qt.color(Theme.listItem.selectedForeground)), label + ": the pointed row's title takes the accent");
            const cursor = cursorOf(owner);
            verify(cursor !== undefined, label + ": the list holds a cursor");
            verify(cursor.placed === row, label + ": the plate sits on the pointed row");
            compare(cursor.opacity, 1, label + ": the plate shows");
            // A row still entering stands below its place by its rise.
            tryVerify(() => Math.abs(cursor.y - row.mapToItem(cursor.parent, 0, 0).y) < 0.5, 2000, label + ": the plate stands at the row");
            compare(cursor.height, row.height, label + ": the plate takes the row's height");
        }

        function test_an_updates_source_takes_the_plate_and_keeps_the_keyboard() {
            const rows = descendants(updatesWindow).filter(child => child.expandable !== undefined && child.focusItem !== undefined)
                .sort((a, b) => a.mapToItem(root, 0, 0).y - b.mapToItem(root, 0, 0).y).map(source => source.focusItem);
            compare(rows.length, 4, "a row per source");
            rows[0].forceActiveFocus(Qt.TabFocusReason);
            const scrolled = scrolls(updatesWindow);
            point(rows[1], rows[1].height / 2);
            verifyHover(updatesWindow, rows[1], "updates");
            compare(rows[0].activeFocus, true, "the keyboard stays on the row it was on");
            compare(String(titleOf(rows[0]).color), String(Qt.color(Theme.color.text)), "a row the plate is not on keeps its resting title");
            compare(scrolls(updatesWindow), scrolled, "the window scrolls nothing");
            // A source with nothing to show takes no click, so no plate.
            compare(rows[3].clickable, false, "the up-to-date source cannot expand");
            point(rows[3], rows[3].height / 2);
            compare(rows[3].hovered, true);
            verify(cursorOf(updatesWindow).placed !== rows[3], "a source that cannot expand takes no plate");
            compare(String(titleOf(rows[3]).color), String(Qt.color(Theme.color.text)), "nor the accent");
        }

        function test_a_plugin_row_takes_the_plate_and_leaves_the_selection() {
            pluginsPage.focusSearch();
            tryVerify(() => pluginsPage.initialFocus.activeFocus, 1000, "the search field holds the keys");
            const rows = descendants(pluginsPage).filter(child => child.modelData !== undefined && child.needs !== undefined)
                .sort((a, b) => a.y - b.y);
            compare(rows.length, 5, "a row per plugin");
            compare(pluginsPage.current, 0);
            const scrolled = scrolls(pluginsPage);
            point(rows[2], rows[2].height / 2);
            verifyHover(pluginsPage, rows[2], "plugins");
            compare(pluginsPage.current, 0, "the selection stays on the row the keyboard left it on");
            compare(pluginsPage.initialFocus.activeFocus, true, "the search field keeps the keys");
            compare(String(titleOf(rows[0]).color), String(Qt.color(Theme.color.text)), "the selection the plate left keeps its resting title");
            compare(scrolls(pluginsPage), scrolled, "the list scrolls nothing");
        }

        // The pointer rests on a row part way past the list's bottom: a
        // selection that moved there would scroll it into view.
        function test_a_history_row_at_the_edge_takes_the_plate_and_scrolls_nothing() {
            const area = descendants(historyPage).find(child => child.contentY !== undefined && child.reveal !== undefined);
            verify(area !== undefined, "the page scrolls its body");
            tryVerify(() => area.contentHeight > area.height, 1000, "the runs overflow the page");
            // The page builds its rows once laid out, and the plate fades
            // in on the selection then.
            tryCompare(cursorOf(historyPage), "opacity", 1, 1000, "the plate shows on the selection");
            const rows = descendants(historyPage).filter(child => child.row !== undefined && child.cursorItem !== undefined);
            verify(rows.length > 0, "the rows in view are built");
            compare(area.contentY, 0);
            const edge = rows.find(row => {
                const top = row.mapToItem(area, 0, 0).y;
                return top < area.height && top + row.height > area.height;
            });
            verify(edge !== undefined, "a run lies part way past the bottom");
            compare(historyPage.current, 0);
            point(edge, (area.height - edge.mapToItem(area, 0, 0).y) / 2);
            compare(historyPage.current, 0, "the selection stays");
            compare(area.contentY, 0, "the page stays where the pointer rests");
            verifyHover(historyPage, edge, "history");
        }
    }
}
