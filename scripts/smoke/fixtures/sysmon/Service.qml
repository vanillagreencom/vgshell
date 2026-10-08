import QtQuick

// The picture runner supplies readings through Probe's held status provider.
Item {
    property var shell: null
    property bool registered: false
    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("lease", () => "ok");
    }
}
