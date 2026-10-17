import QtQuick

Item {
    property var shell: null
    readonly property var systemState: shell === null ? null : shell.system.state
    readonly property var statusValues: shell === null ? null : shell.status.values

    onSystemStateChanged: publish()
    function statusAct(key) { return shell.status.act(key); }
    function publish() {
        if (systemState === null) return;
        const step = systemState["bandwhich-capture"];
        // No reading before the first probe ends: publish nothing.
        if (step === undefined) return;
        shell.status.set("capture", {
            tone: step.state === "ready" ? "ok" : "warning",
            text: step.state + " " + step.reason,
            action: step.state === "needed" || step.state === "nixos"
        });
    }
}
