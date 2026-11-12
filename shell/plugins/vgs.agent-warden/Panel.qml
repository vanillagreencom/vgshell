import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "ViewLogic.js" as View

// The Agent Warden flyout: a heading, one status sentence, one Callout for
// each item of the warden's status and each warn or danger cause of vsys's
// summary (View.rows), in vsys's words drawn as plain text, each with its
// actions as links under its text, which open vsys's TUI with the action's
// arguments; the agent group's memory meter when it is known; the line
// that says vsys found nothing, when it did; the one setup button a state
// that needs setting up offers: Set up opens the `setup` TUI, Start checks
// starts the warden's timer, and Install vsys raises the core's
// requirement notice; and a footer with the check time and Open vsys, which
// opens vsys's home. Every word comes from ViewLogic.js and every value
// from the service's published `detail`.
//
// A panel is built on summon and destroyed on hide, so its lifetime is one
// open: it holds the clock at seconds while it lives. The observation
// boundary is shell/plugins/vgs.agent-warden/README.md § How it works.
Item {
    id: root

    property var shell: null
    // The service's last derived state, null before it published one.
    readonly property var detail: shell === null || shell.status.values.detail === undefined ? null : shell.status.values.detail
    readonly property bool vsysMissing: shell === null || shell.requirements.missing.indexOf("vsys") !== -1
    readonly property real now: Time.now.getTime()
    readonly property var setupButton: detail === null ? null : View.setup(detail, vsysMissing)
    readonly property var footerLink: View.link(vsysMissing, setupButton)
    readonly property var memory: detail === null ? null : View.meter(detail.memory)
    // The rows change only with the detail, so they are not built again
    // each second.
    readonly property var rows: detail === null ? [] : View.rows(detail)
    // Why the last press did not hand off, "" when it did or before one.
    property string problem: ""
    property Item initialFocus: primaryButton.visible ? primaryButton : linkButton

    // Each open and close is reported to the service, which reads vsys's
    // summary for the flyout alone while no fresh status comes. A close
    // that finds the service gone, as when the plugin is disabled, needs
    // no answer, so only a refused open is logged.
    function open(payloadJson) {
        problem = "";
        Time.holdSeconds(root, true);
        if (shell === null) return;
        const reply = shell.ipc.call("panel", "open");
        if (reply !== "ok") console.warn("agent-warden: panel=open " + reply);
    }
    function close() {
        Time.holdSeconds(root, false);
        if (shell !== null) shell.ipc.call("panel", "closed");
    }
    Component.onDestruction: Time.holdSeconds(root, false)

    // Do ACTION, one of View.setup's or View.link's, or `item`, an item's
    // action, which opens the vsys TUI with ARGS; answers the capability's
    // reply. A press that handed off closes the flyout.
    function press(action, args) {
        let reply;
        switch (action) {
        case "open": reply = shell.tui.run("vsys", []); break;
        case "item": reply = shell.tui.run("vsys", args); break;
        case "setup": reply = shell.tui.run("setup"); break;
        case "start": reply = shell.run.detached(View.START_ARGV); break;
        case "get-vsys": reply = shell.requirements.offer(["vsys"]); break;
        default: throw new Error("agent-warden: action=" + JSON.stringify(action) + " unknown");
        }
        problem = View.refusal(reply);
        if (problem === "") shell.surfaces.hide("panel");
        else console.warn("agent-warden: action=" + action + " " + reply);
        return reply;
    }

    implicitWidth: Theme.size.panel.md
    implicitHeight: layout.implicitHeight

    Surface {
        anchors.fill: parent
    }

    // One inset box: the heading and its sentence, the body's blocks
    // `stack.group` apart, and a footer with the check's time and the link.
    Pane {
        id: layout
        anchors.fill: parent
        container: "panel"
        fitToContent: true
        maximumHeight: Theme.size.panel.maxHeight
        title: "Agents"

        subtitle: [
            Label {
                width: layout.headerWidth
                role: "body"
                wrapMode: Text.Wrap
                text: root.detail === null ? "Agent Warden is starting." : View.sentence(root.detail, root.vsysMissing)
            }
        ]

        Column {
            id: itemList
            width: layout.contentWidth
            spacing: Theme.stack.group
            visible: root.rows.length > 0
            Repeater {
                model: root.rows
                Callout {
                    required property var modelData
                    required property int index
                    // The list, not `parent`, which is null while the
                    // repeater tears the row down.
                    width: itemList.width
                    plain: true
                    tone: modelData.tone
                    iconName: modelData.icon
                    title: modelData.title
                    text: modelData.text
                    links: modelData.actions.map(action => action.label)
                    // modelData is the model's converted copy of the row,
                    // whose lists are not JS arrays, which the core's
                    // argument judge refuses, so the press reads the
                    // action from the panel's own rows.
                    onActionActivated: action => root.press("item", root.rows[index].actions[action].args)
                }
            }
        }

        Column {
            width: layout.contentWidth
            spacing: Theme.row.lineGap
            visible: root.memory !== null
            // Memory in use is a quantity at rest: the warden's items and
            // vsys's causes say when it needs attention, and the plugin
            // judges no level of its own.
            ProgressBar {
                width: parent.width
                tone: "neutral"
                value: root.memory === null ? 0 : root.memory.value
            }
            Label {
                role: "hint"
                text: root.memory === null ? "" : root.memory.text
            }
        }

        Label {
            role: "hint"
            width: layout.contentWidth
            wrapMode: Text.Wrap
            // Only the clear verdict is a line; a warn or danger cause is a
            // row of its level.
            visible: text !== ""
            text: root.detail === null ? "" : View.summaryClear(root.detail)
        }

        Button {
            id: primaryButton
            visible: root.setupButton !== null
            variant: "primary"
            text: root.setupButton === null ? "" : root.setupButton.label
            onClicked: root.press(root.setupButton.action)
        }

        Label {
            role: "hint"
            width: layout.contentWidth
            wrapMode: Text.Wrap
            visible: text !== ""
            text: root.problem
            color: Theme.color.danger
        }

        footer: [
            Column {
                width: layout.contentWidth
                spacing: Theme.stack.group

                Item {
                    width: parent.width
                    implicitHeight: Math.max(checkedLabel.implicitHeight, linkButton.implicitHeight)

                    Label {
                        id: checkedLabel
                        role: "hint"
                        anchors.left: parent.left
                        y: topForCapCenter(parent.height)
                        text: root.detail === null ? "" : View.checked(root.detail, root.now)
                    }
                    Button {
                        id: linkButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.footerLink !== null
                        variant: "tertiary"
                        text: root.footerLink === null ? "" : root.footerLink.label
                        onClicked: root.press(root.footerLink.action)
                    }
                }
            }
        ]
    }
}
