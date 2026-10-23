import QtQuick
import QtTest
import Quickshell.Hyprland
import qs.Commons
import qs.Core
import qs.Ui
import "../../shell/plugins/vgs.settings"

// The Plugins window's height: the content and chrome of the page it
// shows, up to a cap, the share of the screen's height
// `size.window.tallHeightShare` names, or the room under the window's
// pinned top, `size.window.topShare` of the screen's height, to the screen
// less `size.window.gutter` at its bottom, when that is less. A plugin page
// is measured on the tab it shows, so each tab fits its view with no room
// below and no scroll, and a tab change takes the other tab's height; the
// list is measured with its rows. A page past the cap takes the cap and
// scrolls, and its Pane takes the cap too, so the window host maps it
// there. While the window shows, a page change asks the compositor for
// the window's client and places it, at its own top-left and width, at
// that height in one request; the request's effect is read back in the
// settings smoke row. The height keeps to the screen the client is on,
// which a page change finds by the name of the client's monitor, and to
// the room below the client's top. The shell here stands in for
// the window's capabilities: a manager whose rows the test names, the
// screen the window opened on, of a fixed size, beside the screen of the
// client's monitor, a key capture and a compositor whose window reads the
// test answers; the Hyprland stand-in reserves that monitor's top 40 px.
Item {
    id: root
    width: 1200
    height: 1200

    // The screen the window opened on, which Hyprland reserves nothing of,
    // and the screen of the client's monitor, which each window state the
    // test answers sets.
    readonly property var screen: ({ name: "DP-1", x: 0, y: 0, width: 1920, height: 1080 })
    property var monitorScreen: null

    // One manager row, as the manager lists it, with FIELDS over a plugin
    // that has nothing to set, and the rows of its fields as the core
    // judges them with its schema (PluginLogic.fieldRows).
    function pluginRow(fields) {
        const row = Object.assign({
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
            guide: null,
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
        row.fieldRows = PluginLogic.fieldRows(row.schema, {});
        return row;
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
        const setup = {};
        for (let i = 0; i < 40; i++) {
            schema["field" + i] = { type: "boolean", label: "Field " + i };
            settings["field" + i] = false;
            setup["step" + i] = { type: "state", label: "Step " + i, setup: true };
        }
        const manifest = { status: setup };
        return pluginRow({ id: "acme.long", name: "Long", schema: schema, settings: settings, status: PluginLogic.statusRows(manifest, {}) });
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
        // The page the window reported shown, each report in order.
        property var viewed: []
        function rescan() { return "ok"; }
        function viewPage(id) { viewed = viewed.concat([id]); }
    }

    QtObject {
        id: fakeCompositor
        // The window reads waiting on an answer, and each place asked for,
        // in order.
        property var reads: []
        property var calls: []
        // A window state each read takes at once, or null to hold reads
        // until answer().
        property var sync: null
        function readWindows(done) {
            if (sync !== null) done(sync);
            else reads = reads.concat([done]);
        }
        function placeWindow(address, x, y, width, height) {
            calls = calls.concat([["place", address, x, y, width, height]]);
            return "ok";
        }
        // The floating Plugins client, as one j/clients entry, with FIELDS
        // over it.
        function client(fields) {
            return Object.assign({ class: "org.vgs.shell", title: "Plugins", mapped: true, address: "0xb", monitor: 3, floating: true, fullscreen: 0, at: [70, 60], size: [512, 300] }, fields);
        }
        // The state of CLIENTS, as Hyprland's j/clients, on monitor DP-3,
        // whose screen is BOTTOM tall, 1000 unless given, with SCREEN's
        // fields over it, and whose top 40 px are reserved: a work area from
        // the screen's y + 40 to its y + BOTTOM. Quickshell hands the
        // reserved list over as a Qt sequence, an array-like that is no
        // Array.
        function state(clients, bottom, screen) {
            root.monitorScreen = Object.assign({ name: "DP-3", x: 0, y: 0, width: 1600, height: bottom === undefined ? 1000 : bottom }, screen);
            Hyprland.monitors = { "DP-3": { lastIpcObject: { reserved: { length: 4, 0: 0, 1: 40, 2: 0, 3: 0 } } } };
            return { ok: true, clients: clients, monitors: [{ id: 3, name: "DP-3" }] };
        }
        // Answer every waiting read with state(CLIENTS, BOTTOM, SCREEN).
        function answer(clients, bottom, screen) {
            const waiting = reads;
            reads = [];
            for (const done of waiting) done(state(clients, bottom, screen));
        }
    }

    QtObject {
        id: fakeShell
        readonly property var manager: fakeManager
        readonly property var compositor: fakeCompositor
        readonly property var manifest: ({ id: "vgs.settings", name: "Plugins" })
        readonly property var screens: ({ current: root.screen, get all() { return root.monitorScreen === null ? [root.screen] : [root.screen, root.monitorScreen]; } })
        readonly property var shortcut: ({ capture: null })
    }

    Component {
        id: windowComponent
        Window { shell: fakeShell }
    }

    TestCase {
        name: "settingsWindowHeight"
        when: windowShown

        // The cap on the screen the window opened on, read from the tokens
        // alone: the share of its height, or the room from the pinned top
        // to its bottom less the gutter.
        function cap() {
            const top = Math.round(Theme.size.window.topShare * root.screen.height);
            return Math.floor(Math.min(Theme.size.window.tallHeightShare * root.screen.height, root.screen.height - Theme.size.window.gutter - top));
        }

        function descendants(item) {
            const found = [item];
            for (let i = 0; i < found.length; i++)
                for (const child of found[i].children || []) found.push(child);
            return found;
        }

        function init() {
            fakeManager.plugins = root.fewRows;
            fakeManager.viewed = [];
            fakeCompositor.reads = [];
            fakeCompositor.calls = [];
            fakeCompositor.sync = null;
            root.monitorScreen = null;
            Hyprland.monitors = {};
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
            verify(pages.length >= 2, "the plugin page has Settings and Details tabs");
            return { page: page, pane: pane, tabs: tabs, settings: pages[0], setup: pages.length === 3 ? pages[1] : null, details: pages[pages.length - 1] };
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

        // The core tells a plugin while its page is shown: the window
        // reports the page it shows, the list as none, and none as it closes.
        function test_the_window_reports_the_page_it_shows() {
            const window = opened(JSON.stringify({ plugin: "acme.short" }));
            compare(fakeManager.viewed, ["acme.short"], "an opened page is reported");
            window.showList(Qt.OtherFocusReason);
            compare(fakeManager.viewed, ["acme.short", ""], "the list shows no plugin's page");
            window.show("acme.long", Qt.OtherFocusReason);
            window.close();
            compare(fakeManager.viewed, ["acme.short", "", "acme.long", ""], "a closing window shows none");
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
            compare(p.pane.cappedHeight, cap(), "the page's Pane takes the cap, the height the window host maps it at");
            verify(p.page.scrollArea.contentHeight > p.page.scrollArea.height, "the page's content runs past its view");
            verify(p.page.scrollArea.overflowing, "a long page scrolls");
        }

        function test_plugin_tabs_stay_pinned_and_switch_from_the_end() {
            const window = opened('{"plugin":"acme.long"}');
            const p = parts(window);
            compare(p.tabs.model, ["Settings", "Setup", "Details"]);
            const strip = p.page.stickyTabs;
            const surface = descendants(p.page).find(item => item.objectName === "stickyTabsSurface");
            const scroll = p.page.scrollArea;
            verify(strip !== null && surface !== undefined, "the page has pinned tabs over a masking surface");
            compare(surface.parent, strip.background, "the cover belongs to the tab bar background");
            verify(strip.z > p.tabs.currentPage.parent.z,
                "the tab bar draws above the scrolling page and its cover");

            scroll.contentY = 0;
            waitForRendering(window);
            const restTop = strip.mapToItem(p.page, 0, 0).y;
            const firstRow = descendants(p.settings).find(item => item.label === "Enabled");
            verify(firstRow !== undefined, "the Settings page has its first switch row");
            const restGap = firstRow.mapToItem(scroll.contentItem, 0, 0).y - scroll.contentPadding - p.tabs.tabs.height;
            compare(restGap, Theme.stack.page, "the first row follows the tab strip by the page spacing token");

            compare(surface.color, Qt.color(Theme.surface.level.raised.background), "the cover matches the application window's raised background");
            compare(surface.mapToItem(scroll, 0, 0).y, scroll.focusInset + scroll.clipPadding,
                "the masking surface covers the clip's top ring room");
            compare(surface.mapToItem(scroll, 0, 0).y + surface.height, strip.mapToItem(scroll, 0, 0).y + strip.height,
                "the fade becomes visible below the pinned tabs");
            compare(scroll.fadeTopInset, surface.mapToItem(scroll, 0, 0).y + surface.height - scroll.focusInset - scroll.clipPadding,
                "the mask keeps the pinned tab band opaque before fading the page");
            const names = ["Settings", "Setup", "Details"];
            function verifyLabelsDraw() {
                for (const name of names) {
                    const button = descendants(strip).find(item => item.text === name && item.checked !== undefined);
                    verify(button !== undefined && button.visible, "the " + name + " tab button is visible");
                    const label = descendants(button).find(item => item.objectName === "tabLabel");
                    verify(label !== undefined && label.visible && label.opacity > 0, "the " + name + " tab label is visible");
                }
            }
            // QtTest 6.12 grabImage crops the window at the item's local
            // x/y, not its scene position (quicktestresult.cpp). PluginPage
            // sits at x=window.width in a translated parent; capture the
            // containing window at the scene origin and map every sample there.
            // https://github.com/qt/qtdeclarative/blob/v6.12.0/src/qmltest/quicktestresult.cpp
            const frames = [];
            function capture() {
                verify(waitForPolish(window), "the window's layout is ready to capture");
                verify(waitForRendering(window), "the window has rendered the requested state");
                compare(window.mapToItem(null, 0, 0), Qt.point(window.x, window.y), "the capture owner's local and scene origins agree");
                const image = grabImage(window);
                const thumb = scroll.bar.thumb;
                const at = thumb.mapToItem(window, 0, 0);
                const sx = image.width / window.width, sy = image.height / window.height;
                frames.push({ image: image, thumb: scroll.bar.visible ? Qt.rect(Math.floor(at.x * sx), Math.floor(at.y * sy),
                    Math.ceil((at.x + thumb.width) * sx) - Math.floor(at.x * sx),
                    Math.ceil((at.y + thumb.height) * sy) - Math.floor(at.y * sy)) : Qt.rect(0, 0, 0, 0) });
                return image;
            }
            function glyphEdge(color, foreground) {
                const background = Qt.color(Theme.surface.level.raised.background);
                const ink = Qt.color(foreground);
                return !Qt.colorEqual(color, background) && !Qt.colorEqual(color, ink)
                    && ["r", "g", "b"].every(channel => color[channel] >= Math.min(background[channel], ink[channel])
                        && color[channel] <= Math.max(background[channel], ink[channel]));
            }
            function sameRenderedPixels(first, second, item, box) {
                const region = box || Qt.rect(0, 0, item.width, item.height);
                const origin = item.mapToItem(window, region.x, region.y);
                const scaleX = first.width / window.width;
                const scaleY = first.height / window.height;
                const left = Math.floor(origin.x * scaleX);
                const top = Math.floor(origin.y * scaleY);
                const right = Math.ceil((origin.x + region.width) * scaleX);
                const bottom = Math.ceil((origin.y + region.height) * scaleY);
                compare(first.width, second.width, "rest and scrolled captures have the same width");
                compare(first.height, second.height, "rest and scrolled captures have the same height");
                verify(left >= 0 && top >= 0 && right <= first.width && bottom <= first.height,
                    "the tab ink region fits inside the rendered page");
                const labels = names.map(name => {
                    const button = descendants(strip).find(item => item.text === name && item.checked !== undefined);
                    const label = descendants(button).find(item => item.objectName === "tabLabel");
                    const at = label.mapToItem(window, 0, 0);
                    return { x: at.x * scaleX, y: at.y * scaleY, width: label.width * scaleX, height: label.height * scaleY,
                        color: button.checked ? Theme.tabs.active : Theme.tabs.foreground };
                });
                const thumbs = [first, second].map(image => frames.find(frame => frame.image === image).thumb);
                for (let y = top; y < bottom; y++) {
                    for (let x = left; x < right; x++) {
                        const before = first.pixel(x, y), after = second.pixel(x, y);
                        if (Qt.colorEqual(before, after)) continue;
                        // ScrollArea's smooth layer resamples antialiased glyph
                        // edges as its source moves. Keep their ink/background
                        // boundary exact; only intermediate ink in both frames
                        // is outside this surrounding-paint comparison.
                        const label = labels.find(label => x >= label.x && x < label.x + label.width && y >= label.y && y < label.y + label.height);
                        if (label !== undefined && glyphEdge(before, label.color) && glyphEdge(after, label.color)) continue;
                        // The existing scrollbar thumb moves between frames;
                        // tst_scroll owns that behavior. Compare the rest of
                        // the gutter, including the edge to its right, exactly.
                        if (thumbs.some(thumb => x >= thumb.x && x < thumb.x + thumb.width && y >= thumb.y && y < thumb.y + thumb.height)) continue;
                        return false;
                    }
                }
                return true;
            }
            function solidPixels(image, item, box, color) {
                const at = item.mapToItem(window, box.x, box.y);
                const sx = image.width / window.width, sy = image.height / window.height;
                verify(Math.ceil(at.x * sx) < Math.floor((at.x + box.width) * sx)
                    && Math.ceil(at.y * sy) < Math.floor((at.y + box.height) * sy), "the solid paint region contains device pixels");
                for (let y = Math.ceil(at.y * sy); y < Math.floor((at.y + box.height) * sy); y++)
                    for (let x = Math.ceil(at.x * sx); x < Math.floor((at.x + box.width) * sx); x++)
                        compare(image.pixel(x, y), Qt.color(color), "the expected solid paint at " + x + "," + y);
            }
            verifyLabelsDraw();
            for (let i = 0; i < names.length; i++) {
                mouseMove(p.page, p.page.width - 1, p.page.height - 1);
                wait(Theme.motion.duration.fast + 20);
                scroll.contentY = 0;
                waitForRendering(window);
                const atRest = capture();
                scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height);
                waitForRendering(window);
                const atEnd = capture();
                verify(atRest !== null && atEnd !== null, "the page renders at rest and at its scroll end");
                verify(scroll.contentY > 0, "the plugin page is scrolled before choosing " + names[i]);
                compare(strip.mapToItem(p.page, 0, 0).y, restTop, "the tabs keep their resting position at the page end");
                compare(surface.mapToItem(scroll, 0, 0).y, scroll.focusInset + scroll.clipPadding,
                    "the tab cover remains at the clip's top while scrolled");
                compare(scroll.fadeTopInset, surface.mapToItem(scroll, 0, 0).y + surface.height - scroll.focusInset - scroll.clipPadding,
                    "the mask keeps the pinned tab band opaque while scrolled");
                verifyLabelsDraw();
                const bandTop = p.pane.contentInset + p.pane.headerHeight;
                const band = Qt.rect(0, bandTop, p.page.width,
                    strip.mapToItem(p.page, 0, strip.height).y - bandTop);
                verify(sameRenderedPixels(atRest, atEnd, p.page, band),
                    "the whole pinned band and its surrounding edges keep their resting paint at the end");
                scroll.contentY = (scroll.contentHeight - scroll.height) / 2;
                waitForRendering(window);
                verify(sameRenderedPixels(atRest, capture(), p.page, band),
                    "the whole pinned band and its surrounding edges keep their resting paint in the middle");
                scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height);
                if (atRest !== null && atEnd !== null) {
                    for (const name of names) {
                        const button = descendants(strip).find(item => item.text === name && item.checked !== undefined);
                        const label = descendants(button).find(item => item.objectName === "tabLabel");
                        verify(sameRenderedPixels(atRest, atEnd, label),
                            "the " + name + " tab label's rendered pixels stay unchanged while the page scrolls");
                    }
                }
                const activeButton = descendants(strip).find(item => item.checked === true);
                verify(activeButton !== undefined, "the selected tab button is present");
                if (activeButton !== undefined) {
                    const indicator = descendants(activeButton).find(item => item.objectName === "indicator");
                    verify(indicator !== undefined && indicator.visible, "the selected tab draws its indicator");
                    if (indicator !== undefined && atRest !== null && atEnd !== null) {
                        verify(sameRenderedPixels(atRest, atEnd, indicator),
                            "the active tab indicator's rendered pixels stay unchanged while the page scrolls");
                        solidPixels(atEnd, indicator, Qt.rect(0, 0, indicator.width, indicator.height), Theme.tabs.indicatorColor);
                    }
                }
                solidPixels(atEnd, surface, Qt.rect(0, 0, surface.width, strip.mapToItem(surface, 0, 0).y), Theme.surface.level.raised.background);
                compare(firstRow.mapToItem(scroll.contentItem, 0, 0).y - scroll.contentPadding - p.tabs.tabs.height, Theme.stack.page,
                    "the first row keeps its page spacing while content scrolls");
                const button = descendants(strip).find(item => item.text === names[i] && item.checked !== undefined);
                verify(button !== undefined, "the pinned " + names[i] + " tab can be found");
                // Read the painted fill, not just TabButton.down: the page's
                // opaque cover must leave the shared pressed background visible.
                for (const held of [activeButton, button]) {
                    mousePress(held);
                    tryCompare(held, "down", true);
                    waitForRendering(window);
                    const pressed = capture();
                    solidPixels(pressed, held, Qt.rect(Theme.border.thin, Theme.border.thin,
                        held.width - 2 * Theme.border.thin, Theme.border.thin), Theme.tabs.pressed);
                    mouseRelease(held);
                }
                waitForRendering(window);
                compare(p.tabs.currentIndex, i, "clicking the pinned " + names[i] + " tab switches pages");
            }
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

        // The one client of the shell's app-id titled Plugins is placed at
        // the new page's height, at its own top-left and width, in one
        // request; a client already that tall is left alone.
        function test_a_page_change_while_shown_places_the_window_client() {
            const window = opened('{"plugin":"acme.detailed"}');
            const p = parts(window);
            const settingsHeight = window.implicitHeight;
            fakeCompositor.reads = [];
            p.tabs.currentIndex = 1;
            waitForRendering(window);
            tryVerify(() => fakeCompositor.reads.length === 1, 1000, "the page change asks for the windows once");
            const client = (title, appClass, address, height) => fakeCompositor.client({ class: appClass, title: title, address: address, size: [512, height] });
            fakeCompositor.answer([client("Plugins", "kitty", "0xa", settingsHeight), client("Plugins", "org.vgs.shell", "0xb", settingsHeight), client("Other", "org.vgs.shell", "0xc", settingsHeight)], 2000);
            verify(window.implicitHeight > settingsHeight, "Details is taller than Settings");
            verify(window.implicitHeight <= Theme.size.window.tallHeightShare * 2000, "Details fits under the 2000 px monitor's cap");
            compare(fakeCompositor.calls, [["place", "0xb", 70, 60, 512, window.implicitHeight]], "the Plugins client takes Details' height at its top-left and width");
            p.tabs.currentIndex = 0;
            waitForRendering(window);
            tryVerify(() => fakeCompositor.reads.length === 1, 1000, "the return asks for the windows once");
            fakeCompositor.answer([client("Plugins", "org.vgs.shell", "0xb", window.implicitHeight)], 2000);
            compare(fakeCompositor.calls.length, 1, "a client already at the page's height is not placed again");
        }

        // A page past the cap places the window at the cap of the screen
        // the client is on, `size.window.tallHeightShare` of its height,
        // and the page scrolls inside: the owner's directive of
        // 2026-10-18 (VGS-1891) replaced the room as the bound.
        function test_a_long_page_places_the_window_at_the_cap() {
            const window = opened('{"plugin":"acme.short"}');
            fakeCompositor.reads = [];
            compare(window.openPlugin("acme.long", Qt.TabFocusReason), "ok");
            waitForRendering(window);
            tryVerify(() => fakeCompositor.reads.length === 1, 1000, "the page change asks for the windows once");
            const p = parts(window);
            const share = Math.floor(Theme.size.window.tallHeightShare * 1000);
            verify(Math.ceil(p.pane.uncappedHeight) > share, "the long page runs past the client screen's cap: " + p.pane.uncappedHeight + " > " + share);
            verify(60 + share <= 1000 - Theme.size.window.gutter, "the cap fits below the client's top");
            compare(window.implicitHeight, cap(), "the window's own request stays at the cap");
            fakeCompositor.answer([fakeCompositor.client({ size: [512, 300] })]);
            compare(fakeCompositor.calls, [["place", "0xb", 70, 60, 512, share]], "the window takes the cap, not the long page's height");
        }

        // The window keeps its top: a page change moves only its bottom
        // edge. The room below the top bounds the height, so a window the
        // user dragged low keeps its top and takes the room left under it,
        // and one dragged above the room's top keeps that top too.
        function test_a_window_keeps_its_top_data() {
            // bottom: the monitor's bottom, its top 40 px reserved; at: the
            // client's y; from: the client's height before, as a step from
            // the page's height; low: whether the room under `at` is less
            // than the page, so the height is that room; placed: whether a
            // place is asked.
            return [
                { tag: "takes its page's height at its top", bottom: 2000, at: 480, from: -200, low: false, placed: true },
                { tag: "keeps a top above the room's top", bottom: 2000, at: 10, from: -200, low: false, placed: true },
                { tag: "dragged low takes the room under its top", bottom: 1000, at: 888, from: -40, low: true, placed: true },
                { tag: "one pixel past its page is placed exactly", bottom: 2000, at: 480, from: 1, low: false, placed: true },
                { tag: "at its page's height is left alone", bottom: 2000, at: 480, from: 0, low: false, placed: false }
            ];
        }
        function test_a_window_keeps_its_top(data) {
            const window = opened('{"plugin":"acme.detailed"}');
            const p = parts(window);
            fakeCompositor.reads = [];
            p.tabs.currentIndex = 1;
            waitForRendering(window);
            tryVerify(() => fakeCompositor.reads.length === 1, 1000, "the page change asks for the windows once");
            const page = window.implicitHeight;
            const under = data.bottom - Theme.size.window.gutter - data.at;
            compare(under < page, data.low, "the room under y " + data.at + ", " + under + ", against the page's " + page);
            const height = data.low ? under : page;
            fakeCompositor.answer([fakeCompositor.client({ at: [70, data.at], size: [512, height + data.from] })], data.bottom);
            compare(fakeCompositor.calls, data.placed ? [["place", "0xb", 70, data.at, 512, height]] : []);
        }

        // The client's own monitor bounds it, not the screen the window
        // opened on: a client dragged to a 1440 px monitor stacked below
        // the 1080 px one keeps its place there.
        function test_a_window_on_another_monitor_keeps_to_that_monitor() {
            const window = opened('{"plugin":"acme.detailed"}');
            const p = parts(window);
            fakeCompositor.reads = [];
            p.tabs.currentIndex = 1;
            waitForRendering(window);
            tryVerify(() => fakeCompositor.reads.length === 1, 1000, "the page change asks for the windows once");
            const height = window.implicitHeight;
            const at = 1080 + 60;
            verify(at + height > 1080 - Theme.size.window.gutter, "Details at y " + at + " passes the opening screen's room: " + height);
            verify(at + height <= 1080 + 1440 - Theme.size.window.gutter, "Details at y " + at + " fits the lower monitor's room: " + height);
            fakeCompositor.answer([fakeCompositor.client({ at: [70, at], size: [512, height - 200] })], 1440, { y: 1080 });
            compare(fakeCompositor.calls, [["place", "0xb", 70, at, 512, height]]);
        }

        // A client whose monitor no screen of the shell names is left alone,
        // with a warning that names the monitor.
        // expected-log: settings: resize screen=none monitor=DP-3 -- the test hands a monitor no screen names on purpose
        function test_a_client_on_no_known_screen_is_left_alone() {
            const window = opened('{"plugin":"acme.detailed"}');
            const p = parts(window);
            fakeCompositor.reads = [];
            p.tabs.currentIndex = 1;
            waitForRendering(window);
            tryVerify(() => fakeCompositor.reads.length === 1, 1000, "the page change asks for the windows once");
            fakeCompositor.answer([fakeCompositor.client({ size: [512, window.implicitHeight - 200] })], undefined, { name: "HDMI-A-1" });
            compare(fakeCompositor.calls, []);
        }

        // A tiled or fullscreen Plugins window is the user's layout: a page
        // change sends it nothing.
        function test_a_tiled_or_fullscreen_window_is_left_alone_data() {
            return [
                { tag: "tiled", fields: { floating: false } },
                { tag: "fullscreen", fields: { fullscreen: 1 } }
            ];
        }
        function test_a_tiled_or_fullscreen_window_is_left_alone(data) {
            const window = opened('{"plugin":"acme.detailed"}');
            const p = parts(window);
            fakeCompositor.reads = [];
            p.tabs.currentIndex = 1;
            waitForRendering(window);
            tryVerify(() => fakeCompositor.reads.length === 1, 1000, "the page change asks for the windows once");
            fakeCompositor.answer([fakeCompositor.client(Object.assign({ size: [512, window.implicitHeight - 200] }, data.fields))]);
            compare(fakeCompositor.calls, []);
        }

        // A read answered in the turn of the tab change, before a frame
        // lays the page out, still takes the new tab's height: fitWindow
        // lays the shown page out before it reads the height.
        function test_a_read_in_the_tab_change_turn_takes_the_new_tab_height() {
            const window = opened('{"plugin":"acme.detailed"}');
            const p = parts(window);
            p.tabs.currentIndex = 1;
            waitForRendering(window);
            const details = window.implicitHeight;
            p.tabs.currentIndex = 0;
            waitForRendering(window);
            verify(window.implicitHeight < details, "Details is the taller tab: " + window.implicitHeight + " < " + details);
            fakeCompositor.calls = [];
            fakeCompositor.sync = fakeCompositor.state([fakeCompositor.client({ size: [512, details - 200] })], 2000);
            p.tabs.currentIndex = 1;
            window.fitWindow();
            const calls = fakeCompositor.calls;
            fakeCompositor.sync = null;
            compare(calls, [["place", "0xb", 70, 60, 512, details]]);
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

        // The search filter never sizes the window: a filtered list keeps
        // the height of the list with every row.
        function test_a_filtered_list_keeps_the_full_list_height() {
            const window = opened('{}');
            const p = listParts(window);
            const full = p.page.fitHeight;
            const drawn = p.pane.uncappedHeight;
            compare(full, drawn, "the unfiltered list's height is its drawn height");
            p.page.query = "short";
            waitForRendering(window);
            verify(p.pane.uncappedHeight < drawn, "the filter draws fewer rows: " + p.pane.uncappedHeight + " < " + drawn);
            compare(p.page.fitHeight, full, "the filtered list keeps the full list's height");
            compare(window.implicitHeight, Math.ceil(full), "the window asks for the full list's height");
            p.page.query = "";
            waitForRendering(window);
            compare(p.page.fitHeight, full);
        }

        function test_a_long_list_takes_the_cap_and_scrolls() {
            fakeManager.plugins = root.manyRows;
            const window = opened('{}');
            const p = listParts(window);
            compare(window.implicitHeight, cap());
            compare(p.pane.cappedHeight, cap(), "the list's Pane takes the cap, the height the window host maps it at");
            verify(p.page.scrollArea.contentHeight > p.page.scrollArea.height, "the list runs past its view");
            verify(p.page.scrollArea.overflowing, "a long list scrolls");
        }
    }
}
