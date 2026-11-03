import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.jarvis"
import "../../shell/plugins/vgs.jarvis/Appearance.js" as Appearance

// Jarvis's approval prompt and fault line as the overlay draws them: the
// question and the fault's title in the shared bodyStrong role, the state
// line in label; each line and answer in the look's ink, the same in both
// modes, over the look's text shadow, which draws no frame while nothing
// changes; the answers at the look's height, Cancel as bare words and
// Confirm on the look's fill; and Confirm's shimmer still at motion scale
// 0. The held request's frame acknowledgement and the drawn overlay on a
// real layer are scripts/smoke/rows/jarvis-bubble.sh's.
Item {
    id: root
    width: 640
    height: 720

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
        property var shell: ({ status: { values: {} }, surfaces: { openPage: () => {} } })
        function attachBubble(item) {}
        function detachBubble(item) {}
        function intent(name) {}
        function shownApproval(item, hold) {}
        function cancelApproval(hold) {}
        function confirmApproval(hold, how) {}
    }

    Bubble { id: bubble; width: root.width; height: root.height; screen: ({ name: "unit" }); service: service }

    function session(over) {
        const s = { gen: 1, check: { kind: "none" }, gate: { kind: "up" }, fault: { kind: "none" }, approval: { kind: "none" },
            action: { kind: "none" }, playback: { kind: "none" }, speech: { kind: "none" }, turn: { kind: "none" },
            capture: { kind: "closed" }, mute: { kind: "off" }, voiceMute: { kind: "off" }, engine: { kind: "chained" } };
        for (const key in over) s[key] = over[key];
        return s;
    }
    readonly property var held: session({ approval: { kind: "held", id: "a", gen: 1, digest: "d", purpose: "action", tool: "files.delete",
        physical: true, text: "Delete draft.txt?\n/home/fixture/draft.txt" } })

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
            const found = all(bubble, []).filter(item => item.role !== undefined && item.text === text && shown(item));
            verify(found.length === 1, "one drawn line reads " + JSON.stringify(text) + ", found " + found.length);
            return found[0];
        }
        function answer(text) {
            const found = all(bubble, []).filter(item => item.shimmering !== undefined && item.text === text && shown(item));
            verify(found.length === 1, "one drawn answer reads " + text);
            return found[0];
        }


        // The shadow effect Qt's layer draws ITEM through: the effect whose
        // source is ITEM's layer.
        function shadowOf(item) {
            verify(item.layer.enabled, "the line draws through a layer");
            const found = all(bubble, []).filter(node => node.shadowEnabled !== undefined && node.source !== null
                && node.source !== undefined && node.source.sourceItem === item);
            verify(found.length === 1, "one effect draws the line, found " + found.length);
            return found[0];
        }
        function put(state) {
            service.sessionState = state;
            verify(renderedFrame(root), "the window draws the overlay");
        }

        function init() {
            UnitTheme.reset();
            service.sessionState = null;
            mouseMove(root, root.width - 1, 0);
        }

        function test_main_text_is_body_strong_data() {
            return [
                { tag: "the approval question", state: root.held, text: "Delete draft.txt?", role: "bodyStrong" },
                { tag: "the fault title", state: root.session({ fault: { kind: "error", reason: "device-lost" } }), title: true, role: "bodyStrong" },
                { tag: "the state line", state: root.session({ capture: { kind: "open", mode: "armed" } }), text: "Say Hey Jarvis", role: "label" }
            ];
        }

        function test_main_text_is_body_strong(data) {
            service.sessionState = data.state;
            const text = data.title ? bubble.fault.title : data.text;
            verify(text !== "", "the line has words");
            compare(labelOf(text).role, data.role);
        }

        // The answers stand at the look's height, Cancel as bare words with
        // no fill and no border at rest or under the pointer, and Confirm on
        // the look's fill, which rises under the pointer.
        function test_answers_take_the_looks_form() {
            service.sessionState = root.held;
            const cancel = answer("Cancel");
            const confirm = answer("Confirm");
            verify(root.look.answer.height !== Theme.size.control.sm && root.look.answer.height !== Theme.size.control.md,
                "the look's height differs from the shared control heights");
            compare(cancel.height, root.look.answer.height);
            compare(confirm.height, root.look.answer.height);
            compare(confirm.background.radius, root.look.answer.radius);
            tryVerify(() => String(confirm.background.color) === String(Qt.color(root.look.answer.fill)), 1000, "Confirm rests on the look's fill");
            compare(cancel.background.color.a, 0);
            compare(cancel.background.border.color.a, 0);
            compare(confirm.background.border.color.a, 0);
            mouseMove(cancel, cancel.width / 2, cancel.height / 2);
            tryCompare(cancel, "hovered", true);
            compare(String(cancel.foreground), String(Qt.color(root.look.answer.bareHoverInk)));
            wait(Theme.motion.duration.fast + 50);
            compare(cancel.background.color.a, 0);
            mouseMove(confirm, confirm.width / 2, confirm.height / 2);
            tryCompare(confirm, "hovered", true);
            tryVerify(() => String(confirm.background.color) === String(Qt.color(root.look.answer.hoverFill)), 1000, "Confirm's fill rises under the pointer");
        }

        // Every line the prompt, the fault and the state line draw, and each
        // answer's label, draws over the look's shadow: no offset, the
        // look's colour, opacity and blur.
        function test_every_line_draws_the_looks_shadow_data() {
            return [
                { tag: "the question", state: root.held, text: "Delete draft.txt?" },
                { tag: "the path", state: root.held, text: "/home/fixture/draft.txt" },
                { tag: "the hint", state: root.held, text: "Use the button or key to confirm." },
                { tag: "Cancel", state: root.held, answer: "Cancel" },
                { tag: "Confirm", state: root.held, answer: "Confirm" },
                { tag: "the state line", state: root.session({ capture: { kind: "open", mode: "armed" } }), text: "Say Hey Jarvis" },
                { tag: "the fault title", state: root.session({ fault: { kind: "error", reason: "device-lost" } }), title: true },
                { tag: "the fault action", state: root.session({ fault: { kind: "error", reason: "device-lost" } }), action: true }
            ];
        }

        function test_every_line_draws_the_looks_shadow(data) {
            put(data.state);
            const item = data.answer !== undefined ? answer(data.answer).contentItem
                : data.action ? all(bubble, []).find(node => node.linkColor !== undefined && shown(node))
                : labelOf(data.title ? bubble.fault.title : data.text);
            verify(item !== undefined && item !== null, "the line draws");
            const effect = shadowOf(item);
            compare(effect.shadowEnabled, true);
            compare(String(effect.shadowColor), String(Qt.color(root.look.shadow.color)));
            compare(effect.shadowOpacity, root.look.shadow.opacity);
            compare(effect.blurMax, root.look.shadow.blur);
            compare(effect.shadowBlur, 1);
            compare(effect.shadowHorizontalOffset, 0);
            compare(effect.shadowVerticalOffset, 0);
        }

        // A still prompt redraws no blur: with the orb still at motion
        // scale 0 and the pointer away, the window swaps no frame. A new
        // question draws, the control that the frames are counted.
        function test_a_still_prompt_draws_no_frame() {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            put(root.held);
            const frames = createTemporaryObject(frameSpy, root, { target: bubble.Window.window });
            verify(renderedFrame(root), "the window draws the prompt");
            frames.clear();
            wait(500);
            compare(frames.count, 0);
            const next = JSON.parse(JSON.stringify(root.held));
            next.approval.text = "Delete notes.txt?\n/home/fixture/notes.txt";
            next.approval.id = "b";
            service.sessionState = next;
            tryVerify(() => frames.count > 0, 1000, "a changed question draws");
        }

        // Each line draws in the look's ink, the same in the light mode as
        // in the dark.
        function test_lines_draw_the_looks_ink_in_both_modes_data() {
            return [{ tag: "dark", light: false }, { tag: "light", light: true }];
        }

        function test_lines_draw_the_looks_ink_in_both_modes(data) {
            if (data.light) compare(UnitTheme.override({ scheme: { mode: "light" } }), "ok");
            const dark = Theme.appearance(Appearance.TOKENS, {});
            put(root.held);
            compare(String(labelOf("Delete draft.txt?").color), String(Qt.color(dark.ink.question)));
            compare(String(labelOf("/home/fixture/draft.txt").color), String(Qt.color(dark.ink.path)));
            compare(String(labelOf("Use the button or key to confirm.").color), String(Qt.color(dark.ink.hint)));
            compare(String(answer("Cancel").foreground), String(Qt.color(dark.answer.bareInk)));
            compare(String(answer("Confirm").foreground), String(Qt.color(dark.answer.ink)));
            put(root.session({ capture: { kind: "open", mode: "armed" } }));
            compare(String(labelOf("Say Hey Jarvis").color), String(Qt.color(dark.ink.state)));
        }

        // Under the pointer Confirm's shimmer sweeps; at motion scale 0 it
        // never starts, and the label keeps the hover ink.
        function test_shimmer_stands_still_at_motion_scale_0_data() {
            return [{ tag: "motion scale 1", scale: 1, sweeps: true }, { tag: "motion scale 0", scale: 0, sweeps: false }];
        }

        function test_shimmer_stands_still_at_motion_scale_0(data) {
            compare(UnitTheme.override({ motion: { scale: data.scale } }), "ok");
            service.sessionState = root.held;
            const confirm = answer("Confirm");
            const changes = createTemporaryObject(spy, root, { target: confirm });
            mouseMove(confirm, confirm.width / 2, confirm.height / 2);
            tryCompare(confirm, "hovered", true);
            if (data.sweeps) {
                tryCompare(confirm, "shimmering", true);
            } else {
                wait(200);
                compare(changes.count, 0);
                compare(confirm.shimmering, false);
            }
            compare(String(confirm.foreground), String(Qt.color(root.look.answer.hoverInk)));
        }
    }

    Component {
        id: frameSpy
        SignalSpy { signalName: "frameSwapped" }
    }

    Component {
        id: spy
        SignalSpy { signalName: "shimmeringChanged" }
    }
}
