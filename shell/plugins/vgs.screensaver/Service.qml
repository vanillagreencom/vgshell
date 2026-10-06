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
    property var seenArtEndedAt: null

    readonly property bool locked: shell !== null && shell.session.locked
    readonly property bool idleEnabled: shell !== null && shell.settings.idleEnabled === true
    readonly property int idleSeconds: shell === null ? 150 : shell.settings.idleSeconds
    readonly property int requirementsRevision: shell === null ? 0 : shell.requirements.revision
    readonly property var artRun: shell === null ? ({ running: false, code: null, endedAt: null }) : shell.tui.state.art
    readonly property string managerKey: shell === null ? "" : JSON.stringify(shell.manager.plugins)

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
        publishAll();
    }
    onIdleEnabledChanged: { watchIdle(); publishLockOrder(); }
    onIdleSecondsChanged: { watchIdle(); publishLockOrder(); }
    onRequirementsRevisionChanged: refreshEffects()
    onLockedChanged: if (locked) stop()
    onRunningChanged: publishState()
    onArtRunChanged: checkArtRun()
    onManagerKeyChanged: publishLockOrder()

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

    function checkArtRun() {
        if (shell === null || artRun === undefined || artRun === null) return;
        if (artRun.endedAt === null || artRun.endedAt === seenArtEndedAt) return;
        seenArtEndedAt = artRun.endedAt;
        if (artRun.code === 0) start();
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

    function publishAll() {
        publishState();
        publishArt();
        publishLockOrder();
    }

    function publishState() {
        publish("state", running ? { tone: "info", text: "Running" } : { tone: "ok", text: "Off" });
    }

    function publishArt() {
        publish("art", { tone: "info", text: "Default art", action: true });
    }

    function publishLockOrder() {
        if (shell === null) return;
        const plugins = shell.manager.plugins || [];
        const lock = plugins.find(row => row.id === "vgs.lock" && row.enabled === true);
        if (lock === undefined) {
            return;
        }
        const seconds = Number(lock.settings.idleLockSeconds || 0);
        if (seconds <= 0) {
            publish("lockOrder", { tone: "warning", text: "Lock is off" });
            return;
        }
        if (!idleEnabled) {
            publish("lockOrder", { tone: "info", text: "Idle start is off" });
            return;
        }
        publish("lockOrder", { tone: idleSeconds < seconds ? "ok" : "warning", text: "Lock follows at " + seconds + " s" });
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
