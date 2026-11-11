#!/usr/bin/env node
// The VPN plugin's decisions under the same loader as QML, over the nmcli
// shapes in scripts/fixtures/vpn/: the list, the multi-uuid detail read,
// the address read and each failure text, as NetworkManager 1.58.1 printed
// them under LC_ALL=C (VGS-1931 verify-first, 2026-10-20). What a connect
// that carried a password reads from those texts is traced in
// NetworkManager 1.58.1 and its VPN plugins' source, not run (VGS-1932
// verify-first § 6): the pppd types and Fortinet end in up-failed.txt's
// Unknown reason, openvpn retries the refused password until the action
// deadline kills nmcli (-1), and a password the plugin never asked for
// ends in No valid secrets with no warning line. Every name, address, key,
// path and password is a stand-in. Every control changes production
// behavior and must redden this suite.
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const assert = require("node:assert/strict");
const { load } = require("../bin/lib/qml-library.js");
const file = path.join(__dirname, "../shell/plugins/vgs.vpn/VpnLogic.js");
const nmcliFile = path.join(__dirname, "../shell/Commons/Nmcli.js");
const commons = { "qs.Commons 1.0": { Nmcli: load(nmcliFile), SettingValues: load(path.join(__dirname, "../shell/Commons/SettingValues.js")) } };
const core = load(path.join(__dirname, "../shell/Core/PluginLogic.js"));
const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "../shell/plugins/vgs.vpn/manifest.json"), "utf8"));
const serviceSource = fs.readFileSync(path.join(__dirname, "../shell/plugins/vgs.vpn/Service.qml"), "utf8");
const bodySource = fs.readFileSync(path.join(__dirname, "../shell/plugins/vgs.vpn/VpnBody.qml"), "utf8");
const leakSource = fs.readFileSync(path.join(__dirname, "../shell/plugins/vgs.vpn/LeakCheck.qml"), "utf8");
const fixtures = path.join(__dirname, "fixtures/vpn");
// A checkout with CRLF endings reads as nmcli's LF output.
const text = name => fs.readFileSync(path.join(fixtures, name), "utf8").replace(/\r\n/g, "\n");
// The core's ceiling for one plugin's published status
// (PluginLogic.STATUS_MAX_BYTES).
const STATUS_MAX_BYTES = core.STATUS_MAX_BYTES;
const plain = value => JSON.parse(JSON.stringify(value));

const HOME = "9d76b882-ead1-4c49-8675-7be6431d5f71";
const OFFICE = "95ea5c2d-312f-4a84-8fd1-9ebc0a4a7581";
const TRAVEL = "5b1c0a9e-2f43-4d7a-9a51-0c3e6e1d2b84";
const CAMPUS = "2e8f4d1a-7c6b-4f3e-8a29-6d5b4c3a2f10";
const BRANCH = "76ceb7f0-0f5b-4315-9f38-2af0937bb726";
const LAB = "c41d7e02-58b3-4a6f-9e1d-3f2a0b8c7d65";
// Text the fixtures hold that no parsed field may carry: a certificate
// path, a user name, keys, allowed addresses and nmcli's noise lines.
const PRIVATE = ["/home/fixture", "fixture-user", "office-ca", "xTIBA5rb", "HIgo9xNz", "allowed-ips", "10.30.0.0",
    "journalctl", "auth-dialog", "libgtk", "passwd-file", "private-key", "vpn.secrets", "password-flags"];
function holdsNothingPrivate(value, where) {
    const json = JSON.stringify(value);
    for (const marker of PRIVATE) assert.ok(!json.includes(marker), where + " carries " + marker);
}

// State file texts and their read, as the root script's parse_state reads
// them: the differential at the end hands each to the shipped script.
const STATE_TABLE = [
    ["the four keys", "version=1\nmeant-on=\nkill-switch=off\nportal-until=0\n", { kind: "valid", meantOn: "", mode: "off", portalUntil: "0" }],
    ["any order, trailing line feeds", "kill-switch=block-lan\nportal-until=1794203888\nmeant-on=" + HOME + "\nversion=1\n\n\n",
        { kind: "valid", meantOn: HOME, mode: "block-lan", portalUntil: "1794203888" }],
    ["an upper-case uuid", "version=1\nmeant-on=" + HOME.toUpperCase() + "\nkill-switch=block\nportal-until=0",
        { kind: "valid", meantOn: HOME.toUpperCase(), mode: "block", portalUntil: "0" }],
    ["empty", "", { kind: "malformed" }],
    ["a missing key", "version=1\nmeant-on=\nkill-switch=off\n", { kind: "malformed" }],
    ["a repeated key", "version=1\nmeant-on=\nkill-switch=off\nportal-until=0\nkill-switch=block\n", { kind: "malformed" }],
    ["another key", "version=1\nmeant-on=\nkill-switch=off\nportal-until=0\nextra=1\n", { kind: "malformed" }],
    ["an empty line between keys", "version=1\n\nmeant-on=\nkill-switch=off\nportal-until=0\n", { kind: "malformed" }],
    ["another version", "version=2\nmeant-on=\nkill-switch=off\nportal-until=0\n", { kind: "malformed" }],
    ["a profile name", "version=1\nmeant-on=Home tunnel\nkill-switch=off\nportal-until=0\n", { kind: "malformed" }],
    ["another mode", "version=1\nmeant-on=\nkill-switch=on\nportal-until=0\n", { kind: "malformed" }],
    ["a leading zero", "version=1\nmeant-on=\nkill-switch=off\nportal-until=01\n", { kind: "malformed" }],
    ["a CR line end", "version=1\r\nmeant-on=\r\nkill-switch=off\r\nportal-until=0\r\n", { kind: "malformed" }],
    ["line feeds past 4096 bytes", "version=1\nmeant-on=\nkill-switch=off\nportal-until=0" + "\n".repeat(4070),
        { kind: "valid", meantOn: "", mode: "off", portalUntil: "0" }],
    ["over 4096 bytes", "version=1\nmeant-on=\nkill-switch=off\nportal-until=0\n" + "x".repeat(4100), { kind: "malformed" }],
    ["a key with no value line", "version=1\nmeant-on=\nkill-switch=off\nportal-until=0\nnoise\n", { kind: "malformed" }]
];

// Status lines and killStatus's read of each, the parsed fields or
// `unreachable` for a line it refuses: the differential at the end hands
// each code-0 line to the root's status_pattern, which must accept the
// same lines.
const STATUS_TABLE = [
    [0, "state=off reason=disarmed blocked=0 tunnel= profile=\n", { state: "off", reason: "disarmed", blocked: "0", tunnel: "", profile: "" }],
    [1, "state=off reason=disarmed blocked=0 tunnel= profile=\n", "unreachable"],
    [0, "state=holding reason=tunnel-down blocked=0042 tunnel=wgnord profile=" + HOME + "\n",
        { state: "holding", reason: "tunnel-down", blocked: "42", tunnel: "wgnord", profile: HOME }],
    [0, "state=passing reason=tunnel-up blocked=18446744073709551615 tunnel=wg.home-0 profile=" + HOME.toUpperCase() + "\n",
        { state: "passing", reason: "tunnel-up", blocked: "18446744073709551615", tunnel: "wg.home-0", profile: HOME }],
    [0, "state=unavailable reason=profile-not-wireguard blocked=3 tunnel= profile=" + OFFICE + "\n",
        { state: "unavailable", reason: "profile-not-wireguard", blocked: "3", tunnel: "", profile: OFFICE }],
    [0, "state=unavailable reason=cache-unreadable blocked=3 tunnel= profile=\n",
        { state: "unavailable", reason: "cache-unreadable", blocked: "3", tunnel: "", profile: "" }],
    [1, "", "unreachable"], [-1, "state=off reason=disarmed blocked=0 tunnel= profile=\n", "unreachable"],
    [0, "state=off reason=disarmed blocked=0 tunnel=\n", "unreachable"],
    [0, "state=armed reason=x blocked=0 tunnel= profile=\n", "unreachable"], [0, "state=off reason=Off blocked=0 tunnel= profile=\n", "unreachable"],
    [0, "state=off reason=disarmed blocked=-1 tunnel= profile=\n", "unreachable"], [0, "state=off reason=disarmed blocked=0 tunnel=a/b profile=\n", "unreachable"],
    [0, "state=off reason=disarmed blocked=0 tunnel= profile=Home\n", "unreachable"],
    [0, "state=off reason=disarmed blocked=0 tunnel= profile=" + HOME + "0\n", "unreachable"],
    [0, "state=off reason=disarmed blocked=0 tunnel= profile=\nstate=off reason=disarmed blocked=0 tunnel= profile=\n", "unreachable"], [0, "", "unreachable"]
];

function vpnRequirementSuite(logic) {
    const openvpn = "org.freedesktop.NetworkManager.openvpn";
    const sourceRows = [
        { uuid: OFFICE, type: "vpn", service: "openvpn", state: "", failure: "" },
        { uuid: TRAVEL, type: "vpn", service: "l2tp", state: "", failure: "needs-password" },
        { uuid: LAB, type: "vpn", service: "vpnc", state: "", failure: "plugin-needed" }
    ];
    const metadata = Object.fromEntries(sourceRows.map(row => [row.uuid, { service: row.service, server: "" }]));
    const failures = Object.fromEntries(sourceRows.map(row => [row.uuid, { kind: row.failure, service: row.service }]));
    const profiles = plain(logic.compose({ state: "available", rows: sourceRows, count: sourceRows.length, activeCount: 0 }, metadata, {}, failures, null, ""));
    const rows = profiles.rows;
    const stale = { ...profiles, rows: rows.map(row => row.uuid === OFFICE ? { ...row, failure: "plugin-needed" } : row) };
    const connected = { ...profiles, rows: rows.map(row => row.uuid === OFFICE ? { ...row, state: "activated" } : row) };
    for (const [uuid, payload, missing, key, install, refused] of [
        [OFFICE, profiles, [openvpn], "plugin-needed", openvpn, true],
        [OFFICE, stale, [], "off", "", false],
        [OFFICE, profiles, [], "off", "", false],
        [OFFICE, connected, [openvpn], "connected", "", false],
        [TRAVEL, profiles, [openvpn], "needs-password", "", false],
        [LAB, profiles, [openvpn], "plugin-needed", "", true]
    ]) {
        const view = logic.rowView(payload.rows.find(row => row.uuid === uuid), payload, missing);
        assert.deepEqual([view.key, view.install, view.reason !== ""], [key, install, refused]);
        const plan = plain(logic.profileCommand({ kind: "profile-up", id: uuid }, payload, missing));
        assert.deepEqual(plan, key === "connected" ? { refusal: "refused: profile=state" }
            : refused ? { refusal: "refused: profile=plugin-needed" } : { argv: ["nmcli", "connection", "up", "uuid", uuid] });
    }
    const password = { ...profiles, rows: rows.map(row => row.uuid === OFFICE ? { ...row, failure: "needs-password" } : row) };
    assert.deepEqual(plain(logic.passwordCommand(OFFICE, password, [openvpn])), { refusal: "refused: profile=state" });
}

function vpnReadinessSuite(logic) {
    // Service.listed publishes the real list before its detail child answers.
    const listing = logic.list(0, text("list.txt"));
    const metadata = logic.details(0, text("details.txt"), logic.detailsKey(listing));
    const missing = ["org.freedesktop.NetworkManager.openvpn"];
    for (const [uuid, details, state, key, refused] of [
        [OFFICE, {}, "", "reading", true],
        [OFFICE, { [OFFICE]: null }, "", "no-answer", true],
        [OFFICE, metadata, "", "plugin-needed", true],
        [OFFICE, { [OFFICE]: { service: "", server: "" } }, "", "off", false],
        [OFFICE, {}, "activated", "connected", true],
        [OFFICE, {}, "activating", "connecting", true],
        [OFFICE, {}, "deactivating", "disconnecting", true],
        [LAB, {}, "", "off", false]
    ]) {
        const source = { ...listing, rows: listing.rows.map(row => row.uuid === uuid ? { ...row, state } : row) };
        const payload = plain(logic.compose(source, details, {}, {}, null, ""));
        const row = payload.rows.find(row => row.uuid === uuid);
        const view = logic.rowView(row, payload, missing);
        assert.equal(view.key, key, uuid + " " + key);
        assert.equal(view.reason !== "", refused && key !== "connected", key);
        assert.deepEqual(plain(logic.profileCommand({ kind: "profile-up", id: uuid }, payload, missing)),
            refused ? { refusal: "refused: profile=" + (["connected", "connecting", "disconnecting"].includes(key) ? "state" : key) }
                : { argv: ["nmcli", "connection", "up", "uuid", uuid] }, key);
        assert.deepEqual(plain(logic.profileCommand({ kind: "profile-remove", id: uuid }, payload, missing)),
            { argv: ["nmcli", "connection", "delete", "uuid", uuid] }, key);
        if (state === "activated" || state === "activating")
            assert.deepEqual(plain(logic.profileCommand({ kind: "profile-down", id: uuid }, payload, missing)),
                { argv: ["nmcli", "connection", "down", "uuid", uuid] }, key);
        if (key === "reading" || key === "no-answer")
            assert.deepEqual(plain(logic.passwordCommand(uuid, payload, missing)), { refusal: "refused: profile=state" }, key);
    }
}

