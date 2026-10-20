.pragma library

// Pure decisions for vgs.power: whether the display device is a laptop
// battery, the battery and profile view published as plugin status, icon
// bands, time text, profile mapping, low-battery latches, the profile
// to apply when the power source changes, the setting a bar pick
// remembers, and Wake on LAN's value, connection list and write rule.
// QML owns UPower, the gdbus and nmcli runs that reach the power profiles
// daemon and NetworkManager, settings writes, IPC and notices.

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

// Wake on LAN as NetworkManager's 802-3-ethernet.wake-on-lan flags. Off is
// `none`: NetworkManager applies it as an ethtool call with no wake option,
// which turns Wake on LAN off, while `ignore` makes no call and leaves the
// network card armed. nmcli takes `none` and prints it back as `none`
// (wake_on_lan_enable in src/core/devices/nm-device-ethernet.c,
// nmp_ethtool_ioctl_set_wake_on_lan in src/libnm-platform/nmp-ethtool-ioctl.c
// and the wake-on-lan entry of src/libnmc-setting/nm-meta-setting-desc.c,
// NetworkManager 1.58.1).
var WAKE = {
    on: "magic",
    off: "none"
};

function wakeTarget(on) {
    return on === true ? WAKE.on : WAKE.off;
}

// The UUIDs of the wired connections in nmcli's terse UUID,TYPE table.
// nmcli escapes a colon inside a field; a UUID and a connection type hold
// none, so each line splits on its one colon.
function wiredConnections(text) {
    return String(text).split("\n").map(function (line) { return line.split(":"); })
        .filter(function (fields) { return fields.length === 2 && fields[0] !== "" && fields[1] === "802-3-ethernet"; })
        .map(function (fields) { return fields[0]; });
}

// The state between Wake on LAN readings: the last reading's wired
// devices, and the setting the last pass wrote, false before any pass.
function wakeInitial() {
    return { present: false, wired: "", written: false };
}

// Whether a Wake on LAN reading starts a pass over the wired connections.
// VGS writes no connection until the user sets the switch, so a value set
// outside VGS stays. A pass runs while a wired device is present, when the
// setting differs from the one the last pass wrote, which holds a change
// made while no device was present until one is, and, while the setting
// is on, when the wired devices change, since NetworkManager adds a
// connection for a device that appears or connects with none. Before any
// pass, written reads off, so the first pass runs once the setting is on;
// the setting cannot tell an off the user chose from the default, so after a
// restart a connection added while off is not written.
function wakeObserved(previous, present, on, wired) {
    var reading = { present: present === true, on: on === true, wired: String(wired) };
    var moved = previous.present !== reading.present || previous.wired !== reading.wired;
    var write = reading.present && (reading.on !== previous.written || (reading.on && moved));
    return { state: { present: reading.present, wired: reading.wired, written: write ? reading.on : previous.written }, write: write };
}

// What the Wake on LAN field says after a pass that failed at `failure`:
// listing the connections, reading one or writing one, with the step that
// starts a new pass from where the switch is now (`on`); "" for none.
function wakeProblemText(failure, on) {
    if (failure === "") return "";
    var retry = on === true ? " Turn Wake on LAN off and on to try again." : " Turn Wake on LAN on and off to try again.";
    if (failure === "list") return "VGS could not read the wired connections." + retry;
    if (failure === "read") return "VGS could not read Wake on LAN on a wired connection." + retry;
    if (failure === "write") return "VGS could not save Wake on LAN on a wired connection." + retry;
    throw new Error("wakeProblemText: failure " + JSON.stringify(failure) + " has no text");
}
