#!/usr/bin/env node
// Check every distribution recipe in this repository offline against the
// requirements VGS declares. One checker serves every channel.
//
//   node scripts/check-packaging.js [--root DIR]
//
// DIR, this repository by default, holds the data judged: VERSION,
// bin/vgshell's preflight_floor table, config/requirements.json, the plugins
// under shell/plugins, packaging/arch, packaging/fedora,
// packaging/xdg-desktop-portal/hyprland-portals.conf,
// packaging/install-tree.manifest, docs/architecture/distribution.md, and
// the git repository the release-tag lookup reads. The judge, its loader and
// bin/vgshell-scan always come from this script's own repository, so a data
// root needs none of their code.
//
// One reader, readRequirements, builds the normalized requirement list:
//   - config/requirements.json, the core's commands, and each shipped
//     plugin's manifest `requirements`, listed by bin/vgshell-scan and judged
//     by shell/Core/PluginLogic.js;
//   - bin/vgshell's preflight_floor table, the versions `vgshell run` refuses to
//     start below. A row attaches to the first requirement whose command is
//     the row's probe command, else it adds one. A row makes its
//     requirement required, and names its package: the declared package for
//     a manager, else the row's tool name. `present` sets no version.
// Each entry is { scope, command, packages, optional, onRequest, floor,
// tool }: scope `core` or the plugin id, command is the normalized requirement
// name, including a D-Bus name or a NetworkManager VPN service,
// packages keyed by manager id, onRequest whether the requirement declares
// `"install": "on-request"`, floor a dotted version or null, tool the
// preflight row's tool or null. A preflight row that lands on an on-request
// requirement is refused: `vgshell run` checks the floor before any
// Requirements section can install the package.
//
// CHANNELS holds one entry per channel whose recipes live here, keyed by
// the package manager id. An entry names its recipes and reads each one
// into hard and soft dependencies; its fields set how the shared rules
// judge it; its `rules` hold the channel's own recipe rules and its
// `freshness` any check against generated metadata. Every channel gets the
// shared rules, per recipe, in this order:
//   requirement  each requirement's package (the first of the entry's
//                `managers` it names) is a hard dependency when it has a
//                floor or is required and not on request; an on-request
//                one is a soft dependency, which its plugin's Requirements
//                section installs; any other one is a soft dependency when
//                the entry is `exact`, else hard or soft; `requiredOnly`
//                channels install no soft dependency
//   floor        a floored hard dependency is constrained `>=` the floor:
//                exactly the floor when the entry is `floorExact`, else at
//                or above it; under `floorExact` a hard dependency with no
//                floor carries no constraint. With `epochs`, the
//                constraint's epoch is the package's epoch there, else 0
//   portal       every backend named by the shipped Hyprland portals.conf is
//                a hard dependency of the system package recipes that ship it
//   on-request   no hard dependency is the package of an on-request
//                requirement, and no requirement installed with VGS wants
//                the package of an on-request one
//   extra        no hard dependency the required union and portal route do not
//                ask for; an `exact` channel also refuses extra soft dependencies
//   agree        every recipe of the channel declares the same hard and the
//                same soft dependencies
// Before any channel: packaging/install-tree.manifest lists MESSAGE, the
// file of the installed tree every package prints on a first install.
// pacman (packaging/arch/{vgshell,vgshell-git}/.SRCINFO): depends and optdepends;
// optdepends may name more than the requirements. Hard dependencies are
// exactly the required union plus portal backends. vgshell: pkgver is VERSION's
// line; arch is any; source is the release tarball URL; one sha256sums entry, SKIP
// only while the tag v<pkgver> does not exist, otherwise 64 lower-case hex
// digits. vgshell-git: arch is any; makedepends holds git; no source; url is
// the repository URL; the PKGBUILD's prepare() holds GIT_CLONE, the clone of
// main alone. Both shell recipes: no conflicts, replaces or provides entry, refused as
// <tag>=<value> recipe=<name>; install is <pkgname>.install,
// the scriptlet beside the PKGBUILD; its post_install prints MESSAGE under
// /usr and runs the installed first-start helper; the two scriptlets are the same text; the PKGBUILD's package()
// holds PACMAN_INSTALL, the system install with SYSCONFDIR, so the package
// ships the browser theme writer, its sudoers rule and the Hyprland portal
// preference. Freshness, last: each .SRCINFO is exactly
// `makepkg --printsrcinfo` of the PKGBUILD beside it.
// dnf (packaging/fedora/{vgshell,vgshell-git}.spec): the Requires and Recommends
// lines between `# begin runtime dependencies` and `# end runtime
// dependencies`, the requirements' set plus portal backends. The block is the same in
// both specs; both are noarch, named for their package, share License, URL,
// BuildRequires and the %build, %install, %check, %files and %post
// sections, install through packaging/install-system.sh with SYSCONFDIR,
// check the tree with scripts/check-install-tree.sh and SYSCONFDIR, list
// the browser theme writer, its sudoers rule, 0440 and noreplace, the XDG
// autostart entry, noreplace, and the Hyprland portal preference, noreplace,
// in %files, and print MESSAGE from %post and run first-start on a first install only. vgshell.spec's Version is VERSION's line and
// its newest %changelog entry is that version at its Release. vgshell-git.spec
// ends with an empty %changelog, which packaging/fedora/srpm.sh fills. Neither
// spec has a Conflicts, Obsoletes or Provides tag, refused as
// <tag lowercase>=<value> spec=<file>.
// The dedicated vgshell-quickshell engine instead provides versioned
// quickshell and conflicts with both stock engine package names. Its pinned
// source, shared patch bytes, checksums and channel integration are checked
// separately by engineRules.
// Licence, after every channel: the shell package licence expression
// docs/architecture/distribution.md, its line
// "- The SPDX licence expression of a VGS shell package is `<expr>`.", equals
// every recipe's: each .SRCINFO's license and each spec's License.
//
// Exit 0 prints `check-packaging: ok channels=<ids> requirements=<n>`, n
// the entries of the normalized list. Exit 1 prints one keyed first line,
// `check-packaging: refused: <key>=<value> ...`, detail after it. Exit 77
// prints `check-packaging: status=not-measured reason=<tool>-missing
// channel=<id>` when every other rule passed and a freshness tool is not on
// PATH; that is not a pass. Exit 2: an argument. The judge's loader refuses
// an unloadable library with its own keyed line, `qml-library: refused:
// ...`, and exit 2. An argument other than `--root DIR` is refused as
// `argument=<arg>`, exit 2.
"use strict";
const childProcess = require("node:child_process");
const fs = require("node:fs");
const crypto = require("node:crypto");
const os = require("node:os");
const path = require("node:path");
const { parseFloors, DOTTED } = require("./preflight-floor.js");

