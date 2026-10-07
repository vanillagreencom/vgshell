import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "UsageView.js" as View

// Each signed-in and visible account in a card of its own: the provider,
// the account's email and one row per limit with its time to reset. Full
// view adds a meter under each limit and the provider detail fields the
// helper received, and each card says how long ago its figures were read.
// The pane is at most half its output's height. Opening the panel reads
// nothing: Check now asks the service for a new check, and the panel draws
// status alone.
Item {
    id: root
    property var shell: null
    property Item initialFocus: refreshButton
    readonly property var usage: shell === null || shell.status.values.usage === undefined ? null : shell.status.values.usage
    readonly property var rows: View.panel(usage, Time.now.getTime(), shell === null ? null : shell.settings)
    readonly property bool fullView: shell !== null && shell.settings.view !== "compact"
    // The output the panel's popup window occupies, a ShellScreen whose
    // height is logical, or null before the panel has a window.
    readonly property var host: QsWindow.window
    readonly property var output: host === null || host === undefined || host.screen === null || host.screen === undefined ? null : host.screen
    // The tallest the pane draws: half its output, or panel.maxHeight with
    // no output yet.
    readonly property real heightCap: output === null ? Theme.size.panel.maxHeight : output.height * Theme.size.window.heightShare

    function refresh() {
        const reply = shell.ipc.call("refresh", "");
        if (reply !== "ok") console.warn("ai-usage: panel refresh " + reply);
        return reply;
    }
    function open(payloadJson) {}
    function close() {}

    implicitWidth: Theme.size.panel.md
    implicitHeight: layout.implicitHeight

    Surface { anchors.fill: parent }

    Pane {
        id: layout
        anchors.fill: parent
        container: "panel"
        fitToContent: true
        maximumHeight: root.heightCap
        title: "AI Usage"

        Label {
            width: layout.contentWidth
            visible: root.rows.length === 0
            role: "body"
            wrapMode: Text.Wrap
            text: root.usage === null ? "Checking your sign-ins." : "No visible account is signed in. Check your AI Usage settings."
        }

        Repeater {
            model: root.rows
            Card {
                required property var modelData
                width: layout.contentWidth

                Label { role: "label"; text: modelData.title }
                Label { visible: text !== ""; role: "hint"; text: modelData.account }
                Label { visible: text !== ""; role: "hint"; text: modelData.checked }
                Label { visible: root.fullView && text !== ""; role: "hint"; text: modelData.detail }
                Label {
                    width: parent.width
                    visible: text !== ""
                    role: "hint"
                    wrapMode: Text.Wrap
                    text: modelData.note
                    color: modelData.noteTone === "warning" ? Theme.badge.tone.warning.foreground : Theme.text.hint.color
                }

                Column {
                    visible: modelData.windows.length > 0
                    width: parent.width
                    spacing: root.fullView ? Theme.stack.inline : Theme.row.lineGap
                    Repeater {
                        model: modelData.windows
                        Column {
                            required property var modelData
                            width: parent.width
                            spacing: Theme.row.lineGap

                            Item {
                                width: parent.width
                                implicitHeight: Math.max(limit.implicitHeight, share.implicitHeight)
                                Label {
                                    id: limit
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - share.width - Theme.stack.inline
                                    elide: Text.ElideRight
                                    role: "body"
                                    text: modelData.label
                                }
                                Row {
                                    id: share
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.stack.inline
                                    Label {
                                        visible: text !== ""
                                        anchors.verticalCenter: parent.verticalCenter
                                        role: "hint"
                                        text: modelData.reset
                                    }
                                    Label {
                                        anchors.verticalCenter: parent.verticalCenter
                                        role: "body"
                                        text: modelData.text
                                        color: modelData.tone === "warning" ? Theme.badge.tone.warning.foreground
                                            : modelData.started ? Theme.color.text : Theme.text.hint.color
                                    }
                                }
                            }
                            ProgressBar { visible: root.fullView; width: parent.width; value: Math.min(modelData.percent, 100) / 100 }
                        }
                    }
                }

                Section {
                    visible: root.fullView && modelData.details.length > 0
                    title: "Details"
                    rowSpacing: Theme.row.lineGap
                    Repeater {
                        model: modelData.details
                        Item {
                            required property var modelData
                            width: parent.width
                            implicitHeight: Math.max(detailName.implicitHeight, detailValue.implicitHeight)
                            Label { id: detailName; role: "hint"; text: modelData.label }
                            Label { id: detailValue; anchors.right: parent.right; role: "body"; text: modelData.value }
                        }
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
