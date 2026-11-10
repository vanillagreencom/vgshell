// A Jarvis home as Setup leaves one (D126), for suites that need a ready
// home: the Jarvis package as kendex installs it, copied from the tree's
// own kendex install at .agents/skills/jarvis, kendex's lock naming it, and
// the starting files the package's init writes
// (.agents/skills/jarvis/references/home-layout.md § Initialize, kendex
// 6c00d3e19). Nothing here installs or initializes.
"use strict";
const fs = require("node:fs");
const path = require("node:path");

// The line init writes in a new home's AGENTS.md (skills/jarvis/scripts/lib/home.py ROUTE).
const ROUTE = "Read `.agents/skills/jarvis/persona.md` and follow it. Read it once per session; when its text is already loaded, use that text.\n";

// The package's session command, which a suite plants as a stand-in when
// it needs one: no suite runs the real package's session.
const SESSION = ".agents/skills/jarvis/scripts/jarvis-session";

/** Make FOLDER a ready Jarvis home from TREE's package; LOCK false leaves kendex's lock out. */
function jarvisHome(folder, tree, { lock = true } = {}) {
    fs.mkdirSync(path.join(folder, ".agents/skills"), { recursive: true });
    fs.cpSync(path.join(tree, ".agents/skills/jarvis"), path.join(folder, ".agents/skills/jarvis"), { recursive: true });
    fs.rmSync(path.join(folder, SESSION), { force: true });
    if (lock) fs.writeFileSync(path.join(folder, ".kendex-lock.json"), JSON.stringify({ version: 11, entries: { "skill:jarvis:codex":
        { kind: "skill", name: "jarvis", harness: "codex", emitted: { kind: "skill", name: "jarvis", paths: [".agents/skills/jarvis"] } } } }) + "\n");
    for (const [file, text] of [["AGENTS.md", ROUTE], ["memory/MEMORY.md", "# Memory index\n"]]) {
        fs.mkdirSync(path.dirname(path.join(folder, file)), { recursive: true });
        if (!fs.existsSync(path.join(folder, file))) fs.writeFileSync(path.join(folder, file), text);
    }
    fs.mkdirSync(path.join(folder, "state"), { recursive: true });
    return folder;
}

module.exports = { jarvisHome, ROUTE };
