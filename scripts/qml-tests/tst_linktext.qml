import QtQuick
import QtTest
import qs.Ui

Item {
    id: root
    width: 420
    height: 320

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
        id: changing
        y: 280
        width: 360
        text: "Set by theme"
        link: "Hyprland config"
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
    // A link the full stop closes, so its box runs on to the stop.
    LinkText {
        id: closing
        y: 240
        width: 360
        text: "Read the notes in hyprland.lua."
        link: "hyprland.lua"
    }
    TextMetrics { id: before; font: labelOf(inline).font; text: "Read the notes in" }
    TextMetrics { id: prefix; font: labelOf(inline).font; text: "Read the notes in " }
    TextMetrics { id: words; font: labelOf(inline).font; text: "hyprland.lua" }
    TextMetrics { id: wordsStop; font: labelOf(inline).font; text: "hyprland.lua." }
    TextMetrics { id: wordsSpace; font: labelOf(inline).font; text: "hyprland.lua " }
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

        function test_initial_focus_has_no_ring_and_tab_shows_it() {
            linked.forceActiveFocus(Qt.OtherFocusReason);
            const ring = ringOf(linked);
            verify(ring !== undefined, "the linked word owns its ring");
            compare(linked.activeFocus, true);
            compare(linked.Accessible.name, linked.text);
            compare(linked.Accessible.role, Accessible.Link);
            compare(linked.visualFocus, false);
            verify(waitForRendering(linked));
            compare(ring.visible, false);
            keyClick(Qt.Key_Tab);
            compare(escaped.activeFocus, true);
            compare(escaped.visualFocus, true);
            const nextRing = ringOf(escaped);
            verify(nextRing !== undefined, "the next linked word owns its ring");
            verify(waitForRendering(escaped));
            compare(nextRing.visible, true);
            compare(linked.visualFocus, false);
            compare(ring.visible, false);
            keyClick(Qt.Key_Backtab);
            compare(linked.activeFocus, true);
            compare(linked.visualFocus, true);
            verify(waitForRendering(linked));
            compare(ring.visible, true);
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

        // Each case: the item, the line its link is on, the run's start and
        // width, and where the words beside it end and start, null where
        // the line starts or the text ends.
        function test_focus_ring_goes_round_the_link_words() {
            const cases = [
                [inline, 0, prefix.advanceWidth, words.advanceWidth, before.advanceWidth, prefix.advanceWidth + wordsSpace.advanceWidth],
                [wrapped, 1, 0, words.advanceWidth, null, wordsSpace.advanceWidth],
                [closing, 0, prefix.advanceWidth, wordsStop.advanceWidth, before.advanceWidth, null]
            ];
            for (const [item, line, x, width, leftEnd, rightStart] of cases) {
                const box = item.linkBox;
                const lineBox = labelOf(item).lineBox;
                compare(box.y, line * lineBox, "the words' line");
                compare(box.height, lineBox, "one line box tall");
                fuzzyCompare(box.x, x, 1, "the words' start");
                fuzzyCompare(box.width, width, 1, "the words' width, punctuation against them included");
                item.forceActiveFocus(Qt.TabFocusReason);
                const ring = ringOf(item);
                verify(ring !== undefined && ring.visible, "the focused link draws its ring");
                const left = ring.mapToItem(item, 0, 0).x;
                const right = left + ring.width;
                verify(left + ring.border.width <= box.x, "the ring clears the words' start");
                verify(right - ring.border.width >= box.x + box.width, "the ring clears the words' end");
                if (leftEnd !== null)
                    verify(left >= leftEnd + 1, "1 px clear of the word before: ring " + left + ", word end " + leftEnd);
                if (rightStart !== null)
                    verify(right <= rightStart - 1, "1 px clear of the word after: ring " + right + ", word start " + rightStart);
                verify(ring.width < item.width, "the ring leaves the prose outside it");
            }
        }

        // A message that changes to a shorter one, as a row's does when
        // its source changes, is measured only with its own link's run:
        // a position past the new text logs a QTextCursor warning, which
        // fails this file.
        function test_a_shorter_text_is_measured_with_its_own_run() {
            changing.text = "Overridden by your Hyprland config";
            changing.text = "Set by your Hyprland config";
            changing.text = "Hyprland config sets 10 px";
            compare(changing.run, [0, 15]);
            verify(changing.linkBox.width > 0 && changing.linkBox.x === 0, "the box is the link's at the text's start");
        }

        function test_pointer_activates_only_the_link() {
            mouseClick(linked, 4, linked.height / 2);
            compare(activated.count, 1);
            mouseClick(linked, linked.width - 4, linked.height / 2);
            compare(activated.count, 1);
        }
    }
}
