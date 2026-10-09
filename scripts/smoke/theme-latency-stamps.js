// Preloaded with `node --require` into the theme judge of the latency
// row's applies: on exit it appends one JSON line to the file
// VGS_LATENCY_STAMPS names with the epoch ms of each part of the process,
// so a slow reading names where its time went. `spawned` is when the row's
// stand-in bin/vgshell started, which VGS_LATENCY_SPAWNED carries in
// bash's EPOCHREALTIME seconds; `node` when node started; `ready` when
// node had booted and ran this file; `backgrounds`, `theme` and `applied`
// when the judge renamed backgrounds.json, theme.json and applied.json
// into place; `exit` when it exits. While the gate file VGS_LATENCY_HOLD
// names exists, the process that renamed theme.json holds its exit, so the
// shell's apply answer waits, for at most the VGS_LATENCY_HOLD_MS the row
// sets past its own poll bound, so a view that waits for the answer fails
// the row's poll before the hold ends: `held` is when the hold starts,
// after its line is written. The wait sleeps in SLICE_MS slices on
// Atomics.wait, which blocks node's main thread without spinning.
const fs = require("fs");
const path = require("path");
const out = process.env.VGS_LATENCY_STAMPS;
const hold = process.env.VGS_LATENCY_HOLD;
const holdMs = Number(process.env.VGS_LATENCY_HOLD_MS);
if (hold !== undefined && hold !== "" && !(Number.isInteger(holdMs) && holdMs > 0))
    throw new Error("theme-latency-stamps: hold-ms=" + JSON.stringify(process.env.VGS_LATENCY_HOLD_MS));
const SLICE_MS = 20;
const stamps = {
    spawned: Math.round(Number(process.env.VGS_LATENCY_SPAWNED) * 1000),
    node: Math.round(performance.timeOrigin),
    ready: Date.now()
};
const named = { "backgrounds.json": "backgrounds", "theme.json": "theme", "applied.json": "applied" };
const rename = fs.renameSync;
fs.renameSync = function (from, to) {
    const result = rename.apply(this, arguments);
    const stage = named[path.basename(String(to))];
    if (stage !== undefined && stamps[stage] === undefined) stamps[stage] = Date.now();
    return result;
};
process.on("exit", () => {
    stamps.exit = Date.now();
    const holding = hold !== undefined && hold !== "" && stamps.theme !== undefined && fs.existsSync(hold);
    if (holding) stamps.held = Date.now();
    fs.appendFileSync(out, JSON.stringify(stamps) + "\n");
    if (!holding) return;
    const cell = new Int32Array(new SharedArrayBuffer(4));
    while (fs.existsSync(hold) && Date.now() - stamps.held < holdMs) Atomics.wait(cell, 0, 0, SLICE_MS);
});
