.pragma library
.import qs.Commons 1.0 as Commons
// Pure decisions for Tailscale: the poll's one-in-flight rule and its rate,
// the snapshot read from `tailscale status --json`, the accounts read from
// `tailscale switch --list --json`, the node `tailscale exit-node suggest`
// names, each exit node's CLI target, the argv of every command, the three
// status values and their byte budgets, and the lines and rows the views
// draw. Service.qml runs the effects.

// A read, a poll, the accounts or a suggestion, that has not ended after
// this long is killed. Only a read's start arms the deadline, so a refresh
// cannot move it.
var WATCHDOG_MS = 10000;
// The poll interval while a view is open or Tailscale is starting.
var FAST_POLL_MS = 3000;
// A command that changes Tailscale is killed after this long.
var ACTION_MS = 30000;
// A sign-in the user has not finished is ended after this long.
var LOGIN_MS = 300000;
// The most the service keeps of what a sign-in run prints, in characters.
var LOGIN_SAID_MAX = 4096;
// List ceilings bound retained rows: the network devices and your own exit
// nodes each, the Mullvad cities, the accounts. statusWrites also bounds
// each value's JSON bytes under the core's per-plugin ceiling (D037).
var PEER_MAX = 64;
var CITY_MAX = 160;
var ACCOUNT_MAX = 16;
// The most matches the chooser's search draws at once. The view builds
// each row a keystroke adds on the GUI thread, about 1 ms a row: 100
// DeviceList rows took 105-126 ms to build in a qmltestrunner offscreen
// run (VGS-1929, 2026-10-21), so the first keystroke over a tailnet's 64
// own nodes and 160 cities would build 224 rows without it.
var SEARCH_MAX = 20;
var TEXT_MAX = 64;
// The longest DNS name, the longest target a node can have.
var TARGET_MAX = 253;
// The tag Tailscale gives each Mullvad exit node.
var MULLVAD_TAG = "tag:mullvad-exit-node";
// The page Open admin console opens. Users, access, approval, keys and
// device removal stay there; VGS rebuilds none of it.
var ADMIN_URL = "https://login.tailscale.com/admin";
var IN_USE = "In use";
// The requests that need the manifest's tailscale `floor`: the add
// transaction reads `debug prefs` and Status.AuthURL as v1.104.1 prints
// them (bin/lib/tailscale-account.py), and sign-in's `up` authenticates
// the selected profile as v1.104.1 cli/up.go does. Every other request
// works on an older Tailscale.
var FLOOR_KINDS = ["add-account", "sign-in"];
var BUSY_TEXT = "A Tailscale change is still in progress.";
var CHECKING_TEXT = "VGS is checking Tailscale access.";

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

