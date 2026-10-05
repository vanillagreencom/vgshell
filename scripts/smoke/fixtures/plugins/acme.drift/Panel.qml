import QtQuick
Item {
    property var shell: null
    implicitWidth: 200
    implicitHeight: 120
    function open(payloadJson) {}
    function close() {}
    Mark { anchors.centerIn: parent }
}
