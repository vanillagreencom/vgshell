import QtQuick

// One discovery lease of the plugin's service, held while `active` holds.
// The service owns discovery and its debt (Service.qml); a flyout or pane
// declares one of these, and its teardown is the lease's disposer, so a
// destroyed instance never leaves a lease behind. A lease the service
// refused, such as one asked for before the service was built, is logged
// and asked for again when `shell` or `active` next changes.
QtObject {
    id: lease

    property var shell: null
    property bool active: false
    // The service's id for the held lease, 0 while none is held.
    property int leaseId: 0

    onShellChanged: sync()
    onActiveChanged: sync()
    Component.onDestruction: release()

    function sync() {
        if (shell === null) return;
        if (active && leaseId === 0) begin();
        else if (!active && leaseId !== 0) release();
    }

    function begin() {
        const reply = shell.ipc.call("discovery", "begin");
        const match = /^lease=([1-9][0-9]*)$/.exec(reply);
        if (match === null) {
            console.warn("bluetooth: discovery lease " + reply);
            return;
        }
        leaseId = Number(match[1]);
    }

    function release() {
        if (leaseId === 0 || shell === null) return;
        const reply = shell.ipc.call("discovery", "end " + leaseId);
        leaseId = 0;
        if (reply !== "ok") console.warn("bluetooth: discovery release " + reply);
    }
}
