import QtQuick
import qs.Commons
import qs.Ui

// A row that shows one item, its icon, its name and one secondary line,
// with its actions at its end in `trailing`, such as an Add button or a
// row's RowActions. It takes no click: no plate, no press and no pointing
// hand, and each trailing control keeps its own hover, focus and click
// (ListItem's `clickable`). Its text starts on the content edge, as the
// other lines of a section do, since a row that takes no click draws no
// box to inset. The secondary line elides on one line, so every content
// row of a list is the same height. A row that opens a page is a
// NavigationRow.
// keyboard-path: each trailing control is its own focus target
ListItem {
    clickable: false
    leftPadding: 0
}
