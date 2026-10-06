#!/usr/bin/env node
// Controls for scripts/check-readme.js. Every row runs this repository's
// check with `--root` on a scratch copy under its tmp/ of the files the
// check reads: README.md, VERSION, bin/vgshell, bin/lib/post-install.txt, install.sh,
// docs/architecture/runtime.md, both Arch PKGBUILDs, the COPR project file
// and both Fedora specs, and each shipped
// plugin's manifest.json and README.md. The pristine copy passes. Each
// other row plants one defect that reaches one rule in a fresh copy and
// asserts the exit status and every output line. Every edit asserts it
// matched once and changed its file. A release changes VERSION, so no row
// reads its expectation from this repository's current version: each reads
// it from the copy it edits. The --write-plugins rows compare the README with
// table rows written out here by hand, never with the check's own render.
"use strict";
const childProcess = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const repo = path.resolve(__dirname, "..");
const tmp = path.join(repo, "tmp", "test-check-readme." + process.pid);
fs.rmSync(tmp, { recursive: true, force: true });
fs.mkdirSync(tmp, { recursive: true });
process.on("exit", () => fs.rmSync(tmp, { recursive: true, force: true }));

const ENV = { PATH: path.dirname(process.execPath) + ":" + process.env.PATH, LC_ALL: "C", HOME: tmp, TMPDIR: tmp };

const pristine = path.join(tmp, "pristine");
const files = ["README.md", "VERSION", "bin/vgshell", "bin/lib/post-install.txt", "install.sh", "docs/architecture/runtime.md", "shell/Core/PackageManagers.js",
    "packaging/arch/vgshell/PKGBUILD", "packaging/arch/vgshell-git/PKGBUILD",
    "packaging/fedora/copr-project", "packaging/fedora/vgshell.spec", "packaging/fedora/vgshell-git.spec"];
const plugins = fs.readdirSync(path.join(repo, "shell/plugins"))
    .filter(dir => fs.existsSync(path.join(repo, "shell/plugins", dir, "manifest.json"))).sort();
// The plugin whose row follows vgs.bar's in the table.
const AFTER_BAR = plugins[plugins.indexOf("vgs.bar") + 1];
if (plugins.length === 0) throw new Error("plugins: refused: count=0, and the repository always ships some");
for (const dir of plugins) {
    files.push(`shell/plugins/${dir}/manifest.json`);
    if (fs.existsSync(path.join(repo, "shell/plugins", dir, "README.md"))) files.push(`shell/plugins/${dir}/README.md`);
}
for (const rel of files) {
    fs.mkdirSync(path.dirname(path.join(pristine, rel)), { recursive: true });
    fs.copyFileSync(path.join(repo, rel), path.join(pristine, rel));
}

function fresh(name) {
    const dir = path.join(tmp, name);
    fs.cpSync(pristine, dir, { recursive: true });
    return dir;
}

// Replace OLD, which must occur exactly once, in TREE/REL.
function replaceIn(tree, rel, old, replacement) {
    const file = path.join(tree, rel);
    if (fs.lstatSync(file).isSymbolicLink()) throw new Error("replace: refused: symlink=" + file);
    const text = fs.readFileSync(file, "utf8");
    const count = text.split(old).length - 1;
    if (count !== 1) throw new Error(`replace: refused: matches=${count} path=${rel} text=${JSON.stringify(old)}`);
    const changed = text.replace(old, () => replacement);
    if (changed === text) throw new Error("replace: refused: unchanged path=" + rel);
    fs.writeFileSync(file, changed);
}

