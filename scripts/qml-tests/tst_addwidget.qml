import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.bar" as BarPlugin

// The Add widget chooser over a stub shell: one content row per widget,
// its one button the row's action. A placed widget asks the manager to
// unplace it, an unplaced one to insert it at the clicked point, a
// widget-only plugin that is off to turn it on, and a plugin with other
// kinds that is off opens its Settings page. A mouse click on the button
// leaves no focus ring; the arrows move the keyboard to a row's button
// with its ring, and Return and Space press it once. Opening focuses the
// list and presses nothing.
Item {
    id: root
    width: 700
    height: 600

    // Each request the chooser makes of the stub shell, in order.
    property var calls: []

    function record(call) {
        root.calls = root.calls.concat([call]);
        return "ok";
    }

    // Manager rows as Registry.managerListing publishes them, the fields
    // the chooser reads.
    readonly property var rows: [
        { id: "acme.placed", name: "Placed", icon: "clock", description: "On the bar", kinds: ["bar-widget", "service"], enablement: "first-party", enabled: true, placed: true },
        { id: "acme.unplaced", name: "Unplaced", icon: "clock", description: "Off the bar", kinds: ["bar-widget", "service"], enablement: "first-party", enabled: true, placed: false },
        { id: "acme.widget", name: "Widget only", icon: "clock", description: "A lone widget", kinds: ["bar-widget"], enablement: "widget", enabled: false, placed: false },
        { id: "acme.off", name: "Turned off", icon: "clock", description: "A plugin that is off", kinds: ["bar-widget", "panel"], enablement: "first-party", enabled: false, placed: false },
        { id: "acme.service", name: "Service", icon: "clock", description: "No widget", kinds: ["service"], enablement: "first-party", enabled: true, placed: false }
    ]

    Component {
        id: chooserComponent
        BarPlugin.AddWidget { width: root.width; height: root.height }
    }

    UnitCase {
        name: "addwidget"
        when: windowShown

        property Item chooser: null

        function shell() {
            return {
                manager: {
                    plugins: root.rows,
                    insertWidget: (id, screen, x) => root.record(["insertWidget", id, screen, x]),
                    setPlaced: (id, placed) => root.record(["setPlaced", id, placed]),
                    setEnabled: (id, enabled) => root.record(["setEnabled", id, enabled])
                },
                surfaces: { openPage: (page, tab) => root.record(["openPage", page, tab]) }
            };
        }

        function init() {
            root.Window.window.requestActivate();
            tryCompare(root.Window.window, "active", true);
            root.calls = [];
            chooser = createTemporaryObject(chooserComponent, root);
            verify(chooser !== null);
            chooser.shell = shell();
            chooser.open(JSON.stringify({ screen: "DP-1", x: 40 }));
            chooser.forceActiveFocus(Qt.OtherFocusReason);
            renderedFrame(chooser);
        }

        function cleanup() { chooser = null; }

        function descendants(item) {
            const out = [];
            for (const child of item.children) out.push(child, ...descendants(child));
            return out;
        }

        function rowOf(id) {
            const found = descendants(chooser).find(item => item.actionButton !== undefined && item.modelData !== undefined && item.modelData.id === id);
            verify(found !== undefined, "a row shows " + id);
            return found;
        }

        function ringOf(button) {
            const ring = descendants(button).find(item => item.keyboardFocus !== undefined && item.target === button);
            verify(ring !== undefined, "the button holds its focus ring");
            return ring;
        }

        function test_a_click_presses_the_action_and_draws_no_ring() {
            const button = rowOf("acme.unplaced").actionButton;
            mouseClick(button);
            compare(root.calls, [["insertWidget", "acme.unplaced", "DP-1", 40]]);
            verify(button.activeFocus, "the click focuses the button");
            compare(button.focusReason, Qt.MouseFocusReason);
            renderedFrame(chooser);
            compare(ringOf(button).visible, false, "a mouse click draws no focus ring");
        }

        function test_the_arrows_move_to_a_row_with_its_ring_and_return_presses_it() {
            keyClick(Qt.Key_Down);
            const first = rowOf("acme.placed").actionButton;
            tryCompare(first, "activeFocus", true);
            compare(ringOf(first).visible, true, "a key move draws the ring");
            keyClick(Qt.Key_Down);
            const second = rowOf("acme.unplaced").actionButton;
            tryCompare(second, "activeFocus", true);
            compare(ringOf(second).visible, true);
            compare(chooser.current, 1, "one Down moves one row");
            keyClick(Qt.Key_Return);
            compare(root.calls, [["insertWidget", "acme.unplaced", "DP-1", 40]], "Return presses the selected row's action once");
            keyClick(Qt.Key_Space);
            compare(root.calls.length, 2, "Space presses it once");
        }

        function test_opening_presses_nothing() {
            verify(chooser.activeFocus, "the list holds the keys on open");
            compare(chooser.current, -1);
            keyClick(Qt.Key_Return);
            keyClick(Qt.Key_Space);
            compare(root.calls, [], "Return with no row selected presses nothing");
        }

        function test_each_state_asks_for_its_one_call_data() {
            return [
                { tag: "placed", id: "acme.placed", action: "remove", call: ["setPlaced", "acme.placed", false] },
                { tag: "unplaced", id: "acme.unplaced", action: "add", call: ["insertWidget", "acme.unplaced", "DP-1", 40] },
                { tag: "widget-only off", id: "acme.widget", action: "add", call: ["setEnabled", "acme.widget", true] },
                { tag: "other kinds off", id: "acme.off", action: "settings", call: ["openPage", "acme.off", "Settings"] }
            ];
        }

        function test_each_state_asks_for_its_one_call(data) {
            const row = rowOf(data.id);
            compare(row.rowAction, data.action);
            mouseClick(row.actionButton);
            compare(root.calls, [data.call]);
            compare(row.secondary === row.modelData.description, data.action !== "settings", "only a plugin that must be turned on in Settings replaces its description");
        }

        function test_rows_list_widgets_alone_with_no_chip() {
            const shown = descendants(chooser).filter(item => item.actionButton !== undefined && item.modelData !== undefined);
            compare(shown.map(row => row.modelData.id), ["acme.placed", "acme.unplaced", "acme.widget", "acme.off"]);
            compare(descendants(chooser).filter(item => item instanceof Badge && item.visible).length, 0, "no row draws a chip");
            const heights = shown.map(row => row.height);
            verify(heights.every(height => height === heights[0]), "every row is one height: " + JSON.stringify(heights));
        }
    }
}
