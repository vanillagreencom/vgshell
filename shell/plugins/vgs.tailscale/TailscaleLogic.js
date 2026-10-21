.pragma library
.import qs.Commons 1.0 as Commons
// Pure decisions for the Tailscale section: the poll's one-in-flight rule,
// the snapshot read from `tailscale status --json`, each exit node's CLI
// target, the argv of every command, and the lines the views draw.
// Service.qml runs the effects.

// A poll that has not ended after this long is killed. Only a poll's start
// arms the deadline, so a refresh cannot move it.
var WATCHDOG_MS = 10000;
// The poll interval while a flyout or the pane is open.
var OPEN_POLL_MS = 3000;
// A command that changes Tailscale is killed after this long.
var ACTION_MS = 30000;
// A sign-in the user has not finished is ended after this long.
var LOGIN_MS = 300000;
// The most the service keeps of what a sign-in run prints, in characters.
var LOGIN_SAID_MAX = 4096;
// List ceilings bound retained rows. statusWrites also bounds their JSON
// bytes together under the core's per-plugin ceiling (D037).
var PEER_MAX = 64;
var EXIT_MAX = 80;
var ACCOUNT_MAX = 16;
var TEXT_MAX = 64;
// The longest DNS name, the longest target a node can have.
var TARGET_MAX = 253;
// The tag Tailscale gives each Mullvad exit node.
var MULLVAD_TAG = "tag:mullvad-exit-node";

