.pragma library
.import qs.Commons 1.0 as Commons
// NetworkManager profile decisions. Service.qml owns the effects.
// nmcli's documented terse output: https://networkmanager.dev/docs/api/latest/nmcli.html
// The shapes parsed here are the readings of NetworkManager 1.58.1 that
// scripts/fixtures/vpn/ holds (VGS-1931 verify-first, 2026-10-20).
var WATCHDOG_MS = 10000;
var OPEN_POLL_MS = 3000;
var ACTION_MS = 30000;
var TEXT_MAX = 64;
// A host name is at most 253 octets; an endpoint adds brackets and a port.
var SERVER_MAX = 261;
var PROFILE_MAX = 32;
var OPENVPN_PLUGIN = "org.freedesktop.NetworkManager.openvpn";
var SERVICE_PREFIX = "org.freedesktop.NetworkManager.";
var UUID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

function pollInterval(open, idleSeconds) {
    return open ? OPEN_POLL_MS : idleSeconds * 1000;
}

function clip(value, max) {
    var text = typeof value === "string" ? value.replace(/[\u0000-\u001f\u007f<]/g, "") : "";
    return text.length > max ? text.slice(0, max) : text;
}
function line(value) { return clip(value, TEXT_MAX); }

function isPlain(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

// The list read's outcome: `reading` before the first answer, `available`,
// `not-running` (nmcli exit 8), `no-answer` for any other failure, and
// `missing` while nmcli is not installed.
function emptyProfiles(state) { return { state: state, rows: [], count: 0, activeCount: 0 }; }

// `nmcli -t -f NAME,UUID,TYPE,STATE connection show`, a terse table whose
// fields escape `:` and `\` (Commons.Nmcli.fields).
// https://networkmanager.dev/docs/api/latest/nmcli.html#exit_status
var STATES = ["activated", "activating", "deactivating", ""];
function list(code, text) {
    if (code === 8) return emptyProfiles("not-running");
    if (code !== 0) return emptyProfiles("no-answer");
    const rows = [];
    for (const raw of String(text).split(/\r?\n/)) {
        if (raw === "") continue;
        const fields = Commons.Nmcli.fields(raw);
        if (fields === null || fields.length !== 4) return emptyProfiles("no-answer");
        if (fields[2] !== "vpn" && fields[2] !== "wireguard") continue;
        if (!UUID.test(fields[1]) || STATES.indexOf(fields[3]) === -1) return emptyProfiles("no-answer");
        rows.push({ uuid: fields[1].toLowerCase(), name: line(fields[0]), type: fields[2], state: fields[3] });
    }
    const activeCount = rows.filter(row => row.state === "activated").length;
    return { state: "available", rows: rows.slice(0, PROFILE_MAX), count: rows.length, activeCount: activeCount };
}

// The uuids one detail read covers, in a stable order, so an unchanged
// set reads nothing again.
function detailsKey(listing) {
    return listing.rows.map(row => row.uuid).sort().join(" ");
}
function detailsArgv(key) {
    const argv = ["nmcli", "-t", "-f", "connection.uuid,vpn.service-type,vpn.data,wireguard.peers", "connection", "show"];
    for (const uuid of key.split(" ")) argv.push("uuid", uuid);
    return argv;
}

// `vpn.data` is `key = value` pairs joined by `, `; a value's own comma is
// `\,`. Only SERVER_KEYS[service] is read: every other key, such as a
// certificate path, is skipped unread and never leaves this function.
var SERVER_KEYS = { openvpn: "remote", l2tp: "gateway", pptp: "gateway", sstp: "gateway", fortisslvpn: "gateway",
    openconnect: "gateway", vpnc: "IPSec gateway", strongswan: "address", libreswan: "right" };
function serverOf(service, data) {
    const wanted = SERVER_KEYS[service];
    if (wanted === undefined) return "";
    let pair = "";
    const pairs = [];
    for (let i = 0; i < data.length; i++) {
        const c = data[i];
        if (c === "\\" && i + 1 < data.length) { pair += c + data[i + 1]; i++; }
        else if (c === "," && data[i + 1] === " ") { pairs.push(pair); pair = ""; i++; }
        else pair += c;
    }
    pairs.push(pair);
    for (const entry of pairs) {
        const split = entry.indexOf(" = ");
        if (split === -1 || entry.slice(0, split) !== wanted) continue;
        let value = entry.slice(split + 3);
        // OpenVPN lists its remotes in one value; the first is the server.
        if (service === "openvpn") value = value.split(/\\,|,/)[0].trim();
        return clip(value.replace(/\\(.)/g, "$1"), SERVER_MAX);
    }
    return "";
}

// `wireguard.peers`: peers joined by `, `, each a public key then
// `name=value` attributes. The first peer's endpoint is the server; the
// keys and allowed addresses are skipped.
function endpointOf(peers) {
    const first = peers.split(", ")[0];
    const found = /(?:^|\s)endpoint=(\S+)/.exec(first);
    return found === null ? "" : clip(found[1], SERVER_MAX);
}

// The detail read: one block per profile, each starting at its
// `connection.uuid:` line; the value is everything after the line's first
// colon, unescaped. Answers { uuid: { service, server } } for the uuids
// asked for, or null when the read failed.
function details(code, text, key) {
    if (code !== 0) return null;
    const asked = key.split(" ");
    const out = {};
    let uuid = "";
    let service = "";
    let data = "";
    let peers = "";
    function close() {
        if (uuid === "" || asked.indexOf(uuid) === -1) return;
        out[uuid] = { service: service, server: peers !== "" ? endpointOf(peers) : serverOf(service, data) };
    }
    for (const raw of String(text).split(/\r?\n/)) {
        const split = raw.indexOf(":");
        if (split === -1) continue;
        const name = raw.slice(0, split);
        const value = raw.slice(split + 1);
        if (name === "connection.uuid") {
            close();
            uuid = value.toLowerCase();
            service = "";
            data = "";
            peers = "";
        } else if (name === "vpn.service-type") {
            service = value.indexOf(SERVICE_PREFIX) === 0 ? value.slice(SERVICE_PREFIX.length) : "";
            if (!/^[A-Za-z0-9_-]{1,32}$/.test(service)) service = "";
        } else if (name === "vpn.data") data = value;
        else if (name === "wireguard.peers") peers = value;
    }
    close();
    return out;
}

function addressArgv(uuid) {
    return ["nmcli", "-t", "-f", "GENERAL.STATE,IP4.ADDRESS", "connection", "show", "uuid", uuid];
}
// The first IPv4 address without its prefix while the profile is
// activated, "" while it has none yet, null when the read failed.
function address(code, text) {
    if (code !== 0) return null;
    const output = String(text);
    if (!/^GENERAL\.STATE:activated$/m.test(output)) return "";
    const found = /^IP4\.ADDRESS\[\d+\]:(\d{1,3}(?:\.\d{1,3}){3})\/\d{1,2}$/m.exec(output);
    return found === null ? "" : found[1];
}

// The one pattern table for nmcli's failure texts under LC_ALL=C. A text
// is classified here and dropped: it can repeat a path or a secret's name.
var SERVICE_MISSING = /The VPN service 'org\.freedesktop\.NetworkManager\.([A-Za-z0-9_-]{1,32})' was not installed\./;
var SECRET_MISSING = /^Warning: password for '([^'\n]{1,128})' not given in 'passwd-file'/gm;
var SECRETS_REQUIRED = /Secrets were required, but not provided|No valid secrets/;
var UNKNOWN_CONNECTION = /^Error: cannot delete unknown connection/m;
// The services whose connect asks for one password, vpn.secrets.password.
var PASSWORD_SERVICES = ["openvpn", "l2tp", "pptp", "sstp", "fortisslvpn"];

