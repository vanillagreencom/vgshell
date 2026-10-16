import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.jarvis"
import "../../shell/plugins/vgs.jarvis/Session.js" as Session

// The Jarvis bar widget: the icon and tone it draws for the status values a
// stand-in `shell` hands it, and that a click, Space, Return and keypad
// Enter each make exactly one `mute` call through `shell.ipc`. The bar
// layer takes no keyboard focus in the live shell, so this test is where
// the keys are proven. WidgetView.js's own table is
// scripts/test-jarvis-widget.js; this test reads what the widget draws.
Item {
    id: root
    width: 200
    height: 60

    property var calls: []
    property string reply: "ok"

    // A shell with VALUES as its status and an ipc that records each call.
    function shellWith(values) {
        return {
            status: { values: values },
            settings: { mode: "hold" },
            shortcut: { keys: { talk: "SUPER+code:108", mute: "SUPER+SHIFT+code:108", stop: "SUPER+ALT+PERIOD", confirm: "SUPER+ALT+Y" } },
            ipc: { call: (name, arg) => { root.calls = root.calls.concat([[name, arg]]); return root.reply; } }
        };
    }
    // Status values over Session's initial record with REGIONS set.
    function ready(regions) {
        const s = Object.assign(JSON.parse(JSON.stringify(Session.initial())), { gate: { kind: "up" } }, regions);
        return { daemon: { tone: "info", text: "Jarvis is ready; microphone is off" }, audio: { tone: "ok", text: "Device list ready" },
            detail: { phase: Session.phaseOf(s), seq: 1, state: s } };
    }

    Widget { id: widget }

    TestCase {
        name: "jarvisWidget"
        when: windowShown

        function init() {
            UnitTheme.reset();
            root.calls = [];
            root.reply = "ok";
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
            const rows = [
                [{ daemon: { tone: "info", text: "Starting" }, detail: null }, "loader", Theme.color.info, "Jarvis is starting\nWait for Jarvis to start.\nClick or press Super+Shift+Right Alt to mute."],
                [root.ready({}), "mic", Theme.bar.foreground, "Jarvis is ready\nHold Super+Right Alt and speak.\nClick or press Super+Shift+Right Alt to mute."],
                [root.ready({ capture: { kind: "open", gen: 1, op: 2, mode: "hold" } }), "audio-lines", Theme.color.accent, "Jarvis is listening\nSpeak now.\nClick or press Super+Shift+Right Alt to mute."],
                [root.ready({ turn: { kind: "thinking", gen: 1, op: 3, deadline: 70 } }), "brain", Theme.color.info, "Jarvis is thinking\nPress Super+Alt+Period to stop.\nClick or press Super+Shift+Right Alt to mute."],
                [root.ready({ playback: { kind: "playing", gen: 1, op: 5, source: 4, interruptible: true, admission: { kind: "started" }, deadline: null } }), "volume-2", Theme.color.accent, "Jarvis is speaking\nPress Super+Alt+Period to stop.\nClick or press Super+Shift+Right Alt to mute."],
                [root.ready({ mute: { kind: "on" } }), "mic-off", Theme.color.textMuted, "Jarvis is muted\nClick or press Super+Shift+Right Alt to unmute."],
                [{ daemon: { tone: "danger", text: "Jarvis needs Node 22 or later", hint: "Update Node to version 22 or later, then turn Jarvis off and on again in Settings > Jarvis", lines: ["jarvis: node=21.0.0 need=22"] }, detail: null }, "circle-alert", Theme.color.danger, "Jarvis needs Node 22 or later\nUpdate Node to version 22 or later, then turn Jarvis off and on again in Settings > Jarvis.\nClick or press Super+Shift+Right Alt to mute."]
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

        function test_a_click_calls_mute_once() {
            mouseClick(button());
            compare(JSON.stringify(root.calls), '[["mute",""]]');
        }

        function test_space_return_and_enter_each_call_mute_once() {
            for (const key of [Qt.Key_Space, Qt.Key_Return, Qt.Key_Enter]) {
                root.calls = [];
                button().forceActiveFocus();
                verify(button().activeFocus, "the button holds focus");
                keyClick(key);
                compare(JSON.stringify(root.calls), '[["mute",""]]', "key " + key);
            }
        }

        // expected-log: jarvis widget: mute unknown: mute -- the widget reports a reply other than ok
        function test_a_refused_reply_is_reported() {
            root.reply = "unknown: mute";
            compare(widget.toggleMute(), "unknown: mute");
        }

        function test_an_unknown_tone_throws() {
            let message = "";
            try { widget.toneColor("loud"); } catch (e) { message = e.message; }
            compare(message, 'jarvis widget: tone "loud" is not one of calm, accent, info, danger, neutral');
        }
    }
}
