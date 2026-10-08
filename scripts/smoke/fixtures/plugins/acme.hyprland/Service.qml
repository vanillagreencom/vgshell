import QtQuick

// Reads the `hyprland` capability back for rows/hyprland-options.sh: its
// member names, the paths reported overridden, the values the user's own
// configuration gave its options, Hyprland's value of its unwritten ones, the foreign keys and the keymaps the
// keyboards are on; `switch` sends a layout switch. `conflict` is the key
// capture's answer for its own bind's key.
Item {
    id: root
    property var shell: null
    property bool registered: false
    readonly property string members: shell === null ? "" : Object.keys(shell.hyprland).sort().join(",")
    readonly property var overridden: shell === null ? [] : shell.hyprland.overridden
    readonly property var userValues: shell === null ? [] : shell.hyprland.userValues
    readonly property var values: shell === null ? null : shell.hyprland.values
    readonly property var foreignBinds: shell === null ? [] : shell.hyprland.foreignBinds
    readonly property var conflict: shell === null ? null : shell.shortcut.capture.conflicts("SUPER+F7", "acme.hyprland", "ping")
    // Each keymap a keyboard is on, once, sorted; null before the first read.
    readonly property var keymaps: {
        const devices = shell === null ? null : shell.hyprland.devices;
        if (devices === null) return null;
        return devices.keyboards.map(keyboard => keyboard.activeKeymap).filter((keymap, i, all) => all.indexOf(keymap) === i).sort();
    }

    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.shortcut.register("ping", "Ping", () => {});
        shell.ipc.handle("switch", target => root.shell.hyprland.switchKeyboardLayout(/^[0-9]+$/.test(target) ? Number(target) : target));
    }
}
