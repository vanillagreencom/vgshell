import QtQuick

Item {
    id: root
    property var shell: null
    property bool ready: true
    property var release: null
    property int received: 0
    onShellChanged: refresh()
    onReadyChanged: refresh()
    function refresh() {
        if (release !== null) { release(); release = null; }
        if (shell === null) return;
        release = shell.handoff.offer("compose", ready ? text => {
            const reply = shell.surfaces.summon("window", JSON.stringify({ text: text }));
            if (reply === "ok") received++;
            return { ok: reply === "ok", reason: reply === "ok" ? "" : "The fixture window could not open." };
        } : null, "The fixture is not ready.");
    }
}
