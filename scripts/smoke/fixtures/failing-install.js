#!/usr/bin/env node
// A requirement install that fails as a bad mirror makes pacman fail, in
// place of the core's `vgshell pkg run install`, which the sandbox never
// runs. The step's output, kept as bin/lib/pkg-run.sh --evidence keeps a
// failed step's cut, goes through the package owner's own failure report
// (bin/lib/pkg-retry.js stepInterval, failed and report) to the outcome
// channel of the presenter that runs this file, and the run exits 1. The
// cut names a mirror with a user and password, which no line of the
// outcome may carry.
//
//   failing-install.js ARG...    ARG, the run's own arguments, unread
"use strict";
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const retry = require(path.join(__dirname, "..", "..", "..", "bin", "lib", "pkg-retry.js"));

const STATUS = 1;
const cut = [
    "\u001b[1m:: Retrieving packages...\u001b[0m",
    " vgs-smoke-needs-pkg-1.0-1-any downloading...\r vgs-smoke-needs-pkg-1.0-1-any failed",
    "error: failed retrieving file 'vgs-smoke-needs-pkg-1.0-1-any.pkg.tar.zst' from https://smoke:mirror-secret@mirror.invalid/core : The requested URL returned error: 404",
    "error: failed to commit transaction (failed to retrieve some files)",
    "Errors occurred, no packages were upgraded.",
    ""
].join("\r\n");
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "failing-install-"));
try {
    fs.writeFileSync(path.join(dir, "interval"), cut);
    fs.writeFileSync(path.join(dir, "result"), "step=1 status=" + STATUS + " cut=ok\n");
    process.stdout.write(cut);
    retry.report(retry.failed("pacman", null, STATUS, retry.stepInterval(dir, STATUS).interval), STATUS);
} finally {
    fs.rmSync(dir, { recursive: true, force: true });
}
process.exit(STATUS);
