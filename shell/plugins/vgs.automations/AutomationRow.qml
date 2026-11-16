import QtQuick
import qs.Ui
import "AutomationsLogic.js" as Engine
import "AutomationsViewLogic.js" as View

// One automation of the list, a ContentRow: a click opens its editor, and
// the row carries a state and a removing action. Under its name stand its
// schedule, its last run with its outcome's mark or, while a run waits for
// the network, that wait with the warning mark, and when it runs next or is
// due. Its switch and Run now stand at its end; Duplicate and Remove are in
// its row menu.
ContentRow {
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

    readonly property bool waiting: row.pending !== null

    width: parent ? parent.width : implicitWidth
    text: row.name
    iconName: row.enabled ? "calendar-check" : "calendar-x"
    secondary: row.summary
    secondaryWraps: true
    // A skipped run's "neutral" tone draws no mark.
    status: waiting ? View.networkExplanation(row.pending) || "Waiting for network" : View.lastRunText(row.lastRun, Engine)
    statusTone: waiting ? "warning" : row.lastRun === null || row.lastRun.tone === "neutral" ? "" : row.lastRun.tone
    detail: (waiting ? "Due " : "Next ") + View.formatWhen(waiting ? row.pending.dueAt : row.nextRun)
    menuActions: [{ key: "duplicate", text: "Duplicate", iconName: "copy" }, { key: "remove", text: "Remove", iconName: "trash" }]
    clickable: true
    cursor: cursorItem
    onClicked: root.openRequested()
    onMenuActionTriggered: action => action.key === "remove" ? root.removeRequested() : root.duplicateRequested()
    trailing: [
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
            iconName: root.waiting ? "x" : "play"
            label: root.waiting ? "Cancel waiting run" : "Run now"
            size: "sm"
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.waiting ? root.cancelRequested() : root.runRequested()
        }
    ]
}
