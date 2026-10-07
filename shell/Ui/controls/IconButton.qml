import QtQuick
import qs.Commons
import qs.Ui

// A square button with one icon and no text. `label` is what a screen
// reader says for it and, unless `tooltip` says more, what its tooltip
// says; a button without one is logged, since an icon alone names nothing. The ghost variant is the default, so a row
// of icon buttons draws no fills until one is hovered. A ghost button's
// icon rests in `color.textMuted` and takes the variant's foreground on
// hover, focus, press or checked; a filled variant's icon keeps its
// foreground, which its fill is chosen to carry. The rest colour is
// opaque, not a faded foreground: an icon's stroke overlaps itself at its
// joins, so an icon drawn translucent shows each overlap brighter. A
// disabled button fades once on the whole control. The icon is
// the size's own, `button.size.<size>.icon`, centred on whole pixels.
// `glyphStart` and `glyphEnd` are the distances from the box's edges to
// the glyph's painted ink: a header that puts a glyph, not a box, on its
// content edge shifts the button by them (D050).
Button {
    id: root

    property string label: ""
    property string tooltip: label
    readonly property real glyphStart: leftPadding + contentItem.painted[0]
    readonly property real glyphEnd: rightPadding + contentItem.size - contentItem.painted[2]

    variant: "ghost"
    leftPadding: Math.floor((controlHeight - sizeTokens.icon) / 2)
    rightPadding: leftPadding
    topPadding: leftPadding
    bottomPadding: leftPadding
    implicitWidth: controlHeight
    Accessible.name: label

    Component.onCompleted: if (label === "") console.error("IconButton: label is required, icon=" + JSON.stringify(iconName))

    contentItem: Icon {
        name: root.iconName
        size: root.sizeTokens.icon
        color: root.variant === "ghost" && root.enabled && !(root.hovered || root.visualFocus || root.down || root.checked) ? Theme.color.textMuted : root.foreground
        Behavior on color { ColorAnimation { duration: Theme.motion.duration.fast; easing.type: Theme.motion.easing.standard } }
    }

    Tooltip {
        text: root.tooltip
    }
}
