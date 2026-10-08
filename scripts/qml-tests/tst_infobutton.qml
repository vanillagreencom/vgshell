import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// InfoButton shows its explanation in its tooltip on hover and on keyboard
// focus, and its label there when it has none. It opens a dialog by click,
// Return and Space; the dialog closes by Escape, its Close button and a
// press outside, and focus returns to the icon. A Field draws the icon only
// when `info` is set.
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
            const window = tooltipOf(of).tracker.popup;
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

        function test_field_draws_icon_only_with_info() {
            compare(infoButtons(explained).length, 1);
            compare(infoButtons(explained)[0].label, "About Explained");
            compare(infoButtons(plain).length, 0);
        }
    }
}
