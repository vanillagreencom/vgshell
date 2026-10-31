.pragma library

// Pure decisions for vgs.power: whether the display device is a laptop
// battery, the battery and profile view published as plugin status, icon
// bands, time text, profile mapping, low-battery latches, the profile
// to apply when the power source changes, the setting a bar pick
// remembers, Wake on LAN's value, connection list and write rule, and the
// power menu's availability reads, offers and confirmation hold.
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

function isPrepareForSleepResume(line) {
    return typeof line === "string"
        && line === "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (false,)";
}

// logind's Can methods return a string. Only yes authorizes an unattended
// request; challenge needs an interactive authorization dialog.
// https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.login1.html
function sleepAllowed(code, text) {
    return code === 0 && /^\('yes',\)\s*$/.test(String(text));
}

var SLEEP_ACTIONS = [
    { value: "suspend", label: "Suspend", method: "Suspend" },
    { value: "hibernate", label: "Hibernate", method: "Hibernate" },
    { value: "suspend-then-hibernate", label: "Suspend then hibernate", method: "SuspendThenHibernate" }
];

function sleepChoices(allowed) {
    return SLEEP_ACTIONS.filter(function (action) { return allowed[action.value] === true; })
        .map(function (action) { return { value: action.value, label: action.label }; });
}

function sleepMethod(action, allowed) {
    var entry = SLEEP_ACTIONS.find(function (entry) { return entry.value === action; });
    return entry !== undefined && allowed[action] === true ? entry.method : "";
}

// The power menu's actions in menu order. Each id is a verb of
// `vgshell power`, which the service runs as its one route.
var POWER_ACTIONS = [
    { id: "logout", label: "Log out", icon: "log-out", failed: "Could not log out" },
    { id: "suspend", label: "Suspend", icon: "moon", failed: "Could not suspend" },
    { id: "hibernate", label: "Hibernate", icon: "snowflake", failed: "Could not hibernate" },
    { id: "reboot", label: "Reboot", icon: "rotate-ccw", failed: "Could not reboot" },
    { id: "poweroff", label: "Shut down", icon: "power-off", failed: "Could not shut down" },
    { id: "switch-user", label: "Switch user", icon: "users", failed: "Could not switch user" }
];

// The notice for an action that did not run: `busy` while another run
// holds the route, `unavailable` for an action not offered, `failed` for a
// run of the route that failed.
function actionFailurePayload(id, kind) {
    var action = POWER_ACTIONS.find(function (entry) { return entry.id === id; });
    var messages = {
        busy: "Another power action is running. Wait for it to finish.",
        unavailable: "This action is not available on this computer now.",
        failed: "VGS could not finish this action. Try again."
    };
    if (!hasOwn(messages, kind)) throw new Error("power: action failure kind=" + kind);
    return {
        title: action === undefined ? "Could not run the power action" : action.failed,
        message: messages[kind],
        tone: "danger",
        icon: "circle-alert"
    };
}

var LOGIND = ["--system", "--dest", "org.freedesktop.login1", "--object-path", "/org/freedesktop/login1"];

// The gdbus call arguments of one availability pass, each with the key
// its answer sets and the judge that reads it. logind's Can methods
// answer for the sleep actions, reboot and power off. Log out needs the
// user's graphical session, logind's User.Display, the property
// `vgshell power logout` ends; user/self names the caller's user, and a
// shell that uwsm runs in the user manager is that user's too:
// https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.login1.html
// Switch user needs LightDM's seat, which XDG_SEAT_PATH names, to answer
// CanSwitch true; with no seat path there is nothing to ask.
// https://github.com/canonical/lightdm/blob/e06f2aed1317c82312bd45ed8af027c348933f11/src/display-manager-service.c#L410-L420
function availabilityReads(seatPath) {
    var reads = SLEEP_ACTIONS.concat([{ value: "reboot", method: "Reboot" }, { value: "poweroff", method: "PowerOff" }])
        .map(function (entry) {
            return { key: entry.value, judge: "can", args: LOGIND.concat(["--method", "org.freedesktop.login1.Manager.Can" + entry.method]) };
        });
    reads.push({ key: "logout", judge: "session", args: ["--system", "--dest", "org.freedesktop.login1",
        "--object-path", "/org/freedesktop/login1/user/self",
        "--method", "org.freedesktop.DBus.Properties.Get", "org.freedesktop.login1.User", "Display"] });
    if (/^(\/[A-Za-z0-9_]+)+$/.test(String(seatPath)))
        reads.push({ key: "switch-user", judge: "true", args: ["--system", "--dest", "org.freedesktop.DisplayManager",
            "--object-path", seatPath,
            "--method", "org.freedesktop.DBus.Properties.Get", "org.freedesktop.DisplayManager.Seat", "CanSwitch"] });
    return reads;
}

