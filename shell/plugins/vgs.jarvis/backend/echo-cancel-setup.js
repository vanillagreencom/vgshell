#!/usr/bin/env node
// The setup TUI alone consumes plan/describe/install. It carries one displayed
// plan through confirmation; neither the plan nor a status read installs it.
"use strict";
const fs = require("node:fs");
const Core = require("./Core.js");
const EchoCancel = require("./EchoCancel.js");
const { Audio } = require("./Audio.js");

function input() {
    const bytes = Buffer.alloc(65537);
    let size = 0;
    while (size < bytes.length) {
        const read = fs.readSync(0, bytes, size, bytes.length - size, null);
        if (read === 0) break;
        size += read;
    }
    if (size > 65536) throw new Error("echo-cancel-input-size");
    return JSON.parse(bytes.subarray(0, size).toString("utf8"));
}

async function main(argv) {
    if (argv.length !== 2 || !["plan", "describe", "install"].includes(argv[0]))
        throw new Error("echo-cancel-arguments");
    Core.use(argv[1]);
    const value = input();
    if (argv[0] === "plan") {
        const installed = EchoCancel.read(process.env);
        if (!["absent", "installed"].includes(installed.state)) throw new Error("echo-cancel-" + installed.reason);
        const audio = new Audio({ session: {}, environment: process.env,
            clock: { now: () => performance.now(), set: (fn, ms) => setTimeout(fn, ms), clear: timer => clearTimeout(timer) },
            offers: () => {}, level: () => {}, fault: () => {}, captureSink: null, playbackSource: null });
        try {
            // The same Audio parser and physical-target judge used by the
            // daemon read one bounded snapshot. No monitor or recorder starts.
            audio.snapshot(await audio.dump(["--no-colors"]), "full");
            process.stdout.write(JSON.stringify(audio.setupTargets(value)) + "\n");
        } finally { await audio.close("setup-plan"); }
    } else if (argv[0] === "describe") {
        const chosen = EchoCancel.targets(value);
        process.stdout.write("Microphone: " + chosen.microphone + "\nSpeaker: " + chosen.speaker
            + "\nFile: " + EchoCancel.location(process.env) + "\n");
    } else {
        const result = EchoCancel.install(process.env, value);
        process.stdout.write((result.changed ? "Installed: " : "Already installed: ") + result.path + "\n");
    }
}

if (require.main === module) main(process.argv.slice(2)).catch(error => {
    const cause = /^echo-cancel-[a-z-]{1,60}$/.test(error.message) ? error.message.slice("echo-cancel-".length) : "operation-failed";
    process.stderr.write("jarvis-echo-cancel: failed=" + cause + "\n");
    process.exitCode = 1;
});

module.exports = { main };
