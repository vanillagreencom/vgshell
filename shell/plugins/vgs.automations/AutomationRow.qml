import QtQuick
import qs.Commons
import qs.Ui
import "AutomationsLogic.js" as Engine
import "AutomationsViewLogic.js" as View

ListItem {
    id: root

    required property var row
    property int index: 0
    property Item cursorItem: null

    signal openRequested()
    signal duplicateRequested()
    signal removeRequested()
    signal runRequested()
    signal cancelRequested()
    signal toggleRequested(bool enabled)

    width: parent ? parent.width : implicitWidth
    text: row.name
    iconName: row.enabled ? "calendar-check" : "calendar-x"
    secondary: row.pending !== null ? "Waiting for network" : row.summary
    secondaryWraps: true
    cursor: cursorItem
    onClicked: root.openRequested()
    trailing: [
        Column {
            id: lastColumn
            // As wide as its widest reading, so the summary keeps the rest,
            // up to panel.sm, where the network explanation wraps.
            width: Math.min(Theme.size.panel.sm, Math.max(nextLabel.implicitWidth, explanation.visible ? explanation.implicitWidth : 0, lastRun.visible ? Theme.space.xs * 2 + lastLabel.implicitWidth : 0))
            spacing: Theme.row.lineGap
            anchors.verticalCenter: parent.verticalCenter
            Label { id: nextLabel; width: parent.width; role: "itemHint"; color: root.lit ? Theme.listItem.selectedForeground : Theme.text.itemHint.color; text: (root.row.pending !== null ? "Due " : "Next ") + View.formatWhen(root.row.pending !== null ? root.row.pending.dueAt : root.row.nextRun); horizontalAlignment: Text.AlignRight; wrapMode: Text.Wrap }
            Label {
                id: explanation
                width: parent.width
                role: "itemHint"
                color: root.lit ? Theme.listItem.selectedForeground : Theme.text.itemHint.color
                text: View.networkExplanation(root.row.pending)
                visible: text !== ""
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.Wrap
            }
            Row {
                id: lastRun
                visible: root.row.pending === null
                anchors.right: parent.right
                spacing: Theme.space.xs
                Rectangle {
                    width: Theme.space.xs
                    height: width
                    radius: Theme.radius.full
                    color: root.row.lastRun === null ? Theme.color.textFaint : root.row.lastRun.tone === "danger" ? Theme.color.danger : root.row.lastRun.tone === "success" ? Theme.color.success : root.row.lastRun.tone === "warning" ? Theme.color.warning : Theme.color.textFaint
                    anchors.verticalCenter: parent.verticalCenter
                }
                Label { id: lastLabel; width: Math.min(implicitWidth, lastColumn.width - Theme.space.xs * 2); role: "itemHint"; text: View.lastRunText(root.row.lastRun, Engine); elide: Text.ElideRight }
            }
        },
        Switch {
            size: "sm"
            checked: root.row.enabled
            anchors.verticalCenter: parent.verticalCenter
            onToggled: {
                checked = Qt.binding(() => root.row.enabled);
                root.toggleRequested(!root.row.enabled);
            }
        },
        IconButton {
            iconName: root.row.pending !== null ? "x" : "play"
            label: root.row.pending !== null ? "Cancel waiting run" : "Run now"
            size: "sm"
            onClicked: root.row.pending !== null ? root.cancelRequested() : root.runRequested()
        },
        IconButton {
            id: moreButton
            iconName: "ellipsis"
            label: "More actions"
            size: "sm"
            onClicked: rowMenu.toggle(KeyNavLogic.opener(moreButton))
            Menu {
                id: rowMenu
                MenuItem { text: "Duplicate"; iconName: "copy"; onTriggered: root.duplicateRequested() }
                MenuItem { text: "Remove"; iconName: "trash"; onTriggered: root.removeRequested() }
            }
        }
    ]
}
