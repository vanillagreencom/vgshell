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
var SERVICE_PREFIX = "org.freedesktop.NetworkManager.";
var UUID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

// Qt shares .pragma library state across this plugin's QML instances:
// https://doc.qt.io/qt-6/qtqml-javascript-resources.html
// The service attaches itself as the password connect's owner and
// releases it on destruction. Only this direct call carries the password,
// inside the one-use stdin closure; IPC, status and logs hold the uuid alone.
var connectOwner = null;
function attachConnect(owner) { connectOwner = owner; }
function releaseConnect(owner) { if (connectOwner === owner) connectOwner = null; }
// Connect UUID with PASSWORD: the owner's reply, `unavailable` with no
// service, or `refused: password=value` for a password nmcli cannot read.
function submitConnect(uuid, password) {
    const text = passwordLine(password);
    if (text === null) return "refused: password=value";
    if (connectOwner === null) return "unavailable";
    return connectOwner.connectWithPassword(uuid, process => {
        process.write(text);
        process.stdinEnabled = false;
    });
}

// The one passwd-file line nmcli reads on stdin, or null for an empty
// password or one that holds a NUL, where nmcli's reader would silently
// cut the password. nmcli 1.58.1 stops reading at a NUL, ends a line at
// LF or CR, ends the key at its first `:` or `=`, and unescapes the value
// with nm_utils_buf_utf8safe_unescape(STRIP_SPACES):
// a backslash starts an escape, and unescaped leading and trailing ASCII
// whitespace is stripped (src/libnmc-base/nm-client-utils.c,
// nmc_utils_parse_passwd_file; VGS-1932 verify-first § 2). So every
// backslash, CR and LF is escaped, and so is each space, tab, VT and FF at
// either end; whitespace inside the value, `:` and `=` pass as they are.
var PASSWORD_ENTRY = "vpn.secrets.password";
var EDGE_ESCAPES = { " ": "\\040", "\t": "\\t", "\v": "\\v", "\f": "\\f" };
function passwordLine(password) {
    if (typeof password !== "string" || password === "" || password.indexOf("\u0000") !== -1) return null;
    const value = password.replace(/\\/g, "\\\\").replace(/\r/g, "\\r").replace(/\n/g, "\\n");
    const parts = /^([ \t\v\f]*)([\s\S]*?)([ \t\v\f]*)$/.exec(value);
    const edge = run => run.replace(/[ \t\v\f]/g, c => EDGE_ESCAPES[c]);
    return PASSWORD_ENTRY + ":" + edge(parts[1]) + parts[2] + edge(parts[3]) + "\n";
}

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
// asked for, or null when the read failed or omitted a requested profile.
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
    return asked.every(uuid => out[uuid] !== undefined) ? out : null;
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
// `failed`. -1 is a run the deadline ended. A connect that CARRIED the
// password leaves `password-tried` unless nmcli named a missing plugin or
// another secret: no listed type tells a refused password apart from
// another failure through nmcli (openvpn retries it until the deadline,
// the pppd types and Fortinet read Unknown reason; VGS-1932 verify-first
// § 6), so the row asks for the password again and claims nothing more.
function upFailure(code, text, row, carried) {
    const output = code === -1 ? "" : String(text);
    const plugin = SERVICE_MISSING.exec(output);
    if (plugin !== null) return { kind: "plugin-needed", service: plugin[1] };
    const missing = [];
    SECRET_MISSING.lastIndex = 0;
    for (let found = SECRET_MISSING.exec(output); found !== null; found = SECRET_MISSING.exec(output)) missing.push(found[1]);
    if (carried === true)
        return { kind: missing.some(name => name !== PASSWORD_ENTRY) ? "sign-in" : "password-tried", service: "" };
    if (missing.length === 0 && !SECRETS_REQUIRED.test(output)) return { kind: "failed", service: "" };
    const single = row.type === "vpn" && PASSWORD_SERVICES.indexOf(row.service) !== -1
        && missing.length === 1 && missing[0] === PASSWORD_ENTRY;
    return { kind: single ? "needs-password" : "sign-in", service: "" };
}

// An editor handoff invalidates every learned failure for its UUID: the
// editor may replace its credentials, type or plugin. Other profiles
// keep their failures. An empty UUID reads metadata without invalidation;
// only an omitted UUID is the internal requirements rescan after install.
function afterRescan(failures, editedUuid) {
    const kept = {};
    for (const uuid of Object.keys(failures)) {
        const keep = editedUuid === undefined
            ? failures[uuid].kind !== "sign-in" && failures[uuid].kind !== "plugin-needed"
            : uuid !== editedUuid;
        if (keep) kept[uuid] = failures[uuid];
    }
    return kept;
}

