import QtQuick

// The Key Hints service: the global shortcut that opens and closes the
// window. It draws nothing and owns nothing else; the registration's
// disposer is the core's, so disabling the plugin releases it. The window
// opens on the focused monitor.
//   shortcut vgs.keyhints:toggle            SUPER+SLASH from the manifest's
//                                            `hyprland` binds
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
        shell.shortcut.register("toggle", "Show every shortcut", () => root.toggle());
    }

    // The window host's reply: `ok`, or its refusal.
    function toggle() {
        const reply = shell.surfaces.toggle("window", "{}");
        if (reply !== "ok") console.warn("keyhints: toggle " + reply);
        return reply;
    }
}
