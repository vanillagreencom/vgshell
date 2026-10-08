import QtQuick

// Planted only in the screenshot sandbox; no network or capture reads.
Item {
    id: root
    property var shell: null
    property bool registered: false
    function publish(state) {
        const active = state !== "measuring" && state !== "idle";
        const needed = state === "capture-needed";
        const apps = active ? [
            { name: "chromium", down: 838861, up: 14336, connections: 18 },
            { name: "Slack", down: 251658, up: 16384, connections: 9 },
            { name: "spotify", down: 104858, up: 4096, connections: 3 }
        ] : [];
        const reply = shell.status.set("traffic", {
            state: state === "measuring" ? "measuring" : state === "idle" ? "idle" : "ready",
            down: state === "idle" ? 0 : 1258291, up: state === "idle" ? 0 : 34816,
            apps: apps, other: { down: 62914, up: 0 }, bandwhich: state !== "no-bandwhich",
            interfaces: [{ name: "enp5s0", down: 1258291, up: 34816 }]
        });
        if (reply !== "ok") return reply;
        return shell.status.set("capture", {
            tone: needed ? "warning" : state === "no-bandwhich" ? "info" : "ok", text: needed ? "Access needed" : state === "no-bandwhich" ? "bandwhich is not installed" : "Ready",
            hint: "See all shows every app and protocol. Allowing it lets every account on this computer see network traffic through bandwhich.",
            action: needed
        });
    }
    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("scene", state => root.publish(state));
        publish("apps");
    }
}
