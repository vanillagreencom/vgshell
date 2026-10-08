import QtQuick
import QtTest
import qs.Commons
import qs.Core
import qs.Ui
import "../../shell/plugins/vgs.settings"

// The Plugins window's height: the content and chrome of the page it opens
// on, up to a cap, the share of the screen's height
// `size.window.tallHeightShare` names, or the screen less
// `size.window.gutter` a side when that is less. A plugin page is measured
// on the taller of its Settings and Details tabs, so the taller tab fits
// its view with no room below and no scroll, and a tab change keeps the
// height; the list is measured with its rows. A page past the cap takes
// the cap and scrolls. The shell here stands in for the window's
// capabilities: a manager whose rows the test names, a screen of a fixed
// size and a key capture.
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
        id: fakeShell
        readonly property var manager: fakeManager
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
            p.tabs.currentIndex = p.settings.height >= p.details.height ? 0 : 1;
            waitForRendering(window);
            verify(window.implicitHeight < cap(), "a short page opens under the cap: " + window.implicitHeight + " < " + cap());
            compare(window.implicitHeight, Math.ceil(p.pane.uncappedHeight), "the window is the pane's content and chrome on the taller tab");
            verify(fits(p.page.scrollArea), "the taller tab fills its view: view " + p.page.scrollArea.height + ", content " + p.page.scrollArea.contentHeight);
            verify(!p.page.scrollArea.overflowing, "a short page does not scroll");
        }

        function test_a_long_page_takes_the_cap_and_scrolls() {
            const window = opened('{"plugin":"acme.long"}');
            const p = parts(window);
            compare(window.implicitHeight, cap());
            verify(p.page.scrollArea.contentHeight > p.page.scrollArea.height, "the page's content runs past its view");
            verify(p.page.scrollArea.overflowing, "a long page scrolls");
        }

        function test_the_taller_details_tab_sets_the_height() {
            const window = opened('{"plugin":"acme.detailed"}');
            const p = parts(window);
            compare(p.tabs.currentIndex, 0, "the page opens on Settings");
            verify(!p.details.visible, "the Details tab is hidden while Settings shows");
            verify(p.details.height > p.settings.height, "Details measures taller while hidden: " + p.details.height + " > " + p.settings.height);
            const height = window.implicitHeight;
            verify(height < cap(), "the page fits under the cap");
            const room = p.page.scrollArea.height - p.page.scrollArea.contentHeight;
            fuzzyCompare(room, p.details.height - p.settings.height, 1, "Settings leaves Details' extra height below it");
            p.tabs.currentIndex = 1;
            waitForRendering(window);
            compare(window.implicitHeight, height, "a tab change keeps the height");
            verify(fits(p.page.scrollArea), "Details fills its view: view " + p.page.scrollArea.height + ", content " + p.page.scrollArea.contentHeight);
            p.tabs.currentIndex = 0;
            waitForRendering(window);
            compare(window.implicitHeight, height, "a return to Settings keeps the height");
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
