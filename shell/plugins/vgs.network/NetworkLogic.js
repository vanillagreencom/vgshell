.pragma library
.import qs.Commons 1.0 as Commons
// Pure decisions for Quickshell.Networking snapshots. Signal strength is
// Quickshell's share from zero to one, not NetworkManager's percentage.
// Enum toString() is localized display wording, not a stable identity.
function enumName(value, variants) {
    return Object.keys(variants).find(name => variants[name] === value) || "Unknown";
}

function strength(value) {
    return Number.isFinite(value) ? Math.round(Math.max(0, Math.min(1, value)) * 100) : 0;
}

function securityLabel(security) {
    const labels = {
        Wpa3SuiteB192: "WPA3 Enterprise", Sae: "WPA3", Wpa2Eap: "WPA2 Enterprise",
        Wpa2Psk: "WPA2", WpaEap: "WPA Enterprise", WpaPsk: "WPA",
        StaticWep: "WEP", DynamicWep: "WEP Enterprise", Leap: "LEAP",
        Owe: "Enhanced open", Open: "Open", Unknown: "Unknown security"
    };
    return Object.prototype.hasOwnProperty.call(labels, security) ? labels[security] : labels.Unknown;
}

function supportsPsk(security) {
    return security === "WpaPsk" || security === "Wpa2Psk" || security === "Sae";
}

function shareable(row) {
    return !!row && !!row.known && (supportsPsk(row.security) || row.security === "Open" || row.security === "Owe" || row.security === "StaticWep");
}

// A saved profile remains known after failed authentication. Retrying that
// profile repeats the failure. NoSecrets also prompts for a new network.
function shouldReprompt(reason, security, known) {
    return supportsPsk(security) && (reason === "NoSecrets"
        || (known && (reason === "WifiAuthTimeout" || reason === "WifiClientFailed")));
}

function ordered(rows) {
    return rows.slice().sort((a, b) => Number(b.connected) - Number(a.connected)
        || Number(b.known) - Number(a.known) || b.strength - a.strength
        || a.name.localeCompare(b.name) || a.key.localeCompare(b.key));
}

function serviceProbe(text, code) {
    if (code !== 0) return "unavailable";
    const fields = {};
    String(text).split(/\r?\n/).forEach(line => {
        const equal = line.indexOf("=");
        if (equal > 0) fields[line.slice(0, equal)] = line.slice(equal + 1);
    });
    if (fields.LoadState === "not-found") return "absent";
    if (fields.LoadState !== "loaded") return "unavailable";
    if (fields.ActiveState === "active") return "running";
    if (["inactive", "failed", "deactivating", "activating", "reloading"].indexOf(fields.ActiveState) >= 0) return "stopped";
    return "unavailable";
}

function permission(text, code) {
    if (code !== 0) return "unavailable";
    const lines = String(text).split(/\r?\n/);
    const prefix = "org.freedesktop.NetworkManager.network-control:";
    for (let i = 0; i < lines.length; i++) {
        if (lines[i].indexOf(prefix) !== 0) continue;
        const value = lines[i].slice(prefix.length);
        if (value === "yes") return "allowed";
        if (value === "no" || value === "auth") return "denied";
        return "unavailable";
    }
    return "unavailable";
}

function state(service, backend, managed, access, connected, connectivity, checks, wifiEnabled, hasWifi) {
    if (service === "absent" || service === "stopped") return service;
    if (service !== "running" || !backend) return "unavailable";
    if (access === "denied") return "denied";
    if (!managed) return "unmanaged";
    if (connected && checks && connectivity === "Portal") return "portal";
    if (connected && checks && connectivity === "Limited") return "limited";
    if (connected) return "connected";
    if (hasWifi && !wifiEnabled) return "radio-off";
    return "offline";
}

function stateText(value) {
    const words = {
        absent: "NetworkManager is not installed on this computer.",
        stopped: "NetworkManager is not running on this computer.",
        unmanaged: "NetworkManager does not manage this device.",
        denied: "NetworkManager denied access to network changes.",
        limited: "Connected with limited internet access.",
        portal: "Connected. This network needs a browser sign-in.",
        connected: "Connected", "radio-off": "Wi-Fi is off.",
        offline: "Not connected", unavailable: "Network status is unavailable."
    };
    return Object.prototype.hasOwnProperty.call(words, value) ? words[value] : words.unavailable;
}

// A wired device's state from NetworkManager's management, the device's
// connection and the physical link. A device with no link has no cable.
function ethernetState(managed, connected, link) {
    if (!managed) return "unmanaged";
    if (connected) return "connected";
    return link ? "disconnected" : "no-cable";
}

function ethernetText(state) {
    const words = { connected: "Connected", disconnected: "Not connected", "no-cable": "Cable not connected", unmanaged: "Not managed by NetworkManager" };
    return Object.prototype.hasOwnProperty.call(words, state) ? words[state] : words.disconnected;
}

function ethernetOrdered(rows) {
    return rows.slice().sort((a, b) => Number(b.state === "connected") - Number(a.state === "connected")
        || a.name.localeCompare(b.name));
}

// The line that names what the computer is connected through: the joined
// Wi-Fi network, else the first connected wired device, else the state.
function summary(network) {
    const joined = (network.wifi || []).find(row => row.connected);
    if (network.state === "connected" && joined) return "Connected to " + (joined.name === "" ? "a hidden network" : joined.name);
    const wired = (network.ethernet || []).find(row => row.state === "connected");
    if (network.state === "connected" && wired) return "Connected through " + wired.name;
    return stateText(network.state);
}

function writable(state) {
    return ["connected", "offline", "radio-off", "limited", "portal"].indexOf(state) >= 0;
}

// nmcli -t escapes backslashes and colons. Split only the first unescaped
// colon: IPv6 and other values can contain escaped colons of their own.
function details(text) {
    const rows = [];
    const shown = /^(GENERAL\.(DEVICE|TYPE|STATE|CONNECTION|HWADDR)|IP[46]\.(ADDRESS\[\d+\]|GATEWAY|DNS\[\d+\]))$/;
    String(text).split(/\r?\n/).forEach(line => {
        const columns = Commons.Nmcli.fields(line);
        const found = columns !== null && columns.length >= 2;
        const key = found ? columns[0] : "";
        const value = found ? columns.slice(1).join(":") : "";
        if (found && shown.test(key) && value !== "") rows.push({ key: key, value: value });
    });
    return rows;
}

// A terminal unsuccessful connect needs a short signal-delivery grace in
// the service, because credentials failures can follow the state change.
function operationResult(kind, connected, known, changing, observedChanging) {
    if ((kind === "connect" || kind === "psk") && connected) return "complete";
    if (kind === "disconnect" && !connected && !changing) return "complete";
    if (kind === "forget" && !known) return "complete";
    if (observedChanging && !changing && (kind === "connect" || kind === "psk")) return "terminal";
    return "pending";
}
