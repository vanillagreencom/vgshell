import QtQuick
import qs.Commons
import qs.Ui
import "PowerLogic.js" as Logic

// The Power flyout under the bar widget. It shows the service's published
// battery view and one SegmentedControl for the available power profiles.
// A user choice goes to the service through IPC, which owns the
// PowerProfiles write and the remembered profile for this power source.
FocusScope {
    id: root

    property var shell: null
    readonly property var power: shell === null || shell.status.values.power === undefined ? null : shell.status.values.power
    readonly property var battery: power && power.battery ? power.battery : { present: false, level: 0, charging: false, state: "absent", secondsToEmpty: 0, secondsToFull: 0 }
    readonly property var profile: power && power.profile ? power.profile : { available: false, active: "balanced", choices: [] }
    readonly property var profileLabels: profile.choices.map(p => Logic.profileLabel(p))
    readonly property int activeIndex: Math.max(0, profile.choices.indexOf(profile.active))
    property string problem: ""
    property Item initialFocus: profileControl.visible ? profileControl : null
    focus: true
    Keys.onRightPressed: event => {
        event.accepted = true;
        chooseProfile(Math.min(profile.choices.length - 1, activeIndex + 1));
    }
    Keys.onLeftPressed: event => {
        event.accepted = true;
        chooseProfile(Math.max(0, activeIndex - 1));
    }

    function open(payloadJson) {
        problem = "";
        Qt.callLater(() => {
            if (profileControl.visible) profileControl.forceActiveFocus(Qt.TabFocusReason);
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

        header: [
            Label {
                role: "h3"
                text: "Power"
            }
        ]

        Column {
            width: layout.contentWidth
            spacing: Theme.stack.group

            Column {
                visible: root.battery.present
                width: parent.width
                spacing: Theme.stack.row

                FormRow {
                    width: parent.width
                    label: "Battery"
                    Label { role: "value"; text: root.battery.level + "%" }
                }
                Label {
                    role: "body"
                    text: Logic.stateLabel(root.battery)
                }
                ProgressBar {
                    width: parent.width
                    from: 0
                    to: 100
                    value: root.battery.level
                }
                Label {
                    visible: text !== ""
                    role: "hint"
                    text: Logic.timeText(root.battery)
                }
            }

            Field {
                width: parent.width
                visible: root.profile.available
                label: "Power profile"
                error: root.problem
                SegmentedControl {
                    id: profileControl
                    visible: root.profile.available && root.profile.choices.length > 0
                    model: root.profileLabels
                    currentIndex: root.activeIndex
                    onActivated: index => root.chooseProfile(index)
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
