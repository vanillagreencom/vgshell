import QtQuick
import qs.Commons
import qs.Ui
import "Appearance.js" as Appearance

// Jarvis's words while its voice is muted, above the orb: the newest line
// at the bottom and at most `words.lines` lines, each older line fainter.
// Words appear one each `words.step` until they catch up with `text`, the
// newest fading in over `words.fade`; a new line moves the lines up over
// `words.lift`. Each is a Qt animation that ends once the words catch up,
// never a ticking driver, and at motion scale 0 every duration is 0, so
// the text appears whole. A `text` that does not extend the words shown
// starts over. It draws only.
Item {
    id: root

    property string text: ""
    readonly property var look: Theme.appearance(Appearance.TOKENS, Appearance.LIGHT)
    readonly property var list: text.trim() === "" ? [] : text.trim().split(/\s+/)
    property real progress: 0
    readonly property int count: Math.min(list.length, Math.floor(progress))
    // The words drawn now, as plain text.
    readonly property string shown: list.slice(0, count).join(" ")
    // The newest word's opacity while it fades in.
    property real newest: 1
    property real lift: 0
    readonly property int lineCount: count === 0 ? 0 : measure.lineCount
    readonly property real lineBox: measure.lineBox
    readonly property bool settled: count === list.length && !reveal.running && !fade.running && !rise.running
    // The words of `list` the reveal last started from.
    property var held: []
    property int laidLines: 0

    implicitHeight: look.words.lines * lineBox
    visible: count > 0
    Accessible.ignored: true

    function escaped(words) {
        return words.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }
    // Styled text draws a `#aarrggbb` font colour at its alpha, which is
    // how Qt.alpha's colour converts to a string (both checked with
    // qmltestrunner on Qt 6.12.0), so the newest word fades on its own.
    readonly property string markup: count === 0 ? ""
        : escaped(list.slice(0, count - 1).join(" ")) + (count > 1 ? " " : "")
          + "<font color=\"" + Qt.alpha(look.ink.words, newest) + "\">" + escaped(list[count - 1]) + "</font>"

    onListChanged: {
        const drawn = Math.min(held.length, count);
        let extends_ = drawn <= list.length;
        for (let i = 0; extends_ && i < drawn; i++) extends_ = held[i] === list[i];
        held = list;
        reveal.stop();
        if (!extends_) progress = 0;
        reveal.to = list.length;
        reveal.duration = Math.max(0, list.length - progress) * look.words.step;
        reveal.start();
    }
    onCountChanged: {
        if (count === 0) return;
        newest = 0;
        fade.restart();
    }
    // A new line lifts the lines above it; a caption that starts over
    // lifts nothing.
    onLineCountChanged: {
        const added = lineCount > laidLines && laidLines > 0;
        laidLines = lineCount;
        if (!added) return;
        lift = lineBox;
        rise.restart();
    }

    NumberAnimation { id: reveal; target: root; property: "progress" }
    NumberAnimation { id: fade; target: root; property: "newest"; from: 0; to: 1; duration: root.look.words.fade }
    NumberAnimation { id: rise; target: root; property: "lift"; to: 0; duration: root.look.words.lift }

    // Lays the shown words out once, for their line count.
    Label {
        id: measure
        visible: false
        width: root.width
        role: "body"
        text: root.markup
        textFormat: Text.StyledText
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
    }

    // One window per line, the newest at the bottom: each clips the whole
    // text to its own line, at its own opacity.
    Repeater {
        model: root.look.words.lines
        Item {
            required property int index
            readonly property int last: root.look.words.lines - 1
            width: root.width
            height: root.lineBox
            y: (last - index) * root.lineBox
            clip: true
            visible: root.lineCount > index
            opacity: index === 0 ? root.look.words.newest : index === last ? root.look.words.oldest : root.look.words.middle
            Label {
                width: root.width
                y: (index - root.lineCount + 1) * root.lineBox + root.lift
                role: "body"
                color: root.look.ink.words
                text: root.markup
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
