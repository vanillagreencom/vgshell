import QtQuick
import Quickshell.Bluetooth
import qs.Commons
import qs.Ui
import "BluetoothLogic.js" as Logic

// The Bluetooth section of the System window, mounted in the holder of
// the `panes` capability, which draws its title and scrolls it: a body
// alone, from x 0, its height its implicitHeight.
//
// From the top: the power switch (PowerField.qml); while the Bluetooth
// service is off, the `power` status entry's action, Turn on the service,
// offered as the core's status rows offer it (`status.rows`) and run
// through `status.act`; Discoverable, which
// lets other devices find this computer and pair with it while this
// section is shown and while the adapter stays discoverable; Hide when off,
// the bar icon's setting, written through `configure` to every entry the
// plugin reads; the pairing's line; and My Devices and Nearby
// (DeviceSections.qml). A discovery lease looks for nearby devices while
// Bluetooth is on, and the section's teardown ends it.
//
// Pairing runs in Pairing.qml, which holds the core's pairing agent while
// a pairing runs; Discoverable holds a lease of its own. Every agent prompt
// answers through one Dialog (Prompt.qml), which a rename shares.
//
// The payload is a JSON object: `{}`, or `{"pair":"<address>"}`, which
// pairs that device, as the flyout's Nearby rows ask.
FocusScope {
    id: root

    property var shell: null
    readonly property bool powerOn: power.powerOn
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool discoverable: adapter !== null && adapter.discoverable
    readonly property bool hideWhenOff: shell !== null && shell.settings.hideWhenOff === true
    // The `power` status entry's action while the core offers it,
    // { label }, else null.
    readonly property var serviceAction: {
        if (shell === null) return null;
        const row = shell.status.rows.find(r => r.key === "power");
        return row === undefined || row.action === null || !row.action.offered ? null : { label: row.action.label };
    }
    // The agent lease Discoverable holds.
    property var discoverLease: null
    readonly property string discoverLeaseState: discoverLease === null ? "" : discoverLease.state
    // The device a rename names, by address, "" for none.
    property string renameAddress: ""
    // The refusal the last setting write was answered with, "" for none.
    property string problem: ""
    readonly property Item initialFocus: power.toggle

    implicitWidth: Theme.size.window.width
    implicitHeight: Math.max(content.implicitHeight, prompt.implicitHeight)
    focus: true

    function open(payloadJson) {
        const payload = payloadJson === "" ? {} : JSON.parse(payloadJson);
        if (payload === null || typeof payload !== "object" || Array.isArray(payload))
            throw new Error("bluetooth: payload must be a JSON object, got " + payloadJson);
        if (payload.pair === undefined) return;
        if (typeof payload.pair !== "string") throw new Error("bluetooth: payload pair must be an address, got " + JSON.stringify(payload.pair));
        pairing.start(payload.pair);
    }

    function close() { setDiscoverable(false); }

    Component.onDestruction: setDiscoverable(false)

    function setHideWhenOff(value) {
        const reply = shell.configure.set("hideWhenOff", value);
        problem = reply === "ok" ? "" : "VGS could not save this setting.";
        if (reply !== "ok") console.warn("bluetooth: configure " + reply);
        return reply;
    }

    // Run the `power` entry's action, which turns the Bluetooth service on
    // in the core's system setup; answers the core's reply.
    function turnOnService() {
        const reply = shell.status.act("power");
        power.problem = reply === "ok" ? "" : "VGS could not open the Bluetooth service setup.";
        if (reply !== "ok") console.warn("bluetooth: act power " + reply);
        return reply;
    }

    // Discoverable holds an agent lease, so a device that pairs from its
    // side gets its prompts here, and lets the adapter be found. BlueZ ends
    // Discoverable on its own timeout and at power-off, which releases the
    // lease too.
    function setDiscoverable(wanted) {
        if (wanted && discoverLease === null && shell !== null) discoverLease = shell.bluetoothAgent.begin("accept pairing requests");
        if (!wanted && discoverLease !== null) {
            discoverLease.release();
            discoverLease = null;
        }
        if (adapter !== null && adapter.discoverable !== wanted) adapter.discoverable = wanted;
    }

    onDiscoverableChanged: if (!discoverable && discoverLease !== null) setDiscoverable(false)

    // The dialog's answer to the open prompt, or to a rename.
    function answer(value) {
        if (prompt.kind === "rename") {
            const device = Logic.deviceAt(Bluetooth.devices.values, renameAddress);
            if (device !== null) device.name = value;
            renameAddress = "";
            return;
        }
        if (pairing.answer(value) !== "ok") prompt.error = Logic.promptRefusal(prompt.kind);
    }

    function dismiss() {
        if (prompt.kind === "rename") renameAddress = "";
        else pairing.dismiss();
    }

    DiscoveryLease {
        shell: root.shell
        active: root.powerOn
    }

    Pairing {
        id: pairing
        shell: root.shell
    }

    Column {
        id: content
        width: root.width
        spacing: Theme.stack.group

        PowerField {
            id: power
            width: parent.width
            shell: root.shell
        }

        RowAction {
            visible: root.serviceAction !== null
            text: root.serviceAction === null ? "" : root.serviceAction.label
            onClicked: root.turnOnService()
        }

        RowAction {
            visible: power.power !== null && power.power.key === "rfkill-missing"
            text: "Install rfkill"
            onClicked: {
                const reply = root.shell.requirements.offer(["rfkill"]);
                if (reply !== "ok" && reply !== "satisfied") console.warn("bluetooth: requirements " + reply);
            }
        }

        Field {
            width: parent.width
            label: "Discoverable"
            inline: true
            enabled: root.powerOn
            hint: root.discoverLeaseState === "refused"
                ? "Another app handles Bluetooth pairing, so pairing requests go there."
                : "Other devices can find this computer while this page is open."
            Switch {
                size: "sm"
                Accessible.name: "Discoverable"
                checked: root.discoverable
                onToggled: {
                    const wanted = checked;
                    checked = Qt.binding(() => root.discoverable);
                    root.setDiscoverable(wanted);
                }
            }
        }

        Field {
            width: parent.width
            label: "Hide when off"
            inline: true
            hint: "Hide the bar icon while Bluetooth is off."
            error: root.problem
            Switch {
                size: "sm"
                Accessible.name: "Hide when off"
                checked: root.hideWhenOff
                onToggled: {
                    const wanted = checked;
                    checked = Qt.binding(() => root.hideWhenOff);
                    root.setHideWhenOff(wanted);
                }
            }
        }

        Label {
            width: parent.width
            visible: text !== ""
            role: "body"
            text: pairing.text
            color: pairing.current.phase === "failed" ? Theme.color.danger : Theme.color.text
            wrapMode: Text.Wrap
        }

        DeviceSections {
            width: parent.width
            powerOn: root.powerOn
            manage: true
            pairBusy: pairing.active
            onPairRequested: address => pairing.start(address)
            onRenameRequested: address => root.renameAddress = address
        }
    }

    Prompt {
        id: prompt
        anchors.fill: parent
        request: pairing.request
        deviceName: pairing.who
        renaming: {
            if (root.renameAddress === "") return "";
            const device = Logic.deviceAt(Bluetooth.devices.values, root.renameAddress);
            return device === null ? "" : Logic.deviceName(device);
        }
        onAnswered: value => root.answer(value)
        onDismissed: root.dismiss()
    }
}
