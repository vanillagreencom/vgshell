#!/usr/bin/env node
// The desktop executors against a stand-in hyprctl and a fake shell side,
// inside J09. Synthetic state from scripts/fixtures/jarvis/desktop.js,
// 2026-10-01. No live Hyprland, dispatch, application or network is reached.
"use strict";
const { assert, fs, path, tree, world, mutant } = require("./fixtures/jarvis/policy.js");
const { standins, desktopWorld, client } = require("./fixtures/jarvis/desktop.js");
const { load } = require("../bin/lib/qml-library.js");
const backend = path.join(tree, "shell/plugins/vgs.jarvis/backend");
const file = path.join(backend, "DesktopSession.js");

world(async () => {
    const Protocol = load(path.join(tree, "shell/plugins/vgs.jarvis/JarvisProtocol.js"));
    const Dispatch = load(path.join(tree, "shell/Core/Dispatch.js"));
    const Launch = load(path.join(tree, "shell/Commons/DesktopLaunch.js"));
    const Tools = require(path.join(backend, "Tools.js"));
    const ShellRequests = require(path.join(backend, "ShellRequests.js"));
    const runtime = process.env.XDG_RUNTIME_DIR;
    const entries = [
        { id: "fixture.editor", name: "Editor", startupClass: "Fixture.Editor", noDisplay: false, command: ["fixture-editor", "--new"], terminal: false },
        { id: "fixture.tool", name: "Tool", startupClass: "", noDisplay: false, command: ["fixture-tool"], terminal: true },
        { id: "fixture.hidden", name: "Hidden", startupClass: "", noDisplay: true, command: ["fixture-hidden"], terminal: false }
    ];
    const desk = desktopWorld(runtime, entries, Launch);
    const clock = { now: () => performance.now(), set: (fn, ms) => setTimeout(fn, ms), clear: timer => clearTimeout(timer) };
    // Small real bounds keep the suite short; production's are in DesktopSession.js.
    const bounds = { hyprctlMs: 3000, hyprctlBytes: 1024 * 1024, requestMs: 250, settleMs: 300, launchMs: 400, pollMs: 20, slackMs: 1000 };
    // The longest paths, near their bounds: each stand-in read sleeps 1 s
    // under a 1.3 s hyprctl bound, and each reply waits 1.05 s under a 1.2 s
    // request bound. A settle bound shorter than one read takes one read.
    // The margins leave room for a loaded host's process start and timers.
    const slow = d => {
        d.delay(1.0);
        d.replyMs = 1050;
        return { ...bounds, hyprctlMs: 1300, requestMs: 1200, settleMs: 100, launchMs: 100, slackMs: 50 };
    };
    const environment = { PATH: process.env.PATH, XDG_RUNTIME_DIR: runtime, LANG: "C.UTF-8" };
    // The monitors and workspaces of px13 on Hyprland 0.57.0 (recorded) and in the
    // shape 0.56.2 writes: scripts/fixtures/capture/hyprland-workspaces.json (VGS-2110).
    const layouts = JSON.parse(fs.readFileSync(path.join(tree, "scripts/fixtures/capture/hyprland-workspaces.json"), "utf8"));
    const withLayout = (version, change = () => {}) => d => {
        const s = d.read(), layout = structuredClone(layouts[version]);
        s.monitors = layout.monitors;
        s.workspaces = layout.workspaces;
        change(s, d);
        d.write(s);
    };
    const exact = lines => new RegExp("^" + lines.join("\n").replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "$");
    const numbered = n => "workspace id=" + n + " name=\"" + n + "\" monitor=eDP-1 windows=" + (n === 4 ? 2 : 1) + (n === 3 ? " shown focused" : "");
    const special = (name, ref, shown = "") => "workspace " + ref + " name=\"special:" + name + "\" monitor=eDP-1 windows=1" + shown;

    function make(Desktop = require(file), commands = ["gio"], timing = bounds) {
        const requests = ShellRequests.create({ Protocol, clock, write: fields => {
            const message = Protocol.accept(JSON.stringify({ v: 1, type: "request", gen: 0, revision: "a".repeat(64), ...fields }), "daemon");
            setTimeout(() => {
                const reply = desk.serve(Protocol, message);
                if (reply !== null) requests.reply(Protocol.accept(JSON.stringify(reply), "shell"));
            }, desk.replyMs);
        } });
        const desktop = Desktop.create({ Dispatch, Launch, request: requests.send, clock, bounds: timing, commands, environment });
        // The router hands an executor Tools' frozen snapshot, never the model's object.
        const run = (id, args = {}) => new Promise(resolve => {
            const refined = Tools.refine({ id, args });
            assert.equal(refined.kind, "call", id + " refines");
            desktop.records[refined.executor].start(refined.call, resolve);
        });
        return { desktop, run };
    }
    const realPoll = () => new Promise(resolve => setTimeout(resolve, 10));
    const eventLoopPoll = () => new Promise(resolve => setImmediate(resolve));
    async function waitUntil(label, predicate, tick = realPoll) {
        for (let wait = 0; ; wait++) {
            if (predicate()) return;
            assert.ok(wait < 500, label);
            await tick();
        }
    }
    function manualClock() {
        let now = 0;
        const timers = [];
        return {
            now: () => now,
            set(fn, ms) {
                const timer = { fn, time: now + ms, cleared: false };
                timers.push(timer);
                return timer;
            },
            clear(timer) { timer.cleared = true; },
            pending: () => timers.some(timer => !timer.cleared),
            advance(ms) {
                now += ms;
                for (const timer of timers.filter(t => !t.cleared && t.time <= now)) {
                    timer.cleared = true;
                    timer.fn();
                }
            }
        };
    }
    const hyprctlStarts = path.join(runtime, "hyprctl.start");
    const startPids = () => fs.existsSync(hyprctlStarts) ? fs.readFileSync(hyprctlStarts, "utf8").trim().split("\n").filter(Boolean) : [];
    const resetStartPids = () => fs.rmSync(hyprctlStarts, { force: true });
    const pidGone = pid => !fs.existsSync(path.join("/proc", pid));
    const activeStartedHyprctlPids = () => new Set(process._getActiveHandles()
        .filter(handle => handle.constructor.name === "ChildProcess" && startPids().includes(String(handle.pid)))
        .map(handle => String(handle.pid)));
    const allStartedHyprctlDelivered = () => {
        const pids = startPids();
        return pids.length > 0 && pids.every(pidGone) && activeStartedHyprctlPids().size === 0;
    };

    const addressOf = (s, title) => s.clients.find(c => c.title === title).address;
    // name, tool, args, setup, outcome, content, check. Each starts from the
    // fixture's initial state: 0xa1 floating, 0xb2 tiled and focused, FIX-1
    // focused showing workspace 1, FIX-2 showing workspace 2.
    const cases = [
        ["focus", "windows.focus", { window: "0xA1" }, null, "completed", /window 0xa1 has the focus/],
        ["focus-noop", "windows.focus", { window: "0xa1" }, d => { d.modes["compositor.focusWindow"] = "noop"; }, "failed", /did not show the change.*0xb2 has the focus/],
        ["focus-refused", "windows.focus", { window: "0xa1" }, d => { d.modes["compositor.focusWindow"] = "refuse"; }, "failed", /refused compositor\.focusWindow: refused: fixture/],
        ["focus-silent", "windows.focus", { window: "0xa1" }, d => { d.modes["compositor.focusWindow"] = "silent"; }, "unknown", /did not answer compositor\.focusWindow/],
        ["focus-unread", "windows.focus", { window: "0xa1" }, d => { d.modes["compositor.focusWindow"] = "unread"; }, "unknown", /requested\. Hyprland state could not be read/],
        ["focus-locked", "windows.focus", { window: "0xa1" }, d => { d.locked = true; }, "failed", /refused compositor\.focusWindow: refused: locked/],
        ["focus-absent", "windows.focus", { window: "0xdead" }, null, "failed", /Window 0xdead is not open/, d => assert.deepEqual(d.requests, [])],
        // A class names the window of that class the user focused last
        // (lowest focusHistoryID), by its class or initial class, in any case.
        ["focus-class", "windows.focus", { window: "class:Fixture.App" }, null, "completed", /window 0xa1 has the focus/,
            d => assert.deepEqual(d.requests, [{ kind: "compositor.focusWindow", args: ["0xa1"] }])],
        ["focus-class-last", "windows.focus", { window: "class:fixture.app" }, d => {
            const s = d.read(); s.clients[0].focusHistoryID = 2; s.active = "0xa1"; d.write(s);
        }, "completed", /window 0xb2 has the focus/],
        ["focus-initial-class", "windows.focus", { window: "class:fixture.first" }, d => {
            const s = d.read(); s.clients[0].initialClass = "Fixture.First"; s.clients[0].focusHistoryID = 2; d.write(s);
        }, "completed", /window 0xa1 has the focus/],
        ["focus-class-absent", "windows.focus", { window: "class:fixture.none" }, null, "failed", /No window of class "fixture\.none" is open/,
            d => assert.deepEqual(d.requests, [])],
        ["close-active", "windows.close", { window: "active" }, null, "completed", /0xb2 is closed/,
            d => assert.deepEqual(d.requests, [{ kind: "compositor.closeWindow", args: ["0xb2"] }])],
        ["fullscreen-active", "windows.fullscreen", { window: "active", mode: "fullscreen", action: "set" }, null, "completed", /0xb2 fullscreen=2/],
        ["active-none", "windows.close", { window: "active" }, d => { const s = d.read(); s.active = ""; d.write(s); },
            "failed", /No window has the focus/, d => assert.deepEqual(d.requests, [])],
        ["reveal", "windows.reveal", { window: "0xa1" }, null, "completed", /0xa1 has the focus/],
        ["reveal-noop", "windows.reveal", { window: "0xa1" }, d => { d.modes["compositor.reveal"] = "noop"; }, "failed", /did not show/],
        ["move", "windows.move", { window: "0xa1", x: 140, y: 130 }, null, "completed", /at=\[140,130\]/],
        ["move-tiled", "windows.move", { window: "0xb2", x: 140, y: 130 }, null, "failed", /at=\[0,0\] floating=false/],
        ["resize", "windows.resize", { window: "0xa1", width: 460, height: 310 }, null, "completed", /size=\[460,310\]/],
        ["resize-noop", "windows.resize", { window: "0xa1", width: 460, height: 310 }, d => { d.modes["compositor.resizeWindow"] = "noop"; }, "failed", /size=\[400,300\]/],
        ["close", "windows.close", { window: "0xa1" }, null, "completed", /0xa1 is closed/],
        ["close-kept", "windows.close", { window: "0xa1" }, d => { d.modes["compositor.closeWindow"] = "noop"; }, "unknown", /0xa1 is still open/],
        ["fullscreen", "windows.fullscreen", { window: "0xa1", mode: "fullscreen", action: "set" }, null, "completed", /fullscreen=2/, d => {
            assert.deepEqual(d.requests.map(r => r.kind), ["compositor.focusWindow", "compositor.fullscreenWindow"]);
            assert.equal(d.read().clients.find(c => c.address === "0xb2").fullscreen, 0, "only the target changes");
        }],
        ["maximize-toggle", "windows.fullscreen", { window: "0xa1", mode: "maximized", action: "toggle" }, null, "completed", /fullscreen=1/],
        ["fullscreen-noop", "windows.fullscreen", { window: "0xa1", mode: "fullscreen", action: "toggle" }, d => { d.modes["compositor.fullscreenWindow"] = "noop"; }, "failed", /fullscreen=0/],
        ["fullscreen-slowest", "windows.fullscreen", { window: "0xa1", mode: "fullscreen", action: "set" }, d => {
            d.modes["compositor.fullscreenWindow"] = "noop";
            return slow(d);
        }, "failed", /accepted compositor\.fullscreenWindow/],
        ["fullscreen-unfocused", "windows.fullscreen", { window: "0xa1", mode: "fullscreen", action: "set" }, d => { d.modes["compositor.focusWindow"] = "noop"; }, "failed", /accepted compositor\.focusWindow/,
            d => assert.deepEqual(d.requests.map(r => r.kind), ["compositor.focusWindow"], "no fullscreen for an unfocused target")],
        ["float-toggle", "windows.float", { window: "0xa1", action: "toggle" }, null, "completed", /floating=false/],
        ["float-toggle-noop", "windows.float", { window: "0xa1", action: "toggle" }, d => { d.modes["compositor.floatWindow"] = "noop"; }, "failed", /floating=true/],
        ["float-set-kept", "windows.float", { window: "0xa1", action: "set" }, d => { d.modes["compositor.floatWindow"] = "noop"; }, "completed", /floating=true/],
        ["to-workspace", "windows.workspace", { window: "0xa1", workspace: 3 }, null, "completed", /workspace="3"/],
        ["to-workspace-noop", "windows.workspace", { window: "0xa1", workspace: 3 }, d => { d.modes["compositor.moveWindowToWorkspace"] = "noop"; }, "failed", /workspace="1"/],
        ["workspace", "workspaces.focus", { workspace: 4 }, null, "completed", /workspace 4 is shown/],
        ["workspace-noop", "workspaces.focus", { workspace: 4 }, d => { d.modes["compositor.focusWorkspace"] = "noop"; }, "failed", /workspace 1 is shown/],
        ["special-show", "workspaces.special", { name: "magic" }, null, "completed", /special:magic is shown/],
        ["special-hide", "workspaces.special", { name: "magic" }, d => {
            const s = d.read(); s.monitors[0].specialWorkspace = { id: -98, name: "special:magic" }; d.write(s);
        }, "completed", /no special workspace is shown/],
        ["special-noop", "workspaces.special", { name: "magic" }, d => { d.modes["compositor.toggleSpecialWorkspace"] = "noop"; }, "failed", /no special workspace/],
        ["monitor", "windows.monitor", { monitor: "FIX-2" }, null, "completed", /monitor FIX-2 has the focus/],
        ["monitor-id", "windows.monitor", { monitor: "1" }, null, "completed", /monitor FIX-2 has the focus/,
            d => assert.deepEqual(d.requests, [{ kind: "compositor.focusMonitor", args: ["FIX-2"] }])],
        ["monitor-unknown", "windows.monitor", { monitor: "desc:Nope" }, null, "failed", /No monitor is named "desc:Nope"/, d => assert.deepEqual(d.requests, [])],
        ["monitor-noop", "windows.monitor", { monitor: "FIX-2" }, d => { d.modes["compositor.focusMonitor"] = "noop"; }, "failed", /monitor FIX-1 has the focus/],
        ["windows", "windows.list", {}, null, "completed", /^2 windows\n0xa1 workspace="1" monitor=FIX-1 class="fixture\.app" title="Target" floating\n0xb2 .*title="Other" focused$/],
        ["workspaces", "workspaces.list", {}, null, "completed", /^2 workspaces\nworkspace id=1 name="1" monitor=FIX-1 windows=2 shown focused\nworkspace id=2 name="2" monitor=FIX-2 windows=0 shown$/],
        // 0.57.0 writes an address and no id for a workspace without a number; the
        // numbered ones come first, the others by address. 0.56.2 gives each an id.
        ["workspaces-0.57.0", "workspaces.list", {}, withLayout("0.57.0"), "completed", exact(["11 workspaces",
            ...[1, 2, 3, 4].map(numbered),
            ...["chatgpt", "github", "linear", "macbook", "spotify", "term", "yazi"].map(name => special(name, "address=\"special:" + name + "\""))])],
        ["workspaces-0.57.0-special-shown", "workspaces.list", {}, withLayout("0.57.0", s => {
            s.monitors[0].specialWorkspace = { address: "special:term", type: "special", name: "special:term" };
        }), "completed", exact(["11 workspaces",
            ...[1, 2, 3, 4].map(numbered),
            ...["chatgpt", "github", "linear", "macbook", "spotify"].map(name => special(name, "address=\"special:" + name + "\"")),
            special("term", "address=\"special:term\"", " shown focused"), special("yazi", "address=\"special:yazi\"")])],
        ["workspaces-0.57.0-no-identity", "workspaces.list", {}, withLayout("0.57.0", s => {
            s.workspaces = [{ type: "normal", name: "ghost", monitor: "eDP-1", monitorID: 0, windows: 0 }];
        }), "completed", exact(["1 workspaces", "workspace address=\"\" name=\"ghost\" monitor=eDP-1 windows=0"])],
        ["workspaces-0.56.2", "workspaces.list", {}, withLayout("0.56.2"), "completed", exact(["11 workspaces",
            ...[["macbook", -104], ["linear", -103], ["chatgpt", -102], ["github", -101], ["spotify", -100], ["term", -99], ["yazi", -98]]
                .map(([name, id]) => special(name, "id=" + id)),
            ...[1, 2, 3, 4].map(numbered)])],
        ["workspaces-0.56.2-special-shown", "workspaces.list", {}, withLayout("0.56.2", s => {
            s.monitors[0].specialWorkspace = { id: -99, name: "special:term" };
        }), "completed", /workspace id=-99 name="special:term" monitor=eDP-1 windows=1 shown focused\nworkspace id=-98 name="special:yazi" monitor=eDP-1 windows=1\nworkspace id=1 /],
        ["workspace-named-0.57.0", "workspaces.focus", { workspace: 4 }, withLayout("0.57.0", (s, d) => {
            s.monitors[0].activeWorkspace = { address: "web", type: "normal", name: "web" };
            d.modes["compositor.focusWorkspace"] = "noop";
        }), "failed", /workspace "web" is shown on the focused monitor/],
        ["apps", "apps.list", {}, null, "completed", /^2 applications\nfixture\.editor name="Editor"\nfixture\.tool name="Tool"$/],
        ["apps-query", "apps.list", { query: "TOOL" }, null, "completed", /^1 applications\nfixture\.tool name="Tool"$/],
        ["launch", "apps.launch", { desktop: "fixture.editor.desktop" }, d => { d.launches["fixture-editor"] = { mode: "window", class: "fixture.editor" }; },
            "completed", /Started "Editor".*class="fixture\.editor"/,
            d => {
                assert.deepEqual(d.requests.at(-1), { kind: "desktop.launch", args: ["fixture.editor"] });
                assert.deepEqual(d.runs, [["fixture-editor", "--new"]]);
            }],
        ["launch-windowless", "apps.launch", { desktop: "fixture.editor" }, null, "unknown", /no window of it appeared.*no new window/],
        ["launch-slowest", "apps.launch", { desktop: "fixture.editor" }, slow, "unknown", /no window of it appeared/],
        ["launch-other-class", "apps.launch", { desktop: "fixture.editor" }, d => { d.launches["fixture-editor"] = { mode: "window", class: "other.app" }; },
            "unknown", /other classes: "other\.app"/],
        ["launch-terminal", "apps.launch", { desktop: "fixture.tool" }, d => { d.launches["fixture-tool"] = { mode: "window", class: "fixture.terminal" }; },
            "completed", /class="fixture\.terminal"/,
            d => assert.deepEqual(d.runs, [["xdg-terminal-exec", "fixture-tool"]])],
        ["terminal", "apps.terminal", {}, d => { d.launches["xdg-terminal-exec"] = { mode: "window", class: "fixture.terminal" }; },
            "completed", /Started a terminal\. Read back: new window .*class="fixture\.terminal"/,
            d => assert.deepEqual(d.requests.at(-1), { kind: "run.detached", args: ["xdg-terminal-exec"] })],
        ["terminal-windowless", "apps.terminal", {}, null, "unknown", /started a terminal, but no window/],
        ["launch-unknown", "apps.launch", { desktop: "fixture.absent" }, null, "failed", /refused desktop\.launch: refused: desktop=unknown/,
            d => assert.deepEqual(d.runs, [])],
        ["launch-locked", "apps.launch", { desktop: "fixture.editor" }, d => { d.locked = true; }, "failed", /refused desktop\.launch: refused: locked/,
            d => assert.deepEqual(d.runs, [])],
        ["launch-hidden", "apps.launch", { desktop: "fixture.hidden" }, null, "failed", /desktop=unknown/],
        ["open", "apps.open", { path: "/fixture/report.txt" }, d => { d.launches.gio = { mode: "window", class: "fixture.viewer" }; }, "completed", /class="fixture\.viewer"/,
            d => assert.deepEqual(d.requests.at(-1), { kind: "run.detached", args: ["gio", "open", "/fixture/report.txt"] })],
        ["open-windowless", "apps.open", { path: "/fixture/report.txt" }, null, "unknown", /existing window. Read back: no new window/],
        ["url", "apps.url", { url: "https://example.test/page" }, null, "unknown", /"https:\/\/example\.test\/page"/,
            d => assert.deepEqual(d.requests.at(-1), { kind: "run.detached", args: ["gio", "open", "https://example.test/page"] })],
        ["run-refused", "apps.url", { url: "https://example.test/" }, d => { d.modes["run.detached"] = "refuse"; }, "failed", /refused run\.detached/],
        // A request that changes nothing goes out while locked.
        ["list-locked", "apps.list", { query: "TOOL" }, d => { d.locked = true; }, "completed", /^1 applications\n/],
        ["launch-oversize", "apps.launch", { desktop: "x".repeat(5000) }, null, "failed", /could not be sent: jarvis: protocol=request-args/,
            d => assert.deepEqual(d.requests, [])]
    ];

    async function check(Desktop, row) {
        const [name, tool, args, setup, outcome, content, after] = row;
        desk.reset();
        const timing = setup === null ? undefined : setup(desk);
        const { desktop, run } = make(Desktop, ["gio"], timing || bounds);
        const started = performance.now();
        try {
            const answer = await run(tool, args);
            assert.equal(answer.outcome, outcome, name + ": " + answer.content);
            assert.match(answer.content, content, name);
            if (after !== undefined) after(desk);
            // Session's limit must outlast the executor's own bounds; the
            // slowest rows run each executor's longest path near them.
            const elapsed = performance.now() - started;
            const limit = desktop.records[Tools.TABLE[tool].executor].timeoutMs;
            assert.ok(elapsed < limit, name + " took " + Math.round(elapsed) + " ms, timeoutMs " + limit);
        } finally { desktop.close(); }
        for (const call of desk.hyprctlCalls()) {
            assert.ok(["j/clients;j/activewindow;j/monitors", "j/workspaces;j/monitors"].includes(call.argv[1]), name + " reads only");
            assert.deepEqual(call.env, ["LANG", "PATH", "XDG_RUNTIME_DIR"], name + " explicit environment");
        }
    }
    for (const row of cases) await check(require(file), row);
    const byName = name => cases.find(row => row[0] === name);
    const toolsWithExecutors = Object.keys(Tools.TABLE).filter(id => ["windows", "compositor", "apps"].includes(Tools.TABLE[id].executor));
    for (const id of toolsWithExecutors)
        assert.ok(cases.some(row => row[1] === id), id + " has a case");

    // A removed stand-in has no host fallback: the read fails, never passes.
    const standin = path.join(process.env.JARVIS_TEST_ROOT, "standins/hyprctl");
    const saved = fs.readFileSync(standin);
    fs.rmSync(standin);
    try {
        desk.reset();
        const { desktop, run } = make();
        const answer = await run("windows.list");
        desktop.close();
        assert.deepEqual([answer.outcome, answer.content], ["failed", "Hyprland state could not be read: hyprctl exit=ENOENT."]);
    } finally { fs.writeFileSync(standin, saved, { mode: 0o700 }); }
    const runLine = "run = os.environ[\"XDG_RUNTIME_DIR\"]\n";
    assert.equal(saved.toString().split(runLine).length, 2, "the stand-in names its runtime dir once");
    fs.writeFileSync(standin, saved.toString().replace(runLine,
        runLine + "with open(os.path.join(run, \"hyprctl.start\"), \"a\") as log:\n    log.write(str(os.getpid()) + \"\\n\")\n"),
    { mode: 0o700 });

    // Registration: the Hyprland executors only after their probe.
    async function installedSession(Desktop, fail, closeEarly = false) {
        desk.reset();
        resetStartPids();
        if (fail) fs.writeFileSync(path.join(runtime, "hyprctl.fail"), "");
        if (closeEarly) desk.delay(1.0);
        const ids = [];
        const router = { register: (id, record) => ids.push([id, record.commands]) };
        const options = { Dispatch, Launch, request: () => assert.fail("no request at install"), clock, bounds, environment, commands: [] };
        const owner = Desktop.install({ router, ...options });
        if (closeEarly) {
            await waitUntil("the probe starts before close", () => startPids().length > 0);
            owner.close();
            await owner.ready;
            return ids;
        }
        await owner.ready;
        owner.close();
        return ids;
    }
    async function installedSeam(Executors, fail, closeEarly = false) {
        desk.reset();
        resetStartPids();
        if (fail) fs.writeFileSync(path.join(runtime, "hyprctl.fail"), "");
        if (closeEarly) desk.delay(1.0);
        const ids = [];
        const router = { register: (id, record) => ids.push([id, record.commands]) };
        const options = { Dispatch, Launch, request: () => assert.fail("no request at install"), clock, bounds, environment, commands: [] };
        const owner = Executors.register(router, { find: () => null, environment, desktop: options });
        if (closeEarly) {
            await waitUntil("the probe starts before close", () => startPids().length > 0);
            owner.close();
            await waitUntil("the probe's close reaches node", allStartedHyprctlDelivered);
            if (desk.hyprctlCalls().length > 0)
                await waitUntil("the unclosed probe registers", () => ids.length > 0, eventLoopPoll);
            return ids;
        }
        if (fail) {
            await waitUntil("the failed probe's close reaches node",
                () => desk.hyprctlCalls().some(call => call.status !== 0) && allStartedHyprctlDelivered());
        } else await waitUntil("the seam registers Hyprland executors", () => ids.length === 3);
        owner.close();
        return ids;
    }
    const registration = async Desktop => {
        assert.deepEqual(await installedSession(Desktop, false), [["windows", ["hyprctl"]], ["compositor", ["hyprctl"]], ["apps", ["hyprctl"]]]);
        assert.deepEqual(await installedSession(Desktop, true), [], "no Hyprland executor without a state read");
        assert.deepEqual(await installedSession(Desktop, false, true), [], "a closed owner registers nothing");
    };
    await registration(require(file));
    const integrated = async Executors => {
        assert.deepEqual(await installedSeam(Executors, false),
            [["windows", ["hyprctl"]], ["compositor", ["hyprctl"]], ["apps", ["hyprctl"]]],
            "the shared seam installs each desktop record once");
        assert.deepEqual(await installedSeam(Executors, true), [],
            "no desktop record is offered without Hyprland");
        assert.deepEqual(await installedSeam(Executors, false, true), [],
            "the seam closes the shared desktop lifetime before its probe registers");
    };
    const executorsFile = path.join(backend, "Executors.js");
    await integrated(require(executorsFile));
    assert.deepEqual(make(require(file), ["gio", "other"]).desktop.records.apps.commands, ["hyprctl", "gio"]);
    assert.deepEqual(make(require(file), []).desktop.records.apps.commands, ["hyprctl"]);
    for (const id of ["windows", "compositor", "apps"])
        assert.equal(make(require(file)).desktop.records[id].cancellable, false, "no executor can take back a dispatch or launch");

    // Lease loss: a poll waiting between reads starts no read after close.
    // A 400 ms poll puts the close inside that wait.
    const closing = async Desktop => {
        desk.reset();
        desk.modes["compositor.focusWindow"] = "noop";
        const testClock = manualClock();
        const requests = ShellRequests.create({ Protocol, clock: testClock, write: fields => {
            const message = Protocol.accept(JSON.stringify({ v: 1, type: "request", gen: 0, revision: "a".repeat(64), ...fields }), "daemon");
            setImmediate(() => {
                const reply = desk.serve(Protocol, message);
                if (reply !== null) requests.reply(Protocol.accept(JSON.stringify(reply), "shell"));
            });
        } });
        const desktop = Desktop.create({ Dispatch, Launch, request: requests.send, clock: testClock,
            bounds: { ...bounds, settleMs: 1000, pollMs: 400 }, commands: ["gio"], environment });
        const run = (id, args = {}) => new Promise(resolve => {
            const refined = Tools.refine({ id, args });
            desktop.records[refined.executor].start(refined.call, resolve);
        });
        let answered = false;
        resetStartPids();
        const answer = run("windows.focus", { window: "0xa1" }).then(value => { answered = true; return value; });
        await waitUntil("the state before and the first poll finish", () => desk.hyprctlCalls().length >= 2);
        await waitUntil("the executor waits for its next poll", () => testClock.pending());
        const reads = desk.hyprctlCalls().length;
        const starts = startPids().length;
        desktop.close();
        testClock.advance(400);
        await waitUntil("the executor reports the closed read or starts another read", () => {
            const newPids = startPids().slice(starts);
            return answered || desk.hyprctlCalls().length > reads || (newPids.length > 0 && newPids.every(pidGone));
        });
        assert.equal(desk.hyprctlCalls().length, reads, "no read after close");
        await answer;
    };
    await closing(require(file));

    let controls = 0;
    async function control(name, needle, replacement, assertion) {
        await mutant(file, name, needle, replacement, assertion, "DesktopSession.js");
        controls++;
    }
    const red = names => Desktop => (async () => { for (const name of names) await check(Desktop, byName(name)); })();
    await control("read-back", "if (verdict.met) return { kind: \"met\", seen: verdict.seen };",
        "return { kind: \"met\", seen: verdict.seen };", red(["focus-noop"]));
    await control("close-undecided", "expect.closed(address))], \"unknown\")", "expect.closed(address))], \"failed\")", red(["close-kept"]));
    await control("fullscreen-focus", "return [step(\"compositor.focusWindow\", [address], expect.active(address)),\n            step(",
        "return [step(", red(["fullscreen"]));
    await control("toggle-before", "action === \"unset\" ? false : !before", "action === \"unset\" ? false : before", red(["float-toggle-noop"]));
    await control("target-check", "if (clientOf(before, address) === undefined) throw failed(", "if (false) throw failed(", red(["focus-absent"]));
    await control("class-rank", "Dispatch.revealTarget(before, addresses, null)", "{ state: \"reveal\", address: addresses[0] }", red(["focus-class-last"]));
    await control("class-initial", " || lower(c.initialClass) === name", "", red(["focus-initial-class"]));
    await control("class-case", "const name = value.slice(\"class:\".length).toLowerCase();", "const name = value.slice(\"class:\".length);", red(["focus-class"]));
    await control("class-absent", "if (target.state === \"none\") throw failed(", "if (false) throw failed(", red(["focus-class-absent"]));
    await control("active-target", "const address = lower(before.active.address);\n        if (address === \"\")", "const address = \"0xa1\";\n        if (address === \"\")", red(["close-active"]));
    await control("active-none", "if (address === \"\") throw failed(\"No window has the focus.\");", "", red(["active-none"]));
    await control("terminal-launch", "Launch.entry({ command: [], runInTerminal: true })", "Launch.entry({ command: [], runInTerminal: false })", red(["terminal"]));
    await control("monitor-resolve", "if (monitor === undefined) throw failed(", "if (false) throw failed(", red(["monitor-unknown"]));
    await control("refused-answer", "if (reply.answer !== \"ok\") throw failed(", "if (false) throw failed(", red(["focus-refused"]));
    await control("timeout-undecided", "case \"timeout\": throw new Ended(\"unknown\",", "case \"timeout\": throw new Ended(\"failed\",", red(["focus-silent"]));
    await control("unread-undecided", "if (result.kind === \"unread\") return { outcome: \"unknown\",",
        "if (result.kind === \"unread\") return { outcome: \"failed\",", red(["focus-unread"]));
    await control("launch-class", ": c => classes.includes(lower(c.class)) || classes.includes(lower(c.initialClass));", ": () => true;", red(["launch-other-class"]));
    await control("terminal-window", "match = entry.terminal ? () => true", "match = false ? () => true", red(["launch-terminal"]));
    await control("timeout-two-steps", "hyprctlWorst + 2 * settleWorst + bounds.slackMs", "hyprctlWorst + settleWorst + bounds.slackMs", red(["fullscreen-slowest"]));
    await control("timeout-last-read", "bounds.launchMs + bounds.pollMs + hyprctlWorst + bounds.slackMs", "bounds.launchMs + bounds.pollMs + bounds.slackMs", red(["launch-slowest"]));
    await control("new-window", "state.clients.filter(c => c.mapped && !old.has(lower(c.address)))", "state.clients.filter(c => c.mapped)", red(["open-windowless"]));
    await control("apps-query", ".toLowerCase().includes(query))", ".length > 0)", red(["apps-query"]));
    await control("probe-first", "    const ready = desktop.probe().then(() => {",
        "    for (const id of [\"windows\", \"compositor\", \"apps\"]) router.register(id, desktop.records[id]);\n    const ready = desktop.probe().then(() => {", registration);
    await control("workspace-shown-by-id", "key(m.activeWorkspace) === key(w) || key(m.specialWorkspace) === key(w)",
        "m.activeWorkspace.id === w.id || m.specialWorkspace.id === w.id", red(["workspaces-0.57.0", "workspaces-0.57.0-special-shown"]));
    await control("workspace-no-identity-shown", "key(w) === \"\" ? [] : ", "", red(["workspaces-0.57.0-no-identity"]));
    await control("workspace-sorted-by-id", "rank(a) - rank(b) || (key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0)", "a.id - b.id", red(["workspaces-0.57.0"]));
    await control("workspace-id-printed", "(Number.isInteger(w.id) ? \"id=\" + w.id : \"address=\" + JSON.stringify(key(w)))", "\"id=\" + w.id", red(["workspaces-0.57.0"]));
    await control("workspace-seen-by-id", "(shown === null ? null : workspaceLabel(shown))", "(shown === null ? null : shown.id)", red(["workspace-named-0.57.0"]));
    await control("close-reads", "if (closed) { reject(new Error(\"closed\")); return; }", "", closing);
    for (const [name, needle, replacement] of [
        ["seam-install", "const session = DesktopSession.install({ router, ...desktop });",
            "const session = { ready: Promise.resolve(false), read: null, readMs: 0, close() {} };"],
        ["seam-close", "for (const lifetime of lifetimes) lifetime.close();", "void lifetimes;"]
    ]) {
        await mutant(executorsFile, name, needle, replacement, integrated, "Executors.js");
        controls++;
    }
    console.log("test-jarvis-desktop: ok cases=" + cases.length + " controls=" + controls);
}, standins);
