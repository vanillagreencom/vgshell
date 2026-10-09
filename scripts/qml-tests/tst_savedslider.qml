import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// SavedSlider: the slider follows the shown value while it is not held; a
// drag moves the slider and its reading and saves nothing until the
// release, which saves the value once; a press that moved nothing saves
// nothing, even over a shown value past the range; a key saves each step;
// after a save the slider follows the shown value again; a range that
// arrives after the shown value takes that value; the reading is what
// `formatValue` writes, ends on the row's end edge and stands
// `field.labelGap` after the slider.
Item {
    id: root
    width: 600
    height: 200

    SavedSlider { id: saved; width: 400; from: 0; to: 32; shown: 8; formatValue: value => Math.round(value) + " px" }
    SavedSlider { id: late; y: 60; width: 400; from: 0; to: 0; shown: 12 }
    SignalSpy { id: saves; target: saved; signalName: "saved" }

    TestCase {
        name: "savedslider"
        when: windowShown

        function reading(item) { return item.children.find(child => child.role !== undefined); }
        function init() {
            UnitTheme.reset();
            saved.shown = 8;
            late.from = 0;
            late.to = 0;
            saves.clear();
        }

        function test_the_slider_follows_the_shown_value() {
            compare(saved.slider.value, 8);
            saved.shown = 20;
            compare(saved.slider.value, 20);
            compare(reading(saved).text, "20 px");
        }

        function test_a_drag_saves_once_on_release() {
            const bar = saved.slider;
            mousePress(bar, bar.width / 4, bar.height / 2);
            mouseMove(bar, bar.width / 2, bar.height / 2);
            mouseMove(bar, bar.width * 3 / 4, bar.height / 2);
            verify(bar.value > 8, "the drag moves the slider: " + bar.value);
            fuzzyCompare(bar.position, bar.value / 32, 0.000001, "the handle stands on a step while it is dragged");
            compare(reading(saved).text, Math.round(bar.value) + " px", "the reading follows the drag");
            compare(saves.count, 0, "a held slider saves nothing");
            const wanted = bar.value;
            mouseRelease(bar, bar.width * 3 / 4, bar.height / 2);
            compare(saves.count, 1);
            compare(saves.signalArguments[0][0], wanted);
            compare(bar.value, 8, "the slider stands at the shown value until the save lands");
            saved.shown = wanted;
            compare(bar.value, wanted, "and follows it again");
        }

        function test_a_press_that_moved_nothing_saves_nothing() {
            const bar = saved.slider;
            saved.shown = 16;
            mouseClick(bar, bar.width / 2, bar.height / 2);
            compare(saves.count, 0);
            // A shown value past the range stands at the range's end.
            saved.shown = 40;
            compare(bar.value, 32);
            mouseClick(bar, bar.width - 1, bar.height / 2);
            compare(saves.count, 0, "the end of the range is where the slider already stands");
        }

        // The template holds the slider through Left and Right and lets it
        // go at the key's release; Slider moves it on Up, Down, Home, End
        // and the page keys with nothing held.
        function test_a_key_saves_each_step() {
            saved.slider.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Right);
            compare(saves.count, 1);
            compare(saves.signalArguments[0][0], 9);
            compare(saved.slider.value, 8, "the slider waits for the saved value");
            keyClick(Qt.Key_End);
            compare(saves.count, 2);
            compare(saves.signalArguments[1][0], 32);
            compare(saved.slider.value, 8);
        }

        function test_a_late_range_takes_the_shown_value() {
            compare(late.slider.value, 0, "no range holds no value");
            late.to = 32;
            compare(late.slider.value, 12);
            late.from = 16;
            compare(late.slider.value, 16);
            late.from = 0;
            compare(late.slider.value, 12);
        }

        function test_the_reading_ends_the_row() {
            const bar = saved.slider, text = reading(saved);
            compare(text.x + text.width, saved.width, "the reading ends on the row's end edge");
            compare(text.x - (bar.x + bar.width), Theme.field.labelGap);
            late.to = 32;
            const short = reading(late);
            compare(short.text, "12", "a value reads as it is unless the caller writes it");
            verify(short.implicitWidth < Theme.size.control.md, "the reading is shorter than its column");
            compare(short.width, Theme.size.control.md, "a short reading keeps the column's width");
        }
    }
}