// The kind a failed `up` of ROW leaves on it: `needs-password`, `sign-in`
// (a secret VGS cannot ask for), `plugin-needed` with the service, or
// `failed`. -1 is a run the deadline ended.
function upFailure(code, text, row) {
    const output = code === -1 ? "" : String(text);
    const plugin = SERVICE_MISSING.exec(output);
    if (plugin !== null) return { kind: "plugin-needed", service: plugin[1] };
    const missing = [];
    SECRET_MISSING.lastIndex = 0;
    for (let found = SECRET_MISSING.exec(output); found !== null; found = SECRET_MISSING.exec(output)) missing.push(found[1]);
    if (missing.length === 0 && !SECRETS_REQUIRED.test(output)) return { kind: "failed", service: "" };
    const single = row.type === "vpn" && PASSWORD_SERVICES.indexOf(row.service) !== -1
        && missing.length === 1 && missing[0] === "vpn.secrets.password";
    return { kind: single ? "needs-password" : "sign-in", service: "" };
}

// A delete's outcome: `removed`, `gone` when NetworkManager no longer
// holds the profile, else `failed`.
function removeOutcome(code, text) {
    if (code === 0) return "removed";
    return code !== -1 && UNKNOWN_CONNECTION.test(String(text)) ? "gone" : "failed";
}

