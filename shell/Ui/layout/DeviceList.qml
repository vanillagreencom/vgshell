import QtQuick
import Quickshell
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
// Each entry of `rows` is a plain object: `key`, unique in the list by
// its producer's identity policy, and the DeviceRow's `text`, `secondary`,
// `secondaryTone`, `iconName`,
// `battery`, `badge`, `badgeTone`, `badgeIcon` and `busy` where it has
// them. `actionOf(row)` answers the row's action as `{ text }`, or null
// for none; a busy row ignores that action and shows a Spinner instead.
// `menuOf(row)` its overflow menu as a list of `{ key, text, iconName }`.
// A row with `opens` true opens a view of its own, such as a country's
// cities: it draws a trailing chevron-right, and since opening changes
// nothing, a `disabledReason` leaves it working. A list that holds such a
// row locks its other rows one by one: the arrows still move, each other
// row draws faded and takes no click or key, and the reason opens while
// the keyboard is on one of them.
// The list acts on nothing itself: it emits `acted(key)`, `chose(key,
// entry)` and `removed(key)`, and the owner acts.
//
// A row is keyed by its `key`, through Quickshell's ScriptModel: a change
// to the rows keeps the item of every row whose key stays, its keyboard
// focus with it, and builds only the rows it adds, so the search of a long
// list builds only the rows a keystroke adds. The selection moves with its
// row while the user chose it, by a Tab, a key or a click, until that row
// leaves the rows, and while the list holds the keyboard, which stays on
// its row. Otherwise nobody chose the selection, so it keeps its place: on
// the first row, which a row listed above it takes, as Recommended does
// above None.
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
    readonly property bool opensAny: rows.some(row => row.opens === true)
    readonly property bool navigable: !(lockState.locked && !opensAny)
    readonly property bool engaged: navigable && (activeFocus || hover.hovered)
    readonly property bool visualFocus: activeFocus && Window.activeFocusItem !== null && Window.activeFocusItem.visualFocus === true && !(current >= 0 && current < rows.length && rows[current].opens === true)
    // Each row's place in `rows` by its key.
    readonly property var placeOf: {
        const out = {};
        rows.forEach((row, index) => { out[String(row.key)] = index; });
        return out;
    }
    // The key of the row that holds the selection, which the rows read.
    property string selectedKey: ""
    // Whether the user chose the selected row: true once the list takes
    // the keyboard or its selection moves while it holds it, and false
    // again once that row leaves the rows, so a selection the list placed
    // itself is never a choice.
    property bool chosenByUser: false

    signal acted(string key)
    signal chose(string key, string entry)
    signal removed(string key)

    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight

    // The handlers read `rows` and `current` themselves: Qt orders a
    // handler and the bindings on one property in no set way, so
    // `placeOf`, `currentKey` and the rows' model can still hold the last
    // value here.
    onCurrentChanged: {
        selectedKey = keyAt(current);
        if (activeFocus) chosenByUser = true;
    }
    onActiveFocusChanged: if (activeFocus) chosenByUser = true
    // The selection follows its row while the user chose it or the list
    // holds the keyboard, which stays on its row; else it keeps its place.
    onRowsChanged: {
        const kept = chosenByUser || activeFocus ? indexOfKey(selectedKey) : -1;
        const choice = chosenByUser && kept !== -1;
        current = kept !== -1 ? kept : Math.max(0, Math.min(current, rows.length - 1));
        selectedKey = keyAt(current);
        // After `current`, whose handler takes a move made while the list
        // holds the keyboard for the user's: this move is the list's own.
        chosenByUser = choice;
        plate.rebuilt();
    }
    Component.onCompleted: selectedKey = keyAt(current)

    function keyAt(index) { return index >= 0 && index < rows.length ? String(rows[index].key) : ""; }
    function indexOfKey(key) { return rows.findIndex(row => String(row.key) === key); }

    // The row item at INDEX, or null.
    function rowAt(index) { return repeater.itemAt(index); }

    // Give the keyboard to the selected row.
    function focusCurrent(reason) {
        const row = rowAt(current);
        if (row !== null) row.forceActiveFocus(reason === undefined ? Qt.TabFocusReason : reason);
    }

    Keys.onPressed: event => { event.accepted = list.navigable && nav.handle(event); }

    // A hover on a row of a locked list takes no plate: a locked row is
    // not clickable, and a locked list holds no selection.
    ListCursor { id: plate; shown: hovered !== null || target !== null }
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
            // Keep the supported Quickshell 0.3.1 floor: its
            // src/core/scriptmodel.cpp updateValuesUnique can leave moved
            // object payloads stale. Stable string keys preserve delegates
            // independently of payload refresh; list.rows owns current data.
            model: ScriptModel { values: list.rows.map(row => String(row.key)) }

            DeviceRow {
                id: row
                required property int index
                required property var modelData
                readonly property string key: String(modelData)
                // A row the rows drop is read once more before it goes.
                readonly property bool live: list.placeOf[key] !== undefined
                readonly property var entry: live ? list.rows[list.placeOf[key]] : ({ key: "", text: "" })
                readonly property var rowAction: live ? list.actionOf(entry) : null
                readonly property bool busy: live && entry.busy === true
                readonly property bool opens: live && entry.opens === true
                readonly property bool locked: lockState.locked && !opens
                readonly property bool selected: key === list.selectedKey
                width: column.width
                focus: selected
                activeFocusOnTab: selected
                // A locked row takes no press: no plate, no hand and no
                // keyboard, as under the shield of a list with no row
                // that opens.
                clickable: !locked
                focusPolicy: locked ? Qt.TabFocus : Qt.StrongFocus
                cursor: plate
                highlighted: list.engaged && selected && !locked
                // By its key: the rows can change before the model moves
                // this row, and its `index` is the model's.
                onActiveFocusChanged: if (activeFocus) list.current = list.indexOfKey(key)
                text: entry.text
                secondary: entry.secondary === undefined ? "" : entry.secondary
                secondaryTone: entry.secondaryTone === undefined ? "" : entry.secondaryTone
                iconName: entry.iconName === undefined ? "" : entry.iconName
                battery: entry.battery === undefined ? NaN : entry.battery
                badge: entry.badge === undefined ? "" : entry.badge
                badgeTone: entry.badgeTone === undefined ? "neutral" : entry.badgeTone
                badgeIcon: entry.badgeIcon === undefined ? "" : entry.badgeIcon
                function act() {
                    if (busy || locked) return;
                    list.acted(row.key);
                }
                onClicked: act()
                // The content fades and the row does not, so the row's
                // focus ring keeps its full strength.
                Binding { target: row.contentItem; property: "opacity"; value: row.locked ? lockState.fade : 1 }
                actions: [
                    Spinner {
                        visible: row.busy
                        anchors.verticalCenter: parent.verticalCenter
                    },
                    RowAction {
                        visible: !row.busy && row.rowAction !== null
                        text: row.rowAction === null ? "" : row.rowAction.text
                        hoverEnabled: !row.locked
                        onClicked: row.act()
                    },
                    Icon {
                        visible: row.opens
                        anchors.verticalCenter: parent.verticalCenter
                        name: "chevron-right"
                        size: Theme.icon.size.md
                        color: Theme.color.textMuted
                    }
                ]
                menuEntries: [
                    Repeater {
                        model: row.live && !lockState.locked ? list.menuOf(row.entry) : []
                        MenuItem {
                            required property var modelData
                            text: modelData.text
                            iconName: modelData.iconName === undefined ? "" : modelData.iconName
                            onTriggered: list.chose(row.key, String(modelData.key))
                        }
                    }
                ]
            }
        }
    }

    // A list with a row that opens refuses its locked rows' presses row by
    // row, so the opening rows keep their clicks.
    DisabledReason { id: lockState; control: list; shields: !list.opensAny }
}
