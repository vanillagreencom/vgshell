import QtQuick
import Quickshell.Io
import "ScreensaverLogic.js" as Logic

Item {
    id: root

    property var shell: null
    property var registeredWith: null
    property var idleDisposer: null
    property bool running: false
    property var published: ({})

    readonly property bool locked: shell !== null && shell.session.locked
    readonly property bool idleEnabled: shell !== null && shell.settings.idleEnabled === true
    readonly property int idleSeconds: shell === null ? 150 : shell.settings.idleSeconds
    readonly property int requirementsRevision: shell === null ? 0 : shell.requirements.revision

    onShellChanged: {
        if (shell === null) return;
        if (registeredWith === null) {
            registeredWith = shell;
            shell.shortcut.register("start", "Start the screensaver", () => root.start());
            shell.ipc.handle("start", () => root.start());
            shell.ipc.handle("stop", () => root.stop());
            shell.ipc.handle("status", () => root.statusJson());
        }
        publish("effects", [{ label: "Random", value: "random" }]);
        refreshEffects();
        watchIdle();
        publishState();
    }
    onIdleEnabledChanged: watchIdle()
    onIdleSecondsChanged: watchIdle()
    onRequirementsRevisionChanged: refreshEffects()
    onLockedChanged: if (locked) stop()
    onRunningChanged: publishState()

    function start() {
        if (shell === null) return "refused: screensaver=not-ready";
        if (locked) return "refused: screensaver=locked";
        running = true;
        return "ok";
    }

    function stop() {
        running = false;
        return "ok";
    }

    function watchIdle() {
        if (idleDisposer !== null) idleDisposer();
        idleDisposer = null;
        if (shell === null || !idleEnabled) return;
        idleDisposer = shell.idle.watch(idleSeconds, idle => {
            if (idle) root.start();
            else root.stop();
        });
    }

    function statusJson() {
        return JSON.stringify({ running: running, idleEnabled: idleEnabled, idleSeconds: idleSeconds, locked: locked });
    }

    function publish(key, value) {
        if (shell === null) return;
        const text = JSON.stringify(value);
        if (published[key] === text) return;
        const reply = shell.status.set(key, value);
        if (reply !== "ok") {
            console.warn("screensaver: status " + reply);
            return;
        }
        const next = Object.assign({}, published);
        next[key] = text;
        published = next;
    }

    function publishState() {
        publish("state", running ? { tone: "info", text: "Running" } : { tone: "ok", text: "Off" });
    }

    function refreshEffects() {
        if (shell === null || effectsHelp.running) return;
        effectsHelp.running = true;
    }

    Process {
        id: effectsHelp
        command: ["ttfx", "--help"]
        stdout: StdioCollector { id: effectsOut; waitForEnd: true }
        onExited: code => {
            if (code === 0) root.publish("effects", Logic.effectChoices(effectsOut.text));
        }
    }
}
