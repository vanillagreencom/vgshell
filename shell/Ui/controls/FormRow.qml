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
// column, `field.gap` below its control's drawn ink, the measure key/value
// rows stand by (Theme.inkBelow, a Label in the slot by its font), and
// wrapped to the column, in the colour `warningTone` names, `warning`,
// `danger` or `muted`. `warningLink`, when set, names the substring of
// `warning` that opens a cited file through `warningLinkActivated`. A page
// reference in `warning` (LinkText) is its link, activated through
// `warningPageActivated`, and one in the `info` dialog's text through
// `infoPageActivated`, each with the page and tab. The
// row ends with the lower of its box and its message. The label and the
// control stay centred on the row box, so a message takes no room from its
// control, and the message's box may overlap the row box where the control
// draws less than its box. Light feedback in a form is this line, plain
// sentence-case text in a muted or status colour. A chip, a fill or
// capitals are for a state the user must act on now, with the action beside
// it. `action` is one
// control for the message, such as a RowAction that undoes what the message
// names: it draws on the message's line, on the row's end edge, only while
// the row has a message, and the message wraps `stack.inline` before it.
// It centres on the message and keeps the message's height: an action
// taller than the message overhangs it and does not count in `inkBelow()`,
// so showing or hiding it moves no row and no heading below.
// Where that would leave the message less than `field.labelWidth`, as in a
// narrow flyout, the action goes on a line of its own, `field.gap` under
// the message, from the value column's start. While the row has a message
// it takes room under it, so the next item of its column that is no
// key/value row starts `stack.group` below the message
// (Theme.subTextRoom); a key/value row stands by ink.
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
// role keep one pitch whatever they read.
// A row with a label beside its control is a key/value row
// (`keyValueRow`), and one under another key/value row of its column
// (`rowAbove`) stands `stack.page` under that row's drawn ink, from its
// lowest drawn part (`lineBelow()`) to this row's highest (`lineAbove()`),
// whatever either control draws in its row box: `inkTop` is that space
// less the room the columns already put there, negative where that room
// exceeds it. The row is the one place that measures it, for a bare row
// and for a Field, so both stand by one rule: every key/value row is a
// FormRow, while a Field has no message, tone or action to build a bare
// row's on. `placed` is the item its
// column places: the row itself, which then takes `inkTop` above its row
// box (`shift`) and draws its label, control and message that far down,
// or a Field that holds it, which takes `inkTop` as its top padding. The
// row box stays `row.height` either way, and a row under anything that is
// no key/value row, such as a section's heading, keeps that item's
// spacing.
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
    property Item placed: root
    default property alias control: slot.data
    readonly property bool keyValueRow: labelColumn
    // The key/value row the placed item stands under, and the room the
    // columns already put between the two: the spacing of the column that
    // holds both and the top padding of each column the placed item is the
    // first shown item of. The first group of a GroupList stands at the
    // list's top, so the search goes on above the list; a later group keeps
    // the list's gap and hairline. null for a row with no label beside its
    // control, under anything that is no key/value row, or under nothing. A
    // Column lays out only its shown, sized children
    // (https://doc.qt.io/qt-6/qml-qtquick-column.html). A Repeater that
    // moves its rows reorders its parent's children with no change of
    // `children`, so the search reads the place in its column of each item
    // it climbs from and of the item it stops at (`Positioner.index`),
    // which the Column sets as it lays the moved rows out. Of another bare
    // row it reads only values that row's own bindings compute (`rowShown`,
    // `belowLine`): Qt 6.11.2 keeps a binding's trigger on an item's height
    // or place it read before, so a row that read another row's geometry
    // and then moved above it would run again inside that row's change
    // and log a binding loop. A Field takes its space as top padding, which
    // moves none of the parts its lineBelow() reads, so it is read as is.
    readonly property var rowAbove: {
        if (!labelColumn || label === "") return null;
        let room = 0;
        for (let at = placed; at.parent !== null; ) {
            void at.Positioner.index;
            const holder = at.parent;
            const list = holder.parent instanceof GroupList ? holder.parent : null;
            if (!(holder instanceof Column) && list === null) return null;
            const siblings = holder.children;
            let below = true;
            for (let i = siblings.length - 1; i >= 0; i--) {
                const item = siblings[i];
                if (item === at) below = false;
                else if (!below && (item.rowShown ?? (item.visible && item.width > 0 && item.height > 0))) {
                    void item.Positioner.index;
                    return list === null && item.keyValueRow === true ? { item: item, room: room + holder.spacing } : null;
                }
            }
            if (list === null) room += holder.topPadding;
            at = list === null ? holder : list;
        }
        return null;
    }
    // The row above must still read as shown when this reads it. QML
    // marks an item and its QObject children deleted as it starts to destroy
    // them, before the item leaves its parent
    // (QQmlPrivate::qdeclarativeelement_destructor, Qt 6.11 qqmlengine.cpp).
    // The mark emits no change, so rowAbove still names the item, and a
    // marked item reads every property as undefined, `visible` and
    // `children` included (QObjectWrapper::getQmlProperty), while
    // `instanceof` still holds: run under scripts/qml-unit.sh on Qt 6.11.2
    // by tst_field_row_above_teardown.qml. Ink is drawn in whole pixel rows
    // on whole-pixel item edges, as Section measures it, so this counts
    // whole rows. It reads the row box's own top, not `lineAbove()`, which
    // counts `shift`.
    readonly property real inkTop: rowAbove === null || !rowAbove.item.visible ? 0 : Theme.stack.page - rowAbove.room - Math.floor(lineBelowOf(rowAbove.item)) - Math.floor(drawnAbove(true))
    // Whether the row's column lays it out, and lineBelow(), as values a
    // row under it reads.
    readonly property bool rowShown: visible && width > 0 && height > 0
    readonly property real belowLine: lineBelow()
    // The part of `inkTop` the row takes above its row box: all of it for a
    // row its column places, none for one a Field places.
    readonly property real shift: placed === root ? inkTop : 0
    property alias action: actionSlot.data
    readonly property Item actionItem: actionSlot.visibleChildren.length > 0 ? actionSlot.visibleChildren[0] : null
    readonly property bool actionBelow: actionItem !== null && valueRoom - actionItem.width - Theme.stack.inline < Theme.field.labelWidth
    readonly property real actionRoom: actionItem === null || actionBelow ? 0 : actionItem.width + Theme.stack.inline
    readonly property real messageLine: actionBelow ? message.height + Theme.field.gap + actionItem.height : message.height
    readonly property real valueX: labelColumn ? Theme.field.labelWidth + Theme.field.labelGap : 0
    readonly property real valueRoom: Math.max(0, width - valueX)
    readonly property real valueBottom: shift + slotTop + slot.height
    // Where the control's drawn ink ends in the slot, read as lineBelow()
    // reads the slot: a Label by its font, any other control as drawn. An
    // empty slot ends at its box. Ink is drawn in whole pixel rows, so a
    // part of a row counts as the whole row.
    readonly property real controlInk: {
        let bottom = -Infinity;
        for (const child of slot.children) {
            if (child.visible) bottom = Math.max(bottom, child.y + child.height - (child instanceof Label ? fontBelow(child) : Theme.inkBelow(child)));
        }
        return bottom === -Infinity ? slot.height : Math.ceil(bottom);
    }
    // Where the control's ink ends, and the message starts, in the row box.
    readonly property real controlBottom: slotTop + controlInk
    readonly property real messageTop: controlBottom + Theme.field.gap
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
    // In the row box's frame, as are the label's and the control's tops
    // and the places that read them.
    readonly property real underText: textBelow ? slotTop + slot.height + Theme.field.gap : warning !== "" ? messageTop : -1
    // Whether the explainer, centred on the label's box, ends above that line.
    readonly property bool besideClear: underText < 0 ? true : (labelBox + besideHeight) / 2 <= underText
    readonly property bool explainBeside: besideWrap > 0 && besideHeight <= labelBox + 2 * Theme.stack.row && besideClear
    // Where the label's focus ring ends: it draws outside the label's box.
    readonly property real ringBottom: labelTop + labelText.height + labelRing.extent
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
    // the control's rounded centre can take. Centred on the slot, it ends
    // above that line while half its height fits between the slot's centre
    // and the line's start, `field.gap` under the slot's box for the
    // owner's text and under the control's ink for the message.
    readonly property bool besideRoom: besideWrap > 0 && besideHeight <= oneLineBox + 2 * Theme.stack.row && (!underLine || besideHeight <= 2 * ((textBelow ? slot.height : controlInk) + Theme.field.gap) - slot.childrenRect.height - 1)
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
    // The row box, the end of the message's line and the room under the
    // lower of the two, each from the row box's top, so the space above it
    // reads none of them.
    readonly property real boxHeight: labelColumn ? Math.max(Theme.row.height, labelText.implicitHeight, slot.childrenRect.height) : slot.childrenRect.height
    readonly property real messageBottom: warning === "" ? boxHeight : messageTop + messageLine
    readonly property real ownHeight: Math.max(boxHeight, messageBottom) + subTextRoom
    // Where the label and the control start in the row box.
    readonly property real labelTop: labelText.lineCount > 1 ? Math.round((boxHeight - labelText.implicitHeight) / 2) : labelText.topForCapCenter(labelBox)
    readonly property real slotTop: labelColumn ? Math.round((boxHeight - slot.height) / 2) : 0
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

    // Whether ITEM is the row's control or inside it, not its label, its
    // message or its action.
    function holdsControl(item) {
        for (let at = item; at !== null && at !== root; at = at.parent) {
            if (at === slot) return true;
        }
        return false;
    }

    function inkBelow() { return drawnBelow(false); }
    function inkAbove() { return shift + drawnAbove(false); }
    function lineBelow() { return drawnBelow(true); }
    function lineAbove() { return shift + drawnAbove(true); }

    // How far above ITEM's bottom edge the row it ends with stops, read by
    // lineBelow() as Theme.inkBelow reads ink: a row or a field by its own,
    // a Column by its last shown child above its bottom padding, a
    // GroupList by its last shown group, a Loader by its item, and anything
    // else as drawn.
    function lineBelowOf(item) {
        if (typeof item.belowLine === "number") return item.belowLine;
        if (typeof item.lineBelow === "function") return item.lineBelow();
        if (item instanceof Loader) return item.item instanceof Item ? item.height - item.item.height + lineBelowOf(item.item) : 0;
        const list = item instanceof GroupList;
        if (!list && !(item instanceof Column)) return Theme.inkBelow(item);
        const shown = (list ? Array.from(item.groups) : Array.from(item.children)).filter(child => child instanceof Item && child.visible && child.width > 0 && child.height > 0);
        if (shown.length === 0) return Theme.inkBelow(item);
        const last = shown[shown.length - 1];
        return (list ? item.height - last.y - last.height : item.bottomPadding) + lineBelowOf(last);
    }

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

    // How far below the row box's top the row's highest drawn part starts,
    // read as drawnBelow reads.
    function drawnAbove(byFont) {
        let top = labelColumn && label !== "" ? labelTop + (byFont ? fontAbove(labelText) : labelText.inkAbove()) : ownHeight;
        for (const child of slot.children) {
            if (child.visible) top = Math.min(top, slotTop + child.y + (byFont && child instanceof Label ? fontAbove(child) : Theme.inkAbove(child)));
        }
        return Math.min(top, ownHeight);
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
    implicitHeight: shift + ownHeight

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
                box: root.explainBeside ? Qt.rect(0, -root.labelTop, root.besideX - Theme.tooltip.gap, root.labelBox) : Qt.rect(root.underX, -root.labelTop, root.width - root.underX, root.underText - Theme.tooltip.gap)
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
        y: root.shift + root.labelTop
    }

    Loader {
        id: infoButton
        active: root.dialogText !== "" && root.labelColumn
        x: Theme.field.labelWidth - width
        y: labelText.lineCount > 2 ? labelText.y + labelText.topForLeadingIcon(implicitHeight) : Math.round((root.labelBox - implicitHeight) / 2) + root.shift
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
        y: root.shift + root.slotTop
    }

    LinkText {
        id: message
        role: root.warningRole
        text: root.warning
        link: root.warningLink
        color: root.toneColor(root.warningTone)
        visible: root.warning !== ""
        x: slot.x
        y: root.shift + root.messageTop
        width: root.valueRoom - root.actionRoom
        wrapMode: Text.Wrap
        onActivated: root.warningLinkActivated()
        onPageActivated: (page, tab) => root.warningPageActivated(page, tab)
    }

    Item {
        id: actionSlot
        visible: message.visible
        x: root.actionBelow ? slot.x : root.width - width
        y: root.shift + (root.actionBelow ? root.messageBottom - height : root.messageBottom - root.messageLine + Math.round((root.messageLine - height) / 2))
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
