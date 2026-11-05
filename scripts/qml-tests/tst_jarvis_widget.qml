import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.jarvis"
import "../../shell/plugins/vgs.jarvis/Session.js" as Session

// The Jarvis bar widget: the icon and tone it draws for the status values a
// stand-in `shell` hands it, that a click, Space, Return and keypad Enter
// each make exactly one `console` call through `shell.ipc`, and that the
// right-click menu holds the Jarvis menu, each entry making one call of its
// intent's handler or opening its page. The bar
// layer takes no keyboard focus in the live shell, so this test is where
// the keys are proven. WidgetView.js's own table is
// scripts/test-jarvis-widget.js; this test reads what the widget draws.
Item {
    id: root
    width: 200
    height: 60

    property var calls: []
    property var pages: []
    property string reply: "ok"

    // A shell with VALUES as its status and an ipc that records each call.
    function shellWith(values) {
        return {
            status: { values: values },
            settings: { holdToTalk: false, voiceProvider: "local" },
            shortcut: { keys: { talk: "SUPER+code:44", "voice-mute": "SUPER+CTRL+M", deny: null, stop: "SUPER+CTRL+X", confirm: "SUPER+CTRL+Y", console: "SUPER+ALT+C" } },
            ipc: { call: (name, arg) => { root.calls = root.calls.concat([[name, arg]]); return root.reply; } },
            surfaces: { openPage: (page, tab) => { root.pages = root.pages.concat([[page, tab]]); return "ok"; } }
        };
    }
    // Status values over Session's initial record with REGIONS set.
    function ready(regions) {
        const s = Object.assign(JSON.parse(JSON.stringify(Session.initial())), { gate: { kind: "up" } }, regions);
        return { microphoneMute: { kind: "ready", muted: false }, daemon: { tone: "info", text: "Jarvis is ready; microphone is off" }, audio: { tone: "ok", text: "Device list ready" },
            detail: { phase: Session.phaseOf(s), seq: 1, state: s } };
    }

    Widget { id: widget }

    TestCase {
        name: "jarvisWidget"
        when: windowShown

        function init() {
            UnitTheme.reset();
            root.calls = [];
            root.pages = [];
            root.reply = "ok";
            widget.frame = null;
            widget.shell = root.shellWith(root.ready({}));
        }

        function find(node, test) {
            if (test(node)) return node;
            for (const child of node.children) {
                const found = find(child, test);
                if (found !== null) return found;
            }
            return null;
        }
        function button() { return find(widget, n => n.iconName !== undefined && n.label !== undefined); }
        function tooltip() { return find(widget, n => n.anchorItem !== undefined && n.text !== undefined); }
        function icon() { return find(button().contentItem, n => n.name !== undefined && n.paths !== undefined); }

        function themeTokens(path) {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../../themes/" + path + "/theme.json"), false);
            request.send();
            return JSON.parse(request.responseText).tokens;
        }

        // Each state glyph draws in the Theme.color role of its tone, never
        // the badge foreground of that tone, under vgs and flexoki-light.
        function test_states_draw_their_icon_tone_and_tooltip_data() {
            return [{ tag: "vgs", theme: "vgs" }, { tag: "flexoki-light", theme: "catalog/flexoki-light" }];
        }
        function test_states_draw_their_icon_tone_and_tooltip(data) {
            compare(UnitTheme.override(themeTokens(data.theme)), "ok");
            // This is the bar's status-only output contract. Console's
            // independent voice and Talk guidance are checked in its suite.
            const muted = root.ready({});
            muted.microphoneMute = { kind: "ready", muted: true };
            const rows = [
                [{ daemon: { tone: "info", text: "Starting" }, detail: null }, "loader", Theme.color.info, "Jarvis is starting"],
                [root.ready({}), "vgs-letter-j", Theme.bar.foreground, "Conversation closed"],
                [root.ready({ conversation: { kind: "active", purpose: "conversation" } }), "vgs-letter-j", Theme.bar.foreground, "Conversation open"],
                [root.ready({ capture: { kind: "open", gen: 1, op: 2, mode: "conversation" } }), "audio-lines", Theme.color.accent, "Jarvis is listening"],
                [root.ready({ turn: { kind: "thinking", gen: 1, op: 3, deadline: 70 } }), "brain", Theme.color.info, "Jarvis is thinking"],
                [root.ready({ playback: { kind: "playing", gen: 1, op: 5, source: 4, interruptible: true, admission: { kind: "started" }, deadline: null } }), "volume-2", Theme.color.accent, "Jarvis is speaking"],
                [muted, "mic-off", Theme.color.textMuted, "Microphone muted"]
            ];
            const badges = [Theme.badge.tone.info, Theme.badge.tone.accent, Theme.badge.tone.neutral, Theme.badge.tone.danger].map(t => String(Qt.color(t.foreground)));
            for (const [values, name, colour, text] of rows) {
                const tip = text.split("\n");
                widget.shell = root.shellWith(values);
                compare(icon().name, name, name);
                compare(String(icon().color), String(Qt.color(colour)), name + " colour");
                verify(badges.indexOf(String(icon().color)) === -1, name + " draws no badge foreground");
                compare(button().label, "Jarvis");
                compare(tooltip().text, tip[0]);
                compare(JSON.stringify(tooltip().details), JSON.stringify(tip.slice(1)));
            }
        }

        function test_a_click_calls_console_once() {
            mouseClick(button());
            compare(JSON.stringify(root.calls), '[["console",""]]');
        }

        // The right-click menu holds the Jarvis menu the overlay opens too:
        // each entry calls its intent's handler once, or opens Jarvis's
        // Keys section through shell.surfaces, as the overlay's menu does,
        // and each toggle names its next action.
        function test_the_menu_holds_the_jarvis_menu_data() {
            return [
                { tag: "Mute microphone", index: 1, calls: '[["microphone-mute",""]]', pages: "[]" },
                { tag: "Mute Jarvis's voice", index: 0, calls: '[["voice-mute",""]]', pages: "[]" },
                { tag: "Stop Jarvis", index: 2, calls: '[["stop",""]]', pages: "[]" },
                { tag: "Key hints", index: 3, calls: "[]", pages: '[["vgs.jarvis","Settings/Keys"]]' }
            ];
        }
        function test_the_menu_holds_the_jarvis_menu(data) {
            let framePages = [];
            widget.frame = { hide: () => "ok", openPage: (page, tab) => { framePages = framePages.concat([[page, tab]]); return "ok"; } };
            compare(JSON.stringify(widget.frameActions.map(row => row.label)), JSON.stringify(["Mute Jarvis's voice", "Mute microphone", "Stop Jarvis", "Key hints"]));
            widget.frameActions[data.index].action();
            compare(JSON.stringify(root.calls), data.calls);
            compare(JSON.stringify(root.pages), data.pages);
            compare(JSON.stringify(framePages), "[]", "the menu opens its page through shell.surfaces, as the overlay's does");
            widget.frame = null;
            const values = root.ready({ voiceMute: { kind: "on" } });
            values.microphoneMute = { kind: "ready", muted: true };
            widget.shell = root.shellWith(values);
            compare(widget.frameActions[0].label, "Unmute Jarvis's voice");
            compare(widget.frameActions[1].label, "Unmute microphone");
        }

        function test_unknown_microphone_is_inert_in_the_real_frame_menu() {
            widget.frame = {
                hide: () => "ok",
                describe: () => ({ name: "Jarvis", page: "", readme: "", keys: [], stops: false, builtin: false, owner: "" })
            };
            const values = root.ready({});
            values.microphoneMute = { kind: "unavailable" };
            widget.shell = root.shellWith(values);
            mouseClick(button(), button().width / 2, button().height / 2, Qt.RightButton);
            tryCompare(widget, "frameMenuOpen", true);
            const menu = find(widget, node => node.triggerCurrent !== undefined && node.items !== undefined);
            verify(menu !== null, "the shared frame menu is built");
            const mic = menu.items().find(item => item.text === "Mute microphone");
            verify(mic !== undefined && mic.disabledReason !== "", "the real menu carries the source's unavailable reason");
            mouseClick(mic);
            compare(root.calls.length, 0, "the disabled menu entry sends no request");
            menu.close();
            tryCompare(widget, "frameMenuOpen", false);
            values.microphoneMute = { kind: "ready", muted: false };
            widget.shell = root.shellWith(values);
            mouseClick(button(), button().width / 2, button().height / 2, Qt.RightButton);
            tryCompare(widget, "frameMenuOpen", true);
            const readyMenu = find(widget, node => node.triggerCurrent !== undefined && node.items !== undefined);
            const available = readyMenu.items().find(item => item.text === "Mute microphone");
            compare(available.disabledReason, "");
            mouseClick(available);
            compare(JSON.stringify(root.calls), '[["microphone-mute",""]]');
        }

        // While the Resume offer stands, a click asks for the resume once and
        // the right-click menu offers Do not resume; without it, neither.
        function test_a_click_on_the_offer_resumes_once() {
            verify(widget.frameActions.every(row => row.label !== "Do not resume"), "no Do not resume without the offer");
            widget.shell = root.shellWith(Object.assign(root.ready({}),
                { jarvisSession: { model: null, since: null, offer: { unlock: "1password" }, steps: [], checkedAt: null } }));
            mouseClick(button());
            compare(JSON.stringify(root.calls), '[["resume-session",""]]');
            const dismiss = widget.frameActions.filter(row => row.label === "Do not resume");
            compare(dismiss.length, 1);
            dismiss[0].action();
            compare(JSON.stringify(root.calls), '[["resume-session",""],["dismiss-resume",""]]');
        }

        function test_space_return_and_enter_each_call_console_once() {
            for (const key of [Qt.Key_Space, Qt.Key_Return, Qt.Key_Enter]) {
                root.calls = [];
                button().forceActiveFocus();
                verify(button().activeFocus, "the button holds focus");
                keyClick(key);
                compare(JSON.stringify(root.calls), '[["console",""]]', "key " + key);
            }
        }

        // expected-log: jarvis widget: microphone-mute unknown: microphone-mute -- the widget reports a reply other than ok
        function test_a_refused_reply_is_reported() {
            root.reply = "unknown: microphone-mute";
            compare(widget.offer("microphone-mute"), "unknown: microphone-mute");
        }

        function test_an_unknown_tone_throws() {
            let message = "";
            try { widget.toneColor("loud"); } catch (e) { message = e.message; }
            compare(message, 'jarvis widget: tone "loud" is not one of calm, accent, info, danger, neutral');
        }
    }
}
