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
// reaches a link, never its raw form. The console's keys, tabs and Audit
// are the jarvis-console smoke row's; this test reads what the header draws.
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
            shortcut: { keys: { talk: "SUPER+code:108", mute: "SUPER+SHIFT+code:108", stop: "SUPER+ALT+PERIOD", confirm: "SUPER+ALT+Y", console: "SUPER+ALT+C" } },
            ipc: { call: (name, arg) => "ok" },
            surfaces: { openPage: (page, tab) => { root.opened = root.opened.concat([[page, tab]]); } }
        };
    }

    Console { id: jarvisConsole; anchors.fill: parent }

    TestCase {
        name: "jarvisConsole"
        when: windowShown

        function init() {
            UnitTheme.reset();
            root.opened = [];
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
