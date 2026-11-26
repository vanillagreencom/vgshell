import QtQuick

// Stands in for Quickshell.Io's Process, whose plugin does not load outside
// the shell. The TUI records test sets stdout and stderr and then emits
// exited before running becomes false, matching the runtime order the core
// relies on.
QtObject {
    id: process

    property var command: []
    property bool running: false
    property var stdout: null
    property var stderr: null
    property var environment: ({})
    property bool clearEnvironment: false
    property bool stdinEnabled: false
    // What the owner wrote to stdin, in order, each while stdin was open;
    // a write to a closed stdin is kept apart, since the real process drops it.
    property var written: []
    property var writtenClosed: []

    signal started()
    signal exited(int code, int status)

    function finish(code, status, out, err) {
        if (stdout !== null && stdout.text !== undefined) stdout.text = out === undefined ? "" : out;
        if (stderr !== null && stderr.text !== undefined) stderr.text = err === undefined ? "" : err;
        exited(code, status);
        running = false;
    }

    function write(data) {
        if (stdinEnabled) written = written.concat([data]);
        else writtenClosed = writtenClosed.concat([data]);
    }

    function failStart() {
        running = false;
    }

    function signal(number) {
        finish(-1, 1, "", "");
    }

    Component.onCompleted: ProcessRegistry.add(process)
    Component.onDestruction: ProcessRegistry.remove(process)
}
