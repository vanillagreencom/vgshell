pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

// The compositor's numbered workspaces, derived once for every screen and
// every plugin that shows them, sorted, named workspaces (negative ids) left
// out. Quickshell 0.3.1 takes a workspace's monitor from Hyprland's
// j/workspaces reply and moves it on `moveworkspacev2`
// (src/wayland/hyprland/ipc/connection.cpp HyprlandIpc::onEvent,
// workspace.cpp HyprlandWorkspace::updateFromObject), so `items` follows a
// workspace to another monitor with no read of its own.
Singleton {
    // One { id, output, active } per workspace: `output` the name of the
    // monitor that holds it, "" while Quickshell knows none, and `active`
    // whether that monitor shows it (HyprlandWorkspace.active,
    // https://quickshell.org/docs/v0.3.1/types/Quickshell.Hyprland/HyprlandWorkspace/).
    readonly property var items: {
        const out = [];
        for (const ws of Hyprland.workspaces.values)
            if (ws.id > 0) out.push({ id: ws.id, output: ws.monitor !== null ? ws.monitor.name : "", active: ws.active });
        out.sort((a, b) => a.id - b.id);
        return out;
    }
    // Read from the ids alone, not from `items`, so a focus change, which
    // changes `items`, hands a Repeater over `ids` no new list.
    readonly property var ids: {
        const out = [];
        for (const ws of Hyprland.workspaces.values)
            if (ws.id > 0) out.push(ws.id);
        out.sort((a, b) => a - b);
        return out;
    }
    readonly property int focusedId: Hyprland.focusedWorkspace !== null ? Hyprland.focusedWorkspace.id : -1
    // One { name, description } per monitor, so a Hyprland rule that names
    // its monitor by description finds the output
    // (https://quickshell.org/docs/v0.3.1/types/Quickshell.Hyprland/HyprlandMonitor/).
    readonly property var monitors: {
        const out = [];
        for (const m of Hyprland.monitors.values) out.push({ name: m.name, description: m.description });
        return out;
    }
}
