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
            const fields = ["Select", "Slider", "TextField", "TextArea", "ShortcutField", "DateField", "PathField", "LevelSlider", "SavedSlider", "SegmentedControl", "TileGroup", "WeekdayChipGroup", "TimeChipList", "TimeField"];
            return compact.map(type => ({tag: type, type: type, minimum: Theme.control.minWidth}))
                .concat(fields.map(type => ({tag: type, type: type, minimum: Theme.field.minWidth})));
        }

        function test_layout_bounds(data) {
            const input = createTemporaryQmlObject("import QtQuick; import QtQuick.Layouts; import qs.Ui; " + data.type + " { " + fixtureProperties(data.type) + "Layout.fillWidth: true }", layout);
            verify(input !== null);
            if (data.type === "LevelSlider" || data.type === "SavedSlider") verify(input.minimumWidth >= data.minimum);
            else compare(input.minimumWidth, data.minimum);
            compare(input.maximumWidth, Theme.control.maxWidth);
            compareWidth(input, Theme.control.maxWidth);
            layout.width = input.minimumWidth - 1;
            // Qt layouts round the allocation up to a whole pixel.
            compareWidth(input, Math.ceil(input.minimumWidth));
            verify(input.width >= input.minimumWidth && input.width <= input.maximumWidth);
        }

        // A button's caller owns the width it binds (tst_button), so only
        // the inputs that install InputWidth are bounded here.
        function test_plain_parent_allocation() {
            const holder = createTemporaryQmlObject("import QtQuick; Item { width: 2000; height: 100 }", parent);
            const buttons = ["Button", "IconButton", "InfoButton", "ToggleButton"];
            const rows = test_layout_bounds_data().filter(row => !buttons.includes(row.type));
            const inputs = rows.map(row => createTemporaryQmlObject("import QtQuick; import qs.Ui; " + row.type + " { " + fixtureProperties(row.type) + "width: parent.width }", holder));
            verify(inputs.every(input => input !== null));
            tryVerify(() => inputs.every(input => input.width === 2000));
            holder.width = 240;
            tryVerify(() => inputs.every(input => input.width === 240));
            holder.width = 2000;
            tryVerify(() => inputs.every(input => input.width === 2000));
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
            compareWidth(outer, 2000);
            compareWidth(inner, 2000);
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

        function test_saved_minimum_keeps_input_and_reading_apart() {
            const input = createTemporaryQmlObject("import QtQuick; import qs.Ui; SavedSlider { width: minimumWidth }", parent);
            verify(input !== null);
            const reading = input.children.find(child => child.role !== undefined);
            verify(reading !== undefined);
            tryVerify(() => input.slider.width >= input.slider.minimumWidth
                && input.slider.x + input.slider.width + Theme.field.labelGap <= reading.x
                && reading.x + reading.width <= input.width);
        }

        function test_form_slot_bounds_composite_rows() {
            const row = createTemporaryQmlObject("import QtQuick; import qs.Ui; FormRow { width: 2000; label: 'Value'; Row { objectName: 'values'; width: parent.width; Item { width: 20; height: 20 } } }", parent);
            const values = findChild(row, "values");
            verify(values !== null);
            compare(values.width, Theme.control.maxWidth);
        }

        function test_row_allocates_inputs_without_caller_widths_data() {
            return test_layout_bounds_data().filter(row => row.minimum === Theme.field.minWidth);
        }

        function test_row_allocates_inputs_without_caller_widths(data) {
            const row = createTemporaryQmlObject("import QtQuick; import qs.Ui; FormRow { width: 2000; label: 'Value'; " + data.type + " { objectName: 'input' } }", parent);
            verify(row !== null);
            const input = findChild(row, "input");
            verify(input !== null);
            compareWidth(input, Theme.control.maxWidth);
            compare(input.mapToItem(row, 0, 0).x, row.valueX);
            row.width = row.valueX + Theme.field.minWidth / 2;
            compareWidth(input, Theme.field.minWidth / 2);
            row.width = 2000;
            compareWidth(input, Theme.control.maxWidth);
        }

        function test_row_keeps_compact_switch_and_external_shortcut_tools() {
            const row = createTemporaryQmlObject("import QtQuick; import qs.Ui; FormRow { width: 2000; label: 'Keys'; ShortcutField { objectName: 'input'; keys: ['SUPER+CTRL+ALT+SHIFT+PAGEDOWN'] } }", parent);
            const input = findChild(row, "input");
            verify(input !== null);
            compareWidth(input, Theme.control.maxWidth);
            const pending = [input];
            let box = null;
            const tools = [];
            while (pending.length > 0) {
                const at = pending.pop();
                if (String(at).indexOf("QQuickAbstractButton") === 0) box = at;
                if (at.inUse !== undefined && at.iconName !== undefined) tools.push(at);
                for (const child of at.children) pending.push(child);
            }
            verify(box !== null && tools.length >= 2);
            compareWidth(box, Theme.control.maxWidth);
            tryVerify(() => tools.every(tool => tool.mapToItem(input, 0, 0).x >= box.width));
            row.width = row.valueX + Theme.field.minWidth;
            compareWidth(box, Theme.field.minWidth);
            tryCompare(input, "toolsBelow", true);
            tryVerify(() => tools.every(tool => {
                const at = tool.mapToItem(input, 0, 0);
                return at.x >= 0 && at.x + tool.width <= input.width && at.y >= box.height
                    && at.y + tool.height <= input.height;
            }));
            tryVerify(() => row.height >= input.height);
            const toggled = createTemporaryQmlObject("import QtQuick; import qs.Ui; FormRow { width: 2000; label: 'On'; Switch { objectName: 'input'; size: 'sm' } }", parent);
            const toggle = findChild(toggled, "input");
            tryVerify(() => toggle.width === toggle.implicitWidth && toggle.width < Theme.field.minWidth);
        }

        function test_row_allocation_stays_fixed_during_slider_readout_changes_data() {
            // Mouse's signed speed and Windows' pixel radius grow their
            // readouts while a pointer press is still on the track.
            return [
                {tag: "mouse-speed", from: -1, to: 1, step: 0.05, expected: 0.55, tolerance: 0.000001,
                    format: "value => (value > 0 ? '+' : '') + value.toFixed(2) + '×'"},
                {tag: "window-radius", from: 0, to: 32, step: 1, expected: 24, tolerance: 2,
                    format: "value => Math.round(value) + ' px'"}
            ];
        }

        function test_row_allocation_stays_fixed_during_slider_readout_changes(data) {
            const row = createTemporaryQmlObject("import QtQuick; import qs.Ui; FormRow { width: 2000; label: 'Value'; SavedSlider { objectName: 'input'; from: " + data.from
                + "; to: " + data.to + "; stepSize: " + data.step + "; shown: 0; formatValue: " + data.format
                + "; property bool observeWidth: false; property real narrowest: width; property real savedValue: NaN; onWidthChanged: if (observeWidth) narrowest = Math.min(narrowest, width); onSaved: value => { savedValue = value; shown = value; } } }", parent);
            verify(row !== null);
            const input = findChild(row, "input");
            verify(input !== null);
            compareWidth(input, Theme.control.maxWidth);
            input.narrowest = input.width;
            input.observeWidth = true;
            const bar = input.slider;
            const x = bar.width * 3 / 4;
            const y = bar.height / 2;
            mousePress(bar, x, y);
            mouseRelease(bar, x, y);
            compare(input.narrowest, Theme.control.maxWidth, "a growing readout never shrinks the row's box during the press");
            fuzzyCompare(input.savedValue, data.expected, data.tolerance, "the original pointer position saves the requested value");
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

            if (data.minimum === Theme.field.minWidth) {
                const outside = createTemporaryQmlObject("import QtQuick; Item { width: 240; height: 100 }", parent);
                input.parent = outside;
                compareWidth(input, 240);
                outside.width = 2000;
                compareWidth(input, 2000);
            }
        }
    }
}
