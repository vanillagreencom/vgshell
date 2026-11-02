import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "SoundLogic.js" as Logic

// The Sound service: the volume keys, the on-screen display, the choice of
// output and input, and the one owner of the pactl runs that move playing
// apps to a new output. The bar widget, the flyout and the pane change
// volume through their own Audio, and ask this service, through the
// plugin's own IPC, for what it owns:
//   shortcut vgs.sound:volume-up, volume-down  a step of `volumeStep`
//   shortcut vgs.sound:mute, mic-mute          output and input mute
//   vgshell ipc call vgs.sound invoke step up|down     the same step; answers
//                                                   the new percentage
//   vgshell ipc call vgs.sound invoke mute ''          answers muted|unmuted
//   vgshell ipc call vgs.sound invoke mic-mute ''      answers muted|unmuted
//   vgshell ipc call vgs.sound invoke output <sink>    makes the sink the
//                                                   default output
//   vgshell ipc call vgs.sound invoke input <source>   makes the source the
//                                                   default input
// A step and a mute show the display on the focused screen for
// `osd.duration`. A step, mute or choice with no PipeWire answers
// `refused: sound=unavailable`, and an unknown device `unknown: <name>`.
//
// A new output becomes Pipewire's preferred default sink, then, while
// pactl is installed, every app already playing moves to it:
// `pactl --format=json list sink-inputs`, then one `pactl
// move-sink-input <index> <sink>` per stream SoundLogic.streamsToMove
// takes. Without pactl, new streams follow and playing ones stay; the
// `streams` status says so and offers to install it.
Item {
    id: root

    // The core assigns the plugin's scoped shell object after creation.
    property var shell: null
    // The shell this service registered with, so a settings change that
    // hands over a new object registers nothing twice.
    property var registeredWith: null
    readonly property real step: shell === null ? NaN : Number(shell.settings.volumeStep)
    readonly property bool pactl: shell !== null && shell.requirements.missing.indexOf("pactl") === -1
    // What the display shows, { icon, level, text } from SoundLogic.osdView,
    // or null while it is hidden.
    property var osd: null
    readonly property string focusedOutput: Hyprland.focusedMonitor === null ? "" : Hyprland.focusedMonitor.name
    // The sink the moves of the last output choice go to, "" for none.
    property string moveTo: ""
    // The streams still to move there.
    property var moveQueue: []

    // One event owner for every Audio instance. Status contains primitives;
    // each view and chooseInput resolve their own current PipeWire objects.
    property bool ending: false
    property int inputGeneration: 0
    property bool inputQueued: false
    property var inputRoutes: ({ state: "pending", reason: "", sources: [] })
    property bool subscriptionRetried: false

    onShellChanged: {
        if (shell === null || registeredWith !== null) return;
        registeredWith = shell;
        publish();
        shell.shortcut.register("volume-up", "Raise the volume", () => root.stepVolume(1));
        shell.shortcut.register("volume-down", "Lower the volume", () => root.stepVolume(-1));
        shell.shortcut.register("mute", "Mute the output", () => root.toggleMute());
        shell.shortcut.register("mic-mute", "Mute the microphone", () => root.toggleInputMute());
        shell.ipc.handle("step", arg => {
            if (arg !== "up" && arg !== "down") return "refused: step=" + arg + " want=up|down";
            return root.stepVolume(arg === "up" ? 1 : -1);
        });
        shell.ipc.handle("mute", () => root.toggleMute());
        shell.ipc.handle("mic-mute", () => root.toggleInputMute());
        shell.ipc.handle("output", name => root.chooseOutput(name));
        shell.ipc.handle("input", name => root.chooseInput(name));
        shell.ipc.handle("refresh-inputs", () => { root.refreshInputs(); return "ok"; });
        root.refreshInputs();
        shell.layers.show(display);
    }
    onPactlChanged: {
        if (registeredWith === null) return;
        publish();
        if (pactl) refreshInputs(); else stopInputs("pactl");
    }

    function publish() {
        const reply = shell.status.set("streams", Logic.streamsState(root.pactl));
        if (!shell.status.isOk(reply)) console.warn("sound: streams " + reply);
    }

    function stepVolume(direction) {
        if (!audio.available || !audio.hasOutput) return "refused: sound=unavailable";
        const next = Logic.stepped(audio.volume, direction, root.step);
        audio.setNodeVolume(audio.volumeSink, next);
        root.osd = Logic.osdView("output", next, audio.muted);
        hide.restart();
        return String(Logic.percent(next));
    }

    function toggleMute() {
        if (!audio.available || !audio.hasOutput) return "refused: sound=unavailable";
        const muted = !audio.muted;
        audio.setNodeMuted(audio.volumeSink, muted);
        root.osd = Logic.osdView("output", audio.volume, muted);
        hide.restart();
        return muted ? "muted" : "unmuted";
    }

    function toggleInputMute() {
        if (!audio.available || !audio.hasInput) return "refused: sound=unavailable";
        const muted = !audio.inputMuted;
        audio.setNodeMuted(audio.source, muted);
        root.osd = Logic.osdView("input", audio.inputVolume, muted);
        hide.restart();
        return muted ? "muted" : "unmuted";
    }

    function chooseOutput(name) {
        if (!audio.available) return "refused: sound=unavailable";
        const node = audio.outputNamed(name);
        if (node === null) return "unknown: " + name;
        Pipewire.preferredDefaultAudioSink = node;
        if (!root.pactl) return "ok";
        root.moveTo = name;
        root.moveQueue = [];
        if (!lister.running) root.list();
        return "ok";
    }

    function chooseInput(name) {
        if (!audio.available) return "refused: sound=unavailable";
        // Registry lookup rejects a row removed during Audio's delayed
        // snapshot. The same judge used by both views rejects unavailable
        // routes even when an old row still sends its source name.
        const node = Pipewire.nodes.values.find(n => n !== null && n.audio !== null
            && !n.isStream && !n.isSink && String(n.name) === name);
        if (node === undefined) return "unknown: " + name;
        const choice = Logic.inputDecision(name, audio.label(node), root.inputRoutes);
        if (!choice.selectable) return "refused: input=unavailable";
        Pipewire.preferredDefaultAudioSource = node;
        return "ok";
    }

    // List the playing streams for the sink of the last choice.
    function list() {
        lister.listedFor = root.moveTo;
        lister.running = true;
    }

    // Move the next stream of the queue, if any.
    function moveNext() {
        if (mover.running || root.moveQueue.length === 0) return;
        const index = root.moveQueue[0];
        root.moveQueue = root.moveQueue.slice(1);
        mover.command = ["pactl", "move-sink-input", String(index), root.moveTo];
        mover.running = true;
    }

    Audio {
        id: audio
        inputMetadata: root.inputRoutes
        onAvailableChanged: {
            if (root.registeredWith === null || root.ending) return;
            if (available) root.refreshInputs(); else root.stopInputs("pipewire");
        }
    }

    function publishInputs(state, reason, sources) {
        if (root.ending) return;
        root.inputRoutes = { state: state, reason: reason, sources: sources };
        if (root.shell === null) return;
        const reply = root.shell.status.set("inputRoutes", root.inputRoutes);
        if (!root.shell.status.isOk(reply)) {
            // PluginStatus owns the publication byte ceiling. A refused
            // inventory must invalidate the previous published routes.
            root.inputRoutes = { state: "unreadable", reason: "publication", sources: [] };
            root.shell.status.set("inputRoutes", root.inputRoutes);
            console.warn("sound: inputRoutes " + reply);
        }
    }

    function stopInputs(reason) {
        ++root.inputGeneration;
        root.inputQueued = false;
        readNext.stop();
        subscribeRetry.stop();
        root.publishInputs("unreadable", reason, []);
        routeReader.running = false;
        routeEvents.running = false;
    }

    function refreshInputs() {
        if (root.ending || root.registeredWith === null) return;
        if (!audio.available || !root.pactl) {
            root.stopInputs(!audio.available ? "pipewire" : "pactl");
            return;
        }
        ++root.inputGeneration;
        root.inputQueued = true;
        // Availability becomes pending immediately. Labels can survive a
        // refresh, but the judge cannot reuse their old availability.
        root.publishInputs("pending", "", root.inputRoutes.sources);
        if (!routeEvents.running) {
            subscribeRetry.stop();
            root.subscriptionRetried = false;
            routeEvents.running = true;
        }
        readNext.start();
    }

    function readInputs() {
        if (root.ending || !audio.available || !root.pactl || routeReader.running || !root.inputQueued) return;
        root.inputQueued = false;
        routeReader.generation = root.inputGeneration;
        routeReader.phase = "sources";
        routeReader.command = ["pactl", "--format=json", "list", "sources"];
        routeReader.running = true;
    }

    // Process closes its parsers before exited, then runningChanged. A
    // failed start has no exited signal. Destruction kills owned children.
    // Verified in installed Quickshell 4f508be src/io/process.cpp and
    // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process/.
    Process {
        id: routeReader
        property var completion: null
        property int generation: -1
        property string phase: ""
        property string sources: ""
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector { id: routeText }
        stderr: StdioCollector {}
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            if (!Logic.currentInputRead(root.ending, audio.available && root.pactl, generation, root.inputGeneration)) {
                if (root.inputQueued && !root.ending) readNext.start();
                return;
            }
            if (done === null || done.code !== 0 || done.status !== 0) {
                root.publishInputs("unreadable", phase, []);
                return;
            }
            if (phase === "sources") {
                sources = routeText.text;
                phase = "cards";
                command = ["pactl", "--format=json", "list", "cards"];
                running = true;
                return;
            }
            const parsed = Logic.parseInputRoutes(sources, routeText.text);
            root.publishInputs(parsed.state, parsed.reason, parsed.sources);
            readNext.start();
        }
    }

    // stdout is attached before startup. started proves a process exists,
    // not that Pulse acknowledged subscription; opening a choice always
    // requests its own fresh read. JSON events are emitted by libpulse's
    // pactl producer, with event and on keys (pactl.c b096704c0).
    Process {
        id: routeEvents
        command: ["pactl", "--format=json", "subscribe"]
        environment: ({ LC_ALL: "C" })
        stdout: SplitParser {
            onRead: line => {
                if (root.ending) return;
                const event = Logic.inputRouteEvent(line);
                if (event !== "ignore") root.refreshInputs();
            }
        }
        stderr: StdioCollector {}
        onRunningChanged: {
            if (running || root.ending || !audio.available || !root.pactl) return;
            ++root.inputGeneration;
            root.inputQueued = false;
            root.publishInputs("unreadable", "subscription", []);
            // A single process-recovery retry, never metadata polling.
            // A view opening or readiness recovery can try again later.
            if (!root.subscriptionRetried) {
                root.subscriptionRetried = true;
                subscribeRetry.start();
            }
        }
    }

    Timer { id: readNext; interval: 0; onTriggered: root.readInputs() }
    Timer {
        id: subscribeRetry
        interval: 1000
        onTriggered: {
            if (root.ending || !audio.available || !root.pactl) return;
            routeEvents.running = true;
            ++root.inputGeneration;
            root.inputQueued = true;
            readNext.start();
        }
    }

    Component.onDestruction: {
        root.ending = true;
        root.inputQueued = false;
        readNext.stop();
        subscribeRetry.stop();
        routeEvents.running = false;
        routeReader.running = false;
    }


    // The playing streams pactl lists after an output choice. A choice
    // made while a list runs lists again once it ends, for the newest sink;
    // a list that could not start ends there.
    Process {
        id: lister
        property var completion: null
        property string listedFor: ""
        command: ["pactl", "--format=json", "list", "sink-inputs"]
        stdout: StdioCollector { id: listed }
        stderr: StdioCollector { id: listErr }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            if (done === null) { console.warn("sound: pactl list start-failed"); return; }
            if (listedFor !== root.moveTo) { root.list(); return; }
            if (done.code !== 0) { console.warn("sound: pactl list exit=" + done.code + " " + listErr.text.trim()); return; }
            const parsed = Logic.parseSinkInputs(listed.text);
            if (!parsed.ok) { console.warn("sound: pactl list " + parsed.error); return; }
            root.moveQueue = Logic.streamsToMove(parsed.inputs);
            root.moveNext();
        }
    }

    Process {
        id: mover
        property var completion: null
        stderr: StdioCollector { id: moveErr }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            if (done === null) console.warn("sound: pactl move start-failed argv=" + JSON.stringify(command));
            else if (done.code !== 0) console.warn("sound: pactl move exit=" + done.code + " argv=" + JSON.stringify(command) + " " + moveErr.text.trim());
            root.moveNext();
        }
    }

    Timer {
        id: hide
        interval: Theme.osd.duration
        onTriggered: root.osd = null
    }

    // The display, one copy per screen, shown on the focused one while a
    // key's change is fresh; it takes no input.
    Component {
        id: display
        Item {
            id: copy
            property var screen: null
            readonly property bool shown: root.osd !== null && screen !== null && screen.name === root.focusedOutput

            LevelOsd {
                visible: copy.shown
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.osd.margin
                iconName: root.osd === null ? "" : root.osd.icon
                level: root.osd === null ? 0 : root.osd.level
                text: root.osd === null ? "" : root.osd.text
            }
        }
    }
}
