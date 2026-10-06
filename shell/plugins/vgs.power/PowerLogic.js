.pragma library

// Pure decisions for vgs.power: whether the display device is a laptop
// battery, the battery and profile view published as plugin status, icon
// bands, time text, profile mapping, low-battery latches and the profile
// to apply when the power source changes. QML owns UPower, PowerProfiles,
// settings writes, IPC and notify-send.

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

function profileName(value) {
    if (value === 0 || value === PROFILE.saver) return PROFILE.saver;
    if (value === 2 || value === PROFILE.performance) return PROFILE.performance;
    return PROFILE.balanced;
}

function profileFromBusctl(text) {
    try {
        return profileName(JSON.parse(String(text || "")).data);
    } catch (e) {
        var match = /'([^']+)'/.exec(String(text || ""));
        return match === null ? "" : profileName(match[1]);
    }
}

function profileEnum(name) {
    if (name === PROFILE.saver) return 0;
    if (name === PROFILE.performance) return 2;
    return 1;
}

function choices(hasPerformance) {
    var out = [PROFILE.saver, PROFILE.balanced];
    if (hasPerformance === true) out.push(PROFILE.performance);
    return out;
}

function validProfile(name) {
    return name === PROFILE.saver || name === PROFILE.balanced || name === PROFILE.performance;
}

function availableProfile(name, hasPerformance) {
    if (!validProfile(name)) return PROFILE.balanced;
    if (name === PROFILE.performance && hasPerformance !== true) return PROFILE.balanced;
    return name;
}

function profileView(available, active, hasPerformance) {
    return {
        available: available === true,
        active: profileName(active),
        choices: choices(hasPerformance)
    };
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

function profileForSource(onBattery, settings, hasPerformance) {
    var key = onBattery === true ? "batteryProfile" : "chargerProfile";
    var wanted = settings && hasOwn(settings, key) ? settings[key] : PROFILE.balanced;
    return availableProfile(wanted, hasPerformance);
}

function sourceObserved(previous, ready, onBattery) {
    var state = previous && typeof previous === "object" ? previous : { ready: false, onBattery: false };
    if (ready !== true) return { state: state, apply: false };
    if (state.ready !== true) return { state: { ready: true, onBattery: onBattery === true }, apply: false };
    if (state.onBattery === (onBattery === true)) return { state: state, apply: false };
    return { state: { ready: true, onBattery: onBattery === true }, apply: true };
}