function suite(logic, service = serviceSource) {
    vpnRequirementSuite(logic);
    vpnReadinessSuite(logic);
    // The list: VPN and WireGuard rows by uuid, other types dropped, every
    // active profile counted.
    const listing = plain(logic.list(0, text("list.txt")));
    assert.equal(listing.state, "available");
    assert.deepEqual(listing.rows.map(row => [row.uuid, row.name, row.type, row.state]), [
        [HOME, "Home tunnel", "wireguard", "activated"], [OFFICE, "Office VPN", "vpn", ""], [TRAVEL, "Travel L2TP", "vpn", ""],
        [CAMPUS, "Campus AnyConnect", "vpn", ""], [BRANCH, "Branch IPsec", "vpn", ""], [LAB, "Lab tunnel", "wireguard", ""]]);
    assert.equal(listing.count, 6);
    assert.equal(listing.activeCount, 1);
    assert.deepEqual(plain(logic.list(0, "Branch\\:IPsec:" + BRANCH.toUpperCase() + ":vpn:activating\n")).rows,
        [{ uuid: BRANCH, name: "Branch:IPsec", type: "vpn", state: "activating" }]);
    for (const [code, output, state] of [[0, "", "available"], [8, "", "not-running"], [10, "x:" + HOME + ":vpn:", "no-answer"],
        [-1, text("list.txt"), "no-answer"], [0, "bad:" + HOME + ":vpn", "no-answer"], [0, "bad:not-a-uuid:vpn:", "no-answer"],
        [0, "bad:" + HOME + ":vpn:connected", "no-answer"], [0, "bad:" + HOME + ":vpn:ending\\", "no-answer"],
        [0, "Wired:not-a-uuid:ethernet:activated", "available"]])
        assert.equal(logic.list(code, output).state, state, JSON.stringify([code, output]));
    const crowd = plain(logic.list(0, Array.from({ length: 40 }, (_, i) =>
        "P" + i + ":" + String(i).padStart(8, "0") + "-0000-4000-8000-000000000000:wireguard:" + (i === 39 ? "activated" : "")).join("\n")));
    assert.equal(crowd.rows.length, logic.PROFILE_MAX);
    assert.equal(crowd.count, 40);
    assert.equal(crowd.activeCount, 1);

    // One detail read for the whole uuid set, in a stable order.
    const key = logic.detailsKey(listing);
    assert.equal(key, [HOME, OFFICE, TRAVEL, CAMPUS, BRANCH, LAB].sort().join(" "));
    assert.equal(logic.detailsKey({ rows: listing.rows.slice().reverse() }), key);
    assert.deepEqual(plain(logic.detailsArgv(key)), ["nmcli", "-t", "-f", "connection.uuid,vpn.service-type,vpn.data,wireguard.peers",
        "connection", "show"].concat(...key.split(" ").map(uuid => ["uuid", uuid])));
    const details = plain(logic.details(0, text("details.txt"), key));
    assert.deepEqual(details, {
        [CAMPUS]: { service: "openconnect", server: "vpn.example.edu" },
        [TRAVEL]: { service: "l2tp", server: "l2tp.example.net" },
        [BRANCH]: { service: "vpnc", server: "ipsec.example.net" },
        [OFFICE]: { service: "openvpn", server: "vpn.example.com" },
        [HOME]: { service: "", server: "203.0.113.10:51820" },
        [LAB]: { service: "", server: "[2001:db8::1]:51820" }
    });
    holdsNothingPrivate(details, "details");
    // A record starts at its uuid line, not at the blank line.
    assert.deepEqual(plain(logic.details(0, text("details.txt").replace(/\n\n/g, "\n"), key)), details);
    assert.deepEqual(plain(logic.details(0, text("details.txt"), [HOME, OFFICE].join(" "))), { [HOME]: details[HOME], [OFFICE]: details[OFFICE] });
    assert.equal(logic.details(10, text("details.txt"), key), null);
    assert.equal(logic.details(-1, "", key), null);
    assert.equal(logic.details(0, "", key), null);
    assert.equal(logic.details(0, text("details.txt"), key + " 00000000-0000-4000-8000-000000000000"), null);
    for (const [service, data, server] of [
        ["openvpn", "ca = /home/fixture/a\\, b.pem, remote = vpn.example.com:1194\\, vpn2.example.com:1195", "vpn.example.com:1194"],
        ["openvpn", "remote = vpn.example.com", "vpn.example.com"],
        ["l2tp", "user = fixture-user, gateway = l2tp\\,odd.example.net", "l2tp,odd.example.net"],
        ["strongswan", "address = ipsec.example.org, method = key", "ipsec.example.org"],
        ["libreswan", "right = 198.51.100.7, leftid = fixture-user", "198.51.100.7"],
        ["vpnc", "IPSec ID = grp", ""],
        ["future", "gateway = vpn.example.net", ""]
    ]) {
        const read = plain(logic.details(0, "connection.uuid:" + OFFICE + "\nvpn.service-type:org.freedesktop.NetworkManager." + service + "\nvpn.data:" + data + "\n", OFFICE));
        assert.equal(read[OFFICE].server, server, service + " " + data);
        holdsNothingPrivate(read, service);
    }
    assert.equal(plain(logic.details(0, "connection.uuid:" + LAB + "\nwireguard.peers:HIgo9xNzJMWLKASShiTqIybxZ0U3wGLiUeJ1PKf8ykw= allowed-ips=10.30.0.0/24, xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg= endpoint=203.0.113.9:51820\n", LAB))[LAB].server, "");
    assert.equal(plain(logic.details(0, "connection.uuid:" + OFFICE + "\nvpn.service-type:com.example.vpn\n", OFFICE))[OFFICE].service, "");

    // The address read.
    assert.deepEqual(plain(logic.addressArgv(HOME)), ["nmcli", "-t", "-f", "GENERAL.STATE,IP4.ADDRESS", "connection", "show", "uuid", HOME]);
    assert.equal(logic.address(0, text("address.txt")), "10.20.0.2");
    assert.equal(logic.address(0, ""), "");
    assert.equal(logic.address(0, "GENERAL.STATE:activated\n"), "");
    assert.equal(logic.address(0, "GENERAL.STATE:activating\nIP4.ADDRESS[1]:10.20.0.2/24\n"), "");
    assert.equal(logic.address(2, ""), null);
    assert.equal(logic.address(-1, text("address.txt")), null);

    // The failure each `up` text leaves, by the profile it ran on and
    // whether the connect carried a password: a carried one leaves
    // password-tried unless nmcli named a missing plugin or another secret.
    const rowOf = (uuid, service) => Object.assign({}, listing.rows.find(row => row.uuid === uuid), { service });
    const noValidSecrets = "Error: Connection activation failed: No valid secrets";
    for (const [name, code, row, kind, failedService, carried] of [
        ["up-secrets-wireguard.txt", 4, rowOf(LAB, ""), "sign-in", ""],
        ["up-secrets-password.txt", 4, rowOf(TRAVEL, "l2tp"), "needs-password", ""],
        ["up-secrets-password.txt", 4, rowOf(OFFICE, "openvpn"), "needs-password", ""],
        ["up-secrets-password.txt", 4, rowOf(BRANCH, "vpnc"), "sign-in", ""],
        ["up-secrets-password.txt", 4, rowOf(TRAVEL, ""), "sign-in", ""],
        ["up-secrets-multiple.txt", 4, rowOf(TRAVEL, "l2tp"), "sign-in", ""],
        ["up-secrets-multiple.txt", 4, rowOf(BRANCH, "vpnc"), "sign-in", ""],
        ["up-service-missing.txt", 4, rowOf(BRANCH, ""), "plugin-needed", "vpnc"],
        ["up-failed.txt", 4, rowOf(OFFICE, "openvpn"), "failed", ""],
        ["up-secrets-password.txt", -1, rowOf(TRAVEL, "l2tp"), "failed", ""],
        [null, 4, rowOf(TRAVEL, "l2tp"), "sign-in", ""],
        ["up-failed.txt", 4, rowOf(TRAVEL, "l2tp"), "failed", "", false],
        ["up-secrets-password.txt", 4, rowOf(TRAVEL, "l2tp"), "needs-password", "", false],
        ["up-secrets-password.txt", -1, rowOf(OFFICE, "openvpn"), "failed", "", false],
        [null, 4, rowOf(TRAVEL, "l2tp"), "sign-in", "", false],
        ["up-failed.txt", 4, rowOf(TRAVEL, "l2tp"), "password-tried", "", true],
        ["up-failed.txt", 4, rowOf(OFFICE, "openvpn"), "password-tried", "", true],
        ["up-secrets-password.txt", -1, rowOf(OFFICE, "openvpn"), "password-tried", "", true],
        [null, 4, rowOf(OFFICE, "sstp"), "password-tried", "", true],
        ["up-secrets-password.txt", 4, rowOf(TRAVEL, "l2tp"), "password-tried", "", true],
        ["up-service-missing.txt", 4, rowOf(BRANCH, ""), "plugin-needed", "vpnc", true],
        ["up-secrets-multiple.txt", 4, rowOf(TRAVEL, "l2tp"), "sign-in", "", true]
    ]) {
        const output = name === null ? noValidSecrets : text(name);
        const failure = plain(logic.upFailure(code, output, row, carried));
        assert.deepEqual(failure, { kind, service: failedService }, (name || noValidSecrets) + " on " + row.name + " carried=" + carried);
        holdsNothingPrivate(failure, name || noValidSecrets);
    }
    for (const [code, output, outcome] of [[0, "", "removed"], [10, text("delete-unknown.txt"), "gone"],
        [1, text("up-failed.txt"), "failed"], [-1, text("delete-unknown.txt"), "failed"]])
        assert.equal(logic.removeOutcome(code, output), outcome);

    // The published rows and what each one shows.
    const addresses = { [HOME]: "10.20.0.2", [OFFICE]: "10.9.9.9" };
    const failures = { [TRAVEL]: { kind: "needs-password", service: "" }, [BRANCH]: { kind: "sign-in", service: "" },
        [LAB]: { kind: "plugin-needed", service: "vpnc" } };
    const profiles = plain(logic.compose(listing, Object.assign({}, details, { [LAB]: undefined }), addresses, failures, null, ""));
    holdsNothingPrivate(profiles, "profiles");
    const byUuid = uuid => profiles.rows.find(row => row.uuid === uuid);
    assert.deepEqual(byUuid(HOME), { uuid: HOME, name: "Home tunnel", type: "wireguard", state: "activated", service: "",
        details: "available", server: "203.0.113.10:51820", address: "10.20.0.2", failure: "" });
    assert.equal(byUuid(OFFICE).address, "", "an address shows only while activated");
    assert.equal(byUuid(LAB).service, "vpnc", "a missing plugin names its service before the details answer");
    assert.deepEqual(Object.keys(profiles).sort(), ["action", "activeCount", "count", "problem", "rows", "state"]);
    // An installed OpenVPN plugin supersedes an earlier failed connect.
    const missingPlugin = plain(logic.compose(listing, details, {}, { [OFFICE]: { kind: "plugin-needed", service: "openvpn" } }, null, ""));
    const viewOf = (payload, uuid) => plain(logic.rowView(payload.rows.find(row => row.uuid === uuid), payload));
    const flags = view => [view.key, view.connected, view.switchOn, view.busy, view.danger, view.reason !== ""];
    for (const [payload, uuid, want] of [
        [profiles, HOME, ["connected", true, true, false, false, false]],
        [profiles, OFFICE, ["off", false, false, false, false, false]],
        [profiles, TRAVEL, ["needs-password", false, false, false, false, false]],
        [profiles, CAMPUS, ["unsupported", false, false, false, false, true]],
        [profiles, BRANCH, ["sign-in", false, false, false, false, true]],
        [profiles, LAB, ["plugin-needed", false, false, false, false, true]],
        [missingPlugin, OFFICE, ["off", false, false, false, false, false]],
        [missingPlugin, TRAVEL, ["off", false, false, false, false, false]],
        [plain(logic.compose(listing, details, {}, { [OFFICE]: { kind: "failed", service: "" } }, null, "")), OFFICE,
            ["failed", false, false, false, true, false]],
        [plain(logic.compose(listing, details, {}, { [HOME]: { kind: "failed", service: "" } }, null, "")), HOME,
            ["connected", true, true, false, false, false]],
        [plain(logic.compose(listing, details, {}, {}, { kind: "profile-up", uuid: OFFICE, name: "Office VPN" }, "")), OFFICE,
            ["connecting", false, true, true, false, true]],
        [plain(logic.compose(listing, details, {}, {}, { kind: "profile-down", uuid: HOME, name: "Home tunnel" }, "")), HOME,
            ["disconnecting", true, false, true, false, true]],
        [plain(logic.compose(listing, details, {}, {}, { kind: "profile-remove", uuid: OFFICE, name: "Office VPN" }, "")), OFFICE,
            ["removing", false, false, true, false, true]],
        [plain(logic.compose(logic.list(0, "Office VPN:" + OFFICE + ":vpn:activating"), details, {}, {}, null, "")), OFFICE,
            ["connecting", false, true, true, false, true]],
        [plain(logic.compose(listing, details, {}, { [TRAVEL]: { kind: "password-tried", service: "" } }, null, "")), TRAVEL,
            ["needs-password", false, false, false, false, false]]
    ]) assert.deepEqual(flags(viewOf(payload, uuid)), want, uuid + " " + want[0]);
    // A connect with a password that failed draws the row and its switch
    // exactly as before the first password, so the switch asks again.
    const tried = plain(logic.compose(listing, details, {}, { [TRAVEL]: { kind: "password-tried", service: "" } }, null, ""));
    assert.deepEqual(viewOf(tried, TRAVEL), viewOf(profiles, TRAVEL));
    // Each service has its own type name; an unread or unknown one reads as
    // a plain VPN.
    const names = Object.keys(logic.TYPE_NAMES).map(service => logic.typeName("vpn", service));
    assert.equal(new Set(names).size, names.length);
    assert.ok(!names.includes(logic.typeName("vpn", "")));
    assert.equal(logic.typeName("vpn", "future"), logic.typeName("vpn", ""));
    assert.notEqual(logic.typeName("wireguard", ""), logic.typeName("vpn", ""));

    // IPC plans address profiles by uuid; a blocked switch refuses as well.
    for (const [request, payload, want] of [
        [{ kind: "profile-up", id: OFFICE }, profiles, { argv: ["nmcli", "connection", "up", "uuid", OFFICE] }],
        [{ kind: "profile-up", id: TRAVEL }, profiles, { argv: ["nmcli", "connection", "up", "uuid", TRAVEL] }],
        [{ kind: "profile-down", id: HOME }, profiles, { argv: ["nmcli", "connection", "down", "uuid", HOME] }],
        [{ kind: "profile-remove", id: CAMPUS }, profiles, { argv: ["nmcli", "connection", "delete", "uuid", CAMPUS] }],
        [{ kind: "profile-details", id: HOME }, profiles, { address: HOME }],
        [{ kind: "profile-up", id: HOME }, profiles, { refusal: "refused: profile=state" }],
        [{ kind: "profile-down", id: OFFICE }, profiles, { refusal: "refused: profile=state" }],
        [{ kind: "profile-up", id: CAMPUS }, profiles, { refusal: "refused: profile=unsupported" }],
        [{ kind: "profile-up", id: BRANCH }, profiles, { refusal: "refused: profile=sign-in" }],
        [{ kind: "profile-up", id: OFFICE }, missingPlugin, { argv: ["nmcli", "connection", "up", "uuid", OFFICE] }],
        [{ kind: "profile-up", id: "Office VPN" }, profiles, { refusal: "refused: profile=absent" }],
        [{ kind: "profile-up", id: OFFICE }, plain(logic.compose(logic.emptyProfiles("not-running"), {}, {}, {}, null, "")), { refusal: "refused: profile=unavailable" }],
        [{ kind: "import" }, profiles, { refusal: "refused: profile=action" }],
        [[], profiles, { refusal: "refused: profile=action" }]
    ]) assert.deepEqual(plain(logic.profileCommand(request, payload)), want, JSON.stringify(request));

    // The one passwd-file line: nmcli 1.58.1 strips unescaped edge
    // whitespace and reads a backslash as an escape, and a CR or LF would
    // start a second line (VGS-1932 verify-first § 2).
    for (const [password, line] of [
        ["hunter2", "vpn.secrets.password:hunter2\n"],
        ["back\\slash", "vpn.secrets.password:back\\\\slash\n"],
        ["\\\\", "vpn.secrets.password:\\\\\\\\\n"],
        [" lead", "vpn.secrets.password:\\040lead\n"],
        ["trail ", "vpn.secrets.password:trail\\040\n"],
        ["  both  ", "vpn.secrets.password:\\040\\040both\\040\\040\n"],
        [" ", "vpn.secrets.password:\\040\n"],
        ["\ttab\t", "vpn.secrets.password:\\ttab\\t\n"],
        ["\v\fedge\f\v", "vpn.secrets.password:\\v\\fedge\\f\\v\n"],
        ["a b\tc\vd\fe", "vpn.secrets.password:a b\tc\vd\fe\n"],
        ["line\nbreak\r", "vpn.secrets.password:line\\nbreak\\r\n"],
        ["\r\nlead", "vpn.secrets.password:\\r\\nlead\n"],
        ["c:o=lon", "vpn.secrets.password:c:o=lon\n"],
        [" a\\b ", "vpn.secrets.password:\\040a\\\\b\\040\n"],
        ["", null],
        ["nul\u0000", null],
        ["\u0000", null],
        [42, null],
        [null, null],
        [undefined, null]
    ]) assert.equal(logic.passwordLine(password), line, JSON.stringify(password));

    // A password connect runs only on a profile that reads Needs password,
    // reads its passwd-file on stdin, and never asks or waits.
    const passwordArgv = uuid => ["nmcli", "connection", "up", "uuid", uuid, "passwd-file", "/dev/stdin"];
    for (const [uuid, payload, want] of [
        [TRAVEL, profiles, { argv: passwordArgv(TRAVEL) }],
        [TRAVEL, tried, { argv: passwordArgv(TRAVEL) }],
        [TRAVEL.toUpperCase(), profiles, { refusal: "refused: profile=absent" }],
        [OFFICE, profiles, { refusal: "refused: profile=state" }],
        [HOME, profiles, { refusal: "refused: profile=state" }],
        [BRANCH, profiles, { refusal: "refused: profile=state" }],
        [CAMPUS, profiles, { refusal: "refused: profile=state" }],
        [LAB, profiles, { refusal: "refused: profile=state" }],
        [TRAVEL, plain(logic.compose(listing, details, {}, { [TRAVEL]: { kind: "failed", service: "" } }, null, "")), { refusal: "refused: profile=state" }],
        [TRAVEL, plain(logic.compose(listing, details, {}, failures, { kind: "profile-up", uuid: TRAVEL, name: "Travel L2TP" }, "")), { refusal: "refused: profile=state" }],
        ["Travel L2TP", profiles, { refusal: "refused: profile=absent" }],
        [TRAVEL, plain(logic.compose(logic.emptyProfiles("not-running"), {}, {}, {}, null, "")), { refusal: "refused: profile=unavailable" }]
    ]) {
        const plan = plain(logic.passwordCommand(uuid, payload));
        assert.deepEqual(plan, want, uuid);
        if (plan.argv !== undefined) assert.ok(!plan.argv.some(word => word === "--ask" || word === "--wait"), "a password connect never asks or waits");
    }

    // submitConnect hands the owner the uuid and a closure that writes the
    // one line and then closes stdin; a password nmcli cannot read, or no
    // owner, reaches no owner.
    const planted = " planted\\stand-in ";
    const plantedLine = "vpn.secrets.password:\\040planted\\\\stand-in\\040\n";
    const connects = [];
    const owner = { reply: "ok", connectWithPassword(uuid, feed) { connects.push([uuid, feed]); return owner.reply; } };
    const other = { connectWithPassword() { throw new Error("a released owner was called"); } };
    assert.equal(logic.submitConnect(TRAVEL, planted), "unavailable");
    logic.attachConnect(other);
    logic.attachConnect(owner);
    logic.releaseConnect(other);
    for (const refused of ["", "nul\u0000", 42, null])
        assert.equal(logic.submitConnect(TRAVEL, refused), "refused: password=value", JSON.stringify(refused));
    assert.deepEqual(connects, []);
    assert.equal(logic.submitConnect(TRAVEL, planted), "ok");
    owner.reply = "busy";
    assert.equal(logic.submitConnect(TRAVEL, planted), "busy");
    assert.deepEqual(connects.map(call => call[0]), [TRAVEL, TRAVEL]);
    const events = [];
    const child = { write(data) { events.push(["write", data]); }, set stdinEnabled(value) { events.push(["stdin", value]); } };
    connects[0][1](child);
    assert.deepEqual(events, [["write", plantedLine], ["stdin", false]]);
    logic.releaseConnect(owner);
    assert.equal(logic.submitConnect(TRAVEL, planted), "unavailable");
    assert.equal(connects.length, 2);

    // The bar icon and its tooltip's subject.
    const bar = payload => plain(logic.barView(payload));
    for (const hidden of [null, logic.emptyProfiles("reading"), logic.emptyProfiles("not-running"), logic.compose(logic.list(0, ""), {}, {}, {}, null, "")])
        assert.equal(bar(hidden).shown, false);
    const quiet = plain(logic.compose(listing, details, addresses, {}, null, ""));
    assert.deepEqual([bar(quiet).icon, bar(quiet).spinning, bar(quiet).warning], ["shield-check", false, false]);
    assert.ok(bar(quiet).tooltip.includes("Home tunnel"));
    const two = plain(logic.compose(logic.list(0, text("list.txt").replace("Office VPN:" + OFFICE + ":vpn:", "Office VPN:" + OFFICE + ":vpn:activated")), details, {}, {}, null, ""));
    assert.ok(bar(two).tooltip.includes("2") && !bar(two).tooltip.includes("Home tunnel"));
    const off = plain(logic.compose(logic.list(0, "Office VPN:" + OFFICE + ":vpn:"), details, {}, {}, null, ""));
    assert.deepEqual([bar(off).shown, bar(off).icon, bar(off).warning], [true, "shield-off", false]);
    const connecting = plain(logic.compose(listing, details, {}, {}, { kind: "profile-up", uuid: OFFICE, name: "Office VPN" }, ""));
    assert.deepEqual([bar(connecting).spinning, bar(connecting).warning], [true, false]);
    assert.ok(bar(connecting).tooltip.includes("Office VPN"));
    assert.equal(bar(plain(logic.compose(listing, details, {}, {}, { kind: "profile-remove", uuid: OFFICE, name: "Office VPN" }, ""))).spinning, false);
    const alerts = {};
    for (const [kind, warning] of [["needs-password", true], ["password-tried", true], ["failed", true], ["sign-in", false], ["plugin-needed", false]]) {
        const view = bar(plain(logic.compose(listing, details, {}, { [OFFICE]: { kind, service: "" } }, null, "")));
        assert.equal(view.warning, warning, kind);
        assert.equal(view.icon, warning ? "shield-alert" : "shield-check", kind);
        if (warning) assert.ok(view.tooltip.includes("Office VPN"));
        alerts[kind] = view.tooltip;
    }
    // password-tried says the profile needs a password, never that it failed.
    assert.equal(alerts["password-tried"], alerts["needs-password"]);
    assert.notEqual(alerts["password-tried"], alerts.failed);

    // Execute the shipped list completion body. start-order reads its
    // log severity; process output can contain private profile data.
    const bodyOf = (id, name) => {
        const found = new RegExp("id: " + id + "[\\s\\S]*?onRunningChanged: \\{([\\s\\S]*?)\\n        \\}").exec(service);
        assert.ok(found, name);
        return found[1];
    };
    const codeBody = /function codeOf\(completion\) \{([\s\S]*?)\n    \}/.exec(service);
    const wordBody = /function completionWord\(code\) \{([\s\S]*?)\n    \}/.exec(service);
    assert.ok(codeBody && wordBody);
    const helpers = () => ({ codeOf: new Function("completion", codeBody[1]), completionWord: new Function("code", wordBody[1]), retried: 0,
        autoRetry() { this.retried++; } });
    const logs = () => {
        const messages = [];
        return { messages, log(message) { messages.push(["log", message]); }, warn(message) { messages.push(["warn", message]); } };
    };
    const completeList = new Function("running", "completion", "root", "Logic", "profilesText", "profilesDeadline", "again", "console", bodyOf("profilesReader", "list"));
    for (const [code, output, state, level, kind] of [
        [1, "/home/fixture/x.conf", "no-answer", "log", "failed"],
        [8, "/home/fixture/x.conf", "not-running", "log", "failed"],
        [10, "PRIVATE-FIXTURE-PROFILE-ERROR", "no-answer", "warn", "failed"],
        [-1, "PRIVATE-FIXTURE-PROFILE-ERROR", "no-answer", "warn", "interrupted"],
        [0, "malformed", "no-answer", "warn", "invalid-reply"],
        [0, text("list.txt"), "available", null, null]
    ]) {
        const console = logs();
        const owner = Object.assign(helpers(), { listed(next) { owner.listing = plain(next); owner.networksAtList = owner.networks; } });
        let stopped = false;
        completeList(false, code === -1 ? null : { code, status: 0 }, owner, logic, { text: output }, { stop() { stopped = true; } }, false, console);
        assert.equal(owner.listing.state, state);
        // The same read's networks are in place before the list decides.
        assert.equal(owner.networksAtList.state, state === "available" ? "available" : "unreadable");
        assert.equal(stopped, true);
        assert.deepEqual(console.messages, level === null ? [] : [[level, "vpn: operation=profile-read completion=" + kind + " code=" + code]]);
    }
    // A new list reads the details only for a changed uuid set, drops the
    // failure of a profile now activated and the address of one no longer
    // activated, and queues the address of each activated profile without
    // one.
    const listedBody = /function listed\(next\) \{([\s\S]*?)\n    \}/.exec(service);
    assert.ok(listedBody);
    // `with` resolves the body's bare names on the owner, as QML does.
    const runListed = new Function("Logic", "owner", "next", "with (owner) {" + listedBody[1] + "}");
    const listedOwner = (fields) => {
        const owner = Object.assign({ listing: null, failures: {}, addresses: {}, profileProblem: null, profileAction: null, detailsRead: "", reads: 0, queued: [],
            decided: 0, readDetails() { owner.reads++; }, queueAddress(uuid) { owner.queued.push(uuid); }, autoConnect() { owner.decided++; } }, fields);
        return owner;
    };
    for (const [name, next, fields, reads, failureUuids, addressUuids, queued] of [
        ["an unchanged uuid set reads no details", listing, { detailsRead: key }, 0, [], [], [HOME]],
        ["a changed uuid set reads once", listing, { detailsRead: [HOME, OFFICE].join(" ") }, 1, [], [], [HOME]],
        ["failures stay off activated profiles", listing, { detailsRead: key,
            failures: { [HOME]: { kind: "failed", service: "" }, [OFFICE]: { kind: "failed", service: "" } } }, 0, [OFFICE], [], [HOME]],
        ["addresses stay on activated profiles", listing, { detailsRead: key, addresses: { [HOME]: "10.20.0.2", [OFFICE]: "10.9.9.9" } },
            0, [], [HOME], []],
        ["no answer reads nothing", logic.emptyProfiles("no-answer"), { detailsRead: key,
            failures: { [OFFICE]: { kind: "failed", service: "" } }, addresses: { [HOME]: "10.20.0.2" } }, 0, [], [], []]
    ]) {
        const owner = listedOwner(fields);
        runListed(logic, owner, next);
        assert.equal(owner.listing, next, name);
        assert.equal(owner.reads, reads, name);
        assert.deepEqual(Object.keys(owner.failures).sort(), failureUuids.slice().sort(), name);
        assert.deepEqual(Object.keys(owner.addresses).sort(), addressUuids.slice().sort(), name);
        assert.deepEqual(owner.queued, queued, name);
        // Connect automatically decides at every list read, an unreadable one too.
        assert.equal(owner.decided, 1, name);
    }
    // A new list drops the problem line of a profile it no longer holds
    // and of a connect whose failure it dropped.
    const problemOf = (uuid, kind) => ({ uuid, kind, text: logic.problem(kind, byUuid(uuid).name, 4) });
    for (const [name, next, problem, failures, kept] of [
        ["a listed profile keeps its connect problem", listing, problemOf(OFFICE, "profile-up"), { [OFFICE]: { kind: "failed", service: "" } }, true],
        ["a profile gone from the list drops its problem", logic.list(0, "Home tunnel:" + HOME + ":wireguard:activated"),
            problemOf(OFFICE, "profile-up"), { [OFFICE]: { kind: "failed", service: "" } }, false],
        ["an empty list drops every problem", logic.list(0, ""), problemOf(OFFICE, "profile-remove"), {}, false],
        ["a connect now activated drops its problem", logic.list(0, "Office VPN:" + OFFICE + ":vpn:activated"),
            problemOf(OFFICE, "profile-up"), { [OFFICE]: { kind: "failed", service: "" } }, false]
    ]) {
        const owner = listedOwner({ detailsRead: logic.detailsKey(next), failures, profileProblem: problem });
        runListed(logic, owner, next);
        assert.equal(owner.profileProblem === null ? null : owner.profileProblem.uuid, kept ? problem.uuid : null, name);
        assert.equal(plain(logic.compose(owner.listing, {}, {}, owner.failures, null,
            owner.profileProblem === null ? "" : owner.profileProblem.text)).problem === "", !kept, name);
    }
    // The detail completion keeps a read only when it answered.
    const completeDetails = new Function("running", "completion", "key", "again", "root", "Logic", "detailsText", "detailsDeadline", "console", bodyOf("detailsReader", "details"));
    for (const [code, output, kept] of [[0, text("details.txt"), true], [10, text("up-failed.txt") + "/home/fixture", false], [0, "", false]]) {
        const console = logs();
        const owner = Object.assign(helpers(), { listing, detailMap: { [HOME]: details[HOME] }, detailsRead: key, readDetails() { owner.again = true; } });
        completeDetails(false, { code, status: 0 }, key, false, owner, logic, { text: output }, { stop() {} }, console);
        assert.equal(owner.detailsRead, kept ? key : "");
        assert.deepEqual(plain(owner.detailMap), kept ? details : Object.fromEntries(key.split(" ").map(uuid => [uuid, uuid === HOME ? details[HOME] : null])));
        assert.deepEqual(console.messages, kept ? [] : [["warn", "vpn: operation=profile-details completion=" + (code === 0 ? "invalid-reply" : "failed") + " code=" + code]]);
        // A connect refused while the details were read is decided again.
        assert.equal(owner.retried, 1, "a detail read's end decides Connect automatically again");
    }
    // The action completion records the failure kind on the uuid, clears it
    // on success, leaves a problem line, and logs no nmcli text.
    const completeAction = new Function("running", "completion", "root", "Logic", "actorText", "actorErrors", "profileActionDeadline", "console", bodyOf("profileActor", "action"));
    for (const [kind, uuid, code, output, failure, problem, password] of [
        ["profile-up", TRAVEL, 4, text("up-failed.txt"), "password-tried", true, true],
        ["profile-up", TRAVEL, 4, text("up-secrets-multiple.txt"), "sign-in", true, true],
        ["profile-up", TRAVEL, 0, "Connection successfully activated", null, false, true],
        ["profile-up", TRAVEL, 4, text("up-secrets-password.txt"), "needs-password", true],
        ["profile-up", LAB, 4, text("up-secrets-wireguard.txt"), "sign-in", true],
        ["profile-up", BRANCH, 4, text("up-service-missing.txt"), "plugin-needed", true],
        ["profile-up", OFFICE, 4, text("up-failed.txt"), "failed", true],
        ["profile-up", TRAVEL, 0, "Connection successfully activated", null, false],
        ["profile-down", HOME, 4, text("up-failed.txt"), null, true],
        ["profile-remove", OFFICE, 10, text("delete-unknown.txt"), null, false],
        ["profile-remove", OFFICE, 1, text("up-failed.txt"), null, true]
    ]) {
        const console = logs();
        let reads = 0;
        const checks = [];
        // A feed the run never took, as when it never started, goes with it.
        const owner = Object.assign(helpers(), { profiles, failures: { [TRAVEL]: { kind: "needs-password", service: "" } },
            profileAction: { kind, uuid, name: byUuid(uuid).name, password: password === true }, profileProblem: null,
            connectFeed: () => {}, runEnded() { reads++; }, startCheck(checked, active) { checks.push([checked, active]); }, autoEnds: [],
            autoEnded(...args) { owner.autoEnds.push(args); } });
        completeAction(false, { code, status: 0 }, owner, logic, { text: "" }, { text: output }, { stop() {} }, console);
        assert.equal(owner.connectFeed, null, kind + " " + code);
        if (kind === "profile-up") assert.equal(owner.failures[uuid] === undefined ? null : owner.failures[uuid].kind, failure, kind + " " + code);
        // A connect's end reaches Connect automatically, with its problem line when it failed.
        assert.deepEqual(owner.autoEnds, kind === "profile-up" ? [[uuid, problem, problem ? owner.profileProblem.text : ""]] : [], kind + " " + code);
        assert.deepEqual(owner.profileProblem === null ? null : [owner.profileProblem.uuid, owner.profileProblem.kind],
            problem ? [uuid, kind] : null, kind + " " + code);
        if (problem) assert.equal(typeof owner.profileProblem.text === "string" && owner.profileProblem.text !== "", true, kind + " " + code);
        // The change stays in flight until the next list (runEnded, below).
        assert.equal(reads, 1, "the run's end hands over to runEnded");
        // A connect that completed starts one leak check of its profile,
        // as connected; no other end starts one (VGS-2398).
        assert.deepEqual(checks, kind === "profile-up" && code === 0 ? [[uuid, true]] : [], kind + " " + code + " leak check");
        assert.deepEqual(console.messages, code === 0 ? [] : [["warn", "vpn: operation=" + kind + " completion=failed code=" + code]]);
        holdsNothingPrivate([owner.failures, owner.profileProblem], kind);
    }

    // A password connect: connectWithPassword plans it and startAction runs
    // nmcli with stdin open and the feed held; the run's start hands the
    // feed the child once and drops it. A plain change holds no feed.
    const bodyNamed = name => {
        const found = new RegExp("function " + name + "\\(([^)]*)\\) \\{([\\s\\S]*?)\\n    \\}").exec(service);
        assert.ok(found, name);
        return found;
    };
    const method = (owner, name) => {
        const found = bodyNamed(name);
        const params = found[1].split(",").map(param => param.trim()).filter(param => param !== "");
        owner[name] = new Function("Logic", "owner", ...params, "with (owner) {" + found[2] + "}").bind(null, logic, owner);
    };
    const feed = () => {};
    // The window between a connect's exit 0 and the next list: the list
    // still reads the profile as before the run, and the kill switch's
    // status still reads holding from the arm wait, so with the action
    // cleared the published state read as a drop. The change stays in
    // flight until a list read started after the run lands; a read
    // already running when it ended started before it, so the one after
    // decides.
    const beforeRun = Object.assign({}, listing, { rows: listing.rows.map(row => row.uuid === HOME ? Object.assign({}, row, { state: "" }) : row), activeCount: 0 });
    const afterRun = listing;
    const holdingHome = plain(logic.killSwitchState({ state: "ready", reason: "granted" }, { kind: "valid", meantOn: HOME, mode: "block", portalUntil: "0" },
        logic.killStatus(0, "state=holding reason=tunnel-down blocked=0 tunnel= profile=" + HOME + "\n"), false, "", false));
    for (const [name, running, listsToClear] of [["no read running", false, 1], ["a read already running", true, 2]]) {
        const ending = { registered: true, profilesMissing: false, profilesReader: { running }, reads: 0, readProfiles() { ending.reads++; },
            profileAction: { kind: "profile-up", uuid: HOME, name: "Home tunnel", password: false },
            listing: beforeRun, failures: {}, addresses: {}, profileProblem: null, detailsRead: key, readDetails() {}, queueAddress() {}, autoConnect() {} };
        method(ending, "runEnded");
        method(ending, "listed");
        ending.runEnded();
        assert.equal(ending.reads, 1, name + ": the run's end asks for a list");
        assert.notEqual(ending.profileAction, null, name + ": the change stays in flight");
        assert.equal(logic.blockedNotice(holdingHome, plain(logic.compose(beforeRun, details, {}, {}, ending.profileAction, ""))), null, name + ": no drop in the window");
        for (let list = 1; list < listsToClear; list++) {
            ending.listed(beforeRun);
            assert.notEqual(ending.profileAction, null, name + ": a list read started before the end does not end it");
        }
        ending.listed(afterRun);
        assert.equal(ending.profileAction, null, name + ": the list after the run ends it");
    }
    const unread = { registered: true, profilesMissing: true, profilesReader: { running: false }, readProfiles() { throw new Error("no list to read"); },
        profileAction: { kind: "profile-up", uuid: HOME, name: "Home tunnel", password: false } };
    method(unread, "runEnded");
    unread.runEnded();
    assert.equal(unread.profileAction, null, "with no list to read the change ends at once");
    const actor = stdinEnabled => ({ running: false, stdinEnabled, command: [], completion: "old" });
    // stale: a feed and an open stdin a change before this one left behind.
    const actionOwner = (stale = false) => {
        const owner = { profiles, shell: { requirements: { missing: [] } }, profileAction: null, profileProblem: { uuid: OFFICE }, connectFeed: stale ? () => {} : null,
            profileActor: actor(stale), restarts: 0, profileActionDeadline: { restart() { owner.restarts++; } },
            stateWrite: null, killReady: false, killFile: { kind: "reading" }, killSwitch: null };
        method(owner, "connectWithPassword");
        method(owner, "startAction");
        method(owner, "launch");
        return owner;
    };
    const started = actionOwner();
    assert.equal(started.connectWithPassword(TRAVEL, feed), "ok");
    assert.deepEqual(plain(started.profileAction), { kind: "profile-up", uuid: TRAVEL, name: "Travel L2TP", password: true });
    assert.deepEqual(plain(started.profileActor), { running: true, stdinEnabled: true, command: passwordArgv(TRAVEL), completion: null });
    assert.equal(started.connectFeed, feed);
    assert.equal(started.profileProblem, null);
    assert.equal(started.restarts, 1);
    assert.equal(started.connectWithPassword(TRAVEL, () => {}), "busy", "one change at a time");
    assert.equal(started.connectFeed, feed);
    const refusedConnect = actionOwner();
    assert.equal(refusedConnect.connectWithPassword(OFFICE, feed), "refused: profile=state");
    assert.deepEqual([refusedConnect.profileActor.running, refusedConnect.connectFeed, refusedConnect.profileAction], [false, null, null]);
    const plainChange = actionOwner(true);
    assert.equal(plainChange.startAction("profile-up", OFFICE, ["nmcli", "connection", "up", "uuid", OFFICE], null), "ok");
    assert.deepEqual([plainChange.profileAction.password, plainChange.profileActor.stdinEnabled, plainChange.connectFeed], [false, false, null]);
    const startBody = /onStarted: \{([\s\S]*?)\n        \}/.exec(service);
    assert.ok(startBody);
    const runStart = new Function("root", "profileActor", startBody[1]);
    const handed = [];
    const startedChild = { name: "child" };
    const startOwner = { connectFeed: process => handed.push(process) };
    runStart(startOwner, startedChild);
    runStart(startOwner, startedChild);
    assert.deepEqual(handed, [startedChild], "the feed runs once, with the started child");
    assert.equal(startOwner.connectFeed, null);
    runStart({ connectFeed: null }, startedChild);
    // The service's destruction releases the connect owner and drops a
    // feed still held.
    const destructionBody = /Component\.onDestruction: \{([\s\S]*?)\n    \}/.exec(service);
    assert.ok(destructionBody);
    const destroyed = { connectWithPassword() { throw new Error("a destroyed owner was called"); }, connectFeed: () => {} };
    logic.attachConnect(destroyed);
    new Function("Logic", "root", "owner", "with (owner) {" + destructionBody[1] + "}")(logic, destroyed, destroyed);
    assert.equal(destroyed.connectFeed, null);
    assert.equal(logic.submitConnect(TRAVEL, planted), "unavailable");

    // A requirements rescan asks again about a missing plugin or sign-in
    // detail, and keeps the failures the bar warns about.
    const recorded = { [TRAVEL]: { kind: "needs-password", service: "" }, [OFFICE]: { kind: "failed", service: "" },
        [BRANCH]: { kind: "sign-in", service: "" }, [LAB]: { kind: "plugin-needed", service: "vpnc" },
        [CAMPUS]: { kind: "password-tried", service: "" } };
    const rescanSignal = /onScansChanged: ([^\n]+)/.exec(service);
    assert.ok(rescanSignal);
    const runRescan = new Function("owner", "with (owner) {" + rescanSignal[1] + "}");
    for (const [uuid, kind, kept] of [[BRANCH, "profile-up", false], [LAB, "profile-up", false], [OFFICE, "profile-up", true],
        [TRAVEL, "profile-up", true], [BRANCH, "profile-remove", true]]) {
        const rescanned = { listing, failures: recorded, profileProblem: { uuid, kind, text: logic.problem(kind, byUuid(uuid).name, 4) },
            detailsRead: key, detailReads: 0, refreshed: 0,
            readDetails() { rescanned.detailReads++; }, readProfiles() { rescanned.refreshed++; }, readKillSwitch() {} };
        method(rescanned, "refresh");
        runRescan(rescanned);
        assert.deepEqual(Object.keys(plain(rescanned.failures)).sort(), [OFFICE, TRAVEL, CAMPUS].sort());
        assert.equal(rescanned.profileProblem === null, !kept, "a rescan's problem line for " + kind + " " + byUuid(uuid).name);
        assert.deepEqual([rescanned.detailsRead, rescanned.detailReads, rescanned.refreshed], ["", 1, 1]);
    }
    assert.deepEqual(plain(recorded)[BRANCH].kind, "sign-in", "the rescan leaves the old map unchanged");
    // An editor save changes the facts for one published UUID, including
    // a previously refused password. Other profiles keep their retries.
    for (const kind of ["needs-password", "password-tried", "sign-in", "plugin-needed", "failed"]) {
        const learned = { [OFFICE]: { kind, service: "openvpn" }, [TRAVEL]: { kind, service: "l2tp" } };
        const updated = { listing, failures: learned,
            profileProblem: { uuid: OFFICE, kind: "profile-up", text: "fixture" },
            detailsRead: key, readDetails() {}, readProfiles() {}, readKillSwitch() {} };
        method(updated, "refresh");
        assert.equal(updated.refresh(OFFICE), "ok", kind);
        assert.deepEqual(plain(updated.failures), { [TRAVEL]: learned[TRAVEL] }, kind);
        assert.equal(updated.profileProblem, null, kind);
        assert.deepEqual(plain(learned), { [OFFICE]: { kind, service: "openvpn" }, [TRAVEL]: { kind, service: "l2tp" } });
        const focused = { listing, failures: learned, profileProblem: null,
            detailsRead: key, readDetails() {}, readProfiles() {}, readKillSwitch() {} };
        method(focused, "refresh");
        focused.refresh("");
        assert.deepEqual(plain(focused.failures), learned, "ordinary metadata refresh preserves " + kind);
        const published = logic.compose(listing, details, {}, updated.failures, null, "");
        const passwordBody = /function passwordRow\(uuid\) \{([\s\S]*?)\n    \}/.exec(bodySource);
        assert.ok(passwordBody);
        const passwordRow = new Function("Logic", "profiles", "shell", "killOn", "held", "uuid", passwordBody[1]).bind(null, logic, published, { requirements: { missing: [] } }, false, "");
        assert.equal(passwordRow(OFFICE), null, kind);
        const toggleBody = /function toggle\(row, wanted\) \{([\s\S]*?)\n    \}/.exec(bodySource);
        assert.ok(toggleBody);
        const actions = [];
        const owner = { passwordRow, watchUuid: "", follow() {},
            askPassword() { actions.push("prompt"); }, act(action, uuid) { actions.push([action, uuid]); return "ok"; } };
        new Function("owner", "row", "wanted", "with (owner) {" + toggleBody[1] + "}")(owner,
            published.rows.find(row => row.uuid === OFFICE), true);
        assert.deepEqual(actions, [["profile-up", OFFICE]], kind);
        assert.deepEqual(plain(logic.profileCommand({ kind: "profile-up", id: OFFICE }, published)),
            { argv: ["nmcli", "connection", "up", "uuid", OFFICE] }, kind);
        const polled = listedOwner({ failures: learned, detailsRead: key });
        runListed(logic, polled, listing);
        assert.deepEqual(plain(polled.failures), learned, "ordinary poll preserves " + kind);
    }
    // An editor can save the same UUID while a detail read is still in
    // flight. Refresh queues one replacement read, which publishes the new
    // server; a failed replacement leaves its stamp unread for retry.
    const detailOwner = (running = false) => {
        const owner = Object.assign(helpers(), { listing, failures: recorded, profileProblem: null, profileAction: null, detailsRead: key, detailMap: details,
            registered: true, profilesMissing: false, starts: 0, refreshed: 0,
            detailsReader: { running, again: false, completion: { code: 0, status: 0 }, key, command: [] },
            detailsDeadline: { restart() { owner.starts++; }, stop() {} }, readProfiles() { owner.refreshed++; }, readKillSwitch() {} });
        method(owner, "readDetails");
        method(owner, "refresh");
        method(owner, "listed");
        owner.queueAddress = () => {};
        owner.autoConnect = () => {};
        owner.addresses = {};
        return owner;
    };
    // Opening a view leases faster list reads; it must retain failures the
    // last connect learned. Explicit refresh owns their invalidation.
    for (const kind of ["needs-password", "sign-in", "plugin-needed", "password-tried", "failed"]) {
        const leased = detailOwner();
        leased.leases = {};
        leased.failures = { [BRANCH]: { kind, service: "vpnc" } };
        method(leased, "lease");
        assert.equal(leased.lease(JSON.stringify({ id: "view", open: true })), "ok");
        assert.deepEqual(plain(leased.leases), { view: true });
        assert.deepEqual(plain(leased.failures), { [BRANCH]: { kind, service: "vpnc" } });
        assert.deepEqual([leased.refreshed, leased.starts, leased.detailsRead], [1, 0, key]);
        assert.equal(leased.lease(JSON.stringify({ id: "view", open: false })), "ok");
        assert.deepEqual(plain(leased.leases), {});
        assert.equal(leased.refreshed, 1);
    }
    const finishDetails = new Function("root", "Logic", "detailsText", "detailsDeadline", "console", "reader",
        "with (reader) {" + bodyOf("detailsReader", "details") + "}");
    const edited = detailOwner(true);
    assert.equal(edited.refresh(), "ok");
    assert.deepEqual([edited.detailsReader.again, edited.starts, edited.refreshed], [true, 0, 1]);
    assert.equal(edited.failures[BRANCH], undefined);
    assert.equal(edited.failures[LAB], undefined);
    assert.equal(edited.failures[CAMPUS].kind, "password-tried");
    edited.detailsReader.running = false;
    finishDetails(edited, logic, { text: text("details.txt") }, edited.detailsDeadline, logs(), edited.detailsReader);
    assert.deepEqual([edited.starts, edited.detailsReader.running, edited.detailsReader.again], [1, true, false]);
    assert.deepEqual(plain(edited.detailsReader.command), plain(logic.detailsArgv(key)));
    edited.detailsReader.running = false;
    edited.detailsReader.completion = { code: 0, status: 0 };
    finishDetails(edited, logic, { text: text("details.txt").replace("vpn.example.com", "edited.example.com") },
        edited.detailsDeadline, logs(), edited.detailsReader);
    assert.equal(edited.detailMap[OFFICE].server, "edited.example.com");
    assert.equal(edited.detailsRead, key);
    edited.detailsReader.completion = { code: 10, status: 0 };
    finishDetails(edited, logic, { text: "" }, edited.detailsDeadline, logs(), edited.detailsReader);
    assert.equal(edited.detailsRead, "");
    edited.listed(listing);
    assert.deepEqual([edited.starts, edited.detailsReader.running], [2, true]);
    for (const missing of [false, true]) {
        const unavailable = detailOwner();
        unavailable.registered = missing;
        unavailable.profilesMissing = missing;
        unavailable.readDetails();
        assert.deepEqual([unavailable.starts, unavailable.detailsReader.running], [0, false]);
    }
    // A problem line describes a listed profile in the state its action
    // left; a disconnect's line goes once the profile is down.
    const down = (state) => [{ uuid: HOME, name: "Home tunnel", type: "wireguard", state }];
    for (const [name, problem, rows, failures, kept] of [
        ["no problem", null, listing.rows, {}, false],
        ["a connect with its failure", { uuid: OFFICE, kind: "profile-up", text: "x" }, listing.rows, { [OFFICE]: { kind: "failed", service: "" } }, true],
        ["a connect without its failure", { uuid: OFFICE, kind: "profile-up", text: "x" }, listing.rows, {}, false],
        ["a removal still listed", { uuid: OFFICE, kind: "profile-remove", text: "x" }, listing.rows, {}, true],
        ["an unlisted profile", { uuid: OFFICE, kind: "profile-remove", text: "x" }, [], {}, false],
        ["a disconnect still up", { uuid: HOME, kind: "profile-down", text: "x" }, down("activated"), {}, true],
        ["a disconnect still going down", { uuid: HOME, kind: "profile-down", text: "x" }, down("deactivating"), {}, true],
        ["a disconnect now down", { uuid: HOME, kind: "profile-down", text: "x" }, down(""), {}, false]
    ])
        assert.equal(logic.problemAfter(problem, rows, failures) === problem && problem !== null, kept, name);

    // Execute the production Import callback with private capability doubles.
    const importBody = /function importFile\(\) \{([\s\S]*?)\n    \}/.exec(service);
    assert.ok(importBody);
    const importRun = new Function("profiles", "shell", "root", importBody[1]);
    // A shown notice answers the press and opens the import once it installs.
    for (const [state, missing, offerAnswer, refusal, offered, launched] of [
        ["available", [], "ok", undefined, [], 1],
        ["available", ["gum"], "ok", undefined, [[["gum"], "import"]], 0],
        ["available", ["nmcli", "gum"], "ok", undefined, [[["nmcli", "gum"], "import"]], 0],
        ["available", ["gum"], "refused: notices=full limit=8", "refused: import=missing-tool", [[["gum"], "import"]], 0],
        ["not-running", [], "ok", "refused: import=unavailable", [], 0]
    ]) {
        const offers = [], launches = [];
        let refreshed = 0;
        const answer = importRun({ state }, { requirements: { missing, offer(commands, tui) { offers.push([plain(commands), tui]); return offerAnswer; } },
            tui: { run(name, args, done) { launches.push([name, args]); done(); return "ok"; } } }, { readProfiles() { refreshed++; } });
        assert.equal(answer, refusal === undefined ? "ok" : refusal);
        assert.deepEqual(offers, offered);
        assert.equal(launches.length, launched);
        assert.equal(refreshed, launched);
        if (launched) assert.deepEqual(launches[0], ["import", []]);
    }
    // The import offers every tool its TUI requires.
    assert.deepEqual(manifest.tui.import.requires.slice().sort(), ["gum", "nmcli"]);

    // Publish bounded profile lists through the production service callback.
    assert.equal(logic.line("a<b>\u0007c\n"), "ab>c");
    const publishBody = /function publish\(\) \{([\s\S]*?)\n    \}\n    onConnectionChanged/.exec(service);
    assert.ok(publishBody);
    const publish = new Function("shell", "connection", "profiles", "Logic", "killSwitch", "killSetup", publishBody[1]);
    const wide = Array.from({ length: 100 }, (_, i) => "界".repeat(80) + i + ":" + String(i).padStart(8, "0") + "-0000-4000-8000-000000000000:vpn:activated").join("\n");
    const wideListing = logic.list(0, wide);
    const wideDetails = {};
    for (const row of wideListing.rows) wideDetails[row.uuid] = { service: "openvpn", server: "界".repeat(logic.SERVER_MAX) };
    const crowded = plain(logic.compose(wideListing, wideDetails, {}, {}, { kind: "profile-up", uuid: wideListing.rows[0].uuid, name: "界".repeat(logic.TEXT_MAX) }, "界".repeat(200)));
    let values = {};
    const shell = { status: { isOk: core.statusReplyOk, set(key, value) {
        const result = core.statusWrite(manifest, values, key, value);
        assert.equal(result.ok, true, key + ": " + result.error);
        values = plain(result.values);
        assert.ok(Buffer.byteLength(JSON.stringify(values)) <= STATUS_MAX_BYTES);
        return "ok";
    } } };
    for (const payload of [profiles, crowded, plain(logic.compose(logic.emptyProfiles("missing"), {}, {}, {}, null, ""))]) {
        const original = JSON.stringify(payload);
        publish(shell, logic.connection(payload), payload, logic, logic.killSwitchState(undefined, { kind: "reading" }, null, false, ""), undefined);
        assert.equal(JSON.stringify(payload), original);
        assert.equal(values.profiles.count, payload.count);
        assert.equal(values.profiles.activeCount, payload.activeCount);
        assert.ok(values.profiles.rows.length > 0 || payload.rows.length === 0);
        for (const row of values.profiles.rows) assert.deepEqual(row, payload.rows.find(input => input.uuid === row.uuid));
        assert.equal(logic.barView(values.profiles).shown, payload.state === "available" && payload.count > 0);
        if (payload === crowded) {
            assert.ok(values.profiles.rows.length < crowded.rows.length, "a list over the status budget drops rows");
            assert.ok(Buffer.byteLength(JSON.stringify(values.profiles)) <= logic.STATUS_DATA_BYTES);
        }
    }
    // The kill switch's entries publish through the same callback, the
    // Setup entry only once the step's first probe answered.
    // Each entry as [tone, action offered, available], or undefined.
    for (const [step, setup] of [[undefined, undefined], [{ state: "needed", reason: "not-set-up" }, ["warning", true, true]],
        [{ state: "ready", reason: "granted" }, ["ok", false, true]], [{ state: "denied", reason: "nixos-unsupported" }, ["warning", false, false]],
        [{ state: "unknown", reason: "system-undetected" }, ["warning", false, false]]]) {
        values = {};
        const state = logic.killSwitchState(step, { kind: "valid", meantOn: HOME, mode: "block-lan", portalUntil: "0" },
            logic.killStatus(0, "state=passing reason=tunnel-up blocked=7 tunnel=wg0 profile=" + HOME + "\n"), false, "");
        publish(shell, logic.connection(profiles), profiles, logic, state, logic.killSwitchSetup(step));
        assert.deepEqual(values.killSwitchState, plain(state));
        const entry = values.killSwitch;
        assert.deepEqual(entry === undefined ? undefined : [entry.tone, entry.action === true, entry.available !== false], setup, JSON.stringify(step));
    }
    killSwitchSuite(logic, service, profiles);
    autoConnectSuite(logic, service);
}

