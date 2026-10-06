#!/usr/bin/env node
// The preview makers off the sandbox: scripts/theme-preview-wallpaper.js,
// which fetches a catalog theme's first wallpaper, and scripts/theme-previews.sh
// --from, which turns shots into each package's preview.jpg. Every row runs
// a disposable tree that holds copies of the two scripts, the libraries
// they load and the token table, with its own catalog and packages, so no
// tracked preview is written. The fetch reads a file:// fixture archive;
// no row reaches the network or starts a graphics program. Without
// ImageMagick the suite exits 77.
//
// The controls at the end edit a tree's copy of a script, one rule at a
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
const COPIED = ["scripts/theme-previews.sh", "scripts/theme-preview-wallpaper.js", "bin/lib/qml-library.js", "bin/lib/theme-download.js",
    "bin/lib/theme-backgrounds.js", "bin/lib/judge-files.js", "shell/Commons/Tokens.js"];
const temp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "theme-previews-")));
// The node running this suite comes first, so the scripts' `node` is the
// same one whatever shims the caller's PATH holds.
const ENV = { PATH: path.dirname(process.execPath) + ":" + process.env.PATH, HOME: path.join(temp, "home") };
const magick = ["magick", "convert"].map(name => spawnSync("sh", ["-c", "command -v " + name], { encoding: "utf8" }).stdout.trim()).find(found => found !== "");

// Whether EDIT, `[file, needle, replacement]`, changes the one place its
// needle occurs in FILE's SOURCE; the edited text.
function edited(source, [file, needle, replacement]) {
    assert.equal(source.split(needle).length, 2, "the edited text occurs once in " + file + ": " + JSON.stringify(needle));
    const text = source.replace(needle, replacement);
    assert.notEqual(text, source, "the edit changes " + file);
    return text;
}

let trees = 0;
// A disposable tree with each of EDITS applied to its copies.
function tree(...edits) {
    const root = path.join(temp, "tree-" + trees++);
    for (const file of COPIED) {
        fs.mkdirSync(path.dirname(path.join(root, file)), { recursive: true });
        fs.copyFileSync(path.join(repo, file), path.join(root, file));
    }
    for (const dir of ["themes/vgs", "themes/catalog/moor"]) {
        fs.mkdirSync(path.join(root, dir), { recursive: true });
        fs.writeFileSync(path.join(root, dir, "theme.json"), "{}\n");
    }
    for (const edit of edits) fs.writeFileSync(path.join(root, edit[0]), edited(fs.readFileSync(path.join(root, edit[0]), "utf8"), edit));
    return root;
}

// The gzipped archive of FILES, `[name, data]`, published under ASSETS as a
// pin's release asset ARCHIVE, and that pin.
function publish(assets, archive, files) {
    const bytes = zlib.gzipSync(tarBytes(files.map(([name, data]) => ({ name, data }))));
    fs.mkdirSync(path.join(assets, "themes"), { recursive: true });
    fs.writeFileSync(path.join(assets, "themes", archive), bytes);
    return { repo: "https://github.com/vanillagreencom/vgs-themes", release: "themes", archive, size: bytes.length, sha256: crypto.createHash("sha256").update(bytes).digest("hex") };
}

function pinCatalog(root, pin) {
    fs.writeFileSync(path.join(root, "themes", "catalog", "index.json"), JSON.stringify({ schemaVersion: 1, entries: [{ name: "moor", mode: "dark", thumbnail: null, imagery: pin }] }));
}

function run(command, args, env) {
    const result = spawnSync(command, args, { encoding: "utf8", env, timeout: 60000 });
    assert.equal(result.error, undefined, command + " ran");
    return result;
}

// The wallpaper rows: the first image by the apply rule, the sorted names,
// though the archive holds b.png first; the kept file reused with its
// archive gone; a re-pinned archive fetched again.
function wallpaperRows(root) {
    const assets = path.join(root, "assets");
    const out = path.join(root, "wallpapers");
    fs.mkdirSync(out);
    const env = Object.assign({ VGS_THEME_ASSET_BASE: pathToFileURL(assets).href, VGS_TEST_RUN: "1" }, ENV);
    const fetch = () => run(process.execPath, [path.join(root, "scripts", "theme-preview-wallpaper.js"), "moor", out, path.join(root, "cache")], env);

    const first = publish(assets, "vgs-theme-moor-r1.tar.gz", [["backgrounds/b.png", "second"], ["backgrounds/a.jpg", "first"], ["readme.txt", "not an image"]]);
    pinCatalog(root, first);
    const firstKept = path.join(out, "moor-" + first.sha256.slice(0, 12) + ".jpg");
    let result = fetch();
    assert.equal(result.status, 0, "the first fetch exits 0: " + result.stderr);
    assert.equal(result.stdout, firstKept + "\n", "the first fetch prints the pin's kept file");
    assert.equal(fs.readFileSync(firstKept, "utf8"), "first", "the kept file is the first image by the apply rule");

    fs.rmSync(path.join(assets, "themes", first.archive));
    result = fetch();
    assert.equal(result.status, 0, "a kept file with the same pin needs no archive: " + result.stderr);
    assert.equal(result.stdout, firstKept + "\n", "the same pin prints the kept file");

    const second = publish(assets, "vgs-theme-moor-r2.tar.gz", [["backgrounds/c.png", "repinned"]]);
    pinCatalog(root, second);
    const secondKept = path.join(out, "moor-" + second.sha256.slice(0, 12) + ".png");
    result = fetch();
    assert.equal(result.status, 0, "a re-pinned fetch exits 0: " + result.stderr);
    assert.equal(result.stdout, secondKept + "\n", "a re-pinned theme prints the new pin's kept file");
    assert.equal(fs.readFileSync(secondKept, "utf8"), "repinned", "a re-pinned theme is fetched again");
}

