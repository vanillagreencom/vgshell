#!/usr/bin/env node
// The theme judge, shell/Commons/ThemeLogic.js, against the shipped token
// table, shell/Commons/Tokens.js. Every expected value below was computed by
// hand from the expression it names, never read from the judge.
//
// The controls at the end edit a copy of the judge, one rule at a time, and
// require this suite to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const repo = path.join(__dirname, "..");
const judgeFile = path.join(__dirname, "..", "shell", "Commons", "ThemeLogic.js");
const TOKENS = load(path.join(__dirname, "..", "shell", "Commons", "Tokens.js")).TOKENS;

const at = (tree, dotted) => dotted.split(".").reduce((node, key) => node[key], tree);
const document = tokens => JSON.stringify({ schemaVersion: 1, name: "probe", tokens: tokens });
const documentWith = fields => JSON.stringify(Object.assign({ schemaVersion: 1, name: "probe", tokens: {} }, fields));
const TERMINAL_SLOTS = Object.fromEntries(Array.from({ length: 16 }, (_, index) => [`color${index}`, "#000000"]));

// Resolved defaults, by token: the expression and the arithmetic.
const DEFAULTS = [
    ["control.minWidth", 16],
    ["control.maxWidth", 480],
    ["field.minWidth", 128],
    ["scheme.mode", "dark"],
    ["voiceBubble.maxWidth", 480],
    ["voiceBubble.margin", 12],
    ["voiceBubble.gap", 12],
    ["voiceBubble.textLines", 3],
    ["palette.accent", "#ff5a36ff"],
    // mix(#000000, #d7d7d9, 0.05): 215 * 0.05 = 10.75, 217 * 0.05 = 10.85
    ["color.surface", "#0b0b0bff"],
    // mix(#000000, #d7d7d9, 0.19): 215 * 0.19 = 40.85, 217 * 0.19 = 41.23
    ["color.border", "#292929ff"],
    // mix(#d7d7d9, #000000, 0.21): 215 * 0.79 = 169.85, 217 * 0.79 = 171.43
    ["color.textMuted", "#aaaaabff"],
    // mix(#d7d7d9, contrast(#000000) = #ffffff, 0.55): 215 + 40 * 0.55 = 237, 217 + 38 * 0.55 = 237.9
    ["color.textHeading", "#ededeeff"],
    // mix(#ff5a36, #d7d7d9, 0.18): 255 - 40 * 0.18 = 247.8, 90 + 125 * 0.18 = 112.5, 54 + 163 * 0.18 = 83.34
    ["color.accentHover", "#f87153ff"],
    // The luminance of #ff5a36 is 0.29, nearer white than black in contrast.
    ["color.onAccent", "#000000ff"],
    // alpha(#ff5a36, 0.35): 255 * 0.35 = 89.25
    ["color.selection", "#ff5a3659"],
    ["color.dangerSubtle", "#f43f5e24"],
    // A badge's text: its role moved 0.28 toward contrast(#000000) =
    // #ffffff. mix(#b4c96f, #ffffff, 0.28): 180 + 75 * 0.28 = 201,
    // 201 + 54 * 0.28 = 216.12, 111 + 144 * 0.28 = 151.32.
    ["badge.tone.success.foreground", "#c9d897ff"],
    // mix(#aaaaab, #ffffff, 0.1): 170 + 85 * 0.1 = 178.5, 171 + 84 * 0.1 = 179.4.
    ["badge.tone.neutral.foreground", "#b3b3b3ff"],
    ["space.xxs", 2],
    ["space.sm", 6],
    ["space.xxxl", 32],
    ["radius.md", 0],
    ["radius.glass", 16],
    ["motion.duration.normal", 150],
    ["motion.easing.standard", "outCubic"],
    // The list motion: fast for travel and resize, normal for the fade, and
    // mul(250, 1.2) = 300 for a row's entrance; the rise is space.sm.
    ["motion.list.travel.duration", 100],
    ["motion.list.travel.easing", "outQuint"],
    ["motion.list.resize.duration", 100],
    ["motion.list.fade.duration", 150],
    ["motion.list.enter.duration", 300],
    ["motion.list.enter.easing", "outQuint"],
    ["motion.list.stagger", 18],
    ["motion.list.staggerRows", 8],
    ["motion.list.rise", 6],
    ["motion.surface.resize.duration", 300],
    ["motion.surface.resize.easing", "outCubic"],
    ["motion.flyout.travel.duration", 100],
    ["motion.flyout.travel.easing", "outCubic"],
    ["motion.flyout.slide", 12],
    ["hyprland.border.size", 2],
    ["hyprland.window.radius", 0],
    ["hyprland.window.roundingPower", 2],
    // Group tabs take the window radius until a user's corner radius sets
    // half of it.
    ["hyprland.window.groupRadius", 0],
    ["hyprland.motion.preset", "smooth"],
    ["hyprland.shadow.color", "#0000008c"],
    // Black mixed 0.18 toward #ff5a36 (45.9, 16.2, 9.72) and 0.1 toward
    // #d7d7d9 (21.5, 21.5, 21.7); inactive is black at alpha 0.
    ["hyprland.glow.color", "#2e100aff"],
    ["hyprland.glow.colorEnd", "#161616ff"],
    ["hyprland.glow.angle", 90],
    ["hyprland.glow.inactive", "#00000000"],
    ["hyprland.glow.range", 40],
    ["hyprland.glow.renderPower", 4],
    // mul(15, 2.27) = 34.05, mul(15, 1.33) = 19.95, mul(15, 1.2) = 18, mul(15, 1.07) = 16.05,
    // mul(15, 0.87) = 13.05, mul(15, 0.8) = 12, mul(15, 0.73) = 10.95
    ["text.display.size", 34],
    ["text.h1.size", 24],
    ["text.h2.size", 20],
    ["text.windowTitle.size", 18],
    ["text.h3.size", 16],
    ["text.body.size", 15],
    // Line boxes on the 4 px grid: 15 * 1.6 = 24, 16 * 1.5 = 24, 18 * 1.333 = 24, 20 * 1.4 = 28.
    ["text.body.lineHeight", 1.6],
    ["stack.titleSpace", 1],
    ["text.h3.lineHeight", 1.5],
    ["text.windowTitle.lineHeight", 1.333],
    ["text.h2.lineHeight", 1.4],
    ["text.tooltip.size", 12],
    ["text.tooltip.family", "Inter Variable"],
    ["text.hint.size", 13],
    ["text.code.size", 13],
    ["text.code.lineHeight", 1.5],
    ["text.bar.size", 12],
    ["text.bar.lineHeight", 1],
    // Chrome is 12 px, 15 * 0.8, and a key/value value 13 px, 15 * 0.87
    // rounded: capitals within a pixel of each other's height.
    ["text.label.size", 12],
    ["text.kbd.size", 11],
    ["text.keyHint.size", 12],
    ["text.button.size", 12],
    ["text.eyebrow.size", 12],
    ["text.value.size", 13],
    ["text.value.family", "Inter Variable"],
    ["text.eyebrow.uppercase", true],
    ["text.eyebrow.color", "#ff5a36ff"],
    ["text.body.family", "Inter Variable"],
    ["text.display.family", "Inter Variable"],
    ["text.label.family", "JetBrains Mono"],
    ["text.bar.family", "JetBrains Mono"],
    ["text.button.family", "JetBrains Mono"],
    ["text.eyebrow.family", "JetBrains Mono"],
    ["text.code.family", "JetBrains Mono"],
    ["font.family.sans", "Inter Variable"],
    ["font.family.caps", "JetBrains Mono"],
    ["bar.height", 28],
    ["bar.item.height", 24],
    ["bar.item.icon", 16],
    ["bar.onActive", "#000000ff"],
    ["bar.item.paddingX", 8],
    ["inset.cornerStep", 4],
    ["bar.item.gap", 4],
    // The bar separator: alpha(#d7d7d9, 0.2), 255 * 0.2 = 51, a 12 px line.
    ["bar.spacer.line", "#d7d7d933"],
    ["bar.spacer.height", 12],
    // Stacked readings: 24 * 0.4 = 9.6, a 10 px text, on 24 * 0.48 = 11.52,
    // 12 px lines, two of them the item's 24 px.
    ["bar.stacked.size", 10],
    ["bar.stacked.lineHeight", 12],
    // Each stacked line's icon at the line's 10 px text, drawn at 1 px.
    ["bar.stacked.icon", 10],
    ["bar.stacked.iconStroke", 1],
    ["bar.scroll.fade", 12],
    ["bar.scroll.hold", 400],
    // The control and row rhythm, Radix Themes' button sizes on the 4 px
    // unit: 24, 32 and 40 px controls with mul(4, 2) = 8, mul(4, 3) = 12
    // and mul(4, 4) = 16 a side and mul(4, 1) = 4, 8 and mul(4, 3) = 12
    // icon gaps; mul(4, 3) = 12 for a row's padding and its label gap,
    // 140 px labels, 17 characters of the 12 px label role, mul(4, 1) = 4
    // between lines. Rows keep their own 36 and 56 px heights.
    ["size.control.sm", 24],
    ["size.control.md", 32],
    ["size.control.lg", 40],
    ["control.paddingX", 12],
    ["control.gap", 8],
    ["control.sm.paddingX", 8],
    ["control.sm.gap", 4],
    ["control.lg.paddingX", 16],
    ["control.lg.gap", 12],
    ["row.paddingX", 12],
    ["row.gap", 12],
    ["row.height", 36],
    ["row.twoLineHeight", 56],
    ["row.labelWidth", 140],
    ["row.lineGap", 4],
    ["stack.row", 4],
    ["stack.group", 12],
    ["stack.page", 16],
    ["stack.section", 24],
    ["stack.heading", 32],
    ["stack.inline", 8],
    ["button.paddingX", 12],
    ["textField.paddingX", 10],
    ["textField.height", 32],
    ["segmented.height", 32],
    ["segmented.paddingX", 12],
    // A tile holds a 20 px icon over a label line: mul(40, 1.6) = 64.
    ["tileGroup.height", 64],
    ["tabs.paddingX", 12],
    ["listItem.paddingX", 12],
    ["menu.item.paddingX", 12],
    ["field.paddingX", 0],
    ["field.labelWidth", 140],
    ["field.labelGap", 12],
    // An input boundary: the raised surface's colour, mix(#000000,
    // #d7d7d9, 0.075) = 16.125, moved halfway toward white,
    // contrast(#000000): 16.125 + 0.5 * 238.875 = 135.56. The off track
    // moves it 0.46 instead, 125.99, then 0.08 toward black: 115.91; the
    // knob on it is the white that contrasts with it best.
    ["color.borderControl", "#888888ff"],
    ["checkbox.borderColor", "#888888ff"],
    ["toggle.off", "#747474ff"],
    ["toggle.knobOff", "#ffffffff"],
    ["toggle.size.sm.width", 28],
    ["toggle.size.sm.height", 16],
    ["toggle.size.md.width", 36],
    ["toggle.size.md.height", 20],
    ["badge.size.sm.height", 20],
    ["badge.size.sm.paddingX", 6],
    ["badge.size.md.height", 24],
    ["badge.gap", 4],
    ["badge.size.md.paddingX", 8],
    ["sectionHeader.paddingBottom", 8],
    ["codeLine.padding", 8],
    ["kbd.paddingX", 6],
    ["kbd.height", 20],
    ["tooltip.paddingX", 8],
    ["tooltip.paddingY", 6],
    ["tooltip.maxWidth", 280],
    ["inset.window", 16],
    ["inset.dialog", 16],
    ["inset.popover", 12],
    // A full-screen overlay's chrome: space.xxxl, 4 * 8.
    ["inset.overlay", 32],
    ["popover.padding", 12],
    // A menu entry's fill rounds with the menu, square by default.
    ["menu.item.radius", 0],
    ["groupList.gap", 12],
    // A card: space.lg, 3 * 4, inside a 1 px outline, its lines
    // space.xs, 4, apart.
    ["card.padding", 12],
    ["card.gap", 4],
    ["card.borderWidth", 1],
    ["button.size.sm.paddingX", 8],
    ["button.size.sm.icon", 14],
    ["button.size.lg.gap", 12],
    ["menu.maxWidth", 360],
    ["tabs.gap", 8],
    // An on-screen level: mul(4, 3) = 12 padding and gaps, the 24 px
    // icon, a 144 px bar and labels up to 192 px, on the 4 px grid.
    ["osd.padding", 12],
    ["osd.gap", 12],
    ["osd.icon", 24],
    ["osd.barWidth", 144],
    ["osd.labelMaxWidth", 192],
    // It stands 16 grid steps, 64 px, above the free room's bottom and
    // shows for 1.2 s.
    ["osd.margin", 64],
    ["osd.duration", 1200],
    // A device's battery warns at a fifth of a charge and is in danger at
    // a tenth.
    ["deviceRow.battery.warning", 0.2],
    ["deviceRow.battery.danger", 0.1],
    ["voiceOrb.size", 96],
    ["voiceOrb.radius", 0.28],
    ["voiceOrb.gap", 0.045],
    ["voiceOrb.stroke", 1.5],
    ["voiceOrb.arcStroke", 0.75],
    ["voiceOrb.amplitude", 0.018],
    ["voiceOrb.waveCount", 3],
    ["voiceOrb.arcSpan", 2.4],
    ["voiceOrb.arcOpacity", 0.6],
    ["voiceOrb.attack", 70],
    ["voiceOrb.release", 250],
    ["voiceOrb.period", 6000],
    ["voiceOrb.tone.accent", "#ff5a36ff"],
    ["voiceOrb.tone.info", "#74a7f7ff"],
    ["voiceOrb.tone.success", "#b4c96fff"],
    ["voiceOrb.tone.warning", "#ffb000ff"],
    ["voiceOrb.tone.danger", "#f43f5eff"],
    ["voiceOrb.tone.muted", "#aaaaabff"],
    ["bar.item.iconGap", 8],
    // A window-like panel: 600 px wide, half its monitor tall, its top at
    // 0.2 of its monitor's height and at most 0.6 of it tall,
    // mul(4, 3) = 12 from a narrower monitor's sides.
    ["size.window.width", 600],
    ["size.window.heightShare", 0.5],
    ["size.window.topShare", 0.2],
    ["size.window.tallHeightShare", 0.6],
    ["size.window.gutter", 12],
    // Nine 36 px entries before a menu scrolls: mul(36, 9) = 324.
    ["menu.maxHeight", 324],
    // A menu entry's icon follows its 14 px text: mul(14, 0.8) = 11.2, 11.
    ["menu.item.icon", 11],
    ["menu.typeahead", 1000],
    ["menu.item.check", "#ff5a36ff"],
    // The scroll bar: 4 px thick, 2 px in, inside an 8 px gutter, a thumb
    // of at least 24 px, faded out 800 ms after the last scroll; the
    // content fades across a 32 px band.
    ["scrollArea.barWidth", 4],
    ["scrollArea.barInset", 2],
    ["scrollArea.gutter", 8],
    ["scrollArea.minThumb", 24],
    ["scrollArea.idleOpacity", 0],
    ["scrollArea.fadeDelay", 800],
    ["scrollArea.fadeHeight", 32],
    ["scrollArea.fade", 250],
    // A list row with a secondary line takes the row group's 56.
    ["listItem.twoLineHeight", 56],
    ["titleButton.gap", 4],
    ["titleButton.underline", 1],
    ["titleButton.underlineGap", 2],
    ["titleButton.hover", "#ff5a36ff"],
    // A row's action: the accent's text over a 1 px underline on hover,
    // 2 px under the baseline.
    ["rowAction.underline", 1],
    ["rowAction.underlineGap", 2],
    ["rowAction.tone.accent.foreground", "#ff5a36ff"],
    // Side-by-side actions one space step, space.lg = 12, apart; the
    // danger mark 14 px, 4 px before its text.
    ["rowAction.gap", 12],
    ["rowAction.icon", 14],
    ["rowAction.iconGap", 4],
    // The dialog: 360 px wide, mul(4, 4) = 16 padding and mul(4, 3) = 12
    // from the free area's edges, stack.group = 12 between its blocks and
    // mul(4, 2) = 8 between its actions; its card is the raised surface,
    // mix(#000000, #d7d7d9, 0.075): 215 * 0.075 = 16.125, 217 * 0.075 =
    // 16.275.
    ["dialog.width", 360],
    ["dialog.margin", 12],
    ["dialog.padding", 16],
    ["dialog.gap", 12],
    ["dialog.actionGap", 8],
    ["dialog.background", "#101010ff"],
    ["dialog.titleRole", "h3"],
    ["dialog.bodyRole", "body"],
    // The angled card: a 28 pixel lean and a 3 pixel selected
    // outline; its outline is borderStrong, mix(#000000, #d7d7d9, 0.27):
    // 215 * 0.27 = 58.05, 217 * 0.27 = 58.59, and textMuted under the
    // pointer; its wash the background at 0.42: 255 * 0.42 = 107.1, and at
    // half that under the pointer: 255 * 0.21 = 53.55.
    ["angledCard.skew", 28],
    ["angledCard.border", "#3a3a3bff"],
    ["angledCard.hoverBorder", "#aaaaabff"],
    ["angledCard.hoverDim", "#00000036"],
    ["angledCard.borderWidth", 1],
    ["angledCard.selectedBorder", "#ff5a36ff"],
    ["angledCard.selectedBorderWidth", 3],
    ["angledCard.dim", "#0000006b"],
    // The carousel: a 768 by 476 card on the grid and
    // 108 by 432 slices, overlapping by the card's 28 pixel lean; the
    // reference rail, 768 + 13 * (108 - 28) + 2 * 20 = 1848, its unit held
    // from 0.35 to 2, two cards built past the shown ones and a decode of
    // at most 2048; the rail moves over motion.duration.normal, 150 ms at
    // motion.scale 1.
    ["carousel.expandedWidth", 768],
    ["carousel.expandedHeight", 476],
    ["carousel.sliceWidth", 108],
    ["carousel.sliceHeight", 432],
    ["carousel.overlap", 28],
    ["carousel.referenceSteps", 13],
    ["carousel.referenceMargin", 20],
    ["carousel.minScale", 0.35],
    ["carousel.maxScale", 2],
    ["carousel.band", 2],
    ["carousel.decodeCap", 2048],
    ["carousel.duration", 150],
    // The scrim, #000000 at 0.6, over a black wallpaper is black, and
    // white contrasts with it. A failure line rests on the surface
    // #0b0b0b, luminance 0.0033, where the danger #f43f5e, luminance
    // 0.236, reads 5.36:1, (0.236 + 0.05) / (0.0033 + 0.05).
    ["carousel.backdrop", "#000000ff"],
    ["carousel.hintActive", "#ffffffff"],
    ["carousel.failurePlate", "#0b0b0bff"],
    ["carousel.hintDanger", "#f43f5eff"],
    // The accent #ff5a36, luminance 0.288, reads 6.76:1 on black.
    ["carousel.tabIndicator", "#ff5a36ff"],
    // A slice's name: h2, space.xxl 24 up the slice from its bottom edge,
    // white over black at full opacity blurred 4 pixels, dropped 2 pixels.
    ["carousel.sliceName.role", "h2"],
    ["carousel.sliceName.inset", 24],
    ["carousel.sliceName.foreground", "#ffffffff"],
    ["carousel.sliceName.shadow", "#000000ff"],
    ["carousel.sliceName.shadowOpacity", 1],
    ["carousel.sliceName.blur", 4],
    ["carousel.sliceName.shadowOffset", 2]
];

