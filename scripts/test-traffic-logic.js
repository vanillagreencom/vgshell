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
    assert.deepEqual(sockets["11"], { name: "Browser", pids: [44], state: "ESTAB", peer: "[2001:db8:1::3]:443", up: 50, down: 100 });
    assert.deepEqual(sockets["12"].pids, []);
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
function kbDigits(api) { assert.equal(api.formatRate(34816, 0, 1), "34 KB/s"); assert.equal(api.formatRate(35328, 1, 0), "34.5 KB/s"); }
test("formatter-steps-digits-and-unknown", api => {
    // The manifest's defaults: whole KB/s, MB/s and up with one decimal.
    for (const [input, kb, mb, expected] of [[0,0,1,"0 B/s"], [1023,2,2,"1023 B/s"], [1024,0,1,"1 KB/s"], [34816,0,1,"34 KB/s"],
        [35328,1,1,"34.5 KB/s"], [35328,2,0,"34.50 KB/s"], [1048576,0,1,"1.0 MB/s"], [12.2 * 1048576,0,1,"12.2 MB/s"], [12.25 * 1048576,0,2,"12.25 MB/s"],
        [12.2 * 1048576,1,0,"12 MB/s"], [1073741824,0,1,"1.0 GB/s"], [null,0,1,"--"], [undefined,0,1,"--"], [-1,0,1,"--"], [NaN,0,1,"--"]])
        assert.equal(api.formatRate(input, kb, mb), expected, input + " " + kb + " " + mb);
    kbDigits(api);
});
function rateSamples(api) {
    for (const [whole, kb, mb, expected] of [[2,0,1,"88.8 MB/s"], [3,0,1,"888.8 MB/s"], [2,2,1,"88.88 KB/s"], [2,0,0,"88 MB/s"], [2,1,1,"88.8 MB/s"]])
        assert.equal(api.rateSample(whole, kb, mb), expected);
}
test("rate-sample-is-the-widest-unit", rateSamples);
const owners = 'ESTAB 0 0 192.0.2.2:1234 198.51.100.1:443 users:(("a\\"b",pid=7,fd=3),("a\\"b",pid=7,fd=4),("helper",pid=9,fd=1),("a\\"b",pid=8,fd=2)) ino:5\n\tbytes_acked:3';
function ownerName(api) { assert.deepEqual(plain(api.parseSockets(owners)["5"]).pids, [7, 8]); }
test("ss-owner-pids-per-name", api => {
    const socket = plain(api.parseSockets(owners)["5"]);
    assert.equal(socket.name, 'a"b');
    ownerName(api);
});
const world = () => ({
    1: { name: "Browser", pids: [44, 42], state: "ESTAB", peer: "198.51.100.9:443", down: 0, up: 0 },
    2: { name: "Browser", pids: [42], state: "FIN-WAIT-1", peer: "198.51.100.1:443", down: 0, up: 0 },
    3: { name: "Player", pids: [50], state: "ESTAB", peer: "[2001:db8::1]:443", down: 0, up: 0 },
    4: { name: "", pids: [], state: "ESTAB", peer: "198.51.100.2:443", down: 0, up: 0 }
});
test("inspect-processes-and-connections", api => {
    assert.deepEqual(plain(api.inspect(world(), "Browser")), { name: "Browser", pids: [42, 44],
        connections: [{ peer: "198.51.100.1:443", state: "FIN-WAIT-1" }, { peer: "198.51.100.9:443", state: "ESTAB" }], connectionCount: 2 });
    assert.equal(api.inspect(world(), "Absent"), null);
    assert.equal(api.inspect(world(), ""), null);
    assert.equal(api.inspect(null, "Browser"), null);
    inspectCap(api);
});
function inspectCap(api) {
    const many = Object.fromEntries(Array.from({ length: api.INSPECT_ROWS + 3 }, (_, i) => [String(i), { name: "App", pids: [i + 1], state: "ESTAB", peer: "198.51.100." + i + ":443", down: 0, up: 0 }]));
    const app = api.inspect(many, "App");
    assert.equal(app.pids.length, api.INSPECT_ROWS + 3);
    assert.equal(app.connections.length, api.INSPECT_ROWS);
    assert.equal(app.connectionCount, api.INSPECT_ROWS + 3);
}
// A sample taken at 10 s, judged at 13 s with a 4 s limit unless a row
// says otherwise.
const judge = (api, request, sample = world(), now = 13000, sampledAt = 10000) => plain(api.killRequest(sample, sampledAt, now, 4000, request));
function killOutsideRow(api) { assert.deepEqual(judge(api, { name: "Browser", pids: [42, 50] }), { error: "changed" }); }
function killStale(api) {
    assert.deepEqual(judge(api, { name: "Player", pids: [50] }, world(), 14000), { pids: [50] }, "at the limit");
    assert.deepEqual(judge(api, { name: "Player", pids: [50] }, world(), 14001), { error: "stale" }, "past the limit");
}
test("kill-request-judge", api => {
    for (const [request, expected] of [
        [{ name: "Browser", pids: [44, 42, 44] }, { pids: [42, 44] }],
        [{ name: "Player", pids: [50] }, { pids: [50] }],
        [{ name: "Browser", pids: [50] }, { error: "changed" }],
        [{ name: "Absent", pids: [42] }, { error: "app" }],
        [{ name: "", pids: [42] }, { error: "app" }],
        [{ name: "Browser", pids: [0] }, { error: "pid" }],
        [{ name: "Browser", pids: [-42] }, { error: "pid" }],
        [{ name: "Browser", pids: [42.5] }, { error: "pid" }],
        [{ name: "Browser", pids: ["42"] }, { error: "pid" }],
        [{ name: "Browser", pids: [] }, { error: "value" }],
        [{ name: "Browser" }, { error: "value" }],
        [{ pids: [42] }, { error: "value" }],
        [null, { error: "value" }]
    ]) assert.deepEqual(judge(api, request), expected, JSON.stringify(request));
    assert.deepEqual(judge(api, { name: "Browser", pids: [42] }, null), { error: "stale" }, "no sample");
    assert.deepEqual(judge(api, { name: "Browser", pids: [42] }, world(), 13000, NaN), { error: "stale" }, "no sample time");
    killOutsideRow(api);
    killStale(api);
});
function connectionStates(api) {
    for (const [state, expected] of [["ESTAB", "Open"], ["SYN-SENT", "Opening"], ["SYN-RECV", "Opening"], ["FIN-WAIT-1", "Closing"], ["FIN-WAIT-2", "Closing"],
        ["CLOSE-WAIT", "Closing"], ["LAST-ACK", "Closing"], ["CLOSING", "Closing"], ["TIME-WAIT", "Closing"], ["UNKNOWN", "UNKNOWN"], ["constructor", "constructor"]])
        assert.equal(api.connectionState(state), expected);
}
function commandLines(api) {
    for (const [text, expected] of [["/usr/bin/app\0--flag\0value\0", "/usr/bin/app --flag value"], ["app\0", "app"], ["", ""], ["a b\0c\0\0", "a b c"]])
        assert.equal(api.commandLine(text), expected);
}
test("connection-states-and-command-lines", api => { connectionStates(api); commandLines(api); });
test("capture-state-actions", api => {
    for (const [state, tone, action] of [["ready","ok",false], ["needed","warning",true], ["nixos","warning",true], ["absent","info",false], ["denied","warning",false], ["unknown","warning",false]]) {
        const result = api.capture({ state }); assert.equal(result.tone, tone); assert.equal(result.action, action);
    }
});
const controls = [
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
    ["formatter-base", 'value /= 1024;', 'value /= 1000;', api => assert.equal(api.formatRate(34816, 1, 1), "34.0 KB/s")],
    ["kb-digits", 'unit === 1 ? kbDigits : mbDigits', 'mbDigits', kbDigits],
    ["owner-other-name", 'if (each === name && Number.isSafeInteger(pid)', 'if (Number.isSafeInteger(pid)', ownerName],
    ["kill-outside-row", 'if (request.pids.some(pid => app.pids.indexOf(pid) === -1)) return { error: "changed" };', '', killOutsideRow],
    ["kill-stale", 'if (sample === null || !(now - sampledAt <= maxAge)) return { error: "stale" };', 'if (sample === null) return { error: "stale" };', killStale],
    ["rate-sample-unit", 'return kb.length > mb.length ? kb : mb;', 'return mb;', rateSamples],
    ["inspect-cap", 'connections: connections.slice(0, INSPECT_ROWS)', 'connections: connections', inspectCap],
    ["connection-state-own", 'return Object.prototype.hasOwnProperty.call(STATES, state) ? STATES[state] : state;', 'return STATES[state] || state;', connectionStates],
    ["command-line-trailing", 'return text.replace(/\\0+$/, "").split("\\0").join(" ");', 'return text.split("\\0").join(" ");', commandLines],
    ["net-dev-transmit-field", 'const down = Number(fields[0]), up = Number(fields[8]);', 'const down = Number(fields[0]), up = Number(fields[9]);', api => assert.equal(api.parseNetDev(before).enp5s0.up, 2000)],
    ["ipv6-loopback-counted", 'host === "::1"', 'host === "::2"', api => assert.equal(Object.keys(api.parseSockets(socketBefore)).includes("14"), false)],
    ["unknown-as-zero", 'return "--";', 'return "0 B/s";', api => assert.equal(api.formatRate(null), "--")],
    ["capture-action", 'action: state === "needed" || state === "nixos"', 'action: false', api => assert.equal(api.capture({ state: "needed" }).action, true)]
];
for (const [name, old, replacement, verify] of controls) {
    assert(source.includes(old), "control match: " + name);
    const mutant = {};
    vm.runInNewContext(source.replace(/^\.pragma library\n/, "").replace(old, replacement), mutant, { filename: name });
    assert.throws(() => verify(mutant), { name: "AssertionError" });
    try { verify(mutant); } catch (error) { console.log("control traffic=" + name + " rejected=" + error.message); }
}
console.log("test-traffic-logic: passed=" + passed + " controls=" + controls.length);
