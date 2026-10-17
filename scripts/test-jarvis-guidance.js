#!/usr/bin/env node
// Source: the Jarvis plan attached to VGS-623, § 5. Voice-agent skill
// Synthetic fixtures authored 2026-09-30. No provider wire or recording.
"use strict";
const { assert, fs, path, backend, world, control } = require("./fixtures/jarvis-voice/assertions.js");
const Guidance = require(path.join(backend, "Guidance.js"));
const fixtures = require("./fixtures/jarvis-voice/guidance.json");
function composed(logic, row, root = backend) {
    const value = logic.compose(row.engine, row.class, row.language);
    assert.deepEqual(value.layers, row.layers);
    assert.equal(value.instructions, row.layers.map(name =>
        fs.readFileSync(path.join(root, "skills/voice", name), "utf8").trim()).join("\n\n"));
    assert.equal(value.afterToolResult, row.repeat ? ["core.md", "class/local.md"].map(name =>
        fs.readFileSync(path.join(root, "skills/voice", name), "utf8").trim()).join("\n\n") : null);
}
assert.equal(fixtures.length, 7, "class/language coverage floor");
assert.deepEqual([...new Set(fixtures.map(row => row.class))].sort(), ["duplex", "local", "text"]);
for (const row of fixtures) composed(Guidance, row);
assert.equal(Guidance.compose("chained", "text", "").instructions, Guidance.compose("chained", "text", "en").instructions);
const invalid = [
    ["other", "text", "en", "engine"], ["chained", "other", "en", "class"],
    ["chained", "duplex", "en", "consumer"], ["chained", "text", "../en", "speech=language"]
];
for (const [engine, brain, language, cause] of invalid)
    assert.throws(() => Guidance.compose(engine, brain, language),
        { message: cause.startsWith("speech") ? "jarvis: " + cause : "jarvis: guidance=" + cause });

