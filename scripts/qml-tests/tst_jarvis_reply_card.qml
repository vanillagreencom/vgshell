import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.jarvis"
import "../../shell/plugins/vgs.jarvis/Session.js" as Session

// Jarvis's reply card under the bar J, over a stand-in `shell`: it shows
// only on the output its `replyCard` status names, opens and closes with
// the bar flyouts' fade (`motion.flyout.travel`), at once at motion scale 0,
// keeps what it drew while it closes, draws the newest answer cut at 4
// lines in one MessageRow, takes a click on an answer as one `console`
// call, reports the pointer through `reply-hover`, and offers a fault's
// Settings link as its only action. Placement under the J is the nested
// sandbox's (scripts/smoke/rows/jarvis-reply.sh).
Item {
    id: root
    width: 400
    height: 300

    property var calls: []
    property var values: ({})
    readonly property QtObject host: QtObject {
        readonly property QtObject screen: QtObject { readonly property string name: "fixture-1" }
    }

    function state(regions) {
        return Object.assign(JSON.parse(JSON.stringify(Session.initial())), { gate: { kind: "up" }, voiceMute: { kind: "on" } }, regions || {});
    }
    function answer(at, text) {
        return { gen: 1, role: "assistant", text: text, stage: "final", at: at, session: "1:0", startedAt: 1 };
    }
    // A shell whose status shows the card for ROWS' newest answer on OUTPUT,
    // or no card for a null KEY.
    function show(rows, key, output, regions) {
        const last = rows[rows.length - 1];
        const s = root.state(regions);
        root.values = { detail: { phase: Session.phaseOf(s), seq: 1, state: s }, conversation: rows, transcript: null,
            replyCard: key === null ? null : { key: key, answer: { gen: last.gen, at: last.at }, fault: false, settled: true, output: output } };
        reply.shell = root.shellOf(root.values);
    }
    function shellOf(values) {
        return {
            status: { values: values },
            settings: { voiceProvider: "local" },
            ipc: { call: (name, arg) => { root.calls = root.calls.concat([[name, arg]]); return "ok"; } },
            surfaces: { openPage: () => "ok" }
        };
    }
    function windowOf() {
        return Array.from(reply.data).find(child => child instanceof Window);
    }
    function rowOf() {
        const all = item => { let out = []; for (const child of item.children) out = out.concat([child], all(child)); return out; };
        return all(windowOf().contentItem).find(child => child.sender === "Jarvis");
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
            QsWindow.window = root.host;
            root.calls = [];
            root.show([root.answer(10, "first")], null, "fixture-1");
            tryCompare(reply, "motionProgress", 0);
        }
        function cleanup() { QsWindow.window = null; }

        function test_it_opens_and_closes_with_the_flyout_motion() {
            root.show([root.answer(10, "At three.")], "1:10", "fixture-1");
            compare(windowOf().visible, true, "the card maps as it shows");
            verify(reply.motionProgress < 1, "the card moves in, not at once: " + reply.motionProgress);
            tryCompare(reply, "motionProgress", 1, 2000);
            root.show([root.answer(10, "At three.")], null, "fixture-1");
            compare(windowOf().visible, true, "the card stays mapped while it moves out");
            compare(rowOf().bodyText, "At three.", "the closing card keeps what it drew");
            tryCompare(reply, "motionProgress", 0, 2000);
            tryCompare(windowOf(), "visible", false);
        }

        function test_motion_scale_zero_opens_and_closes_at_once() {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            root.show([root.answer(10, "At three.")], "1:10", "fixture-1");
            compare(reply.motionProgress, 1, "the card shows whole at once");
            root.show([root.answer(10, "At three.")], null, "fixture-1");
            compare(reply.motionProgress, 0, "the card goes at once");
            compare(windowOf().visible, false);
        }

        function test_it_shows_only_on_the_output_its_status_names() {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            root.show([root.answer(10, "At three.")], "1:10", "fixture-2");
            compare(reply.shown, false);
            compare(windowOf().visible, false);
            root.show([root.answer(10, "At three.")], "1:10", "fixture-1");
            compare(reply.shown, true);
        }

        function test_a_new_answer_replaces_the_text_and_a_long_one_is_cut() {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            root.show([root.answer(10, "At three.")], "1:10", "fixture-1");
            const long = Array(80).fill("word").join(" ");
            root.show([root.answer(10, "At three."), root.answer(20, long)], "1:20", "fixture-1");
            compare(rowOf().bodyText, long, "the newest answer replaces the text");
            compare(rowOf().bodyLines, 4);
            tryCompare(rowOf(), "bodyTruncated", true);
            compare(rowOf().cutHint, "Click to read the full answer");
        }

        function test_a_click_asks_the_service_for_the_console_and_the_pointer_holds_it() {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            root.show([root.answer(10, "At three.")], "1:10", "fixture-1");
            const window = windowOf();
            verify(renderedFrame(window.contentItem));
            mouseMove(window.contentItem, 20, 20);
            tryCompare(reply, "hovered", true);
            verify(root.calls.some(call => call[0] === "reply-hover" && call[1] === "true"), "the card reports the pointer");
            mouseClick(window.contentItem, 20, 20);
            compare(root.calls.filter(call => call[0] === "console"), [["console", ""]]);
        }

        function test_a_faults_link_is_its_only_action() {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            const s = root.state({ fault: { kind: "error", reason: "brain=stream-error", retry: 0 } });
            root.values = { detail: { phase: Session.phaseOf(s), seq: 1, state: s }, conversation: [], transcript: null,
                replyCard: { key: "fault:0:brain=stream-error", answer: null, fault: true, settled: true, output: "fixture-1" } };
            reply.shell = root.shellOf(root.values);
            const row = rowOf();
            compare(row.stateText, "Problem");
            compare(row.title, "The AI model did not answer");
            verify(row.bodyItem !== null && row.bodyItem.text.indexOf("Settings > Jarvis") !== -1, "the fault's action reads under it");
            const window = windowOf();
            verify(renderedFrame(window.contentItem));
            mouseClick(window.contentItem, 4, 4);
            compare(root.calls.filter(call => call[0] === "console").length, 0, "a click beside the link opens no console");
        }
    }
}
