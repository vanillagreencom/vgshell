.pragma library

// Pure decisions about the token table and the shell document. No QML
// objects, no I/O, so scripts/test-theme-logic.js runs every function under
// node. The table is an argument of every function: this file and
// Tokens.js hold no import of each other.
//
// A resolved value is portable: a colour is the string `#rrggbbaa`, lower
// case with alpha last, and every other value is a JSON number, boolean or
// string. Theme.qml converts a colour once; no colour string reaches a QML
// property, because Qt reads eight digits with alpha first.

var SCHEMA_VERSION = 1;

// Every key a shell document may carry. An unknown key is refused.
var DOCUMENT_KEYS = ["schemaVersion", "name", "displayName", "tokens", "backgrounds"];

// The types a token may declare.
var TYPES = ["color", "length", "body-lines", "number", "duration", "family", "weight", "flag", "easing", "choice"];

// Types whose value is a number. A numeric literal takes the type of the
// token it is written for.
var NUMERIC_TYPES = ["length", "body-lines", "number", "duration", "weight"];

// The range of each numeric type that has one range for every token. A
// `number` token declares its own.
var RANGES = { length: [0, 4096], "body-lines": [1, 4096], duration: [0, 10000], weight: [100, 900] };

// Types whose resolved value is rounded to a whole number.
var WHOLE_TYPES = ["length", "duration", "weight"];

// The number every published `duration` is multiplied by once, after every
// expression resolved in unscaled milliseconds, so a theme that states its
// own timing still goes still at 0 and a duration that references another
// is not scaled twice. The range of a duration applies before the scale.
// The table must hold it as a `number`.
var MOTION_SCALE = "motion.scale";

// The curves an `easing` token may name. Theme.qml maps each to its QML
// enumerator.
var EASINGS = ["linear", "inQuad", "outQuad", "inOutQuad", "inCubic", "outCubic", "inOutCubic", "outQuart", "outQuint", "outExpo", "outBack"];

// Bounds on one expression, so a document cannot hold the shell in a parse.
var MAX_EXPRESSION_LENGTH = 256;
var MAX_EXPRESSION_DEPTH = 8;

var NAME_PATTERN = /^[a-z][A-Za-z0-9]*$/;
var REFERENCE_PATTERN = /^\{([A-Za-z0-9.]*)\}$/;

// Each function's argument types and result. `same` is the type of the
// token the expression is written for.
var FUNCTIONS = {
    mix: { args: ["color", "color", "number"], result: "color" },
    contrastMix: { args: ["color", "color", "color", "number"], result: "color" },
    alpha: { args: ["color", "number"], result: "color" },
    contrast: { args: ["color"], result: "color" },
    readable: { args: ["color", "color", "color"], result: "color" },
    discernible: { args: ["color", "color", "color"], result: "color" },
    mul: { args: ["same", "number"], result: "same" }
};

function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function hasOwn(obj, key) {
    return Object.prototype.hasOwnProperty.call(obj, key);
}

// A leaf of the table holds a type name and a default expression; every
// other object is a group.
function isLeaf(node) {
    return isPlainObject(node) && typeof node.type === "string" && hasOwn(node, "value");
}

// One refusal. `token` is "" for a defect of the document as a whole.
function refusal(reason, token, detail) {
    return { ok: false, reason: reason, token: token, detail: detail === undefined ? "" : String(detail) };
}

// The first line a refusal is logged with; the key and the token lead.
function refusalLine(refused) {
    var subject = refused.token === "" ? "document" : "token=" + refused.token;
    return "theme: refused: " + subject + " reason=" + refused.reason + (refused.detail === "" ? "" : " " + refused.detail);
}

// Every leaf of the table as { path, leaf }, in the table's order.
function leaves(tokens) {
    var out = [];
    var walk = function (node, path) {
        var keys = Object.keys(node);
        for (var i = 0; i < keys.length; i++) {
            var child = node[keys[i]];
            var at = path === "" ? keys[i] : path + "." + keys[i];
            if (isLeaf(child))
                out.push({ path: at, leaf: child });
            else
                walk(child, at);
        }
    };
    walk(tokens, "");
    return out;
}

// The leaf or group at a dotted path, or undefined.
function nodeAt(tokens, path) {
    var node = tokens;
    var parts = path.split(".");
    for (var i = 0; i < parts.length; i++) {
        if (!isPlainObject(node) || isLeaf(node) || !hasOwn(node, parts[i]))
            return undefined;
        node = node[parts[i]];
    }
    return node;
}

// The first defect of the table itself, or "". The table is a tree of
// groups whose names match NAME_PATTERN; a leaf declares a type in TYPES, a
// `number` its range, a `length` its optional per-token range, and a
// `choice` its options.
function tableError(tokens) {
    if (!isPlainObject(tokens) || isLeaf(tokens))
        return "table must be a group";
    var walk = function (node, path) {
        var keys = Object.keys(node);
        if (keys.length === 0)
            return "group " + path + " is empty";
        for (var i = 0; i < keys.length; i++) {
            var at = path === "" ? keys[i] : path + "." + keys[i];
            if (!NAME_PATTERN.test(keys[i]))
                return at + " is not a token name";
            var child = node[keys[i]];
            if (!isPlainObject(child))
                return at + " is neither a group nor a token";
            if (!isLeaf(child)) {
                var inner = walk(child, at);
                if (inner !== "")
                    return inner;
                continue;
            }
            if (TYPES.indexOf(child.type) === -1)
                return at + " has unknown type " + JSON.stringify(child.type);
            if (child.type === "number" && !(typeof child.min === "number" && typeof child.max === "number" && child.min <= child.max))
                return at + " is a number without a range";
            if (child.type === "length") {
                if (child.min !== undefined && (typeof child.min !== "number" || !isFinite(child.min)))
                    return at + ".min must be a finite number";
                if (child.max !== undefined && (typeof child.max !== "number" || !isFinite(child.max)))
                    return at + ".max must be a finite number";
                if (child.min !== undefined && child.max !== undefined && child.min > child.max)
                    return at + ".min must not be greater than max";
            }
            if (child.type === "choice" && !(Array.isArray(child.options) && child.options.length > 0))
                return at + " is a choice without options";
        }
        return "";
    };
    var defect = walk(tokens, "");
    if (defect !== "")
        return defect;
    var scale = nodeAt(tokens, MOTION_SCALE);
    if (!isLeaf(scale) || scale.type !== "number")
        return MOTION_SCALE + " must be a number token";
    return "";
}

// --- colours

// { r, g, b, a }, each 0 to 1, from `#rgb`, `#rrggbb` or `#rrggbbaa`, or
// null.
function parseColor(text) {
    var m = /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.exec(text);
    if (m === null)
        return null;
    var hex = m[1];
    if (hex.length === 3)
        hex = hex[0] + hex[0] + hex[1] + hex[1] + hex[2] + hex[2];
    if (hex.length === 6)
        hex += "ff";
    var channel = function (at) { return parseInt(hex.slice(at, at + 2), 16) / 255; };
    return { r: channel(0), g: channel(2), b: channel(4), a: channel(6) };
}

function formatColor(color) {
    var channel = function (value) {
        var text = Math.round(value * 255).toString(16);
        return text.length === 1 ? "0" + text : text;
    };
    return "#" + channel(color.r) + channel(color.g) + channel(color.b) + channel(color.a);
}

// WCAG relative luminance of an opaque colour.
function luminance(color) {
    var linear = function (value) {
        return value <= 0.03928 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
    };
    return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b);
}

// WCAG 2 contrast ratio, from 1 for equal colours to 21 for black on white.
function contrastRatio(a, b) {
    var first = luminance(a);
    var second = luminance(b);
    var light = Math.max(first, second);
    var dark = Math.min(first, second);
    return (light + 0.05) / (dark + 0.05);
}

// Furthest mix toward TARGET that meets RATIO on BACKGROUND, or null.
// Judge published bytes: rounding a continuous solution can break its floor.
// Opposing RGB channels can reverse luminance, so inspect every colour
// interval instead of assuming contrast changes in one direction.
function contrastMix(color, target, background, ratio) {
    var points = [0, 1];
    var channels = ["r", "g", "b"];
    for (var c = 0; c < channels.length; c++) {
        var key = channels[c];
        var delta = target[key] - color[key];
        if (delta === 0)
            continue;
        for (var byte = 0; byte < 255; byte++) {
            var amount = ((byte + 0.5) / 255 - color[key]) / delta;
            if (amount > 0 && amount < 1)
                points.push(amount);
        }
    }
    points.sort(function (a, b) { return a - b; });
    for (var p = points.length - 1; p >= 0; p--) {
        // A crossing itself can differ from both adjacent intervals when
        // channels move in opposite directions and round at the same point.
        var amounts = p > 0 ? [points[p], (points[p] + points[p - 1]) / 2] : [points[p]];
        for (var a = 0; a < amounts.length; a++) {
            var mix = parseColor(formatColor({
                r: color.r + (target.r - color.r) * amounts[a],
                g: color.g + (target.g - color.g) * amounts[a],
                b: color.b + (target.b - color.b) * amounts[a], a: 1
            }));
            if (contrastRatio(mix, background) >= ratio)
                return mix;
        }
    }
    return null;
}

