import QtQuick
import qs.Commons
import qs.Ui

// A labelled control with a hint and an error line: the control goes in
// the body, `label` above it (or beside it when `inline` holds, in a
// FormRow, which owns the key/value row's geometry), `hint` under it, and
// `error` in the hint's place in the error colour while it is set. Form
// feedback is this plain sentence-case line; a chip, a fill or capitals
// mark only a state the user must act on now. An
// inline hint starts under the value column. Width comes from the parent;
// the label, the control and the hint sit `field.paddingX` in from each
// side. The default is zero, so a field's unboxed label sits on the
// container's content edge and its control ends on that edge. `valueX` is
// where the value column starts, for content that belongs under it.
// `subText` holds while the hint or error line shows; the field then takes
// room under it so the next row of its column starts `stack.group` below
// the line (Theme.subTextRoom).
Column {
    id: root

    property string label: ""
    property string hint: ""
    property string info: ""
    property string error: ""
    property bool inline: Theme.field.inline
    default property alias control: controlRow.control
    // The width the label, the control's row and the hint share: the
    // column's own, less its padding, since a positioner does not narrow
    // its children.
    readonly property real bodyWidth: width - leftPadding - rightPadding
    readonly property real valueX: leftPadding + controlRow.valueX
    readonly property bool subText: hintLine.text !== ""

    leftPadding: Theme.field.paddingX
    rightPadding: Theme.field.paddingX
    bottomPadding: Theme.subTextRoom(subText, Positioner.index, Positioner.isLastItem, parent)
    spacing: Theme.field.gap

    Item {
        id: labelLine
        visible: root.label !== "" && !root.inline
        width: root.bodyWidth
        height: Math.max(fieldLabel.implicitHeight, topInfo.implicitHeight)

        Label {
            id: fieldLabel
            role: "label"
            text: root.label
            width: parent.width - (topInfo.active ? topInfo.width + Theme.space.xs : 0)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
        }

        Loader {
            id: topInfo
            active: root.info !== ""
            anchors.left: fieldLabel.right
            anchors.leftMargin: Theme.space.xs
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: InfoButton {
                title: root.label
                info: root.info
            }
        }
    }

    FormRow {
        id: controlRow
        width: root.bodyWidth
        label: root.label
        info: root.info
        labelColumn: root.inline
    }

    Item {
        id: hintSlot
        visible: root.subText
        width: root.bodyWidth
        readonly property real slack: {
            if (!root.inline) return 0;
            let bottom = 0;
            for (const child of controlRow.children) {
                if (child.visible) bottom = Math.max(bottom, child.y + child.height);
            }
            return Math.max(0, controlRow.height - bottom);
        }
        height: Math.max(0, hintLine.implicitHeight - slack)

        Label {
            id: hintLine
            role: "hint"
            text: root.error !== "" ? root.error : root.hint
            color: root.error !== "" ? Theme.color.danger : Theme.text.hint.color
            x: controlRow.valueX
            y: -hintSlot.slack
            width: parent.width - x
            wrapMode: Text.Wrap
        }
    }
}
