import QtQuick
import qs.Commons
import qs.Ui
import "UsageView.js" as View

// Each signed-in account in a card of its own: its name, email and plan,
// and a meter and reset time for each plan limit it reports. Opening the panel asks the service
// for a new check; the panel draws status alone.
Item {
    id: root
    property var shell: null
    property Item initialFocus: refreshButton
    readonly property var usage: shell === null || shell.status.values.usage === undefined ? null : shell.status.values.usage
    readonly property var rows: View.panel(usage, Time.now.getTime())

    function refresh() {
        const reply = shell.ipc.call("refresh", "");
        if (reply !== "ok") console.warn("ai-usage: panel refresh " + reply);
        return reply;
    }
    function open(payloadJson) { refresh(); }
    function close() {}

    implicitWidth: Theme.size.panel.md
    implicitHeight: layout.implicitHeight

    Surface { anchors.fill: parent }

    Pane {
        id: layout
        anchors.fill: parent
        container: "panel"
        fitToContent: true
        maximumHeight: Theme.size.panel.maxHeight
        title: "AI Usage"

        Label {
            width: layout.contentWidth
            visible: root.rows.length === 0
            role: "body"
            wrapMode: Text.Wrap
            text: root.usage === null ? "Checking your sign-ins." : "No account is signed in. Sign in from Plugins."
        }

        Repeater {
            model: root.rows
            Card {
                required property var modelData
                width: layout.contentWidth

                Label { role: "label"; text: modelData.title }
                Label { visible: text !== ""; role: "hint"; text: modelData.detail }
                Label {
                    width: parent.width
                    visible: text !== ""
                    role: "hint"
                    wrapMode: Text.Wrap
                    text: modelData.note
                    color: Theme.badge.tone.warning.foreground
                }
                Repeater {
                    model: modelData.windows
                    Column {
                        required property var modelData
                        width: parent.width
                        spacing: Theme.row.lineGap

                        Item {
                            width: parent.width
                            implicitHeight: Math.max(limit.implicitHeight, share.implicitHeight)
                            Label { id: limit; role: "body"; text: modelData.label }
                            Label {
                                id: share
                                anchors.right: parent.right
                                role: "body"
                                text: modelData.text
                                color: modelData.tone === "warning" ? Theme.badge.tone.warning.foreground : Theme.color.text
                            }
                        }
                        ProgressBar { width: parent.width; value: Math.min(modelData.percent, 100) / 100 }
                        Label { role: "hint"; text: modelData.reset }
                    }
                }
            }
        }

        footer: [
            Button {
                id: refreshButton
                variant: "secondary"
                text: "Check now"
                iconName: "refresh-cw"
                onClicked: root.refresh()
            }
        ]
    }
}
