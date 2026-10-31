import QtQuick
import qs.Ui
import "AutomationsLogic.js" as Engine
import "AutomationsViewLogic.js" as View

ListItem {
    id: root

    required property var row
    property Item cursorItem: null

    signal openRequested(string transcript)

    width: parent ? parent.width : implicitWidth
    text: row.name
    iconName: ""
    secondary: View.historySecondary(row, Engine)
    cursor: cursorItem
    onClicked: root.openRequested(row.transcript)
    trailing: [
        Badge { text: View.outcomeLabel(root.row.outcome); tone: root.row.tone; iconName: root.row.icon; size: "sm"; anchors.verticalCenter: parent.verticalCenter }
    ]
}
