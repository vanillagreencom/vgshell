#!/usr/bin/env node
// endpoint.js PORT_FILE MODE_FILE LOG_FILE: a stand-in for the Claude and
// Copilot usage endpoints on 127.0.0.1, for scripts/test-ai-usage.js and
// scripts/smoke/rows/ai-usage.sh. It writes the port it listens on to
// PORT_FILE. GET /api/oauth/usage answers by MODE_FILE for Claude: ok,
// relative, missing, null, malformed, refused, error, hang, throttled or
// limited. throttled answers 429 to every request. limited answers each
// bearer token's first request after MODE_FILE was written as relative
// does, then 429 with `retry-after: 60` to that token's requests for
// LIMIT_MS after the answer it served, as Anthropic's per-account limit
// turns away frequent reads; a request past that window is served again
// and opens a new one. GET
// /copilot_internal/user answers by MODE_FILE for Copilot: copilot,
// copilot-zero, copilot-unlimited, copilot-refused, copilot-malformed or
// error. The Claude replies are written by hand from the recorded shape:
// five_hour, seven_day, limits[] and seven_day_breakdown. Each request
// appends a line to LOG_FILE with a hash of its authorization value and the
// user-agent, so tests can verify headers without storing tokens.
"use strict";
const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");
const crypto = require("node:crypto");

const RELATIVE = Object.freeze({ five_hour: 19800000, seven_day: 280800000, seven_day_fable: 280800000 });
const LIMIT_MS = 60000;

function hash(value) {
    return value ? crypto.createHash("sha256").update(value).digest("hex") : null;
}
// The request's line in LOG_FILE, which it also returns.
function record(request, logFile) {
    const auth = request.headers.authorization || "";
    const bearer = /^Bearer (.+)$/.exec(auth);
    const token = /^token (.+)$/.exec(auth);
    const line = { method: request.method, path: request.url,
        beta: request.headers["anthropic-beta"] || null, token: bearer === null ? null : hash(bearer[1]),
        authHash: token === null ? null : hash(token[1]), userAgent: request.headers["user-agent"] || null };
    fs.appendFileSync(logFile, JSON.stringify(line) + "\n");
    return line;
}
function relativeClaude() {
    const reply = JSON.parse(fs.readFileSync(path.join(__dirname, "claude-usage.json"), "utf8"));
    reply.five_hour.resets_at = new Date(Date.now() + RELATIVE.five_hour).toISOString();
    reply.seven_day.resets_at = new Date(Date.now() + RELATIVE.seven_day).toISOString();
    for (const entry of reply.limits) {
        if (entry.kind !== "weekly_scoped") continue;
        entry.resets_at = new Date(Date.now() + RELATIVE.seven_day_fable).toISOString();
    }
    return reply;
}
function gatewayBody(mode) {
    if (mode === "gateway-string") return { balance: "10.50", total_used: "5.25" };
    return { balance: 10.50, total_used: 5.25 };
}
function copilotBody(mode) {
    const base = { token_based_billing: true, copilot_plan: "enterprise", quota_reset_date_utc: "2026-11-01T00:00:00.000Z",
        quota_snapshots: { premium_interactions: { entitlement: 1000000, remaining: 954775, credits_used: 362327,
            token_based_billing: true } } };
    if (mode === "copilot-zero") base.quota_snapshots.premium_interactions = { entitlement: 0, remaining: 0, token_based_billing: true };
    if (mode === "copilot-unlimited") base.quota_snapshots.premium_interactions = { unlimited: true, token_based_billing: true };
    return base;
}
function start(portFile, modeFile, logFile) {
    // Mode limited's windows: when each bearer token's hash was last served,
    // for the MODE_FILE write they were opened under.
    let served = new Map();
    let modeWritten = null;
    // Whether limited mode turns this request away: inside its token's
    // window, which a newer write of MODE_FILE closes.
    const limited = token => {
        const written = fs.statSync(modeFile).mtimeMs;
        if (written !== modeWritten) { served = new Map(); modeWritten = written; }
        const at = served.get(token);
        if (at !== undefined && Date.now() - at < LIMIT_MS) return true;
        served.set(token, Date.now());
        return false;
    };
    const server = http.createServer((request, response) => {
        const line = record(request, logFile);
        const mode = fs.readFileSync(modeFile, "utf8").trim();
        if (request.url === "/api/oauth/usage") {
            if (request.method !== "GET") { response.writeHead(404); response.end(); return; }
            if (mode === "hang") return;
            if (mode === "throttled" || (mode === "limited" && limited(line.token))) {
                response.writeHead(429, { "content-type": "application/json", "retry-after": "60" });
                response.end("{}");
                return;
            }
            if (mode === "relative" || mode === "limited") {
                response.writeHead(200, { "content-type": "application/json" });
                response.end(JSON.stringify(relativeClaude()));
                return;
            }
            const reply = { ok: [200, "claude-usage.json"], missing: [200, "claude-usage-missing.json"], null: [200, null],
                malformed: [200, null], refused: [401, null], error: [500, null] }[mode];
            if (reply === undefined) { response.writeHead(400); response.end(); return; }
            response.writeHead(reply[0], { "content-type": "application/json" });
            response.end(reply[1] === null ? (mode === "malformed" ? "{\"five_hour\": " : mode === "null" ? "null" : "{}")
                : fs.readFileSync(path.join(__dirname, reply[1])));
            return;
        }
        if (request.url === "/v1/credits") {
            if (request.method !== "GET") { response.writeHead(404); response.end(); return; }
            if (mode === "gateway-refused") { response.writeHead(401, { "content-type": "application/json" }); response.end("{}"); return; }
            if (mode === "gateway-malformed") { response.writeHead(200, { "content-type": "application/json" }); response.end("{"); return; }
            if (mode === "gateway-error") { response.writeHead(500); response.end("{}"); return; }
            response.writeHead(200, { "content-type": "application/json" });
            response.end(JSON.stringify(gatewayBody(mode)));
            return;
        }
        if (request.url === "/copilot_internal/user") {
            if (request.method !== "GET") { response.writeHead(404); response.end(); return; }
            if (mode === "copilot-refused") { response.writeHead(401, { "content-type": "application/json" }); response.end("{}"); return; }
            if (mode === "copilot-malformed") { response.writeHead(200, { "content-type": "application/json" }); response.end("{"); return; }
            if (["copilot", "copilot-zero", "copilot-unlimited"].includes(mode)) {
                response.writeHead(200, { "content-type": "application/json" });
                response.end(JSON.stringify(copilotBody(mode)));
                return;
            }
            if (mode === "error") { response.writeHead(500); response.end("{}"); return; }
        }
        response.writeHead(404); response.end();
    });
    server.listen(0, "127.0.0.1", () => {
        fs.writeFileSync(portFile + ".next", String(server.address().port));
        fs.renameSync(portFile + ".next", portFile);
    });
    return server;
}

module.exports = { start };
if (require.main === module) start(...process.argv.slice(2, 5));
