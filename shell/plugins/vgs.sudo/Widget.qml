import QtQuick
import qs.Commons
import qs.Ui
import "SudoView.js" as View

// The passwordless sudo lock in the bar: locked while no grant is active,
// open in the warning tone while one is, a question mark while the core
// could not read the grant, and NixOS's snowflake where the system
// configuration holds it (SudoView.look). A click on the open lock opens
// the core revoke TUI, which asks nothing and closes by itself; any other
// click opens the core grant TUI, which asks how long, starting on the
// default duration. The instance that was clicked sends the notification
// once the run ended and the core read the grant again, so every bar does
// not send its own.
BarWidget {
    id: root

    // The core's last read of the grant, null without the capability.
    readonly property var grant: shell === null ? null : shell.sudo.state
    readonly property bool granted: View.active(grant)
    readonly property var look: View.look(grant)
    readonly property string tooltipText: View.tooltip(grant, root.timeOf)

    implicitWidth: item.implicitWidth
    implicitHeight: barSize

    function timeOf(iso) {
        return Qt.formatTime(new Date(iso), "HH:mm");
    }

    // Turns the grant on or off; answers the core's shown answer.
    function toggle() {
        const before = grant === null ? "unknown" : grant.state;
        const answer = granted
            ? shell.sudo.revoke(result => root.ended("revoke", before, result))
            : shell.sudo.grant(String(setting("defaultDuration", "15")), result => root.ended("grant", before, result));
        if (answer !== "ok") console.warn("sudo: widget " + answer);
        return answer;
    }

    function ended(action, before, result) {
        const notice = View.notice(action, before, result, Date.now(), root.timeOf);
        if (notice === null) return;
        const sent = shell.notify.send(notice);
        if (sent !== "ok") console.warn("sudo: notice " + sent);
    }

    BarItem {
        id: item
        anchors.centerIn: parent
        label: "Passwordless sudo"
        iconName: root.look.icon
        tone: root.look.tone !== "bar" ? Theme.badge.tone[root.look.tone].foreground : root.bar ? root.bar.foreground : Theme.bar.foreground
        tooltip: root.tooltipText
        onClicked: root.toggle()
    }
}
