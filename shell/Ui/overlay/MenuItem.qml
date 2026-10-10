import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// One entry of a Menu: an optional icon, the text, an optional key
// shortcut hint in a trailing column, and a check mark at the end while
// `checked` holds, which marks the current choice. The text elides when
// the menu is narrower than the entry, and the shortcut keeps its column. The template owns the click, `triggered` and
// the hover; the menu sets `highlighted` for the keyboard. `shortcut` is a
// hint drawn after the text, not a binding; a click never toggles
// `checked`, which the author binds. The menu hands every entry its
// ListCursor as `cursor`: the cursor then draws the highlight, and a hover
// it lets through emits `pointed` for the menu to highlight the entry. The
// fill spans the entry, which spans the menu's list; the text inset is the
// entry's own side padding. `barRoom` is the strip at the entry's end the
// menu's scroll bar draws over while the entries overflow: the text, the
// shortcut and the check mark keep clear of it, and the fill still spans it.
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

    signal pointed()

    width: parent ? parent.width : implicitWidth
    implicitWidth: implicitContentWidth + leftPadding + rightPadding
    implicitHeight: Math.max(Theme.menu.item.height, implicitContentHeight + topPadding + bottomPadding)
    // Under a rounded theme the side padding grows until the content
    // clears the drawn corner.
    readonly property real sidePadding: Theme.controlPadding(Theme.menu.item.paddingX, Theme.menu.item.radius, Math.max(Theme.menu.item.height, height), implicitContentHeight)
    leftPadding: sidePadding
    // The check mark or the chevron stands at the end.
    readonly property bool endMark: checked ? true : opensSubmenu
    rightPadding: sidePadding + barRoom + (endMark ? Theme.menu.item.icon + spacing : 0)
    spacing: Theme.menu.item.gap
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
        implicitWidth: lead + title.implicitWidth + tail
        implicitHeight: Math.max(icon.visible ? icon.height : 0, title.implicitHeight, hint.visible ? hint.implicitHeight : 0)

        Icon {
            id: icon
            visible: root.iconName !== ""
            name: root.iconName
            size: Theme.menu.item.icon
            color: Theme.menu.item.foreground
            anchors.verticalCenter: parent.verticalCenter
        }
        Label {
            id: title
            role: "item"
            text: root.text
            color: Theme.menu.item.foreground
            x: parent.lead
            width: Math.max(0, parent.width - parent.lead - parent.tail)
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
        }
        Label {
            id: hint
            role: "itemHint"
            text: root.shortcut
            visible: root.shortcut !== ""
            color: Theme.menu.item.shortcut
            x: parent.width - width
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // The check mark stands in the right padding, which grows to hold it
    // while the entry is checked. Its ink, not its box, ends a side padding
    // from the end, as the text's starts a side padding from the start: a
    // Lucide glyph's ink sits inside its box by an amount each shape sets.
    indicator: Icon {
        name: "check"
        visible: root.checked && !root.opensSubmenu
        size: Theme.menu.item.icon
        color: Theme.menu.item.check
        x: root.width - root.sidePadding - root.barRoom - painted[2]
        y: Math.round((root.height - height) / 2)
    }

    // The submenu's chevron stands where the check mark would, its own ink
    // ending where the check mark's does.
    Icon {
        name: "chevron-right"
        visible: root.opensSubmenu
        size: Theme.menu.item.icon
        color: Theme.menu.item.shortcut
        x: root.indicator.x + root.indicator.painted[2] - painted[2]
        y: root.indicator.y
    }

    background: Rectangle {
        radius: Theme.menu.item.radius
        color: root.cursor !== null ? "transparent" : root.down ? Theme.menu.item.pressed : root.highlighted || root.hovered ? Theme.menu.item.hover : "transparent"
    }
}
