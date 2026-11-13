#!/usr/bin/env node
// Check that shipped and catalogued theme text stays readable.
//
// Usage:
//   scripts/check-theme-contrast.js [THEMES_DIR]
//
// THEMES_DIR defaults to this repository's themes/. The check judges every
// direct package except ThemeLogic.RESERVED_DIRECTORIES, then every
// themes/catalog/index.json entry, with its terminal.json when it has one.
// It prints:
//   ok       <name>
//   ok       catalog/<name>
//   short    catalog/<name>: <text> on <surface> ratio=<r> floor=4.5
//   short    <name>: notifications.text.link on notifications.card.fill over <wallpaper> ratio=<r> floor=4.5
//   short    <name>: tooltip.detail on glass.fill solid ratio=<r> floor=4.5
//   short    <name>: jarvis.icon.on on jarvis.plate.card.fill over <wallpaper> ratio=<r> floor=4.5
//   short    <name>: jarvis.answer.tinted.ink on jarvis.answer.tinted.hoverFill over jarvis.plate.card.fill over <wallpaper> ratio=<r> floor=4.5
//   short    <name>: jarvis.ink.words at jarvis.words.oldest on jarvis.plate.card.fill over <wallpaper> ratio=<r> floor=4.5
//   order    catalog/<name>: <stronger> ratio=<r> below <weaker> ratio=<r>
//   refused  catalog/<name>: <refusal>
// The text hierarchy, each against color.background: color.textHeading is
// at least as strong as color.text, and color.textMuted at least as strong
// as color.textFaint. A readability override that lifts palette.foreground
// past the heading, or fades muted text below faint text, breaks it.
// The terminal's six colours and their bright forms are text, each against
// palette.background, the terminal's background; color0, color7, color8 and
// color15 also fill and dim, so they keep their source values.
// A notice's page link is text on the notifications' glass card, whose look
// the theme's accent and mode reach: judged over black and white, the
// darkest and lightest wallpaper pixels the card can lie over.
// A tooltip's text is judged on the fill its glass draws solid, VGlass's
// fill made opaque and lifted, which the theme's raised surface reaches.
// Jarvis's overlay draws every line and icon on a glass plate of its own
// look, which the theme's accent and mode reach: each ink is judged on the
// card's fill over black and white, a caption line at its line's opacity
// and an answer's label on each of the answer's own fills, at rest, under
// the pointer and pressed, over the card. The confirming answer stands on
// the theme's accent. An icon button draws no fill of its own, so its
// glyph stands on the capsule, which is the card's fill. The lens draws
// the fill alone inside a plate's band, where every line stands
// (scripts/qml-tests/tst_jarvis_plates.qml).
// Exit 0: every theme is readable. Exit 1: a shortfall, a hierarchy break
// or a refusal was reported. Exit 2: bad invocation or a file cannot be read.
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const repo = path.join(__dirname, "..");
const logic = load(path.join(repo, "shell", "Commons", "ThemeLogic.js"));
const tokens = load(path.join(repo, "shell", "Commons", "Tokens.js")).TOKENS;
const notifications = load(path.join(repo, "shell", "plugins", "vgs.notifications", "Appearance.js"));
const glass = load(path.join(repo, "shell", "Commons", "Glass.js"));
const jarvis = load(path.join(repo, "shell", "plugins", "vgs.jarvis", "Appearance.js"));

function unreadable(file, cause) {
    console.error(`check-theme-contrast: unreadable: path=${file} error=${cause}`);
    process.exit(2);
}

function usage(detail) {
    console.error(`check-theme-contrast: refused: ${detail}`);
    process.exit(2);
}

function readFile(file) {
    try {
        return fs.readFileSync(file, "utf8");
    } catch (e) {
        unreadable(file, e.code || e.message);
    }
}

function packageDirs(base) {
    let entries;
    try {
        entries = fs.readdirSync(base, { withFileTypes: true });
    } catch (e) {
        unreadable(base, e.code || e.message);
    }
    return entries
        .filter(entry => entry.isDirectory() && !logic.RESERVED_DIRECTORIES.includes(entry.name))
        .map(entry => entry.name)
        .sort((a, b) => a < b ? -1 : a > b ? 1 : 0);
}

