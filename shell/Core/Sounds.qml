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
// one event sounds once, and at most Logic.SOUND_RUNS_MAX runs are in
// flight. pw-play exits when its file has played; one that does not, as
// when PipeWire never answers, is stopped after `runLimit`.
Singleton {
    id: root

    readonly property string directory: Quickshell.shellDir + "/assets/sounds"
    // The longest a run may last. A design choice, not a measurement: the
    // shipped sounds each last under a second (python3 wave, 2026-10-09).
    readonly property int runLimit: 10000
    // The runs in flight, oldest first.
    property var runs: []
    // Every event of every enabled plugin, as the Sounds page lists them.
    readonly property var rows: Logic.frozenJson(Logic.soundRows(Config.effective, Registry.manifests, Registry.defaultBarId))
    // The sounds a choice may name, { id, label } in the page's order.
    readonly property var library: Logic.frozenJson(Logic.SOUNDS.map(sound => ({ id: sound.id, label: sound.label })))

    // The events of plugin ID under the user's choices, { event: value },
    // and none for an instance whose plugin a rescan already removed.
    function choicesOf(id) {
        return Registry.has(id) ? Logic.frozenJson(Logic.soundChoices(Config.effective, Registry.manifests[id])) : Object.freeze({});
    }

    // Play EVENT of the plugin the instance CTX belongs to. Answers `ok`
    // once the player is started, `off` when the event has no sound,
    // `busy` while that sound still plays or the runs are at their
    // ceiling, or the keyed refusal.
    function play(ctx, event) {
        if (!Registry.isEnabled(ctx.id)) return Logic.soundRefusal(event, "retired");
        const request = Logic.soundRequest(Config.effective, Registry.manifests[ctx.id], event);
        return request.ok ? start(request.sound, ctx.id + "/" + event) : request.answer;
    }

    // Play SOUND, an id of the library, as the Sounds page's Test does.
    function test(sound) {
        if (Logic.soundOf(sound) === null) return Logic.soundRefusal(sound, "unknown");
        return start(sound, "test");
    }

    // The Sounds page's choice of VALUE for EVENT of plugin ID: `ok` once
    // the user file holds it, or the keyed refusal.
    function choose(id, event, value) {
        const manifest = typeof id === "string" && Registry.isEnabled(id) ? Registry.manifests[id] : null;
        const edit = Logic.soundEdit(Config.user, Config.effective, manifest, id, event, value);
        return edit.ok ? Config.writeUser(edit.user) : edit.answer;
    }

    function start(sound, origin) {
        if (runs.some(run => run.sound === sound) || runs.length >= Logic.SOUND_RUNS_MAX) return "busy";
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
