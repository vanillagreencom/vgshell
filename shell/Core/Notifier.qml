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
    // Quickshell or the message is dropped. DONE receives the chosen id
    // (empty on dismissal or failure), then "delivered" or "failed".
    function send(ctx, appName, options, hub, done) {
        if (done !== undefined && typeof done !== "function") return "refused: notify=done want=function";
        const judged = Logic.notifyOptions(options);
        if (!judged.ok) return "refused: notify=" + judged.error;
        if (hub.holdsName && !hub.active) {
            console.warn("notify: unsent plugin=" + ctx.id + " reason=no-drawer");
            if (done !== undefined) complete(ctx.id, done, "", "failed");
            return "ok";
        }
        if (runs.length >= Logic.NOTIFY_RUNS_MAX) return "refused: notify=busy limit=" + Logic.NOTIFY_RUNS_MAX;
        // A list crosses createObject's initial properties as something
        // else, so the run takes its command after creation.
        const run = runComponent.createObject(root, { pluginId: ctx.id });
        if (run === null) {
            console.warn("notify: unsent plugin=" + ctx.id + " exit=null process");
            if (done !== undefined) complete(ctx.id, done, "", "failed");
            return "ok";
        }
        run.command = Logic.notifyArgv(ctx.id, appName, judged.value, done !== undefined);
        run.actions = judged.value.actions;
        run.done = done === undefined ? null : (action, delivery) => { if (ctx.active) done(action, delivery); };
        // Only a waiting send borrows an instance lifetime. Core messages
        // and fire-and-forget sends retain the singleton's short run.
        if (judged.value.actions.length > 0 || done !== undefined) {
            run.release = ctx.onDispose(() => {
                run.done = null;
                run.cancelled = true;
                if (run.running) run.running = false;
            });
        }
        runs = runs.concat([run]);
        run.running = true;
        return "ok";
    }

    // A run ended: COMPLETION is its exit, null when it did not start.
    function ended(run, completion, stdout, complaint) {
        runs = runs.filter(item => item !== run);
        const failed = completion === null || completion.code !== 0 || completion.status !== 0;
        if (failed && !run.cancelled)
            console.warn("notify: unsent plugin=" + run.pluginId + " exit=" + JSON.stringify(completion) + " " + complaint.trim().split("\n")[0].trim().slice(0, 200));
        const done = run.done;
        if (run.release !== null) run.release();
        Qt.callLater(() => run.destroy());
        if (done !== null) complete(run.pluginId, done, failed ? "" : Logic.notifyAction(run.actions, stdout), failed ? "failed" : "delivered");
    }

    function complete(pluginId, done, action, delivery) {
        try { done(action, delivery); }
        catch (error) { console.warn("notify: callback plugin=" + pluginId + " " + error); }
    }

    // A command that fails to start emits only runningChanged, so the end
    // is read there: no exit recorded is a failed start.
    Component {
        id: runComponent
        Process {
            id: run
            property string pluginId: ""
            property var completion: null
            property var actions: []
            property var done: null
            property var release: null
            property bool cancelled: false
            // notify-send needs the program path and the session bus alone.
            // Under clearEnvironment a null value passes the shell's own
            // value through (Quickshell 0.3.1, Process.clearEnvironment).
            clearEnvironment: true
            environment: ({ PATH: null, DBUS_SESSION_BUS_ADDRESS: null, XDG_RUNTIME_DIR: null, LANG: "C.UTF-8" })
            // StdioCollector holds the chosen action until the process's
            // stream ends (Quickshell 0.3.1, StdioCollector.text).
            stdout: StdioCollector { id: chosen }
            stderr: StdioCollector { id: complaint }
            onExited: (code, status) => { completion = { code: code, status: status }; }
            onRunningChanged: if (!running) root.ended(run, completion, chosen.text, complaint.text)
        }
    }
}