function ratioText(value) {
    if (value === null) return "translucent";
    return (Math.floor(value * 100) / 100).toFixed(2);
}

// The text hierarchy's pairs: the role that must be at least as strong
// first.
const HIERARCHY = [
    ["color.textHeading", "color.text"],
    ["color.textMuted", "color.textFaint"]
];

// The contrast of ROLE on color.background, null when either is
// translucent; readabilityShortfalls already reports a translucent role.
function backgroundRatio(values, role) {
    const text = logic.parseColor(logic.valueAt(values, role));
    const surface = logic.parseColor(logic.valueAt(values, "color.background"));
    if (text === null || surface === null || text.a < 1 || surface.a < 1) return null;
    return logic.contrastRatio(text, surface);
}

const TERMINAL_TEXT_SLOTS = [1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14].map(index => `color${index}`);

function terminalShortfalls(values, slots) {
    const surface = logic.parseColor(logic.valueAt(values, "palette.background"));
    const out = [];
    for (const slot of TERMINAL_TEXT_SLOTS) {
        const ratio = logic.contrastRatio(logic.parseColor(slots[slot]), surface);
        if (ratio < logic.READABILITY_FLOOR)
            out.push({ text: `terminal.${slot}`, surface: "palette.background", ratio, floor: logic.READABILITY_FLOOR });
    }
    return out;
}

const NOTICE_WALLPAPERS = ["#000000", "#ffffff"];

// The notice link's shortfalls on its card in the notifications look
// LOOK resolves to.
function noticeLinkShortfalls(look) {
    const out = [];
    for (const wallpaper of NOTICE_WALLPAPERS) {
        const card = logic.overlay(logic.parseColor(look.card.fill), logic.parseColor(wallpaper));
        const ratio = logic.contrastRatio(logic.overlay(logic.parseColor(look.text.link), card), card);
        if (ratio < logic.READABILITY_FLOOR)
            out.push({ text: "notifications.text.link", surface: `notifications.card.fill over ${wallpaper}`, ratio, floor: logic.READABILITY_FLOOR });
    }
    return out;
}

// Each ink Jarvis's overlay draws on a plate, as its path in the look,
// with the path of the opacity its line draws at and of the fill that
// lies between it and the card, where it has one. The line leaving the
// caption fades out from `words.oldest` and is not a line to read.
const JARVIS_INKS = [
    ["ink.state"], ["ink.title"], ["ink.action"], ["ink.link"], ["ink.question"], ["ink.path"], ["ink.payload"],
    ["ink.words", "words.newest"], ["ink.words", "words.middle"], ["ink.words", "words.oldest"],
    ["icon.rest"], ["icon.active"], ["icon.on"],
    ["answer.quiet.ink", null, "answer.quiet.fill"], ["answer.quiet.ink", null, "answer.quiet.hoverFill"], ["answer.quiet.ink", null, "answer.quiet.pressedFill"],
    ["answer.tinted.ink", null, "answer.tinted.fill"], ["answer.tinted.ink", null, "answer.tinted.hoverFill"], ["answer.tinted.ink", null, "answer.tinted.pressedFill"]
];

// The shortfalls of Jarvis's inks on their plates in the look LOOK
// resolves to.
function jarvisShortfalls(look) {
    const out = [];
    for (const wallpaper of NOTICE_WALLPAPERS) {
        const card = logic.overlay(logic.parseColor(look.plate.card.fill), logic.parseColor(wallpaper));
        for (const [ink, opacity, fill] of JARVIS_INKS) {
            const ground = fill ? logic.overlay(logic.parseColor(logic.valueAt(look, fill)), card) : card;
            const drawn = logic.parseColor(logic.valueAt(look, ink));
            if (opacity) drawn.a *= logic.valueAt(look, opacity);
            const ratio = logic.contrastRatio(logic.overlay(drawn, ground), ground);
            if (ratio < logic.READABILITY_FLOOR)
                out.push({ text: `jarvis.${ink}` + (opacity ? ` at jarvis.${opacity}` : ""),
                    surface: (fill ? `jarvis.${fill} over ` : "") + `jarvis.plate.card.fill over ${wallpaper}`, ratio, floor: logic.READABILITY_FLOOR });
        }
    }
    return out;
}

