pragma Singleton
import QtQml

// Stands in for Quickshell.Hyprland's Hyprland singleton: a test emits the
// event socket's events by hand, as { name, data }, and sets `monitors`,
// keyed by output name, to the monitor objects monitorFor answers.
// `toplevels` and `workspaces` hold no window, as Quickshell's models with
// every reply in on an empty session.
QtObject {
    property bool usingLua: true
    property var focusedMonitor: null
    property var monitors: ({})
    property var toplevels: ({ values: [] })
    property var workspaces: ({ values: [] })
    signal rawEvent(var event)

    function monitorFor(screen) {
        return screen !== null && monitors[screen.name] !== undefined ? monitors[screen.name] : null;
    }
}
