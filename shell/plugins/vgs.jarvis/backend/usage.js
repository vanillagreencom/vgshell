// node usage.js [--state ABSOLUTE_JARVIS_STATE] [--since ISO] [--until ISO]
// Jarvis's delegate reads the existing audit only. JSON includes each row and
// totals by call kind and tool; costUsd is the priced subtotal, not an estimate
// for unpriced calls. The default window is the last seven days.
"use strict";
const path = require("node:path");
const Audit = require("./Audit.js");

function main(args, env, now = Date.now()) {
    const options = { now };
    const flags = new Set();
    for (let i = 0; i < args.length; i += 2) {
        const flag = args[i], value = args[i + 1];
        if (!["--state", "--since", "--until"].includes(flag) || value === undefined || flags.has(flag))
            throw new Error("jarvis: usage=arguments");
        flags.add(flag);
        if (flag === "--state") {
            if (!path.isAbsolute(value)) throw new Error("jarvis: usage=state");
            options.state = value;
        } else {
            if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(value) || !Number.isFinite(Date.parse(value)))
                throw new Error("jarvis: usage=time");
            options[flag.slice(2)] = Date.parse(value);
        }
    }
    if (options.state === undefined) {
        if (!env.XDG_STATE_HOME && !env.HOME) throw new Error("jarvis: usage=state");
        options.state = path.join(env.XDG_STATE_HOME || path.join(env.HOME, ".local/state"), "vgshell/jarvis");
    }
    options.until ??= now;
    options.since ??= options.until - 7 * 24 * 60 * 60 * 1000;
    return Audit.readUsage(options);
}

if (require.main === module) {
    try { process.stdout.write(JSON.stringify(main(process.argv.slice(2), process.env), null, 2) + "\n"); }
    catch (error) {
        process.stderr.write((/^jarvis: (?:usage|audit)=[a-z-]+$/.test(error.message) ? error.message : "jarvis: usage=read") + "\n");
        process.exitCode = 1;
    }
}
module.exports = { main };