// Shots for NAMES in a new directory under ROOT.
function shots(root, names) {
    const dir = fs.mkdtempSync(path.join(root, "shots-"));
    for (const name of names) {
        const made = run(magick, ["-size", "384x238", "xc:#336699", "png:" + path.join(dir, "theme-preview-" + name + ".png")], ENV);
        assert.equal(made.status, 0, "the fixture shot is made: " + made.stderr);
    }
    return dir;
}

const previews = (root, from) => run("bash", [path.join(root, "scripts", "theme-previews.sh"), "--from", from, "vgs", "moor"], ENV);
const previewSize = file => run(magick, ["identify", "-format", "%m %wx%h", file], ENV).stdout;

// The written rows: tokens and the size each writes, the card's 768 by 476
// at decodeCap on its long side, worked out by hand.
const SIZES = [
    ["the shipped tokens", undefined, "2048x1269"],
    ["a decodeCap of 1024", ["shell/Commons/Tokens.js", "decodeCap: length(2048)", "decodeCap: length(1024)"], "1024x635"]
];

function previewRows(...edits) {
    for (const [label, tokens, size] of SIZES) {
        const root = tree(...edits, ...(tokens === undefined ? [] : [tokens]));
        const result = previews(root, shots(root, ["vgs", "moor"]));
        assert.equal(result.status, 0, label + ": the previews are written: " + result.stderr);
        for (const target of ["themes/vgs/preview.jpg", "themes/catalog/moor/preview.jpg"]) {
            const bytes = fs.statSync(path.join(root, target)).size;
            assert.ok(result.stdout.split("\n").includes("theme-previews: wrote=" + target + " bytes=" + bytes), label + ": the wrote line names " + target);
            assert.equal(previewSize(path.join(root, target)), "JPEG " + size, label + ": " + target + " is a JPEG at " + size);
        }
    }

    const root = tree(...edits);
    const from = shots(root, ["vgs"]);
    const result = previews(root, from);
    assert.equal(result.status, 2, "a missing shot is exit 2");
    assert.equal(result.stderr, "theme-previews: refused: shot=" + path.join(from, "theme-preview-moor.png") + "\n", "a missing shot is refused by its path");
    assert.ok(!fs.existsSync(path.join(root, "themes", "vgs", "preview.jpg")), "a missing shot writes no preview");
}

// Each control: the rows it runs and the edit that plants its defect.
const CONTROLS = [
    ["wallpaper", ["scripts/theme-preview-wallpaper.js", "path.parse(file.name).name === keptName", "file.name.startsWith(name + \"-\")"]],
    ["wallpaper", ["scripts/theme-preview-wallpaper.js", "if (existing !== undefined) {", "if (false) {"]],
    ["wallpaper", ["scripts/theme-preview-wallpaper.js", "backgrounds.images(unpacked, \"theme-preview-wallpaper: theme=\" + name)[0]",
        "backgrounds.images(unpacked, \"theme-preview-wallpaper: theme=\" + name).at(-1)"]],
    ["preview", ["scripts/theme-previews.sh", "-resize \"$preview_size!\"", "-resize \"1536x952!\""]],
    ["preview", ["scripts/theme-previews.sh", "-resize \"$preview_size!\"", "-resize \"2048x1269!\""]],
    ["preview", ["scripts/theme-previews.sh", "|| refuse shot \"$from/theme-preview-$name.png\"", "|| true"]]
];

function main() {
    if (magick === undefined) {
        console.log("test-theme-previews: status=not-measured missing=magick");
        return 77;
    }
    wallpaperRows(tree());
    previewRows();
    for (const [index, [rows, edit]] of CONTROLS.entries()) {
        // Checked outside the try, so an edit that no longer applies fails
        // the suite instead of passing as a control.
        edited(fs.readFileSync(path.join(repo, edit[0]), "utf8"), edit);
        let failed = false;
        try {
            if (rows === "wallpaper") wallpaperRows(tree(edit));
            else previewRows(edit);
        } catch (e) {
            if (!(e instanceof assert.AssertionError)) throw e;
            failed = true;
        }
        assert.ok(failed, "control " + index + " " + JSON.stringify(edit[1]) + ": the rows passed on a copy without that rule");
    }
    console.log(`test-theme-previews: ok sizes=${SIZES.length} controls=${CONTROLS.length}`);
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
