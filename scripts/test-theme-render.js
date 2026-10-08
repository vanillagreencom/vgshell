#!/usr/bin/env node
// The target renderer, bin/lib/theme-render.js, with the shell's theme
// judge and token table. Every expected text below was written by hand from
// the colour it names, never read from the renderer.
//
// The controls at the end edit a copy of the renderer, one rule at a time,
// and require this suite to fail on each copy.
// Inputs also include themes/vgs/* and themes/catalog/*: KDE selection
// foregrounds are rendered from every shipped and catalog package below.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { load } = require("../bin/lib/qml-library.js");

const repo = path.join(__dirname, "..");
const rendererFile = path.join(repo, "bin", "lib", "theme-render.js");
const logic = load(path.join(repo, "shell", "Commons", "ThemeLogic.js"));
const TOKENS = load(path.join(repo, "shell", "Commons", "Tokens.js")).TOKENS;

// The probe package overrides palette.accent to #123456 and has no
// terminal.json; the defaults' slot N is #0000NN in hex.
const slotsJson = colour => JSON.stringify({ schemaVersion: 1, slots: Object.fromEntries(Array.from({ length: 16 }, (_, i) => [`color${i}`, colour(i)])) });
const probe = logic.acceptPackage(TOKENS, {
    directoryName: "probe",
    themeJson: JSON.stringify({ schemaVersion: 1, name: "probe", tokens: { palette: { accent: "#123456" } } }),
    terminalJson: undefined,
    shipped: false
});
const defaults = logic.acceptPackage(TOKENS, {
    directoryName: "vgs",
    themeJson: JSON.stringify({ schemaVersion: 1, name: "vgs", tokens: {} }),
    terminalJson: slotsJson(i => "#0000" + i.toString(16).padStart(2, "0")),
    shipped: true
});
const own = logic.acceptPackage(TOKENS, {
    directoryName: "own",
    themeJson: JSON.stringify({ schemaVersion: 1, name: "own", tokens: {} }),
    terminalJson: slotsJson(() => "#abcdef"),
    shipped: false
});
// A package that states it is light; every other package here is dark.
const lit = logic.acceptPackage(TOKENS, {
    directoryName: "lit",
    themeJson: JSON.stringify({ schemaVersion: 1, name: "lit", tokens: { scheme: { mode: "light" } } }),
    terminalJson: undefined,
    shipped: false
});
for (const pkg of [probe, defaults, own, lit]) assert.equal(pkg.ok, true, pkg.ok ? "" : logic.refusalLine(pkg));

const wiring = { file: "probe/probe.conf", line: "include=@{state}/probe.conf", create: true };
// An entry wiring: links or copies in the application's own directory,
// never a file edit. Two files so an entry can name either.
const entry = { base: "config", dir: "probe/themes", owned: false, links: { "vgs.conf": "probe.conf" } };
const copyEntry = { base: "config", dir: "probe/themes", owned: false, copies: { "vgs.conf": "probe.conf" } };
const accountEntry = { base: "account", dir: "themes", owned: false, links: { "vgs.conf": "probe.conf" } };
const accountCopyEntry = { base: "account", dir: "themes", owned: false, copies: { "vgs.conf": "probe.conf" } };
const accountSelect = { base: "account", file: "settings.json", format: "json", key: ["theme"], value: "custom:vgs" };
const twoFiles = [{ template: "a.conf", destination: "probe.conf" }, { template: "b.json", destination: "probe.pkg.json" }];
const entryText = (fields = {}) => targetText({ files: twoFiles, wiring: Object.assign({}, entry, fields) });
const copyEntryText = (fields = {}) => targetText({ files: twoFiles, wiring: Object.assign({}, copyEntry, fields) });
const targetText = (fields = {}) => JSON.stringify(Object.assign({
    app: "Probe",
    runsCode: false,
    encoder: "hex6",
    files: [{ template: "probe.conf", destination: "probe.conf" }],
    detect: ["probe"],
    wiring,
    reload: { command: ["probe", "--reload"], timeoutMs: 2000 }
}, fields));

// Accepted targets: the name, the document text.
const ACCEPTED_TARGETS = [
    ["probe", targetText()],
    ["probe", targetText({ reload: null, detect: [], wiring: Object.assign({}, wiring, { create: false }) })],
    ["probe", targetText({ detect: [["probe", "probe-bin"]] })],
    ["probe", targetText({ detect: ["probe", ["probe-a", "probe-b"]] })],
    ["probe-2", targetText({ files: [{ template: "a.conf", destination: "probe-2.conf" }, { template: "a.conf", destination: "probe-2.extra.ini" }] })],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { section: "general" }) })],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { section: "Main_2-b" }) })],
    ["probe", targetText({ files: [{ template: "probe.conf", destination: "probe.conf", curatedKeys: ["colors", "tokenColors"] }] })],
    ["probe", entryText()],
    ["probe", entryText({ base: "home", dir: ".probe/extensions/vgs-theme", owned: true, links: { "package.json": "probe.pkg.json", "vgs-color-theme.json": "probe.conf" } })],
    ["probe", copyEntryText()],
    ["probe", targetText({ wiring: accountEntry, select: accountSelect, accounts: "claude" })],
    ["probe", targetText({ wiring: accountCopyEntry, select: accountSelect, accounts: "codex" })],
    ["probe", targetText({ wiring: null })],
    ["probe", targetText({ reload: { command: ["probe", "--file=@{state}/probe.conf", "@@{x}"], timeoutMs: 2000, always: true } })],
    ["probe", targetText({ reload: { command: ["probe"], timeoutMs: 2000, always: false } })],
    ["probe", targetText({ wiring: null, reload: { command: ["probe", "@{target}/shipped", "@{state}"], timeoutMs: 2000 } })],
    ["probe", entryText({ base: "cache", dir: "wal" })],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { file: "chrome/userChrome.css", profiles: [".zen/profiles.ini", ".config/zen/profiles.ini"] }) })],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { section: "general", profiles: ["profiles.ini"] }) })],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { fallbacks: [".config/probe/probe.conf", ".probe.conf"] }) })],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { fallbacks: [".probe.conf"] }), reload: { command: ["touch", "-c", "--", "@{wiring}", "@{state}", "@@{x}"], timeoutMs: 2000 } })],
    ["probe", entryText({ dir: ".obsidian/themes/vgs", owned: true, vaults: "obsidian/obsidian.json" })],
    ["probe", entryText({ base: "home", dir: ".probe", vaults: ".probe-vaults.json" })],
    ["probe", targetText({ setup: "probe-setup", wiring: null })],
    ["probe", targetText({ runsCode: true })]
];

// Refused targets: the name, the document text, the reason, the detail.
const REFUSED_TARGETS = [
    ["Probe", targetText(), "target-name", 'got="Probe"'],
    ["pro.be", targetText(), "target-name", 'got="pro.be"'],
    ["probe", "{", "target-json", ""],
    ["probe", "[]", "target-schema", "key=document"],
    ["probe", targetText({ file: "probe.conf" }), "target-schema", "unknown=file"],
    ["probe", JSON.stringify({ app: "Probe", runsCode: false, encoder: "hex6", files: [], detect: [], wiring }), "target-schema", "missing=reload"],
    ["probe", targetText({ app: "" }), "target-schema", "key=app"],
    ["probe", targetText({ app: "Pro\nbe" }), "target-schema", "key=app"],
    ["probe", JSON.stringify(Object.assign(JSON.parse(targetText()), { runsCode: undefined })), "target-schema", "missing=runsCode"],
    ["probe", targetText({ runsCode: "yes" }), "target-schema", "key=runsCode"],
    ["probe", targetText({ runsCode: null }), "target-schema", "key=runsCode"],
    ["probe", targetText({ runsCode: 1 }), "target-schema", "key=runsCode"],
    ["probe", targetText({ encoder: "hex" }), "target-schema", "key=encoder"],
    ["probe", targetText({ files: [] }), "target-schema", "key=files"],
    ["probe", targetText({ files: [{ template: "probe.conf" }] }), "target-schema", "key=files[0]"],
    ["probe", targetText({ files: [{ template: "../probe.conf", destination: "probe.conf" }] }), "target-schema", "key=files[0].template"],
    ["probe", targetText({ files: [{ template: "target.json", destination: "probe.conf" }] }), "target-schema", "key=files[0].template"],
    ["probe", targetText({ files: [{ template: "probe.conf", destination: "other.conf" }] }), "target-schema", "key=files[0].destination"],
    ["probe", targetText({ files: [{ template: "probe.conf", destination: "probe.c/f" }] }), "target-schema", "key=files[0].destination"],
    ["probe", targetText({ files: [{ template: "a", destination: "probe.conf" }, { template: "b", destination: "probe.conf" }] }), "target-schema", "key=files[1].destination"],
    ["probe", targetText({ files: [{ template: "probe.conf", destination: "probe.conf", curated: ["colors"] }] }), "target-schema", "key=files[0]"],
    ["probe", targetText({ files: [{ template: "probe.conf", destination: "probe.conf", curatedKeys: [] }] }), "target-schema", "key=files[0].curatedKeys"],
    ["probe", targetText({ files: [{ template: "probe.conf", destination: "probe.conf", curatedKeys: "colors" }] }), "target-schema", "key=files[0].curatedKeys"],
    ["probe", targetText({ files: [{ template: "probe.conf", destination: "probe.conf", curatedKeys: [""] }] }), "target-schema", "key=files[0].curatedKeys"],
    ["probe", targetText({ detect: ["probe --version"] }), "target-schema", "key=detect"],
    ["probe", targetText({ detect: "probe" }), "target-schema", "key=detect"],
    ["probe", targetText({ detect: [[]] }), "target-schema", "key=detect"],
    ["probe", targetText({ detect: [["probe", "probe --version"]] }), "target-schema", "key=detect"],
    ["probe", targetText({ detect: [["probe", ["probe-bin"]]] }), "target-schema", "key=detect"],
    ["probe", targetText({ detect: [[["probe"]]] }), "target-schema", "key=detect"],
    ["probe", targetText({ wiring: { file: "probe/probe.conf", line: "include=@{state}/probe.conf" } }), "target-schema", "key=wiring"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { file: "../probe.conf" }) }), "target-schema", "key=wiring.file"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { file: "/etc/probe.conf" }) }), "target-schema", "key=wiring.file"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { line: "include=~/.local/state/vgshell/theme/probe.conf" }) }), "target-schema", "key=wiring.line"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { line: "include=@{palette.accent}" }) }), "target-schema", "key=wiring.line"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { line: "include=@{state}/a\ninclude=b" }) }), "target-schema", "key=wiring.line"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { create: "yes" }) }), "target-schema", "key=wiring.create"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { sections: "general" }) }), "target-schema", "key=wiring"],
    ["probe", targetText({ wiring: { file: "probe/probe.conf", line: "include=@{state}/probe.conf", section: "general" } }), "target-schema", "key=wiring"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { section: "" }) }), "target-schema", "key=wiring.section"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { section: "colors.primary" }) }), "target-schema", "key=wiring.section"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { section: "[general]" }) }), "target-schema", "key=wiring.section"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { section: null }) }), "target-schema", "key=wiring.section"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { profile: ".zen/profiles.ini" }) }), "target-schema", "key=wiring"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { profiles: ".zen/profiles.ini" }) }), "target-schema", "key=wiring.profiles"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { profiles: [] }) }), "target-schema", "key=wiring.profiles"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { profiles: [""] }) }), "target-schema", "key=wiring.profiles"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { profiles: ["/home/u/.zen/profiles.ini"] }) }), "target-schema", "key=wiring.profiles"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { profiles: [".zen/profiles.ini", "../.zen/profiles.ini"] }) }), "target-schema", "key=wiring.profiles"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { profiles: [".zen//profiles.ini"] }) }), "target-schema", "key=wiring.profiles"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { profiles: [[".zen/profiles.ini"]] }) }), "target-schema", "key=wiring.profiles"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { fallbacks: ".probe.conf" }) }), "target-schema", "key=wiring.fallbacks"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { fallbacks: [] }) }), "target-schema", "key=wiring.fallbacks"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { fallbacks: [""] }) }), "target-schema", "key=wiring.fallbacks"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { fallbacks: ["/home/u/.probe.conf"] }) }), "target-schema", "key=wiring.fallbacks"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { fallbacks: [".config/probe.conf", "../.probe.conf"] }) }), "target-schema", "key=wiring.fallbacks"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { fallbacks: [".config//probe.conf"] }) }), "target-schema", "key=wiring.fallbacks"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { fallbacks: [[".probe.conf"]] }) }), "target-schema", "key=wiring.fallbacks"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { profiles: ["profiles.ini"], fallbacks: [".probe.conf"] }) }), "target-schema", "key=wiring.fallbacks"],
    ["probe", entryText({ profiles: [".zen/profiles.ini"] }), "target-schema", "key=wiring"],
    ["probe", entryText({ fallbacks: [".probe.conf"] }), "target-schema", "key=wiring"],
    ["probe", entryText({ line: "include=@{state}/probe.conf" }), "target-schema", "key=wiring"],
    ["probe", entryText({ vault: "obsidian/obsidian.json" }), "target-schema", "key=wiring"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { vaults: "obsidian/obsidian.json" }) }), "target-schema", "key=wiring"],
    ["probe", entryText({ vaults: "" }), "target-schema", "key=wiring.vaults"],
    ["probe", entryText({ vaults: "/home/u/.config/obsidian/obsidian.json" }), "target-schema", "key=wiring.vaults"],
    ["probe", entryText({ vaults: "../obsidian.json" }), "target-schema", "key=wiring.vaults"],
    ["probe", entryText({ vaults: "obsidian//obsidian.json" }), "target-schema", "key=wiring.vaults"],
    ["probe", entryText({ vaults: ["obsidian/obsidian.json"] }), "target-schema", "key=wiring.vaults"],
    ["probe", targetText({ files: twoFiles, wiring: { base: "config", dir: "probe", links: { "vgs.conf": "probe.conf" } } }), "target-schema", "key=wiring"],
    ["probe", entryText({ base: "state" }), "target-schema", "key=wiring.base"],
    ["probe", entryText({ dir: "../probe" }), "target-schema", "key=wiring.dir"],
    ["probe", entryText({ dir: "probe/./themes" }), "target-schema", "key=wiring.dir"],
    ["probe", entryText({ dir: "/etc/probe" }), "target-schema", "key=wiring.dir"],
    ["probe", entryText({ dir: 3 }), "target-schema", "key=wiring.dir"],
    ["probe", entryText({ owned: "no" }), "target-schema", "key=wiring.owned"],
    ["probe", entryText({ links: {} }), "target-schema", "key=wiring.links"],
    ["probe", entryText({ links: ["probe.conf"] }), "target-schema", "key=wiring.links"],
    ["probe", entryText({ links: { "../vgs.conf": "probe.conf" } }), "target-schema", "key=wiring.links.../vgs.conf"],
    ["probe", entryText({ links: { "vgs.conf": "other.conf" } }), "target-schema", "key=wiring.links.vgs.conf"],
    ["probe", entryText({ links: { "vgs.conf": "probe.conf" }, copies: { "vgs-copy.conf": "probe.conf" } }), "target-schema", "key=wiring"],
    ["probe", copyEntryText({ copies: {} }), "target-schema", "key=wiring.copies"],
    ["probe", copyEntryText({ copies: { "../vgs.conf": "probe.conf" } }), "target-schema", "key=wiring.copies.../vgs.conf"],
    ["probe", copyEntryText({ copies: { "vgs.conf": "other.conf" } }), "target-schema", "key=wiring.copies.vgs.conf"],
    ["probe", targetText({ wiring: accountEntry, select: accountSelect, accounts: 7 }), "target-schema", "key=accounts"],
    ["probe", targetText({ wiring: accountEntry, accounts: "claude" }), "target-schema", "key=accounts"],
    ["probe", targetText({ wiring: entry, select: accountSelect, accounts: "claude" }), "target-schema", "key=accounts"],
    ["probe", targetText({ wiring: accountEntry, select: Object.assign({}, accountSelect, { base: "home" }), accounts: "claude" }), "target-schema", "key=accounts"],
    ["probe", targetText({ wiring: accountEntry, select: accountSelect }), "target-schema", "key=wiring.base"],
    ["probe", targetText({ select: accountSelect }), "target-schema", "key=select.base"],
    ["probe", targetText({ reload: { command: ["probe"] } }), "target-schema", "key=reload"],
    ["probe", targetText({ reload: { command: [], timeoutMs: 2000 } }), "target-schema", "key=reload.command"],
    ["probe", targetText({ reload: { command: ["probe"], timeoutMs: 0 } }), "target-schema", "key=reload.timeoutMs"],
    ["probe", targetText({ reload: { command: ["probe"], timeoutMs: 1.5 } }), "target-schema", "key=reload.timeoutMs"],
    ["probe", targetText({ reload: { command: ["probe"], always: true } }), "target-schema", "key=reload"],
    ["probe", targetText({ reload: { command: ["probe"], timeoutMs: 2000, often: true } }), "target-schema", "key=reload"],
    ["probe", targetText({ reload: { command: ["probe"], timeoutMs: 2000, always: "yes" } }), "target-schema", "key=reload.always"],
    ["probe", targetText({ reload: { command: ["probe", "@{palette.accent}"], timeoutMs: 2000 } }), "target-schema", "key=reload.command"],
    ["probe", targetText({ reload: { command: ["probe", "@{state"], timeoutMs: 2000 } }), "target-schema", "key=reload.command"],
    ["probe", targetText({ wiring: Object.assign({}, wiring, { profiles: ["profiles.ini"] }), reload: { command: ["probe", "@{wiring}"], timeoutMs: 2000 } }), "target-schema", "key=reload.command"],
    ["probe", targetText({ files: twoFiles, wiring: entry, reload: { command: ["probe", "@{wiring}"], timeoutMs: 2000 } }), "target-schema", "key=reload.command"],
    ["probe", targetText({ wiring: null, reload: { command: ["probe", "@{wiring}"], timeoutMs: 2000 } }), "target-schema", "key=reload.command"],
    ["probe", targetText({ wiring: "none" }), "target-schema", "key=wiring"],
    ["probe", targetText({ setup: "/usr/local/bin/probe" }), "target-schema", "key=setup"],
    ["probe", targetText({ setup: ["probe"] }), "target-schema", "key=setup"],
    ["probe", targetText({ setup: "" }), "target-schema", "key=setup"]
];