// The kill switch's state file, status line and row (D129), and the
// service's writes around a profile change: the file names the profile
// before nmcli runs, a connect with the switch on runs only once the
// status read reports the table armed, and a profile the root half cannot
// use, or a table that does not arm within ARM_WAIT_MS, puts the file's
// profile back and runs nothing.
function killSwitchSuite(logic, service, profiles) {
    const file = (meantOn, mode, portalUntil = "0") => ({ kind: "valid", meantOn, mode, portalUntil });
    const textOf = (meantOn, mode, portalUntil = "0") => "version=1\nmeant-on=" + meantOn + "\nkill-switch=" + mode + "\nportal-until=" + portalUntil + "\n";
    // The grammar the root script's parse_state reads; STATE_TABLE holds
    // the same texts, which the differential below hands the shipped script.
    for (const [name, input, read] of STATE_TABLE) assert.deepEqual(plain(logic.readState(input)), read, name);
    for (const [meantOn, mode, portal] of [["", "off", "0"], [HOME, "block", "1794203888"], [OFFICE, "block-lan", "0"]])
        assert.deepEqual(plain(logic.readState(logic.stateText(file(meantOn, mode, portal)))), file(meantOn, mode, portal));
    // A change keeps every key it does not set, the portal time included.
    for (const [name, before, patch, after] of [
        ["a connect keeps the mode and the portal time", file("", "block-lan", "1794203888"), { meantOn: HOME }, textOf(HOME, "block-lan", "1794203888")],
        ["a mode change keeps the profile", file(HOME, "block", "0"), { mode: "off" }, textOf(HOME, "off")],
        ["a disconnect clears the profile alone", file(HOME, "block", "1794203888"), { meantOn: "" }, textOf("", "block", "1794203888")],
        ["a missing file reads as off", { kind: "missing" }, { meantOn: HOME }, textOf(HOME, "off")],
        ["a missing file takes the mode", { kind: "missing" }, { mode: "block" }, textOf("", "block")],
        ["a malformed file fails closed", { kind: "malformed" }, { meantOn: HOME }, textOf(HOME, "block")],
        ["an unread file is not written", { kind: "reading" }, { mode: "off" }, null],
        ["an unreadable file is not written", { kind: "unreadable" }, { mode: "off" }, null]
    ]) assert.equal(logic.stateChange(before, patch), after, name);
    // What a profile change writes first.
    for (const [name, kind, uuid, ready, before, type, plan] of [
        ["no step, no write", "profile-up", HOME, false, file("", "block"), "wireguard", null],
        ["a connect names its profile and waits with the switch on", "profile-up", HOME, true, file(OFFICE, "block"), "wireguard", { patch: { meantOn: HOME }, arm: true, previous: OFFICE }],
        ["a connect with local network waits too", "profile-up", HOME, true, file("", "block-lan"), "wireguard", { patch: { meantOn: HOME }, arm: true, previous: "" }],
        ["a connect with the switch off waits for nothing", "profile-up", HOME, true, file("", "off"), "wireguard", { patch: { meantOn: HOME }, arm: false, previous: "" }],
        ["a connect over no file waits for nothing", "profile-up", HOME, true, { kind: "missing" }, "wireguard", { patch: { meantOn: HOME }, arm: false, previous: "" }],
        ["a connect over a malformed file waits", "profile-up", HOME, true, { kind: "malformed" }, "wireguard", { patch: { meantOn: HOME }, arm: true, previous: "" }],
        ["the switch on refuses a profile that is not WireGuard", "profile-up", OFFICE, true, file("", "block"), "vpn", { refuse: "profile-not-wireguard" }],
        ["local network refuses it too", "profile-up", OFFICE, true, file("", "block-lan"), "vpn", { refuse: "profile-not-wireguard" }],
        ["a malformed file refuses it, as it fails closed", "profile-up", OFFICE, true, { kind: "malformed" }, "vpn", { refuse: "profile-not-wireguard" }],
        ["the switch off lets it connect", "profile-up", OFFICE, true, file("", "off"), "vpn", { patch: { meantOn: OFFICE }, arm: false, previous: "" }],
        ["a disconnect of the named profile clears it", "profile-down", HOME, true, file(HOME.toUpperCase(), "block"), "wireguard", { patch: { meantOn: "" }, arm: false, previous: HOME }],
        ["a remove of the named profile clears it", "profile-remove", HOME, true, file(HOME, "off"), "wireguard", { patch: { meantOn: "" }, arm: false, previous: HOME }],
        ["a disconnect over a malformed file writes the off", "profile-down", HOME, true, { kind: "malformed" }, "wireguard", { patch: { meantOn: "" }, arm: false, previous: "" }],
        ["a remove over a malformed file writes the off", "profile-remove", OFFICE, true, { kind: "malformed" }, "vpn", { patch: { meantOn: "" }, arm: false, previous: "" }],
        ["a disconnect of another profile writes nothing", "profile-down", OFFICE, true, file(HOME, "block"), "vpn", null],
        ["a remove of another profile writes nothing", "profile-remove", OFFICE, true, file(HOME, "block"), "vpn", null],
        ["details write nothing", "profile-details", HOME, true, file(HOME, "block"), "wireguard", null],
        ["an unreadable file plans a write for a connect", "profile-up", HOME, true, { kind: "unreadable" }, "wireguard", { patch: { meantOn: HOME }, arm: true, previous: "" }],
        ["an unread file plans a write for a disconnect", "profile-down", HOME, true, { kind: "reading" }, "wireguard", { patch: { meantOn: "" }, arm: true, previous: "" }]
    ]) assert.deepEqual(plain(logic.meantOnPlan(kind, uuid, ready, before, type)), plan, name);
    // A malformed file's off is what `vgs-kill-switch off` writes.
    assert.equal(logic.stateChange({ kind: "malformed" }, logic.meantOnPlan("profile-down", HOME, true, { kind: "malformed" }, "wireguard").patch), textOf("", "block"));
    // The status line, as STATUS_TABLE holds it; the differential below
    // hands each accepted or refused line to the root's status_pattern.
    for (const [code, line, read] of STATUS_TABLE) {
        const got = plain(logic.killStatus(code, line));
        assert.deepEqual(read === "unreachable" ? got.state : got, read, JSON.stringify([code, line]));
    }
    for (const [code, errors, state] of [
        [1, "vgs-kill-switch: refused: status=unreachable path=/run/vgs-kill-switch.sock\n", "unreachable"],
        [1, "vgs-kill-switch: refused: status=unreadable path=/run/vgs-kill-switch.sock\nthe status read gave no status line\n", "unreadable"],
        [1, "noise\nvgs-kill-switch: refused: status=unreadable path=/run/vgs-kill-switch.sock\n", "unreachable"],
        [-1, "vgs-kill-switch: refused: status=unreadable path=x\n", "unreachable"],
        [0, "vgs-kill-switch: refused: status=unreadable path=x\n", "unreachable"]
    ]) assert.equal(logic.killStatus(code, "", errors).state, state, errors);
    // Only a line naming the profile just written answers the wait.
    const line = (state, reason, profile, tunnel = "") => logic.killStatus(0, "state=" + state + " reason=" + reason + " blocked=3 tunnel=" + tunnel + " profile=" + profile + "\n");
    for (const [name, status, outcome] of [
        ["its own passing", line("passing", "tunnel-up", HOME, "wg0"), "armed"],
        ["its own holding", line("holding", "tunnel-down", HOME, "wg0"), "armed"],
        ["its own holding in upper case", line("holding", "tunnel-down", HOME.toUpperCase(), "wg0"), "armed"],
        ["its own refusal", line("unavailable", "endpoint-hostname", HOME), "unavailable"],
        ["its own table with a device it cannot judge", line("unavailable", "device-uncovered", HOME, "wg0"), "armed"],
        ["the previous profile's device it cannot judge", line("unavailable", "device-uncovered", OFFICE, "wg1"), "waiting"],
        ["the previous profile's passing", line("passing", "tunnel-up", OFFICE, "wg1"), "waiting"],
        ["the previous profile's refusal", line("unavailable", "profile-missing", OFFICE), "waiting"],
        ["a sync between cache and table", line("unavailable", "cache-unreadable", ""), "waiting"],
        ["off", line("off", "disarmed", ""), "waiting"],
        ["unreachable", logic.killStatus(1, ""), "failed"],
        ["unreadable", logic.killStatus(1, "", "vgs-kill-switch: refused: status=unreadable path=x"), "failed"],
        ["no read yet", null, "waiting"]
    ]) assert.equal(logic.armOutcome(status === null ? null : plain(status), HOME), outcome, name);

    // The row's states.
    const named = { rows: [{ uuid: HOME, name: "Home tunnel", state: "activated" }, { uuid: OFFICE, name: "Office VPN", state: "" }] };
    const ready = { state: "ready", reason: "granted" };
    const status = (state, reason = "tunnel-up", profile = HOME) => line(state, reason, profile, "wg0");
    const row = (step, kill, read, busy = false, problem = "", settling = false) => plain(logic.killSwitchView(plain(logic.killSwitchState(step, kill, read, busy, problem, settling)), named));
    const pick = view => [view.shown, view.setup, view.switchOn, view.lanShown, view.lanOn, view.reason !== "", view.tone];
    for (const [name, view, shape] of [
        ["nothing published hides the row", plain(logic.killSwitchView(undefined, named)), [false, false, false, false, false, false, ""]],
        ["an absent step hides the row", row({ state: "absent", reason: "x" }, { kind: "reading" }, null), [false, false, false, false, false, false, ""]],
        ["before the probe the switch waits", row(undefined, { kind: "reading" }, null), [true, false, false, false, false, true, ""]],
        ["a step to apply shows Set up", row({ state: "needed", reason: "not-set-up" }, { kind: "reading" }, null), [true, true, false, false, false, false, ""]],
        ["NixOS's snippet shows Set up", row({ state: "nixos", reason: "nixos" }, { kind: "reading" }, null), [true, true, false, false, false, false, ""]],
        ["a denied step says why", row({ state: "denied", reason: "other-account" }, { kind: "reading" }, null), [true, false, false, false, false, true, ""]],
        ["an unknown step says why", row({ state: "unknown", reason: "system-undetected" }, { kind: "reading" }, null), [true, false, false, false, false, true, ""]],
        ["an unread file waits", row(ready, { kind: "reading" }, null), [true, false, false, false, false, true, ""]],
        ["an unreadable file says so", row(ready, { kind: "unreadable" }, null), [true, false, false, false, false, true, "danger"]],
        ["no file is off", row(ready, { kind: "missing" }, status("off", "disarmed", "")), [true, false, false, false, false, false, ""]],
        ["off", row(ready, file("", "off"), status("off", "disarmed", "")), [true, false, false, false, false, false, ""]],
        ["block", row(ready, file(HOME, "block"), status("passing")), [true, false, true, true, false, false, ""]],
        ["block with local network", row(ready, file(HOME, "block-lan"), status("passing")), [true, false, true, true, true, false, ""]],
        ["a write in flight disables both", row(ready, file(HOME, "block"), status("passing"), true), [true, false, true, true, false, true, ""]],
        ["a failed write says so", row(ready, file(HOME, "block"), status("passing"), false, "VGS could not save the kill switch setting."), [true, false, true, true, false, false, "danger"]],
        ["a malformed file reads off and says so", row(ready, { kind: "malformed" }, status("off", "disarmed", "")), [true, false, false, false, false, false, "danger"]],
        ["an unsupported profile says so", row(ready, file(OFFICE, "block"), status("unavailable", "profile-not-wireguard", OFFICE)), [true, false, true, true, false, false, "danger"]],
        ["holding is no danger line here", row(ready, file(HOME, "block"), status("holding", "tunnel-down")), [true, false, true, true, false, false, ""]],
        ["an unreachable status is plain", row(ready, file(HOME, "block"), logic.killStatus(1, "")), [true, false, true, true, false, false, ""]],
        ["an unreadable status is plain", row(ready, file(HOME, "block"), logic.killStatus(1, "", "vgs-kill-switch: refused: status=unreadable path=x")), [true, false, true, true, false, false, ""]],
        ["on with no profile named and no rule is calm", row(ready, file("", "block"), status("off", "disarmed", "")), [true, false, true, true, false, false, ""]],
        ["on, naming a profile, with no rule is danger", row(ready, file(HOME, "block"), status("off", "disarmed", "")), [true, false, true, true, false, false, "danger"]],
        ["no rule while a write runs is not yet danger", row(ready, file(HOME, "block"), status("off", "disarmed", ""), true), [true, false, true, true, false, true, ""]],
        ["no rule in a write's grace is not yet danger", row(ready, file(HOME, "block"), status("off", "disarmed", ""), false, "", true), [true, false, true, true, false, false, ""]],
        ["no rule for a profile not connected is not danger", row(ready, file(OFFICE, "block"), status("off", "disarmed", "")), [true, false, true, true, false, false, ""]]
    ]) assert.deepEqual(pick(view), shape, name);
    // Naming a profile with no rule makes no claim while a write runs, in
    // its grace, or while the profile is not connected: no line says it
    // starts later or that it blocks.
    for (const [name, view] of [["a write runs", row(ready, file(HOME, "block"), status("off", "disarmed", ""), true)],
        ["the grace", row(ready, file(HOME, "block"), status("off", "disarmed", ""), false, "", true)],
        ["not connected", row(ready, file(OFFICE, "block"), status("off", "disarmed", ""))]])
        assert.equal(view.hint, "", name);
    assert.notEqual(row(ready, file("", "block"), status("off", "disarmed", "")).hint, "", "with no profile named the line says when it starts");
    // The lines name the profile the file names, and each reason the root
    // half reports has its own sentence.
    assert.ok(row(ready, file(OFFICE, "block"), status("unavailable", "profile-not-wireguard", OFFICE)).hint.includes("Office VPN"));
    assert.ok(row(ready, file(HOME, "block"), status("passing")).hint.includes("Home tunnel"));
    assert.ok(row(ready, file(HOME, "block"), status("off", "disarmed", "")).hint.includes("Home tunnel"));
    const reasons = ["profile-not-wireguard", "profile-missing", "profile-unread", "interface-invalid", "endpoint-hostname", "endpoint-invalid", "cache-unreadable", "device-uncovered"];
    assert.equal(new Set(reasons.map(reason => logic.unavailableWords(reason, "P"))).size, reasons.length - 1, "profile-unread and cache-unreadable share one sentence");
    for (const reason of reasons) assert.notEqual(logic.unavailableWords(reason, "P"), logic.unavailableWords("unknown-reason", "P"), reason);
    assert.equal(row(ready, file(HOME, "block"), logic.killStatus(1, "")).hint,
        row(ready, file(HOME, "block"), logic.killStatus(1, "", "vgs-kill-switch: refused: status=unreadable path=x")).hint, "unreachable and unreadable read as one");
    assert.notEqual(row(ready, file(HOME, "block"), logic.killStatus(1, "")).hint, "", "a failed status read says so");
    // The blocked-traffic notice shows only while the status read says
    // holding for the profile the file names with the switch on, and that
    // profile is not connected, connecting or changing: holding is also
    // a connect's state between the table arming and its tunnel coming up.
    // It offers the disconnect only for a listed profile.
    const droppedRows = { rows: [{ uuid: HOME, name: "Home tunnel", state: "" }, { uuid: OFFICE, name: "Office VPN", state: "" }], action: null };
    const homeAs = (state, action = null) => ({ rows: [Object.assign({}, droppedRows.rows[0], { state }), droppedRows.rows[1]], action });
    const notice = (step, kill, read, rows = droppedRows) => plain(logic.blockedNotice(plain(logic.killSwitchState(step, kill, read, false, "", false)), rows));
    const holding = status("holding", "tunnel-down");
    for (const [name, got, uuid] of [
        ["holding for a listed profile", notice(ready, file(HOME, "block"), holding), HOME],
        ["holding with local network", notice(ready, file(HOME, "block-lan"), holding), HOME],
        ["an upper-case uuid in the file", notice(ready, file(HOME.toUpperCase(), "block"), holding), HOME],
        ["holding for a profile no longer listed", notice(ready, file(LAB, "block"), status("holding", "tunnel-down", LAB)), ""],
        ["holding while NetworkManager lists nothing", notice(ready, file(HOME, "block"), holding, { rows: [] }), ""],
        ["holding while the named profile is connecting", notice(ready, file(HOME, "block"), holding, homeAs("activating")), null],
        ["holding while VGS connects the named profile", notice(ready, file(HOME, "block"), holding, homeAs("", { kind: "profile-up", uuid: HOME })), null],
        ["holding while Turn VPN off runs", notice(ready, file(HOME, "block"), holding, homeAs("", { kind: "profile-down", uuid: HOME })), null],
        ["holding while the named profile reads connected", notice(ready, file(HOME, "block"), holding, homeAs("activated")), null],
        ["holding while the named profile disconnects", notice(ready, file(HOME, "block"), holding, homeAs("deactivating")), null],
        ["a holding line naming another profile", notice(ready, file(HOME, "block"), status("holding", "tunnel-down", OFFICE)), null],
        ["a holding line naming no profile", notice(ready, file(HOME, "block"), status("holding", "tunnel-down", "")), null],
        ["passing", notice(ready, file(HOME, "block"), status("passing")), null],
        ["off", notice(ready, file(HOME, "block"), status("off", "disarmed", "")), null],
        ["unavailable", notice(ready, file(OFFICE, "block"), status("unavailable", "profile-not-wireguard", OFFICE)), null],
        ["an unreachable status read", notice(ready, file(HOME, "block"), logic.killStatus(1, "")), null],
        ["no status read yet", notice(ready, file(HOME, "block"), null), null],
        ["a holding line after the switch went off", notice(ready, file(HOME, "off"), holding), null],
        ["a holding line after the file's profile was cleared", notice(ready, file("", "block"), holding), null],
        ["a holding line naming no profile after the file's was cleared", notice(ready, file("", "block"), status("holding", "tunnel-down", "")), null],
        ["a malformed file", notice(ready, { kind: "malformed" }, holding), null],
        ["a step that reads needed", notice({ state: "needed", reason: "units-failed" }, file(HOME, "block"), holding), null],
        ["nothing published", plain(logic.blockedNotice(undefined, droppedRows)), null]
    ]) assert.deepEqual(got === null ? null : got.uuid, uuid, name);
    const heldNotice = notice(ready, file(HOME, "block"), holding);
    const unlistedNotice = notice(ready, file(LAB, "block"), status("holding", "tunnel-down", LAB));
    assert.ok(unlistedNotice.text !== "" && unlistedNotice.text !== heldNotice.text, "an unlisted profile's notice names its own way out");
    // Beside the notice the kill switch row's line is the refused count,
    // singular for one, with the switch's info saying what it counts; in
    // any other reading the line carries no count and no info.
    const countView = (blocked, rows = droppedRows) => plain(logic.killSwitchView(plain(logic.killSwitchState(ready, file(HOME, "block"),
        logic.killStatus(0, "state=holding reason=tunnel-down blocked=" + blocked + " tunnel= profile=" + HOME + "\n"), false, "", false)), rows));
    const once = countView("1");
    const many = countView("214");
    assert.ok(once.hint.includes(" 1 ") && many.hint.includes(" 214 "), "the line carries the count");
    assert.notEqual(once.hint.replace(" 1 ", " N "), many.hint.replace(" 214 ", " N "), "one refusal reads singular");
    assert.ok(once.countInfo !== "" && many.countInfo === once.countInfo, "the count carries its info");
    assert.deepEqual([once.tone, many.tone], ["", ""]);
    assert.ok(!heldNotice.text.includes(many.hint), "the row's line does not repeat the notice");
    for (const [name, view] of [
        ["holding while the named profile connects", countView("214", homeAs("activating"))],
        ["passing", plain(logic.killSwitchView(plain(logic.killSwitchState(ready, file(HOME, "block"), status("passing"), false, "", false)), droppedRows))],
        ["off", plain(logic.killSwitchView(plain(logic.killSwitchState(ready, file("", "block"), status("off", "disarmed", ""), false, "", false)), droppedRows))]
    ]) {
        assert.equal(view.countInfo, "", name);
        assert.ok(!view.hint.includes("214"), name);
    }
    // Its button is the profile's disconnect: for a profile NetworkManager
    // already dropped, the state file's write alone; any other profile
    // that is not connected still refuses it.
    const dropped = Object.assign({}, profiles, { rows: profiles.rows.map(entry => entry.uuid === HOME ? Object.assign({}, entry, { state: "" }) : entry) });
    for (const [name, uuid, meantOn, plan] of [
        ["the dropped profile the file names", HOME, HOME, { argv: null }],
        ["the file names it in upper case", HOME, HOME.toUpperCase(), { argv: null }],
        ["the file names another profile", HOME, OFFICE, { refusal: "refused: profile=state" }],
        ["the file names none", HOME, "", { refusal: "refused: profile=state" }],
        ["no kill switch", HOME, undefined, { refusal: "refused: profile=state" }],
        ["another profile that is not connected", OFFICE, HOME, { refusal: "refused: profile=state" }]
    ]) assert.deepEqual(plain(logic.profileCommand({ kind: "profile-down", id: uuid }, dropped, [], true, meantOn)), plan, name);
    assert.deepEqual(plain(logic.profileCommand({ kind: "profile-down", id: HOME }, profiles, [], true, HOME)), { argv: ["nmcli", "connection", "down", "uuid", HOME] },
        "a connected profile the file names takes nmcli down");
    // The profile the notice names reads Dropped with its switch on, so
    // the switch turns it off; a change in flight still shows as one. The
    // flyout header and the status entry name it dropped, not off.
    const homeDropped = dropped.rows.find(entry => entry.uuid === HOME);
    const heldRow = plain(logic.rowView(homeDropped, dropped, [], true, HOME));
    assert.deepEqual([heldRow.key, heldRow.switchOn, heldRow.connected, heldRow.busy, heldRow.reason, heldRow.reconnect], ["dropped", true, false, false, "", true]);
    assert.equal(logic.rowView(homeDropped, dropped, [], true, "").reconnect, false, "Reconnect only for a held profile");
    // Reconnect sends profile-up for the held profile: it plans nmcli up,
    // its write keeps the file naming it, so the block never lifts, and
    // the table it waits for is already armed for it.
    assert.deepEqual(plain(logic.profileCommand({ kind: "profile-up", id: HOME }, dropped, [], true, HOME)), { argv: ["nmcli", "connection", "up", "uuid", HOME] });
    assert.deepEqual(plain(logic.meantOnPlan("profile-up", HOME, true, file(HOME, "block"), "wireguard")), { patch: { meantOn: HOME }, arm: true, previous: HOME },
        "Reconnect keeps meant-on and waits for the table");
    assert.equal(logic.armOutcome(plain(holding), HOME), "armed", "the holding line for the profile answers the wait");
    assert.equal(logic.rowView(homeDropped, dropped, [], true, "").key, "off", "no notice, no Dropped");
    assert.equal(logic.rowView(homeDropped, dropped, [], true, OFFICE).key, "off", "only the named profile reads Dropped");
    assert.equal(logic.rowView(homeDropped, Object.assign({}, dropped, { action: { kind: "profile-down", uuid: HOME } }), [], true, HOME).key, "disconnecting");
    const noticeFor = uuid => ({ uuid, text: "" });
    assert.notEqual(logic.summary(dropped, noticeFor(HOME)), logic.summary(dropped, null), "the header does not read off");
    assert.ok(logic.summary(dropped, noticeFor(HOME)).includes("Home tunnel"), "the header names the dropped profile");
    assert.equal(logic.connection(dropped, noticeFor(HOME)).text, logic.summary(dropped, noticeFor(HOME)), "the status entry reads as the header");
    // The bar's tooltip reads the drop as the header does, not off; with
    // no notice it reads as before.
    const barRows = { state: "available", count: 2, activeCount: 0, action: null,
        rows: [{ uuid: HOME, name: "Home tunnel", state: "", failure: "" }, { uuid: OFFICE, name: "Office VPN", state: "", failure: "" }] };
    const droppedBar = plain(logic.barView(barRows, noticeFor(HOME)));
    assert.equal(droppedBar.tooltip, "VPN: " + logic.summary(barRows, noticeFor(HOME)), "the bar tooltip reads as the header");
    assert.notEqual(droppedBar.tooltip, plain(logic.barView(barRows, null)).tooltip, "the bar tooltip does not read off");
    assert.equal(plain(logic.barView(barRows)).tooltip, "VPN: " + logic.summary(barRows));
    // A held drop puts the danger dot on the bar whatever icon shows, and
    // reads danger in the Details Connection reading, with another profile
    // up outside VGS too.
    const otherUp = Object.assign({}, barRows, { activeCount: 1, rows: [barRows.rows[0], Object.assign({}, barRows.rows[1], { state: "activated" })] });
    const otherConnecting = Object.assign({}, barRows, { action: { kind: "profile-up", uuid: OFFICE, name: "Office VPN", password: false } });
    // A notice for a profile no longer listed reads the drop too.
    for (const [name, rows, icon] of [["no other profile", barRows, "shield-off"], ["another profile up", otherUp, "shield-check"], ["another profile connecting", otherConnecting, "shield"]]) {
        for (const [whose, notice] of [["listed", noticeFor(HOME)], ["unlisted", noticeFor("")]]) {
            const held = plain(logic.barView(rows, notice));
            assert.deepEqual([held.icon, held.stateDot], [icon, "danger"], name + " " + whose);
            assert.equal(logic.connection(rows, notice).tone, "danger", name + " " + whose);
            // A connect in progress reads first in the line; the dot and
            // the tone still mark the drop.
            if (icon !== "shield") {
                assert.notEqual(logic.summary(rows, notice), logic.summary(rows, null), name + " " + whose + ": the line reads the drop");
                assert.equal(held.tooltip, "VPN: " + logic.summary(rows, notice), name + " " + whose);
            } else assert.equal(logic.summary(rows, notice), logic.summary(rows, null), name + " " + whose + ": the line reads the connect");
        }
        assert.equal(plain(logic.barView(rows, null)).stateDot, "", name + ": no dot without a drop");
        assert.notEqual(logic.connection(rows, null).tone, "danger", name + ": no danger without a drop");
    }
    assert.ok(!logic.summary(barRows, noticeFor("")).includes("Home tunnel"), "an unlisted drop names no listed profile");
    // A Reconnect under the block: held, then in flight. Its notice is
    // null while it moves, and the header, Details and the bar's tooltip
    // read the connect as one line, not off.
    const holdingFor = rows => logic.blockedNotice(plain(logic.killSwitchState(ready, file(HOME, "block"), holding, false, "", false)), rows);
    assert.equal(holdingFor(barRows).uuid, HOME, "held before the Reconnect");
    const reconnecting = Object.assign({}, barRows, { action: { kind: "profile-up", uuid: HOME, name: "Home tunnel", password: false } });
    const reconnectNotice = holdingFor(reconnecting);
    assert.equal(reconnectNotice, null, "no notice while the Reconnect runs");
    const reconnectLine = logic.summary(reconnecting, reconnectNotice);
    assert.notEqual(reconnectLine, logic.summary(barRows, null), "the line does not read off while the Reconnect runs");
    assert.ok(reconnectLine.includes("Home tunnel"), "the line names the profile connecting");
    assert.equal(logic.connection(reconnecting, reconnectNotice).text, reconnectLine, "Details reads as the header");
    assert.equal(plain(logic.barView(reconnecting, reconnectNotice)).tooltip, "VPN: " + reconnectLine, "the bar's tooltip reads as the header");
    assert.equal(plain(logic.barView(null, noticeFor(HOME))).stateDot, "", "a hidden bar icon carries no dot");

    // Each cause leaves its own problem line, and an unrestored rollback
    // its own.
    const causes = [["write", ""], ["timeout", ""], ["unchecked", ""], ["unavailable", "endpoint-hostname"]].map(([cause, reason]) => logic.stageProblem("profile-up", "Home tunnel", cause, reason, false));
    assert.equal(new Set(causes).size, 4);
    assert.notEqual(causes[2], logic.stageProblem("profile-up", "Home tunnel", "unavailable", "", false), "a wait with no line has its own words");
    assert.notEqual(logic.stageProblem("profile-down", "Home tunnel", "write", "", false), causes[0]);
    assert.ok(causes.every(cause => cause !== logic.stageProblem("profile-up", "Home tunnel", "timeout", "", true)), "an unrestored rollback reads apart");

    // With the kill switch on, a profile that is not WireGuard cannot
    // connect: its switch says why, and its IPC connect is refused, while
    // a WireGuard profile and a profile already connected are unchanged.
    const kinds = { [HOME]: "wireguard", [OFFICE]: "vpn", [LAB]: "wireguard", [TRAVEL]: "vpn" };
    for (const listed of profiles.rows.filter(entry => kinds[entry.uuid] !== undefined)) {
        const off = logic.rowView(listed, profiles, [], false);
        const on = logic.rowView(listed, profiles, [], true);
        const blocked = listed.type !== "wireguard" && listed.state !== "activated";
        assert.equal(on.key === "kill-switch", blocked, listed.name);
        assert.equal(on.reason !== "", blocked || off.reason !== "", listed.name);
        if (!blocked) assert.deepEqual(plain(on), plain(off), listed.name);
        const plan = logic.profileCommand({ kind: "profile-up", id: listed.uuid }, profiles, [], true);
        if (blocked) assert.deepEqual(plain(plan), { refusal: "refused: profile=kill-switch" }, listed.name);
    }
    assert.deepEqual(plain(logic.passwordCommand(TRAVEL, profiles, [], true)), { refusal: "refused: profile=state" }, "no password connect past the kill switch");
    const campus = profiles.rows.find(entry => entry.uuid === CAMPUS);
    assert.equal(logic.rowView(campus, profiles, [], true).key, "unsupported", "a profile that connects in its own app keeps saying so");
    assert.equal(logic.killSwitchOn(plain(logic.killSwitchState(ready, file("", "block"), null, false, ""))), true);
    assert.equal(logic.killSwitchOn(plain(logic.killSwitchState(ready, file("", "block-lan"), null, false, ""))), true);
    assert.equal(logic.killSwitchOn(plain(logic.killSwitchState(ready, file("", "off"), null, false, ""))), false);
    assert.equal(logic.killSwitchOn(plain(logic.killSwitchState({ state: "needed", reason: "units-failed" }, file("", "block"), null, false, ""))), false);
    assert.equal(logic.killSwitchOn(undefined), false);

    // The service's own functions over doubles: `with` resolves bare names
    // on the owner, as QML does.
    const fnOf = name => {
        const found = new RegExp("function " + name + "\\(([^)]*)\\) \\{([\\s\\S]*?)\\n    \\}").exec(service);
        assert.ok(found, name);
        return found;
    };
    const bind = (owner, name) => {
        const found = fnOf(name);
        const params = found[1].split(",").map(param => param.trim()).filter(param => param !== "");
        owner[name] = new Function("Logic", "owner", ...params, "with (owner) {" + found[2] + "}").bind(null, logic, owner);
    };
    const UP = ["nmcli", "connection", "up", "uuid", HOME];
    const DOWN = ["nmcli", "connection", "down", "uuid", HOME];
    const LAB_UP = ["nmcli", "connection", "up", "uuid", LAB];
    // A service double whose writes and status reads land in EVENTS; its
    // file reads answer DISK. The rename lands the text on DISK unless
    // `lost`, as a rename another writer's rename overtook; `touchFails`
    // fails the pending file; `stall` names a step whose answer never
    // comes.
    const serviceOwner = (fields = {}) => {
        const events = [];
        const owner = Object.assign({
            events, disk: textOf("", "block"), lost: false, saveFails: false, stall: "",
            profiles, profileAction: null, profileProblem: null, connectFeed: null, killReady: true, killWritable: true, killFile: file("", "block"),
            autoMemory: { seen: "", pending: true, problem: null }, autoAction: "",
            killStep: { state: "ready", reason: "granted" }, probeStep: null,
            // The fresh probe answers at once, with probeStep when set.
            shell: { system: { refresh(done) {
                events.push("probe");
                if (owner.probeStep !== null) {
                    owner.killStep = owner.probeStep;
                    owner.killReady = owner.probeStep.state === "ready";
                }
                done();
                return "ok";
            } } },
            killStatus: null, stateWrite: null, stage: null, killChanging: false, killProblem: "", registered: true,
            killSettling: false, killSettlePoll: false, stateSerial: 0, killSwitch: null,
            profileActor: { running: false, stdinEnabled: false, command: [], completion: "old" },
            profileActionDeadline: { restart() {} },
            armDeadline: { restarted: 0, restart() { this.restarted++; }, stop() { events.push("arm-deadline-stop"); } },
            stateDeadline: { restarted: 0, stopped: 0, restart() { this.restarted++; }, stop() { this.stopped++; } },
            // The retry timer fires at once.
            armRetry: { restart() { events.push("retry"); owner.readKillStatus(); }, stop() {} },
            killReader: { running: false, again: false, completion: null, settles: false, forCheck: false }, checkWantsStatus: false,
            killDeadline: { restart() {} },
            readProfiles() { events.push("read-profiles"); }, readKillSwitch() { events.push("read-kill-switch"); },
            stateFile: {
                held: textOf("", "block"),
                text() { return this.held; },
                reload() {
                    events.push("reload");
                    if (owner.stall === "reload") return;
                    this.held = owner.disk;
                    owner.killFile = owner.disk === null ? { kind: "missing" } : logic.readState(owner.disk);
                    if (owner.stateWrite !== null) {
                        if (owner.disk === null && owner.stateWrite.phase === "read") owner.stateRead();
                        else if (owner.disk === null) owner.writeEnded(false);
                        else owner.stateRead();
                    }
                },
            },
            tempFile: {
                path: "",
                setText(text) {
                    events.push(["write", text], ["temp", this.path]);
                    if (owner.saveFails) { owner.tempSaveFailed(); return; }
                    owner.tempSaved();
                }
            },
            stateModer: { command: [], completion: "old", busy: false, signal(sig) { events.push(["signal", "chmod", sig]); },
                get running() { return this.busy; },
                set running(value) {
                    if (!value) return;
                    events.push(["chmod", this.command]);
                    if (owner.stall === "chmod") { this.busy = true; return; }
                    owner.moded(owner.modeFails ? 1 : 0, this.serial);
                } },
            stateMover: { command: [], completion: "old", signal(sig) { events.push(["signal", "mv", sig]); },
                get running() { return false; },
                set running(value) {
                    if (!value) return;
                    events.push(["mv", this.command]);
                    if (!owner.lost && !owner.moveFails) owner.disk = owner.stateWrite.text;
                    owner.renamed(owner.moveFails ? 1 : 0, this.serial);
                } },
            pendingMaker: { command: [], completion: "old", signal(sig) { events.push(["signal", "touch", sig]); },
                get running() { return false; },
                set running(value) {
                    if (!value) return;
                    events.push(["touch", this.command]);
                    owner.pendingMade(owner.touchFails ? 1 : 0, this.serial);
                } },
            tempRemover: { command: [], set running(value) { events.push(["rm", this.command]); } }
        }, fields);
        owner.root = owner;
        owner.Object = Object;
        owner.console = { warn(message) { events.push(["warn", message]); }, log() {} };
        for (const name of ["startAction", "launch", "staged", "armRead", "armExpired", "waitEnd", "probed", "rollBack", "stageEnded", "autoEnded", "setKillSwitch", "writeState", "stateRead",
            "writeEnded", "readKillStatus", "tempSaved", "tempSaveFailed", "moded", "renamed", "makePending", "removeTemp", "pendingMade", "stateExpired", "stateInterrupted"]) bind(owner, name);
        // Each status read ends at once with the next line of `lines`; a
        // `null` line leaves the read running.
        owner.lines = fields.lines || [];
        owner.readKillStatus = () => {
            const next = owner.lines.shift();
            events.push(["status", next === undefined ? "none" : next === null ? "running" : next.state]);
            if (next === undefined) return;
            if (next === null) { owner.killReader.running = true; return; }
            owner.killStatus = plain(next);
            if (owner.stage !== null && owner.stage.phase === "arm") owner.armRead();
        };
        const launch = owner.launch;
        owner.launch = argv => { events.push(["launch", argv]); launch(argv); };
        return owner;
    };
    const launched = owner => owner.events.filter(event => Array.isArray(event) && event[0] === "launch").map(event => event[1]);
    const writes = owner => owner.events.filter(event => Array.isArray(event) && event[0] === "write").map(event => event[1]);
    const order = owner => owner.events.filter(event => Array.isArray(event) && (event[0] === "write" || event[0] === "launch" || event[0] === "status")).map(event => event[0]);
    // Each write as the root script's header has it: a dot-prefixed file
    // in the state directory, its mode, the rename, then pending.
    const writeSteps = owner => owner.events.filter(event => Array.isArray(event) && ["temp", "chmod", "mv", "touch"].includes(event[0]));
    const ended = (owner, kind, name, cause, reason, unrestored) => {
        assert.deepEqual([owner.stage, owner.profileAction, owner.stateWrite], [null, null, null], cause);
        assert.deepEqual(plain(owner.profileProblem), { uuid: kind, kind: "kill-switch", text: logic.stageProblem("profile-up", name, cause, reason, unrestored) }, cause);
    };

    // Switch on: the file names the profile, the table arms for it, then
    // nmcli. A line from the previous profile, and a sync between cache
    // and table, do not answer.
    const armed = serviceOwner({ disk: textOf(OFFICE, "block"), lines: [status("passing", "tunnel-up", OFFICE), status("unavailable", "cache-unreadable", ""),
        status("holding", "tunnel-down")] });
    assert.equal(armed.startAction("profile-up", HOME, UP, null), "ok");
    assert.equal(armed.armDeadline.restarted, 1);
    assert.deepEqual(writes(armed), [textOf(HOME, "block")]);
    const steps = writeSteps(armed);
    assert.equal(steps.length, 4);
    assert.match(steps[0][1], new RegExp("^" + logic.STATE_DIR + "/\\.state\\.[A-Za-z0-9]{10}$"), "a dot-prefixed temporary file in the state directory");
    assert.deepEqual(steps[1], ["chmod", ["chmod", "0644", "--", steps[0][1]]], "mode 0644");
    assert.deepEqual(steps[2], ["mv", ["mv", "-fT", "--", steps[0][1], logic.STATE_FILE]], "renamed over the state file");
    assert.deepEqual(steps[3], ["touch", ["touch", "--", logic.STATE_DIR + "/pending"]], "then the pending file");
    assert.equal(logic.STATE_DIR, "/var/lib/vgshell/vpn");
    assert.deepEqual(order(armed), ["write", "status", "status", "status", "launch"], "the connect runs once the table arms for it");
    assert.deepEqual(launched(armed), [UP]);
    assert.equal(armed.stage, null);
    assert.equal(armed.profileActor.running, true);
    assert.deepEqual(plain(armed.profileAction), { kind: "profile-up", uuid: HOME, name: "Home tunnel", password: false });
    assert.equal(armed.startAction("profile-up", OFFICE, UP, null), "busy");
    assert.equal(armed.stateDeadline.stopped, 1, "the write's deadline stops with the write");
    // The wait ends with the reader idle: the file's profile goes back,
    // nothing runs. Reads that answered say the switch did not start.
    const expired = serviceOwner({ disk: textOf(OFFICE, "block", "1794203888"), lines: [status("off", "disarmed", "")] });
    expired.startAction("profile-up", HOME, UP, null);
    assert.deepEqual(expired.stage.phase, "arm");
    assert.ok(expired.events.includes("retry"), "a waiting read asks again");
    expired.armExpired();
    assert.deepEqual(writes(expired), [textOf(HOME, "block", "1794203888"), textOf(OFFICE, "block", "1794203888")]);
    assert.deepEqual(launched(expired), []);
    ended(expired, HOME, "Home tunnel", "timeout", "", false);
    assert.equal(expired.autoMemory.problem, null, "a connect Connect automatically did not start leaves its line alone");
    // The same wait for a connect Connect automatically started leaves the
    // stage's problem beside the setting too.
    const autoExpired = serviceOwner({ disk: textOf(OFFICE, "block", "1794203888"), lines: [status("off", "disarmed", "")], autoAction: HOME });
    autoExpired.startAction("profile-up", HOME, UP, null);
    autoExpired.armExpired();
    assert.deepEqual(plain([autoExpired.autoAction, autoExpired.autoMemory.problem]),
        ["", { kind: "failed", uuid: HOME, name: "Home tunnel", reason: autoExpired.profileProblem.text }]);
    // The wait ends with a read running: the deadline only marks the
    // stage, and that read's end rolls back unless it names the table
    // armed for the profile.
    for (const [name, last, rolled] of [["a read that does not answer", status("off", "disarmed", ""), true], ["a read that arms", status("passing"), false]]) {
        const running = serviceOwner({ disk: textOf("", "block"), lines: [null] });
        running.startAction("profile-up", HOME, UP, null);
        running.armExpired();
        assert.equal(running.stage.expired, true, name);
        assert.equal(writes(running).length, 1, name + ": nothing rolls back while the read runs");
        running.killReader.running = false;
        running.killStatus = plain(last);
        running.armRead();
        assert.deepEqual(launched(running), rolled ? [] : [UP], name);
        assert.equal(writes(running).length, rolled ? 2 : 1, name);
    }
    // Each wait that ends unarmed asks for a fresh probe.
    assert.ok(expired.events.includes("probe"), "a timeout asks for a fresh probe");
    // A wait that ends while the step reads needed, as after its units
    // failed, points to Set up and still puts the file's profile back.
    const resetUp = serviceOwner({ disk: textOf(OFFICE, "block"), lines: [status("off", "disarmed", "")] });
    resetUp.startAction("profile-up", HOME, UP, null);
    resetUp.probeStep = { state: "needed", reason: "units-failed" };
    resetUp.armExpired();
    assert.deepEqual(writes(resetUp), [textOf(HOME, "block"), textOf(OFFICE, "block")]);
    assert.deepEqual(launched(resetUp), []);
    ended(resetUp, HOME, "Home tunnel", "setup", "", false);
    assert.notEqual(logic.stageProblem("profile-up", "Home tunnel", "setup", "", false), logic.stageProblem("profile-up", "Home tunnel", "timeout", "", false));
    assert.notEqual(logic.stageProblem("profile-up", "Home tunnel", "setup", "", false), logic.stageProblem("profile-up", "Home tunnel", "unavailable", "", false));
    // A wait in which no read gave a line says VGS could not check.
    const unchecked = serviceOwner({ lines: [logic.killStatus(1, ""), logic.killStatus(1, "", "vgs-kill-switch: refused: status=unreadable path=x")] });
    unchecked.startAction("profile-up", HOME, UP, null);
    unchecked.armExpired();
    ended(unchecked, HOME, "Home tunnel", "unchecked", "", false);
    // A WireGuard profile the root half cannot use: put back at once,
    // nothing runs.
    const refused = serviceOwner({ lines: [status("unavailable", "endpoint-hostname", LAB)] });
    refused.startAction("profile-up", LAB, LAB_UP, null);
    assert.deepEqual(writes(refused), [textOf(LAB, "block"), textOf("", "block")]);
    assert.deepEqual(launched(refused), []);
    ended(refused, LAB, "Lab tunnel", "unavailable", "endpoint-hostname", false);
    assert.ok(refused.events.includes("arm-deadline-stop"));
    // A profile that is not WireGuard, with the switch on: refused before
    // any write.
    const notWireGuard = serviceOwner({ lines: [status("passing", "tunnel-up", HOME)] });
    notWireGuard.startAction("profile-up", OFFICE, ["nmcli", "connection", "up", "uuid", OFFICE], null);
    assert.deepEqual([writes(notWireGuard), launched(notWireGuard)], [[], []]);
    ended(notWireGuard, OFFICE, "Office VPN", "unavailable", "profile-not-wireguard", false);
    // A rollback that does not land says the block may hold.
    const unrestored = serviceOwner({ disk: textOf(OFFICE, "block"), lines: [status("off", "disarmed", "")] });
    unrestored.startAction("profile-up", HOME, UP, null);
    unrestored.moveFails = true;
    unrestored.armExpired();
    assert.deepEqual(launched(unrestored), []);
    ended(unrestored, HOME, "Home tunnel", "timeout", "", true);
    // Switch off: the file names the profile and nmcli runs at once.
    const plainUp = serviceOwner({ disk: textOf("", "off"), lines: [] });
    plainUp.startAction("profile-up", HOME, UP, null);
    assert.deepEqual(order(plainUp), ["write", "launch"]);
    assert.deepEqual(writes(plainUp), [textOf(HOME, "off")]);
    // A disconnect clears the profile first.
    const down = serviceOwner({ disk: textOf(HOME, "block") });
    down.startAction("profile-down", HOME, DOWN, null);
    assert.deepEqual(order(down), ["write", "launch"]);
    assert.deepEqual(writes(down), [textOf("", "block")]);
    // The notice's Turn VPN off over the service's IPC: the dropped
    // profile the file names is cleared from it, and nmcli does not run.
    const release = serviceOwner({ disk: textOf(LAB, "block-lan", "1794203888"), killFile: file(LAB, "block-lan", "1794203888"), lines: [status("off", "disarmed", "")],
        profiles: dropped });
    release.killSwitch = plain(logic.killSwitchState(release.killStep, release.killFile, plain(holding), false, "", false));
    release.shell.requirements = { missing: [] };
    bind(release, "actProfile");
    assert.equal(release.actProfile({ kind: "profile-down", id: LAB }), "ok");
    assert.equal(release.autoMemory.pending, false, "a profile turned off here holds Connect automatically until the next network change");
    assert.deepEqual(writes(release), [textOf("", "block-lan", "1794203888")]);
    assert.deepEqual(launched(release), [null]);
    assert.deepEqual([release.profileAction, release.stage, release.stateWrite, release.profileActor.running], [null, null, null, false]);
    assert.ok(release.events.includes("read-profiles"), "the list is read again");
    assert.equal(release.profileProblem, null);
    // With the step not set up there is no file to name a profile, so a
    // dropped profile's disconnect is refused as before.
    const noStep = serviceOwner({ profiles: dropped, killReady: false, killWritable: false });
    noStep.killSwitch = plain(logic.killSwitchState({ state: "needed", reason: "not-set-up" }, file(LAB, "block"), null, false, "", false));
    noStep.shell.requirements = { missing: [] };
    bind(noStep, "actProfile");
    assert.equal(noStep.actProfile({ kind: "profile-down", id: LAB }), "refused: profile=state");
    assert.equal(noStep.autoMemory.pending, true, "a refused disconnect leaves the network change pending");
    // A file already naming the profile is not written again.
    const same = serviceOwner({ disk: textOf(HOME, "off") });
    same.startAction("profile-up", HOME, UP, null);
    assert.deepEqual(order(same), ["launch"]);
    // No step: no write, nmcli at once.
    const unready = serviceOwner({ killReady: false, killWritable: false });
    unready.startAction("profile-up", HOME, UP, null);
    assert.deepEqual(order(unready), ["launch"]);
    // A write that fails before its rename, or over a file VGS cannot
    // read, runs nothing; a failed save, chmod or rename removes its file.
    const unreadable = owner => {
        owner.stateFile.reload = function () {
            owner.events.push("reload");
            owner.killFile = { kind: "unreadable" };
            if (owner.stateWrite !== null) owner.writeEnded(false);
        };
        return owner;
    };
    for (const [name, make, removes] of [["a failed save", fields => serviceOwner(Object.assign({ saveFails: true }, fields)), true],
        ["an unreadable file", fields => unreadable(serviceOwner(fields)), false],
        ["a failed rename", fields => serviceOwner(Object.assign({ moveFails: true }, fields)), true],
        ["a failed chmod", fields => serviceOwner(Object.assign({ modeFails: true }, fields)), true]]) {
        for (const [kind, argv, disk] of [["profile-up", UP, textOf(OFFICE, "block")], ["profile-down", DOWN, textOf(HOME, "block")],
            ["profile-remove", ["nmcli", "connection", "delete", "uuid", HOME], textOf(HOME, "off")]]) {
            const failed = make({ disk, lines: [status("holding", "tunnel-down")] });
            assert.equal(failed.startAction(kind, HOME, argv, null), "ok");
            assert.deepEqual(launched(failed), [], name + " " + kind);
            assert.equal(failed.profileProblem.kind, "kill-switch", name + " " + kind);
            assert.equal(failed.profileProblem.text, logic.stageProblem(kind, "Home tunnel", "write", "", false), name + " " + kind);
            assert.deepEqual([failed.stage, failed.profileAction, failed.stateWrite], [null, null, null], name + " " + kind);
            if (removes) {
                const temp = failed.events.find(event => event[0] === "temp")[1];
                assert.deepEqual(failed.events.filter(event => ["rm", "touch"].includes(event[0]) || (event[0] === "mv" && name !== "a failed rename")),
                    [["rm", ["rm", "-f", "--", temp]]], name + " removes its file, renames nothing and makes no pending");
            }
        }
    }
    // After the rename the write is made: a failed touch, or a read-back
    // another writer's rename overtook, is logged, and the change goes on.
    for (const [name, fields] of [["a failed touch", { touchFails: true }], ["an overtaken rename", { lost: true }]]) {
        const made = serviceOwner(Object.assign({ disk: textOf(HOME, "block") }, fields));
        made.startAction("profile-down", HOME, DOWN, null);
        assert.deepEqual(launched(made), [DOWN], name);
        assert.ok(made.events.some(event => Array.isArray(event) && event[0] === "warn"), name + " is logged");
    }
    // A connect with the file already naming its profile writes nothing
    // but still makes the pending file, so the root half reads it again.
    const nudged = serviceOwner({ disk: textOf(HOME, "block"), lines: [status("holding", "tunnel-down")] });
    nudged.startAction("profile-up", HOME, UP, null);
    assert.deepEqual(writeSteps(nudged).map(event => event[0]), ["touch"], "only the pending file");
    assert.deepEqual(launched(nudged), [UP]);
    assert.deepEqual(nudged.events.filter(event => Array.isArray(event) && event[0] === "warn"), [], "a nudge's read-back finds what it expects");
    // After a nudge the table already named the profile, so a refusal for
    // it can predate the nudged sync: it waits, and decides only at the
    // deadline, unless the sync arms the table first.
    const staleRefusal = serviceOwner({ disk: textOf(HOME, "block"), lines: [status("unavailable", "profile-unread", HOME)] });
    staleRefusal.startAction("profile-up", HOME, UP, null);
    assert.equal(staleRefusal.stage.phase, "arm", "the refusal does not end the wait");
    staleRefusal.armExpired();
    assert.deepEqual(launched(staleRefusal), []);
    ended(staleRefusal, HOME, "Home tunnel", "unavailable", "profile-unread", false);
    const resynced = serviceOwner({ disk: textOf(HOME, "block"), lines: [status("unavailable", "profile-unread", HOME), status("holding", "tunnel-down", HOME)] });
    resynced.startAction("profile-up", HOME, UP, null);
    assert.deepEqual(launched(resynced), [UP], "the nudged sync's armed line connects");
    // A write's end takes the grace from a read already running, and no
    // write starts while a step an interrupted write left still runs.
    const regraced = serviceOwner({ disk: textOf("", "block") });
    regraced.killReader.settles = true;
    regraced.setKillSwitch("off");
    assert.equal(regraced.killReader.settles, false);
    const held = serviceOwner();
    held.stateModer.busy = true;
    assert.equal(held.writeState(() => ({ mode: "off" }), () => { throw new Error("the write ran"); }), "busy");
    const quiet = serviceOwner({ disk: textOf(HOME, "block") });
    quiet.setKillSwitch("block");
    assert.deepEqual(writeSteps(quiet), [], "an unchanged mode writes nothing");
    // A late step of an ended write is not a later write's.
    const serials = serviceOwner({ stall: "chmod" });
    serials.writeState(() => ({ mode: "off" }), () => {});
    const first = serials.stateWrite.serial;
    serials.stateExpired();
    serials.stateModer.busy = false;
    serials.writeState(() => ({ mode: "block-lan" }), () => {});
    assert.equal(serials.stateWrite.phase, "mode");
    serials.stall = "";
    serials.moded(0, first);
    assert.equal(serials.stateWrite.phase, "mode", "the ended write's chmod does not move the later write");
    serials.moded(0, serials.stateWrite.serial);
    assert.equal(serials.stateWrite, null, "the later write's own chmod does");
    // The grace ends on a status read that starts after a poll ticked,
    // not on one already running.
    const graced = { registered: true, killReady: true, killSettlePoll: true, checkWantsStatus: false,
        killReader: { running: true, again: false, settles: false, forCheck: false, completion: null }, killDeadline: { restart() {} } };
    bind(graced, "readKillStatus");
    graced.readKillStatus();
    assert.deepEqual([graced.killReader.again, graced.killReader.settles, graced.killSettlePoll], [true, false, true], "a running read does not take the tick");
    graced.killReader.running = false;
    graced.readKillStatus();
    assert.deepEqual([graced.killReader.settles, graced.killSettlePoll], [true, false], "the read the tick starts carries it");
    // The leak check's status request rides the same way: a running read
    // started before the check asked does not answer it; the next one does.
    graced.checkWantsStatus = true;
    graced.killReader.running = true;
    graced.readKillStatus();
    assert.deepEqual([graced.killReader.forCheck, graced.checkWantsStatus], [false, true], "a running read does not answer the check");
    graced.killReader.running = false;
    graced.readKillStatus();
    assert.deepEqual([graced.killReader.forCheck, graced.checkWantsStatus], [true, false], "the read the check's request starts answers it");
    // One writer: a second write while one runs answers busy.
    const writer = serviceOwner({ stall: "reload" });
    assert.equal(writer.writeState(() => ({ mode: "off" }), () => { throw new Error("the second write ran"); }), "ok");
    assert.equal(writer.writeState(() => ({ mode: "block" }), () => { throw new Error("the second write ran"); }), "busy");
    // A write whose answer never comes ends at its deadline: before the
    // rename as failed, with its running step signalled.
    for (const [name, stall, phase, ok] of [["a read that never answers", "reload", "read", false], ["a chmod that never ends", "chmod", "mode", false]]) {
        const stuck = serviceOwner({ stall });
        let result = null;
        stuck.writeState(() => ({ mode: "off" }), value => { result = value; });
        assert.equal(stuck.stateWrite.phase, phase, name);
        stuck.stateExpired();
        assert.deepEqual([result, stuck.stateWrite], [ok, null], name);
        if (stall === "chmod") assert.deepEqual(stuck.events.filter(event => event[0] === "signal"), [["signal", "chmod", 9]], name);
        // A late answer from the ended write does nothing.
        stuck.moded(0);
        stuck.stateRead();
        assert.equal(stuck.stateWrite, null, name);
    }
    // The switches write the mode and keep every other key.
    const toggled = serviceOwner({ disk: textOf(HOME, "block", "1794203888") });
    assert.equal(toggled.setKillSwitch("on"), "refused: kill-switch=mode");
    assert.equal(toggled.setKillSwitch("block-lan"), "ok");
    assert.deepEqual(writes(toggled), [textOf(HOME, "block-lan", "1794203888")]);
    assert.deepEqual([toggled.killChanging, toggled.killProblem, toggled.killSettling], [false, "", true]);
    toggled.stage = { phase: "arm" };
    assert.equal(toggled.setKillSwitch("off"), "busy");
    assert.equal(serviceOwner({ killReady: false, killWritable: false }).setKillSwitch("off"), "refused: kill-switch=not-set-up");
    const unsaved = serviceOwner({ saveFails: true });
    assert.equal(unsaved.setKillSwitch("off"), "ok");
    assert.notEqual(unsaved.killProblem, "", "a failed save leaves a problem");
}

