#!/usr/bin/env node
// The package drift reading of the selected Jarvis home (backend/Drift.js,
// D126): each report kendex's check prints becomes one reading, and the
// owner reads the selected home once a day or when asked, drops a result
// for a home no longer selected and starts nothing else. The reports keep
// the shape kendex serializes, CheckReport and Line in
// crates/core/src/drift/report.rs and the exit codes of CheckStatus, at
// kendex 6c00d3e19; the unevaluated report is the one
// crates/cli/tests/cli.rs check_reports_an_unevaluated_package_as_drift
// reads. No kendex runs: run is a fake that answers each call.
"use strict";
const { assert, path, tree, world, mutant } = require("./fixtures/jarvis/policy.js");
const file = path.join(tree, "shell/plugins/vgs.jarvis/backend/Drift.js");
const Drift = require(file);
const Protocol = require(path.join(tree, "bin/lib/qml-library.js")).load(path.join(tree, "shell/plugins/vgs.jarvis/JarvisProtocol.js"));

const line = (lineClass, remedy) => ({ class: lineClass, text: "a sentence VGS never reads", ...(remedy === undefined ? {} : { remedy }) });
const report = (status, lines) => JSON.stringify({ status, sections: [{ title: "a title", lines }], snapshotAgeSecs: 30 }, null, 2);
const exited = (code, stdout) => ({ kind: "exited", code, signal: null, stdout, stderr: "" });
const refresh = { verb: "refresh", global: false };

// Each child result and the reading it is, one row per contract case.
const READINGS = [
    ["a clean report is current", exited(0, report("clean", [])), "current"],
    ["notices alone are current", exited(0, report("clean", [line("notice")])), "current"],
    ["a project refresh remedy is behind", exited(1, report("drift", [line("drift", refresh)])), "behind"],
    ["another package's refresh is behind too", exited(1, report("drift", [line("drift", { verb: "apply", global: false }), line("drift", refresh)])), "behind"],
    ["a refresh with an unknown part still offers it", exited(2, report("unknown", [line("unknown"), line("drift", refresh)])), "behind"],
    ["a global refresh is no update of the home", exited(1, report("drift", [line("drift", { verb: "refresh", global: true })])), "drift"],
    ["a change with another remedy is drift", exited(1, report("drift", [line("drift", { verb: "replace-unmanaged", global: false, allowRepoEffects: false })])), "drift"],
    ["an unevaluated comparison is pending", exited(1, report("drift", [line("unevaluated", { verb: "updates", global: false })])), "pending"],
    ["an unevaluated refresh is a comparison owed", exited(1, report("drift", [line("unevaluated", refresh)])), "pending"],
    ["a settling comparison is pending", exited(1, report("drift", [line("settling")])), "pending"],
    ["an unreadable part is unknown", exited(2, report("unknown", [line("unknown")])), "unknown"],
    ["a status that disagrees with the exit is malformed", exited(0, report("drift", [line("drift", refresh)])), "malformed"],
    ["prose is malformed", exited(1, "source comparison needed: 1\n"), "malformed"],
    ["a line of another class is malformed", exited(1, report("drift", [line("stale")])), "malformed"],
    ["a remedy with no verb is malformed", exited(1, report("drift", [line("drift", { global: false })])), "malformed"],
    ["an exit 2 with no report could not check", exited(2, ""), "failed"],
    ["another exit failed", exited(3, report("clean", [])), "failed"],
    ["a signal failed", { kind: "exited", code: null, signal: "SIGKILL", stdout: "", stderr: "" }, "failed"],
    ["a run past its bound timed out", { kind: "stopped", reason: "timeout", stdout: "", stderr: "" }, "timeout"],
    ["a run past its output bound is malformed", { kind: "stopped", reason: "output-limit", stdout: "", stderr: "" }, "malformed"],
    ["a run that never started failed", { kind: "error", reason: "spawn", error: "ENOENT", stdout: "", stderr: "" }, "failed"]
];

function readings(logic) {
    for (const [name, child, kind] of READINGS) assert.equal(logic.classify(child)?.kind, kind, name);
    assert.equal(logic.classify({ kind: "stopped", reason: "cancelled", stdout: "", stderr: "" }), null, "a cancelled run answers nothing");
    for (const [, child] of READINGS) assert.ok(logic.KINDS.includes(logic.classify(child).kind));
    // The wire carries every reading the owner publishes, and no other.
    assert.deepEqual([...Protocol.HOME_DRIFT], [...logic.KINDS], "the home-drift message's kinds are the owner's");
}