// A document that is accepted, and the values it must resolve to.
const ACCEPTED = [
    { tokens: { palette: { accent: "#123456", info: "#234567", success: "#345678", warning: "#456789", danger: "#56789a" }, color: { textMuted: "#6789ab" } }, want: [["voiceOrb.tone.accent", "#123456ff"], ["voiceOrb.tone.info", "#234567ff"], ["voiceOrb.tone.success", "#345678ff"], ["voiceOrb.tone.warning", "#456789ff"], ["voiceOrb.tone.danger", "#56789aff"], ["voiceOrb.tone.muted", "#6789abff"]] },
    { tokens: { motion: { scale: 0 }, voiceOrb: { attack: 90, release: 300, period: 4000 } }, want: [["voiceOrb.attack", 0], ["voiceOrb.release", 0], ["voiceOrb.period", 0]] },
    { tokens: { motion: { scale: 2 } }, want: [["voiceOrb.attack", 140], ["voiceOrb.release", 500], ["voiceOrb.period", 12000]] },
    { tokens: {}, want: [["palette.accent", "#ff5a36ff"]] },
    { tokens: { scheme: { mode: "light" } }, want: [["scheme.mode", "light"], ["palette.background", "#000000ff"]] },
    // A palette colour reaches every role derived from it; #7aa2f7 has
    // luminance 0.36, so the text on it is black.
    { tokens: { palette: { accent: "#7aa2f7" } }, want: [["color.accent", "#7aa2f7ff"], ["color.focus", "#7aa2f7ff"], ["bar.active", "#7aa2f7ff"], ["color.onAccent", "#000000ff"]] },
    // #1a1b26 has luminance 0.01, so the text on it is white.
    { tokens: { palette: { accent: "#1a1b26" } }, want: [["color.onAccent", "#ffffffff"]] },
    { tokens: { palette: { accent: "#abc" } }, want: [["color.accent", "#aabbccff"]] },
    { tokens: { color: { scrim: "#11223344" } }, want: [["color.scrim", "#11223344"]] },
    // A translucent fill is accepted where the text on it is stated too.
    { tokens: { bar: { active: "#ff5a3680", onActive: "#ffffff" } }, want: [["bar.active", "#ff5a3680"], ["bar.onActive", "#ffffffff"]] },
    // One component value changes, and the values derived from it.
    { tokens: { bar: { active: "#ffffff" } }, want: [["bar.active", "#ffffffff"], ["bar.onActive", "#000000ff"], ["color.accent", "#ff5a36ff"]] },
    { tokens: { space: { unit: 5 } }, want: [["space.xs", 5], ["space.sm", 8], ["space.xl", 20], ["bar.gap", 10], ["row.paddingX", 15], ["listItem.paddingX", 15], ["field.paddingX", 0], ["stack.row", 5], ["badge.size.sm.paddingX", 8], ["codeLine.padding", 10], ["kbd.paddingX", 8], ["control.paddingX", 15], ["control.sm.gap", 5], ["textField.paddingX", 13]] },
    // One shared token moves every control that follows the rhythm.
    { tokens: { control: { paddingX: 12, gap: 5 } }, want: [["button.paddingX", 12], ["textField.paddingX", 10], ["segmented.paddingX", 12], ["button.gap", 5], ["textField.gap", 5], ["listItem.gap", 5], ["menu.item.gap", 5], ["checkbox.gap", 5], ["bar.item.iconGap", 5], ["bar.item.paddingX", 8]] },
    // Control sizes move the controls and never the rows' density.
    { tokens: { size: { control: { md: 34, lg: 44 } } }, want: [["textField.height", 34], ["segmented.height", 34], ["menu.item.height", 36], ["menu.maxHeight", 324], ["row.height", 36], ["listItem.height", 36], ["listItem.twoLineHeight", 56]] },
    { tokens: { row: { height: 40, twoLineHeight: 60 } }, want: [["listItem.height", 40], ["listItem.twoLineHeight", 60], ["menu.item.height", 40], ["menu.maxHeight", 360], ["textField.height", 32]] },
    { tokens: { row: { paddingX: 16 } }, want: [["listItem.paddingX", 16], ["menu.item.paddingX", 16], ["field.paddingX", 0], ["button.paddingX", 12]] },
    { tokens: { field: { paddingX: 6 } }, want: [["field.paddingX", 6], ["listItem.paddingX", 12]] },
    // A menu entry's fill rounds with the menu, never with the small radius.
    { tokens: { radius: { sm: 6, md: 12 } }, want: [["menu.radius", 12], ["menu.item.radius", 12], ["listItem.radius", 6]] },
    // A group list's hairline is a tenth of the foreground: 0.1 * 255 = 25.5, 0x1a.
    { tokens: { palette: { foreground: "#ffffff" } }, want: [["groupList.divider", "#ffffff1a"]] },
    { tokens: { font: { size: 16 } }, want: [["text.body.size", 16], ["text.hint.size", 14], ["stack.titleSpace", 1]] },
    { tokens: { text: { body: { lineHeight: 2 } } }, want: [["stack.titleSpace", 1]] },
    { tokens: { stack: { titleSpace: "mul(1, 2)" } }, want: [["stack.titleSpace", 2]] },
    { tokens: { motion: { scale: 0 } }, want: [["motion.duration.fast", 0], ["motion.duration.slow", 0], ["motion.list.travel.duration", 0], ["motion.list.enter.duration", 0], ["motion.list.stagger", 0], ["motion.list.rise", 6]] },
    // The list motion follows the scale steps it names: fast at 60 travels
    // 60, and slow at 400 enters mul(400, 1.2) = 480.
    { tokens: { motion: { duration: { fast: 60, slow: 400 } } }, want: [["motion.list.travel.duration", 60], ["motion.list.resize.duration", 60], ["motion.list.enter.duration", 480]] },
    // The scale applies after a duration's own expression, so a theme that
    // states its own timing still goes still at 0 and doubles at 2.
    { tokens: { motion: { scale: 0, duration: { normal: 200 } } }, want: [["motion.duration.normal", 0]] },
    { tokens: { motion: { scale: 2, duration: { normal: 200 } } }, want: [["motion.duration.normal", 400], ["motion.duration.fast", 200]] },
    { tokens: { motion: { scale: 0.5 } }, want: [["motion.duration.fast", 50], ["motion.duration.slow", 125]] },
    // A duration that references another is scaled once: 100 * 2, not 100 * 2 * 2.
    { tokens: { motion: { scale: 2, duration: { normal: "{motion.duration.fast}" } } }, want: [["motion.duration.fast", 200], ["motion.duration.normal", 200]] },
    { tokens: { motion: { scale: 0.5, duration: { normal: "mul({motion.duration.fast}, 3)" } } }, want: [["motion.duration.fast", 50], ["motion.duration.normal", 150]] },
    // The range applies before the scale: 3000 * 4 publishes as 12000.
    { tokens: { motion: { scale: 4, duration: { slow: 3000 } } }, want: [["motion.duration.slow", 12000], ["motion.duration.fast", 400]] },
    { tokens: { radius: { md: 6.4 } }, want: [["radius.md", 6]] },
    { tokens: { radius: { md: "{radius.full}" }, hyprland: { window: { radius: 32 } } }, want: [["radius.md", 4096], ["hyprland.window.radius", 32]] },
    { tokens: { radius: { md: "mul({space.unit}, 1.5)" } }, want: [["radius.md", 6]] },
    { tokens: { hyprland: { border: { size: 4 }, window: { radius: 8, roundingPower: 3 }, motion: { preset: "snappy" }, shadow: { color: "#11223344" } } }, want: [["hyprland.border.size", 4], ["hyprland.window.radius", 8], ["hyprland.window.roundingPower", 3], ["hyprland.motion.preset", "snappy"], ["hyprland.shadow.color", "#11223344"]] },
    { tokens: { scheme: { mode: "light" }, palette: { background: "#f7f7f7" } }, want: [["hyprland.shadow.color", "#4545458c"]] },
    { tokens: { text: { body: { uppercase: true, family: "Inter", weight: 500 } } }, want: [["text.body.uppercase", true], ["text.body.family", "Inter"], ["text.body.weight", 500]] },
    { tokens: { text: { body: { uppercase: "{text.eyebrow.uppercase}" } } }, want: [["text.body.uppercase", true]] },
    // A dialog's roles name any role of `text`.
    { tokens: { dialog: { titleRole: "h2", bodyRole: "itemHint" } }, want: [["dialog.titleRole", "h2"], ["dialog.bodyRole", "itemHint"]] },
    { tokens: { motion: { easing: { standard: "linear" } } }, want: [["motion.easing.standard", "linear"]] },
    { tokens: { color: { surface: "mix( {palette.background} , alpha(#ffffff, 0.5), 0.5 )" } }, want: [["color.surface", "#808080bf"]] },
    { tokens: { palette: { accent: "contrastMix(#000,#fff,#fff,4.5)" } }, want: [["palette.accent", "#767676ff"]] },
    { tokens: { palette: { accent: "contrastMix(#fff,#000,#000,4.5)" } }, want: [["palette.accent", "#757575ff"]] },
    { tokens: { palette: { accent: "contrastMix(#000,#f00,#fff,3)" } }, want: [["palette.accent", "#ff0000ff"]] },
    { tokens: { palette: { accent: "contrastMix(#000,#fff,#fff,21)" } }, want: [["palette.accent", "#000000ff"]] },
    { tokens: { palette: { accent: "contrastMix(#000,#fff,#fff,1)" } }, want: [["palette.accent", "#ffffffff"]] },
    { tokens: { color: { surface: "mix(#000, mix(#000, mix(#000, mix(#000, mix(#000, mix(#000, #fff, 1), 1), 1), 1), 1), 1)" } }, want: [["color.surface", "#ffffffff"]] }
];

// A document that is refused: the raw text or the `tokens` tree, and the
// reason and token the refusal names.
const REFUSED = [
    { text: "{ nope", reason: "not-json", token: "" },
    { text: "[1]", reason: "not-object", token: "" },
    { text: "null", reason: "not-object", token: "" },
    { text: JSON.stringify({ foreground: "#123456" }), reason: "unknown-key", token: "", detail: "key=foreground" },
    { text: JSON.stringify({ name: "x", tokens: {} }), reason: "schema-version", token: "" },
    { text: JSON.stringify({ schemaVersion: 2, name: "x" }), reason: "schema-version", token: "" },
    { text: JSON.stringify({ schemaVersion: 1 }), reason: "name", token: "" },
    { text: JSON.stringify({ schemaVersion: 1, name: " " }), reason: "name", token: "" },
    { text: JSON.stringify({ schemaVersion: 1, name: "x", displayName: "" }), reason: "display-name", token: "", detail: 'got=""' },
    { text: JSON.stringify({ schemaVersion: 1, name: "x", displayName: " " }), reason: "display-name", token: "" },
    { text: JSON.stringify({ schemaVersion: 1, name: "x", displayName: 5 }), reason: "display-name", token: "", detail: "got=5" },
    { text: JSON.stringify({ schemaVersion: 1, name: "x", displayName: null }), reason: "display-name", token: "" },
    { text: JSON.stringify({ schemaVersion: 1, name: "x", displayName: ["X"] }), reason: "display-name", token: "" },
    { text: JSON.stringify({ schemaVersion: 1, name: "x", tokens: [] }), reason: "tokens", token: "" },
    { tokens: { palette: { acent: "#fff" } }, reason: "unknown-token", token: "palette.acent" },
    { tokens: { palette: { accent: { hover: "#fff" } } }, reason: "not-expression", token: "palette.accent" },
    { tokens: { palette: "#fff" }, reason: "group-expected", token: "palette" },
    { tokens: { palette: { accent: null } }, reason: "not-expression", token: "palette.accent" },
    { tokens: { palette: { accent: ["#fff"] } }, reason: "not-expression", token: "palette.accent" },
    { tokens: { text: { body: { uppercase: "true" } } }, reason: "not-expression", token: "text.body.uppercase" },
    { tokens: { palette: { accent: "#12345" } }, reason: "syntax", token: "palette.accent" },
    { tokens: { palette: { accent: "red" } }, reason: "syntax", token: "palette.accent" },
    { tokens: { palette: { accent: "mix(#000, #fff, 0.5" } }, reason: "syntax", token: "palette.accent" },
    { tokens: { palette: { accent: "#fff trailing" } }, reason: "syntax", token: "palette.accent" },
    { tokens: { palette: { accent: "mix(#000, #fff, " + "0".repeat(260) + ")" } }, reason: "too-long", token: "palette.accent" },
    { tokens: { palette: { accent: "mix(#000, mix(#000, mix(#000, mix(#000, mix(#000, mix(#000, mix(#000, mix(#000, #fff, 1), 1), 1), 1), 1), 1), 1), 1)" } }, reason: "too-deep", token: "palette.accent" },
    { tokens: { palette: { accent: "darken(#fff, 0.5)" } }, reason: "unknown-function", token: "palette.accent" },
    { tokens: { palette: { accent: "mix(#000, #fff)" } }, reason: "arity", token: "palette.accent" },
    { tokens: { palette: { accent: "{palette.acent}" } }, reason: "unknown-reference", token: "palette.accent" },
    { tokens: { palette: { accent: "{palette}" } }, reason: "unknown-reference", token: "palette.accent" },
    { tokens: { palette: { accent: "{color.accent}" } }, reason: "cycle", token: "palette.accent" },
    { tokens: { palette: { accent: "{palette.accent}" } }, reason: "cycle", token: "palette.accent" },
    { tokens: { radius: { md: "{palette.accent}" } }, reason: "type", token: "radius.md" },
    { tokens: { radius: { md: "#ffffff" } }, reason: "type", token: "radius.md" },
    { tokens: { radius: { md: true } }, reason: "type", token: "radius.md" },
    { tokens: { radius: { md: "{motion.scale}" } }, reason: "type", token: "radius.md" },
    { tokens: { palette: { accent: 4 } }, reason: "type", token: "palette.accent" },
    { tokens: { palette: { accent: "mul(#fff, 2)" } }, reason: "type", token: "palette.accent" },
    { tokens: { radius: { md: "mix(#000, #fff, 0.5)" } }, reason: "type", token: "radius.md" },
    { tokens: { radius: { md: "mul({space.unit}, {space.unit})" } }, reason: "type", token: "radius.md" },
    { tokens: { text: { body: { family: 4 } } }, reason: "type", token: "text.body.family" },
    { tokens: { text: { body: { family: " " } } }, reason: "type", token: "text.body.family" },
    { tokens: { radius: { md: -1 } }, reason: "range", token: "radius.md" },
    { tokens: { radius: { md: 5000 } }, reason: "range", token: "radius.md" },
    { tokens: { radius: { md: 33 } }, reason: "range", token: "hyprland.window.radius" },
    { tokens: { hyprland: { border: { size: 21 } } }, reason: "range", token: "hyprland.border.size" },
    { tokens: { hyprland: { window: { radius: 33 } } }, reason: "range", token: "hyprland.window.radius" },
    { tokens: { hyprland: { window: { roundingPower: 11 } } }, reason: "range", token: "hyprland.window.roundingPower" },
    { tokens: { hyprland: { motion: { preset: "bouncy" } } }, reason: "option", token: "hyprland.motion.preset" },
    { tokens: { hyprland: { gaps: 8 } }, reason: "unknown-token", token: "hyprland.gaps" },
    { tokens: { motion: { scale: 5 } }, reason: "range", token: "motion.scale" },
    { tokens: { text: { body: { weight: 50 } } }, reason: "range", token: "text.body.weight" },
    { tokens: { motion: { duration: { fast: 20000 } } }, reason: "range", token: "motion.duration.fast" },
    { tokens: { palette: { accent: "mix(#000, #fff, 1.5)" } }, reason: "range", token: "palette.accent" },
    { tokens: { palette: { accent: "alpha(#000, -0.5)" } }, reason: "range", token: "palette.accent" },
    { tokens: { palette: { accent: "contrastMix(#000,#fff,#fff,22)" } }, reason: "range", token: "palette.accent" },
    { tokens: { palette: { accent: "contrastMix(#000,#fff,#fff,0.5)" } }, reason: "range", token: "palette.accent" },
    { tokens: { palette: { accent: "contrastMix(#888,#999,#fff,4.5)" } }, reason: "contrast-unreachable", token: "palette.accent" },
    ...[0, 1, 2].map(index => ({
        tokens: { palette: { accent: `contrastMix(${["#000000ff", "#ffffffff", "#ffffffff"].map((color, at) => at === index ? color.slice(0, 7) + "80" : color).join(",")},4.5)` } },
        reason: "contrast-translucent", token: "palette.accent"
    })),
    { tokens: { color: { onAccent: "contrast(alpha({palette.accent}, 0.5))" } }, reason: "contrast-translucent", token: "color.onAccent" },
    // The default text on a fill derives from the fill, so a translucent
    // fill alone is refused where that default is evaluated.
    { tokens: { bar: { active: "#ff5a3680" } }, reason: "contrast-translucent", token: "bar.onActive" },
    { tokens: { carousel: { hintDanger: "readable({color.danger}, {color.scrim}, {carousel.hintActive})" } }, reason: "contrast-translucent", token: "carousel.hintDanger" },
    { tokens: { carousel: { failurePlate: "alpha({color.surface}, 0.5)" } }, reason: "contrast-translucent", token: "carousel.hintDanger" },
    { tokens: { motion: { easing: { standard: "bouncy" } } }, reason: "option", token: "motion.easing.standard" },
    { tokens: { scheme: { mode: "dim" } }, reason: "option", token: "scheme.mode" },
    { tokens: { dialog: { titleRole: "shout" } }, reason: "option", token: "dialog.titleRole" },
    { tokens: { stack: { titleSpace: 0.8 } }, reason: "range", token: "stack.titleSpace" },
    { tokens: { stack: { titleSpace: "{space.md}" } }, reason: "type", token: "stack.titleSpace" },
    { tokens: { stack: { group: "{stack.titleSpace}" } }, reason: "type", token: "stack.group" }
];

// A plugin's own table and its light overrides, the shape a plugin's
// appearance file exports. Every expected value is computed by hand.
const LOOK = {
    palette: { accent: { type: "color", value: "#000000" } },
    motion: { scale: { type: "number", value: 1, min: 0, max: 4 }, open: { type: "duration", value: 200 } },
    card: {
        fill: { type: "color", value: "#151515c7" },
        text: { type: "color", value: "#e8e8e8" },
        edge: { type: "color", value: "alpha({palette.accent}, 0.5)" },
        radius: { type: "length", value: 18 }
    }
};
const LOOK_LIGHT = { card: { fill: "#efefefcc", text: "#2a2a2a" } };
// A look that draws text: it holds the interface family and a title family
// that reads it, so the user's interface font reaches both.
const FONT_LOOK = Object.assign({}, LOOK, {
    font: { family: { sans: { type: "family", value: "Inter Variable" } } },
    card: Object.assign({}, LOOK.card, { title: { type: "family", value: "{font.family.sans}" } })
});
// A look that draws on the theme's raised surface: it holds the input and a
// fill that reads it.
const RAISED_LOOK = Object.assign({}, LOOK, {
    color: { surfaceRaised: { type: "color", value: "#000000" } },
    card: Object.assign({}, LOOK.card, { fill: { type: "color", value: "alpha({color.surfaceRaised}, 0.5)" } })
});
// The must-fail controls of the interface font check: a look that keeps a
// fixed family of its own, beside or in place of the input.
const FIXED_FAMILY_LOOKS = [
    ["a fixed family in place of the input", Object.assign({}, LOOK, { font: { family: { type: "family", value: "Liberation Sans" } } })],
    ["a fixed title family beside the input", Object.assign({}, FONT_LOOK, { card: Object.assign({}, LOOK.card, { title: { type: "family", value: "JetBrains Mono" } }) })]
];
const shellTheme = tokens => {
    const result = load(judgeFile).accept(TOKENS, document(tokens));
    assert.equal(result.ok, true, "shell document for an appearance row");
    return result.values;
};
const DARK_THEME = shellTheme({ palette: { accent: "#7aa2f7" } });
const LIGHT_THEME = shellTheme({ scheme: { mode: "light" }, palette: { accent: "#a8330a" } });
// Every shell token moves but the inputs LOOK holds; the plugin's values
// stay.
const UNRELATED_THEME = shellTheme({ palette: { accent: "#7aa2f7", foreground: "#ff00ff", background: "#00ff00" }, font: { size: 22, family: { mono: "Courier" } }, space: { unit: 7 }, radius: { md: 9 } });

// Accepted appearance rows: [label, table, light, theme, want].
const APPEARANCE_ACCEPTED = [
    ["dark mode keeps the table's own values and takes the accent", LOOK, LOOK_LIGHT, DARK_THEME, [["card.fill", "#151515c7"], ["card.text", "#e8e8e8ff"], ["palette.accent", "#7aa2f7ff"], ["card.edge", "#7aa2f780"], ["card.radius", 18], ["motion.open", 200]]],
    ["light mode applies the light overrides and the light accent", LOOK, LOOK_LIGHT, LIGHT_THEME, [["card.fill", "#efefefcc"], ["card.text", "#2a2a2aff"], ["card.edge", "#a8330a80"], ["card.radius", 18]]],
    ["unrelated shell tokens reach no plugin value", LOOK, LOOK_LIGHT, UNRELATED_THEME, [["card.fill", "#151515c7"], ["card.text", "#e8e8e8ff"], ["card.edge", "#7aa2f780"], ["card.radius", 18], ["motion.open", 200]]],
    ["the theme's motion scale reaches the plugin's durations", LOOK, LOOK_LIGHT, shellTheme({ motion: { scale: 0 } }), [["motion.open", 0], ["motion.scale", 0]]],
    ["the scale doubles the plugin's durations", LOOK, LOOK_LIGHT, shellTheme({ motion: { scale: 2 } }), [["motion.open", 400]]],
    ["the theme's interface family reaches the plugin's text", FONT_LOOK, {}, shellTheme({ font: { family: { sans: "Serif" } } }), [["font.family.sans", "Serif"], ["card.title", "Serif"]]],
    // alpha(#336699, 0.5): round(127.5) = 128 = 0x80.
    ["the theme's raised surface reaches a look that holds it", RAISED_LOOK, {}, shellTheme({ color: { surfaceRaised: "#336699" } }), [["color.surfaceRaised", "#336699ff"], ["card.fill", "#33669980"]]]
];

// Refused appearance rows: [label, table, light, theme, reason, token].
const APPEARANCE_REFUSED = [
    ["a table defect", { palette: { accent: { type: "colour", value: "#000" } }, motion: LOOK.motion }, {}, DARK_THEME, "appearance-table", ""],
    ["a palette with a second colour", Object.assign({}, LOOK, { palette: { accent: LOOK.palette.accent, foreground: { type: "color", value: "#fff" } } }), {}, DARK_THEME, "appearance-palette", "palette"],
    ["no palette", { motion: LOOK.motion, card: LOOK.card }, {}, DARK_THEME, "appearance-palette", "palette"],
    ["an accent that is no colour", Object.assign({}, LOOK, { palette: { accent: { type: "length", value: 1 } } }), {}, DARK_THEME, "appearance-palette", "palette"],
    ["light overrides that are no tree", LOOK, [], DARK_THEME, "appearance-light", ""],
    ["light overrides naming no token of the table", LOOK, { card: { glow: "#fff" } }, DARK_THEME, "unknown-token", "card.glow"],
    ["light overrides setting the accent", LOOK, { palette: { accent: "#fff" } }, DARK_THEME, "appearance-input", "palette.accent"],
    ["light overrides setting the scale", LOOK, { motion: { scale: 0 } }, DARK_THEME, "appearance-input", "motion.scale"],
    ["light overrides setting the interface family", FONT_LOOK, { font: { family: { sans: "Serif" } } }, DARK_THEME, "appearance-input", "font.family.sans"],
    ["light overrides setting the raised surface", RAISED_LOOK, { color: { surfaceRaised: "#ffffff" } }, DARK_THEME, "appearance-input", "color.surfaceRaised"],
    ["an interface family that is no family", Object.assign({}, LOOK, { font: { family: { sans: { type: "color", value: "#ffffff" } } } }), {}, DARK_THEME, "appearance-font", "font.family.sans"],
    ["an interface family that is a group", Object.assign({}, LOOK, { font: { family: { sans: { text: { type: "family", value: "Serif" } } } } }), {}, DARK_THEME, "appearance-font", "font.family.sans"],
    ["a theme without a mode", LOOK, LOOK_LIGHT, {}, "appearance-theme", "scheme.mode"],
    ["a theme without an accent", LOOK, LOOK_LIGHT, { scheme: { mode: "dark" }, motion: { scale: 1 } }, "appearance-theme", "palette.accent"],
    ["a theme without a scale", LOOK, LOOK_LIGHT, { scheme: { mode: "dark" }, palette: { accent: "#000000ff" } }, "appearance-theme", "motion.scale"],
    ["a theme without an interface family", LOOK, LOOK_LIGHT, { scheme: { mode: "dark" }, palette: { accent: "#000000ff" }, motion: { scale: 1 } }, "appearance-theme", "font.family.sans"],
    ["a theme without a raised surface", LOOK, LOOK_LIGHT, { scheme: { mode: "dark" }, palette: { accent: "#000000ff" }, motion: { scale: 1 }, font: { family: { sans: "Inter" } } }, "appearance-theme", "color.surfaceRaised"],
    // A light value is judged only where it applies, but its path is
    // judged in both modes.
    ["a light value of the wrong type in light mode", LOOK, { card: { radius: "#fff" } }, LIGHT_THEME, "type", "card.radius"]
];

// A table with one defect, and the text its report starts with.
const BAD_TABLES = [
    [{ palette: { accent: { type: "colour", value: "#fff" } } }, "palette.accent has unknown type"],
    [{ opacity: { disabled: { type: "number", value: 0.5 } } }, "opacity.disabled is a number without a range"],
    [{ motion: { scale: { type: "number", value: 1, min: 0, max: 4 } }, size: { panel: { sm: { type: "length", value: 1, min: "0" } } } }, "size.panel.sm.min must be a finite number"],
    [{ motion: { scale: { type: "number", value: 1, min: 0, max: 4 } }, size: { panel: { sm: { type: "length", value: 1, min: 4, max: 2 } } } }, "size.panel.sm.min must not be greater than max"],
    [{ scheme: { mode: { type: "choice", value: "dark" } } }, "scheme.mode is a choice without options"],
    [{ palette: { "on-accent": { type: "color", value: "#fff" } } }, "palette.on-accent is not a token name"],
    [{ palette: {} }, "group palette is empty"],
    [{ palette: { accent: "#fff" } }, "palette.accent is neither a group nor a token"],
    [{ palette: { accent: { type: "color", value: "#fff" } } }, "motion.scale must be a number token"],
    [{ motion: { scale: { type: "length", value: 1 } } }, "motion.scale must be a number token"]
];