// The repository this script runs from: the judge, its loader and the scan.
const codeRoot = path.resolve(__dirname, "..");
// The data judged: codeRoot, or --root DIR.
const root = (() => {
    const args = process.argv.slice(2);
    if (args.length === 0) return codeRoot;
    if (args.length === 2 && args[0] === "--root" && args[1] !== "") return path.resolve(args[1]);
    process.stdout.write("check-packaging: refused: argument=" + args.join(" ") + "\n");
    return process.exit(2);
})();
const REPO_URL = "https://github.com/vanillagreencom/vgshell";
// The first-install text, relative to the install prefix. A package manager
// runs no VGS code at install, so each channel's scriptlet prints this file.
const MESSAGE = "share/vgshell/bin/lib/post-install.txt";
const FIRST_START = "share/vgshell/bin/lib/first-start.sh";
const MANIFEST = "packaging/install-tree.manifest";
const PORTALS_CONF = "packaging/xdg-desktop-portal/hyprland-portals.conf";
const AUTOSTART_EXEC = "Exec=$prefix/bin/vgshell start";
// The system install every Arch recipe's package() runs.
const PACMAN_INSTALL = 'DESTDIR="$pkgdir" PREFIX=/usr SYSCONFDIR=/etc ./packaging/install-system.sh';
// The vgshell-git fetch. makepkg clones a git+ source as a mirror of every ref
// the remote advertises, GitHub's refs/pull/* among them; this takes main's
// commits, trees and tags and only the blobs of its checkout.
const GIT_CLONE = 'git clone --filter=blob:none --single-branch --branch main -- "$url.git" "$srcdir/vgshell"';
const PORTAL_BACKEND_PACKAGES = {
    pacman: { gnome: "xdg-desktop-portal-gnome", gtk: "xdg-desktop-portal-gtk", hyprland: "xdg-desktop-portal-hyprland" },
    dnf: { gnome: "xdg-desktop-portal-gnome", gtk: "xdg-desktop-portal-gtk", hyprland: "xdg-desktop-portal-hyprland" },
};

const scratchDirs = [];
process.on("exit", () => { for (const dir of scratchDirs) fs.rmSync(dir, { recursive: true, force: true }); });

// The distribution indexes cannot supply these commands. Each gap must
// still name a required command with no mapping on that channel. A gap is
// "no official package", or, for nix, an official package broken at the
// locked nixpkgs revision ({ reason, revision, failure }), or, for dnf, a
// package only its upstream publishes ({ reason, route, source }: reason
// DNF_UPSTREAM, route one line naming an https address, source one line
// naming where the route is stated).
const DNF_UPSTREAM = "no dnf repository package";
function readGaps(requirements) {
    let gaps;
    try { gaps = JSON.parse(readText("packaging/channel-gaps.json", "gaps=unreadable")); }
    catch (error) { refuse("gaps=unreadable", error.message); }
    if (gaps === null || typeof gaps !== "object" || Array.isArray(gaps)) refuse("gaps=shape");
    for (const [manager, commands] of Object.entries(gaps)) {
        if (!["apt", "dnf", "nix"].includes(manager) || commands === null || typeof commands !== "object" || Array.isArray(commands)) refuse("gaps=shape");
        for (const [command, evidence] of Object.entries(commands)) {
            if (evidence !== "no official package" && manager === "dnf") {
                const line = value => typeof value === "string" && value.trim() !== "" && !/[\r\n]/.test(value);
                if (evidence === null || typeof evidence !== "object" || Array.isArray(evidence)
                        || Object.keys(evidence).sort().join(",") !== "reason,route,source"
                        || evidence.reason !== DNF_UPSTREAM
                        || !line(evidence.route) || !/\bhttps:\/\/\S+/.test(evidence.route)
                        || !line(evidence.source))
                    refuse(`gap=evidence manager=${manager} command=${command}`);
            } else if (evidence !== "no official package") {
                if (manager !== "nix" || evidence === null || typeof evidence !== "object" || Array.isArray(evidence)
                        || Object.keys(evidence).sort().join(",") !== "failure,reason,revision"
                        || evidence.reason !== "official-package-broken"
                        || typeof evidence.revision !== "string" || !/^[a-f0-9]{40}$/.test(evidence.revision)
                        || typeof evidence.failure !== "string"
                        || !/^(?:[a-zA-Z_][a-zA-Z0-9_]*::)+test_[a-zA-Z0-9_]+$/.test(evidence.failure))
                    refuse(`gap=evidence manager=${manager} command=${command}`);
                let revision;
                try { revision = JSON.parse(readText("flake.lock", "lock=unreadable")).nodes.nixpkgs.locked.rev; }
                catch (error) { refuse("lock=unreadable", error.message); }
                if (evidence.revision !== revision) refuse(`gap=revision manager=${manager} command=${command}`);
            }

            const rows = requirements.filter(row => row.command === command && !row.optional);
            if (rows.length === 0 || rows.some(row => packageOf(row, [manager]) !== undefined))
                refuse(`gap=stale manager=${manager} command=${command}`);
        }
    }
    return gaps;
}

function refuse(key, ...detail) {
    process.stdout.write("check-packaging: refused: " + key + "\n" + detail.filter(line => line !== "").map(line => line + "\n").join(""));
    process.exit(1);
}

function readText(rel, key) {
    try {
        return fs.readFileSync(path.join(root, rel), "utf8");
    } catch (e) {
        return refuse(key + " path=" + rel, e.code || String(e));
    }
}

function readPortalBackends() {
    const backends = new Set();
    let inPreferred = false;
    for (const raw of readText(PORTALS_CONF, "portals=unreadable").split("\n")) {
        const line = raw.trim();
        if (line === "") continue;
        if (line.startsWith("#") || line.startsWith(";")) continue;
        const section = /^\[([^\]]+)\]$/.exec(line);
        if (section !== null) {
            inPreferred = section[1] === "preferred";
            continue;
        }
        if (!inPreferred) continue;
        const equals = line.indexOf("=");
        if (equals === -1) continue;
        for (const name of line.slice(equals + 1).split(";").map(value => value.trim()).filter(value => value !== "")) {
            backends.add(name);
        }
    }
    const packages = {};
    for (const backend of backends) {
        for (const manager of Object.keys(PORTAL_BACKEND_PACKAGES)) {
            const pkg = PORTAL_BACKEND_PACKAGES[manager][backend];
            if (pkg === undefined) refuse(`portal-backend=unknown backend=${backend} path=${PORTALS_CONF}`);
            packages[manager] = packages[manager] || [];
            packages[manager].push({ backend, package: pkg });
        }
    }
    return packages;
}
// True when HAVE >= NEED, both dotted decimal integers compared component
// by component, a missing component 0: bin/vgshell's version_at_least.
function atLeast(have, need) {
    const a = have.split(".").map(Number), b = need.split(".").map(Number);
    for (let i = 0; i < Math.max(a.length, b.length); i++) {
        const x = a[i] || 0, y = b[i] || 0;
        if (x !== y) return x > y;
    }
    return true;
}

