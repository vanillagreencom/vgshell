import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.jarvis"
import "../../shell/plugins/vgs.jarvis/Appearance.js" as Appearance
import "../../shell/plugins/vgs.jarvis/Session.js" as Session

// Jarvis's approval prompt and fault line as the overlay draws them: the
// question and the fault's title in the shared bodyStrong role, the state
// line in label; each line and answer in the mode's ink; and the answers
// as two capsules of equal width at the look's height, Cancel leading and
// quiet, the confirming answer on the theme's accent unless the request
// needs a press, which is the destructive kind. The held request's frame
// acknowledgement and the drawn overlay on a real layer are
// scripts/smoke/rows/jarvis-bubble.sh's.
Item {
    id: root
    width: 640
    height: 720

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
        property var shell: ({ settings: { voiceProvider: "local", orbStyle: "glass-bead" }, status: { values: {} }, surfaces: { openPage: () => {} } })
        function attachBubble(item) {}
        function detachBubble(item) {}
        function intent(name) {}
        property var acknowledged: []
        property var confirmed: null
        function shownApproval(item, hold) { acknowledged = acknowledged.concat([{ item: item, hold: hold }]); }
        function cancelApproval(hold) {}
        function confirmApproval(hold, how) { confirmed = hold; }
        property var always: null
        function alwaysApproval(hold, checked) { always = { hold: hold, checked: checked }; }
        property int logs: 0
        function viewLog() { logs++; }
        property var sent: null
        function sendFault(fault, title) { sent = { reason: fault.reason, title: title }; }
    }

    Bubble { id: bubble; width: root.width; height: root.height; screen: ({ name: "unit" }); service: service }

    // The host window of a layer that has presented its first frame.
    QtObject { id: presentedHost; property bool presented: true; property bool visible: true }
    // A Bubble on a layer of its own size, at the window's top left.
    Component {
        id: sizedBubble
        Bubble {}
    }

    function session(over) {
        const s = Object.assign(JSON.parse(JSON.stringify(Session.initial())), { gen: 1, gate: { kind: "up" } });
        for (const key in over) s[key] = over[key];
        return s;
    }
    readonly property var held: session({ approval: { kind: "held", id: "a", gen: 1, digest: "d", purpose: "action", tool: "files.delete",
        physical: true, text: "Delete draft.txt?\n/home/fixture/draft.txt" } })
    // A held question, which speech can answer.
    readonly property var asked: session({ approval: { kind: "held", id: "q", gen: 1, digest: "d", purpose: "release", tool: "release",
        physical: false, text: "Send the summary to Dana?" } })
    // A held files.write of LINES numbered lines.
    function write(id, lines) {
        const body = [];
        for (let i = 1; i <= lines; i++) body.push("line " + i + " of the new notes");
        return session({ approval: { kind: "held", id: id, gen: 1, digest: "d", purpose: "action", tool: "files.write", physical: false,
            text: "Write notes.txt?\n/home/fixture/notes.txt\n" + body.join("\n") } });
    }

    UnitCase {
        name: "jarvis-prompt"
        when: windowShown

        function all(item, out) {
            for (const child of item.children) {
                out.push(child);
                all(child, out);
            }
            return out;
        }
        function shown(item) {
            for (let at = item; at !== null && at !== bubble; at = at.parent)
                if (!at.visible) return false;
            return true;
        }
        function labelOf(text) {
            const found = displayedTextItems(bubble).filter(item => item.role !== undefined && displayedText(item) === text && shown(item));
            verify(found.length === 1, "one drawn line reads " + JSON.stringify(text) + ", found " + found.length);
            return found[0];
        }
        function answer(text) {
            const found = all(bubble, []).filter(item => item.quiet !== undefined && item.form !== undefined && item.text === text && shown(item));
            verify(found.length === 1, "one drawn answer reads " + text);
            return found[0];
        }
        function put(state) {
            service.sessionState = state;
            verify(renderedFrame(root), "the window draws the overlay");
        }

        function init() {
            UnitTheme.reset();
            service.sessionState = null;
            service.acknowledged = [];
            service.confirmed = null;
            service.always = null;
            service.logs = 0;
            service.sent = null;
            service.microphoneMute = { kind: "ready", muted: false };
            mouseMove(root, root.width - 1, 0);
        }
        function cleanup() { QsWindow.window = null; }

        // A held request drawn on a WIDTH by HEIGHT layer whose window has
        // presented.
        function presentedOn(width, height, state) {
            QsWindow.window = presentedHost;
            const layer = createTemporaryObject(sizedBubble, root, { width: width, height: height, screen: { name: "unit" }, service: service });
            verify(layer !== null, "the sized overlay builds");
            service.sessionState = state;
            return layer;
        }
        // ITEM's box in LAYER's coordinates lies inside it.
        function inside(layer, item) {
            const at = item.mapToItem(layer, 0, 0);
            return at.x >= 0 && at.y >= 0 && at.x + item.width <= layer.width + 0.5 && at.y + item.height <= layer.height + 0.5;
        }
        // Whether LAYER acknowledged the held request ID.
        function acknowledgedOn(layer, id) {
            return service.acknowledged.some(entry => entry.item === layer && entry.hold.id === id);
        }
        function linesOf(layer, text) {
            return displayedTextItems(layer).filter(item => item.role !== undefined && displayedText(item) === text && layer.drawn(item));
        }

        // Always allow stands over the answers only on a card a saved key
        // can cover, unchecked; a click sends the box for that hold, the
        // hold's state checks it, and the answers stay on the layer.
        function test_always_allow_shows_where_a_key_can_cover() {
            const grantable = hold => Object.assign({}, hold, { approval: Object.assign({}, hold.approval,
                { grantable: true, always: false, label: "Send the summary to Dana" }) });
            put(root.held);
            const box = findChild(bubble, "alwaysAllow");
            verify(box !== null, "the box is built");
            verify(!box.visible, "a request no key can cover shows no box");
            put(grantable(root.asked));
            verify(box.visible, "a request a key can cover shows the box");
            verify(!box.checked, "it starts unchecked");
            verify(displayedTextItems(bubble).some(item => displayedText(item).indexOf("Send the summary to Dana") !== -1 && bubble.drawn(item)),
                "the box names what the key covers");
            mouseClick(box);
            verify(service.always !== null && service.always.checked === true, "a click checks the box for this hold");
            const checked = grantable(root.asked);
            checked.approval.always = true;
            put(checked);
            verify(box.checked, "the hold's state draws the box checked");
            const layer = presentedOn(root.width, root.height, grantable(root.asked));
            tryVerify(() => acknowledgedOn(layer, "q"), 2000, "the card with its box is acknowledged");
            verify(findChild(layer, "alwaysAllow").visible, "the sized overlay shows the box");
            for (const name of ["alwaysAllow"]) verify(inside(layer, findChild(layer, name)), name + " stays on the layer");
            verify(layer.inputItems.indexOf(findChild(layer, "alwaysAllow")) !== -1, "the box takes the pointer");
        }

        // An error card offers View log and Send to agent, which reach the
        // service with the fault the card shows.
        function test_an_error_card_offers_its_log_and_an_agent() {
            put(root.session({ fault: { kind: "error", reason: "speech=dictation-idle", category: "other" } }));
            const log = labelOf("View log");
            const agent = labelOf("Send to agent");
            mouseClick(log);
            compare(service.logs, 1);
            mouseClick(agent);
            compare(service.sent.reason, "speech=dictation-idle");
            compare(service.sent.title, bubble.fault.title);
        }

        function test_main_text_is_body_strong_data() {
            return [
                { tag: "the approval question", state: root.held, text: "Delete draft.txt?", role: "bodyStrong" },
                { tag: "the fault title", state: root.session({ fault: { kind: "error", reason: "device-lost", category: "other" } }), title: true, role: "bodyStrong" },
                { tag: "the microphone's line", state: root.session({ conversation: { kind: "active", purpose: "conversation" } }), muted: true, text: "Microphone muted", role: "label" }
            ];
        }

        function test_main_text_is_body_strong(data) {
            if (data.muted) service.microphoneMute = { kind: "ready", muted: true };
            service.sessionState = data.state;
            const text = data.title ? bubble.fault.title : data.text;
            verify(text !== "", "the line has words");
            compare(labelOf(text).role, data.role);
        }

        // The answers are two capsules at the look's height that share the
        // card's row equally, Cancel or No leading, each label on its
        // capsule's centre and neither with a border. Cancel is quiet. The
        // confirming answer stands on the look's tint, whose fill moves
        // under the pointer while its label keeps its ink; on a request
        // that needs a press it is quiet too.
        function test_answers_take_the_looks_form_data() {
            return [
                { tag: "a request that needs a press", state: root.held, cancel: "Cancel", confirm: "Confirm", tinted: false },
                { tag: "a request speech can answer", state: root.write("w", 3), cancel: "Cancel", confirm: "Confirm", tinted: true },
                { tag: "a question", state: root.asked, cancel: "No", confirm: "Yes", tinted: true }
            ];
        }

        function test_answers_take_the_looks_form(data) {
            put(data.state);
            const look = root.look.answer;
            const cancel = answer(data.cancel);
            const confirm = answer(data.confirm);
            verify(look.height !== Theme.size.control.sm && look.height !== Theme.size.control.md,
                "the look's height differs from the shared control heights");
            verify(String(Qt.color(look.tinted.fill)) !== String(Qt.color(look.quiet.fill)), "the tint differs from the quiet fill");
            for (const item of [cancel, confirm]) {
                compare(item.height, look.height);
                compare(item.background.radius, look.radius);
                compare(item.background.border.color.a, 0, item.text + " draws no border");
                const label = item.contentItem.children.find(child => child.role === "button");
                const middle = label.mapToItem(item, 0, 0).x + label.width / 2;
                verify(Math.abs(middle - item.width / 2) <= 1, item.text + "'s label at " + middle + " stands on its capsule's centre, " + item.width / 2);
            }
            compare(cancel.width, confirm.width, "the answers share the row equally");
            compare(cancel.x, 0, "the quiet answer leads");
            compare(confirm.x - (cancel.x + cancel.width), look.gap);
            compare(confirm.x + confirm.width, cancel.parent.width, "the answers fill the card's row");
            const form = data.tinted ? look.tinted : look.quiet;
            tryVerify(() => String(cancel.background.color) === String(Qt.color(look.quiet.fill)), 1000, data.cancel + " rests on the quiet fill: " + cancel.background.color);
            tryVerify(() => String(confirm.background.color) === String(Qt.color(form.fill)), 1000, data.confirm + " rests on its fill: " + confirm.background.color);
            compare(String(cancel.foreground), String(Qt.color(look.quiet.ink)));
            compare(String(confirm.foreground), String(Qt.color(form.ink)));
            mouseMove(confirm, confirm.width / 2, confirm.height / 2);
            tryCompare(confirm, "hovered", true);
            tryVerify(() => String(confirm.background.color) === String(Qt.color(form.hoverFill)), 1000, data.confirm + "'s fill moves under the pointer: " + confirm.background.color);
            compare(String(confirm.foreground), String(Qt.color(form.ink)), "the label keeps its ink under the pointer");
        }

        // The prompt's lines and answers draw the mode's ink, which
        // scripts/check-theme-contrast.js holds to 4.5:1 on its card.
        function test_lines_draw_the_looks_ink_in_both_modes_data() {
            return [{ tag: "dark", light: false }, { tag: "light", light: true }];
        }

        function test_lines_draw_the_looks_ink_in_both_modes(data) {
            if (data.light) compare(UnitTheme.override({ scheme: { mode: "light" } }), "ok");
            put(root.held);
            compare(String(labelOf("Delete draft.txt?").color), String(Qt.color(root.look.ink.question)));
            compare(String(labelOf("/home/fixture/draft.txt").color), String(Qt.color(root.look.ink.path)));
            compare(String(answer("Cancel").foreground), String(Qt.color(root.look.answer.quiet.ink)));
            compare(String(answer("Confirm").foreground), String(Qt.color(root.look.answer.quiet.ink)));
            put(root.asked);
            compare(String(answer("Yes").foreground), String(Qt.color(root.look.answer.tinted.ink)));
            service.microphoneMute = { kind: "ready", muted: true };
            put(root.session({ conversation: { kind: "active", purpose: "conversation" } }));
            compare(String(labelOf("Microphone muted").color), String(Qt.color(root.look.ink.state)));
        }

        // On a layer narrower than the prompt's width the prompt reflows to
        // the overlay's width: the question and the path draw whole inside
        // the layer before the request is acknowledged.
        function test_a_narrow_layer_shows_the_whole_prompt_before_acknowledging() {
            const text = "Delete the quarterly planning notes for the design review?\n/home/fixture/projects/planning/2026/quarterly/design-review-notes.txt";
            const layer = presentedOn(360, root.height, root.session({ approval: { kind: "held", id: "n", gen: 1, digest: "d", purpose: "action",
                tool: "files.delete", physical: false, text: text } }));
            tryVerify(() => acknowledgedOn(layer, "n"), 2000, "the narrow prompt is acknowledged");
            for (const line of text.split("\n")) {
                const drawn = linesOf(layer, line);
                compare(drawn.length, 1, "one drawn line reads " + line);
                verify(inside(layer, drawn[0]), "the line lies inside the 360 px layer: " + line);
                verify(drawn[0].height >= drawn[0].implicitHeight, "the line draws whole: " + line);
            }
        }

        // A payload that fits the room the layer leaves draws whole, so a
        // keyboard user, who cannot scroll the passive layer, reads every
        // line Confirm confirms: a 20-line write on a 1040 px layer, past
        // the look's `layout.payload`, is acknowledged with no line scrolled
        // away.
        function test_a_payload_that_fits_the_layer_draws_whole() {
            const layer = presentedOn(root.width, 1040, root.write("f", 20));
            tryVerify(() => acknowledgedOn(layer, "f"), 2000, "the 20-line write is acknowledged");
            const area = all(layer, []).find(item => item.overflowing !== undefined && layer.drawn(item));
            verify(area !== undefined, "the payload draws");
            const text = area.contentItem.children.find(item => item.role !== undefined);
            verify(text.implicitHeight > root.look.layout.payload, "the payload runs past the look's floor: " + text.implicitHeight);
            verify(!area.overflowing, "no line scrolls away");
            verify(area.height >= text.implicitHeight, "the region holds the whole payload: " + area.height);
            verify(inside(layer, area), "the payload lies inside the layer");
        }

        // A long file's payload scrolls in the room the layer leaves, so a
        // 60-line write on a 1040 px layer keeps its answers on the layer:
        // the request is acknowledged with the region in the pointer's
        // reach, and Confirm answers it.
        function test_a_long_payload_leaves_the_prompt_answerable() {
            const layer = presentedOn(root.width, 1040, root.write("w", 60));
            tryVerify(() => acknowledgedOn(layer, "w"), 2000, "the long write is acknowledged");
            const area = all(layer, []).find(item => item.overflowing !== undefined && layer.drawn(item));
            verify(area !== undefined, "the payload draws in a scrolled region");
            verify(area.overflowing, "the payload runs past the region");
            verify(inside(layer, area), "the region lies inside the layer");
            verify(layer.inputItems.indexOf(area) !== -1, "the region takes the pointer, so the wheel scrolls it");
            const confirm = all(layer, []).find(item => item.quiet !== undefined && item.form !== undefined && item.text === "Confirm" && layer.drawn(item));
            verify(confirm !== undefined && inside(layer, confirm), "Confirm lies inside the layer");
            mouseClick(confirm);
            verify(service.confirmed !== null && service.confirmed.id === "w", "Confirm answers the long write");
        }

        // A payload at the approval bound, 16 KiB (ToolRouter.js
        // RESULT_BYTES), lays out past 16384 px, the maximum texture size of
        // many GPUs; no item in the held request's column draws through a
        // layer taller than the payload's region, so no texture of the
        // payload's whole length is asked for.
        function test_a_payload_at_the_bound_layers_no_texture_past_its_region() {
            const head = "Write notes.txt?\n/home/fixture/notes.txt\n";
            const body = [];
            while (head.length + (body.length + 1) * 2 <= 16 * 1024) body.push("x");
            const text = head + body.join("\n");
            const layer = presentedOn(root.width, 1040, root.session({ approval: { kind: "held", id: "b", gen: 1, digest: "d", purpose: "action",
                tool: "files.write", physical: false, text: text } }));
            tryVerify(() => acknowledgedOn(layer, "b"), 2000, "the write at the bound is acknowledged");
            const area = all(layer, []).find(item => item.overflowing !== undefined && layer.drawn(item));
            verify(area !== undefined, "the payload draws in a scrolled region");
            const column = area.parent;
            const label = area.contentItem.children.find(item => item.role !== undefined);
            tryVerify(() => label.implicitHeight > 16384, 2000, "the payload lays out past 16384 px: " + label.implicitHeight);
            const layered = all(column, []).filter(item => item.layer !== undefined && item.layer.enabled && layer.drawn(item));
            for (const item of layered)
                verify(item.height <= area.height, "a layer in the column stands taller than the region: " + item + " " + item.height);
        }
    }
}
