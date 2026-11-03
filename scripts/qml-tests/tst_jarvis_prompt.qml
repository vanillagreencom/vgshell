import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.jarvis"
import "../../shell/plugins/vgs.jarvis/Appearance.js" as Appearance

// Jarvis's approval prompt and fault line as the overlay draws them: the
// question and the fault's title in the shared bodyStrong role, the state
// line in label; the answers at the look's height, Cancel as bare words
// and Confirm on the look's fill; the key hints the look's distance under
// the answers; and Confirm's shimmer still at motion scale 0. The held
// request's frame acknowledgement and the drawn overlay on a real layer
// are scripts/smoke/rows/jarvis-bubble.sh's.
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

    TestCase {
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
        function hints() {
            const found = all(bubble, []).filter(item => item.hints !== undefined && item.hints.length > 0 && shown(item));
            verify(found.length === 1, "one key hint row");
            return found[0];
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

        // The key hints stand the look's distance under the answers.
        function test_key_hints_stand_under_the_answers() {
            service.sessionState = root.held;
            const confirm = answer("Confirm");
            const row = hints();
            const bottom = confirm.mapToItem(bubble, 0, confirm.height).y;
            const top = row.mapToItem(bubble, 0, 0).y;
            compare(top - bottom, root.look.layout.hints);
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
        id: spy
        SignalSpy { signalName: "shimmeringChanged" }
    }
}
