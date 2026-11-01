// The package owner's build failures: the evidence a failed AUR build left,
// the one retry without package tests a check-only failure offers, the
// retry a requirement notice's run holds for later, and the typed outcome
// the owner hands its presenter. shell/Core/PackageReview.js judges the
// evidence and the outcome; PackageManagers.js alone builds the retry argv.
//
// The channel: `vgshell-tui present` exports VGS_TUI_OUTCOME, the run's
// private outcome file, VGS_TUI_OUTCOME_PID, its own pid, and
// VGS_TUI_RECORD_KEY and VGS_TUI_RECORD_RUN, the run's key and id. Loading
// this file removes all four from this process's environment, so nothing
// the owner starts, a nested `vgshell pkg run` included, inherits them, and
// keeps them only when this process is the presenter's own command: a
// script the presenter ran that runs the owner in turn reports for itself.
//
// A held retry: only a run keyed core/requirements-install or
// core/requirements-update that stopped at its check-only failure keeps
// one, as <key stem>@<run>.json in the private retry directory beneath the
// package review workspace; each key keeps its latest only. A new ordinary
// run of the key retires it, `vgshell pkg retry <run>` claims it by rename
// before anything runs, and it lapses with the run's ended record or the
// runtime directory. It holds the failed target, action, manager, resolved
// helper, config and the target's gathered binding, never argv.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const cp = require("node:child_process");
const { load } = require("./qml-library.js");
const { refuse, onPath } = require("./judge-files.js");
const review = require("./pkg-review.js");
const outcomeChannel = require("./pkg-outcome.js");
const repo = path.resolve(__dirname, "../..");
const judge = load(path.join(repo, "shell/Core/PackageReview.js"));
const managers = load(path.join(repo, "shell/Core/PackageManagers.js"));

const CHANNEL_ENV = ["VGS_TUI_OUTCOME", "VGS_TUI_OUTCOME_PID", "VGS_TUI_RECORD_KEY", "VGS_TUI_RECORD_RUN"];
const REQUIREMENT_KEYS = ["core/requirements-install", "core/requirements-update"];
// The seconds a `--version` query may take.
const VERSION_TIMEOUT = 10;

const channel = (() => {
    const env = process.env;
    const own = env.VGS_TUI_OUTCOME_PID !== undefined && Number(env.VGS_TUI_OUTCOME_PID) === process.ppid;
    const held = own && env.VGS_TUI_OUTCOME && env.VGS_TUI_RECORD_KEY && env.VGS_TUI_RECORD_RUN
        ? { file: env.VGS_TUI_OUTCOME, key: env.VGS_TUI_RECORD_KEY, run: env.VGS_TUI_RECORD_RUN } : null;
    for (const name of CHANNEL_ENV) delete env[name];
    return held;
})();

const stem = key => key.replace("/", "@");

// One private directory for one build's evidence, beneath the review
// workspace; the caller removes it.
function evidenceDir(prefix) {
    const dir = fs.mkdtempSync(path.join(review.agentHome(), prefix));
    fs.chmodSync(dir, 0o700);
    return dir;
}

// The version COMMAND reports, `paru v2.1.0 ...` or `makepkg (pacman)
// 7.1.0`, or null when it cannot say.
function versionOf(command) {
    const r = cp.spawnSync(command, ["--version"], { encoding: "utf8", timeout: VERSION_TIMEOUT * 1000, stdio: ["ignore", "pipe", "ignore"],
        cwd: process.env.HOME || "/", env: { ...process.env, LC_ALL: "C" } });
    if (r.error !== undefined || r.status !== 0) return null;
    const m = /^(?:\S+ v|makepkg \(pacman\) )([0-9]+\.[0-9]+\.[0-9]+)\b/.exec(r.stdout);
    return m === null ? null : m[1];
}

