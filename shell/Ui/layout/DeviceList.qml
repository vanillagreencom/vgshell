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
// does its RowAction. Shift+F10 and the Menu key open a row's overflow
// menu. With `removable`, Delete asks to remove the selected row (K9).
// The selection shows while the list holds the keyboard or the pointer is
// over it, so two lists of one page never both show one. The selected row
// holds the scope's focus, so a removed row's place takes the keyboard.
//
// Each entry of `rows` is a plain object: `key`, unique in the list, and
// the DeviceRow's `text`, `secondary`, `iconName`, `battery`, `badge`,
// `badgeTone` and `badgeIcon` where it has them. `actionOf(row)` answers
// the row's action as `{ text }`, or null for none;
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
    readonly property int count: repeater.count
    readonly property string currentKey: current >= 0 && current < rows.length ? String(rows[current].key) : ""
    readonly property bool engaged: activeFocus || hover.hovered

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

    Keys.onPressed: event => { event.accepted = nav.handle(event); }

    ListCursor { id: plate }
    HoverHandler { id: hover }

    KeyNav {
        id: nav
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
                width: column.width
                focus: list.current === index
                activeFocusOnTab: list.current === index
                cursor: plate
                highlighted: list.engaged && list.current === index
                onPointed: list.current = index
                onActiveFocusChanged: if (activeFocus) list.current = index
                text: modelData.text
                secondary: modelData.secondary === undefined ? "" : modelData.secondary
                iconName: modelData.iconName === undefined ? "" : modelData.iconName
                battery: modelData.battery === undefined ? NaN : modelData.battery
                badge: modelData.badge === undefined ? "" : modelData.badge
                badgeTone: modelData.badgeTone === undefined ? "neutral" : modelData.badgeTone
                badgeIcon: modelData.badgeIcon === undefined ? "" : modelData.badgeIcon
                onClicked: list.acted(String(modelData.key))
                actions: [
                    RowAction {
                        visible: row.rowAction !== null
                        text: row.rowAction === null ? "" : row.rowAction.text
                        onClicked: list.acted(String(row.modelData.key))
                    }
                ]
                menuEntries: [
                    Repeater {
                        model: row.live ? list.menuOf(row.modelData) : []
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
}