// Execute the production editor planner and the pane's production click
// callback. No editor, profile or stored key is reached by these doubles.
function editorSuite(logic, body = bodySource) {
    const profiles = { state: "available", rows: [{ uuid: HOME, name: "Home tunnel" }] };
    for (const [kind, uuid, payload, expected] of [
        ["create", "", profiles, { argv: ["nm-connection-editor", "--create", "--type=vpn"] }],
        ["edit", HOME, profiles, { argv: ["nm-connection-editor", "--edit=" + HOME] }],
        ["edit", OFFICE, profiles, { refusal: "refused: profile=absent" }],
        ["edit", "Home tunnel", profiles, { refusal: "refused: profile=absent" }],
        ["edit", HOME, { state: "not-running", rows: profiles.rows }, { refusal: "refused: profile=unavailable" }],
        ["remove", HOME, profiles, { refusal: "refused: editor=kind" }]
    ]) assert.deepEqual(plain(logic.editorArgv(kind, uuid, payload)), expected);
    const callback = /function editor\(kind, uuid\) \{([\s\S]*?)\n    \}/.exec(body);
    assert.ok(callback, "production editor callback");
    const invoke = new Function("Logic", "profiles", "owner", "kind", "uuid", "with (owner) {" + callback[1] + "}");
    const activeBody = /Window.onActiveChanged: \{([\s\S]*?)\n    \}/.exec(body);
    assert.ok(activeBody);
    const activate = new Function("owner", "with (owner) {" + activeBody[1] + "}");
    for (const [kind, uuid, missing, launchReply, expectedOffers, expectedLaunches, target] of [
        ["create", "", [], "ok", [], [["nm-connection-editor", "--create", "--type=vpn"]], ""],
        ["edit", HOME, [], "ok", [], [["nm-connection-editor", "--edit=" + HOME]], HOME],
        ["edit", HOME, [], "refused: run=start", [], [["nm-connection-editor", "--edit=" + HOME]], null],
        ["create", "", ["nm-connection-editor"], "ok", [["nm-connection-editor"]], [], null],
        ["edit", HOME, ["nm-connection-editor"], "ok", [["nm-connection-editor"]], [], null],
        ["edit", OFFICE, [], "ok", [], [], null]
    ]) {
        const offers = [], launches = [], answers = [], refreshes = [];
        const owner = { expanded: true, Window: { active: false }, dialogTarget: { uuid: OFFICE }, draft: "fixture-draft",
            shell: {
                requirements: { missing, offer(commands) { offers.push(plain(commands)); return "ok"; } },
                run: { detached(argv) { launches.push(plain(argv)); return launchReply; } },
                ipc: { call(verb, arg) { refreshes.push([verb, arg]); return "ok"; } }
            }, answered(reply) { answers.push(reply); return reply; } };
        invoke(logic, profiles, owner, kind, uuid);
        assert.deepEqual(offers, expectedOffers);
        assert.deepEqual(launches, expectedLaunches);
        assert.deepEqual(answers, uuid === OFFICE ? ["refused: profile=absent"] : target === HOME ? [launchReply, "ok"] : [launchReply]);
        assert.deepEqual(refreshes, target === HOME ? [["refresh", HOME]] : [], "only a successful edit invalidates its UUID at handoff");
        refreshes.length = 0;
        activate(owner);
        assert.deepEqual(refreshes, [], "leaving the window refreshes nothing");
        owner.Window.active = true;
        activate(owner);
        activate(owner);
        assert.deepEqual(refreshes, [["refresh", ""], ["refresh", ""]], "ordinary activations read metadata without invalidating a UUID");
        assert.deepEqual([owner.dialogTarget, owner.draft], [{ uuid: OFFICE }, "fixture-draft"], "focus keeps the unrelated prompt and draft");
    }
    // A pane can be destroyed while the detached editor remains open.
    // Its replacement has no remembered launch, so open itself rereads
    // metadata while keeping every credential requirement learned since.
    const openBody = /function open\(\) \{([\s\S]*?)\n    \}/.exec(body);
    assert.ok(openBody);
    const calls = [];
    const recreated = { leaseId: "replacement", leased: false, expanded: true, dialogTarget: null,
        shell: { ipc: { call(verb, arg) { calls.push([verb, arg]); return "ok"; } } }, answered(reply) { return reply; } };
    new Function("owner", "with (owner) {" + openBody[1] + "}")(recreated);
    assert.deepEqual(calls, [["lease", JSON.stringify({ id: "replacement", open: true })], ["refresh", ""]]);
    assert.equal(manifest.requirements.find(row => row.command === "nm-connection-editor").optional, true);
    for (const kind of manifest.kinds)
        assert.equal(core.instanceCapabilities(manifest, kind).includes("run"), kind === "pane", kind);
}

