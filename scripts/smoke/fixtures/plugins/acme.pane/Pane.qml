import QtQuick
import qs.Commons
import qs.Ui

FocusScope {
    id: root
    property var shell: null
    property string payload: ""
    readonly property string manifestId: shell === null ? "" : shell.manifest.id
    readonly property string label: shell === null ? "" : String(shell.settings.label)
    readonly property string shellKeys: shell === null ? "" : Object.keys(shell).sort().join(",")
    readonly property Item initialFocus: editButton
    property var idleDisposer: null
    property int closes: 0
    property bool pending: false
    property int saves: 0
    property int discards: 0
    readonly property Item footer: SaveBar {
        parent: null
        width: parent === null ? 0 : parent.width
        dirty: root.pending
        onSave: { root.saves += 1; root.pending = false; }
        onDiscard: { root.discards += 1; root.pending = false; }
    }

    function open(payloadJson) {
        payload = payloadJson || "";
        if (idleDisposer === null) idleDisposer = shell.idle.watch(600, idle => {});
    }

    function close() {
        payload = "closed";
        closes += 1;
    }
    function setLabel(value) { return shell.configure.set("label", value); }
    function stageChange() {
        pending = true;
        editButton.forceActiveFocus(Qt.TabFocusReason);
    }
    function scrollBody() {
        for (let item = root.parent; item !== null; item = item.parent) {
            if (typeof item.scrollBy !== "function") continue;
            item.scrollBy(100);
            return String(item.contentY);
        }
        return "no-scroll-area";
    }

    implicitWidth: Theme.size.window.width
    implicitHeight: Theme.size.control.lg * 3
    focus: true

    Column {
        anchors.fill: parent
        spacing: Theme.stack.row
        Label { role: "h3"; text: "Pane fixture" }
        Label { role: "body"; text: root.label }
        Button {
            id: editButton
            text: "Pane edit"
            onClicked: root.setLabel("pane-edited")
        }
    }
}
