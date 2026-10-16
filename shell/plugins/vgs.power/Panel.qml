import QtQuick
import qs.Commons
import qs.Ui
import "PowerLogic.js" as Logic

// The Power flyout under the bar widget. It shows the service's published
// battery view and one full-width TileGroup that lists the profiles the
// daemon offers, with the active one marked.
// A user choice goes to the service through IPC, which owns the profile
// write and the remembered profile for this power source.
FocusScope {
    id: root

    property var shell: null
    readonly property var power: shell === null || shell.status.values.power === undefined ? null : shell.status.values.power
    readonly property var battery: power && power.battery ? power.battery : { present: false, level: 0, charging: false, state: "absent", secondsToEmpty: 0, secondsToFull: 0 }
    readonly property var profile: power && power.profile ? power.profile : { available: false, active: "balanced", choices: [] }
    readonly property var profileTiles: profile.choices.map(p => ({ text: Logic.profileLabel(p), icon: Logic.profileIcon(p), available: true }))
    readonly property int activeIndex: Math.max(0, profile.choices.indexOf(profile.active))
    property string problem: ""
    property Item initialFocus: profileControl.visible ? profileControl : null
    focus: true

    function open(payloadJson) {
        problem = "";
        Qt.callLater(() => {
            if (profileControl.visible) profileControl.forceActiveFocus(Qt.OtherFocusReason);
        });
    }
    function close() {}

    function chooseProfile(index) {
        if (index < 0 || index >= profile.choices.length) return "";
        const reply = shell.ipc.call("profile", profile.choices[index]);
        profileControl.currentIndex = Qt.binding(() => root.activeIndex);
        problem = Logic.validProfile(reply) ? "" : "VGS could not set the power profile.";
        if (!Logic.validProfile(reply)) console.warn("power panel: profile " + reply);
        return reply;
    }

    implicitWidth: Theme.size.panel.md
    implicitHeight: layout.implicitHeight

    Surface { anchors.fill: parent }

    Pane {
        id: layout
        anchors.fill: parent
        container: "panel"
        fitToContent: true
        maximumHeight: Theme.size.panel.maxHeight

        title: "Power"

        Column {
            width: layout.contentWidth
            spacing: Theme.stack.group

            Column {
                visible: root.battery.present
                width: parent.width
                spacing: Theme.stack.row

                Field {
                    width: parent.width
                    inline: true
                    label: "Battery"
                    lines: [Logic.stateLabel(root.battery)]
                    hint: Logic.timeText(root.battery)
                    Label { role: "value"; text: root.battery.level + "%" }
                }
                ProgressBar {
                    width: parent.width
                    from: 0
                    to: 100
                    value: root.battery.level
                }
            }

            Column {
                visible: root.profile.available
                width: parent.width
                spacing: Theme.stack.row

                TileGroup {
                    id: profileControl
                    width: parent.width
                    visible: root.profile.choices.length > 0
                    model: root.profileTiles
                    currentIndex: root.activeIndex
                    onActivated: index => root.chooseProfile(index)
                }
                Label {
                    width: parent.width
                    visible: text !== ""
                    role: "hint"
                    color: Theme.color.danger
                    text: root.problem
                    wrapMode: Text.Wrap
                }
            }
            Label {
                visible: !root.profile.available
                role: "body"
                text: "Power profiles are not available."
            }
        }
    }
}