// COLOR made opaque and mixed toward white by LIFT, a share of one: what a
// glass surface whose fill is COLOR draws over content no blur reaches
// (Theme.glassSolid).
function liftedOpaque(color, lift) {
    var channel = function (value) { return value + (1 - value) * lift; };
    return { r: channel(color.r), g: channel(color.g), b: channel(color.b), a: 1 };
}

// White or black, whichever contrasts more with an opaque colour. Either
// meets any opaque colour at 4.58:1 or more, the ratio both reach on the
// colour of luminance 0.179.
function contrastColor(color) {
    var light = luminance(color);
    return 1.05 / (light + 0.05) > (light + 0.05) / 0.05 ? parseColor("#ffffff") : parseColor("#000000");
}

// Text drawn at rest must meet WCAG 2.2 SC 1.4.3 AA for normal-size text
// on each resting surface. Inactive controls and hover surfaces are exempt.
// `color.accent` draws text roles such as eyebrow, checked buttons and badges.
var READABILITY_TEXT_ROLES = [
    "color.text",
    "color.textHeading",
    "color.textMuted",
    "color.textFaint",
    "color.accent",
    "color.success",
    "color.warning",
    "color.danger",
    "color.info"
];
var READABILITY_SURFACES = [
    "color.background",
    "color.surface",
    "color.surfaceRaised",
    "color.surfaceSunken"
];
var READABILITY_FLOOR = 4.5;
// Pillow native-pixel fixed-stem medians on 9ebf4e75f (2026-10-13,
// VGS-1658): Tray hint and Network bodyStrong danger in dracula and
// flexoki-light fit these coverages without exceeding either capture.
// Medium (500) uses the regular fit; bold (600/700) uses bodyStrong's.
var TEXT_STROKE_COVERAGE = { regular: 0.966, bold: 1.000 };
// Each judged colour's actual weight sources: Label typography, Button's
// variant override and AvatarGroup. TileGroup selects its role
// from the theme, so both caption colours read the selected role's weight.
function readabilityWeights(values) {
    var tileWeight = "text." + valueAt(values, "tileGroup.captionRole") + ".weight";
    return {
        "color.text": ["text.body.weight", "text.bodyStrong.weight", "text.item.weight", "text.itemCode.weight", "text.menuItem.weight", "text.value.weight", "text.button.weight", "text.kbd.weight", "text.code.weight", "text.bar.weight", "text.tooltip.weight", "button.variant.secondary.weight", "button.variant.tertiary.weight", "button.variant.ghost.weight", "avatarGroup.weight"],
        "color.textHeading": ["text.display.weight", "text.h1.weight", "text.h2.weight", "text.h3.weight", "text.windowTitle.weight"],
        "color.textMuted": ["text.subheading.weight", "text.label.weight", "text.body.weight", "text.hint.weight", "text.bar.weight", "text.value.weight", "text.bodyStrong.weight", "text.code.weight", "text.item.weight", "text.button.weight", "text.kbd.weight", tileWeight],
        "color.textFaint": ["text.hint.weight", "text.itemHint.weight", "text.menuItemHint.weight", "text.item.weight", "text.body.weight", "text.kbd.weight"],
        "color.accent": ["text.eyebrow.weight", "text.body.weight", "text.bar.weight", "text.button.weight", "text.label.weight", "button.variant.primary.weight", "button.variant.secondary.weight", "button.variant.tertiary.weight", "button.variant.ghost.weight", "button.variant.danger.weight", tileWeight],
        "color.success": ["text.body.weight", "text.hint.weight", "text.value.weight"],
        "color.warning": ["text.body.weight", "text.hint.weight", "text.value.weight", "text.bar.weight"],
        "color.danger": ["text.body.weight", "text.hint.weight", "text.itemHint.weight", "text.bodyStrong.weight", "text.bar.weight"],
        "color.info": ["text.body.weight", "text.hint.weight", "text.value.weight"],
        "segmented.foreground": ["text.button.weight"],
        "segmented.selectedForeground": ["text.button.weight"],
        "listItem.selectedForeground": ["text.item.weight", "text.itemHint.weight"],
        "badge.tone.neutral.foreground": ["text.label.weight", "text.kbd.weight"],
        "badge.tone.accent.foreground": ["text.label.weight", "text.kbd.weight"],
        "badge.tone.success.foreground": ["text.label.weight", "text.kbd.weight"],
        "badge.tone.warning.foreground": ["text.label.weight", "text.kbd.weight"],
        "badge.tone.danger.foreground": ["text.label.weight", "text.kbd.weight"],
        "badge.tone.info.foreground": ["text.label.weight", "text.kbd.weight"],
        "carousel.hint": ["text.itemHint.weight", "text.h3.weight"],
        "carousel.hintActive": ["text.itemHint.weight", "text.h3.weight", "text.display.weight", "text.bodyStrong.weight"],
        "carousel.hintDanger": ["text.body.weight"],
        "tooltip.foreground": ["text.tooltip.weight"],
        "tooltip.detail": ["text.itemHint.weight"]
    };
}

// The sampled ink model, rounded to display channels before contrast.
function drawnTextRatio(text, surface, weight) {
    var coverage = weight >= 600 ? TEXT_STROKE_COVERAGE.bold : TEXT_STROKE_COVERAGE.regular;
    var ink = { r: text.r, g: text.g, b: text.b, a: coverage };
    return contrastRatio(parseColor(formatColor(overlay(ink, surface))), surface);
}
// Text drawn on a control's own fill rather than on a resting surface, at
// the same floor. A translucent fill, such as a badge's faint tone, is
// judged laid over each resting surface, as it is drawn.
var READABILITY_PAIRS = [
    ["segmented.foreground", "segmented.background"],
    ["segmented.selectedForeground", "segmented.selected"],
    ["listItem.selectedForeground", "listItem.selected"],
    ["badge.tone.neutral.foreground", "badge.tone.neutral.background"],
    ["badge.tone.accent.foreground", "badge.tone.accent.background"],
    ["badge.tone.success.foreground", "badge.tone.success.background"],
    ["badge.tone.warning.foreground", "badge.tone.warning.background"],
    ["badge.tone.danger.foreground", "badge.tone.danger.background"],
    ["badge.tone.info.foreground", "badge.tone.info.background"]
];
// An input that shows its state by its outline or indicator must meet WCAG
// 2.2 SC 1.4.11 non-text contrast, 3:1: each boundary and selected
// indicator on each resting surface, each switch knob on its track, and
// the chosen segment's mark on its segment and on the track.
var BOUNDARY_ROLES = [
    "checkbox.borderColor",
    "radio.borderColor",
    "textField.borderColor",
    "toggle.off",
    "checkbox.checked",
    "radio.checked",
    "toggle.on"
];
var BOUNDARY_PAIRS = [
    ["toggle.knobOff", "toggle.off"],
    ["toggle.knobOn", "toggle.on"],
    ["checkbox.mark", "checkbox.checked"],
    ["segmented.indicatorColor", "segmented.selected"],
    ["segmented.indicatorColor", "segmented.background"]
];
var BOUNDARY_FLOOR = 3;
// A modal card shows over the scrim, which dims the page under it. On each
// dimmed resting surface its border meets the boundary floor, and its fill
// is at least as light as that surface or meets the floor too, so the card
// reads as the layer above the page in every mode.
var MODAL_SCRIM = "color.scrim";
var MODAL_BORDER = "dialog.border";
var MODAL_FILL = "dialog.background";
// Text beside the theme browser's rail sits on the scrim over the
// wallpaper; a black wallpaper leaves it the darkest backdrop.
var RAIL_TEXT_ROLES = ["carousel.hint", "carousel.hintActive"];
// The open tab's indicator there is a mark, held to the boundary floor.
var RAIL_MARK_ROLES = ["carousel.tabIndicator"];
var RAIL_WALLPAPER = "#000000";
// A failure line beside the rail rests on its own plate, not on the scrim,
// so no wallpaper reaches it: the line and its mark are judged on the
// plate alone, which must be solid.
var FAILURE_LINE = "carousel.hintDanger";
var FAILURE_PLATE = "carousel.failurePlate";
// A tooltip's title and detail lines, on its fill without glass and on
// the fill solid glass draws under it (Theme.glassSolid), which VGlass
// lifts toward white: that lifted fill is named GLASS_SOLID.
var TOOLTIP_TEXT_ROLES = ["tooltip.foreground", "tooltip.detail"];
var TOOLTIP_FILL = "tooltip.background";
var GLASS_SOLID = "glass.fill solid";
// A list's plate and the text of the row it sits on draw over glass in a
// menu or a select list as on any surface: the plate laid over the fill
// solid glass draws, since no backdrop under drawn glass can be judged.
var GLASS_PLATE_PAIRS = [["listItem.selectedForeground", "listItem.selected"]];

