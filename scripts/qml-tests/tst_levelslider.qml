import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// LevelSlider: the button, the slider and the readout sit `stack.inline`
// apart in one row, the slider taking the width the others leave; the
// slider follows `value` while it is not held and never while a drag holds
// it; the arrows step it by `stepSize` and hand each new share to `moved`;
// a drag reports `began`; the readout reads the value as a percentage
// unless the caller names it, a value above 1 as it is, in a column as wide
// as "100%"; the button and the slider are each a tab stop.
Item {
    id: root
    width: 600
    height: 200

    LevelSlider { id: level; width: 400; iconName: "volume-2"; buttonLabel: "Mute output"; value: 0.45; stepSize: 0.05 }
    LevelSlider { id: named; y: 100; width: 400; iconName: "volume-x"; buttonLabel: "Unmute output"; value: 0.3; text: "Muted" }
    SignalSpy { id: moves; target: level; signalName: "moved" }
    SignalSpy { id: begins; target: level; signalName: "began" }
    SignalSpy { id: clicks; target: level; signalName: "buttonClicked" }

    TestCase {
        name: "levelslider"
        when: windowShown

        function button(item) { return item.children[0]; }
        function readout(item) { return item.children[2]; }

        function init() {
            UnitTheme.reset();
            level.value = 0.45;
            level.slider.value = 0.45;
            moves.clear();
            begins.clear();
            clicks.clear();
        }

        function test_the_parts_sit_in_one_row() {
            const b = button(level), s = level.slider, r = readout(level);
            compare(s.x, b.x + b.width + Theme.stack.inline);
            compare(r.x, s.x + s.width + Theme.stack.inline);
            compare(r.x + r.width, level.width, "the readout ends on the row's end edge");
            compare(r.width, r.children[0].implicitWidth, "the readout is as wide as 100%");
            compare(b.label, "Mute output");
            compare(b.iconName, "volume-2");
        }

        function test_the_slider_follows_the_value_while_not_held() {
            compare(level.slider.value, 0.45);
            level.value = 0.7;
            compare(level.slider.value, 0.7);
            mousePress(level.slider, level.slider.width / 4, level.slider.height / 2);
            compare(begins.count, 1, "a press begins a drag");
            const held = level.slider.value;
            level.value = 0.9;
            compare(level.slider.value, held, "a held slider is not pulled back");
            mouseRelease(level.slider, level.slider.width / 4, level.slider.height / 2);
            level.value = 0.6;
            compare(level.slider.value, 0.6);
        }

        function test_the_arrows_step_and_report() {
            level.slider.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Up);
            fuzzyCompare(level.slider.value, 0.5, 0.0001);
            compare(moves.count, 1);
            fuzzyCompare(moves.signalArguments[0][0], 0.5, 0.0001);
        }

        function test_the_readout_reads_the_level_or_the_callers_text() {
            compare(readout(level).text, "45%");
            level.value = 1.5;
            compare(readout(level).text, "150%", "a level above full reads as it is");
            compare(level.slider.value, 1, "the slider stands at its end");
            compare(readout(named).text, "Muted");
        }

        function test_the_button_and_the_slider_are_tab_stops() {
            mouseClick(button(level));
            compare(clicks.count, 1);
            button(level).forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Tab);
            verify(level.slider.activeFocus, "Tab moves from the button to the slider");
        }
    }
}
