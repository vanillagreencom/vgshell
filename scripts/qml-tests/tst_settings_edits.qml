import QtQuick
import QtTest
import qs.Commons
import qs.Core
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.settings"

// The Settings page's unsaved edits: a text field keeps what is typed
// until it is saved and joins the page's set (EditSet) meanwhile. Enter
// writes the field it is pressed in, a loss of focus writes nothing, a
// refused text stays, an accepted one draws what the configuration holds,
// and a read-only field and a hidden custom row hold no edit. The set
// saves every field, says when an accepted write of an edit leaves it
// empty, whether its save or Enter in the field sent it, and forgets a
// destroyed field. A Keys row's typed key waits the same way, returns to
// its text entry when its owner refuses it and leaves a read-only row; a
// key the row sends without its text entry is no edit. A Keys row offers
// its reset while the keys in effect are not every default key, one or a
// list, and the reset sends undefined; from the text entry or a capture it
// closes them first, so the default keys show at once. The reset and the
// add button keep their places as they come and go, and the add button
// hides while the text entry is open. A plugin page draws one Keys row per
// shortcut, every alternative key in its one field: Delete on one writes
// the keys left, the add button and a pressed combo write the list with
// the new key, Use my binding removes the key a user bind holds, and the
// reset sends undefined. A refused key returns to the row's text entry
// whether the field or a caller sent it, and a refused removal or list
// opens none. A field that declares `shownWhen` is drawn only while its
// presence entry reads present, and a plugin whose fields only wait keeps
// its Turn on hint while it is off. The owner here stands in for the
// page: it records each write and takes it or refuses it; the page's
// capture names keys with the core's judge and says a user bind holds
// Right Ctrl when asked.
Item {
    id: root
    width: 480
    height: 400

    property var writes: []
    property bool accepts: true
    property var keys: []
    property var pageRow: ({
        id: "acme.unit",
        name: "Unit",
        version: "1",
        description: "Unit plugin",
        author: "VGS",
        license: "",
        icon: "package",
        source: "bundled",
        enabled: true,
        placed: false,
        builtins: [],
        kinds: ["service"],
        capabilities: ["shortcut"],
        schema: ({}),
        settings: ({}),
        settingChoices: ({}),
        status: [],
        secretLabel: "",
        guide: null,
        tuis: [],
        opens: "",
        paneHolder: "",
        binds: [{ shortcut: "tap", key: "code:108", keys: ["code:108", "code:105"], default: ["code:108", "code:105"], description: "Tap" }],
        requirements: [],
        errors: []
    })

    EditSet { id: unsaved }
    QtObject {
        id: pageCapture
        property Item holder: null
        property bool failed: false
        property bool userHoldsRightCtrl: false
        property var ended: ({ item: null, reason: "" })
        readonly property int timeoutMs: 10000
        function begin(item) { holder = item; return "ok"; }
        function end(item, reason) { if (item !== holder) return; ended = { item: item, reason: reason }; holder = null; }
        function keyFor(key, modifiers) { return PluginLogic.capturedKey(key, modifiers); }
        function conflicts(key, id, shortcut) {
            const user = userHoldsRightCtrl && key === "code:105";
            return { plugins: [], user: user, binds: "read", userBinds: [], hint: user ? "Also used by your Hyprland config." : "" };
        }
    }
    SignalSpy { id: saved; target: unsaved; signalName: "saved" }
    Item {
        id: fakePanel
        property var shell: null
        property var plugins: []
        property var capture: pageCapture
        property var keyWrites: []
        property bool refusesKeys: false
        function writeKey(id, shortcut, key) {
            keyWrites.push([id, shortcut, key]);
            return refusesKeys ? "refused: key=" + shortcut : "ok";
        }
        function writeSetting() { return "ok"; }
        function setEnabled() { return "ok"; }
        function setPlaced() { return "ok"; }
        function installRequirements() { return "ok"; }
        function openPane() { return "ok"; }
        function openPlugin() { return "ok"; }
        function updatePlugin() { return "ok"; }
        function removePlugin() { return "ok"; }
        function openTui() { return "ok"; }
        function act() { return "ok"; }
        function replyOf() { return ""; }
        function headReplies() { return []; }
    }

    Column {
        width: 420
        spacing: Theme.stack.row

        Button { id: elsewhere; text: "Elsewhere"; focusPolicy: Qt.StrongFocus }
        SettingField {
            id: gap
            key: "gap"
            spec: ({ type: "number", label: "Gap" })
            value: 4
            edits: unsaved
            onApply: v => { root.writes.push(["gap", v]); if (root.accepts) gap.value = v; }
        }
        SettingField {
            id: size
            key: "size"
            spec: ({ type: "number", label: "Size" })
            value: 12
            edits: unsaved
            onApply: v => { root.writes.push(["size", v]); if (root.accepts) size.value = v; }
        }
        SettingField {
            id: clock
            key: "clock"
            spec: ({ type: "string", label: "Clock", format: "datetime", allowCustom: true, presets: [{ value: "HH:mm" }, { value: "ddd HH:mm" }] })
            value: "HH:mm:ss"
            edits: unsaved
            onApply: v => { root.writes.push(["clock", v]); if (root.accepts) clock.value = v; }
        }
        KeyField {
            id: keyRow
            pluginId: "acme.unit"
            bind: ({ shortcut: "toggle", key: "SUPER+M", default: "SUPER+M", description: "Toggle" })
            edits: unsaved
            onApplyKey: key => { root.keys.push(key); keyRow.settle(key, root.accepts); }
        }
    }

    Component {
        id: disposable
        SettingField {
            key: "spare"
            spec: ({ type: "number", label: "Spare" })
            value: 1
            edits: unsaved
        }
    }

    Component {
        id: disposableKey
        KeyField {
            pluginId: "acme.unit"
            bind: ({ shortcut: "spare", key: "SUPER+N", default: "SUPER+N", description: "Spare" })
            edits: unsaved
        }
    }

    Component {
        id: listDefaultKey
        KeyField {
            pluginId: "acme.unit"
            bind: ({ shortcut: "tap", key: "code:108", keys: ["code:108"], default: ["code:108", "code:105"], description: "Tap" })
            onApplyKey: key => root.keys.push(key)
        }
    }

    Component {
        id: pluginPageComponent
        PluginPage {
            width: 420
            height: 360
            panel: fakePanel
            row: root.withFields(root.pageRow)
        }
    }

    // The manager row a page draws: ROW with the rows of its fields as the
    // core judges them with the manifest (PluginLogic.fieldRows), the ones
    // ROW holds, else from its schema alone, for a row that attaches no
    // entry to a field.
    function withFields(row) { return Object.assign({}, row, { fieldRows: row.fieldRows !== undefined ? row.fieldRows : PluginLogic.fieldRows(row.schema, {}) }); }

    TestCase {
        name: "settingsEdits"
        when: windowShown

        function init() {
            UnitTheme.reset();
            root.accepts = true;
            fakePanel.refusesKeys = false;
            unsaved.discard();
            gap.value = 4;
            size.value = 12;
            clock.value = "HH:mm:ss";
            gap.editable = true;
            keyRow.editable = true;
            root.writes = [];
            root.keys = [];
            saved.clear();
            elsewhere.forceActiveFocus(Qt.TabFocusReason);
        }

        function descendants(item) {
            const found = [item];
            for (let i = 0; i < found.length; i++)
                for (const child of found[i].children || []) found.push(child);
            return found;
        }
        function editor(field) { return descendants(field).find(child => child instanceof TextInput && child.visible); }
        // The Repeater builds its delegates after the model answers; wait for
        // READY, then let the comparison that follows report what is shown.
        function settle(ready) { for (let i = 0; i < 20 && !ready(); i++) wait(50); }
        function keyFields(item) { return descendants(item).filter(child => child.pluginId === "acme.unit" && child.bind !== undefined && child.shortcutField !== undefined); }
        // destroy() defers deletion until this script block ends. Detach
        // the page before restoring the shared model, so cleanup creates
        // no new shortcut fields on a page that is leaving.
        // https://doc.qt.io/qt-6/qtqml-javascript-dynamicobjectcreation.html
        // The page returns to Settings first: rows destroyed while their
        // tab shows log a context warning from Qt.
        function releasePage(page, restoredRow) {
            page.open(Qt.OtherFocusReason, "Settings");
            page.row = null;
            compare(keyFields(page).length, 0);
            root.pageRow = restoredRow;
            compare(keyFields(page).length, 0, "cleanup does not rebuild shortcut fields");
            page.destroy();
        }
        function type(field, text) {
            const input = editor(field);
            input.forceActiveFocus(Qt.TabFocusReason);
            input.selectAll();
            for (const c of text) keyClick(c);
            return input;
        }

        function test_settings_key_boxes_keep_width_across_bound_unbound_and_reset_states() {
            const original = { shortcut: "spare", key: "SUPER+M", default: "SUPER+M", description: "Spare" };
            const field = disposableKey.createObject(root, { width: 600, capture: pageCapture, bind: original });
            const box = () => descendants(field).find(item => String(item).indexOf("QQuickAbstractButton") === 0);
            // Rows update once per frame. Finish the nested action/tool
            // layouts before reading the box, including hidden actions.
            // https://doc.qt.io/qt-6/qml-qtquick-row.html#forceLayout-method
            const layout = () => {
                for (let item = field.actions[0].parent; item; item = item.parent)
                    if (typeof item.forceLayout === "function") item.forceLayout();
            };
            layout();
            const expected = box().width;
            for (const key of [null, "SUPER+N", "SUPER+M"]) {
                field.bind = Object.assign({}, original, { key: key });
                const reset = field.actions.find(item => item.label.indexOf("Reset to ") === 0);
                compare(reset.visible, key !== original.default);
                layout();
                tryCompare(box(), "width", expected);
            }
            field.destroy();
        }

        // The reset and the add button, each in its place whatever shows:
        // the reset while the keys differ from the default, the add button
        // while the text entry is closed.
        function test_key_row_buttons_keep_their_places() {
            const original = { shortcut: "spare", key: "SUPER+K", default: "SUPER+N", description: "Spare" };
            const field = createTemporaryObject(disposableKey, root, { width: 600, capture: pageCapture, bind: original });
            const reset = field.actions.find(item => item.iconName === "rotate-ccw");
            const add = field.actions.find(item => item.iconName === "plus");
            const left = item => item.mapToItem(field, 0, 0).x;
            verify(waitForPolish(root.Window.window));
            const at = [left(reset), left(add)];
            // [why, set up the row, reset shown, add shown]
            for (const [why, setUp, resetShown, addShown] of [
                ["keys other than the default", () => {}, true, true],
                ["the default keys", () => { field.bind = Object.assign({}, original, { key: "SUPER+N" }); }, false, true],
                ["the text entry open", () => field.shortcutField.startTyping(), true, false]
            ]) {
                field.shortcutField.stopTyping();
                field.bind = original;
                setUp();
                verify(waitForPolish(root.Window.window));
                compare(reset.visible, resetShown, why);
                compare(add.visible, addShown, why);
                compare(JSON.stringify([left(reset), left(add)]), JSON.stringify(at), why);
            }
            field.shortcutField.stopTyping();
        }

        // A reset from the text entry, a capture or a new key's capture
        // leaves them, so the field shows the default keys the page writes
        // back at once.
        function test_reset_shows_the_default_keys_from_any_state() {
            const original = { shortcut: "spare", key: "SUPER+K", default: "SUPER+N", description: "Spare" };
            const field = createTemporaryObject(disposableKey, root, { width: 600, capture: pageCapture, bind: original });
            field.applyKey.connect(key => { if (key === undefined) field.bind = Object.assign({}, original, { key: "SUPER+N" }); });
            const reset = field.actions.find(item => item.iconName === "rotate-ccw");
            const shown = () => descendants(field).filter(item => String(item).indexOf("KeyCaps") === 0 && item.visible).map(item => item.caps.join("+"));
            const sf = field.shortcutField;
            // [why, the state the reset starts from]
            for (const [why, enter] of [
                ["the text entry", () => { sf.startTyping(); for (const c of "SUPER+J") keyClick(c); }],
                ["a capture", () => { sf.forceActiveFocus(Qt.TabFocusReason); sf.edit(0); }],
                ["a new key's capture", () => sf.add()]
            ]) {
                field.bind = original;
                enter();
                verify(sf.typing || sf.capturing, why);
                reset.clicked();
                compare(sf.typing, false, why);
                compare(sf.capturing, false, why);
                compare(sf.adding, false, why);
                compare(JSON.stringify(shown()), JSON.stringify(["Super+N"]), why);
                compare(unsaved.edited, false, why);
            }
        }

        function test_settings_bind_explanation_uses_the_shared_label_tooltip() {
            const field = disposableKey.createObject(root, { width: 420, z: 1,
                bind: { shortcut: "spare", key: "SUPER+N", default: "SUPER+N", description: "Spare", info: "Open the window." } });
            compare(UnitTheme.override({ tooltip: { delay: 20 } }), "ok");
            const label = descendants(field).find(item => item.objectName === "fieldLabel");
            const tip = descendants(label).find(item => String(item).indexOf("Tooltip") === 0);
            verify(!descendants(field).some(item => String(item).indexOf("InfoButton") === 0));
            compare(tip.text, "Open the window.");
            mouseMove(label, label.width / 2, label.height / 2);
            tryCompare(tip, "opened", true);
            mouseMove(root, root.width - 1, root.height - 1);
            tryCompare(tip, "opened", false);
            root.Window.window.requestActivate();
            tryCompare(root.Window.window, "active", true);
            wait(0);
            const focused = [];
            const record = () => { if (tip.opened) focused.push(tip.text); };
            tip.openedChanged.connect(record);
            try {
                const control = label.children.find(item => item.visualFocus !== undefined);
                control.forceActiveFocus(Qt.OtherFocusReason);
                keyClick(Qt.Key_Tab);
                keyClick(Qt.Key_Backtab);
                compare(control.activeFocus, true);
                compare(control.visualFocus, true);
                tryVerify(() => focused.length > 0, 2000);
                compare(root.Window.window.active, true);
                compare(control.activeFocus, true);
            } finally {
                tip.openedChanged.disconnect(record);
            }
            compare(focused[0], tip.text);
            elsewhere.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(tip, "opened", false);
            field.destroy();
        }

        function test_a_typed_text_waits_and_joins_the_set() {
            const input = type(gap, "73");
            compare(input.text, "73");
            verify(gap.edited && unsaved.edited, "the field and the set hold the edit");
            elsewhere.forceActiveFocus(Qt.TabFocusReason);
            compare(input.text, "73", "a loss of focus keeps the text");
            compare(root.writes, []);
            verify(gap.edited, "and the edit");
        }

        // A status reading, such as the graphics card a GPU switch needs,
        // reads on Details alone: the switch beside it on Settings keeps
        // its own description.
        function test_a_status_message_reads_on_details_alone() {
            const original = root.pageRow;
            const manifest = { status: { graphics: { type: "state", label: "Graphics card", group: "Readings" } } };
            root.pageRow = Object.assign({}, original, {
                schema: { showGpu: { type: "boolean", label: "GPU", group: "Readings" } },
                settings: { showGpu: true }, binds: [],
                status: PluginLogic.statusRows(manifest, { graphics: { text: "Not found", tone: "info", hint: "No supported graphics card found." } })
            });
            const page = createTemporaryObject(pluginPageComponent, root);
            verify(page !== null);
            const field = () => descendants(page).find(child => child instanceof SettingField && child.key === "showGpu");
            tryVerify(() => field() !== undefined);
            compare(field().hintText, "", "the switch reads no status message");
            verify(!descendants(field()).some(child => child.role === "hint" && child.visible && child.text === "No supported graphics card found."), "Settings draws no status message");
            const tabs = descendants(page).find(child => child instanceof TabPages);
            verify(tabs !== undefined);
            tabs.currentIndex = 1;
            const status = () => descendants(page).find(child => child instanceof StatusRow && child.entry !== null && child.entry.key === "graphics");
            tryVerify(() => status() !== undefined);
            const chip = descendants(status()).find(child => child instanceof Badge && child.text === "Not found");
            const message = descendants(status()).find(child => child.role === "hint" && child.text === "No supported graphics card found.");
            verify(chip !== undefined && chip.visible, "Details chip says Not found");
            verify(message !== undefined && message.visible, "Details shows the full message");
            // The tab's Columns position their children after it becomes visible.
            tryVerify(() => message.mapToItem(status(), 0, 0).y >= chip.mapToItem(status(), 0, chip.height).y, 1000, "the full message sits beneath the chip");
            releasePage(page, original);
        }

        // Required steps and their keys share one section. All actions
        // are links; danger actions and the key list keep their dividers.
        function test_required_steps_and_keys_draw_links_and_hairlines() {
            const original = root.pageRow;
            const screen = { requires: null };
            const manifest = {
                secrets: { service: "acme-unit", label: "Key" }, requirements: [],
                tui: { pairs: screen, connect: screen, out: screen },
                status: {
                    sync: { type: "state", label: "Google Drive sync", setup: true },
                    pairs: { type: "state", label: "Folder pairs", setup: true, action: { label: "Add a pair", tui: "pairs" } },
                    keys: { type: "presenceList", label: "Keys", step: "down" },
                    down: { type: "state", label: "Sign-in", setup: true, actions: { signIn: { label: "Sign in", tui: "connect" }, signOut: { label: "Sign out", tui: "out", tone: "danger" } } }
                }
            };
            const values = {
                sync: { tone: "ok", text: "Up to date" },
                pairs: { tone: "warning", text: "None", action: true },
                keys: [{ label: "Client ID", value: "present", secret: "acme:id" }],
                down: { tone: "ok", text: "Signed in", action: "signOut" }
            };
            root.pageRow = Object.assign({}, original, { binds: [], status: PluginLogic.statusRows(manifest, values) });
            const page = createTemporaryObject(pluginPageComponent, root);
            try {
                verify(page !== null);
                page.open(Qt.OtherFocusReason, "Setup");
                compare(page.tab, "Setup", "a page with setup steps has a Setup tab");
                const shown = type => descendants(page).filter(child => child instanceof type && child.visible);
                tryVerify(() => shown(StatusRow).length === 1, 1000, "the key list is drawn");
                compare(shown(SectionHeader).map(header => header.text).filter(text => ["Status", "Setup", "Download"].indexOf(text) !== -1), ["Setup"]);
                verify(shown(Field).some(row => row.label === "Google Drive sync"), "the Status section draws its entry under its own label");
                compare(shown(Button).filter(button => button.variant === "primary").map(button => button.text), [], "Setup has no boxed action");
                compare(shown(RowAction).map(action => action.text + " " + action.tone).sort(), ["Add a pair accent", "Remove danger", "Replace accent", "Sign out danger"]);
                // The key list draws its one key alone under its step, so
                // its own list holds no divider; the steps keep theirs.
                compare(shown(GroupList).map(list => list.hairlines.length).sort(), [0, 3], "required rows keep their dividers, and a lone key under its step has none of its own");
                page.open(Qt.OtherFocusReason, "Settings");
                compare(shown(SectionHeader).map(header => header.text).filter(text => ["Status", "Setup", "Download"].indexOf(text) !== -1), [], "Settings draws none of the setup");
            } finally {
                releasePage(page, original);
            }
        }

        // Required steps with hints keep the same row pitch.
        function test_setup_steps_keep_one_row_pitch() {
            const original = root.pageRow;
            const screen = { requires: null };
            const step = (label, tui) => ({ type: "state", label: label, setup: true, hint: "What " + label + " unlocks.", action: { label: "Set up " + label, tui: tui } });
            const manifest = {
                requirements: [],
                tui: { voice: screen, browser: screen, input: screen },
                status: { ready: { type: "state", label: "Ready" }, voice: step("Voice", "voice"), browser: step("Browser", "browser"), input: step("Input", "input") }
            };
            const todo = { tone: "warning", text: "To do", action: true };
            root.pageRow = Object.assign({}, original, { binds: [], status: PluginLogic.statusRows(manifest, { ready: { tone: "ok", text: "Ready" }, voice: todo, browser: todo, input: todo }) });
            const page = createTemporaryObject(pluginPageComponent, root);
            try {
                verify(page !== null);
                page.open(Qt.OtherFocusReason, "Setup");
                compare(page.tab, "Setup", "a page with setup steps has a Setup tab");
                const row = label => descendants(page).find(child => child instanceof Field && child.visible && child.label === label);
                tryVerify(() => row("Voice") !== undefined && row("Browser") !== undefined && row("Input") !== undefined);
                compare(descendants(row("Voice")).filter(child => child instanceof RowAction && child.visible).length, 1, "the first step draws a RowAction");
                compare(descendants(row("Browser")).filter(child => child instanceof RowAction && child.visible).length, 1, "the next step draws a RowAction");
                verify(waitForRendering(page));
                const top = label => row(label).mapToItem(page, 0, 0).y;
                compare(top("Browser") - top("Voice"), top("Input") - top("Browser"), "required steps keep the same row pitch");
            } finally {
                releasePage(page, original);
            }
        }

        function test_builtin_and_matching_schema_group_share_one_section() {
            const original = root.pageRow;
            root.pageRow = Object.assign({}, original, {
                builtins: [{ id: "acme.unit-clock", name: "Clock", placed: true }],
                schema: {
                    format: { type: "boolean", label: "Format", group: "Clock" },
                    hidden: { type: "boolean", label: "Hidden", group: "Bar" },
                    plain: { type: "boolean", label: "Plain" }
                },
                settings: { format: true, hidden: false, plain: true }, binds: []
            });
            const page = createTemporaryObject(pluginPageComponent, root);
            verify(page !== null);
            const sections = () => descendants(page).filter(item => item instanceof Section);
            tryVerify(() => sections().some(item => item.title === "Clock"));
            const clockSections = sections().filter(item => item.title === "Clock");
            compare(clockSections.length, 1, "same-named groups draw one heading");
            const fields = descendants(clockSections[0]).filter(item => item instanceof SettingField);
            verify(fields.some(item => item.pluginId === "acme.unit-clock" && item.visible));
            verify(fields.some(item => item.key === "format" && item.visible));
            verify(sections().some(item => item.title === "Bar" && descendants(item).some(child => child.key === "hidden")));
            verify(sections().every(item => !descendants(item).some(child => child.key === "plain")), "a field of no group draws in no section");
            const plain = descendants(page).find(item => item instanceof SettingField && item.key === "plain");
            verify(plain !== undefined && plain.visible, "a field of no group draws");
            verify(plain.mapToItem(page, 0, 0).y < clockSections[0].mapToItem(page, 0, 0).y, "a field of no group draws above the sections");
            releasePage(page, original);
        }

        function test_grouped_lists_follow_their_group() {
            const original = root.pageRow;
            root.pageRow = Object.assign({}, original, {
                schema: {
                    mode: { type: "boolean", label: "Mode", group: "Main" },
                    grouped: { type: "list", label: "Grouped list", group: "Main",
                        items: { item: { type: "string", label: "Item", presets: [{ value: "", label: "None" }] } },
                        defaults: { item: "" } },
                    unknown: { type: "list", label: "Unknown list", group: "Missing",
                        items: { item: { type: "string", label: "Item", presets: [{ value: "", label: "None" }] } },
                        defaults: { item: "" } },
                    plain: { type: "list", label: "Plain list",
                        items: { item: { type: "string", label: "Item", presets: [{ value: "", label: "None" }] } },
                        defaults: { item: "" } }
                },
                settings: { mode: true, grouped: [], unknown: [], plain: [] }, binds: []
            });
            const page = createTemporaryObject(pluginPageComponent, root);
            verify(page !== null);
            try {
                tryVerify(() => page.sections.length === 1);
                compare(page.sections[0].group, "Main");
                compare(page.sections[0].lists, ["grouped"]);
                compare(page.lists, ["unknown", "plain"]);
                const sections = descendants(page).filter(item => item instanceof Section && item.title !== "Keys");
                tryVerify(() => sections.some(item => item.title === "Grouped list"));
                const titles = sections.filter(item => ["Main", "Grouped list", "Unknown list", "Plain list"].indexOf(item.title) !== -1)
                    .sort((a, b) => a.mapToItem(page, 0, 0).y - b.mapToItem(page, 0, 0).y).map(item => item.title);
                compare(titles, ["Main", "Grouped list", "Unknown list", "Plain list"]);
            } finally {
                releasePage(page, original);
            }
        }

        function test_a_hide_empty_field_has_no_place_while_nothing_is_offered() {
            const original = root.pageRow;
            const choices = { type: "string", optionsFrom: "items" };
            // `attached` keeps its row while the stored key list beside it
            // draws; `attachedHidden`'s list has left the manager row, so
            // it draws nothing beside the field and the field has no place.
            const schema = {
                kept: Object.assign({ label: "Kept", group: "Choices" }, choices),
                hiding: Object.assign({ label: "Hiding", group: "Choices", hideEmpty: true }, choices),
                alone: Object.assign({ label: "Alone", group: "Lone", hideEmpty: true }, choices),
                attached: Object.assign({ label: "Attached", group: "Choices", hideEmpty: true }, choices),
                attachedHidden: Object.assign({ label: "Attached hidden", group: "Choices", hideEmpty: true }, choices)
            };
            const status = { shownKeys: { type: "presenceList", label: "Shown keys", setting: "attached" }, goneKeys: { type: "presenceList", label: "Gone keys", setting: "attachedHidden" } };
            root.pageRow = Object.assign({}, original, {
                schema: schema,
                settings: { kept: "", hiding: "", alone: "", attached: "", attachedHidden: "" },
                settingChoices: { kept: [], hiding: [], alone: [], attached: [], attachedHidden: [] }, binds: [],
                status: PluginLogic.statusRows({ status: status, secrets: { service: "acme-unit", label: "Key" } }, { shownKeys: [] }).filter(row => row.key !== "goneKeys"),
                fieldRows: PluginLogic.fieldRows(schema, status)
            });
            const page = createTemporaryObject(pluginPageComponent, root);
            verify(page !== null);
            const drawn = () => descendants(page).filter(item => item instanceof SettingField).map(item => item.key);
            const headings = () => descendants(page).filter(item => item instanceof Section).map(item => item.title);
            tryVerify(() => drawn().indexOf("kept") !== -1);
            compare(drawn().filter(key => key === "hiding" || key === "alone"), [], "a hideEmpty field with nothing offered is not drawn");
            compare(headings().indexOf("Lone"), -1, "a group whose every field is hidden draws no heading");
            verify(drawn().indexOf("attached") !== -1, "a hideEmpty field keeps its place while a line beside it draws");
            verify(descendants(page).some(item => item instanceof StatusRow && item.visible && item.entry !== null && item.entry.key === "shownKeys"), "the key list beside it draws");
            compare(drawn().indexOf("attachedHidden"), -1, "a hideEmpty field whose key list left the manager row is not drawn");
            root.pageRow = Object.assign({}, root.pageRow, { settingChoices: { kept: [], hiding: [{ label: "One", value: "" }], alone: [{ label: "One", value: "" }] } });
            tryVerify(() => drawn().indexOf("hiding") !== -1 && drawn().indexOf("alone") !== -1);
            verify(headings().indexOf("Lone") !== -1, "an offer draws the field under its heading");
            releasePage(page, original);
        }

        // The withheld keys come from the core's judge over the published
        // values, as the manager row's do (PluginLogic.withheldFields).
        function test_a_shown_when_field_has_no_place_while_its_entry_reads_absent() {
            const original = root.pageRow;
            const status = { battery: { type: "presence", label: "Battery", hidden: true } };
            const schema = {
                kept: { type: "boolean", label: "Kept", group: "Alerts" },
                low: { type: "boolean", label: "Low battery", group: "Alerts", shownWhen: "battery" },
                charging: { type: "boolean", label: "While charging", group: "Battery", shownWhen: "battery" }
            };
            const manifest = { schema: schema, status: status };
            root.pageRow = Object.assign({}, original, {
                schema: schema,
                settings: { kept: true, low: true, charging: true },
                binds: [],
                withheldFields: PluginLogic.withheldFields(manifest, { battery: "absent" }),
                fieldRows: PluginLogic.fieldRows(schema, status)
            });
            const page = createTemporaryObject(pluginPageComponent, root);
            verify(page !== null);
            const drawn = () => descendants(page).filter(item => item instanceof SettingField).map(item => item.key);
            const headings = () => descendants(page).filter(item => item instanceof Section).map(item => item.title);
            tryVerify(() => drawn().indexOf("kept") !== -1);
            compare(drawn().filter(key => key === "low" || key === "charging"), [], "a field whose presence entry reads absent is not drawn");
            compare(headings().indexOf("Battery"), -1, "a group whose every field is withheld draws no heading");
            root.pageRow = Object.assign({}, root.pageRow, { withheldFields: PluginLogic.withheldFields(manifest, { battery: "present" }) });
            tryVerify(() => drawn().indexOf("low") !== -1 && drawn().indexOf("charging") !== -1);
            verify(headings().indexOf("Battery") !== -1, "a present entry draws its fields under their heading");
            // Off, the plugin has published nothing, so every field waits;
            // its page still has settings to offer once it is on.
            const waiting = { low: schema.low, charging: schema.charging };
            root.pageRow = Object.assign({}, root.pageRow, {
                enabled: false,
                schema: waiting,
                settings: { low: true, charging: true },
                withheldFields: PluginLogic.withheldFields({ schema: waiting, status: status }, {}),
                fieldRows: PluginLogic.fieldRows(waiting, status)
            });
            tryVerify(() => drawn().length === 0);
            verify(!page.bare, "a plugin whose fields only wait is not bare");
            const enabled = descendants(page).find(item => item instanceof Field && item.label === SettingValues.PAGE_LABELS.enabled);
            verify(enabled !== undefined && enabled.hint !== "", "the Enabled switch keeps its Turn on hint");
            releasePage(page, original);
        }

        function test_enter_writes_the_field_it_is_pressed_in() {
            editor(gap).forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            compare(root.writes, [], "Enter in an untouched field writes nothing");
            compare(saved.count, 0);
            type(size, "20");
            type(gap, "73");
            keyClick(Qt.Key_Return);
            compare(root.writes, [["gap", 73]]);
            verify(!gap.edited && size.edited, "the other field keeps its edit");
            compare(saved.count, 0, "the set still holds an edit");
            type(size, "20");
            keyClick(Qt.Key_Return);
            compare(root.writes, [["gap", 73], ["size", 20]]);
            compare(saved.count, 1, "the write of the last edit is a save");
            verify(!unsaved.edited);
        }

        // The typed text names the value the configuration already holds, so
        // no change of that value redraws the field.
        function test_an_accepted_text_draws_what_the_configuration_holds() {
            gap.value = 12;
            const input = type(gap, "012");
            verify(gap.edited);
            keyClick(Qt.Key_Return);
            compare(root.writes, [["gap", 12]]);
            compare(input.text, "12");
            verify(!gap.edited);
        }

        function test_a_refused_text_stays_in_its_field() {
            root.accepts = false;
            const input = type(gap, "73");
            compare(unsaved.save(), false);
            compare(root.writes, [["gap", 73]]);
            compare(input.text, "73");
            verify(gap.edited && unsaved.edited, "the edit stays");
            compare(saved.count, 0);
        }

        function test_the_set_saves_and_discards_every_field() {
            const first = type(gap, "73"), second = type(size, "20");
            compare(unsaved.save(), true);
            compare(root.writes, [["gap", 73], ["size", 20]]);
            compare(saved.count, 1);
            type(gap, "5");
            type(size, "6");
            unsaved.discard();
            compare([first.text, second.text], ["73", "20"]);
            verify(!unsaved.edited);
            compare(root.writes.length, 2);
            compare(saved.count, 1, "a discard is no save");
        }

        function test_a_read_only_field_holds_no_edit() {
            const input = type(gap, "73");
            elsewhere.forceActiveFocus(Qt.TabFocusReason);
            gap.editable = false;
            compare(input.text, "4");
            verify(!unsaved.edited);
        }

        function test_the_custom_editor_keeps_a_text_its_check_refuses() {
            const input = type(clock, "'abc");
            keyClick(Qt.Key_Return);
            compare(root.writes, []);
            verify(clock.edited, "the refused format stays an edit");
            type(clock, "HH");
            keyClick(Qt.Key_Return);
            compare(root.writes, [["clock", "HH"]]);
            verify(!clock.edited);
            compare(input.text, "HH");
        }

        function test_a_hidden_custom_row_holds_no_edit() {
            clock.value = "HH:mm";
            clock.customChosen = true;
            const input = type(clock, "ss");
            verify(clock.edited);
            clock.customChosen = false;
            verify(!clock.edited, "the row hid with its draft");
            compare(input.text, "HH:mm");
        }

        function test_a_destroyed_field_leaves_the_set() {
            const spare = disposable.createObject(root);
            verify(spare !== null);
            type(spare, "9");
            verify(unsaved.edited);
            spare.destroy();
            tryCompare(unsaved, "edited", false);
        }

        function test_a_typed_key_waits_and_a_refused_one_returns() {
            const field = keyRow.shortcutField;
            field.startTyping();
            for (const c of "SUPER+K") keyClick(c);
            verify(keyRow.edited && unsaved.edited, "the row joins the set");
            elsewhere.forceActiveFocus(Qt.TabFocusReason);
            compare(root.keys, []);
            root.accepts = false;
            compare(unsaved.save(), false);
            compare(root.keys, ["SUPER+K"]);
            verify(field.typing && keyRow.edited, "the refused key is back in the text entry");
            compare(editor(keyRow).text, "SUPER+K");
            root.accepts = true;
            compare(unsaved.save(), true);
            compare(root.keys, ["SUPER+K", "SUPER+K"]);
            verify(!field.typing, "the accepted key closes the entry");
            compare(saved.count, 1);
        }

        function test_enter_in_a_key_row_is_a_save_once_accepted() {
            const field = keyRow.shortcutField;
            root.accepts = false;
            field.startTyping();
            for (const c of "SUPER+K") keyClick(c);
            keyClick(Qt.Key_Return);
            compare(root.keys, ["SUPER+K"]);
            verify(keyRow.edited, "the refused key is back in the text entry");
            compare(saved.count, 0, "a refused key is no save");
            root.accepts = true;
            keyClick(Qt.Key_Return);
            compare(root.keys, ["SUPER+K", "SUPER+K"]);
            verify(!unsaved.edited);
            compare(saved.count, 1, "the accepted key is a save");
            root.accepts = false;
            field.startTyping();
            for (const c of "SUPER+J") keyClick(c);
            keyClick(Qt.Key_Return);
            compare(saved.count, 1, "a key refused after an accepted one is no save");
            keyRow.discard();
            field.startTyping();
            keyClick(Qt.Key_Backspace);
            keyClick(Qt.Key_Return);
            compare(root.keys, ["SUPER+K", "SUPER+K", "SUPER+J", null], "an emptied entry sends the unbind");
            verify(!unsaved.edited, "a refused unbind returns to no entry");
            compare(saved.count, 1, "and is no save");
        }

        function test_a_key_sent_without_the_text_entry_is_no_save() {
            keyRow.applyKey("SUPER+J");
            compare(root.keys, ["SUPER+J"]);
            compare(saved.count, 0);
        }

        function test_a_read_only_key_row_holds_no_edit() {
            keyRow.shortcutField.startTyping();
            for (const c of "SUPER+K") keyClick(c);
            verify(unsaved.edited);
            keyRow.editable = false;
            verify(!keyRow.shortcutField.typing && !unsaved.edited, "the entry closed with its key");
            compare(root.keys, []);
        }

        function test_a_destroyed_key_row_leaves_the_set() {
            const spare = disposableKey.createObject(root);
            verify(spare !== null);
            spare.shortcutField.startTyping();
            for (const c of "SUPER+J") keyClick(c);
            verify(unsaved.edited);
            spare.destroy();
            tryCompare(unsaved, "edited", false);
        }

        function test_discard_drops_a_typed_key() {
            keyRow.shortcutField.startTyping();
            for (const c of "SUPER+K") keyClick(c);
            unsaved.discard();
            verify(!keyRow.shortcutField.typing && !unsaved.edited);
            compare(root.keys, []);
        }

        function test_reset_offers_every_default_key() {
            const field = createTemporaryObject(listDefaultKey, root);
            verify(field !== null);
            const reset = descendants(field).find(child => child.iconName === "rotate-ccw");
            verify(reset !== undefined, "the row draws its reset button");
            // [why, keys in effect, default, reset shown]
            for (const [why, keys, def, shown] of [
                ["one key of a default list", ["code:108"], ["code:108", "code:105"], true],
                ["every key of a default list", ["code:108", "code:105"], ["code:108", "code:105"], false],
                ["an unbound default list", [], ["code:108", "code:105"], true],
                ["a second key beside one default key", ["code:108", "code:105"], "code:108", true],
                ["the one default key", ["code:108"], "code:108", false],
                ["no default", ["code:108"], null, false]
            ]) {
                field.bind = { shortcut: "tap", key: keys.length === 0 ? null : keys[0], keys: keys, default: def, description: "Tap" };
                compare(reset.visible, shown, why);
            }
            field.bind = { shortcut: "tap", key: "code:108", keys: ["code:108"], default: ["code:108", "code:105"], description: "Tap" };
            reset.clicked();
            compare(root.keys, [undefined], "the reset sends undefined, so the default list applies");
        }

        function test_plugin_page_draws_one_row_per_shortcut() {
            fakePanel.keyWrites = [];
            pageCapture.userHoldsRightCtrl = false;
            const shipped = root.pageRow;
            const shownWith = keys => {
                const row = JSON.parse(JSON.stringify(shipped));
                row.binds[0].keys = keys;
                row.binds[0].key = keys.length === 0 ? null : keys[0];
                root.pageRow = row;
            };
            const page = pluginPageComponent.createObject(root);
            verify(page !== null);
            settle(() => keyFields(page).length === 1);
            compare(keyFields(page).length, 1, "one row for a shortcut with two keys");
            const field = () => keyFields(page)[0];
            compare(JSON.stringify(field().shortcutField.keys), JSON.stringify(["code:108", "code:105"]));
            const lastWrite = () => JSON.stringify(fakePanel.keyWrites[fakePanel.keyWrites.length - 1]);

            field().shortcutField.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Right);
            keyClick(Qt.Key_Delete);
            compare(lastWrite(), JSON.stringify(["acme.unit", "tap", "code:108"]), "removing one alternative writes the key left");

            shownWith(["code:108"]);
            settle(() => field().shortcutField.keys.length === 1);
            const add = descendants(field()).find(child => child.iconName === "plus");
            verify(add !== undefined && add.visible, "the row draws its add button");
            add.clicked();
            verify(field().shortcutField.capturing, "the add button listens for the new key");
            keyClick(Qt.Key_K, Qt.MetaModifier);
            compare(lastWrite(), JSON.stringify(["acme.unit", "tap", ["code:108", "SUPER+K"]]), "the new key joins the list");

            pageCapture.userHoldsRightCtrl = true;
            shownWith(["code:108", "code:105"]);
            settle(() => field().userHolds);
            const mine = descendants(field()).find(child => child.objectName === "useMyBinding");
            verify(mine !== undefined && mine.visible, "a user bind on one key offers Use my binding");
            mine.clicked();
            compare(lastWrite(), JSON.stringify(["acme.unit", "tap", "code:108"]), "Use my binding removes the key the user bind holds");
            pageCapture.userHoldsRightCtrl = false;

            shownWith(["code:108", "SUPER+K"]);
            settle(() => field().shortcutField.keys[1] === "SUPER+K");
            const reset = descendants(field()).find(child => child.iconName === "rotate-ccw");
            verify(reset !== undefined && reset.visible, "keys other than the default offer the reset");
            const before = fakePanel.keyWrites.length;
            reset.clicked();
            compare(fakePanel.keyWrites.length, before + 1);
            compare(fakePanel.keyWrites[before][2], undefined, "the reset sends undefined, so the default list applies");
            releasePage(page, shipped);
        }

        // A refused key on the page returns to the row's text entry: a
        // one-key value a caller sends, as the window's key IPC does, and
        // a key the field's own edit set; a refused removal, which would
        // leave one key, and a refused list open none.
        function test_a_refused_key_returns_whatever_sent_it() {
            fakePanel.keyWrites = [];
            const shipped = root.pageRow;
            const shownWith = keys => {
                const row = JSON.parse(JSON.stringify(shipped));
                row.binds[0].keys = keys;
                row.binds[0].key = keys.length === 0 ? null : keys[0];
                root.pageRow = row;
            };
            const page = pluginPageComponent.createObject(root);
            verify(page !== null);
            shownWith(["code:108", "code:105"]);
            settle(() => keyFields(page).length === 1 && keyFields(page)[0].shortcutField.keys.length === 2);
            const field = keyFields(page)[0];
            fakePanel.refusesKeys = true;
            // [why, send, the text entry opens on]
            for (const [why, send, want] of [
                ["a one-key value a caller sends", () => field.applyKey("SUPER+"), "SUPER+"],
                ["a key the field's edit sets", () => field.shortcutField.committed("SUPER+J", 0), "SUPER+J"],
                ["a refused removal", () => field.shortcutField.cleared(0), null],
                ["a list a caller sends", () => field.applyKey(["code:108", "SUPER+"]), null]
            ]) {
                field.discard();
                send();
                compare(field.shortcutField.typing, want !== null, why);
                if (want !== null) compare(editor(field).text, want, why);
            }
            field.discard();
            fakePanel.refusesKeys = false;
            releasePage(page, shipped);
        }
    }
}
