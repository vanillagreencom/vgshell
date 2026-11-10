import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.bar" as BarPlugin

// The Manage widgets chooser over a stub shell: one content row per
// widget, its one control the row's action, a Switch or an Enable plugin
// link, on the row's trailing edge. A placed widget's Switch is on and
// asks the manager to unplace it, an unplaced one's is off and asks to
// insert it at the clicked point, a widget-only plugin that is off shows
// its Switch off and asks to turn it on, and a plugin with other kinds
// that is off shows the link, which asks to turn it on; once the manager
// publishes it on and placed, the row shows its Switch, on, holding the
// focus the link held, as a row whose control a change outside the
// window swaps does. A mouse click on a control leaves no focus ring; the
// arrows move the keyboard to a row's control with its ring, and Return
// and Space press it once. Opening, also over a focused control, focuses
// the list and presses nothing.
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
                }
            };
        }

        // A stub whose setEnabled publishes the row turned on and placed
        // before it answers, as Config.writeUser publishes before it
        // returns and PluginLogic.withEnabled places a widget it turns on.
        function publishingShell() {
            const next = shell();
            next.manager.setEnabled = (id, enabled) => {
                const reply = root.record(["setEnabled", id, enabled]);
                const after = publishingShell();
                after.manager.plugins = chooser.plugins.map(row => row.id === id ? Object.assign({}, row, { enabled, placed: enabled }) : row);
                chooser.shell = after;
                return reply;
            };
            return next;
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
            const found = descendants(chooser).find(item => item.control !== undefined && item.modelData !== undefined && item.modelData.id === id);
            verify(found !== undefined, "a row shows " + id);
            return found;
        }

        function ringOf(control) {
            const ring = descendants(control).find(item => item.keyboardFocus !== undefined && item.target === control);
            verify(ring !== undefined, "the control holds its focus ring");
            return ring;
        }

        function test_a_click_presses_the_action_and_draws_no_ring() {
            const control = rowOf("acme.unplaced").control;
            mouseClick(control);
            compare(root.calls, [["insertWidget", "acme.unplaced", "DP-1", 40]]);
            verify(control.activeFocus, "the click focuses the switch");
            compare(control.focusReason, Qt.MouseFocusReason);
            compare(control.checked, false, "the switch follows the bar, which the stub leaves unchanged");
            renderedFrame(chooser);
            compare(ringOf(control).visible, false, "a mouse click draws no focus ring");
        }

        function test_the_arrows_move_to_a_row_with_its_ring_and_return_presses_it() {
            keyClick(Qt.Key_Down);
            const first = rowOf("acme.placed").control;
            tryCompare(first, "activeFocus", true);
            compare(ringOf(first).visible, true, "a key move draws the ring");
            keyClick(Qt.Key_Down);
            const second = rowOf("acme.unplaced").control;
            tryCompare(second, "activeFocus", true);
            compare(ringOf(second).visible, true);
            compare(chooser.current, 1, "one Down moves one row");
            keyClick(Qt.Key_Return);
            compare(root.calls, [["insertWidget", "acme.unplaced", "DP-1", 40]], "Return presses the selected row's action once");
            keyClick(Qt.Key_Space);
            compare(root.calls.length, 2, "Space presses it once");
        }

        // A re-summon calls open() on the open chooser and the host focuses
        // the scope again, which would hand the focus back to the control
        // last clicked or moved to.
        function test_opening_presses_nothing_data() {
            return [
                { tag: "first open", focus: "" },
                { tag: "re-summon after a click", focus: "click" },
                { tag: "re-summon after a key move", focus: "key" }
            ];
        }

        function test_opening_presses_nothing(data) {
            if (data.focus === "click") mouseClick(rowOf("acme.placed").control);
            if (data.focus === "key") keyClick(Qt.Key_Down);
            if (data.focus !== "") {
                tryVerify(() => rowOf("acme.placed").control.activeFocus, 1000, "the control holds the keys before the re-summon");
                chooser.open(JSON.stringify({ screen: "DP-1", x: 40 }));
                chooser.forceActiveFocus(Qt.OtherFocusReason);
            }
            root.calls = [];
            verify(chooser.activeFocus, "the list holds the keys on open");
            compare(chooser.current, -1);
            compare(rowOf("acme.placed").control.activeFocus, false, "no control holds the keys on open");
            keyClick(Qt.Key_Return);
            keyClick(Qt.Key_Space);
            compare(root.calls, [], "Return and Space with no row selected press nothing");
            keyClick(Qt.Key_Down);
            tryCompare(rowOf("acme.placed").control, "activeFocus", true);
            compare(chooser.current, 0, "the first Down selects the first row");
        }

        // A row removed above the selected one, as when a plugin is
        // uninstalled while the chooser is open, keeps the keys on the
        // selected plugin.
        function test_a_removed_row_keeps_the_keys_on_the_selected_plugin() {
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            const control = rowOf("acme.unplaced").control;
            tryCompare(control, "activeFocus", true);
            const next = shell();
            next.manager.plugins = root.rows.slice(1);
            chooser.shell = next;
            tryCompare(chooser, "current", 0);
            verify(control.activeFocus, "the selected control keeps the keys");
            keyClick(Qt.Key_Return);
            compare(root.calls, [["insertWidget", "acme.unplaced", "DP-1", 40]], "Return presses the selected plugin's action");
        }

        function test_each_state_asks_for_its_one_call_data() {
            return [
                { tag: "placed", id: "acme.placed", action: "remove", link: false, checked: true, call: ["setPlaced", "acme.placed", false] },
                { tag: "unplaced", id: "acme.unplaced", action: "add", link: false, checked: false, call: ["insertWidget", "acme.unplaced", "DP-1", 40] },
                { tag: "widget-only off", id: "acme.widget", action: "add", link: false, checked: false, call: ["setEnabled", "acme.widget", true] },
                { tag: "other kinds off", id: "acme.off", action: "enable", link: true, checked: false, call: ["setEnabled", "acme.off", true] }
            ];
        }

        function test_each_state_asks_for_its_one_call(data) {
            const row = rowOf(data.id);
            compare(row.rowAction, data.action);
            const control = row.control;
            verify(data.link ? control instanceof RowAction : control instanceof Switch, "the row ends in its " + (data.link ? "link" : "switch"));
            verify(control.visible);
            if (data.link) compare(control.text, "Enable plugin");
            else compare(control.checked, data.checked, "the switch is on while the widget is on the bar");
            compare(row.secondary, row.modelData.description, "every row keeps its description");
            mouseClick(control);
            compare(root.calls, [data.call]);
        }

        function test_each_control_ends_on_the_row_edge_data() {
            return [
                { tag: "switch", id: "acme.placed" },
                { tag: "link", id: "acme.off" }
            ];
        }

        // The switch's track, or the link's text, ends where a ContentRow's
        // trailing items end.
        function test_each_control_ends_on_the_row_edge(data) {
            const row = rowOf(data.id);
            const control = row.control;
            const drawnEnd = control instanceof Switch ? control.indicator.x + control.indicator.width : control.width;
            const edge = row.contentItem.mapToItem(row, row.contentItem.width, 0).x;
            compare(control.mapToItem(row, drawnEnd, 0).x, edge);
        }

        function test_turning_a_plugin_on_shows_its_switch_with_the_focus_data() {
            return [
                { tag: "mouse click", key: 0, ring: false },
                { tag: "Return", key: Qt.Key_Return, ring: true },
                { tag: "Space", key: Qt.Key_Space, ring: true }
            ];
        }

        function test_turning_a_plugin_on_shows_its_switch_with_the_focus(data) {
            chooser.shell = publishingShell();
            const link = rowOf("acme.off").control;
            verify(link instanceof RowAction);
            if (data.key === 0) {
                mouseClick(link);
            } else {
                for (let i = 0; i < 4; i++) keyClick(Qt.Key_Down);
                tryCompare(link, "activeFocus", true);
                keyClick(data.key);
            }
            compare(root.calls, [["setEnabled", "acme.off", true]], "one call turns the plugin on");
            const row = rowOf("acme.off");
            compare(row.rowAction, "remove");
            const control = row.control;
            verify(control instanceof Switch, "the row now ends in its switch");
            verify(control.visible && !link.visible, "the switch replaces the link");
            compare(control.checked, true, "the switch is on: turning the plugin on put its widget on the bar");
            verify(control.activeFocus, "the focus the link held moves to the switch");
            renderedFrame(chooser);
            compare(ringOf(control).visible, data.ring, "the ring shows only after the keys");
        }

        // A shell that publishes plugin ID turned on, and so placed, or
        // turned off, as a change made in Settings or the CLI reaches the
        // open chooser.
        function shellWith(id, enabled) {
            const next = shell();
            next.manager.plugins = root.rows.map(row => row.id === id ? Object.assign({}, row, { enabled, placed: enabled || row.placed }) : row);
            return next;
        }

        function test_an_outside_change_moves_the_keys_to_the_shown_control_data() {
            return [
                { tag: "switch to link", id: "acme.unplaced", downs: 2, enabled: false, link: true, call: ["setEnabled", "acme.unplaced", true] },
                { tag: "link to switch", id: "acme.off", downs: 4, enabled: true, link: false, call: ["setPlaced", "acme.off", false] }
            ];
        }

        function test_an_outside_change_moves_the_keys_to_the_shown_control(data) {
            for (let i = 0; i < data.downs; i++) keyClick(Qt.Key_Down);
            const before = rowOf(data.id).control;
            tryCompare(before, "activeFocus", true);
            chooser.shell = shellWith(data.id, data.enabled);
            const control = rowOf(data.id).control;
            verify(control !== before, "the change shows the row's other control");
            verify(data.link ? control instanceof RowAction : control instanceof Switch);
            verify(control.activeFocus, "the shown control takes the keys");
            compare(before.focus, false, "the hidden control gives up its focus");
            compare(chooser.current, data.downs - 1, "the row stays selected");
            renderedFrame(chooser);
            compare(ringOf(control).visible, true, "the ring moves with the keys");
            keyClick(Qt.Key_Return);
            compare(root.calls, [data.call], "Return presses the shown control once");
        }

        // The host focuses the scope on a re-summon, which would hand the
        // keys to a hidden control that kept its focus.
        function test_a_resummon_after_an_outside_change_presses_nothing() {
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            const before = rowOf("acme.unplaced").control;
            tryCompare(before, "activeFocus", true);
            chooser.shell = shellWith("acme.unplaced", false);
            chooser.open(JSON.stringify({ screen: "DP-1", x: 40 }));
            chooser.forceActiveFocus(Qt.OtherFocusReason);
            verify(chooser.activeFocus, "the list holds the keys on open");
            compare(chooser.current, -1);
            verify(!before.activeFocus && !rowOf("acme.unplaced").control.activeFocus, "neither control of the row holds the keys");
            keyClick(Qt.Key_Return);
            keyClick(Qt.Key_Space);
            compare(root.calls, [], "Return and Space with no row selected press nothing");
        }

        function test_rows_list_widgets_alone_with_no_chip() {
            const shown = descendants(chooser).filter(item => item.control !== undefined && item.modelData !== undefined);
            compare(shown.map(row => row.modelData.id), ["acme.placed", "acme.unplaced", "acme.widget", "acme.off"]);
            compare(descendants(chooser).filter(item => item instanceof Badge && item.visible).length, 0, "no row draws a chip");
            compare(shown.filter(row => descendants(row).some(item => item instanceof Button && item.visible)).map(row => row.modelData.id), [], "no row draws a button");
            const heights = shown.map(row => row.height);
            verify(heights.every(height => height === heights[0]), "every row is one height: " + JSON.stringify(heights));
        }
    }
}
