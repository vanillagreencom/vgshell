import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.jarvis"
import "../../shell/plugins/vgs.jarvis/Session.js" as Session

// The Jarvis overlay's fault card: a fault's action that names a page
// draws the reference's words with no Markdown, and a click on them opens
// the page through `shell.surfaces.openPage` (design-system.md § Copy).
// The service is a stand-in that hands the card a Session record.
Item {
    id: root
    width: 600
    height: 300

    property var opened: []

    QtObject {
        id: service
        property var sessionState: null
        property bool bubbleWanted: true
        property string focusedOutput: "SMOKE-1"
        property var consoleBox: null
        property var consoleKey: null
        property var heldKey: null
        property var effectiveKeys: null
        property var shell: ({
            status: { values: {} },
            surfaces: { openPage: (page, tab) => { root.opened = root.opened.concat([[page, tab]]); } }
        })
        function attachBubble(bubble) {}
        function detachBubble(bubble) {}
    }

    Bubble {
        id: bubble
        anchors.fill: parent
        screen: ({ name: "SMOKE-1" })
        service: service
    }

    UnitCase {
        name: "jarvisBubble"
        when: windowShown

        function init() {
            UnitTheme.reset();
            root.opened = [];
            // A clicked link keeps the test window's focus; Qt warns when a
            // focused item stops taking Tab as its fault clears.
            bubble.forceActiveFocus();
            service.sessionState = null;
        }

        function collect(node, test, out) {
            if (test(node)) out.push(node);
            for (const child of node.children) collect(child, test, out);
            return out;
        }
        function shownText() {
            return collect(bubble, n => n instanceof Text && n.visible && n.opacity > 0 && n.text !== "", []).map(n => n.text);
        }
        function links() {
            return collect(bubble, n => n.focusPreview !== undefined && n.linkColor !== undefined && n.visible, []);
        }

        // Faults whose action names a page, each with the reference's words
        // and the page and tab it names.
        function test_a_fault_action_draws_its_page_reference_as_a_link_data() {
            return [
                { tag: "stopped", engine: "chained", reason: "jarvis-test=unknown", words: "Settings > Jarvis", page: "vgs.jarvis", tab: "Settings" },
                { tag: "default device", engine: "dictation", reason: "device-lost", words: "System > Sound", page: "vgs.sound", tab: "" }
            ];
        }
        function test_a_fault_action_draws_its_page_reference_as_a_link(data) {
            service.sessionState = Object.assign(JSON.parse(JSON.stringify(Session.initial())),
                { gate: { kind: "up" }, engine: { kind: data.engine }, fault: { kind: "error", reason: data.reason } });
            compare(bubble.phase, "error");
            const drawn = shownText();
            verify(drawn.length > 0, "the card draws text");
            for (const text of drawn)
                verify(!/\]\((page|file):/.test(text), "no drawn text shows a reference's raw form: " + text);
            const link = links().find(n => n.plain.indexOf(data.words) !== -1);
            verify(link !== undefined, "a link draws the action's words: " + JSON.stringify(drawn));
            compare(link.words, data.words);
            verify(bubble.inputItems.indexOf(link) !== -1, "the passive layer takes clicks on the link");
            // The layout gives the link its width at the next polish.
            verify(renderedFrame(bubble));
            verify(link.underlined.length > 0, "the link's words are laid out");
            const span = link.underlined[0];
            mouseClick(link, (span.left + span.right) / 2, (span.line + 0.5) * link.linePitch);
            compare(JSON.stringify(root.opened), JSON.stringify([[data.page, data.tab]]));
        }
    }
}
