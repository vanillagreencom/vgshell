#!/usr/bin/env node
// power-wait.js --tree ABSOLUTE_VGS_TREE reboot|poweroff HOME, the shell's
// Reboot or Shut down while a Jarvis session lives. HOME is the plugin's
// `home` setting of that session. It asks the Jarvis package's session
// command to save the session, `prepare --for restart` or `--for shutdown`,
// which blocks until the session's saved answer, then runs `systemctl
// reboot` or `systemctl poweroff` once, whatever the answer: when the
// command ends, at the bound, when the home holds no command, and when the
// command cannot start. The service starts this file detached
// (shell.run.detached), so a shell crash or reload during the wait cancels
// no restart. Arguments it cannot read exit 2 with a keyed line and run
// nothing. Each other run writes one keyed line to stderr, before it asks
// systemctl, with what came of the `prepare`:
//   jarvis: power-wait=VERB prepare=OUTCOME
// OUTCOME is `answered exit=0`; `refused exit=2`, the contract's refusal
// of a verb, as from a package without `prepare`; `failed exit=N` or
// `failed signal=S`; `bound`, killed at the bound; `no-home` or `package`,
// no command to ask; `spawn-failed`; or `error`. systemctl's own refusal
// goes to stderr as it writes it, and a systemctl that does not succeed
// adds one keyed line:
//   jarvis: power-wait=VERB systemctl=exit-N|signal-S|ERROR_CODE
"use strict";
const cp = require("node:child_process");
const path = require("node:path");

// The longest wait for the session's saved answer, so a hung session never
// holds a restart longer (VGS-1797). PowerWait.qml counts the same minute
// on its card.
const PREPARE_MS = 60000;
const FOR = { reboot: "restart", poweroff: "shutdown" };

function main() {
    const [flag, tree, verb, home, ...rest] = process.argv.slice(2);
    if (flag !== "--tree" || !path.isAbsolute(tree || "") || !Object.hasOwn(FOR, verb) || typeof home !== "string" || rest.length !== 0) {
        process.stderr.write("jarvis: power-wait=arguments\n");
        process.exitCode = 2;
        return;
    }
    let asked = false;
    // The one power request of this run.
    function power(cause) {
        if (asked) return;
        asked = true;
        process.stderr.write("jarvis: power-wait=" + verb + " prepare=" + cause + "\n");
        // Its stderr is this helper's own, so a refusal by logind or polkit
        // goes where the keyed lines go, as systemctl writes it.
        const request = cp.spawn("systemctl", [verb], { stdio: ["ignore", "ignore", "inherit"] });
        request.on("error", error => {
            process.stderr.write("jarvis: power-wait=" + verb + " systemctl=" + error.code + "\n");
            process.exitCode = 1;
        });
        request.on("exit", (code, signal) => {
            if (code === 0) return;
            process.stderr.write("jarvis: power-wait=" + verb + " systemctl=" + (signal === null ? "exit-" + code : "signal-" + signal) + "\n");
            process.exitCode = 1;
        });
    }
    try {
        require("./Core.js").use(tree);
        const SessionCommand = require("./SessionCommand.js");
        const at = SessionCommand.place(home, process.env.HOME);
        if (at.kind === "blocked") return power(at.block);
        // No pipe: the answer changes nothing, and a program the command
        // started could hold a pipe open past the command's own end. `exit`
        // fires when the command itself ends.
        const prepare = cp.spawn(at.command, ["prepare", "--for", FOR[verb], "--home", at.folder],
            { cwd: at.folder, env: SessionCommand.environment(process.env), stdio: "ignore" });
        const bound = setTimeout(() => {
            prepare.kill("SIGKILL");
            power("bound");
        }, PREPARE_MS);
        prepare.on("error", () => {
            clearTimeout(bound);
            power("spawn-failed");
        });
        prepare.on("exit", (code, signal) => {
            clearTimeout(bound);
            power(signal !== null ? "failed signal=" + signal : code === 0 ? "answered exit=0" : code === 2 ? "refused exit=2" : "failed exit=" + code);
        });
    } catch (error) {
        process.stderr.write("jarvis: power-wait cause=" + String(error.message).split("\n")[0] + "\n");
        power("error");
    }
}

main();
