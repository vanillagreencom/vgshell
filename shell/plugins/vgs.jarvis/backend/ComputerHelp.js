// One on-demand owner for help: the computer-family files VGS installs, one
// regular Markdown file per family, and the skills of the user's Jarvis home
// folder and its memory notes, read through Home.js. Browser readiness adds
// its provider to this same owner.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const Tools = require("./Tools.js");
const Home = require("./Home.js");
const ROOT = path.join(__dirname, "skills/computer");
const LIMIT = 8192;
// A memory note's bound. The model chooses the path, so one read holds at
// most what the router gives any other result (ToolRouter RESULT_BYTES).
const NOTE_LIMIT = 16 * 1024;
/**
 * create(root, browser, home) builds the guidance executor. home() answers
 * the home folder's path, or null while none is usable.
 */
function create(root = ROOT, browser = null, home = () => null) {
    const shipped = Tools.HELP_TOPICS.filter(topic => {
        try { return fs.lstatSync(path.join(root, topic + ".md")).isFile(); }
        catch (error) { if (error.code === "ENOENT") return false; throw error; }
    });
    // A home whose skills cannot be listed offers none; Guidance.compose
    // reports that home to the setup view.
    function skills(folder) {
        if (folder === null) return [];
        try { return Home.skills(folder).skills.map(skill => skill.topic); }
        catch (error) {
            if (/^jarvis: home=/.test(error.message)) return [];
            throw error;
        }
    }
    return { commands: [], timeoutMs: browser === null ? 2000 : browser.timeoutMs, cancellable: false,
        // Read at each offer: the user adds a skill without a restart.
        topics: () => shipped.concat(skills(home())),
        // Verified readiness extends the offer once.
        enableBrowser() {
            if (browser === null) throw new Error("help-browser-unavailable");
            if (!shipped.includes("browser")) shipped.push("browser");
        },
        start(call, done) {
            let fd;
            try {
                if (call.id === "memory.read") {
                    const folder = home();
                    if (folder === null) throw new Error("home-unchosen");
                    const note = Home.note(folder, call.args.path, NOTE_LIMIT);
                    if (note.kind !== "text") throw new Error("note-too-large");
                    if (note.text.trim() === "") throw new Error("note-empty");
                    done({ outcome: "completed", content: note.text.trim() });
                    return;
                }
                const topic = call.args.topic;
                if (Tools.homeTopic(topic) !== null) {
                    const folder = home();
                    if (folder === null) throw new Error("help-topic-unavailable");
                    const text = Home.skill(folder, topic).trim();
                    if (text === "") throw new Error("help-file-empty");
                    done({ outcome: "completed", content: text });
                    return;
                }
                if (!shipped.includes(topic)) throw new Error("help-topic-unavailable");
                if (topic === "browser" && browser !== null) { browser.start(call, done); return; }
                fd = fs.openSync(path.join(root, topic + ".md"), fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
                if (!fs.fstatSync(fd).isFile()) throw new Error("help-file-invalid");
                const buffer = Buffer.alloc(LIMIT + 1);
                const size = fs.readSync(fd, buffer);
                if (size > LIMIT) throw new Error("help-file-too-large");
                const content = new TextDecoder("utf-8", { fatal: true }).decode(buffer.subarray(0, size)).trim();
                if (content === "") throw new Error("help-file-empty");
                done({ outcome: "completed", content });
            } catch (error) { done({ outcome: "failed", content: (call.id === "memory.read" ? "memory-read:" : "help-read:") + (error.code || error.message) }); }
            finally { if (fd !== undefined) fs.closeSync(fd); }
        } };
}
module.exports = { create };
