#!/usr/bin/env node
// The review evidence the package owner gathers for each AUR recipe fixture
// under recipes/ (recipes/<name>/fixture.json names its source), built
// through the production `vgshell-pkg review` in the pkg-review world with
// recipe-command.js answering the fixture's queries, fetch and agent, and
// the fixture's cached/ recipe at paru's clone path in the world's home.
// One row per fixture checks, against the values fixture.json declares:
//   packages.txt  holds `aur <package> <old> <new>`, `?` for a version a
//                 named install does not know, `install <package>
//                 <install>` and `recipe <pkgbase> <recipe>`, and no other
//                 aur, install or recipe line;
//   install/      holds <package>.diff exactly when `install` is changed;
//   recipe/       holds <pkgbase>.diff exactly when `recipe` is changed;
//   failures      the `unknown` lines other than the fixed future-build
//                 limit: none for a fixture;
//   concerns      the owner asks about the package, after the agent's clean
//                 verdict, exactly when `installerRisk` is true: the
//                 installer's own install-script check
//                 (PackageReview.installScriptChange) found a risky line.
// `installerRiskGap` marks a malicious fixture that check misses today.
// PLANTED rows reuse a fixture with one defect in the world and declare
// the failure or whole-folder delta the owner must report instead. Local
// source changes must reach the diff even when PKGBUILD stays identical.
//
// Each control copies one fixture with a wrong declaration into a scratch
// recipes directory, runs this file over it with --recipes, and that run
// must fail at the row the plant names.
"use strict";
const assert = require("node:assert/strict"), fs = require("node:fs"), os = require("node:os"), path = require("node:path"), cp = require("node:child_process"), crypto = require("node:crypto");
const { create } = require("./world.js");
const q = s => "'" + String(s).replaceAll("'", "'\\''") + "'";

if (process.argv[2] === "--inner") {
    // On the pty: one owner review of one fixture, as one-review.js runs it.
    const [root, owner, metaFile] = process.argv.slice(3), meta = JSON.parse(fs.readFileSync(metaFile, "utf8"));
    const created = cp.spawnSync(process.execPath, [owner, "review-transaction"], { encoding: "utf8", env: process.env });
    if (created.status !== 0) throw new Error(created.stderr);
    const tx = created.stdout.trim(), env = { ...process.env, VGS_PACKAGE_TRANSACTION: tx };
    try {
        const config = path.join(tx, "pacman.conf");
        fs.writeFileSync(config, "Include = " + path.join(root, "pacman.conf") + "\nHookDir = " + path.join(root, "hooks") + "\n", { mode: 0o600 });
        const request = meta.old === null
            ? { version: 1, mode: "named", action: "install", groups: [{ manager: "aur", names: [meta.package], installs: [], ignored: [] }], sources: [], rebuild: [], config, customAurArgv: null }
            : { version: 1, mode: "upgrade", action: "upgrade", groups: [{ manager: "aur", names: [], installs: [], ignored: [] }], sources: ["aur"], rebuild: [], config, customAurArgv: null };
        const req = path.join(tx, "request"), result = path.join(tx, "result");
        fs.writeFileSync(req, JSON.stringify(request), { mode: 0o600 });
        fs.writeFileSync(result, "", { mode: 0o600 });
        const r = cp.spawnSync(process.execPath, [owner, "review", "--request", req, "--result", result], { env, stdio: "inherit" });
        fs.writeFileSync(path.join(process.env.RECIPE_OUT, "result.json"), fs.readFileSync(result, "utf8") || "null");
        process.exitCode = r.status === null ? 1 : r.status;
    } finally { fs.rmSync(tx, { recursive: true, force: true }); }
    return;
}

