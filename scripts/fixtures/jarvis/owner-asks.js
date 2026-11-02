#!/usr/bin/env node
// Test-only package command, copied to HOME/.agents/skills/jarvis/scripts/jarvis-session.
// --seed HOME [COUNT], --state HOME, --mode HOME MODE and --verify HOME ID
// are fixture controls. Product callers use only the actual owner-asks CLI.
"use strict";
const fs = require("node:fs"), path = require("node:path");
const args = process.argv.slice(2);
const output = value => process.stdout.write(JSON.stringify(value) + "\n");
const fileAt = home => path.join(home, ".owner-asks-fixture.json");
const callsAt = home => path.join(home, ".owner-asks-fixture-calls.jsonl");
function write(home, value) {
    fs.writeFileSync(fileAt(home) + ".next", JSON.stringify(value), { mode: 0o600 });
    fs.renameSync(fileAt(home) + ".next", fileAt(home));
}
function seed(home, count = 3) {
    fs.mkdirSync(home, { recursive: true });
    const common = { revision: "1", askedAt: new Date(Date.now() - 3600000).toISOString(), state: "open", snoozedUntil: null,
        actions: { reply: { allowed: true, reason: "" }, done: { allowed: true, reason: "" }, later: { allowed: true, reason: "" } } };
    const rows = [
        { id: "jarvis-briefing", kind: "jarvis-ask", what: "Choose the voice for tomorrow's briefing", askedBy: { id: "jarvis", name: "Jarvis" }, link: { label: "Briefing thread", url: "https://example.invalid/briefing" } },
        { id: "tracker-design", kind: "tracker-item", what: "Review the console design", askedBy: { id: "overseer", name: "Shell overseer" }, link: { label: "VGS-2185", url: "https://linear.app/vanillagreen/issue/VGS-2185" } },
        { id: "fleet-update", kind: "fleet-approval", what: "Approve the update on px13", askedBy: { id: "fleet", name: "Fleet" }, link: { label: "Approval thread", url: "https://example.invalid/fleet" } }
    ];
    for (let i = rows.length; i < count; i++) rows.push({ ...rows[0], id: "ask-" + i, what: "Review ask " + i });
    write(home, { revision: 1, mode: "ready", receipts: {}, rows: rows.slice(0, count).map(row => ({ ...common, ...row, threadRef: "thread:" + row.id })) });
    fs.writeFileSync(callsAt(home), "", { mode: 0o600 });
}
if (args[0] === "--seed") { seed(args[1], args[2] === undefined ? 3 : Number(args[2])); process.exit(0); }
if (args[0] === "--state") { output(JSON.parse(fs.readFileSync(fileAt(args[1]), "utf8"))); process.exit(0); }
if (["--mode", "--verify"].includes(args[0])) {
    const home = args[1], state = JSON.parse(fs.readFileSync(fileAt(home), "utf8"));
    if (args[0] === "--mode") state.mode = args[2];
    else { state.rows = state.rows.filter(row => row.id !== args[2]); state.revision++; }
    write(home, state); process.exit(0);
}
const home = args.includes("--home") ? args[args.indexOf("--home") + 1] : null;
if (args[0] !== "owner-asks") {
    output({ v: 1, state: "stopped", reason: "never-started", detail: "", home, harness: null, account: null });
    process.exit(0);
}
if (home === null) process.exit(2);
const state = JSON.parse(fs.readFileSync(fileAt(home), "utf8"));
const verb = args[1];
const input = verb === "list" ? null : JSON.parse(fs.readFileSync(0, "utf8"));
fs.appendFileSync(callsAt(home), JSON.stringify({ argv: args, input }) + "\n");
if (state.mode === "unavailable") { output({ v: 1, kind: "unavailable", cause: "The owner-asks route is unavailable." }); process.exit(2); }
if (state.mode === "malformed") { process.stdout.write("unreadable\n"); process.exit(0); }
if (verb === "list") {
    const view = args[args.indexOf("--view") + 1];
    const rows = state.rows.filter(row => (row.state === "snoozed") === (view === "snoozed"));
    const cursor = args.includes("--cursor") ? args[args.indexOf("--cursor") + 1] : null;
    const at = cursor === null ? 0 : Number(cursor.split(":")[1]);
    if (cursor !== null && cursor.split(":")[0] !== String(state.revision)) { output({ v: 1, kind: "unavailable", cause: "The page changed." }); process.exit(1); }
    const page = rows.slice(at, at + 3);
    const next = at + page.length < rows.length ? state.revision + ":" + (at + page.length) : null;
    output({ v: 1, homeId: "fixture-home", revision: String(state.revision), observedAt: new Date().toISOString(),
        activeCount: state.rows.filter(row => row.state !== "snoozed").length,
        snoozedCount: state.rows.filter(row => row.state === "snoozed").length, rows: page, nextCursor: next, complete: next === null });
} else {
    if (state.receipts[input.requestId] !== undefined) { output(state.receipts[input.requestId]); process.exit(0); }
    const id = args[args.indexOf("--id") + 1], row = state.rows.find(row => row.id === id);
    let receipt;
    if (!row || row.revision !== input.expectedRevision) receipt = { v: 1, requestId: input.requestId, kind: "refused", state: row ? row.state : "closed", cause: "This ask changed. Refresh before trying again." };
    else if (!row.actions[verb].allowed) receipt = { v: 1, requestId: input.requestId, kind: "refused", state: row.state, cause: row.actions[verb].reason };
    else if (verb === "later" && Date.parse(input.until) <= Date.now()) receipt = { v: 1, requestId: input.requestId, kind: "refused", state: row.state, cause: "Choose a future date and time." };
    else {
        state.revision++;
        row.revision = String(state.revision);
        if (verb === "done") { row.state = "checking"; row.statusText = "Jarvis is checking your evidence before closing this ask."; }
        else if (verb === "later") { row.state = "snoozed"; row.snoozedUntil = input.until; }
        else if (verb !== "reply") process.exit(2);
        receipt = { v: 1, requestId: input.requestId, kind: "accepted", state: row.state, cause: "" };
    }
    state.receipts[input.requestId] = receipt;
    write(home, state);
    if (state.mode === "receipt-malformed") { process.stdout.write("unreadable\n"); process.exit(0); }
    if (state.mode === "receipt-timeout") {
        process.stderr.write("fixture: receipt-written\n");
        setInterval(() => {}, 1000);
        return;
    }
    output(receipt);
}
