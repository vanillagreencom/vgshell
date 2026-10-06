import QtQml
import "BluetoothLogic.js" as Logic

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
