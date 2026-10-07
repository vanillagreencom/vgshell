import QtQuick
import qs.Ui

BarWidget {
    id: widget
    readonly property int statusRevision: shell === null ? 0 : shell.status.revision
    property var active: ({ code: "", name: "", count: 0 })
    visible: active.count > 1
    implicitWidth: visible ? button.implicitWidth : 0
    implicitHeight: barSize
    frameActions: [
        { label: "Keyboard controls", action: () => widget.toggleControls() },
        { label: "Keyboard Settings", action: () => shell.surfaces.summon("pane", "{}") }
    ]

    // Only this plugin's revision changes refresh its snapshot. QML's
    // handler reads once without binding to the global status map.
    onStatusRevisionChanged: refreshStatus()
    onShellChanged: refreshStatus()

    function refreshStatus() {
        const values = shell === null ? {} : shell.status.values;
        active = values.active === undefined ? ({ code: "", name: "", count: 0 }) : values.active;
    }

    function toggleControls() {
        const reply = shell.surfaces.toggle("panel", "{}", widget);
        if (reply !== "ok") console.warn("keyboard: panel " + reply);
        return reply;
    }

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
