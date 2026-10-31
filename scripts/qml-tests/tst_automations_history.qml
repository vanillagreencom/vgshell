import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.automations" as Automations
import "../../shell/plugins/vgs.automations/AutomationsLogic.js" as Engine
import "../../shell/plugins/vgs.automations/AutomationsViewLogic.js" as View

// The Automations History page at the 720-run cap, an automation every
// five minutes, so the runs span several days: the page builds only the
// rows its body shows, a new run builds its own row and keeps every other
// built row, and Up, Down and Enter move to and open the run the drawn
// selection shows, across days and past the rows built. The panel stands
// in for Window.qml's history rows and its filteredHistoryGroups.
Item {
    id: root
    width: 480
    height: 520

    readonly property int cap: 720
    readonly property real step: 5 * 60000
    property real newest: 0
    property int serial: 0

    function runRow(at, run) {
        return { automation: "five", run: run, name: "Every five minutes", startedAt: at, durationMs: 1200,
            outcome: "succeeded", tone: "success", icon: "circle-check", transcript: "/runs/five@" + run + ".log" };
    }

    Item {
        id: panel
        property var shell: null
        readonly property var automations: [{ id: "five", name: "Every five minutes" }]
        property var historyRows: []
        function filteredHistoryGroups(id) {
            const rows = id === "" ? historyRows : historyRows.filter(row => row.automation === id);
            return View.historyGroups(rows, Date.now() - Engine.HISTORY_DAYS_MAX * Engine.DAY_MS);
        }
    }

    Automations.HistoryPage { id: page; anchors.fill: parent; panel: panel }
    SignalSpy { id: opened; target: page; signalName: "openRequested" }

    UnitCase {
        name: "automationsHistory"
        when: windowShown

        function init() {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            root.newest = Date.now() - root.step;
            const rows = [];
            for (let i = 0; i < root.cap; i++) rows.push(root.runRow(root.newest - i * root.step, "r" + i));
            // A fresh parse, as each history read hands the window.
            panel.historyRows = JSON.parse(JSON.stringify(rows));
            area().contentY = 0;
            page.current = 0;
            page.forceActiveFocus();
            opened.clear();
            settle();
        }
        function cleanupTestCase() { UnitTheme.reset(); }

        function settle() {
            renderedFrame(page);
            wait(0);
        }
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
        function area() { return descendants(page).find(child => child.contentY !== undefined && child.reveal !== undefined); }
        function built() { return descendants(page).filter(child => child.row !== undefined && child.cursorItem !== undefined); }
        function topOf(row) { return row.mapToItem(area(), 0, 0).y; }
        function indexOf(row) { return page.flatRows.findIndex(at => View.historyKey(at) === View.historyKey(row.row)); }
        function selected() {
            const rows = built().filter(row => row.highlighted);
            compare(rows.length, 1, "one built row draws the selection");
            return rows[0];
        }

        function test_only_the_rows_in_view_are_built() {
            verify(page.groups.length > 2, "the runs span several days");
            const view = area();
            verify(view.contentHeight > 20 * view.height, "the runs overflow the page many times");
            let rows = built();
            verify(rows.length > 0, "the rows in view are built");
            verify(rows.length < 20, "and no more: " + rows.length);
            for (const row of rows)
                verify(topOf(row) < view.height && topOf(row) + row.height > 0, "a built row lies in view");
            const shown = rows.map(indexOf).sort((a, b) => a - b);
            compare(shown[0], 0, "the newest run is built at the top");
            compare(shown[shown.length - 1] - shown[0], shown.length - 1, "the built rows are one run of the list");
            view.contentY = view.contentHeight - view.height;
            settle();
            rows = built();
            const end = rows.map(indexOf);
            verify(end.indexOf(root.cap - 1) >= 0, "the oldest run is built at the bottom");
            verify(end.indexOf(0) < 0, "the newest run's row is gone");
            for (const row of rows)
                verify(topOf(row) < view.height && topOf(row) + row.height > 0, "a built row lies in view at the bottom");
        }

        function test_a_new_run_builds_its_row_and_keeps_the_others() {
            const before = built();
            const keys = before.map(row => View.historyKey(row.row));
            const newestTop = topOf(before[keys.indexOf("five@r0")]);
            const next = [root.runRow(root.newest + root.step, "new")].concat(panel.historyRows.slice(0, root.cap - 1));
            panel.historyRows = JSON.parse(JSON.stringify(next));
            settle();
            const after = built();
            const added = after.filter(row => before.indexOf(row) < 0);
            compare(added.length, 1, "one row is built");
            compare(added[0].row.run, "new", "the new run's");
            compare(topOf(added[0]), newestTop, "at the top");
            for (const row of after.filter(row => before.indexOf(row) >= 0))
                compare(View.historyKey(row.row), keys[before.indexOf(row)], "a kept row shows the run it showed");
        }

        function test_up_down_and_enter_move_and_open_the_shown_row() {
            keyClick(Qt.Key_Down);
            compare(page.current, 1);
            compare(indexOf(selected()), 1, "Down selects the second run");
            keyClick(Qt.Key_Return);
            compare(opened.signalArguments[0][0], page.flatRows[1].transcript, "Return opens it");
            // Past the rows built, then across a day's start.
            const steps = built().length + 3;
            for (let i = 0; i < steps; i++) keyClick(Qt.Key_Down);
            settle();
            compare(page.current, 1 + steps);
            let row = selected();
            compare(indexOf(row), page.current, "the selection is built where Down left it");
            verify(topOf(row) >= 0 && topOf(row) + row.height <= area().height, "and scrolled into view");
            page.current = page.groups[1].start - 2;
            for (let i = 0; i < 3; i++) keyClick(Qt.Key_Down);
            settle();
            row = selected();
            compare(indexOf(row), page.groups[1].start + 1, "Down crosses into the next day");
            verify(topOf(row) >= 0 && topOf(row) + row.height <= area().height, "the next day's row is in view");
            keyClick(Qt.Key_Up);
            keyClick(Qt.Key_Up);
            settle();
            row = selected();
            compare(indexOf(row), page.groups[1].start - 1, "Up returns to the day before");
            keyClick(Qt.Key_Enter);
            compare(opened.signalArguments[1][0], page.flatRows[page.current].transcript, "Enter opens the selected run");
        }
    }
}
