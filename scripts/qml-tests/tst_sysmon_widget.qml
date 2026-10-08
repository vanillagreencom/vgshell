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
            return { status: status,
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
            wait(0);
            const width = widget.implicitWidth;
            const widths = items().map(item => item.implicitWidth);
            verify(width > 0);
            status.values = { readings: sample(100) };
            wait(0);
            compare(widget.implicitWidth, width);
            compare(JSON.stringify(items().map(item => item.implicitWidth)), JSON.stringify(widths));
        }
        function test_temperatures_swap_and_used_memory() {
            widget.settings = { showCpu: true, showMemory: true, showGpu: true,
                cpuTemperature: true, gpuTemperature: true, showSwap: true, memoryUnit: "used" };
            const readings = items();
            compare(readings[0].count, "54°");
            compare(readings[1].text, "1.0 GB");
            compare(readings[1].count, "· 0%");
            compare(readings[2].count, "42°");
            status.values = { readings: sample(null) };
            const empty = sample(null); empty.cpu.temperature = null; empty.gpu.temperature = null;
            status.values = { readings: empty };
            compare(readings[0].count, "--");
            compare(readings[2].count, "--");
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