const read = (tree, rel) => fs.readFileSync(path.join(tree, rel), "utf8");
const version = tree => read(tree, "VERSION").trim();
// The 1-based line of the one README line equal to TEXT.
function lineOf(tree, text) {
    const lines = read(tree, "README.md").split("\n");
    const hits = lines.flatMap((line, i) => line === text ? [i + 1] : []);
    if (hits.length !== 1) throw new Error(`line: refused: matches=${hits.length} text=${JSON.stringify(text)}`);
    return hits[0];
}
// The 1-based line of the one README line that is COMMAND once a `#`
// comment is removed.
function commandLineOf(tree, command) {
    const lines = read(tree, "README.md").split("\n");
    const hits = lines.flatMap((line, i) => line.replace(/(^|\s)#.*$/, "").trim() === command ? [i + 1] : []);
    if (hits.length !== 1) throw new Error(`command line: refused: matches=${hits.length} command=${JSON.stringify(command)}`);
    return hits[0];
}
const curlLine = (tree, args) => lineOf(tree, "curl -fsSL https://raw.githubusercontent.com/vanillagreencom/vgshell/main/install.sh | bash" + args);
const NIX = "nix run github:vanillagreencom/vgshell";
const autostart = tree => /^```lua\n(.*)\n```$/m.exec(read(tree, "README.md"))[1];

const ok = tree => `check-readme: ok commands=${commandLines(tree).length} plugins=${plugins.length}`;
const CURL = "curl -fsSL https://raw.githubusercontent.com/vanillagreencom/vgshell/main/install.sh | bash";
// The --commands lines a tree's README must print, each command named by
// hand with its channel, needs and vgshell arguments, MORE holding the
// commands a row planted.
function commandsWant(tree, more) {
    const v = "v" + version(tree);
    const want = Object.assign({
        "paru -S vgshell-git": ["aur", "aur:vgshell-git", null],
        "sudo dnf copr enable vanillagreen/vgshell": ["fedora", "copr:vanillagreen/vgshell", null],
        "sudo dnf install vgshell": ["fedora", "copr:vanillagreen/vgshell/vgshell", null],
        [CURL + " -s -- --git"]: ["curl", "none", null],
        [NIX + " -- run"]: ["nix", "none", "run"],
        "git clone https://github.com/vanillagreencom/vgshell": ["checkout", "none", null],
        "vgshell/bin/vgshell run": ["checkout", "none", "run"],
    }, more);
    const commands = commandLines(tree);
    if (commands.length !== Object.keys(want).length) throw new Error("commands: refused: README holds a command this row does not name");
    return commands.map(command => {
        if (want[command] === undefined) throw new Error("commands: refused: unnamed=" + command);
        const [channel, needs, vgshell] = want[command];
        return JSON.stringify({ line: commandLineOf(tree, command), channel, needs, vgshell, archHelpers: ["curl", "checkout"].includes(channel) ? ["paru", "yay"] : [], command });
    });
}
const pluginRow = (dir, name, description) => `| [${name}](shell/plugins/${dir}/README.md) | ${description} |`;
// The README row of plugin DIR in TREE, read from the text.
function rowOf(tree, dir) {
    const lines = read(tree, "README.md").split("\n").filter(line => line.includes(`](shell/plugins/${dir}/README.md) |`));
    if (lines.length !== 1) throw new Error(`row: refused: matches=${lines.length} dir=${dir}`);
    return lines[0];
}
// Replace TREE's plugins with a fixture plugin per [dir, manifest object,
// README present] entry.
function fixturePlugins(tree, entries) {
    fs.rmSync(path.join(tree, "shell/plugins"), { recursive: true });
    for (const [dir, manifest, readme] of entries) {
        fs.mkdirSync(path.join(tree, "shell/plugins", dir), { recursive: true });
        fs.writeFileSync(path.join(tree, "shell/plugins", dir, "manifest.json"), JSON.stringify(manifest) + "\n");
        if (readme) fs.writeFileSync(path.join(tree, "shell/plugins", dir, "README.md"), "# " + dir + "\n");
    }
}
const COMMENT = "<!-- Generated from each plugin's manifest.json by `node scripts/check-readme.js --write-plugins`. Do not edit by hand. -->";
const FIXTURE = [
    ["acme.beta", { name: "Beta", description: "Shows the second fixture." }, true],
    ["acme.alpha", { name: "Alpha", description: "Shows the first fixture." }, true],
];
// The § Plugins body FIXTURE renders to, written out by hand: rows in
// directory name order.
const FIXTURE_BODY = [COMMENT, "", "| Plugin | What it does |", "|---|---|",
    "| [Alpha](shell/plugins/acme.alpha/README.md) | Shows the first fixture. |",
    "| [Beta](shell/plugins/acme.beta/README.md) | Shows the second fixture. |"].join("\n");
// A manifest refusal row: one fixture plugin whose manifest is MANIFEST.
const refusal = (name, manifest, readme, detail) => [name, t => fixturePlugins(t, [["acme.bad", manifest, readme]]),
    2, () => ["check-readme: refused: plugin=shell/plugins/acme.bad " + detail]];
// The command lines of every bash fence under `## Install`, read here from
// the text, independent of the check.
function commandLines(tree) {
    const text = read(tree, "README.md");
    const install = text.slice(text.indexOf("## Install\n"), text.indexOf("\n## ", text.indexOf("## Install\n")));
    return [...install.matchAll(/^```bash\n([\s\S]*?)^```$/gm)]
        .flatMap(m => m[1].split("\n"))
        .map(line => line.replace(/(^|\s)#.*$/, "").trim())
        .filter(line => line !== "");
}

// name | setup(tree) | exit | output lines (a function of the tree) |
// arguments | after(tree), which throws when the tree is wrong
const ROWS = [
    ["the committed README passes", () => {}, 0, tree => [ok(tree)]],
    // command
    ["an absent Arch helper prerequisite is refused", t => replaceIn(t, "README.md", "On Arch, the curl install and checkout need an installed AUR helper: paru or yay.", ""),
        1, tree => [`command README.md:${lineOf(tree, "## Install")} arch-helper=declarations have=0 want=1`]],
    ["an unsupported Arch helper is refused", t => replaceIn(t, "README.md", "AUR helper: paru or yay.", "AUR helper: unknown."),
        1, tree => [`command README.md:${lineOf(tree, "On Arch, the curl install and checkout need an installed AUR helper: unknown.")} arch-helper=unknown reason=not-in-package-detection`]],
    ["an AUR command through yay is refused", t => replaceIn(t, "README.md", "\nparu -S vgshell-git\n", "\nyay -S vgshell-git\n"),
        1, tree => [`command README.md:${lineOf(tree, "yay -S vgshell-git")} unknown text=yay -S vgshell-git`]],
    ["an AUR package with no recipe is refused", t => replaceIn(t, "README.md", "\nparu -S vgshell-git\n", "\nparu -S vgshell-bin\n"),
        1, tree => [`command README.md:${lineOf(tree, "paru -S vgshell-bin")} channel=aur package=vgshell-bin reason=no-recipe`]],
    ["a COPR project other than copr-project's is refused", t => replaceIn(t, "README.md", "\nsudo dnf copr enable vanillagreen/vgshell\n", "\nsudo dnf copr enable vanillagreen/vgs\n"),
        1, tree => [`command README.md:${lineOf(tree, "sudo dnf copr enable vanillagreen/vgs")} channel=fedora project=vanillagreen/vgs want=vanillagreen/vgshell`]],
    ["a copr-project naming another project moves the README's want", t => replaceIn(t, "packaging/fedora/copr-project", "\nproject vanillagreen/vgshell\n", "\nproject vanillagreen/planted\n"),
        1, tree => [`command README.md:${lineOf(tree, "sudo dnf copr enable vanillagreen/vgshell")} channel=fedora project=vanillagreen/vgshell want=vanillagreen/planted`]],
    ["a copr-project with no project line is unreadable", t => replaceIn(t, "packaging/fedora/copr-project", "\nproject vanillagreen/vgshell\n", "\n"),
        2, () => ["check-readme: unreadable: packaging/fedora/copr-project: no `project OWNER/NAME` line"]],
    ["a dnf package with no spec is refused", t => replaceIn(t, "README.md", "\nsudo dnf install vgshell\n", "\nsudo dnf install vgshell-bin\n"),
        1, tree => [`command README.md:${lineOf(tree, "sudo dnf install vgshell-bin")} channel=fedora package=vgshell-bin reason=no-spec`]],
    ["a dnf install of vgshell-git passes", t => replaceIn(t, "README.md", "\nsudo dnf install vgshell\n", "\nsudo dnf install vgshell-git\n"),
        0, tree => [ok(tree)]],
    ["a curl option install.sh does not parse is refused", t => replaceIn(t, "README.md", "/install.sh | bash -s -- --git\n", "/install.sh | bash -s -- --planted\n"),
        1, tree => [`command README.md:${curlLine(tree, " -s -- --planted")} channel=curl option=--planted reason=not-in-install.sh`]],
    ["a curl --version other than v<VERSION> is refused", t => replaceIn(t, "README.md", "/install.sh | bash -s -- --git\n", "/install.sh | bash -s -- --version v0.0.0-planted\n"),
        1, tree => [`command README.md:${curlLine(tree, " -s -- --version v0.0.0-planted")} channel=curl version=v0.0.0-planted want=v${version(tree)}`]],
    ["a curl --version of v<VERSION> passes", t => replaceIn(t, "README.md", "/install.sh | bash -s -- --git\n", `/install.sh | bash -s -- --version v${version(t)}\n`),
        0, tree => [ok(tree)]],
    ["a nix tag other than v<VERSION> is refused", t => replaceIn(t, "README.md", `\n${NIX} -- run\n`, `\n${NIX}/v0.0.0-planted -- run\n`),
        1, tree => [`command README.md:${lineOf(tree, NIX + "/v0.0.0-planted -- run")} channel=nix tag=v0.0.0-planted want=v${version(tree)}`]],
    ["an untagged nix run of a vgshell command the help screen does not list is refused", t => replaceIn(t, "README.md", `\n${NIX} -- run\n`, `\n${NIX} -- start\n`),
        1, tree => [`command README.md:${lineOf(tree, NIX + " -- start")} vgshell-command=start reason=not-in-usage`]],
    ["a vgshell command the help screen does not list is refused", t => replaceIn(t, "README.md", "vgshell/bin/vgshell run", "vgshell/bin/vgshell start"),
        1, tree => [`command README.md:${lineOf(tree, "vgshell/bin/vgshell start")} vgshell-command=start reason=not-in-usage`]],
    ["an Install section with no command is refused", t => {
        const text = read(t, "README.md");
        const install = text.slice(text.indexOf("## Install\n"), text.indexOf("\n## ", text.indexOf("## Install\n")));
        replaceIn(t, "README.md", install, install.replace(/^```bash$/gm, "```text"));
    }, 1, tree => [`command README.md:${lineOf(tree, "## Install")} count=0`]],
    // autostart
    ["a README autostart line that drifted is refused", t => replaceIn(t, "README.md", 'hl.exec_cmd("vgshell run")', 'hl.exec_cmd("vgshell run --planted")'),
        1, tree => {
            const n = lineOf(tree, autostart(tree));
            const want = autostart(pristine);
            return [`autostart README.md:${n} differs=docs/architecture/runtime.md want=${want}`, `autostart README.md:${n} differs=install.sh want=${want}`,
                `autostart README.md:${n} differs=bin/lib/post-install.txt want=${want}`];
        }],
    ["a runtime.md autostart line the README does not follow is refused", t => replaceIn(t, "docs/architecture/runtime.md", 'hl.exec_cmd("vgshell run")', 'hl.exec_cmd("vgshell run --planted")'),
        1, tree => [`autostart README.md:${lineOf(tree, autostart(tree))} differs=docs/architecture/runtime.md want=${autostart(tree).replace('"vgshell run"', '"vgshell run --planted"')}`]],
    ["a first-install text autostart line the README does not follow is refused", t => replaceIn(t, "bin/lib/post-install.txt", 'hl.exec_cmd("vgshell run")', 'hl.exec_cmd("vgshell run --planted")'),
        1, tree => [`autostart README.md:${lineOf(tree, autostart(tree))} differs=bin/lib/post-install.txt want=${autostart(tree).replace('"vgshell run"', '"vgshell run --planted"')}`]],
    ["a first-install text without its autostart line is unreadable", t => replaceIn(t, "bin/lib/post-install.txt", "  hl.on(", "  hl.off("),
        2, () => ["check-readme: unreadable: bin/lib/post-install.txt: hl.on lines=0 want=1"]],
    ["a first-install text with two autostart lines is unreadable", t => replaceIn(t, "bin/lib/post-install.txt", '  hl.on("hyprland.start", function () hl.exec_cmd("vgshell run") end)\n', '  hl.on("hyprland.start", function () hl.exec_cmd("vgshell run") end)\n  hl.on("hyprland.start", function () hl.exec_cmd("vgshell run") end)\n'),
        2, () => ["check-readme: unreadable: bin/lib/post-install.txt: hl.on lines=2 want=1"]],
    ["an install.sh autostart line the README does not follow is refused", t => replaceIn(t, "install.sh", 'hl.exec_cmd("%s run")', 'hl.exec_cmd("%s run --planted")'),
        1, tree => [`autostart README.md:${lineOf(tree, autostart(tree))} differs=install.sh want=${autostart(tree).replace('"vgshell run"', '"vgshell run --planted"')}`]],
    ["an autostart fence in Install instead of Setup is refused", t => {
        const fence = "```lua\n" + autostart(t) + "\n```\n\n";
        replaceIn(t, "README.md", fence, "");
        replaceIn(t, "README.md", "\n## How it works\n", "\n" + fence + "## How it works\n");
    }, 1, tree => [`autostart README.md:${lineOf(tree, "## Setup")} lua-fences=0 want=1`]],
    // plugin
    ["a changed manifest description the table does not follow is refused", t => replaceIn(t, "shell/plugins/vgs.bar/manifest.json",
        `"description": ${JSON.stringify(JSON.parse(read(t, "shell/plugins/vgs.bar/manifest.json")).description)}`, `"description": "Planted description."`),
        1, tree => [`plugin README.md:${lineOf(tree, rowOf(tree, "vgs.bar"))} have=${rowOf(tree, "vgs.bar")} want=${pluginRow("vgs.bar", "Bar", "Planted description.")}`]],
    ["a missing row is refused", t => replaceIn(t, "README.md", rowOf(t, "vgs.bar") + "\n", ""),
        1, tree => {
            const next = rowOf(tree, AFTER_BAR);
            return [`plugin README.md:${lineOf(tree, next)} have=${next} want=${rowOf(pristine, "vgs.bar")}`];
        }],
    ["an extra row is refused", t => replaceIn(t, "README.md", rowOf(t, "vgs.bar") + "\n", rowOf(t, "vgs.bar") + "\n" + pluginRow("vgs.planted", "Planted", "Planted row.") + "\n"),
        1, tree => [`plugin README.md:${lineOf(tree, pluginRow("vgs.planted", "Planted", "Planted row."))} have=${pluginRow("vgs.planted", "Planted", "Planted row.")} want=${rowOf(tree, AFTER_BAR)}`]],
    ["a new plugin with no row is refused", t => {
        fs.mkdirSync(path.join(t, "shell/plugins/vgs.zz-planted"));
        fs.writeFileSync(path.join(t, "shell/plugins/vgs.zz-planted/manifest.json"), JSON.stringify({ name: "Planted", description: "Planted plugin." }) + "\n");
        fs.writeFileSync(path.join(t, "shell/plugins/vgs.zz-planted/README.md"), "# Planted\n");
    }, 1, tree => [`plugin README.md:${lineOf(tree, rowOf(tree, plugins[plugins.length - 1])) + 1} have=<end> want=${pluginRow("vgs.zz-planted", "Planted", "Planted plugin.")}`]],
    ["a hand-edited generator comment is refused", t => replaceIn(t, "README.md", COMMENT, "<!-- Planted. -->"),
        1, tree => [`plugin README.md:${lineOf(tree, "<!-- Planted. -->")} have=<!-- Planted. --> want=${COMMENT}`]],
    // a plugin the table cannot carry, refused in every mode
    refusal("a manifest with no description is refused", { name: "Bad" }, true, "field=description reason=missing"),
    refusal("a manifest whose name is not a string is refused", { name: 7, description: "Bad." }, true, "field=name reason=not-a-string"),
    refusal("a manifest with an empty name is refused", { name: " ", description: "Bad." }, true, "field=name reason=empty"),
    refusal("a manifest name holding a pipe is refused", { name: "Bad | worse", description: "Bad." }, true, "field=name reason=pipe"),
    refusal("a manifest description holding a line break is refused", { name: "Bad", description: "Bad.\nWorse." }, true, "field=description reason=line-break"),
    refusal("a plugin with no README is refused", { name: "Bad", description: "Bad." }, false, "reason=no-readme"),
    // section and heading
    ["a README without its Install heading is refused", t => replaceIn(t, "README.md", "\n## Install\n", "\n## Installation\n"),
        1, tree => ["section README.md:1 missing=## Install", `heading README.md:${lineOf(tree, "## Installation")} extra=## Installation`]],
    ["a README with another section is refused", t => replaceIn(t, "README.md", "\n## Plugins\n", "\n## Customize\n\n- Planted.\n\n## Plugins\n"),
        1, tree => [`heading README.md:${lineOf(tree, "## Customize")} extra=## Customize`]],
    ["a README with a section twice is refused", t => replaceIn(t, "README.md", "\n## Plugins\n", "\n## Install\n\n## Plugins\n"),
        1, tree => [`heading README.md:${lineOf(tree, "## Plugins") - 2} duplicate=## Install`]],
    ["a README with a section out of order is refused", t => {
        const text = read(t, "README.md");
        const how = text.slice(text.indexOf("## How it works\n"), text.indexOf("## Plugins\n"));
        replaceIn(t, "README.md", how, "");
        replaceIn(t, "README.md", "\n## Install\n", "\n" + how + "## Install\n");
    }, 1, tree => [`heading README.md:${lineOf(tree, "## Install")} order=## Install after=## How it works`]],
    ["a README without its Setup section is refused", t => {
        const text = read(t, "README.md");
        replaceIn(t, "README.md", text.slice(text.indexOf("## Setup\n"), text.indexOf("## Writing a plugin\n")), "");
    }, 1, () => ["section README.md:1 missing=## Setup"]],
    // --commands, the lines scripts/readme-install.sh reads
    ["--commands prints each command's channel, needs and vgshell arguments", () => {}, 0, tree => commandsWant(tree, {}), ["--commands"]],
    ["--commands marks a curl release install and a nix run of the tag as needing the release, and --uninstall as needing nothing", t => {
        replaceIn(t, "README.md", "/install.sh | bash -s -- --git\n", `/install.sh | bash -s -- --git\n${CURL}\n${CURL} -s -- --uninstall\n`);
        replaceIn(t, "README.md", `\n${NIX} -- run\n`, `\n${NIX} -- run\n${NIX}/v${version(t)} -- run\n`);
    }, 0, tree => {
        const v = "v" + version(tree);
        return commandsWant(tree, { [CURL]: ["curl", "release:" + v, null], [CURL + " -s -- --uninstall"]: ["curl", "none", null],
            [`${NIX}/${v} -- run`]: ["nix", "release:" + v, "run"] });
    }, ["--commands"]],
    ["an install.sh without its argument loop is unreadable", t => replaceIn(t, "install.sh", '  while (($# > 0)); do\n    case "$1" in\n', "  for arg; do\n    case \"$arg\" in\n"),
        2, () => ["check-readme: unreadable: install.sh: no --version arm in the argument loop, so the reader is broken"]],
    ["an unknown argument is refused", () => {}, 2, () => ["check-readme: refused: argument=--bogus"], ["--bogus"]],
    ["a second mode is refused", () => {}, 2, () => ["check-readme: refused: argument=--commands"], ["--write-plugins", "--commands"]],
    // --write-plugins
    ["--write-plugins on a current table changes nothing", () => {}, 0, () => [`check-readme: wrote README.md plugins=${plugins.length} changed=no`],
        ["--write-plugins"], tree => {
            if (read(tree, "README.md") !== read(pristine, "README.md")) throw new Error("write: README changed");
        }],
    ["--write-plugins renders the fixture plugins in directory order and keeps the section after the table", t => {
        fixturePlugins(t, FIXTURE);
        const text = read(t, "README.md");
        replaceIn(t, "README.md", text.slice(text.indexOf("## Plugins\n"), text.indexOf("## Setup\n")), "## Plugins\n\nStale.\n\n");
    }, 0, () => ["check-readme: wrote README.md plugins=2 changed=yes"], ["--write-plugins"], tree => {
        const text = read(tree, "README.md"), before = read(pristine, "README.md");
        const head = before.slice(0, before.indexOf("## Plugins\n")), tail = before.slice(before.indexOf("## Setup\n"));
        if (text !== head + "## Plugins\n\n" + FIXTURE_BODY + "\n\n" + tail) throw new Error("write: README=" + JSON.stringify(text.slice(head.length)));
        const check = childProcess.spawnSync(process.execPath, [path.join(repo, "scripts/check-readme.js"), "--root", tree], { encoding: "utf8", env: ENV });
        if (check.status !== 0) throw new Error("write: the check refused its own render: " + check.stdout);
    }],
    ["--write-plugins keeps the last line ending of a section that ends the file", t => {
        fixturePlugins(t, FIXTURE);
        const text = read(t, "README.md");
        const rest = text.slice(text.indexOf("## Plugins\n")), tail = text.slice(text.indexOf("## Setup\n"));
        replaceIn(t, "README.md", rest, tail + "## Plugins\n\nStale.\n");
    }, 0, () => ["check-readme: wrote README.md plugins=2 changed=yes"], ["--write-plugins"], tree => {
        const text = read(tree, "README.md"), before = read(pristine, "README.md");
        const head = before.slice(0, before.indexOf("## Plugins\n")), tail = before.slice(before.indexOf("## Setup\n"));
        if (text !== head + tail + "## Plugins\n\n" + FIXTURE_BODY + "\n") throw new Error("write: README=" + JSON.stringify(text.slice(head.length)));
    }],
    ["--write-plugins without a Plugins section is refused", t => replaceIn(t, "README.md", "\n## Plugins\n", "\n## Plugin list\n"),
        1, () => ["section README.md:1 missing=## Plugins"], ["--write-plugins"], tree => {
            if (!read(tree, "README.md").includes("\n## Plugin list\n")) throw new Error("write: README changed");
        }],
    ["--write-plugins refuses a plugin the table cannot carry and writes nothing", t => {
        fixturePlugins(t, [["acme.bad", { name: "Bad | worse", description: "Bad." }, true]]);
    }, 2, () => ["check-readme: refused: plugin=shell/plugins/acme.bad field=name reason=pipe"], ["--write-plugins"], tree => {
        if (read(tree, "README.md") !== read(pristine, "README.md")) throw new Error("write: README changed");
    }],
];

let failures = 0;
ROWS.forEach(([name, setup, wantExit, wantLines, args, after], i) => {
    let out = "";
    try {
        const tree = i === 0 ? pristine : fresh("row-" + i);
        setup(tree);
        const run = childProcess.spawnSync(process.execPath, [path.join(repo, "scripts/check-readme.js"), "--root", tree, ...(args || [])], { encoding: "utf8", env: ENV });
        out = run.stdout + run.stderr;
        let have = run.stdout.split("\n").filter(line => line !== "");
        const want = wantLines(tree);
        // --commands lines: every line parses, and block is the count of
        // bash fences opened at or before the command's line.
        if (args !== undefined && args[0] === "--commands") {
            const readme = read(tree, "README.md").split("\n");
            have = have.map(line => {
                const parsed = JSON.parse(line);
                const fences = readme.slice(0, parsed.line - 1).filter(text => text === "```bash").length;
                if (parsed.block !== fences) return "block=" + parsed.block + " want=" + fences + " line=" + parsed.line;
                return JSON.stringify({ line: parsed.line, channel: parsed.channel, needs: parsed.needs, vgshell: parsed.vgshell, archHelpers: parsed.archHelpers, command: parsed.command });
            });
        }
        if (run.status === wantExit && have.join("\n") === want.join("\n")) {
            if (after !== undefined) after(tree);
            console.log("  ok    " + name);
            return;
        }
        console.log(`  FAIL  ${name}: exit=${run.status} want=${wantExit}\n        have=${JSON.stringify(have)}\n        want=${JSON.stringify(want)}`);
    } catch (e) {
        console.log(`  FAIL  ${name}: ${e.message}`);
    }
    failures += 1;
    if (out !== "") console.log(out.replace(/^/gm, "        "));
});
// A missing declaration and an unsupported helper each fail their own guard.
for (const [name, old, replacement, setup, reason] of [
    ["missing-helper", 'finding("command", install.n, "arch-helper=declarations have=" + declarations.length + " want=1")', 'void 0',
        t => replaceIn(t, "README.md", "On Arch, the curl install and checkout need an installed AUR helper: paru or yay.", ""), "arch-helper=declarations"],
    ["unknown-helper", '!supported.includes(helper)', 'false',
        t => replaceIn(t, "README.md", "AUR helper: paru or yay.", "AUR helper: unknown."), "arch-helper=unknown"],
]) {
    const tree = fresh("control-" + name);
    setup(tree);
    for (const rel of ["scripts/check-readme.js", "bin/lib/qml-library.js", "bin/vgshell-scan"]) {
        fs.mkdirSync(path.dirname(path.join(tree, rel)), { recursive: true });
        fs.copyFileSync(path.join(repo, rel), path.join(tree, rel));
    }
    replaceIn(tree, "scripts/check-readme.js", old, replacement);
    const run = childProcess.spawnSync(process.execPath, [path.join(tree, "scripts/check-readme.js"), "--root", tree], { encoding: "utf8", env: ENV });
    if (run.status === 0 && !run.stdout.includes(reason)) console.log("  ok    control: " + name + " rejects its defect only with the guard");
    else { failures++; console.log("  FAIL  control: " + name + " status=" + run.status + " " + run.stdout + run.stderr); }
}
if (failures > 0) {
    console.log("test-check-readme: failed=" + failures);
    process.exit(1);
}
console.log("test-check-readme: ok");
