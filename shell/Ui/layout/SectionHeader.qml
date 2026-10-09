import QtQuick
import qs.Commons
import qs.Ui

// The heading of one section of a panel: an eyebrow title and an optional
// description under it, with the theme's space below, `stack.group` under a
// description, since the rows after it are a group. `Section` owns the
// space above. It spans its parent, as a heading does, unless given a
// width; a surface that insets its rows sets `leftPadding` and
// `rightPadding` to match. `capTop()` is how far below its top the
// title's capitals start, or 0 for no title, for the space `Section`
// measures to what it draws.
Column {
    id: root

    property string text: ""
    property string description: ""
    property string info: ""
    // The width the eyebrow and the description share: the column's own,
    // less its padding, since a positioner does not narrow its children.
    readonly property real bodyWidth: width - leftPadding - rightPadding

    width: parent ? parent.width : implicitWidth

    // The title row is the column's first, at its top padding.
    function capTop() { return text === "" ? 0 : topPadding + titleLabel.y + titleLabel.capTop(); }

    topPadding: 0
    bottomPadding: description !== "" ? Theme.stack.group : Theme.sectionHeader.paddingBottom
    spacing: Theme.sectionHeader.gap

    Item {
        width: root.bodyWidth
        height: Math.max(titleLabel.implicitHeight, infoButton.implicitHeight)

        Label {
            id: titleLabel
            role: "eyebrow"
            text: root.text
            width: parent.width - (infoButton.active ? infoButton.width + Theme.space.xs : 0)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
        }
        Loader {
            id: infoButton
            active: root.info !== ""
            anchors.left: titleLabel.right
            anchors.leftMargin: Theme.space.xs
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: InfoButton {
                title: root.text
                info: root.info
            }
        }
    }
    Label {
        role: "hint"
        text: root.description
        visible: root.description !== ""
        width: root.bodyWidth
        wrapMode: Text.Wrap
    }
}
