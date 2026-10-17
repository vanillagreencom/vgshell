import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui
import "../foundation/KeyNavLogic.js" as KeyNavLogic

// The action of one key/value row, such as a setup step beside its chip:
// its text in the body role, sentence case, drawn as a link with no icon,
// no fill, no box and no side padding, so the text starts on the
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
// A danger action leads with a trash mark `rowAction.icon` wide,
// `rowAction.iconGap` before its text, so it reads apart from an accent
// action beside it by more than colour; the mark then sits on the
// control's edge, centred where the text's leading icon centres
// (Label.topForLeadingIcon).
// The control's box is centred on the text's capital centre, so a row that
// centres it beside a chip sets the text level with the chip's; the box
// holds the thicker hover underline, so a hover moves nothing.
// `inkAbove()` is where its text's ink, or the danger mark, starts below
// that box's top, and `inkBelow()` how far above the box's bottom the
// resting underline ends, or the mark where it ends lower, so a heading
// under the action stands `stack.heading` under what it draws at rest.
T.Button {
    id: root

    property string tone: "accent"
    property bool focusPreview: false
    property string disabledReason: ""
    readonly property DisabledReason lock: lockState
    readonly property var tokens: toneOf(tone)
    readonly property color foreground: down ? tokens.pressed : hovered ? tokens.hover : tokens.foreground
    // Whether the danger mark leads the text.
    readonly property bool marked: tone === "danger"

    function toneOf(name) {
        const found = Theme.rowAction.tone[name];
        if (found !== undefined) return found;
        console.error("RowAction: no tone named " + JSON.stringify(name));
        return Theme.rowAction.tone.accent;
    }

    function inkAbove() {
        const text = label.y + label.inkAbove();
        return contentItem.y + (mark.visible ? Math.min(mark.y, text) : text);
    }

    function inkBelow() {
        const foot = underline.y + Theme.rowAction.underline;
        const lowest = mark.visible ? Math.max(mark.y + mark.height - Theme.inkBelow(mark), foot) : foot;
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
        implicitWidth: label.x + label.implicitWidth
        implicitHeight: 2 * half
        opacity: lockState.fade

        Icon {
            id: mark
            visible: root.marked
            name: "trash"
            size: Theme.rowAction.icon
            color: root.foreground
            y: label.y + label.topForLeadingIcon(height, label.y)
        }
        Label {
            id: label
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
            x: label.x
            y: label.y + label.baselineOffset + parent.drop
            width: label.width
            height: root.hovered ? Theme.rowAction.underlineHover : Theme.rowAction.underline
            color: root.foreground
        }
    }

    background: Item {
        FocusRing { target: root; outside: true }
    }

    DisabledReason { id: lockState; control: root }
}
