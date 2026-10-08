import QtQuick
import qs.Commons

// __NAME__: a replacement bar. The core assigns `shell` and `screen` after
// creation, mounts every plugin widget into the three section containers
// declared below and keeps them current. The core owns each child's
// position and size and each section's width. This file owns section
// placement and spacing, the bar's colours and font. Each
// container spans the bar's height so a widget is centred in it.
Item {
    id: bar

    property var shell: null
    property var screen: null

    readonly property color foreground: Theme.bar.foreground
    readonly property color background: Theme.bar.background
    readonly property string fontFamily: Theme.text.bar.family
    readonly property int barSize: Theme.bar.height

    readonly property Item leftSection: left
    readonly property Item centerSection: center
    readonly property Item rightSection: right

    Item { id: left; readonly property real spacing: Theme.bar.gap; anchors { left: parent.left; leftMargin: Theme.bar.padding; top: parent.top; bottom: parent.bottom } }
    Item { id: center; readonly property real spacing: Theme.bar.gap; anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; bottom: parent.bottom } }
    Item { id: right; readonly property real spacing: Theme.bar.gap; anchors { right: parent.right; rightMargin: Theme.bar.padding; top: parent.top; bottom: parent.bottom } }
}
