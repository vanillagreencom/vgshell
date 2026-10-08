import QtQuick
import QtQuick.Window
import QtQuick.Templates as T
import QtTest
import qs.Ui

Item {
    id: root
    width: 400
    height: 200
    Button { id: before; text: "Before" }
    Component { id: targetFactory; T.Control { y: 60; width: 200; height: 40; activeFocusOnTab: true } }
    Component { id: ringFactory; FocusRing {} }
    TestCase {
        name: "focusring"
        when: windowShown
        function test_a_surviving_ring_hides_after_its_actual_target_is_destroyed() {
            root.Window.window.requestActivate();
            tryCompare(root.Window.window, "active", true);
            const target = createTemporaryObject(targetFactory, root);
            const ring = createTemporaryObject(ringFactory, root, {target: target});
            before.forceActiveFocus(Qt.OtherFocusReason);
            keyClick(Qt.Key_Tab);
            compare(target.activeFocus, true);
            compare(ring.keyboardFocus, true);
            compare(ring.visible, true);
            target.destroy();
            wait(0);
            compare(ring.target, null);
            compare(ring.keyboardFocus, false);
            compare(ring.visible, false);
        }
    }
}
