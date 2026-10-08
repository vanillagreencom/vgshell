#!/usr/bin/env node
// Production TrafficLogic over kernel text fixtures. Controls mutate a
// source copy in a fresh VM; each must break its own contract assertion.
// inputs: shell/plugins/vgs.traffic/TrafficLogic.js scripts/fixtures/traffic/* bin/lib/qml-library.js
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { load } = require("../bin/lib/qml-library.js");
const sourcePath = path.join(__dirname, "../shell/plugins/vgs.traffic/TrafficLogic.js");
const source = fs.readFileSync(sourcePath, "utf8");
const logic = load(sourcePath);
const plain = value => JSON.parse(JSON.stringify(value));
const fixture = name => fs.readFileSync(path.join(__dirname, "fixtures/traffic", name), "utf8");
const before = fixture("net-dev-before.txt"), after = fixture("net-dev-after.txt");
const socketBefore = fixture("ss-before.txt"), socketAfter = fixture("ss-after.txt");
let passed = 0;
function test(name, fn) { fn(logic); passed++; console.log("ok traffic=" + name); }
const names = ["enp5s0", "wlan0", "lo", "wg0"];
const resolved = ["/sys/devices/pci0000:00/net/enp5s0", "/sys/devices/pci0000:00/net/wlan0",
    "/sys/devices/virtual/net/lo", "/sys/devices/virtual/net/wg0"];