// Notice copy shared by the terminal and ThemeRunner. Each role names
// its weakest surface; the verdict keeps every shortfall unchanged.
var READABILITY_NAMES = {
    "color.text": "Body text", "color.textHeading": "Headings",
    "color.textMuted": "Muted text", "color.textFaint": "Faint text",
    "color.accent": "Accent text", "color.success": "Success text",
    "color.warning": "Warning text", "color.danger": "Error text", "color.info": "Information text",
    "color.background": "the main background", "color.surface": "panel backgrounds",
    "color.surfaceRaised": "raised panel backgrounds", "color.surfaceSunken": "inset panel backgrounds",
    "segmented.foreground": "Choice text", "segmented.selectedForeground": "Selected choice text",
    "segmented.background": "choice backgrounds", "segmented.selected": "selected choice backgrounds",
    "listItem.selectedForeground": "Selected row text", "listItem.selected": "selected row backgrounds",
    "checkbox.borderColor": "Checkbox outline", "checkbox.checked": "Selected checkbox",
    "checkbox.mark": "Checkbox mark", "radio.borderColor": "Radio outline", "radio.checked": "Selected radio",
    "textField.borderColor": "Text field outline", "toggle.off": "Switch off track", "toggle.on": "Switch on track",
    "toggle.knobOff": "Switch off knob", "toggle.knobOn": "Switch on knob",
    "segmented.indicatorColor": "Selected choice mark", "dialog.border": "Dialog outline",
    "dialog.background": "Dialog background", "color.scrim": "the dimmed background",
    "carousel.hint": "Theme browser hints", "carousel.hintActive": "Selected theme text",
    "carousel.tabIndicator": "Theme browser tab mark", "carousel.hintDanger": "Theme browser errors",
    "carousel.failurePlate": "the theme browser message background", "tooltip.foreground": "Tooltip text",
    "tooltip.detail": "Tooltip details", "tooltip.background": "tooltip backgrounds",
    "glass.fill solid": "glass panel backgrounds", "#000000": "black wallpaper"
};
var READABILITY_BADGE_NAMES = { neutral: "Neutral", accent: "Accent", success: "Success", warning: "Warning", danger: "Error", info: "Information" };

function readabilityName(key) {
    var parts = key.split(" over ");
    if (parts.length === 2) return readabilityName(parts[0]) + " over " + readabilityName(parts[1]);
    if (hasOwn(READABILITY_NAMES, key)) return READABILITY_NAMES[key];
    var badge = /^badge\.tone\.([^.]+)\.(foreground|background)$/.exec(key);
    if (badge !== null && hasOwn(READABILITY_BADGE_NAMES, badge[1]))
        return READABILITY_BADGE_NAMES[badge[1]] + (badge[2] === "foreground" ? " badge text" : " badge backgrounds");
    throw new Error("theme: unknown readability role=" + key);
}

function readabilityTitle(name, displayName) {
    return (displayName === null ? name : displayName) + ": some text may be hard to read";
}

function readabilityNotice(shortfalls) {
    var worst = {};
    var roles = [];
    for (var i = 0; i < shortfalls.length; i++) {
        var row = shortfalls[i];
        if (!hasOwn(worst, row.text)) { worst[row.text] = row; roles.push(row.text); }
        else if (worst[row.text].ratio !== null && (row.ratio === null || row.ratio < worst[row.text].ratio)) worst[row.text] = row;
    }
    if (roles.length === 0) return "";
    var lines = [];
    for (var j = 0; j < roles.length; j++) {
        var shortfall = worst[roles[j]];
        var ratio = shortfall.ratio === null ? "contrast cannot be measured" : "contrast " + (Math.floor(shortfall.ratio * 100) / 100).toFixed(2) + ":1";
        var line = readabilityName(shortfall.text) + " on " + readabilityName(shortfall.surface) + ": " + ratio + ", needs " + shortfall.floor + ":1.";
        // PluginLogic.notifyOptions accepts at most 600 message characters.
        // Reserve the final line before adding a role so omission is explicit.
        var remaining = roles.length - j - 1;
        var tail = remaining > 0 ? "\n" + remaining + " more roles may be hard to read." : "";
        if (lines.concat([line]).join("\n").length + tail.length > 600) {
            lines.push((roles.length - j) + " more roles may be hard to read.");
            break;
        }
        lines.push(line);
    }
    return lines.join("\n");
}

function valueAt(values, path) {
    var node = values;
    var parts = path.split(".");
    for (var i = 0; i < parts.length; i++)
        node = isPlainObject(node) && hasOwn(node, parts[i]) ? node[parts[i]] : undefined;
    return node;
}

// Every pair of the readability table below its floor, as { text,
// surface, ratio, floor }: text roles on resting surfaces and text on a
// control's fill at 4.5, a translucent fill laid over each resting surface
// and named `<fill> over <surface>`, then input boundaries, selected
// indicators and knobs at 3, then the modal card's border and fill at 3 on
// the scrim laid over each resting surface, a fill at least as light as
// that dimmed surface passing at any ratio, then the rail text at 4.5 and
// the rail's marks at 3 on the scrim laid over a black wallpaper, then the
// failure line, the typed filter and the search hint at 4.5 on their
// plate, then the tooltip's text at 4.5 on its fill and on GLASS, the
// VGlass look resolved for VALUES (acceptAppearance of Glass.js), as its
// glass draws solid, and the list plate's text at 4.5 on the plate laid
// over that solid glass. Any other translucent colour, a translucent failure plate included, has no ratio
// and is a shortfall.
function readabilityShortfalls(values, glass) {
    var weights = readabilityWeights(values);
    var pairs = [];
    for (var i = 0; i < READABILITY_TEXT_ROLES.length; i++)
        for (var j = 0; j < READABILITY_SURFACES.length; j++)
            pairs.push([READABILITY_TEXT_ROLES[i], READABILITY_SURFACES[j], READABILITY_FLOOR]);
    for (var p = 0; p < READABILITY_PAIRS.length; p++) {
        var fill = parseColor(valueAt(values, READABILITY_PAIRS[p][1]));
        if (fill === null || fill.a === 1)
            pairs.push([READABILITY_PAIRS[p][0], READABILITY_PAIRS[p][1], READABILITY_FLOOR]);
        else
            for (var u = 0; u < READABILITY_SURFACES.length; u++)
                pairs.push([READABILITY_PAIRS[p][0], READABILITY_PAIRS[p][1], READABILITY_FLOOR, READABILITY_SURFACES[u]]);
    }
    for (var k = 0; k < BOUNDARY_ROLES.length; k++)
        for (var m = 0; m < READABILITY_SURFACES.length; m++)
            pairs.push([BOUNDARY_ROLES[k], READABILITY_SURFACES[m], BOUNDARY_FLOOR]);
    for (var n = 0; n < BOUNDARY_PAIRS.length; n++)
        pairs.push([BOUNDARY_PAIRS[n][0], BOUNDARY_PAIRS[n][1], BOUNDARY_FLOOR]);
    for (var s = 0; s < READABILITY_SURFACES.length; s++) {
        pairs.push([MODAL_BORDER, MODAL_SCRIM, BOUNDARY_FLOOR, READABILITY_SURFACES[s]]);
        pairs.push([MODAL_FILL, MODAL_SCRIM, BOUNDARY_FLOOR, READABILITY_SURFACES[s], true]);
    }
    for (var w = 0; w < RAIL_TEXT_ROLES.length; w++)
        pairs.push([RAIL_TEXT_ROLES[w], MODAL_SCRIM, READABILITY_FLOOR, RAIL_WALLPAPER]);
    for (var x = 0; x < RAIL_MARK_ROLES.length; x++)
        pairs.push([RAIL_MARK_ROLES[x], MODAL_SCRIM, BOUNDARY_FLOOR, RAIL_WALLPAPER]);
    pairs.push([FAILURE_LINE, FAILURE_PLATE, READABILITY_FLOOR]);
    for (var t = 0; t < TOOLTIP_TEXT_ROLES.length; t++) {
        pairs.push([TOOLTIP_TEXT_ROLES[t], TOOLTIP_FILL, READABILITY_FLOOR]);
        pairs.push([TOOLTIP_TEXT_ROLES[t], GLASS_SOLID, READABILITY_FLOOR]);
    }
    for (var g = 0; g < GLASS_PLATE_PAIRS.length; g++)
        pairs.push([GLASS_PLATE_PAIRS[g][0], GLASS_PLATE_PAIRS[g][1], READABILITY_FLOOR, GLASS_SOLID]);
    // As Theme.glassSolid draws it: formatted, so rounded to whole channels.
    var solid = parseColor(formatColor(liftedOpaque(parseColor(glass.glass.fill), glass.glass.solidLift)));
    var out = [];
    for (var q = 0; q < pairs.length; q++) {
        var under = pairs[q][3];
        var text = parseColor(valueAt(values, pairs[q][0]));
        var surface = pairs[q][1] === GLASS_SOLID ? solid : parseColor(valueAt(values, pairs[q][1]));
        // UNDER names a role, solid glass, or is the literal wallpaper colour.
        if (under !== undefined)
            surface = overlay(surface, under === GLASS_SOLID ? solid : parseColor(under === RAIL_WALLPAPER ? under : valueAt(values, under)));
        var ratio = text === null || surface === null || text.a < 1 || surface.a < 1
            ? null
            : contrastRatio(text, surface);
        if (ratio !== null && pairs[q][2] === READABILITY_FLOOR) {
            var sources = weights[pairs[q][0]];
            for (var r = 0; r < sources.length; r++)
                ratio = Math.min(ratio, drawnTextRatio(text, surface, valueAt(values, sources[r])));
        }
        if (ratio !== null && pairs[q][4] === true && luminance(text) >= luminance(surface))
            continue;
        if (ratio === null || ratio < pairs[q][2])
            out.push({ text: pairs[q][0], surface: under === undefined ? pairs[q][1] : pairs[q][1] + " over " + under, ratio: ratio, floor: pairs[q][2] });
    }
    return out;
}

