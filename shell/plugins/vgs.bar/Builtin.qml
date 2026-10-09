import QtQuick
import qs.Commons
import qs.Ui

// Repeater stacks its delegates as siblings (Qt Quick Repeater reference).
// Keep this Loader under the bar; only its loaded wrapper changes visual parent.
Loader {
    id: root

    required property string name
    required property Item barItem
    // "gap" or "separator" for a spacer the user added, else "".
    readonly property string family: barItem.familyOf(name)

    sourceComponent: BarWidget {
        id: wrapper
        property var release: null

        bar: root.barItem
        Accessible.name: root.barItem.builtinLabel(root.name)
        frameHideText: root.family !== "" ? "Remove " + root.family : "Hide"
        frameHideIcon: root.family !== "" ? "trash" : "eye-off"
        implicitWidth: content.implicitWidth
        implicitHeight: content.implicitHeight

        Loader {
            id: content
            anchors.fill: parent
            sourceComponent: root.name === "center-clock" ? clock
                : root.family === "gap" ? gap
                : root.family === "separator" ? separator
                : workspaces
            Component { id: clock; Clock { bar: root.barItem } }
            Component { id: workspaces; Workspaces { bar: root.barItem } }
            // Empty room the width of the spacer's gap token.
            Component {
                id: gap
                Item {
                    implicitWidth: Theme.bar.spacer.gap
                    implicitHeight: Theme.bar.height
                }
            }
            // A vertical line with the spacer's inset either side.
            Component {
                id: separator
                Item {
                    implicitWidth: 2 * Theme.bar.spacer.inset + Theme.divider.thickness
                    implicitHeight: Theme.bar.height

                    Rectangle {
                        x: Theme.bar.spacer.inset
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.divider.thickness
                        height: Theme.bar.spacer.height
                        color: Theme.bar.spacer.line
                    }
                }
            }
        }

        Component.onCompleted: release = root.barItem.shell.builtins.register(root.name, wrapper)
        Component.onDestruction: if (release !== null) release()
    }
}
