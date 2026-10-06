import QtQuick
import QtTest
import qs.Ui

Item {
    id: root
    width: 420
    height: 160

    LinkText {
        id: linked
        width: 360
        text: "hyprland.lua and hyprland.lua"
        link: "hyprland.lua"
    }
    LinkText {
        id: escaped
        y: 40
        width: 360
        text: "<hyprland.lua> & hyprland.lua"
        link: "hyprland.lua"
    }
    LinkText {
        id: plain
        y: 80
        width: 360
        text: "plain"
    }
    LinkText {
        id: missing
        y: 120
        width: 360
        text: "VGS opens the cited file."
        link: "hyprland.lua"
    }
    SignalSpy { id: activated; target: linked; signalName: "activated" }

    TestCase {
        name: "linktext"
        when: windowShown

        function labelOf(item) { return item.children[0]; }

        function init() {
            activated.clear();
            linked.forceActiveFocus();
        }

        function test_link_occurrences_are_marked_after_escaping() {
            const html = labelOf(linked).text;
            compare((html.match(/<a href=/g) || []).length, 2);
            verify(html.indexOf("hyprland.lua") !== -1);
            const escapedHtml = labelOf(escaped).text;
            verify(escapedHtml.indexOf("&lt;") !== -1);
            verify(escapedHtml.indexOf("&amp;") !== -1);
            compare((escapedHtml.match(/<a href=/g) || []).length, 2);
        }

        function test_empty_link_takes_no_tab_focus() {
            compare(linked.activeFocusOnTab, true);
            compare(plain.activeFocusOnTab, false);
            compare(missing.linked, false);
            compare(missing.activeFocusOnTab, false);
        }

        function test_clicked_signal_activates() {
            linked.clicked();
            compare(activated.count, 1);
        }

        function test_keyboard_activates() {
            keyClick(Qt.Key_Return);
            keyClick(Qt.Key_Enter);
            keyClick(Qt.Key_Space);
            compare(activated.count, 3);
        }

        function test_pointer_activates_only_the_link() {
            mouseClick(linked, 4, linked.height / 2);
            compare(activated.count, 1);
            mouseClick(linked, linked.width - 4, linked.height / 2);
            compare(activated.count, 1);
        }
    }
}
