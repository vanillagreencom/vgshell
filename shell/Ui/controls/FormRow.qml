import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// The one key/value row: a label column `field.labelWidth` wide, then the
// control slot, `field.labelGap` after the column, bounded by
// `control.maxWidth`. The control stays on the value column's start edge. The row box is `row.height` tall unless its label wraps or its
// control is taller, so every key/value row of a page shares one height. A
// one-line label is placed by capital height, a label of more lines is
// centred, and the control is centred by its box. A control taller than the
// row is one of two cases. One that is a single box, such as a text area,
// grows the row box, and a one-line label and its info button centre on
// that box. One that wraps into lines, such as a RowActions, declares
// `firstLineHeight`, the height of its first line while it wraps, and a
// one-line label and its info button centre on that line, as they do
// beside a one-line control; such a control grows the row, so its first
// line starts at the row box's top. A label too long for its
// column wraps onto as many lines as it needs and never elides; the row
// grows to hold them. `labelTooltip`, when set, is the label's tooltip on
// hover and keyboard focus. It ends on the row's end edge and moves no
// row. It opens centred on the label's box, past the
// control's drawn end (Theme.inkEnd), `tooltip.gap` after it, where its
// text wrapped to the room left there reaches no further than `stack.row`
// above or below that box and stops short of the first line under the
// value, so it covers neither its own control nor a row beside it and
// clips no hint. Otherwise, as beside a control that fills the value
// column, it opens under the row's label and control, as wide as the
// row, so it covers the whole of the line it lies on: the first line under
// the value, the row's message or text its owner draws there while
// `textBelow` holds, which it covers from that line's top. That band is one
// line: the room under that line's top holds no more. It stays clear
// of the label's focus ring, which draws outside the label's box: where
// the ring reaches that line, as under a label of two lines, it starts on
// the value column, beside the ring, and still covers the line from its
// top. A row with no such line has no room of its own under it, and an
// explainer too long for one line of the value column would run past that
// line onto the next row, so there the label opens no tooltip and is no Tab
// stop: the row's info button holds the explanation and opens it in its
// dialog, before `info` where the row has both. That button opens no
// tooltip: under it lies the next row's label, and past it its own row's
// control. `warning` is the row's message:
// text in the role `warningRole` names, `hint` unless set, under the value
// column, `field.gap` below the row box and
// wrapped to the column, in the colour `warningTone` names, `warning`,
// `danger` or `muted`. `warningLink`, when set, names the substring of
// `warning` that opens a cited file through `warningLinkActivated`. A page
// reference in `warning` (LinkText) is its link, activated through
// `warningPageActivated`, and one in the `info` dialog's text through
// `infoPageActivated`, each with the page and tab. The
// row grows by the gap and the message's height, and the label and the
// control stay centred on the row box, so a message takes no room from its
// control. Light feedback in a form is this line, plain sentence-case text
// in a muted or status colour. A chip, a fill or capitals are for a state
// the user must act on now, with the action beside it. `action` is one
// control for the message, such as a RowAction that undoes what the message
// names: it draws on the message's line, on the row's end edge, only while
// the row has a message, and the message wraps `stack.inline` before it.
// It centres on the message and keeps the message's height: an action
// taller than the message overhangs it and does not count in `inkBelow()`,
// so showing or hiding it moves no row and no heading below.
// Where that would leave the message less than `field.labelWidth`, as in a
// narrow flyout, the action goes on a line of its own, `field.gap` under
// the message, from the value column's start. While the row has a message
// it takes room under it, so the next row of its column starts
// `stack.group` below the message (Theme.subTextRoom).
// A hidden action takes no room. While
// `labelColumn` is false the row draws no label and keeps
// no row height: the control takes the full width at its own height, as a
// Field whose label stands above its control does. `valueX` is where the
// value column starts, for content that belongs under it, and
// `valueBottom` where the value's box ends in the row, for content under
// the value. Width comes from
// the parent. `inkBelow()` is how far above its bottom edge the row's
// lowest drawn part ends, its label, its control as drawn, its message or
// an action on a line of its own under that message, since the control
// centres in a taller row box. `inkAbove()` is how far below its top edge
// the highest drawn part starts, its label or its control as drawn.
// `lineAbove()` and `lineBelow()` read the same, but a text line, the
// label, a Label in the slot or the message, by its font rather than the
// glyphs it holds (`fontAbove()`, `fontBelow()`), so key/value rows of one
// role keep one pitch whatever they read (Field).
Item {
    id: root

    property string label: ""
    property string warning: ""
    property string warningLink: ""
    property string warningTone: "warning"
    property string warningRole: "hint"
    property string info: ""
    property string labelTooltip: ""
    property bool labelColumn: true
    property bool textBelow: false
    default property alias control: slot.data
    property alias action: actionSlot.data
    readonly property Item actionItem: actionSlot.visibleChildren.length > 0 ? actionSlot.visibleChildren[0] : null
    readonly property bool actionBelow: actionItem !== null && valueRoom - actionItem.width - Theme.stack.inline < Theme.field.labelWidth
    readonly property real actionRoom: actionItem === null || actionBelow ? 0 : actionItem.width + Theme.stack.inline
    readonly property real messageLine: actionBelow ? message.height + Theme.field.gap + actionItem.height : message.height
    readonly property real valueX: labelColumn ? Theme.field.labelWidth + Theme.field.labelGap : 0
    readonly property real valueRoom: Math.max(0, width - valueX)
    readonly property real valueBottom: slot.y + slot.height
    readonly property real messageRoom: warning === "" ? 0 : Theme.field.gap + messageLine
    readonly property real controlEnd: {
        let end = 0;
        for (const child of slot.children) {
            if (child.visible) end = Math.max(end, child.x + Theme.inkEnd(child));
        }
        return slot.x + end;
    }
    readonly property real besideX: controlEnd + Theme.tooltip.gap
    readonly property real besideWrap: Math.min(Theme.tooltip.maxWidth, width - besideX - 2 * Theme.tooltip.paddingX)
    readonly property real besideHeight: besideMeasure.implicitHeight + 2 * Theme.tooltip.paddingY
    // Where the first line under the value starts, -1 with no such line.
    readonly property real underText: textBelow ? valueBottom + Theme.field.gap : warning !== "" ? boxHeight + Theme.field.gap : -1
    // Whether the explainer, centred on the label's box, ends above that line.
    readonly property bool besideClear: underText < 0 ? true : (labelBox + besideHeight) / 2 <= underText
    readonly property bool explainBeside: besideWrap > 0 && besideHeight <= labelBox + 2 * Theme.stack.row && besideClear
    // Where the label's focus ring ends: it draws outside the label's box.
    readonly property real ringBottom: labelText.y + labelText.height + labelRing.extent
    // Whether that ring reaches the first line under the value.
    readonly property bool ringAtUnderText: underText >= 0 && ringBottom + Theme.tooltip.gap > underText
    // Where the explainer starts under the row, clear of that ring.
    readonly property real underX: ringAtUnderText ? valueX : 0
    // The box a one-line label centres on, whatever the label's own lines.
    readonly property real oneLineBox: controlFirstLine > 0 ? controlFirstLine : Math.max(Theme.row.height, slot.childrenRect.height)
    // Whether the row has a line under its value.
    readonly property bool underLine: textBelow || warning !== ""
    // Whether the explainer has room past the control beside a label of any
    // line count, and ends above a line under the value: less a pixel, which
    // the control's rounded centre can take.
    readonly property bool besideRoom: besideWrap > 0 && besideHeight <= oneLineBox + 2 * Theme.stack.row && (!underLine || besideHeight <= slot.childrenRect.height + 2 * Theme.field.gap - 1)
    // Whether the band over that line holds the explainer on one line of the
    // value column, the room it has beside a label ring that reaches the line.
    // A wrapped Text's implicitWidth is its width on one line.
    readonly property bool bandOneLine: underLine && Math.ceil(besideMeasure.implicitWidth) <= valueRoom - 2 * Theme.tooltip.paddingX
    // Whether the info button holds the explainer: a band under a row with
    // no line under its value, or of more than one line, would cover the
    // next row. The button narrows the label, so this reads neither the
    // label's line count nor a place that moves with it.
    readonly property bool explainInDialog: labelTooltip !== "" && labelColumn && !besideRoom && !bandOneLine
    readonly property string tipText: explainInDialog ? "" : labelTooltip
    readonly property string dialogText: !explainInDialog ? info : info === "" ? labelTooltip : labelTooltip + "\n\n" + info
    readonly property real subTextRoom: Theme.subTextRoom(warning !== "", Positioner.index, Positioner.isLastItem, parent)
    // Where the message's line ends, above the room under it.
    readonly property real messageBottom: height - subTextRoom
    readonly property real boxHeight: messageBottom - messageRoom
    // The box a one-line label and its info button centre on.
    readonly property real labelBox: labelText.lineCount > 1 || controlFirstLine === 0 ? boxHeight : controlFirstLine
    // The first line of a control that wraps into lines, 0 beside a control of one box.
    readonly property real controlFirstLine: {
        for (const child of slot.children) {
            if (child.visible && child.firstLineHeight > 0) return child.firstLineHeight;
        }
        return 0;
    }
    signal warningLinkActivated()
    signal warningPageActivated(string page, string tab)
    signal infoPageActivated(string page, string tab)

    function inkBelow() { return drawnBelow(false); }
    function inkAbove() { return drawnAbove(false); }
    function lineBelow() { return drawnBelow(true); }
    function lineAbove() { return drawnAbove(true); }

    // A text line's top and bottom by its font, not the glyphs it holds:
    // the capital top, and the last baseline plus the font's descent, or
    // the baseline for a role drawn in capitals. TEXT is a Label, or a probe
    // Label of a LinkText's role, whose lines share one line box, so its
    // last baseline stands as far above its bottom. The descent is the
    // font's height less its ascent, the capital centre plus half the
    // capital height: QFontMetricsF::height() is always ascent() + descent()
    // (https://doc.qt.io/qt-6/qfontmetricsf.html#height).
    function fontAbove(text) { return text.capTop(); }
    function fontBelow(text) {
        const baseline = text.height - text.lastBaseline();
        if (text.typography.uppercase) return baseline;
        const capital = text.baselineOffset - text.capTop();
        return baseline - (text.fontHeight - text.capCentre - capital / 2);
    }
    // A link's underline, under the descent line, still ends the message.
    function messageBelow() {
        const line = fontBelow(messageProbe);
        return message.linked ? Math.min(line, message.inkBelow()) : line;
    }

    // How far above its bottom edge the row's lowest drawn part ends, each
    // text line read by its font while BYFONT holds and by its glyphs
    // otherwise.
    function drawnBelow(byFont) {
        let bottom = labelColumn && label !== "" ? labelText.y + labelText.height - (byFont ? fontBelow(labelText) : labelText.inkBelow()) : 0;
        for (const child of slot.children) {
            if (child.visible) bottom = Math.max(bottom, slot.y + child.y + child.height - (byFont && child instanceof Label ? fontBelow(child) : Theme.inkBelow(child)));
        }
        if (message.visible) bottom = Math.max(bottom, message.y + message.height - (byFont ? messageBelow() : message.inkBelow()));
        if (actionSlot.visible && root.actionBelow) bottom = Math.max(bottom, actionSlot.y + actionSlot.height);
        return height - bottom;
    }

    // How far below its top edge the row's highest drawn part starts, read
    // as drawnBelow reads.
    function drawnAbove(byFont) {
        let top = labelColumn && label !== "" ? labelText.y + (byFont ? fontAbove(labelText) : labelText.inkAbove()) : height;
        for (const child of slot.children) {
            if (child.visible) top = Math.min(top, slot.y + child.y + (byFont && child instanceof Label ? fontAbove(child) : Theme.inkAbove(child)));
        }
        return Math.min(top, height);
    }

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
        T.Control {
            id: labelFocus
            Accessible.name: labelText.text
            Accessible.role: Accessible.StaticText
            anchors.fill: parent
            activeFocusOnTab: root.tipText !== "" && visible
            Tooltip {
                text: root.tipText
                side: root.explainBeside ? "right" : "belowStart"
                // The side's gap from this box's end puts the tooltip at `besideX`.
                box: root.explainBeside ? Qt.rect(0, -labelText.y, root.besideX - Theme.tooltip.gap, root.labelBox) : Qt.rect(root.underX, -labelText.y, root.width - root.underX, root.underText - Theme.tooltip.gap)
                maxWidth: root.explainBeside ? root.besideWrap : root.width - root.underX - 2 * Theme.tooltip.paddingX
                minWidth: root.explainBeside ? 0 : root.width - root.underX
            }
        }
        FocusRing { id: labelRing; target: labelFocus; outside: true }
        role: "label"
        text: root.label
        visible: root.labelColumn
        width: Theme.field.labelWidth - (infoButton.active ? infoButton.width + Theme.space.xs : 0)
        wrapMode: Text.Wrap
        y: lineCount > 1 ? Math.round((root.boxHeight - implicitHeight) / 2) : topForCapCenter(root.labelBox)
    }

    Loader {
        id: infoButton
        active: root.dialogText !== "" && root.labelColumn
        x: Theme.field.labelWidth - width
        y: labelText.lineCount > 2 ? labelText.y + labelText.topForLeadingIcon(implicitHeight) : Math.round((root.labelBox - implicitHeight) / 2)
        sourceComponent: InfoButton {
            title: root.label
            info: root.dialogText
            // Under the button a tooltip would cover the next row's label.
            tooltip: ""
            onInfoPageActivated: (page, tab) => root.infoPageActivated(page, tab)
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
        role: root.warningRole
        text: root.warning
        link: root.warningLink
        color: root.toneColor(root.warningTone)
        visible: root.warning !== ""
        x: slot.x
        y: root.boxHeight + Theme.field.gap
        width: root.valueRoom - root.actionRoom
        wrapMode: Text.Wrap
        onActivated: root.warningLinkActivated()
        onPageActivated: (page, tab) => root.warningPageActivated(page, tab)
    }

    Item {
        id: actionSlot
        visible: message.visible
        x: root.actionBelow ? slot.x : root.width - width
        y: root.actionBelow ? root.messageBottom - height : root.messageBottom - root.messageLine + Math.round((root.messageLine - height) / 2)
        width: root.actionItem === null ? 0 : root.actionItem.width
        height: root.actionItem === null ? 0 : root.actionItem.height
    }

    // The explainer's text at the width it wraps to past the control.
    Label {
        id: besideMeasure
        visible: false
        role: "tooltip"
        text: root.labelTooltip
        width: Math.max(1, root.besideWrap)
        wrapMode: Text.Wrap
    }

    // One line of the message's role, for its font's lines (fontBelow).
    Label {
        id: messageProbe
        visible: false
        role: message.role
    }
}