// The poll's interval: fast while a view is OPEN, and while STATE reads
// `starting`, so the bar shows the connection as soon as it comes up after
// boot or a connect; else IDLESECONDS, the `pollSeconds` setting.
function pollInterval(open, state, idleSeconds) {
    return open || state === "starting" ? FAST_POLL_MS : idleSeconds * 1000;
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
function line(value, max) {
    var text = typeof value === "string" ? value.replace(/[\u0000-\u001f\u007f<]/g, "") : "";
    var most = max === undefined ? TEXT_MAX : max;
    return text.length > most ? text.slice(0, most) : text;
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

// A peer's DNS name as a drawn line, without its final dot; "" for one
// past the longest DNS name.
function dnsLine(peer) {
    var name = dnsName(peer);
    return name.length > TARGET_MAX ? "" : line(name, TARGET_MAX);
}

function isMullvad(peer) {
    return Array.isArray(peer.Tags) && peer.Tags.indexOf(MULLVAD_TAG) !== -1;
}

function isTagged(peer) {
    return Array.isArray(peer.Tags) && peer.Tags.length > 0;
}

function validId(id) {
    return typeof id === "string" && id !== "" && id.length <= TEXT_MAX;
}

// PEER's operating system as Tailscale reports it, lowercased: the one
// reading peerIcon and sshCapable share.
function osOf(peer) {
    return typeof peer.OS === "string" ? peer.OS.toLowerCase() : "";
}

// The row icon for PEER: a phone for iOS and Android, a server for a
// tagged peer, which a person does not carry, a laptop otherwise.
function peerIcon(peer) {
    var os = osOf(peer);
    if (os === "ios" || os === "android") return "smartphone";
    if (isTagged(peer)) return "server";
    return "laptop";
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

function rank(peer) {
    return isPlain(peer.Location) && typeof peer.Location.Priority === "number" ? peer.Location.Priority : 0;
}

function isPlain(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function has(map, key) {
    return Object.prototype.hasOwnProperty.call(map, key);
}

function byText(key) {
    return function (a, b) { return a[key] < b[key] ? -1 : a[key] > b[key] ? 1 : 0; };
}

function onlineFirst(a, b) {
    return Number(b.online) - Number(a.online) || byText("name")(a, b);
}

// Whether node A, with its rank, beats the node HELD for its place: the
// node in use, then an online node, then the higher rank.
function beats(a, held) {
    if (held === undefined) return true;
    if (a.active !== held.active) return a.active;
    if (a.online !== held.online) return a.online;
    return a.rank > held.rank;
}

// ROWS bounded to MAX, the one row in use kept in the last place.
function keepActive(rows, max) {
    var kept = rows.slice(0, max);
    var active = rows.filter(function (row) { return row.active; })[0];
    if (active !== undefined && kept.indexOf(active) === -1) kept[kept.length - 1] = active;
    return kept;
}

// The exit nodes PEERS offer: { own, countries, cityCount, targets, exit }.
// `own` is the tailnet's own nodes, online first then by name, at most
// PEER_MAX, the one in use kept: { id, target, name, os, icon, online,
// active }. `countries` is the Mullvad nodes by country, then city, each by
// name: { code, name, best: { id, city }, cities: [{ code, name, id,
// target, active }] }. A city keeps the node in use, else an online node
// before an offline one, then the one Tailscale ranks highest
// (Location.Priority); `best` is the country's online node it ranks
// highest, which Best available uses at the moment of the click. At most
// CITY_MAX cities are kept, the one in use always among them; `cityCount`
// counts them all. `targets` maps every exit node's id to { target,
// online, mullvad, dns, name }, for the command and the suggestion, and
// is never published. `exit` is the node in use, { id, name }, or null. A
// peer with no target, or with an id or target past its ceiling, is left
// out.
function exitNodes(peers) {
    var own = [];
    var targets = {};
    var places = {};
    var exit = null;
    peers.forEach(function (peer) {
        if (peer.ExitNodeOption !== true || !validId(peer.ID)) return;
        var target = exitTarget(peer);
        if (target === "" || target.length > TARGET_MAX) return;
        var mullvad = isMullvad(peer);
        var node = { id: peer.ID, target: target, online: peer.Online === true, active: peer.ExitNode === true, rank: rank(peer) };
        var shown = mullvad && place(peer) !== "" ? place(peer) : peerName(peer);
        targets[peer.ID] = { target: target, online: node.online, mullvad: mullvad, dns: dnsName(peer).toLowerCase(), name: shown };
        if (node.active) exit = { id: peer.ID, name: shown };
        if (!mullvad) {
            own.push({ id: peer.ID, target: target, name: peerName(peer), os: line(peer.OS), icon: peerIcon(peer), online: node.online, active: node.active });
            return;
        }
        var at = isPlain(peer.Location) ? peer.Location : {};
        var countryName = line(at.Country);
        var cityName = line(at.City);
        if (countryName === "" || cityName === "") return;
        var countryCode = line(at.CountryCode) !== "" ? line(at.CountryCode) : countryName;
        var cityCode = line(at.CityCode) !== "" ? line(at.CityCode) : cityName;
        if (!has(places, countryCode)) places[countryCode] = { code: countryCode, name: countryName, best: null, cities: {} };
        var country = places[countryCode];
        var held = country.cities[cityCode];
        if (beats(node, held === undefined ? undefined : held.node))
            country.cities[cityCode] = { node: node, row: { code: cityCode, name: cityName, id: node.id, target: target, active: node.active } };
        // Best available never picks by the node in use, only by rank.
        var ranked = { active: false, online: node.online, rank: node.rank };
        if (country.best === null || beats(ranked, country.best.node)) country.best = { node: ranked, id: node.id, city: cityName };
    });
    var countries = Object.keys(places).map(function (code) {
        var country = places[code];
        var cities = Object.keys(country.cities).map(function (key) { return country.cities[key].row; }).sort(byText("name"));
        return { code: country.code, name: country.name, best: { id: country.best.id, city: country.best.city }, cities: cities };
    }).sort(byText("name"));
    var all = [];
    countries.forEach(function (country) { all = all.concat(country.cities); });
    var kept = keepActive(all, CITY_MAX);
    countries = countries.map(function (country) {
        return Object.assign({}, country, { cities: country.cities.filter(function (city) { return kept.indexOf(city) !== -1; }) });
    }).filter(function (country) { return country.cities.length > 0; });
    return { own: keepActive(own.sort(onlineFirst), PEER_MAX), countries: countries, cityCount: all.length, targets: targets, exit: exit };
}

// The operating systems, as osOf reads them, of a device that runs an ssh
// server a user can reach: an allowlist, so an OS Tailscale adds later
// offers no connect until it is listed. iOS, Android, tvOS and `js`, the
// browser client, run none.
var SSH_SYSTEMS = ["linux", "macos", "windows", "freebsd", "openbsd", "illumos", "solaris"];

// Whether a network device PEER offers Connect in terminal: an OS of
// SSH_SYSTEMS and a DNS name, which ssh reaches. Online state does not
// count: a failed ssh stays on screen in the terminal.
function sshCapable(peer) {
    return SSH_SYSTEMS.indexOf(osOf(peer)) !== -1 && dnsLine(peer) !== "";
}

// The network devices PEERS hold, Mullvad nodes left out: { rows, count,
// online }, `rows` online first then by name, at most PEER_MAX: { id, name,
// os, icon, address, dnsName, online, connects }, `connects` as sshCapable
// reads the peer. `count` and `online` count every device, kept or not.
function devices(peers) {
    var all = peers.filter(function (peer) { return !isMullvad(peer) && validId(peer.ID); }).map(function (peer) {
        return { id: peer.ID, name: peerName(peer), os: line(peer.OS), icon: peerIcon(peer), address: firstIPv4(peer.TailscaleIPs),
            dnsName: dnsLine(peer), online: peer.Online === true, connects: sshCapable(peer) };
    });
    all.sort(onlineFirst);
    return { rows: all.slice(0, PEER_MAX), count: all.length, online: all.filter(function (row) { return row.online; }).length };
}

var BACKEND_STATES = {
    Running: "running", Stopped: "stopped", NeedsLogin: "signed-out", NeedsMachineAuth: "needs-approval",
    Starting: "starting", NoState: "starting"
};

function emptySnapshot(state) {
    return { state: state, device: { name: "", address: "", dnsName: "" }, tailnet: "", account: "", exit: null,
        devices: { rows: [], count: 0, online: 0 }, exitNodes: { own: [], countries: [], cityCount: 0 }, targets: {} };
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
    if (!isPlain(doc) || !has(BACKEND_STATES, doc.BackendState)) return emptySnapshot("unavailable");
    var out = emptySnapshot(BACKEND_STATES[doc.BackendState]);
    var self = isPlain(doc.Self) ? doc.Self : {};
    var users = isPlain(doc.User) ? doc.User : {};
    var user = users[String(self.UserID)];
    var peers = isPlain(doc.Peer) ? Object.keys(doc.Peer).map(function (key) { return doc.Peer[key]; }).filter(isPlain) : [];
    out.device = { name: peerName(self), address: firstIPv4(self.TailscaleIPs), dnsName: dnsLine(self) };
    out.tailnet = isPlain(doc.CurrentTailnet) ? line(doc.CurrentTailnet.Name) : "";
    out.account = isPlain(user) ? line(user.LoginName) : "";
    var exits = exitNodes(peers);
    out.exit = exits.exit;
    out.exitNodes = { own: exits.own, countries: exits.countries, cityCount: exits.cityCount };
    out.targets = exits.targets;
    out.devices = devices(peers);
    return out;
}

// The accounts `tailscale switch --list --json` prints: an array of
// { id, nickname, tailnet, account, selected }, `[]` with none. Answers
// { rows, fault }, rows { id, tailnet, account, current } in the CLI's
// order, at most ACCOUNT_MAX: `fault` is "" for a list this read, `failed`
// for a run that did not end with code 0 and `json` for output that is no
// JSON array, both with no rows. An entry with no id, or an id past its
// ceiling, is left out.
function accounts(code, stdout) {
    if (code !== 0) return { rows: [], fault: "failed" };
    var list;
    try {
        list = JSON.parse(stdout);
    } catch (e) {
        return { rows: [], fault: "json" };
    }
    if (!Array.isArray(list)) return { rows: [], fault: "json" };
    var rows = [];
    list.forEach(function (item) {
        if (!isPlain(item) || !validId(item.id) || rows.length === ACCOUNT_MAX) return;
        rows.push({ id: item.id, tailnet: line(item.tailnet), account: line(item.account), current: item.selected === true });
    });
    return { rows: rows, fault: "" };
}

// The node `tailscale exit-node suggest` names, from its text: the line
// "Suggested exit node: <DNS name>." gives the DNS name, without its final
// dot and in lower case; "No exit node suggestion is available." gives
// none. The CLI has no JSON form. CODE is the run's exit code, -1 for a
// run its deadline killed or that never started, as for `snapshot`.
// Answers { name, fault }: `fault` is "" for either text, `timeout` for
// code -1, `failed` for any other code but 0 and `unread` for any other
// text, all three with no name.
function suggested(code, stdout) {
    if (code === -1) return { name: "", fault: "timeout" };
    if (code !== 0) return { name: "", fault: "failed" };
    var lines = String(stdout).split("\n").map(function (text) { return text.trim(); });
    for (var i = 0; i < lines.length; i++) {
        var found = /^Suggested exit node: (\S+)$/.exec(lines[i]);
        if (found !== null) return { name: found[1].replace(/\.$/, "").toLowerCase(), fault: "" };
    }
    if (lines.indexOf("No exit node suggestion is available.") !== -1) return { name: "", fault: "" };
    return { name: "", fault: "unread" };
}

// The suggested node NAME names among SNAP's exit nodes, compared
// case-blind without the final dot: { id, name }, `name` its place or its
// name, or null for no name or a name no listed node holds.
function suggestion(name, snap) {
    if (name === "") return null;
    var ids = Object.keys(snap.targets);
    for (var i = 0; i < ids.length; i++)
        if (snap.targets[ids[i]].dns === name) return { id: ids[i], name: snap.targets[ids[i]].name };
    return null;
}

// The first https address in a line `tailscale up` prints, "" for none.
function loginUrl(text) {
    var found = /https:\/\/[^\s"'<>]+/.exec(String(text));
    return found === null ? "" : found[0];
}

var REACHED = ["running", "stopped", "signed-out", "needs-approval", "starting"];

// The access an accounts read runs under: OPERATOR, the operator step's
// state, while tailscaled answers (STATE, the snapshot's, in REACHED), ""
// while it does not or has no reading. `switch --list` asks tailscaled,
// which answers when the daemon answers and the operator may read the
// profiles; the service step shows as the daemon answering.
function accountsAccess(operator, state) {
    return REACHED.indexOf(state) !== -1 ? operator : "";
}

// The argv of REQUEST, { kind, id? }, over what the service holds, DATA
// { state, targets, accounts, outdated }: { argv }, or { refusal } for a
// request the state does not take or that names nothing listed, with
// `update` true when only a newer Tailscale takes it (FLOOR_KINDS while
// OUTDATED). An exit node goes by its target; "" as the id turns the exit
// node off. An offline node of your own is refused, as Tailscale would
// route nothing through it.
function command(request, data) {
    if (!isPlain(request) || typeof request.kind !== "string") return { refusal: "refused: action=malformed" };
    if (data.outdated === true && FLOOR_KINDS.indexOf(request.kind) !== -1)
        return { refusal: "refused: action=" + request.kind + " state=outdated", update: true };
    var refused = { refusal: "refused: action=" + request.kind + " state=" + data.state };
    switch (request.kind) {
    case "connect":
        return data.state === "stopped" ? { argv: ["tailscale", "up"] } : refused;
    case "disconnect":
        return data.state === "running" || data.state === "starting" ? { argv: ["tailscale", "down"] } : refused;
    case "exit-node":
        if (data.state !== "running") return refused;
        if (request.id === "") return { argv: ["tailscale", "set", "--exit-node="] };
        if (typeof request.id !== "string" || !has(data.targets, request.id)) return { refusal: "refused: exit-node=absent" };
        var node = data.targets[request.id];
        if (!node.mullvad && !node.online) return { refusal: "refused: exit-node=offline" };
        return { argv: ["tailscale", "set", "--exit-node=" + node.target] };
    case "sign-in":
    case "switch":
        if (REACHED.indexOf(data.state) === -1) return refused;
        var account = data.accounts.filter(function (row) { return row.id === request.id; })[0];
        if (account === undefined) return { refusal: "refused: account=absent" };
        return { argv: ["tailscale", "switch", account.id] };
    case "add-account":
        return REACHED.indexOf(data.state) !== -1 ? { system: "accountAdd" } : refused;
    case "logout":
        return REACHED.indexOf(data.state) !== -1 ? { argv: ["tailscale", "logout"] } : refused;
    case "admin-console":
        return { argv: ["xdg-open", ADMIN_URL] };
    }
    return { refusal: "refused: action=unknown" };
}

// The sentence a view shows for the service's REPLY to a request, "" for
// `ok`.
function replyText(reply) {
    switch (reply) {
    case "ok": return "";
    case "busy": return BUSY_TEXT;
    case "refused: exit-node=offline": return "This exit node is offline.";
    case "refused: admin-console=missing-tool":
    case "refused: login=missing-tool": return "This needs a tool to open your browser. Use the installation notice to add it.";
    }
    return "Tailscale cannot do this now.";
}

function stepOffered(step) { return step === "needed" || step === "nixos"; }

// The setup line: { tone, text, hint, action }, `text` the chip's short
// state, `hint` the sentence under it that names why and what the user can
// do, "" for none, and `action` the one step that applies now, `enable` or
// `allow`, or "" for none. CONTEXT is { missing, state, service, operator }:
// whether the `tailscale` command is absent, the snapshot's state and the
// two system steps' states, each "" while it has no reading, before the
// core's first probe ends. An outdated command sets no line: it locks only
// FLOOR_KINDS, and Setup's Optional tools step offers its update. The line is null, which clears the entry, while
// a step it reads has no reading. A missing command offers no step: the
// Review action of the page's Optional tools step installs it, and the
// requirement is optional, so the line reads info. A step Tailscale needs
// reads warning while its action is offered; a state the user cannot
// change here reads info.
var SERVICE_UNOFFERED = {
    absent: { text: "Unavailable", hint: "This computer has no Tailscale service." },
    denied: { text: "Off", hint: "The system turned the Tailscale service off, and VGS leaves it off." }
};
function setupState(tone, text, hint, action) { return { tone: tone, text: text, hint: hint, action: action }; }
function setup(context) {
    if (context.missing) return setupState("info", "Not installed", "Tailscale is optional. Choose Review all missing or outdated tools to use it.", "");
    if (context.state === "service-off") {
        if (context.service === "") return null;
        if (stepOffered(context.service)) return setupState("warning", "Off", "The Tailscale service is off. Enable turns it on.", "enable");
        var unoffered = has(SERVICE_UNOFFERED, context.service) ? SERVICE_UNOFFERED[context.service]
            : { text: "Not checked", hint: "VGS could not check the Tailscale service." };
        return setupState("info", unoffered.text, unoffered.hint, "");
    }
    if (context.operator === "") return null;
    if (stepOffered(context.operator)) return setupState("warning", "Access needed", "The administrator holds Tailscale. After this step, VGS connects and disconnects for you without a password.", "allow");
    if (context.operator === "denied") return setupState("info", "Another account", "Another account controls Tailscale. Only that account can change it.", "");
    // The core's probe could not read the operator, so Ready would be a guess.
    if (context.operator !== "ready")
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
    case "unavailable": return { state: state, tone: "warning", text: "Not answering" };
    case "signed-out": return { state: state, tone: "info", text: "Signed out" };
    case "needs-approval": return { state: state, tone: "warning", text: "Waiting for approval" };
    case "starting": return { state: state, tone: "info", text: "Starting" };
    case "stopped": return { state: state, tone: "info", text: "Off" };
    case "running": return { state: state, tone: "ok", text: snap.exit === null ? "Connected" : "Connected through " + snap.exit.name };
    }
    throw new Error("tailscale: state " + JSON.stringify(state) + " has no connection line");
}

// The `tailscale` value the service publishes and the views draw: the
// connection line, the account, this device and the exit node in use,
// with `writable`, false while the command is MISSING or the Allow step or
// another setup step must run first or its fresh reading is pending,
// and LIVE { accounts, accountsRead, outdated, action, login, problem,
// suggestion, backendPresent }, what the service holds beside the
// snapshot: `accountsRead` is true once the last accounts read gave a
// list, so an empty list means no saved account only then, and
// `outdated` that the command is below the manifest's floor. The network
// devices and the exit nodes are values of their own (statusWrites).
function published(missing, snap, setupLine, live) {
    var shown = connection(missing, snap);
    return { state: shown.state, tone: shown.tone, text: shown.text, writable: !missing && setupLine !== null && setupLine.tone === "ok",
        checkingSetup: setupLine === null, outdated: live.outdated === true,
        backendPresent: live.backendPresent !== false, device: snap.device, tailnet: snap.tailnet, account: snap.account, exit: snap.exit,
        suggestion: live.suggestion === undefined ? null : live.suggestion, accounts: live.accounts, accountsRead: live.accountsRead === true,
        action: live.action, login: live.login, problem: live.problem };
}

// What a view draws before the service's first write.
function unread() {
    return published(false, emptySnapshot("checking"), { action: "" }, { accounts: [], accountsRead: false, action: "", login: "idle", problem: "", suggestion: null });
}

// Why the controls `tailscale.writable` enables cannot change Tailscale now, as
// the one sentence each shows while disabled (its `disabledReason`), ""
// while they can. TAILSCALE is the published `tailscale` value, and STEP the words of
// the setup step the core offers now, "" for none. A value that is not
// writable has one cause (published, setup): the command is missing, the
// service is off, or the administrator holds Tailscale.
function lockReason(tailscale, step) {
    if (tailscale.action !== "") return BUSY_TEXT;
    if (tailscale.checkingSetup) return CHECKING_TEXT;
    if (tailscale.writable) return "";
    if (tailscale.state === "missing") return "Tailscale is not installed, so choose Review all missing or outdated tools under [Optional tools in Tailscale Setup](page:vgs.tailscale/Setup) to use it.";
    var cause = tailscale.state === "service-off" ? "The Tailscale service is off" : "The administrator holds Tailscale";
    return step === "" ? cause + "; review [Tailscale service in Tailscale Setup](page:vgs.tailscale/Setup)." : cause + " until you choose " + step + " beside [Tailscale service in Tailscale Setup](page:vgs.tailscale/Setup).";
}

// Why the account control for KIND, one of FLOOR_KINDS, cannot act now,
// "" while it can. Both need the floor. Sign-in also needs what every
// change needs (lockReason); the add transaction runs while operator
// access is unset, since it sets that access itself, so only a change in
// progress or a pending fresh reading holds it.
function accountReason(tailscale, step, kind) {
    if (FLOOR_KINDS.indexOf(kind) === -1) throw new Error("tailscale: account control " + JSON.stringify(kind) + " is not one of " + FLOOR_KINDS.join(", "));
    if (tailscale.action !== "") return BUSY_TEXT;
    if (tailscale.outdated) return "This Tailscale is too old to add accounts or sign in, so choose Review all missing or outdated tools under [Optional tools in Tailscale Setup](page:vgs.tailscale/Setup) to update it.";
    if (kind === "sign-in") return lockReason(tailscale, step);
    return tailscale.checkingSetup ? CHECKING_TEXT : "";
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

// The sentence a state shows, { text, control }: `text` "" for a state
// with none, and `control` the one the sentence tells the user to choose,
// `sign-in` (a saved account's Sign in, or the first Sign in while the
// list is empty), `add-account`, `setup` (the setup step the core offers)
// or "" for none. TAILSCALE is the published value and STEP the words of
// the setup step offered now, "" for none. Signed out over an unread
// list, the view draws no Sign in (it would hide saved accounts): in
// lockReason's order, a change in progress or a pending fresh reading
// gives the reason the card's controls show and names no control; else
// the sentence names the setup step while one is offered, since the
// service reads the list again once the step changes its access
// (Service.rereadAccounts), else Add account.
function hintState(text, control) { return { text: text, control: control }; }
function stateHint(tailscale, step) {
    switch (tailscale.state) {
    case "signed-out":
        if (tailscale.accountsRead) return hintState("Sign in to connect this computer to your tailnet.", "sign-in");
        if (tailscale.action !== "") return hintState(BUSY_TEXT, "");
        if (tailscale.checkingSetup) return hintState(CHECKING_TEXT, "");
        if (step !== "") return hintState("VGS could not read your saved accounts, so choose " + step + " below and VGS reads them again.", "setup");
        return hintState("VGS could not read your saved accounts, so choose Add account to sign in.", "add-account");
    case "needs-approval": return hintState("An admin of " + (tailscale.tailnet !== "" ? tailscale.tailnet : "your tailnet") + " must approve this device.", "");
    case "unavailable": return hintState("Tailscale did not answer.", "");
    }
    return hintState("", "");
}

// The sign-out confirmation for TAILNET: { title, message }.
function signOutPrompt(tailnet) {
    var name = tailnet !== "" ? tailnet : "your tailnet";
    return { title: "Sign out of " + name + "?",
        message: "This computer leaves " + name + " until you sign in again. An admin of " + name + " may need to approve this computer again." };
}

function badge(active) { return active ? IN_USE : ""; }

// The rows the views draw, each a DeviceList row: { key, text, secondary,
// iconName, badge, badgeTone } and, for an exit node, `id`, the node the
// row chooses, "" for None, which the view sends and never a target.
// The account rows of TAILSCALE, the published value: its saved accounts
// while the list was read, else the account `status --json` names, as
// the one current row, or none. The view sends no request for that row:
// a request names a listed account.
function accountRows(tailscale) {
    var signedOut = tailscale.state === "signed-out";
    if (!tailscale.accountsRead)
        return tailscale.account === "" ? [] : [{ key: "current", text: tailscale.account, secondary: tailscale.tailnet, iconName: "user", badge: badge(!signedOut), badgeTone: "success" }];
    return tailscale.accounts.map(function (row) {
        return { key: row.id, text: row.account, secondary: row.tailnet, iconName: "user", badge: badge(row.current && !signedOut), badgeTone: "success" };
    });
}

// The network devices' DeviceList rows: each device's name, its address
// and whether it is offline, its icon, and the address, DNS name and
// `connects` its icon actions read.
function deviceRows(value) {
    return value.rows.map(function (row) {
        return { key: row.id, text: row.name, secondary: row.online ? row.address : [row.address, "Offline"].filter(function (part) { return part !== ""; }).join(" · "),
            iconName: row.icon, address: row.address, dnsName: row.dnsName, connects: row.connects === true };
    });
}

// "3 of 5 online", over every device, kept or not.
function devicesLine(value) {
    return value.online + " of " + value.count + " online";
}

// The Exit node row's secondary line.
function exitLine(tailscale) {
    return tailscale.exit === null ? "None" : tailscale.exit.name;
}

// Recommended, while a suggestion is read, then None.
function exitTopRows(tailscale) {
    var rows = [];
    var inUse = tailscale.exit === null ? "" : tailscale.exit.id;
    if (tailscale.suggestion !== null)
        rows.push({ key: "recommended", id: tailscale.suggestion.id, text: tailscale.suggestion.name, secondary: "Recommended", iconName: "sparkles",
            badge: badge(tailscale.suggestion.id === inUse), badgeTone: "success" });
    rows.push({ key: "none", id: "", text: "None", secondary: "Use this computer's own connection", iconName: "globe-off",
        badge: badge(tailscale.exit === null), badgeTone: "success" });
    return rows;
}

function ownRow(node) {
    return { key: node.id, id: node.id, text: node.name, secondary: node.online ? "Online" : "Offline", iconName: node.icon,
        badge: badge(node.active), badgeTone: "success" };
}

function ownRows(value) {
    return value.own.map(ownRow);
}

// A Mullvad country as a row: one city shows that city and chooses it;
// more show their count and `opens` the country view.
function countryRows(value) {
    return value.countries.map(function (country) {
        var one = country.cities.length === 1;
        return { key: country.code, code: country.code, id: one ? country.cities[0].id : "", text: country.name,
            secondary: one ? country.cities[0].name : country.cities.length + " cities", iconName: "map-pin", opens: !one,
            badge: badge(country.cities.some(function (city) { return city.active; })), badgeTone: "success" };
    });
}

// The country view's rows: Best available, the best city now, then each city.
function cityRows(country) {
    return [{ key: "best", id: country.best.id, text: "Best available", secondary: country.best.city + " now", iconName: "sparkles" }]
        .concat(country.cities.map(function (city) {
            return { key: "city:" + city.code, id: city.id, text: city.name, iconName: "map-pin", badge: badge(city.active), badgeTone: "success" };
        }));
}

// The rows matching QUERY, case-blind on a node's name, a city or a
// country: your own nodes, then each matching city flat as "City,
// Country". An empty query matches nothing.
function searchRows(value, query) {
    var wanted = String(query).trim().toLowerCase();
    if (wanted === "") return [];
    var holds = function (text) { return text.toLowerCase().indexOf(wanted) !== -1; };
    var rows = value.own.filter(function (node) { return holds(node.name); }).map(ownRow);
    value.countries.forEach(function (country) {
        country.cities.forEach(function (city) {
            if (holds(city.name) || holds(country.name))
                rows.push({ key: country.code + "/" + city.code, id: city.id, text: city.name + ", " + country.name, iconName: "map-pin",
                    badge: badge(city.active), badgeTone: "success" });
        });
    });
    return rows;
}

// Each data value's share of the core's per-plugin ceiling, in UTF-8 bytes
// of its JSON, which together leave room for both state lines and every
// mix of old and new values during the sequential writes. A list longer
// than its budget loses rows from its end, never the one in use, and keeps
// its counts.
var TAILSCALE_BYTES = 8000;
var DEVICES_BYTES = 24000;
var EXIT_NODES_BYTES = 28000;

function bytes(value) { return Commons.SettingValues.utf8Bytes(JSON.stringify(value)); }

// Drops the last row of LIST that is not in use; answers whether one went.
function dropLast(list) {
    for (var i = list.length - 1; i >= 0; i--)
        if (list[i].active !== true) {
            list.splice(i, 1);
            return true;
        }
    return false;
}

function boundedExitNodes(value) {
    var out = { own: value.own.slice(), countries: value.countries.map(function (country) { return Object.assign({}, country, { cities: country.cities.slice() }); }),
        cityCount: value.cityCount };
    while (bytes(out) > EXIT_NODES_BYTES) {
        var dropped = false;
        for (var c = out.countries.length - 1; c >= 0 && !dropped; c--) {
            dropped = dropLast(out.countries[c].cities);
            if (out.countries[c].cities.length === 0) out.countries.splice(c, 1);
        }
        if (!dropped && !dropLast(out.own)) break;
    }
    return out;
}

// The status writes, in order: `connection`, `setup`, `tailscale`,
// `devices` and `exitNodes`, each data value within its budget.
function statusWrites(connectionLine, setupLine, tailscaleValue, devicesValue, exitNodesValue) {
    var setupValue = null;
    if (setupLine !== null) {
        setupValue = { tone: setupLine.tone, text: setupLine.text };
        if (setupLine.hint !== "") setupValue.hint = setupLine.hint;
        if (setupLine.action !== "") setupValue.action = setupLine.action;
        // A required Setup step the user cannot act on here reads Not
        // available, its hint saying why (PluginLogic.statusDeclarationFits).
        else if (setupLine.tone !== "ok") setupValue.available = false;
    }
    var tailscale = Object.assign({}, tailscaleValue, { accounts: tailscaleValue.accounts.slice() });
    while (bytes(tailscale) > TAILSCALE_BYTES && tailscale.accounts.length > 0) tailscale.accounts.pop();
    var devicesOut = { rows: devicesValue.rows.slice(), count: devicesValue.count, online: devicesValue.online };
    while (bytes(devicesOut) > DEVICES_BYTES && devicesOut.rows.length > 0) devicesOut.rows.pop();
    return [["connection", { tone: connectionLine.tone, text: connectionLine.text }], ["setup", setupValue], ["tailscale", tailscale],
        ["devices", devicesOut], ["exitNodes", boundedExitNodes(exitNodesValue)]];
}
