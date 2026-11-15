import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// InfoButton shows its explanation in its tooltip on hover and on keyboard
// focus, and its label there when it has none. It opens a dialog by click,
// Return and Space; the dialog closes by Escape, its Close button and a
// press outside, and focus returns to the icon. The open dialog draws one
// frame, centred inside the window's dialog margin over a scrim that washes
// every row of the window. A Field draws the icon only when `info` is set,
// and beside its label that icon opens no tooltip, which would lie on the
// label of the row under it.
// A page reference in the explanation is a link in the dialog: activating
// it closes the dialog and asks for its page and tab through
// `infoPageActivated`, which a Field forwards whether its label stands
// beside or above its control.
Item {
    id: root
    width: 520
    height: 320

    Button {
        id: outside
        text: "Outside"
        x: 420
        y: 10
    }

    InfoButton {
        id: info
        title: "Warden"
        info: "Shows whether Agent Warden is checking agents."
        x: 20
        y: 20
    }

    InfoButton {
        id: bare
        title: "Bare"
        x: 80
        y: 20
    }

    InfoButton {
        id: paged
        title: "Voice"
        info: "Set it up on the [Voice page](page:acme.voice/Setup)."
        x: 140
        y: 20
    }
    SignalSpy { id: pagedPages; target: paged; signalName: "infoPageActivated" }

    Field {
        id: explained
        label: "Explained"
        info: "This row has a declared explanation."
        inline: true
        width: 360
        y: 80

        Label { role: "value"; text: "Value" }
    }

    Field {
        id: plain
        label: "Plain"
        inline: true
        width: 360
        y: 140

        Label { role: "value"; text: "Value" }
    }

    Field {
        id: pagedBeside
        label: "Beside"
        info: "Keys are on the [Models page](page:acme.models)."
        inline: true
        width: 360
        y: 190

        Label { role: "value"; text: "Value" }
    }
    SignalSpy { id: besidePages; target: pagedBeside; signalName: "infoPageActivated" }

    Field {
        id: pagedAbove
        label: "Above"
        info: "Keys are on the [Models page](page:acme.models/Setup)."
        inline: false
        width: 360
        y: 240

        Label { role: "value"; text: "Value" }
    }
    SignalSpy { id: abovePages; target: pagedAbove; signalName: "infoPageActivated" }

    TestCase {
        name: "infobutton"
        when: windowShown

        function init() {
            UnitTheme.reset();
            info.destroyPopup();
            // A tooltip an earlier test showed may still hold the window
            // focus; keys and focus go to the test window.
            root.Window.window.requestActivate();
            outside.forceActiveFocus();
            tryCompare(outside, "activeFocus", true);
        }

        function descendants(item) {
            const found = [item];
            for (let i = 0; i < found.length; i++)
                for (const child of found[i].children || []) found.push(child);
            return found;
        }

        function typeName(item) { return String(item).split("(")[0].replace(/(_QML(TYPE)?_\d+)+$/, ""); }
        function popup(of) {
            return of.popup === null ? null : of.popup.tracker.popup;
        }
        function dialog(of) {
            return descendants(popup(of).contentItem).find(child => typeName(child) === "Dialog");
        }
        function closeButton(of) {
            return descendants(popup(of).contentItem).find(child => typeName(child) === "Button" && child.text === "Close");
        }
        function shownTexts(of) {
            return descendants(popup(of).contentItem).filter(child => child instanceof Text && child.visible && child.text !== "").map(child => child.text);
        }
        function tooltipOf(of) {
            return descendants(of).find(child => child.anchorItem === of && child.details !== undefined);
        }
        function tooltipTitle(of) {
            // openedChanged runs before the tooltip's tracker binding
            // updates. Read the loaded window itself in that callback.
            const loader = tooltipOf(of).resources.find(child => String(child).indexOf("LazyLoader") === 0);
            const window = loader.item;
            return descendants(window.contentItem).find(child => child.objectName === "tooltipTitle");
        }
        function rest(of) {
            mouseMove(root, root.width - 1, root.height - 1);
            mouseMove(of, of.width / 2, of.height / 2);
        }
        function infoButtons(item) {
            return descendants(item).filter(child => typeName(child) === "InfoButton" && child.visible);
        }
        function openByKey(key) {
            info.forceActiveFocus(Qt.TabFocusReason);
            keyClick(key);
            tryCompare(info, "infoOpen", true);
            popup(info).requestActivate();
            tryCompare(popup(info), "active", true);
            tryCompare(dialog(info), "activeFocus", true);
        }

        function test_opens_by_click_enter_and_space_data() {
            return [
                { tag: "click", key: 0 },
                { tag: "Space", key: Qt.Key_Space }
            ];
        }

        function test_opens_by_click_enter_and_space(data) {
            if (data.key === 0) mouseClick(info);
            else openByKey(data.key);
            tryCompare(info, "infoOpen", true);
            const texts = shownTexts(info);
            verify(texts.indexOf("Warden") !== -1, "the title is not drawn");
            verify(texts.indexOf("Shows whether Agent Warden is checking agents.") !== -1, "the explanation is not drawn");
            info.closeInfo();
            tryCompare(info, "activeFocus", true);
            info.destroyPopup();
        }

        function test_hover_shows_the_explanation_in_the_tooltip() {
            compare(UnitTheme.override({ tooltip: { delay: 50 } }), "ok");
            rest(info);
            tryCompare(tooltipOf(info), "opened", true, 2000);
            compare(tooltipTitle(info).text, "Shows whether Agent Warden is checking agents.");
            compare(info.infoOpen, false);
            mouseMove(root, root.width - 1, root.height - 1);
            tryCompare(tooltipOf(info), "opened", false);
        }

        // The offscreen platform activates a window when it shows, so the
        // shown tooltip takes the focus from the icon and closes again; the
        // test records what the tooltip drew when it opened.
        function test_keyboard_focus_shows_the_explanation_in_the_tooltip() {
            compare(UnitTheme.override({ tooltip: { delay: 50 } }), "ok");
            mouseMove(root, root.width - 1, root.height - 1);
            const tip = tooltipOf(info);
            const shown = [];
            const record = () => { if (tip.opened) shown.push(tooltipTitle(info).text); };
            tip.openedChanged.connect(record);
            try {
                info.forceActiveFocus(Qt.TabFocusReason);
                tryVerify(() => shown.length > 0, 2000, "keyboard focus opens the tooltip");
            } finally {
                tip.openedChanged.disconnect(record);
            }
            compare(shown[0], "Shows whether Agent Warden is checking agents.");
        }

        function test_a_button_without_an_explanation_shows_its_label() {
            compare(UnitTheme.override({ tooltip: { delay: 50 } }), "ok");
            rest(bare);
            tryCompare(tooltipOf(bare), "opened", true, 2000);
            compare(tooltipTitle(bare).text, "About Bare");
            mouseMove(root, root.width - 1, root.height - 1);
            tryCompare(tooltipOf(bare), "opened", false);
        }

        function test_escape_closes_and_returns_focus() {
            openByKey(Qt.Key_Return);
            keyClick(Qt.Key_Escape);
            tryCompare(info, "infoOpen", false);
            compare(info.activeFocus, true);
            info.destroyPopup();
        }

        function test_close_button_closes_and_returns_focus() {
            openByKey(Qt.Key_Return);
            mouseClick(closeButton(info));
            tryCompare(info, "infoOpen", false);
            tryCompare(info, "activeFocus", true);
            info.destroyPopup();
        }

        function test_outside_press_closes_and_returns_focus() {
            openByKey(Qt.Key_Return);
            mouseClick(outside);
            tryCompare(info, "infoOpen", false);
            tryCompare(info, "activeFocus", true);
            compare(outside.activeFocus, false);
            info.destroyPopup();
        }

        // The frames the open help draws: every GlassSurface in its popup.
        function frames(of) {
            return descendants(popup(of).contentItem).filter(child => child.glassSurface === true && child.visible);
        }
        // Open the help by pointer and wait for its surface to take the
        // window's size, which the platform applies once the surface shows.
        function openHelp() {
            mouseClick(info);
            tryCompare(info, "infoOpen", true);
            const covered = root.Window.window.contentItem;
            tryCompare(popup(info).contentItem, "width", covered.width);
            tryCompare(popup(info).contentItem, "height", covered.height);
            return popup(info);
        }
        function boxIn(item, within) {
            const at = item.mapToItem(within, 0, 0);
            return { x: at.x, y: at.y, width: item.width, height: item.height };
        }

        function test_the_help_draws_one_frame() {
            mouseClick(info);
            tryCompare(info, "infoOpen", true);
            const drawn = frames(info);
            compare(drawn.length, 1, "the help draws one frame");
            compare(drawn[0].parent, dialog(info), "the one frame is the dialog's");
            info.closeInfo();
            tryCompare(info, "activeFocus", true);
            info.destroyPopup();
        }

        function test_info_lines_draw_a_paragraph_gap() {
            const original = info.info;
            info.info = "First paragraph.\nSecond paragraph.";
            try {
                const window = openHelp();
                verify(waitForPolish(window));
                const lines = descendants(window.contentItem).filter(child => typeName(child) === "LinkText" && child.visible);
                compare(lines.length, 2);
                compare(lines[1].y - lines[0].y - lines[0].height, Theme.space.md);
            } finally {
                info.closeInfo();
                info.destroyPopup();
                info.info = original;
            }
        }

        // A theme dialog wider than the window shows the cap: the dialog
        // takes the window's width less the margin on each side.
        function test_the_help_stays_inside_the_content_edge_data() {
            return [
                { tag: "theme width", width: 0 },
                { tag: "wider than the window", width: 900 }
            ];
        }

        function test_the_help_stays_inside_the_content_edge(data) {
            if (data.width > 0) compare(UnitTheme.override({ dialog: { width: data.width } }), "ok");
            const window = openHelp();
            const margin = Theme.dialog.margin;
            const box = boxIn(dialog(info), window.contentItem);
            verify(box.x >= margin && box.x + box.width <= window.width - margin, "the dialog spans x " + box.x + "+" + box.width + " in a window " + window.width + " wide");
            verify(box.y >= margin && box.y + box.height <= window.height - margin, "the dialog spans y " + box.y + "+" + box.height + " in a window " + window.height + " tall");
            fuzzyCompare(box.x, window.width - box.x - box.width, 1, "the dialog is centred across the window");
            fuzzyCompare(box.y, window.height - box.y - box.height, 1, "the dialog is centred down the window");
            info.closeInfo();
            tryCompare(info, "activeFocus", true);
            info.destroyPopup();
        }

        // Every row of the window lies under the help's scrim, so none is
        // drawn undimmed beside the dialog, and a press on one closes the
        // help without reaching that row.
        function test_the_help_covers_no_row_undimmed() {
            const window = openHelp();
            const scrim = descendants(window.contentItem).find(child => child.scrim === true && child.visible);
            verify(scrim !== undefined, "the help draws a scrim");
            const wash = boxIn(scrim, window.contentItem);
            for (const row of [info, bare, explained, plain, outside]) {
                const box = boxIn(row, root);
                verify(box.x >= wash.x && box.y >= wash.y && box.x + box.width <= wash.x + wash.width && box.y + box.height <= wash.y + wash.height, "a row at " + box.x + "," + box.y + " lies outside the scrim");
            }
            info.closeInfo();
            tryCompare(info, "activeFocus", true);
            info.destroyPopup();
        }

        function pageLink(of) {
            return descendants(popup(of).contentItem).find(child => typeName(child) === "LinkText" && child.visible && child.linked);
        }

        function test_a_page_reference_closes_the_help_and_asks_for_its_page() {
            pagedPages.clear();
            mouseClick(paged);
            tryCompare(paged, "infoOpen", true);
            const link = pageLink(paged);
            verify(link !== undefined, "the help draws the reference as a link");
            link.clicked();
            tryCompare(paged, "infoOpen", false);
            compare(pagedPages.count, 1);
            compare(pagedPages.signalArguments[0][0], "acme.voice");
            compare(pagedPages.signalArguments[0][1], "Setup");
            tryCompare(paged, "activeFocus", true);
            paged.destroyPopup();
        }

        function test_a_field_forwards_its_help_page_data() {
            return [
                { tag: "label beside", field: pagedBeside, spy: besidePages, tab: "" },
                { tag: "label above", field: pagedAbove, spy: abovePages, tab: "Setup" }
            ];
        }

        function test_a_field_forwards_its_help_page(data) {
            data.spy.clear();
            const buttons = infoButtons(data.field);
            compare(buttons.length, 1);
            mouseClick(buttons[0]);
            tryCompare(buttons[0], "infoOpen", true);
            pageLink(buttons[0]).clicked();
            tryCompare(buttons[0], "infoOpen", false);
            compare(data.spy.count, 1);
            compare(data.spy.signalArguments[0][0], "acme.models");
            compare(data.spy.signalArguments[0][1], data.tab);
            tryCompare(buttons[0], "activeFocus", true);
            buttons[0].destroyPopup();
        }

        // Under a row's icon lies the next row's label and past it the
        // row's own control, so the icon opens its dialog on a press alone.
        function test_a_rows_icon_opens_no_tooltip() {
            compare(UnitTheme.override({ tooltip: { delay: 20 } }), "ok");
            const mark = infoButtons(explained)[0];
            const tip = tooltipOf(mark);
            const opened = [];
            const record = () => { if (tip.opened) opened.push(tip.text); };
            tip.openedChanged.connect(record);
            try {
                rest(mark);
                mark.forceActiveFocus(Qt.TabFocusReason);
                compare(mark.visualFocus, true);
                wait(4 * Theme.tooltip.delay);
                compare(opened.length, 0, "the icon opens a tooltip over the next row: " + opened);
            } finally {
                tip.openedChanged.disconnect(record);
                mouseMove(root, root.width - 1, root.height - 1);
            }
            mouseClick(mark);
            tryCompare(mark, "infoOpen", true);
            mark.closeInfo();
            tryCompare(mark, "activeFocus", true);
            mark.destroyPopup();
        }

        function test_field_draws_icon_only_with_info() {
            compare(infoButtons(explained).length, 1);
            compare(infoButtons(explained)[0].label, "About Explained");
            compare(infoButtons(plain).length, 0);
        }
    }
}
