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
    // The language presets, and the saved value when Settings set codes no
    // preset names, such as eng+deu, so the select shows it.
    readonly property var languageChoices: {
        const presets = shell === null ? [] : shell.manifest.schema.ocrLanguages.presets;
        const current = setting("ocrLanguages", "");
        return current === "" || presets.some(preset => preset.value === current) ? presets : presets.concat([{ label: current, value: current }]);
    }
    readonly property var qualityChoices: [
        { label: "Medium", value: "medium" },
        { label: "High", value: "high" },
        { label: "Very high", value: "very_high" },
        { label: "Ultra", value: "ultra" }
    ]
    // Every target stays choosable and pressable while a tool it needs is
    // missing: the press reaches the service, which offers the install
    // notice, and the panel says why the action did not start.
    readonly property var screenshotTargets: [
        { text: "Area", icon: "scan", action: "screenshot-area" },
        { text: "Window", icon: "app-window", action: "screenshot-window" },
        { text: "Display", icon: "monitor", action: "screenshot-display" },
        { text: "All", icon: "monitor-check", action: "screenshot-all" }
    ]
    readonly property var recordTargets: [
        { text: "Area", icon: "scan", action: "record" },
        { text: "Window", icon: "app-window", action: "record-window" },
        { text: "Display", icon: "monitor", action: "record-display" },
        { text: "Picker", icon: "screen-share", action: "record-portal" }
    ]
    readonly property var currentTargets: mode === "Screenshot" ? screenshotTargets : mode === "Record" ? recordTargets : []
    readonly property int currentTargetIndex: mode === "Record" ? recordTargetIndex : screenshotTargetIndex
    readonly property var currentTarget: currentTargets.length === 0 ? null : currentTargets[currentTargetIndex]
    // The action the primary button hands the service.
    readonly property string primaryActionName: recording ? "record" : mode === "Text" ? "text" : currentTarget === null ? "" : currentTarget.action
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
                    enabled: root.capture.phase !== "stopping"
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
                            model: root.languageChoices
                            textRole: "label"
                            currentIndex: root.choiceIndex(root.languageChoices, root.setting("ocrLanguages", ""))
                            onActivated: index => {
                                root.save("ocrLanguages", root.languageChoices[index].value);
                                currentIndex = Qt.binding(() => root.choiceIndex(root.languageChoices, root.setting("ocrLanguages", "")));
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
                    RowAction {
                        visible: root.languagesOffered
                        text: visible ? root.languagesRow.action.label : ""
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
