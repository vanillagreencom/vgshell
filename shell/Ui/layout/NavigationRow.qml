import QtQuick
import qs.Commons
import qs.Ui

// A row the whole of which takes the click, such as one that opens a
// page: its list's ListCursor draws the hover plate (`cursor`), and it
// ends in a chevron.
// `accessories` are the items before the chevron, such as a count badge
// or a small switch; the row owns `trailing`, so a caller never assigns
// it. Qt's Row lays out no child that is hidden or has no size
// (https://doc.qt.io/qt-6/qml-qtquick-row.html), so a row with no shown
// accessory puts no gap before its chevron. `chevronName` names the
// chevron: a disclosure turns it down or up, and a row whose click acts
// in place, such as a device's, names none, "", and keeps no room for it.
// A row that shows one item with actions and takes no click is a
// ContentRow.
// keyboard-path: a composite list owns keys and writes highlighted, as for ListItem
ListItem {
    id: root

    property alias accessories: accessoryRow.data
    property string chevronName: "chevron-right"

    trailing: [
        Row {
            id: accessoryRow
            spacing: Theme.listItem.gap
            anchors.verticalCenter: parent.verticalCenter
        },
        Icon {
            visible: root.chevronName !== ""
            name: root.chevronName
            size: Theme.icon.size.sm
            color: Theme.color.textMuted
            anchors.verticalCenter: parent.verticalCenter
        }
    ]
}
