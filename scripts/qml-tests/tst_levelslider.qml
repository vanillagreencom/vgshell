import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// LevelSlider: the slider starts `stack.inline` past the button's box less
// its end padding, whatever the icon, and ends `stack.inline` before the
// readout; the
// slider follows `value` while it is not held and never while a drag holds
// it; the arrows step it by `stepSize` and hand each new share to `moved`;
// a drag reports `began`; the readout reads the value as a percentage
// unless the caller names it, a value above 1 as it is, in a column as wide
// as "100%"; the button and the slider are each a tab stop; the button's
// glyph starts on the row's start edge, and hover draws no fill.
Item {
    id: root
    width: 600
    height: 300

    Rectangle { id: ground; y: 200; width: root.width; height: 100; color: "black" }
    LevelSlider { id: flush; x: 100; y: 230; width: 400; iconName: "mic"; buttonLabel: "Mute input"; value: 0.5 }
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
            compare(s.x, b.width - b.leftPadding + Theme.stack.inline, "the slider starts after the icon column");
            compare(flush.slider.x, s.x, "sliders with different icons start together");
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

        // The first column of the band the button covers that holds ink,
        // read from the drawn frame. The glyph's left edge stands within
        // the half pixel its whole-pixel placement leaves of the row's
        // start edge, x = 100; the button's box reaches past that edge.
        function test_the_glyph_starts_on_the_row_edge() {
            wait(100);
            const b = button(flush);
            const top = b.mapToItem(ground, 0, 0).y;
            const img = grabImage(ground);
            let first = -1;
            for (let x = 0; x < flush.x + b.x + b.width && first < 0; x++)
                for (let y = Math.floor(top); y < top + b.height; y++)
                    if (img.red(x, y) > 40) { first = x; break; }
            verify(first >= 0, "the glyph drew");
            verify(Math.abs(first - flush.x) <= 1, "the glyph's ink starts at " + first + ", not on the row's edge " + flush.x);
            verify(Math.abs(b.x + b.glyphStart) <= 0.5, "the glyph's painted edge is " + (b.x + b.glyphStart) + " from the row's edge");
        }

        // Hover and press change the icon's colour and draw no fill: over
        // a black ground, every pixel of the button's box outside its icon
        // stays black.
        function test_hover_draws_no_fill() {
            const b = button(flush);
            const rest = String(b.contentItem.color);
            mouseMove(b, b.width / 2, b.height / 2);
            tryCompare(b, "hovered", true);
            tryVerify(() => String(b.contentItem.color) === String(Qt.color(b.foreground)), 1000, "hover takes the full colour");
            verify(rest !== String(b.contentItem.color), "hover changes the icon's colour");
            mousePress(b, b.width / 2, b.height / 2);
            wait(Theme.motion.duration.fast + 50);
            const box = b.mapToItem(ground, 0, 0), icon = b.contentItem.mapToItem(ground, 0, 0);
            const img = grabImage(ground);
            mouseRelease(b, b.width / 2, b.height / 2);
            let filled = 0;
            for (let x = Math.max(0, Math.round(box.x)); x < box.x + b.width; x++)
                for (let y = Math.round(box.y); y < box.y + b.height; y++) {
                    const inIcon = x >= icon.x - 1 && x <= icon.x + b.contentItem.width && y >= icon.y - 1 && y <= icon.y + b.contentItem.height;
                    if (!inIcon && (img.red(x, y) > 0 || img.green(x, y) > 0 || img.blue(x, y) > 0)) filled++;
                }
            compare(filled, 0, "the hovered, pressed button draws a fill");
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
