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
// a later plugin's pads as a comment (docs/architecture/hyprland.md), and
// every `tui` script a regular
// file with its owner's execute bit, reached through no symbolic link, since
// bin/vgshell-scan follows links and would publish whatever one points at.
// A bar widget that offers `layout` keeps the settings order bar widgets
// share: every field grouped, `layout` first in group "Readings", and the
// Readings fields starting with the shared ones it offers in
// READINGS_ORDER, so like widgets show their Settings pages in one order.
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

let refused = 0;
const seen = {};
const defaultKeys = {};
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
    const orderDefect = readingsOrderDefect(r.manifest);
    if (orderDefect !== "") {
        console.log("refused  " + dir + ": settings order " + orderDefect);
        refused += 1;
        missing = true;
    }
    if (missing) continue;
    console.log("ok       " + r.manifest.id + " " + r.manifest.version + " kinds=" + r.manifest.kinds.join(","));
}
if (refused > 0) { console.log("check-manifests: refused=" + refused); process.exit(1); }
console.log("check-manifests: ok");
