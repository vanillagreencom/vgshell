import QtQuick

Item {
    property var shell: null
    readonly property var targets: shell === null ? [] : shell.handoff.targets
    function hand(text) {
        const target = targets.find(row => row.available);
        return target === undefined ? { ok: false, reason: "No text target is ready." } : target.open(text);
    }
}
