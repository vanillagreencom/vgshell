import QtQuick
import qs.Commons
import qs.Ui
import "TrafficLogic.js" as Logic

BarWidget {
    id: root
    readonly property var traffic: shell === null ? ({}) : shell.status.values.traffic || ({})
    readonly property string showMode: setting("show", "both")
    readonly property int kbDigits: setting("kbDecimals", 0)
    readonly property int mbDigits: setting("mbDecimals", 1)
    function rate(value) { return Logic.formatRate(value, kbDigits, mbDigits); }
    property bool leased: false
    function hold() {
        if (shell !== null && !leased) leased = shell.ipc.call("lease", JSON.stringify({ id: String(root), open: true, kind: "widget" })) === "ok";
    }
    onShellChanged: hold()
    onTrafficChanged: hold()
    Component.onDestruction: if (leased && shell !== null) shell.ipc.call("lease", JSON.stringify({ id: String(root), open: false }))
    implicitWidth: button.implicitWidth
    implicitHeight: barSize

    function toggle() {
        const reply = shell.surfaces.toggle("panel", "{}", root);
        if (reply !== "ok") console.warn("traffic: panel " + reply);
        return reply;
    }

    TextMetrics { id: rateSize; font.family: Theme.text.bar.family; font.pixelSize: Theme.text.bar.size; text: Logic.rateSample(2, root.kbDigits, root.mbDigits) }
    BarItem {
        id: button
        anchors.centerIn: parent
        label: "Network Traffic"
        tooltip: "Network Traffic"
        tooltipDetails: (root.traffic.interfaces || []).map(row => row.name + "  ↓ " + root.rate(row.down) + "  ↑ " + root.rate(row.up))
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
                    Label { role: "bar"; text: root.rate(root.traffic.down); font.capitalization: Font.MixedCase; width: Math.max(rateSize.width, implicitWidth) }
                }
                Row {
                    visible: root.showMode !== "download"
                    spacing: Theme.row.lineGap
                    Label { role: "bar"; text: "↑"; color: Theme.color.accent }
                    Label { role: "bar"; text: root.rate(root.traffic.up); font.capitalization: Font.MixedCase; width: Math.max(rateSize.width, implicitWidth) }
                }
            }
        }
    }
}