// One colour through each encoder: the defaults' color.selection is
// alpha(#ff5a36, 0.35), #ff5a3659, composited over #000000ff. 0x59 = 89 and 89 / 255 = 0.349.
const ENCODED = [
    ["hex6", "591f13"],
    ["hex8", "ff5a3659"],
    ["gnome-accent", "orange"]
];

// The GNOME accent each palette.accent takes, read by hand from its OKLCh
// hue and chroma against libadwaita's nine accents (blue 255.3, teal 213.1,
// green 147.0, yellow 75.6, orange 42.4, red 21.6, pink 352.2, purple
// 316.7; slate under chroma 0.045): the accent, the name.
const GNOME_ACCENTED = [
    ["#3584e4", "blue"],
    ["#2190a4", "teal"],
    ["#3a944a", "green"],
    ["#c88800", "yellow"],
    ["#ed5b00", "orange"],
    ["#e62d42", "red"],
    ["#d56199", "pink"],
    ["#9141ac", "purple"],
    ["#6f8396", "slate"],
    // Grey: no hue, chroma 0.
    ["#808080", "slate"],
    // A blue-grey at chroma 0.033, and a pale blue at 0.049.
    ["#8ba4b0", "slate"],
    ["#94afca", "blue"],
    // Hue 3.2 lies 11.0 from pink across 0 and 18.3 from red.
    ["#e8357a", "pink"]
];
// A package whose selection, its accent at alpha 0.35, lies over a teal
// background: #e62d42 alone is red, and composited it is #666d82, chroma
// 0.034, which takes slate.
const tealed = logic.acceptPackage(TOKENS, {
    directoryName: "tealed",
    themeJson: JSON.stringify({ schemaVersion: 1, name: "tealed", tokens: { palette: { background: "#2190a4", accent: "#e62d42" } } }),
    terminalJson: undefined,
    shipped: false
});
assert.equal(tealed.ok, true, tealed.ok ? "" : logic.refusalLine(tealed));

// Templates under the hex6 encoder against the probe package and the
// defaults' slots: the template, the rendered text.
const RENDERED = [
    ["accent=@{palette.accent}\n", "accent=123456\n"],
    ["@@{palette.accent}", "@{palette.accent}"],
    ["@@@{palette.accent}", "@@{palette.accent}"],
    ["set -g status-left '#{pane_id} ${HOME} {palette.accent} @ @@ #@{palette.accent}'", "set -g status-left '#{pane_id} ${HOME} {palette.accent} @ @@ #123456'"],
    ["gap=@{space.sm}px font=@{font.family.mono}", "gap=6px font=JetBrains Mono"],
    ["regular1=@{terminal.color1} bright15=@{terminal.color15}", "regular1=000001 bright15=00000f"],
    ["", ""]
];

// The mode, bare and through cases, under a dark and a light package: the
// package, the template, the rendered text.
const MODES = [
    [probe, "@{scheme.mode}", "dark"],
    [lit, "@{scheme.mode}", "light"],
    [probe, "@{scheme.mode|dark=vs-dark|light=vs}", "vs-dark"],
    [lit, "@{scheme.mode|dark=vs-dark|light=vs}", "vs"],
    [lit, "@{scheme.mode|light=a=b|dark=c}", "a=b"]
];

// Templates that refuse the target: the template, the detail.
const REFUSED_TEMPLATES = [
    ["@{scheme.mode|dark=vs-dark}", 'template=probe.conf placeholder="scheme.mode|dark=vs-dark"'],
    ["@{scheme.mode|dark=a|dim=c}", 'template=probe.conf placeholder="scheme.mode|dark=a|dim=c"'],
    ["@{scheme.mode|dark=a|light=b|dark=c}", 'template=probe.conf placeholder="scheme.mode|dark=a|light=b|dark=c"'],
    ["@{scheme.mode|dark=|light=b}", 'template=probe.conf placeholder="scheme.mode|dark=|light=b"'],
    ["@{scheme.mode|dark|light=b}", 'template=probe.conf placeholder="scheme.mode|dark|light=b"'],
    ["@{palette.accent|dark=a|light=b}", 'template=probe.conf placeholder="palette.accent|dark=a|light=b"'],
    ["@{terminal.color1|dark=a|light=b}", 'template=probe.conf placeholder="terminal.color1|dark=a|light=b"'],
    ["@{palette.nope}", 'template=probe.conf placeholder="palette.nope"'],
    ["@{palette}", 'template=probe.conf placeholder="palette"'],
    ["@{}", 'template=probe.conf placeholder=""'],
    ["@{terminal.color16}", 'template=probe.conf placeholder="terminal.color16"'],
    ["@{state}", 'template=probe.conf placeholder="state"'],
    ["ok @{palette.accent} then @{palette.accent", "template=probe.conf unterminated=26"]
];

// A configuration file's text before the wiring, and after it, or null when
// the line already stands on a line of its own.
const LINE = "include=/s/foot.ini";
const WIRED = [
    [undefined, "include=/s/foot.ini\n"],
    ["", "include=/s/foot.ini\n"],
    ["[main]\nfont=x\n", "include=/s/foot.ini\n[main]\nfont=x\n"],
    ["font=x", "include=/s/foot.ini\nfont=x"],
    ["font=x\ninclude=/s/foot.ini\n[colors]\n", null],
    ["include=/s/foot.ini", null],
    ["# include=/s/foot.ini\n", "include=/s/foot.ini\n# include=/s/foot.ini\n"],
    ["include=/s/foot.ini.old\n", "include=/s/foot.ini\ninclude=/s/foot.ini.old\n"]
];

// A configuration file's text before the wiring into the `general` section,
// and after it, or null when the line already stands on a line of its own.
const TOML_LINE = 'import = ["/s/alacritty.toml"]';
const WIRED_SECTION = [
    [undefined, '[general]\nimport = ["/s/alacritty.toml"]\n'],
    ["", '[general]\nimport = ["/s/alacritty.toml"]\n'],
    ["[window]\nx = 1\n", '[window]\nx = 1\n[general]\nimport = ["/s/alacritty.toml"]\n'],
    ["[window]\nx = 1", '[window]\nx = 1\n[general]\nimport = ["/s/alacritty.toml"]\n'],
    ["[general]\nlive = true\n[window]\n", '[general]\nimport = ["/s/alacritty.toml"]\nlive = true\n[window]\n'],
    ["[window]\n  [ general ]  # mine\nlive = true", '[window]\n  [ general ]  # mine\nimport = ["/s/alacritty.toml"]\nlive = true'],
    ["[general]\n[general]\n", '[general]\nimport = ["/s/alacritty.toml"]\n[general]\n'],
    ["[general.more]\n[[general]]\n# [general]\n[generalx]\n", '[general.more]\n[[general]]\n# [general]\n[generalx]\n[general]\nimport = ["/s/alacritty.toml"]\n'],
    ["[general]\nlive = true\n[window]\nimport = [\"a\"]\n", '[general]\nimport = ["/s/alacritty.toml"]\nlive = true\n[window]\nimport = ["a"]\n'],
    ["[general]\n[[general.x]]\nimport = [\"a\"]\n", '[general]\nimport = ["/s/alacritty.toml"]\n[[general.x]]\nimport = ["a"]\n'],
    ["[window]\ngeneral.x = 1\n", '[window]\ngeneral.x = 1\n[general]\nimport = ["/s/alacritty.toml"]\n'],
    ['[window]\n[general]\nimport = ["/s/alacritty.toml"]\n', null],
    ['import = ["/s/alacritty.toml"]', null],
    // The section's own one-line import array takes the theme first, so the
    // file's own imports, read after it, override it.
    ['[general]\nimport = ["~/.config/alacritty/theme.toml"]\n', '[general]\nimport = ["/s/alacritty.toml", "~/.config/alacritty/theme.toml"]\n'],
    ['[general]\nimport = ["/old/state/alacritty.toml"]\n', '[general]\nimport = ["/s/alacritty.toml", "/old/state/alacritty.toml"]\n'],
    ['[window]\n[general]\nlive = true\n  import=["a"] # mine\n[window]\n', '[window]\n[general]\nlive = true\n  import=["/s/alacritty.toml", "a"] # mine\n[window]\n'],
    ["[general]\nimport = [ \"a\" , 'b', ]\t# ] mine\n", "[general]\nimport = [ \"/s/alacritty.toml\", \"a\" , 'b', ]\t# ] mine\n"],
    ['[general]\nimport = []\n', '[general]\nimport = ["/s/alacritty.toml"]\n'],
    ['[general]\nimport = [ ]\n', '[general]\nimport = [ "/s/alacritty.toml"]\n'],
    ['[general]\r\nimport = ["a"]\r\n', '[general]\r\nimport = ["/s/alacritty.toml", "a"]\r\n'],
    ['[general]\nimport = ["~/q\\"].toml", "b"]\n', '[general]\nimport = ["/s/alacritty.toml", "~/q\\"].toml", "b"]\n'],
    ["[general]\nimport = ['C:\\', \"b\"]\n", "[general]\nimport = [\"/s/alacritty.toml\", 'C:\\', \"b\"]\n"],
    ['[general]\nimport = ["a", "/s/alacritty.toml"]\n', null]
];

