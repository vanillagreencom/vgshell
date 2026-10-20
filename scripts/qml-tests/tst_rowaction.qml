import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// RowAction: its text in the body role on the control's own edge, with no
// fill, no box and no underline at rest; hover draws its underline, read
// from the drawn pixels at 1x and 2x with its top a set number of clear
// rows under the descenders, and keyboard focus its ring alone; hover,
// press, focus and disabled each drawn apart from rest from their own
// tokens; Space, Return
// and Enter activate it; the danger tone draws its own colour, an unknown
// tone is logged and drawn as accent; a narrow action elides its text; a
// danger action leads with its trash mark in every theme, centred on the
// text's x-height, or with the mark its `markName` names, and an accent action
// never does; an action that removes its row's item draws the trash mark
// alone in the danger colour, in a box no smaller than a text action's,
// under a ring as clear of the mark on its right as on its left, its text
// its accessible name and its tooltip, a set reason shown in the
// tooltip's place; RowActions sets side-by-side actions `rowAction.gap`
// apart, top-aligned on one line as tall as the tallest, and gives no room
// to a hidden action or to the Repeater that makes its actions; given less
// width than its actions, it continues them on a new line once the next
// would pass that width, each line `row.height` tall with its actions
// centred in it and `stack.row` under the last, the pitch of a page's rows, and answers for its highest and lowest ink.
// An action given a `disabledReason` stays a Tab stop, takes no click,
// Space, Return or Enter, draws its content faded with no hover under a
// full-strength ring, and shows the reason on hover and on keyboard focus;
// an empty reason leaves it as it was. The tooltip waits on `tooltip.delay`
// in real time, so this proves its wiring.
Item {
    id: root
    width: 400
    height: 360

    readonly property string reason: "Only the administrator can change Tailscale."

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
    // Room for two of its three actions and not a pixel more.
    RowActions {
        id: lines
        x: 200
        y: 20
        width: one.width + Theme.rowAction.gap + two.width
        RowAction { id: one; text: "Install" }
        RowAction { id: two; text: "Update" }
        RowAction { id: three; text: "Remove"; tone: "danger" }
    }
    RowActions {
        id: made
        x: 200
        y: 220
        Repeater {
            id: maker
            model: ["Install", "Update"]
            RowAction { required property string modelData; text: modelData }
        }
    }
    RowAction { id: locked; x: 40; y: 310; text: "Add account"; disabledReason: root.reason }
    RowAction { id: signOut; x: 200; y: 120; text: "Sign out"; tone: "danger"; markName: "log-out" }
    RowAction { id: alone; x: 200; y: 170; text: "Remove Documents"; removesItem: true }
    SignalSpy { id: aloneClicks; target: alone; signalName: "clicked" }
    SignalSpy { id: clicks; target: action; signalName: "clicked" }
    SignalSpy { id: lockedClicks; target: locked; signalName: "clicked" }
    FontMetrics { id: body; font: action.contentItem.children[1].font }

    // How far the underline's top lies under the baseline, in device
    // pixels, by scale: as close as one clear device row under the
    // descenders allows, 2 device px closer than before at 2x and where it
    // was at 1x (Jarvis decision 1792451829-3591639-28142).
    readonly property var underlineTop: ({ 1: 5, 2: 8 })

    Component {
        id: scaledWindow
        Window { width: 640; height: 120; color: "black" }
    }

    TestCase {
        name: "rowaction"
        when: windowShown

        function init() {
            UnitTheme.reset();
            clicks.clear();
            lockedClicks.clear();
            aloneClicks.clear();
            alone.disabledReason = "";
            alone.focus = false;
            locked.disabledReason = Qt.binding(() => root.reason);
            locked.focus = false;
            action.focus = false;
            action.focusPreview = false;
            mouseMove(root, 0, root.height - 1);
            tryCompare(action, "hovered", false);
        }

        function mark(control) { return control.contentItem.children[0]; }
        function label(control) { return control.contentItem.children[1]; }
        function underline(control) { return control.contentItem.children[2]; }
        function ring(control) { return control.background.children[0].children[0]; }
        function colour(value) { return String(Qt.color(value)); }
        function reasonTip(control) { return control.lock.children.map(child => child.item).find(item => item && item.objectName === "disabledReasonTip") || null; }
        function markTip(control) { return control.children.map(child => child.item).find(item => item && item.objectName === "removesItemTip") || null; }

        // The device rows from `from` to `to` that hold ink in the columns
        // [columns[0], columns[1]) of a grab on black.
        function inkRows(img, columns, from, to) {
            const rows = [];
            for (let row = from; row < Math.min(to, img.height); row++) {
                for (let col = columns[0]; col < columns[1]; col++) {
                    const c = img.pixel(col, row);
                    if (Math.max(c.r, c.g, c.b) > 0.02) {
                        rows.push(row);
                        break;
                    }
                }
            }
            return rows;
        }

        // The drawn underline, read from the window's device pixels: none
        // at rest, none under keyboard focus, which draws the ring alone,
        // and on hover `underlineTop` under the baseline, a clear row under
        // the lowest descender ink of "gypqj".
        function test_hover_draws_the_underline_at_its_top_data() {
            return [{ tag: "1x", scale: 1 }, { tag: "2x", scale: 2 }];
        }

        function test_hover_draws_the_underline_at_its_top(data) {
            const screen = Qt.application.screens[data.scale - 1];
            const window = scaledWindow.createObject(null, { screen: screen, x: screen.virtualX + 10, y: screen.virtualY + 10 });
            window.visible = true;
            const item = Qt.createQmlObject("import qs.Ui\nRowAction { x: 8; y: 8; text: \"gypqj gypqj\" }", window.contentItem);
            const text = label(item);
            const ratio = text.Screen.devicePixelRatio;
            const words = Qt.createQmlObject("import QtQuick\nTextMetrics {}", window.contentItem);
            words.font = text.font;
            words.text = "gypqj";
            const wordEnd = words.advanceWidth;
            words.text = "gypqj ";
            const spaceEnd = words.advanceWidth;
            const origin = text.mapToItem(window.contentItem, 0, 0);
            const baseline = Math.floor((origin.y + text.baselineOffset) * ratio);
            // The box's bottom, which holds the underline; the ring stands outside it.
            const below = Math.ceil((item.y + item.height) * ratio);
            const glyphs = [Math.floor(origin.x * ratio), Math.floor((origin.x + wordEnd) * ratio)];
            const space = [Math.ceil((origin.x + wordEnd) * ratio), Math.floor((origin.x + spaceEnd) * ratio)];
            verify(space[1] > space[0], "the space between the words holds a column");
            const rest = grabImage(window.contentItem);
            const descender = inkRows(rest, glyphs, baseline, below).pop();
            const restLine = inkRows(rest, space, baseline, below);
            window.requestActivate();
            tryCompare(window, "active", true);
            item.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(ring(item), "visible", true);
            // The ring's bottom edge lies under the box.
            const focusLine = inkRows(grabImage(window.contentItem), space, baseline, below);
            item.focus = false;
            mouseMove(item, item.width / 2, item.height / 2);
            tryCompare(item, "hovered", true);
            const hovered = inkRows(grabImage(window.contentItem), space, baseline, below);
            const top = (underline(item).mapToItem(window.contentItem, 0, 0).y - origin.y - text.baselineOffset) * ratio;
            mouseMove(item, item.width + 40, item.height + 40);
            window.destroy();
            compare(ratio, data.scale, "the window draws at its screen's scale");
            verify(descender > baseline, "the descenders ink under the baseline");
            compare(restLine, [], "no underline at rest");
            compare(focusLine, [], "no underline under keyboard focus");
            verify(hovered.length > 0, "the hover draws the underline");
            compare(top, root.underlineTop[data.scale], "the underline's top in device pixels under the baseline");
            verify(hovered[0] - descender - 1 >= 1, "one clear device row between the descenders and the underline: " + (hovered[0] - descender - 1));
        }

        // The opacity an item draws at: its own times every ancestor's.
        function drawnOpacity(item) {
            let out = 1;
            for (let at = item; at !== null; at = at.parent) out *= at.opacity;
            return out;
        }

        function test_rest_is_body_text_on_the_edge_with_no_underline() {
            compare(label(action).role, "body");
            compare(label(action).text, action.text);
            compare(colour(label(action).color), colour(Theme.rowAction.tone.accent.foreground));
            compare(action.leftPadding, 0);
            compare(label(action).mapToItem(action, 0, 0).x, 0, "the text starts on the control's edge");
            compare(action.implicitWidth, label(action).implicitWidth);
            compare(underline(action).visible, false, "no underline at rest");
            compare(underline(action).width, label(action).width);
            compare(underline(action).height, Theme.rowAction.underline);
            // The "p" of "up" reaches under the baseline: the underline
            // starts a clear row under the font's descent.
            verify(underline(action).y >= label(action).y + label(action).baselineOffset + body.descent + 1,
                   "the underline starts " + (underline(action).y - label(action).y - label(action).baselineOffset) + " px under the baseline, the descent is " + body.descent);
            verify(underline(action).y >= label(action).y + label(action).baselineOffset + Theme.rowAction.underlineGap);
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
            compare(underline(action).y, label(action).y + label(action).baselineOffset + 12, "the token sets the underline lower");
            fuzzyCompare(label(action).y + label(action).capCentre, action.height / 2, 0.01);
            verify(underline(action).y + Theme.rowAction.underline <= action.height, "the hover underline stays inside the box");
        }

        function test_it_draws_no_fill_and_no_box() {
            const fill = action.background;
            verify(fill.color === undefined || fill.color.a === 0, "the background paints no fill");
            verify(fill.border === undefined || fill.border.width === 0, "the background draws no box");
            compare(ring(action).visible, false);
        }

        function test_hover_moves_the_colour_and_draws_the_underline() {
            verify(colour(Theme.rowAction.tone.accent.hover) !== colour(Theme.rowAction.tone.accent.foreground), "hover differs from rest");
            compare(underline(action).visible, false);
            mouseMove(action, action.width / 2, action.height / 2);
            tryCompare(action, "hovered", true);
            compare(colour(label(action).color), colour(Theme.rowAction.tone.accent.hover));
            compare(underline(action).visible, true, "the hover draws the underline");
            compare(underline(action).height, Theme.rowAction.underline);
            mouseMove(root, 0, root.height - 1);
            tryCompare(action, "hovered", false);
            compare(underline(action).visible, false, "the underline goes on exit");
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
        // text, so it runs through no glyph: from the text's highest ink,
        // on the pixel row it draws on, to the box's bottom, which holds
        // the hover underline, and past its sides.
        function test_keyboard_focus_rings_the_text_from_outside() {
            action.forceActiveFocus(Qt.MouseFocusReason);
            compare(action.activeFocus, true);
            compare(ring(action).visible, false, "focus from a click shows no ring");
            action.focus = false;
            action.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(ring(action), "visible", true);
            const out = Theme.focusRing.offset + Theme.focusRing.width;
            const ink = Math.floor(action.inkAbove());
            verify(ink > 0, "the text's ink starts on the box's top");
            const box = ring(action).mapToItem(action, 0, 0);
            compare([box.x, box.y, ring(action).width, ring(action).height], [-out, ink - out, action.width + 2 * out, action.height - ink + 2 * out]);
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

        // The mark centres on the text's x-height centre, read from the
        // drawn text's baseline and the font's x-height, within half a
        // pixel and on a whole pixel; the same reading rejects the capital
        // centre the box keeps.
        function test_the_danger_mark_centres_on_the_x_height() {
            const xCentre = label(danger).y + label(danger).baselineOffset - body.xHeight / 2;
            const capCentre = label(danger).y + label(danger).baselineOffset - body.capitalHeight / 2;
            const off = (top, centre) => Math.abs(top + mark(danger).height / 2 - centre);
            verify(off(mark(danger).y, xCentre) <= 0.5, "the mark is " + off(mark(danger).y, xCentre) + " px off the x-height centre");
            compare(mark(danger).y, Math.round(mark(danger).y), "the mark sits on a whole pixel");
            fuzzyCompare(capCentre, danger.height / 2, 0.01);
            verify(off(Math.round(danger.height / 2 - mark(danger).height / 2), xCentre) > 0.5, "control: the capital centre reads as level");
        }

        // A danger action that removes nothing leads with the mark its
        // icon names, in the place and colour of the trash mark.
        function test_a_danger_action_leads_with_its_own_mark() {
            compare(mark(signOut).visible, true);
            compare(mark(signOut).name, "log-out");
            compare(mark(danger).name, "trash", "a danger action with no icon keeps the trash mark");
            compare([mark(signOut).x, mark(signOut).y], [mark(danger).x, mark(danger).y]);
            compare(label(signOut).visible, true);
            compare(label(signOut).text, "Sign out");
            compare(label(signOut).x, mark(signOut).width + Theme.rowAction.iconGap);
            compare(colour(mark(signOut).color), colour(Theme.rowAction.tone.danger.foreground));
            mouseMove(signOut, signOut.width / 2, signOut.height / 2);
            tryCompare(signOut, "hovered", true);
            compare(underline(signOut).visible, true, "a marked action underlines its text on hover");
            mouseMove(root, 0, root.height - 1);
            tryCompare(signOut, "hovered", false);
        }

        // The mark alone: the trash mark in the danger colour with no text
        // or underline, in a square as tall as a text action's box, its
        // ink on the control's edge and level with the mark a text action
        // leads with, so it keeps the value column the other actions share.
        function test_an_action_that_removes_its_item_draws_the_trash_mark_alone() {
            compare(mark(alone).visible, true);
            compare(mark(alone).name, "trash");
            compare(label(alone).visible, false, "the text does not draw");
            mouseMove(alone, alone.width / 2, alone.height / 2);
            tryCompare(alone, "hovered", true);
            compare(underline(alone).visible, false, "the underline does not draw, even on hover");
            mouseMove(root, 0, root.height - 1);
            tryCompare(alone, "hovered", false);
            compare(colour(mark(alone).color), colour(Theme.rowAction.tone.danger.foreground));
            compare(alone.height, danger.height, "as tall as a text action's box");
            compare(alone.width, alone.height, "as wide as it is tall");
            verify(alone.width < label(alone).implicitWidth, "the box holds the mark, not the text");
            compare(mark(alone).mapToItem(alone, 0, 0).x, mark(danger).mapToItem(danger, 0, 0).x, "the mark starts where a leading mark does");
            compare(mark(alone).x, 0, "on the control's edge");
            compare(mark(alone).y, mark(danger).y, "level with a text action's mark");
            compare(alone.Accessible.name, alone.text);
            compare(alone.inkAbove(), mark(alone).y);
            compare(alone.inkBelow(), alone.height - mark(alone).y - mark(alone).height);
            const inkEnd = mark(alone).mapToItem(alone, 0, 0).x + mark(alone).painted[2];
            compare(alone.glyphEnd, alone.width - inkEnd, "glyphEnd reaches the lone mark's ink from the right edge");
            verify(alone.glyphEnd > 0, "the square reaches past the mark's ink");
            compare(danger.glyphEnd, 0, "an action with text reports 0");
        }

        function test_the_mark_alone_takes_the_danger_hover_and_press() {
            mouseMove(alone, alone.width / 2, alone.height / 2);
            tryCompare(alone, "hovered", true);
            compare(colour(mark(alone).color), colour(Theme.rowAction.tone.danger.hover));
            mousePress(alone, alone.width / 2, alone.height / 2);
            tryCompare(mark(alone), "color", Qt.color(Theme.rowAction.tone.danger.pressed));
            mouseRelease(alone, alone.width / 2, alone.height / 2);
            compare(aloneClicks.count, 1);
            // The box's corner, off the mark's ink, takes the click too.
            mouseClick(alone, 1, 1);
            compare(aloneClicks.count, 2);
        }

        // The ring holds the mark's column, as tall as the box, so it
        // stands as far from the trash's ink on the right as on the left;
        // a ring on the square box stands further on the right.
        function test_the_mark_alone_rings_its_mark() {
            alone.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(ring(alone), "visible", true);
            const out = Theme.focusRing.offset + Theme.focusRing.width;
            const box = ring(alone).mapToItem(alone, 0, 0);
            const at = mark(alone).mapToItem(alone, 0, 0);
            compare([box.x, box.y, ring(alone).width, ring(alone).height], [at.x - out, -out, mark(alone).width + 2 * out, alone.height + 2 * out]);
            const left = at.x + mark(alone).painted[0] - box.x;
            const right = box.x + ring(alone).width - (at.x + mark(alone).painted[2]);
            verify(left > out, "the ring stands clear of the ink");
            fuzzyCompare(left, right, 0.01, "the ring stands " + left + " px from the ink on the left and " + right + " px on the right");
            verify(alone.width > ring(alone).width - 2 * out, "the hit target stays the square, wider than the ring");
        }

        // Its text shows in the shared tooltip on hover and on keyboard
        // focus; a text action builds none.
        function test_the_mark_alone_names_itself_in_the_tooltip() {
            compare(UnitTheme.override({ tooltip: { delay: 200 } }), "ok");
            compare(markTip(danger), null, "a text action shows its text");
            const tip = markTip(alone);
            verify(tip !== null, "the mark alone holds its tooltip");
            compare(tip.text, alone.text);
            mouseMove(alone, alone.width / 2, alone.height / 2);
            tryCompare(tip, "opened", true);
            mouseMove(root, 0, root.height - 1);
            tryCompare(tip, "opened", false);
            alone.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(tip, "opened", true);
            alone.focus = false;
            tryCompare(tip, "opened", false);
        }

        function test_a_locked_mark_alone_shows_its_reason_in_the_tooltips_place() {
            compare(UnitTheme.override({ tooltip: { delay: 200 } }), "ok");
            alone.disabledReason = root.reason;
            compare(markTip(alone).text, "", "the text's tooltip stands down");
            const tip = reasonTip(alone);
            verify(tip !== null);
            mouseMove(alone, alone.width / 2, alone.height / 2);
            tryCompare(tip, "opened", true);
            compare(tip.text, root.reason);
            compare(markTip(alone).opened, false, "one tooltip shows");
            mouseClick(alone);
            compare(aloneClicks.count, 0, "a locked mark takes no click");
            mouseMove(root, 0, root.height - 1);
            tryCompare(tip, "opened", false);
        }

        function test_side_by_side_actions_stand_a_gap_apart() {
            compare(remove.x - (update.x + update.width), Theme.rowAction.gap);
            verify(Theme.rowAction.gap > Theme.stack.inline, "the gap is a step above the inline gap");
        }

        // One line keeps the height of its actions and sets them on its
        // top, as wide as they are with their gap.
        function test_one_line_is_as_tall_and_as_wide_as_its_actions() {
            compare([update.y, remove.y], [0, 0]);
            compare(pair.height, Math.max(update.height, remove.height));
            compare(pair.width, update.width + Theme.rowAction.gap + remove.width);
            verify(pair.height < Theme.row.height, "an action is as tall as a row, so the two cases read alike");
        }

        function test_actions_past_the_width_continue_a_row_height_down() {
            compare([one.x, one.y], [0, one.y]);
            compare(two.y, one.y, "an action that fits to the pixel leaves the first line");
            compare(two.x - (one.x + one.width), Theme.rowAction.gap, "the gap on a wrapped line");
            compare(three.x, 0, "the next line starts on the edge");
            verify(Theme.stack.row > 0, "the rows of a page stand no gap apart, so a dropped line gap reads alike");
            compare(three.y - one.y, Theme.row.height + Theme.stack.row, "the line tops");
            compare(lines.height, 2 * Theme.row.height + Theme.stack.row);
            fuzzyCompare(one.y + one.height / 2, Theme.row.height / 2, 0.5, "the first line's actions leave its centre");
            fuzzyCompare(three.y + three.height / 2, 1.5 * Theme.row.height + Theme.stack.row, 0.5, "the second line's action leaves its centre");
            compare(lines.inkAbove(), one.y + one.inkAbove());
            compare(lines.inkBelow(), lines.height - (three.y + three.height) + three.inkBelow());
            verify(three.inkBelow() > three.height - (three.contentItem.y + underline(three).y + underline(three).height), "the ink at rest ends above the underline, which draws on hover alone");
        }

        function test_given_the_room_wrapped_actions_return_to_one_line() {
            const narrow = lines.width;
            lines.width = lines.implicitWidth;
            compare([one.y, two.y, three.y], [0, 0, 0]);
            compare(three.x, two.x + two.width + Theme.rowAction.gap);
            compare(lines.height, Math.max(one.height, two.height, three.height));
            lines.width = narrow;
            compare(three.y - one.y, Theme.row.height + Theme.stack.row);
        }

        function test_a_hidden_action_takes_no_room() {
            verify(remove.x > update.width, "the second action stands on the first");
            update.visible = false;
            compare(remove.x, 0);
            compare(pair.width, remove.width);
            update.visible = true;
            compare(remove.x, update.width + Theme.rowAction.gap);
        }

        function test_the_repeater_that_makes_the_actions_takes_no_room() {
            const first = maker.itemAt(0);
            const second = maker.itemAt(1);
            compare(first.x, 0, "the first action leaves the edge");
            compare(second.x, first.width + Theme.rowAction.gap);
            compare(made.width, first.width + Theme.rowAction.gap + second.width);
            compare(made.height, Math.max(first.height, second.height));
        }

        // Tab reaches the locked action from the item before it, and the
        // reason opens on that focus, under a ring at full strength.
        function test_a_locked_action_stays_a_tab_stop_and_says_why() {
            compare(UnitTheme.override({ tooltip: { delay: 200 } }), "ok");
            locked.nextItemInFocusChain(false).forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Tab);
            compare(locked.activeFocus, true, "Tab reaches the locked action");
            compare(locked.visualFocus, true);
            const tip = reasonTip(locked);
            verify(tip !== null, "the locked action holds its reason");
            tryCompare(tip, "opened", true);
            compare(tip.text, root.reason);
            compare(locked.Accessible.description, root.reason);
            compare(ring(locked).visible, true);
            compare(drawnOpacity(ring(locked)), 1, "the ring draws at full strength");
            locked.focus = false;
            tryCompare(tip, "opened", false);
        }

        function test_a_locked_action_says_why_on_hover_and_draws_none() {
            compare(UnitTheme.override({ tooltip: { delay: 200 } }), "ok");
            const tip = reasonTip(locked);
            mouseMove(locked, locked.width / 2, locked.height / 2);
            tryCompare(tip, "opened", true);
            compare(tip.text, root.reason);
            compare(locked.hovered, false, "a locked action draws no hover");
            compare(underline(locked).visible, false, "a locked action draws no underline");
            compare(colour(label(locked).color), colour(Theme.rowAction.tone.accent.foreground));
            mouseMove(root, 0, root.height - 1);
            tryCompare(tip, "opened", false);
        }

        function test_a_locked_action_takes_no_click_or_key() {
            mouseClick(locked);
            compare(lockedClicks.count, 0, "click");
            locked.forceActiveFocus(Qt.TabFocusReason);
            for (const key of [Qt.Key_Space, Qt.Key_Return, Qt.Key_Enter]) {
                keyClick(key);
                compare(lockedClicks.count, 0, "key " + key);
            }
            compare(locked.activeFocus, true, "the keys leave the focus on the action");
        }

        // The content fades and the control does not, so its ring and its
        // reason draw at full strength.
        function test_a_locked_action_draws_faded() {
            compare(locked.opacity, 1);
            compare(locked.contentItem.opacity, Theme.opacity.disabled);
            compare(action.contentItem.opacity, 1);
        }

        function test_an_empty_reason_leaves_the_action_as_it_was() {
            compare(reasonTip(action), null);
            compare(action.Accessible.description, "");
            locked.disabledReason = "";
            compare(reasonTip(locked), null, "clearing the reason drops the tooltip");
            compare(locked.contentItem.opacity, 1);
            mouseClick(locked);
            compare(lockedClicks.count, 1);
            locked.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Space);
            compare(lockedClicks.count, 2);
        }

        function test_a_theme_change_moves_the_tokens() {
            compare(UnitTheme.override({ rowAction: { underline: 2, tone: { accent: { foreground: "#336699ff" } } } }), "ok");
            compare(colour(Theme.rowAction.tone.accent.foreground), "#336699");
            tryVerify(() => colour(label(action).color) === "#336699");
            compare(underline(action).height, 2);
        }
    }
}
