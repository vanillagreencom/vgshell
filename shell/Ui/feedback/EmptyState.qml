import QtQuick
import qs.Commons
import qs.Ui

// What an empty list or view shows: an icon, one hint line and a recovery
// action, such as Clear search, centred in a box three of a list's
// two-line rows tall, each `stack.group` from the next. The icon draws
// only while `iconName` is set and the action only while `actionText` is;
// a press on the action emits `activated`. With `placement: "top"` the
// parts stand at the box's top and leading edge and the box is only as
// tall as they are, so an empty section's short line stands under its
// heading where its first row would. An unknown placement is logged and
// drawn centred. The caller sets the width and places the box.
Item {
    id: root

    property string iconName: ""
    property string text: ""
    property string actionText: ""
    property string placement: "center"
    readonly property bool atTop: placement === "top"

    signal activated()
    signal pageActivated(string page, string tab)

    function checkPlacement() {
        if (placement !== "center" && placement !== "top") console.error("EmptyState: no placement named " + JSON.stringify(placement));
    }
    onPlacementChanged: checkPlacement()
    Component.onCompleted: checkPlacement()
    implicitHeight: atTop ? column.implicitHeight : 3 * Theme.listItem.twoLineHeight

    Column {
        id: column
        anchors.centerIn: root.atTop ? undefined : parent
        width: parent.width
        spacing: Theme.stack.group

        Icon {
            anchors.horizontalCenter: root.atTop ? undefined : parent.horizontalCenter
            visible: root.iconName !== ""
            name: root.iconName
            size: Theme.icon.size.xl
            color: Theme.color.textFaint
        }
        LinkText {
            role: "hint"
            text: root.text
            color: Theme.color.textMuted
            width: parent.width
            horizontalAlignment: root.atTop ? Text.AlignLeft : Text.AlignHCenter
            wrapMode: Text.Wrap
            onPageActivated: (page, tab) => root.pageActivated(page, tab)
        }
        Button {
            anchors.horizontalCenter: root.atTop ? undefined : parent.horizontalCenter
            visible: root.actionText !== ""
            text: root.actionText
            variant: "tertiary"
            onClicked: root.activated()
        }
    }
}