// The evidence pkg-run.sh --evidence left in DIR for a run of BUILDER over
// TARGETS that exited STATUS, as classifyInstallFailure reads it.
function evidence(dir, builder, targets, status) {
    let interval = null;
    let result = null;
    try {
        result = /^step=[0-9]+ status=([0-9]+) cut=([a-z-]+)\n$/.exec(fs.readFileSync(path.join(dir, "result"), "utf8"));
    } catch (e) {
        if (e.code !== "ENOENT") throw e;
    }
    if (result !== null && Number(result[1]) === status) {
        interval = { complete: false, text: "" };
        if (result[2] === "ok") {
            // The cut is the owner's own private file; an unreadable one is
            // incomplete evidence.
            try {
                const file = path.join(dir, "interval");
                if (fs.lstatSync(file).size <= judge.FAILURE_INTERVAL_MAX) interval = { complete: true, text: fs.readFileSync(file, "utf8") };
            } catch (e) {
                interval = { complete: false, text: "" };
            }
        }
    }
    const env = {};
    for (const name of ["LC_ALL", "LC_MESSAGES", "LANG", "LANGUAGE"]) if (process.env[name] !== undefined) env[name] = process.env[name];
    const versions = { makepkg: versionOf("makepkg") };
    if (builder !== "makepkg") versions[builder] = versionOf(builder);
    return { builder, versions, env, status, signal: null, interval, targets };
}

// The binding a held retry keeps for TARGET: the review owner's gathered
// identity of the helper, its configuration and the target's origin, or
// null when it cannot be read.
function binding(manager, action, target, config) {
    const state = review.gather({ version: 1, mode: "named", action, groups: [{ manager, names: [target], installs: [], ignored: [] }],
        sources: [], rebuild: [], config: config === undefined ? null : config, customAurArgv: null });
    const step = state.steps[0];
    return step.binding === null ? null : { binary: step.binary, binding: step.binding };
}

function retryDir() {
    const dir = path.join(review.agentHome(), "retry");
    try {
        fs.mkdirSync(dir, { mode: 0o700 });
    } catch (e) {
        if (e.code !== "EEXIST") throw e;
    }
    review.ownedDirectory(dir);
    return dir;
}

// Removes every retry KEY holds; another key's stays.
function retire(dir, key) {
    for (const name of fs.readdirSync(dir))
        if (name.startsWith(stem(key) + "@") && name.endsWith(".json")) fs.rmSync(path.join(dir, name), { force: true });
}

// A new ordinary run of a requirement key retires the retry it held.
function retireHeld() {
    if (channel !== null && REQUIREMENT_KEYS.includes(channel.key)) retire(retryDir(), channel.key);
}

// Holds the one retry of this run's check-only failure of TARGET for its
// requirement notice, replacing the key's earlier one. Answers the
// outcome's retry: available, or null when this run is no requirement's
// or the target's binding cannot be read.
function hold(manager, action, target, config) {
    if (channel === null || !REQUIREMENT_KEYS.includes(channel.key)) return null;
    let bound;
    try {
        bound = binding(manager, action, target, config);
    } catch (e) {
        bound = null;
    }
    if (bound === null) return null;
    const dir = retryDir();
    const record = { version: 1, key: channel.key, run: channel.run, manager, action, target, config: config === undefined ? null : config, ...bound };
    const name = stem(channel.key) + "@" + channel.run + ".json";
    const hidden = path.join(dir, "." + name + "." + crypto.randomBytes(6).toString("hex"));
    fs.writeFileSync(hidden, JSON.stringify(record), { flag: "wx", mode: 0o600 });
    retire(dir, channel.key);
    fs.renameSync(hidden, path.join(dir, name));
    return { originRun: channel.run, state: "available" };
}

