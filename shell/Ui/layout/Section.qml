import QtQuick
import qs.Commons
import qs.Ui

// A titled block of rows. The space above the heading is `stack.heading`
// no matter which Column owns it or what stands above: measured from the
// lowest drawn pixel of the item placed above (Theme.inkBelow) to the
// heading's capital top, less the parent's spacing, so a switch, a select
// and a help line all leave the same space. The first item takes no top
// padding. Rows inside the section
// are spaced by `rowSpacing`, `stack.row`; a section of blocks, such as a
// line of buttons and a code line, sets it to `stack.group`. The heading
// sits on the content edge, as docs/architecture/design-system.md § Layout puts unboxed text; `headerInset`
// indents it for a surface whose rows inset their text.
Column {
    id: root

    property string title: ""
    property string description: ""
    property string info: ""
    property real headerInset: 0
    property real rowSpacing: Theme.stack.row
    default property alias rows: content.data

    readonly property real parentSpacing: parent && parent.spacing !== undefined ? parent.spacing : 0
    // The child the parent lays out last before this one, shown and
    // sized, or null, when the space is measured from the parent's top.
    readonly property Item above: {
        if (!parent) return null;
        const siblings = parent.children;
        let below = true;
        for (let i = siblings.length - 1; i >= 0; i--) {
            const item = siblings[i];
            if (item === root) below = false;
            else if (!below && item.visible && item.width > 0 && item.height > 0) return item;
        }
        return null;
    }

    width: parent ? parent.width : implicitWidth
    topPadding: Positioner.isFirstItem ? 0 : Math.max(0, Theme.stack.heading - parentSpacing - Theme.inkBelow(above) - header.capTop())
    spacing: 0

    SectionHeader {
        id: header
        text: root.title
        description: root.description
        info: root.info
        leftPadding: root.headerInset
        rightPadding: root.headerInset
        width: root.width
    }

    Column {
        id: content
        width: root.width
        spacing: root.rowSpacing
    }
}
