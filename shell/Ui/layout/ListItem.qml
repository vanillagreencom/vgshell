import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// One row of a list: an optional icon, a text with an optional secondary
// line under it, and `trailing` items at the end, such as a badge or a
// switch. Both lines draw as plain text: a caller hands a row outside text,
// such as a device name or a copied line, and a tag in it is text, never
// markup. Both lines draw at line height 1, `row.lineGap` apart, so the
// pair's glyphs sit on the row's centre with the icon; a row with a
// secondary line is `listItem.twoLineHeight` tall, one without
// `listItem.height`. The template owns the click and `highlighted`; a
// plain row takes no keyboard focus. A composite list owns the keyboard and
// writes its one selection.
//
// A row of a list that declares a ListCursor names it in `cursor`: the
// cursor then draws the plate and travels to the row while the pointer is
// over it or it is `highlighted`, a hover the cursor lets through emits
// `pointed` for a pick list to select the row, and the row enters through
// ListEntrance when it is created, unless `enters` is false, as for a view
// that creates rows as they scroll in. Every list of clickable rows holds a
// cursor, and no row draws a hover of its own; a row without one fills
// only while it is `highlighted`. `lit` is whether the row draws its text,
// icon and untoned secondary line in `listItem.selectedForeground`: while
// the plate sits on it, its cursor shown, so the pointed row takes the
// accent and a row the plate left drops it, or, without a cursor, while it
// is `highlighted`; and while it is `active`, the page a navigation list
// shows now, so the shown page stays marked while the plate sits on another
// row. A row that draws its own `contentItem` reads `lit` for the same
// colours. Under a rounded theme the side padding grows until the content
// clears the drawn corner. `textStart` is where the row's text
// starts, its padding plus its icon and icon gap, for content a caller
// lines up under the text. `secondaryTone` "danger" draws the secondary
// line in the danger colour, for a state that is a failure, such as a
// stopped printer; "" draws it in its role's colour.
// A row a click cannot change, such as a detail line, sets `clickable`
// false: a hover puts no plate on it, it takes no press and shows no
// pointing hand, and a trailing control keeps its own hover, pointer, focus
// and click.
// `hoverEnabled` stays on, since a control hands its value to each child
// control that sets none, which would take a trailing RowAction's hover.
// keyboard-path: a composite list owns keys and writes highlighted; a plain row is not a tab stop
T.ItemDelegate {
    id: root

    property string iconName: ""
    property string secondary: ""
    property string secondaryTone: ""
    property alias trailing: trailingRow.data
    property ListCursor cursor: null
    property bool active: false
    property bool clickable: true
    property bool enters: cursor !== null
    readonly property bool lit: active || (cursor !== null ? cursor.shown && cursor.placed === root : highlighted)
    readonly property real textStart: leftPadding + (iconName !== "" ? Theme.icon.size.md + Theme.listItem.iconGap : 0)

    signal pointed()

    implicitWidth: leftPadding + rightPadding + (iconName !== "" ? Theme.icon.size.md + Theme.listItem.iconGap : 0) + Math.max(title.implicitWidth, secondaryLabel.implicitWidth) + (trailingRow.width > 0 ? trailingRow.width + Theme.listItem.gap : 0)
    implicitHeight: Math.max(secondary !== "" ? Theme.listItem.twoLineHeight : Theme.listItem.height, implicitContentHeight + topPadding + bottomPadding)
    leftPadding: Theme.controlPadding(Theme.listItem.paddingX, Theme.listItem.radius, Math.max(secondary !== "" ? Theme.listItem.twoLineHeight : Theme.listItem.height, height), implicitContentHeight)
    rightPadding: leftPadding
    spacing: Theme.listItem.gap
    hoverEnabled: true
    down: clickable && pressed
    PointerCursor { enabled: root.clickable }
    opacity: (enabled ? 1 : Theme.opacity.disabled) * entrance.progress
    Accessible.name: text

    transform: ListEntrance { id: entrance; motion: root.cursor !== null ? root.cursor.motion : Theme.motion.list }
    Component.onCompleted: if (enters && cursor !== null) entrance.start(cursor.enterSlot(), 0)
    onSecondaryToneChanged: if (secondaryTone !== "" && secondaryTone !== "danger") console.error("ListItem: secondaryTone " + JSON.stringify(secondaryTone) + " is not one of \"\", danger")

    ListCursorRow {
        cursor: root.cursor
        holds: root.highlighted
        enabled: root.cursor !== null && root.clickable
        onPointed: root.pointed()
    }

    contentItem: Item {
        implicitWidth: (icon.visible ? icon.width + Theme.listItem.iconGap : 0) + Math.max(title.implicitWidth, secondaryLabel.implicitWidth) + (trailingRow.width > 0 ? trailingRow.width + Theme.listItem.gap : 0)
        implicitHeight: Math.max(icon.implicitHeight, lines.implicitHeight, trailingRow.implicitHeight)

        Icon {
            id: icon
            visible: root.iconName !== ""
            name: root.iconName
            size: Theme.icon.size.md
            color: root.lit ? Theme.listItem.selectedForeground : Theme.color.textMuted
            anchors.verticalCenter: parent.verticalCenter
        }
        Column {
            id: lines
            x: icon.visible ? icon.width + Theme.listItem.iconGap : 0
            width: Math.max(0, parent.width - x - (trailingRow.width > 0 ? trailingRow.width + Theme.listItem.gap : 0))
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.row.lineGap
            Label {
                id: title
                role: "item"
                textFormat: Text.PlainText
                text: root.text
                color: root.lit ? Theme.listItem.selectedForeground : Theme.color.text
                width: parent.width
                elide: Text.ElideRight
            }
            Label {
                id: secondaryLabel
                role: "itemHint"
                color: root.secondaryTone === "danger" ? Theme.color.danger : root.lit ? Theme.listItem.selectedForeground : Theme.text.itemHint.color
                textFormat: Text.PlainText
                text: root.secondary
                visible: root.secondary !== ""
                width: parent.width
                elide: Text.ElideRight
            }
        }
        Row {
            id: trailingRow
            spacing: Theme.listItem.gap
            x: parent.width - width
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    background: Rectangle {
        radius: Theme.listItem.radius
        color: root.cursor === null && root.highlighted ? (root.down ? Theme.listItem.selectedPressed : Theme.listItem.selected) : "transparent"
        FocusRing { target: root }
    }
}
