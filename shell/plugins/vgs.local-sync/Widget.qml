import QtQuick
import qs.Commons
import qs.Ui
import "SyncLogic.js" as Logic

// The Local Sync item in the bar. It draws the `jobs` value the service
// publishes and runs nothing itself. Idle, the folder-sync icon in the
// bar's ink. While a job copies, the shared spinner in the info colour
// with the info state dot; at motion scale zero the spinner would stand
// still, so the icon stays with the dot. While a job's last copy failed,
// the icon in the danger colour with the danger dot. The label and the
// tooltip name the state and each job in it (SyncLogic.bar). A click opens
// or closes the Local Sync flyout under the item (Panel.qml).
BarWidget {
    id: widget

    readonly property var value: shell === null ? undefined : shell.status.values.jobs
    readonly property var cards: value === undefined || value === null ? [] : Logic.cards(value, Time.now.getTime(), Timestamp.text)
    readonly property var view: Logic.bar(cards)
    readonly property bool syncing: view.state === "syncing"

    implicitWidth: button.implicitWidth
    implicitHeight: barSize

    // Open or close the flyout under this widget; answers the panel host's
    // reply.
    function toggle() {
        const reply = shell.surfaces.toggle("panel", "{}", widget);
        if (reply !== "ok") console.warn("local-sync widget: panel " + reply);
        return reply;
    }

    BarItem {
        id: button
        anchors.centerIn: parent
        label: widget.view.label
        iconName: "folder-sync"
        spinning: widget.syncing && Theme.spinner.duration > 0
        spinnerColor: Theme.color.info
        stateDot: widget.view.failed ? "danger" : widget.syncing ? "info" : ""
        tone: widget.view.state === "failed" ? Theme.color.danger : Theme.bar.foreground
        tooltip: widget.view.tooltip
        tooltipDetails: widget.view.lines
        onClicked: widget.toggle()
    }
}
