import QtQuick
import Quickshell
import qs.Commons
import "." as Jarvis
import "SetupGate.js" as Gate

// The shell's Reboot and Shut down while a Jarvis session lives. Every
// restart or shutdown VGS asks for, the launcher's System menu and the
// Updates run's Reboot answer, runs `vgshell power` (bin/vgshell-power),
// which asks this instance's `power` handler first and runs `systemctl`
// itself unless the answer is `held`. The answer is `held`
// only while the last session answer reads a session that lives and no
// wait is held already: this instance then starts backend/power-wait.js
// detached, which asks the session to save and runs `systemctl` whatever
// the answer, at the latest after its bound, so a shell crash or reload
// during the wait still restarts the computer. This instance asks
// `systemctl` itself fallbackMarginMs after that bound: `held` means only
// that the helper's start was handed to Quickshell, which reports no start
// that failed (Capabilities.runDetached), so this request goes only when
// the helper did not ask in time. It also shows the card (PowerCard) on
// the focused screen, counting to the helper's bound, in a layer
// registered only while the wait is held. A second ask while held, or the
// card's button, is the skip: the restart goes at once.
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
    // ticks seconds only while a wait is held, at most the wait's own: that
    // clock reads whole seconds (whole minutes until its seconds start),
    // and the deadline keeps the fraction it drops.
    readonly property int remaining: verb === "" ? 0 : Math.max(0, Math.min(waitMs / 1000, Math.ceil((deadline - Time.now.getTime()) / 1000)))
    // backend/power-wait.js PREPARE_MS, the longest wait.
    readonly property int waitMs: 60000
    // How long after the helper's bound this instance's own request waits.
    // The helper arms its bound only once node has loaded it, after this
    // instance's bound starts, and later still under load; the margin lets
    // the helper's request at its bound come first.
    readonly property int fallbackMarginMs: 5000
    readonly property string program: String(Qt.resolvedUrl("backend/power-wait.js")).replace(/^file:\/\//, "")
    property bool registered: false
    // The card layer's release while a wait is held, else null.
    property var cardRelease: null

    onVerbChanged: Time.holdSeconds(root, verb !== "")
    Component.onDestruction: {
        Time.holdSeconds(root, false);
        releaseCard();
    }

    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("power", arg => root.power(arg));
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
        // The helper runs whether the card shows or not.
        try {
            cardRelease = shell.layers.show(card);
        } catch (error) {
            console.warn("jarvis-power: card " + error.message);
        }
        return "held";
    }

    // The card's Restart now or Shut down now, and this instance's bound
    // past the helper's: the restart goes now. The button can come before
    // the helper's request, which then follows a restart already asked
    // for; the bound comes only after the helper's own.
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
        releaseCard();
    }

    function releaseCard() {
        if (cardRelease === null) return;
        const release = cardRelease;
        cardRelease = null;
        release();
    }

    // The restart for a helper that did not ask at its bound, which then
    // never ran or failed before its request; the card goes with it.
    Timer {
        id: bound
        interval: root.waitMs + root.fallbackMarginMs
        onTriggered: {
            console.warn("jarvis-power: bound verb=" + root.verb);
            root.proceedNow();
        }
    }

    Component {
        id: card
        Jarvis.PowerCard { wait: root }
    }
}
