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
    readonly property string rateSample: Logic.rateSample(kbDigits, mbDigits)

    // Each speed holds the width it lays out to at the rate sample and
    // draws right aligned in it, so the arrow stays beside its rate and the
    // held room sits before the arrow.
    component Speed: Item {
        id: speed
        property string arrow: ""
        property string rate: ""
        property string sample: ""
        implicitWidth: line.implicitWidth + reading.room
        implicitHeight: line.implicitHeight
        Row {
            id: line
            anchors.right: parent.right
            spacing: Theme.row.lineGap
            Label { role: "bar"; text: speed.arrow; color: Theme.color.accent }
            BarItem.Reading { id: reading; text: speed.rate; sample: speed.sample; font.capitalization: Font.MixedCase }
        }
    }
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

    BarItem {
        id: button
        anchors.centerIn: parent
        label: "Network Traffic"
        // It draws text, so it keeps a text item's padding: BarItem reads an
        // item with no text, count or caption of its own as icon-only.
        leftPadding: Theme.bar.item.paddingX
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
                Speed { visible: root.showMode !== "upload"; arrow: "↓"; rate: root.rate(root.traffic.down); sample: root.rateSample }
                Speed { visible: root.showMode !== "download"; arrow: "↑"; rate: root.rate(root.traffic.up); sample: root.rateSample }
            }
        }
    }
}
