import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import qs.Commons
import qs.Ui
import "../foundation/KeyNavLogic.js" as KeyNavLogic

// A push button. `variant` names a group of `Theme.button.variant`:
// `primary`, `secondary`, `tertiary`, `ghost` or `danger`; `size` names a
// control height of `Theme.size.control` and a group of
// `Theme.button.size`, which holds that size's padding, gap and icon. An
// unknown name is logged and drawn as the default. `iconName` draws a
// Lucide icon before the text. The label is placed by capital height and
// sized to its optical width, so its ink sits on the button's centre. A
// button set wider than its content draws the content from its side
// padding, as a column's header does, or on its centre with
// `centerContent`. The template supplies press, hover, focus,
// Space and Enter activation and the checked state; a checkable button draws
// `Theme.button.checked` while checked, with its own hover and press. The
// fill animates between states on `motion.duration.fast`. Under a rounded
// theme the side padding grows until the content clears the drawn corner
// (Theme.controlPadding). A set `disabledReason` disables the button: it
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
    width: Math.max(minimumWidth, Math.min(maximumWidth, implicitWidth))
    InputWidth { target: root }

    property string variant: "primary"
    property string size: "md"
    property string iconName: ""
    property bool focusPreview: false
    property string disabledReason: ""
    readonly property DisabledReason lock: lockState
    readonly property var tokens: variantOf(variant)
    readonly property var sizeTokens: Theme.button.size[size] !== undefined ? Theme.button.size[size] : Theme.button.size.md
    property int controlHeight: sizeOf(size)
    property real paddingX: sizeTokens.paddingX
    property real radius: Theme.button.radius
    property color restFill: tokens.background
    property color hoverFill: tokens.hover
    property color pressedFill: tokens.pressed
    property color borderColor: tokens.border
    property color textColor: tokens.foreground
    property color ringColor: Theme.focusRing.color
    property bool centerContent: false
    // The padding each side of the content at the button's own width.
    readonly property real sidePadding: Theme.controlPadding(paddingX, radius, controlHeight, implicitContentHeight)
    readonly property color fill: checked ? (down ? Theme.button.checked.pressed : hovered ? Theme.button.checked.hover : Theme.button.checked.background) : down ? pressedFill : hovered ? hoverFill : restFill
    readonly property color foreground: checked ? Theme.button.checked.foreground : textColor

    function variantOf(name) {
        const found = Theme.button.variant[name];
        if (found !== undefined) return found;
        console.error("Button: no variant named " + JSON.stringify(name));
        return Theme.button.variant.primary;
    }

    function sizeOf(name) {
        const found = Theme.size.control[name];
        if (found !== undefined) return found;
        console.error("Button: no size named " + JSON.stringify(name));
        return Theme.size.control.md;
    }

    implicitWidth: implicitContentWidth + 2 * sidePadding + leftInset + rightInset
    implicitHeight: Math.max(controlHeight, implicitContentHeight + topPadding + bottomPadding)
    // With `centerContent`, a button set wider than its content, one of a
    // pair of equal width, shares the spare width of its fill between the
    // content's two sides, on a whole pixel. The fill is the button less
    // its background insets, which a toggle's unlock mark takes. The
    // implicit width reads `sidePadding` alone, so a button sized by its
    // content does not size itself by its own width.
    leftPadding: leftInset + (centerContent && width > implicitWidth ? Math.floor((width - leftInset - rightInset - implicitContentWidth) / 2) : sidePadding)
    rightPadding: leftPadding - leftInset + rightInset
    spacing: sizeTokens.gap
    hoverEnabled: !lockState.locked
    PointerCursor { enabled: !lockState.locked }
    opacity: enabled ? 1 : Theme.opacity.disabled
    Accessible.name: text
    Keys.onReturnPressed: KeyNavLogic.activate(root)
    Keys.onEnterPressed: KeyNavLogic.activate(root)
    Keys.onPressed: event => { event.accepted = lockState.takeKey(event); }

    contentItem: Row {
        spacing: root.spacing
        opacity: lockState.fade
        Icon {
            visible: root.iconName !== ""
            name: root.iconName
            size: root.sizeTokens.icon
            color: root.foreground
            anchors.verticalCenter: parent.verticalCenter
        }
        Label {
            role: "button"
            text: root.text
            color: root.foreground
            font.weight: root.tokens.weight
            font.variableAxes: ({ wght: root.tokens.weight })
            width: opticalWidth
            y: topForCapCenter(parent.height)
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