const at = process.argv.indexOf("--recipes");
const recipes = at < 0 ? path.join(__dirname, "recipes") : process.argv[at + 1];
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "package-review-recipes-"));
const INSTALL_STATES = ["none", "new", "unchanged", "changed"], RECIPE_STATES = ["new", "unchanged", "changed"];
const FUTURE_BUILD_LIMIT = /^dependencies=unresolved name=/;
// Planted rows: a fixture, the defect planted in its world, and the
// owner's expected evidence in place of the fixture's own declarations.
const PLANTED = [
    { name: "cached-recipe-symlink", fixture: "build-change-cached", plant: "cache-symlink",
        expect: meta => ({ recipe: null, failures: ["recipe=cache-unsafe name=" + meta.pkgbase] }) },
    { name: "cached-local-source-symlink", fixture: "local-launcher-checksum", plant: "cache-source-symlink",
        expect: meta => ({ recipe: null, failures: ["recipe=cache-unsafe name=" + meta.pkgbase] }) },
    { name: "cached-folder-symlink", fixture: "build-change-cached", plant: "cache-folder-symlink",
        expect: meta => ({ recipe: null, failures: ["recipe=cache-unsafe name=" + meta.pkgbase] }) },
    { name: "local-source-only", fixture: "local-launcher-checksum", plant: "source-only",
        expect: () => ({ recipe: "changed", failures: [], diffFiles: ["obsolete.sh", "proton-mail.sh"] }) },
    { name: "empty-source-added", fixture: "cached-malicious-unchanged", plant: "empty-added",
        expect: meta => ({ recipe: "changed", failures: [], diffFiles: [], diffAdded: ["Empty file added: build/" + meta.pkgbase + "/sources/marker"] }) },
    { name: "empty-source-removed", fixture: "cached-malicious-unchanged", plant: "empty-removed",
        expect: meta => ({ recipe: "changed", failures: [], diffFiles: [], diffAdded: ["Empty file removed: cached/" + meta.pkgbase + "/sources/marker"] }) },
    { name: "helper-metadata-only", fixture: "cached-malicious-unchanged", plant: "helper-metadata",
        expect: () => ({ recipe: "unchanged", failures: [] }) }
];

// The owner's review of one fixture: its packages.txt lines, install/ and
// recipe/ files, the concern questions the stand-in gum recorded and the
// owner's result. PLANT, when set, is the one defect its world carries.
function reviewed(label, fixture, plant, stop) {
    const out = path.join(scratch, label);
    if (["source-only", "empty-added"].includes(plant)) {
        const copy = path.join(out, "fixture");
        fs.cpSync(fixture, copy, { recursive: true });
        fixture = copy;
        if (plant === "source-only") {
            for (const file of ["PKGBUILD", ".SRCINFO"]) fs.copyFileSync(path.join(copy, "cached", file), path.join(copy, "build", file));
            // AUR recipes may use SKIP for a local source. Keep the same
            // PKGBUILD on both sides so this is a reachable source-only edit.
            for (const algorithm of ["sha512", "blake2b512"]) {
                const checksum = crypto.createHash(algorithm).update(fs.readFileSync(path.join(copy, "cached/proton-mail.sh"))).digest("hex");
                for (const side of ["cached", "build"]) for (const file of ["PKGBUILD", ".SRCINFO"]) {
                    const at = path.join(copy, side, file), text = fs.readFileSync(at, "utf8");
                    assert.equal(text.split(checksum).length, 2, label + ": one local source checksum");
                    fs.writeFileSync(at, text.replace(checksum, "SKIP"));
                }
            }
            fs.writeFileSync(path.join(copy, "cached/obsolete.sh"), "#!/usr/bin/bash\nprintf '%s\\n' obsolete\n");
        } else {
            fs.mkdirSync(path.join(copy, "build/sources"));
            fs.writeFileSync(path.join(copy, "build/sources/marker"), "");
        }
    }
    const meta = JSON.parse(fs.readFileSync(path.join(fixture, "fixture.json"), "utf8"));
    // A concern question, if any, is answered Skip; the unavailable
    // question a failed read asks, Stop.
    const w = create(path.join(out, "world"), { choices: ["Review", "Use Claude Code", stop ? "Stop" : "Skip"] });
    fs.writeFileSync(path.join(w.root, "config-corresponds"), "");
    if (fs.existsSync(path.join(fixture, "installed.install"))) {
        const local = path.join(w.root, "db/local", meta.package + "-" + meta.old);
        fs.mkdirSync(local, { recursive: true });
        fs.copyFileSync(path.join(fixture, "installed.install"), path.join(local, "install"));
    }
    if (fs.existsSync(path.join(fixture, "cached"))) {
        // paru v2.1.0's default clone directory, $HOME/.cache/paru/clone:
        // the world sets HOME and no XDG_CACHE_HOME.
        const clone = path.join(w.env.HOME, ".cache/paru/clone", meta.pkgbase);
        fs.cpSync(path.join(fixture, "cached"), clone, { recursive: true });
        if (["cache-symlink", "cache-source-symlink"].includes(plant)) {
            const file = plant === "cache-symlink" ? "PKGBUILD" : "proton-mail.sh";
            fs.renameSync(path.join(clone, file), path.join(w.root, "linked-source"));
            fs.symlinkSync(path.join(w.root, "linked-source"), path.join(clone, file));
        } else if (plant === "cache-folder-symlink") {
            fs.renameSync(clone, path.join(w.root, "linked-clone"));
            fs.symlinkSync(path.join(w.root, "linked-clone"), clone);
        } else if (plant === "empty-removed") {
            fs.mkdirSync(path.join(clone, "sources"));
            fs.writeFileSync(path.join(clone, "sources/marker"), "");
        } else if (plant === "helper-metadata") {
            fs.mkdirSync(path.join(clone, ".git"));
            fs.symlinkSync(path.join(w.root, "absent-metadata"), path.join(clone, ".git/ignored"));
        }
    } else assert.equal(plant, undefined, label + ": a planted cache needs a cached fixture");
    for (const tool of ["pacman", "paru", "claude", "codex"]) {
        fs.unlinkSync(path.join(w.root, "tools", tool));
        fs.symlinkSync(path.join(__dirname, "recipe-command.js"), path.join(w.root, "tools", tool));
    }
    const argv = [process.execPath, __filename, "--inner", w.root, w.owner, path.join(fixture, "fixture.json")];
    const r = cp.spawnSync("/usr/bin/script", ["-qec", argv.map(q).join(" "), "/dev/null"],
        { env: { ...w.env, SHELL: "/usr/bin/bash", RECIPE_FIXTURE: fixture, RECIPE_OUT: out }, encoding: "utf8", timeout: 60000 });
    assert.equal(r.status, 0, label + ": owner review: " + r.stdout + r.stderr);
    const evidence = path.join(out, "evidence");
    assert.ok(fs.existsSync(path.join(evidence, "packages.txt")), label + ": the agent ran: " + r.stdout + r.stderr);
    const files = dir => fs.existsSync(path.join(evidence, dir)) ? fs.readdirSync(path.join(evidence, dir)).sort() : [];
    return {
        meta,
        lines: fs.readFileSync(path.join(evidence, "packages.txt"), "utf8").split("\n").filter(Boolean),
        installFiles: files("install"),
        recipeFiles: files("recipe"),
        recipeDiff: fs.existsSync(path.join(evidence, "recipe", meta.pkgbase + ".diff"))
            ? fs.readFileSync(path.join(evidence, "recipe", meta.pkgbase + ".diff"), "utf8") : null,
        concerns: w.calls().filter(c => c.kind === "offer" && c.offered.includes("Install anyway")),
        result: JSON.parse(fs.readFileSync(path.join(out, "result.json"), "utf8"))
    };
}

