import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui
import "../foundation/KeyNavLogic.js" as KeyNavLogic

// The action of one key/value row, such as a setup step beside its chip:
// its text in the body role, sentence case, drawn as a link with no
// fill, no box and no side padding, so the text starts on the
// control's own edge and a row puts it on its value column. `tone` names a
// group of `Theme.rowAction.tone`, `accent` or `danger`; an unknown name is
// logged and drawn as `accent`. The text carries an underline at rest, so
// it reads as an action and not a title, at least `rowAction.underlineGap`
// and the label's `underlineOffset` under its baseline, so one clear row
// stands under its descenders; on hover the text takes the tone's hover
// colour and the underline grows from `rowAction.underline` to
// `rowAction.underlineHover`, and pressed it takes the tone's pressed
// colour. A disabled action fades once on the whole control. The focus
// ring draws outside the text, since
// a ring on its edge would run through the glyphs. The template supplies
// press, hover, focus and Space activation; Return and Enter activate it
// as they do a Button. Given less width than its text, the text elides.
// A set `disabledReason` disables the action: it stays a Tab stop, takes
// no click or key, draws its text, mark and underline faded with no hover
// or press, and shows the reason on hover and keyboard focus
// (DisabledReason).
// A danger action leads with its mark `rowAction.icon` wide,
// `rowAction.iconGap` before its text, so it reads apart from an accent
// action beside it by more than colour: the trash mark, or, for one that
// removes no item, the Lucide mark `markName` names, such as `log-out` for
// a sign-out; an accent action draws no mark, whatever `markName` holds. The
// mark sits on the control's edge, centred where the text's leading icon
// centres (Label.topForLeadingIcon).
// `removesItem` is for an action that removes the one item its row
// shows, where the row names what goes: it draws the trash mark alone, in
// the danger colour whatever `tone` holds, with no underline. Its mark
// keeps the control's edge, as a leading mark does, so it stands on the
// value column the other actions share, and the control is a square as
// tall as the text's box, so its hit target is no smaller than a text
// action's. The focus ring draws around the mark's column, as tall as that
// box, so it stands as clear of the mark on its right as on its left; a
// ring on the square would leave its right part empty. The hit target
// cannot be a `containmentMask` centred on the mark: on Qt 6.11.2 a press,
// click or hover inside a mask but outside the item's bounds reaches
// nothing (a qml-unit probe, 2026-10-17).
// `glyphEnd` is, as IconButton's is, the distance from the control's right
// edge to the lone mark's painted ink: a row that puts the ink, not the
// square, on its control edge shifts the action by it. An action with
// text reports 0.
// Its text stays its accessible name and shows in the shared tooltip on
// hover and keyboard focus, as an IconButton's label does, and a set
// `disabledReason` shows in the tooltip's place.
// The control's box is centred on the text's capital centre, so a row that
// centres it beside a chip sets the text level with the chip's; the box
// holds the thicker hover underline, so a hover moves nothing.
// `inkAbove()` is where its text's ink, or the danger mark, starts below
// that box's top, and `inkBelow()` how far above the box's bottom the
// resting underline ends, or the mark where it ends lower or draws alone,
// so a heading
// under the action stands `stack.heading` under what it draws at rest.
T.Button {
    id: root

    property string tone: "accent"
    property bool focusPreview: false
    property string disabledReason: ""
    // The Lucide name of a danger action's mark, "" for the trash mark. It
    // is not `icon`: AbstractButton's is FINAL, and a RowAction declaring
    // one fails to load (a qml-unit run, 2026-10-17).
    property string markName: ""
    property bool removesItem: false
    readonly property DisabledReason lock: lockState
    readonly property var tokens: toneOf(removesItem ? "danger" : tone)
    readonly property color foreground: down ? tokens.pressed : hovered ? tokens.hover : tokens.foreground
    // Whether the danger mark draws: before the text, or alone.
    readonly property bool marked: removesItem || tone === "danger"
    readonly property real glyphEnd: removesItem ? width - contentItem.x - mark.x - mark.painted[2] : 0

    function toneOf(name) {
        const found = Theme.rowAction.tone[name];
        if (found !== undefined) return found;
        console.error("RowAction: no tone named " + JSON.stringify(name));
        return Theme.rowAction.tone.accent;
    }

    function inkAbove() {
        const text = label.y + label.inkAbove();
        const top = !mark.visible ? text : label.visible ? Math.min(mark.y, text) : mark.y;
        return contentItem.y + top;
    }

    function inkBelow() {
        const foot = underline.y + Theme.rowAction.underline;
        const markFoot = mark.y + mark.height - Theme.inkBelow(mark);
        const lowest = !mark.visible ? foot : underline.visible ? Math.max(markFoot, foot) : markFoot;
        return height - contentItem.y - lowest;
    }

    implicitWidth: implicitContentWidth
    implicitHeight: implicitContentHeight
    padding: 0
    hoverEnabled: !lockState.locked
    PointerCursor { enabled: !lockState.locked }
    opacity: enabled ? 1 : Theme.opacity.disabled
    Accessible.name: text
    Keys.onReturnPressed: KeyNavLogic.activate(root)
    Keys.onEnterPressed: KeyNavLogic.activate(root)
    Keys.onPressed: event => { event.accepted = lockState.takeKey(event); }

    contentItem: Item {
        // How far under the baseline the underline starts.
        readonly property real drop: Math.max(Theme.rowAction.underlineGap, label.underlineOffset)
        // Half the box: from the capital centre up to the label's top, or
        // down to the hover underline's foot, whichever is further.
        readonly property real half: Math.max(label.capCentre, label.baselineOffset + drop + Theme.rowAction.underlineHover - label.capCentre)
        // Alone, the mark takes a square as tall as the text's box.
        implicitWidth: root.removesItem ? implicitHeight : label.x + label.implicitWidth
        implicitHeight: 2 * half
        opacity: lockState.fade

        Icon {
            id: mark
            visible: root.marked
            name: root.removesItem || root.markName === "" ? "trash" : root.markName
            size: Theme.rowAction.icon
            color: root.foreground
            // Alone, it centres where it would lead the text, so it stands
            // level with the danger marks of the rows beside it; the label
            // stays laid out, unseen, to give that centre.
            y: label.y + label.topForLeadingIcon(height, label.y)
        }
        Label {
            id: label
            visible: !root.removesItem
            x: root.marked ? mark.width + Theme.rowAction.iconGap : 0
            y: parent.half - capCentre
            role: "body"
            text: root.text
            color: root.foreground
            width: Math.min(implicitWidth, root.availableWidth - x)
            elide: Text.ElideRight
        }
        Rectangle {
            id: underline
            visible: label.visible
            x: label.x
            y: label.y + label.baselineOffset + parent.drop
            width: label.width
            height: root.hovered ? Theme.rowAction.underlineHover : Theme.rowAction.underline
            color: root.foreground
        }
    }

    background: Item {
        Item {
            x: root.removesItem ? root.contentItem.x + mark.x : 0
            width: root.removesItem ? mark.width : parent.width
            height: parent.height
            FocusRing { target: root; outside: true }
        }
    }

    DisabledReason { id: lockState; control: root }

    // The shared tooltip, wired as IconButton's is, built only for a mark
    // drawn alone, since every other action shows its text.
    Loader {
        active: root.removesItem
        sourceComponent: Tooltip {
            objectName: "removesItemTip"
            anchorItem: root
            text: lockState.locked ? "" : root.text
        }
    }
}
