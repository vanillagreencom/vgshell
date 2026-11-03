import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "PluginLogic.js" as Logic

// Owns the idle watches across plugin instances: one IdleMonitor per watch,
// through the compositor's ext-idle-notify-v1, respecting idle inhibitors
// such as a playing video's. Each watch belongs to its instance lifetime and
// destroys its monitor with it.
//
// A stage watch is the stage owner's own watch on its stage's time. Each
// idle notification it gives carries a ticket, an opaque object that proves
// that this watch saw the seat go idle; the lock and cover routes check it
// with ticketFor. Input, the watch's disposal (a disable, a rebuild or a new
// watch for the stage) and a change of the stage's owner or time revoke it.
//
// The pause holds every watch while any of its sources holds (D116): each
// monitor is disabled, which reads as input, and counts again from the
// pause's end. Its sources are `screensaver`, live while an application's
// org.freedesktop.ScreenSaver inhibit is, which bin/vgshell-idle-inhibit
// answers while a stage can fire, and `stayAwake`, live while a plugin's
// Stay awake hold is (VGS-2257). Each hold belongs to its instance
// lifetime: its wall-clock end, its `end()`, a disable or a rebuild ends
// it, and nothing stores it, so a restart ends it too.
Scope {
    id: root
    // `<plugin id>#<serial>` -> the watch's IdleMonitor, replaced whole on
    // every change.
    property var watches: ({})
    property int serial: 0
    // Stage -> the live ticket of its owner's watch, { token, owner, stage,
    // generation, seconds }, while that watch reads idle.
    property var tickets: ({})
    // `<plugin id>:<stage>` -> the disposer of that owner's stage watch.
    property var stageWatches: ({})

    // The enabled manifests' idle stages, PluginLogic.idleStages' answer:
    // its `stages` are lent below, and Registry reports its `problems`
    // beside the Hyprland layer's.
    readonly property var stageRecord: Logic.idleStages(Registry.manifests, Registry.enabledIds, Config.effective)

    // Source -> true while it holds the pause, replaced whole on every change.
    property var pauseSources: ({})
    readonly property bool paused: Object.keys(pauseSources).length > 0
    // `<plugin id>#<serial>` -> true for each live Stay awake hold,
    // replaced whole on every change; any hold holds the `stayAwake` source.
    property var stayAwakeHolds: ({})
    // The helper's hold on org.freedesktop.ScreenSaver: `taken` while it
    // answers, `owned` once another connection held the name, else `stopped`.
    property string bus: "stopped"
    // An enabled plugin owns a stage that can fire. The helper follows this,
    // not the watches, so a stage owner replacing its watch drops no inhibit
    // (D012: the bus role exists while a plugin holds one).
    readonly property bool stageCanFire: stageRecord.stages.some(row => row.seconds > 0)
    onStageCanFireChanged: answerer.follow()

    // `stages` is the core's read-only idle stage record (D056, D109): a
    // frozen list, replaced whole when a manifest or the configuration
    // changes, so a binding that reads it follows it.
    function provider(ctx) {
        return Object.freeze({
            watch: (seconds, onChange) => root.watch(ctx, seconds, onChange),
            watchStage: (stage, onChange) => root.watchStage(ctx, stage, onChange),
            stayAwake: (seconds, onEnd) => root.stayAwake(ctx, seconds, onEnd),
            get stages() { return root.stageRecord.stages; }
        });
    }

    // The record as the configuration holds it now. A handler of the
    // plugin's own setting change can run before `stageRecord` follows the
    // same change, so the stage routes read it in place.
    function currentStages() {
        return Logic.idleStages(Registry.manifests, Registry.enabledIds, Config.effective).stages;
    }

    // idle: `onChange(isIdle)` each time the user has given no input for
    // `seconds` and each time input returns. Returns the disposer.
    function watch(ctx, seconds, onChange) {
        const refusal = Logic.idleWatchRefusal(seconds, onChange);
        if (refusal !== "") throw new Error(refusal);
        return ctx.onDispose(addMonitor(ctx, "", seconds, onChange).dispose);
    }

    // The stage owner's watch on STAGE at the stage's current time,
    // replacing the owner's previous watch of it: `onChange(true, ticket)`
    // when the seat goes idle and `onChange(false, null)` when input
    // returns. A stage at Never holds no monitor. Returns the disposer.
    function watchStage(ctx, stage, onChange) {
        const stages = currentStages();
        const refusal = Logic.idleStageWatchRefusal(stages, ctx.id, stage, onChange);
        if (refusal !== "") throw new Error(refusal);
        const slot = ctx.id + ":" + stage;
        if (Logic.hasOwn(stageWatches, slot)) stageWatches[slot]();
        const seconds = stages.find(row => row.stage === stage).seconds;
        if (seconds === 0) return () => {};
        let monitor = null;
        monitor = addMonitor(ctx, stage, seconds, idle => {
            if (idle) {
                const ticket = { token: Object.freeze({}), owner: ctx.id, stage: stage, generation: monitor.generation, seconds: seconds };
                setTicket(stage, ticket);
                onChange(true, ticket.token);
            } else {
                revoke(stage, monitor.generation);
                onChange(false, null);
            }
        });
        // The lifetime's release handle runs the cleanup once and forgets
        // it, so a replaced watch leaves nothing registered behind.
        let release = null;
        release = ctx.onDispose(() => {
            root.revoke(stage, monitor.generation);
            monitor.dispose();
            if (root.stageWatches[slot] !== release) return;
            const rest = Object.assign({}, root.stageWatches);
            delete rest[slot];
            root.stageWatches = rest;
        });
        const next = Object.assign({}, stageWatches);
        next[slot] = release;
        stageWatches = next;
        return release;
    }

    // The live ticket record TOKEN stands for when OWNER's watch of STAGE
    // minted it and nothing has revoked it since, else null. A ticket whose
    // stage changed owner or time since it was minted is stale too.
    function ticketFor(owner, stage, token) {
        const ticket = Logic.hasOwn(tickets, stage) ? tickets[stage] : null;
        if (ticket === null || token === null || ticket.token !== token || ticket.owner !== owner) return null;
        const row = currentStages().find(r => r.stage === stage);
        return row !== undefined && row.plugin === owner && row.seconds === ticket.seconds ? ticket : null;
    }

    function setTicket(stage, ticket) {
        const next = Object.assign({}, tickets);
        next[stage] = ticket;
        tickets = next;
    }

    function revoke(stage, generation) {
        if (!Logic.hasOwn(tickets, stage) || tickets[stage].generation !== generation) return;
        const next = Object.assign({}, tickets);
        delete next[stage];
        tickets = next;
    }

    function addMonitor(ctx, stage, seconds, onChange) {
        const generation = ++serial;
        const key = ctx.id + "#" + generation;
        const monitor = monitorComponent.createObject(root, { timeout: seconds, stage: stage, generation: generation });
        monitor.handler = onChange;
        const next = Object.assign({}, watches);
        next[key] = monitor;
        watches = next;
        return {
            generation: generation,
            dispose: () => {
                const rest = Object.assign({}, root.watches);
                delete rest[key];
                root.watches = rest;
                monitor.destroy();
            }
        };
    }

    // Stay awake: hold the `stayAwake` pause source for `seconds`, or until
    // released with 0. Its end is one wall-clock time, `endsAt`, which the
    // holder shows; `onEnd()` runs once when that time ends the hold, never
    // after the disposer or the instance's end did. Returns the hold,
    // { endsAt, end }: `endsAt` 0 for a hold with no end, and `end` the
    // disposer, which ends the hold and is safe to call again.
    // A QML Timer is synchronized with the animation timer
    // (https://doc.qt.io/qt-6/qml-qtqml-timer.html), which counts on Qt's
    // monotonic clock (https://doc.qt.io/qt-6/qelapsedtimer.html,
    // MonotonicClock), and Linux's CLOCK_MONOTONIC leaves out the time the
    // system sleeps (clock_gettime(2)). One timer for the whole hold would
    // end it late by every suspend, so the timer waits at most a step
    // (Logic.stayAwakeWait) and judges the end from the wall clock each
    // time it fires.
    function stayAwake(ctx, seconds, onEnd) {
        const refusal = Logic.stayAwakeRefusal(seconds, onEnd);
        if (refusal !== "") throw new Error(refusal);
        const key = ctx.id + "#" + (++serial);
        const endsAt = seconds === 0 ? 0 : Date.now() + seconds * 1000;
        const timer = seconds === 0 ? null : holdTimer.createObject(root, { interval: Logic.stayAwakeWait(endsAt, Date.now()) });
        let ended = false;
        const end = () => {
            if (ended) return;
            ended = true;
            if (timer !== null) {
                timer.stop();
                timer.destroy();
            }
            const rest = Object.assign({}, root.stayAwakeHolds);
            delete rest[key];
            root.stayAwakeHolds = rest;
            root.setPause("stayAwake", Object.keys(rest).length > 0);
        };
        const release = ctx.onDispose(end);
        if (timer !== null) {
            timer.triggered.connect(() => {
                if (ended) return;
                const wait = Logic.stayAwakeWait(endsAt, Date.now());
                if (wait > 0) {
                    timer.interval = wait;
                    timer.start();
                    return;
                }
                release();
                onEnd();
            });
            timer.start();
        }
        const next = Object.assign({}, stayAwakeHolds);
        next[key] = true;
        stayAwakeHolds = next;
        setPause("stayAwake", true);
        return Object.freeze({ endsAt: endsAt, end: release });
    }

    function setPause(source, holds) {
        if (Logic.hasOwn(pauseSources, source) === holds) return;
        const next = Object.assign({}, pauseSources);
        if (holds) next[source] = true;
        else delete next[source];
        pauseSources = next;
    }

    // The pause for the lending record: its live sources, the plugin id of
    // each Stay awake hold and the bus hold.
    function pauseRecord() {
        return { sources: Object.keys(pauseSources).sort(), stayAwake: Object.keys(stayAwakeHolds).map(key => key.split("#")[0]).sort(), bus: bus };
    }

    // The watches for the lending record: plugin id, timeout, state, the
    // stage a stage watch serves ("" for a plain watch) and its generation.
    function record() {
        return Object.keys(watches).sort().map(key => {
            const monitor = watches[key];
            return { id: key.split("#")[0], timeout: monitor.timeout, idle: monitor.isIdle, stage: monitor.stage, generation: monitor.generation };
        });
    }

    // One Stay awake hold's next check of its end, owned by
    // IdleRegistry.stayAwake and destroyed with its hold.
    Component {
        id: holdTimer
        Timer { repeat: false }
    }

    Component {
        id: monitorComponent
        IdleMonitor {
            property var handler: null
            property string stage: ""
            property int generation: 0
            respectInhibitors: true
            // A disabled monitor holds no ext-idle-notify notification and
            // reads isIdle false, so an idle one reports input; enabled
            // again it creates a notification that counts from then
            // (Quickshell 2b4501a, src/wayland/idle_notify/monitor.cpp;
            // scripts/smoke/rows/idle-inhibit.sh reads both).
            enabled: !root.paused
            onIsIdleChanged: handler(isIdle)
        }
    }

    // The org.freedesktop.ScreenSaver answerer. It runs while a stage can
    // fire. After it ends on its own it starts again only when the stage
    // record goes from no stage that can fire to one: its cookies ended with
    // it, and the idle path fails open until then.
    // A child that fails to start emits only runningChanged, so each end is
    // read there.
    Process {
        id: answerer
        property bool asked: false
        property bool owned: false
        property var completion: null
        command: [Quickshell.shellDir + "/../bin/vgshell-idle-inhibit"]
        stdout: SplitParser { onRead: line => answerer.said(line) }
        stderr: StdioCollector { id: answererErrors }
        Component.onCompleted: follow()
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            root.setPause("screensaver", false);
            const end = completion;
            completion = null;
            if (!asked && !owned) {
                const first = answererErrors.text.split("\n").find(line => line.trim() !== "");
                console.warn("idle: org.freedesktop.ScreenSaver answerer ended code=" + (end === null || end.status !== 0 ? "none" : end.code) + " stderr=" + JSON.stringify(first === undefined ? "" : first.trim().slice(0, 200)));
            }
            if (!owned) root.bus = "stopped";
            asked = false;
        }

        function follow() {
            if (root.stageCanFire) {
                if (running) return;
                owned = false;
                running = true;
            } else if (running) {
                asked = true;
                running = false;
            } else {
                root.bus = "stopped";
            }
        }

        function said(line) {
            switch (line) {
            case "name=taken":
                root.bus = "taken";
                return;
            case "name=owned":
                owned = true;
                root.bus = "owned";
                console.info("idle: org.freedesktop.ScreenSaver is held by another owner; VGS does not answer it");
                return;
            case "live":
                root.setPause("screensaver", true);
                return;
            case "idle":
                root.setPause("screensaver", false);
                return;
            default:
                console.warn("idle: org.freedesktop.ScreenSaver answerer said unknown=" + JSON.stringify(line.slice(0, 80)));
            }
        }
    }
}