var TYPE_NAMES = { openvpn: "OpenVPN", l2tp: "L2TP", pptp: "PPTP", sstp: "SSTP", fortisslvpn: "Fortinet SSL",
    openconnect: "OpenConnect", strongswan: "IPsec (strongSwan)", libreswan: "IPsec (Libreswan)", vpnc: "Cisco IPsec (vpnc)" };
function typeName(type, service) {
    if (type === "wireguard") return "WireGuard";
    return Object.prototype.hasOwnProperty.call(TYPE_NAMES, service) ? TYPE_NAMES[service] : "VPN";
}

// The payload the service publishes: the list's rows with their read
// details, the address while activated, the failure the last `up` left,
// the change in flight and its problem line.
function compose(listing, detailMap, addresses, failures, openvpnMissing, action, problem) {
    const rows = listing.rows.map(row => {
        const detail = detailMap[row.uuid];
        const failure = failures[row.uuid];
        let service = detail === undefined ? "" : detail.service;
        if (service === "" && failure !== undefined) service = failure.service;
        return {
            uuid: row.uuid, name: row.name, type: row.type, state: row.state, service: service,
            server: detail === undefined ? "" : detail.server,
            address: row.state === "activated" && typeof addresses[row.uuid] === "string" ? addresses[row.uuid] : "",
            failure: failure === undefined ? "" : failure.kind
        };
    });
    return { state: listing.state, rows: rows, count: listing.count, activeCount: listing.activeCount,
        openvpnMissing: openvpnMissing, action: action, problem: problem };
}

var SIGN_IN_REASON = "This VPN asks for sign-in details when it connects, and VGS cannot ask for them. Save them in the profile, or connect it from your VPN provider's app.";
var BUSY_REASON = "Wait until NetworkManager finishes this change.";
var UNSUPPORTED_REASON = "VGS cannot show this VPN's sign-in. Connect it from your VPN provider's app.";

// The change in flight on ROW: `connecting`, `disconnecting`, `removing`
// or "".
function motion(row, action) {
    if (isPlain(action) && action.uuid === row.uuid)
        return action.kind === "profile-up" ? "connecting" : action.kind === "profile-down" ? "disconnecting" : "removing";
    return row.state === "activating" ? "connecting" : row.state === "deactivating" ? "disconnecting" : "";
}

// What a profile row shows: its state `key`, the secondary line and its
// tone, the switch's value and the reason it is disabled, whether a
// spinner stands in for the switch, and whether the Type row offers the
// OpenVPN plugin.
function rowView(row, profiles) {
    const type = typeName(row.type, row.service);
    function view(key, words, extra) {
        return Object.assign({ key: key, type: type, secondary: type + " · " + words, danger: false, busy: false,
            connected: false, switchOn: false, reason: "", installPlugin: false }, extra || {});
    }
    const moving = motion(row, profiles.action);
    // The switch shows where the change goes and waits for it.
    if (moving === "connecting") return view(moving, "Connecting…", { busy: true, switchOn: true, reason: BUSY_REASON });
    if (moving === "disconnecting") return view(moving, "Disconnecting…", { busy: true, connected: true, reason: BUSY_REASON });
    if (moving === "removing")
        return view(moving, "Removing…", { busy: true, connected: row.state === "activated", switchOn: row.state === "activated", reason: BUSY_REASON });
    if (row.state === "activated") return view("connected", "Connected", { connected: true, switchOn: true });
    if (row.type === "vpn" && row.service === "openconnect")
        return view("unsupported", "Connects in its own app", { reason: UNSUPPORTED_REASON });
    if (row.type === "vpn" && row.service === "openvpn" && profiles.openvpnMissing === true)
        return view("plugin-needed", "Needs the OpenVPN plugin", {
            reason: "NetworkManager needs its OpenVPN plugin to connect this profile.", installPlugin: true });
    if (row.failure === "plugin-needed")
        return view("plugin-needed", "Needs the " + type + " plugin", { reason: "NetworkManager needs its " + type + " plugin to connect this profile." });
    if (row.failure === "sign-in") return view("sign-in", "Asks for sign-in details VGS cannot ask", { reason: SIGN_IN_REASON });
    if (row.failure === "needs-password") return view("needs-password", "Needs password");
    if (row.failure === "failed") return view("failed", "Could not connect", { danger: true });
    return view("off", "Off");
}