// An owner over a fake run, a hand-driven clock and a record in memory.
function owner(logic, { kendex = "/usr/bin/kendex", last = null, unsaved = false } = {}) {
    const calls = [], published = [], readings = [], timers = new Map(), logs = [];
    let now = 1_000_000, next = 0, stored = last;
    const drift = logic.create({
        run: (fileName, argv, options) => new Promise(resolve => calls.push({ file: fileName, argv, options, resolve })),
        kendex: () => kendex,
        environment: { PATH: "/usr/bin", HOME: "/home/u", OPENAI_API_KEY: "synthetic-key", XDG_STATE_HOME: "/home/u/.state" },
        clock: { wallNow: () => now, set: (fn, ms) => { timers.set(++next, { fn, at: now + ms }); return next; }, clear: id => timers.delete(id) },
        load: () => stored,
        store: at => {
            if (unsaved) throw Object.assign(new Error("planted"), { code: "ENOSPC" });
            stored = at;
        },
        publish: (home, reading) => { published.push([home, reading.kind]); readings.push(reading); }, log: entry => logs.push(entry)
    });
    const settle = () => new Promise(resolve => setImmediate(resolve));
    // Run every timer due by TIME, in order.
    const advance = async time => {
        now = time;
        for (const [id, timer] of [...timers].sort((a, b) => a[1].at - b[1].at))
            if (timer.at <= now) { timers.delete(id); timer.fn(); }
        await settle();
    };
    return { drift, calls, published, readings, timers, logs, settle, advance, now: () => now, stored: () => stored };
}

