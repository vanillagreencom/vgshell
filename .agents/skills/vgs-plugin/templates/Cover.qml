import QtQuick
import qs.Commons

// __NAME__ cover: set `shown` true only while it must cover every screen.
// The core assigns `shell` and `screen` after creation. Colours come from Theme.
Item {
    id: root

    property var shell: null
    property var screen: null
    property bool shown: false

    Rectangle {
        anchors.fill: parent
        color: Theme.color.background
    }
}
