#!/usr/bin/env node
// The Jarvis home folder owner, backend/Home.js, on real folders in J09's
// scratch HOME: the layout an empty folder gets, what a folder that already
// holds files keeps, the refusal of a link at the home and at every layout
// path, the folder a setting names, the bounded read of its text and the
// skill index. Each control edits a copy of Home.js, one rule at a time, and
// must turn a case red.
"use strict";
const { assert, fs, path, tree, world, seed, mutant } = require("./fixtures/jarvis/policy.js");
const file = path.join(tree, "shell/plugins/vgs.jarvis/backend/Home.js");

// The layout VGS-1194 names, independent of the production table: each file
// with what it must say, and each folder.
const FILES = ["AGENTS.md", "CLAUDE.md", "memory/MEMORY.md", ".claude/settings.json", ".codex/config.toml"];
const FOLDERS = ["skills", "skills/base", "skills/own", "memory", "memory/inbox", "state", ".claude", ".codex"];
const KNOWLEDGE = ["AGENTS.md", "CLAUDE.md", "skills", "memory", ".claude", ".codex"];

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
const keyed = (run, cause, label) => assert.throws(run, { message: "jarvis: home=" + cause }, label);

world(() => {
    const { home } = seed();
    let serial = 0;
    const fresh = () => path.join(home, "homes", "h" + ++serial, "Jarvis");

    const CASES = {
        // An empty folder, and one that does not exist yet, get every entry
        // and nothing else.
        empty(Home) {
            for (const made of [false, true]) {
                const folder = fresh();
                if (made) fs.mkdirSync(folder, { recursive: true });
                assert.doesNotThrow(() => Home.layout(folder));
                assert.deepEqual(listing(folder), [...FILES, ...FOLDERS].sort(), "the layout and no scratch file");
                for (const name of FOLDERS) assert.equal(fs.lstatSync(path.join(folder, name)).isDirectory(), true, name);
                for (const name of FILES) assert.equal(fs.lstatSync(path.join(folder, name)).isFile(), true, name);
                assert.equal(fs.readFileSync(path.join(folder, "CLAUDE.md"), "utf8").trim(), "@AGENTS.md", "Claude Code imports the one instruction file");
                assert.deepEqual(JSON.parse(fs.readFileSync(path.join(folder, ".claude/settings.json"), "utf8")), { autoMemoryEnabled: false });
                assert.deepEqual(toml(fs.readFileSync(path.join(folder, ".codex/config.toml"), "utf8")),
                    { features: { memories: false }, memories: { generate_memories: false, use_memories: false } });
                assert.deepEqual(fs.readdirSync(path.join(folder, "skills/base")), [], "the base package is not this owner's");
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
            const stamps = () => Object.keys(kept).map(name => fs.statSync(path.join(folder, name), { bigint: true }).mtimeNs);
            const before = stamps();
            for (let round = 0; round < 2; round++) {
                assert.doesNotThrow(() => Home.layout(folder));
                for (const [name, text] of Object.entries(kept)) assert.equal(fs.readFileSync(path.join(folder, name), "utf8"), text, name + " keeps every byte");
                assert.deepEqual(stamps(), before, "no kept file is written again");
                assert.deepEqual(listing(folder), [...new Set([...FILES, ...FOLDERS, ...Object.keys(kept), ".git"])].sort());
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
            assert.deepEqual(Home.protectedPaths("/h/Jarvis"), KNOWLEDGE.map(name => "/h/Jarvis/" + name));
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
            const write = (name, text) => {
                fs.mkdirSync(path.dirname(path.join(folder, "skills", name)), { recursive: true });
                fs.writeFileSync(path.join(folder, "skills", name), text);
            };
            write("own/alpha.md", "\n# Alpha skill\nbody\n");
            write("own/beta/SKILL.md", "---\nname: beta\ndescription: \"Load for beta work.\"\n---\n# Beta\n");
            write("base/gamma.md", "---\nname: gamma\ndescription: >\n  folded\n---\n\nGamma first line\n");
            write("own/delta.md", "");
            write("own/notes.txt", "no skill\n");
            write("own/plain", "no skill\n");
            write("own/.hidden.md", "no skill\n");
            write("own/bad name.md", "no skill\n");
            write("own/empty-folder/readme.md", "no skill\n");
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
                { topic: "own/delta", file: "skills/own/delta.md", line: "" }] });
            assert.deepEqual(Home.skill(folder, "own/alpha", 64), { kind: "text", text: "\n# Alpha skill\nbody\n" });
            assert.equal(Home.skill(folder, "own/beta", 128).text.includes("# Beta"), true, "a folder's SKILL.md is its body");
            assert.deepEqual(Home.skill(folder, "own/alpha", 8), { kind: "too-large" });
            for (const [topic, cause] of [["own/missing", "absent"], ["own/../../secret", "absent"], ["other/alpha", "absent"],
                ["own/linked", "link"], ["own/linked-folder", "link"]])
                keyed(() => Home.skill(folder, topic, 64), cause, topic);
            // A set past its entry bound answers incomplete, never a part as the whole.
            for (let index = 0; index < 257; index++) write("base/s" + index + ".md", "x\n");
            assert.equal(Home.skills(folder).complete, false);
        }
    };

    const Home = require(file);
    for (const [name, check] of Object.entries(CASES)) {
        check(Home);
        console.log("case=" + name + " passed");
    }
    let controls = 0;
    for (const [name, needle, replacement, row] of [
        ["layout-entry", '    ["state", null],\n', "", "empty"],
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
        ["knowledge-paths", 'const KNOWLEDGE = Object.freeze(["AGENTS.md", "CLAUDE.md", "skills", "memory", ".claude", ".codex"]);',
            'const KNOWLEDGE = Object.freeze(["AGENTS.md", "CLAUDE.md", "skills", "memory", ".claude", ".codex", "state"]);', "resolves"],
        ["read-bound", 'if (content.length > limit) return { kind: "too-large" };', "", "reads"],
        ["read-utf8", '{ kind: "text", text: new TextDecoder("utf-8", { fatal: true })', '{ kind: "text", text: new TextDecoder("utf-8", { fatal: false })', "reads"],
        ["read-kind", 'if (!fs.fstatSync(fd).isFile()) fail("kind");', "", "reads"],
        ["read-link", [['if (kind === "absent" || kind === "link") fail(kind);', 'if (kind === "absent") fail(kind);'],
            ["(last ? flags : O_RDONLY | O_DIRECTORY) | O_NOFOLLOW", "(last ? flags : O_RDONLY | O_DIRECTORY)"]], null, "reads"],
        ["skill-name", "if (Tools.homeTopic(topic) === null) continue;", "", "skills"],
        ["skill-kind", "if (!flat && !entry.isDirectory()) continue;", "", "skills"],
        ["skill-description", 'if (value !== "" && value !== ">" && value !== "|") return value.slice(0, LINE_CHARS);', "", "skills"],
        ["skill-folded", ' && value !== ">" && value !== "|"', "", "skills"],
        ["skill-heading", '.replace(/^#+\\s*/, "")', "", "skills"],
        ["set-bound", "if (entries.length === SET_ENTRIES) { complete = false; break; }", "", "skills"]
    ]) {
        const result = mutant(file, name, needle, replacement, logic => CASES[row](logic));
        assert.equal(result, undefined);
        controls++;
        console.log("control=" + name + " detected");
    }
    console.log("test-jarvis-home: ok cases=" + Object.keys(CASES).length + " controls=" + controls);
});
