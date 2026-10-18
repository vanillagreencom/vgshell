#!/usr/bin/env node
// The Jarvis home folder owner, backend/Home.js, on real folders in J09's
// scratch HOME: the layout an empty folder gets with the render of the Jarvis
// package VGS ships (packaging/jarvis-home), every file its package declares
// in kendex's own layout, with no project-instructions block of this
// repository's own; what a folder that already holds files keeps; a home
// whose recorded package files changed or went stale; an older home's
// skills/base copy, which goes; a write cut short, which the next open
// finishes; the refusal of a link at the home, at every layout path and at
// every package path, of a record VGS cannot read and of a render that is
// partial; the package's declaration as kendex's manifests state it; the
// folder a setting names, the remembered homes list and its Settings offers,
// the bounded read of its text, the skill index, a memory note read by its
// path, the one program of the home, the kendex mail tool, and a kendex home,
// whose render no open writes and no model can write. Each control edits a
// copy of Home.js, or of the Tools.js rule it asks, one rule at a time, and
// must turn a case red; one plants a project-instructions block in a copy of
// the package and must fail that row.
"use strict";
const cp = require("node:child_process");
const { load } = require("../bin/lib/qml-library.js");
const { MENU_ID_PATTERN } = load(require("node:path").join(__dirname, "../shell/Core/PluginLogic.js"));
const { assert, fs, path, tree, world, seed, mutant, fsFault } = require("./fixtures/jarvis/policy.js");
const { scratchTree, useTree } = require("./fixtures/jarvis/core.js");
const file = path.join(tree, "shell/plugins/vgs.jarvis/backend/Home.js");
const denied = path.join(path.dirname(file), "Denied.js");

// The layout VGS-1194 names, independent of the production table: each file
// with what it must say, and each folder.
const FILES = ["AGENTS.md", "memory/MEMORY.md", ".claude/settings.json", ".codex/config.toml"];
const FOLDERS = ["skills", "skills/own", "memory", "memory/inbox", "state", ".claude", ".codex"];
// The render VGS ships, read here from the checkout: kendex writes the
// package into these harness folders, so every file below them is one a home
// without kendex gets, at the same path.
const SHIPPED = path.join(tree, "packaging/jarvis-home");
const HARNESS = [".agents", ".claude/skills", ".claude/agents", ".codex/agents"];
// Where kendex renders the jarvis skill, in a home and in the render alike.
const RENDER = ".agents/skills/jarvis";
// VGS's record of the package files it wrote in a home.
const RECORD = ".vgs-package.json";
// Every regular file below a folder, by its path in it, sorted.
function filesBelow(folder) {
    return fs.readdirSync(folder, { recursive: true }).map(name => String(name))
        .filter(name => fs.lstatSync(path.join(folder, name)).isFile()).sort();
}
const RENDERED = HARNESS.flatMap(harness => filesBelow(path.join(SHIPPED, harness)).map(name => harness + "/" + name)).sort();
// The help topics of the package's skill, its references and its workflows.
const REFERENCES = fs.readdirSync(path.join(SHIPPED, RENDER, "references")).map(name => "base/jarvis/" + name.slice(0, -3));
const WORKFLOWS = fs.readdirSync(path.join(SHIPPED, RENDER, "workflows")).map(name => "base/jarvis/workflows/" + name.slice(0, -3));
const byTopic = (left, right) => left < right ? -1 : left > right ? 1 : 0;
const TOPICS = ["base/jarvis", ...REFERENCES, ...WORKFLOWS].sort(byTopic);
// The file a base topic is read from.
const topicFile = topic => RENDER + (topic === "base/jarvis" ? "/SKILL.md"
    : topic.startsWith("base/jarvis/workflows/") ? "/workflows/" + topic.slice(22) + ".md" : "/references/" + topic.slice(12) + ".md");
// The floor a broken walk or a moved render fails: the package's own two
// files read by name, a reference and a workflow.
for (const name of [RENDER + "/SKILL.md", RENDER + "/persona.md"]) assert.ok(RENDERED.includes(name), "the render holds " + name);
assert.ok(REFERENCES.length > 0 && WORKFLOWS.length > 0, "the render holds references and workflows");

// What the package declares in its SKILL.md front matter, read here in the
// one form the shipped render uses, flow lists under dependencies, and
// independent of Home.declaration.
function declared(text) {
    const front = /^---\n([\s\S]*?)\n---\n/.exec(text);
    assert.ok(front, "the package's front matter");
    const block = /^dependencies:\n((?:[ \t]+\S.*\n)*)/m.exec(front[1] + "\n");
    assert.ok(block, "the package's dependencies");
    const list = key => {
        const found = new RegExp("^[ \\t]+" + key + ":[ \\t]*\\[([^\\]]*)\\][ \\t]*$", "m").exec(block[1]);
        assert.ok(found, "the package's " + key);
        return found[1].split(",").map(name => name.trim()).filter(name => name !== "");
    };
    const out = { skills: list("required"), agents: list("agents") };
    assert.ok(out.skills.length > 0 && out.agents.length > 0, "the declaration reader finds a skill and an agent");
    return out;
}

// The tables and keys of a TOML file of plain `key = value` lines.
function toml(text) {
    const out = {};
    let table = null;
    for (const line of text.split("\n").map(row => row.trim()).filter(Boolean)) {
        const header = /^\[([a-z_]+)\]$/.exec(line), pair = /^([a-z_]+) = (true|false)$/.exec(line);
        assert.ok(header || (pair && table !== null), "plain TOML line: " + line);
        if (header) out[table = header[1]] = {};
        else out[table][pair[1]] = pair[2] === "true";
    }
    return out;
}
// Every entry below a folder, links and scratch files included.
function listing(folder) {
    return fs.readdirSync(folder, { recursive: true }).map(name => String(name)).sort();
}
// Each path with every folder above it.
function withFolders(names) {
    return names.flatMap(name => name.split("/").map((_, index, parts) => parts.slice(0, index + 1).join("/")));
}
// Every entry of a home VGS laid out, with EXTRA, paths of the user's own.
function laidOut(extra = []) {
    return [...new Set([...FILES, ...FOLDERS, RECORD, ...withFolders(RENDERED), ...withFolders(extra)])].sort();
}
const executable = at => (fs.statSync(at).mode & 0o100) !== 0;
// NAME, a package path, is a regular file in the home byte for byte with the
// render's, with its owner's execute bit.
function same(folder, name) {
    const at = path.join(folder, name);
    assert.equal(fs.lstatSync(at, { throwIfNoEntry: false })?.isFile(), true, name + " is a file of the home");
    assert.deepEqual(fs.readFileSync(at), fs.readFileSync(path.join(SHIPPED, name)), name);
    assert.equal(executable(at), executable(path.join(SHIPPED, name)), name + ": its execute bit");
}
// Each harness folder holds the render's files, byte for byte, and nothing
// else but OWN, paths of the user's own. The render is kendex's own install of the package in a Jarvis home:
// the developer policy kendex renders into this repository's own skills as
// a project-instructions block is not for it.
const PROJECT_INSTRUCTIONS = "kendex:project-instructions";
const NO_PROJECT_INSTRUCTIONS = "the home's jarvis skill carries no project instructions";
function shipped(folder, own = []) {
    for (const harness of HARNESS) {
        const mine = withFolders(own.filter(name => name.startsWith(harness + "/")).map(name => name.slice(harness.length + 1)));
        assert.deepEqual(listing(path.join(folder, harness)), [...new Set([...listing(path.join(SHIPPED, harness)), ...mine])].sort(),
            harness + " holds the render alone");
    }
    assert.equal(fs.readFileSync(path.join(folder, RENDER, "SKILL.md"), "utf8").includes(PROJECT_INSTRUCTIONS), false, NO_PROJECT_INSTRUCTIONS);
    for (const name of RENDERED.filter(name => !own.includes(name))) same(folder, name);
}
// The paths VGS's record in a home names.
const recordOf = folder => JSON.parse(fs.readFileSync(path.join(folder, RECORD), "utf8")).files;
// Each named entry of a home with its inode and change time.
function stamps(folder, names) {
    return names.map(name => {
        const stat = fs.lstatSync(path.join(folder, name), { bigint: true, throwIfNoEntry: false });
        return name + ":" + (stat === undefined ? "absent" : stat.ino + ":" + stat.mtimeNs);
    });
}
const keyed = (run, cause, label) => assert.throws(run, { message: "jarvis: home=" + cause }, label);
const write = (folder, name, text, mode) => {
    fs.mkdirSync(path.dirname(path.join(folder, name)), { recursive: true });
    fs.writeFileSync(path.join(folder, name), text, mode === undefined ? undefined : { mode });
};
// kendex's lock in a home, the record of what kendex installed there. A
// kendex home's lock is cut from the shipped render's, whose entries are
// the lock kendex writes for the package; LOCK_ENTRY makes one more.
const LOCK = ".kendex-lock.json";
const SHIPPED_LOCK = JSON.parse(fs.readFileSync(path.join(SHIPPED, LOCK), "utf8"));
const SHIPPED_ENTRIES = Object.entries(SHIPPED_LOCK.entries);
const lockEntry = (kind, name, harness, paths) =>
    [kind + ":" + name + ":" + harness, { name, kind, harness, source: "kendex", enabled: true, emitted: { kind, name, paths } }];
const writeLock = (folder, rows) => write(folder, LOCK, JSON.stringify({ version: SHIPPED_LOCK.version, entries: Object.fromEntries(rows) }, null, 2) + "\n");
// Every entry kendex wrote in a home, the lock among them, with its inode
// and change time.
function kendexStamps(folder) {
    const names = HARNESS.filter(harness => fs.lstatSync(path.join(folder, harness), { throwIfNoEntry: false })?.isDirectory())
        .flatMap(harness => listing(path.join(folder, harness)).map(name => harness + "/" + name));
    return stamps(folder, [LOCK, ...names]);
}
// The kendex mail tool in a home, where kendex's orch skill installs it.
const TOOL = ".agents/skills/mailbox/scripts/lane-mail";
// The package's declaration in the two release forms kendex shipped: v1.18,
// whose front matter names mailbox and seven agents, and PR 4907, whose
// front matter adds orch and whose catalog bundles the package with hooks.
const AGENTS_1_18 = "[cpa, legal, operator, auditor, researcher, scout, reviewer-arch]";
const SORTED_1_18 = ["auditor", "cpa", "legal", "operator", "researcher", "reviewer-arch", "scout"];
const front = dependencies => "---\nname: jarvis\ndescription: \"Load for Jarvis.\"\n" + dependencies + "metadata:\n  source: kendex\n---\n# Jarvis\n";
const DECLARATIONS = [
    ["v1.18", front("dependencies:\n  required: [mailbox]\n  agents: " + AGENTS_1_18 + "\n"), null,
        { skills: ["mailbox"], agents: SORTED_1_18, hooks: [] }],
    ["PR 4907", front("dependencies:\n  required: [mailbox, orch]\n  agents: " + AGENTS_1_18 + "\n"),
        "schema = 7\n\n[bundles.jarvis]\nskills = [\"jarvis\"]\nhooks = [\"session-start-row\", \"lane-mail-check\"]\n",
        { skills: ["mailbox", "orch"], agents: SORTED_1_18, hooks: ["lane-mail-check", "session-start-row"] }],
    ["block lists", front("dependencies:\n  required:\n    - mailbox\n    - \"orch\"\n  optional: anything\n  agents:\n    - scout\n    - cpa\n"), null,
        { skills: ["mailbox", "orch"], agents: ["cpa", "scout"], hooks: [] }],
    ["empty lists", front("dependencies:\n  required: []\n  agents: []\n"), null, { skills: [], agents: [], hooks: [] }],
    // Another map's list of the same name is no dependency.
    ["no dependencies", front("other:\n  required: [elsewhere]\n"), null, { skills: [], agents: [], hooks: [] }],
    ["catalog without the bundle", front("dependencies:\n  required: [mailbox]\n"), "[bundles.other]\nskills = [\"other\"]\n",
        { skills: ["mailbox"], agents: [], hooks: [] }],
    ["multi-line bundle", front("dependencies:\n  required: [mailbox]\n  agents: [scout]\n"),
        "[bundles.jarvis]\n# The package's own.\nskills = [\n  \"jarvis\",  # itself\n  \"mailbox\",\n  \"orch\",\n]\nagents = [\"scout\", \"cpa\"] # beside\n[bundles.other]\nskills = [\"other\"]\n",
        { skills: ["mailbox", "orch"], agents: ["cpa", "scout"], hooks: [] }],
    ["scalar list", front("dependencies:\n  required: mailbox\n"), null, "declaration"],
    ["bad name", front("dependencies:\n  agents: [Scout]\n"), null, "declaration"],
    ["path name", front("dependencies:\n  required: [../mailbox]\n"), null, "declaration"],
    ["no list item", front("dependencies:\n  required:\n    mailbox\n"), null, "declaration"],
    ["duplicate bundle key", front(""), "[bundles.jarvis]\nskills = [\"a\"]\nskills = [\"b\"]\n", "declaration"],
    ["bundle key no array", front(""), "[bundles.jarvis]\nhooks = \"lane-mail-check\"\n", "declaration"],
    ["bundle name unquoted", front(""), "[bundles.jarvis]\nskills = [mailbox]\n", "declaration"],
    ["no front matter", "# Jarvis\n", null, "declaration"],
    ["front matter unclosed", "---\nname: jarvis\n", null, "declaration"]
];

