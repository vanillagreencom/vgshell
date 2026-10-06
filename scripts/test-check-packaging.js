#!/usr/bin/env node
// Controls for scripts/check-packaging.js, one table for every channel. Every
// row runs this repository's check with `--root` on a scratch data tree
// under its tmp/: the Arch recipes and the Fedora specs, the install tree
// manifest, VERSION, bin/vgshell (its preflight floors), the core requirements,
// each shipped plugin's manifest and docs/architecture/distribution.md (its
// licence line), committed to the tree's own git repository so the release-tag
// rule reads that repository alone. The tree holds no code: the check loads
// the judge and bin/vgshell-scan from its own repository, so a new import of
// the judge needs no change here. The pristine tree passes.
// Each other row plants one defect that reaches one rule in a fresh copy and
// asserts the exit status and the exact keyed first line. Every edit asserts
// it matched once and changed its file. A release step legitimately changes
// the recipes and bin/vgshell (a VERSION bump, a pinned sha256, a pkgver
// makepkg rewrote, a raised floor), so no row reads its expectation from
// this repository's current values: each reads them from the copy it
// edits, and a checksum row sets its checksum state first. A channel added
// to CHANNELS adds its rows to ROWS here.
"use strict";
const childProcess = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const repo = path.resolve(__dirname, "..");
const hasMakepkg = childProcess.spawnSync("makepkg", ["--version"], { encoding: "utf8" });
if (hasMakepkg.error) {
    // The freshness rule and every row that reaches it need makepkg.
    console.log("test-check-packaging: status=not-measured reason=makepkg-missing");
    process.exit(77);
}
const tmp = path.join(repo, "tmp", "test-check-packaging." + process.pid);
fs.rmSync(tmp, { recursive: true, force: true });
fs.mkdirSync(path.join(tmp, "home"), { recursive: true });
process.on("exit", () => fs.rmSync(tmp, { recursive: true, force: true }));

// Every check and git call runs with this environment and nothing else.
const basePath = path.dirname(process.execPath) + ":" + process.env.PATH;
const ENV = {
    HOME: path.join(tmp, "home"), LC_ALL: "C", TMPDIR: tmp, GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null",
    GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@example.invalid", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@example.invalid",
};
function git(...args) {
    const run = childProcess.spawnSync("git", args, { encoding: "utf8", env: { ...ENV, PATH: basePath } });
    if (run.status !== 0) throw new Error("git " + args.join(" ") + ": " + run.stderr);
    return run.stdout;
}

const pristine = path.join(tmp, "pristine");
const files = ["packaging/runtime-libraries.json", "packaging/channel-gaps.json", "flake.lock", "flake.nix", "install.sh", "packaging/install-tree.manifest", "packaging/xdg-desktop-portal/hyprland-portals.conf", "VERSION", "config/requirements.json", "bin/vgshell", "docs/architecture/distribution.md"];
for (const plugin of fs.readdirSync(path.join(repo, "shell", "plugins"))) {
    if (fs.existsSync(path.join(repo, "shell", "plugins", plugin, "manifest.json"))) files.push(`shell/plugins/${plugin}/manifest.json`);
}
for (const rel of files) {
    fs.mkdirSync(path.dirname(path.join(pristine, rel)), { recursive: true });
    fs.copyFileSync(path.join(repo, rel), path.join(pristine, rel));
    fs.chmodSync(path.join(pristine, rel), fs.statSync(path.join(repo, rel)).mode);
}
fs.cpSync(path.join(repo, "packaging", "arch"), path.join(pristine, "packaging", "arch"), { recursive: true });
for (const spec of ["vgshell.spec", "vgshell-git.spec"]) {
    fs.mkdirSync(path.join(pristine, "packaging", "fedora"), { recursive: true });
    fs.copyFileSync(path.join(repo, "packaging", "fedora", spec), path.join(pristine, "packaging", "fedora", spec));
}
git("init", "-q", pristine);
git("-C", pristine, "add", "-A");
git("-C", pristine, "commit", "-q", "-m", "pristine");

const sum = crypto.createHash("sha256").update("planted").digest("hex");

// The first value of KEY in a tree's .SRCINFO.
function srcinfo(tree, rel, key) {
    const m = new RegExp("^\\t" + key + " = (.*)$", "m").exec(fs.readFileSync(path.join(tree, rel), "utf8"));
    if (m === null) throw new Error(`srcinfo: refused: key=${key} path=${rel}`);
    return m[1];
}
// The package licence a tree's distribution.md states.
function docLicence(tree) {
    const m = new RegExp("^- The SPDX licence expression of a VGS package is `([^`]+)`\\.$", "m").exec(fs.readFileSync(path.join(tree, "docs/architecture/distribution.md"), "utf8"));
    if (m === null) throw new Error("docLicence: refused: no licence line");
    return m[1];
}
// The version of a tree's bin/vgshell floor for TOOL.
function floorOf(tree, tool) {
    const m = new RegExp("^" + tool + " +([0-9.]+) ", "m").exec(fs.readFileSync(path.join(tree, "bin/vgshell"), "utf8"));
    if (m === null) throw new Error("floor: refused: tool=" + tool);
    return m[1];
}
// The >= version of a hard dependency on NAME in a tree's vgshell .SRCINFO.
function constraintOf(tree, name) {
    const m = new RegExp("^\\tdepends = " + name + ">=([0-9.]+)$", "m").exec(fs.readFileSync(path.join(tree, "packaging/arch/vgshell/.SRCINFO"), "utf8"));
    if (m === null) throw new Error("constraint: refused: package=" + name);
    return m[1];
}