// bin/vgshell's preflight_floor rows as [{ tool, need, probe }], read by
// scripts/preflight-floor.js.
function readFloors() {
    const read = parseFloors(readText("bin/vgshell", "floors=unreadable"));
    if (!read.ok) refuse(read.key + " path=bin/vgshell", read.detail);
    return read.rows;
}

function readRequirements() {
    const ctx = require(path.join(codeRoot, "bin", "lib", "qml-library.js")).load(path.join(codeRoot, "shell", "Core", "PluginLogic.js"));
    const coreRel = "config/requirements.json";
    let core;
    try {
        core = JSON.parse(readText(coreRel, "requirements=unreadable"));
    } catch (e) {
        refuse("requirements=unreadable path=" + coreRel, e.message);
    }
    const coreError = ctx.requirementsError(core);
    if (coreError !== "") refuse("requirements=refused path=" + coreRel, coreError);
    if (core.length === 0) refuse("requirements=empty scope=core", "the core list is never empty, so the reader is broken");
    const entry = (scope, r) => ({ scope, command: r.name, packages: r.packages, optional: r.optional, onRequest: r.onRequest, floor: null, tool: null });
    const list = ctx.normalRequirements(core).map(r => entry("core", r));

    const base = path.join(root, "shell", "plugins");
    const scan = childProcess.spawnSync(path.join(codeRoot, "bin", "vgshell-scan"), ["--require-base", base], { encoding: "utf8", env: { PATH: process.env.PATH, LC_ALL: "C" } });
    if (scan.error || scan.status !== 0) refuse("requirements=unreadable scan=" + (scan.error ? scan.error.code : scan.status), scan.stderr || "");
    for (const listed of JSON.parse(scan.stdout)) {
        const rel = path.relative(root, listed.dir);
        if (listed.error !== undefined) refuse("requirements=unreadable path=" + rel, listed.error);
        let raw;
        try {
            raw = JSON.parse(listed.text);
        } catch (e) {
            refuse("requirements=unreadable path=" + rel, e.message);
        }
        const judged = ctx.validateManifest(raw, listed.dir);
        if (!judged.ok) refuse("requirements=refused path=" + rel, judged.error);
        for (const r of judged.manifest.requirements) list.push(entry(judged.manifest.id, r));
    }

    for (const { tool, need, probe } of readFloors()) {
        const asked = list.find(e => e.command === probe && e.onRequest);
        if (asked !== undefined) refuse(`floor=on-request command=${probe} tool=${tool} scope=${asked.scope}`, "a floor tool must be installed with VGS, before vgshell run checks it");
        let floored = list.find(e => e.command === probe);
        if (floored === undefined) {
            floored = { scope: "core", command: probe, packages: {}, optional: false, onRequest: false, floor: null, tool: null };
            list.push(floored);
        }
        floored.optional = false;
        floored.floor = need === "present" ? null : need;
        floored.tool = tool;
    }
    // Libraries have no PATH command. Their package data shares the same
    // required dependency judge as commands, without inventing a command.
    let libraries;
    try { libraries = JSON.parse(readText("config/runtime-libraries.json", "libraries=unreadable")); }
    catch (error) { refuse("libraries=unreadable", error.message); }
    const seen = new Set();
    if (!Array.isArray(libraries)) refuse("libraries=shape");
    for (const row of libraries) {
        if (row === null || typeof row !== "object" || Object.keys(row).sort().join(",") !== "id,packages"
                || typeof row.id !== "string" || !/^[a-z][a-z0-9-]*$/.test(row.id) || seen.has(row.id)
                || row.packages === null || typeof row.packages !== "object" || Array.isArray(row.packages)
                || Object.keys(row.packages).length === 0
                || Object.entries(row.packages).some(([manager, pkg]) => !["pacman", "apt", "dnf", "nix"].includes(manager)
                    || typeof pkg !== "string" || !/^[a-zA-Z0-9][a-zA-Z0-9+_.-]*$/.test(pkg))) refuse("libraries=shape");
        seen.add(row.id);
        list.push({ scope: "core", command: "library:" + row.id, packages: row.packages, optional: false, onRequest: false, floor: null, tool: null });
    }
    return list;
}

// A requirement's package on a channel: the first of MANAGERS it names,
// else a preflight row's tool name, else undefined.
function packageOf(requirement, managers) {
    for (const manager of managers)
        if (requirement.packages[manager] !== undefined) return requirement.packages[manager];
    return requirement.tool !== null ? requirement.tool : undefined;
}

function one(values) {
    return (values || []).join(",");
}

// Whether the tag exists in this repository.
function tagExists(tag) {
    const probe = childProcess.spawnSync("git", ["-C", root, "rev-parse", "-q", "--verify", "refs/tags/" + tag], { encoding: "utf8" });
    if (probe.status === 0) return true;
    if (probe.status === 1) return false;
    return refuse("tag=unreadable status=" + (probe.error ? probe.error.code : probe.status) + " root=" + root, probe.stderr || "");
}

// ---- pacman ----------------------------------------------------------------

// A depends, optdepends or makedepends entry: `name[op version][: reason]`.
function pacmanEntry(text) {
    const m = /^([^<>=:\s]+)(?:(>=|<=|=|<|>)([^:\s]+))?(?::.*)?$/.exec(text);
    if (m === null) refuse("entry=unreadable text=" + text);
    return { name: m[1], op: m[2] || "", version: m[3] || "", epoch: "", text };
}

// .SRCINFO as { key: [values] } in file order.
function readSrcinfo(recipe) {
    const rel = recipe.dir + "/.SRCINFO";
    const info = {};
    for (const line of readText(rel, "srcinfo=missing recipe=" + recipe.name).split("\n")) {
        const m = /^\s*([a-z0-9_]+) = (.*)$/.exec(line);
        if (m !== null) (info[m[1]] = info[m[1]] || []).push(m[2]);
    }
    const base = one(info.pkgbase);
    if (base !== recipe.name) refuse("pkgbase=" + (base || "missing") + " recipe=" + recipe.name);
    return { hard: (info.depends || []).map(pacmanEntry), soft: (info.optdepends || []).map(pacmanEntry), info };
}

