import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import qs.Commons
import qs.Ui
import "../foundation/KeyNavLogic.js" as KeyNavLogic

// A push button. `variant` names a group of `Theme.button.variant`:
// `primary`, `secondary`, `tertiary`, `ghost` or `danger`; `size` names a
// control height of `Theme.size.control` and a group of
// `Theme.button.size`, which holds that size's gap and icon. An
// unknown name is logged and drawn as the default. `iconName` draws a
// Lucide icon before the text. The label is placed by capital height and
// sized to its optical width. Each side stands `paddingX` from the border's
// inner edge to the content's first or last ink, icon or letter; by
// default that is the mean of the gaps the ink leaves inside the border
// above and below it at the button's height, so the four gaps match
// (Theme.inkAbove, Theme.inkBelow, Theme.inkStart, Theme.inkEnd). A
// button set wider than its content draws the content from its side
// padding, as a column's header does, or on its centre with
// `centerContent`. The template supplies press, hover, focus,
// Space and Enter activation and the checked state; a checkable button draws
// `Theme.button.checked` while checked, with its own hover and press. The
// fill animates between states on `motion.duration.fast`. Under a rounded
// theme both sides' gaps grow alike until the content clears the drawn
// corner (Theme.controlPadding). A set `disabledReason` disables the button: it
// stays a Tab stop, takes no click or key, draws its fill and content
// faded with no hover or press, and shows the reason on hover and
// keyboard focus. `lock` is that state (DisabledReason), which a button
// built on this one reads.
//
// A surface that owns its look (D119) hands the button its own form, each
// value the variant's or the size's shared token by default:
// `controlHeight`, `paddingX` and `radius`; `restFill`, `hoverFill` and
// `pressedFill`; `borderColor`; the label's `textColor`; the focus ring's
// `ringColor`; and `centerContent`.
T.Button {
    id: root

    readonly property real minimumWidth: Theme.control.minWidth
    readonly property real maximumWidth: Theme.control.maxWidth
    Layout.minimumWidth: minimumWidth
    Layout.maximumWidth: maximumWidth
    // The bounds hold a button sized by its content and one a layout
    // places. A caller that binds the width owns that allocation, as a
    // footer's main action fills its row; a form row bounds its own slot.
    width: Math.max(minimumWidth, Math.min(maximumWidth, implicitWidth))

    property string variant: "primary"
    property string size: "md"
    property string iconName: ""
    property bool focusPreview: false
    property string disabledReason: ""
    readonly property DisabledReason lock: lockState
    readonly property var tokens: variantOf(variant)
    readonly property var sizeTokens: Theme.button.size[size] !== undefined ? Theme.button.size[size] : Theme.button.size.md
    property int controlHeight: sizeOf(size)
    property real paddingX: inkGap
    property real radius: Theme.button.radius
    property color restFill: tokens.background
    property color hoverFill: tokens.hover
    property color pressedFill: tokens.pressed
    property color borderColor: tokens.border
    property color textColor: tokens.foreground
    property color ringColor: Theme.focusRing.color
    property bool centerContent: false
    // Whether this file's own content row is drawn, read by its id, with
    // its label complete. A button that draws its own content, as a
    // calendar day does, measures none and centres its content itself:
    // Theme.inkEnd answers such an item's allocated width, which these
    // paddings set. A read before the label's own font binding has run
    // measures the default family at the variant's weight and maps a
    // system fallback face (a run, Qt 6.11.2; scripts/smoke/rows/core-drift.sh).
    readonly property bool ownContent: content !== null && content.labelReady && content.parent === root
    // The mean of the gaps the content's ink leaves inside the border
    // above and below it.
    readonly property real inkGap: ownContent ? contentInkGap() : 0
    // How far right of the content's left edge its ink starts, and how far
    // its box runs past its ink's end: the leading icon's painted ink, as
    // TextField reads its leading icon, and the label's own ink box, since
    // the icon leads the row and the label ends it.
    readonly property real inkLead: !ownContent ? 0 : iconName !== "" ? leadIcon.painted[0] : Theme.inkStart(caption)
    readonly property real inkTrail: ownContent ? implicitContentWidth - caption.x - Theme.inkEnd(caption) : 0
    // The gap each side: `paddingX`, or more until both sides clear a
    // rounded corner, so the two stay equal.
    readonly property real sideGap: Math.max(paddingX, Theme.controlPadding(0, radius, controlHeight, implicitContentHeight) - Theme.button.border + Math.max(inkLead, inkTrail))
    // The padding before the content at the button's own width. The
    // padding after it puts the ink's end as far from the right edge as
    // its start stands from the left.
    readonly property real startPadding: Theme.button.border + sideGap - inkLead
    readonly property color fill: checked ? (down ? Theme.button.checked.pressed : hovered ? Theme.button.checked.hover : Theme.button.checked.background) : down ? pressedFill : hovered ? hoverFill : restFill
    readonly property color foreground: checked ? Theme.button.checked.foreground : textColor

    function variantOf(name) {
        const found = Theme.button.variant[name];
        if (found !== undefined) return found;
        console.error("Button: no variant named " + JSON.stringify(name));
        return Theme.button.variant.primary;
    }

    // The row spans the button's height and centres its icon and label
    // there; the gap is read at `controlHeight`, not at the drawn height:
    // side padding read from the drawn height loops the implicit width
    // under Dialog's action placement, which places a button from inside
    // its implicit width's change (a run, Qt 6.11.2).
    function contentInkGap() {
        const capTop = caption.topForCapCenter(controlHeight);
        const iconTop = (controlHeight - leadIcon.height) / 2;
        const top = Math.min(capTop + Theme.inkAbove(caption), iconName !== "" ? iconTop + leadIcon.painted[1] : Infinity);
        const bottom = Math.max(capTop + caption.height - Theme.inkBelow(caption), iconName !== "" ? iconTop + leadIcon.painted[3] : -Infinity);
        return (controlHeight - bottom + top) / 2 - Theme.button.border;
    }

    function sizeOf(name) {
        const found = Theme.size.control[name];
        if (found !== undefined) return found;
        console.error("Button: no size named " + JSON.stringify(name));
        return Theme.size.control.md;
    }

    implicitWidth: implicitContentWidth + 2 * startPadding + inkLead - inkTrail + leftInset + rightInset
    implicitHeight: Math.max(controlHeight, implicitContentHeight + topPadding + bottomPadding)
    // With `centerContent`, a button set wider than its content, one of a
    // pair of equal width, shares the spare width of its fill between the
    // content's two sides, on a whole pixel. The fill is the button less
    // its background insets, which a toggle's unlock mark takes. The
    // implicit width reads the side paddings alone, so a button sized by
    // its content does not size itself by its own width.
    leftPadding: leftInset + (centerContent && width > implicitWidth ? Math.floor((width - leftInset - rightInset - implicitContentWidth) / 2) : startPadding)
    rightPadding: leftPadding - leftInset + rightInset + inkLead - inkTrail
    spacing: sizeTokens.gap
    hoverEnabled: !lockState.locked
    PointerCursor { enabled: !lockState.locked }
    opacity: enabled ? 1 : Theme.opacity.disabled
    Accessible.name: text
    Keys.onReturnPressed: KeyNavLogic.activate(root)
    Keys.onEnterPressed: KeyNavLogic.activate(root)
    Keys.onPressed: event => { event.accepted = lockState.takeKey(event); }

    contentItem: Row {
        id: content
        // Set once the label's own bindings have run (ownContent).
        property bool labelReady: false

        spacing: root.spacing
        opacity: lockState.fade
        Icon {
            id: leadIcon
            visible: root.iconName !== ""
            name: root.iconName
            size: root.sizeTokens.icon
            color: root.foreground
            anchors.verticalCenter: parent.verticalCenter
        }
        Label {
            id: caption
            role: "button"
            text: root.text
            color: root.foreground
            font.weight: root.tokens.weight
            font.variableAxes: ({ wght: root.tokens.weight })
            width: opticalWidth
            y: topForCapCenter(parent.height)
            Component.onCompleted: content.labelReady = true
        }
    }

    background: Rectangle {
        implicitHeight: root.controlHeight
        radius: root.radius
        color: lockState.faded(root.fill)
        border.width: Theme.button.border
        border.color: lockState.faded(root.checked ? Theme.button.checked.border : root.borderColor)
        Behavior on color { ColorAnimation { duration: Theme.motion.duration.fast; easing.type: Theme.motion.easing.standard } }
        FocusRing { target: root; ringColor: root.ringColor }
    }

    DisabledReason { id: lockState; control: root }
}
