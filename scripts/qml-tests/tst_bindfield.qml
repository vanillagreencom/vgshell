import QtQuick
import QtTest
import qs.Ui
import qs.Unit

// BindField: one plugin bind as a form row. Its label is the bind's
// description, else its shortcut name; its ShortcutField holds the key in
// effect, empty while unbound, names the bind to its capture, so `found` is
// the capture's answer and the line under it the answer's hint, and takes
// `editable`; a combo, a typed key, an empty typed key and the unbind
// button each send what the manager writes; a caller's actions draw in the
// field's tool row, and its hint actions on a line under the hint, taking
// no room while none shows. The capture here answers every conflict question with
// one hint and records each question as "KEY ID SHORTCUT".
Item {
    id: root
    width: 480
    height: 300

    QtObject {
        id: asker
        property var log: ({ asked: [] })
        function conflicts(key, id, shortcut) {
            log.asked.push(key + " " + id + " " + shortcut);
            return { plugins: [], user: true, binds: "read", hint: "Also used by your other shortcuts." };
        }
    }

    property var sent: []

    Column {
        width: parent.width
        BindField {
            id: row
            width: parent.width
            pluginId: "vgs.lock"
            bind: ({ shortcut: "lock", key: "SUPER+L", default: "SUPER+L", description: "Lock the screen" })
            capture: asker
            onApplyKey: key => root.sent = root.sent.concat([key])
            actions: [
                Button { id: extra; text: "Extra"; size: "sm" }
            ]
            hintActions: [
                Button { id: fix; text: "Fix"; size: "sm" },
                Button { id: hidden; text: "Hidden"; size: "sm"; visible: false }
            ]
        }
        BindField {
            id: later
            width: parent.width
            pluginId: "vgs.lock"
            bind: ({ shortcut: "lock", key: "SUPER+L", default: "SUPER+L" })
            capture: asker
            hintActions: [
                Button { id: late; text: "Late"; size: "sm"; visible: false }
            ]
        }
        BindField {
            id: unbound
            width: parent.width
            pluginId: "vgs.lock"
            bind: ({ shortcut: "lock", key: null, default: "SUPER+L" })
            capture: asker
        }
        BindField {
            id: readOnly
            width: parent.width
            editable: false
            bind: ({ shortcut: "lock", key: "SUPER+L", default: "SUPER+L" })
        }
    }

    TestCase {
        name: "bindfield"
        when: windowShown

        function init() {
            UnitTheme.reset();
            root.sent = [];
        }

        function descendant(f, matches) {
            const stack = [f];
            while (stack.length > 0) {
                const item = stack.pop();
                if (item !== f && matches(item)) return item;
                for (let i = 0; i < item.children.length; i++) stack.push(item.children[i]);
            }
            return null;
        }
        function input(f) { return descendant(f, item => String(item).indexOf("ShortcutField") === 0); }

        function test_the_label_is_the_description_else_the_shortcut() {
            compare(row.label, "Lock the screen");
            compare(unbound.label, "lock");
        }

        function test_the_field_holds_the_key_in_effect() {
            compare(input(row).key, "SUPER+L");
            compare(input(unbound).key, "");
        }

        function test_the_field_names_the_bind_to_its_capture() {
            compare(input(row).conflict, "Also used by your other shortcuts.");
            compare(asker.log.asked.indexOf("SUPER+L vgs.lock lock") !== -1, true);
            compare(row.found.user, true);
        }

        function test_each_edit_sends_what_the_manager_writes() {
            const field = input(row);
            field.committed("SUPER+K");
            field.typed("CTRL+K");
            field.typed("");
            field.cleared();
            compare(JSON.stringify(root.sent), JSON.stringify(["SUPER+K", "CTRL+K", null, null]));
        }

        function test_a_read_only_row_offers_no_edit() {
            compare(input(readOnly).editable, false);
            compare(input(row).editable, true);
        }

        function test_a_callers_action_draws_in_the_tool_row() {
            let parent = extra.parent;
            while (parent !== null && parent !== input(row)) parent = parent.parent;
            verify(parent === input(row), "the action sits inside the row's ShortcutField");
        }

        function test_a_hint_action_shown_later_draws() {
            late.visible = true;
            tryVerify(() => late.visible && late.width > 0, 1000, "an action hidden at first shows once it is shown");
            late.visible = false;
        }

        function test_a_hint_action_draws_under_the_hint() {
            const field = input(row);
            const hint = descendant(field, item => item.text === "Also used by your other shortcuts.");
            verify(hint !== null && hint.visible, "the hint draws");
            const below = fix.mapToItem(field, 0, 0).y;
            verify(below >= hint.mapToItem(field, 0, 0).y + hint.height, "the action sits under the hint");
            verify(fix.mapToItem(field, 0, 0).x < extra.mapToItem(field, 0, 0).x, "the action starts the line, not the tool row");
            hidden.visible = false;
            fix.visible = false;
            tryVerify(() => field.implicitHeight <= hint.mapToItem(field, 0, 0).y + hint.height + 1, 1000, "a line with no shown action takes no room");
            fix.visible = true;
            tryVerify(() => fix.mapToItem(field, 0, 0).y >= hint.mapToItem(field, 0, 0).y + hint.height, 1000, "an action shown again draws under the hint");
        }
    }
}
