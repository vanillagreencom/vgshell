import QtQuick
import QtTest
import qs.Commons
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
// key the row sends without its text entry is no edit. The owner here
// stands in for the page: it records each write and takes it or refuses it.
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
        binds: [{ shortcut: "tap", key: "code:108", keys: ["code:108", "code:105"], default: "code:108", description: "Tap" }],
        requirements: [],
        errors: []
    })

    EditSet { id: unsaved }
    SignalSpy { id: saved; target: unsaved; signalName: "saved" }
    Item {
        id: fakePanel
        property var shell: null
        property var plugins: []
        property var capture: null
        property var keyWrites: []
        function writeKey(id, shortcut, key) {
            keyWrites.push([id, shortcut, key]);
            return "ok";
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
        function keyFields(item) { return descendants(item).filter(child => child.pluginId === "acme.unit" && child.bind !== undefined && child.shortcutField !== undefined); }
        function type(field, text) {
            const input = editor(field);
            input.forceActiveFocus(Qt.TabFocusReason);
            input.selectAll();
            for (const c of text) keyClick(c);
            return input;
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

        function test_plugin_page_shows_each_key_and_add_writes_a_list() {
            fakePanel.keyWrites = [];
            const page = pluginPageComponent.createObject(root);
            verify(page !== null);
            compare(keyFields(page).length, 2);
            page.addKeySlot("tap", 2);
            compare(keyFields(page).length, 3);
            keyFields(page)[2].applyKey("code:97");
            compare(JSON.stringify(fakePanel.keyWrites), JSON.stringify([["acme.unit", "tap", ["code:108", "code:105", "code:97"]]]));
            page.destroy();
        }
    }
}
