#!/usr/bin/env node
// The catalog wallpaper name check, scripts/check-catalog-wallpaper-names.js,
// off the network: every row runs a disposable tree holding copies of the
// check and the libraries it loads, with its own catalog, packages and
// file:// fixture archives. Every expected line below was written by hand.
//
// The controls at the end edit a tree's copy of the check, one rule at a
// time, and require the rows to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { pathToFileURL } = require("node:url");
const zlib = require("node:zlib");
const { tarBytes } = require("./tar-fixture.js");

const repo = path.join(__dirname, "..");
const CHECK = "scripts/check-catalog-wallpaper-names.js";
const COPIED = [CHECK, "bin/lib/theme-download.js", "bin/lib/theme-backgrounds.js", "bin/lib/judge-files.js"];
const temp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "catalog-wallpaper-names-")));
const ENV = { PATH: process.env.PATH, HOME: path.join(temp, "home") };

function edited(source, [file, needle, replacement]) {
    assert.equal(source.split(needle).length, 2, "the edited text occurs once in " + file + ": " + JSON.stringify(needle));
    const text = source.replace(needle, replacement);
    assert.notEqual(text, source, "the edit changes " + file);
    return text;
}

let trees = 0;
// A disposable tree with EDIT, when given, applied to its copy.
function tree(edit) {
    const root = path.join(temp, "tree-" + trees++);
    for (const file of COPIED) {
        fs.mkdirSync(path.dirname(path.join(root, file)), { recursive: true });
        fs.copyFileSync(path.join(repo, file), path.join(root, file));
    }
    if (edit !== undefined) fs.writeFileSync(path.join(root, edit[0]), edited(fs.readFileSync(path.join(root, edit[0]), "utf8"), edit));
    return root;
}

// The gzipped archive of MEMBERS, `[name, data]` or, for a symlink,
// `[name, target, "2"]`, published under ASSETS as release asset ARCHIVE,
// and its pin.
function publish(assets, archive, members) {
    const bytes = zlib.gzipSync(tarBytes(members.map(([name, data, type]) => (type === "2" ? { name, type, link: data } : { name, data }))));
    fs.mkdirSync(path.join(assets, "themes"), { recursive: true });
    fs.writeFileSync(path.join(assets, "themes", archive), bytes);
    return { repo: "https://github.com/vanillagreencom/vgs-themes", release: "themes", archive, size: bytes.length, sha256: crypto.createHash("sha256").update(bytes).digest("hex") };
}

// A catalog of one theme, moor, pinning PIN, whose package names NAMES.
function catalog(root, pin, names) {
    const dir = path.join(root, "themes", "catalog", "moor");
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(root, "themes", "catalog", "index.json"), JSON.stringify({ schemaVersion: 1, entries: [{ name: "moor", imagery: pin }] }));
    fs.writeFileSync(path.join(dir, "theme.json"), JSON.stringify(names === undefined ? { name: "moor" } : { name: "moor", backgrounds: names }));
}

function invoke(root, prepare = false) {
    const env = Object.assign({ VGS_THEME_ASSET_BASE: pathToFileURL(path.join(root, "assets")).href, VGS_TEST_RUN: "1" }, ENV);
    const result = spawnSync(process.execPath, [path.join(root, CHECK), ...(prepare ? ["--prepare"] : []), path.join(root, "themes"), path.join(root, "listings")], { encoding: "utf8", env, timeout: 60000 });
    assert.equal(result.error, undefined, "the check ran");
    return result;
}

function check(root) {
    const prepared = invoke(root, true);
    return prepared.status === 0 ? invoke(root) : prepared;
}

const IMAGES = [["backgrounds/b.png", "second"], ["backgrounds/a.jpg", "first"]];
const NAMED = { "a.jpg": "Moor", "b.png": "Heath" };

// Each row: label, the archive's members, the package's names, the exit
// status and stdout.
const ROWS = [
    ["every image named", IMAGES, NAMED, 0, "ok theme=moor images=2\n"],
    ["an image with no name", IMAGES, { "a.jpg": "Moor" }, 1, 'refused: theme=moor reason=missing file="b.png"\n'],
    ["no backgrounds map", IMAGES, undefined, 1, 'refused: theme=moor reason=missing file="a.jpg"\nrefused: theme=moor reason=missing file="b.png"\n'],
    ["a name on a file the archive lacks", IMAGES, Object.assign({ "c.png": "Fen" }, NAMED), 1, 'refused: theme=moor reason=unknown file="c.png"\n'],
    ["two names that differ only in case", IMAGES, { "a.jpg": "Moor", "b.png": "moor" }, 1,
        'refused: theme=moor reason=duplicate name="moor" files=["a.jpg","b.png"]\n'],
    ["members install refuses", [...IMAGES, ["backgrounds/notes.txt", "notes"], ["wallpapers/a-long-name.png", "elsewhere"], ["backgrounds/link.png", "a.jpg", "2"]], NAMED, 1,
        'refused: theme=moor reason=member member="backgrounds/notes.txt" kind=file\n' +
        'refused: theme=moor reason=member member="wallpapers/a-long-name.png" kind=file\n' +
        'refused: theme=moor reason=member member="backgrounds/link.png" kind=symlink\n']
];

