import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "UpdatesLogic.js" as Logic

// The Updates window: where updates stand, how the last update run ended,
// one row per source the service
// published with its count, the packages it lists when opened and its own
// Update when it has updates, unique details, and a footer with Update all,
// Refresh and the last run's log. The heading keeps the check time beside
// the summary, in Timestamp's wording. The title row ends with
// Package review settings, which opens the Packages page, so
// the link takes no height from the sources. It draws the
// status the service publishes and runs nothing itself: Refresh asks the
// service's `check` through the plugin's own IPC. Update all asks
// that service to offer the reboot-notice choice before its TUI; a source
// update and the log open their TUIs directly (UpdatesLogic.tuiRequest). The
// window asks to be `size.panel.lg` wide and fits its content up to
// `size.panel.maxHeight`, or the room its screen leaves when that is less, and the sources scroll
// in whatever size Hyprland gives it after. An Escape nothing here takes
// goes on to the window host, which closes the window. A payload may carry
// the refusal from a setup terminal's attempt to start the update.
FocusScope {
    id: root

    // The core assigns the plugin's scoped shell object after creation, and
    // again when the plugin's settings change.
    property var shell: null
    readonly property var screen: shell === null ? null : shell.screens.current
    readonly property var published: shell === null ? ({}) : shell.status.values
    property string requestState: "idle"
    readonly property var values: requestState === "opening" ? Object.assign({}, published, { checking: true })
        : requestState === "failed" ? Object.assign({}, published, { checking: false, admission: "unavailable" }) : published
    readonly property var view: Logic.widgetView(values, false)
    readonly property var rows: Logic.windowRows(values)
    // How the last update run ended (UpdatesLogic.runOutcome), or null.
    readonly property var outcome: values.lastRun ?? null
    // The refusal the last action was answered with, "" for none.
    property string problem: ""
    property Item initialFocus: sections.firstFocus
    onPublishedChanged: if (requestState === "opening" && published.checking === true) requestState = "idle"

    function open(payloadJson) {
        problem = "";
        refresh();
        const payload = JSON.parse(payloadJson);
        if (typeof payload.problem === "string") problem = payload.problem;
    }
    function close() {}

    // Open the TUI for ACTION (`all`, `source` with SOURCE, or `log`);
    // answers the capability's reply.
    function run(action, source) {
        const request = Logic.tuiRequest(action, source);
        const reply = answered(action === "all" ? shell.ipc.call("update-all", "") : shell.tui.run(request.name, request.args));
        // Hiding destroys this summoned instance; finish its reply first.
        if (reply === "ok" && action !== "log") shell.surfaces.hide("window");
        return reply;
    }

    // Ask the service for a check now; answers its reply, `started` or
    // `queued`.
    function refresh() {
        requestState = "opening";
        // ipc.call invokes the registered handler synchronously (plugin API,
        // IPC). Its first status write masks the old readings before return.
        const reply = answered(shell.ipc.call("check", ""));
        if (reply !== "started" && reply !== "queued") {
            requestState = "failed";
        } else if (published.checking === true) requestState = "idle";
        return reply;
    }

    function answered(reply) {
        problem = Logic.replyLine(reply);
        if (problem !== "") console.warn("updates window: " + reply);
        return reply;
    }

    implicitWidth: Math.floor(Math.min(Theme.size.panel.lg, OverlayState.room(screen).width))
    // Pane measures content; the native host requests that initial height
    // and the pane fills the size the compositor gives it after mapping.
    // Implicit size flows up, assigned size down:
    // https://quickshell.org/docs/v0.3.1/guide/size-position/.
    implicitHeight: Math.floor(layout.implicitHeight)
    focus: true

    // The sources' cursor, in the body's scrolling content with the rows:
    // the plate under the pointer, as every list's (ListItem.lit).
    ListCursor {
        id: plate
        parent: layout.scrollArea.contentItem
    }

    // One inset box: the heading, the scrolling sources, and a footer
    // with Update all, Refresh and the last log that stays in view
    // while the sources scroll; Pane draws the divider over it while more
    // sources lie below.
    Pane {
        id: layout
        anchors.fill: parent
        container: "window"
        fitToContent: true
        maximumHeight: Math.floor(Math.min(Theme.size.panel.maxHeight, OverlayState.windowRoom(root.screen).height))

        title: "Updates"
        // The title slot's implicit height is its children's rect, and the
        // row's height reads it: the holder takes the link's own height, so
        // the link's centred place never feeds back into the row (an anchored
        // centre was a binding loop in tst_list_hover).
        titleContent: [
            Item {
                width: parent.width
                implicitWidth: reviewLink.implicitWidth
                implicitHeight: reviewLink.implicitHeight

                RowAction {
                    id: reviewLink
                    anchors.right: parent.right
                    y: Math.round((layout.titleRowHeight - height) / 2)
                    text: "Package review settings"
                    onClicked: root.answered(shell.run.detached(["vgshell", "pkg", "review-settings"]))
                }
            }
        ]
        subtitle: [
            Column {
                width: layout.contentWidth
                spacing: layout.bodySpacing

                Row {
                    width: parent.width
                    spacing: Theme.control.gap
                    Spinner {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.view.spinning
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - (root.view.spinning ? Theme.spinner.size + parent.spacing : 0)
                        Label {
                            width: Math.min(implicitWidth, parent.width - checkedLabel.width)
                            role: "hint"
                            text: Logic.windowSummaryText(root.values)
                            color: root.view.tone === "warning" ? Theme.color.warning : Theme.color.text
                            wrapMode: Text.Wrap
                        }
                        Label {
                            id: checkedLabel
                            visible: !root.view.spinning && typeof root.values.lastCheck === "number"
                            width: visible ? implicitWidth : 0
                            role: "hint"
                            text: visible ? " · " + Timestamp.text(root.values.lastCheck, Time.now.getTime()) : ""
                            color: Theme.color.textMuted
                        }
                    }
                }
                // How the last update run failed or stopped. The service
                // clears a restart-only result after the restart. Open last log
                // is its action, so the notice has none.
                Callout {
                    width: parent.width
                    visible: root.outcome !== null && root.outcome.ended !== "finished"
                    tone: visible && root.outcome.ended === "stopped" ? "warning" : "danger"
                    title: visible ? root.outcome.title : ""
                    text: visible ? root.outcome.text : ""
                    plain: true
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

            Label {
                width: parent.width
                visible: Logic.lastKnown(root.values) && root.rows.length > 0
                role: "hint"
                text: "Last known results"
            }

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
                    cursor: plate
                    text: modelData.label
                    iconName: modelData.icon
                    expandable: modelData.detail !== "" || modelData.lines.length > 0 || modelData.more !== ""
                    // Unique details open with the row.
                    expanded: modelData.detail !== ""
                    Component.onCompleted: if (index === 0) sections.firstFocus = focusItem
                    // The count stands beside an Update button only for a
                    // source that can update.
                    trailing: [
                        Badge {
                            anchors.verticalCenter: parent.verticalCenter
                            size: "md"
                            text: source.modelData.badge
                            tone: source.modelData.badgeTone
                            visible: !source.modelData.spinning
                        },
                        Spinner {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: source.modelData.spinning
                        },
                        RowAction {
                            id: update
                            anchors.verticalCenter: parent.verticalCenter
                            visible: source.modelData.updatable
                            text: source.modelData.actionText === undefined ? "Update" : source.modelData.actionText
                            onClicked: root.run("source", source.modelData.source)
                        }
                    ]

                    Label {
                        width: parent.width
                        visible: text !== ""
                        role: "hint"
                        text: source.modelData.detail
                        wrapMode: Text.Wrap
                    }
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
            visible: root.rows.length === 0 && !root.view.spinning
            role: "hint"
            text: "No update results yet"
            wrapMode: Text.Wrap
        }

        Spinner {
            visible: root.rows.length === 0 && root.view.spinning
        }

        footer: [
            Row {
                width: layout.contentWidth
                spacing: Theme.control.gap

                Button {
                    width: parent.width - refreshButton.width - logButton.width - 2 * parent.spacing
                    variant: "primary"
                    text: "Update all"
                    iconName: "download"
                    disabledReason: Logic.updateDisabledReason(root.values)
                    onClicked: root.run("all")
                }
                IconButton {
                    id: refreshButton
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Refresh"
                    iconName: "refresh-cw"
                    disabledReason: root.view.spinning ? "An update check is running. Wait for it to finish." : ""
                    onClicked: root.refresh()
                }
                IconButton {
                    id: logButton
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Open last log"
                    iconName: "scroll-text"
                    onClicked: root.run("log")
                }
            }
        ]
    }
}
