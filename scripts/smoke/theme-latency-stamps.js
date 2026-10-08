// Preloaded with `node --require` into the theme judge of the latency
// row's applies: on exit it appends one JSON line to the file
// VGS_LATENCY_STAMPS names with the epoch ms of each part of the process,
// so a slow reading names where its time went. `spawned` is when the row's
// stand-in bin/vgshell started, which VGS_LATENCY_SPAWNED carries in
// bash's EPOCHREALTIME seconds; `node` when node started; `ready` when
// node had booted and ran this file; `backgrounds`, `theme` and `applied`
// when the judge renamed backgrounds.json, theme.json and applied.json
// into place; `exit` when it exits.
const fs = require("fs");
const path = require("path");
const out = process.env.VGS_LATENCY_STAMPS;
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
    fs.appendFileSync(out, JSON.stringify(stamps) + "\n");
});
