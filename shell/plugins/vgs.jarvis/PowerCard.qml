import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// The card of a held Reboot or Shut down (PowerWait), centred on the
// focused screen's passive layer: Jarvis saves its work, the computer
// restarts when it is done or at the bound, and one button restarts it now.
// The countdown is the wait's own.
Item {
    id: root
    property var screen: null
    property var wait: null
    readonly property bool shown: wait !== null && wait.verb !== "" && screen !== null && screen.name === wait.focusedOutput
    readonly property bool restart: wait !== null && wait.verb === "reboot"
    readonly property int remaining: wait === null ? 0 : wait.remaining
    readonly property var inputItems: shown ? [info, now] : []

    visible: shown

    GlassSurface {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * Theme.dialog.margin, Theme.dialog.width)
        height: content.implicitHeight
        standard: Theme.dialog

        Pane {
            id: content
            anchors.fill: parent
            container: "dialog"
            fitToContent: true
            settingsGear: false
            title: "Jarvis is saving its work"
            titleRole: Theme.dialog.titleRole
            titleWrapMode: Text.Wrap

            RowLayout {
                width: content.contentWidth
                spacing: Theme.stack.inline
                Label {
                    Layout.fillWidth: true
                    role: Theme.dialog.bodyRole
                    text: (root.restart ? "The computer restarts" : "The computer shuts down") + " when Jarvis is done, or in "
                        + root.remaining + (root.remaining === 1 ? " second." : " seconds.")
                    wrapMode: Text.Wrap
                }
                InfoButton {
                    id: info
                    Layout.alignment: Qt.AlignTop
                    title: root.restart ? "Saving before a restart" : "Saving before a shutdown"
                    info: "Jarvis gets one minute to save its work. After that minute, the computer "
                        + (root.restart ? "restarts" : "shuts down") + " even if Jarvis did not finish, so a session that does not answer cannot stop the "
                        + (root.restart ? "restart." : "shutdown.")
                }
            }
            Item {
                width: content.contentWidth
                implicitHeight: now.implicitHeight
                // keyboard-path: choosing Reboot or Shut down in the launcher
                // again asks `power` again, which skips the wait the same way.
                Button {
                    id: now
                    anchors.right: parent.right
                    text: root.restart ? "Restart now" : "Shut down now"
                    onClicked: root.wait.proceedNow()
                }
            }
        }
    }
}
