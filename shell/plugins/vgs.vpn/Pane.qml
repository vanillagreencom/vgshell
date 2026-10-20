import QtQuick
import qs.Commons
import qs.Ui

// Saved VPN profiles and their update setting in System Settings.
FocusScope {
    id: root

    property var shell: null
    property var payload: ({})
    readonly property Item initialFocus: body.initialFocus

    implicitWidth: Theme.size.window.width
    implicitHeight: body.implicitHeight
    focus: true

    function open(payloadJson) {
        payload = payloadJson ? JSON.parse(payloadJson) : {};
        body.open();
    }
    function close() { body.close(); }

    VpnBody {
        id: body
        width: root.width
        shell: root.shell
        expanded: true
    }
}
