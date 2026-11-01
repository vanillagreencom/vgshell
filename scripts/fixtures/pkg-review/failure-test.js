#!/usr/bin/env node
// The package owner's build failure decisions: classifyInstallFailure over
// the recorded makepkg and paru transcripts (scripts/fixtures/pkg/
// check-failure/PROVENANCE.md) and variations derived from them, the
// retry argv PackageManagers builds, and the packageOutcome judge. Each
// control loads a copy of one judge with one rule removed, and a row that
// holds the rule must fail.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const cp = require("node:child_process");
const repo = path.resolve(__dirname, "../../..");
const { load } = require(path.join(repo, "bin/lib/qml-library.js"));
const corpus = path.join(repo, "scripts/fixtures/pkg/check-failure");

const at = process.argv.indexOf("--core");
const core = at < 0 ? path.join(repo, "shell/Core") : process.argv[at + 1];
const review = load(path.join(core, "PackageReview.js"));
const managers = load(path.join(core, "PackageManagers.js"));

// The judges run in their own vm context: compare plain copies.
const plain = value => JSON.parse(JSON.stringify(value));
const transcript = name => fs.readFileSync(path.join(corpus, name + ".out"), "utf8");
const BASE = "vgs-fixture-check-only";
const SUPPORTED = { makepkg: "7.1.0", paru: "2.1.0" };
const ENGLISH = { LANG: "en_US.UTF-8" };
function evidence(name, over = {}) {
    const builder = over.builder || (name.startsWith("paru-") ? "paru" : "makepkg");
    return Object.assign({ builder, versions: SUPPORTED, env: ENGLISH, status: builder === "paru" ? 1 : 4, signal: null,
        interval: { complete: true, text: transcript(name) }, targets: [BASE] }, over);
}
// The check-only transcript with TEXT spliced in before or after it.
const around = (name, before, after) => ({ complete: true, text: before + transcript(name) + after });
const making = (base, finished) => `==> Making package: ${base} 2.0-1 (Sat 31 Oct 2026 03:24:21 PM PDT)\r\n` +
    (finished ? `==> Finished making: ${base} 2.0-1 (Sat 31 Oct 2026 03:24:22 PM PDT)\r\n` : "");