// The problem line { uuid, kind, text } a list or a rescan leaves, null
// when it no longer describes a listed profile: it belongs to the profile
// its action ran on and goes when that profile leaves ROWS. A connect's
// line goes with the failure the connect left, and a disconnect's line
// once the profile is no longer up.
function problemAfter(problem, rows, failures) {
    if (problem === null) return null;
    const row = rows.find(candidate => candidate.uuid === problem.uuid);
    if (row === undefined) return null;
    if (problem.kind === "profile-up" && failures[problem.uuid] === undefined) return null;
    if (problem.kind === "profile-down" && row.state === "") return null;
    return problem;
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
function compose(listing, detailMap, addresses, failures, action, problem) {
    const rows = listing.rows.map(row => {
        const detail = detailMap[row.uuid];
        const failure = failures[row.uuid];
        const detailState = detail === undefined ? "reading" : detail === null ? "no-answer" : "available";
        let service = detailState === "available" ? detail.service : "";
        if (service === "" && failure !== undefined) service = failure.service;
        return {
            uuid: row.uuid, name: row.name, type: row.type, state: row.state, service: service,
            details: detailState, server: detailState === "available" ? detail.server : "",
            address: row.state === "activated" && typeof addresses[row.uuid] === "string" ? addresses[row.uuid] : "",
            failure: failure === undefined ? "" : failure.kind
        };
    });
    return { state: listing.state, rows: rows, count: listing.count, activeCount: listing.activeCount, action: action, problem: problem };
}

var SIGN_IN_REASON = "This VPN asks for sign-in details when it connects, and VGS cannot ask for them. Save them with Edit in connection editor, or connect it from your VPN provider's app.";
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
// tone, the switch's value and the reason it is disabled, and whether a
// spinner stands in for the switch. A profile reads Needs password both
// before its first password and after a connect with one failed
// (`password-tried`); its switch opens the prompt (VpnBody). A missing
// OpenVPN plugin reads from the core requirement scan, which can find an
// installed plugin before its first connect. Other plugins still read
// from the `up` that failed for them, since the manifest declares none.
var OPENVPN_SERVICE = "org.freedesktop.NetworkManager.openvpn";
// The way out a sentence names, to the kill switch's own switch. Its label,
// Block traffic if the VPN drops, carries an "if" clause of its own that
// runs into the sentence around it, so a sentence names the kill switch.
var KILL_OFF = "turn off the kill switch";
function sentence(words) {
    return words.charAt(0).toUpperCase() + words.slice(1);
}
// KILL_ON holds while the kill switch is set up and on (killSwitchOn): it
// arms no tunnel for a profile that is not WireGuard, so that profile's
// switch says so before a press. HELD is the profile the blocked-traffic
// notice names (blockedNotice), which reads Dropped with its switch on:
// VGS still means it on, and turning the switch off ends the block. Its
// `reconnect` offers a connect that keeps the block in place: the file
// already names it, so the arm wait passes on its holding line and nmcli
// runs (profileCommand, meantOnPlan).
var KILL_WIREGUARD_ONLY = "The kill switch works only with WireGuard. " + sentence(KILL_OFF) + " to connect this profile.";
function rowView(row, profiles, missing, killOn, held) {
    const type = typeName(row.type, row.service);
    function view(key, words, extra) {
        return Object.assign({ key: key, type: type, secondary: type + " · " + words, danger: false, busy: false,
            connected: false, switchOn: false, reason: "", install: "", reconnect: false }, extra || {});
    }
    const moving = motion(row, profiles.action);
    // The switch shows where the change goes and waits for it.
    if (moving === "connecting") return view(moving, "Connecting…", { busy: true, switchOn: true, reason: BUSY_REASON });
    if (moving === "disconnecting") return view(moving, "Disconnecting…", { busy: true, connected: true, reason: BUSY_REASON });
    if (moving === "removing")
        return view(moving, "Removing…", { busy: true, connected: row.state === "activated", switchOn: row.state === "activated", reason: BUSY_REASON });
    if (row.state === "activated") return view("connected", "Connected", { connected: true, switchOn: true });
    if (held === row.uuid) return view("dropped", "Dropped", { switchOn: true, reconnect: true });
    // The list arrives before its separate detail read. An empty service
    // from a completed read is distinct from a service not yet identified.
    if (row.type === "vpn" && row.details === "reading")
        return view("reading", "Reading…", { reason: "Wait until NetworkManager reads this VPN profile." });
    if (row.type === "vpn" && row.details === "no-answer")
        return view("no-answer", "NetworkManager did not answer", { reason: "NetworkManager did not answer, so wait until it reads this VPN profile." });
    if (row.type === "vpn" && row.service === "openconnect")
        return view("unsupported", "Connects in its own app", { reason: UNSUPPORTED_REASON });
    if (killOn === true && row.type !== "wireguard") return view("kill-switch", "Needs the kill switch off", { reason: KILL_WIREGUARD_ONLY });
    const declaredPlugin = row.type === "vpn" && row.service === "openvpn";
    if ((declaredPlugin && (missing || []).indexOf(OPENVPN_SERVICE) !== -1) || (!declaredPlugin && row.failure === "plugin-needed"))
        return view("plugin-needed", "Needs the " + type + " plugin", {
            reason: "NetworkManager needs its " + type + " plugin to connect this profile.", install: declaredPlugin ? OPENVPN_SERVICE : "" });
    if (row.failure === "sign-in") return view("sign-in", "Asks for sign-in details VGS cannot ask", { reason: SIGN_IN_REASON });
    if (row.failure === "needs-password" || row.failure === "password-tried") return view("needs-password", "Needs password");
    if (row.failure === "failed") return view("failed", "Could not connect", { danger: true });
    return view("off", "Off");
}

var KINDS = ["profile-up", "profile-down", "profile-remove", "profile-details", "profile-check"];
// The editor owns every profile change. Its edit target must still be a
// published row; no typed text becomes an editor argument.
function editorArgv(kind, uuid, profiles) {
    if (kind === "create") return { argv: ["nm-connection-editor", "--create", "--type=vpn"] };
    if (kind !== "edit") return { refusal: "refused: editor=kind" };
    if (profiles.state !== "available") return { refusal: "refused: profile=unavailable" };
    const row = profiles.rows.find(candidate => candidate.uuid === uuid);
    if (row === undefined) return { refusal: "refused: profile=absent" };
    return { argv: ["nm-connection-editor", "--edit=" + row.uuid] };
}

// The plan for one IPC request: { argv } for a change, { address: uuid }
// for an opened row's address read, { check: uuid } for a leak check of
// a connected WireGuard profile or of the one the state file names, whose
// drop the kill switch can hold (leakCheck, checkReads), or { refusal }. MEANT_ON is the
// profile the kill switch's state file names while its step is set up,
// else "". A disconnect of that profile after NetworkManager dropped it,
// while the state file names it, is the state file's write alone, `argv`
// null: there is no connection left to take down.
function profileCommand(request, profiles, missing, killOn, meantOn) {
    if (!isPlain(request) || KINDS.indexOf(request.kind) === -1) return { refusal: "refused: profile=action" };
    if (profiles.state !== "available") return { refusal: "refused: profile=unavailable" };
    const row = profiles.rows.find(candidate => candidate.uuid === request.id);
    if (row === undefined) return { refusal: "refused: profile=absent" };
    if (request.kind === "profile-details") return { address: row.uuid };
    if (request.kind === "profile-check") {
        if (!checkReads(row)) return { refusal: "refused: profile=type" };
        return row.state === "activated" || (typeof meantOn === "string" && meantOn.toLowerCase() === row.uuid)
            ? { check: row.uuid } : { refusal: "refused: profile=state" };
    }
    if (request.kind === "profile-remove") return { argv: ["nmcli", "connection", "delete", "uuid", row.uuid] };
    if (request.kind === "profile-down") {
        if (row.state === "activated" || row.state === "activating") return { argv: ["nmcli", "connection", "down", "uuid", row.uuid] };
        if (typeof meantOn === "string" && meantOn.toLowerCase() === row.uuid) return { argv: null };
        return { refusal: "refused: profile=state" };
    }
    const view = rowView(row, profiles, missing, killOn);
    if (view.connected || row.state === "activating") return { refusal: "refused: profile=state" };
    if (view.reason !== "") return { refusal: "refused: profile=" + view.key };
    return { argv: ["nmcli", "connection", "up", "uuid", row.uuid] };
}

// The plan for a password connect of UUID from the prompt: { argv }, with
// nmcli reading the passwd-file line on stdin and no `--ask`, which would
// read the stdin the file has taken, or { refusal }. Only a profile that
// reads Needs password takes a password.
function passwordCommand(uuid, profiles, missing, killOn) {
    if (profiles.state !== "available") return { refusal: "refused: profile=unavailable" };
    const row = profiles.rows.find(candidate => candidate.uuid === uuid);
    if (row === undefined) return { refusal: "refused: profile=absent" };
    if (rowView(row, profiles, missing, killOn).key !== "needs-password") return { refusal: "refused: profile=state" };
    return { argv: ["nmcli", "connection", "up", "uuid", row.uuid, "passwd-file", "/dev/stdin"] };
}

// The problem line a failed change leaves, in a sentence.
function problem(kind, name, code) {
    if (code === -1) return "NetworkManager did not answer.";
    const verb = kind === "profile-up" ? "connect" : kind === "profile-down" ? "disconnect" : "remove";
    return "NetworkManager could not " + verb + " " + name + ".";
}

// The one line the status entry, the flyout header and the bar's tooltip
// share. A profile connecting or disconnecting reads first, as the bar's
// spinner shows it: a Reconnect under the block, whose notice is null
// while it moves, then reads as the connect it is, not off. NOTICE is the
// blocked-traffic notice (blockedNotice), or null: while it shows, the
// line reads the drop, naming the profile when it is listed, not off or a
// connected count.
function summary(profiles, notice) {
    if (profiles.state === "missing") return "NetworkManager is not installed";
    if (profiles.state === "not-running") return "NetworkManager is not running";
    if (profiles.state === "no-answer") return "NetworkManager did not answer";
    if (profiles.state === "reading") return "Reading your VPN profiles";
    for (const row of profiles.rows) {
        const moving = motion(row, profiles.action);
        if (moving === "connecting") return "Connecting to " + row.name;
        if (moving === "disconnecting") return "Disconnecting from " + row.name;
    }
    if (isPlain(notice)) {
        const dropped = notice.uuid === "" ? undefined : profiles.rows.find(row => row.uuid === notice.uuid);
        return dropped === undefined ? "Dropped" : dropped.name + " dropped";
    }
    if (profiles.activeCount > 1) return profiles.activeCount + " profiles connected";
    if (profiles.activeCount === 1) {
        const active = profiles.rows.find(row => row.state === "activated");
        return active === undefined ? "1 profile connected" : "Connected to " + active.name;
    }
    return "Off";
}

// A drop the notice shows reads in the danger tone, as the notice does,
// even with another profile connected outside VGS.
function connection(profiles, notice) {
    const tone = isPlain(notice) ? "danger" : profiles.state === "available" && profiles.activeCount > 0 ? "ok" : "info";
    return { tone: tone, text: summary(profiles, notice) };
}

// The bar icon: hidden with no profile or no NetworkManager; a spinner
// while a profile connects or disconnects; the warning shield while a
// profile needs its password or could not connect; else connected or off.
// NOTICE, the blocked-traffic notice or null, reads as the drop in the
// tooltip, as the flyout header reads it (summary), and puts the danger
// state dot on whatever icon shows: a live problem shows through
// BarItem.stateDot (docs/architecture/design-system.md § Components).
function barView(profiles, notice) {
    const hidden = { shown: false, icon: "shield-off", tooltip: "VPN", spinning: false, warning: false, stateDot: "" };
    if (!isPlain(profiles) || profiles.state !== "available" || profiles.count === 0) return hidden;
    const rows = Array.isArray(profiles.rows) ? profiles.rows : [];
    const stateDot = isPlain(notice) ? "danger" : "";
    for (const row of rows) {
        const moving = motion(row, profiles.action);
        if (moving === "connecting" || moving === "disconnecting")
            return { shown: true, icon: "shield", spinning: true, warning: false, stateDot: stateDot, tooltip: "VPN: " + summary(profiles, notice) };
    }
    const alert = rows.find(row => row.state !== "activated"
        && (row.failure === "needs-password" || row.failure === "failed" || row.failure === "password-tried"));
    if (alert !== undefined)
        return { shown: true, icon: "shield-alert", spinning: false, warning: true, stateDot: stateDot,
            tooltip: alert.failure === "failed" ? "VPN: Could not connect " + alert.name : "VPN: " + alert.name + " needs a password" };
    return { shown: true, icon: profiles.activeCount > 0 ? "shield-check" : "shield-off", spinning: false, warning: false, stateDot: stateDot,
        tooltip: "VPN: " + summary(profiles, notice) };
}

// Leave room for the state line while keeping the source list unchanged.
var STATUS_DATA_BYTES = 32000;
// The kill switch's two entries follow: its drawn state and, once the
// step's first probe answers, its Setup entry.
function statusWrites(connectionLine, profileValue, killState, killSetup) {
    var profiles = Object.assign({}, profileValue, { rows: profileValue.rows.slice() });
    while (Commons.SettingValues.utf8Bytes(JSON.stringify(profiles)) > STATUS_DATA_BYTES) profiles.rows.pop();
    var writes = [["connection", connectionLine], ["profiles", profiles], ["killSwitchState", killState]];
    return killSetup === undefined ? writes : writes.concat([["killSwitch", killSetup]]);
}

// The kill switch (D129). The `vpn-kill-switch` system step installs the
// root half, config/system/kill-switch/vgs-kill-switch, whose header is the
// contract read here: its units arm the nftables table from STATE_FILE, and
// `vgs-kill-switch status` prints one status line from its socket. The
// shell writes the file and reads that line; it never touches the rule.
var STATE_FILE = "/var/lib/vgshell/vpn/state";
// A writer renames a dot-prefixed temporary file in this directory over
// the state file, then creates PENDING_FILE, which starts a sync even when
// the rename landed while one ran (the root script's header).
var STATE_DIR = STATE_FILE.slice(0, STATE_FILE.lastIndexOf("/"));
var PENDING_FILE = STATE_DIR + "/pending";
var STATE_MAX = 4096;
var KILL_MODES = ["block", "block-lan", "off"];
// The longest wait for the table to arm before a connect, and the pause
// between two status reads while it waits (design: two seconds).
var ARM_WAIT_MS = 2000;
var ARM_RETRY_MS = 200;
var STATUS_ARGV = ["vgs-kill-switch", "status"];
var STATE_UUID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

// The state file's text as the root script's parse_state reads it: each
// of version, meant-on, kill-switch and portal-until once, no other key,
// one key=value per line. Its reader takes the first STATE_MAX + 1
// bytes and strips trailing line feeds, so they are allowed; an empty line
// between keys is not. Answers { kind: "valid", meantOn, mode,
// portalUntil } or { kind: "malformed" }.
function readState(text) {
    const malformed = { kind: "malformed" };
    const raw = String(text).slice(0, STATE_MAX + 1).replace(/\n+$/, "");
    if (raw.length > STATE_MAX) return malformed;
    const fields = {};
    for (const line of raw.split("\n")) {
        const split = line.indexOf("=");
        if (split === -1) return malformed;
        const key = line.slice(0, split);
        const value = line.slice(split + 1);
        if (Object.prototype.hasOwnProperty.call(fields, key)) return malformed;
        fields[key] = value;
        if (key === "version" ? value !== "1"
            : key === "meant-on" ? value !== "" && !STATE_UUID.test(value)
            : key === "kill-switch" ? KILL_MODES.indexOf(value) === -1
            : key === "portal-until" ? !/^(0|[1-9][0-9]{0,11})$/.test(value)
            : true) return malformed;
    }
    if (Object.keys(fields).length !== 4) return malformed;
    return { kind: "valid", meantOn: fields["meant-on"], mode: fields["kill-switch"], portalUntil: fields["portal-until"] };
}

// The temporary file one write fills before its rename: `.state.` and ten
// letters or digits, as the root script's own writer names it, drawn
// from RANDOM, a function answering [0, 1) such as Math.random.
var TEMP_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
function tempPath(random) {
    let name = "";
    for (let i = 0; i < 10; i++) name += TEMP_CHARS.charAt(Math.floor(random() * TEMP_CHARS.length));
    return STATE_DIR + "/.state." + name;
}

function stateText(fields) {
    return "version=1\nmeant-on=" + fields.meantOn + "\nkill-switch=" + fields.mode + "\nportal-until=" + fields.portalUntil + "\n";
}

// The text a change of FILE, the last read of the state file, writes:
// PATCH's meantOn and mode over the read, every other key kept, the
// portal time included, which VGS-2401 writes. A missing file reads as
// off. A file outside the grammar takes what `vgs-kill-switch off` writes
// for one, kill-switch=block and portal-until=0, so its owner's later
// change fails closed. Null while the file is unread or unreadable: a
// write then could drop a key another writer set.
function stateChange(file, patch) {
    const base = file.kind === "valid" ? file
        : file.kind === "missing" ? { meantOn: "", mode: "off", portalUntil: "0" }
        : file.kind === "malformed" ? { meantOn: "", mode: "block", portalUntil: "0" }
        : null;
    if (base === null) return null;
    return stateText({
        meantOn: patch.meantOn === undefined ? base.meantOn : patch.meantOn,
        mode: patch.mode === undefined ? base.mode : patch.mode,
        portalUntil: base.portalUntil
    });
}

// What a profile change KIND of UUID, of NetworkManager TYPE, writes
// first: { patch, arm, previous }, { refuse } for no write and no change,
// or null for no write. A connect names its profile and, with the kill
// switch on, waits for the table to arm; with the switch on, a profile
// that is not WireGuard is refused with the reason the root half gives
// it, since it arms no tunnel for one. A disconnect or a remove of the
// profile the file names clears it, so the block does not hold for a
// profile the user turned off; over a malformed file it writes what
// `vgs-kill-switch off` writes, meant-on= over the block base, since the
// cache can still arm one. With the step not set up there is no file to
// write. A file VGS could not read may name the profile, so every change
// plans a write, which stateChange refuses.
function meantOnPlan(kind, uuid, ready, file, type) {
    if (!ready || (kind !== "profile-up" && kind !== "profile-down" && kind !== "profile-remove")) return null;
    if (file.kind === "reading" || file.kind === "unreadable")
        return { patch: { meantOn: kind === "profile-up" ? uuid : "" }, arm: true, previous: "" };
    // The profile list holds lowercase uuids; the grammar admits either case.
    const named = file.kind === "valid" ? file.meantOn.toLowerCase() : "";
    // The mode stateChange keeps or writes.
    const mode = file.kind === "valid" ? file.mode : file.kind === "malformed" ? "block" : "off";
    if (kind === "profile-up") {
        if (mode !== "off" && type !== "wireguard") return { refuse: "profile-not-wireguard" };
        return { patch: { meantOn: uuid }, arm: mode !== "off", previous: named };
    }
    if (named === uuid || file.kind === "malformed") return { patch: { meantOn: "" }, arm: false, previous: named };
    return null;
}

// `vgs-kill-switch status`: one line, as the root script's status_pattern
// holds it. A failed read is a reading too: `unreadable` when the script's
// refusal, the first line of ERRORS, says the socket answered with no
// status line, else `unreachable`, as for its own status=unreachable, a
// run that never started and any other output.
var STATUS_LINE = /^state=(off|holding|passing|unavailable) reason=([a-z-]{1,40}) blocked=([0-9]{1,20}) tunnel=([A-Za-z0-9_.-]{0,15}) profile=((?:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})?)$/;
var STATUS_UNREADABLE = /^vgs-kill-switch: refused: status=unreadable(?: |$)/;
function killStatus(code, text, errors) {
    const found = code === 0 ? STATUS_LINE.exec(String(text).replace(/\n$/, "")) : null;
    if (found === null) {
        const unreadable = code === 1 && STATUS_UNREADABLE.test(String(errors === undefined ? "" : errors).split("\n")[0]);
        return { state: unreadable ? "unreadable" : "unreachable", reason: "", blocked: "0", tunnel: "", profile: "" };
    }
    return { state: found[1], reason: found[2], blocked: found[3].replace(/^0+(?=[0-9])/, ""), tunnel: found[4], profile: found[5].toLowerCase() };
}

