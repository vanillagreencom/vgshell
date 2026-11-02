import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.jarvis"
import "../../shell/plugins/vgs.jarvis/Appearance.js" as Appearance

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
        property bool bubbleWanted: true
        property string focusedOutput: "unit"
        property var consoleBox: null
        property string consoleKey: ""
        property string heldKey: ""
        property var effectiveKeys: ({ stop: "SUPER+ALT+PERIOD", confirm: "SUPER+ALT+Y" })
        property var values: ({})
        property var shell: ({ status: { values: service.values }, surfaces: { openPage: () => "ok" } })
        function attachBubble(item) {}
        function detachBubble(item) {}
        function intent(name) {}
        function shownApproval(item, hold) {}
        function cancelApproval(hold) {}
        function confirmApproval(hold, how) {}
    }

    Rectangle { id: ground; anchors.fill: parent; color: "#ffffff" }
    // The layer's width: a narrow one puts the screen's edges near the
    // content.
    property real layerWidth: width
    Bubble { id: bubble; width: root.layerWidth; height: root.height; screen: ({ name: "unit" }); service: service }

    function session(over) {
        const s = { gen: 1, check: { kind: "none" }, gate: { kind: "up" }, fault: { kind: "none" }, approval: { kind: "none" },
            action: { kind: "none" }, playback: { kind: "none" }, speech: { kind: "none" }, turn: { kind: "none" },
            capture: { kind: "closed" }, mute: { kind: "off" }, voiceMute: { kind: "off" }, engine: { kind: "chained" } };
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
            service.values = {};
            service.sessionState = null;
            mouseMove(root, 1, 1);
        }
        function all(item, out) {
            for (const child of item.children) {
                out.push(child);
                all(child, out);
            }
            return out;
        }
        function named(name) { return all(bubble, []).find(item => item.objectName === name); }
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
                { tag: "listening with its icons, dark", light: false, hover: true, state: root.session({ capture: { kind: "open", mode: "hold" } }) },
                { tag: "speaking with its words and icons, light", light: true, hover: true, words: true,
                  state: root.session({ playback: { kind: "playing" }, voiceMute: { kind: "on" } }) }
            ];
        }

        function test_every_item_sits_on_the_dark_field(data) {
            if (data.words)
                service.values = { transcript: { role: "assistant", gen: 1, text: "The meeting moved to Thursday at three, and the room is the same as last week." } };
            judge(data.state, data.light, data.hover === true);
        }

        // In light mode the field under the content peaks at 0.60 and every
        // line draws an ink measured on it over the "Pink Courtyard"
        // wallpaper, its text shadow drawn, by the revision 5 method: its
        // lowest WCAG ratio against the lightest pixel 2-4 px from its
        // glyphs that the orb does not draw (VGS-2210 round 3b-2, software
        // OpenGL). 0.60 is the lowest uniform peak at which every line
        // reads 4.5:1. Each figure is the 0.60 reading.
        function test_light_text_draws_the_measured_inks_data() {
            const widest = "Move 3 files to Documents?\n~/Downloads/invoices-october/\ninvoice-1031.pdf, invoice-1017.pdf, invoice-1003.pdf";
            return [
                { tag: "the widest prompt", state: root.held(widest, true), inks: [
                    { text: "Move 3 files to Documents?", ink: "#ffffff" },        // 5.26:1
                    { text: "~/Downloads/invoices-october/", ink: "#e6e8ee" },     // 4.68:1
                    { text: "invoice-1031.pdf, invoice-1017.pdf, invoice-1003.pdf", ink: "#f4f5f8" }, // 5.25:1
                    { text: "Use the button or key to confirm.", ink: "#e6e8ee" }, // 4.84:1
                    { answer: "Cancel", ink: "#f4f5f8" },                           // 4.97:1
                    { answer: "Confirm", ink: "#ffffff" }] },                       // 4.83:1
                { tag: "waiting for the word", state: root.session({ capture: { kind: "open", mode: "armed" } }), inks: [
                    { text: "Say Hey Jarvis", ink: "#ffffff" }] },                  // 4.79:1
                { tag: "listening", state: root.session({ capture: { kind: "open", mode: "hold" } }), inks: [
                    { text: "Listening", ink: "#ffffff" }] },                       // 4.98:1
                { tag: "speaking with its words", words: true, state: root.session({ playback: { kind: "playing" }, voiceMute: { kind: "on" } }), inks: [
                    { text: "Speaking", ink: "#ffffff" },                           // 5.02:1
                    { words: true, ink: "#f4f5f8" }] },                             // 5.07:1, the newest line
                // The action and its link share one ink; the link keeps its
                // underline at rest, so colour is not what marks it.
                { tag: "a fault", state: root.session({ fault: { kind: "error", reason: "brain=exit" } }), inks: [
                    { action: true, ink: "#e6e8ee" }] }                             // 4.92:1, action and link
            ];
        }

        function test_light_text_draws_the_measured_inks(data) {
            compare(UnitTheme.override({ scheme: { mode: "light" }, motion: { scale: 0 } }), "ok");
            if (data.words)
                service.values = { transcript: { role: "assistant", gen: 1, text: "The meeting moved to Thursday at three." } };
            service.sessionState = data.state;
            verify(renderedFrame(root), "the overlay lays out");
            compare(root.look.field.content.peak, 0.6, "the light field's measured peak");
            const items = all(bubble, []);
            for (const want of data.inks) {
                let drawn;
                if (want.action) {
                    const action = items.find(item => item.linkBox !== undefined && item.linked && bubble.drawn(item));
                    verify(action !== undefined, "the fault's action draws its link");
                    compare(action.standalone, false, "the link sits in running text, underlined at rest");
                    compare(String(action.linkColor), want.ink, "the fault's link in light mode");
                    drawn = action.color;
                } else if (want.answer !== undefined) {
                    const answer = items.find(item => item.shimmer !== undefined && item.entry === undefined && item.text === want.answer);
                    verify(answer !== undefined, "the " + want.answer + " answer draws");
                    drawn = answer.foreground;
                } else if (want.words) {
                    const lines = items.filter(item => item.role === "body" && item.text !== "" && bubble.drawn(item) && item.text.indexOf("Thursday") !== -1);
                    verify(lines.length > 0, "the words draw");
                    drawn = lines[0].color;
                } else {
                    const line = items.find(item => item.text === want.text && item.color !== undefined && bubble.drawn(item));
                    verify(line !== undefined, want.text + " draws");
                    drawn = line.color;
                }
                compare(String(drawn), want.ink, (want.text || want.answer || "the words") + " in light mode");
            }
        }
    }
}
