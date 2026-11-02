import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.jarvis"

// Jarvis's words while its voice is muted: they appear a word at a time
// until they catch up with the caption, then every animation has ended;
// at most three lines draw, the newest at the bottom; a caption that does
// not extend the words starts over; motion scale 0 shows the text whole.
Item {
    id: root
    width: 400
    height: 200

    Words { id: words; width: 380 }

    TestCase {
        name: "jarvis-words"
        when: windowShown

        function init() {
            UnitTheme.reset();
            words.text = "";
        }

        function windows() {
            return words.children.filter(child => child.clip === true && child.visible);
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
            words.text = Array(40).fill("scripted reply").join(" ");
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            words.text = words.text + " end";
            tryVerify(() => words.settled && words.count === 81, 1000);
            verify(words.lineCount > words.look.words.lines, "the caption is longer than the window: " + words.lineCount);
            const shown = windows();
            compare(shown.length, words.look.words.lines);
            const bottom = shown.reduce((a, b) => a.y > b.y ? a : b);
            const label = bottom.children[0];
            compare(bottom.y + bottom.height, words.implicitHeight, "the newest line sits at the bottom");
            compare(label.y + label.height, bottom.height, "the bottom window shows the last line");
            verify(bottom.opacity > shown.reduce((a, b) => a.y < b.y ? a : b).opacity, "the oldest line is fainter");
        }

        function test_motion_scale_zero_shows_the_text_whole() {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            words.text = "Done in one";
            tryVerify(() => words.settled && words.shown === "Done in one", 100);
        }

        function test_a_caption_that_does_not_extend_starts_over() {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            words.text = "first reply here";
            tryVerify(() => words.settled, 100);
            UnitTheme.reset();
            words.text = "first reply here and more";
            verify(words.count >= 3, "an extended caption keeps its words");
            words.text = "another reply";
            verify(words.count < 2, "a new caption starts over: " + words.count);
            tryVerify(() => words.settled && words.shown === "another reply", 2000);
            words.text = "";
            compare(words.visible, false);
        }
    }
}
