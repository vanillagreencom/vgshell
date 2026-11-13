#!/usr/bin/env node
// The network snapshot decisions under the same loader as QML. Every
// mutation changes production behavior; the suite must turn red on it.
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const assert = require("node:assert/strict");
const vm = require("node:vm");
const { load } = require("../bin/lib/qml-library.js");
const file = path.join(__dirname, "../shell/plugins/vgs.network/NetworkLogic.js");
const nmcliFile = path.join(__dirname, "../shell/Commons/Nmcli.js");
const commons = { "qs.Commons 1.0": { Nmcli: load(nmcliFile) } };
function activateSuite(source) {
    const match = source.match(/function activate\(row\) \{([\s\S]*?)\n    \}\n    function join\(row\)/);
    assert.ok(match);
    const activate = new Function("row", "Logic", "network", "busy", "join", "action", match[1]);
    const logic = load(file, commons);
    for (const [security, known, connected, want] of [
        ["Wpa2Eap", true, false, "connect"], ["WpaEap", true, false, "connect"],
        ["Wpa2Eap", false, false, "join"], ["WpaEap", false, false, "join"],
        ["Wpa2Eap", true, true, "disconnect"], ["Wpa2Psk", false, false, "connect"]
    ]) {
        const calls = [];
        const row = { security, known, connected };
        activate(row, logic, { writable: true }, false, value => calls.push(["join", value]), (kind, value) => calls.push([kind, value]));
        assert.deepEqual(calls, [[want, row]]);
    }
}
const body = fs.readFileSync(path.join(__dirname, "../shell/plugins/vgs.network/NetworkBody.qml"), "utf8");
const service = fs.readFileSync(path.join(__dirname, "../shell/plugins/vgs.network/Service.qml"), "utf8");
function portalSuite(source) {
    const open = source.match(/function openPortal\(\) \{[\s\S]*?\n    \}/);
    const check = source.match(/function checkConnectivity\(\) \{[\s\S]*?\n    \}/);
    const finish = source.match(/function finishConnectivity\(text, code\) \{[\s\S]*?\n    \}/);
    const offered = source.match(/readonly property bool portalAvailable: (.*)/);
    assert.ok(open && check && finish && offered);
    const offer = new Function("portalConnectionKey", "state", "return " + offered[1]);
    for (const [key, state, expected] of [["wlan0", "portal", true], ["wlan0", "limited", false],
        ["wlan0", "connected", false], ["", "portal", false]]) assert.equal(offer(key, state), expected);
    for (const [available, missing, launchReply, expected] of [
        [false, [], "ok", "refused: portal=unavailable"],
        [true, ["xdg-open"], "ok", "refused: portal=missing-tool"],
        [true, [], "ok", "ok"], [true, [], "refused: run=failed", "refused: run=failed"]
    ]) {
        const calls = [];
        const offers = [];
        let randomReads = 0;
        const context = { portalAvailable: available, problem: "", console: { warn() {} }, Date: { now: () => { throw new Error("clock read"); } }, Math: { random: () => ++randomReads / 4 },
            shell: { requirements: { missing, offer(value) { offers.push(value); } },
                run: { detached(argv) { calls.push(argv); return launchReply; } } } };
        vm.createContext(context);
        vm.runInContext(open[0], context);
        assert.equal(context.openPortal(), expected);
        assert.deepEqual(JSON.parse(JSON.stringify(calls)), available && missing.length === 0
            ? [["xdg-open", "http://captive.apple.com/hotspot-detect.html?4"]] : []);
        assert.deepEqual(JSON.parse(JSON.stringify(offers)), available && missing.length !== 0 ? [["xdg-open"]] : []);
        assert.equal(context.problem !== "", available && missing.length === 0 && launchReply !== "ok");
        if (available && missing.length === 0) {
            assert.equal(context.openPortal(), launchReply);
            assert.equal(calls[1][1], "http://captive.apple.com/hotspot-detect.html?8");
            assert.equal(randomReads, 2);
        }
        context.shell = null;
        assert.equal(context.openPortal(), "refused: portal=unavailable");
    }
    for (const [key, supported, enabled, present, running, pending, expected] of [
        ["wlan0", true, true, true, false, null, true], ["", true, true, true, false, null, false],
        ["wlan0", false, true, true, false, null, false], ["wlan0", true, false, true, false, null, false],
        ["wlan0", true, true, false, false, null, false], ["wlan0", true, true, true, true, null, false],
        ["wlan0", true, true, true, false, {}, false]
    ]) {
        const probe = { running };
        const context = { portalConnectionKey: key, access: "allowed", connectivityGeneration: 3, connectivityRequest: pending,
            nmcliPresent: present, connectivityProbe: probe,
            Networking: { canCheckConnectivity: supported, connectivityCheckEnabled: enabled } };
        vm.createContext(context);
        vm.runInContext(check[0], context);
        context.checkConnectivity();
        assert.equal(probe.running, running || expected);
        assert.deepEqual(JSON.parse(JSON.stringify(context.connectivityRequest)), expected ? { key, generation: 3 } : pending);
    }
    const deniedProbe = { running: false };
    const denied = { portalConnectionKey: "wlan0", access: "denied", connectivityGeneration: 3, connectivityRequest: null,
        nmcliPresent: true, connectivityProbe: deniedProbe,
        Networking: { canCheckConnectivity: true, connectivityCheckEnabled: true } };
    vm.createContext(denied);
    vm.runInContext(check[0], denied);
    denied.checkConnectivity();
    assert.equal(deniedProbe.running, false);
    assert.equal(denied.connectivityRequest, null);
    const logic = load(file, commons);
    for (const [text, code, expected] of [["portal\n", 0, "Portal"], ["full\n", 0, "Full"],
        ["limited", 0, "Limited"], ["none", 0, "None"], ["unknown", 0, "Unknown"],
        ["portal", 1, "Unknown"], ["garbage", 0, "Unknown"]]) assert.equal(logic.checkedConnectivity(text, code), expected);
    for (const [key, generation, request, text, code, expected, retry] of [
        ["wlan0", 3, { key: "wlan0", generation: 3 }, "portal", 0, "Portal", false],
        ["wlan0", 3, { key: "wlan0", generation: 3 }, "full", 0, "Full", false],
        ["wlan1", 3, { key: "wlan0", generation: 3 }, "portal", 0, "Unknown", true],
        ["wlan0", 5, { key: "wlan0", generation: 3 }, "portal", 0, "Unknown", true],
        ["wlan0", 3, null, "portal", 0, "Unknown", false],
        ["wlan0", 3, { key: "wlan0", generation: 3 }, "portal", 1, "Unknown", false]
    ]) {
        let retries = 0;
        const context = { portalConnectionKey: key, connectivityGeneration: generation, connectivityRequest: request,
            checkedConnectivity: "Unknown", connectivityProblem: "", Logic: logic, checkConnectivity() {}, console: { warn() {} },
            Qt: { callLater() { retries++; } } };
        context.root = context;
        vm.createContext(context);
        vm.runInContext(finish[0], context);
        context.finishConnectivity(text, code);
        assert.equal(context.checkedConnectivity, expected);
        assert.equal(context.connectivityRequest, null);
        assert.equal(retries, Number(retry));
    }
    const recovery = { portalConnectionKey: "wlan0", connectivityGeneration: 3,
        connectivityRequest: null, checkedConnectivity: "Portal", connectivityProblem: "",
        Logic: logic, console: { warn() {} }, Qt: { callLater() {} } };
    recovery.root = recovery;
    vm.createContext(recovery);
    vm.runInContext(finish[0], recovery);
    for (const [text, code, expected, failed] of [["", 1, "Portal", true], ["full", 0, "Full", false]]) {
        recovery.connectivityRequest = { key: "wlan0", generation: 3 };
        recovery.finishConnectivity(text, code);
        assert.equal(recovery.checkedConnectivity, expected);
        assert.equal(recovery.connectivityProblem !== "", failed);
    }
    const polling = source.match(/running: (root.portalConnectionKey[^]*?)\n        onTriggered/);
    const interval = source.match(/readonly property int connectivityInterval: ([^\n]*)/);
    assert.ok(polling && interval);
    assert.match(source, /interval: root\.connectivityInterval/);
    const polls = new Function("root", "Networking", "return " + polling[1]);
    const delay = new Function("state", "leaseCount", "return " + interval[1]);
    for (const [key, value, state, failed, leases, enabled, expected, milliseconds] of [
        ["wlan0", "Portal", "portal", false, 0, true, true, 10000],
        ["wlan0", "Full", "connected", false, 0, true, false, 300000],
        ["wlan0", "Full", "connected", false, 1, true, true, 10000],
        ["wlan0", "Full", "connected", true, 0, true, true, 300000],
        ["wlan0", "Unknown", "connected", false, 0, true, true, 300000],
        ["wlan0", "Limited", "limited", false, 0, true, true, 300000],
        ["wlan0", "Limited", "limited", false, 1, true, true, 10000],
        ["", "Unknown", "connected", true, 0, true, false, 300000],
        ["wlan0", "Portal", "portal", false, 0, false, false, 10000]
    ]) {
        const root = { portalConnectionKey: key, checkedConnectivity: value, state, leaseCount: leases,
            connectivityProblem: failed ? "unavailable" : "", access: "allowed", nmcliPresent: true };
        assert.equal(polls(root, { canCheckConnectivity: true, connectivityCheckEnabled: enabled }), expected);
        assert.equal(delay(state, leases), milliseconds);
    }
    for (const [access, present] of [["denied", true], ["allowed", false]]) assert.equal(polls({ portalConnectionKey: "wlan0",
        checkedConnectivity: "Unknown", state: "connected", leaseCount: 0, connectivityProblem: "unavailable", access, nmcliPresent: present },
        { canCheckConnectivity: true, connectivityCheckEnabled: true }), false);
    const seed = source.match(/property string checkedConnectivity: ([^\n]*)/);
    const follow = source.match(/onNativeConnectivityChanged: \{([^]*?)\n    \}/);
    const appears = source.match(/onNmcliPresentChanged: \{([^]*?)\n    \}/);
    assert.ok(seed && follow && appears);
    assert.equal(new Function("nativeConnectivity", "return " + seed[1])("Portal"), "Portal");
    const context = { nativeConnectivity: "Portal", checkedConnectivity: "Unknown", connectivityGeneration: 0,
        connectivityProblem: "unavailable", nmcliPresent: true, access: "allowed", checks: 0, publish() {},
        checkConnectivity() {}, Qt: { callLater() { context.checks++; } } };
    context.root = context;
    vm.createContext(context);
    vm.runInContext("function follow() {" + follow[1] + "}\nfunction appears() {" + appears[1] + "}", context);
    for (const result of ["Portal", "Full", "Limited"]) {
        context.nativeConnectivity = result;
        context.follow();
        assert.equal(context.checkedConnectivity, result);
        assert.equal(context.connectivityProblem, "");
    }
    context.checks = 0;
    context.appears();
    assert.equal(context.checks, 1);

}
portalSuite(service);
for (const [before, after] of [
    ["!portalAvailable", "false"],
    ['shell.requirements.missing.includes("xdg-open")', "false"],
    ['portalConnectionKey === "" ||', ""],
    ["!Networking.canCheckConnectivity ||", ""],
    ["!Networking.connectivityCheckEnabled ||", ""],
    ["|| !nmcliPresent", ""],
    ['access === "denied" ||', ""],
    ['root.access !== "denied" && ', ""],
    ["&& root.nmcliPresent", ""],
    ["connectivityProbe.running ||", ""],
    ["connectivityRequest !== null", "false"],
    ["pending.key !== portalConnectionKey ||", ""],
    ["pending.generation !== connectivityGeneration", "false"],
    ['if (value === "Unknown")', "if (false)"],
    ['root.connectivityProblem !== "" ||', ""],
    ['root.checkedConnectivity === "Unknown"\n            ||', "false ||"],
    ['? 10000 : 300000', '? 10000 : 10000'],
    ['connectivityInterval: state === "portal" || leaseCount > 0', 'connectivityInterval: leaseCount > 0'],
    ['connectivityInterval: state === "portal" || leaseCount > 0', 'connectivityInterval: state === "portal" || false'],
    ['interval: root.connectivityInterval', 'interval: 10000'],
    ['|| root.leaseCount > 0)', ')'],
    ['property string checkedConnectivity: nativeConnectivity', 'property string checkedConnectivity: "Unknown"'],
    ['onNativeConnectivityChanged: {\n        connectivityGeneration++;\n        checkedConnectivity = nativeConnectivity;', 'onNativeConnectivityChanged: {\n        connectivityGeneration++;\n        checkedConnectivity = "Unknown";'],
    ['else Qt.callLater(root.checkConnectivity);', 'else void 0;'],
    ['Math.random().toString(16).slice(2)', 'String(Date.now())'],
    ['Math.random().toString(16).slice(2)', '"4"'],
    ['state === "portal"', '["portal", "limited"].includes(state)']
]) {
    assert.ok(service.includes(before));
    assert.throws(() => portalSuite(service.replace(before, after)));
}
console.log("network-logic: control=portal launch and native checks red");
function promptDescriptionSuite(source) {
    const dialog = source.slice(source.indexOf('objectName: "network-prompt"'));
    const description = dialog.match(/Accessible\.description: ([^\n]+)/);
    assert.ok(description);
    const read = new Function("root", "return " + description[1]);
    for (const [name, reason, expected] of [
        ["VGS Smoke Wi-Fi", "saved-password-failure", "VGS Smoke Wi-Fi. saved-password-failure"],
        ["<b>Hotel</b>", "", "<b>Hotel</b>"], ["", "", ""]
    ]) assert.equal(read({ promptName: name, network: { problem: reason } }), expected);
}
promptDescriptionSuite(body);
assert.throws(() => promptDescriptionSuite(body.replace('Accessible.description: [root.promptName, root.network.problem || ""].filter(Boolean).join(". ")', 'Accessible.description: ""')));
console.log("network-logic: control=dialog description names network red");
function promptReasonSuite(serviceSource, bodySource) {
    const failed = serviceSource.match(/function failed\(n, reason\) \{[\s\S]*?\n    \}/);
    const hint = bodySource.match(/objectName: "network-problem"[\s\S]*?visible: ([^\n]*)/);
    const message = bodySource.match(/objectName: "network-prompt-reason"[\s\S]*?text: ([^\n]*)/);
    assert.ok(failed && hint && message);
    const visible = new Function("text", "root", "return " + hint[1]);
    const reasonText = new Function("root", "return " + message[1]);
    for (const known of [true, false]) {
        const n = { name: "Hotel", security: 2 };
        const context = { operation: { network: n, kind: "connect", key: "hotel", known },
            problem: "", prompt: null, securityVariants: { Wpa2Psk: 2 }, failureVariants: { NoSecrets: 1 },
            Logic: load(file, commons), finishOperation() { context.operation = null; } };
        vm.createContext(context);
        vm.runInContext(failed[0], context);
        context.failed(n, 1);
        assert.equal(context.prompt.name, "Hotel");
        // The reason states the failure alone: the line under it asks for
        // the password, so a request here would ask twice.
        assert.equal(context.problem, known ? "The saved password did not work." : "");
        assert.equal(reasonText({ network: { problem: context.problem } }), context.problem);
        assert.equal(visible(context.problem, { prompting: true }), false);
        assert.equal(visible(context.problem, { prompting: false }), known);
    }
}
promptReasonSuite(service, body);
assert.throws(() => promptReasonSuite(service, body.replace('visible: text !== "" && !root.prompting', 'visible: text !== ""')));
assert.throws(() => promptReasonSuite(service, body.replace('text: root.network.problem || ""', 'text: ""')));
const firstTimeReason = service.replace(/(problem = pending\.known \? [^\n]* : )"";/, '$1"unexpected-reason";');
assert.notEqual(firstTimeReason, service);
assert.throws(() => promptReasonSuite(firstTimeReason, body));
const twoRequests = service.replace('"The saved password did not work."', '"The saved password did not work. Enter the Wi-Fi password again."');
assert.notEqual(twoRequests, service);
assert.throws(() => promptReasonSuite(twoRequests, body));
console.log("network-logic: control=prompt reason drawn once, asks nothing and absent for first join red");
activateSuite(body);
assert.equal(body.split("!row.known && Logic.supportsEnterprise").length - 1, 1);
assert.throws(() => activateSuite(body.replace("!row.known && Logic.supportsEnterprise", "Logic.supportsEnterprise")));
console.log("network-logic: control=saved enterprise reconnect red");
function joinAdapterSuite(source) {
    const join = source.match(/function join\(row\) \{[\s\S]*?\n    \}/);
    const close = source.match(/function closeJoin\(\) \{[\s\S]*?\n    \}/);
    const changed = source.match(/onNetworkChanged: \{([\s\S]*?)\n    \}\n    function answered/);
    assert.ok(join && close && changed);
    // Execute the production handlers with the form's binding delivered
    // before the network-change handler. Smoke owns the real device removal.
    for (const [target, nextInterface, enabled, present, closed] of [
        [null, "wlan1", true, true, true], [{ interface: "wlan0" }, "wlan1", true, true, true],
        [null, "wlan0", false, true, true], [null, "wlan0", true, false, true],
        [null, "wlan0", true, true, false]
    ]) {
        let clears = 0;
        const state = { network: { writable: true, wifiInterface: "wlan0", wifiEnabled: true, hasWifi: true },
            busy: false, shell: { requirements: { missing: [] } }, joinTarget: undefined, joinInterface: "",
            joinLoader: { item: null }, closeShare() {}, promptKey: "", readyDetails: {} };
        vm.createContext(state);
        vm.runInContext(join[0] + "\n" + close[0] + "\nfunction changed() {" + changed[1] + "\n}", state);
        state.join(target);
        assert.equal(state.joinInterface, "wlan0");
        state.joinLoader.item = { interfaceName: nextInterface, clear() { clears++; } };
        state.network = { writable: true, wifiInterface: nextInterface, wifiEnabled: enabled, hasWifi: present };
        state.changed();
        assert.equal(clears, Number(closed));
        assert.equal(state.joinInterface, closed ? "" : "wlan0");
        assert.equal(state.joinTarget, closed ? undefined : target);
    }
}
joinAdapterSuite(body);
const adapterGuard = "joinTarget !== undefined && joinInterface !== network.wifiInterface";
assert.equal(body.split(adapterGuard).length - 1, 1);
assert.throws(() => joinAdapterSuite(body.replace(adapterGuard, "joinLoader.item !== null && joinLoader.item.interfaceName !== network.wifiInterface")));
console.log("network-logic: control=adapter binding delivered before close red");
function suite(logic) {
    // This exercises the shared endpoint itself. QML smoke owns proof that
    // the real service Process outlives the form during UUID cleanup.
    const calls = [];
    const owner = { startJoin: (...args) => { calls.push(args); return "ok"; }, cancelJoin: id => calls.push(id) };
    const request = { owner: "form", interface: "wlan0", name: "Hidden" };
    const feed = () => {};
    const done = () => {};
    assert.equal(logic.submitJoin(request, feed, done), "unavailable");
    logic.attachJoin(owner);
    assert.equal(logic.submitJoin(request, feed, done), "ok");
    assert.equal(calls[0][0], request);
    assert.equal(calls[0][1], feed);
    assert.equal(calls[0][2], done);
    logic.closeJoin("form");
    assert.equal(calls[1], "form");
    logic.releaseJoin({});
    assert.equal(logic.submitJoin(request, feed, done), "ok");
    logic.releaseJoin(owner);
    assert.equal(logic.submitJoin(request, feed, done), "unavailable");
    for (const [security, supported] of [["WpaEap", true], ["Wpa2Eap", true], ["Wpa3SuiteB192", false], ["Wpa2Psk", false], ["Unknown", false]]) assert.equal(logic.supportsEnterprise(security), supported);
    assert.equal(logic.enumName(7, { NoSecrets: 7, WifiAuthTimeout: 8 }), "NoSecrets");
    assert.equal(logic.enumName(99, { NoSecrets: 7 }), "Unknown");
    for (const [row, want] of [[null, false], [{ known: false, security: "Wpa2Psk" }, false], [{ known: true, security: "Wpa2Eap" }, false], [{ known: true, security: "Unknown" }, false], ...["Open", "Owe", "StaticWep", "WpaPsk", "Wpa2Psk", "Sae"].map(security => [{ known: true, security }, true])]) assert.equal(logic.shareable(row), want);
    for (const [kind, connected, known, changing, observed, want] of [
        ["connect", true, true, false, true, "complete"], ["psk", true, true, false, true, "complete"],
        ["connect", false, true, true, true, "pending"], ["connect", false, true, false, false, "pending"],
        ["connect", false, true, false, true, "terminal"], ["psk", false, true, false, true, "terminal"],
        ["disconnect", false, true, false, true, "complete"], ["disconnect", true, true, false, false, "pending"],
        ["forget", false, false, false, false, "complete"], ["forget", false, true, false, false, "pending"]
    ]) assert.equal(logic.operationResult(kind, connected, known, changing, observed), want);
    for (const [raw, want] of [[0, 0], [0.82, 82], [1, 100], [-1, 0], [2, 100], [NaN, 0], [undefined, 0]]) assert.equal(logic.strength(raw), want);
    for (const [percent, want] of [
        [0, "wifi-zero"], [10, "wifi-zero"], [24, "wifi-zero"], [25, "wifi-low"], [37, "wifi-low"], [49, "wifi-low"],
        [50, "wifi-high"], [62, "wifi-high"], [74, "wifi-high"], [75, "wifi"], [82, "wifi"], [100, "wifi"]
    ]) assert.equal(logic.wifiIcon(percent), want, "wifiIcon(" + percent + ")");
    const rows = [
        { key: "z", name: "Z", connected: false, known: false, strength: 90 },
        { key: "saved", name: "Saved", connected: false, known: true, strength: 10 },
        { key: "active", name: "Active", connected: true, known: true, strength: 5 },
        { key: "a", name: "A", connected: false, known: false, strength: 90 }
    ];
    assert.deepEqual(Array.from(logic.ordered(rows), row => row.key), ["active", "saved", "a", "z"]);
    assert.equal(rows[0].key, "z");
    for (const [security, label] of Object.entries({ Wpa3SuiteB192: "WPA3 Enterprise", Sae: "WPA3", Wpa2Eap: "WPA2 Enterprise", Wpa2Psk: "WPA2", WpaEap: "WPA Enterprise", WpaPsk: "WPA", StaticWep: "WEP", DynamicWep: "WEP Enterprise", Leap: "LEAP", Owe: "Enhanced open", Open: "Open", Unknown: "Unknown security" })) assert.equal(logic.securityLabel(security), label);
    for (const [reason, security, known, want] of [
        ["NoSecrets", "Wpa2Psk", false, true], ["NoSecrets", "Wpa2Psk", true, true],
        ["WifiAuthTimeout", "Sae", true, true], ["WifiClientFailed", "WpaPsk", true, true],
        ["WifiAuthTimeout", "Wpa2Psk", false, false], ["WifiNetworkLost", "Wpa2Psk", true, false],
        ["WifiClientDisconnected", "Wpa2Psk", true, false], ["NoSecrets", "Wpa2Eap", true, false],
        ["NoSecrets", "StaticWep", false, false], ["Unknown", "Open", true, false]
    ]) assert.equal(logic.shouldReprompt(reason, security, known), want);
    for (const [text, code, want] of [
        ["LoadState=not-found\nActiveState=inactive", 0, "absent"],
        ["LoadState=loaded\nActiveState=inactive", 0, "stopped"],
        ["LoadState=loaded\nActiveState=active", 0, "running"],
        ["LoadState=loaded\nActiveState=failed", 0, "stopped"],
        ["LoadState=loaded\nActiveState=future", 0, "unavailable"],
        ["", 0, "unavailable"], ["LoadState=not-found", 1, "unavailable"]
    ]) assert.equal(logic.serviceProbe(text, code), want);
    for (const [text, code, want] of [
        ["org.freedesktop.NetworkManager.network-control:yes", 0, "allowed"],
        ["org.freedesktop.NetworkManager.network-control:no", 0, "denied"],
        ["org.freedesktop.NetworkManager.network-control:auth", 0, "denied"],
        ["org.freedesktop.NetworkManager.network-control:yes", 1, "unavailable"], ["", 0, "unavailable"]
    ]) assert.equal(logic.permission(text, code), want);
    for (const [service, backend, managed, access, connected, connectivity, checks, wifi, hasWifi, want] of [
        ["absent", false, true, "unavailable", false, "Unknown", false, false, false, "absent"],
        ["stopped", true, true, "allowed", false, "Full", true, true, true, "stopped"],
        ["running", true, false, "allowed", false, "Full", true, true, true, "unmanaged"],
        ["running", true, true, "denied", false, "Full", true, true, true, "denied"],
        ["running", true, true, "allowed", true, "Limited", true, true, true, "limited"],
        ["running", true, true, "allowed", true, "Limited", false, true, true, "connected"],
        ["running", true, true, "allowed", true, "Portal", true, true, true, "portal"],
        ["unavailable", false, true, "unavailable", false, "Unknown", false, false, false, "unavailable"],
        ["unavailable", true, true, "allowed", false, "Unknown", false, true, true, "unavailable"],
        ["running", true, true, "allowed", false, "Full", true, false, true, "radio-off"],
        ["running", true, true, "allowed", false, "Full", true, true, true, "offline"],
        ["running", true, true, "unavailable", false, "Unknown", false, true, true, "offline"],
        ["running", true, true, "unavailable", true, "Full", true, true, true, "connected"]
    ]) assert.equal(logic.state(service, backend, managed, access, connected, connectivity, checks, wifi, hasWifi), want);
    const states = ["absent", "stopped", "unmanaged", "denied", "limited", "portal", "connected", "radio-off", "offline", "unavailable"];
    assert.equal(new Set(states.map(s => logic.stateText(s))).size, states.length);
    for (const s of ["absent", "stopped", "unmanaged", "denied", "unavailable"]) assert.equal(logic.writable(s), false);
    for (const s of ["connected", "offline", "radio-off", "limited", "portal"]) assert.equal(logic.writable(s), true);
    for (const [managed, connected, link, want] of [
        [false, true, true, "unmanaged"], [false, false, false, "unmanaged"],
        [true, true, true, "connected"], [true, false, true, "disconnected"], [true, false, false, "no-cable"]
    ]) assert.equal(logic.ethernetState(managed, connected, link), want);
    const wired = ["connected", "disconnected", "no-cable", "unmanaged"];
    assert.equal(new Set(wired.map(s => logic.ethernetText(s))).size, wired.length);
    assert.deepEqual(Array.from(logic.ethernetOrdered([
        { name: "enp11s0", state: "no-cable" }, { name: "enp9s0", state: "disconnected" }, { name: "enp12s0", state: "connected" }
    ]), row => row.name), ["enp12s0", "enp11s0", "enp9s0"]);
    const ethernet = [{ name: "enp11s0", state: "no-cable" }, { name: "enp10s0", state: "connected" }];
    const wifi = [{ name: "Cafe", connected: false }, { name: "Home", connected: true }];
    assert.match(logic.summary({ state: "connected", wifi: [], ethernet }), /enp10s0/);
    assert.doesNotMatch(logic.summary({ state: "connected", wifi: [], ethernet }), /enp11s0/);
    assert.match(logic.summary({ state: "connected", wifi, ethernet }), /Home/);
    assert.equal(logic.summary({ state: "offline", wifi: [], ethernet: [{ name: "enp11s0", state: "no-cable" }] }), logic.stateText("offline"));
    assert.equal(logic.summary({ state: "limited", wifi, ethernet }), logic.stateText("limited"));
    assert.equal(JSON.stringify(logic.details("GENERAL.DEVICE:wlan0\nGENERAL.CONNECTION:Office\\:west\\\\desk\nIP6.ADDRESS[1]:fe80\\:\\:1/64\nWIFI.PSK:no")), JSON.stringify([
        { key: "GENERAL.DEVICE", value: "wlan0" }, { key: "GENERAL.CONNECTION", value: "Office:west\\desk" }, { key: "IP6.ADDRESS[1]", value: "fe80::1/64" }
    ]));
}
suite(load(file, commons));
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "network-logic-"));
try {
    const source = fs.readFileSync(file, "utf8");
    for (const [name, needle, replacement] of [
        ["join endpoint release", 'if (joinOwner === owner) joinOwner = null;', 'joinOwner = owner;'],
        ["enterprise security routing", 'return security === "WpaEap" || security === "Wpa2Eap";', 'return false;'],
        ["strength uses the upstream share", " * 100)", ")"],
        ["the full Wi-Fi glyph starts at 75", "percent >= 75", "percent >= 76"],
        ["the two-arc Wi-Fi glyph starts at 50", "percent >= 50", "percent >= 51"],
        ["the one-arc Wi-Fi glyph starts at 25", "percent >= 25", "percent > 25"],
        ["connected ordering", "Number(b.connected) - Number(a.connected)", "0"],
        ["security label", 'Wpa2Psk: "WPA2"', 'Wpa2Psk: "Open"'],
        ["saved credential reprompt", '(known && (reason === "WifiAuthTimeout" || reason === "WifiClientFailed"))', 'false'],
        ["stopped state", 'return "stopped";', 'return "absent";'],
        ["denied access", 'if (access === "denied") return "denied";', 'if (access === "denied") return "offline";'],
        ["limited connectivity", 'return "limited";', 'return "connected";'],
        ["permission refusal", 'if (value === "no" || value === "auth") return "denied";', 'if (value === "no" || value === "auth") return "allowed";'],
        ["operation recovery", 'return "terminal";', 'return "pending";'],
        ["share requires a saved profile", '!!row.known && (supportsPsk', 'true && (supportsPsk'],
        ["details allowlist", 'shown.test(key)', 'true'],
        ["a wired device without a link has no cable", 'return link ? "disconnected" : "no-cable";', 'return "disconnected";'],
        ["connected wired devices first", 'Number(b.state === "connected") - Number(a.state === "connected")', '0'],
        ["the summary names the connected wired device", 'row => row.state === "connected");', 'row => true);']
    ]) {
        assert.equal(source.split(needle).length - 1, 1, name + " mutation must match once");
        const mutant = path.join(scratch, "NetworkLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, replacement));
        assert.throws(() => suite(load(mutant, commons)), undefined, "control: " + name);
        console.log("network-logic: control=" + name + " red");
    }
} finally { fs.rmSync(scratch, { recursive: true, force: true }); }
console.log("network-logic: passed");
