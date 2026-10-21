"use strict";
// The Jarvis package's session command in a home folder, as the shell's two
// callers run it: session-control.js, which starts, stops and reads the
// session, and power-wait.js, which asks it to save before a restart. A
// caller runs Core.use(tree) before it loads this file, as Home.js needs.
const fs = require("node:fs");
const Home = require("./Home.js");

// What stops a session command a home holds, by Home.sessionCommand's
// kind: a link or a part that is no folder or cannot be opened is the Home
// folder's to fix.
const BLOCKS = { link: "home-link", kind: "home-kind", unreadable: "home-unreadable" };

/**
 * The home folder SETTING names under USER with its session command, as
 * { folder, command }, or { kind: "blocked", block }: "no-home" for no
 * folder; for a folder without the command, "package" in a home Kendex
 * installed, whose Repair restores it, and "vgs-package" in one VGS laid
 * out, whose render ships none (Home.packageOwner); "home-link",
 * "home-kind" or "home-unreadable" for a way to it that Jarvis cannot
 * follow.
 */
function place(setting, user) {
    let folder = null;
    try { folder = Home.resolve(setting, user); }
    catch (error) {
        // A setting the daemon refuses is the home row's to show.
        if (!/^jarvis: home=/.test(error.message)) throw error;
    }
    if (folder === null || !fs.statSync(folder, { throwIfNoEntry: false })?.isDirectory()) return { kind: "blocked", block: "no-home" };
    const command = Home.sessionCommand(folder);
    if (command.kind === "found") return { folder, command: command.path };
    if (command.kind !== "absent") return { kind: "blocked", block: BLOCKS[command.kind] };
    let owner;
    try { owner = Home.packageOwner(folder); }
    catch (error) {
        if (!/^jarvis: home=/.test(error.message)) throw error;
        return { kind: "blocked", block: "home-unreadable" };
    }
    return { kind: "blocked", block: owner === "kendex" ? "package" : "vgs-package" };
}

/**
 * The environment the command takes: the session is the user's own
 * program, so it takes the user's session environment, XDG_SESSION_ID for
 * its boot receipt among it, less what marks the shell's own processes and
 * a tmux pane the shell was restarted from.
 */
function environment(from) {
    const { TMUX, TMUX_PANE, VGSHELL_RUNNER_PID, ...kept } = from;
    return kept;
}

module.exports = { place, environment };