async function lifetime(logic) {
    {
        // The first selection ever reads the home at once, in the home, with
        // the report-only check and no credential; its answer is published
        // for that home and counts toward the daily reading.
        const t = owner(logic);
        t.drift.select("/home/u/Jarvis");
        await t.advance(t.now());
        assert.equal(t.calls.length, 1, "the first selection reads the home");
        const [call] = t.calls;
        assert.deepEqual(call.argv, ["--pdeathsig", "KILL", "--", "/usr/bin/kendex", "check", "--scope", "project", "--report-only", "--json"]);
        assert.equal(call.file, "setpriv");
        assert.equal(call.options.cwd, "/home/u/Jarvis");
        assert.equal(call.options.env.OPENAI_API_KEY, undefined, "no credential reaches kendex");
        assert.ok(Number.isInteger(call.options.deadline) && call.options.group === true, "the check is bounded and its group ends with it");
        call.resolve(exited(1, report("drift", [line("drift", refresh)])));
        await t.settle();
        assert.deepEqual(t.published, [["/home/u/Jarvis", "none"], ["/home/u/Jarvis", "checking"], ["/home/u/Jarvis", "behind"]]);
        assert.equal(t.stored(), t.now(), "the finished reading is recorded");
        // A request while none runs reads again; one while a reading runs
        // joins it.
        t.drift.request();
        t.drift.request();
        await t.settle();
        assert.equal(t.calls.length, 2, "a request reads once, however often it is asked");
        t.calls[1].resolve(exited(0, report("clean", [])));
        await t.settle();
        assert.equal(t.published.at(-1)[1], "current");
        // The next daily reading waits a day from the last one.
        await t.advance(t.now() + logic.DAY_MS - 1);
        assert.equal(t.calls.length, 2, "no reading before a day has passed");
        await t.advance(t.now() + 1);
        assert.equal(t.calls.length, 3, "the daily reading runs once a day has passed");
        t.calls[2].resolve(exited(1, report("drift", [line("settling")])));
        await t.settle();
        assert.equal(t.published.at(-1)[1], "pending");
        t.drift.close();
    }
    {
        // A result for a home no longer selected is dropped: the new home
        // reads its own, and the old result never reaches it.
        const t = owner(logic, { last: 1_000_000 });
        t.drift.select("/home/u/Old");
        t.drift.request();
        await t.settle();
        assert.equal(t.calls.length, 1);
        const old = t.calls[0];
        t.drift.select("/home/u/New");
        assert.equal(old.options.signal.aborted, true, "a new selection ends the old reading");
        t.drift.request();
        await t.settle();
        old.resolve(exited(1, report("drift", [line("drift", refresh)])));
        await t.settle();
        assert.deepEqual(t.published.filter(([home]) => home === "/home/u/New").map(([, kind]) => kind), ["none", "checking"],
            "the old home's late result reaches no reading of the new one");
        assert.equal(t.published.some(([home, kind]) => home === "/home/u/Old" && kind === "behind"), false, "nor its own");
        t.calls[1].resolve(exited(0, report("clean", [])));
        await t.settle();
        assert.deepEqual(t.published.at(-1), ["/home/u/New", "current"]);
        // No home: nothing runs and the reading says none.
        t.drift.select(null);
        t.drift.request();
        await t.advance(t.now() + 2 * logic.DAY_MS);
        assert.equal(t.calls.length, 2, "no home is never read");
        assert.deepEqual(t.published.at(-1), [null, "none"]);
        t.drift.close();
    }
    {
        // A time record that cannot be stored never brings the next reading
        // forward: the daily one still waits a day from the last.
        const t = owner(logic, { unsaved: true });
        t.drift.select("/home/u/Jarvis");
        await t.advance(t.now());
        t.calls[0].resolve(exited(0, report("clean", [])));
        await t.settle();
        assert.deepEqual(t.published.at(-1), ["/home/u/Jarvis", "current"]);
        assert.ok(t.logs.some(line => line === "jarvis: drift=record-unsaved cause=ENOSPC"), t.logs.join("\n"));
        assert.deepEqual([...t.timers.values()].map(timer => timer.at - t.now()), [logic.DAY_MS], "the next reading waits a day");
        await t.advance(t.now() + logic.DAY_MS - 1);
        assert.equal(t.calls.length, 1, "no reading runs before the day has passed");
        t.drift.close();
    }
    {
        // A non-answer logs one keyed line with kendex's first stderr line
        // and publishes its kind alone.
        const t = owner(logic, { last: 1_000_000 });
        t.drift.select("/home/u/Jarvis");
        t.drift.request();
        await t.settle();
        t.calls[0].resolve({ ...exited(1, "not a report"), stderr: "\nError: the report was cut\nsecond line\n" });
        await t.settle();
        assert.deepEqual(t.readings.at(-1), { kind: "malformed" }, "the cause is never published");
        assert.deepEqual(t.logs, ["jarvis: drift=malformed cause=exit=1 stderr=\"Error: the report was cut\""]);
        t.drift.close();
    }
    {
        // kendex missing reads as such, runs nothing, installs nothing and
        // logs nothing: the daemon's stderr carries no line for a world
        // without kendex.
        const t = owner(logic, { kendex: null });
        t.drift.select("/home/u/Jarvis");
        await t.advance(t.now());
        assert.equal(t.calls.length, 0);
        assert.deepEqual(t.published.at(-1), ["/home/u/Jarvis", "kendex-missing"]);
        assert.deepEqual(t.logs, []);
        t.drift.close();
    }
    {
        // A reading published after close, or a check started by it, is none.
        const t = owner(logic, { last: 1_000_000 });
        t.drift.select("/home/u/Jarvis");
        t.drift.request();
        await t.settle();
        t.drift.close();
        assert.equal(t.calls[0].options.signal.aborted, true);
        t.calls[0].resolve(exited(0, report("clean", [])));
        await t.settle();
        assert.equal(t.published.at(-1)[1], "checking", "a closed owner publishes no late reading");
        assert.equal(t.timers.size, 0);
    }
}

world(async () => {
    readings(Drift);
    await lifetime(Drift);
    let controls = 0;
    const fails = async check => {
        await mutant(file, check.name, check.needle, check.replacement, logic => check.run(logic));
        controls++;
    };
    await fails({ name: "refresh-remedy", needle: 'line.class === "drift" && line.remedy?.verb === "refresh" && line.remedy.global === false',
        replacement: 'line.remedy?.verb === "refresh"', run: readings });
    await fails({ name: "unknown-not-current", needle: 'if (read.status === "unknown" || classes.includes("unknown")) return { kind: "unknown" };',
        replacement: "", run: readings });
    await fails({ name: "exit-status", needle: "STATUS_EXIT[report.status] !== code", replacement: "false", run: readings });
    await fails({ name: "late-result", needle: "if (closed || own.selection !== selection) return;", replacement: "if (closed) return;",
        run: logic => lifetime(logic) });
    await fails({ name: "unsaved-time", needle: "const times = [load(), finished]", replacement: "const times = [load()]", run: logic => lifetime(logic) });
    await fails({ name: "non-answer-log", needle: "        if (NON_ANSWERS.includes(drift.kind))\n", replacement: "        if (false)\n", run: logic => lifetime(logic) });
    await fails({ name: "daily-interval", needle: "Math.max(...times) + DAY_MS - clock.wallNow()", replacement: "0", run: logic => lifetime(logic) });
    console.log("jarvis-drift: readings=" + READINGS.length + " controls=" + controls);
});
