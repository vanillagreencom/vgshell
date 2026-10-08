import QtQuick
import QtTest
import qs.Commons
import qs.Unit
import "../../shell/plugins/vgs.sysmon" as Sysmon

Item {
    id: root
    width: 900
    height: 200
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
                    if (child.reservedText !== undefined && child.iconName !== undefined) found.push(child);
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
        function test_fixed_width_from_five_to_one_hundred_percent() {
            verify(waitForRendering(widget));
            const width = widget.implicitWidth;
            const widths = items().map(item => item.implicitWidth);
            verify(width > 0);
            status.values = { readings: sample(100) };
            verify(waitForRendering(widget));
            compare(widget.implicitWidth, width);
            compare(JSON.stringify(items().map(item => item.implicitWidth)), JSON.stringify(widths));
        }
        function test_temperatures_swap_and_used_memory() {
            widget.settings = { showCpu: true, showMemory: true, showGpu: true,
                cpuTemperature: true, gpuTemperature: true, showSwap: true, memoryUnit: "used" };
            const readings = items();
            compare(readings[0].text + readings[0].count, "5%/54°");
            compare(readings[1].text, "1.0 GB");
            compare(readings[1].count, "· 0%");
            compare(readings[2].count, "42°");
            status.values = { readings: sample(null) };
            const empty = sample(null); empty.cpu.temperature = null; empty.gpu.temperature = null;
            status.values = { readings: empty };
            compare(readings[0].count, "/--");
            compare(readings[2].count, "--");
        }
        function test_fahrenheit_readings_keep_celsius_tones() {
            widget.settings = { showCpu: true, showGpu: true, cpuTemperature: true,
                gpuTemperature: true, temperatureUnit: "Fahrenheit" };
            const value = sample(12); value.cpu.temperature = 70; value.gpu.temperature = 65;
            status.values = { readings: value };
            const readings = items();
            compare(readings[0].text + readings[0].count, "12%/158°");
            compare(readings[2].count, "149°");
            compare(readings[0].countTone, Qt.color(Theme.color.warning));
            compare(readings[2].countTone, Qt.color(Theme.color.warning));
            verify(readings[0].tooltip.indexOf("158°") !== -1);
            verify(readings[2].tooltip.indexOf("149°") !== -1);
            verify(waitForRendering(widget));
            const width = widget.implicitWidth;
            status.values = { readings: sample(100) };
            verify(waitForRendering(widget));
            compare(widget.implicitWidth, width);
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
            compare(gpu.count, "--");
        }
    }
}
