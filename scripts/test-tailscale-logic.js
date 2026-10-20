#!/usr/bin/env node
// The Tailscale section's decisions under the same loader as QML, over the
// `tailscale status --json` shapes in scripts/fixtures/tailscale/: running,
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
const PageReference = load(path.join(__dirname, "../shell/Commons/PageReference.js"));
const file = path.join(__dirname, "../shell/plugins/vgs.tailscale/TailscaleLogic.js");
const commons = { "qs.Commons 1.0": { SettingValues: load(path.join(__dirname, "../shell/Commons/SettingValues.js")) } };
const core = load(path.join(__dirname, "../shell/Core/PluginLogic.js"));
const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "../shell/plugins/vgs.tailscale/manifest.json"), "utf8"));
// The manifest as the core judges it, which the status judge reads.
const judged = core.validateManifest(manifest, path.join(__dirname, "../shell/plugins/vgs.tailscale")).manifest;
const serviceSource = fs.readFileSync(path.join(__dirname, "../shell/plugins/vgs.tailscale/Service.qml"), "utf8");
const fixtures = path.join(__dirname, "fixtures/tailscale");
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
    assert.deepEqual(running.device, { name: "desk", address: "100.64.0.1", dnsName: "desk.tail-fixture.ts.net" });
    assert.equal(running.tailnet, "fixture.example");
    assert.equal(running.account, "owner@fixture.example");
    assert.deepEqual(running.exit, { id: "nFIXTURE0002CNTRL", name: "gateway" });
    assert.deepEqual(running.devices.rows.map(row => [row.name, row.online]),
        [["100.64.0.4", true], ["attic box", true], ["gateway", true], ["laptop", true], ["backup", false]]);
    assert.equal(running.devices.count, 5);
    const stopped = read("stopped.json");
    assert.equal(stopped.state, "stopped");
    assert.equal(stopped.exit, null);
    const loggedOut = read("logged-out.json");
    assert.equal(loggedOut.state, "signed-out");
    assert.deepEqual([loggedOut.devices.rows, loggedOut.exitNodes.own, loggedOut.exitNodes.countries, loggedOut.account, loggedOut.tailnet], [[], [], [], "", ""]);
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
    assert.deepEqual(running.exitNodes.own.map(row => [row.id, row.target, row.active]), [
        ["nFIXTURE0004CNTRL", "100.64.0.4", false], ["nFIXTURE0003CNTRL", "attic box", false],
        ["nFIXTURE0002CNTRL", "gateway.tail-fixture.ts.net", true]
    ]);
    // One Mullvad node a city: the one in use, else the highest ranked.
    assert.deepEqual(mullvad.exitNodes.own.map(row => [row.id, row.target]), [["nFIXTURE0002CNTRL", "gateway.tail-fixture.ts.net"]]);
    assert.deepEqual(mullvad.exitNodes.countries.map(country => [country.name, country.cities.map(city => [city.id, city.target, city.name])]), [
        ["Sweden", [["nFIXTURE0011CNTRL", "100.64.0.11", "Stockholm"]]], ["Switzerland", [["nFIXTURE0013CNTRL", "100.64.0.13", "Zurich"]]]
    ]);
    assert.deepEqual(mullvad.exit, { id: "nFIXTURE0013CNTRL", name: "Zurich, Switzerland" });
    assert.deepEqual(mullvad.devices.rows.map(row => row.name), ["gateway", "laptop"]);
    const unaddressed = plain(logic.exitNodes([{ ID: "nG", ExitNodeOption: true, Tags: mullvadTag, TailscaleIPs: ["fd7a:115c:a1e0::d"] }]));
    assert.deepEqual(unaddressed, { own: [], countries: [], cityCount: 0, targets: {}, exit: null });
    const listedNodes = snapshot => snapshot.exitNodes.own.concat(...snapshot.exitNodes.countries.map(country => country.cities));
    for (const snapshot of [running, mullvad]) {
        const data = { state: "running", targets: snapshot.targets, accounts: [] };
        for (const node of listedNodes(snapshot)) {
            assert.notEqual(node.target, node.id);
            const argv = plain(logic.command({ kind: "exit-node", id: node.id }, data)).argv;
            assert.deepEqual(argv, ["tailscale", "set", "--exit-node=" + node.target]);
            assert.equal(argv.join(" ").includes(node.id), false, "the peer id reached the argv of " + node.id);
        }
    }

    // Every command's argv, and the refusals.
    const accountsJson = JSON.stringify([
        { id: "f1a0", nickname: "", tailnet: "fixture.example", account: "owner@fixture.example", selected: true },
        { id: "f1a1", nickname: "", tailnet: "second.example", account: "owner@second.example", selected: false }
    ], null, 2);
    const listed = plain(logic.accounts(0, accountsJson));
    const accounts = listed.rows;
    assert.equal(listed.fault, "");
    assert.deepEqual(accounts, [
        { id: "f1a0", tailnet: "fixture.example", account: "owner@fixture.example", current: true },
        { id: "f1a1", tailnet: "second.example", account: "owner@second.example", current: false }
    ]);
    for (const [code, stdout, fault] of [[1, accountsJson, "failed"], [0, "", "json"], [0, "{}", "json"]])
        assert.deepEqual(plain(logic.accounts(code, stdout)), { rows: [], fault: fault });
    const held = state => ({ state: state, targets: running.targets, accounts: accounts });
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
        assert.equal(logic.pollInterval(open, "running", seconds), want);

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
    // Ready over an operator the core could not read. The Setup tone rule
    // (design-system.md, Steps.js stepOpen): a step Tailscale needs reads
    // warning while its action is offered; the optional tool's absence and
    // a state the user cannot change here read info.
    const SETUP_ROWS = [
        [{ missing: true, state: "checking", service: "absent", operator: "absent" }, "", "info"],
        [{ missing: false, state: "service-off", service: "needed", operator: "unknown" }, "enable", "warning"],
        [{ missing: false, state: "service-off", service: "nixos", operator: "unknown" }, "enable", "warning"],
        [{ missing: false, state: "service-off", service: "absent", operator: "unknown" }, "", "info"],
        [{ missing: false, state: "service-off", service: "denied", operator: "unknown" }, "", "info"],
        [{ missing: false, state: "service-off", service: "unknown", operator: "unknown" }, "", "info"],
        [{ missing: false, state: "running", service: "ready", operator: "needed" }, "allow", "warning"],
        [{ missing: false, state: "stopped", service: "ready", operator: "nixos" }, "allow", "warning"],
        [{ missing: false, state: "running", service: "ready", operator: "denied" }, "", "info"],
        [{ missing: false, state: "running", service: "ready", operator: "unknown" }, "", "info"],
        [{ missing: false, state: "stopped", service: "ready", operator: "unknown" }, "", "info"],
        [{ missing: false, state: "running", service: "ready", operator: "ready" }, "", "ok"]
    ];
    for (const [context, action, tone] of SETUP_ROWS) {
        const shown = logic.setup(context);
        assert.deepEqual([shown.action, shown.tone], [action, tone], JSON.stringify(context));
        // The chip holds a short state, never a sentence; the sentence that
        // names why goes in the hint under it, which every line but Ready
        // carries and the published value keeps.
        assert.equal(shown.hint === "", tone === "ok", "a hint on every line but Ready: " + JSON.stringify(context));
        const written = logic.statusWrites({ tone: "ok", text: "" }, shown, logic.unread(), logic.emptySnapshot("checking").devices, logic.emptySnapshot("checking").exitNodes)[1][1];
        assert.equal(written.hint, shown.hint === "" ? undefined : shown.hint, "the published setup value keeps the hint");
        // A line that is not Ready and offers no step reads Not available on Setup.
        assert.equal(written.available, action === "" && tone !== "ok" ? false : undefined, "an unoffered line is Not available: " + JSON.stringify(context));
        assert.equal(core.statusWrite(judged, {}, "setup", written).ok, true, "the status judge admits the setup value: " + JSON.stringify(context));
    }
    // The line draws in the Tailscale service step on Setup, beside the
    // Optional tools step's Review action, so it links no page.
    assert.equal(PageReference.parse(logic.setup({ missing: true }).hint).page, "", "the Setup line links no page");
    // Before the core's first probe a step has no reading (""): the setup
    // line is null, so its entry is unreported, never Ready or Not checked.
    // A missing command needs no step reading and still reads Not installed.
    for (const context of [
        { missing: false, state: "running", service: "", operator: "" },
        { missing: false, state: "running", service: "ready", operator: "" },
        { missing: false, state: "service-off", service: "", operator: "" }
    ]) assert.equal(logic.setup(context), null, "no step reading, no setup line: " + JSON.stringify(context));
    assert.deepEqual([logic.setup({ missing: true, state: "checking", service: "", operator: "" }).tone], ["info"], "a missing command needs no step reading");
    assert.deepEqual(plain(logic.statusWrites({ tone: "ok", text: "" }, null, logic.unread(), logic.emptySnapshot("checking").devices, logic.emptySnapshot("checking").exitNodes)[1]), ["setup", null], "a null line clears the setup entry");
    const unoffered = ["absent", "denied", "unknown"].map(service => logic.setup({ missing: false, state: "service-off", service: service, operator: "unknown" }).hint);
    assert.equal(new Set(unoffered).size, unoffered.length, "each service state that offers no step names its own why");

    // The connection line and the bar icon.
    const states = ["missing", "checking", "service-off", "unavailable", "signed-out", "needs-approval", "starting", "stopped", "running"];
    const lines = states.map(state => logic.connection(state === "missing", logic.emptySnapshot(state === "missing" ? "checking" : state)));
    assert.deepEqual(lines.map(shown => shown.state), states);
    assert.equal(new Set(lines.map(shown => shown.text)).size, states.length);
    assert.throws(() => logic.connection(false, logic.emptySnapshot("future")));
    const live = { accounts: accounts, action: "", login: "idle", problem: "" };
    const ready = logic.setup({ missing: false, state: "running", service: "ready", operator: "ready" });
    const denied = logic.setup({ missing: false, state: "running", service: "ready", operator: "needed" });
    // The action names its result for the user, and the sentence before it holds none of its words.
    assert.equal(manifest.status.setup.actions.allow.label, "Let my login control Tailscale");
    const shown = plain(logic.published(false, running, ready, live));
    assert.deepEqual([shown.state, shown.tone, shown.writable], ["running", "ok", true]);
    assert.equal(logic.published(false, running, denied, live).writable, false);
    assert.equal(logic.published(false, running, null, live).writable, true, "no step reading locks nothing, as a step that could not be checked");
    assert.equal(logic.published(true, running, logic.setup({ missing: true, state: "running", service: "ready", operator: "ready" }), live).writable, false,
        "a missing command takes no change, though it offers no step");
    // Each locked value says why in one sentence, names the step the core
    // offers, and tells its cause apart even with no step.
    const steps = manifest.status.setup.actions;
    const locked = [
        [plain(logic.published(true, running, logic.setup({ missing: true, state: "running", service: "ready", operator: "ready" }), live)), ""],
        [plain(logic.published(false, logic.emptySnapshot("service-off"), logic.setup({ missing: false, state: "service-off", service: "needed", operator: "unknown" }), live)), steps.enable.label],
        [plain(logic.published(false, running, denied, live)), steps.allow.label]
    ];
    for (const [tailscale, step] of locked) {
        const reason = logic.lockReason(tailscale, step);
        assert.equal(tailscale.writable, false, tailscale.state);
        assert.ok(/^[A-Z][^.!?]*\.$/.test(PageReference.plain(reason)), "one sentence: " + JSON.stringify(reason));
        assert.ok(!/\btailscale |sudo|vgshell|systemctl/.test(reason), "no command: " + JSON.stringify(reason));
        assert.ok(step === "" || reason.includes(step), "names the step: " + JSON.stringify(reason));
        for (const offered of [step, ""]) {
            const link = PageReference.parse(logic.lockReason(tailscale, offered));
            assert.deepEqual([link.page, link.tab], [manifest.id, "Setup"], "offered and unoffered reasons open the Tailscale service step on Setup");
        }
    }
    // Distinct lock causes retain distinct reasons.
    const causes = locked.map(([tailscale]) => logic.lockReason(tailscale, ""));
    assert.equal(new Set(causes).size, causes.length, "each cause says its own why");
    assert.equal(plain(logic.unread()).state, "checking");
    for (const [tailscale, want] of [
        [null, { shown: false }], [plain(logic.published(true, running, ready, live)), { shown: false }],
        [shown, { shown: true, icon: "earth-lock" }],
        [plain(logic.published(false, Object.assign({}, running, { exit: null }), ready, live)), { shown: true, icon: "route" }],
        [plain(logic.published(false, stopped, ready, live)), { shown: true, icon: "route-off" }],
        [plain(logic.published(false, logic.emptySnapshot("service-off"), ready, live)), { shown: true, icon: "route-off" }]
    ]) {
        const view = logic.barView(tailscale);
        for (const key of Object.keys(want)) assert.equal(view[key], want[key], key + " of " + (tailscale === null ? "null" : tailscale.state));
    }

    assert.equal(logic.lockReason(shown, steps.allow.label), "");
    for (const [state, action, login, spinning, warning] of [
        ["starting", "", "idle", true, false], ["running", "connect", "idle", true, false],
        ["signed-out", "", "waiting", true, false], ["signed-out", "", "idle", false, false],
        ["needs-approval", "", "idle", false, true], ["unavailable", "", "idle", false, true]
    ]) {
        const value = logic.published(false, logic.emptySnapshot(state), ready, { accounts: [], action, login, problem: "" });
        const icon = logic.barView(value);
        assert.deepEqual([icon.spinning, icon.warning], [spinning, warning], state);
    }
    assert.equal(logic.barView(Object.assign({}, shown, { backendPresent: false })).shown, false);
    assert.equal(logic.barView(logic.published(false, running, ready, Object.assign({}, live, { backendPresent: false }))).shown, false);
    assert.equal(logic.barView(logic.published(false, running, denied, live)).warning, true);
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
    const cities = largest.exitNodes.countries.reduce((all, country) => all.concat(country.cities), []);
    assert.equal(cities.length, logic.CITY_MAX);
    assert.equal(largest.exitNodes.cityCount, 300);
    assert.equal(largest.exitNodes.own.length, logic.PEER_MAX);
    assert.equal(largest.exitNodes.own.filter(row => row.active).length, 1, "the node in use is kept");
    assert.equal(largest.devices.rows.length, logic.PEER_MAX);
    assert.equal(largest.devices.count, 300);
    const manyAccounts = plain(logic.accounts(0, JSON.stringify(Array.from({ length: 40 }, (_, i) => ({ id: "a".repeat(63) + (i % 10), tailnet: wide, account: wide, selected: false }))))).rows;
    assert.equal(manyAccounts.length, logic.ACCOUNT_MAX);
    const bigValue = plain(logic.published(false, largest, ready, { accounts: manyAccounts, action: "exit-node", login: "opened", problem: wide.slice(0, 200) }));
    const written = logic.statusWrites({ tone: "ok", text: "" }, denied, bigValue, largest.devices, largest.exitNodes);
    const bytes = Buffer.byteLength(JSON.stringify(Object.fromEntries(written)));
    assert.ok(bytes < STATUS_MAX_BYTES, "the largest status is " + bytes + " bytes, the ceiling " + STATUS_MAX_BYTES);

    // Execute the production writer against the core judge, including
    // shrink/grow transitions and a null setup that clears its state entry.
    const publishBody = /function publish\(\) \{([\s\S]*?)\n    \}\n    onPublishedChanged/.exec(service);
    assert.ok(publishBody);
    const publish = new Function("shell", "connection", "setup", "published", "snapshot", "Logic", publishBody[1]);
    let values = {};
    const shell = { status: { set(key, value) {
        const result = core.statusWrite(manifest, values, key, value);
        assert.equal(result.ok, true, key + ": " + result.error);
        values = plain(result.values);
        assert.ok(Buffer.byteLength(JSON.stringify(values)) <= STATUS_MAX_BYTES);
        return "ok";
    } } };
    for (const [data, snap, setupLine] of [[bigValue, largest, ready], [shown, running, denied], [bigValue, largest, denied], [shown, running, null]]) {
        const original = JSON.stringify([data, snap]);
        publish(shell, { tone: data.tone, text: data.text }, setupLine, data, snap, logic);
        assert.equal(JSON.stringify([data, snap]), original);
        assert.equal(values.devices.count, snap.devices.count);
        assert.equal(values.exitNodes.cityCount, snap.exitNodes.cityCount);
        assert.deepEqual(values.exitNodes.own.filter(row => row.active), snap.exitNodes.own.filter(row => row.active));
        for (const row of values.exitNodes.own) assert.deepEqual(row, snap.exitNodes.own.find(input => input.id === row.id));
        assert.deepEqual(Object.keys(values), setupLine === null ? ["connection", "tailscale", "devices", "exitNodes"] : ["connection", "setup", "tailscale", "devices", "exitNodes"]);
    }
}

