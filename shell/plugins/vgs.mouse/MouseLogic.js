.pragma library

var OPTION_PATHS = {
    sensitivity: "input.sensitivity",
    accelProfile: "input.accel_profile",
    naturalScroll: "input.natural_scroll",
    leftHanded: "input.left_handed",
    scrollFactor: "input.scroll_factor",
    tapToClick: "input.touchpad.tap_to_click",
    touchpadNaturalScroll: "input.touchpad.natural_scroll",
    disableWhileTyping: "input.touchpad.disable_while_typing",
    clickMethod: "input.touchpad.clickfinger_behavior",
    touchpadScrollFactor: "input.touchpad.scroll_factor",
    touchpadEnabled: "device.touchpad.enabled"
};

function mice(devices) {
    if (devices === null || devices === undefined || !Array.isArray(devices.mice)) return [];
    return devices.mice.map(function (mouse) {
        return { name: String(mouse.name || ""), touchpad: mouse.touchpad === true };
    }).filter(function (mouse) { return mouse.name !== ""; });
}

function hasTouchpad(devices) {
    return mice(devices).some(function (mouse) { return mouse.touchpad; });
}

function deviceRows(devices) {
    return mice(devices).map(function (mouse) {
        return {
            key: mouse.name,
            text: mouse.name,
            secondary: mouse.touchpad ? "Touchpad" : "Pointer",
            icon: mouse.touchpad ? "touchpad" : "mouse",
            badge: mouse.touchpad ? "Touchpad" : "Pointer"
        };
    });
}

function statusValue(devices) {
    var rows = deviceRows(devices);
    return { hasTouchpad: hasTouchpad(devices), devices: rows };
}

function overriddenMap(paths) {
    var out = {};
    if (!Array.isArray(paths)) return out;
    for (var i = 0; i < paths.length; i++) out[paths[i]] = true;
    return out;
}

function rowOverridden(paths, key) {
    return overriddenMap(paths)[OPTION_PATHS[key]] === true;
}

function overriddenText(paths, key) {
    return rowOverridden(paths, key) ? "Overridden by your Hyprland config" : "";
}

function pointerSpeedText(value) {
    var n = Number(value);
    if (!isFinite(n)) n = 0;
    return (n > 0 ? "+" : "") + n.toFixed(2) + "×";
}

function factorText(value) {
    var n = Number(value);
    if (!isFinite(n)) n = 1;
    return n.toFixed(2) + "×";
}

function profileIndex(value) {
    return value === "flat" ? 1 : 0;
}

function profileAt(index) {
    return index === 1 ? "flat" : "adaptive";
}

function replyProblem(reply) {
    return /^(refused|unknown|error):/.test(String(reply));
}
