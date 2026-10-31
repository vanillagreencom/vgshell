import QtQuick
import qs.Commons
import qs.Ui

// One device of a list, of any kind: a ListItem with the device's icon,
// its name as `text`, its state as `secondary`, then at the row's end a
// level or battery Badge, the `actions` slot for the device's own buttons,
// such as Connect, and an overflow IconButton that opens a Menu of
// `menuEntries`, the MenuItems the caller supplies. The row takes keyboard
// focus and draws its FocusRing while focus is visual; Enter, Return and
// Space emit `clicked`, the row's primary action, as a click does, and
// Shift+F10 and the Menu key open the overflow menu, as KeyNavLogic reads
// them. Arrows go to the list. Without entries the overflow button is
// hidden and the menu keys pass on. `drawnEntries` counts the menu's first
// entries the row already draws as buttons in `actions`: the overflow
// button shows only for an entry past them, so no button opens a menu
// that repeats the buttons beside it, and the menu keys still open it.
// While the button is hidden the menu opens under the actions.
//
// `battery`, a share of one, draws the badge as a percentage with a battery
// icon, `warning` at or below `deviceRow.battery.warning` and `danger` at
// or below `deviceRow.battery.danger`; a battery that is not a number
// draws none. Otherwise `badge` draws in `badgeTone` with `badgeIcon`, for
// a level such as a signal's. The row owns `trailing`; a list names its
// ListCursor in `cursor`, as for every ListItem.
// focus-indicator: ListItem draws its FocusRing for the row
ListItem {
    id: root

    property real battery: NaN
    property string badge: ""
    property string badgeTone: "neutral"
    property string badgeIcon: ""
    property alias actions: actionRow.data
    property alias menuEntries: overflowMenu.entries
    property int drawnEntries: 0
    property string menuLabel: "More actions"
    readonly property bool hasBattery: Number.isFinite(battery)
    readonly property real batteryShare: hasBattery ? Math.max(0, Math.min(1, battery)) : 0
    readonly property string batteryTone: batteryShare <= Theme.deviceRow.battery.danger ? "danger" : batteryShare <= Theme.deviceRow.battery.warning ? "warning" : "neutral"

    // Open the overflow menu from `opener`, "key" or "pointer"; answers
    // whether there was one to open.
    function openMenu(opener) {
        if (overflowMenu.items().length === 0) return false;
        overflowMenu.open(opener);
        return true;
    }

    focusPolicy: Qt.StrongFocus
    Keys.onPressed: event => {
        const action = KeyNavLogic.intent(event.key, event.modifiers, "vertical", false);
        if (action === "activate") event.accepted = KeyNavLogic.activate(root);
        else if (action === "menu") event.accepted = root.openMenu("key");
    }

    trailing: [
        Badge {
            id: levelBadge
            visible: root.hasBattery || root.badge !== ""
            text: root.hasBattery ? Math.round(root.batteryShare * 100) + "%" : root.badge
            tone: root.hasBattery ? root.batteryTone : root.badgeTone
            iconName: root.hasBattery ? (root.batteryTone === "danger" ? "battery-warning" : root.batteryTone === "warning" ? "battery-low" : "battery") : root.badgeIcon
            anchors.verticalCenter: parent.verticalCenter
        },
        Row {
            id: actionRow
            spacing: Theme.stack.inline
            anchors.verticalCenter: parent.verticalCenter
        },
        IconButton {
            id: more
            visible: overflowMenu.items().length > root.drawnEntries
            iconName: "ellipsis"
            label: root.menuLabel
            size: "sm"
            anchors.verticalCenter: parent.verticalCenter
            onClicked: overflowMenu.toggle(KeyNavLogic.opener(more))

            // A menu follows its parent and closes when it hides
            // (AnchorTracker), so with the button hidden it hangs from the
            // actions it repeats.
            Menu { id: overflowMenu; parent: more.visible ? more : actionRow }
        }
    ]
}
