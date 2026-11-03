import QtQuick
import QtQuick.Effects
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
// sized to its optical width, so its ink sits on the button's centre. The
// template supplies press, hover, focus,
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
// A surface that owns its look (D118) hands the button its own form, each
// value the variant's or the size's shared token by default:
// `controlHeight`, `paddingX` and `radius`; `restFill`, `hoverFill` and
// `pressedFill`; `borderColor`; the label's `textColor` at rest and its
// `hoverTextColor` under the pointer or pressed; and the focus ring's
// `ringColor`. `shimmer`, the look's `{ sweep, pause, band, easing }`,
// sweeps a soft band of `textColor` across the label, which rests in
// `hoverTextColor`, for as long as the pointer rests on the button: one
// sweep of `sweep` and a `pause`, again and again, a `band` of the label's
// width a side. The sweep stops the moment the pointer leaves, and the
// button draws no further frame of it. The look's durations scale with
// motion, so at motion scale 0 no sweep runs and no band draws. Keyboard
// focus draws the ring and no shimmer. `shadow`, the look's
// `{ color, opacity, blur }`, draws a shadow with no offset under the
// content, the shimmer included, as the surface's other text draws it.
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
    property color hoverTextColor: textColor
    property color ringColor: Theme.focusRing.color
    property var shimmer: null
    property var shadow: null
    // A band crosses the label only while a sweep runs, under the pointer.
    // The sweep lives
    // in the content, which a button built on this one may replace.
    readonly property bool shimmering: contentItem !== null && contentItem.shimmering === true
    readonly property color fill: checked ? (down ? Theme.button.checked.pressed : hovered ? Theme.button.checked.hover : Theme.button.checked.background) : down ? pressedFill : hovered ? hoverFill : restFill
    readonly property color foreground: checked ? Theme.button.checked.foreground : hovered || down ? hoverTextColor : textColor

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

    implicitWidth: implicitContentWidth + leftPadding + rightPadding
    implicitHeight: Math.max(controlHeight, implicitContentHeight + topPadding + bottomPadding)
    leftPadding: Theme.controlPadding(paddingX, radius, controlHeight, implicitContentHeight)
    rightPadding: leftPadding
    spacing: sizeTokens.gap
    hoverEnabled: !lockState.locked
    PointerCursor { enabled: !lockState.locked }
    opacity: enabled ? 1 : Theme.opacity.disabled
    Accessible.name: text
    Keys.onReturnPressed: KeyNavLogic.activate(root)
    Keys.onEnterPressed: KeyNavLogic.activate(root)
    Keys.onPressed: event => { event.accepted = lockState.takeKey(event); }

    contentItem: Row {
        readonly property bool shimmering: sweep.running
        spacing: root.spacing
        opacity: lockState.fade
        // The shadow blurs the content's layer, which Qt draws again only
        // when the content changes: a still label redraws no blur
        // (tst_jarvis_prompt.qml). shadowBlur 1 is the full blur blurMax
        // allows (doc.qt.io/qt-6/qml-qtquick-effects-multieffect.html).
        layer.enabled: root.shadow !== null
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: root.shadow === null ? "transparent" : root.shadow.color
            shadowOpacity: root.shadow === null ? 0 : root.shadow.opacity
            blurMax: root.shadow === null ? 0 : root.shadow.blur
            shadowBlur: 1
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
        }
        // Each pass carries the band from wholly before the label to wholly
        // past it, then pauses, until the pointer leaves: hover is the
        // user's input, so it may draw frames while it lasts. At motion scale 0 the
        // look's durations are 0, and Qt ends an animation of no duration
        // as it starts, never reporting it running (tst_jarvis_prompt.qml,
        // Qt 6.12.0), so no band draws.
        SequentialAnimation {
            id: sweep
            running: root.shimmer !== null && root.hovered
            loops: Animation.Infinite
            NumberAnimation {
                target: band
                property: "x"
                from: -band.width
                to: bandMask.width
                duration: root.shimmer === null ? 0 : root.shimmer.sweep
                easing.type: root.shimmer === null ? Easing.Linear : root.shimmer.easing
            }
            PauseAnimation { duration: root.shimmer === null ? 0 : root.shimmer.pause }
        }
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

            // The shimmer: the label again in `textColor`, drawn through a
            // mask whose alpha is the band. Qt's Item layer effect takes a
            // texture-backed mask's alpha, and a threshold of 0.5 with a
            // spread of 1 passes the band's ramp through softly
            // (doc.qt.io/qt-6/qml-qtquick-effects-multieffect.html), as
            // ScrollArea's fade does. The band moves in an item that stays
            // visible while the sweep runs, hidden from drawing by the
            // texture's `hideSource`: a move inside an invisible item
            // schedules no frame, so a hidden layer's band stood still
            // (tst_button.qml, Qt 6.12.0). No layer or texture exists while
            // no sweep runs, so a still button draws the plain label alone.
            Label {
                width: parent.width
                visible: sweep.running
                role: "button"
                text: root.text
                color: root.textColor
                font.weight: root.tokens.weight
                font.variableAxes: ({ wght: root.tokens.weight })
                layer.enabled: sweep.running
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: bandTexture
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }
            }
            Item {
                id: bandMask
                width: parent.width
                height: parent.height
                visible: bandTexture.live
                Rectangle {
                    id: band
                    width: root.shimmer === null ? 0 : 2 * root.shimmer.band * bandMask.width
                    height: bandMask.height
                    x: -width
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: root.maskColor(0) }
                        GradientStop { position: 0.5; color: root.maskColor(1) }
                        GradientStop { position: 1; color: root.maskColor(0) }
                    }
                }
            }
            ShaderEffectSource {
                id: bandTexture
                width: bandMask.width
                height: bandMask.height
                visible: false
                sourceItem: sweep.running ? bandMask : null
                hideSource: true
                live: sweep.running
            }
        }
    }

    function maskColor(alpha) {
        const color = Qt.color(textColor);
        color.a = alpha;
        return color;
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