world(() => {
    const { home, roots } = seed();
    let serial = 0;
    const fresh = () => path.join(home, "homes", "h" + ++serial, "Jarvis");
    const backendFolder = path.dirname(file);

    const CASES = {
        // An empty folder, and one that does not exist yet, get every entry
        // and the render's package files, and nothing else; the help topics
        // list the package's skill and each of its references and workflows.
        empty(Home) {
            for (const made of [false, true]) {
                const folder = fresh();
                if (made) fs.mkdirSync(folder, { recursive: true });
                assert.doesNotThrow(() => Home.layout(folder));
                assert.deepEqual(listing(folder), laidOut(), "the layout, the package, its record and no scratch file");
                for (const name of FOLDERS) assert.equal(fs.lstatSync(path.join(folder, name)).isDirectory(), true, name);
                for (const name of FILES) assert.equal(fs.lstatSync(path.join(folder, name)).isFile(), true, name);
                assert.equal(fs.existsSync(path.join(folder, "CLAUDE.md")), false, "Claude Code reads AGENTS.md itself");
                assert.deepEqual(JSON.parse(fs.readFileSync(path.join(folder, ".claude/settings.json"), "utf8")), { autoMemoryEnabled: false });
                assert.deepEqual(toml(fs.readFileSync(path.join(folder, ".codex/config.toml"), "utf8")),
                    { features: { memories: false }, memories: { generate_memories: false, use_memories: false } });
                shipped(folder);
                assert.deepEqual(recordOf(folder), RENDERED, "the record names every package file VGS wrote");
                assert.equal(fs.readFileSync(path.join(folder, RENDER, "persona.md")).length <= 3072, true, "the persona's bound");
                assert.equal(Home.baseSet(folder), ".agents/skills");
                assert.deepEqual(Home.skills(folder).skills.map(skill => [skill.topic, skill.file]), TOPICS.map(topic => [topic, topicFile(topic)]));
                assert.match(Home.skill(folder, REFERENCES[0]), /^# /, "a reference reads by its topic");
            }
        },
        // Done when: a fresh home without kendex holds every file the package
        // declares, as its SKILL.md front matter states it: the package's own
        // skill with its references and workflows, each required skill and
        // each agent in both harnesses' folders, byte for byte with the
        // render and with each execute bit, and a session dispatches each
        // agent by the name its file carries.
        acceptance(Home) {
            const folder = fresh();
            Home.layout(folder);
            const wants = declared(fs.readFileSync(path.join(SHIPPED, RENDER, "SKILL.md"), "utf8"));
            for (const skill of ["jarvis", ...wants.skills])
                for (const harness of [".agents/skills", ".claude/skills"]) {
                    const names = filesBelow(path.join(SHIPPED, harness, skill));
                    assert.ok(names.includes("SKILL.md"), harness + "/" + skill + ": the render holds the skill");
                    for (const name of names) same(folder, harness + "/" + skill + "/" + name);
                }
            for (const topic of [...REFERENCES, ...WORKFLOWS]) same(folder, topicFile(topic));
            for (const agent of wants.agents)
                for (const [name, named] of [[".claude/agents/" + agent + ".md", /^---\n(?:.*\n)*?name:[ \t]*"?([^"\n]*?)"?[ \t]*\n/],
                    [".codex/agents/" + agent + ".toml", /^name[ \t]*=[ \t]*"([^"\n]*)"[ \t]*$/m]]) {
                    same(folder, name);
                    assert.equal(named.exec(fs.readFileSync(path.join(folder, name), "utf8"))?.[1], agent, name + ": a session dispatches it by name");
                }
            if (wants.skills.includes("mailbox"))
                for (const harness of [".agents/skills", ".claude/skills"]) {
                    const tool = harness + "/mailbox/scripts/lane-mail";
                    assert.equal(executable(path.join(SHIPPED, tool)), true, tool + ": the render's mail tool runs");
                    assert.equal(executable(path.join(folder, tool)), true, tool + ": the home's mail tool runs");
                }
        },
        // A folder that already holds files keeps every byte of them, a
        // layout file among them, and gains only what it lacks; a second
        // layout writes nothing, the package and its record among them.
        keeps(Home) {
            const folder = fresh();
            const kept = { "AGENTS.md": "# Mine\nMARKER\n", "README.md": "notes\n", ".git/HEAD": "ref: refs/heads/main\n",
                ".claude/settings.json": "{\"mine\": true}\n", "skills/own/mine.md": "# Mine\n", ".claude/agents/mine.md": "# My agent\n" };
            for (const [name, text] of Object.entries(kept)) write(folder, name, text);
            const before = stamps(folder, Object.keys(kept));
            let package_;
            for (let round = 0; round < 2; round++) {
                assert.doesNotThrow(() => Home.layout(folder));
                for (const [name, text] of Object.entries(kept)) assert.equal(fs.readFileSync(path.join(folder, name), "utf8"), text, name + " keeps every byte");
                assert.deepEqual(stamps(folder, Object.keys(kept)), before, "no kept file is written again");
                for (const name of RENDERED) same(folder, name);
                assert.deepEqual(listing(folder), laidOut([...Object.keys(kept), ".git"]));
                if (round === 0) package_ = stamps(folder, [...RENDERED, RECORD]);
                else assert.deepEqual(stamps(folder, [...RENDERED, RECORD]), package_, "a home that holds the package is not written again");
            }
        },
        // What a VGS update with a changed render finds: a recorded file the
        // render no longer names goes, with each folder it leaves empty; a
        // recorded file changed by hand, or gone, is written again with its
        // execute bit. A file the user wrote at a package path before the
        // first open stays the user's, unrecorded, where it differs from the
        // render's in its bytes or its execute bit, and joins the record,
        // unwritten, where it is the same. A file of the user's outside the
        // record, beside a removed one among them, keeps every byte.
        update(Home) {
            const folder = fresh();
            const lane = ".claude/skills/mailbox/scripts/lane-mail";
            const own = { "AGENTS.md": "# Mine\nMARKER\n", "skills/own/mine.md": "# Mine\n", ".claude/agents/mine.md": "# My agent\n",
                ".agents/skills/kept/notes.md": "mine\n", ".claude/agents/cpa.md": "# Mine at a package path\n",
                [lane]: fs.readFileSync(path.join(SHIPPED, lane), "utf8") };
            for (const [name, text] of Object.entries(own)) write(folder, name, text, 0o644);
            assert.equal(executable(path.join(SHIPPED, lane)), true, "the render's tool runs, the user's copy does not");
            const equal = ".codex/agents/cpa.toml";
            fs.mkdirSync(path.join(folder, ".codex/agents"), { recursive: true });
            fs.copyFileSync(path.join(SHIPPED, equal), path.join(folder, equal));
            fs.chmodSync(path.join(folder, equal), 0o644);
            const joined = stamps(folder, [equal]);
            assert.deepEqual(fs.readFileSync(path.join(folder, lane)), fs.readFileSync(path.join(SHIPPED, lane)), "the user's tool differs in its execute bit alone");
            const users = [".claude/agents/cpa.md", lane];
            const ours = RENDERED.filter(name => !users.includes(name));
            assert.doesNotThrow(() => Home.layout(folder));
            shipped(folder, Object.keys(own));
            assert.deepEqual(stamps(folder, [equal]), joined, "a file the same as the render's is not written again");
            assert.deepEqual(recordOf(folder), ours, "the user's differing files stay out of the record");
            // An older render named these, and VGS wrote them.
            const retired = [".agents/skills/retired/SKILL.md", ".agents/skills/retired/references/one.md", ".agents/skills/kept/SKILL.md",
                ".claude/agents/retired.md"];
            for (const name of retired) write(folder, name, "# Retired\n");
            fs.writeFileSync(path.join(folder, RECORD), JSON.stringify({ files: [...ours, ...retired].sort() }) + "\n");
            // The user changed and removed recorded files by hand.
            fs.appendFileSync(path.join(folder, RENDER, "persona.md"), "my line\n");
            fs.chmodSync(path.join(folder, ".agents/skills/mailbox/scripts/lane-mail"), 0o644);
            fs.rmSync(path.join(folder, ".codex/agents/scout.toml"));
            const before = stamps(folder, Object.keys(own));
            assert.doesNotThrow(() => Home.layout(folder));
            for (const name of retired) assert.equal(fs.existsSync(path.join(folder, name)), false, name + " goes");
            shipped(folder, Object.keys(own));
            assert.equal(fs.existsSync(path.join(folder, ".agents/skills/retired")), false, "a folder the removal leaves empty goes");
            assert.equal(fs.lstatSync(path.join(folder, ".agents/skills/kept")).isDirectory(), true, "a folder that holds a file of the user's stays");
            for (const [name, text] of Object.entries(own)) assert.equal(fs.readFileSync(path.join(folder, name), "utf8"), text, name + " keeps every byte");
            assert.deepEqual(stamps(folder, Object.keys(own)), before, "the update writes no file of the user's");
            assert.deepEqual(recordOf(folder), ours, "the record names the render's files alone");
            assert.deepEqual(listing(folder), laidOut(Object.keys(own)), "no scratch file is left");
        },
        // A write cut short leaves no scratch file, and every package file
        // VGS wrote named in its record, so the next open, by another process
        // and with a render changed meanwhile, finishes the work: a file the
        // cut open wrote is VGS's, never the user's.
        interrupted(Home, backend = backendFolder) {
            const folder = fresh();
            let cut = false;
            fsFault("renameSync", (original, from, to) => {
                if (!cut && String(to).endsWith("/scout.toml")) {
                    cut = true;
                    throw Object.assign(new Error("planted write failure"), { code: "EIO" });
                }
                return original(from, to);
            }, () => keyed(() => Home.layout(folder), "unwritable", "the cut write"));
            assert.equal(cut, true, "the fault reached a package write");
            assert.equal(fs.existsSync(path.join(folder, ".codex/agents/scout.toml")), false, "the cut file is not there");
            assert.deepEqual(listing(folder).filter(name => name.endsWith(".new")), [], "the cut write leaves no scratch file");
            assert.equal(fs.existsSync(path.join(folder, RENDER, "persona.md")), true, "the cut open wrote the persona");
            withRender(backend, render => fs.appendFileSync(path.join(render, RENDER, "persona.md"), "A newer line.\n"), (Newer, copy) => {
                const opened = cp.spawnSync(process.execPath, ["-e", "require(process.argv[1]).use(process.argv[2]);"
                    + " require(process.argv[3]).layout(process.argv[4]);", path.join(copy.backend, "Core.js"), copy.root,
                    path.join(copy.backend, "Home.js"), folder], { env: { PATH: process.env.PATH }, encoding: "utf8", timeout: 30000 });
                assert.equal(opened.status, 0, "another process opens the home: " + opened.stderr);
                for (const name of RENDERED)
                    assert.deepEqual(fs.readFileSync(path.join(folder, name)), fs.readFileSync(path.join(copy.root, "packaging/jarvis-home", name)), name);
            });
            assert.deepEqual(recordOf(folder), RENDERED);
            assert.deepEqual(listing(folder), laidOut(), "no scratch file is left");
        },
        // A home VGS copied the package into before kendex's layout: its
        // skills/base goes, whatever stands there, a link never followed, and
        // the home gains the render; the user's own files keep every byte.
        migration(Home) {
            for (const standing of ["copy", "link", "file"]) {
                const folder = fresh();
                const own = { "AGENTS.md": "# Mine\nMARKER\n", "skills/own/mine.md": "# Mine\n", "memory/MEMORY.md": "- mine\n" };
                for (const [name, text] of Object.entries(own)) write(folder, name, text);
                const outside = path.join(path.dirname(folder), "outside");
                write(outside, "SKILL.md", "OUTSIDE\n");
                if (standing === "copy") {
                    for (const name of ["jarvis/SKILL.md", "jarvis/persona.md", "jarvis/references/memory.md", "stray.md"])
                        write(folder, "skills/base/" + name, "# Older\n");
                } else if (standing === "link") fs.symlinkSync(outside, path.join(folder, "skills/base"));
                else write(folder, "skills/base", "older\n");
                const before = stamps(folder, Object.keys(own));
                assert.doesNotThrow(() => Home.layout(folder), standing);
                assert.equal(fs.lstatSync(path.join(folder, "skills/base"), { throwIfNoEntry: false }), undefined, standing + ": no skills/base");
                assert.deepEqual([fs.readdirSync(outside), fs.readFileSync(path.join(outside, "SKILL.md"), "utf8")], [["SKILL.md"], "OUTSIDE\n"],
                    standing + ": nothing through the link");
                shipped(folder);
                assert.deepEqual(stamps(folder, Object.keys(own)), before, standing + ": no file of the user's is written");
                assert.deepEqual(listing(folder), laidOut(Object.keys(own)), standing);
            }
        },
        // A home whose package the user removed: each read answers absent,
        // which a reader answers by judging the home again, and that open
        // writes the package again.
        removed(Home) {
            const folder = fresh();
            Home.layout(folder);
            fs.rmSync(path.join(folder, ".agents"), { recursive: true });
            keyed(() => Home.baseSet(folder), "absent", "the set");
            keyed(() => Home.skills(folder), "absent", "the index");
            keyed(() => Home.skill(folder, "base/jarvis"), "absent", "the skill");
            assert.doesNotThrow(() => Home.layout(folder));
            shipped(folder);
            // A home kendex installed the package in is kendex's to restore.
            const kendexHome = kendex();
            fs.rmSync(path.join(kendexHome, ".agents"), { recursive: true });
            const before = kendexStamps(kendexHome);
            keyed(() => Home.layout(kendexHome), "absent", "kendex's home");
            keyed(() => Home.skills(kendexHome), "absent", "kendex's index");
            assert.deepEqual(kendexStamps(kendexHome), before, "VGS writes no package file in kendex's home");
            assert.deepEqual([RECORD, ".agents"].filter(name => fs.existsSync(path.join(kendexHome, name))), [], "nor a record");
        },
        // The CLAUDE.md VGS wrote before, a regular file of exactly its one
        // import line, goes, since Claude Code reads AGENTS.md itself and a
        // CLAUDE.md turns its nested loading off. Any other CLAUDE.md is the
        // user's and stays as it is: other bytes, the execute bit, a folder,
        // and a link, never followed.
        claudeShim(Home) {
            const SHIM = "@AGENTS.md\n";
            for (const [label, plant, kept] of [
                ["shim", at => fs.writeFileSync(at, SHIM, { mode: 0o644 }), false],
                ["more lines", at => fs.writeFileSync(at, SHIM + "# Mine\n"), true],
                ["no newline", at => fs.writeFileSync(at, SHIM.trim()), true],
                ["empty", at => fs.writeFileSync(at, ""), true],
                ["executable", at => { fs.writeFileSync(at, SHIM); fs.chmodSync(at, 0o755); }, true],
                ["folder", at => write(at, "notes.md", SHIM), true],
                ["link", (at, outside) => { fs.writeFileSync(outside, SHIM); fs.symlinkSync(outside, at); }, true]
            ]) {
                const folder = fresh();
                fs.mkdirSync(folder, { recursive: true });
                const at = path.join(folder, "CLAUDE.md");
                const outside = path.join(path.dirname(folder), "outside");
                plant(at, outside);
                const stamp = kept ? stamps(folder, ["CLAUDE.md"]) : null;
                assert.doesNotThrow(() => Home.layout(folder), label);
                assert.equal(fs.lstatSync(at, { throwIfNoEntry: false }) !== undefined, kept, label + (kept ? ": the user's CLAUDE.md stays" : ": VGS's old CLAUDE.md goes"));
                if (kept) assert.deepEqual(stamps(folder, ["CLAUDE.md"]), stamp, label + ": the user's CLAUDE.md is left as it is");
                if (label === "folder") assert.equal(fs.readFileSync(path.join(at, "notes.md"), "utf8"), SHIM, "the folder keeps its file");
                if (label === "link") assert.deepEqual([fs.lstatSync(at).isSymbolicLink(), fs.existsSync(outside) && fs.readFileSync(outside, "utf8")], [true, SHIM],
                    "the link is left as it is and what it points at keeps its bytes");
                shipped(folder);
            }
        },
        // A link at the home, or at any layout path, is refused and never
        // followed: what it points at stays as it was.
        links(Home) {
            for (const entry of [".", ...FILES, ...FOLDERS]) {
                for (const dangling of [false, true]) {
                    const folder = fresh();
                    const outside = path.join(path.dirname(folder), "outside");
                    const directory = entry === "." || FOLDERS.includes(entry);
                    if (!dangling && directory) fs.mkdirSync(outside, { recursive: true });
                    else fs.mkdirSync(path.dirname(outside), { recursive: true });
                    if (!dangling && !directory) fs.writeFileSync(outside, "outside\n");
                    const at = path.join(folder, entry);
                    fs.mkdirSync(path.dirname(at), { recursive: true });
                    fs.symlinkSync(outside, at);
                    keyed(() => Home.layout(folder), "link", entry + (dangling ? " dangling" : ""));
                    assert.equal(fs.lstatSync(at).isSymbolicLink(), true, entry + ": the link is left as it is");
                    if (dangling) assert.equal(fs.existsSync(outside), false, entry + ": nothing is made through the link");
                    else if (directory) assert.deepEqual(fs.readdirSync(outside), [], entry + ": nothing is made in the linked folder");
                    else assert.equal(fs.readFileSync(outside, "utf8"), "outside\n", entry + ": the linked file keeps its bytes");
                }
            }
        },
        // A link at a package path of a home VGS laid out, a folder on the
        // way or a file, is refused and never followed: the link stays and
        // what it points at keeps its bytes.
        packageLinks(Home) {
            for (const entry of [".agents", ".claude/agents", ".claude/skills/jarvis/references", RENDER + "/SKILL.md",
                ".agents/skills/mailbox/scripts/lane-mail", ".codex/agents/scout.toml"]) {
                const folder = fresh();
                Home.layout(folder);
                const outside = path.join(path.dirname(folder), "outside");
                const directory = fs.lstatSync(path.join(folder, entry)).isDirectory();
                if (directory) write(outside, "SKILL.md", "OUTSIDE\n");
                else fs.writeFileSync(outside, "OUTSIDE\n");
                const at = path.join(folder, entry);
                fs.rmSync(at, { recursive: true, force: true });
                fs.symlinkSync(outside, at);
                keyed(() => Home.layout(folder), "link", entry);
                assert.equal(fs.lstatSync(at).isSymbolicLink(), true, entry + ": the link is left as it is");
                if (directory) assert.deepEqual([fs.readdirSync(outside), fs.readFileSync(path.join(outside, "SKILL.md"), "utf8")], [["SKILL.md"], "OUTSIDE\n"], entry);
                else assert.equal(fs.readFileSync(outside, "utf8"), "OUTSIDE\n", entry + ": the linked file keeps its bytes");
            }
        },
        // A record VGS cannot read refuses the home by its cause, and the
        // open writes no package file: a link, never followed, an entry of
        // another kind, and one that is no list of plain paths.
        records(Home) {
            for (const [label, cause, plant] of [
                ["link", "link", (at, outside) => { fs.writeFileSync(outside, "{\"files\": []}\n"); fs.symlinkSync(outside, at); }],
                ["folder", "kind", at => fs.mkdirSync(at)],
                ["malformed", "record", at => fs.writeFileSync(at, "{")],
                ["no list", "record", at => fs.writeFileSync(at, "{\"files\": \"" + RENDER + "/SKILL.md\"}\n")],
                ["no files", "record", at => fs.writeFileSync(at, "{}\n")],
                ["parent path", "record", at => fs.writeFileSync(at, "{\"files\": [\"../outside\"]}\n")],
                ["dot path", "record", at => fs.writeFileSync(at, "{\"files\": [\".agents/./x\"]}\n")],
                ["empty path", "record", at => fs.writeFileSync(at, "{\"files\": [\"\"]}\n")]
            ]) {
                const folder = fresh();
                Home.layout(folder);
                const outside = path.join(path.dirname(folder), "outside");
                fs.writeFileSync(outside, "OUTSIDE\n");
                const at = path.join(folder, RECORD);
                fs.rmSync(at);
                plant(at, outside);
                const kept = fs.readFileSync(outside, "utf8");
                // A package file changed by hand shows the refused open writes none.
                fs.appendFileSync(path.join(folder, RENDER, "persona.md"), "mine\n");
                const before = stamps(folder, RENDERED);
                keyed(() => Home.layout(folder), cause, label);
                assert.deepEqual(stamps(folder, RENDERED), before, label + ": no package file is written");
                assert.equal(fs.existsSync(outside) && fs.readFileSync(outside, "utf8"), kept, label + ": nothing outside the home is touched");
                if (label === "link") assert.equal(fs.lstatSync(at).isSymbolicLink(), true, "the linked record is left as it is");
            }
        },
        // An entry of the other kind is refused by its own cause.
        kinds(Home) {
            for (const [entry, make] of [["AGENTS.md", at => fs.mkdirSync(at)], ["skills", at => fs.writeFileSync(at, "")],
                ["memory/inbox", at => fs.writeFileSync(at, "")], [".", at => fs.writeFileSync(at, "")], [".claude/agents", at => fs.writeFileSync(at, "")]]) {
                const folder = fresh();
                const at = path.join(folder, entry);
                fs.mkdirSync(path.dirname(at), { recursive: true });
                make(at);
                keyed(() => Home.layout(folder), "kind", entry);
            }
        },
        // A render that is partial or that VGS cannot read refuses a home
        // without kendex at its open, which writes no package file and no
        // record: one declared agent's file left out, a declared agent or a
        // required skill the lock has no entry for, a lock of another version
        // or none that parses, a path that is no plain path, and a link.
        renderBroken(Home, backend = backendFolder) {
            const lock = render => JSON.parse(fs.readFileSync(path.join(render, ".kendex-lock.json"), "utf8"));
            const relock = (render, change) => {
                const value = lock(render);
                change(value);
                fs.writeFileSync(path.join(render, ".kendex-lock.json"), JSON.stringify(value, null, 2) + "\n");
            };
            const unlist = (render, name) => relock(render, value => {
                const named = Object.keys(value.entries).filter(key => value.entries[key].name === name);
                assert.ok(named.length > 0, name + " has lock entries");
                for (const key of named) {
                    for (const at of value.entries[key].emitted.paths) fs.rmSync(path.join(render, at), { recursive: true });
                    delete value.entries[key];
                }
            });
            const wants = declared(fs.readFileSync(path.join(SHIPPED, RENDER, "SKILL.md"), "utf8"));
            for (const [label, spoil] of [
                ["agent file left out", render => fs.rmSync(path.join(render, ".codex/agents", wants.agents.at(-1) + ".toml"))],
                ["no persona", render => fs.rmSync(path.join(render, RENDER, "persona.md"))],
                ["declared agent unlisted", render => unlist(render, wants.agents.at(-1))],
                ["required skill unlisted", render => unlist(render, wants.skills[0])],
                ["entry without paths", render => relock(render, value => { delete value.entries["agent:" + wants.agents.at(-1) + ":codex"].emitted; })],
                ["paths no array", render => relock(render, value => { value.entries["agent:" + wants.agents.at(-1) + ":codex"].emitted.paths = ""; })],
                ["lock version", render => relock(render, value => { value.version -= 1; })],
                ["lock unreadable", render => fs.writeFileSync(path.join(render, ".kendex-lock.json"), "{")],
                ["path outside", render => {
                    fs.writeFileSync(path.join(render, "../escape.md"), "ESCAPE\n");
                    relock(render, value => { value.entries["skill:jarvis:codex"].emitted.paths.push("../escape.md"); });
                }],
                ["linked file", render => {
                    fs.writeFileSync(path.join(render, "../outside.md"), "OUTSIDE\n");
                    fs.rmSync(path.join(render, ".claude/agents", wants.agents[0] + ".md"));
                    fs.symlinkSync(path.join(render, "../outside.md"), path.join(render, ".claude/agents", wants.agents[0] + ".md"));
                }]
            ]) withRender(backend, spoil, Broken => {
                const folder = fresh();
                keyed(() => Broken.layout(folder), "package", label);
                assert.deepEqual([RECORD, ".agents", ".claude/agents", ".codex/agents", ".claude/skills", "../escape.md"]
                    .filter(name => fs.existsSync(path.join(folder, name))), [], label + ": no package file and no record");
            });
            // The control the refusals rest on: the same copy of the render, unspoiled, lays out.
            withRender(backend, () => {}, Whole => {
                const folder = fresh();
                assert.doesNotThrow(() => Whole.layout(folder));
                shipped(folder);
            });
        },
        // What the package declares beside its own files, read from kendex's
        // manifests in each form kendex shipped: the front matter's lists and
        // the catalog's bundle table, sorted, once and without the package.
        declaration(Home) {
            for (const [label, skill, catalog, expected] of DECLARATIONS) {
                let got;
                try { got = Home.declaration(skill, catalog); }
                catch (error) { got = { error: error.message }; }
                assert.deepEqual(got, typeof expected === "string" ? { error: "jarvis: home=" + expected } : expected, label);
            }
        },
        // The folder a setting names: inside the user's home directory, or
        // none for the empty setting.
        resolves(Home) {
            assert.equal(Home.resolve("", home), null);
            for (const [setting, want] of [["~/Jarvis", "Jarvis"], ["~/Jarvis/", "Jarvis"], ["~/a/../b", "b"], [home + "/x/y", "x/y"]])
                assert.equal(Home.resolve(setting, home), path.join(home, want), setting);
            for (const setting of ["~", home, "Jarvis", "./Jarvis", "/etc/jarvis", "~/../other", home + "-other/x", "~/a\nb", "~/" + "x".repeat(4097)])
                keyed(() => Home.resolve(setting, home), "path", JSON.stringify(setting.slice(0, 40)));
            for (const [setting, base] of [[7, home], ["~/Jarvis", "relative"], ["~/Jarvis", undefined]])
                keyed(() => Home.resolve(setting, base), "path", "types");
            assert.deepEqual(Home.guard("/h/Jarvis"), { root: "/h/Jarvis", open: "state" });
        },
        rememberOffers(Home) {
            const plainOffers = list => Home.offers(list, home).map(({ label, value }) => ({ label, value }));
            const first = Home.offers([home + "/One", home + "/Two"], home);
            const reordered = Home.offers([home + "/Two", home + "/One"], home);
            for (const offer of first) {
                assert.match(offer.id, MENU_ID_PATTERN, "a launcher id");
                assert.match(offer.id, /^h[0-9a-f]{12}$/, "the path hash id");
                assert.equal(reordered.find(row => row.value === offer.value).id, offer.id, "reordering keeps the id");
            }
            assert.notEqual(first[0].id, first[1].id, "different paths have different ids");
            assert.equal(Home.offers(["/user/One"], "/user")[0].id, "hb60681ca7e5f", "SHA-256 of the absolute path");
            assert.equal(Home.offers([home + "/One/"], home)[0].id, first[0].id, "normalizing a path keeps the id");
            const names = Array.from({ length: 12 }, (_, index) => path.join(home, "homes", "h" + index));
            const longLabel = path.join(home, "homes", "l".repeat(53));
            const longValue = "~/" + path.relative(home, longLabel).split(path.sep).join("/");
            const tooLong = path.join(home, "x".repeat(199));
            assert.deepEqual(Home.remember([], names[0]), [names[0]], "a new absolute path is first");
            assert.deepEqual(Home.remember([names[0], names[1]], names[1]), [names[1], names[0]], "an existing path moves to the front once");
            assert.deepEqual(Home.remember(names.slice(0, 12), names[11]), [names[11]].concat(names.slice(0, 9)),
                "the newest path is first, with at most ten paths");
            assert.deepEqual(Home.remember([names[0], "relative", names[1]], names[2]), [names[2], names[0], names[1]],
                "only absolute remembered paths stay");
            assert.deepEqual(Home.remember([names[0]], tooLong), [names[0]], "a home whose offer value does not fit is not kept");
            assert.equal(longValue.length > 60 && longValue.length <= 200, true, "the long label fixture fits the value wire");
            assert.deepEqual(plainOffers([path.join(home, "Jarvis"), path.join(home, "work/One")]),
                [{ label: "~/Jarvis", value: "~/Jarvis" }, { label: "~/work/One", value: "~/work/One" }]);
            assert.deepEqual(plainOffers([longLabel]),
                [{ label: "…" + longValue.slice(-59), value: longValue }], "a long value keeps its full value and shortens its label");
            assert.deepEqual(plainOffers([names[0], names[0]]),
                [{ label: "~/homes/h0", value: "~/homes/h0" }], "an offer is listed once");
            assert.deepEqual(Home.offers([path.dirname(home)], home), [], "an offer must stay inside the user's home");
        },
        // A file's text whole within its bound, or too-large; never a cut
        // text, a link's target or bytes that are no UTF-8.
        reads(Home) {
            const folder = fresh();
            Home.layout(folder);
            const agents = path.join(folder, "AGENTS.md");
            fs.writeFileSync(agents, "é".repeat(8));
            assert.deepEqual(Home.read(folder, "AGENTS.md", 16), { kind: "text", text: "é".repeat(8) }, "exactly the bound");
            assert.deepEqual(Home.read(folder, "AGENTS.md", 15), { kind: "too-large" }, "one byte over");
            fs.writeFileSync(agents, Buffer.from([0x66, 0xff]));
            keyed(() => Home.read(folder, "AGENTS.md", 16), "text");
            keyed(() => Home.read(folder, "memory/absent.md", 16), "absent");
            keyed(() => Home.read(folder, "skills", 16), "kind");
            const secret = path.join(path.dirname(folder), "secret");
            fs.writeFileSync(secret, "OUTSIDE-SECRET\n");
            fs.rmSync(agents);
            fs.symlinkSync(secret, agents);
            keyed(() => Home.read(folder, "AGENTS.md", 64), "link", "a link placed after the layout");
            fs.rmSync(path.join(folder, "memory"), { recursive: true });
            fs.symlinkSync(path.dirname(secret), path.join(folder, "memory"));
            keyed(() => Home.read(folder, "memory/secret", 64), "link", "a linked folder on the way");
        },
        // The skill index: a flat file or a folder's SKILL.md under a plain
        // name, in topic order, each with its line; a link, a hidden entry
        // and any other file is no skill. The base set is the jarvis folder
        // of kendex's render alone, here a kendex home's own small one.
        skills(Home) {
            const folder = fresh();
            const write = (name, text) => {
                fs.mkdirSync(path.dirname(path.join(folder, name)), { recursive: true });
                fs.writeFileSync(path.join(folder, name), text);
            };
            write(RENDER + "/SKILL.md", "---\nname: jarvis\ndescription: \"Load for the package.\"\n---\n# Jarvis\n");
            write(RENDER + "/persona.md", "# Persona\n");
            write(RENDER + "/references/base-one.md", "# Base reference\n");
            write(RENDER + "/workflows/run.md", "---\ndescription: Load to run the package.\n---\nRUN-BODY\n");
            // kendex's other skills and a flat file beside the package are no Jarvis skill.
            write(".agents/skills/mailbox/SKILL.md", "# Mailbox\n");
            write(".agents/skills/stray.md", "# Stray\n");
            writeLock(folder, [lockEntry("skill", "jarvis", "codex", [RENDER]), lockEntry("skill", "mailbox", "codex", [".agents/skills/mailbox"])]);
            Home.layout(folder);
            write("skills/own/alpha.md", "\n# Alpha skill\nbody\n");
            write("skills/own/beta/SKILL.md", "---\nname: beta\ndescription: \"Load for beta work.\"\n---\n# Beta\n");
            write("skills/own/gamma.md", "---\nname: gamma\ndescription: >\n  folded\n---\n\nGamma first line\n");
            write("skills/own/delta.md", "");
            write("skills/own/epsilon.md", "---\ndescription: >-\n  folded and stripped\n---\nEpsilon first line\n");
            write("skills/own/eta.md", "---\ndescription: |+2\n    kept\n---\nEta first line\n");
            write("skills/own/notes.txt", "no skill\n");
            write("skills/own/plain", "no skill\n");
            write("skills/own/.hidden.md", "no skill\n");
            write("skills/own/bad name.md", "no skill\n");
            write("skills/own/empty-folder/readme.md", "no skill\n");
            write("skills/own/bad dir/SKILL.md", "no skill\n");
            write("skills/own/beta/references/one.md", "# One reference\nONE-BODY\n");
            // A reference is read on demand: no size bound holds it back.
            const long = "# Long reference\n" + "long line\n".repeat(4096);
            assert.ok(Buffer.byteLength(long) > 40 * 1024);
            write("skills/own/beta/references/long.md", long);
            write("skills/own/beta/references/bad name.md", "no skill\n");
            write("skills/own/beta/references/notes.txt", "no skill\n");
            write("skills/own/empty-folder/references/orphan.md", "no skill\n");
            write("skills/own/zeta/SKILL.md", "# Zeta\n");
            write("skills/own/zeta/references", "a file, not a folder\n");
            // A workflow passes every rule a reference does, and one of a
            // reference's file name is its own topic, never a silent pick.
            write("skills/own/beta/workflows/one.md", "# One workflow\nONE-WORKFLOW\n");
            write("skills/own/beta/workflows/long.md", long.replace("reference", "workflow"));
            write("skills/own/beta/workflows/bad name.md", "no skill\n");
            write("skills/own/beta/workflows/notes.txt", "no skill\n");
            write("skills/own/empty-folder/workflows/orphan.md", "no skill\n");
            write("skills/own/zeta/workflows", "a file, not a folder\n");
            write("skills/own/kappa/SKILL.md", "# Kappa\n");
            write("skills/own/kappa/workflows/run.md", "---\ndescription: Load to run kappa.\n---\nRUN-BODY\n");
            const outside = path.join(path.dirname(folder), "outside-skill.md");
            fs.writeFileSync(outside, "OUTSIDE-SECRET\n");
            fs.symlinkSync(outside, path.join(folder, "skills/own/linked.md"));
            fs.mkdirSync(path.join(folder, "skills/own/linked-folder"));
            fs.symlinkSync(outside, path.join(folder, "skills/own/linked-folder/SKILL.md"));
            fs.symlinkSync(outside, path.join(folder, "skills/own/beta/workflows/linked.md"));
            fs.mkdirSync(path.join(folder, "skills/own/linked-workflows"));
            fs.writeFileSync(path.join(folder, "skills/own/linked-workflows/SKILL.md"), "# Linked workflows\n");
            fs.symlinkSync(path.join(folder, "skills/own/beta/workflows"), path.join(folder, "skills/own/linked-workflows/workflows"));
            assert.equal(cp.spawnSync("python3", ["-c", "import os, sys; os.mkfifo(sys.argv[1])",
                path.join(folder, "skills/own/beta/workflows/fifo.md")]).status, 0, "the test makes a FIFO");
            let listed;
            assert.doesNotThrow(() => { listed = Home.skills(folder); });
            assert.deepEqual(listed, { complete: true, skills: [
                { topic: "base/jarvis", file: RENDER + "/SKILL.md", line: "Load for the package." },
                { topic: "base/jarvis/base-one", file: RENDER + "/references/base-one.md", line: "Base reference" },
                { topic: "base/jarvis/workflows/run", file: RENDER + "/workflows/run.md", line: "Load to run the package." },
                { topic: "own/alpha", file: "skills/own/alpha.md", line: "Alpha skill" },
                { topic: "own/beta", file: "skills/own/beta/SKILL.md", line: "Load for beta work." },
                { topic: "own/beta/long", file: "skills/own/beta/references/long.md", line: "Long reference" },
                { topic: "own/beta/one", file: "skills/own/beta/references/one.md", line: "One reference" },
                { topic: "own/beta/workflows/long", file: "skills/own/beta/workflows/long.md", line: "Long workflow" },
                { topic: "own/beta/workflows/one", file: "skills/own/beta/workflows/one.md", line: "One workflow" },
                { topic: "own/delta", file: "skills/own/delta.md", line: "" },
                { topic: "own/epsilon", file: "skills/own/epsilon.md", line: "Epsilon first line" },
                { topic: "own/eta", file: "skills/own/eta.md", line: "Eta first line" },
                { topic: "own/gamma", file: "skills/own/gamma.md", line: "Gamma first line" },
                { topic: "own/kappa", file: "skills/own/kappa/SKILL.md", line: "Kappa" },
                { topic: "own/kappa/workflows/run", file: "skills/own/kappa/workflows/run.md", line: "Load to run kappa." },
                { topic: "own/linked-workflows", file: "skills/own/linked-workflows/SKILL.md", line: "Linked workflows" },
                { topic: "own/zeta", file: "skills/own/zeta/SKILL.md", line: "Zeta" }] });
            for (const entry of listed.skills) assert.doesNotThrow(() => Home.skill(folder, entry.topic), "every listed topic reads back: " + entry.topic);
            assert.equal(Home.skill(folder, "own/alpha"), "\n# Alpha skill\nbody\n");
            assert.equal(Home.skill(folder, "own/beta").includes("# Beta"), true, "a folder's SKILL.md is its body");
            assert.equal(Home.skill(folder, "own/beta/one"), "# One reference\nONE-BODY\n");
            assert.equal(Home.skill(folder, "own/beta/long"), long, "a 40 KB reference reads whole");
            assert.equal(Home.skill(folder, "own/beta/workflows/one"), "# One workflow\nONE-WORKFLOW\n", "a workflow keeps its own topic");
            assert.equal(Home.skill(folder, "own/beta/workflows/long"), long.replace("reference", "workflow"), "a 40 KB workflow reads whole");
            assert.equal(Home.skill(folder, "own/kappa/workflows/run"), "---\ndescription: Load to run kappa.\n---\nRUN-BODY\n");
            assert.equal(Home.skill(folder, "base/jarvis/workflows/run"), "---\ndescription: Load to run the package.\n---\nRUN-BODY\n");
            for (const [topic, cause] of [["own/missing", "absent"], ["own/../../secret", "absent"], ["other/alpha", "absent"],
                ["own/linked", "link"], ["own/linked-folder", "link"], ["own/beta/two", "absent"], ["own/beta/workflows/two", "absent"],
                ["own/beta/workflows/linked", "link"], ["own/linked-workflows/workflows/one", "link"], ["own/beta/workflows/fifo", "kind"],
                ["own/beta/workflows/bad name", "absent"], ["own/beta/references/one", "absent"], ["own/zeta/workflows/one", "kind"],
                ["base/mailbox", "absent"], ["base/stray", "absent"]])
                keyed(() => Home.skill(folder, topic), cause, topic);
            // A folder past its entry bound answers incomplete, never a part as the whole.
            for (let index = 0; index < 257; index++) write("skills/own/beta/workflows/w" + index + ".md", "x\n");
            assert.equal(Home.skills(folder).complete, false, "a workflows folder past its bound");
            fs.rmSync(path.join(folder, "skills/own/beta/workflows"), { recursive: true });
            assert.equal(Home.skills(folder).complete, true);
            for (let index = 0; index < 257; index++) write(".agents/skills/s" + index + ".md", "x\n");
            assert.equal(Home.skills(folder).complete, false, "the base set past its bound");
        },
        // A memory note by its path below memory/, as MEMORY.md routes to
        // it. Each refused path names a file that is there, so the path rule
        // refuses it, not its absence: nothing under memory/inbox/, outside
        // memory/ or behind a link is read.
        notes(Home) {
            const folder = fresh();
            Home.layout(folder);
            const write = (name, text) => {
                fs.mkdirSync(path.dirname(path.join(folder, name)), { recursive: true });
                fs.writeFileSync(path.join(folder, name), text);
            };
            write("memory/facts/My team.md", "TEAM-NOTE\n");
            write("facts/My team.md", "HOME-ROOT\n");
            write("memory/inbox/pending.md", "PENDING-NOTE\n");
            write("memory/.hidden.md", "HIDDEN-NOTE\n");
            write("memory/facts/team.txt", "NO-MARKDOWN\n");
            write("AGENTS.md", "OUTSIDE-MEMORY\n");
            assert.equal(Home.note(folder, "facts/My team.md"), "TEAM-NOTE\n");
            write("memory/facts/long.md", "l".repeat(40 * 1024));
            assert.equal(Home.note(folder, "facts/long.md"), "l".repeat(40 * 1024), "a 40 KB note reads whole");
            keyed(() => Home.note(folder, "facts/absent.md"), "absent");
            for (const entry of ["inbox/pending.md", "../AGENTS.md", "facts/../../AGENTS.md", "facts/../inbox/pending.md", ".hidden.md",
                "facts/team.txt", path.join(folder, "memory/facts/My team.md"), 7])
                keyed(() => Home.note(folder, entry), "absent", String(entry));
            const secret = path.join(path.dirname(folder), "secret.md");
            fs.writeFileSync(secret, "OUTSIDE-SECRET\n");
            fs.symlinkSync(secret, path.join(folder, "memory/linked.md"));
            fs.symlinkSync(path.dirname(secret), path.join(folder, "memory/linked-folder"));
            fs.symlinkSync("inbox", path.join(folder, "memory/waiting"));
            for (const entry of ["linked.md", "linked-folder/secret.md", "waiting/pending.md"])
                keyed(() => Home.note(folder, entry), "link", entry);
        },
        // The memory search walker lists only confirmed Markdown notes and
        // returns the stat facts the index reconciles by. It skips inbox,
        // dot entries, links and non-Markdown files, and refuses a tree past
        // its declared count bound rather than cutting it.
        notesList(Home) {
            const folder = fresh();
            Home.layout(folder);
            const write = (name, text = "note\n") => {
                fs.mkdirSync(path.dirname(path.join(folder, name)), { recursive: true });
                fs.writeFileSync(path.join(folder, name), text);
            };
            write("memory/facts/a.md");
            write("memory/facts/b.md");
            write("memory/inbox/pending.md");
            write("memory/.hidden.md");
            write("memory/facts/team.txt");
            const secret = path.join(path.dirname(folder), "secret.md");
            fs.writeFileSync(secret, "secret\n");
            fs.symlinkSync(secret, path.join(folder, "memory/linked.md"));
            fs.symlinkSync(path.dirname(secret), path.join(folder, "memory/linked-folder"));
            const listed = Home.notes(folder);
            assert.deepEqual(listed.map(row => row.id), ["MEMORY.md", "facts/a.md", "facts/b.md"]);
            for (const row of listed) assert.equal(["size", "mtimeNs", "ctimeNs", "ino"].every(key => typeof row[key] === "bigint"), true, row.id);
            const crowded = fresh();
            Home.layout(crowded);
            for (let n = 0; n < 10001; n++) fs.writeFileSync(path.join(crowded, "memory", "n" + n + ".md"), "note\n");
            keyed(() => Home.notes(crowded), "notes-too-many");
        },
        // The mail tool is the one program Jarvis starts from the home: an
        // executable file at TOOL is its path, and the same file anywhere
        // else in the home is none, as is TOOL that is no executable regular
        // file or is reached through a link.
        mailTool(Home) {
            const folder = fresh();
            Home.layout(folder);
            fs.mkdirSync(path.join(folder, ".git"));
            const plant = (entry, mode = 0o755) => {
                fs.mkdirSync(path.dirname(path.join(folder, entry)), { recursive: true });
                fs.writeFileSync(path.join(folder, entry), "#!/bin/sh\n", { mode });
            };
            fs.rmSync(path.join(folder, TOOL), { force: true });
            assert.equal(Home.mailTool(folder), null, "a home without the canonical mail tool");
            for (const entry of ["skills/own/lane-mail", ".agents/skills/orch/scripts/workflow-state", ".agents/skills/other/scripts/lane-mail",
                ".agents/skills/orch/lane-mail", ".agents/skills/mailbox/scripts/other-tool",
                [".agents", "skills", "orch", "scripts", "lane-mail"].join("/"), "lane-mail", "state/lane-mail"]) {
                plant(entry);
                assert.equal(Home.mailTool(folder), null, entry + " is no program of the home");
            }
            // The control the refusals rest on: the same file at TOOL is admitted.
            plant(TOOL);
            assert.equal(Home.mailTool(folder), path.join(folder, TOOL));
            fs.chmodSync(path.join(folder, TOOL), 0o644);
            assert.equal(Home.mailTool(folder), null, "a tool without its execute bit");
            fs.rmSync(path.join(folder, TOOL));
            fs.mkdirSync(path.join(folder, TOOL), { mode: 0o755 });
            assert.equal(Home.mailTool(folder), null, "a folder in the tool's place");
            fs.rmSync(path.join(folder, TOOL), { recursive: true });
            const outside = path.join(path.dirname(folder), "outside");
            fs.mkdirSync(path.join(outside, "scripts"), { recursive: true });
            fs.writeFileSync(path.join(outside, "scripts/lane-mail"), "#!/bin/sh\n", { mode: 0o755 });
            fs.symlinkSync(path.join(outside, "scripts/lane-mail"), path.join(folder, TOOL));
            assert.equal(Home.mailTool(folder), null, "a link in the tool's place");
            fs.rmSync(path.join(folder, TOOL));
            fs.rmSync(path.join(folder, ".agents/skills/mailbox/scripts"), { recursive: true });
            fs.symlinkSync(path.join(outside, "scripts"), path.join(folder, ".agents/skills/mailbox/scripts"));
            assert.equal(Home.mailTool(folder), null, "a linked folder on the way");
            assert.equal(Home.mailTool(path.join(folder, "absent")), null, "a home that is not there");
        },
        cutover(Home) {
            const legacy = [".agents", "skills", "orch", "scripts", "lane-mail"].join("/");
            for (const [name, plant, expected] of [
                ["old-only", () => {}, "eligible"],
                ["canonical", at => write(at, TOOL, "#!/bin/sh\n", 0o755), "ready"],
                ["canonical-no-execute", at => write(at, TOOL, "#!/bin/sh\n", 0o644), "refused"],
                ["canonical-directory", at => fs.mkdirSync(path.join(at, TOOL), { recursive: true }), "refused"],
                ["canonical-link", at => { fs.mkdirSync(path.dirname(path.join(at, TOOL)), { recursive: true });
                    fs.symlinkSync(path.join(at, legacy), path.join(at, TOOL)); }, "refused"]]) {
                const folder = fresh();
                write(folder, legacy, "#!/bin/sh\nexit 99\n", 0o755);
                fs.mkdirSync(path.join(folder, ".git"));
                plant(folder);
                assert.equal(Home.mailCutover(folder), expected, name);
            }
            const folder = fresh();
            fs.mkdirSync(folder, { recursive: true });
            assert.equal(Home.mailCutover(folder), "ineligible");
            assert.equal(Home.consumeMailCutover(folder), true);
            assert.equal(Home.consumeMailCutover(folder), false, "a second process cannot restore eligibility");
            Home.release(folder);
            assert.equal(Home.consumeMailCutover(folder), false, "package release keeps the record");
            fsFault("readSync", () => { throw Object.assign(new Error("planted read failure"), { code: "EIO" }); },
                () => keyed(() => Home.consumeMailCutover(folder), "cutover-record"));
            for (const content of ["", "{", '{"consumed":false}\n', "x".repeat(129)]) {
                fs.writeFileSync(path.join(folder, ".vgs-mailbox-cutover.json"), content);
                keyed(() => Home.consumeMailCutover(folder), "cutover-record");
            }
            for (const method of ["writeFileSync", "fsyncSync", "closeSync"]) {
                const target = fresh();
                fs.mkdirSync(target, { recursive: true });
                let cut = false;
                fsFault(method, (original, ...args) => {
                    if (!cut && (method !== "closeSync" || fs.readlinkSync("/proc/self/fd/" + args[0]).endsWith("/.vgs-mailbox-cutover.json"))) { cut = true; if (method === "closeSync") original(...args);
                        throw Object.assign(new Error("planted record fault"), { code: "EIO" }); }
                    return original(...args);
                }, () => keyed(() => Home.consumeMailCutover(target), "cutover-record"));
                assert.equal(cut, true, method + " reached the durable writer");
                assert.equal(fs.existsSync(path.join(target, ".vgs-mailbox-cutover.json")), true);
            }
            fs.rmSync(path.join(folder, ".vgs-mailbox-cutover.json"));
            const outside = fresh();
            write(outside, "marker", '{"consumed":true}\n');
            fs.symlinkSync(path.join(outside, "marker"), path.join(folder, ".vgs-mailbox-cutover.json"));
            keyed(() => Home.consumeMailCutover(folder), "cutover-record");
        },
        // lane-mail takes the repository its working folder belongs to, so
        // the tool counts only in a home that is its own repository: one
        // with a .git folder, or a worktree's .git file, of its own. A home
        // inside another repository with none, as this scratch HOME lies
        // inside this checkout, or with a linked .git, has no tool.
        ownRepository(Home) {
            const folder = fresh();
            Home.layout(folder);
            fs.mkdirSync(path.dirname(path.join(folder, TOOL)), { recursive: true });
            fs.writeFileSync(path.join(folder, TOOL), "#!/bin/sh\n", { mode: 0o755 });
            const git = path.join(folder, ".git");
            assert.equal(Home.mailTool(folder), null, "a home with no repository of its own");
            const outside = path.join(path.dirname(folder), "outside.git");
            fs.mkdirSync(outside);
            fs.symlinkSync(outside, git);
            assert.equal(Home.mailTool(folder), null, "a linked .git");
            fs.rmSync(git);
            assert.equal(cp.spawnSync("python3", ["-c", "import os, sys; os.mkfifo(sys.argv[1])", git]).status, 0, "the test makes a FIFO");
            assert.equal(Home.mailTool(folder), null, "a .git that is neither a folder nor a file");
            fs.rmSync(git);
            // The control the refusals rest on: a .git of its own admits the tool.
            fs.mkdirSync(git);
            assert.equal(Home.mailTool(folder), path.join(folder, TOOL), "a .git folder of its own");
            fs.rmSync(git, { recursive: true });
            fs.writeFileSync(git, "gitdir: /elsewhere/.git/worktrees/home\n");
            assert.equal(Home.mailTool(folder), path.join(folder, TOOL), "a worktree's .git file");
        },
        // The Jarvis session's mailbox folder, which Jarvis never makes: a
        // folder at its place, reached through no link.
        mailbox(Home) {
            const folder = fresh();
            Home.layout(folder);
            assert.equal(Home.mailbox(folder), false, "no mailbox");
            fs.mkdirSync(path.join(folder, "tmp/lane-mail"), { recursive: true });
            fs.writeFileSync(path.join(folder, "tmp/lane-mail/overseer"), "");
            assert.equal(Home.mailbox(folder), false, "a file in the mailbox's place");
            fs.rmSync(path.join(folder, "tmp/lane-mail/overseer"));
            const outside = path.join(path.dirname(folder), "outside-box");
            fs.mkdirSync(outside);
            fs.symlinkSync(outside, path.join(folder, "tmp/lane-mail/overseer"));
            assert.equal(Home.mailbox(folder), false, "a linked mailbox");
            fs.rmSync(path.join(folder, "tmp/lane-mail/overseer"));
            fs.mkdirSync(path.join(folder, "tmp/lane-mail/overseer"));
            assert.equal(Home.mailbox(folder), true, "the Jarvis session's mailbox folder");
            assert.deepEqual(fs.readdirSync(path.join(folder, "tmp/lane-mail/overseer")), [], "nothing is made in it");
        },
        // A home kendex installed the package in, as its lock names the
        // package's skill, in a version other than the shipped one: no open
        // writes a package file or a record there, every file kendex wrote
        // keeps every byte, the open still removes an older
        // skills/base, whatever stands there, and every read of the base
        // package is kendex's render. kendex's other skills and a flat
        // jarvis.md beside the render are no Jarvis skill.
        render(Home) {
            for (const standing of ["none", "copy", "link"]) {
                const folder = kendex();
                const outside = path.join(path.dirname(folder), "outside");
                write(outside, "SKILL.md", "OUTSIDE\n");
                if (standing === "copy") write(folder, "skills/base/jarvis/SKILL.md", "# Older\n");
                if (standing === "link") {
                    fs.mkdirSync(path.join(folder, "skills"));
                    fs.symlinkSync(outside, path.join(folder, "skills/base"));
                }
                const before = kendexStamps(folder);
                for (let update = 0; update < 2; update++) {
                    assert.doesNotThrow(() => Home.layout(folder), standing);
                    assert.equal(fs.lstatSync(path.join(folder, "skills/base"), { throwIfNoEntry: false }), undefined, standing + ": no skills/base");
                    assert.deepEqual(kendexStamps(folder), before, standing + ": every file kendex wrote keeps every byte");
                    assert.equal(fs.existsSync(path.join(folder, RECORD)), false, standing + ": no record of VGS's");
                    assert.deepEqual([fs.readdirSync(outside), fs.readFileSync(path.join(outside, "SKILL.md"), "utf8")], [["SKILL.md"], "OUTSIDE\n"], standing);
                    assert.equal(Home.baseSet(folder), ".agents/skills");
                    assert.equal(Home.skill(folder, "base/jarvis"), fs.readFileSync(path.join(folder, RENDER, "SKILL.md"), "utf8"), "the brain's skill text is the render's");
                    assert.match(Home.skill(folder, "base/jarvis"), /RENDER-MARKER/);
                    assert.deepEqual(Home.skills(folder).skills.map(skill => [skill.topic, skill.file]),
                        [...TOPICS, "base/jarvis/workflows/run"].sort(byTopic).map(topic => [topic, topicFile(topic)]));
                    assert.equal(Home.read(folder, Home.baseSet(folder) + "/" + Home.PACKAGE + "/persona.md", null).text, "# Render persona\n");
                    keyed(() => Home.skill(folder, "base/orch"), "absent", "kendex's other skill");
                }
            }
        },
        // kendex installed the package for Claude Code alone: its lock names
        // the package's skill in that harness, so the home is kendex's in
        // every harness. VGS writes nothing there, and the home, without the
        // package where every brain reads it, answers absent.
        claudeOnly(Home) {
            const folder = fresh();
            const claude = SHIPPED_ENTRIES.filter(([, entry]) => entry.harness === "claude");
            assert.ok(claude.some(([, entry]) => entry.kind === "skill" && entry.name === "jarvis"), "the lock names the package for Claude Code");
            for (const [, entry] of claude) for (const at of entry.emitted.paths) fs.cpSync(path.join(SHIPPED, at), path.join(folder, at), { recursive: true });
            writeLock(folder, claude);
            const before = kendexStamps(folder);
            keyed(() => Home.layout(folder), "absent", "a home kendex installed for Claude Code alone");
            assert.deepEqual(kendexStamps(folder), before, "every file kendex wrote keeps every byte");
            assert.deepEqual([RECORD, ".agents", ".codex/agents"].filter(name => fs.existsSync(path.join(folder, name))), [], "VGS writes nothing");
        },
        // kendex installed the package in a home VGS laid out: its lock now
        // names the package's skill, so VGS's record goes and every file,
        // kendex's edits among them, stays as it is.
        adopted(Home) {
            const folder = fresh();
            Home.layout(folder);
            writeLock(folder, SHIPPED_ENTRIES);
            fs.writeFileSync(path.join(folder, RENDER, "persona.md"), "# kendex's persona\n");
            fs.writeFileSync(path.join(folder, ".claude/agents/cpa.md"), "---\nname: cpa\n---\n# kendex's cpa\n");
            fs.rmSync(path.join(folder, ".codex/agents/scout.toml"));
            const before = kendexStamps(folder);
            for (let round = 0; round < 2; round++) {
                assert.doesNotThrow(() => Home.layout(folder));
                assert.equal(fs.existsSync(path.join(folder, RECORD)), false, "VGS's record goes");
                assert.deepEqual(kendexStamps(folder), before, "kendex's edits survive, and nothing is written again");
                assert.equal(fs.existsSync(path.join(folder, ".codex/agents/scout.toml")), false, "a file kendex removed stays removed");
            }
        },
        // A home that holds kendex's orch and mailbox, as fleet setup leaves
        // it, mailbox delivered for Claude Code as a copy or as a link to its
        // .agents folder: the package is VGS's to write, the paths kendex's
        // lock names are kendex's, never walked, written, recorded or
        // dropped, and a mailbox VGS wrote before kendex took it leaves the
        // record with kendex's bytes.
        fleet(Home) {
            const mailbox = [".agents/skills/mailbox", ".claude/skills/mailbox"];
            for (const [delivery, vgsFirst] of [["copy", false], ["link", false], ["copy", true], ["link", true]]) {
                const label = delivery + (vgsFirst ? " over VGS's copy" : "");
                const folder = fresh();
                if (vgsFirst) {
                    Home.layout(folder);
                    assert.deepEqual(recordOf(folder), RENDERED, label + ": VGS wrote the mailbox");
                    for (const at of mailbox) fs.rmSync(path.join(folder, at), { recursive: true });
                }
                fs.cpSync(path.join(SHIPPED, mailbox[0]), path.join(folder, mailbox[0]), { recursive: true });
                fs.writeFileSync(path.join(folder, mailbox[0], "README.md"), "# kendex's newer mailbox\n");
                write(folder, ".agents/skills/orch/SKILL.md", "# Orch\n");
                if (delivery === "copy") fs.cpSync(path.join(folder, mailbox[0]), path.join(folder, mailbox[1]), { recursive: true });
                else {
                    fs.mkdirSync(path.join(folder, ".claude/skills"), { recursive: true });
                    fs.symlinkSync("../../.agents/skills/mailbox", path.join(folder, mailbox[1]));
                }
                writeLock(folder, ["codex", "claude"].flatMap(harness => [
                    lockEntry("skill", "orch", harness, [(harness === "codex" ? ".agents" : ".claude") + "/skills/orch"]),
                    lockEntry("skill", "mailbox", harness, [harness === "codex" ? mailbox[0] : mailbox[1]])]));
                // Every entry kendex wrote: the lock, each skill folder or the
                // link in its place, and each file below a folder.
                const kendexOwn = () => stamps(folder, [LOCK, ...[...mailbox, ".agents/skills/orch"].flatMap(at =>
                    [at, ...(fs.lstatSync(path.join(folder, at), { throwIfNoEntry: false })?.isDirectory() ? listing(path.join(folder, at)).map(name => at + "/" + name) : [])])]);
                const before = kendexOwn();
                assert.doesNotThrow(() => Home.layout(folder), label);
                assert.deepEqual(kendexOwn(), before, label + ": every file kendex wrote keeps every byte");
                if (delivery === "link") assert.equal(fs.lstatSync(path.join(folder, mailbox[1])).isSymbolicLink(), true, label + ": kendex's link stays");
                const ours = RENDERED.filter(name => !mailbox.some(at => name.startsWith(at + "/")));
                assert.ok(ours.length < RENDERED.length, "the render holds the mailbox");
                for (const name of ours) same(folder, name);
                assert.deepEqual(recordOf(folder), ours, label + ": the record names VGS's files alone");
                assert.equal(Home.baseSet(folder), ".agents/skills");
            }
        },
        // A kendex lock VGS cannot read refuses the home by its cause, and the
        // open writes nothing: VGS cannot tell which files are kendex's.
        kendexLock(Home) {
            for (const [label, cause, plant] of [
                ["link", "link", (at, outside) => { fs.writeFileSync(outside, JSON.stringify({ entries: {} })); fs.symlinkSync(outside, at); }],
                ["folder", "kind", at => fs.mkdirSync(at)],
                ["malformed", "kendex-lock", at => fs.writeFileSync(at, "{")],
                ["no entries", "kendex-lock", at => fs.writeFileSync(at, "{\"version\": 11}\n")],
                ["null entries", "kendex-lock", at => fs.writeFileSync(at, "{\"entries\": null}\n")],
                ["text entries", "kendex-lock", at => fs.writeFileSync(at, "{\"entries\": \"skill:jarvis\"}\n")]
            ]) {
                const folder = fresh();
                Home.layout(folder);
                fs.appendFileSync(path.join(folder, RENDER, "persona.md"), "mine\n");
                const outside = path.join(path.dirname(folder), "outside");
                plant(path.join(folder, LOCK), outside);
                const before = stamps(folder, [...RENDERED, RECORD]);
                keyed(() => Home.layout(folder), cause, label);
                assert.deepEqual(stamps(folder, [...RENDERED, RECORD]), before, label + ": nothing is written");
                keyed(() => Home.release(folder), cause, label + ": release");
                assert.deepEqual(stamps(folder, [...RENDERED, RECORD]), before, label + ": nothing is removed");
            }
        },
        // Release, before kendex installs over a home VGS laid out: every
        // file VGS recorded goes, with each folder that leaves empty, and the
        // record, but a file at a path kendex's lock names and every file of
        // the user's; a home without a record is left as it is. The next
        // layout writes the package again.
        release(Home) {
            const folder = fresh();
            Home.layout(folder);
            const own = { "AGENTS.md": "# Mine\n", ".claude/agents/mine.md": "# My agent\n", "skills/own/mine.md": "# Mine\n" };
            for (const [name, text] of Object.entries(own)) write(folder, name, text);
            const before = stamps(folder, Object.keys(own));
            assert.doesNotThrow(() => Home.release(folder));
            assert.deepEqual(RENDERED.filter(name => fs.existsSync(path.join(folder, name))), [], "every file VGS wrote goes");
            // The home's own top-level entries stay, an emptied .agents among them.
            assert.deepEqual(listing(folder), [...new Set([...FILES, ...FOLDERS, ".agents", ...withFolders(Object.keys(own))])].sort(),
                "the record and every folder below them the removal left empty go");
            assert.deepEqual(stamps(folder, Object.keys(own)), before, "the user's files keep every byte");
            assert.doesNotThrow(() => Home.release(folder), "a home without a record");
            assert.deepEqual(stamps(folder, Object.keys(own)), before);
            assert.doesNotThrow(() => Home.layout(folder));
            shipped(folder, Object.keys(own));
            // kendex took the mailbox meanwhile: its files stay.
            const mailbox = ".agents/skills/mailbox";
            writeLock(folder, [lockEntry("skill", "mailbox", "codex", [mailbox])]);
            const kept = RENDERED.filter(name => name.startsWith(mailbox + "/"));
            const held = stamps(folder, kept);
            assert.doesNotThrow(() => Home.release(folder));
            assert.deepEqual(stamps(folder, kept), held, "a file at a path kendex's lock names stays");
            assert.deepEqual(RENDERED.filter(name => !kept.includes(name) && fs.existsSync(path.join(folder, name))), [], "the rest goes");
            assert.equal(fs.existsSync(path.join(folder, RECORD)), false, "and the record");
            // A kendex home holds no record of VGS's: nothing goes.
            const kendexHome = kendex();
            const untouched = kendexStamps(kendexHome);
            assert.doesNotThrow(() => Home.release(kendexHome));
            assert.deepEqual(kendexStamps(kendexHome), untouched, "a home without a record is left as it is");
        },
        // A kendex render that is partial, a link, or no tree of folders and
        // regular files refuses the home with its cause, at the open and at
        // each read, and the open writes no package file.
        renderRefused(Home) {
            const outside = path.join(home, "homes", "render-outside");
            fs.cpSync(path.join(SHIPPED, RENDER), outside, { recursive: true });
            const agents = path.join(home, "homes", "agents-outside");
            fs.cpSync(path.join(SHIPPED, RENDER), path.join(agents, "skills/jarvis"), { recursive: true });
            for (const [label, cause, spoil] of [
                ["no SKILL.md", "package", folder => fs.rmSync(path.join(folder, RENDER, "SKILL.md"))],
                ["no persona.md", "package", folder => fs.rmSync(path.join(folder, RENDER, "persona.md"))],
                ["linked .agents", "link", folder => relink(folder, ".agents", agents)],
                ["linked render", "link", folder => relink(folder, RENDER, outside)],
                ["linked SKILL.md", "link", folder => relink(folder, RENDER + "/SKILL.md", path.join(outside, "SKILL.md"))],
                ["linked reference", "link", folder => relink(folder, RENDER + "/references/memory.md", path.join(outside, "references/memory.md"))],
                ["file render", "kind", folder => { fs.rmSync(path.join(folder, RENDER), { recursive: true }); fs.writeFileSync(path.join(folder, RENDER), ""); }],
                ["fifo inside", "kind", folder => assert.equal(cp.spawnSync("python3", ["-c", "import os, sys; os.mkfifo(sys.argv[1])",
                    path.join(folder, RENDER, "references/fifo.md")]).status, 0, "the test makes a FIFO")]
            ]) {
                const folder = kendex();
                spoil(folder);
                const before = kendexStamps(folder);
                keyed(() => Home.layout(folder), cause, label);
                assert.deepEqual(kendexStamps(folder), before, label + ": the refused open writes no package file");
                assert.equal(fs.existsSync(path.join(folder, RECORD)), false, label + ": nor a record");
                keyed(() => Home.skills(folder), cause, label + ": the index");
                keyed(() => Home.skill(folder, "base/jarvis"), cause, label + ": the skill");
            }
        }
    };
    // A home kendex installed the package in, never opened by VGS: kendex's
    // render of the package in both harnesses with its lock, the jarvis
    // skill in another version than the shipped one, with one more
    // workflow, beside another kendex skill and a flat jarvis.md that is no
    // part of the render.
    function kendex() {
        const folder = fresh();
        for (const harness of HARNESS) fs.cpSync(path.join(SHIPPED, harness), path.join(folder, harness), { recursive: true });
        writeLock(folder, [...SHIPPED_ENTRIES, lockEntry("skill", "orch", "codex", [".agents/skills/orch"])]);
        const render = path.join(folder, RENDER);
        fs.writeFileSync(path.join(render, "SKILL.md"), "---\nname: jarvis\ndescription: Render.\n---\nRENDER-MARKER\n");
        fs.writeFileSync(path.join(render, "persona.md"), "# Render persona\n");
        fs.writeFileSync(path.join(render, "workflows/run.md"), "# Run\n");
        write(folder, ".agents/skills/orch/SKILL.md", "# Orch\n");
        fs.writeFileSync(path.join(folder, ".agents/skills/jarvis.md"), "FLAT\n");
        return folder;
    }
    function relink(folder, entry, target) {
        fs.rmSync(path.join(folder, entry), { recursive: true });
        fs.symlinkSync(target, path.join(folder, entry));
    }
    // CHECK on the Home.js of a copy of the backend in BACKEND whose tree
    // holds a copy of the shipped render SPOIL changed, and on the copy's
    // {backend, root}.
    function withRender(backend, spoil, check) {
        const outer = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "render-"));
        try {
            const plugin = path.join(outer, "plugin");
            fs.cpSync(backend, path.join(plugin, "backend"), { recursive: true });
            for (const beside of ["AccountProviders.js", "manifest.json"])
                fs.copyFileSync(path.join(tree, "shell/plugins/vgs.jarvis", beside), path.join(plugin, beside));
            const root = scratchTree(outer, {});
            const render = path.join(root, "packaging/jarvis-home");
            fs.cpSync(SHIPPED, render, { recursive: true });
            spoil(render);
            useTree(path.join(plugin, "backend"), root);
            return check(require(path.join(plugin, "backend/Home.js")), { backend: path.join(plugin, "backend"), root });
        } finally { fs.rmSync(outer, { recursive: true, force: true }); }
    }
    // The gate keeps every model out of the render as out of the rest of the
    // home: no file tool, shell command or harness approval reaches it, and a
    // sandboxed command finds .agents masked. state/ is the control: open.
    function renderGate(Denied, Home = require(file)) {
        const folder = kendex();
        Home.layout(folder);
        const judge = Denied.create({ ...roots, jarvisHome: Home.guard(folder) });
        for (const entry of [".agents", ".agents/skills", RENDER, RENDER + "/SKILL.md", RENDER + "/persona.md", RENDER + "/references/new.md", RENDER + "/workflows/run.md"])
            for (const role of ["read", "tree-read", "write", "move", "remove", "workspace"])
                assert.equal(judge.inspect(path.join(folder, entry), role).reason, "protected-path", entry + " " + role);
        assert.equal(judge.masks.includes(path.join(folder, ".agents")), true, ".agents is masked from a sandboxed command");
        assert.equal(judge.inspect(path.join(folder, "state/note.md"), "write").kind, "path", "state/ stays open");
    }

    const Home = require(file);
    // The real daemon's accepted, repeated, cleared and refused snapshots.
    // These hellos start no conversation and use J09's scratch HOME.
    function currentHome(daemon) {
        const state = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "home-wire-"));
        const settings = { ...JSON.parse(fs.readFileSync(path.join(tree, "shell/plugins/vgs.jarvis/manifest.json"))).settings,
            sounds: false, voiceProvider: "local", dictation: "" };
        // The service keeps these settings; the daemon's hello holds none.
        for (const kept of ["localTier", "startAtBoot", "bootSession"]) delete settings[kept];
        const hello = { v: 1, type: "hello", gen: 0, revision: "a".repeat(64), locked: false,
            directories: { state, data: state + "/data", runtime: state + "/run" },
            keys: { talk: null, mute: null, stop: null, confirm: null, console: null } };
        const result = cp.spawnSync(process.execPath, [daemon, "--tree", tree], {
            input: ["~/wire-home", home + "/wire-home", "", "/etc/refused-home"].map(value =>
                JSON.stringify({ ...hello, settings: { ...settings, home: value } }) + "\n").join(""),
            env: { PATH: process.env.PATH, HOME: home, XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR,
                XDG_DATA_HOME: process.env.XDG_DATA_HOME }, encoding: "utf8", timeout: 10000
        });
        assert.ifError(result.error);
        assert.equal(result.status, 0, result.stderr);
        const messages = result.stdout.split("\n").filter(Boolean).map(JSON.parse).filter(row => row.type === "homes");
        assert.deepEqual(messages.map(row => row.current), ["", "~/wire-home", "~/wire-home", "", ""],
            "current names only the accepted home, normalized to the offer value");
        assert.equal(messages[1].homes[0].value, messages[1].current);
    }
    const daemon = path.join(path.dirname(file), "jarvisd.js");
    currentHome(daemon);
    console.log("case=currentHome passed");
    const daemonCopy = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "home-daemon-control-"));
    try {
        fs.cpSync(path.dirname(path.dirname(file)), daemonCopy, { recursive: true });
        const target = path.join(daemonCopy, "backend/jarvisd.js");
        const source = fs.readFileSync(target, "utf8");
        const needle = 'current: homeFolder.state.kind === "ready" ?';
        assert.equal(source.split(needle).length - 1, 1);
        const changed = source.replace(needle, 'current: false ?');
        assert.notEqual(changed, source);
        fs.writeFileSync(target, changed);
        assert.throws(() => currentHome(target), assert.AssertionError, "current home publication must turn red");
    } finally { fs.rmSync(daemonCopy, { recursive: true, force: true }); }
    console.log("control=currentHome detected");
    for (const [name, check] of Object.entries(CASES)) {
        check(Home);
        console.log("case=" + name + " passed");
    }
    renderGate(require(denied));
    console.log("case=renderGate passed");
    let controls = 0;
    for (const [name, needle, replacement, row, source = file] of [
        ["layout-entry", '    ["state", null],\n', "", "empty"],
        ["extra-file", '    ["state", null],\n', '    ["state", null], ["extra.md", ""],\n', "empty"],
        ["claude-memory", '"{\\"autoMemoryEnabled\\": false}\\n"', '"{}\\n"', "empty"],
        ["codex-memory", "generate_memories = false\\n", "", "empty"],
        ["scratch-left", "    } finally { fs.unlinkSync(scratch); }", "    } finally {}", "empty"],
        ["keeps-existing", "} else if (kind === \"absent\") createFile(parent, name, content);", "} else if (true) createFile(parent, name, content);", "keeps"],
        ["link-refused", '            const kind = kindOf(parent, name);\n            if (kind === "link") fail("link");\n',
            '            const kind = kindOf(parent, name);\n', "links"],
        ["home-link", 'case "link": return fail("link");', 'case "link": return fail("kind");', "links"],
        ["kind-refused", '                else if (kind !== "directory") fail("kind");\n', "\n", "kinds"],
        ["file-kind", '            else if (kind !== "file") fail("kind");', "", "kinds"],
        ["package-folder-kind", '            } else if (kind !== "directory") fail("kind");\n', "            }\n", "kinds"],
        // The render VGS copies: every emitted path of a skill or an agent,
        // each file's execute bit, and the lock's own rules.
        ["copy-every-path", "for (const at of entry.emitted.paths) {", 'for (const at of entry.emitted.paths.filter(at => !at.startsWith(".codex/"))) {', "acceptance"],
        ["executable-bit", "const mode = executable ? 0o755 : 0o644;", "const mode = 0o644;", "acceptance"],
        ["render-files", '        if (!RENDER_FILES.every(name => found.has(RENDER + "/" + PACKAGE + "/" + name))) fail("package");\n', "", "renderBroken"],
        ["declared-agent-present", " || !declared.agents.every(name => names.agent.has(name))", "", "renderBroken"],
        ["declared-skill-present", "![PACKAGE, ...declared.skills].every(name => names.skill.has(name)) || ", "", "renderBroken"],
        ["lock-version", "lock?.version !== LOCK_VERSION || ", "", "renderBroken"],
        ["render-plain-path", '                const parts = plainParts(at);\n                if (parts === null) fail("package");\n',
            '                const parts = at.split("/");\n', "renderBroken"],
        ["render-unreadable", '    } catch { return fail("package"); }\n', "    } catch (error) { throw error; }\n", "renderBroken"],
        // The record and the sync.
        ["sync-record-first", "    record(fd, [...new Set([...kept, ...names])]);\n", "", "interrupted"],
        ["record-final", "    record(fd, names);\n", "", "update"],
        ["drop-stale", "    for (const name of kept) if (!names.includes(name) && !under(name, claimed)) drop(fd, name);\n", "", "update"],
        ["drop-empty-folders", "for (let depth = chain.length - 1; depth > 1; depth--) {", "for (let depth = chain.length - 1; depth > chain.length; depth--) {", "update"],
        ["rewrite-changed", 'return same ? "same" : "differs";', 'return "same";', "update"],
        ["rewrite-mode", " && ((fs.fstatSync(held).mode & S_IXUSR) !== 0) === executable;", ";", "update"],
        ["unchanged-no-write", "    if (before !== null && same && stale.length === 0) return;\n", "", "keeps"],
        ["unchanged-compare", 'found.filter(([, state]) => state !== "same")', "found", "keeps"],
        ["user-file-kept", 'state !== "differs" || kept.includes(name)', "true", "update"],
        ["recorded-differs-rewritten", 'state !== "differs" || kept.includes(name)', 'state !== "differs"', "update"],
        ["replace-scratch-cleanup", "        fs.rmSync(child(fd, scratch), { force: true });\n        throw error;", "        throw error;", "interrupted"],
        ["claude-shim-removed", '            fs.unlinkSync(Core.anchored().child(held.get("."), claude));\n', "            void claude;\n", "claudeShim"],
        ["claude-shim-bytes", 'compare(held.get("."), claude, Buffer.from(shim), false) === "same"', "true", "claudeShim"],
        ["claude-shim-mode", 'Buffer.from(shim), false)', "Buffer.from(shim), true)", "claudeShim"],
        ["claude-shim-file", 'kindOf(held.get("."), claude) === "file" && ', "", "claudeShim"],
        ["kendex-home-untouched", "if (kendex?.jarvis) {", "if (false) {", "render"],
        ["kendex-home-not-restored", "if (kendex?.jarvis) {", "if (false) {", "removed"],
        ["kendex-any-harness", 'row?.kind === "skill" && row.name === PACKAGE', 'row?.kind === "skill" && row.name === PACKAGE && row.harness === "codex"', "claudeOnly"],
        ["kendex-record-dropped", '            if (before !== null) fs.unlinkSync(Core.anchored().child(held.get("."), RECORD));\n', "            void before;\n", "adopted"],
        ["claimed-skipped", "rendered().filter(([name]) => !under(name, claimed))", "rendered()", "fleet"],
        ["claimed-not-dropped", "if (!names.includes(name) && !under(name, claimed)) drop(fd, name);", "if (!names.includes(name)) drop(fd, name);", "fleet"],
        ["claimed-below", 'name === at || name.startsWith(at + "/")', "name === at", "fleet"],
        ["kendex-lock-link", '    if (kind === "link") fail("link");\n    if (kind !== "file") fail("kind");\n    const held = fs.openSync(Core.anchored().child(fd, LOCK)',
            '    if (kind !== "file") fail("kind");\n    const held = fs.openSync(Core.anchored().child(fd, LOCK)', "kendexLock"],
        ["kendex-lock-entries", '    if (entries === null || typeof entries !== "object") fail("kendex-lock");\n', "", "kendexLock"],
        ["kendex-lock-parse", "    catch {}\n    finally { fs.closeSync(held); }", "    catch (error) { throw error; }\n    finally { fs.closeSync(held); }", "kendexLock"],
        ["release-drop", "        for (const name of before) if (!under(name, kendex === null ? [] : kendex.paths)) drop(fd, name);\n", "", "release"],
        ["release-kendex-kept", "if (!under(name, kendex === null ? [] : kendex.paths)) drop(fd, name);", "drop(fd, name);", "release"],
        ["release-record", "        fs.unlinkSync(Core.anchored().child(fd, RECORD));\n", "", "release"],
        ["release-no-record", "        if (before === null) return;\n", "", "release"],
        ["emitted-paths-array", '            if (!Array.isArray(entry.emitted?.paths)) fail("package");\n', "", "renderBroken"],
        ["migration-removes-skills-base", '        fs.rmSync(Core.anchored().child(held.get("skills"), path.basename(OLD_COPY)), { recursive: true, force: true });\n',
            "        void OLD_COPY;\n", "migration"],
        ["package-link", '            if (kind === "link") fail("link");\n            if (kind === "absent") {', '            if (kind === "absent") {', "packageLinks"],
        ["package-file-link", '        if (kind === "absent") return "absent";\n        if (kind === "link") fail("link");', '        if (kind === "absent") return "absent";', "packageLinks"],
        ["record-link", '    if (kind === "link") fail("link");\n    if (kind !== "file") fail("kind");\n    const held = fs.openSync(Core.anchored().child(fd, RECORD)',
            '    if (kind !== "file") fail("kind");\n    const held = fs.openSync(Core.anchored().child(fd, RECORD)', "records"],
        ["record-shape", "!Array.isArray(files) || ", "", "records"],
        ["record-plain", " || !files.every(name => plainParts(name) !== null)", "", "records"],
        ["source-absent", 'if (kind === "absent") return fail("absent");', 'if (kind === "absent") return fail("package");', "removed"],
        // The declaration, rule by rule.
        ["declaration-front", '    if (lines[0].trim() !== "---" || end === -1) fail("declaration");\n', "", "declaration"],
        ["declaration-scope", "inside = /^dependencies:\\s*$/.test(line);", "inside = true;", "declaration"],
        ["declaration-flow", "            if (!flow) fail(\"declaration\");\n", "", "declaration"],
        ["declaration-block", "        found[open].push(...declaredNames([item[1]]));\n", "", "declaration"],
        ["declaration-item", '        if (!item) fail("declaration");\n', "        if (!item) continue;\n", "declaration"],
        ["declaration-name", '        if (!DECLARED_NAME.test(name)) fail("declaration");\n', "", "declaration"],
        ["declaration-catalog", 'const bundled = catalog === null ? bundle("") : bundle(catalog);', 'const bundled = bundle("");', "declaration"],
        ["declaration-once", "[...new Set(lists.flat())]", "lists.flat()", "declaration"],
        ["declaration-without-package", ".filter(name => name !== PACKAGE).sort();", ".sort();", "declaration"],
        ["declaration-sorted", ".filter(name => name !== PACKAGE).sort();", ".filter(name => name !== PACKAGE);", "declaration"],
        ["bundle-table-end", "const end = rest.findIndex(line => TABLE_HEADER.test(line.trim()));", "const end = -1;", "declaration"],
        ["bundle-duplicate", "if (assigned.length > 1 || arrays.length !== assigned.length)", "if (arrays.length !== assigned.length)", "declaration"],
        ["bundle-array", "if (assigned.length > 1 || arrays.length !== assigned.length)", "if (assigned.length > 1)", "declaration"],
        ["bundle-comment", '.map(line => line.replace(/\\s#.*$|^#.*$/, ""))', "", "declaration"],
        ["bundle-quoted", '            if (entries.some(item => !/^"[^"]*"$/.test(item))) fail("declaration");\n', "", "declaration"],
        ["inside-home", '!file.startsWith(base === "/" ? "/" : base + "/")', "false", "resolves"],
        ["path-bound", " || Buffer.byteLength(file) > PATH_BYTES", "", "resolves"],
        ["control-characters", ' || /[\\x00-\\x1f\\x7f]/.test(named)', "", "resolves"],
        ["open-entry", 'const OPEN = "state";', 'const OPEN = "skills";', "resolves"],
        ["remember-first", "return [folder].concat(found.filter(item => homeOffer(item, userHome).value !== choice.value)).slice(0, HOMES);",
            "return found.concat([folder]).slice(0, HOMES);", "rememberOffers"],
        ["remember-once", "homeOffer(item, userHome).value !== choice.value", "true", "rememberOffers"],
        ["remember-bound", "const HOMES = 10;", "const HOMES = 11;", "rememberOffers"],
        ["remember-offer-bound", "if (value.length > OFFER_VALUE_MAX) return null;", "", "rememberOffers"],
        ["remember-offer-label", 'label: value.length <= OFFER_LABEL_MAX ? value : "…" + value.slice(1 - OFFER_LABEL_MAX)',
            "label: value", "rememberOffers"],
        ["offer-id-path", '.update(path.resolve(folder))', '.update("same")', "rememberOffers"],
        ["offer-id-bound", '.slice(0, 12)', '.slice(0, 13)', "rememberOffers"],
        ["remember-offer-duplicate", "if (choice === null || seen.has(choice.value)) continue;", "if (choice === null) continue;", "rememberOffers"],
        ["offers-relative", 'return "~/" + relative.split(path.sep).join("/");',
            'return file;', "rememberOffers"],
        ["read-bound", 'if (limit !== null && content.length > limit) return { kind: "too-large" };', "", "reads"],
        ["read-utf8", '{ kind: "text", text: new TextDecoder("utf-8", { fatal: true })', '{ kind: "text", text: new TextDecoder("utf-8", { fatal: false })', "reads"],
        ["read-kind", 'if (!fs.fstatSync(fd).isFile()) fail("kind");', "", "reads"],
        ["read-link", [['if (kind === "absent" || kind === "link") fail(kind);', 'if (kind === "absent") fail(kind);'],
            ["(last ? flags : O_RDONLY | O_DIRECTORY) | O_NOFOLLOW", "(last ? flags : O_RDONLY | O_DIRECTORY)"]], null, "reads"],
        ["skill-name", " && Tools.homeTopic(topic) !== null)", ")", "skills"],
        ["folder-name", "if (Tools.homeTopic(topic) === null) continue;\n            // An entry", "// An entry", "skills"],
        ["reference-topics", '[["references", topic + "/"], ["workflows", topic + "/workflows/"]]', '[["workflows", topic + "/workflows/"]]', "empty"],
        ["workflow-topics", ', ["workflows", topic + "/workflows/"]]', "]", "skills"],
        ["workflow-own-topic", '["workflows", topic + "/workflows/"]', '["workflows", topic + "/"]', "skills"],
        ["reference-read", 'if (named.file !== null) return whole(base + "/" + named.folder + "/" + named.file + ".md");', "", "skills"],
        ["workflow-read", 'whole(base + "/" + named.folder + "/"', 'whole(base + "/references/"', "skills"],
        ["skill-whole", "const whole = file => read(home, file, null).text;", "const whole = file => read(home, file, 16384).text;", "skills"],
        ["skill-description", 'if (value !== "" && !BLOCK_SCALAR.test(value)) return value.slice(0, LINE_CHARS);', "", "skills"],
        ["skill-folded", " && !BLOCK_SCALAR.test(value)", "", "skills"],
        ["skill-folded-marks", "const BLOCK_SCALAR = /^[>|][-+1-9]{0,2}$/;", "const BLOCK_SCALAR = /^[>|]$/;", "skills"],
        ["skill-heading", '.replace(/^#+\\s*/, "")', "", "skills"],
        ["folder-kind", ' && (!last || flags & O_DIRECTORY)) fail("kind");', ' && !last) fail("kind");', "skills"],
        ["set-bound", "if (entries.length === SET_ENTRIES) return { entries, complete: false };", "", "skills"],
        ["note-rule", '    if (!Tools.memoryNote(entry)) fail("absent");\n', "", "notes"],
        ["note-folder", 'return read(home, "memory/" + entry, null).text;', "return read(home, entry, null).text;", "notes"],
        ["note-whole", 'return read(home, "memory/" + entry, null).text;', 'return read(home, "memory/" + entry, 16384).text;', "notes"],
        ["note-inbox", "(?!inbox/)", "", "notes", path.join(path.dirname(file), "Tools.js")],
        ["notes-list-kind", 'if (!stat.isFile() || !entry.name.endsWith(".md") || !Tools.memoryNote(id)) continue;', 'if (!stat.isFile()) continue;', "notesList"],
        ["notes-list-bound", 'if (found.length > NOTE_ENTRIES) fail("notes-too-many");', "", "notesList"],
        ["cutover-consumed", '            return false;\n        }\n        const record =', '            return true;\n        }\n        const record =', "cutover"],
        ["cutover-canonical", 'if (entry(MAIL_TOOL) !== "absent") return "refused";', '', "cutover"],
        ["tool-entry", 'const MAIL_TOOL = ".agents/skills/mailbox/scripts/lane-mail";', 'const MAIL_TOOL = "skills/own/lane-mail";', "mailTool"],
        ["tool-execute", " && (stat.mode & 0o100) !== 0", "", "mailTool"],
        ["tool-file", "stat.isFile() && (stat.mode", "(stat.mode", "mailTool"],
        ["own-repository", "    if (own !== true) return null;\n", "", "ownRepository"],
        ["own-repository-kind", "return stat.isDirectory() || stat.isFile();", "return true;", "ownRepository"],
        ["own-repository-link", [['if (kind === "absent" || kind === "link") fail(kind);', 'if (kind === "absent") fail(kind);'],
            ["(last ? flags : O_RDONLY | O_DIRECTORY) | O_NOFOLLOW", "(last ? flags : O_RDONLY | O_DIRECTORY)"]], null, "ownRepository"],
        ["own-repository-name", 'const OWN_REPOSITORY = ".git";', 'const OWN_REPOSITORY = ".agents";', "ownRepository"],
        ["mailbox-folder", 'const MAILBOX = "tmp/lane-mail/overseer";', 'const MAILBOX = "tmp/lane-mail";', "mailbox"],
        ["mailbox-kind", "return held(home, MAILBOX, O_RDONLY | O_DIRECTORY, () => true) === true;", "return held(home, MAILBOX, O_RDONLY | O_NONBLOCK, () => true) === true;", "mailbox"],
        ["tool-link", [['if (kind === "absent" || kind === "link") fail(kind);', 'if (kind === "absent") fail(kind);'],
            ["(last ? flags : O_RDONLY | O_DIRECTORY) | O_NOFOLLOW", "(last ? flags : O_RDONLY | O_DIRECTORY)"]], null, "mailTool"],
        ["render-place", 'const RENDER = ".agents/skills";', 'const RENDER = ".agents/skill";', "render"],
        ["render-package-alone", "if (folder === RENDER) listed =", "if (false) listed =", "render"],
        ["render-name", '    if (set === RENDER && named.name !== PACKAGE) fail("absent");\n', "", "render"],
        ["render-flat", "    if (set !== RENDER) {", "    if (true) {", "render"],
        ["render-partial", '        if (!RENDER_FILES.every(name => found.includes(name))) fail("package");\n', "", "renderRefused"],
        ["render-link", '            if (kind === "link") return fail("link");\n', "", "renderRefused"],
        ["render-inner-link", 'fail(kind === "link" ? "link" : "kind")', 'fail("kind")', "renderRefused"],
        ["render-tree", "const found = entries(at, 0).map(([name]) => name);", 'const found = fs.readdirSync("/proc/self/fd/" + at);', "renderRefused"],
    ]) {
        const result = mutant(source, name, needle, replacement, (logic, folder) => CASES[row](logic, folder), "Home.js");
        assert.equal(result, undefined);
        controls++;
        console.log("control=" + name + " detected");
    }
    // The gate's own rules, each held by the render's row.
    for (const [name, needle, replacement] of [
        ["render-gate", " || inJarvisHome(target.path, ancestor))", ")"],
        ["render-masks", "protectedRoots.concat(accounts, jarvisHomeMasks())", "protectedRoots.concat(accounts)"]
    ]) {
        assert.equal(mutant(denied, name, needle, replacement, logic => renderGate(logic), "Denied.js"), undefined);
        controls++;
        console.log("control=" + name + " detected");
    }
    // The project-instructions row: a home whose package copy carries a
    // well-formed block after the frontmatter fails that row, not the byte
    // comparison after it.
    const planted = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "planted-"));
    try {
        for (const harness of HARNESS) fs.cpSync(path.join(SHIPPED, harness), path.join(planted, harness), { recursive: true });
        const skill = path.join(planted, RENDER, "SKILL.md");
        const text = fs.readFileSync(skill, "utf8");
        const close = text.indexOf("\n---\n", 4) + "\n---\n".length;
        assert.equal(text.startsWith("---\n") && close > "\n---\n".length, true, "project-instructions frontmatter");
        fs.writeFileSync(skill, text.slice(0, close) + "\n<!-- " + PROJECT_INSTRUCTIONS + ":start -->\n## Project Instructions\n\nPlanted policy.\n<!-- "
            + PROJECT_INSTRUCTIONS + ":end -->\n" + text.slice(close));
        assert.notEqual(fs.readFileSync(skill, "utf8"), text);
        // An assertion's message carries its diff after the first line.
        assert.throws(() => shipped(planted),
            error => error instanceof assert.AssertionError && error.message.split("\n")[0] === NO_PROJECT_INSTRUCTIONS,
            "project-instructions must turn red");
    } finally { fs.rmSync(planted, { recursive: true, force: true }); }
    controls++;
    console.log("control=project-instructions detected");
    console.log("test-jarvis-home: ok cases=" + Object.keys(CASES).length + " controls=" + controls);
});
