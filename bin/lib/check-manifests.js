#!/usr/bin/env node
// Validate plugin manifests offline through the shell's own judge,
// shell/Core/PluginLogic.js, loaded through bin/lib/qml-library.js.
//
//   check-manifests.js [--base DIR] [--] [PLUGIN_DIR...]
//
// With no plugin directories it checks every plugin under the base
// (default shell/plugins), listed the way the shell lists them: by
// bin/vgshell-scan, so a directory with no manifest.json is not a plugin and a
// directory the scan cannot read ends the run. With plugin directories it
// checks those. Beside the judge's verdict it reads the files a manifest
// names: every entry point must be a file, every first-party default key must
// be unique across the checked manifests, at most one of them declares
// `hyprland.pads`, since the Hyprland layer holds one pads table and writes
// a later plugin's pads as a comment (docs/architecture/hyprland.md), each
// former id in `formerIds` has one claimant and is no checked plugin's id,
// since the shell renames a user file by bundled claims alone, the first in
// scan order, and leaves out a claim of a live id (PluginLogic.formerIdClaims,
// D108), so a second claimant would lose its settings and a live id's
// claimant its rename, and every `tui` script a regular
// file with its owner's execute bit, reached through no symbolic link, since
// bin/vgshell-scan follows links and would publish whatever one points at.
// A `setupGuide` names the anchor of a heading of the plugin's README.md,
// which its Setup tab opens on GitHub; a heading renamed under it would
// open the README's top.
// A bar widget that offers `layout` keeps the settings order bar widgets
// share: every field grouped, `layout` first in group "Readings", and the
// Readings fields starting with the shared ones it offers in
// READINGS_ORDER, so like widgets show their Settings pages in one order.
// A schema entry's `description` and a status entry's `hint` say something
// its label does not (docs/architecture/design-system.md § Copy): a hint
// whose every word, bar the small words of a sentence, stands in its label
// is refused.
// No status entry the plugin page draws on Details offers an action
// (PluginLogic.detailSteps): a step stands on Setup
// (docs/architecture/design-system.md § Settings pages). A plugin in
// DETAIL_STEPS_HELD keeps its Details steps until the issue named beside it
// moves them.
// Prints one line per plugin. Exit 0 when every manifest is
// valid, 1 when any is refused, 2 when a directory or file cannot be read or
// the invocation is bad, each as one keyed line:
//   check-manifests: unreadable: <path>: <cause>
//   check-manifests: refused: option=<argument>
"use strict";
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const repo = path.join(__dirname, "..", "..");
const ctx = require(path.join(__dirname, "qml-library.js")).load(path.join(repo, "shell", "Core", "PluginLogic.js"));

function unreadable(where, cause) {
    console.log("check-manifests: unreadable: " + where + ": " + cause);
    process.exit(2);
}

// Options end at the first `--`; every later argument is a plugin directory.
let base = path.join(repo, "shell", "plugins");
const argv = process.argv.slice(2);
const dirs = [];
let optionsDone = false;
for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (optionsDone || !arg.startsWith("-")) { dirs.push(arg); continue; }
    if (arg === "--") { optionsDone = true; continue; }
    if (arg === "--base" && i + 1 < argv.length) { base = path.resolve(argv[++i]); continue; }
    console.log("check-manifests: refused: option=" + arg);
    process.exit(2);
}

// [{ dir, text }] for every plugin to check: the scan's listing of the base,
// or the manifest of each named directory read here.
function manifests() {
    if (dirs.length > 0) {
        return dirs.map(dir => {
            const file = path.join(dir, "manifest.json");
            try {
                return { dir: dir, text: fs.readFileSync(file, "utf8") };
            } catch (e) {
                return unreadable(file, e.code);
            }
        });
    }
    const scan = spawnSync(path.join(repo, "bin", "vgshell-scan"), ["--require-base", base], { encoding: "utf8", env: { PATH: process.env.PATH, LC_ALL: "C" } });
    if (scan.status !== 0) return unreadable(base, "vgshell-scan exited " + scan.status);
    const entries = JSON.parse(scan.stdout);
    for (const entry of entries)
        if (entry.error !== undefined) unreadable(entry.dir, entry.error);
    return entries;
}

// Why SCRIPT, a `tui` script path the judge accepted, cannot run from the
// plugin at DIR, or "": `missing`, `is a symbolic link or lies under one`,
// `is not a regular file` or `is not executable`. A file that cannot be
// read ends the run.
function scriptDefect(dir, script) {
    const file = path.join(dir, script);
    let stat, real;
    try {
        stat = fs.lstatSync(file);
        real = fs.realpathSync(file);
    } catch (e) {
        if (e.code === "ENOENT") return "missing";
        return unreadable(file, e.code);
    }
    let base;
    try {
        base = fs.realpathSync(dir);
    } catch (e) {
        return unreadable(dir, e.code);
    }
    if (stat.isSymbolicLink() || real !== path.join(base, script)) return "is a symbolic link or lies under one";
    if (!stat.isFile()) return "is not a regular file";
    if ((stat.mode & 0o100) === 0) return "is not executable";
    return "";
}

