import QtQuick

// Reads the `monitors` capability back for rows/monitor-outputs.sh: its
// member names, the outputs and the panel support.
Item {
    id: root
    property var shell: null
    readonly property string members: shell === null ? "" : Object.keys(shell.monitors).sort().join(",")
    readonly property var outputs: shell === null ? null : shell.monitors.outputs
    readonly property var support: shell === null ? null : shell.monitors.support
}