const checkOnly = target => ({ kind: "check-only", base: BASE, version: "1.0-1", target: target || BASE });
const ordinary = reason => ({ kind: "ordinary", reason });
// Each row: a label, its evidence and the answer it must get.
const rows = [
    ["makepkg check-only", evidence("makepkg-check-only"), checkOnly()],
    ["paru check-only", evidence("paru-check-only"), checkOnly()],
    ["paru check-only for a qualified target", evidence("paru-check-only", { targets: ["aur/" + BASE] }), checkOnly("aur/" + BASE)],
    ["a finished dependency base before the target", evidence("paru-check-only", { interval: around("paru-check-only", making("vgs-fixture-dependency", true), "") }), checkOnly()],
    ["English messages under LC_ALL=C despite LANGUAGE", evidence("paru-check-only", { env: { LC_ALL: "C", LANGUAGE: "de" } }), checkOnly()],
    ["makepkg build()", evidence("makepkg-build-fail"), ordinary("phase=other")],
    ["makepkg prepare()", evidence("makepkg-prepare-fail"), ordinary("phase=other")],
    ["makepkg pkgver()", evidence("makepkg-pkgver-fail"), ordinary("phase=other")],
    ["makepkg package()", evidence("makepkg-package-fail"), ordinary("phase=other")],
    ["makepkg missing source", evidence("makepkg-source-missing", { status: 1 }), ordinary("phase=other")],
    ["makepkg integrity", evidence("makepkg-integrity", { status: 1 }), ordinary("phase=other")],
    ["makepkg missing dependency", evidence("makepkg-dependency", { status: 8 }), ordinary("phase=other")],
    ["misleading check text before a package() failure", evidence("makepkg-misleading"), ordinary("makepkg-errors=2")],
    ["a check() that prints a build failure line", evidence("makepkg-spoof-in-check"), ordinary("makepkg-errors=2")],
    ["paru build()", evidence("paru-build-fail"), ordinary("phase=other")],
    ["paru package()", evidence("paru-package-fail"), ordinary("phase=other")],
    ["paru missing source", evidence("paru-source-missing"), ordinary("phase=other")],
    ["paru integrity", evidence("paru-integrity"), ordinary("phase=other")],
    ["paru unresolved dependency", evidence("paru-dependency"), ordinary("makepkg-errors=0")],
    ["paru two failed check() bases", evidence("paru-multi"), ordinary("makepkg-errors=2")],
    ["paru check() and build() failures", evidence("paru-mixed"), ordinary("makepkg-errors=2")],
    ["an interrupt during check()", evidence("makepkg-interrupted", { status: 130 }), ordinary("signal")],
    ["an interrupt's own error line at any status", evidence("makepkg-interrupted"), ordinary("phase=other")],
    ["a signal", evidence("paru-check-only", { status: null, signal: "SIGTERM" }), ordinary("signal")],
    ["no capture", evidence("paru-check-only", { interval: null }), ordinary("capture=failed")],
    ["an end mark that never arrived", evidence("paru-check-only", { interval: { complete: false, text: transcript("paru-check-only") } }), ordinary("interval=incomplete")],
    ["an interval over the bound", evidence("paru-check-only", { interval: around("paru-check-only", "x".repeat(16 * 1024 * 1024), "") }), ordinary("interval=incomplete")],
    ["output cut before Aborting", evidence("makepkg-check-only", { interval: { complete: true, text: transcript("makepkg-check-only").split("    Aborting")[0] } }), ordinary("marker=incomplete")],
    ["output cut before the error", evidence("paru-check-only", { interval: { complete: true, text: transcript("paru-check-only").split("==> ERROR")[0] } }), ordinary("makepkg-errors=0")],
    ["exit 4 alone", evidence("makepkg-check-only", { interval: { complete: true, text: "" } }), ordinary("makepkg-errors=0")],
    ["exit 13 with test words", evidence("makepkg-check-only", { status: 13, interval: { complete: true, text: "test_fixture ... FAILED\r\n" } }), ordinary("makepkg-errors=0")],
    ["paru's summary alone", evidence("paru-check-only", { interval: { complete: true, text: transcript("paru-check-only").split("    Aborting...")[1] } }), ordinary("makepkg-errors=0")],
    ["yay", evidence("paru-check-only", { builder: "yay", versions: { makepkg: "7.1.0", yay: "12.5.0" } }), ordinary("builder=unsupported")],
    ["an unchecked paru version", evidence("paru-check-only", { versions: { makepkg: "7.1.0", paru: "2.2.0" } }), ordinary("version=unsupported")],
    ["an unchecked makepkg version", evidence("makepkg-check-only", { versions: { makepkg: "7.0.0" } }), ordinary("version=unsupported")],
    ["an unread version", evidence("paru-check-only", { versions: { makepkg: "7.1.0", paru: null } }), ordinary("version=unsupported")],
    ["a German message locale", evidence("paru-check-only", { env: { LANG: "de_DE.UTF-8" } }), ordinary("locale=unsupported")],
    ["German first in LANGUAGE", evidence("paru-check-only", { env: { LANG: "en_US.UTF-8", LANGUAGE: "de:en" } }), ordinary("locale=unsupported")],
    // makepkg's de.po wording, put in place of the English line: a locale
    // the step really ran in that the environment did not show.
    ["a translated marker", evidence("makepkg-check-only", { interval: { complete: true, text: transcript("makepkg-check-only").replace("==> ERROR:", "==> FEHLER:").replace("A failure occurred in check().", "Ein Fehler ist in check() aufgetreten.") } }), ordinary("makepkg-errors=0")],
    ["a check failure line that check() did not start", evidence("makepkg-check-only", { interval: { complete: true, text: transcript("makepkg-check-only").replace(/^[^\n]*Starting check\(\)[^\n]*\n/m, "") } }), ordinary("phase=out-of-order")],
    ["a base that did not finish before the target", evidence("paru-check-only", { interval: around("paru-check-only", making("vgs-fixture-dependency", false), "") }), ordinary("bases=ambiguous")],
    ["a helper error before the build", evidence("paru-check-only", { interval: around("paru-check-only", "error: could not resolve a provider\r\n", "") }), ordinary("builder-errors")],
    ["a helper line after its summary", evidence("paru-check-only", { interval: around("paru-check-only", "", "error: another transaction failed\r\n") }), ordinary("summary=mismatch")],
    ["makepkg as the builder of paru's transcript", evidence("paru-check-only", { builder: "makepkg", status: 4 }), ordinary("summary=mismatch")],
    ["a target the base does not name", evidence("paru-check-only", { targets: ["ttfx"] }), ordinary("target=unmatched")],
    ["two targets naming the base", evidence("paru-check-only", { targets: [BASE, "aur/" + BASE] }), ordinary("target=unmatched")]
];

