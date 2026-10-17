import QtQuick
import qs.Commons
import qs.Ui

// A list of devices, of any kind: one DeviceRow per entry of `rows`, one
// ListCursor and one Tab stop, the selected row. The list is a FocusScope:
// a Tab, or focus handed to the list, reaches the selected row alone, and
// every other row takes no Tab stop (design-system.md § Keyboard). Up,
// Down, Home, End
// and the pages move the selection and the keyboard with it, through
// KeyNav; Enter, Return, Space and a click run the row's action, and so
// does its RowAction. A busy row shows a Spinner in the action slot and
// emits no action. Shift+F10 and the Menu key open a row's overflow menu.
// With `removable`, Delete asks to remove the selected row (K9).
// The selection shows while the list holds the keyboard or the pointer is
// over it, so two lists of one page never both show one. The selected row
// holds the scope's focus, so a removed row's place takes the keyboard. A
// hover moves the plate and never the selection: the selection moving
// would move the keyboard, and a scroll area reveals the item that takes
// it, so a hover over a row at its edge would scroll the page under the
// pointer (design-system.md § Pointer).
// A set `disabledReason` disables the list: the selected row stays its
// Tab stop, no row, action or key acts or moves the selection, the rows'
// content draws faded with no selection, hover or overflow menu, and the
// reason shows on hover and keyboard focus (DisabledReason). `visualFocus`
// is the keyboard's focus on a row or on a control in one, which opens
// that reason.
//
// Each entry of `rows` is a plain object: `key`, unique in the list, and
// the DeviceRow's `text`, `secondary`, `secondaryTone`, `iconName`,
// `battery`, `badge`, `badgeTone`, `badgeIcon` and `busy` where it has
// them. `actionOf(row)` answers the row's action as `{ text }`, or null
// for none; a busy row ignores that action and shows a Spinner instead.
// `menuOf(row)` its overflow menu as a list of `{ key, text, iconName }`.
// The list acts on nothing itself: it emits `acted(key)`, `chose(key,
// entry)` and `removed(key)`, and the owner acts.
FocusScope {
    id: list

    property var rows: []
    property var actionOf: row => null
    property var menuOf: row => []
    property bool removable: false
    property int current: 0
    property string disabledReason: ""
    readonly property DisabledReason lock: lockState
    readonly property int count: repeater.count
    readonly property string currentKey: current >= 0 && current < rows.length ? String(rows[current].key) : ""
    readonly property bool engaged: !lockState.locked && (activeFocus || hover.hovered)
    readonly property bool visualFocus: activeFocus && Window.activeFocusItem !== null && Window.activeFocusItem.visualFocus === true

    signal acted(string key)
    signal chose(string key, string entry)
    signal removed(string key)

    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight

    onRowsChanged: current = Math.max(0, Math.min(current, rows.length - 1))

    // The row item at INDEX, or null.
    function rowAt(index) { return repeater.itemAt(index); }

    // Give the keyboard to the selected row.
    function focusCurrent(reason) {
        const row = rowAt(current);
        if (row !== null) row.forceActiveFocus(reason === undefined ? Qt.TabFocusReason : reason);
    }

    Keys.onPressed: event => { event.accepted = !lockState.locked && nav.handle(event); }

    // A hover on a row of a locked list takes no plate.
    ListCursor { id: plate; shown: !lockState.locked && (hovered !== null || target !== null) }
    HoverHandler { id: hover }

    KeyNav {
        id: nav
        // Qt publishes a new receiver when a focused row is removed or
        // rebuilt, including an empty list refilled at the same index.
        // https://doc.qt.io/qt-6/qml-qtquick-window.html#activeFocusItem-prop
        focusTarget: list.activeFocus ? list.Window.activeFocusItem : null
        count: list.rows.length
        currentIndex: list.current
        cursor: plate
        itemAt: index => list.rowAt(index)
        labelAt: index => String(list.rows[index].text)
        // The selected row holds the scope's focus. A key move hands the
        // row the keyboard first, with the reason that shows its focus
        // ring, since the focus binding alone would move it with none.
        onMoved: index => {
            const row = list.rowAt(index);
            if (row !== null) row.forceActiveFocus(Qt.TabFocusReason);
            list.current = index;
        }
        onRemoved: index => {
            if (list.removable) list.removed(String(list.rows[index].key));
        }
    }

    Column {
        id: column
        width: list.width

        Repeater {
            id: repeater
            // A count, not the array: a change to the rows keeps every row
            // item, and the keyboard with it, unless the count changes.
            model: list.rows.length

            DeviceRow {
                id: row
                required property int index
                // A row the count drops is read once more before it goes.
                readonly property bool live: index < list.rows.length
                readonly property var modelData: live ? list.rows[index] : ({ key: "", text: "" })
                readonly property var rowAction: live ? list.actionOf(modelData) : null
                readonly property bool busy: live && modelData.busy === true
                width: column.width
                focus: list.current === index
                activeFocusOnTab: list.current === index
                cursor: plate
                highlighted: list.engaged && list.current === index
                onActiveFocusChanged: if (activeFocus) list.current = index
                text: modelData.text
                secondary: modelData.secondary === undefined ? "" : modelData.secondary
                secondaryTone: modelData.secondaryTone === undefined ? "" : modelData.secondaryTone
                iconName: modelData.iconName === undefined ? "" : modelData.iconName
                battery: modelData.battery === undefined ? NaN : modelData.battery
                badge: modelData.badge === undefined ? "" : modelData.badge
                badgeTone: modelData.badgeTone === undefined ? "neutral" : modelData.badgeTone
                badgeIcon: modelData.badgeIcon === undefined ? "" : modelData.badgeIcon
                function act() {
                    if (busy || lockState.locked) return;
                    list.acted(String(modelData.key));
                }
                onClicked: act()
                // The content fades and the row does not, so the row's
                // focus ring keeps its full strength.
                Binding { target: row.contentItem; property: "opacity"; value: lockState.fade }
                actions: [
                    Spinner {
                        visible: row.busy
                        anchors.verticalCenter: parent.verticalCenter
                    },
                    RowAction {
                        visible: !row.busy && row.rowAction !== null
                        text: row.rowAction === null ? "" : row.rowAction.text
                        hoverEnabled: !lockState.locked
                        onClicked: row.act()
                    }
                ]
                menuEntries: [
                    Repeater {
                        model: row.live && !lockState.locked ? list.menuOf(row.modelData) : []
                        MenuItem {
                            required property var modelData
                            text: modelData.text
                            iconName: modelData.iconName === undefined ? "" : modelData.iconName
                            onTriggered: list.chose(String(row.modelData.key), String(modelData.key))
                        }
                    }
                ]
            }
        }
    }

    DisabledReason { id: lockState; control: list }
}
