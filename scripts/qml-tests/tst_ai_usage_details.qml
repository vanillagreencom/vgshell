import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.ai-usage"

// The delivered card readings are the result: one muted capital heading,
// a space step closer than a page heading, and body-sized rows in plain ink. Geometry reads the production
// meters, including a barless credit and a final row with no trailing room.
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
    UnitCase {
        name: "aiUsageDetails"
        when: windowShown

        function initTestCase() { verify(Theme.name !== ""); }
        function init() {
            UnitTheme.reset();
            Time.now = new Date(Date.UTC(2026, 10, 18));
        }
        function all(node, predicate) {
            return (predicate(node) ? [node] : []).concat(...node.children.map(child => all(child, predicate)));
        }
        function label(node, text) {
            const owner = displayedTextItems(node).find(item => displayedText(item) === text);
            return owner === undefined ? null : displayedTextRenderer(owner);
        }
        function reading(node, text) {
            return all(node, item => item.visible && item.modelData !== undefined && item.modelData !== null
                && item.modelData.label === text && item.spacing !== undefined)[0] || null;
        }
        function fontOf(item) {
            return [item.font.family, item.font.pixelSize, item.font.weight, item.font.letterSpacing, item.font.capitalization];
        }
        function scenarios() {
            const now = Time.now.getTime();
            return [
                { tag: "Copilot", provider: "copilot", limit: "AI credits",
                    windows: [{ name: "credits", usedPercent: 82.8, resetsAt: now + 86400000 }],
                    credits: { unit: "credits", used: 828000, granted: 1000000 },
                    details: { copilotMonthUsed: 900000, copilotRenewsAt: Date.UTC(2026, 11, 1) },
                    expected: [["Month credits used", "900k", true], ["Renews", "2026-12-01", true]] },
                { tag: "Claude", provider: "claude", limit: "Weekly limit",
                    windows: [{ name: "seven_day", usedPercent: 60, resetsAt: now + 86400000 },
                        { name: "five_hour", usedPercent: 40, resetsAt: now + 3600000 }],
                    details: { creditPools: [
                        { kind: "labelled", label: "Cloud credits", usedPercent: 20, used: 12, limit: 60, resetsAt: null },
                        { kind: "labelled", label: "Unreported credit", used: null, limit: null, resetsAt: null }
                    ], claudeExtra: { used: 10, limit: 100, currency: "USD" } },
                    expected: [["Cloud credits", "$12.00 of $60.00", false], ["Extra usage", "$10.00 of $100.00", true]] },
                { tag: "Codex", provider: "codex", limit: "Weekly limit",
                    windows: [{ name: "seven_day", usedPercent: 4, resetsAt: now + 86400000 }],
                    details: { creditPools: [{ kind: "codex", balance: "10", unlimited: false }], availableResets: 3 },
                    expected: [["API credits", "10", false], ["Resets", "3", false]] },
                { tag: "Gateway", provider: "gateway", limit: "AI Gateway credits",
                    windows: [{ name: "credits", usedPercent: 30, resetsAt: null }],
                    details: { gateway: { balance: 10.5, totalUsed: 5.25 } },
                    expected: [["API credits", "$10.50", false], ["Total used", "$5.25", true]] }
            ];
        }
        function openCard(data) {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../../themes/" + data.theme + "/theme.json"), false);
            request.send();
            compare(UnitTheme.override(JSON.parse(request.responseText).tokens), "ok");
            const window = createTemporaryObject(panelWindow, null, { screen: Qt.application.screens[0], visible: true });
            verify(window !== null);
            const source = data.source;
            const now = Time.now.getTime();
            const details = data.absent ? { creditPools: [{ kind: "codex", balance: "0" }], availableResets: 0 } : source.details;
            window.panel.shell = { settings: { view: data.view }, ipc: { call: () => "ok" }, configure: { set: () => "ok" },
                status: { values: { usage: { readAt: now, gatewayKey: null, accounts: [
                    { id: "account", provider: source.provider, state: "ok", email: "fixture@example.invalid", readAt: now,
                        windows: source.windows, credits: source.credits || null, details: details }
                ] } } } };
            tryVerify(() => window.panel.cardOf("account") !== null, 5000, "the account card is created");
            const card = window.panel.cardOf("account");
            tryVerify(() => label(card, source.limit) !== null && reading(card, source.limit).width > 0, 5000, "the account readings settle");
            return card;
        }
        function test_secondary_hierarchy_data() {
            const rows = [];
            for (const source of scenarios())
                for (const theme of ["vgs", "catalog/flexoki-light"])
                    for (const view of ["compact", "full"])
                        for (const absent of [false, true])
                            rows.push({ tag: source.tag + " " + theme + " " + view + (absent ? " absent" : ""),
                                source: source, theme: theme, view: view, absent: absent });
            return rows;
        }
        function test_secondary_hierarchy(data) {
            const card = openCard(data), source = data.source;
            const expected = data.absent ? [] : source.expected.filter(row => !row[2] || data.view === "full");
            const headings = semanticLabelItems(card).filter(item => displayedText(item) === "Details").map(item => displayedTextRenderer(item));
            compare(headings.length, expected.length > 0 ? 1 : 0, "no empty or duplicate details block");
            for (const omitted of source.expected.filter(row => data.absent || (row[2] && data.view !== "full")))
                compare(label(card, omitted[0]), null, "unreported or compact-hidden readings take no room");
            compare(label(card, "Unreported credit"), null, "a pool with no value has no row");
            if (expected.length === 0) return;
            const heading = headings[0], primary = label(card, source.limit), first = reading(card, source.limit);
            compare(heading.role, "label");
            compare(heading.font.capitalization, Font.AllUppercase, "a capital label");
            compare(String(heading.color), String(Qt.color(Theme.color.textMuted)), "muted ink, neither accent nor body");
            verify(heading.font.pixelSize < primary.font.pixelSize, "smaller than the body rows");
            const limits = source.windows.map(row => reading(card, row.name === "credits" ? source.limit
                : row.name === "seven_day" ? "Weekly limit" : "5-hour limit"));
            const lastLimit = limits[limits.length - 1];
            tryVerify(() => heading.mapToItem(card, 0, 0).y >= lastLimit.mapToItem(card, 0, lastLimit.height).y,
                5000, "all plan limits precede the secondary heading");
            // Ink to capital top, as SectionHeader measures its space above.
            const header = heading.parent.parent;
            const gap = () => header.mapToItem(card, 0, header.topPadding).y + Math.floor(header.titleCapTop)
                - (lastLimit.mapToItem(card, 0, lastLimit.height).y - Math.floor(Theme.inkBelow(lastLimit)));
            const wantGap = Theme.stack.heading - Theme.space.xs;
            tryVerify(() => gap() === wantGap, 5000, "the heading settles");
            compare(gap(), wantGap, "one space step under a page heading's gap");
            let previous = heading;
            for (const wanted of expected) {
                const row = reading(card, wanted[0]);
                verify(row !== null, wanted[0] + " uses the common reading style");
                const name = label(row, wanted[0]);
                const value = all(row, item => item.role === "body" && item !== name)[0];
                verify(value !== undefined);
                compare(name.role, "body");
                compare(fontOf(name), fontOf(primary));
                compare(fontOf(value), fontOf(primary));
                compare(value.text, wanted[1], "the provider's delivered reading");
                compare(String(value.color), String(Qt.color(Theme.color.text)), "every details figure is plain ink");
                compare(row.parent, first.parent, "one shared row list");
                compare(name.mapToItem(card, 0, 0).x, primary.mapToItem(card, 0, 0).x);
                const primaryValue = all(first, item => item.role === "body" && item !== primary)[0];
                compare(value.mapToItem(card, value.width, 0).x, primaryValue.mapToItem(card, primaryValue.width, 0).x);
                const above = previous;
                tryVerify(() => row.mapToItem(card, 0, 0).y >= above.mapToItem(card, 0, above.height).y, 5000, "one ordered details block");
                previous = row;
            }
        }

        function test_details_leave_out_limit_figures_data() {
            return [
                { tag: "month total repeats the limit", month: 828000, shown: false },
                { tag: "month total of its own", month: 900000, shown: true }
            ];
        }
        function test_details_leave_out_limit_figures(data) {
            const copilot = scenarios()[0];
            const source = Object.assign({}, copilot, { details: { copilotMonthUsed: data.month, copilotRenewsAt: Date.UTC(2026, 11, 1) } });
            const card = openCard({ source: source, theme: "vgs", view: "full", absent: false });
            tryVerify(() => label(card, "Renews") !== null, 5000, "the details block is drawn");
            compare(label(card, "Month credits used") !== null, data.shown, "a details row says only what no limit row says");
        }

        function test_meter_rhythm_data() {
            const claude = scenarios()[1], codex = scenarios()[2];
            const barless = JSON.parse(JSON.stringify(claude));
            delete barless.details.creditPools[0].usedPercent;
            const detailsOnly = Object.assign({}, codex, { windows: [], limit: "API credits" });
            return [
                { tag: "metered limits and details", source: claude, view: "full", absent: false,
                    groups: [["Weekly limit", "5-hour limit"], ["Cloud credits", "Extra usage"]] },
                { tag: "final meter", source: claude, view: "full", absent: true,
                    groups: [["Weekly limit", "5-hour limit"]] },
                { tag: "barless credit", source: barless, view: "full", absent: false,
                    groups: [["Weekly limit", "5-hour limit"], ["Cloud credits", "Extra usage"]] },
                { tag: "compact has no meters", source: claude, view: "compact", absent: false,
                    groups: [["Weekly limit", "5-hour limit"], ["Cloud credits"]] },
                { tag: "barless balances", source: codex, view: "full", absent: false,
                    groups: [["Weekly limit"], ["API credits", "Resets"]] },
                { tag: "details without limits", source: detailsOnly, view: "full", absent: false,
                    groups: [["API credits", "Resets"]] }
            ].map(row => Object.assign({ theme: "vgs" }, row));
        }
        // Every gap the rows draw that differs from the view's rhythm, as
        // "row: got want". A meter's Loader builds after its row is first
        // laid out, so the readings are taken again until they settle.
        function rhythmFaults(card, data) {
            const faults = [];
            const first = reading(card, data.groups[0][0]);
            if (first === null) return ["rows are not drawn"];
            const list = first.parent;
            if (data.source.windows.length > 0) {
                if (first.y !== 0) faults.push("leading spacer: " + first.y + " 0");
            } else {
                const heading = label(card, "Details").parent.parent;
                if (heading.y !== 0) faults.push("details heading start: " + heading.y + " 0");
            }
            const gap = data.view === "full" ? Theme.stack.inline : Theme.row.lineGap;
            let last = first;
            for (const group of data.groups) {
                for (let i = 0; i < group.length; i++) {
                    const row = reading(card, group[i]), name = label(row, group[i]);
                    const meter = all(row, item => item instanceof ProgressBar && item.visible)[0];
                    const end = meter || name.parent;
                    const bottom = end.mapToItem(list, 0, end.height).y;
                    if (i + 1 < group.length) {
                        const next = label(reading(card, group[i + 1]), group[i + 1]);
                        const got = next.mapToItem(list, 0, 0).y - bottom, want = gap + (meter ? Theme.stack.inline : 0);
                        if (got !== want) faults.push(group[i] + " to " + group[i + 1] + ": " + got + " " + want);
                    } else {
                        const tail = row.mapToItem(list, 0, row.height).y - bottom;
                        if (tail !== 0) faults.push(group[i] + " trailing spacer: " + tail + " 0");
                    }
                    last = row;
                }
            }
            if (list.height !== last.y + last.height) faults.push("list bottom room: " + (list.height - last.y - last.height) + " 0");
            return faults;
        }
        function test_meter_rhythm(data) {
            const card = openCard(data);
            tryVerify(() => rhythmFaults(card, data).length === 0, 5000, "rows settle at the view's rhythm");
            compare(rhythmFaults(card, data), [], "only a meter gains one inline gap; no spacer at either end");
        }
    }
}
