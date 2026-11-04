#!/usr/bin/env node
// Safe requirement-result producer for the notices smoke row and captures.
// MODE_FILE PROOF_JSONL VERSION_COMMAND ARG...: MODE_FILE holds available,
// consumed or success; ARG is the original `vgshell pkg ...` argv. The
// supported paru corpus supplies the check-only classification, with only
// its fixture target renamed to the row's outdated package. The real
// presenter judges and records this command's outcome. No manager runs.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../..");
const judge = require(path.join(root, "bin/lib/qml-library.js")).load(path.join(root, "shell/Core/PackageReview.js"));
const run = process.env.VGS_TUI_RECORD_RUN;
const retry = require(path.join(root, "bin/lib/pkg-retry.js"));
const [modeFile, proof, versionCommand, ...argv] = process.argv.slice(2);
const mode = fs.readFileSync(modeFile, "utf8").trim();
const target = "vgs-smoke-old-aur";
assert(["available", "consumed", "success"].includes(mode));
assert.equal(argv[1], "pkg");
const isRetry = argv[2] === "retry";
assert(isRetry ? argv.length === 4 : argv[2] === "run" && argv[3] === "update" && argv.includes(target));
fs.appendFileSync(proof, JSON.stringify({ mode, run, argv }) + "\n");
if (isRetry && mode === "success") {
    fs.writeFileSync(versionCommand, "#!/bin/sh\nprintf '%s\\n' 'vgs-smoke-old 2.0.0'\n", { mode: 0o755 });
    retry.report({ kind: "package-installed", manager: "aur", helper: "paru", package: target, testsSkipped: true }, 0);
    process.exit(0);
}
const text = fs.readFileSync(path.join(root, "scripts/fixtures/pkg/check-failure/paru-check-only.out"), "utf8")
    .replaceAll("vgs-fixture-check-only", target);
const verdict = judge.classifyInstallFailure({ builder: "paru", versions: { makepkg: "7.1.0", paru: "2.1.0" },
    env: { LC_ALL: "C" }, status: 1, signal: null, interval: { complete: true, text }, targets: [target] });
assert.equal(verdict.kind, "check-only");
assert.equal(verdict.target, target);
process.stdout.write(text);
retry.report({ kind: "package-check-failed", manager: "aur", helper: "paru", package: verdict.target, status: 1,
    retry: { originRun: isRetry ? argv[3] : run, state: isRetry ? "consumed" : "available" } }, 1);
process.exit(1);
