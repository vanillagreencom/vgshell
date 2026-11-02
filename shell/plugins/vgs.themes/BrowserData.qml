import QtQuick
import "BrowserLogic.js" as BrowserLogic

// On its first start with a shell, a view asks the service once to read
// its sources again, since the service reads on no timer. It reads the
// retained answer then, and later only newer revisions. Polling is an
// in-process IPC call, with no disk read or child.
Item {
    id: root
    property var shell: null
    property var snapshot: null
    property int revision: -1
    property bool asked: false
    onShellChanged: start()
    Component.onCompleted: start()

    function start() {
        if (shell === null) return;
        if (!asked) {
            asked = true;
            refresh(true);
        }
        read();
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
    // Ask the service to read its sources again. An opening view takes the
    // `unknown:` reply of a service not registered, as read() does.
    function refresh(opening) {
        const reply = shell.ipc.call("refresh-browser-data", "");
        if (reply === "ok" || opening === true && reply.indexOf("unknown:") === 0) return;
        throw new Error("themes: data refresh " + reply);
    }
    Timer {
        interval: BrowserLogic.PROGRESS_POLL_MS
        repeat: true
        running: root.shell !== null
        onTriggered: root.read()
    }
}
