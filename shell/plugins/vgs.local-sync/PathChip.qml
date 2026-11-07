import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// A folder of a job in a chip: its path on one or more lines of the
// `pathChip` text role, the bundled monospace face, `pathChip.padding`
// inside on every side, on `pathChip.background` at the user's control
// corner, `pathChip.hoverBackground` under the pointer. A local folder is
// a button: the pointer, Space and Return open it through the core's
// folder route (Panel.qml showFolder), and keyboard focus draws the ring
// outside the chip. A folder on another computer, such as an ssh root of
// a unison job, is text only. The chip is as wide as its path up to
// `maxWidth` and wraps anywhere past it, so no path is cut.
T.AbstractButton {
    id: chip

    property real maxWidth: 0
    // Whether the path names a folder on this computer, which opens.
    readonly property bool local: text.charAt(0) === "/"
    // The height of a one-line chip, which a label beside it centres on.
    readonly property real lineHeight: 2 * Theme.pathChip.padding + path.lineBox

    enabled: local
    focusPolicy: local ? Qt.StrongFocus : Qt.NoFocus
    hoverEnabled: local
    implicitWidth: Math.min(maxWidth, Math.ceil(path.implicitWidth) + 2 * Theme.pathChip.padding)
    implicitHeight: 2 * Theme.pathChip.padding + Math.max(1, path.lineCount) * path.lineBox
    Accessible.name: local ? "Open " + text : text

    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()

    background: Surface {
        standard: ({
            background: chip.hovered ? Theme.pathChip.hoverBackground : Theme.pathChip.background,
            border: chip.hovered ? Theme.pathChip.hoverBackground : Theme.pathChip.background,
            radius: Theme.button.radius
        })
    }

    contentItem: Item {
        Label {
            id: path
            x: Theme.pathChip.padding
            y: lineCount <= 1 ? topForCapCenter(chip.height) : Theme.pathChip.padding
            width: chip.width - 2 * Theme.pathChip.padding
            role: "pathChip"
            text: chip.text
            wrapMode: Text.WrapAnywhere
        }
    }

    // A sibling of the fill, so the ring outside the chip is not cut by
    // the surface.
    FocusRing { target: chip; outside: true; targetRadius: Math.min(Theme.button.radius, chip.height / 2) }
    PointerCursor { enabled: chip.local }
}
