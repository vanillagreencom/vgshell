import QtQuick
import QtTest
import qs.Commons
import qs.Core
import qs.Ui
import "../../shell/plugins/vgs.settings"

// The Plugins window's height: the content and chrome of the page it
// shows, up to a cap, the share of the screen's height
// `size.window.tallHeightShare` names, or the screen less
// `size.window.gutter` a side when that is less. A plugin page is measured
// on the tab it shows, so each tab fits its view with no room below and no
// scroll, and a tab change takes the other tab's height; the list is
// measured with its rows. A page past the cap takes the cap and scrolls.
// While the window shows, a page change asks the compositor for the
// window's client and resizes it to that height, keeping its width; the
// dispatch's effect is read back in the settings smoke row. The shell here
// stands in for the window's capabilities: a manager whose rows the test
// names, a screen of a fixed size, a key capture and a compositor whose
// window reads the test answers.
Item {
    id: root
    width: 1200
    height: 1200

    readonly property var screen: ({ width: 1920, height: 1080 })

    // One manager row, as the manager lists it, with FIELDS over a plugin
    // that has nothing to set.
    function pluginRow(fields) {
        return Object.assign({
            id: "acme.short",
            name: "Short",
            version: "1",
            description: "Short plugin",
            author: "VGS",
            license: "",
            icon: "package",
            source: "bundled",
            enabled: true,
            alwaysOn: false,
            placed: false,
            kinds: ["service"],
            capabilities: [],
            schema: ({}),
            settings: ({}),
            settingChoices: ({}),
            status: [],
            secretLabel: "",
            tuis: [],
            builtins: [],
            opens: "",
            paneHolder: "",
            binds: [],
            requirements: [],
            errors: []
        }, fields);
    }

    // A page like VPN's: two switches.
    readonly property var shortRow: pluginRow({
        id: "acme.short",
        schema: ({
            autoconnect: { type: "boolean", label: "Connect at login" },
            killswitch: { type: "boolean", label: "Block traffic while disconnected" }
        }),
        settings: ({ autoconnect: true, killswitch: false })
    })

    readonly property var longRow: {
        const schema = {};
        const settings = {};
        for (let i = 0; i < 40; i++) {
            schema["field" + i] = { type: "boolean", label: "Field " + i };
            settings["field" + i] = false;
        }
        return pluginRow({ id: "acme.long", name: "Long", schema: schema, settings: settings });
    }

    // Nothing to set, and a description that runs over many lines.
    readonly property var detailedRow: pluginRow({
        id: "acme.detailed",
        name: "Detailed",
        description: Array(14).fill("This sentence makes the description of the plugin long enough to wrap over several lines of the Details tab.").join(" ")
    })

    readonly property var fewRows: [shortRow, longRow, detailedRow]
    readonly property var manyRows: {
        const rows = fewRows.slice();
        for (let i = 0; i < 40; i++) rows.push(pluginRow({ id: "acme.row" + i, name: "Row " + i }));
        return rows;
    }

    QtObject {
        id: fakeManager
        property var plugins: root.fewRows
        function rescan() { return "ok"; }
    }

    QtObject {
        id: fakeCompositor
        // The window reads waiting on an answer, and each resize and move
        // asked for, in order.
        property var reads: []
        property var calls: []
        function readWindows(done) { reads = reads.concat([done]); }
        function resizeWindow(address, width, height) {
            calls = calls.concat([["resize", address, width, height]]);
            return "ok";
        }
        function moveWindow(address, x, y) {
            calls = calls.concat([["move", address, x, y]]);
            return "ok";
        }
        // Answer every waiting read with CLIENTS, as Hyprland's j/clients,
        // on one monitor at scale 2 whose top 40 px are reserved: a work
        // area from y 40 to BOTTOM, 1000 unless given.
        function answer(clients, bottom) {
            const waiting = reads;
            reads = [];
            const monitors = [{ id: 3, x: 0, y: 0, width: 3200, height: 2 * (bottom === undefined ? 1000 : bottom), scale: 2, reserved: [0, 40, 0, 0] }];
            for (const done of waiting) done({ ok: true, clients: clients, monitors: monitors });
        }
    }

    QtObject {
        id: fakeShell
        readonly property var manager: fakeManager
        readonly property var compositor: fakeCompositor
        readonly property var manifest: ({ id: "vgs.settings", name: "Plugins" })
        readonly property var screens: ({ current: root.screen })
        readonly property var shortcut: ({ capture: null })
    }

    Component {
        id: windowComponent
        Window { shell: fakeShell }
    }

    TestCase {
        name: "settingsWindowHeight"
        when: windowShown

        // The cap, read from the tokens alone.
        function cap() {
            return Math.floor(Math.min(Theme.size.window.tallHeightShare * root.screen.height, root.screen.height - 2 * Theme.size.window.gutter));
        }

        function descendants(item) {
            const found = [item];
            for (let i = 0; i < found.length; i++)
                for (const child of found[i].children || []) found.push(child);
            return found;
        }

        function init() {
            fakeManager.plugins = root.fewRows;
            fakeCompositor.reads = [];
            fakeCompositor.calls = [];
        }

        // The list page and its pane.
        function listParts(window) {
            const page = descendants(window).find(item => item.fitHeight !== undefined && item.query !== undefined);
            const pane = descendants(page).find(item => item.uncappedHeight !== undefined);
            return { page: page, pane: pane };
        }

        // The plugin page's pane, its tab pages and its two pages.
        function parts(window) {
            const page = descendants(window).find(item => item.fitHeight !== undefined && item.row !== undefined);
            const pane = descendants(page).find(item => item.uncappedHeight !== undefined);
            const tabs = descendants(page).find(item => item.currentPage !== undefined && item.tabs !== undefined);
            const pages = tabs.currentPage.parent.children;
            compare(pages.length, 2, "the plugin page has a Settings and a Details tab");
            return { page: page, pane: pane, tabs: tabs, settings: pages[0], details: pages[1] };
        }

        function opened(payload) {
            const window = createTemporaryObject(windowComponent, root);
            verify(window !== null, "the window builds");
            window.open(payload);
            waitForRendering(window);
            return window;
        }

        // Room below the shown tab's content, and none past it.
        function fits(scroll) {
            return scroll.height >= scroll.contentHeight && scroll.height - scroll.contentHeight < 1;
        }

        function test_a_short_page_takes_its_content_height() {
            const window = opened('{"plugin":"acme.short"}');
            const p = parts(window);
            compare(p.tabs.currentIndex, 0, "the page opens on Settings");
            verify(window.implicitHeight < cap(), "a short page opens under the cap: " + window.implicitHeight + " < " + cap());
            compare(window.implicitHeight, Math.ceil(p.pane.uncappedHeight), "the window is the pane's content and chrome on Settings");
            verify(fits(p.page.scrollArea), "Settings fills its view: view " + p.page.scrollArea.height + ", content " + p.page.scrollArea.contentHeight);
            verify(!p.page.scrollArea.overflowing, "a short page does not scroll");
        }

        function test_a_long_page_takes_the_cap_and_scrolls() {
            const window = opened('{"plugin":"acme.long"}');
            const p = parts(window);
            compare(window.implicitHeight, cap());
            verify(p.page.scrollArea.contentHeight > p.page.scrollArea.height, "the page's content runs past its view");
            verify(p.page.scrollArea.overflowing, "a long page scrolls");
        }

        function test_a_tab_change_takes_the_shown_tab_height() {
            const window = opened('{"plugin":"acme.detailed"}');
            const p = parts(window);
            compare(p.tabs.currentIndex, 0, "the page opens on Settings");
            verify(p.details.height > p.settings.height, "Details is the taller tab: " + p.details.height + " > " + p.settings.height);
            const height = window.implicitHeight;
            const settingsChrome = p.pane.uncappedHeight - p.settings.height;
            compare(height, Math.ceil(p.pane.uncappedHeight), "the window is the pane's content and chrome on Settings");
            verify(fits(p.page.scrollArea), "Settings fills its view: view " + p.page.scrollArea.height + ", content " + p.page.scrollArea.contentHeight);
            p.tabs.currentIndex = 1;
            waitForRendering(window);
            compare(window.implicitHeight, Math.ceil(settingsChrome + p.details.height), "Details takes the chrome and its own height");
            verify(window.implicitHeight < cap(), "Details fits under the cap: " + window.implicitHeight + " < " + cap());
            verify(fits(p.page.scrollArea), "Details fills its view: view " + p.page.scrollArea.height + ", content " + p.page.scrollArea.contentHeight);
            verify(!p.page.scrollArea.overflowing, "Details that fits does not scroll");
            p.tabs.currentIndex = 0;
            waitForRendering(window);
            compare(window.implicitHeight, height, "a return to Settings takes the Settings height");
        }

        // The one client of the shell's app-id titled Plugins is resized to
        // the new page's height at its own width, then moved back to its
        // top-left, which Hyprland's resize does not keep; a client already
        // that tall is left alone.
        function test_a_page_change_while_shown_resizes_the_window_client() {
            const window = opened('{"plugin":"acme.detailed"}');
            const p = parts(window);
            const settingsHeight = window.implicitHeight;
            fakeCompositor.reads = [];
            p.tabs.currentIndex = 1;
            waitForRendering(window);
            tryVerify(() => fakeCompositor.reads.length === 1, 1000, "the page change asks for the windows once");
            const client = (title, appClass, address, height) => ({ class: appClass, title: title, mapped: true, address: address, monitor: 3, at: [70, 60], size: [512, height] });
            fakeCompositor.answer([client("Plugins", "kitty", "0xa", settingsHeight), client("Plugins", "org.vgs.shell", "0xb", settingsHeight), client("Other", "org.vgs.shell", "0xc", settingsHeight)]);
            verify(window.implicitHeight > settingsHeight, "Details is taller than Settings");
            verify(60 + window.implicitHeight <= 1000, "the grown window fits above the work area's bottom");
            compare(fakeCompositor.calls, [["resize", "0xb", 512, window.implicitHeight], ["move", "0xb", 70, 60]], "the Plugins client takes Details' height at its width and keeps its top-left");
            p.tabs.currentIndex = 0;
            waitForRendering(window);
            tryVerify(() => fakeCompositor.reads.length === 1, 1000, "the return asks for the windows once");
            fakeCompositor.answer([client("Plugins", "org.vgs.shell", "0xb", settingsHeight)]);
            compare(fakeCompositor.calls.length, 2, "a client already at the page's height is neither resized nor moved");
        }

        // A window that would pass the work area's bottom rises by the
        // overflow alone, and never above the work area's top.
        function test_a_grown_window_stays_on_its_monitor_data() {
            return [
                { tag: "rises by its overflow", bottom: 1000, rise: true },
                { tag: "stops at the work area's top", bottom: 300, rise: false }
            ];
        }
        function test_a_grown_window_stays_on_its_monitor(data) {
            const window = opened('{"plugin":"acme.detailed"}');
            const p = parts(window);
            const settingsHeight = window.implicitHeight;
            fakeCompositor.reads = [];
            p.tabs.currentIndex = 1;
            waitForRendering(window);
            tryVerify(() => fakeCompositor.reads.length === 1, 1000, "the page change asks for the windows once");
            const height = window.implicitHeight;
            verify(480 + height > data.bottom, "the window at y 480 would pass the work area's bottom: " + height);
            fakeCompositor.answer([{ class: "org.vgs.shell", title: "Plugins", mapped: true, address: "0xb", monitor: 3, at: [70, 480], size: [512, settingsHeight] }], data.bottom);
            compare(fakeCompositor.calls, [["resize", "0xb", 512, height], ["move", "0xb", 70, data.rise ? data.bottom - height : 40]]);
        }

        function test_a_short_list_takes_its_content_height() {
            const window = opened('{}');
            const p = listParts(window);
            compare(window.page, "");
            verify(window.implicitHeight < cap(), "a short list opens under the cap: " + window.implicitHeight + " < " + cap());
            compare(window.implicitHeight, Math.ceil(p.pane.uncappedHeight), "the window is the list's content and chrome");
            verify(fits(p.page.scrollArea), "the list fills its view: view " + p.page.scrollArea.height + ", content " + p.page.scrollArea.contentHeight);
            verify(!p.page.scrollArea.overflowing, "a short list does not scroll");
        }

        function test_a_long_list_takes_the_cap_and_scrolls() {
            fakeManager.plugins = root.manyRows;
            const window = opened('{}');
            const p = listParts(window);
            compare(window.implicitHeight, cap());
            verify(p.page.scrollArea.contentHeight > p.page.scrollArea.height, "the list runs past its view");
            verify(p.page.scrollArea.overflowing, "a long list scrolls");
        }
    }
}
