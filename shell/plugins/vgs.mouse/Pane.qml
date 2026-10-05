import QtQuick
import qs.Commons
import qs.Ui
import "MouseLogic.js" as Logic

FocusScope {
    id: root

    property var shell: null
    property int clicks: 0
    readonly property var deviceRows: shell === null ? [] : Logic.deviceRows(shell.hyprland.devices)
    readonly property Item initialFocus: controls.firstFocus

    function open(payloadJson) {}
    function close() {}

    implicitWidth: Theme.size.window.width
    implicitHeight: content.implicitHeight
    focus: true

    Column {
        id: content
        width: root.width
        spacing: Theme.stack.group

        MouseControls {
            id: controls
            width: parent.width
            shell: root.shell
        }

        SectionHeader {
            width: parent.width
            text: "Devices"
            description: "Pointer devices from Hyprland."
        }

        Column {
            width: parent.width
            spacing: Theme.stack.row

            Repeater {
                model: root.deviceRows
                DeviceRow {
                    width: root.width
                    text: modelData.text
                    secondary: modelData.secondary
                    iconName: modelData.icon
                    badge: modelData.badge
                    badgeTone: "neutral"
                }
            }

            Label {
                visible: root.deviceRows.length === 0
                width: root.width
                role: "hint"
                text: "No pointer devices are listed."
                wrapMode: Text.Wrap
            }
        }

        SectionHeader {
            width: parent.width
            text: "Try it"
            description: "Scroll this box and click the target to feel the settings."
        }

        ScrollArea {
            width: parent.width
            height: Math.min(implicitHeight, Theme.size.panel.md)
            keyboardScroll: true

            Column {
                width: root.width - Theme.space.md
                spacing: Theme.stack.row

                Repeater {
                    model: ["Slow scroll check", "Middle scroll check", "Fast scroll check"]
                    Label {
                        width: root.width - Theme.space.md
                        role: "body"
                        text: modelData
                    }
                }

                Button {
                    text: "Click target " + root.clicks
                    iconName: "mouse-pointer-click"
                    onClicked: root.clicks += 1
                }
            }
        }
    }
}
