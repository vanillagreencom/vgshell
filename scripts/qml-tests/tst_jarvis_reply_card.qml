import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.jarvis"

// Jarvis's reply card under the bar J, over a stand-in `shell` whose
// `replyCard` status holds the card's decision (WidgetView.replyCard): it
// shows only on the output that status names, draws the newest answer cut
// at 4 lines in one MessageRow, the words as Jarvis speaks them through the
// card's real Words while the voice speaks, or a fault with its Settings
// link as its only action; it keeps what it drew while it closes, takes a
// click on an answer as one `console` call, and claims the pointer through
// `reply-hover` only while it shows. Its surface and motion are
// PassivePopup's (tst_passive_popup.qml); placement under the J is the
// nested sandbox's (scripts/smoke/rows/jarvis-reply.sh).
Item {
    id: root
    width: 400
    height: 300

    property var calls: []
    readonly property QtObject host: QtObject {
        readonly property QtObject screen: QtObject { readonly property string name: "fixture-1" }
    }

    function answer(at, text) {
        return { gen: 1, role: "assistant", text: text, stage: "final", at: at, session: "1:0", startedAt: 1 };
    }
    // A shell whose status shows ROWS' newest answer in MODE on OUTPUT, or
    // no card for a null MODE; CAPTION is the transcript status.
    function show(rows, mode, output, caption) {
        const last = rows[rows.length - 1];
        reply.shell = root.shellOf({ conversation: rows, transcript: caption || null,
            replyCard: mode === null ? null : { key: last.gen + ":" + last.at, answer: { gen: last.gen, at: last.at }, mode: mode,
                fault: null, settled: mode === "answer", output: output } });
    }
    function shellOf(values) {
        return {
            status: { values: values },
            ipc: { call: (name, arg) => { root.calls = root.calls.concat([[name, arg]]); return "ok"; } },
            surfaces: { openPage: () => "ok" }
        };
    }
    function windowOf() {
        return Array.from(reply.data).find(child => child instanceof Window);
    }
    function all(item) {
        let out = [];
        for (const child of item.children) out = out.concat([child], all(child));
        return out;
    }
    function rowOf() {
        return all(windowOf().contentItem).find(child => child.sender === "Jarvis");
    }
    function wordsOf() {
        return all(windowOf().contentItem).find(child => child.objectName === "replyWords");
    }

    Item {
        id: anchor
        x: 300
        width: 24
        height: 24
        ReplyCard { id: reply; shell: null }
    }

    UnitCase {
        name: "jarvisReplyCard"
        when: windowShown

        function init() {
            UnitTheme.reset();
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            QsWindow.window = root.host;
            root.show([root.answer(10, "first")], null, "fixture-1");
            compare(windowOf().visible, false);
            root.calls = [];
        }
        function cleanup() { QsWindow.window = null; }

        function test_it_shows_only_on_the_output_its_status_names() {
            root.show([root.answer(10, "At three.")], "answer", "fixture-2");
            compare(reply.shown, false);
            compare(windowOf().visible, false);
            root.show([root.answer(10, "At three.")], "answer", "fixture-1");
            compare(reply.shown, true);
            compare(windowOf().visible, true);
        }

        function test_a_new_answer_replaces_the_text_and_a_long_one_is_cut() {
            root.show([root.answer(10, "At three.")], "answer", "fixture-1");
            compare(rowOf().bodyText, "At three.");
            const long = Array(80).fill("word").join(" ");
            root.show([root.answer(10, "At three."), root.answer(20, long)], "answer", "fixture-1");
            compare(rowOf().bodyText, long, "the newest answer replaces the text");
            compare(rowOf().bodyLines, 4);
            tryCompare(rowOf(), "bodyTruncated", true);
            compare(rowOf().cutHint, "Click to read the full answer");
        }

        function test_the_closing_card_keeps_what_it_drew() {
            UnitTheme.reset();
            root.show([root.answer(10, "At three.")], "answer", "fixture-1");
            tryCompare(reply, "motionProgress", 1, 2000);
            root.show([root.answer(10, "At three.")], null, "fixture-1");
            compare(windowOf().visible, true, "the card moves out");
            compare(rowOf().bodyText, "At three.", "the closing card keeps what it drew");
            tryCompare(windowOf(), "visible", false, 2000);
        }

        // The voice speaks: the row's body is the card's real Words reading
        // the caption, in the theme's inks at full opacity, at the left
        // edge; once the phase leaves speaking the
        // service's mode is the answer again and the row draws its body.
        function test_the_voice_speaks_the_words_in_the_card() {
            const caption = { gen: 1, role: "assistant", text: "Tomorrow starts cloudy at nine with a light wind from the west and rain at noon" };
            const full = caption.text + " and a clear sky after eight.";
            root.show([root.answer(10, full)], "follow", "fixture-1", caption);
            const row = rowOf();
            compare(row.stateText, "Speaking");
            compare(row.bodyText, "", "the words draw in the body's place");
            const words = wordsOf();
            verify(words !== undefined, "the row's body is the card's Words");
            compare(words.text, caption.text, "the words are the caption");
            tryVerify(() => words.settled, 2000);
            compare(words.window, 4);
            compare(String(words.newestInk), String(Qt.color(Theme.color.text)), "the newest line in the text ink");
            compare(String(words.olderInk), String(Qt.color(Theme.color.textMuted)), "an older line in the muted ink");
            compare([words.newestOpacity, words.middleOpacity, words.oldestOpacity], [1, 1, 1], "every line opaque");
            compare(words.horizontalAlignment, Text.AlignLeft, "the lines start at the left edge");
            const slots = words.children.filter(child => child.line !== undefined && child.visible).sort((a, b) => a.y - b.y);
            verify(slots.length > 1, "the caption takes more than one line");
            for (const slot of slots) {
                compare(slot.children[0].x, 0, "each line starts at the left edge");
            }
            compare(String(slots[slots.length - 1].ink), String(Qt.color(Theme.color.text)), "the newest line draws in the text ink");
            for (const slot of slots.slice(0, -1)) compare(String(slot.ink), String(Qt.color(Theme.color.textMuted)), "an older line draws muted");
            root.show([root.answer(10, full)], "answer", "fixture-1", caption);
            compare(rowOf().stateText, "");
            compare(rowOf().bodyText, full, "the answer's body once the voice is done");
            compare(wordsOf(), undefined, "no words remain");
        }

        function test_a_click_asks_the_service_for_the_console_and_the_pointer_holds_it() {
            root.show([root.answer(10, "At three.")], "answer", "fixture-1");
            const window = windowOf();
            verify(renderedFrame(window.contentItem));
            mouseMove(window.contentItem, 20, 20);
            tryCompare(reply, "hovered", true);
            compare(root.calls.filter(call => call[0] === "reply-hover"), [["reply-hover", "true"]], "the card claims the pointer");
            mouseClick(window.contentItem, 20, 20);
            compare(root.calls.filter(call => call[0] === "console"), [["console", ""]]);
        }

        // A card that stops showing under the pointer withdraws its claim.
        function test_a_card_that_goes_under_the_pointer_withdraws_its_claim() {
            root.show([root.answer(10, "At three.")], "answer", "fixture-1");
            const window = windowOf();
            verify(renderedFrame(window.contentItem));
            mouseMove(window.contentItem, 20, 20);
            tryCompare(reply, "hovered", true);
            root.calls = [];
            root.show([root.answer(10, "At three.")], null, "fixture-1");
            const claims = root.calls.filter(call => call[0] === "reply-hover");
            verify(claims.length > 0 && claims.every(call => call[1] === "false"), "the claim goes with the card: " + JSON.stringify(claims));
        }

        function test_a_faults_link_is_its_only_action() {
            reply.shell = root.shellOf({ conversation: [], transcript: null,
                replyCard: { key: "fault:0:brain=stream-error", answer: null, mode: "fault",
                    fault: { title: "The AI model did not answer", action: "Turn Jarvis off and on again in [Settings > Jarvis](page:vgs.jarvis/Settings)." },
                    settled: true, output: "fixture-1" } });
            const row = rowOf();
            compare(row.stateText, "Problem");
            compare(row.title, "The AI model did not answer");
            // The LinkText holds the action's words with their link markup.
            const link = all(windowOf().contentItem).find(child => child.visible && child.link !== undefined
                && String(child.text).indexOf("[Settings > Jarvis]") !== -1);
            verify(link !== undefined, "the fault's action reads under it");
            const window = windowOf();
            verify(renderedFrame(window.contentItem));
            mouseClick(window.contentItem, 4, 4);
            compare(root.calls.filter(call => call[0] === "console").length, 0, "a click beside the link opens no console");
        }
    }
}
