import QtQuick
import QtTest
import qs.Commons
import qs.Core
import qs.Ui
import qs.Unit

// ShortcutField: a click, Enter, Return or Space asks the capture to begin;
// while it holds the field, held modifiers show as caps, the first other
// key commits the combo the judge names unless it is the key in effect,
// Escape, Tab and a focus loss end it, a held key's repeat does nothing, an
// unnamed key and a bare text key keep it with a notice, a refused
// pass-through and a timeout say so, the caps clear a rounded corner as a
// text field does and stand as far from the left border as from the top;
// the keyboard button types a
// combo instead, the clear button unbinds, a read-only field asks nothing,
// and the field is one Tab stop. A shortcut's alternative keys draw as one
// group each with a separator between them, in one box that grows to hold
// them at any width, with no button over a cap; a click on one, or Left and Right, picks the one edited, a combo
// and Delete name it, and add() edits a new one after the last. The
// capture here records what the field asks and names keys with the core's
// own judge. A field naming a plugin bind draws the hint its capture's
// `conflicts` answers for the first alternative another holder asks for.
Item {
    id: root
    width: 480
    height: 300

    QtObject {
        id: capture
        property Item holder: null
        property var calls: []
        property bool failed: false
        property var ended: ({ item: null, reason: "" })
        readonly property int timeoutMs: 10000
        function begin(item) { calls = calls.concat(["begin"]); holder = item; return "ok"; }
        function end(item, reason) { if (item !== holder) return; calls = calls.concat(["end " + reason]); ended = { item: item, reason: reason }; holder = null; }
        function keyFor(key, modifiers) { return PluginLogic.capturedKey(key, modifiers); }
    }

    // A capture that answers every conflict question with one hint and
    // records each question as "KEY ID SHORTCUT", in plain state a binding
    // reads without depending on it.
    QtObject {
        id: asker
        property var log: ({ asked: [] })
        function conflicts(key, id, shortcut) {
            log.asked.push(key + " " + id + " " + shortcut);
            return { plugins: [], user: true, binds: "read", hint: "Also used by your other shortcuts." };
        }
    }
    // Answers a conflict only for Right Ctrl.
    QtObject {
        id: picky
        function conflicts(key, id, shortcut) {
            return { plugins: [], user: key === "code:105", binds: "read", hint: key === "code:105" ? "Also used by your other shortcuts." : "" };
        }
    }
    // Outside the column, so the Tab chain the cases walk holds none of it.
    ShortcutField { id: bound; visible: false; width: 480; keys: ["SUPER+L"]; capture: asker; pluginId: "vgs.lock"; shortcut: "lock" }
    ShortcutField { id: pickyBound; visible: false; width: 480; keys: ["code:108", "code:105"]; capture: picky; pluginId: "vgs.voice"; shortcut: "tap" }

    property var events: []
    // Escapes the fields leave to their surface, as a page's back step reads them.
    property int escapes: 0

    Column {
        id: column
        width: parent.width
        spacing: Theme.space.md
        Keys.onEscapePressed: root.escapes += 1
        Button { id: before; text: "Before"; focusPolicy: Qt.StrongFocus }
        ShortcutField {
            id: field
            width: parent.width
            keys: ["SUPER+M"]
            capture: capture
            onCommitted: key => root.events = root.events.concat(["committed " + key])
            onTyped: text => root.events = root.events.concat(["typed " + text])
            onCleared: root.events = root.events.concat(["cleared"])
        }
        ShortcutField { id: readOnly; width: parent.width; keys: ["SUPER+N"]; capture: capture; editable: false }
        ShortcutField {
            id: pair
            width: parent.width
            keys: ["code:108", "code:105"]
            capture: capture
            onCommitted: (key, index) => root.events = root.events.concat(["committed " + key + " " + index])
            onTyped: (text, index) => root.events = root.events.concat(["typed " + text + " " + index])
            onCleared: index => root.events = root.events.concat(["cleared " + index])
        }
        Button { id: after; text: "After"; focusPolicy: Qt.StrongFocus }
    }
    // As narrow as the gallery's focus example, after the column's Tab chain.
    ShortcutField { id: narrow; y: column.height; width: Theme.size.panel.sm / 2; capture: capture }

    TestCase {
        name: "shortcutfield"
        when: windowShown

        function init() {
            UnitTheme.reset();
            capture.holder = null;
            capture.calls = [];
            capture.failed = false;
            capture.ended = { item: null, reason: "" };
            root.events = [];
            root.escapes = 0;
            field.notice = "";
            field.conflict = "";
            field.capture = capture;
            column.visible = true;
            field.stopTyping();
            pair.keys = ["code:108", "code:105"];
            pair.width = column.width;
            pair.current = 0;
            pair.stopTyping();
            before.forceActiveFocus(Qt.TabFocusReason);
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
        function box(f) { return descendant(f, item => String(item).indexOf("QQuickAbstractButton") === 0); }
        function buttonLabelled(f, label) { return descendant(f, item => item.label === label && item.visible); }
        // The tool row places a button it shows again at its next polish.
        function press(f, label) {
            const button = buttonLabelled(f, label);
            waitForItemPolished(button.parent);
            mouseClick(button);
        }
        function arm() {
            box(field).forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            compare(field.capturing, true);
        }

        function test_tab_reaches_the_box_once() {
            keyClick(Qt.Key_Tab);
            verify(box(field).activeFocus);
            keyClick(Qt.Key_Tab);
            verify(!box(field).activeFocus);
        }

        function test_a_read_only_field_takes_no_focus_and_asks_nothing() {
            compare(box(readOnly).focusPolicy, Qt.NoFocus);
            mouseClick(box(readOnly));
            compare(JSON.stringify(capture.calls), "[]");
            compare(buttonLabelled(readOnly, "Unbind"), null);
        }

        function test_idle_caps_show_the_key() {
            compare(JSON.stringify(field.caps), '["SUPER","M"]');
        }

        function test_return_space_enter_and_click_begin() {
            for (const start of [() => keyClick(Qt.Key_Return), () => keyClick(Qt.Key_Space), () => keyClick(Qt.Key_Enter), () => mouseClick(box(field))]) {
                capture.holder = null;
                capture.calls = [];
                field.forceActiveFocus(Qt.TabFocusReason);
                start();
                compare(JSON.stringify(capture.calls), '["begin"]');
                compare(field.capturing, true);
            }
        }

        function test_a_combo_commits_the_judged_key() {
            for (const row of [
                { key: Qt.Key_Space, modifiers: Qt.MetaModifier, want: "SUPER+SPACE" },
                { key: Qt.Key_T, modifiers: Qt.ControlModifier | Qt.AltModifier, want: "CTRL+ALT+T" },
                { key: Qt.Key_F5, modifiers: Qt.NoModifier, want: "F5" }
            ]) {
                root.events = [];
                capture.calls = [];
                arm();
                keyClick(row.key, row.modifiers);
                compare(JSON.stringify(root.events), JSON.stringify(["committed " + row.want]));
                compare(JSON.stringify(capture.calls), '["begin","end commit"]');
                compare(field.capturing, false);
            }
        }

        function test_held_modifiers_show_as_caps() {
            arm();
            keyPress(Qt.Key_Meta);
            keyPress(Qt.Key_Control, Qt.MetaModifier);
            compare(JSON.stringify(field.caps), '["SUPER","CTRL"]');
            // QtTest releases every modifier its mask names, so each
            // release names none.
            keyRelease(Qt.Key_Control);
            compare(JSON.stringify(field.caps), '["SUPER"]');
            keyRelease(Qt.Key_Meta);
            compare(JSON.stringify(field.caps), "[]");
            compare(JSON.stringify(root.events), "[]");
        }

        function test_escape_cancels() {
            arm();
            keyClick(Qt.Key_Escape);
            compare(JSON.stringify(capture.calls), '["begin","end cancel"]');
            compare(JSON.stringify(root.events), "[]");
            compare(JSON.stringify(field.caps), '["SUPER","M"]');
        }

        function test_a_focus_loss_cancels() {
            arm();
            after.forceActiveFocus(Qt.TabFocusReason);
            compare(JSON.stringify(capture.calls), '["begin","end focus"]');
            compare(JSON.stringify(root.events), "[]");
        }

        function test_an_unnamed_key_keeps_capturing() {
            arm();
            keyClick(Qt.Key_Exclam, Qt.ShiftModifier);
            compare(field.capturing, true);
            verify(field.notice !== "");
            compare(JSON.stringify(root.events), "[]");
        }

        function test_a_capture_owned_elsewhere_ends_the_field() {
            arm();
            capture.holder = before;
            compare(field.capturing, false);
            keyClick(Qt.Key_K, Qt.MetaModifier);
            compare(JSON.stringify(root.events), "[]");
        }

        function test_no_capture_asks_nothing() {
            field.capture = null;
            field.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            compare(field.capturing, false);
            compare(JSON.stringify(capture.calls), "[]");
        }

        function test_typing_sends_the_text_and_escape_goes_back() {
            press(field, "Type the keys");
            compare(field.typing, true);
            for (const c of "SUPER+K") keyClick(c);
            keyClick(Qt.Key_Return);
            compare(field.typing, false);
            compare(JSON.stringify(root.events), '["typed SUPER+K"]');
            verify(box(field).activeFocus);
            press(field, "Type the keys");
            keyClick(Qt.Key_End);
            keyClick("X");
            keyClick(Qt.Key_Escape);
            compare(field.typing, true, "the first Escape restores the key in effect");
            compare(descendant(field, item => item.escapeReverts === true).text, field.key);
            keyClick(Qt.Key_Escape);
            compare(field.typing, false, "the next Escape goes back to the box");
            verify(box(field).activeFocus);
            compare(JSON.stringify(root.events), '["typed SUPER+K"]');
        }

        // A typed key waits for its owner: a loss of focus leaves the entry
        // open and sends nothing, `edited` follows the text against the key
        // in effect, and `acceptTyped` from elsewhere sends the text, closes
        // the entry and leaves the keyboard where it is, with the box as
        // the field's focus.
        function test_a_typed_key_waits_for_its_owner() {
            press(field, "Type the keys");
            compare(field.edited, false, "the key in effect is no edit");
            for (const c of "SUPER+K") keyClick(c);
            compare(field.edited, true);
            after.forceActiveFocus(Qt.TabFocusReason);
            compare(field.typing, true, "a loss of focus leaves the entry open");
            compare(field.edited, true);
            compare(JSON.stringify(root.events), "[]");
            field.acceptTyped();
            compare(JSON.stringify(root.events), '["typed SUPER+K"]');
            compare(field.typing, false);
            compare(field.edited, false);
            verify(after.activeFocus, "the keyboard stays where it was");
            field.forceActiveFocus(Qt.TabFocusReason);
            verify(box(field).activeFocus, "the box is the field's focus");
        }

        // A hidden ancestor, as a tab page that is not shown is to its
        // fields, closes no entry and drops no edit.
        function test_a_typed_key_outlives_a_hidden_ancestor() {
            field.startTyping();
            for (const c of "SUPER+K") keyClick(c);
            column.visible = false;
            compare(field.typing, true);
            compare(field.edited, true);
            column.visible = true;
            const entry = descendant(field, item => item.escapeReverts === true);
            compare(entry.visible, true, "the entry draws again");
            compare(entry.text, "SUPER+K");
        }

        function test_the_entry_opens_on_a_text_its_owner_hands_back() {
            field.startTyping("SUPER+");
            compare(field.typing, true);
            const entry = descendant(field, item => item.escapeReverts === true);
            compare(entry.text, "SUPER+");
            compare(entry.selectedText, "SUPER+");
            compare(field.edited, true);
            verify(entry.activeFocus);
        }

        function test_a_focus_preview_draws_the_ring() {
            const ring = descendant(box(field), item => item.ringColor !== undefined);
            compare(ring.visible, false);
            field.focusPreview = true;
            compare(ring.visible, true);
            field.focusPreview = false;
        }

        function test_escape_on_the_idle_box_goes_on_up() {
            box(field).forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Escape);
            compare(root.escapes, 1);
        }

        function test_typing_ends_a_capture() {
            arm();
            press(field, "Type the keys");
            compare(field.capturing, false);
            compare(JSON.stringify(capture.calls), '["begin","end focus"]');
            compare(field.typing, true);
        }

        function test_clear_unbinds() {
            press(field, "Unbind");
            compare(JSON.stringify(root.events), '["cleared"]');
        }

        function test_the_key_in_effect_changes_nothing() {
            arm();
            keyClick(Qt.Key_M, Qt.MetaModifier);
            compare(JSON.stringify(capture.calls), '["begin","end commit"]');
            compare(JSON.stringify(root.events), "[]");
        }

        function test_a_bare_text_key_keeps_capturing() {
            for (const row of [{ key: Qt.Key_T, modifiers: Qt.NoModifier }, { key: Qt.Key_T, modifiers: Qt.ShiftModifier }, { key: Qt.Key_Space, modifiers: Qt.NoModifier }, { key: Qt.Key_Backspace, modifiers: Qt.NoModifier }]) {
                capture.holder = null;
                field.notice = "";
                arm();
                keyClick(row.key, row.modifiers);
                compare(field.capturing, true);
                verify(field.notice.indexOf("Hold Super, Ctrl or Alt") === 0, field.notice);
                compare(JSON.stringify(root.events), "[]");
            }
        }

        function test_tab_and_shift_tab_end_the_capture_and_move_on() {
            const b = box(field);
            const next = b.nextItemInFocusChain(true);
            const previous = b.nextItemInFocusChain(false);
            arm();
            keyClick(Qt.Key_Tab);
            compare(JSON.stringify(capture.calls), '["begin","end tab"]');
            verify(next.activeFocus, "Tab moves to the next item in the focus chain");
            capture.calls = [];
            arm();
            keyClick(Qt.Key_Backtab, Qt.ShiftModifier);
            compare(JSON.stringify(capture.calls), '["begin","end tab"]');
            verify(previous.activeFocus, "Shift+Tab moves to the item before");
            compare(JSON.stringify(root.events), "[]");
        }

        function test_a_combo_with_tab_is_captured() {
            arm();
            keyClick(Qt.Key_Tab, Qt.AltModifier);
            compare(JSON.stringify(root.events), '["committed ALT+TAB"]');
        }

        function test_a_held_key_repeat_does_nothing() {
            arm();
            const repeat = { key: Qt.Key_Return, modifiers: Qt.NoModifier, isAutoRepeat: true, accepted: false };
            field.pressed(repeat);
            compare(repeat.accepted, true);
            compare(field.capturing, true);
            compare(field.notice, "");
            compare(JSON.stringify(root.events), "[]");
        }

        function test_a_refused_pass_through_is_named() {
            arm();
            capture.failed = true;
            verify(field.hint.indexOf("Hyprland's own shortcuts still run") === 0, field.hint);
            const shown = descendant(field, item => item.text === field.hint && item.visible);
            verify(shown !== null);
            compare(Qt.colorEqual(shown.color, Theme.color.danger), true);
            keyClick(Qt.Key_Escape);
            compare(field.hint, "");
        }

        function test_a_timeout_is_named() {
            arm();
            capture.ended = { item: field, reason: "timeout" };
            capture.holder = null;
            compare(field.notice, "Listening stopped after 10 s. Press Return or click the field to listen again.");
            arm();
            compare(field.notice, "");
            capture.ended = { item: readOnly, reason: "timeout" };
            capture.holder = null;
            compare(field.notice, "");
        }

        // Under a pill theme the first cap starts past the inset, by
        // Theme.controlPadding, so it clears the drawn corner.
        function test_the_caps_clear_a_rounded_corner() {
            compare(UnitTheme.override({ radius: { sm: 4096 } }), "ok");
            const b = box(field);
            tryVerify(() => b.leftPadding > field.inset, 1000, "padding " + b.leftPadding);
            compare(b.leftPadding, field.sidePadding);
            compare(b.rightPadding, field.sidePadding);
            const cap = descendant(b, item => item.text === "Super" && item.radius !== undefined);
            compare(cap.mapToItem(b, 0, 0).x, b.leftPadding);
        }

        function test_a_bind_field_draws_its_capture_hint() {
            compare(bound.conflict, "Also used by your other shortcuts.");
            compare(asker.log.asked[asker.log.asked.length - 1], "SUPER+L vgs.lock lock");
            bound.keys = [];
            compare(bound.conflict, "");
            bound.keys = ["SUPER+L"];
            compare(bound.conflict, "Also used by your other shortcuts.");
            compare(field.conflict, "");
        }

        function test_a_conflict_is_a_hint_that_blocks_nothing() {
            field.conflict = "Also bound to Launcher (toggle).";
            const hint = descendant(field, item => item.text === field.conflict && item.visible);
            verify(hint !== null);
            compare(Qt.colorEqual(hint.color, Theme.color.warning), true);
            arm();
            keyClick(Qt.Key_Space, Qt.MetaModifier);
            compare(JSON.stringify(root.events), '["committed SUPER+SPACE"]');
        }

        // The groups the box draws, each with its caps, and the separators
        // between them that are shown.
        function groupCaps(f) { return descendants(box(f)).filter(item => String(item).indexOf("KeyCaps") === 0 && item.visible).map(item => item.caps.join("+")); }
        function separators(f) { return descendants(box(f)).filter(item => item.objectName === "alternativeSeparator" && item.visible).length; }
        function descendants(f) {
            const found = [f];
            for (let i = 0; i < found.length; i++)
                for (const child of found[i].children || []) found.push(child);
            return found;
        }

        function test_alternatives_draw_apart_with_a_separator_between() {
            compare(JSON.stringify(groupCaps(pair)), JSON.stringify(["Right Alt", "Right Ctrl"]));
            compare(separators(pair), 1);
            compare(JSON.stringify(groupCaps(field)), JSON.stringify(["Super+M"]));
            compare(separators(field), 0, "one key draws no separator");
        }

        function test_the_box_grows_to_hold_every_alternative() {
            const b = box(pair);
            const oneLine = b.height;
            pair.keys = ["SUPER+CTRL+SHIFT+F1", "SUPER+CTRL+SHIFT+F2", "SUPER+CTRL+SHIFT+F3", "SUPER+CTRL+SHIFT+F4"];
            pair.width = Theme.size.panel.sm / 2;
            tryVerify(() => b.height > oneLine, 1000, "the box takes a second line");
            const caps = descendants(b).filter(item => String(item).indexOf("KeyCaps") === 0 && item.visible);
            compare(caps.length, 4);
            for (const each of caps) {
                const at = each.mapToItem(b, 0, 0);
                verify(at.y >= 0 && at.y + each.height <= b.height, "every alternative sits inside the border");
            }
        }

        function caps(f) { return descendants(box(f)).filter(item => String(item).indexOf("Kbd") === 0 && item.visible); }
        function rect(item, to) {
            const at = item.mapToItem(to, 0, 0);
            return { left: at.x, top: at.y, right: at.x + item.width, bottom: at.y + item.height };
        }
        function inside(r, b) { return r.left >= 0 && r.top >= 0 && r.right <= b.width && r.bottom <= b.height; }
        function overlaps(a, c) { return a.left < c.right && c.left < a.right && a.top < c.bottom && c.top < a.bottom; }
        function narrowPair() {
            narrow.keys = ["SUPER+SPACE", "CTRL+ALT+K"];
            narrow.width = Theme.size.panel.sm / 2;
            compare(caps(narrow).length, 5);
        }

        // At the gallery's width the box, which the border and the ring draw
        // on, grows to hold its widest alternative, the buttons follow it,
        // and the field asks for the width it draws.
        function test_every_cap_lies_inside_the_box_at_a_narrow_width() {
            narrowPair();
            const b = box(narrow);
            tryVerify(() => caps(narrow).every(cap => inside(rect(cap, b), b)), 1000, "a cap lies outside the box " + b.width + " wide");
            for (const label of ["Type the keys", "Remove Super+Space"]) {
                const tool = rect(buttonLabelled(narrow, label), b);
                verify(tool.left >= b.width, label + " starts at " + tool.left + ", inside the box " + b.width + " wide");
                verify(narrow.implicitWidth >= rect(buttonLabelled(narrow, label), narrow).right, "the field asks for " + narrow.implicitWidth + ", less than it draws");
            }
        }

        // The Space cap and a plain letter's cap each draw their name with
        // no button drawn over it.
        function test_no_button_draws_over_a_cap() {
            narrowPair();
            const b = box(narrow);
            const named = caps(narrow).filter(cap => cap.text === "Space" || cap.text === "K");
            compare(named.length, 2);
            const tools = ["Type the keys", "Remove Super+Space"].map(label => buttonLabelled(narrow, label));
            tryVerify(() => named.every(cap => tools.every(tool => !overlaps(rect(cap, b), rect(tool, b)))), 1000, "a button lies over a cap");
        }

        // A cap's left edge stands as far from the border as its top, on one
        // line and on several.
        function test_a_cap_stands_as_far_from_the_left_border_as_from_the_top() {
            const one = rect(caps(field)[0], box(field));
            verify(one.top > 0, "the cap touches the border");
            compare(one.left, one.top);
            narrow.keys = ["SUPER+CTRL+SHIFT+F1", "SUPER+CTRL+SHIFT+F2", "SUPER+CTRL+SHIFT+F3"];
            narrow.width = Theme.size.panel.sm;
            const b = box(narrow);
            tryVerify(() => b.height > Theme.textField.height, 1000, "the box takes a second line");
            waitForItemPolished(b.contentItem.children[0]);
            const first = rect(caps(narrow)[0], b);
            compare(first.left, first.top);
        }

        function test_arrows_pick_the_alternative_delete_and_a_combo_edit() {
            box(pair).forceActiveFocus(Qt.TabFocusReason);
            compare(pair.editing, 0);
            keyClick(Qt.Key_Right);
            compare(pair.editing, 1);
            compare(pair.key, "code:105");
            keyClick(Qt.Key_Delete);
            keyClick(Qt.Key_Left);
            compare(pair.editing, 0);
            keyClick(Qt.Key_Return);
            compare(pair.capturing, true);
            keyClick(Qt.Key_K, Qt.MetaModifier);
            compare(JSON.stringify(root.events), JSON.stringify(["cleared 1", "committed SUPER+K 0"]));
        }

        function test_a_click_edits_the_alternative_under_it() {
            const second = descendants(box(pair)).filter(item => String(item).indexOf("KeyCaps") === 0 && item.visible)[1];
            mouseClick(second);
            compare(pair.capturing, true);
            compare(pair.editing, 1);
            keyClick(Qt.Key_K, Qt.MetaModifier);
            compare(JSON.stringify(root.events), JSON.stringify(["committed SUPER+K 1"]));
        }

        function test_add_edits_a_new_alternative_after_the_last() {
            pair.add();
            compare(pair.capturing, true);
            compare(pair.editing, 2);
            compare(separators(pair), 2, "the new alternative draws while it listens");
            keyClick(Qt.Key_K, Qt.MetaModifier);
            compare(JSON.stringify(root.events), JSON.stringify(["committed SUPER+K 2"]));
            pair.add();
            keyClick(Qt.Key_Escape);
            compare(pair.capturing, false);
            compare(pair.editing, 1, "a cancelled new alternative leaves the last one edited");
        }

        function test_the_hint_names_the_alternative_another_holder_asks_for() {
            compare(pickyBound.found.key, "code:105");
            compare(pickyBound.conflict, "Also used by your other shortcuts.");
            pickyBound.keys = ["code:108"];
            compare(pickyBound.found.key, "code:108");
            compare(pickyBound.conflict, "");
            pickyBound.keys = ["code:108", "code:105"];
        }
    }
}
