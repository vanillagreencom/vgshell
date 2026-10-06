.pragma library

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

function optionPath(options, key) {
    return options !== null && options !== undefined && typeof options === "object" ? options[key] : undefined;
}

function rowOverridden(paths, options, key) {
    var path = optionPath(options, key);
    return path !== undefined && overriddenMap(paths)[path] === true;
}

function overriddenText(paths, options, key) {
    return rowOverridden(paths, options, key) ? "Overridden by your Hyprland config" : "";
}

// The value the user's Hyprland configuration gave the option setting KEY
// maps to, from VALUES, the capability's `userValues`; undefined when it
// names no such option.
function userValue(values, options, key) {
    var path = optionPath(options, key);
    if (path === undefined || !Array.isArray(values)) return undefined;
    for (var i = 0; i < values.length; i++)
        if (values[i].path === path) return values[i].value;
    return undefined;
}

function hasUserValue(values, options, key) {
    return userValue(values, options, key) !== undefined;
}

// VALUE as the row of setting KEY shows it.
function valueText(key, value) {
    if (typeof value === "boolean") return value ? "on" : "off";
    if (typeof value === "number") return key === "sensitivity" ? pointerSpeedText(value) : factorText(value);
    return String(value);
}

// The line under a row: the user's own value where VGS replaced it, else
// the overridden line.
function warningText(paths, values, options, key) {
    var value = userValue(values, options, key);
    if (value !== undefined) return "Your Hyprland config sets this to " + valueText(key, value);
    return overriddenText(paths, options, key);
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
