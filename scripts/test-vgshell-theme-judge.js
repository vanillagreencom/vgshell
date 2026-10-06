#!/usr/bin/env node
// Controls for bin/vgshell-theme-judge: the shipped-package walk accepts a valid
// package set, rejects a package whose document name does not match its
// directory, rejects a malformed terminal slot through ThemeLogic.acceptPackage,
// and fails closed when the package root cannot be listed. The target walk
// renders every target under targets/ against the vgs package, refuses a bad
// target.json or placeholder, and fails closed on an unreadable template or
// a missing vgs package. The catalog check judges the index and every
// package it names, refuses a curated file on a target whose files run
// code, one no target writes, one apply would not take and any symlink,
// and requires the thumbnail;
// the package walk skips the catalog. Its controls at the end edit a copy
// of the judge, one rule at a time, and require the catalog rows to fail on
// each copy. Test directories live under repo tmp so the suite does not
// depend on the host temporary directory.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const repo = path.join(__dirname, "..");
const CHECK = path.join(repo, "bin", "vgshell-theme-judge");
const ENV = { PATH: process.env.PATH, LC_ALL: "C", TMPDIR: path.join(repo, "tmp") };
const slots = Object.fromEntries(Array.from({ length: 16 }, (_, index) => [`color${index}`, "#000000"]));

function writePackage(base, name, themeName, terminalSlots = slots) {
    const dir = path.join(base, name);
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, "theme.json"), JSON.stringify({ schemaVersion: 1, name: themeName, tokens: {} }));
    if (terminalSlots !== null)
        fs.writeFileSync(path.join(dir, "terminal.json"), JSON.stringify({ schemaVersion: 1, slots: terminalSlots }));
}

const target = { app: "Probe", runsCode: false, encoder: "hex6", files: [{ template: "probe.conf", destination: "probe.conf" }], detect: ["probe"], wiring: { file: "probe/probe.conf", line: "include=@{state}/probe.conf", create: true }, reload: null };

function writeTarget(base, name, document, templates) {
    const dir = path.join(base, "targets", name);
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, "target.json"), JSON.stringify(document));
    for (const [file, text] of Object.entries(templates)) fs.writeFileSync(path.join(dir, file), text);
    return dir;
}

function run(base) {
    return spawnSync(process.execPath, [CHECK, "packages", base], { encoding: "utf8", env: ENV });
}

// --- catalog-check

// One palette the fixture packages set and their index entries state.
const PALETTE = Object.fromEntries(["background", "foreground", "accent", "success", "warning", "danger", "info"].map(name => [name, "#101010"]));
const catalogEntry = name => ({ name, mode: "dark", thumbnail: name + "/thumbnail.jpg", palette: PALETTE, imagery: null });
const catalogTheme = (name, palette = PALETTE) => JSON.stringify({ schemaVersion: 1, name, tokens: { scheme: { mode: "dark" }, palette } });

// A themes directory at BASE holding a target that runs no code (`plain`),
// one that does (`code`), one that takes a curated file only as a JSON
// object with a `colors` key (`keyed`), and a catalog whose index lists
// `probe`, a valid package with a thumbnail and a curated file for `plain`
// and for `keyed`.
function writeCatalog(base) {
    writeTarget(base, "plain", Object.assign({}, target, { app: "Plain", files: [{ template: "plain.conf", destination: "plain.conf" }] }), { "plain.conf": "" });
    writeTarget(base, "code", Object.assign({}, target, { app: "Code", runsCode: true, files: [{ template: "code.conf", destination: "code.conf" }] }), { "code.conf": "" });
    writeTarget(base, "keyed", Object.assign({}, target, { app: "Keyed", files: [{ template: "keyed.json", destination: "keyed.json", curatedKeys: ["colors"] }] }), { "keyed.json": "{}" });
    const dir = path.join(base, "catalog", "probe");
    fs.mkdirSync(path.join(dir, "targets"), { recursive: true });
    fs.writeFileSync(path.join(base, "catalog", "index.json"), JSON.stringify({ schemaVersion: 1, entries: [catalogEntry("probe")] }));
    fs.writeFileSync(path.join(dir, "theme.json"), catalogTheme("probe"));
    fs.writeFileSync(path.join(dir, "terminal.json"), JSON.stringify({ schemaVersion: 1, slots }));
    fs.writeFileSync(path.join(dir, "preview.jpg"), "preview");
    fs.writeFileSync(path.join(dir, "thumbnail.jpg"), "jpeg");
    fs.writeFileSync(path.join(dir, "targets", "plain.conf"), "curated");
    fs.writeFileSync(path.join(dir, "targets", "keyed.json"), JSON.stringify({ colors: {} }));
    return dir;
}

