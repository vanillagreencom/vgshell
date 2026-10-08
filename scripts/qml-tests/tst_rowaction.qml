import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// RowAction: its text in the body role on the control's own edge, with no
// fill and no box, over an underline at rest; hover, press, focus and
// disabled each drawn apart from rest from their own tokens; Space, Return
// and Enter activate it; the danger tone draws its own colour, an unknown
// tone is logged and drawn as accent; a narrow action elides its text; a
// danger action leads with its trash mark in every theme, and an accent
// action never does; RowActions sets side-by-side actions `rowAction.gap`
// apart.
Item {
    id: root
    width: 400
    height: 300

    RowAction { id: action; x: 40; y: 20; text: "Set up local voice" }
    RowAction { id: danger; x: 40; y: 70; text: "Remove"; tone: "danger" }
    RowAction { id: off; x: 40; y: 120; text: "Off"; enabled: false }
    RowAction { id: narrow; x: 40; y: 170; width: 40; text: "An action far wider than its control" }
    RowActions {
        id: pair
        x: 40
        y: 220
        RowAction { id: update; text: "Update" }
        RowAction { id: remove; text: "Remove"; tone: "danger" }
    }
    SignalSpy { id: clicks; target: action; signalName: "clicked" }

    TestCase {
        name: "rowaction"
        when: windowShown

        function init() {
            UnitTheme.reset();
            clicks.clear();
            action.focus = false;
            action.focusPreview = false;
            mouseMove(root, 0, root.height - 1);
            tryCompare(action, "hovered", false);
        }

        function mark(control) { return control.contentItem.children[0]; }
        function label(control) { return control.contentItem.children[1]; }
        function underline(control) { return control.contentItem.children[2]; }
        function ring(control) { return control.background.children[0]; }
        function colour(value) { return String(Qt.color(value)); }

        function test_rest_is_body_text_on_the_edge_over_an_underline() {
            compare(label(action).role, "body");
            compare(label(action).text, action.text);
            compare(colour(label(action).color), colour(Theme.rowAction.tone.accent.foreground));
            compare(action.leftPadding, 0);
            compare(label(action).mapToItem(action, 0, 0).x, 0, "the text starts on the control's edge");
            compare(action.implicitWidth, label(action).implicitWidth);
            compare(underline(action).visible, true);
            compare(underline(action).width, label(action).width);
            compare(underline(action).height, Theme.rowAction.underline);
            verify(underline(action).height > 0, "the underline shows at rest");
            compare(underline(action).y, label(action).y + label(action).baselineOffset + Theme.rowAction.underlineGap);
            compare(colour(underline(action).color), colour(Theme.rowAction.tone.accent.foreground));
            compare(action.Accessible.name, action.text);
        }

        // The box centres on the text's capitals, so a row that centres the
        // action beside a chip sets the two level, and it holds the hover
        // underline, so a hover moves nothing.
        function test_the_box_centres_on_the_capitals() {
            fuzzyCompare(label(action).y + label(action).capCentre, action.height / 2, 0.01);
            const height = action.height;
            mouseMove(action, action.width / 2, action.height / 2);
            tryCompare(action, "hovered", true);
            compare(action.height, height, "a hover keeps the box");
            verify(underline(action).y + underline(action).height <= action.height, "the hover underline stays inside the box");
        }

        // A theme that sets the underline well under the text grows the
        // box below the capitals, and the box grows above them to match,
        // so the capitals stay on its centre.
        function test_a_low_underline_keeps_the_capitals_centred() {
            compare(UnitTheme.override({ rowAction: { underlineGap: 12 } }), "ok");
            tryVerify(() => label(action).y >= 4, 1000, "the text moves down to balance the underline: y=" + label(action).y);
            fuzzyCompare(label(action).y + label(action).capCentre, action.height / 2, 0.01);
            verify(underline(action).y + Theme.rowAction.underlineHover <= action.height, "the hover underline stays inside the box");
        }

        function test_it_draws_no_fill_and_no_box() {
            const fill = action.background;
            verify(fill.color === undefined || fill.color.a === 0, "the background paints no fill");
            verify(fill.border === undefined || fill.border.width === 0, "the background draws no box");
            compare(ring(action).visible, false);
        }

        function test_hover_moves_the_colour_and_thickens_the_underline() {
            verify(colour(Theme.rowAction.tone.accent.hover) !== colour(Theme.rowAction.tone.accent.foreground), "hover differs from rest");
            verify(Theme.rowAction.underlineHover > Theme.rowAction.underline, "the hover underline is thicker");
            mouseMove(action, action.width / 2, action.height / 2);
            tryCompare(action, "hovered", true);
            compare(colour(label(action).color), colour(Theme.rowAction.tone.accent.hover));
            compare(underline(action).height, Theme.rowAction.underlineHover);
            mouseMove(root, 0, root.height - 1);
            tryCompare(action, "hovered", false);
            compare(underline(action).height, Theme.rowAction.underline);
        }

        function test_press_draws_its_own_colour() {
            verify(colour(Theme.rowAction.tone.accent.pressed) !== colour(Theme.rowAction.tone.accent.foreground), "pressed differs from rest");
            verify(colour(Theme.rowAction.tone.accent.pressed) !== colour(Theme.rowAction.tone.accent.hover), "pressed differs from hover");
            mousePress(action, action.width / 2, action.height / 2);
            tryCompare(label(action), "color", Qt.color(Theme.rowAction.tone.accent.pressed));
            mouseRelease(action, action.width / 2, action.height / 2);
            compare(clicks.count, 1);
        }

        function test_disabled_fades_once() {
            fuzzyCompare(off.opacity, Theme.opacity.disabled, 0.001);
            compare(action.opacity, 1);
        }

        // The ring shows for keyboard focus alone and stands outside the
        // text, so it runs through no glyph.
        function test_keyboard_focus_rings_the_text_from_outside() {
            action.forceActiveFocus(Qt.MouseFocusReason);
            compare(action.activeFocus, true);
            compare(ring(action).visible, false, "focus from a click shows no ring");
            action.focus = false;
            action.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(ring(action), "visible", true);
            const out = Theme.focusRing.offset + Theme.focusRing.width;
            const box = ring(action).mapToItem(action, 0, 0);
            compare([box.x, box.y, ring(action).width, ring(action).height], [-out, -out, action.width + 2 * out, action.height + 2 * out]);
            action.focus = false;
            tryCompare(ring(action), "visible", false);
            action.focusPreview = true;
            compare(ring(action).visible, true);
        }

        function test_space_return_and_enter_activate() {
            action.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Space);
            compare(clicks.count, 1);
            keyClick(Qt.Key_Return);
            compare(clicks.count, 2);
            keyClick(Qt.Key_Enter);
            compare(clicks.count, 3);
        }

        function test_the_danger_tone_draws_its_own_colour() {
            verify(colour(Theme.rowAction.tone.danger.foreground) !== colour(Theme.rowAction.tone.accent.foreground));
            compare(colour(label(danger).color), colour(Theme.rowAction.tone.danger.foreground));
            compare(colour(underline(danger).color), colour(Theme.rowAction.tone.danger.foreground));
        }

        // expected-log: RowAction: no tone named "loud" -- the test names an unknown tone on purpose
        function test_an_unknown_tone_is_logged_and_drawn_as_accent() {
            const made = Qt.createQmlObject("import qs.Ui\nRowAction { tone: \"loud\"; text: \"x\" }", root);
            compare(colour(made.foreground), colour(Theme.rowAction.tone.accent.foreground));
            made.destroy();
        }

        function test_a_narrow_action_elides_its_text() {
            compare(label(narrow).width, narrow.width);
            compare(underline(narrow).width, narrow.width);
            verify(label(narrow).truncated, "the text elides");
        }

        // A danger action leads with its mark on the control's edge, in
        // the danger colour, its text and underline after it; an accent
        // action never draws it; a theme whose danger and accent differ
        // keeps the mark.
        function test_a_danger_action_leads_with_its_mark() {
            compare(mark(danger).visible, true);
            compare(mark(danger).name, "trash");
            compare(mark(danger).x, 0, "the mark sits on the control's edge");
            compare(label(danger).x, mark(danger).width + Theme.rowAction.iconGap);
            compare(underline(danger).x, label(danger).x, "the underline runs under the text alone");
            compare(colour(mark(danger).color), colour(Theme.rowAction.tone.danger.foreground));
            compare(mark(action).visible, false, "an accent action draws no mark");
            compare(label(action).x, 0);
            compare(UnitTheme.override({ palette: { accent: "#205ea6", danger: "#b64339" } }), "ok");
            tryVerify(() => colour(mark(danger).color) === colour("#b64339"));
            compare(mark(danger).visible, true, "the mark stays where danger and accent differ");
            compare(mark(action).visible, false);
        }

        function test_side_by_side_actions_stand_a_gap_apart() {
            compare(remove.x - (update.x + update.width), Theme.rowAction.gap);
            verify(Theme.rowAction.gap > Theme.stack.inline, "the gap is a step above the inline gap");
        }

        function test_a_theme_change_moves_the_tokens() {
            compare(UnitTheme.override({ rowAction: { underline: 2, tone: { accent: { foreground: "#336699ff" } } } }), "ok");
            compare(colour(Theme.rowAction.tone.accent.foreground), "#336699");
            tryVerify(() => colour(label(action).color) === "#336699");
            compare(underline(action).height, 2);
        }
    }
}
