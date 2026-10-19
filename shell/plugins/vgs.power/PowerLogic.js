.pragma library

// Pure decisions for vgs.power: whether the display device is a laptop
// battery, the battery and profile view published as plugin status, icon
// bands, time text, profile mapping, low-battery latches, the profile
// to apply when the power source changes and the setting a bar pick
// remembers. QML owns UPower, the gdbus runs
// that reach the power profiles daemon, settings writes, IPC and notices.

var PROFILE = {
    saver: "power-saver",
    balanced: "balanced",
    performance: "performance"
};

var STATE = {
    Unknown: 0,
    Charging: 1,
    Discharging: 2,
    Empty: 3,
    FullyCharged: 4,
    PendingCharge: 5,
    PendingDischarge: 6
};

function hasOwn(object, key) {
    return object !== null && typeof object === "object" && Object.prototype.hasOwnProperty.call(object, key);
}

function levelOf(device) {
    if (device === null || device === undefined) return 0;
    return Math.max(0, Math.min(100, Math.round(Number(device.percentage || 0) * 100)));
}

function batteryPresent(device) {
    return !!(device && device.isPresent === true && device.isLaptopBattery === true);
}

function stateName(state) {
    switch (state) {
    case STATE.Charging: return "charging";
    case STATE.Discharging: return "discharging";
    case STATE.Empty: return "empty";
    case STATE.FullyCharged: return "fully-charged";
    case STATE.PendingCharge: return "pending-charge";
    case STATE.PendingDischarge: return "pending-discharge";
    default: return "unknown";
    }
}

function charging(device, onBattery) {
    if (!batteryPresent(device)) return false;
    return onBattery !== true && device.state === STATE.Charging;
}

function batteryView(device, onBattery) {
    var present = batteryPresent(device);
    return {
        present: present,
        level: present ? levelOf(device) : 0,
        charging: present ? charging(device, onBattery) : false,
        state: present ? stateName(device.state) : "absent",
        secondsToEmpty: present ? Math.max(0, Math.round(Number(device.timeToEmpty || 0))) : 0,
        secondsToFull: present ? Math.max(0, Math.round(Number(device.timeToFull || 0))) : 0
    };
}

function validProfile(name) {
    return name === PROFILE.saver || name === PROFILE.balanced || name === PROFILE.performance;
}

function availableProfile(name, choices) {
    return choices.indexOf(name) === -1 ? PROFILE.balanced : name;
}

// The profile view from TEXT, the daemon's reply to Properties.GetAll as
// gdbus prints it, GVariant text such as
// ({'ActiveProfile': <'balanced'>, 'Profiles': <[{'Profile': <'power-saver'>, 'Driver': <'x'>}, ...]>, ...},).
// The choices are the daemon's Profiles in its order, less a name outside
// the three its interface defines. Profiles are available while the active
// one is among them; any other text, an empty one for a failed read
// included, is the unavailable view.
function profileView(text) {
    var source = String(text || "");
    var active = /'ActiveProfile': <'([^']*)'>/.exec(source);
    var list = /'Profiles': <\[(.*?)\]>/.exec(source);
    var choices = [];
    var entry = /'Profile': <'([^']*)'>/g;
    var found;
    while (list !== null && (found = entry.exec(list[1])) !== null)
        if (validProfile(found[1]) && choices.indexOf(found[1]) === -1) choices.push(found[1]);
    if (active === null || choices.indexOf(active[1]) === -1)
        return { available: false, active: PROFILE.balanced, choices: [] };
    return { available: true, active: active[1], choices: choices };
}

// VIEW with NAME as its active profile.
function profileMarked(view, name) {
    return { available: view.available, active: name, choices: view.choices };
}

function batteryIcon(level, isCharging) {
    if (isCharging) return "battery-charging";
    if (level <= 10) return "battery-warning";
    if (level < 35) return "battery-low";
    if (level < 80) return "battery-medium";
    return "battery-full";
}

function profileIcon(profile) {
    if (profile === PROFILE.saver) return "leaf";
    if (profile === PROFILE.performance) return "zap";
    return "gauge";
}

function profileLabel(profile) {
    if (profile === PROFILE.saver) return "Power saver";
    if (profile === PROFILE.performance) return "Performance";
    return "Balanced";
}

