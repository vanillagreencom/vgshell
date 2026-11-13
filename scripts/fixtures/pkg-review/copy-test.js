#!/usr/bin/env node
// Committed recipe snapshots exclude clone build output and never materialize
// links. The local clones contain no executable package-manager fixture.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const cp = require("node:child_process");

const helper = path.resolve(__dirname, "../../../bin/lib/pkg-review-copy.py");
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "pkg-review-copy-"));
const env = { ...process.env, HOME: scratch, XDG_CONFIG_HOME: path.join(scratch, "config"),
    XDG_DATA_HOME: path.join(scratch, "data"), XDG_STATE_HOME: path.join(scratch, "state"),
    XDG_CACHE_HOME: path.join(scratch, "cache"), GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null" };

function command(binary, args, options = {}) {
    const result = cp.spawnSync(binary, args, { env, encoding: "utf8", timeout: 15000, ...options });
    assert.equal(result.error, undefined, binary + " starts and ends");
    assert.equal(result.status, 0, binary + ": " + result.stderr);
    return result.stdout;
}

function verify(program, label) {
    const root = path.join(scratch, label), source = path.join(root, "source"), clone = path.join(root, "clone");
    const destination = path.join(root, "snapshot");
    fs.mkdirSync(source, { recursive: true });
    fs.mkdirSync(destination, { mode: 0o700 });
    const tracked = new Map([
        ["PKGBUILD", "pkgname=fixture\npkgver=1\npkgrel=1\n# $Format:%H$\n"],
        [".SRCINFO", "pkgbase = fixture\n\tpkgver = 1\npkgname = fixture\n\tinstall = fixture.install\n"],
        [".gitattributes", "fixture.install export-ignore\nPKGBUILD export-subst\n"],
        ["fixture.install", "post_install() { printf '%s\\n' fixture; }\n"],
        ["patches/.gitattributes", "build.patch export-ignore\n"],
        ["patches/build.patch", "committed patch bytes\n"],
        ["symlinks.txt", "a real recipe file keeps its name and $Format:%H$ bytes\n"]
    ]);
    for (const [name, text] of tracked) {
        fs.mkdirSync(path.dirname(path.join(source, name)), { recursive: true });
        fs.writeFileSync(path.join(source, name), text);
    }
    const outside = path.join(root, "outside");
    fs.writeFileSync(outside, "outside sentinel that the agent must not receive\n");
    fs.symlinkSync(outside, path.join(source, "outside-link"));
    fs.symlinkSync("../../outside-directory", path.join(source, "patches/directory-link"));
    command("git", ["init", "--quiet", source]);
    command("git", ["-C", source, "add", "--all"]);
    command("git", ["-C", source, "-c", "user.name=Fixture", "-c", "user.email=fixture@invalid", "commit", "--quiet", "-m", "recipe"]);
    command("git", ["clone", "--quiet", "--local", "--", source, clone]);
    const tree = command("git", ["-C", clone, "rev-parse", "HEAD^{tree}"]).trim();
    fs.mkdirSync(path.join(clone, ".git/info"), { recursive: true });
    fs.writeFileSync(path.join(clone, ".git/info/attributes"), ".SRCINFO export-ignore\nsymlinks.txt export-subst\n");

    // paru builds inside these clones. Neither dirty tracked paths nor the
    // retained src/, pkg/ and built package may become review evidence.
    fs.writeFileSync(path.join(clone, "PKGBUILD"), "uncommitted recipe\n");
    fs.unlinkSync(path.join(clone, "patches/build.patch"));
    fs.symlinkSync(outside, path.join(clone, "patches/build.patch"));
    fs.mkdirSync(path.join(clone, "src"));
    fs.symlinkSync(outside, path.join(clone, "src/download"));
    fs.symlinkSync(path.join(root, "missing-package-directory"), path.join(clone, "pkg"));
    const packageFile = fs.openSync(path.join(clone, "fixture-1-1-any.pkg.tar.zst"), "wx");
    try { fs.ftruncateSync(packageFile, 1024 * 1024 * 1024); } finally { fs.closeSync(packageFile); }

    const manifest = JSON.parse(command("python3", [program, clone, destination]));
    assert.equal(manifest.tree, tree, "manifest names the archived tree");
    assert.deepEqual(manifest.files.slice().sort(), [...tracked.keys()].sort(), "every tracked regular file is copied");
    assert.deepEqual(manifest.symlinks, [
        { path: "outside-link", target: outside },
        { path: "patches/directory-link", target: "../../outside-directory" }
    ], "committed symlinks are listed without resolving their targets");
    for (const [name, text] of tracked) assert.equal(fs.readFileSync(path.join(destination, name), "utf8"), text, "HEAD bytes: " + name);
    for (const name of ["outside-link", "patches/directory-link", "src", "pkg", ".git", "fixture-1-1-any.pkg.tar.zst"])
        assert.equal(fs.lstatSync(path.join(destination, name), { throwIfNoEntry: false }), undefined, "no clone output or symbolic link: " + name);
    assert.equal(fs.readFileSync(outside, "utf8"), "outside sentinel that the agent must not receive\n", "outside bytes stay unchanged");
}

try {
    verify(helper, "ordinary");
    const original = fs.readFileSync(helper, "utf8");
    const needle = '"--worktree-attributes", "--format=tar"';
    assert.equal(original.split(needle).length, 2, "one archive attribute boundary");
    const control = path.join(scratch, "copy-attributes.py");
    fs.writeFileSync(control, original.replace(needle, '"--format=tar"'));
    assert.throws(() => verify(control, "control"), error => error.code === "ERR_ASSERTION"
        && error.message.includes("every tracked regular file is copied"), "archive attribute omissions are detected");
    process.stdout.write("package review committed snapshots: pass (attribute control rejected)\n");
} finally {
    fs.rmSync(scratch, { recursive: true, force: true });
}
