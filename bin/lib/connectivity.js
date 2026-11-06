// The NetworkManager Connectivity read shared by Automations and Updates.
// Updates runs this file once under its managed Process and reads the JSON.
"use strict";
const childProcess = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

function firstLine(text) {
    return String(text || "").split("\n").find(line => line.trim() !== "") || "";
}

// busctl get-property --json=short emits a typed unsigned scalar. UNKNOWN
// is a valid reading but grants no admission, as the consumers decide.
// https://networkmanager.dev/docs/api/latest/nm-dbus-types.html
function nmConnectivity(reply) {
    let doc;
    try { doc = JSON.parse(String(reply)); }
    catch (_e) { return null; }
    return doc !== null && typeof doc === "object" && !Array.isArray(doc)
        && doc.type === "u" && Number.isInteger(doc.data) && doc.data >= 0 && doc.data <= 4 ? doc.data : null;
}

// busctl is the one producer for both the property read and Automations'
// PropertiesChanged wait. Keep arbitrary diagnostics bounded in the result.
function networkCall(env, operation, args, boundMs) {
    const outcome = { operation, command: "busctl", category: "missing-command", exit: null, signal: null, timeoutMs: null, detail: "" };
    let bin = null;
    for (const dir of String(env.PATH || "").split(path.delimiter)) {
        if (!dir.startsWith("/")) continue;
        const candidate = path.join(dir, "busctl");
        try {
            fs.accessSync(candidate, fs.constants.X_OK);
            if (fs.statSync(candidate).isFile()) { bin = candidate; break; }
        } catch (_e) {
            // Not here; keep looking.
        }
    }
    if (bin === null) return { outcome, stdout: "" };
    const out = childProcess.spawnSync(bin, ["--system", "--json=short", operation].concat(args),
        { env, timeout: boundMs, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
    outcome.exit = out.status;
    outcome.signal = out.signal;
    outcome.detail = firstLine(out.stderr || (out.error ? out.error.code : "")).slice(0, 512);
    if (out.error && out.error.code === "ETIMEDOUT") {
        outcome.category = "timeout";
        outcome.timeoutMs = boundMs;
    } else if (out.error) outcome.category = "spawn";
    else if (out.signal !== null) outcome.category = "signal";
    else outcome.category = out.status === 0 ? "completed" : "exit";
    return { outcome, stdout: out.stdout };
}

function readConnectivity(env) {
    const result = networkCall(env, "get-property", ["org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager", "org.freedesktop.NetworkManager", "Connectivity"], 5000);
    if (result.outcome.category !== "completed") return { connectivity: null, outcome: result.outcome };
    const connectivity = nmConnectivity(result.stdout);
    result.outcome.category = connectivity === null ? "invalid-reply" : "connectivity";
    if (connectivity === null) result.outcome.detail = firstLine(result.stdout).slice(0, 512);
    else result.outcome.connectivity = connectivity;
    return { connectivity, outcome: result.outcome };
}

module.exports = { nmConnectivity, networkCall, readConnectivity };
if (require.main === module) process.stdout.write(JSON.stringify(readConnectivity(process.env)) + "\n");
