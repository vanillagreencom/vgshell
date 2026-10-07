pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "PluginLogic.js" as Logic

// A plugin's message to the user, the `notify` capability: one system
// notification per send, through one notify-send run this singleton owns,
// with the plugin's manifest name as the sender. Until this shell first
// builds its own notification server the message goes to whatever program
// holds org.freedesktop.Notifications; with none, notify-send fails. Once
// built, this shell holds that name for good (NotificationHub.holdsName),
// so while no plugin holds the `notifications` role nothing would draw the
// message and the core does not send it. Either way the message is
// dropped and one `notify: unsent` line names the plugin; the core draws
// nothing in its place and no plugin carries a fallback. notify-send
// without --action or --wait exits once the server answers; libnotify's
// Notify call passes timeout -1, the GDBus proxy default of 25 seconds, so
// a server that never answers ends the run then.
Singleton {
    id: root

    // The runs in flight, oldest first.
    property var runs: []

    // Send OPTIONS for the instance CTX belongs to, as APP_NAME, past HUB,
    // the core's NotificationHub. Answers "ok" once the run is handed to
    // Quickshell or the message is dropped; delivery is not reported back.
    function send(ctx, appName, options, hub) {
        const judged = Logic.notifyOptions(options);
        if (!judged.ok) return "refused: notify=" + judged.error;
        if (hub.holdsName && !hub.active) {
            console.warn("notify: unsent plugin=" + ctx.id + " reason=no-drawer");
            return "ok";
        }
        if (runs.length >= Logic.NOTIFY_RUNS_MAX) return "refused: notify=busy limit=" + Logic.NOTIFY_RUNS_MAX;
        // A list crosses createObject's initial properties as something
        // else, so the run takes its command after creation.
        const run = runComponent.createObject(root, { pluginId: ctx.id });
        if (run === null) {
            console.warn("notify: unsent plugin=" + ctx.id + " exit=null process");
            return "ok";
        }
        run.command = Logic.notifyArgv(ctx.id, appName, judged.value);
        runs = runs.concat([run]);
        run.running = true;
        return "ok";
    }

    // A run ended: COMPLETION is its exit, null when it did not start.
    function ended(run, completion, complaint) {
        runs = runs.filter(item => item !== run);
        if (completion === null || completion.code !== 0 || completion.status !== 0)
            console.warn("notify: unsent plugin=" + run.pluginId + " exit=" + JSON.stringify(completion) + " " + complaint.trim().split("\n")[0].trim().slice(0, 200));
        Qt.callLater(() => run.destroy());
    }

    // A command that fails to start emits only runningChanged, so the end
    // is read there: no exit recorded is a failed start.
    Component {
        id: runComponent
        Process {
            id: run
            property string pluginId: ""
            property var completion: null
            // notify-send needs the program path and the session bus alone.
            // Under clearEnvironment a null value passes the shell's own
            // value through (Quickshell 0.3.1, Process.clearEnvironment).
            clearEnvironment: true
            environment: ({ PATH: null, DBUS_SESSION_BUS_ADDRESS: null, XDG_RUNTIME_DIR: null, LANG: "C.UTF-8" })
            stderr: StdioCollector { id: complaint }
            onExited: (code, status) => { completion = { code: code, status: status }; }
            onRunningChanged: if (!running) root.ended(run, completion, complaint.text)
        }
    }
}
