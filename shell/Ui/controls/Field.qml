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
// `stack.page` under that row's drawn ink, from its lowest drawn part to
// this row's highest, whatever either control draws in its row box, by
// the rule a bare FormRow stands by: its FormRow searches for the row
// above and measures the space (FormRow `rowAbove`, `inkTop`), and the
// field takes it as its top padding. A text line, the label, a Label
// value, the lines and the hint, counts from its capital top to its
// font's descent line, or its baseline in a role drawn in capitals, not by
// the glyphs it holds, so rows of one role keep one pitch whatever they
// read (FormRow.lineAbove, `lineBelow()`); a control counts as drawn
// (Theme.inkAbove, Theme.inkBelow). The top padding takes out of that
// space the column's spacing and both blanks, and goes negative where
// those exceed it, so the row boxes overlap where the controls draw less
// than the box. A field that is the first item of a column, such as the
// editor of a SettingField, reads the row above that column. A set
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
    readonly property bool keyValueRow: controlRow.keyValueRow
    // Whether the field's column lays it out, and lineBelow(), as values a
    // key/value row under it reads (FormRow `rowAbove`).
    readonly property bool rowShown: visible && width > 0 && height > 0
    readonly property real belowLine: lineBelow()
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

    // The space above a key/value row, which its row measures (FormRow
    // `inkTop`), so a Field and a bare FormRow stand by one rule.
    topPadding: controlRow.inkTop
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

    // inkBelow() with each text line read by its font: where a key/value
    // row under this one measures from.
    function lineBelow() {
        const room = hintSlot.visible && hintSlot.height > 0 ? spacing + hintSlot.height : 0;
        const below = bottomPadding + room + controlRow.lineBelow();
        if (!subText) return below;
        const slotTop = bottomPadding + room - spacing;
        return Math.min(below, slotTop - hintSlot.textBottom + hintSlot.textLineBelow());
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
        placed: root
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
        // The same by the text's font (FormRow.fontBelow): the hint's role
        // through a probe line of it, a link's underline still counted.
        // `belowLine` reads this whenever the field changes, also while the
        // lines' Repeater holds no Label for `lines`: then no line draws.
        function textLineBelow() {
            if (hintLine.text === "") {
                const lines = Array.from(subLines.children).filter(child => child instanceof Label);
                return lines.length === 0 ? Theme.inkBelow(subLines) : controlRow.fontBelow(lines[lines.length - 1]);
            }
            const line = controlRow.fontBelow(hintProbe);
            return hintLine.linked ? Math.min(line, hintLine.inkBelow()) : line;
        }
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

        // One line of the hint's role, for its font's lines; last, after the
        // lines and the hint, which keep their places among the children.
        Label {
            id: hintProbe
            visible: false
            role: "hint"
        }
    }
}
