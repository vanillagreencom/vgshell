#!/usr/bin/env node
// The satellite owner against the package stand-in, through the production
// child owner, in the J09 scratch world. No SSH call and no live session.
"use strict";
const { assert, fs, path, tree, world, mutant } = require("./fixtures/jarvis/policy.js");
const cp = require("node:child_process");
const { load } = require("../bin/lib/qml-library.js");
const backend = path.join(tree, "shell/plugins/vgs.jarvis/backend");
const satelliteFile = path.join(backend, "Satellite.js");
const fixture = path.join(tree, "scripts/fixtures/jarvis/satellite-package.py");
// The installed Jarvis package's own record judge, the contract a forward
// record must pass (forward.py checked_record).
const packageLib = path.join(tree, ".agents/skills/jarvis/scripts/lib");

world(async () => {
    const Protocol = load(path.join(tree, "shell/plugins/vgs.jarvis/JarvisProtocol.js"));
    const ComputerHelp = require(path.join(backend, "ComputerHelp.js"));
    let controls = 0;

    function home() {
        const folder = fs.mkdtempSync(path.join(process.env.HOME, "satellite-home-"));
        const scripts = path.join(folder, ".agents/skills/jarvis/scripts");
        fs.mkdirSync(scripts, { recursive: true });
        fs.copyFileSync(fixture, path.join(scripts, "jarvis-session"));
        fs.chmodSync(path.join(scripts, "jarvis-session"), 0o755);
        return { folder,
            state: value => fs.writeFileSync(path.join(scripts, "satellite.json"), JSON.stringify(value)),
            calls: () => fs.existsSync(path.join(scripts, "calls.log"))
                ? fs.readFileSync(path.join(scripts, "calls.log"), "utf8").trim().split("\n").map(line => JSON.parse(line)) : [] };
    }

    async function until(check, label) {
        for (let n = 0; !check(); n++) {
            assert.ok(n < 2000, label);
            await new Promise(resolve => setTimeout(resolve, 5));
        }
    }

    // What `status --main` answers, as the Now line reads it, for the
    // setting "cachy"; every reading passes the wire's judge.
    function readings(Satellite) {
        const satellite = { v: 1, role: "satellite", main: "cachy", reachable: true, cause: null };
        for (const [label, answer, reach] of [
            ["reached", satellite, { kind: "satellite", host: "cachy", reachable: true, cause: "" }],
            ["unanswered", { ...satellite, reachable: false, cause: "main-unreachable" }, { kind: "satellite", host: "cachy", reachable: false, cause: "main-unreachable" }],
            ["not yet contacted", { ...satellite, reachable: null }, { kind: "satellite", host: "cachy", reachable: null, cause: "" }],
            ["unparsed setting", { ...satellite, main: null, reachable: null, cause: "setting-invalid" }, { kind: "satellite", host: "", reachable: null, cause: "setting-invalid" }],
            ["setting not taken", { v: 1, role: "main" }, { kind: "unavailable", cause: "package" }],
            ["another main", { ...satellite, main: "other" }, { kind: "unavailable", cause: "package" }],
            ["no answer", null, { kind: "unavailable", cause: "package" }]
        ]) {
            assert.deepEqual(Satellite.reading(answer, "cachy"), reach, label);
            assert.equal(Protocol.mainReach(reach), true, label + ": the wire takes it");
        }
        assert.deepEqual(Satellite.reading(satellite, "cachy:/srv/jarvis"), { kind: "satellite", host: "cachy", reachable: true, cause: "" },
            "a setting with the main's own path names the same host");
        for (const [value, setting] of [["", ""], ["cachy", "cachy:/home/me/jarvis"], ["me@cachy:/srv/jarvis", "me@cachy:/srv/jarvis"]])
            assert.equal(Satellite.settingOf(value, "/home/me/jarvis"), setting, value);
    }

    async function live(Satellite) {
        const h = home();
        let value = "", folder = h.folder;
        const published = [], logs = [], timers = [];
        const s = Satellite.create({ home: () => folder, mainHost: () => value, environment: process.env,
            publish: reach => published.push(reach), log: line => logs.push(line),
            clock: { set: (fn, ms) => { timers.push(ms); return {}; }, clear() {} } });
        try {
            s.refresh();
            await until(() => published.length === 1, "an empty setting reads as this computer");
            assert.deepEqual(published[0], { kind: "main" });
            assert.deepEqual(h.calls(), [], "this computer reads nothing from the package");
            assert.deepEqual(timers, [], "and keeps no timer");

            value = "cachy";
            await s.choose("cachy", h.folder);
            await until(() => published.length === 2, "a choice reads the main again");
            assert.deepEqual(h.calls().map(call => call.argv), [
                ["main-host", "--set=cachy:" + h.folder, "--home", h.folder],
                ["status", "--main", "--home", h.folder]], "the choice goes to the package's setting, then the read");
            assert.deepEqual(published[1], { kind: "satellite", host: "cachy", reachable: null, cause: "" });
            assert.equal(s.executor.available(), true, "a satellite offers the forward");
            assert.deepEqual(timers, [Satellite.READ_EVERY_MS], "a named main is read again on the drain's interval");

            h.state({ main: "cachy:" + h.folder, reachable: false });
            s.refresh();
            await until(() => published.length === 3, "an unanswered main reads again");
            assert.deepEqual(published[2], { kind: "satellite", host: "cachy", reachable: false, cause: "main-unreachable" });

            const forward = (text, caller) => new Promise(resolve =>
                s.executor.start({ id: "fleet.forward", args: { text } }, resolve, () => ({ kind: "allow" }), undefined, caller));
            const caller = { ref: "vgs-audit:2026-11-03T08:10:36.642Z#7:3", at: "2026-11-03T08:10:36.642Z", method: "voice", spoken: true, gen: 7 };
            const forwards = () => h.calls().filter(call => call.argv[0] === "forward");
            assert.equal((await forward("Rebase the lanes.", caller)).outcome, "completed");
            const spoken = forwards().at(-1);
            assert.deepEqual(spoken.record, { v: 1,
                request: { ref: caller.ref, at: caller.at,
                    text: "voice-request: caller=owner operation=" + caller.ref + " conversation=jarvis-7 provenance=vgs-talk\nRebase the lanes." },
                confirmation: { ref: caller.ref, at: caller.at, method: "voice" } }, "a Talk request opens with the owner's voice-request line");
            assert.equal(fs.existsSync(spoken.argv[spoken.argv.indexOf("--record") + 1]), false, "the record is removed after the run");
            const checked = path.join(process.env.JARVIS_TEST_ROOT, "record.json");
            fs.writeFileSync(checked, JSON.stringify(spoken.record));
            const judged = cp.spawnSync("python3", ["-c", "import sys; sys.path.insert(0, sys.argv[1]); import forward; forward.checked_record(sys.argv[2])",
                packageLib, checked], { encoding: "utf8", env: { PATH: process.env.PATH, LANG: "C.UTF-8" } });
            assert.equal(judged.status, 0, "the package's record judge takes the record: " + judged.stderr);

            assert.equal((await forward("Rebase the lanes.", { ...caller, method: "physical", spoken: false })).outcome, "completed");
            assert.equal(forwards().at(-1).record.request.text, "Rebase the lanes.", "a typed request carries no voice-request line");
            assert.equal(JSON.stringify(forwards().at(-1).record).includes("caller=owner"), false);

            const before = forwards().length;
            assert.deepEqual(await forward("Rebase.", { ...caller, method: "none" }), { outcome: "failed", content: "fleet-forward:unconfirmed" });
            assert.deepEqual(await forward("Use sk-ant-abcdefghijklmnopqrstuv now.", caller), { outcome: "failed", content: "fleet-forward:secret" });
            assert.equal(forwards().length, before, "an unconfirmed or secret request never reaches the package");

            h.state({ main: "cachy:" + h.folder, forward: { exit: 75, cause: "main-unreachable" } });
            const queued = await forward("Queued.", caller);
            assert.deepEqual([queued.outcome, queued.content.includes("main-unreachable")], ["completed", true], "a queued forward names its cause");
            h.state({ main: "cachy:" + h.folder, forward: { exit: 2, cause: "request-conflict" } });
            assert.deepEqual(await forward("Refused.", caller), { outcome: "failed", content: "fleet-forward:request-conflict" });

            value = "not a host";
            await s.choose(value, h.folder);
            await until(() => published.at(-1).cause === "setting-invalid", "the package judges the setting");
            assert.equal(s.executor.available(), false, "an unparsed setting offers no forward");

            h.state({ package: "old" });
            value = "cachy";
            const count = published.length;
            await s.choose(value, h.folder);
            await until(() => published.length > count, "an older package reads again");
            assert.deepEqual(published.at(-1), { kind: "unavailable", cause: "package" });
            assert.ok(logs.includes("jarvis: satellite=main-host cause=package-old"), logs.join("\n"));
            assert.equal(s.executor.available(), false);
            assert.deepEqual(await forward("Old.", caller), { outcome: "failed", content: "fleet-forward:package-old" });

            folder = null;
            s.refresh();
            await until(() => published.at(-1).cause === "home", "no home reads unavailable");
        } finally { await s.close(); }
    }

    readings(require(satelliteFile));
    console.log("case=readings passed");
    await live(require(satelliteFile));
    console.log("case=live passed");
    const help = ComputerHelp.create(undefined, null, () => process.env.HOME, {}, () => false);
    assert.equal(help.fleet(), false, "a satellite offers no fleet.request");
    console.log("case=fleet-request-satellite passed");

    for (const [name, needle, replacement, check] of [
        ["typed-voice-line", "    if (caller.spoken !== true) return text;\n", "", live],
        ["unconfirmed", 'if (caller === undefined || !["voice", "physical"].includes(caller.method)) return failed("unconfirmed");', "", live],
        ["secret", 'if (Redact.secret(call.args.text)) return failed("secret");', "", live],
        ["host-mismatch", ' || answer.main !== hostOf(value)', "", readings],
        ["main-unread", 'if (value === "") return { kind: "main" };', "", live]
    ]) {
        await mutant(satelliteFile, name, needle, replacement, check, "Satellite.js");
        controls++; console.log("control=" + name + " detected");
    }
    console.log("test-jarvis-satellite: ok controls=" + controls);
});