function stateLabel(battery) {
    if (!battery || battery.present !== true) return "No battery";
    if (battery.state === "fully-charged") return "Fully charged";
    if (battery.charging) return "Charging";
    if (battery.state === "discharging") return "On battery";
    if (battery.state === "pending-charge") return "Plugged in, not charging";
    return "Battery present";
}

function timeText(battery) {
    if (!battery || battery.present !== true) return "";
    if (battery.state === "discharging") return durationText(battery.secondsToEmpty, "left");
    if (battery.charging) return durationText(battery.secondsToFull, "to full");
    return "";
}

function durationText(seconds, suffix) {
    var total = Math.max(0, Math.round(Number(seconds || 0)));
    if (total <= 0) return "";
    var minutes = Math.round(total / 60);
    if (minutes <= 0) return "";
    var hours = Math.floor(minutes / 60);
    var rest = minutes % 60;
    var text = hours > 0 ? hours + " h" + (rest > 0 ? " " + rest + " min" : "") : rest + " min";
    return text + " " + suffix;
}

function widgetView(power) {
    var battery = power && power.battery ? power.battery : { present: false };
    var profile = power && power.profile ? power.profile : { available: false, active: PROFILE.balanced };
    var parts = [];
    if (battery.present === true) parts.push(String(battery.level) + "% " + stateLabel(battery));
    if (profile.available === true) parts.push(profileLabel(profile.active));
    return {
        shown: battery.present === true || profile.available === true,
        batteryShown: battery.present === true,
        profileShown: profile.available === true,
        batteryIcon: batteryIcon(Number(battery.level || 0), battery.charging === true),
        profileIcon: profileIcon(profile.active),
        levelText: String(Number(battery.level || 0)) + "%",
        tooltip: parts.join(" · ")
    };
}

function latchInitial() {
    return { low: false, critical: false };
}

function notices(previous, level, discharging, lowThreshold, criticalThreshold) {
    var latch = previous && typeof previous === "object" ? previous : latchInitial();
    var next = { low: latch.low === true, critical: latch.critical === true };
    var out = [];
    var low = Math.max(0, Math.round(Number(lowThreshold)));
    var critical = Math.max(0, Math.round(Number(criticalThreshold)));
    var n = Math.max(0, Math.round(Number(level)));
    if (discharging !== true) return { notices: out, latch: latchInitial() };
    if (n <= critical) {
        if (!next.critical) out.push({ threshold: "critical", urgency: "critical", level: n });
        next.critical = true;
        next.low = true;
    } else if (n <= low) {
        if (!next.low) out.push({ threshold: "low", urgency: "normal", level: n });
        next.low = true;
    }
    return { notices: out, latch: next };
}

// What the notify capability sends for one of notices(): the low notice
// is a warning and the critical one danger, each titled by its state, so
// the two cards differ by the tone their icon draws in and by the title.
function noticePayload(notice) {
    var critical = notice.threshold === "critical";
    return {
        title: critical ? "Battery critical" : "Battery low",
        message: "Battery is down to " + notice.level + "%",
        tone: critical ? "danger" : "warning",
        icon: critical ? "battery-warning" : "battery-low",
        urgency: notice.urgency
    };
}

// The setting a bar pick of a profile writes, so the next change of the
// power source applies that pick again: the current source's profile
// while a battery is present, and "" with no battery. Without a battery
// a source change applies no profile (sourceObserved), so neither
// setting would ever act, and the Settings page draws neither field (the
// manifest's shownWhen).
function rememberedSetting(batteryPresent, onBattery) {
    if (batteryPresent !== true) return "";
    return onBattery === true ? "batteryProfile" : "chargerProfile";
}

// The Details line that says how Power sets the profile on this machine:
// with a battery it follows the power source, without one it keeps the
// one profile chosen from the bar. Settings draws a text value on one
// elided line with no link, so it stays short and plain.
function profileRuleText(batteryPresent) {
    return batteryPresent === true
        ? "Power sets it when you connect or disconnect power"
        : "Power sets one profile from the bar";
}

function profileForSource(onBattery, settings, choices) {
    var key = onBattery === true ? "batteryProfile" : "chargerProfile";
    var wanted = settings && hasOwn(settings, key) ? settings[key] : PROFILE.balanced;
    return availableProfile(wanted, choices);
}