// The CLI's failure texts this plugin tells apart, first match wins.
var FAILURES = [
    { kind: "access-denied", pattern: /access denied/i },
    { kind: "service-off", pattern: /failed to connect to local tailscaled|doesn't appear to be running/i }
];

function failureKind(stderr) {
    var text = String(stderr);
    for (var i = 0; i < FAILURES.length; i++)
        if (FAILURES[i].pattern.test(text)) return FAILURES[i].kind;
    return "other";
}

function failureText(kind) {
    switch (kind) {
    case "access-denied": return "Tailscale refused the change for this account.";
    case "service-off": return "The Tailscale service is off.";
    case "timeout": return "Tailscale did not answer.";
    case "other": return "Tailscale could not make the change.";
    }
    throw new Error("tailscale: failure kind " + JSON.stringify(kind) + " is not one of access-denied, service-off, timeout, other");
}

function pollInterval(open, idleSeconds) {
    return open ? OPEN_POLL_MS : idleSeconds * 1000;
}

function pollIdle() { return { flight: false, again: false }; }

// One step of the poll: EVENT is `tick`, the timer; `refresh`, a request
// for a reading newer than now; `exit`, the poll's end; or `deadline`, the
// watchdog. Answers { state, effects }, effects in order from `start`,
// `arm`, `disarm` and `kill`. A poll in flight starts no second one: a
// tick is dropped and a refresh waits for the exit. Neither arms.
function pollStep(state, event) {
    switch (event) {
    case "tick":
    case "refresh":
        if (state.flight) return { state: { flight: true, again: state.again || event === "refresh" }, effects: [] };
        return { state: { flight: true, again: false }, effects: ["start", "arm"] };
    case "deadline":
        return { state: state, effects: state.flight ? ["kill"] : [] };
    case "exit":
        if (state.again) return { state: { flight: true, again: false }, effects: ["disarm", "start", "arm"] };
        return { state: pollIdle(), effects: ["disarm"] };
    }
    throw new Error("tailscale: poll event " + JSON.stringify(event) + " is not one of tick, refresh, exit, deadline");
}

// A name another device chose, as one drawn line: no control character,
// and no `<`, which makes Qt read a text as markup.
function line(value) {
    var text = typeof value === "string" ? value.replace(/[\u0000-\u001f\u007f<]/g, "") : "";
    return text.length > TEXT_MAX ? text.slice(0, TEXT_MAX) : text;
}

function firstIPv4(addresses) {
    if (!Array.isArray(addresses)) return "";
    for (var i = 0; i < addresses.length; i++)
        if (typeof addresses[i] === "string" && /^\d{1,3}(\.\d{1,3}){3}$/.test(addresses[i])) return addresses[i];
    return "";
}

function dnsName(peer) {
    return typeof peer.DNSName === "string" ? peer.DNSName.replace(/\.$/, "") : "";
}

function isMullvad(peer) {
    return Array.isArray(peer.Tags) && peer.Tags.indexOf(MULLVAD_TAG) !== -1;
}

// What `tailscale set --exit-node=` takes for PEER: its DNS name, else its
// host name, else its first IPv4; a Mullvad node's IPv4. "" for a peer
// with none of them. The peer id is the views' key and is never a target.
function exitTarget(peer) {
    var address = firstIPv4(peer.TailscaleIPs);
    if (isMullvad(peer)) return address;
    var dns = dnsName(peer);
    if (dns !== "") return dns;
    if (typeof peer.HostName === "string" && peer.HostName !== "") return peer.HostName;
    return address;
}

function peerName(peer) {
    var label = dnsName(peer).split(".")[0];
    if (label !== "") return line(label);
    if (typeof peer.HostName === "string" && peer.HostName !== "") return line(peer.HostName);
    return firstIPv4(peer.TailscaleIPs);
}

function place(peer) {
    var at = isPlain(peer.Location) ? peer.Location : {};
    return line([at.City, at.Country].filter(function (part) { return typeof part === "string" && part !== ""; }).join(", "));
}

function isPlain(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function byText(key) {
    return function (a, b) { return a[key] < b[key] ? -1 : a[key] > b[key] ? 1 : 0; };
}

// The exit nodes PEERS offer as { rows, count }: the tailnet's own nodes
// by name, then one Mullvad node a city, the one in use, else the one
// Tailscale ranks highest. A peer with no target, or with an id or target
// past its ceiling, is left out. `rows` holds at most EXIT_MAX, the node
// in use always among them.
function exitNodes(peers) {
    var own = [];
    var cities = {};
    peers.forEach(function (peer) {
        if (peer.ExitNodeOption !== true || typeof peer.ID !== "string" || peer.ID === "" || peer.ID.length > TEXT_MAX) return;
        var target = exitTarget(peer);
        if (target === "" || target.length > TARGET_MAX) return;
        var mullvad = isMullvad(peer);
        var row = { id: peer.ID, target: target, name: peerName(peer), place: mullvad ? place(peer) : "", mullvad: mullvad,
            online: peer.Online === true, active: peer.ExitNode === true };
        if (!mullvad) {
            own.push(row);
            return;
        }
        var rank = isPlain(peer.Location) && typeof peer.Location.Priority === "number" ? peer.Location.Priority : 0;
        var city = row.place !== "" ? row.place : row.id;
        var held = cities[city];
        if (held === undefined || (!held.row.active && (row.active || rank > held.rank))) cities[city] = { row: row, rank: rank };
    });
    var mullvadRows = Object.keys(cities).map(function (key) { return cities[key].row; });
    var all = own.sort(byText("name")).concat(mullvadRows.sort(byText("place")));
    var rows = all.slice(0, EXIT_MAX);
    var active = all.filter(function (row) { return row.active; })[0];
    if (active !== undefined && rows.indexOf(active) === -1) rows[rows.length - 1] = active;
    return { rows: rows, count: all.length };
}

function peerRows(peers) {
    var all = peers.filter(function (peer) { return !isMullvad(peer); }).map(function (peer) {
        return { name: peerName(peer), address: firstIPv4(peer.TailscaleIPs), online: peer.Online === true };
    });
    all.sort(function (a, b) { return Number(b.online) - Number(a.online) || byText("name")(a, b); });
    return { rows: all.slice(0, PEER_MAX), count: all.length };
}

var BACKEND_STATES = {
    Running: "running", Stopped: "stopped", NeedsLogin: "signed-out", NeedsMachineAuth: "needs-approval",
    Starting: "starting", NoState: "starting"
};

function emptySnapshot(state) {
    return { state: state, device: { name: "", address: "" }, tailnet: "", account: "", exit: null,
        exitNodes: [], exitCount: 0, peers: [], peerCount: 0 };
}

// What one `tailscale status --json` run reads: CODE its exit code, -1 for
// a run that was killed or never started. `state` is `checking` before
// the first run, then `running`, `stopped`, `signed-out`,
// `needs-approval`, `starting`, `service-off` for a daemon that does not
// answer, or `unavailable` for a run this cannot read.
function snapshot(code, stdout, stderr) {
    if (code !== 0) return emptySnapshot(failureKind(stderr) === "service-off" ? "service-off" : "unavailable");
    var doc;
    try {
        doc = JSON.parse(stdout);
    } catch (e) {
        return emptySnapshot("unavailable");
    }
    if (!isPlain(doc) || !Object.prototype.hasOwnProperty.call(BACKEND_STATES, doc.BackendState)) return emptySnapshot("unavailable");
    var out = emptySnapshot(BACKEND_STATES[doc.BackendState]);
    var self = isPlain(doc.Self) ? doc.Self : {};
    var users = isPlain(doc.User) ? doc.User : {};
    var user = users[String(self.UserID)];
    var peers = isPlain(doc.Peer) ? Object.keys(doc.Peer).map(function (key) { return doc.Peer[key]; }).filter(isPlain) : [];
    out.device = { name: peerName(self), address: firstIPv4(self.TailscaleIPs) };
    out.tailnet = isPlain(doc.CurrentTailnet) ? line(doc.CurrentTailnet.Name) : "";
    out.account = isPlain(user) ? line(user.LoginName) : "";
    var exits = exitNodes(peers);
    var active = exits.rows.filter(function (row) { return row.active; })[0];
    out.exit = active === undefined ? null : { id: active.id, name: active.place !== "" ? active.place : active.name };
    out.exitNodes = exits.rows;
    out.exitCount = exits.count;
    var listed = peerRows(peers);
    out.peers = listed.rows;
    out.peerCount = listed.count;
    return out;
}

// The accounts `tailscale switch --list` prints: a header line starting
// `ID`, then one line an account, its columns two or more spaces apart
// and the account in use ending in `*`. Answers { rows, fault }: `fault`
// is "" for a list this read, `failed` for a run that did not end with
// code 0 and `header` for output without that header, both with no rows.
function accounts(code, stdout) {
    var lines = String(stdout).split("\n").filter(function (text) { return text.trim() !== ""; });
    if (code !== 0) return { rows: [], fault: "failed" };
    if (lines.length === 0 || !/^ID\s/.test(lines[0])) return { rows: [], fault: "header" };
    var rows = [];
    lines.slice(1).forEach(function (text) {
        var columns = text.trim().split(/\s{2,}|\t+/);
        if (columns.length < 3 || columns[0].length > TEXT_MAX || rows.length === ACCOUNT_MAX) return;
        var current = /\*$/.test(columns[2]);
        rows.push({ id: columns[0], tailnet: line(columns[1]), account: line(columns[2].replace(/\*$/, "")), current: current });
    });
    return { rows: rows, fault: "" };
}

// The first https address in a line `tailscale login` prints, "" for none.
function loginUrl(text) {
    var found = /https:\/\/[^\s"'<>]+/.exec(String(text));
    return found === null ? "" : found[0];
}

var REACHED = ["running", "stopped", "signed-out", "needs-approval", "starting"];

// The argv of REQUEST, { kind, id? }, over what the service holds, DATA
// { state, exitNodes, accounts }: { argv }, or { refusal } for a request
// the state does not take or that names nothing listed. An exit node goes
// by its target; "" as the id turns the exit node off.
function command(request, data) {
    if (!isPlain(request) || typeof request.kind !== "string") return { refusal: "refused: action=malformed" };
    var refused = { refusal: "refused: action=" + request.kind + " state=" + data.state };
    switch (request.kind) {
    case "connect":
        return data.state === "stopped" ? { argv: ["tailscale", "up"] } : refused;
    case "disconnect":
        return data.state === "running" || data.state === "starting" ? { argv: ["tailscale", "down"] } : refused;
    case "exit-node":
        if (data.state !== "running") return refused;
        if (request.id === "") return { argv: ["tailscale", "set", "--exit-node="] };
        var node = data.exitNodes.filter(function (row) { return row.id === request.id; })[0];
        if (node === undefined) return { refusal: "refused: exit-node=absent" };
        return { argv: ["tailscale", "set", "--exit-node=" + node.target] };
    case "switch":
        if (REACHED.indexOf(data.state) === -1) return refused;
        var account = data.accounts.filter(function (row) { return row.id === request.id; })[0];
        if (account === undefined) return { refusal: "refused: account=absent" };
        return { argv: ["tailscale", "switch", account.id] };
    case "login":
        return REACHED.indexOf(data.state) !== -1 ? { argv: ["tailscale", "login", "--timeout", "0"] } : refused;
    }
    return { refusal: "refused: action=unknown" };
}

function stepOffered(step) { return step === "needed" || step === "nixos"; }

// The setup line: { tone, text, hint, action }, `text` the chip's short
// state, `hint` the sentence under it that names why and what the user can
// do, "" for none, and `action` the one step that applies now, `enable` or
// `allow`, or "" for none. CONTEXT is { missing, state, service, operator }:
// whether the `tailscale` command is absent, the snapshot's state and the
// two system steps' states, each "" while it has no reading, before the
// core's first probe ends. The line is null, which clears the entry, while
// a step it reads has no reading. A missing command names the one install
// action, `tools` (PluginLogic.STATUS_TOOLS_ACTION), whose Review the step's
// row offers, and the requirement is optional, so the line reads info.
// A step Tailscale needs
// reads warning while its action is offered; a state the user cannot
// change here reads info.
var SERVICE_UNOFFERED = {
    absent: { text: "Unavailable", hint: "This computer has no Tailscale service." },
    denied: { text: "Off", hint: "The system turned the Tailscale service off, and VGS leaves it off." }
};
function setupState(tone, text, hint, action) { return { tone: tone, text: text, hint: hint, action: action }; }
function setup(context) {
    if (context.missing) return setupState("info", "Not installed", "Choose Review all missing or outdated tools to install Tailscale", "tools");
    if (context.state === "service-off") {
        if (context.service === "") return null;
        if (stepOffered(context.service)) return setupState("warning", "Off", "The Tailscale service is off. Enable turns it on.", "enable");
        var unoffered = Object.prototype.hasOwnProperty.call(SERVICE_UNOFFERED, context.service) ? SERVICE_UNOFFERED[context.service]
            : { text: "Not checked", hint: "VGS could not check the Tailscale service." };
        return setupState("info", unoffered.text, unoffered.hint, "");
    }
    if (context.operator === "") return null;
    if (stepOffered(context.operator)) return setupState("warning", "Access needed", "The administrator holds Tailscale. After this step, VGS connects and disconnects for you without a password.", "allow");
    if (context.operator === "denied") return setupState("info", "Another account", "Another account controls Tailscale. Only that account can change it.", "");
    // The core's probe could not read the operator, so Ready would be a guess.
    if (context.operator === "unknown" && REACHED.indexOf(context.state) !== -1)
        return setupState("info", "Not checked", "VGS could not read who controls Tailscale.", "");
    return setupState("ok", "Ready", "", "");
}

// The connection line: { state, tone, text }. `missing` stands over the
// snapshot's state while the command is absent.
function connection(missing, snap) {
    var state = missing ? "missing" : snap.state;
    switch (state) {
    case "missing": return { state: state, tone: "warning", text: "Tailscale is not installed." };
    case "checking": return { state: state, tone: "info", text: "Checking Tailscale" };
    case "service-off": return { state: state, tone: "warning", text: "The Tailscale service is off." };
    case "unavailable": return { state: state, tone: "warning", text: "Tailscale did not answer." };
    case "signed-out": return { state: state, tone: "info", text: "Signed out" };
    case "needs-approval": return { state: state, tone: "warning", text: "This device waits for approval." };
    case "starting": return { state: state, tone: "info", text: "Starting" };
    case "stopped": return { state: state, tone: "info", text: "Off" };
    case "running": return { state: state, tone: "ok", text: snap.exit === null ? "Connected" : "Connected through " + snap.exit.name };
    }
    throw new Error("tailscale: state " + JSON.stringify(state) + " has no connection line");
}

// The `tailscale` value the service publishes and the views draw: the snapshot
// under the connection line, MISSING the command's absence, with
// `writable`, false while a setup step must run first, the install of a
// missing command among them, and
// true while SETUPLINE is null, before the steps' first reading, as for a
// step that could not be checked, and LIVE { accounts, action,
// login, problem }, what the service holds beside the snapshot.
function published(missing, snap, setupLine, live) {
    var shown = connection(missing, snap);
    return Object.assign({}, snap, { state: shown.state, tone: shown.tone, text: shown.text, writable: setupLine === null || setupLine.action === "",
        accounts: live.accounts, action: live.action, login: live.login, problem: live.problem, backendPresent: live.backendPresent !== false });
}

// What a view draws before the service's first write.
function unread() {
    return published(false, emptySnapshot("checking"), { action: "" }, { accounts: [], action: "", login: "idle", problem: "" });
}

// Why the controls `tailscale.writable` enables cannot change Tailscale now, as
// the one sentence each shows while disabled (its `disabledReason`), ""
// while they can. TAILSCALE is the published `tailscale` value, and STEP the words of
// the setup step the core offers now, "" for none. A value that is not
// writable has one cause (published, setup): the command is missing, the
// service is off, or the administrator holds Tailscale.
function lockReason(tailscale, step) {
    if (tailscale.writable) return "";
    if (tailscale.state === "missing") return "Tailscale is not installed, so choose Review all missing or outdated tools under [Optional tools in Tailscale Setup](page:vgs.tailscale/Setup) to use it.";
    var cause = tailscale.state === "service-off" ? "The Tailscale service is off" : "The administrator holds Tailscale";
    return step === "" ? cause + "; review [Tailscale service in Tailscale Setup](page:vgs.tailscale/Setup)." : cause + " until you choose " + step + " beside [Tailscale service in Tailscale Setup](page:vgs.tailscale/Setup).";
}

// The backend probe hides the icon without removing its saved placement.
function barView(tailscale) {
    if (!isPlain(tailscale) || tailscale.state === "missing" || tailscale.backendPresent === false)
        return { shown: false, icon: "route-off", spinning: false, warning: false, tooltip: "Tailscale" };
    return { shown: true, icon: tailscale.state === "running" ? (tailscale.exit === null ? "route" : "earth-lock") : "route-off",
        spinning: tailscale.state === "starting" || tailscale.action !== "" || tailscale.login !== "idle",
        warning: tailscale.tone === "warning" || !tailscale.writable,
        tooltip: "Tailscale: " + tailscale.text };
}

// Bound the snapshot with room for both state lines during sequential writes.
var STATUS_DATA_BYTES = 32000;

function statusWrites(connectionLine, setupLine, tailscaleValue) {
    var setupValue = null;
    if (setupLine !== null) {
        setupValue = { tone: setupLine.tone, text: setupLine.text };
        if (setupLine.hint !== "") setupValue.hint = setupLine.hint;
        if (setupLine.action !== "") setupValue.action = setupLine.action;
        // A required Setup step the user cannot act on here reads Not
        // available, its hint saying why (PluginLogic.statusDeclarationFits).
        else if (setupLine.tone !== "ok") setupValue.available = false;
    }
    var tailscale = Object.assign({}, tailscaleValue, { exitNodes: tailscaleValue.exitNodes.slice(), peers: tailscaleValue.peers.slice(), accounts: tailscaleValue.accounts.slice() });
    while (Commons.SettingValues.utf8Bytes(JSON.stringify(tailscale)) > STATUS_DATA_BYTES) {
        var last = tailscale.exitNodes.length - 1;
        while (last >= 0 && tailscale.exitNodes[last].active) last--;
        if (last >= 0) tailscale.exitNodes.splice(last, 1);
        else if (tailscale.peers.length > 0) tailscale.peers.pop();
        else tailscale.accounts.pop();
    }
    return [["connection", { tone: connectionLine.tone, text: connectionLine.text }], ["setup", setupValue], ["tailscale", tailscale]];
}
