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
    function enabledSwitch() {
        const field = descendants(page).find(item => item instanceof Field && item.label === SettingValues.PAGE_LABELS.enabled);
        return descendants(field).find(item => item instanceof Switch);
    }

    UnitCase {
        name: "SettingsScroll"
        when: windowShown

        function init() {
            manager.current = root.row(true);
            manager.listCase = false;
            root.page = createTemporaryObject(pageComponent, root);
            verify(root.page !== null);
            verify(renderedFrame(root.page));
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
