"use strict";
// The Jarvis package's session command in a home folder. A caller runs
// Core.use(tree) before it loads this file, as Home.js needs.
const fs = require("node:fs");
const Home = require("./Home.js");

// What stops a session command a home holds, by Home.sessionCommand's
// kind: a link or a part that is no folder or cannot be opened is the Home
// folder's to fix.
const BLOCKS = { link: "home-link", kind: "home-kind", unreadable: "home-unreadable" };

/**
 * The home folder SETTING names under USER with its session command, as
 * { folder, command }, or { kind: "blocked", block }: "no-home" for an
 * empty or refused setting; "not-set-up" for a folder the setting names
 * that is not there, which Setup makes (D126); for a folder without the
 * command, "package" in a home kendex installed the Jarvis package in,
 * whose Repair restores it, and "not-set-up" in one it did not, whose
 * Setup installs it (Home.packageInstalled); "home-link", "home-kind" or
 * "home-unreadable" for a way to it that Jarvis cannot follow.
 */
function place(setting, user) {
    let folder = null;
    try { folder = Home.resolve(setting, user); }
    catch (error) {
        // A setting the daemon refuses is the home row's to show.
        if (!/^jarvis: home=/.test(error.message)) throw error;
    }
    if (folder === null) return { kind: "blocked", block: "no-home" };
    const found = fs.statSync(folder, { throwIfNoEntry: false });
    if (found === undefined) return { kind: "blocked", block: "not-set-up" };
    if (!found.isDirectory()) return { kind: "blocked", block: "home-kind" };
    const command = Home.sessionCommand(folder);
    if (command.kind === "found") return { folder, command: command.path };
    if (command.kind !== "absent") return { kind: "blocked", block: BLOCKS[command.kind] };
    let installed;
    try { installed = Home.packageInstalled(folder); }
    catch (error) {
        if (!/^jarvis: home=/.test(error.message)) throw error;
        return { kind: "blocked", block: "home-unreadable" };
    }
    return { kind: "blocked", block: installed ? "package" : "not-set-up" };
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

// What a content-bearing call of the command reads: the user's home and
// session paths and the locale, never an inherited provider credential.
const CALL_ENVIRONMENT = ["PATH", "HOME", "LANG", "LC_ALL", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_RUNTIME_DIR", "XDG_SESSION_ID"];

/**
 * The session environment FROM gives (environment) narrowed to
 * CALL_ENVIRONMENT and the EXTRA names a call needs besides.
 */
function callEnvironment(from, extra = []) {
    const kept = environment(from);
    const picked = {};
    for (const name of [...CALL_ENVIRONMENT, ...extra]) if (kept[name] !== undefined) picked[name] = kept[name];
    return picked;
}

module.exports = { place, environment, callEnvironment };
