import QtQuick
import QtTest
import qs.Commons
import qs.Ui

Item {
    id: root
    width: 420
    height: 760

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
    // A link the full stop closes: the stop stands outside its ring.
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
    SignalSpy { id: activated; target: linked; signalName: "activated" }
    SignalSpy { id: inlineActivated; target: inline; signalName: "activated" }
    // A page reference inside prose, one at the text's start with no tab,
    // and one that names no page.
    LinkText {
        id: paged
        y: 320
        width: 360
        text: "Add a key on the [Models page](page:acme.models/Setup) first."
    }
    LinkText {
        id: tabless
        y: 360
        width: 360
        text: "[Models](page:acme.models) holds the keys."
    }
    LinkText {
        id: pageless
        y: 400
        width: 360
        text: "Turn it on in [Plugins](page:)."
    }
    // A fixed link whose words the text does not hold, beside a page
    // reference: a Settings row's declared link under a hint of another state.
    LinkText {
        id: elsewhere
        y: 440
        width: 360
        link: "Key site"
        text: "Choose it in [Models](page:acme.models/Settings)."
    }
    // A link whose "y" reaches under the baseline, as Remove key's does.
    LinkText {
        id: descending
        y: 480
        width: 360
        text: "Remove key"
        link: "Remove key"
    }
    // A link in a look that hands its own link colour.
    LinkText {
        id: hosted
        y: 520
        width: 360
        text: "Read the notes in hyprland.lua today."
        link: "hyprland.lua"
        linkColor: "#123456"
    }
    // A file reference in prose, as a Setup hint cites a file outside the
    // configuration directory.
    LinkText {
        id: filed
        y: 560
        width: 360
        text: "Shorten [AGENTS.md](file:~%2F.local%2Fshare%2Fvgs%2FAGENTS.md) first."
    }
    LinkText {
        id: multiple
        y: 600
        width: 400
        text: "notes: [notes](file:%2Fhome%2FMy%20Home%2Fnotes%20%28draft%29.md) or [notes](page:vgs.voice/Setup)."
    }
    LinkText {
        id: explicit
        y: 640
        width: 400
        text: "[notes](page:vgs.voice) or [notes](page:acme.models)."
        link: "notes"
    }
    SignalSpy { id: multiplePages; target: multiple; signalName: "pageActivated" }
    SignalSpy { id: explicitPages; target: explicit; signalName: "pageActivated" }
    SignalSpy { id: explicitActivated; target: explicit; signalName: "activated" }
    FontMetrics { id: font; font: labelOf(inline).font }
    SignalSpy { id: elsewherePages; target: elsewhere; signalName: "pageActivated" }
    SignalSpy { id: pagedPages; target: paged; signalName: "pageActivated" }
    SignalSpy { id: pagedActivated; target: paged; signalName: "activated" }
    SignalSpy { id: tablessPages; target: tabless; signalName: "pageActivated" }
    SignalSpy { id: filedPages; target: filed; signalName: "pageActivated" }
    SignalSpy { id: filedActivated; target: filed; signalName: "activated" }

    TestCase {
        name: "linktext"
        when: windowShown

        function init() {
            activated.clear();
            inlineActivated.clear();
            linked.forceActiveFocus();
        }

        function test_link_occurrences_are_marked_after_escaping() {
            const html = labelOf(linked).text;
            compare((html.match(/<font color=/g) || []).length, 2);
            verify(html.indexOf("hyprland.lua") !== -1);
            const escapedHtml = labelOf(escaped).text;
            verify(escapedHtml.indexOf("&lt;") !== -1);
            verify(escapedHtml.indexOf("&amp;") !== -1);
            compare((escapedHtml.match(/<font color=/g) || []).length, 2);
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
            // The ring's visible is bound to its target's visualFocus, so each
            // check reads it at once. Qt 6.11.2 QuickTestResult::waitForRendering
            // waits for the next frameSwapped and requests no frame: a frame
            // that swaps before it connects leaves it to time out.
            compare(ring.visible, false);
            keyClick(Qt.Key_Tab);
            compare(escaped.activeFocus, true);
            compare(escaped.visualFocus, true);
            const nextRing = ringOf(escaped);
            verify(nextRing !== undefined, "the next linked word owns its ring");
            compare(nextRing.visible, true);
            compare(linked.visualFocus, false);
            compare(ring.visible, false);
            keyClick(Qt.Key_Backtab);
            compare(linked.activeFocus, true);
            compare(linked.visualFocus, true);
            compare(ring.visible, true);
        }

        function test_each_reference_has_its_own_pointer_and_keyboard_target() {
            compare(multiple.plain, "notes: notes or notes.");
            compare((labelOf(multiple).text.match(/<font color=/g) || []).length, 2);
            compare(multiple.underlined.length, 2);
            const spans = multiple.underlined;
            multiplePages.clear();
            for (const span of spans)
                mouseClick(multiple, (span.left + span.right) / 2, multiple.height / 2);
            compare(multiplePages.count, 2);
            compare(multiplePages.signalArguments[0][0], "file:%2Fhome%2FMy%20Home%2Fnotes%20%28draft%29.md");
            compare(PageReference.file(multiplePages.signalArguments[0][0]), "/home/My Home/notes (draft).md");
            compare(multiplePages.signalArguments[1][0], "vgs.voice");
            compare(multiplePages.signalArguments[1][1], "Setup");
            mouseClick(multiple, 2, multiple.height / 2);
            compare(multiplePages.count, 2, "the same label outside a reference is plain text");
            multiple.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Home);
            const firstBox = multiple.linkBox.x;
            keyClick(Qt.Key_Return);
            keyClick(Qt.Key_Right);
            verify(multiple.linkBox.x > firstBox, "the ring follows the keyboard target");
            keyClick(Qt.Key_Space);
            compare(multiplePages.count, 4);
            compare(multiplePages.signalArguments[2][0], "file:%2Fhome%2FMy%20Home%2Fnotes%20%28draft%29.md");
            compare(multiplePages.signalArguments[3][0], "vgs.voice");
            keyClick(Qt.Key_Left);
            keyClick(Qt.Key_Enter);
            compare(multiplePages.signalArguments[4][0], "file:%2Fhome%2FMy%20Home%2Fnotes%20%28draft%29.md");
            multiplePages.clear();
            keyClick(Qt.Key_Right);
            compare(multiplePages.count, 0, "navigation opens no target");
        }

        function test_an_explicit_link_keeps_its_activation() {
            explicitPages.clear();
            explicitActivated.clear();
            explicit.forceActiveFocus();
            keyClick(Qt.Key_Return);
            const span = explicit.underlined[1];
            mouseClick(explicit, (span.left + span.right) / 2, explicit.height / 2);
            compare(explicitActivated.count, 2);
            compare(explicitPages.count, 0);
        }

        function test_a_page_reference_draws_its_words_as_the_link() {
            compare(paged.plain, "Add a key on the Models page first.");
            compare(paged.Accessible.name, "Add a key on the Models page first.");
            const html = labelOf(paged).text;
            compare((html.match(/<font color=/g) || []).length, 1);
            verify(html.indexOf(">Models page</font>") !== -1, "the reference's words are the link");
            compare(paged.underlined.length, 1, "the words draw one underline");
            compare(html.indexOf("page:"), -1, "the target is not drawn");
            compare(paged.activeFocusOnTab, true);
        }

        function test_a_page_reference_activates_its_page_and_tab() {
            pagedPages.clear();
            pagedActivated.clear();
            tablessPages.clear();
            paged.forceActiveFocus();
            keyClick(Qt.Key_Return);
            compare(pagedPages.count, 1);
            compare(pagedPages.signalArguments[0][0], "acme.models");
            compare(pagedPages.signalArguments[0][1], "Setup");
            compare(pagedActivated.count, 0, "a page reference emits no plain activation");
            mouseClick(tabless, 4, tabless.height / 2);
            compare(tablessPages.count, 1);
            compare(tablessPages.signalArguments[0][0], "acme.models");
            compare(tablessPages.signalArguments[0][1], "", "a reference without a tab names none");
        }

        // The file reference travels as the page `file:<path>`, which the
        // owner hands on to the core's reference route.
        function test_a_file_reference_activates_its_path() {
            compare(filed.plain, "Shorten AGENTS.md first.");
            compare(labelOf(filed).text.indexOf("file:"), -1, "the target is not drawn");
            compare(filed.underlined.length, 1, "the words draw one underline");
            compare(filed.activeFocusOnTab, true);
            filedPages.clear();
            filedActivated.clear();
            filed.forceActiveFocus();
            keyClick(Qt.Key_Return);
            mouseClick(filed, filed.linkBox.x + filed.linkBox.width / 2, filed.linkBox.y + filed.linkBox.height / 2);
            compare(filedPages.count, 2, "the keyboard and the pointer each activate it once");
            for (const args of filedPages.signalArguments) {
                compare(args[0], "file:~%2F.local%2Fshare%2Fvgs%2FAGENTS.md");
                compare(args[1], "");
            }
            compare(filedActivated.count, 0, "a file reference emits no plain activation");
        }

        function test_a_link_the_text_does_not_hold_gives_way_to_the_page_reference() {
            compare(elsewhere.plain, "Choose it in Models.");
            compare(elsewhere.words, "Models");
            compare(elsewhere.linked, true);
            elsewherePages.clear();
            elsewhere.forceActiveFocus();
            keyClick(Qt.Key_Return);
            compare(elsewherePages.count, 1);
            compare(elsewherePages.signalArguments[0][0], "acme.models");
            compare(elsewherePages.signalArguments[0][1], "Settings");
        }

        function test_a_reference_to_no_page_reads_as_its_words() {
            compare(pageless.plain, "Turn it on in Plugins.");
            compare(pageless.linked, false);
            compare(pageless.activeFocusOnTab, false);
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

        // Each case: the item, the line its link is on and what its ring
        // holds: the words and the punctuation against their end.
        function test_focus_ring_stands_clear_of_the_link_words_on_every_side() {
            const cases = [
                [inline, 0, "hyprland.lua"],
                [wrapped, 1, "hyprland.lua"],
                [closing, 0, "hyprland.lua."]
            ];
            const clear = Theme.focusRing.offset;
            for (const [item, line, held] of cases) {
                const label = labelOf(item);
                const box = item.linkBox;
                const baseline = line * label.lineBox + label.baselineOffset;
                const x = line === 0 ? font.advanceWidth(item.drawn.slice(0, item.run[0])) : 0;
                fuzzyCompare(box.x, x, 0.5, "the box starts at the words");
                fuzzyCompare(box.width, font.advanceWidth(held), 1, "the box is as wide as the words and the mark against them");
                compare(box.y, Math.floor(baseline + font.tightBoundingRect(held).y), "the box starts at the words' highest ink");
                compare(box.y + box.height, Math.ceil(baseline + label.underlineOffset + item.underlineThickness), "the box ends at the underline's bottom");
                verify(box.y > line * label.lineBox, "the box starts at the words' ink, not their line box: " + box.y);
                item.forceActiveFocus(Qt.TabFocusReason);
                const ring = ringOf(item);
                verify(ring !== undefined && ring.visible, "the focused link draws its ring");
                const at = ring.mapToItem(item, 0, 0);
                const stroke = ring.border.width;
                compare(box.x - (at.x + stroke), clear, "clear of the words' start");
                compare(at.x + ring.width - stroke - (box.x + box.width), clear, "clear of the words' end");
                compare(box.y - (at.y + stroke), clear, "clear of the words' top");
                compare(at.y + ring.height - stroke - (box.y + box.height), clear, "clear of the underline");
                verify(ring.width < item.width, "the ring leaves the prose outside it");
            }
            // The glyph before the words stands a pixel past the ring's outer
            // edge, and no further than one gap space more. The text after
            // the words keeps its spacing.
            const reach = Theme.focusRing.offset + Theme.focusRing.width + 1;
            const glue = font.advanceWidth("\u202f");
            for (const item of [inline, wrapped, closing]) {
                const start = item.drawn.indexOf("hyprland.lua");
                const before = item.drawn.slice(0, start).match(/[ \u202f]*$/)[0];
                verify(font.advanceWidth(before) >= reach, "room for the ring: " + font.advanceWidth(before));
                if (before.indexOf("\u202f") !== -1)
                    verify(font.advanceWidth(before) - glue < reach, "no wider than the ring needs: " + font.advanceWidth(before));
                verify(!before.endsWith("\u202f"), "no line starts with a gap before the words");
                compare(item.drawn.slice(start), item.plain.slice(item.plain.indexOf("hyprland.lua")), "the text from the words on is drawn as written");
                compare(item.drawn.replace(/\u202f/g, ""), item.plain, "the gaps are all the drawn text adds");
            }
            verify(inline.drawn.indexOf("\u202f") !== -1, "a word space narrower than the ring's room gets the gap");
            verify(labelOf(inline).text.indexOf("&#x202f; <font") !== -1, "styled text keeps the gap only as its entity");
            compare(inline.Accessible.name, inline.plain, "the gap is drawn, not read out");
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

        function underlines(item) {
            return descendants(item).filter(child => child.modelData !== undefined);
        }

        // Each case: the item, the baseline of the line its link is on, and
        // the text on that line under the link. Every run of its underline
        // starts a clear pixel row under the font's descent, which the
        // words' lowest ink stays above.
        function test_the_underline_keeps_a_row_under_the_descenders() {
            const cases = [
                [descending, labelOf(descending).baselineOffset, "Remove key"],
                [wrapped, labelOf(wrapped).baselineOffset + labelOf(wrapped).lineBox, "hyprland.lua"]
            ];
            for (const [item, baseline, inked] of cases) {
                const runs = underlines(item);
                compare(runs.length, 1, item.text + " draws one underline");
                const top = runs[0].y;
                const ink = font.tightBoundingRect(inked);
                verify(top >= baseline + font.descent + 1, item.text + ": the underline starts " + (top - baseline) + " px under the baseline, the descent is " + font.descent);
                verify(top - (baseline + ink.y + ink.height) >= 1, item.text + ": the words' ink ends " + (top - baseline - ink.y - ink.height) + " px over the underline");
                compare(runs[0].height, Math.max(1, Math.round(font.lineWidth)));
            }
        }

        // The underline runs under each occurrence alone, from its first
        // glyph to its last one's end.
        function test_the_underline_runs_under_the_words() {
            const runs = underlines(inline);
            compare(runs.length, 1);
            const start = font.advanceWidth(inline.drawn.slice(0, inline.run[0]));
            verify(Math.abs(runs[0].x - start) <= 1, "the underline starts at the words: " + runs[0].x + ", not " + start);
            verify(Math.abs(runs[0].width - words.advanceWidth) <= 1, "the underline is the words' width: " + runs[0].width + ", not " + words.advanceWidth);
            compare(underlines(linked).length, 2, "each occurrence is underlined");
            compare(underlines(plain).length, 0);
            compare(underlines(missing).length, 0);
        }

        function test_the_link_and_its_underline_take_the_handed_colour() {
            verify(!Qt.colorEqual(hosted.linkColor, Theme.color.accent), "the handed colour is not the accent");
            verify(labelOf(hosted).text.indexOf("<font color=\"" + hosted.linkColor + "\">hyprland.lua</font>") !== -1, labelOf(hosted).text);
            verify(Qt.colorEqual(underlines(hosted)[0].color, hosted.linkColor), "the underline draws " + underlines(hosted)[0].color);
            verify(Qt.colorEqual(inline.linkColor, Theme.color.accent), "a link handed no colour draws the accent");
            verify(Qt.colorEqual(underlines(inline)[0].color, Theme.color.accent));
        }

        // Hover is the underline's thickness: the resting one plus
        // `linkText.underlineHover`, while the pointer is on the words. Its
        // name sorts it before the click tests: after a mouseClick the
        // runner's moves leave the area's containsMouse set (this file under
        // scripts/qml-unit.sh on 2026-10-13).
        function test_hover_thickens_the_underline_only_under_the_pointer() {
            const rest = Math.max(1, Math.round(font.lineWidth));
            const run = underlines(inline)[0];
            verify(Theme.linkText.underlineHover > 0, "the hover token adds thickness");
            mouseMove(root, root.width - 1, root.height - 1);
            tryCompare(inline, "hoveredLink", false);
            compare(run.height, rest);
            mouseMove(inline, inline.linkBox.x + inline.linkBox.width / 2, inline.height / 2);
            tryCompare(inline, "hoveredLink", true);
            compare(run.height, rest + Theme.linkText.underlineHover);
            mouseMove(inline, before.advanceWidth / 2, inline.height / 2);
            tryCompare(inline, "hoveredLink", false);
            compare(run.height, rest, "the words before the link draw the resting underline");
            mouseMove(inline, inline.linkBox.x + inline.linkBox.width / 2, inline.height / 2);
            tryCompare(inline, "hoveredLink", true);
            mouseMove(root, root.width - 1, root.height - 1);
            tryCompare(inline, "hoveredLink", false);
            compare(run.height, rest, "the underline is back at rest on exit");
        }

        function test_pointer_activates_only_the_link() {
            mouseClick(linked, 4, linked.height / 2);
            compare(activated.count, 1);
            mouseClick(linked, linked.width - 4, linked.height / 2);
            compare(activated.count, 1);
            mouseClick(inline, before.advanceWidth / 2, inline.height / 2);
            compare(inlineActivated.count, 0, "the words before the link do not activate it");
            mouseClick(inline, inline.linkBox.x + inline.linkBox.width / 2, inline.height / 2);
            compare(inlineActivated.count, 1, "the link's words activate it");
        }
    }
}