// Whether the PKGBUILD's function NAME holds LINE, trimmed, as a line of
// its body.
function functionHolds(pkgbuild, name, line) {
    const body = new RegExp("^" + name + "\\(\\) \\{\\n([\\s\\S]*?)^\\}$", "m").exec(pkgbuild);
    return body !== null && body[1].split("\n").some(text => text.trim() === line);
}

function pacmanRules(recipes, reads, version) {
    const scriptlets = recipes.map((recipe, i) => {
        const name = recipe.name + ".install";
        const install = one(reads[i].info.install);
        if (install !== name) refuse(`install=${install || "missing"} want=${name} recipe=${recipe.name}`);
        const text = readText(recipe.dir + "/" + name, "scriptlet=missing recipe=" + recipe.name);
        const body = /^post_install\(\) \{\n([\s\S]*?)^\}$/m.exec(text);
        const wants = ["cat /usr/" + MESSAGE, "/usr/" + FIRST_START];
        const bodyLines = body === null ? [] : body[1].split("\n").map(line => line.trim());
        for (const want of wants)
            if (!bodyLines.includes(want)) refuse(`scriptlet=silent recipe=${recipe.name}`, "want in post_install: " + want);
        const pkgbuild = readText(recipe.dir + "/PKGBUILD", "pkgbuild=missing recipe=" + recipe.name);
        if (!functionHolds(pkgbuild, "package", PACMAN_INSTALL))
            refuse(`installer=missing recipe=${recipe.name}`, "want in package(): " + PACMAN_INSTALL);
        if (recipe.name === "vgshell-git" && !functionHolds(pkgbuild, "prepare", GIT_CLONE))
            refuse("fetch=missing recipe=vgshell-git", "want in prepare(): " + GIT_CLONE);
        return text;
    });
    if (scriptlets.some(text => text !== scriptlets[0])) refuse("scriptlet=differs recipes=" + recipes.map(r => r.name).join(","));
    recipes.forEach((recipe, i) => {
        const info = reads[i].info;
        if (one(info.arch) !== "any") refuse("arch=" + one(info.arch) + " recipe=" + recipe.name);
        for (const tag of ["conflicts", "replaces", "provides"])
            if ((info[tag] || []).length > 0) refuse(tag + "=" + one(info[tag]) + " recipe=" + recipe.name);
        const pkgver = one(info.pkgver);
        if (recipe.name === "vgshell") {
            if (pkgver !== version) refuse("pkgver=" + pkgver + " version=" + version + " recipe=vgshell");
            const want = `vgshell-${pkgver}.tar.gz::${REPO_URL}/releases/download/v${pkgver}/vgshell-${pkgver}.tar.gz`;
            if (one(info.source) !== want) refuse("source=" + one(info.source) + " recipe=vgshell", "want " + want);
            const sums = info.sha256sums || [];
            if (sums.length !== 1) refuse("sha256sums=count count=" + sums.length + " recipe=vgshell");
            if (sums[0] === "SKIP") {
                if (tagExists("v" + pkgver)) refuse("sha256sums=SKIP tag=v" + pkgver + " recipe=vgshell", "the release tag exists: pin the release tarball's sha256");
            } else if (!/^[0-9a-f]{64}$/.test(sums[0])) {
                refuse("sha256sums=" + sums[0] + " recipe=vgshell", "want SKIP before the tag v" + pkgver + " exists, else 64 lower-case hex digits");
            }
        } else {
            if ((info.source || []).length > 0) refuse("source=" + one(info.source) + " recipe=vgshell-git", "want none: prepare() clones main alone");
            if (one(info.url) !== REPO_URL) refuse("url=" + (one(info.url) || "missing") + " recipe=vgshell-git", "want " + REPO_URL + ": prepare() clones $url.git");
            if (!(info.makedepends || []).some(text => pacmanEntry(text).name === "git")) refuse("makedepends=missing package=git recipe=vgshell-git");
        }
    });
}

// makepkg --printsrcinfo of a scratch copy of the PKGBUILD equals the
// committed .SRCINFO; null when makepkg is not on PATH.
function pacmanFresh(recipe) {
    const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "check-packaging-"));
    scratchDirs.push(scratch);
    // makepkg refuses a PKGBUILD whose install file is not beside it.
    for (const name of fs.readdirSync(path.join(root, recipe.dir))) {
        const file = path.join(root, recipe.dir, name);
        if (fs.statSync(file).isFile()) fs.copyFileSync(file, path.join(scratch, name));
    }
    const run = childProcess.spawnSync("makepkg", ["--printsrcinfo"], { cwd: scratch, encoding: "utf8" });
    if (run.error && run.error.code === "ENOENT") return null;
    if (run.error || run.status !== 0) refuse("srcinfo=unreadable recipe=" + recipe.name + " status=" + (run.error ? run.error.code : run.status), run.stderr || "");
    if (run.stdout !== readText(recipe.dir + "/.SRCINFO", "srcinfo=missing recipe=" + recipe.name))
        refuse("srcinfo=stale recipe=" + recipe.name, `run: (cd ${recipe.dir} && makepkg --printsrcinfo > .SRCINFO)`);
    return true;
}

