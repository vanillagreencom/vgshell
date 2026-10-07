import QtQuick
import QtQuick.Layouts
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// Layouts and plain parent bindings allocate real qs.Ui controls.
// Composite fields anchor their inner input to their bounded outer box.
Item {
    width: 2200
    height: 400

    RowLayout {
        id: layout
        width: 2000
        height: 200
    }

    TestCase {
        name: "inputwidth"
        when: windowShown

        function init() {
            verify(Theme.control.minWidth > 0);
            UnitTheme.reset();
            layout.width = 2000;
        }

        function fixtureProperties(type) {
            return type === "IconButton" ? "label: 'Close'; iconName: 'x'; " : "";
        }

        function compareWidth(input, expected) {
            tryCompare(input, "width", expected);
        }

        function test_layout_bounds_data() {
            const compact = ["Button", "IconButton", "InfoButton", "ToggleButton", "BarItem", "TitleButton", "Switch", "Checkbox", "Radio"];
            const fields = ["Select", "Slider", "TextField", "TextArea", "ShortcutField", "DateField", "PathField", "LevelSlider", "SegmentedControl", "TileGroup", "WeekdayChipGroup", "TimeChipList", "TimeField"];
            return compact.map(type => ({tag: type, type: type, minimum: Theme.control.minWidth}))
                .concat(fields.map(type => ({tag: type, type: type, minimum: Theme.field.minWidth})));
        }

        function test_layout_bounds(data) {
            const input = createTemporaryQmlObject("import QtQuick; import QtQuick.Layouts; import qs.Ui; " + data.type + " { " + fixtureProperties(data.type) + "Layout.fillWidth: true }", layout);
            verify(input !== null);
            if (data.type === "LevelSlider") verify(input.minimumWidth >= data.minimum);
            else compare(input.minimumWidth, data.minimum);
            compare(input.maximumWidth, Theme.control.maxWidth);
            compareWidth(input, Theme.control.maxWidth);
            layout.width = input.minimumWidth - 1;
            // Qt layouts round the allocation up to a whole pixel.
            compareWidth(input, Math.ceil(input.minimumWidth));
            verify(input.width >= input.minimumWidth && input.width <= input.maximumWidth);
        }

        function test_plain_parent_allocation() {
            const holder = createTemporaryQmlObject("import QtQuick; Item { width: 2000; height: 100 }", parent);
            const rows = test_layout_bounds_data();
            const inputs = rows.map(row => createTemporaryQmlObject("import QtQuick; import qs.Ui; " + row.type + " { " + fixtureProperties(row.type) + "width: parent.width }", holder));
            verify(inputs.every(input => input !== null));
            tryVerify(() => inputs.every(input => input.width === Theme.control.maxWidth));
            holder.width = 240;
            tryVerify(() => inputs.every(input => input.width === 240));
            holder.width = 2000;
            tryVerify(() => inputs.every(input => input.width === Theme.control.maxWidth));
            holder.width = 0;
            tryVerify(() => inputs.every(input => input.width === input.minimumWidth));
        }

        function test_composite_anchor_inputs_data() {
            return [{tag: "DateField", type: "DateField"}, {tag: "PathField", type: "PathField"}];
        }

        function test_composite_anchor_inputs(data) {
            const holder = createTemporaryQmlObject("import QtQuick; Item { width: 2000; height: 100 }", parent);
            const outer = createTemporaryQmlObject("import QtQuick; import qs.Ui; " + data.type + " { width: parent.width }", holder);
            const inner = outer.children.find(child => child.placeholderText !== undefined);
            verify(inner !== undefined);
            compareWidth(outer, Theme.control.maxWidth);
            compareWidth(inner, Theme.control.maxWidth);
            holder.width = 240;
            compareWidth(outer, 240);
            compareWidth(inner, 240);
            holder.width = Theme.field.minWidth;
            compareWidth(outer, Theme.field.minWidth);
            compareWidth(inner, Theme.field.minWidth);
        }

        function test_compact_natural_width_tracks_content() {
            const input = createTemporaryQmlObject("import QtQuick; import qs.Ui; Button { text: 'Apply' }", parent);
            verify(input !== null);
            tryVerify(() => input.width === input.implicitWidth);
            input.text = "Apply ".repeat(100);
            compareWidth(input, Theme.control.maxWidth);
            input.text = "Save";
            tryVerify(() => input.width === input.implicitWidth && input.width < Theme.control.maxWidth);
        }

        function test_level_minimum_keeps_input_and_readout_apart() {
            const input = createTemporaryQmlObject("import QtQuick; import qs.Ui; LevelSlider { iconName: 'volume-2'; value: 1; width: minimumWidth }", parent);
            verify(input !== null);
            const button = input.children.find(child => child.label === input.buttonLabel);
            const readout = input.children.find(child => child.lineBox !== undefined && child.text === input.text);
            verify(button !== undefined && readout !== undefined);
            tryVerify(() => input.slider.width >= input.slider.minimumWidth
                && button.x + button.width <= input.slider.x
                && input.slider.x + input.slider.width + input.spacing <= readout.x
                && readout.x + readout.width <= input.width);
        }

        function test_form_slot_bounds_composite_rows() {
            const row = createTemporaryQmlObject("import QtQuick; import qs.Ui; FormRow { width: 2000; label: 'Value'; Row { objectName: 'values'; width: parent.width; Item { width: 20; height: 20 } } }", parent);
            const values = findChild(row, "values");
            verify(values !== null);
            compare(values.width, Theme.control.maxWidth);
        }

        function test_parent_width_bindings_stay_bounded_data() {
            return test_layout_bounds_data();
        }

        function test_parent_width_bindings_stay_bounded(data) {
            const row = createTemporaryQmlObject("import QtQuick; import qs.Ui; FormRow { width: 2000; label: 'Value'; " + data.type + " { " + fixtureProperties(data.type) + "objectName: 'input'; width: parent.width } }", parent);
            verify(row !== null);
            const input = findChild(row, "input");
            verify(input !== null);
            compareWidth(input, Theme.control.maxWidth);
            compare(input.mapToItem(row, 0, 0).x, row.valueX);
            const minimumAllocation = Math.max(Theme.field.minWidth, input.minimumWidth);
            row.width = row.valueX + minimumAllocation;
            compareWidth(input, minimumAllocation);
            row.width = 2000;
            compareWidth(input, Theme.control.maxWidth);
        }
    }
}
