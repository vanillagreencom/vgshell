import QtQuick
import qs.Commons
import qs.Ui

// One tray icon in the manage popup: the app's icon and name, then its Pin
// and Hide toggles, each checked while the setting names the app. A toggle
// asks its owner to change the setting and draws the setting again, so it
// never shows a choice the setting does not hold.
Item {
    id: root

    property string title: ""
    property string icon: ""
    property bool pinned: false
    property bool hidden: false

    signal pinToggled()
    signal hideToggled()

    implicitHeight: Math.max(Theme.row.height, toggles.implicitHeight)

    TrayIcon {
        id: glyph
        anchors.verticalCenter: parent.verticalCenter
        source: root.icon
        size: Theme.icon.size.md
        tint: Theme.color.text
    }

    Label {
        anchors.verticalCenter: parent.verticalCenter
        x: glyph.width + Theme.row.gap
        width: toggles.x - x - Theme.row.gap
        text: root.title
        elide: Text.ElideRight
    }

    Row {
        id: toggles
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.control.gap

        ToggleButton {
            text: "Pin"
            size: "sm"
            checked: root.pinned
            onClicked: {
                root.pinToggled();
                checked = Qt.binding(() => root.pinned);
            }
        }
        ToggleButton {
            text: "Hide"
            size: "sm"
            checked: root.hidden
            onClicked: {
                root.hideToggled();
                checked = Qt.binding(() => root.hidden);
            }
        }
    }
}