// Execute the recipe's pkgver against a private checkout, never the caller's
// runtime. The older shell's client answers function-not-found with exit 0.
function pacmanVersion() {
    const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "check-pkgver-"));
    scratchDirs.push(scratch);
    const tree = path.join(scratch, "vgshell");
    fs.mkdirSync(tree);
    fs.cpSync(path.join(codeRoot, "bin"), path.join(tree, "bin"), { recursive: true });
    fs.copyFileSync(path.join(root, "bin/vgshell"), path.join(tree, "bin/vgshell"));
    fs.copyFileSync(path.join(root, "VERSION"), path.join(tree, "VERSION"));
    fs.writeFileSync(path.join(scratch, "qs"), '#!/bin/bash\nprintf "%s\\n" "$*" >>"$STUB_ARGS"\nprintf "Function not found.\\n"\n', { mode: 0o755 });
    const env = {
        PATH: scratch + ":" + path.dirname(process.execPath) + ":/usr/bin:/bin", HOME: scratch,
        XDG_RUNTIME_DIR: path.join(scratch, "runtime"), XDG_CONFIG_HOME: path.join(scratch, "config"),
        VGS_TEST_RUN: "1", TMPDIR: scratch, LC_ALL: "C", STUB_ARGS: path.join(scratch, "ipc-args"),
        GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null",
        GIT_AUTHOR_NAME: "fixture", GIT_AUTHOR_EMAIL: "fixture@example.invalid",
        GIT_COMMITTER_NAME: "fixture", GIT_COMMITTER_EMAIL: "fixture@example.invalid",
    };
    fs.mkdirSync(env.XDG_RUNTIME_DIR);
    const setup = childProcess.spawnSync("/bin/bash", ["-c", 'set -e; git init -q "$1"; git -C "$1" add .; git -C "$1" commit -q -m fixture; printf "%s.r1.g%s\\n" "$(cat "$1/VERSION")" "$(git -C "$1" rev-parse --short=7 HEAD)"', "pkgver-fixture", tree], { encoding: "utf8", env });
    if (setup.error || setup.status !== 0) refuse("pkgver=fixture-failed", setup.stderr || "");
    for (const state of ["absent", "older"]) {
        const run = childProcess.spawnSync("/bin/bash", ["-c", `
set -euo pipefail
if [[ $3 == older ]]; then
  sleep 300 &
  holder=$!
  trap 'kill "$holder"; wait "$holder" || :' EXIT
  printf '%s\\n' "$holder" >"$XDG_RUNTIME_DIR/vgshell.lock"
fi
source "$1"
srcdir="$2"
pkgver
`, "pkgver-check", path.join(root, "packaging/arch/vgshell-git/PKGBUILD"), scratch, state], { encoding: "utf8", env, timeout: 10000 });
        if (run.error || run.status !== 0 || run.stdout !== setup.stdout || run.stderr !== "")
            refuse(`pkgver=failed shell=${state}`, run.error ? run.error.message : run.stdout + run.stderr);
        if (fs.existsSync(env.STUB_ARGS)) refuse(`pkgver=ipc shell=${state}`);
    }
}

// ---- dnf -------------------------------------------------------------------