// The anchors GitHub gives the headings of the Markdown TEXT: each heading
// in lower case with every character but a letter, a digit, a space, a
// dash and an underscore dropped and each space a dash. A heading inside a
// fenced code block is no heading.
function headingAnchors(text) {
    const anchors = [];
    let fenced = false;
    for (const line of text.split("\n")) {
        if (/^\s*(```|~~~)/.test(line)) fenced = !fenced;
        const heading = fenced ? null : /^#{1,6}\s+(.*?)\s*#*\s*$/.exec(line);
        if (heading !== null) anchors.push(heading[1].toLowerCase().replace(/[^\p{L}\p{N} _-]/gu, "").replace(/ /g, "-"));
    }
    return anchors;
}

// Why the plugin at DIR cannot open the README section its `setupGuide`
// names, or "": its README.md is missing or holds no heading of that
// anchor. A README that cannot be read otherwise ends the run.
function guideDefect(dir, guide) {
    const file = path.join(dir, "README.md");
    let text;
    try {
        text = fs.readFileSync(file, "utf8");
    } catch (e) {
        if (e.code === "ENOENT") return "README.md is missing";
        return unreadable(file, e.code);
    }
    return headingAnchors(text).indexOf(guide.readme) === -1 ? "README.md has no heading #" + guide.readme : "";
}

// The shared Readings fields of a bar widget, in their Settings order.
const READINGS_ORDER = ["layout", "labelStyle", "refreshSeconds"];

// Why a manifest breaks the bar widget settings order, as
// "schema.KEY: cause", or "". The Settings page draws ungrouped fields
// before every group and each group where its first field appears in the
// schema (shell/plugins/vgs.settings/PluginPage.qml `sections`), so the
// schema's key order is the page's.
function readingsOrderDefect(manifest) {
    const schema = manifest.schema;
    if (manifest.kinds.indexOf("bar-widget") === -1 || !Object.prototype.hasOwnProperty.call(schema, "layout")) return "";
    const keys = Object.keys(schema).filter(key => schema[key].type !== "list");
    const ungrouped = keys.find(key => schema[key].group === undefined);
    if (ungrouped !== undefined) return "schema." + ungrouped + ": has no group, and a bar widget with layout groups every field";
    if (keys[0] !== "layout") return "schema." + keys[0] + ": comes before schema.layout";
    const readings = keys.filter(key => schema[key].group === "Readings");
    const shared = READINGS_ORDER.filter(key => Object.prototype.hasOwnProperty.call(schema, key));
    for (let i = 0; i < shared.length; i++)
        if (readings[i] !== shared[i]) return "schema." + shared[i] + ": must be Readings field " + (i + 1) + " (" + shared.join(", ") + ")";
    return "";
}

// The words that carry no meaning of their own in a hint.
const SMALL_WORDS = new Set(["a", "an", "the", "to", "of", "in", "on", "at", "for", "and", "or", "your", "you", "it", "its", "is", "are", "be", "this", "that", "with", "as", "by", "from", "when", "while", "if", "so"]);

// The words of TEXT that carry meaning, lower case with a plural s dropped.
function meaningWords(text) {
    return (text.toLowerCase().match(/[\p{L}\p{N}]+/gu) || []).filter(word => !SMALL_WORDS.has(word)).map(word => word.replace(/s$/, ""));
}

// The refusal for a manifest's hints that restate their labels, as
// "schema.KEY.description: cause", or "".
function restatedHint(manifest) {
    const entries = [["schema", "description", manifest.schema], ["status", "hint", manifest.status]];
    for (const [table, field, declared] of entries) {
        for (const key of Object.keys(declared)) {
            const entry = declared[key];
            if (typeof entry.label !== "string" || typeof entry[field] !== "string") continue;
            const hint = meaningWords(entry[field]);
            const label = meaningWords(entry.label);
            if (hint.length > 0 && hint.every(word => label.indexOf(word) !== -1))
                return table + "." + key + "." + field + ": repeats its label; keep a hint only where the user cannot act without it";
        }
    }
    return "";
}

// The plugins whose Details steps their own lanes move, by the issue that
// removes each from this list once it has. VGS-1958 moves Power's once
// VGS-1905 lands and VPN's once VGS-1928 lands.
const DETAIL_STEPS_HELD = {
    "vgs.jarvis": "VGS-1953",
    "vgs.power": "VGS-1958",
    "vgs.vpn": "VGS-1958"
};

let refused = 0;
const seen = {};
const defaultKeys = {};
const formerClaims = {};
let padsOwner = null;
for (const { dir, text } of manifests()) {
    let raw;
    try {
        raw = JSON.parse(text);
    } catch (e) {
        console.log("refused  " + dir + ": manifest does not parse: " + e.message);
        refused += 1;
        continue;
    }
    const r = ctx.validateManifest(raw, dir);
    if (!r.ok) { console.log("refused  " + dir + ": " + r.error); refused += 1; continue; }
    if (seen[r.manifest.id]) { console.log("refused  " + dir + ": id " + r.manifest.id + " already used by " + seen[r.manifest.id]); refused += 1; continue; }
    seen[r.manifest.id] = dir;
    let missing = false;
    // Either order of a former id and a live id refuses the later manifest.
    if (formerClaims[r.manifest.id] !== undefined) {
        console.log("refused  " + dir + ": id " + r.manifest.id + " is a former id of " + formerClaims[r.manifest.id]);
        refused += 1;
        missing = true;
    }
    for (const former of (r.manifest.formerIds === undefined ? [] : r.manifest.formerIds)) {
        if (formerClaims[former] !== undefined) {
            console.log("refused  " + dir + ": former id " + former + " of " + r.manifest.id + " already claimed by " + formerClaims[former]);
            refused += 1;
            missing = true;
        } else if (seen[former] !== undefined) {
            console.log("refused  " + dir + ": former id " + former + " of " + r.manifest.id + " is the id of " + seen[former]);
            refused += 1;
            missing = true;
        }
        if (formerClaims[former] === undefined) formerClaims[former] = r.manifest.id;
    }
    for (const bind of (r.manifest.hyprland === undefined ? [] : r.manifest.hyprland.binds)) {
        if (bind.key === null) continue;
        const owner = r.manifest.id + ":" + bind.shortcut;
        for (const key of ctx.keyValues(bind.key)) {
            const prior = defaultKeys[key];
            if (prior !== undefined) {
                console.log("refused  " + dir + ": default key " + key + " for " + owner + " already used by " + prior);
                refused += 1;
                missing = true;
                continue;
            }
            defaultKeys[key] = owner;
        }
    }
    if (r.manifest.hyprland !== undefined && r.manifest.hyprland.pads !== undefined) {
        if (padsOwner !== null) {
            console.log("refused  " + dir + ": hyprland.pads of " + r.manifest.id + " already declared by " + padsOwner);
            refused += 1;
            missing = true;
        } else {
            padsOwner = r.manifest.id;
        }
    }
    for (const kind of r.manifest.kinds) {
        const entry = path.join(dir, r.manifest.entryPoints[kind]);
        try {
            if (!fs.statSync(entry).isFile()) {
                console.log("refused  " + dir + ": entry point for " + kind + " not a file: " + entry);
                refused += 1;
                missing = true;
            }
        } catch (e) {
            if (e.code !== "ENOENT") unreadable(entry, e.code);
            console.log("refused  " + dir + ": entry point for " + kind + " missing: " + entry);
            refused += 1;
            missing = true;
        }
    }
    for (const name of Object.keys(r.manifest.tui)) {
        const defect = scriptDefect(dir, r.manifest.tui[name].script);
        if (defect === "") continue;
        console.log("refused  " + dir + ": tui." + name + ".script " + r.manifest.tui[name].script + " " + defect);
        refused += 1;
        missing = true;
    }
    const guide = r.manifest.setupGuide === undefined ? "" : guideDefect(dir, r.manifest.setupGuide);
    if (guide !== "") {
        console.log("refused  " + dir + ": setupGuide.readme " + guide);
        refused += 1;
        missing = true;
    }
    const orderDefect = readingsOrderDefect(r.manifest);
    if (orderDefect !== "") {
        console.log("refused  " + dir + ": settings order " + orderDefect);
        refused += 1;
        missing = true;
    }
    const restated = restatedHint(r.manifest);
    if (restated !== "") {
        console.log("refused  " + dir + ": hint " + restated);
        refused += 1;
        missing = true;
    }
    const detailSteps = ctx.detailSteps(r.manifest);
    if (detailSteps.length > 0 && DETAIL_STEPS_HELD[r.manifest.id] === undefined) {
        console.log("refused  " + dir + ": status." + detailSteps[0] + " offers an action on Details; a step stands on Setup (setup true or \"optional\")");
        refused += 1;
        missing = true;
    }
    if (missing) continue;
    console.log("ok       " + r.manifest.id + " " + r.manifest.version + " kinds=" + r.manifest.kinds.join(","));
}
if (refused > 0) { console.log("check-manifests: refused=" + refused); process.exit(1); }
console.log("check-manifests: ok");
