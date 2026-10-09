import QtQuick
import qs.Commons
import qs.Ui

// Date and time from the shared clock, in the bar's `clockFormat`, on a bar
// item at the bar's vertical centre, where the workspace pills sit. The
// shared clock ticks once a second only while some format on some screen
// shows seconds. A click opens or closes the bar's calendar panel
// (Calendar.qml) under the item.
Item {
    id: root

    // The bar, read for its `shell` alone; it goes before its built-ins when
    // a screen goes away, so the read is null-checked.
    required property Item bar
    readonly property string format: bar && bar.shell !== null ? String(bar.shell.settings.clockFormat) : ""

    // A quoted literal such as 'secs' is not a seconds field.
    readonly property bool showsSeconds: format.replace(/'[^']*'/g, "").indexOf("s") !== -1
    onShowsSecondsChanged: Time.holdSeconds(root, root.showsSeconds)
    Component.onCompleted: Time.holdSeconds(root, root.showsSeconds)
    Component.onDestruction: Time.holdSeconds(root, false)

    implicitWidth: button.width
    implicitHeight: Theme.bar.height

    BarItem {
        id: button
        anchors.centerIn: parent
        text: Qt.formatDateTime(Time.now, root.format)
        tone: Theme.bar.foreground
        onClicked: {
            const reply = root.bar && root.bar.shell !== null ? root.bar.shell.surfaces.toggle("panel", "{}", button) : "refused: shell=none";
            if (reply !== "ok") console.warn("vgs.bar: calendar " + reply);
        }
    }
}
