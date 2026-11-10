// The package drift reading of the selected Jarvis home (D126): kendex's
// own answer, `kendex check --scope project --report-only --json`, run in
// the home when the Setup tab opens or a package update ends, and at most
// once a day while Jarvis runs, never at a Voice start. VGS reads only
// the report's typed `status`, `class` and `remedy` fields, never its
// prose, kendex's lock or its snapshot, and keeps no drift judge of its own. --report-only leaves the home's install
// record as it is; kendex may still start its own detached source refresh,
// which outlives the check by kendex's design (crates/cli/src/commands/
// check.rs, kendex 6c00d3e19). A reading binds to the home and the
// selection it ran for: a result for an older selection is dropped.
"use strict";

// The daily reading's interval, the "at most once a day" of D126.
const DAY_MS = 24 * 60 * 60 * 1000;
// A recovery bound for a check that hangs, not a measured latency.
const CHECK_MS = 30000;
// The report of a home's few packages stays far below this.
const OUTPUT_BYTES = 1 << 20;
// What kendex reads besides the home: the user's tools, its own config,
// data, state and cache folders and the locale. No credential reaches it.
const ENVIRONMENT = ["PATH", "HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_RUNTIME_DIR"];
// kendex's CheckStatus and its exit code: 0 clean, 1 drift or not yet
// evaluated, 2 could not check (crates/core/src/drift/report.rs).
const STATUS_EXIT = Object.freeze({ clean: 0, drift: 1, unknown: 2 });
// kendex's Class (the same file).
const CLASSES = Object.freeze(["drift", "notice", "unevaluated", "unknown", "settling"]);
// The readings a home's drift can hold. "behind" alone offers the update.
const KINDS = Object.freeze(["none", "checking", "current", "behind", "drift", "pending", "unknown",
    "kendex-missing", "malformed", "timeout", "failed"]);
// The readings of a check that ran and gave no answer: each logs the cause
// it never publishes. A missing kendex runs nothing, and its reading is its
// whole cause, so it logs nothing.
const NON_ANSWERS = Object.freeze(["malformed", "timeout", "failed"]);
// The first stderr line a non-answer logs, at most this many characters.
const STDERR_CHARS = 200;

function object(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }

// The report's lines from STDOUT, kendex's CheckReport, and the exit CODE
// it ended with, or null for any other shape.
function lines(stdout, code) {
    let report;
    try { report = JSON.parse(stdout); } catch { return null; }
    if (!object(report) || !Object.hasOwn(STATUS_EXIT, report.status) || STATUS_EXIT[report.status] !== code
            || !Array.isArray(report.sections)) return null;
    const found = [];
    for (const section of report.sections) {
        if (!object(section) || !Array.isArray(section.lines)) return null;
        for (const line of section.lines) {
            if (!object(line) || !CLASSES.includes(line.class)) return null;
            if (line.remedy !== undefined && (!object(line.remedy) || typeof line.remedy.verb !== "string")) return null;
            found.push(line);
        }
    }
    return { status: report.status, lines: found };
}

/**
 * The reading of one finished check, CHILD Child.run's result, as {kind}:
 * "behind" when a drift line's remedy is a project refresh, the one update
 * VGS offers, whichever package of the home the line names; an
 * unevaluated line's refresh is a comparison still owed, never an update
 * (report/scope.rs). Else "unknown" when kendex could not check a part, "pending"
 * while a comparison is owed, "drift" for a change whose remedy is not a
 * refresh, which the user resolves through kendex, and "current" for a
 * report with notices alone. A run that did not finish within its bound is
 * "timeout", one that printed no report "malformed", and one that failed
 * otherwise "failed"; each of these carries its cause, which is logged and
 * never published. null for a cancelled run, which answers nothing.
 */