// Whether one read's reply offers its action. gdbus prints a Get reply
// as the variant it holds, `(<value>,)`; Display is a (so) pair whose
// empty id, with object path /, means no graphical session.
function readAnswer(judge, code, text) {
    if (judge === "can") return sleepAllowed(code, text);
    if (judge === "session") return code === 0 && /^\(<\('[^']+', objectpath '[^']+'\)>,\)\s*$/.test(String(text));
    if (judge === "true") return code === 0 && /^\(<true>,\)\s*$/.test(String(text));
    throw new Error("power: read judge=" + judge);
}

// The menu's published reading: `checking` before the first pass ends,
// `failed` when no read of the last pass answered, else `ready` with the
// offered action ids in menu order.
function actionsView(passes, answered, allowed) {
    if (passes === 0) return { state: "checking", offered: [] };
    if (!answered) return { state: "failed", offered: [] };
    return { state: "ready", offered: POWER_ACTIONS.filter(function (action) { return allowed[action.id] === true; })
        .map(function (action) { return action.id; }) };
}

// The confirmation hold of the power menu. An action fires only after
// HOLD_MS of one continuous hold: a press of a source, a key or the
// pointer, on the selected offered action. Its phases:
//   idle      nothing held; a fresh press with an action starts a hold.
//   holding   { action, source, start }: one source held since `start`.
//   spent     { held, fired }: a hold that fired or was cancelled while
//             the sources in `held` stayed down; nothing starts again
//             until every one is released, so holds never chain.
// `now` is a monotonic reading in milliseconds; the caller supplies it.
var HOLD_MS = 3000;

function holdIdle() {
    return { phase: "idle" };
}

function holdPress(hold, source, action, now) {
    if (hold.phase === "idle")
        return action === "" ? hold : { phase: "holding", action: action, source: source, start: now };
    if (hold.phase === "holding")
        return source === hold.source ? hold : { phase: "spent", held: [hold.source, source], fired: false };
    if (hold.phase === "spent")
        return hold.held.indexOf(source) !== -1 ? hold : { phase: "spent", held: hold.held.concat([source]), fired: hold.fired };
    throw new Error("power: hold phase=" + hold.phase);
}

function holdRelease(hold, source) {
    if (hold.phase === "idle") return hold;
    if (hold.phase === "holding") return source === hold.source ? holdIdle() : hold;
    if (hold.phase === "spent") {
        var held = hold.held.filter(function (s) { return s !== source; });
        return held.length === 0 ? holdIdle() : { phase: "spent", held: held, fired: hold.fired };
    }
    throw new Error("power: hold phase=" + hold.phase);
}

// A cancel keeps the held source, which must be released before a fresh
// hold, and clears a fired hold's full fill, as after a refusal.
function holdCancel(hold) {
    if (hold.phase === "holding") return { phase: "spent", held: [hold.source], fired: false };
    if (hold.phase === "spent") return { phase: "spent", held: hold.held, fired: false };
    return hold;
}

// The milliseconds left before a hold is due, 0 once it is, -1 with no
// hold.
function holdRemaining(hold, now) {
    return hold.phase === "holding" ? Math.max(0, hold.start + HOLD_MS - now) : -1;
}

// A due hold fires once: the action to request, and the spent hold that
// keeps its source down.
function holdFire(hold, now) {
    if (holdRemaining(hold, now) !== 0) return { hold: hold, fire: "" };
    return { hold: { phase: "spent", held: [hold.source], fired: true }, fire: hold.action };
}

// The fill, 0 to 1, linear in the time held.
function holdProgress(hold, now) {
    if (hold.phase === "holding") return Math.min(1, Math.max(0, (now - hold.start) / HOLD_MS));
    return hold.phase === "spent" && hold.fired ? 1 : 0;
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
// devices, the setting the last pass wrote, and whether a pass has ever
// started from the user's choice, restored from the plugin's settings.
function wakeInitial(chosen) {
    return { present: false, wired: "", written: false, chosen: chosen === true };
}

// Whether a Wake on LAN reading starts a pass over the wired connections.
// VGS writes no connection until the user sets the switch, so a value set
// outside VGS stays. A pass runs while a wired device is present, when the
// setting differs from the one the last pass wrote, which holds a change
// made while no device was present until one is. Once chosen, either
// value is reapplied when wired devices change, since NetworkManager adds
// a connection for a device that appears or connects with none. The saved
// marker keeps a chosen Off distinct from the untouched default at restart.
function wakeObserved(previous, present, on, wired) {
    var reading = { present: present === true, on: on === true, wired: String(wired) };
    var moved = previous.present !== reading.present || previous.wired !== reading.wired;
    var write = reading.present && (reading.on !== previous.written || (previous.chosen && moved));
    return { state: { present: reading.present, wired: reading.wired, written: write ? reading.on : previous.written,
        chosen: previous.chosen || write }, write: write };
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
        hint: step.state === "absent" ? "No connected USB device supports wake from sleep"
            : step.state === "denied" ? "USB wake setup is not permitted on this computer"
            : "VGS could not read USB wake settings" };
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
