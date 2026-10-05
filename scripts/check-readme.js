#!/usr/bin/env node
// Check README.md's headings and its Install, Plugins and Setup sections
// offline against the files they describe, and write its plugin table.
//
//   node scripts/check-readme.js [--root DIR] [--commands | --write-plugins]
//
// DIR, this repository by default, holds the files read: README.md,
// VERSION, bin/vgshell, bin/lib/post-install.txt, install.sh,
// docs/architecture/runtime.md, packaging/arch/ and shell/plugins/. bin/vgshell-scan always comes from this
// script's own repository and lists DIR's plugins.
//
// Rules. Each finding is one line, `<rule> README.md:<line> <detail>`:
//   section    README.md has the headings `## Install`, `## Plugins` and
//              `## Setup`. A section runs to the next `## ` heading.
//   heading    README.md's `## ` headings are among Features, Install, How
//              it works, Plugins, Setup, Writing a plugin and Licence, in
//              that order, and none appears twice.
//   command    every line of every ```bash fence in § Install, with a `#`
//              comment removed, is one command of one channel:
//                aur       `paru -S <pkg>`, <pkg> a directory under packaging/arch/
//                curl      `curl -fsSL <INSTALL_URL> | bash`, or the same with
//                          `| bash -s -- <options>`: each option one that
//                          install.sh's option parser accepts, and a
//                          --version value `v<VERSION>`
//                nix       `nix run github:vanillagreencom/vgshell -- <vgshell args>`, the
//                          flake on main, or the same with `vgshell/v<VERSION>`
//                checkout  `git clone https://github.com/vanillagreencom/vgshell`,
//                          or `vgshell/bin/vgshell <vgshell args>`
//              <vgshell args> start with a command the usage header of bin/vgshell
//              lists. § Install holds at least one command.
//   autostart  § Setup holds one ```lua fence of one line. The line equals
//              the autostart line docs/architecture/runtime.md states, the
//              line install.sh prints with `vgshell` for its absolute path,
//              and the line of bin/lib/post-install.txt, the text a package
//              prints on a first install.
//   plugin     § Plugins, without its leading and trailing blank lines,
//              equals the plugin table rendered from the manifests, byte for
//              byte. The one finding names the first line that differs, as
//              `have=<line> want=<line>`, `<end>` for a side that ran out.
//
// The plugin table is a comment line naming --write-plugins, a blank line,
// a header and one row per plugin directory bin/vgshell-scan lists under
// shell/plugins/, in scan order, which is directory name order:
// `| [<name>](shell/plugins/<dir>/README.md) | <description> |`, from the
// manifest's `name` and `description`. A manifest whose name or
// description is missing, not a string, empty, or holds `|` or a line
// break, or a plugin with no README.md, is refused rather than skipped.
//
// --write-plugins replaces § Plugins with the rendered table and changes
// nothing else. It runs no other rule.
//
// --commands prints, when every rule passes, one JSON line per command:
// { block, line, channel, needs, vgshell, command }. block counts the bash
// fences of § Install from 1. line is the command's line in README.md.
// needs is `release:v<VERSION>` for a curl release install and a nix run
// of the tag, `aur:<pkg>` for an AUR install, else `none`: what must be
// published before the command can run. vgshell is the vgshell arguments the
// command runs, else null. scripts/readme-install.sh reads these lines.
//
// Exit 0 prints `check-readme: ok commands=<n> plugins=<n>`, the JSON
// lines under --commands, or `check-readme: wrote README.md plugins=<n>`
// under --write-plugins, `changed=yes` or `changed=no` after it. Exit 1
// prints the findings; under --write-plugins only a `section` finding for
// a missing § Plugins. Exit 2 prints `check-readme: unreadable: <path>:
// <cause>` for a file that cannot be read or holds none of what a rule
// reads, `check-readme: refused: plugin=<dir> field=<field>
// reason=<missing|not-a-string|empty|pipe|line-break>` or `check-readme:
// refused: plugin=<dir> reason=no-readme` for a plugin the table cannot
// carry, or `check-readme: refused: argument=<arg>` for the first argument
// it does not take.
"use strict";
const childProcess = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const codeRoot = path.resolve(__dirname, "..");
const args = process.argv.slice(2);
let root = codeRoot, mode = "check";
for (let i = 0; i < args.length; i++) {
    if (args[i] === "--root" && i + 1 < args.length && args[i + 1] !== "") root = path.resolve(args[++i]);
    else if ((args[i] === "--commands" || args[i] === "--write-plugins") && mode === "check") mode = args[i].slice(2);
    else {
        process.stdout.write("check-readme: refused: argument=" + args[i] + "\n");
        process.exit(2);
    }
}

