import QtQuick
import qs.Commons
import qs.Ui
import "WidgetView.js" as View
import "AccountProviders.js" as Providers

// The Jarvis icon in the bar. It draws the status the service publishes
// and runs nothing itself: one closed state table decides off, loading,
// ready, listening, working, speaking, muted and problem. The tooltip
// names the current status. A click,
// Space (which the button turns into a click), Return and keypad Enter
// call the service's `console` IPC handler, which opens the console; while
// the Resume offer stands (WidgetView `click`) they call `resume-session`
// instead. The right-click menu adds the Jarvis menu the overlay's right
// click opens too (WidgetView.menuEntries): the microphone's and the
// voice's mute, Stop and Key hints, each intent sent through the service's
// IPC handler of its name and Key hints opening its page through
// shell.surfaces.openPage, as the overlay's menu does, and Do not resume
// while the offer stands. It is one BarItem.
BarWidget {
    id: root

    // Core/Plugins.qml createWidget hands this widget the plugin's shell,
    // whose settings hold the Talk preference and voice from the first frame;
    // the Session's own settings arrive only after the daemon's hello.
    readonly property var view: shell === null ? View.view({}, null)
        : View.view(shell.status.values, Providers.cloudVoice(shell.settings.voiceProvider))

    readonly property var ownerAsks: shell === null || shell.status.values.ownerAsks === undefined ? null : shell.status.values.ownerAsks
    readonly property bool hasAsks: ownerAsks !== null && ownerAsks.kind === "ready" && ownerAsks.activeCount > 0
    implicitWidth: item.implicitWidth
    implicitHeight: barSize
    readonly property var detail: shell === null || shell.status.values.detail === undefined ? null : shell.status.values.detail
    // System microphone and independent voice mute, as the service read them.
    readonly property var microphoneMuted: View.microphoneMuted(shell === null ? undefined : shell.status.values.microphoneMute)
    readonly property bool voiceMuted: detail !== null && detail.state.voiceMute.kind === "on"
    frameActions: View.menuEntries(root.microphoneMuted, root.voiceMuted).map(entry => ({ label: entry.label, icon: entry.icon,
        disabledReason: entry.disabledReason || "",
        action: entry.intent !== undefined ? () => root.offer(entry.intent) : () => root.shell.surfaces.openPage(entry.page, entry.tab) }))
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

    // Open the console through the service; answers the handler's reply.
    function openConsole() {
        const reply = shell.ipc.call("console", "");
        if (reply !== "ok") console.warn("jarvis widget: console " + reply);
        return reply;
    }

    // NAME, the service's handler of a Jarvis menu entry's intent, or its
    // resume-session or dismiss-resume handler while the Resume offer
    // stands; answers the handler's reply.
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
        tooltipDetails: root.view.tooltipDetails.concat(root.hasAsks ? [root.ownerAsks.activeCount + " asks need you"] : [])
        contentItem: Row {
            spacing: Theme.stack.inline
            Icon { name: item.iconName; size: Theme.bar.item.icon; color: item.tone; anchors.verticalCenter: parent.verticalCenter }
            Badge { visible: root.hasAsks; variant: "unread"; text: root.hasAsks ? String(root.ownerAsks.activeCount) : ""; anchors.verticalCenter: parent.verticalCenter }
        }
        onTooltipPageActivated: (page, tab) => root.frame.openPage(page, tab)
        onClicked: root.view.click === "resume" ? root.offer("resume-session") : root.openConsole()
    }
}