// The catalog index. CATALOG_ENTRY is valid; each refused row plants one
// defect in a copy of it, by the key path it names. The palette names are
// the table's palette group, written out here, not read from the table.
const CATALOG_PALETTE = { background: "#000000", foreground: "#ffffff", accent: "#fff", success: "#00ff00", warning: "#ffff00", danger: "#ff0000", info: "#0000ff" };
const CATALOG_IMAGERY = { repo: "https://github.com/vanillagreencom/vgs-themes", release: "themes", archive: "vgs-theme-probe-r1.tar.gz", size: 1, sha256: "0123456789abcdef".repeat(4) };
const CATALOG_ENTRY = { name: "probe", mode: "dark", palette: CATALOG_PALETTE, imagery: CATALOG_IMAGERY };
const catalog = entries => JSON.stringify({ schemaVersion: 1, entries });
// CATALOG_ENTRY with the value at dotted KEY set to VALUE, or removed when
// VALUE is REMOVED.
const REMOVED = Symbol("removed");
function entryWith(key, value) {
    const entry = JSON.parse(JSON.stringify(CATALOG_ENTRY));
    const parts = key.split(".");
    const parent = parts.slice(0, -1).reduce((node, part) => node[part], entry);
    if (value === REMOVED) delete parent[parts[parts.length - 1]];
    else parent[parts[parts.length - 1]] = value;
    return entry;
}
// [label, index text, reason, token, detail or undefined]
const CATALOG_REFUSED = [
    ["not JSON", "{", "catalog-json", ""],
    ["null document", "null", "catalog-document", "", "got=null"],
    ["array document", "[]", "catalog-document", "", "got=[]"],
    ["unknown document key", JSON.stringify({ schemaVersion: 1, entries: [], themes: [] }), "catalog-document", "", "key=themes"],
    ["missing schema version", JSON.stringify({ entries: [] }), "catalog-document", "", "key=schemaVersion"],
    ["schema version", JSON.stringify({ schemaVersion: 2, entries: [] }), "catalog-schema-version", ""],
    ["entries not a list", JSON.stringify({ schemaVersion: 1, entries: { probe: CATALOG_ENTRY } }), "catalog-entries", ""],
    ["entry not an object", catalog(["probe"]), "catalog-entry", "entries.0", 'got="probe"'],
    ["unknown entry key", catalog([entryWith("pair", "")]), "catalog-entry", "entries.0", "key=pair"],
    ["missing entry key", catalog([entryWith("imagery", REMOVED)]), "catalog-entry", "entries.0", "key=imagery"],
    ["name with a space", catalog([entryWith("name", "my theme")]), "package-name", "entries.0.name"],
    ["name leaving the directory", catalog([entryWith("name", "../probe")]), "package-name", "entries.0.name"],
    ["reserved vgs", catalog([entryWith("name", "vgs")]), "reserved-name", "entries.0.name", "name=vgs"],
    ["reserved targets", catalog([entryWith("name", "targets")]), "reserved-name", "entries.0.name", "name=targets"],
    ["reserved catalog", catalog([entryWith("name", "catalog")]), "reserved-name", "entries.0.name", "name=catalog"],
    ["duplicate name", catalog([CATALOG_ENTRY, entryWith("mode", "light")]), "duplicate-name", "entries.1.name", "name=probe"],
    ["unknown mode", catalog([entryWith("mode", "dim")]), "catalog-mode", "entries.0.mode"],
    ["palette not an object", catalog([entryWith("palette", null)]), "catalog-palette", "entries.0.palette", "got=null"],
    ["missing palette colour", catalog([entryWith("palette.info", REMOVED)]), "catalog-palette", "entries.0.palette", "key=info"],
    ["unknown palette colour", catalog([entryWith("palette.accent2", "#000000")]), "catalog-palette", "entries.0.palette", "key=accent2"],
    ["palette colour syntax", catalog([entryWith("palette.accent", "red")]), "catalog-palette", "entries.0.palette.accent"],
    ["palette colour type", catalog([entryWith("palette.accent", 7)]), "catalog-palette", "entries.0.palette.accent"],
    ["imagery not an object", catalog([entryWith("imagery", "themes")]), "catalog-imagery", "entries.0.imagery", 'got="themes"'],
    ["missing imagery key", catalog([entryWith("imagery.sha256", REMOVED)]), "catalog-imagery", "entries.0.imagery", "key=sha256"],
    ["unknown imagery key", catalog([entryWith("imagery.rev", 1)]), "catalog-imagery", "entries.0.imagery", "key=rev"],
    ["http repo", catalog([entryWith("imagery.repo", "http://github.com/vanillagreencom/vgs-themes")]), "catalog-repo", "entries.0.imagery.repo"],
    ["file repo", catalog([entryWith("imagery.repo", "file:///srv/vgs-themes")]), "catalog-repo", "entries.0.imagery.repo"],
    ["owner/name repo", catalog([entryWith("imagery.repo", "vanillagreencom/vgs-themes")]), "catalog-repo", "entries.0.imagery.repo"],
    ["repo without a path", catalog([entryWith("imagery.repo", "https://github.com")]), "catalog-repo", "entries.0.imagery.repo"],
    ["repo with credentials", catalog([entryWith("imagery.repo", "https://user@github.com/vanillagreencom/vgs-themes")]), "catalog-repo", "entries.0.imagery.repo"],
    ["repo with a port", catalog([entryWith("imagery.repo", "https://github.com:8443/vanillagreencom/vgs-themes")]), "catalog-repo", "entries.0.imagery.repo"],
    ["repo with a trailing slash", catalog([entryWith("imagery.repo", "https://github.com/vanillagreencom/vgs-themes/")]), "catalog-repo", "entries.0.imagery.repo"],
    ["repo with a query", catalog([entryWith("imagery.repo", "https://github.com/vanillagreencom/vgs-themes?x=1")]), "catalog-repo", "entries.0.imagery.repo"],
    ["repo not a string", catalog([entryWith("imagery.repo", null)]), "catalog-repo", "entries.0.imagery.repo"],
    ["repo a list that reads as a URL", catalog([entryWith("imagery.repo", ["https://github.com/vanillagreencom/vgs-themes"])]), "catalog-repo", "entries.0.imagery.repo"],
    ["release leaving the path", catalog([entryWith("imagery.release", "../themes")]), "catalog-imagery", "entries.0.imagery.release"],
    ["archive with a separator", catalog([entryWith("imagery.archive", "a/vgs-theme-probe-r1.tar.gz")]), "catalog-imagery", "entries.0.imagery.archive"],
    ["zero size", catalog([entryWith("imagery.size", 0)]), "catalog-size", "entries.0.imagery.size"],
    ["negative size", catalog([entryWith("imagery.size", -1)]), "catalog-size", "entries.0.imagery.size"],
    ["fractional size", catalog([entryWith("imagery.size", 1.5)]), "catalog-size", "entries.0.imagery.size"],
    ["size as text", catalog([entryWith("imagery.size", "1")]), "catalog-size", "entries.0.imagery.size"],
    ["upper-case sha256", catalog([entryWith("imagery.sha256", "0123456789ABCDEF".repeat(4))]), "catalog-sha256", "entries.0.imagery.sha256"],
    ["short sha256", catalog([entryWith("imagery.sha256", "0".repeat(63))]), "catalog-sha256", "entries.0.imagery.sha256"],
    ["sha256 not a string", catalog([entryWith("imagery.sha256", 1)]), "catalog-sha256", "entries.0.imagery.sha256"]
];
// A package a catalog entry names: theme.json with MODE and ACCENT over
// CATALOG_PALETTE, under NAME.
const catalogTheme = (name, mode, accent) => JSON.stringify({ schemaVersion: 1, name, tokens: { scheme: { mode }, palette: Object.assign({}, CATALOG_PALETTE, { accent }) } });
const READABILITY_ROLES = ["color.text", "color.textHeading", "color.textMuted", "color.textFaint", "text.keyHint.color", "color.accent", "color.success", "color.warning", "color.danger", "color.info"];
const READABILITY_SURFACES = ["color.background", "color.surface", "color.surfaceRaised", "color.surfaceSunken"];
const BOUNDARY_ROLES = ["checkbox.borderColor", "radio.borderColor", "textField.borderColor", "toggle.off", "checkbox.checked", "radio.checked", "toggle.on"];
const READABILITY_PAIRS = [["kbd.foreground", "kbd.background"], ["segmented.foreground", "segmented.background"], ["segmented.selectedForeground", "segmented.selected"], ["listItem.selectedForeground", "listItem.selected"],
    ...["neutral", "accent", "success", "warning", "danger", "info"].map(tone => [`badge.tone.${tone}.foreground`, `badge.tone.${tone}.background`]),
    ...["foreground", "gradientStart", "gradientEnd"].map(role => [`screensaver.${role}`, "screensaver.background"])];
const BOUNDARY_PAIRS = [["toggle.knobOff", "toggle.off"], ["toggle.knobOn", "toggle.on"], ["checkbox.mark", "checkbox.checked"], ["segmented.indicatorColor", "segmented.selected"], ["segmented.indicatorColor", "segmented.background"]];
const truncateRatio = value => Math.floor(value * 100) / 100;
const plain = value => JSON.parse(JSON.stringify(value));

function verifyReadabilityNotice(judge) {
    assert.equal(judge.readabilityTitle("tokyo-night", null), "tokyo-night: some text may be hard to read");
    assert.equal(judge.readabilityTitle("tokyo-night", "Tokyo Night"), "Tokyo Night: some text may be hard to read");
    assert.equal(judge.readabilityNotice([]), "", "a passing theme has no notice");
    const worst = { text: "color.textFaint", surface: "color.surface", ratio: 1.25, floor: judge.READABILITY_FLOOR };
    const better = { text: "color.textFaint", surface: "color.background", ratio: 2.25, floor: judge.READABILITY_FLOOR };
    const notice = judge.readabilityNotice([worst]);
    assert.equal(judge.readabilityNotice([better, worst, better]), notice, "each role names only its worst surface");
    assert.equal(judge.readabilityNotice([worst, better]), notice, "worst selection does not depend on input order");
    assert.equal(notice, `Faint text on panel backgrounds: contrast 1.25:1, needs ${judge.READABILITY_FLOOR}:1.`, "one measured line states its background and minimum");
    assert.equal(judge.readabilityNotice([better]), `Faint text on the main background: contrast 2.25:1, needs ${judge.READABILITY_FLOOR}:1.`);
    assert.equal(judge.readabilityNotice([Object.assign({}, worst, { text: "checkbox.borderColor", floor: judge.BOUNDARY_FLOOR })]),
        `Checkbox outline on panel backgrounds: contrast 1.25:1, needs ${judge.BOUNDARY_FLOOR}:1.`, "a mark keeps its own minimum");
    assert.ok(notice.includes("1.25:1"), "the notice contains the judged ratio");
    assert.ok(!notice.includes("2.25:1"), "the notice omits stronger surfaces");
    const translucent = Object.assign({}, worst, { surface: "color.surfaceRaised", ratio: null });
    assert.equal(judge.readabilityNotice([translucent]), `Faint text on raised panel backgrounds: contrast cannot be measured, needs ${judge.READABILITY_FLOOR}:1.`);
    assert.equal(judge.readabilityNotice([better, translucent]), judge.readabilityNotice([translucent]), "an unmeasurable surface takes priority");
    assert.equal(judge.readabilityNotice([translucent, worst]), judge.readabilityNotice([translucent]), "a measurable ratio cannot replace an unmeasurable one");
    // Discover the source table's roles and surfaces, including composites.
    const pairs = judge.READABILITY_PAIRS.concat(judge.BOUNDARY_PAIRS);
    const keys = new Set(judge.READABILITY_TEXT_ROLES.concat(judge.READABILITY_SURFACES, judge.BOUNDARY_ROLES,
        judge.RAIL_TEXT_ROLES, judge.RAIL_MARK_ROLES, judge.TOOLTIP_TEXT_ROLES,
        [judge.MODAL_BORDER, judge.MODAL_FILL, judge.MODAL_SCRIM, judge.RAIL_WALLPAPER,
            judge.FAILURE_LINE, judge.FAILURE_PLATE, judge.TOOLTIP_FILL, judge.GLASS_SOLID]));
    for (const pair of pairs) for (const key of pair) keys.add(key);
    assert.ok(keys.has("color.textFaint") && keys.has("glass.fill solid"), "label coverage reaches text and glass");
    for (const key of keys) {
        const words = judge.readabilityName(key);
        assert.equal(typeof words, "string");
        assert.ok(words.trim().length > 0 && !words.includes(".") && !words.includes("#"), key + ": labels use user words");
        const composite = judge.readabilityName(key + " over color.surfaceRaised");
        assert.ok(!composite.includes("color.") && composite.length > words.length, key + ": composite surfaces use user words");
    }
    const roles = Array.from(new Set(judge.READABILITY_TEXT_ROLES.concat(judge.BOUNDARY_ROLES,
        pairs.map(pair => pair[0]), judge.RAIL_TEXT_ROLES, judge.RAIL_MARK_ROLES, judge.TOOLTIP_TEXT_ROLES,
        [judge.MODAL_BORDER, judge.MODAL_FILL, judge.FAILURE_LINE])));
    const crowded = judge.readabilityNotice(roles.map(text => ({ text, surface: "color.scrim over color.surfaceRaised", ratio: 1.25, floor: 4.5 })));
    assert.ok(crowded.length <= 600, "one notice stays within the notifier's message limit");
    const omitted = /^(\d+)\b/.exec(crowded.split("\n").slice(-1)[0]);
    assert.notEqual(omitted, null, "a bounded notice names how many roles remain");
    assert.equal(crowded.split("\n").length - 1 + Number(omitted[1]), roles.length, "each role is listed or counted");
    assert.ok(!/color\.|badge\.|segmented\.|carousel\.|vgshell/.test(crowded), "no internal key or command reaches the notice");
}

function verifyScreensaver(judge) {
    for (const text of ["#d7d7d9", "#100f0f", "#ffffff33"]) {
        const result = judge.accept(TOKENS, document({ color: { text } }));
        assert.equal(result.ok, true, text);
        assert.equal(result.values.screensaver.background, "#000000ff");
        assert.deepEqual(plain(readability(judge, result.values).filter(row => row.text.startsWith("screensaver."))), [], text);
    }
    for (const background of ["#101010", "#00000080"]) {
        const result = judge.accept(TOKENS, document({ screensaver: { background } }));
        assert.equal(result.ok, false, background);
        assert.equal(result.token, "screensaver.background");
        assert.equal(result.reason, "fixed-background");
    }
    for (const role of ["foreground", "gradientStart", "gradientEnd"]) {
        const unreadable = judge.accept(TOKENS, document({ screensaver: { [role]: "#000000" } }));
        assert.equal(readability(judge, unreadable.values).some(row => row.text === `screensaver.${role}` && row.surface === "screensaver.background"), true);
    }
    for (const accent of ["#000000", "#4b369d", "#00ff00", "#ff0000", "#0000ff", "#ffffff"]) {
        const result = judge.accept(TOKENS, document({ color: { accent } }));
        assert.equal(result.ok, true);
        const start = judge.parseColor(result.values.screensaver.gradientStart);
        const end = judge.parseColor(result.values.screensaver.gradientEnd);
        assert.deepEqual(plain(readability(judge, result.values).filter(row => row.text.startsWith("screensaver."))), []);
        for (const channel of ["r", "g", "b"]) assert.ok(end[channel] >= start[channel], `${accent} ${channel} never darkens during interpolation`);
    }
}

