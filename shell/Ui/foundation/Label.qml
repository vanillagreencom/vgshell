import QtQuick
import qs.Commons
import "LineBreak.js" as LineBreak

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
// `xCentre` is the first line's x-height centre from the label top.
// `capitalsLine` is whether that line reads in capitals and figures: drawn
// in capitals, or text with no lowercase letter, such as "CPU" or "42%".
// Empty text reads as mixed case unless the role draws in capitals, so an
// empty field's icon stands where its typed text will read.
// `topForLeadingIcon(iconHeight, origin, link)` gives the top, from the label
// top, that puts an icon leading the first line on the centre the eye
// levels it with: the x-height centre for mixed case, whose ink sits
// mostly between the baseline and the x-height, and the capital centre
// for a capitals line. The icon's top lands on a device pixel of the
// frame the label top sits `origin` into (default 0, a label top on a
// whole pixel).
// A true `link` centres a single mixed-case line between its highest ink
// and baseline, excluding descenders. FontMetrics.tightBoundingRect is
// relative to the baseline (Qt 6.12.0, qml-unit run actual-font-metrics,
// VGS-1966). Empty, capitals and wrapped lines keep
// their existing reading, so a link never changes a block's placement.
// `capTop()` is how far below the label top the first line's capitals
// start, `inkAbove()` how far below it the first line's ink starts, its
// glyphs' highest ink for a one-line label and the capital top for a
// wrapped one, whose first line's text it does not know, and
// `inkBelow(lastLine)` how far above its bottom edge the last
// line's ink ends: its glyphs' lowest ink (FontMetrics.tightBoundingRect,
// whose origin is the baseline) for a one-line label, a caller that
// names the last line's text, or a wrapped label of plain text, whose
// last line a hidden twin laid out alike names, as LinkText's does, else
// the baseline in capitals and the descent in mixed case. The twin is
// built at the first such reading, so only a label whose ink a layout
// reads, such as the last of a group, lays its text out twice.
// `lastBaseline()` is the last line's baseline from the label top: lines
// of one label share one line box, so it is the first one
// `baselineOffset` places, moved down by every line box but the last.
// `spaceWrappedText`, when set, is the plain value drawn broken only at
// spaces. Label re-breaks it when the value, width or font changes; the
// caller keeps the plain value for its accessible name.
Text {
    id: root

    property string role: "body"
    property var spaceWrappedText: null
    readonly property var typography: typographyOf(role)
    readonly property real fontHeight: metrics.height
    readonly property real lineBox: Math.max(Math.round(typography.size * typography.lineHeight), Math.ceil(fontHeight))
    readonly property real halfLeading: Math.max(0, (lineBox - fontHeight) / 2)
    readonly property real capCentre: metrics.ascent - metrics.capitalHeight / 2
    readonly property real xCentre: metrics.ascent - metrics.xHeight / 2
    readonly property bool capitalsLine: font.capitalization === Font.AllUppercase || (text !== "" && text.toUpperCase() === text)
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

    // Assign from handlers: atSpaces writes the measuring text, so a
    // binding would read its own writes (Quickshell 0.3.1 QML language:
    // https://quickshell.org/docs/v0.3.1/guide/qml-language).
    function breakLines() {
        if (spaceWrappedText !== null) text = LineBreak.atSpaces(spaceWrappedText, width, lineMetrics);
    }
    onSpaceWrappedTextChanged: breakLines()
    onWidthChanged: breakLines()
    Component.onCompleted: breakLines()

    TextMetrics {
        id: lineMetrics
        font: root.font
        onFontChanged: root.breakLines()
    }

    function capTop() {
        return baselineOffset - metrics.capitalHeight;
    }

    function inkAbove() {
        if (lineCount > 1 || text === "") return capTop();
        return baselineOffset + metrics.tightBoundingRect(typography.uppercase ? text.toUpperCase() : text).y;
    }

    function lastBaseline() {
        const lines = Math.max(1, lineCount);
        return baselineOffset + contentHeight * (lines - 1) / lines;
    }

    // The twin, made at the first reading. A plain object, so making it
    // notifies no binding that reads the label's ink while it runs.
    readonly property var twinHolder: ({ twin: null })

    // The last drawn line's text of a wrapped label, or null for rich
    // text, while the twin is not laid out at this text and width, or
    // when the label elides.
    function lastLineText() {
        if (textFormat !== Text.PlainText && textFormat !== Text.AutoText) return null;
        if (twinHolder.twin === null) twinHolder.twin = twinComponent.createObject(root);
        const laid = twinHolder.twin;
        if (truncated || laid.width !== width || laid.length !== text.length) return null;
        return text.slice(laid.positionAt(0, laid.contentHeight - 1));
    }

    function inkBelow(lastLine) {
        const lines = Math.max(1, lineCount);
        const known = lastLine !== undefined ? lastLine : lines === 1 ? text : lastLineText();
        const ink = known === null ? null : metrics.tightBoundingRect(typography.uppercase ? known.toUpperCase() : known);
        const below = ink !== null ? Math.max(0, ink.y + ink.height) : typography.uppercase ? 0 : metrics.descent;
        return height - lastBaseline() - below;
    }

    function topForCapCenter(boxHeight) {
        return Math.round((boxHeight / 2 + metrics.capitalHeight / 2) * Screen.devicePixelRatio) / Screen.devicePixelRatio - metrics.ascent;
    }

    function topForLeadingIcon(iconHeight, origin, link) {
        const centre = capitalsLine ? capCentre : xCentre;
        if (link === true && !capitalsLine && text !== "" && lineCount === 1) {
            const ink = metrics.tightBoundingRect(text);
            return leadingIconTop(iconHeight, origin, baselineOffset + ink.y / 2);
        }
        return leadingIconTop(iconHeight, origin, centre);
    }

    function leadingIconTop(iconHeight, origin, centre) {
        const at = origin === undefined ? 0 : origin;
        return Math.round((at + centre - iconHeight / 2) * Screen.devicePixelRatio) / Screen.devicePixelRatio - at;
    }

    FontMetrics {
        id: metrics
        font: root.font
    }

    // Text reports no character position, so a TextEdit laid out at the
    // same width and font gives the last line's first one. A Component is
    // no item, so a label that is never read adds none to the scene.
    Component {
        id: twinComponent
        TextEdit {
            visible: false
            readOnly: true
            width: root.width
            text: root.text
            textFormat: root.textFormat === Text.PlainText ? TextEdit.PlainText : TextEdit.AutoText
            font: root.font
            wrapMode: root.wrapMode
            horizontalAlignment: root.horizontalAlignment
        }
    }
}
