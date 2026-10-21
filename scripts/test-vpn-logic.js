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

function suite(logic, service = serviceSource) {
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
        server: "203.0.113.10:51820", address: "10.20.0.2", failure: "" });
    assert.equal(byUuid(OFFICE).address, "", "an address shows only while activated");
    assert.equal(byUuid(LAB).service, "vpnc", "a missing plugin names its service before the details answer");
    assert.deepEqual(Object.keys(profiles).sort(), ["action", "activeCount", "count", "problem", "rows", "state"]);
    // A missing OpenVPN plugin reads from the `up` that failed for it.
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
        [missingPlugin, OFFICE, ["plugin-needed", false, false, false, false, true]],
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
        [{ kind: "profile-up", id: OFFICE }, missingPlugin, { refusal: "refused: profile=plugin-needed" }],
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
    const helpers = () => ({ codeOf: new Function("completion", codeBody[1]), completionWord: new Function("code", wordBody[1]) });
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
        const owner = Object.assign(helpers(), { listed(next) { owner.listing = plain(next); } });
        let stopped = false;
        completeList(false, code === -1 ? null : { code, status: 0 }, owner, logic, { text: output }, { stop() { stopped = true; } }, false, console);
        assert.equal(owner.listing.state, state);
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
        const owner = Object.assign({ listing: null, failures: {}, addresses: {}, profileProblem: null, detailsRead: "", reads: 0, queued: [],
            readDetails() { owner.reads++; }, queueAddress(uuid) { owner.queued.push(uuid); } }, fields);
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
    for (const [code, output, kept] of [[0, text("details.txt"), true], [10, text("up-failed.txt") + "/home/fixture", false]]) {
        const console = logs();
        const owner = Object.assign(helpers(), { listing, detailMap: "unread", detailsRead: key, readDetails() { owner.again = true; } });
        completeDetails(false, { code, status: 0 }, key, false, owner, logic, { text: output }, { stop() {} }, console);
        assert.equal(owner.detailsRead, kept ? key : "");
        assert.deepEqual(owner.detailMap === "unread" ? null : plain(owner.detailMap), kept ? details : null);
        assert.deepEqual(console.messages, kept ? [] : [["warn", "vpn: operation=profile-details completion=failed code=10"]]);
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
        // A feed the run never took, as when it never started, goes with it.
        const owner = Object.assign(helpers(), { profiles, failures: { [TRAVEL]: { kind: "needs-password", service: "" } },
            profileAction: { kind, uuid, name: byUuid(uuid).name, password: password === true }, profileProblem: null,
            connectFeed: () => {}, readProfiles() { reads++; } });
        completeAction(false, { code, status: 0 }, owner, logic, { text: "" }, { text: output }, { stop() {} }, console);
        assert.equal(owner.connectFeed, null, kind + " " + code);
        if (kind === "profile-up") assert.equal(owner.failures[uuid] === undefined ? null : owner.failures[uuid].kind, failure, kind + " " + code);
        assert.deepEqual(owner.profileProblem === null ? null : [owner.profileProblem.uuid, owner.profileProblem.kind],
            problem ? [uuid, kind] : null, kind + " " + code);
        if (problem) assert.equal(typeof owner.profileProblem.text === "string" && owner.profileProblem.text !== "", true, kind + " " + code);
        assert.equal(owner.profileAction, null);
        assert.equal(reads, 1);
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
    const actor = stdinEnabled => ({ running: false, stdinEnabled, command: [], completion: "old" });
    // stale: a feed and an open stdin a change before this one left behind.
    const actionOwner = (stale = false) => {
        const owner = { profiles, profileAction: null, profileProblem: { uuid: OFFICE }, connectFeed: stale ? () => {} : null,
            profileActor: actor(stale), restarts: 0, profileActionDeadline: { restart() { owner.restarts++; } } };
        method(owner, "connectWithPassword");
        method(owner, "startAction");
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
            readDetails() { rescanned.detailReads++; }, readProfiles() { rescanned.refreshed++; } };
        method(rescanned, "refresh");
        runRescan(rescanned);
        assert.deepEqual(Object.keys(plain(rescanned.failures)).sort(), [OFFICE, TRAVEL, CAMPUS].sort());
        assert.equal(rescanned.profileProblem === null, !kept, "a rescan's problem line for " + kind + " " + byUuid(uuid).name);
        assert.deepEqual([rescanned.detailsRead, rescanned.detailReads, rescanned.refreshed], ["", 1, 1]);
    }
    assert.deepEqual(plain(recorded)[BRANCH].kind, "sign-in", "the rescan leaves the old map unchanged");
    // An editor can save the same UUID while a detail read is still in
    // flight. Refresh queues one replacement read, which publishes the new
    // server; a failed replacement leaves its stamp unread for retry.
    const detailOwner = (running = false) => {
        const owner = Object.assign(helpers(), { listing, failures: recorded, profileProblem: null, detailsRead: key, detailMap: details,
            registered: true, profilesMissing: false, starts: 0, refreshed: 0,
            detailsReader: { running, again: false, completion: { code: 0, status: 0 }, key, command: [] },
            detailsDeadline: { restart() { owner.starts++; }, stop() {} }, readProfiles() { owner.refreshed++; } });
        method(owner, "readDetails");
        method(owner, "refresh");
        method(owner, "listed");
        owner.queueAddress = () => {};
        owner.addresses = {};
        return owner;
    };
    // Opening a view leases faster list reads; it must retain failures the
    // last connect learned. Explicit refresh owns their invalidation.
    for (const kind of ["sign-in", "plugin-needed", "password-tried"]) {
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
    const publish = new Function("shell", "connection", "profiles", "Logic", publishBody[1]);
    const wide = Array.from({ length: 100 }, (_, i) => "界".repeat(80) + i + ":" + String(i).padStart(8, "0") + "-0000-4000-8000-000000000000:vpn:activated").join("\n");
    const wideListing = logic.list(0, wide);
    const wideDetails = {};
    for (const row of wideListing.rows) wideDetails[row.uuid] = { service: "openvpn", server: "界".repeat(logic.SERVER_MAX) };
    const crowded = plain(logic.compose(wideListing, wideDetails, {}, {}, { kind: "profile-up", uuid: wideListing.rows[0].uuid, name: "界".repeat(logic.TEXT_MAX) }, "界".repeat(200)));
    let values = {};
    const shell = { status: { set(key, value) {
        const result = core.statusWrite(manifest, values, key, value);
        assert.equal(result.ok, true, key + ": " + result.error);
        values = plain(result.values);
        assert.ok(Buffer.byteLength(JSON.stringify(values)) <= STATUS_MAX_BYTES);
        return "ok";
    } } };
    for (const payload of [profiles, crowded, plain(logic.compose(logic.emptyProfiles("missing"), {}, {}, {}, null, ""))]) {
        const original = JSON.stringify(payload);
        publish(shell, logic.connection(payload), payload, logic);
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
    const invoke = new Function("Logic", "profiles", "shell", "answered", "kind", "uuid", callback[1]);
    for (const [kind, uuid, missing, expectedOffers, expectedLaunches] of [
        ["create", "", [], [], [["nm-connection-editor", "--create", "--type=vpn"]]],
        ["edit", HOME, [], [], [["nm-connection-editor", "--edit=" + HOME]]],
        ["create", "", ["nm-connection-editor"], [["nm-connection-editor"]], []],
        ["edit", HOME, ["nm-connection-editor"], [["nm-connection-editor"]], []],
        ["edit", OFFICE, [], [], []]
    ]) {
        const offers = [], launches = [], answers = [];
        invoke(logic, profiles, {
            requirements: { missing, offer(commands) { offers.push(plain(commands)); return "ok"; } },
            run: { detached(argv) { launches.push(plain(argv)); return "ok"; } }
        }, reply => answers.push(reply), kind, uuid);
        assert.deepEqual(offers, expectedOffers);
        assert.deepEqual(launches, expectedLaunches);
        assert.deepEqual(answers, [uuid === OFFICE ? "refused: profile=absent" : "ok"]);
    }
    assert.equal(manifest.requirements.find(row => row.command === "nm-connection-editor").optional, true);
    for (const kind of manifest.kinds)
        assert.equal(core.instanceCapabilities(manifest, kind).includes("run"), kind === "pane", kind);
}

suite(load(file, commons));
editorSuite(load(file, commons));
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "vpn-logic-"));
try {
    const source = fs.readFileSync(file, "utf8");
    for (const [name, sourceText, needle, replacement, target] of [
        ["editor create type", source, '"--type=vpn"', '"--type=ethernet"', "logic"],
        ["editor edit uuid", source, '"--edit=" + row.uuid', '"--edit=" + row.name', "logic"],
        ["editor absent refusal", source, 'candidate.uuid === uuid);\n    if (row === undefined) return { refusal: "refused: profile=absent" };\n    return { argv: ["nm-connection-editor"', 'true);\n    if (row === undefined) return { refusal: "refused: profile=absent" };\n    return { argv: ["nm-connection-editor"', "logic"],
        ["editor missing offer", bodySource, 'missing ? shell.requirements.offer(["nm-connection-editor"])', 'false ? shell.requirements.offer(["nm-connection-editor"])', "body"]
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
        ["a missing plugin blocks its profile", 'if (row.failure === "plugin-needed")', 'if (false)'],
        ["an address shows only while activated", 'row.state === "activated" && typeof addresses', 'typeof addresses'],
        ["a blocked switch refuses its IPC", 'if (view.reason !== "") return', 'if (false) return'],
        ["profile argv names uuid", '"up", "uuid", row.uuid]', '"up", "id", row.name]'],
        ["profile lists are bounded", 'rows: rows.slice(0, PROFILE_MAX)', 'rows: rows'],
        ["no profiles hides the icon", ' || profiles.count === 0', ''],
        ["a rescan clears a sign-in failure", 'failures[uuid].kind !== "sign-in" && ', ''],
        ["a rescan keeps the bar's failures", 'kept[uuid] = failures[uuid];', '{}'],
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
        ["only Needs password takes a password", 'if (rowView(row, profiles).key !== "needs-password") return { refusal: "refused: profile=state" };', ""],
        ["the password connect never asks", '"passwd-file", "/dev/stdin"]', '"passwd-file", "/dev/stdin", "--ask"]'],
        ["status rows are trimmed to their budget", "profiles.rows.pop();", "break;"]
    ]) {
        assert.equal(source.split(needle).length - 1, 1, name + " mutation must match once");
        const mutant = path.join(scratch, "VpnLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, replacement));
        assert.throws(() => suite(load(mutant, commons)), undefined, "control: " + name);
        console.log("vpn-logic: control=" + name + " red");
    }
    for (const [name, old, replacement] of [
        ["optional profile absence is informational", "if (code === 1 || code === 8) console.log(diagnostic);", "if (code === 1 || code === 8) console.warn(diagnostic);"],
        ["a failed detail read keeps nothing", "if (read === null) {", "if (false) {"],
        ["a failed detail read retries", 'root.detailsRead = "";', ""],
        ["a view lease preserves learned failures", "if (request.open) readProfiles();", "if (request.open) refresh();"],
        ["a successful up clears its failure", "if (code === 0) delete next[action.uuid];", "if (code === 0) {}"],
        ["a gone profile leaves no problem", 'Logic.removeOutcome(code, output) === "failed"', 'code !== 0'],
        ["no nmcli text reaches the log", '" code=" + code);\n            if (action.kind', '" code=" + code + " " + output);\n            if (action.kind'],
        ["a rescan applies the failure rule", "failures = Logic.afterRescan(failures);", ""],
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
        ["a password connect opens stdin", "profileActor.stdinEnabled = feed !== null;", "profileActor.stdinEnabled = false;"],
        ["a password connect is marked", "password: feed !== null }", "password: false }"],
        ["a password connect holds its feed", "connectFeed = feed;", ""],
        ["one change at a time", 'if (profileActor.running) return "busy";', ""],
        ["the started run drops its feed", "root.connectFeed = null;\n            if (once !== null)", "if (once !== null)"],
        ["a plain change drops a stale feed", "connectFeed = feed;", "if (feed !== null) connectFeed = feed;"],
        ["a plain change closes stdin", "profileActor.stdinEnabled = feed !== null;", "if (feed !== null) profileActor.stdinEnabled = true;"],
        ["the ended run drops its feed", "root.connectFeed = null;\n            profileActionDeadline.stop();", "profileActionDeadline.stop();"],
        ["destruction drops the feed", "Logic.releaseConnect(root);\n        connectFeed = null;", "Logic.releaseConnect(root);"],
        ["a password connect's failure is carried", "action.password === true)", "false)"]
    ]) {
        assert.equal(serviceSource.split(old).length - 1, 1, name);
        assert.throws(() => suite(load(file, commons), serviceSource.replace(old, replacement)), undefined, "control: " + name);
        console.log("vpn-logic: control=" + name + " red");
    }
} finally { fs.rmSync(scratch, { recursive: true, force: true }); }
console.log("vpn-logic: passed");