function verify(judge) {
    verifyScreensaver(judge);
    const interior = judge.contrastMix(judge.parseColor("#ff0000"), judge.parseColor("#00ff00"), judge.parseColor("#ffffff"), 4.1);
    assert.notEqual(interior, null, "opposing channels can meet the floor when both endpoints fail");
    assert.ok(judge.contrastRatio(interior, judge.parseColor("#ffffff")) >= 4.1);
    verifyReadabilityNotice(judge);
    assert.equal(judge.tableError(TOKENS), "");
    for (const [table, start] of BAD_TABLES)
        assert.ok(judge.tableError(table).startsWith(start), `${start}: got ${JSON.stringify(judge.tableError(table))}`);
    assert.throws(() => judge.defaults({ palette: {}, motion: { scale: { type: "number", value: 1, min: 0, max: 4 } } }), /theme: token table: group palette is empty/);
    assert.throws(() => judge.defaults({ palette: { accent: { type: "color", value: "{palette.accent}" } }, motion: { scale: { type: "number", value: 1, min: 0, max: 4 } } }), /theme: refused: token=palette\.accent reason=cycle/);

    const lineTable = {
        motion: {scale: {type: "number", value: 1, min: 0, max: 4}},
        stack: {first: {type: "body-lines", value: 1}, twice: {type: "body-lines", value: "mul({stack.first}, 2)"}}
    };
    assert.equal(judge.tableError(lineTable), "");
    assert.equal(judge.defaults(lineTable).values.stack.twice, 2, "compatible body-line references retain their unit");
    for (const family of ["Inter Variable", "JetBrains Mono"]) {
        const tokens = {text: {body: {family, lineHeight: 0.8}}, stack: {titleSpace: 1}};
        const packageVerdict = judge.acceptPackage(TOKENS, {directoryName: "probe", themeJson: document(tokens), terminalJson: JSON.stringify({schemaVersion: 1, slots: TERMINAL_SLOTS}), shipped: false});
        assert.equal(packageVerdict.ok, true, "compact body-line package agrees with document acceptance");
        assert.equal(packageVerdict.values.stack.titleSpace, 1);
        assert.equal(judge.accept(TOKENS, document(tokens)).ok, true);
        const belowLine = {...tokens, stack: {titleSpace: 0.8}};
        assert.equal(judge.acceptPackage(TOKENS, {directoryName: "probe", themeJson: document(belowLine), terminalJson: JSON.stringify({schemaVersion: 1, slots: TERMINAL_SLOTS}), shipped: false}).reason, "range");
    }
    const defaults = judge.defaults(TOKENS);
    assert.equal(defaults.name, "vgs");
    for (const [token, want] of DEFAULTS)
        assert.deepEqual(at(defaults.values, token), want, token);
    assert.deepEqual(plain(judge.READABILITY_TEXT_ROLES), READABILITY_ROLES);
    assert.deepEqual(plain(judge.READABILITY_SURFACES), READABILITY_SURFACES);
    assert.equal(judge.READABILITY_FLOOR, 4.5);
    assert.deepEqual(plain(judge.READABILITY_PAIRS), READABILITY_PAIRS);
    assert.deepEqual(plain(judge.BOUNDARY_ROLES), BOUNDARY_ROLES);
    assert.deepEqual(plain(judge.BOUNDARY_PAIRS), BOUNDARY_PAIRS);
    assert.equal(judge.BOUNDARY_FLOOR, 3);
    assert.equal(judge.contrastRatio(judge.parseColor("#000000"), judge.parseColor("#ffffff")), 21);
    assert.deepEqual(plain(readability(judge, defaults.values)), [], "default vgs readability");
    verifyHintMargin(judge);
    verifyDrawnWeights(judge);
    const faintFailure = judge.accept(TOKENS, document({ color: { textFaint: "#111111" } }));
    assert.equal(faintFailure.ok, true, faintFailure.ok ? "" : judge.refusalLine(faintFailure));
    const faintShortfalls = readability(judge, faintFailure.values);
    assert.deepEqual(
        Object.assign({}, faintShortfalls[0], { ratio: truncateRatio(faintShortfalls[0].ratio) }),
        { text: "color.textFaint", surface: "color.background", ratio: 1.1, floor: 4.5 }
    );
    const accentFailure = judge.accept(TOKENS, document({ palette: { accent: "#111111" } }));
    assert.equal(accentFailure.ok, true, accentFailure.ok ? "" : judge.refusalLine(accentFailure));
    assert.equal(readability(judge, accentFailure.values).some(row => row.text === "color.accent" && row.surface === "color.background"), true);
    const statusFailure = judge.accept(TOKENS, document({ color: { success: "#111111" } }));
    assert.equal(statusFailure.ok, true, statusFailure.ok ? "" : judge.refusalLine(statusFailure));
    assert.equal(readability(judge, statusFailure.values).some(row => row.text === "color.success" && row.surface === "color.background"), true);
    const translucentFailure = judge.accept(TOKENS, document({ color: { textFaint: "alpha({palette.foreground}, 0.5)" } }));
    assert.equal(translucentFailure.ok, true, translucentFailure.ok ? "" : judge.refusalLine(translucentFailure));
    assert.deepEqual(plain(readability(judge, translucentFailure.values)[0]), { text: "color.textFaint", surface: "color.background", ratio: null, floor: 4.5 });
    // An input boundary as faint as the surface it sits on, and a switch
    // knob the colour of its track, each fall under the 3:1 floor; a 3.63
    // boundary holds.
    const boundaryFailure = judge.accept(TOKENS, document({ checkbox: { borderColor: "{color.surface}" } }));
    assert.equal(boundaryFailure.ok, true, boundaryFailure.ok ? "" : judge.refusalLine(boundaryFailure));
    const boundaryRows = readability(judge, boundaryFailure.values);
    assert.deepEqual(plain(boundaryRows.map(row => [row.text, row.surface, row.floor])), READABILITY_SURFACES.map(surface => ["checkbox.borderColor", surface, 3]));
    const knobFailure = judge.accept(TOKENS, document({ toggle: { knobOff: "{toggle.off}" } }));
    assert.equal(knobFailure.ok, true, knobFailure.ok ? "" : judge.refusalLine(knobFailure));
    assert.deepEqual(plain(readability(judge, knobFailure.values)), [{ text: "toggle.knobOff", surface: "toggle.off", ratio: 1, floor: 3 }]);
    // A modal card over a scrim the colour of the background, with a
    // strong border: in a light theme that scrim lightens the page past
    // the card's fill, so fill and border fall under the 3:1 floor on
    // every dimmed surface; in the dark defaults the fill stays lighter
    // than the dimmed page and only the border falls. The table's own
    // values hold in both.
    const modalRows = tokens => {
        const accepted = judge.accept(TOKENS, document(tokens));
        assert.equal(accepted.ok, true, accepted.ok ? "" : judge.refusalLine(accepted));
        return plain(readability(judge, accepted.values).filter(row => row.surface.startsWith("color.scrim over ")).map(row => [row.text, row.surface, row.floor]));
    };
    const LIGHT_PAGE = { scheme: { mode: "light" }, palette: { background: "#fffcf0", foreground: "#100f0f" } };
    const OLD_MODAL = { color: { scrim: "alpha({palette.background}, 0.6)" }, dialog: { border: "{color.borderStrong}" } };
    assert.deepEqual(modalRows(LIGHT_PAGE), []);
    assert.deepEqual(modalRows(Object.assign({}, LIGHT_PAGE, OLD_MODAL)),
        READABILITY_SURFACES.flatMap(surface => [["dialog.border", "color.scrim over " + surface, 3], ["dialog.background", "color.scrim over " + surface, 3]]));
    assert.deepEqual(modalRows(OLD_MODAL), READABILITY_SURFACES.map(surface => ["dialog.border", "color.scrim over " + surface, 3]));
    // Rail text over the scrim on a black wallpaper: catppuccin-latte's
    // palette holds 4.5:1 with the table's own rule, and falls under it
    // with the theme's text and heading colours.
    const LATTE = { scheme: { mode: "light" }, palette: { background: "#eff1f5", foreground: "#4c4f69" } };
    const railRows = tokens => modalRows(tokens).filter(row => row[0].startsWith("carousel."));
    assert.deepEqual(railRows(LATTE), []);
    assert.deepEqual(railRows(Object.assign({}, LATTE, { carousel: { hint: "{color.text}", hintActive: "{color.textHeading}" } })),
        [["carousel.hint", "color.scrim over #000000", 4.5], ["carousel.hintActive", "color.scrim over #000000", 4.5]]);
    // A failure line beside the rail is judged on its plate alone, never
    // on the scrim: latte's danger #f43f5e, forced onto the line, reads
    // 2.94:1 drawn on its surface #e7e9ee and falls under the floor there, and a
    // translucent plate has no ratio.
    const plateRows = tokens => {
        const accepted = judge.accept(TOKENS, document(tokens));
        assert.equal(accepted.ok, true, accepted.ok ? "" : judge.refusalLine(accepted));
        return plain(readability(judge, accepted.values).filter(row => row.surface === "carousel.failurePlate"));
    };
    assert.deepEqual(plateRows(LATTE), []);
    assert.deepEqual(plateRows(Object.assign({}, LATTE, { carousel: { hintDanger: "{color.danger}" } })).map(row => [row.text, row.surface, truncateRatio(row.ratio), row.floor]),
        [["carousel.hintDanger", "carousel.failurePlate", 2.94, 4.5]]);
    assert.deepEqual(plateRows({ carousel: { hintDanger: "{color.danger}", failurePlate: "alpha({color.surface}, 0.5)" } }), [
        { text: "carousel.hintDanger", surface: "carousel.failurePlate", ratio: null, floor: 4.5 }
    ]);
    // The open tab's indicator on that backdrop is a mark at 3:1: the
    // theme's accent forced onto it falls under the floor in latte.
    assert.deepEqual(railRows(Object.assign({}, LATTE, { carousel: { tabIndicator: "{color.accent}" } })),
        [["carousel.tabIndicator", "color.scrim over #000000", 3]]);
    // Each rule holds its own floor: the grey #6a6a6a, luminance 0.144,
    // reads 3.88:1 on the default black backdrop, (0.144 + 0.05) / 0.05,
    // so it is kept as a mark and not as text.
    const floors = judge.accept(TOKENS, document({ carousel: {
        hintDanger: "readable(#6a6a6a, {carousel.backdrop}, {carousel.hintActive})",
        tabIndicator: "discernible(#6a6a6a, {carousel.backdrop}, {carousel.hintActive})" } }));
    assert.equal(floors.ok, true, floors.ok ? "" : judge.refusalLine(floors));
    assert.deepEqual([floors.values.carousel.hintDanger, floors.values.carousel.tabIndicator], ["#ffffffff", "#6a6a6aff"]);
    // A translucent danger has no ratio, so the line takes the fallback.
    const faintDanger = judge.accept(TOKENS, document({ carousel: { hintDanger: "readable(alpha(#ffffff, 0.5), {carousel.backdrop}, {carousel.hintActive})" } }));
    assert.equal(faintDanger.ok, true, faintDanger.ok ? "" : judge.refusalLine(faintDanger));
    assert.equal(faintDanger.values.carousel.hintDanger, "#ffffffff");
    // A segmented control's text the colour of the fill it sits on falls
    // under the 4.5:1 floor, and a chosen segment's mark the colour of its
    // segment or of the track under the 3:1 floor.
    for (const [segmented, rows] of [
        [{ foreground: "{segmented.background}" }, [["segmented.foreground", "segmented.background", 4.5]]],
        [{ selectedForeground: "{segmented.selected}" }, [["segmented.selectedForeground", "segmented.selected", 4.5]]],
        [{ indicatorColor: "{segmented.selected}" }, [["segmented.indicatorColor", "segmented.selected", 3], ["segmented.indicatorColor", "segmented.background", 3]]],
        [{ selected: "{color.accent}", selectedForeground: "{color.onAccent}" }, [["segmented.indicatorColor", "segmented.selected", 3]]]
    ]) {
        const segmentedFailure = judge.accept(TOKENS, document({ segmented }));
        assert.equal(segmentedFailure.ok, true, segmentedFailure.ok ? "" : judge.refusalLine(segmentedFailure));
        assert.deepEqual(plain(readability(judge, segmentedFailure.values).map(row => [row.text, row.surface, row.floor])), rows, JSON.stringify(segmented));
    }
    // A selected list row's text is judged on its translucent plate laid
    // over each resting surface and over the fill glass draws solid.
    const rowFailure = judge.accept(TOKENS, document({ listItem: { selectedForeground: "#3a3a3a" } }));
    assert.equal(rowFailure.ok, true, rowFailure.ok ? "" : judge.refusalLine(rowFailure));
    assert.deepEqual(plain(readability(judge, rowFailure.values).map(row => [row.text, row.surface, row.floor])),
        [...READABILITY_SURFACES, "glass.fill solid"].map(surface => ["listItem.selectedForeground", "listItem.selected over " + surface, 4.5]));

    // A badge's text on its translucent fill is judged on the fill laid
    // over each resting surface, by the ratio of that blend; an opaque
    // fill is judged as it is.
    const badgeFailure = judge.accept(TOKENS, document({ badge: { tone: { success: { foreground: "#3a3a3a" } } } }));
    assert.equal(badgeFailure.ok, true, badgeFailure.ok ? "" : judge.refusalLine(badgeFailure));
    const blend = surface => {
        const fill = judge.parseColor(at(badgeFailure.values, "badge.tone.success.background"));
        const base = judge.parseColor(at(badgeFailure.values, surface));
        const mixed = channel => fill[channel] * fill.a + base[channel] * (1 - fill.a);
        return { r: mixed("r"), g: mixed("g"), b: mixed("b"), a: 1 };
    };
    assert.deepEqual(plain(readability(judge, badgeFailure.values).map(row => [row.text, row.surface, truncateRatio(row.ratio), row.floor])),
        READABILITY_SURFACES.map(surface => ["badge.tone.success.foreground", "badge.tone.success.background over " + surface,
            truncateRatio(judge.drawnTextRatio(judge.parseColor("#3a3a3a"), blend(surface), 500)), 4.5]));
    const opaqueFill = judge.accept(TOKENS, document({ badge: { tone: { success: { background: "#c9d897" } } } }));
    assert.equal(opaqueFill.ok, true, opaqueFill.ok ? "" : judge.refusalLine(opaqueFill));
    assert.deepEqual(plain(readability(judge, opaqueFill.values)), [{ text: "badge.tone.success.foreground", surface: "badge.tone.success.background", ratio: 1, floor: 4.5 }]);

    // The resolved tree holds exactly the table's tokens, each with a value
    // of its type's portable form.
    const all = judge.leaves(TOKENS);
    assert.ok(all.length >= 150, `the table walk found ${all.length} tokens; the walk is broken`);
    for (const { path: token, leaf } of all) {
        const value = at(defaults.values, token);
        if (leaf.type === "color") assert.match(value, /^#[0-9a-f]{8}$/, token);
        else if (leaf.type === "flag") assert.equal(typeof value, "boolean", token);
        else if (["family", "easing", "choice"].includes(leaf.type)) assert.equal(typeof value, "string", token);
        else assert.equal(typeof value, "number", token);
        if (["length", "duration", "weight"].includes(leaf.type)) assert.ok(Number.isInteger(value), token);
    }
    const listed = judge.paths(TOKENS);
    for (const token of ["palette", "palette.accent", "text.body", "text.body.size", "motion.duration.fast"])
        assert.ok(listed.includes(token), token);
    assert.ok(!listed.includes("palette.accent.value"));

    for (const row of ACCEPTED) {
        const result = judge.accept(TOKENS, document(row.tokens));
        assert.equal(result.ok, true, `${JSON.stringify(row.tokens)}: ${result.ok ? "" : judge.refusalLine(result)}`);
        assert.equal(result.name, "probe");
        for (const [token, want] of row.want)
            assert.deepEqual(at(result.values, token), want, `${JSON.stringify(row.tokens)} ${token}`);
    }

    for (const row of REFUSED) {
        const text = row.text !== undefined ? row.text : document(row.tokens);
        const label = text.slice(0, 120);
        let result;
        assert.doesNotThrow(() => { result = judge.accept(TOKENS, text); }, label);
        assert.equal(result.ok, false, label);
        assert.equal(result.reason, row.reason, label);
        assert.equal(result.token, row.token, label);
        if (row.detail !== undefined) assert.equal(result.detail, row.detail, label);
        assert.deepEqual(Object.keys(result).sort(), ["detail", "ok", "reason", "token"], label);
    }

    const backgroundNames = judge.accept(TOKENS, documentWith({ backgrounds: { "black.png": "Black", "wide.avif": "Blue Ridge" } }));
    assert.equal(backgroundNames.ok, true, backgroundNames.ok ? "" : judge.refusalLine(backgroundNames));
    assert.deepEqual(plain(backgroundNames.backgrounds), { "black.png": "Black", "wide.avif": "Blue Ridge" });
    for (const [label, text, reason, detail] of [
        ["three words", documentWith({ backgrounds: { "a.png": "Blue Ridge Day" } }), "background-name", 'file=a.png got="Blue Ridge Day"'],
        ["empty name", documentWith({ backgrounds: { "a.png": "" } }), "background-name", 'file=a.png got=""'],
        ["bad key", documentWith({ backgrounds: { "nested/a.png": "Blue" } }), "background-file", 'file="nested/a.png"'],
        ["not an object", documentWith({ backgrounds: [] }), "backgrounds", "got=[]"]
    ]) {
        const result = judge.accept(TOKENS, text);
        assert.equal(result.ok, false, label);
        assert.equal(result.reason, reason, label);
        assert.equal(result.token, "backgrounds", label);
        assert.equal(result.detail, detail, label);
    }

    const shippedVgs = judge.acceptPackage(TOKENS, {
        directoryName: "vgs",
        themeJson: fs.readFileSync(path.join(repo, "themes", "vgs", "theme.json"), "utf8"),
        terminalJson: fs.readFileSync(path.join(repo, "themes", "vgs", "terminal.json"), "utf8"),
        shipped: true
    });
    assert.equal(shippedVgs.ok, true, shippedVgs.ok ? "" : judge.refusalLine(shippedVgs));
    assert.equal(shippedVgs.name, "vgs");
    assert.equal(shippedVgs.displayName, "VGS", "the shipped defaults state the product's name");
    assert.equal(shippedVgs.terminal.color0, "#0b0b0bff");
    assert.equal(shippedVgs.terminal.color15, "#ffffffff");
    assert.equal(Object.keys(shippedVgs.terminal).length, 16);
    assert.deepEqual(plain(shippedVgs.backgrounds), { "black.png": "Black" });

    const packageWithoutTerminal = judge.acceptPackage(TOKENS, {
        directoryName: "probe",
        themeJson: document({ palette: { accent: "#abcdef" } }),
        shipped: false
    });
    assert.equal(packageWithoutTerminal.ok, true, packageWithoutTerminal.ok ? "" : judge.refusalLine(packageWithoutTerminal));
    assert.equal(packageWithoutTerminal.terminal, null);
    assert.equal(packageWithoutTerminal.displayName, null, "a package states no display name unless its document does");
    assert.equal(judge.accept(TOKENS, documentWith({})).displayName, null, "an absent display name is accepted");
    assert.equal(judge.accept(TOKENS, documentWith({ displayName: "Probe X" })).displayName, "Probe X");
    assert.deepEqual(plain(packageWithoutTerminal.backgrounds), {});
    assert.equal(at(packageWithoutTerminal.values, "palette.accent"), "#abcdefff");

    const packageRefusals = [
        [{ directoryName: "vgs", themeJson: JSON.stringify({ schemaVersion: 1, name: "vgs", tokens: {} }), shipped: false }, "reserved-name", ""],
        [{ directoryName: "other", themeJson: document({}), shipped: false }, "name-mismatch", ""],
        [{ directoryName: "my theme", themeJson: JSON.stringify({ schemaVersion: 1, name: "my theme", tokens: {} }), shipped: false }, "package-name", ""],
        [{ directoryName: ".probe", themeJson: JSON.stringify({ schemaVersion: 1, name: ".probe", tokens: {} }), shipped: false }, "package-name", ""],
        [{ directoryName: "probe", themeJson: document({}), terminalJson: JSON.stringify({ schemaVersion: 1, slots: Object.assign({ colour0: "#000000" }, TERMINAL_SLOTS) }), shipped: false }, "terminal-slot", "terminal"],
        [{ directoryName: "probe", themeJson: document({}), terminalJson: JSON.stringify({ schemaVersion: 1, slots: Object.assign({}, TERMINAL_SLOTS, { color3: "red" }) }), shipped: false }, "terminal-colour", "terminal.color3"]
    ];
    for (const [files, reason, token] of packageRefusals) {
        const result = judge.acceptPackage(TOKENS, files);
        assert.equal(result.ok, false, JSON.stringify(files));
        assert.equal(result.reason, reason, JSON.stringify(files));
        assert.equal(result.token, token, JSON.stringify(files));
    }

    for (const name of ["targets", "catalog"]) {
        const result = judge.acceptPackage(TOKENS, { directoryName: name, themeJson: JSON.stringify({ schemaVersion: 1, name, tokens: {} }), shipped: true });
        assert.equal(result.ok, false, name);
        assert.equal(result.reason, "reserved-name", name);
        assert.equal(result.detail, "name=" + name, name);
    }

    const index = judge.acceptCatalogIndex(TOKENS, catalog([CATALOG_ENTRY, entryWith("name", "bare")].map((entry, i) => i === 0 ? entry : Object.assign(entry, { mode: "light", imagery: null }))));
    assert.equal(index.ok, true, index.ok ? "" : judge.refusalLine(index));
    // The judge runs in its own context, so its objects compare as JSON.
    assert.deepEqual(plain(index.entries), [
        { name: "probe", mode: "dark", palette: { background: "#000000ff", foreground: "#ffffffff", accent: "#ffffffff", success: "#00ff00ff", warning: "#ffff00ff", danger: "#ff0000ff", info: "#0000ffff" }, imagery: CATALOG_IMAGERY },
        { name: "bare", mode: "light", palette: { background: "#000000ff", foreground: "#ffffffff", accent: "#ffffffff", success: "#00ff00ff", warning: "#ffff00ff", danger: "#ff0000ff", info: "#0000ffff" }, imagery: null }
    ]);
    assert.deepEqual(plain(judge.acceptCatalogIndex(TOKENS, catalog([]))), { ok: true, entries: [] });
    for (const [label, text, reason, token, detail] of CATALOG_REFUSED) {
        let result;
        assert.doesNotThrow(() => { result = judge.acceptCatalogIndex(TOKENS, text); }, label);
        assert.equal(result.ok, false, label);
        assert.equal(result.reason, reason, label);
        assert.equal(result.token, token, label);
        if (detail !== undefined) assert.equal(result.detail, detail, label);
    }

    // A catalogued package is judged as the installed package it becomes,
    // and the index states its own mode and palette.
    const probe = index.entries[0];
    const accepted = judge.acceptCatalogEntry(TOKENS, probe, { themeJson: catalogTheme("probe", "dark", "#ffffff") });
    assert.equal(accepted.ok, true, accepted.ok ? "" : judge.refusalLine(accepted));
    assert.equal(accepted.name, "probe");
    const entryRefusals = [
        ["name mismatch", probe, { themeJson: catalogTheme("other", "dark", "#ffffff") }, "name-mismatch", ""],
        ["mode mismatch", probe, { themeJson: catalogTheme("probe", "light", "#ffffff") }, "catalog-mode-mismatch", "scheme.mode"],
        ["palette mismatch", probe, { themeJson: catalogTheme("probe", "dark", "#fffffe") }, "catalog-palette-mismatch", "palette.accent"],
        ["bad terminal", probe, { themeJson: catalogTheme("probe", "dark", "#ffffff"), terminalJson: JSON.stringify({ schemaVersion: 1, slots: Object.assign({}, TERMINAL_SLOTS, { color3: "red" }) }) }, "terminal-colour", "terminal.color3"],
        ["installed vgs", Object.assign({}, probe, { name: "vgs" }), { themeJson: catalogTheme("vgs", "dark", "#ffffff") }, "reserved-name", ""],
        ["files not an object", probe, null, "package", ""]
    ];
    for (const [label, entry, files, reason, token] of entryRefusals) {
        const result = judge.acceptCatalogEntry(TOKENS, entry, files);
        assert.equal(result.ok, false, label);
        assert.equal(result.reason, reason, label);
        assert.equal(result.token, token, label);
    }

    // The shipped catalog: its index and every package it names pass.
    const catalogDir = path.join(repo, "themes", "catalog");
    const shipped = judge.acceptCatalogIndex(TOKENS, fs.readFileSync(path.join(catalogDir, "index.json"), "utf8"));
    assert.equal(shipped.ok, true, shipped.ok ? "" : judge.refusalLine(shipped));
    assert.ok(shipped.entries.some(entry => entry.name === "nord"), "the shipped catalog lists nord");
    for (const entry of shipped.entries) {
        const terminal = path.join(catalogDir, entry.name, "terminal.json");
        const result = judge.acceptCatalogEntry(TOKENS, entry, {
            themeJson: fs.readFileSync(path.join(catalogDir, entry.name, "theme.json"), "utf8"),
            terminalJson: fs.existsSync(terminal) ? fs.readFileSync(terminal, "utf8") : undefined
        });
        assert.equal(result.ok, true, `${entry.name}: ${result.ok ? "" : judge.refusalLine(result)}`);
    }

    for (const name of ["vgs", "tokyo-night", "Nord2", "a.b_c"])
        assert.equal(judge.isPackageName(name), true, name);
    for (const name of ["", ".", "..", "../x", "a/b", "a b", "-x", ".x", "x\n", 7, undefined])
        assert.equal(judge.isPackageName(name), false, JSON.stringify(name));

    for (const name of ["DP-1", "HDMI-A-1", "eDP-1", "HEADLESS-2", "SMOKE_HIDPI"])
        assert.equal(judge.isOutputName(name), true, name);
    for (const name of ["", "-DP", "_DP", "DP 1", "DP.1", "DP/1", "DP-1\n", null, 1])
        assert.equal(judge.isOutputName(name), false, JSON.stringify(name));

    // The theme capability's set screen and download options, as argv.
    for (const [screen, want] of [
        [null, []],
        [undefined, []],
        ["*", ["--every-screen"]],
        ["DP-1", ["--screen", "DP-1"]],
        ["../x", null],
        ["", null],
        ["**", null],
        [1, null]
    ]) assert.deepEqual(JSON.parse(JSON.stringify(judge.setScreenArguments(screen))), want, "set screen " + JSON.stringify(screen));
    for (const [options, want] of [
        [undefined, []],
        [{}, []],
        [{ update: false }, []],
        [{ update: true }, ["--update"]],
        [null, null],
        [true, null],
        [[], null],
        [{ update: "yes" }, null],
        [{ update: true, force: true }, null]
    ]) assert.deepEqual(JSON.parse(JSON.stringify(judge.wallpaperArguments(options))), want, "wallpapers options " + JSON.stringify(options));

    for (const text of ["/a", "/home/u/.config/vgshell/themes/x/backgrounds/a.png", "/a b/.c"])
        assert.equal(judge.isAbsolutePath(text), true, text);
    for (const text of ["", "/", "a.png", "./a.png", "~/a.png", "//a", "/a//b", "/a/", "/a/./b", "/a/../b", "/..", "/a\u0000b", null, ["/a"]])
        assert.equal(judge.isAbsolutePath(text), false, JSON.stringify(text));

    for (const [label, table, light, theme, want] of APPEARANCE_ACCEPTED) {
        const result = judge.acceptAppearance(table, light, theme);
        assert.equal(result.ok, true, `${label}: ${result.ok ? "" : judge.refusalLine(result)}`);
        for (const [token, value] of want)
            assert.deepEqual(at(result.values, token), value, `${label} ${token}`);
    }
    assert.deepEqual(judge.acceptAppearance(LOOK, LOOK_LIGHT, UNRELATED_THEME).values, judge.acceptAppearance(LOOK, LOOK_LIGHT, DARK_THEME).values, "unrelated shell tokens moved a plugin value");
    for (const [label, table, light, theme, reason, token] of APPEARANCE_REFUSED) {
        const result = judge.acceptAppearance(table, light, theme);
        assert.equal(result.ok, false, label);
        assert.equal(result.reason, reason, label);
        assert.equal(result.token, token, label);
    }
    assert.equal(judge.acceptAppearance(LOOK, { card: { radius: "#fff" } }, DARK_THEME).ok, true, "a light value applies only in light mode");

    assert.equal(judge.refusalLine(judge.accept(TOKENS, document({ palette: { acent: "#fff" } }))), "theme: refused: token=palette.acent reason=unknown-token");
    assert.equal(judge.refusalLine(judge.accept(TOKENS, JSON.stringify({ foreground: "#123456" }))), "theme: refused: document reason=unknown-key key=foreground");
    verifyAppearance(judge);
    verifyGlass(judge);
}

// VGlass, shell/Commons/Glass.js, judged as a plugin's own look is, in
// both modes against the shipped defaults: the window values Hyprland
// takes, whose shadow is the tight shadow's colour, alpha 0.45 in dark,
// round(0.45 * 255) = 115 = 0x73, and 0.16 in light, round(40.8) = 41 =
// 0x29. The surface values are pinned in scripts/test-notifications-logic.js
// beside the looks that hand them, but the fill, which takes the theme's
// raised surface. Each fill row: [mode, raised surface, fill, its solid
// form]. Dark, the shipped #101010 at 0.8, 204 = 0xcc, lifted by 0.05: 16 +
// 239 * 0.05 = 27.95, #1c1c1c; another dark surface, #283038, gives 50.75,
// 58.35 and 65.95, #333a42. Light, #f2f2f2 at 0.85, round(216.75) = 217 =
// 0xd9, lifted by 0.1: 242 + 13 * 0.1 = 243.3, #f3f3f3; a cream #e8e4d8
// gives 234.3, 230.7 and 219.9, #eae7dc.
const GLASS = load(path.join(repo, "shell", "Commons", "Glass.js"));
// The readability judge on VALUES with the VGlass look they resolve.
function readability(judge, values) {
    return judge.readabilityShortfalls(values, judge.acceptAppearance(GLASS.TOKENS, GLASS.LIGHT, values).values);
}
const LAUNCHER = load(path.join(repo, "shell", "plugins", "vgs.launcher", "Appearance.js"));
const NOTIFICATIONS = load(path.join(repo, "shell", "plugins", "vgs.notifications", "Appearance.js"));
function verifyGlass(judge, glass = GLASS) {
    const shipped = judge.defaults(TOKENS).values;
    for (const [mode, shadow] of [["dark", "#00000073"], ["light", "#00000029"]]) {
        const result = judge.acceptAppearance(glass.TOKENS, glass.LIGHT, Object.assign({}, shipped, { scheme: { mode } }));
        assert.equal(result.ok, true, result.ok ? "" : judge.refusalLine(result));
        assert.deepEqual(plain(result.values.window), { opacity: 0.92, inactiveOpacity: 0.86, blurSize: 8, blurPasses: 2, shadowRange: 30, shadowPower: 3, shadowColor: shadow }, "the window glass in " + mode + " mode");
    }
    for (const [mode, raised, fill, solid] of [["dark", null, "#101010cc", "#1c1c1cff"], ["dark", "#283038ff", "#283038cc", "#333a42ff"], ["light", "#f2f2f2ff", "#f2f2f2d9", "#f3f3f3ff"], ["light", "#e8e4d8ff", "#e8e4d8d9", "#eae7dcff"]]) {
        const theme = Object.assign({}, shipped, { scheme: { mode } }, raised === null ? {} : { color: Object.assign({}, shipped.color, { surfaceRaised: raised }) });
        const drawn = judge.acceptAppearance(glass.TOKENS, glass.LIGHT, theme).values.glass;
        assert.equal(drawn.fill, fill, "the glass fill in " + mode + " mode over " + raised);
        assert.equal(judge.formatColor(judge.liftedOpaque(judge.parseColor(drawn.fill), drawn.solidLift)), solid, "its solid form");
    }
    // A blur size Hyprland would not take is refused.
    const wide = JSON.parse(JSON.stringify(glass.TOKENS));
    wide.window.blurSize.value = 65;
    assert.equal(judge.acceptAppearance(wide, glass.LIGHT, shipped).reason, "range", "a blur size past 64 is refused");
}

// The shipped dark theme, flexoki-light and every catalog theme, read once
// from the catalog's index.
const JUDGED_THEMES = (() => {
    const judge = load(judgeFile);
    const index = judge.acceptCatalogIndex(TOKENS, fs.readFileSync(path.join(repo, "themes/catalog/index.json"), "utf8"));
    assert.equal(index.ok, true, index.ok ? "" : judge.refusalLine(index));
    assert.ok(index.entries.length > 10, "the catalog is read");
    const names = new Set(["vgs", "catalog/flexoki-light", ...index.entries.map(entry => "catalog/" + entry.name)]);
    return [...names].map(name => {
        const theme = judge.accept(TOKENS, fs.readFileSync(path.join(repo, "themes", name, "theme.json"), "utf8"));
        assert.equal(theme.ok, true, name);
        return { name, values: theme.values };
    });
})();

// Every `family` token of a plugin-owned look, resolved against THEME,
// is THEME's interface font, so the Fonts page reaches the look's text.
function lookFollowsInterfaceFont(judge, table, light, theme) {
    const result = judge.acceptAppearance(table, light, theme);
    assert.equal(result.ok, true, result.ok ? "" : judge.refusalLine(result));
    const families = judge.leaves(table).filter(entry => entry.leaf.type === "family");
    assert.ok(families.length > 0, "the look draws text in a family");
    for (const entry of families)
        assert.equal(at(result.values, entry.path), at(theme, "font.family.sans"), entry.path + " follows the interface font");
}

// The user's Appearance values over the theme (D104). Each expected value
// is the arithmetic its comment names, never read from the judge.
function verifyAppearance(judge) {
    const shipped = judge.defaults(TOKENS);
    const over = (theme, user) => {
        const result = judge.withAppearance(TOKENS, theme, user);
        assert.equal(result.ok, true, result.ok ? "" : judge.refusalLine(result));
        return result;
    };
    const accepted = tokens => {
        const result = judge.accept(TOKENS, document(tokens));
        assert.equal(result.ok, true, result.ok ? "" : judge.refusalLine(result));
        return result;
    };
    // No value, or an empty key, draws every package exactly as it draws
    // today: the shipped theme, every package under themes/ and every
    // catalog entry.
    const packages = [shipped].concat(fs.readdirSync(path.join(repo, "themes")).filter(name => fs.existsSync(path.join(repo, "themes", name, "theme.json")))
        .concat(fs.readdirSync(path.join(repo, "themes/catalog")).filter(name => fs.existsSync(path.join(repo, "themes/catalog", name, "theme.json"))).map(name => "catalog/" + name))
        .map(name => judge.accept(TOKENS, fs.readFileSync(path.join(repo, "themes", name, "theme.json"), "utf8"))));
    assert.ok(packages.length > 10, "the shipped and catalog packages are read");
    for (const theme of packages) {
        assert.equal(theme.ok, true);
        assert.deepEqual(plain(over(theme, {}).values), plain(theme.values), theme.name + ": no Appearance value");
        assert.deepEqual(plain(judge.published(TOKENS, theme, "").values), plain(theme.values), theme.name + ": no appearance key");
    }
    // A corner radius of 12: windows 12, flyouts 12 * 0.75 = 9, group tabs
    // 12 * 0.5 = 6; a menu entry follows its menu.
    const twelve = over(shipped, { windowRadius: 12 }).values;
    assert.deepEqual([at(twelve, "hyprland.window.radius"), at(twelve, "surface.radius"), at(twelve, "popover.radius"), at(twelve, "menu.radius"), at(twelve, "menu.item.radius"), at(twelve, "dialog.radius"), at(twelve, "osd.radius"), at(twelve, "hyprland.window.groupRadius")],
        [12, 9, 9, 9, 9, 9, 9, 6], "a corner radius of 12 and its ratios");
    assert.equal(at(twelve, "button.radius"), 0, "the corner radius leaves controls to the UI base");
    // 13: 13 * 0.75 = 9.75 rounds to 10, 13 * 0.5 = 6.5 rounds to 7.
    const thirteen = over(shipped, { windowRadius: 13 }).values;
    assert.deepEqual([at(thirteen, "surface.radius"), at(thirteen, "hyprland.window.groupRadius")], [10, 7], "lengths round to whole pixels");
    const controls = over(shipped, { controlRadius: 6 }).values;
    assert.deepEqual([at(controls, "button.radius"), at(controls, "textField.radius"), at(controls, "segmented.radius"), at(controls, "surface.radius"), at(controls, "checkbox.radius")], [6, 6, 6, 0, 0], "a control radius sets buttons, inputs and segmented controls alone");
    assert.equal(at(over(shipped, { borderWidth: 5 }).values, "hyprland.border.size"), 5, "a border width sets the window border");
    // A theme's own radius stands without a ratio, and a user's value wins
    // over a theme's.
    const roundTheme = accepted({ hyprland: { window: { radius: 12 } }, button: { radius: 2 }, surface: { radius: 3 } });
    assert.deepEqual([at(roundTheme.values, "surface.radius"), at(roundTheme.values, "hyprland.window.groupRadius")], [3, 12], "the theme's values stand without a ratio");
    assert.deepEqual(plain(over(roundTheme, {}).values), plain(roundTheme.values), "no value keeps the theme's own");
    const userWins = over(roundTheme, { windowRadius: 8, controlRadius: 4 }).values;
    assert.deepEqual([at(userWins, "surface.radius"), at(userWins, "button.radius")], [6, 4], "a user's value wins over the theme's");
    // Motion: off stills every duration, a speed of 2 halves each,
    // 150 / 2 = 75, and Snappy sets the preset and both easings.
    const still = over(shipped, { motion: false }).values;
    assert.deepEqual([at(still, "motion.scale"), at(still, "motion.duration.normal"), at(still, "motion.list.enter.duration")], [0, 0, 0], "motion off stills the shell");
    const fast = over(shipped, { motionSpeed: 2 }).values;
    assert.deepEqual([at(fast, "motion.scale"), at(fast, "motion.duration.normal")], [0.5, 75], "a speed of 2 halves every duration");
    const snappy = over(shipped, { motionStyle: "snappy" }).values;
    assert.deepEqual([at(snappy, "hyprland.motion.preset"), at(snappy, "motion.easing.standard"), at(snappy, "motion.easing.emphasized"), at(snappy, "motion.list.travel.easing")], ["snappy", "outQuart", "outExpo", "outExpo"], "Snappy sets the preset and the easings");
    const smooth = over(accepted({ hyprland: { motion: { preset: "snappy" } }, motion: { easing: { standard: "linear" } } }), { motionStyle: "smooth" }).values;
    assert.deepEqual([at(smooth, "hyprland.motion.preset"), at(smooth, "motion.easing.standard"), at(smooth, "motion.easing.emphasized")], ["smooth", "outCubic", "outQuint"], "Smooth sets the table's own preset and easings over a theme's");
    const stillTheme = accepted({ motion: { scale: 0 } });
    const moved = over(stillTheme, { motion: true }).values;
    assert.deepEqual([at(moved, "motion.scale"), at(moved, "motion.duration.normal")], [1, 150], "Motion on over a still theme moves at speed 1");
    assert.equal(at(over(stillTheme, { motion: true, motionSpeed: 0.5 }).values, "motion.scale"), 2, "and at a slower speed, 1 / 0.5");
    assert.equal(at(over(stillTheme, { motionSpeed: 2 }).values, "motion.scale"), 0, "a speed alone does not move a still theme");
    assert.equal(at(over(shipped, { motion: false, motionSpeed: 2 }).values, "motion.scale"), 0, "a speed does not move motion that is off");
    // Fonts: the interface font sets the reading text and the capitals and
    // leaves code and key names; a theme's fixed-width family reaches the
    // capitals until the user sets a font; the terminal font sets no token.
    const fonts = over(shipped, { interfaceFont: "Noto Serif" }).values;
    assert.deepEqual([at(fonts, "font.family.sans"), at(fonts, "text.body.family"), at(fonts, "text.h1.family"), at(fonts, "text.bar.family"), at(fonts, "text.label.family"), at(fonts, "text.button.family"), at(fonts, "text.eyebrow.family")],
        ["Noto Serif", "Noto Serif", "Noto Serif", "Noto Serif", "Noto Serif", "Noto Serif", "Noto Serif"], "the interface font sets the reading text and the capitals");
    assert.deepEqual([at(fonts, "font.family.mono"), at(fonts, "text.code.family"), at(fonts, "text.kbd.family"), at(fonts, "text.itemCode.family")],
        ["JetBrains Mono", "JetBrains Mono", "JetBrains Mono", "JetBrains Mono"], "and leaves code and key names in the fixed-width family");
    const monoTheme = accepted({ font: { family: { mono: "Courier", sans: "Serif" } } });
    assert.deepEqual([at(monoTheme.values, "text.bar.family"), at(monoTheme.values, "text.code.family")], ["Courier", "Courier"], "a theme's fixed-width family reaches the capitals");
    const overMono = over(monoTheme, { interfaceFont: "Noto Serif" }).values;
    assert.deepEqual([at(overMono, "text.body.family"), at(overMono, "text.bar.family"), at(overMono, "text.code.family")], ["Noto Serif", "Noto Serif", "Courier"], "a user's interface font wins over a theme's families");
    // A plugin-owned look takes the resolved interface font (D023): the
    // user's font over the shipped theme and over a theme's own families.
    lookFollowsInterfaceFont(judge, FONT_LOOK, {}, fonts);
    lookFollowsInterfaceFont(judge, FONT_LOOK, {}, overMono);
    for (const [label, look] of FIXED_FAMILY_LOOKS)
        assert.throws(() => lookFollowsInterfaceFont(judge, look, {}, fonts), /follows the interface font/, "control: " + label);
    // The launcher's look draws its text in it; its control is the look
    // with its old fixed family back.
    lookFollowsInterfaceFont(judge, LAUNCHER.TOKENS, LAUNCHER.LIGHT, fonts);
    lookFollowsInterfaceFont(judge, LAUNCHER.TOKENS, LAUNCHER.LIGHT, overMono);
    const fixedLauncher = Object.assign({}, LAUNCHER.TOKENS, { font: { family: { type: "family", value: "JetBrains Mono" } } });
    assert.throws(() => lookFollowsInterfaceFont(judge, fixedLauncher, LAUNCHER.LIGHT, fonts), /follows the interface font/, "control: the launcher's fixed JetBrains Mono");
    // The notifications' look draws its text in it; its control is the look
    // with its old fixed family back.
    lookFollowsInterfaceFont(judge, NOTIFICATIONS.TOKENS, NOTIFICATIONS.LIGHT, fonts);
    lookFollowsInterfaceFont(judge, NOTIFICATIONS.TOKENS, NOTIFICATIONS.LIGHT, overMono);
    const fixedNotifications = Object.assign({}, NOTIFICATIONS.TOKENS, { font: { family: { type: "family", value: "Liberation Sans" } } });
    assert.throws(() => lookFollowsInterfaceFont(judge, fixedNotifications, NOTIFICATIONS.LIGHT, fonts), /follows the interface font/, "control: the notifications' fixed Liberation Sans");
    const terminal = over(shipped, { terminalFont: "Fira Code" });
    assert.deepEqual(plain(terminal.values), plain(shipped.values), "the terminal font sets no token");
    assert.deepEqual([terminal.appearance.values.terminalFont, terminal.appearance.sources.terminalFont, Object.hasOwn(terminal.appearance.theme, "terminalFont")], ["Fira Code", "user", false], "and is the user's value, with none of the theme's to show");
    // A font named as the Hyprland choice is a font: no layer group stands behind it.
    const named = over(shipped, { interfaceFont: "hyprland" });
    assert.deepEqual([named.appearance.sources.interfaceFont, at(named.values, "text.body.family")], ["user", "hyprland"], "a family is never the Hyprland source");
    // Where each value comes from, what the theme shows, and which layer
    // groups the user leaves to Hyprland.
    const plainResult = over(shipped, {}).appearance;
    assert.deepEqual(plain(plainResult.sources), { windowRadius: "theme", borderWidth: "theme", controlRadius: "theme", motion: "theme", motionStyle: "theme", motionSpeed: "theme", windowAnimations: "hyprland", interfaceFont: "theme", terminalFont: "theme", glass: "surface", windowGlass: "hyprland", windowGlow: "hyprland" }, "every value from the theme, animations, window glass and glow from Hyprland, glass from each surface");
    assert.deepEqual(plain(plainResult.hyprland), { radius: true, borders: true, motion: false, glass: false, glow: false, surfaceBlur: false }, "the layer writes borders and radius and leaves animations, window glass and glow");
    assert.deepEqual(plain(plainResult.theme), { motion: true, motionStyle: "smooth", motionSpeed: 1, windowRadius: 0, borderWidth: 2, controlRadius: 0, interfaceFont: "Inter Variable" }, "the theme's own values");
    assert.equal(over(accepted({ motion: { scale: 2 } }), {}).appearance.theme.motionSpeed, 0.5, "a theme's speed is 1 / its scale");
    const own = over(shipped, { windowRadius: "hyprland", borderWidth: "hyprland", windowAnimations: true, controlRadius: 4 }).appearance;
    assert.deepEqual(plain([own.sources.windowRadius, own.sources.borderWidth, own.sources.windowAnimations, own.sources.controlRadius]), ["hyprland", "hyprland", "user", "user"], "Use my Hyprland value is its own source");
    assert.deepEqual(plain(own.hyprland), { radius: false, borders: false, motion: true, glass: false, glow: false, surfaceBlur: false }, "the layer leaves the groups the user keeps and writes the motion the user chose");
    // VGlass: the effective window glass is the windows' own choice under
    // the user's `glass`, which turns it on or off for every surface; the
    // shell's own layers and popups take the blur only while every surface
    // draws glass. Each row: [glass, windowGlass, the layer writes window
    // glass, the layer blurs the shell's surfaces].
    for (const [glass, windowGlass, want, surfaces] of [[undefined, undefined, false, false], [undefined, true, true, false], ["on", undefined, true, true], ["on", true, true, true], ["off", undefined, false, false], ["off", true, false, false]]) {
        const user = {};
        if (glass !== undefined) user.glass = glass;
        if (windowGlass !== undefined) user.windowGlass = windowGlass;
        const result = over(shipped, user).appearance;
        assert.equal(result.hyprland.glass, want, "window glass under glass=" + glass + " windowGlass=" + windowGlass);
        assert.equal(result.hyprland.surfaceBlur, surfaces, "surface blur under glass=" + glass + " windowGlass=" + windowGlass);
        assert.deepEqual([result.sources.glass, result.sources.windowGlass], [glass === undefined ? "surface" : "user", windowGlass === undefined ? "hyprland" : "user"], "glass sources under glass=" + glass + " windowGlass=" + windowGlass);
    }
    assert.deepEqual(plain(over(shipped, { glass: "off", windowGlass: true }).values), plain(shipped.values), "VGlass draws no token of the shell's table");
    // The glass corner: while the user's glass is on, a menu, a dialog, a
    // popover and an OSD whose corner would be 0 take radius.glass, 16, a
    // menu entry following its menu; a corner above 0 stands, the theme's
    // or the user's 24 * 0.75 = 18, as with glass off; a panel and a
    // tooltip are never set. Each row: [label, theme, user, the four
    // corners and the menu entry's, the panel's, the tooltip's].
    const squareCorners = [0, 0, 0, 0, 0], glassCorners = [16, 16, 16, 16, 16];
    for (const [label, theme, user, corners, panel, tooltip] of [
        ["a square theme, glass on", shipped, { glass: "on" }, glassCorners, 0, 0],
        ["a square theme, glass off", shipped, { glass: "off" }, squareCorners, 0, 0],
        ["a square theme, glass unset", shipped, {}, squareCorners, 0, 0],
        ["a square theme, the windows' own glass", shipped, { windowGlass: true }, squareCorners, 0, 0],
        ["a user's corner radius of 24, glass on", shipped, { glass: "on", windowRadius: 24 }, [18, 18, 18, 18, 18], 18, 0],
        ["a user's corner radius of 24, glass off", shipped, { glass: "off", windowRadius: 24 }, [18, 18, 18, 18, 18], 18, 0],
        ["a user's corner radius of 0, glass on", shipped, { glass: "on", windowRadius: 0 }, glassCorners, 0, 0],
        ["the user's own Hyprland radius, glass on", shipped, { glass: "on", windowRadius: "hyprland" }, glassCorners, 0, 0],
        ["a rounded theme, glass on", accepted({ radius: { sm: 4, md: 8 } }), { glass: "on" }, [8, 8, 8, 8, 8], 8, 4],
        ["a theme that rounds its menu alone, glass on", accepted({ menu: { radius: 6 } }), { glass: "on" }, [6, 16, 16, 16, 6], 0, 0],
        ["a theme's own glass corner", accepted({ radius: { glass: 10 } }), { glass: "on" }, [10, 10, 10, 10, 10], 0, 0]
    ]) {
        const values = over(theme, user).values;
        assert.deepEqual(["menu.radius", "dialog.radius", "popover.radius", "osd.radius", "menu.item.radius"].map(token => at(values, token)), corners, label);
        assert.deepEqual([at(values, "surface.radius"), at(values, "tooltip.radius")], [panel, tooltip], label + ": the panel and the tooltip");
    }
    // Window glow: the windows' own choice, written only while window glass
    // is. Each row: [glass, windowGlass, windowGlow, the layer writes glow].
    for (const [glass, windowGlass, windowGlow, want] of [[undefined, undefined, undefined, false], [undefined, true, undefined, false], [undefined, true, true, true], [undefined, undefined, true, false],
        ["on", undefined, true, true], ["on", undefined, undefined, false], ["off", true, true, false], ["off", undefined, true, false]]) {
        const user = {};
        if (glass !== undefined) user.glass = glass;
        if (windowGlass !== undefined) user.windowGlass = windowGlass;
        if (windowGlow !== undefined) user.windowGlow = windowGlow;
        const result = over(shipped, user).appearance;
        assert.equal(result.hyprland.glow, want, "window glow under " + JSON.stringify(user));
        assert.equal(result.sources.windowGlow, windowGlow === undefined ? "hyprland" : "user", "glow source under " + JSON.stringify(user));
    }
    // glassOn: a surface's own choice, which `glass` overrides either way.
    // Each row: [values, optIn, want].
    for (const [values, optIn, want] of [[{}, false, false], [{}, true, true], [{ glass: "on" }, false, true], [{ glass: "on" }, true, true], [{ glass: "off" }, false, false], [{ glass: "off" }, true, false], [{}, "yes", false]])
        assert.equal(judge.glassOn(values, optIn), want, "glassOn(" + JSON.stringify(values) + ", " + JSON.stringify(optIn) + ")");
    assert.deepEqual(plain(over(shipped, { windowRadius: "hyprland" }).values), plain(shipped.values), "Use my Hyprland value leaves the shell's surfaces on the theme");
    // A member the judge refuses is left out, listed by key, and shows as
    // Set by theme.
    const refused = over(shipped, { windowRadius: 40, controlRadius: "hyprland", motion: "yes", motionStyle: "bouncy", motionSpeed: 3, windowAnimations: false, corner: 4, borderWidth: -1, glass: "auto", windowGlass: false, windowGlow: "on" });
    assert.deepEqual(plain(refused.refusals.map(row => row.key)), ["windowRadius", "controlRadius", "motion", "motionStyle", "motionSpeed", "windowAnimations", "corner", "borderWidth", "glass", "windowGlass", "windowGlow"], "each bad member is refused by key");
    assert.ok(refused.refusals.every(row => row.line.startsWith("refused: ")), "each refusal is a keyed line");
    assert.deepEqual(plain(refused.values), plain(shipped.values), "refused members draw the theme");
    assert.deepEqual(plain(refused.appearance.values), {}, "refused members hold no value");
    for (const [key, value] of [["windowRadius", 32], ["windowRadius", 0], ["windowRadius", "hyprland"], ["borderWidth", 20], ["borderWidth", "hyprland"], ["controlRadius", 16], ["motion", true], ["motion", false], ["motionStyle", "smooth"], ["motionSpeed", 0.5], ["motionSpeed", 2], ["windowAnimations", true], ["glass", "on"], ["glass", "off"], ["windowGlass", true], ["windowGlow", true],
        ["interfaceFont", "Inter Variable"], ["terminalFont", "JetBrainsMono Nerd Font"], ["terminalFont", "Noto Sans Mono CJK JP"], ["terminalFont", "M+ 1mn"], ["interfaceFont", "x".repeat(100)]])
        assert.equal(judge.appearanceRefusal(key, value), "", key + "=" + JSON.stringify(value) + " is accepted");
    for (const [key, value] of [["windowRadius", 33], ["windowRadius", "12"], ["windowRadius", 12.5], ["borderWidth", 0.5], ["controlRadius", 4.25], ["borderWidth", 21], ["controlRadius", 17], ["controlRadius", "hyprland"], ["motionSpeed", 0.25], ["motionSpeed", "hyprland"], ["motion", "hyprland"], ["windowAnimations", false], ["motionStyle", "none"], ["corner", 1], ["windowRadius", undefined], ["glass", true], ["glass", "auto"], ["glass", "hyprland"], ["windowGlass", false], ["windowGlass", "on"], ["windowGlow", false], ["windowGlow", "on"],
        // A family: text, with nothing that ends or changes the terminal's
        // configuration line and nothing the resolver reads as a reference.
        ["terminalFont", ""], ["terminalFont", 12], ["terminalFont", ["Fira Code"]], ["terminalFont", " Fira Code"], ["terminalFont", "Fira Code "], ["terminalFont", "x".repeat(101)],
        ["terminalFont", "Fira Code\nmap ctrl+a launch sh"], ["terminalFont", "Fira\rCode"], ["terminalFont", "Fira\tCode"], ["terminalFont", "Fira\u0085Code"], ["terminalFont", "Fira\u2028Code"], ["terminalFont", "Fira\u2029Code"],
        ["terminalFont", "Fira\u007fCode"], ["terminalFont", "Fira \"Code\""], ["terminalFont", "Fira\\Code"], ["terminalFont", "family=Fira Code"], ["interfaceFont", "{font.family.mono}"], ["interfaceFont", "Fira}"], ["interfaceFont", "hyprland\n"]])
        assert.ok(judge.appearanceRefusal(key, value).startsWith("refused: "), key + "=" + JSON.stringify(value) + " is refused");
    // What Theme publishes: the values, the frozen sources and a line per
    // refused member. A value the
    // theme's own expressions cannot take draws the theme alone: here a
    // theme's offset of 300 control radii leaves the length range.
    const text = JSON.stringify({ windowRadius: 12, controlRadius: 99 });
    const published = judge.published(TOKENS, shipped, text);
    assert.ok(Object.isFrozen(published.appearance) && Object.isFrozen(published.appearance.sources), "the publication is frozen");
    assert.equal(at(published.values, "surface.radius"), 9, "the publication resolves the accepted members");
    assert.equal(published.logs.length, 1, "one line per refused member");
    const brittle = accepted({ focusRing: { offset: "mul({button.radius}, 300)" } });
    assert.equal(judge.withAppearance(TOKENS, brittle, { controlRadius: 16 }).ok, false, "16 * 300 = 4800 leaves the length range");
    const fallback = judge.published(TOKENS, brittle, JSON.stringify({ controlRadius: 16 }));
    assert.deepEqual([plain(fallback.values), fallback.logs.length], [plain(brittle.values), 1], "a resolver refusal is logged and draws the theme alone");
    assert.equal(fallback.appearance.sources.controlRadius, "theme", "and shows the value as Set by theme");
}
verify(load(judgeFile));

// The production judge owns the rendering margin. These old catalogue
// amounts passed token contrast but fail the sampled-stroke floor.
function verifyHintMargin(judge) {
    for (const [name, oldInk, expected] of [
        ["vgs", "#7d7d7e", null],
        ["catalog/flexoki-light", "#6b6965", null],
        ["catalog/catppuccin-latte", "mix({palette.foreground}, {palette.background}, 0.13)", 4.342148561625259],
        ["catalog/dracula", "mix({palette.foreground}, {palette.background}, 0.41)", 4.368422119504450],
        ["catalog/nord", "mix({palette.foreground}, {palette.background}, 0.29)", 4.338940848008551]
    ]) {
        const source = JSON.parse(fs.readFileSync(path.join(repo, "themes", name, "theme.json"), "utf8"));
        source.tokens.color = { ...source.tokens.color, textFaint: oldInk };
        const values = judge.accept(TOKENS, JSON.stringify(source)).values;
        assert.ok(judge.contrastRatio(judge.parseColor(values.color.textFaint), judge.parseColor(values.color.surfaceRaised)) >= 4.5, name + ": old token contrast passes");
        const row = readability(judge, values).find(row => row.text === "color.textFaint" && row.surface === "color.surfaceRaised");
        assert.ok(row, name + ": old hint is refused by stroke-core contrast");
        assert.equal(row.floor, 4.5);
        if (expected !== null) assert.ok(Math.abs(row.ratio - expected) < 1e-12, name + ": rounded stroke-core ratio");
        assert.ok(!readability(judge, values).some(row => row.text === "color.textFaint" && row.surface === "color.background"), name + ": its background also clears the drawn floor");
    }
}

// Native fixed-stem medians from VGS-1658, main 9ebf4e75f, measured
// with Pillow on 2026-10-13. The model can read low, never high.
function verifyDrawnWeights(judge) {
    for (const [theme, weight, ink, fill, measured, predicted] of [
        ["dracula", 400, "#a9aaab", "#383944", 4.688598365121197, 4.688598365121197],
        ["flexoki-light", 400, "#64625e", "#edeadf", 4.751705100405833, 4.690615181927497],
        ["dracula", 600, "#ff7a7a", "#383944", 4.527718224903436, 4.527718224903436],
        ["flexoki-light", 600, "#b64339", "#edeadf", 4.527591635617860, 4.527591635617860]
    ]) {
        const ratio = judge.drawnTextRatio(judge.parseColor(ink), judge.parseColor(fill), weight);
        assert.ok(ratio <= measured + 1e-12, theme + ": model never exceeds the fixed-stem median");
        assert.ok(Math.abs(ratio - predicted) < 1e-12, theme + ": drawn weight ratio");
    }
    const fill = judge.parseColor("#edeadf");
    const danger = judge.parseColor("#b64339");
    const lighter = judge.parseColor("#b74339");
    assert.ok(judge.drawnTextRatio(danger, fill, 600) >= 4.5, "original flexoki-light bodyStrong danger clears the floor");
    const failed = judge.drawnTextRatio(lighter, fill, 600);
    assert.ok(Math.abs(failed - 4.499039530534811) < 1e-12, "one red unit lighter: drawn danger ratio");
    assert.ok(failed < 4.5, "control: one red unit lighter fails the drawn floor");
    // Isolate bodyStrong: other danger uses draw bold, then this actual
    // role moves to regular. Omitting it would silently skip the failure.
    const text = Object.fromEntries(["body", "hint", "itemHint", "bodyStrong", "bar"].map(role => [role, { weight: 600 }]));
    const fixture = (weight, ink = "#b64339") => judge.accept(TOKENS, document({ color: { danger: ink, surfaceRaised: "#edeadf" }, text: { ...text, bodyStrong: { weight } } })).values;
    const dangerRows = (weight, ink) => readability(judge, fixture(weight, ink)).filter(row => row.text === "color.danger" && row.surface === "color.surfaceRaised");
    assert.equal(dangerRows(600).length, 0, "all drawn danger weights clear the floor");
    assert.equal(dangerRows(600, "#b74339").length, 1, "control: the judge rejects one red unit lighter at bodyStrong weight");
    assert.equal(dangerRows(400).length, 1, "the actual bodyStrong weight is judged");
    verifyDrawingWeightSources(judge);
    // Every default typography colour has its drawing role represented.
    for (const [role, type] of Object.entries(TOKENS.text)) {
        const colour = /^\{(color\.[^}]+)\}$/.exec(type.color.value);
        const source = role === "keyHint" ? "text.keyHint.color" : colour === null ? null : colour[1];
        assert.ok(source && judge.readabilityWeights(judge.defaults(TOKENS).values)[source].includes("text." + role + ".weight"), role + ": typography is judged at its own weight");
    }
}