// FILL laid over the opaque colour BASE, as the screen shows it, or null
// while either is missing or BASE is translucent itself. A fill the colour
// of its base answers that colour exactly.
function overlay(fill, base) {
    if (fill === null || base === null || base.a < 1)
        return null;
    return {
        r: base.r + (fill.r - base.r) * fill.a,
        g: base.g + (fill.g - base.g) * fill.a,
        b: base.b + (fill.b - base.b) * fill.a,
        a: 1
    };
}

// --- expressions

// Parse one expression into a tree of
//   { kind: "color", value }, { kind: "number", value },
//   { kind: "reference", path }, { kind: "call", name, args }
// or answer { error, detail }. The grammar:
//   expr := hex | number | '{' path '}' | name '(' expr { ',' expr } ')'
function parseExpression(text) {
    if (text.length > MAX_EXPRESSION_LENGTH)
        return { error: "too-long", detail: "length=" + text.length + " limit=" + MAX_EXPRESSION_LENGTH };
    var at = 0;
    var failure = null;
    var fail = function (reason, detail) {
        if (failure === null)
            failure = { error: reason, detail: detail };
        return null;
    };
    var skip = function () {
        while (at < text.length && text[at] === " ")
            at++;
    };
    var expr = function (depth) {
        if (depth > MAX_EXPRESSION_DEPTH)
            return fail("too-deep", "limit=" + MAX_EXPRESSION_DEPTH);
        skip();
        var rest = text.slice(at);
        var m = /^#[0-9a-fA-F]+/.exec(rest);
        if (m !== null) {
            if (parseColor(m[0]) === null)
                return fail("syntax", "colour=" + JSON.stringify(m[0]));
            at += m[0].length;
            return { kind: "color", value: m[0] };
        }
        m = /^-?[0-9]+(\.[0-9]+)?/.exec(rest);
        if (m !== null) {
            at += m[0].length;
            return { kind: "number", value: Number(m[0]) };
        }
        m = /^\{([^{}]*)\}/.exec(rest);
        if (m !== null) {
            at += m[0].length;
            return { kind: "reference", path: m[1] };
        }
        m = /^([a-z][A-Za-z0-9]*)\(/.exec(rest);
        if (m === null)
            return fail("syntax", "at=" + at);
        at += m[0].length;
        var args = [];
        for (;;) {
            var arg = expr(depth + 1);
            if (arg === null)
                return null;
            args.push(arg);
            skip();
            if (text[at] === ",") {
                at++;
                continue;
            }
            if (text[at] === ")") {
                at++;
                return { kind: "call", name: m[1], args: args };
            }
            return fail("syntax", "at=" + at);
        }
    };
    var tree = expr(1);
    if (tree === null)
        return failure;
    skip();
    if (at !== text.length)
        return { error: "syntax", detail: "at=" + at };
    return tree;
}

// The expression a token's raw value states, as a tree, or { error,
// detail }. A number or a boolean is a literal. A string is a literal for
// a `family`, an `easing` and a `choice` unless it is one reference, and an
// expression for every other type.
function readValue(leaf, raw) {
    if (typeof raw === "number")
        return isFinite(raw) ? { kind: "number", value: raw } : { error: "not-expression", detail: "value=" + raw };
    if (typeof raw === "boolean")
        return { kind: "flag", value: raw };
    if (typeof raw !== "string")
        return { error: "not-expression", detail: "value=" + JSON.stringify(raw) };
    var reference = REFERENCE_PATTERN.exec(raw);
    if (reference !== null)
        return { kind: "reference", path: reference[1] };
    if (leaf.type === "family" || leaf.type === "easing" || leaf.type === "choice")
        return { kind: "text", value: raw };
    if (leaf.type === "flag")
        return { error: "not-expression", detail: "value=" + JSON.stringify(raw) };
    return parseExpression(raw);
}

// --- resolution

// Every token's resolved value, from the table's defaults under
// `overrides`, a map of dotted token path to raw value. Answers
// { ok: true, values } with `values` a tree in the table's shape, or one
// refusal. Each token is resolved once; a reference to a token on the
// current path is a cycle. The table's leaves are listed once and found by
// path from then on: a walk of the table for every token and reference was
// 6.3 to 7.3 ms of the 16.0 to 17.1 ms three judgments took in one apply
// (node --cpu-prof at 100 us, three applies on cachy, 2026-10-12).
function resolve(tokens, overrides) {
    var resolved = {};
    var visiting = [];
    var failure = null;
    var all = leaves(tokens);
    var leafAt = {};
    for (var l = 0; l < all.length; l++)
        leafAt[all[l].path] = all[l].leaf;

    var fail = function (reason, token, detail) {
        if (failure === null)
            failure = refusal(reason, token, detail);
        return undefined;
    };

    function valueOf(path) {
        if (hasOwn(resolved, path))
            return resolved[path];
        if (visiting.indexOf(path) !== -1)
            return fail("cycle", path, "path=" + visiting.concat([path]).join(">"));
        var leaf = leafAt[path];
        visiting.push(path);
        var tree = readValue(leaf, hasOwn(overrides, path) ? overrides[path] : leaf.value);
        var value = tree.error !== undefined ? fail(tree.error, path, tree.detail) : evaluate(tree, leaf.type, path);
        if (value !== undefined)
            value = settle(leaf, value, path);
        visiting.pop();
        if (value === undefined)
            return undefined;
        resolved[path] = value;
        return value;
    }

    // The value of one tree node as type `want`, or undefined after fail().
    function evaluate(tree, want, token) {
        switch (tree.kind) {
        case "color":
            if (want !== "color")
                return fail("type", token, "want=" + want + " got=color");
            return parseColor(tree.value);
        case "number":
            if (NUMERIC_TYPES.indexOf(want) === -1)
                return fail("type", token, "want=" + want + " got=number");
            return tree.value;
        case "flag":
            if (want !== "flag")
                return fail("type", token, "want=" + want + " got=flag");
            return tree.value;
        case "text":
            return tree.value;
        case "reference":
            var target = hasOwn(leafAt, tree.path) ? leafAt[tree.path] : undefined;
            if (target === undefined)
                return fail("unknown-reference", token, "reference=" + tree.path);
            if (target.type !== want)
                return fail("type", token, "want=" + want + " got=" + target.type + " reference=" + tree.path);
            var value = valueOf(tree.path);
            if (value === undefined)
                return undefined;
            return want === "color" ? parseColor(value) : value;
        case "call":
            return call(tree, want, token);
        }
        return fail("syntax", token, "kind=" + tree.kind);
    }

    function call(tree, want, token) {
        if (!hasOwn(FUNCTIONS, tree.name))
            return fail("unknown-function", token, "function=" + tree.name);
        var signature = FUNCTIONS[tree.name];
        if (tree.args.length !== signature.args.length)
            return fail("arity", token, "function=" + tree.name + " want=" + signature.args.length + " got=" + tree.args.length);
        var result = signature.result === "same" ? want : signature.result;
        if (result !== want || (signature.result === "same" && NUMERIC_TYPES.indexOf(want) === -1))
            return fail("type", token, "want=" + want + " got=" + tree.name);
        var args = [];
        for (var i = 0; i < tree.args.length; i++) {
            var arg = evaluate(tree.args[i], signature.args[i] === "same" ? want : signature.args[i], token);
            if (arg === undefined)
                return undefined;
            args.push(arg);
        }
        switch (tree.name) {
        case "contrastMix":
            if (args[3] < 1 || args[3] > 21)
                return fail("range", token, "function=contrastMix ratio=" + args[3]);
            if (args[0].a < 1 || args[1].a < 1 || args[2].a < 1)
                return fail("contrast-translucent", token, "function=contrastMix");
            var solved = contrastMix(args[0], args[1], args[2], args[3]);
            return solved === null ? fail("contrast-unreachable", token, "function=contrastMix ratio=" + args[3]) : solved;
        case "mix":
            if (args[2] < 0 || args[2] > 1)
                return fail("range", token, "function=mix amount=" + args[2]);
            return {
                r: args[0].r + (args[1].r - args[0].r) * args[2],
                g: args[0].g + (args[1].g - args[0].g) * args[2],
                b: args[0].b + (args[1].b - args[0].b) * args[2],
                a: args[0].a + (args[1].a - args[0].a) * args[2]
            };
        case "alpha":
            if (args[1] < 0 || args[1] > 1)
                return fail("range", token, "function=alpha alpha=" + args[1]);
            return { r: args[0].r, g: args[0].g, b: args[0].b, a: args[1] };
        case "contrast":
            if (args[0].a < 1)
                return fail("contrast-translucent", token, "colour=" + formatColor(args[0]));
            return contrastColor(args[0]);
        case "readable":
        case "discernible":
            // The first colour where it meets its floor on the opaque
            // second one, as text for `readable` and as a mark for
            // `discernible`, else the third; a translucent first colour
            // has no ratio and does not meet it.
            if (args[1].a < 1)
                return fail("contrast-translucent", token, "colour=" + formatColor(args[1]));
            var floor = tree.name === "readable" ? READABILITY_FLOOR : BOUNDARY_FLOOR;
            return args[0].a === 1 && contrastRatio(args[0], args[1]) >= floor ? args[0] : args[2];
        case "mul":
            return args[0] * args[1];
        }
        return fail("unknown-function", token, "function=" + tree.name);
    }

    // The portable value of an evaluated token, checked against its type's
    // range or options, or undefined after fail().
    function settle(leaf, value, token) {
        if (leaf.type === "color")
            return formatColor(value);
        if (leaf.type === "flag")
            return value;
        if (leaf.type === "family") {
            if (typeof value !== "string" || value.trim() === "")
                return fail("type", token, "want=family got=" + JSON.stringify(value));
            return value;
        }
        if (leaf.type === "easing" || leaf.type === "choice") {
            var options = leaf.type === "easing" ? EASINGS : leaf.options;
            if (options.indexOf(value) === -1)
                return fail("option", token, "value=" + JSON.stringify(value));
            return value;
        }
        // Every numeric path above yields a finite number: literals are
        // parsed from digits and the functions add and multiply bounded
        // values. Anything else is a defect of this file.
        if (typeof value !== "number" || !isFinite(value))
            throw new Error("theme: settle: " + token + " evaluated to " + String(value));
        if (WHOLE_TYPES.indexOf(leaf.type) !== -1)
            value = Math.round(value);
        var range = leaf.type === "number" ? [leaf.min, leaf.max]
            : leaf.type === "length" ? [
                leaf.min === undefined ? RANGES.length[0] : leaf.min,
                leaf.max === undefined ? RANGES.length[1] : leaf.max
            ] : RANGES[leaf.type];
        if (value < range[0] || value > range[1])
            return fail("range", token, "value=" + value + " min=" + range[0] + " max=" + range[1]);
        return value;
    }

    var values = {};
    var scale = valueOf(MOTION_SCALE);
    if (failure !== null)
        return failure;
    for (var i = 0; i < all.length; i++) {
        var value = valueOf(all[i].path);
        if (failure !== null)
            return failure;
        if (all[i].leaf.type === "duration")
            value = Math.round(value * scale);
        var parts = all[i].path.split(".");
        var group = values;
        for (var p = 0; p < parts.length - 1; p++) {
            if (!hasOwn(group, parts[p]))
                group[parts[p]] = {};
            group = group[parts[p]];
        }
        group[parts[parts.length - 1]] = value;
    }
    return { ok: true, values: values };
}

// The overrides a document's `tokens` tree states, as a map of dotted token
// path to raw value, or one refusal. A path the table does not hold is
// refused, as is a value where the table holds a group. A group where the
// table holds a token is an object, which readValue refuses.
function overridesOf(tokens, tree) {
    var out = {};
    var failure = null;
    var walk = function (node, path) {
        var keys = Object.keys(node);
        for (var i = 0; i < keys.length && failure === null; i++) {
            var at = path === "" ? keys[i] : path + "." + keys[i];
            var known = nodeAt(tokens, at);
            if (known === undefined)
                failure = refusal("unknown-token", at);
            else if (isLeaf(known))
                out[at] = node[keys[i]];
            else if (!isPlainObject(node[keys[i]]))
                failure = refusal("group-expected", at, "value=" + JSON.stringify(node[keys[i]]));
            else
                walk(node[keys[i]], at);
        }
    };
    walk(tree, "");
    return failure === null ? { ok: true, overrides: out } : failure;
}

function acceptBackgrounds(document) {
    if (document.backgrounds === undefined)
        return { ok: true, backgrounds: {} };
    if (!isPlainObject(document.backgrounds))
        return refusal("backgrounds", "backgrounds", "got=" + JSON.stringify(document.backgrounds));
    var keys = Object.keys(document.backgrounds);
    var out = {};
    for (var i = 0; i < keys.length; i++) {
        var file = keys[i];
        if (file === "" || file.indexOf("/") !== -1 || file.charAt(0) === ".")
            return refusal("background-file", "backgrounds", "file=" + JSON.stringify(file));
        var name = document.backgrounds[file];
        if (typeof name !== "string" || !/^\S+( \S+)?$/.test(name))
            return refusal("background-name", "backgrounds", "file=" + file + " got=" + JSON.stringify(name));
        out[file] = name;
    }
    return { ok: true, backgrounds: out };
}

// Judge and resolve one shell document, given as text. Answers
// { ok: true, name, displayName, values, overrides, backgrounds } or one
// refusal; nothing of a refused document is part of the answer.
// `displayName` is the optional name a view shows for the package, null
// when the document states none. `overrides` is what the document states,
// which withAppearance resolves again under a user's values.
function accept(tokens, text) {
    var document;
    try {
        document = JSON.parse(text);
    } catch (e) {
        return refusal("not-json", "", e.message);
    }
    if (!isPlainObject(document))
        return refusal("not-object", "");
    var keys = Object.keys(document);
    for (var i = 0; i < keys.length; i++)
        if (DOCUMENT_KEYS.indexOf(keys[i]) === -1)
            return refusal("unknown-key", "", "key=" + keys[i]);
    if (document.schemaVersion !== SCHEMA_VERSION)
        return refusal("schema-version", "", "want=" + SCHEMA_VERSION + " got=" + JSON.stringify(document.schemaVersion));
    if (typeof document.name !== "string" || document.name.trim() === "")
        return refusal("name", "", "got=" + JSON.stringify(document.name));
    var displayName = null;
    if (document.displayName !== undefined) {
        displayName = document.displayName;
        if (typeof displayName !== "string" || displayName.trim() === "")
            return refusal("display-name", "", "got=" + JSON.stringify(displayName));
    }
    var tree = document.tokens === undefined ? {} : document.tokens;
    if (!isPlainObject(tree))
        return refusal("tokens", "", "got=" + JSON.stringify(tree));
    var backgrounds = acceptBackgrounds(document);
    if (!backgrounds.ok)
        return backgrounds;
    var stated = overridesOf(tokens, tree);
    if (!stated.ok)
        return stated;
    var result = resolve(tokens, stated.overrides);
    if (!result.ok)
        return result;
    return { ok: true, name: document.name, displayName: displayName, values: result.values, overrides: stated.overrides, backgrounds: backgrounds.backgrounds };
}

// --- plugin-owned appearance

// The tokens a plugin-owned appearance takes from the active theme, by the
// path both tables hold them at, and nothing else of the theme. The accent
// is the one palette colour; the scale is the motion control, so reduced
// motion reaches the plugin's durations as it reaches the shell's; the
// family is the interface font, so the user's Fonts choice reaches the
// plugin's text; the raised surface is the fill the theme's own controls
// stand on, so a look that draws them, as VGlass does, shares their hue.
var INTERFACE_FAMILY = "font.family.sans";
var RAISED_SURFACE = "color.surfaceRaised";
var APPEARANCE_INPUTS = ["palette.accent", MOTION_SCALE, INTERFACE_FAMILY, RAISED_SURFACE];

// The token whose value picks the plugin's light overrides.
var SCHEME_MODE = "scheme.mode";

// Judge and resolve a plugin's own token table. `table` is in Tokens.js
// leaf format; `light` is an overrides tree in document shape, applied when
// the theme's `scheme.mode` is `light` and judged in both modes, so a defect
// in it refuses in either. `theme` is the active theme's resolved values,
// as accept answers them, so its mode is one the shell's own judge
// accepted. The table's `palette` group holds `accent` alone, a
// `font.family.sans` the table holds is a `family`, and `light` sets no
// input, so no other theme value reaches the plugin and the plugin cannot
// shadow what the theme gives it. An input reaches only a table that holds
// its path. Answers { ok: true, values } or
// one refusal whose reason starts `appearance-` or is the resolver's own.
function acceptAppearance(table, light, theme) {
    var defect = tableError(table);
    if (defect !== "")
        return refusal("appearance-table", "", defect);
    var palette = nodeAt(table, "palette");
    var accent = nodeAt(table, APPEARANCE_INPUTS[0]);
    if (!isLeaf(accent) || accent.type !== "color" || Object.keys(palette).length !== 1)
        return refusal("appearance-palette", "palette", "want=accent-colour-alone");
    var family = nodeAt(table, INTERFACE_FAMILY);
    if (family !== undefined && family.type !== "family")
        return refusal("appearance-font", INTERFACE_FAMILY, "want=family");
    if (!isPlainObject(light))
        return refusal("appearance-light", "", "got=" + JSON.stringify(light));
    var stated = overridesOf(table, light);
    if (!stated.ok)
        return stated;
    for (var i = 0; i < APPEARANCE_INPUTS.length; i++)
        if (hasOwn(stated.overrides, APPEARANCE_INPUTS[i]))
            return refusal("appearance-input", APPEARANCE_INPUTS[i], "light sets an input");
    var mode = valueAt(theme, SCHEME_MODE);
    if (typeof mode !== "string")
        return refusal("appearance-theme", SCHEME_MODE, "got=" + JSON.stringify(mode));
    var overrides = mode === "light" ? stated.overrides : {};
    for (var j = 0; j < APPEARANCE_INPUTS.length; j++) {
        var value = valueAt(theme, APPEARANCE_INPUTS[j]);
        if (value === undefined)
            return refusal("appearance-theme", APPEARANCE_INPUTS[j], "got=undefined");
        overrides[APPEARANCE_INPUTS[j]] = value;
    }
    return resolve(table, overrides);
}

// The name the defaults carry and the only package name an installed theme
// may not take. The shipped package with this name is the revert.
var DEFAULT_NAME = "vgs";

// A package name is a directory name the runner can join to a themes
// directory without leaving it and print in a keyed line without quoting:
// no separator, no leading dot, no space.
var PACKAGE_NAME_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

function isPackageName(name) {
    return typeof name === "string" && PACKAGE_NAME_PATTERN.test(name);
}

// A Hyprland output name as `hyprctl monitors` prints it and Quickshell's
// `screen.name` carries it: `DP-1`, `HDMI-A-1`, `eDP-1`, `HEADLESS-2`.
// Its shape alone; whether the output exists is Hyprland's answer, so an
// entry can wait for a disconnected monitor.
var OUTPUT_NAME_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_-]*$/;

