import QtQuick
import qs.Commons
import qs.Ui

// The Agent Debug window's Diagnose draft: a failure another plugin handed
// over, such as a failed sync job from Local Sync, as the facts the agent
// will get, with Run, which opens the chosen agent, and Cancel. The service
// holds the draft; the draft asks it through the plugin's IPC.
// Recovery.qml shows it.
FocusScope {
    id: root
    property var shell: null
    property string problem: ""
    // The handed failure's facts and the chosen agent's name; facts null
    // while the service holds no draft.
    property var facts: null
    property string agent: ""
    readonly property Item initialFocus: run
    implicitHeight: layout.implicitHeight

    // Read the draft the service holds.
    function open() {
        problem = "";
        const reply = shell.ipc.call("draft", "");
        const current = reply.indexOf("{") === 0 ? JSON.parse(reply) : { facts: null, agent: "" };
        facts = current.facts;
        agent = current.agent;
    }
    // The window closed on this draft, or turned to another screen: the
    // service's draft goes, if it still holds one.
    function discard() {
        shell.ipc.call("draft-cancel", "");
    }
    // Run: the service opens the agent, or, when the saved message target
    // refused, the window turns to the recovery choice (`recovery`), which
    // stays shown.
    function runDraft() {
        const reply = shell.ipc.call("draft-run", "");
        if (reply === "ok") shell.surfaces.hide("window");
        else if (reply !== "recovery") problem = "The agent could not open. Check its installation, then try again.";
    }
    // The facts in the order the prompt names them (Diagnose.js).
    readonly property var rows: facts === null ? [] : [
        { label: "System job", value: facts.unit },
        { label: "Name", value: facts.name },
        { label: "Engine", value: facts.engine },
        { label: "From", value: facts.from },
        { label: "To", value: facts.to },
        { label: "Last error", value: facts.error }
    ].filter(row => row.value !== "")

    Pane {
        id: layout
        anchors.fill: parent
        container: "window"
        title: "Diagnose a failed sync job"
        header: Label {
            width: layout.contentWidth
            text: root.agent === "" ? "Choose an agent in Agent Debug's settings, then run the diagnosis." : "Run opens " + root.agent + " with these facts. The agent asks you before it runs a command."
            color: Theme.color.textMuted
            wrapMode: Text.Wrap
        }
        GroupList {
            width: parent.width
            Repeater {
                model: root.rows
                FormRow {
                    id: fact
                    required property var modelData
                    width: parent.width
                    label: modelData.label
                    // A fact holds the job's own text and an engine's error
                    // line, which may hold markup; the agent gets it as it
                    // is, so it shows as it is.
                    Label { width: parent.width; role: "value"; textFormat: Text.PlainText; text: fact.modelData.value; wrapMode: Text.WrapAtWordBoundaryOrAnywhere }
                }
            }
        }
        Label { width: parent.width; visible: root.problem !== ""; text: root.problem; color: Theme.color.danger; wrapMode: Text.Wrap }
        footer: RowActions {
            Button {
                id: run
                text: "Run"
                iconName: "play"
                disabledReason: root.agent === "" ? "Choose an agent in Agent Debug's settings first." : ""
                onClicked: root.runDraft()
            }
            Button { text: "Cancel"; variant: "secondary"; onClicked: root.shell.surfaces.hide("window") }
        }
    }
}