// A configuration file the wiring into `general` would give a key twice:
// its text, the refusal's detail.
const CONFLICTS = [
    ['[general]\nimport = [\n  "~/a.toml",\n]\n', "section=general key=import"],
    ['[general]\nimport = "~/a.toml"\n', "section=general key=import"],
    ["[general]\nimport = '\"a\"] #'\n", "section=general key=import"],
    ['[general]\nimport = [1, 1]\n', "section=general key=import"],
    ['[general]\nimport = ["a" "b"]\n', "section=general key=import"],
    ['[general]\nimport = ["a"] x\n', "section=general key=import"],
    ['[general]\nimport = ["a"]\nimport = ["b"]\n', "section=general key=import"],
    ['[general]\nimport = [\"\"\"a\"\"\"]\n', "section=general key=import"],
    ["general.live = true\n[window]\n", "section=general key=general"],
    ["general = { live = true }\n", "section=general key=general"]
];

// A wiring line that assigns no one-line array of one string, which a file
// whose `general` assigns its key refuses.
const CONFLICT_LINES = ['import = ["/s/x", "/s/y"]', 'import = "/s/x"'];

// A configuration file's text before the line is removed, and after it, or
// null when no line of it is the include line.
const UNWIRED = [
    [undefined, null],
    ["", null],
    ["[main]\nfont=x\n", null],
    ["# include=/s/foot.ini\ninclude=/s/foot.ini.old\n", null],
    ["include=/s/foot.ini\n[main]\nfont=x\n", "[main]\nfont=x\n"],
    ["include=/s/foot.ini\nfont=x", "font=x"],
    ["include=/s/foot.ini\n", ""],
    ["font=x\ninclude=/s/foot.ini\n[colors]\ninclude=/s/foot.ini\n", "font=x\n[colors]\n"],
    ["[window]\n[general]\ninclude=/s/foot.ini\n", "[window]\n[general]\n"]
];

// A configuration file's text before the wiring into `general` is removed,
// and after it, or null when neither the line nor its string stands there.
const UNWIRED_SECTION = [
    [undefined, null],
    ['[general]\nimport = ["/s/alacritty.toml"]\nlive = true\n', '[general]\nlive = true\n'],
    ['[general]\nimport = ["/s/alacritty.toml", "~/a.toml"]\n', '[general]\nimport = ["~/a.toml"]\n'],
    ['[general]\nimport = ["a", "/s/alacritty.toml"]\n', '[general]\nimport = ["a"]\n'],
    ['[general]\nimport = [ "/s/alacritty.toml"]\n', '[general]\nimport = [ ]\n'],
    ['[general]\nimport = ["/s/alacritty.toml",]\n', '[general]\nimport = []\n'],
    ['[general]\nimport = ["/s/alacritty.toml", "a", "/s/alacritty.toml"] # mine\n', '[general]\nimport = ["a"] # mine\n'],
    ['[general]\nx = 1\n[window]\nimport = ["/s/alacritty.toml", "a"]\n', null],
    ['[general]\nx = 1\n[general]\nimport = ["/s/alacritty.toml", "a"]\n', null],
    ['[general]\nother = ["/s/alacritty.toml", "a"]\n', null],
    ['[general]\nimport = ["/s/alacritty.toml.old", "a"]\n', null],
    ['[general]\nimport = [\n  "/s/alacritty.toml",\n]\n', null],
    ['import = ["/s/alacritty.toml", "a"]\n', null]
];

// A Mozilla profiles.ini's text, and the profile directories it lists.
const REL = path => ({ path, relative: true });
const ABS = path => ({ path, relative: false });
const PROFILES = [
    ["", []],
    ["[General]\nStartWithLastProfile=1\nVersion=2\n\n[Profile0]\nName=default\nIsRelative=1\nPath=a1b2.Default (release)\nDefault=1\n", [REL("a1b2.Default (release)")]],
    ["[Profile1]\nIsRelative=0\nPath=/srv/zen/p1\n[Profile0]\nIsRelative=1\nPath=Profiles/p0\n", [ABS("/srv/zen/p1"), REL("Profiles/p0")]],
    ["[Profile0]\r\nIsRelative=1\r\nPath=p0\r\n", [REL("p0")]],
    [" [ Profile0 ] \n IsRelative = 1 \n Path = p0 \n", [REL("p0")]],
    ["[Profile0]\nIsRelative=1\nPath=a=b\n", [REL("a=b")]],
    ["[Profile0]\nPath=/srv/p0\n", [ABS("/srv/p0")]],
    ["Path=/outside\n[Install4F96D1932A9F858E]\nDefault=p0\nPath=/install\n[General]\nPath=/general\n[ProfileX]\nPath=/x\n", []],
    ["[Profile0]\nName=no-path\nIsRelative=1\n", []],
    ["[Profile0]\nIsRelative=1\nPath=\n", []],
    ["[Profile0]\nIsRelative=0\nPath=relative/p0\n", []],
    ["[Profile0]\nIsRelative=true\nPath=relative/p0\n", []]
];

// An Obsidian vault registry's text, and the vault directories it lists;
// null for a registry no vault list can be read from.
const VAULTS = [
    ["{}", []],
    ['{"vaults":{}}', []],
    ['{"vaults":{"a1b2":{"path":"/home/u/Notes","ts":1,"open":true},"c3d4":{"path":"/srv/Work Vault"}},"updateDisabled":true}', ["/home/u/Notes", "/srv/Work Vault"]],
    ['{"vaults":{"a":{"path":"/n"},"b":{"path":"/n"},"c":{"path":"/m"}}}', ["/n", "/m"]],
    ['{"vaults":{"a":{"path":"Notes"},"b":{"path":""},"c":{"path":3},"d":"/x","e":null,"f":{"ts":1},"g":{"path":"/ok"}}}', ["/ok"]],
    ["", null],
    ["{", null],
    ["[]", null],
    ['"/n"', null],
    ["null", null],
    ['{"vaults":[{"path":"/n"}]}', null],
    ['{"vaults":"/n"}', null]
];

// Detection: an accepted detect list, the commands on PATH, whether it is met.
// A command entry is required; a list entry is met by any one of its names.
const DETECTED = [
    [[], [], true],
    [["a"], ["a"], true],
    [["a"], [], false],
    [["a", "b"], ["a"], false],
    [["a", "b"], ["a", "b"], true],
    [[["a", "b"]], ["a"], true],
    [[["a", "b"]], ["b"], true],
    [[["a", "b"]], ["a", "b"], true],
    [[["a", "b"]], [], false],
    [[["a", "b"]], ["c"], false],
    [["c", ["a", "b"]], ["b"], false],
    [["c", ["a", "b"]], ["b", "c"], true]
];

