import QtQuick

// One plain idle watch for scripts/smoke/rows/idle-inhibit.sh, which reads
// its state through the core's lending record. IPC: `watch <seconds>`
// replaces it, `unwatch` runs its disposer.
Item {
    id: root
    property var shell: null
    property bool registered: false
    property var disposer: null

    function unwatch() {
        if (disposer !== null) disposer();
        disposer = null;
    }

    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("watch", arg => {
            root.unwatch();
            root.disposer = root.shell.idle.watch(Number(arg), () => {});
            return "ok";
        });
        shell.ipc.handle("unwatch", () => { root.unwatch(); return "ok"; });
    }
}
