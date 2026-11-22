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
        property bool listCase: false
        property var current: root.row(true)
        function setEnabled(id, enabled) { current = root.row(enabled, listCase); return "ok"; }
        function replyOf() { return ""; }
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

        // An open that carries a reveal target builds every Settings group
        // before its first frame, each laid out below the one before it in
        // the same turn; a plain open leaves the groups past its first view
        // to the steps after it. Each of the page's four groups fills the
        // window's room, so a link to the first group's field leaves the
        // last groups past the room a target builds after it. The panel
        // lists plugins, and the page's picker builds their entries only
        // when its menu opens or in the steps, never before the first frame.
        function test_a_linked_open_builds_the_whole_page_before_its_first_frame_data() {
            return [
                { tag: "plain open", tab: "Settings", whole: false },
                { tag: "linked open", tab: "Settings/g0t0", whole: true }
            ];
        }

        function test_a_linked_open_builds_the_whole_page_before_its_first_frame(data) {
            const schema = {};
            const settings = {};
            for (let group = 0; group < 4; group++)
                for (let i = 0; i < 15; i++) {
                    schema["g" + group + "t" + i] = { type: "boolean", label: "Option " + i, group: "Group " + group };
                    settings["g" + group + "t" + i] = true;
                }
            manager.current = Object.assign({}, root.row(true), { schema: schema, settings: settings, fieldRows: PluginLogic.fieldRows(schema, {}) });
            manager.plugins = [{ id: "acme.one", name: "One", icon: "package" }, { id: "acme.two", name: "Two", icon: "package" }];
            const opened = createTemporaryObject(pageComponent, root);
            verify(opened !== null);
            const view = descendants(opened).find(item => item.firstViewRoot === true);
            verify(view !== undefined, "the page builds through a FirstView");
            verify(!view.settled, "the later groups stand past the first view");
            opened.open(Qt.OtherFocusReason, data.tab);
            const groups = descendants(opened).filter(item => item instanceof Section && /^Group [0-3]$/.test(item.title));
            groups.sort((a, b) => a.title < b.title ? -1 : 1);
            if (data.whole) {
                compare(groups.map(group => group.title), ["Group 0", "Group 1", "Group 2", "Group 3"], "every group is built before any frame draws it");
                for (let i = 1; i < groups.length; i++)
                    verify(groups[i].mapToItem(view, 0, 0).y >= groups[i - 1].mapToItem(view, 0, groups[i - 1].height).y,
                           groups[i].title + " is laid out below " + groups[i - 1].title + " in the same turn");
            } else {
                verify(groups.length < 4, "a plain open leaves the later groups to the steps");
            }
            const picker = view.parts.find(part => part.values !== undefined && part.values.some(value => value !== null && value.id === "acme.one"));
            verify(picker !== undefined, "the picker's entries belong to the page's view");
            compare(picker.count, 0, "the picker's entries wait for its menu or the steps");
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
