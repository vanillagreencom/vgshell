#!/usr/bin/env node
// The Jarvis home folder owner, backend/Home.js, on real folders in J09's
// scratch HOME. kendex installs the Jarvis package and the package's init
// writes a home's starting files (D126), so every case builds its home
// itself; Home.js only judges and reads it: the judgement of a ready home,
// of a missing one, of one Setup has not set up and of a link or an entry
// of another kind, and that it writes nothing; whether kendex's lock names
// the package; the package's declaration as its SKILL.md states it; the
// folder a setting names, the remembered homes list and its Settings
// offers, the bounded read of its text, the skill index of the package,
// the skills it requires and skills, a memory note read by its path,
// the kendex mail tool and the session's mailbox; and a package that is
// partial or holds a link; and a fleet request to a project kendex lists,
// through the real ComputerHelp. Each control edits a copy of Home.js, or
// of the Tools.js or ComputerHelp.js rule it asks, one rule at a time, and
// must turn a case red.
"use strict";
const cp = require("node:child_process");
const { load } = require("../bin/lib/qml-library.js");
const { MENU_ID_PATTERN } = load(require("node:path").join(__dirname, "../shell/Core/PluginLogic.js"));
const { assert, fs, path, tree, world, seed, mutant } = require("./fixtures/jarvis/policy.js");
const { jarvisHome } = require("./fixtures/jarvis/home.js");
const file = path.join(tree, "shell/plugins/vgs.jarvis/backend/Home.js");
const denied = path.join(path.dirname(file), "Denied.js");

// Where kendex renders the jarvis skill in a home.
const RENDER = ".agents/skills/jarvis";
// The starting files the package's init writes
// (.agents/skills/jarvis/references/home-layout.md § Initialize).
const STARTING = ["AGENTS.md", "memory/MEMORY.md", "state"];
// Every entry below a folder, links and scratch files included.
function listing(folder) {
    return fs.readdirSync(folder, { recursive: true }).map(name => String(name)).sort();
}
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
// kendex's lock in a home, the record of what kendex installed there.
const LOCK = ".kendex-lock.json";
const lockEntry = (kind, name, harness, paths) =>
    [kind + ":" + name + ":" + harness, { name, kind, harness, source: "kendex", enabled: true, emitted: { kind, name, paths } }];
const writeLock = (folder, rows) => write(folder, LOCK, JSON.stringify({ version: 11, entries: Object.fromEntries(rows) }, null, 2) + "\n");
// The kendex mail tool in a home, where kendex's mailbox skill installs it.
const TOOL = ".agents/skills/mailbox/scripts/lane-mail";
// A home as Setup leaves it, with a small package of its own: the
// package's two files read by name, and its starting files. A case writes
// its own skill files before or after.
function ready(folder) {
    for (const [name, text] of [[RENDER + "/SKILL.md", "---\nname: jarvis\ndescription: The package.\n---\n# Jarvis\n"],
        [RENDER + "/persona.md", "# Persona\n"], ["AGENTS.md", "# Instructions\n"], ["memory/MEMORY.md", "# Memory index\n"]])
        if (!fs.existsSync(path.join(folder, name))) write(folder, name, text);
    fs.mkdirSync(path.join(folder, "state"), { recursive: true });
    return folder;
}
// The package's declaration: the front matter forms a SKILL.md takes.
const AGENTS_1_18 = "[cpa, legal, operator, auditor, researcher, scout, reviewer-arch]";
const SORTED_1_18 = ["auditor", "cpa", "legal", "operator", "researcher", "reviewer-arch", "scout"];
const front = dependencies => "---\nname: jarvis\ndescription: \"Load for Jarvis.\"\n" + dependencies + "metadata:\n  source: kendex\n---\n# Jarvis\n";
const DECLARATIONS = [
    ["v1.18", front("dependencies:\n  required: [mailbox]\n  agents: " + AGENTS_1_18 + "\n"), { skills: ["mailbox"], agents: SORTED_1_18 }],
    ["KEN-4957", front("dependencies:\n  required: [commit-guards, communication, docs-writing, mailbox, orch, slack]\n  optional: [linear]\n  agents: [cpa, publicist]\n"
        + "  commands:\n    - command: agent-browser\n      purpose: Browser automation\n      floor: \"0.26.0\"\n"),
        { skills: ["commit-guards", "communication", "docs-writing", "mailbox", "orch", "slack"], agents: ["cpa", "publicist"] }],
    ["block lists", front("dependencies:\n  required:\n    - mailbox\n    - \"orch\"\n  optional: anything\n  agents:\n    - scout\n    - cpa\n"),
        { skills: ["mailbox", "orch"], agents: ["cpa", "scout"] }],
    ["the package itself", front("dependencies:\n  required: [jarvis, mailbox, mailbox]\n"), { skills: ["mailbox"], agents: [] }],
    ["empty lists", front("dependencies:\n  required: []\n  agents: []\n"), { skills: [], agents: [] }],
    // Another map's list of the same name is no dependency.
    ["no dependencies", front("other:\n  required: [elsewhere]\n"), { skills: [], agents: [] }],
    ["no front matter", "# Jarvis\n", { skills: [], agents: [] }],
    ["scalar list", front("dependencies:\n  required: mailbox\n"), "declaration"],
    ["bad name", front("dependencies:\n  agents: [Scout]\n"), "declaration"],
    ["path name", front("dependencies:\n  required: [../mailbox]\n"), "declaration"],
    ["no list item", front("dependencies:\n  required:\n    mailbox\n"), "declaration"],
    ["front matter unclosed", "---\nname: jarvis\n", "declaration"]
];

