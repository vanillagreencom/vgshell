pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "PluginLogic.js" as Logic

// The shell's one sound player. A plugin declares its sound events in its
// manifest's `sounds` key and plays one through capability `sounds`; the
// Sounds page chooses each event's sound through capability
// `soundSettings`, and the choice is shell.json `sounds`, which this
// singleton alone writes. PluginLogic judges every request; this file owns
// the player processes, one pw-play run per sound, each destroyed when it
// ends. A sound that is still playing is not started again, so a burst of
// one event sounds once and the runs in flight never outnumber the core's
// sounds. pw-play exits when its file has played; one that does not, as
// when PipeWire never answers, is stopped after `runLimit`.
//
// An event its manifest marks `held` has its value in another program's
// file, which shell.json does not copy: the plugin's one holder states the
// value it read and applies the page's choice, and the page asks every
// holder to read again when it opens.
Singleton {
    id: root

    readonly property string directory: Quickshell.shellDir + "/assets/sounds"
    // The longest a run may last. A design choice, not a measurement: the
    // shipped sounds each last under a second (python3 wave, 2026-10-09).
    readonly property int runLimit: 10000
    // The runs in flight, oldest first.
    property var runs: []
    // Plugin id -> { event -> { value, problem } }: what the holder of each
    // held event last stated. Replaced whole on every change, so `rows`
    // re-evaluates once per statement.
    property var held: ({})
    // Plugin id -> { event -> { ctx, read, choose } }: the instance that
    // holds each held event and its two handlers. A holder lives with the
    // instance that registered it, and its statement goes with it.
    property var holders: ({})
    // Every event of every enabled plugin, as the Sounds page lists them.
    readonly property var rows: Logic.frozenJson(Logic.soundRows(Config.effective, Registry.manifests, Registry.defaultBarId, held))

    // The events of plugin ID under the user's choices, { event: value },
    // and none for an instance whose plugin a rescan already removed.
    function choicesOf(id) {
        return Registry.has(id) ? Logic.frozenJson(Logic.soundChoices(Config.effective, Registry.manifests[id])) : Object.freeze({});
    }

    function holderOf(id, event) {
        return Logic.hasOwn(holders, id) && Logic.hasOwn(holders[id], event) ? holders[id][event] : null;
    }

    function withEntry(map, id, event, entry) {
        const next = Object.assign({}, map);
        const own = Object.assign({}, next[id]);
        if (entry === undefined) delete own[event];
        else own[event] = entry;
        if (Object.keys(own).length === 0) delete next[id];
        else next[id] = own;
        return next;
    }

    // Register the instance CTX belongs to as the holder of its plugin's
    // held EVENT, released with the instance. HOLDER is { read, choose }:
    // `read()` reads the value again and reports it, and `choose(value)`
    // applies the page's choice and answers `ok` once it took it, or its
    // own keyed refusal. Answers `ok`, `reason=undeclared`, `reason=stored`
    // for an event the core stores, or `reason=held` while another
    // instance holds the event.
    function hold(ctx, event, holder) {
        if (holder === null || typeof holder !== "object" || typeof holder.read !== "function" || typeof holder.choose !== "function")
            throw new Error("refused: sound=" + event + " holder=not-read-and-choose");
        if (typeof event !== "string" || !Logic.hasOwn(ctx.manifest.sounds, event)) return Logic.soundRefusal(event, "undeclared");
        if (!Logic.soundHeld(ctx.manifest, event)) return Logic.soundRefusal(event, "stored");
        if (holderOf(ctx.id, event) !== null) return Logic.soundRefusal(event, "held");
        holders = withEntry(holders, ctx.id, event, { ctx: ctx, read: holder.read, choose: holder.choose });
        ctx.onDispose(() => {
            root.holders = root.withEntry(root.holders, ctx.id, event, undefined);
            root.held = root.withEntry(root.held, ctx.id, event, undefined);
        });
        return "ok";
    }

    // The holder CTX states the value of its held EVENT: `ok`, or the
    // keyed refusal, `reason=unheld` from an instance that is not the
    // event's holder.
    function report(ctx, event, value, problem) {
        const holder = holderOf(ctx.id, event);
        if (holder === null || holder.ctx !== ctx) return Logic.soundRefusal(event, "unheld");
        const stated = Logic.soundReport(ctx.manifest, event, value, problem);
        if (!stated.ok) return stated.answer;
        held = withEntry(held, ctx.id, event, stated.state);
        return "ok";
    }

    // Ask every holder to read its value again, as the Sounds page does
    // when it opens, so a change made outside the shell shows there.
    function refresh() {
        for (const id of Object.keys(holders))
            for (const event of Object.keys(holders[id])) holders[id][event].read();
    }

    // Play EVENT of the plugin the instance CTX belongs to. Answers `ok`
    // once the player is started, `off` when the event has no sound,
    // `busy` while that sound still plays, or the keyed refusal.
    function play(ctx, event) {
        if (!Registry.isEnabled(ctx.id)) return Logic.soundRefusal(event, "retired");
        const request = Logic.soundRequest(Config.effective, Registry.manifests[ctx.id], event);
        return request.ok ? start(request.sound, ctx.id + "/" + event) : request.answer;
    }

    // Play SOUND, an id of the core's sounds, as the Sounds page's Test does.
    function test(sound) {
        if (Logic.soundOf(sound) === null) return Logic.soundRefusal(sound, "unknown");
        return start(sound, "test");
    }

    // The Sounds page's choice of VALUE for EVENT of plugin ID: `ok` once
    // the user file holds it, or the keyed refusal. A held event's choice
    // goes to its holder and answers what the holder answers, `ok` once it
    // took the choice; what came of it is the holder's next statement.
    // `reason=unheld` while no instance holds the event.
    function choose(id, event, value) {
        const manifest = typeof id === "string" && Registry.isEnabled(id) ? Registry.manifests[id] : null;
        const edit = Logic.soundEdit(Config.user, Config.effective, manifest, id, event, value);
        if (!edit.ok) return edit.answer;
        if (edit.held !== true) return Config.writeUser(edit.user);
        const holder = holderOf(id, event);
        if (holder === null) return Logic.soundRefusal(event, "unheld");
        const reply = holder.choose(value);
        return typeof reply === "string" ? reply : Logic.soundRefusal(event, "reply");
    }

    function start(sound, origin) {
        if (runs.some(run => run.sound === sound)) return "busy";
        // A list crosses createObject's initial properties as something
        // else, so the run takes its command after creation.
        const run = runComponent.createObject(root, { sound: sound, origin: origin });
        if (run === null) {
            console.warn("sounds: unplayed sound=" + sound + " origin=" + origin + " exit=null process");
            return "ok";
        }
        run.command = Logic.soundArgv(directory, sound);
        runs = runs.concat([run]);
        run.running = true;
        return "ok";
    }

    // A run ended: COMPLETION is its exit, null when it did not start.
    function ended(run, completion, complaint) {
        runs = runs.filter(item => item !== run);
        if (completion === null || completion.code !== 0 || completion.status !== 0)
            console.warn("sounds: unplayed sound=" + run.sound + " origin=" + run.origin + " exit=" + JSON.stringify(completion) + " " + complaint.trim().split("\n")[0].trim().slice(0, 200));
        Qt.callLater(() => run.destroy());
    }

    // The sounds playing now, oldest first, for the lending record.
    function record() {
        return { playing: runs.map(run => run.sound) };
    }

    // A command that fails to start emits only runningChanged, so the end
    // is read there: no exit recorded is a failed start.
    Component {
        id: runComponent
        Process {
            id: run
            property string sound: ""
            property string origin: ""
            property var completion: null
            // pw-play needs the program path and the session's PipeWire
            // alone. Under clearEnvironment a null value passes the shell's
            // own value through (Quickshell 0.3.1, Process.clearEnvironment).
            clearEnvironment: true
            environment: ({ PATH: null, XDG_RUNTIME_DIR: null, PIPEWIRE_RUNTIME_DIR: null, PIPEWIRE_REMOTE: null, LANG: "C.UTF-8" })
            stderr: StdioCollector { id: complaint }
            onExited: (code, status) => { completion = { code: code, status: status }; }
            onRunningChanged: if (!running) root.ended(run, completion, complaint.text)
            // Setting `running` to false sends SIGTERM (Quickshell 0.3.1,
            // Process.running).
            property Timer limit: Timer {
                interval: root.runLimit
                running: run.running
                onTriggered: run.running = false
            }
        }
    }
}