// Every catalog row against the judge at CHECK, with fixtures under ROOT.
// Each refused row plants one defect in a copy of the valid catalog.
function catalogRows(check, root) {
    const judge = (...args) => spawnSync(process.execPath, [check, ...args], { encoding: "utf8", env: ENV });
    let proc = judge("catalog-check");
    assert.equal(proc.status, 0, "shipped catalog: " + proc.stdout + proc.stderr);
    assert.match(proc.stdout, /^ok       catalog\/nord$/m, "shipped catalog");

    let base = path.join(root, "good");
    writeCatalog(base);
    proc = judge("catalog-check", base);
    assert.equal(proc.status, 0, "good: " + proc.stdout + proc.stderr);
    assert.equal(proc.stdout, "ok       catalog/probe\nvgshell-theme-judge: ok\n", "good");

    // [label, the defect planted in the probe directory DIR, the refusal]
    const refused = [
        ["curated code", dir => fs.writeFileSync(path.join(dir, "targets", "code.conf"), "os.execute()"), "reason=curated-code file=targets/code.conf target=code"],
        ["curated shape", dir => fs.writeFileSync(path.join(dir, "targets", "keyed.json"), JSON.stringify({ extension: "probe" })), "reason=curated-shape file=targets/keyed.json target=keyed"],
        ["curated unknown", dir => fs.writeFileSync(path.join(dir, "targets", "other.conf"), ""), "reason=curated-unknown file=targets/other.conf"],
        ["curated directory", dir => fs.mkdirSync(path.join(dir, "targets", "plain.d")), "reason=curated-file file=targets/plain.d"],
        ["curated symlink", dir => { fs.rmSync(path.join(dir, "targets", "plain.conf")); fs.symlinkSync("../theme.json", path.join(dir, "targets", "plain.conf")); }, "reason=symlink file=targets/plain.conf"],
        ["targets symlink", dir => { fs.renameSync(path.join(dir, "targets"), path.join(dir, "real")); fs.symlinkSync("real", path.join(dir, "targets")); }, "reason=symlink file=targets"],
        ["thumbnail absent", dir => fs.rmSync(path.join(dir, "thumbnail.jpg")), "reason=absent file=probe/thumbnail.jpg"],
        ["thumbnail symlink", dir => { fs.rmSync(path.join(dir, "thumbnail.jpg")); fs.symlinkSync("theme.json", path.join(dir, "thumbnail.jpg")); }, "reason=symlink file=probe/thumbnail.jpg"],
        ["entry absent", dir => fs.rmSync(dir, { recursive: true }), "reason=absent file=probe"],
        ["entry symlink", dir => { fs.renameSync(dir, dir + ".real"); fs.symlinkSync("probe.real", dir); }, "reason=symlink file=probe"],
        ["theme absent", dir => fs.rmSync(path.join(dir, "theme.json")), "reason=absent file=probe/theme.json"],
        ["theme symlink", dir => { fs.renameSync(path.join(dir, "theme.json"), path.join(dir, "real.json")); fs.symlinkSync("real.json", path.join(dir, "theme.json")); }, "reason=symlink file=probe/theme.json"],
        ["name mismatch", dir => fs.writeFileSync(path.join(dir, "theme.json"), catalogTheme("other")), "reason=name-mismatch directory=probe document=other"],
        ["palette mismatch", dir => fs.writeFileSync(path.join(dir, "theme.json"), catalogTheme("probe", Object.assign({}, PALETTE, { accent: "#202020" }))), "token=palette.accent reason=catalog-palette-mismatch index=#101010ff package=#202020ff"]
    ];
    for (const [label, plant, want] of refused) {
        base = path.join(root, label.replace(/ /g, "-"));
        const dir = writeCatalog(base);
        plant(dir);
        proc = judge("catalog-check", base);
        assert.equal(proc.status, 1, label + ": " + proc.stdout + proc.stderr);
        const subject = want.startsWith("token=") ? "" : "document ";
        assert.equal(proc.stdout, `refused  ${dir}: theme: refused: ${subject}${want}\nvgshell-theme-judge: refused=1\n`, label);
    }

    base = path.join(root, "preview-symlink-accepted");
    {
        const dir = writeCatalog(base);
        fs.rmSync(path.join(dir, "preview.jpg"));
        fs.symlinkSync("theme.json", path.join(dir, "preview.jpg"));
        proc = judge("catalog-check", base);
        assert.equal(proc.status, 0, "preview symlink ignored: " + proc.stdout + proc.stderr);
    }

    base = path.join(root, "index-refused");
    writeCatalog(base);
    const indexFile = path.join(base, "catalog", "index.json");
    fs.writeFileSync(indexFile, JSON.stringify({ schemaVersion: 1, entries: [catalogEntry("vgs")] }));
    proc = judge("catalog-check", base);
    assert.equal(proc.status, 1, "index refused: " + proc.stdout + proc.stderr);
    assert.equal(proc.stdout, `refused  ${indexFile}: theme: refused: token=entries.0.name reason=reserved-name name=vgs\nvgshell-theme-judge: refused=1\n`, "index refused");

    fs.rmSync(indexFile);
    proc = judge("catalog-check", base);
    assert.equal(proc.status, 2, "index absent: " + proc.stdout + proc.stderr);
    assert.equal(proc.stdout, `vgshell-theme-judge: unreadable: ${indexFile}: ENOENT\n`, "index absent");

    // A refused target leaves a curated file unclassified, so it refuses
    // the catalog while every entry passes.
    base = path.join(root, "target-refused");
    writeCatalog(base);
    const bad = writeTarget(base, "bad", Object.assign({}, target, { encoder: "hex" }), { "probe.conf": "" });
    proc = judge("catalog-check", base);
    assert.equal(proc.status, 1, "target refused: " + proc.stdout + proc.stderr);
    assert.equal(proc.stdout, `refused  ${bad}: target=bad reason=target-schema key=encoder\nok       catalog/probe\nvgshell-theme-judge: refused=1\n`, "target refused");

    // The package walk takes the catalog for no package.
    base = path.join(root, "packages");
    writePackage(base, "vgs", "vgs");
    writeCatalog(base);
    fs.rmSync(path.join(base, "targets"), { recursive: true });
    proc = judge("packages", base);
    assert.equal(proc.status, 0, "packages: " + proc.stdout + proc.stderr);
    assert.equal(proc.stdout, "ok       vgs\nvgshell-theme-judge: ok\n", "packages");
}

