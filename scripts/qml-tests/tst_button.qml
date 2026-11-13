import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import qs.Unit

// Button: the variant's fill and text, the hover and pressed fills, a
// click by pointer and by keyboard, the checked fill, an icon toggle that
// draws no fill or border, the disabled opacity,
// the focus ring for keyboard focus, a caller's width past the control
// maximum, an unknown variant, and a theme
// change that moves the fill and keeps the text readable. An icon
// button's tooltip opens under it, or to its right when its side says so,
// the theme's gap away.
Item {
    id: root
    width: 300
    height: 320

    Button { id: primary; text: "Publish" }
    Button { id: secondary; text: "Browse"; variant: "secondary"; y: 40 }
    ToggleButton { id: toggle; text: "Pin"; y: 80 }
    Button { id: off; text: "Off"; enabled: false; y: 120 }
    IconButton { id: iconOnly; iconName: "x"; label: "Close"; y: 160 }
    IconButton { id: focusIcon; iconName: "scan-eye"; label: "Focused"; y: 200 }
    IconButton { id: pressedIcon; iconName: "mouse-pointer-click"; label: "Pressed"; y: 230; down: true }
    IconButton { id: checkedIcon; iconName: "check"; label: "Checked"; y: 260; checkable: true; checked: true }
    IconButton { id: disabledIcon; iconName: "ban"; label: "Disabled"; y: 290; enabled: false }
    Button { id: small; text: "Small"; iconName: "check"; size: "sm"; y: 320 }
    Button { id: large; text: "Large"; iconName: "check"; size: "lg"; y: 350 }
    IconButton { id: smallIcon; iconName: "chevron-left"; label: "Back"; size: "sm"; y: 400 }
    IconButton { id: dangerIcon; iconName: "x"; label: "Close"; variant: "danger"; x: 200; y: 400 }
    IconButton { id: besideIcon; iconName: "settings"; label: "Settings"; tooltipSide: "right"; x: 200; y: 160 }
    IconButton { id: lookIcon; iconName: "mic"; label: "Look"; x: 200; y: 230; restColor: "#a3a7b3"; activeColor: "#f4f5f8"; onColor: "#33cc66"; ringColor: "#4fd1c5" }
    Button {
        id: lookButton
        text: "Look"
        x: 100; y: 440
        variant: "secondary"
        controlHeight: 26
        paddingX: 13
        radius: 13
        restFill: "#1a2b3c"
        hoverFill: "#2b3c4d"
        pressedFill: "#3c4d5e"
        borderColor: "#4d5e6f"
        textColor: "#e6e8ee"
        ringColor: "#4fd1c5"
    }
    Button { id: wide; text: "Wide"; variant: "secondary"; x: 100; y: 480; width: 180 }
    Button { id: centred; text: "Wide"; variant: "secondary"; x: 100; y: 520; width: 180; centerContent: true }
    SignalSpy { id: clicks; target: primary; signalName: "clicked" }

    TestCase {
        name: "button"
        when: windowShown

        function init() { UnitTheme.reset(); clicks.clear(); primary.focus = false; }

        function test_variant_draws_its_tokens() {
            tryCompare(primary.background, "color", Qt.color(Theme.button.variant.primary.background));
            compare(String(primary.foreground), String(Qt.color(Theme.button.variant.primary.foreground)));
            tryCompare(secondary.background, "color", Qt.color(Theme.button.variant.secondary.background));
            compare(secondary.background.color.a, 0);
            verify(secondary.background.border.width > 0, "the secondary button has an outline");
            verify(secondary.background.border.color.a > 0, "the secondary button outline is visible");
            compare(primary.height, Theme.size.control.md);
            compare(primary.background.radius, Theme.button.radius);
        }

        function test_hover_and_press_move_the_fill() {
            mouseMove(primary, primary.width / 2, primary.height / 2);
            tryCompare(primary, "hovered", true);
            tryCompare(primary.background, "color", Qt.color(Theme.button.variant.primary.hover));
            mousePress(primary, primary.width / 2, primary.height / 2);
            tryCompare(primary.background, "color", Qt.color(Theme.button.variant.primary.pressed));
            mouseRelease(primary, primary.width / 2, primary.height / 2);
            compare(clicks.count, 1);
            mouseMove(root, 0, root.height - 1);
            tryCompare(primary, "hovered", false);
        }

        function test_keyboard_activates_and_shows_the_ring() {
            primary.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(primary, "visualFocus", true);
            const ring = primary.background.children[primary.background.children.length - 1];
            compare(ring.visible, true);
            keyClick(Qt.Key_Space);
            compare(clicks.count, 1);
            keyClick(Qt.Key_Return);
            compare(clicks.count, 2);
            primary.focusPreview = true;
            primary.focus = false;
            compare(ring.visible, true);
            primary.focusPreview = false;
            primary.focus = false;
            tryCompare(ring, "visible", false);
        }

        // The ring draws on the button's own edge, its box and corner the
        // background's, so no second border shows outside the control. On
        // a primary button's accent fill, which the focus colour meets
        // below 3:1, it draws in white or black, whichever contrasts more
        // with the fill, focusRing.offset inside the edge so the fill
        // shows on both sides; a secondary button paints no fill, so its
        // ring keeps focusRing.color on the edge.
        function test_the_ring_draws_on_the_control_edge_in_a_colour_its_fill_shows() {
            const contrast = Theme.contrastOf(primary.background.color);
            verify(String(Qt.color(contrast)) !== String(Qt.color(Theme.focusRing.color)), "the primary case draws apart from the focus colour");
            const cases = [
                { button: primary, color: contrast, inset: Theme.focusRing.offset },
                { button: secondary, color: Theme.focusRing.color, inset: 0 }
            ];
            for (const c of cases) {
                const fill = c.button.background;
                const ring = fill.children[fill.children.length - 1];
                compare(ring.visible, false, c.button.text + " without focus");
                c.button.forceActiveFocus(Qt.MouseFocusReason);
                compare(c.button.activeFocus, true);
                compare(ring.visible, false, c.button.text + " with focus from a click");
                c.button.focus = false;
                c.button.forceActiveFocus(Qt.TabFocusReason);
                tryCompare(ring, "visible", true);
                const i = c.inset;
                compare([ring.x, ring.y, ring.width, ring.height], [i, i, fill.width - 2 * i, fill.height - 2 * i], c.button.text + " ring box");
                compare(ring.radius, fill.radius === 0 ? 0 : Math.max(0, fill.radius - i), c.button.text + " ring corner");
                compare(String(ring.border.color), String(Qt.color(c.color)), c.button.text + " ring colour");
                c.button.focus = false;
                tryCompare(ring, "visible", false);
            }
        }

        function test_checkable_draws_the_checked_fill() {
            compare(toggle.checked, false);
            mouseClick(toggle);
            compare(toggle.checked, true);
            tryCompare(toggle.background, "color", Qt.color(Theme.button.checked.background));
            mouseClick(toggle);
            compare(toggle.checked, false);
        }

        // Each size draws its own height, padding, gap and icon, Radix
        // Themes' button sizes 1, 2 and 3 on the 4 px unit.
        function test_each_size_draws_its_rhythm_data() {
            return [
                { tag: "sm", height: 24, pad: 8, gap: 4, icon: 14 },
                { tag: "md", height: 32, pad: 12, gap: 8, icon: 16 },
                { tag: "lg", height: 40, pad: 16, gap: 12, icon: 16 }
            ];
        }
        function test_each_size_draws_its_rhythm(data) {
            const button = data.tag === "sm" ? small : data.tag === "lg" ? large : Qt.createQmlObject("import qs.Ui\nButton { text: \"Medium\"; iconName: \"check\" }", root);
            tryCompare(button, "height", data.height);
            compare(button.leftPadding, data.pad);
            compare(button.rightPadding, data.pad);
            const row = button.contentItem;
            compare(row.children[0].size, data.icon);
            tryVerify(() => row.children[1].x - (row.children[0].x + row.children[0].width) === data.gap, 1000, "gap " + (row.children[1].x - row.children[0].width));
            if (data.tag === "md") button.destroy();
        }

        function test_checked_button_shows_hover_and_press() {
            mouseClick(toggle);
            compare(toggle.checked, true);
            mouseMove(toggle, toggle.width / 2, toggle.height / 2);
            tryCompare(toggle.background, "color", Qt.color(Theme.button.checked.hover));
            mousePress(toggle, toggle.width / 2, toggle.height / 2);
            tryCompare(toggle.background, "color", Qt.color(Theme.button.checked.pressed));
            mouseRelease(toggle, toggle.width / 2, toggle.height / 2);
            compare(toggle.checked, false);
            mouseMove(root, 0, root.height - 1);
        }

        // The ring follows the button's own corner under a rounded theme,
        // inset with the primary button's contrast ring, and the side
        // padding grows until the label clears the round end.
        function test_rounded_button_clears_its_corner_and_rings_it() {
            compare(UnitTheme.override({ button: { radius: 4096 } }), "ok");
            const want = Inset.controlPadding(Theme.button.size.sm.paddingX, 4096, small.height, small.implicitContentHeight, Theme.space.xs);
            verify(want > Theme.button.size.sm.paddingX, "the sm pill's label needs more than its pad: " + want);
            tryCompare(small, "leftPadding", want);
            const ring = small.background.children[small.background.children.length - 1];
            compare(ring.radius, 4096 - Theme.focusRing.offset);
        }

        // An icon button's glyph insets reach the ink: chevron-left's ink
        // starts 9 of 24 units in, less half the stroke.
        function test_icon_button_reads_its_glyph_insets() {
            compare(smallIcon.contentItem.size, Theme.icon.size.sm);
            compare(smallIcon.leftPadding, Math.floor((Theme.size.control.sm - Theme.icon.size.sm) / 2));
            fuzzyCompare(smallIcon.glyphStart, smallIcon.leftPadding + 9 * Theme.icon.size.sm / 24 - Theme.icon.stroke / 2, 0.01);
            fuzzyCompare(smallIcon.glyphEnd, smallIcon.rightPadding + smallIcon.contentItem.size - (15 * Theme.icon.size.sm / 24 + Theme.icon.stroke / 2), 0.01);
        }

        function test_disabled_fades() {
            fuzzyCompare(off.opacity, Theme.opacity.disabled, 0.001);
            compare(primary.opacity, 1);
        }

        // expected-log: Button: no variant named "loud" -- the test names an unknown variant on purpose
        function test_unknown_variant_is_logged_and_drawn_primary() {
            const button = Qt.createQmlObject("import qs.Ui\nButton { variant: \"loud\"; text: \"x\" }", root);
            compare(String(button.fill), String(Qt.color(Theme.button.variant.primary.background)));
            button.destroy();
        }

        // expected-log: IconButton: label is required, icon="x" -- the test builds an icon button with no label on purpose
        function test_icon_button_is_square_and_named() {
            compare(iconOnly.width, iconOnly.height);
            fuzzyCompare(iconOnly.contentItem.y, (iconOnly.height - iconOnly.contentItem.height) / 2, 1);
            compare(iconOnly.Accessible.name, "Close");
            const unnamed = Qt.createQmlObject("import qs.Ui\nIconButton { iconName: \"x\" }", root);
            unnamed.destroy();
        }

        // A ghost icon rests in the muted text colour, opaque, and takes its
        // foreground on hover, focus, press or checked; a disabled button
        // fades once, on the whole control.
        function test_icon_button_colour_states() {
            const rest = String(Qt.color(Theme.color.textMuted));
            const full = button => String(Qt.color(button.foreground));
            compare(String(iconOnly.contentItem.color), rest);
            compare(iconOnly.contentItem.opacity, 1, "the resting icon is opaque");
            compare(String(dangerIcon.contentItem.color), full(dangerIcon), "a filled variant's icon rests in its foreground");
            verify(rest !== full(iconOnly), "rest and foreground differ");
            mouseMove(root, root.width - 1, root.height - 1);
            focusIcon.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(focusIcon, "visualFocus", true);
            tryVerify(() => String(focusIcon.contentItem.color) === full(focusIcon));
            focusIcon.focus = false;
            tryVerify(() => String(focusIcon.contentItem.color) === rest);
            tryVerify(() => String(pressedIcon.contentItem.color) === full(pressedIcon));
            compare(pressedIcon.contentItem.opacity, Theme.opacity.disabled);
            pressedIcon.down = false;
            tryVerify(() => String(pressedIcon.contentItem.color) === rest);
            tryVerify(() => String(checkedIcon.contentItem.color) === full(checkedIcon));
            checkedIcon.checked = false;
            tryVerify(() => String(checkedIcon.contentItem.color) === rest);
            iconOnly.tone = "warning";
            tryCompare(iconOnly.contentItem, "color", Qt.color(Theme.color.warning));
            iconOnly.tone = "accent";
            tryCompare(iconOnly.contentItem, "color", Qt.color(Theme.color.accent));
            iconOnly.tone = "";
            mouseMove(iconOnly, iconOnly.width / 2, iconOnly.height / 2);
            tryVerify(() => String(iconOnly.contentItem.color) === full(iconOnly));
            tryCompare(iconOnly.background, "color", Qt.color(Theme.button.variant.ghost.background));
            compare(iconOnly.background.color.a, 0, "hover draws no fill");
            mouseMove(root, 0, root.height - 1);
            tryVerify(() => String(iconOnly.contentItem.color) === rest);
            mouseMove(root, root.width - 1, 1);
            tryCompare(disabledIcon, "hovered", false);
            compare(disabledIcon.opacity, Theme.opacity.disabled);
            compare(disabledIcon.contentItem.opacity, 1);
            compare(String(disabledIcon.contentItem.color), full(disabledIcon), "a disabled icon fades once, with its control");
            compare(UnitTheme.override({ color: { textMuted: "#336699ff" } }), "ok");
            iconOnly.focus = false;
            mouseMove(root, 0, root.height - 1);
            tryVerify(() => String(iconOnly.contentItem.color) === String(Qt.color(Theme.color.textMuted)));
        }

        // An icon toggle draws no fill and no border in any state: on at
        // rest, under the pointer, under keyboard focus and pressed. Its
        // glyph is the accent, or its tone's colour when a tone is set.
        function test_checked_icon_button_draws_no_fill_or_border() {
            const bare = state => {
                compare(checkedIcon.background.color.a, 0, state + ": no fill");
                verify(checkedIcon.background.border.width === 0 || checkedIcon.background.border.color.a === 0, state + ": no border");
            };
            const glyph = (want, state) => tryVerify(() => String(checkedIcon.contentItem.color) === String(Qt.color(want)), 1000, state + ": glyph " + checkedIcon.contentItem.color);
            checkedIcon.checked = true;
            mouseMove(root, root.width - 1, root.height - 1);
            glyph(Theme.color.accent, "rest");
            bare("rest");
            mouseMove(checkedIcon, checkedIcon.width / 2, checkedIcon.height / 2);
            tryCompare(checkedIcon, "hovered", true);
            glyph(Theme.color.accent, "hover");
            bare("hover");
            mousePress(checkedIcon, checkedIcon.width / 2, checkedIcon.height / 2);
            tryCompare(checkedIcon, "down", true);
            bare("pressed");
            mouseRelease(checkedIcon, checkedIcon.width / 2, checkedIcon.height / 2);
            compare(checkedIcon.checked, false, "a click turns the toggle off");
            checkedIcon.checked = true;
            mouseMove(root, root.width - 1, root.height - 1);
            checkedIcon.focus = false;
            checkedIcon.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(checkedIcon, "visualFocus", true);
            bare("focus");
            checkedIcon.focus = false;
            checkedIcon.tone = "warning";
            glyph(Theme.color.warning, "warning tone");
            bare("warning tone");
            checkedIcon.tone = "";
        }

        // A surface that owns its look hands the button its height, side
        // padding, corner, fills, border, label ink and ring colour; the
        // variant's and size's tokens draw none of them.
        function test_button_takes_a_looks_form() {
            const label = lookButton.contentItem.children.find(child => child.role === "button");
            const ring = lookButton.background.children.find(child => child.ringColor !== undefined);
            const same = (actual, want, what) => compare(String(actual), String(Qt.color(want)), what);
            for (const [want, token] of [["#1a2b3c", lookButton.tokens.background], ["#2b3c4d", lookButton.tokens.hover],
                                         ["#3c4d5e", lookButton.tokens.pressed], ["#4d5e6f", lookButton.tokens.border],
                                         ["#e6e8ee", lookButton.tokens.foreground],
                                         ["#4fd1c5", Theme.focusRing.color]])
                verify(String(Qt.color(want)) !== String(Qt.color(token)), "the look colour " + want + " differs from the token it replaces");
            for (const [want, token] of [[26, Theme.size.control.sm], [26, Theme.size.control.md], [13, Theme.button.radius], [13, lookButton.sizeTokens.paddingX]])
                verify(want !== token, "the look metric " + want + " differs from the token it replaces");
            mouseMove(root, root.width - 1, root.height - 1);
            tryCompare(lookButton, "hovered", false);
            compare(lookButton.height, 26);
            compare(lookButton.background.radius, 13);
            compare(lookButton.leftPadding, 13);
            compare(lookButton.rightPadding, 13);
            tryVerify(() => String(lookButton.background.color) === String(Qt.color("#1a2b3c")), 1000, "rest fill " + lookButton.background.color);
            same(lookButton.background.border.color, "#4d5e6f", "border");
            same(label.color, "#e6e8ee", "rest ink");
            mouseMove(lookButton, lookButton.width / 2, lookButton.height / 2);
            tryCompare(lookButton, "hovered", true);
            tryVerify(() => String(lookButton.background.color) === String(Qt.color("#2b3c4d")), 1000, "hover fill " + lookButton.background.color);
            same(label.color, "#e6e8ee", "the pointer keeps the ink");
            mousePress(lookButton, lookButton.width / 2, lookButton.height / 2);
            tryVerify(() => String(lookButton.background.color) === String(Qt.color("#3c4d5e")), 1000, "pressed fill " + lookButton.background.color);
            mouseRelease(lookButton, lookButton.width / 2, lookButton.height / 2);
            mouseMove(root, root.width - 1, root.height - 1);
            lookButton.focus = false;
            lookButton.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(lookButton, "visualFocus", true);
            verify(ring.visible, "keyboard focus draws the ring");
            compare(String(ring.drawnColor), String(Qt.color("#4fd1c5")));
            same(label.color, "#e6e8ee", "keyboard focus keeps the rest ink");
            lookButton.focus = false;
        }

        // A button set wider than its content draws the content from its
        // side padding, as a column's header does; with `centerContent`
        // the content stands on the button's centre, on a whole pixel. A
        // button sized by its content keeps its side padding either way.
        function test_a_wide_button_centres_its_content_when_asked() {
            const labelOf = button => button.contentItem.children.find(child => child.role === "button");
            for (const button of [wide, centred])
                verify(button.width > button.implicitWidth, "the button is wider than its content needs: " + button.width + " against " + button.implicitWidth);
            compare(labelOf(wide).mapToItem(wide, 0, 0).x, wide.sidePadding, "a wide button's content starts at its side padding");
            const box = labelOf(centred).mapToItem(centred, 0, 0, labelOf(centred).width, labelOf(centred).height);
            verify(Math.abs(box.x + box.width / 2 - centred.width / 2) <= 1, "the label's middle at " + (box.x + box.width / 2) + " stands on the button's, " + centred.width / 2);
            compare(box.x, Math.floor(box.x), "the label starts on a whole pixel");
            compare(centred.leftPadding, centred.rightPadding);
            centred.width = centred.implicitWidth;
            try {
                compare(centred.leftPadding, centred.sidePadding, "a button sized by its content keeps its side padding");
            } finally {
                centred.width = 180;
            }
        }

        // A caller that binds a button's width owns that allocation, as
        // Updates' Update everything fills its footer: the button follows
        // its row narrower than the control maximum and past it.
        function test_a_stretched_button_follows_its_row() {
            const row = createTemporaryQmlObject("import QtQuick; Item { height: 40 }", root);
            const button = createTemporaryQmlObject("import qs.Ui; Button { text: 'Update everything'; width: parent.width }", row);
            for (const width of [Theme.control.minWidth + 120, 2 * Theme.control.maxWidth]) {
                row.width = width;
                // Process any Qt.callLater allocation before reading:
                // https://doc.qt.io/qt-6/qml-qttest-testcase.html#wait-method
                wait(0);
                compare(button.width, width);
            }
        }

        // A surface that owns its look hands the glyph its rest, active and
        // on colours and the ring its colour; the theme's tokens draw none.
        function test_icon_button_takes_a_looks_colours() {
            const glyph = (want, state) => tryVerify(() => String(lookIcon.contentItem.color) === String(Qt.color(want)), 1000, state + ": glyph " + lookIcon.contentItem.color);
            const ring = lookIcon.background.children.find(child => child.ringColor !== undefined);
            verify(ring !== undefined, "the icon button holds its focus ring");
            for (const want of ["#a3a7b3", "#f4f5f8", "#33cc66", "#4fd1c5"])
                for (const token of [Theme.color.textMuted, lookIcon.tokens.foreground, Theme.button.checked.foreground, Theme.focusRing.color])
                    verify(String(Qt.color(want)) !== String(Qt.color(token)), "the look colour " + want + " differs from the token it replaces");
            mouseMove(root, root.width - 1, root.height - 1);
            glyph("#a3a7b3", "rest");
            mouseMove(lookIcon, lookIcon.width / 2, lookIcon.height / 2);
            tryCompare(lookIcon, "hovered", true);
            glyph("#f4f5f8", "hover");
            mouseMove(root, root.width - 1, root.height - 1);
            lookIcon.checked = true;
            glyph("#33cc66", "on");
            lookIcon.checked = false;
            lookIcon.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(lookIcon, "visualFocus", true);
            glyph("#f4f5f8", "focus");
            verify(ring.visible, "keyboard focus draws the ring");
            compare(String(ring.drawnColor), String(Qt.color("#4fd1c5")));
            lookIcon.focus = false;
        }

        function test_theme_change_keeps_the_text_readable() {
            compare(UnitTheme.override({ button: { variant: { primary: { background: "#ffffff" } } } }), "ok");
            tryCompare(primary.background, "color", Qt.color("#ffffff"));
            compare(String(primary.foreground), "#000000");
            compare(UnitTheme.override({ button: { variant: { primary: { background: "#000000" } } } }), "ok");
            compare(String(primary.foreground), "#ffffff");
        }

        function test_icon_button_tooltip_opens_on_its_side_data() {
            return [
                { tag: "below", button: iconOnly, edge: Edges.Bottom, bottom: -Theme.tooltip.gap, right: 0 },
                { tag: "right", button: besideIcon, edge: Edges.Right, bottom: 0, right: -Theme.tooltip.gap }
            ];
        }

        // The stand-in window positions nothing; the anchor it is handed is
        // what the compositor places the tooltip by.
        function test_icon_button_tooltip_opens_on_its_side(data) {
            const tip = data.button.data.find(child => child.anchorItem !== undefined && child.side !== undefined);
            verify(tip !== undefined, "the icon button holds its tooltip");
            tip.shown = true;
            const anchor = tip.tracker.popup.anchor;
            compare(anchor.item, data.button);
            compare(anchor.edges, data.edge);
            compare(anchor.gravity, data.edge);
            compare(anchor.margins.bottom, data.bottom);
            compare(anchor.margins.right, data.right);
            tip.shown = false;
        }
    }
}
