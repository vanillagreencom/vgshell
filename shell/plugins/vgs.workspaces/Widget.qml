import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "WorkspacesLogic.js" as Logic

// Workspace numbers, one BarItem pill each: its label plus
// `bar.item.paddingX` a side, never narrower than it is tall,
// `bar.item.height` tall, the lit one filled with `bar.active`, on the
// bar's vertical centre. WorkspacesLogic.pills chooses the pills from the
// shared Workspaces singleton, which follows Hyprland's events, and the
// workspace rules the `hyprland` capability reads on each reload; nothing
// here reads Hyprland on a timer. A click focuses a workspace through the
// widget's own compositor capability, which checks the argument and judges
// the reply.
BarWidget {
    id: root

    readonly property string screenName: shell === null || shell.screens.current === null ? "" : shell.screens.current.name
    readonly property bool thisDisplayOnly: setting("thisDisplayOnly", false) === true
    readonly property bool showEmpty: setting("showEmpty", false) === true
    readonly property var pills: Logic.pills(Workspaces.items,
        showEmpty && shell !== null ? shell.hyprland.workspaceRules : null,
        Workspaces.monitors, thisDisplayOnly ? screenName : "", Workspaces.focusedId)
    // The pill ids as text. `pills` is a new list on every focus change,
    // and a Repeater given a new model rebuilds every delegate; a string
    // property notifies only when its value differs (Qt 6.12.0
    // src/qml/qml/qqmlvmemetaobject.cpp QQmlVMEMetaObject::metaCall), so
    // the model changes only with the set of pills, and each pill keeps its
    // item, and BarItem's colour fade, as the lit one moves.
    readonly property string pillKey: JSON.stringify(pills.map(pill => pill.id))

    implicitWidth: row.implicitWidth
    implicitHeight: barSize

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: Theme.bar.item.gap

        Repeater {
            model: JSON.parse(root.pillKey)

            BarItem {
                id: pill
                required property int modelData

                Layout.alignment: Qt.AlignVCenter
                text: String(modelData)
                active: root.pills.some(entry => entry.id === pill.modelData && entry.active)
                onClicked: root.shell.compositor.focusWorkspace(pill.modelData)
            }
        }
    }
}
