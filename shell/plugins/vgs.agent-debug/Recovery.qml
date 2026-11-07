import QtQuick
import qs.Commons
import qs.Ui

// The Agent Debug window, in one of two modes its payload names. `{}`:
// a diagnosis whose saved message target could not open, with a one-off
// Claude Code or Codex choice. `{"draft": true}`: a failure another plugin
// handed over, such as a failed sync job from Local Sync, as the facts the
// agent will get, with Run, which opens the chosen agent, and Cancel. The
// service holds both; the window asks it through the plugin's IPC.
FocusScope {
    id: root
    property var shell: null
    property string reason: ""
    property string problem: ""
    property bool waiting: false
    // The handed failure's facts and the chosen agent's name, or null.
    property var draft: null
    property string agent: ""
    property Item initialFocus: draft !== null ? run : cancel
    implicitWidth: Theme.size.panel.lg
    implicitHeight: layout.implicitHeight
    function open(payload) {
        problem = "";
        const wanted = payload ? JSON.parse(payload) : {};
        if (wanted.draft === true) {
            const reply = shell.ipc.call("draft", "");
            const current = reply.indexOf("{") === 0 ? JSON.parse(reply) : { facts: null, agent: "" };
            draft = current.facts;
            agent = current.agent;
            waiting = false;
            return;
        }
        draft = null;
        const reply = shell.ipc.call("recovery", "");
        const current = reply.indexOf("{") === 0 ? JSON.parse(reply) : { waiting: false };
        waiting = current.waiting === true;
        reason = waiting ? current.reason : "No diagnosis is waiting. Press Diagnose on a failure notification.";
    }
    function close() {
        if (shell === null) return;
        if (draft !== null) shell.ipc.call("draft-cancel", "");
        else shell.ipc.call("recover", "cancel");
    }
    function choose(agent) {
        const reply = shell.ipc.call("recover", agent);
        if (reply === "ok") shell.surfaces.hide("window");
        else problem = "This agent could not open. Check its installation, then retry Diagnose.";
    }
    function runDraft() {
        const reply = shell.ipc.call("draft-run", "");
        if (reply === "ok") {
            draft = null;
            shell.surfaces.hide("window");
        } else {
            problem = "The agent could not open. Check its installation, then try again.";
        }
    }
    function missing(agent) {
        if (!waiting) return "Press Diagnose on a failure notification first.";
        return shell === null || shell.requirements.missing.indexOf(agent) !== -1
            ? "Install this agent, then retry Diagnose." : "";
    }
    // The facts of a handed sync failure, in the order the prompt names
    // them (Diagnose.js).
    readonly property var facts: draft === null ? [] : [
        { label: "System job", value: draft.unit },
        { label: "Name", value: draft.name },
        { label: "Engine", value: draft.engine },
        { label: "From", value: draft.from },
        { label: "To", value: draft.to },
        { label: "Last error", value: draft.error }
    ].filter(row => row.value !== "")
    Pane {
        id: layout
        anchors.fill: parent
        container: "window"
        title: root.draft !== null ? "Diagnose a failed sync job" : "Cannot open the diagnosis"
        header: Label {
            width: layout.contentWidth
            text: root.draft !== null ? (root.agent === "" ? "Choose an agent in Agent Debug's settings, then run the diagnosis." : "Run opens " + root.agent + " with these facts. The agent asks you before it runs a command.") : root.reason
            color: root.draft !== null ? Theme.color.textMuted : Theme.color.warning
            wrapMode: Text.Wrap
        }
        Column {
            width: parent.width
            spacing: Theme.stack.page
            visible: root.draft === null
            Label { width: parent.width; text: "Open this failure with Claude Code or Codex instead. Your saved agent stays selected."; wrapMode: Text.Wrap }
        }
        GroupList {
            width: parent.width
            visible: root.draft !== null
            Repeater {
                model: root.facts
                FormRow {
                    id: fact
                    required property var modelData
                    width: parent.width
                    label: modelData.label
                    Label { width: parent.width; role: "value"; text: fact.modelData.value; wrapMode: Text.WrapAtWordBoundaryOrAnywhere }
                }
            }
        }
        Label { width: parent.width; visible: root.problem !== ""; text: root.problem; color: Theme.color.danger; wrapMode: Text.Wrap }
        footer: RowActions {
            Button { text: "Claude Code"; visible: root.draft === null; disabledReason: root.missing("claude"); onClicked: root.choose("claude") }
            Button { text: "Codex"; visible: root.draft === null; disabledReason: root.missing("codex"); onClicked: root.choose("codex") }
            Button {
                id: run
                text: "Run"
                iconName: "play"
                visible: root.draft !== null
                disabledReason: root.agent === "" ? "Choose an agent in Agent Debug's settings first." : ""
                onClicked: root.runDraft()
            }
            Button { id: cancel; text: "Cancel"; variant: "secondary"; onClicked: root.shell.surfaces.hide("window") }
        }
    }
}
