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
    function open(payloadJson) { problem = ""; }
    function close() {}
    function invoke(name) {
        const reply = shell.ipc.call(name, "");
        problem = reply === "ok" ? "" : reply.indexOf("capture=missing") >= 0 ? "Install the missing tools to use this action." : "Capture is busy. Wait for it to finish.";
        if (reply === "ok") shell.ipc.call("toggle", "");
        return reply;
    }
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
            Button { width: parent.width; text: root.recording ? "Stop recording" : root.capture.available.record === false ? "Recording unavailable" : "Record screen"; iconName: "video"; enabled: root.capture.phase !== "stopping"; onClicked: root.invoke("record") }
            Button { width: parent.width; text: "Copy text from area"; iconName: "text-cursor"; onClicked: root.invoke("text") }
            Label { role: "hint"; text: "Screenshot folder" }
            TextField { id: folder; width: parent.width; text: root.shell === null ? "" : root.shell.settings.folder; placeholderText: "Pictures / Screenshots"; onAccepted: root.save("folder", text) }
            Button { width: parent.width; text: "Save screenshot folder"; variant: "secondary"; onClicked: root.save("folder", folder.text) }
            Label { role: "hint"; text: "Recording folder" }
            TextField { id: recordings; width: parent.width; text: root.shell === null ? "" : root.shell.settings.recordFolder; placeholderText: "Videos / Screencasts"; onAccepted: root.save("recordFolder", text) }
            Button { width: parent.width; text: "Save recording folder"; variant: "secondary"; onClicked: root.save("recordFolder", recordings.text) }
            Label { role: "hint"; text: "Recording audio" }
            Select {
                width: parent.width
                model: ["None", "Desktop", "Microphone", "Desktop and microphone"]
                currentIndex: root.shell === null ? 0 : root.shell.manifest.schema.audio.options.indexOf(root.shell.settings.audio)
                onActivated: index => { root.save("audio", root.shell.manifest.schema.audio.options[index]); currentIndex = Qt.binding(() => root.shell.manifest.schema.audio.options.indexOf(root.shell.settings.audio)); }
            }
            Label { width: parent.width; visible: text !== ""; role: "hint"; text: root.problem; wrapMode: Text.Wrap }
        }
    }
}