for (const [label, input, want] of rows)
    assert.deepEqual(plain(review.classifyInstallFailure(input)), want, label);
// Every recorded transcript is a row's input, so a new one cannot go unread.
const read = new Set(rows.map(([, input]) => input.interval && input.interval.text));
for (const name of fs.readdirSync(corpus).filter(n => n.endsWith(".out") && !/-(retry|check-pass)\.out$/.test(n)))
    assert.ok(read.has(transcript(name.slice(0, -4))), "unread transcript " + name);

// The retry's argv: the table's step with the helper's words before `--`.
const onPath = found => command => command === found;
const config = "/home/user/.config/vgs pacman.conf";
for (const [label, helper, action, cfg, want] of [
    ["paru install", "paru", "install", undefined, ["paru", "-S", "--needed", "--nocheck", "--", "ttfx"]],
    ["paru update keeps --needed", "paru", "update", undefined, ["paru", "-S", "--needed", "--nocheck", "--", "ttfx"]],
    ["paru reinstall keeps its absence", "paru", "reinstall", undefined, ["paru", "-S", "--nocheck", "--", "ttfx"]],
    ["paru with its config", "paru", "install", config, ["paru", "--config", config, "-S", "--needed", "--nocheck", "--", "ttfx"]],
    ["yay passes makepkg's flag", "yay", "install", undefined, ["yay", "-S", "--needed", "--mflags", "--nocheck", "--", "ttfx"]]
]) {
    const r = managers.retryPlan("aur", action, "ttfx", onPath(helper), cfg);
    assert.ok(r.ok, label);
    assert.deepEqual(plain(r.plan.steps), [want], label);
}
for (const [manager, action] of [["pacman", "install"], ["aur", "upgrade"], ["aur", "remove"]])
    assert.equal(managers.retryPlan(manager, action, "ttfx", onPath("paru")).error, "manager=" + manager + " action=" + action + " retry=unsupported");
assert.deepEqual(plain(managers.bootstrapBuild(false)), ["makepkg", "-si"]);
assert.deepEqual(plain(managers.bootstrapBuild(true)), ["makepkg", "-si", "--nocheck"]);

