import QtQuick
import qs.Ui

// Jarvis's words while its voice is muted, above the orb: the newest line
// at the bottom and at most `words.lines` lines, each older line fainter.
// Words appear one each `stepDuration` until they catch up with `text`,
// the newest fading in over `fadeDuration`; a new line moves the lines up
// over `liftDuration` while the line leaving the top fades out. Each is a Qt
// animation that ends once the words catch up, never a ticking driver, and
// at motion scale 0 every duration is 0, so the text appears whole. It
// draws only, in the values its owner hands it: the bubble hands its
// look's, the reply card under the bar J the theme's. Each line draws over
// the handed text shadow, when there is one: a 0-offset blur of the line's
// layer, which Qt draws again only while that line changes, so a lift or a
// still line redraws no blur.
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

    // How many lines show, the pace, the newest line's ink and every older
    // line's, and each line's opacity: the newest line's, the oldest shown
    // line's, and the others'.
    required property int window
    required property int stepDuration
    required property int fadeDuration
    required property int liftDuration
    required property color newestInk
    required property color olderInk
    required property real newestOpacity
    required property real middleOpacity
    required property real oldestOpacity
    // The text shadow under each line, { color, opacity, blur }, or null
    // for none.
    property var shadow: null
    property int horizontalAlignment: Text.AlignHCenter
    property string text: ""
    readonly property var list: text.trim() === "" ? [] : text.trim().split(/\s+/)
    property real progress: 0
    readonly property int count: Math.min(list.length, Math.floor(progress))
    // The words drawn now, as plain text.
    readonly property string shown: list.slice(0, count).join(" ")
    // The newest word's opacity while it fades in.
    property real newest: 1
    property real lift: 0
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
        reveal.duration = Math.max(0, list.length - progress) * stepDuration;
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
    NumberAnimation { id: fade; target: root; property: "newest"; from: 0; to: 1; duration: root.fadeDuration }
    NumberAnimation { id: rise; target: root; property: "lift"; to: 0; duration: root.liftDuration }

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
            readonly property color ink: index === 0 ? root.newestInk : root.olderInk
            layer.enabled: root.shadow !== null
            layer.effect: TextShadow { shadow: root.shadow }
            opacity: index === 0 ? root.newestOpacity
                : index === root.window ? root.oldestOpacity * root.lift / Math.max(1, root.lineBox)
                : index === root.window - 1 ? root.oldestOpacity : root.middleOpacity
            Row {
                x: root.horizontalAlignment === Text.AlignLeft ? 0 : Math.max(0, (slot.width - width) / 2)
                spacing: space.advanceWidth
                Label {
                    visible: text !== ""
                    role: "body"
                    color: slot.ink
                    textFormat: Text.PlainText
                    text: slot.line === null ? "" : slot.line.head
                }
                // A line's last word, the newest word on the bottom line,
                // which fades in on its own.
                Label {
                    role: "body"
                    color: slot.ink
                    textFormat: Text.PlainText
                    opacity: slot.index === 0 ? root.newest : 1
                    text: slot.line === null ? "" : slot.line.last
                }
            }
        }
    }
}