world(async () => {
    const { home, roots } = seed();
    let serial = 0;
    const fresh = () => path.join(home, "homes", "h" + ++serial, "Jarvis");

    const CASES = {
        // A home Setup set up judges ready, and the judgement writes nothing;
        // no folder, a folder without the package or a starting file, and
        // an entry Jarvis cannot follow each refuse by their cause.
        judge(Home) {
            const folder = ready(fresh());
            const before = stamps(folder, listing(folder));
            for (let round = 0; round < 2; round++) assert.doesNotThrow(() => Home.judge(folder), "a ready home");
            assert.deepEqual(stamps(folder, listing(folder)), before, "the judgement writes nothing");
            // No folder in a parent that is there, and none under a parent
            // that is not.
            const missing = fresh();
            fs.mkdirSync(path.dirname(missing), { recursive: true });
            keyed(() => Home.judge(missing), "missing", "no folder");
            assert.equal(fs.existsSync(missing), false, "and none is made");
            const orphan = fresh();
            keyed(() => Home.judge(orphan), "missing", "no folder or parent");
            assert.equal(fs.existsSync(path.dirname(orphan)), false, "and no parent is made");
            const empty = fresh();
            fs.mkdirSync(empty, { recursive: true });
            keyed(() => Home.judge(empty), "not-set-up", "an empty folder");
            assert.deepEqual(fs.readdirSync(empty), [], "and nothing is written in it");
            for (const name of [...STARTING, ".agents"]) {
                const partial = ready(fresh());
                fs.rmSync(path.join(partial, name), { recursive: true });
                keyed(() => Home.judge(partial), "not-set-up", "a home without " + name);
            }
            for (const [label, cause, spoil] of [
                ["no SKILL.md", "package", at => fs.rmSync(path.join(at, RENDER, "SKILL.md"))],
                ["no persona.md", "package", at => fs.rmSync(path.join(at, RENDER, "persona.md"))],
                ["AGENTS.md a folder", "kind", at => { fs.rmSync(path.join(at, "AGENTS.md")); fs.mkdirSync(path.join(at, "AGENTS.md")); }],
                ["state a file", "kind", at => { fs.rmSync(path.join(at, "state"), { recursive: true }); fs.writeFileSync(path.join(at, "state"), ""); }],
                ["state a link", "link", at => { fs.rmSync(path.join(at, "state"), { recursive: true }); fs.symlinkSync(home, path.join(at, "state")); }],
                ["memory a link", "link", at => { fs.rmSync(path.join(at, "memory"), { recursive: true }); fs.symlinkSync(home, path.join(at, "memory")); }]
            ]) {
                const spoilt = ready(fresh());
                spoil(spoilt);
                keyed(() => Home.judge(spoilt), cause, label);
            }
            const target = ready(fresh());
            const linked = fresh();
            fs.mkdirSync(path.dirname(linked), { recursive: true });
            fs.symlinkSync(target, linked);
            keyed(() => Home.judge(linked), "link", "a home that is a link");
            const plain = fresh();
            write(path.dirname(plain), path.basename(plain), "a file\n");
            keyed(() => Home.judge(plain), "kind", "a home that is a file");
            // The shared fixture's home is one Jarvis judges ready.
            assert.doesNotThrow(() => Home.judge(jarvisHome(fresh(), tree)), "the suites' ready home");
        },
        // Whether kendex installed the package: its lock names the package's
        // skill, in any harness; a lock VGS cannot read refuses by its cause.
        packageInstalled(Home) {
            const folder = ready(fresh());
            assert.equal(Home.packageInstalled(folder), false, "no lock");
            writeLock(folder, [lockEntry("skill", "mailbox", "codex", [".agents/skills/mailbox"])]);
            assert.equal(Home.packageInstalled(folder), false, "a lock without the package");
            for (const harness of ["codex", "claude"]) {
                writeLock(folder, [lockEntry("skill", "jarvis", harness, [RENDER])]);
                assert.equal(Home.packageInstalled(folder), true, "the package in " + harness);
            }
            for (const [label, cause, plant] of [
                ["link", "link", (at, outside) => { fs.writeFileSync(outside, JSON.stringify({ entries: {} })); fs.symlinkSync(outside, at); }],
                ["folder", "kind", at => fs.mkdirSync(at)],
                ["malformed", "kendex-lock", at => fs.writeFileSync(at, "{")],
                ["no entries", "kendex-lock", at => fs.writeFileSync(at, "{\"version\": 11}\n")],
                ["null entries", "kendex-lock", at => fs.writeFileSync(at, "{\"entries\": null}\n")],
                ["text entries", "kendex-lock", at => fs.writeFileSync(at, "{\"entries\": \"skill:jarvis\"}\n")]
            ]) {
                const at = ready(fresh());
                plant(path.join(at, LOCK), path.join(path.dirname(at), "outside"));
                keyed(() => Home.packageInstalled(at), cause, label);
            }
        },
        declaration(Home) {
            for (const [label, skill, expected] of DECLARATIONS) {
                let got;
                try { got = Home.declaration(skill); }
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
            ready(folder);
            const agents = path.join(folder, "AGENTS.md");
            fs.writeFileSync(agents, "é".repeat(8));
            assert.deepEqual(Home.read(folder, "AGENTS.md", 16), { kind: "text", text: "é".repeat(8) }, "exactly the bound");
            assert.deepEqual(Home.read(folder, "AGENTS.md", 15), { kind: "too-large" }, "one byte over");
            fs.writeFileSync(agents, Buffer.from([0x66, 0xff]));
            keyed(() => Home.read(folder, "AGENTS.md", 16), "text");
            keyed(() => Home.read(folder, "memory/absent.md", 16), "absent");
            keyed(() => Home.read(folder, "state", 16), "kind");
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
        // and any other file is no skill. The base set is the package and
        // the skills its SKILL.md requires (D126): a required skill's
        // references and workflows read by topic without a line each, and a
        // skill it does not declare is no Jarvis skill.
        skills(Home) {
            const folder = fresh();
            const write = (name, text) => {
                fs.mkdirSync(path.dirname(path.join(folder, name)), { recursive: true });
                fs.writeFileSync(path.join(folder, name), text);
            };
            write(RENDER + "/SKILL.md", "---\nname: jarvis\ndescription: \"Load for the package.\"\ndependencies:\n  required: [communication, absent-skill]\n  agents: [scout]\n---\n# Jarvis\n");
            write(RENDER + "/persona.md", "# Persona\n");
            write(RENDER + "/references/base-one.md", "# Base reference\n");
            write(RENDER + "/workflows/run.md", "---\ndescription: Load to run the package.\n---\nRUN-BODY\n");
            // A required skill: its SKILL.md is listed, its references and
            // workflows are read by topic. kendex's other skills and a flat
            // file beside the package are no Jarvis skill.
            write(".agents/skills/communication/SKILL.md", "---\nname: communication\ndescription: Load before a message.\n---\n# Communication\n");
            write(".agents/skills/communication/references/voice.md", "VOICE-BODY\n");
            write(".agents/skills/communication/workflows/reply.md", "REPLY-BODY\n");
            write(".agents/skills/mailbox/SKILL.md", "# Mailbox\n");
            write(".agents/skills/stray.md", "# Stray\n");
            ready(folder);
            // A home without skills lists the base set alone.
            let bare;
            assert.doesNotThrow(() => { bare = Home.skills(folder); }, "a home without skills");
            assert.deepEqual(bare.skills.map(entry => entry.topic),
                ["base/communication", "base/jarvis", "base/jarvis/base-one", "base/jarvis/workflows/run"], "lists the base set alone");
            write("skills/beta/SKILL.md", "---\nname: beta\njarvis-voice: true\ndescription: \"Load for beta work.\"\n---\n# Beta\n");
            write("skills/gamma/SKILL.md", "---\nname: gamma\njarvis-voice: true\ndescription: >\n  folded\n---\n\nGamma first line\n");
            write("skills/epsilon/SKILL.md", "---\njarvis-voice: true\ndescription: >-\n  folded and stripped\n---\nEpsilon first line\n");
            write("skills/eta/SKILL.md", "---\njarvis-voice: true\ndescription: |+2\n    kept\n---\nEta first line\n");
            write("skills/notes.txt", "no skill\n");
            write("skills/plain", "no skill\n");
            // Each opts in, so the name rule alone leaves it unlisted.
            write("skills/.hidden.md", "---\njarvis-voice: true\n---\nno skill\n");
            write("skills/bad name.md", "---\njarvis-voice: true\n---\nno skill\n");
            write("skills/bad dir/SKILL.md", "---\njarvis-voice: true\n---\nno skill\n");
            write("skills/empty-folder/readme.md", "no skill\n");
            write("skills/beta/references/one.md", "# One reference\nONE-BODY\n");
            // A file without front matter and an empty file are references of
            // an opted-in skill: an own skill without the key is unlisted.
            write("skills/beta/references/alpha.md", "\n# Alpha skill\nbody\n");
            write("skills/beta/references/delta.md", "");
            // A reference is read on demand: no size bound holds it back.
            const long = "# Long reference\n" + "long line\n".repeat(4096);
            assert.ok(Buffer.byteLength(long) > 40 * 1024);
            write("skills/beta/references/long.md", long);
            write("skills/beta/references/bad name.md", "no skill\n");
            write("skills/beta/references/notes.txt", "no skill\n");
            write("skills/empty-folder/references/orphan.md", "no skill\n");
            write("skills/zeta/SKILL.md", "---\njarvis-voice: true\n---\n# Zeta\n");
            write("skills/zeta/references", "a file, not a folder\n");
            // A workflow passes every rule a reference does, and one of a
            // reference's file name is its own topic, never a silent pick.
            write("skills/beta/workflows/one.md", "# One workflow\nONE-WORKFLOW\n");
            write("skills/beta/workflows/long.md", long.replace("reference", "workflow"));
            write("skills/beta/workflows/bad name.md", "no skill\n");
            write("skills/beta/workflows/notes.txt", "no skill\n");
            write("skills/empty-folder/workflows/orphan.md", "no skill\n");
            write("skills/zeta/workflows", "a file, not a folder\n");
            write("skills/kappa/SKILL.md", "---\njarvis-voice: true\n---\n# Kappa\n");
            write("skills/kappa/workflows/run.md", "---\ndescription: Load to run kappa.\n---\nRUN-BODY\n");
            // An own skill without the key, or a flat one with another value,
            // stays with Jarvis main: neither it nor its reference or workflow
            // is listed.
            write("skills/ledger/SKILL.md", "---\nname: ledger\ndescription: Load for the accounts.\n---\n# Ledger\n");
            write("skills/ledger/references/accounts.md", "# Accounts\n");
            write("skills/ledger/workflows/close.md", "# Close the books\n");
            write("skills/ledger-notes.md", "---\njarvis-voice: false\n---\n# Ledger notes\n");
            const outside = path.join(path.dirname(folder), "outside-skill.md");
            fs.writeFileSync(outside, "OUTSIDE-SECRET\n");
            fs.symlinkSync(outside, path.join(folder, "skills/linked.md"));
            fs.mkdirSync(path.join(folder, "skills/linked-folder"));
            fs.symlinkSync(outside, path.join(folder, "skills/linked-folder/SKILL.md"));
            fs.symlinkSync(outside, path.join(folder, "skills/beta/workflows/linked.md"));
            fs.mkdirSync(path.join(folder, "skills/linked-workflows"));
            fs.writeFileSync(path.join(folder, "skills/linked-workflows/SKILL.md"), "---\njarvis-voice: true\n---\n# Linked workflows\n");
            fs.symlinkSync(path.join(folder, "skills/beta/workflows"), path.join(folder, "skills/linked-workflows/workflows"));
            assert.equal(cp.spawnSync("python3", ["-c", "import os, sys; os.mkfifo(sys.argv[1])",
                path.join(folder, "skills/beta/workflows/fifo.md")]).status, 0, "the test makes a FIFO");
            let listed;
            assert.doesNotThrow(() => { listed = Home.skills(folder); });
            assert.deepEqual(listed, { complete: true, skills: [
                { topic: "base/communication", file: ".agents/skills/communication/SKILL.md", line: "Load before a message." },
                { topic: "base/jarvis", file: RENDER + "/SKILL.md", line: "Load for the package." },
                { topic: "base/jarvis/base-one", file: RENDER + "/references/base-one.md", line: "Base reference" },
                { topic: "base/jarvis/workflows/run", file: RENDER + "/workflows/run.md", line: "Load to run the package." },
                { topic: "own/beta", file: "skills/beta/SKILL.md", line: "Load for beta work." },
                { topic: "own/beta/alpha", file: "skills/beta/references/alpha.md", line: "Alpha skill" },
                { topic: "own/beta/delta", file: "skills/beta/references/delta.md", line: "" },
                { topic: "own/beta/long", file: "skills/beta/references/long.md", line: "Long reference" },
                { topic: "own/beta/one", file: "skills/beta/references/one.md", line: "One reference" },
                { topic: "own/beta/workflows/long", file: "skills/beta/workflows/long.md", line: "Long workflow" },
                { topic: "own/beta/workflows/one", file: "skills/beta/workflows/one.md", line: "One workflow" },
                { topic: "own/epsilon", file: "skills/epsilon/SKILL.md", line: "Epsilon first line" },
                { topic: "own/eta", file: "skills/eta/SKILL.md", line: "Eta first line" },
                { topic: "own/gamma", file: "skills/gamma/SKILL.md", line: "Gamma first line" },
                { topic: "own/kappa", file: "skills/kappa/SKILL.md", line: "Kappa" },
                { topic: "own/kappa/workflows/run", file: "skills/kappa/workflows/run.md", line: "Load to run kappa." },
                { topic: "own/linked-workflows", file: "skills/linked-workflows/SKILL.md", line: "Linked workflows" },
                { topic: "own/zeta", file: "skills/zeta/SKILL.md", line: "Zeta" }], rules: { kind: "none" } });
            for (const entry of listed.skills) assert.doesNotThrow(() => Home.skill(folder, entry.topic), "every listed topic reads back: " + entry.topic);
            assert.equal(Home.skill(folder, "own/beta/alpha"), "\n# Alpha skill\nbody\n");
            assert.equal(Home.skill(folder, "own/beta").includes("# Beta"), true, "a folder's SKILL.md is its body");
            assert.equal(Home.skill(folder, "own/beta/one"), "# One reference\nONE-BODY\n");
            assert.equal(Home.skill(folder, "own/beta/long"), long, "a 40 KB reference reads whole");
            assert.equal(Home.skill(folder, "own/beta/workflows/one"), "# One workflow\nONE-WORKFLOW\n", "a workflow keeps its own topic");
            assert.equal(Home.skill(folder, "own/beta/workflows/long"), long.replace("reference", "workflow"), "a 40 KB workflow reads whole");
            assert.equal(Home.skill(folder, "own/kappa/workflows/run"), "---\ndescription: Load to run kappa.\n---\nRUN-BODY\n");
            assert.equal(Home.skill(folder, "base/jarvis/workflows/run"), "---\ndescription: Load to run the package.\n---\nRUN-BODY\n");
            assert.equal(Home.skill(folder, "base/communication/voice"), "VOICE-BODY\n", "a required skill's reference reads by topic");
            assert.equal(Home.skill(folder, "base/communication/workflows/reply"), "REPLY-BODY\n", "and its workflow");
            for (const [topic, cause] of [["own/missing", "absent"], ["own/../../secret", "absent"], ["other/alpha", "absent"],
                ["own/linked", "link"], ["own/linked-folder", "link"], ["own/beta/two", "absent"], ["own/beta/workflows/two", "absent"],
                ["own/beta/workflows/linked", "link"], ["own/linked-workflows/workflows/one", "link"], ["own/beta/workflows/fifo", "kind"],
                ["own/beta/workflows/bad name", "absent"], ["own/beta/references/one", "absent"], ["own/zeta/workflows/one", "kind"],
                ["base/mailbox", "absent"], ["base/stray", "absent"], ["base/absent-skill", "absent"], ["base/scout", "absent"]])
                keyed(() => Home.skill(folder, topic), cause, topic);
            // A folder past its entry bound answers incomplete, never a part as the whole.
            for (let index = 0; index < 257; index++) write("skills/beta/workflows/w" + index + ".md", "x\n");
            assert.equal(Home.skills(folder).complete, false, "a workflows folder past its bound");
            fs.rmSync(path.join(folder, "skills/beta/workflows"), { recursive: true });
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
            ready(folder);
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
            ready(folder);
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
            ready(crowded);
            for (let n = 0; n < 10001; n++) fs.writeFileSync(path.join(crowded, "memory", "n" + n + ".md"), "note\n");
            keyed(() => Home.notes(crowded), "notes-too-many");
        },
        // The mail tool is the one program Jarvis starts from the home: an
        // executable file at TOOL is its path, and the same file anywhere
        // else in the home is none, as is TOOL that is no executable regular
        // file or is reached through a link.
        mailTool(Home) {
            const folder = fresh();
            ready(folder);
            fs.mkdirSync(path.join(folder, ".git"));
            const plant = (entry, mode = 0o755) => {
                fs.mkdirSync(path.dirname(path.join(folder, entry)), { recursive: true });
                fs.writeFileSync(path.join(folder, entry), "#!/bin/sh\n", { mode });
            };
            assert.equal(Home.mailTool(folder), null, "a home without the canonical mail tool");
            for (const entry of ["skills/lane-mail", ".agents/skills/orch/scripts/workflow-state", ".agents/skills/other/scripts/lane-mail",
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
        // lane-mail takes the repository its working folder belongs to, so
        // the tool counts only in a home that is its own repository: one
        // with a .git folder, or a worktree's .git file, of its own. A home
        // inside another repository with none, as this scratch HOME lies
        // inside this checkout, or with a linked .git, has no tool.
        ownRepository(Home) {
            const folder = fresh();
            ready(folder);
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
            ready(folder);
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
        // A package that is partial, a link, or no tree of folders and
        // regular files refuses the home with its cause, at the judgement and
        // at each read.
        renderRefused(Home) {
            const outside = path.join(home, "homes", "render-outside");
            ready(path.join(home, "homes", "render-source"));
            fs.cpSync(path.join(home, "homes", "render-source", RENDER), outside, { recursive: true });
            write(outside, "references/memory.md", "# Memory\n");
            for (const [label, cause, spoil] of [
                ["no SKILL.md", "package", folder => fs.rmSync(path.join(folder, RENDER, "SKILL.md"))],
                ["no persona.md", "package", folder => fs.rmSync(path.join(folder, RENDER, "persona.md"))],
                ["linked .agents", "link", folder => relink(folder, ".agents", path.dirname(outside))],
                ["linked render", "link", folder => relink(folder, RENDER, outside)],
                ["linked SKILL.md", "link", folder => relink(folder, RENDER + "/SKILL.md", path.join(outside, "SKILL.md"))],
                ["linked reference", "link", folder => relink(folder, RENDER + "/references/memory.md", path.join(outside, "references/memory.md"))],
                ["file render", "kind", folder => { fs.rmSync(path.join(folder, RENDER), { recursive: true }); fs.writeFileSync(path.join(folder, RENDER), ""); }],
                ["fifo inside", "kind", folder => assert.equal(cp.spawnSync("python3", ["-c", "import os, sys; os.mkfifo(sys.argv[1])",
                    path.join(folder, RENDER, "references/fifo.md")]).status, 0, "the test makes a FIFO")]
            ]) {
                const folder = ready(fresh());
                write(folder, RENDER + "/references/memory.md", "# Memory\n");
                spoil(folder);
                keyed(() => Home.judge(folder), cause, label);
                keyed(() => Home.skills(folder), cause, label + ": the index");
                keyed(() => Home.skill(folder, "base/jarvis"), cause, label + ": the skill");
            }
        }
    };
    function relink(folder, entry, target) {
        fs.rmSync(path.join(folder, entry), { recursive: true });
        fs.symlinkSync(target, path.join(folder, entry));
    }
    // A fleet request naming a project goes to the overseer mailbox of a
    // project kendex lists, through the real ComputerHelp on real folders:
    // kendex is a synthetic program on the scratch PATH that prints the
    // document a row chooses (`kendex project list --json`, kendex v1.21.0
    // crates/cli/src/commands/project.rs), and each lane-mail records its
    // runs and keeps its mailbox in --root/box. A worktree entry stands for
    // its main checkout; a link anywhere on the way refuses; one entry of
    // another shape leaves the whole list unread. The home's own request
    // is the control that the project route left it alone.
    async function listedProjects(Help) {
        const base = path.join(home, "listed", String(++serial));
        const bin = path.join(base, "bin");
        const runs = path.join(base, "runs");
        const reply = path.join(base, "kendex-reply");
        write(bin, "kendex", "#!" + process.execPath + "\nconst r = JSON.parse(require('node:fs').readFileSync(" + JSON.stringify(reply)
            + ", 'utf8'));\nprocess.stdout.write(r.stdout);\nprocess.exit(r.code);\n", 0o755);
        const laneMail = "#!" + process.execPath + `
const fs = require('node:fs'), path = require('node:path'), a = process.argv.slice(2), opt = name => a[a.indexOf(name) + 1];
fs.appendFileSync(${JSON.stringify(runs)}, JSON.stringify({ tool: __filename, cwd: process.cwd(), root: opt('--root') }) + '\\n');
const box = path.join(opt('--root'), 'box'), rows = fs.existsSync(box) ? fs.readFileSync(box, 'utf8').split('\\n').filter(Boolean) : [];
if (a[0] === 'events') { console.log('count=' + rows.length + ' first='); for (const row of rows.slice(Number(opt('--after')))) console.log(row); }
if (a[0] === 'send') { const id = 'row-' + (rows.length + 1); fs.appendFileSync(box, JSON.stringify({ id }) + '\\n'); console.log('lane-mail: sent item=overseer id=' + id + ' bytes=1 monitor=none'); }
`;
        const project = (name, tool = TOOL) => {
            const folder = path.join(base, name);
            fs.mkdirSync(path.join(folder, ".git"), { recursive: true });
            if (tool !== null) write(folder, tool, laneMail, 0o755);
            return folder;
        };
        const boxOf = folder => fs.existsSync(path.join(folder, "box")) ? fs.readFileSync(path.join(folder, "box"), "utf8").split("\n").filter(Boolean) : [];
        const own = project("home");
        const listed = project("listed");
        const main = project("main");
        const worktree = project("worktree");
        const stranger = project("stranger");
        const bare = project("bare", null);
        const linkway = project("linkway", null);
        write(path.join(base, "outside"), "scripts/lane-mail", laneMail, 0o755);
        fs.mkdirSync(path.join(linkway, ".agents/skills/mailbox"), { recursive: true });
        fs.symlinkSync(path.join(base, "outside/scripts"), path.join(linkway, ".agents/skills/mailbox/scripts"));
        project("real/inner");
        fs.symlinkSync(path.join(base, "real"), path.join(base, "alias"));
        const aliased = path.join(base, "alias/inner");
        const second = project("second", ".agents/skills/orch/scripts/lane-mail");
        const entry = (folder, linked = null, state = "ok") => ({ folder, state, worktree: linked });
        const document = [entry(listed), entry(worktree, { main }), entry(bare), entry(linkway), entry(aliased), entry(second),
            entry(path.join(base, "gone"), null, "folder-not-found")];
        const ok = { code: 0, stdout: JSON.stringify(document, null, 2) };
        const help = Help.create(undefined, null, () => own,
            { PATH: bin + ":" + process.env.PATH, HOME: process.env.HOME, XDG_CONFIG_HOME: process.env.XDG_CONFIG_HOME }, () => true);
        try {
            // The row, the project named, kendex's answer, the outcome (the
            // failed cause after fleet-request:), and the folder whose
            // lane-mail alone runs, or null for none.
            for (const [label, named, answer, want, ran] of [
                ["a listed project", listed, ok, "completed", listed],
                ["a worktree entry's main checkout", main, ok, "completed", main],
                ["the worktree entry's own folder", worktree, ok, "project-unlisted", null],
                ["an unlisted project", stranger, ok, "project-unlisted", null],
                ["a listed project with no lane-mail", bare, ok, "mail-tool-absent", null],
                ["a linked folder on the way to lane-mail", linkway, ok, "mail-tool-absent", null],
                ["a listed folder through a linked ancestor", aliased, ok, "mail-tool-absent", null],
                ["a second program name", second, ok, "mail-tool-absent", null],
                ["kendex exits non-zero", listed, { code: 1, stdout: "" }, "projects-unread", null],
                ["a malformed entry", listed, { code: 0, stdout: JSON.stringify([...document, { folder: 7, state: "ok", worktree: null }]) }, "projects-unread", null],
                ["the home's own request", undefined, ok, "completed", own]
            ]) {
                fs.writeFileSync(reply, JSON.stringify(answer));
                fs.rmSync(runs, { force: true });
                const before = ran === null ? [] : boxOf(ran);
                const args = named === undefined ? { text: "Rebase the lanes." } : { text: "Rebase the lanes.", project: named };
                const result = await new Promise(resolve => help.start({ id: "fleet.request", args }, resolve));
                assert.equal(result.outcome === "completed" ? "completed" : result.content.replace(/^fleet-request:/, ""), want, label + ": " + result.content);
                const ranTools = fs.existsSync(runs) ? fs.readFileSync(runs, "utf8").trim().split("\n").map(line => JSON.parse(line)) : [];
                if (ran === null) { assert.deepEqual(ranTools, [], label + ": no lane-mail runs"); continue; }
                assert.deepEqual([...new Set(ranTools.map(run => JSON.stringify(run)))].map(run => JSON.parse(run)),
                    [{ tool: path.join(ran, TOOL), cwd: ran, root: ran }], label + ": that folder's own lane-mail alone runs, in it");
                assert.equal(boxOf(ran).length, before.length + 1, label + ": one row lands in that mailbox");
            }
        } finally { await help.close(); }
    }
    // The gate keeps every model out of the package as out of the rest of
    // the home: no file tool, shell command or harness approval reaches it,
    // and a sandboxed command finds .agents masked. state/ is the control: open.
    function renderGate(Denied, Home = require(file)) {
        const folder = ready(fresh());
        write(folder, RENDER + "/workflows/run.md", "# Run\n");
        Home.judge(folder);
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
        ready(path.join(home, "wire-home"));
        const state = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "home-wire-"));
        const settings = { ...JSON.parse(fs.readFileSync(path.join(tree, "shell/plugins/vgs.jarvis/manifest.json"))).settings,
            sounds: false, voiceProvider: "local", dictation: "" };
        // The service keeps these settings; the daemon's hello holds none.
        for (const kept of ["localTier", "startAtBoot", "bootSession"]) delete settings[kept];
        const hello = { v: 1, type: "hello", gen: 0, revision: "a".repeat(64), locked: false,
            directories: { state, data: state + "/data", runtime: state + "/run" },
            keys: { talk: null, deny: null, stop: null, confirm: null, console: null, "voice-mute": null } };
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
    const help = path.join(path.dirname(file), "ComputerHelp.js");
    await listedProjects(require(help));
    console.log("case=listedProjects passed");
    let controls = 0;
    for (const [name, needle, replacement, row, source = file] of [
        ["home-link", 'case "link": return fail("link");', 'case "link": return fail("kind");', "judge"],
        ["kendex-any-harness", 'row?.kind === "skill" && row.name === PACKAGE', 'row?.kind === "skill" && row.name === PACKAGE && row.harness === "claude"', "packageInstalled"],
        ["kendex-lock-link", '    if (kind === "link") fail("link");\n    if (kind !== "file") fail("kind");\n    const held = fs.openSync(Core.anchored().child(fd, LOCK)',
            '    if (kind !== "file") fail("kind");\n    const held = fs.openSync(Core.anchored().child(fd, LOCK)', "packageInstalled"],
        ["kendex-lock-entries", '    if (rows === null || typeof rows !== "object") fail("kendex-lock");\n', "", "packageInstalled"],
        ["kendex-lock-parse", "    catch {}\n    finally { fs.closeSync(held); }", "    catch (error) { throw error; }\n    finally { fs.closeSync(held); }", "packageInstalled"],
        ["source-absent", 'if (kind === "absent") return fail("absent");', 'if (kind === "absent") return fail("package");', "judge"],
        ["declaration-scope", "inside = /^dependencies:\\s*$/.test(line);", "inside = true;", "declaration"],
        ["declaration-flow", "            if (!flow) fail(\"declaration\");\n", "", "declaration"],
        ["declaration-block", "        found[open].push(...declaredNames([item[1]]));\n", "", "declaration"],
        ["declaration-item", '        if (!item) fail("declaration");\n', "        if (!item) continue;\n", "declaration"],
        ["declaration-name", '        if (!DECLARED_NAME.test(name)) fail("declaration");\n', "", "declaration"],
        ["declaration-once", "[...new Set(list)]", "list", "declaration"],
        ["declaration-without-package", ".filter(name => name !== PACKAGE).sort();", ".sort();", "declaration"],
        ["declaration-sorted", ".filter(name => name !== PACKAGE).sort();", ".filter(name => name !== PACKAGE);", "declaration"],
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
        ["workflow-topics", ', ["workflows", topic + "/workflows/"]]', "]", "skills"],
        ["workflow-own-topic", '["workflows", topic + "/workflows/"]', '["workflows", topic + "/"]', "skills"],
        ["reference-read", 'if (named.file !== null) return offered(base + "/SKILL.md", base + "/" + named.folder + "/" + named.file + ".md");', "", "skills"],
        ["workflow-read", 'base + "/" + named.folder + "/"', 'base + "/references/"', "skills"],
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
        ["tool-entry", 'const MAIL_TOOL = ".agents/skills/mailbox/scripts/lane-mail";', 'const MAIL_TOOL = "skills/lane-mail";', "mailTool"],
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
        ["render-place", 'const RENDER = ".agents/skills";', 'const RENDER = ".agents/skill";', "skills"],
        ["own-place", [['set === "base" ? base : "skills"', 'set === "base" ? base : "private-skills"'],
            ['named.set === "base" ? baseSet(home) : "skills"', 'named.set === "base" ? baseSet(home) : "private-skills"']], null, "skills"],
        ["render-partial", '        if (!RENDER_FILES.every(name => found.includes(name))) fail("package");\n', "", "renderRefused"],
        ["render-link", '            if (kind === "link") return fail("link");\n', "", "renderRefused"],
        ["render-inner-link", 'fail(kind === "link" ? "link" : "kind")', 'fail("kind")', "renderRefused"],
        // D126: the judge reads a home and writes nothing; the base set is
        // the package and the skills it requires.
        ["home-missing", 'case "absent": return fail("missing");', 'case "absent": return fail("unreadable");', "judge"],
        ["judge-starting", 'const STARTING = Object.freeze([["AGENTS.md", "file"], ["memory/MEMORY.md", "file"], ["state", "directory"]]);',
            "const STARTING = Object.freeze([]);", "judge"],
        ["judge-starting-not-set-up", '        } catch (error) {\n            if (error.message === "jarvis: home=absent") fail("not-set-up");\n            throw error;\n        }\n    }\n}',
            '        } catch (error) {\n            throw error;\n        }\n    }\n}', "judge"],
        ["no-lock-false", '    if (kind === "absent") return false;', '    if (kind === "absent") return true;', "packageInstalled"],
        ["base-declared", '    if (set === RENDER && !baseNames(home, set).includes(named.name)) fail("absent");\n', "", "skills"],
        ["base-listed", "if (folder === RENDER) listed =", "if (false) listed =", "skills"],
        ["required-index-only", "            if (folder === RENDER && entry.name !== PACKAGE) continue;\n", "", "skills"],
        ["own-optional", '            if (set === "own" && error.message === "jarvis: home=absent") continue;\n', "", "skills"],
        ["declaration-no-front", '    if (block === null) return found;\n', '    if (block === null) fail("declaration");\n', "declaration"],
        ["declaration-unclosed", '    if (block.body === null) fail("declaration");\n', "", "declaration"],
        ["own-voice", "    if (voice && !voiced(text)) return null;\n", "", "skills"],
    ]) {
        const result = mutant(source, name, needle, replacement, (logic, folder) => CASES[row](logic, folder), "Home.js");
        assert.equal(result, undefined);
        controls++;
        console.log("control=" + name + " detected");
    }
    // The listed-project route's own guards, each held by its case.
    for (const [name, source, needle, replacement] of [
        ["project-member", help, '            if (!listed.has(project)) return failed("project-unlisted");\n', ""],
        ["project-worktree-alias", help, "if (entry.state === \"ok\" && destination !== null) found.add(destination);",
            "if (entry.state === \"ok\" && destination !== null) found.add(destination).add(entry.folder);"],
        ["project-walk-whole", file, "    if (!listed) try {", "    try {"],
        ["project-list-whole", help, "if (!shaped(entry)) return null;", "if (!shaped(entry)) continue;"]
    ]) {
        await mutant(source, name, needle, replacement, logic => listedProjects(logic), "ComputerHelp.js");
        controls++;
        console.log("control=" + name + " detected");
    }
    // The gate's own rules, each held by the package's row.
    for (const [name, needle, replacement] of [
        ["render-gate", " || inJarvisHome(target.path, ancestor))", ")"],
        ["render-masks", "protectedRoots.concat(accounts, jarvisHomeMasks())", "protectedRoots.concat(accounts)"]
    ]) {
        assert.equal(mutant(denied, name, needle, replacement, logic => renderGate(logic), "Denied.js"), undefined);
        controls++;
        console.log("control=" + name + " detected");
    }
    console.log("test-jarvis-home: ok cases=" + Object.keys(CASES).length + " controls=" + controls);
});
