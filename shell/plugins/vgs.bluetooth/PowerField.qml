import QtQuick
import qs.Commons
import qs.Ui

// The power switch the System pane keeps: the shared Bluetooth power state
// as a Switch, with the line BluetoothLogic.powerLine picks under it as a
// hint or an error. A refused press keeps its line until the next press.
Field {
    id: root

    property var shell: null
    readonly property alias power: powerState.power
    readonly property alias powerOn: powerState.powerOn
    readonly property alias toggle: powerSwitch
    property alias problem: powerState.problem
    readonly property alias line: powerState.line

    function setPower(on) { return powerState.setPower(on); }

    Power {
        id: powerState
        shell: root.shell
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
