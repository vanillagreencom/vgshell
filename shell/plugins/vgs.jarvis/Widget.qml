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

    // Core/Plugins.qml createWidget assigns shell.settings to this bar-widget.
    // Session settings arrive only after daemon hello, so the widget reads the
    // truthful talk mode from shell.settings.
    readonly property string talkMode: shell === null ? "hold" : String(shell.settings.mode)
    readonly property var spelledKeys: ({
        talk: spellKey("talk"),
        mute: spellKey("mute"),
        stop: spellKey("stop"),
        confirm: spellKey("confirm")
    })
    readonly property var view: View.view(shell === null ? ({}) : shell.status.values, spelledKeys, talkMode)

    implicitWidth: item.implicitWidth
    implicitHeight: barSize

    function spellKey(name) {
        if (shell === null || shell.shortcut === undefined || (shell.shortcut.keys[name] === undefined || shell.shortcut.keys[name] === null)) return null;
        return KeyNavLogic.keyCaps(shell.shortcut.keys[name]).join("+");
    }

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
