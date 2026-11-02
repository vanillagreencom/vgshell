import QtQuick
import qs.Commons
import qs.Ui

// A status chip, for a state tag or for a state the user must act on now
// with its action beside it; a light message in a form is FormRow's
// `warning` line. `size` is `sm`, the default, or `md`. The label is
// placed by capital height. The width uses the label's optical
// width with equal side padding. `tone` names a group of
// `Theme.badge.tone`: `neutral`, `accent`, `success`, `warning`, `danger`
// or `info`; an unknown tone is logged and drawn neutral. `iconName`
// draws a Lucide icon before the text. `verbatim` keeps the text as
// written, for a name whose case matters such as a package's: it is drawn
// in the `kbd` role, mono at the `label` role's size without its capitals,
// so the chip keeps the same height and centre. Under a rounded theme the
// side padding grows until the content clears the drawn corner. Given a
// width under its implicit width, the chip keeps its side padding and
// elides the label at its end; at its implicit width the label is whole.
// `variant: "unread"` draws a circular accent count. Counts above 99 read
// 99+ in the next control size while the accessible name keeps the count.
Rectangle {
    id: root

    property string text: ""
    property string variant: "status"
    property string iconName: ""
    property string size: "sm"
    property string tone: "neutral"
    property bool verbatim: false
    readonly property bool unread: variant === "unread"
    readonly property string displayedText: unread && /^[0-9]+$/.test(text) && Number(text) > 99 ? "99+" : text
    readonly property real diameter: unread && displayedText.length > 2 ? Math.max(sizeTokens.height, Theme.size.control.sm) : sizeTokens.height
    readonly property color foreground: unread ? Theme.color.onAccent : tokens.foreground
    readonly property var tokens: toneOf(tone)
    readonly property var sizeTokens: sizeOf(size)
    readonly property real sidePadding: unread ? Math.max(0, (diameter - label.opticalWidth) / 2)
        : Theme.controlPadding(sizeTokens.paddingX, Theme.badge.radius, sizeTokens.height, Math.max(icon.visible ? icon.height : 0, label.lineBox))

    Accessible.role: Accessible.StaticText
    Accessible.name: text

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
    implicitHeight: unread ? diameter : sizeTokens.height
    radius: unread ? Theme.radius.full : Theme.badge.radius
    color: unread ? Theme.color.accent : tokens.background

    Icon {
        id: icon
        visible: root.iconName !== "" && !root.unread
        name: root.iconName
        size: Theme.icon.size.xs
        color: root.foreground
        x: root.sidePadding
        y: Math.round(root.height / 2 - height / 2)
    }

    Label {
        id: label
        role: root.verbatim ? "kbd" : "label"
        text: root.displayedText
        color: root.foreground
        x: root.sidePadding + (icon.visible ? icon.width + Theme.badge.gap : 0)
        y: topForCapCenter(root.height)
        width: root.width < root.implicitWidth ? Math.max(0, root.width - x - root.sidePadding) : implicitWidth
        elide: Text.ElideRight
    }
}
