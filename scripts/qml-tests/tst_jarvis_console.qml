import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.jarvis"
import "../../shell/plugins/vgs.jarvis/Session.js" as Session

// The Jarvis console's state lines under its purpose, over a stand-in
// `shell`: the bar's state, the action a problem names and the AI model
// each draw as a line of their own, and the action's page reference
// reaches a link, never its raw form. Composer replacements retain a visible
// keyboard target and leave another tab or control's focus alone.
Item {
    id: root
    width: 760
    height: 900

    property var opened: []

    // Status values over Session's initial record with REGIONS set, the
    // AI model the daemon names beside it.
    function values(regions) {
        const s = Object.assign(JSON.parse(JSON.stringify(Session.initial())), { gate: { kind: "up" } }, regions);
        return { daemon: { tone: "info", text: "Jarvis is ready; microphone is off" }, audio: { tone: "ok", text: "Device list ready" },
            detail: { phase: Session.phaseOf(s), seq: 1, state: s, brain: "Claude Opus 5.5" } };
    }

    function shellWith(values) {
        return {
            screens: { current: null },
            status: { values: values },
            settings: { mode: "hold", voiceProvider: "gemini" },
            shortcut: { keys: { talk: "SUPER+code:30", mute: "SUPER+SHIFT+code:30", stop: "SUPER+ALT+PERIOD", confirm: "SUPER+ALT+Y", console: "SUPER+ALT+C" } },
            ipc: { call: (name, arg) => "ok" },
            surfaces: { openPage: (page, tab) => { root.opened = root.opened.concat([[page, tab]]); } }
        };
    }

    Console { id: jarvisConsole; anchors.fill: parent }
    Button { id: outside; text: "Outside Console" }

    TestCase {
        name: "jarvisConsole"
        when: windowShown

        function init() {
            UnitTheme.reset();
            root.opened = [];
            jarvisConsole.tab = 0;
            jarvisConsole.shell = root.shellWith(root.values({}));
            wait(0); // Drain the tab's queued focus before each case chooses its control.
            outside.forceActiveFocus();
        }

        function collect(node, test, out) {
            if (test(node)) out.push(node);
            for (const child of node.children) collect(child, test, out);
            return out;
        }
        function shownText() {
            return collect(jarvisConsole, n => n instanceof Text && n.visible && n.opacity > 0 && n.text !== "", []).map(n => n.text);
        }
        function links() {
            return collect(jarvisConsole, n => n.focusPreview !== undefined && n.linkColor !== undefined && n.visible, []);
        }

        function composerControls() {
            const all = collect(jarvisConsole, n => true, []);
            const stops = all.filter(n => n.label === "Stop Jarvis");
            return {
                entry: all.find(n => n.placeholderText === "Message Jarvis"),
                send: all.find(n => n.text === "Send"),
                info: all.find(n => n.title === "Message length"),
                speechStop: stops[0], typedStop: stops[1],
                speechHint: all.find(n => n.linkColor !== undefined && n.text === jarvisConsole.speechOnlyText),
                tabs: all.find(n => n.model !== undefined && Array.isArray(n.model) && n.model[0] === "Conversation")
            };
        }

        // Real Session regions: mute and gate can refuse before duplex, and
        // engine changes arrive while the same Console instance stays open.
        function test_composer_transition_data() {
            const typed = { engine: { kind: "chained" } };
            const speech = { engine: { kind: "duplex" } };
            const rows = [
                { tag: "unmute-duplex", from: Object.assign({}, speech, { mute: { kind: "on" } }), to: speech, focus: "speechStop", expected: "speechStop" },
                { tag: "mute-duplex", from: speech, to: Object.assign({}, speech, { mute: { kind: "on" } }), focus: "speechStop", expected: "speechStop" },
                { tag: "ready-duplex", from: Object.assign({}, speech, { gate: { kind: "down", reason: "unconfigured" } }), to: speech, focus: "speechStop", expected: "speechStop" },
                { tag: "unready-duplex", from: speech, to: Object.assign({}, speech, { gate: { kind: "down", reason: "unconfigured" } }), focus: "speechStop", expected: "speechStop" },
                { tag: "dictation", from: typed, to: { engine: { kind: "dictation" } }, focus: "entry", expected: "entry" }
            ];
            for (const focus of ["entry", "send", "info", "typedStop"])
                rows.push({ tag: "local-to-cloud-" + focus, from: typed, to: speech, focus: focus, expected: "speechStop" });
            for (const focus of ["speechStop", "speechHint"])
                rows.push({ tag: "cloud-to-local-" + focus, from: speech, to: typed, focus: focus, expected: "entry" });
            for (const focus of ["outside", "tabs", "tasks", "audit"])
                for (const fromSpeech of [false, true])
                    rows.push({ tag: "keep-" + focus + "-" + fromSpeech, from: fromSpeech ? speech : typed,
                        to: fromSpeech ? typed : speech, focus: focus, expected: focus });
            rows.push({ tag: "daemon-arrives", from: null, to: speech, focus: "entry", expected: "speechStop" });
            rows.push({ tag: "daemon-leaves", from: speech, to: null, focus: "speechStop", expected: "entry" });
            return rows;
        }

        function setRegions(regions) {
            const shell = root.shellWith(regions === null ? {} : root.values(regions));
            // With no Talk key the speech hint itself is a focusable link.
            shell.shortcut.keys.talk = "";
            jarvisConsole.shell = shell;
        }

        function test_composer_transition(data) {
            setRegions(data.from);
            let controls = composerControls();
            let focused;
            if (data.focus === "outside") focused = outside;
            else if (data.focus === "tasks" || data.focus === "audit") {
                jarvisConsole.tab = data.focus === "tasks" ? 1 : 2;
                jarvisConsole.focusTab();
                wait(0);
                focused = collect(jarvisConsole, n => n.activeFocus && n.focusPolicy === Qt.StrongFocus && n !== jarvisConsole, []).pop();
            } else focused = controls[data.focus];
            verify(focused !== undefined, "find source " + data.focus);
            focused.forceActiveFocus(Qt.TabFocusReason);
            verify(focused.activeFocus, "source owns focus");
            setRegions(data.to);
            controls = composerControls();
            const expected = data.expected === data.focus ? focused : controls[data.expected];
            tryCompare(expected, "activeFocus", true);
            verify(expected.visible, "focus target is visible");
            compare(jarvisConsole.speechOnly, data.to !== null && data.to.engine.kind === "duplex");
            if (expected !== focused) {
                verify(!focused.activeFocus, "replaced control releases focus");
                compare(expected.focusReason, Qt.TabFocusReason, "replacement keeps the keyboard reason");
            }
        }

        function test_tabs_enter_visible_composer_data() {
            return [{ tag: "typed", kind: "chained", control: "entry" }, { tag: "speech", kind: "duplex", control: "speechStop" }];
        }

        function test_tabs_enter_visible_composer(data) {
            setRegions({ engine: { kind: data.kind } });
            const controls = composerControls();
            controls.tabs.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Tab);
            tryCompare(controls[data.control], "activeFocus", true);
            keyClick(Qt.Key_Backtab);
            tryCompare(controls.tabs, "activeFocus", true);
        }

        // A refused key is a problem whose action links the Voice key field.
        function test_a_problem_draws_its_facts_as_lines_and_its_action_as_a_link() {
            jarvisConsole.shell = root.shellWith(root.values({ fault: { kind: "error", reason: "live=key-refused", retry: 0 } }));
            const reference = "(page:vgs.jarvis/Settings/voiceAccount)";
            const drawn = shownText();
            verify(drawn.length > 0, "the console draws text");
            for (const text of drawn)
                compare(PageReference.parse(text).page, "", "no drawn line shows a page reference's raw form: " + text);
            verify(drawn.indexOf("AI model: Claude Opus 5.5") !== -1, "the AI model is a line of its own: " + JSON.stringify(drawn));
            const link = links().find(n => n.text.indexOf(reference) !== -1);
            verify(link !== undefined, "a link holds the action's page reference");
            verify(link.text.indexOf("AI model: ") === -1, "the action's link holds no other fact");
            link.pageActivated("vgs.jarvis/Settings", "voiceAccount");
            compare(JSON.stringify(root.opened), '[["vgs.jarvis/Settings","voiceAccount"]]');
        }
    }
}
