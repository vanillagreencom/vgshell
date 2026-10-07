import QtQuick

// Search fields and device controls bind width directly to their parent.
// Qt layouts honour the attached bounds; plain Items do not.
// A property action changes the allocation without removing its binding.
// Defer the correction until anchors finish their geometry update.
// Qt.callLater returns to the event loop before calling the function:
// https://doc.qt.io/qt-6/qml-qtqml-qt.html#callLater-method
QtObject {
    id: root

    required property Item target
    property bool ready: false

    function constrain() {
        if (!ready || target === null) return;
        const boundedWidth = Math.max(target.minimumWidth, Math.min(target.maximumWidth, target.width));
        if (target.width !== boundedWidth) {
            correction.value = boundedWidth;
            correction.restart();
        }
    }

    property Connections allocation: Connections {
        target: root.target
        function onWidthChanged() { Qt.callLater(root.constrain); }
        function onMinimumWidthChanged() { Qt.callLater(root.constrain); }
        function onMaximumWidthChanged() { Qt.callLater(root.constrain); }
    }

    property PropertyAction correction: PropertyAction {
        target: root.target
        property: "width"
    }

    Component.onCompleted: {
        ready = true;
        Qt.callLater(constrain);
    }
}
