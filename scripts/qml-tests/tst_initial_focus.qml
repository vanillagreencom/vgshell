import QtQuick
import QtQuick.Window
import QtQuick.Templates as T
import QtTest
import qs.Ui as Ui

Item {
    id: root
    width: 400
    height: 240
    Ui.Button { id: before; text: "Before" }
    FocusScope {
        id: scope
        y: 60
        width: 200
        height: 40
        T.Control {
            id: leaf
            width: parent.width
            height: parent.height
            focus: true
            activeFocusOnTab: true
            Ui.FocusRing { id: ring; target: leaf }
        }
    }
    Ui.Button { id: after; y: 120; text: "After" }
    QtObject { id: otherWindow; property Item activeFocusItem: after }
    TestCase {
        name: "initial_focus"
        when: windowShown
        function init() {
            root.Window.window.requestActivate();
            tryCompare(root.Window.window, "active", true);
            before.forceActiveFocus(Qt.OtherFocusReason);
        }
        function test_active_scope_reopen_resets_its_actual_keyboard_leaf() {
            scope.forceActiveFocus(Qt.OtherFocusReason);
            keyClick(Qt.Key_Tab);
            compare(after.activeFocus, true);
            keyClick(Qt.Key_Backtab);
            compare(leaf.activeFocus, true);
            compare(leaf.focusReason, Qt.BacktabFocusReason);
            compare(ring.visible, true);
            Ui.KeyNavLogic.focusInitial(scope, root.Window.window);
            compare(leaf.activeFocus, true);
            compare(leaf.focusReason, Qt.OtherFocusReason);
            compare(ring.visible, false);
        }
        function test_another_windows_leaf_keeps_its_reason() {
            scope.forceActiveFocus(Qt.OtherFocusReason);
            keyClick(Qt.Key_Tab);
            compare(after.activeFocus, true);
            compare(after.focusReason, Qt.TabFocusReason);
            scope.forceActiveFocus(Qt.OtherFocusReason);
            after.focusReason = Qt.TabFocusReason;
            Ui.KeyNavLogic.focusInitial(scope, otherWindow);
            compare(leaf.activeFocus, true);
            compare(after.focusReason, Qt.TabFocusReason);
            compare(ring.visible, false);
        }
    }
}
