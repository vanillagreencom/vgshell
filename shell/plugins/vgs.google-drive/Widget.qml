import QtQuick
import qs.Commons
import qs.Ui
import "GoogleDriveLogic.js" as Logic

// The Google Drive icon in the bar. It draws the status the service
// publishes and runs nothing itself: nothing until a folder pair exists,
// then the headline's icon and tone (GoogleDriveLogic.headline, which the
// window and the Settings page also read), calm while the sync is fine,
// with the count of files to review and a spinner while a sync runs. The
// tooltip's title is the headline; its lines name each folder pair by its
// label and state, and the last sync's time in the shell's one wording of
// a past moment (Timestamp); it never shows a file name or an account. A
// click opens or closes the Google Drive window.
BarWidget {
    id: widget

    readonly property var cloud: shell === null ? undefined : shell.status.values.cloud
    readonly property var view: Logic.widgetView(cloud, Time.now.getTime())
    readonly property var tip: Logic.widgetTooltip(cloud, Time.now.getTime(), Timestamp.text)

    visible: !view.hidden
    implicitWidth: view.hidden ? 0 : button.implicitWidth
    implicitHeight: barSize

    function toneColor(tone) {
        switch (tone) {
        case "calm": return Theme.bar.foreground;
        case "warning": return Theme.color.warning;
        case "danger": return Theme.color.danger;
        default: throw new Error("google-drive widget: tone " + JSON.stringify(tone) + " is not one of calm, warning, danger");
        }
    }

    // Open or close the Google Drive window; answers the window host's reply.
    function toggle() {
        const reply = shell.surfaces.toggle("window", "{}");
        if (reply !== "ok") console.warn("google-drive widget: window " + reply);
        return reply;
    }

    BarItem {
        id: button
        anchors.centerIn: parent
        label: "Google Drive"
        iconName: widget.view.icon
        spinning: widget.view.spinning
        count: widget.view.badge
        tone: widget.toneColor(widget.view.tone)
        tooltip: widget.tip.title
        tooltipDetails: widget.tip.details
        onClicked: widget.toggle()
    }
}
