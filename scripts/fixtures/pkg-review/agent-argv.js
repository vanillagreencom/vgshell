// The write limit each shipped review agent's launch carries
// (PackageReview.reviewCommand), judged for the claude and codex stand-ins:
// Claude's one rule names this review's verdict from the agent's working
// directory; Codex starts in this review's evidence folder, its one
// writable root, and no -C/--cd moves its root and no --add-dir adds
// another. ARGS end with the prompt, which names the review directory.
// Returns null when the launch carries the limit, else the refusal line.
"use strict";
const fs = require("node:fs"), path = require("node:path");
const sameFolder = (a, b) => { try { return fs.realpathSync(a) === fs.realpathSync(b); } catch (_) { return false; } };
function agentArgvRefusal(name, args, cwd) {
    const reviewDir = /The review directory is `([^`]+)`/.exec(args.at(-1) || "")?.[1], words = args.slice(0, -1);
    if (name === "claude") {
        const rules = words.filter(arg => arg.startsWith("--allowedTools")), rule = /^--allowedTools=Edit\(\.\/(.+)\)$/.exec(rules[0] || "");
        if (rules.length === 1 && rule && reviewDir && path.basename(rule[1]) === "verdict" && sameFolder(path.dirname(path.resolve(cwd, rule[1])), reviewDir)) return null;
        return "fixture: claude verdict rule rules=" + JSON.stringify(rules) + " cwd=" + cwd + " review=" + reviewDir;
    }
    const roots = words.filter(arg => /^(-C|--cd|--add-dir)/.test(arg));
    if (!roots.length && reviewDir && sameFolder(cwd, reviewDir)) return null;
    return "fixture: codex working root cwd=" + cwd + " roots=" + JSON.stringify(roots) + " review=" + reviewDir;
}
module.exports = { agentArgvRefusal };
