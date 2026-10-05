import QtQuick
import qs.Commons
import qs.Ui
import "BluetoothLogic.js" as Logic

// The power switch the flyout and the pane share: the published power view
// as a Switch, which asks the service to turn Bluetooth on or off, with
// the line BluetoothLogic.powerLine picks under it as a hint or an error.
// A refused press keeps its line until the next press.
Field {
    id: root

    property var shell: null
    readonly property var power: shell === null ? null : Logic.publishedPower(shell.status.values)
    readonly property bool powerOn: power !== null && power.on
    readonly property alias toggle: powerSwitch
    // The line a refused press left, "" for none.
    property string problem: ""
    readonly property var line: Logic.powerLine(power, problem)

    // Ask the service to turn Bluetooth on or off; answers its reply.
    function setPower(on) {
        const reply = shell.ipc.call("power", on ? "on" : "off");
        problem = reply === "ok" ? "" : "VGS could not turn Bluetooth " + (on ? "on" : "off") + ".";
        return reply;
    }

    label: "Bluetooth"
    inline: true
    hint: line.hint
    error: line.error

    Switch {
        id: powerSwitch
        size: "sm"
        Accessible.name: "Bluetooth"
        checked: root.powerOn
        enabled: root.power !== null && root.power.canToggle
        onToggled: {
            const wanted = checked;
            checked = Qt.binding(() => root.powerOn);
            root.setPower(wanted);
        }
    }
}