// Each real drawing source can fail alone while the other sources use
// bold ink. The expectations name shipped sites independently of the table.
function verifyDrawingWeightSources(judge) {
    const cases = [
        ["color.textMuted", "text.bodyStrong.weight"], // ThemeCard, WallpaperCard, Console
        ["color.textMuted", "text.code.weight"], // Polkit Prompt
        ["color.textMuted", "text.item.weight"], // SaveBar
        ["color.textMuted", "text.button.weight"], // Tabs
        ["color.textMuted", "text.kbd.weight"], // Mono chrome
        ["text.keyHint.color", "text.keyHint.weight"], // KeyHints
        ["color.textFaint", "text.item.weight"], // TextField and Select placeholders
        ["color.textFaint", "text.body.weight"], // TextArea placeholder
        ["color.textFaint", "text.kbd.weight"], // ShortcutField placeholder
        ["color.accent", "text.label.weight"], // TileGroup's default caption
        ...["secondary", "tertiary", "ghost"].map(variant => ["color.text", "button.variant." + variant + ".weight"]),
        ...["primary", "secondary", "tertiary", "ghost", "danger"].map(variant => ["color.accent", "button.variant." + variant + ".weight"]), // checked Button
        ["color.text", "avatarGroup.weight"],
        ["color.warning", "text.bar.weight"], // BarItem's warning reading
        ["color.danger", "text.bar.weight"], // BarItem's danger reading
        ["carousel.hintActive", "text.bodyStrong.weight"], // WallpaperView's chosen scope word
        ["tooltip.detail", "text.itemHint.weight"],
        ["color.accent", "text.itemCode.weight", "itemCode"],
        ["color.textMuted", "text.itemCode.weight", "itemCode"]
    ];
    const assign = (tree, path, value) => {
        const parts = path.split(".");
        const leaf = parts.pop();
        const parent = parts.reduce((node, part) => node[part] ??= {}, tree);
        parent[leaf] = value;
    };
    for (const [colour, source, caption] of cases) {
        const given = caption === undefined ? {} : { tileGroup: { captionRole: caption } };
        const defaults = judge.accept(TOKENS, document(given)).values;
        for (const path of judge.readabilityWeights(defaults)[colour]) assign(given, path, 600);
        assign(given, colour, "#b64339");
        let surface = "color.surfaceRaised";
        if (colour === "tooltip.detail") surface = "tooltip.background";
        else if (colour === "carousel.hintActive") {
            surface = "color.scrim over #000000";
            given.color = { ...given.color, scrim: "alpha(#edeadf, 1)" };
        }
        assign(given, surface === "color.scrim over #000000" ? "color.surfaceRaised" : surface, "#edeadf");
        const rows = weight => {
            assign(given, source, weight);
            const accepted = judge.accept(TOKENS, document(given));
            assert.equal(accepted.ok, true);
            return readability(judge, accepted.values).filter(row => row.text === colour && row.surface === surface);
        };
        assert.equal(rows(600).length, 0, colour + ": bold drawing sources pass");
        const regular = rows(400);
        assert.equal(regular.length, 1, colour + ": " + source + " is judged independently");
        assert.ok(Math.abs(regular[0].ratio - 4.291450265492549) < 1e-12, source + ": regular drawn ratio");
    }
}