// What a status read means to a connect of UUID waiting for the table:
// `armed` with the table in place for UUID, `unavailable` when the root
// half armed for UUID without a usable profile, `failed` for a read that
// gave no line, else `waiting`. Only a line whose profile= is UUID
// answers: a line left from the previous profile, or from a sync still
// running, never does, and cache-unreadable, which a sync shows between
// deleting the cache and writing it again, names no profile.
// device-uncovered is `armed`: the table is in place for UUID, and a
// rollback for a device the root half cannot judge would drop the block
// it does hold.
function armOutcome(status, uuid) {
    if (status === null) return "waiting";
    if (status.state === "unreachable" || status.state === "unreadable") return "failed";
    if (status.profile !== uuid) return "waiting";
    if (status.state === "holding" || status.state === "passing") return "armed";
    if (status.state === "unavailable" && status.reason === "device-uncovered") return "armed";
    return status.state === "unavailable" ? "unavailable" : "waiting";
}

// Why the root half cannot use the profile, or which traffic it cannot
// judge, in a sentence, from its status reason. NAME is the profile's.
function unavailableWords(reason, name) {
    switch (reason) {
    case "profile-not-wireguard": return name + " is not a WireGuard profile, and the kill switch works only with WireGuard.";
    case "profile-missing": return "The VPN profile is gone.";
    case "endpoint-hostname": return name + " names its server by host name, and the kill switch needs an IP address.";
    case "endpoint-invalid": return name + "'s server address is not valid.";
    case "interface-invalid": return name + "'s network interface name is not valid.";
    case "profile-unread":
    case "cache-unreadable": return "The kill switch could not read " + name + ".";
    case "device-uncovered": return "The kill switch cannot check one of the network devices, so traffic can go out through it without the VPN.";
    }
    return "The kill switch cannot use " + name + ".";
}

