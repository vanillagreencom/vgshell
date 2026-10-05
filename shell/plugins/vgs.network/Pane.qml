import QtQuick
import qs.Commons
import qs.Ui

FocusScope {
    id: root
    focus: true
    property var shell: null
    property var payload: ({})
    readonly property Item initialFocus: body.initialFocus
    implicitWidth: Theme.size.window.width
    implicitHeight: body.implicitHeight
    function open(payloadJson) { payload = payloadJson ? JSON.parse(payloadJson) : {}; body.open(); }
    function close() { body.close(); }
    NetworkBody { id: body; objectName: "network-body"; width: root.width; shell: root.shell; expanded: true }
}
