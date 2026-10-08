import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../foundation/KeyNavLogic.js" as KeyNavLogic

// Seven weekday chips, Monday first. `selected` holds weekday keys
// `mon` through `sun`; a click toggles one key and keeps the list in week
// order. The group is one tab stop and the arrow keys move the current
// chip.
// focus-indicator: the focused chip's ToggleButton draws the ring.
FocusScope {
    id: root

    readonly property real minimumWidth: Theme.field.minWidth
    readonly property real maximumWidth: Theme.control.maxWidth
    Layout.minimumWidth: minimumWidth
    Layout.maximumWidth: maximumWidth
    width: Math.max(minimumWidth, Math.min(maximumWidth, implicitWidth))
    InputWidth { target: root }

    property var selected: []
    property var displaySelected: selected
    property bool exclusive: false
    readonly property var days: [
        { key: "mon", label: "M" },
        { key: "tue", label: "T" },
        { key: "wed", label: "W" },
        { key: "thu", label: "T" },
        { key: "fri", label: "F" },
        { key: "sat", label: "S" },
        { key: "sun", label: "S" }
    ]
    property int currentIndex: 0
    signal changed(var selected)
    signal toggled(string day)

    onSelectedChanged: displaySelected = ordered(selected)

    function has(key) { return displaySelected.indexOf(key) !== -1; }
    function ordered(keys) { return days.map(d => d.key).filter(key => keys.indexOf(key) !== -1); }
    function setChecked(key, checked) {
        let next = exclusive ? [key] : displaySelected.filter(v => v !== key);
        if (!exclusive && checked) next.push(key);
        next = ordered(next);
        displaySelected = next;
        toggled(key);
        changed(next);
    }
    function focusCurrent(reason) {
        const item = repeater.itemAt(currentIndex);
        if (item !== null) item.forceActiveFocus(reason || Qt.OtherFocusReason);
    }
    function chipAt(index) { return repeater.itemAt(index); }
    function move(step) {
        currentIndex = Math.max(0, Math.min(days.length - 1, currentIndex + step));
        focusCurrent(step > 0 ? Qt.TabFocusReason : Qt.BacktabFocusReason);
        KeyNavLogic.focusNavigation(chipAt(currentIndex));
    }

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    activeFocusOnTab: false
    Keys.onLeftPressed: move(-1)
    Keys.onRightPressed: move(1)

    Row {
        id: row
        spacing: Theme.space.xs

        Repeater {
            id: repeater
            model: root.days

            ToggleButton {
                required property var modelData
                required property int index
                text: modelData.label
                size: "sm"
                focus: root.currentIndex === index
                activeFocusOnTab: root.currentIndex === index
                checked: root.has(modelData.key)
                Accessible.name: modelData.key
                onClicked: {
                    const wanted = root.exclusive ? true : !root.has(modelData.key);
                    root.currentIndex = index;
                    checked = Qt.binding(() => root.has(modelData.key));
                    root.setChecked(modelData.key, wanted);
                }
                Keys.onLeftPressed: root.move(-1)
                Keys.onRightPressed: root.move(1)
            }
        }
    }
}