function classify(child) {
    if (child.kind === "stopped") {
        if (child.reason === "cancelled") return null;
        if (child.reason === "timeout") return { kind: "timeout", cause: "timeout" };
        if (child.reason === "output-limit") return { kind: "malformed", cause: "output-limit" };
        return { kind: "failed", cause: "stopped=" + child.reason };
    }
    if (child.kind !== "exited") return { kind: "failed", cause: "spawn=" + child.error };
    if (child.code === null) return { kind: "failed", cause: "signal" };
    if (!Object.values(STATUS_EXIT).includes(child.code)) return { kind: "failed", cause: "exit=" + child.code };
    const read = lines(child.stdout, child.code);
    // kendex exits 2 with no report when it fails before the check runs
    // (crates/cli/tests/cli.rs, check_failing_before_it_runs_exits_2).
    if (read === null) return { kind: child.code === 2 && child.stdout.trim() === "" ? "failed" : "malformed", cause: "exit=" + child.code };
    const classes = read.lines.map(line => line.class);
    if (read.lines.some(line => line.class === "drift" && line.remedy?.verb === "refresh" && line.remedy.global === false))
        return { kind: "behind" };
    if (read.status === "unknown" || classes.includes("unknown")) return { kind: "unknown" };
    if (classes.includes("unevaluated") || classes.includes("settling")) return { kind: "pending" };
    if (read.status === "drift" || classes.includes("drift")) return { kind: "drift" };
    return { kind: "current" };
}

/**
 * The one drift reader of the daemon. Options:
 *   run(file, argv, options)  Child.run
 *   kendex()        the absolute path of kendex on PATH, or null
 *   environment     the daemon's environment, ENVIRONMENT picks from it
 *   clock           {wallNow, set, clear}
 *   load()          the wall time of the last finished check, or null
 *   store(at)       record that time
 *   publish(home, drift)  the reading for HOME, an absolute path or null
 *   log(line)
 * select(home) names the selected home, null for none; a new selection
 * ends the running check and schedules the daily one. request() reads the
 * selected home now, as Setup's opening and a finished update ask. close()
 * ends both.
 */
function create({ run, kendex, environment, clock, load, store, publish, log }) {
    let home = null;
    let selection = 0;
    let running = null;
    let timer = null;
    let closed = false;
    // The wall time of this owner's last finished reading, kept here as
    // well as stored, so a store that fails never brings the next reading
    // forward: the daily one waits from the later of the two.
    let finished = null;

    function schedule() {
        if (timer !== null) clock.clear(timer);
        timer = null;
        if (closed || home === null) return;
        const times = [load(), finished].filter(at => at !== null);
        const wait = times.length === 0 ? 0 : Math.max(0, Math.max(...times) + DAY_MS - clock.wallNow());
        timer = clock.set(() => { timer = null; check(); }, wait);
    }

    function check() {
        if (closed || home === null) return;
        if (running !== null && running.selection === selection) return;
        const target = home;
        const own = { selection, controller: new AbortController() };
        running = own;
        const file = kendex();
        if (file === null) {
            running = null;
            finish(own, target, { kind: "kendex-missing" });
            return;
        }
        publish(target, { kind: "checking" });
        const env = { LANG: "C.UTF-8" };
        for (const name of ENVIRONMENT) if (environment[name] !== undefined) env[name] = environment[name];
        void run("setpriv", ["--pdeathsig", "KILL", "--", file, "check", "--scope", "project", "--report-only", "--json"],
            { env, cwd: target, limit: OUTPUT_BYTES, deadline: CHECK_MS, group: true, signal: own.controller.signal })
            .then(child => {
                if (running === own) running = null;
                const drift = classify(child);
                if (drift !== null) finish(own, target, drift, child.stderr);
            }, error => {
                if (running === own) running = null;
                finish(own, target, { kind: "failed", cause: "thrown=" + (error.code || error.message) });
            });
    }

    // Publish a reading for the selection it ran for alone, its kind
    // alone, log one keyed line for a non-answer, and count it toward the
    // daily one.
    function finish(own, target, drift, stderr = "") {
        if (closed || own.selection !== selection) return;
        if (NON_ANSWERS.includes(drift.kind))
            log("jarvis: drift=" + drift.kind + " cause=" + drift.cause + " stderr="
                + JSON.stringify((stderr.split("\n").find(line => line.trim() !== "") ?? "").slice(0, STDERR_CHARS)));
        finished = clock.wallNow();
        try { store(finished); }
        catch (error) { log("jarvis: drift=record-unsaved cause=" + (error.code || error.message)); }
        publish(target, { kind: drift.kind });
        schedule();
    }

    return {
        select(next) {
            if (next === home) return;
            home = next;
            selection += 1;
            if (running !== null) running.controller.abort();
            running = null;
            publish(home, { kind: "none" });
            schedule();
        },
        request() { check(); },
        close() {
            closed = true;
            if (timer !== null) clock.clear(timer);
            timer = null;
            if (running !== null) running.controller.abort();
            running = null;
        }
    };
}

module.exports = { create, classify, KINDS, DAY_MS };
