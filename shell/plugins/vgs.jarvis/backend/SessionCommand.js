"use strict";
// The Jarvis package's session command in a home folder, as the shell's two
// callers run it: session-control.js, which starts, stops and reads the
// session, and power-wait.js, which asks it to save before a restart. A
// caller runs Core.use(tree) before it loads this file, as Home.js needs.
const fs = require("node:fs");
const Home = require("./Home.js");

/**
 * The home folder SETTING names under USER with its session command, as
 * { folder, command }, or { kind: "blocked", block }: "no-home" for no
 * folder, "package" for a folder without the command.
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
    return command === null ? { kind: "blocked", block: "package" } : { folder, command };
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