function virtualSkip(api) { assert.deepEqual(plain(api.physicalInterfaces(names, resolved)), ["enp5s0", "wlan0"]); }
function elapsed(api) {
    assert.deepEqual(plain(api.totals(api.parseNetDev(after), api.parseNetDev(before), ["enp5s0", "wlan0"], 4000, 1000)), {
        down: 2500, up: 2000, interfaces: [{ name: "enp5s0", down: 2000, up: 1000 }, { name: "wlan0", down: 500, up: 1000 }]
    });
}
function acked(api) { assert.equal(api.parseSockets(socketBefore)["10"].up, 1000); }
function omittedZeroCounters(api) {
    // iproute2 ss tcp_stats_print omits byte fields whose counters are zero.
    for (const [name, fields, up, down] of [
        ["upload omitted", "bytes_received:100", 0, 100],
        ["download omitted", "bytes_acked:50", 50, 0],
        ["both omitted", "cubic rto:200", 0, 0]
    ]) {
        const sockets = api.parseSockets('ESTAB 0 0 192.0.2.2:1234 198.51.100.1:443 users:(("App",pid=42,fd=8)) ino:17\n\t' + fields);
        assert(Object.prototype.hasOwnProperty.call(sockets, "17"), name + ": socket retained");
        assert.equal(sockets["17"].up, up, name + ": upload");
        assert.equal(sockets["17"].down, down, name + ": download");
    }
}
test("net-dev-fields", api => {
    assert.deepEqual(plain(api.parseNetDev(before).enp5s0), { down: 1000, up: 2000 });
    assert.equal(api.parseNetDev("unreadable"), null);
    assert.equal(api.parseNetDev(before.replace("1000 1", "bad 1")), null);
});
test("physical-virtual-skip", virtualSkip);
test("elapsed-time", elapsed);
test("counter-backwards-and-rebaseline", api => {
    const a = api.parseNetDev(before), b = api.parseNetDev(after);
    const unknown = api.totals(a, b, ["enp5s0"], 7000, 4000);
    assert.equal(unknown.down, null); assert.equal(unknown.up, null);
    assert.equal(api.totals(b, a, ["enp5s0"], 10000, 7000).down, 2000);
    assert.equal(api.totals(b, a, ["enp5s0"], 4000, 4000).down, null);
    assert.equal(api.totals(b, null, ["enp5s0"], 4000, 0).down, null);
});
test("ss-acked-inode-ipv6-own-process-and-loopback", api => {
    acked(api);
    const sockets = plain(api.parseSockets(socketBefore));
    assert.deepEqual(Object.keys(sockets), ["10", "11", "12"]);
    assert.deepEqual(sockets["11"], { name: "Browser", up: 50, down: 100 });
    assert.equal(sockets["12"].name, "");
    assert.equal(Object.keys(api.parseSockets(socketAfter)).includes("16"), false);
    assert.equal(api.loopback("[2001:db8::1]:443"), false);
    assert.equal(api.loopback("127.19.2.3:443"), true);
});
test("ss-omitted-zero-counters", omittedZeroCounters);
test("per-inode-new-socket-merged-name-and-remainder", api => {
    const a = api.parseSockets(socketBefore), b = api.parseSockets(socketAfter);
    assert.equal(api.apps(a, null, 1000, 0, { down: 6000, up: 4000 }).state, "measuring");
    const result = plain(api.apps(b, a, 4000, 1000, { down: 6000, up: 4000 }));
    assert.deepEqual(result, { state: "ready", apps: [
        { name: "Browser", down: 3000, up: 1500, connections: 2 },
        { name: "Player", down: 1000, up: 500, connections: 1 }
    ], other: { down: 2000, up: 2000 } });
    assert.deepEqual(plain(api.apps(b, a, 4000, 1000, { down: 1, up: 1 }).other), { down: 0, up: 0 });
    assert.deepEqual(plain(api.apps(b, a, 4000, 1000, { down: null, up: null }).other), { down: null, up: null });
    assert.equal(api.apps(a, b, 7000, 4000, { down: 0, up: 0 }).apps[0].down, null);
    assert.equal(api.apps({}, {}, 4000, 1000, { down: 0, up: 0 }).state, "idle");
    assert.equal(api.apps({}, a, 4000, 1000, { down: 12, up: 0 }).apps.length, 0);
});
test("bounded-sockets-and-apps", api => {
    const text = Array.from({ length: 4200 }, (_, i) => `ESTAB 0 0 192.168.1.2:${i + 1000} 93.184.216.34:443 users:(("App${i}",pid=42,fd=8)) ino:${i + 1}\n\tbytes_acked:3 bytes_received:6`).join("\n");
    const sockets = api.parseSockets(text);
    assert.equal(Object.keys(sockets).length, 4096);
    const result = api.apps(sockets, {}, 4000, 1000, { down: 9000, up: 8000 });
    assert.equal(result.apps.length, 50);
    assert.equal(result.other.down, 8900); assert.equal(result.other.up, 7950);
    const proto = api.parseSockets('ESTAB 0 0 192.168.1.2:1234 93.184.216.34:443 users:(("__proto__",pid=42,fd=8)) ino:9\n\tbytes_acked:3 bytes_received:6');
    assert.equal(api.apps(proto, {}, 4000, 1000, { down: 10, up: 10 }).apps[0].name, "__proto__");
});
test("formatter-steps-and-unknown", api => {
    for (const [input, expected] of [[0,"0 B/s"], [1023,"1023 B/s"], [1024,"1.0 KB/s"], [34816,"34.0 KB/s"], [1048576,"1.0 MB/s"], [1073741824,"1.0 GB/s"], [null,"--"], [undefined,"--"], [-1,"--"], [NaN,"--"]]) assert.equal(api.formatRate(input), expected);
});
test("capture-state-actions", api => {
    for (const [state, tone, action] of [["ready","ok",false], ["needed","warning",true], ["nixos","warning",true], ["absent","info",false], ["denied","warning",false], ["unknown","warning",false]]) {
        const result = api.capture({ state }); assert.equal(result.tone, tone); assert.equal(result.action, action);
    }
});
for (const [name, old, replacement, verify] of [
    ["bytes-sent", 'const down = /\\bbytes_received:(\\d+)/.exec(line), up = /\\bbytes_acked:(\\d+)/.exec(line);', 'const down = /\\bbytes_received:(\\d+)/.exec(line), up = /\\bbytes_sent:(\\d+)/.exec(line);', acked],
    ["omitted-upload-unknown", 'acked = up ? Number(up[1]) : 0', 'acked = up ? Number(up[1]) : NaN', omittedZeroCounters],
    ["omitted-download-unknown", 'const received = down ? Number(down[1]) : 0', 'const received = down ? Number(down[1]) : NaN', omittedZeroCounters],
    ["lo-counted", '!resolved[i].startsWith("/sys/devices/virtual/")', 'true', virtualSkip],
    ["configured-interval", 'const seconds = (at - previousAt) / 1000;', 'const seconds = 2;', elapsed],
    ["backwards-known", 'current < previous || ', '', api => assert.equal(api.delta(3, 5, 1), null)],
    ["new-socket-baseline", 'previous[inode] || { down: 0, up: 0 }', 'previous[inode] || socket', api => assert.equal(api.apps({ 1: { name: "New", down: 6, up: 3 } }, {}, 3000, 0, { down: 20, up: 20 }).apps[0].down, 2)],
    ["loopback-counted", 'if (loopback(header.local) || loopback(header.peer))', 'if (false)', api => assert.equal(Object.keys(api.parseSockets(socketBefore)).includes("13"), false)],
    ["app-merge", 'merged[socket.name] = row;', 'merged["socket-" + inode] = row;', api => assert.equal(api.apps(api.parseSockets(socketAfter), api.parseSockets(socketBefore), 4000, 1000, { down: 9000, up: 9000 }).apps.filter(row => row.name === "Browser").length, 1)],
    ["negative-other", 'Math.max(0, total.down - rows.reduce((sum, row) => sum + row.down, 0))', 'total.down - rows.reduce((sum, row) => sum + row.down, 0)', api => assert.equal(api.apps({ 1: { name: "App", down: 6, up: 3 } }, {}, 3000, 0, { down: 1, up: 20 }).other.down, 0)],
    ["socket-cap", 'count >= 4096', 'count >= 4097', api => {
        const text = Array.from({ length: 4097 }, (_, i) => `ESTAB 0 0 192.0.2.2:1234 198.51.100.1:443 ino:${i + 1}\n\tbytes_acked:1`).join("\n");
        assert.equal(Object.keys(api.parseSockets(text)).length, 4096);
    }],
    ["app-cap", '.slice(0, 50)', '.slice(0, 51)', api => {
        const sockets = Object.fromEntries(Array.from({ length: 51 }, (_, i) => [String(i + 1), { name: "App" + i, down: 6, up: 3 }]));
        assert.equal(api.apps(sockets, {}, 3000, 0, { down: 1000, up: 1000 }).apps.length, 50);
    }],
    ["formatter-base", 'value /= 1024;', 'value /= 1000;', api => assert.equal(api.formatRate(34816), "34.0 KB/s")],
    ["net-dev-transmit-field", 'const down = Number(fields[0]), up = Number(fields[8]);', 'const down = Number(fields[0]), up = Number(fields[9]);', api => assert.equal(api.parseNetDev(before).enp5s0.up, 2000)],
    ["ipv6-loopback-counted", 'host === "::1"', 'host === "::2"', api => assert.equal(Object.keys(api.parseSockets(socketBefore)).includes("14"), false)],
    ["unknown-as-zero", 'return "--";', 'return "0 B/s";', api => assert.equal(api.formatRate(null), "--")],
    ["capture-action", 'action: state === "needed" || state === "nixos"', 'action: false', api => assert.equal(api.capture({ state: "needed" }).action, true)]
]) {
    assert(source.includes(old), "control match: " + name);
    const mutant = {};
    vm.runInNewContext(source.replace(/^\.pragma library\n/, "").replace(old, replacement), mutant, { filename: name });
    assert.throws(() => verify(mutant), { name: "AssertionError" });
    try { verify(mutant); } catch (error) { console.log("control traffic=" + name + " rejected=" + error.message); }
}
console.log("test-traffic-logic: passed=" + passed + " controls=17");