// The expected count, read here from the declarations and not from the
// check: every core and shipped-plugin requirement, and each preflight row
// whose probe command no requirement declares.
function countRequirements(tree) {
    const lists = [JSON.parse(fs.readFileSync(path.join(tree, "config/requirements.json"), "utf8"))];
    for (const plugin of fs.readdirSync(path.join(tree, "shell/plugins")))
        lists.push(JSON.parse(fs.readFileSync(path.join(tree, "shell/plugins", plugin, "manifest.json"), "utf8")).requirements || []);
    const all = lists.flat();
    const table = fs.readFileSync(path.join(tree, "bin/vgshell"), "utf8").split("preflight_floor='\n")[1].split("\n'\n")[0];
    const probes = table.split("\n").filter(Boolean).map(line => line.trim().split(/\s+/)[3]);
    return all.length + probes.filter(probe => !all.some(entry => entry.command === probe)).length
        + JSON.parse(fs.readFileSync(path.join(tree, "packaging/runtime-libraries.json"), "utf8")).length;
}

function fresh(name) {
    const dir = path.join(tmp, name);
    fs.cpSync(pristine, dir, { recursive: true });
    return dir;
}

// Replace the one match of the multi-line PATTERN in TREE/REL.
function edit(tree, rel, pattern, replacement) {
    const file = path.join(tree, rel);
    if (fs.lstatSync(file).isSymbolicLink()) throw new Error("edit: refused: symlink=" + file);
    const text = fs.readFileSync(file, "utf8");
    const regex = new RegExp(pattern, "gm");
    const matches = (text.match(regex) || []).length;
    if (matches !== 1) throw new Error(`edit: refused: matches=${matches} path=${rel} pattern=${pattern}`);
    const changed = text.replace(regex, replacement);
    if (changed === text) throw new Error("edit: refused: unchanged path=" + rel);
    fs.writeFileSync(file, changed);
}
function write(tree, rel, text) { fs.writeFileSync(path.join(tree, rel), text); }

// Set the vgshell recipe's one checksum in both the PKGBUILD and .SRCINFO of a
// copy, whatever it held: SKIP or a pin. Each file must hold exactly one
// checksum line, and must hold VALUE after the edit.
function setChecksum(tree, value) {
    for (const [rel, pattern, line] of [
        ["packaging/arch/vgshell/PKGBUILD", "^sha256sums=\\('[^']*'\\)$", `sha256sums=('${value}')`],
        ["packaging/arch/vgshell/.SRCINFO", "^\\tsha256sums = .*$", "\tsha256sums = " + value],
    ]) {
        const file = path.join(tree, rel);
        const text = fs.readFileSync(file, "utf8");
        const regex = new RegExp(pattern, "gm");
        const matches = (text.match(regex) || []).length;
        if (matches !== 1) throw new Error(`checksum: refused: matches=${matches} path=${rel}`);
        const changed = text.replace(regex, line);
        if (!changed.split("\n").includes(line)) throw new Error("checksum: refused: unset path=" + rel);
        fs.writeFileSync(file, changed);
    }
}

// Append a requirement to a copied plugin's manifest; PACKAGES keyed by
// manager id.
function addRequirement(tree, plugin, command, packages, optional) {
    const file = path.join(tree, "shell/plugins", plugin, "manifest.json");
    const manifest = JSON.parse(fs.readFileSync(file, "utf8"));
    const requirements = manifest.requirements || [];
    if (requirements.some(entry => entry.command === command)) throw new Error("plugin requirement: refused: declared=" + command);
    manifest.requirements = requirements.concat([{ command, packages, optional, purpose: "A planted requirement" }]);
    fs.writeFileSync(file, JSON.stringify(manifest));
}

// Replace OLD, which must occur exactly once, in each of RELS.
function replaceIn(tree, rels, old, replacement) {
    for (const rel of rels) {
        const file = path.join(tree, rel);
        const text = fs.readFileSync(file, "utf8");
        const count = text.split(old).length - 1;
        if (count !== 1) throw new Error(`replace: refused: matches=${count} path=${rel} text=${JSON.stringify(old)}`);
        fs.writeFileSync(file, text.replace(old, () => replacement));
    }
}

// A spec's value of TAG, or the first %changelog entry line for "*".
function specValue(tree, rel, tag) {
    const text = fs.readFileSync(path.join(tree, rel), "utf8");
    const m = tag === "*" ? /^%changelog\n(\* .*)$/m.exec(text) : new RegExp("^" + tag + ":\\s*(.*?)\\s*$", "m").exec(text);
    if (m === null) throw new Error(`spec: refused: tag=${tag} path=${rel}`);
    return m[1];
}
// The version a spec's Requires line on NAME carries, without its epoch.
function specFloor(tree, rel, name) {
    const m = new RegExp("^Requires:\\s+" + name + " >= (?:\\d+:)?(\\S+)$", "m").exec(fs.readFileSync(path.join(tree, rel), "utf8"));
    if (m === null) throw new Error(`spec: refused: floor=${name} path=${rel}`);
    return m[1];
}

function plantPluginRequirement(tree, command, pkg) {
    const file = path.join(tree, "shell/plugins/vgs.launcher/manifest.json");
    const manifest = JSON.parse(fs.readFileSync(file, "utf8"));
    const requirements = manifest.requirements || [];
    if (requirements.some(entry => entry.command === command)) throw new Error("plugin requirement: refused: declared=" + command);
    manifest.requirements = requirements.concat([{ command, packages: { pacman: pkg }, optional: true, purpose: "A planted requirement" }]);
    fs.writeFileSync(file, JSON.stringify(manifest));
}

// A PATH holding what the check runs except makepkg: git, and python3 for
// bin/vgshell-scan's interpreter line.
const farm = path.join(tmp, "path-farm");
fs.mkdirSync(farm);
for (const command of ["git", "python3"]) {
    const found = childProcess.spawnSync("sh", ["-c", 'command -v "$1"', "sh", command], { encoding: "utf8" }).stdout.trim();
    if (found === "") throw new Error("path farm: " + command + " is not on PATH");
    fs.symlinkSync(found, path.join(farm, command));
}

