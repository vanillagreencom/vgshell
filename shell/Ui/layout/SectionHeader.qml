import QtQuick
import qs.Commons
import qs.Ui

// The heading of one section of a panel: an eyebrow title and an optional
// description under it, with the theme's space below. `Section` owns the
// space above. It spans its parent, as a heading does, unless given a
// width; a surface that insets its rows sets `leftPadding` and
// `rightPadding` to match.
Column {
    id: root

    property string text: ""
    property string description: ""
    property string info: ""
    // The width the eyebrow and the description share: the column's own,
    // less its padding, since a positioner does not narrow its children.
    readonly property real bodyWidth: width - leftPadding - rightPadding

    width: parent ? parent.width : implicitWidth

    topPadding: 0
    bottomPadding: Theme.sectionHeader.paddingBottom
    spacing: Theme.sectionHeader.gap

    Item {
        width: root.bodyWidth
        height: Math.max(titleLabel.implicitHeight, infoButton.implicitHeight)

        Label {
            id: titleLabel
            role: "eyebrow"
            text: root.text
            width: parent.width - (infoButton.visible ? infoButton.width + Theme.space.xs : 0)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
        }
        IconButton {
            id: infoButton
            visible: root.info !== ""
            iconName: "info"
            label: "About " + root.text
            infoTitle: root.text
            info: root.info
            size: "sm"
            anchors.left: titleLabel.right
            anchors.leftMargin: Theme.space.xs
            anchors.verticalCenter: parent.verticalCenter
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