// Claims the retry run RUN holds: renamed away first, so a second claim or
// a retirement finds nothing, then judged. Refuses `retry=unavailable` when
// none is held, `retry=stale` when the run's ended record is gone, and
// `retry=changed` when the helper, configuration or target's origin no
// longer match; none of them runs anything, and none restores the claim.
function claim(run) {
    const dir = retryDir();
    let claimed = null;
    for (const key of REQUIREMENT_KEYS) {
        const to = path.join(dir, ".claimed-" + crypto.randomBytes(6).toString("hex"));
        try {
            fs.renameSync(path.join(dir, stem(key) + "@" + run + ".json"), to);
        } catch (e) {
            if (e.code === "ENOENT") continue;
            throw e;
        }
        claimed = to;
        break;
    }
    if (claimed === null) refuse("retry=unavailable run=" + run);
    let record;
    try {
        record = JSON.parse(review.privateFile(claimed));
    } finally {
        fs.rmSync(claimed, { force: true });
    }
    if (record.version !== 1 || record.run !== run || !REQUIREMENT_KEYS.includes(record.key)) refuse("retry=unavailable run=" + run);
    const records = path.join(process.env.XDG_RUNTIME_DIR, "vgshell", "tui");
    if (!fs.existsSync(path.join(records, stem(record.key) + "@" + run + ".ended.json"))) refuse("retry=stale run=" + run);
    let now;
    try {
        now = binding(record.manager, record.action, record.target, record.config === null ? undefined : record.config);
    } catch (e) {
        now = null;
    }
    if (now === null || JSON.stringify(now) !== JSON.stringify({ binary: record.binary, binding: record.binding })) refuse("retry=changed run=" + run);
    return record;
}

// The retry's steps for a claimed or immediate failure of TARGET.
function retrySteps(manager, action, target, config) {
    const r = managers.retryPlan(manager, action, target, onPath, config);
    if (!r.ok) refuse(r.error);
    return r.plan.steps;
}

// After BUILDER's run over TARGETS failed with STATUS and left its evidence
// in DIR: a check-only failure asks Retry without tests or Stop, Stop
// selected. RERUN(steps) runs the retry's steps once and answers their
// status. Answers { status, outcome } for the run to exit with: Stop keeps
// STATUS, a retry its own status, a cancelled question 128 plus its signal.
async function afterFailure({ dir, manager, builder, targets, status, retry }) {
    const verdict = judge.classifyInstallFailure(evidence(dir, builder, targets, status));
    if (verdict.kind !== "check-only") return { status, outcome: failed(manager, builder, status) };
    const answer = await review.ui("retry", verdict.target);
    if (answer.cancelled) return { status: answer.status, outcome: { kind: "package-cancelled", manager, status: answer.status } };
    if (answer.value === "Stop") {
        const held = retry.hold === undefined ? null : retry.hold(verdict.target);
        return { status, outcome: { kind: "package-check-failed", manager, helper: builder, package: verdict.target, status, retry: held } };
    }
    if (answer.value !== "Retry without tests") refuse("retry=choice-invalid");
    const again = await retry.run(verdict.target);
    return again === 0
        ? { status: 0, outcome: { kind: "package-installed", manager, helper: builder, package: verdict.target, testsSkipped: true } }
        : { status: again, outcome: again >= 128 ? { kind: "package-cancelled", manager, status: again }
            : { kind: "package-check-failed", manager, helper: builder, package: verdict.target, status: again, retry: consumed() } };
}

function failed(manager, helper, status) {
    return status >= 128 ? { kind: "package-cancelled", manager, status } : { kind: "package-failed", manager, helper, status };
}

// A retry this run consumed, named for the run that offered it.
function consumed(originRun) {
    const run = originRun !== undefined ? originRun : channel === null ? null : channel.run;
    return run === null ? null : { originRun: run, state: "consumed" };
}

// Hands OUTCOME to the presenter, when this process is its command; the
// run then exits STATUS. A write that fails is reported and changes
// nothing else: the steps already ran.
function report(outcome, status) {
    if (channel === null) return;
    const failure = outcomeChannel.write(channel.file, outcome, channel.run, status);
    if (failure !== null) process.stderr.write("vgshell: package-outcome=unwritten reason=" + failure + "\n");
}

module.exports = { afterFailure, claim, consumed, evidenceDir, failed, hold, report, retireHeld, retrySteps };
