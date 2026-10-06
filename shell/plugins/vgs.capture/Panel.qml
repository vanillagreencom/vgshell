import QtQuick
import qs.Commons
import qs.Ui

// The mode switch picks what to capture, the tiles pick its target, and one
// primary action runs it; a few options follow, and Settings holds the
// rest. Every action, including a setting change, goes through the
// service's IPC.
Item {
    id: root
    property var shell: null
    property Item initialFocus: primaryAction
    property string problem: ""
    property string mode: "Screenshot"
    // Each mode's own target, kept while the panel is open.
    property int screenshotTargetIndex: 0
    property int recordTargetIndex: 0
    readonly property var capture: shell === null || shell.status.values.capture === undefined ? ({ phase: "idle", available: {} }) : shell.status.values.capture
    readonly property bool recording: capture.phase === "recording" || capture.phase === "stopping"
    readonly property var values: shell === null ? ({}) : shell.status.values
    readonly property var languagesRow: shell === null ? null : shell.status.rows.find(row => row.key === "languages") || null
    readonly property bool languagesOffered: languagesRow !== null && languagesRow.action !== null && languagesRow.action.offered
    readonly property var modes: ["Screenshot", "Record", "Text"]
    readonly property int modeIndex: modes.indexOf(mode)
    readonly property var processingChoices: [
        { label: "Save and copy", value: "save-copy" },
        { label: "Copy only", value: "copy" },
        { label: "Save only", value: "save" }
    ]
    // The usual delays, and the saved one when Settings set another.
    readonly property var delayChoices: {
        const current = setting("delay", 0);
        const seconds = [0, 3, 5, 10];
        if (seconds.indexOf(current) < 0) seconds.push(current);
        seconds.sort((a, b) => a - b);
        return seconds.map(value => ({ label: value === 0 ? "None" : value + " seconds", value: value }));
    }
    readonly property var audioChoices: [
        { label: "None", value: "none" },
        { label: "Desktop", value: "desktop" },
        { label: "Microphone", value: "microphone" },
        { label: "Desktop and microphone", value: "both" }
    ]
    readonly property var qualityChoices: [
        { label: "Medium", value: "medium" },
        { label: "High", value: "high" },
        { label: "Very high", value: "very_high" },
        { label: "Ultra", value: "ultra" }
    ]
    readonly property var screenshotTargets: [
        { text: "Area", icon: "scan", action: "screenshot-area", available: actionAvailable("screenshot-area") },
        { text: "Window", icon: "app-window", action: "screenshot-window", available: actionAvailable("screenshot-window") },
        { text: "Display", icon: "monitor", action: "screenshot-display", available: actionAvailable("screenshot-display") },
        { text: "All", icon: "monitor-check", action: "screenshot-all", available: actionAvailable("screenshot-all") }
    ]
    readonly property var recordTargets: [
        { text: "Area", icon: "scan", action: "record", available: actionAvailable("record") },
        { text: "Window", icon: "app-window", action: "record-window", available: actionAvailable("record-window") },
        { text: "Display", icon: "monitor", action: "record-display", available: actionAvailable("record-display") },
        { text: "Picker", icon: "screen-share", action: "record-portal", available: actionAvailable("record-portal") }
    ]
    readonly property var currentTargets: mode === "Screenshot" ? screenshotTargets : mode === "Record" ? recordTargets : []
    readonly property int currentTargetIndex: mode === "Record" ? recordTargetIndex : screenshotTargetIndex
    readonly property var currentTarget: currentTargets.length === 0 ? null : currentTargets[currentTargetIndex]
    // The action the primary button hands the service.
    readonly property string primaryActionName: recording ? "record" : mode === "Text" ? "text" : currentTarget === null ? "" : currentTarget.action
    readonly property bool primaryAvailable: recording ? capture.phase !== "stopping" : actionAvailable(primaryActionName)
    readonly property string primaryText: recording ? "Stop recording" : mode === "Screenshot" ? "Take screenshot" : mode === "Record" ? "Start recording" : "Copy text"
    readonly property string primaryIcon: recording ? "circle-stop" : mode === "Screenshot" ? "camera" : mode === "Record" ? "video" : "scan-text"

    function open(payloadJson) {
        problem = "";
        if (shell !== null) shell.ipc.call("probe", "");
    }
    function close() {}
    function invoke(name) {
        const reply = shell.ipc.call(name, "");
        problem = reply === "ok" ? "" : reply.indexOf("capture=missing") >= 0 ? "Install the missing tools to use this action." : "Capture is busy. Wait for it to finish.";
        if (reply === "ok") shell.ipc.call("toggle", "");
        return reply;
    }
    function installLanguages() { return shell.status.act("languages"); }
    function setting(key, fallback) { return shell === null || shell.settings[key] === undefined ? fallback : shell.settings[key]; }
    function actionAvailable(name) { return name !== "" && capture.available[name] !== false; }
    function choiceIndex(choices, value) { return choices.findIndex(choice => choice.value === value); }
    function save(key, value) {
        const reply = shell.ipc.call("setting", JSON.stringify({ key: key, value: value }));
        problem = reply === "ok" ? "" : "The setting could not be saved.";
        return reply;
    }
    function chooseMode(index) {
        mode = modes[index];
        modeSwitch.currentIndex = Qt.binding(() => root.modeIndex);
    }
    function chooseTarget(index) {
        if (mode === "Record") recordTargetIndex = index;
        else screenshotTargetIndex = index;
        targetTiles.currentIndex = Qt.binding(() => root.currentTargetIndex);
    }

    implicitWidth: Theme.size.panel.md
    implicitHeight: layout.implicitHeight
    Surface { anchors.fill: parent }
    Pane {
        id: layout
        anchors.fill: parent
        container: "panel"
        fitToContent: true
        maximumHeight: Theme.size.panel.maxHeight
        title: "Capture"
        Column {
            width: layout.contentWidth
            spacing: Theme.stack.section

            SegmentedControl {
                id: modeSwitch
                width: parent.width
                model: root.modes
                currentIndex: root.modeIndex
                onActivated: index => root.chooseMode(index)
            }

            Column {
                width: parent.width
                spacing: Theme.stack.group
                TileGroup {
                    id: targetTiles
                    width: parent.width
                    visible: root.mode !== "Text"
                    enabled: !root.recording
                    model: root.currentTargets
                    currentIndex: root.currentTargetIndex
                    onActivated: index => root.chooseTarget(index)
                }
                Label {
                    width: parent.width
                    visible: root.mode === "Text"
                    role: "hint"
                    wrapMode: Text.Wrap
                    text: "Select an area. Its text goes to the clipboard."
                }
                Button {
                    id: primaryAction
                    width: parent.width
                    size: "lg"
                    variant: root.recording ? "danger" : "primary"
                    text: root.primaryText
                    iconName: root.primaryIcon
                    enabled: root.primaryAvailable
                    onClicked: root.invoke(root.primaryActionName)
                }
                Label {
                    width: parent.width
                    visible: text !== ""
                    role: "hint"
                    wrapMode: Text.Wrap
                    text: root.problem
                }
            }

            Column {
                width: parent.width
                spacing: Theme.stack.row
                SectionHeader { text: "Options" }

                Column {
                    width: parent.width
                    spacing: Theme.stack.row
                    visible: root.mode === "Screenshot"
                    FormRow {
                        width: parent.width
                        label: "After capture"
                        Select {
                            width: parent.width
                            model: root.processingChoices
                            textRole: "label"
                            currentIndex: root.choiceIndex(root.processingChoices, root.setting("processing", "save-copy"))
                            onActivated: index => {
                                root.save("processing", root.processingChoices[index].value);
                                currentIndex = Qt.binding(() => root.choiceIndex(root.processingChoices, root.setting("processing", "save-copy")));
                            }
                        }
                    }
                    FormRow {
                        width: parent.width
                        label: "Delay"
                        Select {
                            width: parent.width
                            model: root.delayChoices
                            textRole: "label"
                            currentIndex: root.choiceIndex(root.delayChoices, root.setting("delay", 0))
                            onActivated: index => {
                                root.save("delay", root.delayChoices[index].value);
                                currentIndex = Qt.binding(() => root.choiceIndex(root.delayChoices, root.setting("delay", 0)));
                            }
                        }
                    }
                    FormRow {
                        width: parent.width
                        label: "Show pointer"
                        Switch {
                            checked: root.setting("cursor", false)
                            onClicked: { root.save("cursor", checked); checked = Qt.binding(() => root.setting("cursor", false)); }
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.stack.row
                    visible: root.mode === "Record"
                    FormRow {
                        width: parent.width
                        label: "Audio"
                        Select {
                            width: parent.width
                            model: root.audioChoices
                            textRole: "label"
                            currentIndex: root.choiceIndex(root.audioChoices, root.setting("audio", "desktop"))
                            onActivated: index => {
                                root.save("audio", root.audioChoices[index].value);
                                currentIndex = Qt.binding(() => root.choiceIndex(root.audioChoices, root.setting("audio", "desktop")));
                            }
                        }
                    }
                    FormRow {
                        width: parent.width
                        label: "Quality"
                        Select {
                            width: parent.width
                            model: root.qualityChoices
                            textRole: "label"
                            currentIndex: root.choiceIndex(root.qualityChoices, root.setting("quality", "very_high"))
                            onActivated: index => {
                                root.save("quality", root.qualityChoices[index].value);
                                currentIndex = Qt.binding(() => root.choiceIndex(root.qualityChoices, root.setting("quality", "very_high")));
                            }
                        }
                    }
                    FormRow {
                        width: parent.width
                        label: "Show pointer"
                        Switch {
                            checked: root.setting("recordCursor", false)
                            onClicked: { root.save("recordCursor", checked); checked = Qt.binding(() => root.setting("recordCursor", false)); }
                        }
                    }
                    FormRow {
                        width: parent.width
                        label: "Camera"
                        Switch {
                            checked: root.setting("webcam", false)
                            onClicked: { root.save("webcam", checked); checked = Qt.binding(() => root.setting("webcam", false)); }
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.stack.row
                    visible: root.mode === "Text"
                    FormRow {
                        width: parent.width
                        label: "Language"
                        Select {
                            width: parent.width
                            model: root.shell === null ? [] : root.shell.manifest.schema.ocrLanguages.presets
                            textRole: "label"
                            currentIndex: model.findIndex(preset => preset.value === root.setting("ocrLanguages", ""))
                            onActivated: index => {
                                root.save("ocrLanguages", model[index].value);
                                currentIndex = Qt.binding(() => model.findIndex(preset => preset.value === root.setting("ocrLanguages", "")));
                            }
                        }
                    }
                    Label {
                        width: parent.width
                        visible: text !== "" && (root.languagesOffered || root.values.languages.tone !== "info")
                        role: "hint"
                        wrapMode: Text.Wrap
                        text: root.values.languages === undefined ? "" : root.values.languages.text
                    }
                    Button {
                        width: parent.width
                        visible: root.languagesOffered
                        variant: "secondary"
                        text: visible ? root.languagesRow.action.label : ""
                        iconName: "languages"
                        onClicked: root.installLanguages()
                    }
                }

                Label {
                    width: parent.width
                    role: "hint"
                    wrapMode: Text.Wrap
                    text: "More options are in Settings."
                }
            }
        }
    }
}
