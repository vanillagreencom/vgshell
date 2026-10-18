import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// Text with cited substrings as independent links. The text property is plain
// text; every occurrence of `link` is drawn as a link and activates the
// component. `lineCount` is the wrapped label's line count, for owners that
// measure whether the message stayed on one line, `inkAbove()` is the
// label's (Label.qml), and `inkBelow()` is the
// label's over the last line's text, which the plain twin
// lays out at the same width, or the link's underline where an
// occurrence reaches that line and the underline ends lower. Use it where a consumer
// surface cites a file that the core can open through `vgshell edit`.
// A page reference in the text, `[words](page:<plugin id>)` or
// `[words](page:<plugin id>/<tab>)`, or a file reference,
// `[words](file:<encoded path>)`, which PageReference.js reads, draws its words
// alone, as a link while the text holds no `link` words and the reference
// names a page or a file, so an owner's fixed `link` gives way in a text
// that does not cite it, and activating it emits `pageActivated` with that
// page and tab, "" for no tab, in place of `activated`: a file
// reference's page is `file:<path>`. The owner hands it on to the core's
// one reference route, which opens a page in Settings and a file or folder
// through the core edit route (`shell.tui.edit`); a reference to no page,
// as `[words](page:)`, reads as its words.
// The focus ring goes round the selected link's words, `linkBox`, not
// the whole text, so a ring on a line of prose shows which words act.
// The box holds the words and the punctuation against their end, since a
// ring cannot part a mark from its word and the text keeps its spacing
// at rest. It runs from their highest ink to the underline's bottom, and
// the ring stands `focusRing.offset` clear of it on every side. The glyph
// before the words stands a pixel past the ring's outer edge or further:
// where the line is short of that room, `drawn` holds a no-break gap
// there. `ringBelow` is how far the ring's outer edge lies
// under this item, for an owner whose edge the ring must clear.
// `focusPreview` draws that ring for an owner that keeps the keyboard and
// names this link as its current one, as a tooltip's item does.
// Every occurrence is drawn in `linkColor`, the accent unless the look
// that hosts the text hands its own, over its own underline, the
// label's `underlineOffset` under each line's baseline, since Qt Quick
// draws a link's or `<u>`'s underline at the font's underline position,
// which a descender meets (Qt 6.11 qquickstyledtext.cpp,
// parseAnchorAttributes; qquicktextnodeengine.cpp, addTextDecorations).
// The pointer reaches the words on those underlined runs, and while it
// is on them the hovered link grows `linkText.underlineHover` thicker, downward,
// so the row under the descenders stays clear.
T.Control {
    id: root

    property string text: ""
    property string link: ""
    property string role: "body"
    property bool focusPreview: false
    property alias color: label.color
    property color linkColor: Theme.color.accent
    property alias wrapMode: label.wrapMode
    property alias horizontalAlignment: label.horizontalAlignment
    readonly property alias lineCount: label.lineCount
    readonly property var reference: PageReference.parse(text)
    // The text drawn and the words of it that are the link.
    readonly property var references: PageReference.references(text)
    readonly property string plain: references.text
    // Whether the text cites `link`: a link it does not cite gives way to
    // the page reference.
    readonly property bool cited: link !== "" && plain.indexOf(link) !== -1
    readonly property string words: cited ? link : reference.page !== "" ? reference.words : ""
    readonly property var links: cited ? explicitLinks() : references.links.filter(item => item.page !== "")
    property int currentLink: 0
    readonly property bool linked: links.length > 0
    readonly property int hoveredIndex: linked && pointer.containsMouse ? linkAt(pointer.mouseX, pointer.mouseY) : -1
    readonly property bool hoveredLink: hoveredIndex !== -1
    // The room the ring takes before the words: its offset, its width and
    // one pixel clear of the glyph there.
    readonly property real ringRoom: Theme.focusRing.offset + Theme.focusRing.width + 1
    // The text drawn: `plain` with the gaps the ring needs.
    readonly property var layout: positioned(underline.font)
    readonly property string drawn: layout.text
    // The selected link and the marks against its end, as the
    // [start, end) indices of `drawn`.
    readonly property var run: linked && currentLink < layout.links.length ? [layout.links[currentLink].start, marked(layout.links[currentLink].end)] : [0, 0]
    // That run's box in this item, on the line it is laid out on, once
    // the twin holds the text. The arguments name what the twin's layout
    // depends on, since its positions are a function a binding cannot
    // follow. A new text reaches the twin before `run` follows it, so the
    // box waits for a run that lies inside the text; the twin has no
    // position past its end.
    readonly property rect linkBox: linked && twin.length === drawn.length && run[1] > run[0] && run[1] <= drawn.length ? wordsBox(twin.contentWidth, twin.contentHeight, twin.lineCount) : Qt.rect(0, 0, width, height)
    readonly property real ringBelow: linkBox.y + linkBox.height + Theme.focusRing.offset + Theme.focusRing.width - height
    // Each occurrence's span on each line it is laid out on, as
    // { line, left, right, index }, under the same wait for the twin.
    readonly property var underlined: linked && twin.length === drawn.length ? wordSpans(twin.contentWidth, twin.contentHeight, twin.lineCount) : []
    // The label's distance from one line's baseline to the next.
    readonly property real linePitch: label.contentHeight / Math.max(1, label.lineCount)
    readonly property real underlineThickness: Inset.underlineWidth(underline.lineWidth)
    signal activated()
    signal pageActivated(string page, string tab)
    signal clicked()

    function htmlEscaped(value) {
        return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\u202f/g, "&#x202f;");
    }

    function markup(plain, colour) {
        let out = "";
        let end = 0;
        for (const item of layout.links) {
            out += htmlEscaped(plain.slice(end, item.start));
            out += "<font color=\"" + colour + "\">" + htmlEscaped(plain.slice(item.start, item.end)) + "</font>";
            end = item.end;
        }
        return out + htmlEscaped(plain.slice(end));
    }

    // Where the glyphs against index `end` of `drawn` stop.
    function marked(end) {
        while (end < drawn.length && !/\s/.test(drawn.charAt(end))) end++;
        return end;
    }

    // The gap before an occurrence, where `beside` is the text before it,
    // nearest glyph first: as many narrow no-break spaces, glue the line
    // never breaks at, as the room there is short of `ringRoom`. A word
    // space there is room, and no glyph or a line break past it needs
    // none. One such space is 2.4 px at 13 px, which a word space of 3.7 px
    // there is short by (FontMetrics.advanceWidth, Inter Variable, under
    // scripts/qml-unit.sh on 2026-10-13). Styled text reads a run of spaces
    // of any kind as one plain space and keeps a space only as an entity
    // (Qt 6.11 qquickstyledtext.cpp, parse and parseEntity), which
    // `htmlEscaped` writes.
    function gap(beside) {
        const space = beside.charAt(0) === " ";
        const next = beside.charAt(space ? 1 : 0);
        if (next === "" || /\s/.test(next)) return "";
        const short = ringRoom - (space ? underline.advanceWidth(" ") : 0);
        return "\u202f".repeat(Math.max(0, Math.ceil(short / underline.advanceWidth("\u202f"))));
    }

    // `plain` with each occurrence's gap. The gap stays on the far side of
    // the space before the words, so no wrapped line starts with one, and
    // the text after the words keeps its spacing. `font` names what the
    // gaps depend on, since a metric is a function a binding cannot follow.
    function explicitLinks() {
        const result = [];
        for (let at = plain.indexOf(link); at !== -1; at = plain.indexOf(link, at + link.length))
            result.push({ start: at, end: at + link.length, words: link, page: "", tab: "" });
        return result;
    }

    function positioned(font) {
        let out = "";
        let end = 0;
        const positionedLinks = [];
        for (const item of links) {
            const part = plain.slice(end, item.start);
            const ends = part.endsWith(" ") ? 1 : 0;
            out += part.slice(0, part.length - ends) + gap(part.slice(-2).split("").reverse().join("")) + part.slice(part.length - ends);
            const start = out.length;
            out += item.words;
            positionedLinks.push({ start: start, end: out.length, page: item.page, tab: item.tab });
            end = item.end;
        }
        return { text: out + plain.slice(end), links: positionedLinks };
    }

    // Where the underline of line `line` ends, from the label's top.
    function underlineBottom(line) {
        return label.baselineOffset + line * linePitch + label.underlineOffset + underlineThickness;
    }

    // Text reports no character position, so a TextEdit twin laid out in
    // the label's font, width, wrap and alignment gives the words' x and
    // line; Text and TextEdit break lines through the same QTextLayout.
    // The box is on whole pixels, as the ring round it draws. Its top is
    // floored: the highest ink draws on the floor's row (the capital's top
    // row on scripts/sandbox-shots.sh tooltip-link, Inter Variable 13 px,
    // on 2026-10-13). Words that wrap take their lines' full width.
    function wordsBox(twinWidth, twinHeight, twinLines) {
        const from = twin.positionToRectangle(run[0]);
        const first = lineOf(from, twinHeight, twinLines);
        const last = lineOf(twin.positionToRectangle(run[1] - 1), twinHeight, twinLines);
        const held = drawn.slice(run[0], run[1]);
        const top = Math.floor(label.baselineOffset + first * linePitch + underline.tightBoundingRect(held).y);
        const height = Math.ceil(underlineBottom(last)) - top;
        if (last !== first) return Qt.rect(0, top, width, height);
        const left = Math.round(from.x);
        return Qt.rect(left, top, Math.round(from.x + underline.advanceWidth(held)) - left, height);
    }

    function lineOf(r, twinHeight, twinLines) {
        return Math.floor((r.y + r.height / 2) / (twinLines > 0 ? twinHeight / twinLines : 1));
    }

    function wordSpans(twinWidth, twinHeight, twinLines) {
        const spans = [];
        for (let index = 0; index < layout.links.length; index++) {
            const item = layout.links[index];
            let span = null;
            for (let i = item.start; i < item.end; i++) {
                const glyph = twin.positionToRectangle(i);
                const line = lineOf(glyph, twinHeight, twinLines);
                const right = glyph.x + underline.advanceWidth(drawn.charAt(i));
                if (span !== null && span.line === line) {
                    span.right = right;
                } else {
                    span = { line: line, left: glyph.x, right: right, index: index };
                    spans.push(span);
                }
            }
        }
        return spans;
    }

    function onWords(x, y) {
        return linkAt(x, y) !== -1;
    }

    function linkAt(x, y) {
        const span = underlined.find(span => x >= span.left && x < span.right && y >= span.line * linePitch && y < (span.line + 1) * linePitch);
        return span === undefined ? -1 : span.index;
    }

    onLinksChanged: currentLink = 0
    onClicked: {
        const target = links[currentLink];
        if (target !== undefined && !cited && target.page !== "") pageActivated(target.page, target.tab);
        else activated();
    }

    function inkAbove() { return label.y + label.inkAbove(); }

    // Every occurrence is underlined, so the underline reaches the last
    // line when the last occurrence ends past that line's start.
    function inkBelow() {
        const lastStart = twin.length === drawn.length ? twin.positionAt(0, twin.contentHeight - 1) : -1;
        const glyphs = label.inkBelow(lastStart < 0 ? undefined : drawn.slice(lastStart));
        const lastUnderlined = linked && lastStart >= 0 && layout.links.some(item => item.end > lastStart);
        return height - label.y - label.height + (lastUnderlined ? Math.min(glyphs, label.height - underlineBottom(label.lineCount - 1)) : glyphs);
    }

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight
    height: implicitHeight
    activeFocusOnTab: linked
    Accessible.name: plain
    Accessible.role: linked ? Accessible.Link : Accessible.StaticText

    // Qt Keys accepts handled events before the control's default handler:
    // https://doc.qt.io/qt-6/qml-qtquick-keys.html#key-handling-priorities
    Keys.onPressed: event => { event.accepted = !cited && links.length > 1 && navigation.handle(event); }


    Keys.onReturnPressed: event => { if (root.linked) root.clicked(); else event.accepted = false; }
    Keys.onEnterPressed: event => { if (root.linked) root.clicked(); else event.accepted = false; }
    Keys.onSpacePressed: event => { if (root.linked) root.clicked(); else event.accepted = false; }

    Label {
        id: label
        role: root.role
        width: root.width
        text: root.markup(root.drawn, root.linkColor)
        textFormat: Text.StyledText
    }

    KeyNav {
        id: navigation
        focusTarget: root
        count: root.links.length
        currentIndex: root.currentLink
        orientation: "horizontal"
        onMoved: index => root.currentLink = index
    }

    Repeater {
        model: root.underlined
        Rectangle {
            required property var modelData
            x: modelData.left
            y: label.baselineOffset + modelData.line * root.linePitch + label.underlineOffset
            width: modelData.right - modelData.left
            height: root.underlineThickness + ((root.cited ? root.hoveredLink : root.hoveredIndex === modelData.index) ? Theme.linkText.underlineHover : 0)
            color: root.linkColor
        }
    }

    TextEdit {
        id: twin
        visible: false
        readOnly: true
        width: label.width
        text: root.drawn
        textFormat: TextEdit.PlainText
        font: label.font
        wrapMode: label.wrapMode
        horizontalAlignment: label.horizontalAlignment
    }

    FontMetrics {
        id: underline
        font: label.font
    }

    // FocusRing stands `focusRing.offset` outside this item, the words'
    // box, on every side.
    Item {
        x: root.linkBox.x
        y: root.linkBox.y
        width: root.linkBox.width
        height: root.linkBox.height

        FocusRing {
            target: root
            outside: true
        }
    }

    // keyboard-path: Return, Enter and Space activate the focused link
    MouseArea {
        id: pointer
        anchors.fill: label
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onPressed: mouse => { mouse.accepted = root.onWords(mouse.x, mouse.y); }
        onClicked: mouse => {
            root.currentLink = root.cited ? 0 : root.linkAt(mouse.x, mouse.y);
            root.forceActiveFocus(Qt.MouseFocusReason);
            root.clicked();
        }
        PointerCursor {
            enabled: root.hoveredLink
        }
    }
}
