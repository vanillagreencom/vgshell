import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.sysmon" as Sysmon

Item {
    id: root
    width: 900
    height: 900
    property var leaseCalls: []
    QtObject { id: status; property var values: ({}) }
    Component { id: widgetComponent; Sysmon.Widget {} }
    Component { id: panelComponent; Sysmon.Panel {} }

    TestCase {
        id: tests
        name: "sysmon_widget"
        when: windowShown
        property var widget: null

        function sample(use, gpu) {
            return { cpu: { use: use, temperature: 54, cores: 16 },
                memory: { use: use, used: 1073741824, total: 4294967296,
                    available: 3221225472, swapUse: 0, swapUsed: 0, swapTotal: 1073741824 },
                gpu: gpu === undefined ? { id: "gpu", name: "Fixture GPU", state: "awake", use: use, temperature: 42 } : gpu };
        }
        function scope() {
            return { status: status, settings: {}, requirements: { missing: ["btop"] },
                ipc: { call: function (method, argument) {
                    root.leaseCalls = root.leaseCalls.concat([[method, argument]]);
                    return "ok";
                } }, surfaces: { toggle: function () { return "ok"; } } };
        }
        function init() {
            verify(Theme.bar.height > 0);
            UnitTheme.reset();
            root.leaseCalls = [];
            status.values = { readings: sample(5) };
            widget = createTemporaryObject(widgetComponent, root, { shell: scope(),
                settings: { showCpu: true, showMemory: true, showGpu: true } });
            verify(widget !== null);
        }
        function cleanup() {
            if (widget !== null) { widget.destroy(); widget = null; }
            wait(0);
        }
        function items() {
            const found = [];
            function walk(node) {
                for (const child of node.children) {
                    if (child.compactCount !== undefined && child.iconName !== undefined) found.push(child);
                    walk(child);
                }
            }
            walk(widget);
            return found;
        }
        function shown() { return items().filter(item => item.visible).map(item => item.iconName); }
        function test_toggle_combinations_data() {
            const cases = [];
            for (let mask = 0; mask < 8; mask++) {
                const expected = [];
                if (mask & 1) expected.push("cpu");
                if (mask & 2) expected.push("memory-stick");
                if (mask & 4) expected.push("gpu");
                cases.push({ tag: String(mask), mask: mask, expected: expected });
            }
            return cases;
        }
        function test_toggle_combinations(data) {
            widget.settings = { showCpu: !!(data.mask & 1), showMemory: !!(data.mask & 2), showGpu: !!(data.mask & 4) };
            compare(JSON.stringify(shown()), JSON.stringify(data.expected));
            compare(widget.visible, data.mask !== 0);
        }
        function test_unknown_and_zero_are_distinct() {
            status.values = { readings: sample(null) };
            for (const item of items()) compare(item.text, "--");
            status.values = { readings: sample(0) };
            for (const item of items()) compare(item.text, "0%");
        }
        function drawn(item) {
            const found = [];
            function walk(node) {
                for (const child of node.children) {
                    if (child.role !== undefined && child.visible) found.push(child);
                    walk(child);
                }
            }
            walk(item.contentItem);
            return found;
        }
        // The expected width adds the padding to the icon and the drawn
        // labels' own widths, so room kept past the reading turns it red.
        function drawnWidth(item) {
            let content = Theme.bar.item.icon + Theme.bar.item.iconGap;
            for (const label of drawn(item)) content += label.implicitWidth;
            return item.leftPadding + Math.ceil(content) + item.rightPadding;
        }
        function allReadings() {
            return { showCpu: true, showMemory: true, showGpu: true,
                cpuTemperature: true, gpuTemperature: true, showSwap: true };
        }
        function test_each_item_ends_at_its_reading_data() {
            return [
                { tag: "values", settings: { showCpu: true, showMemory: true, showGpu: true } },
                { tag: "both-values", settings: allReadings() }
            ];
        }
        function test_each_item_ends_at_its_reading(data) {
            widget.settings = data.settings;
            const shownItems = items().filter(item => item.visible);
            compare(shownItems.length, 3);
            for (const item of shownItems) {
                compare(item.leftPadding, Theme.bar.item.paddingX);
                compare(item.rightPadding, Theme.bar.item.paddingX);
                tryVerify(() => item.implicitWidth === drawnWidth(item), 1000, item.label + " keeps no room after its reading");
            }
        }
        function test_width_moves_only_with_the_character_count() {
            widget.settings = allReadings();
            const cpu = items()[0];
            tryVerify(() => cpu.implicitWidth === drawnWidth(cpu), 1000, "the CPU item lays out its reading");
            const five = cpu.implicitWidth;
            status.values = { readings: sample(7) };
            compare(cpu.text, "7%");
            verify(waitForRendering(widget));
            compare(cpu.implicitWidth, five, "a reading with the same character count keeps its width");
            status.values = { readings: sample(100) };
            compare(cpu.text, "100%");
            tryVerify(() => cpu.implicitWidth === drawnWidth(cpu), 1000, "the CPU item lays out its longer reading");
            const advance = drawn(cpu)[0].implicitWidth / cpu.text.length;
            verify(advance > 0);
            fuzzyCompare(cpu.implicitWidth - five, 2 * advance, 1, "two more characters widen the item by two advances");
        }
        function test_widget_spaces_its_items_by_the_bar_gap_data() {
            return [
                { tag: "three", settings: allReadings(), shown: 3 },
                { tag: "cpu-gpu", settings: { showCpu: true, showMemory: false, showGpu: true }, shown: 2 },
                { tag: "memory", settings: { showCpu: false, showMemory: true, showGpu: false }, shown: 1 }
            ];
        }
        function test_widget_spaces_its_items_by_the_bar_gap(data) {
            widget.settings = data.settings;
            const shownItems = items().filter(item => item.visible);
            compare(shownItems.length, data.shown);
            tryVerify(() => shownItems.every(item => item.width === drawnWidth(item)), 1000, "each item lays out its reading");
            const expected = () => shownItems.reduce((total, item) => total + item.width, 0) + (shownItems.length - 1) * Theme.bar.gap;
            tryVerify(() => widget.implicitWidth === expected(), 1000, "the widget is its items and the bar gap between them");
        }
        function test_temperatures_swap_and_used_memory() {
            widget.settings = { showCpu: true, showMemory: true, showGpu: true,
                cpuTemperature: true, gpuTemperature: true, showSwap: true, memoryUnit: "used" };
            const readings = items();
            compare(readings[0].text + readings[0].count, "5%/54°");
            compare(readings[1].text + readings[1].count, "1.0 GB/0%");
            compare(readings[2].text + readings[2].count, "5%/42°");
            for (const item of readings) compare(item.compactCount, true, item.label + " draws its count against its value");
            status.values = { readings: sample(null) };
            const empty = sample(null); empty.cpu.temperature = null; empty.gpu.temperature = null;
            status.values = { readings: empty };
            compare(readings[0].count, "/--");
            compare(readings[2].count, "/--");
        }
        function test_fahrenheit_readings_keep_celsius_tones() {
            widget.settings = { showCpu: true, showGpu: true, cpuTemperature: true,
                gpuTemperature: true, temperatureUnit: "Fahrenheit" };
            const value = sample(12); value.cpu.temperature = 70; value.gpu.temperature = 65;
            status.values = { readings: value };
            const readings = items();
            compare(readings[0].text + readings[0].count, "12%/158°");
            compare(readings[2].count, "/149°");
            compare(readings[0].countTone, Qt.color(Theme.color.warning));
            compare(readings[2].countTone, Qt.color(Theme.color.warning));
            verify(readings[0].tooltip.indexOf("158°") !== -1);
            verify(readings[2].tooltip.indexOf("149°") !== -1);
            const shownItems = readings.filter(row => row.visible);
            tryVerify(() => shownItems.every(item => item.implicitWidth === drawnWidth(item)), 1000, "each item lays out its Fahrenheit reading");
            const widths = readings.map(item => item.implicitWidth);
            const next = sample(45); next.cpu.temperature = 85; next.gpu.temperature = 80;
            status.values = { readings: next };
            compare(readings[0].text + readings[0].count, "45%/185°");
            compare(readings[2].count, "/176°");
            verify(waitForRendering(widget));
            compare(JSON.stringify(readings.map(item => item.implicitWidth)), JSON.stringify(widths), "the same character count keeps each width");
        }
        function test_panel_converts_cpu_and_gpu_details() {
            const facade = scope(); facade.settings = { temperatureUnit: "Fahrenheit" };
            const panel = createTemporaryObject(panelComponent, root, { shell: facade });
            verify(panel !== null);
            const found = [];
            function walk(node) {
                for (const child of node.children) {
                    if (child.details !== undefined && child.title !== undefined && child.iconName !== undefined) found.push(child);
                    walk(child);
                }
            }
            walk(panel);
            verify(found.find(item => item.iconName === "cpu").details[0].indexOf("129°") !== -1);
            verify(found.find(item => item.iconName === "gpu").details[1].indexOf("108°") !== -1);
            const reading = sample(5); reading.cpu.temperature = null; reading.gpu.temperature = null;
            status.values = { readings: reading };
            verify(found.find(item => item.iconName === "cpu").details[0].indexOf("--") !== -1);
            verify(found.find(item => item.iconName === "gpu").details[1].indexOf("--") !== -1);
        }
        function descendants(item) {
            const found = [];
            function walk(node) {
                for (const child of node.children) { found.push(child); walk(child); }
            }
            walk(item);
            return found;
        }
        function panelReadings(panel) {
            return descendants(panel).filter(item => item.details !== undefined && item.iconName !== undefined);
        }
        function detailRows(reading) {
            const repeated = reading.children.find(item => item instanceof Repeater);
            return Array.from({ length: repeated.count }, (_, index) => repeated.itemAt(index));
        }
        function test_panel_sampling_keeps_detail_rows_and_live_text() {
            const panel = createTemporaryObject(panelComponent, root, { shell: scope() });
            verify(panel !== null);
            const readings = panelReadings(panel);
            const held = readings.map(detailRows);
            const value = sample(12);
            value.cpu.temperature = 63;
            value.memory.available = 2147483648;
            value.gpu.temperature = 58;
            status.values = { readings: value };
            for (let group = 0; group < readings.length; group++) {
                const rows = detailRows(readings[group]);
                compare(rows.length, held[group].length);
                for (let index = 0; index < rows.length; index++) {
                    compare(rows[index], held[group][index], "sampling retains each existing detail Label");
                    compare(rows[index].text, readings[group].details[index], "the retained row draws the live value");
                }
            }
            verify(waitForRendering(panel));
            // QtTest crops grabImage at the item's local x/y. Capture the
            // root and map nested detail bounds into that image instead.
            // Compare against the same panel with only these glyphs hidden:
            // an opaque background alone cannot satisfy this paint check.
            // https://github.com/qt/qtdeclarative/blob/v6.11.2/src/qmltest/quicktestresult.cpp
            const rows = [];
            for (const group of held) for (const row of group) rows.push(row);
            const opacities = rows.map(row => row.opacity);
            const painted = grabImage(root);
            let blank;
            try {
                for (const row of rows) row.opacity = 0;
                verify(waitForRendering(panel));
                blank = grabImage(root);
            } finally {
                for (let index = 0; index < rows.length; index++) rows[index].opacity = opacities[index];
            }
            verify(waitForRendering(panel));
            const scaleX = painted.width / root.width;
            const scaleY = painted.height / root.height;
            for (const row of rows) {
                const point = row.mapToItem(root, 0, 0);
                const left = Math.floor(point.x * scaleX);
                const top = Math.floor(point.y * scaleY);
                const right = Math.ceil((point.x + row.width) * scaleX);
                const bottom = Math.ceil((point.y + row.height) * scaleY);
                verify(left >= 0 && top >= 0 && right <= painted.width && bottom <= painted.height);
                verify(right > left && bottom > top, "the detail region is nonempty");
                let ink = false;
                for (let x = left; x < right && !ink; x++)
                    for (let y = top; y < bottom && !ink; y++)
                        ink = !Qt.colorEqual(painted.pixel(x, y), blank.pixel(x, y));
                verify(ink, "each retained detail row paints the updated sample");
            }
            compare(held[0][0].text, "Temperature 63° · 16 cores");
            compare(held[1][1].text, "2.0 GB available");
            compare(held[2][1].text, "Temperature 58°");
            status.values = { readings: sample(5, { name: "Sleeping GPU", state: "asleep" }) };
            const asleep = readings.find(item => item.iconName === "gpu");
            compare(detailRows(asleep).length, 1, "sleep intentionally changes the detail count");
            compare(detailRows(asleep)[0].text, "The graphics card is asleep.");
            status.values = { readings: sample(5, null) };
            compare(asleep.visible, false);
        }
        function test_panel_reading_hover_and_click_keep_geometry_focus_and_scroll() {
            const facade = scope(); facade.requirements.missing = [];
            facade.tui = { run: () => "ok" }; facade.surfaces.hide = () => "ok";
            const panel = createTemporaryObject(panelComponent, root, { shell: facade });
            verify(panel !== null);
            panel.height = Qt.binding(() => panel.implicitHeight);
            panel.forceActiveFocus(Qt.OtherFocusReason);
            verify(waitForRendering(panel));
            const readings = panelReadings(panel);
            const pane = descendants(panel).find(item => item instanceof Pane);
            const originalFocus = root.Window.window.activeFocusItem;
            const originalScroll = pane.scrollArea.contentY;
            const boxes = readings.map(item => [item.y, item.height, item.childrenRect.height]);
            for (const reading of readings) {
                mouseMove(reading, reading.width / 2, reading.height / 2);
                verify(waitForRendering(panel));
                compare(JSON.stringify(readings.map(item => [item.y, item.height, item.childrenRect.height])), JSON.stringify(boxes), "hover adds no layout row");
                mouseClick(reading, reading.width / 2, reading.height / 2);
                verify(waitForRendering(panel));
                compare(root.Window.window.activeFocusItem, originalFocus, "a reading click leaves keyboard focus in the body");
                compare(pane.scrollArea.contentY, originalScroll, "a reading click does not scroll");
                verify(!descendants(reading).some(item => item instanceof FocusRing && item.visible), "a reading click draws no focus ring");
            }
            const seeAll = descendants(panel).find(item => item instanceof Button && item.text === "See all");
            verify(seeAll !== undefined && seeAll.visible);
            seeAll.forceActiveFocus(Qt.TabFocusReason);
            compare(seeAll.activeFocus, true, "See all remains keyboard accessible");
        }
        function test_production_tone_boundaries_data() {
            const rules = [
                { name: "cpu-use", reading: "cpu", field: "use", icon: "cpu", output: "tone", warning: 60, danger: 80 },
                { name: "memory-use", reading: "memory", field: "use", icon: "memory-stick", output: "tone", warning: 75, danger: 90 },
                { name: "cpu-temperature", reading: "cpu", field: "temperature", icon: "cpu", output: "countTone", warning: 70, danger: 85 },
                { name: "gpu-temperature", reading: "gpu", field: "temperature", icon: "gpu", output: "countTone", warning: 65, danger: 80 }
            ];
            const cases = [];
            for (const rule of rules) {
                const values = [
                    { value: null, expected: Theme.bar.foreground },
                    { value: rule.warning - 1, expected: Theme.bar.foreground },
                    { value: rule.warning, expected: Theme.color.warning },
                    { value: rule.warning + 1, expected: Theme.color.warning },
                    { value: rule.danger - 1, expected: Theme.color.warning },
                    { value: rule.danger, expected: Theme.color.danger },
                    { value: rule.danger + 1, expected: Theme.color.danger }
                ];
                for (const row of values) cases.push(Object.assign({ tag: rule.name + "-" + row.value }, rule, row));
            }
            return cases;
        }
        function test_production_tone_boundaries(data) {
            widget.settings = { showCpu: true, showMemory: true, showGpu: true, cpuTemperature: true, gpuTemperature: true };
            const reading = sample(5);
            reading[data.reading][data.field] = data.value;
            status.values = { readings: reading };
            const item = items().find(row => row.iconName === data.icon);
            verify(item !== undefined);
            compare(item[data.output], Qt.color(data.expected));
        }
        function test_widget_lease_lifetime() {
            compare(root.leaseCalls.length, 1);
            compare(root.leaseCalls[0][0], "lease");
            const opened = JSON.parse(root.leaseCalls[0][1]);
            compare(opened.open, true);
            widget.shell = scope();
            compare(root.leaseCalls.length, 1);
            widget.destroy(); widget = null;
            wait(0);
            compare(root.leaseCalls.length, 2);
            const closed = JSON.parse(root.leaseCalls[1][1]);
            compare(closed.open, false);
            compare(closed.id, opened.id);
        }
        function test_no_gpu_and_sleeping_gpu() {
            status.values = { readings: sample(5, null) };
            compare(JSON.stringify(shown()), JSON.stringify(["cpu", "memory-stick"]));
            widget.settings = { showCpu: false, showMemory: false, showGpu: true, gpuTemperature: true };
            compare(widget.visible, false);
            status.values = { readings: sample(5, { name: "Sleeping GPU", state: "asleep", use: 95, temperature: 75 }) };
            compare(widget.visible, true);
            const gpu = items()[2];
            compare(gpu.text, "--");
            compare(gpu.count, "/--");
        }
    }
}
