pragma Singleton
import QtQml

// Stands in for Quickshell.Hyprland's Hyprland singleton: a test emits the
// event socket's events by hand, as { name, data }, and sets `monitors`,
// keyed by output name, to the monitor objects monitorFor answers.
QtObject {
    property bool usingLua: true
    property var focusedMonitor: null
    property var monitors: ({})
    signal rawEvent(var event)

    function monitorFor(screen) {
        return screen !== null && monitors[screen.name] !== undefined ? monitors[screen.name] : null;
    }
}
