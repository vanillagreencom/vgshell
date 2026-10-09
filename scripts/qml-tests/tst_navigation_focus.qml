import QtQuick
import QtQuick.Window
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.traffic" as Traffic

// Real key events reach the shipped controls from initial non-keyboard
// focus. Programmatic movement and rejected keys keep that reason.
Item {
    id: root
    width: 900
    height: 700
    Button { id: outside; x: 700; y: 600; text: "Outside" }
    Component { id: tabs; Tabs { model: ["First", "Second", "Third"] } }
    Component { id: segments; SegmentedControl { model: ["First", "Second", "Third"] } }
    Component { id: tiles; TileGroup { model: [{text:"First"}, {text:"Second"}, {text:"Third"}] } }
    Component { id: slider; Slider { from: 0; to: 10; value: 5; stepSize: 1 } }
    Component { id: field; TextField { width: 250; text: "Caret" } }
    Component { id: area; TextArea { width: 250; height: 80; text: "Caret" } }
    Component { id: select; Select { model: ["First", "Second", "Third"] } }
    Component { id: scroll; ScrollArea { width: 200; height: 80; keyboardScroll: true; Item { width: 180; height: 500 } } }
    QtObject {
        id: testCapture
        readonly property bool failed: false
        property Item holder: null
        property var ended: ({item:null,reason:""})
        readonly property int timeoutMs: 10000
        function begin(item) { holder = item; return "ok"; }
        function end(item, reason) { if (holder === item) { ended = {item:item,reason:reason}; holder = null; } }
        function keyFor(key, modifiers) { return {kind:"held", modifiers:[]}; }
    }
    Component { id: captureField; ShortcutField { capture: testCapture; keys: ["SUPER+A"]; width: 400 } }
    Component { id: shortcuts; ShortcutField { keys: ["SUPER+A", "SUPER+B"]; width: 400 } }
    Component { id: weekdays; WeekdayChipGroup { width: 400 } }
    Component { id: radio; Radio { text: "Only choice"; checked: true } }
    Component { id: callbackDialog; Dialog {
        x: 300; y: 150; visible: false; title: "Save changes"
        actions: [{label:"Save",role:"accept"},{label:"Cancel",role:"cancel"}]
    } }
    Component { id: devices; DeviceList { width: 350; rows: [{key:"one", text:"Only device"}] } }
    Component { id: traffic; Traffic.Panel {
        width: 600; height: implicitHeight
        shell: ({status:{values:{traffic:{state:"ready", apps:[{name:"Alpha",down:100,up:2,connections:1},{name:"Beta",down:20,up:1,connections:1}]}}}})
    } }

    TestCase {
        name: "navigation_focus"
        when: windowShown
        function init() { root.Window.window.requestActivate(); tryCompare(root.Window.window, "active", true); UnitTheme.reset(); outside.forceActiveFocus(Qt.OtherFocusReason); mouseMove(outside, 2, 2); }
        function rings(item, target) {
            let found = [];
            for (const child of item.children) {
                if ("keyboardFocus" in child && (target === null || child.target === target)) found.push(child);
                found = found.concat(rings(child, target));
            }
            return found;
        }
        function hasRing(item, target) { return rings(item, target).some(ring => ring.visible); }
        function start(target) {
            KeyNavLogic.focusInitial(target, root.Window.window);
            compare(target.activeFocus, true);
            compare(target.focusReason, Qt.OtherFocusReason);
            compare(target.visualFocus, false);
        }
        function test_native_navigation_data() {
            return [
                {tag:"tabs", component:tabs, key:Qt.Key_Right, field:"currentIndex", before:0, after:1},
                {tag:"segments", component:segments, key:Qt.Key_Right, field:"currentIndex", before:0, after:1},
                {tag:"tiles", component:tiles, key:Qt.Key_Right, field:"currentIndex", before:0, after:1},
                {tag:"slider-horizontal", component:slider, key:Qt.Key_Right, field:"value", before:5, after:6},
                {tag:"slider-vertical", component:slider, key:Qt.Key_Up, field:"value", before:5, after:6},
                {tag:"select", component:select, key:Qt.Key_Down, field:"currentIndex", before:0, after:1},
                {tag:"scroll", component:scroll, key:Qt.Key_Down, field:"contentY", before:0, after:Theme.row.height},
                {tag:"shortcut-alternatives", component:shortcuts, key:Qt.Key_Right, field:"current", before:0, after:1},
                {tag:"radio-edge", component:radio, key:Qt.Key_Right, field:"checked", before:true, after:true},
                {tag:"weekday-edge", component:weekdays, key:Qt.Key_Left, field:"currentIndex", before:0, after:0},
                {tag:"device-edge", component:devices, key:Qt.Key_Down, field:"current", before:0, after:0}
            ];
        }
        function test_native_navigation(data) {
            const control = createTemporaryObject(data.component, root);
            verify(control !== null);
            wait(0);
            const target = data.tag === "scroll" ? control.focusProxy : data.tag === "device-edge" ? control.rowAt(0) : data.tag === "weekday-edge" ? control.chipAt(0) : control;
            // ShortcutField's focus scope delegates to its existing box.
            let receiver = target;
            if (data.tag === "shortcut-alternatives") {
                KeyNavLogic.focusInitial(control, root.Window.window);
                receiver = root.Window.window.activeFocusItem;
            }
            start(receiver);
            compare(hasRing(control, data.tag === "tabs" ? null : receiver), false);
            compare(control[data.field], data.before);
            keyClick(data.key);
            compare(control[data.field], data.after);
            compare(receiver.visualFocus, true, "reason=" + receiver.focusReason);
            compare(hasRing(control, data.tag === "tabs" ? null : receiver), true);
            KeyNavLogic.focusInitial(control, root.Window.window);
            waitForRendering(control);
            compare(receiver.visualFocus, false);
            compare(hasRing(control, data.tag === "tabs" ? null : receiver), false);
        }
        function test_retained_scope_empty_refill_native_edge() {
            root.Window.window.requestActivate();
            tryCompare(root.Window.window, "active", true);
            UnitTheme.reset();
            const list = createTemporaryObject(devices, root);
            wait(0);
            KeyNavLogic.focusInitial(list, root.Window.window);
            compare(list.rowAt(0).activeFocus, true);
            compare(hasRing(list, null), false);
            keyClick(Qt.Key_Down);
            compare(hasRing(list, null), true);
            list.rows = [];
            tryCompare(list, "count", 0);
            compare(list.activeFocus, true);
            list.rows = [{key:"next",text:"Next device"}];
            tryCompare(list, "count", 1);
            const row = list.rowAt(0);
            compare(row.activeFocus, true);
            compare(row.focusReason, Qt.OtherFocusReason);
            compare(hasRing(list, null), false);
            keyClick(Qt.Key_Down);
            compare(list.current, 0);
            compare(row.visualFocus, true);
            compare(hasRing(list, null), true);
        }
        function test_tab_callback_keeps_its_dialog_recipient_data() {
            return [{tag:"pointer"}, {tag:"keyboard"}];
        }
        function test_tab_callback_keeps_its_dialog_recipient(data) {
            const control = createTemporaryObject(tabs, root);
            const dialog = createTemporaryObject(callbackDialog, root);
            verify(dialog !== null);
            start(control);
            const changed = () => { if (control.currentIndex === 1) { dialog.visible = true; dialog.takeFocus(); } };
            control.currentIndexChanged.connect(changed);
            try {
                if (data.tag === "pointer") mouseClick(control.itemAt(1));
                else keyClick(Qt.Key_Right);
                compare(control.currentIndex, 1);
                compare(dialog.buttons()[0].activeFocus, true);
                compare(root.Window.window.activeFocusItem, dialog.buttons()[0]);
                compare(dialog.buttons()[0].focusReason, Qt.OtherFocusReason);
                compare(hasRing(dialog, null), false);
            } finally { control.currentIndexChanged.disconnect(changed); }
        }
        function test_programmatic_and_forwarded_movement() {
            const control = createTemporaryObject(segments, root);
            start(control);
            control.nav.moveBy(1);
            compare(control.currentIndex, 1);
            compare(control.visualFocus, false);
            keyClick(Qt.Key_Down);
            compare(control.visualFocus, false);
            outside.forceActiveFocus(Qt.OtherFocusReason);
            control.nav.handle({key:Qt.Key_Right, modifiers:Qt.NoModifier, text:""});
            compare(root.Window.window.activeFocusItem, outside);
            compare(outside.visualFocus, false);
            compare(control.focusReason, Qt.OtherFocusReason);
        }
        function test_pointer_focus_clears_keyboard_ring_data() {
            return [{tag:"segments",component:segments}, {tag:"tiles",component:tiles}, {tag:"tabs",component:tabs}];
        }
        function test_pointer_focus_clears_keyboard_ring(data) {
            const control = createTemporaryObject(data.component, root);
            start(control);
            keyClick(Qt.Key_Right);
            compare(hasRing(control, data.tag === "tabs" ? null : control), true);
            const child = data.tag === "tabs" ? control.itemAt(0) : control.contentItem.children[0];
            mouseClick(child);
            compare(control.currentIndex, 0);
            compare(control.visualFocus, false);
            compare(hasRing(control, null), false);
        }
        function test_weekday_scope_initial_and_native_tab() {
            const group = createTemporaryObject(weekdays, root);
            KeyNavLogic.focusInitial(group, root.Window.window);
            compare(group.chipAt(0).activeFocus, true);
            compare(hasRing(group, null), false);
            keyClick(Qt.Key_Backtab);
            compare(outside.activeFocus, true);
            keyClick(Qt.Key_Tab);
            compare(group.chipAt(0).activeFocus, true);
            compare(group.chipAt(0).focusReason, Qt.TabFocusReason);
            compare(hasRing(group, null), true);
            keyClick(Qt.Key_Tab);
            compare(outside.activeFocus, true);
            keyClick(Qt.Key_Backtab);
            compare(group.chipAt(0).activeFocus, true);
            compare(group.chipAt(0).focusReason, Qt.BacktabFocusReason);
            KeyNavLogic.focusInitial(group, root.Window.window);
            compare(hasRing(group, null), false);
        }
        function test_traffic_actual_tab_and_arrows() {
            const panel = createTemporaryObject(traffic, root);
            verify(panel !== null);
            wait(0);
            function find(item) {
                for (const child of item.children) {
                    if ("keyboardFocus" in child && child.target !== null && child.target.Accessible.name === "Network traffic applications") return child.target;
                    const found = find(child); if (found !== null) return found;
                }
                return null;
            }
            const list = find(panel);
            verify(list !== null);
            list.forceActiveFocus(Qt.OtherFocusReason);
            if ("focusReason" in list) list.focusReason = Qt.OtherFocusReason;
            compare(list.activeFocus, true);
            compare(hasRing(panel, list), false);
            keyClick(Qt.Key_Backtab);
            verify(root.Window.window.activeFocusItem !== list);
            keyClick(Qt.Key_Tab);
            compare(root.Window.window.activeFocusItem, list);
            compare(hasRing(panel, list), true);
            start(list);
            keyClick(Qt.Key_Down);
            compare(panel.current, 1);
            compare(hasRing(panel, list), true);
            const entries = list.children.find(child => child.children.some(row => "highlighted" in row));
            verify(entries !== undefined);
            mouseClick(entries.children.find(row => "highlighted" in row));
            compare(hasRing(panel, list), false);
            KeyNavLogic.focusInitial(list, root.Window.window);
            waitForRendering(panel);
            compare(hasRing(panel, list), false);
            compare(list.Accessible.role, Accessible.List);
        }
        function test_inflight_text_border_reset_data() {
            return [{tag:"field-neutral",component:field,hover:false,error:false}, {tag:"field-hover",component:field,hover:true,error:false}, {tag:"field-error",component:field,hover:true,error:true}, {tag:"area-neutral",component:area,hover:false,error:false}, {tag:"area-hover",component:area,hover:true,error:false}, {tag:"area-error",component:area,hover:true,error:true}];
        }
        function test_inflight_text_border_reset(data) {
            compare(UnitTheme.override({motion:{duration:{fast:1000}}, textField:{error:"#00ff00"}}), "ok");
            const control = createTemporaryObject(data.component, root);
            KeyNavLogic.focusInitial(control, root.Window.window);
            compare(hasRing(control, control), false);
            keyClick(Qt.Key_Backtab);
            compare(outside.activeFocus, true);
            keyClick(Qt.Key_Tab);
            compare(control.activeFocus, true);
            compare(hasRing(control, control), true);
            control.error = true;
            // The old gated Behavior kept a keyboard tint in this transition
            // after reset. The first rendered reset frame must be exact.
            waitForRendering(control);
            if (data.hover) { mouseMove(control, 5, 5); tryCompare(control, "hovered", true); }
            KeyNavLogic.focusInitial(control, root.Window.window);
            control.error = data.error;
            compare(control.focusReason, Qt.OtherFocusReason);
            waitForRendering(control);
            compare(control.background.border.color, Qt.color(data.error ? Theme.textField.error : control.hovered ? Theme.textField.hover : Theme.textField.borderColor));
            compare(hasRing(control, control), false);
            compare(control.cursorVisible, true);
        }
        function test_select_pointer_open_list_keeps_its_cue() {
            const control = createTemporaryObject(select, root);
            mouseClick(control);
            compare(control.listOpen, true);
            compare(hasRing(control, control), false);
            waitForRendering(control);
            compare(control.background.border.color, Qt.color(Theme.textField.focus));
            control.choose(0);
            compare(control.listOpen, false);
        }
        function test_shortcut_capture_keeps_its_cue() {
            const control = createTemporaryObject(captureField, root);
            KeyNavLogic.focusInitial(control, root.Window.window);
            const box = root.Window.window.activeFocusItem;
            compare(hasRing(control, box), false);
            compare(control.capture, testCapture);
            keyClick(Qt.Key_Space);
            compare(control.capturing, true);
            compare(box.focusReason, Qt.OtherFocusReason);
            waitForRendering(control);
            compare(box.background.border.color, Qt.color(Theme.textField.focus));
            keyClick(Qt.Key_Escape);
            compare(control.capturing, false);
        }
        function test_retained_border_data() {
            return [{tag:"select-neutral", component:select, hover:false}, {tag:"select-hover", component:select, hover:true}, {tag:"shortcut-neutral",component:shortcuts,hover:false}, {tag:"shortcut-hover",component:shortcuts,hover:true}];
        }
        function test_retained_border(data) {
            const control = createTemporaryObject(data.component, root);
            KeyNavLogic.focusInitial(control, root.Window.window);
            const receiver = root.Window.window.activeFocusItem;
            verify("background" in receiver);
            if (data.hover) mouseMove(receiver, 5, 5); else mouseMove(outside, 2, 2);
            waitForRendering(control);
            compare(receiver.background.border.color, Qt.color(receiver.hovered ? Theme.textField.hover : Theme.textField.borderColor));
            keyClick(data.tag.startsWith("select") ? Qt.Key_Down : Qt.Key_Right);
            compare(receiver.visualFocus, true);
            tryCompare(receiver.background.border, "color", Qt.color(Theme.textField.focus));
            KeyNavLogic.focusInitial(control, root.Window.window);
            compare(receiver.focusReason, Qt.OtherFocusReason);
            compare(receiver.visualFocus, false);
            waitForRendering(control);
            compare(receiver.background.border.color, Qt.color(receiver.hovered ? Theme.textField.hover : Theme.textField.borderColor));
            compare(hasRing(control, receiver), false);
        }
    }
}