{
    const judge = load(judgeFile);
    const catalog = judge.acceptCatalogIndex(TOKENS, fs.readFileSync(path.join(repo, "themes/catalog/index.json"), "utf8"));
    assert.equal(catalog.ok, true);
    for (const name of ["vgs", ...catalog.entries.map(entry => "catalog/" + entry.name)]) {
        const accepted = judge.accept(TOKENS, fs.readFileSync(path.join(repo, "themes", name, "theme.json"), "utf8"));
        assert.equal(accepted.ok, true, name);
        assert.deepEqual(plain(readability(judge, accepted.values)), [], name + ": every readability rule passes");
    }
}

// Catalog packages lift status fills independently of their palette. Helix
// mode labels consume onSuccess/success and onInfo/info from these tokens.
function verifyStatusText(table) {
    const judge = load(judgeFile);
    const statuses = ["success", "warning", "danger", "info"];
    const documents = [
        document({ palette: Object.fromEntries(statuses.map(name => [name, "#000000"])),
            color: Object.fromEntries(statuses.map(name => [name, "#ffffff"])) }),
        document({ palette: Object.fromEntries(statuses.map(name => [name, "#ffffff"])),
            color: Object.fromEntries(statuses.map(name => [name, "#000000"])) })
    ];
    const index = judge.acceptCatalogIndex(table, fs.readFileSync(path.join(repo, "themes/catalog/index.json"), "utf8"));
    assert.equal(index.ok, true);
    assert.ok(index.entries.some(entry => entry.name === "akane"));
    assert.ok(index.entries.some(entry => entry.name === "catppuccin-latte"));
    for (const entry of index.entries)
        documents.push(fs.readFileSync(path.join(repo, "themes/catalog", entry.name, "theme.json"), "utf8"));
    for (const text of documents) {
        const result = judge.accept(table, text);
        assert.equal(result.ok, true);
        for (const name of statuses) {
            const color = result.values.color;
            const on = "on" + name[0].toUpperCase() + name.slice(1);
            assert.equal(typeof color[on], "string");
            const foreground = judge.parseColor(color[on]);
            const background = judge.parseColor(color[name]);
            assert.notEqual(foreground, null);
            assert.notEqual(background, null);
            const ratio = judge.contrastRatio(foreground, background);
            assert.ok(ratio >= judge.READABILITY_FLOOR, `${result.name} ${on}/${name}: ${ratio}`);
        }
    }
}
verifyStatusText(TOKENS);

// The default theme and every theme the shipped catalog lists, each
// judged against TABLE, as [name, result]; the catalog lists flexoki-light
// at least, so a catalog read short fails here.
function shippedThemes(table) {
    const judge = load(judgeFile);
    const themes = [["vgs", judge.defaults(table)]];
    const index = judge.acceptCatalogIndex(table, fs.readFileSync(path.join(repo, "themes/catalog/index.json"), "utf8"));
    assert.equal(index.ok, true);
    assert.ok(index.entries.some(entry => entry.name === "flexoki-light"), "the shipped catalog lists flexoki-light");
    for (const entry of index.entries)
        themes.push([entry.name, judge.accept(table, fs.readFileSync(path.join(repo, "themes/catalog", entry.name, "theme.json"), "utf8"))]);
    return themes;
}

// The bar separator the owner set: a 12 px line in the bar's text colour
// at 20% alpha, 0x33 of 0xff, in the default theme and every shipped one.
function verifyBarSeparator(table) {
    for (const [name, result] of shippedThemes(table)) {
        assert.equal(result.ok, true, name);
        const line = at(result.values, "bar.spacer.line");
        assert.equal(line.slice(0, 7), at(result.values, "bar.foreground").slice(0, 7), `${name} bar.spacer.line colour`);
        assert.ok(Math.abs(parseInt(line.slice(7), 16) - 0x33) <= 1, `${name} bar.spacer.line alpha ${line}`);
        assert.equal(at(result.values, "bar.spacer.height"), 12, `${name} bar.spacer.height`);
    }
}
verifyBarSeparator(TOKENS);

// Two stacked lines fit the bar item at every height the judge lets a
// theme give it, its whole length range and odd heights between, and the
// stacked text is smaller than the bar text. Each line's icon fits its
// line.
function verifyBarStacked(table) {
    const judge = load(judgeFile);
    const defaults = judge.defaults(table).values;
    assert.ok(at(defaults, "bar.stacked.size") < at(defaults, "text.bar.size"), "the stacked text is smaller than the bar text");
    for (const height of [0, 1, 7, 16, 23, 24, 25, 63, 4095, 4096]) {
        const result = judge.accept(table, document({ bar: { item: { height: height } } }));
        assert.equal(result.ok, true, `item height ${height}`);
        const line = at(result.values, "bar.stacked.lineHeight");
        assert.ok(2 * line <= height, `item height ${height}: two ${line} px lines`);
        assert.ok(at(result.values, "bar.stacked.size") <= line, `item height ${height}: the text fits its line`);
        assert.ok(at(result.values, "bar.stacked.icon") <= line, `item height ${height}: the icon fits its line`);
    }
}
verifyBarStacked(TOKENS);

// A clipped bar zone's button sits on the bar's own colour, and its fade
// runs from that colour to the same colour clear, in the default theme
// and every shipped one, so the fade shows no band of another colour.
function verifyBarScroll(table) {
    for (const [name, result] of shippedThemes(table)) {
        assert.equal(result.ok, true, name);
        const background = at(result.values, "bar.background");
        assert.equal(at(result.values, "bar.scroll.backdrop"), background, `${name} bar.scroll.backdrop`);
        assert.equal(at(result.values, "bar.scroll.clear"), background.slice(0, 7) + "00", `${name} bar.scroll.clear`);
    }
}
verifyBarScroll(TOKENS);

// A failure line beside the rail rests on its solid plate, and draws the
// theme's danger where it reads 4.5:1 on that plate and the theme's text
// colour where it does not, by the ratio and never by the theme's mode.
// The default danger #f43f5e reads 5.36:1 on its surface #0b0b0b.
// catppuccin-latte's surface is #e7e9ee, luminance 0.814: its palette's
// danger #d20f39, luminance 0.143, reads 4.47:1 there, (0.814 + 0.05) /
// (0.143 + 0.05), and the line draws its text #4c4f69; the catalog's
// danger, that red moved 0.03 toward black, #cc0f37, luminance 0.135,
// reads 4.68:1 and the line draws it. In every shipped theme the plate is
// solid and the line reads 4.5:1 on it, whatever the wallpaper.
function verifyFailureLine(table) {
    const judge = load(judgeFile);
    const own = judge.accept(table, document({}));
    assert.equal(own.ok, true, own.ok ? "" : judge.refusalLine(own));
    for (const [name, result] of shippedThemes(table)) {
        assert.equal(result.ok, true, name);
        const plate = judge.parseColor(at(result.values, "carousel.failurePlate"));
        assert.equal(plate.a, 1, `${name} carousel.failurePlate is solid`);
        assert.ok(judge.contrastRatio(judge.parseColor(at(result.values, "carousel.hintDanger")), plate) >= 4.5, `${name} carousel.hintDanger reads on its plate`);
    }
    const latte = danger => {
        const accepted = judge.accept(table, document({ scheme: { mode: "light" }, palette: { background: "#eff1f5", foreground: "#4c4f69", danger: "#d20f39" }, color: { danger: danger } }));
        assert.equal(accepted.ok, true, accepted.ok ? "" : judge.refusalLine(accepted));
        return accepted.values.carousel.hintDanger;
    };
    assert.equal(judge.defaults(table).values.carousel.hintDanger, "#f43f5eff", "a dark theme whose danger reads keeps it");
    assert.equal(latte("{palette.danger}"), "#4c4f69ff", "a danger under the floor on the plate draws the theme's text");
    assert.equal(latte("mix({palette.danger}, contrast({palette.background}), 0.03)"), "#cc0f37ff", "a light theme whose danger reads keeps it");
}
verifyFailureLine(TOKENS);

// The open tab's indicator beside the rail keeps the theme's accent where
// it reads 3:1 on the backdrop and draws carousel.hintActive where it
// does not. The default accent reads 6.76:1 on black. catppuccin-latte's
// accent #1b5ddf, luminance 0.134, reads 1.37:1 on its backdrop #7b7c7e,
// (0.20 + 0.05) / (0.134 + 0.05), and the indicator draws black.
function verifyTabIndicator(table) {
    const judge = load(judgeFile);
    const latte = judge.accept(table, document({ scheme: { mode: "light" }, palette: { background: "#eff1f5", foreground: "#4c4f69", accent: "#1b5ddf" } }));
    assert.equal(latte.ok, true, latte.ok ? "" : judge.refusalLine(latte));
    assert.equal(judge.defaults(table).values.carousel.tabIndicator, "#ff5a36ff", "a theme whose accent reads keeps it");
    assert.equal(latte.values.carousel.tabIndicator, "#000000ff", "catppuccin-latte draws the label's ink");
}
verifyTabIndicator(TOKENS);

