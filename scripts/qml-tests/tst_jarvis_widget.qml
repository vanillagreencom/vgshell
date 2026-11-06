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
            screens: { current: null },
            session: { locked: false },
            status: { values: values },
            settings: { holdToTalk: false, voiceProvider: "local", home: "" },
            shortcut: { keys: { talk: "SUPER+code:44", "voice-mute": "SUPER+CTRL+M", deny: null, stop: "SUPER+CTRL+X", confirm: "SUPER+CTRL+Y", console: "SUPER+ALT+C" } },
            ipc: { call: (name, arg) => { root.calls = root.calls.concat([[name, arg]]); return root.reply; } },
            surfaces: { openPage: (page, tab) => { root.pages = root.pages.concat([[page, tab]]); return "ok"; } }
        };
    }
    // Status values over Session's initial record with REGIONS set.
    function ready(regions) {
        const s = Object.assign(JSON.parse(JSON.stringify(Session.initial())), { gate: { kind: "up" }, barIndicator: { kind: "present", gen: 0 } }, regions);
        return { microphoneMute: { kind: "ready", muted: false }, daemon: { tone: "info", text: "Jarvis is ready; microphone is off" }, audio: { tone: "ok", text: "Device list ready" },
            detail: { phase: Session.phaseOf(s), seq: 1, state: s } };
    }

    Widget { id: widget }
    // Both real views consume the same status publication. The hidden
    // console is read for its Needs you tab's actual unreadCounts binding.
    Console { id: jarvisConsole; visible: false; shell: widget.shell }

    UnitCase {
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
        function collect(node, test) {
            let out = test(node) ? [node] : [];
            for (const child of node.children) out = out.concat(collect(child, test));
            return out;
        }

        function themeTokens(path) {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../../themes/" + path + "/theme.json"), false);
            request.send();
            return JSON.parse(request.responseText).tokens;
        }

        // The J stays in every state. Its shared dot draws the Theme.color
        // role beside it, under vgs and flexoki-light.
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
                [{ daemon: { tone: "info", text: "Starting" }, detail: null }, Theme.color.info, "info", "Jarvis: Starting", 0],
                [root.ready({}), Theme.bar.foreground, "", "Jarvis: Ready", 0],
                [root.ready({ conversation: { kind: "active", purpose: "conversation" } }), Theme.bar.foreground, "", "Jarvis: Ready", 0],
                [root.ready({ capture: { kind: "open", gen: 1, op: 2, mode: "conversation" } }), Theme.color.accent, "success", "Jarvis: Listening", 0],
                [root.ready({ turn: { kind: "thinking", gen: 1, op: 3, deadline: 70 } }), Theme.color.info, "info", "Jarvis: Thinking", 0],
                [root.ready({ playback: { kind: "playing", gen: 1, op: 5, source: 4, interruptible: true, admission: { kind: "started" }, deadline: null } }), Theme.color.accent, "success", "Jarvis: Speaking", 0],
                [muted, Theme.color.textMuted, "warning", "Jarvis: Microphone muted", 0],
                [root.ready({ gate: { kind: "down", reason: "unconfigured" } }), Theme.color.textMuted, "warning", "Jarvis: Not set up", 1],
                [root.ready({ fault: { kind: "error", reason: "brain=stream-error", retry: 0 } }), Theme.color.danger, "danger", "Jarvis: Problem", 1]
            ];
            const badges = [Theme.badge.tone.info, Theme.badge.tone.accent, Theme.badge.tone.neutral, Theme.badge.tone.danger].map(t => String(Qt.color(t.foreground)));
            for (const [values, colour, dotRole, text, actionLines] of rows) {
                widget.shell = root.shellWith(values);
                compare(icon().name, "vgs-letter-j", text);
                compare(String(icon().color), String(Qt.color(colour)), text + " colour");
                verify(badges.indexOf(String(icon().color)) === -1, text + " draws no badge foreground");
                compare(button().label, text);
                compare(tooltip().text, text);
                compare(tooltip().details.length, actionLines);
                compare(button().stateDot, dotRole);
                const dot = find(button(), n => n.objectName === "bar-item-state-dot");
                verify(dot !== null, "the shared BarItem owns the dot");
                tryCompare(dot, "active", dotRole !== "");
                if (dotRole !== "") {
                    verify(dot.item !== null);
                    compare(String(dot.item.color), String(Qt.color(Theme.color[dotRole])));
                }
                compare(collect(button(), n => n instanceof Badge).length, dotRole === "" ? 0 : 1, "no second dot or private badge");
            }
        }

        function test_count_equals_console_needs_you_data() {
            return [
                { tag: "unpublished", asks: undefined, count: "", drawn: "" },
                { tag: "status-full", asks: null, count: "", drawn: "" },
                { tag: "reading", asks: { kind: "reading" }, count: "", drawn: "" },
                { tag: "unavailable", asks: { kind: "unavailable", cause: "Fixture unavailable" }, count: "", drawn: "" },
                { tag: "zero", total: 0, count: "", drawn: "" },
                { tag: "three", total: 3, count: "3", drawn: "3" },
                { tag: "above-corner-limit", total: 13, count: "13", drawn: "9+" }
            ];
        }
        function test_count_equals_console_needs_you(data) {
            const values = root.ready({ capture: { kind: "open", gen: 1, op: 2, mode: "conversation" } });
            // JarvisProtocol.ownerAsksPage accepts an empty final page with
            // a non-null cursor. Its total is not that page's row count.
            if (data.total !== undefined) values.ownerAsks = {
                kind: "ready", homeId: "fixture-home", revision: "fixture-revision",
                observedAt: "2026-11-06T15:00:00.000Z", activeCount: data.total, snoozedCount: 0,
                active: [], snoozed: [], activeCursor: data.total > 0 ? "fixture-last-page" : null,
                activeNextCursor: null, snoozedCursor: null, snoozedNextCursor: null
            };
            else if (data.asks !== undefined) values.ownerAsks = data.asks;
            widget.shell = root.shellWith(values);
            const tabs = find(jarvisConsole, n => n.unreadCounts !== undefined && n.model !== undefined);
            verify(tabs !== null, "read the real Console tabs");
            const consoleCount = tabs.unreadCounts["Needs you"];
            compare(button().count, data.count, data.tag);
            compare(button().count, consoleCount === undefined ? "" : String(consoleCount), "same publication as Console");
            compare(button().implicitWidth, button().implicitHeight, "count takes no row width");
            compare(tooltip().text, "Jarvis: Listening");
            compare(tooltip().details.length, 0, "the count adds no tooltip line");
            const count = find(button(), n => n.objectName === "bar-item-count");
            verify(count !== null, "the shared BarItem owns the count");
            tryCompare(count, "active", data.count !== "");
            if (data.count !== "") {
                verify(count.item !== null);
                compare(count.item.text, data.count, "full total reaches the shared badge");
                compare(count.item.displayedText, data.drawn, "shared corner compaction");
                verify(button().label.indexOf(data.count) !== -1, "accessible name keeps the full count");
            }
            const dot = find(button(), n => n.objectName === "bar-item-state-dot");
            verify(dot !== null && dot.item !== null);
            compare(button().stateDot, "success", "the state remains independent of asks");
            compare(collect(button(), n => n instanceof Badge).length, data.count === "" ? 1 : 2, "one dot and at most one count");
            if (data.count !== "") verify(dot.x + dot.width <= count.x, "dot and count do not overlap");
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
                { tag: "New conversation", index: 3, calls: '[["new-conversation",""]]', pages: "[]" },
                { tag: "Hide Jarvis", index: 4, calls: '[["hide",""]]', pages: "[]" },
                { tag: "Key hints", index: 5, calls: "[]", pages: '[["vgs.jarvis","Settings/Keys"]]' }
            ];
        }
        function test_the_menu_holds_the_jarvis_menu(data) {
            let framePages = [];
            widget.frame = { hide: () => "ok", openPage: (page, tab) => { framePages = framePages.concat([[page, tab]]); return "ok"; } };
            compare(JSON.stringify(widget.frameActions.map(row => row.label)), JSON.stringify(["Mute Jarvis's voice", "Mute microphone", "Stop Jarvis", "New conversation", "Hide Jarvis", "Key hints"]));
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
            verify(renderedFrame(readyMenu.surface.scope), "the reopened menu lays out after its reason goes");
            mouseClick(available);
            compare(JSON.stringify(root.calls), '[["microphone-mute",""]]');
        }

        function test_hidden_icon_keeps_shared_listening_dot_and_count() {
            const values = root.ready({ visibility: { kind: "hidden" }, conversation: { kind: "active", purpose: "conversation" },
                input: { kind: "conversation" }, capture: { kind: "closed" } });
            widget.shell = root.shellWith(values);
            compare(icon().name, "vgs-letter-j-hidden");
            compare(button().stateDot, "success", "demand, not admitted capture, draws the badge");
            compare(button().tooltip, "Jarvis: Listening (hidden)");
            compare(widget.presentationItem, button(), "the host observes the actual shared BarItem");
            compare(widget.presentationKey, values.detail.state.gen + ":listening");
            compare(collect(button(), n => n instanceof Badge).length, 1, "no second listening badge");
            const show = widget.frameActions.find(row => row.icon === "eye");
            verify(show !== undefined && show.disabledReason === "");
            show.action();
            compare(JSON.stringify(root.calls), '[["show",""]]');
        }

        function test_hide_without_presented_widget_is_inert() {
            widget.frame = {
                hide: () => "ok",
                describe: () => ({ name: "Jarvis", page: "", readme: "", keys: [], stops: false, builtin: false, owner: "" })
            };
            widget.shell = root.shellWith(root.ready({ barIndicator: { kind: "gone" } }));
            mouseClick(button(), button().width / 2, button().height / 2, Qt.RightButton);
            tryCompare(widget, "frameMenuOpen", true);
            const menu = find(widget, n => n.triggerCurrent !== undefined && n.items !== undefined);
            const hide = menu.items().find(n => n.text === "Hide Jarvis");
            verify(hide !== undefined && hide.disabledReason !== "");
            mouseClick(hide);
            compare(root.calls.length, 0);
            menu.close();
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