// The outcome judge: each row VALUE, RUN, CODE and the error, or null for
// an outcome it keeps whole.
const outcome = (kind, extra) => Object.assign({ kind, manager: "aur" }, extra);
for (const [label, value, run, code, error] of [
    ["installed", outcome("package-installed", { helper: "paru" }), "r1", 0, null],
    ["installed by the retry", outcome("package-installed", { helper: "paru", package: "ttfx", testsSkipped: true }), "r1", 0, null],
    ["installed with a failing code", outcome("package-installed", { helper: "paru" }), "r1", 1, "status"],
    ["testsSkipped without its package", outcome("package-installed", { helper: "paru", testsSkipped: true }), "r1", 0, "tests-skipped"],
    ["testsSkipped false", outcome("package-installed", { helper: "paru", package: "ttfx", testsSkipped: false }), "r1", 0, "tests-skipped"],
    ["skipped", outcome("package-skipped"), "r1", 0, null],
    ["failed", outcome("package-failed", { helper: null, status: 1 }), "r1", 1, null],
    ["failed with another code", outcome("package-failed", { helper: null, status: 1 }), "r1", 2, "status"],
    ["failed at exit 0", outcome("package-failed", { helper: null, status: 0 }), "r1", 0, "status"],
    ["cancelled", outcome("package-cancelled", { status: 130 }), "r1", 130, null],
    ["cancelled below 128", outcome("package-cancelled", { status: 1 }), "r1", 1, "status"],
    ["check failed, retry held for this run", outcome("package-check-failed", { helper: "paru", package: "ttfx", status: 1, retry: { originRun: "r1", state: "available" } }), "r1", 1, null],
    ["check failed, retry held for another run", outcome("package-check-failed", { helper: "paru", package: "ttfx", status: 1, retry: { originRun: "r0", state: "available" } }), "r1", 1, "retry-run"],
    ["check failed, retry consumed by another run", outcome("package-check-failed", { helper: "paru", package: "ttfx", status: 1, retry: { originRun: "r0", state: "consumed" } }), "r1", 1, null],
    ["check failed, no retry", outcome("package-check-failed", { helper: "paru", package: "ttfx", status: 1, retry: null }), "r1", 1, null],
    ["check failed, retry with a path", outcome("package-check-failed", { helper: "paru", package: "ttfx", status: 1, retry: { originRun: "r1", state: "available", argv: ["paru"] } }), "r1", 1, "retry"],
    ["check failed without its package", outcome("package-check-failed", { helper: "paru", status: 1, retry: null }), "r1", 1, "package"],
    ["an unknown kind", outcome("package-maybe"), "r1", 0, "kind"],
    ["an extra field", outcome("package-skipped", { argv: ["paru"] }), "r1", 0, "field=argv"],
    ["an unknown manager", { kind: "package-skipped", manager: "brew" }, "r1", 0, "manager"]
]) {
    const judged = plain(review.packageOutcome(value, run, code));
    if (error === null) assert.deepEqual(judged, { ok: true, outcome: value }, label);
    else assert.deepEqual(judged, { ok: false, error }, label);
}

// Controls: a copy of shell/Core with one rule removed fails this file.
if (at < 0) {
    const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "package-failure-control-"));
    try {
        for (const [name, file, needle, replacement] of [
            ["one-error", "PackageReview.js", "if (errors.length !== 1) return", "if (errors.length === 0) return"],
            ["check-phase", "PackageReview.js", 'if (started !== "check") return', "if (false) return"],
            ["summary", "PackageReview.js", "return ordinary(\"summary=mismatch\");", ";"],
            ["locale", "PackageReview.js", 'if (!englishMessages(e.env)) return ordinary("locale=unsupported");', ""],
            ["retry-run", "PackageReview.js", 'if (retry.state === "available" && retry.originRun !== run) return fail("retry-run");', ""],
            ["skip-words", "PackageManagers.js", 'var SKIP_TESTS = { paru: ["--nocheck"], yay: ["--mflags", "--nocheck"] };', 'var SKIP_TESTS = { paru: ["--nocheck"], yay: ["--nocheck"] };']
        ]) {
            const copy = path.join(scratch, name);
            fs.cpSync(path.join(repo, "shell/Core"), copy, { recursive: true });
            const source = fs.readFileSync(path.join(copy, file), "utf8");
            assert.equal(source.split(needle).length - 1, 1, name);
            fs.writeFileSync(path.join(copy, file), source.replace(needle, replacement));
            const r = cp.spawnSync(process.execPath, [__filename, "--core", copy], { encoding: "utf8" });
            assert.notEqual(r.status, 0, "the " + name + " mutant passes");
            assert.match(r.stderr, /ERR_ASSERTION/, name + ": " + r.stderr);
        }
    } finally {
        fs.rmSync(scratch, { recursive: true, force: true });
    }
    console.log("test-package-failure: ok");
}
