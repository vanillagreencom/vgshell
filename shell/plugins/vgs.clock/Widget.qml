import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
    id: root

    readonly property string format: String(setting("clockFormat", ""))

    // The shared clock ticks every second only while a widget shows seconds.
    // A quoted literal such as 'secs' is not a seconds field.
    readonly property bool showsSeconds: format.replace(/'[^']*'/g, "").indexOf("s") !== -1
    onShowsSecondsChanged: Time.holdSeconds(root, root.showsSeconds)
    Component.onCompleted: Time.holdSeconds(root, root.showsSeconds)
    Component.onDestruction: Time.holdSeconds(root, false)

    implicitWidth: button.width
    implicitHeight: barSize
    Accessible.name: "Clock"

    BarItem {
        id: button
        anchors.centerIn: parent
        text: Qt.formatDateTime(Time.now, root.format)
        tone: root.bar ? root.bar.foreground : Theme.bar.foreground
        onClicked: {
            const reply = root.shell.surfaces.toggle("panel", "{}", button);
            if (reply !== "ok") console.warn("vgs.clock: calendar " + reply);
        }
    }
}
