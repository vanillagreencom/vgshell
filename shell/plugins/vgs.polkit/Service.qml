import QtQuick
import Quickshell
import Quickshell.Io
import "PolkitModel.js" as PolkitModel

// The polkit agent's service. The core builds the one agent while the
// plugin holds capability `polkit`; this service shows the prompt overlay
// while the agent holds an authentication request and takes it down when
// the request ends, and publishes whether polkitd accepted the agent. While
// polkitd has not, it runs bin/agents to name each other agent in the
// session, and asks polkitd again once a step that makes room has ended.
// It holds no password and no flow state of its own.
Item {
    id: root

    // The core assigns the plugin's scoped shell object after creation.
    property var shell: null
    readonly property var agent: shell === null ? null : shell.polkit.agent
    readonly property bool active: agent !== null && agent.isActive
    readonly property bool registered: agent !== null && shell.polkit.registered
    // The last check of the session for the agent that is not registered,
    // PolkitModel.readCheck's answer; null before one ended.
    property var check: null
    // Whether the requirement scan found no polkit on the system.
    readonly property bool polkitMissing: shell !== null && shell.requirements.missing.indexOf("pkexec") !== -1
    // Published while the agent exists: the core destroys it as the plugin
    // is disabled, and a write then is refused as retired.
    readonly property var agentState: agent === null ? null : PolkitModel.agentStatus(registered, check, polkitMissing)
    // The ends of the plugin's own steps this service has acted on.
    property string seenEnds: ""
    readonly property var steps: shell === null ? null : shell.tui.state
    // Whether the prompt shows, so each request summons it once and its end
    // hides it once.
    property bool shown: false

    onActiveChanged: route()
    onShellChanged: {
        if (shell !== null) seenEnds = PolkitModel.stepEnds(shell.tui.state);
        route();
    }
    onAgentStateChanged: publish()
    onAgentChanged: look()
    onRegisteredChanged: look()
    // A step that ended, or polkit installed, may have made room.
    onStepsChanged: {
        if (shell === null) return;
        const ends = PolkitModel.stepEnds(shell.tui.state);
        if (ends === seenEnds) return;
        seenEnds = ends;
        register();
    }
    onPolkitMissingChanged: if (!polkitMissing) register()

    // Look for other agents while polkitd has not accepted this one. The
    // handler reads the core's own values: the bindings above may still
    // hold the last ones.
    function look() {
        if (shell === null || shell.polkit.agent === null) return;
        if (shell.polkit.registered) {
            check = null;
            return;
        }
        checker.run();
    }

    // Ask polkitd again, with a new agent the core builds; `look` then
    // follows the new agent.
    function register() {
        if (shell === null || shell.polkit.agent === null || shell.polkit.registered) return;
        const reply = shell.polkit.register();
        if (reply !== "ok") console.warn("polkit: register " + reply);
    }

    function checked(code, stdout, stderr) {
        const answer = PolkitModel.readCheck(code, stdout);
        if (!answer.ok) console.warn("polkit: check=failed exit=" + code + " " + stderr.split("\n")[0]);
        check = answer;
        // The check ended an agent the user stopped before, so there is room.
        if (answer.ok && answer.stopped > 0) register();
    }

    // A request no prompt can answer is cancelled, so the application that
    // asked is denied at once instead of waiting on a dialog that never came.
    function route() {
        if (shell === null || active === shown) return;
        if (!active) {
            shown = false;
            shell.surfaces.hide("overlay");
            return;
        }
        const reply = shell.surfaces.summon("overlay", "{}");
        if (reply === "ok") {
            shown = true;
            return;
        }
        console.warn("polkit: summon " + reply + "; the request is cancelled");
        if (PolkitModel.cancellable(agent.flow)) agent.flow.cancelAuthenticationRequest();
    }

    // The state last published, so an unchanged state is written once.
    property var published: null

    function publish() {
        if (!PolkitModel.statusChanged(published, agentState)) return;
        const reply = shell.status.set("agent", agentState);
        if (reply === "ok") published = agentState;
        else console.warn("polkit: status " + reply);
    }

    // bin/agents check, one run at a time; a run asked for while one runs
    // starts once it ends. `code` is null for a command that did not start,
    // which emits `runningChanged` alone.
    Process {
        id: checker

        property bool again: false
        property var completion: null

        command: [decodeURIComponent(String(Qt.resolvedUrl("bin/agents")).replace(/^file:\/\//, "")), "--tree", Quickshell.shellDir + "/..", "check"]
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }

        function run() {
            if (running) again = true;
            else running = true;
        }

        onExited: (code, status) => { completion = { code: code }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            root.checked(done === null ? null : done.code, out.text, err.text);
            if (!again) return;
            again = false;
            running = true;
        }
    }
}
