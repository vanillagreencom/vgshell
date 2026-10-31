import QtQuick

// The `cover` capability fixture. It owns the screensaver stage, starts its
// cover from the stage watch and on request, ends it on input, and keeps the
// last idle ticket so a row can hand back one the core has revoked. Each
// idle start's answer is kept in `presents`.
Item {
    id: root

    property var shell: null
    property var registeredWith: null
    property var idleDisposer: null
    property var lastTicket: null
    property var presents: []
    property string watchProblem: ""
    readonly property bool running: shell !== null && shell.cover.running
    readonly property string placement: shell === null ? "none" : shell.cover.placement
    readonly property int seconds: shell === null ? 0 : shell.settings.seconds

    onSecondsChanged: watch()
    onShellChanged: {
        if (shell === null) return;
        if (registeredWith === null) {
            registeredWith = shell;
            shell.ipc.handle("present", () => root.shell.cover.present());
            shell.ipc.handle("present-last-ticket", () => root.lastTicket === null ? "no-ticket" : root.shell.cover.present(root.lastTicket));
            shell.ipc.handle("stop", () => root.shell.cover.stop());
            shell.ipc.handle("failed", () => root.shell.cover.failed());
            shell.ipc.handle("display-off", () => root.shell.compositor.displayPower("off"));
            shell.ipc.handle("status", () => JSON.stringify({ running: root.running, placement: root.placement, presents: root.presents, watchProblem: root.watchProblem }));
        }
        watch();
    }

    function watch() {
        if (idleDisposer !== null) idleDisposer();
        idleDisposer = null;
        if (shell === null) return;
        try {
            idleDisposer = shell.idle.watchStage("screensaver", (idle, ticket) => {
                if (!idle) {
                    root.shell.cover.stop();
                    return;
                }
                root.lastTicket = ticket;
                root.presents = root.presents.concat([root.shell.cover.present(ticket)]);
            });
            watchProblem = "";
        } catch (e) {
            watchProblem = e.message;
        }
    }
}
