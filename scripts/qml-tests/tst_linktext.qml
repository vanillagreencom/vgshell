import QtQuick
import QtTest
import qs.Ui

Item {
    id: root
    width: 420
    height: 280

    function labelOf(item) { return item.children[0]; }

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
    // Prose with its link inside one line, and the same prose in a width
    // that wraps the link onto its second line.
    LinkText {
        id: inline
        y: 160
        width: 360
        text: "Read the notes in hyprland.lua today."
        link: "hyprland.lua"
    }
    LinkText {
        id: wrapped
        y: 200
        width: prefix.advanceWidth + 10
        wrapMode: Text.Wrap
        text: "Read the notes in hyprland.lua today."
        link: "hyprland.lua"
    }
    TextMetrics { id: prefix; font: labelOf(inline).font; text: "Read the notes in " }
    TextMetrics { id: words; font: labelOf(inline).font; text: "hyprland.lua" }
    SignalSpy { id: activated; target: linked; signalName: "activated" }

    TestCase {
        name: "linktext"
        when: windowShown

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

        function descendants(item) {
            const found = [];
            for (const child of item.children) found.push(child, ...descendants(child));
            return found;
        }

        function ringOf(item) {
            return descendants(item).find(child => child.target === item && child.border !== undefined);
        }

        function test_focus_ring_goes_round_the_link_words() {
            for (const [item, line, x] of [[inline, 0, prefix.advanceWidth], [wrapped, 1, 0]]) {
                const box = item.linkBox;
                const lineBox = labelOf(item).lineBox;
                compare(box.y, line * lineBox, "the words' line");
                compare(box.height, lineBox, "one line box tall");
                fuzzyCompare(box.x, x, 1, "the words' start");
                fuzzyCompare(box.width, words.advanceWidth, 1, "the words' width");
                item.forceActiveFocus(Qt.TabFocusReason);
                const ring = ringOf(item);
                verify(ring !== undefined && ring.visible, "the focused link draws its ring");
                const at = ring.mapToItem(item, 0, 0);
                fuzzyCompare(at.x, box.x - ring.extent, 0.5, "the ring's left beside the words");
                fuzzyCompare(ring.width, box.width + 2 * ring.extent, 0.5, "the ring as wide as the words and its gap");
                verify(ring.width < item.width, "the ring leaves the prose outside it");
            }
        }

        function test_pointer_activates_only_the_link() {
            mouseClick(linked, 4, linked.height / 2);
            compare(activated.count, 1);
            mouseClick(linked, linked.width - 4, linked.height / 2);
            compare(activated.count, 1);
        }
    }
}
