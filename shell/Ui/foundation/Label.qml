import QtQuick
import qs.Commons

// Text in one typography role of the theme: `role` names a group of
// `Theme.text`, and the family, size, weight, letter spacing, line height,
// case and colour follow it. A role the theme lacks is logged and drawn as
// body. Both `font.weight` and `font.variableAxes` carry the weight, since
// a variable font moves on the axis alone and a static family on the
// weight alone. Letter spacing is stated in em and set in pixels here.
// `lineBox` is the role's font-size multiple, floored at the font's own
// line box rounded up to a whole pixel. `halfLeading` is the extra line space above and below each
// fixed line. `capCentre` is the first line's capital centre from the
// label top. `opticalWidth` removes the tracking Qt adds after the last
// glyph. `topForCapCenter()` gives the top that puts the capital centre on
// a box centre with the baseline on a whole device pixel of the label's own
// screen, since a whole pixel spans two device pixels on a 2x screen.
// `capTop()` is how far below the label top the first line's capitals
// start, and `inkBelow(lastLine)` how far above its bottom edge the last
// line's ink ends: its glyphs' lowest ink (FontMetrics.tightBoundingRect,
// whose origin is the baseline) for a one-line label or a caller that
// names the last line's text, else the baseline in capitals and the
// descent in mixed case. Lines of one label share one line box, so the
// last baseline is the first one `baselineOffset` places, moved down by
// every line box but the last.
Text {
    id: root

    property string role: "body"
    readonly property var typography: typographyOf(role)
    readonly property real fontHeight: metrics.height
    readonly property real lineBox: Math.max(Math.round(typography.size * typography.lineHeight), Math.ceil(fontHeight))
    readonly property real halfLeading: Math.max(0, (lineBox - fontHeight) / 2)
    readonly property real capCentre: metrics.ascent - metrics.capitalHeight / 2
    readonly property real opticalWidth: Math.max(0, implicitWidth - (text === "" ? 0 : font.letterSpacing))

    function typographyOf(name) {
        const found = Theme.text[name];
        if (found !== undefined) return found;
        console.error("Label: no text role named " + JSON.stringify(name));
        return Theme.text.body;
    }

    color: typography.color
    font.family: typography.family
    font.pixelSize: typography.size
    font.weight: typography.weight
    font.variableAxes: ({ wght: typography.weight })
    font.letterSpacing: typography.letterSpacing * typography.size
    font.capitalization: typography.uppercase ? Font.AllUppercase : Font.MixedCase
    lineHeight: lineBox > fontHeight ? lineBox : 1
    lineHeightMode: lineBox > fontHeight ? Text.FixedHeight : Text.ProportionalHeight

    function capTop() {
        return baselineOffset - metrics.capitalHeight;
    }

    function inkBelow(lastLine) {
        const lines = Math.max(1, lineCount);
        const known = lastLine !== undefined ? lastLine : lines === 1 ? text : null;
        const ink = known === null ? null : metrics.tightBoundingRect(typography.uppercase ? known.toUpperCase() : known);
        const below = ink !== null ? Math.max(0, ink.y + ink.height) : typography.uppercase ? 0 : metrics.descent;
        return height - baselineOffset - contentHeight * (lines - 1) / lines - below;
    }

    function topForCapCenter(boxHeight) {
        return Math.round((boxHeight / 2 + metrics.capitalHeight / 2) * Screen.devicePixelRatio) / Screen.devicePixelRatio - metrics.ascent;
    }

    FontMetrics {
        id: metrics
        font: root.font
    }
}
