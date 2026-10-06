#!/usr/bin/env node
// The network snapshot decisions under the same loader as QML. Every
// mutation changes production behavior; the suite must turn red on it.
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const assert = require("node:assert/strict");
const { load } = require("../bin/lib/qml-library.js");
const file = path.join(__dirname, "../shell/plugins/vgs.network/NetworkLogic.js");
function suite(logic) {
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
    assert.match(logic.stateText("stopped"), /NetworkManager.*not running/);
    assert.doesNotMatch(logic.stateText("stopped"), /another|other service/i);
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
suite(load(file));
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "network-logic-"));
try {
    const source = fs.readFileSync(file, "utf8");
    for (const [name, needle, replacement] of [
        ["strength uses the upstream share", " * 100)", ")"],
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
        assert.throws(() => suite(load(mutant)), undefined, "control: " + name);
        console.log("network-logic: control=" + name + " red");
    }
} finally { fs.rmSync(scratch, { recursive: true, force: true }); }
console.log("network-logic: passed");
