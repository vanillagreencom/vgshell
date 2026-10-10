#!/usr/bin/env node
// The Jarvis home folder owner, backend/Home.js, on real folders in J09's
// scratch HOME: the layout an empty folder gets with the base package VGS
// ships, what a folder that already holds files keeps, a home that holds an
// older package, the refusal of a link at the home, at every layout path and
// inside skills/base, the folder a setting names, the bounded read of its
// text, the skill index, a memory note read by its path and a request handed
// to the master session's mailbox. Each control edits
// a copy of Home.js, or of the Tools.js rule it asks, one rule at a time, and
// must turn a case red.
"use strict";
const cp = require("node:child_process");
const { assert, fs, path, tree, world, seed, mutant, fsFault } = require("./fixtures/jarvis/policy.js");
const file = path.join(tree, "shell/plugins/vgs.jarvis/backend/Home.js");

// The layout VGS-1194 names, independent of the production table: each file
// with what it must say, and each folder.
const FILES = ["AGENTS.md", "CLAUDE.md", "memory/MEMORY.md", ".claude/settings.json", ".codex/config.toml"];
const FOLDERS = ["skills", "skills/base", "skills/own", "memory", "memory/inbox", "state", ".claude", ".codex"];
// The shipped base package, read here from the checkout: every entry a home
// gets in skills/base, and the help topics they list.
const SHIPPED = path.join(tree, ".agents/skills/jarvis");
const PACKAGE = ["skills/base/jarvis", ...fs.readdirSync(SHIPPED, { recursive: true }).map(name => "skills/base/jarvis/" + name)];
const REFERENCES = fs.readdirSync(path.join(SHIPPED, "references")).map(name => "base/jarvis/" + name.slice(0, -3));

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
// skills/base holds the shipped package and nothing else, byte for byte.
function shipped(folder) {
    assert.equal(fs.lstatSync(path.join(folder, "skills/base"), { throwIfNoEntry: false })?.isDirectory(), true, "skills/base");
    assert.deepEqual(listing(path.join(folder, "skills/base")), PACKAGE.map(name => name.slice("skills/base/".length)).sort());
    for (const name of PACKAGE.filter(entry => fs.lstatSync(path.join(tree, ".agents/skills", entry.slice(12))).isFile()))
        assert.deepEqual(fs.readFileSync(path.join(folder, name)), fs.readFileSync(path.join(tree, ".agents/skills", name.slice(12))), name);
}
const keyed = (run, cause, label) => assert.throws(run, { message: "jarvis: home=" + cause }, label);
// The master session's mailbox below a home, as lane-mail lays it out, and a
// row of it stamped 2026-10-10T12:00:07.900Z, epoch second 1791633607.
const BOX = "tmp/lane-mail/overseer";
const MAIL = BOX + "/to-lane.jsonl";
const STAMP = Date.UTC(2026, 9, 10, 12, 0, 7, 900);
const mailRow = (id, text) => '{"id":"' + id + '","kind":"directive","at":"2026-10-10T12:00:07Z","from":"owner","text":' + text + "}\n";