const README = "README.md";
const INSTALL_URL = "https://raw.githubusercontent.com/vanillagreencom/vgshell/main/install.sh";
const CLONE_URL = "https://github.com/vanillagreencom/vgshell";

function unreadable(rel, cause) {
    process.stdout.write("check-readme: unreadable: " + rel + ": " + cause + "\n");
    process.exit(2);
}

function readText(rel) {
    try {
        return fs.readFileSync(path.join(root, rel), "utf8");
    } catch (e) {
        return unreadable(rel, e.code || String(e));
    }
}

const findings = [];
function finding(rule, line, detail) {
    findings.push(`${rule} ${README}:${line} ${detail}`);
}

// ---- sources ---------------------------------------------------------------

const version = readText("VERSION").replace(/\n$/, "");
const vgshellText = readText("bin/vgshell");

// The first word after `vgshell` on each command line of bin/vgshell's usage
// header, the comment block after the shebang.
const vgshellCommands = (() => {
    const header = /^#!.*\n((?:#.*\n)+)/.exec(vgshellText);
    const names = new Set();
    if (header !== null)
        for (const m of header[1].matchAll(/^#\s+vgshell (\S+)/gm)) names.add(m[1]);
    if (!names.has("run")) unreadable("bin/vgshell", "the usage header lists no `vgshell run`, so the reader is broken");
    return names;
})();

const installText = readText("install.sh");

// The long options of the `case "$1" in` arms inside install.sh's argument
// loop, `while (($# > 0)); do`.
const installOptions = (() => {
    const loop = /^\s*while \(\(\$# > 0\)\); do\n\s*case "\$1" in\n([\s\S]*?)^\s*esac$/m.exec(installText);
    const options = new Set();
    if (loop !== null) {
        for (const arm of loop[1].matchAll(/^\s*([^\s()][^)\n]*)\)/gm))
            for (const alternative of arm[1].split("|").map(text => text.trim()))
                if (/^--[a-z][a-z-]*$/.test(alternative)) options.add(alternative);
    }
    if (!options.has("--version")) unreadable("install.sh", "no --version arm in the argument loop, so the reader is broken");
    return options;
})();

// The autostart line install.sh prints, with `vgshell` for the path it fills.
const installAutostart = (() => {
    const m = /^\s*printf '\s*(hl\.on\([^'\n]*%s run[^'\n]*\))\\n' "\$link"$/m.exec(installText);
    if (m === null) unreadable("install.sh", "no printf of the hl.on autostart line");
    return m[1].replace("%s", "vgshell");
})();

// The one autostart line of the text a package prints on a first install.
const messageAutostart = (() => {
    const rel = "bin/lib/post-install.txt";
    const lines = readText(rel).split("\n").map(line => line.trim()).filter(line => line.startsWith("hl.on("));
    if (lines.length !== 1) unreadable(rel, "hl.on lines=" + lines.length + " want=1");
    return lines[0];
})();

const runtimeAutostart = (() => {
    const rel = "docs/architecture/runtime.md";
    const m = /Autostart is \x60(hl\.on\([^\x60\n]*\))\x60/.exec(readText(rel));
    if (m === null) unreadable(rel, "no `Autostart is `hl.on(...)`` sentence");
    return m[1];
})();

// Each plugin directory as bin/vgshell-scan lists it, in its order, as
// { dir, text }: dir relative to the root, text the manifest's bytes.
const plugins = (() => {
    const base = path.join(root, "shell", "plugins");
    const scan = childProcess.spawnSync(path.join(codeRoot, "bin", "vgshell-scan"), ["--require-base", base],
        { encoding: "utf8", env: { PATH: process.env.PATH, LC_ALL: "C" } });
    if (scan.error || scan.status !== 0) unreadable("shell/plugins", "vgshell-scan " + (scan.error ? scan.error.code : "exited " + scan.status) + " " + (scan.stderr || ""));
    const listedPlugins = [];
    for (const listed of JSON.parse(scan.stdout)) {
        const rel = path.relative(root, listed.dir);
        if (listed.error !== undefined) unreadable(rel, listed.error);
        listedPlugins.push({ dir: rel, text: listed.text });
    }
    if (listedPlugins.length === 0) unreadable("shell/plugins", "vgshell-scan listed no plugin, and the core always ships some");
    return listedPlugins;
})();

function refusePlugin(dir, detail) {
    process.stdout.write(`check-readme: refused: plugin=${dir} ${detail}\n`);
    process.exit(2);
}

// The lines of § Plugins: the comment, a blank line, the header and one
// row per plugin.
const pluginTable = (() => {
    const lines = ["<!-- Generated from each plugin's manifest.json by `node scripts/check-readme.js --write-plugins`. Do not edit by hand. -->", "",
        "| Plugin | What it does |", "|---|---|"];
    for (const { dir, text } of plugins) {
        let manifest;
        try {
            manifest = JSON.parse(text);
        } catch (e) {
            unreadable(dir + "/manifest.json", e.message);
        }
        if (manifest === null || typeof manifest !== "object" || Array.isArray(manifest)) unreadable(dir + "/manifest.json", "not a JSON object");
        const cells = [];
        for (const field of ["name", "description"]) {
            const value = manifest[field];
            if (value === undefined) refusePlugin(dir, `field=${field} reason=missing`);
            if (typeof value !== "string") refusePlugin(dir, `field=${field} reason=not-a-string`);
            if (value.trim() === "") refusePlugin(dir, `field=${field} reason=empty`);
            if (value.includes("|")) refusePlugin(dir, `field=${field} reason=pipe`);
            if (/[\r\n\u2028\u2029]/.test(value)) refusePlugin(dir, `field=${field} reason=line-break`);
            cells.push(value.trim());
        }
        if (!fs.existsSync(path.join(root, dir, "README.md"))) refusePlugin(dir, "reason=no-readme");
        lines.push(`| [${cells[0]}](${dir}/README.md) | ${cells[1]} |`);
    }
    return lines;
})();

// ---- README ----------------------------------------------------------------

const readmeLines = readText(README).split("\n");
// The `## ` headings README.md may hold, in their order; section()
// requires its own.
const HEADINGS = ["Features", "Install", "How it works", "Plugins", "Setup", "Writing a plugin", "Licence"];

// The lines of the `## <title>` section as [{ n, text }], n from 1, or
// null when the heading is absent.
function section(title) {
    const start = readmeLines.findIndex(line => line === "## " + title);
    if (start < 0) {
        finding("section", 1, "missing=## " + title);
        return null;
    }
    const lines = [];
    for (let i = start + 1; i < readmeLines.length && !readmeLines[i].startsWith("## "); i++)
        lines.push({ n: i + 1, text: readmeLines[i] });
    return { n: start + 1, lines };
}

// The fences of a section as [{ lang, n, lines: [{ n, text }] }].
function fences(sec) {
    const found = [];
    let open = null;
    for (const line of sec.lines) {
        const m = /^\x60\x60\x60(\S*)\s*$/.exec(line.text);
        if (open === null && m !== null) open = { lang: m[1], n: line.n, lines: [] };
        else if (open !== null && line.text.trim() === "```") {
            found.push(open);
            open = null;
        } else if (open !== null) open.lines.push(line);
    }
    if (open !== null) finding("section", open.n, "fence=unclosed");
    return found;
}

// The vgshell arguments ARGS as a string when their first word is a command
// the usage header lists, else a finding.
function vgshellArgs(args, n) {
    const first = args.split(/\s+/)[0];
    if (!vgshellCommands.has(first)) {
        finding("command", n, `vgshell-command=${first} reason=not-in-usage`);
        return null;
    }
    return args;
}

// One command line as { channel, needs, vgshell }, or null after a finding.
function classify(command, n) {
    let m;
    if ((m = /^paru -S (\S+)$/.exec(command)) !== null) {
        const pkg = m[1];
        if (!fs.existsSync(path.join(root, "packaging", "arch", pkg, "PKGBUILD"))) {
            finding("command", n, `channel=aur package=${pkg} reason=no-recipe`);
            return null;
        }
        return { channel: "aur", needs: "aur:" + pkg, vgshell: null };
    }
    const curl = `curl -fsSL ${INSTALL_URL} | bash`;
    if (command === curl || command.startsWith(curl + " ")) {
        const rest = command.slice(curl.length).trim();
        if (rest === "") return { channel: "curl", needs: `release:v${version}`, vgshell: null };
        if (!rest.startsWith("-s -- ")) {
            finding("command", n, "channel=curl reason=unknown-form text=" + rest);
            return null;
        }
        const words = rest.slice("-s -- ".length).trim().split(/\s+/);
        let release = true, ok = true;
        for (let i = 0; i < words.length; i++) {
            const [option, inline] = words[i].split(/=(.*)/s, 2);
            if (!installOptions.has(option)) {
                finding("command", n, `channel=curl option=${option} reason=not-in-install.sh`);
                ok = false;
                continue;
            }
            if (option === "--version") {
                const value = inline !== undefined ? inline : words[++i];
                if (value !== "v" + version) {
                    finding("command", n, `channel=curl version=${value} want=v${version}`);
                    ok = false;
                }
            }
            if (option === "--git" || option === "--uninstall") release = false;
        }
        return ok ? { channel: "curl", needs: release ? `release:v${version}` : "none", vgshell: null } : null;
    }
    if ((m = /^nix run github:vanillagreencom\/vgshell(?:\/(\S+))? -- (.+)$/.exec(command)) !== null) {
        if (m[1] !== undefined && m[1] !== "v" + version) {
            finding("command", n, `channel=nix tag=${m[1]} want=v${version}`);
            return null;
        }
        const vgshell = vgshellArgs(m[2], n);
        return vgshell === null ? null : { channel: "nix", needs: m[1] === undefined ? "none" : `release:v${version}`, vgshell };
    }
    if (command === `git clone ${CLONE_URL}`) return { channel: "checkout", needs: "none", vgshell: null };
    if ((m = /^vgshell\/bin\/vgshell (.+)$/.exec(command)) !== null) {
        const vgshell = vgshellArgs(m[1], n);
        return vgshell === null ? null : { channel: "checkout", needs: "none", vgshell };
    }
    finding("command", n, "unknown text=" + command);
    return null;
}

function checkCommands(install) {
    const commands = [];
    let block = 0;
    for (const fence of fences(install).filter(f => f.lang === "bash")) {
        block++;
        for (const line of fence.lines) {
            const command = line.text.replace(/(^|\s)#.*$/, "").trim();
            if (command === "") continue;
            const judged = classify(command, line.n);
            if (judged !== null) commands.push({ block, line: line.n, ...judged, command });
        }
    }
    if (commands.length === 0 && !findings.some(f => f.startsWith("command "))) finding("command", install.n, "count=0");
    return commands;
}

function checkAutostart(setup) {
    const lua = fences(setup).filter(f => f.lang === "lua");
    if (lua.length !== 1) {
        finding("autostart", setup.n, "lua-fences=" + lua.length + " want=1");
        return;
    }
    const lines = lua[0].lines.filter(line => line.text.trim() !== "");
    if (lines.length !== 1) {
        finding("autostart", lua[0].n, "lines=" + lines.length + " want=1");
        return;
    }
    const line = lines[0].text.trim();
    if (line !== runtimeAutostart) finding("autostart", lines[0].n, "differs=docs/architecture/runtime.md want=" + runtimeAutostart);
    if (line !== installAutostart) finding("autostart", lines[0].n, "differs=install.sh want=" + installAutostart);
    if (line !== messageAutostart) finding("autostart", lines[0].n, "differs=bin/lib/post-install.txt want=" + messageAutostart);
}

// The lines of SEC without its leading and trailing blank lines.
function trimmed(sec) {
    let first = 0, last = sec.lines.length;
    while (first < last && sec.lines[first].text.trim() === "") first++;
    while (last > first && sec.lines[last - 1].text.trim() === "") last--;
    return sec.lines.slice(first, last);
}

function checkHeadings() {
    const seen = new Set();
    let last = -1;
    readmeLines.forEach((text, i) => {
        if (!text.startsWith("## ")) return;
        const at = HEADINGS.indexOf(text.slice(3));
        if (at < 0) finding("heading", i + 1, "extra=" + text);
        else if (seen.has(text)) finding("heading", i + 1, "duplicate=" + text);
        else if (at < last) finding("heading", i + 1, `order=${text} after=## ${HEADINGS[last]}`);
        seen.add(text);
        last = Math.max(last, at);
    });
}

function checkPlugins(sec) {
    const have = trimmed(sec);
    for (let i = 0; i < Math.max(have.length, pluginTable.length); i++) {
        if (i < have.length && i < pluginTable.length && have[i].text === pluginTable[i]) continue;
        const n = i < have.length ? have[i].n : have.length > 0 ? have[have.length - 1].n + 1 : sec.n;
        finding("plugin", n, `have=${i < have.length ? have[i].text : "<end>"} want=${i < pluginTable.length ? pluginTable[i] : "<end>"}`);
        return;
    }
}

if (mode === "write-plugins") {
    const sec = section("Plugins");
    if (sec === null) {
        process.stdout.write(findings.join("\n") + "\n");
        process.exit(1);
    }
    const end = sec.n + sec.lines.length;
    const atEnd = end === readmeLines.length;
    // A section that ends the file keeps the file's own last line ending,
    // the empty string after its final newline.
    const body = ["", ...pluginTable, ""];
    const text = [...readmeLines.slice(0, sec.n), ...body, ...(atEnd ? [] : readmeLines.slice(end))].join("\n");
    const before = readmeLines.join("\n");
    if (text !== before) fs.writeFileSync(path.join(root, README), text);
    console.log(`check-readme: wrote ${README} plugins=${plugins.length} changed=${text !== before ? "yes" : "no"}`);
    process.exit(0);
}

const install = section("Install");
const pluginSection = section("Plugins");
const setup = section("Setup");
checkHeadings();
const commands = install !== null ? checkCommands(install) : [];
if (setup !== null) checkAutostart(setup);
if (pluginSection !== null) checkPlugins(pluginSection);

if (findings.length > 0) {
    process.stdout.write(findings.join("\n") + "\n");
    process.exit(1);
}
if (mode === "commands") {
    for (const c of commands)
        process.stdout.write(JSON.stringify({ block: c.block, line: c.line, channel: c.channel, needs: c.needs, vgshell: c.vgshell, command: c.command }) + "\n");
} else {
    console.log(`check-readme: ok commands=${commands.length} plugins=${plugins.length}`);
}