function isOutputName(name) {
    return typeof name === "string" && OUTPUT_NAME_PATTERN.test(name);
}

// The screen of `vgshell theme background set --every-screen`, in its result
// and in the theme capability's `set`: no output name can be it.
var EVERY_SCREEN = "*";

// The `vgshell theme background set` arguments after the path for the theme
// capability's SCREEN: none for null or undefined, the current image;
// `--every-screen` for EVERY_SCREEN; `--screen <name>` for an output name;
// null for anything else, which the capability refuses at once.
function setScreenArguments(screen) {
    if (screen === null || screen === undefined)
        return [];
    if (screen === EVERY_SCREEN)
        return ["--every-screen"];
    return isOutputName(screen) ? ["--screen", screen] : null;
}

// The `vgshell theme wallpapers` arguments after the name for the theme
// capability's OPTIONS: none for undefined or an object without `update`,
// `--update` for `update: true`; null for anything else, a non-object, an
// unknown key or an `update` that is no boolean, which the capability
// refuses at once.
function wallpaperArguments(options) {
    if (options === undefined)
        return [];
    if (!isPlainObject(options))
        return null;
    var keys = Object.keys(options);
    for (var i = 0; i < keys.length; i++) {
        if (keys[i] !== "update")
            return null;
    }
    if (!hasOwn(options, "update"))
        return [];
    if (typeof options.update !== "boolean")
        return null;
    return options.update ? ["--update"] : [];
}

