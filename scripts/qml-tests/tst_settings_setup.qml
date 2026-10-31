import QtQuick
import QtTest
import qs.Unit
import qs.Commons
import qs.Core
import qs.Ui
import "../../shell/plugins/vgs.settings"
import "../../shell/plugins/vgs.settings/Steps.js" as Steps
import "../../shell/Commons/Reply.js" as Reply

// PluginLogic produces the manager rows. The actual page and list consume
// them. Required steps, including an actionless Home failure, keep Setup
// and its warning; an optional step or an optional tool creates Setup and
// raises no warning. Settings draws only values: no chip. Setup's chips
// are Done, To do, Not available and Optional, and its actions are
// RowAction links, including the Tools and Optional tools steps' Review;
// while the plugin is off the tab opens with one Turn on notice, no step
// offers Turn on and both tools steps still install. Details lists the optional tools as readings with
// no Review, and draws a fact's declared action beside it, which
// bin/lib/check-manifests.js refuses in a bundled plugin. A step the user
// cannot act on, by its value or a failed build, reads neutral, offers
// nothing and raises no Setup needed; a step a missing required tool
// blocks offers Review on its own row. The unit model rebuilds delegates;
// keyed movement and editor retention run in the actual settings smoke.
// A page link in a status entry's info, or in one key's, opens that page.
// A stored key list beside its Settings field draws its keys alone, as
// plain text with no chip, each with its list's source action, which takes
// the manager's act for that key's account and keeps its refusal apart
// from the key's write; with no key to draw it reads one sentence under the
// field. A key the keyring cannot read links its plugin's Setup tab while
// the key tool is missing. A key list on Details keeps its head.
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
    // A required step beside an optional one (setup "optional"), a step
    // that adds a feature.
    readonly property var extended: ({
        requirements: [], tui: { connect: { requires: [] } },
        status: {
            model: { type: "state", label: "Model", setup: true },
            extra: { type: "state", label: "Extra", setup: "optional", action: { label: "Add", tui: "connect" } }
        }
    })
    readonly property var todo: ({ model: { tone: "warning", text: "Account missing", action: true }, home: ready, health: ready })
    readonly property var done: ({ model: ready, home: ready, health: ready })
    readonly property var homeOnly: ({ model: ready, home: { tone: "danger", text: "Choose an allowed Home" }, health: ready })
    readonly property var homeUnavailable: ({ model: ready, home: { tone: "warning", text: "No Home on this computer", hint: "Connect a Home to set this up", available: false }, health: ready })
    // stepped with a required tool, whose Home a missing tool blocks.
    readonly property var toolStepped: Object.assign({}, stepped, { requirements: PluginLogic.normalRequirements([{ command: "required-a", purpose: "Basic work" }]) })
    readonly property var homeBlocked: ({ model: ready, home: { tone: "warning", text: "Needs its tool", action: "tools" }, health: ready })
    // An optional step declared before a required one.
    readonly property var optionalStepped: ({
        requirements: [], tui: { connect: { requires: [] } },
        status: {
            extra: { type: "state", label: "Extra", setup: "optional", action: { label: "Connect", tui: "connect" } },
            model: { type: "state", label: "Model", setup: true, action: { label: "Sign in", tui: "connect" } }
        }
    })
    readonly property var extraOpen: ({ tone: "info", text: "Not set up", action: true })
    readonly property var optional: ({
        requirements: PluginLogic.normalRequirements([{ command: "optional-tool", optional: true, purpose: "Optional work" }]),
        tui: { configure: { requires: [] } },
        status: {
            featureState: { type: "state", label: "Feature state", action: { label: "Configure feature", tui: "configure" } },
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
    // keyed, its Connection step's info and its Client ID's each linking
    // another plugin's page.
    readonly property var pagedKeys: ({ requirements: [], tui: {}, secrets: { service: "acme-unit", label: "Key" },
        status: { connection: { type: "state", label: "Connection", setup: true, info: "Keys are listed on the [Done page](page:acme.done/Details)." },
            credentials: { type: "presenceList", label: "Credentials", step: "connection" } } })
    // A stored key list beside the Sync field whose keys offer the script
    // that makes one, and a key list read on Details.
    readonly property string sourcedHint: "No workspace is listed yet"
    readonly property var sourced: ({ requirements: [], tui: { make: { requires: [] } }, secrets: { service: "acme-unit", label: "Key" },
        status: { keys: { type: "presenceList", label: "Workspaces", hint: root.sourcedHint, setting: "sync", sourceAction: { label: "Make key", tui: "make" } },
            wiring: { type: "presenceList", label: "Wiring" } } })
    readonly property var sourcedKeys: [{ label: "Acme", value: "present", hint: "A token for photos.", secret: "acme:a" }, { label: "Globex", value: "absent", hint: "A token for photos.", secret: "acme:g" }]
    readonly property var syncField: ({ schema: { sync: { type: "boolean", label: "Sync" } }, settings: { sync: true } })
    // sourced reading its keys with the core's key tool, declared as the
    // plugin's requirement, and one key the keyring cannot read.
    readonly property var keyTooled: Object.assign({}, sourced, { requirements: PluginLogic.normalRequirements([{ command: Steps.KEY_TOOL, purpose: "Reads the keys" }]) })
    readonly property var unreadKeys: [{ label: "Acme", value: "unavailable", secret: "acme:a" }]
    // The guide a manifest's setupGuide gives its Setup tab, and the same
    // guide of a plugin with no README to open.
    readonly property var guide: ({ title: "Acme needs keys from your own account", text: "It takes about 5 minutes.", link: "Open the guide", url: "https://example.com/acme/README.md#get-your-keys" })
    // The manager row of plugin ID, its MANIFEST's rows for its published
    // VALUES and MISSING commands, with FIELDS over them; its field rows
    // are the core's (PluginLogic.fieldRows) over the schema FIELDS holds.
    function pluginRow(id, manifest, values, missing, fields) {
        const row = Object.assign({ id: id, name: id, version: "1", description: "", author: "VGS", license: "", icon: "package", source: "bundled",
            enabled: true, alwaysOn: false, placed: false, kinds: ["service"], capabilities: [], schema: {}, settings: {}, settingChoices: {},
            status: PluginLogic.statusRows(manifest, values), secretLabel: "", readme: "", guide: null, tuis: [], builtins: [], opens: "", paneHolder: "", binds: [],
            requirements: PluginLogic.requirementRows(manifest, missing, {}), errors: [] }, fields);
        row.fieldRows = PluginLogic.fieldRows(row.schema, manifest.status);
        return row;
    }
    // Thirty Setup steps and thirty Details facts, each published ready,
    // the last of each far below the window's first screen.
    function longStatus() {
        const status = {}, values = {};
        for (let i = 0; i < 30; i++) {
            status["s" + i] = { type: "state", label: "Step " + i, setup: true };
            status["f" + i] = { type: "state", label: "Fact " + i };
            values["s" + i] = root.ready;
            values["f" + i] = root.ready;
        }
        return { manifest: { requirements: [], tui: {}, status: status }, values: values };
    }
    function listed(settings) { return { tuis: [{ name: "task", label: "Run task", icon: "wrench", settings: settings }] }; }
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
            pluginRow("acme.neutral", stepped, homeUnavailable, [], {}),
            pluginRow("acme.failed", stepped, {}, [], { errors: ["build failed: service: file:///fixture/Service.qml:12: No such type"] }),
            pluginRow("acme.refused", stepped, {}, [], { errors: ["refused: capability=acme.audio held-by=acme.other"] }),
            pluginRow("acme.toolstep", toolStepped, homeBlocked, ["required-a"], {}),
            pluginRow("acme.optstep", optionalStepped, { extra: root.extraOpen, model: ready }, [], {}),
            pluginRow("acme.optreq", optionalStepped, { extra: root.extraOpen, model: { tone: "warning", text: "Account missing", action: true } }, [], {}),
            pluginRow("acme.off", stepped, todo, [], { enabled: false }),
            pluginRow("acme.optional", optional, { featureState: { tone: "warning", text: "Not configured", action: true }, health: ready }, ["optional-tool"],
                { schema: { feature: { type: "boolean", label: "Feature" } }, settings: { feature: false } }),
            pluginRow("acme.required", requiredTools, {}, ["required-a", "required-b"], {}),
            pluginRow("acme.extra", extended, { model: ready, extra: { tone: "warning", text: "Not set up", action: true } }, [], {}),
            pluginRow("acme.present", requiredTools, {}, [], {}),
            pluginRow("acme.keys", keyed, { connection: ready, credentials: [{ label: "Client ID", value: "present", secret: "acme:id" }, { label: "Client secret", value: "absent", secret: "acme:secret" }] }, [], {}),
            pluginRow("acme.explained", keyed, { connection: ready, credentials: [{ label: "Client ID", value: "present", hint: root.idHint, info: root.idInfo, secret: "acme:id" }, { label: "Client secret", value: "absent", secret: "acme:secret" }] }, [], {}),
            pluginRow("acme.guided", keyed, { connection: ready, credentials: [{ label: "Client ID", value: "absent", secret: "acme:id" }] }, [], { guide: root.guide }),
            pluginRow("acme.unlinked", keyed, { connection: ready, credentials: [{ label: "Client ID", value: "absent", secret: "acme:id" }] }, [], { guide: Object.assign({}, root.guide, { url: "" }) }),
            pluginRow("acme.paged", pagedKeys, { connection: ready, credentials: [{ label: "Client ID", value: "present", info: "Make one on the [Plain page](page:acme.plain).", secret: "acme:id" }] }, [], {}),
            pluginRow("acme.plain", { requirements: [], status: {}, tui: {} }, {}, [], {}),
            pluginRow("acme.tasks", { requirements: [], status: {}, tui: {} }, {}, [], listed(false)),
            pluginRow("acme.held", { requirements: [], status: {}, tui: {} }, {}, [], Object.assign(listed(false), { enabled: false })),
            pluginRow("acme.settings", { requirements: [], status: {}, tui: {} }, {}, [], listed(true)),
            pluginRow("acme.offtools", requiredTools, {}, ["required-a"], { enabled: false }),
            pluginRow("acme.long", { requirements: [], status: {}, tui: {} }, {}, [], longFields()),
            pluginRow("acme.longsteps", longStatus().manifest, longStatus().values, [], {}),
            pluginRow("acme.installed", stepped, done, [], { source: "installed" }),
            pluginRow("acme.loose", { requirements: [], status: {}, tui: {} }, {}, [], { source: "installed" }),
            pluginRow("acme.sourced", sourced, { keys: sourcedKeys, wiring: [{ label: "Bar", value: "present" }] }, [], syncField),
            pluginRow("acme.sourcedempty", sourced, { keys: [] }, [], syncField),
            pluginRow("acme.sourcedwait", sourced, {}, [], syncField),
            pluginRow("acme.sourcedoff", sourced, {}, [], Object.assign({ enabled: false }, syncField)),
            pluginRow("acme.keytoolmissing", keyTooled, { keys: unreadKeys }, [Steps.KEY_TOOL], syncField),
            pluginRow("acme.keytoolpresent", keyTooled, { keys: unreadKeys }, [], syncField)
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
        property var chosen: []
        property string actionReply: "ok"
        property string enableReply: "ok"
        property string installReply: "ok"
        function rescan() { return "ok"; }
        function setEnabled(id, enabled) { enables = enables.concat([[id, enabled]]); return enableReply; }
        function viewPage(id) {}
        function installRequirements(id) { installs = installs.concat([id]); return installReply; }
        function update(id) { updates = updates.concat([id]); return "ok"; }
        function openTui(id, name) { opens = opens.concat([[id, name]]); return "ok"; }
        function act(id, key, row, rowAction) { acts = acts.concat([[id, key].concat(row === undefined ? [] : [row, rowAction])]); return actionReply; }
        function setSetting(id, key, value) { chosen = chosen.concat([[id, key, value]]); return "ok"; }
    }
    QtObject { id: fakeCompositor; function readWindows(done) {} }
    QtObject {
        id: fakeShell
        readonly property var manager: fakeManager
        readonly property var compositor: fakeCompositor
        readonly property var manifest: ({ id: "vgs.settings", name: "Plugins" })
        readonly property var screens: ({ current: root.screen, all: [root.screen] })
        readonly property var shortcut: ({ capture: null })
        readonly property var run: fakeRun
    }
    QtObject {
        id: fakeRun
        property var launched: []
        function detached(argv) { launched = launched.concat([argv]); return "ok"; }
    }
    Component { id: windowComponent; Window { shell: fakeShell } }
    UnitCase {
        name: "settingsSetup"
        when: windowShown
        function descendants(item) {
            const found = [item];
            for (let i = 0; i < found.length; i++) for (const child of found[i].children || []) found.push(child);
            return found;
        }
        function init() { fakeManager.plugins = root.rows(); fakeManager.installs = []; fakeManager.updates = []; fakeManager.opens = []; fakeManager.enables = []; fakeManager.acts = []; fakeManager.chosen = []; fakeManager.actionReply = "ok"; fakeManager.enableReply = "ok"; fakeManager.installReply = "ok"; }
        function opened() {
            const window = createTemporaryObject(windowComponent, root);
            verify(window !== null, "the window builds");
            window.width = window.implicitWidth; window.height = 900; window.open("{}"); renderedFrame(window);
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
                { tag: "optional work and tools", id: "acme.optional", setup: true },
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
                { tag: "not available", id: "acme.neutral", warning: false },
                { tag: "not available after a failed build", id: "acme.failed", warning: false },
                { tag: "not available while refused", id: "acme.refused", warning: false },
                { tag: "blocked by a missing tool", id: "acme.toolstep", warning: true },
                { tag: "an optional step open", id: "acme.optstep", warning: false },
                { tag: "an optional step beside a required step To do", id: "acme.optreq", warning: true },
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
        // An optional step reads Optional in the neutral tone, after a
        // required step To do and before a Done one, with its own action.
        function test_setup_draws_an_optional_step_data() {
            return [{ tag: "beside a done required step", id: "acme.optstep", labels: ["Extra", "Model"], chips: [["Optional", "neutral"], ["Done", "success"]], actions: ["Connect"] },
                { tag: "beside a required step To do", id: "acme.optreq", labels: ["Model", "Extra"], chips: [["To do", "warning"], ["Optional", "neutral"]], actions: ["Sign in", "Connect"] }];
        }
        function test_setup_draws_an_optional_step(data) {
            const window = opened(); window.openPlugin(data.id, Qt.OtherFocusReason, "Setup");
            compare(pageOf(window).tab, "Setup");
            compare(shown(window, Field).map(field => field.label).filter(label => ["Extra", "Model"].indexOf(label) !== -1), data.labels);
            compare(shown(window, Badge).map(chip => [chip.text, chip.tone]), data.chips);
            compare(shown(window, RowAction).map(action => action.text), data.actions);
        }
        // An optional step that is not done reads Optional, in the neutral
        // tone, before the Done step, offers its action, and gives neither
        // the list row nor the Setup tab a warning.
        function test_an_optional_step_reads_optional_with_no_warning() {
            const window = opened(); window.openPlugin("acme.extra", Qt.OtherFocusReason, "Setup");
            compare(pageOf(window).tab, "Setup");
            const steps = shown(window, Field).filter(field => ["Model", "Extra"].indexOf(field.label) !== -1);
            compare(steps.map(field => field.label), ["Extra", "Model"]);
            compare(shown(window, Badge).map(chip => [chip.text, chip.tone]), [["Optional", "neutral"], ["Done", "success"]]);
            compare(descendants(steps[0]).filter(item => item instanceof RowAction && item.visible).map(action => action.text), ["Add"]);
            compare(chipShown(window, "acme.extra"), false, "the list row draws no warning");
            compare(tabsOf(window).warningTabs, []);
            compare(tabWarning(window).visible, false, "the Setup tab draws no warning icon");
        }
        // [tag, plugin, the chip tone of each step in drawn order, the step
        // labels in that order, the steps that draw an action].
        function test_setup_draws_the_neutral_reading_and_the_tools_action_data() {
            return [{ tag: "not available by its value", id: "acme.neutral", tones: ["neutral", "success"], labels: ["Home", "Model"], acting: [] },
                { tag: "not available after a failed build", id: "acme.failed", tones: ["neutral", "neutral"], labels: ["Model", "Home"], acting: [] },
                { tag: "not available while refused", id: "acme.refused", tones: ["neutral", "neutral"], labels: ["Model", "Home"], acting: [] },
                { tag: "blocked by a missing tool", id: "acme.toolstep", tones: ["warning", "warning", "success"], labels: ["Home", "Tools", "Model"], acting: ["Home", "Tools"] }];
        }
        function test_setup_draws_the_neutral_reading_and_the_tools_action(data) {
            const window = opened(); window.openPlugin(data.id, Qt.OtherFocusReason, "Setup");
            compare(pageOf(window).tab, "Setup");
            const steps = shown(window, Field).filter(field => data.labels.indexOf(field.label) !== -1);
            compare(steps.map(field => field.label), data.labels);
            compare(shown(window, Badge).map(chip => chip.tone), data.tones);
            const action = field => descendants(field).find(item => item instanceof RowAction && item.visible);
            compare(steps.filter(field => action(field) !== undefined).map(field => field.label), data.acting);
            if (data.acting.indexOf("Home") === -1) return;
            const review = action(steps[0]);
            tryVerify(() => review.height > 0 && pageOf(window).parent.x === -window.width, 2000, "the page has slid in");
            mouseClick(review);
            compare(fakeManager.installs, [data.id], "the step's Review opens the one requirement notice");
            compare(fakeManager.acts, [], "the step's Review takes no status route");
        }
        // Settings holds only values the user changes: the feature's
        // switch, with no chip, status line, tools line or action. The
        // feature's state keeps its action beside it on Details, and its
        // missing tool is listed there as a reading; Setup's Optional tools
        // step holds the action that installs it.
        function test_settings_draws_no_chip_and_the_optional_action_stays_beside_its_fact() {
            const window = opened(); window.openPlugin("acme.optional", Qt.OtherFocusReason);
            compare(pageOf(window).tab, "Settings");
            verify(onTab(window, SettingField).some(item => item.key === "feature"), "the user has the feature choice");
            compare(onTab(window, Badge).length, 0, "the Settings tab draws no chip");
            compare(onTab(window, StatusLine).length, 0, "the Settings tab draws no status line");
            compare(onTab(window, RowAction).length, 0, "the Settings tab draws no free action");
            compare(onTab(window, RequirementRow).length, 0, "the Settings tab draws no tool");
            tabsOf(window).currentIndex = 2;
            compare(pageOf(window).tab, "Details");
            compare(onTab(window, StatusRow).map(row => row.entry.label), ["Feature state", "Health"]);
            const fact = onTab(window, StatusRow).find(row => row.entry.key === "featureState");
            const action = () => descendants(fact).find(item => item instanceof RowAction && item.visible);
            verify(action() !== undefined, "the feature's state draws its action");
            compare(action().text, "Configure feature");
            tryVerify(() => action().height > 0 && pageOf(window).parent.x === -window.width, 2000, "the page has slid in");
            mouseClick(action());
            compare(fakeManager.acts, [["acme.optional", "featureState"]], "the action takes its status entry's route");
            compare(onTab(window, RequirementRow).map(row => row.requirement.name), ["optional-tool"], "Details lists the optional tool");
            compare(onTab(window, RowAction).filter(item => item.text === Steps.REVIEW_LABEL).length, 0, "Details offers no install");
            window.openPlugin("acme.optional", Qt.OtherFocusReason, "Setup");
            compare(pageOf(window).tab, "Setup");
            const step = onTab(window, Field).find(item => item.label === "Optional tools");
            verify(step !== undefined, "Setup draws the Optional tools step");
            compare(descendants(step).filter(item => item instanceof Badge && item.visible).map(chip => [chip.text, chip.tone]), [["Optional", "neutral"]]);
            const review = descendants(step).find(item => item instanceof RowAction && item.visible);
            verify(review !== undefined, "the Optional tools step offers the install of the missing optional tool");
            compare(review.text, Steps.REVIEW_LABEL);
            // The tab's pages slide: click once the link holds still.
            let last = null;
            tryVerify(() => {
                const at = review.mapToItem(null, 0, 0), still = last !== null && at.x === last.x && at.y === last.y;
                last = at;
                return review.height > 0 && still;
            }, 3000, "the Setup tab has settled");
            mouseClick(review);
            compare(fakeManager.installs, ["acme.optional"]);
            const field = onTab(window, Field).find(item => descendants(item).includes(review));
            compare(field.error, "", "an install the manager opened leaves Review clear");
            // A refusal another action keeps under the plugin, such as a
            // refused update or setting write, or a refused Turn on, never
            // reads beside Review; the page head shows each once.
            const pageFailure = "refused: update=not-installed";
            const enableFailure = "refused: enable=conflict";
            const installFailure = "refused: requirements=none-missing";
            ignoreWarning("settings: acme.optional " + pageFailure);
            window.keep("acme.optional", pageFailure);
            fakeManager.enableReply = enableFailure;
            ignoreWarning(new RegExp("^settings: acme\\.optional/\\S+ " + enableFailure + "$"));
            window.setEnabled("acme.optional", true);
            compare(field.error, "", "another action's refusal stays off Review");
            // A refused install reads beside Review, not only in the page head.
            fakeManager.installReply = installFailure;
            ignoreWarning(new RegExp("^settings: acme\\.optional/\\S+ " + installFailure + "$"));
            mouseClick(review);
            verify(field.error !== "", "the install's refusal reads under Review");
            const head = descendants(pageOf(window)).filter(item => item instanceof Label && item.visible && item.text !== "" && Qt.colorEqual(item.color, Theme.color.danger) && !descendants(tabsOf(window)).includes(item));
            compare(head.length, 1, "the page head draws one refusal line");
            compare(head[0].text.split("\n").filter(line => line !== "").length, 3, "the page head shows each of the three refusals once");
        }
        // While the plugin is off, a Details fact that declares an action
        // offers Turn on in its place.
        function test_an_off_plugin_details_fact_offers_turn_on() {
            fakeManager.plugins = root.rows().map(row => row.id === "acme.optional" ? Object.assign({}, row, { enabled: false, status: PluginLogic.statusRows(root.optional, {}) }) : row);
            const window = opened(); window.openPlugin("acme.optional", Qt.OtherFocusReason, "Details");
            const fact = onTab(window, StatusRow).find(row => row.entry.key === "featureState");
            verify(fact !== undefined);
            compare(descendants(fact).filter(item => item instanceof RowAction && item.visible).map(item => item.text), ["Turn on acme.optional"]);
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
                { tag: "optional feature on Details", id: "acme.optional", key: "featureState", tab: "Details" }];
        }
        function test_status_reply_stays_with_its_entry(data) {
            const window = opened(); window.openPlugin(data.id, Qt.OtherFocusReason, data.tab);
            const line = () => descendants(pageOf(window)).find(item => item.entry !== undefined && item.entry !== null && item.entry.key === data.key && item.action !== undefined);
            // A Details fact reads its refusal in its head line.
            const error = () => line() instanceof StatusRow ? descendants(line()).find(item => item instanceof StatusLine).error : line().error;
            verify(line() !== undefined);
            const failure = "refused: action=" + data.key + " reason=not-offered";
            ignoreWarning("settings: " + data.id + "/" + data.key + " " + failure);
            window.keep(window.stepKey(data.id, data.key), failure);
            compare(error(), window.replyOf(data.id, data.key), "a refusal reads under its entry even without an offered link");
            if (data.id === "acme.done") {
                fakeManager.plugins = fakeManager.plugins.map(row => row.id === data.id ? Object.assign({}, row, { status: PluginLogic.statusRows(root.stepped, root.todo) }) : row);
            }
            tryVerify(() => line() !== undefined && line().action !== null);
            const action = descendants(line()).find(item => item instanceof RowAction && item.visible);
            verify(action !== undefined);
            action.clicked();
            compare(fakeManager.acts, [[data.id, data.key]], "the primary action uses its status entry's manager route");
            compare(fakeManager.opens, [], "the primary status action keeps its own reply owner");
            compare(error(), "", "a successful retry clears the same entry's refusal");
        }
        // A key list under its step draws its keys alone: the step names it.
        function test_a_step_key_list_draws_its_keys_alone() {
            const window = opened(); window.openPlugin("acme.keys", Qt.OtherFocusReason, "Setup");
            compare(onTab(window, StatusLine).map(line => line.label), ["Connection", "Client ID", "Client secret"]);
        }
        // The guide heads the Setup tab, above its steps, and its link opens
        // the README section in the default browser; a plugin with no README
        // to open draws it with no link, and one with no guide draws none.
        function test_the_setup_guide_heads_the_steps_and_opens_its_readme_section_data() {
            return [{ tag: "a guide with its README section", id: "acme.guided", callout: true, link: true },
                { tag: "a guide with no README to open", id: "acme.unlinked", callout: true, link: false },
                { tag: "no guide", id: "acme.keys", callout: false, link: false }];
        }
        function test_the_setup_guide_heads_the_steps_and_opens_its_readme_section(data) {
            fakeRun.launched = [];
            const window = opened(); window.openPlugin(data.id, Qt.OtherFocusReason, "Setup");
            const callouts = onTab(window, Callout);
            compare(callouts.length, data.callout ? 1 : 0, "the tab draws the guide only for a plugin that declares one");
            if (!data.callout) return;
            compare([callouts[0].title, callouts[0].text], [root.guide.title, root.guide.text]);
            const setup = onTab(window, Section).find(section => section.title === "Setup");
            tryVerify(() => callouts[0].height > 0 && callouts[0].mapToItem(null, 0, callouts[0].height).y <= setup.mapToItem(null, 0, 0).y, 2000, "the guide stands above the steps: "
                + callouts[0].mapToItem(null, 0, callouts[0].height).y + " " + setup.mapToItem(null, 0, 0).y);
            const links = descendants(callouts[0]).filter(item => item instanceof RowAction && item.visible);
            compare(links.map(link => link.text), data.link ? [root.guide.link] : [], "the guide links its README section only where one opens");
            if (!data.link) return;
            tryVerify(() => links[0].height > 0 && pageOf(window).parent.x === -window.width, 2000, "the page has slid in");
            mouseClick(links[0]);
            compare(fakeRun.launched, [DesktopLaunch.open(root.guide.url)], "the link opens the README section in the default browser");
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
            return [{ tag: "step info", label: "Connection", page: "acme.done", tab: "Details" },
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
        function keyLines(window) {
            const row = onTab(window, StatusRow).find(item => item.entry !== null && item.entry.key === "keys");
            return row === undefined ? [] : descendants(row).filter(item => item instanceof StatusLine && item.visible);
        }
        function settled(window, item) {
            let last = null;
            tryVerify(() => {
                const at = item.mapToItem(null, 0, 0), still = last !== null && at.x === last.x && at.y === last.y;
                last = at;
                return item.height > 0 && still && pageOf(window).parent.x === -window.width;
            }, 3000, "the page has settled");
        }
        function test_a_settings_key_list_draws_its_keys_as_the_fields_own() {
            const window = opened(); window.openPlugin("acme.sourced", Qt.OtherFocusReason);
            compare(pageOf(window).tab, "Settings");
            compare(keyLines(window).map(line => line.label), ["Acme", "Globex"], "the list draws its keys alone, with no head");
            compare(onTab(window, Badge).length, 0, "a stored key draws no chip on Settings");
            const acme = keyLines(window)[0];
            verify(acme.text !== "" && acme.tone === "", "a stored key reads plain text");
            for (const line of keyLines(window))
                verify(descendants(line).some(item => item instanceof RowAction && item.visible && item.text === "Make key"), line.label + " offers its source");
            // A key's own write reads in its value's place and holds its
            // source; the other key reads as it did.
            const acmeText = acme.text;
            window.writing = { step: window.stepKey("acme.sourced", "keys", "acme:g"), verb: "store" };
            const globex = keyLines(window).find(line => line.label === "Globex");
            compare([globex.text, globex.tone], [Steps.WRITE_WORDS.store, ""], "Globex reads its write");
            verify(!descendants(globex).find(item => item instanceof RowAction && item.visible && item.text === "Make key").enabled, "Globex's source takes no press while its write runs");
            compare(keyLines(window)[0].text, acmeText, "Acme reads as it did");
            window.writing = { step: window.stepKey("acme.sourced", "keys", "acme:g"), verb: "clear" };
            compare(globex.text, Steps.WRITE_WORDS.clear, "a removal reads its own write");
            window.writing = null;
            compare(globex.text, "", "the write's words go once it ends");
            window.openPlugin("acme.sourced", Qt.OtherFocusReason, "Details");
            const wiring = onTab(window, StatusRow).find(item => item.entry !== null && item.entry.key === "wiring");
            verify(wiring !== undefined, "Details draws its key list");
            compare(descendants(wiring).filter(item => item instanceof StatusLine && item.visible).map(line => line.label), ["Wiring", "Bar"], "a Details key list keeps its head");
        }
        // expected-log: settings: acme.sourced/keys/source acme:g refused: tui=make reason=busy-other -- the refused source the case plants
        // expected-log: settings: acme.sourced/keys/acme:g refused: secret write failed locked -- the failed write the case plants
        function test_a_key_source_takes_the_manager_route_and_keeps_its_own_reply() {
            const window = opened(); window.openPlugin("acme.sourced", Qt.OtherFocusReason);
            const globex = () => keyLines(window).find(line => line.label === "Globex");
            const source = () => descendants(globex()).find(item => item instanceof RowAction && item.visible && item.text === "Make key");
            settled(window, source());
            mouseClick(source());
            compare(fakeManager.acts, [["acme.sourced", "keys", "acme:g", "source"]], "the source asks the manager for that key's account");
            const input = descendants(globex()).find(item => item instanceof TextField);
            verify(input !== undefined && input.activeFocus, "the key's field opened and holds the keyboard");
            const busy = "refused: tui=make reason=busy-other";
            fakeManager.actionReply = busy;
            source().clicked();
            compare(globex().error, Reply.line(busy), "the refused source reads under its key, translated");
            const failed = "refused: secret write failed locked";
            window.keep(window.stepKey("acme.sourced", "keys", "acme:g"), failed);
            verify(globex().error.indexOf(Reply.line(failed)) !== -1 && globex().error.indexOf(Reply.line(busy)) !== -1, "the write's failure and the source's refusal read side by side");
            fakeManager.actionReply = "ok";
            source().clicked();
            compare(globex().error, Reply.line(failed), "a source that opens clears its own refusal alone");
            const typed = descendants(globex()).find(item => item instanceof TextField);
            typed.forceActiveFocus();
            keyClick(Qt.Key_Escape);
            tryVerify(() => descendants(globex()).find(item => item instanceof TextField) === undefined, 1000, "Escape closes the field");
            const add = descendants(globex()).find(item => item instanceof RowAction && item.visible && item.text === "Add key");
            verify(add !== undefined && add.activeFocus, "Escape hands the keyboard back to Add key");
        }
        function test_a_settings_key_list_with_no_key_reads_one_sentence_data() {
            return [{ tag: "listed none", id: "acme.sourcedempty", hint: true }, { tag: "not yet reported", id: "acme.sourcedwait", hint: false }, { tag: "plugin off", id: "acme.sourcedoff", hint: false }];
        }
        function test_a_settings_key_list_with_no_key_reads_one_sentence(data) {
            const window = opened(); window.openPlugin(data.id, Qt.OtherFocusReason);
            const lines = keyLines(window);
            compare(lines.length, 1, "the list draws one line");
            compare(lines[0].label, "", "with no label of its own: the field names what it is for");
            verify(lines[0].hint !== "", "it reads a sentence under the field");
            compare(lines[0].hint === root.sourcedHint, data.hint, "an empty list reads its hint, any other state its own sentence");
            compare(descendants(lines[0]).filter(item => item instanceof RowAction && item.visible).length, 0, "with no key it offers no action");
        }
        // A key the keyring cannot read links its own plugin's Setup tab,
        // where the Tools step installs the key tool, while that tool is
        // missing, and links nothing while it is present.
        function test_an_unavailable_key_links_setup_while_its_tool_is_missing_data() {
            return [{ tag: "tool missing", id: "acme.keytoolmissing", links: [["acme.keytoolmissing", "Setup"]] },
                { tag: "tool present", id: "acme.keytoolpresent", links: [] }];
        }
        function test_an_unavailable_key_links_setup_while_its_tool_is_missing(data) {
            const window = opened(); window.openPlugin(data.id, Qt.OtherFocusReason);
            compare(pageOf(window).tab, "Settings");
            const line = keyLines(window).find(item => item.label === "Acme");
            verify(line !== undefined, "the unavailable key draws its line");
            const hint = descendants(line).find(item => item instanceof LinkText && item.visible && item.role === "hint" && item.plain !== "");
            verify(hint !== undefined, "the key reads a sentence under its value");
            compare(hint.links.map(link => [link.page, link.tab]), data.links, "the sentence links the plugin's Setup tab only while the key tool is missing");
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
                { tag: "failed build row", id: "acme.failed", row: true, asked: "", tab: "Settings" },
                { tag: "refused row", id: "acme.refused", row: true, asked: "", tab: "Settings" },
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
        // While the plugin is off, the tab opens with one Turn on notice
        // above the steps, whose press asks the manager to turn the plugin
        // on; each step keeps its chip and offers no Turn on, and the Tools
        // step still installs.
        function test_off_plugin_setup_opens_with_one_turn_on_notice() {
            const window = opened(); window.openPlugin("acme.off", Qt.OtherFocusReason, "Setup");
            compare(pageOf(window).tab, "Setup");
            const notices = onTab(window, Callout);
            compare(notices.length, 1, "the tab draws one notice");
            const setup = onTab(window, Section).find(section => section.title === "Setup");
            tryVerify(() => notices[0].height > 0 && notices[0].mapToItem(null, 0, notices[0].height).y <= setup.mapToItem(null, 0, 0).y, 2000, "the notice stands above the steps");
            const link = descendants(notices[0]).filter(item => item instanceof RowAction && item.visible);
            compare(link.length, 1, "the notice draws one link");
            // Model reads To do and Home, published as done, Done; neither offers a link.
            compare(onTab(window, StatusLine).map(line => [line.label, line.text, line.actionOffered]), [["Model", "To do", false], ["Home", "Done", false]], "each step keeps its chip and offers nothing");
            compare(onTab(window, RowAction).filter(action => link.indexOf(action) === -1).length, 0, "no step draws a link");
            tryVerify(() => pageOf(window).parent.x === -window.width, 2000, "the page has slid in");
            mouseClick(link[0]);
            compare(fakeManager.enables, [["acme.off", true]], "Turn on asks to turn the plugin on");
            window.openPlugin("acme.offtools", Qt.OtherFocusReason, "Setup");
            compare(onTab(window, Callout).length, 1, "a plugin with only a Tools step opens with the notice too");
            const review = onTab(window, StatusLine).map(line => line.actionOffered ? line.actionLabel : "");
            compare(review, ["Review all missing or outdated tools"], "the Tools step installs while the plugin is off");
            const reviewLink = descendants(onTab(window, StatusLine)[0]).find(item => item instanceof RowAction && item.visible);
            mouseClick(reviewLink);
            compare(fakeManager.installs, ["acme.offtools"]);
        }
        // A value the user picks on the page goes through the manager's
        // choice route once, with its plugin, key and value, which tells the
        // plugin of it (PluginStatus.handleChoice).
        function test_a_page_choice_takes_the_choice_route() {
            const window = opened(); window.openPlugin("acme.optional", Qt.OtherFocusReason, "Settings");
            const field = descendants(tabsOf(window).currentPage).find(item => item instanceof SettingField && item.key === "feature");
            verify(field !== undefined, "the page draws the feature field");
            const toggle = descendants(field).find(item => item instanceof Switch && item.visible);
            tryVerify(() => toggle.height > 0 && pageOf(window).parent.x === -window.width, 2000, "the page has slid in");
            mouseClick(toggle);
            compare(fakeManager.chosen, [["acme.optional", "feature", true]]);
        }
        // A reference to a row brings it into view on its tab and marks it
        // with one plate inside the content, until a scroll the reveal did
        // not make: [tag, plugin, reference, tab, the row's key].
        function test_a_row_reference_scrolls_to_it_and_marks_it_data() {
            return [{ tag: "a Settings field", id: "acme.long", reference: "Settings/f39", tab: "Settings", key: "f39" },
                { tag: "a Setup step", id: "acme.longsteps", reference: "Setup/s29", tab: "Setup", key: "s29" },
                { tag: "a Details fact", id: "acme.longsteps", reference: "Details/f29", tab: "Details", key: "f29" }];
        }
        function test_a_row_reference_scrolls_to_it_and_marks_it(data) {
            const window = opened(); window.openPlugin(data.id, Qt.OtherFocusReason, data.reference);
            const area = pageOf(window).scrollArea;
            compare(pageOf(window).tab, data.tab);
            tryVerify(() => area.contentY > 0, 2000, "the page scrolls to the far row");
            const far = descendants(tabsOf(window).currentPage).find(item => item.visible && (item.fieldKey === data.key || item.statusKey === data.key));
            verify(far !== undefined, "the tab draws the row");
            const top = far.mapToItem(area, 0, 0).y;
            verify(top >= 0 && top + far.height <= area.height, "the far row is in view: " + top);
            const plate = descendants(area.contentItem).find(item => item.objectName === "revealMark");
            verify(plate !== undefined, "the page declares its plate");
            tryCompare(plate, "opacity", 1, 2000);
            const box = far.mapToItem(plate.parent, 0, 0);
            verify(plate.y <= box.y && plate.y + plate.height >= box.y + far.height, "the plate covers the row");
            verify(plate.x >= 0 && plate.x + plate.width <= plate.parent.width, "the plate stays inside the content: " + [plate.x, plate.width, plate.parent.width]);
            area.contentY = 0;
            tryVerify(() => !plate.visible, 2000, "a scroll the reveal did not make clears the plate");
        }
        // The area settling back inside its end after a reveal, as the
        // window takes the page's height, keeps the plate: only a scroll
        // the user makes clears it.
        function test_a_settle_inside_the_end_keeps_the_plate() {
            const window = opened(); window.openPlugin("acme.longsteps", Qt.OtherFocusReason, "Details/f29");
            const area = pageOf(window).scrollArea;
            tryVerify(() => area.contentY > 0, 2000, "the page scrolls to the far row");
            const plate = descendants(area.contentItem).find(item => item.objectName === "revealMark");
            tryCompare(plate, "opacity", 1, 2000);
            const scrolled = area.contentY;
            const height = area.height;
            area.height = area.contentHeight;
            tryVerify(() => area.contentY < scrolled, 2000, "the area settles inside its end: " + area.contentY);
            compare(pageOf(window).revealing, "f29", "the settle keeps the row shown");
            compare(plate.opacity, 1, "the settle keeps the plate");
            area.height = height;
            area.contentY = 10;
            tryVerify(() => !plate.visible, 2000, "a scroll the user makes clears the plate");
        }
        // A reference to a key its tab draws no row for opens the tab and
        // says so at the page head, once.
        function test_a_reference_to_an_undrawn_row_is_refused() {
            ignoreWarning("settings: acme.longsteps refused: page-target=Setup/f29 reason=undrawn");
            const window = opened(); window.openPlugin("acme.longsteps", Qt.OtherFocusReason, "Setup/f29");
            compare(pageOf(window).tab, "Setup");
            tryCompare(pageOf(window).panel, "replies", ({ "acme.longsteps": Reply.line("refused: page-target=Setup/f29 reason=undrawn") }), 2000);
            compare(pageOf(window).panel.headReplies("acme.longsteps").length, 1, "the page head draws it");
            compare(pageOf(window).revealing, "", "the page shows nothing");
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
                { tag: "required delegate", kind: "delegate", id: "acme.todo", tab: "Setup" },
                { tag: "Details tool", kind: "tool", id: "acme.optional", tab: "Details" }];
        }
        function test_detached_rows_keep_their_layout_owner_width(data) {
            const window = opened(); window.openPlugin(data.id, Qt.OtherFocusReason, data.tab);
            const body = tabsOf(window).currentPage;
            let loader, group, row, owner;
            if (data.kind === "more") {
                row = onTab(window, Field).find(field => field.label === "More settings");
                owner = body;
            } else if (data.kind === "tool") {
                row = onTab(window, RequirementRow)[0];
                owner = descendants(body).find(item => item instanceof Section && descendants(item).indexOf(row) !== -1);
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
