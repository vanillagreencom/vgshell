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
// ContentRow per published row, on the content edge. A declared folder
// makes its row clickable with the shared hover and keyboard-focus plate.
// Other rows stay passive and take no plate. Under the name stand the
// state, with its tone's mark, the secondary line and a small button per
// row action, `space.md` apart ink to ink, inside `listItem.paddingX` of
// box above and below; a row without a state or a secondary line leaves
// no room for it. Remove stands in the row's menu, named for its row, and
// the dots' ink ends on the list's edge. Each button and menu entry hands
// the manager the entry, the row's id and the row action, and opens no
// folder. Add stands under the list and acts on the entry alone. The reply
// of the list's last press reads under it. While the plugin is off the
// list says so, and on Details it offers Turn on.
// The window's capabilities record each act.
Item {
    id: root
    width: 1200
    height: 1200
    readonly property var screen: ({ name: "DP-1", x: 0, y: 0, width: 1920, height: 1080 })
    // acme.rows's status entry, on Settings as it ships, and as a list of
    // facts on Details.
    readonly property var pairsEntry: ({ type: "rows", label: "Folder pairs", settings: true, icon: "folder-sync", folderProperty: "local",
        hint: "Each pair keeps one Google Drive folder and one folder on this computer the same",
        action: { label: "Add a folder pair", tui: "add" },
        rowActions: { initialize: { label: "Set up two-way sync", tui: "initialize" }, remove: { label: "Remove", tui: "remove", tone: "danger" } } })
    // acme.muted's entry: rows with a name and one action that removes nothing.
    readonly property var mutedEntry: ({ type: "rows", label: "Muted programs", settings: true, icon: "bell-off", hint: "You get no crash notifications for these programs",
        rowActions: { unmute: { label: "Unmute", tui: "unmute" } } })
    readonly property var factsEntry: ({ type: "rows", label: "Folder pairs", icon: "folder-sync" })
    // acme.rows's entry with its actions, placed on Details.
    readonly property var detailsEntry: ({ type: "rows", label: "Folder pairs", icon: "folder-sync",
        action: { label: "Add a folder pair", tui: "add" }, rowActions: { remove: { label: "Remove", tui: "remove", tone: "danger" } } })
    readonly property var pairs: [
        { id: "documents", label: "Documents", local: "/home/me/Drive/My docs (1)", secondary: "Drive/Documents ⇄ ~/Drive/Documents", state: { tone: "warning", text: "1 to review" }, actions: ["initialize", "remove"] },
        { id: "uploads", label: "Agent uploads", local: "/srv/uploads", secondary: "Drive/VGS/Uploads ⇄ ~/agents/uploads", state: { tone: "ok", text: "Up to date" }, actions: ["remove"] },
        { id: "taxes", label: "Taxes", secondary: "Drive/Finance/Taxes ⇄ ~/Documents/Taxes", state: { tone: "ok", text: "Up to date" }, actions: ["remove"] }
    ]
    // The manager row of plugin ID over its status ENTRY, which publishes
    // VALUES, with FIELDS over them.
    function pluginRow(id, entry, values, fields) {
        const manifest = { requirements: [], tui: { add: { requires: [] }, initialize: { requires: [] }, remove: { requires: [] }, unmute: { requires: [] } }, status: { pairs: entry } };
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
            pluginRow("acme.muted", mutedEntry, { pairs: [{ id: "crashy", label: "crashy", actions: ["unmute"] }] }, {}),
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
        property var installFailures: ({})
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
        id: fakeTui
        property var opens: []
        function edit(path) { opens = opens.concat([path]); return "ok"; }
    }
    QtObject {
        id: fakeShell
        readonly property var manager: fakeManager
        readonly property var compositor: fakeCompositor
        readonly property var manifest: ({ id: "vgs.settings", name: "Plugins" })
        readonly property var screens: ({ current: root.screen, all: [root.screen] })
        readonly property var shortcut: ({ capture: null })
        readonly property var tui: fakeTui
    }
    Component { id: windowComponent; Window { shell: fakeShell } }
    // A plain row of the same name and mark, for where a passive stacked
    // row draws its name's line.
    Component { id: plainRowComponent; ContentRow { width: 300; text: "crashy"; iconName: "bell-off" } }
    UnitCase {
        name: "settingsRows"
        when: windowShown
        function descendants(item) {
            const found = [item];
            for (let i = 0; i < found.length; i++) for (const child of found[i].children || []) found.push(child);
            return found;
        }
        function init() { fakeManager.plugins = root.rows(); fakeManager.acts = []; fakeManager.enables = []; fakeManager.actionReply = "ok"; fakeTui.opens = []; }
        // The theme loads with the first window; a test that stilled motion
        // puts it back.
        function cleanup() { if (UnitTheme.source !== null) UnitTheme.reset(); }
        function opened(id, tab) {
            const window = createTemporaryObject(windowComponent, root);
            verify(window !== null, "the window builds");
            window.width = window.implicitWidth; window.height = 900; window.open("{}"); renderedFrame(window);
            window.openPlugin(id, Qt.OtherFocusReason, tab);
            tryVerify(() => pageOf(window).parent.x === -window.width, 2000, "the page has slid in");
            renderedFrame(window);
            return window;
        }
        function pageOf(window) { return descendants(window).find(item => item.fitHeight !== undefined && item.row !== undefined); }
        function tabsOf(window) { return descendants(pageOf(window)).find(item => item instanceof TabPages); }
        function onTab(window, type) { return descendants(tabsOf(window).currentPage).filter(item => item instanceof type && item.visible); }
        function listOf(window) { return onTab(window, RowsList)[0]; }
        function lines(window) { return descendants(listOf(window)).filter(item => item instanceof ContentRow && item.visible); }
        function actionsOf(line) { return descendants(line).filter(item => item instanceof Button && !(item instanceof IconButton) && item.visible); }
        function moreOf(line) { return descendants(line).find(item => item instanceof IconButton && item.visible); }
        function menuOf(line) { return descendants(line).find(item => item instanceof Menu); }
        function menuTexts(line) { return menuOf(line).items().map(entry => [entry.text, entry.iconName]); }
        // Where a line's drawn ink starts and ends, in the row's frame.
        function inkTop(line, item) { return item.mapToItem(line, 0, 0).y + Theme.inkAbove(item); }
        function inkBottom(line, item) { return item.mapToItem(line, 0, item.height).y - Theme.inkBelow(item); }
        function labelOf(line, text) { return descendants(line).find(item => item instanceof Label && item.visible && item.text === text); }
        function addOf(window) { return descendants(listOf(window)).find(item => item instanceof Button && item.visible && item.text === "Add a folder pair"); }
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
            compare(drawn.map(line => [line.text, line.detail, line.secondary, line.iconName, line.clickable]), root.pairs.map(pair => [pair.label, pair.secondary, "", "folder-sync", pair.local !== undefined]));
            compare(drawn.map(line => line.width), drawn.map(() => listOf(window).width), "each row is as wide as the list");
            compare(drawn.map(line => line.mapToItem(listOf(window), 0, 0).x), drawn.map(() => 0), "each row stands on the content edge");
            compare(drawn.map(line => line.leftPadding), drawn.map(() => 0), "a row insets no text");
            // The state reads under the name with its tone's mark; a calm
            // one in the hint colour, one that needs the user in its tone.
            compare(drawn.map(line => [line.status, line.statusTone]), [["1 to review", "warning"], ["Up to date", "success"], ["Up to date", "success"]]);
            compare(descendants(listOf(window)).filter(item => item instanceof Badge && item.visible).length, 0, "no state is a chip");
            verify(Qt.colorEqual(labelOf(drawn[0], "1 to review").color, Theme.color.warning), "a state that needs the user reads in its tone");
            verify(Qt.colorEqual(labelOf(drawn[1], "Up to date").color, Theme.text.itemHint.color), "a calm state reads in the hint colour");
            // A needed step is a small secondary button; Remove stands in the
            // row's menu, named Remove alone, led by the trash mark.
            compare(drawn.map(line => actionsOf(line).map(action => [action.text, action.size, action.variant])), [[["Set up two-way sync", "sm", "secondary"]], [], []]);
            compare(drawn.map(line => menuTexts(line)), root.pairs.map(pair => [["Remove", "trash"]]));
            compare(drawn.map(line => moreOf(line).label), root.pairs.map(pair => "More actions for " + pair.label));
            verify(addOf(window) !== undefined, "Add stands under the list");
            compare(addOf(window).variant, "secondary");
            // The dots' ink, not their square, ends on the list's edge.
            compare(drawn.map(line => Math.round(moreOf(line).mapToItem(listOf(window), moreOf(line).width - moreOf(line).glyphEnd, 0).x)),
                drawn.map(() => Math.round(listOf(window).width)), "each menu's dots end on the list's edge");
            const last = drawn[drawn.length - 1];
            const groups = descendants(listOf(window)).find(item => item instanceof GroupList);
            verify(Number.isInteger(groups.height) && Number.isInteger(groups.implicitHeight), "the list keeps a whole-pixel height: " + groups.height);
            compare(addOf(window).mapToItem(null, 0, 0).y - (last.mapToItem(null, 0, last.height).y - Math.floor(last.drawnInkBelow)), Theme.stack.heading, "Add stands stack.heading below the list's last drawn ink, floored");
            compare(onTab(window, LinkText).map(text => text.text).filter(text => text === root.pairsEntry.hint).length, 1, "the hint reads under the list");
        }

        // Name, state, folders and button stand one ink gap apart, and the
        // row's box holds its padding above the first ink and below the last.
        function test_a_rows_lines_stand_one_ink_gap_apart() {
            const window = opened("acme.rows", "Settings");
            const line = lines(window)[0];
            const name = labelOf(line, "Documents");
            // The name's line inks to its folder icon's painted shape too.
            const icon = descendants(line).find(item => item instanceof Icon && item.visible && item.name === "folder-sync");
            const iconTop = icon.mapToItem(line, 0, 0).y;
            const headTop = Math.min(inkTop(line, name), iconTop + icon.painted[1]);
            const headBottom = Math.max(inkBottom(line, name), iconTop + icon.painted[3]);
            const state = labelOf(line, "1 to review").parent;
            const folders = labelOf(line, root.pairs[0].secondary);
            const button = actionsOf(line)[0];
            fuzzyCompare(inkTop(line, state) - headBottom, Theme.space.md, 0.5, "the state stands space.md under the name's line");
            const stacked = [state, folders, button];
            compare(stacked.map(item => item.mapToItem(line, 0, 0).x), stacked.map(() => line.textStart), "the stacked lines start under the name, indented no further");
            for (let i = 1; i < stacked.length; i++)
                fuzzyCompare(inkTop(line, stacked[i]) - inkBottom(line, stacked[i - 1]), Theme.space.md, 0.5, "line " + i + " stands space.md under the one above it");
            compare(Math.floor(headTop), Theme.listItem.paddingX, "the box holds its padding above the first ink");
            compare(Math.floor(line.height - inkBottom(line, button)), Theme.listItem.paddingX, "the box holds its padding below the last ink");
            // A calm row with no button ends its box under its folders.
            const calm = lines(window)[1];
            compare(Math.floor(calm.height - inkBottom(calm, labelOf(calm, root.pairs[1].secondary))), Theme.listItem.paddingX);
        }

        // A row with neither a state nor a secondary line puts its button
        // straight under its name, and a row with nothing to remove has no
        // menu. Without a folder it takes no plate.
        function test_a_row_without_state_or_secondary_leaves_no_room_for_them() {
            const window = opened("acme.muted", "Settings");
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            const line = lines(window)[0];
            compare([line.text, line.status, line.detail, line.clickable, line.cursor], ["crashy", "", "", false, null]);
            const unmute = actionsOf(line);
            compare(unmute.map(action => [action.text, action.size, action.variant]), [["Unmute", "sm", "secondary"]]);
            compare(moreOf(line), undefined, "Unmute removes nothing, so the row has no menu");
            const icon = descendants(line).find(item => item instanceof Icon && item.visible && item.name === "bell-off");
            const headBottom = Math.max(inkBottom(line, labelOf(line, "crashy")), icon.mapToItem(line, 0, 0).y + icon.painted[3]);
            fuzzyCompare(inkTop(line, unmute[0]) - headBottom, Theme.space.md, 0.5, "the button stands space.md under the name's line");
            // A heading over the passive list measures from the row's drawn ink:
            // the higher of the name's and the icon's painted shape.
            const headTop = Math.min(inkTop(line, labelOf(line, "crashy")), icon.mapToItem(line, 0, 0).y + icon.painted[1]);
            fuzzyCompare(Theme.inkAbove(line), headTop, 0.01, "the row reads its first ink as its drawn ink");
            // A passive row draws its name's line where a plain row does, so
            // its heading keeps the gap it keeps over plain rows, and its last
            // ink stands 2 * listItem.paddingX less that offset above its bottom.
            const plain = createTemporaryObject(plainRowComponent, root);
            const plainIcon = descendants(plain).find(item => item instanceof Icon && item.visible && item.name === "bell-off");
            compare([icon.mapToItem(line, 0, 0).y, labelOf(line, "crashy").mapToItem(line, 0, 0).y],
                [plainIcon.mapToItem(plain, 0, 0).y, labelOf(plain, "crashy").mapToItem(plain, 0, 0).y], "the name's line stands where a plain row's does");
            fuzzyCompare(line.height - inkBottom(line, unmute[0]), 2 * Theme.listItem.paddingX - headTop, 0.5, "the last ink keeps the rows' ink spacing");
            const plate = descendants(listOf(window)).find(item => item instanceof ListCursor);
            mouseMove(line, line.textStart + 1, 4);
            tryCompare(line, "hovered", true);
            compare(plate.shown, false, "a passive row takes no plate");
            // With no action under the list, its hint stands stack.heading
            // below the last row's drawn ink.
            const hint = onTab(window, LinkText).find(text => text.text === root.mutedEntry.hint);
            fuzzyCompare(hint.mapToItem(null, 0, 0).y - (line.mapToItem(null, 0, line.height).y - line.drawnInkBelow), Theme.stack.heading, 1, "the hint stands stack.heading below the list's last drawn ink");
            verify(Number.isInteger(descendants(listOf(window)).find(item => item instanceof GroupList).height), "the passive list keeps a whole-pixel height");
            mouseClick(unmute[0]);
            compare(fakeManager.acts, [["acme.muted", "pairs", "crashy", "unmute"]]);
        }

        // A status write hands the page new row objects with the same keys,
        // here with new words for both row actions: each button and menu
        // entry stays, with the focus it holds, and reads the new words.
        function test_a_status_write_keeps_a_rows_button_and_its_focus() {
            const window = opened("acme.rows", "Settings");
            const setUp = actionsOf(lines(window)[0])[0];
            const entry = menuOf(lines(window)[1]).items()[0];
            setUp.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(setUp, "activeFocus", true);
            const renamed = Object.assign({}, root.pairsEntry, { rowActions: { initialize: { label: "Set up two-way sync now", tui: "initialize" }, remove: { label: "Stop", tui: "remove", tone: "danger" } } });
            fakeManager.plugins = [root.pluginRow("acme.rows", renamed, { pairs: root.pairs }, {})].concat(root.rows().slice(1));
            renderedFrame(window);
            compare(actionsOf(lines(window)[0]).map(action => action.text), ["Set up two-way sync now"], "the write reaches the row");
            verify(actionsOf(lines(window)[0])[0] === setUp, "the write keeps the button");
            compare(setUp.activeFocus, true, "the button keeps keyboard focus");
            verify(menuOf(lines(window)[1]).items()[0] === entry, "the write keeps the menu entry");
            compare(entry.text, "Stop");
        }

        function test_a_rows_remove_hands_the_manager_its_row_and_add_the_entry() {
            const window = opened("acme.rows", "Settings");
            const line = lines(window)[1];
            mouseClick(moreOf(line));
            tryCompare(menuOf(line), "opened", true);
            menuOf(line).items()[0].triggered();
            menuOf(line).close();
            compare(fakeManager.acts, [["acme.rows", "pairs", "uploads", "remove"]], "Remove acts on its own row");
            compare(fakeTui.opens, [], "Remove never opens the folder");
            const setUp = actionsOf(lines(window)[0])[0];
            mouseClick(setUp);
            compare(fakeManager.acts[1], ["acme.rows", "pairs", "documents", "initialize"], "a row's button acts on its own row");
            compare(fakeTui.opens, [], "a row's button never opens the folder");
            setUp.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            compare(fakeTui.opens, [], "a keyboard press on a row's button never opens the folder");
            compare(fakeManager.acts[2], ["acme.rows", "pairs", "documents", "initialize"]);
            mouseClick(addOf(window));
            compare(fakeManager.acts[3], ["acme.rows", "pairs", undefined, undefined], "Add acts on the entry");
        }

        function test_a_row_takes_no_hover_and_its_action_keeps_its_own() {
            const window = opened("acme.rows", "Settings");
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            const line = lines(window)[2];
            const at = line.textStart + 1;
            mouseMove(line, at, line.height / 2);
            tryCompare(line, "hovered", true);
            compare(String(line.background.color), "#00000000", "a row draws no hover");
            compare(line.cursor, null, "a row with no folder takes no plate");
            compare(showsHand(line, at), false, "a row shows no hand");
            mousePress(line, at, line.height / 2);
            compare(line.down, false, "a row draws no press");
            mouseRelease(line, at, line.height / 2);
            compare(fakeManager.acts, [], "a press on a row runs nothing");
            const more = moreOf(line);
            verify(showsHand(more, more.width / 2), "the menu button shows the hand");
            more.forceActiveFocus(Qt.TabFocusReason);
            compare(more.activeFocus, true, "the menu button takes keyboard focus");
            keyClick(Qt.Key_Space);
            tryCompare(menuOf(line), "opened", true);
            compare(menuOf(line).currentIndex, 0, "a key opening highlights Remove");
            menuOf(line).items()[0].triggered();
            menuOf(line).close();
            compare(fakeManager.acts, [["acme.rows", "pairs", "taxes", "remove"]], "the menu runs Remove on its row");
            compare(fakeTui.opens, []);
        }

        function test_folder_row_activation_data() {
            return [{ tag: "click", key: 0 }, { tag: "Return", key: Qt.Key_Return }, { tag: "Enter", key: Qt.Key_Enter }];
        }
        function test_folder_row_activation(data) {
            const window = opened("acme.rows", "Settings");
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            const line = lines(window)[0];
            if (data.key === 0) {
                verify(showsHand(line, line.textStart + 1));
                mouseMove(line, line.textStart + 3, line.height / 2);
                tryCompare(line.cursor, "placed", line);
                compare(line.cursor.background.color, Theme.listItem.selected);
                compare([line.cursor.x, line.cursor.width, line.cursor.height], [line.x, line.width, line.height], "the plate holds the whole row, from the content edge");
                verify(Qt.colorEqual(labelOf(line, "1 to review").color, Theme.listItem.selectedForeground), "on the plate the state reads in the plate's ink");
                mouseClick(line, line.textStart + 1, line.height / 2);
            } else {
                mouseMove(window, 1, 1);
                // The fake editor opens no window. Give keyboard entry its
                // own focus transition, not the preceding click's focus.
                window.forceActiveFocus(Qt.OtherFocusReason);
                line.forceActiveFocus(Qt.TabFocusReason);
                tryCompare(line, "visualFocus", true);
                tryCompare(line.cursor, "target", line);
                compare(line.cursor.shown, true);
                compare(line.cursor.background.color, Theme.listItem.selected, "focus uses the same standard plate as hover");
                keyClick(data.key);
            }
            compare(fakeTui.opens, ["/home/me/Drive/My docs (1)/"]);
            compare(fakeManager.acts, [], "opening is not a Remove or Add action");
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
            menuOf(lines(window)[2]).items()[0].triggered();
            tryCompare(listOf(window), "reply", changed);
            compare(shown(), [changed], "the row's words read alone, in the error colour");
            fakeManager.actionReply = "ok";
            menuOf(lines(window)[1]).items()[0].triggered();
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
            const under = descendants(listOf(window)).filter(item => item instanceof Button && item.visible).map(action => action.text);
            compare(under, data.action === "" ? [] : [data.action]);
            if (data.action.indexOf("Turn on") !== 0) return;
            mouseClick(descendants(listOf(window)).find(item => item instanceof Button && item.visible));
            compare(fakeManager.enables, [[data.id, true]], "Turn on turns the plugin on");
        }

        function test_a_list_of_facts_stands_on_details() {
            const window = opened("acme.facts", "Settings");
            compare(onTab(window, RowsList).length, 0, "Settings draws no list the user cannot change");
            tabsOf(window).currentIndex = tabsOf(window).model.indexOf("Details");
            renderedFrame(window);
            compare(onTab(window, RowsList).length, 1);
            compare(lines(window).map(line => [line.text, line.detail, line.clickable, actionsOf(line).length, moreOf(line)]), root.pairs.map(pair => [pair.label, pair.secondary, false, 0, undefined]));
        }
    }
}
