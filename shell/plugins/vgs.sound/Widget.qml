import QtQuick
import qs.Commons
import qs.Ui
import "SoundLogic.js" as Logic

// The Sound icon in the bar: the output level as one of SoundLogic's level
// icons, `volume-off` while PipeWire is not there. A left click opens or
// closes the flyout under it, the wheel steps the volume by `volumeStep`
// and a middle click mutes the output; the step and the mute go to the
// service through the plugin's own IPC, which shows the on-screen display,
// so the widget starts no process. The tooltip names the output and its
// level.
BarWidget {
    id: widget

    readonly property string iconName: Logic.levelIcon(audio.available, audio.volume, audio.muted)
    readonly property string tooltip: Logic.widgetTooltip(audio.available, audio.outputLabel, audio.volume, audio.muted)
    // Wheel angle not yet a whole notch, so a touchpad's small deltas add up.
    property real wheelCarry: 0

    implicitWidth: button.implicitWidth
    implicitHeight: barSize

    // Open or close the flyout under this widget; answers the panel host's
    // reply.
    function toggle() {
        return answered("panel", shell.surfaces.toggle("panel", "{}", widget));
    }

    // Step the volume by DELTA wheel angle; answers the service's reply to
    // the last step, or "" when the angle made no whole notch.
    function wheel(delta) {
        const turned = Logic.wheelSteps(wheelCarry, delta);
        wheelCarry = turned.carry;
        let reply = "";
        for (let i = 0; i < Math.abs(turned.steps); i++)
            reply = answered("step", shell.ipc.call("step", turned.steps > 0 ? "up" : "down"));
        return reply;
    }

    function mute() {
        return answered("mute", shell.ipc.call("mute", ""));
    }

    function answered(what, reply) {
        if (Logic.replyFailed(reply)) console.warn("sound widget: " + what + " " + reply);
        return reply;
    }

    Audio { id: audio }

    BarItem {
        id: button
        anchors.centerIn: parent
        label: "Sound"
        iconName: widget.iconName
        tooltip: widget.tooltip
        onClicked: widget.toggle()

        // keyboard-path: the mute key, vgs.sound:mute, mutes the output as the middle click does
        // pointer-cursor-exempt: it adds the middle click to the BarItem it sits in, whose own PointerCursor shows the hand
        TapHandler {
            acceptedButtons: Qt.MiddleButton
            onTapped: widget.mute()
        }

        // keyboard-path: the volume keys, vgs.sound:volume-up and volume-down, step the volume as the wheel does
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => widget.wheel(event.angleDelta.y)
        }
    }
}
