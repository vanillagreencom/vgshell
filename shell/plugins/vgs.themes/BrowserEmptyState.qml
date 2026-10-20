import QtQuick
import qs.Commons
import qs.Ui

// What an empty rail shows: an icon, one line and, for a filter no card
// matches, Clear filter, each `stack.group` from the next. They sit on the
// scrim in the rail's text colours, as the tabs and the search line do.
// Clear filter is a word like Show all: brighter and underlined under the
// pointer, since `carousel.hint` and `carousel.hintActive` are near one
// black or white there.
BrowserSlot {
    id: root

    property string iconName: ""
    property string text: ""
    property string actionText: ""
    signal activated()

    implicitHeight: column.implicitHeight

    Column {
        id: column
        width: root.width
        spacing: Theme.stack.group

        Icon {
            x: Math.round((parent.width - width) / 2)
            visible: root.iconName !== ""
            name: root.iconName
            size: Theme.icon.size.xl
            color: Theme.carousel.hint
        }
        Label {
            role: "itemHint"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Theme.carousel.hint
            text: root.text
        }
        // A MouseArea takes no focus, so the view keeps the keyboard.
        // keyboard-path: Escape and Ctrl+U clear the filter as a click does
        MouseArea {
            id: action
            x: Math.round((parent.width - width) / 2)
            width: Math.ceil(actionLabel.implicitWidth)
            height: actionLabel.implicitHeight
            visible: root.actionText !== ""
            hoverEnabled: true
            Accessible.role: Accessible.Button
            Accessible.name: root.actionText
            onClicked: root.activated()
            PointerCursor {}

            Label {
                id: actionLabel
                role: "itemHint"
                text: root.actionText
                color: action.containsMouse ? Theme.carousel.hintActive : Theme.carousel.hint

                TextUnderline { label: actionLabel; visible: action.containsMouse }
            }
        }
    }
}
