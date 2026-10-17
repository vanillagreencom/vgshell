// Session guidance for the J33 chained engine and J37 duplex delegation.
// compose(engine, brainClass, language, home) returns { instructions, layers,
// afterToolResult, overBudget, withHome }. Engines are "chained" or "duplex";
// classes are "duplex" (the voice model), "text" or "local" (a brain). The
// local chained consumer appends afterToolResult as instructions after EACH
// tool result. overBudget holds the causes of the texts over their budget,
// which the Setup page names. home is
// the user's Jarvis home folder or null: a brain gets the base package's
// persona and the home's AGENTS.md after the shipped layers, then the index of
// its skills, each read on demand through the help tool, then memory/MEMORY.md,
// the memory bootstrap that points to the memory tools when they are offered,
// then the path of the home's state/ folder, the one its file tools reach.
// The voice model only reads the brain's words aloud and gets no
// home text (D105).
// Read failures and the shipped layers' bound throw keyed errors; a home text
// over its budget does not. No cache or session store.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { languageCode } = require("./SpeechLanguage.js");
const Home = require("./Home.js");
// The bound of one shipped layer, a file of this package.
const MAX_LAYER_BYTES = 8192;
// The size budgets, in bytes, of the texts a conversation starts with. A
// text over its budget still loads whole: compose names it in overBudget.
// The persona's budget is the one its kendex package sets.
const PERSONA_BUDGET = 3072;
const AGENTS_BUDGET = 8192;
const SKILLS_BUDGET = 8192;
// MEMORY.md's, about 1,000 tokens: a synthetic index of 62 lines and 4,018
// bytes counted 1,023 tokens under tiktoken 0.14.0's o200k_base encoding
// (VGS-1256, 2026-10-10).
const MEMORY_BUDGET = 4096;
// The whole start text's: the shipped layers and the home's together.
const START_BUDGET = 32768;
const ROOT = path.join(__dirname, "skills/voice");

function layer(name) {
    const file = path.join(ROOT, name);
    let fd;
    try {
        fd = fs.openSync(file, "r");
        const buffer = Buffer.alloc(MAX_LAYER_BYTES + 1);
        let size = 0;
        while (size < buffer.length) {
            const read = fs.readSync(fd, buffer, size, buffer.length - size, null);
            if (read === 0) break;
            size += read;
        }
        if (size > MAX_LAYER_BYTES) throw new Error("layer-too-large");
        const text = new TextDecoder("utf-8", { fatal: true }).decode(buffer.subarray(0, size)).trim();
        if (text === "") throw new Error("layer-empty");
        return text;
    } catch (error) {
        throw new Error("jarvis: guidance=layer file=" + name + " cause=" + (error.code || error.message));
    } finally {
        if (fd !== undefined) fs.closeSync(fd);
    }
}

// The home's layers as {layers, over}: layers the [name, text] pairs of the
// persona, then the user's AGENTS.md, which may refine it, the skill index,
// the memory layer and the state folder's path; over the causes of the texts
// over their budget, in that order. Each text loads whole whatever its size,
// and a budget only informs, so Setup names the text over it (owner decision
// C, VGS-1771): a cut persona would read as the user's own words, a cut memory
// index would hide the notes below the cut, and a refusal would stop Jarvis
// over a file the user can shorten later. A skill set over Home's entry bound
// still refuses: that bound stops a runaway folder scan, and is no budget.
function homeLayers(home) {
    const out = [];
    const over = [];
    const whole = (entry, budget, cause) => {
        const text = Home.read(home, entry, null).text;
        if (Buffer.byteLength(text) > budget) over.push(cause);
        return text.trim();
    };
    const persona = whole(Home.baseSet(home) + "/" + Home.PACKAGE + "/persona.md", PERSONA_BUDGET, "guidance=persona-over-budget");
    if (persona !== "") out.push(["home/persona", persona]);
    const agents = whole("AGENTS.md", AGENTS_BUDGET, "guidance=agents-over-budget");
    if (agents !== "")
        out.push(["home/AGENTS.md", "The user's own instructions for you, from their Jarvis home folder:\n\n" + agents]);
    const listed = Home.skills(home);
    if (!listed.complete) throw new Error("jarvis: guidance=home-skills-too-large");
    const index = listed.skills.map(skill => "- " + skill.topic + (skill.line === "" ? "" : ": " + skill.line)).join("\n");
    if (Buffer.byteLength(index) > SKILLS_BUDGET) over.push("guidance=skills-over-budget");
    if (index !== "")
        out.push(["home/skills", "Skills in the user's Jarvis home folder. Read a skill with the help tool, by its topic, before you use it:\n\n" + index]);
    const memory = whole("memory/MEMORY.md", MEMORY_BUDGET, "guidance=memory-over-budget");
    if (memory !== "")
        out.push(["home/MEMORY.md", "The user's memory notes. When offered, use memory search before answering from memory, then memory read by id. Say which note the answer came from. The memory/MEMORY.md bootstrap:\n\n" + memory]);
    // The folder the gate leaves open, by the name the gate reads, since the
    // file tools take only absolute paths.
    out.push(["home/state", "Your state folder is " + path.join(home, Home.guard(home).open) + ". It is the one place in your home folder that your file tools can list, read and write. They refuse every other path in the home folder, and a search of the home folder itself."]);
    return { layers: out, over };
}

