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
// list, and the reset sends undefined. A plugin page draws one Keys row per
// shortcut, every alternative key in its one field: Delete on one writes
// the keys left, the add button and a pressed combo write the list with
// the new key, Use my binding removes the key a user bind holds, and the
// reset sends undefined. A refused key returns to the row's text entry
// whether the field or a caller sent it, and a refused removal or list
// opens none. The owner here stands in for the page: it records
// each write and takes it or refuses it; the page's capture names keys
// with the core's judge and says a user bind holds Right Ctrl when asked.
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
        kinds: ["service"],
        capabilities: ["shortcut"],
        schema: ({}),
        settings: ({}),
        settingChoices: ({}),
        status: [],
        secretLabel: "",
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
            row: root.pageRow
        }
    }

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
        function type(field, text) {
            const input = editor(field);
            input.forceActiveFocus(Qt.TabFocusReason);
            input.selectAll();
            for (const c of text) keyClick(c);
            return input;
        }

        function test_settings_key_boxes_keep_width_across_bound_unbound_and_reset_states() {
            const original = keyRow.bind;
            keyRow.capture = pageCapture;
            const box = () => descendants(keyRow).find(item => String(item).indexOf("QQuickAbstractButton") === 0);
            const expected = box().width;
            for (const key of [null, "SUPER+N", "SUPER+M"]) {
                keyRow.bind = Object.assign({}, original, { key: key });
                waitForItemPolished(box().parent);
                compare(box().width, expected);
            }
            keyRow.bind = original;
            keyRow.capture = null;
        }

        function test_settings_bind_explanation_uses_the_shared_label_tooltip() {
            const original = keyRow.bind;
            keyRow.bind = Object.assign({}, original, { info: "Open the window." });
            compare(UnitTheme.override({ tooltip: { delay: 20 } }), "ok");
            const label = descendants(keyRow).find(item => item.objectName === "fieldLabel");
            const tip = descendants(label).find(item => String(item).indexOf("Tooltip") === 0);
            verify(!descendants(keyRow).some(item => String(item).indexOf("InfoButton") === 0));
            compare(tip.text, "Open the window.");
            mouseMove(label, label.width / 2, label.height / 2);
            tryCompare(tip, "opened", true);
            mouseMove(root, root.width - 1, root.height - 1);
            tryCompare(tip, "opened", false);
            label.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(tip, "opened", true);
            elsewhere.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(tip, "opened", false);
            keyRow.bind = original;
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
            root.pageRow = shipped;
            page.destroy();
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
            root.pageRow = shipped;
            page.destroy();
        }
    }
}
