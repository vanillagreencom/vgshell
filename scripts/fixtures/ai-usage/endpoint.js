#!/usr/bin/env node
// endpoint.js PORT_FILE MODE_FILE LOG_FILE: a stand-in for the Claude usage
// endpoint on 127.0.0.1, for scripts/test-ai-usage.js and
// scripts/smoke/rows/ai-usage.sh. It writes the port it listens on to
// PORT_FILE and answers each GET of /api/oauth/usage by the word in
// MODE_FILE: ok, the recorded reply claude-usage.json; relative, that reply
// with each reset time moved to the request's moment plus RELATIVE's
// offset, so a reading of the words for it never goes stale on a calendar
// date; missing, the reply claude-usage-missing.json, which holds no
// five-hour window; malformed, a body that is no JSON; refused, 401; error,
// 500; hang, no answer at all, the connection held open. Each request appends one
// line to LOG_FILE: { method, path, beta, token }, token the SHA-256 of the
// bearer token, so a reader can match it without the log holding it. The
// replies are written by hand from the endpoint's documented shape: each
// window { utilization, resets_at }, a missing window null.
"use strict";
const fs = require("node:fs");
// How long after the request each window of the relative reply resets:
// 5 h 30 min and 3 d 6 h.
const RELATIVE = Object.freeze({ five_hour: 19800000, seven_day: 280800000 });
const http = require("node:http");
const path = require("node:path");
const crypto = require("node:crypto");

function start(portFile, modeFile, logFile) {
    const server = http.createServer((request, response) => {
        const bearer = /^Bearer (.+)$/.exec(request.headers.authorization || "");
        fs.appendFileSync(logFile, JSON.stringify({ method: request.method, path: request.url,
            beta: request.headers["anthropic-beta"] || null,
            token: bearer === null ? null : crypto.createHash("sha256").update(bearer[1]).digest("hex") }) + "\n");
        const mode = fs.readFileSync(modeFile, "utf8").trim();
        if (request.method !== "GET" || request.url !== "/api/oauth/usage") { response.writeHead(404); response.end(); return; }
        if (mode === "hang") return;
        if (mode === "relative") {
            const reply = JSON.parse(fs.readFileSync(path.join(__dirname, "claude-usage.json"), "utf8"));
            for (const [name, offset] of Object.entries(RELATIVE)) reply[name].resets_at = new Date(Date.now() + offset).toISOString();
            response.writeHead(200, { "content-type": "application/json" });
            response.end(JSON.stringify(reply));
            return;
        }
        const reply = { ok: [200, "claude-usage.json"], missing: [200, "claude-usage-missing.json"],
            malformed: [200, null], refused: [401, null], error: [500, null] }[mode];
        if (reply === undefined) { response.writeHead(400); response.end(); return; }
        response.writeHead(reply[0], { "content-type": "application/json" });
        response.end(reply[1] === null ? (mode === "malformed" ? "{\"five_hour\": " : "{}")
            : fs.readFileSync(path.join(__dirname, reply[1])));
    });
    server.listen(0, "127.0.0.1", () => {
        fs.writeFileSync(portFile + ".next", String(server.address().port));
        fs.renameSync(portFile + ".next", portFile);
    });
    return server;
}

module.exports = { start };
if (require.main === module) start(...process.argv.slice(2, 5));
