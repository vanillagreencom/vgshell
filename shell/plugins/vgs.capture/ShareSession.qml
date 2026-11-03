import QtQuick
import Quickshell
import Quickshell.Io

// The service owns one pending portal request. A closed surface cancels it.
// The caller consumes a completed answer once and cancels on its own timeout.
// It also sets xdph up to call the VGS picker, with no step from the user
// (D075): a probe reads whether the portal runs with the picker, and a
// configure writes it and restarts the portal while no share runs.
Item {
    id: root
    property var shell: null
    property bool registered: false
    property var session: null
    // Whether the probe that runs, and the one queued behind it, may go on
    // to a configure: a share-begin's probe only reads.
    property bool setUpAfterProbe: false
    property bool probeAgain: false
    property bool setUpAgain: false
    readonly property var missing: shell === null ? [] : shell.requirements.missing
    readonly property var toolsMissing: ["systemctl", "busctl"].filter(tool => missing.indexOf(tool) >= 0)
    readonly property bool pageViewed: shell !== null && shell.status.viewed
    // shellDir is the root configuration, independent of plugin snapshots.
    // https://quickshell.org/docs/v0.3.1/types/Quickshell/Quickshell
    readonly property string pickerPath: Quickshell.shellDir + "/../bin/vgshell-share-picker"
    // Quickshell 0.3.1 clearEnvironment passes only the named values, and a
    // null one as the shell has it. PipeWire's pair reaches pw-dump, which
    // the configure reads for a running share.
    // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process
    readonly property var pickerEnvironment: ({ HOME: null, XDG_CONFIG_HOME: null, XDG_RUNTIME_DIR: null, DBUS_SESSION_BUS_ADDRESS: null,
        PIPEWIRE_RUNTIME_DIR: null, PIPEWIRE_REMOTE: null, PATH: null, VGS_TEST_RUN: null })
    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("share-begin", arg => root.begin(arg));
        shell.ipc.handle("share-result", arg => root.result(JSON.parse(arg).id));
        shell.ipc.handle("share-cancel", arg => root.cancel(JSON.parse(arg).id));
        shell.ipc.handle("share-close", arg => root.session !== null && root.session.phase === "pending" ? root.cancel(JSON.parse(arg).id, false) : "ok");
        shell.ipc.handle("share-choice", arg => root.choose(arg));
        check(true);
    }
    onMissingChanged: if (registered) check(true)
    // Opening Capture's Settings page tries a setup that did not finish again.
    onPageViewedChanged: if (registered && pageViewed) check(true)

    // Probes, then sets up when SETUP is true and the probe reads Needed. A
    // request during a probe queues one more; a configure in flight reads
    // everything afresh and publishes its own result, so it takes none.
    function check(setUp) {
        if (configurer.running) return;
        if (setup.running) {
            probeAgain = true;
            setUpAgain = setUpAgain || setUp;
            return;
        }
        setUpAfterProbe = setUp;
        setup.running = true;
    }

    function publish(value) { root.shell.status.set("sharing", value); }

    // The user's Off: xdph goes back to its own picker, since no capture
    // service answers the VGS one. Detached, as the service ends now
    // (turnedOff, .agents/skills/vgs-plugin/references/api.md § Kinds); a
    // reload, a rescan or a shell exit keeps the picker. The release owns
    // its outcome from here: it waits out a share and tells the user itself
    // when the portal cannot let the picker go (bin/vgshell-share-picker).
    function turnedOff() {
        if (shell === null) return;
        const reply = shell.run.detached([pickerPath, "--release"]);
        if (reply !== "ok") console.error("capture: share-release " + reply);
    }

    function begin(arg) {
        if (session !== null) return "refused: share=busy";
        const request = JSON.parse(arg);
        if (typeof request.id !== "string" || request.id === "" || !Array.isArray(request.windows) || typeof request.remember !== "boolean") return "refused: share=request";
        // A later portal start can activate a previously needed setup. This
        // probe only reads: a restart now would end the request.
        check(false);
        session = { phase: "pending", request: request };
        deadline.restart();
        const reply = shell.surfaces.summon("window", JSON.stringify(request));
        if (reply !== "ok") { deadline.stop(); session = null; return reply; }
        return "ok";
    }

    function result(id) {
        if (session === null || session.request.id !== id) return "cancelled";
        if (session.phase === "pending") return "pending";
        const answer = session.phase === "selected" ? JSON.stringify({ choice: session.choice }) : "cancelled";
        session = null;
        deadline.stop();
        return answer;
    }

    function cancel(id, hideSurface) {
        if (session === null || session.request.id !== id) return "ok";
        session = { phase: "cancelled", request: session.request };
        // A close or replacement already owns the window's visibility.
        if (hideSurface !== false) shell.surfaces.hide("window");
        session = null;
        deadline.stop();
        return "ok";
    }

    Timer { id: deadline; interval: 300000; onTriggered: if (root.session !== null) root.cancel(root.session.request.id) }

    function choose(arg) {
        const answer = JSON.parse(arg);
        if (session === null || session.phase !== "pending" || session.request.id !== answer.id) return "refused: share=request-ended";
        // The executable owns the xdph grammar and validates this typed choice.
        session = { phase: "selected", request: session.request, choice: answer.choice };
        shell.surfaces.hide("window");
        return "ok";
    }

    Process {
        id: setup
        command: [root.pickerPath, "--probe"]
        clearEnvironment: true
        environment: root.pickerEnvironment
        stderr: StdioCollector { id: setupError }
        stdout: StdioCollector { id: setupResult }
        onExited: (code, status) => {
            let ready = false;
            if (code === 0 && status === 0) {
                try { ready = JSON.parse(setupResult.text).state === "ready"; }
                catch (error) { console.error("capture: share-probe invalid-result"); }
            }
            if (code !== 0 || status !== 0) console.error("capture: share-probe " + setupError.text.trim());
            if (ready) {
                retry.stop();
                root.publish({ tone: "ok", text: "Ready" });
            } else if (root.setUpAfterProbe && root.toolsMissing.length > 0) {
                // Without them the configure cannot tell when the portal
                // took the picker, and would restart it at each check.
                root.publish({ tone: "warning", text: "Not set up", hint: "Setup needs " + root.toolsMissing.join(" and ") + " from systemd." });
            } else if (root.setUpAfterProbe && root.session === null) {
                // The configure reads everything afresh, so it answers a
                // request queued behind this probe too.
                root.probeAgain = false;
                root.setUpAgain = false;
                configurer.running = true;
                return;
            } else if (root.setUpAfterProbe) {
                // A request of VGS's own is open: try once it can end.
                retry.restart();
            }
            if (root.probeAgain) {
                const setUp = root.setUpAgain;
                root.probeAgain = false;
                root.setUpAgain = false;
                root.check(setUp);
            }
        }
    }

    // Exit statuses are bin/vgshell-share-picker's: 73 a config folder VGS
    // cannot use, its sentence and step on stdout; 75 the picker written
    // but the portal not restarted; 76 the restart waiting on a share.
    Process {
        id: configurer
        command: [root.pickerPath, "--configure"]
        clearEnvironment: true
        environment: root.pickerEnvironment
        stderr: StdioCollector { id: configureError }
        stdout: StdioCollector { id: configureSaid }
        onExited: (code, status) => {
            // The status shows each outcome the picker names; only another
            // end is an error, which the log keeps with its keyed cause.
            const named = status === 0 && [0, 73, 75, 76].indexOf(code) >= 0;
            if (!named) console.error("capture: share-setup code=" + code + " " + configureError.text.trim());
            else if (code !== 0) console.info("capture: share-setup code=" + code + " " + configureError.text.trim());
            const again = "VGS tries again when you open this page.";
            if (status !== 0) root.publish({ tone: "danger", text: "Setup failed", hint: again });
            else if (code === 0) root.publish({ tone: "ok", text: "Ready" });
            else if (code === 76) root.publish({ tone: "info", text: "Waiting for the screen share to end", hint: "VGS sets up the picker once no app shares your screen." });
            else if (code === 75) root.publish({ tone: "warning", text: "Ready after you log in again", hint: "The screen sharing service did not restart. " + again });
            else if (code === 73) {
                const said = configureSaid.text.trim().split("\n");
                root.publish({ tone: "danger", text: said[0].slice(0, 200), hint: (said[1] || again).slice(0, 200) });
            } else root.publish({ tone: "danger", text: "Setup failed", hint: again });
            if (status === 0 && code === 76) retry.restart();
            else retry.stop();
        }
    }

    // While a share holds the restart, ask again each minute; each try is
    // one probe and one pw-dump, and ends with the setup.
    Timer { id: retry; interval: 60000; onTriggered: root.check(true) }
}
