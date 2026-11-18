import QtQuick
import qs.Commons

// FormRow allocates settings inputs; standalone controls keep their caller's
// width within their bounds. Qt layouts honour attached bounds; Items do not.
// Bind row allocations directly. Outside rows, a property action bounds the
// caller's width without removing its binding. Defer that correction until
// anchors finish their geometry update.
// Qt.callLater returns to the event loop before calling the function:
// https://doc.qt.io/qt-6/qml-qtqml-qt.html#callLater-method
QtObject {
    id: root

    required property Item target
    property bool ready: false

    // FormRow owns a settings editor's allocation. A composite input owns
    // its inner slider or text field, which keeps that composite's layout.
    readonly property Item rowSlot: {
        for (let at = target === null ? null : target.parent; at !== null && at !== undefined; at = at.parent) {
            if (typeof at.inputWidth === "number") return at;
        }
        return null;
    }
    readonly property Item inputOwner: {
        for (let at = target === null ? null : target.parent; at !== null && at !== undefined && at !== rowSlot; at = at.parent) {
            if (typeof at.minimumWidth === "number" && typeof at.maximumWidth === "number") return at;
        }
        return null;
    }
    readonly property var allocation: rowSlot !== null && inputOwner === null && target.minimumWidth >= Theme.field.minWidth ? rowSlot.inputWidth : null
    readonly property real availableWidth: rowSlot !== null ? rowSlot.availableWidth
        : target.parent !== null ? Math.max(target.width, target.parent.width - target.x) : target.width
    onAllocationChanged: if (allocation === null) Qt.callLater(constrain)

    function constrain() {
        if (!ready || target === null || allocation !== null) return;
        const boundedWidth = Math.max(rowSlot !== null ? 0 : target.minimumWidth, Math.min(target.maximumWidth, target.width));
        if (target.width !== boundedWidth) {
            correction.value = boundedWidth;
            correction.restart();
        }
    }

    // A readout can change its composite's natural width during a drag.
    // Hold the row allocation as a binding instead of correcting that
    // natural width after the event. Binding restores the caller's width
    // when the control leaves the row.
    // https://doc.qt.io/qt-6/qml-qtqml-binding.html#when-prop
    property Binding rowAllocation: Binding {
        target: root.target
        property: "width"
        when: root.ready && root.target !== null && root.allocation !== null
        value: root.target === null || root.allocation === null ? 0 : Math.min(root.target.maximumWidth, root.allocation)
    }

    property Connections allocationWatch: Connections {
        target: root.allocation === null ? root.target : null
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
        if (allocation === null) Qt.callLater(constrain);
    }
}