try {
    const names = fs.readdirSync(recipes, { withFileTypes: true }).filter(e => e.isDirectory()).map(e => e.name).sort();
    const table = names.map(name => ({ name, fixture: path.join(recipes, name), plant: undefined, expect: meta => ({ recipe: meta.recipe, failures: [] }) }))
        .concat(at < 0 ? PLANTED.map(row => ({ ...row, fixture: path.join(recipes, row.fixture) })) : []);
    const rows = [];
    for (const row of table) {
        const declared = JSON.parse(fs.readFileSync(path.join(row.fixture, "fixture.json"), "utf8")), expected = row.expect(declared);
        const seen = reviewed(row.name, row.fixture, row.plant, expected.failures.length > 0);
        const { meta, lines, installFiles, recipeFiles, concerns, result } = seen, name = row.name;
        assert.ok(INSTALL_STATES.includes(meta.install), name + ": declared install state");
        assert.ok(RECIPE_STATES.includes(meta.recipe), name + ": declared recipe state");
        assert.equal(typeof meta.installerRisk, "boolean", name + ": declared installerRisk");
        const version = v => meta.old === null || v === null ? "?" : v;
        assert.deepEqual(lines.filter(l => l.startsWith("aur ")), [`aur ${meta.package} ${version(meta.old)} ${version(meta.new)}`], name + ": aur line");
        assert.deepEqual(lines.filter(l => l.startsWith("install ")), [`install ${meta.package} ${meta.install}`], name + ": install line");
        assert.deepEqual(lines.filter(l => l.startsWith("recipe ")), expected.recipe === null ? [] : [`recipe ${meta.pkgbase} ${expected.recipe}`], name + ": recipe line");
        assert.deepEqual(installFiles.filter(f => f.endsWith(".diff")), meta.install === "changed" ? [meta.package + ".diff"] : [], name + ": install diff");
        assert.deepEqual(recipeFiles, expected.recipe === "changed" ? [meta.pkgbase + ".diff"] : [], name + ": recipe diff");
        if (expected.recipe === "changed" && (expected.diffFiles || meta.recipeDiffFiles)) {
            const prefix = "+++ build/" + meta.pkgbase + "/";
            assert.deepEqual(seen.recipeDiff.split("\n").filter(line => line.startsWith(prefix)).map(line => line.slice(prefix.length)).sort(),
                [...(expected.diffFiles || meta.recipeDiffFiles)].sort(), name + ": recipe diff files");
            for (const added of expected.diffAdded || meta.recipeDiffAdded || [])
                assert.ok(seen.recipeDiff.includes(added), name + ": recipe diff carries the local source change");
        }
        assert.deepEqual(lines.filter(l => l.startsWith("unknown ")).map(l => l.slice(8)).filter(l => !FUTURE_BUILD_LIMIT.test(l)), expected.failures, name + ": failures");
        assert.equal(result.decision, expected.failures.length ? "stop" : "proceed", name + ": owner decision");
        assert.deepEqual(result.reviewed, [meta.package], name + ": reviewed packages");
        assert.equal(concerns.length, meta.installerRisk ? 1 : 0, name + ": installer risk");
        assert.deepEqual(result.skipped, meta.installerRisk && !expected.failures.length ? [meta.package] : [], name + ": installer risk skip");
        rows.push(seen);
        console.log("package-recipe-proof: " + JSON.stringify({ name, install: meta.install, recipe: expected.recipe, failures: expected.failures, installerRisk: meta.installerRisk, expect: meta.expect }));
    }
    // Coverage floor: the set exercises every install and recipe state and
    // both installer answers, so a discovery that lost fixtures cannot pass.
    if (at < 0) {
        for (const state of INSTALL_STATES) assert.ok(rows.some(r => r.meta.install === state), "coverage: install " + state);
        for (const state of RECIPE_STATES) assert.ok(rows.some(r => r.meta.recipe === state), "coverage: recipe " + state);
        for (const risk of [true, false]) assert.ok(rows.some(r => r.meta.installerRisk === risk), "coverage: installerRisk " + risk);
        for (const expect of ["clean", "flagged"]) assert.ok(rows.some(r => r.meta.expect === expect), "coverage: expect " + expect);

        // Must-fail controls: one fixture copy with one wrong declaration each.
        for (const [control, fixture, field, value, fails] of [
            ["wrong-install-state", "install-changed", "install", "unchanged", /install-changed: install line/],
            ["wrong-recipe-state", "source-domain-change", "recipe", "unchanged", /source-domain-change: recipe line/],
            ["omitted-local-source-diff", "local-launcher-checksum", "recipeDiffFiles", ["PKGBUILD"], /local-launcher-checksum: recipe diff files/],
            ["missed-installer-risk", "install-setuid", "installerRisk", false, /install-setuid: installer risk/],
            ["invented-installer-risk", "pkgver-bump-cached", "installerRisk", true, /pkgver-bump-cached: installer risk/]
        ]) {
            const planted = path.join(scratch, "controls", control);
            fs.cpSync(path.join(recipes, fixture), path.join(planted, fixture), { recursive: true });
            const file = path.join(planted, fixture, "fixture.json"), meta = JSON.parse(fs.readFileSync(file, "utf8"));
            assert.notEqual(meta[field], value, control + ": the plant changes the declaration");
            fs.writeFileSync(file, JSON.stringify({ ...meta, [field]: value }));
            const r = cp.spawnSync(process.execPath, [__filename, "--recipes", planted],
                { env: { PATH: "/usr/bin:/bin", TMPDIR: scratch, VGS_TEST_RUN: "1" }, encoding: "utf8", timeout: 120000 });
            assert.equal(r.status, 1, control + ": the planted run fails: " + r.stdout + r.stderr);
            assert.match(r.stderr, fails, control + ": " + r.stderr);
            console.log("package-recipe-control: " + JSON.stringify({ control, status: r.status }));
        }
    }
} finally {
    fs.rmSync(scratch, { recursive: true, force: true });
}
console.log("test-package-recipes: ok");