// The problem line a profile change the kill switch stopped leaves.
// CAUSE is `write` (the state file was not saved), `timeout` (the table
// did not arm in ARM_WAIT_MS) or `unavailable` with the status REASON.
// CAUSE `unchecked` is a wait in which no status read gave a line, and
// `setup` one that ended while the step reads needed. With
// UNRESTORED, the rollback of the state file failed, so it still names
// NAME and the table can block traffic for it.
function stageProblem(kind, name, cause, reason, unrestored) {
    const verb = kind === "profile-up" ? "connect" : kind === "profile-down" ? "disconnect" : "remove";
    if (cause === "setup")
        return "The kill switch needs to be set up again, so VGS did not connect " + name + ". Use Set up in the kill switch row.";
    if (unrestored === true)
        return "VGS did not connect " + name + " and could not clear it from the kill switch. " + sentence(KILL_OFF) + " to clear it.";
    if (cause === "write") return "VGS could not save the kill switch setting, so it did not " + verb + " " + name + ".";
    if (cause === "unchecked") return "VGS could not check the kill switch, so it did not connect " + name + ". " + sentence(KILL_OFF) + " to connect without it.";
    if (cause === "timeout") return "The kill switch did not start, so VGS did not connect " + name + ". " + sentence(KILL_OFF) + " to connect without it.";
    return unavailableWords(reason, name) + " VGS did not connect it.";
}

// The step's reading as one word: `checking` before the first probe,
// `setup` while it can be applied, `ready`, `denied`, `unknown` or
// `absent`.
function stepWord(step) {
    if (!isPlain(step)) return "checking";
    if (step.state === "needed" || step.state === "nixos") return "setup";
    return ["ready", "denied", "unknown", "absent"].indexOf(step.state) !== -1 ? step.state : "unknown";
}

// What a leak check reads of the kill switch with STEP its system step:
// `none` when the step rules out a table (absent, or denied for NixOS,
// systemd or nftables), so the check judges it off; else `read`, its
// status. A table can be armed while the step reads anything else: an
// update that changes the step's files leaves the installed ones running
// until Set up, a failed unit leaves the table in place, and the status
// socket answers any local user, another account's table too (D129).
var KILL_RULED_OUT = ["nixos-unsupported", "systemd-missing", "nft-missing"];
function checkKillPlan(step) {
    const word = stepWord(step);
    return word === "absent" || (word === "denied" && KILL_RULED_OUT.indexOf(step.reason) !== -1) ? "none" : "read";
}
// The kill switch status a leak check judges from a status read while
// the step reads READY or not: STATUS, killStatus's reading, or null for
// not set up when the step is not set up and the status command never
// started, since the step installs it (vgshell-system vpn-kill-switch).
function checkKillStatus(ready, status, started) {
    return !ready && !started ? null : status;
}

// The value the service publishes as `killSwitchState`, which the flyout
// and the section draw (killSwitchView). SETTLING holds from a write's
// end until a status read started after it has ended, the grace a sync
// takes to follow the write.
function killSwitchState(step, file, status, busy, problem, settling) {
    const valid = file.kind === "valid";
    return {
        step: stepWord(step), reason: isPlain(step) && typeof step.reason === "string" ? step.reason : "",
        file: file.kind, mode: valid ? file.mode : file.kind === "missing" ? "off" : "", meantOn: valid ? file.meantOn : "",
        status: status, busy: busy === true, problem: typeof problem === "string" ? problem : "", settling: settling === true
    };
}

// The `killSwitch` Setup entry: nothing before the first probe, so
// Settings reads it as Checking.
function killSwitchSetup(step) {
    switch (stepWord(step)) {
    case "checking": return undefined;
    case "setup": return { tone: "warning", text: "Not set up", action: true };
    case "ready": return { tone: "ok", text: "Set up", action: false };
    case "absent": return { hidden: true };
    case "denied": return { tone: "warning", text: "Not available", action: false, available: false, hint: deniedWords(step.reason) };
    }
    return { tone: "warning", text: "Could not check", action: false, available: false, hint: "VGS could not read the kill switch setup. VGS checks again each time you open Settings." };
}

function deniedWords(reason) {
    switch (reason) {
    case "nixos-unsupported": return "The kill switch is not available on NixOS.";
    case "other-account": return "Another account on this computer set up the kill switch.";
    case "systemd-missing": return "The kill switch needs systemd.";
    case "nft-missing": return "The kill switch needs nftables. Install the nftables package.";
    }
    return "The kill switch is not available on this computer.";
}

// Whether STATE, the published `killSwitchState`, reads the kill switch set
// up and on.
function killSwitchOn(state) {
    return isPlain(state) && state.step === "ready" && (state.mode === "block" || state.mode === "block-lan");
}

// The blocked-traffic notice over the profiles, from STATE, the published
// `killSwitchState`, and PROFILES: null unless the kill switch is set up
// and on, the state file names a profile and the status read says
// holding for that profile, the block in place with its tunnel gone. A
// profile connected, connecting or changing is no drop: holding is also
// the state between the table arming for a connect and its tunnel coming
// up. `uuid` is the named profile when it is listed, whose disconnect
// ends the block (profileCommand), else "", where turning the kill switch
// off is the way out.
function blockedNotice(state, profiles) {
    if (!killSwitchOn(state) || state.file !== "valid" || state.meantOn === "") return null;
    const named = state.meantOn.toLowerCase();
    if (!isPlain(state.status) || state.status.state !== "holding" || state.status.profile !== named) return null;
    const rows = isPlain(profiles) && Array.isArray(profiles.rows) ? profiles.rows : [];
    const meant = rows.find(row => row.uuid === named);
    if (meant === undefined)
        return { uuid: "", text: "The VPN dropped, and the kill switch blocks traffic. " + sentence(KILL_OFF) + " to end the block." };
    if (meant.state === "activated" || meant.state === "activating" || motion(meant, profiles.action) !== "") return null;
    return { uuid: meant.uuid, text: "VPN dropped: traffic blocked" };
}

var KILL_COUNT_INFO = "Counts each time the kill switch refused traffic outside the VPN since it last started: when you turned on the VPN or the kill switch in VGS, or when this computer started. "
    + "A change to another VPN profile while one is on does not restart it, and a VGS update can restart it. "
    + "One app can try many times, so it is not a count of apps or sites.";
var KILL_LAN_HINT = "Printers, shared folders, containers and virtual machines work only with this on";
// What the kill switch row draws from STATE, the published
// `killSwitchState`, and PROFILES, for the profile names: whether it
// shows, Set up in place of the switch, the switch and Allow local
// network with their states and the reason they are disabled, and the
// line under them with its tone, "" or `danger`, and `countInfo`, the
// switch's info while its line is the refused count.
function killSwitchView(state, profiles) {
    const view = { shown: true, setup: false, switchOn: false, lanShown: false, lanOn: false, reason: "", hint: "", tone: "", countInfo: "" };
    if (!isPlain(state) || state.step === "absent") return Object.assign(view, { shown: false });
    const fill = extra => Object.assign(view, extra);
    switch (state.step) {
    case "checking": return fill({ reason: "Wait until VGS checks the kill switch setup." });
    case "setup": return fill({ setup: true, hint: "Set up installs a firewall service that keeps the block in place when VGS is not running" });
    case "denied": return fill({ reason: deniedWords(state.reason), hint: deniedWords(state.reason) });
    case "unknown": return fill({ reason: "VGS could not check the kill switch setup.", hint: "VGS could not check the kill switch setup. VGS checks again each time you open Settings." });
    }
    if (state.file === "reading") return fill({ reason: "Wait until VGS reads the kill switch setting." });
    if (state.file === "unreadable")
        return fill({ reason: "VGS could not read the kill switch setting.", hint: "VGS could not read the kill switch setting.", tone: "danger" });
    const on = state.mode === "block" || state.mode === "block-lan";
    fill({ switchOn: on, lanShown: on, lanOn: state.mode === "block-lan", reason: state.busy ? "Wait until VGS saves this setting." : "" });
    if (state.problem !== "") return fill({ hint: state.problem, tone: "danger" });
    if (state.file === "malformed")
        return fill({ hint: "VGS could not read the kill switch setting. Turn it on or off to save it again.", tone: "danger" });
    if (!on) return view;
    const rows = isPlain(profiles) && Array.isArray(profiles.rows) ? profiles.rows : [];
    const meant = rows.find(row => row.uuid === String(state.meantOn).toLowerCase());
    const name = meant !== undefined ? meant.name : "the VPN";
    const status = isPlain(state.status) ? state.status : null;
    if (status === null) return view;
    switch (status.state) {
    case "passing": return fill({ hint: "Active for " + name });
    // Beside the blocked-traffic notice, which says what holds and the way
    // out, the line is the root half's refused count, with what it counts
    // in the switch's info (docs/architecture/design-system.md § Copy).
    // The counter counts the packets the table refused since it was last
    // created: the root half creates it when the VPN or the switch is
    // turned on in VGS and at boot, and deletes it at every off
    // (vgs-kill-switch, sync).
    case "holding":
        if (blockedNotice(state, profiles) === null) return fill({ hint: "Blocking traffic outside the VPN" });
        return fill({ hint: "Refused traffic " + status.blocked + (status.blocked === "1" ? " time" : " times") + " since the kill switch started",
            countInfo: KILL_COUNT_INFO });
    case "unavailable": {
        // The root half still passes tailscale0, DHCP and, under block-lan,
        // the local network, so the line names the way out, not a scope.
        const words = unavailableWords(status.reason, meant !== undefined ? meant.name : "the VPN profile");
        return fill({ hint: sentence(words) + " " + sentence(KILL_OFF) + " to end the block.", tone: "danger" });
    }
    case "off":
        if (state.meantOn === "") return fill({ hint: "Starts when you connect a VPN here" });
        // Naming a profile with no rule in place: while a write runs or
        // its sync may still be arming, no claim; with the profile
        // connected, the units did not arm or the table was removed, and
        // a write, which turning the switch off and on makes, starts a
        // sync again. A profile not connected is the problem line's to
        // explain.
        if (state.busy || state.settling || meant === undefined || meant.state !== "activated") return view;
        return fill({ hint: "The kill switch is not active for " + name + ", so traffic is not blocked if it drops. To start it, " + KILL_OFF + ", then turn it on again.", tone: "danger" });
    }
    // unreachable and unreadable: either way VGS cannot tell.
    return fill({ hint: "VGS cannot check whether the kill switch is blocking traffic" });
}