// An absolute path in the form `vgshell theme background list` prints it: a
// leading `/` and no empty, `.` or `..` segment. The theme capability
// passes only such a path to the runner, whose working directory is the
// shell's and no plugin's.
function isAbsolutePath(text) {
    if (typeof text !== "string" || text.charAt(0) !== "/" || text.indexOf("\u0000") !== -1)
        return false;
    var segments = text.slice(1).split("/");
    for (var i = 0; i < segments.length; i++) {
        if (segments[i] === "" || segments[i] === "." || segments[i] === "..")
            return false;
    }
    return true;
}

// The directories of a themes directory or the catalog that hold no
// package: the targets and the catalog. A walk of a
// themes directory skips them, so no package of any source takes these
// names.
var RESERVED_DIRECTORIES = ["targets", "catalog"];

var TERMINAL_SCHEMA_VERSION = 1;
var TERMINAL_SLOT_PREFIX = "color";
var TERMINAL_SLOT_COUNT = 16;

function terminalSlotName(index) {
    return TERMINAL_SLOT_PREFIX + index;
}

function terminalSlotNames() {
    var out = [];
    for (var i = 0; i < TERMINAL_SLOT_COUNT; i++)
        out.push(terminalSlotName(i));
    return out;
}

function acceptTerminal(text) {
    if (text === undefined)
        return { ok: true, slots: null };
    if (typeof text !== "string")
        return refusal("terminal-json", "", "got=" + JSON.stringify(text));
    var document;
    try {
        document = JSON.parse(text);
    } catch (e) {
        return refusal("terminal-json", "", e.message);
    }
    if (!isPlainObject(document))
        return refusal("terminal-document", "");
    if (document.schemaVersion !== TERMINAL_SCHEMA_VERSION)
        return refusal("terminal-schema-version", "", "want=" + TERMINAL_SCHEMA_VERSION + " got=" + JSON.stringify(document.schemaVersion));
    if (!isPlainObject(document.slots))
        return refusal("terminal-slots", "", "got=" + JSON.stringify(document.slots));
    var names = terminalSlotNames();
    var expected = {};
    for (var i = 0; i < names.length; i++)
        expected[names[i]] = true;
    var keys = Object.keys(document.slots);
    for (i = 0; i < keys.length; i++)
        if (!hasOwn(expected, keys[i]))
            return refusal("terminal-slot", "terminal", "slot=" + keys[i]);
    var out = {};
    for (i = 0; i < names.length; i++) {
        var name = names[i];
        if (!hasOwn(document.slots, name))
            return refusal("terminal-slot", "terminal", "missing=" + name);
        if (typeof document.slots[name] !== "string")
            return refusal("terminal-colour", "terminal." + name, "value=" + JSON.stringify(document.slots[name]));
        var colour = parseColor(document.slots[name]);
        if (colour === null)
            return refusal("terminal-colour", "terminal." + name, "value=" + JSON.stringify(document.slots[name]));
        out[name] = formatColor(colour);
    }
    return { ok: true, slots: out };
}

// Judge one package directory from the file texts its caller read. `files`
// carries the directory name, the required `theme.json` text, an optional
// `terminal.json` text and whether the package is shipped with the shell.
// The directory walk stays in the runner; this function does no I/O.
function acceptPackage(tokens, files) {
    if (!isPlainObject(files))
        return refusal("package", "", "got=" + JSON.stringify(files));
    if (!isPackageName(files.directoryName))
        return refusal("package-name", "", "got=" + JSON.stringify(files.directoryName));
    if (RESERVED_DIRECTORIES.indexOf(files.directoryName) !== -1)
        return refusal("reserved-name", "", "name=" + files.directoryName);
    if (files.directoryName === DEFAULT_NAME && files.shipped !== true)
        return refusal("reserved-name", "", "name=" + DEFAULT_NAME);
    if (typeof files.themeJson !== "string")
        return refusal("package-theme", "", "got=" + JSON.stringify(files.themeJson));
    var shell = accept(tokens, files.themeJson);
    if (!shell.ok)
        return shell;
    if (shell.name !== files.directoryName)
        return refusal("name-mismatch", "", "directory=" + files.directoryName + " document=" + shell.name);
    var terminal = acceptTerminal(files.terminalJson);
    if (!terminal.ok)
        return terminal;
    return { ok: true, name: shell.name, displayName: shell.displayName, values: shell.values, terminal: terminal.slots, backgrounds: shell.backgrounds };
}

// --- the theme catalog

// themes/catalog/index.json: `{ schemaVersion, entries }`, one entry per
// catalogued package, each with exactly these keys. `imagery` is null for a
// theme without wallpapers, or the pin of its release archive.
var CATALOG_SCHEMA_VERSION = 1;
var CATALOG_KEYS = ["schemaVersion", "entries"];
var CATALOG_ENTRY_KEYS = ["name", "mode", "palette", "imagery"];
var CATALOG_IMAGERY_KEYS = ["repo", "release", "archive", "size", "sha256"];

