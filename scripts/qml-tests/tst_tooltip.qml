import QtQuick
import QtQuick.Templates as T
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// A tooltip's page references through the stand-in popup window. A tooltip
// with no link closes when the pointer leaves its item. A `pageLinks`
// tooltip whose line names a page stays open while the pointer goes from
// the item into the popup and closes after it left the popup. Without
// `pageLinks` the line draws the reference's words alone. Opened by
// focus, Tab makes the link current and draws its ring round the words,
// Enter emits `pageActivated` with the page and tab, and Escape closes it
// with the focus still on the item. The crossing waits on `tooltip.delay`
// in real time, so it proves the timer's wiring; the nested sandbox proves
// the real pointer, the real keys and the popup's surface. With the
// user's glass on, the tooltip draws its glass solid.
Item {
    id: root
    width: 300
    height: 200

    // A focusable item, as BarItem is: it hands its keys to its tooltip.
    component Anchor: T.Button {
        id: anchor
        property alias tip: tip
        property alias pageLinks: tip.pageLinks
        property alias title: tip.text
        property alias details: tip.details
        width: 60
        height: 26
        focusPolicy: Qt.TabFocus
        Keys.onPressed: event => { event.accepted = tip.takeKey(event); }
        Tooltip { id: tip }
    }

    Anchor { id: bare; title: "Sound" }
    Anchor { id: linked; x: 100; pageLinks: true; title: "Jarvis is not set up"; details: ["Finish in [Setup](page:acme.probe/Setup)."] }
    Anchor { id: unrouted; x: 200; title: "Jarvis is not set up"; details: ["Finish in [Setup](page:acme.probe/Setup)."] }
    Anchor { id: after; y: 60; title: "Next" }
    // A linked detail line wider than the tooltip wraps, and the line under
    // it starts below its last line.
    Anchor { id: wrapping; y: 120; pageLinks: true; title: "Jarvis heard nothing"
        details: ["Choose a working microphone in [Microphone](page:acme.probe/Settings/microphone), then talk again, and check that the microphone is not muted.", "AI model: Fixture"] }
    SignalSpy { id: activations; target: linked.tip; signalName: "pageActivated" }

    TestCase {
        name: "tooltip"
        when: windowShown

        function init() {
            UnitTheme.reset();
            Theme.appearanceInput = "";
            compare(UnitTheme.override({ tooltip: { delay: 200 } }), "ok");
            activations.clear();
            away();
            root.forceActiveFocus();
        }

        function cleanup() {
            for (const item of [bare, linked, unrouted, after, wrapping]) {
                item.tip.shown = false;
                tryCompare(item.tip, "opened", false);
            }
        }

        function away() { mouseMove(root, root.width - 1, root.height - 1); }

        function descendants(node) {
            let out = [];
            for (const child of node.children) out = out.concat([child], descendants(child));
            return out;
        }

        function named(tip, name) {
            return descendants(tip.tracker.popup.contentItem).filter(child => child.objectName === name);
        }

        // The stand-in popup opens at the screen's origin, where the
        // offscreen platform's cursor rests, so a new popup reads the
        // pointer on it until a move says otherwise.
        function opened(item) {
            tryCompare(item.tip, "opened", true);
            const popup = item.tip.tracker.popup;
            mouseMove(popup.contentItem, -10, -10);
            tryCompare(popup, "pointerOver", false);
        }

        function hoverOpen(item) {
            mouseMove(item, item.width / 2, item.height / 2);
            opened(item);
        }

        // The fill the tooltip draws, read from its surface's body, as
        // tst_glasssurface.qml reads it.
        function drawnFill(tip) { return named(tip, "tooltipSurface")[0].children[1].color; }

        // With the user's glass on, the tooltip draws its glass solid, the
        // fill check-theme-contrast.js judges its text on, though its
        // popup is a transparent window where glass is drawn. Control: the
        // same surface handed no `solidOnly` draws the translucent fill,
        // which the check refuses.
        function test_glass_on_draws_the_tooltip_solid() {
            Theme.appearanceInput = JSON.stringify({ glass: "on" });
            hoverOpen(bare);
            const surface = named(bare.tip, "tooltipSurface")[0];
            const solid = Theme.glassSolid(surface.fill);
            verify(!Qt.colorEqual(solid, surface.fill), "the solid fill is not the glass fill");
            compare([surface.on, surface.solid], [true, true]);
            verify(Qt.colorEqual(drawnFill(bare.tip), solid), "glass on draws the solid fill: " + drawnFill(bare.tip));
            surface.solidOnly = false;
            compare(surface.drawn, true, "control: without solidOnly the popup draws glass");
            verify(!Qt.colorEqual(drawnFill(bare.tip), solid), "control: the translucent fill is not the solid one");
            surface.solidOnly = true;
            Theme.appearanceInput = "";
        }

        // A linked detail line that wraps takes the height of its lines, so
        // the next detail line starts under it, not over its second line.
        function test_a_wrapped_link_line_keeps_the_next_line_below_it() {
            compare(UnitTheme.override({ tooltip: { maxWidth: 160 } }), "ok");
            hoverOpen(wrapping);
            const rows = named(wrapping.tip, "tooltipDetailRow");
            compare(rows.length, 2);
            const link = named(wrapping.tip, "tooltipLink").find(item => item.text.indexOf("Microphone") !== -1);
            verify(link !== undefined, "the first detail line draws its link");
            verify(link.lineCount > 1, "the linked line wraps");
            verify(rows[0].height >= link.height, "the row takes the wrapped line's height");
            verify(rows[1].y >= rows[0].y + link.height, "the next line starts below the wrapped line");
        }

        function test_a_tooltip_with_no_link_closes_when_the_pointer_leaves() {
            hoverOpen(bare);
            compare(named(bare.tip, "tooltipLink").length, 0);
            away();
            compare(bare.tip.opened, false);
        }

        function test_the_pointer_crosses_into_a_linked_tooltip() {
            hoverOpen(linked);
            const popup = linked.tip.tracker.popup;
            away();
            compare(linked.tip.opened, true, "the tooltip stays while the pointer crosses the gap");
            mouseMove(popup.contentItem, popup.width / 2, popup.height / 2);
            tryCompare(popup, "pointerOver", true);
            // Longer than the grace: the pointer on the popup holds it open.
            wait(3 * Theme.tooltip.delay);
            compare(linked.tip.opened, true, "the pointer on the popup holds it open");
            mouseMove(popup.contentItem, -10, -10);
            tryCompare(linked.tip, "opened", false);
        }

        function test_an_owner_that_routes_no_link_draws_the_words() {
            hoverOpen(unrouted);
            compare(named(unrouted.tip, "tooltipLink").length, 0);
            const lines = named(unrouted.tip, "tooltipDetailLine");
            compare(lines.length, 1);
            compare(lines[0].text, "Finish in Setup.");
            compare(lines[0].visible, true);
            // The defaults' faint text falls short on the solid glass fill,
            // so the line draws the tooltip's detail colour, not its role's.
            verify(!Qt.colorEqual(Theme.tooltip.detail, Theme.text.itemHint.color), "the defaults' detail colour is not the role's");
            verify(Qt.colorEqual(lines[0].color, Theme.tooltip.detail), "the detail line draws tooltip.detail: " + lines[0].color);
            away();
            compare(unrouted.tip.opened, false, "it closes on leave as a tooltip with no link does");
            hoverOpen(linked);
            compare(named(linked.tip, "tooltipLink").length, 1);
            compare(named(linked.tip, "tooltipLink")[0].plain, "Finish in Setup.");
            compare(named(linked.tip, "tooltipDetailLine")[0].visible, false);
        }

        function test_the_keyboard_reaches_and_opens_the_link() {
            linked.forceActiveFocus(Qt.TabFocusReason);
            opened(linked);
            const link = named(linked.tip, "tooltipLink")[0];
            const ring = descendants(link).find(child => child.target === link && child.border !== undefined);
            verify(ring !== undefined, "the link owns its ring");
            compare(ring.visible, false);
            keyClick(Qt.Key_Return);
            compare(activations.count, 0, "Enter on the item opens no link before Tab");
            keyClick(Qt.Key_Tab);
            compare(linked.activeFocus, true, "the first Tab stays on the item");
            compare(linked.tip.currentLine, 1);
            compare(ring.visible, true);
            verify(ring.parent.width < link.width, "the ring goes round the words, not the line: " + ring.parent.width + " of " + link.width);
            const popup = linked.tip.tracker.popup;
            const ringBottom = ring.mapToItem(popup.contentItem, 0, ring.height).y;
            compare(popup.height - ringBottom, Theme.focusRing.offset + Theme.surface.border, "the last line's ring stands clear of the tooltip's border");
            keyClick(Qt.Key_Return);
            compare(activations.count, 1);
            compare(activations.signalArguments[0][0], "acme.probe");
            compare(activations.signalArguments[0][1], "Setup");
            tryCompare(linked.tip, "opened", false);
            compare(linked.activeFocus, true);

            // Escape closes it with the focus on the item, and it stays
            // closed until the focus left and came back.
            root.forceActiveFocus();
            linked.forceActiveFocus(Qt.TabFocusReason);
            opened(linked);
            keyClick(Qt.Key_Escape);
            compare(linked.tip.opened, false);
            compare(linked.activeFocus, true);
            wait(3 * Theme.tooltip.delay);
            compare(linked.tip.opened, false);

            // Past the last link, Tab goes on to the next item.
            root.forceActiveFocus();
            linked.forceActiveFocus(Qt.TabFocusReason);
            opened(linked);
            keyClick(Qt.Key_Tab);
            compare(linked.activeFocus, true);
            keyClick(Qt.Key_Tab);
            compare(linked.activeFocus, false, "the second Tab leaves the item");
            tryCompare(linked.tip, "opened", false);
        }

        // Lines that refresh while the tooltip is open keep the link Tab
        // reached, so Enter opens it, also where a line above it came and
        // moved it down; a refresh whose line links elsewhere or holds no
        // link drops it, and Enter is the item's again.
        function test_a_refresh_keeps_the_link_tab_reached_data() {
            return [
                { tag: "the same lines", details: ["Finish in [Setup](page:acme.probe/Setup)."], line: 1, opens: 1 },
                { tag: "a line above it changed", title: "Jarvis is starting", details: ["Finish in [Setup](page:acme.probe/Setup)."], line: 1, opens: 1 },
                { tag: "a line came above it", details: ["AI model: Fixture", "Finish in [Setup](page:acme.probe/Setup)."], line: 2, opens: 1 },
                { tag: "another target", details: ["Finish in [Setup](page:acme.other/Setup)."], line: -1, opens: 0 },
                { tag: "the link is gone", details: ["Jarvis is ready"], line: -1, opens: 0 },
            ];
        }

        function test_a_refresh_keeps_the_link_tab_reached(row) {
            const before = { title: linked.title, details: linked.details };
            linked.forceActiveFocus(Qt.TabFocusReason);
            opened(linked);
            keyClick(Qt.Key_Tab);
            compare(linked.tip.currentLine, 1);
            if (row.title !== undefined) linked.title = row.title;
            linked.details = row.details;
            compare(linked.tip.currentLine, row.line);
            keyClick(Qt.Key_Return);
            compare(activations.count, row.opens);
            linked.title = before.title;
            linked.details = before.details;
        }
    }
}
