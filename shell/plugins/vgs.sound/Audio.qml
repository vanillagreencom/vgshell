import QtQuick
import Quickshell.Services.Pipewire
import "SoundLogic.js" as Logic

// The sound every instance of vgs.sound reads and changes, from
// Quickshell's in-process Pipewire service, a read model that claims no
// session role: the default output and input, the sink a volume change
// reaches, and the outputs, inputs and playing apps a list draws. Each
// instance declares its own; nothing here runs a process.
//
// The lists are snapshots `refresh` takes a short time after PipeWire's
// node or link lists change, never a binding or a Repeater on the live
// model: rebuilding from the removal signal while Quickshell dispatches it
// has crashed Quickshell's PipeWire service, and that crash would end the whole
// shell. An output, input or app row is { name, label, node }.
//
// `volumeSink` is the sink a volume change reaches: the default output, or
// the device a DSP default output plays to (SoundLogic.volumeTarget), from
// each output stream's application.name and node.link-group, which PipeWire
// gives only a bound node, so the default input and every output and
// output stream are bound. `available` is false while Quickshell holds no
// synced PipeWire connection, as after PipeWire stopped.
Item {
    id: root

    visible: false

    property var outputs: []
    property var inputs: []
    // Every audio node and link group of the last snapshot: the nodes as
    // PwNode objects, the links as { source, target } node names.
    property var nodes: []
    property var links: []
    // The app streams of the snapshot as rows. A binding over the snapshot,
    // not over the live model: a stream's application.name arrives once the
    // tracker below has bound it, after the snapshot that listed it, and
    // the row follows then.
    readonly property var apps: root.nodes.filter(n => n.isStream && n.isSink
            && Logic.isAppStream(root.property(n, "application.name"), root.property(n, "node.link-group")))
        .map(n => ({ name: String(n.name), label: root.property(n, "application.name"), node: n }))

    // False once PipeWire stops: a lost connection resets the registry and
    // its nodes go, and the socket a restarted PipeWire makes brings it back.
    readonly property bool available: Pipewire.ready
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property string sinkName: sink === null ? "" : String(sink.name)
    readonly property string sourceName: source === null ? "" : String(source.name)
    readonly property var graph: root.nodes.map(n => ({ name: String(n.name), stream: n.isStream, sink: n.isSink,
        app: root.property(n, "application.name"), linkGroup: root.property(n, "node.link-group") }))
    readonly property string volumeSinkName: Logic.volumeTarget(sinkName, graph, links)
    readonly property var volumeSink: root.outputNamed(volumeSinkName)
    readonly property var outputAudio: root.audioOf(volumeSink)
    readonly property var inputAudio: root.audioOf(source)
    readonly property bool hasOutput: outputAudio !== null
    readonly property bool hasInput: inputAudio !== null
    readonly property real volume: hasOutput ? outputAudio.volume : 0
    readonly property bool muted: hasOutput && outputAudio.muted
    readonly property real inputVolume: hasInput ? inputAudio.volume : 0
    readonly property bool inputMuted: hasInput && inputAudio.muted
    // The default output's and input's names as a list draws them, "" for
    // none.
    readonly property string outputLabel: sink === null ? "" : root.label(sink)
    readonly property string inputLabel: source === null ? "" : root.label(source)

    // NODE's audio, or null for no node, a node that is no audio node, or
    // one PipeWire removed, whose object reads as null until the next
    // snapshot drops it.
    function audioOf(node) {
        try {
            return node && node.audio ? node.audio : null;
        } catch (e) {
            return null;
        }
    }

    // NODE's property KEY as a string, "" while the node is unbound or
    // lacks it.
    function property(node, key) {
        const props = node.properties;
        return props !== null && props !== undefined && typeof props[key] === "string" ? props[key] : "";
    }

    function label(node) {
        return String(node.description || node.nickname || node.name);
    }

    // The output named NAME: the default sink, or another of the snapshot;
    // null for none.
    function outputNamed(name) {
        if (name === sinkName) return sink;
        const row = root.outputs.find(r => r.name === name);
        return row === undefined ? null : row.node;
    }

    function row(node) {
        return { name: String(node.name), label: root.label(node), node: node };
    }

    function refresh() {
        const all = Pipewire.nodes.values.filter(n => n !== null && n.audio !== null);
        root.nodes = all;
        root.links = Pipewire.linkGroups.values.filter(g => g !== null && g.source !== null && g.target !== null)
            .map(g => ({ source: String(g.source.name), target: String(g.target.name) }));
        root.outputs = all.filter(n => !n.isStream && n.isSink).map(root.row);
        root.inputs = all.filter(n => !n.isStream && !n.isSink).map(root.row);
    }

    // Set NODE's volume to VALUE, a share of one: never below silent, and
    // above full only as a step from a level above full leaves it
    // (SoundLogic.stepped); a slider's value is never above full. A node
    // that went changes nothing, so a drag held on a sink that went away
    // is dropped.
    function setNodeVolume(node, value) {
        const audio = root.audioOf(node);
        if (audio === null) return false;
        audio.volume = Math.max(0, value);
        return true;
    }

    function setNodeMuted(node, muted) {
        const audio = root.audioOf(node);
        if (audio === null) return false;
        audio.muted = muted;
        return true;
    }

    // Every output and output stream of the snapshot, never the derived
    // volumeSink: binding a node changes its properties, which the volume
    // target reads.
    PwObjectTracker {
        objects: [root.sink, root.source].concat(root.nodes.filter(n => n.isSink))
    }

    Timer {
        id: settle
        interval: 75
        onTriggered: root.refresh()
    }

    Connections {
        target: Pipewire.nodes
        function onValuesChanged() { settle.restart(); }
    }

    Connections {
        target: Pipewire.linkGroups
        function onValuesChanged() { settle.restart(); }
    }

    Component.onCompleted: refresh()
}
