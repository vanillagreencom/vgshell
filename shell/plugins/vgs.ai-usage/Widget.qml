import QtQuick
import qs.Commons
import qs.Ui
import "UsageView.js" as View

// The highest share of a plan limit used among the signed-in accounts, in
// the warning tone from View.WARNING_PERCENT. It takes no room while no
// account is signed in. A click opens or closes the panel under it.
BarWidget {
    id: root
    readonly property var usage: shell === null || shell.status.values.usage === undefined ? null : shell.status.values.usage
    readonly property var view: View.widget(usage, shell === null ? null : shell.settings)
    readonly property bool shown: view.shown
    readonly property var percent: view.percent
    readonly property string tone: view.tone

    visible: shown
    implicitWidth: shown ? item.implicitWidth : 0
    implicitHeight: barSize

    function toggle() {
        const reply = shell.surfaces.toggle("panel", "{}", root);
        if (reply !== "ok") console.warn("ai-usage: widget panel " + reply);
        return reply;
    }

    BarItem {
        id: item
        anchors.centerIn: parent
        label: "AI Usage"
        text: root.view.text
        iconName: "gauge"
        tone: root.tone === "warning" ? Theme.badge.tone.warning.foreground : root.bar ? root.bar.foreground : Theme.bar.foreground
        tooltip: root.view.tooltip
        onClicked: root.toggle()
    }
}
