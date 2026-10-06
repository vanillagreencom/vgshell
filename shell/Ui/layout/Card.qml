import QtQuick
import qs.Commons

// A raised block for one of several repeated groups, such as one account
// among a panel's accounts, so each group reads apart from the next. Its
// children stand in one column `card.gap` apart, `card.padding` inside an
// outline in `card.border` on `card.background`, and a rounded corner moves
// them in until they clear it (Inset.clearing). It takes its parent's width;
// a caller spaces the cards themselves, as a Pane body does by `stack.group`.
Rectangle {
    id: root

    default property alias content: column.data
    readonly property real contentInset: clearingInset.inset

    width: parent ? parent.width : implicitWidth
    implicitWidth: column.implicitWidth + 2 * contentInset
    implicitHeight: column.implicitHeight + 2 * contentInset
    color: Theme.card.background
    border.color: Theme.card.border
    border.width: Theme.card.borderWidth
    radius: Theme.card.radius

    ClearingInset {
        id: clearingInset
        pad: Theme.card.padding
        radius: root.radius
        width: root.width
        height: root.height
        top: Theme.card.padding
    }

    Column {
        id: column
        x: root.contentInset
        y: root.contentInset
        width: Math.max(0, root.width - 2 * root.contentInset)
        spacing: Theme.card.gap
    }
}
