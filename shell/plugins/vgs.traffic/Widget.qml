import QtQuick
import qs.Commons
import qs.Ui
import "TrafficLogic.js" as Logic

BarWidget {
    id: root
    readonly property var traffic: shell === null ? ({}) : shell.status.values.traffic || ({})
    readonly property string showMode: setting("show", "both")
    implicitWidth: button.implicitWidth
    implicitHeight: barSize

    function toggle() {
        const reply = shell.surfaces.toggle("panel", "{}", root);
        if (reply !== "ok") console.warn("traffic: panel " + reply);
        return reply;
    }

    TextMetrics { id: rateSize; font.family: Theme.text.bar.family; font.pixelSize: Theme.text.bar.size; text: "88.8 MB/s" }
    BarItem {
        id: button
        anchors.centerIn: parent
        label: "Network Traffic"
        tooltip: "Network Traffic"
        tooltipDetails: (root.traffic.interfaces || []).map(row => row.name + "  ↓ " + Logic.formatRate(row.down) + "  ↑ " + Logic.formatRate(row.up))
        onClicked: root.toggle()
        contentItem: Item {
            implicitWidth: rates.implicitWidth
            implicitHeight: rates.implicitHeight
            Row {
                id: rates
                anchors.centerIn: parent
                spacing: Theme.stack.inline
                Row {
                    visible: root.showMode !== "upload"
                    spacing: Theme.row.lineGap
                    Label { role: "bar"; text: "↓"; color: Theme.color.accent }
                    Label { role: "bar"; text: Logic.formatRate(root.traffic.down); width: Math.max(rateSize.width, implicitWidth) }
                }
                Row {
                    visible: root.showMode !== "download"
                    spacing: Theme.row.lineGap
                    Label { role: "bar"; text: "↑"; color: Theme.color.accent }
                    Label { role: "bar"; text: Logic.formatRate(root.traffic.up); width: Math.max(rateSize.width, implicitWidth) }
                }
            }
        }
    }
}
