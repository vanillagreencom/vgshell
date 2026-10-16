import QtQuick
import QtTest
import qs.Commons
import qs.Core
import qs.Ui
import "../../shell/plugins/vgs.settings"
import "../../shell/plugins/vgs.settings/Steps.js" as Steps

// PluginLogic produces the manager rows. The actual page and list consume
// them. Required steps, including an actionless Home failure, keep Setup
// and its warning. Optional actions stay beside their Settings choice;
// facts stay in Details. Setup has only Done/To do chips and RowAction
// links, including its one Tools step; while the plugin is off each To do
// step offers Turn on and Tools still installs. A field's screen draws in
// its own row, never in a row labelled Actions. The unit model rebuilds delegates;
// keyed movement and editor retention run in the actual settings smoke.
// A page link in a status entry's info, or in one key's, opens that page.
// Production-source controls live in
// test-qml-unit.sh. The window's capabilities record each requested action.
Item {
    id: root
    width: 1200
    height: 1200
    readonly property var screen: ({ name: "DP-1", x: 0, y: 0, width: 1920, height: 1080 })
    readonly property var stepped: ({
        requirements: [], tui: { connect: { requires: [] } },
        status: {
            model: { type: "state", label: "Model", setup: true, action: { label: "Sign in", tui: "connect" } },
            home: { type: "state", label: "Home", setup: true },
            health: { type: "state", label: "Health" }
        }
    })
    readonly property var ready: ({ tone: "ok", text: "Ready" })
    readonly property var todo: ({ model: { tone: "warning", text: "Account missing", action: true }, home: ready, health: ready })
    readonly property var done: ({ model: ready, home: ready, health: ready })
    readonly property var homeOnly: ({ model: ready, home: { tone: "danger", text: "Choose an allowed Home" }, health: ready })
    readonly property var optional: ({
        requirements: PluginLogic.normalRequirements([{ command: "optional-tool", optional: true, setting: "feature", purpose: "Optional work" }]),
        tui: { configure: { requires: [] } },
        status: {
            featureState: { type: "state", label: "Feature state", setting: "feature", action: { label: "Configure feature", tui: "configure" } },
            health: { type: "state", label: "Health" }
        }
    })
    readonly property var requiredTools: ({
        requirements: PluginLogic.normalRequirements([{ command: "required-a", purpose: "Basic work" }, { command: "required-b", purpose: "Basic work" }]),
        tui: {}, status: {}
    })
    // What one key of acme.explained explains in its own info and hint;
    // the other key carries neither.
    readonly property string idInfo: "Make a Desktop app client in your Google Cloud project to get it."
    readonly property string idHint: "Ends in .apps.googleusercontent.com"
    readonly property var keyed: ({ requirements: [], tui: {}, secrets: { service: "acme-unit", label: "Key" },
        status: { connection: { type: "state", label: "Connection", setup: true }, credentials: { type: "presenceList", label: "Credentials", step: "connection" } } })
    // keyed, its Credentials entry's info and its Client ID's each linking
    // another plugin's page.
    readonly property var pagedKeys: ({ requirements: [], tui: {}, secrets: { service: "acme-unit", label: "Key" },
        status: { connection: { type: "state", label: "Connection", setup: true },
            credentials: { type: "presenceList", label: "Credentials", step: "connection", info: "Keys are listed on the [Done page](page:acme.done/Details)." } } })
    // A choice whose own screen is listed beside it.
    readonly property var screened: ({ requirements: [], status: {},
        tui: { open: { requires: [], entry: { label: "Open feature", icon: "wrench", group: "Acme", setting: "feature" } } } })
    // The manager row of plugin ID, its MANIFEST's rows for its published
    // VALUES and MISSING commands, with FIELDS over them; its field rows
    // are the core's (PluginLogic.fieldRows) over the schema FIELDS holds.
    function pluginRow(id, manifest, values, missing, fields) {
        const row = Object.assign({ id: id, name: id, version: "1", description: "", author: "VGS", license: "", icon: "package", source: "bundled",
            enabled: true, alwaysOn: false, placed: false, kinds: ["service"], capabilities: [], schema: {}, settings: {}, settingChoices: {},
            status: PluginLogic.statusRows(manifest, values), secretLabel: "", readme: "", tuis: [], builtins: [], opens: "", paneHolder: "", binds: [],
            requirements: PluginLogic.requirementRows(manifest, missing, {}), errors: [] }, fields);
        const tui = {};
        for (const name of Object.keys(manifest.tui)) tui[name] = { entry: manifest.tui[name].entry === undefined ? null : manifest.tui[name].entry, requires: manifest.tui[name].requires };
        row.fieldRows = PluginLogic.fieldRows(row.schema, manifest.status, manifest.requirements, tui);
        return row;
    }
    function listed(settings) { return { tuis: [{ name: "task", label: "Run task", icon: "wrench", settings: settings, setting: "" }] }; }
    // Forty switches, the last far below the window's first screen.
    function longFields() {
        const schema = {}, settings = {};
        for (let i = 0; i < 40; i++) { schema["f" + i] = { type: "boolean", label: "Field " + i }; settings["f" + i] = false; }
        return { schema: schema, settings: settings };
    }
    function rows() {
        return [
            pluginRow("acme.todo", stepped, todo, [], {}),
            pluginRow("acme.done", stepped, done, [], {}),
            pluginRow("acme.home", stepped, homeOnly, [], {}),
            pluginRow("acme.unknown", stepped, {}, [], {}),
            pluginRow("acme.off", stepped, todo, [], { enabled: false }),
            pluginRow("acme.optional", optional, { featureState: { tone: "warning", text: "Not configured", action: true }, health: ready }, ["optional-tool"],
                { schema: { feature: { type: "boolean", label: "Feature" } }, settings: { feature: false } }),
            pluginRow("acme.required", requiredTools, {}, ["required-a", "required-b"], {}),
            pluginRow("acme.present", requiredTools, {}, [], {}),
            pluginRow("acme.keys", keyed, { connection: ready, credentials: [{ label: "Client ID", value: "present", secret: "acme:id" }, { label: "Client secret", value: "absent", secret: "acme:secret" }] }, [], {}),
            pluginRow("acme.explained", keyed, { connection: ready, credentials: [{ label: "Client ID", value: "present", hint: root.idHint, info: root.idInfo, secret: "acme:id" }, { label: "Client secret", value: "absent", secret: "acme:secret" }] }, [], {}),
            pluginRow("acme.paged", pagedKeys, { connection: ready, credentials: [{ label: "Client ID", value: "present", info: "Make one on the [Plain page](page:acme.plain).", secret: "acme:id" }] }, [], {}),
            pluginRow("acme.plain", { requirements: [], status: {}, tui: {} }, {}, [], {}),
            pluginRow("acme.tasks", { requirements: [], status: {}, tui: {} }, {}, [], listed(false)),
            pluginRow("acme.held", { requirements: [], status: {}, tui: {} }, {}, [], Object.assign(listed(false), { enabled: false })),
            pluginRow("acme.settings", { requirements: [], status: {}, tui: {} }, {}, [], listed(true)),
            pluginRow("acme.offtools", requiredTools, {}, ["required-a"], { enabled: false }),
            pluginRow("acme.screen", screened, {}, [], { schema: { feature: { type: "boolean", label: "Feature" } }, settings: { feature: false },
                tuis: [{ name: "open", label: "Open feature", icon: "wrench", settings: false, setting: "feature" }] }),
            pluginRow("acme.long", { requirements: [], status: {}, tui: {} }, {}, [], longFields()),
            pluginRow("acme.installed", stepped, done, [], { source: "installed" }),
            pluginRow("acme.loose", { requirements: [], status: {}, tui: {} }, {}, [], { source: "installed" })
        ];
    }
    QtObject {
        id: fakeManager
        property var plugins: root.rows()
        property var installs: []
        property var updates: []
        property var opens: []
        property var enables: []
        property var acts: []
        property string actionReply: "ok"
        function rescan() { return "ok"; }
        function setEnabled(id, enabled) { enables = enables.concat([[id, enabled]]); return "ok"; }
        function viewPage(id) {}
        function installRequirements(id) { installs = installs.concat([id]); return "ok"; }
        function update(id) { updates = updates.concat([id]); return "ok"; }
        function openTui(id, name) { opens = opens.concat([[id, name]]); return "ok"; }
        function act(id, key) { acts = acts.concat([[id, key]]); return actionReply; }
    }
    QtObject { id: fakeCompositor; function readWindows(done) {} }
    QtObject {
        id: fakeShell
        readonly property var manager: fakeManager
        readonly property var compositor: fakeCompositor
        readonly property var manifest: ({ id: "vgs.settings", name: "Plugins" })
        readonly property var screens: ({ current: root.screen, all: [root.screen] })
        readonly property var shortcut: ({ capture: null })
    }
    Component { id: windowComponent; Window { shell: fakeShell } }
    TestCase {
        name: "settingsSetup"
        when: windowShown
        function descendants(item) {
            const found = [item];
            for (let i = 0; i < found.length; i++) for (const child of found[i].children || []) found.push(child);
            return found;
        }
        function init() { fakeManager.plugins = root.rows(); fakeManager.installs = []; fakeManager.updates = []; fakeManager.opens = []; fakeManager.enables = []; fakeManager.acts = []; fakeManager.actionReply = "ok"; }
        function opened() {
            const window = createTemporaryObject(windowComponent, root);
            verify(window !== null, "the window builds");
            window.width = window.implicitWidth; window.height = 900; window.open("{}"); waitForRendering(window);
            return window;
        }
        function pageOf(window) { return descendants(window).find(item => item.fitHeight !== undefined && item.row !== undefined); }
        function tabsOf(window) { return descendants(pageOf(window)).find(item => item instanceof TabPages); }
        function shown(window, type) { return descendants(pageOf(window)).filter(item => item instanceof type && item.visible); }
        function onTab(window, type) {
            const body = tabsOf(window).currentPage;
            verify(body !== null, "the shown tab has its body");
            return descendants(body).filter(item => item instanceof type && item.visible);
        }
        function listRow(window, id) { return descendants(window).find(item => item instanceof ListItem && item.text === id); }
        function chipShown(window, id) { return descendants(listRow(window, id)).some(item => item instanceof Badge && item.visible && item.tone === "warning"); }
        function tabWarning(window) {
            const tab = tabsOf(window).tabs.itemAt(tabsOf(window).model.indexOf("Setup"));
            return descendants(tab).find(item => item.objectName === "tabWarning");
        }
        function test_required_work_alone_creates_setup_data() {
            return [
                { tag: "required steps open", id: "acme.todo", setup: true },
                { tag: "required steps done", id: "acme.done", setup: true },
                { tag: "required tools missing", id: "acme.required", setup: true },
                { tag: "required tools present", id: "acme.present", setup: true },
                { tag: "optional only", id: "acme.optional", setup: false },
                { tag: "nothing required", id: "acme.plain", setup: false },
                { tag: "settings screen", id: "acme.settings", setup: false },
                { tag: "task screen", id: "acme.tasks", setup: false }
            ];
        }
        function test_required_work_alone_creates_setup(data) {
            const window = opened(); window.openPlugin(data.id, Qt.OtherFocusReason);
            compare(tabsOf(window).model, data.setup ? ["Settings", "Setup", "Details"] : ["Settings", "Details"]);
            compare(pageOf(window).tab, "Settings");
        }
        function test_required_warning_is_shared_by_list_and_tab_data() {
            return [
                { tag: "open", id: "acme.todo", warning: true },
                { tag: "done", id: "acme.done", warning: false },
                { tag: "Home only blocker", id: "acme.home", warning: true },
                { tag: "unreported", id: "acme.unknown", warning: true },
                { tag: "missing required tools", id: "acme.required", warning: true },
                { tag: "tools present", id: "acme.present", warning: false },
                { tag: "off", id: "acme.off", warning: false }
            ];
        }
        function test_required_warning_is_shared_by_list_and_tab(data) {
            const window = opened();
            compare(chipShown(window, data.id), data.warning, "the list uses required readiness");
            window.openPlugin(data.id, Qt.OtherFocusReason);
            compare(tabsOf(window).warningTabs, data.warning ? ["Setup"] : []);
            verify(tabWarning(window) !== undefined, "the actual Setup tab declares its warning icon");
            compare(tabWarning(window).visible, data.warning, "the drawn icon follows required readiness");
            compare(tabWarning(window).color, Qt.color(Theme.color.warning));
        }
        function test_optional_missing_has_no_list_mark() {
            const window = opened();
            compare(chipShown(window, "acme.optional"), false);
            compare(descendants(listRow(window, "acme.optional")).filter(item => item instanceof IconButton && item.visible).length, 0, "an optional tool gives the list no warning icon");
        }
        function test_details_without_required_work_has_no_setup_heading_data() {
            return [{ tag: "no steps or tools", id: "acme.plain" },
                { tag: "optional work only", id: "acme.optional" }];
        }
        function test_details_without_required_work_has_no_setup_heading(data) {
            const window = opened(); window.openPlugin(data.id, Qt.OtherFocusReason, "Details");
            compare(pageOf(window).tab, "Details");
            verify(onTab(window, Section).every(section => section.title !== "Setup"),
                "Details has no empty Setup heading when it occupies the second tab");
        }
        function test_setup_draws_required_steps_with_links_and_two_state_chips_data() {
            return [ { tag: "open", id: "acme.todo", chips: ["To do", "Done"], actions: ["Sign in"] },
                { tag: "complete", id: "acme.done", chips: ["Done", "Done"], actions: [] },
                { tag: "Home only", id: "acme.home", chips: ["To do", "Done"], actions: [] } ];
        }
        function test_setup_draws_required_steps_with_links_and_two_state_chips(data) {
            const window = opened(); window.openPlugin(data.id, Qt.OtherFocusReason, "Setup");
            compare(pageOf(window).tab, "Setup");
            compare(shown(window, Field).map(field => field.label).filter(label => ["Model", "Home", "Health"].indexOf(label) !== -1), data.id === "acme.home" ? ["Home", "Model"] : ["Model", "Home"]);
            compare(shown(window, Badge).map(chip => chip.text), data.chips);
            compare(shown(window, RowAction).map(action => action.text), data.actions);
            compare(onTab(window, Button).length, 0, "Setup draws no boxed action");
            compare(shown(window, RequirementRow).length, 0, "Setup has no separate requirement rows");
        }
        function test_optional_action_stays_beside_its_setting_and_facts_stay_in_details() {
            const window = opened(); window.openPlugin("acme.optional", Qt.OtherFocusReason);
            const field = shown(window, SettingField).find(item => item.key === "feature");
            verify(field !== undefined, "the user has the feature choice");
            const attached = descendants(pageOf(window)).find(item => item.entry !== undefined && item.entry !== null && item.entry.key === "featureState" && item.action !== undefined);
            verify(attached !== undefined);
            verify(descendants(field.parent).indexOf(attached) !== -1, "the optional action and choice share their declared Settings row group");
            compare(attached.label, "", "the field's own state draws no label of its own");
            compare(descendants(attached).filter(item => item instanceof RowAction && item.visible).map(item => item.text), ["Configure feature"]);
            const tools = descendants(field.parent).find(item => item instanceof StatusLine && item.visible && item.entry === null && item.hint.indexOf("optional-tool") !== -1);
            verify(tools !== undefined, "the feature's tools read as one line in its row");
            compare(descendants(tools).filter(item => item instanceof RowAction && item.visible).map(item => item.text), ["Review all missing or outdated tools"]);
            compare(shown(window, RequirementRow).length, 0, "Settings draws no row per tool");
            tabsOf(window).currentIndex = 1;
            compare(shown(window, StatusRow).map(row => row.entry.label), ["Health"]);
            compare(shown(window, RequirementRow).length, 0, "Details does not repeat the feature's tool");
        }
        function test_tools_are_one_persistent_step_and_the_link_requests_the_notice() {
            const window = opened(); window.openPlugin("acme.required", Qt.OtherFocusReason, "Setup");
            const tools = shown(window, Field).filter(field => field.label === "Tools");
            compare(tools.length, 1, "required tools collapse to one step");
            compare(shown(window, Badge).map(chip => chip.text), ["To do"]);
            const link = descendants(tools[0]).find(item => item instanceof RowAction && item.visible);
            verify(link !== undefined);
            tryVerify(() => link.height > 0 && pageOf(window).parent.x === -window.width, 2000, "the page has slid in");
            mouseClick(link); compare(fakeManager.installs, ["acme.required"]);
            window.openPlugin("acme.present", Qt.OtherFocusReason, "Setup");
            compare(shown(window, Field).filter(field => field.label === "Tools").length, 1);
            compare(shown(window, Badge).map(chip => chip.text), ["Done"]);
            compare(shown(window, RowAction).length, 0);
        }
        function test_status_reply_stays_with_its_entry_data() {
            return [{ tag: "completed Setup step", id: "acme.done", key: "model", tab: "Setup" },
                { tag: "offered Setup step", id: "acme.todo", key: "model", tab: "Setup" },
                { tag: "optional Settings feature", id: "acme.optional", key: "featureState", tab: "Settings" }];
        }
        function test_status_reply_stays_with_its_entry(data) {
            const window = opened(); window.openPlugin(data.id, Qt.OtherFocusReason, data.tab);
            const line = () => descendants(pageOf(window)).find(item => item.entry !== undefined && item.entry !== null && item.entry.key === data.key && item.action !== undefined);
            verify(line() !== undefined);
            const failure = "refused: action=" + data.key + " reason=not-offered";
            ignoreWarning("settings: " + data.id + "/" + data.key + " " + failure);
            window.keep(window.stepKey(data.id, data.key), failure);
            compare(line().error, window.replyOf(data.id, data.key), "a refusal reads under its entry even without an offered link");
            if (data.id === "acme.done") {
                fakeManager.plugins = fakeManager.plugins.map(row => row.id === data.id ? Object.assign({}, row, { status: PluginLogic.statusRows(root.stepped, root.todo) }) : row);
            }
            tryVerify(() => line() !== undefined && line().action !== null);
            const action = descendants(line()).find(item => item instanceof RowAction && item.visible);
            verify(action !== undefined);
            action.clicked();
            compare(fakeManager.acts, [[data.id, data.key]], "the primary action uses its status entry's manager route");
            compare(fakeManager.opens, [], "the primary status action keeps its own reply owner");
            compare(line().error, "", "a successful retry clears the same entry's refusal");
        }
        function test_required_credential_chips_and_masked_actions_follow_setup_rules() {
            const window = opened(); window.openPlugin("acme.keys", Qt.OtherFocusReason, "Setup");
            compare(shown(window, Badge).map(chip => chip.text), ["Done", "Done", "To do"]);
            compare(onTab(window, Button).length, 0);
            const add = () => shown(window, RowAction).find(action => action.text === "Add key");
            verify(add() !== undefined, "a missing required credential has its masked-field path");
            add().clicked();
            tryVerify(() => onTab(window, TextField).length > 0);
            compare(onTab(window, Button).length, 0, "the masked editor keeps Setup actions as links");
            compare(descendants(onTab(window, TextField)[0].parent).filter(item => item instanceof RowAction && item.visible).length, 2, "the masked editor draws its two action links");
        }
        // A key's info draws its own icon beside the key's label, which opens
        // the explanation in a dialog; a key without info draws none. The
        // key's hint stays under its value.
        function test_a_key_with_info_draws_its_own_icon_and_dialog() {
            const window = opened(); window.openPlugin("acme.explained", Qt.OtherFocusReason, "Setup");
            const line = label => onTab(window, StatusLine).find(item => item.label === label);
            const marks = item => descendants(item).filter(child => child instanceof InfoButton && child.visible);
            compare(marks(line("Client secret")).length, 0, "a key without info draws no info icon");
            const mark = marks(line("Client ID"));
            compare(mark.length, 1, "a key with info draws its own info icon");
            compare(mark[0].info, root.idInfo);
            // The list page hides once the page has slid in, where the
            // pointer reaches the icon.
            tryVerify(() => !descendants(window).find(item => item instanceof ListPage).visible);
            mouseClick(mark[0]);
            tryVerify(() => mark[0].infoOpen, 1000, "the key's info icon opens its dialog");
            mark[0].closeInfo();
            tryVerify(() => !mark[0].infoOpen);
            const chip = descendants(line("Client ID")).find(item => item instanceof Badge && item.visible);
            const hint = descendants(line("Client ID")).find(item => item instanceof LinkText && item.visible && item.text === root.idHint);
            verify(hint !== undefined, "the key's hint draws");
            verify(hint.mapToItem(null, 0, 0).y >= chip.mapToItem(null, 0, chip.height).y, "the key's hint sits under its value");
        }
        // A page link in the info of a status entry, or of one of its keys,
        // closes the dialog and opens the page it names, on its tab.
        function test_an_info_page_link_opens_its_page_data() {
            return [{ tag: "entry info", label: "Credentials", page: "acme.done", tab: "Details" },
                { tag: "key info", label: "Client ID", page: "acme.plain", tab: "Settings" }];
        }
        function test_an_info_page_link_opens_its_page(data) {
            const window = opened(); window.openPlugin("acme.paged", Qt.OtherFocusReason, "Setup");
            const line = onTab(window, StatusLine).find(item => item.label === data.label);
            verify(line !== undefined, "the line draws");
            const mark = descendants(line).filter(child => child instanceof InfoButton && child.visible);
            compare(mark.length, 1, "the line draws its info icon");
            tryVerify(() => !descendants(window).find(item => item instanceof ListPage).visible);
            mouseClick(mark[0]);
            tryVerify(() => mark[0].infoOpen, 1000, "the icon opens its dialog");
            const link = descendants(mark[0].popup.tracker.popup.contentItem).find(item => item instanceof LinkText && item.visible && item.linked);
            verify(link !== undefined, "the dialog draws the page reference as a link");
            link.clicked();
            tryVerify(() => pageOf(window).row !== null && pageOf(window).row.id === data.page, 2000, "the link opens the page it names");
            compare(pageOf(window).tab, data.tab);
        }
        function test_list_click_and_keyboard_open_required_setup() {
            const window = opened(); mouseClick(listRow(window, "acme.todo"));
            compare(pageOf(window).tab, "Setup"); window.back();
            mouseClick(listRow(window, "acme.optional")); compare(pageOf(window).tab, "Settings"); window.back();
            const list = descendants(window).find(item => item.openCurrent !== undefined);
            list.current = list.shown.findIndex(plugin => plugin.id === "acme.home"); list.openCurrent(Qt.TabFocusReason);
            compare(pageOf(window).tab, "Setup");
        }
        function test_requested_tab_and_row_readiness_data() {
            return [
                { tag: "required row", id: "acme.todo", row: true, asked: "", tab: "Setup" },
                { tag: "done row", id: "acme.done", row: true, asked: "", tab: "Settings" },
                { tag: "optional row", id: "acme.optional", row: true, asked: "", tab: "Settings" },
                { tag: "requested Setup", id: "acme.done", row: false, asked: "Setup", tab: "Setup" },
                { tag: "missing Setup", id: "acme.plain", row: false, asked: "Setup", tab: "Settings" }
            ];
        }
        function test_requested_tab_and_row_readiness(data) {
            const window = opened();
            if (data.row) window.openRow(data.id, Qt.OtherFocusReason); else window.openPlugin(data.id, Qt.OtherFocusReason, data.asked);
            compare(pageOf(window).tab, data.tab);
        }
        function test_manager_changes_keep_shown_tab_and_remove_missing_tab_to_details() {
            const window = opened(); window.openPlugin("acme.todo", Qt.OtherFocusReason, "Setup");
            fakeManager.plugins = root.rows().map(row => row.id === "acme.todo" ? Object.assign({}, row, { status: PluginLogic.statusRows(root.stepped, root.done) }) : row);
            compare(pageOf(window).tab, "Setup"); compare(tabWarning(window).visible, false);
            fakeManager.plugins = fakeManager.plugins.map(row => row.id === "acme.todo" ? Object.assign({}, row, { status: [] }) : row);
            compare(tabsOf(window).model, ["Settings", "Details"]); compare(pageOf(window).tab, "Details");
            fakeManager.plugins = root.rows(); compare(pageOf(window).tab, "Details"); compare(tabsOf(window).currentIndex, 2);
        }
        // While the plugin is off, every To do step offers Turn on, whose
        // press asks the manager to turn the plugin on, and the Tools step
        // still installs.
        function test_off_plugin_steps_offer_turn_on() {
            const window = opened(); window.openPlugin("acme.off", Qt.OtherFocusReason, "Setup");
            compare(pageOf(window).tab, "Setup");
            const links = () => shown(window, RowAction);
            // Model reads To do; Home, published as done, reads Done and offers nothing.
            compare(links().map(action => [action.text, action.enabled]), [["Turn on acme.off", true]], "each To do step offers Turn on");
            tryVerify(() => links()[0].height > 0 && pageOf(window).parent.x === -window.width, 2000, "the page has slid in");
            mouseClick(links()[0]);
            compare(fakeManager.enables, [["acme.off", true]], "Turn on asks to turn the plugin on");
            window.openPlugin("acme.offtools", Qt.OtherFocusReason, "Setup");
            compare(links().map(action => [action.text, action.enabled]), [["Review all missing or outdated tools", true]], "the Tools step installs while the plugin is off");
            mouseClick(links()[0]);
            compare(fakeManager.installs, ["acme.offtools"]);
        }
        // A field's screen draws in that field's own row: no Settings page
        // draws a row labelled Actions.
        function test_a_screen_draws_in_its_field_row() {
            const window = opened(); window.openPlugin("acme.screen", Qt.OtherFocusReason);
            const action = shown(window, RowAction).find(item => item.text === "Open feature");
            verify(action !== undefined, "the field's screen draws");
            let owner = action.parent;
            while (owner !== null && owner.fieldKey === undefined) owner = owner.parent;
            verify(owner !== null && owner.fieldKey === "feature", "the screen draws in its field's row");
            compare(shown(window, Field).filter(field => field.label === "Actions").length, 0, "Settings draws no Actions row");
        }
        // A reference to a field brings it into view on Settings.
        function test_a_field_reference_scrolls_to_it() {
            const window = opened(); window.openPlugin("acme.long", Qt.OtherFocusReason, "Settings/f39");
            compare(pageOf(window).tab, "Settings");
            tryVerify(() => pageOf(window).scrollArea.contentY > 0, 2000, "the page scrolls to the far field");
            const far = shown(window, SettingField).find(item => item.key === "f39");
            verify(far !== undefined);
            const top = far.mapToItem(pageOf(window).scrollArea, 0, 0).y;
            verify(top >= 0 && top + far.height <= pageOf(window).scrollArea.height, "the far field is in view: " + top);
        }
        function test_more_settings_and_task_screens_have_one_home() {
            const window = opened(); window.openPlugin("acme.settings", Qt.OtherFocusReason);
            const action = () => shown(window, RowAction).find(item => item.text === "Run task");
            const fieldOf = link => shown(window, Field).find(field => descendants(field).indexOf(link) !== -1);
            verify(action() !== undefined); compare(fieldOf(action()).label, "More settings");
            tabsOf(window).currentIndex = 1; compare(action(), undefined, "Details does not repeat More settings");
            window.openPlugin("acme.tasks", Qt.OtherFocusReason, "Details");
            verify(action() !== undefined); compare(fieldOf(action()).label, "Actions");
            tryVerify(() => action().height > 0 && pageOf(window).parent.x === -window.width, 2000);
            mouseClick(action()); compare(fakeManager.opens, [["acme.tasks", "task"]]);
            window.openPlugin("acme.held", Qt.OtherFocusReason, "Details");
            verify(action() !== undefined); compare(action().enabled, false, "a task screen takes no press while its plugin is off");
            const reason = descendants(action()).find(item => item instanceof Tooltip).text;
            compare(reason, Steps.offReason("acme.held"), "the screen names why");
            compare(fieldOf(action()).hint, reason, "the row reads the reason too");
        }
        function test_detached_rows_keep_their_layout_owner_width_data() {
            return [{ tag: "More settings field", kind: "more", id: "acme.settings", tab: "Settings" },
                { tag: "required group", kind: "group", id: "acme.todo", tab: "Setup" },
                { tag: "required delegate", kind: "delegate", id: "acme.todo", tab: "Setup" }];
        }
        function test_detached_rows_keep_their_layout_owner_width(data) {
            const window = opened(); window.openPlugin(data.id, Qt.OtherFocusReason, data.tab);
            const body = tabsOf(window).currentPage;
            let loader, group, row, owner;
            if (data.kind === "more") {
                row = onTab(window, Field).find(field => field.label === "More settings");
                owner = body;
            } else {
                loader = descendants(body).find(item => item instanceof Loader && item.modelData !== undefined
                    && item.modelData !== null && item.modelData.key === "model");
                verify(loader !== undefined, "the required step uses the production delegate");
                group = descendants(body).find(item => item instanceof GroupList && descendants(item).indexOf(loader) !== -1);
                verify(group !== undefined, "the required delegate has its layout group");
                row = data.kind === "group" ? group : loader;
                owner = data.kind === "group" ? body : group;
            }
            verify(row !== undefined, "the actual row exists");
            tryVerify(() => owner.width > 0 && row.width === owner.width);
            const originalParent = row.parent, originalWidth = owner.width;
            row.parent = null;
            try {
                window.width += 96;
                tryVerify(() => owner.width !== originalWidth, 2000, "the page's layout owner resizes");
                tryCompare(row, "width", owner.width, 2000,
                    "the detached row follows its named layout owner instead of its absent parent");
            } finally {
                row.parent = originalParent;
            }
            tryCompare(row, "width", owner.width);
        }
        function test_details_action_reaches_either_tab_position_data() {
            return [{ tag: "third page", before: "acme.loose", id: "acme.installed", index: 2 }, { tag: "second page", before: "acme.installed", id: "acme.loose", index: 1 }];
        }
        function test_details_action_reaches_either_tab_position(data) {
            const window = opened(); window.openPlugin(data.before, Qt.OtherFocusReason); window.openPlugin(data.id, Qt.OtherFocusReason);
            tabsOf(window).currentIndex = data.index; compare(pageOf(window).tab, "Details");
            const update = () => shown(window, RowAction).find(item => item.text === "Update");
            tryVerify(() => update() !== undefined && update().height > 0 && pageOf(window).parent.x === -window.width, 2000);
            mouseClick(update()); compare(fakeManager.updates, [data.id]);
        }
    }
}