// The leak check (VGS-2398) judged from recorded readings: the tunnel's
// interface as nmcli 1.58.1 prints it, routes as iproute2 7.3.0 prints
// them under LC_ALL=C, systemd-resolved's settings in the shape systemd
// 262's io.systemd.Resolve.DumpDNSConfiguration answers (each recorded on
// 2026-11-11, in network namespaces or on the host, with stand-in values;
// dns-tunnel.json is dns-wifi-domain.json without the Wi-Fi's DHCP
// domain, and dns-wifi-route.json is dns-tunnel.json with the tunnel's
// DNS server gone and the Wi-Fi holding the DNS default route), and the
// provider's answer with the fields the issue lists. The judge never reads
// a pass from a reading it could not take. SERVICE and LEAK are
// Service.qml's and LeakCheck.qml's text, whose leak check wiring runs
// over doubles.
function leakCheckSuite(logic, service = serviceSource, leak = leakSource) {
    const json = name => JSON.parse(text(name));
    const tunnelDns = json("dns-tunnel.json");
    // DNS readings: the recorded settings with each named entry's changed,
    // `global` naming the global settings, a planted defect private to its
    // row.
    const dnsWith = changes => logic.dnsRead(0, JSON.stringify({ configuration: tunnelDns.configuration.map(entry => {
        const change = changes[typeof entry.ifname === "string" ? entry.ifname : "global"];
        return change === undefined ? entry : Object.assign({}, entry, change);
    }) }));
    const root = [{ name: ".", routeOnly: true, ifindex: 0 }];
    const servers = [{ addressString: "192.0.2.53", address: [192, 0, 2, 53], family: 2, port: 53 }];
    const status = (state, blocked, tunnel = "wg-home", profile = HOME) =>
        logic.killStatus(0, "state=" + state + " reason=" + (state === "holding" ? "tunnel-down" : state === "passing" ? "tunnel-up" : "disarmed")
            + " blocked=" + blocked + " tunnel=" + tunnel + " profile=" + profile + "\n");

    // The parsers, on recorded and malformed readings.
    const TAILNET = { link: "tailscale0", defaultRoute: false, domains: ["tail0000.ts.net", "ts.net"] };
    const TUNNEL = { link: "wg-home", defaultRoute: true, domains: ["."] };
    for (const [name, read, expected] of [
        ["an activated profile's interface", logic.linkRead(0, text("link.txt")), { kind: "active", link: "wg-home" }],
        ["a profile not active prints nothing", logic.linkRead(0, ""), { kind: "inactive" }],
        ["a profile going down", logic.linkRead(0, "GENERAL.STATE:deactivating\nGENERAL.IP-IFACE:wg-home\n"), { kind: "inactive" }],
        ["a failed interface read", logic.linkRead(10, ""), { kind: "unreadable" }],
        ["an interface name outside the kernel's", logic.linkRead(0, "GENERAL.STATE:activated\nGENERAL.IP-IFACE:wg/home\n"), { kind: "unreadable" }],
        ["an activated profile with no interface line", logic.linkRead(0, "GENERAL.STATE:activated\n"), { kind: "unreadable" }],
        ["a route through the tunnel", logic.routeRead(0, text("route-tunnel.json"), ""), { kind: "via", link: "wg-home" }],
        ["a route through the Wi-Fi", logic.routeRead(0, text("route-wlan0.json"), ""), { kind: "via", link: "wlan0" }],
        ["no route", logic.routeRead(2, "", text("route-none.txt")), { kind: "none" }],
        ["an unreachable route", logic.routeRead(2, "", "RTNETLINK answers: No route to host\n"), { kind: "none" }],
        ["a blackhole route", logic.routeRead(2, "", "RTNETLINK answers: Invalid argument\n"), { kind: "unreadable" }],
        ["a route read the deadline ended", logic.routeRead(-1, "", ""), { kind: "unreadable" }],
        ["a route read that is no JSON", logic.routeRead(0, "default via 192.168.50.1", ""), { kind: "unreadable" }],
        ["an empty route list", logic.routeRead(0, "[]", ""), { kind: "unreadable" }],
        ["two routes", logic.routeRead(0, "[" + text("route-tunnel.json").trim().slice(1, -1) + "," + text("route-wlan0.json").trim().slice(1, -1) + "]", ""), { kind: "unreadable" }],
        ["the recorded settings", logic.dnsRead(0, text("dns-tunnel.json")), { kind: "scopes", fallback: true, scopes: [
            { link: "wlan0", defaultRoute: false, domains: [] }, TAILNET, TUNNEL] }],
        ["the Wi-Fi's DHCP domain", logic.dnsRead(0, text("dns-wifi-domain.json")), { kind: "scopes", fallback: true, scopes: [
            { link: "wlan0", defaultRoute: false, domains: ["hotel.example"] }, TAILNET, TUNNEL] }],
        ["global servers with a domain, which take every unrouted name",
            dnsWith({ global: { servers, searchDomains: [{ name: "Corp.Example.", routeOnly: true }] } }), { kind: "scopes", fallback: true, scopes: [
                { link: logic.GLOBAL_DNS, defaultRoute: true, domains: ["corp.example"] }, { link: "wlan0", defaultRoute: false, domains: [] }, TAILNET, TUNNEL] }],
        ["the Wi-Fi holding the DNS default route", logic.dnsRead(0, text("dns-wifi-route.json")), { kind: "scopes", fallback: true, scopes: [
            { link: "wlan0", defaultRoute: true, domains: [] }, TAILNET] }],
        ["a delegate's servers", logic.dnsRead(0, JSON.stringify({ configuration: [{ resolvConfMode: "stub" },
            { delegate: "corp", defaultRoute: false, servers, searchDomains: [{ name: "corp.example" }] }] })),
            { kind: "scopes", fallback: false, scopes: [{ link: logic.GLOBAL_DNS, defaultRoute: false, domains: ["corp.example"] }] }],
        // Programs that read /etc/resolv.conf ask resolved only while it
        // names resolved's stub.
        ["resolv.conf naming resolved's static stub", dnsWith({ global: { resolvConfMode: "static" } }), { kind: "scopes", fallback: true, scopes: [
            { link: "wlan0", defaultRoute: false, domains: [] }, TAILNET, TUNNEL] }],
        ["resolv.conf listing the uplink servers", dnsWith({ global: { resolvConfMode: "uplink" } }), { kind: "unreadable" }],
        ["resolv.conf resolved does not manage", dnsWith({ global: { resolvConfMode: "foreign" } }), { kind: "unreadable" }],
        ["no resolv.conf", dnsWith({ global: { resolvConfMode: "missing" } }), { kind: "unreadable" }],
        ["no resolv.conf mode read", dnsWith({ global: { resolvConfMode: null } }), { kind: "unreadable" }],
        ["resolved not reachable", logic.dnsRead(1, ""), { kind: "unreadable" }],
        ["a reply that is no JSON", logic.dnsRead(0, "Link 3 (wlan0)"), { kind: "unreadable" }],
        ["a link with servers and no default-route reading", dnsWith({ wlan0: { defaultRoute: null } }), { kind: "unreadable" }],
        ["a link with no name", dnsWith({ wlan0: { ifname: null } }), { kind: "unreadable" }],
        ["a domain with no name", dnsWith({ wlan0: { searchDomains: [{ routeOnly: false }] } }), { kind: "unreadable" }],
        ["fallback servers that are no list", dnsWith({ global: { fallbackServers: "192.0.2.53" } }), { kind: "unreadable" }]
    ]) assert.deepEqual(plain(read), expected, name);

    // The provider's answer: a good one, a failed request and malformed
    // answers, each never a blank, zero or guessed field.
    const good = json("insights.json");
    const answer = changes => JSON.stringify(Object.assign({}, good, changes));
    assert.deepEqual(plain(logic.insights(0, text("insights.json"))), { kind: "ok", ip: "198.51.100.7", country: "Netherlands", city: "Amsterdam" });
    assert.deepEqual(plain(logic.insights(0, answer({ city: undefined }))), { kind: "ok", ip: "198.51.100.7", country: "Netherlands", city: "" });
    for (const [name, code, output, reason] of [
        ["the deadline", -1, "", "timeout"], ["curl's own timeout", 28, "", "timeout"], ["no name lookup", 6, "", "lookup"],
        ["no connection", 7, "", "connect"], ["an HTTP error", 22, "", "refused"], ["the interface", 45, "", "interface"],
        ["the certificate", 60, "", "secure"], ["an answer over the size bound", 63, "", "malformed"], ["another failure", 92, "", "request"],
        ["no JSON", 0, "<html>Too many requests</html>", "malformed"], ["a list", 0, "[" + text("insights.json") + "]", "malformed"],
        ["an address out of range", 0, answer({ ip: "198.51.100.700" }), "malformed"], ["an IPv6 address", 0, answer({ ip: "2001:db8::7" }), "malformed"],
        ["an address as a number", 0, answer({ ip: 3325256711 }), "malformed"], ["a zero address", 0, answer({ ip: "" }), "malformed"],
        ["no country", 0, answer({ country: undefined }), "malformed"], ["an empty country", 0, answer({ country: " " }), "malformed"],
        ["a country with a control character", 0, answer({ country: "Nether\u0007lands" }), "malformed"],
        ["a country past the length bound", 0, answer({ country: "N".repeat(logic.TEXT_MAX + 1) }), "malformed"],
        ["a city that is no text", 0, answer({ city: 7 }), "malformed"],
        ["an answer past the size bound", 0, answer({ isp: "x".repeat(logic.INSIGHTS_MAX) }), "malformed"]
    ]) assert.deepEqual(plain(logic.insights(code, output)), { kind: "failed", reason }, name);

    // The one outside question goes through the tunnel's interface, over
    // IPv4 and HTTPS, bounded in time and size, with no redirect; every
    // command a check runs is a declared optional requirement.
    const ask = logic.insightsArgv("wg-home");
    assert.equal(ask[ask.indexOf("--interface") + 1], "if!wg-home");
    for (const flag of ["-q", "--ipv4", "--fail", "--max-time", "--max-filesize"]) assert.ok(ask.includes(flag), flag);
    assert.equal(ask[ask.indexOf("--proto") + 1], "=https");
    assert.equal(ask[ask.length - 1], "https://api.nordvpn.com/v1/helpers/ips/insights");
    assert.ok(!ask.some(arg => arg === "-L" || arg === "--location"));
    for (const argv of [logic.linkArgv(HOME), logic.routeArgv("ipv4"), logic.routeArgv("ipv6"), logic.DNS_ARGV, ask]) {
        const declared = manifest.requirements.find(row => row.command === argv[0]);
        assert.ok(declared !== undefined && declared.optional === true, argv[0] + " is a declared optional requirement");
    }

    // The one table: readings over a connected Home tunnel whose routes
    // and lookups stay in the tunnel, the kill switch not set up; each row
    // changes what it names. Verdicts are [ipv4, ipv6, dns, kill state],
    // a leak as "leak:<link>", an unknown as "unknown:<reason>", with the
    // command to install after a missing one's.
    const base = { uuid: HOME, link: { kind: "active", link: "wg-home" }, status: null,
        ipv4: { kind: "via", link: "wg-home" }, ipv6: { kind: "none" }, dns: logic.dnsRead(0, text("dns-tunnel.json")), public: logic.insights(0, text("insights.json")) };
    const unreadable = { kind: "unreadable" };
    const wlan = { kind: "via", link: "wlan0" };
    const wifiDomain = logic.dnsRead(0, text("dns-wifi-domain.json"));
    const wifiRoute = logic.dnsRead(0, text("dns-wifi-route.json"));
    const domains = (...names) => names.map(name => ({ name, routeOnly: true }));
    const tailnetDomains = domains("tail0000.ts.net", "ts.net", "0.e.1.a.c.5.1.1.a.7.d.f.ip6.arpa", "64.100.in-addr.arpa", "127.100.in-addr.arpa");
    const GLOBAL = "leak:" + logic.GLOBAL_DNS;
    const LEAK_TABLE = [
        ["DNS on the tunnel, with Tailscale's split DNS on its own domains, passes", {}, ["tunnel", "none", "tunnel", "off"]],
        ["a Wi-Fi link's DHCP domain is a DNS leak beside the tunnel's ~.", { dns: wifiDomain }, ["tunnel", "none", "leak:wlan0", "off"]],
        ["the same with the kill switch armed is blocked", { dns: wifiDomain, status: status("passing", 7) }, ["tunnel", "none", "blocked", "on"]],
        ["a domain the tunnel holds too still goes to the Wi-Fi", { dns: dnsWith({ wlan0: { searchDomains: [{ name: "corp.example" }] },
            "wg-home": { searchDomains: root.concat([{ name: "corp.example" }]) } }) }, ["tunnel", "none", "leak:wlan0", "off"]],
        ["a non-tunnel link holding the DNS default route is a DNS leak",
            { dns: dnsWith({ wlan0: { defaultRoute: true }, "wg-home": { searchDomains: [] } }) }, ["tunnel", "none", "leak:wlan0", "off"]],
        ["a non-tunnel link carrying ~. is a DNS leak", { dns: dnsWith({ wlan0: { searchDomains: root } }) }, ["tunnel", "none", "leak:wlan0", "off"]],
        ["a default-route link the tunnel's ~. outranks takes no lookup", { dns: dnsWith({ wlan0: { defaultRoute: true } }) }, ["tunnel", "none", "tunnel", "off"]],
        ["global servers beside a tunnel that is only the default route are a DNS leak",
            { dns: dnsWith({ global: { servers }, "wg-home": { searchDomains: [] } }) }, ["tunnel", "none", GLOBAL, "off"]],
        ["global servers with a domain are a DNS leak", { dns: dnsWith({ global: { servers, searchDomains: [{ name: "corp.example" }] } }) },
            ["tunnel", "none", GLOBAL, "off"]],
        ["global servers the tunnel's ~. outranks take no lookup", { dns: dnsWith({ global: { servers } }) }, ["tunnel", "none", "tunnel", "off"]],
        ["with no ~. and no default route, lookups go to the fallback servers", { dns: dnsWith({ "wg-home": { searchDomains: [], defaultRoute: false } }) },
            ["tunnel", "none", GLOBAL, "off"]],
        ["DNS no server takes is unknown", { dns: dnsWith({ "wg-home": { searchDomains: [], defaultRoute: false }, global: { fallbackServers: [] } }) },
            ["tunnel", "none", "unknown:lookups", "off"]],
        ["Tailscale's DNS taking every lookup is a DNS leak", { dns: dnsWith({ tailscale0: { searchDomains: root }, "wg-home": { searchDomains: [] } }) },
            ["tunnel", "none", "leak:tailscale0", "off"]],
        ["Tailscale's MagicDNS and reverse zones take no internet name", { dns: dnsWith({ tailscale0: { searchDomains: tailnetDomains } }) },
            ["tunnel", "none", "tunnel", "off"]],
        ["a public split domain on tailscale0 is a DNS leak", { dns: dnsWith({ tailscale0: { searchDomains: tailnetDomains.concat(domains("nordvpn.com")) } }) },
            ["tunnel", "none", "leak:tailscale0", "off"]],
        ["a reverse zone outside Tailscale's addresses on tailscale0 is a DNS leak", { dns: dnsWith({ tailscale0: { searchDomains: domains("63.100.in-addr.arpa") } }) },
            ["tunnel", "none", "leak:tailscale0", "off"]],
        ["a name that only ends in ts.net on tailscale0 is a DNS leak", { dns: dnsWith({ tailscale0: { searchDomains: domains("notts.net") } }) },
            ["tunnel", "none", "leak:tailscale0", "off"]],
        ["Tailscale's zone on another link is a DNS leak", { dns: dnsWith({ wlan0: { searchDomains: domains("ts.net") } }) },
            ["tunnel", "none", "leak:wlan0", "off"]],
        ["the Wi-Fi holding the DNS default route beside a tunnel with no DNS server is a DNS leak", { dns: wifiRoute },
            ["tunnel", "none", "leak:wlan0", "off"]],
        ["resolv.conf listing the uplink servers is unknown", { dns: dnsWith({ global: { resolvConfMode: "uplink" } }) },
            ["tunnel", "none", "unknown:read", "off"]],
        ["an IPv6 default route outside the tunnel with the kill switch off is an IPv6 leak", { ipv6: wlan }, ["tunnel", "leak:wlan0", "tunnel", "off"]],
        ["the same with the kill switch set up and off", { ipv6: wlan, status: status("off", 0, "", "") }, ["tunnel", "leak:wlan0", "tunnel", "off"]],
        ["the same with the kill switch armed is blocked", { ipv6: wlan, status: status("passing", 7) }, ["tunnel", "blocked", "tunnel", "on"]],
        ["the same with the kill switch armed closed is blocked", { ipv6: wlan, status: status("unavailable", 7, "", HOME) }, ["tunnel", "blocked", "tunnel", "on"]],
        ["the same with the kill switch unread is unknown", { ipv6: wlan, status: logic.killStatus(1, "", "") }, ["tunnel", "unknown:kill", "tunnel", "unknown"]],
        ["a route out of tailscale0, which the kill switch passes, is a leak", { ipv4: { kind: "via", link: "tailscale0" }, status: status("passing", 7) },
            ["leak:tailscale0", "none", "tunnel", "on"]],
        ["a drop the kill switch holds blocks every family", { link: { kind: "inactive" }, status: status("holding", 42), ipv4: wlan, ipv6: wlan,
            dns: dnsWith({ "wg-home": { servers: [] }, wlan0: { defaultRoute: true } }), public: null }, ["blocked", "blocked", "blocked", "holding"]],
        ["a drop with the kill switch off leaks", { link: { kind: "inactive" }, ipv4: wlan, ipv6: { kind: "none" },
            dns: dnsWith({ "wg-home": { servers: [] }, wlan0: { defaultRoute: true } }), public: null }, ["leak:wlan0", "none", "leak:wlan0", "off"]],
        ["an unreadable interface is unknown for every family", { link: unreadable, status: status("passing", 7) }, ["unknown:link", "unknown:link", "unknown:link", "on"]],
        ["an unreadable IPv4 route is unknown", { ipv4: unreadable }, ["unknown:read", "none", "tunnel", "off"]],
        ["an unreadable IPv6 route is unknown", { ipv6: unreadable }, ["tunnel", "unknown:read", "tunnel", "off"]],
        ["unreadable DNS settings are unknown", { dns: unreadable }, ["tunnel", "none", "unknown:read", "off"]],
        ["ip not installed is unknown, naming it", { ipv4: { kind: "missing", command: "ip" }, ipv6: { kind: "missing", command: "ip" } },
            ["unknown:missing:ip", "unknown:missing:ip", "tunnel", "off"]],
        ["varlinkctl not installed is unknown, naming it", { dns: { kind: "missing", command: "varlinkctl" } }, ["tunnel", "none", "unknown:missing:varlinkctl", "off"]]
    ];
    const verdictOf = family => family.verdict === "leak" ? "leak:" + family.link
        : family.verdict === "unknown" ? "unknown:" + family.reason + (family.install === "" ? "" : ":" + family.install) : family.verdict;
    for (const [name, changes, expected] of LEAK_TABLE) {
        const result = plain(logic.leakCheck(Object.assign({}, base, changes), null));
        assert.deepEqual([verdictOf(result.ipv4), verdictOf(result.ipv6), verdictOf(result.dns), result.kill.state], expected, name);
        assert.deepEqual(result.public, plain(Object.assign({}, base, changes).public), name + ": the answer passes through");
    }

    // The provider is asked only through the tunnel and only while lookups
    // of its own name stay in it or the armed kill switch blocks the rest:
    // curl looks its name up through the system resolver.
    const asked = { kind: "ask", link: "wg-home" };
    const leaks = { kind: "failed", reason: "lookups-leak" };
    for (const [name, changes, expected] of [
        ["lookups in the tunnel", {}, asked],
        ["lookups the armed kill switch blocks outside it", { dns: wifiRoute, status: status("passing", 7) }, asked],
        ["a lookup that can leave by the Wi-Fi", { dns: wifiRoute }, leaks],
        ["a lookup that can go to global servers", { dns: dnsWith({ global: { servers, searchDomains: root } }) }, leaks],
        ["the Wi-Fi's DHCP domain, which the provider's name is not under", { dns: wifiDomain }, asked],
        ["a router's search domain on the Wi-Fi", { dns: dnsWith({ wlan0: { searchDomains: [{ name: "lan", routeOnly: false }] } }) }, asked],
        ["a domain that ends in the same letters as the provider's", { dns: dnsWith({ wlan0: { searchDomains: domains("vpn.com") } }) }, asked],
        ["the provider's domain on the Wi-Fi", { dns: dnsWith({ wlan0: { searchDomains: domains("NordVPN.com.") } }) }, leaks],
        ["the provider's domain on the tunnel and the Wi-Fi alike", { dns: dnsWith({ wlan0: { searchDomains: domains("nordvpn.com") },
            "wg-home": { searchDomains: root.concat(domains("nordvpn.com")) } }) }, leaks],
        ["a tunnel domain longer than the Wi-Fi's ~.", { dns: dnsWith({ wlan0: { searchDomains: root }, "wg-home": { searchDomains: domains("nordvpn.com") } }) }, asked],
        ["a public split domain on tailscale0", { dns: dnsWith({ tailscale0: { searchDomains: tailnetDomains.concat(domains("nordvpn.com")) } }) }, leaks],
        ["with no ~., the tunnel holding the DNS default route", { dns: dnsWith({ "wg-home": { searchDomains: [] } }) }, asked],
        ["with no ~. and no default route, the fallback servers", { dns: dnsWith({ "wg-home": { searchDomains: [], defaultRoute: false } }) }, leaks],
        ["no server takes the provider's name", { dns: dnsWith({ "wg-home": { searchDomains: [], defaultRoute: false }, global: { fallbackServers: [] } }) },
            { kind: "failed", reason: "lookups-unknown" }],
        ["resolv.conf listing the uplink servers", { dns: dnsWith({ global: { resolvConfMode: "uplink" } }) }, { kind: "failed", reason: "lookups-unknown" }],
        ["DNS settings not read", { dns: unreadable }, { kind: "failed", reason: "lookups-unknown" }],
        ["varlinkctl not installed", { dns: { kind: "missing", command: "varlinkctl" } }, { kind: "failed", reason: "lookups-unknown" }],
        ["a lookup outside with the kill switch unread", { dns: wifiRoute, status: logic.killStatus(1, "", "") }, { kind: "failed", reason: "lookups-unknown" }],
        ["the profile no longer connected", { link: { kind: "inactive" } }, { kind: "failed", reason: "inactive" }],
        ["the interface not read", { link: unreadable }, { kind: "failed", reason: "link" }]
    ]) assert.deepEqual(plain(logic.publicPlan(Object.assign({}, base, changes, { public: null }))), expected, name);

    // The refused count's rise between two reads of one armed table: never
    // against another profile's table or a first read, and compared as the
    // whole numbers the status line carries, past 2^53.
    for (const [name, before, after, previous, rising] of [
        ["a first read", null, status("holding", 42), "", false],
        ["a higher count", status("holding", 30), status("holding", 42), "30", true],
        ["one more digit", status("passing", 9), status("holding", 10), "9", true],
        ["the same count", status("holding", 42), status("holding", 42), "42", false],
        ["a lower count, a table made again", status("holding", 42), status("holding", 3), "42", false],
        ["past 2^53", status("holding", "18446744073709551614"), status("holding", "18446744073709551615"), "18446744073709551614", true],
        ["another profile's table", status("holding", 30, "wg-office", OFFICE), status("holding", 42), "", false],
        ["after the kill switch was off", status("off", 0, "", ""), status("holding", 42), "", false]
    ]) {
        const first = before === null ? null : logic.leakCheck(Object.assign({}, base, { status: before }), null).kill;
        const kill = plain(logic.leakCheck(Object.assign({}, base, { status: after, link: { kind: "inactive" } }), first).kill);
        assert.deepEqual([kill.blocked, kill.previous, kill.rising], [after.blocked, previous, rising], name);
    }

    // The kill switch a check reads, by the system step's state: no table
    // only where the step rules one out; anywhere else its status, since
    // an installed table outlives an update or a failed unit and the
    // status socket answers any user. A status command that never started
    // reads not set up while the step is not set up.
    for (const [name, step, plan] of [
        ["before the first probe", undefined, "read"], ["set up", { state: "ready", reason: "granted" }, "read"],
        ["needs setting up", { state: "needed", reason: "not-set-up" }, "read"], ["units failed", { state: "needed", reason: "units-failed" }, "read"],
        ["NixOS setup", { state: "nixos", reason: "" }, "read"], ["unread", { state: "unknown", reason: "hash-failed" }, "read"],
        ["another account's", { state: "denied", reason: "other-account" }, "read"], ["denied for a reason it does not name", { state: "denied", reason: "other" }, "read"],
        ["absent", { state: "absent", reason: "" }, "none"], ["NixOS", { state: "denied", reason: "nixos-unsupported" }, "none"],
        ["no systemd", { state: "denied", reason: "systemd-missing" }, "none"], ["no nftables", { state: "denied", reason: "nft-missing" }, "none"]
    ]) assert.equal(logic.checkKillPlan(step), plan, name);
    const holdingHome = status("holding", 42);
    for (const [name, ready, started, expected] of [
        ["set up, read", true, true, holdingHome], ["set up, never started", true, false, holdingHome],
        ["not set up, read", false, true, holdingHome], ["not set up, no status command", false, false, null]
    ]) assert.deepEqual(logic.checkKillStatus(ready, holdingHome, started), expected, name);

    // The service's wiring over doubles: `with` resolves bare names on the
    // owner, as QML does.
    const sourceFn = (source, owner, name) => {
        const found = new RegExp("function " + name + "\\(([^)]*)\\) \\{([\\s\\S]*?)\\n    \\}").exec(source);
        assert.ok(found, name);
        const params = found[1].split(",").map(param => param.trim()).filter(param => param !== "");
        owner[name] = new Function("Logic", "owner", ...params, "with (owner) {" + found[2] + "}").bind(null, logic, owner);
    };
    const serviceFn = (owner, name) => sourceFn(service, owner, name);
    const checkOwner = step => {
        const owner = { registered: true, killStep: step, killReady: step.state === "ready", killSettlePoll: false, checkWantsStatus: false, handed: [],
            killReader: { running: false, again: false, settles: false, forCheck: false, completion: "old" }, killDeadline: { restart() {} },
            leakCheck: { statusRead(read) { owner.handed.push(read); } } };
        serviceFn(owner, "checkStatus");
        serviceFn(owner, "readKillStatus");
        return owner;
    };
    for (const [name, step, reads] of [["set up", { state: "ready" }, true], ["needs setting up", { state: "needed", reason: "not-set-up" }, true],
        ["absent", { state: "absent" }, false]]) {
        const owner = checkOwner(step);
        owner.checkStatus();
        assert.deepEqual([owner.killReader.running, owner.killReader.forCheck, plain(owner.handed)], reads ? [true, true, []] : [false, false, [null]], name);
    }
    const idle = checkOwner({ state: "needed", reason: "not-set-up" });
    idle.readKillStatus();
    assert.equal(idle.killReader.running, false, "the poll reads no status while the step is not set up");
    // The status read's end hands the check its reading; one taken for the
    // check alone while the step is not set up leaves the switch's own.
    const ended = /id: killReader[\s\S]*?onRunningChanged: \{([\s\S]*?)\n        \}/.exec(service);
    assert.ok(ended, "the status reader's end");
    const finishStatus = new Function("root", "Logic", "killText", "killErrors", "killDeadline", "console", "leakCheck", "reader", "with (reader) {" + ended[1] + "}");
    const line = "state=holding reason=tunnel-down blocked=42 tunnel=wg-home profile=" + HOME + "\n";
    for (const [name, ready, completion, killStatus, handed] of [
        ["set up", true, { code: 0, status: 0 }, holdingHome, holdingHome],
        ["not set up, read", false, { code: 0, status: 0 }, null, holdingHome],
        ["not set up, no status command", false, null, null, null],
        ["set up, no status command", true, null, logic.killStatus(-1, "", ""), logic.killStatus(-1, "", "")]
    ]) {
        const handedReads = [];
        const owner = { killReady: ready, killStatus: null, killSettling: false, stage: null, readKillStatus() {}, armRead() {},
            codeOf: done => done === null || done.status !== 0 ? -1 : done.code };
        const reader = { running: false, completion, forCheck: true, settles: false, again: false };
        finishStatus(owner, logic, { text: completion === null ? "" : line }, { text: "" }, { stop() {} }, { warn() {} },
            { statusRead(read) { handedReads.push(read); } }, reader);
        assert.deepEqual(plain([owner.killStatus, handedReads]), plain([killStatus, [handed]]), name);
    }

    // Only a WireGuard profile is checked: a connect's own start of a
    // check refuses another type, as the IPC does.
    const listing = plain(logic.list(0, text("list.txt")));
    const payload = plain(logic.compose(listing, {}, {}, {}, null, ""));
    const started = [];
    const starter = { profiles: payload, leakCheck: { start(uuid, active) { started.push([uuid, active]); return "ok"; } } };
    serviceFn(starter, "startCheck");
    assert.equal(starter.startCheck(TRAVEL, true), "refused: profile=type");
    assert.equal(starter.startCheck(HOME, true), "ok");
    assert.deepEqual(started, [[HOME, true]], "only the WireGuard profile's check starts");

    // The row: the address and its place only from a good answer; a failed
    // or malformed answer reads Could not check with its reason in the
    // error line, the text the issue's Done-when names, and never a place;
    // a question VGS did not ask reads as no check made, with its reason.
    // No hint repeats the info while the answer is good or the check runs.
    const connected = { uuid: HOME, type: "wireguard", state: "activated" };
    const done = (changes, active = true) => ({ uuid: HOME, busy: false, active, result: plain(logic.leakCheck(Object.assign({}, base, changes), null)) });
    const shown = plain(logic.checkView(done({}), connected, ""));
    assert.deepEqual([shown.shown, shown.publicShown, shown.public.text, shown.place, shown.reason], [true, true, "198.51.100.7", "Amsterdam, Netherlands", ""]);
    assert.deepEqual([shown.public.error, shown.public.hint], ["", ""], "a good answer has no hint");
    assert.deepEqual(shown.families.map(family => [family.key, family.error]), [["ipv4", ""], ["ipv6", ""], ["dns", ""]]);
    assert.equal(shown.killShown, false, "a kill switch that is off has its own row");
    assert.equal(plain(logic.checkView(done({ status: status("off", 0, "", "") }), connected, "")).killShown, false, "set up and off too");
    const armed = plain(logic.checkView(done({ status: status("passing", 7) }), connected, ""));
    assert.deepEqual([armed.killShown, armed.kill.error], [true, ""]);
    const unreadKill = plain(logic.checkView(done({ status: logic.killStatus(1, "", "") }), connected, ""));
    assert.ok(unreadKill.killShown && unreadKill.kill.error !== "", "an unread kill switch shows, with its reason");
    const leaking = plain(logic.checkView(done({ ipv6: wlan, dns: wifiDomain }), connected, ""));
    assert.deepEqual(leaking.families.map(family => family.error !== ""), [false, true, true]);
    assert.ok(leaking.families[1].error.includes("wlan0") && leaking.families[2].error.includes("wlan0"), "a leak names its link");
    assert.notEqual(plain(logic.checkView(done({ dns: dnsWith({ global: { servers, searchDomains: root } }) }), connected, "")).families[2].error, "",
        "a leak to global servers says so");
    assert.equal(new Set([logic.checkView(done({ ipv6: { kind: "none" } }), connected, "").families[1].text,
        logic.checkView(done({ ipv6: wlan }), connected, "").families[1].text,
        logic.checkView(done({ ipv6: unreadable }), connected, "").families[1].text,
        logic.checkView(done({ ipv6: { kind: "via", link: "wg-home" } }), connected, "").families[1].text]).size, 4, "each verdict reads apart");
    const reasons = new Set();
    const unchecked = plain(logic.checkView(null, connected, "")).public.text;
    for (const [failed, word] of [[logic.insights(28, ""), "Could not check"], [logic.insights(0, "<html>"), "Could not check"],
        [logic.insights(45, ""), "Could not check"], [logic.publicPlan(Object.assign({}, base, { dns: wifiRoute })), unchecked],
        [logic.publicPlan(Object.assign({}, base, { dns: unreadable })), unchecked]]) {
        const view = plain(logic.checkView(done({ public: failed }), connected, ""));
        assert.deepEqual([view.public.text, view.place, view.public.hint], [word, "", ""], failed.reason);
        reasons.add(view.public.error);
    }
    assert.ok(reasons.size === 5 && !reasons.has(""), "each failure names its own reason");
    // A command not installed: the line offers to install it.
    for (const [changes, pick, command] of [[{ public: { kind: "failed", reason: "missing" } }, view => view.public, "curl"],
        [{ ipv4: { kind: "missing", command: "ip" } }, view => view.families[0], "ip"],
        [{ dns: { kind: "missing", command: "varlinkctl" } }, view => view.families[2], "varlinkctl"]]) {
        const offered = pick(plain(logic.checkView(done(changes), connected, "")));
        assert.ok(offered.install === command && offered.error === "" && offered.link !== "" && offered.hint.includes(offered.link), command);
    }
    const busy = plain(logic.checkView({ uuid: HOME, busy: true, active: true, result: null }, connected, ""));
    assert.ok(busy.reason !== "" && busy.public.text !== "" && busy.public.hint === "" && busy.place === "", "a running check disables Check and shows no place or hint");
    const never = plain(logic.checkView(null, connected, ""));
    assert.ok(never.shown && never.reason === "" && never.public.text !== "" && never.families.length === 0 && !never.killShown);
    const stale = plain(logic.checkView(done({}), { uuid: HOME, type: "wireguard", state: "" }, HOME));
    assert.ok(stale.shown && !stale.publicShown && stale.families.length === 0, "a connected check does not describe the drop");
    const held = plain(logic.checkView(done({ link: { kind: "inactive" }, status: status("holding", 42), ipv4: wlan, public: null }, false),
        { uuid: HOME, type: "wireguard", state: "" }, HOME));
    assert.ok(held.shown && !held.publicShown && held.killShown && held.families.length === 3);
    assert.equal(plain(logic.checkView(done({}), { uuid: HOME, type: "wireguard", state: "" }, "")).shown, false, "an off profile no kill switch holds has no check");
    assert.equal(plain(logic.checkView(done({}), { uuid: OFFICE, type: "wireguard", state: "activated" }, "")).families.length, 0, "a check of another profile is not drawn");
    assert.equal(plain(logic.checkView(null, { uuid: OFFICE, type: "vpn", state: "activated" }, "")).shown, false, "a VPN-plugin profile has no check");

    // A list that outdates the result drops it, as LeakCheck.judgeStale
    // does: connected, disconnected outside VGS, connected again shows no
    // result until a new check. A change in flight holds its own profile.
    const listed = state => [{ uuid: HOME, type: "wireguard", state }];
    let published = done({});
    for (const [name, rows, action, stale] of [
        ["still connected", listed("activated"), null, false],
        ["the list a connect's end may predate", listed(""), { kind: "profile-up", uuid: HOME, ended: true }, false],
        ["another profile's change", listed(""), { kind: "profile-up", uuid: OFFICE }, true],
        ["disconnected", listed(""), null, true],
        ["gone", [], null, true]
    ]) assert.equal(logic.checkStale(published, rows, action), stale, name);
    for (const state of ["activated", "", "activated"])
        if (logic.checkStale(published, listed(state), null)) published = Object.assign({}, published, { result: null });
    const reconnected = plain(logic.checkView(published, connected, ""));
    assert.deepEqual([reconnected.public.text, reconnected.families.length, reconnected.place], [never.public.text, 0, ""], "no retained result");
    assert.equal(logic.checkStale(published, listed(""), null), false, "a dropped result has nothing left to drop");
    assert.equal(logic.checkStale({ uuid: HOME, busy: true, active: true, result: null }, listed(""), null), true, "a check in flight is outdated too");
    assert.equal(logic.checkStale(done({}, false), listed("activated"), null), true, "a drop's result goes once the profile connects");

    // LeakCheck's wiring over doubles: a connected check asks the provider
    // once its local readings are in; one a list outdated first asks
    // nothing, since curl's lookup of the provider's name could then leave
    // by another network, and a question already out is ended.
    const leakChecker = () => {
        const owner = { run: null, value: null, lastKill: null, rows: null, action: null, missing: [], signalled: [],
            deadline: { restart() {}, stop() {} }, statusWanted() {}, console: { log() {} } };
        owner.root = owner;
        for (const key of ["link", "ipv4", "ipv6", "dns", "public"])
            owner[key + "Reader"] = { key, running: false, completion: "old", command: [], signal(code) { owner.signalled.push([key, code]); } };
        for (const name of ["judgeStale", "start", "statusRead", "launch", "ended", "linked", "settle", "finish"]) sourceFn(leak, owner, name);
        return owner;
    };
    const readLocal = (owner, beforeDns) => {
        owner.start(HOME, true);
        owner.ended("link", 0, text("link.txt"), "", "");
        owner.statusRead(null);
        owner.ended("ipv4", 0, text("route-tunnel.json"), "", "");
        owner.ended("ipv6", 0, text("route-tunnel.json"), "", "");
        beforeDns(owner);
        owner.ended("dns", 0, text("dns-tunnel.json"), "", "");
    };
    const disconnect = owner => {
        owner.rows = listed("");
        owner.judgeStale();
    };
    const asking = leakChecker();
    readLocal(asking, () => {});
    assert.deepEqual(plain([asking.publicReader.running, asking.publicReader.command]), [true, plain(logic.insightsArgv("wg-home"))], "a connected check asks through the tunnel");
    const droppedFirst = leakChecker();
    readLocal(droppedFirst, disconnect);
    assert.deepEqual(plain([droppedFirst.publicReader.running, droppedFirst.run, droppedFirst.value]), [false, null, { uuid: HOME, busy: false, active: true, result: null }],
        "a disconnect before the last local reading asks nothing");
    const droppedAsking = leakChecker();
    readLocal(droppedAsking, () => {});
    disconnect(droppedAsking);
    assert.deepEqual(droppedAsking.signalled, [["public", 9]], "a disconnect ends the question already out");
    droppedAsking.publicReader.running = false;
    droppedAsking.ended("public", -1, "", "", "");
    assert.deepEqual(plain([droppedAsking.run, droppedAsking.value]), [null, { uuid: HOME, busy: false, active: true, result: null }], "the ended question leaves no result");

    // Check's IPC: a connected WireGuard profile or the one the state file
    // names; another type is refused whatever its state.
    const activated = payload.rows.find(row => row.uuid === HOME);
    const off = payload.rows.find(row => row.uuid === LAB);
    const plugin = Object.assign({}, payload, { rows: payload.rows.map(row => row.uuid === OFFICE ? Object.assign({}, row, { state: "activated" }) : row) });
    assert.deepEqual(plain(logic.profileCommand({ kind: "profile-check", id: activated.uuid }, payload, [])), { check: activated.uuid });
    assert.deepEqual(plain(logic.profileCommand({ kind: "profile-check", id: off.uuid }, payload, [], true, "")), { refusal: "refused: profile=state" });
    assert.deepEqual(plain(logic.profileCommand({ kind: "profile-check", id: off.uuid }, payload, [], true, off.uuid.toUpperCase())), { check: off.uuid });
    assert.deepEqual(plain(logic.profileCommand({ kind: "profile-check", id: OFFICE }, plugin, [])), { refusal: "refused: profile=type" });
    assert.deepEqual(plain(logic.profileCommand({ kind: "profile-check", id: OFFICE }, plugin, [], true, OFFICE)), { refusal: "refused: profile=type" });
}

