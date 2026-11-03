import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.jarvis"
import "../../shell/plugins/vgs.jarvis/Appearance.js" as Appearance

// Jarvis's words while its voice is muted: they appear a word at a time
// until they catch up with the caption, then every animation has ended;
// at most three lines draw, the newest at the bottom, and only the tail
// they need is laid out; a caption that grows inside its last drawn word
// keeps its words, and one that changes an earlier word starts over;
// motion scale 0 shows the text whole; each line draws over the look's
// text shadow.
Item {
    id: root
    width: 400
    height: 200

    Words { id: words; width: 380; look: Theme.appearance(Appearance.TOKENS, Appearance.LIGHT) }

    TestCase {
        name: "jarvis-words"
        when: windowShown

        function init() {
            UnitTheme.reset();
            words.text = "";
        }

        // The drawn lines, top to bottom, each as its plain text.
        function drawn() {
            return words.children.filter(child => child.line !== undefined && child.visible)
                .sort((a, b) => a.y - b.y);
        }
        function textOf(slot) {
            return (slot.line.head === "" ? "" : slot.line.head + " ") + slot.line.last;
        }

        function test_words_catch_up_then_stand_still() {
            words.text = "On it. The balance is ready";
            verify(words.count < 6, "the words do not appear at once");
            tryVerify(() => words.count > 1 && words.count < 6, 2000, "the words appear one at a time: " + words.count);
            tryVerify(() => words.settled, 5000, "the reveal ends");
            compare(words.shown, "On it. The balance is ready");
            compare(words.newest, 1, "the newest word ends opaque");
        }

        function test_three_lines_at_most_newest_at_the_bottom() {
            const text = Array(40).fill("scripted reply").join(" ") + " end";
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            words.text = text;
            tryVerify(() => words.settled && words.count === 81, 1000);
            verify(words.lineCount > words.look.words.lines, "the caption is longer than the window: " + words.lineCount);
            verify(words.start > 0 && words.lines.length <= words.look.words.lines + 1,
                "only the tail is laid out: start=" + words.start + " lines=" + words.lines.length);
            const shown = drawn();
            compare(shown.length, words.look.words.lines);
            const bottom = shown[shown.length - 1];
            compare(bottom.y + bottom.height, words.implicitHeight, "the newest line sits at the bottom");
            verify(textOf(bottom).endsWith("end"), "the bottom line ends the caption: " + textOf(bottom));
            const tail = shown.map(textOf).join(" ");
            verify(text.endsWith(" " + tail), "the lines are the caption's last, in order: " + tail);
            verify(bottom.opacity > shown[0].opacity, "the oldest line is fainter");
        }

        // Each drawn line draws through its layer's shadow, no offset, in
        // the look's colour, opacity and blur.
        function test_each_line_draws_the_looks_shadow() {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            words.text = Array(20).fill("scripted reply").join(" ");
            tryVerify(() => words.settled, 1000);
            const shown = drawn();
            verify(shown.length > 1, "more than one line draws");
            const effects = [];
            const collect = item => { for (const child of item.children) { if (child.shadowEnabled !== undefined) effects.push(child); collect(child); } };
            collect(root);
            for (const slot of shown) {
                verify(slot.layer.enabled, "the line draws through a layer");
                const effect = effects.find(found => found.source !== null && found.source !== undefined && found.source.sourceItem === slot);
                verify(effect !== undefined, "an effect draws the line");
                compare(String(effect.shadowColor), String(Qt.color(words.look.shadow.color)));
                compare(effect.shadowOpacity, words.look.shadow.opacity);
                compare(effect.blurMax, words.look.shadow.blur);
                compare(effect.shadowHorizontalOffset, 0);
                compare(effect.shadowVerticalOffset, 0);
            }
        }

        function test_motion_scale_zero_shows_the_text_whole() {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            words.text = "Done in one";
            tryVerify(() => words.settled && words.shown === "Done in one", 100);
        }

        function test_a_caption_that_grows_inside_its_last_word_keeps_its_words() {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            words.text = "help you with that";
            tryVerify(() => words.settled && words.count === 4, 100);
            UnitTheme.reset();
            words.text = "help you with that.";
            compare(words.count, 4, "the drawn words stay");
            tryVerify(() => words.settled && words.shown === "help you with that.", 2000);
        }

        function test_a_caption_that_changes_an_earlier_word_starts_over() {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            words.text = "first reply here";
            tryVerify(() => words.settled, 100);
            UnitTheme.reset();
            words.text = "first reply here and more";
            verify(words.count >= 3, "an extended caption keeps its words");
            words.text = "another reply here today";
            verify(words.count < 2, "a new caption starts over: " + words.count);
            tryVerify(() => words.settled && words.shown === "another reply here today", 2000);
            words.text = "";
            compare(words.visible, false);
        }
    }
}
