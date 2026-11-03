import QtQuick
import qs.Commons
import qs.Ui

// The heading of one section of a panel: an eyebrow title and an optional
// description under it. It spans its parent, as a heading does, unless
// given a width; a surface that insets its rows sets `leftPadding` and
// `rightPadding` to match. `info` adds an InfoButton after the title,
// whose dialog takes `infoTitle`, the title unless set.
//
// It owns the space on both sides, so no page pads a heading. Above, it
// leaves `spaceAbove`, `stack.heading`, from the lowest drawn pixel of the
// item laid out before it (Theme.inkBelow) to its capital top. A heading
// first in its Column, or in a Column first in its own, as a `Section`
// holds it, looks to the item before that Column in the Column above, and
// the spacing and top padding of each Column it climbs already stand in
// that space. It climbs no further than a parent that is not a Column,
// such as a Card's box or a tab page's holder, and a heading with nothing
// shown before it there, the first of a page or a card, takes none. Ink is
// drawn in whole pixel rows on whole-pixel item edges: the lowest inked
// row ends floor(inkBelow) above the item's bottom and the first capital
// row starts floor(capital top) below the padding, so the padding counts
// whole rows. Below, it leaves `spaceBelow`, `sectionHeader.paddingBottom`
// under a title alone and `sectionHeader.descriptionGap` under a
// description, less the spacing of the Column it stands in, which the
// Column adds after it. A list with its own rhythm, such as a navigation
// list's group headings, sets both from its own token group.
Column {
    id: root

    property string text: ""
    property string description: ""
    property string info: ""
    property string infoTitle: text
    signal pageActivated(string page, string tab)
    // The width the eyebrow and the description share: the column's own,
    // less its padding, since a positioner does not narrow its children.
    readonly property real bodyWidth: width - leftPadding - rightPadding
    property real spaceAbove: Theme.stack.heading
    property real spaceBelow: description !== "" ? Theme.sectionHeader.descriptionGap : Theme.sectionHeader.paddingBottom

    // The item laid out last before the heading, and the space the
    // Columns climbed to reach it already leave above the heading, or
    // null when nothing shown stands before it. Only `spacing`,
    // `topPadding`, `visible` and sizes are read, never a laid-out `y`
    // or a mapping: Qt 6.11.2 keeps a binding's trigger on geometry it
    // read before, and a moved row would loop (design-system.md § Layout).
    readonly property var placement: {
        let item = root;
        let room = 0;
        while (item.parent instanceof Column) {
            const column = item.parent;
            const siblings = column.children;
            for (let i = siblings.indexOf(item) - 1; i >= 0; i--) {
                const before = siblings[i];
                if (before.visible && before.width > 0 && before.height > 0) return { above: before, room: room + column.spacing };
            }
            room += column.topPadding;
            item = column;
        }
        return null;
    }
    readonly property real parentSpacing: parent instanceof Column ? parent.spacing : 0

    width: parent ? parent.width : implicitWidth

    // The title row is the column's first, at its top padding; its
    // capitals start this far below it.
    readonly property real titleCapTop: text === "" ? 0 : titleLabel.y + titleLabel.capTop()

    // The item above must still read as shown when this reads it. QML
    // marks an item deleted as it starts to destroy it, before it leaves
    // its parent, and emits no change, so `placement` can still name it;
    // a marked item reads `visible` and `children` as undefined while
    // `instanceof` holds (FormRow `inkTop`; run under scripts/qml-unit.sh
    // on Qt 6.11.2 by tst_field_row_above_teardown.qml). The heading then
    // takes no space until `placement` reads the column again.
    topPadding: placement === null || !placement.above.visible ? 0 : Math.max(0, spaceAbove - placement.room - Math.floor(Theme.inkBelow(placement.above)) - Math.floor(titleCapTop))
    bottomPadding: Math.max(0, spaceBelow - parentSpacing)
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
                title: root.infoTitle
                info: root.info
            }
        }
    }
    LinkText {
        role: "hint"
        text: root.description
        visible: root.description !== ""
        width: root.bodyWidth
        wrapMode: Text.Wrap
        onPageActivated: (page, tab) => root.pageActivated(page, tab)
    }
}