// Connect automatically (VGS-2399). One table judges the decision over a
// run of list reads, each the world nmcli prints: list.txt's profiles with
// Home tunnel off, Fixture Wi-Fi, which the setting trusts, Hotel Wi-Fi on
// no list and a wired profile, which no setting can trust, with the user's
// deliberate off between reads. Lab tunnel is the chosen profile.
const HOTEL = "7a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d";
const WIFI = "0f3e2d1c-4b5a-4968-8776-5a4b3c2d1e0f";
const WIRED = "3c9d8e7f-6a5b-4c4d-9e3f-2a1b0c9d8e7f";
const TWIN = "6d5c4b3a-2f1e-4d0c-9b8a-7f6e5d4c3b2a";
const GONE = "11111111-2222-4333-8444-555555555555";
const UP = "activated";
// A list read of WORLD: { home, lab, wifi, hotel, wired } states, "" for
// off, and `extra` lines as nmcli prints them.
function autoWorld(world) {
    const states = { [HOME]: world.home || "", [LAB]: world.lab || "", [WIFI]: world.wifi || "" };
    const lines = text("list.txt").split("\n").filter(line => line !== "").map(line => {
        const fields = line.split(":");
        const uuid = fields[fields.length - 3];
        if (states[uuid] === undefined) return line;
        return fields.slice(0, -1).concat([states[uuid]]).join(":");
    });
    lines.push("Hotel Wi-Fi:" + HOTEL + ":802-11-wireless:" + (world.hotel || ""), "Hotel Ethernet:" + WIRED + ":802-3-ethernet:" + (world.wired || ""));
    return lines.concat(world.extra === undefined ? [] : [world.extra]).join("\n") + "\n";
}
// The service's inputs for one read of [code, output], as Service.qml
// hands them on (VpnLogic.list, compose and networkList).
function autoRead(logic, code, output) {
    return { networks: plain(logic.networkList(code, output)), profiles: plain(logic.compose(logic.list(code, output), {}, {}, {}, null, "")) };
}

