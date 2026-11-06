import QtQuick
import qs.Commons
import qs.Ui

FocusScope {
    id: root
    property var shell: null
    property string reason: ""
    property string problem: ""
    property bool waiting: false
    property Item initialFocus: cancel
    implicitWidth: Theme.size.panel.lg
    implicitHeight: layout.implicitHeight
    function open(payload) {
        const reply = shell.ipc.call("recovery", "");
        const current = reply.indexOf("{") === 0 ? JSON.parse(reply) : { waiting: false };
        waiting = current.waiting === true;
        reason = waiting ? current.reason : "No diagnosis is waiting. Press Diagnose on a failure notification.";
        problem = "";
    }
    function close() { if (shell !== null) shell.ipc.call("recover", "cancel"); }
    function choose(agent) {
        const reply = shell.ipc.call("recover", agent);
        if (reply === "ok") shell.surfaces.hide("window");
        else problem = "This agent could not open. Check its installation, then retry Diagnose.";
    }
    function missing(agent) {
        if (!waiting) return "Press Diagnose on a failure notification first.";
        return shell === null || shell.requirements.missing.indexOf(agent) !== -1
            ? "Install this agent, then retry Diagnose." : "";
    }
    Pane {
        id: layout
        anchors.fill: parent
        container: "window"
        title: "Cannot open the diagnosis"
        header: Label { width: layout.contentWidth; text: root.reason; color: Theme.color.warning; wrapMode: Text.Wrap }
        Column {
            width: parent.width
            spacing: Theme.stack.page
            Label { width: parent.width; text: "Open this failure with Claude Code or Codex instead. Your saved agent stays selected."; wrapMode: Text.Wrap }
            Label { width: parent.width; visible: root.problem !== ""; text: root.problem; color: Theme.color.danger; wrapMode: Text.Wrap }
        }
        footer: RowActions {
            Button { text: "Claude Code"; disabledReason: root.missing("claude"); onClicked: root.choose("claude") }
            Button { text: "Codex"; disabledReason: root.missing("codex"); onClicked: root.choose("codex") }
            Button { id: cancel; text: "Cancel"; variant: "secondary"; onClicked: root.shell.surfaces.hide("window") }
        }
    }
}