suite(load(file, commons));
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "tailscale-logic-"));
try {
    const source = fs.readFileSync(file, "utf8");
    for (const [name, needle, replacement] of [
        ["a missing command takes no change", 'writable: !missing && (setupLine === null || setupLine.action === ""),', 'writable: (setupLine === null || setupLine.action === ""),'],
        ["a writable value gives no reason", 'if (tailscale.writable) return "";', ''],
        ["a service that is off is told apart", 'tailscale.state === "service-off" ? "The', 'false ? "The'],
        ["the reason names the step", 'return step === "" ? cause +', 'return true ? cause +'],
        ["an unoffered setup line waits on the user", '        else if (setupLine.tone !== "ok") setupValue.available = false;\n', ''],
        ["a blocked service opens its Setup step", 'cause + "; review [Tailscale service in Tailscale Setup](page:vgs.tailscale/Setup)."', 'cause + "; review [Tailscale in Details](page:vgs.tailscale/Details)."'],
        ["a target equal to the peer id", "targets[peer.ID] = { target: target,", "targets[peer.ID] = { target: peer.ID,"],
        ["a Mullvad node goes by its IPv4", "if (isMullvad(peer)) return address;", ""],
        ["the DNS name comes before the host name", 'if (dns !== "") return dns;', ""],
        ["the first IPv4, not the first address", "/^\\d{1,3}(\\.\\d{1,3}){3}$/.test(addresses[i])", "true"],
        ["one poll in flight", "if (state.flight) return { state: { flight: true,", "if (false) return { state: { flight: true,"],
        ["a refresh does not arm the watchdog", 'again: state.again || event === "refresh" }, effects: [] };', 'again: state.again || event === "refresh" }, effects: ["arm"] };'],
        ["the watchdog kills a poll in flight", 'effects: state.flight ? ["kill"] : [] };', "effects: [] };"],
        ["an open view polls fast", "return open || state === \"starting\" ? FAST_POLL_MS : idleSeconds * 1000;", "return idleSeconds * 1000;"],
        ["access denied is told apart", '{ kind: "access-denied", pattern: /access denied/i }', '{ kind: "access-denied", pattern: /prefs denied/i }'],
        ["a needed operator offers Allow", 'for you without a password.", "allow");', 'for you without a password.", "");'],
        ["a missing optional tool reads info", 'if (context.missing) return setupState("info"', 'if (context.missing) return setupState("warning"'],
        ["an offered service step reads warning", 'return setupState("warning", "Off"', 'return setupState("info", "Off"'],
        ["a service the user cannot turn on reads info", 'return setupState("info", unoffered.text', 'return setupState("warning", unoffered.text'],
        ["each unoffered service state names why", '    denied: { text: "Off", hint: "The system turned the Tailscale service off, and VGS leaves it off." }\n', ''],
        ["another account's operator reads info", 'return setupState("info", "Another account"', 'return setupState("warning", "Another account"'],
        ["the published setup value keeps its hint", 'if (setupLine.hint !== "") setupValue.hint = setupLine.hint;', ''],
        ["an unread operator is not Ready", 'context.operator === "unknown" && REACHED', 'context.operator === "unread" && REACHED'],
        ["an operator with no reading reads Ready", '    if (context.operator === "") return null;\n', ''],
        ["a service with no reading reads Not checked", '        if (context.service === "") return null;\n', ''],
        ["an exit node goes by its target", '"--exit-node=" + node.target]', '"--exit-node=" + node.id]'],
        ["the exit nodes are bounded", "var kept = rows.slice(0, max);", "var kept = rows.slice(0);"],
        ["the node in use survives the bound", "kept[kept.length - 1] = active;", ""],
        ["one Mullvad node a city", "return a.rank > held.rank;", "return false;"],
        ["the node in use keeps its city", "if (a.active !== held.active) return a.active;", ""],
        ["only an https sign-in page opens", "/https:\\/\\/[^\\s\"'<>]+/", "/[a-z]+:\\/\\/[^\\s\"'<>]+/"],
        ["a drawn line holds no markup start", "\\u007f<]/g", "\\u007f]/g"],
        ["absent service hides", ' || tailscale.backendPresent === false', ''],
        ["exit node uses a distinct icon", '(tailscale.exit === null ? "route" : "earth-lock")', '"route"'],
        ["starting spins", 'tailscale.state === "starting" || ', ''],
        ["access needed warns", ' || !tailscale.writable', '']
    ]) {
        assert.equal(source.split(needle).length - 1, 1, name + " mutation must match once");
        const mutant = path.join(scratch, "TailscaleLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, replacement));
        assert.throws(() => suite(load(mutant, commons)), undefined, "control: " + name);
        console.log("tailscale-logic: control=" + name + " red");
    }
} finally { fs.rmSync(scratch, { recursive: true, force: true }); }
console.log("tailscale-logic: passed");
