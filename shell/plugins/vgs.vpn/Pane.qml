import QtQuick
import qs.Commons
import qs.Ui

// The VPN section of the System window, mounted in the holder of the
// `panes` capability, which draws its title and scrolls it: VpnBody.qml
// with this device, the accounts, the other devices and the poll setting.
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
