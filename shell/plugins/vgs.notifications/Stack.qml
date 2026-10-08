import QtQuick
import QtQuick.Layouts
import qs.Commons
import "Appearance.js" as Appearance

// The stack on one screen, the content the service hands its layer: the
// toasts, at the edge the service's `position` names inside the space other
// layers do not reserve, so never over the bar, with the newest toast
// nearest that edge. The layer host builds one per screen and assigns
// `screen`. Presses reach only the toast cards. It keeps no keyboard. The
// host destroys a copy a moment after the service that declared it can
// already be gone, so every binding on the service checks it for null, and
// the look is the stack's own reading of the same table.
Item {
    id: stack

    property var screen: null
    required property var service
    readonly property var look: Theme.appearance(Appearance.TOKENS, Appearance.LIGHT)
    readonly property bool inputAll: false
    readonly property var inputItems: [column]
    // With the service gone the model is gone too, so no card is placed.
    readonly property string position: service !== null ? service.position : ""
    // A bottom position lays the cards out from the bottom edge, which the
    // slots read for their gap and their entrance.
    readonly property bool fromBottom: position.startsWith("bottom")
    readonly property string side: position.endsWith("-left") ? "left" : position.endsWith("-right") ? "right" : "centre"

    ColumnLayout {
        id: column
        x: stack.side === "left" ? stack.look.stack.edge
            : stack.side === "right" ? stack.width - width - stack.look.stack.edge
            : Math.round((stack.width - width) / 2)
        y: stack.fromBottom ? stack.height - height - stack.look.stack.edge : stack.look.stack.edge
        // Each slot carries its own gap, scaled by its morph, so the rows
        // close up smoothly when one goes.
        spacing: 0

        CardScroll {
            id: scroll
            look: stack.look
            maxHeight: stack.height - stack.look.stack.edge - stack.look.stack.far
            fromEnd: stack.fromBottom
            scrollObjectName: "notificationScrollBar"
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: implicitWidth
            Layout.preferredHeight: implicitHeight

            Repeater {
                id: slots
                model: stack.service !== null ? stack.service.rows : null
                // The rows are newest first; a bottom stack places them in
                // reverse, the newest in the last row.
                CardSlot {
                    host: stack
                    look: stack.look
                    textColumn: scroll.textColumn
                    Layout.row: stack.fromBottom ? slots.count - 1 - index : index
                }
            }
        }
    }
}
