import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.ai-usage"

// The card's delivered label/value text is the UI result: limits, then
// account credits and resets share body type and one right value edge.
Item {
    width: 700
    height: 1000
    Component {
        id: panelWindow
        Window {
            property alias panel: panel
            width: 700
            height: 1000
            Panel { id: panel; width: implicitWidth; height: implicitHeight }
        }
    }
    TestCase {
        name: "aiUsageCardRows"
        when: windowShown

        function initTestCase() { verify(Theme.name !== ""); }
        function find(node, predicate) {
            if (predicate(node)) return node;
            for (const child of node.children) {
                const found = find(child, predicate);
                if (found !== null) return found;
            }
            return null;
        }
        function fontOf(label) {
            return [label.font.family, label.font.pixelSize, label.font.weight, label.font.letterSpacing, label.font.capitalization];
        }
        function test_account_rows_follow_the_limits_data() {
            const rows = [];
            for (const theme of ["vgs", "catalog/flexoki-light", "catalog/dracula"])
                for (const view of ["compact", "full"])
                    rows.push({ tag: theme + " " + view, theme: theme, view: view });
            return rows;
        }
        function test_account_rows_follow_the_limits(data) {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../../themes/" + data.theme + "/theme.json"), false);
            request.send();
            compare(UnitTheme.override(JSON.parse(request.responseText).tokens), "ok");
            const window = createTemporaryObject(panelWindow, null, { screen: Qt.application.screens[0], visible: true });
            verify(window !== null);
            const now = Date.now();
            window.panel.shell = { settings: { view: data.view }, ipc: { call: () => "ok" }, configure: { set: () => "ok" },
                status: { values: { usage: { readAt: now, gatewayKey: null, accounts: [
                    { id: "codex-a", provider: "codex", state: "ok", email: "a@example.com", readAt: now, credits: null,
                        details: { creditPools: [{ kind: "codex", balance: "10", unlimited: false }], availableResets: 3 },
                        windows: [{ name: "seven_day", usedPercent: 4, resetsAt: now + 86400000 }] }
                ] } } } };
            const label = text => find(window.panel, item => item.text === text && item.role !== undefined);
            tryVerify(() => label("Resets") !== null, 5000, "the card draws Resets after its API credits");
            const title = label("Codex"), weekly = label("Weekly limit"), credits = label("API credits"), resets = label("Resets");
            verify(title !== null && weekly !== null && credits !== null && resets !== null);
            compare(title.role, "eyebrow");
            compare(String(title.color), String(Qt.color(Theme.text.eyebrow.color)));
            compare(title.font.pixelSize, Theme.text.eyebrow.size);
            const values = [label("4%"), label("10"), label("3")];
            verify(values.every(value => value !== null));
            const rows = [weekly, credits, resets];
            tryVerify(() => rows.every(row => row.width > 0) && resets.mapToItem(window.panel, 0, 0).y > credits.mapToItem(window.panel, 0, 0).y
                && credits.mapToItem(window.panel, 0, 0).y > weekly.mapToItem(window.panel, 0, 0).y, 5000, "the shared rows settle");
            for (let i = 0; i < rows.length; i++) {
                compare(rows[i].role, "body");
                compare(fontOf(rows[i]), fontOf(weekly));
                compare(values[i].role, "body");
                compare(fontOf(values[i]), fontOf(values[0]));
                compare(rows[i].parent.parent.parent, weekly.parent.parent.parent, "one shared row list");
                compare(rows[i].mapToItem(window.panel, 0, 0).x, weekly.mapToItem(window.panel, 0, 0).x);
                compare(values[i].mapToItem(window.panel, values[i].width, 0).x,
                    values[0].mapToItem(window.panel, values[0].width, 0).x, "one right value edge");
            }
            const tops = [title, weekly, credits, resets].map(item => item.mapToItem(window.panel, 0, 0).y);
            verify(tops.every((top, at) => at === 0 || top > tops[at - 1]), "title, limits, credits, resets");
        }
    }
}
