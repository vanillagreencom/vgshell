import QtQuick
import Quickshell
import qs.Commons
import "." as Jarvis
import "SetupGate.js" as Gate

// The shell's Reboot and Shut down while a Jarvis session lives. The
// launcher's System menu asks this instance's `power` handler first and
// runs `systemctl` itself unless the answer is `held`. The answer is `held`
// only while the last session answer reads a session that lives and no
// wait is held already: this instance then starts backend/power-wait.js
// detached, which asks the session to save and runs `systemctl` whatever
// the answer, at the latest after its bound, so a shell crash or reload
// during the wait still restarts the computer. It also shows the card
// (PowerCard) on the focused screen until the bound. A second ask while
// held, or the card's button, is the skip: the restart goes at once.
Item {
    id: root
    property var shell: null
    // The SessionStart instance: its last answer and the home of its session.
    property var session: null
    property string focusedOutput: ""
    // "reboot" or "poweroff" while a wait is held, else "".
    property string verb: ""
    // When the held wait ends, in milliseconds since the epoch.
    property real deadline: 0
    // Whole seconds to the deadline by the shell's clock (Time), which
    // ticks seconds only while a wait is held.
    readonly property int remaining: verb === "" ? 0 : Math.max(0, Math.ceil((deadline - Time.now.getTime()) / 1000))
    // backend/power-wait.js PREPARE_MS, the longest wait.
    readonly property int waitMs: 60000
    readonly property string program: String(Qt.resolvedUrl("backend/power-wait.js")).replace(/^file:\/\//, "")
    property bool registered: false

    onVerbChanged: Time.holdSeconds(root, verb !== "")
    Component.onDestruction: Time.holdSeconds(root, false)

    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("power", arg => root.power(arg));
        shell.layers.show(card);
    }

    // The `power` handler's answer for ARG, "reboot" or "poweroff": `held`
    // or `proceed`; any other answer, a refusal included, lets the caller
    // proceed too.
    function power(arg) {
        if (arg !== "reboot" && arg !== "poweroff") return "refused: power=" + arg;
        if (verb !== "") {
            end();
            return "proceed";
        }
        const result = session === null ? null : session.result;
        if (result === null || result.kind !== "answer" || !Gate.sessionLive(result.state)) return "proceed";
        const reply = shell.run.detached(["node", program, "--tree", Quickshell.shellDir + "/..", arg, session.sessionHome]);
        if (reply !== "ok") {
            console.warn("jarvis-power: wait " + reply);
            return "proceed";
        }
        verb = arg;
        deadline = Date.now() + waitMs;
        bound.restart();
        return "held";
    }

    // The card's Restart now or Shut down now.
    function proceedNow() {
        if (verb === "") return;
        const reply = shell.run.detached(["systemctl", verb]);
        if (reply !== "ok") console.warn("jarvis-power: " + verb + " " + reply);
        end();
    }

    function end() {
        bound.stop();
        verb = "";
        deadline = 0;
    }

    // The card goes at the bound: power-wait.js has asked for the restart
    // by then.
    Timer {
        id: bound
        interval: root.waitMs
        onTriggered: root.end()
    }

    Component {
        id: card
        Jarvis.PowerCard { wait: root }
    }
}
