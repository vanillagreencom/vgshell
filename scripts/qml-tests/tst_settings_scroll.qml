import QtQuick
import QtQuick.Window
import QtTest
import qs.Unit
import qs.Commons
import qs.Core
import qs.Ui
import "../../shell/plugins/vgs.settings"

// A status-fed custom field loses its offers when its plugin stops. The
// page must leave the pressed switch in place when that exposes an editor.
Item {
    id: root
    width: 680
    height: 460
    property Item page: null
    property var fixtures: ({})

    function row(enabled, listCase) {
        // Registry.managerRows retains m.schema/m.fieldRows while replacing
        // state rows. Match that producer so a toggle is no manifest reload.
        const fixtureKey = listCase ? "list" : "flat";
        if (fixtures[fixtureKey] !== undefined)
            return Object.assign({}, fixtures[fixtureKey], { enabled: enabled, settingChoices: { home: enabled ? [{ label: "None", value: "none" }] : [] } });
        const schema = {};
        const settings = {};
        for (let i = 0; i < 15; i++) {
            schema["toggle" + i] = { type: "boolean", label: "Option " + i, group: "Options" };
            settings["toggle" + i] = true;
        }
        if (listCase) {
            schema.pads = { type: "list", label: "Pads", items: { command: { type: "string", label: "App", presets: [{ label: "Terminal", value: "terminal" }], allowCustom: true } }, defaults: { command: "terminal" } };
            settings.pads = [{ name: "1", command: "fixture-command-never-run" }];
        } else {
            schema.home = { type: "string", label: "Home folder", group: "Home", optionsFrom: "homes", allowCustom: true };
            settings.home = "none";
        }
        const result = {
            id: "acme.scroll", name: "Scroll", version: "1", description: "", author: "VGS", license: "", icon: "package", source: "bundled",
            enabled: enabled, alwaysOn: false, placed: true, kinds: ["service", "bar-widget"], capabilities: [],
            schema: schema, settings: settings, settingChoices: { home: enabled ? [{ label: "None", value: "none" }] : [] },
            fieldRows: PluginLogic.fieldRows(schema, {}), withheldFields: [], fieldProblems: {}, status: [], secretLabel: "", guide: null,
            tuis: [], builtins: [], opens: "", paneHolder: "", binds: [], requirements: [], errors: []
        };
        fixtures[fixtureKey] = result;
        return result;
    }

    Item {
        id: manager
        property var shell: null
        property var plugins: []
        property var installFailures: ({})
        property var capture: null
        property bool listCase: false
        property var current: root.row(true)
        function setEnabled(id, enabled) { current = root.row(enabled, listCase); return "ok"; }
        function replyOf() { return ""; }
        function editorOf() { return null; }
        function headReplies() { return []; }
    }
    Component {
        id: pageComponent
        PluginPage {
            width: root.width
            height: root.height
            maximumHeight: root.height
            panel: manager
            row: manager.current
        }
    }

    function descendants(item) {
        let out = [];
        for (const child of item.children) out = out.concat([child], descendants(child));
        return out;
    }
    UnitCase {
        name: "SettingsScroll"
        when: windowShown
        function enabledSwitch() {
            const field = descendants(page).find(item => item instanceof Field && semanticLabelItems(item).some(label => displayedText(label) === SettingValues.PAGE_LABELS.enabled));
            return descendants(field).find(item => item instanceof Switch);
        }

        function cleanup() {
            manager.plugins = [];
        }

        function init() {
            manager.current = root.row(true);
            manager.listCase = false;
            root.page = createTemporaryObject(pageComponent, root);
            verify(root.page !== null);
            verify(renderedFrame(root.page));
            // The page builds its groups past the first view behind the
            // first frame (FirstView); these cases read the whole page.
            const views = descendants(root.page).filter(item => item.firstViewRoot === true);
            verify(views.length > 0, "the page builds through a FirstView");
            tryVerify(() => views.every(view => view.settled), 5000, "the page's groups are built");
            root.page.scrollArea.contentY = 0;
        }

        function test_toggle_keeps_the_page_at_the_pressed_row_data() {
            return [
                { tag: "runtime choices off", list: false, wanted: false },
                { tag: "runtime choices on", list: false, wanted: true },
                { tag: "custom list off", list: true, wanted: false },
                { tag: "custom list on", list: true, wanted: true }
            ];
        }

        function test_toggle_keeps_the_page_at_the_pressed_row(data) {
            manager.listCase = data.list;
            manager.current = root.row(!data.wanted, data.list);
            verify(renderedFrame(page));
            page.scrollArea.contentY = 0;
            const before = page.scrollArea.contentY;
            mouseClick(enabledSwitch());
            tryCompare(manager.current, "enabled", data.wanted);
            verify(waitForPolish(page.Window.window));
            wait(0);
            verify(renderedFrame(page));
            compare(page.scrollArea.contentY, before);
        }

        // A linked open builds, in its own turn, through its target row,
        // with every row above it, and reveals the row; nothing after an
        // unbuilt row is built, so no later content draws in its place. Its
        // first view also fills the viewport below the revealed row, so the
        // first frame shows what the settled page shows there, and leaves
        // the rows past one window below it to the steps. A link into a
        // page past its first frame builds through the target in the same
        // turn and leaves the rest to the steps. A plain open fills the
        // viewport and leaves the rows past its first view to the steps
        // after it. The page has four groups of sixty rows, then the Pads
        // list, the Keys section and its panes holder's button. An open
        // shows the page as the Settings window does: the page shows,
        // hidden until then, and opens; or, from another plugin's settled
        // page, it takes the new plugin's row and opens, so none of the
        // last page's rows stays built. Each target stands past the first
        // window, near its group's top, so only the target row's own target
        // builds one window below it and no further: with it dropped, the
        // reveal's ensure builds through the row alone and the group's
        // target counts the room from the group's end. The panel lists
        // plugins, and the page's picker builds their entries only when its
        // menu opens or in the steps, never before the first frame; the
        // entries list every plugin, not the page's, so those built on the
        // other plugin's page stay built through the switch.
        function test_a_linked_open_builds_through_its_target_row_data() {
            return [
                { tag: "plain open", tab: "Settings", target: null, from: "hidden" },
                { tag: "linked open", tab: "Settings/g1t5", target: "g1t5", from: "hidden" },
                { tag: "link into a shown page", tab: "Settings/g3t5", target: "g3t5", from: "shown" },
                { tag: "plain open from another page", tab: "Settings", target: null, from: "another" },
                { tag: "linked open from another page", tab: "Settings/g1t5", target: "g1t5", from: "another" }
            ];
        }

        function test_a_linked_open_builds_through_its_target_row(data) {
            const schema = {};
            const settings = {};
            const order = [];
            for (let group = 0; group < 4; group++)
                for (let i = 0; i < 60; i++) {
                    const key = "g" + group + "t" + i;
                    schema[key] = { type: "boolean", label: "Option " + i, group: "Group " + group };
                    settings[key] = true;
                    order.push(key);
                }
            schema.pads = { type: "list", label: "Pads", items: { command: { type: "string", label: "App", presets: [{ label: "Terminal", value: "terminal" }], allowCustom: true } }, defaults: { command: "terminal" } };
            settings.pads = [{ name: "1", command: "fixture-command-never-run" }];
            order.push("pads", "keys", "holder");
            const bind = { shortcut: "tap", key: "code:108", keys: ["code:108"], default: ["code:108"], description: "Tap" };
            const opening = Object.assign({}, root.row(true), { schema: schema, settings: settings, fieldRows: PluginLogic.fieldRows(schema, {}), binds: [bind], paneHolder: "acme.holder" });
            manager.plugins = [{ id: "acme.one", name: "One", icon: "package" }, { id: "acme.holder", name: "Holder", icon: "package" }];
            if (data.from === "another") {
                // One group of forty rows, a window and more, with Keys and
                // the panes holder's button, which stay shown at the switch.
                const before = {};
                for (let i = 0; i < 40; i++) before["b" + i] = { type: "boolean", label: "Before " + i, group: "Before" };
                manager.current = Object.assign({}, root.row(true), { id: "acme.before", schema: before, settings: {}, fieldRows: PluginLogic.fieldRows(before, {}), binds: [bind], paneHolder: "acme.holder" });
            } else {
                manager.current = opening;
            }
            const opened = createTemporaryObject(pageComponent, root, { visible: data.from !== "hidden" });
            verify(opened !== null);
            const view = descendants(opened).find(item => item.firstViewRoot === true);
            verify(view !== undefined, "the page builds through a FirstView");
            if (data.from === "hidden") {
                opened.visible = true;
            } else {
                if (data.from === "shown") verify(!view.settled, "the later rows stand past the first view");
                verify(renderedFrame(opened));
            }
            if (data.from === "another") {
                tryVerify(() => view.settled, 5000, "the other plugin's page is built");
                manager.current = opening;
            }
            opened.open(Qt.OtherFocusReason, data.tab);
            // Read in the open's turn, before any further frame.
            const shown = descendants(opened);
            const built = shown.filter(item => item instanceof SettingField && /^g[0-3]t[0-9]+$/.test(item.key)).map(item => item.key);
            if (shown.some(item => item instanceof Section && item.title === "Pads")) built.push("pads");
            if (shown.some(item => item instanceof Section && item.title === "Keys")) built.push("keys");
            if (shown.some(item => item instanceof Button && item.text === "More settings in Holder")) built.push("holder");
            const prefix = order.slice(0, built.length);
            compare(built.slice().sort(), prefix.slice().sort(), "the rows built are every row down to the last one built");
            verify(built.length < order.length, "the rows past the first view wait for the steps");
            const area = opened.scrollArea;
            if (data.from !== "shown") verify(view.mapToItem(area, 0, view.height).y >= area.height, "the first view fills the viewport");
            if (data.target !== null) {
                verify(built.indexOf(data.target) !== -1, "the target row is built in the open's turn");
                const row = shown.find(item => item instanceof SettingField && item.key === data.target);
                const top = row.mapToItem(area, 0, 0).y;
                verify(top >= 0 && top + row.height <= area.height, "the target row is revealed in the open's turn");
                if (data.from !== "shown") {
                    const last = data.target.replace(/t[0-9]+$/, "t59");
                    verify(built.indexOf(last) === -1, "the rows past one window below the target row wait for the steps");
                }
            }
            const picker = view.parts.find(part => part.values !== undefined && part.values.some(value => value !== null && value.id === "acme.one"));
            verify(picker !== undefined, "the picker's entries belong to the page's view");
            if (data.from === "another") compare(picker.count, manager.plugins.length, "the picker's entries stay built through the switch");
            else compare(picker.count, 0, "the picker's entries wait for its menu or the steps");
        }

        function test_choosing_custom_still_reveals_the_editor() {
            const home = descendants(page).find(item => item instanceof SettingField && item.key === "home");
            const select = descendants(home).find(item => item instanceof Select);
            select.choose(home.choices.length);
            tryVerify(() => home.customVisible && page.scrollArea.contentY > 0);
            const input = descendants(home).find(item => item instanceof TextInput && item.visible);
            verify(input !== undefined);
            verify(input.mapToItem(page.scrollArea, 0, input.height).y <= page.scrollArea.height);
        }

        function test_keyboard_focus_still_reveals_the_control() {
            const home = descendants(page).find(item => item instanceof SettingField && item.key === "home");
            const select = descendants(home).find(item => item instanceof Select);
            select.forceActiveFocus(Qt.TabFocusReason);
            tryVerify(() => select.activeFocus && page.scrollArea.contentY > 0);
            verify(select.mapToItem(page.scrollArea, 0, select.height).y <= page.scrollArea.height);
        }
    }
}
