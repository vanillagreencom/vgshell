import QtQuick
import qs.Commons
import qs.Ui
import "UsageView.js" as View

// Each signed-in and visible account in a card of its own. Compact view
// shows account identity and one text row per limit. Full view adds meters
// and the provider detail fields the helper received. Opening the panel asks
// the service for a new check; the panel draws status alone.
Item {
    id: root
    property var shell: null
    property Item initialFocus: refreshButton
    readonly property var usage: shell === null || shell.status.values.usage === undefined ? null : shell.status.values.usage
    readonly property var rows: View.panel(usage, Time.now.getTime(), shell === null ? null : shell.settings)
    readonly property bool fullView: shell !== null && shell.settings.view !== "compact"

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
            text: root.usage === null ? "Checking your sign-ins." : "No visible account is signed in. Check your AI Usage settings."
        }

        Repeater {
            model: root.rows
            Card {
                required property var modelData
                width: layout.contentWidth

                Label { role: "label"; text: modelData.title }
                Label { visible: text !== ""; role: "hint"; text: modelData.email }
                Label { visible: root.fullView && text !== ""; role: "hint"; text: modelData.detail }
                Label {
                    width: parent.width
                    visible: text !== ""
                    role: "hint"
                    wrapMode: Text.Wrap
                    text: modelData.note
                    color: Theme.badge.tone.warning.foreground
                }

                Section {
                    visible: modelData.windows.length > 0
                    title: root.fullView ? "Limits" : ""
                    rowSpacing: Theme.card.gap
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
                                    text: root.fullView ? modelData.text : modelData.text + " · " + modelData.reset
                                    color: modelData.tone === "warning" ? Theme.badge.tone.warning.foreground : Theme.color.text
                                }
                            }
                            ProgressBar { visible: root.fullView; width: parent.width; value: Math.min(modelData.percent, 100) / 100 }
                            Label { visible: root.fullView; role: "hint"; text: modelData.reset }
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
