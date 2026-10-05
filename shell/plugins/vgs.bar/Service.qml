import QtQuick

// The bar's service: the global shortcut and the IPC function that hide or
// show the bar on every screen. It draws nothing; each registration's
// disposer is the core's, so a bar that stops being the active one releases
// them.
//   shortcut vgs.bar:toggle                 SUPER+SHIFT+SPACE from the
//                                            manifest's `hyprland` binds;
//                                            the launcher's Style row runs
//                                            it too (README)
//   vgshell ipc call vgs.bar invoke toggle ''  the same toggle
// The toggle flips the `hidden` setting through `configure`, so it holds
// across a restart; Bar.qml reads it as `shown`, which the bar host follows.
Item {
    id: root

    // The core assigns the plugin's scoped shell object after creation.
    property var shell: null
    // The shell this service registered with, so a settings change that
    // hands over a new object registers nothing twice.
    property var registeredWith: null

    onShellChanged: {
        if (shell === null || registeredWith !== null) return;
        registeredWith = shell;
        shell.shortcut.register("toggle", "Hide or show the top bar", () => root.toggle());
        shell.ipc.handle("toggle", () => root.toggle());
    }

    // The configure capability's reply: `ok`, or its refusal.
    function toggle() {
        const reply = shell.configure.set("hidden", shell.settings.hidden !== true);
        if (reply !== "ok") console.warn("vgs.bar: toggle " + reply);
        return reply;
    }
}