function autoConnectSuite(logic, service = serviceSource) {
    // Each step a read of its world, with `choice` the setting's profile
    // (Lab tunnel unless set), `trusted` the setting's items (Fixture Wi-Fi
    // unless set), `busy` while a change runs and `raw` a read's own
    // [code, output]; or "off", the user turning a profile off.
    const run = steps => {
        let memory = logic.autoConnectStart();
        let last = null;
        for (const step of steps) {
            if (step === "off") { memory = plain(logic.autoConnectOff(memory)); continue; }
            const [code, output] = step.raw || [0, autoWorld(step)];
            const read = autoRead(logic, code, output);
            const trusted = logic.trustedUuids(step.trusted === undefined ? [{ name: "1", network: WIFI }] : step.trusted);
            last = plain(logic.autoConnectPlan(memory, step.choice === undefined ? LAB : step.choice, trusted, read.networks, read.profiles, step.busy === true));
            memory = last.memory;
        }
        return last;
    };
    // name, steps, why, the profile it connects, the problem's kind
    const AUTO_TABLE = [
        ["an untrusted network coming up connects the chosen profile", [{}, { hotel: UP }], "connect", LAB, null],
        ["the first readable list with an untrusted network up connects", [{ hotel: UP }], "connect", LAB, null],
        ["a trusted network coming up connects nothing", [{}, { wifi: UP }], "trusted", "", null],
        ["a trusted and an untrusted network up together connect", [{ wifi: UP }, { wifi: UP, hotel: UP }], "connect", LAB, null],
        ["a wired network on no list connects", [{}, { wired: UP }], "connect", LAB, null],
        ["a wired profile saved as trusted counts as untrusted", [{}, { wired: UP, trusted: [{ name: "1", network: WIRED }] }], "connect", LAB, null],
        ["a Bluetooth profile saved as trusted counts as untrusted", [{}, { extra: "Phone:" + TWIN + ":bluetooth:activated", trusted: [{ name: "1", network: TWIN }] }], "connect", LAB, null],
        ["a mobile profile saved as trusted counts as untrusted", [{}, { extra: "Carrier:" + TWIN + ":gsm:activated", trusted: [{ name: "1", network: TWIN }] }], "connect", LAB, null],
        ["an unknown uplink type is a network not trusted", [{ wifi: UP }, { wifi: UP, extra: "DSL:" + TWIN + ":pppoe:activated" }], "connect", LAB, null],
        ["trust follows the profile, not its name", [{}, { extra: "Fixture Wi-Fi:" + TWIN + ":802-11-wireless:activated" }], "connect", LAB, null],
        ["a trusted uuid in capitals is trusted", [{}, { wifi: UP, trusted: [{ name: "1", network: WIFI.toUpperCase() }] }], "trusted", "", null],
        ["an item with no network chosen trusts nothing", [{}, { wifi: UP, trusted: [{ name: "1", network: "" }] }], "connect", LAB, null],
        ["a network change is decided once", [{}, { hotel: UP }, { hotel: UP }], "settled", "", null],
        ["a deliberate off stays off on the same network", [{}, { hotel: UP, lab: UP }, "off", { hotel: UP }], "settled", "", null],
        ["a deliberate off during an undecided change stays off on the same network", [{}, { hotel: UP, lab: UP, busy: true }, "off", { hotel: UP }], "settled", "", null],
        ["a deliberate off holds until the next network change", [{}, { hotel: UP, lab: UP, busy: true }, "off", { hotel: UP }, { wired: UP }], "connect", LAB, null],
        ["an unreadable network list connects nothing and says why", [{}, { raw: [10, ""] }], "unread", "", "unread"],
        ["NetworkManager not running is an unreadable list", [{ hotel: UP, busy: true }, { raw: [8, ""] }], "unread", "", "unread"],
        ["a network row outside the grammar is an unreadable list", [{}, { hotel: UP, extra: "Lobby:not-a-uuid:802-11-wireless:activated" }], "unread", "", "unread"],
        ["a profile row outside the grammar is an unreadable list", [{}, { hotel: UP, extra: "Bad:" + GONE + ":vpn:connected" }], "unread", "", "unread"],
        ["the read after an unreadable one decides the change it shows", [{}, { raw: [10, ""] }, { hotel: UP }], "connect", LAB, null],
        ["an unreadable read keeps a change still undecided", [{}, { hotel: UP, busy: true }, { raw: [10, ""] }, { hotel: UP }], "connect", LAB, null],
        ["a change in flight keeps the network change", [{}, { hotel: UP, busy: true }], "waiting", "", null],
        ["the read after a change in flight connects", [{}, { hotel: UP, busy: true }, { hotel: UP }], "connect", LAB, null],
        ["a VPN profile already up is left alone", [{}, { hotel: UP, home: UP }], "connected", "", null],
        ["a VPN profile connecting is left alone", [{}, { hotel: UP, lab: "activating" }], "connected", "", null],
        ["no network up connects nothing", [{ wifi: UP }, {}], "offline", "", null],
        ["a tun up is no network", [{ wifi: UP }, { extra: "tailscale0:" + TWIN + ":tun:activated" }], "offline", "", null],
        ["a bridge up is no network", [{ wifi: UP }, { extra: "docker0:" + TWIN + ":bridge:activated" }], "offline", "", null],
        ["with Connect automatically off nothing connects", [{ hotel: UP, choice: "" }], "off", "", null],
        ["choosing a profile connects nothing until the network changes", [{ hotel: UP, choice: "" }, { hotel: UP }], "settled", "", null],
        ["a chosen profile in capitals connects by its uuid", [{}, { hotel: UP, choice: LAB.toUpperCase() }], "connect", LAB, null],
        ["a chosen profile no longer listed says why", [{ hotel: UP, choice: GONE }], "gone", "", "gone"]
    ];
    for (const [name, steps, why, uuid, problem] of AUTO_TABLE) {
        const got = run(steps);
        assert.deepEqual([got.why, got.uuid, got.memory.problem === null ? null : got.memory.problem.kind], [why, uuid, problem], name);
        assert.equal(logic.autoConnectText(got.memory.problem) !== "", problem !== null, name + ": a problem has its line");
    }

    // The networks and choices the service publishes: Settings' selects
    // take printable labels of at most STATUS_LABEL_MAX characters, each
    // value once, at most STATUS_LIST_MAX of them, the active networks
    // first.
    const crowd = Array.from({ length: 80 }, (_, i) => "Net\u0007" + "界".repeat(70) + ":" + String(i).padStart(8, "0") + "-0000-4000-8000-000000000000:802-11-wireless:" + (i === 79 ? UP : ""));
    const many = plain(logic.networkList(0, crowd.join("\n")));
    assert.equal(many.count, 80);
    assert.deepEqual([many.active, many.activeWifi], [["00000079-0000-4000-8000-000000000000"], ["00000079-0000-4000-8000-000000000000"]]);
    // A saved network's name reaches labels as text: no `<` for markup.
    assert.deepEqual(plain(logic.networkList(0, "<img src=x> Lobby:" + TWIN + ":802-11-wireless:\n").rows).map(row => row.name), ["img src=x> Lobby"]);
    assert.equal(many.rows[0].uuid, "00000079-0000-4000-8000-000000000000", "an active network comes first");
    const published = read => {
        const manifestOk = core.validateManifest(manifest, "/p");
        assert.equal(manifestOk.ok, true, manifestOk.error);
        let values = {};
        for (const [key, value] of [["networks", read.networks], ["networkChoices", logic.networkChoices(read.networks)], ["vpnChoices", logic.vpnChoices(read.profiles)]]) {
            const result = core.statusWrite(manifestOk.manifest, values, key, plain(value));
            assert.equal(result.ok, true, key + ": " + result.error);
            values = plain(result.values);
        }
        return values;
    };
    const wide = published({ networks: many, profiles: autoRead(logic, 0, autoWorld({})).profiles });
    assert.equal(wide.networkChoices.length, logic.NETWORK_MAX);
    const fixtureValues = published(autoRead(logic, 0, autoWorld({ hotel: UP })));
    // Only Wi-Fi profiles are offered to trust, the active ones first.
    assert.deepEqual(fixtureValues.networkChoices.map(choice => choice.value), [HOTEL, WIFI]);
    assert.deepEqual(fixtureValues.vpnChoices.map(choice => choice.value), ["off", HOME, OFFICE, TRAVEL, CAMPUS, BRANCH, LAB]);
    // Settings stores what Off stands for as the empty setting.
    assert.equal(plain(core.settingChoices(core.validateManifest(manifest, "/p").manifest, fixtureValues, { autoConnect: "", trustedNetworks: [] })).autoConnect[0].value, "");

    // The section's Trusted networks switch: the setting's other items
    // stay; a new item takes the lowest whole number no item names, as the
    // Settings list editor's; turning one off removes it whatever its case.
    const items = [{ name: "1", network: "" }, { name: "2", network: WIRED }];
    assert.deepEqual(plain(logic.trustedChange(items, WIFI, true)), items.concat([{ name: "3", network: WIFI }]));
    assert.deepEqual(plain(logic.trustedChange(items.concat([{ name: "3", network: WIFI }]), WIFI, true)), items.concat([{ name: "3", network: WIFI }]));
    assert.deepEqual(plain(logic.trustedChange([{ name: "2", network: WIFI.toUpperCase() }, { name: "1", network: WIRED }], WIFI, false)), [{ name: "1", network: WIRED }]);
    assert.deepEqual(plain(logic.trustedChange(undefined, WIFI, true)), [{ name: "1", network: WIFI }]);

    // A refusal or failure kept for one profile goes when another is chosen,
    // or when its own profile connects.
    const hotelRead = autoRead(logic, 0, autoWorld({ hotel: UP }));
    for (const [name, choice, uuid, read, kept] of [["the same profile", LAB, LAB, hotelRead, true], ["another profile", LAB, OFFICE, hotelRead, false],
        ["its profile now connected", LAB, LAB, autoRead(logic, 0, autoWorld({ hotel: UP, lab: UP })), false]]) {
        for (const kind of ["refused", "failed"]) {
            const memory = { seen: HOTEL, pending: false, problem: { kind, uuid, name: "a profile", reason: "" } };
            const got = plain(logic.autoConnectPlan(memory, choice, [WIFI], read.networks, read.profiles, false));
            assert.equal(got.memory.problem === null ? null : got.memory.problem.kind, kept ? kind : null, kind + " of " + name);
        }
    }

    // What the switch's own answer leaves: a refusal that lasts is the
    // problem line; one a passing state gives, and a busy service, keep the
    // network change pending for the next read.
    const officeRow = hotelRead.profiles.rows.find(row => row.uuid === OFFICE);
    for (const [reply, pending, problem] of [["ok", false, null], ["busy", true, null], ["refused: profile=reading", true, null],
        ["refused: profile=no-answer", true, null], ["refused: profile=connecting", true, null], ["refused: profile=state", true, null],
        ["refused: profile=unavailable", true, null], ["refused: profile=kill-switch", false, "refused"], ["refused: profile=plugin-needed", false, "refused"],
        ["refused: profile=sign-in", false, "refused"], ["refused: profile=unsupported", false, "refused"]]) {
        const got = plain(logic.autoConnectReply({ seen: HOTEL, pending: false, problem: null }, reply, officeRow, "a reason"));
        assert.deepEqual([got.pending, got.problem === null ? null : got.problem.kind], [pending, problem], reply);
    }

    // The service's decision over doubles: a connect goes through the
    // switch's own IPC action; a lasting refusal leaves its problem line,
    // which a later read of the same network keeps; a passing one keeps the
    // change; a change or a write in flight, or a kill switch step not yet
    // read, waits, and the step's reading decides again; a connect that
    // starts and then fails leaves its line.
    const serviceFunction = (owner, name) => {
        const found = new RegExp("function " + name + "\\(([^)]*)\\) \\{([\\s\\S]*?)\\n    \\}").exec(service);
        assert.ok(found, name);
        const params = found[1].split(",").map(param => param.trim()).filter(param => param !== "");
        owner[name] = new Function("Logic", "owner", "console", ...params, "with (owner) {" + found[2] + "}").bind(null, logic, owner, { log() {}, warn() {} });
    };
    const autoOwner = (reply, fields = {}) => {
        const owner = Object.assign({ registered: true, autoMemory: logic.autoConnectStart(), autoChoice: LAB, autoAction: "", trusted: [WIFI],
            networks: hotelRead.networks, profiles: hotelRead.profiles, profileAction: null, stateWrite: null, killStep: { state: "absent", reason: "" },
            killSwitch: null, shell: { requirements: { missing: [] } }, asked: [],
            actProfile(request) { owner.asked.push(plain(request)); return reply; } }, fields);
        for (const name of ["autoConnect", "autoRetry", "autoEnded"]) serviceFunction(owner, name);
        return owner;
    };
    const connected = autoOwner("ok");
    connected.autoConnect();
    assert.deepEqual(connected.asked, [{ kind: "profile-up", id: LAB }]);
    assert.deepEqual(plain([connected.autoMemory, connected.autoAction]), [{ seen: HOTEL, pending: false, problem: null }, LAB]);
    connected.autoEnded(LAB, true, "NetworkManager could not connect Lab tunnel.");
    assert.deepEqual(plain([connected.autoAction, connected.autoMemory.problem]),
        ["", { kind: "failed", uuid: LAB, name: "Lab tunnel", reason: "NetworkManager could not connect Lab tunnel." }], "a started connect that fails leaves its line");
    assert.notEqual(logic.autoConnectText(connected.autoMemory.problem), "");
    connected.autoConnect();
    assert.deepEqual([connected.asked.length, connected.autoMemory.problem.kind], [1, "failed"], "the same network keeps the failure's line");
    const succeeded = autoOwner("ok");
    succeeded.autoConnect();
    succeeded.autoEnded(LAB, false, "");
    assert.deepEqual(plain([succeeded.autoAction, succeeded.autoMemory.problem]), ["", null]);
    const busy = autoOwner("busy");
    busy.autoConnect();
    assert.deepEqual(plain([busy.autoMemory.pending, busy.autoMemory.problem, busy.autoAction]), [true, null, ""], "a busy service keeps the network change");
    const refused = autoOwner("refused: profile=plugin-needed", { autoChoice: OFFICE });
    refused.autoConnect();
    assert.deepEqual(refused.asked, [{ kind: "profile-up", id: OFFICE }]);
    assert.deepEqual([refused.autoMemory.pending, refused.autoMemory.problem.kind, refused.autoMemory.problem.name], [false, "refused", "Office VPN"]);
    assert.notEqual(refused.autoMemory.problem.reason, "", "the refusal carries the reason the switch shows");
    refused.autoConnect();
    assert.deepEqual([refused.asked.length, refused.autoMemory.problem.kind], [1, "refused"], "the same network keeps the refusal's line");
    const reading = autoOwner("refused: profile=reading", { autoChoice: OFFICE });
    reading.autoConnect();
    assert.deepEqual(plain([reading.autoMemory.pending, reading.autoMemory.problem]), [true, null], "a profile still read keeps the change pending");
    for (const [name, fields] of [["a change in flight", { profileAction: { kind: "profile-down", uuid: HOME, name: "Home tunnel" } }],
        ["a kill switch write", { stateWrite: { serial: 1, phase: "read" } }], ["a kill switch step not yet read", { killStep: undefined }]]) {
        const waiting = autoOwner("ok", fields);
        waiting.autoConnect();
        assert.deepEqual([waiting.asked.length, waiting.autoMemory.pending], [0, true], name + " waits");
    }
    // The list lands before the step's first reading: nothing connects
    // until it reads, then the change is decided again.
    const unprobed = autoOwner("ok", { killStep: undefined });
    unprobed.autoConnect();
    unprobed.autoRetry();
    assert.equal(unprobed.asked.length, 0, "nothing connects before the step reads");
    unprobed.killStep = { state: "ready", reason: "granted" };
    unprobed.autoRetry();
    assert.deepEqual(unprobed.asked, [{ kind: "profile-up", id: LAB }], "the step's reading decides the waiting change");
}

