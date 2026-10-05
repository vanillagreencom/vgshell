import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "UpdatesLogic.js" as Logic

// The Updates window: where updates stand, one row per source the service
// published with its count, the packages it lists when opened and its own
// Update when it has updates, and a footer with Update everything over
// Refresh, the last check's time and the last run's log. It draws the
// status the service publishes and runs nothing itself: Refresh asks the
// service's `check` through the plugin's own IPC, and every update and the
// log open the plugin's floating TUIs (UpdatesLogic.tuiRequest). The
// window asks to be `size.panel.lg` wide and `size.panel.maxHeight` tall,
// or the room its screen leaves when that is less, and the sources scroll
// in whatever size Hyprland gives it after. An Escape nothing here takes
// goes on to the window host, which closes the window. It takes no payload.
FocusScope {
    id: root

    // The core assigns the plugin's scoped shell object after creation, and
    // again when the plugin's settings change.
    property var shell: null
    readonly property var screen: shell === null ? null : shell.screens.current
    readonly property var values: shell === null ? ({}) : shell.status.values
    readonly property var view: Logic.widgetView(values, false)
    readonly property var rows: Logic.windowRows(values)
    // The refusal the last action was answered with, "" for none.
    property string problem: ""
    property Item initialFocus: sections.firstFocus

    function open(payloadJson) {
        problem = "";
    }
    function close() {}

    // The time of MS in the locale's short format, with the date when
    // WITHDATE holds.
    function formatWhen(ms, withDate) {
        const when = new Date(ms);
        return withDate ? when.toLocaleString(Qt.locale(), Locale.ShortFormat) : when.toLocaleTimeString(Qt.locale(), Locale.ShortFormat);
    }

    // Open the TUI for ACTION (`all`, `source` with SOURCE, or `log`);
    // answers the capability's reply.
    function run(action, source) {
        const request = Logic.tuiRequest(action, source);
        return answered(shell.tui.run(request.name, request.args));
    }

    // Ask the service for a check now; answers its reply, `started` or
    // `queued`.
    function refresh() { return answered(shell.ipc.call("check", "")); }

    function answered(reply) {
        problem = Logic.replyLine(reply);
        if (problem !== "") console.warn("updates window: " + reply);
        return reply;
    }

    implicitWidth: Math.floor(Math.min(Theme.size.panel.lg, OverlayState.room(screen).width))
    implicitHeight: Math.floor(Math.min(Theme.size.panel.maxHeight, OverlayState.room(screen).height))
    focus: true

    // One inset box: the heading, the scrolling sources, and a footer
    // with Update everything, Refresh and the last log that stays in view
    // while the sources scroll; Pane draws the divider over it while more
    // sources lie below.
    Pane {
        id: layout
        anchors.fill: parent
        container: "window"

        header: [
            Column {
                width: layout.contentWidth
                spacing: Theme.row.lineGap

                Label {
                    role: "h3"
                    text: "Updates"
                }
                Row {
                    width: parent.width
                    spacing: Theme.control.gap
                    Spinner {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.view.spinning
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - (root.view.spinning ? Theme.spinner.size + parent.spacing : 0)
                        role: "hint"
                        text: Logic.summaryText(root.values)
                        color: root.view.tone === "warning" ? Theme.color.warning : Theme.color.textMuted
                        wrapMode: Text.Wrap
                    }
                }
                Label {
                    width: parent.width
                    role: "hint"
                    visible: text !== ""
                    text: root.problem
                    color: Theme.color.danger
                    wrapMode: Text.Wrap
                }
            }
        ]

        // The sources, one group of rows.
        Column {
            id: sections
            property Item firstFocus: null
            width: layout.contentWidth
            spacing: Theme.stack.row

            Repeater {
                id: rowsRepeater
                model: ScriptModel {
                    values: root.rows
                    objectProp: "key"
                }

                Disclosure {
                    id: source
                    required property var modelData
                    required property int index
                    // The column, not `parent`, which is null while the
                    // repeater tears the row down.
                    width: sections.width
                    text: modelData.label
                    secondary: modelData.secondary
                    iconName: modelData.icon
                    expandable: modelData.lines.length > 0 || modelData.more !== ""
                    Component.onCompleted: if (index === 0) sections.firstFocus = focusItem
                    // The count stands beside an Update button only for a
                    // source that can update.
                    trailing: [
                        Badge {
                            anchors.verticalCenter: parent.verticalCenter
                            size: "md"
                            text: source.modelData.badge
                            tone: source.modelData.badgeTone
                        },
                        Button {
                            id: update
                            anchors.verticalCenter: parent.verticalCenter
                            visible: source.modelData.updatable
                            variant: "secondary"
                            size: "sm"
                            text: "Update"
                            onClicked: root.run("source", source.modelData.source)
                        }
                    ]

                    Repeater {
                        model: source.modelData.lines
                        Label {
                            required property string modelData
                            width: parent.width
                            role: "itemCode"
                            text: modelData
                            elide: Text.ElideRight
                        }
                    }
                    Label {
                        width: parent.width
                        visible: text !== ""
                        role: "hint"
                        text: source.modelData.more
                    }
                }
            }
        }

        Label {
            width: layout.contentWidth
            visible: root.rows.length === 0
            role: "hint"
            text: "No update results yet"
            wrapMode: Text.Wrap
        }

        footer: [
            Column {
                width: layout.contentWidth
                spacing: Theme.stack.group

                Button {
                    width: parent.width
                    variant: "primary"
                    text: "Update everything"
                    iconName: "download"
                    onClicked: root.run("all")
                }

                Item {
                    width: parent.width
                    height: Math.max(refreshButton.implicitHeight, logButton.implicitHeight)

                    Button {
                        id: refreshButton
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        variant: "tertiary"
                        text: "Refresh"
                        iconName: "refresh-cw"
                        onClicked: root.refresh()
                    }
                    Label {
                        anchors.left: refreshButton.right
                        anchors.right: logButton.left
                        anchors.leftMargin: Theme.control.gap
                        anchors.rightMargin: Theme.control.gap
                        y: topForCapCenter(parent.height)
                        horizontalAlignment: Text.AlignHCenter
                        role: "hint"
                        text: Logic.checkedText(root.values.lastCheck, Time.now.getTime(), root.formatWhen)
                        elide: Text.ElideRight
                    }
                    Button {
                        id: logButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        variant: "tertiary"
                        text: "Open last log"
                        iconName: "scroll-text"
                        onClicked: root.run("log")
                    }
                }
            }
        ]
    }
}
