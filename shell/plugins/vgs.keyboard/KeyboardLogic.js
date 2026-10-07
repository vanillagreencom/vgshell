.pragma library

// evdev.xml is the xkeyboard-config layout catalog. Only its layout and
// variant configItems are kept. Refuse oversized catalogs rather than
// publish a partial list as the complete set of input sources.
var XML_MAX = 1048576;
var DATA_MAX = 58000;
// The keyboard library supports four evdev groups. Offer only sources
// that the compositor can activate.
var SOURCE_MAX = 4;

function xmlText(value) {
    return value.replace(/&#(x[0-9a-f]+|[0-9]+);/gi, function (_, code) {
        return String.fromCodePoint(code[0].toLowerCase() === "x" ? parseInt(code.slice(1), 16) : parseInt(code, 10));
    }).replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, "&").trim();
}

function configItem(block) {
    var item = /<configItem\b[^>]*>([\s\S]*?)<\/configItem>/.exec(block);
    if (item === null) throw new Error("catalog=config-item");
    var code = /<name>([^<]+)<\/name>/.exec(item[1]);
    var name = /<description>([^<]+)<\/description>/.exec(item[1]);
    if (code === null || name === null) throw new Error("catalog=fields");
    return { code: xmlText(code[1]), name: xmlText(name[1]) };
}

function parseCatalog(xml) {
    if (xml.length > XML_MAX) throw new Error("catalog=source-bound");
    var list = /<layoutList>([\s\S]*?)<\/layoutList>/.exec(xml);
    if (list === null) throw new Error("catalog=layout-list");
    var layouts = [], layout, re = /<layout>([\s\S]*?)<\/layout>/g;
    while ((layout = re.exec(list[1])) !== null) {
        var row = configItem(layout[1]);
        row.variants = [];
        var variant, variants = /<variant>([\s\S]*?)<\/variant>/g;
        while ((variant = variants.exec(layout[1])) !== null) row.variants.push(configItem(variant[1]));
        layouts.push(row);
    }
    if (layouts.length === 0) throw new Error("catalog=empty");
    if (JSON.stringify(layouts).length > DATA_MAX) throw new Error("catalog=data-bound");
    return layouts;
}

function mainKeyboard(devices) {
    var rows = devices === null || devices === undefined ? [] : devices.keyboards;
    if (!Array.isArray(rows) || rows.length === 0) return null;
    return rows.find(function (row) { return row.main; }) || rows[0];
}

// Empty layouts means use the compositor's system value, never a US default.
function sources(layouts, variants, devices) {
    var keyboard = mainKeyboard(devices);
    var codes = (layouts === "" && keyboard !== null ? keyboard.layout : layouts).split(",");
    var names = (layouts === "" && keyboard !== null ? keyboard.variant : variants).split(",");
    return codes.filter(function (code) { return code.trim() !== ""; }).slice(0, SOURCE_MAX).map(function (code, index) {
        return { code: code.trim(), variant: (names[index] || "").trim() };
    });
}

function serialize(rows) {
    return { layouts: rows.map(function (row) { return row.code; }).join(","),
        variants: rows.map(function (row) { return row.variant; }).join(",") };
}

function addSource(rows, code, variant) {
    if (rows.some(function (row) { return row.code === code && row.variant === variant; })) return { ok: true, rows: rows };
    if (rows.length >= SOURCE_MAX) return { ok: false, reason: "source-limit" };
    return { ok: true, rows: rows.concat([{ code: code, variant: variant }]) };
}

function moveSource(rows, index, delta) {
    var target = index + delta;
    if (index < 0 || index >= rows.length || target < 0 || target >= rows.length) return rows;
    var next = rows.slice(), moved = next.splice(index, 1)[0];
    next.splice(target, 0, moved);
    return next;
}

function removeSource(rows, index) {
    if (rows.length <= 1 || index < 0 || index >= rows.length) return rows;
    return rows.filter(function (_, i) { return i !== index; });
}

function sourceRows(rows, catalog) {
    return rows.map(function (row, index) {
        var layout = catalog.find(function (entry) { return entry.code === row.code; });
        var variant = layout === undefined ? undefined : layout.variants.find(function (entry) { return entry.code === row.variant; });
        return { key: String(index), text: layout === undefined ? row.code : layout.name,
            secondary: row.variant === "" ? "Default" : variant === undefined ? row.variant : variant.name, iconName: "keyboard" };
    });
}

function layoutValue(devices, catalog, keyboardName, name, previous) {
    var keyboard = mainKeyboard(devices);
    if (keyboard === null || keyboard.name !== keyboardName) return previous;
    var rows = sources("", "", devices);
    var matches = rows.filter(function (source) {
        var layout = catalog.find(function (row) { return row.code === source.code; });
        if (layout === undefined) return false;
        var variant = layout.variants.find(function (row) { return row.code === source.variant; });
        return (source.variant === "" ? layout.name : variant === undefined ? "" : variant.name) === name;
    });
    // XKB uses "Mara" for both mm:mara and in:mara. An event names no
    // group index, so distinct matching codes must wait for devices.
    if (matches.length === 0 || matches.some(function (source) { return source.code !== matches[0].code; })) return null;
    return reconcileEvent(devices, { keyboard: keyboardName, layouts: keyboard.layout, variants: keyboard.variant,
        code: matches[0].code.toUpperCase(), name: name });
}

function reconcileEvent(devices, event) {
    if (event === null) return null;
    var keyboard = mainKeyboard(devices);
    if (keyboard === null || event.keyboard !== keyboard.name || event.layouts !== keyboard.layout || event.variants !== keyboard.variant)
        return null;
    var code = (keyboard.layout.split(",").slice(0, SOURCE_MAX)[keyboard.activeLayoutIndex] || "").toUpperCase();
    if (code === event.code && keyboard.activeKeymap === event.name) return null;
    return event;
}

function activeValue(devices, event) {
    var keyboard = mainKeyboard(devices);
    if (keyboard === null) return { code: "", name: "", count: 0 };
    var codes = keyboard.layout.split(",").slice(0, SOURCE_MAX);
    // A layout event precedes the asynchronous devices read. Its code and
    // name must stay together until that read catches up. A changed source
    // list or main keyboard invalidates the event's source identity.
    event = reconcileEvent(devices, event);
    if (event !== null) return { code: event.code, name: event.name, count: codes.length };
    return { code: (codes[keyboard.activeLayoutIndex] || "").toUpperCase(), name: keyboard.activeKeymap, count: codes.length };
}
