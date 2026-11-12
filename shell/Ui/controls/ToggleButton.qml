import QtQuick
import qs.Ui

// A button that stays pressed: a tertiary button with `checkable` on, so
// a click toggles `checked` and the checked fill of the theme draws. A set
// `disabledReason` disables it as it disables a Button. With `unlock`
// set, `{ label, run }`, a lock-open mark after the button runs that step
// (UnlockMark): the button keeps that room at its right, outside its fill.
Button {
    id: root

    property var unlock: null

    checkable: true
    variant: "tertiary"
    rightInset: mark.room

    UnlockMark { id: mark; control: root; bodyEnd: root.width - mark.room; centreY: root.height / 2 }
}
