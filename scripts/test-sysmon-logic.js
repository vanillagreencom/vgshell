#!/usr/bin/env node
// inputs: shell/plugins/vgs.sysmon/SysmonLogic.js bin/lib/qml-library.js
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");
const file = process.env.SYS_MON_LOGIC_PATH || path.join(__dirname, "../shell/plugins/vgs.sysmon/SysmonLogic.js");
const plain = value => JSON.parse(JSON.stringify(value));
const before = "cpu 100 20 30 400 50 5 5 10 30 4\ncpu0 50 10 15 200 25 2 2 5 15 2\ncpu1 50 10 15 200 25 3 3 5 15 2\n";
const after = "cpu 120 20 40 440 70 5 5 20 40 5\ncpu0 60 10 20 220 35 2 2 10 20 2\ncpu1 60 10 20 220 35 3 3 10 20 3\n";
const meminfo = "MemTotal: 10000 kB\nMemFree: 1000 kB\nMemAvailable: 4000 kB\nSwapTotal: 2000 kB\nSwapFree: 1500 kB\n";
function suite(logic) {
    const a = logic.cpuCounters(before), b = logic.cpuCounters(after);
    assert.equal(a.total, 620, "CPU guest fields must not add to total");
    assert.equal(a.idle, 450, "CPU iowait belongs to idle");
    assert.equal(a.cores, 2);
    assert.equal(logic.cpuUse(a, b), 40, "CPU delta must exclude iowait from busy");
    assert.equal(logic.cpuUse(null, b), null);
    assert.equal(logic.cpuUse(a, a), null);
    for (const [text, want] of [
        [after.replace("120 20 40", "99 20 100"), null],
        [after.replace("440 70", "440 49"), null],
        ["cpu 100 20 30 500 50 5 5 10 30 4\n", 0],
        ["cpu 200 20 30 400 50 5 5 10 30 4\n", 100]
    ]) assert.equal(logic.cpuUse(a, logic.cpuCounters(text)), want);
    for (const text of ["", "cpu0 1 2 3 4 5 6 7 8", "cpu 1 2 x 4 5 6 7 8", "cpu 1 2 3 -1 5 6 7 8", "cpu 1 2 3 4 5 6 7"])
        assert.equal(logic.cpuCounters(text), null);
    assert.equal(logic.cpuUse(logic.cpuCounters(before.replace(/\n/g, "\r\n")), b), 40);
    assert.deepEqual(plain(logic.memory(meminfo)), { total: 10240000, available: 4096000,
        used: 6144000, use: 60, swapTotal: 2048000, swapUsed: 512000, swapUse: 25 });
    assert.equal(logic.memory(meminfo.replace(/\n/g, "\r\n")).used, 6144000);
    for (const [text, field, want] of [
        ["MemTotal: 10 kB\nMemFree: 5 kB\n", "used", null],
        ["MemTotal: 10 kB\nMemAvailable: 10 kB\n", "use", 0],
        ["MemTotal: 10 kB\nMemAvailable: 0 kB\n", "use", 100],
        ["SwapTotal: 0 kB\nSwapFree: 0 kB\n", "swapUse", 0],
        ["MemTotal: 0 kB\nMemAvailable: 0 kB\n", "use", null],
        ["MemTotal: 10 kB\nMemAvailable: 11 kB\n", "used", null],
        ["MemTotal: 10 MB\nMemAvailable: 5 kB\n", "used", null],
        ["MemTotal: 10 kB\nMemAvailable: 5 kB\nMemAvailable: 4 kB\n", "used", null],
        ["SwapTotal: 10 kB\nSwapFree: 11 kB\n", "swapUsed", null],
        ["", "total", null]
    ]) assert.equal(logic.memory(text)[field], want);
    const device = (name, label, sensorPath) => ({ name, path: sensorPath.split("/temp")[0], temperatures: [{ label, path: sensorPath }] });
    const k10 = device("k10temp", "Tctl", "/hwmon7/temp2_input");
    const zen = device("zenpower", "Tdie", "/hwmon2/temp1_input");
    const core = device("coretemp", "Package id 0", "/hwmon5/temp1_input");
    const thermal = [{ type: "acpitz", path: "/thermal0/temp" }, { type: "x86_pkg_temp", path: "/thermal9/temp" }];
    for (const [devices, zones, want] of [
        [[core, zen, k10], thermal, "/hwmon7/temp2_input"],
        [[core, zen], thermal, "/hwmon2/temp1_input"],
        [[device("coretemp", "Core 0", "/wrong"), core], thermal, "/hwmon5/temp1_input"],
        [[], thermal, "/thermal9/temp"],
        [[device("k10temp", "Tccd1", "/wrong")], [], null],
        [[], [], null]
    ]) assert.equal(logic.chooseCpuTemperature(devices, zones), want);
    for (const [raw, want] of [["54000\n", 54], ["0", 0], ["-5000", -5], ["[N/A]", null], ["", null], ["4x", null]])
        assert.equal(logic.temperature(raw), want);
    for (const [raw, want] of [["0", 0], ["3.5\n", 3.5], ["", null], [undefined, null], ["[N/A]", null], ["N/A", null], ["-1", null], ["4x", null]])
        assert.equal(logic.number(raw), want);
    assert.deepEqual(plain(logic.amdGpu({ use: "17\n", vramUsed: "1073741824\n", vramTotal: "8589934592\n", temperature: "63000\n" })),
        { use: 17, vramUsed: 1073741824, vramTotal: 8589934592, temperature: 63 });
    assert.deepEqual(plain(logic.amdGpu({ use: "0", vramUsed: "0", vramTotal: "0", temperature: "0" })),
        { use: 0, vramUsed: 0, vramTotal: 0, temperature: 0 });
    assert.deepEqual(plain(logic.amdGpu({ use: "101", vramUsed: "", vramTotal: "[N/A]", temperature: "bad" })),
        { use: null, vramUsed: null, vramTotal: null, temperature: null });
    assert.deepEqual(plain(logic.nvidiaRows("0, 00000000:0A:00.0, NVIDIA RTX 5090, 0, 1024, 32768, 54\r\n1, 0000:0b:00.0, NVIDIA Sleep, [N/A], [N/A], [N/A], [N/A]\n")), [
        { id: "0000:0a:00.0", index: 0, name: "NVIDIA RTX 5090", use: 0, vramUsed: 1073741824, vramTotal: 34359738368, temperature: 54 },
        { id: "0000:0b:00.0", index: 1, name: "NVIDIA Sleep", use: null, vramUsed: null, vramTotal: null, temperature: null }
    ]);
    assert.equal(logic.nvidiaRows('2, 0000:0c:00.0, "NVIDIA, model", 17, 0, 1024, 0')[0].name, "NVIDIA, model");
    for (const raw of ["", "garbage", "0, pci, NVIDIA, 1, 2, 3, 4", "-1, 0000:0a:00.0, NVIDIA, 1, 2, 3, 4", '0, 0000:0a:00.0, "unclosed, 1, 2, 3, 4'])
        assert.deepEqual(plain(logic.nvidiaRows(raw)), []);
    for (const [warning, danger] of [[60, 80], [75, 90], [70, 85], [65, 80]]) {
        for (const [value, want] of [[null, "normal"], [NaN, "normal"], [0, "normal"], [warning - 1, "normal"],
            [warning, "warning"], [danger - 1, "warning"], [danger, "danger"], [danger + 1, "danger"]])
            assert.equal(logic.tone(value, warning, danger), want);
    }
    const cards = [{ id: "intel", discrete: false, vramTotal: 64000 },
        { id: "amd", discrete: true, vramTotal: 8000 }, { id: "nv", discrete: true, vramTotal: 32000 }];
    assert.deepEqual(Array.from(logic.orderGpus(cards), row => row.id), ["nv", "amd", "intel"]);
    assert.equal(cards[0].id, "intel");
    assert.equal(logic.selectedGpu(cards, "").id, "intel");
    assert.equal(logic.selectedGpu(cards, "nv").id, "nv");
    assert.equal(logic.selectedGpu(cards, "removed"), null);
    assert.equal(logic.selectedGpu([], ""), null);
}
suite(load(file));
if (!process.env.SYS_MON_LOGIC_PATH) {
    const source = fs.readFileSync(file, "utf8");
    const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "sysmon-controls-"));
    const logDir = process.env.SYS_MON_CONTROL_LOG_DIR;
    if (logDir) fs.mkdirSync(logDir, { recursive: true });
    try {
        for (const [name, needle, replacement, matchCount = 1] of [
            ["memory-available", "MemAvailable", "MemFree", 3],
            ["cpu-iowait", "idle: counters[3] + counters[4]", "idle: counters[3]"],
            ["tone-boundary", "value >= warning", "value > warning"],
            ["cpu-guest", "fields.slice(1, 9)", "fields.slice(1, 11)"],
            ["cpu-backwards", "value < previous.counters[index]", "false"],
            ["hwmon-label", 'label: "Tctl"', 'label: "Tccd1"'],
            ["amd-temperature-unit", "value / 1000", "value"],
            ["nvidia-memory-unit", "vramUsed: used === null ? null : used * 1048576", "vramUsed: used === null ? null : used"]
        ]) {
            assert.equal(source.split(needle).length - 1, matchCount, name + " mutation match count");
            const changed = source.split(needle).join(replacement);
            assert.notEqual(changed, source);
            const mutant = path.join(scratch, "SysmonLogic.js");
            fs.writeFileSync(mutant, changed, { flag: "w" });
            let failure = null;
            try { suite(load(mutant)); } catch (error) { failure = error; }
            assert.equal(failure && failure.code, "ERR_ASSERTION", "control did not fail an assertion: " + name);
            if (logDir) fs.writeFileSync(path.join(logDir, name + ".log"), String(failure.stack) + "\n");
            console.log("sysmon-logic: control=" + name + " red");
        }
    } finally { fs.rmSync(scratch, { recursive: true, force: true }); }
}
console.log("sysmon-logic: passed");
