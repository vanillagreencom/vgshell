.pragma library
.import qs.Commons 1.0 as Commons
// NetworkManager profile decisions. Service.qml owns the effects.
var WATCHDOG_MS = 10000;
var OPEN_POLL_MS = 3000;
var ACTION_MS = 30000;
var TEXT_MAX = 64;
var TARGET_MAX = 253;

function pollInterval(open, idleSeconds) {
    return open ? OPEN_POLL_MS : idleSeconds * 1000;
}

function line(value) {
    var text = typeof value === "string" ? value.replace(/[\u0000-\u001f\u007f<]/g, "") : "";
    return text.length > TEXT_MAX ? text.slice(0, TEXT_MAX) : text;
}

function isPlain(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

var PROFILE_MAX = 32;
function emptyProfiles() { return { state: "unavailable", rows: [], count: 0, activeCount: 0 }; }

// nmcli's documented terse table is escaped, including the connection id.
// https://networkmanager.dev/docs/api/latest/nmcli.html
function profiles(code, text) {
    if (code !== 0) return emptyProfiles();
    const rows = [];
    const names = Object.create(null);
    for (const raw of String(text).split(/\r?\n/)) {
        if (raw === "") continue;
        const fields = Commons.Nmcli.fields(raw);
        if (fields === null || fields.length !== 3) return emptyProfiles();
        names[fields[0]] = (names[fields[0]] || 0) + 1;
        if (fields[1] !== "vpn" && fields[1] !== "wireguard") continue;
        if (fields[0] === "" || fields[0].length > TARGET_MAX) continue;
        rows.push({ id: fields[0], name: line(fields[0]), type: fields[1], active: fields[2] === "activated" });
    }
    // nmcli resolves id against every connection type, including rows the
    // view does not retain. The bar's active fact must survive both bounds.
    const activeCount = rows.filter(row => row.active).length;
    const retained = rows.slice(0, PROFILE_MAX);
    for (const row of retained) row.ambiguous = names[row.id] > 1;
    return { state: "available", rows: retained, count: rows.length, activeCount: activeCount };
}

function profileCommand(request, data) {
    if (!isPlain(request) || (request.kind !== "profile-up" && request.kind !== "profile-down"))
        return { refusal: "refused: profile=action" };
    if (data.state !== "available") return { refusal: "refused: profile=unavailable" };
    const matches = data.rows.filter(row => row.id === request.id);
    if (matches.length > 1) return { refusal: "refused: profile=ambiguous" };
    const row = matches[0];
    if (row === undefined) return { refusal: "refused: profile=absent" };
    if (row.ambiguous) return { refusal: "refused: profile=ambiguous" };
    if ((request.kind === "profile-down") !== row.active) return { refusal: "refused: profile=state" };
    return { argv: ["nmcli", "connection", request.kind === "profile-up" ? "up" : "down", "id", row.id] };
}

// No saved profile means there is no connection to control from the bar.
function barView(profiles) {
    if (!isPlain(profiles) || profiles.state !== "available" || profiles.count === 0)
        return { shown: false, icon: "shield-off", tooltip: "VPN" };
    return { shown: true, icon: profiles.activeCount > 0 ? "shield-check" : "shield-off",
        tooltip: profiles.activeCount > 0 ? "VPN: Connected" : "VPN: Off" };
}

function connection(missing, profiles) {
    if (missing) return { tone: "info", text: "NetworkManager is not installed." };
    if (profiles.state !== "available") return { tone: "info", text: "NetworkManager did not answer." };
    return { tone: profiles.activeCount > 0 ? "ok" : "info", text: profiles.activeCount > 0 ? "Connected" : "Off" };
}

// Leave room for the state line while keeping the source list unchanged.
var STATUS_DATA_BYTES = 32000;
function statusWrites(connectionLine, profileValue) {
    var profiles = Object.assign({}, profileValue, { rows: profileValue.rows.slice() });
    while (Commons.SettingValues.utf8Bytes(JSON.stringify(profiles)) > STATUS_DATA_BYTES) profiles.rows.pop();
    return [["connection", connectionLine], ["profiles", profiles]];
}
