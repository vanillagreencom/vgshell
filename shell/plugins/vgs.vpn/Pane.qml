import QtQuick
import qs.Commons
import qs.Ui

// System Settings › VPN: the profiles with Remove profile, Import a VPN
// file, the empty and NetworkManager-absent states and the Updates section
// (VpnBody with `expanded`).
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
