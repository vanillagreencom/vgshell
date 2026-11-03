import QtQuick
import qs.Commons
import qs.Ui

// A titled block of rows: a SectionHeader, which owns the space above and
// below the heading, `spaceAbove` and `spaceBelow`, over the rows. Rows
// inside the section are spaced by `rowSpacing`, `stack.row`, and a
// key/value row under another stands by drawn ink instead (Field); a
// section of blocks, such as a line of buttons and a code line, sets it to
// `stack.group`. The heading sits on the content edge, as
// docs/architecture/design-system.md § Layout puts unboxed text;
// `headerInset` indents it for a surface whose rows inset their text.
Column {
    id: root

    property string title: ""
    property string description: ""
    property string info: ""
    // The info dialog's title, the section's title unless set.
    property string infoTitle: title
    signal pageActivated(string page, string tab)
    property real headerInset: 0
    property real rowSpacing: Theme.stack.row
    property alias spaceAbove: header.spaceAbove
    property alias spaceBelow: header.spaceBelow
    default property alias rows: content.data

    width: parent ? parent.width : implicitWidth
    spacing: 0

    SectionHeader {
        id: header
        text: root.title
        description: root.description
        info: root.info
        infoTitle: root.infoTitle
        onPageActivated: (page, tab) => root.pageActivated(page, tab)
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
