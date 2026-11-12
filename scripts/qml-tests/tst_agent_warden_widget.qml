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
// tone, `neutral` for a calm or information-only state, so one state
// takes one colour in both themes whatever hue the accent has.
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
            const item = level => ({ kind: "any", key: "any", level: level, title: "Something.", detail: null, actions: [] });
            const rows = [
                [{ state: "calm", agents: 2, items: [], causes: [] }, "textMuted", "neutral", "neutral"],
                [{ state: "info", agents: 2, items: [item("info")], causes: [] }, "textMuted", "neutral", "neutral"],
                [{ state: "warn", agents: 2, items: [item("warn")], causes: [] }, "warning", "warning", "warning"],
                [{ state: "danger", agents: 2, items: [item("danger")], causes: [] }, "danger", "danger", "danger"],
                [{ state: "not-set-up", agents: null, items: [], causes: null }, "textMuted", "neutral", "neutral"]
            ];
            for (const [detail, role, badge, level] of rows) {
                widget.shell = { status: { values: { detail: detail } } };
                const drawn = String(glyph().color);
                compare(drawn, String(Qt.color(Theme.color[role])), detail.state);
                verify(drawn !== String(Qt.color(Theme.badge.tone[badge].foreground)), detail.state + " draws no badge foreground");
                compare(button().countLevel, level, detail.state + " counts at its tone's level");
            }
        }

        function test_an_unknown_tone_throws() {
            let message = "";
            try { widget.toneColor("loud"); } catch (e) { message = e.message; }
            compare(message, 'agent-warden widget: tone "loud" is not one of neutral, warning, danger');
        }
    }
}
