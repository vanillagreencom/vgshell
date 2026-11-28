import QtQuick

// The toggle writes `hidden` so it holds across a restart. Hide and
// reveal write `hiddenUntilReveal` in memory, so a restart ends that hide.
// Bar.qml reads both as `shown`, which the bar host follows on every screen.
Item {
    id: root

    property var shell: null
    // A settings change can hand over a new shell without rebuilding this service.
    property var registeredWith: null

    onShellChanged: {
        if (shell === null || registeredWith !== null) return;
        registeredWith = shell;
        shell.shortcut.register("toggle", "Hide or show the top bar", () => root.toggle());
        shell.ipc.handle("toggle", () => root.toggle());
        shell.ipc.handle("hide", () => root.hideUntilReveal(true));
        shell.ipc.handle("reveal", () => root.hideUntilReveal(false));
    }

    function toggle() {
        const reply = shell.configure.set("hidden", shell.settings.hidden !== true);
        if (reply !== "ok") console.warn("vgs.bar: toggle " + reply);
        return reply;
    }

    function hideUntilReveal(hidden) {
        const reply = shell.status.set("hiddenUntilReveal", hidden);
        if (!shell.status.isOk(reply)) console.warn("vgs.bar: " + (hidden ? "hide " : "reveal ") + reply);
        return reply;
    }
}
