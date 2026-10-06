import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// Info buttons: an IconButton with `info` opens a dialog by click, Return
// and Space; the dialog closes by Escape, its Close button and a press
// outside, and focus returns to the icon. A Field draws the icon only when
// `info` is set.
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

    IconButton {
        id: info
        iconName: "info"
        label: "About Warden"
        infoTitle: "Warden"
        info: "Shows whether Agent Warden is checking agents."
        x: 20
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
            info.destroyInfoWindow();
            outside.forceActiveFocus();
        }

        function descendants(item) {
            const found = [item];
            for (let i = 0; i < found.length; i++)
                for (const child of found[i].children || []) found.push(child);
            return found;
        }

        function typeName(item) { return String(item).split("(")[0].replace(/(_QML(TYPE)?_\d+)+$/, ""); }
        function popup(of) {
            return of.infoWindow === null ? null : of.infoWindow.tracker.popup;
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
        function iconButtons(item) {
            return descendants(item).filter(child => typeName(child) === "IconButton" && child.visible);
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
            info.destroyInfoWindow();
        }

        function test_escape_closes_and_returns_focus() {
            openByKey(Qt.Key_Return);
            keyClick(Qt.Key_Escape);
            tryCompare(info, "infoOpen", false);
            compare(info.activeFocus, true);
            info.destroyInfoWindow();
        }

        function test_close_button_closes_and_returns_focus() {
            openByKey(Qt.Key_Return);
            mouseClick(closeButton(info));
            tryCompare(info, "infoOpen", false);
            tryCompare(info, "activeFocus", true);
            info.destroyInfoWindow();
        }

        function test_outside_press_closes_and_returns_focus() {
            openByKey(Qt.Key_Return);
            mouseClick(outside);
            tryCompare(info, "infoOpen", false);
            tryCompare(info, "activeFocus", true);
            compare(outside.activeFocus, false);
            info.destroyInfoWindow();
        }

        function test_field_draws_icon_only_with_info() {
            compare(iconButtons(explained).length, 1);
            compare(iconButtons(explained)[0].label, "About Explained");
            compare(iconButtons(plain).length, 0);
        }
    }
}