var KINDS = ["profile-up", "profile-down", "profile-remove", "profile-details"];
// The plan for one IPC request: { argv } for a change, { address: uuid }
// for an opened row's address read, or { refusal }.
function profileCommand(request, profiles) {
    if (!isPlain(request) || KINDS.indexOf(request.kind) === -1) return { refusal: "refused: profile=action" };
    if (profiles.state !== "available") return { refusal: "refused: profile=unavailable" };
    const row = profiles.rows.find(candidate => candidate.uuid === request.id);
    if (row === undefined) return { refusal: "refused: profile=absent" };
    if (request.kind === "profile-details") return { address: row.uuid };
    if (request.kind === "profile-remove") return { argv: ["nmcli", "connection", "delete", "uuid", row.uuid] };
    if (request.kind === "profile-down") {
        if (row.state !== "activated" && row.state !== "activating") return { refusal: "refused: profile=state" };
        return { argv: ["nmcli", "connection", "down", "uuid", row.uuid] };
    }
    const view = rowView(row, profiles);
    if (view.connected || row.state === "activating") return { refusal: "refused: profile=state" };
    if (view.reason !== "") return { refusal: "refused: profile=" + view.key };
    return { argv: ["nmcli", "connection", "up", "uuid", row.uuid] };
}

// The problem line a failed change leaves, in a sentence.
function problem(kind, name, code) {
    if (code === -1) return "NetworkManager did not answer.";
    const verb = kind === "profile-up" ? "connect" : kind === "profile-down" ? "disconnect" : "remove";
    return "NetworkManager could not " + verb + " " + name + ".";
}

// The one line the status entry, the flyout header and the bar share.
function summary(profiles) {
    if (profiles.state === "missing") return "NetworkManager is not installed";
    if (profiles.state === "not-running") return "NetworkManager is not running";
    if (profiles.state === "no-answer") return "NetworkManager did not answer";
    if (profiles.state === "reading") return "Reading your VPN profiles";
    if (profiles.activeCount > 1) return profiles.activeCount + " profiles connected";
    if (profiles.activeCount === 1) {
        const active = profiles.rows.find(row => row.state === "activated");
        return active === undefined ? "1 profile connected" : "Connected to " + active.name;
    }
    return "Off";
}

function connection(profiles) {
    return { tone: profiles.state === "available" && profiles.activeCount > 0 ? "ok" : "info", text: summary(profiles) };
}

// The bar icon: hidden with no profile or no NetworkManager; a spinner
// while a profile connects or disconnects; the warning shield while a
// profile needs its password or could not connect; else connected or off.
function barView(profiles) {
    const hidden = { shown: false, icon: "shield-off", tooltip: "VPN", spinning: false, warning: false };
    if (!isPlain(profiles) || profiles.state !== "available" || profiles.count === 0) return hidden;
    const rows = Array.isArray(profiles.rows) ? profiles.rows : [];
    for (const row of rows) {
        const moving = motion(row, profiles.action);
        if (moving === "connecting" || moving === "disconnecting")
            return { shown: true, icon: "shield", spinning: true, warning: false,
                tooltip: "VPN: " + (moving === "connecting" ? "Connecting to " : "Disconnecting from ") + row.name };
    }
    const alert = rows.find(row => row.state !== "activated" && (row.failure === "needs-password" || row.failure === "failed"));
    if (alert !== undefined)
        return { shown: true, icon: "shield-alert", spinning: false, warning: true,
            tooltip: alert.failure === "needs-password" ? "VPN: " + alert.name + " needs a password" : "VPN: Could not connect " + alert.name };
    return { shown: true, icon: profiles.activeCount > 0 ? "shield-check" : "shield-off", spinning: false, warning: false,
        tooltip: "VPN: " + summary(profiles) };
}

// Leave room for the state line while keeping the source list unchanged.
var STATUS_DATA_BYTES = 32000;
function statusWrites(connectionLine, profileValue) {
    var profiles = Object.assign({}, profileValue, { rows: profileValue.rows.slice() });
    while (Commons.SettingValues.utf8Bytes(JSON.stringify(profiles)) > STATUS_DATA_BYTES) profiles.rows.pop();
    return [["connection", connectionLine], ["profiles", profiles]];
}
