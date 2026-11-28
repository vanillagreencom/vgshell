import QtQuick
import qs.Commons as Commons
import qs.Ui

// Repeater stacks its delegates as siblings (Qt Quick Repeater reference).
// Keep this Loader under the bar; only its loaded wrapper changes visual parent.
Loader {
    id: root

    required property string name
    required property Item barItem
    readonly property string family: barItem.familyOf(name)

    sourceComponent: BarWidget {
        id: wrapper
        property var release: null

        bar: root.barItem
        Accessible.name: root.barItem.familyLabels[root.family]
        frameHideText: "Remove " + root.family
        frameHideIcon: "trash"
        implicitWidth: content.implicitWidth
        implicitHeight: content.implicitHeight

        Loader {
            id: content
            anchors.fill: parent
            sourceComponent: root.family === "gap" ? gap : separator
            // Empty room the width of the spacer's gap token.
            Component {
                id: gap
                Item {
                    implicitWidth: Commons.Theme.bar.spacer.gap
                    implicitHeight: Commons.Theme.bar.height
                }
            }
            // A vertical line with the spacer's inset either side.
            Component {
                id: separator
                Item {
                    implicitWidth: 2 * Commons.Theme.bar.spacer.inset + Commons.Theme.divider.thickness
                    implicitHeight: Commons.Theme.bar.height

                    Rectangle {
                        x: Commons.Theme.bar.spacer.inset
                        anchors.verticalCenter: parent.verticalCenter
                        width: Commons.Theme.divider.thickness
                        height: Commons.Theme.bar.spacer.height
                        color: Commons.Theme.bar.spacer.line
                    }
                }
            }
        }

        Component.onCompleted: release = root.barItem.shell.builtins.register(root.name, wrapper)
        Component.onDestruction: if (release !== null) release()
    }
}
