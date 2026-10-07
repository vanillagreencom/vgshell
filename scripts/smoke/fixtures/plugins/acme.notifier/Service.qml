import QtQuick
// A sender without the `notifications` capability, so with it alone
// enabled no plugin keeps the core's notification server up:
// notify <json options> answers the reply of shell.notify.send.
Item {
    id: root
    property var shell: null
    property bool registered: false
    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("notify", arg => root.shell.notify.send(JSON.parse(arg)));
    }
}
