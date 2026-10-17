import QtQuick
import qs.Commons
import qs.Ui

// A labelled control with a hint and an error line: the control goes in
// the body, `label` above it (or beside it when `inline` holds, in a
// FormRow, which owns the key/value row's geometry), `hint` under it, and
// `error` in the hint's place in the error colour while it is set.
// `hintLink`, when set, names words of the hint drawn as a link, which
// the pointer, Return, Enter and Space activate through
// `hintLinkActivated`; the error line carries none. A page reference in
// the hint (LinkText) is its link, activated through `hintPageActivated`,
// and one in the `info` dialog's text through `infoPageActivated`.
// `lines` are further lines of the value, each in the value role, between
// the control and the hint, such as what a setup step still needs. Form
// feedback is this plain sentence-case line; a chip, a fill or capitals
// mark only a state the user must act on now. An
// inline hint starts under the value column, `field.gap` under the value
// however far the label column reaches, a label of two lines or an info
// mark beside it, and the field ends with the lower of the hint and the row
// box, so a label taller than the value and the hint still ends the row.
// `inkBelow()` is how far above its bottom edge the lowest drawn part
// ends: the row's, its lines' or its hint's. Width comes from the parent;
// the label, the control and the hint sit `field.paddingX` in from each
// side. The default is zero, so a field's unboxed label sits on the
// container's content edge and its control ends on that edge. `valueX` is
// where the value column starts, for content that belongs under it.
// `subText` holds while the lines, the hint or the error line show; the
// field then takes room under them so the next item of its column that is
// no key/value row starts `stack.group` below the last line
// (Theme.subTextRoom). An inline field with a label is a key/value row,
// and one under another key/value row of its column (`keyValueRow`) stands
// `stack.page` under that row's drawn ink, from its lowest drawn pixel to
// this row's highest (Theme.inkBelow, Theme.inkAbove), whatever either
// control draws in its row box: its top padding takes out of that space
// the column's spacing and both blanks, and goes negative where those
// exceed it, so the row boxes overlap where the controls draw less than
// the box. Ink is drawn in whole pixel rows on whole-pixel item edges, as
// Section measures it, so the padding counts whole rows. A field that is
// the first item of a column, such as the editor of a SettingField, reads
// the row above that column. A set
// `disabledReason` goes to the control that takes one (DisabledReason); a
// reason no control takes is logged.
Column {
    id: root

    property string label: ""
    property string hint: ""
    property string info: ""
    property string labelTooltip: ""
    property string error: ""
    property string hintLink: ""
    property var lines: []
    property bool inline: Theme.field.inline
    property string disabledReason: ""
    default property alias control: controlRow.control
    // The control that takes the reason, or null.
    readonly property Item reasonTarget: {
        for (const child of controlRow.control)
            if (child.disabledReason !== undefined) return child;
        return null;
    }
    // The width the label, the control's row and the hint share: the
    // column's own, less its padding, since a positioner does not narrow
    // its children.
    readonly property real bodyWidth: width - leftPadding - rightPadding
    readonly property real valueX: leftPadding + controlRow.valueX
    readonly property bool subText: lines.length > 0 || hintLine.text !== ""
    // A row a key/value row under it is spaced from by ink; a column that
    // holds rows of one setting, such as a SettingField, declares it too.
    readonly property bool keyValueRow: inline
    // The key/value row this one stands under, and the room the columns
    // already put between the two: the spacing of the column that holds
    // both and the top padding of each column this field is the first
    // shown item of. The first group of a GroupList stands at the list's
    // top, so the search goes on above the list; a later group keeps the
    // list's gap and hairline. null for a field with no label beside its
    // control, under anything that is no key/value row, such as a
    // section's heading, or under nothing. A Column lays out only its
    // shown, sized children
    // (https://doc.qt.io/qt-6/qml-qtquick-column.html).
    readonly property var rowAbove: {
        if (!inline || label === "") return null;
        let room = 0;
        for (let at = root; at.parent !== null; ) {
            const holder = at.parent;
            const list = holder.parent instanceof GroupList ? holder.parent : null;
            if (!(holder instanceof Column) && list === null) return null;
            const siblings = holder.children;
            let below = true;
            for (let i = siblings.length - 1; i >= 0; i--) {
                const item = siblings[i];
                if (item === at) below = false;
                else if (!below && item.visible && item.width > 0 && item.height > 0)
                    return list === null && item.keyValueRow === true ? { item: item, room: room + holder.spacing } : null;
            }
            if (list === null) room += holder.topPadding;
            at = list === null ? holder : list;
        }
        return null;
    }
    signal hintLinkActivated()
    signal hintPageActivated(string page, string tab)
    signal infoPageActivated(string page, string tab)

    Binding {
        target: root.reasonTarget
        property: "disabledReason"
        value: root.disabledReason
        when: root.reasonTarget !== null && root.disabledReason !== ""
    }
    function judgeReason() {
        if (disabledReason !== "" && reasonTarget === null)
            console.error("Field: disabledReason=" + JSON.stringify(disabledReason) + " no control takes it, label=" + JSON.stringify(label));
    }
    onDisabledReasonChanged: judgeReason()
    Component.onCompleted: judgeReason()

    topPadding: rowAbove === null ? 0 : Theme.stack.page - rowAbove.room - Math.floor(Theme.inkBelow(rowAbove.item)) - Math.floor(controlRow.inkAbove())
    leftPadding: Theme.field.paddingX
    rightPadding: Theme.field.paddingX
    bottomPadding: Theme.subTextRoom(subText, Positioner.index, Positioner.isLastItem, parent)
    // An inline field's lines take their gap from the value, inside the
    // slot, which starts at the row box's bottom.
    spacing: inline ? 0 : Theme.field.gap

    // No child's `y` is read, since a positioner sets it on a later polish
    // than a page's height is read for a resize (Theme.inkBelow); the slot
    // takes `spacing` under the row while it has height, and a Column skips
    // a child of none.
    function inkBelow() {
        const room = hintSlot.visible && hintSlot.height > 0 ? spacing + hintSlot.height : 0;
        const below = bottomPadding + room + controlRow.inkBelow();
        if (!subText) return below;
        const slotTop = bottomPadding + room - spacing;
        return Math.min(below, slotTop - hintSlot.textBottom + hintSlot.textInkBelow());
    }

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
                onInfoPageActivated: (page, tab) => root.infoPageActivated(page, tab)
            }
        }
    }

    FormRow {
        id: controlRow
        width: root.bodyWidth
        label: root.label
        info: root.info
        labelTooltip: root.labelTooltip
        labelColumn: root.inline
        textBelow: root.inline && root.subText
        Component.onCompleted: infoPageActivated.connect(root.infoPageActivated)
    }

    Item {
        id: hintSlot
        visible: root.subText
        width: root.bodyWidth
        // Where the lines start in the slot: `field.gap` under the value,
        // which a taller label column centres lower in the row box, so
        // above the slot's top while the box reaches more than the gap
        // under the value.
        readonly property real textTop: root.inline ? controlRow.valueBottom + Theme.field.gap - controlRow.height : 0
        // The lines' block, then the hint `field.gap` under it; the last
        // of them ends the text, and the text or the row box the slot.
        readonly property real linesHeight: root.lines.length > 0 ? subLines.implicitHeight + (hintLine.text !== "" ? Theme.field.gap : 0) : 0
        readonly property real textBottom: textTop + linesHeight + (hintLine.text !== "" ? hintLine.implicitHeight : 0)
        function textInkBelow() { return hintLine.text !== "" ? hintLine.inkBelow() : Theme.inkBelow(subLines); }
        // How far the text sits below where the slot is: none while the
        // Column places it, and the slot's stale `y` for a slot of no
        // height, which the Column skips.
        readonly property real shift: controlRow.y + controlRow.height + root.spacing - y
        height: Math.max(0, textBottom)

        LinkText {
            id: hintLine
            role: "hint"
            text: root.error !== "" ? root.error : root.hint
            link: root.error !== "" ? "" : root.hintLink
            color: root.error !== "" ? Theme.color.danger : Theme.text.hint.color
            x: controlRow.valueX
            y: hintSlot.shift + hintSlot.textTop + hintSlot.linesHeight
            width: parent.width - x
            wrapMode: Text.Wrap
            onActivated: root.hintLinkActivated()
            onPageActivated: (page, tab) => root.hintPageActivated(page, tab)
        }

        Column {
            id: subLines
            x: hintLine.x
            y: hintSlot.shift + hintSlot.textTop
            width: parent.width - x
            spacing: Theme.field.gap

            Repeater {
                model: root.lines
                Label {
                    required property string modelData
                    role: "value"
                    text: modelData
                    width: subLines.width
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}
