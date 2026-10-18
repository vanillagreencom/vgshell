import QtQuick
import qs.Commons
import qs.Ui

// A square button with one icon and no text. `label` is what a screen
// reader says for it and what its action tooltip says; a button without
// one is logged, since an icon alone names nothing. Hover, press and
// checked draw no fill and no border: they show on the glyph alone, and a
// filled variant keeps its own fill in every state. The ghost variant is
// the default. A ghost button's icon rests in `color.textMuted` and takes
// the variant's foreground on hover, focus or press; a checked button's
// icon is the accent, `button.checked.foreground`; a filled variant's icon
// keeps its foreground, which its fill is chosen to carry. A `tone` sets
// the icon in every state. Press dims the icon. The rest colour is
// opaque, not a faded foreground: an icon's stroke overlaps itself at its
// joins, so an icon drawn translucent shows each overlap brighter. A
// disabled button fades once on the whole control; one a `disabledReason`
// locks (Button) fades its fill and icon, and shows the reason in place
// of its action tooltip, so one tooltip shows. The icon is
// the size's own, `button.size.<size>.icon`, centred on whole pixels.
// `glyphStart` and `glyphEnd` are the distances from the box's edges to
// the glyph's painted ink: a header that puts a glyph, not a box, on its
// content edge shifts the button by them (docs/architecture/design-system.md § Layout).
Button {
    id: root

    property string label: ""
    property string tooltip: label
    // Where the tooltip opens: Tooltip's `side`.
    property string tooltipSide: "below"
    // A state tone names a Theme.color token, including in a plugin-owned look.
    property string tone: ""
    readonly property real glyphStart: leftPadding + contentItem.painted[0]
    readonly property real glyphEnd: rightPadding + contentItem.size - contentItem.painted[2]

    variant: "ghost"
    leftPadding: Math.floor((controlHeight - sizeTokens.icon) / 2)
    rightPadding: leftPadding
    topPadding: leftPadding
    bottomPadding: leftPadding
    implicitWidth: controlHeight
    Accessible.name: label

    background: Rectangle {
        implicitHeight: root.controlHeight
        radius: Theme.button.radius
        color: root.lock.faded(root.tokens.background)
        border.width: Theme.button.border
        border.color: root.lock.faded(root.tokens.border)
        FocusRing { target: root }
    }

    Component.onCompleted: if (label === "") console.error("IconButton: label is required, icon=" + JSON.stringify(iconName))

    contentItem: Icon {
        name: root.iconName
        size: root.sizeTokens.icon
        opacity: (root.down ? Theme.opacity.disabled : 1) * root.lock.fade
        color: root.tone !== "" ? Theme.color[root.tone] : root.variant === "ghost" && root.enabled && !(root.hovered || root.visualFocus || root.down || root.checked) ? Theme.color.textMuted : root.foreground
        Behavior on color { ColorAnimation { duration: Theme.motion.duration.fast; easing.type: Theme.motion.easing.standard } }
    }

    Tooltip {
        text: root.lock.locked ? "" : root.tooltip
        side: root.tooltipSide
    }
}
