#!/usr/bin/env node
// Process-boundary controls for check-packaging's two engine operations.
// Run inside gpu-fence.sh: curl, the package database and qs are private
// stand-ins. The real XML reader, engine judge and CLI entry remain in use.
// inputs: scripts/check-packaging.js scripts/lib/engine-availability.js scripts/preflight-floor.js scripts/validate scripts/smoke/gpu-fence.sh scripts/smoke/row-inputs.sh bin/lib/engine.js bin/lib/judge-files.js packaging/fedora/copr-project flake.nix flake.lock packaging/arch/vgshell-quickshell/*.patch VERSION
"use strict";
const assert = require("node:assert/strict");
const cp = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const zlib = require("node:zlib");
const crypto = require("node:crypto");
const repo = path.resolve(__dirname, "..");
const engine = require(path.join(repo, "bin/lib/engine.js"));
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "test-engine-availability-"));
process.on("exit", () => fs.rmSync(tmp, { recursive: true, force: true }));
const api = "https://api.github.com/repos/vanillagreencom/vgshell/";
const aur = "https://aur.archlinux.org/rpc/v5/info?arg[]=vgshell-quickshell";
const sha = "a".repeat(40);
const asset = engine.debianAsset("amd64");
const version = fs.readFileSync(path.join(repo, "VERSION"), "utf8").trim();
const copr = fs.readFileSync(path.join(repo, "packaging/fedora/copr-project"), "utf8");
const project = /^project (\S+)$/m.exec(copr)[1];
const targets = [...copr.matchAll(/^chroot (\S+)$/gm)].map(match => match[1]);
const flake = fs.readFileSync(path.join(repo, "flake.nix"), "utf8");
const patches = [...flake.matchAll(/\.\/(packaging\/arch\/vgshell-quickshell\/[a-zA-Z0-9._-]+\.patch)/g)].map(match => match[1]);
const only = process.argv[2]; // A named case also drives before-fix proofs.
let matched = false;
function write(file, text, mode) { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, text, mode === undefined ? undefined : { mode }); }
function record(body, code = 200) { return { body: Buffer.from(typeof body === "string" ? body : JSON.stringify(body)).toString("base64"), code }; }
function release(id) { return { tag_name: "v" + version, draft: false, prerelease: false, assets_url: api + `releases/${id}/assets` }; }
function assets() { return [asset, "release-key.asc", "SHA256SUMS", "SHA256SUMS.asc"].map(name => ({ name, state: "uploaded", size: 1, browser_download_url: "https://github.com/vanillagreencom/vgshell/releases/download/v" + version + "/" + name })); }
function sourceFile(bytes) { return { type: "file", encoding: "base64", size: bytes.length, content: bytes.toString("base64") }; }
function git(root, ...args) {
    const result = cp.spawnSync("git", ["-C", root, ...args], { encoding: "utf8", env: { PATH: "/usr/bin:/bin", HOME: tmp, GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null", GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@example.invalid", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@example.invalid", GIT_AUTHOR_DATE: "2026-01-01T00:00:00Z", GIT_COMMITTER_DATE: "2026-01-01T00:00:00Z" } });
    assert.equal(result.status, 0, result.stderr);
    return result.stdout.trim();
}
function publishSource(w) {
    w.source = git(w.root, "rev-parse", "HEAD");
    w.responses[api + "commits/" + w.source] = record({ sha: w.source });
    for (const file of ["flake.nix", "flake.lock", ...new Set(patches)]) w.responses[`${api}contents/${file}?ref=${w.source}`] = record(sourceFile(fs.readFileSync(path.join(w.root, file))));
}
function declareFloor(w, manager, floor) {
    const file = path.join(w.root, "bin/lib/engine.js"), before = fs.readFileSync(file, "utf8");
    const pattern = manager === "apt" ? /const DEBIAN_VERSION = "[^"]+"/g : new RegExp(manager + ": `[^`]+`", "g");
    assert.equal([...before.matchAll(pattern)].length, 1);
    const changed = before.replace(pattern, manager === "apt" ? "const DEBIAN_VERSION = " + JSON.stringify(floor) : manager + ": " + JSON.stringify(floor));
    assert.notEqual(changed, before);
    fs.writeFileSync(file, changed);
}
const assetList = api + "releases/1/assets?per_page=100&page=1";
function rpmRecords(responses, target, packages, declaredCount = packages.length) {
    const base = `https://download.copr.fedorainfracloud.org/results/${project}/${target}/`;
    const primary = zlib.gzipSync(Buffer.from(`<metadata xmlns="http://linux.duke.edu/metadata/common" packages="${declaredCount}">${packages.join("")}</metadata>`));
    const sum = crypto.createHash("sha256").update(primary).digest("hex");
    const href = `repodata/${sum}-primary.xml.gz`;
    responses[base + "repodata/repomd.xml"] = record(`<repomd xmlns="http://linux.duke.edu/metadata/repo"><data type="primary"><checksum type="sha256">${sum}</checksum><location href="${href}"/></data></repomd>`);
    responses[base + href] = { body: primary.toString("base64"), code: 200 };
    responses[base + "001/vgshell-quickshell.rpm"] = record("");
}
function rpmPackage(target, floor = engine.PACKAGE_FLOORS.dnf) {
    const split = floor.lastIndexOf("-");
    return `<package><name>vgshell-quickshell</name><arch>${target.slice(target.lastIndexOf("-") + 1)}</arch><version epoch="0" ver="${floor.slice(0, split)}" rel="${floor.slice(split + 1)}"/><location href="001/vgshell-quickshell.rpm"/></package>`;
}
function world(name) {
    const root = path.join(tmp, name), tools = path.join(root, "tools");
    fs.mkdirSync(tools, { recursive: true });
    for (const file of ["bin/lib/engine.js", "bin/lib/judge-files.js", "VERSION", "flake.nix", "flake.lock", "packaging/fedora/copr-project", ...new Set(patches)]) write(path.join(root, file), fs.readFileSync(path.join(repo, file)));
    const responses = {
        [aur]: record({ version: 5, type: "multiinfo", resultcount: 1, results: [{ Name: "vgshell-quickshell", Version: engine.PACKAGE_FLOORS.pacman }] }),
        [api + "releases/tags/v" + version]: record(release(1)),
        [assetList]: record(assets()),
        [api + "commits/main"]: record({ sha }),
    };
    for (const file of ["flake.nix", "flake.lock", ...new Set(patches)]) responses[`${api}contents/${file}?ref=${sha}`] = record(sourceFile(fs.readFileSync(path.join(repo, file))));
    for (const asset of assets()) responses[asset.browser_download_url] = record("");
    targets.forEach(target => rpmRecords(responses, target, [rpmPackage(target)]));
    write(path.join(tools, "curl"), `#!${process.execPath}
const fs = require("node:fs"), path = require("node:path");
const responses = JSON.parse(fs.readFileSync(path.join(__dirname, "responses.json")));
const url = process.argv.at(-1), row = responses[url];
if (!row) { console.error("unlisted fixture URL: " + url); process.exit(90); }
if (row.exit) process.exit(row.exit);
process.stdout.write(Buffer.from(row.body, "base64")); process.stdout.write("\\n" + row.code);
`, 0o755);
    write(path.join(tools, "qs"), `#!${process.execPath}
if (process.argv.slice(2).join(" ") !== "--version") process.exit(91);
process.stdout.write(require("node:fs").readFileSync(require("node:path").join(__dirname, "version.txt")));
`, 0o755);
    write(path.join(tools, "version.txt"), `Quickshell 0.3.2 (revision fixture, distributed by VGS ${engine.RELEASE} (package: vgshell-quickshell))`);
    const facts = { primary: { id: "pacman" }, holders: { qs: { path: path.join(tools, "qs"), owners: { pacman: "vgshell-quickshell" } } }, version: engine.DEBIAN_VERSION };
    write(path.join(root, "bin/vgshell-pkg"), `const fs = require("node:fs"), path = require("node:path");
const facts = JSON.parse(fs.readFileSync(path.join(__dirname, "../facts.json")));
if (process.argv[2] === "owner" && facts.ownerError) { console.error(facts.ownerError); process.exit(1); }
console.log(JSON.stringify(process.argv[2] === "owner" ? { manager: facts.primary.id, package: facts.holders.qs.owners[facts.primary.id], version: facts.version } : facts));
`);
    git(root, "init", "-q"); git(root, "add", "flake.nix", "flake.lock", ...new Set(patches)); git(root, "commit", "-qm", "engine source");
    const w = { root, tools, responses, facts };
    publishSource(w);
    return w;
}
function run(world, args, checker = path.join(repo, "scripts/check-packaging.js")) {
    write(path.join(world.tools, "responses.json"), JSON.stringify(world.responses));
    write(path.join(world.root, "facts.json"), JSON.stringify(world.facts));
    const result = cp.spawnSync(process.execPath, [checker, ...args, "--root", world.root], {
        encoding: "utf8", timeout: 30000,
        env: { PATH: world.searchPath || world.tools + ":" + path.dirname(process.execPath) + ":/usr/bin:/bin", HOME: world.root, TMPDIR: tmp, LC_ALL: "C" },
    });
    assert.equal(result.error, undefined, result.error?.message);
    let output;
    try { output = JSON.parse(result.stdout); } catch { throw new Error(result.stdout + result.stderr); }
    return { code: result.status, output };
}
function runSelected(world) {
    for (const file of ["scripts/check-packaging.js", "scripts/preflight-floor.js", "scripts/lib/engine-availability.js", "scripts/smoke/gpu-fence.sh", "scripts/smoke/row-inputs.sh"])
        write(path.join(world.root, file), fs.readFileSync(path.join(repo, file)), fs.statSync(path.join(repo, file)).mode);
    const source = fs.readFileSync(path.join(repo, "scripts/validate"), "utf8");
    const rows = source.split("\n").filter(line => line.startsWith('  "cli|engine publication availability|'));
    assert.equal(rows.length, 1);
    const table = /^rows=\(\n[\s\S]*?^\)/gm;
    assert.equal([...source.matchAll(table)].length, 1);
    write(path.join(world.root, "scripts/validate"), source.replace(table, "rows=(\n" + rows[0] + "\n)"));
    write(path.join(world.tools, "responses.json"), JSON.stringify(world.responses));
    write(path.join(world.root, "facts.json"), JSON.stringify(world.facts));
    const result = cp.spawnSync("/usr/bin/bash", ["scripts/validate", "cli", "--full"], {
        encoding: "utf8", timeout: 30000, cwd: world.root,
        env: { PATH: world.tools + ":" + path.dirname(process.execPath) + ":/usr/bin:/bin", HOME: world.root, TMPDIR: tmp, LC_ALL: "C", GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null", VGSHELL_WORLD_ROOT: process.env.VGSHELL_WORLD_ROOT || "" },
    });
    assert.equal(result.error, undefined, result.error?.message);
    const line = result.stdout.split("\n").find(line => line.startsWith("{"));
    assert.ok(line, result.stdout + result.stderr);
    return { code: result.status, output: JSON.parse(line) };
}
const publication = [
    ["published", () => {}, 0, "publication"],
    ["aur-unpublished", w => { w.responses[aur] = record({ version: 5, type: "multiinfo", resultcount: 0, results: [] }); }, 1, "aur"],
    ["aur-old", w => { w.responses[aur] = record({ version: 5, type: "multiinfo", resultcount: 1, results: [{ Name: "vgshell-quickshell", Version: engine.PACKAGE_FLOORS.pacman.replace(/-[0-9]+$/, "-0") }] }); }, 1, "aur"],
    ["aur-full-floor", w => declareFloor(w, "pacman", `0.3.3.r1.gabcdef0-${engine.RELEASE}`), 1, "aur"],
    ["aur-unreadable", w => { w.responses[aur] = record("<html>challenge</html>"); }, 77, "aur"],
    ["aur-partial", w => { w.responses[aur] = record({ version: 5, type: "multiinfo", resultcount: 1, results: [] }); }, 77, "aur"],
    ["transport", w => { w.responses[aur] = { exit: 28 }; }, 77, "aur"],
    ["copr-target-missing", w => { w.responses[`https://download.copr.fedorainfracloud.org/results/${project}/${targets.at(-1)}/repodata/repomd.xml`] = record("", 404); }, 1, "copr"],
    ["copr-package-missing", w => rpmRecords(w.responses, targets.at(-1), []), 1, "copr"],
    ["copr-rpm-missing", w => { w.responses[`https://download.copr.fedorainfracloud.org/results/${project}/${targets.at(-1)}/001/vgshell-quickshell.rpm`] = record("", 404); }, 1, "copr"],
    ["copr-old", w => rpmRecords(w.responses, targets.at(-1), [rpmPackage(targets.at(-1), engine.PACKAGE_FLOORS.dnf.replace(/-[0-9]+\./, "-0."))]), 1, "copr"],
    ["copr-full-floor", w => declareFloor(w, "dnf", `0.3.3-${engine.RELEASE}.abcdef0`), 1, "copr"],
    ["copr-unreadable", w => { w.responses[`https://download.copr.fedorainfracloud.org/results/${project}/${targets[0]}/repodata/repomd.xml`] = record("<repomd/>"); }, 77, "copr"],
    ["copr-incomplete-collection", w => rpmRecords(w.responses, targets[0], [rpmPackage(targets[0])], 2), 77, "copr"],
    ["debian-tag-asset-missing", w => { w.responses[assetList] = record(assets().filter(a => a.name !== asset)); }, 1, "debian"],
    ["debian-wrong-tag", w => { w.responses[api + "releases/tags/v" + version] = record({ ...release(1), tag_name: "v0.0.0" }); }, 77, "debian"],
    ["debian-signature-missing", w => { w.responses[assetList] = record(assets().filter(a => a.name !== "SHA256SUMS.asc")); }, 1, "debian"],
    ["debian-collection-unreadable", w => { w.responses[assetList] = record({}); }, 77, "debian"],
    ["debian-asset-on-next-page", w => { w.responses[assetList] = record(Array.from({ length: 100 }, (_, i) => ({ name: "other-" + i, state: "uploaded", size: 1, browser_download_url: "https://github.com/other" }))); w.responses[assetList.replace(/&page=1$/, "&page=2")] = record(assets()); }, 0, "publication"],
    ["nix-source-missing", w => { w.responses[api + "commits/" + w.source] = record("", 404); }, 1, "nix"],
    ["nix-lock-differs", w => { w.responses[`${api}contents/flake.lock?ref=${w.source}`] = record(sourceFile(Buffer.from("different"))); }, 1, "nix"],
    ["nix-content-incomplete", w => { w.responses[`${api}contents/flake.lock?ref=${w.source}`] = record({ ...sourceFile(Buffer.from("different")), size: 999 }); }, 77, "nix"],
    ["unreadable-outranks-known-gap", w => { w.responses[aur] = record({ version: 5, type: "multiinfo", resultcount: 0, results: [] }); w.responses[`${api}contents/flake.lock?ref=${w.source}`] = record({}); }, 77, "nix"],
    ["nix-public-candidate", w => { write(path.join(w.root, "flake.nix"), flake + "\n# committed candidate\n"); git(w.root, "add", "flake.nix"); git(w.root, "commit", "-qm", "candidate"); publishSource(w); write(path.join(w.root, "unrelated"), "local work"); git(w.root, "add", "unrelated"); git(w.root, "commit", "-qm", "unrelated private commit"); }, 0, "publication"],
];
function judgePublication(result, name, code, channel, contract = engine) {
    assert.equal(result.code, code, name + ": " + JSON.stringify(result));
    assert.equal(result.output.channel, channel, name);
    assert.equal(result.output.status, { 0: "pass", 1: "refuse", 77: "unreadable" }[code], name);
    assert.equal(result.output.release, engine.RELEASE, name);
    assert.deepEqual(result.output.checks.map(check => check.channel), ["aur", "copr", "debian", "nix"], name);
    if (code === 1) assert.equal(result.output.need, channel === "aur" ? contract.PACKAGE_FLOORS.pacman : channel === "copr" ? contract.PACKAGE_FLOORS.dnf : channel === "debian" ? asset : engine.RELEASE);
}
for (const [name, edit, code, channel] of publication) {
    if (only && only !== name) continue;
    matched = true;
    const w = world(name); edit(w);
    judgePublication(name === "nix-public-candidate" ? runSelected(w) : run(w, ["--engine-availability"]), name, code, channel, require(path.join(w.root, "bin/lib/engine.js")));
    console.log("ok " + name);
}
const installation = [
    ["installed-current", () => {}, 0],
    ["installed-absent", w => { fs.unlinkSync(path.join(w.tools, "qs")); w.searchPath = w.tools; }, 1],
    ["installed-old", w => write(path.join(w.tools, "version.txt"), `Quickshell (distributed by VGS ${engine.RELEASE - 1} (package: vgshell-quickshell))`), 1],
    ["installed-stock", w => write(path.join(w.tools, "version.txt"), "Quickshell 0.3.2"), 1],
    ["installed-wrong-owner", w => { w.facts.holders.qs.owners.pacman = "quickshell"; }, 1],
    ["installed-apt-current", w => { w.facts.primary.id = "apt"; w.facts.holders.qs.owners.apt = "vgshell-quickshell"; }, 0],
    ["installed-apt-old-package", w => { w.facts.primary.id = "apt"; w.facts.holders.qs.owners.apt = "vgshell-quickshell"; w.facts.version = engine.DEBIAN_VERSION.replace(/\+vgs[0-9]+/, "+vgs0"); }, 1],
    ["installed-apt-full-floor", w => { w.facts.primary.id = "apt"; w.facts.holders.qs.owners.apt = "vgshell-quickshell"; declareFloor(w, "apt", `0.3.3+gitabcdef0+vgs${engine.RELEASE}-1`); }, 1],
    ["installed-version-unreadable", w => write(path.join(w.tools, "qs"), "#!/bin/sh\nexit 1\n", 0o755), 77],
    ["installed-owner-timeout", w => { w.facts.holders.qs.owners.pacman = null; w.facts.ownerError = "vgshell: refused: query=pacman reason=failed error=ETIMEDOUT"; }, 77],
    ["installed-owner-spawn-failed", w => { w.facts.holders.qs.owners.pacman = null; w.facts.ownerError = "vgshell: refused: query=pacman reason=failed error=ENOENT"; }, 77],
];
for (const [name, edit, code] of installation) {
    if (only && only !== name) continue;
    matched = true;
    const w = world(name); edit(w);
    const result = run(w, ["--installed-engine"]);
    assert.equal(result.code, code, name + ": " + JSON.stringify(result));
    assert.equal(result.output.channel, "installed");
    assert.equal(result.output.need, engine.RELEASE);
    if (w.facts.ownerError) assert.ok(result.output.reason.includes(w.facts.ownerError), name + " preserves the package owner's failure");
    console.log("ok " + name);
}
for (const [name, old] of [["explicit-current", false], ["explicit-old", true]]) {
    if (only && only !== name) continue;
    matched = true;
    const w = world(name), executable = path.join(w.tools, "selected-qs");
    write(executable, `#!${process.execPath}\nconsole.log("Quickshell (distributed by VGS ${engine.RELEASE - Number(old)} (package: vgshell-quickshell))");\n`, 0o755);
    const result = run(w, ["--installed-engine", "--executable", executable]);
    assert.equal(result.code, old ? 1 : 0, name);
    assert.equal(result.output.channel, "installed", name);
    console.log("ok " + name + " judges the selected executable rather than PATH qs");
}
if (only) { assert.equal(matched, true, "unknown case: " + only); process.exit(0); }
// Removing the new instrument's refusal must make its own refusing case red.
const control = path.join(tmp, "control");
for (const file of ["scripts/check-packaging.js", "scripts/preflight-floor.js", "scripts/lib/engine-availability.js"]) write(path.join(control, file), fs.readFileSync(path.join(repo, file)));
const instrument = path.join(control, "scripts/lib/engine-availability.js");
const before = fs.readFileSync(instrument, "utf8"), needle = 'throw outcome("refuse", channel, need, reason, step);';
assert.equal(before.split(needle).length - 1, 1);
fs.writeFileSync(instrument, before.replace(needle, 'throw outcome("pass", channel, need, reason, step);'));
const w = world("control"); publication.find(row => row[0] === "aur-unpublished")[1](w);
assert.throws(() => judgePublication(run(w, ["--engine-availability"], path.join(control, "scripts/check-packaging.js")), "control", 1, "aur"), assert.AssertionError);
console.log("ok refusal mutation changes the refusing case to a detectable false pass");
