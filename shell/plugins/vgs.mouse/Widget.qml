import QtQuick
import qs.Commons
import qs.Ui
import "MouseLogic.js" as Logic

BarWidget {
    id: widget

    readonly property bool hasTouchpad: shell !== null && Logic.hasTouchpad(shell.hyprland.devices)

    implicitWidth: button.implicitWidth
    implicitHeight: barSize

    function toggle() {
        const reply = shell.surfaces.toggle("panel", "{}", widget);
        if (reply !== "ok") console.warn("mouse widget: panel " + reply);
        return reply;
    }

    BarItem {
        id: button
        anchors.centerIn: parent
        label: "Mouse"
        iconName: widget.hasTouchpad ? "touchpad" : "mouse-pointer"
        tooltip: widget.hasTouchpad ? "Mouse and touchpad" : "Mouse"
        onClicked: widget.toggle()
    }
}
