import QtQuick
import qs.Commons

FocusScope {
    id: root
    property var shell: null
    readonly property Item initialFocus: controls.firstFocus
    function open(payloadJson) {}
    function close() {}
    implicitWidth: Theme.size.window.width
    implicitHeight: controls.implicitHeight
    focus: true
    KeyboardControls { id: controls; width: root.width; shell: root.shell }
}
