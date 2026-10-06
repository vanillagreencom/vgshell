import QtQuick
import qs.Commons
import qs.Ui

// The Bluetooth flyout: the shared title-row power switch, your devices
// and the devices nearby (DeviceSections.qml). A click on one of your
// devices connects or disconnects it; a click on a nearby device opens the
// System window's Bluetooth section, which pairs it, since pairing asks
// through a dialog there. A discovery lease looks for nearby devices while
// the flyout is open and Bluetooth is on, and the flyout's teardown ends
// it. It takes no payload, and opens with the keyboard on the power
// switch in the shared header.
Item {
    id: root

    // The core assigns the plugin's scoped shell object after creation, and
    // again when the plugin's settings change.
    property var shell: null
    property Item initialFocus: layout.headerSwitch

    function open(payloadJson) { power.problem = ""; }
    function close() {}

    // Open the Bluetooth section on ADDRESS, which pairs it there.
    function pairInPane(address) {
        const reply = shell.surfaces.summon("pane", JSON.stringify({ pair: address }));
        if (reply !== "ok") {
            power.problem = "Open System Settings to pair this device.";
            console.warn("bluetooth panel: pane " + reply);
            return reply;
        }
        shell.surfaces.hide("panel");
        return reply;
    }

    function openSettings() {
        const reply = shell.surfaces.summon("pane", "{}");
        if (reply !== "ok") console.warn("bluetooth panel: pane " + reply);
        else shell.surfaces.hide("panel");
        return reply;
    }

    implicitWidth: Theme.size.panel.md
    implicitHeight: layout.implicitHeight

    DiscoveryLease {
        shell: root.shell
        active: power.powerOn
    }

    Power {
        id: power
        shell: root.shell
    }

    Surface {
        anchors.fill: parent
    }

    Pane {
        id: layout
        anchors.fill: parent
        container: "panel"
        fitToContent: true
        maximumHeight: Theme.size.panel.maxHeight
        title: "Bluetooth"
        switchShown: true
        switchChecked: power.powerOn
        switchEnabled: power.power !== null && power.power.canToggle
        switchName: "Bluetooth"
        onSwitchToggled: checked => power.setPower(checked)

        Label {
            width: layout.contentWidth
            visible: text !== ""
            role: "hint"
            text: power.line.hint !== "" ? power.line.hint : power.line.error
            color: power.line.error !== "" ? Theme.color.danger : Theme.text.hint.color
            wrapMode: Text.Wrap
        }

        DeviceSections {
            width: layout.contentWidth
            powerOn: power.powerOn
            onPairRequested: address => root.pairInPane(address)
        }

        footer: [
            Button {
                width: layout.contentWidth
                variant: "tertiary"
                text: "Bluetooth Settings"
                iconName: "settings"
                onClicked: root.openSettings()
            }
        ]
    }
}
