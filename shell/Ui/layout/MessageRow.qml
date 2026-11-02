import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// One message or ask: a fixed avatar, name and time, then its text. A
// source link stands apart from the small secondary buttons that answer it.
// Buttons take { id, label, disabledReason }; each keeps the shared reason,
// keyboard and focus behavior. The row itself takes no click or focus.
Item {
    id: root

    property string sender: ""
    property string timeText: ""
    property string initials: ""
    property string avatarIcon: ""
    property string title: ""
    property string bodyText: ""
    property string linkText: ""
    property string stateText: ""
    property string stateTone: "neutral"
    property string above: ""
    property var actions: []
    readonly property Item linkControl: sourceLink
    readonly property real avatarSize: Theme.size.control.sm
    readonly property real paddingY: Theme.stack.inline
    readonly property real contentX: avatarSize + Theme.stack.group

    signal sourceActivated()
    signal actionTriggered(string id)

    function actionAt(index) { return actionItems.itemAt(index); }

    implicitHeight: content.implicitHeight + 2 * paddingY

    AvatarGroup {
        id: avatar
        y: root.paddingY
        size: root.avatarSize
        initialsShare: Theme.text.hint.size / root.avatarSize
        people: [{ initials: root.avatarIcon === "" ? root.initials : "" }]
    }
    Icon {
        visible: root.avatarIcon !== ""
        name: root.avatarIcon
        size: Theme.icon.size.md
        color: Theme.avatarGroup.foreground
        anchors.centerIn: avatar
    }
    Column {
        id: content
        x: root.contentX
        y: root.paddingY
        width: Math.max(0, root.width - x)
        spacing: Theme.row.lineGap

        Label {
            visible: root.above !== ""
            width: parent.width
            role: "hint"
            text: root.above
            textFormat: Text.PlainText
            color: Theme.color.textMuted
            wrapMode: Text.Wrap
        }
        Item {
            width: parent.width
            height: Math.max(root.avatarSize, names.implicitHeight, state.visible ? state.height : 0)
            Flow {
                id: names
                width: Math.max(0, parent.width - (state.visible ? state.width + Theme.stack.inline : 0))
                spacing: Theme.stack.inline
                anchors.verticalCenter: parent.verticalCenter
                Label {
                    id: senderLabel
                    role: "bodyStrong"
                    text: root.sender
                    textFormat: Text.PlainText
                    width: Math.min(implicitWidth, parent.width)
                    wrapMode: Text.Wrap
                }
                Item {
                    width: Math.min(timeLabel.implicitWidth, parent.width)
                    height: Math.max(senderLabel.implicitHeight, timeLabel.implicitHeight)
                    Label {
                        id: timeLabel
                        role: "hint"
                        text: root.timeText
                        textFormat: Text.PlainText
                        color: Theme.color.textMuted
                        width: parent.width
                        wrapMode: Text.Wrap
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
            Badge {
                id: state
                visible: root.stateText !== ""
                text: root.stateText
                tone: root.stateTone
                width: Math.min(implicitWidth, parent.width)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Label {
            visible: root.title !== ""
            width: parent.width
            role: "bodyStrong"
            text: root.title
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
        }
        Label {
            visible: root.bodyText !== ""
            width: parent.width
            role: "body"
            text: root.bodyText
            textFormat: Text.PlainText // Source text can contain markup.
            wrapMode: Text.Wrap
        }
        LinkText {
            id: sourceLink
            visible: root.linkText !== ""
            width: parent.width
            text: root.linkText
            link: root.linkText
            wrapMode: Text.Wrap
            onActivated: root.sourceActivated()
            // A label that resembles a page reference cannot replace the
            // original source destination the caller holds.
            onPageActivated: (page, tab) => root.sourceActivated()
        }
        Item {
            visible: root.actions.length > 0
            width: parent.width
            implicitHeight: buttons.implicitHeight + Theme.stack.inline
            RowActions {
                id: buttons
                y: Theme.stack.inline
                width: parent.width
                gap: Theme.stack.page
                Repeater {
                    id: actionItems
                    // Stable keys preserve focused controls on republication.
                    // Read payloads from the owner to support Quickshell 0.3.1
                    // even when actions move and their current reason changes.
                    model: ScriptModel { values: root.actions.map(action => String(action.id)) }
                    Button {
                        required property var modelData
                        readonly property var actionData: root.actions.find(action => String(action.id) === String(modelData))
                            || ({ id: "", label: "", disabledReason: "Action is no longer available." })
                        text: actionData.label
                        variant: "secondary"
                        size: "sm"
                        disabledReason: actionData.disabledReason === undefined ? "" : actionData.disabledReason
                        onClicked: root.actionTriggered(actionData.id)
                    }
                }
            }
        }
    }
}
