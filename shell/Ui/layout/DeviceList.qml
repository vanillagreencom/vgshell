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
// A row with `opens` true opens a view of its own, such as a country's
// cities: it draws a trailing chevron-right, and since opening changes
// nothing, a `disabledReason` leaves it working. A list that holds such a
// row locks its other rows one by one: the arrows still move, each other
// row draws faded and takes no click or key, and the reason opens while
// the keyboard is on one of them.
// The list acts on nothing itself: it emits `acted(key)`, `chose(key,
// entry)` and `removed(key)`, and the owner acts.
//
// A row is keyed: a change to the rows keeps the item of every row whose
// key stays, its keyboard focus with it, builds only the rows it adds and,
// once the list has held the keyboard, moves the selection with its row.
// Until then nobody chose the selection, so it stays on the first row,
// which a row listed above it takes, as Recommended does above None. The
// search of a long list then builds only the rows a keystroke adds.
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
    // The key of the row that holds the selection, which the keyboard
    // follows through a change to the rows.
    property string selectedKey: ""
    // Whether the list has held the keyboard, which makes its selection
    // a choice that follows its row.
    property bool held: false

    signal acted(string key)
    signal chose(string key, string entry)
    signal removed(string key)

    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight

    // The handlers read `rows` and `current` themselves: Qt orders a
    // handler and the bindings on one property in no set way, so
    // `placeOf` and `currentKey` can still hold the last value here.
    onCurrentChanged: selectedKey = keyAt(current)
    onActiveFocusChanged: if (activeFocus) held = true
    onRowsChanged: {
        const changed = syncKeys();
        const kept = rows.findIndex(row => String(row.key) === selectedKey);
        current = held && kept !== -1 ? kept : Math.max(0, Math.min(current, rows.length - 1));
        selectedKey = keyAt(current);
        if (changed) plate.rebuilt();
    }
    Component.onCompleted: {
        syncKeys();
        selectedKey = keyAt(current);
    }

    function keyAt(index) { return index >= 0 && index < rows.length ? String(rows[index].key) : ""; }

    // The row item at INDEX, or null.
    function rowAt(index) { return repeater.itemAt(index); }

    // Give the keyboard to the selected row.
    function focusCurrent(reason) {
        const row = rowAt(current);
        if (row !== null) row.forceActiveFocus(reason === undefined ? Qt.TabFocusReason : reason);
    }

    // Brings `keyed` to the keys of `rows`, in their order, by removals,
    // moves and inserts alone; answers whether it changed. Qt's ListModel
    // move keeps a Repeater's delegate:
    // https://doc.qt.io/qt-6/qml-qtqml-models-listmodel.html#move-method
    function syncKeys() {
        const keys = rows.map(row => String(row.key));
        const wanted = {};
        for (const key of keys) wanted[key] = true;
        const held = [];
        for (let index = 0; index < keyed.count; index++) held.push(keyed.get(index).key);
        let changed = false;
        for (let index = held.length - 1; index >= 0; index--) {
            if (wanted[held[index]] === true) continue;
            keyed.remove(index);
            held.splice(index, 1);
            changed = true;
        }
        for (let index = 0; index < keys.length; index++) {
            const at = held.indexOf(keys[index], index);
            if (at === index) continue;
            if (at === -1) {
                keyed.insert(index, { key: keys[index] });
                held.splice(index, 0, keys[index]);
            } else {
                keyed.move(at, index, 1);
                held.splice(index, 0, held.splice(at, 1)[0]);
            }
            changed = true;
        }
        return changed;
    }

    Keys.onPressed: event => { event.accepted = list.navigable && nav.handle(event); }

    // A hover on a row of a locked list takes no plate: a locked row is
    // not clickable, and a locked list holds no selection.
    ListCursor { id: plate; shown: hovered !== null || target !== null }
    HoverHandler { id: hover }
    ListModel { id: keyed }

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
            model: keyed

            DeviceRow {
                id: row
                required property int index
                required property string key
                // A row the rows drop is read once more before it goes.
                readonly property bool live: list.placeOf[key] !== undefined
                readonly property var modelData: live ? list.rows[list.placeOf[key]] : ({ key: "", text: "" })
                readonly property var rowAction: live ? list.actionOf(modelData) : null
                readonly property bool busy: live && modelData.busy === true
                readonly property bool opens: live && modelData.opens === true
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
                    if (busy || locked) return;
                    list.acted(String(modelData.key));
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

    // A list with a row that opens refuses its locked rows' presses row by
    // row, so the opening rows keep their clicks.
    DisabledReason { id: lockState; control: list; shields: !list.opensAny }
}
