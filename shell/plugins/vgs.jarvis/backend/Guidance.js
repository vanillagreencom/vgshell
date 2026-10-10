// Session guidance for the J33 chained engine and J37 duplex delegation.
// compose(engine, brainClass, language, home) returns { instructions, layers,
// afterToolResult, withHome }. Engines are "chained" or "duplex"; classes are "duplex"
// (the voice model), "text" or "local" (a brain). The local chained consumer
// appends afterToolResult as instructions after EACH tool result. home is
// the user's Jarvis home folder or null: a brain gets its AGENTS.md after the
// shipped layers and the index of its skills, each read on demand through the
// help tool. The voice model only reads the brain's words aloud and gets no
// home text (D105).
// Read failures and bounds throw keyed errors. No cache or session store.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { languageCode } = require("./SpeechLanguage.js");
const Home = require("./Home.js");
const MAX_LAYER_BYTES = 8192;
const MAX_COMPOSE_BYTES = 32768;
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

// The home's layers as [name, text] pairs. An AGENTS.md or a skill index
// over the layer bound refuses whole: a cut persona would read as the
// user's own words.
function homeLayers(home) {
    const out = [];
    const agents = Home.read(home, "AGENTS.md", MAX_LAYER_BYTES);
    if (agents.kind !== "text") throw new Error("jarvis: guidance=home-too-large");
    if (agents.text.trim() !== "")
        out.push(["home/AGENTS.md", "The user's own instructions for you, from their Jarvis home folder:\n\n" + agents.text.trim()]);
    const listed = Home.skills(home);
    const index = listed.skills.map(skill => "- " + skill.topic + (skill.line === "" ? "" : ": " + skill.line)).join("\n");
    if (!listed.complete || Buffer.byteLength(index) > MAX_LAYER_BYTES) throw new Error("jarvis: guidance=home-skills-too-large");
    if (index !== "")
        out.push(["home/skills", "Skills in the user's Jarvis home folder. Read a skill with the help tool, by its topic, before you use it:\n\n" + index]);
    return out;
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
    for (const [name, text] of home === null ? [] : homeLayers(home)) {
        names.push(name);
        content.push(text);
    }
    const instructions = content.join("\n\n");
    if (Buffer.byteLength(instructions) > MAX_COMPOSE_BYTES) throw new Error("jarvis: guidance=compose-too-large");
    // The same core rule reaches the model again, not a second spelling of it.
    const afterToolResult = engine === "chained" && brainClass === "local" ? content[0] + "\n\n" + content[4] : null;
    return Object.freeze({ instructions, layers: Object.freeze(names), afterToolResult,
        /** This consumer's guidance with the text of the home FOLDER as it reads now. */
        withHome: folder => compose(engine, brainClass, language, folder) });
}

module.exports = { compose };
