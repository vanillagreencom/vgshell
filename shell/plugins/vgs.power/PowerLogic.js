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
// the source never changes, so neither setting would ever act, and the
// Settings page draws neither field (the manifest's shownWhen).
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

function sourceObserved(previous, ready, onBattery) {
    var state = previous && typeof previous === "object" ? previous : { ready: false, onBattery: false };
    if (ready !== true) return { state: state, apply: false };
    if (state.ready !== true) return { state: { ready: true, onBattery: onBattery === true }, apply: false };
    if (state.onBattery === (onBattery === true)) return { state: state, apply: false };
    return { state: { ready: true, onBattery: onBattery === true }, apply: true };
}