function rows(edit) {
    const missing = tree(edit);
    catalog(missing, publish(path.join(missing, "assets"), "vgs-theme-moor-r1.tar.gz", IMAGES), NAMED);
    const unprepared = invoke(missing);
    assert.equal(unprepared.status, 2, "an offline consumer requires its prepared input");
    assert.match(unprepared.stderr, /^input-step: failed listing=missing /);
    assert.ok(!fs.existsSync(path.join(missing, "listings")), "an offline consumer creates no cache or fetch scratch");

    for (const [label, members, names, status, stdout] of ROWS) {
        const root = tree(edit);
        catalog(root, publish(path.join(root, "assets"), "vgs-theme-moor-r1.tar.gz", members), names);
        const result = check(root);
        assert.equal(result.stdout, stdout, label + ": the lines");
        assert.equal(result.status, status, label + ": the exit status: " + result.stderr);
    }

    // The listing is kept per pin, and the archive is not.
    let root = tree(edit);
    const pin = publish(path.join(root, "assets"), "vgs-theme-moor-r1.tar.gz", IMAGES);
    catalog(root, pin, NAMED);
    assert.equal(check(root).status, 0, "the first check passes");
    assert.deepEqual(fs.readdirSync(path.join(root, "listings")), [pin.sha256], "only the pin's directory is kept");
    assert.deepEqual(fs.readdirSync(path.join(root, "listings", pin.sha256)), ["listing.json"], "only the verified names are kept");
    fs.rmSync(path.join(root, "assets"), { recursive: true });
    let result = check(root);
    assert.equal(result.status, 0, "a kept listing needs no archive: " + result.stdout);
    const kept = path.join(root, "listings", pin.sha256, "listing.json");
    for (const malformed of ["{", JSON.stringify({ files: "fixture.png" }), JSON.stringify({ files: [1] })]) {
        fs.writeFileSync(kept, malformed);
        result = invoke(root, true);
        assert.equal(result.status, 2, "malformed metadata fails preparation");
        assert.match(result.stderr, /^input-step: failed listing=(unreadable|invalid) /);
    }

    // An archive that is not its pin is refused; one that cannot be fetched
    // is unavailable, not a pass.
    root = tree(edit);
    const wrong = Object.assign({}, publish(path.join(root, "assets"), "vgs-theme-moor-r1.tar.gz", IMAGES), { sha256: "0".repeat(64) });
    catalog(root, wrong, NAMED);
    result = check(root);
    assert.equal(result.status, 1, "a wrong sha256 is refused");
    assert.match(result.stdout, /^refused: theme=moor reason=sha256 /, "a wrong sha256 names its reason");
    root = tree(edit);
    catalog(root, Object.assign({}, pin, { archive: "vgs-theme-moor-r9.tar.gz" }), NAMED);
    result = check(root);
    assert.equal(result.status, 2, "an unavailable archive fails its input step");
    assert.match(result.stderr, /^input-step: failed theme=moor reason=download /, "an archive that cannot be fetched names the input failure");
}

const CONTROLS = [
    [CHECK, 'if (!Object.hasOwn(names, file)) out.push(["missing"', 'if (false) out.push(["missing"'],
    [CHECK, 'if (!held.has(file)) out.push(["unknown"', 'if (false) out.push(["unknown"'],
    [CHECK, "const key = String(name).toLowerCase();", "const key = file;"],
    [CHECK, '!backgrounds.isImageName(file))', 'false)'],
    [CHECK, '!member.name.startsWith(backgrounds.DIR + "/") ||', ''],
    [CHECK, 'member.kind !== "file" || ', ''],
    [CHECK, "if (fs.existsSync(kept)) {", "if (false) {"],
    [CHECK, '!Array.isArray(cached.files)', 'false'],
    [CHECK, 'if (!prepare) throw new Unreadable("input-step: failed listing=missing sha256=" + pin.sha256 + " path=" + kept);', ""],
    [CHECK, 'return refusal.step === "fetch" && !["sha256", "size", "pin"].includes(refusal.reason);', "return false;"]
];

function main() {
    rows();
    for (const [index, edit] of CONTROLS.entries()) {
        // Checked outside the try, so an edit that no longer applies fails
        // the suite instead of passing as a control.
        edited(fs.readFileSync(path.join(repo, edit[0]), "utf8"), edit);
        let failed = false;
        try {
            rows(edit);
        } catch (e) {
            if (!(e instanceof assert.AssertionError)) throw e;
            failed = true;
        }
        assert.ok(failed, "control " + index + " " + JSON.stringify(edit[1]) + ": the rows passed on a copy without that rule");
    }
    console.log(`test-check-catalog-wallpaper-names: ok rows=${ROWS.length} controls=${CONTROLS.length}`);
    return 0;
}

try {
    process.exitCode = main();
} catch (e) {
    console.error(e.stack || e);
    process.exitCode = 1;
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}
