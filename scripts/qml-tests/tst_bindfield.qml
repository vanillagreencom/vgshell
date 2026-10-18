import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Core
import qs.Ui
import qs.Unit

// BindField: one plugin bind as a form row. Its label is the bind's
// description, else its shortcut name; its ShortcutField holds the key in
// effect, empty while unbound, names the bind to its capture, so `found` is
// the capture's answer and the line under it the answer's hint, and takes
// `editable`; a combo, a typed key, an empty typed key and the unbind
// button each send what the manager writes, and for a bind with a list of
// keys that is the list with the one alternative set or removed, one key
// once one is left and a key twice once; a caller's actions draw in the
// field's tool row, and its hint actions on a line under the hint, taking
// no room while none shows. The explanation of a bind with no hint is
// in its info icon's dialog: the label opens no tooltip, which would lie
// on the bind under it. A bind with a hint opens its explanation in a band
// of one line over that hint, and one too long for that line is in the info
// icon's dialog too. The capture here answers every conflict question with
// one hint and records each question as "KEY ID SHORTCUT". The listed
// bind's key goes through the manager's judge and write as Plugins.setKey
// takes it from the signal.
Item {
    id: root
    width: 480
    height: 300

    // Two key rows as a Settings page draws them, each with a hint, and the
    // row under them.
    Column {
        id: hinted
        y: 600
        width: 570
        BindField {
            id: longKey
            width: parent.width
            hint: "Default shortcut: SUPER+CTRL+X"
            bind: ({ shortcut: "toggle", key: "SUPER+CTRL+X", default: "SUPER+CTRL+X", description: "Start or stop dictation", info: "A key combination that turns dictation on and off. Press it once to start, speak, and press it again to stop. VGS then types what you said into the field that has focus." })
        }
        BindField {
            id: shortKey
            width: parent.width
            hint: "Default shortcut: F9"
            bind: ({ shortcut: "talk", key: "F9", default: "F9", description: "Push to talk", info: "Hold the key while you speak." })
        }
        BindField {
            id: underKeys
            width: parent.width
            hint: "No default shortcut"
            bind: ({ shortcut: "lock", key: null, default: null })
        }
    }

    QtObject {
        id: asker
        property var log: ({ asked: [] })
        function conflicts(key, id, shortcut) {
            log.asked.push(key + " " + id + " " + shortcut);
            return { plugins: [], user: true, binds: "read", hint: "Also used by your other shortcuts." };
        }
    }

    property var sent: []
    property var pairs: []
    property var judged: []
    readonly property var voice: ({ id: "vgs.voice", hyprland: { binds: [{ shortcut: "tap", key: ["code:108", "code:105"] }] } })
    property int linked: 0

    Column {
        width: parent.width
        BindField {
            id: row
            width: parent.width
            pluginId: "vgs.lock"
            bind: ({ shortcut: "lock", key: "SUPER+L", default: "SUPER+L", description: "Lock the screen", info: "Locks the screen at once." })
            capture: asker
            onApplyKey: key => root.sent = root.sent.concat([key])
            actions: [
                Button { id: extra; text: "Extra"; size: "sm" }
            ]
            hintLink: "your other shortcuts"
            onHintLinkActivated: root.linked += 1
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
            id: listed
            width: parent.width
            pluginId: "vgs.voice"
            bind: ({ shortcut: "tap", key: "code:108", keys: ["code:108", "code:105"], default: ["code:108", "code:105"] })
            onApplyKey: key => {
                root.pairs = root.pairs.concat([[key, listed.alternative]]);
                root.judged = root.judged.concat([[PluginLogic.keyRefusal(root.voice, "tap", key), PluginLogic.withKey({}, root.voice, "tap", key, {}).plugins[0].keys.tap]]);
            }
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
            root.pairs = [];
            root.judged = [];
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

        // A bind row with no hint has no line of its own under it, so its
        // explanation opens in the info icon's dialog and neither the label
        // nor the icon opens a tooltip over the bind under it.
        function test_the_bind_explanation_is_in_the_info_dialog() {
            const label = descendant(row, item => item.objectName === "fieldLabel");
            const tip = descendant(label, item => String(item).indexOf("Tooltip") === 0);
            compare(tip.text, "", "the label opens the explanation over the next bind");
            verify(!label.children.find(item => item.visualFocus !== undefined).activeFocusOnTab);
            const mark = descendant(row, item => String(item).indexOf("InfoButton") === 0);
            verify(mark !== null, "the bind draws its info icon");
            compare(mark.info, "Locks the screen at once.");
            compare(mark.tooltip, "");
            compare(descendant(later, item => String(item).indexOf("InfoButton") === 0), null, "a bind with no explanation draws an info icon");
        }

        function tipOf(f) {
            return descendant(descendant(f, item => item.objectName === "fieldLabel"), item => String(item).indexOf("Tooltip") === 0);
        }

        // The room under a hint's top holds a band of one line. A key row's
        // explanation of one line opens there and ends above the next row;
        // a longer one opens in the info icon's dialog and in no band.
        function test_a_key_explanation_over_its_hint_keeps_one_line() {
            const tip = tipOf(shortKey);
            compare(tip.text, "Hold the key while you speak.");
            compare(descendant(shortKey, item => String(item).indexOf("InfoButton") === 0), null, "a key row with room for its explanation draws an info icon");
            tip.shown = true;
            try {
                verify(tip.opened, "the explanation opens its own surface");
                const popup = tip.tracker.popup;
                compare(popup.anchor.edges, Edges.Bottom | Edges.Left, "the explanation opens under its row");
                const title = descendant(popup.contentItem, item => item.objectName === "tooltipTitle");
                compare(title.lineCount, 1);
                const top = tip.anchorItem.mapToItem(hinted, popup.anchor.rect.x, popup.anchor.rect.y + popup.anchor.rect.height - popup.anchor.margins.bottom);
                verify(top.y + popup.implicitHeight <= underKeys.y, "the band reaches the next row: " + (top.y + popup.implicitHeight) + " next " + underKeys.y);
            } finally {
                tip.shown = false;
            }
            compare(tipOf(longKey).text, "", "a long explanation opens in a band over the next row");
            const mark = descendant(longKey, item => String(item).indexOf("InfoButton") === 0);
            verify(mark !== null, "the key row draws its info icon");
            compare(mark.info, longKey.bind.info);
            compare(mark.tooltip, "");
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
            field.committed("SUPER+K", 0);
            field.typed("CTRL+K", 0);
            field.typed("", 0);
            field.cleared(0);
            compare(JSON.stringify(root.sent), JSON.stringify(["SUPER+K", "CTRL+K", null, null]));
        }

        function test_an_edit_of_a_list_sends_the_whole_list() {
            compare(JSON.stringify(input(listed).keys), JSON.stringify(["code:108", "code:105"]));
            const field = input(listed);
            // [why, edit, [what the manager writes, the key the edit set]]
            for (const [why, edit, want] of [
                ["a combo sets its alternative", () => field.committed("SUPER+K", 1), [["code:108", "SUPER+K"], "SUPER+K"]],
                ["a combo past the last adds one", () => field.committed("SUPER+K", 2), [["code:108", "code:105", "SUPER+K"], "SUPER+K"]],
                ["a typed key sets its alternative", () => field.typed("CTRL+K", 0), [["CTRL+K", "code:105"], "CTRL+K"]],
                ["a removal leaves the one other key", () => field.cleared(0), ["code:105", null]],
                ["an empty typed key removes its alternative", () => field.typed("", 1), ["code:108", null]],
                ["a key twice counts once", () => field.committed("code:105", 0), ["code:105", "code:105"]],
                ["remove takes the alternative it names", () => listed.remove(1), ["code:108", null]]
            ]) {
                root.pairs = [];
                root.judged = [];
                edit();
                compare(JSON.stringify(root.pairs), JSON.stringify([want]), why);
                // On Qt 6.12 a list arrives as a wrapper Array.isArray refuses.
                compare(JSON.stringify(root.judged), JSON.stringify([["", want[0]]]), why + ": the manager judges and writes it");
            }
            field.committed("SUPER+K", 0);
            compare(listed.alternative, undefined, "the edit's key is named only while it is sent");
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

        function test_the_hint_cites_its_link_and_reports_it() {
            const link = descendant(input(row), item => item.linked !== undefined && item.text === "Also used by your other shortcuts.");
            verify(link !== null && link.linked, "the hint draws its cited text as a link");
            const before = root.linked;
            link.activated();
            compare(root.linked, before + 1);
            const plain = descendant(input(later), item => item.linked !== undefined && item.text === "Also used by your other shortcuts.");
            verify(plain !== null && !plain.linked, "a field with no link draws plain text");
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
            // The line's room comes back only once its Flow lays out again,
            // which moves the label below; a later hover aimed at the label
            // before that ends outside it.
            tryVerify(() => field.implicitHeight >= fix.mapToItem(field, 0, 0).y + fix.height, 1000, "an action shown again takes its room");
        }
    }
}
