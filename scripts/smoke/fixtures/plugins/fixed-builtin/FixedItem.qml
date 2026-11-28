import QtQuick
import qs.Commons
import qs.Ui

// The fixture supplies a stable label at the size of a normal bar reading.
Item {
    id: root

    required property string label

    implicitWidth: button.width
    implicitHeight: Theme.bar.height

    BarItem {
        id: button
        anchors.centerIn: parent
        text: root.label
    }
}
