import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.agent-warden"

// The Agent Warden shield draws in the Theme.color role of its state's
// tone, `neutral` in textMuted, under the shipped vgs theme and the
// catalog's flexoki-light, with its count on or off, and never in the
// badge foreground of that tone; its corner count takes the level of that
// tone.
Item {
    id: root
    width: 200
    height: 60

    Widget { id: widget }

    TestCase {
        name: "agentWardenWidget"
        when: windowShown

        function init() { UnitTheme.reset(); }

        function themeTokens(path) {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../../themes/" + path + "/theme.json"), false);
            request.send();
            return JSON.parse(request.responseText).tokens;
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
        function glyph() {
            return find(button().contentItem, n => n.name !== undefined && n.paths !== undefined);
        }
        function themes() {
            const out = [];
            for (const [tag, theme] of [["vgs", "vgs"], ["flexoki-light", "catalog/flexoki-light"]])
                for (const shown of [true, false]) out.push({ tag: tag + (shown ? "" : "-no-count"), theme: theme, showCount: shown });
            return out;
        }
        function cleanup() { widget.settings = ({}); }

        function test_states_draw_their_colour_role_data() { return themes(); }
        function test_states_draw_their_colour_role(data) {
            compare(UnitTheme.override(themeTokens(data.theme)), "ok");
            widget.settings = ({ showCount: data.showCount });
            const rows = [
                [{ state: "calm", agents: 2 }, "textMuted", "neutral", "normal"],
                [{ state: "look", issues: 1, items: [{ kind: "leftover", level: "look", count: 1, processes: 1 }] }, "warning", "warning", "warning"],
                [{ state: "problem", issues: 1, items: [{ kind: "scan-failed", level: "problem" }] }, "danger", "danger", "danger"],
                [{ state: "not-set-up" }, "textMuted", "neutral", "normal"]
            ];
            for (const [detail, role, badge, level] of rows) {
                widget.shell = { status: { values: { detail: detail } } };
                const drawn = String(glyph().color);
                compare(drawn, String(Qt.color(Theme.color[role])), detail.state);
                verify(drawn !== String(Qt.color(Theme.badge.tone[badge].foreground)), detail.state + " draws no badge foreground");
                compare(button().countLevel, level, detail.state + " counts at its tone's level");
            }
        }

        // Working draws once a move is reported, and its tooltip reads
        // Commons.Duration, which the unit runner does not host; its tone
        // is read through the widget's own map.
        function test_working_is_the_accent_data() { return themes(); }
        function test_working_is_the_accent(data) {
            compare(UnitTheme.override(themeTokens(data.theme)), "ok");
            compare(String(Qt.color(widget.toneColor("accent"))), String(Qt.color(Theme.color.accent)));
            verify(String(Qt.color(widget.toneColor("accent"))) !== String(Qt.color(Theme.badge.tone.accent.foreground)));
        }

        function test_an_unknown_tone_throws() {
            let message = "";
            try { widget.toneColor("loud"); } catch (e) { message = e.message; }
            compare(message, 'agent-warden widget: tone "loud" is not one of neutral, accent, warning, danger');
        }
    }
}