// The Jarvis page's estimate: the ratio Guidance records, 4,018 bytes
// counted 1,023 o200k_base tokens, rounded to ten.
function tokenEstimate(logic) {
    assert.deepEqual([0, 4018, 40180, 200].map(logic.tokens), [0, 1020, 10230, 50]);
}
tokenEstimate(Guidance);
let controls = 0;
// The words a brain reads, the one consumer of these files: every brain is
// told to state one step before a tool call and to speak only its result, and
// no layer asks it to narrate.
function quietTools(logic) {
    for (const row of fixtures.filter(row => row.class !== "duplex")) {
        const text = logic.compose(row.engine, row.class, row.language).instructions;
        assert.deepEqual(["Before a tool call, write only one short `<step>` element", "except the `<step>` element", "speak only its result"].map(words => text.includes(words)), [true, true, true],
            row.engine + " " + row.class + ": states a step before a tool call, the result after it");
        assert.equal(/narrat/i.test(text), false, row.engine + " " + row.class + ": no narration");
    }
}
quietTools(Guidance);
world("jg", root => {
    for (const [name, layer, needle, replacement] of [
        ["tool-step", "core.md", "Before a tool call, write only one short `<step>` element", "Before a tool call, write prose"],
        ["tool-step-markup", "core.md", "except the `<step>` element", "with any markup"],
        ["tool-result", "core.md", "speak only its result", "say what you did"],
        ["tool-narration", "turns.md", "Ask before a long action.", "Ask before a long action. Narrate progress."]
    ]) {
        const copy = path.join(root, name);
        fs.cpSync(backend, copy, { recursive: true });
        const file = path.join(copy, "skills/voice", layer);
        const source = fs.readFileSync(file, "utf8");
        assert.equal(source.split(needle).length - 1, 1, name + " mutation match");
        fs.writeFileSync(file, source.replace(needle, replacement));
        assert.throws(() => quietTools(require(path.join(copy, "Guidance.js"))), assert.AssertionError, name + " must turn red");
        controls++;
    }
});
world("jg", root => {
    const rows = [
        ["voice-layers", '? ["class/duplex.md"]', '? ["core.md", "class/duplex.md"]', logic => composed(logic, fixtures[0])],
        ["delegation-layers", '["core.md", "speech.md", "actions.md"]',
            '["core.md", "speech.md", "turns.md"]', logic => composed(logic, fixtures[1])],
        ["frontier-language", 'names.push("lang/" + code + ".md");', 'names.push("lang/en.md");',
            logic => composed(logic, fixtures[4])],
        ["local-layer", 'if (brainClass === "local") names.push("class/local.md");',
            'if (false) names.push("class/local.md");', logic => composed(logic, fixtures[5])],
        ["tool-repeat", 'engine === "chained" && brainClass === "local" ? content[0] + "\\n\\n" + content[4] : null',
            'engine === "chained" && brainClass === "local" ? null : null', logic => composed(logic, fixtures[5])],
        ["engine", 'engine !== "chained" && engine !== "duplex"', 'false',
            logic => assert.throws(() => logic.compose("other", "text", "en"), { message: "jarvis: guidance=engine" })],
        ["class", '!["duplex", "text", "local"].includes(brainClass)', 'false',
            logic => assert.throws(() => logic.compose("chained", "other", "en"), { message: "jarvis: guidance=class" })],
        ["consumer", 'engine === "chained" && brainClass === "duplex"', 'false',
            logic => assert.throws(() => logic.compose("chained", "duplex", "en"), { message: "jarvis: guidance=consumer" })],
        ["token-ratio", "const MEASURED_TOKENS = 1023;", "const MEASURED_TOKENS = 1000;", tokenEstimate]
    ];
    for (const [name, needle, replacement, check] of rows) {
        control(root, name, "Guidance.js", needle, replacement, check); controls++;
    }
    for (const [name, content, cause] of [
        ["missing", null, "ENOENT"], ["empty", "", "layer-empty"],
        ["oversize", "x".repeat(8193), "layer-too-large"], ["utf8", Buffer.from([255]), "ERR_ENCODING_INVALID_ENCODED_DATA"]
    ]) {
        const copy = path.join(root, name);
        fs.cpSync(backend, copy, { recursive: true });
        const file = path.join(copy, "skills/voice/core.md");
        if (content === null) fs.unlinkSync(file); else fs.writeFileSync(file, content);
        assert.throws(() => require(path.join(copy, "Guidance.js")).compose("chained", "text", "en"),
            { message: "jarvis: guidance=layer file=core.md cause=" + cause });
    }
    control(root, "layer-bound", "Guidance.js", 'if (size > MAX_LAYER_BYTES)', 'if (false)', logic => {
        const copy = path.join(root, "layer-bound/skills/voice/core.md");
        fs.writeFileSync(copy, "x".repeat(8193));
        assert.throws(() => logic.compose("duplex", "text", "en"), /layer-too-large/);
    }); controls++;
    // A start text over its whole budget composes whole and names that
    // budget: every selected shipped layer at its own bound, no home.
    const startOver = (logic, copy) => {
        for (const file of fixtures[5].layers) fs.writeFileSync(path.join(copy, "skills/voice", file), "x".repeat(8192));
        let value;
        assert.doesNotThrow(() => { value = logic.compose("chained", "local", "en"); }, "a start text over its budget composes");
        assert.equal(value.instructions, fixtures[5].layers.map(() => "x".repeat(8192)).join("\n\n"), "and is whole");
        assert.deepEqual(value.overBudget, ["guidance=start-over-budget"]);
    };
    {
        const large = path.join(root, "large");
        fs.cpSync(backend, large, { recursive: true });
        startOver(require(path.join(large, "Guidance.js")), large);
    }
    for (const [name, needle, replacement] of [
        ["start-budget", "start > START_BUDGET", "false"],
        ["start-refuses", "    const overBudget = start > START_BUDGET",
            '    if (start > START_BUDGET) throw new Error("jarvis: guidance=compose-too-large");\n    const overBudget = start > START_BUDGET']
    ]) {
        control(root, name, "Guidance.js", needle, replacement, logic => startOver(logic, path.join(root, name))); controls++;
    }
    for (const [name, needle, replacement, content, cause] of [
        ["empty-bound", 'if (text === "")', 'if (false)', "", "layer-empty"],
        ["utf8-bound", '{ fatal: true }', '{ fatal: false }', Buffer.from([255]), "ERR_ENCODING_INVALID_ENCODED_DATA"]
    ]) {
        control(root, name, "Guidance.js", needle, replacement, logic => {
            fs.writeFileSync(path.join(root, name, "skills/voice/core.md"), content);
            assert.throws(() => logic.compose("chained", "text", "en"),
                { message: "jarvis: guidance=layer file=core.md cause=" + cause });
        }); controls++;
    }
    // The user's home folder: a brain gets the base package's persona and
    // then its AGENTS.md after the shipped layers, the index of its skills and
    // memory/MEMORY.md, the index of its memory notes; the voice model gets
    // none. A text over its budget composes whole, and overBudget names it; a
    // skill set over Home's entry bound refuses. The folder is made by
    // hand, as a user's is, with the package where kendex renders it.
    const tree = path.resolve(backend, "../../../..");
    const home = (name, agents, skills = {}, persona = "# Persona\nPERSONA-MARKER\n", memory = "") => {
        const folder = path.join(root, "home-" + name);
        for (const set of [".agents/skills/jarvis", "skills/own"]) fs.mkdirSync(path.join(folder, set), { recursive: true });
        fs.mkdirSync(path.join(folder, "memory"));
        fs.writeFileSync(path.join(folder, "memory/MEMORY.md"), memory);
        fs.writeFileSync(path.join(folder, "AGENTS.md"), agents);
        fs.writeFileSync(path.join(folder, ".agents/skills/jarvis/SKILL.md"), "# Jarvis package\n");
        fs.writeFileSync(path.join(folder, ".agents/skills/jarvis/persona.md"), persona);
        for (const [file, text] of Object.entries(skills)) fs.writeFileSync(path.join(folder, "skills", file), text);
        return folder;
    };
    // Its persona holds a character of two bytes, so a size in characters
    // differs from one in bytes.
    const full = home("full", "\nHOME-MARKER persona\n", { "own/alpha.md": "# Alpha skill\nALPHA-BODY\n" },
        "# Persona\nPERSONA-MARKER caf\u00e9\n", "\n- [Team](facts/team.md): MEMORY-MARKER\n");
    // A persona left where VGS copied the package before kendex's layout is
    // no persona of the home: the one the brain gets is the render's.
    fs.mkdirSync(path.join(full, "skills/base/jarvis"), { recursive: true });
    fs.writeFileSync(path.join(full, "skills/base/jarvis/persona.md"), "# Old persona\nOLD-PERSONA\n");
    const bare = home("bare", "  \n", {}, "\n", " \n");
    const memoryEdge = home("memory-edge", "", {}, "\n", "m".repeat(4096));
    const memoryOver = home("memory-over", "", {}, "\n", "m".repeat(4097));
    const personaEdge = home("persona-edge", "", {}, "p".repeat(3072));
    const personaOver = home("persona-over", "", {}, "p".repeat(3073));
    const edge = home("edge", "x".repeat(8192));
    const oversize = home("oversize", "x".repeat(8193));
    const crowded = home("crowded", "persona", Object.fromEntries(Array.from({ length: 60 }, (_, index) => ["own/s" + index + ".md", "y".repeat(200) + "\n"])));
    const startHome = home("start", "s".repeat(32768));
    const many = home("many", "persona", Object.fromEntries(Array.from({ length: 257 }, (_, index) => ["own/s" + index + ".md", "z\n"])));
    const linked = home("linked", "");
    fs.rmSync(path.join(linked, "AGENTS.md"));
    fs.symlinkSync(path.join(full, "AGENTS.md"), path.join(linked, "AGENTS.md"));
    // The state layer is last and holds no blank line: split it off the
    // text before it, and require the folder's own state/ path in it.
    const stateLast = (instructions, folder, what) => {
        const cut = instructions.lastIndexOf("\n\n");
        assert.equal(instructions.slice(cut + 2).includes(path.join(folder, "state") + "."), true, what + ": the last layer names <folder>/state");
        return instructions.slice(0, cut);
    };
    // The size the Jarvis page shows: each home layer's bytes in order,
    // and the whole start text's, which the shipped files, those layers and
    // the blank line between each two add up to.
    const sized = (value, row, copy, homeLayers, what) => {
        assert.deepEqual(value.size.home.map(entry => entry.layer), homeLayers, what + ": a size for each home layer, in order");
        assert.equal(value.size.start, Buffer.byteLength(value.instructions), what + ": the whole start text's bytes");
        const counted = [...row.layers.map(name => Buffer.byteLength(fs.readFileSync(path.join(copy, "skills/voice", name), "utf8").trim())),
            ...value.size.home.map(entry => entry.bytes)];
        assert.equal(counted.reduce((sum, bytes) => sum + bytes, 0) + 2 * (counted.length - 1), value.size.start,
            what + ": the layers and the blank lines between them are the whole start text");
    };
    function homeText(logic, copy = backend) {
        require(path.join(copy, "Core.js")).use(tree);
        for (const row of fixtures) {
            const plain = logic.compose(row.engine, row.class, row.language);
            sized(plain, row, copy, [], row.engine + " " + row.class + " with no home");
            if (row.class === "duplex") {
                assert.throws(() => logic.compose(row.engine, row.class, row.language, full), { message: "jarvis: guidance=consumer" },
                    "the voice that reads the brain's words aloud takes no home text");
                continue;
            }
            const value = logic.compose(row.engine, row.class, row.language, full);
            assert.equal(value.instructions.startsWith(plain.instructions + "\n\n"), true, "the shipped layers lead, unchanged");
            const added = value.instructions.slice(plain.instructions.length);
            assert.equal(added.includes("HOME-MARKER persona"), true, row.class + ": the home's AGENTS.md");
            assert.equal(added.indexOf("PERSONA-MARKER") > -1 && added.indexOf("PERSONA-MARKER") < added.indexOf("HOME-MARKER"), true,
                row.class + ": the package's persona, before the user's AGENTS.md");
            assert.equal(added.includes("OLD-PERSONA"), false, row.class + ": no persona of an older copy");
            assert.deepEqual(["- base/jarvis: Jarvis package", "- own/alpha: Alpha skill"].map(line => added.split("\n").includes(line)), [true, true],
                row.class + ": the skill index, name and first line");
            assert.equal(added.includes("ALPHA-BODY"), false, "a skill body is read on demand, never composed");
            assert.equal(stateLast(added, full, row.class).endsWith("\n\n- [Team](facts/team.md): MEMORY-MARKER"), true, row.class + ": the memory index, each line whole");
            assert.deepEqual(value.layers, [...row.layers, "home/persona", "home/AGENTS.md", "home/skills", "home/MEMORY.md", "home/state"]);
            sized(value, row, copy, ["home/persona", "home/AGENTS.md", "home/skills", "home/MEMORY.md", "home/state"], row.class + " full home");
            assert.equal(value.size.home[0].bytes, Buffer.byteLength("# Persona\nPERSONA-MARKER caf\u00e9"), "the persona's size in bytes");
            assert.deepEqual(value.overBudget, [], row.class + ": a home within its budgets names none");
            assert.equal(value.afterToolResult, plain.afterToolResult, "the home text is not repeated after a tool result");
            assert.equal(plain.withHome(full).instructions, value.instructions, "a composed guidance reads the home again");
            const empty = logic.compose(row.engine, row.class, row.language, bare);
            // Every home holds the package, whose SKILL.md is a skill of its own.
            const bareAdded = stateLast(empty.instructions, bare, row.class + " empty home");
            assert.equal(bareAdded.startsWith(plain.instructions + "\n\n"), true, "an empty home keeps the shipped layers");
            assert.equal(bareAdded.slice(plain.instructions.length).split("\n").includes("- base/jarvis: Jarvis package"), true, "the package's skill");
            assert.deepEqual(empty.layers, [...row.layers, "home/skills", "home/state"], "an empty home adds only the package's skill and its state folder");
            sized(empty, row, copy, ["home/skills", "home/state"], row.class + " empty home");
        }
        // Each text at and over its budget: the layer is whole where the
        // blank lines around it hold it alone, or it ends the text before
        // the state layer.
        const skillLines = text => Array.from({ length: 60 }, (_, index) => "- own/s" + index + ": " + "y".repeat(160)).every(line => text.split("\n").includes(line));
        for (const [name, folder, whole, over] of [
            ["AGENTS.md at its budget", edge, text => text.includes("\n\n" + "x".repeat(8192) + "\n\n"), []],
            ["AGENTS.md over its budget", oversize, text => text.includes("\n\n" + "x".repeat(8193) + "\n\n"), ["guidance=agents-over-budget"]],
            ["persona at its budget", personaEdge, text => text.includes("\n\n" + "p".repeat(3072) + "\n\n"), []],
            ["persona over its budget", personaOver, text => text.includes("\n\n" + "p".repeat(3073) + "\n\n"), ["guidance=persona-over-budget"]],
            ["MEMORY.md at its budget", memoryEdge, text => text.endsWith("\n\n" + "m".repeat(4096)), []],
            ["MEMORY.md over its budget", memoryOver, text => text.endsWith("\n\n" + "m".repeat(4097)), ["guidance=memory-over-budget"]],
            ["a skill list over its budget", crowded, skillLines, ["guidance=skills-over-budget"]],
            ["a start text over its budget", startHome, text => text.includes("\n\n" + "s".repeat(32768) + "\n\n"), ["guidance=agents-over-budget", "guidance=start-over-budget"]]
        ]) {
            let value;
            assert.doesNotThrow(() => { value = logic.compose("chained", "local", "en", folder); }, name + ": composes");
            assert.equal(whole(stateLast(value.instructions, folder, name)), true, name + ": whole");
            assert.deepEqual(value.overBudget, over, name + ": the budgets it is over");
        }
        // A skill set's entry bound guards the folder scan and still refuses.
        assert.throws(() => logic.compose("chained", "local", "en", many), { message: "jarvis: guidance=home-skills-too-large" });
        assert.throws(() => logic.compose("chained", "text", "en", linked), { message: "jarvis: home=link" });
    }
    homeText(Guidance);
    for (const [name, needle, replacement] of [
        ["home-refuses", 'const agents = whole("AGENTS.md", AGENTS_BUDGET, "guidance=agents-over-budget");',
            'const agents = whole("AGENTS.md", AGENTS_BUDGET, "guidance=agents-over-budget");\n    if (Buffer.byteLength(agents) > AGENTS_BUDGET) throw new Error("jarvis: guidance=home-too-large");'],
        ["home-whole", 'const text = Home.read(home, entry, null).text;', 'const text = Home.read(home, entry, budget).text ?? "";'],
        ["over-named", "if (Buffer.byteLength(text) > budget) over.push(cause);", ""],
        ["home-layer", "        content.push(text);\n", ""],
        ["home-order", "        content.push(text);\n", "        content.unshift(text);\n"],
        ["home-empty", 'if (agents !== "")', "if (true)"],
        ["persona-layer", 'if (persona !== "") out.push(["home/persona", persona]);', ""],
        ["persona-empty", 'if (persona !== "")', "if (true)"],
        ["persona-render", 'Home.baseSet(home) + "/" + Home.PACKAGE', '"skills/base/" + Home.PACKAGE'],
        ["voice-home", 'if (home !== null && brainClass === "duplex") throw new Error("jarvis: guidance=consumer");', ""],
        ["memory-cap-high", "const MEMORY_BUDGET = 4096;", "const MEMORY_BUDGET = 4097;"],
        ["memory-cap-low", "const MEMORY_BUDGET = 4096;", "const MEMORY_BUDGET = 4095;"],
        ["memory-cut", 'bootstrap:\\n\\n" + memory]);', 'bootstrap:\\n\\n" + memory.slice(0, 4096)]);'],
        ["memory-empty", 'if (memory !== "")', "if (true)"],
        ["memory-file", 'whole("memory/MEMORY.md", MEMORY_BUDGET', 'whole("AGENTS.md", MEMORY_BUDGET'],
        ["skills-budget", 'if (Buffer.byteLength(index) > SKILLS_BUDGET) over.push("guidance=skills-over-budget");', ""],
        ["skills-complete", 'if (!listed.complete) throw new Error("jarvis: guidance=home-skills-too-large");', ""],
        ["skill-line", '(skill.line === "" ? "" : ": " + skill.line)', '""'],
        ["read-again", "withHome: folder => compose(engine, brainClass, language, folder)", "withHome: () => compose(engine, brainClass, language)"],
        ["state-root", "path.join(home, Home.guard(home).open)", "home"],
        ["state-layer", 'out.push(["home/state", ', 'if (false) out.push(["home/state", '],
        ["size-layer", "        homeSize.push(", '        if (name !== "home/skills") homeSize.push('],
        ["size-bytes", "homeSize.push(Object.freeze({ layer: name, bytes: Buffer.byteLength(text) }));",
            "homeSize.push(Object.freeze({ layer: name, bytes: text.length }));"],
        ["size-start", "const start = Buffer.byteLength(instructions);", "const start = instructions.length;"]
    ]) {
        control(root, name, "Guidance.js", needle, replacement, logic => homeText(logic, path.join(root, name))); controls++;
    }
    // The Personality section the Settings page shows: its text up to the
    // next heading of level one or two, its own deeper headings kept, and
    // missing for no heading or an empty one.
    const sections = [
        ["between headings", "# Mine\n\nIntro.\n\n## Personality\n\nCalm.\n### Pace\nSlow.\n\n## Tools\nNone.\n", { kind: "section", text: "Calm.\n### Pace\nSlow." }],
        ["last", "## personality  \nBrief and warm.\n", { kind: "section", text: "Brief and warm." }],
        ["before a title", "## Personality\nDry.\n# Other\nx\n", { kind: "section", text: "Dry." }],
        ["absent", "# Mine\nNo section.\n", { kind: "missing" }],
        ["empty", "## Personality\n\n## Tools\nx\n", { kind: "missing" }],
        ["another heading", "## Personality notes\nx\n", { kind: "missing" }]
    ].map(([name, agents, expected]) => [name, home("personality-" + name.replace(/ /g, "-"), agents), expected]);
    const overSection = home("personality-over", "## Personality\nCalm.\n## Notes\n" + "n".repeat(9000) + "\n");
    const personality = (logic, copy = backend) => {
        require(path.join(copy, "Core.js")).use(tree);
        for (const [name, folder, expected] of sections) assert.deepEqual(logic.personality(folder), expected, name);
        let shown;
        assert.doesNotThrow(() => { shown = logic.personality(overSection); }, "an AGENTS.md over its budget shows its section");
        assert.deepEqual(shown, { kind: "section", text: "Calm." });
    };
    personality(Guidance);
    for (const [name, needle, replacement] of [
        ["personality-end", 'const end = rest.findIndex(line => /^#{1,2}\\s/.test(line));', "const end = -1;"],
        ["personality-heading", "/^##\\s+Personality\\s*$/i", "/^##\\s+Personality/i"],
        ["personality-empty", 'return text === "" ? { kind: "missing" } : { kind: "section", text };', 'return { kind: "section", text };'],
        ["personality-whole", 'Home.read(home, "AGENTS.md", null)', 'Home.read(home, "AGENTS.md", 8192)']
    ]) {
        control(root, name, "Guidance.js", needle, replacement, logic => personality(logic, path.join(root, name))); controls++;
    }
});
console.log("test-jarvis-guidance: ok fixtures=" + fixtures.length + " controls=" + controls);