function hierarchyBreaks(values) {
    const out = [];
    for (const [stronger, weaker] of HIERARCHY) {
        const high = backgroundRatio(values, stronger);
        const low = backgroundRatio(values, weaker);
        if (high !== null && low !== null && high < low) out.push({ stronger, high, weaker, low });
    }
    return out;
}

// Judge the package in DIR: its theme.json, and its terminal.json when
// present.
function checkPackage(label, dir) {
    const accepted = logic.accept(tokens, readFile(path.join(dir, "theme.json")));
    if (!accepted.ok) {
        console.log(`refused  ${label}: ${logic.refusalLine(accepted)}`);
        return 1;
    }
    const terminalFile = path.join(dir, "terminal.json");
    const terminal = logic.acceptTerminal(fs.existsSync(terminalFile) ? readFile(terminalFile) : undefined);
    if (!terminal.ok) {
        console.log(`refused  ${label}: ${logic.refusalLine(terminal)}`);
        return 1;
    }
    const look = logic.acceptAppearance(notifications.TOKENS, notifications.LIGHT, accepted.values);
    if (!look.ok) {
        console.log(`refused  ${label}: notifications ${logic.refusalLine(look)}`);
        return 1;
    }
    const overlay = logic.acceptAppearance(jarvis.TOKENS, jarvis.LIGHT, accepted.values);
    if (!overlay.ok) {
        console.log(`refused  ${label}: jarvis ${logic.refusalLine(overlay)}`);
        return 1;
    }
    const vglass = logic.acceptAppearance(glass.TOKENS, glass.LIGHT, accepted.values);
    if (!vglass.ok) {
        console.log(`refused  ${label}: glass ${logic.refusalLine(vglass)}`);
        return 1;
    }
    const shortfalls = logic.readabilityShortfalls(accepted.values, vglass.values);
    if (terminal.slots !== null)
        shortfalls.push(...terminalShortfalls(accepted.values, terminal.slots));
    shortfalls.push(...noticeLinkShortfalls(look.values));
    shortfalls.push(...jarvisShortfalls(overlay.values));
    const breaks = hierarchyBreaks(accepted.values);
    if (shortfalls.length === 0 && breaks.length === 0) {
        console.log(`ok       ${label}`);
        return 0;
    }
    for (const shortfall of shortfalls) {
        console.log(`short    ${label}: ${shortfall.text} on ${shortfall.surface} ratio=${ratioText(shortfall.ratio)} floor=${shortfall.floor}`);
    }
    for (const broken of breaks) {
        console.log(`order    ${label}: ${broken.stronger} ratio=${ratioText(broken.high)} below ${broken.weaker} ratio=${ratioText(broken.low)}`);
    }
    return 1;
}

function checkCatalog(themesDir) {
    const catalogDir = path.join(themesDir, "catalog");
    const indexFile = path.join(catalogDir, "index.json");
    if (!fs.existsSync(indexFile)) return 0;
    const judged = logic.acceptCatalogIndex(tokens, readFile(indexFile));
    if (!judged.ok) {
        console.log(`refused  catalog/index.json: ${logic.refusalLine(judged)}`);
        return 1;
    }
    let findings = 0;
    for (const entry of judged.entries) {
        findings += checkPackage(`catalog/${entry.name}`, path.join(catalogDir, entry.name));
    }
    return findings;
}

function main() {
    const args = process.argv.slice(2);
    if (args.includes("--help")) {
        process.stdout.write(fs.readFileSync(__filename, "utf8").split("\n").slice(0, 40).join("\n") + "\n");
        return 0;
    }
    if (args.length > 1) usage("arguments=too-many");
    if (args.length === 1 && args[0].startsWith("-")) usage(`argument=${args[0]}`);
    const themesDir = path.resolve(args[0] || path.join(repo, "themes"));
    let findings = 0;
    for (const name of packageDirs(themesDir)) {
        findings += checkPackage(name, path.join(themesDir, name));
    }
    findings += checkCatalog(themesDir);
    return findings === 0 ? 0 : 1;
}

process.exit(main());
