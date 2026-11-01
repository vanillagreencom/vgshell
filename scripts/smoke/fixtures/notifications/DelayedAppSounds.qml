import QtQuick
import "." as Notifications

// Copied beside the production plugin files in a fresh test directory.
// The scene outlives the Loader, but retains no reference to its item.
Item {
    id: scene

    visible: false
    property bool queued: false
    property bool drained: false
    property string kind: ""
    property bool release: false
    property string expected: ""
    property var writer: null
    property bool ruleRunningAtQueue: true
    property int metadataStarts: 0
    property bool observingWriter: false

    readonly property var observation: {
        const item = sounds.item;
        const state = item === null ? null : item.state();
        return {
            ready: state !== null && state.writer !== null && state.hold === "confirmed" && item.ruleHold !== null,
            loaded: item !== null,
            writer: writer === null && state !== null ? state.writer : writer,
            hold: state === null ? "released" : state.hold,
            queued: queued,
            drained: drained,
            kind: kind,
            release: release,
            expected: expected,
            ruleRunningAtQueue: ruleRunningAtQueue,
            metadataStarts: metadataStarts,
            observingWriter: observingWriter
        };
    }

    Loader {
        id: sounds
        sourceComponent: Component {
            Notifications.AppSounds { ruleRunning: true }
        }
    }

    function exercise(argument) {
        const row = JSON.parse(argument);
        if (queued || !observation.ready) throw new Error("delayed-app-sounds: not-ready");
        if (!["publish", "refresh"].includes(row.kind) || typeof row.release !== "boolean" || typeof row.app !== "string" || row.app === "")
            throw new Error("delayed-app-sounds: invalid-case");
        kind = row.kind;
        release = row.release;
        expected = row.app;
        writer = sounds.item.state().writer;
        // Item.resources contains its nonvisual children (Qt Item API):
        // https://doc.qt.io/qt-6/qml-qtquick-item.html#resources-prop
        // Observe the real Process.started signal, not a sampled PID:
        // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process
        const writers = Array.from(sounds.item.resources).filter(object => "command" in object && object.command[0] === "pw-metadata");
        if (writers.length !== 1) throw new Error("delayed-app-sounds: metadata-writer-not-unique");
        writers[0].started.connect(scene.metadataStarted);
        observingWriter = true;
        sounds.item.ruleRunning = false;
        ruleRunningAtQueue = sounds.item.ruleRunning;
        // Change pending intent without calling the synchronous write path.
        sounds.item.ruleHold = { apps: [row.app], roles: [] };
        queued = true;
        if (kind === "publish") {
            // refresh is the production producer of deferred publication.
            sounds.item.refresh();
            sounds.item.refresh();
        } else {
            // The exact stable callback queued by Pipewire.valuesChanged.
            Qt.callLater(sounds.item.deferredWork.refresh);
            Qt.callLater(sounds.item.deferredWork.refresh);
        }
        if (release) sounds.active = false;
        Qt.callLater(scene.firstDrain);
    }

    // A deferred refresh can itself queue publication. The second barrier
    // acknowledges that next turn too; elapsed time proves no queue order.
    function firstDrain() { Qt.callLater(scene.finishDrain); }
    function finishDrain() { drained = true; }
    function metadataStarted() { metadataStarts += 1; }
}