// The leak check (VGS-2398). The service takes its readings when a
// connect it ran ends and when the user presses Check, never on a timer,
// and keeps no reading but the last check's kill switch count. Each
// reading is parsed here, and leakCheck judges them.
//
// It reads WireGuard profiles alone, the kill switch's scope (D129): nmcli
// fills GENERAL.IP-IFACE from the active connection's device, which for a
// NetworkManager VPN-plugin connection is the parent device, the uplink,
// so the check would judge the uplink as the tunnel.
function checkReads(row) {
    return isPlain(row) && row.type === "wireguard";
}

// The tunnel's network interface: GENERAL.IP-IFACE of the profile while
// it is activated. nmcli 1.58.1 prints nothing, with exit 0, for a profile
// that is not active (recorded under LC_ALL=C, 2026-11-11;
// scripts/fixtures/vpn/link*.txt).
function linkArgv(uuid) {
    return ["nmcli", "-t", "-f", "GENERAL.STATE,GENERAL.IP-IFACE", "connection", "show", "uuid", uuid];
}
// An interface name as the kill switch's status line admits one.
var LINK_NAME = /^[A-Za-z0-9_.-]{1,15}$/;
// { kind: "active", link } while the profile is activated, `inactive`
// while it is not, else `unreadable`.
function linkRead(code, text) {
    if (code !== 0) return { kind: "unreadable" };
    const output = String(text);
    if (output.trim() === "") return { kind: "inactive" };
    const state = /^GENERAL\.STATE:(.*)$/m.exec(output);
    if (state === null) return { kind: "unreadable" };
    if (state[1] !== "activated") return { kind: "inactive" };
    const link = /^GENERAL\.IP-IFACE:(.*)$/m.exec(output);
    return link !== null && LINK_NAME.test(link[1]) ? { kind: "active", link: link[1] } : { kind: "unreadable" };
}

// The route an internet address of each family takes: the kernel's
// answer for a documentation address (RFC 5737, RFC 3849), which no route
// names in particular. `ip route get` follows the policy rules a
// WireGuard profile adds and sends nothing.
var ROUTE_PROBES = { ipv4: "192.0.2.1", ipv6: "2001:db8::1" };
function routeArgv(family) {
    return ["ip", "-j", family === "ipv6" ? "-6" : "-4", "route", "get", ROUTE_PROBES[family]];
}
// iproute2 7.3.0 under LC_ALL=C, recorded in network namespaces on
// 2026-11-11 (scripts/fixtures/vpn/route-*.txt): one JSON route whose `dev`
// is the link it leaves by; with no route, exit 2 and one of these lines.
var NO_ROUTE = /^RTNETLINK answers: (?:Network is unreachable|No route to host)$/;
// { kind: "via", link }, `none` for no route out, else `unreadable`.
function routeRead(code, text, errors) {
    if (code === 2 && NO_ROUTE.test(String(errors).replace(/\n+$/, ""))) return { kind: "none" };
    if (code !== 0) return { kind: "unreadable" };
    let routes;
    try { routes = JSON.parse(String(text)); } catch (error) { return { kind: "unreadable" }; }
    if (!Array.isArray(routes) || routes.length !== 1 || !isPlain(routes[0])
        || typeof routes[0].dev !== "string" || !LINK_NAME.test(routes[0].dev)) return { kind: "unreadable" };
    return { kind: "via", link: routes[0].dev };
}

// systemd-resolved's settings through its varlink interface:
// io.systemd.Resolve.DumpDNSConfiguration, whose DNSConfiguration entries
// are the global settings (no ifname, ifindex or delegate), each link's
// and each delegate's, with `defaultRoute`, `servers`, `fallbackServers`
// (global only) and `searchDomains`, which holds the search and the
// route-only domains (introspected on systemd 262, 2026-11-11). `~.`
// reads as the domain "." with routeOnly true.
var DNS_ARGV = ["varlinkctl", "--json=short", "call", "/run/systemd/resolve/io.systemd.Resolve",
    "io.systemd.Resolve.DumpDNSConfiguration", "{}"];
