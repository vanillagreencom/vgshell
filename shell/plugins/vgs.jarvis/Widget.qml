import QtQuick
import qs.Commons
import qs.Ui
import "WidgetView.js" as View
import "AccountProviders.js" as Providers
import "Session.js" as Session

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
    readonly property bool hidden: detail !== null && detail.state.visibility.kind === "hidden"
    // The host observes this real BarItem and its existing dot. The widget
    // neither acknowledges a frame nor sends an admission grant.
    presentationItem: item
    presentationKey: detail === null ? "" : detail.state.gen + ":" + (view.state === "listening" ? "listening" : "present")
    frameActions: View.menuEntries(root.microphoneMuted, root.voiceMuted, root.hidden,
        Session.hideRefusal(detail === null ? null : detail.state))
        .concat(view.click === "resume" ? [{ label: "Do not resume", icon: "x", intent: "dismiss-resume" }] : [])
        .map(entry => {
            const action = entry.intent !== undefined ? () => root.offer(entry.intent)
                : () => root.shell.surfaces.openPage(entry.page, entry.tab);
            return { label: entry.label, icon: entry.icon, disabledReason: entry.disabledReason || "",
                action: action };
        })

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
        label: root.view.tooltip + (root.hasAsks ? ", " + root.ownerAsks.activeCount + " asks need you" : "")
        iconName: root.view.icon
        tone: root.toneColor(root.view.tone)
        stateDot: root.view.stateDot
        count: root.hasAsks ? String(root.ownerAsks.activeCount) : ""
        tooltip: root.view.tooltip
        tooltipDetails: root.view.tooltipDetails
        onTooltipPageActivated: (page, tab) => root.frame.openPage(page, tab)
        onClicked: root.view.click === "resume" ? root.offer("resume-session") : root.openConsole()
    }
}
