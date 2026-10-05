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
const fixtures = path.join(__dirname, "fixtures/vpn");
const text = name => fs.readFileSync(path.join(fixtures, name), "utf8");
// The core's ceiling for one plugin's published status (status.md).
const STATUS_MAX_BYTES = 64 * 1024;
const plain = value => JSON.parse(JSON.stringify(value));

function suite(logic) {
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
}

suite(load(file));
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "vpn-logic-"));
try {
    const source = fs.readFileSync(file, "utf8");
    for (const [name, needle, replacement] of [
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
        assert.throws(() => suite(load(mutant)), undefined, "control: " + name);
        console.log("vpn-logic: control=" + name + " red");
    }
} finally { fs.rmSync(scratch, { recursive: true, force: true }); }
console.log("vpn-logic: passed");