const DNF_BEGIN = "# begin runtime dependencies";
const DNF_END = "# end runtime dependencies";
const DNF_LINE = /^(Requires|Recommends|Conflicts):\s+(\S+)(?:\s+>=\s+(?:(\d+):)?(\S+))?\s*$/;
const DNF_SECTION = /^%(description|prep|build|install|check|files|post|changelog)\b/;
const DNF_INSTALL = "DESTDIR=%{buildroot} PREFIX=%{_prefix} SYSCONFDIR=%{_sysconfdir} packaging/install-system.sh";
const DNF_CHECK = "scripts/check-install-tree.sh %{buildroot} %{_prefix} %{_sysconfdir}";
// The %files lines of what the system install adds beside the tree.
const DNF_FILES = ["%{_bindir}/vgshell-browser-policy", "%attr(0440,root,root) %config(noreplace) %{_sysconfdir}/sudoers.d/vgshell-theme-browser", "%config(noreplace) %{_sysconfdir}/xdg/autostart/vgshell.desktop", "%config(noreplace) %{_sysconfdir}/xdg/xdg-desktop-portal/hyprland-portals.conf"];
// $1 is the count of this package installed after the transaction: 1 on a
// first install, 2 on an upgrade.
const DNF_POST = ['if [ "$1" -eq 1 ]; then', "cat %{_datadir}/" + MESSAGE.replace(/^share\//, ""), "%{_datadir}/" + FIRST_START.replace(/^share\//, ""), "fi"];

// A spec's preamble tags, sections and runtime dependency block.
function readSpec(recipe) {
    const lines = readText(recipe.file, "spec=missing").split("\n");
    const tags = {}, sections = {};
    let section = null;
    for (const line of lines) {
        const found = DNF_SECTION.exec(line);
        if (found !== null) {
            section = "%" + found[1];
            sections[section] = [];
        } else if (section !== null) {
            sections[section].push(line);
        } else {
            const tag = /^([A-Za-z0-9]+):\s*(.*?)\s*$/.exec(line);
            if (tag !== null) (tags[tag[1]] = tags[tag[1]] || []).push(tag[2]);
        }
    }
    for (const body of Object.values(sections)) while (body.length > 0 && body[body.length - 1].trim() === "") body.pop();
    const starts = lines.flatMap((line, i) => line.trim() === DNF_BEGIN ? [i] : []);
    const ends = lines.flatMap((line, i) => line.trim() === DNF_END ? [i] : []);
    if (starts.length !== 1 || ends.length !== 1 || ends[0] < starts[0]) refuse("block=missing spec=" + recipe.spec);
    const block = lines.slice(starts[0] + 1, ends[0]).map(line => line.trim()).filter(line => line !== "" && !line.startsWith("#"));
    const hard = [], soft = [];
    for (const line of block) {
        const m = DNF_LINE.exec(line);
        if (m === null) refuse("line=unreadable spec=" + recipe.spec + " text=" + line);
        const dep = { name: m[2], op: m[4] !== undefined ? ">=" : "", version: m[4] || "", epoch: m[3] || "0", text: line };
        if (m[1] === "Requires") hard.push(dep);
        else if (m[1] === "Recommends") soft.push(dep);
    }
    return { hard, soft, tags, sections, block };
}

function dnfRules(recipes, reads, version) {
    const [rel, git] = reads;
    const tagOne = (read, tag, spec) => {
        const values = read.tags[tag] || [];
        if (values.length !== 1) refuse("tag=missing name=" + tag + " spec=" + spec);
        return values[0];
    };
    if (rel.block.join("\n") !== git.block.join("\n")) refuse("block=differs specs=vgshell.spec,vgshell-git.spec");
    recipes.forEach((recipe, i) => {
        const name = tagOne(reads[i], "Name", recipe.spec);
        if (name !== recipe.name) refuse(`name=mismatch spec=${recipe.spec} have=${name} want=${recipe.name}`);
        const arch = tagOne(reads[i], "BuildArch", recipe.spec);
        if (arch !== "noarch") refuse(`buildarch=${arch} spec=${recipe.spec} want=noarch`);
        for (const tag of ["Conflicts", "Obsoletes", "Provides"])
            if ((reads[i].tags[tag] || []).length > 0) refuse(tag.toLowerCase() + "=" + one(reads[i].tags[tag]) + " spec=" + recipe.spec);
    });
    for (const tag of ["License", "URL", "BuildRequires"]) {
        const a = (rel.tags[tag] || []).slice().sort(), b = (git.tags[tag] || []).slice().sort();
        if (a.length === 0 || a.join("\n") !== b.join("\n")) refuse("tag=differs name=" + tag + " specs=vgshell.spec,vgshell-git.spec");
    }
    for (const section of ["%build", "%install", "%check", "%files", "%post"]) {
        if (rel.sections[section] === undefined || (rel.sections[section] || []).join("\n") !== (git.sections[section] || []).join("\n"))
            refuse("section=differs name=" + section + " specs=vgshell.spec,vgshell-git.spec");
    }
    if (!(rel.sections["%install"] || []).some(line => line.trim() === DNF_INSTALL)) refuse("install=missing want=" + DNF_INSTALL);
    if (!(rel.sections["%check"] || []).some(line => line.trim() === DNF_CHECK)) refuse("check=missing want=" + DNF_CHECK);
    for (const want of DNF_FILES)
        if (!(rel.sections["%files"] || []).some(line => line.trim() === want)) refuse("files=missing want=" + want);
    if (rel.sections["%post"].map(line => line.trim()).join("\n") !== DNF_POST.join("\n")) refuse("post=mismatch specs=vgshell.spec,vgshell-git.spec", "want:", ...DNF_POST);
    const relVersion = tagOne(rel, "Version", "vgshell.spec");
    if (relVersion !== version) refuse(`version=mismatch spec=vgshell.spec have=${relVersion} want=${version}`);
    const release = tagOne(rel, "Release", "vgshell.spec").replace("%{?dist}", "");
    const entries = (rel.sections["%changelog"] || []).filter(line => line.startsWith("* "));
    const wantEntry = `- ${relVersion}-${release}`;
    if (entries.length === 0 || !entries[0].endsWith(wantEntry))
        refuse(`changelog=mismatch spec=vgshell.spec want=...${wantEntry} have=${entries.length > 0 ? entries[0] : "none"}`);
    if (git.sections["%changelog"] === undefined) refuse("changelog=missing spec=vgshell-git.spec");
    if (git.sections["%changelog"].some(line => line.trim() !== "")) refuse("changelog=entries spec=vgshell-git.spec", "want empty: srpm.sh writes the entry");
}

// ---- channels --------------------------------------------------------------

// Nix keeps its runtime closure as package attributes. The offline judge
// reads the declaration without requiring a Nix store or network.
function readNix() {
    const text = readText("flake.nix", "recipe=unreadable channel=nix");
    const blocks = [...text.matchAll(/^      runtimePackages = pkgs: \[\n([\s\S]*?)^      \];$/gm)];
    if (blocks.length !== 1) refuse("dependencies=unreadable channel=nix recipe=flake");
    const hard = [];
    for (const raw of blocks[0][1].split("\n")) {
        const line = raw.trim();
        if (line === "" || line.startsWith("#")) continue;
        const match = /^pkgs\.([a-zA-Z0-9][a-zA-Z0-9+_.-]*)$/.exec(line);
        if (match === null) refuse("entry=unreadable channel=nix text=" + line);
        hard.push({ name: match[1], op: "", version: "", epoch: "", text: match[1] });
    }
    return { hard, soft: [] };
}

// The installer hands these package names to the existing package runner.
function readInstaller(recipe) {
    const text = readText("install.sh", "recipe=unreadable channel=" + recipe.manager);
    const blocks = [...text.matchAll(/^  runtime_packages='\n([\s\S]*?)^'$/gm)];
    if (blocks.length !== 1) refuse("dependencies=unreadable channel=install recipe=" + recipe.name);
    const rows = blocks[0][1].split("\n").filter(line => line.trim() !== "").map(line => line.trim().split(/\s+/));
    const matches = rows.filter(row => row[0] === recipe.manager);
    if (matches.length !== 1) refuse("dependencies=unreadable channel=install recipe=" + recipe.name);
    const selected = recipe.manager === "pacman" ? [matches[0], ...rows.filter(row => row[0] === "aur")] : matches;
    if (recipe.manager === "pacman" && selected.length !== 2) refuse("dependencies=unreadable channel=install recipe=aur");
    const hard = selected.flatMap(row => row.slice(1)).map(name => {
        if (!/^[a-zA-Z0-9][a-zA-Z0-9+_.-]*$/.test(name)) refuse("entry=unreadable channel=install text=" + name);
        return { name, op: "", version: "", epoch: "", text: name };
    });
    return { hard, soft: [] };
}

// One entry per package manager id with recipes here. A new channel is one
// entry: its recipes, a reader returning { hard, soft, ... } with each
// dependency as { name, op, version, epoch, text }, the fields the shared
// rules read, its own rules over all its recipes, a reader of a recipe's
// licence expressions for the licence rule or null where no package
// recipe is read, and its freshness check or null. Its controls go in scripts/test-check-packaging.js ROWS.
// The engine replaces stock Quickshell only on channels that publish it.
const ENGINE = "vgshell-quickshell";
const ENGINE_REVISION = "2b4501a282689792b62e94f3fb30d8f512324fe6";
const ENGINE_DIR = "packaging/arch/" + ENGINE;
const ENGINE_SOURCES = ["quickshell-check.hook", "vgs-989-deletelater.patch", "vgs-1109-log-filter-mutex.patch"];
function engineRules() {
    const recipe = { name: ENGINE, dir: ENGINE_DIR };
    const { info } = readSrcinfo(recipe);
    const build = readText(ENGINE_DIR + "/PKGBUILD", "engine=pkgbuild");
    const field = (key, want) => {
        if (one(info[key]) !== want) refuse(`engine=${key} recipe=${ENGINE}`, "want " + want);
    };
    field("provides", "quickshell=0.3.2");
    field("license", "LGPL-3.0-only");
    field("conflicts", "quickshell,quickshell-git");
    if ((info.replaces || []).length) refuse(`engine=replaces recipe=${ENGINE}`);
    field("source", `quickshell::git+https://git.outfoxxed.me/quickshell/quickshell.git#commit=${ENGINE_REVISION},${ENGINE_SOURCES.join(",")}`);
    const sums = info.sha256sums || [];
    if (sums.length !== ENGINE_SOURCES.length + 1 || sums[0] !== "SKIP") refuse(`engine=checksums recipe=${ENGINE}`);
    ENGINE_SOURCES.forEach((name, i) => {
        const bytes = readText(ENGINE_DIR + "/" + name, "engine=source");
        if (crypto.createHash("sha256").update(bytes).digest("hex") !== sums[i + 1]) refuse(`engine=checksum source=${name}`);
    });
    for (const name of ENGINE_SOURCES.filter(name => name.endsWith(".patch")))
        if (!functionHolds(build, "prepare", `patch -p1 --forward < "$srcdir/${name}"`)) refuse(`engine=patch source=${name}`);
    if (!build.includes('-DDISTRIBUTOR="VGS (package: vgshell-quickshell)"')) refuse("engine=distributor channel=pacman");
    const spec = readText("packaging/fedora/vgshell-quickshell.spec", "engine=spec");
    const required = [
        `%global commit ${ENGINE_REVISION}`, "Name:           " + ENGINE,
        "Provides:       quickshell = %{version}", "Conflicts:      quickshell", "Conflicts:      quickshell-git",
        "Obsoletes:      quickshell < 0.3.3", "Obsoletes:      quickshell-git < 0.3.3",
        "Source0:        %{url}/archive/%{commit}.tar.gz", "%autosetup -n quickshell -p1",
        '    -DDISTRIBUTOR="VGS (package: vgshell-quickshell)" \\',
        "Patch0:         vgs-989-deletelater.patch", "Patch1:         vgs-1109-log-filter-mutex.patch",
    ];
    for (const line of required)
        if (!spec.split("\n").includes(line)) refuse("engine=spec-contract", "want " + line);
    const nix = readText("flake.nix", "engine=nix");
    const override = /^        quickshell = prev.quickshell.overrideAttrs \(old: \{\n([\s\S]*?)^        \}\);$/m.exec(nix);
    if (override === null || !override[1].includes(`/${ENGINE_REVISION}.tar.gz`)) refuse("engine=nix-source");
    const patches = /^          patches = \[\n([\s\S]*?)^          \];$/m.exec(override[1]);
    const paths = patches === null ? [] : patches[1].split("\n").map(line => line.trim()).filter(line => line && !line.startsWith("#"));
    const expected = ENGINE_SOURCES.filter(name => name.endsWith(".patch")).map(name => `./${ENGINE_DIR}/${name}`);
    if (paths.join(",") !== expected.join(",")) refuse("engine=nix-patches");
    return recipe;
}
const CHANNELS = {
    pacman: {
        recipes: [{ name: "vgshell", dir: "packaging/arch/vgshell" }, { name: "vgshell-git", dir: "packaging/arch/vgshell-git" }],
        managers: ["pacman", "aur"], enginePackage: ENGINE,
        hardField: "depends",
        softField: "optdepends",
        exact: false,
        floorExact: false,
        epochs: null,
        read: readSrcinfo,
        licence: read => read.info.license || [],
        rules: pacmanRules,
        freshness: { tool: "makepkg", check: pacmanFresh },
        shipPortalConfig: true,
    },
    dnf: {
        recipes: [{ name: "vgshell", spec: "vgshell.spec", file: "packaging/fedora/vgshell.spec" }, { name: "vgshell-git", spec: "vgshell-git.spec", file: "packaging/fedora/vgshell-git.spec" }],
        managers: ["dnf"], enginePackage: ENGINE,
        hardField: "Requires",
        softField: "Recommends",
        exact: true,
        floorExact: true,
        // The epoch Fedora's packages carry, where it is not 0. A floor
        // written without it reads as epoch 0, which every epoch-1 build
        // passes whatever its version. nodejs22 is 1:22.23.1 on Fedora 44
        // (read 2026-09-28); scripts/fedora-container.sh checks each floor's
        // epoch against the installed package's.
        epochs: { nodejs: "1" },
        read: readSpec,
        licence: read => read.tags.License || [],
        rules: dnfRules,
        freshness: null,
        shipPortalConfig: true,
    },
    nix: {
        recipes: [{ name: "flake" }], managers: ["nix"], hardField: "runtimePackages", softField: "optional",
        exact: false, checkFloors: false, epochs: null,
        read: readNix, licence: null, rules: () => {}, freshness: null, requiredOnly: true,
    },
    "install-pacman": {
        recipes: [{ name: "pacman", manager: "pacman" }], managers: ["pacman", "aur"], enginePackage: ENGINE, hardField: "runtime_packages", softField: "optional",
        exact: false, checkFloors: false, epochs: null,
        read: readInstaller, licence: null, rules: () => {}, freshness: null, requiredOnly: true,
    },
    "install-apt": {
        recipes: [{ name: "apt", manager: "apt" }], managers: ["apt"], hardField: "runtime_packages", softField: "optional",
        exact: false, checkFloors: false, epochs: null,
        read: readInstaller, licence: null, rules: () => {}, freshness: null, requiredOnly: true,
    },
    "install-dnf": {
        recipes: [{ name: "dnf", manager: "dnf" }], managers: ["dnf"], enginePackage: ENGINE, hardField: "runtime_packages", softField: "optional",
        exact: false, checkFloors: false, epochs: null,
        read: readInstaller, licence: null, rules: () => {}, freshness: null, requiredOnly: true,
    },
    "install-nix": {
        recipes: [{ name: "nix", manager: "nix" }], managers: ["nix"], hardField: "runtime_packages", softField: "optional",
        exact: false, checkFloors: false, epochs: null,
        read: readInstaller, licence: null, rules: () => {}, freshness: null, requiredOnly: true,
    },
};

function sharedRules(id, channel, recipe, read, requirements, gaps, portalBackends) {
    const where = r => ` channel=${id} recipe=${recipe.name} scope=${r.scope}`;
    const hardWant = new Map(), softWant = new Map(), onRequest = new Map();
    for (const r of requirements) {
        const declaredPackage = packageOf(r, channel.managers);
        const pkg = declaredPackage === "quickshell" && channel.enginePackage ? channel.enginePackage : declaredPackage;
        if (pkg === undefined) {
            if (!r.optional && channel.managers.some(manager => gaps[manager] && gaps[manager][r.command])) continue;
            if (!r.optional) refuse(`requirement=${r.command} package=unmapped want=${channel.hardField}` + where(r));
            continue;
        }
        if (r.onRequest) {
            if (!onRequest.has(pkg)) {
                onRequest.set(pkg, r);
                softWant.set(pkg, r);
            }
        } else if (r.tool !== null || !r.optional) {
            if (!hardWant.has(pkg)) hardWant.set(pkg, r);
        } else if (!softWant.has(pkg)) {
            softWant.set(pkg, r);
        }
    }
    for (const [pkg, r] of onRequest)
        if (hardWant.has(pkg))
            refuse(`on-request=${pkg} wanted-hard-by=${hardWant.get(pkg).scope} channel=${id} recipe=${recipe.name} scope=${r.scope}`,
                "one package is either installed with VGS or installed on request: mark both requirements alike");
    if (channel.shipPortalConfig === true) {
        for (const manager of channel.managers) {
            for (const row of portalBackends[manager] || []) {
                const requirement = { scope: "portal", command: "portal-backend:" + row.backend, floor: null, tool: null, optional: false };
                if (!hardWant.has(row.package)) hardWant.set(row.package, requirement);
            }
        }
    }
    for (const pkg of hardWant.keys()) softWant.delete(pkg);
    const hard = new Map(read.hard.map(dep => [dep.name, dep]));
    const soft = new Map(read.soft.map(dep => [dep.name, dep]));
    for (const [pkg, r] of hardWant) {
        const dep = hard.get(pkg);
        if (dep === undefined) refuse(`requirement=${r.command} package=${pkg} want=${channel.hardField}` + where(r));
        if (channel.checkFloors === false) {
            // These channels select names; the existing preflight checks versions.
        } else if (channel.floorExact) {
            const have = dep.version || "none", want = r.floor || "none";
            if (have !== want) refuse(`floor=mismatch package=${pkg} have=${have} want=${want}` + where(r));
        } else if (r.floor !== null) {
            if (dep.op !== ">=" || !DOTTED.test(dep.version)) refuse(`floor=missing package=${pkg} want=>=${r.floor}` + where(r));
            if (!atLeast(dep.version, r.floor)) refuse(`floor=below package=${pkg} have=>=${dep.version} want=>=${r.floor}` + where(r));
        }
        if (channel.epochs !== null && r.floor !== null) {
            const want = channel.epochs[pkg] || "0";
            if (dep.epoch !== want) refuse(`epoch=mismatch package=${pkg} have=${dep.epoch} want=${want}` + where(r));
        }
    }
    for (const pkg of hard.keys())
        if (!hardWant.has(pkg) && onRequest.has(pkg))
            refuse(`on-request=${pkg} field=${channel.hardField} channel=${id} recipe=${recipe.name} scope=${onRequest.get(pkg).scope}`,
                "its requirement declares \"install\": \"on-request\": list it as " + channel.softField + ", which its plugin's Requirements section installs");
    for (const pkg of hard.keys())
        if (!hardWant.has(pkg)) refuse(`extra=${pkg} field=${channel.hardField} channel=${id} recipe=${recipe.name}`);
    for (const [pkg, r] of softWant) {
        if (channel.requiredOnly) continue;
        if (channel.exact || onRequest.has(pkg)) {
            if (!soft.has(pkg)) refuse(`requirement=${r.command} package=${pkg} want=${channel.softField}` + where(r));
        } else if (!hard.has(pkg) && !soft.has(pkg)) {
            refuse(`requirement=${r.command} package=${pkg} want=${channel.hardField}-or-${channel.softField}` + where(r));
        }
    }
    if (channel.exact) {
        for (const [field, have, want] of [[channel.hardField, hard, hardWant], [channel.softField, soft, softWant]])
            for (const pkg of have.keys())
                if (!want.has(pkg)) refuse(`extra=${pkg} field=${field} channel=${id} recipe=${recipe.name}`);
    }
}

// The package licence expression docs/architecture/distribution.md
// § Licence states.
const DOC_LICENCE = new RegExp("^- The SPDX licence expression of a VGS shell package is `([^`]+)`\\.$", "m");

function licenceRule(licences) {
    const rel = "docs/architecture/distribution.md";
    const m = DOC_LICENCE.exec(readText(rel, "licence-doc=missing"));
    if (m === null) refuse("licence-doc=unreadable path=" + rel, "want a line: - The SPDX licence expression of a VGS shell package is `<expr>`.");
    for (const [where, values] of licences) {
        if (values.length !== 1 || values[0] !== m[1])
            refuse(`licence=mismatch ${where} have=${JSON.stringify(values.join(" "))} want=${JSON.stringify(m[1])}`, "the recipe and " + rel + " § Licence must state one licence expression");
    }
}

const requirements = readRequirements();
const gaps = readGaps(requirements);
const portalBackends = readPortalBackends();
const version = readText("VERSION", "version=missing").replace(/\n$/, "");
const manifestLines = readText(MANIFEST, "manifest=missing").split("\n");
if (!manifestLines.includes("f " + MESSAGE)) refuse(`message=unshipped path=${MESSAGE} manifest=${MANIFEST}`);
if (!manifestLines.includes("f " + FIRST_START)) refuse(`first-start=unshipped path=${FIRST_START} manifest=${MANIFEST}`);
if (!readText("packaging/install-system.sh", "installer=missing").split("\n").includes(AUTOSTART_EXEC))
    refuse("autostart=exec want=" + AUTOSTART_EXEC);
const judged = [];
const licences = [];
const engineRecipe = engineRules();
for (const [id, channel] of Object.entries(CHANNELS)) {
    const reads = channel.recipes.map(recipe => channel.read(recipe));
    channel.recipes.forEach((recipe, i) => sharedRules(id, channel, recipe, reads[i], requirements, gaps, portalBackends));
    for (const [field, key] of [[channel.hardField, "hard"], [channel.softField, "soft"]]) {
        const sets = reads.map(read => read[key].map(dep => dep.text).sort().join("\n"));
        if (sets.some(set => set !== sets[0]))
            refuse(`${field}=differ channel=${id} recipes=${channel.recipes.map(r => r.name).join(",")}`);
    }
    channel.rules(channel.recipes, reads, version);
    if (channel.licence !== null) channel.recipes.forEach((recipe, i) => licences.push([`channel=${id} recipe=${recipe.name}`, channel.licence(reads[i])]));
    judged.push(id);
}
licenceRule(licences);
pacmanVersion();
// Freshness last, so a missing tool still leaves every other rule judged.
const notMeasured = [];
if (pacmanFresh(engineRecipe) === null) notMeasured.push("check-packaging: status=not-measured reason=makepkg-missing channel=engine");
for (const id of judged) {
    const freshness = CHANNELS[id].freshness;
    if (freshness === null) continue;
    for (const recipe of CHANNELS[id].recipes) {
        if (freshness.check(recipe) === null) {
            notMeasured.push(`check-packaging: status=not-measured reason=${freshness.tool}-missing channel=${id}`);
            break;
        }
    }
}
if (notMeasured.length > 0) {
    process.stdout.write(notMeasured.join("\n") + "\nevery other rule passed; install the tool to compare each recipe with its generated metadata\n");
    process.exit(77);
}
console.log(`check-packaging: ok channels=${judged.join(",")} requirements=${requirements.length}`);
for (const [manager, commands] of Object.entries(gaps))
    for (const [command, evidence] of Object.entries(commands)) {
        const detail = typeof evidence === "string" ? `reason=${evidence}`
            : manager === "dnf" ? `reason=${evidence.reason} route=${evidence.route} source=${evidence.source}`
            : `reason=${evidence.reason} revision=${evidence.revision} failure=${evidence.failure}`;
        console.log(`check-packaging: gap manager=${manager} command=${command} ${detail}`);
    }