// A copy of the judge with NEEDLE, which must occur once, replaced by
// REPLACEMENT, in a tree at DIR whose other directories link to this
// repository's; answers the copy's path.
function judgeCopy(dir, needle, replacement) {
    const source = fs.readFileSync(CHECK, "utf8");
    assert.equal(source.split(needle).length, 2, `control needle must occur once: ${needle}`);
    fs.mkdirSync(path.join(dir, "bin"), { recursive: true });
    for (const link of ["bin/lib", "scripts", "shell", "themes"]) fs.symlinkSync(path.join(repo, link), path.join(dir, link));
    const copy = path.join(dir, "bin", "vgshell-theme-judge");
    fs.writeFileSync(copy, source.replace(needle, () => replacement));
    return copy;
}

// Each control removes one catalog-check rule from a copy of the judge and
// keeps the text around it.
const CATALOG_CONTROLS = [
    ["curated code", "if (target.runsCode) return", "if (false) return"],
    ["curated unknown", "if (target === undefined) return", "if (false) return"],
    ["curated shape", "if (!render.curatedTaken(logic, target.file, fs.readFileSync(path.join(base, entry.name)))) return", "if (false) return"],
    ["curated file kind", "if (!entry.isFile()) return", "if (false) return"],
    ["curated symlink", "if (entry.isSymbolicLink()) return", "if (false) return"],
    ["targets symlink", 'if (stat.isSymbolicLink()) return logic.refusal("symlink", "", "file=" + TARGETS);', ""],
    ["thumbnail absent", 'if (thumbnail.state === "absent") return', "if (false) return"],
    ["thumbnail symlink", 'if (thumbnail.state === "linked") return', "if (false) return"],
    ["entry absent", 'if (stat === undefined) return logic.refusal("absent", "", "file=" + entry.name);', ""],
    ["entry symlink", 'if (stat.isSymbolicLink()) return logic.refusal("symlink", "", "file=" + entry.name);', ""],
    ["theme absent", "if (read.files.theme === undefined) return logic.refusal(", "if (false) return logic.refusal("],
    ["package symlink", 'if (read.linked !== null) return logic.refusal("symlink", "", "file=" + entry.name + "/" + read.linked);', ""],
    ["package judged", "const verdict = logic.acceptCatalogEntry(tokens, entry, { themeJson: text(read.files.theme), terminalJson: text(read.files.terminal) });", "const verdict = { ok: true };"],
    ["index refusal", "if (!index.ok) {", "if (false) {"],
    ["refused target counted", "let refused = targetsRefused;", "let refused = 0;"],
    ["catalog skipped by packages", "names.filter(name => !logic.RESERVED_DIRECTORIES.includes(name))", "names.filter(name => name !== TARGETS)"]
];

