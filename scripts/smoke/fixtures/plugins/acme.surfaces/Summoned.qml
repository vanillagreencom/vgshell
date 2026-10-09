import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui
Item {
    id: root
    property var shell: null
    property alias initialFocus: initialScope
    property int opened: 0
    property string lastPayload: ""
    property bool sizing: false
    property int sizingRows: 7
    implicitWidth: 200
    implicitHeight: 120
    // A payload may name a file close() creates, and may ask open() to throw.
    function open(payloadJson) {
        const payload = JSON.parse(payloadJson);
        opened += 1;
        lastPayload = payloadJson;
        sizing = payload.sizing === true;
        sizingRows = payload.rows === undefined ? 7 : payload.rows;
        if (payload.fail === true) throw new Error("probe open refused");
    }
    function close() {
        const marker = JSON.parse(lastPayload).closeMarker;
        if (marker !== undefined) shell.run.detached(["touch", marker]);
    }
    function geometry() { const p = mapToGlobal(0, 0); return JSON.stringify([p.x, p.y, width, height]); }
    function menuHere(payload) { return shell.surfaces.summon("menu", payload || "{}", menuAnchor); }
    function moveAnchor() { container.y += 20; return "ok"; }
    function hideAnchor() { container.visible = false; return "ok"; }
    function anchorGeometry() { const p = menuAnchor.mapToGlobal(0, 0); return JSON.stringify([p.x, p.y, menuAnchor.width, menuAnchor.height]); }
    // The real window host receives the same small request while the Pane
    // owns its title, source rows and footer, as in the shipped Updates.
    Pane {
        id: sizingPane
        visible: root.sizing
        anchors.fill: parent
        container: "window"
        title: "Window sizing"
        subtitle: Label { width: parent.width; text: "Sources"; role: "hint" }
        Column {
            width: parent.width
            spacing: Theme.stack.row
            Repeater {
                model: root.sizingRows
                ListItem { required property int index; width: parent.width; text: "Source " + index; secondary: "Ready" }
            }
        }
        footer: Button { text: "Refresh" }
    }
    FocusScope {
        id: initialScope
        width: 120
        height: 40
        anchors.centerIn: parent
        T.Control {
            id: focusTarget
            property string text: "Initial focus"
            anchors.fill: parent
            focus: true
            focusPolicy: Qt.StrongFocus
            background: Item { FocusRing { target: focusTarget } }
        }
    }
    Button {
        text: "Next"
        x: 120
        y: 80
    }
    Item {
        id: container
        x: 40
        y: 20
        Item { id: menuAnchor; x: 20; y: 10; width: 20; height: 20 }
    }
}