// The failure line of each browser view rests on its plate and leads
// with the danger mark, so the state does not rest on the line's colour
// nor the line on the wallpaper. This reads the view's source: it holds
// that the row sits in a rectangle filled with the plate and that the mark
// is declared before the line in that row, and the rendered line is the
// theme sheets' to show. The controls are the same source without the
// plate's fill and without the mark. The mark takes its top from its
// line's label, whose placement `scripts/qml-tests/tst_label.qml` holds;
// the control is the line-box placement.
const FAILURE_LINE = /Rectangle \{[^{}]*color: Theme\.carousel\.failurePlate[^{}]*Row \{[^{}]*Icon \{[^{}]*name: "circle-alert"[^{}]*\}\s*Label \{[^{}]*color: Theme\.carousel\.hintDanger/;
const FAILURE_MARK = /Icon \{[^{}]*name: "circle-alert"[^{}]*\}/;
const FAILURE_MARK_TOP = /Icon \{[^{}]*y: failureText\.topForLeadingIcon\(height\)[^{}]*name: "circle-alert"/;
for (const view of ["ThemeView.qml", "WallpaperView.qml"]) {
    const viewSource = fs.readFileSync(path.join(repo, "shell/plugins/vgs.themes", view), "utf8");
    assert.equal(viewSource.split("Theme.carousel.hintDanger").length, 2, `${view} draws one failure line`);
    assert.match(viewSource, FAILURE_LINE, `${view} leads its failure line with the danger mark`);
    assert.doesNotMatch(viewSource.replace(FAILURE_MARK, ""), FAILURE_LINE, `control: ${view} without the mark must fail the check`);
    assert.equal(viewSource.split("color: Theme.carousel.failurePlate").length, 2, `${view} fills its failure plate`);
    assert.doesNotMatch(viewSource.replaceAll("color: Theme.carousel.failurePlate", "color: Theme.carousel.backdrop"), FAILURE_LINE, `control: ${view} without the plate's fill must fail the check`);
    assert.match(viewSource, FAILURE_MARK_TOP, `${view} centres the mark on its line's leading icon centre`);
    assert.doesNotMatch(viewSource.replace("failureText.topForLeadingIcon(height)", "Math.round((failureText.lineBox - height) / 2)"), FAILURE_MARK_TOP, `control: ${view} with the mark on the line box must fail the check`);
}

// An icon that leads a line of text takes its top from that line's label.
// These source checks cover each placement binding and its consumer.
// The FormRow QML test verifies its rendered geometry.
const LED_LINES = [
    { file: "shell/Ui/feedback/SaveBar.qml", label: "savedText", icon: 'name: "check"' },
    { file: "shell/Ui/controls/TitleButton.qml", label: "label", icon: 'name: "chevron-down"' },
    { file: "shell/Ui/feedback/Callout.qml", label: "titleLabel", icon: "name: root.iconName" },
    { file: "shell/plugins/vgs.sysmon/Reading.qml", label: "titleLabel", icon: "name: root.iconName" },
    {
        file: "shell/plugins/vgs.themes/WallpaperView.qml", icon: "color: sourceText.color",
        binding: "y: sourceText.y + sourceText.topForLeadingIcon(height, sourceText.y, true)",
        centred: "anchors.verticalCenter: parent.verticalCenter"
    },
    { file: "shell/plugins/vgs.themes/ThemeRow.qml", label: "nameText", icon: "name: row.iconName" },
    {
        file: "shell/plugins/vgs.system/Window.qml", icon: "id: icon\n",
        binding: "y: title.y + title.topForLeadingIcon(height, title.y)",
        centred: "anchors.verticalCenter: parent.verticalCenter"
    },
    {
        file: "shell/plugins/vgs.polkit/Prompt.qml", icon: 'name: "user"',
        binding: "y: identityText.y + identityText.topForLeadingIcon(height, identityText.y)",
        centred: "anchors.verticalCenter: parent.verticalCenter"
    },
    {
        file: "shell/Ui/controls/TextField.qml", icon: "name: root.leadingIcon",
        binding: "y: placeholder.y + placeholder.topForLeadingIcon(height, placeholder.y)",
        centred: "anchors.verticalCenter: parent.verticalCenter"
    },
    {
        file: "shell/plugins/vgs.launcher/ContextMenu.qml", item: "Item", icon: "id: iconBox",
        binding: "y: entryText.y + entryReading.topForLeadingIcon(height, entryText.y)",
        centred: "anchors.verticalCenter: parent.verticalCenter"
    },
    {
        file: "shell/plugins/vgs.launcher/Launcher.qml", item: "SearchGlyph", icon: "id: searchGlyph",
        binding: "y: headerText.y + headerReading.topForLeadingIcon(height, headerText.y)",
        centred: "anchors.verticalCenter: parent.verticalCenter"
    },
    {
        file: "shell/Ui/controls/FormRow.qml", item: "Loader", icon: "id: infoButton",
        binding: "y: labelText.lineCount > 2 ? labelText.y + labelText.topForLeadingIcon(implicitHeight) : Math.round((root.labelBox - implicitHeight) / 2)",
        centred: "y: Math.round((root.labelBox - implicitHeight) / 2)"
    },
    {
        file: "shell/Ui/controls/RowAction.qml", icon: "id: mark\n",
        binding: "y: label.y + label.topForLeadingIcon(height, label.y, true)",
        centred: "y: Math.round(parent.half - height / 2)"
    },
    {
        file: "shell/plugins/vgs.google-drive/Panel.qml", icon: "id: mark\n",
        binding: "y: nameLabel.topForLeadingIcon(height, 0, reviewRow.linked && nameLabel.lineCount === 1)",
        centred: "anchors.verticalCenter: parent.verticalCenter"
    },
    {
        file: "shell/Ui/overlay/MenuItem.qml", icon: "id: icon\n",
        binding: "y: root.inkTop(icon) - parent.y",
        centred: "anchors.verticalCenter: parent.verticalCenter"
    }
];
for (const site of LED_LINES) {
    const binding = site.binding || `${site.label}.topForLeadingIcon(height)`;
    const ledIcon = source => (source.match(new RegExp(`\\b${site.item || "Icon"} \\{[^{}]*`, "g")) || []).filter(block => block.includes(site.icon));
    const levelled = source => ledIcon(source).length === 1 && ledIcon(source)[0].includes(binding) && !/anchors\.(?:centerIn|verticalCenter):/.test(ledIcon(source)[0]);
    const siteSource = fs.readFileSync(path.join(repo, site.file), "utf8");
    assert.equal(levelled(siteSource), true, `${site.file} centres its leading icon on its line's leading icon centre`);
    const targetBlock = ledIcon(siteSource)[0];
    const centredBlock = site.binding ? targetBlock.replace(binding, site.centred)
        : targetBlock.replace(new RegExp(`y: [^\\n;{}]*${binding.replace(/[.()]/g, "\\$&")}`), "anchors.verticalCenter: parent.verticalCenter");
    assert.notEqual(centredBlock, targetBlock, `control: ${site.file} replaces the target icon's binding`);
    const centred = siteSource.replace(targetBlock, centredBlock);
    assert.notEqual(centred, siteSource, `control: ${site.file} holds the call to replace`);
    assert.equal(levelled(centred), false, `control: ${site.file} with the icon on the row centre must fail the check`);
}

// A menu entry's icon, check mark and chevron take their top from inkTop,
// which centres each glyph's ink through the title's placement.
const menuItemSource = fs.readFileSync(path.join(repo, "shell/Ui/overlay/MenuItem.qml"), "utf8");
const MENU_INK_TOP = /readonly property real firstLineCentre: contentItem\.y \+ title\.y \+ title\.leadingIconCentre\r?\n[\s\S]*?function inkTop\(glyph\) \{\s*return title\.leadingIconTop\(glyph\.painted\[1\] \+ glyph\.painted\[3\], 0, firstLineCentre\);/;
assert.match(menuItemSource, MENU_INK_TOP, "menu entry glyphs use the shared label placement");
assert.doesNotMatch(menuItemSource.replace("title.leadingIconTop(glyph.painted[1] + glyph.painted[3], 0, firstLineCentre)", "title.capCentre - (glyph.painted[1] + glyph.painted[3]) / 2"), MENU_INK_TOP,
    "control: menu entry glyphs placed on the capital centre must fail the check");

// The launcher flyout's icon box reads its entry text through a Label that
// draws nothing and takes the entry text's own font and text, so the
// reading is the launcher look's font, not a text role's.
const contextMenuSource = fs.readFileSync(path.join(repo, "shell/plugins/vgs.launcher/ContextMenu.qml"), "utf8");
const FLYOUT_READING = /Label \{\s*id: entryReading\s*visible: false\s*text: entryText\.text\s*font: entryText\.font\s*\}/;
assert.match(contextMenuSource, FLYOUT_READING, "the launcher flyout reads its entry text in the entry's own font");
assert.doesNotMatch(contextMenuSource.replace("font: entryText.font", "role: \"item\""), FLYOUT_READING,
    "control: a flyout reading in a text role's font must fail the check");

// Each token control edits a copy of the shipped table, and the verifier
// it names must fail on that copy.
const tokenSource = fs.readFileSync(path.join(repo, "shell/Commons/Tokens.js"), "utf8");
function verifyTitleSpace(table) {
    assert.equal(table.stack.titleSpace.type, "body-lines");
    assert.equal(load(judgeFile).defaults(table).values.stack.titleSpace, 1);
}
verifyTitleSpace(TOKENS);
const TOKEN_CONTROLS = [
    ["title space", 'titleSpace: bodyLines(1)', 'titleSpace: bodyLines(1.2)', verifyTitleSpace],
    ["status text on its fill", 'color("contrast({color." + name + "})")', 'color("contrast({palette." + name + "})")', verifyStatusText],
    ["bar separator colour", 'line: color("alpha({bar.foreground}, 0.2)")', 'line: color("alpha({bar.foreground}, 0.4)")', verifyBarSeparator],
    ["bar separator height", 'height: length(12),\n            line:', 'height: length("{icon.size.md}"),\n            line:', verifyBarSeparator],
    ["stacked lines rounded past the item", 'lineHeight: length("mul({bar.item.height}, 0.48)")', 'lineHeight: length("mul({bar.item.height}, 0.5)")', verifyBarStacked],
    ["stacked icon past its line", 'icon: length("{bar.stacked.size}")', 'icon: length("{bar.item.height}")', verifyBarStacked],
    ["stacked text at the bar size", 'size: length("mul({bar.item.height}, 0.4)")', 'size: length("{text.bar.size}")', verifyBarStacked],
    ["bar scroll fade end", 'clear: color("alpha({bar.background}, 0)")', 'clear: color("alpha({bar.foreground}, 0)")', verifyBarScroll],
    ["bar scroll backdrop", 'backdrop: color("{bar.background}")', 'backdrop: color("{color.surface}")', verifyBarScroll],
    ["failure line danger forced", 'hintDanger: color("readable({color.danger}, {carousel.failurePlate}, {color.text})")', 'hintDanger: color("{color.danger}")', verifyFailureLine],
    ["failure plate translucent", 'failurePlate: color("alpha({color.surface}, 1)")', 'failurePlate: color("alpha({color.surface}, 0.9)")', verifyFailureLine],
    ["failure plate on the rail backdrop", 'failurePlate: color("alpha({color.surface}, 1)")', 'failurePlate: color("{carousel.backdrop}")', verifyFailureLine],
    ["open tab indicator forced to the accent", 'tabIndicator: color("discernible({color.accent}, {carousel.backdrop}, {carousel.hintActive})")', 'tabIndicator: color("{color.accent}")', verifyTabIndicator],
    ["open tab indicator without its accent", 'tabIndicator: color("discernible({color.accent}, {carousel.backdrop}, {carousel.hintActive})")', 'tabIndicator: color("{carousel.hintActive}")', verifyTabIndicator],
    ["failure line without its danger", 'hintDanger: color("readable({color.danger}, {carousel.failurePlate}, {color.text})")', 'hintDanger: color("{color.text}")', verifyFailureLine]
];
fs.mkdirSync(os.tmpdir(), { recursive: true });
const tokenControlDir = fs.mkdtempSync(path.join(require("node:os").tmpdir(), "token-control-"));
try {
    for (const [label, needle, replacement, verifier] of TOKEN_CONTROLS) {
        assert.equal(tokenSource.split(needle).length, 2, `token control "${label}": the text to replace must occur once`);
        const mutant = path.join(tokenControlDir, "Tokens.js");
        fs.writeFileSync(mutant, tokenSource.replace(needle, () => replacement));
        assert.throws(() => verifier(load(mutant).TOKENS), { code: "ERR_ASSERTION" }, `token control "${label}": the suite passed on that table`);
    }
} finally {
    fs.rmSync(tokenControlDir, { recursive: true, force: true });
}

// Each glass control edits a copy of Glass.js, and verifyGlass must fail
// on that copy.
const glassSource = fs.readFileSync(path.join(repo, "shell/Commons/Glass.js"), "utf8");
const GLASS_CONTROLS = [
    ["window shadow is the tight shadow", 'shadowColor: color("{shadow.tight.color}")', 'shadowColor: color("{shadow.wide.color}")'],
    ["light shadow", 'tight: { color: "alpha(#000000, 0.16)" }', 'tight: { color: "alpha(#000000, 0.2)" }'],
    ["blur size bound", "blurSize: whole(8, 1, 64)", "blurSize: whole(8, 1, 4096)"],
    ["the fill takes the theme's raised surface", 'fill: color("alpha({color.surfaceRaised}, 0.8)")', 'fill: color("alpha(#101010, 0.8)")'],
    ["the light fill takes the theme's raised surface", 'fill: "alpha({color.surfaceRaised}, 0.85)"', 'fill: "alpha(#f2f2f2, 0.85)"'],
    ["the dark fill's alpha", 'fill: color("alpha({color.surfaceRaised}, 0.8)")', 'fill: color("alpha({color.surfaceRaised}, 0.85)")'],
    ["the dark lift", "solidLift: share(0.05)", "solidLift: share(0.25)"],
    ["the light lift", "solidLift: 0.1", "solidLift: 0.05"]
];
const glassControlDir = fs.mkdtempSync(path.join(os.tmpdir(), "glass-control-"));
try {
    for (const [label, needle, replacement] of GLASS_CONTROLS) {
        assert.equal(glassSource.split(needle).length, 2, `glass control "${label}": the text to replace must occur once`);
        const mutant = path.join(glassControlDir, "Glass.js");
        fs.writeFileSync(mutant, glassSource.replace(needle, () => replacement));
        assert.throws(() => verifyGlass(load(judgeFile), load(mutant)), { code: "ERR_ASSERTION" }, `glass control "${label}": verifyGlass passed on that table`);
    }
} finally {
    fs.rmSync(glassControlDir, { recursive: true, force: true });
}
// Each launcher text reads on its own fill. GlassSurface makes the menu
// opaque and lifted over the card; with glass off it draws the theme's
// raised surface. The title/detail step compares both drawn inks on the
// same fill, by dividing their contrast ratios against that fill.
function launcherMenuFills(judge, look, values) {
    const glass = judge.acceptAppearance(GLASS.TOKENS, GLASS.LIGHT, values);
    assert.equal(glass.ok, true, glass.ok ? "" : judge.refusalLine(glass));
    return [judge.parseColor(judge.formatColor(judge.liftedOpaque(judge.parseColor(look.card.fill), glass.values.glass.solidLift))),
        judge.parseColor(values.surface.level.raised.background)];
}
function launcherTextReadings(judge, launcher, menuFills = launcherMenuFills) {
    const out = [];
    for (const { name, values } of JUDGED_THEMES) {
        const result = judge.acceptAppearance(launcher.TOKENS, launcher.LIGHT, values);
        assert.equal(result.ok, true, result.ok ? "" : judge.refusalLine(result));
        const look = result.values;
        const plate = fill => judge.overlay(judge.parseColor(look.highlight.plate), fill);
        const ratio = (ink, fill, weight) => judge.drawnTextRatio(judge.overlay(judge.parseColor(ink), fill), fill, weight);
        const grounds = ["#000000", "#ffffff"].map(w => judge.overlay(judge.parseColor(look.card.fill), judge.parseColor(w)));
        const solid = launcherMenuFills(judge, look, values);
        for (const [state, fill] of [...grounds, ...solid].entries()) {
            const title = judge.formatColor({ ...judge.parseColor(look.text.foreground), a: look.text.label.rest });
            out.push([name, "step", state, ratio(title, fill, look.text.label.weight) / ratio(look.text.detail.color, fill, 400)]);
            out.push([name, "empty", state, ratio(look.text.detail.color, fill, 400)]);
        }
        for (const [state, fill] of [...grounds, ...solid].map(plate).entries())
            for (const [role, ink] of [["link", look.text.link], ["detail", look.text.detail.color]])
                out.push([name, role, state, ratio(ink, fill, 400)]);
        for (const [state, fill] of menuFills(judge, look, values).flatMap(fill => [fill, plate(fill)]).entries())
            out.push([name, "menu", state, ratio(look.text.detail.color, fill, 400)]);
    }
    return out;
}
function launcherDetailShortfalls(judge, launcher) {
    return launcherTextReadings(judge, launcher).filter(([, role, , ratio]) => role !== "step" && ratio < judge.READABILITY_FLOOR);
}
{
    const judge = load(judgeFile);
    assert.deepEqual(launcherDetailShortfalls(judge, LAUNCHER), [], "the launcher's detail text and link read at 4.5:1 on the card in every theme");
    const readings = launcherTextReadings(judge, LAUNCHER);
    const checkStep = rows => assert.deepEqual(rows.filter(([, role, , ratio]) => role === "step" && ratio < 1.25), [], "launcher title/detail step is at least 1.25:1 in every theme");
    checkStep(readings);
    // Independent menu reading: vgs's lifted #212121 under its plate,
    // detail alpha 0.84 and regular stroke coverage, rounded as drawn.
    const checkMenuFill = rows => assert.ok(rows.some(([name, role, state, ratio]) => name === "vgs" && role === "menu" && state === 1 && ratio > 7.31 && ratio < 7.33), "launcher menu detail is judged on its own lifted fill");
    checkMenuFill(readings);
    assert.throws(() => checkMenuFill(launcherTextReadings(judge, LAUNCHER, (j, look) => [j.overlay(j.parseColor(look.card.fill), j.parseColor("#ffffff"))])), { code: "ERR_ASSERTION" }, "control: the menu judged on the launcher card's fill fails");
    // Controls: the link in the theme's accent alone, as LinkText draws it
    // by default, the detail text at a 0.5 fade, and the link picked on
    // the card itself, which reads there by the colours' ratio and falls
    // short as drawn in catppuccin-latte and ayu.
    const launcherSource = fs.readFileSync(path.join(repo, "shell/plugins/vgs.launcher/Appearance.js"), "utf8");
    const launcherControlDir = fs.mkdtempSync(path.join(require("node:os").tmpdir(), "launcher-control-"));
    try {
        for (const [role, needle, replacement, themes] of [
            ["link", /link: color\("readable\(.*\)"\),/g, 'link: color("{palette.accent}"),', ["vgs", "catalog/flexoki-light"]],
            ["detail", /color: color\("alpha\(\{text\.foreground\}, [0-9.]+\)"\) \},/g, 'color: color("alpha({text.foreground}, 0.5)") },', ["vgs", "catalog/flexoki-light"]],
            ["link", /linkGround: color\("mix\(.*\)"\),/g, 'linkGround: color("{card.nearInk}"),', ["catalog/catppuccin-latte", "catalog/ayu"]]
        ]) {
            assert.equal((launcherSource.match(needle) || []).length, 1, `launcher control "${role}": the text to replace must occur once`);
            const mutant = path.join(launcherControlDir, "Appearance.js");
            fs.writeFileSync(mutant, launcherSource.replace(needle, () => replacement));
            const short = launcherDetailShortfalls(judge, load(mutant));
            assert.ok(themes.every(theme => short.some(row => row[0] === theme && row[1] === role)), `launcher control "${role}": the planted colour is short in ${themes.join(" and ")}`);
            assert.ok(short.every(row => role === "detail" ? ["detail", "empty", "menu"].includes(row[1]) : row[1] === role), `launcher control "${role}": the other role still reads`);
        }
        const equalDetail = /color: color\("alpha\(\{text\.foreground\}, [0-9.]+\)"\) \},/g;
        assert.equal((launcherSource.match(equalDetail) || []).length, 1, "equal-title control replaces one detail colour");
        const mutant = path.join(launcherControlDir, "Appearance.js");
        fs.writeFileSync(mutant, launcherSource.replace(equalDetail, 'color: color("alpha({text.foreground}, {text.label.rest})") },'));
        const equalReadings = launcherTextReadings(judge, load(mutant));
        assert.throws(() => checkStep(equalReadings), { code: "ERR_ASSERTION" }, "control: detail equal to title fails the measured step");
        assert.ok(JUDGED_THEMES.every(({ name }) => equalReadings.some(([theme, role, , ratio]) => theme === name && role === "step" && ratio === 1)), "equal-title control reaches every theme");
    } finally {
        fs.rmSync(launcherControlDir, { recursive: true, force: true });
    }
    // The colour is the whole fade: no launcher view fades detail text or
    // the empty list's message through an opacity of the look. Control: a
    // view that does.
    const fadedSites = sources => sources.filter(([, text]) => /\.text\.(detail|empty)\.opacity\b/.test(text)).map(([name]) => name);
    const launcherDir = path.join(repo, "shell/plugins/vgs.launcher");
    const views = fs.readdirSync(launcherDir).filter(name => name.endsWith(".qml")).map(name => [name, fs.readFileSync(path.join(launcherDir, name), "utf8")]);
    assert.ok(views.some(([, text]) => text.includes(".text.detail.color")), "the launcher views are read");
    assert.deepEqual(fadedSites(views), [], "no launcher view fades detail text through the look's opacity");
    assert.deepEqual(fadedSites([["Faded.qml", "opacity: row.look.text.detail.opacity"]]), ["Faded.qml"], "launcher control: a faded detail site is named");
}

// Each control removes one rule's behaviour from a copy of the judge and
// keeps the text around it. The suite must fail on every copy.
const CONTROLS = [
    ["screensaver gradient is judged", '    ["screensaver.gradientStart", "screensaver.background"],\n', "", verifyScreensaver],
    ["screensaver fixed canvas", 'leaf.type === "color" && token === "screensaver.background" && (value.r !== 0 || value.g !== 0 || value.b !== 0 || value.a !== 1)', "false", verifyScreensaver],
    ["notice states the minimum", ' + ", needs " + shortfall.floor + ":1."', ' + "."'],
    ["notice names the main background", '"color.background": "the main background"', '"color.background": "desktop"'],
    ["notice names panel backgrounds", '"color.surface": "panel backgrounds"', '"color.surface": "panels"'],
    ["notice names its theme", '(displayName === null ? name : displayName) + ": some text may be hard to read"', '": some text may be hard to read"'],
    ["notice uses the display name", 'displayName === null ? name : displayName', 'name'],
    ["notice omits the repeated introduction", 'var lines = [];', 'var lines = ["Some parts may be hard to read."];'],
    ["notice groups each role", "if (!hasOwn(worst, row.text)) { worst[row.text] = row; roles.push(row.text); }", "if (true) { worst[row.text] = row; roles.push(row.text); }"],
    ["notice picks the weakest surface", "row.ratio < worst[row.text].ratio", "row.ratio > worst[row.text].ratio"],
    ["notice message limit", 'lines.concat([line]).join("\\n").length + tail.length > 600', 'lines.concat([line]).join("\\n").length + tail.length > 6000'],
    ["regular drawn ink", "regular: 0.966", "regular: 1"],
    ["bold drawn ink", "bold: 1.000", "bold: 0.966"],
    ["drawn ink on every text pair", "pairs[q][2] === READABILITY_FLOOR", "false"],
    ["danger bodyStrong drawn weight", '"color.danger": ["text.body.weight", "text.hint.weight", "text.itemHint.weight", "text.bodyStrong.weight", "text.bar.weight"]', '"color.danger": ["text.body.weight", "text.hint.weight", "text.itemHint.weight", "text.bar.weight"]'],
    ["muted bodyStrong drawing weight", '"text.value.weight", "text.bodyStrong.weight", "text.code.weight"', '"text.value.weight", "text.code.weight"'],
    ["button variant drawing weight", '"text.tooltip.weight", "button.variant.secondary.weight", "button.variant.tertiary.weight"', '"text.tooltip.weight", "button.variant.primary.weight", "button.variant.tertiary.weight"'],
    ["tooltip detail drawing weight", '"tooltip.detail": ["text.itemHint.weight"]', '"tooltip.detail": ["text.hint.weight"]'],
    ["selected TileGroup drawing weight", 'var tileWeight = "text." + valueAt(values, "tileGroup.captionRole") + ".weight";', 'var tileWeight = "text.label.weight";'],
    ["unknown top-level key", "if (DOCUMENT_KEYS.indexOf(keys[i]) === -1)", "if (false)"],
    ["schema version", "if (document.schemaVersion !== SCHEMA_VERSION)", "if (false)"],
    ["document name", 'if (typeof document.name !== "string" || document.name.trim() === "")', "if (false)"],
    ["document display name", 'if (typeof displayName !== "string" || displayName.trim() === "")', "if (false)"],
    ["absent display name is null", "var displayName = null;", 'var displayName = "";'],
    ["package carries its display name", "displayName: shell.displayName, ", ""],
    ["tokens shape", "if (!isPlainObject(tree))\n        return refusal(\"tokens\"", "if (false)\n        return refusal(\"tokens\""],
    ["unknown token", "if (known === undefined)", "if (false)"],
    ["value on a group", "else if (!isPlainObject(node[keys[i]]))", "else if (false)"],
    ["expression length", "if (text.length > MAX_EXPRESSION_LENGTH)", "if (false)"],
    ["expression depth", "if (depth > MAX_EXPRESSION_DEPTH)", "if (false)"],
    ["trailing text", "if (at !== text.length)", "if (false)"],
    ["unknown function", "if (!hasOwn(FUNCTIONS, tree.name))", "if (false)"],
    ["arity", "if (tree.args.length !== signature.args.length)", "if (false)"],
    ["readable holds the text floor", 'tree.name === "readable" ? READABILITY_FLOOR : BOUNDARY_FLOOR;', 'tree.name === "readable" ? BOUNDARY_FLOOR : BOUNDARY_FLOOR;'],
    ["discernible holds the mark floor", 'tree.name === "readable" ? READABILITY_FLOOR : BOUNDARY_FLOOR;', 'tree.name === "readable" ? READABILITY_FLOOR : 1;'],
    ["discernible keeps a mark under the text floor", 'tree.name === "readable" ? READABILITY_FLOOR : BOUNDARY_FLOOR;', 'tree.name === "readable" ? READABILITY_FLOOR : READABILITY_FLOOR;'],
    ["a colour that meets its floor is kept", ">= floor ? args[0] : args[2];", ">= floor ? args[2] : args[2];"],
    ["rail marks are judged", "pairs.push([RAIL_MARK_ROLES[x], MODAL_SCRIM, BOUNDARY_FLOOR, RAIL_WALLPAPER]);", ";"],
    ["the failure line is judged on its plate", "pairs.push([FAILURE_LINE, FAILURE_PLATE, READABILITY_FLOOR]);", ";"],
    ["readable refuses a translucent text colour", "return args[0].a === 1 && contrastRatio(", "return contrastRatio("],
    ["readable refuses a translucent backdrop", "if (args[1].a < 1)\n                return fail(\"contrast-translucent\"", "if (false)\n                return fail(\"contrast-translucent\""],
    ["unknown reference", "if (target === undefined)", "if (false)"],
    ["reference type", "if (target.type !== want)", "if (false)"],
    ["colour literal type", 'if (want !== "color")', "if (false)"],
    ["number literal type", "if (NUMERIC_TYPES.indexOf(want) === -1)\n                return fail", "if (false)\n                return fail"],
    ["flag literal type", 'if (want !== "flag")', "if (false)"],
    ["function result type", 'if (result !== want || (signature.result === "same" && NUMERIC_TYPES.indexOf(want) === -1))', "if (false)"],
    ["cycle", "if (visiting.indexOf(path) !== -1)", "if (false)"],
    ["mix amount", "if (args[2] < 0 || args[2] > 1)", "if (false)"],
    ["contrast mix floor", "if (contrastRatio(mix, background) >= ratio)", "if (true)"],
    ["alpha amount", "if (args[1] < 0 || args[1] > 1)", "if (false)"],
    ["translucent contrast", "if (args[0].a < 1)", "if (false)"],
    ["contrast choice", "1.05 / (light + 0.05) > (light + 0.05) / 0.05", "true"],
    ["family", 'if (typeof value !== "string" || value.trim() === "")', "if (false)"],
    ["option", "if (options.indexOf(value) === -1)", "if (false)"],
    ["whole rounding", "value = Math.round(value);", ""],
    ["duration scaling", "value = Math.round(value * scale);", ""],
    ["table motion scale", 'if (!isLeaf(scale) || scale.type !== "number")', "if (false)"],
    ["range", "if (value < range[0] || value > range[1])", "if (false)"],
    ["override wins", "hasOwn(overrides, path) ? overrides[path] : leaf.value", "leaf.value"],
    ["table type", "if (TYPES.indexOf(child.type) === -1)", "if (false)"],
    ["table number range", 'if (child.type === "number" && ', 'if (false && child.type === "number" && '],
    ["table length finite min", 'if (child.min !== undefined && (typeof child.min !== "number" || !isFinite(child.min)))', "if (false)"],
    ["table length max order", 'if (child.min !== undefined && child.max !== undefined && child.min > child.max)', "if (false)"],
    ["length token range", ': leaf.type === "length" ? [\n                leaf.min === undefined ? RANGES.length[0] : leaf.min,\n                leaf.max === undefined ? RANGES.length[1] : leaf.max\n            ] : RANGES[leaf.type];', ': RANGES[leaf.type];'],
    ["table choice options", 'if (child.type === "choice" && ', 'if (false && child.type === "choice" && '],
    ["table name", "if (!NAME_PATTERN.test(keys[i]))", "if (false)"],
    ["table empty group", "if (keys.length === 0)", "if (false)"],
    ["table defect throws", "if (defect !== \"\")\n        throw new Error(\"theme: token table: \"", "if (false)\n        throw new Error(\"theme: token table: \""],
    ["package name", "if (!isPackageName(files.directoryName))", "if (false)"],
    ["package name pattern", "PACKAGE_NAME_PATTERN.test(name)", "true"],
    ["backgrounds object", "if (!isPlainObject(document.backgrounds))", "if (false)"],
    ["background file name", 'if (file === "" || file.indexOf("/") !== -1 || file.charAt(0) === ".")', "if (false)"],
    ["background display name", 'if (typeof name !== "string" || !/^\\S+( \\S+)?$/.test(name))', "if (false)"],
    ["accept states background names", "backgrounds: backgrounds.backgrounds", "backgrounds: {}"],
    ["output name pattern", "OUTPUT_NAME_PATTERN.test(name)", "true"],
    ["set every screen", 'return ["--every-screen"];', 'return ["--screen", screen];'],
    ["set output name", 'return isOutputName(screen) ? ["--screen", screen] : null;', 'return ["--screen", screen];'],
    ["wallpapers options object", "if (!isPlainObject(options))\n        return null;", "if (false)\n        return null;"],
    ["wallpapers options keys", 'if (keys[i] !== "update")', "if (false)"],
    ["wallpapers update boolean", 'if (typeof options.update !== "boolean")', "if (false)"],
    ["wallpapers update flag", 'return options.update ? ["--update"] : [];', "return [];"],
    ["absolute path leading slash", 'text.charAt(0) !== "/" || ', ""],
    ["absolute path NUL", ' || text.indexOf("\\u0000") !== -1', ""],
    ["absolute path segments", 'if (segments[i] === "" || segments[i] === "." || segments[i] === "..")', "if (false)"],
    ["package reserved name", "if (files.directoryName === DEFAULT_NAME && files.shipped !== true)", "if (false)"],
    ["package reserved directory", "if (RESERVED_DIRECTORIES.indexOf(files.directoryName) !== -1)", "if (false)"],
    ["catalog document", "if (!isPlainObject(document))\n        return refusal(\"catalog-document\"", "if (false)\n        return refusal(\"catalog-document\""],
    ["catalog document keys", "if (defect !== \"\")\n        return refusal(\"catalog-document\"", "if (false)\n        return refusal(\"catalog-document\""],
    ["catalog unknown key", "if (keys.indexOf(own[i]) === -1)", "if (false)"],
    ["catalog missing key", "if (!hasOwn(value, keys[i]))", "if (false)"],
    ["catalog schema version", "if (document.schemaVersion !== CATALOG_SCHEMA_VERSION)", "if (false)"],
    ["catalog entries list", "if (!Array.isArray(document.entries))", "if (false)"],
    ["catalog entry object", "if (!isPlainObject(entry))", "if (false)"],
    ["catalog entry keys", "if (defect !== \"\")\n        return refusal(\"catalog-entry\"", "if (false)\n        return refusal(\"catalog-entry\""],
    ["catalog name", "if (!isPackageName(entry.name))", "if (false)"],
    ["catalog reserved vgs", "entry.name === DEFAULT_NAME || ", ""],
    ["catalog reserved directory", " || RESERVED_DIRECTORIES.indexOf(entry.name) !== -1", ""],
    ["catalog duplicate name", "if (hasOwn(seen, judged.entry.name))", "if (false)"],
    ["catalog mode", "if (nodeAt(tokens, SCHEME_MODE).options.indexOf(entry.mode) === -1)", "if (false)"],
    ["catalog palette object", "if (!isPlainObject(entry.palette))", "if (false)"],
    ["catalog palette keys", "if (defect !== \"\")\n        return refusal(\"catalog-palette\"", "if (false)\n        return refusal(\"catalog-palette\""],
    ["catalog palette colour", "if (colour === null)\n            return refusal(\"catalog-palette\"", "if (false)\n            return refusal(\"catalog-palette\""],
    ["catalog palette resolved form", "palette[names[j]] = formatColor(colour);", "palette[names[j]] = entry.palette[names[j]];"],
    ["catalog imagery object", "if (!isPlainObject(imagery))", "if (false)"],
    ["catalog imagery keys", "if (defect !== \"\")\n        return refusal(\"catalog-imagery\"", "if (false)\n        return refusal(\"catalog-imagery\""],
    ["catalog repo type", "if (typeof imagery.repo !== \"string\" || ", "if ("],
    ["catalog repo pattern", "!CATALOG_REPO_PATTERN.test(imagery.repo)", "false"],
    ["catalog release", "if (!isPackageName(imagery.release))", "if (false)"],
    ["catalog archive", "if (!isPackageName(imagery.archive))", "if (false)"],
    ["catalog size integer", "!Number.isSafeInteger(imagery.size) || ", ""],
    ["catalog size positive", " || imagery.size <= 0", ""],
    ["catalog sha256", "if (typeof imagery.sha256 !== \"string\" || !SHA256_PATTERN.test(imagery.sha256))", "if (false)"],
    ["catalog entry files", "if (!isPlainObject(files))\n        return refusal(\"package\", \"\", \"got=\" + JSON.stringify(files));\n    var accepted", "if (false)\n        return refusal(\"package\", \"\", \"got=\" + JSON.stringify(files));\n    var accepted"],
    ["catalog entry installed", "terminalJson: files.terminalJson, shipped: false });", "terminalJson: files.terminalJson, shipped: true });"],
    ["catalog entry package verdict", "if (!accepted.ok)\n        return accepted;", "if (false)\n        return accepted;"],
    ["catalog mode mismatch", "if (accepted.values.scheme.mode !== entry.mode)", "if (false)"],
    ["catalog palette mismatch", "if (accepted.values.palette[names[i]] !== entry.palette[names[i]])", "if (false)"],
    ["package name mismatch", "if (shell.name !== files.directoryName)", "if (false)"],
    ["terminal slot name", "if (!hasOwn(expected, keys[i]))", "if (false)"],
    ["terminal colour syntax", "if (colour === null)\n            return refusal(\"terminal-colour\"", "if (false)\n            return refusal(\"terminal-colour\""],
    ["appearance table", "if (defect !== \"\")\n        return refusal(\"appearance-table\"", "if (false)\n        return refusal(\"appearance-table\""],
    ["appearance palette", 'if (!isLeaf(accent) || accent.type !== "color" || Object.keys(palette).length !== 1)', "if (!isLeaf(accent))"],
    ["appearance light tree", "if (!isPlainObject(light))", "if (false)"],
    ["appearance light judged", "if (!stated.ok)\n        return stated;\n    for", "if (false)\n        return stated;\n    for"],
    ["appearance font type", 'if (family !== undefined && family.type !== "family")', "if (false)"],
    ["appearance interface family input", "var APPEARANCE_INPUTS = [\"palette.accent\", MOTION_SCALE, INTERFACE_FAMILY, RAISED_SURFACE];", "var APPEARANCE_INPUTS = [\"palette.accent\", MOTION_SCALE, RAISED_SURFACE];"],
    ["appearance raised surface input", "MOTION_SCALE, INTERFACE_FAMILY, RAISED_SURFACE];", "MOTION_SCALE, INTERFACE_FAMILY];"],
    ["appearance input", "if (hasOwn(stated.overrides, APPEARANCE_INPUTS[i]))", "if (false)"],
    ["appearance mode", 'var overrides = mode === "light" ? stated.overrides : {};', "var overrides = stated.overrides;"],
    ["appearance theme mode", 'if (typeof mode !== "string")', "if (false)"],
    ["appearance theme input", "if (value === undefined)\n            return refusal(\"appearance-theme\"", "if (false)\n            return refusal(\"appearance-theme\""],
    ["appearance inputs applied", "overrides[APPEARANCE_INPUTS[j]] = value;", ""],
    ["readability contrast ratio", "return (light + 0.05) / (dark + 0.05);", "return 1;"],
    ["readability accent role", "    \"color.accent\",\n", ""],
    ["readability text roles", "    \"color.success\",\n", ""],
    ["readability surfaces", "    \"color.surfaceRaised\",\n", ""],
    ["readability floor", "var READABILITY_FLOOR = 4.5;", "var READABILITY_FLOOR = 1;"],
    ["readability pairs", "    [\"segmented.foreground\", \"segmented.background\"],\n", ""],
    ["readability badge pairs", "    [\"badge.tone.success.foreground\", \"badge.tone.success.background\"],\n", ""],
    ["readability translucent fill over a surface", "if (fill === null || fill.a === 1)", "if (true)"],
    ["readability fill blend", "r: base.r + (fill.r - base.r) * fill.a,", "r: fill.r,"],
    ["readability fill named with its surface", 'pairs[q][1] + " over " + under', "pairs[q][1]"],
    ["readability pair floor", "pairs.push([READABILITY_PAIRS[p][0], READABILITY_PAIRS[p][1], READABILITY_FLOOR]);", "pairs.push([READABILITY_PAIRS[p][0], READABILITY_PAIRS[p][1], BOUNDARY_FLOOR]);"],
    ["readability translucency", "var ratio = text === null || surface === null || text.a < 1 || surface.a < 1\n            ? null\n            : contrastRatio(text, surface);", "var ratio = contrastRatio(text, surface);"],
    ["boundary roles", "    \"checkbox.borderColor\",\n", ""],
    ["boundary pairs", "    [\"toggle.knobOff\", \"toggle.off\"],\n", ""],
    ["boundary floor", "var BOUNDARY_FLOOR = 3;", "var BOUNDARY_FLOOR = 1;"],
    ["modal border on the dimmed page", "        pairs.push([MODAL_BORDER, MODAL_SCRIM, BOUNDARY_FLOOR, READABILITY_SURFACES[s]]);\n", ""],
    ["modal fill on the dimmed page", "        pairs.push([MODAL_FILL, MODAL_SCRIM, BOUNDARY_FLOOR, READABILITY_SURFACES[s], true]);\n", ""],
    ["a modal fill as light as the dimmed page passes", "if (ratio !== null && pairs[q][4] === true && luminance(text) >= luminance(surface))", "if (false)"],
    ["a modal fill darker than the dimmed page is judged", "pairs[q][4] === true && luminance(text) >= luminance(surface)", "pairs[q][4] === true"],
    ["only the modal fill passes by its lightness", "if (ratio !== null && pairs[q][4] === true && luminance(text)", "if (ratio !== null && pairs[q][3] !== undefined && luminance(text)"],
    ["title space below body line", '"body-lines": [1, 4096]', '"body-lines": [0, 4096]'],
    ["appearance flyout ratio", "flyout: 0.75,", "flyout: 1,"],
    ["appearance group tab ratio", "groupTab: 0.5,", "groupTab: 1,"],
    ["appearance control ratio", "control: 1 };", "control: 0.5 };"],
    ["appearance user over theme", "Object.keys(stated).forEach(function (path) { overrides[path] = stated[path]; });", "Object.keys(stated).forEach(function (path) { if (!hasOwn(overrides, path)) overrides[path] = stated[path]; });"],
    ["appearance ratios on a user value alone", "if (member.targets !== undefined && sources[key] === \"user\")\n            member.targets.forEach(function (target) { stated[target[0]] = member.type === \"family\" ? values[key] : values[key] * APPEARANCE_RATIOS[target[1]]; });", "if (member.targets !== undefined)\n            member.targets.forEach(function (target) { stated[target[0]] = member.type === \"family\" ? (sources[key] === \"user\" ? values[key] : shown[key]) : (typeof values[key] === \"number\" ? values[key] : shown[key]) * APPEARANCE_RATIOS[target[1]]; });"],
    ["appearance family sets its targets whole", "stated[target[0]] = member.type === \"family\" ? values[key] : values[key] * APPEARANCE_RATIOS[target[1]];", "if (member.type !== \"family\") stated[target[0]] = values[key] * APPEARANCE_RATIOS[target[1]];"],
    ["appearance interface font reaches the capitals", "targets: [[\"font.family.sans\"], [\"font.family.caps\"]]", "targets: [[\"font.family.sans\"]]"],
    ["appearance terminal font sets no token", "terminalFont: { type: \"family\" }", "terminalFont: { type: \"family\", targets: [[\"font.family.mono\"]] }"],
    ["appearance family is text", "typeof value === \"string\" && value !== \"\" && value.length <= FAMILY_MAX", "value !== \"\" && value.length <= FAMILY_MAX"],
    ["appearance family is not empty", "typeof value === \"string\" && value !== \"\" && value.length <= FAMILY_MAX", "typeof value === \"string\" && value.length <= FAMILY_MAX"],
    ["appearance family length", "value.length <= FAMILY_MAX && ", ""],
    ["appearance family edge spaces", "value.trim() === value && ", ""],
    ["appearance family refused characters", "!FAMILY_REFUSED.test(value))", "true)"],
    ["appearance family control characters", "\\u0000-\\u001f\\u007f-\\u009f", "\\u0000-\\u0009"],
    ["appearance family line separators", "\\u2028\\u2029", ""],
    ["appearance family quote", "\\u2029\"\\\\={}]/", "\\u2029\\\\={}]/"],
    ["appearance family backslash", "\"\\\\={}]/", "\"={}]/"],
    ["appearance family equals sign", "\\\\={}]/", "\\\\{}]/"],
    ["appearance family braces", "={}]/", "=]/"],
    ["appearance hyprland value on a group member", "if (member.hyprland !== undefined && value === \"hyprland\")", "if (value === \"hyprland\")"],
    ["appearance range", "value >= member.min && value <= member.max", "true"],
    ["appearance length is whole", "(member.type !== \"length\" || Number.isInteger(value))", "true"],
    ["appearance number takes a fraction", "(member.type !== \"length\" || Number.isInteger(value))", "Number.isInteger(value)"],
    ["appearance flag only", "member.only !== undefined ? value === member.only : typeof value === \"boolean\"", "typeof value === \"boolean\""],
    ["appearance choice", "if (member.options.indexOf(value) !== -1)\n            return \"\";", "return \"\";"],
    ["appearance unknown member", "if (!hasOwn(APPEARANCE, key))\n        return \"refused: appearance=\" + key + \" unknown\";", "if (!hasOwn(APPEARANCE, key))\n        return \"\";"],
    ["appearance refused member left out", "if (line === \"\")\n            values[key] = given[key];", "if (true)\n            values[key] = given[key];"],
    ["appearance motion off", "if (!moving && hasOwn(values, \"motion\"))\n        stated[MOTION_SCALE] = 0;", "if (!moving && hasOwn(values, \"motion\"))\n        stated[MOTION_SCALE] = 1;"],
    ["appearance speed", "stated[MOTION_SCALE] = 1 / values.motionSpeed;", "stated[MOTION_SCALE] = values.motionSpeed;"],
    ["appearance on over a still theme", "else if (moving && themeScale === 0)\n        stated[MOTION_SCALE] = 1;", ""],
    ["appearance speed needs motion", "else if (moving && hasOwn(values, \"motionSpeed\"))", "else if (hasOwn(values, \"motionSpeed\"))"],
    ["appearance style easings", "stated[\"motion.easing.emphasized\"] = MOTION_STYLES[values.motionStyle].emphasized;", ""],
    ["appearance style preset", "stated[\"hyprland.motion.preset\"] = values.motionStyle;", ""],
    ["appearance hyprland source", "member.hyprland !== undefined && values[key] === \"hyprland\" ? \"hyprland\" : \"user\";", "\"user\";"],
    ["appearance hyprland source on a group member alone", "member.hyprland !== undefined && values[key] === \"hyprland\" ? \"hyprland\" : \"user\";", "values[key] === \"hyprland\" ? \"hyprland\" : \"user\";"],
    ["appearance unset source", "(member.unset || \"theme\")", "\"theme\""],
    ["glass off overrides a surface's choice", "(values.glass !== \"off\" && optIn === true)", "(optIn === true)"],
    ["glass on overrides a surface's choice", "return values.glass === \"on\" || (", "return ("],
    ["the shell's surfaces take the blur only while every surface draws glass", "hyprland.surfaceBlur = glassOn(values, false);", "hyprland.surfaceBlur = hyprland.glass;"],
    ["glass takes a surface's choice only when true", "values.glass !== \"off\" && optIn === true", "values.glass !== \"off\" && !!optIn"],
    ["glass rounds a square corner", "if (glassOn(values, false))\n        GLASS_CORNERS.forEach", "if (false)\n        GLASS_CORNERS.forEach"],
    ["glass rounds only while the user's glass is on", "if (glassOn(values, false))\n        GLASS_CORNERS.forEach", "if (glassOn(values, values.windowGlass === true))\n        GLASS_CORNERS.forEach"],
    ["glass keeps a corner above 0", "if ((hasOwn(stated, path) ? stated[path] : valueAt(theme.values, path)) === 0)", "if (true)"],
    ["glass reads the user's corner before the theme's", "if ((hasOwn(stated, path) ? stated[path] : valueAt(theme.values, path)) === 0)", "if (valueAt(theme.values, path) === 0)"],
    ["glass reads the theme's corner where the user sets none", "if ((hasOwn(stated, path) ? stated[path] : valueAt(theme.values, path)) === 0)", "if (hasOwn(stated, path) && stated[path] === 0)"],
    ["glass rounds to the theme's glass corner", "stated[path] = valueAt(theme.values, GLASS_RADIUS);", "stated[path] = 16;"],
    ["glass rounds an OSD", "\"popover.radius\", \"osd.radius\"];", "\"popover.radius\"];"],
    ["glass leaves a panel square", "var GLASS_CORNERS = [\"menu.radius\",", "var GLASS_CORNERS = [\"surface.radius\", \"menu.radius\","],
    ["glass leaves a tooltip's corner", "var GLASS_CORNERS = [\"menu.radius\",", "var GLASS_CORNERS = [\"tooltip.radius\", \"menu.radius\","],
    ["a solid fill is opaque", "b: channel(color.b), a: 1 };", "b: channel(color.b), a: color.a };"],
    ["a solid fill is lifted toward white", "return value + (1 - value) * lift;", "return value;"],
    ["window glass follows glassOn", "hyprland.glass = glassOn(values, values.windowGlass === true);", ""],
    ["window glow follows window glass", "hyprland.glow = hyprland.glass && values.windowGlow === true;", "hyprland.glow = values.windowGlow === true;"],
    ["glow needs windowGlow", "hyprland.glow = hyprland.glass && values.windowGlow === true;", "hyprland.glow = hyprland.glass && true;"],
    ["glass members unset to the surface", "glass: { type: \"choice\", options: [\"on\", \"off\"], unset: \"surface\" }", "glass: { type: \"choice\", options: [\"on\", \"off\"] }"],
    ["appearance layer groups", "hyprland[member.hyprland] = sources[key] !== \"hyprland\";", "hyprland[member.hyprland] = true;"],
    ["appearance theme speed", "motionSpeed: themeScale > 0 ? 1 / themeScale : 1", "motionSpeed: 1"],
    ["appearance published fallback", "result = withAppearance(tokens, accepted, {});\n    }", "}"],
    ["accept states its overrides", "values: result.values, overrides: stated.overrides, backgrounds: backgrounds.backgrounds };", "values: result.values, overrides: {}, backgrounds: backgrounds.backgrounds };"]
];

const source = fs.readFileSync(judgeFile, "utf8");
const temp = fs.mkdtempSync(path.join(os.tmpdir(), "theme-logic-control-"));
try {
    for (const [label, needle, replacement, selectedVerify = verify] of CONTROLS) {
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        const mutant = path.join(temp, "ThemeLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, () => replacement));
        let failed = false;
        try {
            selectedVerify(load(mutant));
        } catch (e) {
            failed = true;
        }
        assert.ok(failed, `control "${label}": the suite passed on a judge without that rule`);
    }
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}
// The 4 px grid (docs/architecture/design-system.md § Tokens): every
// length token of the shipped table resolves to a multiple of 4 or to
// radius.full, except the classes the rule names, one pattern each. The
// control moves row.height off the grid in a theme document, and the
// check must name it.
const GRID_EXCEPTIONS = [
    [/^(font\.size|text\.[^.]+\.size|bar\.stacked\.size)$/, "type sizes"],
    [/(^border\.|\.border$|[bB]orderWidth$|^divider\.thickness$|^focusRing\.width$|^titleButton\.underline$|^rowAction\.underline$|^tabs\.(indicator|hoverIndicator)$|^segmented\.indicator$|^avatarGroup\.ringWidth$|^hyprland\.border\.size$)/, "strokes"],
    [/^(icon\.size\.|button\.size\.[^.]+\.icon$|rowAction\.icon$|bar\.stacked\.icon$|menu\.item\.icon$|slider\.handle$|radio\.dot$)/, "indicator and icon drawing sizes"],
    [/^(space\.xxs|segmented\.padding|segmented\.gap|toggle\.inset|focusRing\.offset|scrollArea\.barInset|titleButton\.underlineGap|rowAction\.underlineGap|carousel\.sliceName\.shadowOffset)$/, "2 px steps inside one component"],
    [/^textField\.paddingX$/, "optical insets inside one component"],
    [/^(space\.sm|badge\.size\.sm\.paddingX|kbd\.paddingX|tooltip\.paddingY)$/, "6 px padding inside a chip, a key cap or a tooltip"],
    [/^carousel\.namePadding$/, "the owner's 5 px wallpaper name padding"],
    [/^bar\.spacer\.(gap|inset)$/, "the owner's bar gap and separator room"],
    [/^motion\./, "motion distances"],
    [/\.blur$/, "blur radii"]
];
function gridShortfalls(values) {
    const out = [];
    (function walk(node, prefix) {
        for (const [key, leaf] of Object.entries(node)) {
            const name = prefix ? prefix + "." + key : key;
            if (leaf !== null && typeof leaf === "object" && "type" in leaf && "value" in leaf) {
                if (leaf.type !== "length") continue;
                const value = at(values, name);
                if (value % 4 === 0 || value >= 4096) continue;
                if (GRID_EXCEPTIONS.some(([pattern]) => pattern.test(name))) continue;
                out.push(`${name}=${value}`);
            } else if (leaf !== null && typeof leaf === "object") walk(leaf, name);
        }
    })(TOKENS, "");
    return out;
}
{
    const judge = load(judgeFile);
    assert.deepEqual(gridShortfalls(judge.defaults(TOKENS).values), [], "every shipped length is on the 4 px grid or in a named exception");
    const moved = judge.accept(TOKENS, document({ row: { height: 30 } }));
    assert.equal(moved.ok, true, "the grid control document is accepted");
    assert.deepEqual(gridShortfalls(moved.values), ["row.height=30", "listItem.height=30", "menu.maxHeight=270", "menu.item.height=30"], "control: a row height off the grid is named with the list and menu rows that read it");
    // The theme browser's reference geometry is walked like every other
    // group: a card height and an overlap off the grid are named.
    const offGrid = judge.accept(TOKENS, document({ carousel: { expandedHeight: 475, overlap: 30 } }));
    assert.equal(offGrid.ok, true, "the browser grid control document is accepted");
    assert.deepEqual(gridShortfalls(offGrid.values), ["carousel.expandedHeight=475", "carousel.overlap=30"], "control: the carousel's off-grid card height and overlap are named");
}
console.log(`test-theme-logic: ok documents=${ACCEPTED.length + REFUSED.length} controls=${CONTROLS.length + TOKEN_CONTROLS.length + GLASS_CONTROLS.length}`);
