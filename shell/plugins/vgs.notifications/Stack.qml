import QtQuick
import QtQuick.Layouts
import qs.Commons
import "Appearance.js" as Appearance
import "NotificationLogic.js" as Logic

// The host can destroy this per-screen view after its service is gone.
// Guard service bindings and resolve the look independently for teardown.
Item {
    id: stack

    property var screen: null
    required property var service
    readonly property var look: Theme.appearance(Appearance.TOKENS, Appearance.LIGHT)
    readonly property bool inputAll: false
    // The open inbox lists every toast, so the stack draws none and takes
    // no input under it; its cards stay built and show again as they were
    // when it closes.
    readonly property bool underInbox: service !== null && service.panelOpen
    readonly property var inputItems: underInbox ? [] : [column]
    readonly property string position: service !== null ? service.position : ""
    readonly property bool fromBottom: position.startsWith("bottom")
    readonly property string side: position.endsWith("-left") ? "left" : position.endsWith("-right") ? "right" : "center"
    // The visible gap between the nearest card and each edge the stack is
    // placed at, the same at the top, the bottom and the sides: the top
    // gap the stack keeps plus the gap a slot keeps beside its card. The
    // column's box carries room past the card, for the cards' shadows at
    // the sides and the scroll tail and a slot's gap under a bottom stack's
    // newest card, so the box sits that much past the edge: off the
    // surface, where nothing draws. The slim bar beside a right stack's
    // cards stays on the surface while scrollbar.gap plus half of
    // scrollbar.width and of scrollbar.wide fits in this gap.
    readonly property real gap: look.stack.edge + look.card.gap
    readonly property real sideInset: gap - look.stack.pad
    readonly property real topInset: gap - look.card.gap
    readonly property real bottomInset: gap - look.card.gap - look.stack.tail
    // A top stack starts below a box a bar widget draws under the bar on
    // this screen across the column's span, such as Jarvis's reply card,
    // its top gap below that box's bottom: both count from the bar's
    // bottom edge, where this layer starts (Layers.barCovers).
    readonly property real coverBottom: fromBottom || service === null || screen === null ? 0
        : service.barCovers.filter(c => c.output === screen.name && c.x < column.x + column.width && c.x + c.width > column.x)
            .reduce((low, c) => Math.max(low, c.bottom), 0)
    readonly property real stackTop: topInset + coverBottom

    ColumnLayout {
        id: column
        visible: !stack.underInbox
        x: stack.side === "left" ? stack.sideInset
            : stack.side === "right" ? stack.width - width - stack.sideInset
            : Math.round((stack.width - width) / 2)
        y: stack.fromBottom ? stack.height - height - stack.bottomInset : stack.stackTop
        // Each slot carries its own gap, scaled by its morph, so the rows
        // close up smoothly when one goes.
        spacing: 0

        CardScroll {
            id: scroll
            look: stack.look
            maxHeight: stack.height - stack.look.stack.far - (stack.fromBottom ? stack.bottomInset : stack.stackTop)
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
                    Layout.row: (stack.fromBottom ? slots.count - 1 - index : index) + (captionLoader.active && !stack.fromBottom ? 1 : 0)
                }
            }

            // The refusal toast takes the row nearest the stack's edge, and
            // the rows move one away from it. It is hidden while inactive,
            // so the grid gives it no row.
            Loader {
                id: captionLoader
                active: stack.service !== null && stack.service.refusalCaption !== ""
                visible: active
                Layout.row: stack.fromBottom ? slots.count : 0
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: stack.look.card.width
                Layout.preferredHeight: item !== null ? item.implicitHeight : 0
                sourceComponent: Component {
                    CardSlot {
                        host: stack
                        look: stack.look
                        textColumn: scroll.textColumn
                        index: 0
                        key: ""
                        app: ""
                        appIcon: ""
                        summary: ""
                        body: ""
                        image: ""
                        desktopEntry: ""
                        urgency: Logic.URGENCY.normal
                        hintAvatar: ""
                        hintIcon: ""
                        hintTone: ""
                        hintPage: ""
                        leaving: ""
                        refusal: stack.service !== null ? stack.service.refusalCaption : ""
                    }
                }
            }
        }
    }
}
