import QtQml
import "BluetoothLogic.js" as Logic

// Bluetooth power as the flyout's title switch and the System pane's
// PowerField both read it: the published power view, the refusal the last
// press left and the line under the switch, and the one request that turns
// Bluetooth on or off.
QtObject {
    id: root

    property var shell: null
    readonly property var power: shell === null ? null : Logic.publishedPower(shell.status.values)
    readonly property bool powerOn: power !== null && power.on
    // The line a refused press left, "" for none.
    property string problem: ""
    readonly property var line: Logic.powerLine(power, problem)

    // Ask the service to turn Bluetooth on or off; answers its reply.
    function setPower(on) {
        const reply = shell.ipc.call("power", on ? "on" : "off");
        problem = reply === "ok" ? "" : "VGS could not turn Bluetooth " + (on ? "on" : "off") + ".";
        return reply;
    }
}