// The name a lookup target with no link of its own reads as: the global
// servers, a delegate's or the compiled-in fallback servers. No interface
// name holds a space (LINK_NAME).
var GLOBAL_DNS = "global servers";
// resolved's routing holds for programs that read /etc/resolv.conf only
// while it names resolved's stub (the global entry's `resolvConfMode`,
// stub or static). In uplink or foreign mode it lists servers that such
// programs (musl or static binaries, dig, Go's own resolver) ask directly,
// the Wi-Fi's among them; with missing, or no mode read, it is unknown.
var RESOLVED_MODES = ["stub", "static"];
// { kind: "scopes", scopes: [{ link, defaultRoute, domains }], fallback }
// for each entry that holds a DNS server, the global servers taking every
// name no domain routes, as for a default-route link; `fallback` when the
// global settings list fallback servers. Else `unreadable`: a reading
// the judge cannot fully evaluate is no pass.
function dnsRead(code, text) {
    const unreadable = { kind: "unreadable" };
    if (code !== 0) return unreadable;
    let reply;
    try { reply = JSON.parse(String(text)); } catch (error) { return unreadable; }
    if (!isPlain(reply) || !Array.isArray(reply.configuration)) return unreadable;
    const absent = value => value === undefined || value === null;
    const list = value => absent(value) ? [] : value;
    const scopes = [];
    let fallback = false;
    let mode = null;
    for (const entry of reply.configuration) {
        if (!isPlain(entry)) return unreadable;
        const global = absent(entry.ifname) && absent(entry.ifindex) && absent(entry.delegate);
        const servers = list(entry.servers);
        const domains = list(entry.searchDomains);
        if (!Array.isArray(servers) || !Array.isArray(domains) || !Array.isArray(list(entry.fallbackServers))
            || domains.some(domain => !isPlain(domain) || typeof domain.name !== "string" || domain.name === "")) return unreadable;
        if (global) {
            fallback = fallback || list(entry.fallbackServers).length > 0;
            mode = entry.resolvConfMode;
        }
        if (servers.length === 0) continue;
        const link = global || !absent(entry.delegate) ? GLOBAL_DNS : entry.ifname;
        if (typeof link !== "string" || (link !== GLOBAL_DNS && !LINK_NAME.test(link))) return unreadable;
        if (!global && typeof entry.defaultRoute !== "boolean") return unreadable;
        // resolved keeps a domain without its final dot, the root as ".".
        const names = domains.map(domain => domain.name === "." ? "." : domain.name.toLowerCase().replace(/\.$/, ""));
        scopes.push({ link: link, defaultRoute: global || entry.defaultRoute, domains: names });
    }
    if (RESOLVED_MODES.indexOf(mode) === -1) return unreadable;
    return { kind: "scopes", scopes: scopes, fallback: fallback };
}
// The domains Tailscale routes to tailscale0 for its own names: MagicDNS
// under ts.net and the reverse zones of its addresses, 100.64.0.0/10 and
// fd7a:115c:a1e0::/48 (systemd 262's DumpDNSConfiguration on a host
// running Tailscale, 2026-11-11). Any other domain there is one a tailnet
// admin routes to a nameserver outside the VPN.
var TAILNET_ZONE = /^(?:.+\.)?(?:ts\.net|(?:6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.100\.in-addr\.arpa|0\.e\.1\.a\.c\.5\.1\.1\.a\.7\.d\.f\.ip6\.arpa)$/;
function tailnetOnly(scope, domain) {
    return scope.link === "tailscale0" && TAILNET_ZONE.test(domain);
}
function unique(links) {
    return links.filter((link, index) => links.indexOf(link) === index);
}
// Where a lookup goes, by systemd-resolved.service(8) § Protocols and
// routing: a name under a routing or search domain goes to the targets
// whose matching domain has the most labels, "." matching every name with
// none; a name no domain matches goes to every default-route link and the
// global servers, and with none of those to the fallback servers.
function unroutedLinks(dns) {
    const links = dns.scopes.filter(scope => scope.defaultRoute).map(scope => scope.link);
    return links.length === 0 && dns.fallback ? [GLOBAL_DNS] : links;
}
// Where a lookup for some internet name can go: any domain but "." takes
// some names to its target, sharing them with a tunnel that holds the
// same domain, and the rest go to the targets that hold ".", or unrouted.
// Tailscale's own domains take no name of the internet. The names of the
// targets, each once.
function lookupLinks(dns) {
    const named = dns.scopes.filter(scope => scope.domains.some(domain => domain !== "." && !tailnetOnly(scope, domain)));
    const root = dns.scopes.filter(scope => scope.domains.indexOf(".") !== -1);
    return unique(named.concat(root).map(scope => scope.link).concat(root.length > 0 ? [] : unroutedLinks(dns)));
}
// Where a lookup of NAME, lower case with no final dot, goes: the targets
// of its longest matching domain, else unrouted.
function nameLinks(dns, name) {
    let best = -1;
    let links = [];
    for (const scope of dns.scopes) for (const domain of scope.domains) {
        if (domain !== "." && name !== domain && !name.endsWith("." + domain)) continue;
        const depth = domain === "." ? 0 : domain.split(".").length;
        if (depth > best) { best = depth; links = []; }
        if (depth === best) links.push(scope.link);
    }
    return unique(best === -1 ? unroutedLinks(dns) : links);
}

// The one outside service: the VPN provider's own, asked through the
// tunnel for the public address it sees. api.nordvpn.com answers IPv4
// alone, with no sign-in (VGS-2398 facts, 2026-11-08). -q reads no
// curlrc; no redirect is followed.
var INSIGHTS_HOST = "api.nordvpn.com";
var INSIGHTS_URL = "https://" + INSIGHTS_HOST + "/v1/helpers/ips/insights";
var INSIGHTS_SECONDS = 10;
var INSIGHTS_MAX = 4096;
function insightsArgv(link) {
    return ["curl", "-q", "--silent", "--show-error", "--fail", "--ipv4", "--interface", "if!" + link, "--proto", "=https",
        "--max-time", String(INSIGHTS_SECONDS), "--max-filesize", String(INSIGHTS_MAX), INSIGHTS_URL];
}
// curl's exit codes (curl(1) § Exit codes, curl 8.23.0) as the reason
// keys checkView words; -1 is a run the check's deadline ended.
var CURL_REASONS = { "-1": "timeout", 6: "lookup", 7: "connect", 22: "refused", 28: "timeout", 35: "secure",
    45: "interface", 60: "secure", 63: "malformed" };
var IPV4 = /^(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(?:\.(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}$/;
// A place name the answer gives, or null for one that is no short text.
function placeName(value) {
    return typeof value === "string" && value.length <= TEXT_MAX && !/[\u0000-\u001f\u007f<]/.test(value) ? value.trim() : null;
}
// The answer, untrusted: at most INSIGHTS_MAX characters of one JSON
// object whose `ip` is an IPv4 address and whose `country` is short text,
// and `city` too when present. { kind: "ok", ip, country, city } or
// { kind: "failed", reason }: never a blank or a guessed field.
function insights(code, text) {
    if (code !== 0) return { kind: "failed", reason: CURL_REASONS[code] || "request" };
    const raw = String(text);
    let answer = null;
    try {
        if (raw.length <= INSIGHTS_MAX) answer = JSON.parse(raw);
    } catch (error) {
        answer = null;
    }
    if (!isPlain(answer) || typeof answer.ip !== "string" || !IPV4.test(answer.ip)) return { kind: "failed", reason: "malformed" };
    const country = placeName(answer.country);
    const city = answer.city === undefined || answer.city === null ? "" : placeName(answer.city);
    if (country === null || country === "" || city === null) return { kind: "failed", reason: "malformed" };
    return { kind: "ok", ip: answer.ip, country: country, city: city };
}
// Whether a check of a connected profile asks the provider, over READINGS
// with every reading in but `public`: { kind: "ask", link } through the
// tunnel's interface while lookups of the provider's name stay in the
// tunnel or the armed kill switch blocks the rest, else the failed answer
// with its reason. curl
// looks the provider's name up through the system resolver: --interface
// binds the transfer alone, and Arch's curl 8.23.0, built without c-ares,
// refuses --dns-interface ("the installed libcurl version does not
// support this", run 2026-11-11), so a lookup the judge cannot place in
// the tunnel is never made.
function publicPlan(readings) {
    if (readings.link.kind !== "active") return { kind: "failed", reason: readings.link.kind === "unreadable" ? "link" : "inactive" };
    const dns = leakCheck(Object.assign({}, readings, { public: null }), null, INSIGHTS_HOST).dns.verdict;
    if (dns === "tunnel" || dns === "blocked") return { kind: "ask", link: readings.link.link };
    return { kind: "failed", reason: dns === "leak" ? "lookups-leak" : "lookups-unknown" };
}

// The links every armed kill switch passes besides its tunnel (D129).
var KILL_PASSES = ["tailscale0"];
// Whether count A, as killStatus gives it, is above B.
function countAbove(a, b) {
    return a.length !== b.length ? a.length > b.length : a > b;
}
// The kill switch as one check reads it, from STATUS, killStatus's
// reading or null while the kill switch is not set up: `holding` (armed,
// its tunnel gone), `on` (armed: passing, or unavailable, which arms
// closed), `off` or `unknown`, with its refused count and, against BEFORE,
// the last check's reading, the count then and whether it rose.
function killReading(status, before) {
    const off = { state: "off", profile: "", tunnel: "", blocked: "", previous: "", rising: false };
    if (status === null || status.state === "off") return off;
    if (status.state !== "holding" && status.state !== "passing" && status.state !== "unavailable") return Object.assign(off, { state: "unknown" });
    const previous = isPlain(before) && (before.state === "holding" || before.state === "on") && before.profile === status.profile ? before.blocked : "";
    return { state: status.state === "holding" ? "holding" : "on", profile: status.profile, tunnel: status.tunnel,
        blocked: status.blocked, previous: previous, rising: previous !== "" && countAbove(status.blocked, previous) };
}

// One check of profile UUID over READINGS { uuid, link (linkRead), status
// (killStatus, or null while the kill switch is not set up), ipv4 and
// ipv6 (routeRead), dns (dnsRead), public (insights or publicPlan's
// failure, or null when not asked) }, with BEFORE the last check's
// `kill`, or null, and HOST, when given, the one name whose lookups DNS
// judges, else every name. A reading whose command is not installed is
// { kind: "missing", command }. Each family reads `tunnel` when it leaves
// by the tunnel alone, `none` with no route out, `blocked` when the armed
// kill switch refuses what leaves elsewhere, `leak` with the link it
// leaves by, or `unknown` with its reason, and the command to install
// for `missing`, for any reading that could not be taken or read: never
// a pass.
function leakCheck(readings, before, host) {
    const kill = killReading(readings.status, before);
    const tunnel = readings.link.kind === "active" ? readings.link.link : "";
    const passes = kill.tunnel === "" ? KILL_PASSES : KILL_PASSES.concat([kill.tunnel]);
    const unknown = (reason, install) => ({ verdict: "unknown", link: "", reason: reason, install: install || "" });
    const verdict = (word, link) => ({ verdict: word, link: link, reason: "", install: "" });
    // OUTS: the links it leaves by, or the unknown verdict of its reading.
    function judge(outs) {
        if (readings.link.kind === "unreadable") return unknown("link");
        if (!Array.isArray(outs)) return outs;
        if (outs.length === 0) return verdict("none", "");
        const outside = outs.filter(name => name !== tunnel);
        if (outside.length === 0) return verdict("tunnel", "");
        const passed = outside.find(name => passes.indexOf(name) !== -1);
        if (passed !== undefined) return verdict("leak", passed);
        if (kill.state === "holding" || kill.state === "on") return verdict("blocked", "");
        return kill.state === "unknown" ? unknown("kill") : verdict("leak", outside[0]);
    }
    const unread = reading => reading.kind === "missing" ? unknown("missing", reading.command) : unknown("read");
    const route = reading => reading.kind === "via" ? [reading.link] : reading.kind === "none" ? [] : unread(reading);
    // A lookup no target takes goes nowhere this reading can judge.
    const lookups = readings.dns.kind !== "scopes" ? unread(readings.dns)
        : host === undefined ? lookupLinks(readings.dns) : nameLinks(readings.dns, host);
    return {
        uuid: readings.uuid, kill: kill, public: readings.public,
        ipv4: judge(route(readings.ipv4)), ipv6: judge(route(readings.ipv6)),
        dns: judge(Array.isArray(lookups) && lookups.length === 0 ? unknown("lookups") : lookups)
    };
}

// Whether CHECK, the published `leakCheck`, no longer describes its
// profile after a list read NetworkManager answered with ROWS: its
// result, or the one in flight, was of the profile connected and the list
// shows it not connected, or the other way round. A later connect is
// another connection, so the result goes, also for a change VGS did not
// make. ACTION, the change in flight, holds its own profile back: a list
// read that started before its end still shows the state before it
// (Service.runEnded).
function checkStale(check, rows, action) {
    if (!isPlain(check) || (check.busy !== true && !isPlain(check.result))) return false;
    if (isPlain(action) && action.uuid === check.uuid) return false;
    const row = rows.find(candidate => candidate.uuid === check.uuid);
    return row === undefined || (row.state === "activated") !== check.active;
}

// What a profile row draws of CHECK, the published `leakCheck` ({ uuid,
// busy, active, result }, or null), for ROW, whose switch the blocked-
// traffic notice names when HELD is its uuid: whether it shows, Check's
// disabled reason, the public address and its place, one line per family
// and the kill switch line. Each line is { text, error, hint, link,
// install }: its value, the error line for a leak or a reading that
// failed, and for a command not installed a hint whose LINK words offer
// INSTALL (Field `hintLink`).
var PUBLIC_INFO = "VGS asks " + INSIGHTS_HOST + ", NordVPN's own service, which public address it sees. "
    + "It asks through the VPN once after you connect a WireGuard profile here and each time you press Check, "
    + "only when the lookup of its name stays in the VPN, and never while no profile is connected. "
    + "The service sees the address the question comes from, the address every site you open sees.";
var CHECK_REASONS = {
    link: "VGS could not read the VPN's network interface",
    inactive: "The VPN is not connected",
    "lookups-leak": "VGS did not ask, because name lookups can go outside the VPN",
    "lookups-unknown": "VGS did not ask, because it could not check where name lookups go",
    interface: "VGS could not send the question through the VPN",
    lookup: "VGS could not find " + INSIGHTS_HOST,
    connect: INSIGHTS_HOST + " did not answer",
    timeout: INSIGHTS_HOST + " did not answer in " + INSIGHTS_SECONDS + " seconds",
    refused: INSIGHTS_HOST + " refused the question",
    secure: "VGS could not make a secure connection to " + INSIGHTS_HOST,
    malformed: INSIGHTS_HOST + " sent an answer VGS cannot read",
    request: "The question to " + INSIGHTS_HOST + " did not complete"
};
// What a user installs for each command a check runs, as the requirement's
// package is named upstream; the install notice picks the package per
// package manager (manifest `requirements`).
// The reasons VGS did not ask, which read as a check not made, not failed.
var NOT_ASKED = ["lookups-leak", "lookups-unknown"];
var CHECK_INSTALLS = { ip: "iproute2", varlinkctl: "systemd", curl: "curl" };
var FAMILIES = [["ipv4", "IPv4"], ["ipv6", "IPv6"], ["dns", "DNS"]];
function checkLine(text, error) {
    return { text: text, error: error || "", hint: "", link: "", install: "" };
}
function installLine(command, what) {
    const link = "Install " + CHECK_INSTALLS[command];
    return { text: "Could not check", error: "", hint: link + " to check " + what, link: link, install: command };
}
function familyLine(key, family) {
    const dns = key === "dns";
    switch (family.verdict) {
    case "tunnel": return checkLine("In the VPN");
    case "none": return checkLine("Not used");
    case "blocked": return checkLine("Blocked by the kill switch");
    case "leak":
        if (family.link === GLOBAL_DNS) return checkLine("Leaks", "Name lookups can go to DNS servers outside the VPN");
        return checkLine("Leaks", (dns ? "Name lookups can go through " : "Traffic goes out through ") + family.link + ", outside the VPN");
    }
    switch (family.reason) {
    case "missing": return installLine(family.install, "this");
    case "link": return checkLine("Could not check", CHECK_REASONS.link);
    case "kill": return checkLine("Could not check", "VGS could not check whether the kill switch blocks it");
    case "lookups": return checkLine("Could not check", "VGS could not find where name lookups go");
    }
    return checkLine("Could not check", dns ? "VGS could not read the DNS settings" : "VGS could not read the route");
}
function killLine(kill) {
    if (kill.state === "unknown") return checkLine("Could not check", "VGS could not read the kill switch");
    const times = kill.blocked + (kill.blocked === "1" ? " time" : " times");
    return checkLine((kill.state === "holding" ? "Holding" : "On") + ", refused traffic " + times
        + (kill.rising ? ", up from " + kill.previous + " at the last check" : ""));
}
function checkView(check, row, held) {
    const view = { shown: false, reason: "", publicShown: false, public: checkLine(""), place: "", families: [], killShown: false, kill: checkLine("") };
    if (!checkReads(row)) return view;
    const active = row.state === "activated";
    if (!active && held !== row.uuid) return view;
    const mine = isPlain(check) && check.uuid === row.uuid ? check : null;
    // A result of the profile connected does not describe its drop, nor
    // the other way round (checkStale drops one a later list outdates).
    const result = mine !== null && !mine.busy && mine.active === active && isPlain(mine.result) ? mine.result : null;
    const busy = mine !== null && mine.busy;
    Object.assign(view, { shown: true, publicShown: active, reason: busy ? "Wait until the check ends." : "" });
    if (result === null) {
        view.public = checkLine(busy ? "Checking…" : "Not checked");
        if (busy) view.families = FAMILIES.map(pair => Object.assign({ key: pair[0], label: pair[1] }, checkLine("Checking…")));
        return view;
    }
    const answer = result.public;
    if (isPlain(answer) && answer.kind === "ok") {
        view.public = checkLine(answer.ip);
        view.place = answer.city === "" ? answer.country : answer.city + ", " + answer.country;
    } else if (isPlain(answer) && answer.reason === "missing") {
        view.public = installLine("curl", "the public address");
    } else {
        const reason = isPlain(answer) && CHECK_REASONS[answer.reason] !== undefined ? answer.reason : "request";
        view.public = checkLine(NOT_ASKED.indexOf(reason) !== -1 ? "Not checked" : "Could not check", CHECK_REASONS[reason]);
    }
    view.families = FAMILIES.map(pair => Object.assign({ key: pair[0], label: pair[1] }, familyLine(pair[0], result[pair[0]])));
    // A kill switch that is off has its own row in the flyout and section.
    return Object.assign(view, { killShown: result.kill.state !== "off", kill: killLine(result.kill) });
}

// Connect automatically (VGS-2399). The list read the profiles come from,
// `nmcli -t -f NAME,UUID,TYPE,STATE connection show`, also holds every
// saved connection with its state, so the service decides from
// NetworkManager's own profiles, and NetworkManager's own activation
// connects the chosen VPN profile, through the same connect a press runs
// (profileCommand), so the kill switch's state file names it first
// (D129). The types are the connection.type setting names nmcli prints in
// terse mode (scripts/fixtures/vpn/list.txt; nm-settings-nmcli(5)).
//
// Only a Wi-Fi profile can be trusted (overseer ruling on VGS-2399): a
// profile names a connection setting, not a place, and a wired, Bluetooth
// or mobile profile matches any network on its port or device. A Wi-Fi
// profile matches every network with the same name and password, or the
// same name when it is open.
var WIFI_TYPE = "802-11-wireless";
// Every other activated connection is a network that is not trusted,
// unknown uplink types included (pppoe, vlan, bond), except these, which
// carry no uplink of their own and stay up on any network: the VPN
// profiles themselves, loopback, a tun such as tailscale0, a bridge such
// as docker0 (a bridge that enslaves the uplink activates the uplink's own
// profile too), dummy and veth.
var LOCAL_TYPES = ["vpn", "wireguard", "loopback", "tun", "bridge", "dummy", "veth"];
// A Settings select offers at most this many choices
// (PluginLogic.STATUS_LIST_MAX); active networks come first.
var NETWORK_MAX = 64;
// The longest label of a published choice (PluginLogic.STATUS_LABEL_MAX).
var CHOICE_MAX = 60;
// The longest problem line the Settings field takes (PluginLogic.STATUS_TEXT_MAX).
var PROBLEM_MAX = 200;

function emptyNetworks(state) { return { state: state, rows: [], active: [], activeWifi: [], count: 0 }; }

// A printable choice label of at most CHOICE_MAX characters, as line()
// keeps text: no control character and no `<`, which a label's AutoText
// would read as markup; FALLBACK for a name with nothing printable.
function choiceLabel(value, fallback) {
    const text = clip(String(value).replace(/[\u0080-\u009f\u2028\u2029]/g, ""), CHOICE_MAX).trim();
    return text === "" ? fallback : text;
}

// The networks of the list read: { state: "available", rows, active,
// activeWifi, count }. `rows` are the saved Wi-Fi profiles, the only ones
// a user can trust, [{ uuid, name, type, active }], the active ones first
// and at most NETWORK_MAX; `active` is the uuid of every activated
// connection that is not LOCAL_TYPES, and `activeWifi` of those that are
// Wi-Fi, each sorted. `unreadable` for a read that failed or a row outside
// the grammar, which decides nothing.
function networkList(code, text) {
    if (code !== 0) return emptyNetworks("unreadable");
    const rows = [];
    const active = [];
    const activeWifi = [];
    for (const raw of String(text).split(/\r?\n/)) {
        if (raw === "") continue;
        const fields = Commons.Nmcli.fields(raw);
        if (fields === null || fields.length !== 4) return emptyNetworks("unreadable");
        if (LOCAL_TYPES.indexOf(fields[2]) !== -1) continue;
        if (!UUID.test(fields[1]) || STATES.indexOf(fields[3]) === -1) return emptyNetworks("unreadable");
        const uuid = fields[1].toLowerCase();
        const up = fields[3] === "activated";
        if (up) active.push(uuid);
        if (fields[2] !== WIFI_TYPE) continue;
        if (up) activeWifi.push(uuid);
        rows.push({ uuid: uuid, name: choiceLabel(fields[0], "Wi-Fi"), type: "Wi-Fi", active: up });
    }
    const shown = rows.filter(row => row.active).concat(rows.filter(row => !row.active));
    return { state: "available", rows: shown.slice(0, NETWORK_MAX), active: active.sort(), activeWifi: activeWifi.sort(), count: rows.length };
}

// The choices of the Connect automatically select: Off, which stands for
// the empty setting, then each listed profile by uuid.
function vpnChoices(profiles) {
    const rows = isPlain(profiles) && profiles.state === "available" ? profiles.rows : [];
    return [{ label: "Off", value: "off" }].concat(rows.map(row => ({ label: choiceLabel(row.name, typeName(row.type, row.service)), value: row.uuid })));
}
// The choices of a Trusted networks item: each saved Wi-Fi profile by uuid.
function networkChoices(networks) {
    return isPlain(networks) && networks.state === "available" ? networks.rows.map(row => ({ label: row.name, value: row.uuid })) : [];
}

// The trusted networks' uuids from the `trustedNetworks` setting, a list
// of { name, network } items; an item with no network chosen yet trusts
// nothing. A saved uuid that is not a Wi-Fi profile trusts nothing either
// (autoConnectPlan).
function trustedUuids(items) {
    return (Array.isArray(items) ? items : []).filter(item => isPlain(item) && typeof item.network === "string" && UUID.test(item.network))
        .map(item => item.network.toLowerCase());
}
// The `trustedNetworks` setting with network UUID trusted when WANTED, or
// not. Every other item stays as it is; a new item takes the lowest whole
// number no item names, as the Settings page's list editor names one.
function trustedChange(items, uuid, wanted) {
    const list = Array.isArray(items) ? items.filter(isPlain) : [];
    const holds = item => typeof item.network === "string" && item.network.toLowerCase() === uuid;
    if (!wanted) return list.filter(item => !holds(item));
    if (list.some(holds)) return list;
    let n = 1;
    while (list.some(item => item.name === String(n))) n += 1;
    return list.concat([{ name: String(n), network: uuid }]);
}

// The decision's memory: `seen`, the active networks of the last readable
// list as one key, null before the first; `pending`, a network change not
// yet decided; `problem`, why the last decision connected nothing, or
// null: { kind: "unread" }, { kind: "gone" }, or for the chosen profile
// { kind: "refused", uuid, name, reason }, the reason its switch gave the
// last connect, which no decision keeps, or { kind: "failed", uuid, name,
// reason }, a connect that started and did not complete.
function autoConnectStart() { return { seen: null, pending: false, problem: null }; }

// One decision, at each list read, over MEMORY: CHOICE, the setting's
// profile uuid or ""; TRUSTED, trustedUuids; NETWORKS, networkList;
// PROFILES, the published profiles; BUSY while a profile change or a kill
// switch write runs, or before the kill switch step's first reading, which
// decides whether the connect writes the state file first. Answers { why,
// uuid, memory }: `uuid` the profile to connect, else "". A change of the
// active networks, the first readable list included, is decided once: it
// connects the chosen profile while an active network is not a trusted
// Wi-Fi profile and no VPN profile is up. A change the switch refused
// stays undecided (autoConnectReply), so the next read connects once its
// cause is gone. A deliberate off (autoConnectOff) leaves it decided until
// the next change. With no
// profile chosen, a change is decided as it comes, so choosing one later
// connects nothing until the next change. An unreadable list decides
// nothing and keeps its change pending.
function autoConnectPlan(memory, choice, trusted, networks, profiles, busy) {
    const wanted = typeof choice === "string" ? choice.toLowerCase() : "";
    const readable = isPlain(networks) && networks.state === "available" && isPlain(profiles) && profiles.state === "available";
    const key = readable ? networks.active.join(" ") : null;
    const plan = (why, next, uuid) => ({ why: why, uuid: uuid === undefined ? "" : uuid, memory: next });
    if (wanted === "") return plan("off", { seen: readable ? key : memory.seen, pending: false, problem: null });
    if (!readable) return plan("unread", { seen: memory.seen, pending: memory.pending, problem: { kind: "unread" } });
    const pending = memory.seen !== key || memory.pending;
    const row = profiles.rows.find(candidate => candidate.uuid === wanted);
    if (row === undefined) return plan("gone", { seen: key, pending: false, problem: { kind: "gone" } });
    // A failure of the chosen profile stays until a change is decided again
    // or the profile connects, and goes with the choice. A refusal is the
    // switch's answer to the last connect: only a wait, which decides
    // nothing, keeps it; the next connect asks again.
    const ours = isPlain(memory.problem) && memory.problem.uuid === wanted && row.state !== "activated";
    const failed = ours && memory.problem.kind === "failed" ? memory.problem : null;
    if (!pending) return plan("settled", { seen: key, pending: false, problem: failed });
    if (busy) return plan("waiting", { seen: key, pending: true, problem: ours ? memory.problem : null });
    const decided = { seen: key, pending: false, problem: null };
    if (profiles.rows.some(candidate => candidate.state === "activated" || candidate.state === "activating")) return plan("connected", decided);
    if (networks.active.length === 0) return plan("offline", decided);
    if (networks.active.every(uuid => networks.activeWifi.indexOf(uuid) !== -1 && trusted.indexOf(uuid) !== -1)) return plan("trusted", decided);
    return plan("connect", decided, row.uuid);
}
// The user turned a profile off: no network change is pending.
function autoConnectOff(memory) { return Object.assign({}, memory, { pending: false }); }

// The switch's refusals a user acts on: the profile, its plugin, its saved
// sign-in or the kill switch. Their reason is the problem line; any other
// refusal is a state that passes, such as a detail read or a change in
// flight, and shows none.
var USER_REFUSALS = ["kill-switch", "plugin-needed", "sign-in", "unsupported"];
// MEMORY after the connect autoConnectPlan asked for answered REPLY, the
// IPC action's: `ok` keeps it. Anything else, `busy` included, leaves the
// change undecided, so the next read asks again and connects once the
// cause is gone: the chosen profile connects, the user turns it off or the
// network changes first. A refusal of ROW a user acts on shows REASON, the
// one its switch shows (rowView), "" for none.
function autoConnectReply(memory, reply, row, reason) {
    if (reply === "ok") return memory;
    const found = /^refused: profile=([a-z-]+)$/.exec(String(reply));
    const shown = found !== null && USER_REFUSALS.indexOf(found[1]) !== -1;
    return Object.assign({}, memory, { pending: true, problem: shown ? { kind: "refused", uuid: row.uuid, name: row.name, reason: reason } : null });
}
// MEMORY after a connect it started failed later, at the kill switch or in
// nmcli: ROW's failure with TEXT, the problem line the change left.
function autoConnectFailed(memory, row, text) {
    return Object.assign({}, memory, { problem: { kind: "failed", uuid: row.uuid, name: row.name, reason: text } });
}
// The problem line under Connect automatically, "" for none.
function autoConnectText(problem) {
    if (!isPlain(problem)) return "";
    if (problem.kind === "unread") return "VGS could not read which networks this computer is on, so it did not connect a VPN.";
    if (problem.kind === "gone") return "The VPN profile chosen here is gone. Choose another profile.";
    const text = problem.kind === "failed" ? "VGS tried to connect " + problem.name + " automatically." : "VGS did not connect " + problem.name + " automatically.";
    const full = problem.reason === "" ? text : text + " " + problem.reason;
    return full.length > PROBLEM_MAX ? text : full;
}
