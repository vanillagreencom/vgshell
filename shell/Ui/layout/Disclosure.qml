import QtQuick
import qs.Commons
import qs.Ui

// A list row that shows or hides the content declared inside it: a
// `ListItem` whose click or Space toggles `expanded`, with its `trailing`
// items and then a chevron that points down while the content is hidden
// and up while it shows. A row that cannot expand draws no chevron and keeps
// no chevron room, so trailing items end on the row's content edge. The
// content stacks under the row and takes no height while hidden. A control
// among the trailing items takes its own click, so pressing it toggles
// nothing. While `expandable` is false, as
// for a row with nothing to show, the row draws no chevron and takes no
// click, plate or pointing hand (ListItem.clickable). The content starts at
// the row's text column, the row's padding plus its icon and icon gap, and
// ends at the row's padding. The caller sets the width. A list of
// disclosures declares one ListCursor beside the positioner that holds
// them and names it in each one's `cursor`, which the row takes as a
// ListItem does. Hovering the content releases that plate and keeps the
// header's accent through ListItem.active.
Column {
    id: root

    property alias text: row.text
    property alias secondary: row.secondary
    property alias iconName: row.iconName
    property alias trailing: extra.data
    property bool expanded: false
    property bool expandable: true
    property alias cursor: row.cursor
    readonly property alias focusItem: row
    default property alias content: body.data

    // focus-indicator: ListItem draws its FocusRing for the disclosure row
    ListItem {
        id: row
        width: root.width
        focusPolicy: Qt.StrongFocus
        clickable: root.expandable
        active: contentHover.hovered
        onClicked: if (root.expandable) root.expanded = !root.expanded
        Keys.onReturnPressed: if (root.expandable) root.expanded = !root.expanded
        Keys.onEnterPressed: if (root.expandable) root.expanded = !root.expanded
        Keys.onSpacePressed: if (root.expandable) root.expanded = !root.expanded
        Keys.onRightPressed: if (root.expandable) root.expanded = true
        Keys.onLeftPressed: if (root.expandable) root.expanded = false
        trailing: [
            Row {
                id: extra
                spacing: Theme.listItem.gap
                anchors.verticalCenter: parent.verticalCenter
            },
            Icon {
                visible: root.expandable
                name: root.expanded ? "chevron-up" : "chevron-down"
                size: Theme.icon.size.md
                color: Theme.color.textMuted
                anchors.verticalCenter: parent.verticalCenter
            }
        ]
    }

    Column {
        id: body
        readonly property real inset: row.textStart
        x: inset
        width: Math.max(0, root.width - inset - row.rightPadding)
        visible: root.expandable && root.expanded
        // HoverHandler covers its parent, including nested controls:
        // https://doc.qt.io/qt-6/qml-qtquick-hoverhandler.html#hovered-prop
        HoverHandler {
            id: contentHover
            onHoveredChanged: if (hovered && row.cursor !== null) row.cursor.pointerLeave()
        }
    }
}
