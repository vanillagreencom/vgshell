import QtQuick
import QtTest
import qs.Commons
import qs.Core
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.settings"

// A `rows` status entry on the actual Settings window: PluginLogic makes
// the manager rows from the acme.rows fixture's entry, and the page draws
// the list full width under its label on the tab the manifest names, one
// ListItem per published row. A row takes no click: no hover fill, no
// press and no pointing hand. Its state reads as plain text while calm and
// as a chip while it needs the user, and its Remove draws the trash mark
// alone, its text naming the row as its tooltip and accessible name, with
// its own hover, hand, keyboard focus and click, which hands the manager
// the entry, the row's id and the row action. Add stands under the list
// and acts on the entry alone. The reply of the list's last press reads
// under it. While the plugin is off the list says so, and on Details it
// offers Turn on.
// The window's capabilities record each act.
Item {
    id: root
    width: 1200
    height: 1200
    readonly property var screen: ({ name: "DP-1", x: 0, y: 0, width: 1920, height: 1080 })
    // acme.rows's status entry, on Settings as it ships, and as a list of
    // facts on Details.
    readonly property var pairsEntry: ({ type: "rows", label: "Folder pairs", settings: true, icon: "folder-sync",
        hint: "Each pair keeps one Google Drive folder and one folder on this computer the same",
        action: { label: "Add a folder pair", tui: "add" },
        rowActions: { remove: { label: "Remove", tui: "remove", tone: "danger" } } })
    readonly property var factsEntry: ({ type: "rows", label: "Folder pairs", icon: "folder-sync" })
    // acme.rows's entry with its actions, placed on Details.
    readonly property var detailsEntry: ({ type: "rows", label: "Folder pairs", icon: "folder-sync",
        action: { label: "Add a folder pair", tui: "add" }, rowActions: { remove: { label: "Remove", tui: "remove", tone: "danger" } } })
    readonly property var pairs: [
        { id: "documents", label: "Documents", secondary: "Drive/Documents ⇄ ~/Drive/Documents", state: { tone: "warning", text: "1 to review" }, actions: ["remove"] },
        { id: "uploads", label: "Agent uploads", secondary: "Drive/VGS/Uploads ⇄ ~/agents/uploads", state: { tone: "ok", text: "Up to date" }, actions: ["remove"] },
        { id: "taxes", label: "Taxes", secondary: "Drive/Finance/Taxes ⇄ ~/Documents/Taxes", state: { tone: "ok", text: "Up to date" }, actions: ["remove"] }
    ]
    // The manager row of plugin ID over its status ENTRY, which publishes
    // VALUES, with FIELDS over them.
    function pluginRow(id, entry, values, fields) {
        const manifest = { requirements: [], tui: { add: { requires: [] }, remove: { requires: [] } }, status: { pairs: entry } };
        const row = Object.assign({ id: id, name: id, version: "1", description: "", author: "VGS", license: "", icon: "package", source: "bundled",
            enabled: true, alwaysOn: false, placed: false, kinds: ["service"], capabilities: [], schema: {}, settings: {}, settingChoices: {},
            status: PluginLogic.statusRows(manifest, values), secretLabel: "", readme: "", guide: null, tuis: [], builtins: [], opens: "", paneHolder: "", binds: [],
            requirements: [], errors: [] }, fields);
        row.fieldRows = PluginLogic.fieldRows(row.schema, manifest.status);
        return row;
    }
    function rows() {
        return [
            pluginRow("acme.rows", pairsEntry, { pairs: pairs }, {}),
            pluginRow("acme.empty", pairsEntry, { pairs: [] }, {}),
            pluginRow("acme.waiting", pairsEntry, {}, {}),
            pluginRow("acme.off", pairsEntry, {}, { enabled: false }),
            pluginRow("acme.detailsoff", detailsEntry, {}, { enabled: false }),
            pluginRow("acme.facts", factsEntry, { pairs: pairs.map(pair => ({ id: pair.id, label: pair.label, secondary: pair.secondary })) }, {})
        ];
    }
    QtObject {
        id: fakeManager
        property var plugins: root.rows()
        property var acts: []
        property var enables: []
        property string actionReply: "ok"
        function rescan() { return "ok"; }
        function viewPage(id) {}
        function setEnabled(id, enabled) { enables = enables.concat([[id, enabled]]); return "ok"; }
        function act(id, key, row, rowAction) { acts = acts.concat([[id, key, row, rowAction]]); return actionReply; }
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
        name: "settingsRows"
        when: windowShown
        function descendants(item) {
            const found = [item];
            for (let i = 0; i < found.length; i++) for (const child of found[i].children || []) found.push(child);
            return found;
        }
        function init() { fakeManager.plugins = root.rows(); fakeManager.acts = []; fakeManager.enables = []; fakeManager.actionReply = "ok"; }
        // The theme loads with the first window; a test that stilled motion
        // puts it back.
        function cleanup() { if (UnitTheme.source !== null) UnitTheme.reset(); }
        function opened(id, tab) {
            const window = createTemporaryObject(windowComponent, root);
            verify(window !== null, "the window builds");
            window.width = window.implicitWidth; window.height = 900; window.open("{}"); waitForRendering(window);
            window.openPlugin(id, Qt.OtherFocusReason, tab);
            tryVerify(() => pageOf(window).parent.x === -window.width, 2000, "the page has slid in");
            waitForRendering(window);
            return window;
        }
        function pageOf(window) { return descendants(window).find(item => item.fitHeight !== undefined && item.row !== undefined); }
        function tabsOf(window) { return descendants(pageOf(window)).find(item => item instanceof TabPages); }
        function onTab(window, type) { return descendants(tabsOf(window).currentPage).filter(item => item instanceof type && item.visible); }
        function listOf(window) { return onTab(window, RowsList)[0]; }
        function lines(window) { return descendants(listOf(window)).filter(item => item instanceof ListItem && item.visible); }
        function actionsOf(line) { return descendants(line).filter(item => item instanceof RowAction && item.visible); }
        function addOf(window) { return descendants(listOf(window)).find(item => item instanceof RowAction && item.visible && item.text === "Add a folder pair"); }
        // Qt takes the cursor over an item from a handler of the item that
        // sets a cursor shape and is hovered; with none, the arrow shows.
        function showsHand(item, x) {
            mouseMove(item, x === undefined ? item.width / 2 : x, item.height / 2);
            return item.data.some(child => child instanceof HoverHandler && child.cursorShape === Qt.PointingHandCursor && child.hovered);
        }

        function test_settings_draws_one_row_per_published_row() {
            const window = opened("acme.rows", "Settings");
            compare(pageOf(window).tab, "Settings");
            compare(onTab(window, RowsList).length, 1, "the list stands on the tab its manifest names");
            compare(listOf(window).title, "Folder pairs");
            const drawn = lines(window);
            compare(drawn.map(line => [line.text, line.secondary, line.iconName, line.clickable]), root.pairs.map(pair => [pair.label, pair.secondary, "folder-sync", false]));
            compare(drawn.map(line => line.width), drawn.map(() => listOf(window).width), "each row is as wide as the list");
            // A state that needs the user is a chip; a calm one plain text.
            const chips = drawn.map(line => descendants(line).filter(item => item instanceof Badge && item.visible).map(chip => [chip.text, chip.tone]));
            compare(chips, [[["1 to review", "warning"]], [], []]);
            const plain = drawn.map(line => descendants(line).filter(item => item instanceof Label && item.visible && item.text === "Up to date").length);
            compare(plain, [0, 1, 1]);
            // Each Remove is the trash mark alone, named for its row.
            compare(drawn.map(line => actionsOf(line).map(action => [action.text, action.removesItem, action.Accessible.name])),
                root.pairs.map(pair => [["Remove " + pair.label, true, "Remove " + pair.label]]));
            verify(addOf(window) !== undefined, "Add stands under the list");
            // The trash ink, not its square, ends on the list's edge.
            const inkEnds = drawn.map(line => {
                const mark = descendants(actionsOf(line)[0]).find(item => item instanceof Icon && item.visible);
                return Math.round(mark.mapToItem(listOf(window), mark.painted[2], 0).x);
            });
            compare(inkEnds, drawn.map(() => Math.round(listOf(window).width)), "each trash mark's ink ends on the list's edge");
            verify(addOf(window).mapToItem(null, 0, 0).y > drawn[drawn.length - 1].mapToItem(null, 0, drawn[drawn.length - 1].height).y, "Add is under the last row");
            compare(onTab(window, LinkText).map(text => text.text).filter(text => text === root.pairsEntry.hint).length, 1, "the hint reads under the list");
        }

        function test_a_rows_remove_hands_the_manager_its_row_and_add_the_entry() {
            const window = opened("acme.rows", "Settings");
            const remove = actionsOf(lines(window)[1])[0];
            mouseClick(remove);
            compare(fakeManager.acts, [["acme.rows", "pairs", "uploads", "remove"]], "Remove acts on its own row");
            mouseClick(addOf(window));
            compare(fakeManager.acts[1], ["acme.rows", "pairs", undefined, undefined], "Add acts on the entry");
        }

        function test_a_row_takes_no_hover_and_its_action_keeps_its_own() {
            const window = opened("acme.rows", "Settings");
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            const line = lines(window)[0];
            const at = line.textStart + 1;
            mouseMove(line, at, line.height / 2);
            tryCompare(line, "hovered", true);
            compare(String(line.background.color), "#00000000", "a row draws no hover");
            compare(showsHand(line, at), false, "a row shows no hand");
            mousePress(line, at, line.height / 2);
            compare(line.down, false, "a row draws no press");
            mouseRelease(line, at, line.height / 2);
            compare(fakeManager.acts, [], "a press on a row runs nothing");
            const remove = actionsOf(line)[0];
            verify(showsHand(remove), "Remove shows the hand");
            tryCompare(remove, "hovered", true);
            remove.forceActiveFocus(Qt.TabFocusReason);
            compare(remove.activeFocus, true, "Remove takes keyboard focus");
            keyClick(Qt.Key_Space);
            compare(fakeManager.acts, [["acme.rows", "pairs", "documents", "remove"]], "Space runs Remove on its row");
        }

        // The list reads the reply of its last press: a row whose row
        // changed reads the row's words, never an older refusal of Add,
        // and a later press that opens its window clears it.
        function test_the_list_reads_the_reply_of_its_last_press() {
            const window = opened("acme.rows", "Settings");
            const shown = () => descendants(listOf(window)).filter(item => item instanceof Label && item.visible && item.color === Qt.color(Theme.color.danger)).map(label => label.text);
            fakeManager.actionReply = "refused: tui=add reason=launcher-missing";
            ignoreWarning("settings: acme.rows/pairs " + fakeManager.actionReply);
            mouseClick(addOf(window));
            tryCompare(listOf(window), "reply", Reply.line(fakeManager.actionReply));
            fakeManager.actionReply = "refused: action=pairs reason=row-changed";
            const changed = Reply.line(fakeManager.actionReply);
            verify(changed !== Reply.line("refused: action=pairs reason=not-offered"), "a changed row reads its own words, not a setup step's");
            ignoreWarning("settings: acme.rows/pairs/taxes " + fakeManager.actionReply);
            mouseClick(actionsOf(lines(window)[2])[0]);
            tryCompare(listOf(window), "reply", changed);
            compare(shown(), [changed], "the row's words read alone, in the error colour");
            fakeManager.actionReply = "ok";
            mouseClick(actionsOf(lines(window)[1])[0]);
            tryCompare(listOf(window), "reply", "");
            compare(shown(), [], "an opened window leaves no refusal");
        }

        function test_an_empty_unreported_or_off_list_says_so_data() {
            // On Settings the Enabled switch is the one Turn on of a plugin
            // that is off; a Details list offers its own.
            return [{ tag: "empty", id: "acme.empty", tab: "Settings", text: "None yet", action: "Add a folder pair" },
                { tag: "unreported", id: "acme.waiting", tab: "Settings", text: "Not reported", action: "" },
                { tag: "off on Settings", id: "acme.off", tab: "Settings", text: "acme.off is off", action: "" },
                { tag: "off on Details", id: "acme.detailsoff", tab: "Details", text: "acme.detailsoff is off", action: "Turn on acme.detailsoff" }];
        }
        function test_an_empty_unreported_or_off_list_says_so(data) {
            const window = opened(data.id, data.tab);
            compare(pageOf(window).tab, data.tab);
            compare(lines(window).length, 0);
            verify(descendants(listOf(window)).some(item => item instanceof Label && item.visible && item.text === data.text), "the list reads " + data.text);
            const under = descendants(listOf(window)).filter(item => item instanceof RowAction && item.visible).map(action => action.text);
            compare(under, data.action === "" ? [] : [data.action]);
            if (data.action.indexOf("Turn on") !== 0) return;
            mouseClick(descendants(listOf(window)).find(item => item instanceof RowAction && item.visible));
            compare(fakeManager.enables, [[data.id, true]], "Turn on turns the plugin on");
        }

        function test_a_list_of_facts_stands_on_details() {
            const window = opened("acme.facts", "Settings");
            compare(onTab(window, RowsList).length, 0, "Settings draws no list the user cannot change");
            tabsOf(window).currentIndex = tabsOf(window).model.indexOf("Details");
            waitForRendering(window);
            compare(onTab(window, RowsList).length, 1);
            compare(lines(window).map(line => [line.text, line.clickable, actionsOf(line).length]), root.pairs.map(pair => [pair.label, false, 0]));
        }
    }
}