// Observe actual package reads and module loads in a disposable process.
// Applying one package must not parse unrelated packages or initialize
// the downloader. The list command still judges the full package set.
function applyRows(root, mutation) {
    const tree = path.join(root, "tree");
    fs.mkdirSync(path.join(tree, "bin"), { recursive: true });
    for (const link of ["bin/lib", "shell", "config"]) fs.symlinkSync(path.join(repo, link), path.join(tree, link));
    let source = fs.readFileSync(CHECK, "utf8");
    if (mutation !== undefined) {
        const [needle, replacement] = mutation;
        assert.equal(source.split(needle).length, 2, "apply control must match once");
        source = source.replace(needle, () => replacement);
    }
    const check = path.join(tree, "bin", "vgshell-theme-judge");
    fs.writeFileSync(check, source);
    const config = path.join(root, "config", "vgshell");
    const state = path.join(root, "state");
    const shipped = path.join(tree, "themes");
    const installed = path.join(config, "themes");
    writePackage(shipped, "vgs", "vgs");
    writePackage(shipped, "probe", "probe", null);
    writePackage(shipped, "unrelated", "wrong-name");
    writePackage(installed, "broken", "wrong-name");
    const trace = path.join(root, "trace.jsonl");
    const preload = path.join(root, "observe.js");
    fs.writeFileSync(preload, `
const fs = require('node:fs');
const Module = require('node:module');
const read = fs.readFileSync;
const load = Module._load;
const log = row => fs.appendFileSync(${JSON.stringify(trace)}, JSON.stringify(row) + '\\n');
fs.readFileSync = function(file, ...args) { log(['read', String(file)]); return read.call(this, file, ...args); };
Module._load = function(file, ...args) { log(['module', file]); return load.call(this, file, ...args); };
`);
    const judge = (...args) => spawnSync(process.execPath, ["--require", preload, check, ...args], { encoding: "utf8", env: ENV });
    const apply = () => judge("apply", "json", config, state, "held", "probe");
    let proc = apply();
    assert.equal(proc.status, 0, proc.stdout + proc.stderr);
    assert.equal(JSON.parse(proc.stdout).state, "applied");
    assert.equal(fs.readFileSync(path.join(state, "theme", "terminal.json"), "utf8"), fs.readFileSync(path.join(shipped, "vgs", "terminal.json"), "utf8"), "selected theme uses shipped fallback slots");
    const observed = fs.readFileSync(trace, "utf8").trim().split("\n").map(line => JSON.parse(line));
    assert.ok(observed.some(([kind, file]) => kind === "read" && file === path.join(shipped, "probe", "theme.json")), "observer reached selected package");
    assert.ok(observed.some(([kind, file]) => kind === "read" && file === path.join(shipped, "vgs", "terminal.json")), "observer reached fallback package");
    assert.ok(!observed.some(([kind, file]) => kind === "read" && (file.startsWith(path.join(shipped, "unrelated") + path.sep) || file.startsWith(path.join(installed, "broken") + path.sep))), "apply read an unrelated package");
    assert.ok(!observed.some(([kind, file]) => kind === "module" && file.endsWith("theme-download.js")), "apply initialized the downloader");
    proc = judge("list", "json", config, state);
    assert.equal(proc.status, 0, proc.stdout + proc.stderr);
    assert.match(proc.stdout, /name-mismatch/, "list still judges unrelated packages");
    writePackage(installed, "vgs", "vgs", Object.assign({}, slots, { color0: "#ffffff" }));
    proc = apply();
    assert.equal(proc.status, 0, "reserved installed default: " + proc.stdout + proc.stderr);
    assert.equal(fs.readFileSync(path.join(state, "theme", "terminal.json"), "utf8"), fs.readFileSync(path.join(shipped, "vgs", "terminal.json"), "utf8"), "installed vgs cannot replace fallback");

    // Each malformed input reaches the selected-package or root check.
    const refused = [
        ["installed shadow", () => writePackage(installed, "probe", "wrong-name"), "name-mismatch"],
        ["selected invalid", () => { fs.rmSync(path.join(installed, "probe"), { recursive: true }); writePackage(shipped, "probe", "wrong-name"); }, "name-mismatch"],
        ["fallback invalid", () => { writePackage(shipped, "probe", "probe", null); fs.rmSync(path.join(shipped, "probe", "terminal.json")); writePackage(shipped, "vgs", "wrong-name"); }, "terminal-fallback"],
        ["shipped root absent", () => fs.rmSync(shipped, { recursive: true }), "unreadable"]
    ];
    for (const [label, plant, reason] of refused) {
        plant();
        proc = apply();
        assert.equal(proc.status, 1, label + ": " + proc.stdout + proc.stderr);
        assert.equal(JSON.parse(proc.stdout).reason, reason, label);
    }
}

