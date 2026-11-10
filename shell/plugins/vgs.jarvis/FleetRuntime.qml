import QtQuick
import Quickshell

// The Agent fleet row (SetupGate.fleetStep, shaped by the service with
// SetupGate.fleetRoute beside the Home folder step) uses the same setup status
// reader as local voice, read again after the home's Set up terminal ends,
// whose Jarvis bundle holds the mail tool, each requirement scan and the
// daemon's home publication after setup. Qt defines
// no order between this command's binding and LocalRuntime's own handler
// of a new shell, which a changed home
// setting brings, so a changed command reads again.
LocalRuntime {
    statusKey: "setupFleet"
    tuiName: "setup-home"
    program: String(Qt.resolvedUrl("backend/fleet-setup.js")).replace(/^file:\/\//, "")
    command: ["node", program, "--tree", Quickshell.shellDir + "/..", "status", shell === null ? "" : shell.settings.home]
    onCommandChanged: refresh()
}
