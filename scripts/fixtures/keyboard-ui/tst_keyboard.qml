import QtQuick
import QtTest
import Quickshell.Hyprland

// Test the shipped Keyboard components through the normal QML test
// stand-ins. The provider counts snapshot reads, without timing them.
Item {
    id: root
    property url pluginRoot: Qt.resolvedUrl("../../../shell/plugins/vgs.keyboard/")
    property var records: ({})
    property var meter: ({ reads: 0 })
    property var writes: []
    property var changes: []
    property var fixtureShell: null
    property var catalog: [
        { code: "us", name: "English", variants: [{ code: "intl", name: "International" }] },
        { code: "de", name: "German", variants: [{ code: "nodeadkeys", name: "No dead keys" }] },
        { code: "it", name: "Italian", variants: [] }
    ]
    property var devices: ({ keyboards: [{ name: "main", main: true, layout: "us", variant: "", activeLayoutIndex: 0, activeKeymap: "English" }] })
    property string serviceCatalogXml: '<layoutList><layout><configItem><name>us</name><description>English</description></configItem><variantList><variant><configItem><name>intl</name><description>International</description></configItem></variant></variantList></layout><layout><configItem><name>de</name><description>German</description></configItem></layout></layoutList>'

    function makeShell() {
        return {
            status: {
                get revision() { return root.records.keyboard === undefined ? 0 : root.records.keyboard.serial; },
                get values() {
                    root.meter.reads++;
                    return root.records.keyboard === undefined ? {} : JSON.parse(JSON.stringify(root.records.keyboard.values));
                },
                set: (key, value) => {
                    root.writes.push(key);
                    const record = root.records.keyboard || { serial: 0, values: {} };
                    const values = Object.assign({}, record.values);
                    values[key] = value;
                    root.records = { keyboard: { serial: record.serial + 1, values: values } };
                    return "ok";
                }
            },
            settings: { layouts: "us", variants: "", options: "", repeatRate: 25, repeatDelay: 600, numlockByDefault: false },
            manifest: { schema: { options: { presets: [{ label: "Default", value: "" }, { label: "Caps to Escape", value: "caps:escape" }] } }, hyprland: { options: {} } },
            hyprland: { devices: root.devices, overridden: [] },
            configure: {
                set: (key, value) => root.configure("set", key, value),
                unset: key => root.configure("unset", key, "")
            }
        };
    }
    function configure(verb, key, value) {
        changes.push([verb, key, value]);
        const settings = Object.assign({}, fixtureShell.settings);
        settings[key] = value;
        fixtureShell = Object.assign({}, fixtureShell, { settings: settings });
        return "ok";
    }
    function component(name) {
        const source = Qt.createComponent(pluginRoot + name + ".qml");
        if (source.status !== Component.Ready) throw new Error(source.errorString());
        return source;
    }
    function descendant(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) {
            const found = descendant(child, name);
            if (found !== null) return found;
        }
        return null;
    }
    TestCase {
        name: "keyboard-ui"
        property var widget: null
        property var editor: null
        property var service: null

        function init() {
            root.records = { keyboard: { serial: 1, values: { catalog: { state: "ready", layouts: root.catalog }, active: { code: "US", name: "English", count: 2 } } } };
            root.fixtureShell = root.makeShell();
            root.writes = [];
            root.changes = [];
            root.meter = { reads: 0 };
        }
        function cleanup() {
            for (const item of [widget, editor, service]) if (item !== null) item.destroy();
            widget = null; editor = null; service = null;
            wait(0);
        }
        function buildEditor() {
            editor = root.component("KeyboardControls").createObject(root, { shell: Qt.binding(() => root.fixtureShell), width: 900 });
            verify(editor !== null);
            compare(editor.catalog.length, root.catalog.length);
        }
        function setSources(layouts, variants) {
            root.fixtureShell = Object.assign({}, root.fixtureShell, { settings: Object.assign({}, root.fixtureShell.settings, { layouts, variants }) });
        }
        function test_source_menu_offers_only_possible_actions() {
            buildEditor();
            const list = root.descendant(editor, "inputSources");
            const cases = [
                ["us", [[]]],
                ["us,de", [["down", "remove"], ["up", "remove"]]],
                ["us,de,it", [["down", "remove"], ["up", "down", "remove"], ["up", "remove"]]],
                ["us,de,it,fr", [["down", "remove"], ["up", "down", "remove"], ["up", "down", "remove"], ["up", "remove"]]]
            ];
            for (const [layouts, offered] of cases) {
                setSources(layouts, "");
                compare(list.rows.length, offered.length);
                compare(list.menuOf(list.rows[0]).map(entry => entry.key), offered[0]);
                for (let index = 1; index < list.rows.length; index++)
                    compare(list.menuOf(list.rows[index]).map(entry => entry.key), offered[index]);
                compare(list.removable, list.rows.length > 1);
            }
        }
        function test_add_keeps_selected_variant() {
            buildEditor();
            root.descendant(editor, "layoutPicker").activated(1);
            root.descendant(editor, "variantPicker").activated(1);
            root.descendant(editor, "addSource").clicked();
            compare(root.changes, [["set", "variants", ",nodeadkeys"], ["set", "layouts", "us,de"]]);
        }
        function test_fifth_source_keeps_saved_sources() {
            setSources("us,de,fr,es", ",nodeadkeys,,");
            buildEditor();
            root.descendant(editor, "layoutPicker").activated(2);
            root.descendant(editor, "addSource").clicked();
            compare(root.changes, []);
            compare(root.fixtureShell.settings.layouts, "us,de,fr,es");
            compare(editor.sources.length, 4);
            verify(editor.problem !== "");
        }
        function test_system_layout_unsets_both_values() {
            setSources("us,de", ",nodeadkeys");
            buildEditor();
            root.descendant(editor, "systemLayout").clicked();
            compare(root.changes, [["unset", "variants", ""], ["unset", "layouts", ""]]);
            compare(editor.sources, [{ code: "us", variant: "" }]);
        }
        function test_modifier_preset_and_custom_commit() {
            buildEditor();
            const picker = root.descendant(editor, "modifierPicker");
            picker.activated(1);
            compare(root.fixtureShell.settings.options, "caps:escape");
            picker.activated(2);
            const field = root.descendant(editor, "customOptions");
            verify(field.parent.visible);
            field.text = "ctrl:swapcaps,compose:ralt";
            field.editingFinished();
            compare(root.changes, [["set", "options", "caps:escape"], ["set", "options", "ctrl:swapcaps,compose:ralt"]]);
        }
        function test_status_ignores_other_plugins_and_keeps_models() {
            widget = root.component("Widget").createObject(root, { shell: Qt.binding(() => root.fixtureShell) });
            buildEditor();
            const catalog = editor.catalogStatus;
            const rows = root.descendant(editor, "inputSources").rows;
            const variants = editor.variants;
            root.meter.reads = 0;
            for (let i = 0; i < 30; i++) {
                root.records = { keyboard: root.records.keyboard, jarvis: { serial: i + 2, values: { level: i / 30 } } };
                wait(0);
            }
            compare(root.meter.reads, 0);
            compare(widget.active.code, "US");
            root.records = { keyboard: { serial: 32, values: { catalog: { state: "ready", layouts: root.catalog }, active: { code: "DE", name: "German", count: 2 } } } };
            wait(0);
            compare(root.meter.reads, 2);
            compare(widget.active.code, "DE");
            verify(editor.catalogStatus === catalog);
            verify(root.descendant(editor, "inputSources").rows === rows);
            verify(editor.variants === variants);
            root.records = {};
            wait(0);
            compare(widget.active.count, 0);
            compare(editor.catalogStatus.state, "pending");
            root.records = { keyboard: { serial: 33, values: { catalog: { state: "ready", layouts: root.catalog }, active: { code: "FR", name: "French", count: 2 } } } };
            wait(0);
            compare(widget.active.code, "FR");
            compare(editor.catalogStatus.state, "ready");
            root.records = { keyboard: { serial: 33, values: { catalog: { state: "failed", layouts: [] }, active: { code: "IT", name: "Italian", count: 2 } } } };
            root.fixtureShell = root.makeShell();
            wait(0);
            compare(widget.active.code, "IT");
            compare(editor.catalogStatus.state, "failed");
        }
        function reader() { return Array.from(service.data).find(item => typeof item.finishRead === "function"); }
        function test_catalog_publishes_only_from_its_state() {
            root.fixtureShell.hyprland.devices = { keyboards: [{ name: "main", main: true, layout: "us,us", variant: ",intl", activeLayoutIndex: 0, activeKeymap: "English" }] };
            service = root.component("Service").createObject(root, { shell: Qt.binding(() => root.fixtureShell) });
            verify(service !== null);
            const view = reader();
            compare(view.reads, 1);
            compare(view.watchers, 0);
            root.writes = [];
            view.finishRead(root.serviceCatalogXml);
            compare(root.writes, ["catalog"]);
            compare(root.records.keyboard.values.catalog.state, "ready");
            const catalog = service.catalog;
            root.writes = [];
            Hyprland.rawEvent({ name: "activelayout", parse: count => ["main", "International"] });
            compare(root.writes, ["active"]);
            compare(root.records.keyboard.values.active.code, "US");
            compare(root.records.keyboard.values.active.name, "International");
            compare(root.records.keyboard.values.active.count, 2);
            verify(service.catalog === catalog);
        }
        function test_reload_retires_a_pending_layout_event() {
            const keyboard = { name: "main", main: true, layout: "us,de", variant: ",", activeLayoutIndex: 0, activeKeymap: "English" };
            root.fixtureShell.hyprland.devices = { keyboards: [keyboard] };
            service = root.component("Service").createObject(root, { shell: Qt.binding(() => root.fixtureShell) });
            reader().finishRead(root.serviceCatalogXml);
            Hyprland.rawEvent({ name: "activelayout", parse: count => ["main", "German"] });
            compare(root.records.keyboard.values.active.code, "DE");
            compare(root.records.keyboard.values.active.name, "German");
            verify(service.layoutEvent !== null);
            Hyprland.rawEvent({ name: "configreloaded" });
            root.fixtureShell = Object.assign({}, root.fixtureShell, { hyprland: { devices: { keyboards: [Object.assign({}, keyboard)] }, overridden: [] } });
            wait(0);
            compare(service.devices.keyboards[0].layout, "us,de");
            compare(service.devices.keyboards[0].variant, ",");
            compare(root.records.keyboard.values.active.code, "US");
            compare(root.records.keyboard.values.active.name, "English");
            compare(root.records.keyboard.values.active.count, 2);
            compare(service.layoutEvent, null);
        }
        // expected-log: keyboard: catalog-read=2 -- the catalog read this case refuses
        function test_failed_catalog_is_published() {
            service = root.component("Service").createObject(root, { shell: Qt.binding(() => root.fixtureShell) });
            root.writes = [];
            reader().failRead(2);
            compare(root.writes, ["catalog"]);
            compare(root.records.keyboard.values.catalog.state, "failed");
        }
    }
}
