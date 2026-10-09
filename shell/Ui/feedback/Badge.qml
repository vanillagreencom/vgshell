import QtQuick
import qs.Commons
import qs.Ui

// A status chip, for a state tag or for a state the user must act on now
// with its action beside it; a light message in a form is FormRow's
// `warning` line. `size` is `sm`, the default, or `md`. The label is
// placed by capital height with its baseline on a whole device pixel,
// since a whole pixel spans two device pixels on a 2x screen and leaves
// the capitals off the chip's centre. The width uses the label's optical
// width with equal side padding. `tone` names a group of
// `Theme.badge.tone`: `neutral`, `accent`, `success`, `warning`, `danger`
// or `info`; an unknown tone is logged and drawn neutral. `iconName`
// draws a Lucide icon before the text. `verbatim` keeps the text as
// written, for a name whose case matters such as a package's: it is drawn
// in the `kbd` role, mono at the `label` role's size without its capitals,
// so the chip keeps the same height and centre. Under a rounded theme the
// side padding grows until the content clears the drawn corner.
Rectangle {
    id: root

    property string text: ""
    property string iconName: ""
    property string size: "sm"
    property string tone: "neutral"
    property bool verbatim: false
    readonly property var tokens: toneOf(tone)
    readonly property var sizeTokens: sizeOf(size)
    readonly property real sidePadding: Theme.controlPadding(sizeTokens.paddingX, Theme.badge.radius, sizeTokens.height, Math.max(icon.visible ? icon.height : 0, label.lineBox))

    function toneOf(name) {
        const found = Theme.badge.tone[name];
        if (found !== undefined) return found;
        console.error("Badge: no tone named " + JSON.stringify(name));
        return Theme.badge.tone.neutral;
    }

    function sizeOf(name) {
        const found = Theme.badge.size[name];
        if (found !== undefined) return found;
        console.error("Badge: no size named " + JSON.stringify(name));
        return Theme.badge.size.sm;
    }

    implicitWidth: 2 * sidePadding + label.opticalWidth + (icon.visible ? icon.width + Theme.badge.gap : 0)
    implicitHeight: sizeTokens.height
    radius: Theme.badge.radius
    color: tokens.background

    Icon {
        id: icon
        visible: root.iconName !== ""
        name: root.iconName
        size: Theme.icon.size.xs
        color: root.tokens.foreground
        x: root.sidePadding
        y: Math.round(root.height / 2 - height / 2)
    }

    Label {
        id: label
        role: root.verbatim ? "kbd" : "label"
        pixelRatio: Screen.devicePixelRatio
        text: root.text
        color: root.tokens.foreground
        x: root.sidePadding + (icon.visible ? icon.width + Theme.badge.gap : 0)
        y: topForCapCenter(root.height)
    }
}
