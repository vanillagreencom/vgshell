import QtQuick
import qs.Ui

// Repeater stacks its delegates as siblings (Qt Quick Repeater reference).
// Keep this Loader under the bar; only its loaded wrapper changes visual parent.
Loader {
    id: root

    required property string name
    required property Item barItem
    sourceComponent: BarWidget {
        id: wrapper
        property var release: null

        bar: root.barItem
        Accessible.name: root.barItem.builtinLabels[root.name]
        implicitWidth: content.implicitWidth
        implicitHeight: content.implicitHeight

        Loader {
            id: content
            anchors.fill: parent
            sourceComponent: root.name === "center-clock" ? clock : workspaces
            Component { id: clock; Clock { bar: root.barItem } }
            Component { id: workspaces; Workspaces { bar: root.barItem } }
        }

        Component.onCompleted: release = root.barItem.shell.builtins.register(root.name, wrapper)
        Component.onDestruction: if (release !== null) release()
    }
}