// Whether a power source reading applies the new source's profile. The
// first ready reading only records the source. A later change applies
// only while a laptop battery is present: UPower also changes OnBattery
// when a UPS is the display device (upower's up-daemon.c), and with no
// battery Settings draws neither source field and a bar pick remembers
// neither, so the bar pick stands.
function sourceObserved(previous, ready, onBattery, batteryPresent) {
    var state = previous && typeof previous === "object" ? previous : { ready: false, onBattery: false };
    if (ready !== true) return { state: state, apply: false };
    if (state.ready !== true) return { state: { ready: true, onBattery: onBattery === true }, apply: false };
    if (state.onBattery === (onBattery === true)) return { state: state, apply: false };
    return { state: { ready: true, onBattery: onBattery === true }, apply: batteryPresent === true };
}

// BlueZ 5.87 exposes WakeAllowed only when the device supports wake
// (src/device.c, dev_property_wake_allowed_exist). GetAll also supplies
// Class/Appearance, which Quickshell 0.3.1 does not expose. Icon alone
// loses the combined keyboard/pointing class (src/dbus-common.c).
function bluetoothWakeReading(code, text) {
    if (code !== 0) return { state: "failed", reason: "read-failed" };
    // Remove string values before looking for primitive top-level fields.
    // Device-provided names and nested service data cannot become fields.
    var source = String(text).replace(/'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"/g, function (token) {
        return /^'(?:WakeAllowed|Class|Appearance)'$/.test(token) ? token : "''";
    });
    if (!/^\(\{[\s\S]*\},\)\s*$/.test(source)) return { state: "failed", reason: "read-invalid" };
    var fields = {}, depth = 0, match;
    var tokens = /[{}]|'(WakeAllowed|Class|Appearance)': <([^<>]*)>/g;
    while ((match = tokens.exec(source)) !== null) {
        if (match[0] === "{") depth++;
        else if (match[0] === "}") depth--;
        else if (depth === 1) fields[match[1]] = match[2];
    }
    if (!hasOwn(fields, "WakeAllowed")) return { state: "unsupported" };
    if (fields.WakeAllowed !== "true" && fields.WakeAllowed !== "false") return { state: "failed", reason: "read-invalid" };
    var kind = hasOwn(fields, "Class") ? /^(?:uint32 )?(\d+)$/.exec(fields.Class) : null;
    var appearance = hasOwn(fields, "Appearance") ? /^(?:uint16 )?(\d+)$/.exec(fields.Appearance) : null;
    if ((hasOwn(fields, "Class") && kind === null) || (hasOwn(fields, "Appearance") && appearance === null))
        return { state: "failed", reason: "read-invalid" };
    var deviceClass = kind === null ? 0 : Number(kind[1]);
    var look = appearance === null ? 0 : Number(appearance[1]);
    var allowed = deviceClass !== 0 ? (deviceClass & 0x1f00) === 0x0500 && (deviceClass & 0xc0) !== 0
        : (look & 0xffc0) === 0x03c0 && [1, 2, 5, 7, 9].indexOf(look & 0x3f) !== -1;
    return { state: "supported", current: fields.WakeAllowed === "true", allowed: allowed };
}

function wakeSourcesValue(step, bluetooth) {
    if (!step) return null;
    if (step.state === "needed" || step.state === "nixos")
        return { tone: "info", text: "Setup needed", action: true };
    if (step.state !== "ready") return { tone: "info", text: "Not available", available: false,
        hint: "VGS could not check wake permissions (" + step.reason + ")." };
    if (bluetooth.state === "failed") return { tone: "info", text: "Not available", available: false,
        hint: bluetooth.reason === "permission-denied" ? "The Bluetooth service denied permission to change wake sources."
            : bluetooth.reason === "write-failed" ? "The Bluetooth service could not change wake permission."
            : "VGS could not read Bluetooth wake permission." };
    return { tone: bluetooth.state === "ready" ? "ok" : "info", text: bluetooth.state === "ready" ? "Ready" : "Checking" };
}

function bluetoothWakeFailure(reason, stderr) {
    // dbus-daemon's denied Set and BlueZ's explicit authorization refusal
    // are permission failures, never a reason to run the root setup again.
    var permissionErrors = ["org.freedesktop.DBus.Error.AccessDenied", "org.bluez.Error.NotAuthorized"];
    return { state: "failed", reason: permissionErrors.some(function (name) { return String(stderr).indexOf(name) !== -1; })
        ? "permission-denied" : reason };
}
