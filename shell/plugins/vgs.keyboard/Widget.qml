import QtQuick
import qs.Ui

BarWidget {
    id: widget
    readonly property var active: shell === null || shell.status.values.active === undefined ? ({ code: "", name: "", count: 0 }) : shell.status.values.active
    visible: active.count > 1
    implicitWidth: visible ? button.implicitWidth : 0
    implicitHeight: barSize
    frameActions: [{ label: "Keyboard Settings", action: () => shell.surfaces.summon("pane", "{}") }]

    function switchNext() {
        const reply = shell.hyprland.switchKeyboardLayout("next");
        if (reply !== "ok") console.warn("keyboard: switch " + reply);
        return reply;
    }

    BarItem {
        id: button
        anchors.centerIn: parent
        text: widget.active.code
        label: "Keyboard layout"
        tooltip: widget.active.name
        onClicked: widget.switchNext()
    }
}
