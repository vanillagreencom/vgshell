import QtQuick
import QtQuick.Templates as T
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
// `variant: "unread"` draws a circular count, its fill and figures from
// `Theme.badge.unread.tone` at `level`, `neutral` (muted ink, for a count
// at rest), `normal` (the accent), `warning` or `danger`; an unknown level
// is logged and drawn normal. Counts above
// 99 read 99+ in the next control size while the accessible name keeps
// the count. `size: "corner"` is the count at a bar item's top-right
// (BarItem's `count`): a `badge.unread.corner` circle with its ring in the
// bar's background, figures in the bar role at `bar.stacked.size`, and
// above 9 it reads 9+ in a pill that holds `space.xxs` inside its ring
// either side. `tooltip` and `tooltipDetails` open the shared Tooltip on
// hover and keyboard focus; page links emit `tooltipPageActivated`. The
// accessible name includes the same explanation. Without help the badge
// takes no keyboard focus.
T.Control {
    id: root

    property string text: ""
    property string variant: "status"
    property string iconName: ""
    property string size: "sm"
    property string tone: "neutral"
    property bool verbatim: false
    property string tooltip: ""
    property var tooltipDetails: []
    signal tooltipPageActivated(string page, string tab)
    property alias radius: chip.radius
    property alias color: chip.color
    property alias border: chip.border
    // The unread count's level: "neutral", "normal", "warning" or "danger".
    property string level: "normal"
    readonly property bool unread: variant === "unread"
    readonly property bool corner: unread && size === "corner"
    // The most a count draws before it reads N+.
    readonly property int countMax: corner ? 9 : 99
    readonly property string displayedText: unread && /^[0-9]+$/.test(text) && Number(text) > countMax ? countMax + "+" : text
    readonly property real diameter: unread && !corner && displayedText.length > 2 ? Math.max(sizeTokens.height, Theme.size.control.sm) : sizeTokens.height
    readonly property color foreground: unread ? unreadTokens.foreground : tokens.foreground
    readonly property var tokens: toneOf(tone)
    readonly property var unreadTokens: levelOf(level)
    readonly property var sizeTokens: corner ? Theme.badge.unread.corner : sizeOf(size)
    readonly property real sidePadding: corner ? Math.max((diameter - label.opticalWidth) / 2, Theme.space.xxs + Theme.badge.unread.corner.border)
        : unread ? Math.max(0, (diameter - label.opticalWidth) / 2)
        : Theme.controlPadding(sizeTokens.paddingX, Theme.badge.radius, sizeTokens.height, Math.max(icon.visible ? icon.height : 0, label.lineBox))

    Accessible.role: Accessible.StaticText
    Accessible.name: tooltip === "" ? text : PageReference.plain([tooltip].concat(tooltipDetails).join("\n"))
    // Control supplies visualFocus for the shared Tooltip and FocusRing.
    // https://doc.qt.io/qt-6/qml-qtquick-controls-control.html#visualFocus-prop
    focusPolicy: tooltip === "" ? Qt.NoFocus : Qt.TabFocus
    Keys.onPressed: event => {
        event.accepted = tip.takeKey(event);
        // A help-only badge has no activation of its own. Do not pass
        // these keys to a containing list's selected-row action.
        if (!event.accepted && [Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space].indexOf(event.key) !== -1)
            event.accepted = true;
    }

    Tooltip {
        id: tip
        text: root.tooltip
        details: root.tooltipDetails
        side: "clear"
        pageLinks: true
        onPageActivated: (page, tab) => root.tooltipPageActivated(page, tab)
    }

    function toneOf(name) {
        const found = Theme.badge.tone[name];
        if (found !== undefined) return found;
        console.error("Badge: no tone named " + JSON.stringify(name));
        return Theme.badge.tone.neutral;
    }

    function levelOf(name) {
        const found = Theme.badge.unread.tone[name];
        if (found !== undefined) return found;
        console.error("Badge: no level named " + JSON.stringify(name));
        return Theme.badge.unread.tone.normal;
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
    color: unread ? unreadTokens.background : tokens.background
    // A Rectangle draws its border inside its edge, so the corner count's
    // ring takes from its fill, not its size.
    border.width: corner ? Theme.badge.unread.corner.border : 0
    border.color: Theme.badge.unread.corner.borderColor
    background: Rectangle { id: chip }
    FocusRing { target: tip.currentLine === -1 ? root : null; targetRadius: root.radius }

    // The icon is built only for a chip that draws one, so a count or a
    // chip without one holds no hidden Icon for a reader of the item it
    // sits in to find first. A Loader with no size of its own takes its
    // item's size, and 0 while inactive
    // (https://doc.qt.io/qt-6/qml-qtquick-loader.html#loader-sizing-behavior).
    Loader {
        id: icon
        active: root.iconName !== "" && !root.unread
        visible: active
        x: root.sidePadding
        y: Math.round(root.height / 2 - height / 2)
        sourceComponent: Icon {
            name: root.iconName
            size: Theme.icon.size.xs
            color: root.foreground
        }
    }

    Label {
        id: label
        role: root.verbatim ? "kbd" : root.corner ? "bar" : "label"
        // The corner figures take the bar role at the stacked size, with
        // the role's tracking at that size, as a stacked bar reading does.
        // Each reads the size, not font.pixelSize: a font sub-property
        // read inside the font group's own binding loops (Qt 6.11).
        readonly property real size: root.corner ? Theme.bar.stacked.size : typography.size
        font.pixelSize: size
        font.letterSpacing: typography.letterSpacing * size
        text: root.displayedText
        color: root.foreground
        x: root.sidePadding + (icon.visible ? icon.width + Theme.badge.gap : 0)
        y: topForCapCenter(root.height)
        width: root.width < root.implicitWidth ? Math.max(0, root.width - x - root.sidePadding) : implicitWidth
        elide: Text.ElideRight
    }
}
