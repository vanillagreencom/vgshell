import QtQuick
import "BrowserLogic.js" as BrowserLogic

// A view reads the service's retained answer on creation, then only newer
// revisions. Polling is an in-process IPC call, with no disk read or child.
Item {
    id: root
    property var shell: null
    property var snapshot: null
    property int revision: -1
    onShellChanged: read()
    Component.onCompleted: read()

    function read() {
        if (shell === null) return;
        const text = shell.ipc.call("browser-data", String(revision));
        if (text === "") return;
        if (text.indexOf("unknown:") === 0) return;
        const next = JSON.parse(text);
        revision = next.revision;
        snapshot = next;
    }
    function refresh() {
        const reply = shell.ipc.call("refresh-browser-data", "");
        if (reply !== "ok") throw new Error("themes: data refresh " + reply);
    }
    Timer {
        interval: BrowserLogic.PROGRESS_POLL_MS
        repeat: true
        running: root.shell !== null
        onTriggered: root.read()
    }
}
