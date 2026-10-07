#!/usr/bin/env node
// The VPN section's decisions under the same loader as QML, over the
// `tailscale status --json` shapes in scripts/fixtures/vpn/: running,
// stopped, logged out and a tailnet with Mullvad nodes, and the CLI's
// access-denied and service-off texts. The field names are the ones one
// read of a live tailnet gave; every name, address, key and account is
// made up. Every mutation changes production behavior; the suite must
// turn red on it.
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
const text = name => fs.readFileSync(path.join(fixtures, name), "utf8");
// The core's ceiling for one plugin's published status
// (PluginLogic.STATUS_MAX_BYTES).
const STATUS_MAX_BYTES = core.STATUS_MAX_BYTES;
const plain = value => JSON.parse(JSON.stringify(value));

function suite(logic, service = serviceSource) {
    const read = name => plain(logic.snapshot(0, text(name), ""));
    const running = read("running.json");
    const mullvad = read("mullvad.json");

    // The recorded shapes.
    assert.equal(running.state, "running");
    assert.deepEqual(running.device, { name: "desk", address: "100.64.0.1" });
    assert.equal(running.tailnet, "fixture.example");
    assert.equal(running.account, "owner@fixture.example");
    assert.deepEqual(running.exit, { id: "nFIXTURE0002CNTRL", name: "gateway" });
    assert.deepEqual(running.peers.map(row => [row.name, row.online]),
        [["100.64.0.4", true], ["attic box", true], ["gateway", true], ["laptop", true], ["backup", false]]);
    assert.equal(running.peerCount, 5);
    const stopped = read("stopped.json");
    assert.equal(stopped.state, "stopped");
    assert.equal(stopped.exit, null);
    const loggedOut = read("logged-out.json");
    assert.equal(loggedOut.state, "signed-out");
    assert.deepEqual([loggedOut.peers, loggedOut.exitNodes, loggedOut.account, loggedOut.tailnet], [[], [], "", ""]);
    assert.equal(plain(logic.snapshot(1, "", text("service-off.txt"))).state, "service-off");
    for (const [code, stdout] of [[1, ""], [-1, text("running.json")], [0, "not json"], [0, "[]"], [0, '{"BackendState":"Future"}']])
        assert.equal(logic.snapshot(code, stdout, "").state, "unavailable");

    // The exit-node target rule: the DNS name, else the host name, else
    // the first IPv4; a Mullvad node's IPv4; never the peer id.
    const mullvadTag = ["tag:mullvad-exit-node"];
    for (const [peer, want] of [
        [{ ID: "nA", DNSName: "gateway.tail-fixture.ts.net.", HostName: "gateway", TailscaleIPs: ["100.64.0.2"] }, "gateway.tail-fixture.ts.net"],
        [{ ID: "nB", DNSName: "", HostName: "attic box", TailscaleIPs: ["100.64.0.3"] }, "attic box"],
        [{ ID: "nC", DNSName: "", HostName: "", TailscaleIPs: ["fd7a:115c:a1e0::4", "100.64.0.4"] }, "100.64.0.4"],
        [{ ID: "nD", DNSName: "se-sto-wg-011.mullvad.ts.net.", HostName: "se-sto-wg-011", Tags: mullvadTag, TailscaleIPs: ["fd7a:115c:a1e0::b", "100.64.0.11"] }, "100.64.0.11"],
        [{ ID: "nE", DNSName: "ch-zrh-wg-012.mullvad.ts.net.", Tags: mullvadTag, TailscaleIPs: ["fd7a:115c:a1e0::c"] }, ""],
        [{ ID: "nF", TailscaleIPs: null }, ""]
    ]) assert.equal(logic.exitTarget(peer), want, "target of " + peer.ID);
    assert.deepEqual(running.exitNodes.map(row => [row.id, row.target, row.active]), [
        ["nFIXTURE0004CNTRL", "100.64.0.4", false], ["nFIXTURE0003CNTRL", "attic box", false],
        ["nFIXTURE0002CNTRL", "gateway.tail-fixture.ts.net", true]
    ]);
    // One Mullvad node a city: the one in use, else the highest ranked.
    assert.deepEqual(mullvad.exitNodes.map(row => [row.id, row.target, row.place]), [
        ["nFIXTURE0002CNTRL", "gateway.tail-fixture.ts.net", ""],
        ["nFIXTURE0011CNTRL", "100.64.0.11", "Stockholm, Sweden"], ["nFIXTURE0013CNTRL", "100.64.0.13", "Zurich, Switzerland"]
    ]);
    assert.deepEqual(mullvad.exit, { id: "nFIXTURE0013CNTRL", name: "Zurich, Switzerland" });
    assert.deepEqual(mullvad.peers.map(row => row.name), ["gateway", "laptop"]);
    const unaddressed = plain(logic.exitNodes([{ ID: "nG", ExitNodeOption: true, Tags: mullvadTag, TailscaleIPs: ["fd7a:115c:a1e0::d"] }]));
    assert.deepEqual(unaddressed, { rows: [], count: 0 });
    for (const snapshot of [running, mullvad]) {
        const data = { state: "running", exitNodes: snapshot.exitNodes, accounts: [] };
        for (const node of snapshot.exitNodes) {
            assert.notEqual(node.target, node.id);
            const argv = plain(logic.command({ kind: "exit-node", id: node.id }, data)).argv;
            assert.deepEqual(argv, ["tailscale", "set", "--exit-node=" + node.target]);
            assert.equal(argv.join(" ").includes(node.id), false, "the peer id reached the argv of " + node.id);
        }
    }

    // Every command's argv, and the refusals.
    const listed = plain(logic.accounts(0, text("accounts.txt")));
    const accounts = listed.rows;
    assert.equal(listed.fault, "");
    assert.deepEqual(accounts, [
        { id: "f1a0", tailnet: "fixture.example", account: "owner@fixture.example", current: true },
        { id: "f1a1", tailnet: "second.example", account: "owner@second.example", current: false }
    ]);
    for (const [code, stdout, fault] of [[1, text("accounts.txt"), "failed"], [0, "", "header"], [0, "owner@fixture.example *\n", "header"]])
        assert.deepEqual(plain(logic.accounts(code, stdout)), { rows: [], fault: fault });
    const held = state => ({ state: state, exitNodes: running.exitNodes, accounts: accounts });
    for (const [request, state, want] of [
        [{ kind: "connect" }, "stopped", { argv: ["tailscale", "up"] }],
        [{ kind: "connect" }, "running", { refusal: "refused: action=connect state=running" }],
        [{ kind: "connect" }, "signed-out", { refusal: "refused: action=connect state=signed-out" }],
        [{ kind: "disconnect" }, "running", { argv: ["tailscale", "down"] }],
        [{ kind: "disconnect" }, "starting", { argv: ["tailscale", "down"] }],
        [{ kind: "disconnect" }, "stopped", { refusal: "refused: action=disconnect state=stopped" }],
        [{ kind: "exit-node", id: "" }, "running", { argv: ["tailscale", "set", "--exit-node="] }],
        [{ kind: "exit-node", id: "gateway.tail-fixture.ts.net" }, "running", { refusal: "refused: exit-node=absent" }],
        [{ kind: "exit-node", id: "nFIXTURE0002CNTRL" }, "stopped", { refusal: "refused: action=exit-node state=stopped" }],
        [{ kind: "switch", id: "f1a1" }, "running", { argv: ["tailscale", "switch", "f1a1"] }],
        [{ kind: "switch", id: "owner@second.example" }, "running", { refusal: "refused: account=absent" }],
        [{ kind: "switch", id: "f1a1" }, "service-off", { refusal: "refused: action=switch state=service-off" }],
        [{ kind: "login" }, "signed-out", { argv: ["tailscale", "login", "--timeout", "0"] }],
        [{ kind: "login" }, "unavailable", { refusal: "refused: action=login state=unavailable" }],
        [{ kind: "restart" }, "running", { refusal: "refused: action=unknown" }],
        [null, "running", { refusal: "refused: action=malformed" }]
    ]) assert.deepEqual(plain(logic.command(request, held(state))), want);

    // The poll: one run in flight, and only a start arms the watchdog.
    const idle = plain(logic.pollIdle());
    const started = plain(logic.pollStep(idle, "tick"));
    assert.deepEqual(started, { state: { flight: true, again: false }, effects: ["start", "arm"] });
    assert.deepEqual(plain(logic.pollStep(started.state, "tick")), { state: { flight: true, again: false }, effects: [] });
    const asked = plain(logic.pollStep(started.state, "refresh"));
    assert.deepEqual(asked, { state: { flight: true, again: true }, effects: [] });
    assert.deepEqual(plain(logic.pollStep(asked.state, "refresh")).effects, []);
    assert.deepEqual(plain(logic.pollStep(asked.state, "deadline")), { state: asked.state, effects: ["kill"] });
    assert.deepEqual(plain(logic.pollStep(idle, "deadline")).effects, []);
    assert.deepEqual(plain(logic.pollStep(asked.state, "exit")), { state: { flight: true, again: false }, effects: ["disarm", "start", "arm"] });
    assert.deepEqual(plain(logic.pollStep(started.state, "exit")), { state: idle, effects: ["disarm"] });
    assert.deepEqual(plain(logic.pollStep(idle, "refresh")).effects, ["start", "arm"]);
    assert.throws(() => logic.pollStep(idle, "later"));
    assert.equal(logic.WATCHDOG_MS, 10000);
    for (const [open, seconds, want] of [[false, 10, 10000], [false, 30, 30000], [false, 60, 60000], [true, 30, 3000], [true, 60, 3000]])
        assert.equal(logic.pollInterval(open, seconds), want);

    // The CLI's failure texts.
    assert.equal(logic.failureKind(text("access-denied.txt")), "access-denied");
    assert.equal(logic.failureKind(text("service-off.txt")), "service-off");
    assert.equal(logic.failureKind("exit status 1"), "other");
    const kinds = ["access-denied", "service-off", "timeout", "other"];
    assert.equal(new Set(kinds.map(kind => logic.failureText(kind))).size, kinds.length);
    assert.throws(() => logic.failureText("future"));

    // The sign-in page's address.
    for (const [printed, want] of [
        ["\thttps://login.fixture.example/a/0123456789abcdef", "https://login.fixture.example/a/0123456789abcdef"],
        ["To authenticate, visit:", ""], ["", ""], ["http://login.fixture.example/a/0123", ""], ["file:///etc/passwd", ""]
    ]) assert.equal(logic.loginUrl(printed), want);

    // Setup: one step at a time, Allow while access is denied, and no
    // Ready over an operator the core could not read.
    for (const [context, action, tone] of [
        [{ missing: true, state: "checking", service: "absent", operator: "absent" }, "install", "warning"],
        [{ missing: false, state: "service-off", service: "needed", operator: "unknown" }, "enable", "warning"],
        [{ missing: false, state: "service-off", service: "nixos", operator: "unknown" }, "enable", "warning"],
        [{ missing: false, state: "service-off", service: "absent", operator: "unknown" }, "", "warning"],
        [{ missing: false, state: "running", service: "ready", operator: "needed" }, "allow", "warning"],
        [{ missing: false, state: "stopped", service: "ready", operator: "nixos" }, "allow", "warning"],
        [{ missing: false, state: "running", service: "ready", operator: "denied" }, "", "warning"],
        [{ missing: false, state: "running", service: "ready", operator: "unknown" }, "", "warning"],
        [{ missing: false, state: "stopped", service: "ready", operator: "unknown" }, "", "warning"],
        [{ missing: false, state: "running", service: "ready", operator: "ready" }, "", "ok"],
        [{ missing: false, state: "running", service: "", operator: "" }, "", "ok"]
    ]) assert.deepEqual([logic.setup(context).action, logic.setup(context).tone], [action, tone], JSON.stringify(context));

    // The connection line and the bar icon.
    const states = ["missing", "checking", "service-off", "unavailable", "signed-out", "needs-approval", "starting", "stopped", "running"];
    const lines = states.map(state => logic.connection(state === "missing", logic.emptySnapshot(state === "missing" ? "checking" : state)));
    assert.deepEqual(lines.map(shown => shown.state), states);
    assert.equal(new Set(lines.map(shown => shown.text)).size, states.length);
    assert.throws(() => logic.connection(false, logic.emptySnapshot("future")));
    const live = { accounts: accounts, action: "", login: "idle", problem: "" };
    const ready = logic.setup({ missing: false, state: "running", service: "ready", operator: "ready" });
    const denied = logic.setup({ missing: false, state: "running", service: "ready", operator: "needed" });
    const shown = plain(logic.published(false, running, ready, live));
    assert.deepEqual([shown.state, shown.tone, shown.writable], ["running", "ok", true]);
    assert.equal(logic.published(false, running, denied, live).writable, false);
    assert.equal(plain(logic.unread()).state, "checking");
    for (const [vpn, want] of [
        [null, { shown: false }], [plain(logic.published(true, running, ready, live)), { shown: false }],
        [shown, { shown: true, icon: "globe-lock" }],
        [plain(logic.published(false, Object.assign({}, running, { exit: null }), ready, live)), { shown: true, icon: "shield-check" }],
        [plain(logic.published(false, stopped, ready, live)), { shown: true, icon: "shield-off" }],
        [plain(logic.published(false, logic.emptySnapshot("service-off"), ready, live)), { shown: true, icon: "shield-alert" }]
    ]) {
        const view = logic.barView(vpn);
        for (const key of Object.keys(want)) assert.equal(view[key], want[key], key + " of " + (vpn === null ? "null" : vpn.state));
    }

    const profiles = plain(logic.profiles(0, "Office\\:west\\\\desk:vpn:\nHome tunnel:wireguard:activated\nWifi:wifi:activated\n"));
    assert.deepEqual(profiles, { state: "available", rows: [
        { id: "Office:west\\desk", name: "Office:west\\desk", type: "vpn", active: false, ambiguous: false },
        { id: "Home tunnel", name: "Home tunnel", type: "wireguard", active: true, ambiguous: false }
    ], count: 2, activeCount: 1 });
    for (const [code, output, state] of [[0, "", "available"], [10, "x:vpn:", "unavailable"],
        [0, "bad:vpn", "unavailable"], [0, "bad:vpn:ending\\", "unavailable"]])
        assert.equal(logic.profiles(code, output).state, state);
    for (const [request, argv, refusal] of [
        [{ kind: "profile-up", id: "Office:west\\desk" }, ["nmcli", "connection", "up", "id", "Office:west\\desk"], undefined],
        [{ kind: "profile-down", id: "Home tunnel" }, ["nmcli", "connection", "down", "id", "Home tunnel"], undefined],
        [{ kind: "profile-up", id: "Home tunnel" }, undefined, "refused: profile=state"],
        [{ kind: "profile-down", id: "gone" }, undefined, "refused: profile=absent"]
    ]) assert.deepEqual(plain(logic.profileCommand(request, profiles)), argv ? { argv } : { refusal });
    assert.equal(logic.profileCommand({ kind: "profile-up", id: "Office:west\\desk" }, { state: "available", rows: [profiles.rows[0], profiles.rows[0]] }).refusal, "refused: profile=ambiguous");
    assert.equal(logic.profileCommand({ kind: "profile-up", id: "Home tunnel" }, logic.emptyProfiles()).refusal, "refused: profile=unavailable");
    assert.equal(logic.barView({ state: "missing" }, profiles).shown, true);
    assert.equal(logic.barView({ state: "missing" }, profiles).icon, "shield-check");
    assert.equal(logic.barView({ state: "missing" }, logic.profiles(0, "")).icon, "shield-off");
    assert.equal(logic.barView({ state: "missing" }, logic.emptyProfiles()).shown, false);
    // Names resolve across every type and across rows beyond the view bound.
    for (const otherType of ["wifi", "vpn", "wireguard"]) {
        for (const active of [false, true]) {
            const inventory = "Shared:wireguard:" + (active ? "activated" : "deactivated") + "\n" +
                Array.from({ length: logic.PROFILE_MAX }, (_, i) => "Other" + i + ":vpn:deactivated").join("\n") +
                "\nShared:" + otherType + ":activated";
            const listed = plain(logic.profiles(0, inventory));
            assert.equal(listed.rows[0].ambiguous, true);
            for (const kind of ["profile-up", "profile-down"])
                assert.equal(logic.profileCommand({ kind, id: "Shared" }, listed).refusal, "refused: profile=ambiguous");
        }
    }
    const hiddenActive = plain(logic.profiles(0, Array.from({ length: logic.PROFILE_MAX }, (_, i) => "Idle" + i + ":vpn:deactivated").join("\n") + "\nActive:wireguard:activated"));
    assert.equal(hiddenActive.rows.some(row => row.active), false);
    assert.equal(hiddenActive.activeCount, 1);
    for (const state of states.filter(state => state !== "running")) {
        assert.equal(logic.barView({ state }, hiddenActive).icon, "shield-check", state);
        assert.equal(logic.barView({ state }, profiles).icon, "shield-check", state);
    }
    assert.equal(logic.barView(shown, profiles).icon, "globe-lock");

    // Execute the shipped profile completion body. start-order reads its
    // log severity; process output can contain private profile data.
    const completionBody = /id: profilesReader[\s\S]*?onRunningChanged: \{([\s\S]*?)\n        \}/.exec(service);
    const codeBody = /function codeOf\(completion\) \{([\s\S]*?)\n    \}/.exec(service);
    assert.ok(completionBody);
    assert.ok(codeBody);
    const complete = new Function("running", "completion", "root", "Logic", "profilesText", "profilesDeadline", "again", "console", completionBody[1]);
    for (const [code, output, state, level, kind] of [
        [1, "/private/fixture.conf", "unavailable", "log", "failed"],
        [8, "/private/fixture.conf", "unavailable", "log", "failed"],
        [10, "PRIVATE-FIXTURE-PROFILE-ERROR", "unavailable", "warn", "failed"],
        [-1, "PRIVATE-FIXTURE-PROFILE-ERROR", "unavailable", "warn", "interrupted"],
        [0, "malformed", "unavailable", "warn", "invalid-reply"],
        [0, "", "available", null, null]
    ]) {
        const messages = [];
        const owner = { codeOf: new Function("completion", codeBody[1]) };
        let stopped = false;
        complete(false, { code, status: 0 }, owner, logic, { text: output }, { stop() { stopped = true; } }, false,
            { log(message) { messages.push(["log", message]); }, warn(message) { messages.push(["warn", message]); } });
        assert.equal(owner.profileSnapshot.state, state);
        assert.equal(stopped, true);
        assert.deepEqual(messages, level === null ? [] : [[level, "vpn: operation=profile-read completion=" + kind + " code=" + code]]);
    }
    assert.equal(logic.barView(Object.assign({}, shown, { exit: null }), profiles).icon, "shield-check");
    const trimmedProfiles = logic.statusWrites({ tone: "ok", text: "" }, ready, shown,
        Object.assign({}, hiddenActive, { rows: hiddenActive.rows.map(row => Object.assign({}, row, { id: "界".repeat(logic.TARGET_MAX), name: "界".repeat(logic.TEXT_MAX) })), action: "", problem: "" }))[3][1];
    assert.ok(trimmedProfiles.rows.length < hiddenActive.rows.length);
    assert.equal(trimmedProfiles.activeCount, 1);
    assert.equal(logic.barView({ state: "stopped" }, trimmedProfiles).icon, "shield-check");

    // Execute the production Import callback with private capability doubles.
    const importBody = /function importWireguard\(\) \{([\s\S]*?)\n    \}/.exec(service);
    assert.ok(importBody);
    const importRun = new Function("profiles", "shell", "root", importBody[1]);
    for (const [state, missing, refusal, offered, launched] of [
        ["available", [], undefined, [], 1],
        ["available", ["gum"], "refused: import=missing-tool", [["gum"]], 0],
        ["available", ["nmcli", "gum"], "refused: import=missing-tool", [["nmcli", "gum"]], 0],
        ["unavailable", [], "refused: import=unavailable", [], 0]
    ]) {
        const offers = [], launches = [];
        let refreshed = 0;
        const answer = importRun({ state }, { requirements: { missing, offer(commands) { offers.push(plain(commands)); return "ok"; } },
            tui: { run(name, args, done) { launches.push([name, args]); done(); return "ok"; } } }, { readProfiles() { refreshed++; } });
        assert.equal(answer, refusal === undefined ? "ok" : refusal);
        assert.deepEqual(offers, offered);
        assert.equal(launches.length, launched);
        assert.equal(refreshed, launched);
        if (launched) assert.deepEqual(launches[0], ["import-wireguard", []]);
    }
    const profileCrowd = Array.from({ length: 100 }, (_, i) => String(i).padStart(3, "0") + "\u0001".repeat(250) + ":vpn:").join("\n");
    const profileBound = plain(logic.profiles(0, profileCrowd));
    assert.equal(profileBound.rows.length, logic.PROFILE_MAX);
    assert.equal(profileBound.count, 100);
    assert.ok(Buffer.byteLength(JSON.stringify(Object.assign(profileBound, { action: "x".repeat(logic.TARGET_MAX), problem: "" }))) < STATUS_MAX_BYTES);

    // A drawn line holds no markup start and no control character.
    assert.equal(logic.line("a<b>\u0007c\n"), "ab>c");
    assert.equal(logic.line(7), "");
    assert.equal(logic.line("x".repeat(500)).length, logic.TEXT_MAX);

    // The largest tailnet stays under the status ceiling, with its counts.
    const wide = "w".repeat(400);
    const crowd = [];
    for (let i = 0; i < 300; i++) {
        crowd.push({ ID: "n" + String(i).padStart(63, "0"), DNSName: String(i).padStart(4, "0") + "." + "d".repeat(248) + ".", HostName: wide,
            TailscaleIPs: ["100.64.1." + (i % 250)], Online: true, ExitNodeOption: true, ExitNode: i === 299 });
        crowd.push({ ID: "m" + i, DNSName: wide, HostName: wide, Tags: mullvadTag, TailscaleIPs: ["100.64.2." + (i % 250)], Online: true,
            ExitNodeOption: true, Location: { City: i + wide, Country: wide, Priority: i } });
    }
    const peers = {};
    crowd.forEach((peer, index) => { peers["nodekey:" + index] = peer; });
    const largest = plain(logic.snapshot(0, JSON.stringify({ BackendState: "Running", Self: { HostName: wide, UserID: 1, TailscaleIPs: ["100.64.0.1"] },
        CurrentTailnet: { Name: wide }, User: { 1: { LoginName: wide } }, Peer: peers }), ""));
    assert.equal(largest.exitNodes.length, logic.EXIT_MAX);
    assert.equal(largest.exitCount, 600);
    assert.equal(largest.exitNodes.filter(row => row.active).length, 1, "the node in use is kept");
    assert.equal(largest.peers.length, logic.PEER_MAX);
    assert.equal(largest.peerCount, 300);
    const manyAccounts = plain(logic.accounts(0, "ID  Tailnet  Account\n" + Array.from({ length: 40 }, (_, i) => "a".repeat(63) + (i % 10) + "  " + wide + "  " + wide).join("\n"))).rows;
    assert.equal(manyAccounts.length, logic.ACCOUNT_MAX);
    const bytes = Buffer.byteLength(JSON.stringify(logic.published(false, largest, ready, { accounts: manyAccounts, action: "exit-node", login: "opened", problem: wide.slice(0, 200) })));
    assert.ok(bytes < STATUS_MAX_BYTES, "the largest vpn value is " + bytes + " bytes, the ceiling " + STATUS_MAX_BYTES);

    // Run the shipped publication body against the core judge. Large lists
    // grow, shrink and change together, so intermediate writes must fit too.
    const publishBody = /function publish\(\) \{([\s\S]*?)\n    \}\n    onPublishedChanged/.exec(service);
    assert.ok(publishBody);
    const publish = new Function("shell", "connection", "setup", "published", "profiles", "Logic", publishBody[1]);
    const bigVpn = plain(logic.published(false, largest, ready, { accounts: manyAccounts, action: "exit-node", login: "opened", problem: wide.slice(0, 200) }));
    const bigProfiles = Object.assign({}, profileBound, { action: profileBound.rows[0].id, problem: "NetworkManager could not change this connection." });
    assert.ok(Buffer.byteLength(JSON.stringify({ vpn: bigVpn, profiles: bigProfiles })) > STATUS_MAX_BYTES, "the unbounded combined fixture must exceed the core ceiling");
    const unicodeProfiles = plain(logic.profiles(0, Array.from({ length: 100 }, (_, i) => i + "界".repeat(250) + ":wireguard:activated").join("\n")));
    let values = {};
    const shell = { status: { set(key, value) {
        const result = core.statusWrite(manifest, values, key, value);
        assert.equal(result.ok, true, key + ": " + result.error);
        values = plain(result.values);
        assert.ok(Buffer.byteLength(JSON.stringify(values)) <= STATUS_MAX_BYTES);
        return "ok";
    } } };
    for (const [vpn, profileList, setupLine] of [
        [bigVpn, Object.assign({}, logic.emptyProfiles(), { action: "", problem: "" }), ready],
        [shown, bigProfiles, denied], [bigVpn, bigProfiles, ready],
        [bigVpn, Object.assign({}, unicodeProfiles, { action: unicodeProfiles.rows[0].id, problem: "" }), denied],
        [shown, Object.assign({}, profiles, { action: "", problem: "" }), ready]
    ]) {
        const original = JSON.stringify([vpn, profileList]);
        publish(shell, { tone: vpn.tone, text: vpn.text }, setupLine, vpn, profileList, logic);
        assert.equal(JSON.stringify([vpn, profileList]), original, "publication does not change the service's source lists");
        assert.equal(values.vpn.peerCount, vpn.peerCount);
        assert.equal(values.vpn.exitCount, vpn.exitCount);
        assert.equal(values.profiles.count, profileList.count);
        assert.equal(values.profiles.action, profileList.action);
        assert.equal(values.profiles.activeCount, profileList.activeCount);
        assert.ok(values.profiles.rows.length > 0 || profileList.rows.length === 0);
        for (const row of values.profiles.rows) {
            assert.deepEqual(row, profileList.rows.find(input => input.id === row.id));
            assert.deepEqual(plain(logic.profileCommand({ kind: row.active ? "profile-down" : "profile-up", id: row.id }, values.profiles)).argv,
                ["nmcli", "connection", row.active ? "down" : "up", "id", row.id]);
        }
        assert.deepEqual(values.vpn.exitNodes.filter(row => row.active), vpn.exitNodes.filter(row => row.active));
        for (const row of values.vpn.exitNodes) assert.deepEqual(row, vpn.exitNodes.find(input => input.id === row.id));
        assert.deepEqual(Object.keys(values), ["connection", "setup", "vpn", "profiles"]);
    }
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
        ["all types contribute to name ambiguity", 'names[fields[0]] = (names[fields[0]] || 0) + 1;', 'if (fields[1] === "vpn" || fields[1] === "wireguard") names[fields[0]] = (names[fields[0]] || 0) + 1;'],
        ["duplicates beyond the bound remain ambiguous", 'row.ambiguous = names[row.id] > 1;', 'row.ambiguous = retained.filter(other => other.id === row.id).length > 1;'],
        ["ambiguous profile commands refuse", 'if (row.ambiguous)', 'if (false)'],
        ["active profiles survive list limits", 'const activeCount = rows.filter(row => row.active).length;', 'const activeCount = rows.slice(0, PROFILE_MAX).filter(row => row.active).length;'],
        ["inactive Tailscale does not hide an active VPN", 'if (profiles.activeCount > 0)', 'if (vpn.state === "missing" && profiles.activeCount > 0)'],
        ["VPN profiles exclude other types", 'fields[1] !== "vpn" && fields[1] !== "wireguard"', 'false'],
        ["profile argv names id", '"down", "id", row.id]', '"down", row.id]'],
        ["profile lists are bounded", 'const retained = rows.slice(0, PROFILE_MAX);', 'const retained = rows.slice(0);'],
        ["the combined status record fits", 'var STATUS_DATA_BYTES = 32000;', 'var STATUS_DATA_BYTES = 65536;'],
        ["a target equal to the peer id", "{ id: peer.ID, target: target,", "{ id: peer.ID, target: peer.ID,"],
        ["a Mullvad node goes by its IPv4", "if (isMullvad(peer)) return address;", ""],
        ["the DNS name comes before the host name", 'if (dns !== "") return dns;', ""],
        ["the first IPv4, not the first address", "/^\\d{1,3}(\\.\\d{1,3}){3}$/.test(addresses[i])", "true"],
        ["one poll in flight", "if (state.flight) return { state: { flight: true,", "if (false) return { state: { flight: true,"],
        ["a refresh does not arm the watchdog", 'again: state.again || event === "refresh" }, effects: [] };', 'again: state.again || event === "refresh" }, effects: ["arm"] };'],
        ["the watchdog kills a poll in flight", 'effects: state.flight ? ["kill"] : [] };', "effects: [] };"],
        ["an open view polls fast", "return open ? OPEN_POLL_MS : idleSeconds * 1000;", "return idleSeconds * 1000;"],
        ["access denied is told apart", '{ kind: "access-denied", pattern: /access denied/i }', '{ kind: "access-denied", pattern: /prefs denied/i }'],
        ["a needed operator offers Allow", 'action: "allow" };', 'action: "" };'],
        ["an unread operator is not Ready", 'context.operator === "unknown" && REACHED', 'context.operator === "unread" && REACHED'],
        ["an exit node goes by its target", '"--exit-node=" + node.target]', '"--exit-node=" + node.id]'],
        ["the exit nodes are bounded", "var rows = all.slice(0, EXIT_MAX);", "var rows = all.slice(0);"],
        ["the node in use survives the bound", "rows[rows.length - 1] = active;", ""],
        ["one Mullvad node a city", "(row.active || rank > held.rank)", "false"],
        ["the node in use keeps its city", "!held.row.active && ", ""],
        ["only an https sign-in page opens", "/https:\\/\\/[^\\s\"'<>]+/", "/[a-z]+:\\/\\/[^\\s\"'<>]+/"],
        ["a drawn line holds no markup start", "\\u007f<]/g", "\\u007f]/g"]
    ]) {
        assert.equal(source.split(needle).length - 1, 1, name + " mutation must match once");
        const mutant = path.join(scratch, "VpnLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, replacement));
        assert.throws(() => suite(load(mutant, commons)), undefined, "control: " + name);
        console.log("vpn-logic: control=" + name + " red");
    }
    const publicationNeedle = "Logic.statusWrites(connection, setup, published, profiles)";
    assert.equal(serviceSource.split(publicationNeedle).length - 1, 1);
    const unboundedService = serviceSource.replace(publicationNeedle,
        '[["connection", { tone: connection.tone, text: connection.text }], ["setup", { tone: setup.tone, text: setup.text }], ["vpn", published], ["profiles", profiles]]');
    assert.throws(() => suite(load(file, commons), unboundedService));
    console.log("vpn-logic: control=service uses combined bound red");
    for (const [name, old, replacement] of [
        ["optional profile absence is informational", "if (code === 1 || code === 8) console.log(diagnostic);", "if (code === 1 || code === 8) console.warn(diagnostic);"],
        ["missing import tools offer setup", "if (needed.length > 0)", "if (false)"],
        ["import availability", 'if (profiles.state !== "available")', 'if (false)'],
        ["import completion refreshes", '() => root.readProfiles()', '() => {}']
    ]) {
        assert.equal(serviceSource.split(old).length - 1, 1, name);
        assert.throws(() => suite(load(file, commons), serviceSource.replace(old, replacement)));
        console.log("vpn-logic: control=" + name + " red");
    }
} finally { fs.rmSync(scratch, { recursive: true, force: true }); }
console.log("vpn-logic: passed");
