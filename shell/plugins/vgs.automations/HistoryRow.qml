import QtQuick
import qs.Ui
import "AutomationsLogic.js" as Engine
import "AutomationsViewLogic.js" as View

// One run of the history, a NavigationRow: its one click opens the run's
// transcript, and its outcome badge stands before the chevron.
NavigationRow {
    id: root

    required property var row
    property Item cursorItem: null

    signal openRequested(string transcript)

    width: parent ? parent.width : implicitWidth
    text: row.name
    secondary: View.historySecondary(row, Engine)
    cursor: cursorItem
    onClicked: root.openRequested(row.transcript)
    accessories: [
        Badge { text: View.outcomeLabel(root.row.outcome); tone: root.row.tone; iconName: root.row.icon; size: "sm" }
    ]
}
