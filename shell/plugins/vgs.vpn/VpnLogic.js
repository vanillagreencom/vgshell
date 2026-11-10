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

var KINDS = ["profile-up", "profile-down", "profile-remove", "profile-details"];
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
// for an opened row's address read, or { refusal }. MEANT_ON is the
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
function armOutcome(status, uuid) {
    if (status === null) return "waiting";
    if (status.state === "unreachable" || status.state === "unreadable") return "failed";
    if (status.profile !== uuid) return "waiting";
    if (status.state === "holding" || status.state === "passing") return "armed";
    return status.state === "unavailable" ? "unavailable" : "waiting";
}

// Why the root half cannot use the profile, in a sentence, from its
// status reason. NAME is the profile's.
function unavailableWords(reason, name) {
    switch (reason) {
    case "profile-not-wireguard": return name + " is not a WireGuard profile, and the kill switch works only with WireGuard.";
    case "profile-missing": return "The VPN profile is gone.";
    case "endpoint-hostname": return name + " names its server by host name, and the kill switch needs an IP address.";
    case "endpoint-invalid": return name + "'s server address is not valid.";
    case "interface-invalid": return name + "'s network interface name is not valid.";
    case "profile-unread":
    case "cache-unreadable": return "The kill switch could not read " + name + ".";
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