world(() => {
    const { home } = seed();
    let serial = 0;
    const fresh = () => path.join(home, "homes", "h" + ++serial, "Jarvis");

    const CASES = {
        // An empty folder, and one that does not exist yet, get every entry
        // and the base package, and nothing else; the help topics list the
        // package's skill and each of its references.
        empty(Home) {
            for (const made of [false, true]) {
                const folder = fresh();
                if (made) fs.mkdirSync(folder, { recursive: true });
                assert.doesNotThrow(() => Home.layout(folder));
                assert.deepEqual(listing(folder), [...FILES, ...FOLDERS, ...PACKAGE].sort(), "the layout, the package and no scratch file");
                for (const name of FOLDERS) assert.equal(fs.lstatSync(path.join(folder, name)).isDirectory(), true, name);
                for (const name of FILES) assert.equal(fs.lstatSync(path.join(folder, name)).isFile(), true, name);
                assert.equal(fs.readFileSync(path.join(folder, "CLAUDE.md"), "utf8").trim(), "@AGENTS.md", "Claude Code imports the one instruction file");
                assert.deepEqual(JSON.parse(fs.readFileSync(path.join(folder, ".claude/settings.json"), "utf8")), { autoMemoryEnabled: false });
                assert.deepEqual(toml(fs.readFileSync(path.join(folder, ".codex/config.toml"), "utf8")),
                    { features: { memories: false }, memories: { generate_memories: false, use_memories: false } });
                shipped(folder);
                assert.equal(fs.readFileSync(path.join(folder, "skills/base/jarvis/persona.md")).length <= 3072, true, "the persona's bound");
                assert.deepEqual(Home.skills(folder).skills.map(skill => skill.topic), ["base/jarvis", ...REFERENCES]);
                assert.match(Home.skill(folder, REFERENCES[0]), /^# /, "a reference reads by its topic");
            }
        },
        // A folder that already holds files keeps every byte of them, a
        // layout file among them, and gains only what it lacks; a second
        // layout changes nothing.
        keeps(Home) {
            const folder = fresh();
            const kept = { "AGENTS.md": "# Mine\nMARKER\n", "README.md": "notes\n", ".git/HEAD": "ref: refs/heads/main\n",
                ".claude/settings.json": "{\"mine\": true}\n", "skills/own/mine.md": "# Mine\n" };
            for (const [name, text] of Object.entries(kept)) {
                fs.mkdirSync(path.dirname(path.join(folder, name)), { recursive: true });
                fs.writeFileSync(path.join(folder, name), text);
            }
            const stamps = names => names.map(name => fs.statSync(path.join(folder, name), { bigint: true })).map(stat => stat.ino + ":" + stat.mtimeNs);
            const before = stamps(Object.keys(kept));
            let package_;
            for (let round = 0; round < 2; round++) {
                assert.doesNotThrow(() => Home.layout(folder));
                for (const [name, text] of Object.entries(kept)) assert.equal(fs.readFileSync(path.join(folder, name), "utf8"), text, name + " keeps every byte");
                assert.deepEqual(stamps(Object.keys(kept)), before, "no kept file is written again");
                assert.deepEqual(listing(folder), [...new Set([...FILES, ...FOLDERS, ...PACKAGE, ...Object.keys(kept), ".git"])].sort());
                if (round === 0) package_ = stamps(PACKAGE);
                else assert.deepEqual(stamps(PACKAGE), package_, "a package the home already holds is not copied again");
            }
        },
        // A home that holds an older package, what a VGS update with a
        // changed package finds: skills/base becomes the shipped package byte
        // for byte, and the user's own skill and AGENTS.md keep every byte.
        update(Home) {
            const folder = fresh();
            const base = path.join(folder, "skills/base");
            const own = { "AGENTS.md": "# Mine\nMARKER\n", "skills/own/mine.md": "# Mine\n" };
            for (const [name, text] of Object.entries(own)) {
                fs.mkdirSync(path.dirname(path.join(folder, name)), { recursive: true });
                fs.writeFileSync(path.join(folder, name), text);
            }
            // The older package changed text under the same names.
            fs.cpSync(SHIPPED, path.join(base, "jarvis"), { recursive: true });
            fs.writeFileSync(path.join(base, "jarvis/SKILL.md"), "older\n");
            fs.appendFileSync(path.join(base, "jarvis/persona.md"), "older line\n");
            const stamps = () => Object.keys(own).map(name => fs.statSync(path.join(folder, name), { bigint: true }).mtimeNs);
            const before = stamps();
            assert.doesNotThrow(() => Home.layout(folder));
            shipped(folder);
            // Then it changed names too.
            fs.writeFileSync(path.join(base, "jarvis/SKILL.md"), "older\n");
            fs.rmSync(path.join(base, "jarvis/references", fs.readdirSync(path.join(base, "jarvis/references"))[0]));
            fs.writeFileSync(path.join(base, "jarvis/references/retired.md"), "# Retired\n");
            fs.mkdirSync(path.join(base, "jarvis/assets"));
            fs.writeFileSync(path.join(base, "stray.md"), "# Stray\n");
            assert.doesNotThrow(() => Home.layout(folder));
            shipped(folder);
            for (const [name, text] of Object.entries(own)) assert.equal(fs.readFileSync(path.join(folder, name), "utf8"), text, name + " keeps every byte");
            assert.deepEqual(stamps(), before, "the update writes no file of the user's");
            assert.deepEqual(listing(folder), [...FILES, ...FOLDERS, ...PACKAGE, "skills/own/mine.md"].sort(), "no scratch folder is left");
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
        // A link at skills/base, or anywhere inside it, is refused and never
        // followed: the link stays and what it points at keeps its bytes.
        packageLinks(Home) {
            for (const entry of ["jarvis", "jarvis/SKILL.md", "jarvis/persona.md", "jarvis/references", "jarvis/references/memory.md", "stray.md"]) {
                const folder = fresh();
                Home.layout(folder);
                const outside = path.join(path.dirname(folder), "outside");
                const directory = !entry.endsWith(".md");
                if (directory) {
                    fs.mkdirSync(outside);
                    fs.writeFileSync(path.join(outside, "SKILL.md"), "OUTSIDE\n");
                } else fs.writeFileSync(outside, "OUTSIDE\n");
                const at = path.join(folder, "skills/base", entry);
                fs.rmSync(at, { recursive: true, force: true });
                fs.symlinkSync(outside, at);
                keyed(() => Home.layout(folder), "link", entry);
                assert.equal(fs.lstatSync(at).isSymbolicLink(), true, entry + ": the link is left as it is");
                if (directory) assert.deepEqual([fs.readdirSync(outside), fs.readFileSync(path.join(outside, "SKILL.md"), "utf8")], [["SKILL.md"], "OUTSIDE\n"], entry);
                else assert.equal(fs.readFileSync(outside, "utf8"), "OUTSIDE\n", entry + ": the linked file keeps its bytes");
            }
        },
        // An entry of the other kind is refused by its own cause.
        kinds(Home) {
            for (const [entry, make] of [["AGENTS.md", at => fs.mkdirSync(at)], ["skills", at => fs.writeFileSync(at, "")],
                ["memory/inbox", at => fs.writeFileSync(at, "")], [".", at => fs.writeFileSync(at, "")]]) {
                const folder = fresh();
                const at = path.join(folder, entry);
                fs.mkdirSync(path.dirname(at), { recursive: true });
                make(at);
                keyed(() => Home.layout(folder), "kind", entry);
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
        // and any other file is no skill.
        skills(Home) {
            const folder = fresh();
            Home.layout(folder);
            fs.rmSync(path.join(folder, "skills/base/jarvis"), { recursive: true });
            const write = (name, text) => {
                fs.mkdirSync(path.dirname(path.join(folder, "skills", name)), { recursive: true });
                fs.writeFileSync(path.join(folder, "skills", name), text);
            };
            write("own/alpha.md", "\n# Alpha skill\nbody\n");
            write("own/beta/SKILL.md", "---\nname: beta\ndescription: \"Load for beta work.\"\n---\n# Beta\n");
            write("base/gamma.md", "---\nname: gamma\ndescription: >\n  folded\n---\n\nGamma first line\n");
            write("own/delta.md", "");
            write("own/epsilon.md", "---\ndescription: >-\n  folded and stripped\n---\nEpsilon first line\n");
            write("own/eta.md", "---\ndescription: |+2\n    kept\n---\nEta first line\n");
            write("own/notes.txt", "no skill\n");
            write("own/plain", "no skill\n");
            write("own/.hidden.md", "no skill\n");
            write("own/bad name.md", "no skill\n");
            write("own/empty-folder/readme.md", "no skill\n");
            write("own/bad dir/SKILL.md", "no skill\n");
            write("own/beta/references/one.md", "# One reference\nONE-BODY\n");
            // A reference is read on demand: no size bound holds it back.
            const long = "# Long reference\n" + "long line\n".repeat(4096);
            assert.ok(Buffer.byteLength(long) > 40 * 1024);
            write("own/beta/references/long.md", long);
            write("own/beta/references/bad name.md", "no skill\n");
            write("own/beta/references/notes.txt", "no skill\n");
            write("own/empty-folder/references/orphan.md", "no skill\n");
            write("own/zeta/SKILL.md", "# Zeta\n");
            write("own/zeta/references", "a file, not a folder\n");
            const outside = path.join(path.dirname(folder), "outside-skill.md");
            fs.writeFileSync(outside, "OUTSIDE-SECRET\n");
            fs.symlinkSync(outside, path.join(folder, "skills/own/linked.md"));
            fs.mkdirSync(path.join(folder, "skills/own/linked-folder"));
            fs.symlinkSync(outside, path.join(folder, "skills/own/linked-folder/SKILL.md"));
            let listed;
            assert.doesNotThrow(() => { listed = Home.skills(folder); });
            assert.deepEqual(listed, { complete: true, skills: [
                { topic: "base/gamma", file: "skills/base/gamma.md", line: "Gamma first line" },
                { topic: "own/alpha", file: "skills/own/alpha.md", line: "Alpha skill" },
                { topic: "own/beta", file: "skills/own/beta/SKILL.md", line: "Load for beta work." },
                { topic: "own/beta/long", file: "skills/own/beta/references/long.md", line: "Long reference" },
                { topic: "own/beta/one", file: "skills/own/beta/references/one.md", line: "One reference" },
                { topic: "own/delta", file: "skills/own/delta.md", line: "" },
                { topic: "own/epsilon", file: "skills/own/epsilon.md", line: "Epsilon first line" },
                { topic: "own/eta", file: "skills/own/eta.md", line: "Eta first line" },
                { topic: "own/zeta", file: "skills/own/zeta/SKILL.md", line: "Zeta" }] });
            assert.equal(Home.skill(folder, "own/alpha"), "\n# Alpha skill\nbody\n");
            assert.equal(Home.skill(folder, "own/beta").includes("# Beta"), true, "a folder's SKILL.md is its body");
            assert.equal(Home.skill(folder, "own/beta/one"), "# One reference\nONE-BODY\n");
            assert.equal(Home.skill(folder, "own/beta/long"), long, "a 40 KB reference reads whole");
            for (const [topic, cause] of [["own/missing", "absent"], ["own/../../secret", "absent"], ["other/alpha", "absent"],
                ["own/linked", "link"], ["own/linked-folder", "link"], ["own/beta/two", "absent"]])
                keyed(() => Home.skill(folder, topic), cause, topic);
            // A set past its entry bound answers incomplete, never a part as the whole.
            for (let index = 0; index < 257; index++) write("base/s" + index + ".md", "x\n");
            assert.equal(Home.skills(folder).complete, false);
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
        // A request handed to the master session is one lane-mail row at the
        // end of its mailbox file, which is made when absent: the id of
        // lane-mail's form, the owner as its sender, the stamp to the second
        // and the text whole on one line. A row already there keeps every
        // byte, a line a killed writer left open is closed first, and the
        // home gains no other entry.
        hands(Home) {
            const folder = fresh();
            Home.layout(folder);
            fs.mkdirSync(path.join(folder, BOX), { recursive: true });
            assert.equal(Home.mailbox(folder), true);
            const before = listing(folder);
            const first = Home.hand(folder, "Rebase the lanes.\nThen \"report\".", STAMP);
            assert.deepEqual(Object.keys(first), ["kind", "id"]);
            assert.equal(first.kind, "handed");
            assert.match(first.id, new RegExp("^1791633607-" + process.pid + "-[0-9]{1,5}$"), "lane-mail's id form");
            const one = mailRow(first.id, '"Rebase the lanes.\\nThen \\"report\\"."');
            assert.equal(fs.readFileSync(path.join(folder, MAIL), "utf8"), one);
            assert.deepEqual(listing(folder), [...before, MAIL].sort(), "the mailbox file and no other entry");
            fs.appendFileSync(path.join(folder, MAIL), '{"id":"cut');
            const second = Home.hand(folder, "Second request", STAMP);
            assert.equal(fs.readFileSync(path.join(folder, MAIL), "utf8"), one + '{"id":"cut\n' + mailRow(second.id, '"Second request"'));
            assert.deepEqual(listing(folder), [...before, MAIL].sort());
            // Half of a surrogate pair, which a model can send: the row holds
            // U+FFFD in its place and no \ud escape, which lane-mail's parser
            // refuses.
            const third = Home.hand(folder, "Half \ud83d pair", STAMP);
            assert.equal(third.kind, "handed");
            const stored = fs.readFileSync(path.join(folder, MAIL), "utf8").split("\n").at(-2);
            assert.equal(stored + "\n", mailRow(third.id, '"Half \ufffd pair"'));
            assert.equal(stored.includes("\\ud"), false, "no surrogate escape");
        },
        // The append holds lane-mail's lock, flock on the mailbox file: while
        // another holder keeps it, and where flock cannot run, no row lands.
        handsLocked(Home) {
            const folder = fresh();
            Home.layout(folder);
            fs.mkdirSync(path.join(folder, BOX), { recursive: true });
            const kept = mailRow("1791633000-1-1", '"kept"');
            fs.writeFileSync(path.join(folder, MAIL), kept);
            const holder = fs.openSync(path.join(folder, MAIL), "r");
            try {
                assert.equal(cp.spawnSync("flock", ["-n", "3"], { stdio: ["ignore", "ignore", "ignore", holder] }).status, 0, "the test holds the lock");
                keyed(() => Home.hand(folder, "Blocked request", STAMP), "busy");
            } finally { fs.closeSync(holder); }
            const search = process.env.PATH;
            process.env.PATH = "";
            try { keyed(() => Home.hand(folder, "No flock", STAMP), "lock"); }
            finally { process.env.PATH = search; }
            assert.equal(fs.readFileSync(path.join(folder, MAIL), "utf8"), kept, "no row lands without the lock");
            assert.equal(Home.hand(folder, "Free again", STAMP).kind, "handed");
        },
        // A row that does not read back from the file's end is reported as
        // unread, never as handed.
        handsUnread(Home) {
            const folder = fresh();
            Home.layout(folder);
            fs.mkdirSync(path.join(folder, BOX), { recursive: true });
            fsFault("readSync", (original, fd, buffer, ...rest) => {
                const count = original(fd, buffer, ...rest);
                buffer.fill(0);
                return count;
            }, () => {
                const handed = Home.hand(folder, "Request", STAMP);
                assert.deepEqual([handed.kind, typeof handed.id], ["unread", "string"]);
            });
        },
        // The mailbox is the master's: a home without the folder gets none
        // made and no row, and a link at any part of the path, or another
        // kind of entry there, is refused and never followed. What a link
        // points at holds the rest of the path, so a followed link would
        // write there; it keeps its entries.
        handsNowhere(Home) {
            const parts = BOX.split("/");
            for (let made = 0; made < parts.length; made++) {
                const folder = fresh();
                Home.layout(folder);
                if (made > 0) fs.mkdirSync(path.join(folder, ...parts.slice(0, made)), { recursive: true });
                const before = listing(folder);
                assert.equal(Home.mailbox(folder), false, "no mailbox below " + made + " parts");
                keyed(() => Home.hand(folder, "Request", STAMP), "absent", made + " parts");
                assert.deepEqual(listing(folder), before, "nothing is made");
            }
            for (const [entry, rest] of [["tmp", "lane-mail/overseer"], ["tmp/lane-mail", "overseer"], [BOX, ""], [MAIL, null], [MAIL, "dangling"]]) {
                const folder = fresh();
                Home.layout(folder);
                const outside = path.join(path.dirname(folder), "outside");
                if (rest === null) fs.writeFileSync(outside, "OUTSIDE\n");
                else if (rest !== "dangling") fs.mkdirSync(path.join(outside, rest), { recursive: true });
                const held = rest === null || rest === "dangling" ? null : listing(outside);
                fs.mkdirSync(path.dirname(path.join(folder, entry)), { recursive: true });
                fs.symlinkSync(outside, path.join(folder, entry));
                if (entry !== MAIL) assert.equal(Home.mailbox(folder), false, entry + ": a linked mailbox is none");
                keyed(() => Home.hand(folder, "Request", STAMP), "link", entry);
                if (rest === "dangling") assert.equal(fs.existsSync(outside), false, "nothing is made through the link");
                else if (rest === null) assert.equal(fs.readFileSync(outside, "utf8"), "OUTSIDE\n", "the linked file keeps its bytes");
                else assert.deepEqual(listing(outside), held, entry + ": nothing is made in the linked folder");
            }
            for (const [entry, make] of [[BOX, at => fs.writeFileSync(at, "")], [MAIL, at => fs.mkdirSync(at)]]) {
                const folder = fresh();
                Home.layout(folder);
                fs.mkdirSync(path.dirname(path.join(folder, entry)), { recursive: true });
                make(path.join(folder, entry));
                keyed(() => Home.hand(folder, "Request", STAMP), "kind", entry);
            }
        }
    };

    const Home = require(file);
    for (const [name, check] of Object.entries(CASES)) {
        check(Home);
        console.log("case=" + name + " passed");
    }
    let controls = 0;
    for (const [name, needle, replacement, row, source = file] of [
        ["layout-entry", '    ["state", null],\n', "", "empty"],
        ["extra-file", '    ["state", null],\n', '    ["state", null], ["extra.md", ""],\n', "empty"],
        ["base-copy", '        base(held.get("skills/base"));\n', "", "empty"],
        ["base-again", "found.every(([name, content], index) =>", "false && found.every(([name, content], index) =>", "keeps"],
        ["base-compare", "content.equals(shipped[index][1])", "true", "update"],
        ["base-stray", "        if (name !== PACKAGE) fs.rmSync(child(fd, name), { recursive: true, force: true });\n", "        ;\n", "update"],
        ["base-own", 'base(held.get("skills/base"));', 'base(held.get("skills/own"));', "update"],
        ["base-home", 'base(held.get("skills/base"));', 'base(held.get("."));', "update"],
        ["base-link", 'fail(kind === "link" ? "link" : "kind")', 'fail("kind")', "packageLinks"],
        ["claude-import", '["CLAUDE.md", "@AGENTS.md\\n"]', '["CLAUDE.md", ""]', "empty"],
        ["claude-memory", '"{\\"autoMemoryEnabled\\": false}\\n"', '"{}\\n"', "empty"],
        ["codex-memory", "generate_memories = false\\n", "", "empty"],
        ["scratch-left", "    } finally { fs.unlinkSync(scratch); }", "    } finally {}", "empty"],
        ["keeps-existing", "} else if (kind === \"absent\") createFile(parent, name, content);", "} else if (true) createFile(parent, name, content);", "keeps"],
        ["link-refused", '            if (kind === "link") fail("link");\n', "", "links"],
        ["home-link", 'case "link": return fail("link");', 'case "link": return fail("kind");', "links"],
        ["kind-refused", 'else if (kind !== "directory") fail("kind");', "", "kinds"],
        ["file-kind", '            else if (kind !== "file") fail("kind");', "", "kinds"],
        ["inside-home", '!file.startsWith(base === "/" ? "/" : base + "/")', "false", "resolves"],
        ["path-bound", " || Buffer.byteLength(file) > PATH_BYTES", "", "resolves"],
        ["control-characters", ' || /[\\x00-\\x1f\\x7f]/.test(named)', "", "resolves"],
        ["open-entry", 'const OPEN = "state";', 'const OPEN = "skills";', "resolves"],
        ["read-bound", 'if (limit !== null && content.length > limit) return { kind: "too-large" };', "", "reads"],
        ["read-utf8", '{ kind: "text", text: new TextDecoder("utf-8", { fatal: true })', '{ kind: "text", text: new TextDecoder("utf-8", { fatal: false })', "reads"],
        ["read-kind", 'if (!fs.fstatSync(fd).isFile()) fail("kind");', "", "reads"],
        ["read-link", [['if (kind === "absent" || kind === "link") fail(kind);', 'if (kind === "absent") fail(kind);'],
            ["(last ? flags : O_RDONLY | O_DIRECTORY) | O_NOFOLLOW", "(last ? flags : O_RDONLY | O_DIRECTORY)"]], null, "reads"],
        ["skill-name", " && Tools.homeTopic(topic) !== null)", ")", "skills"],
        ["folder-name", "if (Tools.homeTopic(topic) === null) continue;\n            // An entry", "// An entry", "skills"],
        ["reference-topics", '            flat(references, topic + "/", inside);\n', "", "empty"],
        ["reference-read", 'if (named.reference !== null) return whole(base + "/references/" + named.reference + ".md");', "", "skills"],
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
        ["hand-terminated", 'text: text.toWellFormed() }) + "\\n");', "text: text.toWellFormed() }));", "hands"],
        ["hand-sender", 'from: "owner", text: text', 'from: "jarvis", text: text', "hands"],
        ["hand-stamp", '.replace(".000Z", "Z")', "", "hands"],
        ["hand-well-formed", "text: text.toWellFormed() })", "text })", "hands"],
        ["hand-clock", "const seconds = Math.floor(now / 1000);", "const seconds = Math.floor(Date.now() / 1000);", "hands"],
        ["hand-closes-line", 'open ? Buffer.concat([Buffer.from("\\n"), row]) : row', "row", "hands"],
        ["hand-appends", "O_RDWR | O_APPEND | O_CREAT | O_NOFOLLOW", "O_RDWR | fs.constants.O_TRUNC | O_CREAT | O_NOFOLLOW", "hands"],
        ["hand-lock", "            lock(fd);\n", "", "handsLocked"],
        ["hand-busy", 'if (taken.status === 75) fail("busy");', "", "handsLocked"],
        ["hand-no-flock", 'if (taken.status !== 0) fail("lock");', "", "handsLocked"],
        ["hand-read-back", "seen.equals(row)", "true", "handsUnread"],
        ["hand-no-folder", "    return within(home, MAILBOX, O_RDONLY | O_DIRECTORY, folder => {",
            "    fs.mkdirSync(path.join(home, MAILBOX), { recursive: true });\n    return within(home, MAILBOX, O_RDONLY | O_DIRECTORY, folder => {", "handsNowhere"],
        ["mailbox-present", "return within(home, MAILBOX, O_RDONLY | O_DIRECTORY, () => true); }", "return true; }", "handsNowhere"],
        ["hand-folder-link", [['if (kind === "absent" || kind === "link") fail(kind);', 'if (kind === "absent") fail(kind);'],
            ["(last ? flags : O_RDONLY | O_DIRECTORY) | O_NOFOLLOW", "(last ? flags : O_RDONLY | O_DIRECTORY)"]], null, "handsNowhere"],
        ["hand-file-link", [['        if (kind === "link") fail(kind);\n', ""],
            ["O_RDWR | O_APPEND | O_CREAT | O_NOFOLLOW", "O_RDWR | O_APPEND | O_CREAT"]], null, "handsNowhere"],
        ["hand-kind", '        if (kind !== "file" && kind !== "absent") fail("kind");\n', "", "handsNowhere"]
    ]) {
        const result = mutant(source, name, needle, replacement, logic => CASES[row](logic), "Home.js");
        assert.equal(result, undefined);
        controls++;
        console.log("control=" + name + " detected");
    }
    console.log("test-jarvis-home: ok cases=" + Object.keys(CASES).length + " controls=" + controls);
});
