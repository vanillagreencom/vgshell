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

let controls = 0;
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
            logic => assert.throws(() => logic.compose("chained", "duplex", "en"), { message: "jarvis: guidance=consumer" })]
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
    // Actual boundary input: all selected files reach their per-layer cap.
    const large = path.join(root, "large");
    fs.cpSync(backend, large, { recursive: true });
    for (const file of fixtures[5].layers) fs.writeFileSync(path.join(large, "skills/voice", file), "x".repeat(8192));
    assert.throws(() => require(path.join(large, "Guidance.js")).compose("chained", "local", "en"),
        { message: "jarvis: guidance=compose-too-large" });
    control(root, "layer-bound", "Guidance.js", 'if (size > MAX_LAYER_BYTES)', 'if (false)', logic => {
        const copy = path.join(root, "layer-bound/skills/voice/core.md");
        fs.writeFileSync(copy, "x".repeat(8193));
        assert.throws(() => logic.compose("duplex", "text", "en"), /layer-too-large/);
    }); controls++;
    control(root, "compose-bound", "Guidance.js", 'Buffer.byteLength(instructions) > MAX_COMPOSE_BYTES', 'false', logic => {
        for (const file of fixtures[5].layers)
            fs.writeFileSync(path.join(root, "compose-bound/skills/voice", file), "x".repeat(8192));
        assert.throws(() => logic.compose("chained", "local", "en"), { message: "jarvis: guidance=compose-too-large" });
    }); controls++;
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
    // then its AGENTS.md after the shipped layers, and the index of its skills, the voice model gets none, and a
    // text over its bound refuses whole. The folder is made by hand, as a
    // user's is.
    const tree = path.resolve(backend, "../../../..");
    const home = (name, agents, skills = {}, persona = "# Persona\nPERSONA-MARKER\n") => {
        const folder = path.join(root, "home-" + name);
        for (const set of ["base/jarvis", "own"]) fs.mkdirSync(path.join(folder, "skills", set), { recursive: true });
        fs.writeFileSync(path.join(folder, "AGENTS.md"), agents);
        fs.writeFileSync(path.join(folder, "skills/base/jarvis/persona.md"), persona);
        for (const [file, text] of Object.entries(skills)) fs.writeFileSync(path.join(folder, "skills", file), text);
        return folder;
    };
    const full = home("full", "\nHOME-MARKER persona\n", { "own/alpha.md": "# Alpha skill\nALPHA-BODY\n", "base/gamma.md": "Gamma line\n" });
    const bare = home("bare", "  \n", {}, "\n");
    const personaEdge = home("persona-edge", "", {}, "p".repeat(3072));
    const personaOver = home("persona-over", "", {}, "p".repeat(3073));
    const edge = home("edge", "x".repeat(8192));
    const oversize = home("oversize", "x".repeat(8193));
    const crowded = home("crowded", "persona", Object.fromEntries(Array.from({ length: 60 }, (_, index) => ["own/s" + index + ".md", "y".repeat(200) + "\n"])));
    const many = home("many", "persona", Object.fromEntries(Array.from({ length: 257 }, (_, index) => ["own/s" + index + ".md", "z\n"])));
    const linked = home("linked", "");
    fs.rmSync(path.join(linked, "AGENTS.md"));
    fs.symlinkSync(path.join(full, "AGENTS.md"), path.join(linked, "AGENTS.md"));
    function homeText(logic, copy = backend) {
        require(path.join(copy, "Core.js")).use(tree);
        for (const row of fixtures) {
            const plain = logic.compose(row.engine, row.class, row.language);
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
            assert.deepEqual(["- base/gamma: Gamma line", "- own/alpha: Alpha skill"].map(line => added.split("\n").includes(line)), [true, true],
                row.class + ": the skill index, name and first line");
            assert.equal(added.includes("ALPHA-BODY"), false, "a skill body is read on demand, never composed");
            assert.deepEqual(value.layers, [...row.layers, "home/persona", "home/AGENTS.md", "home/skills"]);
            assert.equal(value.afterToolResult, plain.afterToolResult, "the home text is not repeated after a tool result");
            assert.equal(plain.withHome(full).instructions, value.instructions, "a composed guidance reads the home again");
            assert.equal(logic.compose(row.engine, row.class, row.language, bare).instructions, plain.instructions, "an empty home adds nothing");
            assert.deepEqual(logic.compose(row.engine, row.class, row.language, bare).layers, row.layers);
        }
        assert.equal(logic.compose("chained", "text", "en", edge).instructions.endsWith("x".repeat(8192)), true, "a persona of exactly the bound is whole");
        assert.throws(() => logic.compose("chained", "text", "en", oversize), { message: "jarvis: guidance=home-too-large" });
        assert.equal(logic.compose("chained", "text", "en", personaEdge).instructions.endsWith("p".repeat(3072)), true, "a persona of exactly its bound is whole");
        assert.throws(() => logic.compose("chained", "text", "en", personaOver), { message: "jarvis: guidance=home-persona-too-large" });
        for (const folder of [crowded, many])
            assert.throws(() => logic.compose("chained", "local", "en", folder), { message: "jarvis: guidance=home-skills-too-large" });
        assert.throws(() => logic.compose("chained", "text", "en", linked), { message: "jarvis: home=link" });
    }
    homeText(Guidance);
    for (const [name, needle, replacement] of [
        ["home-bound", 'if (agents.kind !== "text") throw new Error("jarvis: guidance=home-too-large");', ""],
        ["home-layer", "        content.push(text);\n", ""],
        ["home-order", "        content.push(text);\n", "        content.unshift(text);\n"],
        ["home-empty", 'if (agents.text.trim() !== "")', "if (true)"],
        ["persona-bound", 'if (persona.kind !== "text") throw new Error("jarvis: guidance=home-persona-too-large");', ""],
        ["persona-layer", 'if (persona.text.trim() !== "") out.push(["home/persona", persona.text.trim()]);', ""],
        ["persona-empty", 'if (persona.text.trim() !== "")', "if (true)"],
        ["voice-home", 'if (home !== null && brainClass === "duplex") throw new Error("jarvis: guidance=consumer");', ""],
        ["skills-bound", "if (!listed.complete || Buffer.byteLength(index) > MAX_LAYER_BYTES)", "if (!listed.complete)"],
        ["skills-complete", "if (!listed.complete || Buffer.byteLength(index) > MAX_LAYER_BYTES)", "if (Buffer.byteLength(index) > MAX_LAYER_BYTES)"],
        ["skill-line", '(skill.line === "" ? "" : ": " + skill.line)', '""'],
        ["read-again", "withHome: folder => compose(engine, brainClass, language, folder)", "withHome: () => compose(engine, brainClass, language)"]
    ]) {
        control(root, name, "Guidance.js", needle, replacement, logic => homeText(logic, path.join(root, name))); controls++;
    }
});
console.log("test-jarvis-guidance: ok fixtures=" + fixtures.length + " controls=" + controls);