suite(load(file, commons));
editorSuite(load(file, commons));
leakCheckSuite(load(file, commons));
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "vpn-logic-"));
try {
    const source = fs.readFileSync(file, "utf8");
    for (const [name, needle, replacement] of [
        ["pending details block connect", 'row.details === "reading"', 'false'],
        ["failed details block connect", 'row.details === "no-answer"', 'false']
    ]) {
        assert.equal(source.split(needle).length - 1, 1, name);
        const mutant = path.join(scratch, "VpnLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, replacement));
        assert.throws(() => vpnReadinessSuite(load(mutant, commons)), undefined, "control: " + name);
        console.log("vpn-logic: control=" + name + " red");
    }
    for (const [name, sourceText, needle, replacement, target] of [
        ["editor create type", source, '"--type=vpn"', '"--type=ethernet"', "logic"],
        ["editor edit uuid", source, '"--edit=" + row.uuid', '"--edit=" + row.name', "logic"],
        ["editor absent refusal", source, 'candidate.uuid === uuid);\n    if (row === undefined) return { refusal: "refused: profile=absent" };\n    return { argv: ["nm-connection-editor"', 'true);\n    if (row === undefined) return { refusal: "refused: profile=absent" };\n    return { argv: ["nm-connection-editor"', "logic"],
        ["editor missing offer", bodySource, 'missing ? shell.requirements.offer(["nm-connection-editor"])', 'false ? shell.requirements.offer(["nm-connection-editor"])', "body"],
        ["only launched edits invalidate credentials", bodySource, '!missing && reply === "ok" && kind === "edit"', 'true', "body"],
        ["editor handoff refreshes its UUID", bodySource, 'shell.ipc.call("refresh", uuid)', 'shell.ipc.call("refresh", "")', "body"],
        ["recreated panes reread metadata", bodySource, 'if (expanded && shell !== null)\n            answered(shell.ipc.call("refresh", "")', 'if (false)\n            answered(shell.ipc.call("refresh", "")', "body"]
    ]) {
        assert.equal(sourceText.split(needle).length - 1, 1, name);
        const changed = sourceText.replace(needle, replacement);
        const mutant = path.join(scratch, "VpnLogic.js");
        if (target === "logic") fs.writeFileSync(mutant, changed);
        assert.throws(() => editorSuite(load(target === "logic" ? mutant : file, commons), target === "body" ? changed : bodySource), undefined, "control: " + name);
        console.log("vpn-logic: control=" + name + " red");
    }

    const parserSource = fs.readFileSync(nmcliFile, "utf8");
    const parserNeedle = 'else if (c === "\\\\") escaped = true;';
    assert.equal(parserSource.split(parserNeedle).length - 1, 1);
    const parserMutant = path.join(scratch, "Nmcli.js");
    fs.writeFileSync(parserMutant, parserSource.replace(parserNeedle, 'else if (c === "\\\\") out[out.length - 1] += c;'));
    assert.throws(() => suite(load(file, { "qs.Commons 1.0": Object.assign({}, commons["qs.Commons 1.0"], { Nmcli: load(parserMutant) }) })));
    console.log("vpn-logic: control=nmcli escaping red");
    for (const [name, needle, replacement] of [
        ["VPN profiles exclude other types", 'fields[2] !== "vpn" && fields[2] !== "wireguard"', 'false'],
        ["active profiles survive list limits", 'const activeCount = rows.filter(', 'const activeCount = rows.slice(0, PROFILE_MAX).filter('],
        ["NetworkManager not running is its own state", 'if (code === 8) return emptyProfiles("not-running");', ''],
        ["a record starts at its uuid line", 'if (name === "connection.uuid") {', 'if (name === "connection.uuid" && uuid === "") {'],
        ["only the server key is read", 'entry.slice(0, split) !== wanted', 'false'],
        ["an escaped comma stays inside its pair", 'if (c === "\\\\" && i + 1 < data.length)', 'if (false)'],
        ["the first OpenVPN remote is the server", 'value = value.split(/\\\\,|,/)[0].trim();', ''],
        ["the first WireGuard peer's endpoint", 'const first = peers.split(", ")[0];', 'const first = peers;'],
        ["the address waits for activation", 'if (!/^GENERAL\\.STATE:activated$/m.test(output)) return "";', ''],
        ["one password on a single-password service", 'missing.length === 1 && ', ''],
        ["a missing plugin is classified", 'if (plugin !== null) return', 'if (false) return'],
        ["an unknown delete is no failure", 'UNKNOWN_CONNECTION.test(String(text)) ? "gone"', 'false ? "gone"'],
        ["OpenConnect cannot connect here", 'row.service === "openconnect"', 'false'],
        ["a missing plugin blocks its profile", '(!declaredPlugin && row.failure === "plugin-needed")', '(false)'],
        ["an address shows only while activated", 'row.state === "activated" && typeof addresses', 'typeof addresses'],
        ["a blocked switch refuses its IPC", 'if (view.reason !== "") return', 'if (false) return'],
        ["profile argv names uuid", '"up", "uuid", row.uuid]', '"up", "id", row.name]'],
        ["profile lists are bounded", 'rows: rows.slice(0, PROFILE_MAX)', 'rows: rows'],
        ["no profiles hides the icon", ' || profiles.count === 0', ''],
        ["a rescan clears a sign-in failure", 'failures[uuid].kind !== "sign-in" && ', ''],
        ["a rescan keeps the bar's failures", 'kept[uuid] = failures[uuid];', '{}'],
        ["editor clears every target failure", ': uuid !== editedUuid;', ': true;'],
        ["editor preserves other profile failures", ': uuid !== editedUuid;', ': false;'],
        ["a problem goes with its profile", 'if (row === undefined) return null;', ''],
        ["a connect's problem goes with its failure", 'if (problem.kind === "profile-up" && failures[problem.uuid] === undefined) return null;', ''],
        ["a disconnect's problem goes once the profile is down", 'if (problem.kind === "profile-down" && row.state === "") return null;', ''],
        ["a password failure raises the alert", 'row.failure === "needs-password" || row.failure === "failed"', 'row.failure === "failed"'],
        ["a drawn line holds no markup start", "\\u007f<]/g", "\\u007f]/g"],
        ["a backslash is escaped", String.raw`password.replace(/\\/g, "\\\\")`, "password"],
        ["CR and LF are escaped", String.raw`.replace(/\r/g, "\\r").replace(/\n/g, "\\n")`, ""],
        ["leading whitespace is escaped", "edge(parts[1])", "parts[1]"],
        ["trailing whitespace is escaped", "edge(parts[3])", "parts[3]"],
        ["an empty password is refused", 'password === "" || ', ""],
        ["a NUL is refused", String.raw` || password.indexOf("\u0000") !== -1`, ""],
        ["a password nmcli cannot read reaches no owner", 'if (text === null) return "refused: password=value";', ""],
        ["no owner answers unavailable", 'if (connectOwner === null) return "unavailable";', ""],
        ["only the owner releases itself", "if (connectOwner === owner) connectOwner = null;", "connectOwner = null;"],
        ["the feed closes stdin", "process.stdinEnabled = false;", ""],
        ["a carried password reads password-tried", "if (carried === true)", "if (false)"],
        ["a carried second secret reads sign-in", 'missing.some(name => name !== PASSWORD_ENTRY) ? "sign-in" : "password-tried"', '"password-tried"'],
        ["password-tried reads Needs password", 'row.failure === "needs-password" || row.failure === "password-tried") return view(', 'row.failure === "needs-password") return view('],
        ["password-tried raises the alert", ' || row.failure === "password-tried"));', "));"],
        ["only Needs password takes a password", 'if (rowView(row, profiles, missing, killOn).key !== "needs-password") return { refusal: "refused: profile=state" };', ""],
        ["the core scan blocks OpenVPN before connect", '(missing || []).indexOf(OPENVPN_SERVICE) !== -1', "false"],
        ["the password connect never asks", '"passwd-file", "/dev/stdin"]', '"passwd-file", "/dev/stdin", "--ask"]'],
        ["status rows are trimmed to their budget", "profiles.rows.pop();", "break;"],
        ["a missing key is malformed", "if (Object.keys(fields).length !== 4) return malformed;", ""],
        ["a repeated key is malformed", "if (Object.prototype.hasOwnProperty.call(fields, key)) return malformed;", ""],
        ["the portal time is kept", "portalUntil: base.portalUntil", 'portalUntil: "0"'],
        ["a missing file reads as off", 'file.kind === "missing" ? { meantOn: "", mode: "off"', 'file.kind === "missing" ? { meantOn: "", mode: "block"'],
        ["a malformed file fails closed", 'file.kind === "malformed" ? { meantOn: "", mode: "block"', 'file.kind === "malformed" ? { meantOn: "", mode: "off"'],
        ["an unread file is not written", "if (base === null) return null;", 'if (base === null) return stateText({ meantOn: "", mode: "off", portalUntil: "0" });'],
        ["a disconnect clears only its own profile", 'if (named === uuid || file.kind === "malformed")', 'if (true)'],
        ["the switch on refuses a profile that is not WireGuard", 'if (mode !== "off" && type !== "wireguard") return { refuse', 'if (false) return { refuse'],
        ["a malformed file's disconnect writes the off", ' || file.kind === "malformed") return { patch: { meantOn: "" }', ') return { patch: { meantOn: "" }'],
        ["only the written profile answers the wait", '    if (status.profile !== uuid) return "waiting";\n', ''],
        ["a read with no line is no answer", '    if (status.state === "unreachable" || status.state === "unreadable") return "failed";\n', ''],
        ["the status line names its profile", 'profile: found[5].toLowerCase() }', 'profile: "" }'],
        ["on, naming a connected profile, with no rule is danger", 'then turn it on again.", tone: "danger" });', 'then turn it on again.", tone: "" });'],
        ["a write's grace holds the danger line back", 'if (state.busy || state.settling || ', 'if (state.busy || '],
        ["a profile not connected gets no danger line", ' || meant === undefined || meant.state !== "activated") return view;', ') return view;'],
        ["naming a profile makes no plain claim", 'if (state.meantOn === "") return fill({ hint: "Starts when you connect a VPN here" });', 'if (true) return fill({ hint: "Starts when you connect a VPN here" });'],
        ["the kill switch marks a profile that is not WireGuard", 'if (killOn === true && row.type !== "wireguard")', 'if (false)'],
        ["an unrestored rollback says so", 'if (unrestored === true)', 'if (false)'],
        ["a wait with no line says VGS could not check", 'if (cause === "unchecked") return', 'if (false) return'],
        ["Set up has its own line", 'if (cause === "setup")', 'if (false)'],
        ["the switch off waits for nothing", 'arm: mode !== "off"', "arm: true"],
        ["only holding or passing is armed", 'if (status.state === "holding" || status.state === "passing") return "armed";', 'if (status.state !== "unreachable") return "armed";'],
        ["a refused status read is unreachable", "const found = code === 0 ?", "const found = true ?"],
        ["the temporary file is dot-prefixed", 'return STATE_DIR + "/.state." + name;', 'return STATE_DIR + "/state." + name;'],
        ["an unreadable status is its own reading", "const unreadable = code === 1 &&", "const unreadable = false &&"],
        ["an unsupported profile reads in the danger colour", '" to end the block.", tone: "danger" });', '" to end the block.", tone: "" });'],
        ["a step to apply shows Set up", 'case "setup": return fill({ setup: true,', 'case "setup": return fill({ setup: false,'],
        ["Allow local network shows only while on", "lanShown: on,", "lanShown: true,"],
        ["a write in flight disables the switches", 'reason: state.busy ? "Wait until VGS saves this setting." : ""', 'reason: ""'],
        ["only a holding read shows the blocked notice", '|| state.status.state !== "holding" ||', '|| state.status.state === "off" ||'],
        ["a holding line for another profile shows no notice", ' || state.status.profile !== named) return null;', ') return null;'],
        ["a connected or connecting profile shows no notice", 'if (meant.state === "activated" || meant.state === "activating" || motion(', 'if (motion('],
        ["a change in flight shows no notice", ' || motion(meant, profiles.action) !== "") return null;', ') return null;'],
        ["the count shows only beside the notice", '        if (blockedNotice(state, profiles) === null) return fill({ hint: "Blocking traffic outside the VPN" });\n', ''],
        ["one refusal reads singular", '(status.blocked === "1" ? " time" : " times")', '" times"'],
        ["the count carries its info", 'countInfo: KILL_COUNT_INFO });', 'countInfo: "" });'],
        ["the held profile reads Dropped", '    if (held === row.uuid) return view("dropped", "Dropped", { switchOn: true, reconnect: true });\n', ''],
        ["a held drop marks the bar with the danger dot", 'const stateDot = isPlain(notice) ? "danger" : "";', 'const stateDot = "";'],
        ["a held drop reads danger in Details", 'const tone = isPlain(notice) ? "danger" : ', 'const tone = false ? "danger" : '],
        ["the bar tooltip reads a held profile as the header does", 'warning: false, stateDot: stateDot,\n        tooltip: "VPN: " + summary(profiles, notice) };', 'warning: false, stateDot: stateDot,\n        tooltip: "VPN: " + summary(profiles) };'],
        ["an unlisted drop reads the drop", '    if (isPlain(notice)) {\n', '    if (isPlain(notice) && notice.uuid !== "") {\n'],
        ["a change in flight reads first in the line", '        if (moving === "connecting") return "Connecting to " + row.name;\n', ''],
        ["the bar's spinner tooltip is the line", 'stateDot: stateDot, tooltip: "VPN: " + summary(profiles, notice) };', 'stateDot: stateDot, tooltip: "VPN: Connecting" };'],
        ["a dropped profile offers Reconnect", 'view("dropped", "Dropped", { switchOn: true, reconnect: true })', 'view("dropped", "Dropped", { switchOn: true })'],
        ["the header names a held profile", 'return dropped === undefined ? "Dropped" : dropped.name + " dropped";', 'return "Dropped";'],
        ["the blocked notice needs the file to name a profile", 'state.file !== "valid" || state.meantOn === "") return null;', 'state.file !== "valid") return null;'],
        ["the blocked notice needs the switch on", 'if (!killSwitchOn(state) || state.file', 'if (!isPlain(state) || state.file'],
        ["an unlisted profile offers no disconnect", 'return { uuid: "", text: "The VPN dropped', 'return { uuid: state.meantOn, text: "The VPN dropped'],
        ["a dropped profile the file names turns off by its write", '        if (typeof meantOn === "string" && meantOn.toLowerCase() === row.uuid) return { argv: null };\n', ''],
        ["the Setup entry waits for the first probe", 'case "checking": return undefined;', 'case "checking": return { tone: "info", text: "Checking", action: false };']
    ]) {
        assert.equal(source.split(needle).length - 1, 1, name + " mutation must match once");
        const mutant = path.join(scratch, "VpnLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, replacement));
        assert.throws(() => name === "the core scan blocks OpenVPN before connect" ? vpnRequirementSuite(load(mutant, commons)) : suite(load(mutant, commons)), undefined, "control: " + name);
        console.log("vpn-logic: control=" + name + " red");
    }
    for (const [name, old, replacement] of [
        ["optional profile absence is informational", "if (code === 1 || code === 8) console.log(diagnostic);", "if (code === 1 || code === 8) console.warn(diagnostic);"],
        ["a failed detail read keeps nothing", "if (read === null) {", "if (false) {"],
        ["a failed detail read retries", 'root.detailsRead = "";', ""],
        ["a view lease preserves learned failures", "if (request.open) {\n            readProfiles();", "if (request.open) {\n            refresh();"],
        ["a successful up clears its failure", "if (code === 0) delete next[action.uuid];", "if (code === 0) {}"],
        ["a gone profile leaves no problem", 'Logic.removeOutcome(code, output) === "failed"', 'code !== 0'],
        ["no nmcli text reaches the log", '" code=" + code);\n            if (action.kind', '" code=" + code + " " + output);\n            if (action.kind'],
        ["a rescan applies the failure rule", "failures = Logic.afterRescan(failures, editedUuid);", ""],
        ["editor refresh passes its UUID", "Logic.afterRescan(failures, editedUuid)", "Logic.afterRescan(failures)"],
        ["a rescan prunes the problem line", "profileProblem = Logic.problemAfter(profileProblem, listing.rows, failures);", ""],
        ["a list prunes the problem line", "profileProblem = Logic.problemAfter(profileProblem, rows, failures);", ""],
        ["a failed action records its profile", "root.profileProblem = { uuid: action.uuid,", "root.profileProblem = { uuid: \"\","],
        ["missing import tools offer setup", "if (needed.length > 0)", "if (false)"],
        ["import availability", 'if (profiles.state !== "available")', 'if (false)'],
        ["import completion refreshes", '() => root.readProfiles()', '() => {}'],
        ["an unchanged uuid set reads no details", "if (Logic.detailsKey(next) !== detailsRead) readDetails();", "readDetails();"],
        ["an activated profile drops its failure", 'failures = kept(failures, row => row.state !== "activated");', "failures = kept(failures, row => true);"],
        ["a profile no longer activated drops its address", 'addresses = kept(addresses, row => row.state === "activated");', "addresses = kept(addresses, row => true);"],
        ["an activated profile with an address queues no read", 'row.state === "activated" && addresses[row.uuid] === undefined', 'row.state === "activated"'],
        ["a password connect opens stdin", "profileActor.stdinEnabled = connectFeed !== null;", "profileActor.stdinEnabled = false;"],
        ["a password connect is marked", "password: feed !== null }", "password: false }"],
        ["a password connect holds its feed", "connectFeed = feed;", ""],
        ["one change at a time", 'if (profileAction !== null || stateWrite !== null) return "busy";', ""],
        ["a connect with the switch on waits for the table", "if (plan === null || !plan.arm) {", "if (true) {"],
        ["only an armed table runs the connect", 'if (outcome === "armed") {', "if (true) {"],
        ["an unusable profile runs nothing", '} else if (outcome === "unavailable" && !stage.nudged) {', "} else if (false) {"],
        ["after a nudge a refusal waits for the deadline", '} else if (outcome === "unavailable" && !stage.nudged) {', '} else if (outcome === "unavailable") {'],
        ["a refusal read in the wait decides at its end", '        else if (stage.refusal !== "") rollBack("unavailable", stage.refusal);\n', ""],
        ["a nudge records the file's text", "stateWrite = Object.assign({}, stateWrite, { text: text, nudged: true });", "stateWrite = Object.assign({}, stateWrite, { nudged: true });"],
        ["a write's end takes the grace from a running read", "        killReader.settles = false;\n", ""],
        ["no write while a step still runs", " || stateModer.running || stateMover.running || pendingMaker.running) return", ") return"],
        ["the end of the wait runs nothing", 'else if (stage.expired) waitEnd();', 'else if (false) waitEnd();'],
        ["the rollback puts the previous profile back", "{ meantOn: previous } : null", '{ meantOn: "" } : null'],
        ["the file is read again before a write", "else stateFile.reload();", "else stateRead();"],
        ["an unchanged file is not written", "else if (text === stateFile.text()) {", "else if (false) {"],
        ["a connect nudges an unchanged file", "            if (!stateWrite.nudge) writeEnded(true);\n            else {", "            if (true) writeEnded(true);\n            else {"],
        ["a late chmod of an ended write is not a later write's", 'stateWrite.phase !== "mode" || stateWrite.serial !== serial) return;', 'stateWrite.phase !== "mode") return;'],
        ["a read the poll starts ends the grace", "        killReader.settles = killSettlePoll;\n", ""],
        ["a failed write runs nothing", 'if (!ok) {\n            stageEnded("write", "", false);', 'if (false) {\n            stageEnded("write", "", false);'],
        ["the switches take three modes", 'if (Logic.KILL_MODES.indexOf(mode) === -1) return "refused: kill-switch=mode";', ""],
        ["one state write at a time", 'if (stateWrite !== null || stage !== null) return "busy";', ""],
        ["a profile the switch refuses runs nothing", "if (plan !== null && plan.refuse !== undefined) {", "if (false) {"],
        ["the deadline marks a running read's wait", "        stage = Object.assign({}, stage, { expired: true });\n", ""],
        ["the deadline ends an idle wait", '        if (!killReader.running) waitEnd();', '        if (false) waitEnd();'],
        ["a wait that ends while the step reads needed points to Set up", 'if (Logic.stepWord(killStep) === "setup") rollBack("setup", "");', 'if (false) rollBack("setup", "");'],
        ["a wait that ends unarmed asks for a fresh probe first", 'const reply = shell === null ? "refused" : shell.system.refresh(() => root.probed());', 'const reply = "refused";'],
        ["a step that reads needed still takes the rollback", '        if (!killWritable) writeEnded(false);', '        if (!killReady) writeEnded(false);'],
        ["a wait records a read that answered", 'if (outcome !== "failed" && !stage.answered)', 'if (!stage.answered)'],
        ["a failed rollback is shown", "root.stageEnded(cause, reason, !ok);", "root.stageEnded(cause, reason, false);"],
        ["a read-back after the rename does not fail the write", '            if (stateFile.text() !== stateWrite.text) console.warn("vpn: operation=kill-switch-write completion=read-back-differs");\n            writeEnded(true);', '            writeEnded(stateFile.text() === stateWrite.text);'],
        ["a failed touch does not fail the write", 'if (code !== 0) console.warn("vpn: operation=kill-switch-pending completion=failed code=" + code);', 'if (code !== 0) { writeEnded(false); return; }'],
        ["one writer", 'if (stateWrite !== null || stateModer.running', 'if (stateModer.running'],
        ["the write's deadline ends the write", '        writeEnded(stateWrite.committed === true);\n    }\n    function writeEnded', '    }\n    function writeEnded'],
        ["the deadline signals a running step", "if (step.running) step.signal(9);", "if (false) step.signal(9);"],
        ["a late step of an ended write does nothing", '        if (stateWrite === null || stateWrite.phase !== "mode" || stateWrite.serial !== serial) return;\n', ''],
        ["a failed save removes its file", '        if (stateWrite !== null && stateWrite.phase === "save") removeTemp();', '        if (stateWrite !== null && stateWrite.phase === "save") writeEnded(false);'],
        ["the pending file is the state directory's", 'pendingMaker.command = ["touch", "--", Logic.PENDING_FILE];', 'pendingMaker.command = ["touch", "--", Logic.STATE_FILE];'],
        ["a write's end opens the grace", "        killSettling = true;\n", ""],
        ["the pending file follows the rename", "        pendingMaker.serial = stateWrite.serial;\n        pendingMaker.running = true;", "        pendingMade(0, stateWrite.serial);"],
        ["a failed step removes its file", "        tempRemover.running = true;", ""],
        ["the temporary file takes mode 0644 before the rename", '        stateWrite = Object.assign({}, stateWrite, { phase: "mode" });\n        stateModer.command = ["chmod", "0644", "--", stateWrite.temp];\n        stateModer.completion = null;\n        stateModer.serial = stateWrite.serial;\n        stateModer.running = true;', "        moded(0, stateWrite.serial);"],
        ["the started run drops its feed", "root.connectFeed = null;\n            if (once !== null)", "if (once !== null)"],
        ["a plain change drops a stale feed", "connectFeed = feed;", "if (feed !== null) connectFeed = feed;"],
        ["a plain change closes stdin", "profileActor.stdinEnabled = connectFeed !== null;", "if (connectFeed !== null) profileActor.stdinEnabled = true;"],
        ["the ended run drops its feed", "root.connectFeed = null;\n            profileActionDeadline.stop();", "profileActionDeadline.stop();"],
        ["destruction drops the feed", "Logic.releaseConnect(root);\n        connectFeed = null;", "Logic.releaseConnect(root);"],
        ["a password connect's failure is carried", "action.password === true)", "false)"],
        ["a run's end keeps the change in flight", '        profileAction = Object.assign({}, profileAction, { ended: true, stale: profilesReader.running });\n', '        profileAction = null;\n'],
        ["a read running at the run's end does not end it", '{ ended: true, stale: profilesReader.running }', '{ ended: true, stale: false }'],
        ["the list after the run ends it", '            profileAction = profileAction.stale ? Object.assign({}, profileAction, { stale: false }) : null;', '            profileAction = profileAction;'],
        ["a disconnect with no run ends the action", "        if (argv === null) {\n            profileAction = null;", "        if (false) {\n            profileAction = null;"],
        ["the service hands the file's profile to the plan", 'Logic.killSwitchOn(killSwitch), killReady ? killSwitch.meantOn : "");', 'Logic.killSwitchOn(killSwitch), "");'],
        ["a profile turned off here ends the pending change", 'if (request.kind === "profile-down" && reply === "ok") autoMemory = Logic.autoConnectOff(autoMemory);', ""],
        ["each list read decides Connect automatically", "        autoConnect();\n", ""],
        ["the read's networks are in place before the list decides", "root.networks = Logic.networkList(code, profilesText.text);", ""],
        ["the switch's answer reaches Connect automatically", "autoMemory = Logic.autoConnectReply(autoMemory, reply, row,", "autoMemory = Logic.autoConnectOff(autoMemory, reply, row,"],
        ["Connect automatically waits on a kill switch write", "stateWrite !== null || killStep === undefined);", "killStep === undefined);"],
        ["Connect automatically waits for the kill switch step's reading", "|| killStep === undefined);", ");"],
        ["an accepted automatic connect is followed to its end", 'if (reply === "ok") autoAction = row.uuid;', ""],
        ["a stage that stops an automatic connect leaves its line", "        autoEnded(ended.uuid, true, profileProblem.text);\n", ""],
        ["a connect's end reaches Connect automatically", 'if (action.kind === "profile-up") root.autoEnded(action.uuid, failed, failed ? root.profileProblem.text : "");', ""],
        ["a detail read's end decides again", "            else root.autoRetry();\n", ""]
    ]) {
        assert.equal(serviceSource.split(old).length - 1, 1, name);
        assert.throws(() => suite(load(file, commons), serviceSource.replace(old, replacement)), undefined, "control: " + name);
        console.log("vpn-logic: control=" + name + " red");
    }

    // The root script's own reader agrees with STATE_TABLE and reads
    // stateText's output back, and its status_pattern accepts exactly the
    // STATUS_TABLE lines killStatus accepts: its definitions, parse_state
    // and status_pattern run under bash from the shipped file, with
    // read_state's 4097-byte read.
    const root = fs.readFileSync(path.join(__dirname, "../config/system/kill-switch/vgs-kill-switch"), "utf8");
    const definition = name => {
        const found = new RegExp("^" + name + "=.*$", "m").exec(root);
        assert.ok(found, "the root script defines " + name);
        return found[0];
    };
    const parseState = /^parse_state\(\) \{\n[\s\S]*?\n\}$/m.exec(root);
    assert.ok(parseState, "the root script has parse_state");
    const definitions = ["digit", "hex", "word_char", "uuid_body", "uuid_pattern"].map(definition);
    const run = (script, args) => require("child_process").execFileSync("bash", ["--norc", "--noprofile", script, ...args],
        { env: { PATH: process.env.PATH, LC_ALL: "C" }, encoding: "utf8" });
    const asRoot = read => read.kind === "malformed" ? "malformed" : ["valid", read.meantOn === "" ? "-" : read.meantOn, read.mode, read.portalUntil].join(" ");
    const shipped = load(file, commons);
    // PARSE is parse_state's text, PATTERN status_pattern's line; each
    // disagreement throws.
    const rootAgrees = (parse, pattern) => {
        const reader = path.join(scratch, "parse-state.sh");
        fs.writeFileSync(reader, definitions.concat([parse,
            'state_text="$(head -c 4097 -- "$1")"', "state_present=1",
            'if ((${#state_text} > 4096)); then echo malformed; elif parse_state; then printf "valid %s %s %s\\n" "${meant_on:--}" "$kill_switch" "$portal_until"; else echo malformed; fi', ""]).join("\n"));
        const rootRead = input => {
            const at = path.join(scratch, "state");
            fs.writeFileSync(at, input);
            return run(reader, [at]).trim();
        };
        for (const [name, input, read] of STATE_TABLE) assert.equal(rootRead(input), asRoot(read), "the root script reads " + name);
        for (const fields of [{ meantOn: "", mode: "off", portalUntil: "0" }, { meantOn: HOME, mode: "block-lan", portalUntil: "1794203888" }])
            assert.equal(rootRead(shipped.stateText(fields)), asRoot(Object.assign({ kind: "valid" }, fields)), "the root script reads what VGS writes");
        const matcher = path.join(scratch, "status-pattern.sh");
        fs.writeFileSync(matcher, definitions.concat([pattern, 'for line; do if [[ $line =~ $status_pattern ]]; then echo accept; else echo refuse; fi; done', ""]).join("\n"));
        const lines = STATUS_TABLE.filter(row => row[0] === 0).map(row => row[1].replace(/\n$/, ""));
        const verdicts = run(matcher, lines).trim().split("\n");
        assert.equal(verdicts.length, lines.length, "the root's status_pattern judges every line");
        lines.forEach((text, i) => assert.equal(verdicts[i], shipped.killStatus(0, text + "\n").state === "unreachable" ? "refuse" : "accept", "status_pattern on " + JSON.stringify(text)));
    };
    rootAgrees(parseState[0], definition("status_pattern"));
    console.log("vpn-logic: root-script reader agrees");
    // The agreement fails on a root that reads otherwise: a parse_state
    // that takes version=2 and a status_pattern that takes state=armed.
    for (const [name, parse, pattern] of [
        ["parse_state", parseState[0].replace("[[ $value == 1 ]]", "[[ $value == [12] ]]"), definition("status_pattern")],
        ["status_pattern", parseState[0], definition("status_pattern").replace("(off|holding|passing|unavailable)", "(off|holding|passing|unavailable|armed)")]
    ]) {
        assert.notEqual(parse + pattern, parseState[0] + definition("status_pattern"), name + " mutation must change the text");
        assert.throws(() => rootAgrees(parse, pattern), undefined, "control: the agreement on " + name);
        console.log("vpn-logic: control=the root's " + name + " disagreeing red");
    }
    // Each Connect automatically control changes the shipped decision and
    // must redden its table.
    for (const [name, needle, replacement] of [
        ["a trusted network connects nothing", 'if (networks.active.every(uuid => networks.activeWifi.indexOf(uuid) !== -1 && trusted.indexOf(uuid) !== -1)) return plan("trusted", decided);', 'if (false) return plan("trusted", decided);'],
        ["only a Wi-Fi profile can be trusted", "networks.activeWifi.indexOf(uuid) !== -1 && trusted.indexOf(uuid)", "trusted.indexOf(uuid)"],
        ["a network name drops the markup it holds", "const text = clip(String(value)", "const text = String(String(value)"],
        ["a passing refusal keeps the change pending", "if (found === null || LASTING_REFUSALS.indexOf(found[1]) === -1) return", "if (found === null) return"],
        ["a kept problem belongs to the chosen profile", "&& memory.problem.uuid === wanted && row.state !== \"activated\" ? memory.problem : null;", "? memory.problem : null;"],
        ["an unreadable list decides nothing", 'if (!readable) return plan("unread",', 'if (false) return plan("unread",'],
        ["a deliberate off ends a pending change", "function autoConnectOff(memory) { return Object.assign({}, memory, { pending: false }); }", "function autoConnectOff(memory) { return memory; }"],
        ["the first readable list is a change", "const pending = memory.seen !== key || memory.pending;", "const pending = (memory.seen !== null && memory.seen !== key) || memory.pending;"],
        ["a network change is decided once", "const decided = { seen: key, pending: false, problem: null };", "const decided = { seen: key, pending: true, problem: null };"],
        ["a VPN profile up is left alone", 'if (profiles.rows.some(candidate => candidate.state === "activated" || candidate.state === "activating")) return plan("connected", decided);', ""],
        ["local connections are no network", "if (LOCAL_TYPES.indexOf(fields[2]) !== -1) continue;", 'if (fields[2] === "vpn" || fields[2] === "wireguard") continue;']
    ]) {
        const source = fs.readFileSync(file, "utf8");
        assert.equal(source.split(needle).length - 1, 1, name);
        const mutant = path.join(scratch, "VpnLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, replacement));
        assert.throws(() => autoConnectSuite(load(mutant, commons)), undefined, "control: " + name);
        console.log("vpn-logic: control=" + name + " red");
    }
    // Each leak check control changes the shipped judge or the service's
    // wiring and must redden the leak check suite.
    for (const [name, needle, replacement] of [
        ["the leak check reads WireGuard alone", 'return isPlain(row) && row.type === "wireguard";', "return isPlain(row);"],
        ["the tunnel's ~. takes unrouted lookups alone", "concat(root.length > 0 ? [] : unroutedLinks(dns))", "concat(unroutedLinks(dns))"],
        ["with no ~., lookups go to default-route links", "dns.scopes.filter(scope => scope.defaultRoute)", "dns.scopes.filter(scope => false)"],
        ["a domain on another link takes lookups", 'const named = dns.scopes.filter(scope => scope.domains.some(domain => domain !== "." && !tailnetOnly(scope, domain)));', "const named = [];"],
        ["Tailscale's own domains take no internet name", " && !tailnetOnly(scope, domain)", ""],
        ["only Tailscale's own zones on tailscale0 are exempt", 'return scope.link === "tailscale0" && TAILNET_ZONE.test(domain);', 'return scope.link === "tailscale0";'],
        ["global servers take unrouted lookups", "defaultRoute: global || entry.defaultRoute", "defaultRoute: entry.defaultRoute === true"],
        ["with no default route, lookups go to the fallback servers", "return links.length === 0 && dns.fallback ? [GLOBAL_DNS] : links;", "return links;"],
        ["lookups are judged only while resolv.conf names resolved's stub", "if (RESOLVED_MODES.indexOf(mode) === -1) return unreadable;", ""],
        ["the provider's own name decides whether VGS asks", ": nameLinks(readings.dns, host);", ": lookupLinks(readings.dns);"],
        ["a name goes to its longest matching domain", "if (depth > best) { best = depth; links = []; }", "if (depth > best) best = depth;"],
        ["a domain matches whole labels", 'name !== domain && !name.endsWith("." + domain)', "!name.endsWith(domain)"],
        ["a question VGS did not ask reads as not checked", 'NOT_ASKED.indexOf(reason) !== -1 ? "Not checked" : "Could not check"', '"Could not check"'],
        ["an unreadable route is unknown", 'reading.kind === "none" ? [] : unread(reading);', 'reading.kind === "none" ? [] : [];'],
        ["the armed kill switch blocks", 'if (kill.state === "holding" || kill.state === "on") return verdict("blocked"', 'if (false) return verdict("blocked"'],
        ["an unread kill switch is unknown", 'return kill.state === "unknown" ? unknown("kill") :', "return false ? unknown(\"kill\") :"],
        ["the links the kill switch passes leak", 'if (passed !== undefined) return verdict("leak", passed);', ""],
        ["the provider is asked only with lookups in the tunnel", 'if (dns === "tunnel" || dns === "blocked") return', "if (true) return"],
        ["a step rules out a table only for its reasons", "KILL_RULED_OUT.indexOf(step.reason) !== -1", "true"],
        ["an absent step rules out a table", 'return word === "absent" || (', "return ("],
        ["a missing status command is no table only while not set up", "return !ready && !started ? null : status;", "return !started ? null : status;"],
        ["a list that outdates a result drops it", 'return row === undefined || (row.state === "activated") !== check.active;', "return false;"],
        ["a change in flight holds its own profile", "if (isPlain(action) && action.uuid === check.uuid) return false;", ""],
        ["the kill switch line hides while off", 'killShown: result.kill.state !== "off"', "killShown: true"],
        ["the count rises only above the last check's", "rising: previous !== \"\" && countAbove(status.blocked, previous)", "rising: previous !== \"\""],
        ["the answer's address is IPv4", "!IPV4.test(answer.ip)", "false"],
        ["the answer's country is short text", 'if (country === null || country === "" || city === null)', "if (false)"],
        ["the question goes through the tunnel", '"--interface", "if!" + link,', '"--interface", link,'],
        ["no route out is no leak", 'if (code === 2 && NO_ROUTE.test(', 'if (false && NO_ROUTE.test(']
    ]) {
        const source = fs.readFileSync(file, "utf8");
        assert.equal(source.split(needle).length - 1, 1, name);
        const mutant = path.join(scratch, "VpnLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, replacement));
        assert.throws(() => leakCheckSuite(load(mutant, commons)), undefined, "control: " + name);
        console.log("vpn-logic: control=" + name + " red");
    }
    for (const [name, needle, replacement] of [
        ["a connect's check starts for WireGuard alone", "if (!Logic.checkReads(profiles.rows.find", "if (false && !Logic.checkReads(profiles.rows.find"],
        ["the check's status read runs while the step is not set up", "if (!registered || !(killReady || checkWantsStatus)) return;", "if (!registered || !killReady) return;"],
        ["a step that rules out a table hands none", 'if (Logic.checkKillPlan(killStep) === "none") {', "if (!killReady) {"],
        ["the check's own read leaves the switch's reading", "            if (root.killReady) {\n                const failed", "            if (true) {\n                const failed"],
        ["the status read hands the check its reading", "leakCheck.statusRead(Logic.checkKillStatus(root.killReady, next, completion !== null));", "leakCheck.statusRead(next);"]
    ]) {
        assert.equal(serviceSource.split(needle).length - 1, 1, name);
        assert.throws(() => leakCheckSuite(load(file, commons), serviceSource.replace(needle, replacement)), undefined, "control: " + name);
        console.log("vpn-logic: control=" + name + " red");
    }
    for (const [name, needle, replacement] of [
        ["a dropped check asks the provider nothing", 'run.dropped ? { kind: "failed", reason: "inactive" } : Logic.publicPlan(run.readings)', "Logic.publicPlan(run.readings)"],
        ["a dropped check ends the question already out", "if (publicReader.running) publicReader.signal(9);", ""]
    ]) {
        assert.equal(leakSource.split(needle).length - 1, 1, name);
        assert.throws(() => leakCheckSuite(load(file, commons), serviceSource, leakSource.replace(needle, replacement)), undefined, "control: " + name);
        console.log("vpn-logic: control=" + name + " red");
    }
} finally { fs.rmSync(scratch, { recursive: true, force: true }); }
console.log("vpn-logic: passed");
