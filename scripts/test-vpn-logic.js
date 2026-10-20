#!/usr/bin/env node
// The VPN plugin's decisions under the same loader as QML, over the nmcli
// shapes in scripts/fixtures/vpn/: the list, the multi-uuid detail read,
// the address read and each failure text, as NetworkManager 1.58.1 printed
// them under LC_ALL=C (VGS-1931 verify-first, 2026-10-20). Every name,
// address, key and path is a stand-in. Every control changes production
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

    // The failure each `up` text leaves, by the profile it ran on.
    const rowOf = (uuid, service) => Object.assign({}, listing.rows.find(row => row.uuid === uuid), { service });
    for (const [name, code, row, kind, failedService] of [
        ["up-secrets-wireguard.txt", 4, rowOf(LAB, ""), "sign-in", ""],
        ["up-secrets-password.txt", 4, rowOf(TRAVEL, "l2tp"), "needs-password", ""],
        ["up-secrets-password.txt", 4, rowOf(OFFICE, "openvpn"), "needs-password", ""],
        ["up-secrets-password.txt", 4, rowOf(BRANCH, "vpnc"), "sign-in", ""],
        ["up-secrets-password.txt", 4, rowOf(TRAVEL, ""), "sign-in", ""],
        ["up-secrets-multiple.txt", 4, rowOf(TRAVEL, "l2tp"), "sign-in", ""],
        ["up-secrets-multiple.txt", 4, rowOf(BRANCH, "vpnc"), "sign-in", ""],
        ["up-service-missing.txt", 4, rowOf(BRANCH, ""), "plugin-needed", "vpnc"],
        ["up-failed.txt", 4, rowOf(OFFICE, "openvpn"), "failed", ""],
        ["up-secrets-password.txt", -1, rowOf(TRAVEL, "l2tp"), "failed", ""]
    ]) {
        const failure = plain(logic.upFailure(code, text(name), row));
        assert.deepEqual(failure, { kind, service: failedService }, name + " on " + row.name);
        holdsNothingPrivate(failure, name);
    }
    assert.equal(logic.upFailure(4, "Error: Connection activation failed: No valid secrets", rowOf(TRAVEL, "l2tp")).kind, "sign-in");
    for (const [code, output, outcome] of [[0, "", "removed"], [10, text("delete-unknown.txt"), "gone"],
        [1, text("up-failed.txt"), "failed"], [-1, text("delete-unknown.txt"), "failed"]])
        assert.equal(logic.removeOutcome(code, output), outcome);

    // The published rows and what each one shows.
    const addresses = { [HOME]: "10.20.0.2", [OFFICE]: "10.9.9.9" };
    const failures = { [TRAVEL]: { kind: "needs-password", service: "" }, [BRANCH]: { kind: "sign-in", service: "" },
        [LAB]: { kind: "plugin-needed", service: "vpnc" } };
    const profiles = plain(logic.compose(listing, Object.assign({}, details, { [LAB]: undefined }), addresses, failures, false, null, ""));
    holdsNothingPrivate(profiles, "profiles");
    const byUuid = uuid => profiles.rows.find(row => row.uuid === uuid);
    assert.deepEqual(byUuid(HOME), { uuid: HOME, name: "Home tunnel", type: "wireguard", state: "activated", service: "",
        server: "203.0.113.10:51820", address: "10.20.0.2", failure: "" });
    assert.equal(byUuid(OFFICE).address, "", "an address shows only while activated");
    assert.equal(byUuid(LAB).service, "vpnc", "a missing plugin names its service before the details answer");
    assert.deepEqual(Object.keys(profiles).sort(), ["action", "activeCount", "count", "openvpnMissing", "problem", "rows", "state"]);
    const missingPlugin = plain(logic.compose(listing, details, {}, {}, true, null, ""));
    const viewOf = (payload, uuid) => plain(logic.rowView(payload.rows.find(row => row.uuid === uuid), payload));
    const flags = view => [view.key, view.connected, view.switchOn, view.busy, view.danger, view.reason !== "", view.installPlugin];
    for (const [payload, uuid, want] of [
        [profiles, HOME, ["connected", true, true, false, false, false, false]],
        [profiles, OFFICE, ["off", false, false, false, false, false, false]],
        [profiles, TRAVEL, ["needs-password", false, false, false, false, false, false]],
        [profiles, CAMPUS, ["unsupported", false, false, false, false, true, false]],
        [profiles, BRANCH, ["sign-in", false, false, false, false, true, false]],
        [profiles, LAB, ["plugin-needed", false, false, false, false, true, false]],
        [missingPlugin, OFFICE, ["plugin-needed", false, false, false, false, true, true]],
        [missingPlugin, TRAVEL, ["off", false, false, false, false, false, false]],
        [plain(logic.compose(listing, details, {}, { [OFFICE]: { kind: "failed", service: "" } }, false, null, "")), OFFICE,
            ["failed", false, false, false, true, false, false]],
        [plain(logic.compose(listing, details, {}, { [HOME]: { kind: "failed", service: "" } }, false, null, "")), HOME,
            ["connected", true, true, false, false, false, false]],
        [plain(logic.compose(listing, details, {}, {}, false, { kind: "profile-up", uuid: OFFICE, name: "Office VPN" }, "")), OFFICE,
            ["connecting", false, true, true, false, true, false]],
        [plain(logic.compose(listing, details, {}, {}, false, { kind: "profile-down", uuid: HOME, name: "Home tunnel" }, "")), HOME,
            ["disconnecting", true, false, true, false, true, false]],
        [plain(logic.compose(listing, details, {}, {}, false, { kind: "profile-remove", uuid: OFFICE, name: "Office VPN" }, "")), OFFICE,
            ["removing", false, false, true, false, true, false]],
        [plain(logic.compose(logic.list(0, "Office VPN:" + OFFICE + ":vpn:activating"), details, {}, {}, false, null, "")), OFFICE,
            ["connecting", false, true, true, false, true, false]]
    ]) assert.deepEqual(flags(viewOf(payload, uuid)), want, uuid + " " + want[0]);
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
        [{ kind: "profile-up", id: OFFICE }, plain(logic.compose(logic.emptyProfiles("not-running"), {}, {}, {}, false, null, "")), { refusal: "refused: profile=unavailable" }],
        [{ kind: "import" }, profiles, { refusal: "refused: profile=action" }],
        [[], profiles, { refusal: "refused: profile=action" }]
    ]) assert.deepEqual(plain(logic.profileCommand(request, payload)), want, JSON.stringify(request));

    // The bar icon and its tooltip's subject.
    const bar = payload => plain(logic.barView(payload));
    for (const hidden of [null, logic.emptyProfiles("reading"), logic.emptyProfiles("not-running"), logic.compose(logic.list(0, ""), {}, {}, {}, false, null, "")])
        assert.equal(bar(hidden).shown, false);
    const quiet = plain(logic.compose(listing, details, addresses, {}, false, null, ""));
    assert.deepEqual([bar(quiet).icon, bar(quiet).spinning, bar(quiet).warning], ["shield-check", false, false]);
    assert.ok(bar(quiet).tooltip.includes("Home tunnel"));
    const two = plain(logic.compose(logic.list(0, text("list.txt").replace("Office VPN:" + OFFICE + ":vpn:", "Office VPN:" + OFFICE + ":vpn:activated")), details, {}, {}, false, null, ""));
    assert.ok(bar(two).tooltip.includes("2") && !bar(two).tooltip.includes("Home tunnel"));
    const off = plain(logic.compose(logic.list(0, "Office VPN:" + OFFICE + ":vpn:"), details, {}, {}, false, null, ""));
    assert.deepEqual([bar(off).shown, bar(off).icon, bar(off).warning], [true, "shield-off", false]);
    const connecting = plain(logic.compose(listing, details, {}, {}, false, { kind: "profile-up", uuid: OFFICE, name: "Office VPN" }, ""));
    assert.deepEqual([bar(connecting).spinning, bar(connecting).warning], [true, false]);
    assert.ok(bar(connecting).tooltip.includes("Office VPN"));
    assert.equal(bar(plain(logic.compose(listing, details, {}, {}, false, { kind: "profile-remove", uuid: OFFICE, name: "Office VPN" }, ""))).spinning, false);
    for (const [kind, warning] of [["needs-password", true], ["failed", true], ["sign-in", false], ["plugin-needed", false]]) {
        const view = bar(plain(logic.compose(listing, details, {}, { [OFFICE]: { kind, service: "" } }, false, null, "")));
        assert.equal(view.warning, warning, kind);
        assert.equal(view.icon, warning ? "shield-alert" : "shield-check", kind);
        if (warning) assert.ok(view.tooltip.includes("Office VPN"));
    }

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
    // The detail completion keeps a read only when it answered.
    const completeDetails = new Function("running", "completion", "key", "again", "root", "Logic", "detailsText", "detailsDeadline", "console", bodyOf("detailsReader", "details"));
    for (const [code, output, kept] of [[0, text("details.txt"), true], [10, text("up-failed.txt") + "/home/fixture", false]]) {
        const console = logs();
        const owner = Object.assign(helpers(), { listing, detailMap: "unread", detailsRead: "", readDetails() { owner.again = true; } });
        completeDetails(false, { code, status: 0 }, key, false, owner, logic, { text: output }, { stop() {} }, console);
        assert.equal(owner.detailsRead, kept ? key : "");
        assert.deepEqual(owner.detailMap === "unread" ? null : plain(owner.detailMap), kept ? details : null);
        assert.deepEqual(console.messages, kept ? [] : [["warn", "vpn: operation=profile-details completion=failed code=10"]]);
    }
    // The action completion records the failure kind on the uuid, clears it
    // on success, leaves a problem line, and logs no nmcli text.
    const completeAction = new Function("running", "completion", "root", "Logic", "actorText", "actorErrors", "profileActionDeadline", "console", bodyOf("profileActor", "action"));
    for (const [kind, uuid, code, output, failure, problem] of [
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
        const owner = Object.assign(helpers(), { profiles, failures: { [TRAVEL]: { kind: "needs-password", service: "" } },
            profileAction: { kind, uuid, name: byUuid(uuid).name }, profileProblem: "", readProfiles() { reads++; } });
        completeAction(false, { code, status: 0 }, owner, logic, { text: "" }, { text: output }, { stop() {} }, console);
        if (kind === "profile-up") assert.equal(owner.failures[uuid] === undefined ? null : owner.failures[uuid].kind, failure, kind + " " + code);
        assert.equal(owner.profileProblem !== "", problem, kind + " " + code);
        assert.equal(owner.profileAction, null);
        assert.equal(reads, 1);
        assert.deepEqual(console.messages, code === 0 ? [] : [["warn", "vpn: operation=" + kind + " completion=failed code=" + code]]);
        holdsNothingPrivate([owner.failures, owner.profileProblem], kind);
    }

    // A requirements rescan asks again about a missing plugin or sign-in
    // detail, and keeps the failures the bar warns about.
    const recorded = { [TRAVEL]: { kind: "needs-password", service: "" }, [OFFICE]: { kind: "failed", service: "" },
        [BRANCH]: { kind: "sign-in", service: "" }, [LAB]: { kind: "plugin-needed", service: "vpnc" } };
    const rescanBody = /onScansChanged: \{([\s\S]*?)\n    \}/.exec(service);
    assert.ok(rescanBody);
    const rescanned = { failures: recorded, refreshed: 0, refresh() { this.refreshed++; } };
    new Function("Logic", "refresh", rescanBody[1].replace(/\bfailures\b/g, "this.failures")).call(rescanned, logic, () => rescanned.refresh());
    assert.deepEqual(Object.keys(plain(rescanned.failures)).sort(), [OFFICE, TRAVEL].sort());
    assert.equal(rescanned.refreshed, 1);
    assert.deepEqual(plain(recorded)[BRANCH].kind, "sign-in", "the rescan leaves the old map unchanged");

    // Execute the production Import callback with private capability doubles.
    const importBody = /function importFile\(\) \{([\s\S]*?)\n    \}/.exec(service);
    assert.ok(importBody);
    const importRun = new Function("profiles", "shell", "root", importBody[1]);
    // A shown notice answers the press and opens the import once it installs.
    for (const [state, missing, offerAnswer, refusal, offered, launched] of [
        ["available", [], "ok", undefined, [], 1],
        ["available", ["gum"], "ok", undefined, [[["gum"], "import"]], 0],
        ["available", ["nmcli", "gum"], "ok", undefined, [[["nmcli", "gum"], "import"]], 0],
        ["available", ["busctl"], "ok", undefined, [[["busctl"], "import"]], 0],
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
    assert.deepEqual(manifest.tui.import.requires.slice().sort(), ["busctl", "gum", "nmcli"]);

    // Publish bounded profile lists through the production service callback.
    assert.equal(logic.line("a<b>\u0007c\n"), "ab>c");
    const publishBody = /function publish\(\) \{([\s\S]*?)\n    \}\n    onConnectionChanged/.exec(service);
    assert.ok(publishBody);
    const publish = new Function("shell", "connection", "profiles", "Logic", publishBody[1]);
    const wide = Array.from({ length: 100 }, (_, i) => "界".repeat(80) + i + ":" + String(i).padStart(8, "0") + "-0000-4000-8000-000000000000:vpn:activated").join("\n");
    const wideListing = logic.list(0, wide);
    const wideDetails = {};
    for (const row of wideListing.rows) wideDetails[row.uuid] = { service: "openvpn", server: "界".repeat(logic.SERVER_MAX) };
    const crowded = plain(logic.compose(wideListing, wideDetails, {}, {}, false, { kind: "profile-up", uuid: wideListing.rows[0].uuid, name: "界".repeat(logic.TEXT_MAX) }, "界".repeat(200)));
    let values = {};
    const shell = { status: { set(key, value) {
        const result = core.statusWrite(manifest, values, key, value);
        assert.equal(result.ok, true, key + ": " + result.error);
        values = plain(result.values);
        assert.ok(Buffer.byteLength(JSON.stringify(values)) <= STATUS_MAX_BYTES);
        return "ok";
    } } };
    for (const payload of [profiles, crowded, plain(logic.compose(logic.emptyProfiles("missing"), {}, {}, {}, false, null, ""))]) {
        const original = JSON.stringify(payload);
        publish(shell, logic.connection(payload), payload, logic);
        assert.equal(JSON.stringify(payload), original);
        assert.equal(values.profiles.count, payload.count);
        assert.equal(values.profiles.activeCount, payload.activeCount);
        assert.ok(values.profiles.rows.length > 0 || payload.rows.length === 0);
        for (const row of values.profiles.rows) assert.deepEqual(row, payload.rows.find(input => input.uuid === row.uuid));
        assert.equal(logic.barView(values.profiles).shown, payload.state === "available" && payload.count > 0);
    }
    assert.ok(crowded.rows.length > values.profiles.rows.length || Buffer.byteLength(JSON.stringify(crowded)) <= logic.STATUS_DATA_BYTES);
}

suite(load(file, commons));
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "vpn-logic-"));
try {
    const source = fs.readFileSync(file, "utf8");
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
        ["a missing OpenVPN plugin blocks its profiles", 'profiles.openvpnMissing === true', 'false'],
        ["an address shows only while activated", 'row.state === "activated" && typeof addresses', 'typeof addresses'],
        ["a blocked switch refuses its IPC", 'if (view.reason !== "") return', 'if (false) return'],
        ["profile argv names uuid", '"up", "uuid", row.uuid]', '"up", "id", row.name]'],
        ["profile lists are bounded", 'rows: rows.slice(0, PROFILE_MAX)', 'rows: rows'],
        ["no profiles hides the icon", ' || profiles.count === 0', ''],
        ["a rescan clears a sign-in failure", 'failures[uuid].kind !== "sign-in" && ', ''],
        ["a rescan keeps the bar's failures", 'kept[uuid] = failures[uuid];', '{}'],
        ["a password failure raises the alert", 'row.failure === "needs-password" || row.failure === "failed"', 'row.failure === "failed"'],
        ["a drawn line holds no markup start", "\\u007f<]/g", "\\u007f]/g"]
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
        ["a successful up clears its failure", "if (code === 0) delete next[action.uuid];", "if (code === 0) {}"],
        ["a gone profile leaves no problem", 'Logic.removeOutcome(code, output) === "failed"', 'code !== 0'],
        ["no nmcli text reaches the log", '" code=" + code);\n            if (action.kind', '" code=" + code + " " + output);\n            if (action.kind'],
        ["a rescan applies the failure rule", "failures = Logic.afterRescan(failures);", ""],
        ["missing import tools offer setup", "if (needed.length > 0)", "if (false)"],
        ["import availability", 'if (profiles.state !== "available")', 'if (false)'],
        ["import completion refreshes", '() => root.readProfiles()', '() => {}']
    ]) {
        assert.equal(serviceSource.split(old).length - 1, 1, name);
        assert.throws(() => suite(load(file, commons), serviceSource.replace(old, replacement)), undefined, "control: " + name);
        console.log("vpn-logic: control=" + name + " red");
    }
} finally { fs.rmSync(scratch, { recursive: true, force: true }); }
console.log("vpn-logic: passed");
