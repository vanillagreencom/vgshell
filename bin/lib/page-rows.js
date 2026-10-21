#!/usr/bin/env node
// The rows each tab of a plugin's Settings page draws, which a page
// reference `page:<plugin id>/<tab>/<key>` can open, as the page's own
// judges place them: Settings its schema fields, Setup the status entries
// Steps.declaresStep takes as steps, and Details those Steps.detailEntries
// draws, of PluginLogic.statusRows over the manifest with nothing
// published. scripts/check-user-commands.py reads it, so a placement rule
// lives in those judges alone.
//
// Usage: node bin/lib/page-rows.js PLUGINS_DIR
// stdout: one JSON object, { "<plugin directory>": { "Settings": [keys],
// "Setup": [keys], "Details": [keys] } }, for each directory of PLUGINS_DIR
// that holds a manifest.json. The manifest is read as written, not judged:
// check-manifests refuses a manifest that does not validate, and a
// reference into it is still judged by what it declares.
// A refusal is one keyed line on stderr and exit 2:
//   page-rows: refused: arguments
//   page-rows: refused: unreadable path=<file> error=<cause>
"use strict";
const fs = require("fs");
const path = require("path");
const { load } = require("./qml-library.js");

const repo = path.join(__dirname, "..", "..");
const logic = load(path.join(repo, "shell", "Core", "PluginLogic.js"));
const steps = load(path.join(repo, "shell", "plugins", "vgs.settings", "Steps.js"));

function refuse(line) {
    process.stderr.write("page-rows: refused: " + line + "\n");
    process.exit(2);
}

const isObject = value => value !== null && typeof value === "object" && !Array.isArray(value);

function rows(file) {
    let raw;
    try { raw = JSON.parse(fs.readFileSync(file, "utf8")); }
    catch (error) { refuse("unreadable path=" + file + " error=" + (error.code || error.message.split("\n")[0])); }
    if (!isObject(raw)) return { Settings: [], Setup: [], Details: [] };
    const status = logic.statusRows({ status: isObject(raw.status) ? raw.status : {}, secrets: raw.secrets }, {});
    return {
        Settings: isObject(raw.schema) ? Object.keys(raw.schema) : [],
        Setup: status.filter(steps.declaresStep).map(entry => entry.key),
        Details: steps.detailEntries(status).map(entry => entry.key)
    };
}

if (process.argv.length !== 3) refuse("arguments");
const base = process.argv[2];
let names;
try { names = fs.readdirSync(base); }
catch (error) { refuse("unreadable path=" + base + " error=" + (error.code || error.message)); }
const out = {};
for (const name of names.sort()) {
    const file = path.join(base, name, "manifest.json");
    if (fs.existsSync(file)) out[name] = rows(file);
}
process.stdout.write(JSON.stringify(out) + "\n");
