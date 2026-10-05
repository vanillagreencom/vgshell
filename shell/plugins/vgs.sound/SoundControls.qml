import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "SoundLogic.js" as Logic

// The controls the flyout and the pane share, one key/value row each:
// Output and Input, each a device Select and a LevelSlider, with the
// input's level meter under them while `meter` holds, then one LevelSlider
// per app that plays, and the playing-apps line from the `streams` status,
// which offers pactl while it is missing. A device choice goes to the
// service through the plugin's own IPC, which makes the device the default
// and moves the playing apps; a volume or mute change goes to PipeWire
// through AUDIO. While PipeWire is not there the controls give way to an
// empty state. `firstFocus` is the output's Select.
Column {
    id: root

    property var shell: null
    property Audio audio: null
    // Whether the input's level meter draws and listens to PipeWire; the
    // pane holds it while it is open.
    property bool meter: false
    // Whether the playing-apps line draws while pactl is there.
    property bool streamsLine: true
    readonly property real step: shell === null ? 0 : Number(shell.settings.volumeStep) / 100
    readonly property var streams: shell === null || shell.status.values.streams === undefined ? null : shell.status.values.streams
    readonly property Item firstFocus: audio !== null && audio.available ? outputSelect : null
    // The sink a drag changes: the volume target when it began.
    property var held: null
    // The refusal the last request was answered with, "" for none.
    property string problem: ""

    spacing: Theme.stack.group

    // Make the device named NAME of KIND, `output` or `input`, the default.
    function choose(kind, name) {
        return answered(shell.ipc.call(kind, name));
    }

    function offerPactl() {
        return answered(shell.requirements.offer(["pactl"]));
    }

    function answered(reply) {
        const failed = Logic.replyFailed(reply);
        problem = failed ? "That did not work. Try again." : "";
        if (failed) console.warn("sound: " + reply);
        return reply;
    }

    EmptyState {
        width: root.width
        visible: root.audio !== null && !root.audio.available
        iconName: "volume-off"
        text: "Sound is not available. VGS connects again when PipeWire starts."
    }

    Section {
        title: "Output"
        visible: root.audio !== null && root.audio.available

        FormRow {
            width: parent.width
            label: "Device"
            Select {
                id: outputSelect
                readonly property int chosen: root.audio.outputs.findIndex(r => r.name === root.audio.sinkName)
                width: parent.width
                model: root.audio.outputs
                textRole: "label"
                currentIndex: chosen
                onActivated: index => {
                    currentIndex = Qt.binding(() => chosen);
                    root.choose("output", root.audio.outputs[index].name);
                }
            }
        }
        FormRow {
            width: parent.width
            label: "Volume"
            LevelSlider {
                width: parent.width
                iconName: Logic.levelIcon(true, root.audio.volume, root.audio.muted)
                buttonLabel: (root.audio.muted ? "Unmute" : "Mute") + " output"
                value: root.audio.volume
                text: Logic.levelText(root.audio.volume, root.audio.muted)
                stepSize: root.step
                enabled: root.audio.hasOutput
                onBegan: root.held = root.audio.volumeSink
                onMoved: value => root.audio.setNodeVolume(slider.pressed ? root.held : root.audio.volumeSink, value)
                onButtonClicked: root.audio.setNodeMuted(root.audio.volumeSink, !root.audio.muted)
            }
        }
    }

    Section {
        title: "Input"
        visible: root.audio !== null && root.audio.available

        FormRow {
            width: parent.width
            label: "Device"
            Select {
                readonly property int chosen: root.audio.inputs.findIndex(r => r.name === root.audio.sourceName)
                width: parent.width
                model: root.audio.inputs
                textRole: "label"
                currentIndex: chosen
                onActivated: index => {
                    currentIndex = Qt.binding(() => chosen);
                    root.choose("input", root.audio.inputs[index].name);
                }
            }
        }
        FormRow {
            width: parent.width
            label: "Volume"
            LevelSlider {
                width: parent.width
                iconName: Logic.inputIcon(true, root.audio.inputMuted)
                buttonLabel: (root.audio.inputMuted ? "Unmute" : "Mute") + " microphone"
                value: root.audio.inputVolume
                text: Logic.levelText(root.audio.inputVolume, root.audio.inputMuted)
                stepSize: root.step
                enabled: root.audio.hasInput
                onMoved: value => root.audio.setNodeVolume(root.audio.source, value)
                onButtonClicked: root.audio.setNodeMuted(root.audio.source, !root.audio.inputMuted)
            }
        }
        FormRow {
            width: parent.width
            label: "Level"
            visible: root.meter
            ProgressBar {
                width: parent.width
                value: peak.peak
            }
        }
    }

    Section {
        title: "Apps"
        visible: root.audio !== null && root.audio.available && root.audio.apps.length > 0

        Repeater {
            model: ScriptModel {
                values: root.audio.apps
                objectProp: "name"
            }
            FormRow {
                id: app
                required property var modelData
                // The app's audio, null once its node went and before the
                // next snapshot drops the row.
                readonly property var level: root.audio.audioOf(modelData.node)
                // The column's width, not `parent`'s, which is null while
                // the repeater tears the row down.
                width: root.width
                label: modelData.label
                LevelSlider {
                    readonly property real volume: app.level === null ? 0 : app.level.volume
                    readonly property bool muted: app.level !== null && app.level.muted
                    width: parent.width
                    iconName: Logic.levelIcon(true, volume, muted)
                    buttonLabel: (muted ? "Unmute " : "Mute ") + app.modelData.label
                    value: volume
                    text: Logic.levelText(volume, muted)
                    stepSize: root.step
                    enabled: app.level !== null
                    onMoved: value => root.audio.setNodeVolume(app.modelData.node, value)
                    onButtonClicked: root.audio.setNodeMuted(app.modelData.node, !muted)
                }
            }
        }
    }

    FormRow {
        width: root.width
        label: "Playing apps"
        visible: root.streams !== null && root.audio !== null && root.audio.available && (root.streamsLine || root.streams.action === true)
        Column {
            width: parent.width
            spacing: Theme.stack.inline
            Label {
                width: parent.width
                role: "hint"
                wrapMode: Text.Wrap
                text: root.streams === null ? "" : root.streams.text
            }
            Button {
                visible: root.streams !== null && root.streams.action === true
                text: "Install pactl"
                size: "sm"
                variant: "secondary"
                onClicked: root.offerPactl()
            }
        }
    }

    Label {
        width: root.width
        role: "hint"
        visible: root.problem !== ""
        text: root.problem
        color: Theme.color.danger
        wrapMode: Text.Wrap
    }

    PwNodePeakMonitor {
        id: peak
        node: root.audio === null ? null : root.audio.source
        enabled: root.meter && root.audio !== null && root.audio.hasInput
    }
}
