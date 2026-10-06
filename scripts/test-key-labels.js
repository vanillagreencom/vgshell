#!/usr/bin/env node
// Every Keys row a shipped plugin draws shows its whole label. The rows are
// the binds each shell/plugins/*/manifest.json declares, each labelled with
// the description its Service.qml registers and carrying the manifest's
// explanation, so the row draws the info icon beside the label. The script
// builds each row as the Settings page and Key Hints do, a BindField, in a
// generated QML test run by scripts/qml-unit.sh with the shell's bundled
// fonts, and reads each label's `truncated`. A label that wraps past two
// lines or elides fails the run and is named.
//
// A description is read from the register call that names the shortcut: a
// string literal, Capture's `descriptions[name]` map in the same file, or
// the Themes views' `view.description` from BrowserLogic.VIEWS. A register
// call of any other form, or a manifest bind no call describes, fails the
// extractor, so a new form cannot drop rows unseen.
//
// The control plants one description long enough to elide and requires
// the generated test to fail on it.
//
// Exit 0 when every label fits and the control fails, 1 otherwise, 77 when
// scripts/qml-unit.sh could not run.
"use strict";
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const vm = require("node:vm");
const { spawnSync } = require("node:child_process");
const { load } = require("../bin/lib/qml-library.js");

const repo = path.join(__dirname, "..");
const plugins = path.join(repo, "shell", "plugins");
const REGISTER = /shell\.shortcut\.register\(\s*([^,]+?)\s*,\s*([^,]+?)\s*,/g;
const PLANTED = "Open or close the notification inbox and every earlier message it holds";

function fail(message) {
    console.error("test-key-labels: " + message);
    process.exit(1);
}

// The descriptions SOURCE registers, shortcut name -> text.
function registered(id, source) {
    const out = {};
    const views = () => {
        const keyNav = load(path.join(repo, "shell", "Ui", "foundation", "KeyNavLogic.js"));
        return load(path.join(plugins, "vgs.themes", "BrowserLogic.js"), { "qs.Ui 1.0": { KeyNavLogic: keyNav } }).VIEWS;
    };
    const named = () => {
        const block = source.match(/property var descriptions: (\(\{[\s\S]*?\}\))/);
        if (block === null) fail("extractor: " + id + " registers descriptions[name] with no descriptions map");
        return vm.runInNewContext(block[1]);
    };
    for (const call of source.matchAll(REGISTER)) {
        const [, name, description] = call;
        if (/^"[a-z0-9-]+"$/.test(name) && /^"[^"]*"$/.test(description)) out[JSON.parse(name)] = JSON.parse(description);
        else if (name === "name" && description === "descriptions[name]") Object.assign(out, named());
        else if (name === "view.name" && description === "view.description") for (const view of views()) out[view.name] = view.description;
        else if (name.startsWith('"pad-"')) continue;
        else fail("extractor: " + id + " registers an unknown form: " + call[0]);
    }
    return out;
}

function rows() {
    const out = [];
    for (const dir of fs.readdirSync(plugins).sort()) {
        const manifestPath = path.join(plugins, dir, "manifest.json");
        if (!fs.existsSync(manifestPath)) continue;
        const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
        const binds = manifest.hyprland === undefined || manifest.hyprland.binds === undefined ? [] : manifest.hyprland.binds;
        if (binds.length === 0) continue;
        const servicePath = path.join(plugins, dir, "Service.qml");
        const descriptions = registered(manifest.id, fs.existsSync(servicePath) ? fs.readFileSync(servicePath, "utf8") : "");
        for (const bind of binds) {
            if (!Object.prototype.hasOwnProperty.call(descriptions, bind.shortcut))
                fail("extractor: no register call describes " + manifest.id + ":" + bind.shortcut);
            out.push({ id: manifest.id, shortcut: bind.shortcut, label: descriptions[bind.shortcut], info: bind.info || "" });
        }
    }
    // A broken extractor finds none; the shipped set has a dozen plugins with binds.
    if (out.length < 12) fail("extractor: rows=" + out.length + " floor=12");
    return out;
}

function testSource(list) {
    return `import QtQuick
import QtTest
import qs.Ui

Item {
    id: root
    width: 720
    height: 200
    readonly property var rows: ${JSON.stringify(list)}

    Component { id: rowComponent; BindField { width: 640 } }

    TestCase {
        name: "keylabels"
        when: windowShown

        function descendants(item) {
            const found = [item];
            for (let i = 0; i < found.length; i++)
                for (const child of found[i].children || []) found.push(child);
            return found;
        }

        function test_every_keys_label_shows_whole() {
            const cut = [];
            for (const row of root.rows) {
                const field = createTemporaryObject(rowComponent, root, { bind: { shortcut: row.shortcut, key: null, default: null, description: row.label, info: row.info } });
                const labels = descendants(field).filter(child => child instanceof Text && child.visible && child.text === row.label);
                compare(labels.length, 1, row.id + ":" + row.shortcut + " draws its label once");
                if (labels[0].truncated) cut.push(row.id + ":" + row.shortcut + " " + JSON.stringify(row.label));
            }
            compare(JSON.stringify(cut), "[]", "every Keys label shows whole");
        }
    }
}
`;
}

// Run the generated test over LIST; the runner's exit status.
function run(list) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vgs-key-labels-"));
    try {
        fs.cpSync(path.join(repo, "scripts", "qml-tests", "stand-ins"), path.join(dir, "stand-ins"), { recursive: true });
        const test = path.join(dir, "tst_keylabels.qml");
        fs.writeFileSync(test, testSource(list));
        const env = {};
        for (const name of ["PATH", "HOME", "TMPDIR", "XDG_RUNTIME_DIR", "LANG", "LC_ALL"])
            if (process.env[name] !== undefined) env[name] = process.env[name];
        const result = spawnSync(path.join(repo, "scripts", "qml-unit.sh"), ["--tests", dir, test], { env, encoding: "utf8" });
        process.stdout.write(result.stdout);
        process.stderr.write(result.stderr);
        if (result.error) fail("qml-unit: " + result.error.message);
        return result.status;
    } finally {
        fs.rmSync(dir, { recursive: true, force: true });
    }
}

const list = rows();
console.log("test-key-labels: rows=" + list.length);
const shipped = run(list);
if (shipped === 77) process.exit(77);
if (shipped !== 0) fail("shipped labels status=" + shipped);
console.log("  ok    every shipped Keys label shows whole");
const planted = list.slice();
planted[0] = Object.assign({}, planted[0], { label: PLANTED });
const control = run(planted);
if (control === 77) process.exit(77);
if (control !== 1) fail("control: a planted long label status=" + control + " want=1");
console.log("  ok    control: a planted long label fails the check");
console.log("test-key-labels: ok");
