import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// ScrollArea, Tabs, ListItem, SectionHeader, Surface and Divider: the
// scroll area's content height follows its children and its bar shows on
// overflow, a click opens a tab, a list item highlights and clicks and
// draws its lines as plain text, a list item that takes no click draws no
// hover or press and shows no hand while its trailing action keeps its
// own, a section header draws its eyebrow inside
// its padding, a surface draws its level and logs an unknown one, and a
// divider is one hairline thick.
Item {
    id: root
    width: 400
    height: 720

    ScrollArea { id: scroll; width: 100; height: 50; Column { Repeater { model: 10; Rectangle { width: 80; height: 20; color: "transparent" } } } }
    Tabs { id: tabs; model: ["Installed", "Available"]; y: 60 }
    Tabs { id: markedTabs; model: ["Themes", "Wallpapers"]; y: 624; hoverMark: true }
    Tabs { id: handedTabs; model: ["Themes", "Wallpapers"]; y: 580; foreground: "#204060"; hover: "#406080"; active: "#6080a0"; indicatorColor: "#a0c0e0" }
    KeyHints { id: hints; y: 90; hints: [{ key: "Left/Right", text: "Move" }, { key: "Ctrl+Tab", text: "Tabs" }] }
    ListItem { id: row; text: "Plugin updates"; secondary: "1 update available"; iconName: "package"; width: 300; y: 100 }
    ListItem { id: bare; text: "Plugin updates"; secondary: "1 update available"; iconName: "package"; y: 300 }
    ListItem { id: still; text: "Started"; clickable: false; width: 300; y: 668; trailing: [ RowAction { id: stillAction; text: "Remove" } ] }
    SectionHeader { id: header; text: "Listed since"; description: "Sep 24"; width: 300; y: 150 }
    SectionHeader { id: inset; text: "Plugins"; description: "Every plugin the shell found"; leftPadding: Theme.row.paddingX; rightPadding: Theme.row.paddingX; width: 300; y: 330 }
    Column {
        id: sectionColumn
        width: 300
        y: 380
        spacing: Theme.stack.group
        Rectangle { id: beforeSection; width: parent.width; height: Theme.row.height; color: "transparent" }
        Section {
            id: section
            title: "Status"
            description: "Values from the plugin"
            headerInset: Theme.row.paddingX
            width: parent.width
            Field { label: "One"; inline: true; width: parent.width; Label { role: "item"; text: "Ready" } }
            Field { label: "Two"; inline: true; width: parent.width; Label { role: "item"; text: "Set" } }
        }
    }
    Column {
        id: firstSectionColumn
        width: 300
        y: 540
        spacing: Theme.stack.group
        Section { id: firstSection; title: "First"; width: parent.width; Field { label: "One"; inline: true; width: parent.width; Label { role: "item"; text: "Ready" } } }
    }
    FontMetrics { id: eyebrowMetrics; font: section.children[0].children[0].children[0].font }
    Surface { id: surface; level: "raised"; width: 100; height: 40; y: 220 }
    Divider { id: divider; width: 100; y: 270 }
    SignalSpy { id: clicks; target: row; signalName: "clicked" }
    SignalSpy { id: actionClicks; target: stillAction; signalName: "clicked" }
    Component { id: centredTabs; Tabs { y: 60 } }

    TestCase {
        name: "layout"
        when: windowShown

        function init() { UnitTheme.reset(); tabs.currentIndex = 0; row.highlighted = false; clicks.clear(); actionClicks.clear(); }

        function tabLabel(tab) { return findChild(tab.contentItem, "tabLabel"); }

        function test_scroll_area_follows_its_content() {
            compare(scroll.contentHeight, 200);
            verify(scroll.contentHeight > scroll.height, "the content overflows");
            compare(scroll.bar.parent, scroll);
            compare(scroll.bar.visible, true);
            compare(scroll.bar.width, Theme.scrollArea.barWidth);
        }

        function test_tabs_open_on_click() {
            compare(tabs.count, 2);
            compare(tabs.currentIndex, 0);
            mouseClick(tabs.itemAt(1));
            compare(tabs.currentIndex, 1);
            compare(tabs.itemAt(1).checked, true);
            compare(tabs.itemAt(0).checked, false);
            compare(tabs.itemAt(1).background.children[0].visible, true);
            compare(tabs.itemAt(0).background.children[0].visible, false);
            compare(tabs.height, Theme.tabs.height);
        }

        // A tab's label centres `tabs.paddingX` in from each side; hover
        // lifts a closed tab's label short of the open one's, a press keeps
        // the tab background transparent, and a disabled row fades.
        function test_tabs_centre_and_draw_their_states() {
            const tab = tabs.itemAt(1);
            compare(tab.leftPadding, Theme.tabs.paddingX);
            compare(tab.rightPadding, Theme.tabs.paddingX);
            compare(tab.contentItem.x, Theme.tabs.paddingX);
            compare(tab.contentItem.width, tab.width - 2 * Theme.tabs.paddingX);
            tabs.currentIndex = 0;
            mouseMove(tab, tab.width / 2, tab.height / 2);
            tryCompare(tabLabel(tab), "color", Qt.color(Theme.tabs.hover));
            verify(String(Qt.color(Theme.tabs.hover)) !== String(Qt.color(Theme.tabs.active)), "hover differs from the open tab");
            mousePress(tab, tab.width / 2, tab.height / 2);
            tryCompare(tab.background, "color", Qt.color("transparent"));
            mouseRelease(tab, tab.width / 2, tab.height / 2);
            mouseMove(root, root.width - 1, root.height - 1);
            tabs.enabled = false;
            compare(tabs.opacity, Theme.opacity.disabled);
            tabs.enabled = true;
        }

        function test_tabs_centre_the_visible_label_group_data() {
            const cases = [
                { tag: "short ordinary narrow", label: "Status", width: 240, setup: false },
                { tag: "long ordinary wide", label: "Plugin settings", width: 400, setup: false },
                { tag: "Setup narrow", label: "Setup", width: 240, setup: true },
                { tag: "Setup wide", label: "Setup", width: 400, setup: true }
            ];
            const data = [];
            for (const mode of ["dark", "light"]) {
                for (const row of cases) {
                    data.push({ tag: mode + " " + row.tag, mode: mode, label: row.label, width: row.width, setup: row.setup });
                }
            }
            return data;
        }

        // Read the actual child bounds. Text alignment alone cannot centre
        // a natural-width label inside a stretched content item.
        function test_tabs_centre_the_visible_label_group(data) {
            compare(UnitTheme.override({ scheme: { mode: data.mode } }), "ok");
            const bar = createTemporaryObject(centredTabs, root, { width: data.width, model: data.setup ? ["Status", "Setup"] : [data.label, "Setup"] });
            verify(bar !== null);
            tryCompare(bar, "count", 2);
            const tab = bar.itemAt(data.setup ? 1 : 0);
            const label = tabLabel(tab);
            const warning = findChild(tab.contentItem, "tabWarning");
            verify(warning !== null);
            for (const width of [data.width, data.width + 80]) {
                const previousWidth = tab.width;
                bar.width = width;
                if (width !== data.width) tryVerify(() => tab.width > previousWidth, 1000, "the tab expands with its bar");
                for (const needsSetup of [false, true, false]) {
                    bar.warningTabs = needsSetup ? ["Setup"] : [];
                    tryCompare(warning, "visible", data.setup && needsSetup);
                    // The Row repositions on polish after warning or width changes.
                    tryVerify(() => {
                        const left = label.mapToItem(tab, 0, 0).x;
                        const right = warning.visible ? warning.mapToItem(tab, warning.width, 0).x : label.mapToItem(tab, label.width, 0).x;
                        return Math.abs((left + right) / 2 - tab.width / 2) <= 0.5;
                    }, 1000, "the visible label and warning group centres in the tab");
                    compare(label.width, label.implicitWidth);
                    const left = label.mapToItem(tab, 0, 0).x;
                    const right = warning.visible ? warning.mapToItem(tab, warning.width, 0).x : label.mapToItem(tab, label.width, 0).x;
                    const visibleWidth = label.width + (warning.visible ? Theme.stack.inline + warning.width : 0);
                    verify(tab.width > tab.implicitWidth, "the tab has room beyond its natural label group");
                    fuzzyCompare(right - left, visibleWidth, 0.01);
                    fuzzyCompare(tab.implicitWidth, visibleWidth + tab.leftPadding + tab.rightPadding, 0.01);
                    verify(left >= tab.leftPadding);
                    verify(right <= tab.width - tab.rightPadding);
                    const centreY = label.mapToItem(tab, 0, label.height / 2).y;
                    fuzzyCompare(centreY, tab.height / 2, 0.5);
                    if (warning.visible) {
                        fuzzyCompare(warning.mapToItem(tab, 0, warning.height / 2).y, centreY, 0.5);
                    }
                }
            }
        }

        // A row handed label colours draws its closed and open tabs in them.
        function test_tabs_draw_handed_colours() {
            handedTabs.currentIndex = 0;
            compare(tabLabel(handedTabs.itemAt(0)).color, Qt.color("#6080a0"));
            tryCompare(tabLabel(handedTabs.itemAt(1)), "color", Qt.color("#204060"));
        }

        // A row with `hoverMark` draws the mark under a closed tab while
        // the pointer is on it, and never under the open tab or in a row
        // without it.
        function test_hover_mark_shows_under_a_hovered_closed_tab() {
            markedTabs.currentIndex = 0;
            const closed = markedTabs.itemAt(1);
            const mark = findChild(closed.background, "hoverMark");
            compare(mark.visible, false);
            mouseMove(closed, closed.width / 2, closed.height / 2);
            tryCompare(mark, "visible", true);
            compare(mark.color, markedTabs.hover);
            const open = markedTabs.itemAt(0);
            mouseMove(open, open.width / 2, open.height / 2);
            tryCompare(open, "hovered", true);
            compare(findChild(open.background, "hoverMark").visible, false);
            const plain = handedTabs.itemAt(handedTabs.currentIndex === 0 ? 1 : 0);
            mouseMove(plain, plain.width / 2, plain.height / 2);
            tryCompare(plain, "hovered", true);
            compare(findChild(plain.background, "hoverMark").visible, false);
            mouseMove(root, root.width - 1, root.height - 1);
        }

        // The open tab's indicator draws the colour the view hands the
        // row, and the theme's where it hands none.
        function test_open_tab_indicator_draws_the_handed_colour() {
            handedTabs.currentIndex = 0;
            compare(findChild(handedTabs.itemAt(0).background, "indicator").color, Qt.color("#a0c0e0"));
            compare(findChild(tabs.itemAt(tabs.currentIndex).background, "indicator").color, Qt.color(Theme.tabs.indicatorColor));
        }

        // A view can hand the open tab's line and the hover line one
        // colour, so the hover line is the thinner of the two.
        function test_hover_mark_is_thinner_than_the_open_indicator() {
            const open = findChild(markedTabs.itemAt(0).background, "indicator");
            const mark = findChild(markedTabs.itemAt(1).background, "hoverMark");
            verify(mark.height > 0);
            verify(mark.height < open.height, "hover " + mark.height + ", open " + open.height);
        }

        // The track is a resting surface's line: a row with `hoverMark`
        // draws none, so no stub shows between its tabs.
        function test_a_marked_row_draws_no_track() {
            compare(findChild(markedTabs.background, "track").visible, false);
            compare(findChild(handedTabs.background, "track").visible, true);
        }

        function test_list_item_highlights_and_clicks() {
            compare(String(row.background.color), "#00000000");
            row.highlighted = true;
            tryCompare(row.background, "color", Qt.color(Theme.listItem.selected));
            mouseClick(row);
            compare(clicks.count, 1);
            verify(row.height >= Theme.listItem.height);
            // A row without a width prefers the width of its text.
            verify(bare.implicitWidth > 100, "a populated row without a width is " + bare.implicitWidth + " wide");
        }

        // Qt takes the cursor over an item from a handler of the item that
        // sets a cursor shape and is hovered; with none, the arrow shows.
        function showsHand(item) {
            mouseMove(item, item.width / 2, item.height / 2);
            return item.data.some(child => child instanceof HoverHandler && child.cursorShape === Qt.PointingHandCursor && child.hovered);
        }

        // Motion is stilled, so a fill the row would draw lands at once. A
        // row draws no hover of its own: its list's cursor draws it.
        function test_list_item_that_takes_no_click_draws_no_hover_or_press() {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            verify(showsHand(row), "a row that takes a click shows the hand");
            compare(String(row.background.color), "#00000000", "a row draws no hover fill of its own");
            const at = still.textStart + 1;
            mouseMove(still, at, still.height / 2);
            tryCompare(still, "hovered", true);
            compare(String(still.background.color), "#00000000", "a row that takes no click draws no hover");
            compare(showsHand(still), false, "a row that takes no click shows no hand");
            mousePress(still, at, still.height / 2);
            compare(still.down, false, "a row that takes no click draws no press");
            compare(String(still.background.color), "#00000000");
            mouseRelease(still, at, still.height / 2);
        }

        function test_list_item_that_takes_no_click_keeps_its_trailing_action() {
            verify(showsHand(stillAction), "the trailing action shows the hand");
            tryCompare(stillAction, "hovered", true);
            mouseClick(stillAction);
            compare(actionClicks.count, 1);
            stillAction.forceActiveFocus();
            compare(stillAction.activeFocus, true);
            keyClick(Qt.Key_Return);
            compare(actionClicks.count, 2);
        }

        function test_key_hints_draw_alternative_keys_as_separate_caps() {
            const firstPair = hints.children[0];
            const caps = firstPair.children[0].children.filter(child => child.shortcut !== undefined);
            compare(caps.length, 2);
            compare(caps[0].shortcut, "Left");
            compare(caps[1].shortcut, "Right");
            const secondCaps = hints.children[1].children[0].children.filter(child => child.shortcut !== undefined);
            compare(secondCaps.length, 1);
            compare(secondCaps[0].shortcut, "Ctrl+Tab");
        }

        function test_hint_word_draws_plain_in_the_hint_role_data() {
            return [
                { tag: "dark", mode: "dark", faint: "#8090a0" },
                { tag: "light", mode: "light", faint: "#405060" }
            ];
        }

        // A hint word is a hint-role label on the surface under it: no
        // backing, no layer and no colour of its own.
        function test_hint_word_draws_plain_in_the_hint_role(row) {
            compare(UnitTheme.override({ scheme: { mode: row.mode }, color: { text: "#d0d0d0", textFaint: row.faint } }), "ok");
            const label = hints.children[0].children[1];
            compare(label.role, "hint");
            tryCompare(label, "color", Qt.color(row.faint));
            compare(label.children.length, 0, "the word draws no backing");
            compare(label.layer.enabled, false, "the word draws no shadow layer");
        }

        // The title and secondary lines draw with whole-pixel line boxes,
        // so the pair sits on the icon's centre, which is the row's.
        function test_list_item_centres_its_lines_on_its_icon() {
            const icon = row.contentItem.children[0];
            const column = row.contentItem.children[1];
            const title = column.children[0];
            const secondary = column.children[1];
            compare(title.role, "item");
            compare(secondary.role, "itemHint");
            compare(title.lineHeight, title.lineBox);
            compare(secondary.lineHeight, secondary.lineBox);
            const top = title.mapToItem(row, 0, 0).y;
            const bottom = secondary.mapToItem(row, 0, secondary.height).y;
            const iconMid = icon.mapToItem(row, 0, icon.height / 2).y;
            verify(Math.abs((top + bottom) / 2 - iconMid) <= 1, "lines centre " + (top + bottom) / 2 + ", icon centre " + iconMid);
            verify(Math.abs(iconMid - row.height / 2) <= 1, "icon centre " + iconMid + ", row centre " + row.height / 2);
            compare(row.height, Theme.listItem.twoLineHeight, "a row with a secondary line takes the two-line height");
            const single = Qt.createQmlObject("import qs.Ui\nListItem { text: \"One line\"; width: 200 }", root);
            compare(single.height, Theme.listItem.height, "a row without one takes the one-line height");
            single.destroy();
        }

        // A row's text comes from outside the shell, such as a device name
        // or a copied line: a tag in it is text, never markup.
        function test_list_item_draws_plain_text() {
            const column = row.contentItem.children[1];
            compare(column.children[0].textFormat, Text.PlainText, "the title");
            compare(column.children[1].textFormat, Text.PlainText, "the secondary line");
        }

        function test_section_header_and_divider() {
            const eyebrow = header.children[0].children[0];
            compare(eyebrow.role, "eyebrow");
            compare(eyebrow.text, "Listed since");
            compare(header.topPadding, 0);
            // A padded header keeps its lines inside the padding.
            for (const line of inset.children) {
                compare(line.x, inset.leftPadding);
                compare(line.width, inset.width - inset.leftPadding - inset.rightPadding);
            }
            compare(divider.height, Theme.divider.thickness);
            compare(String(divider.color), String(Qt.color(Theme.divider.color)));
        }

        // How far the heading's capitals start under the drawn row above
        // it, a box that draws to its edge.
        function headingSpace() {
            const eyebrow = section.children[0].children[0].children[0];
            return eyebrow.mapToItem(sectionColumn, 0, eyebrow.baselineOffset).y - eyebrowMetrics.capitalHeight - beforeSection.height;
        }

        function test_section_spacing_and_inset() {
            const headerItem = section.children[0];
            const rows = section.children[1];
            fuzzyCompare(headingSpace(), Theme.stack.heading, 1);
            compare(firstSection.topPadding, 0);
            compare(rows.spacing, Theme.stack.row);
            compare(headerItem.leftPadding, Theme.row.paddingX);
            compare(headerItem.children[0].x, Theme.row.paddingX);
        }

        // expected-log: Surface: no level named "floating" -- the test names an unknown level on purpose
        function test_surface_draws_its_level() {
            // The drawn body and edge of the GlassSurface it is, glass off.
            compare(String(surface.children[1].color), String(Qt.color(Theme.surface.level.raised.background)));
            compare(String(surface.children[2].border.color), String(Qt.color(Theme.surface.level.raised.border)));
            compare(surface.children[1].radius, Theme.surface.radius);
            const odd = Qt.createQmlObject("import qs.Ui\nSurface { level: \"floating\" }", root);
            compare(String(odd.children[1].color), String(Qt.color(Theme.surface.level.base.background)));
            odd.destroy();
        }

        function test_theme_change_moves_the_layout() {
            compare(UnitTheme.override({ tabs: { height: 44 }, row: { height: 50 }, stack: { row: 9, heading: 40 }, divider: { thickness: 3 }, surface: { radius: 9 } }), "ok");
            compare(tabs.height, 44);
            verify(row.height >= 50);
            // The column places its rows again on its next polish.
            tryVerify(() => Math.abs(headingSpace() - 40) <= 1, 1000, "the heading moves with the token");
            compare(section.children[1].spacing, 9);
            compare(divider.height, 3);
            compare(surface.children[1].radius, 9);
        }
    }
}