// The repository an archive downloads from: an https URL of a host and one
// or more path segments, with no credentials, port, query, fragment or
// trailing slash, so the release and archive segments join it into one URL.
var CATALOG_REPO_PATTERN = /^https:\/\/[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*(\/[A-Za-z0-9][A-Za-z0-9._-]*)+$/;
var SHA256_PATTERN = /^[0-9a-f]{64}$/;

// The first key of VALUE that KEYS does not name, or the first of KEYS that
// VALUE lacks, as `key=<name>`; "" when VALUE holds exactly KEYS.
function keyDefect(value, keys) {
    var own = Object.keys(value);
    for (var i = 0; i < own.length; i++)
        if (keys.indexOf(own[i]) === -1)
            return "key=" + own[i];
    for (i = 0; i < keys.length; i++)
        if (!hasOwn(value, keys[i]))
            return "key=" + keys[i];
    return "";
}

// Judge one index entry at position I; answer the entry with its palette
// colours in resolved form, or one refusal whose token is `entries.<i>`
// and the key it names.
function catalogEntry(tokens, entry, i) {
    var at = "entries." + i;
    if (!isPlainObject(entry))
        return refusal("catalog-entry", at, "got=" + JSON.stringify(entry));
    var defect = keyDefect(entry, CATALOG_ENTRY_KEYS);
    if (defect !== "")
        return refusal("catalog-entry", at, defect);
    if (!isPackageName(entry.name))
        return refusal("package-name", at + ".name", "got=" + JSON.stringify(entry.name));
    if (entry.name === DEFAULT_NAME || RESERVED_DIRECTORIES.indexOf(entry.name) !== -1)
        return refusal("reserved-name", at + ".name", "name=" + entry.name);
    if (nodeAt(tokens, SCHEME_MODE).options.indexOf(entry.mode) === -1)
        return refusal("catalog-mode", at + ".mode", "got=" + JSON.stringify(entry.mode));
    if (!isPlainObject(entry.palette))
        return refusal("catalog-palette", at + ".palette", "got=" + JSON.stringify(entry.palette));
    var names = Object.keys(nodeAt(tokens, "palette"));
    defect = keyDefect(entry.palette, names);
    if (defect !== "")
        return refusal("catalog-palette", at + ".palette", defect);
    var palette = {};
    for (var j = 0; j < names.length; j++) {
        var colour = typeof entry.palette[names[j]] === "string" ? parseColor(entry.palette[names[j]]) : null;
        if (colour === null)
            return refusal("catalog-palette", at + ".palette." + names[j], "value=" + JSON.stringify(entry.palette[names[j]]));
        palette[names[j]] = formatColor(colour);
    }
    var imagery = null;
    if (entry.imagery !== null) {
        var pin = catalogImagery(entry.imagery, at + ".imagery");
        if (!pin.ok)
            return pin;
        imagery = pin.imagery;
    }
    return { ok: true, entry: { name: entry.name, mode: entry.mode, palette: palette, imagery: imagery } };
}

// Judge IMAGERY, the pin of a wallpaper archive, at token AT: an index
// entry's `imagery`, or the pin a catalog install's marker records for the
// archive it unpacked. Answers { ok: true, imagery } with exactly the pin's
// keys, or one refusal whose token is AT or AT and the key it names.
function catalogImagery(imagery, at) {
    if (!isPlainObject(imagery))
        return refusal("catalog-imagery", at, "got=" + JSON.stringify(imagery));
    var defect = keyDefect(imagery, CATALOG_IMAGERY_KEYS);
    if (defect !== "")
        return refusal("catalog-imagery", at, defect);
    if (typeof imagery.repo !== "string" || !CATALOG_REPO_PATTERN.test(imagery.repo))
        return refusal("catalog-repo", at + ".repo", "got=" + JSON.stringify(imagery.repo));
    if (!isPackageName(imagery.release))
        return refusal("catalog-imagery", at + ".release", "got=" + JSON.stringify(imagery.release));
    if (!isPackageName(imagery.archive))
        return refusal("catalog-imagery", at + ".archive", "got=" + JSON.stringify(imagery.archive));
    if (!Number.isSafeInteger(imagery.size) || imagery.size <= 0)
        return refusal("catalog-size", at + ".size", "got=" + JSON.stringify(imagery.size));
    if (typeof imagery.sha256 !== "string" || !SHA256_PATTERN.test(imagery.sha256))
        return refusal("catalog-sha256", at + ".sha256", "got=" + JSON.stringify(imagery.sha256));
    return { ok: true, imagery: { repo: imagery.repo, release: imagery.release, archive: imagery.archive, size: imagery.size, sha256: imagery.sha256 } };
}

// Judge the text of themes/catalog/index.json. The package each entry names
// is judged apart, by acceptCatalogEntry, because its files are the
// caller's to read. Answers { ok: true, entries } in index order, each
// entry's palette in resolved colour form, or one refusal whose reason
// starts `catalog-` or is a name rule's.
function acceptCatalogIndex(tokens, text) {
    var document;
    try {
        document = JSON.parse(text);
    } catch (e) {
        return refusal("catalog-json", "", e.message);
    }
    if (!isPlainObject(document))
        return refusal("catalog-document", "", "got=" + JSON.stringify(document));
    var defect = keyDefect(document, CATALOG_KEYS);
    if (defect !== "")
        return refusal("catalog-document", "", defect);
    if (document.schemaVersion !== CATALOG_SCHEMA_VERSION)
        return refusal("catalog-schema-version", "", "want=" + CATALOG_SCHEMA_VERSION + " got=" + JSON.stringify(document.schemaVersion));
    if (!Array.isArray(document.entries))
        return refusal("catalog-entries", "", "got=" + JSON.stringify(document.entries));
    var entries = [];
    var seen = {};
    for (var i = 0; i < document.entries.length; i++) {
        var judged = catalogEntry(tokens, document.entries[i], i);
        if (!judged.ok)
            return judged;
        if (hasOwn(seen, judged.entry.name))
            return refusal("duplicate-name", "entries." + i + ".name", "name=" + judged.entry.name);
        seen[judged.entry.name] = true;
        entries.push(judged.entry);
    }
    return { ok: true, entries: entries };
}

// Judge one catalogued package against ENTRY, an entry acceptCatalogIndex
// answered: acceptPackage judges it as the installed package it becomes,
// under the entry's name, and the index's mode and palette must be the
// package's own resolved `scheme.mode` and palette group. `files` carries
// the `theme.json` text and the optional `terminal.json` text.
function acceptCatalogEntry(tokens, entry, files) {
    if (!isPlainObject(files))
        return refusal("package", "", "got=" + JSON.stringify(files));
    var accepted = acceptPackage(tokens, { directoryName: entry.name, themeJson: files.themeJson, terminalJson: files.terminalJson, shipped: false });
    if (!accepted.ok)
        return accepted;
    if (accepted.values.scheme.mode !== entry.mode)
        return refusal("catalog-mode-mismatch", SCHEME_MODE, "index=" + entry.mode + " package=" + accepted.values.scheme.mode);
    var names = Object.keys(entry.palette);
    for (var i = 0; i < names.length; i++)
        if (accepted.values.palette[names[i]] !== entry.palette[names[i]])
            return refusal("catalog-palette-mismatch", "palette." + names[i], "index=" + entry.palette[names[i]] + " package=" + accepted.values.palette[names[i]]);
    return accepted;
}

// The table's defaults resolved, as accept answers a document. The table
// ships with the shell, so a defect in it is the shell's and throws.
function defaults(tokens) {
    var defect = tableError(tokens);
    if (defect !== "")
        throw new Error("theme: token table: " + defect);
    var result = resolve(tokens, {});
    if (!result.ok)
        throw new Error(refusalLine(result));
    return { ok: true, name: DEFAULT_NAME, values: result.values, overrides: {}, backgrounds: {} };
}

// Every dotted path the table holds, groups and tokens both, for the
// checks that judge a `Theme.<path>` reference.
function paths(tokens) {
    var out = [];
    var walk = function (node, path) {
        var keys = Object.keys(node);
        for (var i = 0; i < keys.length; i++) {
            var at = path === "" ? keys[i] : path + "." + keys[i];
            out.push(at);
            if (!isLeaf(node[keys[i]]))
                walk(node[keys[i]], at);
        }
    };
    walk(tokens, "");
    return out;
}

// --- Appearance values over the theme (D104)

// The share of a user's base value each token takes: windows the base,
// flyouts three quarters, grouped window tabs half, controls the base. A
// ratio applies to a user's value only; a theme's own tokens stand as the
// theme states them.
var APPEARANCE_RATIOS = { window: 1, flyout: 0.75, groupTab: 0.5, control: 1 };

// The motion styles a user may choose, each named after the Hyprland
// preset it sets, with the shell's two easings beside it. `smooth` is the
// table's own default.
var MOTION_STYLES = {
    smooth: { standard: "outCubic", emphasized: "outQuint" },
    snappy: { standard: "outQuart", emphasized: "outExpo" }
};

// A font family name a user may set: FAMILY_MAX characters at most, with
// no space at either end, no brace, which would make it a token reference,
// and no character that could end or change the kitty or Ghostty
// configuration line the terminal font is written into: a control
// character, a line separator, a quote, a backslash or an equals sign.
var FAMILY_MAX = 100;
var FAMILY_REFUSED = /[\u0000-\u001f\u007f-\u009f\u2028\u2029"\\={}]/;

// Each member of shell.json `appearance`. `type` is `length` (a whole
// pixel count from `min` to `max`), `number` (from `min` to `max`), `flag`
// (a boolean, or `only` that value), `choice` (one of `options`) or
// `family` (a font family name, which sets each target whole).
// `hyprland` names the generated layer's group the member decides: a
// length member takes the value "hyprland", which leaves that group to the
// user's own Hyprland configuration, and a member without a value is
// `unset`, "theme" unless stated. `theme` is the token whose resolved theme
// value the member shows while the user sets none; `targets` are the tokens
// a user's number sets, each with its ratio. `terminalFont` sets no token:
// the kitty and ghostty theme targets write it (bin/lib/theme-render.js).
var APPEARANCE = {
    windowRadius: {
        type: "length", min: 0, max: 32, hyprland: "radius", theme: "hyprland.window.radius",
        targets: [["hyprland.window.radius", "window"], ["surface.radius", "flyout"], ["popover.radius", "flyout"], ["menu.radius", "flyout"],
            ["dialog.radius", "flyout"], ["osd.radius", "flyout"], ["hyprland.window.groupRadius", "groupTab"]]
    },
    borderWidth: { type: "length", min: 0, max: 20, hyprland: "borders", theme: "hyprland.border.size", targets: [["hyprland.border.size", "window"]] },
    controlRadius: { type: "length", min: 0, max: 16, theme: "button.radius", targets: [["button.radius", "control"], ["textField.radius", "control"], ["segmented.radius", "control"]] },
    motion: { type: "flag" },
    motionStyle: { type: "choice", options: Object.keys(MOTION_STYLES) },
    motionSpeed: { type: "number", min: 0.5, max: 2 },
    // Hyprland keeps the user's own animations unless the user chooses to
    // move windows with the shell's motion: no theme value stands in.
    windowAnimations: { type: "flag", only: true, hyprland: "motion", unset: "hyprland" },
    interfaceFont: { type: "family", theme: "font.family.sans", targets: [["font.family.sans"], ["font.family.caps"]] },
    terminalFont: { type: "family" },
    // VGlass on every surface or on none; unset, each surface's own choice
    // decides (glassOn).
    glass: { type: "choice", options: ["on", "off"], unset: "surface" },
    // Hyprland's own windows as one surface's choice: unset leaves window
    // decoration to the user's Hyprland config.
    windowGlass: { type: "flag", only: true, hyprland: "glass", unset: "hyprland" },
    // A glow inside the focused window while window glass is on; unset
    // leaves the glow to the user's Hyprland config.
    windowGlow: { type: "flag", only: true, hyprland: "glow", unset: "hyprland" }
};

// The roles VGlass rounds while every surface draws glass, and the token
// that holds their corner then. A panel keeps `surface.radius`, the square
// edge of the bar it is attached to, and a tooltip its own small corner.
var GLASS_CORNERS = ["menu.radius", "dialog.radius", "popover.radius", "osd.radius"];
var GLASS_RADIUS = "radius.glass";

// Whether a surface whose own VGlass choice is OPTIN draws glass under
// VALUES, the accepted Appearance values: `glass` "on" or "off" decides for
// every surface, and unset leaves it to OPTIN. The shared GlassSurface and
// the layer's window glass both ask this, so the two cannot differ.
function glassOn(values, optIn) {
    return values.glass === "on" || (values.glass !== "off" && optIn === true);
}

// Why VALUE cannot be the user's KEY of APPEARANCE, as a keyed line, or "".
function appearanceRefusal(key, value) {
    if (!hasOwn(APPEARANCE, key))
        return "refused: appearance=" + key + " unknown";
    var member = APPEARANCE[key];
    var want;
    switch (member.type) {
    case "length":
    case "number":
        if (member.hyprland !== undefined && value === "hyprland")
            return "";
        if (typeof value === "number" && isFinite(value) && value >= member.min && value <= member.max
            && (member.type !== "length" || Number.isInteger(value)))
            return "";
        want = (member.type === "length" ? "whole " : "") + member.min + ".." + member.max + (member.hyprland !== undefined ? "|hyprland" : "");
        break;
    case "flag":
        if (member.only !== undefined ? value === member.only : typeof value === "boolean")
            return "";
        want = member.only !== undefined ? String(member.only) : "boolean";
        break;
    case "choice":
        if (member.options.indexOf(value) !== -1)
            return "";
        want = member.options.join("|");
        break;
    case "family":
        if (typeof value === "string" && value !== "" && value.length <= FAMILY_MAX && value.trim() === value && !FAMILY_REFUSED.test(value))
            return "";
        want = "family";
        break;
    default:
        throw new Error("theme: appearance member " + key + " has unknown type " + member.type);
    }
    return "refused: " + key + "=" + JSON.stringify(value) + " want=" + want;
}

// THEME, an accept or defaults answer, under USER, shell.json `appearance`:
// { ok: true, values, appearance, refusals } or the resolver's refusal.
// Each member APPEARANCE refuses is left out and listed in `refusals` as
// { key, line }, so it shows as Set by theme. The user's values join the
// theme's overrides, the user's winning, and resolve once, so every token
// that references a changed token follows it; with no user token the
// theme's own values answer unchanged. While the user's `glass` is on,
// each corner of GLASS_CORNERS that would be 0, by the user's corner radius
// or else by the theme, takes the theme's GLASS_RADIUS, and one above 0
// stands. A user's 0 is rounded too: nothing tells it from a square
// theme's. `appearance` is { values, the accepted members; theme, what each
// member shows while the user sets none; sources, `theme`, `user`,
// `hyprland` or `surface` per member; hyprland, whether the layer writes
// each group a member decides }.
function withAppearance(tokens, theme, user) {
    var given = isPlainObject(user) ? user : {};
    var values = {};
    var refusals = [];
    Object.keys(given).forEach(function (key) {
        var line = appearanceRefusal(key, given[key]);
        if (line === "")
            values[key] = given[key];
        else
            refusals.push({ key: key, line: line });
    });
    var themeScale = valueAt(theme.values, MOTION_SCALE);
    var shown = {
        motion: themeScale > 0,
        motionStyle: valueAt(theme.values, "hyprland.motion.preset"),
        motionSpeed: themeScale > 0 ? 1 / themeScale : 1
    };
    var stated = {};
    var sources = {};
    var hyprland = {};
    Object.keys(APPEARANCE).forEach(function (key) {
        var member = APPEARANCE[key];
        if (member.theme !== undefined)
            shown[key] = valueAt(theme.values, member.theme);
        sources[key] = !hasOwn(values, key) ? (member.unset || "theme") : member.hyprland !== undefined && values[key] === "hyprland" ? "hyprland" : "user";
        if (member.hyprland !== undefined)
            hyprland[member.hyprland] = sources[key] !== "hyprland";
        if (member.targets !== undefined && sources[key] === "user")
            member.targets.forEach(function (target) { stated[target[0]] = member.type === "family" ? values[key] : values[key] * APPEARANCE_RATIOS[target[1]]; });
    });
    if (glassOn(values, false))
        GLASS_CORNERS.forEach(function (path) {
            if ((hasOwn(stated, path) ? stated[path] : valueAt(theme.values, path)) === 0)
                stated[path] = valueAt(theme.values, GLASS_RADIUS);
        });
    // Window glass is Hyprland's windows taking glass as a surface does,
    // their own choice being `windowGlass`.
    hyprland.glass = glassOn(values, values.windowGlass === true);
    // Glow follows window glass: off whenever window glass is off.
    hyprland.glow = hyprland.glass && values.windowGlow === true;
    // The shell's own layers and popups take the compositor's blur while
    // every surface draws glass, their own choice being none: the blur a
    // GlassSurface shows through is the compositor's. Written with window
    // glass, which is on whenever this is.
    hyprland.surfaceBlur = glassOn(values, false);
    var moving = hasOwn(values, "motion") ? values.motion : themeScale > 0;
    if (!moving && hasOwn(values, "motion"))
        stated[MOTION_SCALE] = 0;
    else if (moving && hasOwn(values, "motionSpeed"))
        stated[MOTION_SCALE] = 1 / values.motionSpeed;
    else if (moving && themeScale === 0)
        stated[MOTION_SCALE] = 1;
    if (hasOwn(values, "motionStyle")) {
        stated["hyprland.motion.preset"] = values.motionStyle;
        stated["motion.easing.standard"] = MOTION_STYLES[values.motionStyle].standard;
        stated["motion.easing.emphasized"] = MOTION_STYLES[values.motionStyle].emphasized;
    }
    var resolved = { ok: true, values: theme.values };
    if (Object.keys(stated).length > 0) {
        var overrides = {};
        Object.keys(theme.overrides).forEach(function (path) { overrides[path] = theme.overrides[path]; });
        Object.keys(stated).forEach(function (path) { overrides[path] = stated[path]; });
        resolved = resolve(tokens, overrides);
        if (!resolved.ok)
            return resolved;
    }
    return { ok: true, values: resolved.values, appearance: { values: values, theme: shown, sources: sources, hyprland: hyprland }, refusals: refusals };
}

function frozen(value) {
    if (value !== null && typeof value === "object")
        Object.keys(value).forEach(function (key) { frozen(value[key]); });
    return Object.freeze(value);
}

// What Theme publishes for ACCEPTED, an accept or defaults answer, under
// TEXT, shell.json `appearance` as JSON text or "" for none: { values,
// appearance, logs }. `appearance` is withAppearance's, deep-frozen; `logs`
// are the lines to log, one per refused member, and the resolver's refusal,
// after which the theme alone is drawn.
function published(tokens, accepted, text) {
    var logs = [];
    var result = withAppearance(tokens, accepted, text === "" ? {} : JSON.parse(text));
    if (!result.ok) {
        logs.push(refusalLine(result).replace(/^theme: /, "appearance: ") + "; drawing the theme alone");
        result = withAppearance(tokens, accepted, {});
    }
    result.refusals.forEach(function (refused) { logs.push("appearance: " + refused.line); });
    return { values: result.values, appearance: frozen(JSON.parse(JSON.stringify(result.appearance))), logs: logs };
}
