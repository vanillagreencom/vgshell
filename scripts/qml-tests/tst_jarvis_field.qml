import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.jarvis"
import "../../shell/plugins/vgs.jarvis/Appearance.js" as Appearance
import "../../shell/plugins/vgs.jarvis/Session.js" as Session

// Jarvis's overlay draws every content item where its field is dark: each
// line, answer, the words and the icon row sit where the field's alpha is
// at least 60% of their box's peak, at the widest and a narrow approval
// prompt, while listening with the icon row shown and while Jarvis speaks
// with its words shown, in both modes. The
// field is read alone from the drawn bubble under scripts/qml-unit.sh's
// software OpenGL: with the content hidden, alpha a over a white and a
// black ground reads a = 1 - (white - black) / 255, whatever the ink and
// the orb's halo add.
Item {
    id: root
    width: 1180
    height: 740

    readonly property var look: Theme.appearance(Appearance.TOKENS, Appearance.LIGHT)

    QtObject {
        id: service
        property var sessionState: null
        property var microphoneMute: ({ kind: "ready", muted: false })
        property bool bubbleWanted: true
        property string focusedOutput: "unit"
        property var consoleBox: null
        property string consoleKey: ""
        property string heldKey: ""
        property var effectiveKeys: ({ stop: "SUPER+CTRL+X", confirm: "SUPER+CTRL+Y" })
        property var values: ({})
        property var shell: ({ settings: { voiceProvider: "local" }, status: { values: service.values }, surfaces: { openPage: () => "ok" } })
        function attachBubble(item) {}
        function detachBubble(item) {}
        function intent(name) {}
        property var acknowledged: []
        function shownApproval(item, hold) { acknowledged = acknowledged.concat([hold]); }
        function cancelApproval(hold) {}
        function confirmApproval(hold, how) {}
    }

    Rectangle { id: ground; anchors.fill: parent; color: "#ffffff" }
    // The layer's width: a narrow one puts the screen's edges near the
    // content.
    property real layerWidth: width
    Bubble { id: bubble; width: root.layerWidth; height: root.height; screen: ({ name: "unit" }); service: service }
    QtObject { id: presentedHost; property bool presented: true; property bool visible: true }

    function session(over) {
        const s = Object.assign(JSON.parse(JSON.stringify(Session.initial())), { gen: 1, gate: { kind: "up" } });
        for (const key in over) s[key] = over[key];
        return s;
    }
    function held(text, physical) {
        return session({ approval: { kind: "held", id: "a", gen: 1, digest: "d", purpose: "action", tool: "files.move", physical: physical, text: text } });
    }

    UnitCase {
        name: "jarvis-field"
        when: windowShown

        function init() {
            UnitTheme.reset();
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            root.layerWidth = root.width;
            ground.color = "#ffffff";
            service.bubbleWanted = true;
            service.consoleBox = null;
            service.consoleKey = "";
            service.heldKey = "";
            service.acknowledged = [];
            service.values = {};
            service.sessionState = null;
            mouseMove(root, 1, 1);
        }
        function cleanup() { QsWindow.window = null; }
        function all(item, out) {
            for (const child of item.children) {
                out.push(child);
                all(child, out);
            }
            return out;
        }
        function named(name) { return all(bubble, []).find(item => item.objectName === name); }

        // Service publishes the existing asynchronous console answer after
        // the hold arrives. Pixels from the window must stay empty until
        // then; this file's software OpenGL paints the real shadow layers.
        // A failed read and no console both publish null in Service.
        function test_a_late_console_answer_gates_the_first_painted_frame_data() {
            const rows = [];
            for (const light of [false, true])
                for (const result of ["over-console", "none-or-failed"])
                    rows.push({ tag: (light ? "light-" : "dark-") + result, light: light, result: result });
            return rows;
        }

        function test_a_late_console_answer_gates_the_first_painted_frame(data) {
            if (data.light) compare(UnitTheme.override({ scheme: { mode: "light" } }), "ok");
            QsWindow.window = presentedHost;
            service.bubbleWanted = false;
            verify(renderedFrame(root));
            const empty = grabImage(root);
            service.heldKey = "1:a";
            service.sessionState = root.held("Delete draft.txt?\n/home/fixture/draft.txt", true);
            service.bubbleWanted = true;
            const overlay = named("overlay");
            verify(overlay !== undefined);
            for (let frame = 0; frame < 2; frame++) {
                verify(renderedFrame(root), "the window paints while the console answer is pending");
                verify(grabImage(root).equals(empty), "no bottom frame paints before the current hold's console answer");
                compare(service.acknowledged.length, 0, "an unplaced hold is not acknowledged");
            }
            const over = { output: "unit", x: 0, y: 0, width: root.width, height: root.height };
            service.consoleBox = data.result === "over-console" ? over : null;
            service.consoleKey = service.heldKey;
            verify(renderedFrame(root), "the first ready frame paints");
            verify(!grabImage(root).equals(empty), "the answered hold paints its prompt");
            const top = () => fuzzyCompare(overlay.y, root.look.layout.margin, 0.5);
            const bottom = () => fuzzyCompare(overlay.y + overlay.height, root.height - root.look.layout.margin, 0.5);
            if (data.result === "over-console") top(); else bottom();
            tryVerify(() => service.acknowledged.some(hold => hold.id === "a"), 2000, "the placed frame acknowledges the hold");

            // A later window event retains this hold's consoleKey, so its
            // read keeps the card painted and re-places it on completion.
            verify(renderedFrame(root));
            verify(!grabImage(root).equals(empty), "a same-hold read keeps the card painted");
            service.consoleBox = data.result === "over-console" ? null : over;
            verify(renderedFrame(root));
            verify(!grabImage(root).equals(empty), "a moved console does not hide the card");
            if (data.result === "over-console") bottom(); else top();

            service.heldKey = "1:b";
            const next = root.held("Delete notes.txt?\n/home/fixture/notes.txt", true);
            next.approval.id = "b";
            service.sessionState = next;
            verify(renderedFrame(root));
            verify(grabImage(root).equals(empty), "a new hold cannot use the previous hold's placement");
        }
        // Each content item that shows, with the peak of the box it sits in.
        function contents() {
            const out = bubble.textItems.filter(item => bubble.drawn(item) && item.height > 0)
                .map(item => ({ name: item.text === undefined ? "words" : String(item.text).slice(0, 24), item: item, peak: root.look.field.content.peak }));
            for (const item of all(bubble, []).filter(item => item.shimmer !== undefined && item.entry === undefined && bubble.drawn(item)))
                out.push({ name: "answer " + item.text, item: item, peak: root.look.field.content.peak });
            if (bubble.iconsShown)
                for (const item of all(bubble, []).filter(item => item.entry !== undefined))
                    out.push({ name: "icon " + item.entry.intent, item: item, peak: root.look.field.icons.peak });
            return out;
        }
        // The field's alpha alone, as a function of a pixel of the root.
        function fieldAlpha() {
            const overlay = named("overlay");
            overlay.opacity = 0;
            ground.color = "#ffffff";
            verify(renderedFrame(root), "the field draws over white");
            const white = grabImage(root);
            ground.color = "#000000";
            verify(renderedFrame(root), "the field draws over black");
            const black = grabImage(root);
            ground.color = "#ffffff";
            overlay.opacity = 1;
            return (x, y) => 1 - (white.green(x, y) - black.green(x, y)) / 255;
        }
        // The lowest field alpha over RECT, a box in the root, and whether
        // it reaches 60% of PEAK; a pixel off the layer reads 0.
        function lowest(alpha, rect) {
            let low = 1;
            for (let y = Math.floor(rect.y); y < Math.ceil(rect.y + rect.height); y++)
                for (let x = Math.floor(rect.x); x < Math.ceil(rect.x + rect.width); x++)
                    low = Math.min(low, x < 0 || y < 0 || x >= root.width || y >= root.height ? 0 : alpha(x, y));
            return low;
        }
        function judge(state, light, hover) {
            if (light) compare(UnitTheme.override({ scheme: { mode: "light" }, motion: { scale: 0 } }), "ok");
            service.sessionState = state;
            if (hover) {
                const orb = all(bubble, []).find(item => item.phase !== undefined && item.capture !== undefined);
                const centre = orb.mapToItem(root, orb.width / 2, orb.height / 2);
                mouseMove(root, centre.x, centre.y);
                tryCompare(bubble, "iconOpacity", 1, 500);
            }
            verify(renderedFrame(root), "the overlay lays out");
            const items = contents();
            verify(items.length >= 2, "the overlay draws its content: " + items.map(entry => entry.name));
            const alpha = fieldAlpha();
            for (const entry of items) {
                const box = entry.item.mapToItem(root, 0, 0, entry.item.width, entry.item.height);
                const low = lowest(alpha, box);
                verify(low >= 0.6 * entry.peak - 0.01, entry.name + " at " + JSON.stringify([box.x, box.y, box.width, box.height]) + " sits where the field reads "
                    + low.toFixed(3) + ", under 60% of " + entry.peak + "; the field's boxes: " + JSON.stringify(bubble.fieldBoxes.map(b => [b.x, b.y, b.w, b.h, b.fade, b.inset])));
            }
            // The control: the widest item widened 200 px each side reaches
            // past the field's dark part, so the check must catch it.
            const widest = items.slice().sort((a, b) => b.item.width - a.item.width)[0];
            const box = widest.item.mapToItem(root, 0, 0, widest.item.width, widest.item.height);
            const planted = lowest(alpha, Qt.rect(box.x - 200, box.y, box.width + 400, box.height));
            verify(planted < 0.6 * widest.peak, "a box widened 200 px each side is caught: " + planted.toFixed(3));
        }

        // On a narrow screen the field's fade shortens so it ends before
        // the screen's side edges, rather than stopping there at a cut.
        function test_the_field_ends_before_a_screen_edge() {
            root.layerWidth = 600;
            service.sessionState = root.held("Move 3 files to Documents?\n~/Downloads/invoices-october/\ninvoice-1031.pdf", true);
            verify(renderedFrame(root), "the overlay lays out");
            const question = bubble.textItems.find(item => item.text === "Move 3 files to Documents?");
            const box = question.mapToItem(root, 0, 0, question.width, question.height);
            verify(box.x <= 100, "the prompt stands near the left edge: " + box.x);
            const alpha = fieldAlpha();
            const y = Math.round(box.y + box.height / 2);
            verify(alpha(0, y) < 0.01, "the field ends before the left edge: " + alpha(0, y).toFixed(3));
            verify(alpha(root.layerWidth - 1, y) < 0.01, "and before the right edge: " + alpha(root.layerWidth - 1, y).toFixed(3));
            verify(lowest(alpha, box) >= 0.6 * root.look.field.content.peak - 0.01, "the prompt still sits on the dark field");
        }

        function test_every_item_sits_on_the_dark_field_data() {
            const widest = "Move 3 files to Documents?\n~/Downloads/invoices-october/\ninvoice-1031.pdf, invoice-1017.pdf, invoice-1003.pdf";
            return [
                { tag: "the widest prompt, dark", state: root.held(widest, true), light: false },
                { tag: "the widest prompt, light", state: root.held(widest, true), light: true },
                { tag: "a narrow prompt, dark", state: root.held("Open Firefox?", false), light: false },
                { tag: "a narrow prompt, light", state: root.held("Open Firefox?", false), light: true },
                { tag: "listening with its icons, dark", light: false, hover: true, state: root.session({ capture: { kind: "open", gen: 1, op: 2, mode: "hold" }, conversation: { kind: "active", purpose: "conversation" } }) },
                { tag: "speaking with its words and icons, light", light: true, hover: true, words: true,
                  state: root.session({ playback: { kind: "playing" }, voiceMute: { kind: "on" } }) }
            ];
        }

        function test_every_item_sits_on_the_dark_field(data) {
            if (data.words)
                service.values = { transcript: { role: "assistant", gen: 1, text: "The meeting moved to Thursday at three, and the room is the same as last week." } };
            judge(data.state, data.light, data.hover === true);
        }

    }
}
