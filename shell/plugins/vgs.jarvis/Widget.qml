import QtQuick
import qs.Commons
import qs.Ui
import "WidgetView.js" as View

// The Jarvis icon in the bar. It draws the status the service publishes
// and runs nothing itself: one closed state table decides off, loading,
// ready, listening, working, speaking, muted and problem. The tooltip
// names what happens, the next action and the mute action. A click, Space
// (which the button turns into a click), Return and keypad Enter call the
// service's `mute` IPC handler, the intent the Mute key sends. It is one
// BarItem.
BarWidget {
    id: root

    // Core/Plugins.qml createWidget hands this widget the plugin's shell,
    // whose settings hold the talk mode from the first frame; the Session's
    // own settings arrive only after the daemon's hello.
    readonly property var view: shell === null ? View.view({}, View.spelledKeys(null, KeyNavLogic.keyCaps), "hold")
        : View.view(shell.status.values, View.spelledKeys(shell.shortcut.keys, KeyNavLogic.keyCaps), shell.settings.mode)

    implicitWidth: item.implicitWidth
    implicitHeight: barSize

    function toneColor(tone) {
        switch (tone) {
        case "calm": return Theme.bar.foreground;
        case "accent": return Theme.badge.tone.accent.foreground;
        case "info": return Theme.badge.tone.info.foreground;
        case "danger": return Theme.badge.tone.danger.foreground;
        case "neutral": return Theme.badge.tone.neutral.foreground;
        default: throw new Error("jarvis widget: tone " + JSON.stringify(tone) + " is not one of calm, accent, info, danger, neutral");
        }
    }

    // Toggle privacy mute through the service; answers the handler's reply.
    function toggleMute() {
        const reply = shell.ipc.call("mute", "");
        if (reply !== "ok") console.warn("jarvis widget: mute " + reply);
        return reply;
    }

    BarItem {
        id: item
        anchors.centerIn: parent
        label: "Jarvis"
        iconName: root.view.icon
        tone: root.toneColor(root.view.tone)
        tooltip: root.view.tooltip
        tooltipDetails: root.view.tooltipDetails
        onClicked: root.toggleMute()
    }
}