fs.mkdirSync(path.join(repo, "tmp"), { recursive: true });
const root = fs.mkdtempSync(path.join(repo, "tmp", "test-vgshell-theme-judge+ space-"));
try {
    let base = path.join(root, "good");
    writePackage(base, "vgs", "vgs");
    let proc = run(base);
    assert.equal(proc.status, 0, proc.stdout + proc.stderr);
    assert.match(proc.stdout, /ok       vgs/);
    assert.match(proc.stdout, /vgshell-theme-judge: ok/);

    base = path.join(root, "name-mismatch");
    writePackage(base, "vgs", "other");
    proc = run(base);
    assert.equal(proc.status, 1, proc.stdout + proc.stderr);
    assert.match(proc.stdout, /reason=name-mismatch/);
    assert.doesNotMatch(proc.stdout, /ok       vgs/);

    base = path.join(root, "bad-slot");
    writePackage(base, "vgs", "vgs", Object.assign({}, slots, { colour0: "#000000" }));
    proc = run(base);
    assert.equal(proc.status, 1, proc.stdout + proc.stderr);
    assert.match(proc.stdout, /reason=terminal-slot/);

    proc = run(path.join(root, "missing"));
    assert.equal(proc.status, 2, proc.stdout + proc.stderr);
    assert.match(proc.stdout, /vgshell-theme-judge: unreadable:/);

    // targets/ is no package, and an empty one holds no target.
    base = path.join(root, "targets-empty");
    writePackage(base, "vgs", "vgs");
    fs.mkdirSync(path.join(base, "targets"));
    proc = run(base);
    assert.equal(proc.status, 0, proc.stdout + proc.stderr);
    assert.equal(proc.stdout, "ok       vgs\nvgshell-theme-judge: ok\n");

    base = path.join(root, "targets-good");
    writePackage(base, "vgs", "vgs");
    writeTarget(base, "probe", target, { "probe.conf": "accent=#@{palette.accent} pane=#{pane_id} red=@{terminal.color1}\n" });
    proc = run(base);
    assert.equal(proc.status, 0, proc.stdout + proc.stderr);
    assert.equal(proc.stdout, "ok       vgs\nok       targets/probe\nvgshell-theme-judge: ok\n");

    base = path.join(root, "targets-placeholder");
    writePackage(base, "vgs", "vgs");
    let dir = writeTarget(base, "probe", target, { "probe.conf": "accent=@{palette.nope}\n" });
    writeTarget(base, "second", Object.assign({}, target, { files: [{ template: "a.conf", destination: "second.conf" }] }), { "a.conf": "@{palette.accent}" });
    proc = run(base);
    assert.equal(proc.status, 1, proc.stdout + proc.stderr);
    assert.equal(proc.stdout, `ok       vgs\nrefused  ${dir}: target=probe reason=placeholder template=probe.conf placeholder="palette.nope"\nok       targets/second\nvgshell-theme-judge: refused=1\n`);

    base = path.join(root, "targets-schema");
    writePackage(base, "vgs", "vgs");
    dir = writeTarget(base, "probe", Object.assign({}, target, { encoder: "hex" }), { "probe.conf": "" });
    proc = run(base);
    assert.equal(proc.status, 1, proc.stdout + proc.stderr);
    assert.match(proc.stdout, new RegExp(`^refused  ${RegExp.escape(dir)}: target=probe reason=target-schema key=encoder$`, "m"));

    base = path.join(root, "targets-template-missing");
    writePackage(base, "vgs", "vgs");
    dir = writeTarget(base, "probe", target, {});
    proc = run(base);
    assert.equal(proc.status, 2, proc.stdout + proc.stderr);
    assert.match(proc.stdout, new RegExp(`vgshell-theme-judge: unreadable: ${RegExp.escape(path.join(dir, "probe.conf"))}: ENOENT`));

    // Targets render against the vgs package's slots; without them there is
    // nothing to judge a terminal placeholder against.
    for (const [label, pkg] of [["targets-no-vgs", ["dusk", "dusk", slots]], ["targets-vgs-no-slots", ["vgs", "vgs", null]]]) {
        base = path.join(root, label);
        writePackage(base, ...pkg);
        writeTarget(base, "probe", target, { "probe.conf": "" });
        proc = run(base);
        assert.equal(proc.status, 2, label + ": " + proc.stdout + proc.stderr);
        assert.match(proc.stdout, new RegExp(`vgshell-theme-judge: unreadable: ${RegExp.escape(path.join(base, "vgs"))}: no accepted package with terminal slots`), label);
    }

    catalogRows(CHECK, path.join(root, "catalog"));
    applyRows(path.join(root, "apply"));
    for (const [label, needle, replacement] of [
        ["whole catalogue", "requested === undefined || requested.includes(name)", "true"],
        ["eager downloader", 'const catalog = require(path.join(__dirname, "lib", "theme-catalog.js"));', 'const catalog = require(path.join(__dirname, "lib", "theme-catalog.js"));\nrequire(path.join(__dirname, "lib", "theme-download.js"));']
    ]) {
        assert.equal(fs.readFileSync(CHECK, "utf8").split(needle).length, 2, label + " control must match once before its failure check");
        assert.throws(() => applyRows(path.join(root, "apply-control-" + label.replace(/ /g, "-")), [needle, replacement]), { code: "ERR_ASSERTION" }, label + " control must fail");
    }
    for (const [label, needle, replacement] of CATALOG_CONTROLS) {
        const copy = judgeCopy(path.join(root, "control-" + label.replace(/ /g, "-")), needle, replacement);
        let failed = false;
        try {
            catalogRows(copy, path.join(root, "catalog-" + label.replace(/ /g, "-")));
        } catch (e) {
            failed = true;
        }
        assert.ok(failed, `control "${label}": the catalog rows passed on a judge without that rule`);
    }
} finally {
    fs.rmSync(root, { recursive: true, force: true });
}
console.log(`test-vgshell-theme-judge: ok catalog-controls=${CATALOG_CONTROLS.length}`);
