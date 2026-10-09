import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// Text with one cited substring as a link. The text property is plain
// text; every occurrence of `link` is drawn as a link and activates the
// component. `lineCount` is the wrapped label's line count, for owners that
// measure whether the message stayed on one line, and `inkBelow()` is the
// label's (Label.qml) over the last line's text, which the plain twin
// lays out at the same width. Use it where a consumer
// surface cites a file that the core can open through `vgshell edit`.
// The focus ring goes round the first occurrence's words, `linkBox`, not
// the whole text, so a ring on a line of prose shows which words act.
// The box runs on to the spaces around the occurrence, so punctuation
// against it sits inside the ring, and the ring reaches sideways no
// further than one space less a pixel, so it touches no neighbouring word.
T.Control {
    id: root

    property string text: ""
    property string link: ""
    property string role: "body"
    property alias color: label.color
    property alias wrapMode: label.wrapMode
    property alias horizontalAlignment: label.horizontalAlignment
    readonly property alias lineCount: label.lineCount
    readonly property bool linked: link !== "" && text.indexOf(link) !== -1
    readonly property bool hoveredLink: linked && pointer.containsMouse && label.linkAt(pointer.mouseX, pointer.mouseY) !== ""
    // The first occurrence widened to the spaces around it, as the
    // [start, end) indices of `text`.
    readonly property var run: linked ? wordRun(text.indexOf(link), text.indexOf(link) + link.length) : [0, 0]
    // That run's box in this item: its x span on the line it is laid out
    // on, one label line box tall, once the twin holds the text. The
    // arguments name what the twin's layout depends on, since its
    // positions are a function a binding cannot follow. A new text
    // reaches the twin before `run` follows it, so the box waits for a run
    // that lies inside the text; the twin has no position past its end.
    readonly property rect linkBox: linked && twin.length === text.length && run[1] <= text.length ? wordsBox(twin.contentWidth, twin.contentHeight, twin.lineCount, label.lineBox) : Qt.rect(0, 0, width, height)
    // How far the ring's outer edge lies beside the run: the standard
    // offset and width, cut to one space less a pixel.
    readonly property real ringReach: Math.min(Theme.focusRing.offset + Theme.focusRing.width, spaceGlyph.advanceWidth - 1)
    signal activated()
    signal clicked()

    function htmlEscaped(value) {
        return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function markup(plain, cited) {
        const escaped = htmlEscaped(plain);
        const needle = htmlEscaped(cited);
        if (needle === "") return escaped;
        const parts = escaped.split(needle);
        const anchor = "<a href=\"file\"><u>" + needle + "</u></a>";
        return parts.join(anchor);
    }

    function wordRun(start, end) {
        while (start > 0 && !/\s/.test(text.charAt(start - 1))) start--;
        while (end < text.length && !/\s/.test(text.charAt(end))) end++;
        return [start, end];
    }

    // Text reports no character position, so a TextEdit twin laid out in
    // the label's font, width, wrap and alignment gives the words' x and
    // line; Text and TextEdit break lines through the same QTextLayout.
    // Words that close one line and wrap at their end read the cursor at
    // the next line's start, so their end is their last glyph's start plus
    // its advance.
    function wordsBox(twinWidth, twinHeight, twinLines, lineBox) {
        const start = run[0];
        const end = run[1];
        const spacing = twinLines > 0 ? twinHeight / twinLines : 1;
        const lineOf = r => Math.floor((r.y + r.height / 2) / spacing);
        const from = twin.positionToRectangle(start);
        let to = twin.positionToRectangle(end);
        let right = to.x;
        if (lineOf(to) !== lineOf(from)) {
            to = twin.positionToRectangle(end - 1);
            right = to.x + lastGlyph.advanceWidth;
        }
        if (lineOf(to) !== lineOf(from))
            return Qt.rect(0, lineOf(from) * lineBox, width, (lineOf(to) - lineOf(from) + 1) * lineBox);
        return Qt.rect(from.x, lineOf(from) * lineBox, right - from.x, lineBox);
    }

    onClicked: activated()

    function inkBelow() {
        const lastLine = twin.length === text.length ? text.slice(twin.positionAt(0, twin.contentHeight - 1)) : undefined;
        return height - label.y - label.height + label.inkBelow(lastLine);
    }

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight
    height: implicitHeight
    activeFocusOnTab: linked
    Accessible.name: text
    Accessible.role: linked ? Accessible.Link : Accessible.StaticText

    Keys.onReturnPressed: event => { if (root.linked) root.clicked(); else event.accepted = false; }
    Keys.onEnterPressed: event => { if (root.linked) root.clicked(); else event.accepted = false; }
    Keys.onSpacePressed: event => { if (root.linked) root.clicked(); else event.accepted = false; }

    Label {
        id: label
        role: root.role
        width: root.width
        text: root.markup(root.text, root.link)
        textFormat: Text.StyledText
        linkColor: Theme.color.accent
    }

    TextEdit {
        id: twin
        visible: false
        readOnly: true
        width: label.width
        text: root.text
        textFormat: TextEdit.PlainText
        font: label.font
        wrapMode: label.wrapMode
        horizontalAlignment: label.horizontalAlignment
    }

    TextMetrics {
        id: lastGlyph
        font: label.font
        text: root.text.charAt(root.run[1] - 1)
    }

    TextMetrics {
        id: spaceGlyph
        font: label.font
        text: " "
    }

    // FocusRing reaches its standard extent outside this item, which
    // stands in from the run by the part of it the reach cuts.
    Item {
        readonly property real inset: Theme.focusRing.offset + Theme.focusRing.width - root.ringReach
        x: root.linkBox.x + inset
        y: root.linkBox.y
        width: root.linkBox.width - 2 * inset
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
        onPressed: mouse => { mouse.accepted = label.linkAt(mouse.x, mouse.y) !== ""; }
        onClicked: root.clicked()
        PointerCursor {
            enabled: root.hoveredLink
        }
    }
}
