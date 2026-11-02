import QtQuick
import "BrowserLogic.js" as BrowserLogic

// On its first start with a shell, a view opens itself to the service,
// which reads its sources again for it and, while any view is open, after
// each watched change and apply too, since the service reads on no timer.
// It reads the retained answer then, and later only newer revisions, and
// closes itself on its destruction. Polling is an in-process IPC call,
// with no disk read or child.
Item {
    id: root
    property var shell: null
    property var snapshot: null
    property int revision: -1
    // Whether the service holds this view open. A view that starts before
    // the service registered opens on a later poll.
    property bool opened: false
    // A random key, unique among the few views open at once, so a view's
    // close ends only its own entry.
    readonly property string key: Math.random().toString(36).slice(2)
    onShellChanged: start()
    Component.onCompleted: start()
    Component.onDestruction: {
        if (!opened || shell === null) return;
        const reply = shell.ipc.call("close-browser-view", key);
        if (reply !== "ok" && reply.indexOf("unknown:") !== 0) console.error("themes: close browser view " + reply);
    }

    function start() {
        if (shell === null) return;
        open();
        read();
    }
    // Ask the service to hold this view open and read for it once. A
    // service not registered answers `unknown:`, as read() takes it.
    function open() {
        if (opened) return;
        const reply = shell.ipc.call("open-browser-view", key);
        if (reply === "ok") opened = true;
        else if (reply.indexOf("unknown:") !== 0) throw new Error("themes: open browser view " + reply);
    }
    function read() {
        if (shell === null) return;
        const text = shell.ipc.call("browser-data", String(revision));
        if (text === "") return;
        if (text.indexOf("unknown:") === 0) return;
        const next = JSON.parse(text);
        revision = next.revision;
        snapshot = next;
    }
    // Ask the service to read its sources again.
    function refresh() {
        const reply = shell.ipc.call("refresh-browser-data", "");
        if (reply !== "ok") throw new Error("themes: data refresh " + reply);
    }
    Timer {
        interval: BrowserLogic.PROGRESS_POLL_MS
        repeat: true
        running: root.shell !== null
        onTriggered: {
            root.open();
            root.read();
        }
    }
}