/**
 * The `## Personality` section of the home's AGENTS.md, which the Settings
 * page shows: {kind: "section", text} with its text up to the next heading
 * of level one or two, {kind: "missing"} for no such heading or no text
 * under it, of an AGENTS.md of any size. Every brain reads the section with
 * the rest of AGENTS.md through compose; this read only shows it.
 */
function personality(home) {
    const lines = Home.read(home, "AGENTS.md", null).text.split("\n");
    const start = lines.findIndex(line => /^##\s+Personality\s*$/i.test(line.trim()));
    if (start === -1) return { kind: "missing" };
    const rest = lines.slice(start + 1);
    const end = rest.findIndex(line => /^#{1,2}\s/.test(line));
    const text = (end === -1 ? rest : rest.slice(0, end)).join("\n").trim();
    return text === "" ? { kind: "missing" } : { kind: "section", text };
}

/** Compose only the layers assigned to this consumer by the voice contract. */
function compose(engine, brainClass, language, home = null) {
    if (engine !== "chained" && engine !== "duplex") throw new Error("jarvis: guidance=engine");
    if (!["duplex", "text", "local"].includes(brainClass)) throw new Error("jarvis: guidance=class");
    if (engine === "chained" && brainClass === "duplex") throw new Error("jarvis: guidance=consumer");
    if (home !== null && brainClass === "duplex") throw new Error("jarvis: guidance=consumer");
    const code = languageCode(language);
    let names;
    if (engine === "duplex") {
        // The duplex voice reads the brain's words aloud and decides nothing.
        names = brainClass === "duplex" ? ["class/duplex.md"] : ["core.md", "speech.md", "actions.md"];
    } else {
        names = ["core.md", "speech.md", "turns.md", "actions.md"];
        if (brainClass === "local") names.push("class/local.md");
        names.push("lang/" + code + ".md");
    }
    const content = names.map(layer);
    const read = home === null ? { layers: [], over: [] } : homeLayers(home);
    for (const [name, text] of read.layers) {
        names.push(name);
        content.push(text);
    }
    const instructions = content.join("\n\n");
    // A start text over the model's context window is the model's refusal
    // of the turn, which fails that turn alone.
    const overBudget = Buffer.byteLength(instructions) > START_BUDGET ? [...read.over, "guidance=start-over-budget"] : read.over;
    // The same core rule reaches the model again, not a second spelling of it.
    const afterToolResult = engine === "chained" && brainClass === "local" ? content[0] + "\n\n" + content[4] : null;
    return Object.freeze({ instructions, layers: Object.freeze(names), afterToolResult, overBudget: Object.freeze(overBudget),
        /** This consumer's guidance with the text of the home FOLDER as it reads now. */
        withHome: folder => compose(engine, brainClass, language, folder) });
}

module.exports = { compose, personality };