function verify(render) {
    const accepted = (name, text) => {
        const result = render.acceptTarget(logic, name, text);
        assert.equal(result.ok, true, `${name} ${text}: ${result.ok ? "" : render.refusalLine(name, result)}`);
        return result.target;
    };
    for (const [name, text] of ACCEPTED_TARGETS) {
        const target = accepted(name, text);
        assert.equal(target.name, name);
        assert.deepEqual(Object.assign({ name }, JSON.parse(text)), target);
    }
    for (const [name, text, reason, detail] of REFUSED_TARGETS) {
        const result = render.acceptTarget(logic, name, text);
        assert.deepEqual(result, { ok: false, reason, detail }, `${name} ${text}`);
    }
    for (const [detect, found, want] of DETECTED)
        assert.equal(render.detected(detect, command => found.includes(command)), want, `${JSON.stringify(detect)} with ${JSON.stringify(found)}`);
    assert.equal(render.refusalLine("probe", { ok: false, reason: "target-schema", detail: "key=app" }), "target=probe reason=target-schema key=app");
    assert.equal(render.refusalLine("probe", { ok: false, reason: "target-json", detail: "" }), "target=probe reason=target-json");

    // The terminal fallback: a package's own slots, else the defaults'.
    assert.equal(render.terminalSource(own, defaults), own);
    assert.equal(render.terminalSource(probe, defaults), defaults);
    assert.equal(render.terminalSource(probe, null), null);
    assert.equal(render.terminalSource(probe, probe), null);
    assert.throws(() => render.terminalSource({ values: {} }, defaults), /without its terminal verdict/);

    const target = (encoder, files) => accepted("probe", targetText(Object.assign({ encoder }, files === undefined ? {} : { files })));
    const one = (encoder, text, pkg = probe, curated = new Map()) => {
        const source = render.terminalSource(pkg, defaults);
        return render.renderTarget(logic, TOKENS, target(encoder), new Map([["probe.conf", text]]), { values: pkg.values, slots: source.terminal, curated, installed: false });
    };
    const rendered = (encoder, text, pkg, curated) => {
        const result = one(encoder, text, pkg, curated);
        assert.equal(result.ok, true, `${encoder} ${text}: ${result.ok ? "" : render.refusalLine("probe", result)}`);
        assert.equal(result.files.length, 1);
        return result.files[0];
    };

    for (const [encoder, want] of ENCODED) {
        const file = rendered(encoder, "c=@{color.selection}", defaults);
        assert.equal(file.bytes.toString("utf8"), "c=" + want, encoder);
        assert.equal(file.destination, "probe.conf");
        assert.equal(file.curated, false);
    }
    for (const [accent, want] of GNOME_ACCENTED) {
        const pkg = logic.acceptPackage(TOKENS, {
            directoryName: "accent",
            themeJson: JSON.stringify({ schemaVersion: 1, name: "accent", tokens: { palette: { accent } } }),
            terminalJson: undefined,
            shipped: false
        });
        assert.equal(rendered("gnome-accent", "@{palette.accent}", pkg).bytes.toString("utf8"), want, accent);
    }
    assert.equal(rendered("gnome-accent", "@{palette.accent} @{color.selection}", tealed).bytes.toString("utf8"), "red slate");
    for (const [text, want] of RENDERED)
        assert.equal(rendered("hex6", text).bytes.toString("utf8"), want, text);
    for (const [pkg, text, want] of MODES)
        assert.equal(rendered("hex6", text, pkg).bytes.toString("utf8"), want, `${pkg.values.scheme.mode} ${text}`);
    for (const [text, detail] of REFUSED_TEMPLATES)
        assert.deepEqual(one("hex6", text), { ok: false, reason: "placeholder", detail }, text);

    // A package's own terminal.json wins over the defaults'.
    assert.equal(rendered("hex6", "@{terminal.color1}", own).bytes.toString("utf8"), "abcdef");

    // A curated file is taken byte for byte in place of the rendered one;
    // its template is rendered all the same, so a bad placeholder refuses.
    const curatedBytes = Buffer.from([0x40, 0x7b, 0x6e, 0x6f, 0x7d, 0xff, 0x0a]);
    const curated = rendered("hex6", "accent=@{palette.accent}", probe, new Map([["probe.conf", curatedBytes]]));
    assert.equal(curated.curated, true);
    assert.ok(curated.bytes.equals(curatedBytes));
    assert.deepEqual(one("hex6", "@{palette.nope}", probe, new Map([["probe.conf", curatedBytes]])).reason, "placeholder");

    // With curatedKeys, a curated file is taken only as a JSON object holding
    // one of them; any other file at that name, a vscode.json naming an
    // extension included, leaves the render in place.
    const keyed = accepted("probe", targetText({ files: [{ template: "probe.conf", destination: "probe.conf", curatedKeys: ["colors", "tokenColors"] }] }));
    const keyedFile = bytes => {
        const result = render.renderTarget(logic, TOKENS, keyed, new Map([["probe.conf", "a=@{palette.accent}"]]), { values: probe.values, slots: defaults.terminal, curated: new Map([["probe.conf", Buffer.from(bytes)]]), installed: false });
        assert.equal(result.ok, true);
        return [result.files[0].bytes.toString("utf8"), result.files[0].curated];
    };
    for (const bytes of ['{ "tokenColors": [] }', '{ "colors": {}, "name": "x" }'])
        assert.deepEqual(keyedFile(bytes), [bytes, true], bytes);
    for (const bytes of ['{ "name": "Tokyo Night", "extension": "enkia.tokyo-night" }', '[{ "colors": {} }]', '{ "colors": {} ', "null", ""])
        assert.deepEqual(keyedFile(bytes), ["a=123456", false], bytes);

    // Several files render in the target's order; a curated file stands in
    // for its own destination only.
    const two = accepted("probe", targetText({ files: [{ template: "a.conf", destination: "probe.conf" }, { template: "b.ini", destination: "probe.extra.ini" }] }));
    const both = render.renderTarget(logic, TOKENS, two, new Map([["a.conf", "a=@{palette.accent}"], ["b.ini", "b=@{palette.accent}"]]),
        { values: probe.values, slots: defaults.terminal, curated: new Map([["probe.extra.ini", Buffer.from("mine")]]), installed: false });
    assert.equal(both.ok, true);
    assert.deepEqual(both.files.map(f => [f.destination, f.bytes.toString("utf8"), f.curated]), [["probe.conf", "a=123456", false], ["probe.extra.ini", "mine", true]]);
    assert.deepEqual(both.dropped, []);

    // On a runsCode target an installed package's curated file is dropped
    // and named, the template rendered in its place, and never judged, so a
    // file curatedKeys would refuse is named too; a shipped package's is
    // taken, and so is an installed package's on any other target. ROW:
    // runsCode, installed, curatedKeys, the curated files, then the bytes
    // and curated flag of each file in order and the dropped destinations.
    const DROPS = [
        [true, true, undefined, [["probe.conf", "mine"]], [["a=123456", false], ["b=123456", false]], ["probe.conf"]],
        [true, true, undefined, [["probe.conf", "mine"], ["probe.extra.ini", "also"]], [["a=123456", false], ["b=123456", false]], ["probe.conf", "probe.extra.ini"]],
        [true, true, ["colors"], [["probe.conf", '{ "name": "x" }']], [["a=123456", false], ["b=123456", false]], ["probe.conf"]],
        [true, true, undefined, [], [["a=123456", false], ["b=123456", false]], []],
        [true, false, undefined, [["probe.conf", "mine"]], [["mine", true], ["b=123456", false]], []],
        [false, true, undefined, [["probe.conf", "mine"]], [["mine", true], ["b=123456", false]], []],
        [false, false, undefined, [["probe.extra.ini", "also"]], [["a=123456", false], ["also", true]], []]
    ];
    for (const [runsCode, installed, curatedKeys, curatedFiles, want, dropped] of DROPS) {
        const first = Object.assign({ template: "a.conf", destination: "probe.conf" }, curatedKeys === undefined ? {} : { curatedKeys });
        const flagged = accepted("probe", targetText({ runsCode, files: [first, { template: "b.ini", destination: "probe.extra.ini" }] }));
        const result = render.renderTarget(logic, TOKENS, flagged, new Map([["a.conf", "a=@{palette.accent}"], ["b.ini", "b=@{palette.accent}"]]),
            { values: probe.values, slots: defaults.terminal, curated: new Map(curatedFiles.map(([name, text]) => [name, Buffer.from(text)])), installed });
        const row = JSON.stringify([runsCode, installed, curatedKeys, curatedFiles]);
        assert.equal(result.ok, true, row);
        assert.deepEqual(result.files.map(f => [f.bytes.toString("utf8"), f.curated]), want, row);
        assert.deepEqual(result.dropped, dropped, row);
    }
    // A dropped file's template is judged all the same.
    const flaggedBad = accepted("probe", targetText({ runsCode: true }));
    assert.equal(render.renderTarget(logic, TOKENS, flaggedBad, new Map([["probe.conf", "@{palette.nope}"]]),
        { values: probe.values, slots: defaults.terminal, curated: new Map([["probe.conf", Buffer.from("mine")]]), installed: true }).reason, "placeholder");

    assert.throws(() => render.renderTarget(logic, TOKENS, target("hex6"), new Map(), { values: probe.values, slots: defaults.terminal, curated: new Map(), installed: false }), /was not read/);
    assert.throws(() => render.renderTarget(logic, TOKENS, target("hex6"), new Map([["probe.conf", ""]]), { values: probe.values, slots: null, curated: new Map(), installed: false }), /without terminal slots/);
    assert.throws(() => render.renderTarget(logic, TOKENS, target("hex6"), new Map([["probe.conf", ""]]), { values: probe.values, slots: defaults.terminal, curated: new Map() }), /without the package's source/);

    // The wiring line names the state directory; `@@{` stays a literal.
    assert.equal(render.wiringLine(target("hex6"), "/s/vgshell/theme"), "include=/s/vgshell/theme/probe.conf");
    const escaped = accepted("probe", targetText({ wiring: Object.assign({}, wiring, { line: "a=@@{x} source @{state}/b @{state}/c" }) }));
    assert.equal(render.wiringLine(escaped, "/s"), "a=@{x} source /s/b /s/c");
    for (const [text, want] of WIRED)
        assert.equal(render.wiredText(text, LINE), want, JSON.stringify(text));
    for (const [text, want] of WIRED_SECTION)
        assert.equal(render.wiredText(text, TOML_LINE, "general"), want, JSON.stringify(text));
    for (const [text, detail] of CONFLICTS)
        assert.deepEqual(render.wiredText(text, TOML_LINE, "general"), { ok: false, reason: "wiring-conflict", detail }, JSON.stringify(text));
    for (const line of CONFLICT_LINES)
        assert.deepEqual(render.wiredText('[general]\nimport = ["a"]\n', line, "general"), { ok: false, reason: "wiring-conflict", detail: "section=general key=import" }, line);
    for (const [text, want] of UNWIRED)
        assert.equal(render.unwiredText(text, LINE), want, JSON.stringify(text));
    for (const [text, want] of UNWIRED_SECTION)
        assert.equal(render.unwiredText(text, TOML_LINE, "general"), want, JSON.stringify(text));
    for (const [text, want] of PROFILES)
        assert.deepEqual(render.profileDirs(text), want, JSON.stringify(text));
    for (const [text, want] of VAULTS)
        assert.deepEqual(render.vaultDirs(logic, text), want, JSON.stringify(text));

    // An entry target's entries name its files in the state directory's
    // theme/, in target.json's order, with their kind; each form refuses
    // the other's helper.
    const linked = accepted("probe", entryText({ links: { "vgs.conf": "probe.conf", "package.json": "probe.pkg.json" } }));
    const copied = accepted("probe", copyEntryText());
    assert.equal(render.wiringForm(linked.wiring), "entry");
    assert.equal(render.wiringForm(target("hex6").wiring), "include");
    assert.deepEqual(render.entryItems(linked, "/s/vgshell/theme"), [{ kind: "link", name: "vgs.conf", destination: "probe.conf", to: "/s/vgshell/theme/probe.conf" }, { kind: "link", name: "package.json", destination: "probe.pkg.json", to: "/s/vgshell/theme/probe.pkg.json" }]);
    assert.deepEqual(render.entryItems(copied, "/s/vgshell/theme"), [{ kind: "copy", name: "vgs.conf", destination: "probe.conf", to: "/s/vgshell/theme/probe.conf" }]);
    assert.throws(() => render.wiringLine(linked, "/s"), /has wiring form entry/);
    assert.throws(() => render.entryItems(target("hex6"), "/s"), /has wiring form include/);

    // A null wiring is its own form, and neither form's helper takes it.
    const unwired = accepted("probe", targetText({ wiring: null }));
    assert.equal(render.wiringForm(unwired.wiring), "none");
    assert.throws(() => render.wiringLine(unwired, "/s"), /has wiring form none/);
    assert.throws(() => render.entryItems(unwired, "/s"), /has wiring form none/);

    // A reload argument names the state directory, the target's own
    // directory and, for include targets without profiles, the wiring file;
    // `@@{` stays a literal. `always` alone makes a hook due on every apply.
    const hooked = accepted("probe", targetText({ reload: { command: ["probe", "--file=@{state}/probe.conf", "@@{x}"], timeoutMs: 2000, always: true } }));
    assert.deepEqual(render.reloadCommand(hooked, "/s/vgshell/theme", "/t/probe"), ["probe", "--file=/s/vgshell/theme/probe.conf", "@{x}"]);
    const shipping = accepted("probe", targetText({ wiring: null, reload: { command: ["probe", "@{target}/shipped", "@{state}"], timeoutMs: 2000 } }));
    assert.deepEqual(render.reloadCommand(shipping, "/s/vgshell/theme", "/t/probe"), ["probe", "/t/probe/shipped", "/s/vgshell/theme"]);
    assert.equal(render.reloadNamesWiring(hooked), false);
    const wiringHook = accepted("probe", targetText({ reload: { command: ["touch", "-c", "--", "@{wiring}", "@{state}", "@@{x}"], timeoutMs: 2000 } }));
    assert.equal(render.reloadNamesWiring(wiringHook), true);
    assert.deepEqual(render.reloadCommand(wiringHook, "/s/vgshell/theme", "/t/probe", "/home/u/.wezterm.lua"), ["touch", "-c", "--", "/home/u/.wezterm.lua", "/s/vgshell/theme", "@{x}"]);
    assert.throws(() => render.reloadCommand(wiringHook, "/s/vgshell/theme", "/t/probe"), /names placeholder wiring/);
    assert.deepEqual(render.reloadCommand(target("hex6"), "/s", "/t/probe"), ["probe", "--reload"]);
    assert.equal(render.reloadNamesWiring(target("hex6")), false);
    assert.equal(render.reloadAlways(hooked), true);
    assert.equal(render.reloadAlways(target("hex6")), false);
    assert.equal(render.reloadAlways(accepted("probe", targetText({ reload: { command: ["probe"], timeoutMs: 2000, always: false } }))), false);
    const hookless = accepted("probe", targetText({ reload: null }));
    assert.equal(render.reloadNamesWiring(hookless), false);
    assert.equal(render.reloadAlways(hookless), false);
    assert.throws(() => render.reloadCommand(hookless, "/s", "/t/probe"), /has no reload/);

    // A setup command is met by PATH alone; a target naming none always is.
    const setup = accepted("probe", targetText({ setup: "probe-setup" }));
    assert.equal(render.setupDone(setup, command => command === "probe-setup"), true);
    assert.equal(render.setupDone(setup, command => command === "probe"), false);
    assert.equal(render.setupDone(target("hex6"), () => false), true);
}
verify(require(rendererFile));

// Status text must use the judged roles even when a package's raw palette
// and ANSI slots are unreadable. These are the fields shipped apps consume.
const STATUS_RESTING_SURFACES = ["background", "surface", "surfaceRaised", "surfaceSunken"];
const DISCORD_STATUS_FIELDS = [
    ["--accent-new", "danger"],
    ...[["red", "danger"], ["green", "success"], ["blue", "info"], ["yellow", "warning"]]
        .flatMap(([hue, role]) => Array.from({ length: 5 }, (_, i) => [`--${hue}-${i + 1}`, role]))
];
const STATUS_TARGETS = [
    { name: "obsidian", file: "obsidian.css", format: "css", surfaces: STATUS_RESTING_SURFACES, fields: [
        ["--text-error", "danger"], ["--text-warning", "warning"], ["--text-success", "success"],
        ["--link-external-color", "info"], ["--link-external-color-hover", "info"]
    ] },
    { name: "oh-my-posh", file: "oh-my-posh.json", format: "json", surfaces: ["background"], fields: [
        ["danger", "danger"], ["success", "success"], ["warning", "warning"], ["info", "info"]
    ] },
    { name: "btop", file: "btop.theme", format: "btop", surfaces: ["background"], fields: [["proc_misc", "info"]] },
    { name: "hermes", file: "hermes.yaml", format: "yaml", surfaces: ["surfaceRaised"], fields: [["status_bar_critical", "danger"]] },
    ...["omp", "pi"].map(name => ({ name, file: `${name}.json`, format: "json", surfaces: ["surface"], fields: [["customMessageText", "warning"]] })),
    ...["vencord", "vesktop", "equibop"].map(name => ({ name, file: `${name}.css`, format: "css", surfaces: STATUS_RESTING_SURFACES,
        fields: DISCORD_STATUS_FIELDS, marks: [["--online", "success"], ["--dnd", "danger"], ["--idle", "warning"]] }))
];

function statusFields(text, format) {
    if (format === "json") {
        const doc = JSON.parse(text);
        return new Map(Object.entries(doc.colors || doc.palette));
    }
    const pattern = {
        css: /^\s*(--[\w-]+):\s*(#[\da-f]{6});\s*$/gm,
        yaml: /^\s*(\w+):\s*"(#[\da-f]{6})"\s*$/gm,
        btop: /^theme\[(\w+)\]="(#[\da-f]{6})"\s*$/gm
    }[format];
    assert.ok(pattern, format);
    const fields = new Map();
    for (const [, name, color] of text.matchAll(pattern)) {
        assert.equal(fields.has(name), false, `duplicate status field ${name}`);
        fields.set(name, color);
    }
    return fields;
}

function statusTemplatePairs(render, pkg, changeTemplate = text => text) {
    const pairs = [];
    for (const row of STATUS_TARGETS) {
        const dir = path.join(repo, "themes", "targets", row.name);
        const accepted = render.acceptTarget(logic, row.name, fs.readFileSync(path.join(dir, "target.json"), "utf8"));
        assert.equal(accepted.ok, true);
        const templates = new Map(accepted.target.files.map(file => [file.template,
            changeTemplate(fs.readFileSync(path.join(dir, file.template), "utf8"), row.name, file.template)]));
        const result = render.renderTarget(logic, TOKENS, accepted.target, templates,
            { values: pkg.values, slots: render.terminalSource(pkg, defaults).terminal, curated: new Map(), installed: false });
        assert.equal(result.ok, true);
        const text = result.files.find(file => file.destination === row.file).bytes.toString("utf8");
        const fields = statusFields(text, row.format);
        for (const [rows, surfaces, floor] of [[row.fields, row.surfaces, 4.5], [row.marks || [], ["background"], 3]]) {
            for (const [field, role] of rows) {
                const color = logic.parseColor(fields.get(field));
                assert.notEqual(color, null, `${row.name} ${field}`);
                for (const surface of surfaces) {
                    const background = pkg.values.color[surface];
                    const ratio = logic.contrastRatio(color, logic.parseColor(background));
                    assert.ok(ratio >= floor, `${row.name} ${field} on ${surface}: contrast ${ratio} < ${floor}`);
                    pairs.push({ target: row.name, field, role, foreground: fields.get(field), surface, background, ratio, floor });
                }
                assert.deepEqual(color, logic.parseColor(pkg.values.color[role]), `${row.name} ${field} role`);
            }
        }
    }
    return pairs;
}
// End status template contract.

let statusPairs = 0;
for (const [mode, background, foreground, colors] of [
    ["dark", "#000000", "#ffffff", { danger: "#f08080", success: "#90ee90", warning: "#ffff00", info: "#87cefa" }],
    ["light", "#ffffff", "#000000", { danger: "#900000", success: "#004400", warning: "#665500", info: "#000099" }]
]) {
    const pkg = logic.acceptPackage(TOKENS, {
        directoryName: "status",
        themeJson: JSON.stringify({ schemaVersion: 1, name: "status", tokens: {
            scheme: { mode }, palette: { background, foreground, danger: background, success: background, warning: background, info: background }, color: colors
        } }),
        terminalJson: slotsJson(() => background), shipped: false
    });
    assert.equal(pkg.ok, true);
    statusPairs += statusTemplatePairs(require(rendererFile), pkg).length;
    // Restore the old source mapping in an in-memory template copy. Only
    // the contrast assertion can fail here: rendering still succeeds.
    assert.throws(() => statusTemplatePairs(require(rendererFile), pkg, (text, target, file) => {
        if (target !== "obsidian" || file !== "obsidian.css") return text;
        const needle = "--text-error: #@{color.danger};";
        assert.equal(text.split(needle).length, 2);
        return text.replace(needle, "--text-error: #@{palette.danger};");
    }), error => error.code === "ERR_ASSERTION" && error.actual === false && error.expected === true);
}
console.log(`test-theme-render: status-pairs=${statusPairs} modes=dark,light controls=2`);

// KDE reads every foreground role in Colors:Selection on either selection
// fill. Status and link text must remain readable when its row is selected.
const SELECTION_ROLES = [
    ["ForegroundActive", "color.accent"],
    ["ForegroundInactive", "color.textMuted"],
    ["ForegroundLink", "color.info"],
    ["ForegroundNegative", "color.danger"],
    ["ForegroundNeutral", "color.warning"],
    ["ForegroundNormal", null],
    ["ForegroundPositive", "color.success"],
    ["ForegroundVisited", "color.accent"]
];
const selectionRender = require(rendererFile);
const themesDir = path.join(repo, "themes");
const selectionDir = path.join(themesDir, "targets", "kcolorscheme");
const selectionTemplate = fs.readFileSync(path.join(selectionDir, "kcolorscheme.colors"), "utf8");
const selectionTarget = selectionRender.acceptTarget(logic, "kcolorscheme",
    fs.readFileSync(path.join(selectionDir, "target.json"), "utf8"));
assert.equal(selectionTarget.ok, true);
const catalog = logic.acceptCatalogIndex(TOKENS,
    fs.readFileSync(path.join(themesDir, "catalog", "index.json"), "utf8"));
assert.equal(catalog.ok, true);
const catalogNames = Array.from(catalog.entries, entry => entry.name).sort();
const catalogDirs = fs.readdirSync(path.join(themesDir, "catalog"), { withFileTypes: true })
    .filter(entry => entry.isDirectory()).map(entry => entry.name).sort();
assert.deepEqual(catalogDirs, catalogNames);
assert.ok(catalogNames.includes("dracula"));
assert.ok(catalogNames.includes("flexoki-light"));
assert.equal(catalogNames.includes("vgs"), false);
const shippedNames = fs.readdirSync(themesDir, { withFileTypes: true })
    .filter(entry => entry.isDirectory() && !logic.RESERVED_DIRECTORIES.includes(entry.name))
    .map(entry => entry.name).sort();
assert.ok(shippedNames.includes("vgs"));
const selectionPackages = [
    ...shippedNames.map(name => ({ name, directory: path.join(themesDir, name), shipped: true })),
    ...catalogNames.map(name => ({ name, directory: path.join(themesDir, "catalog", name), shipped: false }))
].map(({ name, directory, shipped }) => {
    const terminalFile = path.join(directory, "terminal.json");
    const pkg = logic.acceptPackage(TOKENS, {
        directoryName: name,
        themeJson: fs.readFileSync(path.join(directory, "theme.json"), "utf8"),
        terminalJson: fs.existsSync(terminalFile) ? fs.readFileSync(terminalFile, "utf8") : undefined,
        shipped
    });
    assert.equal(pkg.ok, true);
    return { pkg, shipped };
});
const selectionDefaults = selectionPackages.find(entry => entry.shipped && entry.pkg.name === "vgs").pkg;

function verifySelection(pkg, shipped, template) {
    const rendered = selectionRender.renderTarget(logic, TOKENS, selectionTarget.target,
        new Map([["kcolorscheme.colors", template]]), {
            values: pkg.values,
            slots: selectionRender.terminalSource(pkg, selectionDefaults).terminal,
            curated: new Map(),
            installed: !shipped
        });
    assert.equal(rendered.ok, true);
    const output = rendered.files.find(file => file.destination === "kcolorscheme.colors");
    assert.notEqual(output, undefined);
    const fields = new Map();
    let selected = false;
    let sections = 0;
    for (const line of output.bytes.toString("utf8").split("\n")) {
        if (selectionRender.opensSection(line)) {
            selected = selectionRender.isSectionHeader(line, "Colors:Selection");
            if (selected) sections++;
        } else if (selected) {
            const key = selectionRender.assignedKey(line);
            if (key !== null) {
                assert.equal(fields.has(key), false);
                fields.set(key, line.slice(line.indexOf("=") + 1).trim());
            }
        }
    }
    assert.equal(sections, 1);
    assert.deepEqual([...fields.keys()].filter(key => key.startsWith("Foreground")).sort(),
        SELECTION_ROLES.map(([role]) => role).sort());
    const shortfalls = [];
    for (const [role] of SELECTION_ROLES) {
        const foreground = logic.parseColor(fields.get(role));
        assert.notEqual(foreground, null);
        assert.equal(foreground.a, 1);
        for (const surface of ["BackgroundNormal", "BackgroundAlternate"]) {
            const background = logic.parseColor(fields.get(surface));
            assert.notEqual(background, null);
            assert.equal(background.a, 1);
            const ratio = logic.contrastRatio(foreground, background);
            if (ratio < 4.5) shortfalls.push({ kind: "selection-contrast", package: pkg.name, role, surface, ratio, floor: 4.5 });
        }
    }
    assert.deepEqual(shortfalls, []);
}

for (const { pkg, shipped } of selectionPackages) verifySelection(pkg, shipped, selectionTemplate);
const selectionScratch = fs.mkdtempSync(path.join(os.tmpdir(), "kcolorscheme-control-"));
let selectionControls = 0;
try {
    const start = selectionTemplate.indexOf("[Colors:Selection]\n");
    assert.notEqual(start, -1);
    const end = selectionTemplate.indexOf("\n[", start + 1);
    assert.notEqual(end, -1);
    const section = selectionTemplate.slice(start, end);
    for (const [role, oldToken] of SELECTION_ROLES) {
        if (oldToken === null) continue;
        const needle = `${role}=#@{color.onAccent}`;
        assert.equal(section.split(needle).length, 2);
        const mutant = selectionTemplate.slice(0, start) +
            section.replace(needle, `${role}=#@{${oldToken}}`) + selectionTemplate.slice(end);
        assert.notEqual(mutant, selectionTemplate);
        const file = path.join(selectionScratch, `${role}.colors`);
        fs.writeFileSync(file, mutant, { flag: "wx" });
        assert.throws(() => verifySelection(selectionDefaults, true, fs.readFileSync(file, "utf8")),
            error => error instanceof assert.AssertionError && Array.isArray(error.actual) &&
                error.actual.some(shortfall => shortfall.kind === "selection-contrast" &&
                    shortfall.role === role && shortfall.surface === "BackgroundNormal" && shortfall.ratio < shortfall.floor));
        selectionControls++;
    }
} finally {
    fs.rmSync(selectionScratch, { recursive: true, force: true });
}
console.log(`test-theme-render: selection packages=${selectionPackages.length} roles=${SELECTION_ROLES.length} controls=${selectionControls}`);

// Helix reads jump labels as a dedicated style. Parse rendered TOML with
// Python's standard parser, as the editor-entry suite does for this target.
const helixDir = path.join(themesDir, "targets", "helix");
const helixTemplate = fs.readFileSync(path.join(helixDir, "helix.toml"), "utf8");
const helixTarget = selectionRender.acceptTarget(logic, "helix",
    fs.readFileSync(path.join(helixDir, "target.json"), "utf8"));
assert.equal(helixTarget.ok, true);

function verifyHelixJumpLabels(template) {
    const texts = selectionPackages.map(({ pkg, shipped }) => {
        const rendered = selectionRender.renderTarget(logic, TOKENS, helixTarget.target,
            new Map([["helix.toml", template]]), {
                values: pkg.values,
                slots: selectionRender.terminalSource(pkg, selectionDefaults).terminal,
                curated: new Map(),
                installed: !shipped
            });
        assert.equal(rendered.ok, true);
        const output = rendered.files.find(file => file.destination === "helix.toml");
        assert.notEqual(output, undefined);
        return output.bytes.toString("utf8");
    });
    const parsed = spawnSync("python3", ["-c",
        "import json, sys, tomllib; json.dump([tomllib.loads(text) for text in json.load(sys.stdin)], sys.stdout)"], {
        input: JSON.stringify(texts), encoding: "utf8",
        env: { PATH: process.env.PATH, LANG: "C.UTF-8", VGS_TEST_RUN: "1" }
    });
    assert.ifError(parsed.error);
    assert.equal(parsed.status, 0, parsed.stderr);
    const documents = JSON.parse(parsed.stdout);
    assert.equal(documents.length, selectionPackages.length);
    const shortfalls = [];
    const metrics = documents.map((document, index) => {
        const pkg = selectionPackages[index].pkg;
        const label = document["ui.virtual.jump-label"];
        assert.equal(logic.isPlainObject(label), true, pkg.name);
        const foreground = logic.parseColor(label.fg);
        const background = logic.parseColor(document["ui.background"].bg);
        assert.notEqual(foreground, null, pkg.name);
        assert.notEqual(background, null, pkg.name);
        const ratio = logic.contrastRatio(foreground, background);
        if (ratio < logic.READABILITY_FLOOR) shortfalls.push({ kind: "jump-label-contrast",
            package: pkg.name, foreground: label.fg, background: document["ui.background"].bg,
            ratio, floor: logic.READABILITY_FLOOR });
        return { package: pkg.name, mode: pkg.values.scheme.mode, foreground: label.fg,
            background: document["ui.background"].bg, ratio, modifiers: label.modifiers };
    });
    assert.deepEqual(shortfalls, []);
    for (const [index, metric] of metrics.entries()) {
        assert.deepEqual(logic.parseColor(metric.foreground),
            logic.parseColor(selectionPackages[index].pkg.values.color.accent), metric.package);
        assert.ok(Array.isArray(metric.modifiers) && metric.modifiers.includes("bold"), metric.package);
    }
    assert.ok(metrics.some(metric => metric.mode === "dark"));
    assert.ok(metrics.some(metric => metric.mode === "light"));
    return metrics;
}

const helixMetrics = verifyHelixJumpLabels(helixTemplate);
const helixScratch = fs.mkdtempSync(path.join(os.tmpdir(), "helix-jump-control-"));
try {
    const needle = '"ui.virtual.jump-label" = { fg = "#@{color.accent}", modifiers = ["bold"] }';
    assert.equal(helixTemplate.split(needle).length, 2);
    const mutant = helixTemplate.replace(needle,
        '"ui.virtual.jump-label" = { fg = "#@{color.textDisabled}", modifiers = ["bold"] }');
    assert.notEqual(mutant, helixTemplate);
    const file = path.join(helixScratch, "helix.toml");
    fs.writeFileSync(file, mutant, { flag: "wx" });
    assert.throws(() => verifyHelixJumpLabels(fs.readFileSync(file, "utf8")),
        error => error instanceof assert.AssertionError && Array.isArray(error.actual) &&
            error.actual.some(shortfall => shortfall.kind === "jump-label-contrast" &&
                shortfall.ratio < shortfall.floor));
} finally {
    fs.rmSync(helixScratch, { recursive: true, force: true });
}
console.log(`test-theme-render: helix-jump-label packages=${helixMetrics.length} modes=dark,light floor=${logic.READABILITY_FLOOR} control=disabled-grey-rejected`);

// RGB channel separation is a numerical distinction check. The owner judges
// appearance in real terminal pictures. Rose Pine's main ANSI blue/brightblack
// pair measured 55.650696 channels in the VGS-1043 role probe on 2026-10-07.
function channelSeparation(first, second) {
    const a = logic.parseColor(first), b = logic.parseColor(second);
    return 255 * Math.hypot(a.r - b.r, a.g - b.g, a.b - b.b);
}
function tmuxStyle(text, option) {
    const line = text.split("\n").find(line => line.startsWith("set -g " + option + " "));
    assert.ok(line, option);
    const value = /^set -g [^ ]+ "([^"\n]+)"$/.exec(line);
    assert.ok(value, option);
    return Object.fromEntries(value[1].split(",").map(part => part.includes("=") ? part.split("=") : [part, true]));
}
function verifyAppStyles(render, changedTemplates = {}) {
    const targets = Object.fromEntries(["tmux", "neovim", "ghostty"].map(name => {
        const dir = path.join(repo, "themes", "targets", name);
        const accepted = render.acceptTarget(logic, name, fs.readFileSync(path.join(dir, "target.json"), "utf8"));
        assert.equal(accepted.ok, true);
        const templates = new Map(accepted.target.files.map(file => [file.template,
            changedTemplates[name] ?? fs.readFileSync(path.join(dir, file.template), "utf8")]));
        return [name, { target: accepted.target, templates }];
    }));
    const catalog = JSON.parse(fs.readFileSync(path.join(repo, "themes", "catalog", "index.json"), "utf8"));
    assert.ok(catalog.entries.some(entry => entry.name === "horizon-light"));
    assert.ok(catalog.entries.some(entry => entry.name === "white"));
    const metrics = [];
    for (const name of ["vgs", ...catalog.entries.map(entry => entry.name)]) {
        const dir = path.join(repo, "themes", name === "vgs" ? "vgs" : "catalog/" + name);
        const pkg = logic.acceptPackage(TOKENS, { directoryName: name,
            themeJson: fs.readFileSync(path.join(dir, "theme.json"), "utf8"),
            terminalJson: fs.readFileSync(path.join(dir, "terminal.json"), "utf8"), shipped: name === "vgs" });
        assert.equal(pkg.ok, true);
        const original = JSON.stringify({ values: pkg.values, slots: pkg.terminal });
        const rendered = Object.fromEntries(Object.entries(targets).map(([app, data]) => {
            const result = render.renderTarget(logic, TOKENS, data.target, data.templates,
                { values: pkg.values, slots: pkg.terminal, curated: new Map(), installed: name !== "vgs" });
            assert.equal(result.ok, true);
            return [app, result.files[0].bytes.toString("utf8")];
        }));
        assert.equal(JSON.stringify({ values: pkg.values, slots: pkg.terminal }), original, "render leaves package data unchanged");
        assert.equal(/^palette = 8=(#[0-9a-f]{6})$/m.exec(rendered.ghostty)[1],
            pkg.terminal.color8.slice(0, 7), name + "/terminal preserves its original brightblack");
        const bg = /^background = (#[0-9a-f]{6})$/m.exec(rendered.ghostty)[1];
        assert.equal(/^vim.o.background = "(dark|light)"$/m.exec(rendered.neovim)[1], pkg.values.scheme.mode);
        for (const group of ["Normal", "NormalNC", "SignColumn"]) {
            const highlight = rendered.neovim.split("\n").find(line => line.trimStart().startsWith('hl("' + group + '",'));
            assert.ok(highlight, group);
            assert.equal(/bg = "(#[0-9a-f]{6})"/.exec(highlight)[1], bg, name + "/" + group);
        }
        const status = tmuxStyle(rendered.tmux, "status-style");
        const session = tmuxStyle(rendered.tmux, "status-left-style");
        const active = tmuxStyle(rendered.tmux, "window-status-current-style");
        const inactive = tmuxStyle(rendered.tmux, "window-status-style");
        assert.equal(status.bg, bg);
        assert.equal(active.bg, bg);
        assert.equal(inactive.bg, bg);
        assert.equal(session.fg, pkg.values.color.onInfo.slice(0, 7));
        assert.equal(active.fg, pkg.values.color.info.slice(0, 7));
        assert.equal(active.bold, true);
        assert.equal(inactive.bold, undefined);
        const ratios = Object.fromEntries(Object.entries({ status, session, active, inactive }).map(([role, style]) => {
            const ratio = logic.contrastRatio(logic.parseColor(style.fg), logic.parseColor(style.bg));
            assert.deepEqual(ratio < 4.5 ? [{ kind: "app-style-contrast", theme: name, role, ratio, floor: 4.5 }] : [], []);
            return [role, ratio];
        }));
        assert.equal(session.bg, pkg.values.color.info.slice(0, 7));
        const separation = channelSeparation(active.fg, inactive.fg);
        assert.ok(separation >= 55.65, name + "/inactive RGB separation=" + separation);
        const old = pkg.terminal.color8.slice(0, 7);
        const oldRatio = logic.contrastRatio(logic.parseColor(old), logic.parseColor(bg));
        if (oldRatio >= 4.5 && channelSeparation(old, active.fg) >= 55.65) {
            assert.equal(inactive.fg, old, name + "/preserve distinct readable inactive text");
        } else {
            const colour = logic.parseColor(inactive.fg);
            assert.equal(colour.r, colour.g, name + "/repair uses grey");
            assert.equal(colour.g, colour.b, name + "/repair uses grey");
        }
        for (const option of ["status-left", "window-status-format", "window-status-current-format"]) {
            const line = rendered.tmux.split("\n").find(line => line.startsWith("set -g " + option + " "));
            assert.ok(line);
            assert.equal(line.includes("#["), false, option + "/inline style overrides managed colours");
        }
        if (name === "horizon-light") assert.equal(session.fg, "#ffffff");
        metrics.push({ name, background: bg, session, active, inactive, ratios, separation, preserved: inactive.fg === old });
    }
    return metrics;
}
verifyAppStyles(require(rendererFile));
const tmuxTemplate = fs.readFileSync(path.join(repo, "themes/targets/tmux/tmux.conf"), "utf8");
const styleControls = [
    ["old session block text", 'fg=#@{color.onInfo}', 'fg=#@{color.text}'],
    ["rejected session without block", 'set -g status-left-style "bg=#@{color.info}', 'set -g status-left-style "bg=#@{color.background}'],
    ["old filled active tab", 'set -g window-status-current-style "bg=#@{color.background}', 'set -g window-status-current-style "bg=#@{palette.accent}'],
    ["rejected neutral unbolded active", 'fg=#@{color.info},bold', 'fg=#@{color.textHeading}'],
    ["old inline active", 'set -g window-status-current-format " #I:#W#F "', 'set -g window-status-current-format "#[fg=blue,bold] #I:#W#F "']
];
for (const [label, needle, replacement] of styleControls) {
    assert.equal(tmuxTemplate.split(needle).length, 2, label);
    assert.throws(() => verifyAppStyles(require(rendererFile), { tmux: tmuxTemplate.replace(needle, replacement) }), undefined, label);
}
const sessionScratch = fs.mkdtempSync(path.join(os.tmpdir(), "tmux-session-control-"));
try {
    const needle = 'set -g status-left-style "bg=#@{color.info}';
    assert.equal(tmuxTemplate.split(needle).length, 2);
    const mutant = tmuxTemplate.replace(needle, 'set -g status-left-style "bg=#@{palette.info}');
    assert.notEqual(mutant, tmuxTemplate);
    const file = path.join(sessionScratch, "tmux.conf");
    fs.writeFileSync(file, mutant, { flag: "wx" });
    assert.throws(() => verifyAppStyles(require(rendererFile), { tmux: fs.readFileSync(file, "utf8") }),
        error => error instanceof assert.AssertionError && Array.isArray(error.actual) &&
            error.actual.some(shortfall => shortfall.kind === "app-style-contrast" &&
                shortfall.theme === "akane" && shortfall.role === "session" && shortfall.ratio < shortfall.floor));
} finally {
    fs.rmSync(sessionScratch, { recursive: true, force: true });
}
console.log("test-theme-render: tmux-session control=palette-info rejected=akane/session");

// Alacritty's search, hint labels and footer have explicit colour pairs.
// Parse the rendered TOML, including catalog packages that use the same
// accent and primary foreground, before judging contrast and role identity.
const alacrittyDir = path.join(themesDir, "targets", "alacritty");
const alacrittyTemplate = fs.readFileSync(path.join(alacrittyDir, "alacritty.toml"), "utf8");
const alacrittyTarget = selectionRender.acceptTarget(logic, "alacritty",
    fs.readFileSync(path.join(alacrittyDir, "target.json"), "utf8"));
assert.equal(alacrittyTarget.ok, true);
const ALACRITTY_ROLES = ["search.matches", "search.focused_match", "hints.start", "hints.end", "footer_bar"];

function verifyAlacrittyColors(template, packages = selectionPackages) {
    const texts = packages.map(({ pkg, shipped }) => {
        const rendered = selectionRender.renderTarget(logic, TOKENS, alacrittyTarget.target,
            new Map([["alacritty.toml", template]]), {
                values: pkg.values,
                slots: selectionRender.terminalSource(pkg, selectionDefaults).terminal,
                curated: new Map(), installed: !shipped
            });
        assert.equal(rendered.ok, true);
        const output = rendered.files.find(file => file.destination === "alacritty.toml");
        assert.notEqual(output, undefined);
        return output.bytes.toString("utf8");
    });
    const parsed = spawnSync("python3", ["-c",
        "import json, sys, tomllib; json.dump([tomllib.loads(text) for text in json.load(sys.stdin)], sys.stdout)"], {
        input: JSON.stringify(texts), encoding: "utf8",
        env: { PATH: process.env.PATH, LANG: "C.UTF-8", VGS_TEST_RUN: "1" }
    });
    assert.ifError(parsed.error);
    assert.equal(parsed.status, 0, parsed.stderr);
    const documents = JSON.parse(parsed.stdout);
    assert.equal(documents.length, packages.length);
    const shortfalls = [];
    for (const [index, document] of documents.entries()) {
        const pkg = packages[index].pkg;
        const colors = document.colors;
        const base = logic.parseColor(colors.primary.background);
        assert.notEqual(base, null);
        const pairs = new Map();
        for (const role of ALACRITTY_ROLES) {
            const pair = role.split(".").reduce((value, key) => value?.[key], colors);
            assert.equal(logic.isPlainObject(pair), true, `${pkg.name}/${role}`);
            const foreground = logic.parseColor(pair.foreground);
            const background = logic.parseColor(pair.background);
            assert.notEqual(foreground, null, `${pkg.name}/${role}`);
            assert.notEqual(background, null, `${pkg.name}/${role}`);
            const textRatio = logic.contrastRatio(foreground, background);
            const boundaryRatio = logic.contrastRatio(background, base);
            if (textRatio < 4.5) shortfalls.push({ kind: "alacritty-text", package: pkg.name, role, ratio: textRatio, floor: 4.5 });
            if (boundaryRatio < 3) shortfalls.push({ kind: "alacritty-boundary", package: pkg.name, role, ratio: boundaryRatio, floor: 3 });
            pairs.set(role, pair);
        }
        if (pairs.get("search.matches").background === pairs.get("search.focused_match").background) {
            shortfalls.push({ kind: "alacritty-focused-distinct", package: pkg.name, role: "search.focused_match" });
        }
        for (const role of ["hints.start", "hints.end"]) {
            const pair = pairs.get(role);
            if (pair.foreground === colors.primary.foreground) {
                shortfalls.push({ kind: "alacritty-hint-distinct", package: pkg.name, role });
            }
        }
    }
    assert.deepEqual(shortfalls, []);
    return documents;
}

const alacrittyDocuments = verifyAlacrittyColors(alacrittyTemplate);
assert.ok(selectionPackages.some(({ pkg }) => pkg.values.scheme.mode === "dark"));
assert.ok(selectionPackages.some(({ pkg }) => pkg.values.scheme.mode === "light"));
assert.ok(selectionPackages.some(({ pkg }) => pkg.name === "vice-city"));
const alacrittyScratch = fs.mkdtempSync(path.join(os.tmpdir(), "alacritty-colors-control-"));
let alacrittyControls = 0;
try {
    const sectionPair = (template, role, foreground, background) => {
        const expression = new RegExp(`(\\[colors\\.${role.replaceAll(".", "\\.")}\\]\\n)foreground = "[^"\\n]+"\\nbackground = "[^"\\n]+"`);
        assert.equal([...template.matchAll(new RegExp(expression.source, "g"))].length, 1);
        const mutant = template.replace(expression, `$1foreground = "${foreground}"\nbackground = "${background}"`);
        assert.notEqual(mutant, template);
        return mutant;
    };
    const controls = ALACRITTY_ROLES.flatMap(role => {
        const fill = role === "search.focused_match" || role === "hints.start" ? "#@{color.accent}" : "#@{color.textMuted}";
        return [
            { kind: "alacritty-text", role, template: sectionPair(alacrittyTemplate, role, fill, fill) },
            { kind: "alacritty-boundary", role, template: sectionPair(alacrittyTemplate, role,
                "#@{color.text}", "#@{color.background}") }
        ];
    });
    controls.push({ kind: "alacritty-focused-distinct", role: "search.focused_match",
        template: sectionPair(alacrittyTemplate, "search.focused_match", "#@{color.background}", "#@{color.textMuted}") });
    // Restore ordinary text colours: contrast still passes, but the
    // hint foreground loses its distinction from the labelled text.
    for (const role of ["hints.start", "hints.end"]) {
        controls.push({ kind: "alacritty-hint-distinct", role,
            template: sectionPair(alacrittyTemplate, role, "#@{palette.foreground}", "#@{color.background}") });
    }
    for (const [index, control] of controls.entries()) {
        const file = path.join(alacrittyScratch, `${index}.toml`);
        fs.writeFileSync(file, control.template, { flag: "wx" });
        assert.throws(() => verifyAlacrittyColors(fs.readFileSync(file, "utf8")),
            error => error instanceof assert.AssertionError && Array.isArray(error.actual) &&
                error.actual.some(shortfall => shortfall.kind === control.kind && shortfall.role === control.role));
        alacrittyControls++;
    }
} finally {
    fs.rmSync(alacrittyScratch, { recursive: true, force: true });
}
console.log(`test-theme-render: alacritty packages=${alacrittyDocuments.length} roles=${ALACRITTY_ROLES.length} text-floor=4.5 boundary-floor=3 controls=${alacrittyControls}`);

// Each control removes one rule's behaviour from a copy of the renderer and
// keeps the text around it. The suite must fail on every copy.
const CONTROLS = [
    ["tmux derivation never changes terminal", 'if (target.name === "tmux") input = { ...input, slots: tmuxSlots(logic, input) };', 'if (target.name === "tmux" || target.name === "ghostty") input = { ...input, slots: tmuxSlots(logic, input) };', verifyAppStyles],
    ["tmux old inactive values", 'if (target.name === "tmux") input = { ...input, slots: tmuxSlots(logic, input) };', "", verifyAppStyles],
    ["tmux readability", 'const readable = color => color.a === 1 && logic.contrastRatio(color, background) >= logic.READABILITY_FLOOR;', 'const readable = color => true;', verifyAppStyles],
    ["tmux distinction", 'const distinct = color => separation(color) >= 55.65;', 'const distinct = color => true;', verifyAppStyles],
    ["tmux preserve distinct readable", 'if (readable(inactive) && distinct(inactive)) return input.slots;', '', verifyAppStyles],
    ["hex6 encoder", "hex6: (hex, background) => hex6(hex, background)", "hex6: hex => hex.slice(1, 7)"],
    ["hex8 encoder", "hex8: hex => hex.slice(1, 9)", "hex8: hex => hex.slice(1, 7)"],
    ["gnome accent composited", '"gnome-accent": (hex, background) => gnomeAccent(hex6(hex, background))', '"gnome-accent": hex => gnomeAccent(hex.slice(1, 7))'],
    ["gnome accent grey", "if (colour.c < GREY_CHROMA) return GREY_ACCENT;", "if (false) return GREY_ACCENT;"],
    ["gnome accent grey by hue never", "if (name === GREY_ACCENT) continue;", ""],
    ["gnome accent hue wraps", "return Math.min(d, 360 - d);", "return d;"],
    ["gnome accent linear light", "return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;", "return c;"],
    ["escape", 'if (m[0] === "@@{") {', "if (false) {"],
    ["pass-through", "const MARKER = /@@\\{|@\\{([^}]*)\\}|@\\{/g;", "const MARKER = /@@\\{|[@#$]\\{([^}]*)\\}|@\\{/g;"],
    ["unterminated", "if (m[1] === undefined) return { ok: false, at: m.index };", "if (m[1] === undefined) continue;"],
    ["unknown placeholder", "if (value === undefined) return refused(", "if (false) return refused("],
    ["group placeholder", "if (!logic.isLeaf(leaf)) return undefined;", "if (leaf === undefined) return undefined;"],
    ["slot name", "return logic.terminalSlotNames().includes(slot) ? encode(input.slots[slot]) : undefined;", "return encode(input.slots[slot]);"],
    ["case written", "if (cases.length > 0) return caseText(leaf, cases, value);", "if (false) return caseText(leaf, cases, value);"],
    ["slot takes no case", "if (cases.length > 0) return undefined;", "if (false) return undefined;"],
    ["case on a choice only", 'if (leaf.type !== "choice") return undefined;', 'if (!Array.isArray(leaf.options)) return "x";'],
    ["case text present", "const CASE_PATTERN = /^([^=]+)=(.+)$/;", "const CASE_PATTERN = /^([^=]+)=(.*)$/;"],
    ["case has its =", "if (m === null || !leaf.options", "if (m === null && false || !leaf.options"],
    ["case option known", "!leaf.options.includes(m[1]) || texts.has(m[1])", "texts.has(m[1])"],
    ["case option once", "!leaf.options.includes(m[1]) || texts.has(m[1])", "!leaf.options.includes(m[1])"],
    ["case every option", "return texts.size === leaf.options.length ? texts.get(value) : undefined;", "return texts.get(value);"],
    ["non-colour token", 'return leaf.type === "color" ? encode(value) : String(value);', "return encode(String(value));"],
    ["curated precedence", "const curated = present && !drop && curatedTaken(", "const curated = false && curatedTaken("],
    ["runsCode required", 'const TARGET_KEYS = ["app", "encoder", "files", "detect", "wiring", "reload", "runsCode"];', 'const TARGET_KEYS = ["app", "encoder", "files", "detect", "wiring", "reload"];'],
    ["runsCode boolean", 'if (typeof document.runsCode !== "boolean") return', "if (false) return"],
    ["drop only installed", "const drop = present && input.installed && target.runsCode;", "const drop = present && target.runsCode;"],
    ["drop only runsCode", "const drop = present && input.installed && target.runsCode;", "const drop = present && input.installed;"],
    ["dropped named", "if (drop) dropped.push(file.destination);", "if (false) dropped.push(file.destination);"],
    ["dropped not taken", "const curated = present && !drop && curatedTaken(", "const curated = present && curatedTaken("],
    ["dropped never judged", "const drop = present && input.installed && target.runsCode;", "const drop = present && input.installed && target.runsCode && curatedTaken(logic, file, input.curated.get(file.destination));"],
    ["source required", 'if (typeof input.installed !== "boolean")', "if (false)"],
    ["curated keys admitted", "k => FILE_KEYS.includes(k) || k === CURATED_KEYS_KEY)", "k => FILE_KEYS.includes(k))"],
    ["curated keys shape", "(!Array.isArray(file.curatedKeys) || file.curatedKeys.length === 0 || !file.curatedKeys.every(isLine))", "false"],
    ["curated keys judged", "if (!logic.hasOwn(file, CURATED_KEYS_KEY)) return true;", "return true;"],
    ["curated keys any key", "file.curatedKeys.some(key => logic.hasOwn(document, key))", "file.curatedKeys.every(key => logic.hasOwn(document, key))"],
    ["curated keys object", "return logic.isPlainObject(document) && file.curatedKeys", "return true && file.curatedKeys"],
    ["curated file judges its template", "for (const part of template.parts) {", "for (const part of input.curated.has(file.destination) ? [] : template.parts) {"],
    ["own terminal first", "for (const candidate of [pkg, defaults]) {", "for (const candidate of [defaults, pkg]) {"],
    ["terminal fallback", "for (const candidate of [pkg, defaults]) {", "for (const candidate of [pkg]) {"],
    ["target name", "if (typeof name !== \"string\" || !TARGET_NAME_PATTERN.test(name))", "if (false)"],
    ["unknown key", "if (!TARGET_KEYS.includes(key) && key !== SELECT_KEY && key !== SETUP_KEY && key !== ACCOUNTS_KEY) return", "if (false) return"],
    ["missing key", "if (!logic.hasOwn(document, key)) return", "if (false) return"],
    ["app", "if (!isLine(document.app)) return", "if (false) return"],
    ["encoder name", "if (!logic.hasOwn(ENCODERS, document.encoder)) return", "if (false) return"],
    ["files list", "if (!Array.isArray(document.files) || document.files.length === 0) return", "if (!Array.isArray(document.files)) return"],
    ["file keys", "!FILE_KEYS.every(k => logic.hasOwn(file, k)) ||", "false ||"],
    ["template name", "if (!logic.isPackageName(file.template) || file.template === TARGET_FILE) return", "if (false) return"],
    ["destination prefix", "!file.destination.startsWith(name + \".\")", "false"],
    ["unique destination", "if (destinations.has(document.files[at].destination)) return", "if (false) return"],
    ["detect", "if (!Array.isArray(document.detect) || !document.detect.every(entry => isDetectEntry(logic, entry))) return", "if (false) return"],
    ["detect command name", "if (!Array.isArray(entry)) return logic.isPackageName(entry);", "if (!Array.isArray(entry)) return true;"],
    ["detect list admitted", "if (!Array.isArray(entry)) return logic.isPackageName(entry);", "if (!Array.isArray(entry) || true) return logic.isPackageName(entry);"],
    ["detect list present", "return entry.length > 0 && entry.every(logic.isPackageName);", "return entry.every(logic.isPackageName);"],
    ["detect list names", "return entry.length > 0 && entry.every(logic.isPackageName);", "return entry.length > 0;"],
    ["detected any of a list", "Array.isArray(entry) ? entry.some(onPath) : onPath(entry)", "Array.isArray(entry) ? entry.every(onPath) : onPath(entry)"],
    ["detected every entry", "return detect.every(entry => Array.isArray", "return detect.some(entry => Array.isArray"],
    ["wiring required keys", "!WIRING_KEYS.every(key => logic.hasOwn(wiring, key)) ||", "false ||"],
    ["wiring unknown key", "!Object.keys(wiring).every(key => WIRING_KEYS.includes(key) || INCLUDE_OPTIONAL_KEYS.includes(key))", "false"],
    ["wiring section admitted", 'const INCLUDE_OPTIONAL_KEYS = ["section", "profiles", "fallbacks"];', 'const INCLUDE_OPTIONAL_KEYS = ["profiles", "fallbacks"];'],
    ["wiring profiles admitted", 'const INCLUDE_OPTIONAL_KEYS = ["section", "profiles", "fallbacks"];', 'const INCLUDE_OPTIONAL_KEYS = ["section", "fallbacks"];'],
    ["wiring fallbacks admitted", 'const INCLUDE_OPTIONAL_KEYS = ["section", "profiles", "fallbacks"];', 'const INCLUDE_OPTIONAL_KEYS = ["section", "profiles"];'],
    ["wiring section name", "(typeof wiring.section !== \"string\" || !SECTION_PATTERN.test(wiring.section))", "false"],
    ["wiring profiles list", "(!Array.isArray(wiring.profiles) || wiring.profiles.length === 0 ||", "(!Array.isArray(wiring.profiles) ||"],
    ["wiring profiles path", "!wiring.profiles.every(ini => typeof ini === \"string\" && ini.split(\"/\").every(segment => DIR_SEGMENT_PATTERN.test(segment)))", "!wiring.profiles.every(ini => typeof ini === \"string\")"],
    ["wiring fallbacks list", "(!Array.isArray(wiring.fallbacks) || wiring.fallbacks.length === 0 ||", "(!Array.isArray(wiring.fallbacks) ||"],
    ["wiring fallbacks path", "!wiring.fallbacks.every(file => typeof file === \"string\" && file.split(\"/\").every(segment => DIR_SEGMENT_PATTERN.test(segment)))", "!wiring.fallbacks.every(file => typeof file === \"string\")"],
    ["wiring fallbacks exclude profiles", 'if (logic.hasOwn(wiring, "fallbacks") && logic.hasOwn(wiring, "profiles")) return "key=wiring.fallbacks";', 'if (false) return "key=wiring.fallbacks";'],
    ["profile sections only", "PROFILE_SECTION.test(line.slice(1, -1).trim()) ? new Map() : null", "new Map()"],
    ["profile lines trimmed", "const line = raw.trim();", "const line = raw;"],
    ["profile value keeps its =", 'const at = line.indexOf("=");', 'const at = line.lastIndexOf("=");'],
    ["profile relative flag", 'relative: keys.get("IsRelative") === "1"', 'relative: keys.has("IsRelative")'],
    ["profile relative path present", 'dir.relative ? dir.path !== "" :', "dir.relative ? true :"],
    ["profile absolute path", ': dir.path.startsWith("/"));', ': dir.path !== "");'],
    ["wiring file", "!wiring.file.split(\"/\").every(logic.isPackageName)", "false"],
    ["wiring line placeholder", "if (names.length === 0 || names.some(placeholder => placeholder !== STATE_PLACEHOLDER)) return", "if (false) return"],
    ["wiring line is one line", "if (!isLine(wiring.line)) return", "if (typeof wiring.line !== \"string\") return"],
    ["wiring create", "if (typeof wiring.create !== \"boolean\") return", "if (false) return"],
    ["reload required keys", "!RELOAD_KEYS.every(key => logic.hasOwn(reload, key)) ||", "false ||"],
    ["reload unknown key", "!Object.keys(reload).every(key => RELOAD_KEYS.includes(key) || key === ALWAYS_KEY)", "false"],
    ["reload always admitted", "RELOAD_KEYS.includes(key) || key === ALWAYS_KEY)", "RELOAD_KEYS.includes(key))"],
    ["reload always boolean", "typeof reload.always !== \"boolean\"", "false"],
    ["reload argument placeholder", "!allowed.includes(name)", "false"],
    ["reload target placeholder", "const names = [STATE_PLACEHOLDER, TARGET_PLACEHOLDER];", "const names = [STATE_PLACEHOLDER];"],
    ["reload target written", "const values = { [STATE_PLACEHOLDER]: state, [TARGET_PLACEHOLDER]: dir };", "const values = { [STATE_PLACEHOLDER]: state, [TARGET_PLACEHOLDER]: state };"],
    ["reload argument unterminated", "list === null ||", "false ||"],
    ["reload wiring placeholder gate", 'if (target.wiring !== null && wiringForm(target.wiring) === "include" && !logic.hasOwn(target.wiring, "profiles")) names.push(WIRING_PLACEHOLDER);', "names.push(WIRING_PLACEHOLDER);"],
    ["reload names wiring", "return names !== null && names.includes(WIRING_PLACEHOLDER);", "return false;"],
    ["reload argument state", "target.reload.command.map(arg => withValues(arg, values,", "target.reload.command.map(arg => String(arg,"],
    ["reload always read", "target.reload.always === true", "target.reload.always !== undefined"],
    ["setup admitted", "key !== SELECT_KEY && key !== SETUP_KEY && key !== ACCOUNTS_KEY)", "key !== SELECT_KEY && key !== ACCOUNTS_KEY)"],
    ["setup is a command name", "!logic.isPackageName(document.setup)", "false"],
    ["setup read", "target.setup === undefined || onPath(target.setup)", "true"],
    ["wiring none form", "if (wiring === null) return \"none\";", "if (false) return \"none\";"],
    ["wiring null accepted", "document.wiring === null ? \"\"", "document.wiring === undefined ? \"\""],
    ["reload command", "if (!Array.isArray(reload.command) || reload.command.length === 0 || !reload.command.every(isLine)) return", "if (false) return"],
    ["reload timeout", "if (!Number.isInteger(reload.timeoutMs) || reload.timeoutMs <= 0) return", "if (false) return"],
    ["wiring line state", "        return values[part.name];\n", "        return part.name === STATE_PLACEHOLDER ? \"@{state}\" : values[part.name];\n"],
    ["wiring whole line", "if (lines.includes(line)) return null;", "if (text !== undefined && text.includes(line)) return null;"],
    ["wiring line first", "return line + \"\\n\" + (text === undefined ? \"\" : text);", "return (text === undefined ? \"\" : text) + line + \"\\n\";"],
    ["wiring creates", "const lines = text === undefined ? [] : text.split(\"\\n\");", "if (text === undefined) return null;\n    const lines = text.split(\"\\n\");"],
    ["wiring into its section", "if (at !== -1) {", "if (false) {"],
    ["wiring after the header", "lines.slice(0, at + 1).concat(line, lines.slice(at + 1))", "lines.slice(0, at).concat(line, lines.slice(at))"],
    ["wiring the first header", "lines.findIndex(existing => isSectionHeader(existing, section))", "lines.findLastIndex(existing => isSectionHeader(existing, section))"],
    ["section header form", "return m !== null && m[1] === section;", "return text === \"[\" + section + \"]\";"],
    ["section header whole name", "const SECTION_HEADER = /^\\s*\\[\\s*([^\\]]*?)\\s*\\]\\s*(?:#.*)?$/;", "const SECTION_HEADER = /^\\s*\\[+\\s*([^\\]]*?)\\s*\\]/;"],
    ["section header appended", "\"[\" + section + \"]\\n\" + line", "line"],
    ["section key conflict", "if (key !== null && assignedKey(lines[index]) === key) assigning.push(index);", "if (false) assigning.push(index);"],
    ["section array merged", "const array = assigning.length === 1 && element !== null ? stringArray(own) : null;", "const array = null;"],
    ["section array assigned once", "const array = assigning.length === 1 && element !== null ?", "const array = element !== null ?"],
    ["wiring line one string", "array === null || array.elements.length !== 1 ? null", "array === null || array.elements.length === 0 ? null"],
    ["wiring line an array", "&& element !== null ? stringArray(own)", "? stringArray(own)"],
    ["section array holds it already", "if (array.elements.some(held => own.slice(held.start, held.end) === element)) return null;", "if (false) return null;"],
    ["section array theme first", "const into = array.elements.length === 0 ? array.close : array.elements[0].start;", "const into = array.close;"],
    ["string array opens", 'if (text[at] !== "[") return null;', "if (false) return null;"],
    ["string array blanks", 'while (text[at] === " " || text[at] === "\\t") at++;', "while (false) at++;"],
    ["string array strings only", `if (quote !== "\\"" && quote !== "'") return null;`, "if (quote === undefined) return null;"],
    ["string array basic escape", 'at += quote === "\\"" && text[at] === "\\\\" ? 2 : 1;', "at += 1;"],
    ["string array literal no escape", 'at += quote === "\\"" && text[at] === "\\\\" ? 2 : 1;', 'at += text[at] === "\\\\" ? 2 : 1;'],
    ["string array separator", 'else if (text[at] !== "]") return null;', "else if (false) return null;"],
    ["string array comment after", "/^\\s*(?:#.*)?$/.test(text.slice(at + 1))", "/^\\s*$/.test(text.slice(at + 1))"],
    ["string array nothing else after", "/^\\s*(?:#.*)?$/.test(text.slice(at + 1))", "/.*/.test(text.slice(at + 1))"],
    ["section ends at the next header", "index > at && ANY_HEADER.test(existing)", "false"],
    ["array of tables ends a section", "const ANY_HEADER = /^\\s*\\[/;", "const ANY_HEADER = /^\\s*\\[[^\\[]/;"],
    ["assigned key trimmed", "text.slice(0, at).trim();", "text.slice(0, at);"],
    ["dotted root conflict", "if (root.some(existing =>", "if (false && root.some(existing =>"],
    ["dotted key prefix", "name === section || (name !== null && name.startsWith(section + \".\"))", "name === section"],
    ["dotted keys at the root only", "const root = lines.slice(0, first === -1 ? lines.length : first);", "const root = lines;"],
    ["section appended on its own line", "(before === \"\" || before.endsWith(\"\\n\") ? \"\" : \"\\n\")", "\"\""],
    ["entry form", 'return entryItemKey(wiring) === "" ? "include" : "entry";', 'return "include";'],
    ["entry item kind", "return present.length === 1 ? present[0] : \"\";", "return present[0] || \"links\";"],
    ["entry required keys", "if (itemKey === \"\" || !ENTRY_BASE_KEYS.every(key => logic.hasOwn(wiring, key)) ||", "if (false ||"],
    ["entry unknown key", "!Object.keys(wiring).every(key => ENTRY_BASE_KEYS.includes(key) || ENTRY_ITEM_KEYS.includes(key) || ENTRY_OPTIONAL_KEYS.includes(key))) return", "false) return"],
    ["entry vaults admitted", 'const ENTRY_OPTIONAL_KEYS = ["vaults"];', "const ENTRY_OPTIONAL_KEYS = [];"],
    ["entry vaults path", 'if (logic.hasOwn(wiring, "vaults") && !isRelativePath(wiring.vaults)) return', "if (false) return"],
    ["vault registry parses", "        registry = JSON.parse(text);\n    } catch (e) {\n        return null;", "        registry = JSON.parse(text);\n    } catch (e) {\n        return [];"],
    ["vault registry is an object", "if (!logic.isPlainObject(registry)) return null;", "if (registry === null) return null;"],
    ["vault registry without vaults", 'if (!logic.hasOwn(registry, "vaults")) return [];', ""],
    ["vault list is an object", "if (!logic.isPlainObject(registry.vaults)) return null;", "if (false) return null;"],
    ["vault entry is an object", "logic.isPlainObject(vault) ? vault.path : undefined", "vault.path"],
    ["vault path absolute", 'dir.startsWith("/") && !dirs.includes(dir)', "!dirs.includes(dir)"],
    ["vault listed once", "&& !dirs.includes(dir)) dirs.push(dir);", ") dirs.push(dir);"],
    ["entry base", "if (!entryBaseAccepted(wiring.base, hasAccounts)) return", "if (false) return"],
    ["entry cache base", 'const ENTRY_BASES = ["config", "home", "cache"];', 'const ENTRY_BASES = ["config", "home"];'],
    ["accounts key admitted", "&& key !== ACCOUNTS_KEY) return", ") return"],
    ["accounts id shape", "if (hasAccounts && !logic.isPackageName(document.accounts)) return", "if (false) return"],
    ["account base requires accounts", "return ENTRY_BASES.includes(base) || (hasAccounts && base === ACCOUNT_BASE);", "return ENTRY_BASES.includes(base) || base === ACCOUNT_BASE;"],
    ["accounts require account wiring and selection", "if (hasAccounts) {", "if (false) {"],
    ["entry dir segment", "const DIR_SEGMENT_PATTERN = /^\\.?[A-Za-z0-9][A-Za-z0-9._-]*$/;", "const DIR_SEGMENT_PATTERN = /^[.A-Za-z0-9_-]+$/;"],
    ["entry owned", "if (typeof wiring.owned !== \"boolean\") return", "if (false) return"],
    ["entry item present", "if (!logic.isPlainObject(wiring[itemKey]) || Object.keys(wiring[itemKey]).length === 0) return", "if (!logic.isPlainObject(wiring[itemKey])) return"],
    ["entry item name", "if (!logic.isPackageName(name)) return", "if (false) return"],
    ["entry item destination", "if (!destinations.has(destination)) return", "if (false) return"],
    ["entry link target", "({ kind, name, destination, to: live + \"/\" + destination })", "({ kind, name, destination, to: destination })"],
    ["unwiring whole line", 'text.split("\\n").filter(existing => existing !== line)', 'text.split("\\n").map(existing => existing.split(line).join(""))'],
    ["unwiring every line", 'text.split("\\n").filter(existing => existing !== line)', 'text.split("\\n").filter((existing, at, all) => at !== all.indexOf(line))'],
    ["unwiring null when unchanged", "return next === text ? null : next;", "return next;"],
    ["unwiring in its section", "const at = section === undefined ? -1 : sectionAt(lines, section);", "const at = -1;"],
    ["unwiring the section's own lines", "end = at === -1 ? 0 : sectionEnd(lines, at)", "end = at === -1 ? 0 : lines.length"],
    ["unwiring its key only", "assignedKey(lines[index]) !== key) continue;", "false) continue;"],
    ["unwiring every copy", "array !== null; array = stringArray(lines[index])) {", "array !== null; array = null) {"],
    ["unwiring the separator after", "[array.elements[k].start, array.elements[k + 1].start]", "[array.elements[k].start, array.elements[k].end]"],
    ["unwiring the separator before the last", "[array.elements[k - 1].end, array.elements[k].end]", "[array.elements[k].start, array.elements[k].end]"],
    ["unwiring a sole string to the bracket", "[array.elements[0].start, array.close]", "[array.elements[0].start, array.elements[0].end]"]
];

const source = fs.readFileSync(rendererFile, "utf8");
const temp = fs.mkdtempSync(path.join(os.tmpdir(), "theme-render-control-"));
try {
    CONTROLS.forEach(([label, needle, replacement, surface = verify], index) => {
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        // One file per control: require caches a module by its path.
        const mutant = path.join(temp, `theme-render-${index}.js`);
        fs.writeFileSync(mutant, source.replace(needle, () => replacement));
        let failed = false;
        try {
            surface(require(mutant));
        } catch (e) {
            failed = true;
        }
        assert.ok(failed, `control "${label}": the suite passed on a renderer without that rule`);
    });
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}
console.log(`test-theme-render: ok targets=${ACCEPTED_TARGETS.length + REFUSED_TARGETS.length} templates=${ENCODED.length + GNOME_ACCENTED.length + RENDERED.length + MODES.length + REFUSED_TEMPLATES.length} wiring=${WIRED.length + WIRED_SECTION.length + CONFLICTS.length + CONFLICT_LINES.length + UNWIRED.length + UNWIRED_SECTION.length + PROFILES.length + VAULTS.length} controls=${CONTROLS.length}`);
