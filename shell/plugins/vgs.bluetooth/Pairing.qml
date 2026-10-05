import QtQuick
import Quickshell.Bluetooth
import qs.Commons
import "BluetoothLogic.js" as Logic

// The section's pairing runner, drawing nothing: one pairing at a time
// through the core's pairing agent, capability `bluetoothAgent`.
// BluetoothLogic.pairStep decides each step; this runs them. It holds the
// agent lease while a pairing runs, calls Pair once the lease reads ready,
// and trusts and connects the device once it reads paired, as Omarchy's
// bin/omarchy-bluetooth-device pairs one. A code to type on the device is
// dismissed when the pairing ends, and the lease goes with the instance.
//
// It also answers the agent's prompts, the first it lists, which come from
// a pairing or, while Discoverable holds a lease, from another device:
// `answer` sends the dialog's accept answer and `dismiss` what
// BluetoothLogic.promptDismiss names for its kind.
Item {
    id: root

    property var shell: null
    property var current: Logic.pairIdle()
    property var lease: null
    readonly property string leaseState: lease === null ? "" : lease.state
    readonly property bool active: Logic.pairActive(current)
    readonly property string text: Logic.pairText(current)
    readonly property var requests: shell === null ? [] : shell.bluetoothAgent.requests
    // The prompt the dialog shows: the first the agent lists.
    readonly property var request: requests.length > 0 ? requests[0] : null
    // The device the dialog names: the one this pairs, else "" for a
    // request from another device.
    readonly property string who: active ? current.name : ""
    readonly property var target: current.address === "" ? null : Logic.deviceAt(Bluetooth.devices.values, current.address)
    readonly property bool targetPaired: target !== null && target.paired
    readonly property bool targetPairing: target !== null && target.pairing
    readonly property bool targetGone: current.address !== "" && target === null

    visible: false

    // Pair ADDRESS; a pairing already running keeps running, with its name.
    function start(address) {
        const device = Logic.deviceAt(Bluetooth.devices.values, address);
        if (device === null) {
            console.warn("bluetooth: pair " + address + " reason=unknown");
            return;
        }
        run(Logic.pairStep(current, { type: "start", address: address, name: Logic.deviceName(device) }));
    }

    // The dialog's accept answer to the open prompt; answers the agent's
    // reply.
    function answer(value) {
        const reply = shell.bluetoothAgent.answer(request.id, value);
        if (reply !== "ok") console.warn("bluetooth: answer " + reply);
        return reply;
    }

    // The dialog's Cancel, Decline or Escape on the open prompt.
    function dismiss() {
        const entry = request;
        const effect = Logic.promptDismiss(entry.kind);
        const reply = shell.bluetoothAgent.answer(entry.id, effect.answer);
        if (reply !== "ok") console.warn("bluetooth: dismiss " + reply);
        if (effect.cancels) run(Logic.pairStep(current, { type: "cancel" }));
    }

    function run(step) {
        current = step.state;
        for (const effect of step.effects) {
            switch (effect) {
            case "begin-lease":
                lease = shell.bluetoothAgent.begin("pair a device");
                break;
            case "pair":
                if (target !== null) target.pair();
                break;
            case "cancel-pair":
                if (target !== null && target.pairing) target.cancelPair();
                break;
            case "release-lease":
                dismissDisplays();
                if (lease !== null) lease.release();
                lease = null;
                break;
            case "trust-connect":
                if (target !== null) {
                    target.trusted = true;
                    if (!target.connected) target.connect();
                }
                break;
            case "arm-settle":
                settle.restart();
                break;
            case "disarm-settle":
                settle.stop();
                break;
            default:
                throw new Error("bluetooth: pair effect " + JSON.stringify(effect) + " is not one of begin-lease, pair, cancel-pair, release-lease, trust-connect, arm-settle, disarm-settle");
            }
        }
        if (current.phase === "failed" && step.effects.length > 0) console.warn("bluetooth: pair " + current.address + " reason=" + current.reason);
    }

    // A code to type on the other device stays listed until it is
    // dismissed; a pairing that ends dismisses it.
    function dismissDisplays() {
        for (const entry of requests)
            if (entry.kind === "passkey-display") shell.bluetoothAgent.answer(entry.id, true);
    }

    // The prompts that keep a pairing running.
    function openPrompts() { return requests.filter(entry => entry.kind !== "cancel").length; }

    onLeaseStateChanged: if (leaseState !== "") run(Logic.pairStep(current, { type: "lease", state: leaseState }))
    onTargetPairedChanged: if (targetPaired) run(Logic.pairStep(current, { type: "paired" }))
    onTargetPairingChanged: if (!targetPairing) run(Logic.pairStep(current, { type: "pair-ended", open: openPrompts() }))
    onTargetGoneChanged: if (targetGone) run(Logic.pairStep(current, { type: "gone" }))
    onRequestsChanged: {
        if (requests.some(entry => entry.kind === "cancel")) run(Logic.pairStep(current, { type: "cancel" }));
        else run(Logic.pairStep(current, { type: "prompts", open: openPrompts() }));
    }
    Component.onDestruction: if (lease !== null) lease.release()

    Timer {
        id: settle
        interval: Logic.PAIR_SETTLE_MS
        repeat: false
        onTriggered: root.run(Logic.pairStep(root.current, { type: "settled" }))
    }
}
