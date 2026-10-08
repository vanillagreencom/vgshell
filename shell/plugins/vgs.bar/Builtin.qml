import QtQuick
import qs.Ui

// The bar model owns this wrapper and its content. The core supplies its
// shared drag frame and visual placement, while the registration name stays fixed.
BarWidget {
    id: root

    required property string name
    required property Item barItem
    property var release: null

    bar: barItem
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

    Loader {
        id: content
        anchors.fill: parent
        sourceComponent: root.name === "center-clock" ? clock : workspaces
        Component { id: clock; Clock { bar: root.barItem } }
        Component { id: workspaces; Workspaces { bar: root.barItem } }
    }

    Component.onCompleted: release = barItem.shell.builtins.register(name, root)
    Component.onDestruction: if (release !== null) release()
}
