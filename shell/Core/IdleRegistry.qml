import QtQuick
import Quickshell
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

    // `stages` is the core's read-only idle stage record (D056, D109): a
    // frozen list, replaced whole when a manifest or the configuration
    // changes, so a binding that reads it follows it.
    function provider(ctx) {
        return Object.freeze({
            watch: (seconds, onChange) => root.watch(ctx, seconds, onChange),
            watchStage: (stage, onChange) => root.watchStage(ctx, stage, onChange),
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

    // The watches for the lending record: plugin id, timeout, state, the
    // stage a stage watch serves ("" for a plain watch) and its generation.
    function record() {
        return Object.keys(watches).sort().map(key => {
            const monitor = watches[key];
            return { id: key.split("#")[0], timeout: monitor.timeout, idle: monitor.isIdle, stage: monitor.stage, generation: monitor.generation };
        });
    }

    Component {
        id: monitorComponent
        IdleMonitor {
            property var handler: null
            property string stage: ""
            property int generation: 0
            respectInhibitors: true
            onIsIdleChanged: handler(isIdle)
        }
    }
}
