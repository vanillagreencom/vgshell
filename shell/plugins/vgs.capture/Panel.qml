import QtQuick
import qs.Commons
import qs.Ui

// Every action, including a setting change, goes through the service's IPC.
Item {
    id: root
    property var shell: null
    property Item initialFocus: screenshot
    property string problem: ""
    readonly property var capture: shell === null || shell.status.values.capture === undefined ? ({ phase: "idle", available: {} }) : shell.status.values.capture
    readonly property bool recording: capture.phase === "recording" || capture.phase === "stopping"
    readonly property var values: shell === null ? ({}) : shell.status.values
    readonly property var audioChoices: values.audioSources === undefined ? [] : values.audioSources
    readonly property var cameraChoices: [{ label: "First camera found", value: "" }].concat(values.cameras === undefined ? [] : values.cameras)
    readonly property var languagesRow: shell === null ? null : shell.status.rows.find(row => row.key === "languages") || null
    readonly property var recordActions: [
        { name: "record", text: "Record area", icon: "video" },
        { name: "record-window", text: "Record window", icon: "app-window" },
        { name: "record-display", text: "Record selected display", icon: "monitor" },
        { name: "record-output", text: "Record focused display", icon: "monitor-play" },
        { name: "record-portal", text: "Record with the screen picker", icon: "screen-share" }
    ]
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
    // One item per extra audio source; a new item takes the lowest free name.
    function toggleSource(value, on) {
        const items = root.shell.settings.audioSources.filter(item => item.source !== value);
        if (on) {
            let n = 1;
            while (items.some(item => item.name === "source-" + n)) n++;
            items.push({ name: "source-" + n, source: value });
        }
        return save("audioSources", items);
    }
    function installLanguages() { return shell.status.act("languages"); }
    function schemaOption(key, index) { return root.shell.manifest.schema[key].options[index]; }
    function optionIndex(key) { return root.shell === null ? 0 : root.shell.manifest.schema[key].options.indexOf(root.shell.settings[key]); }
    function save(key, value) {
        const reply = shell.ipc.call("setting", JSON.stringify({ key: key, value: value }));
        problem = reply === "ok" ? "" : "The setting could not be saved.";
        return reply;
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
        header: [ Label { role: "h3"; text: "Capture" } ]
        Column {
            width: layout.contentWidth
            spacing: Theme.stack.row
            Button { id: screenshot; width: parent.width; text: "Screenshot focused display"; iconName: "camera"; onClicked: root.invoke("screenshot") }
            Button { width: parent.width; text: "Screenshot area"; iconName: "scan"; onClicked: root.invoke("screenshot-area") }
            Button { width: parent.width; text: "Screenshot window"; iconName: "app-window"; onClicked: root.invoke("screenshot-window") }
            Button { width: parent.width; text: "Screenshot selected display"; iconName: "monitor"; onClicked: root.invoke("screenshot-display") }
            Button { width: parent.width; text: "Screenshot all displays"; iconName: "camera"; onClicked: root.invoke("screenshot-all") }
            Switch {
                width: parent.width
                text: "Click to select a window or display"
                checked: root.shell !== null && root.shell.settings.smart
                onClicked: { root.save("smart", checked); checked = Qt.binding(() => root.shell.settings.smart); }
            }
            Field {
                width: parent.width
                label: "Screenshot result"
                Select {
                    width: parent.width
                    model: ["Save and copy", "Copy only", "Save only"]
                    currentIndex: root.shell === null ? 0 : root.shell.manifest.schema.processing.options.indexOf(root.shell.settings.processing)
                    onActivated: index => { root.save("processing", root.shell.manifest.schema.processing.options[index]); currentIndex = Qt.binding(() => root.shell.manifest.schema.processing.options.indexOf(root.shell.settings.processing)); }
                }
            }
            Switch {
                width: parent.width
                text: "Include pointer"
                checked: root.shell !== null && root.shell.settings.cursor
                onClicked: { root.save("cursor", checked); checked = Qt.binding(() => root.shell.settings.cursor); }
            }
            Field {
                width: parent.width
                label: "Screenshot delay"
                hint: root.shell === null ? "" : root.shell.settings.delay + " seconds"
                Slider {
                    width: parent.width
                    from: root.shell === null ? 0 : root.shell.manifest.schema.delay.min
                    to: root.shell === null ? 0 : root.shell.manifest.schema.delay.max
                    stepSize: root.shell === null ? 1 : root.shell.manifest.schema.delay.step
                    value: root.shell === null ? 0 : root.shell.settings.delay
                    function commitSetting() { root.save("delay", Math.round(value)); value = Qt.binding(() => root.shell.settings.delay); }
                    onMoved: if (!pressed) commitSetting()
                    onPressedChanged: if (!pressed) commitSetting()
                }
            }
            Field {
                width: parent.width
                label: "Capture time limit"
                hint: root.shell === null ? "" : root.shell.settings.timeout + " seconds"
                Slider {
                    width: parent.width
                    from: root.shell === null ? 1 : root.shell.manifest.schema.timeout.min
                    to: root.shell === null ? 1 : root.shell.manifest.schema.timeout.max
                    stepSize: root.shell === null ? 1 : root.shell.manifest.schema.timeout.step
                    value: root.shell === null ? 1 : root.shell.settings.timeout
                    function commitSetting() { root.save("timeout", Math.round(value)); value = Qt.binding(() => root.shell.settings.timeout); }
                    onMoved: if (!pressed) commitSetting()
                    onPressedChanged: if (!pressed) commitSetting()
                }
            }
            Button { width: parent.width; visible: root.recording; text: "Stop recording"; iconName: "circle-stop"; enabled: root.capture.phase !== "stopping"; onClicked: root.invoke("record") }
            Repeater {
                model: root.recordActions
                Button {
                    required property var modelData
                    width: parent.width
                    visible: !root.recording
                    text: root.capture.available[modelData.name] === false ? modelData.text + " (unavailable)" : modelData.text
                    iconName: modelData.icon
                    onClicked: root.invoke(modelData.name)
                }
            }
            Button { width: parent.width; text: "Copy text from area"; iconName: "text-cursor"; onClicked: root.invoke("text") }
            Label { role: "hint"; text: "Screenshot folder" }
            TextField { id: folder; width: parent.width; text: root.shell === null ? "" : root.shell.settings.folder; placeholderText: "Pictures / Screenshots"; onAccepted: root.save("folder", text) }
            Button { width: parent.width; text: "Save screenshot folder"; variant: "secondary"; onClicked: root.save("folder", folder.text) }
            Label { role: "hint"; text: "Recording folder" }
            TextField { id: recordings; width: parent.width; text: root.shell === null ? "" : root.shell.settings.recordFolder; placeholderText: "Videos / Screencasts"; onAccepted: root.save("recordFolder", text) }
            Button { width: parent.width; text: "Save recording folder"; variant: "secondary"; onClicked: root.save("recordFolder", recordings.text) }
            Field {
                width: parent.width
                label: "Recording audio"
                Select {
                    width: parent.width
                    model: ["None", "Desktop", "Microphone", "Desktop and microphone"]
                    currentIndex: root.optionIndex("audio")
                    onActivated: index => { root.save("audio", root.schemaOption("audio", index)); currentIndex = Qt.binding(() => root.optionIndex("audio")); }
                }
            }
            Label { role: "hint"; visible: root.audioChoices.length > 0; text: "Extra audio sources" }
            Repeater {
                model: root.audioChoices
                Switch {
                    required property var modelData
                    width: parent.width
                    text: modelData.label
                    checked: root.shell !== null && root.shell.settings.audioSources.some(item => item.source === modelData.value)
                    onClicked: { root.toggleSource(modelData.value, checked); checked = Qt.binding(() => root.shell.settings.audioSources.some(item => item.source === modelData.value)); }
                }
            }
            Field {
                width: parent.width
                label: "Recording quality"
                Select {
                    width: parent.width
                    model: ["Medium", "High", "Very high", "Ultra"]
                    currentIndex: root.optionIndex("quality")
                    onActivated: index => { root.save("quality", root.schemaOption("quality", index)); currentIndex = Qt.binding(() => root.optionIndex("quality")); }
                }
            }
            Field {
                width: parent.width
                label: "Video codec"
                Select {
                    width: parent.width
                    model: ["Automatic", "H.264", "HEVC", "AV1", "VP9"]
                    currentIndex: root.optionIndex("codec")
                    onActivated: index => { root.save("codec", root.schemaOption("codec", index)); currentIndex = Qt.binding(() => root.optionIndex("codec")); }
                }
            }
            Field {
                width: parent.width
                label: "Frames per second"
                hint: root.shell === null ? "" : String(root.shell.settings.frameRate)
                Slider {
                    width: parent.width
                    from: root.shell === null ? 1 : root.shell.manifest.schema.frameRate.min
                    to: root.shell === null ? 1 : root.shell.manifest.schema.frameRate.max
                    stepSize: root.shell === null ? 1 : root.shell.manifest.schema.frameRate.step
                    value: root.shell === null ? 1 : root.shell.settings.frameRate
                    function commitSetting() { root.save("frameRate", Math.round(value)); value = Qt.binding(() => root.shell.settings.frameRate); }
                    onMoved: if (!pressed) commitSetting()
                    onPressedChanged: if (!pressed) commitSetting()
                }
            }
            Switch {
                width: parent.width
                text: "Constant frame rate"
                checked: root.shell !== null && root.shell.settings.constantFrameRate
                onClicked: { root.save("constantFrameRate", checked); checked = Qt.binding(() => root.shell.settings.constantFrameRate); }
            }
            Switch {
                width: parent.width
                text: "Include pointer in recordings"
                checked: root.shell !== null && root.shell.settings.recordCursor
                onClicked: { root.save("recordCursor", checked); checked = Qt.binding(() => root.shell.settings.recordCursor); }
            }
            Switch {
                width: parent.width
                text: "Show the camera in recordings"
                checked: root.shell !== null && root.shell.settings.webcam
                onClicked: { root.save("webcam", checked); checked = Qt.binding(() => root.shell.settings.webcam); }
            }
            Field {
                width: parent.width
                label: "Camera"
                Select {
                    width: parent.width
                    model: root.cameraChoices
                    textRole: "label"
                    currentIndex: root.shell === null ? 0 : root.cameraChoices.findIndex(choice => choice.value === root.shell.settings.webcamDevice)
                    onActivated: index => { root.save("webcamDevice", root.cameraChoices[index].value); currentIndex = Qt.binding(() => root.cameraChoices.findIndex(choice => choice.value === root.shell.settings.webcamDevice)); }
                }
            }
            Switch {
                width: parent.width
                text: "Trim and level finished recordings"
                checked: root.shell !== null && root.shell.settings.postProcess
                onClicked: { root.save("postProcess", checked); checked = Qt.binding(() => root.shell.settings.postProcess); }
            }
            Field {
                width: parent.width
                label: "Text languages"
                Select {
                    width: parent.width
                    model: root.shell === null ? [] : root.shell.manifest.schema.ocrLanguages.presets
                    textRole: "label"
                    currentIndex: root.shell === null ? -1 : model.findIndex(preset => preset.value === root.shell.settings.ocrLanguages)
                    onActivated: index => { root.save("ocrLanguages", model[index].value); currentIndex = Qt.binding(() => model.findIndex(preset => preset.value === root.shell.settings.ocrLanguages)); }
                }
            }
            TextField { id: languages; width: parent.width; text: root.shell === null ? "" : root.shell.settings.ocrLanguages; placeholderText: "eng+deu"; onAccepted: root.save("ocrLanguages", text) }
            Button { width: parent.width; text: "Save text languages"; variant: "secondary"; onClicked: root.save("ocrLanguages", languages.text) }
            Label { width: parent.width; visible: text !== ""; role: "hint"; wrapMode: Text.Wrap; text: root.values.languages === undefined ? "" : root.values.languages.text }
            Button {
                width: parent.width
                visible: root.languagesRow !== null && root.languagesRow.action !== null && root.languagesRow.action.offered
                text: visible ? root.languagesRow.action.label : ""
                iconName: "languages"
                onClicked: root.installLanguages()
            }
            Label { width: parent.width; visible: text !== ""; role: "hint"; text: root.problem; wrapMode: Text.Wrap }
        }
    }
}
