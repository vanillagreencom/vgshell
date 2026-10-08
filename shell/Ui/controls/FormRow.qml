import QtQuick
import qs.Commons
import qs.Ui

// The one key/value row: a label column `field.labelWidth` wide, then the
// control slot, `field.labelGap` after the column, bounded by
// `control.maxWidth`. The control stays on the value column's start edge. The row box is `row.height` tall unless its label wraps or its
// control is taller, so every key/value row of a page shares one height. A
// one-line label is placed by capital height, a two-line label is centred,
// and the control is centred by its box. A label too long for its column
// wraps to a second line before it elides. `warning` is the row's message:
// `hint` text under the value column, `field.gap` below the row box and
// wrapped to the column, in the colour `warningTone` names, `warning`,
// `danger` or `muted`. `warningLink`, when set, names the substring of
// `warning` that opens a cited file through `warningLinkActivated`. The
// row grows by the gap and the message's height, and the label and the
// control stay centred on the row box, so a message takes no room from its
// control. Light feedback in a form is this line, plain sentence-case text
// in a muted or status colour. A chip, a fill or capitals are for a state
// the user must act on now, with the action beside it. `action` is one
// control for the message, such as a RowAction that undoes what the message
// names: it draws on the message's line, on the row's end edge, only while
// the row has a message, and the message wraps `stack.inline` before it.
// Where that would leave the message less than `field.labelWidth`, as in a
// narrow flyout, the action goes on a line of its own, `field.gap` under
// the message, from the value column's start. While the row has a message
// it takes room under it, so the next row of its column starts
// `stack.group` below the message (Theme.subTextRoom).
// A hidden action takes no room. While
// `labelColumn` is false the row draws no label and keeps
// no row height: the control takes the full width at its own height, as a
// Field whose label stands above its control does. `valueX` is where the
// value column starts, for content that belongs under it. Width comes from
// the parent.
Item {
    id: root

    property string label: ""
    property string warning: ""
    property string warningLink: ""
    property string warningTone: "warning"
    property string info: ""
    property string labelTooltip: ""
    property bool labelColumn: true
    default property alias control: slot.data
    property alias action: actionSlot.data
    readonly property Item actionItem: actionSlot.visibleChildren.length > 0 ? actionSlot.visibleChildren[0] : null
    readonly property bool actionBelow: actionItem !== null && valueRoom - actionItem.width - Theme.stack.inline < Theme.field.labelWidth
    readonly property real actionRoom: actionItem === null || actionBelow ? 0 : actionItem.width + Theme.stack.inline
    readonly property real messageLine: actionBelow ? message.height + Theme.field.gap + actionItem.height : Math.max(message.height, actionItem === null ? 0 : actionItem.height)
    readonly property real valueX: labelColumn ? Theme.field.labelWidth + Theme.field.labelGap : 0
    readonly property real valueRoom: Math.max(0, width - valueX)
    readonly property real messageRoom: warning === "" ? 0 : Theme.field.gap + messageLine
    readonly property real subTextRoom: Theme.subTextRoom(warning !== "", Positioner.index, Positioner.isLastItem, parent)
    // Where the message's line ends, above the room under it.
    readonly property real messageBottom: height - subTextRoom
    readonly property real boxHeight: messageBottom - messageRoom
    signal warningLinkActivated()

    function toneColor(name) {
        if (name === "warning") return Theme.color.warning;
        if (name === "danger") return Theme.color.danger;
        if (name === "muted") return Theme.text.hint.color;
        console.error("FormRow: no warningTone named " + JSON.stringify(name));
        return Theme.color.warning;
    }

    // Smoke rows read this hook to verify all key/value rows use one
    // height without depending on the private tree shape.
    objectName: "fieldRow"
    implicitWidth: slot.x + Math.max(Theme.field.minWidth, Math.min(Theme.control.maxWidth, slot.childrenRect.width))
    implicitHeight: (labelColumn ? Math.max(Theme.row.height, labelText.implicitHeight, slot.childrenRect.height) : slot.childrenRect.height) + messageRoom + subTextRoom

    Label {
        id: labelText
        objectName: "fieldLabel"
        activeFocusOnTab: root.labelTooltip !== "" && visible
        readonly property bool visualFocus: activeFocus
        Tooltip { text: root.labelTooltip }
        FocusRing { target: labelText; outside: true }
        role: "label"
        text: root.label
        visible: root.labelColumn
        width: Theme.field.labelWidth - (infoButton.active ? infoButton.width + Theme.space.xs : 0)
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        y: lineCount > 1 ? Math.round((root.boxHeight - implicitHeight) / 2) : topForCapCenter(root.boxHeight)
    }

    Loader {
        id: infoButton
        active: root.info !== "" && root.labelColumn
        x: Theme.field.labelWidth - width
        y: Math.round((root.boxHeight - implicitHeight) / 2)
        sourceComponent: InfoButton {
            title: root.label
            info: root.info
        }
    }

    Item {
        id: slot
        x: root.valueX
        width: Math.min(root.valueRoom, Theme.control.maxWidth)
        height: childrenRect.height
        y: root.labelColumn ? Math.round((root.boxHeight - height) / 2) : 0
    }

    LinkText {
        id: message
        role: "hint"
        text: root.warning
        link: root.warningLink
        color: root.toneColor(root.warningTone)
        visible: root.warning !== ""
        x: slot.x
        y: root.boxHeight + Theme.field.gap + (root.actionBelow ? 0 : Math.round((root.messageLine - height) / 2))
        width: root.valueRoom - root.actionRoom
        wrapMode: Text.Wrap
        onActivated: root.warningLinkActivated()
    }

    Item {
        id: actionSlot
        visible: message.visible
        x: root.actionBelow ? slot.x : root.width - width
        y: root.actionBelow ? root.messageBottom - height : root.messageBottom - root.messageLine + Math.round((root.messageLine - height) / 2)
        width: root.actionItem === null ? 0 : root.actionItem.width
        height: root.actionItem === null ? 0 : root.actionItem.height
    }
}
