import QtQuick
import qs.Commons
import qs.Ui
import "WidgetView.js" as View
import "AccountProviders.js" as Providers

// The Jarvis icon in the bar. It draws the status the service publishes
// and runs nothing itself: one closed state table decides off, loading,
// ready, listening, working, speaking, muted and problem. The tooltip
// names what happens, the next action and what a click does. A click,
// Space (which the button turns into a click), Return and keypad Enter
// call the service's `console` IPC handler, which opens the console; while
// the Resume offer stands (WidgetView `click`) they call `resume-session`
// instead. The right-click menu adds Mute Jarvis or Unmute Jarvis, the
// intent the Mute key sends, and Do not resume while the offer stands. It
// is one BarItem.
BarWidget {
    id: root

    // Core/Plugins.qml createWidget hands this widget the plugin's shell,
    // whose settings hold the talk mode and the voice from the first frame;
    // the Session's own settings arrive only after the daemon's hello.
    readonly property var view: shell === null ? View.view({}, View.spelledKeys(null, KeyNavLogic.keyCaps), "hold", null)
        : View.view(shell.status.values, View.spelledKeys(shell.shortcut.keys, KeyNavLogic.keyCaps), shell.settings.mode,
            Providers.cloudVoice(shell.settings.voiceProvider))

    implicitWidth: item.implicitWidth
    implicitHeight: barSize
    // Whether Jarvis is muted or turning muted, as the service last read it.
    readonly property bool muted: shell !== null && shell.status.values.detail !== undefined && shell.status.values.detail !== null
        && View.muted(shell.status.values.detail.state.mute)
    // Unmute draws Jarvis's own J: the microphone is the Voice widget's.
    frameActions: [{ label: root.muted ? "Unmute Jarvis" : "Mute Jarvis", icon: root.muted ? "vgs-letter-j" : "mic-off", action: () => root.toggleMute() }]
        .concat(view.click === "resume" ? [{ label: "Do not resume", icon: "x", action: () => root.offer("dismiss-resume") }] : [])

    function toneColor(tone) {
        switch (tone) {
        case "calm": return Theme.bar.foreground;
        case "accent": return Theme.color.accent;
        case "info": return Theme.color.info;
        case "danger": return Theme.color.danger;
        case "neutral": return Theme.color.textMuted;
        default: throw new Error("jarvis widget: tone " + JSON.stringify(tone) + " is not one of calm, accent, info, danger, neutral");
        }
    }

    // Toggle privacy mute through the service; answers the handler's reply.
    function toggleMute() {
        const reply = shell.ipc.call("mute", "");
        if (reply !== "ok") console.warn("jarvis widget: mute " + reply);
        return reply;
    }

    // Open the console through the service; answers the handler's reply.
    function openConsole() {
        const reply = shell.ipc.call("console", "");
        if (reply !== "ok") console.warn("jarvis widget: console " + reply);
        return reply;
    }

    // NAME, the service's resume-session or dismiss-resume handler, while
    // the Resume offer stands; answers the handler's reply.
    function offer(name) {
        const reply = shell.ipc.call(name, "");
        if (reply !== "ok") console.warn("jarvis widget: " + name + " " + reply);
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
        onTooltipPageActivated: (page, tab) => root.frame.openPage(page, tab)
        onClicked: root.view.click === "resume" ? root.offer("resume-session") : root.openConsole()
    }
}
