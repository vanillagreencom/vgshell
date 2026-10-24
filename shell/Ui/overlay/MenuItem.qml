import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// One entry of a Menu: an optional icon, the text, an optional key
// shortcut hint in a trailing column, and a check mark at the end while
// `checked` holds, which marks the current choice. Text wider than the
// menu wraps onto further lines and never elides, so a long value reads in
// full: a line breaks only at a space (LineBreak.atSpaces), the entry grows
// by its lines, and the shortcut keeps its column. A one-line entry's text
// centres its capitals on the entry, as a button's label does, since a
// line box's centre lies below its capitals' centre; a
// wrapped entry keeps its first line where a one-line entry's stands, with
// its icon, shortcut and check mark on its text's reading centre, and as
// much room under its last line. Both draw in the menu's own roles, a pixel
// under a list row's.
// The accessible name is the plain text. The template owns the click,
// `triggered` and the hover; the
// menu sets `highlighted` for the keyboard. `shortcut` is a hint drawn
// after the text, not a binding; a click never toggles
// `checked`, which the author binds. The menu hands every entry its
// ListCursor as `cursor`: the cursor then draws the highlight, and a hover
// it lets through emits `pointed` for the menu to highlight the entry. The
// entry draws no fill of its own. `lit` is whether its icon, text and
// shortcut draw in `listItem.selectedForeground`, as a list row's do
// (ListItem.lit): while the plate sits on it, or, without a cursor, while
// it is `highlighted`. The plate spans the entry, which spans the menu's
// list; the text inset is the entry's own side padding. `barRoom` is the
// strip at the entry's end the menu's scroll bar draws over while the
// entries overflow: the text, the shortcut and the check mark keep clear
// of it, and the plate still spans it.
// An entry that `opensSubmenu` draws a chevron at its end in place of the
// check mark. Its trigger, and that of any entry that `keepsOpen`, such as
// one that goes back a level, leaves the menu open, so the menu's owner
// can change the entries it shows.
// keyboard-path: Menu owns keys and triggers its highlighted item
// focus-indicator: Menu's ListCursor plate shows the highlighted item
T.MenuItem {
    id: root

    property string iconName: ""
    property string shortcut: ""
    property ListCursor cursor: null
    property real barRoom: 0
    property bool opensSubmenu: false
    property bool keepsOpen: opensSubmenu
    readonly property bool lit: cursor !== null ? cursor.shown && cursor.placed === root : highlighted

    signal pointed()

    width: parent ? parent.width : implicitWidth
    implicitWidth: implicitContentWidth + leftPadding + rightPadding
    // A wrapped entry keeps a one-line entry's room above its first line and
    // under its last.
    readonly property bool wraps: title.lineCount > 1
    readonly property real lineInset: Math.max(0, (Theme.menu.item.height - title.lineBox) / 2)
    topPadding: wraps ? lineInset : 0
    bottomPadding: wraps ? lineInset : 0
    implicitHeight: Math.max(Theme.menu.item.height, implicitContentHeight + topPadding + bottomPadding)
    // The centre of the first line from the entry's top, where a control
    // drawn beside the text centres. Label chooses the reading from its
    // text and case, shared by the shortcut, marks and select action.
    readonly property real firstLineCentre: contentItem.y + title.y + title.leadingIconCentre
    // Under a rounded theme the side padding grows until the content
    // clears the drawn corner.
    readonly property real sidePadding: Theme.controlPadding(Theme.menu.item.paddingX, Theme.menu.item.radius, Math.max(Theme.menu.item.height, height), implicitContentHeight)
    leftPadding: sidePadding
    // The check mark or the chevron stands at the end.
    readonly property bool endMark: checked ? true : opensSubmenu
    rightPadding: sidePadding + barRoom + (endMark ? Theme.menu.item.icon + spacing : 0)
    spacing: Theme.menu.item.gap

    // The top, in the entry's coordinates, that puts `glyph`'s ink centre
    // where the text's leading icon centres (Label.topForLeadingIcon), on a
    // whole device pixel: the text centres its capitals on the entry
    // (Label.topForCapCenter), and the icon, the check mark and the chevron
    // centre their ink on the text, so no size takes an offset of its own.
    // A box as tall as the ink's top and bottom together centres on the
    // ink's centre.
    function inkTop(glyph) {
        return title.leadingIconTop(glyph.painted[1] + glyph.painted[3], 0, firstLineCentre);
    }
    hoverEnabled: true
    focusPolicy: Qt.NoFocus
    PointerCursor {}
    opacity: enabled ? 1 : Theme.opacity.disabled
    Accessible.name: text
    Accessible.checked: checked

    ListCursorRow {
        cursor: root.cursor
        holds: root.highlighted
        onPointed: root.pointed()
    }

    contentItem: Item {
        readonly property real lead: icon.visible ? icon.width + root.spacing : 0
        readonly property real tail: hint.visible ? hint.implicitWidth + 2 * root.spacing : 0
        // The text's width on one line, which its line breaks never change.
        implicitWidth: lead + oneLine.advanceWidth + tail
        implicitHeight: Math.max(icon.visible ? icon.height : 0, title.implicitHeight, hint.visible ? hint.implicitHeight : 0)

        Icon {
            id: icon
            visible: root.iconName !== ""
            name: root.iconName
            size: Theme.menu.item.icon
            color: root.lit ? Theme.listItem.selectedForeground : Theme.menu.item.foreground
            y: root.inkTop(icon) - parent.y
        }
        Label {
            id: title
            role: "menuItem"
            spaceWrappedText: root.text
            color: root.lit ? Theme.listItem.selectedForeground : Theme.menu.item.foreground
            x: parent.lead
            width: Math.max(0, parent.width - parent.lead - parent.tail)
            wrapMode: Text.Wrap
            y: root.wraps ? 0 : topForCapCenter(parent.height)
            TextMetrics { id: oneLine; font: title.font; text: root.text }
        }
        Label {
            id: hint
            role: "menuItemHint"
            text: root.shortcut
            visible: root.shortcut !== ""
            color: root.lit ? Theme.listItem.selectedForeground : Theme.menu.item.shortcut
            x: parent.width - width
            // The shortcut's capitals read on the title's first-line
            // centre, including a mixed-case title's x-height reading.
            y: topForCapCenter(2 * (root.firstLineCentre - parent.y))
        }
    }

    // The check mark stands in the right padding, which grows to hold it
    // while the entry is checked. Its ink, not its box, ends a side padding
    // from the end, as the text's starts a side padding from the start: a
    // Lucide glyph's ink sits inside its box by an amount each shape sets.
    indicator: Icon {
        id: check
        name: "check"
        visible: root.checked && !root.opensSubmenu
        size: Theme.menu.item.icon
        color: Theme.menu.item.check
        x: root.width - root.sidePadding - root.barRoom - painted[2]
        y: root.inkTop(check)
    }

    // The submenu's chevron stands where the check mark would, its own ink
    // ending where the check mark's does.
    Icon {
        id: chevron
        name: "chevron-right"
        visible: root.opensSubmenu
        size: Theme.menu.item.icon
        color: Theme.menu.item.shortcut
        x: root.indicator.x + root.indicator.painted[2] - painted[2]
        y: root.inkTop(chevron)
    }
}