const SRC = "packaging/arch/vgshell/.SRCINFO";
const GIT_SRC = "packaging/arch/vgshell-git/.SRCINFO";
const ok = n => `check-packaging: ok channels=pacman,dnf,nix,install-pacman,install-dnf,install-nix requirements=${n}`;
const REL = "packaging/fedora/vgshell.spec";
const GIT = "packaging/fedora/vgshell-git.spec";
const SPECS = [REL, GIT];
const SCRIPTLET = "packaging/arch/vgshell/vgshell.install";
const GIT_SCRIPTLET = "packaging/arch/vgshell-git/vgshell-git.install";
const MESSAGE = "share/vgshell/bin/lib/post-install.txt";
const dnf = (recipe = "vgshell", scope = "core") => `channel=dnf recipe=${recipe} scope=${scope}`;
const firstPlugin = tree => fs.readdirSync(path.join(tree, "shell/plugins")).sort()[0];
const refused = key => "check-packaging: refused: " + key;
const where = (recipe = "vgshell") => `channel=pacman recipe=${recipe} scope=core`;

// name | setup(tree) | exit | first line (a function of the tree) | PATH |
// arguments
const ROWS = [
    ["Arch: a required shipped feature left optional is refused", t => {
        edit(t, SRC, "^\\tdepends = tesseract\\n", "");
        edit(t, SRC, "^(pkgbase = vgshell\\n)", "$1\toptdepends = tesseract: planted\n");
    }, 1, () => refused("requirement=tesseract package=tesseract want=depends channel=pacman recipe=vgshell scope=vgs.capture")],
    ["Arch: a hardware option promoted to required is refused", t => {
        edit(t, SRC, "^(pkgbase = vgshell\\n)", "$1\tdepends = ddcutil\n");
    }, 1, () => refused("extra=ddcutil field=depends channel=pacman recipe=vgshell")],
    ["Nix: a dropped required package is refused", t => edit(t, "flake.nix", "^        pkgs\\.qrencode\\n", ""),
        1, () => refused("requirement=qrencode package=qrencode want=runtimePackages channel=nix recipe=flake scope=vgs.network")],
    ["Nix: an optional package in the runtime closure is refused", t => edit(t, "flake.nix", "^(      runtimePackages = pkgs: \\[\\n)", "$1        pkgs.ddcutil\n"),
        1, () => refused("extra=ddcutil field=runtimePackages channel=nix recipe=flake")],
    ["installer: a dropped English data package is refused", t => edit(t, "install.sh", "^(pacman .*?) tesseract-data-eng( .*)$", "$1$2"),
        1, () => refused("requirement=library:capture-english package=tesseract-data-eng want=runtime_packages channel=install-pacman recipe=pacman scope=core")],
    ["installer: a dropped AUR requirement is refused", t => edit(t, "install.sh", "^(aur .*?) wlrctl$", "$1"),
        1, () => refused("requirement=wlrctl package=wlrctl want=runtime_packages channel=install-pacman recipe=pacman scope=vgs.jarvis")],
    ["Fedora installer: a dropped required package is refused", t => edit(t, "install.sh", "^(dnf .*?) qrencode( .*)$", "$1$2"),
        1, () => refused("requirement=qrencode package=qrencode want=runtime_packages channel=install-dnf recipe=dnf scope=vgs.network")],
    ["Nix installer: a dropped required package is refused", t => edit(t, "install.sh", "^(nix .*?) qrencode( .*)$", "$1$2"),
        1, () => refused("requirement=qrencode package=qrencode want=runtime_packages channel=install-nix recipe=nix scope=vgs.network")],
    ["a removed distribution gap is refused", t => {
        const file = path.join(t, "packaging/channel-gaps.json");
        const gaps = JSON.parse(fs.readFileSync(file, "utf8"));
        delete gaps.dnf.vsys;
        fs.writeFileSync(file, JSON.stringify(gaps));
    }, 1, () => refused("requirement=vsys package=unmapped want=Requires channel=dnf recipe=vgshell scope=vgs.agent-warden")],
    ["a broken official package gap needs its failure evidence", t => {
        const file = path.join(t, "packaging/channel-gaps.json");
        const gaps = JSON.parse(fs.readFileSync(file, "utf8"));
        delete gaps.nix["agent-browser"].failure;
        fs.writeFileSync(file, JSON.stringify(gaps));
    }, 1, () => refused("gap=evidence manager=nix command=agent-browser")],
    ["a broken official package gap needs a named failing test", t => {
        const file = path.join(t, "packaging/channel-gaps.json");
        const gaps = JSON.parse(fs.readFileSync(file, "utf8"));
        gaps.nix["agent-browser"].failure = "build failed";
        fs.writeFileSync(file, JSON.stringify(gaps));
    }, 1, () => refused("gap=evidence manager=nix command=agent-browser")],
    ["a broken official package gap expires with the pinned revision", t => {
        const file = path.join(t, "flake.lock");
        const lock = JSON.parse(fs.readFileSync(file, "utf8"));
        lock.nodes.nixpkgs.locked.rev = "0000000000000000000000000000000000000000";
        fs.writeFileSync(file, JSON.stringify(lock));
    }, 1, () => refused("gap=revision manager=nix command=agent-browser")],
    ["a gap with an available package is refused as stale", t => {
        const file = path.join(t, "shell/plugins/vgs.agent-warden/manifest.json");
        const manifest = JSON.parse(fs.readFileSync(file, "utf8"));
        manifest.requirements.find(row => row.command === "vsys").packages.dnf = "vsys";
        fs.writeFileSync(file, JSON.stringify(manifest));
    }, 1, () => refused("gap=stale manager=dnf command=vsys")],
    ["the committed recipes pass", () => {}, 0, tree => ok(countRequirements(tree))],
    ["Arch: a portal backend dependency is required", t => edit(t, SRC, "^\\tdepends = xdg-desktop-portal-gnome\\n", ""),
        1, () => refused("requirement=portal-backend:gnome package=xdg-desktop-portal-gnome want=depends channel=pacman recipe=vgshell scope=portal")],
    ["dnf: a portal backend dependency is required", t => replaceIn(t, SPECS, "Requires:       xdg-desktop-portal-gnome\n", ""),
        1, () => refused("requirement=portal-backend:gnome package=xdg-desktop-portal-gnome want=Requires channel=dnf recipe=vgshell scope=portal")],
    ["an unknown portal backend is refused", t => replaceIn(t, ["packaging/xdg-desktop-portal/hyprland-portals.conf"], "org.freedesktop.impl.portal.Settings=gnome", "org.freedesktop.impl.portal.Settings=planted"),
        1, () => refused("portal-backend=unknown backend=planted path=packaging/xdg-desktop-portal/hyprland-portals.conf")],
    ["a missing required runtime library is refused", t => edit(t, SRC, "^\\tdepends = libxkbcommon\\n", ""),
        1, () => refused("requirement=library:xkbcommon package=libxkbcommon want=depends " + where())],
    ["runtime library data rejects a duplicate identity", t => {
        const file = path.join(t, "packaging/runtime-libraries.json");
        const data = JSON.parse(fs.readFileSync(file, "utf8")); data.push(data[0]);
        fs.writeFileSync(file, JSON.stringify(data));
    }, 1, () => refused("libraries=shape")],
    ["a .SRCINFO older than its PKGBUILD is refused", t => edit(t, "packaging/arch/vgshell/PKGBUILD", "^pkgdesc=.*$", "pkgdesc='Changed without regenerating .SRCINFO'"),
        1, () => refused("srcinfo=stale recipe=vgshell")],
    ["a required core requirement in optdepends is refused", t => {
        edit(t, SRC, "^\\tdepends = nodejs(>=.*)?\\n", "");
        edit(t, SRC, "^(pkgbase = vgshell\\n)", "$1\toptdepends = nodejs: moved\n");
    }, 1, () => refused("requirement=node package=nodejs want=depends " + where())],
    ["a missing optional core requirement is refused", t => edit(t, SRC, "^\\toptdepends = bluez-utils: .*\\n", ""),
        1, () => refused("requirement=bluetoothctl package=bluez-utils want=depends-or-optdepends " + where())],
    ["a shipped plugin's listed requirement passes and counts", t => plantPluginRequirement(t, "vgs-already-provided", "file"), 0, tree => ok(countRequirements(tree))],
    ["a shipped plugin's unlisted requirement is refused", t => plantPluginRequirement(t, "vgs-planted", "vgs-planted-package"),
        1, () => refused("requirement=vgs-planted package=vgs-planted-package want=depends-or-optdepends channel=pacman recipe=vgshell scope=vgs.launcher")],
    // Floors from bin/vgshell's preflight table.
    ["a floored depends without its constraint is refused", t => edit(t, SRC, "^\\tdepends = quickshell>=.*$", "\tdepends = quickshell"),
        1, tree => refused(`floor=missing package=quickshell want=>=${floorOf(tree, "quickshell")} ` + where())],
    ["a floored depends below its floor is refused", t => edit(t, SRC, "^\\tdepends = nodejs>=.*$", "\tdepends = nodejs>=0"),
        1, tree => refused(`floor=below package=nodejs have=>=0 want=>=${floorOf(tree, "node")} ` + where())],
    // The floor rises one past the recipe's own constraint, so the recipe is
    // below it whatever both held before.
    ["a floor bump in bin/vgshell refuses the recipes until they follow", t => {
        const bumped = constraintOf(t, "hyprland").replace(/[0-9]+$/, n => String(Number(n) + 1));
        edit(t, "bin/vgshell", "^hyprland( +)[0-9.]+ ", `hyprland$1${bumped} `);
    }, 1, tree => refused(`floor=below package=hyprland have=>=${constraintOf(tree, "hyprland")} want=>=${floorOf(tree, "hyprland")} ` + where())],
    ["a floor makes an optional core requirement required", t => edit(t, "bin/vgshell", "^(preflight_floor='\\n)", "$1bluez-utils 0.1     ^([0-9.]+)   bluetoothctl --version\n"),
        1, () => refused("requirement=bluetoothctl package=bluez-utils want=depends " + where())],
    ["a floor tool no requirement declares is required by its tool name", t => edit(t, "bin/vgshell", "^(preflight_floor='\\n)", "$1planted    1.0     ^([0-9.]+)   planted --version\n"),
        1, () => refused("requirement=planted package=planted want=depends " + where())],
    ["a bin/vgshell without the floor table is refused", t => edit(t, "bin/vgshell", "^preflight_floor='$", "preflight_floors='"),
        1, () => refused("floors=unreadable path=bin/vgshell")],
    ["an empty floor table is refused", t => edit(t, "bin/vgshell", "^preflight_floor='\\n[\\s\\S]*?^'$", "preflight_floor='\n'"),
        1, () => refused("floors=empty path=bin/vgshell")],
    // The agree rule.
    ["recipes with different depends are refused", t => edit(t, GIT_SRC, "^(pkgbase = vgshell-git\\n)", "$1\tdepends = planted\n"),
        1, () => refused("extra=planted field=depends channel=pacman recipe=vgshell-git")],
    ["recipes with different optdepends are refused", t => edit(t, GIT_SRC, "^(pkgbase = vgshell-git\\n)", "$1\toptdepends = planted: a reason\n"),
        1, () => refused("optdepends=differ channel=pacman recipes=vgshell,vgshell-git")],
    // The pacman channel's recipe rules.
    ["a vgshell pkgver other than VERSION is refused", t => write(t, "VERSION", "9.9.9\n"),
        1, tree => refused(`pkgver=${srcinfo(tree, SRC, "pkgver")} version=9.9.9 recipe=vgshell`)],
    // Each checksum row sets the checksum state it tests first, so the rows
    // hold for an unpublished recipe (SKIP) and a pinned one alike.
    ["SKIP before the release tag exists passes", t => setChecksum(t, "SKIP"), 0, tree => ok(countRequirements(tree))],
    ["SKIP after the release tag exists is refused", t => {
        setChecksum(t, "SKIP");
        git("-C", t, "tag", "v" + srcinfo(t, SRC, "pkgver"));
    }, 1, tree => refused(`sha256sums=SKIP tag=v${srcinfo(tree, SRC, "pkgver")} recipe=vgshell`)],
    ["a pinned sum after the release tag exists passes", t => {
        setChecksum(t, sum);
        git("-C", t, "tag", "v" + srcinfo(t, SRC, "pkgver"));
    }, 0, tree => ok(countRequirements(tree))],
    ["a sum that is not lower-case hex is refused", t => setChecksum(t, sum.toUpperCase()),
        1, () => refused(`sha256sums=${sum.toUpperCase()} recipe=vgshell`)],
    // A compatibility entry in either recipe, naming the release package.
    ...[[SRC, "vgshell"], [GIT_SRC, "vgshell-git"]].flatMap(([source, recipe]) => ["conflicts", "replaces", "provides"].map(tag => [
        `${recipe}: ${tag} is refused`,
        t => edit(t, source, "^(\\tarch = any\\n)", `$1\t${tag} = vgshell\n`),
        1, () => refused(`${tag}=vgshell recipe=${recipe}`)])),
    ["vgshell: an arch other than any is refused", t => edit(t, SRC, "^\\tarch = any$", "\tarch = x86_64"), 1, () => refused("arch=x86_64 recipe=vgshell")],
    ["vgshell-git: an arch other than any is refused", t => edit(t, GIT_SRC, "^\\tarch = any$", "\tarch = x86_64"), 1, () => refused("arch=x86_64 recipe=vgshell-git")],
    ["vgshell-git: a missing git makedepends is refused", t => edit(t, GIT_SRC, "^\\tmakedepends = git\\n", ""), 1, () => refused("makedepends=missing package=git recipe=vgshell-git")],
    ["vgshell: another source is refused", t => edit(t, SRC, "^\\tsource = (.*)$", "\tsource = $1.planted"),
        1, tree => refused(`source=${srcinfo(pristine, SRC, "source")}.planted recipe=vgshell`)],
    // makepkg mirrors a git+ source with every ref the remote advertises.
    ["vgshell-git: a source is refused", t => edit(t, GIT_SRC, "^(\\tarch = any\\n)", "$1\tsource = vgshell::git+https://github.com/vanillagreencom/vgshell.git\n"),
        1, () => refused("source=vgshell::git+https://github.com/vanillagreencom/vgshell.git recipe=vgshell-git")],
    ["vgshell-git: another url is refused", t => edit(t, GIT_SRC, "^\\turl = .*$", "\turl = https://github.com/planted/vgshell"),
        1, () => refused("url=https://github.com/planted/vgshell recipe=vgshell-git")],
    // The clone stays and takes every blob.
    ["vgshell-git: a prepare() clone without the blob filter is refused", t => replaceIn(t, ["packaging/arch/vgshell-git/PKGBUILD"], "git clone --filter=blob:none --single-branch", "git clone --single-branch"),
        1, () => refused("fetch=missing recipe=vgshell-git")],
    // The clone stays in the file and leaves prepare().
    ["vgshell-git: the clone outside prepare() is refused", t => replaceIn(t, ["packaging/arch/vgshell-git/PKGBUILD"], "\nprepare() {\n", "\n_fetch() {\n"),
        1, () => refused("fetch=missing recipe=vgshell-git")],
    // The first-install text: shipped, and printed by each recipe's scriptlet.
    ["a manifest without the first-install text is refused", t => edit(t, "packaging/install-tree.manifest", "^f " + MESSAGE.replace(/\./g, "\\.") + "\\n", ""),
        1, () => refused(`message=unshipped path=${MESSAGE} manifest=packaging/install-tree.manifest`)],
    ["vgshell: a recipe without its scriptlet is refused", t => edit(t, SRC, "^\\tinstall = vgshell\\.install\\n", ""),
        1, () => refused("install=missing want=vgshell.install recipe=vgshell")],
    // post_install stays and prints nothing.
    ["a scriptlet that prints no first-install text is refused", t => { for (const rel of [SCRIPTLET, GIT_SCRIPTLET]) edit(t, rel, "^  cat /usr/" + MESSAGE.replace(/\./g, "\\.") + "$", "  true"); },
        1, () => refused("scriptlet=silent recipe=vgshell")],
    // The print stays in the file and leaves post_install.
    ["a scriptlet that prints the first-install text outside post_install is refused", t => { for (const rel of [SCRIPTLET, GIT_SCRIPTLET]) edit(t, rel, "^post_install\\(\\) \\{\\n", "post_install() {\n  true\n}\npost_remove() {\n"); },
        1, () => refused("scriptlet=silent recipe=vgshell")],
    ["scriptlets that differ are refused", t => edit(t, GIT_SCRIPTLET, "^(post_install\\(\\) \\{\\n)", "$1  echo planted\n"),
        1, () => refused("scriptlet=differs recipes=vgshell,vgshell-git")],
    // package() installs the tree alone, without the browser theme writer
    // and its rule.
    ["vgshell: a package() without SYSCONFDIR is refused", t => replaceIn(t, ["packaging/arch/vgshell/PKGBUILD"], " SYSCONFDIR=/etc ./packaging", " ./packaging"),
        1, () => refused("installer=missing recipe=vgshell")],
    ["vgshell-git: a package() without SYSCONFDIR is refused", t => replaceIn(t, ["packaging/arch/vgshell-git/PKGBUILD"], " SYSCONFDIR=/etc ./packaging", " ./packaging"),
        1, () => refused("installer=missing recipe=vgshell-git")],
    // The line stays in the file and leaves package().
    ["vgshell: the system install outside package() is refused", t => replaceIn(t, ["packaging/arch/vgshell/PKGBUILD"], "\npackage() {\n", "\nprepare() {\n"),
        1, () => refused("installer=missing recipe=vgshell")],
    // The dnf channel: the runtime dependency block is exactly the
    // requirements' set, with each floor at its epoch.
    ["dnf: a dropped Requires is refused", t => replaceIn(t, SPECS, "Requires:       git\n", ""),
        1, () => refused("requirement=git package=git want=Requires " + dnf())],
    ["dnf: an extra Requires is refused", t => replaceIn(t, SPECS, "Requires:       git\n", "Requires:       git\nRequires:       jq\n"),
        1, () => refused("extra=jq field=Requires channel=dnf recipe=vgshell")],
    ["dnf: a spec floor below the preflight is refused", t => { for (const spec of SPECS) edit(t, spec, "^(Requires:\\s+quickshell >= ).*$", "$10"); },
        1, tree => refused(`floor=mismatch package=quickshell have=0 want=${floorOf(tree, "quickshell")} ` + dnf())],
    ["dnf: a spec floor with no version is refused", t => { edit(t, REL, "^(Requires:\\s+hyprland) >= .*$", "$1"); edit(t, GIT, "^(Requires:\\s+hyprland) >= .*$", "$1"); },
        1, tree => refused(`floor=mismatch package=hyprland have=none want=${floorOf(tree, "hyprland")} ` + dnf())],
    // The Arch recipes follow the raised floor, so the dnf channel is the one
    // that refuses.
    ["dnf: a raised preflight floor is refused", t => {
        const bumped = specFloor(t, REL, "quickshell").replace(/[0-9]+$/, n => String(Number(n) + 1));
        edit(t, "bin/vgshell", "^quickshell( +)[0-9.]+ ", `quickshell$1${bumped} `);
        for (const recipe of ["vgshell", "vgshell-git"]) edit(t, `packaging/arch/${recipe}/.SRCINFO`, "^\\tdepends = quickshell>=.*$", "\tdepends = quickshell>=" + bumped);
    }, 1, tree => refused(`floor=mismatch package=quickshell have=${specFloor(tree, REL, "quickshell")} want=${floorOf(tree, "quickshell")} ` + dnf())],
    ["dnf: an explicit epoch 0 on a floor passes", t => { edit(t, REL, "^(Requires:\\s+hyprland >= )", "$10:"); edit(t, GIT, "^(Requires:\\s+hyprland >= )", "$10:"); },
        0, tree => ok(countRequirements(tree))],
    ["dnf: a node floor without its epoch is refused", t => { edit(t, REL, "^(Requires:\\s+nodejs >= )1:", "$1"); edit(t, GIT, "^(Requires:\\s+nodejs >= )1:", "$1"); },
        1, () => refused("epoch=mismatch package=nodejs have=0 want=1 " + dnf())],
    ["dnf: a node floor with another epoch is refused", t => { edit(t, REL, "^(Requires:\\s+nodejs >= )1:", "$12:"); edit(t, GIT, "^(Requires:\\s+nodejs >= )1:", "$12:"); },
        1, () => refused("epoch=mismatch package=nodejs have=2 want=1 " + dnf())],
    ["dnf: an epoch on an epoch-0 package is refused", t => { edit(t, REL, "^(Requires:\\s+quickshell >= )", "$11:"); edit(t, GIT, "^(Requires:\\s+quickshell >= )", "$11:"); },
        1, () => refused("epoch=mismatch package=quickshell have=1 want=0 " + dnf())],
    ["dnf: an optional requirement as Requires is refused", t => replaceIn(t, SPECS, "Recommends:     bluez\n", "Requires:       bluez\n"),
        1, () => refused("extra=bluez field=Requires channel=dnf recipe=vgshell")],
    ["dnf: an extra Recommends is refused", t => replaceIn(t, SPECS, "Recommends:     brightnessctl\n", "Recommends:     brightnessctl\nRecommends:     jq\n"),
        1, () => refused("extra=jq field=Recommends channel=dnf recipe=vgshell")],
    ["dnf: a renamed dnf package is refused", t => {
        const file = path.join(t, "config/requirements.json");
        const data = JSON.parse(fs.readFileSync(file, "utf8"));
        const hits = data.filter(r => r.command === "node");
        if (hits.length !== 1) throw new Error("rename: refused: node requirements=" + hits.length);
        hits[0].packages.dnf = "nodejs22";
        fs.writeFileSync(file, JSON.stringify(data, null, 2) + "\n");
    }, 1, () => refused("requirement=node package=nodejs22 want=Requires " + dnf())],
    ["dnf: a plugin's optional requirement must be recommended", t => addRequirement(t, firstPlugin(t), "wf-recorder", { dnf: "wf-recorder" }, true),
        1, tree => refused("requirement=wf-recorder package=wf-recorder want=Recommends " + dnf("vgshell", firstPlugin(tree)))],
    ["dnf: a plugin's required requirement must be required", t => addRequirement(t, firstPlugin(t), "vgs-required-new", { pacman: "file", dnf: "vgs-required-new" }, false),
        1, tree => refused("requirement=vgs-required-new package=vgs-required-new want=Requires " + dnf("vgshell", firstPlugin(tree)))],
    ["dnf: a requirement with no dnf package has no Fedora line", t => addRequirement(t, firstPlugin(t), "checkupdates", { pacman: "pacman-contrib" }, true),
        0, tree => ok(countRequirements(tree))],
    ["dnf: an unreadable dependency line is refused", t => { edit(t, REL, "^(Requires:\\s+quickshell) >= ", "$1 > "); edit(t, GIT, "^(Requires:\\s+quickshell) >= ", "$1 > "); },
        1, tree => refused("line=unreadable spec=vgshell.spec text=Requires:       quickshell > " + fs.readFileSync(path.join(tree, REL), "utf8").match(/^Requires:\s+quickshell > (\S+)$/m)[1])],
    // The same lines in another order: the dependency sets agree, the blocks
    // do not.
    ["dnf: blocks that differ are refused", t => replaceIn(t, [REL], "Recommends:     bluez\nRecommends:     brightnessctl\n", "Recommends:     brightnessctl\nRecommends:     bluez\n"),
        1, () => refused("block=differs specs=vgshell.spec,vgshell-git.spec")],
    ["dnf: a missing block marker is refused", t => replaceIn(t, [GIT], "# end runtime dependencies\n", ""),
        1, () => refused("block=missing spec=vgshell-git.spec")],
    ["dnf: a Version off VERSION is refused", t => edit(t, REL, "^(Version:\\s+).*$", "$19.9.9"),
        1, tree => refused(`version=mismatch spec=vgshell.spec have=9.9.9 want=${fs.readFileSync(path.join(tree, "VERSION"), "utf8").trim()}`)],
    ["dnf: a changelog entry off the version is refused", t => edit(t, REL, "^(\\* .* - )[^\\s]+$", "$10.0.0-1"),
        1, tree => refused(`changelog=mismatch spec=vgshell.spec want=...- ${specValue(tree, REL, "Version")}-${specValue(tree, REL, "Release").replace("%{?dist}", "")} have=${specValue(tree, REL, "*")}`)],
    ...[[REL, "vgshell.spec"], [GIT, "vgshell-git.spec"]].flatMap(([rel, spec]) => ["Conflicts", "Obsoletes", "Provides"].map(tag => [
        `dnf: ${tag} in ${spec} is refused`,
        t => edit(t, rel, "^(BuildArch:\\s+noarch\\n)", `$1${tag}:      vgshell\n`),
        1, () => refused(`${tag.toLowerCase()}=vgshell spec=${spec}`)])),
    ["dnf: a vgshell-git changelog entry is refused", t => replaceIn(t, [GIT], "\n%changelog\n", "\n%changelog\n* Mon Sep 28 2026 A <a@b> - 0-1\n- x\n"),
        1, () => refused("changelog=entries spec=vgshell-git.spec")],
    ["dnf: an arch-bound spec is refused", t => replaceIn(t, [REL], "BuildArch:      noarch", "BuildArch:      x86_64"),
        1, () => refused("buildarch=x86_64 spec=vgshell.spec want=noarch")],
    ["dnf: a licence that differs is refused", t => edit(t, GIT, "^(License:\\s+).*$", "$1MIT"),
        1, () => refused("tag=differs name=License specs=vgshell.spec,vgshell-git.spec")],
    ["dnf: an install section that differs is refused", t => replaceIn(t, [GIT], "PREFIX=%{_prefix} SYSCONFDIR", "PREFIX=/usr/local SYSCONFDIR"),
        1, () => refused("section=differs name=%install specs=vgshell.spec,vgshell-git.spec")],
    ["dnf: a %post that differs is refused", t => replaceIn(t, [GIT], '"$1" -eq 1', '"$1" -ge 1'),
        1, () => refused("section=differs name=%post specs=vgshell.spec,vgshell-git.spec")],
    // Both specs print on an upgrade too.
    ["dnf: a %post off the first-install text is refused", t => replaceIn(t, SPECS, '"$1" -eq 1', '"$1" -ge 1'),
        1, () => refused("post=mismatch specs=vgshell.spec,vgshell-git.spec")],
    ["dnf: an install off the shared installer is refused", t => replaceIn(t, SPECS, "DESTDIR=%{buildroot} PREFIX=%{_prefix} SYSCONFDIR=%{_sysconfdir} packaging/install-system.sh", "make install"),
        1, () => refused("install=missing want=DESTDIR=%{buildroot} PREFIX=%{_prefix} SYSCONFDIR=%{_sysconfdir} packaging/install-system.sh")],
    // The tree alone, without the browser theme writer and its rule.
    ["dnf: an install without SYSCONFDIR is refused", t => replaceIn(t, SPECS, " SYSCONFDIR=%{_sysconfdir} packaging/install-system.sh", " packaging/install-system.sh"),
        1, () => refused("install=missing want=DESTDIR=%{buildroot} PREFIX=%{_prefix} SYSCONFDIR=%{_sysconfdir} packaging/install-system.sh")],
    ["dnf: a check off the manifest checker is refused", t => replaceIn(t, SPECS, "scripts/check-install-tree.sh %{buildroot} %{_prefix} %{_sysconfdir}", "true"),
        1, () => refused("check=missing want=scripts/check-install-tree.sh %{buildroot} %{_prefix} %{_sysconfdir}")],
    ["dnf: a check of the tree without its system files is refused", t => replaceIn(t, SPECS, "%{_prefix} %{_sysconfdir}\n", "%{_prefix}\n"),
        1, () => refused("check=missing want=scripts/check-install-tree.sh %{buildroot} %{_prefix} %{_sysconfdir}")],
    ["dnf: %files without the browser theme writer is refused", t => replaceIn(t, SPECS, "%{_bindir}/vgshell-browser-policy\n", ""),
        1, () => refused("files=missing want=%{_bindir}/vgshell-browser-policy")],
    // The rule stays listed and loses its mode and its noreplace.
    ["dnf: %files with a plain sudoers rule is refused", t => replaceIn(t, SPECS, "%attr(0440,root,root) %config(noreplace) %{_sysconfdir}", "%{_sysconfdir}"),
        1, () => refused("files=missing want=%attr(0440,root,root) %config(noreplace) %{_sysconfdir}/sudoers.d/vgshell-theme-browser")],
    ["dnf: %files without the autostart entry is refused", t => replaceIn(t, SPECS, "%config(noreplace) %{_sysconfdir}/xdg/autostart/vgshell.desktop\n", ""),
        1, () => refused("files=missing want=%config(noreplace) %{_sysconfdir}/xdg/autostart/vgshell.desktop")],
    ["dnf: a renamed package is refused", t => replaceIn(t, [REL], "Name:           vgshell\n", "Name:           vgs2\n"),
        1, () => refused("name=mismatch spec=vgshell.spec have=vgs2 want=vgshell")],
    // The requirement read never passes empty.
    ["an unparsable core requirement file is refused", t => write(t, "config/requirements.json", "[\n"),
        1, () => refused("requirements=unreadable path=config/requirements.json")],
    ["a core list the judge refuses is refused", t => edit(t, "config/requirements.json", '"command": "node"', '"command": "node planted"'),
        1, () => refused("requirements=refused path=config/requirements.json")],
    ["an empty core list is refused", t => write(t, "config/requirements.json", "[]\n"), 1, () => refused("requirements=empty scope=core")],
    // Without makepkg every other rule still judges, and a clean tree is not
    // measured rather than passed.
    ["without makepkg a passing tree is not measured", () => {}, 77, () => "check-packaging: status=not-measured reason=makepkg-missing channel=pacman", farm],
    ["an unknown argument is refused", () => {}, 2, () => refused("argument=--bogus"), undefined, ["--bogus"]],
    ["--root without a directory is refused", () => {}, 2, () => refused("argument=--root"), undefined, ["--root"]],
    // A data root whose own judge and scan would refuse still passes: both
    // come from the checker's repository.
    ["the judge and the scan load from the checker's repository", t => {
        if (fs.existsSync(path.join(t, "shell/Core")) || fs.existsSync(path.join(t, "bin/lib"))) throw new Error("data root: refused: code=present");
        fs.mkdirSync(path.join(t, "shell/Core"), { recursive: true });
        fs.mkdirSync(path.join(t, "bin/lib"), { recursive: true });
        fs.writeFileSync(path.join(t, "shell/Core/PluginLogic.js"), "planted: not a library\n");
        fs.writeFileSync(path.join(t, "bin/lib/qml-library.js"), "throw new Error('planted loader');\n");
        fs.writeFileSync(path.join(t, "bin/vgshell-scan"), "#!/bin/sh\nexit 9\n", { mode: 0o755 });
    }, 0, tree => ok(countRequirements(tree))],
    // The licence: docs/architecture/distribution.md
    // recipe state one expression.
    ["a doc licence the recipes do not state is refused", t => edit(t, "docs/architecture/distribution.md", "^(- The SPDX licence expression of a VGS package is `)[^`]+(`\\.)$", "$1MIT$2"),
        1, tree => refused(`licence=mismatch channel=pacman recipe=vgshell have=${JSON.stringify(srcinfo(tree, SRC, "license"))} want="MIT"`)],
    ["a doc with no licence line is refused", t => edit(t, "docs/architecture/distribution.md", "^- The SPDX licence expression of a VGS package is .*\\n", ""),
        1, () => refused("licence-doc=unreadable path=docs/architecture/distribution.md")],
    ["vgshell-git: a recipe licence the doc does not state is refused", t => edit(t, GIT_SRC, "^(\\tlicense = ).*$", "$1MIT"),
        1, tree => refused(`licence=mismatch channel=pacman recipe=vgshell-git have="MIT" want=${JSON.stringify(docLicence(tree))}`)],
    ["dnf: a spec licence the doc does not state is refused", t => { for (const spec of SPECS) edit(t, spec, "^(License:\\s+).*$", "$1MIT"); },
        1, tree => refused(`licence=mismatch channel=dnf recipe=vgshell have="MIT" want=${JSON.stringify(docLicence(tree))}`)],
    ["without makepkg a refused rule still fails", t => edit(t, SRC, "^\\tarch = any$", "\tarch = x86_64"), 1, () => refused("arch=x86_64 recipe=vgshell"), farm],
];

let failures = 0;
ROWS.forEach(([name, setup, wantExit, wantLine, pathValue, args], i) => {
    let status, first, out = "";
    try {
        const tree = fresh("row-" + i);
        setup(tree);
        const run = childProcess.spawnSync(process.execPath, [path.join(repo, "scripts/check-packaging.js"), ...(args || ["--root", tree])], { encoding: "utf8", env: { ...ENV, PATH: pathValue || basePath } });
        out = run.stdout + run.stderr;
        status = run.status;
        first = run.stdout.split("\n")[0];
        if (status === wantExit && first === wantLine(tree)) {
            console.log("  ok    " + name);
            return;
        }
        console.log(`  FAIL  ${name}: exit=${status} want=${wantExit} first=[${first}] want=[${wantLine(tree)}]`);
    } catch (e) {
        console.log(`  FAIL  ${name}: ${e.message}`);
    }
    failures += 1;
    if (out !== "") console.log(out.replace(/^/gm, "        "));
});
if (failures > 0) {
    console.log("test-check-packaging: failed=" + failures);
    process.exit(1);
}
console.log("test-check-packaging: ok");
