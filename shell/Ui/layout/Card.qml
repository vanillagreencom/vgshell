import QtQuick
import qs.Commons
import qs.Ui

// A raised block for one of several repeated groups, such as one account
// among a panel's accounts, so each group reads apart from the next. Its
// children stand in one column `card.gap` apart, `card.padding` inside an
// outline in `card.border` on `card.background`, and a rounded corner moves
// them in until they clear it (Inset.clearing). It takes its parent's width;
// a caller spaces the cards themselves, as a Pane body does by `stack.group`.
// A `floating` card stands alone in its own popup over the desktop, as
// Jarvis's reply card does in a PassivePopup: it draws its ground through
// GlassSurface in the popover's token group, solid wherever glass is on so
// its text reads over any backdrop, with no outline of its own, and keeps
// the card's padding, gap and clearing.
Rectangle {
    id: root

    default property alias content: column.data
    readonly property real contentInset: clearingInset.inset
    property bool floating: false

    width: parent ? parent.width : implicitWidth
    implicitWidth: column.implicitWidth + 2 * contentInset
    implicitHeight: column.implicitHeight + 2 * contentInset
    color: floating ? "transparent" : Theme.card.background
    border.color: Theme.card.border
    border.width: floating ? 0 : Theme.card.borderWidth
    radius: floating && ground.item !== null ? ground.item.corner : Theme.card.radius

    // Built only for a floating card: a card in a panel draws no glass.
    Loader {
        id: ground
        active: root.floating
        z: -1
        anchors.fill: parent
        sourceComponent: GlassSurface {
            standard: Theme.popover
            elevation: "tight"
            solidOnly: true
        }
    }

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
