import QtQuick
import qs.Ui

// Jarvis's words while its voice is muted, above the orb: the newest line
// at the bottom and at most `words.lines` lines, each older line fainter.
// Words appear one each `words.step` until they catch up with `text`, the
// newest fading in over `words.fade`; a new line moves the lines up over
// `words.lift` while the line leaving the top fades out. Each is a Qt
// animation that ends once the words catch up, never a ticking driver, and
// at motion scale 0 every duration is 0, so the text appears whole. It
// draws only, in the look its bubble hands it, each line over the look's
// text shadow: a 0-offset blur of the line's layer, which Qt draws again
// only while that line changes, so a lift or a still line redraws no blur.
//
// A caption that grows, as a duplex voice's does chunk by chunk, keeps the
// words drawn: it extends them when every drawn word but the last is the
// same and the last drawn word begins the word in its place, as "that"
// becomes "that." A caption that changes an earlier word starts over.
//
// Per frame only the reveal's count, the newest word's opacity and the
// lift move; no text is laid out again. The lines are laid out here, at
// spaces, when a word is added or the caption, width or font changes, and
// only from `start`, the first word of the oldest line still drawn, so a
// long reply lays out its tail alone.
Item {
    id: root

    required property var look
    property string text: ""
    readonly property var list: text.trim() === "" ? [] : text.trim().split(/\s+/)
    property real progress: 0
    readonly property int count: Math.min(list.length, Math.floor(progress))
    // The words drawn now, as plain text.
    readonly property string shown: list.slice(0, count).join(" ")
    // The newest word's opacity while it fades in.
    property real newest: 1
    property real lift: 0
    // How many lines the window shows.
    readonly property int window: look.words.lines
    readonly property real lineBox: probe.lineBox
    // The laid-out tail, oldest first, each { from, head, last }: a line's
    // first word in `list`, its words but the last, and its last word. It
    // holds one line above the window, the line a lift fades out.
    property var lines: []
    // Lines dropped from the front of the tail; with `lines`, how many
    // lines the shown words take.
    property int dropped: 0
    property int start: 0
    readonly property int lineCount: count === 0 ? 0 : dropped + lines.length
    readonly property bool settled: count === list.length && !reveal.running && !fade.running && !rise.running
    // The previous caption's words, which the next must extend.
    property var held: []

    implicitHeight: window * lineBox
    visible: count > 0
    clip: true
    Accessible.ignored: true

    function extendsDrawn(drawn, next) {
        if (drawn.length > next.length) return false;
        for (let i = 0; i < drawn.length - 1; i++) if (drawn[i] !== next[i]) return false;
        return drawn.length === 0 || next[drawn.length - 1].startsWith(drawn[drawn.length - 1]);
    }

    // The words from `start` to `count` broken at spaces into lines no wider
    // than the view, by qs.Ui's LineBreak.rows, measured by a TextMetrics in
    // the label's font. It writes metrics.text, so it runs from handlers
    // only.
    function relayout() {
        const before = lineCount;
        if (count === 0 || !(width > 0)) {
            lines = [];
            return;
        }
        let rows = LineBreak.rows(list.slice(start, count), width, metrics)
            .map(row => ({ from: start + row.from, to: start + row.to }));
        const keep = window + 1;
        if (rows.length > keep) {
            dropped += rows.length - keep;
            rows = rows.slice(rows.length - keep);
            start = rows[0].from;
        }
        lines = rows.map(row => ({ from: row.from, head: list.slice(row.from, row.to - 1).join(" "), last: list[row.to - 1] }));
        // A new line lifts the lines above it; a caption that starts over
        // lifts nothing.
        if (before > 0 && lineCount > before) {
            lift = lineBox;
            rise.restart();
        }
    }

    onListChanged: {
        const drawn = held.slice(0, Math.min(held.length, Math.floor(progress)));
        held = list;
        reveal.stop();
        if (!extendsDrawn(drawn, list)) {
            rise.stop();
            lift = 0;
            lines = [];
            dropped = 0;
            start = 0;
            progress = 0;
        }
        relayout();
        reveal.to = list.length;
        reveal.duration = Math.max(0, list.length - progress) * look.words.step;
        reveal.start();
    }
    onCountChanged: {
        relayout();
        if (count === 0) return;
        newest = 0;
        fade.restart();
    }
    onWidthChanged: relayout()

    NumberAnimation { id: reveal; target: root; property: "progress" }
    NumberAnimation { id: fade; target: root; property: "newest"; from: 0; to: 1; duration: root.look.words.fade }
    NumberAnimation { id: rise; target: root; property: "lift"; to: 0; duration: root.look.words.lift }

    // The body role's font and line box, which every line draws in.
    Label {
        id: probe
        visible: false
        role: "body"
    }
    TextMetrics {
        id: metrics
        font: probe.font
        onFontChanged: root.relayout()
    }
    TextMetrics {
        id: space
        font: probe.font
        text: " "
    }

    // One slot per line, the newest at the bottom, each at its own opacity.
    // The slot above the window draws the line a lift moves out, fading.
    Repeater {
        model: root.window + 1
        Item {
            id: slot
            required property int index
            readonly property var line: root.lines.length > index ? root.lines[root.lines.length - 1 - index] : null
            width: root.width
            height: root.lineBox
            y: (root.window - 1 - index) * root.lineBox + root.lift
            visible: line !== null && (index < root.window || root.lift > 0)
            layer.enabled: true
            layer.effect: TextShadow { shadow: root.look.shadow }
            opacity: index === 0 ? root.look.words.newest
                : index === root.window ? root.look.words.oldest * root.lift / Math.max(1, root.lineBox)
                : index === root.window - 1 ? root.look.words.oldest : root.look.words.middle
            Row {
                x: Math.max(0, (slot.width - width) / 2)
                spacing: space.advanceWidth
                Label {
                    visible: text !== ""
                    role: "body"
                    color: root.look.ink.words
                    textFormat: Text.PlainText
                    text: slot.line === null ? "" : slot.line.head
                }
                // A line's last word, the newest word on the bottom line,
                // which fades in on its own.
                Label {
                    role: "body"
                    color: root.look.ink.words
                    textFormat: Text.PlainText
                    opacity: slot.index === 0 ? root.newest : 1
                    text: slot.line === null ? "" : slot.line.last
                }
            }
        }
    }
}
