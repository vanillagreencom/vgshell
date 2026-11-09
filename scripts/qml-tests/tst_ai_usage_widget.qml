import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.ai-usage"

// The AI Usage gauge draws a share from the warning percent in
// Theme.color.warning, under the shipped vgs theme and the catalog's
// flexoki-light, and never in the warning badge foreground; a lower share
// draws in the bar's foreground. The panel's provider marks, on a card and
// in the reset calendar, load at their size in device pixels at scale 1
// and 2. A card keeps its More actions, with the keys and an open menu,
// through Time.now's tick, and a Hide moves the keys to a neighbour.
Item {
    id: root
    width: 200
    height: 60

    Widget { id: widget }
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
        name: "aiUsageWidget"
        when: windowShown

        function init() {
            UnitTheme.reset();
            Time.now = new Date(2026, 8, 30, 20, 34, 0);
        }

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
        function images(node) {
            const own = node.sourceSize !== undefined && node.fillMode !== undefined && node.status !== undefined ? [node] : [];
            return own.concat(...node.children.map(images));
        }
        function glyph() {
            const button = find(widget, n => n.iconName !== undefined && n.label !== undefined);
            return find(button.contentItem, n => n.name !== undefined && n.paths !== undefined);
        }
        function usedAt(percent) {
            widget.shell = { settings: {}, status: { values: { usage: { accounts: [
                { id: "a", provider: "claude", state: "ok", email: "a@example.com", windows: [{ name: "5h", usedPercent: percent }] }] } } } };
        }

        // A mark's implicit size is the size of the image Qt loaded for it,
        // in pixels (QQuickImageBase sets it from the pixmap, divided by
        // the pixmap's own ratio, which is 1 for a data URL): at scale 2 a
        // mark drawn from an image of its logical size is scaled up. The
        // window opens on the offscreen screen of the row's scale
        // (scripts/qml-unit.sh).
        function test_marks_load_at_the_display_scale_data() {
            return [{ tag: "scale 1", scale: 1 }, { tag: "scale 2", scale: 2 }];
        }
        function test_marks_load_at_the_display_scale(data) {
            const screen = Qt.application.screens[data.scale - 1];
            const window = panelWindow.createObject(null, { screen: screen, x: screen.virtualX + 10, y: screen.virtualY + 10 });
            window.visible = true;
            const now = Time.now.getTime();
            window.panel.shell = { settings: { view: "full" }, ipc: { call: () => "ok" }, configure: { set: () => "ok" },
                status: { values: { usage: { readAt: now, gatewayKey: null, accounts: [
                    { id: "claude-a", provider: "claude", state: "ok", email: "a@example.com", readAt: now, credits: null, details: {},
                        windows: [{ name: "seven_day", usedPercent: 40, resetsAt: now + 2 * 86400000 }] }] } } } };
            find(window.panel, n => n.label === "Reset calendar").checked = true;
            // The one card's mark and the calendar's, the panel's images,
            // told apart by their sizes.
            const marks = images(window.panel);
            compare(marks.map(mark => mark.width).sort(), [Theme.icon.size.md, Theme.icon.size.sm].sort(), "the card and the calendar each draw a mark");
            for (const mark of marks) {
                const name = mark.width === Theme.icon.size.md ? "the card's mark" : "the calendar's mark";
                compare(mark.Screen.devicePixelRatio, data.scale, "the window draws at its screen's scale");
                tryCompare(mark, "status", Image.Ready);
                verify(mark.width > 0, name + " has a size");
                compare([mark.implicitWidth, mark.implicitHeight], [mark.width * data.scale, mark.height * data.scale],
                    name + " loads at its size in device pixels");
            }
            window.destroy();
        }

        // A panel on the scale 1 screen over one ok account per email, in
        // that order, whose configure.set writes the setting into the
        // shell it hands the panel, as the core's new shell does.
        function panelOver(emails) {
            const screen = Qt.application.screens[0];
            const window = panelWindow.createObject(null, { screen: screen, x: screen.virtualX + 10, y: screen.virtualY + 10 });
            window.visible = true;
            const now = Time.now.getTime();
            const accounts = emails.map((email, at) => ({ id: "claude-" + at, provider: "claude", state: "ok", email: email, readAt: now,
                credits: null, details: {}, windows: [{ name: "five_hour", usedPercent: 40, resetsAt: now + 2 * 3600000 }] }));
            const shell = { settings: { view: "full", sort: "provider", hidden: [] }, ipc: { call: () => "ok" },
                status: { values: { usage: { readAt: now, gatewayKey: null, accounts: accounts } } } };
            shell.configure = { set: (key, value) => {
                const settings = Object.assign({}, window.panel.shell.settings);
                settings[key] = value;
                window.panel.shell = Object.assign({}, window.panel.shell, { settings: settings });
                return "ok";
            } };
            window.panel.shell = shell;
            window.requestActivate();
            tryCompare(window, "active", true);
            return window;
        }
        // The More actions button of the card whose account line is EMAIL.
        function moreActionsOf(panel, email) {
            const line = find(panel, n => n.text === email && n.role === "hint");
            for (let at = line; at !== null; at = at.parent) {
                const button = find(at, n => n.label === "More actions");
                if (button !== null) return button;
            }
            return null;
        }
        function menuOf(button) { return find(button, n => n.triggerCurrent !== undefined); }

        // Time.now ticks each minute, and every status write hands the
        // panel fresh rows; a card stays the same item through both, so
        // its More actions keeps the keys, its ring and its open menu.
        function test_a_card_outlives_the_minute_tick() {
            const window = panelOver(["a@example.com", "b@example.com"]);
            const button = moreActionsOf(window.panel, "a@example.com");
            button.forceActiveFocus(Qt.TabFocusReason);
            verify(button.visualFocus, "More actions shows its ring before the tick");
            Time.now = new Date(Time.now.getTime() + 60000);
            wait(0);
            verify(moreActionsOf(window.panel, "a@example.com") === button, "the tick keeps the card's More actions");
            verify(button.activeFocus && button.visualFocus, "More actions keeps the keys and its ring through the tick");
            const menu = menuOf(button);
            button.clicked();
            verify(menu.opened, "More actions opens its menu");
            Time.now = new Date(Time.now.getTime() + 60000);
            wait(0);
            verify(menuOf(moreActionsOf(window.panel, "a@example.com")) === menu && menu.opened, "the menu stays open through the tick");
            menu.close();
            window.destroy();
        }

        // A Hide from the card's menu moves the keys to the More actions of
        // the card that takes its place, else of the card before it, else
        // to Check now.
        function test_hide_moves_the_keys_on_data() {
            return [
                { tag: "to the next card", emails: ["a@example.com", "b@example.com", "c@example.com"], hide: "b@example.com", to: "c@example.com" },
                { tag: "to the card before the last", emails: ["a@example.com", "b@example.com", "c@example.com"], hide: "c@example.com", to: "b@example.com" },
                { tag: "to Check now from the only card", emails: ["a@example.com"], hide: "a@example.com", to: "" }
            ];
        }
        function test_hide_moves_the_keys_on(data) {
            const window = panelOver(data.emails);
            const button = moreActionsOf(window.panel, data.hide);
            const target = data.to === "" ? find(window.panel, n => n.text === "Check now" && n.clicked !== undefined) : moreActionsOf(window.panel, data.to);
            verify(target !== null && target !== button, "the panel draws the control the keys move to");
            button.forceActiveFocus(Qt.TabFocusReason);
            button.clicked();
            const menu = menuOf(button);
            verify(menu.opened, "More actions opens its menu");
            menu.triggerCurrent();
            tryVerify(() => moreActionsOf(window.panel, data.hide) === null, 5000, "Hide takes the card away");
            window.requestActivate();
            tryCompare(window, "active", true);
            tryVerify(() => target.activeFocus, 5000, "the keys move " + data.tag);
            window.destroy();
        }

        function test_shares_draw_their_colour_data() {
            return [{ tag: "vgs", theme: "vgs" }, { tag: "flexoki-light", theme: "catalog/flexoki-light" }];
        }
        function test_shares_draw_their_colour(data) {
            compare(UnitTheme.override(themeTokens(data.theme)), "ok");
            usedAt(90);
            compare(widget.tone, "warning");
            compare(String(glyph().color), String(Qt.color(Theme.color.warning)), "warning");
            verify(String(glyph().color) !== String(Qt.color(Theme.badge.tone.warning.foreground)), "warning draws no badge foreground");
            usedAt(40);
            compare(widget.tone, "normal");
            compare(String(glyph().color), String(Qt.color(Theme.bar.foreground)), "normal");
        }
    }
}
